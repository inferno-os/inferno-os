implement Lucifer;

#
# lucifer - Lucifer WM Tiler
#
# Fullscreen three-zone layout for InferNode:
#   Left  (~30%): Conversation  — luciconv goroutine
#   Centre(~45%): Presentation  — lucipres wmclient app (via wmsrv)
#   Right (~25%): Context       — lucictx goroutine
#
# lucifer owns:
#   - the main Window (via wmclient)
#   - header bar drawing (logo, label, status, accent bar)
#   - zone separators
#   - Screen + sub-Image allocation for conv and ctx zones
#   - a mini wmsrv (preswmloop) for the presentation zone
#   - mouse routing by X position to zone channels
#   - keyboard routing (all to conv)
#   - nslistener for "status"/"label" header events
#

include "sys.m";
	sys: Sys;

include "draw.m";
	draw: Draw;
	Font, Point, Rect, Image, Display, Screen, Pointer, Wmcontext: import draw;

include "arg.m";

include "bufio.m";

include "imagefile.m";

include "wmclient.m";
	wmclient: Wmclient;

include "wmsrv.m";
	wmsrv: Wmsrv;
	Client: import wmsrv;

Lucifer: module {
	init: fn(ctxt: ref Draw->Context, args: list of string);
};

# --- Inline module declarations for zone apps ---

LuciConv: module {
	PATH: con "/dis/luciconv.dis";
	init: fn(img: ref Draw->Image, dsp: ref Draw->Display,
	         font: ref Draw->Font, mfont: ref Draw->Font,
	         mountpt: string, actid: int,
	         mouse: chan of ref Draw->Pointer,
	         kbd:   chan of int,
	         evch:  chan of string,
	         rsz:   chan of ref Draw->Image);
};

LuciCtx: module {
	PATH: con "/dis/lucictx.dis";
	init: fn(img: ref Draw->Image, dsp: ref Draw->Display,
	         font: ref Draw->Font,
	         mountpt: string, actid: int,
	         mouse: chan of ref Draw->Pointer,
	         evch:  chan of string,
	         rsz:   chan of ref Draw->Image);
};

LuciPres: module {
	PATH: con "/dis/lucipres.dis";
	init: fn(ctxt: ref Draw->Context, args: list of string);
	deliverevent: fn(ev: string);
};

# --- Color constants (for header only) ---
COLBG:		con int 16r080808FF;
COLBORDER:	con int 16r131313FF;
COLHEADER:	con int 16r0A0A0AFF;
COLACCENT:	con int 16rE8553AFF;
COLTEXT:	con int 16rCCCCCCFF;
COLDIM:		con int 16r444444FF;

# --- Module-level state ---

stderr: ref Sys->FD;
display: ref Display;
win: ref Wmclient->Window;
mainwin: ref Image;		# the main window image (full frame)

# Colors (header only)
bgcol: ref Image;
bordercol: ref Image;
headercol: ref Image;
accentcol: ref Image;
textcol: ref Image;
dimcol: ref Image;

# Fonts
mainfont: ref Font;
monofont: ref Font;

# Logo
logoimg: ref Image;

# Mount point and activity
mountpt: string;
actid := -1;
actlabel: string;
actstatus: string;

# Zone boundaries (set on every layout pass, used by mouseproc)
pres_zone_minx := 0;
pres_zone_maxx := 0;
ctx_zone_minx := 0;

# Zone channels
convMouseCh: chan of ref Pointer;
convKbdCh:   chan of int;
convEvCh:    chan of string;
convRszCh:   chan of ref Draw->Image;

presMouseCh: chan of ref Pointer;
presKbdCh:   chan of int;

ctxMouseCh: chan of ref Pointer;
ctxEvCh:    chan of string;
ctxRszCh:   chan of ref Draw->Image;

# Preswmloop resize channel (sends new pres zone rect when window resizes)
presRszCh: chan of Rect;

# Loaded lucipres module ref (for event delivery)
lucipres_g: LuciPres;

# Header event channel (status/label only)
luciStatusCh: chan of string;

# Main trigger for header redraws
uievent: chan of int;

# Quit/resize pseudo-buttons
M_RESIZE: con 1 << 5;
M_QUIT:   con 1 << 6;

# Shared cmouse for eventproc → mainloop
cmouse: chan of ref Pointer;
zpointer: Pointer;

# Screen/sub-image globals — must be module-level to prevent GC.
# When a Screen is GC'd the draw kernel refills its background area with the
# parent screen's fill color (White from wmclient putimage).  The separator
# pixels between zone sub-images ARE that background area, so GC → white lines.
mainscr: ref Screen;
pressubimg: ref Image;
presscr: ref Screen;
convimg: ref Image;
ctximg: ref Image;

nomod(s: string)
{
	sys->fprint(stderr, "lucifer: can't load %s: %r\n", s);
	raise "fail:load";
}

usage()
{
	sys->fprint(stderr, "Usage: lucifer [-m mountpoint]\n");
	raise "fail:usage";
}

# --- init ---

init(ctxt: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	sys->pctl(Sys->NEWPGRP, nil);
	stderr = sys->fildes(2);

	sys->fprint(sys->fildes(1), "lucifer: INIT BUILD=20260301a\n");
	sys->fprint(sys->fildes(2), "lucifer: INIT BUILD=20260301a\n");
	{
		hse := sys->open("/dev/hoststderr", Sys->OWRITE);
		if(hse != nil)
			sys->fprint(hse, "lucifer: INIT BUILD=20260301a (hoststderr)\n");
	}

	draw = load Draw Draw->PATH;
	if(draw == nil)
		nomod(Draw->PATH);

	wmclient = load Wmclient Wmclient->PATH;
	if(wmclient == nil)
		nomod(Wmclient->PATH);
	wmclient->init();

	arg := load Arg Arg->PATH;
	if(arg == nil)
		nomod(Arg->PATH);
	arg->init(args);

	mountpt = "/n/ui";
	while((o := arg->opt()) != 0)
		case o {
		'm' =>	mountpt = arg->earg();
		* =>	usage();
		}
	arg = nil;

	# Create main window
	if(ctxt == nil)
		ctxt = wmclient->makedrawcontext();
	display = ctxt.display;

	buts := Wmclient->Appl;
	if(ctxt.wm == nil)
		buts = Wmclient->Plain;
	win = wmclient->window(ctxt, "Lucifer", buts);
	wmclient->win.reshape(((0, 0), (win.displayr.size())));
	wmclient->win.onscreen("place");
	wmclient->win.startinput("kbd"::"ptr"::nil);
	mainwin = win.image;

	# Allocate colors (header only)
	bgcol    = display.color(COLBG);
	bordercol= display.color(COLBORDER);
	headercol= display.color(COLHEADER);
	accentcol= display.color(COLACCENT);
	textcol  = display.color(COLTEXT);
	dimcol   = display.color(COLDIM);

	# Load fonts
	mainfont = Font.open(display, "/fonts/dejavu/DejaVuSans/unicode.14.font");
	if(mainfont == nil)
		mainfont = Font.open(display, "*default*");
	monofont = Font.open(display, "/fonts/dejavu/DejaVuSansMono/unicode.14.font");
	if(monofont == nil)
		monofont = mainfont;

	# Load logo
	bufio := load Bufio Bufio->PATH;
	if(bufio != nil) {
		readpng := load RImagefile RImagefile->READPNGPATH;
		remap := load Imageremap Imageremap->PATH;
		if(readpng != nil && remap != nil) {
			readpng->init(bufio);
			remap->init(display);
			fd := bufio->open("/lib/lucifer/logo.png", Bufio->OREAD);
			if(fd != nil) {
				(raw, nil) := readpng->read(fd);
				if(raw != nil)
					(logoimg, nil) = remap->remap(raw, display, 0);
			}
		}
	}

	# Read current activity
	s := readfile(mountpt + "/activity/current");
	if(s != nil)
		actid = strtoint(strip(s));
	if(actid >= 0) {
		loadlabel();
		loadstatus();
	}

	# Allocate channels
	cmouse      = chan of ref Pointer;
	uievent     = chan[1] of int;
	luciStatusCh= chan[1] of string;

	convMouseCh = chan[16] of ref Pointer;
	convKbdCh   = chan[16] of int;
	convEvCh    = chan[4] of string;
	convRszCh   = chan[1] of ref Draw->Image;

	presMouseCh = chan[16] of ref Pointer;
	presKbdCh   = chan[16] of int;
	presRszCh   = chan[1] of Rect;

	ctxMouseCh  = chan[16] of ref Pointer;
	ctxEvCh     = chan[4] of string;
	ctxRszCh    = chan[1] of ref Draw->Image;

	# Layout zones and allocate sub-images + wmsrv
	r := mainwin.r;
	(convr, presr, ctxr) := zonerects(r);

	# Main screen — needed to create sub-windows
	mainscr = Screen.allocate(mainwin, bgcol, 0);

	# Sub-images for conv and ctx zones
	convimg = mainscr.newwindow(convr, Draw->Refbackup, Draw->Nofill);
	ctximg  = mainscr.newwindow(ctxr,  Draw->Refbackup, Draw->Nofill);

	# Draw initial chrome (header, separators, background)
	drawchrome(r);

	# Set up wmsrv for presentation zone
	wmsrv = load Wmsrv Wmsrv->PATH;
	if(wmsrv == nil)
		nomod(Wmsrv->PATH);
	(wmchan, join, req) := wmsrv->init();

	# Screen for pres zone (backed by pres sub-image)
	pressubimg = mainscr.newwindow(presr, Draw->Refbackup, Draw->Nofill);
	presscr = Screen.allocate(pressubimg, bgcol, 0);

	# Build Draw->Context for lucipres (pres sub-screen + wmsrv channel)
	presCtxt := ref Draw->Context(display, presscr, wmchan);

	# Spawn preswmloop
	spawn preswmloop(presscr, presr, presMouseCh, join, req, presRszCh);

	# Load and spawn zone modules
	luciconv := load LuciConv LuciConv->PATH;
	if(luciconv == nil)
		nomod(LuciConv->PATH);

	lucictx := load LuciCtx LuciCtx->PATH;
	if(lucictx == nil)
		nomod(LuciCtx->PATH);

	lucipres := load LuciPres LuciPres->PATH;
	if(lucipres == nil)
		nomod(LuciPres->PATH);
	lucipres_g = lucipres;

	# Spawn zone goroutines
	spawn luciconv->init(convimg, display, mainfont, monofont,
		mountpt, actid, convMouseCh, convKbdCh, convEvCh, convRszCh);

	spawn lucictx->init(ctximg, display, mainfont,
		mountpt, actid, ctxMouseCh, ctxEvCh, ctxRszCh);

	spawn lucipres->init(presCtxt,
		"lucipres" :: mountpt :: string actid :: nil);

	# Spawn event handlers
	spawn eventproc();
	spawn mouseproc();
	spawn kbdproc();
	if(actid >= 0)
		spawn nslistener();

	# Main loop (header redraws + quit/resize)
	mainloop();
}

# --- Zone layout ---

zonerects(r: Rect): (Rect, Rect, Rect)
{
	headerh := 40;
	zonety := r.min.y + headerh + 1;
	w := r.dx();

	convw := w * 30 / 100;
	presw := w * 45 / 100;

	convx := r.min.x;
	presx := convx + convw;
	ctxx  := presx + presw;

	# Record for mouse routing (used by mouseproc)
	pres_zone_minx = presx + 1;
	pres_zone_maxx = ctxx;
	ctx_zone_minx  = ctxx + 1;

	# Zones tile the full area below the separator with no gaps.
	# Separator pixels at exactly presx and ctxx (1px wide) are drawn by
	# drawchrome and are NOT part of any zone rect.  Every other pixel is in
	# exactly one zone sub-window, so nothing is ever left unpainted/White.
	convr := Rect((convx,     zonety), (presx,     r.max.y));
	presr := Rect((presx + 1, zonety), (ctxx,      r.max.y));
	ctxr  := Rect((ctxx + 1,  zonety), (r.max.x,   r.max.y));
	return (convr, presr, ctxr);
}

# --- Header / chrome drawing ---

drawchrome(r: Rect)
{
	# Only clear and redraw the header area — never clear zone areas.
	# The full-window clear would blank all zone sub-images and leave them
	# black until the next user interaction triggers a zone redraw.
	headerh := 40;
	headerr := Rect((r.min.x, r.min.y), (r.max.x, r.min.y + headerh));
	mainwin.draw(headerr, headercol, nil, (0, 0));

	if(mainfont != nil) {
		title := "InferNode";
		if(actlabel != nil && actlabel != "")
			title += " | " + actlabel;
		if(actstatus != nil && actstatus != "" && actstatus != "idle")
			title += " [" + actstatus + "]";
		texty := headerr.min.y + (headerh - mainfont.height) / 2;
		# Accent bar (4px left edge)
		mainwin.draw(Rect((r.min.x, r.min.y), (r.min.x + 4, r.min.y + headerh)),
			accentcol, nil, (0, 0));
		# Logo
		textx := r.min.x + 16;
		if(logoimg != nil) {
			lw := logoimg.r.dx();
			lh := logoimg.r.dy();
			logoy := headerr.min.y + (headerh - lh) / 2;
			logodst := Rect((textx, logoy), (textx + lw, logoy + lh));
			mainwin.draw(logodst, logoimg, nil, (0, 0));
			textx = textx + lw + 8;
		}
		mainwin.text((textx, texty), textcol, (0, 0), mainfont, title);
	}

	# Header/zone separator
	zonety := r.min.y + headerh + 1;
	mainwin.draw(Rect((r.min.x, zonety - 1), (r.max.x, zonety)), bordercol, nil, (0, 0));

	# Zone width calculations (must match zonerects)
	w := r.dx();
	convw := w * 30 / 100;
	presw := w * 45 / 100;
	presx := r.min.x + convw;
	ctxx  := presx + presw;

	# Zone separator lines (1px vertical)
	mainwin.draw(Rect((presx, zonety), (presx + 1, r.max.y)), bordercol, nil, (0, 0));
	mainwin.draw(Rect((ctxx,  zonety), (ctxx + 1,  r.max.y)), bordercol, nil, (0, 0));

	mainwin.flush(Draw->Flushnow);
}

# --- preswmloop — mini WM for presentation zone ---

preswmloop(scr: ref Screen, zoner: Rect,
           presMouseCh: chan of ref Pointer,
           join: chan of (ref Client, chan of string),
           req:  chan of (ref Client, array of byte, Sys->Rwrite),
           rszch: chan of Rect)
{
	client: ref Client;
	curzone := zoner;
	for(;;) alt {
	(c, rc) := <-join =>
		client = c;
		rc <-= nil;
	(c, data, rc) := <-req =>
		if(rc == nil) {
			# Client disconnected
			client = nil;
			break;
		}
		s := string data;
		n := len data;
		err: string;
		# Handle reshape: always give the full pres zone
		if(len s >= 8 && s[0:8] == "!reshape") {
			img := scr.newwindow(curzone, Draw->Refbackup, Draw->Nofill);
			if(img == nil) {
				err = "window creation failed";
				n = -1;
			} else {
				c.setimage("app", img);
			}
		}
		# "start ptr", "start kbd", "raise", etc. — just reply OK
		alt { rc <-= (n, err) => ; * => ; }
	newzoner := <-rszch =>
		curzone = newzoner;
		if(client != nil) {
			# presscr (module global) was updated by handleresize before it
			# sent to this channel — channel ordering guarantees we see the
			# new Screen backed by the new mainwin.
			img := presscr.newwindow(curzone, Draw->Refbackup, Draw->Nofill);
			if(img != nil) {
				client.setimage("app", img);
				client.ctl <-= sys->sprint("!reshape app -1 %s", r2s(curzone));
			}
		}
	p := <-presMouseCh =>
		if(client != nil)
			client.ptr <-= p;
	}
}

# --- Main loop ---

mainloop()
{
	for(;;) alt {
	p := <-cmouse =>
		if(p.buttons & M_QUIT) {
			shutdown();
			return;
		}
		if(p.buttons & M_RESIZE) {
			mainwin = win.image;
			handleresize();
		}
	<-uievent =>
		# Header redraw (status/label changed)
		drawchrome(mainwin.r);
	}
}

handleresize()
{
	r := mainwin.r;
	(convr, presr, ctxr) := zonerects(r);

	# Recreate all zone sub-images on a fresh mainscr.
	# Must happen before drawchrome so separators are drawn on top of the fill.
	mainscr = Screen.allocate(mainwin, bgcol, 0);
	convimg = mainscr.newwindow(convr, Draw->Refbackup, Draw->Nofill);
	ctximg  = mainscr.newwindow(ctxr,  Draw->Refbackup, Draw->Nofill);
	pressubimg = mainscr.newwindow(presr, Draw->Refbackup, Draw->Nofill);
	presscr = Screen.allocate(pressubimg, bgcol, 0);

	# Redraw chrome after zone allocation so separators are visible
	drawchrome(r);

	# Send new images to conv and ctx zones
	alt { convRszCh <-= convimg => ; * => ; }
	alt { ctxRszCh  <-= ctximg  => ; * => ; }

	# For pres zone: update presscr global first (preswmloop reads it),
	# then send new rect; channel ordering ensures preswmloop sees new presscr.
	alt { presRszCh <-= presr => ; * => ; }
}

shutdown()
{
	fd := sys->open("/dev/sysctl", Sys->OWRITE);
	if(fd != nil)
		sys->fprint(fd, "halt");
	wmclient->win.wmctl("exit");
}

# --- Namespace reading (header only) ---

loadlabel()
{
	s := readfile(sys->sprint("%s/activity/%d/label", mountpt, actid));
	if(s != nil)
		actlabel = strip(s);
	else
		actlabel = "";
}

loadstatus()
{
	s := readfile(sys->sprint("%s/activity/%d/status", mountpt, actid));
	if(s != nil)
		actstatus = strip(s);
	else
		actstatus = "";
}

nslistener()
{
	evpath := sys->sprint("%s/activity/%d/event", mountpt, actid);
	for(;;) {
		fd := sys->open(evpath, Sys->OREAD);
		if(fd == nil) {
			sys->sleep(1000);
			continue;
		}
		buf := array[4096] of byte;
		n := sys->read(fd, buf, len buf);
		if(n <= 0) {
			sys->sleep(500);
			continue;
		}
		ev := strip(string buf[0:n]);
		if(ev == "status") {
			loadstatus();
			alt { uievent <-= 1 => ; * => ; }
		} else if(ev == "label") {
			loadlabel();
			alt { uievent <-= 1 => ; * => ; }
		} else if(hasprefix(ev, "conversation ")) {
			alt { convEvCh <-= ev => ; * => ; }
		} else if(ev == "catalog" || hasprefix(ev, "context ")) {
			alt { ctxEvCh <-= ev => ; * => ; }
		} else if(hasprefix(ev, "presentation ")) {
			if(lucipres_g != nil)
				lucipres_g->deliverevent(ev);
		}
	}
}

# --- Event handling ---

eventproc()
{
	wmsize := startwmsize();
	for(;;) alt {
	wmsz := <-wmsize =>
		# Only resize if the window size actually changed (ignore move-only events)
		if(wmsz.max.x == mainwin.r.dx() && wmsz.max.y == mainwin.r.dy())
			break;
		win.image = win.screen.newwindow(wmsz, Draw->Refnone, Draw->Nofill);
		p := ref zpointer;
		mainwin = win.image;
		p.buttons = M_RESIZE;
		cmouse <-= p;
	e := <-win.ctl or
	e = <-win.ctxt.ctl =>
		p := ref zpointer;
		if(e == "exit") {
			p.buttons = M_QUIT;
			cmouse <-= p;
		} else {
			wmclient->win.wmctl(e);
			if(win.image != mainwin) {
				mainwin = win.image;
				p.buttons = M_RESIZE;
				cmouse <-= p;
			}
		}
	}
}

mouseproc()
{
	for(;;) {
		p := <-win.ctxt.ptr;
		if(wmclient->win.pointer(*p) == 0) {
			# Route by X position
			if(pres_zone_minx > 0 && p.xy.x >= pres_zone_minx &&
					p.xy.x < pres_zone_maxx) {
				# Presentation zone
				alt { presMouseCh <-= p => ; * => ; }
			} else if(ctx_zone_minx > 0 && p.xy.x >= ctx_zone_minx) {
				# Context zone
				alt { ctxMouseCh <-= p => ; * => ; }
			} else {
				# Conversation zone (default)
				alt { convMouseCh <-= p => ; * => ; }
			}
		}
	}
}

kbdproc()
{
	for(;;) {
		c := <-win.ctxt.kbd;
		# Quit shortcut (q when conv input is empty — handled in luciconv)
		alt { convKbdCh <-= c => ; * => ; }
	}
}

# --- WM size tracking ---

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

Wmsize: con 1 + 4*12;

wmsizeproc(sync: chan of int, fd: ref Sys->FD, ptr: chan of Rect)
{
	sync <-= sys->pctl(0, nil);
	b := array[Wmsize] of byte;
	while(sys->read(fd, b, len b) > 0) {
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
	return ref Rect((0, 0), (x, y));
}

# --- Helpers ---

r2s(r: Rect): string
{
	return sys->sprint("%d %d %d %d", r.min.x, r.min.y, r.max.x, r.max.y);
}

readfile(path: string): string
{
	fd := sys->open(path, Sys->OREAD);
	if(fd == nil)
		return nil;
	result := "";
	buf := array[8192] of byte;
	for(;;) {
		n := sys->read(fd, buf, len buf);
		if(n <= 0)
			break;
		result += string buf[0:n];
	}
	if(result == "")
		return nil;
	return result;
}

hasprefix(s, pfx: string): int
{
	return len s >= len pfx && s[0:len pfx] == pfx;
}

strip(s: string): string
{
	while(len s > 0 && (s[len s - 1] == '\n' || s[len s - 1] == ' ' || s[len s - 1] == '\t'))
		s = s[0:len s - 1];
	return s;
}

strtoint(s: string): int
{
	n := 0;
	for(i := 0; i < len s; i++) {
		c := s[i];
		if(c < '0' || c > '9')
			return -1;
		n = n * 10 + (c - '0');
	}
	if(len s == 0)
		return -1;
	return n;
}
