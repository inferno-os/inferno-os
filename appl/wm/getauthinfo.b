implement WmGetauthinfo;

include "sys.m";
	sys: Sys;

include "security.m";
	login: Login;

include "draw.m";
	draw: Draw;

include "tk.m";
	tk: Tk;

include "tkclient.m";
	tkclient: Tkclient;

include "dialog.m";
	dialog: Dialog;

include "keyring.m";
	kr: Keyring;

include "string.m";

include "sh.m";

#
# Tk version of getauthinfo command
#
WmGetauthinfo: module 
{
	init: fn(ctxt: ref Draw->Context, argv: list of string);
};

Wm: module
{
	init:	fn(ctxt: ref Draw->Context, argv: list of string);
};

cfg := array[] of {
	"frame .all -borderwidth 2 -relief raised",

	"frame .u",
	"label .u.l -text {User    } -anchor w",
	"entry .u.e",
	"pack .u.l .u.e -side left -in .u -expand 1",
	"bind .u.e <Key-\n> {send cmd u}",
	"focus .u.e",

	"frame .p",
	"label .p.l -text {Password} -anchor w",
	"entry .p.e -show *",
	"pack .p.l .p.e -side left -in .p -expand 1",
	"bind .p.e <Key-\n> {send cmd p}",

	"frame .s",
	"label .s.l -text {Signer  } -anchor w",
	"entry .s.e",
	"pack .s.l .s.e -side left -in .s -expand 1",
	"bind .s.e <Key-\n> {send cmd s}",

	"frame .f",
	"label .f.l -text {Save key} -anchor w",
	"entry .f.e",
	"pack .f.l .f.e -side left -in .f -expand 1",
	"bind .f.e <Key-\n> {send cmd f}",

	"frame .b",
	"radiobutton .b.p -variable save -value p -anchor w -text '" + "Permanent",
	"radiobutton .b.t -variable save -value t -anchor w -text '" + "Temporary",
	"pack .b.p .b.t -side right -in .b -expand 1",
	".b.p invoke",
	"pack .u .p .s .f .b -in .all",
	"pack .Wm_t .all -fill x -expand 1",
	"update"
};

about : con "Generate keys and\n" + 
	    "request certificate for\n" +
	    "mounting remote server";


init(ctxt: ref Draw->Context, nil: list of string)
{
	sys = load Sys Sys->PATH;
	if (ctxt == nil) {
		sys->fprint(sys->fildes(2), "getauthinfo: no window context\n");
		raise "fail:bad context";
	}
	kr = load Keyring Keyring->PATH;
	str := load String String->PATH;

	draw = load Draw Draw->PATH;
	tk = load Tk Tk->PATH;

	tkclient = load Tkclient Tkclient->PATH;
	dialog = load Dialog Dialog->PATH;
	tkclient->init();
	dialog->init();

	(top, wmctl) := tkclient->toplevel(ctxt, "",
		"Obtain Certificate for Server", Tkclient->Help);
	for (c:=0; c<len cfg; c++)
		tk->cmd(top, cfg[c]);
	cmd := chan of string;
	tk->namechan(top, cmd, "cmd");

	login = load Login Login->PATH;
	if(login == nil){
		dialog->prompt(ctxt, top.image, "error -fg red", "Error", 
			"Cannot load " + Login->PATH, 0, "Exit"::nil);
		exit;
	}

	# start interactive
	usr := user();
	passwd := "";
	signer := defaultsigner();
	dir:= "";
	file := "net!";
	path := "";
	tk->cmd(top, ".u.e insert end '" + usr);
	tk->cmd(top, ".s.e insert end '" + signer);
	tk->cmd(top, "update");
	tkclient->onscreen(top, nil);
	tkclient->startinput(top, "kbd"::"ptr"::nil);
	info : ref Keyring->Authinfo;
	for(;;){
		alt {
		s := <-top.ctxt.kbd =>
			tk->keyboard(top, s);
		s := <-top.ctxt.ptr =>
			tk->pointer(top, *s);
		s := <-top.ctxt.ctl or
		s = <-top.wreq =>
			tkclient->wmctl(top, s);
		menu := <-wmctl =>
			case menu {
			"exit" =>
				exit;
			"help" =>
				dialog->prompt(ctxt, top.image, "info -fg green", "About", 
				  about, 0, "OK"::nil);
			}
			tkclient->wmctl(top, menu);
		rdy := <-cmd =>
			case (rdy[0]) {
			'u' =>
				usr = tk->cmd(top, ".u.e get");
				if(usr == "")
					tk->cmd(top, "focus .u.e; update");
				else {
					dir = "/usr/" + usr + "/keyring/";
					path = dir + file;
					tk->cmd(top, ".f.e delete 0 end");
					tk->cmd(top, ".f.e insert end '" + path);
					tk->cmd(top, "focus .p.e; update");
				}
				continue;
			'p' =>
				passwd = tk->cmd(top, ".p.e get");	
				if(passwd == "")
					tk->cmd(top, "focus .p.e; update");
				else
					tk->cmd(top, "focus .s.e; update");
				continue;
			's' =>
				signer = tk->cmd(top, ".s.e get");
				if(signer == "")
					tk->cmd(top, "focus .s.e");
				else {
					file = "net!" + signer;
					path = dir + file;
					tk->cmd(top, ".f.e delete 0 end");
					tk->cmd(top, ".f.e insert end " + path);
					tk->cmd(top, "focus .f.e; update");
				}
				continue;
			'f' =>
				path = tk->cmd(top, ".f.e get");
				if(path == "") {
					tk->cmd(top, "focus .f.e; update");
					continue;
				}

				# start encrypt key exchange
				addr := "net!"+signer+"!inflogin";
				tk->cmd(top, "cursor -bitmap cursor.wait");
				err: string;	
				(err, info) = login->login(usr, passwd, addr);
				tk->cmd(top, "cursor -default");
				if(info == nil){
					dialog->prompt(ctxt, top.image, "warning -fg yellow", "Warning", 
						err, 0, "Continue"::nil);
					tk->cmd(top, ".p.e delete 0 end");
					tk->cmd(top, "focus .p.e");
					continue;
				}

				# save the info for later access
				save := tk->cmd(top, "variable save");
				(dir, file) = str->splitr(path, "/");
				if(save[0] == 't')
					spawn save2file(dir, file);

				tk->cmd(top, "cursor -default");			
				if(kr->writeauthinfo(path, info) < 0){
					dialog->prompt(ctxt, top.image, "error -fg red", "Error", 
						"Can't write to " + path, 0, "Exit"::nil);
					exit;
				}	
				if(save[0] == 'p')
					dialog->prompt(ctxt, top.image, "info -fg green", "Notice", 
						"Authentication information is\nsaved in file:\n" 
						+ path, 0, "OK"::nil);
				else
					dialog->prompt(ctxt, top.image, "info -fg green", "Notice", 
						"Authentication information is\nheld in a temporary file:\n" 
						+ path, 0, "OK"::nil);

				return;

			}
		}
	}
}


user(): string
{
	sys = load Sys Sys->PATH;

	fd := sys->open("/dev/user", sys->OREAD);
	if(fd == nil)
		return "";

	buf := array[Sys->NAMEMAX] of byte;
	n := sys->read(fd, buf, len buf);
	if(n < 0)
		return "";

	return string buf[0:n];	
}

save2file(dir, file: string)
{
	if(sys->bind("#s", dir, Sys->MBEFORE) < 0)
		exit;
	fileio := sys->file2chan(dir, file);
	if(fileio != nil)
		exit;

	sys->pctl(Sys->NEWPGRP, nil);

	infodata := array[0] of byte;

	for(;;) alt {
	(off, nbytes, fid, rc) := <-fileio.read =>
		if(rc == nil)
			break;
		if(off > len infodata){
			rc <-= (infodata[off:off], nil);
		} else {
			if(off + nbytes > len infodata)
				nbytes = len infodata - off;
			rc <-= (infodata[off:off+nbytes], nil);
		}

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
		data = nil;
	}
}

# get default signer server name
defaultsigner(): string
{
	return "$SIGNER";
}
