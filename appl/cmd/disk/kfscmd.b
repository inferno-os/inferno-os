implement Kfscmd;

include "sys.m";
	sys:	Sys;

include "draw.m";
include "arg.m";

Kfscmd: module
{
	init:	fn(nil: ref Draw->Context, nil: list of string);
};

init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;

	arg := load Arg Arg->PATH;
	if (arg == nil)
		err(sys->sprint("can't load %s: %r", Arg->PATH));

	cfs := "main";
	arg->init(args);
	arg->setusage("disk/kfscmd [-n fsname] cmd ...");
	while((c := arg->opt()) != 0)
		case c {
		'n' =>
			cfs = arg->earg();
		* =>
			arg->usage();
		}
	args = arg->argv();
	arg = nil;

	ctlf := "/chan/kfs."+cfs+".cmd";
	ctl := sys->open(ctlf, Sys->ORDWR);
	if(ctl == nil)
		err(sys->sprint("can't open %s: %r", ctlf));
	for(; args != nil; args = tl args){
		if(sys->fprint(ctl, "%s", hd args) > 0){
			buf := array[1024] of byte;
			while((n := sys->read(ctl, buf, len buf)) > 0)
				sys->write(sys->fildes(1), buf, n);
		}else
			err(sys->sprint("%q: %r", hd args));
	}
}

err(s: string)
{
	sys->fprint(sys->fildes(2), "kfscmd: %s\n", s);
	raise "fail:error";
}
