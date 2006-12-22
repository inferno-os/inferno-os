implement Volumectl;

include "sys.m";
sys: Sys;
sprint: import sys;

include "draw.m";
draw: Draw;
Context, Display, Font, Rect, Point, Image, Screen, Pointer: import draw;

include "prefab.m";
prefab: Prefab;
Style, Element, Compound, Environ: import prefab;

include "muxclient.m";
include "volume.m";

include "bufio.m";
bufio: Bufio;
Iobuf: import bufio;

include "ir.m";

screen: ref Screen;
display: ref Display;
windows: array of ref Image;
env: ref Environ;
zr := ((0,0),(0,0));

el, et: ref Element;

style: ref Style;

c: ref Compound;

tics: int;
INTERVAL: con 500;

value: int;

ones, white, red: ref Image;

volumectl(ctxt: ref Context, ch: chan of int, var: string)
{
	key: int;

	sys = load Sys Sys->PATH;
	draw = load Draw Draw->PATH;
	prefab = load Prefab Prefab->PATH;
	if ((bufio = load Bufio Bufio->PATH) == nil) {
		sys->print("Audioctl: Can't load bufio\n");
		exit;
	}

	if ((ac := bufio->open("/dev/volume", bufio->ORDWR)) == nil) {
		sys->print("Audioctl: Can't open /dev/volume: %r\n");
		exit;
	}

	screen = ctxt.screen;
	display = ctxt.display;
	windows = array[1] of ref Image;

	ones = display.opaque;
	white = display.color(draw->White);
	red = display.color(draw->Red);

	textfont := Font.open(display, "*default*");

	style = ref Style(
			textfont,			# titlefont
			textfont,			# textfont
			display.color(draw->White),	# elemcolor
			display.color(draw->Black),	# edgecolor
			display.color(draw->Yellow),	# titlecolor	
			display.color(draw->Black),	# textcolor
			display.color(130));		# highlightcolor

	env = ref Environ (ctxt.screen, style);

	slavectl := chan of int;
	spawn timerslave(slavectl);

	while ((s := ac.gets('\n')) != nil) {
		sp := -1;
		for (i := 0; i < len s; i++) if (s[i] == ' ') sp = i;
		if (sp <= 1) {
			sys->print("Volume: /dev/volume bad:\n%s\n", s);
			exit;
		}
		if (var == s[0:sp]) {
			value = int s[sp+1:];
		}
	}

	n := 0;
	for(;;) {
		key = <- ch;
		case key {
		Ir->Enter =>
			slavectl <-= Muxclient->AMexit;
			return;
		Ir->VolUP =>
			if (value++ >= 100) value = 100;
			ac.puts(sprint("%s %d\n", var, value));
			displayslider();
		Ir->VolDN =>
			if (value-- <= 0) value = 0;
			ac.puts(sprint("%s %d\n", var, value));
			displayslider();
		}
	}
}

slider(): ref Element
{
	r: Rect;

	r = ((0,0),(200,20));
	chans := display.image.chans;
	icon := display.newimage(r.inset(-2), chans, 0, draw->Black);
	icon.draw(r, white, ones, (0,0));
	rr := r;
	rr.max.x = 2*value;
	icon.draw(rr, red, ones, (0,0));
	return Element.icon(env, zr, icon, ones);
}

displayslider()
{
	if (et == nil) {
		et = Element.text(env, "Volume", zr, Prefab->EText);
		el = slider();
	}

	img := el.image;
	r: Rect = ((0,0),(200,20));
	img.draw(r, white, nil, (0,0));
	r.max.x = 2*value;
	img.draw(r, red, nil, (0,0));

	if (c == nil) {
		c = Compound.box(env, Point(100, 100), et, el);
		windows[0] = c.image;
	}
	c.draw();
	screen.top(windows);
	tics = 5;
}

timerslave(ctl: chan of int)
{
	m: int;

	for(;;) {
		sys->sleep(INTERVAL);
		if (tics-- <= 0) {
			tics = 0;
			c = nil;
			el = nil;
			et = nil;
			windows[0] = nil;
		}

		alt{
		m = <-ctl =>
			return;
		* =>
			continue;
		}
	}
}
