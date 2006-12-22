implement Telnet;

include "sys.m";
	sys: Sys;
	Connection: import sys;

include "draw.m";
	draw: Draw;
	Context: import draw;

Telnet: module
{
	init:	fn(ctxt: ref Draw->Context, args: list of string);
};

Debug: con 0;

Inbuf: adt {
	fd:	ref Sys->FD;
	out:	ref Outbuf;
	buf:	array of byte;
	ptr:	int;
	nbyte:	int;
};

Outbuf: adt {
	buf:	array of byte;
	ptr:	int;
};

BS:		con 8;		# ^h backspace character
BSW:		con 23;		# ^w bacspace word
BSL:		con 21;		# ^u backspace line
EOT:		con 4;		# ^d end of file
ESC:		con 27;		# hold mode

net:	Connection;
stdin, stdout, stderr: ref Sys->FD;

# control characters
Se:			con 240;	# end subnegotiation
NOP:			con 241;
Mark:		con 242;	# data mark
Break:		con 243;
Interrupt:		con 244;
Abort:		con 245;	# TENEX ^O
AreYouThere:	con 246;
Erasechar:	con 247;	# erase last character
Eraseline:		con 248;	# erase line
GoAhead:		con 249;	# half duplex clear to send
Sb:			con 250;	# start subnegotiation
Will:			con 251;
Wont:		con 252;
Do:			con 253;
Dont:		con 254;
Iac:			con 255;

# options
Binary, Echo, SGA, Stat, Timing,
Det, Term, EOR, Uid, Outmark,
Ttyloc, M3270, Padx3, Window, Speed,
Flow, Line, Xloc, Extend: con iota;

Opt: adt
{
	name:	string;
	code:	int;
	noway:	int;	
	remote:	int;		# remote value
	local:	int;		# local value
};

opt := array[] of
{
	Binary =>		Opt("binary",			0,	0,	0, 	0),
	Echo	=>		Opt("echo",			1,  	0, 	0,	0),
	SGA	=>		Opt("suppress go ahead",	3,  	0, 	0,	0),
	Stat =>		Opt("status",			5,  	1, 	0,	0),
	Timing =>		Opt("timing",			6,  	1, 	0,	0),
	Det=>		Opt("det",				20, 	1, 	0,	0),
	Term =>		Opt("terminal",			24, 	0, 	0,	0),
	EOR =>		Opt("end of record",		25, 	1, 	0,	0),
	Uid =>		Opt("uid",				26, 	1, 	0,	0),
	Outmark => 	Opt("outmark",			27, 	1, 	0,	0),
	Ttyloc =>		Opt("ttyloc",			28, 	1, 	0,	0),
	M3270 =>		Opt("3270 mode",		29, 	1, 	0,	0),
	Padx3 =>		Opt("pad x.3",			30, 	1, 	0,	0),
	Window =>	Opt("window size",		31, 	1, 	0,	0),
	Speed =>		Opt("speed",			32, 	1, 	0,	0),
	Flow	=>		Opt("flow control",		33, 	1, 	0,	0),
	Line	=>		Opt("line mode",		34, 	1, 	0,	0),
	Xloc	=>		Opt("X display loc",		35, 	1, 	0,	0),
	Extend =>		Opt("Extended",		255,	1, 	0,	0),
};

usage()
{
	sys->fprint(stderr, "usage: telnet host [port]\n");
	raise "fail:usage";
}

init(nil: ref Context, argv: list of string)
{
	sys = load Sys Sys->PATH;
	stderr = sys->fildes(2);
	stdout = sys->fildes(1);
	stdin = sys->fildes(0);

	if (len argv < 2)
		usage();
	argv = tl argv;
	host := hd argv;
	argv = tl argv;
	port := "23";
	if(argv != nil)
		port = hd argv;
	connect(host, port);
}

ccfd: ref Sys->FD;
connect(addr: string, port: string)
{
	ok: int;
	(ok, net) = sys->dial(netmkaddr(addr, "tcp", port), nil);
	if(ok < 0) {
		sys->fprint(stderr, "telnet: %r\n");
		return;
	}
	sys->fprint(stderr, "telnet: connected to %s\n", addr);

	raw(1);
	pidch := chan of int;
	finished := chan of int;
	spawn fromnet(pidch, finished);
	spawn fromuser(pidch, finished);
	pids := array[2] of {* => <-pidch};
	kill(pids[<-finished == pids[0]]);
	raw(0);
}


fromuser(pidch, finished: chan of int)
{
	pidch <-= sys->pctl(0, nil);
	b := array[1024] of byte;
	while((n := sys->read(stdin, b, len b)) > 0) {
		if (opt[Echo].remote == 0)
			sys->write(stdout, b, n);
		sys->write(net.dfd, b, n);
	}
	sys->fprint(stderr, "telnet: error reading stdin: %r\n");
	finished <-= sys->pctl(0, nil);
}

getc(b: ref Inbuf): int
{
	if(b.nbyte == 0) {
		if(b.out != nil)
			flushout(b.out);
		b.nbyte = sys->read(b.fd, b.buf, len b.buf);
		if(b.nbyte <= 0)
			return -1;
		b.ptr = 0;
	}
	b.nbyte--;
	return int b.buf[b.ptr++];
}

putc(b: ref Outbuf, c: int)
{
	b.buf[b.ptr++] = byte c;
	if(b.ptr == len b.buf)
		flushout(b);
}

flushout(b: ref Outbuf)
{
	sys->write(stdout, b.buf, b.ptr);
	b.ptr = 0;
}

BUFSIZE: con 2048;
fromnet(pidch, finished: chan of int)
{
	pidch <-= sys->pctl(0, nil);
	conout := ref Outbuf(array[BUFSIZE] of byte, 0);
	netinp := ref Inbuf(net.dfd, conout, array[BUFSIZE] of byte, 0, 0);

loop:	for(;;) {
		c := getc(netinp);	
		case c {
		-1 =>
			break loop;
		Iac  =>
			c = getc(netinp);
			if(c != Iac) {
				flushout(conout);
				if(control(netinp, c) < 0)
					break loop;
			} else
				putc(conout, c);
		* =>
			putc(conout, c);
		}
	}
	sys->fprint(stderr, "telnet: remote host closed connection\n");
	finished <-= sys->pctl(0, nil);
}

control(bp: ref Inbuf, c: int): int
{
	r := 0;
	case c {
	AreYouThere =>
		sys->fprint(net.dfd, "Inferno telnet\r\n");
	Sb =>
		r = sub(bp);
	Will =>
		r = will(bp);
	Wont =>
		r = wont(bp);
	Do =>
		r = doit(bp);
	Dont =>
		r = dont(bp);
	Se =>
		sys->fprint(stderr, "telnet: SE without an SB\n");
	-1 =>
		r = -1;
	}

	return r;
}

sub(bp: ref Inbuf): int
{
	subneg: string;
	i := 0;
	for(;;){
		c := getc(bp);
		if(c == Iac) {
			c = getc(bp);
			if(c == Se)
				break;
			subneg[i++] = Iac;
		}
		if(c < 0)
			return -1;
		subneg[i++] = c;
	}
	if(i == 0)
		return 0;

	if (Debug)
		sys->fprint(stderr, "telnet: sub(%s, %d, n = %d)\n", optname(subneg[0]), subneg[1], i);

	for(i = 0; i < len opt; i++)
		if(opt[i].code == subneg[0])
			break;

	if(i >= len opt)
		return 0;

	case i {
	Term =>
		sbsend(opt[Term].code, array of byte "network");	
	}

	return 0;
}

sbsend(code: int, data: array of byte): int
{
	buf := array[4+len data+2] of byte;
	o := 4+len data;

	buf[0] = byte Iac;
	buf[1] = byte Sb;
	buf[2] = byte code;
	buf[3] = byte 0;
	buf[4:] = data;
	buf[o] = byte Iac;
	o++;
	buf[o] = byte Se;

	return sys->write(net.dfd, buf, len buf);
}

will(bp: ref Inbuf): int
{
	c := getc(bp);
	if(c < 0)
		return -1;

	if (Debug)
		sys->fprint(stderr, "telnet: will(%s)\n", optname(c));

	for(i := 0; i < len opt; i++)
		if(opt[i].code == c)
			break;

	if(i >= len opt) {
		send3(bp, Iac, Dont, c);
		return 0;
	}

	rv := 0;
	if(opt[i].noway)
		send3(bp, Iac, Dont, c);
	else
	if(opt[i].remote == 0)
		rv |= send3(bp, Iac, Do, c);

	if(opt[i].remote == 0)
		rv |= change(bp, i, Will);
	opt[i].remote = 1;
	return rv;
}

wont(bp: ref Inbuf): int
{
	c := getc(bp);
	if(c < 0)
		return -1;

	if (Debug)
		sys->fprint(stderr, "telnet: wont(%s)\n", optname(c));

	for(i := 0; i < len opt; i++)
		if(opt[i].code == c)
			break;

	if(i >= len opt)
		return 0;

	rv := 0;
	if(opt[i].remote) {
		rv |= change(bp, i, Wont);
		rv |= send3(bp, Iac, Dont, c);
	}
	opt[i].remote = 0;
	return rv;
}

doit(bp: ref Inbuf): int
{
	c := getc(bp);
	if(c < 0)
		return -1;

	if (Debug)
		sys->fprint(stderr, "telnet: do(%s)\n", optname(c));

	for(i := 0; i < len opt; i++)
		if(opt[i].code == c)
			break;

	if(i >= len opt || opt[i].noway) {
		send3(bp, Iac, Wont, c);
		return 0;
	}
	rv := 0;
	if(opt[i].local == 0) {
		rv |= change(bp, i, Do);
		rv |= send3(bp, Iac, Will, c);
	}
	opt[i].local = 1;
	return rv;
}

dont(bp: ref Inbuf): int
{
	c := getc(bp);
	if(c < 0)
		return -1;

	if (Debug)
		sys->fprint(stderr, "telnet: dont(%s)\n", optname(c));

	for(i := 0; i < len opt; i++)
		if(opt[i].code == c)
			break;

	if(i >= len opt || opt[i].noway)
		return 0;

	rv := 0;
	if(opt[i].local){
		opt[i].local = 0;
		rv |= change(bp, i, Dont);
		rv |= send3(bp, Iac, Wont, c);
	}
	opt[i].local = 0;
	return rv;
}

change(bp: ref Inbuf, o: int, what: int): int
{
	if(bp != nil)
		{}
	if(o != 0)
		{}
	if(what != 0)
		{}
	return 0;
}

send3(bp: ref Inbuf, c0: int, c1: int, c2: int): int
{
	if (Debug)
		sys->fprint(stderr, "telnet: reply(%s(%s))\n", negname(c1), optname(c2));
		
	buf := array[3] of byte;

	buf[0] = byte c0;
	buf[1] = byte c1;
	buf[2] = byte c2;

	if (sys->write(bp.fd, buf, 3) != 3)
		return -1;
	return 0;
}

kill(pid: int): int
{
	fd := sys->open("/prog/"+string pid+"/ctl", Sys->OWRITE);
	if (fd == nil)
		return -1;
	if (sys->write(fd, array of byte "kill", 4) != 4)
		return -1;
	return 0;
}

negname(c: int): string
{
	t := "Unknown";
	case c {
	Will =>	t = "will";
	Wont =>	t = "wont";
	Do =>	t = "do";
	Dont =>	t = "dont";
	}
	return t;
}

optname(c: int): string
{
	for (i := 0; i < len opt; i++)
		if (opt[i].code == c)
			return opt[i].name;
	return "unknown";
}

raw(on: int)
{
	if(ccfd == nil) {
		ccfd = sys->open("/dev/consctl", Sys->OWRITE);
		if(ccfd == nil) {
			sys->fprint(stderr, "telnet: cannot open /dev/consctl: %r\n");
			return;
		}
	}
	if(on)
		sys->fprint(ccfd, "rawon");
	else
		sys->fprint(ccfd, "rawoff");
}

netmkaddr(addr, net, svc: string): string
{
	if(net == nil)
		net = "net";
	(n, l) := sys->tokenize(addr, "!");
	if(n <= 1){
		if(svc== nil)
			return sys->sprint("%s!%s", net, addr);
		return sys->sprint("%s!%s!%s", net, addr, svc);
	}
	if(svc == nil || n > 2)
		return addr;
	return sys->sprint("%s!%s", addr, svc);
}
