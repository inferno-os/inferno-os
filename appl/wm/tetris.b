# Copyright  © 1999 Roger Peppe.  All rights reserved.
implement Tetris;

include "sys.m";
	sys: Sys;
	stderr: ref Sys->FD;
include "draw.m";
	draw: Draw;
	Point, Rect: import draw;
include "tk.m";
	tk: Tk;
include "tkclient.m";
	tkclient: Tkclient;
include "rand.m";
	rand: Rand;
include "scoretable.m";
	scoretab: Scoretable;
include "arg.m";
include "keyboard.m";
	Up, Down, Right, Left: import Keyboard;

include "keyring.m";
include "security.m";	# for random seed

Tetris: module {
	init: fn(ctxt: ref Draw->Context, argv: list of string);
};

SCORETABLE: con "/lib/scores/tetris";
LOCKPORT: con 18343;

# number of pieces across and down board.
BOARDWIDTH: con 10;
BOARDHEIGHT: con 22;

awaitingscore := 1;
	
Row: adt {
	tag:		string;
	delete:	int;
};

Board: adt {
	new:			fn(top: ref Tk->Toplevel, w: string,
					blocksize: int, maxsize: Point): ref Board;
	makeblock:	fn(bd: self ref Board, colour: string, p: Point): string;
	moveblock:	fn(bd: self ref Board, b: string, p: Point);
	movecurr:	fn(bd: self ref Board, delta: Point);
	delrows:		fn(bd: self ref Board, rows: list of int);
	landedblock:	fn(bd: self ref Board, b: string, p: Point);
	setnextshape:	fn(bd: self ref Board, colour: string, spec: array of Point);
	setscore:		fn(bd: self ref Board, score: int);
	setlevel:		fn(bd: self ref Board, level: int);
	setnrows:		fn(bd: self ref Board, level: int);
	gameover:	fn(bd: self ref Board);
	update:		fn(bd: self ref Board);

	state:		array of array of byte;
	w:			string;
	dx:			int;
	win:			ref Tk->Toplevel;
	rows:		array of Row;
	maxid:		int;
};

Piece: adt {
	shape:	int;
	rot:		int;
};

Shape: adt {
	coords:	array of array of Point;
	colour:	string;
	score:	array of int;
};

Game: adt {
	new:		fn(bd: ref Board): ref Game;
	move:	fn(g: self ref Game, dx: int);
	rotate:	fn(g: self ref Game, clockwise: int);
	tick:		fn(g: self ref Game): int;
	drop:	fn(g: self ref Game);

	bd:		ref Board;
	level:	int;
	delay:	int;
	score:	int;
	nrows:	int;
	pieceids:	array of string;
	pos:		Point;
	next,
	curr:		Piece;
};

badmod(path: string)
{
	sys->fprint(stderr, "tetris: cannot load %s: %r\n", path);
	raise "fail: bad module";
}

usage()
{
	sys->fprint(stderr, "usage: tetris [-b blocksize]\n");
	raise "fail:usage";
}

init(ctxt: ref Draw->Context, argv: list of string)
{
	sys = load Sys Sys->PATH;
	stderr = sys->fildes(2);
	draw = load Draw Draw->PATH;
	tk = load Tk Tk->PATH;
	if (tk == nil)
		badmod(Tk->PATH);
	tkclient = load Tkclient Tkclient->PATH;
	if (tkclient == nil)
		badmod(Tkclient->PATH);
	tkclient->init();
	rand = load Rand Rand->PATH;
	if (rand == nil)
		badmod(Rand->PATH);
	arg := load Arg Arg->PATH;
	if (arg == nil)
		badmod(Arg->PATH);
	if (ctxt == nil)
		ctxt = tkclient->makedrawcontext();
	blocksize := 17;			# preferred block size
	arg->init(argv);
	while ((opt := arg->opt()) != 0) {
		case opt {
		'b' =>
			if ((b := arg->arg()) == nil || int b <= 0)
				usage();
			blocksize = int b;
		* =>
			usage();
		}
	}
	if (arg->argv() != nil)
		usage();
	
	sys->pctl(Sys->NEWPGRP|Sys->FORKNS, nil);
	scoretab = load Scoretable Scoretable->PATH;
	scorech := chan of int;
	spawn scoresrvwait(scorech);
	(win, winctl) := tkclient->toplevel(ctxt, "", "Tetris",Tkclient->Hide);
	seedrand();
	fromuser := chan of string;
	tk->namechan(win, fromuser, "user");
	cmd(win, "bind . <Key> {send user k %s}");
	cmd(win, "bind . <ButtonRelease-1> {focus .}");
	cmd(win, "bind .Wm_t <ButtonRelease-1> +{focus .}");
	cmd(win, "focus .");

	maxsize := Point(10000, 10000);
	if (ctxt.display.image != nil) {
		img := ctxt.display.image;
		wsz := wsize(win, ".");
		maxsize.y = img.r.dy() - wsz.y;
		maxsize.x = img.r.dx();
	}
		
	tkclient->onscreen(win, nil);
	tkclient->startinput(win, "kbd"::"ptr"::nil);
	for (;;) {
		bd := Board.new(win, ".f", blocksize, maxsize);
		if (bd == nil) {
			sys->fprint(stderr, "tetris: couldn't make board\n");
			return;
		}
		cmd(win, "bind .f.c <ButtonRelease-1> {send user m %x %y}");
		cmd(win, "pack .f -side top");
		cmd(win, "update");
		g := Game.new(bd);
		(finished, rank) := rungame(g, win, fromuser, winctl, scorech);
		if (finished)
			break;
		cmd(win, "pack propagate . 0");
		if (scoretab != nil) {
			cmd(win, "destroy .f");
			if (showhighscores(win, fromuser, winctl, rank) == 0)
				break;
		} else
			cmd(win, "destroy .f");
	}
}

wsize(win: ref Tk->Toplevel, w: string): Point
{
	bd := int cmd(win, w + " cget -bd");
	return (int cmd(win, w + " cget -width") + bd * 2,
		int cmd(win, w + " cget -height") + bd * 2);
}

rungame(g: ref Game, win: ref Tk->Toplevel, fromuser: chan of string, winctl: chan of string, scorech: chan of int): (int, int)
{	
	tickchan := chan of int;
	spawn ticker(g, tickchan);
	paused := 0;
	tch := chan of int;

	gameover := 0;
	rank := -1;
	bdsize := wsize(win, ".f.c");
	boundy := bdsize.y * 2 / 3;
	id := cmd(win, ".f.c create line " + p2s((0, boundy)) + " " + p2s((bdsize.x, boundy)) +
			" -fill white");
	cmd(win, ".f.c lower " + id);
	for (;;) alt {
	s := <-win.ctxt.kbd =>
		tk->keyboard(win, s);
	s := <-win.ctxt.ptr =>
		tk->pointer(win, *s);
	s := <-fromuser =>
		key: int;
		if (s[0] == 'm') {
			(nil, toks) := sys->tokenize(s, " ");
			p := Point(int hd tl toks, int hd tl tl toks);
			if (p.y > boundy)
				key = ' ';
			else {
				x := p.x / (bdsize.x / 3);
				case x {
				0 =>
					key = '7';
				1 =>
					key = '8';
				2 =>
					key = '9';
				* =>
					break;
				}
			}
		} else if (s[0] == 'k')
			key = int s[1:];
		else
			sys->print("oops (%s)\n", s);
		if (gameover)
			return (key == 'q', rank);
		if (paused) {
			paused = 0;
			(tickchan, tch) = (tch, tickchan);
			if (key != 'q')
				continue;
		}
		case key {
		'9'  or 'c' or Right =>
			g.move(1);
		'7' or 'z' or Left =>
			g.move(-1);
		'8' or 'x' or Up =>
			g.rotate(0);
		' ' or Down =>
			g.drop();
		'p' =>
			paused = 1;
			(tickchan, tch) = (tch, tickchan);
		'q' =>
			g.delay = -1;
			while (<-tickchan)
				;
			return (1, rank);
		}
	s := <-win.ctxt.ctl or
	s = <-win.wreq or
	s = <-winctl =>
		tkclient->wmctl(win, s);
	n := <-tickchan =>
		if (g.tick() == -1) {
			while (n)
				n = <-tickchan;
			if (awaitingscore && !<-scorech) {
				awaitingscore = 0;
				scoretab = nil;
			}
			if (scoretab != nil)
				rank = scoretab->setscore(g.score, sys->sprint("%d %d %bd", g.nrows, g.level,
						big readfile("/dev/time") / big 1000000));
			gameover = 1;
		}
	ok := <-scorech =>
		awaitingscore = 0;
		if (!ok)
			scoretab = nil;
	}
}

tablerow(win: ref Tk->Toplevel, w, bg: string, relief: string, vals: array of string, widths: array of string)
{
	cmd(win, "frame " + w + " -bd 2 -relief " + relief);
	for (i := 0; i < len vals; i++) {
		cw := cmd(win, "label " + w + "." + string i + " -text " + tk->quote(vals[i]) + " -width " + widths[i] + bg);
		cmd(win, "pack " + cw + " -side left -anchor w");
	}
	cmd(win, "pack " + w + " -side top");
}

showhighscores(win: ref Tk->Toplevel, fromuser: chan of string, winctl: chan of string, rank: int): int
{
	widths := array[] of {"10w", "7w", "7w", "5w"};	# user, score, level, rows
	cmd(win, "frame .f -bd 4 -relief raised");
	cmd(win, "label .f.title -text {High Scores}");
	cmd(win, "pack .f.title -side top -anchor n");
	tablerow(win, ".f.h", nil, "raised", array[] of {"User", "Score", "Level", "Rows"}, widths);
	sl := scoretab->scores();
	n := 0;
	while (sl != nil) {
		s := hd sl;
		bg := "";
		if (n == rank)
			bg = " -bg white";
		f := ".f.f" + string n++;
		nrows := level := "";
		(nil, toks) := sys->tokenize(s.other, " ");
		if (toks != nil)
			(nrows, toks) = (hd toks, tl toks);
		if (toks != nil)
			level = hd toks;
		tablerow(win, f, bg, "sunken", array[] of {s.user, string s.score, level, nrows}, widths);
		sl = tl sl;
	}
	cmd(win, "button .f.b -text {New game} -command {send user s}");
	cmd(win, "pack .f.b -side top");
	cmd(win, "pack .f -side top");
	cmd(win, "update");
	for (;;) alt {
	s := <-win.ctxt.kbd =>
		tk->keyboard(win, s);
	s := <-win.ctxt.ptr =>
		tk->pointer(win, *s);
	s := <-fromuser =>
		if (s[0] == 'k') {
			cmd(win, "destroy .f");
			return int s[1:] != 'q';
		} else if (s[0] == 's') {
			cmd(win, "destroy .f");
			return 1;
		}
	s := <-win.ctxt.ctl or
	s = <-win.wreq or
	s = <-winctl =>
		tkclient->wmctl(win, s);
	}
}

scoresrvwait(ch: chan of int)
{
	if (scoretab == nil) {
		ch <-= 0;
		return;
	}
	(ok, err) := scoretab->init(LOCKPORT, readfile("/dev/user"), "tetris", SCORETABLE);
	if (ok != -1)
		ch <-= 1;
	else {
		if (err != "timeout")
			sys->fprint(stderr, "tetris: scoretable error: %s\n", err);
		else
			sys->fprint(stderr, "tetris: timed out trying to connect to score server\n");
		ch <-= 0;
	}
}

readfile(f: string): string
{
	fd := sys->open(f, Sys->OREAD);
	if (fd == nil)
		return nil;
	buf := array[Sys->ATOMICIO] of byte;
	n := sys->read(fd, buf, len buf);
	if (n <= 0)
		return nil;
	return string buf[0:n];
}

ticker(g: ref Game, c: chan of int)
{
	c <-= 1;
	while (g.delay >= 0) {
		sys->sleep(g.delay);
		c <-= 1;
	}
	c <-= 0;
}

seedrand()
{
	random := load Random Random->PATH;
	if (random == nil) {
		sys->fprint(stderr, "tetris: cannot load %s: %r\n", Random->PATH);
		return;
	}
	seed := random->randomint(Random->ReallyRandom);
	rand->init(seed);
}

Game.new(bd: ref Board): ref Game
{
	g := ref Game;
	g.bd = bd;
	g.level = 0;
	g.pieceids = array[4] of string;
	g.score = 0;
	g.delay = delays[g.level];
	g.nrows = 0;
	g.next = randompiece();
	newpiece(g);
	bd.update();
	return g;
}

randompiece(): Piece
{
	p: Piece;
	p.shape = rand->rand(len shapes);
	p.rot = rand->rand(len shapes[p.shape].coords);
	return p;
}

Game.move(g: self ref Game, dx: int)
{
	np := g.pos.add((dx, 0));
	if (canmove(g, g.curr, np)) {
		g.bd.movecurr((dx, 0));
		g.bd.update();
		g.pos = np;
	}
}

Game.rotate(g: self ref Game, clockwise: int)
{
	inc := 1;
	if (!clockwise)
		inc = -1;
	npiece := g.curr;
	coords := shapes[npiece.shape].coords;
	nrots := len coords;
	npiece.rot = (npiece.rot + inc + nrots) % nrots;
	if (canmove(g, npiece, g.pos)) {
		c := coords[npiece.rot];
		for (i := 0; i < len c; i++)
			g.bd.moveblock(g.pieceids[i], g.pos.add(c[i]));
		g.curr = npiece;
		g.bd.update();
	}
}
		
Game.tick(g: self ref Game): int
{
	if (canmove(g, g.curr, g.pos.add((0, 1)))) {
		g.bd.movecurr((0, 1));
		g.pos.y++;
	} else {
		c := shapes[g.curr.shape].coords[g.curr.rot];
		max := g.pos.y;
		min := g.pos.y + 4;
		for (i := 0; i < len c; i++) {
			p := g.pos.add(c[i]);
			if (p.y < 0) {
				g.delay = -1;
				g.bd.gameover();
				g.bd.update();
				return -1;
			}
			if (p.y > max)
				max = p.y;
			if (p.y < min)
				min = p.y;
			g.bd.landedblock(g.pieceids[i], p);
		}
		full: list of int;
		for (i = min; i <= max; i++) {
			for (x := 0; x < BOARDWIDTH; x++)
				if (g.bd.state[i][x] == byte 0)
					break;
			if (x == BOARDWIDTH)
				full = i :: full;
		}
		if (full != nil) {
			g.bd.delrows(full);
			g.nrows += len full;
			g.bd.setnrows(g.nrows);
			level := g.nrows / 10;
			if (level != g.level) {
				g.bd.setlevel(level);
				g.level  = level;
				if (level >= len delays)
					level = len delays - 1;
				g.delay = delays[level];
			}
		}
		g.score += shapes[g.curr.shape].score[g.curr.rot];
		g.bd.setscore(g.score);
		newpiece(g);
	}
	g.bd.update();
	return 0;
}

Game.drop(g: self ref Game)
{
	p := g.pos.add((0, 1));
	while (canmove(g, g.curr, p))
		p.y++;
	p.y--;
	g.bd.movecurr((0, p.y - g.pos.y));
	g.pos = p;
	g.bd.update();
}

canmove(g: ref Game, piece: Piece, p: Point): int
{
	c := shapes[piece.shape].coords[piece.rot];
	for (i := 0; i < len c; i++) {
		q := p.add(c[i]);
		if (q.x < 0 || q.x >= BOARDWIDTH || q.y >= BOARDHEIGHT)
			return 0;
		if (q.y >= 0 && int g.bd.state[q.y][q.x])
			return 0;
	}
	return 1;
}

newpiece(g: ref Game)
{
	g.curr = g.next;
	g.next = randompiece();
	g.bd.setnextshape(shapes[g.next.shape].colour, shapes[g.next.shape].coords[g.next.rot]);
	shape := shapes[g.curr.shape];
	coords := shape.coords[g.curr.rot];
	g.pos = (3, -4);
	for (i := 0; i < len coords; i++)
		g.pieceids[i] = g.bd.makeblock(shape.colour, g.pos.add(coords[i]));
}

p2s(p: Point): string
{
	return string p.x + " " + string p.y;
}

Board.new(top: ref Tk->Toplevel, w: string, blocksize: int, maxsize: Point): ref Board
{
	cmd(top, "frame " + w);
	cmd(top, "canvas " + w + ".c -borderwidth 2 -relief sunken -width 1 -height 1");
	cmd(top, "frame " + w + ".f");
	cmd(top, "canvas " + w + ".f.ns -width 1 -height 1");
	makescorewidget(top, w + ".f.scoref", "Score");
	makescorewidget(top, w + ".f.levelf", "Level");
	makescorewidget(top, w + ".f.rowsf", "Rows");
	cmd(top, "pack " + w + ".c -side left");
	cmd(top, "pack " + w + ".f -side top");
	cmd(top, "pack " + w + ".f.ns -side top");
	cmd(top, "pack " + w + ".f.scoref -side top -fill x");
	cmd(top, "pack " + w + ".f.levelf -side top -fill x");
	cmd(top, "pack " + w + ".f.rowsf -side top -fill x");

	sz := wsize(top, w);
	avail := Point(maxsize.x - sz.x, maxsize.y);
	avail.x /= BOARDWIDTH;
	avail.y /= BOARDHEIGHT;
	dx := avail.x;
	if (avail.y < avail.x)
		dx = avail.y;
	if (dx <= 0)
		return nil;
	if (dx > blocksize)
		dx = blocksize;
	cmd(top, w + ".f.ns configure -width " + string(4 * dx + 1 - 2*2) +
			" -height " + string(4 * dx + 1 - 2*2));
	cmd(top, w + ".c configure -width " + string(dx * BOARDWIDTH + 1) +
		" -height " + string(dx * BOARDHEIGHT + 1));
	bd := ref Board(array[BOARDHEIGHT]
					of {* => array[BOARDWIDTH] of {* => byte 0}},
			w, dx, top, array[BOARDHEIGHT]  of {* => Row(nil, 0)}, 1);
	return bd;
}

makescorewidget(top: ref Tk->Toplevel, w, title: string)
{
	cmd(top, "frame " + w);
	cmd(top, "label " + w + ".title -text " + tk->quote(title));
	cmd(top, "label " + w +
		".val -bd 2 -relief sunken -width 5w -text 0 -anchor e");
	cmd(top, "pack " + w + ".title -side left -anchor w");
	cmd(top, "pack " + w + ".val -side right -anchor e");
}

blockrect(bd: ref Board, p: Point): string
{
	p = p.mul(bd.dx);
	q := p.add((bd.dx, bd.dx));
	return string p.x + " " + string p.y + " " + string q.x + " " + string q.y;
}

Board.makeblock(bd: self ref Board, colour: string, p: Point): string
{
	tag := cmd(bd.win, bd.w + ".c create rectangle " + blockrect(bd, p) + " -fill " + colour + " -tags curr");
	if (tag != nil && tag[0] == '!')
		return nil;
	return tag;
}

Board.moveblock(bd: self ref Board, b: string, p: Point)
{
	cmd(bd.win, bd.w + ".c coords " + b + " " + blockrect(bd, p));
}

Board.movecurr(bd: self ref Board, delta: Point)
{
	delta = delta.mul(bd.dx);
	cmd(bd.win, bd.w + ".c move curr " + string delta.x + " " + string delta.y);
}

Board.landedblock(bd: self ref Board, b: string, p: Point)
{
	cmd(bd.win, bd.w + ".c dtag " + b + " curr");
	rs := cmd(bd.win, bd.w + ".c coords " + b);
	if (rs != nil && rs[0] == '!')
		return;
	(nil, toks) := sys->tokenize(rs, " ");
	if (len toks != 4) {
		sys->fprint(stderr, "bad coords for block %s\n", b);
		return;
	}
	y := int hd tl toks / bd.dx;
	if (y < 0)
		return;
	if (y >= BOARDHEIGHT) {
		sys->fprint(stderr, "block '%s' too far down (coords %s)\n", b, rs);
		return;
	}
	rtag := bd.rows[y].tag;
	if (rtag == nil)
		rtag = bd.rows[y].tag = "r" + string bd.maxid++;
	cmd(bd.win, bd.w + ".c addtag " + rtag + " withtag " + b);
	if (p.y >= 0)
		bd.state[p.y][p.x] = byte 1;
}
	
Board.delrows(bd: self ref Board, rows: list of int)
{
	while (rows != nil) {
		r := hd rows;
		bd.rows[r].delete = 1;
		rows = tl rows;
	}
	j := BOARDHEIGHT - 1;
	for (i := BOARDHEIGHT - 1; i >= 0; i--) {
		if (bd.rows[i].delete) {
			cmd(bd.win, bd.w + ".c delete " + bd.rows[i].tag);
			bd.rows[i] = (nil, 0);
			bd.state[i] = nil;
		} else {
			if (i != j && bd.rows[i].tag != nil) {
				dy := (j - i) * bd.dx;
				cmd(bd.win, bd.w + ".c move " + bd.rows[i].tag + " 0 " + string dy);
				bd.rows[j] = bd.rows[i];
				bd.rows[i] = (nil, 0);
				bd.state[j] = bd.state[i];
				bd.state[i] = nil;
			}
			j--;
		}
	}
	for (i = 0; i < BOARDHEIGHT; i++)
		if (bd.state[i] == nil)
			bd.state[i] = array[BOARDWIDTH] of {* => byte 0};
}

Board.update(bd: self ref Board)
{
	cmd(bd.win, "update");
}

Board.setnextshape(bd: self ref Board, colour: string, spec: array of Point)
{
	cmd(bd.win, bd.w + ".f.ns delete all");
	min := Point(4,4);
	max := Point(0,0);
	for (i := 0; i < len spec; i++) {
		if (spec[i].x > max.x) max.x = spec[i].x;
		if (spec[i].x < min.x) min.x = spec[i].x;
		if (spec[i].y > max.y) max.y = spec[i].y;
		if (spec[i].y < min.y) min.y = spec[i].y;
	}
	o: Point;
	o.x = (4 - (max.x - min.x + 1)) * bd.dx / 2 - min.x * bd.dx;
	o.y = (4 - (max.y - min.y + 1)) * bd.dx / 2 - min.y * bd.dx;
	for (i = 0; i < len spec; i++) {
		br := Rect(o.add(spec[i].mul(bd.dx)), o.add(spec[i].add((1,1)).mul(bd.dx)));
		cmd(bd.win, bd.w + ".f.ns create rectangle " +
			string br.min.x + " " + string br.min.y + " " + string br.max.x + " " + string br.max.y +
			" -fill " + colour);
	}
}

Board.setscore(bd: self ref Board, score: int)
{
	cmd(bd.win, bd.w + ".f.scoref.val configure -text " + string score);
}

Board.setlevel(bd: self ref Board, level: int)
{
	cmd(bd.win, bd.w + ".f.levelf.val configure -text " + string level);
}

Board.setnrows(bd: self ref Board, nrows: int)
{
	cmd(bd.win, bd.w + ".f.rowsf.val configure -text " + string nrows);
}

Board.gameover(bd: self ref Board)
{
	cmd(bd.win, "label " + bd.w + ".gameover -text {Game over} -bd 4 -relief ridge");
	p := Point(BOARDWIDTH * bd.dx / 2, BOARDHEIGHT * bd.dx / 3);
	cmd(bd.win, bd.w + ".c create window " + string p.x + " " + string p.y + " -window " + bd.w + ".gameover");
}

cmd(top: ref Tk->Toplevel, s: string): string
{
	e := tk->cmd(top, s);
#	sys->print("%s\n", s);
	if (e != nil && e[0] == '!')
		sys->fprint(stderr, "tetris: tk error on '%s': %s\n", s, e);
	return e;
}

VIOLET: con "#ffaaff";
CYAN: con "#93ddf1";

delays := array[] of {300, 250, 200, 150, 100, 80};

shapes := array[] of {
Shape(
	# ####
	array[] of {
		array[] of {Point(0,1), Point(1,1), Point(2,1), Point(3,1)},
		array[] of {Point(1,0), Point(1,1), Point(1,2), Point(1,3)},
	},
	"red",
	array[] of {5, 8}),
Shape(
	# ##
	# ##
	array[] of {
		array[] of {Point(0,0), Point(0,1), Point(1,0), Point(1,1)},
	},
	"orange",
	array[] of {6}),
Shape(
	# #
	# ##
	# #
	array[] of {
		array[] of {Point(1,0), Point(0,1), Point(1,1), Point(2,1)},
		array[] of {Point(1,0), Point(1,1), Point(2,1), Point(1,2)},
		array[] of {Point(0,1), Point(1,1), Point(2,1), Point(1,2)},
		array[] of {Point(1,0), Point(0,1), Point(1,1), Point(1,2)},
	},
	"yellow",
	array[] of {5,5,6,5}),
Shape(
	# ##
	#  ##
	array[] of {
		array[] of {Point(0,0), Point(1,0), Point(1,1), Point(2,1)},
		array[] of {Point(1,0), Point(0,1), Point(1,1), Point(0,2)},
	},
	"green",
	array[] of {6,7}),
Shape(
	#  ##
	# ##
	array[] of {
		array[] of {Point(1,0), Point(2,0), Point(0,1), Point(1,1)},
		array[] of {Point(0,0), Point(0,1), Point(1,1), Point(1,2)},
	},
	"blue",
	array[] of {6,7}),
Shape(
	# ###
	# #
	array[] of {
		array[] of {Point(2,0), Point(0,1), Point(1,1), Point(2,1)},
		array[] of {Point(0,0), Point(0,1), Point(0,2), Point(1,2)},
		array[] of {Point(0,0), Point(1,0), Point(2,0), Point(0,1)},
		array[] of {Point(0,0), Point(1,0), Point(1,1), Point(1,2)},
	},
	CYAN,
	array[] of {6,7,6,7}),
Shape(
	# #
	# ###
	array[] of {
		array[] of {Point(0,0), Point(1,0), Point(2,0), Point(2,1)},
		array[] of {Point(1,0), Point(1,1), Point(0,2), Point(1,2)},
		array[] of {Point(0,0), Point(0,1), Point(1,1), Point(2,1)},
		array[] of {Point(0,0), Point(1,0), Point(0,1), Point(0,2)},
	},
	VIOLET,
	array[] of {6,7,6,7}
),
};

