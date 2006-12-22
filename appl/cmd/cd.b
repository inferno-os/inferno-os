implement Cd;

include "sys.m";
	sys: Sys;

include "draw.m";

Cd: module
{
	init:	fn(ctxt: ref Draw->Context, argv: list of string);
};

stderr: ref Sys->FD;

init(nil: ref Draw->Context, argv: list of string)
{
	sys = load Sys Sys->PATH;

	stderr = sys->fildes(2);

	argv = tl argv;
	if(argv == nil)
		argv = "/usr/"+user() :: nil;

	if(tl argv != nil) {
		sys->fprint(stderr, "Usage: cd [directory]\n");
		raise "fail:usage";
	}

	if(sys->chdir(hd argv) < 0) {
		sys->fprint(stderr, "cd: %s: %r\n", hd argv);
		raise "fail:failed";
	}
}

user(): string
{
	fd := sys->open("/dev/user", sys->OREAD);
	if(fd == nil)
		return "inferno";

	buf := array[Sys->NAMEMAX] of byte;
	n := sys->read(fd, buf, len buf);
	if(n <= 0)
		return "inferno";

	return string buf[0:n];
}
