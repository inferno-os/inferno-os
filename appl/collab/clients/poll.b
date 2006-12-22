implement Poll;

include "sys.m";
	sys: Sys;

include "draw.m";

include "tk.m";
	tk: Tk;

include "tkclient.m";
	tkclient: Tkclient;

include "dialog.m";
	dialog: Dialog;

include "arg.m";

Poll: module
{
	init:	fn(nil: ref Draw->Context, nil: list of string);
};

Maxanswer: con 4;

contents := array[] of {
	"frame .f",
	"frame .a",
	"radiobutton .a.a1 -state disabled -variable answer -value A -text {A} -command {send entry A}",
	"radiobutton .a.a2 -state disabled -variable answer -value B -text {B} -command {send entry B}",
	"radiobutton .a.a3 -state disabled -variable answer -value C -text {C} -command {send entry C}",
	"radiobutton .a.a4 -state disabled -variable answer -value D -text {D} -command {send entry D}",
	"pack .a.a1 -side top -fill x -expand 1",
	"pack .a.a2 -side top -fill x -expand 1",
	"pack .a.a3 -side top -fill x -expand 1",
	"pack .a.a4 -side top -fill x -expand 1",
	"pack .a -side top -fill both -expand 1",
	"pack .f -side top -fill both",
};

dbcontents := array[] of {
	"text .f.t -state disabled -wrap word -yscrollcommand {.f.sb set} -height 4h",
	"scrollbar .f.sb -orient vertical -command {.f.t yview}",
	"pack .f.sb -side left -fill y",
	"pack .f.t -side left -fill both -expand 1",
};

usage()
{
	sys->fprint(sys->fildes(2), "usage: poll [-d] [servicedir] pollname\n");
	raise "fail:usage";
}

init(ctxt: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	tk = load Tk Tk->PATH;
	tkclient = load Tkclient Tkclient->PATH;
	dialog = load Dialog Dialog->PATH;

	arg := load Arg Arg->PATH;
	if(arg == nil){
		sys->fprint(sys->fildes(2), "poll: can't load %s: %r\n", Arg->PATH);
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
		sys->fprint(sys->fildes(2), "poll: can't access poll %s: %s\n", pollname, emsg);
		raise "fail:error";
	}
	fd := sys->open(dir+"/leaf", Sys->ORDWR);
	if(fd == nil){
		sys->fprint(sys->fildes(2), "poll: can't open %s/leaf: %r\n", dir);
		raise "fail:open";
	}

	tkclient->init();
	dialog->init();
	(frame, wmctl) := tkclient->toplevel(ctxt, nil, sys->sprint("Poll %s", pollname), Tkclient->Appl);
	entry := chan of string;
	tk->namechan(frame, entry, "entry");
	tkcmds(frame, contents);
	if(debug)
		tkcmds(frame, dbcontents);
	tkcmd(frame, "pack propagate . 0");
	fittoscreen(frame);
	tk->cmd(frame, "update");
	tkclient->onscreen(frame, nil);
	tkclient->startinput(frame, "kbd"::"ptr"::nil);

	in := chan of string;
	spawn reader(fd, in);
	first := 1;
	lastval := -1;
	qno := -1;
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

		msg := <-entry =>
			if(fd == nil){
				dialog->prompt(ctxt, frame.image, "error -fg red", "Error", "Lost connection to polling station", 0, "Dismiss"::nil);
				break;
			}
			n := msg[0]-'A';
			lastval = n;
			selectonly(frame, n, Maxanswer, "disabled");
			if(qno >= 0) {
				# send our answer to the polling station
				if(sys->fprint(fd, "%d %s", qno, msg) < 0){
					sys->fprint(sys->fildes(2), "poll: write error: %r\n");
					fd = nil;
				}
				qno = -1;	# only one go at it
			}

		s := <-in =>
			if(s != nil){
				if(debug){
					t := s;
					if(!first)
						t = "\n"+t;
					first = 0;
					tk->cmd(frame, ".f.t insert end '" + t);
					tk->cmd(frame, ".f.t see end");
					tk->cmd(frame, "update");
				}
				(nf, flds) := sys->tokenize(s, " ");
				if(nf > 1 && hd flds == "error:"){
					dialog->prompt(ctxt, frame.image, "error -fg red", "Error", sys->sprint("polling station reports: %s", s), 0, "Dismiss"::nil);
					break;
				}
				if(nf < 4)
					break;
				# seq clientid op name data
				op, name: string;
				flds = tl flds;	# ignore seq
				flds = tl flds;	# ignore clientid
				(op, flds) = (hd flds, tl flds);
				(name, flds) = (hd flds, tl flds);
				case op {
				"M" =>
					# poll qno nanswer opt
					# stop qno
					selectonly(frame, -1, Maxanswer, "disabled");
					if(len flds < 2)
						break;
					(op, flds) = (hd flds, tl flds);
					(s, flds) = (hd flds, tl flds);
					case op {
					"poll" =>
						qno = int s;
						(s, flds) = (hd flds, tl flds);
						n := int s;
						if(n > Maxanswer)
							n = Maxanswer;
						if(n < 2)
							n = 2;
						selectonly(frame, -1, n, "normal");
						lastval = -1;
					"stop" =>
						selectonly(frame, lastval, Maxanswer, "disabled");
					}
				"L" =>
					dialog->prompt(ctxt, frame.image, "error -fg red", "Notice", sys->sprint("Poller (%s) has gone", name), 0, "Exit"::nil);
					tkclient->wmctl(frame, "exit");
				}
			}else{
				dialog->prompt(ctxt, frame.image, "error -fg red", "Notice", "Polling station closed", 0, "Exit"::nil);
				tkclient->wmctl(frame, "exit");
			}
		}
}

selectonly(t: ref Tk->Toplevel, n: int, top: int, state: string)
{
	for(i := 0; i < top; i++){
		path := sys->sprint(".a.a%d", i+1);
		if(i != n)
			tkcmd(t, path+" deselect");
		else
			tkcmd(t, path+" select");
		tkcmd(t, path+" configure -state "+state);
	}
	tk->cmd(t, "update");
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
		sys->fprint(sys->fildes(2), "poll: tk error: %s [%s]\n", s, cmd);
	return s;
}

fittoscreen(win: ref Tk->Toplevel)
{
	draw := load Draw Draw->PATH;
	Point, Rect: import draw;
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
