implement WmLogon;
#
# get a certificate to enable remote access.
#
include "sys.m";
	sys: Sys;

include "draw.m";
	draw: Draw;
	Screen, Display, Image, Context, Point, Rect: import draw;

include "tk.m";
	tk: Tk;

include "tkclient.m";
	tkclient: Tkclient;

include "arg.m";
include "sh.m";
include "newns.m";
include "keyring.m";
	keyring: Keyring;
include "security.m";
	login: Login;

# XXX where to put the certificate: is the username already set to
# something appropriate, with a home directory and keyring directory in that?

# how do we find out the signer; presumably from the registry?
# should do that before signing on; if we can't get it, then prompt for it.
WmLogon: module {
	init:	fn(ctxt: ref Draw->Context, argv: list of string);
};

cfg := array[] of {
	"label .p -bitmap @/icons/inferno.bit -borderwidth 2 -relief raised",
	"label .ul -text {User Name:} -anchor w",
	"entry .ue -bg white",
	"label .pl -text {Password:} -anchor w",
	"entry .pe -bg white -show *",
	"frame .f -borderwidth 2 -relief raised",
	"grid .ul .ue -in .f",
	"grid .pl .pe -in .f",
	"pack .p .f -fill x",
	"bind .ue <Key-\n> {focus next}",
	"bind .ue {<Key-\t>} {focus next}",
	"bind .pe <Key-\n> {send cmd ok}",
	"bind .pe {<Key-\t>} {focus next}",
	"focus .e",
};

init(ctxt: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	draw = load Draw Draw->PATH;
	tk = load Tk Tk->PATH;
	tkclient = load Tkclient Tkclient->PATH;
	if(tkclient == nil){
		sys->fprint(stderr(), "logon: cannot load %s: %r\n", Tkclient->PATH);
		raise "fail:bad module";
	}
	login = load Login Login->PATH;
	if(login == nil){
		sys->fprint(stderr(), "logon: cannot load %s: %r\n", Login->PATH);
		raise "fail:bad module";
	}
	keyring = load Keyring Keyring->PATH;
	if(keyring == nil){
		sys->fprint(stderr(), "logon: cannot load %s: %r\n", Keyring->PATH);
		raise "fail:bad module";
	}
	sys->pctl(sys->NEWPGRP, nil);
	tkclient->init();

	(ctlwin, nil) := tkclient->toplevel(ctxt, nil, nil, Tkclient->Plain);
	if(sys->fprint(ctlwin.ctxt.connfd, "request") == -1){
		sys->fprint(stderr(), "logon: must be run as principal wm application\n");
		raise "fail:lack of control";
	}
	addr: con "tcp!127.0.0.1!inflogin";
	usr := "";
	passwd := "";
	arg := load Arg Arg->PATH;
	if(arg != nil){
		arg->init(args);
		arg->setusage("usage: logon [-u user] [-p passwd] command [arg...]]\n");
		while((opt := arg->opt()) != 0){
			case opt{
			'u' =>
				usr = arg->earg();
			'p' =>
				passwd = arg->earg();
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

	if (usr == nil || !logon(ctxt, usr, passwd, addr)) {
		(panel, cmd) := makepanel(ctxt);
		stop := chan of int;
		spawn tkclient->handler(panel, stop);
		for(;;) {
			tk->cmd(panel, "focus .ue; update");
			<-cmd;
			usr = tk->cmd(panel, ".ue get");
			if(usr == nil) {
				notice(ctxt, "You must supply a user name to login");
				continue;
			}
			passwd = tk->cmd(panel, ".pe get");

			if(logon(ctxt, usr, passwd, addr)) {
				panel = nil;
				stop <-= 1;
				break;
			}
			tk->cmd(panel, ".ue delete 0 end");
			tk->cmd(panel, ".pe delete 0 end");
		}
	}
	(ok, nil) := sys->stat("namespace");
	if(ok >= 0) {
		ns := load Newns Newns->PATH;
		if(ns == nil)
			notice(ctxt, "failed to load namespace builder");
		else if ((nserr := ns->newns(nil, nil)) != nil)
			notice(ctxt, "namespace error:\n"+nserr);
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

makepanel(ctxt: ref Draw->Context): (ref Tk->Toplevel, chan of string)
{
	(t, nil) := tkclient->toplevel(ctxt, "-bg silver", nil, Tkclient->Plain);

	cmd := chan of string;
	tk->namechan(t, cmd, "cmd");

	for(i := 0; i < len cfg; i++)
		tk->cmd(t, cfg[i]);
	err := tk->cmd(t, "variable lasterr");
	if(err != nil) {
		sys->fprint(stderr(), "logon: tk error: %s\n", err);
		raise "fail:config error";
	}
	tk->cmd(t, "update");
	org: Point;
	ir := tk->rect(t, ".", Tk->Border|Tk->Required);
	org.x = t.screenr.dx() / 2 - ir.dx() / 2;
	org.y = t.screenr.dy() / 3 - ir.dy() / 2;
	if (org.y < 0)
		org.y = 0;
	tk->cmd(t, ". configure -x " + string org.x + " -y " + string org.y);
	tkclient->startinput(t, "kbd" :: "ptr" :: nil);
	tkclient->onscreen(t, "onscreen");
	return (t, cmd);
}

exec(ctxt: ref Draw->Context, argv: list of string, errch: chan of string)
{
	sys->pctl(sys->NEWFD, 0 :: 1 :: 2 :: nil);
	if(argv == nil)
		argv = "/dis/wm/toolbar.dis" :: nil;
	else {
		sh := load Sh Sh->PATH;
		if(sh != nil){
			sh->run(ctxt, "{$* &}" :: argv);
			errch <-= nil;
			exit;
		}
	}
	{
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

logon(ctxt: ref Draw->Context, uname, passwd, addr: string): int
{
	(err, info) := login->login(uname, passwd, addr);
	if(err != nil){
		notice(ctxt, "Login failed:\n" + err);
		return 0;
	}

	keys := "/usr/" + user() + "/keyring";
	if(sys->bind("#s", keys, Sys->MBEFORE) == -1){
		notice(ctxt, sys->sprint("Cannot access keyring: %r"));
		return 0;
	}
	fio := sys->file2chan(keys, "default");
	if(fio == nil){
		notice(ctxt, sys->sprint("Cannot create key file: %r"));
		return 0;
	}
	sync := chan of int;
	spawn infofile(fio, sync);
	<-sync;

	if(keyring->writeauthinfo(keys + "/default", info) == -1){
		notice(ctxt, sys->sprint("Cannot write key file: %r"));
		return 0;
	}

	return 1;
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
	sz := Point(int tk->cmd(t, ". cget -width"), int tk->cmd(t, ". cget -height"));
	r := t.screenr;
	if (sz.x > r.dx())
		tk->cmd(t, ". configure -width " + string r.dx());
	org: Point;
	org.x = r.dx() / 2 - tk->rect(t, ".", 0).dx() / 2;
	org.y = r.dy() / 3 - tk->rect(t, ".", 0).dy() / 2;
	if (org.y < 0)
		org.y = 0;
	tk->cmd(t, ". configure -x " + string org.x + " -y " + string org.y);
}

notice(ctxt: ref Draw->Context, message: string)
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

stderr(): ref Sys->FD
{
	return sys->fildes(2);
}

user(): string
{
	fd := sys->open("/dev/user", Sys->OREAD);
	buf := array[8192] of byte;
	if((n := sys->read(fd, buf, len buf)) > 0)
		return string buf[0:n];
	return "none";
}

infofile(fileio: ref Sys->FileIO, sync: chan of int)
{
	sys->pctl(Sys->NEWPGRP|Sys->NEWFD|Sys->NEWNS, nil);
	sync <-= 1;

	infodata: array of byte;
	for(;;) alt {
	(off, nbytes, fid, rc) := <-fileio.read =>
		if(rc == nil)
			break;
		if(off > len infodata)
			off = len infodata;
		rc <-= (infodata[off:], nil);

	(off, data, fid, wc) := <-fileio.write =>
		if(wc == nil)
			break;

		if(off != len infodata){
			wc <-= (0, "cannot be rewritten");
		} else {
			nid := array[len infodata+len data] of byte;
			nid[0:] = infodata;
			nid[len infodata:] = data;
			infodata = nid;
			wc <-= (len data, nil);
		}
	}
}
