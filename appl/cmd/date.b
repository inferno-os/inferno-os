implement Date;

include "sys.m";
	sys: Sys;

include "draw.m";
include "daytime.m";
include "arg.m";

Date: module
{
	init:	fn(ctxt: ref Draw->Context, argv: list of string);
};

usage()
{
	sys->fprint(sys->fildes(2), "usage: date [-un] [seconds]\n");
	raise "fail:usage";
}

nomod(m: string)
{
	sys->fprint(sys->fildes(2), "date: cannot load %s: %r", m);
	raise "fail:load";
}

init(nil: ref Draw->Context, argv: list of string)
{
	sys = load Sys Sys->PATH;
	daytime := load Daytime Daytime->PATH;
	if (daytime == nil)
		nomod(Daytime->PATH);
	arg := load Arg Arg->PATH;
	if (arg == nil)
		nomod(Arg->PATH);
	nflag := uflag := 0;
	arg->init(argv);
	while ((opt := arg->opt()) != 0) {
		case opt {
		'n' =>
			nflag = 1;
		'u' =>
			uflag = 1;
		* =>
			usage();
		}
	}
	argv = arg->argv();
	arg = nil;
	if (argv != nil && (tl argv != nil || !isnumeric(hd argv)))
		usage();
	now: int;
	if (argv != nil)
		now = int hd argv;
	else
		now = daytime->now();
	if (nflag)
		sys->print("%d\n", now);
	else if (uflag)
		sys->print("%s\n", daytime->text(daytime->gmt(now)));
	else
		sys->print("%s\n", daytime->text(daytime->local(now)));
}

isnumeric(s: string): int
{
	for (i := 0; i < len s; i++)
		if (s[i] < '0' || s[i] > '9')
			return 0;
	return 1;
}
