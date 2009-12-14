implement Mangaload;

# to do:
#	- set arp entry based on /lib/ndb if necessary

include "sys.m";
	sys: Sys;

include "draw.m";

include "ip.m";
	ip: IP;
	IPaddr: import ip;

include "timers.m";
	timers: Timers;
	Timer: import timers;

include "dial.m";
	dial: Dial;

include "arg.m";

Mangaload: module
{
	init:	fn(nil: ref Draw->Context, nil: list of string);
};

# manga parameters
FlashBlocksize: con 16r10000;
FlashSize: con 16r400000;	# 4meg for now
FlashUserArea: con 16r3C0000;

# magic values
FooterOffset: con 16rFFEC;
FooterSig: con 16rA0FFFF9F;	# ARM flash library
FileInfosize: con 64;
FileNamesize: con FileInfosize - 3*4;	# x, y, z
Packetdatasize: con 1500-28;	# ether data less IP + ICMP header
RequestTimeout: con 500;
Probecount: con 10;	# query unit every so many packets

# manga uses extended TFTP ops in ICMP InfoRequest packets
Tftp_Req: con 0;
Tftp_Read: con 1;
Tftp_Write: con 2;
Tftp_Data: con 3;
Tftp_Ack: con 4;
Tftp_Error: con 5;
Tftp_Last: con 6;

Icmp: adt
{
	ttl:	int;	# time to live
	src:	IPaddr;
	dst:	IPaddr;
	ptype:	int;
	code:	int;
	id:	int;
	seq:	int;
	data:	array of byte;
	munged:	int;	# packet received but corrupt

	unpack:	fn(b: array of byte): ref Icmp;
};

# ICMP packet types
EchoReply: con 0;
Unreachable: con 3;
SrcQuench: con 4;
EchoRequest: con 8;
TimeExceed: con 11;
Timestamp: con 13;
TimestampReply: con 14;
InfoRequest: con 15;
InfoReply: con 16;

Nmsg: con 32;
Interval: con 1000;	# ms

debug := 0;
flashblock := 1;	# never 0, that's the boot firmware
maxfilesize := 8*FlashBlocksize;
flashlim := FlashSize/FlashBlocksize;
loadinitrd := 0;
maxlen := 512*1024;
mypid := 0;
Datablocksize: con 4096;

init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	timers = load Timers Timers->PATH;
	dial = load Dial Dial->PATH;
	ip = load IP IP->PATH;
	ip->init();


	arg := load Arg Arg->PATH;
	arg->init(args);
	arg->setusage("mangaload [-48dr] destination file");
	while((o := arg->opt()) != 0)
		case o {
		'4' =>
			flashlim = 4*1024*1024/FlashBlocksize;
		'8' =>
			flashlim = 8*1024*1024/FlashBlocksize;
		'r' =>
			loadinitrd = 1;
			flashblock = 9;
			if(flashlim > 4*1024*1024/FlashBlocksize)
				maxfilesize = 113*FlashBlocksize;
			else
				maxfilesize = 50*FlashBlocksize;
		'd' =>
			debug++;
		}
	args = arg->argv();
	if(len args != 2)
		arg->usage();
	arg = nil;

	sys->pctl(Sys->NEWPGRP|Sys->FORKFD, nil);

	filename := hd tl args;
	fd := sys->open(filename, Sys->OREAD);
	if(fd == nil){
		sys->fprint(sys->fildes(2), "mangaload: can't open %s: %r\n", filename);
		raise "fail:open";
	}
	(ok, d) := sys->fstat(fd);
	if(ok < 0){
		sys->fprint(sys->fildes(2), "mangaload: can't stat %s: %r\n", filename);
		raise "fail:stat";
	}
	if(d.length > big maxfilesize){
		sys->fprint(sys->fildes(2), "mangaload: file %s too long (must not exceed %d bytes)\n",
			filename, maxfilesize);
		raise "fail:size";
	}
	filesize := int d.length;

	port := sys->sprint("%d", 16r8695);
	addr := dial->netmkaddr(hd args, "icmp", port);
	c := dial->dial(addr, port);
	if(c == nil){
		sys->fprint(sys->fildes(2), "mangaload: can't dial %s: %r\n", addr);
		raise "fail:dial";
	}
	
	tpid := timers->init(20);

	pids := chan of int;
	replies := chan [2] of ref Icmp;
	spawn reader(c.dfd, replies, pids);
	rpid := <-pids;

	flashoffset := flashblock * FlashBlocksize;

	# file name first
	bname := array of byte filename;
	l := len bname;
	buf := array[Packetdatasize] of byte;
	ip->put4(buf, 0, filesize);
	ip->put4(buf, 4, l);
	buf[8:] = bname;
	l += 2*4;
	buf[l++] = byte 0;
	ip->put4(buf, l, flashoffset);
	l += 4;
	{
		if(send(c.dfd, buf[0:l], Tftp_Write, 0) < 0)
			senderr();
		(op, iseq, data) := recv(replies, 400);
		sys->print("initial reply: %d %d\n", op, iseq);
		if(op != Tftp_Ack){
			why := "no response";
			if(op == Tftp_Error)
				why = "manga cannot receive file";
			sys->fprint(sys->fildes(2), "mangaload: %s\n", why);
			raise "fail:error";
		}
		sys->print("sending %s size %d at address %d (0x%x)\n", filename, filesize, flashoffset, flashoffset);
		seq := 1;
		nsent := 0;
		last := 0;
		while((n := sys->read(fd, buf, len buf)) >= 0 && !last){
			last = n != len buf;
		  Retry:
			for(;;){
				if(++nsent%10 == 0){	# probe
					o = Tftp_Req;
					send(c.dfd, array[0] of byte, Tftp_Req, seq);
					(op, iseq, data) = recv(replies, 500);
					if(debug || op != Tftp_Ack)
						sys->print("ack reply: %d %d\n", op, iseq);
					if(op == Tftp_Last || op == Tftp_Error){
						if(op == Tftp_Last)
							sys->print("timed out\n");
						else
							sys->print("error reply\n");
						raise "disaster";
					}
					if(debug)
						sys->print("ok\n");
					continue Retry;
				}
				send(c.dfd, buf[0:n], Tftp_Data, seq);
				(op, iseq, data) = recv(replies, 40);
				case op {
				Tftp_Error =>
					sys->fprint(sys->fildes(2), "mangaload: manga refused data\n");
					raise "disaster";
				Tftp_Ack =>
					if(seq == iseq){
						seq++;
						break Retry;
					}
					sys->print("sequence error: rcvd %d expected %d\n", iseq, seq);
					if(iseq > seq){
						sys->print("unrecoverable sequence error\n");
						send(c.dfd, array[0] of byte, Tftp_Data, ++seq);	# stop manga
						raise "disaster";
					}
					# resend
					sys->seek(fd, -big ((seq-iseq)*len buf), 1);
					seq = iseq;
				Tftp_Last =>
					seq++;
					break Retry;	# timeout ok: manga doesn't usually reply unless packet lost
				}
			}
		}
	}exception{
	* =>
		;
	}
	kill(rpid);
	kill(tpid);
	sys->print("ok?\n");
}

kill(pid: int)
{
	if(pid)
		sys->fprint(sys->open("#p/"+string pid+"/ctl", Sys->OWRITE), "kill");
}

senderr()
{
	sys->fprint(sys->fildes(2), "mangaload: icmp write failed: %r\n");
	raise "disaster";
}

send(fd: ref Sys->FD, data: array of byte, op: int, seq: int): int
{
	buf := array[64*1024+512] of {* => byte 0};
	buf[Odata:] = data;
	ip->put2(buf, Oseq, seq);
	buf[Otype] = byte InfoRequest;
	buf[Ocode] = byte op;
	if(sys->write(fd, buf, Odata+len data) < Odata+len data)
		return -1;
	if(debug)
		sys->print("sent op=%d seq=%d ld=%d\n", op, seq, len data);
	return 0;
}

flush(input: chan of ref Icmp)
{
	for(;;)alt{
	<-input =>
		;
	* =>
		return;
	}
}

recv(input: chan of ref Icmp, msec: int): (int, int, array of byte)
{
	t := Timer.start(msec);
	alt{
	<-t.timeout =>
		return (Tftp_Last, 0, nil);
	ic := <-input =>
		t.stop();
		if(ic.ptype == InfoReply)
			return (ic.code, ic.seq, ic.data);
		return (Tftp_Last, 0, nil);
	}
}

reader(fd: ref Sys->FD, out: chan of ref Icmp, pid: chan of int)
{
	pid <-= sys->pctl(0, nil);
	for(;;){
		buf := array[64*1024+512] of byte;
		n := sys->read(fd, buf, len buf);
		if(n <= 0){
			if(n == 0)
				sys->werrstr("unexpected eof");
			break;
		}
		ic := Icmp.unpack(buf[0:n]);
		if(ic != nil){
			if(debug)
				sys->print("recv type=%d op=%d seq=%d id=%d\n", ic.ptype, ic.code, ic.seq, ic.id);
			out <-= ic;
		}else
			sys->fprint(sys->fildes(2), "mangaload: corrupt icmp packet rcvd\n");
	}
	sys->print("read: %r\n");
	out <-= nil;
}

# IP and ICMP packet header
Ovihl: con 0;
Otos: con 1;
Olength: con 2;
Oid: con Olength+2;
Ofrag: con Oid+2;
Ottl: con Ofrag+2;
Oproto: con Ottl+1;
Oipcksum: con Oproto+1;
Osrc: con Oipcksum+2;
Odst: con Osrc+4;
Otype: con Odst+4;
Ocode: con Otype+1;
Ocksum: con Ocode+1;
Oicmpid: con Ocksum+2;
Oseq: con Oicmpid+2;
Odata: con Oseq+2;

Icmp.unpack(b: array of byte): ref Icmp
{
	if(len b < Odata)
		return nil;
	ic := ref Icmp;
	ic.ttl = int b[Ottl];
	ic.src = IPaddr.newv4(b[Osrc:]);
	ic.dst = IPaddr.newv4(b[Odst:]);
	ic.ptype = int b[Otype];
	ic.code = int b[Ocode];
	ic.seq = ip->get2(b, Oseq);
	ic.id = ip->get2(b, Oicmpid);
	ic.munged = 0;
	if(len b > Odata)
		ic.data = b[Odata:];
	return ic;
}
