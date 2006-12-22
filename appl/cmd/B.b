implement B;

include "sys.m";
include "draw.m";
include "workdir.m";

FD: import Sys;
Context: import Draw;

B: module
{
	init:	fn(nil: ref Context, argv: list of string);
};

sys: Sys;
stderr: ref FD;
wkdir: string;

init(nil: ref Context, argv: list of string)
{
	sys = load Sys Sys->PATH;
	stderr = sys->fildes(2);

	if(len argv < 2) {
		sys->fprint(stderr, "Usage: B file ...\n");
		return;
	}
	argv = tl argv;

	cmd := "exec B ";
	while(argv != nil) {
		f := hd argv;
		if(len f > 0 && f[0] != '/' && f[0] != '-')
			f = wd() + f;
		cmd += "/usr/inferno"+f;
		argv = tl argv;
		if(argv != nil)
			cmd += " ";
	}			
	cfd := sys->open("/cmd/clone", sys->ORDWR);
	if(cfd == nil) {
		sys->fprint(stderr, "B: open /cmd/clone: %r\n");
		return;
	}
	
	buf := array[32] of byte;
	n := sys->read(cfd, buf, len buf);
	if(n <= 0) {
		sys->fprint(stderr, "B: read /cmd/#/ctl: %r\n");
		return;
	}
	dir := "/cmd/"+string buf[0:n];

	# Start the Command
	n = sys->fprint(cfd, "%s", cmd);
	if(n <= 0) {
		sys->fprint(stderr, "B: exec: %r\n");
		return;
	}

	io := sys->open(dir+"/data", sys->ORDWR);
	if(io == nil) {
		sys->fprint(stderr, "B: open /cmd/#/data: %r\n");
		return;
	}

	sys->pctl(sys->NEWPGRP, nil);
	copy(io, sys->fildes(1), nil);
}

wd(): string
{
	if(wkdir != nil)
		return wkdir;

	gwd := load Workdir Workdir->PATH;

	wkdir = gwd->init();
	if(wkdir == nil) {
		sys->fprint(stderr, "B: can't get working dir: %r");
		exit;
	}
	wkdir = wkdir+"/";
	return wkdir;
}

copy(f, t: ref FD, c: chan of int)
{
	if(c != nil)
		c <-= sys->pctl(0, nil);

	buf := array[8192] of byte;
	for(;;) {
		r := sys->read(f, buf, len buf);
		if(r <= 0)
			break;
		w := sys->write(t, buf, r);
		if(w != r)
			break;
	}
}

kill(pid: int)
{
	fd := sys->open("/prog/"+string pid+"/ctl", sys->OWRITE);
	sys->fprint(fd, "kill");
}
