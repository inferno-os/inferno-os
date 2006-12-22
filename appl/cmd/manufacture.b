implement Manufacture;

include "sys.m";
FD, Dir: import Sys;
sys: Sys;

include "draw.m";
draw: Draw;
Context, Display, Font, Screen, Image, Point, Rect: import draw;

Manufacture: module
{
	init:	fn(ctxt: ref Context, argv: list of string);
};

stderr: ref FD;

init(nil: ref Context, argv: list of string)
{
	s: string;
	argv0: string;

	argv0 = hd argv;
	argv = tl argv;
	sys = load Sys Sys->PATH;

	stderr = sys->fildes(2);

	fd := sys->create("/nvfs/ID", sys->OWRITE, 8r666);
	if(fd == nil){
		sys->fprint(stderr, "manufacture: can't create /nvfs/ID: %r\n");
		return;
	}

	while(argv != nil) {
		s = hd argv;
		sys->fprint(fd, "%s", s);
		argv = tl argv;
		if(argv != nil)
			sys->fprint(fd, " ");
	}
}
