implement Fpgaload;

include"sys.m";
	sys: Sys;

include "draw.m";

include "arg.m";

Fpgaload: module
{
	init:	fn(nil: ref Draw->Context, nil: list of string);
};

init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	arg := load Arg Arg->PATH;
	if(arg == nil)
		error(sys->sprint("can't load %s: %r", Arg->PATH));
	arg->init(args);
	arg->setusage("fpgaload [-c clock] file.rbf");
	clock := -1;
	while((c := arg->opt()) != 0)
		case c {
		'c' =>
			clock = int arg->earg();
			if(clock <= 0)
				error("invalid clock value");
		* =>
			arg->usage();
		}
	args = arg->argv();
	if(args == nil)
		arg->usage();
	arg = nil;

	fd := sys->open(hd args, Sys->OREAD);
	if(fd == nil)
		error(sys->sprint("can't open %s: %r", hd args));
	ofd := sys->open("#G/fpgaprog", Sys->OWRITE);
	if(ofd == nil)
		error(sys->sprint("can't open %s: %r", "#G/fpgaprog"));
	a := array[128*1024] of byte;
	while((n := sys->read(fd, a, len a)) > 0)
		if(sys->write(ofd, a, n) != n)
			error(sys->sprint("write error: %r"));
	if(n < 0)
		error(sys->sprint("read error: %r"));
	if(clock >= 0)
		setclock(clock);
}

setclock(n: int)
{
	fd := sys->open("#G/fpgactl", Sys->OWRITE);
	if(fd == nil)
		error(sys->sprint("can't open %s: %r", "#G/fpgactl"));
	if(sys->fprint(fd, "bclk %d", n) < 0)
		error(sys->sprint("can't set clock to %d: %r", n));
}

error(s: string)
{
	sys->fprint(sys->fildes(2), "fpgaload: %s\n", s);
	raise "fail:error";
}
