implement Clock;

#
# Subject to the Lucent Public License 1.02
#

include "sys.m";
	sys: Sys;

include "draw.m";
	draw: Draw;
	Display, Image, Point, Rect: import draw;

include "math.m";
	math: Math;

include "tk.m";
include "wmclient.m";
	wmclient: Wmclient;
	Window: import wmclient;

include "daytime.m";
	daytime: Daytime;
	Tm: import daytime;

Clock: module
{
	init:	fn(nil: ref Draw->Context, nil: list of string);
};

hrhand: ref Image;
minhand: ref Image;
dots: ref Image;
back: ref Image;

init(ctxt: ref Draw->Context, nil: list of string)
{
	sys = load Sys Sys->PATH;
	draw = load Draw Draw->PATH;
	math = load Math Math->PATH;
	daytime = load Daytime Daytime->PATH;
	wmclient = load Wmclient Wmclient->PATH;

	sys->pctl(Sys->NEWPGRP, nil);
	wmclient->init();

	w := wmclient->window(ctxt, "clock", Wmclient->Appl);	# Plain?
	display := w.display;
	back = display.colormix(Draw->Palebluegreen, Draw->White);

	hrhand = display.newimage(Rect((0,0),(1,1)), Draw->CMAP8, 1, Draw->Darkblue);
	minhand = display.newimage(Rect((0,0),(1,1)), Draw->CMAP8, 1, Draw->Paleblue);
	dots = display.newimage(Rect((0,0),(1,1)), Draw->CMAP8, 1, Draw->Blue);

	w.reshape(Rect((0, 0), (100, 100)));
	w.startinput("ptr" :: nil);

	now := daytime->now();
	w.onscreen(nil);
	drawclock(w.image, now);

	ticks := chan of int;
	spawn timer(ticks, 30*1000);
	for(;;) alt{
	ctl := <-w.ctl or
	ctl = <-w.ctxt.ctl =>
		w.wmctl(ctl);
		if(ctl != nil && ctl[0] == '!')
			drawclock(w.image, now);
	p := <-w.ctxt.ptr =>
		w.pointer(*p);
	<-ticks =>
		t := daytime->now();
		if(t != now){
			now = t;
			drawclock(w.image, now);
		}
	}
}

ZP := Point(0, 0);

drawclock(screen: ref Image, t: int)
{
	if(screen == nil)
		return;
	tms := daytime->local(t);
	anghr := 90-(tms.hour*5 + tms.min/10)*6;
	angmin := 90-tms.min*6;
	r := screen.r;
	c := r.min.add(r.max).div(2);
	if(r.dx() < r.dy())
		rad := r.dx();
	else
		rad = r.dy();
	rad /= 2;
	rad -= 8;

	screen.draw(screen.r, back, nil, ZP);
	for(i:=0; i<12; i++)
		screen.fillellipse(circlept(c, rad, i*(360/12)), 2, 2, dots, ZP);

	screen.line(c, circlept(c, (rad*3)/4, angmin), 0, 0, 1, minhand, ZP);
	screen.line(c, circlept(c, rad/2, anghr), 0, 0, 1, hrhand, ZP);

	screen.flush(Draw->Flushnow);
}

circlept(c: Point, r: int, degrees: int): Point
{
	rad := real degrees * Math->Pi/180.0;
	c.x += int (math->cos(rad)*real r);
	c.y -= int (math->sin(rad)*real r);
	return c;
}

timer(c: chan of int, ms: int)
{
	for(;;){
		sys->sleep(ms);
		c <-= 1;
	}
}
