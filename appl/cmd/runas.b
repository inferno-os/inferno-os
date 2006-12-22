implement Runas;

include "sys.m";
include "draw.m";
include "sh.m";

sys: Sys;
sh: Sh;

Context: import sh;

Runas: module {
	init: fn(nil: ref Draw->Context, argv: list of string);
};

init(drawctxt: ref Draw->Context, argv: list of string)
{
	sys = load Sys Sys->PATH;
	sh = load Sh Sh->PATH;
	if (sh == nil)
		badmodule(Sh->PATH);

	if (len argv < 3)
		usage();

	argv = tl argv;
	user := hd argv;
	argv = tl argv;

	fd := sys->open("/dev/user", Sys->OWRITE);
	if (fd == nil)
		error(sys->sprint("cannot open /dev/user: %r"));
	u := array of byte user;
	if (sys->write(fd, u, len u) != len u)
		error(sys->sprint("cannot set user: %r"));
	sh->run(drawctxt, argv);
}

badmodule(p: string)
{
	sys->fprint(stderr(), "runas: cannot load %s: %r\n", p);
	raise "fail:bad module";
}

stderr(): ref Sys->FD
{
	return sys->fildes(2);
}

usage()
{
	sys->fprint(stderr(), "usage: runas user cmd [args...]\n");
	raise "fail:usage";
}

error(e: string)
{
	sys->fprint(stderr(), "runas: %s\n", e);
	raise "fail:error";
}