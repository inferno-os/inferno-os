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

include "menu.m";

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
lucitheme_g: Lucitheme;		# kept for live theme reload

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
# Each app gets a per-app wmchan relay (appwmrelay goroutine) that intercepts
# the wmlib registration, records a token→id mapping, then forwards to the
# shared wmsrv.  preswmloop's join handler looks up c.token to find the
# artifact id, so the mapping is independent of join order.
AppSlot: adt {
	id:     string;
	owneract: int;		# activity that created this app (immutable after alloc)
	client: ref Client;
};
MAXAPPSLOTS: con 16;
appslots: array of ref AppSlot;
nappslots := 0;
activeappid: string;	# artifact id of currently-visible app ("" = lucipres showing)

# Token-to-ID map: populated by appwmrelay before forwarding the wmreq,
# consumed by preswmloop's join handler via poppending(c.token).
MAXTOKENPENDING: con 16;
pendingtokens: array of int;
pendingids: array of string;
npendingtokens := 0;

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

# Task tile state
TileInfo: adt {
	id:       int;
	label:    string;
	status:   string;
	urgency:  int;
	x:        int;		# left pixel (cached for hit testing)
	w:        int;		# width in pixels
};
tiles: array of ref TileInfo;
ntiles := 0;
tilescrollx := 0;		# horizontal scroll offset for tile strip
tiletotalw := 0;		# total pixel width of all tiles (for scroll cap)
blinkon := 0;			# toggled by tileblinker goroutine
tilelock: chan of int;		# mutex for tiles/ntiles/blinkon access

# Urgency colors (allocated from theme)
yellowcol: ref Image;
redcol: ref Image;
greencol: ref Image;

# Menu module
menumod: Menu;
Popup: import menumod;

# Zone boundaries (set on every layout pass, used by mouseproc)
pres_zone_minx := 0;
pres_zone_maxx := 0;
ctx_zone_minx := 0;

# Last known mouse X — updated by mouseproc, used by kbdproc for focus-follows-mouse
lastmousex := 0;

# Zone layout percentages (default; modified by ctx expand/restore)
conv_pct := 30;
pres_pct := 45;

# nslistener process ID — killed and respawned on activity switch
nslistenerpid := -1;

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
	lucitheme_g = load Lucitheme Lucitheme->PATH;
	if(lucitheme_g == nil) {
		sys->fprint(stderr, "lucifer: cannot load lucitheme: %r\n");
		return;
	}
	th := lucitheme_g->gettheme();
	bgcol    = display.color(th.bg);
	bordercol= display.color(th.border);
	headercol= display.color(th.header);
	accentcol= display.color(th.accent);
	textcol  = display.color(th.text);
	dimcol   = display.color(th.dim);
	yellowcol= display.color(th.yellow);
	redcol   = display.color(th.red);
	greencol = display.color(th.green);

	# Load fonts
	mainfont = Font.open(display, "/fonts/combined/unicode.sans.14.font");
	if(mainfont == nil)
		mainfont = Font.open(display, "*default*");
	if(mainfont == nil) {
		sys->fprint(stderr, "lucifer: cannot load any font\n");
		return;
	}
	monofont = Font.open(display, "/fonts/combined/unicode.14.font");
	if(monofont == nil)
		monofont = mainfont;

	# Load menu module
	menumod = load Menu Menu->PATH;
	if(menumod != nil)
		menumod->init(display, mainfont);

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
	tiles = array[8] of ref TileInfo;
	loadtiles();

	# Allocate channels
	cmouse      = chan of ref Pointer;
	uievent     = chan[1] of int;
	luciStatusCh= chan[1] of string;

	convMouseCh = chan[16] of ref Pointer;
	convKbdCh   = chan[16] of int;
	convEvCh    = chan[16] of string;
	convRszCh   = chan[1] of ref Draw->Image;

	presMouseCh = chan[16] of ref Pointer;
	presRszCh   = chan[1] of Rect;

	ctxMouseCh  = chan[16] of ref Pointer;
	ctxEvCh     = chan[4] of string;
	ctxRszCh    = chan[1] of ref Draw->Image;
	ctxreqch    = chan[1] of string;
	switchch    = chan[1] of int;

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
	pendingtokens = array[MAXTOKENPENDING] of int;
	pendingids = array[MAXTOKENPENDING] of string;
	applock = chan[1] of int;
	applock <-= 1;			# initially unlocked
	tilelock = chan[1] of int;
	tilelock <-= 1;			# initially unlocked

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
	spawn globallistener();
	spawn tileblinker();

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

# --- Theme reload ---

reloadtheme()
{
	if(lucitheme_g == nil)
		return;
	th := lucitheme_g->gettheme();
	bgcol    = display.color(th.bg);
	bordercol= display.color(th.border);
	headercol= display.color(th.header);
	accentcol= display.color(th.accent);
	textcol  = display.color(th.text);
	dimcol   = display.color(th.dim);
	yellowcol= display.color(th.yellow);
	redcol   = display.color(th.red);
	greencol = display.color(th.green);
	# Reload logo variant for the new theme
	reloadlogo();
}

reloadlogo()
{
	bufio := load Bufio Bufio->PATH;
	if(bufio == nil)
		return;
	readpng := load RImagefile RImagefile->READPNGPATH;
	remap := load Imageremap Imageremap->PATH;
	if(readpng == nil || remap == nil)
		return;
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

		# Task tiles — scrollable strip after logo
		tileh := 28;
		tiley := headerr.min.y + (headerh - tileh) / 2;
		tilepad := 8;	# horizontal text padding per side
		tilegap := 4;	# gap between tiles
		tilestripx := textx;	# start of tile strip (after logo)

		if(ntiles > 0) {
			tx := tilestripx - tilescrollx;
			for(i := 0; i < ntiles; i++) {
				t := tiles[i];
				tlabel := t.label;
				if(tlabel == nil || tlabel == "")
					tlabel = string t.id;
				# Show tool name on the active tile during execution
				istool := t.status != nil && t.status != "" &&
					t.status != "idle" && t.status != "working" &&
					t.status != "done" && t.status != "complete";
				if(istool)
					tlabel += " · " + t.status;
				tw := mainfont.width(tlabel) + tilepad * 2;
				if(tw < 60)
					tw = 60;

				# Cache position for mouse hit testing (screen coords)
				t.x = tx;
				t.w = tw;

				# Only draw if visible in the strip
				if(tx + tw > tilestripx && tx < r.max.x) {
					# Determine tile colors
					tilefg: ref Image;
					tilebg: ref Image;

					if(t.urgency > 0 && blinkon) {
						# Blinking urgency state
						if(t.urgency >= 2) {
							tilebg = redcol;
							tilefg = textcol;
						} else {
							tilebg = yellowcol;
							tilefg = headercol;
						}
					} else if(t.id == actid) {
						# Active tile: accent background
						tilebg = accentcol;
						tilefg = headercol;
					} else if(t.status == "working" || istool) {
						# Working tile (or executing a tool): accent underline
						tilebg = headercol;
						tilefg = textcol;
					} else if(t.status == "done") {
						tilebg = headercol;
						tilefg = greencol;
					} else {
						# Normal/idle tile
						tilebg = headercol;
						tilefg = dimcol;
					}

					# Draw tile background
					tiler := Rect((tx, tiley), (tx + tw, tiley + tileh));
					mainwin.draw(tiler, tilebg, nil, (0, 0));

					# Draw 1px border for non-active tiles
					if(t.id != actid || (t.urgency > 0 && blinkon)) {
						mainwin.draw(Rect((tx, tiley), (tx + tw, tiley + 1)), bordercol, nil, (0, 0));
						mainwin.draw(Rect((tx, tiley + tileh - 1), (tx + tw, tiley + tileh)), bordercol, nil, (0, 0));
						mainwin.draw(Rect((tx, tiley), (tx + 1, tiley + tileh)), bordercol, nil, (0, 0));
						mainwin.draw(Rect((tx + tw - 1, tiley), (tx + tw, tiley + tileh)), bordercol, nil, (0, 0));
					}

					# Working tile: accent bottom border
					if((t.status == "working" || istool) && t.id != actid)
						mainwin.draw(Rect((tx, tiley + tileh - 2), (tx + tw, tiley + tileh)), accentcol, nil, (0, 0));

					# Draw label text centered in tile
					textw := mainfont.width(tlabel);
					ltx := tx + (tw - textw) / 2;
					lty := tiley + (tileh - mainfont.height) / 2;
					mainwin.text((ltx, lty), tilefg, (0, 0), mainfont, tlabel);
				}

				tx += tw + tilegap;
			}
			# Cache total tile width for scroll cap
			totalw := tx - (tilestripx - tilescrollx);
			visiblew := r.max.x - tilestripx;
			if(totalw > visiblew)
				tiletotalw = totalw - visiblew;
			else
				tiletotalw = 0;
		} else {
			tiletotalw = 0;
			# No tiles: fall back to simple title text
			title := "InferNode";
			if(actlabel != nil && actlabel != "")
				title += " | " + actlabel;
			if(actstatus != nil && actstatus != "" && actstatus != "idle")
				title += " [" + actstatus + "]";
			texty := headerr.min.y + (headerh - mainfont.height) / 2;
			mainwin.text((textx, texty), textcol, (0, 0), mainfont, title);
		}
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
#   - Token-to-ID pending map is bounded to 16 entries (more than enough for
#     concurrent launches).
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
			# Subsequent join = an app; look up token→id to find the right slot
			<-applock;
			appid2 := poppending(c.token);
			if(appid2 != "") {
				for(asi := 0; asi < nappslots; asi++) {
					if(appslots[asi] != nil && appslots[asi].id == appid2) {
						appslots[asi].client = c;
						break;
					}
				}
			}
			applock <-= 1;
		}
		rc <-= nil;
	(c, data, rc) := <-req =>
		if(rc == nil) {
			# Client disconnected — clear from lucipres slot or app slot.
			# MUST NOT fall through to the reply code below: rc is nil,
			# and alt send on a nil channel is a fatal Dis error.
			if(c == lucipresclient) {
				lucipresclient = nil;
				break;	# lucipres gone — presentation zone dead, exit loop
			}
			cleanupappslot(c);
			# App disconnected: keep preswmloop running for remaining apps
		} else {
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
						# If this app belongs to a non-focused activity, hide it
						# immediately.  Without this, a background task agent's
						# app window appears over the currently-viewed activity.
						<-applock;
						for(oai := 0; oai < nappslots; oai++) {
							if(appslots[oai] != nil &&
							   appslots[oai].client == c &&
							   appslots[oai].owneract != actid) {
								c.bottom();
								break;
							}
						}
						applock <-= 1;
					}
				}
				# else: app already has a window — ignore re-reshape
			}
			# "embedded-exit": app signals clean exit before GC closes its wmclient fd.
			# Remove the tab immediately rather than waiting for the async fd close.
			if(s == "embedded-exit")
				cleanupappslot(c);
			# All other req messages ("start ptr", "start kbd", "raise", etc.) — reply OK
			alt { rc <-= (n, err) => ; * => ; }
		}
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
				alt { lucipresclient.ptr <-= p => ; * => ; }
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
				alt { actclient.ptr <-= p => ; * => ; }
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
		# Activity changed — reload tiles then redraw header
		loadtiles();
		drawchrome(mainwin.r);
	req := <-ctxreqch =>
		if(req == "restore")
			handlectxlayout(30, 45);
		else if(req == "expand")
			handlectxlayout(20, 30);
	newact := <-switchch =>
		switchactivity(newact);
	}
}

# Switch channel — globallistener sends new activity id
switchch: chan of int;

switchactivity(newid: int)
{
	if(newid == actid)
		return;

	actid = newid;
	# Tell luciuisrv which activity is focused so tools (e.g. launch)
	# that read /n/ui/activity/current get the correct id.
	writefile(sys->sprint("%s/activity/current", mountpt), string newid);
	loadlabel();
	loadstatus();

	# Clear urgency on the newly focused activity
	writefile(sys->sprint("%s/activity/%d/urgency", mountpt, newid), "0");
	updatetile(newid, "urgency", "0");

	# Hide apps from OTHER activities; show the new activity's current app
	# (if any).  All apps live on the shared presscr z-stack, so visibility
	# is purely z-order: top() = visible, bottom() = hidden.
	curid := "";
	s := readfile(sys->sprint("%s/activity/%d/presentation/current", mountpt, newid));
	if(s != nil) {
		curid = strip(s);
		at := readfile(sys->sprint("%s/activity/%d/presentation/%s/type",
			mountpt, newid, curid));
		if(at != nil) at = strip(at);
		if(at != "app")
			curid = "";	# current artifact isn't an app
	}
	<-applock;
	for(sai := 0; sai < nappslots; sai++) {
		if(appslots[sai] != nil && appslots[sai].client != nil) {
			if(appslots[sai].owneract == newid && appslots[sai].id == curid) {
				appslots[sai].client.top();
				activeappid = curid;
			} else {
				appslots[sai].client.bottom();
			}
		}
	}
	if(curid == "")
		activeappid = "";
	applock <-= 1;

	# Kill and respawn nslistener so it reads events for the new activity.
	# nslistener blocks on sys->read() of the per-activity event file;
	# killing it is the only way to redirect it to the new activity.
	if(nslistenerpid >= 0) {
		fd := sys->open("/prog/" + string nslistenerpid + "/ctl", Sys->OWRITE);
		if(fd != nil)
			sys->fprint(fd, "kill");
	}
	spawn nslistener();

	# Signal zone modules to switch to new activity
	ev := "switchactivity " + string newid;
	alt { convEvCh <-= ev => ; * => ; }
	alt { ctxEvCh <-= ev => ; * => ; }
	if(lucipres_g != nil)
		lucipres_g->deliverevent(ev);

	# Reload tiles and redraw header
	loadtiles();
	drawchrome(mainwin.r);
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
	if(mainscr == nil)
		return;
	convimg = mainscr.newwindow(convr, Draw->Refbackup, Draw->Nofill);
	ctximg  = mainscr.newwindow(ctxr,  Draw->Refbackup, Draw->Nofill);
	pressubimg = mainscr.newwindow(presr, Draw->Refbackup, Draw->Nofill);
	if(convimg == nil || ctximg == nil || pressubimg == nil)
		return;
	presscr = Screen.allocate(pressubimg, bgcol, 0);
	if(presscr == nil)
		return;
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

# Read all activities from /n/ui/ and populate tile state
loadtiles()
{
	<-tilelock;
	info := readfile(mountpt + "/ctl");
	if(info == nil)
		return;
	info = strip(info);

	# Parse "activities: id1 id2 ..." line
	ids: list of int;
	nids := 0;
	lines := splitlines(info);
	for(; lines != nil; lines = tl lines) {
		line := hd lines;
		if(hasprefix(line, "activities:")) {
			rest := strip(line[len "activities:":]);
			if(rest != "") {
				words := splitwords(rest);
				for(; words != nil; words = tl words) {
					id := strtoint(hd words);
					if(id >= 0) {
						ids = id :: ids;
						nids++;
					}
				}
			}
		}
	}

	# Reverse to preserve order
	rids: list of int;
	for(; ids != nil; ids = tl ids)
		rids = hd ids :: rids;
	ids = rids;

	# Allocate tiles array
	if(tiles == nil || len tiles < nids)
		tiles = array[nids + 4] of ref TileInfo;
	ntiles = 0;

	for(; ids != nil; ids = tl ids) {
		id := hd ids;
		label := readfile(sys->sprint("%s/activity/%d/label", mountpt, id));
		status := readfile(sys->sprint("%s/activity/%d/status", mountpt, id));
		urgstr := readfile(sys->sprint("%s/activity/%d/urgency", mountpt, id));
		if(label != nil)
			label = strip(label);
		if(status != nil)
			status = strip(status);
		else
			status = "";
		if(status == "hidden")
			continue;
		urg := 0;
		if(urgstr != nil)
			urg = strtoint(strip(urgstr));
		if(ntiles >= len tiles) {
			na := array[len tiles * 2] of ref TileInfo;
			na[0:] = tiles[0:ntiles];
			tiles = na;
		}
		tiles[ntiles++] = ref TileInfo(id, label, status, urg, 0, 0);
	}
	tilelock <-= 1;
}

# Update a single tile field without full reload
updatetile(id: int, field, val: string)
{
	<-tilelock;
	for(i := 0; i < ntiles; i++) {
		if(tiles[i].id == id) {
			if(field == "status")
				tiles[i].status = val;
			else if(field == "label")
				tiles[i].label = val;
			else if(field == "urgency")
				tiles[i].urgency = strtoint(val);
			tilelock <-= 1;
			return;
		}
	}
	tilelock <-= 1;
}

# Split string into lines on \n
splitlines(s: string): list of string
{
	result: list of string;
	start := 0;
	for(i := 0; i < len s; i++) {
		if(s[i] == '\n') {
			if(i > start)
				result = s[start:i] :: result;
			start = i + 1;
		}
	}
	if(start < len s)
		result = s[start:] :: result;
	# reverse
	rev: list of string;
	for(; result != nil; result = tl result)
		rev = hd result :: rev;
	return rev;
}

# Split string into whitespace-separated words
splitwords(s: string): list of string
{
	result: list of string;
	i := 0;
	for(;;) {
		# skip whitespace
		while(i < len s && (s[i] == ' ' || s[i] == '\t'))
			i++;
		if(i >= len s)
			break;
		start := i;
		while(i < len s && s[i] != ' ' && s[i] != '\t')
			i++;
		result = s[start:i] :: result;
	}
	# reverse
	rev: list of string;
	for(; result != nil; result = tl result)
		rev = hd result :: rev;
	return rev;
}

# Listen for global events (activity new/delete/switch/urgency)
globallistener()
{
	evpath := mountpt + "/event";
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
		backoff = 500;
		ev := strip(string buf[0:n]);
		if(hasprefix(ev, "newtask ")) {
			# Direct task creation from lucipres "+" button.
			# Provision with full budget (no tools= → default) and
			# inherit bound paths so the new task has the same access.
			newid := strtoint(strip(ev[len "newtask ":]));
			if(newid > 0) {
				# Remove stale brief/instructions from previous sessions
				# so lucibridge doesn't inject an old agenda
				sys->remove("/tmp/veltro/brief." + string newid);
				sys->remove("/tmp/veltro/instructions." + string newid);
				provision := "provision " + string newid;
				# Pass user-bound paths
				paths := readfile("/tool/paths");
				if(paths != nil && paths != "") {
					pcsv := "";
					(nil, ptoks) := sys->tokenize(strip(paths), "\n");
					for(; ptoks != nil; ptoks = tl ptoks) {
						p := strip(hd ptoks);
						if(p == "") continue;
						if(pcsv != "")
							pcsv += ",";
						pcsv += p;
					}
					if(pcsv != "")
						provision += " paths=" + pcsv;
				}
				writefile("/tool/ctl", provision);
				# Switch to new activity
				alt { switchch <-= newid => ; * => ; }
			}
			# Also update tiles/taskboard
			if(lucipres_g != nil)
				lucipres_g->deliverevent("activity new " + string newid);
			alt { uievent <-= 1 => ; * => ; }
		}
		if(hasprefix(ev, "applaunch ")) {
			# "applaunch <activityid> <artifactid>"
			# Launch the app in the EXACT activity that created it,
			# regardless of which activity the user is viewing.
			rest := strip(ev[len "applaunch ":]);
			(nil, toks) := sys->tokenize(rest, " \t");
			if(toks != nil && tl toks != nil) {
				targetact := strtoint(hd toks);
				appid := hd tl toks;
				if(targetact >= 0 && appid != "")
					checklaunchapp(appid, targetact);
			}
		}
		if(hasprefix(ev, "activity ")) {
			# Check if this is a switch event (format: "activity {id}")
			rest := strip(ev[len "activity ":]);
			if(hasprefix(rest, "delete ")) {
				# If the deleted activity is the current one, switch to activity 0
				delrest := strip(rest[len "delete ":]);
				delid := strtoint(delrest);
				if(delid >= 0 && delid == actid)
					alt { switchch <-= 0 => ; * => ; }
			} else if(!hasprefix(rest, "new ") && !hasprefix(rest, "urgency ")) {
				# Pure switch event: "activity {id}"
				newid := strtoint(rest);
				if(newid >= 0 && newid != actid)
					alt { switchch <-= newid => ; * => ; }
			}
			# Notify lucipres so taskboard redraws with updated activities
			if(lucipres_g != nil)
				lucipres_g->deliverevent(ev);
			# Any activity event: signal main loop to reload tiles and redraw
			alt { uievent <-= 1 => ; * => ; }
		}
		if(hasprefix(ev, "theme ")) {
			# Live theme switch: reload colours, redraw chrome, notify zones
			reloadtheme();
			alt { convEvCh <-= ev => ; * => ; }
			alt { ctxEvCh <-= ev => ; * => ; }
			if(lucipres_g != nil)
				lucipres_g->deliverevent(ev);
			alt { uievent <-= 1 => ; * => ; }
		}
	}
}

# Toggle blink state for urgency tiles
tileblinker()
{
	for(;;) {
		sys->sleep(500);
		# Check if any tile has urgency > 0
		<-tilelock;
		hasurgency := 0;
		for(i := 0; i < ntiles; i++) {
			if(tiles[i].urgency > 0) {
				hasurgency = 1;
				break;
			}
		}
		if(hasurgency)
			blinkon = 1 - blinkon;
		else
			blinkon = 0;
		tilelock <-= 1;
		if(hasurgency)
			alt { uievent <-= 1 => ; * => ; }
	}
}

nslistener()
{
	nslistenerpid = sys->pctl(0, nil);
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
			updatetile(actid, "status", actstatus);
			alt { uievent <-= 1 => ; * => ; }
		} else if(ev == "label") {
			loadlabel();
			updatetile(actid, "label", actlabel);
			alt { uievent <-= 1 => ; * => ; }
		} else if(ev == "urgency") {
			s := readfile(sys->sprint("%s/activity/%d/urgency", mountpt, actid));
			if(s != nil)
				updatetile(actid, "urgency", strip(s));
			alt { uievent <-= 1 => ; * => ; }
		} else if(hasprefix(ev, "conversation ")) {
			alt { convEvCh <-= ev => ; * => ; }
		} else if(ev == "catalog" || hasprefix(ev, "context ")) {
			alt { ctxEvCh <-= ev => ; * => ; }
		} else if(hasprefix(ev, "presentation ")) {
			# Always deliver to lucipres for tab/artifact updates
			if(lucipres_g != nil)
				lucipres_g->deliverevent(ev);
			# App launches are handled by globallistener via "applaunch"
			# events — never via nslistener — so apps always target the
			# correct activity regardless of which activity is focused.
			if(hasprefix(ev, "presentation kill ")) {
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
	headerh := 40;
	for(;;) {
		p := <-win.ctxt.ptr;
		lastmousex = p.xy.x;
		if(wmclient->win.pointer(*p) == 0) {
			# Header area: tile clicks and scroll
			if(p.xy.y < mainwin.r.min.y + headerh) {
				if(p.buttons & 1) {
					# Button-1: click on tile to switch activity
					clickid := -1;
					<-tilelock;
					for(i := 0; i < ntiles; i++) {
						t := tiles[i];
						if(p.xy.x >= t.x && p.xy.x < t.x + t.w) {
							if(t.id != actid)
								clickid = t.id;
							break;
						}
					}
					tilelock <-= 1;
					if(clickid >= 0)
						writefile(mountpt + "/activity/current", string clickid);
				} else if(p.buttons & 4) {
					# Button-3: right-click context menu on tile
					menutileid := -1;
					<-tilelock;
					for(i := 0; i < ntiles; i++) {
						t := tiles[i];
						if(p.xy.x >= t.x && p.xy.x < t.x + t.w) {
							if(t.id != 0)
								menutileid = t.id;
							break;
						}
					}
					tilelock <-= 1;
					if(menutileid >= 0 && menumod != nil) {
						mitems := array[] of {"End Task"};
						mpop := menumod->new(mitems);
						mres := mpop.show(mainwin, p.xy, win.ctxt.ptr);
						if(mres == 0)
							writefile(mountpt + "/ctl", "activity delete " + string menutileid);
						alt { uievent <-= 1 => ; * => ; }
					}
				} else if(p.buttons & 8) {
					# Scroll up (left)
					tilescrollx -= 40;
					if(tilescrollx < 0)
						tilescrollx = 0;
					alt { uievent <-= 1 => ; * => ; }
				} else if(p.buttons & 16) {
					# Scroll down (right)
					tilescrollx += 40;
					if(tilescrollx > tiletotalw)
						tilescrollx = tiletotalw;
					alt { uievent <-= 1 => ; * => ; }
				}
				continue;
			}
			# Route by X position to zones
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
			<-applock;
			for(ksi := 0; ksi < nappslots; ksi++) {
				if(appslots[ksi] != nil && appslots[ksi].id == activeappid &&
						appslots[ksi].client != nil) {
					alt { appslots[ksi].client.kbd <-= c => ; * => ; }
					routed = 1;
					break;
				}
			}
			applock <-= 1;
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

writefile(path, data: string)
{
	fd := sys->open(path, Sys->OWRITE);
	if(fd != nil)
		sys->write(fd, array of byte data, len array of byte data);
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
		if(n > 214748364 || (n == 214748364 && (c - '0') > 7))
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

# writeappstatus: write appstatus to luciuisrv ctl and deliver event to lucipres.
# Takes explicit targetact so status updates go to the correct activity.
writeappstatus(id, status: string, targetact: int)
{
	if(targetact < 0) return;
	writetofile(sys->sprint("%s/activity/%d/presentation/ctl", mountpt, targetact),
		"appstatus id=" + id + " status=" + status);
	if(lucipres_g != nil)
		lucipres_g->deliverevent("presentation app " + id + " status=" + status);
}

# checklaunchapp: called when globallistener sees "applaunch <actid> <id>"
#
# If the new artifact has type=app, reads dispath and launches the GUI app.
# Uses the explicit targetact parameter — NEVER the global actid — so that
# apps always launch in the activity that created them.
# Also auto-centers the artifact so handleprescurrent() fires and hides all
# other apps — without this, the newly-launched app window starts at z-top
# but activeappid is never set, so subsequent "center mermaid" calls call
# hideapp("") which is a no-op, leaving the app window floating over content.
checklaunchapp(id: string, targetact: int)
{
	if(targetact < 0) return;
	base := sys->sprint("%s/activity/%d/presentation/%s", mountpt, targetact, id);
	atype := readfile(base + "/type");
	if(atype != nil) atype = strip(atype);
	if(atype != "app") return;
	dispath := readfile(base + "/dispath");
	if(dispath != nil) dispath = strip(dispath);
	if(dispath == "") return;
	# Read data field for app arguments (e.g., file path for edit)
	appdata := readfile(base + "/data");
	if(appdata != nil) appdata = strip(appdata);
	launchapp(id, dispath, appdata, targetact);
	# Auto-center the new app so handleprescurrent() hides other apps
	if(targetact >= 0)
		writetofile(sys->sprint("%s/activity/%d/presentation/ctl", mountpt, targetact),
			"center id=" + id);
}

# launchapp: allocate AppSlot, then spawn the GUI app with a per-app wmchan relay.
#
# Each app gets its own proxy wmchan.  appwmrelay intercepts the wmlib
# registration, records a token→id mapping, then forwards to the shared wmsrv.
# preswmloop's join handler looks up c.token to find the artifact id, so the
# mapping is correct regardless of the order apps happen to join.
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

launchapp(id, dispath, appdata: string, targetact: int)
{
	# Validate dispath against whitelist
	if(!validdispath(dispath)) {
		sys->fprint(stderr, "lucifer: blocked load of %s: not in allowed path\n", dispath);
		writeappstatus(id, "dead", targetact);
		return;
	}
	# Allocate AppSlot (client filled in later by preswmloop join handler)
	<-applock;
	if(nappslots >= MAXAPPSLOTS) {
		applock <-= 1;
		sys->fprint(stderr, "lucifer: max app slots reached, cannot launch %s\n", dispath);
		writeappstatus(id, "dead", targetact);
		return;
	}
	appslots[nappslots] = ref AppSlot(id, targetact, nil);
	nappslots++;
	applock <-= 1;
	# Load the GUI app module
	guimod := load GuiApp dispath;
	if(guimod == nil) {
		sys->fprint(stderr, "lucifer: cannot load %s: %r\n", dispath);
		writeappstatus(id, "dead", targetact);
		return;
	}
	# Create per-app proxy wmchan; the relay registers token→id before forwarding
	appwm := chan of (string, chan of (string, ref Wmcontext));
	spawn appwmrelay(id, appwm);
	newctxt := ref Draw->Context(display, presscr, appwm);
	appargs: list of string;
	if(appdata != nil && appdata != "") {
		# Tokenize appdata so multi-flag strings like "-c 1 -t dark -E"
		# arrive as separate list elements (argopt expects one flag per element).
		(nil, datatl) := sys->tokenize(appdata, " \t");
		appargs = dispath :: datatl;
	} else
		appargs = dispath :: nil;
	spawn guimod->init(newctxt, appargs);
	writeappstatus(id, "running", targetact);
}

# appwmrelay: per-app goroutine that intercepts the single wmlib registration
# (token string, reply channel) from the app's proxy wmchan, records a
# token→id mapping under applock, then forwards the registration to the
# shared wmchan so wmsrv processes the join as usual.
appwmrelay(id: string, appwm: chan of (string, chan of (string, ref Wmcontext)))
{
	(tokenstr, rc) := <-appwm;
	tok := int tokenstr;
	<-applock;
	addpending(tok, id);
	applock <-= 1;
	wmchan <-= (tokenstr, rc);
}

# addpending: register a token→id mapping (caller must hold applock).
addpending(token: int, id: string)
{
	if(npendingtokens < MAXTOKENPENDING) {
		pendingtokens[npendingtokens] = token;
		pendingids[npendingtokens] = id;
		npendingtokens++;
	}
}

# poppending: look up and remove a token→id mapping (caller must hold applock).
# Returns "" if no mapping found.
poppending(token: int): string
{
	for(i := 0; i < npendingtokens; i++) {
		if(pendingtokens[i] == token) {
			id := pendingids[i];
			for(j := i; j < npendingtokens - 1; j++) {
				pendingtokens[j] = pendingtokens[j+1];
				pendingids[j] = pendingids[j+1];
			}
			npendingtokens--;
			return id;
		}
	}
	return "";
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
			# Compact slot array
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
