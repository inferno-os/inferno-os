implement Gui;

include "common.m";
include "tk.m";
include "wmclient.m";
	wmclient: Wmclient;

sys : Sys;
draw : Draw;
xenith : Xenith;
dat : Dat;
utils : Utils;

Font, Point, Rect, Image, Context, Screen, Display, Pointer : import draw;
keyboardpid, mousepid : import xenith;
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
	xenith = mods.xenith;
	dat = mods.dat;
	utils = mods.utils;
	wmclient = load Wmclient Wmclient->PATH;
	if(wmclient == nil)
		error(sys->sprint("cannot load %s: %r", Wmclient->PATH));
	wmclient->init();

	if(xenith->xenithctxt == nil)
		xenith->xenithctxt = wmclient->makedrawcontext();
	display = (xenith->xenithctxt).display;
	buts := Wmclient->Appl;
	if((xenith->xenithctxt).wm == nil)
		buts = Wmclient->Plain;
	win = wmclient->window(xenith->xenithctxt, "Xenith", buts);
	wmclient->win.reshape(((0, 0), (win.displayr.size().div(2))));
	dat->cmouse = chan of ref Draw->Pointer;
	dat->ckeyboard = win.ctxt.kbd;
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
	wmsize := startwmsize();
	for(;;) alt{
	wmsz := <-wmsize =>
		win.image = win.screen.newwindow(wmsz, Draw->Refnone, Draw->Nofill);
		p := ref zpointer;
		mainwin = win.image;
		p.buttons = Xenith->M_RESIZE;
		dat->cmouse <-= p;
	e := <-win.ctl or
	e = <-win.ctxt.ctl =>
		p := ref zpointer;
		if(e == "exit"){
			p.buttons = Xenith->M_QUIT;
			dat->cmouse <-= p;
		}else{
			wmclient->win.wmctl(e);
			if(win.image != mainwin){
				mainwin = win.image;
				p.buttons = Xenith->M_RESIZE;
				dat->cmouse <-= p;
			}
		}
	}
}

mouseproc()
{
	for(;;){
		p := <-win.ctxt.ptr;
		if(wmclient->win.pointer(*p) == 0){
			p.buttons &= ~Xenith->M_DOUBLE;
			dat->cmouse <-= p;
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
	# Write "halt" to /dev/sysctl to trigger cleanexit() at C level
	# This properly cleans up SDL and closes the window
	fd := sys->open("/dev/sysctl", Sys->OWRITE);
	if(fd != nil)
		sys->fprint(fd, "halt");
	# Fallback to wmctl if sysctl fails
	wmclient->win.wmctl("exit");
}

signalclose()
{
	# Signal preswmloop that we're exiting cleanly without halting emu.
	# Used in embedded mode: writes "embedded-exit" to wmsrv ctl so that
	# preswmloop can immediately remove the ghost tab without waiting for
	# the GC to collect the gui module and close the wmclient fd.
	wmclient->win.wmctl("embedded-exit");
}

startwmsize(): chan of Rect
{
	rchan := chan of Rect;
	fd := sys->open("/dev/wmsize", Sys->OREAD);
	if(fd == nil)
		return rchan;
	sync := chan of int;
	spawn wmsizeproc(sync, fd, rchan);
	<-sync;
	return rchan;
}

Wmsize: con 1+4*12;		# 'm' plus 4 12-byte decimal integers

wmsizeproc(sync: chan of int, fd: ref Sys->FD, ptr: chan of Rect)
{
	sync <-= sys->pctl(0, nil);

	b:= array[Wmsize] of byte;
	while(sys->read(fd, b, len b) > 0){
		p := bytes2rect(b);
		if(p != nil)
			ptr <-= *p;
	}
}

bytes2rect(b: array of byte): ref Rect
{
	if(len b < Wmsize || int b[0] != 'm')
		return nil;
	x := int string b[1:13];
	y := int string b[13:25];
#	but := int string b[25:37];
#	msec := int string b[37:49];
	return ref Rect((0,0), (x, y));
}
