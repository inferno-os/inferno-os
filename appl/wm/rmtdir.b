implement WmRmtdir;

include "sys.m";
	sys: Sys;

include "draw.m";
	draw: Draw;

include "tk.m";
	tk: Tk;
	Toplevel: import tk;

include	"tkclient.m";
	tkclient: Tkclient;

include "keyring.m";
include "security.m";

t: ref Toplevel;

WmRmtdir: module
{
	init:	fn(ctxt: ref Draw->Context, argv: list of string);
};

Wm: module
{
	init:	fn(ctxt: ref Draw->Context, argv: list of string);
};

rmt_config := array[] of {
	"frame .f",
	"label .f.l -text Address:",
	"entry .f.e",
	"pack .f.l .f.e -side left",
	"label .status -text {Enter net!machine ...} -anchor w",
	"pack .Wm_t .status .f -fill x",
	"bind .f.e <Key-\n> {send cmd dial}",
	"frame .b",
	"radiobutton .b.none -variable alg -value none -anchor w -text '"+
			"Authentication without SSL",
	"radiobutton .b.clear -variable alg -value clear -anchor w -text '"+
			"Authentication with SSL clear",
	"radiobutton .b.sha -variable alg -value sha  -anchor w -text '"+
			"Authentication with SHA hash",
	"radiobutton .b.md5 -variable alg -value md5  -anchor w -text '"+
			"Authentication with MD5 hash",
	"radiobutton .b.rc4 -variable alg -value rc4 -anchor w -text '"+
			"Authentication with RC4 encryption",
	"radiobutton .b.sharc4 -variable alg -value sha/rc4 -anchor w -text '"+
			"Authentication with SHA and RC4",
	"radiobutton .b.md5rc4 -variable alg -value md5/rc4 -anchor w -text '"+
			"Authentication with MD5 and RC4",
	"pack .b.none .b.clear .b.sha .b.md5 .b.rc4 .b.sharc4 .b.md5rc4 -fill x",
	"pack .b -fill x",
	".b.none invoke",
	"update",
};

init(ctxt: ref Draw->Context, nil: list of string)
{
	menubut : chan of string;

	sys  = load Sys  Sys->PATH;
	if (ctxt == nil) {
		sys->fprint(sys->fildes(2), "rmtdir: no window context\n");
		raise "fail:bad context";
	}
	draw = load Draw Draw->PATH;
	tk   = load Tk   Tk->PATH;
	tkclient= load Tkclient Tkclient->PATH;

	tkclient->init();

	(t, menubut) = tkclient->toplevel(ctxt, "", sysname()+": Remote Connection", 0);

	cmd := chan of string;
	tk->namechan(t, cmd, "cmd");

	for (i:=0; i<len rmt_config; i++)
		tk->cmd(t, rmt_config[i]);
	tkclient->onscreen(t, nil);
	tkclient->startinput(t, "kbd"::"ptr"::nil);

	for(;;) alt {
	s := <-t.ctxt.kbd =>
		tk->keyboard(t, s);
	s := <-t.ctxt.ptr =>
		tk->pointer(t, *s);
	s := <-t.ctxt.ctl or
	s = <-t.wreq or
	s = <-menubut =>
		tkclient->wmctl(t, s);
	<-cmd =>
		addr := tk->cmd(t, ".f.e get");
		status("Dialing");
		(ok, c) := sys->dial(netmkaddr(addr, "tcp", "styx"), nil);
		if(ok < 0) {
			tk->cmd(t, ".status configure -text {Failed: "+
					sys->sprint("%r")+"}; update");
			break;
		}
		status("Authenticate");
		alg := tk->cmd(t, "variable alg");

		kr := load Keyring Keyring->PATH;
		if(kr == nil){
			tk->cmd(t, ".status configure -text {Error: can't load module Keyring "+
					sys->sprint("%r")+"}; update");
			break;
		}

		user := user();
		kd := "/usr/" + user + "/keyring/";
		cert := kd + netmkaddr(addr, "tcp", "");
		(ok, nil) = sys->stat(cert);
		if(ok < 0)
			cert = kd + "default";

		ai := kr->readauthinfo(cert);
		if(ai == nil){
			tk->cmd(t, ".status configure -text {Error: certificate for "+
					sys->sprint("%s",addr)+" not found}; update");
			wmgetauthinfo := load Wm "/dis/wm/wmgetauthinfo.dis";
			if(wmgetauthinfo == nil){
				tk->cmd(t, ".status configure -text {Error: can't load module wmgetauthinfo.dis}; update");
				exit;
			}
			spawn wmgetauthinfo->init(ctxt, nil); 
			break;
		}

		au := load Auth Auth->PATH;
		if(au == nil){
			tk->cmd(t, ".status configure -text {Error: can't load module Auth "+
					sys->sprint("%r")+"; update");
			break;
		}

		err := au->init();
		if(err != nil){
			tk->cmd(t, ".status configure -text {Error: "+
					sys->sprint("%s", err)+"; update");
			break;
		}

		fd: ref Sys->FD;
		(fd, err) = au->client(alg, ai, c.dfd);
		if(fd == nil){
			tk->cmd(t, ".status configure -text {Error: authentication failed: "+
					sys->sprint("%s",err)+"; update");
			break;
		}

		status("Mount");
		sys->pctl(sys->FORKNS, nil);	# don't fork before authentication
		n := sys->mount(fd, nil, "/n/remote", sys->MREPL, "");
		if(n < 0) {
			tk->cmd(t, ".status configure -text {Mount failed: "+
					sys->sprint("%r")+"}; update");
			break;
		}
		wmdir := load Wm "/dis/wm/dir.dis";
		spawn wmdir->init(ctxt, "wm/dir" :: "/n/remote" :: nil);
		return;
	}
}

status(s: string)
{
	tk->cmd(t, ".status configure -text {"+s+"}; update");
}

sysname(): string
{
	fd := sys->open("#c/sysname", sys->OREAD);
	if(fd == nil)
		return "Anon";
	buf := array[128] of byte;
	n := sys->read(fd, buf, len buf);
	if(n < 0) 
		return "Anon";
	return string buf[0:n];
}

user(): string
{
	sys = load Sys Sys->PATH;

	fd := sys->open("/dev/user", sys->OREAD);
	if(fd == nil)
		return "";

	buf := array[128] of byte;
	n := sys->read(fd, buf, len buf);
	if(n < 0)
		return "";

	return string buf[0:n];	
}

netmkaddr(addr, net, svc: string): string
{
	if(net == nil)
		net = "net";
	(n, l) := sys->tokenize(addr, "!");
	if(n <= 1){
		if(svc== nil)
			return sys->sprint("%s!%s", net, addr);
		return sys->sprint("%s!%s!%s", net, addr, svc);
	}
	if(svc == nil || n > 2)
		return addr;
	return sys->sprint("%s!%s", addr, svc);
}
