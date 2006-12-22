implement WmLogon;

#
# Copyright © 2003 Vita Nuova Holdings Limited.  All rights reserved.
#

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
include "registries.m";
	registries: Registries;
	Registry, Attributes: import registries;


# XXX where to put the certificate: is the username already set to
# something appropriate, with a home directory and keyring directory in that?

# how do we find out the signer; presumably from the registry?
# should do that before signing on; if we can't get it, then prompt for it.
WmLogon: module {
	init:	fn(ctxt: ref Draw->Context, argv: list of string);
};

registry: ref Registry;
usr := "";
passwd := "";
loginaddr := "";
signerpkhash := "";

cfg := array[] of {
	"frame .f -bd 2 -relief raised",
	"label .f.p -bitmap @/icons/inferno.bit -borderwidth 2 -relief raised",
	"label .f.ul -text {User Name:} -anchor w",
	"entry .f.ue -bg white -width 10w",
	"label .f.pl -text {Password:} -anchor w",
	"entry .f.pe -bg white -show *",
	"checkbutton .f.ck -variable newuser -text {New}",
	"frame .f.f -borderwidth 2 -relief raised",
	"frame .f.u",
	"pack .f.ue -in .f.u -side left -expand 1 -fill x",
	"pack .f.ck -in .f.u -side left",
	"grid .f.ul -row 0 -column 0 -sticky e -in .f.f",
	"grid .f.u -row 0 -column 1 -sticky ew -in .f.f",
	"grid .f.pl -row 1 -column 0 -sticky e -in .f.f",
	"grid .f.pe -row 1 -column 1 -sticky ew -in .f.f",
	"pack .f.p .f.f -fill x",
	"bind .f.ue <Key-\n> {focus .f.pe}",
	"bind .f.ue {<Key-\t>} {focus .f.pe}",
	"bind .f.pe <Key-\n> {send panelcmd ok}",
	"bind .f.pe {<Key-\t>} {focus .f.ue}",
	"focus .f.ue",
};

notecfg := array[] of {
	"frame .n -bd 2 -relief raised",
	"frame .n.f",
	"label .n.f.m -anchor nw",
	"label .n.f.l -bitmap error -foreground red",
	"button .n.b -text Continue -command {send notecmd done}",
	"focus .n.f",
	"bind .n.f <Key-\n> {send notecmd done}",
	"pack .n.f.l .n.f.m -side left -expand 1",
	"pack .n.f .n.b",
};

checkload[T](x: T, p: string): T
{
	if(x == nil)
		error(sys->sprint("cannot load %s: %r\n", p));
	return x;
}

init(ctxt: ref Draw->Context, argv: list of string)
{
	sys = load Sys Sys->PATH;
	draw = checkload(load Draw Draw->PATH, Draw->PATH);
	tk = checkload(load Tk Tk->PATH, Tk->PATH);
	tkclient = checkload(load Tkclient Tkclient->PATH, Tkclient->PATH);
	tkclient->init();
	login = checkload(load Login Login->PATH, Login->PATH);
	keyring = checkload(load Keyring Keyring->PATH, Keyring->PATH);
	registries = checkload(load Registries Registries->PATH, Registries->PATH);
	registries->init();

	arg := load Arg Arg->PATH;
	if(arg != nil){
		arg->init(argv);
		arg->setusage("usage: logon [-u user] [-p passwd] [-a loginaddr] command [arg...]]\n");
		while((opt := arg->opt()) != 0){
			case opt{
			'a' =>
				loginaddr = arg->earg();
			'k' =>
				signerpkhash = arg->earg();
			'u' =>
				usr = arg->earg();
			'p' =>
				passwd = arg->earg();
			* =>
				arg->usage();
			}
		}
		argv = arg->argv();
		arg = nil;
	} else {
		if(tl argv != nil)
			sys->fprint(stderr(), "remotelogon: cannot load %s: %r; ignoring arguments\n", Arg->PATH);
		argv = nil;
	}
	sys->pctl(Sys->FORKNS, nil);

	sync := chan of (ref Keyring->Authinfo, string);
	spawn logon(ctxt, sync);
	(key, err) := <-sync;
	if(key == nil)
		raise "fail:" + err;
	registry = nil;
	servekeyfile(key);

	errch := chan of string;
	spawn exec(ctxt, argv, errch);
	err = <-errch;
	if (err != nil)
		error(err);
}

# run in a separate process so that we keep the outer namespace unsullied by
# mounted registries.
logon(ctxt: ref Draw->Context, sync: chan of (ref Keyring->Authinfo, string))
{
	sys->pctl(Sys->NEWPGRP|Sys->FORKNS, nil);

	{
		logon1(ctxt, sync);
	} exception e {
	"fail:*" =>
		sync <-= (nil, e[5:]);
	}
}

logon1(ctxt: ref Draw->Context, sync: chan of (ref Keyring->Authinfo, string))
{
	if(ctxt == nil)
		ctxt = tkclient->makedrawcontext();

	(top, ctl) := tkclient->toplevel(ctxt, nil, nil, Tkclient->Plain);
	tkclient->startinput(top, "kbd" :: "ptr" :: nil);
	tkclient->onscreen(top, "onscreen");
	stop := chan of int;
	spawn tkclient->handler(top, stop);
	if(usr != nil){
		fa := loginaddr;
		if(fa == nil)
			fa = findloginresource(top, signerpkhash);
		if(getauthinfo(top, fa, 0, sync)){
			cleanup();
			stop <-= 1;
			exit;
		}
	}

	cmd(top, "canvas .c -buffer none -bg #777777");
	cmd(top, "pack .c -fill both -expand 1");
	enter := makepanel(top);
	for(;;) {
		cmd(top, "focus .f.ue; update");
		<-enter;
		usr = cmd(top, ".f.ue get");
		if(usr == nil) {
			notice(top, "You must supply a user name to login");
			continue;
		}
		passwd = cmd(top, ".f.pe get");

		if(getauthinfo(top, loginaddr, int cmd(top, "variable newuser"), sync)){
			cleanup();
			stop <-= 1;
			exit;
		}
		cmd(top, ".f.ue delete 0 end");
		cmd(top, ".f.pe delete 0 end");
	}
}

findloginresource(top: ref Tk->Toplevel, signerpkhash: string): string
{
	mountregistry();
	attrs := ("resource", "login")::nil;
	if(signerpkhash != nil)
		attrs = ("pk", signerpkhash) :: attrs;
	(svc, err) := registry.find(attrs);
	if(svc == nil){
		notice(top, "cannot find name of login server");
		return nil;
	}
	return (hd svc).addr;
}

cleanup()
{
	# get rid of spurious mouse/kbd reading processes.
	# XXX should probably implement "stop" ctl message in wmlib
	sys->fprint(sys->open("/prog/"+string sys->pctl(0, nil)+"/ctl", Sys->OWRITE), "killgrp");
}

getauthinfo(top: ref Tk->Toplevel, addr: string, newuser: int, sync: chan of (ref Keyring->Authinfo, string)): int
{
	if(newuser)
		if(createuser(top, usr, passwd, signerpkhash) == 0)
			return 0;

	if(addr == nil){
		addr = findloginresource(top, signerpkhash);
		if(addr == nil)
			return 0;
	}
	(err, info) := login->login(usr, passwd, addr);
	if(info == nil){
		notice(top, "Login failed:\n" + err);
		return 0;
	}
	sync <-= (info, nil);
	return 1;
}

createuser(top: ref Tk->Toplevel, user, passwd: string, signerpkhash: string): int
{
	mountregistry();
	attrs := ("resource", "createuser")::nil;
	if(signerpkhash != nil)
		attrs = ("signer", signerpkhash) :: attrs;
	(svcs, err) := registry.find(attrs);
	if(svcs == nil){
		notice(top, "cannot find name of login server");
		return 0;
	}
	addr := (hd svcs).addr;
	(ok, c) := sys->dial(addr, nil);
	if(ok == -1){
		notice(top, sys->sprint("cannot dial %s: %r", addr));
		return 0;
	}
	if(sys->mount(c.dfd, nil, "/tmp", Sys->MREPL, nil) == -1){
		notice(top, sys->sprint("cannot mount %s: %r", addr));
		return 0;
	}
	fd := sys->open("/tmp/createuser", Sys->OWRITE);
	if(fd == nil){
		notice(top, sys->sprint("cannot open createuser: %r"));
		return 0;
	}
	if(sys->fprint(fd, "%q %q", user, passwd) <= 0){
		notice(top, sys->sprint("cannot create user: %r"));
		return 0;
	}
	signerpkhash = (hd svcs).attrs.get("signer");
	return 1;
}

servekeyfile(info: ref Keyring->Authinfo)
{
	keys := "/usr/" + user() + "/keyring";
	if(sys->bind("#s", keys, Sys->MBEFORE) == -1)
		error(sys->sprint("cannot bind #s: %r"));
	fio := sys->file2chan(keys, "default");
	if(fio == nil)
		error(sys->sprint("cannot make %s: %r", keys + "/default"));
	sync := chan of int;
	spawn infofile(fio, sync);
	<-sync;

	if(keyring->writeauthinfo(keys + "/default", info) == -1)
		error(sys->sprint("cannot write %s: %r", keys + "/default"));
}

mountregistry()
{
	if(registry == nil)
		registry = Registry.new("/mnt/registry");
	if(registry == nil)
		registry = Registry.connect(nil, nil, nil);
	if(registry == nil){
		sys->fprint(stderr(), "logon: cannot contact registry: %r\n");
		raise "fail:no registry";
	}
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

exec(ctxt: ref Draw->Context, argv: list of string, errch: chan of string)
{
	sys->pctl(sys->NEWFD, 0 :: 1 :: 2 :: nil);
	if(argv == nil)
		argv = "/dis/wm/wm.dis" :: nil;
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

makepanel(top: ref Tk->Toplevel): chan of string
{
	c := chan of string;
	tk->namechan(top, c, "panelcmd");

	for(i := 0; i < len cfg; i++)
		cmd(top, cfg[i]);
	centre(top, ".f");
	return c;
}

centre(top: ref Tk->Toplevel, w: string): string
{
	ir := tk->rect(top, w, Tk->Required);
	r := tk->rect(top, ".", 0);
	org := Point(r.dx() / 2 - ir.dx() / 2, r.dy() / 3 - ir.dy() / 2);
	if (org.y < 0)
		org.y = 0;
	if(org.x < 0)
		org.x = 0;
	return cmd(top, ".c create window "+string org.x+" "+string org.y+" -window "+w+" -anchor nw");
}

notice(top: ref Tk->Toplevel, message: string)
{
	if(top == nil)
		error(message);
	c := chan of string;
	tk->namechan(top, c, "notecmd");
	for(i := 0; i < len notecfg; i++)
		cmd(top, notecfg[i]);
	cmd(top, ".n.f.m configure -text '" + message);
	id := centre(top, ".n");
	cmd(top, "update");
	<-c;
	cmd(top, ".c delete " + id);
	cmd(top, "destroy .n");
	cmd(top, "update");
}

error(e: string)
{
	sys->fprint(stderr(), "remotelogon: %s\n", e);
	raise "fail:error";
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

cmd(top: ref Tk->Toplevel, s: string): string
{
	e := tk->cmd(top, s);
	if (e != nil && e[0] == '!')
		sys->fprint(stderr(), "remotelogon: tk error on '%s': %s\n", s, e);
	return e;
}
