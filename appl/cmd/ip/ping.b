implement Ping;

include "sys.m";
	sys: Sys;

include "draw.m";

include "ip.m";
	ip: IP;
	IPaddr: import ip;

include "timers.m";
	timers: Timers;
	Timer: import timers;

include "rand.m";
	rand: Rand;

include "dial.m";
	dial: Dial;

include "arg.m";

Ping: module
{
	init:	fn(nil: ref Draw->Context, nil: list of string);
};

Icmp: adt
{
	ttl:	int;	# time to live
	src:	IPaddr;
	dst:	IPaddr;
	ptype:	int;
	code:	int;
	seq:	int;
	munged:	int;
	time:	big;

	unpack:	fn(b: array of byte): ref Icmp;
};

# packet types
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

Req: adt
{
	seq:	int;	# sequence number
	time:	big;	# time sent
	rtt:	big;
	ttl:	int;
	replied:	int;
};

debug := 0;
quiet := 0;
lostonly := 0;
lostmsgs := 0;
rcvdmsgs := 0;
sum := big 0;
firstseq := 0;
addresses := 0;

init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	rand = load Rand Rand->PATH;
	timers = load Timers Timers->PATH;
	dial = load Dial Dial->PATH;
	ip = load IP IP->PATH;
	ip->init();


	msglen := interval := 0;
	nmsg := Nmsg;

	arg := load Arg Arg->PATH;
	arg->init(args);
	arg->setusage("ip/ping [-alq] [-s msgsize] [-i millisecs] [-n #pings] destination");
	while((o := arg->opt()) != 0)
		case o {
		'l' =>
			lostonly++;
		'd' =>
			debug++;
		's' =>
			msglen = int arg->earg();
		'i' =>
			interval = int arg->earg();
		'n' =>
			nmsg = int arg->earg();
		'a' =>
			addresses = 1;
		'q' =>
			quiet = 1;
		}
	if(msglen < 32)
		msglen = 64;
	if(msglen >= 65*1024)
		msglen = 65*1024-1;
	if(interval <= 0)
		interval = Interval;

	args = arg->argv();
	if(args == nil)
		arg->usage();
	arg = nil;

	sys->pctl(Sys->NEWPGRP|Sys->FORKFD, nil);
	opentime();
	rand->init(int(nsec()/big 1000));

	addr := dial->netmkaddr(hd args, "icmp", "1");
	c := dial->dial(addr, nil);
	if(c == nil){
		sys->fprint(sys->fildes(2), "ip/ping: can't dial %s: %r\n", addr);
		raise "fail:dial";
	}

	sys->print("sending %d %d byte messages %d ms apart\n", nmsg, msglen, interval);

	done := chan of int;
	reqs := chan of ref Req;

	spawn sender(c.dfd, msglen, interval, nmsg, done, reqs);
	spid := <-done;

	pids := chan of int;
	replies := chan [8] of ref Icmp;
	spawn reader(c.dfd, msglen, replies, pids);
	rpid := <-pids;

	tpid := 0;
	timeout := chan of int;
	requests: list of ref Req;
Work:
	for(;;) alt{
	r := <-reqs =>
		requests = r :: requests;
	ic := <-replies =>
		if(ic == nil){
			rpid = 0;
			break Work;
		}
		if(ic.munged)
			sys->print("corrupted reply\n");
		if(ic.ptype != EchoReply || ic.code != 0){
			sys->print("bad type/code %d/%d seq %d\n",
				ic.ptype, ic.code, ic.seq);
			continue;
		}
		requests = clean(requests, ic);
		if(lostmsgs+rcvdmsgs == nmsg)
			break Work;
	<-done =>
		spid = 0;
		# must be at least one message outstanding; wait for it
		tpid = timers->init(Timers->Sec);
		timeout = Timer.start((nmsg-lostmsgs-rcvdmsgs)*interval+5*Timers->Sec).timeout;
	<-timeout =>
		break Work;
	}
	kill(rpid);
	kill(spid);
	kill(tpid);
	
	for(; requests != nil; requests = tl requests)
		if((hd requests).replied == 0)
			lostmsgs++;

	if(lostmsgs){
		sys->print("%d out of %d message(s) lost\n", lostmsgs, lostmsgs+rcvdmsgs);
		raise "fail:lost messages";
	}
}

kill(pid: int)
{
	if(pid)
		sys->fprint(sys->open("#p/"+string pid+"/ctl", Sys->OWRITE), "kill");
}

SECOND: con big 1000000000;	# nanoseconds
MINUTE: con big 60*SECOND;

clean(l: list of ref Req, ip: ref Icmp): list of ref Req
{
	left: list of ref Req;
	for(; l != nil; l = tl l){
		r := hd l;
		if(ip.seq == r.seq){
			r.rtt = ip.time-r.time;
			r.ttl = ip.ttl;
			reply(r, ip);
		}
		if(ip.time-r.time > MINUTE){
			r.rtt = ip.time-r.time;
			r.ttl = ip.ttl;
			if(!r.replied)
				lost(r, ip);
		}else
			left = r :: left;
	}
	return left;
}

sender(fd: ref Sys->FD, msglen: int, interval: int, n: int, done: chan of int, reqs: chan of ref Req)
{

	done <-= sys->pctl(0, nil);

	firstseq = rand->rand(65536) - n;	# -n to ensure we don't exceed 16 bits
	if(firstseq < 0)
		firstseq = 0;

	buf := array[64*1024+512] of {* => byte 0};
	for(i := Odata; i < msglen; i++)
		buf[i] = byte i;
	buf[Otype] = byte EchoRequest;
	buf[Ocode] = byte 0;

	seq := firstseq;
	for(i = 0; i < n; i++){
		if(i != 0)
			sys->sleep(interval);
		ip->put2(buf, Oseq, seq);	# order?
		r := ref Req;
		r.seq = seq;
		r.replied = 0;
		r.time = nsec();
		reqs <-= r;
		if(sys->write(fd, buf, msglen) < msglen){
			sys->fprint(sys->fildes(2), "ping: write failed: %r\n");
			break;
		}
		seq++;
	}
	done <-= 1;
}

reader(fd: ref Sys->FD, msglen: int, out: chan of ref Icmp, pid: chan of int)
{
	pid <-= sys->pctl(0, nil);
	buf := array[64*1024+512] of byte;
	while((n := sys->read(fd, buf, len buf)) > 0){
		now := nsec();
		if(n < msglen){
			sys->print("bad len %d/%d\n", n, msglen);
			continue;
		}
		ic := Icmp.unpack(buf[0:n]);
		ic.munged = 0;
		for(i := Odata; i < msglen; i++)
			if(buf[i] != byte i)
				ic.munged++;
		ic.time = now;
		out <-= ic;
	}
	sys->print("read: %r\n");
	out <-= nil;
}

reply(r: ref Req, ic: ref Icmp)
{
	rcvdmsgs++;
	r.rtt /= big 1000;
	sum += r.rtt;
	if(!quiet && !lostonly){
		if(addresses)
			sys->print("%ud: %s->%s rtt %bd µs, avg rtt %bd µs, ttl = %d\n",
				r.seq-firstseq,
				ic.src.text(), ic.dst.text(),
				r.rtt, sum/big rcvdmsgs, r.ttl);
		else
			sys->print("%ud: rtt %bd µs, avg rtt %bd µs, ttl = %d\n",
				r.seq-firstseq,
				r.rtt, sum/big rcvdmsgs, r.ttl);
	}
	r.replied = 1;	# TO DO: duplicates might be interesting
}

lost(r: ref Req, ic: ref Icmp)
{
	if(!quiet){
		if(addresses)
			sys->print("lost %ud: %s->%s avg rtt %bd µs\n",
				r.seq-firstseq,
				ic.src.text(), ic.dst.text(),
				sum/big rcvdmsgs);
		else
			sys->print("lost %ud: avg rtt %bd µs\n",
				r.seq-firstseq,
				sum/big rcvdmsgs);
	}
	lostmsgs++;
}

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
	ic := ref Icmp;
	ic.ttl = int b[Ottl];
	ic.src = IPaddr.newv4(b[Osrc:]);
	ic.dst = IPaddr.newv4(b[Odst:]);
	ic.ptype = int b[Otype];
	ic.code = int b[Ocode];
	ic.seq = ip->get2(b, Oseq);
	ic.munged = 0;
	ic.time = big 0;
	return ic;
}

timefd: ref Sys->FD;

opentime()
{
	timefd = sys->open("/dev/time", Sys->OREAD);
	if(timefd == nil){
		sys->fprint(sys->fildes(2), "ping: can't open /dev/time: %r\n");
		raise "fail:no time";
	}
}

nsec(): big
{
	buf := array[64] of byte;
	n := sys->pread(timefd, buf, len buf, big 0);
	if(n <= 0)
		return big 0;
	return big string buf[0:n] * big 1000;
}
