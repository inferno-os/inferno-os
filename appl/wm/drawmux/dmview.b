implement DMView;

include "sys.m";
include "draw.m";
include "tk.m";
include "tkclient.m";

DMView : module {
	init : fn (ctxt : ref Draw->Context, args : list of string);
};

DMPORT : con 9998;

sys : Sys;
draw : Draw;
tk : Tk;
tkclient : Tkclient;

Display, Image, Screen, Point, Rect, Chans : import draw;

display : ref Display;
screen : ref Screen;


init(ctxt : ref Draw->Context, args : list of string)
{
	sys = load Sys Sys->PATH;
	draw = load Draw Draw->PATH;
	tk = load Tk Tk->PATH;
	if (tk == nil)
		fail(sys->sprint("cannot load %s: %r", Tk->PATH), "init");

	tkclient = load Tkclient Tkclient->PATH;
	if (tkclient == nil)
		fail(sys->sprint("cannot load %s: %r", Tkclient->PATH), "init");

	args = tl args;
	if (args == nil)
		fail("usage: dmview netaddr", "usage");
	addr := hd args;
	args = tl args;

	display = ctxt.display;
	screen = ctxt.screen;

	tkclient ->init();

	(ok, nc) := sys->dial("tcp!"+addr+"!" + string DMPORT, nil);
	if (ok < 0)
		fail(sys->sprint("could not connect: %r"), "init");

	info := array [2 * 12] of byte;
	if (sys->read(nc.dfd, info, len info) != len info) {
		sys->print("protocol error\n");
		return;
	}
	dispw := int string info[0:12];
	disph := int string info[12:24];
	info = nil;

	(tktop, wmctl) := tkclient->toplevel(ctxt, "", "dmview: "+addr, Tkclient->Hide);
	if (tktop == nil)
		fail("cannot create window", "init");

	cpos := mkframe(tktop, dispw, disph);
	winr := Rect((0, 0), (dispw, disph));
	newwin := display.newimage(winr, display.image.chans, 0, Draw->White);
	# newwin := screen.newwindow(winr, Draw->Refbackup, Draw->White);
	if (newwin == nil) {
		sys->print("failed to create window: %r\n");
		return;
	}
	tk->putimage(tktop, ".c", newwin, nil);
	tk->cmd(tktop, ".c dirty");
	tk->cmd(tktop, "update");
	winr = winr.addpt(cpos);
	newwin.origin(Point(0,0), winr.min);

	pubscr := Screen.allocate(newwin, ctxt.display.black, 1);
	if (pubscr == nil) {
		sys->print("failed to create public screen: %r\n");
		return;
	}
	
	msg := array of byte sys->sprint("%11d %11s ", pubscr.id, newwin.chans.text());
	sys->write(nc.dfd, msg, len msg);
	msg = nil;

	pidc := chan of int;
	spawn srv(nc.dfd, wmctl, pidc);
	srvpid := <- pidc;

	tkclient->onscreen(tktop, nil);
	tkclient->startinput(tktop, nil);

	for (;;) {
		cmd := <- wmctl;
		case cmd {
		"srvexit" =>
sys->print("srv exit: %r\n");
			srvpid = -1;
		"exit" =>
			if (srvpid != -1)
				kill(srvpid);
			return;
		"move" =>
			newwin.origin(Point(0,0), display.image.r.max);
			tkclient->wmctl(tktop, cmd);
			x := int tk->cmd(tktop, ".c cget -actx");
			y := int tk->cmd(tktop, ".c cget -acty");
			newwin.origin(Point(0,0), Point(x, y));
		"task" =>
			newwin.origin(Point(0,0), display.image.r.max);
			tkclient->wmctl(tktop, cmd);
			x := int tk->cmd(tktop, ".c cget -actx");
			y := int tk->cmd(tktop, ".c cget -acty");
			newwin.origin(Point(0,0), Point(x, y));
		* =>
			tkclient->wmctl(tktop, cmd);
		}
	}
}

srv(fd : ref Sys->FD, done : chan of string, pidc : chan of int)
{
	pidc <-= sys->pctl(Sys->FORKNS, nil);
	sys->bind("/dev/draw", "/", Sys->MREPL);
	sys->export(fd, "/", Sys->EXPWAIT);
	done <-= "srvexit";
}

fail(msg, exc : string)
{
	sys->print("%s\n", msg);
	raise "fail:"+exc;
}

mkframe(t : ref Tk->Toplevel, w, h : int) : Point
{
	tk->cmd(t, "panel .c -width " + string w + " -height " + string h);
	tk->cmd(t, "frame .f -borderwidth 3 -relief groove");
	tk->cmd(t, "pack .c -in .f");
	tk->cmd(t, "pack .f");
	tk->cmd(t, "update");

	x := int tk->cmd(t, ".c cget -actx");
	y := int tk->cmd(t, ".c cget -acty");

	return Point(x, y);
}

kill(pid: int)
{
	if ((pctl  := sys->open("/prog/" + string pid + "/ctl", Sys->OWRITE)) != nil)
		sys->fprint(pctl, "kill");
}

tkcmd(t : ref Tk->Toplevel, c : string)
{
	s := tk->cmd(t, c);
	if (s != nil)
		sys->print("%s ERROR: %s\n", c, s);
}
