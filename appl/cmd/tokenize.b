implement Tokenize;

include "sys.m";
	sys: Sys;

include "draw.m";

Tokenize: module
{
	init:	fn(nil: ref Draw->Context, nil: list of string);
};

stderr: ref Sys->FD;

usage()
{
	  sys->fprint(stderr, "Usage: tokenize string delimiters\n");
	  raise "fail: usage";
}

init(nil: ref Draw->Context, args : list of string)
{
	sys = load Sys Sys->PATH;
	stderr = sys->fildes(2);

	if(args != nil)
		args = tl args;
	if(len args != 2)
		usage();
	(nil, l) := sys->tokenize(hd args, hd tl args);
	for(; l != nil; l = tl l)
		sys->print("%s\n", hd l);
}
