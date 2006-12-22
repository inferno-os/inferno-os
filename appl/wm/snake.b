implement Snake;
include "sys.m";
	sys: Sys;
include "draw.m";
	draw: Draw;
	Display, Point, Screen, Image, Rect: import draw;
include "tk.m";
	tk: Tk;
include "tkclient.m";
	tkclient: Tkclient;
include "keyboard.m";
include "rand.m";
	rand: Rand;
include "scoretable.m";
	scoretable: Scoretable;

Snake: module{
	init: fn(ctxt: ref Draw->Context, argv: list of string);
};

Tick: adt{
	dt: int;
};

DX: con 30;
DY: con 30;
Size: int;

EMPTY, SNAKE, FOOD, CRASH: con iota;
HIGHSCOREFILE: con "/lib/scores/snake";

board: array of array of int;
win: ref Tk->Toplevel;

init(ctxt: ref Draw->Context, argv: list of string)
{
	sys = load Sys Sys->PATH;
	if (ctxt == nil) {
		sys->fprint(sys->fildes(2), "snake: no window context\n");
		raise "fail:bad context";
	}
	draw = load Draw Draw->PATH;
	tkclient = load Tkclient Tkclient->PATH;
	if(tkclient == nil){
		sys->print("sys->fildes(2), couldn't load %s: %r\n", Tkclient->PATH);
		raise "fail:bad module";
	}
	tkclient->init();
	tk = load Tk Tk->PATH;
	rand = load Rand Rand->PATH;
	if(rand == nil){
		sys->fprint(sys->fildes(2), "snake: cannot load %s: %r\n", Rand->PATH);
		raise "fail:bad module";
	}
	scoretable = load Scoretable Scoretable->PATH;
	if (scoretable != nil) {
		(ok, err) := scoretable->init(-1, readfile("/dev/user"), "snake", HIGHSCOREFILE);
		if (ok == -1) {
			sys->fprint(sys->fildes(2), "snake: cannot init scoretable: %s\n", err);
			scoretable = nil;
		}
	}

	sys->pctl(Sys->NEWPGRP, nil);
	ctlchan: chan of string;
	(win, ctlchan) = tkclient->toplevel(ctxt, nil, "Snake", Tkclient->Hide);

	tk->namechan(win, kch := chan of string, "kch");

	cmd(win, "canvas .c -bd 2 -relief ridge");
	cmd(win, "label .scoret -text Score:");
	cmd(win, "label .score -text 0");
	cmd(win, "frame .f");
	if (scoretable != nil) {
		cmd(win, "label .hight -text High:");
		cmd(win, "label .high -text 0");
		cmd(win, "pack .hight .high -in .f -side left");
	}
	cmd(win, "pack .score .scoret -in .f -side right");
	cmd(win, "pack .f -side top -fill x");
	cmd(win, "pack .c");
	cmd(win, "bind .c <Key> {send kch %s}");
	cmd(win, "bind . <ButtonRelease-1> {focus .c}");
	cmd(win, "bind .Wm_t <ButtonRelease-1> +{focus .c}");
	cmd(win, "focus .c");

	Size = int cmd(win, ".c cget -actheight") / DY;
	cmd(win, ".c configure -width " + string (Size * DX) + " -height " + string (Size * DY));

	tkclient->onscreen(win, nil);
	tkclient->startinput(win, "kbd"::"ptr"::nil);

	spawn winctl(ctlchan);
	if (len argv > 1)
		game(kch, hd tl argv);

	for(;;){
		game(kch, nil);
		cmd(win, ".c delete all");
	}
}

winctl(ctlchan: chan of string)
{
	for(;;) alt {
		s := <-win.ctxt.kbd =>
			tk->keyboard(win, s);
		s := <-win.ctxt.ptr =>
			tk->pointer(win, *s);
		s := <-win.ctxt.ctl or
		s = <-win.wreq or
		s = <-ctlchan =>
			tkclient->wmctl(win, s);
	}
}

board2s(board: array of array of int): string
{
	s := string DX + "." + string DY + ".";
	for (y := 0; y < DY; y++)
		for (x := 0; x < DX; x++)
			s[len s] = board[x][y] + '0';
	return s;
}

replayproc(replay: string, kch: chan of string, tick: chan of int, nil: ref Tick)
{
	i := 0;
	while(i < len replay){
		n := 0;
		while(i < len replay && replay[i] >= '0' && replay[i] <= '9') {
			n = n*10 + replay[i] - '0';
			i++;
		}
		for (t := 0; t < n; t++) {
			tick <-= 1;
			sys->sleep(0);
		}
		if (i == len replay)
			break;
		kch <-= string replay[i];
		i++;
	}
	tick <-= 1;
	tick <-= 0;
}

game(realkch: chan of string, replay: string)
{
	scores := scoretable->scores();
	if (scores != nil)
		cmd(win, ".high configure -text " + string (hd scores).score);
	cmd(win, ".score configure -text {0}");
	board = array[DX] of { * => array[DY] of{* => EMPTY}};

	seed := rand->rand(16r7fffffff);
	if (replay != nil) {
		seed = int replay;
		for (i := 0; i < len replay; i++)
			if (replay[i] == '.')
				break;
		if (i<len replay)
			replay = replay[i+1:];
	}
	rand->init(seed);
	p := Point(DX/2, DY/2);
	dir := Point(1, 0);
	lkey := 'r';
	snake := array[5] of Point;
	for(i := 0; i < len snake; i++){
		snake[i] = p.add(dir.mul(i));
		make(snake[i]);
	}
	placefood();
	p = p.add(dir.mul(i));
	ticki := ref Tick(100);
	realtick := chan of int;

	userkch: chan of string;
	if(replay != nil) {
		(userkch, realkch) = (realkch, chan of string);
		spawn replayproc(replay, realkch, realtick, ticki);
	} else {
		userkch = chan of string;
		spawn ticker(realtick, ticki);
	}
	cmd(win, "update");

	score := 0;
	leaveit := 0;
	paused := 0;

	log := "";
	nticks := 0;
	odir := dir;

	dummykch := chan of string;
	kch := realkch;

	dummytick := chan of int;
	tick := realtick;
	for(;;){
		alt{
		c := <-kch =>
			if(paused){
				paused = 0;
				tick = realtick;
			}
			kch = dummykch;
			ndir := dir;
			case int c{
			Keyboard->Up =>
				ndir = (0, -1);
			Keyboard->Down =>
				ndir = (0, 1);
			Keyboard->Left =>
				ndir = (-1, 0);
			Keyboard->Right =>
				ndir = (1, 0);
			'q' =>
				tkclient->wmctl(win, "exit");
			'p' =>
				paused = 1;
				tick = dummytick;
				kch = realkch;
			}
			if (!ndir.eq(dir) && !ndir.eq(dir.mul(-1))) {		# don't allow 180° turn.
				lkey = int c;
				dir = ndir;
			}
		<-tick =>
			if(!odir.eq(dir)) {
				log += string nticks;
				log[len log] = lkey;
				nticks = 0;
				odir = dir;
			}
			nticks++;
			if(leaveit){
				ns := array[len snake + 1] of Point;
				ns[0:] = snake;
				snake = ns;
				leaveit = 0;
			} else{
				destroy(snake[0]);
				snake[0:] = snake[1:];
			}
			np := snake[len snake - 2].add(dir);
			np.x = (np.x + DX) % DX;
			np.y = (np.y + DY) % DY;
			snake[len snake - 1] = np;
			wasfood := board[np.x][np.y] == FOOD;
			if(!make(np)){
				cmd(win, ".c create oval " + r2s(square(np).inset(-5)) + " -fill yellow");
				cmd(win, "update");
				if (scoretable != nil && replay == nil) {
					board[np.x][np.y] = CRASH;
					log += string nticks;
					sys->print("%d.%s\n", seed, log);
					scoretable->setscore(score, string seed + "." + log + " " + board2s(board));
				}
				ticki.dt = -1;
				while(<-tick)
					;
				sys->sleep(750);
				absorb(realkch);
				if(int <-realkch == 'q')
					tkclient->wmctl(win, "exit");
				return;
			}
			if(wasfood){
				score++;
				#if(score % 10 == 0){
				#	if(ticki.dt > 0)
				#		ticki.dt -= 5;
				#}
				cmd(win, ".score configure -text " + string score);
				leaveit = 1;
				placefood();
			}
			cmd(win, "update");
			kch = realkch;
		}
	}
}

placefood()
{
	for(;;)
		if(makefood((rand->rand(DX), rand->rand(DY))))
			return;
}

make(p: Point): int
{
	# b := board[p.x][p.y];
	if(board[p.x][p.y] == SNAKE)
		return 0;
	cmd(win, ".c create rectangle " + r2s(square(p)) +
			" -fill blue -outline {} -tags b." + string p.x + "." + string p.y);
	board[p.x][p.y] = SNAKE;
	return 1;
}

makefood(p: Point): int
{
	b := board[p.x][p.y];
	if(b == SNAKE)
		return 0;
	cmd(win, ".c create oval " + r2s(square(p).inset(-2)) +
			" -fill red -tags b." + string p.x + "." + string p.y);
	board[p.x][p.y] = FOOD;
	return 1;
}

destroy(p: Point)
{
	board[p.x][p.y] = 0;
	cmd(win, ".c delete b." + string p.x + "." + string p.y);
}

square(p: Point): Rect
{
	p = p.mul(Size);
	return (p, p.add((Size, Size)));
}

ticker(tick: chan of int, ticki: ref Tick)
{
	while((dt := ticki.dt) >= 0){
		sys->sleep(dt);
		tick <-= 1;
	}
	tick <-= 0;
}

absorb(c: chan of string)
{
	for(;;){
		alt{
		<-c =>
			;
		* =>
			return;
		}
	}
}

r2s(r: Rect): string
{
	return sys->sprint("%d %d %d %d", r.min.x, r.min.y, r.max.x, r.max.y);
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

cmd(win: ref Tk->Toplevel, s: string): string
{
	r := tk->cmd(win, s);
	if(len r > 0 && r[0] == '!'){
		sys->print("error executing '%s': %s\n", s, r[1:]);
	}
	return r;
}
