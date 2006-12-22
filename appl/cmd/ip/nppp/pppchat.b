implement Dialupchat;

#
# Copyright © 2001 Vita Nuova Holdings Limited.  All rights reserved.
#

include "sys.m";
        sys: Sys;

include "draw.m";
	draw: Draw;
	Point, Rect: import draw;

include "tk.m";
        tk: Tk;

include "wmlib.m";
	wmlib: Wmlib;

include "translate.m";
	translate: Translate;
	Dict: import translate;
	dict: ref Dict;

Dialupchat: module
{
	init:	fn(nil: ref Draw->Context, nil: list of string);
};

# Dimension constant for ISP Connect window
WIDTH: con 300;
HEIGHT: con 58;

LightGreen: con "#00FF80";           # colour for successful blob
Blobx: con 8;
Gapx: con 4;
BARW: con (Blobx+Gapx)*10;			# Progress bar width
BARH: con 18;			# Progress bar height
DIALQUANTA : con 1000;
ICONQUANTA : con 5000;

pppquanta := DIALQUANTA;

Maxstep: con 9;

init(ctxt: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	draw = load Draw Draw->PATH;
	tk = load Tk Tk->PATH;
	wmlib = load Wmlib Wmlib->PATH;
	wmlib->init();

	translate = load Translate Translate->PATH;
	if(translate != nil) {
		translate->init();
		dictname := translate->mkdictname("", "pppchat");
		dicterr: string;
		(dict, dicterr) = translate->opendict(dictname);
		if(dicterr != nil)
			sys->fprint(sys->fildes(2), "pppchat: can't open %s: %s\n", dictname, dicterr);
	}else
		sys->fprint(sys->fildes(2), "pppchat: can't load %s: %r\n", Translate->PATH);

	tkargs: string;
	if(args != nil) {
		tkargs = hd args;
		args = tl args;
	}

	sys->pctl(Sys->NEWPGRP, nil);

	pppfd := sys->open("/chan/pppctl", Sys->ORDWR);
	if(pppfd == nil)
		error(sys->sprint("can't open /chan/pppctl: %r"));

	(t, wmctl) := wmlib->titlebar(ctxt.screen, tkargs, X("Dialup Connection"), Wmlib->Hide);

	cmd := chan of string;
	tk->namechan(t, cmd, "cmd");

	pb := Progressbar.mk(t, ".f.prog.c", (BARW, BARH));

	config_win := array[] of {
		"frame .f",
		"frame .f.prog",
		"frame .f.b",

		pb.tkcreate(),
		"pack .f.prog.c -pady 6 -side top",

		"label .f.stat -fg blue -text {"+X("Initialising connection...")+"}",
		"pack .f.stat -side top -fill x -expand 1 -anchor n",

		"pack .f -side top -expand 1 -padx 5 -pady 3 -fill both -anchor w",
		"pack .f.prog -side top -expand 1 -fill x",
		"button .f.b.done -text {"+X("Cancel")+"} -command {send cmd cancel}",
		"pack .f.b.done -side right -padx 1 -pady 1 -anchor s",
		"button .f.b.retry -text {"+X("Retry")+"} -command {send cmd retry} -state disabled",
		"pack .f.b.retry -side left -padx 1 -pady 1 -anchor s",
		"pack .f.b -side top -expand 1 -fill x",

		"pack propagate . 0",
		"update",
	};

	for(i := 0; i < len config_win; i++)
		tkcmd(t, config_win[i]);

	connected := 0;
	winmapped := 1;
	timecount := 0;
	xmin := 0;
	x := 0;
	turn := 0;

	pppquanta = DIALQUANTA;
	ticks := chan of int;
	spawn ppptimer(ticks);

	statuslines := chan of (string, string);
	pids := chan of int;
	spawn ctlreader(pppfd, pids, statuslines);
	ctlpid := <-pids;

Work:
	for(;;) alt {

	s := <-wmctl =>
		if(s == "exit")
			s = "task";
		if(s == "task"){
			spawn wmlib->titlectl(t, s);
			continue;
		}
		wmlib->titlectl(t, s);

	press := <-cmd =>
		case press {
		"cancel" or "disconnect" =>
			tkcmd(t, sys->sprint(".f.stat configure -text '%s", X("Disconnecting")));
			tkcmd(t, "update");
			if(sys->fprint(pppfd, "hangup") < 0){
				err := sys->sprint("%r");
				tkcmd(t, sys->sprint(".f.stat configure -text '%s: %s", X("Error disconnecting"), X(err)));
				sys->fprint(sys->fildes(2), "pppchat: can't disconnect: %s\n", err);
			}
			break Work;
		"retry" =>
			if(sys->fprint(pppfd, "connect") < 0){
				err := sys->sprint("%r");
			}
		}

	<-ticks =>
		ticks <-= 1;
		if(!connected){
			if(pb != nil){
				if((turn ^= 1) == 0)
					pb.setcolour("white");
				else
					pb.setcolour(LightGreen);
			}
			tkcmd(t, "raise .; update");
		}

	(status, err) := <-statuslines =>
		if(status == nil){
			status = "0 1 empty status";
			if(err != nil)
				sys->print("pppchat: !%s\n", err);
		} else
			sys->print("pppchat: %s\n", status);
		(nf, flds) := sys->tokenize(status, " \t\n");
#		for(i = 0; i < len status; i++)
#			if(status[i] == ' ' || status[i] == '\t') {
#				status = status[i+1:];
#				break;
#			}
		if(nf < 3)
			break;
		step := int hd flds; flds = tl flds;
		nstep := int hd flds; flds = tl flds;
		if(step < 0)
			raise "pppchat: bad step";
		case hd flds {
		"error:" =>
			tkcmd(t, ".f.stat configure -fg red -text '"+X(status));
			tkcmd(t, ".f.b.retry configure -state normal");
			tkcmd(t, "update");
			wmlib->unhide();
			winmapped = 1;
			pb.stepto(step, "red");
			#break Work;
		* =>
			pb.setcolour(LightGreen);
			pb.stepto(step, LightGreen);
		}
		turn = 0;
		statusmsg := X(status);
		tkcmd(t, ".f.stat configure -text '"+statusmsg);
		tkcmd(t, "raise .; update");

		case hd flds {
		"up" or "done" =>
			if(!connected){
				connected = 1;
			}
			pppquanta = ICONQUANTA;

			# display connection speed
			if(tl flds != nil)
				tkcmd(t, ".f.stat configure -text {"+statusmsg+" "+"SPEED"+" hd tl flds}");
			else
				tkcmd(t, ".f.stat configure -text {"+statusmsg+"}");
			tkcmd(t, ".f.b.done configure -text Disconnect -command 'send cmd disconnect");
			tkcmd(t, "update");
			sys->sleep(2000);
			tkcmd(t, "pack forget .f.prog; update");
			spawn wmlib->titlectl(t, "task");
			winmapped = 0;
		}
		tkcmd(t, "update");
	}
	<-ticks;
	ticks <-= 0;	# stop ppptimer
	kill(ctlpid);
}

ppptimer(ticks: chan of int)
{
	do{
		sys->sleep(pppquanta);
		ticks <-= 1;
	}while(<-ticks);
}

ctlreader(fd: ref Sys->FD, pidc: chan of int, lines: chan of (string, string))
{
	pidc <-= sys->pctl(0, nil);
	buf := array[128] of byte;
	while((n := sys->read(fd, buf, len buf)) > 0)
		lines <-= (string buf[0:n], nil);
	if(n < 0)
		lines <-= (nil, sys->sprint("%r"));
	else
		lines <-= (nil, nil);
}

Progressbar: adt {
	t:	ref Tk->Toplevel;
	canvas:	string;
	csize:	Point;
	blobs:	list of string;

	mk:		fn(t: ref Tk->Toplevel, canvas: string, csize: Point): ref Progressbar;
	tkcreate:	fn(pb: self ref Progressbar): string;
	setcolour:	fn(pb: self ref Progressbar, c: string);
	stepto:	fn(pb: self ref Progressbar, step: int, col: string);
	destroy:	fn(pb: self ref Progressbar);
};

Progressbar.mk(t: ref Tk->Toplevel, canvas: string, csize: Point): ref Progressbar
{
	return ref Progressbar(t, canvas, csize, nil);
}

Progressbar.tkcreate(pb: self ref Progressbar): string
{
	return sys->sprint("canvas %s -width %d -height %d", pb.canvas, pb.csize.x, pb.csize.y);
}

Progressbar.setcolour(pb: self ref Progressbar, colour: string)
{
	if(pb.blobs != nil)
		tkcmd(pb.t, sys->sprint("%s itemconfigure %s -fill %s; update", pb.canvas, hd pb.blobs, colour));
}

Progressbar.stepto(pb: self ref Progressbar, step: int, col: string)
{
	for(nblob := len pb.blobs; nblob > step+1; nblob--){
		tkcmd(pb.t, sys->sprint("%s delete %s", pb.canvas, hd pb.blobs));
		pb.blobs = tl pb.blobs;
	}
	if(nblob == step+1)
		return;
	p := Point(step*(Blobx+Gapx), 0);
	r := Rect(p, p.add((Blobx, pb.csize.y-2)));
	pb.blobs =  tkcmd(pb.t, sys->sprint("%s create rectangle %d %d %d %d -fill %s", pb.canvas, r.min.x,r.min.y, r.max.x,r.max.y, col)) :: pb.blobs;
}

Progressbar.destroy(pb: self ref Progressbar)
{
	tk->cmd(pb.t, "destroy "+pb.canvas);	# ignore errors
}

tkcmd(t: ref Tk->Toplevel, s: string): string
{
	e := tk->cmd(t, s);
	if(e != nil && e[0] == '!')
		sys->print("pppchat: tk error: %s [%s]\n", e, s);
	return e;
}

kill(pid: int)
{
	if(pid > 0 && (fd := sys->open("/prog/"+string pid+"/ctl", Sys->OWRITE)) != nil)
		sys->fprint(fd, "kill");
}

error(s: string)
{
	sys->fprint(sys->fildes(2), "pppchat: %s\n", s);
	raise "fail:error";
}

X(s: string): string
{
	if(dict != nil)
		return dict.xlate(s);
	return s;
}
