implement Connect;

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

Connect: module 
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
		fatal("wm not running");
	display = ctxt.display;
	tkclient->init();
	(win, wmcmd) := tkclient->toplevel(ctxt, "", "Connect", Tkclient->Resize | Tkclient->Hide);
	mainwin = win;
	sys->pctl(Sys->NEWPGRP, nil);
	cmdch := chan of string;
	tk->namechan(win, cmdch, "cmd");
	for(i := 0; i < len win_config; i++)
		cmd(win, win_config[i]);
	pid := -1;
	sync := chan of int;
	mvch := chan of (int, int);
	initboard();
	setimage();
	spawn game(sync, mvch);
	pid = <- sync;
	tkclient->onscreen(win, nil);
	tkclient->startinput(win, "kbd"::"ptr"::nil);

	for(;;){
		alt{
			s := <-win.ctxt.kbd =>
				tk->keyboard(win, s);
			s := <-win.ctxt.ptr =>
				tk->pointer(win, *s);
			c := <-win.ctxt.ctl or
			c = <-win.wreq or
			c = <-wmcmd =>
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
							mvch <-= (int hd tl toks, int hd tl tl toks) => ;
							* => ;
						}
					"bh" or "bm" or "wh" or "wm" =>
						colour := BLACK;
						knd := HUMAN;
						if((hd toks)[0] == 'w')
							colour = WHITE;
						if((hd toks)[1] == 'm')
							knd = MACHINE;
						kind[colour] = knd;
					"blev" or "wlev" =>
						colour := BLACK;
						e := "be";
						if((hd toks)[0] == 'w'){
							colour = WHITE;
							e = "we";
						}
						sk := int cmd(win, ".f0." + e + " get");
						if(sk > MAXPLIES)
							sk = MAXPLIES;
						if(sk >= 0)
							skill[colour] = sk;
					* =>
						;
				}
			<- sync =>
				pid = -1;
				# exit;
				spawn game(sync, mvch);
				pid = <- sync;
		}
	}
}

WIDTH: con 400;
HEIGHT: con 400;

SZW: con 7;
SZH: con 6;
SZC: con 4;
SZS: con 1024;
PIECES: con SZW*SZH;

BLACK, WHITE, EMPTY: con iota;
MACHINE, HUMAN: con iota;
SKILLB : con 8;
SKILLW : con 0;
MAXPLIES: con 10;

board: array of array of int;	# for display
brd: array of array of int;		# for calculations
col: array of int;
pieces: array of int;
val: array of int;
kind: array of int;
skill: array of int;
name: array of string;
lines: array of array of int;
line: array of array of list of int;

mainwin: ref Toplevel;
brdimg: ref Image;
brdr: Rect;
brdx, brdy: int;

black, white, bg: ref Image;

movech: chan of (int, int);

setimage()
{
	brdw := int tk->cmd(mainwin, ".p cget -actwidth");
	brdh := int tk->cmd(mainwin, ".p cget -actheight");
	brdr = Rect((0,0), (brdw, brdh));
	brdimg = display.newimage(brdr, display.image.chans, 0, Draw->White);
	if(brdimg == nil)
		fatal("not enough image memory");
	tk->putimage(mainwin, ".p", brdimg, nil);
}

game(sync: chan of int, mvch: chan of (int, int))
{
	sync <-= sys->pctl(0, nil);
	movech = mvch;
	initbrd();
	play();
	sync <-= 0;
}

initboard()
{
	i, j, k: int;

	board = array[SZW] of array of int;
	brd = array[SZW] of array of int;
	line = array[SZW] of array of list of int;
	col = array[SZW] of int;
	for(i = 0; i < SZW; i++){
		board[i] = array[SZH] of int;
		brd[i] = array[SZH] of int;
		line[i] = array[SZH] of list of int;
	}
	pieces = array[2] of int;
	val = array[2] of int;
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
	bg = display.color(Draw->Yellow);
	n := SZW*(SZH-SZC+1)+SZH*(SZW-SZC+1)+2*(SZH-SZC+1)*(SZW-SZC+1);
	lines = array[n] of array of int;
	for(i = 0; i < n; i++)
		lines[i] = array[2] of int;
	m := 0;
	for(i = 0; i < SZW; i++){
		for(j = 0; j <= SZH-SZC; j++){
			for(k = 0; k < SZC; k++){
				line[i][j+k] = m :: line[i][j+k];
			}
			m++;
		}
	}
	for(i = 0; i < SZH; i++){
		for(j = 0; j <= SZW-SZC; j++){
			for(k = 0; k < SZC; k++){
				line[j+k][i] = m :: line[j+k][i];
			}
			m++;
		}
	}
	for(i = 0; i <= SZW-SZC; i++){
		for(j = 0; j <= SZH-SZC; j++){
			for(k = 0; k < SZC; k++){
				line[i+k][j+k] = m :: line[i+k][j+k];
			}
			m++;
		}
	}
	for(i = 0; i <= SZW-SZC; i++){
		for(j = 0; j <= SZH-SZC; j++){
			for(k = 0; k < SZC; k++){
				line[SZW-1-i-k][j+k] = m :: line[SZW-1-i-k][j+k];
			}
			m++;
		}
	}
	if(m != n)
		fatal(sys->sprint("%d != %d\n", m, n));		
}

initbrd()
{
	i, j: int;

	for(i = 0; i < SZW; i++){
		col[i] = 0;
		for(j = 0; j < SZH; j++)
			board[i][j] = brd[i][j] = EMPTY;
	}
	pieces[BLACK] = pieces[WHITE] = 0;
	val[BLACK] = val[WHITE] = 0;
	drawboard();
	n := len lines;
	for(i = 0; i < n; i++)
		lines[i][0] = lines[i][1] = 0;
}

plays := 0;
bwins := 0;
wwins := 0;

play()
{
	if(plays&1)
		(first, second) := (WHITE, BLACK);
	else
		(first, second) = (BLACK, WHITE);
	for(;;){
		if(pieces[BLACK]+pieces[WHITE] == PIECES)
			break;
		m1 := move(first, second);
		if(printout)
			sys->print("%s: %d %d %d\n", name[first], m1, val[BLACK], val[WHITE]);
		if(win(first))
			break;
		if(pieces[BLACK]+pieces[WHITE] == PIECES)
			break;
		m2 := move(second, first);
		if(printout)
			sys->print("%s: %d %d %d\n", name[second], m2, val[BLACK], val[WHITE]);
		if(win(second))
			break;
	}
	if(win(BLACK)){
		bwins++;
		puts("black wins");
		highlight(BLACK);
	}
	else if(win(WHITE)){
		wwins++;
		puts("white wins");
		highlight(WHITE);
	}
	else
		puts("draw");
	sleep(2500);
	plays++;
	puts(sys->sprint("black %d:%d white", bwins, wwins));
	sleep(2500);
	if(printout)
		sys->print("\n");
}

move(me: int, you: int): int
{
	if(kind[me] == MACHINE){
		puts("machine " + name[me] + " move");
		return genmove(me, you);
	}
	else{
		m, n: int;

		# mvs := findmoves();
		for(;;){
			puts("human " + name[me] + " move");
			m = getmove();
			if(m < 0 || m >= SZW)
				continue;
			n = col[m];
			valid := n >= 0 && n < SZH;
			if(valid && brd[m][n] != EMPTY)
				fatal("! EMPTY");
			if(valid)
				break;
			puts("illegal move");
			sleep(2500);
		}
		makemove(m, n, me, you, 0);
		return m*SZS+n;
	}
}

genmove(me: int, you: int): int
{
	m, n, v: int;

	mvs := findmoves();
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
		visits = leaves = 0;
		(v, (m, n)) = minimax(me, you, plies, ∞);
		if(0){
			while(mvs != nil){
				v0: int;
				(a, b) := hd mvs;
				makemove(a, b, me, you, 1);
				(v0, (m, n)) = minimax(you, me, plies-1, ∞);
				sys->print("	(%d, %d): %d\n", a, b, -v0);
				undomove(a, b, me, you);
				mvs = tl mvs;
			}
			sys->print("best move is %d, %d\n", m, n);
			kind[WHITE] = HUMAN;
		}
		if(auto)		
			sys->print("eval = %d plies=%d goes=%d visits=%d\n", v, plies, len mvs, leaves);
	}
	makemove(m, n, me, you, 0);
	return m*SZS+n;
}

findmoves(): list of (int, int)
{
	mvs: list of (int, int);

	for(i := 0; i < SZW; i++){
		if((j := col[i]) < SZH)
			mvs = (i, j) :: mvs;
	}
	return mvs;
}

makemove(m: int, n: int, me: int, you: int, gen: int)
{
	pieces[me]++;
	brd[m][n] = me;
	col[m]++;
	for(l := line[m][n]; l != nil; l = tl l){
		i := hd l;
		a := lines[i][me];
		b := lines[i][you];
		lines[i][me]++;
		if(a+b >= SZC)
			fatal("makemove a+b");
		if(b == 0){
			val[me] += 2*a+1;
			if(a == SZC-1)
				val[me] += WIN;
		}
		else if(a == 0)
			val[you] -= b*b;
	}
	if(!gen){
		board[m][n] = me;
		drawpiece(m, n, me);
		panelupdate();
		# sleep(1000);
	}
}

undomove(m: int, n: int, me: int, you: int)
{
	brd[m][n] = EMPTY;
	pieces[me]--;
	col[m]--;
	for(l := line[m][n]; l != nil; l = tl l){
		i := hd l;
		a := lines[i][me];
		b := lines[i][you];
		lines[i][me]--;
		if(a == 0 || a+b > SZC)
			fatal("undomove a+b");
		if(b == 0){
			val[me] -= 2*a-1;
			if(a == SZC)
				val[me] -= WIN;
		}
		else if(a == 1)
			val[you] += b*b;
	}
}

win(me: int): int
{
	return val[me] > WIN/2;
}

highlight(me: int)
{
	n := len lines;
	for(i := 0; i < n; i++){
		if(lines[i][me] == SZC){
			for(j := 0; j < SZW; j++){
				for(k := 0; k < SZH; k++){
					for(l := line[j][k]; l != nil; l = tl l){
						if(i == hd l)
							highpiece(j, k, board[j][k]);
					}
				}
			}
		}
	}
}

getmove(): int
{
	(x, nil) := <- movech;
	return x/brdx;
}

drawboard()
{
	brdx = brdr.dx()/SZW;
	brdy = brdr.dy()/SZH;
	brdimg.draw(brdr, bg, nil, (0, 0));
	for(i := 1; i < SZW; i++)
		drawline(lmap(i, 0), lmap(i, SZH), nil);
	for(j := 1; j < SZH; j++)
		drawline(lmap(0, j), lmap(SZW, j), nil);
	for(i = 0; i < SZW; i++){
		for(j = 0; j < SZH; j++){
			if (board[i][j] == BLACK || board[i][j] == WHITE)
				drawpiece(i, j, board[i][j]);
		}
	}
	panelupdate();
}

drawpiece(m, n, p: int)
{
	if(p == BLACK)
		src := black;
	else if(p == WHITE)
		src = white;
	else
		src = bg;
	brdimg.fillellipse(cmap(m, n), 3*brdx/8, 3*brdy/8, src, (0, 0));
}

highpiece(m, n, p: int)
{
	if(p == BLACK)
		src := white;
	else if(p == WHITE)
		src = black;
	else
		src = bg;
	pt := cmap(m, n);
	rx := (3*brdx/8, 0);
	ry := (0, 3*brdy/8);
	drawline(pt.add(rx), pt.sub(rx), src);
	drawline(pt.add(ry), pt.sub(ry), src);
}

panelupdate()
{
	tk->cmd(mainwin, sys->sprint(".p dirty %d %d %d %d", brdr.min.x, brdr.min.y, brdr.max.x, brdr.max.y));
	tk->cmd(mainwin, "update");
}

drawline(p0, p1: Point, c: ref Image)
{
	if(c == nil)
		c = black;
	brdimg.line(p0, p1, Draw->Endsquare, Draw->Endsquare, 0, c, (0, 0));
}

cmap(m, n: int): Point
{
	return brdr.min.add((m*brdx+brdx/2, (SZH-1-n)*brdy+brdy/2));
}

lmap(m, n: int): Point
{
	return brdr.min.add((m*brdx, n*brdy));
}

∞: con (1<<30);
WIN: con (1<<20);
MAXVISITS: con 1024;

visits, leaves : int;

minimax(me: int, you: int, plies: int, αβ: int): (int, (int, int))
{
	v: int;

	if(plies == 0){
		visits++;
		leaves++;
		if(visits == MAXVISITS){
			visits = 0;
			sys->sleep(0);
		}
		return (eval(me, you), (0, 0));
	}
	mvs := findmoves();
	if(mvs == nil){
		fatal("mvs==nil");
		# if(mv)
		# 	(v, nil) := minimax(you, me, plies, ∞);
		# else
		#	(v, nil) = minimax(you, me, plies-1, ∞);
		# return (-v, (0, 0));
	}
	bestv := -∞;
	bestm := (0, 0);
	e := 0;
	for(; mvs != nil; mvs = tl mvs){
		(m, n) := hd mvs;
		makemove(m, n, me, you, 1);
		if(win(me))
			v = eval(me, you);
		else{
			(v, nil) = minimax(you, me, plies-1, -bestv);
			v = -v;
		}
		undomove(m, n, me, you);
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
	return val[me]-val[you];
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
		sys->fprint(stderr, "connect: tk error on '%s': %s\n", s, e);
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
					
win_config := array[] of {
	"frame .f",
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

	"frame .f0",
	"label .f0.bl -text {Black level}",
	"label .f0.wl -text {White level}",
	"entry .f0.be -width 32",
	"entry .f0.we -width 32",
	".f0.be insert 0 {" + string SKILLB+"}",
	".f0.we insert 0 {" + string SKILLW+"}",
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
	# "bind .c <ButtonRelease-1> {send cmd b1r %x %y}",
	# "bind .c <ButtonRelease-2> {send cmd b2r %x %y}",
	# "bind .c <ButtonRelease-3> {send cmd b3r %x %y}",
	"bind .f0.be <Key-\n> {send cmd blev}",
	"bind .f0.we <Key-\n> {send cmd wlev}",
	"update",
};
