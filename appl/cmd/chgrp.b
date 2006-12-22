implement Chgrp;

include "sys.m";
	sys: Sys;

include "draw.m";

include "arg.m";

Chgrp: module
{
	init:	fn(nil: ref Draw->Context, nil: list of string);
};

usage()
{
	sys->fprint(sys->fildes(2), "usage: chgrp [-uo] group file ...\n");
	raise "fail:usage";
}

init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;

	arg := load Arg Arg->PATH;
	if(arg == nil){
		sys->fprint(sys->fildes(2), "chgrp: can't load %s: %r\n", Arg->PATH);
		raise "fail:load";
	}
	setuser := 0;
	arg->init(args);
	while((o := arg->opt()) != 0)
		case o {
		'o' or 'u' =>
			setuser = 1;
		* =>
			usage();
		}
	args = arg->argv();
	arg = nil;
	if(args == nil)
		usage();
	id := hd args;
	err := 0;
	while((args = tl args) != nil){
		d := sys->nulldir;
		if(setuser)
			d.uid = id;
		else
			d.gid = id;
		if(sys->wstat(hd args, d) < 0){
			sys->fprint(sys->fildes(2), "chgrp: can't change %s: %r\n", hd args);
			err = 1;
		}
	}
	if(err)
		raise "fail:error";
}
