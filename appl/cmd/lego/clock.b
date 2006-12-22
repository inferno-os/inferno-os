implement Clock;

include "sys.m";
	sys: Sys;

include "draw.m";
	draw: Draw;
	Point, Rect: import draw;

include "math.m";
	math: Math;
	sqrt, atan2, hypot, Degree: import math;

include "tk.m";
	tk: Tk;
	top: ref Tk->Toplevel;

include "tkclient.m";
	tkclient: Tkclient;

Clock: module {
	init:	fn(ctxt: ref Draw->Context, argl: list of string);
};

cmds := array[] of {
	"bind . <Configure> {send win resize}",
	"canvas .face -height 200 -width 200 -bg yellow",
	"bind .face <ButtonPress> {send ptr %x %y}",
	"bind .face <ButtonRelease> {send ptr release}",
	"pack .face -expand yes -fill both",
	"button .reset -text Reset -command {send win reset}",
	"pack .reset -after .Wm_t.title -side right -fill y",
	"pack propagate . no",
};

init(ctxt: ref Draw->Context, nil: list of string)
{
	sys = load Sys Sys->PATH;
	draw = load Draw Draw->PATH;
	math = load Math Math->PATH;
	tk = load Tk Tk->PATH;
	tkclient = load Tkclient Tkclient->PATH;
	tkclient->init();

	sys->pctl(Sys->NEWPGRP, nil);

	clockface := sys->open("/chan/clockface", Sys->ORDWR);
	if (clockface == nil) {
		sys->print("open /chan/clockface failed: %r\n");
		raise "fail:clockface";
	}
	tock := chan of string;
	spawn readme(clockface, tock);

	titlech: chan of string;
	(top, titlech) = tkclient->toplevel(ctxt, "hh:mm", "", Tkclient->Appl);
	win := chan of string;
	ptr := chan of string;
	tk->namechan(top, win, "win");
	tk->namechan(top, ptr, "ptr");
	for(i:=0; i<len cmds; i++)
		tk->cmd(top, cmds[i]);
	tkclient->onscreen(top, nil);
	tkclient->startinput(top, "ptr"::nil);
	drawface();
	spawn hands(ptr, clockface);

	for (;;) alt {
	s := <-top.ctxt.kbd =>
		tk->keyboard(top, s);
	s := <-top.ctxt.ptr =>
		tk->pointer(top, *s);
	s := <-top.ctxt.ctl or
	s = <-top.wreq or
	s = <-titlech =>
		tkclient->wmctl(top, s);
	msg := <-win =>
		case msg {
		"resize" =>	drawface();
		"reset" =>		sys->fprint(clockface, "reset");
		}
	nowis := <-tock =>
		(n, toks) := sys->tokenize(nowis, ":");
		if (n == 2) {
			(hour, minute) = (int hd toks, int hd tl toks);
			setclock();
		}
	}
}

readme(fd: ref Sys->FD, ch: chan of string)
{
	buf := array[64] of byte;
	while ((n := sys->read(fd, buf, len buf)) > 0) {
		if (buf[n-1] == byte '\n')
			n--;
		ch <-= string buf[:n];
	}
	ch <-= "99:99";
}

hour, minute: int;
center, focus: Point;
major: int;

Frim:	con .98;
Fminute:	con .90;
Fhour:	con .45;
Fnub:	con .05;

hands(ptr: chan of string, fd: ref Sys->FD)
{
	for (;;) {
		pos := <-ptr;
		p := s2p(pos);
		hand := "";
		if (elinside(p, Fnub))
			hand = nil;
		else if (elinside(p, Fhour))
			hand = "hour";
		else if (elinside(p, Fminute))
			hand = "minute";

		do {
			p = s2p(pos).sub(center);
			angle := int (atan2(real -p.y, real p.x) / Degree);
			if (hand != nil)
				tkc(".face itemconfigure "+hand+" -start "+string angle+"; update");
			case hand {
			"hour" =>		hour = ((360+90-angle) / 30) % 12;
			"minute" =>	minute = ((360+90-angle) / 6) % 60;
			}
		} while ((pos = <-ptr) != "release");
		if (hand != nil)
			sys->fprint(fd, "%d:%d\n", hour, minute);
	}
}

drawface()
{
	elparms();
	tkc(sys->sprint(".face configure -scrollregion {0 0 %d %d}", 2*center.x, 2*center.y));
	tkc(".face delete all");
	tkc(".face create oval "+elrect(Frim)+" -fill fuchsia -outline aqua -width 2");
	for (a := 0; a < 360; a += 30)
		tkc(".face create arc "+elrect(Frim)+" -fill aqua -outline aqua -width 2 -extent 1 -start "+string a);
	tkc(".face create oval "+elrect(Fminute)+" -fill fuchsia -outline fuchsia");
	tkc(".face create oval "+elrect(Fnub)+" -fill aqua -outline aqua");
	tkc(".face create arc "+elrect(Fhour)+" -fill aqua -outline aqua -width 6 -extent 1 -tags hour");
	tkc(".face create arc "+elrect(Fminute)+" -fill aqua -outline aqua -width 2 -extent 1 -tags minute");
	setclock();
}

setclock()
{
	tkc(".face itemconfigure hour -start "+string (90 - 30*(hour%12) - minute/2));
	tkc(".face itemconfigure minute -start "+string (90 - 6*minute));
	tkc(sys->sprint(".Wm_t.title configure -text {%d:%.2d}", (hour+11)%12+1, minute));
	tkc("update");
}

elparms()
{
	center = (int tkc(".face cget actwidth") / 2, int tkc(".face cget actheight") / 2);
	dist := center.x*center.x - center.y*center.y;
	if (dist > 0) {
		major = 2 * center.x;
		focus = (int sqrt(real dist), 0);
	} else {
		major = 2 * center.y;
		focus = (0, int sqrt(real -dist));
	}
}

elinside(p: Point, frac: real): int
{
	foc := mulf(focus, frac);
	d := dist(p, center.add(foc)) + dist(p, center.sub(foc));
	return (d < frac * real major);
}

elrect(frac: real): string
{
	inset := mulf(center, 1.-frac);
	r := Rect(inset, center.mul(2).sub(inset));
	return sys->sprint("%d %d %d %d", r.min.x, r.min.y, r.max.x, r.max.y);
}

mulf(p: Point, f: real): Point
{
	return (int (f * real p.x), int (f * real p.y));
}

dist(p, q: Point): real
{
	p = p.sub(q);
	return hypot(real p.x, real p.y);
}

s2p(s: string): Point
{
	(nil, xy) := sys->tokenize(s, " ");
	if (len xy != 2)
		return (0, 0);
	return (int hd xy, int hd tl xy);
}

tkc(msg: string): string
{
	ret := tk->cmd(top, msg);
	if (ret != nil && ret[0] == '!')
		sys->print("tk error? %s → %s\n", msg, ret);
	return ret;
}
