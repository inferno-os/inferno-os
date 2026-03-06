implement About;

#
# About Infernode — native Draw version
#
# Displays the Infernode logo, system version, and project info
# using native Draw primitives (no Tk dependency).
#

include "sys.m";
	sys: Sys;

include "draw.m";
	draw: Draw;
	Display, Font, Image, Point, Rect: import draw;

include "wmclient.m";
	wmclient: Wmclient;
	Window: import wmclient;

include "lucitheme.m";
	lucitheme: Lucitheme;
	Theme: import lucitheme;

About: module
{
	init: fn(ctxt: ref Draw->Context, argv: list of string);
};

ZP := Point(0, 0);

WINW: con 280;
WINH: con 320;
PADDING: con 16;

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

	sys->pctl(Sys->NEWPGRP, nil);
	wmclient->init();

	w := wmclient->window(ctxt, "About Infernode", Wmclient->Appl);
	display := w.display;

	w.reshape(Rect((0, 0), (WINW, WINH)));
	w.startinput("ptr" :: "kbd" :: nil);
	w.onscreen(nil);

	redraw(w, display);

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
	textcol := display.color(theme.text | 16rFF);
	dimcol := display.color(theme.dim | 16rFF);

	# Clear background
	screen.draw(screen.r, bg, nil, ZP);

	# Draw border
	screen.border(screen.r, 1, accent, ZP);

	# Load fonts
	titlefont := Font.open(display, "/fonts/combined/unicode.16.font");
	if(titlefont == nil)
		titlefont = Font.open(display, "*default*");
	bodyfont := Font.open(display, "/fonts/combined/unicode.12.font");
	if(bodyfont == nil)
		bodyfont = Font.open(display, "*default*");

	r := screen.r;
	cx := (r.min.x + r.max.x) / 2;
	y := r.min.y + PADDING;

	# Load and draw logo
	logo := display.open("/lib/lucifer/logo.png");
	if(logo != nil) {
		# Scale: draw logo centered
		lw := logo.r.dx();
		lh := logo.r.dy();
		# Draw at 2x if small
		if(lw < 48) {
			scale := 4;
			sw := lw * scale;
			sh := lh * scale;
			dst := Rect((cx - sw/2, y), (cx + sw/2, y + sh));
			scaled := display.newimage(dst, screen.chans, 0, Draw->Nofill);
			if(scaled != nil) {
				# Nearest-neighbor scale by drawing each pixel as a block
				scaleblit(scaled, logo, scale);
				screen.draw(dst, scaled, nil, dst.min);
			}
			y += sh + PADDING;
		} else {
			lx := cx - lw/2;
			dst := Rect((lx, y), (lx + lw, y + lh));
			screen.draw(dst, logo, nil, logo.r.min);
			y += lh + PADDING;
		}
	} else
		y += PADDING;

	# Title
	title := "Infernode";
	tw := titlefont.width(title);
	screen.text(Point(cx - tw/2, y), accent, ZP, titlefont, title);
	y += titlefont.height + 4;

	# Version from sysctl
	version := rf("/dev/sysctl");
	if(version != nil) {
		vw := bodyfont.width(version);
		screen.text(Point(cx - vw/2, y), textcol, ZP, bodyfont, version);
		y += bodyfont.height + 4;
	}

	# Separator line
	y += 8;
	screen.line(Point(r.min.x + PADDING*2, y), Point(r.max.x - PADDING*2, y),
		0, 0, 0, dimcol, ZP);
	y += 12;

	# Description lines
	lines := array[] of {
		"Inferno\u00AE Operating System",
		"",
		"Originally by Bell Labs (Lucent)",
		"Vita Nuova Holdings",
		"",
		"Infernode fork by",
		"NERVsystems",
		"",
		"lucent.com/inferno",
		"nervsystems.com",
	};

	for(i := 0; i < len lines; i++) {
		if(lines[i] == nil || len lines[i] == 0) {
			y += bodyfont.height / 2;
			continue;
		}
		lw := bodyfont.width(lines[i]);
		col := textcol;
		# Dim the URLs
		if(i >= 8)
			col = dimcol;
		screen.text(Point(cx - lw/2, y), col, ZP, bodyfont, lines[i]);
		y += bodyfont.height + 2;
	}

	screen.flush(Draw->Flushnow);
}

# Nearest-neighbor scale: blit src into dst at integer scale factor
scaleblit(dst, src: ref Image, scale: int)
{
	sw := src.r.dx();
	sh := src.r.dy();
	# Read source pixels
	bpp := src.depth / 8;
	if(bpp < 1)
		bpp = 1;
	srcbuf := array[sw * sh * bpp] of byte;
	src.readpixels(src.r, srcbuf);

	# Write scaled rows
	dw := sw * scale;
	rowbuf := array[dw * bpp] of byte;
	for(sy := 0; sy < sh; sy++) {
		# Expand one source row
		for(sx := 0; sx < sw; sx++) {
			for(k := 0; k < bpp; k++) {
				v := srcbuf[(sy * sw + sx) * bpp + k];
				for(dx := 0; dx < scale; dx++)
					rowbuf[((sx * scale + dx) * bpp) + k] = v;
			}
		}
		# Write this row 'scale' times
		for(dy := 0; dy < scale; dy++) {
			ry := dst.r.min.y + sy * scale + dy;
			r := Rect((dst.r.min.x, ry), (dst.r.min.x + dw, ry + 1));
			dst.writepixels(r, rowbuf);
		}
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
	# Trim trailing whitespace
	while(n > 0 && (buf[n-1] == byte '\n' || buf[n-1] == byte ' ' || buf[n-1] == byte '\t'))
		n--;
	if(n == 0)
		return nil;
	return string buf[0:n];
}
