implement Uniq;

include "sys.m";
	sys: Sys;
include "bufio.m";
include "draw.m";
include "arg.m";

Uniq: module
{
	init:	fn(nil: ref Draw->Context, args: list of string);
};

usage()
{
	fail("usage", sys->sprint("usage: uniq [-udc] [file]"));
}

init(nil : ref Draw->Context, args : list of string)
{
	bio : ref Bufio->Iobuf;

	sys = load Sys Sys->PATH;
	bufio := load Bufio Bufio->PATH;
	if (bufio == nil)
		fail("bad module", sys->sprint("uniq: cannot load %s: %r", Bufio->PATH));
	Iobuf: import bufio;
	arg := load Arg Arg->PATH;
	if (arg == nil)
		fail("bad module", sys->sprint("uniq: cannot load %s: %r", Arg->PATH));

	uflag := 0;
	dflag := 0;
	cflag := 0;
	arg->init(args);
	while ((opt := arg->opt()) != 0) {
		case opt {
		'u' =>
			uflag = 1;
		'd' =>
			dflag = 1;
		'c' =>
			cflag = 1;
		* =>
			usage();
		}
	}
	args = arg->argv();
	if (len args > 1)
		usage();
	if (args != nil) {
		bio = bufio->open(hd args, Bufio->OREAD);
		if (bio == nil)
			fail("open file", sys->sprint("uniq: cannot open %s: %r\n", hd args));
	} else
		bio = bufio->fopen(sys->fildes(0), Bufio->OREAD);

	stdout := bufio->fopen(sys->fildes(1), Bufio->OWRITE);
	if (!(uflag || dflag))
		uflag = dflag = 1;
	prev := "";
	n := 0;
	while ((s := bio.gets('\n')) != nil) {
		if (s == prev)
			n++;
		else {
			if ((uflag && n == 1) || (dflag && n > 1)) {
				if(cflag)
					prev = string n + "\t" + prev;
				stdout.puts(prev);
			}
			n = 1;
			prev = s;
		}
	}
	if ((uflag && n == 1) || (dflag && n > 1)) {
		if(cflag)
			prev = string n + "\t" + prev;
		stdout.puts(prev);
	}
	stdout.close();
}

fail(ex, msg: string)
{
	sys->fprint(sys->fildes(2), "%s\n", msg);
	raise "fail:"+ex;
}
