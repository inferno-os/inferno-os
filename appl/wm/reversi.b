implement Reversi;

#
# Copyright © 2000 Vita Nuova Limited. All rights reserved.
#

include "sys.m";
	sys: Sys;
include "draw.m";
	draw: Draw;
	Point, Rect, Image, Font, Context, Screen, Display: import draw;
include "tk.m";
	tk: Tk;
	Toplevel: import tk;
include "tkclient.m";
	tkclient: Tkclient;
include "daytime.m";
	daytime: Daytime;
include "rand.m";
	rand: Rand;

# adtize and modularize

stderr: ref Sys->FD;

Reversi: module 
{
	init: fn(ctxt: ref Draw->Context, argv: list of string);
};

nosleep, printout, auto: int;
display: ref Draw->Display;

init(ctxt: ref Draw->Context, argv: list of string)
{
	sys = load Sys Sys->PATH;
	draw = load Draw Draw->PATH;
	tk = load Tk Tk->PATH;
	tkclient = load Tkclient Tkclient->PATH;
	tkclient->init();
	daytime = load Daytime Daytime->PATH;
	rand = load Rand Rand->PATH;

	argv = tl argv;
	while(argv != nil){
		s := hd argv;
		if(s != nil && s[0] == '-'){
			for(i := 1; i < len s; i++){
				case s[i]{
					'a' => auto = 1;
					'p' => printout = 1;
					's' => nosleep = 1;
				}
			}
		}
		argv = tl argv;
	}
	stderr = sys->fildes(2);
	rand->init(daytime->now());
	daytime = nil;

	if(ctxt == nil)
		ctxt = tkclient->makedrawcontext();
	display = ctxt.display;
	(win, wmctl) := tkclient->toplevel(ctxt, "", "Reversi", Tkclient->Resize | Tkclient->Hide);
	mainwin = win;
	sys->pctl(Sys->NEWPGRP, nil);
	cmdch := chan of string;
	tk->namechan(win, cmdch, "cmd");
	for(i := 0; i < len win_config; i++)
		cmd(win, win_config[i]);
	fittoscreen(win);
	pid := -1;
	sync := chan of int;
	mvch := chan of (int, int, int);
	initboard();
	setimage();
	spawn game(sync, mvch, 0);
	pid = <- sync;
	tkclient->onscreen(win, nil);
	tkclient->startinput(win, "kbd"::"ptr"::nil);
	lasts := 1;
	for(;;){
		alt{
			s := <-win.ctxt.kbd =>
				tk->keyboard(win, s);
			s := <-win.ctxt.ptr =>
				tk->pointer(win, *s);
			s := <-win.ctxt.ctl or
			s = <-win.wreq =>
				tkclient->wmctl(win, s);
			c := <- wmctl =>
				case c{
					"exit" =>
						if(pid != -1)
							kill(pid);
						exit;
					* =>
						e := tkclient->wmctl(win, c);
						if(e == nil && c[0] == '!'){
							setimage();
							drawboard();
						}
				}
			c := <- cmdch =>
				(nil, toks) := sys->tokenize(c, " ");
				case hd toks{
					"b1" or "b2" or "b3" =>
						alt{
							mvch <-= (SQUARE, int hd tl toks, int hd tl tl toks) => lasts = 1;
							* => ;
						}
					"bh" or "bm" or "wh" or "wm" =>
						col := BLACK;
						knd := HUMAN;
						if((hd toks)[0] == 'w')
							col = WHITE;
						if((hd toks)[1] == 'm')
							knd = MACHINE;
						kind[col] = knd;
					"blev" or "wlev" =>
						col := BLACK;
						e := "be";
						if((hd toks)[0] == 'w'){
							col = WHITE;
							e = "we";
						}
						sk := int cmd(win, ".f0." + e + " get");
						if(sk > MAXPLIES)
							sk = MAXPLIES;
						if(sk >= 0)
							skill[col] = sk;
					"last" =>
						alt{
							mvch <-= (REPLAY, lasts, 0) => lasts++;
							* => ;
						}
					* =>
						;
				}
			<- sync =>
				pid = -1;
				# exit;
				spawn game(sync, mvch, 0);
				pid = <- sync;
		}
	}
}

SQUARE, REPLAY: con iota;

WIDTH: con 400;
HEIGHT: con 400;

SZB: con 8;		# must be even
SZF: con SZB+2;
MC1: con SZB/2;
MC2: con MC1+1;
PIECES: con SZB*SZB;
SQUARES: con PIECES-4;
MAXMOVES: con 3*PIECES/2;
NOMOVE: con SZF*SZF - 1;

BLACK, WHITE, EMPTY, BORDER: con iota;
MACHINE, HUMAN: con iota;
SKILLB : con 6;
SKILLW : con 0;
MAXPLIES: con 6;

moves: array of int;
board: array of array of int;	# for display
brd: array of array of int;		# for calculations
val: array of array of int;
order: array of (int, int);
pieces: array of int;
value: array of int;
kind: array of int;
skill: array of int;
name: array of string;

mainwin: ref Toplevel;
brdimg: ref Image;
brdr: Rect;
brdx, brdy: int;

black, white, green: ref Image;

movech: chan  of (int, int, int);

setimage()
{
	brdw := int tk->cmd(mainwin, ".p cget -actwidth");
	brdh := int tk->cmd(mainwin, ".p cget -actheight");
#	if (brdw > display.image.r.dx())
#		brdw = display.image.r.dx() - 4;
#	if (brdh > display.image.r.dy())
#		brdh = display.image.r.dy() - 40;

	brdr = Rect((0,0), (brdw, brdh));
	brdimg = display.newimage(brdr, display.image.chans, 0, Draw->White);
	if(brdimg == nil)
		fatal("not enough image memory");
	tk->putimage(mainwin, ".p", brdimg, nil);
}

game(sync: chan of int, mvch: chan of (int, int, int), again: int)
{
	sync <-= sys->pctl(0, nil);
	movech = mvch;
	initbrd();
	drawboard();
	if(again)
		replay(moves);
	else
		play();
	sync <-= 0;
}

ordrect()
{
	i, j : int;

	n := 0;
	for(i = 1; i <= SZB; i++){
		for(j = 1; j <= SZB; j++){
			if(i < SZB/2 || j < SZB/2 || i > SZB/2+1 || j > SZB/2+1)
				order[n++] = (i, j);
		}
	}
	for(k := 0; k < SQUARES-1; k++){
		for(l := k+1; l < SQUARES; l++){
			(i, j) = order[k];
			(a, b) := order[l];
			if(val[i][j] > val[a][b])
				(order[k], order[l]) = (order[l], order[k]);
		}
	}
}

initboard()
{
	i, j, k: int;

	moves = array[MAXMOVES+1] of int;
	board = array[SZF] of array of int;
	brd = array[SZF] of array of int;
	for(i = 0; i < SZF; i++){
		board[i] = array[SZF] of int;
		brd[i] = array[SZF] of int;
	}
	val = array[SZF] of array of int;
	s := -pow(-1, SZB/2);
	for(i = 0; i < SZF; i++){
		val[i] = array[SZF] of int;
		val[i][0] = val[i][SZF-1] = 0;
		for(j = 1; j <= SZB; j++){
			for(k = SZB/2; k > 0; k--){
				if(i == k || i == SZB+1-k || j == k || j == SZB+1-k){
					val[i][j] = s*pow(-7, SZB/2-k);
					break;
				}
			}
		}
	}
	order = array[SQUARES] of (int, int);
	ordrect();
	pieces = array[2] of int;
	value = array[2] of int;
	kind = array[2] of int;
	kind[BLACK] = MACHINE;
	if(auto)
		kind[WHITE] = MACHINE;
	else
		kind[WHITE] = HUMAN;
	skill = array[2] of int;
	skill[BLACK] = SKILLB;
	skill[WHITE] = SKILLW;
	name = array[2] of string;
	name[BLACK] = "black";
	name[WHITE] = "white";
	black = display.color(Draw->Black);
	white = display.color(Draw->White);
	green = display.color(Draw->Green);
}

initbrd()
{
	i, j: int;

	for(i = 0; i < SZF; i++)
		for(j = 0; j < SZF; j++)
			brd[i][j] = EMPTY;
	for(i = 0; i < SZF; i++)
		brd[i][0] = brd[i][SZF-1] = BORDER;
	for(j = 0; j< SZF; j++)
		brd[0][j] = brd[SZF-1][j] = BORDER;
	brd[MC1][MC1] = brd[MC2][MC2] = BLACK;
	brd[MC1][MC2] = brd[MC2][MC1] = WHITE;
	for(i = 0; i < SZF; i++)
		for(j = 0; j < SZF; j++)
			board[i][j] = brd[i][j];
	pieces[BLACK] = pieces[WHITE] = 2;
	value[BLACK] = value[WHITE] = -2;
}

plays := 0;
bscore := 0;
wscore := 0;
bwins := 0;
wwins := 0;

play()
{
	n := 0;
	for(i := 0; i <= MAXMOVES; i++)
		moves[i] = NOMOVE;
	if(plays&1)
		(first, second) := (WHITE, BLACK);
	else
		(first, second) = (BLACK, WHITE);
	if(printout)
		sys->print("%d\n", first);
	moves[n++] = first;
	m1 := m2 := 1;
	for(;;){
		if(pieces[BLACK]+pieces[WHITE] == PIECES)
			break;
		m2 = m1;
		m1 = move(first, second);
		if(printout)
			sys->print("%d\n", m1);
		moves[n++] = m1;
		if(!m1 && !m2)
			break;
		(first, second) = (second, first);
	}
	if(auto)
		sys->print("score: %d-%d\n", pieces[BLACK], pieces[WHITE]);
	bscore += pieces[BLACK];
	wscore += pieces[WHITE];
	if(pieces[BLACK] > pieces[WHITE])
		bwins++;
	else if(pieces[BLACK] < pieces[WHITE])
		wwins++;
	plays++;
	if(auto)
		sys->print("	black: %d white: %d draw: %d total: (%d-%d)\n", bwins, wwins, plays-bwins-wwins, bscore, wscore);
	puts(sys->sprint("black %d:%d white", pieces[BLACK], pieces[WHITE]));
	sleep(2000);
	puts(sys->sprint("black %d:%d white", bwins, wwins));
	sleep(2000);
}

replay(moves: array of int)
{
	n := 0;
	first := moves[n++];
	second := BLACK+WHITE-first;
	m1 := m2 := 1;
	while (pieces[BLACK]+pieces[WHITE] < PIECES){
		m2 = m1;
		m1 = moves[n++];
		if(m1 == NOMOVE)
			break;
		if(m1 != 0)
			makemove(m1/SZF, m1%SZF, first, second, 1, 0);
		if(!m1 && !m2)
			break;
		(first, second) = (second, first);
	}
	# sys->print("score: %d-%d\n", pieces[BLACK], pieces[WHITE]);
}

lastmoves(p: int, moves: array of int)
{
	initbrd();
	k := MAXMOVES+1;
	for(i := 0; i <= MAXMOVES; i++){
		if(moves[i] == NOMOVE){
			k = i;
			break;
		}
	}
	if(k-p < 1)
		p = k-1;
	for(i = k-p; i < k; i++)
		if(moves[i] == 0)
			p++;
	if(k-p < 1)
		p = k-1;
	n := 0;
	me := moves[n++];
	you := BLACK+WHITE-me;
	while(n < k-p){
		m := moves[n++];
		if(m != 0)
			makemove(m/SZF, m%SZF, me, you, 1, 1);
		(me, you) = (you, me);
	}
	for(i = 0; i < SZF; i++)
		for(j := 0; j < SZF; j++)
			board[i][j] = brd[i][j];
	drawboard();
	sleep(1000);
	while(n < k){
		m := moves[n++];
		if(m != 0)
			makemove(m/SZF, m%SZF, me, you, 1, 0);
		if(n < k)
			sleep(500);
		(me, you) = (you, me);
	}
}

move(me: int, you: int): int
{
	if(kind[me] == MACHINE){
		puts("machine " + name[me] + " move");
		m := genmove(me, you);
		if(!m){
			puts("machine " + name[me] + " cannot go");
			sleep(2000);
		}
		return m;
	}
	else{
		m, n: int;

		mvs := findmoves(me, you);
		if(mvs == nil){
			puts("human " + name[me] + " cannot go");
			sleep(2000);
			return 0;
		}
		for(;;){
			puts("human " + name[me] + " move");
			(m, n) = getmove();
			if(m < 1 || n < 1 || m > SZB || n > SZB)
				continue;
			if(brd[m][n] == EMPTY)
				(valid, nil) := makemove(m, n, me, you, 0, 0);
			else
				valid = 0;
			if(valid)
				break;
			puts("illegal move");
			sleep(2000);
		}
		makemove(m, n, me, you, 1, 0);
		return m*SZF+n;
	}
}

fullsrch: int;

genmove(me: int, you: int): int
{
	m, n, v: int;

	mvs := findmoves(me, you);
	if(mvs == nil)
		return 0;
	if(skill[me] == 0){
		l := len mvs;
		r := rand->rand(l);
		# r = 0;
		while(--r >= 0)
			mvs = tl mvs;
		(m, n) = hd mvs;
	}
	else{
		plies := skill[me];
		left := PIECES-(pieces[BLACK]+pieces[WHITE]);
		if(left < plies)		# limit search
			plies = left;
		else if(left < 2*plies)	# expand search to end
			plies = left;
		else{				# expand search nearer end of game
			k := left/plies;
			if(k < 3)
				plies = ((k+2)*plies)/(k+1);
		}
		fullsrch = plies == left;
		visits = leaves = 0;
		(v, (m, n)) = minimax(me, you, plies, ∞, 1);
		if(0){
		# if((m==2&&n==2&&brd[1][1]!=BLACK) ||
		#    (m==2&&n==7&&brd[1][8]!=BLACK) ||
		#    (m==7&&n==2&&brd[8][1]!=BLACK) ||
		#    (m==7&&n==7&&brd[8][8]!=BLACK)){
			while(mvs != nil){
				(a, b) := hd mvs;
				(nil, sqs) := makemove(a, b, me, you, 1, 1);
				(v0, nil) := minimax(you, me, plies-1, ∞, 1);
				sys->print("	(%d, %d): %d\n", a, b, v0);
				undomove(a, b, me, you, sqs);
				mvs = tl mvs;
			}
			if(!fullsrch){
				sys->print("best move is %d, %d\n", m, n);
				kind[WHITE] = HUMAN;
			}
		}
		if(auto)		
			sys->print("eval = %d plies=%d goes=%d visits=%d\n", v, plies, len mvs, leaves);
	}
	makemove(m, n, me, you, 1, 0);
	return m*SZF+n;
}

findmoves(me: int, you: int): list of (int, int)
{
	mvs: list of (int, int);

	for(k := 0; k < SQUARES; k++){
		(i, j) := order[k];
		if(brd[i][j] == EMPTY){
			(valid, nil) := makemove(i, j, me, you, 0, 0);
			if(valid)
				mvs = (i, j) :: mvs;
		}
	}
	return mvs;
}

makemove(m: int, n: int, me: int, you: int, move: int, gen: int): (int, list of (int, int))
{
	sqs: list of (int, int);

	if(move){
		pieces[me]++;
		value[me] += val[m][n];
		brd[m][n] = me;
		if(!gen){
			board[m][n] = me;
			drawpiece(m, n, me, 1);
			panelupdate();
			sleep(1000);
		}
	}
	valid := 0;
	for(i := -1; i < 2; i++){
		for(j := -1; j < 2; j++){
			if(i != 0 || j != 0){
				v: int;

				(v, sqs) = dirmove(m, n, i, j, me, you, move, gen, sqs);
				valid |= v;
				if (valid && !move)
					return (1, sqs);
			}
		}
	}
	if(!valid && move)
		fatal(sys->sprint("bad makemove call (%d, %d)", m, n));
	return (valid, sqs);
}

dirmove(m: int, n: int, dx: int, dy: int, me: int, you: int, move: int, gen: int, sqs: list of (int, int)): (int, list of (int, int))
{
	p := 0;
	m += dx;
	n += dy;
	while(brd[m][n] == you){
		m += dx;
		n += dy;
		p++;
	}
	if(p > 0 && brd[m][n] == me){
		if(move){
			pieces[me] += p;
			pieces[you] -= p;
			m -= p*dx;
			n -= p*dy;
			while(--p >= 0){
				brd[m][n] = me;
				value[me] += val[m][n];
				value[you] -= val[m][n];
				if(gen)
					sqs = (m, n) :: sqs;
				else{
					board[m][n] = me;
					drawpiece(m, n, me, 0);
					# sleep(500);
					panelupdate();
				}
				m += dx;
				n += dy;
			}
		}
		return (1, sqs);
	}
	return (0, sqs);
}			

undomove(m: int, n: int, me: int, you: int, sqs: list of (int, int))
{
	brd[m][n] = EMPTY;
	pieces[me]--;
	value[me] -= val[m][n];
	for(; sqs != nil; sqs = tl sqs){
		(x, y) := hd sqs;
		brd[x][y] = you;
		pieces[me]--;
		pieces[you]++;
		value[me] -= val[x][y];
		value[you] += val[x][y];
	}
}

getmove(): (int, int)
{
	k, x, y: int;

	(k, x, y) = <- movech;
	if(k == REPLAY){
		lastmoves(x, moves);
		return getmove();
	}
	return (x/brdx+1, y/brdy+1);
}

drawboard()
{
	brdx = brdr.dx()/SZB;
	brdy = brdr.dy()/SZB;
	brdimg.draw(brdr, green, nil, (0, 0));
	for(i := 1; i < SZB; i++)
		drawline(lmap(i, 0), lmap(i, SZB));
	for(j := 1; j < SZB; j++)
		drawline(lmap(0, j), lmap(SZB, j));
	for(i = 1; i <= SZB; i++){
		for(j = 1; j <= SZB; j++){
			if (board[i][j] == BLACK || board[i][j] == WHITE)
				drawpiece(i, j, board[i][j], 0);
		}
	}
	panelupdate();
}

drawpiece(m, n, p, flash: int)
{
	if(p == BLACK)
		src := black;
	else
		src = white;
	if(0 && flash && kind[p] == MACHINE){
		for(i := 0; i < 4; i++){
			brdimg.fillellipse(cmap(m, n), 3*brdx/8, 3*brdy/8, src, (0, 0));
			panelupdate();
			sys->sleep(250);
			brdimg.fillellipse(cmap(m, n), 3*brdx/8, 3*brdy/8, green, (0, 0));
			panelupdate();
			sys->sleep(250);
		}
	}
	brdimg.fillellipse(cmap(m, n), 3*brdx/8, 3*brdy/8, src, (0, 0));
}

panelupdate()
{
	tk->cmd(mainwin, sys->sprint(".p dirty %d %d %d %d", brdr.min.x, brdr.min.y, brdr.max.x, brdr.max.y));
	tk->cmd(mainwin, "update");
}

drawline(p0, p1: Point)
{
	brdimg.line(p0, p1, Draw->Endsquare, Draw->Endsquare, 0, brdimg.display.black, (0, 0));
}

cmap(m, n: int): Point
{
	return brdr.min.add((m*brdx-brdx/2, n*brdy-brdy/2));
}

lmap(m, n: int): Point
{
	return brdr.min.add((m*brdx, n*brdy));
}

∞: con (1<<30);
MAXVISITS: con 1024;

visits, leaves : int;

minimax(me: int, you: int, plies: int, αβ: int, mv: int): (int, (int, int))
{
	if(plies == 0){
		visits++;
		leaves++;
		if(visits == MAXVISITS){
			visits = 0;
			sys->sleep(0);
		}
		return (eval(me, you), (0, 0));
	}
	mvs := findmoves(me, you);
	if(mvs == nil){
		if(mv)
			(v, nil) := minimax(you, me, plies, ∞, 0);
		else
			(v, nil) = minimax(you, me, plies-1, ∞, 0);
		return (-v, (0, 0));
	}
	bestv := -∞;
	bestm := (0, 0);
	e := 0;
	for(; mvs != nil; mvs = tl mvs){
		(m, n) := hd mvs;
		(nil, sqs) := makemove(m, n, me, you, 1, 1);
		(v, nil) := minimax(you, me, plies-1, -bestv, 1);
		v = -v;
		undomove(m, n, me, you, sqs);
		if(v > bestv || (v == bestv && rand->rand(++e) == 0)){
			if(v > bestv)
				e = 1;
			bestv = v;
			bestm = (m, n);
			if(bestv >= αβ)
				return (∞, (0, 0));
		}
	}
	return (bestv, bestm);
}
	
eval(me: int, you: int): int
{
	d := pieces[me]-pieces[you];
	if(fullsrch)
		return d;
	n := pieces[me]+pieces[you];
	v := 0;
	for(i := 1; i <= SZB; i += SZB-1)
		for(j := 1; j <= SZB; j += SZB-1)
			v += line(i, j, me, you);
	return (PIECES-n)*(value[me]-value[you]+v) + n*d;
}

line(m: int, n: int, me: int, you: int): int
{
	if(brd[m][n] == EMPTY)
		return 0;
	dx := dy := -1;
	if(m == 1)
		dx = 1;
	if(n == 1)
		dy = 1;
	return line0(m, n, 0, dy, me, you) +
		   line0(m, n, dx, 0, me, you) +
		   line0(m, n, dx, dy, me, you);
}

line0(m: int, n: int, dx: int, dy: int, me: int, you: int): int
{
	v := 0;
	p := brd[m][n];
	i := val[1][1];
	while(brd[m][n] == p){
		v += i;
		m += dx;
		n += dy;
	}
	if(p == you)
		return -v;
	if(p == me)
		return v;
	return v;
}

pow(n: int, m: int): int
{
	p := 1;
	while(--m >= 0)
		p *= n;
	return p;
}

fatal(s: string)
{
	sys->fprint(stderr, "%s\n", s);
	exit;
}

sleep(t: int)
{
	if(nosleep)
		sys->sleep(0);
	else
		sys->sleep(t);
}

kill(pid: int): int
{
	fd := sys->open("#p/"+string pid+"/ctl", Sys->OWRITE);
	if(fd == nil)
		return -1;
	if(sys->write(fd, array of byte "kill", 4) != 4)
		return -1;
	return 0;
}

cmd(top: ref Toplevel, s: string): string
{
	e := tk->cmd(top, s);
	if (e != nil && e[0] == '!')
		sys->fprint(stderr, "reversi: tk error on '%s': %s\n", s, e);
	return e;
}

# swidth: int;
# sfont: ref Font;

# gettxtattrs()
# {
#	swidth = int cmd(mainwin, ".f1.txt cget -width");	# always initial value ?
#	f := cmd(mainwin, ".f1.txt cget -font");
#	sfont = Font.open(brdimg.display, f);
# }
	
puts(s: string)
{
	# while(sfont.width(s) > swidth)
	#	s = s[0: len s -1];
	cmd(mainwin, ".f1.txt configure -text {" + s + "}");
	cmd(mainwin, "update");
}

fittoscreen(win: ref Tk->Toplevel)
{
	Point: import draw;
	if (display.image == nil)
		return;
	r :=  display.image.r;
	scrsize := Point(r.dx(), r.dy());
	bd := int cmd(win, ". cget -bd");
	winsize := Point(int cmd(win, ". cget -actwidth") + bd * 2, int cmd(win, ". cget -actheight") + bd * 2);
	if (winsize.x > scrsize.x)
		cmd(win, ". configure -width " + string (scrsize.x - bd * 2));
	if (winsize.y > scrsize.y)
		cmd(win, ". configure -height " + string (scrsize.y - bd * 2));
	actr: Rect;
	actr.min = Point(int cmd(win, ". cget -actx"), int cmd(win, ". cget -acty"));
	actr.max = actr.min.add((int cmd(win, ". cget -actwidth") + bd*2,
				int cmd(win, ". cget -actheight") + bd*2));
	(dx, dy) := (actr.dx(), actr.dy());
	if (actr.max.x > r.max.x)
		(actr.min.x, actr.max.x) = (r.max.x - dx, r.max.x);
	if (actr.max.y > r.max.y)
		(actr.min.y, actr.max.y) = (r.max.y - dy, r.max.y);
	if (actr.min.x < r.min.x)
		(actr.min.x, actr.max.x) = (r.min.x, r.min.x + dx);
	if (actr.min.y < r.min.y)
		(actr.min.y, actr.max.y) = (r.min.y, r.min.y + dy);
	cmd(win, ". configure -x " + string actr.min.x + " -y " + string actr.min.y);
	cmd(win, "update");
}
					
win_config := array[] of {
	"frame .f",
	"button .f.last -text {last move} -command {send cmd last}",
	"menubutton .f.bk -text Black -menu .f.bk.bm",
	"menubutton .f.wk -text White -menu .f.wk.wm",
	"menu .f.bk.bm",
	".f.bk.bm add command -label Human -command { send cmd bh }",
	".f.bk.bm add command -label Machine -command { send cmd bm }",
	"menu .f.wk.wm",
	".f.wk.wm add command -label Human -command { send cmd wh }",
	".f.wk.wm add command -label Machine -command { send cmd wm }",
	"pack .f.bk -side left",
	"pack .f.wk -side right",
	"pack .f.last -side top",

	"frame .f0",
	"label .f0.bl -text {Black level}",
	"label .f0.wl -text {White level}",
	"entry .f0.be -width 32",
	"entry .f0.we -width 32",
	".f0.be insert 0 " + string SKILLB,
	".f0.we insert 0 " + string SKILLW,
	"pack .f0.bl -side left",
	"pack .f0.be -side left",
	"pack .f0.wl -side right",
	"pack .f0.we -side right",

	"frame .f1",
	"label .f1.txt -text { } -width " + string WIDTH,
	"pack .f1.txt -side top -fill x",

	"panel .p -width " + string WIDTH + " -height " + string HEIGHT,

	"pack .f -side top -fill x",
	"pack .f0 -side top -fill x",
	"pack .f1 -side top -fill x",
	"pack .p -side bottom -fill both -expand 1",
	"pack propagate . 0",

	"bind .p <Button-1> {send cmd b1 %x %y}",
	"bind .p <Button-2> {send cmd b2 %x %y}",
	"bind .p <Button-3> {send cmd b3 %x %y}",
	"bind .f0.be <Key-\n> {send cmd blev}",
	"bind .f0.we <Key-\n> {send cmd wlev}",
	"update",
};
