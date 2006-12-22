implement Info;

include "sys.m";
	sys: Sys;
include "draw.m";
include "bufio.m";
	bufio: Bufio;
	Iobuf: import bufio;
include "daytime.m";
	daytime: Daytime;
include "arg.m";
	arg: Arg;
include "wrap.m";
	wrap : Wrap;

Info: module{
	init:	fn(nil: ref Draw->Context, nil: list of string);
};

root : string;

TYPLEN : con 4;
typestr := array[TYPLEN] of { "???", "package", "update", "full update" };

fatal(err : string)
{
	sys->fprint(sys->fildes(2), "%s\n", err);
	raise "fail:error";
}

init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	bufio = load Bufio Bufio->PATH;
	daytime = load Daytime Daytime->PATH;
	arg = load Arg Arg->PATH;
	wrap = load Wrap Wrap->PATH;
	wrap->init(bufio);

	arg->init(args);
	while ((c := arg->opt()) != 0) {
		case c {
			'r' =>
				root = arg->arg();
				if (root == nil)
					fatal("missing root name");
			* =>
				fatal(sys->sprint("bad argument -%c", c));
		}
	}
	args = arg->argv();
	if (args == nil || tl args != nil)
		fatal("usage: install/info [-r root] package");
	w := wrap->openwraphdr(hd args, root, nil, 0);
	if (w == nil)
		fatal("no such package found");
	tm := daytime->text(daytime->local(w.tfull));
	sys->print("%s (complete as of %s)\n", w.name, tm[0:28]);
	for (i := w.nu; --i >= 0;) {
		typ := w.u[i].typ;
		if (typ < 0 || typ >= TYPLEN)
			sys->print("%s", typestr[0]);
		else
			sys->print("%s", typestr[typ]);
		sys->print(" %s", wrap->now2string(w.u[i].time, 0));
		if (typ & wrap->UPD)
			sys->print(" updating %s", wrap->now2string(w.u[i].utime, 0));
		if (w.u[i].desc != nil)
			sys->print(": %s", w.u[i].desc);
		sys->print("\n");
	}
	wrap->end();
}
