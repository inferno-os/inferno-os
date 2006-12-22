implement Send;

include "sys.m";
include "draw.m";
include "rcxsend.m";

Send : module {
	init : fn (ctxt : ref Draw->Context, argv : list of string);
};

sys : Sys;
rcx : RcxSend;
me : int;

init(nil : ref Draw->Context, argv : list of string)
{
	sys = load Sys Sys->PATH;
	me = sys->pctl(Sys->NEWPGRP, nil);

	rcx = load RcxSend "rcxsend.dis";
	if (rcx == nil)
		error(sys->sprint("cannot load rcx module: %r"));

	argv = tl argv;
	if (len argv < 2)
		error("usage: send portnum XX...");

	portnum := int hd argv;
	argv = tl argv;

	cmd := array [len argv] of byte;
	for (i := 0; i < len cmd; i++) {
		arg := hd argv;
		argv = tl argv;
		if (arg == nil || len arg > 2)
			error(sys->sprint("bad arg %s\n", arg));
		d1, d2 : int = 0;
		d2 = hexdigit(arg[0]);
		if (len arg == 2) {
			d1 = d2;
			d2 = hexdigit(arg[1]);
		}
		if (d1 == -1 || d2 == -1)
			error(sys->sprint("bad arg %s\n", arg));
		cmd[i] = byte ((d1 << 4) + d2);
	}

	rcx->init(portnum, 1);
	reply := rcx->send(cmd, len cmd, -1);
	hexdump(reply);
	killgrp(me);
}

hexdigit(h : int) : int
{
	if (h >= '0' && h <= '9')
		return h - '0';
	if (h >= 'A' && h <= 'F')
		return 10 + h - 'A';
	if (h >= 'a' && h <= 'f')
		return 10 + h - 'a';
	return -1;
}
		
error(msg : string)
{
	sys->print("%s\n", msg);
	killgrp(me);
}

killgrp(pid : int)
{
	pctl := sys->open("/prog/" + string pid + "/ctl", Sys->OWRITE);
	if (pctl != nil) {
		poison := array of byte "killgrp";
		sys->write(pctl, poison, len poison);
	}
	exit;
}

hexdump(data : array of byte)
{
	for (i := 0; i < len data; i++)
		sys->print("%.2x ", int data[i]);
	sys->print("\n");
}
