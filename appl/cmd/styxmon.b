implement Styxmon;

include "sys.m";
	sys: Sys;
include "draw.m";
include "styx.m";
	styx: Styx;
	Tmsg, Rmsg: import styx;
include "sh.m";
include "arg.m";

Styxmon: module {
	init: fn(nil: ref Draw->Context, argv: list of string);
};

badmod(p: string)
{
	sys->fprint(sys->fildes(2), "styxmon: cannot load %s: %r\n", p);
	raise "fail:bad module";
}

showdata := 0;
init(ctxt: ref Draw->Context, argv: list of string)
{
	sys = load Sys Sys->PATH;
	styx = load Styx Styx->PATH;
	if(styx == nil)
		badmod(Styx->PATH);
	styx->init();
	arg := load Arg Arg->PATH;
	if(arg == nil)
		badmod(Arg->PATH);
	arg->init(argv);
	arg->setusage("usage: styxmon [-d] cmd [arg...]");
	while((opt := arg->opt()) != 0){
		case opt{
		'd' =>
			showdata = 1;
		* =>
			arg->usage();
		}
	}
	argv = arg->argv();
	if(argv == nil)
		arg->usage();
	fd0 := sys->fildes(0);
	fd1 := popen(ctxt, argv);
	sync := chan of int;
	spawn msgtx(fd0, fd1, sync, "tmsg");
	<-sync;
	spawn msgtx(fd1, fd0, sync, "rmsg");
	<-sync;
}

msgtx(f0, f1: ref Sys->FD, sync: chan of int, what: string)
{
	sys->pctl(Sys->NEWFD|Sys->NEWNS, 2 :: f0.fd :: f1.fd :: nil);
	sync <-= 1;
	f0 = sys->fildes(f0.fd);
	f1 = sys->fildes(f1.fd);
	stderr := sys->fildes(2);
	for (;;) {
		(d, err) := styx->readmsg(f0, 0);
		if(d == nil){
			if(err != nil)
				sys->fprint(stderr, "styxmon: error from %s: %s\n", what, err);
			else
				sys->fprint(stderr, "styxmon: eof from %s\n", what);
			exit;
		}
		if(styx->istmsg(d)){
			(n, m) := Tmsg.unpack(d);
			if(n != len d){
				sys->fprint(stderr, "styxmon: %s message error (%d/%d)\n", what, n, len d);
			}else{
				sys->fprint(stderr, "%s\n", m.text());
			}
		}else{
			(n, m) := Rmsg.unpack(d);
			if(n != len d){
				sys->fprint(stderr, "styxmon: %s message error (%d/%d)\n", what, n, len d);
				if(m != nil)
					sys->fprint(stderr, "err: %s\n", m.text());
			}else{
				sys->fprint(stderr, "%s\n", m.text());
			}
		}
		sys->write(f1, d, len d);
	}
}

popen(ctxt: ref Draw->Context, argv: list of string): ref Sys->FD
{
	sync := chan of int;
	fds := array[2] of ref Sys->FD;
	sys->pipe(fds);
	spawn runcmd(ctxt, argv, fds[0], sync);
	<-sync;
	return fds[1];
}

runcmd(ctxt: ref Draw->Context, argv: list of string, stdin: ref Sys->FD, sync: chan of int)
{
	sys->pctl(Sys->FORKFD, nil);
	sys->dup(stdin.fd, 0);
	stdin = nil;
	sync <-= 0;
	sh := load Sh Sh->PATH;
	sh->run(ctxt, argv);
}
