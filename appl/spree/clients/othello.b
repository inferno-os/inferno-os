implement Othello;
include "sys.m";
	sys: Sys;
include "draw.m";
	draw: Draw;
	Point, Rect: import draw;
include "tk.m";
	tk: Tk;
include "tkclient.m";
	tkclient: Tkclient;

SQ: con 30;		# Square size in pixels
N: con 8;

stderr: ref Sys->FD;

Othello: module {
	init:   fn(ctxt: ref Draw->Context, argv: list of string);
};

Black, White, Nocolour: con iota;
colours := array[] of {White => "white", Black => "black"};

win: ref Tk->Toplevel;
board: array of array of int;
notifypid := -1;
membername: string;
membernames := array[2] of string;

init(ctxt: ref Draw->Context, argv: list of string)
{
	sys = load Sys Sys->PATH;
	stderr = sys->fildes(2);
	draw = load Draw Draw->PATH;
	tk = load Tk Tk->PATH;
	tkclient = load Tkclient Tkclient->PATH;
	if (tkclient == nil) {
		sys->fprint(stderr, "othello: cannot load %s: %r\n", Tkclient->PATH);
		raise "fail:bad module";
	}
	tkclient->init();

	if (len argv >= 3) {		# argv: modname mnt dir ...
		membername = readfile(hd tl argv + "/name");
		sys->print("name is %s\n", membername);
	}
	client1(ctxt);
}

configcmds := array[] of {
"canvas .c -height " + string (SQ * N) + " -width " + string (SQ * N) + " -bg green",
"label .status -text {No clique in progress}",
"frame .f",
"label .f.l -text {watching} -bg white",
"label .f.turn -text {}",
"pack .f.l -side left -expand 1  -fill x",
"pack .f.turn -side left -fill x -expand 1",
"pack .c -side top",
"pack .status .f -side top -fill x",
"bind .c <ButtonRelease-1> {send cmd b1up %x %y}",
};

client1(ctxt: ref Draw->Context)
{
	cliquefd := sys->fildes(0);

	sys->pctl(Sys->NEWPGRP, nil);

	winctl: chan of string;
	(win, winctl) = tkclient->toplevel(ctxt, nil,
		"Othello", Tkclient->Appl);
	bcmd := chan of string;
	tk->namechan(win, bcmd, "cmd");
	for (i := 0; i < len configcmds; i++)
		cmd(win, configcmds[i]);

	for (i = 0; i < N; i++)
		for (j := 0; j < N; j++)
			cmd(win, ".c create rectangle " + r2s(square(i, j)));
	board = array[N] of {* => array[N] of {* => Nocolour}};
	tkclient->onscreen(win, nil);
	tkclient->startinput(win, "ptr"::"kbd"::nil);
	spawn updateproc(cliquefd);

	for (;;) alt {
	c := <-bcmd =>
		(n, toks) := sys->tokenize(c, " ");
		case hd toks {
		"b1up" =>
			(inboard, x, y) := boardpos((int hd tl toks, int hd tl tl toks));
			if (!inboard)
				break;
			othellocmd(cliquefd, "move " + string x + " " + string y);
			cmd(win, "update");
		}
	s := <-win.ctxt.kbd =>
		tk->keyboard(win, s);
	s := <-win.ctxt.ptr =>
		tk->pointer(win, *s);
	s := <-win.ctxt.ctl or
	s = <-win.wreq or
	s = <-winctl =>
		if (s == "exit")
			sys->write(cliquefd, array[0] of byte, 0);
		tkclient->wmctl(win, s);
	}
}

othellocmd(fd: ref Sys->FD, s: string): int
{
	if (sys->fprint(fd, "%s\n", s) == -1) {
		notify(sys->sprint("%r"));
		return 0;
	}
	return 1;
}

updateproc(cliquefd: ref Sys->FD)
{
	buf := array[Sys->ATOMICIO] of byte;
	while ((n := sys->read(cliquefd, buf, len buf)) > 0) {
		(nil, lines) := sys->tokenize(string buf[0:n], "\n");
		for (; lines != nil; lines = tl lines)
			applyupdate(hd lines);
		cmd(win, "update");
	}
	if (n < 0)
		sys->fprint(stderr, "othello: error reading updates: %r\n");
	sys->fprint(stderr, "othello: updateproc exiting\n");
}

applyupdate(s: string)
{
	(nt, toks) := sys->tokenize(s, " ");
	case hd toks {
	"create" =>
		; # ignore - there's only one object (the board)
	"set" =>
		# set objid attr val
		toks = tl tl toks;
		(attr, val) := (hd toks, hd tl toks);
		case attr {
		"members" =>
			membernames[Black] = hd tl toks;
			membernames[White] = hd tl tl toks;
			status(membernames[Black]+ "(Black) vs. " + string membernames[White] + "(White)");
			if (membername == membernames[Black])
				cmd(win, ".f.l configure -text Black");
			else if (membername == membernames[White])
				cmd(win, ".f.l configure -text White");
		"turn" =>
			turn := int val;
			if (turn != Nocolour) {
				if (membername == membernames[turn])
					cmd(win, ".f.turn configure -text {(Your turn)}");
				else if (membername == membernames[!turn])
					cmd(win, ".f.turn configure -text {}");
			}
		"winner" =>
			text := "it was a draw";
			winner := int val;
			if (winner != Nocolour)
				text = colours[int val] + " won.";
			status("clique over. " + text);
			cmd(win, ".f.l configure -text {watching}");
		* =>
			(x, y) := (attr[0] - 'a', attr[1] - 'a');
			set(x, y, int val);
		}
	* =>
		sys->fprint(stderr, "othello: unknown update message '%s'\n", s);
	}
}

status(s: string)
{
	cmd(win, ".status configure -text '" + s);
}

itemopts(colour: int): string
{
	return "-fill " + colours[colour] +
		" -outline " + colours[!colour];
}

set(x, y, colour: int)
{
	id := piece(x, y);
	if (colour == Nocolour)
		cmd(win, ".c delete " + id);
	else if (board[x][y] != Nocolour)
		cmd(win, ".c itemconfigure " + id + " " + itemopts(colour));
	else
		cmd(win, ".c create oval " + r2s(square(x, y)) + " " +
			itemopts(colour) +
			" -tags {piece " + id + "}");
	board[x][y] = colour;
}

notify(s: string)
{
	kill(notifypid);
	sync := chan of int;
	spawn notifyproc(s, sync);
	notifypid = <-sync;
}

notifyproc(s: string, sync: chan of int)
{
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

boardpos(p: Point): (int, int, int)
{
	(x, y) := (p.x / SQ, p.y / SQ);
	if (x < 0 || x > N - 1 || y < 0 || y > N - 1)
		return (0, 0, 0);
	return (1, x, y);
}

square(x, y: int): Rect
{
	return ((SQ*x, SQ*y), (SQ*(x + 1), SQ*(y + 1)));
}

piece(x, y: int): string
{
	return "p" + string x + "." + string y;
}

cmd(top: ref Tk->Toplevel, s: string): string
{
	e := tk->cmd(top, s);
	if (e != nil && e[0] == '!')
		sys->fprint(stderr, "tk error %s on '%s'\n", e, s);
	return e;
}

r2s(r: Rect): string
{
	return sys->sprint("%d %d %d %d", r.min.x, r.min.y, r.max.x, r.max.y);
}

kill(pid: int)
{
	if ((fd := sys->open("/prog/"+string pid+"/ctl", Sys->OWRITE)) != nil)
		sys->write(fd, array of byte "kill", 4);
}

readfile(f: string): string
{
	if ((fd := sys->open(f, Sys->OREAD)) == nil)
		return nil;
	a := array[8192] of byte;
	n := sys->read(fd, a, len a);
	if (n <= 0)
		return nil;
	return string a[0:n];
}

