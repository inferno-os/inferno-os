implement Joinsession;
include "sys.m";
	sys: Sys;
include "draw.m";
include "sh.m";
include "arg.m";
include "joinsession.m";

usage()
{
	sys->fprint(stderr(), "usage: joinsession [-d mntdir] [-j joinrequest] name\n");
	raise "fail:usage";
}

CLIENTDIR: con "/dis/spree/clients";

init(ctxt: ref Draw->Context, argv: list of string)
{
	sys = load Sys Sys->PATH;
	arg := load Arg Arg->PATH;
	arg->init(argv);
	mnt := "/n/remote";
	joinmsg := "join";
	while ((opt := arg->opt()) != 0) {
		case opt {
		'd' =>
			if ((mnt = arg->arg()) == nil)
				usage();
		'j' =>
			joinmsg = arg->arg();
		* =>
			usage();
		}
	}
	argv = arg->argv();
	if (len argv != 1)
		usage();
	arg = nil;
	e := join(ctxt, mnt, hd argv, joinmsg);
	if (e != nil) {
		sys->fprint(stderr(), "startclient: %s\n", e);
		raise "fail:error";
	}
}

join(ctxt: ref Draw->Context, mnt: string, dir: string, joinmsg: string): string
{
	if (sys == nil)
		sys = load Sys Sys->PATH;

	fd := sys->open(mnt + "/" + dir + "/ctl", Sys->ORDWR);
	if (fd == nil)
		return sys->sprint("cannot open %s: %r", mnt + "/" + dir + "/ctl");
	if (joinmsg != nil)
		if (sys->fprint(fd, "%s", joinmsg) == -1)
			return sys->sprint("cannot join: %r");

	buf := array[Sys->ATOMICIO] of byte;
	while ((n := sys->read(fd, buf, len buf)) > 0) {
		(nil, lines) := sys->tokenize(string buf[0:n], "\n");
		for (; lines != nil; lines = tl lines) {
			(nil, toks) := sys->tokenize(hd lines, " ");
			if (len toks > 1 && hd toks == "clienttype") {
				sync := chan of string;
				spawn startclient(ctxt, hd tl toks :: mnt :: dir :: tl tl toks, fd, sync);
				fd = nil;
				return <-sync;
			}
			sys->fprint(stderr(), "startclient: unknown lobby message %s\n", hd lines);
		}
	}
	return "premature EOF";
}

startclient(ctxt: ref Draw->Context, argv: list of string, fd: ref Sys->FD, sync: chan of string)
{
	sys->pctl(Sys->FORKNS|Sys->FORKFD|Sys->NEWPGRP, nil);
	sys->dup(fd.fd, 0);
	fd = nil;
	sys->pctl(Sys->NEWFD, 0 :: 1 :: 2 :: nil);

	# XXX security: weed out slashes
	path := CLIENTDIR + "/" + hd argv + ".dis";
	mod := load Command path;
	if (mod == nil) {
		sync <-= sys->sprint("cannot load %s: %r\n", path);
		return;
	}
	spawn clientmod(mod, ctxt, argv);
	sync <-= nil;
}

clientmod(mod: Command, ctxt: ref Draw->Context, argv: list of string)
{
	wfd := sys->open("/prog/" + string sys->pctl(0, nil) + "/wait", Sys->OREAD);
	spawn mod->init(ctxt, argv);
	buf := array[Sys->ATOMICIO] of byte;
	n := sys->read(wfd, buf, len buf);
	sys->print("client process (%s) exited: %s\n", concat(argv), string buf[0:n]);
}

concat(l: list of string): string
{
	if (l == nil)
		return nil;
	s := hd l;
	for (l = tl l; l != nil; l = tl l)
		s += " " + hd l;
	return s;
}

stderr(): ref Sys->FD
{
	return sys->fildes(2);
}
