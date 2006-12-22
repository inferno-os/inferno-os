implement Bind;

include "sys.m";
	sys: Sys;

include "draw.m";

Bind: module
{
	init:	fn(ctxt: ref Draw->Context, args: list of string);
};

stderr: ref Sys->FD;

usage()
{
	sys->fprint(stderr, "usage: bind [-a|-b|-c|-ac|-bc] [-q] source target\n");
	raise "fail:usage";
}

init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;

	stderr = sys->fildes(2);
	flags := 0;
	qflag := 0;
	if(args != nil)
		args = tl args;
	while(args != nil && (a := hd args) != "" && a[0] == '-'){
		args = tl args;
		if(a == "--")
			break;
		for(o := 1; o < len a; o++)
			case a[o] {
			'a' =>
				flags |= Sys->MAFTER;
			'b' =>
				flags |= Sys->MBEFORE;
			'c' =>
				flags |= Sys->MCREATE;
			'q' =>
				qflag = 1;
			* =>
				usage();
			}
	}
	if(len args != 2 || flags&Sys->MAFTER && flags&Sys->MBEFORE)
		usage();

	f1 := hd args;
	f2 := hd tl args;
	if(sys->bind(f1, f2, flags) < 0){
		if(qflag)
			exit;
		#  try to improve the error message
		err := sys->sprint("%r");
		if(sys->stat(f1).t0 < 0)
			sys->fprint(stderr, "bind: %s: %r\n", f1);
		else if(sys->stat(f2).t0 < 0)
			sys->fprint(stderr, "bind: %s: %r\n", f2);
		else
			sys->fprint(stderr, "bind: cannot bind %s onto %s: %s\n", f1, f2, err);
		raise "fail:bind";
	}
}
