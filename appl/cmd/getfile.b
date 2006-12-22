implement Getfile;

include "sys.m";
	sys: Sys;
	stderr: ref Sys->FD;
include "draw.m";
	draw: Draw;
	Rect: import draw;
include "tk.m";
	tk: Tk;
include "wmlib.m";
	wmlib: Wmlib;
include "arg.m";

Getfile: module
{
	init:	fn(ctxt: ref Draw->Context, argv: list of string);
};

usage()
{
	sys->fprint(stderr, "usage: getfile [-g geom] [-d startdir] [pattern...]\n");
	raise "fail:usage";
}

init(ctxt: ref Draw->Context, argv: list of string)
{
	sys = load Sys Sys->PATH;
	stderr = sys->fildes(2);
	draw = load Draw Draw->PATH;
	tk = load Tk Tk->PATH;
	wmlib = load Wmlib Wmlib->PATH;
	if (wmlib == nil) {
		sys->fprint(stderr, "getfile: cannot load %s: %r\n", Wmlib->PATH);
		raise "fail:bad module";
	}
	arg := load Arg Arg->PATH;
	if (arg == nil) {
		sys->fprint(stderr, "getfile: cannot load %s: %r\n", Arg->PATH);
		raise "fail:bad module";
	}

	if (ctxt == nil) {
		sys->fprint(stderr, "getfile: no window context\n");
		raise "fail:bad context";
	}

	wmlib->init();

	startdir := ".";
	geom := "-x " + string (ctxt.screen.image.r.dx() / 5) +
			" -y " + string (ctxt.screen.image.r.dy() / 5);
	title := "Select a file";
	arg->init(argv);
	while (opt := arg->opt()) {
		case opt {
		'g' =>
			geom = arg->arg();
		'd' =>
			startdir = arg->arg();
		't' =>
			title = arg->arg();
		* =>
			sys->fprint(stderr, "getfile: unknown option -%c\n", opt);
			usage();
		}
	}
	if (geom == nil || startdir == nil || title == nil)
		usage();
	top := tk->toplevel(ctxt.screen, geom);
	argv = arg->argv();
	arg = nil;
	sys->print("%s\n", wmlib->filename(ctxt.screen, top, title, argv, startdir));
}
