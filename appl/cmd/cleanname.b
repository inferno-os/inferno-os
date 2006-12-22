implement Cleanname;

include "sys.m";
	sys: Sys;

include "draw.m";

include "names.m";
	names: Names;

include "arg.m";

Cleanname: module
{
	init:	fn(nil: ref Draw->Context, nil: list of string);
};

init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	names = load Names Names->PATH;
	arg := load Arg Arg->PATH;

	dir: string;
	arg->init(args);
	arg->setusage("cleanname [-d pwd] name ...");
	while((o := arg->opt()) != 0)
		case o {
		'd' =>
			dir = arg->earg();
		* =>
			arg->usage();
		}
	args = arg->argv();
	if(args == nil)
		arg->usage();
	arg = nil;

	for(; args != nil; args = tl args){
		n := hd args;
		if(dir != nil && n != nil && n[0] != '/' && n[0] != '#')
			n = dir+"/"+n;
		sys->print("%s\n", names->cleanname(n));	# %q?
	}
}
