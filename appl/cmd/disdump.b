implement Disdump;

include "sys.m";
	sys: Sys;
include "draw.m";
include "dis.m";
	dis: Dis;
include "bufio.m";
	bufio: Bufio;
	Iobuf: import bufio;

Disdump: module {
	init: fn(nil: ref Draw->Context, argv: list of string);
};

init(nil: ref Draw->Context, argv: list of string)
{
	sys = load Sys Sys->PATH;
	stderr := sys->fildes(2);
	bufio = load Bufio Bufio->PATH;
	if (bufio == nil) {
		sys->fprint(stderr, "dis: cannot load %s: %r\n", Bufio->PATH);
		raise "fail:bad module";
	}

	dis = load Dis Dis->PATH;
	if (dis == nil) {
		sys->fprint(stderr, "dis: cannot load %s: %r\n", Dis->PATH);
		raise "fail:bad module";
	}

	if (len argv < 2) {
		sys->fprint(stderr, "usage: dis module...\n");
		raise "fail:usage";
	}
	dis->init();
	out := bufio->fopen(sys->fildes(1), Sys->OWRITE);
	errs := 0;
	for (argv = tl argv; argv != nil; argv = tl argv) {
		(mod, err) := dis->loadobj(hd argv);
		if (mod == nil) {
			sys->fprint(stderr, "dis: failed to load %s: %s\n", hd argv, err);
			errs++;
			continue;
		}
		for (i := 0; i < len mod.inst; i++)
			out.puts(dis->inst2s(mod.inst[i])+"\n");
	}
	out.close();
	if (errs)
		raise "fail:errors";
}
