implement Time;

include "sys.m";
include "draw.m";
include "sh.m";

FD: import Sys;
Context: import Draw;

Time: module
{
	init:	fn(ctxt: ref Context, argv: list of string);
};

sys: Sys;
stderr, waitfd: ref FD;

init(ctxt: ref Context, argv: list of string)
{
	sys = load Sys Sys->PATH;

	stderr = sys->fildes(2);

	waitfd = sys->open("#p/"+string sys->pctl(0, nil)+"/wait", sys->OREAD);
	if(waitfd == nil){
		sys->fprint(stderr, "time: open wait: %r\n");
		return;
	}

	argv = tl argv;

	if(argv == nil) {
		sys->fprint(stderr, "usage: time cmd ...\n");
		return;
	}

	file := hd argv;

	if(len file<4 || file[len file-4:]!=".dis")
		file += ".dis";

	t0 := sys->millisec();

	c := load Command file;
	if(c == nil) {
		err := sys->sprint("%r");
		if(1){
			c = load Command "/dis/"+file;
			if(c == nil)
				err = sys->sprint("%r");
		}
		if(c == nil) {
			sys->fprint(stderr, "time: %s: %s\n", hd argv, err);
			return;
		}
	}

	t1 := sys->millisec();

	pidc := chan of int;

	spawn cmd(ctxt, c, pidc, argv);
	waitfor(<-pidc);

	t2 := sys->millisec();

	f1 := real (t1 - t0) /1000.;
	f2 := real (t2 - t1) /1000.;
	sys->fprint(stderr, "%.4gl %.4gr %.4gt\n", f1, f2, f1+f2);
}

cmd(ctxt: ref Context, c: Command, pidc: chan of int, argv: list of string)
{
	pidc <-= sys->pctl(0, nil);
	c->init(ctxt, argv);
}

waitfor(pid: int)
{
	buf := array[sys->WAITLEN] of byte;
	status := "";
	for(;;){
		n := sys->read(waitfd, buf, len buf);
		if(n < 0) {
			sys->fprint(stderr, "sh: read wait: %r\n");
			return;
		}
		status = string buf[0:n];
		if(status[len status-1] != ':')
			sys->fprint(stderr, "%s\n", status);
		who := int status;
		if(who != 0) {
			if(who == pid)
				return;
		}
	}
}
