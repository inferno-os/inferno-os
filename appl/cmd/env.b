implement Envcmd;

#
# Copyright © 2000 Vita Nuova Limited.  All rights reserved.
#

include "sys.m";
	sys: Sys;

include "draw.m";

include "env.m";

include "readdir.m";

Envcmd: module
{
	init: fn(nil: ref Draw->Context, argv: list of string);
};

init(nil: ref Draw->Context, argv: list of string)
{
	sys = load Sys Sys->PATH;
	stdout := sys->fildes(1);
	if (tl argv != nil) {
		sys->fprint(stderr(), "Usage: env\n");
		raise "fail:usage";
	}
	env := load Env Env->PATH;
	if(env == nil)
		error(sys->sprint("can't load %s: %r", Env->PATH));
	readdir := load Readdir Readdir->PATH;
	if(readdir == nil)
		error(sys->sprint("can't load %s: %r", Readdir->PATH));
	(a, n) := readdir->init("/env",
			Readdir->NONE | Readdir->COMPACT | Readdir->DESCENDING);
	for(i := 0; i < len a; i++){
		s := a[i].name+"="+env->getenv(a[i].name)+"\n";
		b := array of byte s;
		sys->write(stdout, b, len b);
	}
}

error(s: string)
{
	sys->fprint(stderr(), "env: %s\n", s);
	raise "fail:error";
}

stderr(): ref Sys->FD
{
	return sys->fildes(2);
}
