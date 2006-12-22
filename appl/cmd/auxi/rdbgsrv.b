implement RDbgSrv;

include "sys.m";
	sys: Sys;
include "draw.m";

include "styx.m";
	styx: Styx;
	Rmsg, Tmsg: import styx;

include "arg.m";
	arg: Arg;

RDbgSrv: module
{
	init: fn(nil: ref Draw->Context, argv: list of string);
};

debug:=	0;
dev:=	"/dev/eia0";
speed:=	38400;
progname: string;
rpid := 0;
wpid := 0;

usage()
{
	sys->fprint(stderr(), "Usage: rdbgsrv [-d n] [-s speed] [-f dev] mountpoint\n");
	raise "fail: usage";
}

init(nil: ref Draw->Context, av: list of string)
{
	sys = load Sys Sys->PATH;
	if(sys == nil)
		return;
	styx = load Styx Styx->PATH;
	if(styx == nil){
		sys->fprint(stderr(), "rdbgsrv: can't load %s; %r\n", Styx->PATH);
		raise "fail:load";
	}
	arg = load Arg Arg->PATH;
	if(arg == nil){
		sys->fprint(stderr(), "rdbgsrv: can't load %s: %r\n", Arg->PATH);
		raise "fail:load";
	}

	arg->init(av);
	progname = arg->progname();
	while(o := arg->opt())
		case o {
		'd' =>
			d := arg->arg();
			if(d == nil)
				usage();
			debug = int d;
		's' =>
			s := arg->arg();
			if(s == nil)
				usage();
			speed = int s;
		'f' =>
			s := arg->arg();
			if(s == nil)
				usage();
			dev = s;
		'h' =>
			usage();
		}

	mtpt := arg->arg();
	if(mtpt == nil)
		usage();

	ctl := dev + "ctl";
	cfd := sys->open(ctl, Sys->OWRITE);
	if(cfd == nil){
		sys->fprint(stderr(), "%s: can't open %s: %r\n", progname, ctl);
		raise "fail: open eia\n";
	}

	sys->fprint(cfd, "b%d", speed);
	sys->fprint(cfd, "l8");
	sys->fprint(cfd, "pn");
	sys->fprint(cfd, "s1");

	(rfd, wfd) := start(dev);
	if(rfd == nil){
		sys->fprint(stderr(), "%s: failed to start protocol\n", progname);
		raise "fail:proto start";
	}

	fds := array[2] of ref Sys->FD;

	if(sys->pipe(fds) == -1){
		sys->fprint(stderr(), "%s: pipe: %r\n", progname);
		raise "fail:no pipe";
	}

	if(debug)
		sys->fprint(stderr(), "%s: starting server\n", progname);

	rc := chan of int;
	spawn copymsg(fds[1], wfd, "->", rc);
	rpid = <-rc;
	spawn copymsg(rfd, fds[1], "<-", rc);
	wpid = <-rc;

	if(sys->mount(fds[0], nil, mtpt, Sys->MREPL, nil) == -1) {
		fds[1] = nil;
		sys->fprint(stderr(), "%s: can't mount on %s: %r\n", progname, mtpt);
		quit("mount");
	}
}

stderr(): ref Sys->FD
{
	return sys->fildes(2);
}

killpid(pid: int)
{
	fd := sys->open("#p/"+string pid+"/ctl", sys->OWRITE);
	if(fd != nil)
		sys->fprint(fd, "kill");
}

quit(err: string)
{
	killpid(rpid);
	killpid(wpid);
	if(err != nil)
		raise "fail:"+err;
	exit;
}

start(name:string): (ref Sys->FD, ref Sys->FD)
{
	rfd := sys->open(name, Sys->OREAD);
	wfd := sys->open(name, Sys->OWRITE);
	if(rfd == nil || wfd == nil)
			return (nil, nil);
	if(sys->fprint(wfd, "go") < 0)
		return (nil, nil);
	c := array[1] of byte;
	state := 0;
	for(;;) {
		if(sys->read(rfd, c, 1) != 1)
			return (nil, nil);
		if(state == 0 && c[0] == byte 'o')
			state = 1;
		else if(state == 1 && c[0] == byte 'k')
			break;
		else
			state = 0;
	}
	return (rfd, wfd);
}

copymsg(f: ref Sys->FD, t: ref Sys->FD, dir: string, pidc: chan of int)
{
	pidc <-= sys->pctl(0, nil);
	
	{
		for(;;) {
			(msg, err) := styx->readmsg(f, 0);
			if(msg == nil){
				sys->fprint(stderr(), "%s: %s: read error: %s\n", progname, dir, err);
				quit("error");
			}
			if(debug &1)
				trace(dir, msg);
			if(debug & 2)
				dump(dir, msg, len msg);
			if(sys->write(t, msg, len msg) != len msg){
				sys->fprint(stderr(), "%s: %s: write error: %r\n", progname, dir);
				quit("error");
			}
		}
	}exception e{
	"*" =>
		sys->print("%s: %s: %s: exiting\n", progname, dir, e);
		quit("exception");
	}
}

trace(sourcept: string,  op: array of byte ) 
{
	if(styx->istmsg(op)){
		(nil, m) := Tmsg.unpack(op);
		if(m != nil)
			sys->print("%s: %s\n", sourcept, m.text());
		else
			sys->print("%s: unknown\n", sourcept);
	}else{
		(nil, m) := Rmsg.unpack(op);
		if(m != nil)
			sys->print("%s: %s\n", sourcept, m.text());
		else
			sys->print("%s: unknown\n", sourcept);
	}
}

dump(msg: string, buf: array of byte, n: int)
{
	sys->print("%s: [%d bytes]: ", msg, n);
	s := "";
	for(i:=0;i<n;i++) {
		if((i % 20) == 0) {
			sys->print(" %s\n", s);
			s = "";
		}
		sys->print("%2.2x ", int buf[i]);
		if(int buf[i] >= 32 && int buf[i] < 127)
			s[len s] = int buf[i];
		else
			s += ".";
	}
	for(i %= 20; i < 20; i++)
		sys->print("   ");
	sys->print(" %s\n\n", s);
}
