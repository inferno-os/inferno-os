implement WmLogon;
#
# Logon program for Wm environment
#
include "sys.m";
	sys: Sys;

include "draw.m";
	draw: Draw;
	Screen, Display, Image, Context, Point, Rect: import draw;
	ctxt: ref Context;

include "tk.m";
	tk: Tk;

include "tkclient.m";
	tkclient: Tkclient;

include "readdir.m";

include "arg.m";
include "sh.m";
include "newns.m";
include "keyring.m";
include "security.m";

WmLogon: module
{
	init:	fn(ctxt: ref Draw->Context, argv: list of string);
};

cfg := array[] of {
	"label .p -bitmap @/icons/inferno.bit -borderwidth 2 -relief raised",
	"frame .l -bg red",
	"label .l.u -fg black -bg silver -text {User Name:} -anchor w",
	"pack .l.u -fill x",
	"frame .e",
	"entry .e.u -bg white",
	"pack .e.u -fill x",
	"frame .f -borderwidth 2 -relief raised",
	"pack .l .e -side left -in .f",
	"pack .p .f -fill x",
	"bind .e.u <Key-\n> {send cmd ok}",
	"focus .e.u"
};

listcfg := array[] of {
	"frame .f",
	"listbox .f.lb -yscrollcommand {.f.sb set}",
	"scrollbar .f.sb -orient vertical -command {.f.lb yview}",
	"button .login -text {Login} -command {send cmd login}",
	"pack .f.sb .f.lb -in .f -side left -fill both -expand 1",
	"pack .f -side top -anchor center -fill y -expand 1",
	"pack .login -side top",
#	"pack propagate . 0",
};

init(actxt: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	draw = load Draw Draw->PATH;
	tk = load Tk Tk->PATH;
	tkclient = load Tkclient Tkclient->PATH;
	if(tkclient == nil){
		sys->fprint(stderr(), "logon: cannot load %s: %r\n", Tkclient->PATH);
		raise "fail:bad module";
	}
	sys->pctl(Sys->NEWPGRP|Sys->FORKFD, nil);
	tkclient->init();
	ctxt = actxt;

	dolist := 0;
	usr := "";
	nsfile := "namespace";
	arg := load Arg Arg->PATH;
	if(arg != nil){
		arg->init(args);
		arg->setusage("logon [-l] [-n namespace] [-u user]");
		while((opt := arg->opt()) != 0){
			case opt{
			'u' =>
				usr = arg->earg();
			'l' =>
				dolist = 1;
			'n' =>
				nsfile = arg->earg();
			* =>
				arg->usage();
			}
		}
		args = arg->argv();
		arg = nil;
	} else
		args = nil;
	if(ctxt == nil)
		sys->fprint(stderr(), "logon: must run under a window manager\n");

	(ctlwin, nil) := tkclient->toplevel(ctxt, nil, nil, Tkclient->Plain);
	if(sys->fprint(ctlwin.ctxt.connfd, "request") == -1){
		sys->fprint(stderr(), "logon: must be run as principal wm application\n");
		raise "fail:lack of control";
	}

	if(dolist)
		usr = chooseuser(ctxt);

	if (usr == nil || !logon(usr)) {
		(panel, cmd) := makepanel(ctxt, cfg);
		stop := chan of int;
		spawn tkclient->handler(panel, stop);
		for(;;) {
			tk->cmd(panel, "focus .e.u; update");
			<-cmd;
			usr = tk->cmd(panel, ".e.u get");
			if(usr == "") {
				notice("You must supply a user name to login");
				continue;
			}
			if(logon(usr)) {
				panel = nil;
				stop <-= 1;
				break;
			}
			tk->cmd(panel, ".e.u delete 0 end");
		}
	}
	ok: int;
	if(nsfile != nil){
		(ok, nil) = sys->stat(nsfile);
		if(ok < 0){
			nsfile = nil;
			(ok, nil) = sys->stat("namespace");
		}
	}else
		(ok, nil) = sys->stat("namespace");
	if(ok >= 0) {
		ns := load Newns Newns->PATH;
		if(ns == nil)
			notice("failed to load namespace builder");
		else if ((nserr := ns->newns(nil, nsfile)) != nil)
			notice("namespace error:\n"+nserr);
	}
	tkclient->wmctl(ctlwin, "endcontrol");
	errch := chan of string;
	spawn exec(ctxt, args, errch);
	err := <-errch;
	if (err != nil) {
		sys->fprint(stderr(), "logon: %s\n", err);
		raise "fail:exec failed";
	}
}

makepanel(ctxt: ref Draw->Context, cmds: array of string): (ref Tk->Toplevel, chan of string)
{
	(t, nil) := tkclient->toplevel(ctxt, "-bg silver", nil, Tkclient->Plain);

	cmd := chan of string;
	tk->namechan(t, cmd, "cmd");

	for(i := 0; i < len cmds; i++)
		tk->cmd(t, cmds[i]);
	err := tk->cmd(t, "variable lasterr");
	if(err != nil) {
		sys->fprint(stderr(), "logon: tk error: %s\n", err);
		raise "fail:config error";
	}
	tk->cmd(t, "update");
	centre(t);
	tkclient->startinput(t, "kbd" :: "ptr" :: nil);
	tkclient->onscreen(t, "onscreen");
	return (t, cmd);
}

exec(ctxt: ref Draw->Context, argv: list of string, errch: chan of string)
{
	sys->pctl(sys->NEWFD, 0 :: 1 :: 2 :: nil);
	{
		argv = "/dis/wm/toolbar.dis" :: nil;
		cmd := load Command hd argv;
		if (cmd == nil) {
			errch <-= sys->sprint("cannot load %s: %r", hd argv);
		} else {
			errch <-= nil;
			spawn cmd->init(ctxt, argv);
		}
	}exception{
	"fail:*" =>
		exit;
	}
}

logon(user: string): int
{
	userdir := "/usr/"+user;
	if(sys->chdir(userdir) < 0) {
		notice("There is no home directory for \""+
			user+"\"\nmounted on this machine");
		return 0;
	}

	chmod("/chan", Sys->DMDIR|8r777);
	chmod("/chan/wmrect", 8r666);
	chmod("/chan/wmctl", 8r666);

	#
	# Set the user id
	#
	fd := sys->open("/dev/user", sys->OWRITE);
	if(fd == nil) {
		notice(sys->sprint("failed to open /dev/user: %r"));
		return 0;
	}
	b := array of byte user;
	if(sys->write(fd, b, len b) < 0) {
		notice("failed to write /dev/user\nwith error "+sys->sprint("%r"));
		return 0;
	}

	return 1;
}

chmod(file: string, mode: int): int
{
	d := sys->nulldir;
	d.mode = mode;
	if(sys->wstat(file, d) < 0){
		notice(sys->sprint("failed to chmod %s: %r", file));
		return -1;
	}
	return 0;
}

chooseuser(ctxt: ref Draw->Context): string
{
	(t, cmd) := makepanel(ctxt, listcfg);
	usrlist := getusers();
	if(usrlist == nil)
		usrlist = "inferno" :: nil;
	for(; usrlist != nil; usrlist = tl usrlist)
		tkcmd(t, ".f.lb insert end '" + hd usrlist);
	tkcmd(t, "update");
	stop := chan of int;
	spawn tkclient->handler(t, stop);
	u := "";
	for(;;){
		<-cmd;
		sel := tkcmd(t, ".f.lb curselection");
		if(sel == nil)
			continue;
		u = tkcmd(t, ".f.lb get " + sel);
		if(u != nil)
			break;
	}
	stop <-= 1;
	return u;
}

getusers(): list of string
{
	readdir := load Readdir Readdir->PATH;
	if(readdir == nil)
		return nil;
	(dirs, nil) := readdir->init("/usr", Readdir->NAME);
	n: list of string;
	for (i := len dirs -1; i >=0; i--)
		if (dirs[i].qid.qtype & Sys->QTDIR)
			n = dirs[i].name :: n;
	return n;
}

notecmd := array[] of {
	"frame .f",
	"label .f.l -bitmap error -foreground red",
	"button .b -text Continue -command {send cmd done}",
	"focus .f",
	"bind .f <Key-\n> {send cmd done}",
	"pack .f.l .f.m -side left -expand 1",
	"pack .f .b",
	"pack propagate . 0",
};

centre(t: ref Tk->Toplevel)
{
	org: Point;
	ir := tk->rect(t, ".", Tk->Border|Tk->Required);
	org.x = t.screenr.dx() / 2 - ir.dx() / 2;
	org.y = t.screenr.dy() / 3 - ir.dy() / 2;
#sys->print("ir: %d %d %d %d\n", ir.min.x, ir.min.y, ir.max.x, ir.max.y);
	if (org.y < 0)
		org.y = 0;
	tk->cmd(t, ". configure -x " + string org.x + " -y " + string org.y);
}

notice(message: string)
{
	(t, nil) := tkclient->toplevel(ctxt, "-borderwidth 2 -relief raised", nil, Tkclient->Plain);
	cmd := chan of string;
	tk->namechan(t, cmd, "cmd");
	tk->cmd(t, "label .f.m -anchor nw -text '"+message);
	for(i := 0; i < len notecmd; i++)
		tk->cmd(t, notecmd[i]);
	centre(t);
	tkclient->onscreen(t, "onscreen");
	tkclient->startinput(t, "kbd"::"ptr"::nil);
	stop := chan of int;
	spawn tkclient->handler(t, stop);
	tk->cmd(t, "update; cursor -default");
	<-cmd;
	stop <-= 1;
}

tkcmd(t: ref Tk->Toplevel, cmd: string): string
{
	s := tk->cmd(t, cmd);
	if (s != nil && s[0] == '!') {
		sys->print("%s\n", cmd);
		sys->print("tk error: %s\n", s);
	}
	return s;
}

stderr(): ref Sys->FD
{
	return sys->fildes(2);
}

rf(path: string) : string
{
	fd := sys->open(path, sys->OREAD);
	if(fd == nil)
		return nil;

	buf := array[512] of byte;
	n := sys->read(fd, buf, len buf);
	if(n <= 0)
		return nil;

	return string buf[0:n];
}
