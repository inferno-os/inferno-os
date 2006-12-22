implement Bounce;

# bouncing balls demo.  it uses tk and multiple processes to animate a
# number of balls bouncing around the screen.  each ball has its own
# process; CPU time is doled out fairly to each process by using
# a central monitor loop.

include "sys.m";
	sys: Sys;
include "draw.m";
	draw: Draw;
	Point, Rect: import draw;
include "tk.m";
	tk: Tk;
include "tkclient.m";
	tkclient: Tkclient;
include "math.m";
	math: Math;
include "rand.m";

Bounce: module {
	init: fn(ctxt: ref Draw->Context, argv: list of string);
};

BALLSIZE: con 4;
ZERO: con 1e-6;
π: con Math->Pi;

Line: adt {
	p1, p2: Point;
};

Realpoint: adt {
	x, y: real;
};

gamecmds := array[] of {
"canvas .c",
"bind .c <ButtonRelease-1> {send cmd 0 %x %y}",
"bind .c <ButtonRelease-2> {send cmd 0 %x %y}",
"bind .c <Button-1> {send cmd 1 %x %y}",
"bind .c <Button-2> {send cmd 2 %x %y}",
"frame .f",
"button .f.left -bitmap small_color_left.bit -bd 0 -command {send cmd k -1}",
"button .f.right -bitmap small_color_right.bit -bd 0 -command {send cmd k 1}",
"label .f.l -text {8 balls}",
"pack .f.left .f.right -side left",
"pack .f.l -side left",
"pack .f -fill x",
"pack .c -fill both -expand 1",
};

randch: chan of int;
lines: list of (int, Line);
lineid := 0;
lineversion := 0;

addline(win: ref Tk->Toplevel, v: Line)
{
	lines = (++lineid, v) :: lines;
	cmd(win, ".c create line " + pt2s(v.p1) + " " + pt2s(v.p2) + " -width 3 -fill black" +
			" -tags l" + string lineid);
	lineversion++;
}

nomod(s: string)
{
	sys->fprint(sys->fildes(2), "bounce: cannot load %s: %r\n", s);
	raise "fail:bad module";
}

init(ctxt: ref Draw->Context, argv: list of string)
{
	sys = load Sys Sys->PATH;
	draw = load Draw Draw->PATH;
	math = load Math Math->PATH;
	tk = load Tk Tk->PATH;
	tkclient = load Tkclient Tkclient->PATH;
	if (tkclient == nil)
		nomod(Tkclient->PATH);
	tkclient->init();
	nballs := 8;
	if (argv != nil && tl argv != nil)
		nballs = int hd tl argv;
	if (nballs < 0) {
		sys->fprint(sys->fildes(2), "usage: bounce [nballs]\n");
		raise "fail:usage";
	}
	sys->pctl(Sys->NEWPGRP, nil);
	if(ctxt == nil)
		ctxt = tkclient->makedrawcontext();
	(win, wmctl) := tkclient->toplevel(ctxt, nil, "Bounce", 0);
	cmdch := chan of string;
	tk->namechan(win, cmdch, "cmd");
	for (i := 0; i < len gamecmds; i++)
		cmd(win, gamecmds[i]);
	cmd(win, ".c configure -width 400 -height 400");
	cmd(win, "pack propagate . 0");
	cmd(win, ".f.l configure -text '" + string nballs + " balls");
	tkclient->onscreen(win, nil);
	tkclient->startinput(win, "kbd"::"ptr"::nil);

	mch := chan of (int, Point);
	randch = chan of int;
	spawn randgenproc(randch);
	csz := Point(int cmd(win, ".c cget -actwidth"), int cmd(win, ".c cget -actheight"));

	# add edges of window
	addline(win, ((-1, -1), (csz.x, -1)));
	addline(win, ((csz.x, -1), csz));
	addline(win, (csz, (-1, csz.y)));
	addline(win, ((-1, csz.y), (-1, -1)));

	spawn makelinesproc(win, mch);
	mkball := chan of (int, Realpoint, Realpoint);
	spawn monitor(win, mkball);
	for (i = 0; i < nballs; i++)
		mkball <-= (1, randpoint(csz), makeunit(randpoint(csz)));
	for (;;) alt {
	s := <-win.ctxt.kbd =>
		tk->keyboard(win, s);
	s := <-win.ctxt.ptr =>
		tk->pointer(win, *s);
	s := <-win.ctxt.ctl or
	s = <-win.wreq or
	s = <-wmctl =>
		tkclient->wmctl(win, s);
	c := <-cmdch =>
		(nil, toks) := sys->tokenize(c, " ");
		if (hd toks != "k") {
			mch <-= (int hd toks, Point(int hd tl toks, int hd tl tl toks));
			continue;
		}
		n := nballs + int hd tl toks;
		if (n < 0)
			n = 0;
		dn := 1;
		if (n < nballs)
			dn = -1;
		for (; nballs != n; nballs += dn)
			mkball <-= (dn, randpoint(csz), makeunit(randpoint(csz)));
		cmd(win, ".f.l configure -text '" + string nballs + " balls");
		cmd(win, "update");
	}
}

randpoint(size: Point): Realpoint
{
	return (randreal(size.x), randreal(size.y));
}

# return randomish real number between 1 and x-1
randreal(x: int): real
{
	return real (<-randch % ((x - 1) * 100)) / 100.0 + 1.0;
}

# make sure cpu time is handed to all ball processes fairly
# by passing a "token" around to each process in turn.
# each process does its work when it *hasn't* got its
# token but it can't go through two iterations without
# waiting its turn.
#
# new processes can be created and destroyed by
# sending on mkball. processes are arranged in a stack-like
# order: new processes are added to the top of the stack, and
# processes are destroyed from the top of the stack downwards.
monitor(win: ref Tk->Toplevel, mkball: chan of (int, Realpoint, Realpoint))
{
	procl := proc := chan of int :: nil;
	spawn nullproc(hd proc);	# always there to avoid deadlock when no balls.
	hd proc <-= 1;			# hand token to dummy proc
	for (;;) {
		procc := hd proc;
		alt {
		(n, p, v) := <-mkball =>
			if (n > 0) {					# start new ball proc going.
				procl = chan of int :: procl;
				spawn animproc(hd procl, win, p, v);
			} else if (tl procl != nil) {		# stop a ball proc.
				<-hd proc;			# get token.
				hd procl <-= 0;			# stop proc.
				proc = procl = tl procl;	# remove proc.
				hd proc <-= 1;			# hand out token.
			}
		<-procc =>					# got token.
			if ((proc = tl proc) == nil)
				proc = procl;
			hd proc <-= 1;				# hand token to next process.
		}
	}
}

nullproc(c: chan of int)
{
	for (;;)
		c <-= <-c;
}

# animate one ball. initial position and unit-velocity are
# given by p and v.
animproc(c: chan of int, win: ref Tk->Toplevel, p, v: Realpoint)
{
	speed := 0.1 + real (<-randch % 40) / 100.0;
	ballid := cmd(win, sys->sprint(".c create oval 0 0 1 1 -fill #%.6x", <-randch & 16rffffff));
	hitlineid := -1;
	smallcount := 0;
	version := lineversion;
loop:	for (;;) {
		hitline: Line;
		hitp: Realpoint;

		dist := 1000000.0;
		oldid := hitlineid;
		for (l := lines; l != nil; l = tl l) {
			(id, line) := hd l;
			(ok, hp, hdist) := intersect(p, v, line);
			if (ok && hdist < dist && id != oldid && (smallcount < 10 || hdist > 1.5)) {
				(hitp, hitline, hitlineid, dist) = (hp, line, id, hdist);
			}
		}
		if (dist > 10000.0) {
			sys->print("no intersection!\n");
#			sys->print("p: [%f, %f], v: [%f, %f]\n", p.x, p.y, v.x, v.y);
#			for (l := lines; l != nil; l = tl l) {
#				(id, line) := hd l;
#				(ok, hp, hdist) := intersect(p, v, line);
#				sys->print("line: [%d %d]->[%d %d] -> %d, [%f, %f], %f\n", line.p1.x, line.p1.y, line.p2.x, line.p2.y,
#						ok, hp.x, hp.y, hdist);
#			}
			cmd(win, ".c delete " + ballid + ";update");
			while (c <-= <-c)
				;
			exit;
		}
		if (dist < 0.0001)
			smallcount++;
		else
			smallcount = 0;
		bouncev := boing(v, hitline);
		t0 := sys->millisec();
		dt := int (dist / speed);
		t := 0;
		do {
			s := real t * speed;
			currp := Realpoint(p.x + s * v.x,  p.y + s * v.y);
			bp := Point(int currp.x, int currp.y);
			cmd(win, ".c coords " + ballid + " " +
				string (bp.x-BALLSIZE)+" "+string (bp.y-BALLSIZE)+" "+
				string (bp.x+BALLSIZE)+" "+string (bp.y+BALLSIZE));
			cmd(win, "update");
			if (lineversion > version) {
				(p, hitlineid, version) = (currp, oldid, lineversion);
				continue loop;
			}
			# pass the token back to the monitor.
			if (<-c == 0) {
				cmd(win, ".c delete " + ballid + ";update");
				exit;
			}
			c <-= 1;
			t = sys->millisec() - t0;
		} while (t < dt);
		p = hitp;
		v = bouncev;
	}
}

# thread-safe access to the Rand module
randgenproc(ch: chan of int)
{
	rand := load Rand Rand->PATH;
	for (;;)
		ch <-= rand->rand(16r7fffffff);
}

makelinesproc(win: ref Tk->Toplevel, mch: chan of (int, Point))
{
	for (;;) {
		(down, p1) := <-mch;
		addline(win, (p1, p1));
		(id, nil) := hd lines;
		p2 := p1;
		do {
			(down, p2) = <-mch;
			cmd(win, ".c coords l" + string id + " " + pt2s(p1) + " " + pt2s(p2));
			cmd(win, "update");
			lines = (id, (p1, p2)) :: tl lines;
			lineversion++;
			if (down > 1) {
				dp := p2.sub(p1);
				if (dp.x*dp.x + dp.y*dp.y > 5) {
					p1 = p2;
					addline(win, (p2, p2));
					(id, nil) = hd lines;
				}
			}
		} while (down);
	}
}

# make a vector of unit-length, parallel to v.
makeunit(v: Realpoint): Realpoint
{
	mag := math->sqrt(v.x * v.x + v.y * v.y);
	return (v.x / mag, v.y / mag);
}

# bounce ball travelling in direction av off line b.
# return the new unit vector.
boing(av: Realpoint, b: Line): Realpoint
{
	f := b.p2.sub(b.p1);
	d := math->atan2(real f.y, real f.x) * 2.0 - math->atan2(av.y, av.x);
	return (math->cos(d), math->sin(d));
}

# compute the intersection of lines a and b.
# b is assumed to be fixed, and a is indefinitely long
# but doesn't extend backwards from its starting point.
# a is defined by the starting point p and the unit vector v.
intersect(p, v: Realpoint, b: Line): (int, Realpoint, real)
{
	w := Realpoint(real (b.p2.x - b.p1.x), real (b.p2.y - b.p1.y));
	det := w.x * v.y - v.x * w.y;
	if (det > -ZERO && det < ZERO)
		return (0, (0.0, 0.0), 0.0);

	y21 := real b.p1.y - p.y;
	x21 := real b.p1.x - p.x;
	s := (w.x * y21 - w.y * x21) / det;
	if (s < 0.0)
		return (0, (0.0, 0.0), 0.0);

	hp := Realpoint(p.x+v.x*s, p.y+v.y*s);
	if (b.p1.x > b.p2.x)
		(b.p1.x, b.p2.x) = (b.p2.x, b.p1.x);
	if (b.p1.y > b.p2.y)
		(b.p1.y, b.p2.y) = (b.p2.y, b.p1.y);

	return (int hp.x >= b.p1.x && int hp.x <= b.p2.x
			&& int hp.y >= b.p1.y && int hp.y <= int b.p2.y, hp, s);
}

cmd(top: ref Tk->Toplevel, s: string): string
{
	e := tk->cmd(top, s);
	if (e != nil && e[0] == '!')
		sys->print("tk error %s on '%s'\n", e, s);
	return e;
}

pt2s(p: Point): string
{
	return string p.x + " " + string p.y;
}
