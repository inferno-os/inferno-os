implement Palmsrv;

#
# serve up a Palm using SLP and PADP
#
# Copyright © 2003 Vita Nuova Holdings Limited.  All rights reserved.
#
# forsyth@vitanuova.com
#
# TO DO
#	USB and possibly other transports
#	tickle

include "sys.m";
	sys: Sys;

include "draw.m";

include "timers.m";
	timers: Timers;
	Timer, Sec: import timers;

include "palm.m";

include "arg.m";

Palmsrv: module
{
	init:	fn(nil: ref Draw->Context, nil: list of string);
};

debug := 0;

usage()
{
	sys->fprint(sys->fildes(2), "usage: palm/palmsrv [-d /dev/eia0] [-s 57600]\n");
	raise "fail:usage";
}

init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	sys->pctl(Sys->NEWPGRP|Sys->FORKFD, nil);

	device, speed: string;

	arg := load Arg Arg->PATH;
	if(arg == nil)
		error(sys->sprint("can't load %s: %r", Arg->PATH));
	arg->init(args);
	while((c := arg->opt()) != 0)
		case c {
		'D' =>
			debug++;
		'd' =>
			device = arg->arg();
		's' =>
			speed = arg->arg();
		* =>
			usage();
		}
	args = arg->argv();
	arg = nil;

	if(device == nil)
		device = "/dev/eia0";
	if(speed == nil)
		speed = "57600";

	dfd := sys->open(device, Sys->ORDWR);
	if(dfd == nil)
		error(sys->sprint("can't open %s: %r", device));
	cfd := sys->open(device+"ctl", Sys->OWRITE);

	timers = load Timers Timers->PATH;
	if(timers == nil)
		error(sys->sprint("can't load %s: %r", Timers->PATH));
	srvio := sys->file2chan("/chan", "palmsrv");
	if(srvio == nil)
		error(sys->sprint("can't create channel /chan/palmsrv: %r"));
	timers->init(Sec/100);
	p := Pchan.init(dfd, cfd);
	spawn server(srvio, p);
}

error(s: string)
{
	sys->fprint(sys->fildes(2), "palmsrv: %s\n", s);
	raise "fail:error";
}

Xact: adt
{
	fid:	int;
	reply:	array of byte;
	error:	string;
};

server(srv: ref Sys->FileIO, p: ref Pchan)
{
	actions: list of ref Xact;
	nuser := 0;
	for(;;)alt{
	(nil, nbytes, fid, rc) := <-srv.read =>
		if(rc == nil){
			actions = delact(actions, fid);
			break;
		}
		act := findact(actions, fid);
		if(act == nil){
			rc <-= (nil, "no transaction in progress");
			break;
		}
		actions = delact(actions, fid);
		if(p.shutdown)
			rc <-= (nil, "link shut down");
		else if(act.error != nil)
			rc <-= (nil, act.error);
		else if(act.reply != nil)
			rc <-= (act.reply, nil);
		else
			rc <-= (nil, "no reply");	# probably shouldn't happen

	(nil, data, fid, wc) := <-srv.write =>
		actions = delact(actions, fid);	# discard result of any previous transaction
		if(wc == nil){
			if(--nuser <= 0){
				nuser = 0;
				p.stop();
			}
			break;
		}
		if(len data == 4 && string data == "exit"){
			p.close();
			wc <-= (len data, nil);
			exit;
		}
		if(p.shutdown){
			wc <-= (0, "link shut down");	# must close then reopen
			break;
		}
		if(!p.started){
			err := p.start();
			if(err != nil){
				wc <-= (0, sys->sprint("can't start protocol: %s", err));
				break;
			}
			nuser++;
		}
		(result, err) := p.padp_xchg(data, 20*1000);
		if(err != nil){
			wc <-= (0, err);
			break;
		}
		actions = ref Xact(fid, result, err) :: actions;
		wc <-= (len data, nil);
	}
}

findact(l: list of ref Xact, fid: int): ref Xact
{
	for(; l != nil; l = tl l)
		if((a := hd l).fid == fid)
			return a;
	return nil;
}

delact(l: list of ref Xact, fid: int): list of ref Xact
{
	ol := l;
	l = nil;
	for(; ol != nil; ol = tl ol)
		if((a := hd ol).fid != fid)
			l = a :: l;
	return l;
}

killpid(pid: int)
{
	if(pid != 0){
		fd := sys->open("/prog/"+string pid+"/ctl", sys->OWRITE);
		if(fd != nil)
			sys->fprint(fd, "kill");
	}
}

#
# protocol implementation
#	Serial Link Protocol (framing)
#	Connection Management Protocol (wakeup, negotiation)
#	Packet Assembly/Disassembly Protocol (reliable delivery fragmented datagram)
#

DATALIM: con 1024;

# SLP packet types
SLP_System, SLP_Unused, SLP_PAD, SLP_Loop: con iota;

# SLP block content, without framing
Sblock: adt {
	src:	int;	# socket ID
	dst:	int;	# socket ID
	proto:	int;	# packet type
	xid:	int;	# transaction ID
	data:	array of byte;

	new:	fn(): ref Sblock;
	print:	fn(sb: self ref Sblock, dir: string);
};

#
# Palm channel
#
Pchan: adt {
	started:	int;
	shutdown:	int;

	protocol:	int;
	lport:	byte;
	rport:	byte;

	fd:	ref Sys->FD;
	cfd:	ref Sys->FD;
	baud:	int;

	rpid:	int;
	lastid:	int;
	rd:	chan of ref Sblock;
	reply:	ref Sblock;	# data replacing lost ack

	init:	fn(dfd: ref Sys->FD, cfd: ref Sys->FD): ref Pchan;
	start:	fn(p: self ref Pchan): string;
	stop:	fn(p: self ref Pchan);
	close:	fn(p: self ref Pchan): int;
	slp_read:	fn(p: self ref Pchan, nil: int): (ref Sblock, string);
	slp_write:	fn(p: self ref Pchan, xid: int, nil: array of byte): string;

	setbaud:	fn(p: self ref Pchan, nil: int);

	padp_read:	fn(p: self ref Pchan, xid: int, timeout: int): (array of byte, string);
	padp_write:	fn(p: self ref Pchan, msg: array of byte, xid: int): string;
	padp_xchg:	fn(p: self ref Pchan, msg: array of byte, timeout: int): (array of byte, string);
	tickle:	fn(p: self ref Pchan);

	connect:	fn(p: self ref Pchan): string;
	accept:	fn(p: self ref Pchan, baud: int): string;

	nextseq:	fn(p: self ref Pchan): int;
};

Pchan.init(dfd: ref Sys->FD, cfd: ref Sys->FD): ref Pchan
{
	p := ref Pchan;
	p.fd = dfd;
	p.cfd = cfd;
	p.baud = InitBaud;
	p.protocol = SLP_PAD;
	p.rport = byte 3;
	p.lport = byte 3;
	p.rd = chan of ref Sblock;
	p.lastid = 0;
	p.rpid = 0;
	p.started = 0;
	p.shutdown = 0;
	return p;
}

Pchan.start(p: self ref Pchan): string
{
	if(p.started)
		return nil;
	p.shutdown = 0;
	p.baud = InitBaud;
	p.reply = nil;
	ctl(p, "f");
	ctl(p, "d1");
	ctl(p, "r1");
	ctl(p, "i8");
	ctl(p, "q8192");
	ctl(p, sys->sprint("b%d", InitBaud));
	pidc := chan of int;
	spawn slp_recv(p, pidc);
	p.started = 1;
	p.rpid = <-pidc;
	err := p.accept(57600);
	if(err != nil)
		p.stop();
	return err;
}

ctl(p: ref Pchan, s: string)
{
	if(p.cfd != nil)
		sys->fprint(p.cfd, "%s", s);
}

Pchan.setbaud(p: self ref Pchan, baud: int)
{
	if(p.baud != baud){
		p.baud = baud;
		ctl(p, sys->sprint("b%d", baud));
		sys->sleep(200);
	}
}

Pchan.stop(p: self ref Pchan)
{
	p.shutdown = 0;
	if(!p.started)
		return;
	killpid(p.rpid);
	p.rpid = 0;
	p.reply = nil;
#	ctl(p, "f");
#	ctl(p, "d0");
#	ctl(p, "r0");
#	ctl(p, sys->sprint("b%d", InitBaud));
	p.started = 0;
}
	
Pchan.close(p: self ref Pchan): int
{
	if(p.started)
		p.stop();
	p.reply = nil;
	p.cfd = nil;
	p.fd = nil;
	timers->shutdown();
	return 0;
}

# CMP protocol for connection management
#	See include/Core/System/CMCommon.h, Palm SDK
# There are two major versions: the original V1, still always used in wakeup messsages;
# and V2, which is completely different (similar structure to Desklink) and used by newer devices, but the headers
# are the same length.  Start off in V1 announcing version 2.x, then switch to that.
# My device supports only V1, so I use that.

CMPHDRLEN: con 10;	# V1: type[1] flags[1] vermajor[1] verminor[1] mbz[2] baud[4]
					# V2: type[1] cmd[1] error[2] argc[1] mbz[1] mbz[4]

# CMP V1
Cmajor:	con 1;
Cminor:	con 2;

InitBaud: con 9600;

# type
Cwake, Cinit, Cabort, Cextended: con 1+iota;

# Cinit flags
ChangeBaud: con 16r80;
RcvTimeout1: con 16r40;	# tell Palm to set receive timeout to 1 minute (CMP v1.1)
RcvTimeout2:	con 16r20;	# tell Palm to set receive timeout to 2 minutes (v1.1)

# Cinit and Cwake flag
LongPacketEnable:	con 16r10;	# enable long packet support (v1.2)

# Cabort flags
WrongVersion:	con 16r80;	# incompatible com versions

# CMP V2
Carg1:		con Palm->ArgIDbase;
Cresponse:	con 16r80;
Cxchgprefs, Chandshake:	con 16r10+iota;

Pchan.connect(p: self ref Pchan): string
{
	(nil, e1) := cmp_write(p, Cwake, 0, Cmajor, Cminor, 57600);
	if(e1 != nil)
		return e1;
	(op, flag, nil, nil, baud, e2) := cmp_read(p, 0);
	if(e2 != nil)
		return e2;
	case op {
	Cinit=>
		if(flag & ChangeBaud)
			p.setbaud(baud);
		return nil;

	Cabort=>
		return "Palm rejected connect";

	* =>
		return sys->sprint("Palm connect: reply %d", op);
	}
	return nil;
}

Pchan.accept(p: self ref Pchan, maxbaud: int): string
{
	(op, nil, major, minor, baud, err) := cmp_read(p, 0);
	if(err != nil)
		return err;
	if(major != 1){
		sys->fprint(sys->fildes(2), "palmsrv: comm version mismatch: %d.%d\n", major, minor);
		cmp_write(p, Cabort, WrongVersion, Cmajor, 0, 0);
		return sys->sprint("comm version mismatch: %d.%d", major, minor);
	}
	if(baud > maxbaud)
		baud = maxbaud;
	flag := 0;
	if(baud != InitBaud)
		flag = ChangeBaud;
	(nil, err) = cmp_write(p, Cinit, flag, Cmajor, Cminor, baud);
	if(err != nil)
		return err;
	p.setbaud(baud);
	return nil;
}

cmp_write(p: ref Pchan, op: int, flag: int, major: int, minor: int, baud: int): (int, string)
{
	cmpbuf := array[CMPHDRLEN] of byte;
	cmpbuf[0] = byte op;
	cmpbuf[1] = byte flag;
	cmpbuf[2] = byte major;
	cmpbuf[3] = byte minor;
	cmpbuf[4] = byte 0;
	cmpbuf[5] = byte 0;
	put4(cmpbuf[6:], baud);

	if(op == Cwake)
		return (16rFF, p.padp_write(cmpbuf, 16rFF));
	xid := p.nextseq();
	return (xid, p.padp_write(cmpbuf, xid));
}

cmp_read(p: ref Pchan, xid: int): (int, int, int, int, int, string)
{
	(c, err) := p.padp_read(xid, 20*Sec);
	if(err != nil)
		return (0, 0, 0, 0, 0, err);
	if(len c != CMPHDRLEN)
		return (0, 0, 0, 0, 0, "CMP: bad response");
	return (int c[0], int c[1], int c[2], int c[3], get4(c[6:]), nil);
}

#
# Palm PADP protocol
#	``The Packet Assembly/Disassembly Protocol'' in
#	Developing Palm OS Communications, US Robotics, 1996, pp. 53-68.
#
# forsyth@caldo.demon.co.uk, 1997
#

FIRST: con 16r80;
LAST: con 16r40;
MEMERROR: con 16r20;

# packet types
Pdata: con 1;
Pack: con 2;
Ptickle: con 4;
Pabort: con 8;

PADPHDRLEN: con 4;	# type[1] flags[1] size[2]

RetryInterval: con 4*Sec;
MaxRetries: con 14; # they say 14 `seconds', but later state they might need 20 for heap mgmt, so i'll assume 14 attempts (at 4sec ea)

Pchan.padp_xchg(p: self ref Pchan, msg: array of byte, timeout: int): (array of byte, string)
{
	xid := p.nextseq();
	err := p.padp_write(msg, xid);
	if(err != nil)
		return (nil, err);
	return p.padp_read(xid, timeout);
}

#
# PADP header
#	type[1] flags[2] size[2], high byte first for size
#
# max block size is 2^16-1
# must ack within 2 seconds
# wait at most 10 seconds for next chunk
# 10 retries
#

Pchan.padp_write(p: self ref Pchan, buf: array of byte, xid: int): string
{
	count := len buf;
	if(count >= 1<<16)
		return "padp: write too big";
	p.reply = nil;
	flags := FIRST;
	mem := buf[0:];
	offset := 0;
	while(count > 0){
		n := count;
		if(n > DATALIM)
			n = DATALIM;
		else
			flags |= LAST;
		ob := array[PADPHDRLEN+n] of byte;
		ob[0] = byte Pdata;
		ob[1] = byte flags;
		l: int;
		if(flags & FIRST)
			l = count;	# total size in first segment
		else
			l = offset;	# offset in rest
		put2(ob[2:], l);
		ob[PADPHDRLEN:] = mem[0:n];
		if(debug)
			padp_dump(ob, "Tx");
		p.slp_write(xid, ob);
		retries := 0;
		for(;;){
			(ib, nil) := p.slp_read(RetryInterval);
			if(ib == nil){
				sys->print("padp write: ack timeout\n");
				retries++;
				if(retries > MaxRetries){
					# USR says not to give up if (flags&LAST)!=0; giving up seems safer
					sys->print("padp write: give up\n");
					return "PADP: no response";
				}
				p.slp_write(xid, ob);
				continue;
			}
			if(ib.proto != SLP_PAD || len ib.data < PADPHDRLEN || ib.xid != xid && ib.xid != 16rFF){
				sys->print("padp write: ack wrong type(%d) or xid(%d,%d), or len %d\n", ib.proto, ib.xid, xid, len ib.data);
				continue;
			}
			if(ib.xid == 16rFF){	# connection management
				if(int ib.data[0] == Ptickle)
					continue;
				if(int ib.data[0] == Pabort){
					sys->print("padp write: device abort\n");
					p.shutdown = 1;
					return "device cancelled operation";
				}
			}
			if(int ib.data[0] != Pack){
				if(int ib.data[0] == Ptickle)
					continue;
				# right transaction ... if it's acceptable data, USR says to save it & treat as ack
				sys->print("padp write: type %d, not ack\n", int ib.data[0]);
				if(int ib.data[0] == Pdata && flags & LAST && int ib.data[1] & FIRST){
					p.reply = ib;
					break;
				}
				continue;
			}
			if(int ib.data[1] & MEMERROR)
				return "padp: pilot out of memory";
			if((flags&(FIRST|LAST)) != (int ib.data[1]&(FIRST|LAST)) ||
			    get2(ib.data[2:]) != get2(ob[2:])){
				sys->print("padp write: ack, wrong flags (#%x,#%x) or offset (%d,%d)\n", int ib.data[1], flags, get2(ib.data[2:]), get2(ob[2:]));
				continue;
			}
			if(debug)
				sys->print("padp write: ack %d %d\n", xid, get2(ob[2:]));
			break;
		}
		mem = mem[n:];
		count -= n;
		offset += n;
		flags &= ~FIRST;
	}
	return nil;
}

Pchan.padp_read(p: self ref Pchan,  xid, timeout: int): (array of byte, string)
{
	buf, mem: array of byte;

	offset := 0;
	ready := 0;
	retries := 0;
	ack := array[PADPHDRLEN] of byte;
	for(;;){
		b := p.reply;
		if(b == nil){
			err: string;
			(b, err) = p.slp_read(timeout);
			if(b == nil){
				sys->print("padp read: timeout %d\n", retries);
				if(++retries <= 5)
					continue;
				sys->print("padp read: gave up\n");
				return (nil, err);
			}
			retries = 0;
		} else
			p.reply = nil;
		if(debug)
			padp_dump(b.data, "Rx");
 		if(len b.data < PADPHDRLEN){
			sys->print("padp read: length\n");
			continue;
		}
		if(b.proto != SLP_PAD){
			sys->print("padp read: bad proto (%d)\n", b.proto);
			continue;
		}
		if(int b.data[0] == Pabort && b.xid == 16rFF){
			p.shutdown = 1;
			return (nil, "device cancelled transaction");
		}
		if(int b.data[0] != Pdata || xid != 0 && b.xid != xid){
			sys->print("padp read mismatch: type (%d) or xid(%d::%d)\n", int b.data[0], b.xid, xid);
			continue;
		}
		f := int b.data[1];
		o := get2(b.data[2:]);
		if(f & FIRST){
			buf = array[o] of byte;
			ready = 1;
			offset = 0;
			o = 0;
			mem = buf;
			timeout = 4*Sec;
		}
		if(!ready || o != offset){
			sys->print("padp read: offset %d, expected %d\n", o, offset);
			continue;
		}
		n := len b.data - PADPHDRLEN;
		if(n > len mem){
			sys->print("padp read: record too long (%d/%d)\n", n, len mem);
			# it's probably fatal, but retrying does no harm
			continue;
		}
		mem[0:] = b.data[PADPHDRLEN:PADPHDRLEN+n];
		mem = mem[n:];
		offset += n;
		ack[0:] = b.data[0:PADPHDRLEN];
		ack[0] = byte Pack;
		p.slp_write(xid, ack);
		if(f & LAST)
			break;
	}
	if(offset != len buf)
		return (buf[0:offset], nil);
	return (buf, nil);
}

Pchan.nextseq(p: self ref Pchan): int
{
	n := p.lastid + 1;
	if(n >= 16rFF)
		n = 1;
	p.lastid = n;
	return n;
}

Pchan.tickle(p: self ref Pchan)
{
	xid := p.nextseq();
	data := array[PADPHDRLEN] of byte;
	data[0] = byte Ptickle;
	data[1] = byte (FIRST|LAST);
	put2(data[2:], 0);
	if(debug)
		sys->print("PADP: tickle\n");
	p.slp_write(xid, data);
}

padp_dump(data: array of byte, dir: string)
{
	stype: string;

	case int data[0] {
	Pdata =>	stype = "Data";
	Pack =>	stype = "Ack";
	Ptickle =>	stype = "Tickle";
	Pabort =>	stype = "Abort";
	* =>	stype = sys->sprint("#%x", int data[0]);
	}

	sys->print("PADP %s %s flags=#%x len=%d\n", stype, dir, int data[1], get2(data[2:]));

	if(debug > 1 && (data[0] != byte Pack || len data > 4)){
		data = data[4:];
		for(i := 0; i < len data;){
			sys->print(" %.2x", int data[i]);
			if(++i%16 == 0)
				sys->print("\n");
		}
		sys->print("\n");
	}
}

#
# Palm's Serial Link Protocol
#	See include/Core/System/SerialLinkMgr.h in Palm SDK
# 	and the description in the USR document mentioned above.
#

SLPHDRLEN: con 10;		# BE[1] EF[1] ED[1] dest[1] src[1] type[1] size[2] xid[1] check[1] body[size] crc[2]
SLP_MTU: con SLPHDRLEN+PADPHDRLEN+DATALIM;

Sblock.new(): ref Sblock
{
	return ref Sblock(0, 0, 0, 16rFF, nil);
}

#
# format and write an SLP frame
#
Pchan.slp_write(p: self ref Pchan, xid: int, b: array of byte): string
{
	d := array[SLPHDRLEN] of byte;
	cb := array[2] of byte;

	nb := len b;
	d[0] = byte 16rBE;
	d[1] = byte 16rEF;
	d[2] = byte 16rED;
	d[3] = byte p.rport;
	d[4] = byte p.lport;
	d[5] = byte p.protocol;
	d[6] = byte (nb >> 8);
	d[7] = byte (nb & 16rFF);
	d[8] = byte xid;
	d[9] = byte 0;
	n := 0;
	for(i:=0; i<len d; i++)
		n += int d[i];
	d[9] = byte (n & 16rFF);
	if(debug)
		printbytes(d, "SLP Tx hdr");
	crc := crc16(d, 0);
	put2(cb, crc16(b, crc));

	if(sys->write(p.fd, d, SLPHDRLEN) != SLPHDRLEN ||
	   sys->write(p.fd, b, nb) != len b ||
	   sys->write(p.fd, cb, 2) != 2)
		return sys->sprint("%r");
	return nil;
}

Pchan.slp_read(p: self ref Pchan, timeout: int): (ref Sblock, string)
{
	clock := Timer.start(timeout);
	alt {
	<-clock.timeout =>
		if(debug)
			sys->print("SLP: timeout\n");
		return (nil, "SLP: timeout");
	b := <-p.rd =>
		clock.stop();
		return (b, nil);
	}
}

slp_recv(p: ref Pchan, pidc: chan of int)
{
	n: int;

	pidc <-= sys->pctl(0, nil);
	buf := array[2*SLP_MTU] of byte;
	sb := Sblock.new();
	rd := wr := 0;
Work:
	for(;;){

		if(wr != rd){
			# data already in buffer might start a new frame
			if(rd != 0){
				buf[0:] = buf[rd:wr];
				wr -= rd;
				rd = 0;
			}
		}else
			rd = wr = 0;

		# header
		while(wr < SLPHDRLEN){
			n = sys->read(p.fd, buf[wr:], SLPHDRLEN-wr);
			if(n <= 0)
				break Work;
			wr += n;
		}
#		{for(i:=0; i<wr;i++)sys->print("%.2x", int buf[i]);sys->print("\n");}
		if(buf[0] != byte 16rBE || buf[1] != byte 16rEF || buf[2] != byte 16rED){
			rd++;
			continue;
		}
		if(debug)
			printbytes(buf[0:wr], "SLP Rx hdr");
		n = 0;
		for(i:=0; i<SLPHDRLEN-1; i++)
			n += int buf[i];
		if((n & 16rFF) != int buf[9]){
			rd += 3;
			continue;
		}
		hdr := buf[0:SLPHDRLEN];
		sb.dst = int hdr[3];
		sb.src = int hdr[4];
		sb.proto = int hdr[5];
		size := (int hdr[6]<<8) | int hdr[7];
		sb.xid = int hdr[8];
		sb.data = array[size] of byte;
		crc := crc16(hdr, 0);
		rd += SLPHDRLEN;
		if(rd == wr)
			rd = wr = 0;

		# data and CRC
		while(wr-rd < size+2){
			n = sys->read(p.fd, buf[wr:], size+2-(wr-rd));
			if(n <= 0)
				break Work;
			wr += n;
		}
		crc = crc16(buf[rd:rd+size], crc);
		if(crc != get2(buf[rd+size:])){
			if(debug)
				sys->print("CRC error: local=#%.4ux pilot=#%.4ux\n", crc, get2(buf[rd+size:]));
			for(; rd < wr && buf[rd] != byte 16rBE; rd++)
				;	# hunt for next header
			continue;
		}
		if(sb.proto != SLP_Loop){
			sb.data[0:] = buf[rd:rd+size];
			if(debug)
				sb.print("Rx");
			rd += size+2;
			p.rd <-= sb;
			sb = Sblock.new();
		} else {
			# should we reflect these?
			if(debug)
				sb.print("Loop");
			rd += size+2;
		}
	}
	p.rd <-= nil;
}

Sblock.print(b: self ref Sblock, dir: string)
{
	sys->print("SLP %s %d->%d len=%d proto=%d xid=#%.2x\n",
			dir, int b.src, int b.dst, len b.data, int b.proto, int b.xid);
}

printbytes(d: array of byte, what: string)
{
	buf := sys->sprint("%s[", what);
	for(i:=0; i<len d; i++)
		buf += sys->sprint(" #%.2x", int d[i]);
	buf += "]";
	sys->print("%s\n", buf);
}

get4(p: array of byte): int
{
	return (int p[0]<<24) | (int p[1]<<16) | (int p[2]<<8) | int p[3];
}

get3(p: array of byte): int
{
	return (int p[1]<<16) | (int p[2]<<8) | int p[3];
}

get2(p: array of byte): int
{
	return (int p[0]<<8) | int p[1];
}

put4(p: array of byte, v: int)
{
	p[0] = byte (v>>24);
	p[1] = byte (v>>16);
	p[2] = byte (v>>8);
	p[3] = byte (v & 16rFF);
}

put3(p: array of byte, v: int)
{
	p[0] = byte (v>>16);
	p[1] = byte (v>>8);
	p[2] = byte (v & 16rFF);
}

put2(p: array of byte, v: int)
{
	p[0] = byte (v>>8);
	p[1] = byte (v & 16rFF);
}

# this will be done by table look up;
# polynomial is xⁱ⁶+xⁱ⁲+x⁵+1

crc16(buf: array of byte, crc: int): int
{
	for(j := 0; j < len buf; j++){
		crc = crc ^ (int buf[j]) << 8;
		for(i := 0; i < 8; i++)
			if(crc & 16r8000)
				crc = (crc << 1) ^ 16r1021;
			else
				crc = crc << 1;
	}
	return crc & 16rffff;
}
