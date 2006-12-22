implement Gui;

include "common.m";
include "tk.m";
include "wmclient.m";
	wmclient: Wmclient;

sys : Sys;
draw : Draw;
acme : Acme;
dat : Dat;
utils : Utils;

Font, Point, Rect, Image, Context, Screen, Display, Pointer : import draw;
keyboardpid, mousepid : import acme;
ckeyboard, cmouse : import dat;
mousefd: ref Sys->FD;
error : import utils;

win: ref Wmclient->Window;

r2s(r: Rect): string
{
	return sys->sprint("%d %d %d %d", r.min.x, r.min.y, r.max.x, r.max.y);
}

init(mods : ref Dat->Mods)
{
	sys = mods.sys;
	draw = mods.draw;
	acme = mods.acme;
	dat = mods.dat;
	utils = mods.utils;
	wmclient = load Wmclient Wmclient->PATH;
	if(wmclient == nil)
		error(sys->sprint("cannot load %s: %r", Wmclient->PATH));
	wmclient->init();

	if(acme->acmectxt == nil)
		acme->acmectxt = wmclient->makedrawcontext();
	display = (acme->acmectxt).display;
	win = wmclient->window(acme->acmectxt, "Acme", Wmclient->Appl);
	wmclient->win.reshape(((0, 0), (win.displayr.size().div(2))));
	cmouse = chan of ref Draw->Pointer;
	ckeyboard = win.ctxt.kbd;
	wmclient->win.onscreen("place");
	wmclient->win.startinput("kbd"::"ptr"::nil);
	mainwin = win.image;
	
	yellow = display.color(Draw->Yellow);
	green = display.color(Draw->Green);
	red = display.color(Draw->Red);
	blue = display.color(Draw->Blue);
	black = display.color(Draw->Black);
	white = display.color(Draw->White);
}

spawnprocs()
{
	spawn mouseproc();
	spawn eventproc();
}

zpointer: Draw->Pointer;

eventproc()
{
	for(;;) alt{
	e := <-win.ctl or
	e = <-win.ctxt.ctl =>
		p := ref zpointer;
		if(e == "exit"){
			p.buttons = Acme->M_QUIT;
			cmouse <-= p;
		}else{
			wmclient->win.wmctl(e);
			if(win.image != mainwin){
				mainwin = win.image;
				p.buttons = Acme->M_RESIZE;
				cmouse <-= p;
			}
		}
	}
}

mouseproc()
{
	for(;;){
		p := <-win.ctxt.ptr;
		if(wmclient->win.pointer(*p) == 0){
			p.buttons &= ~Acme->M_DOUBLE;
			cmouse <-= p;
		}
	}
}
		

# consctlfd : ref Sys->FD;

cursorset(p: Point)
{
	wmclient->win.wmctl("ptr " + string p.x + " " + string p.y);
}

cursorswitch(cur: ref Dat->Cursor)
{
	s: string;
	if(cur == nil)
		s = "cursor";
	else{
		Hex: con "0123456789abcdef";
		s = sys->sprint("cursor %d %d %d %d ", cur.hot.x, cur.hot.y, cur.size.x, cur.size.y);
		buf := cur.bits;
		for(i := 0; i < len buf; i++){
			c := int buf[i];
			s[len s] = Hex[c >> 4];
			s[len s] = Hex[c & 16rf];
	 	}
	}
	wmclient->win.wmctl(s);
}

killwins()
{
	wmclient->win.wmctl("exit");
}
