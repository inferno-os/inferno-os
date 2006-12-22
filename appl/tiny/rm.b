implement Rm;

include "sys.m";
	sys: Sys;
include "draw.m";

Rm: module
{
	init:	fn(ctxt: ref Draw->Context, argv: list of string);
};

init(nil: ref Draw->Context, argv: list of string)
{
	sys = load Sys Sys->PATH;
	stderr := sys->fildes(2);

	argv = tl argv;
	while(argv != nil) {
		if(sys->remove(hd argv) < 0)
			sys->fprint(stderr, "rm: %s: %r\n", hd argv);
		argv = tl argv;
	}
}
