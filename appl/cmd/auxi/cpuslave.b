implement CPUslave;

include "sys.m";
	sys: Sys;
include "draw.m";
	draw: Draw;
	Context, Display, Screen: import draw;
include "arg.m";

include "sh.m";

stderr: ref Sys->FD;

CPUslave: module
{
	init: fn(ctxt: ref Context, args: list of string);
};

usage()
{
	sys->fprint(stderr, "usage: cpuslave [-s screenid] command args\n");
	raise "fail:usage";
}

init(nil: ref Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	stderr = sys->fildes(2);
	draw = load Draw Draw->PATH;

	arg := load Arg Arg->PATH;
	if (arg == nil) {
		sys->fprint(stderr, "cpuslave: cannot load %s: %r\n", Arg->PATH);
		raise "fail:bad module";
	}
	screenid := -1;
	arg->init(args);
	while ((opt := arg->opt()) != 0) {
		if (opt != 's' || (a := arg->arg()) == nil)
			usage();
		screenid = int a;
	}
	args = arg->argv();
	if(args == nil)
		usage();

	file := hd args + ".dis";
	cmd := load Command file;
	if(cmd == nil)
		cmd = load Command "/dis/"+file;
	if(cmd == nil){
		sys->fprint(stderr, "cpuslave: can't load %s: %r\n", hd args);
		raise "fail:bad command";
	}

	ctxt: ref Context;
	if (screenid >= 0) {
		display := Display.allocate(nil);
		if(display == nil){
			sys->fprint(stderr, "cpuslave: can't initialize display: %r\n");
			raise "fail:no display";
		}
	
		screen: ref Screen;
		if(screenid >= 0){
			screen = display.publicscreen(screenid);
			if(screen == nil){
				sys->fprint(stderr, "cpuslave: cannot access screen %d: %r\n", screenid);
				raise "fail:bad screen";
			}
		}

		ctxt = ref Context;
		ctxt.screen = screen;
		ctxt.display = display;
	}
	
	spawn cmd->init(ctxt, args);
}
