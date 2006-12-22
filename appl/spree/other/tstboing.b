implement Tst;

include "sys.m";
	sys: Sys;
include "draw.m";
	draw: Draw;
	Point, Rect: import draw;
include "sh.m";
	sh: Sh;
	Context: import Sh;
include "math.m";
	math: Math;
ZERO: con 1e-6;

stderr: ref Sys->FD;

Tst: module {
	init: fn(nil: ref Draw->Context, argv: list of string);
};
π: con Math->Pi;
Maxδ: con π / 4.0;

init(nil: ref Draw->Context, argv: list of string)
{
	sys = load Sys Sys->PATH;
	stderr = sys->fildes(2);
	math = load Math Math->PATH;
	if (len argv != 9) {
		sys->fprint(stderr, "args?\n");
		exit;
	}
	ar := argv2r(tl argv);
	br := argv2r(tl tl tl tl tl argv);

	a := Line.new(ar.min, ar.max);			# ball
	b := Line.new(br.min, br.max);			# bat
	(hit, hitp, s, t) := b.intersection(a.p, a.v);
	if (hit) {
		nv := boing(a.v, b);
		rl := ref Line(hitp, nv, 50.0);
		ballθ := a.θ();
		batθ := b.θ();
		φ := ballθ - batθ;
		δ: real;
		if (math->sin(φ) > 0.0)
			δ = (t / b.s) * Maxδ * 2.0 - Maxδ;
		else
			δ = (t / b.s) * -Maxδ * 2.0 + Maxδ;
		nl := Line.newpolar(rl.p, rl.θ() + δ, rl.s);
		sys->print("%s %s %s\n", p2s(rl.point(0.0)), p2s(rl.point(rl.s)), p2s(nl.point(nl.s)));
	} else
		sys->fprint(stderr, "no hit\n");
}

argv2r(v: list of string): Rect
{
	r: Rect;
	(r.min.x, v) = (int hd v, tl v);
	(r.min.y, v) = (int hd v, tl v);
	(r.max.x, v) = (int hd v, tl v);
	(r.max.y, v) = (int hd v, tl v);
	return r;
}
Line: adt {
	p, v:		Realpoint;
	s:		real;
	new:			fn(p1, p2: Point): ref Line;
	hittest:		fn(l: self ref Line, p: Point): (Realpoint, real, real);
	intersection:	fn(b: self ref Line, p, v: Realpoint): (int, Realpoint, real, real);
	point:		fn(b: self ref Line, s: real): Point;
	θ:			fn(b: self ref Line): real;
	newpolar:		fn(p: Realpoint, θ: real, s: real): ref Line;
};

Realpoint: adt {
	x, y: real;
};

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

Line.newpolar(p: Realpoint, θ: real, s: real): ref Line
{
	l := ref Line;
	l.p = p;
	l.s = s;
	l.v = (math->cos(θ), math->sin(θ));
	return l;
}

Line.θ(l: self ref Line): real
{
	return math->atan2(l.v.y, l.v.x);
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

# bounce ball travelling in direction av off line b.
# return the new unit vector.
boing(av: Realpoint, b: ref Line): Realpoint
{
	d := math->atan2(real b.v.y, real b.v.x) * 2.0 - math->atan2(av.y, av.x);
	return (math->cos(d), math->sin(d));
}

p2s(p: Point): string
{
	return string p.x + " " + string p.y;
}

