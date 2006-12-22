implement Tstwin;

include "sys.m";
	sys: Sys;

include "draw.m";
	draw: Draw;
	Context, Display, Point, Rect, Image, Screen: import draw;

include "tk.m";
	tk: Tk;
	Toplevel: import tk;

include	"tkclient.m";
	tkclient: Tkclient;

include "math.m";
	math: Math;

Tstwin: module
{
	init:	fn(ctxt: ref Context, argv: list of string);
};

screen: ref Screen;
display: ref Display;
win: ref Toplevel;

NC: con 6;

task_cfg := array[] of {
"label .xy -text {0 0}",
"canvas .c -height 500 -width 500",
"pack .xy -side top -fill x",
"pack .c -side bottom -fill both -expand 1",
"bind .c <ButtonRelease-1> {send cmd 0 1 %x %y}",
"bind .c <ButtonRelease-2> {send cmd 0 2 %x %y}",
"bind .c <Button-1> {send cmd 1 1 %x %y}",
"bind .c <Button-2> {send cmd 1 2 %x %y}",
};

Obstacle: adt {
	line: 		ref Line;
	s1, s2: 	real;
	id:		int;
	config: 	fn(b: self ref Obstacle);
	new:		fn(id: int): ref Obstacle;
};

Line: adt {
	p, v:		Realpoint;
	s:		real;
	new:			fn(p1, p2: Point): ref Line;
	hittest:		fn(l: self ref Line, p: Point): (Realpoint, real, real);
	intersection:	fn(b: self ref Line, p, v: Realpoint): (int, Realpoint, real, real);
	point:		fn(b: self ref Line, s: real): Point;
};
bats: list of ref Obstacle;
init(ctxt: ref Context, argv: list of string)
{
	sys = load Sys Sys->PATH;
	draw = load Draw Draw->PATH;
	tk = load Tk Tk->PATH;
	tkclient = load Tkclient Tkclient->PATH;
	math = load Math Math->PATH;

	sys->pctl(Sys->NEWPGRP, nil);

	display = ctxt.display;
	screen = ctxt.screen;

	tkclient->init();

	menubut: chan of string;
	(win, menubut) = tkclient->toplevel(screen, nil, "Window testing", 0);

	cmd := chan of string;
	tk->namechan(win, cmd, "cmd");

	tkclient->tkcmds(win, task_cfg);

	mch := chan of (int, Point);
	spawn mouseproc(mch);

	bat := Obstacle.new(0);
	bats = bat :: nil;
	bat.line = Line.new((100, 0), (150, 500));
	bat.s1 = 10.0;
	bat.s2 = 110.0;
	bat.config();

	tk->cmd(win, "update");
	buts := 0;
	for(;;) alt {
	menu := <-menubut =>
		tkclient->wmctl(win, menu);

	c := <-cmd =>
		(nil, toks) := sys->tokenize(c, " ");
		if ((hd toks)[0] == '1')
			buts |= int hd tl toks;
		else
			buts &= ~int hd tl toks;
		mch <-= (buts, Point(int hd tl tl toks, int hd tl tl tl toks));
	}
}

Realpoint: adt {
	x, y: real;
};

cmd(top: ref Tk->Toplevel, s: string): string
{
	e := tk->cmd(top, s);
	if (e != nil && e[0] == '!')
		sys->print("tk error %s on '%s'\n", e, s);
	return e;
}

p2s(p: Point): string
{
	return string p.x + " " + string p.y;
}

mouseproc(mch: chan of (int, Point))
{
	for (;;) {
		hitbat: ref Obstacle = nil;
		minperp, hitdist: real;
		(buts, p) := <-mch;
		for (bl := bats; bl != nil; bl = tl bl) {
			b := hd bl;
			(normal, perp, dist) := b.line.hittest(p);
			perp = abs(perp);
			
			if ((hitbat == nil || perp < minperp) && (dist >= b.s1 && dist <= b.s2))
				(hitbat, minperp, hitdist) = (b, perp, dist);
		}
		if (hitbat == nil || minperp > 30.0) {
			while ((<-mch).t0)
				;
			continue;
		}
		offset := hitdist - hitbat.s1;
		if (buts & 2)
			(buts, p) = aim(mch, hitbat, p);
		if (buts & 1)
			drag(mch, hitbat, offset);
	}
}


drag(mch: chan of (int, Point), hitbat: ref Obstacle, offset: real)
{
	line := hitbat.line;
	batlen := hitbat.s2 - hitbat.s1;

	cvsorigin := Point(int cmd(win, ".c cget -actx"), int cmd(win, ".c cget -acty"));

#	cmd(win, "grab set .c");
#	cmd(win, "focus .");
loop:	for (;;) alt {
	(buts, p) := <-mch =>
		if (buts & 2)
			(buts, p) = aim(mch, hitbat, p);
		(v, perp, dist) := line.hittest(p);
		dist -= offset;
		# constrain bat and mouse positions
		if (dist < 0.0 || dist + batlen > line.s) {
			if (dist < 0.0) {
				p = line.point(offset);
				dist = 1.0;
			} else {
				p = line.point(line.s - batlen + offset);
				dist = line.s - batlen;
			}
			p.x -= int (v.x * perp);
			p.y -= int (v.y * perp);
			win.image.display.cursorset(p.add(cvsorigin));
		}
		(hitbat.s1, hitbat.s2) = (dist, dist + batlen);
		hitbat.config();
		cmd(win, "update");
		if (!buts)
			break loop;
	}
#	cmd(win, "grab release .c");
}

CHARGETIME: con 1000.0;
MAXCHARGE: con 50.0;

α: con 0.999;		# decay in one millisecond
Max: con 60.0;
D: con 5;
ZERO: con 1e-6;
aim(mch: chan of (int, Point), hitbat: ref Obstacle, p: Point): (int, Point)
{
	cvsorigin := Point(int cmd(win, ".c cget -actx"), int cmd(win, ".c cget -acty"));
	startms := ms := sys->millisec();
	delta := Realpoint(0.0, 0.0);
	line := hitbat.line;
	charge := 0.0;
	pivot := line.point((hitbat.s1 + hitbat.s2) / 2.0);
	s1 := p2s(line.point(hitbat.s1));
	s2 := p2s(line.point(hitbat.s2));
	cmd(win, ".c create line 0 0 0 0 -tags wire");
	cmd(win, ".c create oval 0 0 1 1 -fill green -tags ball");
	p2: Point;
	buts := 2;
	for (;;) {
		v := makeunit(delta);
		bp := pivot.add((int (v.x * charge), int (v.y * charge)));
		cmd(win, ".c coords wire "+s1+" "+p2s(bp)+" "+s2);
		cmd(win, ".c coords ball "+string (bp.x - D) + " " + string (bp.y - D) + " " +
					string (bp.x + D) + " " + string (bp.y + D));
		cmd(win, "update");
		if ((buts & 2) == 0)
			break;
		(buts, p2) = <-mch;
		now := sys->millisec();
		fade := math->pow(α, real (now - ms));
		charge = real (now - startms) * (MAXCHARGE / CHARGETIME);
		if (charge > MAXCHARGE)
			charge = MAXCHARGE;
		ms = now;
		delta.x = delta.x * fade + real (p2.x - p.x);
		delta.y = delta.y * fade + real (p2.y - p.y);
		mag := delta.x * delta.x + delta.y * delta.y;
		win.image.display.cursorset(p.add(cvsorigin));
	}
	sys->print("pow\n");
	cmd(win, ".c delete wire ball");
	cmd(win, "update");
	return (buts, p2);
}

makeunit(v: Realpoint): Realpoint
{
	mag := math->sqrt(v.x * v.x + v.y * v.y);
	if (mag < ZERO)
		return (1.0, 0.0);
	return (v.x / mag, v.y / mag);
}

#drag(mch: chan of (int, Point), p: Point)
#{
#	down := 1;
#	cvsorigin := Point(int cmd(win, ".c cget -actx"), int cmd(win, ".c cget -acty"));
#	ms := sys->millisec();
#	delta := Realpoint(0.0, 0.0);
#	id := cmd(win, ".c create line " + p2s(p) + " " + p2s(p));
#	coords := ".c coords " + id + " " + p2s(p) + " ";
#	do {
#		p2: Point;
#		(down, p2) = <-mch;
#		now := sys->millisec();
#		fade := math->pow(α, real (now - ms));
#		ms = now;
#		delta.x = delta.x * fade + real (p2.x - p.x);
#		delta.y = delta.y * fade + real (p2.y - p.y);
#		mag := delta.x * delta.x + delta.y * delta.y;
#		d: Realpoint;
#		if (mag > Max * Max) {
#			fade = Max / math->sqrt(mag);
#			d  = (delta.x * fade, delta.y * fade);
#		} else
#			d = delta;
#		
#		cmd(win, coords + p2s(p.add((int d.x, int d.y))));
#		win.image.display.cursorset(p.add(cvsorigin));
#		cmd(win, "update");
#	} while (down);
#}
#
Line.new(p1, p2: Point): ref Line
{
	ln := ref Line;
	ln.p = (real p1.x, real p1.y);
	v := Realpoint(real (p2.x - p1.x), real (p2.y - p1.y));
	ln.s =  math->sqrt(v.x * v.x + v.y * v.y);
	if (ln.s > ZERO)
		ln.v = (v.x / ln.s, v.y / ln.s);
	else
		ln.v = (1.0, 0.0);
	return ln;
}

# return normal from line, perpendicular distance from line and distance down line
Line.hittest(l: self ref Line, ip: Point): (Realpoint, real, real)
{
	p := Realpoint(real ip.x, real ip.y);
	v := Realpoint(-l.v.y, l.v.x);
	(nil, nil, perp, ldist) := l.intersection(p, v);
	return (v, perp, ldist);
}

Line.point(l: self ref Line, s: real): Point
{
	return (int (l.p.x + s * l.v.x), int (l.p.y + s * l.v.y));
}

# compute the intersection of lines a and b.
# b is assumed to be fixed, and a is indefinitely long
# but doesn't extend backwards from its starting point.
# a is defined by the starting point p and the unit vector v.
# return whether it hit, the point at which it hit if so,
# the distance of the intersection point from p,
# and the distance of the intersection point from b.p.
Line.intersection(b: self ref Line, p, v: Realpoint): (int, Realpoint, real, real)
{
	det := b.v.x * v.y - v.x * b.v.y;
	if (det > -ZERO && det < ZERO)
		return (0, (0.0, 0.0), 0.0, 0.0);

	y21 := b.p.y - p.y;
	x21 := b.p.x - p.x;
	s := (b.v.x * y21 - b.v.y * x21) / det;
	t := (v.x * y21 - v.y * x21) / det;
	if (s < 0.0)
		return (0, (0.0, 0.0), s, t);
	hit := t >= 0.0 && t <= b.s;
	hp: Realpoint;
	if (hit)
		hp = (p.x+v.x*s, p.y+v.y*s);
	return (hit, hp, s, t);
}

blankobstacle: Obstacle;
Obstacle.new(id: int): ref Obstacle
{
	cmd(win, ".c create line 0 0 0 0 -width 3 -fill #aaaaaa" + " -tags l" + string id);
	o := ref blankobstacle;
	o.line = Line.new((0, 0), (0, 0));
	o.id = id;
	return o;
}

Obstacle.config(o: self ref Obstacle)
{
	cmd(win, ".c coords l" + string o.id + " " +
		p2s(o.line.point(o.s1)) + " " + p2s(o.line.point(o.s2)));
	cmd(win, ".c itemconfigure l" + string o.id + " -fill red");
}

abs(x: real): real
{
	if (x < 0.0)
		return -x;
	return x;
}
