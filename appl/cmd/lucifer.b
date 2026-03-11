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

include "lucitheme.m";

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

# Mutex for appslots/nappslots/activeappid — serializes access between
# nslistener (checklaunchapp, killapp, handleprescurrent) and preswmloop
# (join handler, cleanupappslot, mouse routing).
# Usage: <-applock before access, applock <-= 1 after.
applock: chan of int;

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

# Last known mouse X — updated by mouseproc, used by kbdproc for focus-follows-mouse
lastmousex := 0;

# Zone layout percentages (default; modified by ctx expand/restore)
conv_pct := 30;
pres_pct := 45;

# Zone channels
convMouseCh: chan of ref Pointer;
convKbdCh:   chan of int;
convEvCh:    chan of string;
convRszCh:   chan of ref Draw->Image;

presMouseCh: chan of ref Pointer;

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
	initallowed();

	buildstamp := readfile("/lib/lucifer/buildstamp");
	if(buildstamp == nil || buildstamp == "")
		buildstamp = "dev";
	else
		buildstamp = strip(buildstamp);
	sys->fprint(sys->fildes(1), "lucifer: INIT BUILD=%s\n", buildstamp);
	sys->fprint(sys->fildes(2), "lucifer: INIT BUILD=%s\n", buildstamp);
	{
		hse := sys->open("/dev/hoststderr", Sys->OWRITE);
		if(hse != nil)
			sys->fprint(hse, "lucifer: INIT BUILD=%s (hoststderr)\n", buildstamp);
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

	# Allocate colors from theme
	lucitheme := load Lucitheme Lucitheme->PATH;
	th := lucitheme->gettheme();
	bgcol    = display.color(th.bg);
	bordercol= display.color(th.border);
	headercol= display.color(th.header);
	accentcol= display.color(th.accent);
	textcol  = display.color(th.text);
	dimcol   = display.color(th.dim);

	# Load fonts
	mainfont = Font.open(display, "/fonts/combined/unicode.sans.14.font");
	if(mainfont == nil)
		mainfont = Font.open(display, "*default*");
	monofont = Font.open(display, "/fonts/combined/unicode.14.font");
	if(monofont == nil)
		monofont = mainfont;

	# Load logo (skip on Windows — readpng hangs due to inflate filter issue)
	emuhost := readfile("/env/emuhost");
	if(emuhost != nil)
		emuhost = strip(emuhost);
	if(emuhost != "Nt") {
		# Load logo — use theme-specific variant if available
		bufio := load Bufio Bufio->PATH;
		if(bufio != nil) {
			readpng := load RImagefile RImagefile->READPNGPATH;
			remap := load Imageremap Imageremap->PATH;
			if(readpng != nil && remap != nil) {
				readpng->init(bufio);
				remap->init(display);
				logopath := "/lib/lucifer/logo.png";
				themename := readfile("/lib/lucifer/theme/current");
				if(themename != nil) {
					themename = strip(themename);
					if(themename != "brimstone" && themename != "") {
						tpath := "/lib/lucifer/logo-" + themename + ".png";
						tfd := sys->open(tpath, Sys->OREAD);
						if(tfd != nil)
							logopath = tpath;
					}
				}
				fd := bufio->open(logopath, Bufio->OREAD);
				if(fd != nil) {
					(raw, nil) := readpng->read(fd);
					if(raw != nil)
						(logoimg, nil) = remap->remap(raw, display, 0);
				}
				if(logoimg == nil)
					sys->fprint(stderr, "lucifer: warning: could not load logo from %s\n", logopath);
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
	mainwin.draw(mainwin.r, mainscr.fill, nil, mainscr.fill.r.min);

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
	appjoinch = chan[16] of string;	# capacity 16 (was 4) — see item 13
	applock = chan[1] of int;
	applock <-= 1;			# initially unlocked

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
#   Keyboard events go to the active app if mouse is in the pres zone and an app
#   is foregrounded, otherwise to the conv zone (convKbdCh).
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
				<-applock;
				for(asi := 0; asi < nappslots; asi++) {
					if(appslots[asi] != nil && appslots[asi].id == appid2) {
						appslots[asi].client = c;
						break;
					}
				}
				applock <-= 1;
			}
		}
		rc <-= nil;
	(c, data, rc) := <-req =>
		if(rc == nil) {
			# Client disconnected — clear from lucipres slot or app slot
			if(c == lucipresclient) {
				lucipresclient = nil;
				break;	# lucipres gone — presentation zone dead, exit loop
			}
			cleanupappslot(c);
			# App disconnected: keep preswmloop running for remaining apps
		}
		s := string data;
		n := len data;
		err: string;
		# !reshape / !onscreen: allocate window on first connect only.
		# Subsequent reshapes for apps are ignored (z-order managed via top/bottom).
		# !onscreen is the first !-prefixed call from wmclient (gui.b init calls
		# win.onscreen before evhandle is spawned); wmlib blocks on <-wm.images
		# after any !-prefixed write, so we must send back an image here too.
		if(len s >= 8 && s[0:8] == "!reshape" ||
		   len s >= 9 && s[0:9] == "!onscreen") {
			if(c == lucipresclient) {
				img := scr.newwindow(curzone, Draw->Refbackup, Draw->Nofill);
				if(img == nil) {
					err = "window creation failed";
					n = -1;
				} else {
					c.setimage("app", img);
					# scr.newwindow() places the new lucipres window at the TOP of
					# presscr by default, pushing any active app window behind it.
					# Re-raise the active app so it stays in front of lucipres.
					<-applock;
					for(rasi := 0; rasi < nappslots; rasi++) {
						if(appslots[rasi] != nil &&
						   appslots[rasi].id == activeappid &&
						   appslots[rasi].client != nil) {
							appslots[rasi].client.top();
							break;
						}
					}
					applock <-= 1;
				}
			} else if(c.image("app") == nil) {
				# First reshape for this app: allocate content-area window
				tabh2 := 0;
				if(mainfont != nil) tabh2 = mainfont.height + 13;
				appr := Rect((curzone.min.x, curzone.min.y + tabh2), curzone.max);
				img := scr.newwindow(appr, Draw->Refbackup, Draw->Nofill);
				if(img == nil) {
					err = "window creation failed";
					n = -1;
				} else {
					c.setimage("app", img);
					# Register c in the wmsrv z-list via top().
					# scr.newwindow() puts the image at z-top on the Screen,
					# but wmsrv's Client.bottom() requires c.znext != nil to
					# actually call screen.bottom().  c.top() sets c.znext so
					# a subsequent c.bottom() (in cleanupappslot/hideapp) works.
					c.top();
				}
				# handleprescurrent() will call bottom() if another artifact is active
			}
			# else: app already has a window — ignore re-reshape
		}
		# "embedded-exit": app signals clean exit before GC closes its wmclient fd.
		# Remove the tab immediately rather than waiting for the async fd close.
		if(s == "embedded-exit")
			cleanupappslot(c);
		# All other req messages ("start ptr", "start kbd", "raise", etc.) — reply OK
		alt { rc <-= (n, err) => ; * => ; }
	newzoner := <-rszch =>
		curzone = newzoner;
		# Resize lucipres window (full zone)
		if(lucipresclient != nil) {
			# presscr (module global) was updated by handleresize before sending
			# Fill old image with bg before replacing to prevent ghost artifacts
			oldimg := lucipresclient.image("app");
			if(oldimg != nil)
				oldimg.draw(oldimg.r, bgcol, nil, (0, 0));
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
		<-applock;
		for(asi3 := 0; asi3 < nappslots; asi3++) {
			if(appslots[asi3] != nil && appslots[asi3].client != nil) {
				# Fill old image with bg before replacing to prevent ghost artifacts
				oldimg3 := appslots[asi3].client.image("app");
				if(oldimg3 != nil)
					oldimg3.draw(oldimg3.r, bgcol, nil, (0, 0));
				img3 := presscr.newwindow(appr2, Draw->Refbackup, Draw->Nofill);
				if(img3 != nil) {
					appslots[asi3].client.setimage("app", img3);
					appslots[asi3].client.ctl <-= sys->sprint("!reshape app -1 %s", r2s(appr2));
				}
			}
		}
		applock <-= 1;
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
			<-applock;
			for(masi := 0; masi < nappslots; masi++) {
				if(appslots[masi] != nil && appslots[masi].id == activeappid &&
						appslots[masi].client != nil) {
					actclient = appslots[masi].client;
					break;
				}
			}
			applock <-= 1;
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
		if(req == "restore")
			handlectxlayout(30, 45);
		else if(req == "expand")
			handlectxlayout(20, 30);
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
	backoff := 500;
	for(;;) {
		fd := sys->open(evpath, Sys->OREAD);
		if(fd == nil) {
			sys->sleep(backoff);
			if(backoff < 8000)
				backoff *= 2;
			continue;
		}
		buf := array[4096] of byte;
		n := sys->read(fd, buf, len buf);
		if(n <= 0) {
			sys->sleep(backoff);
			if(backoff < 8000)
				backoff *= 2;
			continue;
		}
		backoff = 500;	# reset on successful read
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
		lastmousex = p.xy.x;
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
	# ANSI escape sequence decoder state
	escstate := 0;	# 0=normal, 1=saw-ESC, 2=saw-ESC[, 3=collecting-arg
	escarg   := 0;

	for(;;) {
		c := <-win.ctxt.kbd;

		# Decode ANSI escape sequences to Inferno key codes.
		# Inferno key codes (>= 0xFF00) pass through unmodified.
		if(c < 16rFF00) {
			case escstate {
			0 =>
				if(c == 27) {
					escstate = 1;
					continue;
				}
			1 =>
				escstate = 0;
				if(c == '[') {
					escstate = 2;
					escarg = 0;
					continue;
				}
				# Bare ESC+char: deliver char as-is (fall through to route)
			2 =>
				escstate = 0;
				if(c == 'A')       c = 16rFF52;	# up
				else if(c == 'B') c = 16rFF54;	# down
				else if(c == 'C') c = 16rFF53;	# right
				else if(c == 'D') c = 16rFF51;	# left
				else if(c == 'H') c = 16rFF61;	# home
				else if(c == 'F') c = 16rFF57;	# end
				else if(c == '1' || c == '4' || c == '5' ||
				        c == '6' || c == '7' || c == '8') {
					escarg = c - '0';
					escstate = 3;
					continue;
				} else
					continue;	# unknown: discard
			3 =>
				if(c == '~') {
					escstate = 0;
					if(escarg == 1 || escarg == 7)      c = 16rFF61;	# home
					else if(escarg == 4 || escarg == 8) c = 16rFF57;	# end
					else if(escarg == 5)                c = 16rFF55;	# pgup
					else if(escarg == 6)                c = 16rFF56;	# pgdn
					else continue;
				} else if(c >= '0' && c <= '9') {
					escarg = escarg * 10 + (c - '0');
					continue;
				} else {
					escstate = 0;
					continue;
				}
			}
		}

		# Route decoded key to appropriate target
		if(pres_zone_minx > 0 && lastmousex >= pres_zone_minx &&
				lastmousex < pres_zone_maxx && activeappid != "") {
			routed := 0;
			for(ksi := 0; ksi < nappslots; ksi++) {
				if(appslots[ksi] != nil && appslots[ksi].id == activeappid &&
						appslots[ksi].client != nil) {
					alt { appslots[ksi].client.kbd <-= c => ; * => ; }
					routed = 1;
					break;
				}
			}
			if(!routed)
				alt { convKbdCh <-= c => ; * => ; }
		} else {
			alt { convKbdCh <-= c => ; * => ; }
		}
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
	while((n := sys->read(fd, b, len b)) > 0) {
		if(n < Wmsize)
			continue;	# short read — discard
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
	i := 0;
	while(i < len s && (s[i] == ' ' || s[i] == '\t' || s[i] == '\n'))
		i++;
	if(i >= len s)
		return -1;
	n := 0;
	for(; i < len s; i++) {
		c := s[i];
		if(c < '0' || c > '9')
			return -1;
		if(n > 214748364)
			return -1;
		n = n * 10 + (c - '0');
	}
	return n;
}

# --- Presentation zone WM namespace goroutines ---

# --- App lifecycle management ---

# cleanupappslot: remove an app client from the slot array and delete its artifact.
#
# Called from two places:
#   1. preswmloop disconnect handler (rc == nil): client fd was closed by GC.
#   2. preswmloop req handler for "embedded-exit": app signals clean exit before
#      its goroutines die (so the ghost tab is removed immediately, not after GC).
#
# Calls c.bottom() to hide the window, compacts the slot array, clears activeappid
# if needed, and writes "delete id=<deadid>" to presentation/ctl.
# luciuisrv fires "presentation delete <id>" which nslistener delivers to lucipres.
cleanupappslot(c: ref Client)
{
	<-applock;
	for(ci := 0; ci < nappslots; ci++) {
		if(appslots[ci] != nil && appslots[ci].client == c) {
			c.bottom();
			deadid := appslots[ci].id;
			appslots[ci] = nil;
			for(cj := ci; cj + 1 < nappslots; cj++)
				appslots[cj] = appslots[cj + 1];
			nappslots--;
			if(activeappid == deadid)
				activeappid = "";
			applock <-= 1;
			if(actid >= 0 && deadid != "")
				writetofile(sys->sprint(
					"%s/activity/%d/presentation/ctl",
					mountpt, actid),
					"delete id=" + deadid);
			return;
		}
	}
	applock <-= 1;
}

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
	# Read data field for app arguments (e.g., file path for luciedit)
	appdata := readfile(base + "/data");
	if(appdata != nil) appdata = strip(appdata);
	launchapp(id, dispath, appdata);
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
# Allowed dis path prefixes for GUI app launch.  Prevents arbitrary module execution
# via crafted artifact dispath fields from the LLM agent.
# Each entry must end with '/'.
ALLOWED_PREFIXES: array of string;

initallowed()
{
	ALLOWED_PREFIXES = array[] of {
		"/dis/wm/",
		"/dis/charon/",
		"/dis/xenith/",
	};
}

validdispath(path: string): int
{
	if(path == nil || len path == 0)
		return 0;
	# Must start with one of the allowed prefixes
	ok := 0;
	for(i := 0; i < len ALLOWED_PREFIXES; i++) {
		pfx := ALLOWED_PREFIXES[i];
		if(len path >= len pfx && path[0:len pfx] == pfx) {
			ok = 1;
			break;
		}
	}
	if(!ok)
		return 0;
	# Must end with .dis
	if(len path < 4 || path[len path - 4:] != ".dis")
		return 0;
	# Reject control characters and whitespace
	for(i = 0; i < len path; i++) {
		c := path[i];
		if(c <= ' ' || c == 16r7F)
			return 0;
	}
	# No path traversal (.., //, or /. components)
	for(i = 0; i < len path - 1; i++) {
		if(path[i] == '.' && path[i+1] == '.')
			return 0;
		if(path[i] == '/' && path[i+1] == '/')
			return 0;
		if(path[i] == '/' && path[i+1] == '.' &&
				(i+2 >= len path || path[i+2] == '/'))
			return 0;
	}
	return 1;
}

launchapp(id, dispath, appdata: string)
{
	# Validate dispath against whitelist
	if(!validdispath(dispath)) {
		sys->fprint(stderr, "lucifer: blocked load of %s: not in allowed path\n", dispath);
		writeappstatus(id, "dead");
		return;
	}
	# Allocate AppSlot (client filled in later by preswmloop join handler)
	<-applock;
	if(nappslots < MAXAPPSLOTS) {
		appslots[nappslots] = ref AppSlot(id, nil);
		nappslots++;
	}
	applock <-= 1;
	# Signal preswmloop: next join belongs to this id
	alt { appjoinch <-= id => ;
		* => sys->fprint(stderr, "lucifer: appjoinch overflow for %s\n", id); }
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
	appargs: list of string;
	if(appdata != nil && appdata != "") {
		# Tokenize appdata so multi-flag strings like "-c 1 -t dark -E"
		# arrive as separate list elements (argopt expects one flag per element).
		(nil, datatl) := sys->tokenize(appdata, " \t");
		appargs = dispath :: datatl;
	} else
		appargs = dispath :: nil;
	spawn guimod->init(newctxt, appargs);
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
	<-applock;
	for(si := 0; si < nappslots; si++) {
		if(appslots[si] != nil && appslots[si].id == id) {
			if(appslots[si].client != nil)
				appslots[si].client.top();
			applock <-= 1;
			return;
		}
	}
	applock <-= 1;
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
	<-applock;
	for(si := 0; si < nappslots; si++) {
		if(appslots[si] != nil && appslots[si].id == id) {
			if(appslots[si].client != nil)
				appslots[si].client.bottom();
			applock <-= 1;
			return;
		}
	}
	applock <-= 1;
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
	<-applock;
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
			applock <-= 1;
			return;
		}
	}
	applock <-= 1;
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
	# Collect IDs under lock, then call show/hide outside lock to avoid deadlock
	# (showapp/hideapp take applock internally).
	hideids: list of string;
	showid := "";
	<-applock;
	if(atype == "app") {
		if(newid != activeappid) {
			for(hsi := 0; hsi < nappslots; hsi++)
				if(appslots[hsi] != nil && appslots[hsi].id != newid)
					hideids = appslots[hsi].id :: hideids;
			showid = newid;
			activeappid = newid;
		}
	} else {
		for(hsi2 := 0; hsi2 < nappslots; hsi2++)
			if(appslots[hsi2] != nil && appslots[hsi2].id != "")
				hideids = appslots[hsi2].id :: hideids;
		activeappid = "";
	}
	applock <-= 1;
	for(; hideids != nil; hideids = tl hideids)
		hideapp(hd hideids);
	if(showid != "")
		showapp(showid);
}
