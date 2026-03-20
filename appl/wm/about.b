implement About;

#
# About InferNode — native Draw + Widget version
#
# Displays the InferNode logo, system version, and project info
# using Widget->Label for themed text (no Tk dependency).
#

include "sys.m";
	sys: Sys;

include "draw.m";
	draw: Draw;
	Display, Font, Image, Point, Rect: import draw;

include "bufio.m";

include "imagefile.m";

include "wmclient.m";
	wmclient: Wmclient;
	Window: import wmclient;

include "lucitheme.m";
	lucitheme: Lucitheme;
	Theme: import lucitheme;

include "widget.m";
	widgetmod: Widget;
	Label, CENTER: import widgetmod;

About: module
{
	init: fn(ctxt: ref Draw->Context, argv: list of string);
};

ZP := Point(0, 0);

WINW: con 600;
WINH: con 590;
PADDING: con 12;
LINEH: con 18;	# line height for body labels

init(ctxt: ref Draw->Context, nil: list of string)
{
	sys = load Sys Sys->PATH;
	if(ctxt == nil) {
		sys->fprint(sys->fildes(2), "about: no window context\n");
		raise "fail:bad context";
	}

	draw = load Draw Draw->PATH;
	wmclient = load Wmclient Wmclient->PATH;
	lucitheme = load Lucitheme Lucitheme->PATH;
	widgetmod = load Widget Widget->PATH;

	sys->pctl(Sys->NEWPGRP, nil);
	wmclient->init();

	w := wmclient->window(ctxt, "About InferNode", Wmclient->Appl);
	display := w.display;

	# Init widget module with body font
	bodyfont := Font.open(display, "/fonts/combined/unicode.sans.12.font");
	if(bodyfont == nil)
		bodyfont = Font.open(display, "/fonts/combined/unicode.sans.14.font");
	if(bodyfont == nil)
		bodyfont = Font.open(display, "*default*");
	widgetmod->init(display, bodyfont);

	w.reshape(Rect((0, 0), (WINW, WINH)));
	w.startinput("ptr" :: "kbd" :: nil);
	w.onscreen(nil);

	redraw(w, display);

	# Listen for live theme changes
	themech := chan of int;
	spawn themelistener(themech);

	for(;;) alt {
	ctl := <-w.ctl or
	ctl = <-w.ctxt.ctl =>
		w.wmctl(ctl);
		if(ctl != nil && ctl[0] == '!')
			redraw(w, display);

	<-w.ctxt.kbd =>
		;	# ignore keyboard

	p := <-w.ctxt.ptr =>
		w.pointer(*p);

	<-themech =>
		widgetmod->retheme(display);
		redraw(w, display);
	}
}

redraw(w: ref Window, display: ref Display)
{
	screen := w.image;
	if(screen == nil)
		return;

	# Load theme
	theme: ref Theme;
	if(lucitheme != nil)
		theme = lucitheme->gettheme();
	if(theme == nil)
		theme = ref Theme;

	bg := display.color(theme.bg | 16rFF);
	accent := display.color(theme.accent | 16rFF);
	dimcol := display.color(theme.dim | 16rFF);

	# Clear background
	screen.draw(screen.r, bg, nil, ZP);

	# Draw border
	screen.border(screen.r, 1, accent, ZP);

	# Title font (larger than widget font)
	titlefont := Font.open(display, "/fonts/combined/unicode.sans.18.font");
	if(titlefont == nil)
		titlefont = Font.open(display, "/fonts/combined/unicode.sans.14.font");
	if(titlefont == nil)
		titlefont = Font.open(display, "*default*");

	r := screen.r;
	cx := (r.min.x + r.max.x) / 2;
	y := r.min.y + PADDING;

	# Load and draw logo via PNG decoder (display.open only handles Plan 9 format)
	logopath := "/lib/lucifer/about-screen.png";
	themename := rf("/lib/lucifer/theme/current");
	if(themename != nil) {
		while(len themename > 0 && (themename[len themename - 1] == '\n' || themename[len themename - 1] == ' '))
			themename = themename[:len themename - 1];
		if(themename != "brimstone" && themename != "") {
			tpath := "/lib/lucifer/logo-" + themename + ".png";
			tfd := sys->open(tpath, Sys->OREAD);
			if(tfd != nil)
				logopath = tpath;
		}
	}
	logo: ref Image;
	{
		bufio := load Bufio Bufio->PATH;
		if(bufio != nil) {
			readpng := load RImagefile RImagefile->READPNGPATH;
			remap := load Imageremap Imageremap->PATH;
			if(readpng != nil && remap != nil) {
				readpng->init(bufio);
				remap->init(display);
				fd := bufio->open(logopath, Bufio->OREAD);
				if(fd != nil) {
					(raw, nil) := readpng->read(fd);
					if(raw != nil)
						(logo, nil) = remap->remap(raw, display, 0);
				}
			}
		}
	}
	if(logo != nil) {
		lw := logo.r.dx();
		lh := logo.r.dy();
		if(lw < 48) {
			scale := 4;
			sw := lw * scale;
			sh := lh * scale;
			dst := Rect((cx - sw/2, y), (cx + sw/2, y + sh));
			scaled := display.newimage(dst, screen.chans, 0, Draw->Nofill);
			if(scaled != nil) {
				scaleblit(scaled, logo, scale);
				screen.draw(dst, scaled, nil, dst.min);
			}
			y += sh + PADDING * 2;
		} else {
			lx := cx - lw/2;
			dst := Rect((lx, y), (lx + lw, y + lh));
			screen.draw(dst, logo, nil, logo.r.min);
			y += lh + PADDING * 2;
		}
	} else
		y += PADDING;

	# Title — uses larger font, drawn manually
	title := "InferNode";
	tw := titlefont.width(title);
	screen.text(Point(cx - tw/2, y), accent, ZP, titlefont, title);
	y += titlefont.height + 4;

	# Version from sysctl — Widget Label
	version := rf("/dev/sysctl");
	if(version != nil) {
		vl := Label.mk(Rect((r.min.x, y), (r.max.x, y + LINEH)), version, 0, CENTER);
		vl.draw(screen);
		y += LINEH;
	}

	# Separator line
	y += 8;
	screen.line(Point(r.min.x + PADDING*2, y), Point(r.max.x - PADDING*2, y),
		0, 0, 0, dimcol, ZP);
	y += 12;

	# Description lines — Widget Labels
	# (text, dim) pairs: dim=1 for URLs
	lines := array[] of {
		("Inferno\u00AE Operating System", 0),
		("", 0),
		("Originally by Bell Labs (Lucent)", 0),
		("Vita Nuova Holdings", 0),
		("", 0),
		("InferNode fork by", 0),
		("infernode-os", 0),
		("", 0),
		("lucent.com/inferno", 1),
		("infernode.io", 1),
		("github.com/infernode-os", 1),
	};

	for(i := 0; i < len lines; i++) {
		(text, dim) := lines[i];
		if(text == nil || len text == 0) {
			y += LINEH / 2;
			continue;
		}
		l := Label.mk(Rect((r.min.x, y), (r.max.x, y + LINEH)), text, dim, CENTER);
		l.draw(screen);
		y += LINEH;
	}

	screen.flush(Draw->Flushnow);
}

# Nearest-neighbor scale: blit src into dst at integer scale factor
scaleblit(dst, src: ref Image, scale: int)
{
	sw := src.r.dx();
	sh := src.r.dy();
	bpp := src.depth / 8;
	if(bpp < 1)
		bpp = 1;
	srcbuf := array[sw * sh * bpp] of byte;
	src.readpixels(src.r, srcbuf);

	dw := sw * scale;
	rowbuf := array[dw * bpp] of byte;
	for(sy := 0; sy < sh; sy++) {
		for(sx := 0; sx < sw; sx++) {
			for(k := 0; k < bpp; k++) {
				v := srcbuf[(sy * sw + sx) * bpp + k];
				for(dx := 0; dx < scale; dx++)
					rowbuf[((sx * scale + dx) * bpp) + k] = v;
			}
		}
		for(dy := 0; dy < scale; dy++) {
			ry := dst.r.min.y + sy * scale + dy;
			lr := Rect((dst.r.min.x, ry), (dst.r.min.x + dw, ry + 1));
			dst.writepixels(lr, rowbuf);
		}
	}
}

themelistener(ch: chan of int)
{
	fd := sys->open("/n/ui/event", Sys->OREAD);
	if(fd == nil)
		return;
	buf := array[256] of byte;
	for(;;) {
		n := sys->read(fd, buf, len buf);
		if(n <= 0)
			break;
		ev := string buf[0:n];
		if(len ev >= 6 && ev[0:6] == "theme ")
			alt { ch <-= 1 => ; * => ; }
	}
}

rf(name: string): string
{
	fd := sys->open(name, Sys->OREAD);
	if(fd == nil)
		return nil;
	buf := array[128] of byte;
	n := sys->read(fd, buf, len buf);
	if(n < 0)
		return nil;
	while(n > 0 && (buf[n-1] == byte '\n' || buf[n-1] == byte ' ' || buf[n-1] == byte '\t'))
		n--;
	if(n == 0)
		return nil;
	return string buf[0:n];
}
