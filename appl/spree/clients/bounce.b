implement Clientmod;

# bouncing balls demo.  it uses tk and multiple processes to animate a
# number of balls bouncing around the screen.  each ball has its own
# process; CPU time is doled out fairly to each process by using
# a central monitor loop.

include "sys.m";
	sys: Sys;
include "draw.m";
	draw: Draw;
	Display, Point, Rect, Image: import draw;
include "tk.m";
	tk: Tk;
include "tkclient.m";
	tkclient: Tkclient;
include "math.m";
	math: Math;
include "rand.m";
include "../client.m";

BALLSIZE: con 5;
ZERO: con 1e-6;
π: con Math->Pi;
Maxδ: con π / 4.0;			# max bat angle deflection

Line: adt {
	p, v:		Realpoint;
	s:		real;
	new:			fn(p1, p2: Point): ref Line;
	hittest:		fn(l: self ref Line, p: Point): (Realpoint, real, real);
	intersection:	fn(b: self ref Line, p, v: Realpoint): (int, Realpoint, real, real);
	point:		fn(b: self ref Line, s: real): Point;
};

Realpoint: adt {
	x, y: real;
};

cliquecmds := array[] of {
"canvas .c -bg black",
"bind .c <ButtonRelease-1> {send mouse 0 1 %x %y}",
"bind .c <ButtonRelease-2> {send mouse 0 2 %x %y}",
"bind .c <Button-1> {send mouse 1 1 %x %y}",
"bind .c <Button-2> {send mouse 1 2 %x %y}",
"bind . <Key-b> {send ucmd newball}",
"bind . <ButtonRelease-1> {focus .}",
"bind .Wm_t <ButtonRelease-1> +{focus .}",
"focus .",
"bind .c <Key-b> {send ucmd newball}",
"bind .c <Key-u> {grab release .c}",
"frame .f",
"button .f.b -text {Start} -command {send ucmd start}",
"button .f.n -text {New ball} -command {send ucmd newball}",
"pack .f.b .f.n -side left",
"pack .f -fill x",
"pack .c -fill both -expand 1",
"update",
};

Ballstate: adt {
	owner: int;		# index into member array
	hitobs: ref Obstacle;
	t0: int;
	p, v: Realpoint;
	speed: real;
};

Queue: adt {
	h, t: list of T; 
	put: fn(q: self ref Queue, s: T);
	get: fn(q: self ref Queue): T;
};


Obstacle: adt {
	line: 		ref Line;
	id: 		int;
	isbat: 	int;
	s1, s2: 	real;
	srvid:	int;
	owner:	int;
	new: 	fn(id: int): ref Obstacle;
	config: 	fn(b: self ref Obstacle);
};

Object: adt {
	obstacle: ref Obstacle;
	ballctl: chan of ref Ballstate;
};


Member: adt {
	id: int;
	colour: string;
};

win: ref Tk->Toplevel;

lines: list of ref Obstacle;
lineversion := 0;
memberid: int;
myturn: int;
stderr: ref Sys->FD;
timeoffset := 0;

objects: array of ref Object;
srvobjects: array of ref Obstacle;	# all for lasthit...
members: array of ref Member;

CORNER: con 60;
INSET: con 20;
WIDTH: con 500;
HEIGHT: con 500;

bats: list of ref Obstacle;
mkball: chan of (int, chan of chan of ref Ballstate);
cliquefd: ref Sys->FD;
currentlydragging := -1;
Ballexit: ref Ballstate;
Noobs: ref Obstacle;

nomod(s: string)
{
	sys->fprint(stderr, "bounce: cannot load %s: %r\n", s);
	sys->raise("fail:bad module");
}

client(ctxt: ref Draw->Context, argv: list of string, nil: int)
{
	sys = load Sys Sys->PATH;
	stderr = sys->fildes(2);
	draw = load Draw Draw->PATH;
	math = load Math Math->PATH;
	tk = load Tk Tk->PATH;
	tkclient = load Tkclient Tkclient->PATH;
	if (tkclient == nil)
		nomod(Tkclient->PATH);
	tkclient->init();
	cliquefd = sys->fildes(0);
	Ballexit = ref Ballstate;
	Noobs = Obstacle.new(-1);
	lines = tl lines;		# XXX ahem.

	if (len argv >= 3)		# argv: modname mnt dir ...
		membername = readfile(hd tl argv + "/name");

	sys->pctl(Sys->NEWPGRP, nil);
	wmctl: chan of string;
	(win, wmctl) = tkclient->toplevel(ctxt.screen, nil, "Bounce", 0);
	ucmd := chan of string;
	tk->namechan(win, ucmd, "ucmd");
	mouse := chan of string;
	tk->namechan(win, mouse, "mouse");
	for (i := 0; i < len cliquecmds; i++)
		cmd(win, cliquecmds[i]);
	cmd(win, ".c configure -width 500 -height 500");
	cmd(win, ".c configure -width [.c cget -actwidth] -height [.c cget -actheight]");
	imageinit();

	mch := chan of (int, Point);

	spawn mouseproc(mch);
	mkball = chan of (int, chan of chan of ref Ballstate);
	spawn monitor(mkball);
	balls: list of chan of ref Ballstate;

	spawn updateproc();
	sys->sleep(500);		# wait for things to calm down a little
	cliquecmd("time " + string sys->millisec());

	buts := 0;
	for (;;) alt {
	c := <-wmctl =>
		if (c == "exit")
			sys->write(cliquefd, array[0] of byte, 0);
		tkclient->wmctl(win, c);
	c := <-mouse =>
		(nil, toks) := sys->tokenize(c, " ");
		if ((hd toks)[0] == '1')
			buts |= int hd tl toks;
		else
			buts &= ~int hd tl toks;
		mch <-= (buts, Point(int hd tl tl toks, int hd tl tl tl toks));
	c := <-ucmd =>
		cliquecmd(c);
	}
}

cliquecmd(s: string): int
{
	if (sys->fprint(cliquefd, "%s\n", s) == -1) {
		err := sys->sprint("%r");
		notify(err);
		sys->print("bounce: cmd error on '%s': %s\n", s, err);
		return 0;
	}
	return 1;
}

updateproc()
{
	wfd := sys->open("/prog/" + string sys->pctl(0, nil) + "/wait", Sys->OREAD);
	spawn updateproc1();
	buf := array[Sys->ATOMICIO] of byte;
	n := sys->read(wfd, buf, len buf);
	sys->print("updateproc process exited: %s\n", string buf[0:n]);
}

updateproc1()
{
	buf := array[Sys->ATOMICIO] of byte;
	while ((n := sys->read(cliquefd, buf, len buf)) > 0) {
		(nil, lines) := sys->tokenize(string buf[0:n], "\n");
		for (; lines != nil; lines = tl lines)
			applyupdate(hd lines);
		cmd(win, "update");
	}
	if (n < 0)
		sys->fprint(stderr, "bounce: error reading updates: %r\n");
	sys->fprint(stderr, "bounce: updateproc exiting\n");
}

UNKNOWN, BALL, OBSTACLE: con iota;

applyupdate(s: string)
{
#	sys->print("bounce: got update %s\n", s);
	(nt, toks) := sys->tokenize(s, " ");
	case hd toks {
	"create" =>
		# create id parentid vis type
		id := int hd tl toks;
		if (id >= len objects) {
			newobjects := array[id + 10] of ref Object;
			newobjects[0:] = objects;
			objects = newobjects;
		}
		objects[id] = ref Object;
	"del" =>
		# del parent start end objid...
		for (toks = tl tl tl tl toks; toks != nil; toks = tl toks) {
			id := int hd toks;
			if (objects[id].obstacle != nil)
				sys->fprint(stderr, "bounce: cannot delete obstructions yet\n");
			else
				objects[id].ballctl <-= Ballexit;
			objects[id] = nil;
		}
	"set" =>
		# set obj attr val
		id := int hd tl toks;
		attr := hd tl tl toks;
		val := tl tl tl toks;
		case attr {
		"state" =>
			# state lasthit owner p.x p.y v.x v.y s time
			state := ref Ballstate;
			(state.hitobs, val) = (srvobj(int hd val), tl val);
			(state.owner, val) = (int hd val, tl val);
			(state.p.x, val) = (real hd val, tl val);
			(state.p.y, val) = (real hd val, tl val);
			(state.v.x, val) = (real hd val, tl val);
			(state.v.y, val) = (real hd val, tl val);
			(state.speed, val) = (real hd val, tl val);
			(state.t0, val) = (int hd val, tl val);
			if (objects[id].ballctl == nil)
				objects[id].ballctl = makeball(id, state);
			else
				objects[id].ballctl <-= state;
		"pos" or "coords" or "owner" or "id" =>
			if (objects[id].obstacle == nil)
				objects[id].obstacle = Obstacle.new(id);
			o := objects[id].obstacle;
			case attr {
			"pos" =>
				(o.s1, val) = (real hd val, tl val);
				(o.s2, val) = (real hd val, tl val);
				o.isbat = 1;
			"coords" =>
				p1, p2: Point;
				(p1.x, val) = (int hd val, tl val);
				(p1.y, val) = (int hd val, tl val);
				(p2.x, val) = (int hd val, tl val);
				(p2.y, val) = (int hd val, tl val);
				o.line = Line.new(p1, p2);
			"owner" =>
				o.owner = hd val;
				if (o.owner == membername)
					bats = o :: bats;
			"id" =>
				o.srvid = int hd val;
				if (o.srvid >= len srvobjects) {
					newobjects := array[id + 10] of ref Obstacle;
					newobjects[0:] = srvobjects;
					srvobjects = newobjects;
				}
				srvobjects[o.srvid] = o;
			}
			if (currentlydragging != id)
				o.config();
		"arenasize" =>
			# arenasize w h
			cmd(win, ".c configure -width " + hd val + " -height " + hd tl val);
		* =>
			if (len attr > 5 && attr[0:5] == "score") {
				# scoreN val
				n := int attr[5:];
				w := ".f." + string n;
				if (!tkexists(w)) {
					cmd(win, "label " + w + "l -text '" + attr);
					cmd(win, "label " + w + " -relief sunken -bd 5 -width 5w");
					cmd(win, "pack " +w + "l " + w + " -side left");
				}
				cmd(win, w + " configure -text {" + hd val + "}");
			} else if (len attr > 6 && attr[0:6] == "member") {
				# memberN id colour
				n := int attr[6:];
				if (n >= len members) {
					newmembers := array[n + 1] of ref Member;
					newmembers[0:] = members;
					members = newmembers;
				}
				p := members[n] = ref Member(int hd val, hd tl val);
				cmd(win, ".c itemconfigure o" + string p.id + " -fill " + p.colour);
				if (p.id == memberid)
					myturn = n;
			}
			else
				sys->fprint(stderr, "bounce: unknown attr '%s'\n", attr);
		}
	"time" =>
		# time offset orig
		now := sys->millisec();
		time := int hd tl tl toks;
		transit := now - time;
		timeoffset = int hd tl toks - transit / 2;
		sys->print("transit time %d, timeoffset: %d\n", transit, timeoffset);
	* =>
		sys->fprint(stderr, "chat: unknown update message '%s'\n", s);
	}
}

tkexists(w: string): int
{
	return tk->cmd(win, w + " cget -bd")[0] != '!';
}

srvobj(id: int): ref Obstacle
{
	if (id < 0 || id >= len srvobjects || srvobjects[id] == nil)
		return Noobs;
	return srvobjects[id];
}

mouseproc(mch: chan of (int, Point))
{
	procname("mouse");
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
	realtosrv := chan of string;
	dummytosrv := chan of string;
	tosrv := dummytosrv;
	currevent := "";

	currentlydragging = hitbat.id;

	line := hitbat.line;
	batlen := hitbat.s2 - hitbat.s1;

	cvsorigin := Point(int cmd(win, ".c cget -actx"), int cmd(win, ".c cget -acty"));
	spawn sendproc(realtosrv);

	cmd(win, "grab set .c");
	cmd(win, "focus .");
loop:	for (;;) alt {
	tosrv <-= currevent =>
		tosrv = dummytosrv;

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
		currevent = "bat " + string hitbat.s1;
		tosrv = realtosrv;
		if (!buts)
			break loop;
	}
	cmd(win, "grab release .c");
	realtosrv <-= nil;
	currentlydragging = -1;
}

CHARGETIME: con 1000.0;
MAXCHARGE: con 50.0;

α: con 0.999;		# decay in one millisecond
D: con 5;
aim(mch: chan of (int, Point), hitbat: ref Obstacle, p: Point): (int, Point)
{
	cvsorigin := Point(int cmd(win, ".c cget -actx"), int cmd(win, ".c cget -acty"));
	startms := ms := sys->millisec();
	δ := Realpoint(0.0, 0.0);
	line := hitbat.line;
	charge := 0.0;
	pivot := line.point((hitbat.s1 + hitbat.s2) / 2.0);
	s1 := p2s(line.point(hitbat.s1));
	s2 := p2s(line.point(hitbat.s2));
	cmd(win, ".c create line 0 0 0 0 -tags wire -fill yellow");
	ballid := makeballitem(-1, myturn);
	bp, p2: Point;
	buts := 2;
	for (;;) {
		v := makeunit(δ);
		bp = pivot.add((int (v.x * charge), int (v.y * charge)));
		cmd(win, ".c coords wire "+s1+" "+p2s(bp)+" "+s2);
		ballmove(ballid, bp);
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
		dp := p2.sub(p);
		δ.x = δ.x * fade + real dp.x;
		δ.y = δ.y * fade + real dp.y;
		mag := δ.x * δ.x + δ.y * δ.y;
		if (dp.x != 0 || dp.y != 0)
			win.image.display.cursorset(p.add(cvsorigin));
	}
	cmd(win, ".c delete wire " + ballid);
	cmd(win, "update");
	(δ.x, δ.y) = (-δ.x, -δ.y);
	cliquecmd("newball " + string hitbat.id + " " +
		p2s(bp) + " " + rp2s(makeunit(δ)) + " " + string (charge / 100.0));
	return (buts, p2);
}

makeunit(v: Realpoint): Realpoint
{
	mag := math->sqrt(v.x * v.x + v.y * v.y);
	if (mag < ZERO)
		return (1.0, 0.0);
	return (v.x / mag, v.y / mag);
}

sendproc(tosrv: chan of string)
{
	procname("send");
	while ((ev := <-tosrv) != nil)
		cliquecmd(ev);
}

makeball(id: int, state: ref Ballstate): chan of ref Ballstate
{
	mkballreply := chan of chan of ref Ballstate;
	mkball <-= (id, mkballreply);
	ballctl := <-mkballreply;
	ballctl <-= state;
	return ballctl;
}

blankobstacle: Obstacle;
Obstacle.new(id: int): ref Obstacle
{
	cmd(win, ".c create line 0 0 0 0 -width 3 -fill #aaaaaa" + " -tags l" + string id);
	o := ref blankobstacle;
	o.line = Line.new((0, 0), (0, 0));
	o.id = id;
	o.owner = -1;
	o.srvid = -1;
	lineversion++;
	lines = o :: lines;
	return o;
}

Obstacle.config(o: self ref Obstacle)
{
	if (o.isbat) {
		cmd(win, ".c coords l" + string o.id + " " +
			p2s(o.line.point(o.s1)) + " " + p2s(o.line.point(o.s2)));
		if (o.owner == memberid)
			cmd(win, ".c itemconfigure l" + string o.id + " -fill red");
		else
			cmd(win, ".c itemconfigure l" + string o.id + " -fill white");
	} else {
		cmd(win, ".c coords l" + string o.id + " " +
			p2s(o.line.point(0.0)) + " " + p2s(o.line.point(o.line.s)));
	}
}
	
# make sure cpu time is handed to all ball processes fairly
# by passing a "token" around to each process in turn.
# each process does its work when it *hasn't* got its
# token but it can't go through two iterations without
# waiting its turn.
#
# new processes are created by sending on mkball.
# the channel sent back can be used to control the position
# and velocity of the ball and to destroy it.
monitor(mkball: chan of (int, chan of chan of ref Ballstate))
{
	procname("mon");
	procl, proc: list of (chan of ref Ballstate, chan of int);
	rc := dummyrc := chan of int;
	for (;;) {
		alt {
		(id, ch) := <-mkball =>
			(newc, newrc) := (chan of ref Ballstate, chan of int);
			procl = (newc, newrc) :: procl;
			spawn animproc(id, newc, newrc);
			ch <-= newc;
			if (tl procl == nil) {		# first ball
				newc <-= nil;
				rc = newrc;
				proc = procl;
			}
		alive := <-rc =>					# got token.
			if (!alive) {
				# ball has exited: remove from list
				newprocl: list of (chan of ref Ballstate, chan of int);
				for (; procl != nil; procl = tl procl)
					if ((hd procl).t1 != rc)
						newprocl = hd procl :: newprocl;
				procl = newprocl;
			}
			if ((proc = tl proc) == nil)
				proc = procl;
			if (proc == nil) {
				rc = dummyrc;
			} else {
				c: chan of ref Ballstate;
				(c, rc) = hd proc;
				c <-= nil;				# hand token to next process.
			}
		}
	}
}

# buffer ball state commands, so at least balls we handle
# locally appear glitch free.
bufferproc(cmdch: chan of string)
{
	procname("buffer");
	buffer := ref Queue;
	bufhd: string;
	dummytosrv := chan of string;
	realtosrv := chan of string;
	spawn sendproc(realtosrv);
	tosrv := dummytosrv;
	for (;;) alt {
	tosrv <-= bufhd =>
		if ((bufhd = buffer.get()) == nil)
			tosrv = dummytosrv;
	s := <-cmdch =>
		if (s == nil) {
			# ignore other queued requests, as they're
			# only state changes for a ball that's now been deleted.
			realtosrv <-= nil;
			exit;
		}
		buffer.put(s);
		if (tosrv == dummytosrv) {
			tosrv = realtosrv;
			bufhd = buffer.get();
		}
	}
}
start: int;
# animate one ball. initial position and unit-velocity are
# given by p and v.
animproc(id: int, c: chan of ref Ballstate, rc: chan of int)
{
	procname("anim");
	while ((newstate := <-c) == nil)
		rc <-= 1;
	state := *newstate;
	totaldist := 0.0;		# distance ball has travelled from reference point to last intersection
	ballid := makeballitem(id, state.owner);
	smallcount := 0;
	version := lineversion;
	tosrv := chan of string;
	start := sys->millisec();
	spawn bufferproc(tosrv);
loop:	for (;;) {
		hitp: Realpoint;

		dist := 1000000.0;
		oldobs := state.hitobs;
		hitt: real;
		for (l := lines; l != nil; l = tl l) {
			obs := hd l;
			(ok, hp, hdist, t) := obs.line.intersection(state.p, state.v);
			if (ok && hdist < dist && obs != oldobs && (smallcount < 10 || hdist > 1.5)) {
				(hitp, state.hitobs, dist, hitt) = (hp, obs, hdist, t);
			}
		}
		if (dist > 10000.0) {
			sys->print("no intersection!\n");
			state = ballexit(1, ballid, tosrv, c, rc);
			totaldist = 0.0;
			continue loop;
		}
		if (dist < 0.0001)
			smallcount++;
		else
			smallcount = 0;
		t0 := int (totaldist / state.speed) + state.t0 - timeoffset;
		et := t0 + int (dist / state.speed);
		t := sys->millisec() - t0;
		dt := et - t0;
		do {
			s := real t * state.speed;
			currp := Realpoint(state.p.x + s * state.v.x,  state.p.y + s * state.v.y);
			ballmove(ballid, (int currp.x, int currp.y));
			cmd(win, "update");
			if (lineversion > version) {
				(state.p, state.hitobs, version) = (currp, oldobs, lineversion);
				totaldist += s;
				continue loop;
			}
			if ((newstate := <-c) != nil) {
				if (newstate == Ballexit)
					ballexit(0, ballid, tosrv, c, rc);
				state = *newstate;
				totaldist = 0.0;
				continue loop;
			}
			rc <-= 1;
			t = sys->millisec() - t0;
		} while (t < dt);
		totaldist += dist;
		state.p = hitp;
		hitobs := state.hitobs;
		if (hitobs.isbat) {
			if (hitobs.owner == memberid) {
				if (hitt >= hitobs.s1 && hitt <= hitobs.s2)
					state.v = batboing(hitobs, hitt, state.v);
				tosrv <-= "state " + 
					string id + 
					" " + string hitobs.srvid +
					" " + string state.owner +
					" " + rp2s(state.p) + " " + rp2s(state.v) +
					" " + string state.speed +
					" " + string (sys->millisec() + timeoffset);
			} else {
				# wait for enlightenment
				while ((newstate := <-c) == nil)
					rc <-= 1;
				if (newstate == Ballexit)
					ballexit(0, ballid, tosrv, c, rc);
				state = *newstate;
				totaldist = 0.0;
			}
		} else if (hitobs.owner == memberid) {
			# if line has an owner but isn't a bat, then it's
			# a terminating line, so we inform server.
			cliquecmd("lost " + string id);
			state = ballexit(1, ballid, tosrv, c, rc);
			totaldist = 0.0;
		} else
			state.v = boing(state.v, hitobs.line);
	}
}

#ballmask: ref Image;
imageinit()
{
#	displ := win.image.display;
#	ballmask = displ.newimage(((0, 0), (BALLSIZE+1, BALLSIZE+1)), 0, 0, Draw->White);
#	ballmask.draw(ballmask.r, displ.zeros, displ.ones, (0, 0));
#	ballmask.fillellipse((BALLSIZE/2, BALLSIZE/2), BALLSIZE/2, BALLSIZE/2, displ.ones,  (0, 0));
#	End: con Draw->Endsquare;
#	n := 5;
#	θ := 0.0;
#	δ := (2.0 * π) / real n;
#	c := Point(BALLSIZE / 2, BALLSIZE / 2).sub((1, 1));
#	r := real (BALLSIZE / 2);
#	for (i := 0; i < n; i++) {
#		p2 := Point(int (r * math->cos(θ)), int (r * math->sin(θ)));
#		sys->print("drawing from %s to %s\n", p2s(c), p2s(p2.add(c)));
#		ballmask.line(c, c.add(p2), End, End, 1, displ.ones, (0, 0));
#		θ += δ;
#	}
}

makeballitem(id, owner: int): string
{
	displ := win.image.display;
	return cmd(win, ".c create oval 0 0 1 1 -fill " + members[owner].colour +
			" -tags o" + string owner);
}

ballmove(ballid: string, p: Point)
{
	cmd(win, ".c coords " + ballid +
		" " + string (p.x - BALLSIZE) +
		" " + string (p.y - BALLSIZE) +
		" " + string (p.x + BALLSIZE) +
		" " + string (p.y + BALLSIZE));
}

ballexit(wait: int, ballid: string, tosrv: chan of string, c: chan of ref Ballstate, rc: chan of int): Ballstate
{
	if (wait) {
		while ((s := <-c) != Ballexit)
			if (s == nil)
				rc <-= 1;
			else
				return *s;			# maybe we're not exiting, after all...
	}
	cmd(win, ".c delete " + ballid + ";update");
#	cmd(win, "image delete " + ballid);
	tosrv <-= nil;
	<-c;
	rc <-= 0;		# inform monitor that we've gone
	exit;
}

# thread-safe access to the Rand module
randgenproc(ch: chan of int)
{
	procname("rand");
	rand := load Rand Rand->PATH;
	for (;;)
		ch <-= rand->rand(16r7fffffff);
}

abs(x: real): real
{
	if (x < 0.0)
		return -x;
	return x;
}

# bounce ball travelling in direction av off line b.
# return the new unit vector.
boing(av: Realpoint, b: ref Line): Realpoint
{
	d := math->atan2(b.v.y, b.v.x) * 2.0 - math->atan2(av.y, av.x);
	return (math->cos(d), math->sin(d));
}

# calculate how a bounce vector should be modified when
# hitting a bat. t gives the intersection point on the bat;
# ballv is the ball's vector.
batboing(bat: ref Obstacle, t: real, ballv: Realpoint): Realpoint
{
	ballθ := math->atan2(ballv.y, ballv.x);
	batθ := math->atan2(bat.line.v.y, bat.line.v.x);
	φ := ballθ - batθ;
	δ: real;
	t -= bat.s1;
	batlen := bat.s2 - bat.s1;
	if (math->sin(φ) > 0.0)
		δ = (t / batlen) * Maxδ * 2.0 - Maxδ;
	else
		δ = (t / batlen) * -Maxδ * 2.0 + Maxδ;
	θ := math->atan2(bat.line.v.y, bat.line.v.x) * 2.0 - ballθ;	# boing
	θ += δ;
	return (math->cos(θ), math->sin(θ));
}

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

cmd(top: ref Tk->Toplevel, s: string): string
{
	e := tk->cmd(top, s);
	if (e != nil && e[0] == '!')
		sys->print("tk error %s on '%s'\n", e, s);
	return e;
}

state2s(s: ref Ballstate): string
{
	return sys->sprint("[hitobs:%d(id %d), t0: %d, p: %g %g; v: %g %g; s: %g",
		s.hitobs.srvid, s.hitobs.id, s.t0, s.p.x, s.p.y, s.v.x, s.v.y, s.speed);
}

l2s(l: ref Line): string
{
	return p2s(l.point(0.0)) + " " + p2s(l.point(l.s));
}

rp2s(rp: Realpoint): string
{
	return string rp.x + " " + string rp.y;
}


p2s(p: Point): string
{
	return string p.x + " " + string p.y;
}

notifypid := -1;
notify(s: string)
{
	kill(notifypid);
	sync := chan of int;
	spawn notifyproc(s, sync);
	notifypid = <-sync;
}

notifyproc(s: string, sync: chan of int)
{
	procname("notify");
	sync <-= sys->pctl(0, nil);
	cmd(win, ".c delete notify");
	id := cmd(win, ".c create text 0 0 -anchor nw -fill red -tags notify -text '" + s);
	bbox := cmd(win, ".c bbox " + id);
	cmd(win, ".c create rectangle " + bbox + " -fill #ffffaa -tags notify");
	cmd(win, ".c raise " + id);
	cmd(win, "update");
	sys->sleep(750);
	cmd(win, ".c delete notify");
	cmd(win, "update");
	notifypid = -1;
}

kill(pid: int)
{
	if ((fd := sys->open("/prog/"+string pid+"/ctl", Sys->OWRITE)) != nil)
		sys->write(fd, array of byte "kill", 4);
}

T: type string;

Queue.put(q: self ref Queue, s: T)
{
	q.t = s :: q.t;
}

Queue.get(q: self ref Queue): T
{
	s: T;
	if(q.h == nil){
		q.h = revlist(q.t);
		q.t = nil;
	}
	if(q.h != nil){
		s = hd q.h;
		q.h = tl q.h;
	}
	return s;
}

revlist(ls: list of T) : list of T
{
	rs: list of T;
	for (; ls != nil; ls = tl ls)
		rs = hd ls :: rs;
	return rs;
}

procname(s: string)
{
#	sys->procname(sys->procname(nil) + " " + s);
}

