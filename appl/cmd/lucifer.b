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
	         rsz:   chan of ref Draw->Image,
	         req:   chan of string);
};

LuciPres: module {
	PATH: con "/dis/lucipres.dis";
	init: fn(ctxt: ref Draw->Context, args: list of string);
	deliverevent: fn(ev: string);
};

GuiApp: module {
	init: fn(ctxt: ref Draw->Context, args: list of string);
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

# wmsrv channel (module-level so launchapp can use it)
wmchan: chan of (string, chan of (string, ref Wmcontext));

# App slot tracking
#
# Each GUI app launched into the presentation zone gets one AppSlot.
# The slot tracks the app's artifact ID and its wmsrv Client handle.
# The Client is populated by preswmloop when the app sends its first join.
#
# Z-order management (show/hide):
#   Each app window is allocated ONCE at first !reshape and lives forever
#   until killapp().  Visibility is managed via Client.top() / Client.bottom()
#   which move the window up or down the Screen's z-stack without reallocating.
#
#   Client.hide() and Client.unhide() are empty stubs in wmsrv.b — do NOT call them.
#
# TODO: replace this flat slot array + appjoinch protocol with per-app wmsrv instances.
#   Currently all apps share one wmsrv (preswmloop) and the appjoinch channel provides
#   a fragile ordering guarantee: launchapp() pushes the ID *before* spawning, so
#   preswmloop sees the ID waiting when the app's first join arrives.  This breaks if
#   two apps are launched faster than the buffered channel can absorb (capacity = 4),
#   or if an app connects to wmsrv from a different goroutine family than expected.
#   Per-app wmsrv: each launchapp() calls wmsrv->init() independently, gets its own
#   (join, req) pair, spawns a dedicated bridge goroutine.  No global appjoinch needed.
AppSlot: adt {
	id:     string;
	client: ref Client;
};
MAXAPPSLOTS: con 16;
appslots: array of ref AppSlot;
nappslots := 0;
activeappid: string;	# artifact id of currently-visible app ("" = lucipres showing)

# appjoinch: ordering signal from launchapp() to preswmloop's join handler.
#
# Protocol:
#   1. launchapp() pushes id onto appjoinch (non-blocking alt — capacity 4)
#   2. launchapp() spawns the GUI app process
#   3. app calls wmlib->connect() → wmsrv join fires in preswmloop
#   4. preswmloop reads the id from appjoinch and links client → AppSlot
#
# Capacity-4 buffer: safe for sequential launches.  Concurrent launches of >4 apps
# before any join fires would corrupt the id→client mapping.
# TODO: eliminate this channel by using per-app wmsrv instances (see AppSlot TODO above).
appjoinch: chan of string;

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

# Zone layout percentages (default; modified by ctx expand/restore)
conv_pct := 30;
pres_pct := 45;

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

# Context zone expand/restore request channel
ctxreqch: chan of string;

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

	# Remove stale wmready sentinel from a previous run, then immediately
	# write the new one.  The sentinel only signals "lucifer process is alive";
	# tools9p and lucibridge must start regardless of display/WM setup outcome.
	#
	# Use /usr/inferno/tmp/ (emu root filesystem, not trfs-backed /tmp).
	# trfs has a negative lookup cache: after sys->remove deletes the old
	# sentinel, subsequent cat calls can get a cached "not found" even after
	# sys->create writes the new one.  The emu root filesystem has no such
	# cache — reads and writes are immediately coherent.
	sys->remove("/usr/inferno/tmp/lucifer-wmready");
	{
		rfd := sys->create("/usr/inferno/tmp/lucifer-wmready", Sys->OWRITE, 8r644);
		if(rfd == nil)
			sys->fprint(sys->fildes(2), "lucifer: warning: cannot create wmready sentinel: %r\n");
		rfd = nil;
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
	ctxreqch    = chan[1] of string;

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
	(wmc, join, req) := wmsrv->init();
	wmchan = wmc;

	# Screen for pres zone (backed by pres sub-image)
	pressubimg = mainscr.newwindow(presr, Draw->Refbackup, Draw->Nofill);
	presscr = Screen.allocate(pressubimg, bgcol, 0);

	# Publish pressubimg by name so namedimage() works cross-connection
	pressubimg.name("lucifer-pres", 1);

	# Init app slot infrastructure
	appslots = array[MAXAPPSLOTS] of ref AppSlot;
	nappslots = 0;
	activeappid = "";
	appjoinch = chan[4] of string;

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
		mountpt, actid, ctxMouseCh, ctxEvCh, ctxRszCh, ctxreqch);

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

	convw := w * conv_pct / 100;
	presw := w * pres_pct / 100;

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
	convw := w * conv_pct / 100;
	presw := w * pres_pct / 100;
	presx := r.min.x + convw;
	ctxx  := presx + presw;

	# Zone separator lines (1px vertical)
	mainwin.draw(Rect((presx, zonety), (presx + 1, r.max.y)), bordercol, nil, (0, 0));
	mainwin.draw(Rect((ctxx,  zonety), (ctxx + 1,  r.max.y)), bordercol, nil, (0, 0));

	mainwin.flush(Draw->Flushnow);
}

# --- preswmloop — mini WM for presentation zone ---
#
# Architecture:
#   preswmloop is a hand-rolled WM server for the presentation zone.  It multiplexes
#   exactly one wmsrv instance across two kinds of clients:
#
#   1. lucipres (first join):
#      Gets the full zone rect.  Draws the tab strip + artifact content.
#      Always present; its window is at z-order bottom (z=1).
#
#   2. GUI app clients (subsequent joins, one per app):
#      Gets the content-area rect (below the tab strip) so the tab strip stays visible.
#      Each app window is allocated ONCE at first !reshape.
#      Visibility is controlled by Client.top() / Client.bottom() (z-order), never by
#      recreating windows.  Creating a new window via Screen.newwindow() for every
#      show/hide causes accumulating ghost windows (old windows linger under GC) that
#      overdraw lucipres content — this was the original "clock floating on mermaid" bug.
#
# Mouse routing:
#   Tab strip (top mainfont.height+13 pixels) → always lucipres (tab clicks/scrolls)
#   Content area → active app if one is showing, otherwise lucipres
#
# Keyboard routing:
#   Currently all keyboard events go to the conv zone (convKbdCh).
#   TODO: route keyboard to active app when an app is foregrounded.
#         This requires preswmloop to hold a presKbdCh ref and check activeappid.
#
# Resize:
#   handleresize() sends a new Rect on rszch.  preswmloop reallocates ALL client
#   windows (lucipres + every app slot).  This is correct but creates new windows
#   rather than resizing in-place — see newwindow() note above.
#   TODO: Screen.newwindow() returns a fresh window; old window should be explicitly
#         flushed (e.g. fill with bg color) before replace, to avoid resize flicker.
#
# Limitations (known fragile points):
#   - Only one wmsrv instance is shared by all apps; app context menus, iconify, etc.
#     are not meaningfully supported (all req messages get a generic OK reply).
#   - appjoinch is a 4-slot buffer; launching >4 apps faster than joins arrive corrupts
#     the id→client mapping.
#   - Client.hide() / Client.unhide() in wmsrv.b are empty stubs — never call them.

preswmloop(scr: ref Screen, zoner: Rect,
           presMouseCh: chan of ref Pointer,
           join: chan of (ref Client, chan of string),
           req:  chan of (ref Client, array of byte, Sys->Rwrite),
           rszch: chan of Rect)
{
	lucipresclient: ref Client;
	curzone := zoner;
	for(;;) alt {
	(c, rc) := <-join =>
		if(lucipresclient == nil) {
			# First join = lucipres
			lucipresclient = c;
		} else {
			# Subsequent join = an app; register its client in the app slot
			appid2 := "";
			alt { appid2 = <-appjoinch => ; * => ; }
			if(appid2 != "") {
				for(asi := 0; asi < nappslots; asi++) {
					if(appslots[asi] != nil && appslots[asi].id == appid2) {
						appslots[asi].client = c;
						break;
					}
				}
			}
		}
		rc <-= nil;
	(c, data, rc) := <-req =>
		if(rc == nil) {
			# Client disconnected — clear from lucipres slot or app slot
			if(c == lucipresclient)
				lucipresclient = nil;
			else {
				for(asi2 := 0; asi2 < nappslots; asi2++) {
					if(appslots[asi2] != nil && appslots[asi2].client == c) {
						appslots[asi2].client = nil;
						break;
					}
				}
			}
			break;
		}
		s := string data;
		n := len data;
		err: string;
		# !reshape: allocate window on first connect only.
		# Subsequent reshapes for apps are ignored (z-order managed via top/bottom).
		if(len s >= 8 && s[0:8] == "!reshape") {
			if(c == lucipresclient) {
				img := scr.newwindow(curzone, Draw->Refbackup, Draw->Nofill);
				if(img == nil) {
					err = "window creation failed";
					n = -1;
				} else
					c.setimage("app", img);
			} else if(c.image("app") == nil) {
				# First reshape for this app: allocate content-area window
				tabh2 := 0;
				if(mainfont != nil) tabh2 = mainfont.height + 13;
				appr := Rect((curzone.min.x, curzone.min.y + tabh2), curzone.max);
				img := scr.newwindow(appr, Draw->Refbackup, Draw->Nofill);
				if(img == nil) {
					err = "window creation failed";
					n = -1;
				} else
					c.setimage("app", img);
				# App starts at top; handleprescurrent() will call bottom() if needed
			}
			# else: app already has a window — ignore re-reshape
		}
		# All other req messages ("start ptr", "start kbd", "raise", etc.) — reply OK
		alt { rc <-= (n, err) => ; * => ; }
	newzoner := <-rszch =>
		curzone = newzoner;
		# Resize lucipres window (full zone)
		if(lucipresclient != nil) {
			# presscr (module global) was updated by handleresize before sending
			img := presscr.newwindow(curzone, Draw->Refbackup, Draw->Nofill);
			if(img != nil) {
				lucipresclient.setimage("app", img);
				lucipresclient.ctl <-= sys->sprint("!reshape app -1 %s", r2s(curzone));
			}
		}
		# Resize app windows (content area)
		tabh3 := 0;
		if(mainfont != nil) tabh3 = mainfont.height + 13;
		appr2 := Rect((curzone.min.x, curzone.min.y + tabh3), curzone.max);
		for(asi3 := 0; asi3 < nappslots; asi3++) {
			if(appslots[asi3] != nil && appslots[asi3].client != nil) {
				img3 := presscr.newwindow(appr2, Draw->Refbackup, Draw->Nofill);
				if(img3 != nil) {
					appslots[asi3].client.setimage("app", img3);
					appslots[asi3].client.ctl <-= sys->sprint("!reshape app -1 %s", r2s(appr2));
				}
			}
		}
	p := <-presMouseCh =>
		# Tab strip (top N px) always routes to lucipres;
		# content area routes to active app or lucipres.
		tabh_m := 0;
		if(mainfont != nil) tabh_m = mainfont.height + 13;
		if(p.xy.y < curzone.min.y + tabh_m) {
			# Tab strip: always deliver to lucipres
			if(lucipresclient != nil)
				lucipresclient.ptr <-= p;
		} else {
			# Content area: active app or lucipres
			actclient: ref Client;
			for(masi := 0; masi < nappslots; masi++) {
				if(appslots[masi] != nil && appslots[masi].id == activeappid &&
						appslots[masi].client != nil) {
					actclient = appslots[masi].client;
					break;
				}
			}
			if(actclient == nil)
				actclient = lucipresclient;
			if(actclient != nil)
				actclient.ptr <-= p;
		}
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
	req := <-ctxreqch =>
		if(req == "expand")
			handlectxlayout(25, 35);
		else if(req == "restore")
			handlectxlayout(30, 45);
	}
}

handlectxlayout(cp, pp: int)
{
	conv_pct = cp;
	pres_pct = pp;
	handleresize();
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
	pressubimg.name("lucifer-pres", 1);

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
			# Always deliver to lucipres for tab/artifact updates
			if(lucipres_g != nil)
				lucipres_g->deliverevent(ev);
			# Additional handling for app lifecycle events
			if(hasprefix(ev, "presentation new ")) {
				newid := strip(ev[len "presentation new ":]);
				if(newid != "")
					checklaunchapp(newid);
			} else if(hasprefix(ev, "presentation kill ")) {
				killid := strip(ev[len "presentation kill ":]);
				if(killid != "")
					killapp(killid);
			} else if(ev == "presentation current") {
				handleprescurrent();
			}
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

sendinput(text: string)
{
	if(actid < 0)
		return;
	# Show the human message immediately without waiting for lucibridge echo
	messages = appendmsg(messages, ref ConvMsg("human", text, nil, nil));
	nmsg++;
	scrollpx = 0;
	alt { uievent <-= 1 => ; * => ; }
	# Send to lucibridge (it will echo back as role=human; loadmessage deduplicates)
	path := sys->sprint("%s/activity/%d/conversation/input", mountpt, actid);
	fd := sys->open(path, Sys->OWRITE);
	if(fd == nil) {
		sys->fprint(stderr, "lucifer: can't open %s: %r\n", path);
		return;
	}
	b := array of byte text;
	sys->write(fd, b, len b);
}

# --- Drawing ---

redraw()
{
	if(mainwin == nil)
		return;

	r := mainwin.r;
	w := r.dx();

	# Fill background
	mainwin.draw(r, bgcol, nil, (0, 0));

	# Header bar (40px)
	headerh := 40;
	headerr := Rect((r.min.x, r.min.y), (r.max.x, r.min.y + headerh));
	mainwin.draw(headerr, headercol, nil, (0, 0));

	# Header text and logo
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
		# Logo (after accent bar, before title)
		textx := r.min.x + 16;
		if(logoimg != nil) {
			lw := logoimg.r.dx();
			lh := logoimg.r.dy();
			logoy := headerr.min.y + (headerh - lh) / 2;
			logodst := Rect((textx, logoy), (textx + lw, logoy + lh));
			mainwin.draw(logodst, logoimg, nil, (0, 0));
			textx = textx + lw + 8;
		}
		# Title
		mainwin.text((textx, texty), textcol, (0, 0), mainfont, title);
	}

	# Zone layout below header
	zonety := r.min.y + headerh + 1;
	# Draw header/zone separator
	mainwin.draw(Rect((r.min.x, zonety - 1), (r.max.x, zonety)), bordercol, nil, (0, 0));

	# Zone widths: conversation ~30%, presentation ~45%, context ~25%
	convw := w * 30 / 100;
	presw := w * 45 / 100;

	convx := r.min.x;
	presx := convx + convw;
	ctxx := presx + presw;

	# Draw zone separators (1px vertical lines)
	mainwin.draw(Rect((presx, zonety), (presx + 1, r.max.y)), bordercol, nil, (0, 0));
	mainwin.draw(Rect((ctxx, zonety), (ctxx + 1, r.max.y)), bordercol, nil, (0, 0));

	# Record presentation zone x-boundaries for scroll and click routing
	pres_zone_minx = presx + 2;
	pres_zone_maxx = ctxx - 1;

	if(mainfont != nil) {
		contenty := zonety + 4;

		# Draw the three zones
		drawconversation(Rect((convx, contenty), (presx - 1, r.max.y)));
		drawpresentation(Rect((presx + 2, contenty), (ctxx - 1, r.max.y)));
		drawcontext(Rect((ctxx + 2, contenty), (r.max.x, r.max.y)));
	}

	mainwin.flush(Draw->Flushnow);
}

# --- Conversation zone ---

drawconversation(zone: Rect)
{
	pad := 8;
	inputh := mainfont.height + 2 * pad;
	msgy := zone.max.y - inputh - 2;	# bottom of message area

	# Draw input field at bottom
	inputr := Rect((zone.min.x + pad, zone.max.y - inputh),
		(zone.max.x - pad, zone.max.y));
	mainwin.draw(inputr, inputcol, nil, (0, 0));

	# Input text
	itext := inputbuf;
	itx := inputr.min.x + pad;
	ity := inputr.min.y + (inputh - mainfont.height) / 2;
	maxitw := inputr.dx() - 2 * pad - 8;	# leave room for cursor

	# Truncate from left if too wide
	while(len itext > 0 && mainfont.width(itext) > maxitw)
		itext = itext[1:];
	mainwin.text((itx, ity), textcol, (0, 0), mainfont, itext);

	# Block cursor after text
	cw := 8;
	ch := mainfont.height;
	cx := itx + mainfont.width(itext);
	cy := ity;
	mainwin.draw(Rect((cx, cy), (cx + cw, cy + ch)), cursorcol, nil, (0, 0));

	# Draw messages bottom-up from msgy
	if(messages == nil) {
		drawcentertext(Rect((zone.min.x, zone.min.y), (zone.max.x, msgy)),
			"No messages yet");
		return;
	}

	# Reset tile layout for this frame
	tilelayout = array[nmsg + 1] of ref TileRect;
	ntiles = 0;

	# Tile layout parameters
	tilegap := 4;
	tpadv := 3;			# vertical padding only — no horizontal indent
	tilew := zone.dx() - 2 * pad;	# full width, both roles
	tilex := zone.min.x + pad;	# same left edge for both roles

	# Invalidate rlayout image cache when tile width changes (e.g. resize)
	if(tilew != lastrendw) {
		for(ml := messages; ml != nil; ml = tl ml)
			(hd ml).rendimg = nil;
		lastrendw = tilew;
	}

	# Get messages as array for indexed access
	marr := msgstoarray(messages, nmsg);

	# Pass 1: Estimate heights without calling rlayout (fast path).
	# Use cached image height for rendered messages; wraptext estimate otherwise.
	harr := array[nmsg] of int;
	total_h := 0;
	for(pi := 0; pi < nmsg; pi++) {
		imgh: int;
		if(marr[pi].rendimg != nil)
			imgh = marr[pi].rendimg.r.dy();
		else {
			ls := wraptext(marr[pi].text, tilew - 8);
			n := 0;
			for(wl := ls; wl != nil; wl = tl wl)
				n++;
			imgh = n * mainfont.height;
		}
		harr[pi] = mainfont.height + imgh + 2 * tpadv;
		total_h += harr[pi] + tilegap;
	}

	# Update viewport height and pixel scroll bounds using estimated heights.
	viewport_h = msgy - zone.min.y;
	newmax := total_h - viewport_h;
	if(newmax < 0)
		newmax = 0;
	maxscrollpx = newmax;
	if(scrollpx > maxscrollpx)
		scrollpx = maxscrollpx;

	# Pass 2: Render only messages visible in the current viewport.
	# Walk bottom-up to find visible range, then call rlayout only for those.
	codebg := display.color(int 16r1A1A2AFF);
	ey := msgy + scrollpx;
	for(ri := nmsg - 1; ri >= 0; ri--) {
		tiletop_e := ey - harr[ri] - tilegap;
		# Below viewport — skip
		if(tiletop_e >= msgy) {
			ey = tiletop_e;
			continue;
		}
		# Above viewport — stop
		if(tiletop_e + harr[ri] <= zone.min.y)
			break;
		# In viewport — render if not yet cached
		if(marr[ri].rendimg == nil && rlay != nil) {
			human_r := marr[ri].role == "human";
			bgc_r: ref Image;
			if(human_r) bgc_r = humancol; else bgc_r = veltrocol;
			style_r := ref Rlayout->Style(
				tilew, 4,
				mainfont, monofont,
				textcol, bgc_r, accentcol, codebg,
				100
			);
			(img, nil) := rlay->render(rlay->parsemd(marr[ri].text), style_r);
			marr[ri].rendimg = img;
			# Update height estimate with actual rendered height
			if(img != nil) {
				harr[ri] = mainfont.height + img.r.dy() + 2 * tpadv;
			}
		}
		ey = tiletop_e;
	}

	# Draw messages bottom-up using pixel offset
	y := msgy + scrollpx;		# effective viewport floor
	for(i := nmsg - 1; i >= 0; i--) {
		tileh := harr[i];
		tiletop := y - tileh - tilegap;

		# Completely below visible area — skip
		if(tiletop >= msgy) {
			y = tiletop;
			continue;
		}
		# Completely above visible area — stop
		if(tiletop + tileh <= zone.min.y)
			break;

		msg := marr[i];
		human := msg.role == "human";
		tilecol: ref Image;
		rolecol: ref Image;
		if(human) {
			tilecol = humancol;
			rolecol = text2col;
		} else {
			tilecol = veltrocol;
			rolecol = accentcol;
		}

		# Draw tile background clamped to visible area
		drawtop := tiletop;
		if(drawtop < zone.min.y) drawtop = zone.min.y;
		drawbot := tiletop + tileh;
		if(drawbot > msgy) drawbot = msgy;
		if(drawtop < drawbot) {
			tiler := Rect((tilex, drawtop), (tilex + tilew, drawbot));
			mainwin.draw(tiler, tilecol, nil, (0, 0));
		}
		if(ntiles < len tilelayout)
			tilelayout[ntiles++] = ref TileRect(Rect((tilex, tiletop), (tilex + tilew, tiletop + tileh)), msg);

		# Role label (skip if outside visible area)
		ty := tiletop + tpadv;
		rolelabel := msg.role;
		if(human)
			rolelabel = username;
		if(ty >= zone.min.y && ty + mainfont.height <= msgy) {
			if(human)
				mainwin.text((tilex + tilew - mainfont.width(rolelabel), ty), rolecol, (0, 0), mainfont, rolelabel);
			else
				mainwin.text((tilex, ty), rolecol, (0, 0), mainfont, rolelabel);
		}
		ty += mainfont.height;

		# Composite the rlayout-rendered markdown image (clipped to viewport)
		if(msg.rendimg != nil) {
			imgh := msg.rendimg.r.dy();
			srcy := 0;
			dsty := ty;
			if(dsty < zone.min.y) {
				srcy = zone.min.y - dsty;
				dsty = zone.min.y;
			}
			enddsty := ty + imgh;
			if(enddsty > msgy) enddsty = msgy;
			if(dsty < enddsty)
				mainwin.draw(Rect((tilex, dsty), (tilex + tilew, enddsty)),
					msg.rendimg, nil, (0, srcy));
		}

		y = tiletop;
	}
}

# --- Presentation zone ---

drawpresentation(zone: Rect)
{
	pad := 8;
	al: list of ref Artifact;
	centart: ref Artifact;

	# Find the centered artifact
	centart = nil;
	for(al = artifacts; al != nil; al = tl al) {
		if((hd al).id == centeredart) {
			centart = hd al;
			break;
		}
	}
	# Default to first artifact when none is centered
	if(centart == nil) {
		if(artifacts != nil)
			centart = hd artifacts;
	}

	if(centart == nil) {
		drawcentertext(zone, "No artifacts");
		return;
	}

	# Tab strip at top (artifact labels as navigation tabs)
	tabh := mainfont.height + 12;
	tabr := Rect((zone.min.x, zone.min.y), (zone.max.x, zone.min.y + tabh));
	mainwin.draw(tabr, headercol, nil, (0, 0));

	# Reset tab hit layout for this frame
	tablayout = array[nart + 1] of ref TabRect;
	ntabs = 0;

	tx := zone.min.x + pad;
	for(al = artifacts; al != nil; al = tl al) {
		art := hd al;
		tw := mainfont.width(art.label);
		if(tx + tw + pad > zone.max.x)
			break;
		active := 0;
		if(art.id == centart.id)
			active = 1;
		tcol := text2col;
		if(active) {
			tcol = textcol;
			# Accent underline for active tab
			mainwin.draw(Rect((tx, tabr.max.y - 3), (tx + tw, tabr.max.y - 1)),
				accentcol, nil, (0, 0));
		}
		mainwin.text((tx, tabr.min.y + 6), tcol, (0, 0), mainfont, art.label);
		# Record tab hit rect (full tab-bar height, label width + inter-tab gap)
		if(ntabs < len tablayout)
			tablayout[ntabs++] = ref TabRect(
				Rect((tx, tabr.min.y), (tx + tw + 20, tabr.max.y)), art.id);
		tx += tw + 20;
	}

	# Separator line below tab strip
	mainwin.draw(Rect((zone.min.x, tabr.max.y), (zone.max.x, tabr.max.y + 1)),
		bordercol, nil, (0, 0));

	# Content area below tab strip
	contentr := Rect((zone.min.x, tabr.max.y + 1), (zone.max.x, zone.max.y));
	contentw := contentr.dx() - 2 * pad;

	# Invalidate all render caches when zone width changes (e.g. window resize)
	if(contentw != artrendw) {
		for(al = artifacts; al != nil; al = tl al)
			(hd al).rendimg = nil;
		artrendw = contentw;
	}

	contenty := contentr.min.y + pad;

	# Update viewport height for presentation scroll bounds
	pres_viewport_h = contentr.dy() - 2 * pad;

	case centart.atype {
	"markdown" or "doc" =>
		# Render with rlayout for rich markdown content
		if(centart.rendimg == nil)
		if(rlay != nil)
		if(centart.data != "") {
			codebg := display.color(int 16r1A1A2AFF);
			style := ref Rlayout->Style(
				contentw, 4,
				mainfont, monofont,
				textcol, bgcol, accentcol, codebg,
				100
			);
			(img, nil) := rlay->render(rlay->parsemd(centart.data), style);
			centart.rendimg = img;
		}
		if(centart.rendimg != nil) {
			imgh := centart.rendimg.r.dy();
			newmax := imgh - pres_viewport_h;
			if(newmax < 0) newmax = 0;
			maxpresscrollpx = newmax;
			if(presscrollpx > maxpresscrollpx)
				presscrollpx = maxpresscrollpx;
			srcy := presscrollpx;
			dsty := contentr.min.y + pad;
			enddsty := dsty + (imgh - srcy);
			if(enddsty > contentr.max.y) enddsty = contentr.max.y;
			if(dsty < enddsty)
				mainwin.draw(
					Rect((contentr.min.x + pad, dsty),
					     (contentr.min.x + pad + contentw, enddsty)),
					centart.rendimg, nil, (0, srcy));
		} else
			drawcentertext(contentr, "(empty)");
	"text" or "code" =>
		# Direct monofont rendering — preserves whitespace and line structure
		if(centart.atype == "code") {
			codebg2 := display.color(int 16r1A1A2AFF);
			mainwin.draw(contentr, codebg2, nil, (0, 0));
		}
		ls := splitlines(centart.data);
		total_h := listlen(ls) * monofont.height;
		newmax2 := total_h - pres_viewport_h;
		if(newmax2 < 0) newmax2 = 0;
		maxpresscrollpx = newmax2;
		if(presscrollpx > maxpresscrollpx)
			presscrollpx = maxpresscrollpx;
		y2 := contenty - presscrollpx;
		wl: list of string;
		for(wl = ls; wl != nil; wl = tl wl) {
			if(y2 + monofont.height > contentr.max.y)
				break;
			if(y2 >= contentr.min.y)
				mainwin.text((contentr.min.x + pad, y2),
					textcol, (0, 0), monofont, hd wl);
			y2 += monofont.height;
		}
		if(centart.data == "")
			drawcentertext(contentr, "(empty)");
	"pdf" =>
		# Render PDF file — centart.data is the file path; page 0 cached in rendimg
		if(centart.rendimg == nil)
			centart.rendimg = renderpdfpage(centart.data);
		if(centart.rendimg != nil) {
			imgh3 := centart.rendimg.r.dy();
			newmax3 := imgh3 - pres_viewport_h;
			if(newmax3 < 0) newmax3 = 0;
			maxpresscrollpx = newmax3;
			if(presscrollpx > maxpresscrollpx)
				presscrollpx = maxpresscrollpx;
			srcy3 := presscrollpx;
			dsty3 := contentr.min.y + pad;
			enddsty3 := dsty3 + (imgh3 - srcy3);
			if(enddsty3 > contentr.max.y) enddsty3 = contentr.max.y;
			if(dsty3 < enddsty3)
				mainwin.draw(
					Rect((contentr.min.x + pad, dsty3),
					     (contentr.min.x + pad + contentw, enddsty3)),
					centart.rendimg, nil, (0, srcy3));
		} else
			drawcentertext(contentr, "cannot render PDF");
	"image" =>
		# Render image file (PNG) — centart.data is the file path; cached in rendimg
		if(centart.rendimg == nil) {
			bufio2 := load Bufio Bufio->PATH;
			readpng2 := load RImagefile RImagefile->READPNGPATH;
			remap2 := load Imageremap Imageremap->PATH;
			if(bufio2 != nil && readpng2 != nil && remap2 != nil) {
				readpng2->init(bufio2);
				remap2->init(display);
				fd2 := bufio2->open(centart.data, Bufio->OREAD);
				if(fd2 != nil) {
					(raw2, nil) := readpng2->read(fd2);
					if(raw2 != nil)
						(centart.rendimg, nil) = remap2->remap(raw2, display, 0);
				}
			}
		}
		if(centart.rendimg != nil) {
			imgh4 := centart.rendimg.r.dy();
			newmax4 := imgh4 - pres_viewport_h;
			if(newmax4 < 0) newmax4 = 0;
			maxpresscrollpx = newmax4;
			if(presscrollpx > maxpresscrollpx)
				presscrollpx = maxpresscrollpx;
			srcy4 := presscrollpx;
			dsty4 := contentr.min.y + pad;
			enddsty4 := dsty4 + (imgh4 - srcy4);
			if(enddsty4 > contentr.max.y) enddsty4 = contentr.max.y;
			if(dsty4 < enddsty4)
				mainwin.draw(
					Rect((contentr.min.x + pad, dsty4),
					     (contentr.min.x + pad + contentw, enddsty4)),
					centart.rendimg, nil, (0, srcy4));
		} else
			drawcentertext(contentr, "cannot render image");
	* =>
		# Other types: show type badge + wrapped plain text (no scroll)
		if(centart.atype != "") {
			mainwin.text((contentr.min.x + pad, contenty),
				labelcol, (0, 0), mainfont, "[" + centart.atype + "]");
			contenty += mainfont.height + 4;
		}
		if(centart.data == "")
			drawcentertext(contentr, "(empty)");
		else {
			ls2 := wraptext(centart.data, contentw);
			wl2: list of string;
			for(wl2 = ls2; wl2 != nil; wl2 = tl wl2) {
				if(contenty + mainfont.height > contentr.max.y)
					break;
				mainwin.text((contentr.min.x + pad, contenty),
					textcol, (0, 0), mainfont, hd wl2);
				contenty += mainfont.height;
			}
		}
	}
}

# --- Context zone ---

drawcontext(zone: Rect)
{
	pad := 8;
	y := zone.min.y + pad;
	secgap := 12;
	indw := 10;	# status indicator width
	indh := 10;	# status indicator height

	# --- Resources section ---
	if(resources != nil) {
		mainwin.text((zone.min.x + pad, y), labelcol, (0, 0), mainfont, "Resources");
		y += mainfont.height + 4;

		for(r := resources; r != nil; r = tl r) {
			res := hd r;
			if(y + mainfont.height > zone.max.y)
				break;

			# Status indicator (small filled rect)
			indcol := dimcol;
			if(res.status == "streaming")
				indcol = greencol;
			else if(res.status == "stale")
				indcol = yellowcol;
			else if(res.status == "offline" || res.status == "error")
				indcol = redcol;

			indy := y + (mainfont.height - indh) / 2;
			mainwin.draw(Rect(
				(zone.min.x + pad, indy),
				(zone.min.x + pad + indw, indy + indh)),
				indcol, nil, (0, 0));

			# Label
			label := res.label;
			if(label == nil || label == "")
				label = res.path;
			mainwin.text((zone.min.x + pad + indw + 6, y),
				text2col, (0, 0), mainfont, label);
			y += mainfont.height + 2;
		}
		y += secgap;
	}

	# --- Gaps section ---
	if(gaps != nil) {
		if(y + mainfont.height > zone.max.y)
			return;
		mainwin.text((zone.min.x + pad, y), labelcol, (0, 0), mainfont, "Gaps");
		y += mainfont.height + 4;

		for(g := gaps; g != nil; g = tl g) {
			gap := hd g;
			if(y + mainfont.height > zone.max.y)
				break;
			desc := gap.desc;
			if(gap.relevance != nil && gap.relevance != "")
				desc += " [" + gap.relevance + "]";
			mainwin.text((zone.min.x + pad, y), text2col, (0, 0), mainfont, desc);
			y += mainfont.height + 2;
		}
		y += secgap;
	}

	# --- Background tasks section ---
	if(bgtasks != nil) {
		if(y + mainfont.height > zone.max.y)
			return;
		mainwin.text((zone.min.x + pad, y), labelcol, (0, 0), mainfont, "Background");
		y += mainfont.height + 4;

		barh := 6;
		for(b := bgtasks; b != nil; b = tl b) {
			bg := hd b;
			if(y + mainfont.height + barh + 4 > zone.max.y)
				break;

			# Task label + status
			label := bg.label;
			if(bg.status != nil && bg.status != "")
				label += " [" + bg.status + "]";
			mainwin.text((zone.min.x + pad, y), text2col, (0, 0), mainfont, label);
			y += mainfont.height + 2;

			# Progress bar
			if(bg.progress != nil && bg.progress != "") {
				pct := strtoint(bg.progress);
				if(pct < 0)
					pct = 0;
				if(pct > 100)
					pct = 100;
				barw := zone.dx() - 2 * pad;
				bary := y;
				# Background
				mainwin.draw(Rect(
					(zone.min.x + pad, bary),
					(zone.min.x + pad + barw, bary + barh)),
					progbgcol, nil, (0, 0));
				# Fill
				fillw := barw * pct / 100;
				if(fillw > 0)
					mainwin.draw(Rect(
						(zone.min.x + pad, bary),
						(zone.min.x + pad + fillw, bary + barh)),
						progfgcol, nil, (0, 0));
				y += barh + 4;
			}
		}
	}

	# Empty state
	if(resources == nil && gaps == nil && bgtasks == nil)
		drawcentertext(zone, "No context");
}

drawcentertext(r: Rect, text: string)
{
	tw := mainfont.width(text);
	tx := r.min.x + (r.dx() - tw) / 2;
	ty := r.min.y + (r.dy() - mainfont.height) / 2;
	mainwin.text((tx, ty), dimcol, (0, 0), mainfont, text);
}

# --- Word wrapping ---

wraptext(text: string, maxw: int): list of string
{
	if(text == nil || text == "")
		return "" :: nil;

	lines: list of string;
	line := "";

	i := 0;
	while(i < len text) {
		# Find next word
		while(i < len text && (text[i] == ' ' || text[i] == '\t'))
			i++;
		if(i >= len text)
			break;
		wstart := i;
		while(i < len text && text[i] != ' ' && text[i] != '\t' && text[i] != '\n')
			i++;
		word := text[wstart:i];

		# Handle newline
		if(i < len text && text[i] == '\n') {
			if(line != "")
				line += " " + word;
			else
				line = word;
			lines = line :: lines;
			line = "";
			i++;
			continue;
		}

		# Check if word fits on current line
		candidate: string;
		if(line != "")
			candidate = line + " " + word;
		else
			candidate = word;

		if(mainfont.width(candidate) > maxw && line != "") {
			# Wrap: current line is done, start new with word
			lines = line :: lines;
			line = word;
		} else {
			line = candidate;
		}
	}
	if(line != "")
		lines = line :: lines;
	if(lines == nil)
		return "" :: nil;

	# Reverse to correct order
	rev: list of string;
	for(; lines != nil; lines = tl lines)
		rev = hd lines :: rev;
	return rev;
}

# --- Attribute parsing ---
# Same format as luciuisrv: "key1=val1 key2=val2"

Attr: adt {
	key: string;
	val: string;
};

parseattrs(s: string): list of ref Attr
{
	kstarts := array[32] of int;
	eqposs := array[32] of int;
	nkp := 0;

	i := 0;
	while(i < len s && (s[i] == ' ' || s[i] == '\t'))
		i++;

	j := i;
	while(j < len s) {
		if(s[j] == '=') {
			kstart := j - 1;
			while(kstart > i && s[kstart - 1] != ' ' && s[kstart - 1] != '\t')
				kstart--;
			if(kstart >= 0 && kstart < j) {
				if(kstart == 0 || kstart == i || s[kstart - 1] == ' ' || s[kstart - 1] == '\t') {
					if(nkp >= len kstarts) {
						nks := array[len kstarts * 2] of int;
						nks[0:] = kstarts[0:nkp];
						kstarts = nks;
						neq := array[len eqposs * 2] of int;
						neq[0:] = eqposs[0:nkp];
						eqposs = neq;
					}
					kstarts[nkp] = kstart;
					eqposs[nkp] = j;
					nkp++;
				}
			}
		}
		j++;
	}

	attrs: list of ref Attr;
	for(k := 0; k < nkp; k++) {
		key := s[kstarts[k]:eqposs[k]];
		vstart := eqposs[k] + 1;
		vend: int;
		if(k + 1 < nkp) {
			vend = kstarts[k + 1];
			while(vend > vstart && (s[vend - 1] == ' ' || s[vend - 1] == '\t'))
				vend--;
		} else
			vend = len s;
		val := "";
		if(vstart < vend)
			val = s[vstart:vend];
		attrs = ref Attr(key, val) :: attrs;
	}

	rev: list of ref Attr;
	for(; attrs != nil; attrs = tl attrs)
		rev = hd attrs :: rev;
	return rev;
}

getattr(attrs: list of ref Attr, key: string): string
{
	for(; attrs != nil; attrs = tl attrs)
		if((hd attrs).key == key)
			return (hd attrs).val;
	return nil;
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

# --- Presentation zone WM namespace goroutines ---

# presWMns: serve /n/pres-clone and /n/pres-winname (connect/identity protocol)
presWMns(cloneIO, winnameIO: ref Sys->FileIO)
{
	for(;;) alt {
	(off, cnt, fid, rc) := <-cloneIO.read =>
		if(rc != nil) {
			data := array of byte "ready";
			if(off < len data)
				rc <-= (data[off:], nil);
			else
				rc <-= (array[0] of byte, nil);
		}
	(off, wdata, fid, wc) := <-cloneIO.write =>
		if(wc != nil) wc <-= (len wdata, nil);
	(off, cnt, fid, rc) := <-winnameIO.read =>
		if(rc != nil) {
			data := array of byte "lucifer-pres";
			if(off < len data)
				rc <-= (data[off:], nil);
			else
				rc <-= (array[0] of byte, nil);
		}
	(off, wdata, fid, wc) := <-winnameIO.write =>
		if(wc != nil) wc <-= (len wdata, nil);
	}
}

# presPointerSrv: serve /n/pres-pointer — blocks until mouse event, encodes it
presPointerSrv(io: ref Sys->FileIO)
{
	for(;;) {
		(off, cnt, fid, rc) := <-io.read;
		if(rc == nil)
			continue;
		p := <-presMouseCh;
		s := sys->sprint("m%11d %11d %11d %11d",
			p.xy.x, p.xy.y, p.buttons, p.msec);
		alt { rc <-= (array of byte s, nil) => ; * => ; }
	}
}

# presKbdSrv: serve /n/pres-keyboard — blocks until key event, returns UTF-8 rune
presKbdSrv(io: ref Sys->FileIO)
{
	for(;;) {
		(off, cnt, fid, rc) := <-io.read;
		if(rc == nil)
			continue;
		k := <-presKbdCh;
		alt { rc <-= (array of byte string(k), nil) => ; * => ; }
	}
}


# --- App lifecycle management ---

# writetofile: write a string to a file path
writetofile(path, data: string): string
{
	fd := sys->open(path, Sys->OWRITE);
	if(fd == nil)
		return sys->sprint("cannot open %s: %r", path);
	b := array of byte data;
	n := sys->write(fd, b, len b);
	if(n < 0)
		return sys->sprint("write failed: %r");
	return nil;
}

# writeappstatus: write appstatus to luciuisrv ctl and deliver event to lucipres
writeappstatus(id, status: string)
{
	if(actid < 0) return;
	writetofile(sys->sprint("%s/activity/%d/presentation/ctl", mountpt, actid),
		"appstatus id=" + id + " status=" + status);
	if(lucipres_g != nil)
		lucipres_g->deliverevent("presentation app " + id + " status=" + status);
}

# checklaunchapp: called when nslistener sees "presentation new <id>"
#
# If the new artifact has type=app, reads dispath and launches the GUI app.
# Also auto-centers the artifact so handleprescurrent() fires and hides all
# other apps — without this, the newly-launched app window starts at z-top
# but activeappid is never set, so subsequent "center mermaid" calls call
# hideapp("") which is a no-op, leaving the app window floating over content.
checklaunchapp(id: string)
{
	if(actid < 0) return;
	base := sys->sprint("%s/activity/%d/presentation/%s", mountpt, actid, id);
	atype := readfile(base + "/type");
	if(atype != nil) atype = strip(atype);
	if(atype != "app") return;
	dispath := readfile(base + "/dispath");
	if(dispath != nil) dispath = strip(dispath);
	if(dispath == "") return;
	launchapp(id, dispath);
	# Auto-center the new app so handleprescurrent() hides other apps
	if(actid >= 0)
		writetofile(sys->sprint("%s/activity/%d/presentation/ctl", mountpt, actid),
			"center id=" + id);
}

# launchapp: allocate AppSlot, queue id for preswmloop, then spawn the GUI app.
#
# Ordering is critical:
#   1. Push id to appjoinch BEFORE spawning, so preswmloop sees the id waiting
#      when the app's first join arrives.  The app can only join after spawn, so
#      the push always happens-before the join.
#   2. If load fails, drain appjoinch so the stale id doesn't mis-label the
#      next app that successfully joins.
#
# TODO: eliminate the appjoinch protocol by giving each app its own wmsrv instance.
launchapp(id, dispath: string)
{
	# Allocate AppSlot (client filled in later by preswmloop join handler)
	if(nappslots < MAXAPPSLOTS) {
		appslots[nappslots] = ref AppSlot(id, nil);
		nappslots++;
	}
	# Signal preswmloop: next join belongs to this id
	alt { appjoinch <-= id => ; * => ; }
	# Load the GUI app module; drain appjoinch if load fails
	guimod := load GuiApp dispath;
	if(guimod == nil) {
		sys->fprint(stderr, "lucifer: cannot load %s: %r\n", dispath);
		# Drain the appjoinch entry so the next app isn't misidentified
		alt { <-appjoinch => ; * => ; }
		writeappstatus(id, "dead");
		return;
	}
	# Spawn app with presscr context so it connects to our wmsrv (wmchan)
	newctxt := ref Draw->Context(display, presscr, wmchan);
	spawn guimod->init(newctxt, dispath :: nil);
	writeappstatus(id, "running");
}

# showapp: bring app window to front of the Screen z-stack (in front of lucipres).
#
# Uses Client.top() — the correct Inferno WM z-order primitive.
# Do NOT use Client.unhide() — it is an empty stub in wmsrv.b.
# Do NOT create a new window via Screen.newwindow() — each app has exactly ONE
# window allocated at first !reshape; creating more causes ghost windows.
showapp(id: string)
{
	if(id == "") return;
	for(si := 0; si < nappslots; si++) {
		if(appslots[si] != nil && appslots[si].id == id) {
			if(appslots[si].client != nil)
				appslots[si].client.top();
			return;
		}
	}
}

# hideapp: send app window to the bottom of the Screen z-stack (behind lucipres).
#
# Uses Client.bottom() — the correct Inferno WM z-order primitive.
# Do NOT use Client.hide() — it is an empty stub in wmsrv.b.
# Do NOT use a 1×1 offscreen rect — Screen.newwindow() checks that the rect fits
# within the backing image; coordinates outside pressubimg.r return nil.
hideapp(id: string)
{
	if(id == "") return;
	for(si := 0; si < nappslots; si++) {
		if(appslots[si] != nil && appslots[si].id == id) {
			if(appslots[si].client != nil)
				appslots[si].client.bottom();
			return;
		}
	}
}

# killapp: terminate the app process and free its AppSlot.
#
# Sends bottom() first so the app window disappears immediately while the
# "exit" message is in flight.  "exit" causes wmsrv to disconnect the client;
# the req handler in preswmloop clears appslots[].client on disconnect.
#
# TODO: when an app crashes (no orderly exit), its client may linger in appslots
#       with client != nil but the goroutine dead.  Add a watchdog that clears
#       dead slots by detecting that client.ctl is closed (rc == nil in req).
killapp(id: string)
{
	if(id == "") return;
	for(si := 0; si < nappslots; si++) {
		if(appslots[si] != nil && appslots[si].id == id) {
			if(appslots[si].client != nil) {
				# Send to back before exit so it's invisible immediately
				appslots[si].client.bottom();
				alt { appslots[si].client.ctl <-= "exit" => ; * => ; }
			}
			appslots[si] = nil;
			# Compact slot array (preserve ordering for appjoinch protocol)
			for(ci := si; ci + 1 < nappslots; ci++)
				appslots[ci] = appslots[ci + 1];
			nappslots--;
			if(activeappid == id)
				activeappid = "";
			return;
		}
	}
}

# handleprescurrent: called when "presentation current" event fires.
#
# Reads the artifact id from /presentation/current and determines whether
# it's a GUI app or a standard artifact (mermaid, markdown, etc.).
#
# App tab selected:
#   Hide all OTHER running apps (bottom()), show the selected one (top()),
#   update activeappid.  Mouse events in the content area go to activeappid's
#   client (see preswmloop mouse routing).
#
# Non-app tab selected (mermaid, markdown, pdf, …):
#   Hide ALL running apps.  lucipres draws the artifact in the content area.
#   activeappid is cleared so mouse events go to lucipres.
#
# Critical: MUST iterate all appslots, not just activeappid.  Before this was
# fixed, centering mermaid called hideapp("") which is a no-op, leaving whichever
# app was last-top still floating over the presentation content.
handleprescurrent()
{
	if(actid < 0) return;
	s := readfile(sys->sprint("%s/activity/%d/presentation/current", mountpt, actid));
	if(s == nil) return;
	newid := strip(s);
	# Check type of newly-centered artifact
	atype := readfile(sys->sprint("%s/activity/%d/presentation/%s/type",
		mountpt, actid, newid));
	if(atype != nil) atype = strip(atype);
	if(atype == "app") {
		if(newid != activeappid) {
			# Hide all apps except the newly-centered one
			for(hsi := 0; hsi < nappslots; hsi++)
				if(appslots[hsi] != nil && appslots[hsi].id != newid)
					hideapp(appslots[hsi].id);
			showapp(newid);
			activeappid = newid;
		}
	} else {
		# Non-app centered: hide ALL running apps so lucipres is fully visible
		for(hsi2 := 0; hsi2 < nappslots; hsi2++)
			if(appslots[hsi2] != nil && appslots[hsi2].id != "")
				hideapp(appslots[hsi2].id);
		activeappid = "";
	}
}
