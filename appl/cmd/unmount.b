implement Unmount;

include "sys.m";
include "draw.m";

FD: import Sys;
Context: import Draw;

Unmount: module
{
	init:	fn(ctxt: ref Context, argv: list of string);
};

sys: Sys;
stderr: ref FD;

usage()
{
	sys->fprint(stderr, "Usage: unmount [source] target\n");
}

init(nil: ref Context, argv: list of string)
{
	r: int;

	sys = load Sys Sys->PATH;

	stderr = sys->fildes(2);

	argv = tl argv;

	case len argv {
	* =>
		usage();
		return;
	1 =>
		r = sys->unmount(nil, hd argv);
	2 =>
		r = sys->unmount(hd argv, hd tl argv);
	};

	if(r < 0)
		sys->fprint(stderr, "unmount: %r\n");
}
