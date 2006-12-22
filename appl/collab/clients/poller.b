implement Poller;

include "sys.m";
	sys: Sys;

include "draw.m";
	draw: Draw;
	Rect, Point: import draw;

include "tk.m";
	tk: Tk;

include "tkclient.m";
	tkclient: Tkclient;

include "dialog.m";
	dialog: Dialog;

include "arg.m";

Poller: module
{
	init:	fn(nil: ref Draw->Context, nil: list of string);
};

Maxanswer: con 4;	# Tk below isn't parametrised, but could be

contents := array[] of {
	"frame .f",
	"frame .f.n",
	"label .f.l -anchor nw -text {Number of answers: }",
	"radiobutton .f.n.a2 -text {2} -variable nanswer -value 2",
	"radiobutton .f.n.a3 -text {3} -variable nanswer -value 3",
	"radiobutton .f.n.a4 -text {4} -variable nanswer -value 4",
	"pack .f.n.a2 .f.n.a3 .f.n.a4 -side left",

	"frame .f.b",
	"button .f.b.start -text {Start} -command {send cmd start}",
	"button .f.b.stop -text {Stop} -state disabled -command {send cmd stop}",
	"pack .f.b.start .f.b.stop -side left",

	"canvas .f.c -height 230 -width 200",

	"pack .f.l -side top -fill x",
	"pack .f.n -side top -fill x",
	"pack .f.b -side top -fill x -expand 1",
	"pack .f.c -side top -pady 2",
	"pack .f -side top -fill both -expand 1",
};

dbcontents := array[] of {
	"text .f.t -state disabled -wrap word -height 4h -yscrollcommand {.f.sb set}",	# message log
	"scrollbar .f.sb -orient vertical -command {.f.t yview}",
	"pack .f.sb -side left -fill y",
	"pack .f.t -side left -fill both",
};

Bar: adt {
	frame:	ref Tk->Toplevel;
	canvas:	string;
	border:	string;
	inside:	string;
	label:	string;
	r:	Rect;
	v:	real;

	draw:	fn(nil: self ref Bar);
};

usage()
{
	sys->fprint(sys->fildes(2), "usage: poller [-d] [servicedir] pollname\n");
	raise "fail:usage";
}

init(ctxt: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	draw = load Draw Draw->PATH;
	tk = load Tk Tk->PATH;
	tkclient = load Tkclient Tkclient->PATH;
	dialog = load Dialog Dialog->PATH;

	arg := load Arg Arg->PATH;
	if(arg == nil){
		sys->fprint(sys->fildes(2), "poller: can't load %s: %r\n", Arg->PATH);
		raise "fail:load";
	}
	arg->init(args);
	debug := 0;
	while((ch := arg->opt()) != 0)
		case ch {
		'd' =>
			debug = 1;
		* =>
			usage();
		}
	args = arg->argv();
	arg = nil;
	if(len args < 1)
		usage();
	sys->pctl(Sys->NEWPGRP, nil);

	servicedir := "/n/remote/services";
	if(len args == 2)
		(servicedir, args) = (hd args, tl args);
	pollname := hd args;

	(cfd, dir, emsg) := opensvc(servicedir, "mpx", pollname);
	if(cfd == nil){
		sys->fprint(sys->fildes(2), "poller: can't access polling station %s: %s\n", pollname, emsg);
		raise "fail:error";
	}
	fd := sys->open(dir+"/root", Sys->ORDWR);
	if(fd == nil){
		sys->fprint(sys->fildes(2), "poller: can't open %s/root: %r\n", dir);
		raise "fail:open";
	}

	tkclient->init();
	dialog->init();
	(frame, wmctl) := tkclient->toplevel(ctxt, nil, sys->sprint("Poller: %s", pollname), Tkclient->Appl);
	cmd := chan of string;
	tk->namechan(frame, cmd, "cmd");
	tkcmds(frame, contents);
	if(debug)
		tkcmds(frame, dbcontents);
	tkcmd(frame, "pack propagate . 0");
	fittoscreen(frame);
	tk->cmd(frame, "update");
	tkclient->onscreen(frame, nil);
	tkclient->startinput(frame, "kbd"::"ptr"::nil);

	bars := mkbars(frame, ".f.c", Maxanswer);
	count: array of int;

	in := chan of string;
	spawn reader(fd, in);
	first := 1;
	qno := 0;
	nanswer := 0;
	opt := 0;
	total := 0;
	for(;;)
		alt{
		s := <-frame.ctxt.kbd =>
			tk->keyboard(frame, s);
		s := <-frame.ctxt.ptr =>
			tk->pointer(frame, *s);
		s := <-frame.ctxt.ctl or
		s = <-frame.wreq or
		s = <-wmctl =>
			tkclient->wmctl(frame, s);

		c := <-cmd =>
			if(fd == nil){
				dialog->prompt(ctxt, frame.image, "error -fg red", "Error", "Lost connection to polling station", 0, "Dismiss"::nil);
				break;
			}
			case c {
			"start" =>
				s := tkcmd(frame, "variable nanswer");
				if(s == nil || s[0] == '!'){
					dialog->prompt(ctxt, frame.image, "error -fg red", "Error", "Please select number of answers", 0, "Ok"::nil);
					break;
				}
				nanswer = int s;
				count = array[Maxanswer] of {* => 0};
				total = 0;
				qno++;
				#opt = (int tkcmd(frame, "variable none") << 1) | int tkcmd(frame, "variable all");
				tkcmd(frame, ".f.b.start configure -state disabled");
				tkcmd(frame, ".f.b.stop configure -state normal");
				if(sys->fprint(fd, "poll %d %d %d", qno, nanswer, opt) <= 0)
					sys->fprint(sys->fildes(2), "poller: write error: %r\n");
			"stop" =>
				tkcmd(frame, ".f.b.stop configure -state disabled");
				tkcmd(frame, "update");
				if(sys->fprint(fd, "stop %d", qno) <= 0)
					sys->fprint(sys->fildes(2), "poller: write error: %r\n");
				# stop ...
				tkcmd(frame, ".f.b.start configure -state normal");
			}
			tk->cmd(frame, "update");

		s := <-in =>
			if(s != nil){
				if(debug){
					t := s;
					if(!first)
						t = "\n"+t;
					first = 0;
					tkcmd(frame, ".f.t insert end '" + t);
					tkcmd(frame, ".f.t see end");
					tkcmd(frame, "update");
				}
				r := getresult(s, qno);
				if(r < 0)
					break;
				if(r >= 0 && r < len count){
					count[r]++;
					total++;
					for(i:=0; i < len count; i++){
						bars[i].v = real count[i]/real total;
						bars[i].draw();
					}
					tk->cmd(frame, "update");
				}
				#sys->print("%d %d\n", qno, r);
			}else
				fd = nil;
		}
}

mkbars(t: ref Tk->Toplevel, canvas: string, nbars: int): array of ref Bar
{
	x := 0;
	a := array[nbars] of ref Bar;
	for(i := 0; i < nbars; i++){
		b := ref Bar(t, canvas, nil, nil, nil, Rect((x,2),(x+20,202)), 0.0);
		b.border = tkcmd(t, sys->sprint("%s create rectangle %d %d %d %d",
			canvas, b.r.min.x,b.r.min.y,b.r.max.x,b.r.max.y));
		r := b.r.inset(1);
		b.inside = tkcmd(t, sys->sprint("%s create rectangle %d %d %d %d -fill red",
			canvas, r.max.x, r.max.y,r.max.x,r.max.y));
		b.label = tkcmd(t, sys->sprint("%s create text %d %d -justify center -anchor n -text '0%%",
			canvas, (r.min.x+r.max.x)/2, r.max.y+4));
		a[i] = b;
		x += 50;
	}
	tk->cmd(t, "update");
	return a;
}

Bar.draw(b: self ref Bar)
{
	r := b.r.inset(2);
	y := r.max.y - int (b.v * real r.dy());
	tkcmd(b.frame, sys->sprint("%s coords %s %d %d %d %d",
		b.canvas, b.inside, r.min.x, y, r.max.x, r.max.y));
	tkcmd(b.frame, sys->sprint("%s itemconfigure %s -text '%.0f%%",
		b.canvas, b.label, b.v*100.0));
}

getresult(msg: string, qno: int): int
{
	(nf, flds) := sys->tokenize(msg, " ");
	if(nf < 5 || hd flds == "error:")
		return -1;	# not of interest
	op := hd tl tl flds;
	flds = tl tl tl flds;
	if(op != "m")
		return -1; # not a message from leaf
	if(len flds < 3)
		return -1;	# bad format
	flds = tl flds;	# ignore user name
	if(int hd flds != qno)
		return -1;	# not current question
	result := hd tl flds;
	if(result[0] >= 'A' && result[0] <= 'D')
		return result[0]-'A';
	return -1;
}
	
reader(fd: ref Sys->FD, c: chan of string)
{
	buf := array[Sys->ATOMICIO] of byte;
	while((n := sys->read(fd, buf, len buf)) > 0)
		c <-= string buf[0:n];
	if(n < 0)
		c <-= sys->sprint("error: %r");
	c <-= nil;
}

opensvc(dir: string, svc: string, name: string): (ref Sys->FD, string, string)
{
	ctlfd := sys->open(dir+"/ctl", Sys->ORDWR);
	if(ctlfd == nil)
		return (nil, nil, sys->sprint("can't open %s/ctl: %r", dir));
	if(sys->fprint(ctlfd, "%s %s", svc, name) <= 0)
		return (nil, nil, sys->sprint("can't access %s service %s: %r", svc, name));
	buf := array [32] of byte;
	sys->seek(ctlfd, big 0, Sys->SEEKSTART);
	n := sys->read(ctlfd, buf, len buf);
	if (n <= 0)
		return (nil, nil, sys->sprint("%s/ctl: protocol error: %r", dir));
	return (ctlfd, dir+"/"+string buf[0:n], nil);
}

tkcmds(t: ref Tk->Toplevel, cmds: array of string)
{
	for (i := 0; i < len cmds; i++)
		tkcmd(t, cmds[i]);
}

tkcmd(t: ref Tk->Toplevel, cmd: string): string
{
	s := tk->cmd(t, cmd);
	if (s != nil && s[0] == '!')
		sys->fprint(sys->fildes(2), "poller: tk error: %s [%s]\n", s, cmd);
	return s;
}

fittoscreen(win: ref Tk->Toplevel)
{
	if (win.image == nil || win.image.screen == nil)
		return;
	r := win.image.screen.image.r;
	scrsize := Point((r.max.x - r.min.x), (r.max.y - r.min.y));
	bd := int tkcmd(win, ". cget -bd");
	winsize := Point(int tkcmd(win, ". cget -actwidth") + bd * 2, int tkcmd(win, ". cget -actheight") + bd * 2);
	if (winsize.x > scrsize.x)
		tkcmd(win, ". configure -width " + string (scrsize.x - bd * 2));
	if (winsize.y > scrsize.y)
		tkcmd(win, ". configure -height " + string (scrsize.y - bd * 2));
	actr: Rect;
	actr.min = Point(int tkcmd(win, ". cget -actx"), int tkcmd(win, ". cget -acty"));
	actr.max = actr.min.add((int tkcmd(win, ". cget -actwidth") + bd*2,
				int tkcmd(win, ". cget -actheight") + bd*2));
	(dx, dy) := (actr.dx(), actr.dy());
	if (actr.max.x > r.max.x)
		(actr.min.x, actr.max.x) = (r.min.x - dx, r.max.x - dx);
	if (actr.max.y > r.max.y)
		(actr.min.y, actr.max.y) = (r.min.y - dy, r.max.y - dy);
	if (actr.min.x < r.min.x)
		(actr.min.x, actr.max.x) = (r.min.x, r.min.x + dx);
	if (actr.min.y < r.min.y)
		(actr.min.y, actr.max.y) = (r.min.y, r.min.y + dy);
	tkcmd(win, ". configure -x " + string actr.min.x + " -y " + string actr.min.y);
}
