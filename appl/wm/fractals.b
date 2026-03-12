implement Fractals;

#
# Mandelbrot/Julia fractal browser
#
# Ported from the original Inferno OS mand.b (Vita Nuova, 2000)
# to draw-only (no Tk) with contextual popup menu and Veltro
# agent integration via real-file IPC.
#
# Mouse:
#   Button 1     drag rectangle to zoom in
#   Button 2     show Julia set at cursor point (from Mandelbrot view)
#   Button 3     context menu (zoom out, depth, Julia presets, etc.)
#
# Veltro integration:
#   /tmp/veltro/fractal/ctl     write commands (zoomin, zoomout, julia, etc.)
#   /tmp/veltro/fractal/state   read current fractal state
#   /tmp/veltro/fractal/view    read view description for AI "vision"
#

include "sys.m";
	sys: Sys;

include "draw.m";
	draw: Draw;
	Display, Font, Image, Point, Rect: import draw;

include "wmclient.m";
	wmclient: Wmclient;
	Window: import wmclient;

include "menu.m";
	menumod: Menu;
	Popup: import menumod;

include "widget.m";
	widget: Widget;
	Statusbar: import widget;

Fractals: module
{
	init: fn(nil: ref Draw->Context, argv: list of string);
};

stderr: ref Sys->FD;
w: ref Window;
display: ref Display;
font: ref Font;
colours: array of ref Image;
sbar: ref Statusbar;

# Current fractal state (global for Veltro IPC)
g_specr: Fracrect;
g_morj: int;
g_julp: Fracpoint;
g_kdivisor: int;
g_fill: int;
g_computing: int;
g_stackdepth: int;

FIX: type big;

Calc: adt {
	xr, yr:		array of FIX;
	parx, pary:	FIX;
	dispbase:	array of byte;
	imgch:		chan of (ref Image, Rect);
	img:		ref Image;
	maxx, maxy:	int;
	supx, supy:	int;
	disp:		int;
	morj:		int;
	winr:		Rect;
	kdivisor:	int;
	pointsdone:	int;
};

# Fixed-point arithmetic: 60 bits of fraction in a 64-bit big.
# This gives ~18 decimal digits of precision while leaving 4 bits
# for the integer part (range roughly ±8), sufficient for the
# Mandelbrot escape radius of 4.
BASE:	con 60;
HBASE:	con BASE / 2;
SCALE:	con big 1 << BASE;
TWO:	con big 1 << (BASE + 1);
FOUR:	con big 1 << (BASE + 2);
NEG:	con ~((big 1 << (32 - HBASE)) - big 1);
MINDELTA: con big 1 << (HBASE - 1);

SCHEDCOUNT: con 100;

BLANK:	con 0;
BORDER:	con 255;
LIMIT:	con 4;
MAXCOUNT: con 253;
MAXDEPTH: con 20;	# cap depth multiplier to avoid freezing (20 * 253 = 5060 iterations)

# Initial size
WIDTH:	con 400;
HEIGHT:	con 400;

# Colour cube
R, G, B: int;

# Veltro IPC directory
FRACT_DIR: con "/tmp/veltro/fractal";

Fracpoint: adt {
	x, y: real;
};

Fracrect: adt {
	min, max: Fracpoint;
	dx:	fn(r: self Fracrect): real;
	dy:	fn(r: self Fracrect): real;
};

Params: adt {
	r:		Fracrect;
	p:		Fracpoint;
	m:		int;
	kdivisor:	int;
	fill:		int;
};

Usercmd: adt {
	pick {
	Zoomin =>
		fr: Fracrect;
	Julia =>
		fp: Fracpoint;
	Mandelbrot or
	Zoomout or
	Restart =>
	Depth =>
		d: int;
	Fill =>
		on: int;
	}
};

# Preset Julia sets with interesting visual character
Juliapreset: adt {
	label: string;
	c: Fracpoint;
};

JULIA_PRESETS: con 5;

juliapresets := array[JULIA_PRESETS] of {
	Juliapreset("dendrite", Fracpoint(0.0, 1.0)),
	Juliapreset("seahorse", Fracpoint(-0.75, 0.1)),
	Juliapreset("spiral", Fracpoint(-0.4, 0.6)),
	Juliapreset("rabbit", Fracpoint(-0.123, 0.745)),
	Juliapreset("star", Fracpoint(-0.744, 0.148)),
};

init(ctxt: ref Draw->Context, argv: list of string)
{
	sys = load Sys Sys->PATH;
	draw = load Draw Draw->PATH;
	wmclient = load Wmclient Wmclient->PATH;
	menumod = load Menu Menu->PATH;
	stderr = sys->fildes(2);

	if(ctxt == nil) {
		sys->fprint(stderr, "fractals: no window context\n");
		raise "fail:no context";
	}

	sys->pctl(Sys->NEWPGRP, nil);
	wmclient->init();

	# Parse colour cube args
	R = G = B = 6;
	argv = tl argv;
	if(argv != nil) { R = int hd argv; argv = tl argv; if(R <= 0) R = 1; }
	if(argv != nil) { G = int hd argv; argv = tl argv; if(G <= 0) G = 1; }
	if(argv != nil) { B = int hd argv; argv = tl argv; if(B <= 0) B = 1; }

	sys->sleep(100);
	w = wmclient->window(ctxt, "Fractals", Wmclient->Appl);
	display = w.display;

	font = Font.open(display, "/fonts/combined/unicode.14.font");
	if(font == nil)
		font = Font.open(display, "/fonts/10646/9x15/9x15.font");
	if(font == nil)
		font = Font.open(display, "*default*");

	# Build colour palette
	colours = array[256] of ref Image;
	for(i := 0; i < len colours; i++)
		colours[i] = display.rgb(col(i / (G * B), R),
					col(i / B, G),
					col(i, B));

	w.reshape(Rect((0, 0), (WIDTH, HEIGHT)));
	w.startinput("kbd" :: "ptr" :: nil);
	w.onscreen(nil);

	if(menumod != nil)
		menumod->init(display, font);

	widget = load Widget Widget->PATH;
	if(widget != nil)
		widget->init(display, font);

	# Initialize Veltro IPC
	initfractdir();

	# Create statusbar at bottom of window
	if(widget != nil) {
		wr := w.imager(w.image.r);
		sh := widget->statusheight();
		sbr := Rect((wr.min.x, wr.max.y - sh), wr.max);
		sbar = Statusbar.new(sbr);
		sbar.left = "Mandelbrot";
		sbar.right = "depth 1";
	}

	canvr := canvposn();
	specr := Fracrect((-2.0, -1.5), (1.0, 1.5));
	fill := 1;
	kdivisor := 1;
	morj := 1;	# 1=mandelbrot, 0=julia
	julp := Fracpoint(0.0, 0.0);

	# Set global state for Veltro
	g_specr = specr;
	g_morj = morj;
	g_julp = julp;
	g_kdivisor = kdivisor;
	g_fill = fill;
	g_computing = 1;
	g_stackdepth = 0;

	p := Params(
		correctratio(specr, canvr),
		julp,
		morj,
		kdivisor,
		fill
	);

	pid := -1;
	sync := chan of int;
	imgch := chan of (ref Image, Rect);
	if(!isempty(canvr)) {
		spawn docalculate(sync, p, imgch);
		pid = <-sync;
		imgch <-= (w.image, canvr);
	}

	stack: list of (Fracrect, Params);
	b1down := 0;
	b1start := Point(0, 0);

	# Tick timer for Veltro IPC polling
	ticks := chan of int;
	spawn timer(ticks, 500);

	writefractstate();
	updatesbar();

	for(;;) {
		restart := 0;
		alt {
		ctl := <-w.ctl or
		ctl = <-w.ctxt.ctl =>
			if(ctl == nil)
				;	# ignore nil ctl (wmsrv disconnect)
			else if(ctl[0] == '!') {
				if(pid != -1)
					restart = winreq(ctl, imgch, sync);
				else {
					w.wmctl(ctl);
					restart = 1;
				}
			} else
				w.wmctl(ctl);
		<-w.ctxt.kbd =>
			;	# ignore keyboard
		ptr := <-w.ctxt.ptr =>
			if(ptr == nil)
				;	# ignore nil ptr (wmsrv disconnect)
			else if(w.pointer(*ptr))
				;
			else if(ptr.buttons & 1) {
				# Button 1: start zoom drag
				if(!b1down) {
					b1down = 1;
					b1start = ptr.xy;
				}
			} else if(b1down && !(ptr.buttons & 1)) {
				# Button 1 release: zoom in
				b1down = 0;
				r := Rect(b1start, ptr.xy).canon();
				cr := canvposn();
				r = cliprect(r, cr);
				# Make relative to canvas
				r = r.subpt(cr.min);
				if(r.dx() > 4 && r.dy() > 4) {
					stack = (specr, p) :: stack;
					specr.min = pt2real(r.min, p.r);
					specr.max = pt2real(r.max, p.r);
					(specr.min.y, specr.max.y) = (specr.max.y, specr.min.y);
					restart = 1;
				}
			} else if(ptr.buttons & 2) {
				# Button 2: Julia set at cursor point (Mandelbrot mode only)
				if(p.m) {
					cr := canvposn();
					rp := ptr.xy.sub(cr.min);
					stack = (specr, p) :: stack;
					julp = pt2real(rp, p.r);
					specr = Fracrect((-2.0, -1.5), (1.0, 1.5));
					morj = 0;
					restart = 1;
				}
			} else if(ptr.buttons & 4) {
				# Button 3: context menu
				ucmd := showmenu(ptr);
				if(ucmd != nil)
				pick u := ucmd {
				Zoomout =>
					if(stack != nil) {
						((specr, p), stack) = (hd stack, tl stack);
						fill = p.fill;
						kdivisor = p.kdivisor;
						morj = p.m;
						julp = p.p;
						restart = 1;
					}
				Depth =>
					kdivisor = u.d;
					restart = 1;
				Fill =>
					fill = u.on;
					restart = 1;
				Julia =>
					stack = (specr, p) :: stack;
					julp = u.fp;
					specr = Fracrect((-2.0, -1.5), (1.0, 1.5));
					morj = 0;
					restart = 1;
				Mandelbrot =>
					stack = (specr, p) :: stack;
					specr = Fracrect((-2.0, -1.5), (1.0, 1.5));
					morj = 1;
					julp = Fracpoint(0.0, 0.0);
					kdivisor = 1;
					restart = 1;
				Restart =>
					specr = Fracrect((-2.0, -1.5), (1.0, 1.5));
					stack = nil;
					morj = 1;
					julp = Fracpoint(0.0, 0.0);
					kdivisor = 1;
					fill = 1;
					restart = 1;
				* =>
					;
				}
			}
		<-ticks =>
			changed := checkctlfile(specr, p, stack, morj, julp, kdivisor, fill);
			if(changed != nil)
			pick c := changed {
			Zoomin =>
				stack = (specr, p) :: stack;
				specr = c.fr;
				restart = 1;
			Zoomout =>
				if(stack != nil) {
					((specr, p), stack) = (hd stack, tl stack);
					fill = p.fill;
					kdivisor = p.kdivisor;
					morj = p.m;
					julp = p.p;
					restart = 1;
				}
			Julia =>
				stack = (specr, p) :: stack;
				julp = c.fp;
				specr = Fracrect((-2.0, -1.5), (1.0, 1.5));
				morj = 0;
				restart = 1;
			Mandelbrot =>
				stack = (specr, p) :: stack;
				specr = Fracrect((-2.0, -1.5), (1.0, 1.5));
				morj = 1;
				julp = Fracpoint(0.0, 0.0);
				kdivisor = 1;
				restart = 1;
			Depth =>
				kdivisor = c.d;
				restart = 1;
			Fill =>
				fill = c.on;
				restart = 1;
			Restart =>
				restart = 1;
			}
			writefractstate();
			updatesbar();
		<-sync =>
			w.image.flush(Draw->Flushon);
			pid = -1;
			g_computing = 0;
			writefractstate();
			updatesbar();
		}
		if(restart) {
			if(pid != -1)
				kill(pid);
			w.image.flush(Draw->Flushoff);
			# Reposition statusbar on resize
			if(sbar != nil && widget != nil) {
				wr := w.imager(w.image.r);
				sh := widget->statusheight();
				sbar.resize(Rect((wr.min.x, wr.max.y - sh), wr.max));
			}
			wr := canvposn();
			if(!isempty(wr)) {
				p = Params(correctratio(specr, wr), julp, morj, kdivisor, fill);
				# Update globals
				g_specr = specr;
				g_morj = morj;
				g_julp = julp;
				g_kdivisor = kdivisor;
				g_fill = fill;
				g_computing = 1;
				g_stackdepth = len stack;
				sync = chan of int;
				imgch = chan of (ref Image, Rect);
				spawn docalculate(sync, p, imgch);
				pid = <-sync;
				imgch <-= (w.image, wr);
				writefractstate();
				updatesbar();
			}
		}
	}
}

showmenu(ptr: ref Draw->Pointer): ref Usercmd
{
	if(menumod == nil)
		return nil;
	fillstr := "fill on";
	if(g_fill)
		fillstr = "fill off";

	# Build menu items depending on current mode
	items: list of string;
	if(g_morj) {
		# In Mandelbrot mode: offer Julia presets
		items = "zoom out"
			:: "depth+"
			:: "depth-"
			:: fillstr
			:: "---"
			:: nil;
		for(i := len juliapresets - 1; i >= 0; i--)
			items = sys->sprint("julia: %s", juliapresets[i].label) :: items;
		items = rev(items);
		items = append(items, "---" :: "reset" :: "exit" :: nil);
	} else {
		# In Julia mode: offer switch back to Mandelbrot
		items = "zoom out"
			:: "depth+"
			:: "depth-"
			:: fillstr
			:: "---"
			:: "mandelbrot"
			:: "---"
			:: "reset"
			:: "exit"
			:: nil;
	}

	# Convert to array, filtering out separators
	nitems := 0;
	for(l := items; l != nil; l = tl l) {
		if(hd l != "---")
			nitems++;
	}
	menuarr := array[nitems] of string;
	mi := 0;
	for(l = items; l != nil; l = tl l) {
		if(hd l != "---")
			menuarr[mi++] = hd l;
	}

	menu := menumod->new(menuarr);
	n := menu.show(w.image, ptr.xy, w.ctxt.ptr);
	if(n < 0 || n >= len menuarr)
		return nil;

	sel := menuarr[n];

	case sel {
	"zoom out" =>
		return ref Usercmd.Zoomout;
	"depth+" =>
		d := g_kdivisor + 1;
		if(d > MAXDEPTH) d = MAXDEPTH;
		return ref Usercmd.Depth(d);
	"depth-" =>
		d := g_kdivisor - 1;
		if(d < 1) d = 1;
		return ref Usercmd.Depth(d);
	"fill on" or "fill off" =>
		return ref Usercmd.Fill(!g_fill);
	"mandelbrot" =>
		return ref Usercmd.Mandelbrot;
	"reset" =>
		return ref Usercmd.Restart;
	"exit" =>
		postnote(1, sys->pctl(0, nil), "kill");
		exit;
	* =>
		# Check for Julia preset selection
		if(len sel > 7 && sel[0:7] == "julia: ") {
			name := sel[7:];
			for(i := 0; i < len juliapresets; i++) {
				if(juliapresets[i].label == name)
					return ref Usercmd.Julia(juliapresets[i].c);
			}
		}
	}
	return nil;
}

rev(l: list of string): list of string
{
	r: list of string;
	for(; l != nil; l = tl l)
		r = hd l :: r;
	return r;
}

append(a, b: list of string): list of string
{
	if(a == nil)
		return b;
	r := rev(a);
	for(; b != nil; b = tl b)
		r = hd b :: r;
	return rev(r);
}

updatesbar()
{
	if(sbar == nil)
		return;
	ftype := "Mandelbrot";
	if(!g_morj) {
		ftype = "Julia";
		# Show Julia parameter in statusbar
		ftype += sys->sprint(" c=(%.3g, %.3g)", g_julp.x, g_julp.y);
	}
	sbar.left = ftype;
	status := "ready";
	if(g_computing)
		status = "computing...";
	sbar.right = sys->sprint("depth %d | %s", g_kdivisor, status);
	sbar.draw(w.image);
}

winreq(ctl: string, imgch: chan of (ref Image, Rect), terminated: chan of int): int
{
	oldimage := w.image;
	if(imgch != nil) {
		alt {
		imgch <-= (nil, ((0, 0), (0, 0))) =>;
		<-terminated =>
			imgch = nil;
		}
	}
	w.wmctl(ctl);
	if(w.image != oldimage)
		return 1;
	if(imgch != nil)
		imgch <-= (w.image, canvposn());
	return 0;
}

correctratio(r: Fracrect, wr: Rect): Fracrect
{
	if(isempty(wr))
		return Fracrect((0.0, 0.0), (0.0, 0.0));
	btall := real wr.dy() / real wr.dx();
	atall := r.dy() / r.dx();
	if(btall > atall) {
		excess := r.dx() * btall - r.dy();
		r.min.y -= excess / 2.0;
		r.max.y += excess / 2.0;
	} else {
		excess := r.dy() / btall - r.dx();
		r.min.x -= excess / 2.0;
		r.max.x += excess / 2.0;
	}
	return r;
}

pt2real(pt: Point, r: Fracrect): Fracpoint
{
	sz := canvsize();
	return Fracpoint(
		real pt.x / real sz.x * (r.max.x - r.min.x) + r.min.x,
		real (sz.y - pt.y) / real sz.y * (r.max.y - r.min.y) + r.min.y
	);
}

canvposn(): Rect
{
	r := w.imager(w.image.r);
	if(sbar != nil && widget != nil) {
		sh := widget->statusheight();
		r.max.y -= sh;
		if(r.max.y < r.min.y)
			r.max.y = r.min.y;
	}
	return r;
}

canvsize(): Point
{
	r := canvposn();
	return Point(r.dx(), r.dy());
}

cliprect(r, bounds: Rect): Rect
{
	if(r.min.x < bounds.min.x) r.min.x = bounds.min.x;
	if(r.min.y < bounds.min.y) r.min.y = bounds.min.y;
	if(r.max.x > bounds.max.x) r.max.x = bounds.max.x;
	if(r.max.y > bounds.max.y) r.max.y = bounds.max.y;
	return r;
}

isempty(r: Rect): int
{
	return r.dx() <= 0 || r.dy() <= 0;
}

timer(c: chan of int, ms: int)
{
	for(;;) {
		sys->sleep(ms);
		c <-= 1;
	}
}

# ---- Fractal calculation ----

poll(calc: ref Calc)
{
	if(calc.img != nil)
		calc.img.flush(Draw->Flushnow);
	alt {
	<-calc.imgch =>
		calc.img = nil;
		(calc.img, calc.winr) = <-calc.imgch;
	* =>;
	}
}

docalculate(sync: chan of int, p: Params, imgch: chan of (ref Image, Rect))
{
	sync <-= sys->pctl(0, nil);
	calculate(p, imgch);
	sync <-= 0;
}

calculate(p: Params, imgch: chan of (ref Image, Rect))
{
	calc := ref Calc;
	(calc.img, calc.winr) = <-imgch;
	r := calc.winr;
	calc.maxx = r.dx();
	calc.maxy = r.dy();
	calc.supx = calc.maxx + 2;
	calc.supy = calc.maxy + 2;
	calc.imgch = imgch;
	calc.xr = array[calc.maxx] of FIX;
	calc.yr = array[calc.maxy] of FIX;
	calc.morj = p.m;
	initr(calc, p);

	# Clear to white
	calc.img.draw(r, calc.img.display.white, nil, (0, 0));

	if(p.fill) {
		calc.dispbase = array[calc.supx * calc.supy] of byte;
		calc.disp = calc.maxy + 3;
		setdisp(calc);
		displayset(calc);
	} else {
		for(x := 0; x < calc.maxx; x++)
			for(y := 0; y < calc.maxy; y++)
				point(calc, calc.img, (x, y), pointcolour(calc, x, y));
	}
}

setdisp(calc: ref Calc)
{
	for(i := 0; i < calc.supx * calc.supy; i++)
		calc.dispbase[i] = byte BLANK;

	# Top border
	d := 0;
	for(i = 0; i < calc.supx; i++) {
		calc.dispbase[d] = byte BORDER;
		d += calc.supy;
	}
	# Left border
	for(i = 0; i < calc.supy; i++)
		calc.dispbase[i] = byte BORDER;
	# Bottom border
	d = calc.supx * calc.supy - 1;
	for(i = 0; i < calc.supx; i++) {
		calc.dispbase[d] = byte BORDER;
		d -= calc.supy;
	}
	# Right border
	d = calc.supx * calc.supy - 1;
	for(i = 0; i < calc.supy; i++) {
		calc.dispbase[d] = byte BORDER;
		d--;
	}
}

initr(calc: ref Calc, p: Params)
{
	r := p.r;
	dp := real2fix((r.max.x - r.min.x) / real calc.maxx);
	dq := real2fix((r.max.y - r.min.y) / real calc.maxy);
	calc.xr[0] = real2fix(r.min.x) - (big calc.maxx * dp - (real2fix(r.max.x) - real2fix(r.min.x))) / big 2;
	for(x := 1; x < calc.maxx; x++)
		calc.xr[x] = calc.xr[x - 1] + dp;
	calc.yr[0] = real2fix(r.max.y) + (big calc.maxy * dq - (real2fix(r.max.y) - real2fix(r.min.y))) / big 2;
	for(y := 1; y < calc.maxy; y++)
		calc.yr[y] = calc.yr[y - 1] - dq;
	calc.parx = real2fix(p.p.x);
	calc.pary = real2fix(p.p.y);
	calc.kdivisor = p.kdivisor;
	calc.pointsdone = 0;
}

pointcolour(calc: ref Calc, x, y: int): int
{
	if(++calc.pointsdone >= SCHEDCOUNT) {
		calc.pointsdone = 0;
		sys->sleep(0);
		poll(calc);
	}
	if(calc.morj)
		return mcount(calc, x, y) + 1;
	else
		return jcount(calc, x, y) + 1;
}

mcount(calc: ref Calc, x_coord, y_coord: int): int
{
	(p, q) := (calc.xr[x_coord], calc.yr[y_coord]);
	(x, y) := (calc.parx, calc.pary);
	k := 0;
	maxcount := MAXCOUNT * calc.kdivisor;
	while(k < maxcount) {
		if(x >= TWO || y >= TWO || x <= -TWO || y <= -TWO)
			break;
		x >>= HBASE;
		y >>= HBASE;
		t := y * y;
		y = big 2 * x * y + q;
		x *= x;
		if(x + t >= FOUR)
			break;
		x -= t - p;
		k++;
	}
	return k / calc.kdivisor;
}

jcount(calc: ref Calc, x_coord, y_coord: int): int
{
	(x, y) := (calc.xr[x_coord], calc.yr[y_coord]);
	(p, q) := (calc.parx, calc.pary);
	k := 0;
	maxcount := MAXCOUNT * calc.kdivisor;
	while(k < maxcount) {
		if(x >= TWO || y >= TWO || x <= -TWO || y <= -TWO)
			break;
		x >>= HBASE;
		y >>= HBASE;
		t := y * y;
		y = big 2 * x * y + q;
		x *= x;
		if(x + t >= FOUR)
			break;
		x -= t - p;
		k++;
	}
	return k / calc.kdivisor;
}

getcolour(calc: ref Calc, x, y, d: int): int
{
	if(calc.dispbase[d] == byte BLANK) {
		calc.dispbase[d] = byte pointcolour(calc, x, y);
		point(calc, calc.img, (x, y), int calc.dispbase[d]);
	}
	return int calc.dispbase[d];
}

fillline(calc: ref Calc, x, y, d, dir, dird, col: int)
{
	x0 := x;
	while(calc.dispbase[d] == byte BLANK) {
		calc.dispbase[d] = byte col;
		x -= dir;
		d -= dird;
	}
	horizline(calc, calc.img, x0, x, y, col);
}

# Re-trace boundary and fill interior scan-lines with fillline.
crawlt(calc: ref Calc, x, y, d, col: int)
{
	yinc, dyinc: int;
	firstd := d;
	xinc := 1;
	dxinc := calc.supy;

	for(;;) {
		if(getcolour(calc, x + xinc, y, d + dxinc) == col) {
			x += xinc;
			d += dxinc;
			yinc = -xinc;
			dyinc = -dxinc;
			if(calc.dispbase[d + dxinc] == byte BLANK)
				fillline(calc, x + xinc, y, d + dxinc, yinc, dyinc, col);
			if(d == firstd)
				break;
		} else {
			yinc = xinc;
			dyinc = dxinc;
		}
		if(getcolour(calc, x, y + yinc, d + yinc) == col) {
			y += yinc;
			d += yinc;
			xinc = yinc;
			dxinc = dyinc;
			if(calc.dispbase[d - dxinc] == byte BLANK)
				fillline(calc, x - xinc, y, d - dxinc, yinc, dyinc, col);
			if(d == firstd)
				break;
		} else {
			xinc = -yinc;
			dxinc = -dyinc;
		}
	}
}

# Trace boundary of a same-colour region, computing its signed area.
# If the area is positive (clockwise winding), hand off to crawlt to fill.
crawlf(calc: ref Calc, x, y, d, col: int)
{
	xinc, yinc, dxinc, dyinc: int;
	area := 0;
	count := 0;

	firstd := d;
	xinc = 1;
	dxinc = calc.supy;

	for(;;) {
		if(getcolour(calc, x + xinc, y, d + dxinc) == col) {
			x += xinc;
			d += dxinc;
			yinc = -xinc;
			dyinc = -dxinc;
			area += xinc * count;
			if(d == firstd)
				break;
		} else {
			yinc = xinc;
			dyinc = dxinc;
		}
		if(getcolour(calc, x, y + yinc, d + yinc) == col) {
			y += yinc;
			d += yinc;
			xinc = yinc;
			dxinc = dyinc;
			count -= yinc;
			if(d == firstd)
				break;
		} else {
			xinc = -yinc;
			dxinc = -dyinc;
		}
	}
	if(area > 0)
		crawlt(calc, x, y, firstd, col);
}

# Boundary-trace fill: scan columns for runs of identical colour.
# When a run of LIMIT identical pixels is found, crawlf traces the
# boundary of the region and crawlt flood-fills the interior using
# horizline, avoiding per-pixel computation for large solid areas.
displayset(calc: ref Calc)
{
	last := BLANK;
	edge := 0;
	d := calc.disp;

	for(x := 0; x < calc.maxx; x++) {
		for(y := 0; y < calc.maxy; y++) {
			col := calc.dispbase[d];
			if(col == byte BLANK) {
				col = byte pointcolour(calc, x, y);
				calc.dispbase[d] = col;
				point(calc, calc.img, (x, y), int col);
				if(int col == last)
					edge++;
				else {
					last = int col;
					edge = 0;
				}
				if(edge >= LIMIT) {
					crawlf(calc, x, y - edge, d - edge, last);
					last = BLANK;
				}
			} else {
				if(int col == last)
					edge++;
				else {
					last = int col;
					edge = 0;
				}
			}
			d++;
		}
		last = BLANK;
		edge = 0;
		d += 2;
	}
}

point(calc: ref Calc, d: ref Image, p: Point, col: int)
{
	d.draw(Rect(p, p.add((1, 1))).addpt(calc.winr.min), colours[col], nil, (0, 0));
}

horizline(calc: ref Calc, d: ref Image, x0, x1, y: int, col: int)
{
	if(x0 < x1)
		r := Rect((x0, y), (x1, y + 1));
	else
		r = Rect((x1 + 1, y), (x0 + 1, y + 1));
	d.draw(r.addpt(calc.winr.min), colours[col], nil, (0, 0));
}

# ---- Veltro real-file IPC ----
#
# /tmp/veltro/fractal/ is inside the restricted agent namespace.
# The tick loop polls command files and writes state files so the
# Veltro fractal tool can drive the viewer across namespace forks.

initfractdir()
{
	mkdirq("/tmp/veltro");
	mkdirq(FRACT_DIR);
}

mkdirq(path: string)
{
	fd := sys->open(path, Sys->OREAD);
	if(fd != nil) {
		fd = nil;
		return;
	}
	fd = sys->create(path, Sys->OREAD, Sys->DMDIR | 8r755);
	fd = nil;
}

writefractstate()
{
	ftype := "mandelbrot";
	if(!g_morj)
		ftype = "julia";

	state := sys->sprint("type %s\n", ftype);
	state += sys->sprint("view %g %g %g %g\n", g_specr.min.x, g_specr.min.y, g_specr.max.x, g_specr.max.y);
	if(!g_morj)
		state += sys->sprint("julia %g %g\n", g_julp.x, g_julp.y);
	state += sys->sprint("depth %d\n", g_kdivisor);
	state += sys->sprint("fill %d\n", g_fill);
	state += sys->sprint("computing %d\n", g_computing);
	state += sys->sprint("zoomdepth %d\n", g_stackdepth);
	writestatefile(FRACT_DIR + "/state", state);

	# Human-readable view description for Veltro vision
	view := sys->sprint("Fractal viewer: %s set\n", ftype);
	view += sys->sprint("Viewing region: x=[%g, %g] y=[%g, %g]\n",
		g_specr.min.x, g_specr.max.x, g_specr.min.y, g_specr.max.y);
	dx := g_specr.max.x - g_specr.min.x;
	dy := g_specr.max.y - g_specr.min.y;
	view += sys->sprint("Region size: %g x %g\n", dx, dy);
	cx := (g_specr.min.x + g_specr.max.x) / 2.0;
	cy := (g_specr.min.y + g_specr.max.y) / 2.0;
	view += sys->sprint("Center: (%g, %g)\n", cx, cy);
	if(!g_morj)
		view += sys->sprint("Julia parameter: c = %g + %gi\n", g_julp.x, g_julp.y);
	view += sys->sprint("Depth multiplier: %d (max iterations: %d)\n", g_kdivisor, MAXCOUNT * g_kdivisor);
	view += sys->sprint("Fill mode: %s\n", boolstr(g_fill));
	if(g_computing)
		view += "Status: computing...\n";
	else
		view += "Status: ready\n";
	view += sys->sprint("Zoom history: %d levels deep\n", g_stackdepth);

	# Describe notable regions when viewing the full Mandelbrot set
	if(g_morj && dx > 2.5) {
		view += "\nNotable regions to explore:\n";
		view += "  Main cardioid: center ~(-0.25, 0), the large heart shape\n";
		view += "  Period-2 bulb: center ~(-1.0, 0), the large circle to the left\n";
		view += "  Seahorse valley: between cardioid and bulb ~(-0.75, 0.1)\n";
		view += "  Elephant valley: ~(0.28, 0.008)\n";
		view += "  Antenna tip: ~(-1.788, 0)\n";
		view += "  Mini-Mandelbrot: ~(-1.768, 0.002)\n";
	}

	# Describe notable Julia sets when viewing Julia
	if(!g_morj && dx > 2.5) {
		view += "\nJulia set presets (try via menu or 'fractal julia <re> <im>'):\n";
		view += "  Dendrite:  c = 0 + 1i (tree-like filaments)\n";
		view += "  Seahorse:  c = -0.75 + 0.1i (spiral arms)\n";
		view += "  Spiral:    c = -0.4 + 0.6i (connected spiral)\n";
		view += "  Rabbit:    c = -0.123 + 0.745i (Douady's rabbit)\n";
		view += "  Star:      c = -0.744 + 0.148i (star-shaped)\n";
	}

	writestatefile(FRACT_DIR + "/view", view);
}

boolstr(b: int): string
{
	if(b) return "on";
	return "off";
}

writestatefile(path, data: string)
{
	fd := sys->create(path, Sys->OWRITE, 8r666);
	if(fd == nil)
		return;
	b := array of byte data;
	sys->write(fd, b, len b);
	fd = nil;
}

# Parse commands from /tmp/veltro/fractal/ctl
# Commands:
#   zoomin <x1> <y1> <x2> <y2>   zoom to fractal coordinates
#   zoomout                       go back one level
#   julia <re> <im>              show Julia set for c = re + im*i
#   mandelbrot                    switch back to Mandelbrot set
#   depth <n>                     set depth multiplier
#   fill on|off                   toggle boundary fill
#   restart                       restart current computation
#   center <re> <im> <radius>    zoom to center with radius

checkctlfile(specr: Fracrect, p: Params, stack: list of (Fracrect, Params),
	morj: int, julp: Fracpoint, kdivisor, fill: int): ref Usercmd
{
	cmd := readrmfile(FRACT_DIR + "/ctl");
	if(cmd == nil || cmd == "")
		return nil;

	(nil, toks) := sys->tokenize(cmd, " \t\n");
	if(toks == nil)
		return nil;

	verb := hd toks;
	toks = tl toks;

	case verb {
	"zoomin" =>
		if(listlen(toks) < 4)
			return nil;
		x1 := real hd toks; toks = tl toks;
		y1 := real hd toks; toks = tl toks;
		x2 := real hd toks; toks = tl toks;
		y2 := real hd toks;
		# Canonicalize
		if(x1 > x2) (x1, x2) = (x2, x1);
		if(y1 > y2) (y1, y2) = (y2, y1);
		return ref Usercmd.Zoomin(Fracrect((x1, y1), (x2, y2)));
	"center" =>
		if(listlen(toks) < 3)
			return nil;
		cx := real hd toks; toks = tl toks;
		cy := real hd toks; toks = tl toks;
		rad := real hd toks;
		if(rad <= 0.0) rad = 0.1;
		return ref Usercmd.Zoomin(Fracrect((cx - rad, cy - rad), (cx + rad, cy + rad)));
	"zoomout" =>
		return ref Usercmd.Zoomout;
	"julia" =>
		if(listlen(toks) < 2)
			return nil;
		re := real hd toks; toks = tl toks;
		im := real hd toks;
		return ref Usercmd.Julia(Fracpoint(re, im));
	"mandelbrot" =>
		return ref Usercmd.Mandelbrot;
	"depth" =>
		if(toks == nil)
			return nil;
		d := int hd toks;
		if(d < 1) d = 1;
		if(d > MAXDEPTH) d = MAXDEPTH;
		return ref Usercmd.Depth(d);
	"fill" =>
		if(toks == nil)
			return nil;
		on := 0;
		if(hd toks == "on" || hd toks == "1")
			on = 1;
		return ref Usercmd.Fill(on);
	"restart" =>
		return ref Usercmd.Restart;
	}
	return nil;
}

readrmfile(path: string): string
{
	fd := sys->open(path, Sys->OREAD);
	if(fd == nil)
		return nil;
	buf := array[4096] of byte;
	n := sys->read(fd, buf, len buf);
	fd = nil;
	if(n <= 0)
		return nil;
	s := string buf[0:n];
	# Truncate file to consume the command
	fd = sys->create(path, Sys->OWRITE, 8r666);
	fd = nil;
	# Strip trailing whitespace
	while(len s > 0 && (s[len s - 1] == '\n' || s[len s - 1] == ' ' || s[len s - 1] == '\t'))
		s = s[0:len s - 1];
	return s;
}

listlen(l: list of string): int
{
	n := 0;
	for(; l != nil; l = tl l)
		n++;
	return n;
}

# ---- Utilities ----

Fracrect.dx(r: self Fracrect): real
{
	return r.max.x - r.min.x;
}

Fracrect.dy(r: self Fracrect): real
{
	return r.max.y - r.min.y;
}

real2fix(x: real): FIX
{
	return big(x * real SCALE);
}

col(i, r: int): int
{
	if(r == 1)
		return 0;
	return (255 * (i % r)) / (r - 1);
}

kill(pid: int): int
{
	fd := sys->open("#p/" + string pid + "/ctl", Sys->OWRITE);
	if(fd == nil)
		return -1;
	if(sys->write(fd, array of byte "kill", 4) != 4)
		return -1;
	return 0;
}

postnote(t: int, pid: int, note: string): int
{
	fd := sys->open("#p/" + string pid + "/ctl", Sys->OWRITE);
	if(fd == nil)
		return -1;
	if(t == 1)
		note += "grp";
	sys->fprint(fd, "%s", note);
	fd = nil;
	return 0;
}
