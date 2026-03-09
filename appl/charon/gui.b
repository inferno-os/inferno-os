# Gui implementation for running under wm (tk window manager)
implement Gui;

include "common.m";
include "wmclient.m";
	wmclient: Wmclient;
	Window: import wmclient;

sys: Sys;

D: Draw;
	Font,Point, Rect, Image, Screen, Display: import D;
	menumod: Menu;
	Popup: import menumod;

CU: CharonUtils;

E: Events;
	Event: import E;


WINDOW, CTLS, PROG, STATUS, BORDER, EXIT: con 1 << iota;
REQD: con ~0;

mousegrabbed := 0;
offset: Point;
ZP: con Point(0,0);
popup: ref Popup;
gctl: chan of string;
drawctxt: ref Draw->Context;
window: ref Window;
menu: ref Menu->Popup;

realwin: ref Draw->Image;
mask: ref Draw->Image;

init(ctxt: ref Draw->Context, cu: CharonUtils): ref Draw->Context
{
	sys = load Sys Sys->PATH;
	D = load Draw Draw->PATH;
	CU = cu;
	E = cu->E;
	if((CU->config).doacme){
		display=ctxt.display;
		makewins();
		progress = chan of Progressmsg;
		pidc := chan of int;
		spawn doacmeprogmon(pidc);
		<- pidc;
		return ctxt;
	}
	wmclient = load Wmclient Wmclient->PATH;
	wmclient->init();
	if (ctxt == nil)
		ctxt = wmclient->makedrawcontext();
	if(ctxt == nil) {
		# Headless mode: no display available.
		# Drain the progress channel so goproc never blocks on it.
		progress = chan of Progressmsg;
		pidc := chan of int;
		spawn doacmeprogmon(pidc);
		<-pidc;
		return nil;
	}

	menumod = load Menu Menu->PATH;

	win := wmclient->window(ctxt, "charon", Wmclient->Plain);
	window = win;
	drawctxt = ctxt;
	display = win.display;
	if(menumod != nil) {
		f := Font.open(display, "/fonts/combined/unicode.sans.14.font");
		if(f == nil)
			f = Font.open(display, "*default*");
		menumod->init(display, f);
		menu = menumod->new(array[] of {"back", "forward", "stop", "start"});
	}

	gctl = chan of string;
#	w := (CU->config).defaultwidth;
#	h := (CU->config).defaultheight;
	win.reshape(Rect((0, 0), (display.image.r.dx(), display.image.r.dy())));
	win.startinput( "kbd"::"ptr"::nil);
	win.onscreen(nil);
	makewins();
	mask = display.opaque;
	progress = chan of Progressmsg;
	pidc := chan of int;
	spawn progmon(pidc);
	<- pidc;
	spawn evhandle(win, E->evchan);
	return ctxt;
}

doacmeprogmon(pidc: chan of int)
{
	pidc <-= sys->pctl(0, nil);
	for (;;) {
		<- progress;
	}
}

progmon(pidc: chan of int)
{
	pidc <-= sys->pctl(0, nil);
	for (;;) {
		msg := <- progress;
#prprog(msg);
		# just handle stop button for now
		if (msg.bsid == -1) {
			case (msg.state) {
			Pstart =>	stopbutton(1);
			* =>		stopbutton(0);
			}
		}
	}
}

st2s := array [] of {
	Punused => "unused",
	Pstart => "start",
	Pconnected => "connected",
	Psslconnected => "sslconnected",
	Phavehdr => "havehdr",
	Phavedata => "havedata",
	Pdone => "done",
	Perr => "error",
	Paborted => "aborted",
};

prprog(m:Progressmsg)
{
	sys->print("%d %s %d%% %s\n", m.bsid, st2s[m.state], m.pcnt, m.s);
}


r2s(r: Rect): string
{
	return sys->sprint("%d %d %d %d", r.min.x, r.min.y, r.max.x, r.max.y);
}

evhandle(w: ref Window, evchan: chan of ref Event)
{
	last : Draw->Pointer;
	wmsize := startwmsize();
	for(;;) {
		ev: ref Event = nil;
		alt {
		wmsz := <-wmsize =>
			w.image = w.screen.newwindow(wmsz, Draw->Refnone, Draw->Nofill);
			makewins();
			ev = ref Event.Ereshape(mainwin.r);
			offset = w.image.r.min;
		ctl := <-w.ctl or
		ctl = <-w.ctxt.ctl =>
			w.wmctl(ctl);
			if(ctl != nil && ctl[0] == '!'){
				makewins();
				ev = ref Event.Ereshape(mainwin.r);
				offset = w.image.r.min;
			}
		p := <-w.ctxt.ptr =>
			if(w.pointer(*p))
				continue;
			if(p.buttons & 4){
				if(menumod == nil || menu == nil)
					continue;
				n := menu.show(window.image, p.xy, w.ctxt.ptr);
				case n {
				0 => ev = ref Event.Eback;
				1 => ev = ref Event.Efwd;
				2 => ev = ref Event.Estop;
				3 => ev = ref Event.Ego((CU->config).starturl, "_top", 0, E->EGnormal);
				}
			}else if(p.buttons & (8|16)) {
				if(p.buttons & 8)
					ev = ref Event.Escrollr(0, Point(0, -50));
				else
					ev = ref Event.Escrollr(0, Point(0, 50));
			}else {
				pt := p.xy;
				pt = pt.sub(offset);
				if(p.buttons  && !last.buttons)
					ev = ref Event.Emouse(pt, E->Mlbuttondown);
				else if(!p.buttons  &&  last.buttons)
					ev = ref Event.Emouse(pt, E->Mlbuttonup);
				else if(p.buttons && last.buttons)
					ev = ref Event.Emouse(pt, E->Mldrag);
				last = *p;
			}
		k := <-w.ctxt.kbd =>
			ev = ref Event.Ekey(k);
		}
		if (ev != nil)
			evchan <-= ev;
	}
}

makewins()
{
	if((CU->config).doacme){
		mainwin = display.newimage(Rect(display.image.r.min, ((CU->config).defaultwidth, display.image.r.max.y)), display.image.chans, 0, D->White);
		return;
		if(mainwin == nil)
			CU->raisex(sys->sprint("EXFatal: can't initialize windows: %r"));
	}
	if(window.image == nil)
		return;
	screen := Screen.allocate(window.image, display.transparent, 0);
	r := window.image.r;
	realwin = screen.newwindow(r, D->Refnone, D->White);
	realwin.origin(ZP, r.min);
	if(realwin == nil)
		CU->raisex(sys->sprint("EXFatal: can't initialize windows: %r"));
	mainwin = display.newimage(realwin.r, realwin.chans, 0, D->White);
	if(mainwin == nil)
		CU->raisex(sys->sprint("EXFatal: can't create offscreen buffer: %r"));
}

hidewins()
{
	if((CU->config).doacme)
		return;
}

snarfput(nil: string)
{
	if((CU->config).doacme)
		return;
}

setstatus(nil: string)
{
	if((CU->config).doacme)
		return;
}

seturl(nil: string)
{
	if((CU->config).doacme)
		return;
}

auth(realm: string): (int, string, string)
{
	user := prompt(realm + " username?", nil).t1;
	passwd := prompt("password?", nil).t1;
	if(user == nil)
		return (0, nil, nil);
	return (1, user, passwd);
}

alert(msg: string)
{
sys->print("ALERT:%s\n", msg);
	return;
}

confirm(msg: string): int
{
sys->print("CONFIRM:%s\n", msg);
	return -1;
}

prompt(nil, nil: string): (int, string)
{
	if((CU->config).doacme)
		return (-1, "");
	return (-1, "");
}

stopbutton(nil: int)
{
	if((CU->config).doacme)
		return;
}

backbutton(nil: int)
{
	if((CU->config).doacme)
		return;
}

fwdbutton(nil: int)
{
	if((CU->config).doacme)
		return;
}

flush(r: Rect)
{
	if((CU->config).doacme)
		return;
	if(realwin != nil) {
		oclipr := mainwin.clipr;
		mainwin.clipr = r;
		realwin.draw(r, mainwin, nil, r.min);
		mainwin.clipr = oclipr;
		mainwin.flush(D->Flushnow);
	}
}

clientfocus()
{
	if((CU->config).doacme)
		return;
}

exitcharon()
{
	hidewins();
	E->evchan <-= ref Event.Equit(0);
}

tkupdate()
{
}

getpopup(nil: Rect): ref Menu->Popup
{
	return nil;
}

cancelpopup(): int
{
	if (popup == nil)
		return 0;
	popup = nil;
	return 1;
}


startwmsize(): chan of Rect
{
	rchan := chan of Rect;
	fd := sys->open("#w/wmsize", Sys->OREAD);
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
