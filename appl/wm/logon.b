implement WmLogon;

#
# Infernode login splash screen
#
# Displays the Infernode brand image, prompts for a username (or uses
# the default from /dev/user), writes it to /dev/user, then launches
# the toolbar to continue startup.  Mirrors the role of the upstream
# Inferno wm/logon but uses native Draw instead of Tk.
#

include "sys.m";
	sys: Sys;

include "draw.m";
	draw: Draw;
	Display, Font, Image, Point, Rect: import draw;

include "wmclient.m";
	wmclient: Wmclient;
	Window: import wmclient;

WmLogon: module
{
	init: fn(ctxt: ref Draw->Context, argv: list of string);
};

IMGPATH:  con "/lib/lucifer/about-screen.png";
IMGW:     con 600;
IMGH:     con 414;
PADDING:  con 16;

init(ctxt: ref Draw->Context, nil: list of string)
{
	sys = load Sys Sys->PATH;
	if(ctxt == nil) {
		sys->fprint(sys->fildes(2), "logon: no window context\n");
		raise "fail:bad context";
	}

	draw = load Draw Draw->PATH;
	wmclient = load Wmclient Wmclient->PATH;

	sys->pctl(Sys->NEWPGRP, nil);
	wmclient->init();

	winh := IMGH + PADDING*2 + 20;  # image + gap + label
	w := wmclient->window(ctxt, "Infernode", Wmclient->Plain);
	display := w.display;

	w.reshape(Rect((0, 0), (IMGW, winh)));
	w.startinput("ptr" :: "kbd" :: nil);
	w.onscreen(nil);

	screen := w.image;

	# Black background
	black := display.rgb(0, 0, 0);
	screen.draw(screen.r, black, nil, Point(0, 0));

	# Load and draw splash image
	img := display.open(IMGPATH);
	if(img != nil) {
		screen.draw(Rect((0,0),(IMGW,IMGH)), img, nil, img.r.min);
	}

	# Load font for prompt
	font := Font.open(display, "/fonts/combined/unicode.sans.18.font");
	if(font == nil)
		font = Font.open(display, "/fonts/combined/unicode.sans.14.font");
	if(font == nil)
		font = Font.open(display, "*default*");

	orange := display.rgb(16rff, 16r55, 16r00);

	# Read current user as default
	defuser := rf("/dev/user");
	if(defuser == nil)
		defuser = "inferno";

	# Draw "User:" label
	labely := IMGH + PADDING;
	label := "User: " + defuser + "   (press Enter to continue)";
	screen.text(Point(PADDING, labely), orange, Point(0, 0), font, label);

	screen.flush(Draw->Flushnow);

	# Wait for Enter key or pointer click to proceed
	for(;;) alt {
	ctl := <-w.ctl or
	ctl = <-w.ctxt.ctl =>
		w.wmctl(ctl);

	k := <-w.ctxt.kbd =>
		if(k == 16r0a || k == 16r0d) {	# newline or carriage return
			setuser(defuser);
			return;
		}

	p := <-w.ctxt.ptr =>
		w.pointer(*p);
		if(p.buttons != 0) {
			setuser(defuser);
			return;
		}
	}
}

setuser(user: string)
{
	fd := sys->open("/dev/user", Sys->OWRITE);
	if(fd != nil)
		sys->fprint(fd, "%s", user);
}

rf(name: string): string
{
	fd := sys->open(name, Sys->OREAD);
	if(fd == nil)
		return nil;
	buf := array[64] of byte;
	n := sys->read(fd, buf, len buf);
	if(n <= 0)
		return nil;
	while(n > 0 && (buf[n-1] == byte '\n' || buf[n-1] == byte ' '))
		n--;
	if(n == 0)
		return nil;
	return string buf[0:n];
}
