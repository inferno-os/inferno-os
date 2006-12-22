implement Filename;

include "sys.m";
	sys: Sys;
	stderr: ref Sys->FD;
include "draw.m";
	draw: Draw;
	Rect: import draw;
include "tk.m";
include "selectfile.m";
	selectfile: Selectfile;

include "arg.m";

Filename: module
{
	init:	fn(ctxt: ref Draw->Context, argv: list of string);
};

usage()
{
	sys->fprint(stderr, "usage: filename [-g geom] [-d startdir] [pattern...]\n");
	raise "fail:usage";
}

init(ctxt: ref Draw->Context, argv: list of string)
{
	sys = load Sys Sys->PATH;
	stderr = sys->fildes(2);
	draw = load Draw Draw->PATH;
	selectfile = load Selectfile Selectfile->PATH;
	if (selectfile == nil) {
		sys->fprint(stderr, "selectfile: cannot load %s: %r\n", Selectfile->PATH);
		raise "fail:bad module";
	}
	arg := load Arg Arg->PATH;
	if (arg == nil) {
		sys->fprint(stderr, "filename: cannot load %s: %r\n", Arg->PATH);
		raise "fail:bad module";
	}

	if (ctxt == nil) {
		sys->fprint(stderr, "filename: no window context\n");
		raise "fail:bad context";
	}

	sys->pctl(Sys->NEWPGRP, nil);
	selectfile->init();

	startdir := ".";
#	geom := "-x " + string (ctxt.screen.image.r.dx() / 5) +
#			" -y " + string (ctxt.screen.image.r.dy() / 5);
	title := "Select a file";
	arg->init(argv);
	while (opt := arg->opt()) {
		case opt {
#		'g' =>
#			geom = arg->arg();
		'd' =>
			startdir = arg->arg();
		't' =>
			title = arg->arg();
		* =>
			sys->fprint(stderr, "filename: unknown option -%c\n", opt);
			usage();
		}
	}
	if (startdir == nil || title == nil)
		usage();
#	top := tk->toplevel(ctxt.screen, geom);
	argv = arg->argv();
	arg = nil;
	sys->print("%s\n", selectfile->filename(ctxt, nil, title, argv, startdir));
}
