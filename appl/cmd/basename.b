implement Basename;

include "sys.m";
	sys: Sys;

include "draw.m";

include "names.m";
	names: Names;

include "arg.m";

Basename: module
{
	init:	fn(nil: ref Draw->Context, nil: list of string);
};

init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	names = load Names Names->PATH;
	arg := load Arg Arg->PATH;

	dirname := 0;
	arg->init(args);
	arg->setusage("basename [-d] string [suffix]");
	while((o := arg->opt()) != 0)
		case o {
		'd' =>
			dirname = 1;
		* =>
			arg->usage();
		}
	args = arg->argv();
	if(args == nil || tl args != nil && (dirname || tl tl args != nil))
		arg->usage();
	arg = nil;

	if(dirname){
		s := names->dirname(hd args);
		if(s == nil)
			s = ".";
		sys->print("%s\n", s);
		exit;
	}
	suffix: string;
	if(tl args != nil)
		suffix = hd tl args;
	sys->print("%s\n", names->basename(hd args, suffix));
}
