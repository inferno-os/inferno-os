implement Sweeper;

#
# michael@vitanuova.com
#
# Copyright © 2000 Vita Nuova Limited.  All rights reserved.
# Copyright © 2001 Vita Nuova Holdings Limited.  All rights reserved.
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

stderr: ref Sys->FD;

Sweeper: module 
{
	init: fn(ctxt: ref Draw->Context, argv: list of string);
};

mainwin: ref Toplevel;
score: int;
mines: int;

WIDTH: con 220;
HEIGHT: con 220;

EASY: con 20;
SZB: con 10;
SZI: con SZB+2;			# internal board is 2 larger than visible board

Cell: adt {
	mine, state: int;
};

board: array of array of Cell;

UNSELECTED, SELECTED, MARKED: con (1<<iota);


init(ctxt: ref Draw->Context, nil: list of string)
{
	sys = load Sys Sys->PATH;
	draw = load Draw Draw->PATH;
	tk = load Tk Tk->PATH;
	tkclient = load Tkclient Tkclient->PATH;
	daytime = load Daytime Daytime->PATH;
	rand = load Rand Rand->PATH;

	stderr = sys->fildes(2);
	rand->init(daytime->now());
	daytime = nil;

	tkclient->init();
	if(ctxt == nil)
		ctxt = tkclient->makedrawcontext();

	(win, wmcmd) := tkclient->toplevel(ctxt, "", "Mine Sweeper", Tkclient->Hide);
	mainwin = win;
	sys->pctl(Sys->NEWPGRP, nil);
	cmdch := chan of string;
	tk->namechan(win, cmdch, "cmd");
	display_board();
	pid := -1;
	finished := 0;
	init_board();
	tkclient->onscreen(win, nil);
	tkclient->startinput(win, "kbd"::"ptr"::nil);
	for (;;) {
		alt {
			s := <-win.ctxt.kbd =>
				tk->keyboard(win, s);
			s := <-win.ctxt.ptr =>
				tk->pointer(win, *s);
			c := <-win.ctxt.ctl or
			c = <-win.wreq or
			c = <- wmcmd =>	# wm commands
				case c {
					"exit" =>
						if(pid != -1)
							kill(pid);
						exit;
					* =>
						tkclient->wmctl(win, c);
				}
			c := <- cmdch =>	# tk commands
				(nil, toks) := sys->tokenize(c, " ");
				case hd toks {
					"b" =>
						x := int hd tl toks;
						y := int hd tl tl toks;
						i := board_check(x, y);
						case i {
							-1 =>
								display_mines();
								display_lost();
								finished = 1;
							0 to 8 =>
								if (finished)
									break;
								score++;
								board[x][y].state = SELECTED;
								display_square(x, y, sys->sprint("%d", i), "olive");
								if (i == 0) {  # check all adjacent zeros
									display_zeros(x, y);
								}
								display_score();
								if (score+mines == SZB*SZB) {
									display_mines();
									display_win();
									finished = 1;
								}
							* =>
								;
						}
						cmd(mainwin, "update");
					"b3" =>
						x := int hd tl toks;
						y := int hd tl tl toks;
						mark_square(x, y);
						cmd(mainwin, "update");
					"restart" =>
						init_board();
						display_score();
						reset_display();
						finished = 0;
					* =>
						sys->fprint(stderr, "%s\n", c);
				}
			}
	}
}

display_board() {
	i, j: int;
	pack: string;

	for(i = 0; i < len win_config; i++)
		cmd(mainwin, win_config[i]);

	for (i = 1; i <= SZB; i++) {
		cmd(mainwin,  sys->sprint("frame .f%d", i));
		pack = "";
		for (j = 1; j <= SZB; j++) {
			pack += sys->sprint(" .f%d.b%dx%d", i, i, j);
			cmd(mainwin, sys->sprint("button .f%d.b%dx%d -text { } -width 14 -command {send cmd b %d %d}", i, i, j, i, j));
			cmd(mainwin, sys->sprint("bind .f%d.b%dx%d <ButtonRelease-3> {send cmd b3 %d %d}", i, i, j, i, j));
		}
		cmd(mainwin, sys->sprint("pack %s -side left", pack));
		cmd(mainwin, sys->sprint("pack .f%d -side top -fill x", i));
	}

	for (i = 0; i < len win_config2; i++)
		cmd (mainwin, win_config2[i]);
}

reset_display()
{
	for (i := 1; i <= SZB; i++) {
		for (j := 1; j <= SZB; j++) {
			s := sys->sprint(".f%d.b%dx%d configure -text { } -bg #dddddd -activebackground #eeeeee", i, i, j);
			cmd(mainwin, s);
		}
	}
	cmd(mainwin, "update");
}


init_board()
{
	i, j: int;

	score = 0;
	mines = 0;
	board = array[SZI] of array of Cell;
	for (i = 0; i < SZI; i++)
		board[i] = array[SZI] of Cell;

	# initialize board
	for (i = 0; i < SZI; i++)
		for (j =0; j < SZI; j++) {
			board[i][j].mine = 0;
			board[i][j].state = UNSELECTED;
		}

	# place mines
	for (i = 0; i < EASY; i++) {
		j = rand->rand(SZB*SZB);
		if (board[(j/SZB)+1][(j%SZB)+1].mine == 0) { 	# rand could yield same result twice
			board[(j/SZB)+1][(j%SZB)+1].mine = 1;
			mines++;
		}
	}
	cmd(mainwin, "update");
}

display_score()
{
	cmd(mainwin, ".f.l configure -text {Score: "+ sys->sprint("%d", score)+ "}");
}

display_win()
{
	cmd(mainwin, ".f.l configure -text {You have Won}");
}

display_lost()
{
	cmd(mainwin, ".f.l configure -text {You have Lost}");
}

display_mines()
{
	for (i := 1; i <= SZB; i++)
		for (j := 1; j <= SZB; j++)
			if (board[i][j].mine == 1)
				display_square(i, j, "M", "red");
}

display_square(i, j: int, v: string, c: string) {
	cmd(mainwin, sys->sprint(".f%d.b%dx%d configure -text {%s} -bg %s -activebackground %s", i, i, j, v, c, c));
	cmd(mainwin, "update");
}

mark_square(i, j: int) {
	case board[i][j].state {
		UNSELECTED =>
			board[i][j].state = MARKED;
			display_square(i, j, "?", "orange");
		MARKED =>
			board[i][j].state = UNSELECTED;
			display_square(i, j, " ", "#dddddd");
	}
}

board_check(i, j: int) : int 
{
	if (board[i][j].mine == 1)
		return -1;
	if (board[i][j].state&(SELECTED|MARKED))
		return -2;
	c := 0;
	for (x := i-1; x <= i+1; x++)
		for (y := j-1; y <= j+1; y++)
			if (board[x][y].mine == 1)
				c++;
	return c;
}

display_zeros(i, j: int)
{
	for (x := i-1; x <= i+1; x++) {
		for (y := j-1; y <= j+1; y++) {
			if (x <1 || x>SZB || y<1 || y>SZB)
				continue;
			if (board_check(x, y) == 0) {
				score++;
				board[x][y].state = SELECTED;
				display_square(x, y, "0", "olive");
				display_zeros(x, y);
			}
		}
	}		
}

fatal(s: string)
{
	sys->fprint(stderr, "%s\n", s);
	exit;
}

sleep(t: int)
{
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
		sys->fprint(stderr, "sweeper: tk error on '%s': %s\n", s, e);
	return e;
}
				
win_config := array[] of {
	"frame .f -width 220 -height 220",

	"menubutton .f.sz -text Options -menu .f.sz.sm",
	"menu .f.sz.sm",
	".f.sz.sm add command -label restart -command { send cmd restart }",
	"pack .f.sz -side left",

	"label .f.l -text {Score:  }",
	"pack .f.l  -side right",

	"frame .ft",
	"label .ft.l -text {  }",
	"pack .ft.l -side left",

	"pack .f -side top -fill x",
	"pack .ft -side top -fill x",

};

win_config2 := array[] of {

	"pack propagate . 0",
	"update",
};