implement Chat;

include "sys.m";
	sys: Sys;

include "draw.m";
	draw: Draw;

include "tk.m";
	tk: Tk;

include "tkclient.m";
	tkclient: Tkclient;

Chat: module {
	init: fn(ctxt: ref Draw->Context, args: list of string);
};

stderr: ref Sys->FD;

tksetup := array [] of {
	"frame .f",
	"text .f.t -state disabled -wrap word -yscrollcommand {.f.sb set}",
	"scrollbar .f.sb -orient vertical -command {.f.t yview}",
	"entry .e -bg white",
	"bind .e <Key-\n> {send cmd send}",
	"pack .f.sb -in .f -side left -fill y",
	"pack .f.t -in .f -side left -fill both -expand 1",
	"pack .f -side top -fill both -expand 1",
	"pack .e -side bottom -fill x",
	"pack propagate . 0",
	"update",
};

init(ctxt: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	sys->pctl(Sys->NEWPGRP, nil);
	stderr = sys->fildes(2);

	draw = load Draw Draw->PATH;
	if (draw == nil)
		badmodule(Draw->PATH);

	tk = load Tk Tk->PATH;
	if (tk == nil)
		badmodule(Tk->PATH);

	tkclient = load Tkclient Tkclient->PATH;
	if (tkclient == nil)
		badmodule(Tkclient->PATH);


	if (args == nil || tl args == nil) {
		sys->fprint(stderr, "usage: chat [servicedir]\n");
		raise "fail:init";
	}
	args = tl args;

	servicedir := ".";
	if(args != nil)
		servicedir = hd args;

	tkclient->init();
	(win, winctl) := tkclient->toplevel(ctxt, nil, "Chat", Tkclient->Appl);

	cmd := chan of string;
	tk->namechan(win, cmd, "cmd");
	tkcmds(win, tksetup);
	tkcmd(win, ". configure -height 300");
	fittoscreen(win);
	tkclient->onscreen(win, nil);
	tkclient->startinput(win, "kbd"::"ptr"::nil);

	msgs := chan of string;
	conn := chan of (string, ref Sys->FD);
	spawn connect(servicedir, msgs, conn);
	msgsfd: ref Sys->FD;

	for (;;) alt {
	(e, fd) := <-conn =>
		if (msgsfd == nil) {
			if (e == nil) {
				output(win, "*** connected");
				msgsfd = fd;
			} else
				output(win, "*** " + e);
		} else {
			output(win, "*** disconnected");
			msgsfd = nil;
		}

	txt := <-msgs =>
		output(win, txt);

	<- cmd =>
		msg := tkcmd(win, ".e get");
		if (msgsfd != nil && msg != nil) {
			tkcmd(win, ".f.t see end");
			tkcmd(win, ".e delete 0 end");
			tkcmd(win, "update");
			d := array of byte msg;
			sys->write(msgsfd, d, len d);
		}

	s := <-win.ctxt.kbd =>
		tk->keyboard(win, s);
	s := <-win.ctxt.ptr =>
		tk->pointer(win, *s);
	s := <-win.ctxt.ctl or
	s = <-win.wreq or
	s = <-winctl =>
		tkclient->wmctl(win, s);
	}
}

err(s: string)
{
	sys->fprint(stderr, "chat: %s\n", s);
	raise "fail:err";
}

badmodule(path: string)
{
	err(sys->sprint("can't load module %s: %r", path));
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
		sys->fprint(stderr, "chat: tk error: %s [%s]\n", s, cmd);
	return s;
}

connect(dir: string, msgs: chan of string, conn: chan of (string, ref Sys->FD))
{
	srvpath := dir+"/msgs";
	msgsfd := sys->open(srvpath, Sys->ORDWR);
	if(msgsfd == nil) {
		conn <-= (sys->sprint("internal error: can't open %s: %r", srvpath), nil);
		return;
	}
	conn <-= (nil, msgsfd);
	buf := array[Sys->ATOMICIO] of byte;
	while((n := sys->read(msgsfd, buf, len buf)) > 0)
		msgs <-= string buf[0:n];
	conn <-= (nil, nil);
}

firstmsg := 1;
output(win: ref Tk->Toplevel, txt: string)
{
	if (firstmsg)
		firstmsg = 0;
	else
		txt = "\n" + txt;
	yview := tkcmd(win, ".f.t yview");
	(nil, toks) := sys->tokenize(yview, " ");
	toks = tl toks;

	tkcmd(win, ".f.t insert end '" + txt);
	if (hd toks == "1")
		tkcmd(win, ".f.t see end");
	tkcmd(win, "update");
}

KEYBOARDH: con 90;

fittoscreen(win: ref Tk->Toplevel)
{
	Point, Rect: import draw;
	if (win.image == nil || win.image.screen == nil)
		return;
	r := win.image.screen.image.r;
	scrsize := Point((r.max.x - r.min.x), (r.max.y - r.min.y)- KEYBOARDH);
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
