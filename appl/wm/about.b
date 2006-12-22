implement WmAbout;

include "sys.m";
	sys: Sys;

include "draw.m";
	draw: Draw;
	Display, Image: import draw;

include "tk.m";
	tk: Tk;

include	"tkclient.m";
	tkclient: Tkclient;

WmAbout: module
{
	init:	fn(ctxt: ref Draw->Context, argv: list of string);
};

tkcfg(version: string): array of string
{
	return  array[] of {
	"frame .f -bg black -borderwidth 2 -relief ridge",
	"label .b -bg black -bitmap @/icons/inferno.bit",
	"label .l1 -bg black -fg #ff5500  -text {Inferno "+ version + "}",
	"pack .b .l1 -in .f",
	"pack .f -ipadx 4 -ipady 2",
	"pack propagate . 0",
	"update",
	};
}

init(ctxt: ref Draw->Context, nil: list of string)
{
	sys  = load Sys  Sys->PATH;
	if (ctxt == nil) {
		sys->fprint(sys->fildes(2), "about: no window context\n");
		raise "fail:bad context";
	}

	draw = load Draw Draw->PATH;
	tk   = load Tk   Tk->PATH;
	tkclient= load Tkclient Tkclient->PATH;

	tkclient->init();
	(t, menubut) := tkclient->toplevel(ctxt, "", "About Inferno", 0);

	tkcmds := tkcfg(rf("/dev/sysctl"));
	for (i := 0; i < len tkcmds; i++)
		tk->cmd(t,tkcmds[i]);

	tkclient->onscreen(t, nil);
	tkclient->startinput(t, "ptr"::nil);
	stop := chan of int;
	spawn tkclient->handler(t, stop);
	while((menu := <-menubut) != "exit")
		tkclient->wmctl(t, menu);
	stop <-= 1;
}

rf(name: string): string
{
	fd := sys->open(name, Sys->OREAD);
	if(fd == nil)
		return nil;
	buf := array[128] of byte;
	n := sys->read(fd, buf, len buf);
	if(n < 0)
		n = 0;
	return string buf[0:n];
}
