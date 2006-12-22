implement WmSendmail;

include "sys.m";
	sys: Sys;

include "draw.m";
	draw: Draw;
	Context: import draw;

include "tk.m";
	tk: Tk;
	Toplevel: import tk;

include "tkclient.m";
	tkclient: Tkclient;

include "dialog.m";
	dialog: Dialog;

include "selectfile.m";
	selectfile: Selectfile;

WmSendmail: module
{
	init:	fn(ctxt: ref Draw->Context, args: list of string);
};

srv: Sys->Connection;
main: ref Toplevel;
ctxt: ref Context;
username: string;

mail_cfg := array[] of {
	"frame .top",
	"label .top.l -bitmap email.bit",
	"frame .top.con",
	"frame .top.con.b",
	"button .top.con.b.con -bitmap mailcon -command {send msg connect}",
	"bind .top.con.b.con <Enter> +{.top.status configure -text {connect/disconnect to mail server}}",
	"button .top.con.b.send -bitmap maildeliver -command {send msg send}",
	"bind .top.con.b.send <Enter> +{.top.status configure -text {deliver mail}}",

	"button .top.con.b.nocc -bitmap mailnocc -command {.hdr.e.cc delete 0 end}",
	"bind .top.con.b.nocc <Enter> +{.top.status configure -text {no carbon copy}}",

	"button .top.con.b.new -bitmap mailnew -command {send msg new}",
	"bind .top.con.b.new <Enter> +{.top.status configure -text {start a new message}}",
	"button .top.con.b.save -bitmap mailsave -command {send msg save}",
	"bind .top.con.b.save <Enter> +{.top.status configure -text {save message}}",
	"pack .top.con.b.con .top.con.b.send .top.con.b.nocc .top.con.b.new .top.con.b.save -padx 2 -side left",
	"label .top.status -text {not connected ...} -anchor w",
	"pack .top.l -side left",
	"pack .top.con -side left -padx 10",
	"pack .top.con.b .top.status -in .top.con -fill x -expand 1",
	"frame .hdr",
	"frame .hdr.l",
	"frame .hdr.e",
	"label .hdr.l.mt -text {Mail To:}",
	"label .hdr.l.cc -text {Mail CC:}",
	"label .hdr.l.sb -text {Subject:}",
	"pack .hdr.l.mt .hdr.l.cc .hdr.l.sb -fill y -expand 1",
	"entry .hdr.e.mt -bg white",
	"entry .hdr.e.cc -bg white",
	"entry .hdr.e.sb -bg white",
	"bind .hdr.e.mt <Key-\n> {}",
	"bind .hdr.e.cc <Key-\n> {}",
	"bind .hdr.e.sb <Key-\n> {}",
	"pack .hdr.e.mt .hdr.e.cc .hdr.e.sb -fill x -expand 1",
	"pack .hdr.l -side left -fill y",
	"pack .hdr.e -side left -fill x -expand 1",
	"frame .body",
	"scrollbar .body.scroll -command {.body.t yview}",
	"text .body.t -width 15c -height 7c -yscrollcommand {.body.scroll set} -bg white",
	"pack .body.t -side left -expand 1 -fill both",
	"pack .body.scroll -side left -fill y",
	"pack .top -anchor w -padx 5",
	"pack .hdr -fill x -anchor w -padx 5 -pady 5",
	"pack .body -expand 1 -fill both -padx 5 -pady 5",
	"pack .b -padx 5 -pady 5 -fill x",
	"pack propagate . 0",
	"update"
};

con_cfg := array[] of {
	"frame .b",
	"button .b.ok -text {Connect} -command {send cmd ok}",
	"button .b.can -text {Cancel} -command {send cmd can}",
	"pack .b.ok .b.can -side left -fill x -padx 10 -pady 10 -expand 1",
	"frame .l",
	"label .l.h -text {Mail Server:} -anchor w",
	"label .l.u -text {User Name:} -anchor w",
	"pack .l.h .l.u -fill both -expand 1",
	"frame .e",
	"entry .e.h -width 30w",
	"entry .e.u -width 30w",
	"pack .e.h .e.u -fill x",
	"frame .f -borderwidth 2 -relief raised",
	"pack .l .e -fill both -expand 1 -side left -in .f",
	"bind .e.h <Key-\n> {send cmd ok}",
	"bind .e.u <Key-\n> {send cmd ok}",
};

con_pack := array[] of {
	"pack .f",
	"pack .b -fill x -expand 1",
	"focus .e.u",
	"update",
};

new_cmd := array[] of {
	".hdr.e.mt delete 0 end",
	".hdr.e.cc delete 0 end",
	".hdr.e.sb delete 0 end",
	".body.t delete 1.0 end",
	".body.t see 1.0",
	"update"
};

init(xctxt: ref Context, argv: list of string)
{
	sys = load Sys Sys->PATH;
	if (xctxt == nil) {
		sys->fprint(sys->fildes(2), "sendmail: no window context\n");
		raise "fail:bad context";
	}
	draw = load Draw Draw->PATH;
	tk = load Tk Tk->PATH;
	tkclient = load Tkclient Tkclient->PATH;
	dialog = load Dialog Dialog->PATH;
	selectfile = load Selectfile Selectfile->PATH;

	ctxt = xctxt;

	tkclient->init();
	dialog->init();
	selectfile->init();

	tkargs := "";
	argv = tl argv;
	if(argv != nil) {
		tkargs = hd argv;
		argv = tl argv;
	}

	titlectl: chan of string;
	(main, titlectl) = tkclient->toplevel(ctxt, tkargs,
				"MailStop: Sender", Tkclient->Appl);

	msg := chan of string;
	tk->namechan(main, msg, "msg");

	for (c:=0; c<len mail_cfg; c++)
		tk->cmd(main, mail_cfg[c]);
	tkclient->onscreen(main, nil);
	tkclient->startinput(main, "kbd"::"ptr"::nil);

	if(argv != nil)
		fromreadmail(hd argv);

	for(;;) alt {
		s := <-main.ctxt.kbd =>
			tk->keyboard(main, s);
		s := <-main.ctxt.ptr =>
			tk->pointer(main, *s);
		s := <-main.ctxt.ctl or
		s = <-main.wreq or
		s = <-titlectl =>
		if(s == "exit") {
			if(srv.dfd == nil)
				return;
			status("Closing connection...");
			smtpcmd("QUIT");
			return;
		}
		tkclient->wmctl(main, s);
	cmd := <-msg =>
		case cmd {
		"connect" =>
			if(srv.dfd == nil) {
				connect(main, 1);
				fixbutton();
				break;
			}
			disconnect();
		"save" =>
			save();
		"send" =>
			sendmail();
		"new" =>
			for (c=0; c<len new_cmd; c++)
				tk->cmd(main, new_cmd[c]);
		}
	}
}

fixbutton()
{
	s := "Connect";
	if(srv.dfd != nil)
		s = "Disconnect";

	tk->cmd(main, ".top.con configure -text "+s+"; update");
}

sendmail()
{
	if(srv.dfd == nil) {
		dialog->prompt(ctxt, main.image, "error -fg red", "Send",
				"You must be connected to deliver mail",
				0, "Continue"::nil);
		return;
	}

	mto := tk->cmd(main, ".hdr.e.mt get");
	if(mto == "") {
		dialog->prompt(ctxt, main.image, "error -fg red", "Send",
				"You must fill in the \"Mail To\" entry",
				0, "Continue (nothing sent)"::nil);
		return;
	}

	if(tk->cmd(main, ".body.t index end") == "1.0") {
		opt := "Cancel" :: "Send anyway" :: nil;
		if(dialog->prompt(ctxt, main.image, "warning -fg yellow", "Send",
				"The body of the mail is empty", 0, opt) == 0)
			return;
	}

	(err, s) := smtpcmd("MAIL FROM:<"+username+">");
	if(err != nil) {
		dialog->prompt(ctxt, main.image, "error -fg red", "Send",
				"Failed to specify FROM correctly:\n"+err,
				0, "Continue (nothing sent)"::nil);
		return;
	}
	status(s);
	(err, s) = smtpcmd("RCPT TO:<"+mto+">");
	if(err != nil) {
		dialog->prompt(ctxt, main.image, "error -fg red", "Send",
				"Failed to specify TO correctly:\n"+err,
				0, "Continue (nothing sent)"::nil);
		return;
	}
	status(s);
	cc := tk->cmd(main, ".hdr.e.cc get");
	if(cc != nil) {
		(nil, l) := sys->tokenize(cc, "\t ,");
		while(l != nil) {
			copy := hd l;
			(err, s) = smtpcmd("RCPT TO:<"+copy+">");
			if(err != nil) {
				dialog->prompt(ctxt, main.image, "error -fg red", "Send",
					"Carbon copy to "+copy+"failed:\n"+err,
					0, "Continue (nothing sent)"::nil);
			}
		}
	}
	(err, s) = smtpcmd("DATA");
	if(err != nil) {
		dialog->prompt(ctxt, main.image, "error -fg red", "Send",
				"Failed to enter DATA mode:\n"+err,
				0, "Continue (nothing sent)"::nil);
		return;
	}

	sub := tk->cmd(main, ".hdr.e.sb get");
	if(sub != nil)
		sys->fprint(srv.dfd, "Subject: %s\n", sub);

	b := array of byte tk->cmd(main, ".body.t get 1.0 end");
	n := sys->write(srv.dfd, b, len b);
	b = nil;
	if(n < 0) {
		dialog->prompt(ctxt, main.image, "error -fg red", "Send",
				"Error writing server:\n"+sys->sprint("%r"),
				0, "Abort (partial send)"::nil);
		return;
	}
	(err, s) = smtpcmd("\r\n.");
	if(err != nil) {
		dialog->prompt(ctxt, main.image, "error -fg red", "Send",
				"Failed to terminate message:\n"+err,
				0, "Abort (partial send)"::nil);
		return;
	}
	status(s);
}

save()
{
	mto := tk->cmd(main, ".hdr.e.to get");
	if(mto == "") {
		dialog->prompt(ctxt, main.image, "error -fg red", "Save",
				"No message to save",
				0, "Dismiss"::nil);
		return;
	}

	pat := list of {
		"*.letter (Saved mail)",
		"* (All files)"
	};

	fname: string;
	fd: ref Sys->FD;

	for(;;) {
		fname = selectfile->filename(ctxt, main.image, "Save in Mailbox", pat,
					  "/usr/"+rf("/dev/user")+"/mail");
		if(fname == nil)
			return;

		fd = sys->create(fname, sys->OWRITE, 8r660);
		if(fd != nil)
			break;
		r := dialog->prompt(ctxt, main.image, "error -fg red", "Save",
			"Failed to create "+sys->sprint("%s\n%r", fname),
			0, "Retry"::"Cancel"::nil);
		if(r > 0)
			return;
	}

	r := sys->fprint(srv.dfd, "Mail To: %s\n", mto);
	cc := tk->cmd(main, ".hdr.e.cc get");
	if(cc != nil)
		r += sys->fprint(srv.dfd, "Mail CC: %s\n", cc);
	sb := tk->cmd(main, ".hdr.e.sb get");
	if(sb != nil)
		r += sys->fprint(srv.dfd, "Subject: %s\n\n", sb);

	s := tk->cmd(main, ".body.t get 1.0 end");
	b := array of byte s;
	n := sys->write(fd, b, len b);
	if(n < 0) {
		dialog->prompt(ctxt, main.image, "error -fg red", "Save",
			"Error writing file "+sys->sprint("%s\n%r", fname),
			0, "Continue"::nil);
		return;
	}
	status("wrote "+string(n+r)+" bytes.");
}

status(msg: string)
{
	tk->cmd(main, ".top.status configure -text {"+msg+"}; update");
}

disconnect()
{
	(err, s) := smtpcmd("QUIT");
	srv.dfd = nil;
	fixbutton();
	if(err != nil) {
		dialog->prompt(ctxt, main.image, "error -fg red", "Disconnect",
					"Server problem:\n"+err,
				0, "Dismiss"::nil);
		return;
	}
	status(s);
}

connect(parent: ref Toplevel, interactive: int)
{
	(t, conctl) := tkclient->toplevel(ctxt, postposn(parent),
					"Connection Parameters", 0);

	cmd := chan of string;
	tk->namechan(t, cmd, "cmd");

	for (c:=0; c<len con_cfg; c++)
		tk->cmd(t, con_cfg[c]);

	username = rf("/dev/user");
	s := rf("/usr/"+username+"/mail/smtpserver");
	if(s != "")
		tk->cmd(t, ".e.h insert 0 '"+s);

	s = rf("/usr/"+username+"/mail/domain");
	if(s != nil)
		username += "@"+s;

	u := tk->cmd(t, ".e.u get");
	if(u == "")
		tk->cmd(t, ".e.u insert 0 '"+username);

	if(interactive == 0 && checkthendial(t) != 0)
		return;

	for (c=0; c<len con_pack; c++)
		tk->cmd(t, con_pack[c]);
	tkclient->onscreen(t, nil);
	tkclient->startinput(t, "kbd"::"ptr"::nil);

	for(;;) alt {
		ss := <-t.ctxt.kbd =>
			tk->keyboard(t, ss);
		ss := <-t.ctxt.ptr =>
			tk->pointer(t, *ss);
		ss := <-t.ctxt.ctl or
		ss = <-t.wreq or
		ss = <-conctl =>
			if (ss == "exit")
				return;
			tkclient->wmctl(t, ss);
	s = <-cmd =>
		if(s == "can")
			return;
		if(checkthendial(t) != 0)
			return;
		status("not connected");
	}
	srv.dfd = nil;
}

checkthendial(t: ref Toplevel): int
{
	server := tk->cmd(t, ".e.h get");
	if(server == "") {
		dialog->prompt(ctxt, t.image, "error -fg red", "Connect",
				"You must supply a server address",
				0, "Continue"::nil);
		return 0;
	}
	user := tk->cmd(t, ".e.u get");
	if(user == "") {
		dialog->prompt(ctxt, t.image, "error -fg red", "Connect",
				"You must supply a user name",
				0, "Continue"::nil);
		return 0;
	}
	if(dom(user) == "") {
		dialog->prompt(ctxt, t.image, "error -fg red", "Connect",
				"The user name must contain an '@'",
				0, "Continue"::nil);
		return 0;
	}
	return dialer(t, server, user);
}

dialer(t: ref Toplevel, server, user: string): int
{
	ok: int;

	status("dialing server...");
	(ok, srv) = sys->dial(netmkaddr(server, nil, "25"), nil);
	if(ok < 0) {
		dialog->prompt(ctxt, t.image, "error -fg red", "Connect",
				"The following error occurred while\n"+
				 "dialing the server: "+sys->sprint("%r"),
				0, "Continue"::nil);
		return 0;
	}
	status("connected...");
	(err, s) := smtpresp();
	if(err != nil) {
		dialog->prompt(ctxt, t.image, "error -fg red", "Connect",
				"An error occurred during sign on.\n"+err,
				0, "Continue"::nil);
		return 0;
	}
	status(s);
	(err, s) = smtpcmd("HELO "+dom(user));
	if(err != nil) {
		dialog->prompt(ctxt, t.image, "error -fg red", "Connect",
				"An error occurred during login.\n"+err,
				0, "Continue"::nil);
		return 0;
	}
	status("ready to send...");
	return 1;
}

rf(file: string): string
{
	fd := sys->open(file, sys->OREAD);
	if(fd == nil)
		return "";

	buf := array[128] of byte;
	n := sys->read(fd, buf, len buf);
	if(n < 0)
		return "";

	return string buf[0:n];	
}

postposn(parent: ref Toplevel): string
{
	x := int tk->cmd(parent, ".top.con cget -actx");
	y := int tk->cmd(parent, ".top.con cget -acty");
	h := int tk->cmd(parent, ".top.con cget -height");

	return "-x "+string(x-2)+" -y "+string(y+h+2);
}

dom(name: string): string
{
	for(i := 0; i < len name; i++)
		if(name[i] == '@')
			return name[i+1:];
	return nil;
}

fromreadmail(hdr: string)
{
	(nil, l) := sys->tokenize(hdr, "\n");
	while(l != nil) {
		s := hd l;
		l = tl l;
		n := match(s, "subject: ");
		if(n != nil) {
			tk->cmd(main, ".hdr.e.sb insert end '"+n);
			continue;
		}
		n = match(s, "cc: ");
		if(n != nil) {
			tk->cmd(main, ".hdr.e.cc insert end '"+n);
			continue;
		}
		n = match(s, "from: ");
		if(n != nil) {
			n = extract(n);
			tk->cmd(main, ".hdr.e.mt insert end '"+n);
		}
	}
	connect(main, 0);
}

extract(name: string): string
{
	for(i := 0; i < len name; i++) {
		if(name[i] == '<') {
			for(j := i+1; j < len name; j++)
				if(name[j] == '>')
					break;
			return name[i+1:j];
		}
	}
	for(i = 0; i < len name; i++)
		if(name[i] == ' ')
			break;
	return name[0:i];
}

lower(c: int): int
{
	if(c >= 'A' && c <= 'Z')
		c = 'a' + (c - 'A');
	return c;
}

match(text, pat: string): string
{
	for(i := 0; i < len pat; i++) {
		c := text[i];
		p := pat[i];
		if(c != p && lower(c) != p)
			return "";
	}
	return text[i:];
}

#
# Talk SMTP
#
smtpcmd(cmd: string): (string, string)
{
	cmd += "\r\n";
#	sys->print("->%s", cmd);
	b := array of byte cmd;
	l := len b;
	n := sys->write(srv.dfd, b, l);
	if(n != l)
		return ("send to server:"+sys->sprint("%r"), nil);

	return smtpresp();
}

smtpresp(): (string, string)
{
	s := "";
	i := 0;
	lastc := 0;
	for(;;) {
		c := smtpgetc();
		if(c == -1)
			return ("read from server:"+sys->sprint("%r"), nil);
		if(lastc == '\r' && c == '\n')
			break;
		s[i++] = c;
		lastc = c;
	}
#	sys->print("<-%s\n", s);
	if(i < 3)
		return ("short read from server", nil);
	s = s[0:i-1];
	case s[0] {
	'1' or '2' or '3' =>
		i = 3;
		while(s[i] == ' ' && i < len s)
			i++;
		return (nil, s[i:]);
	'4'or '5' =>
		i = 3;
		while(s[i] == ' ' && i < len s)
			i++;
		return (s[i:], nil);
	 * =>
		return ("invalid server response", nil);
	}
}

Iob: adt
{
	nbyte:	int;
	posn:	int;
	buf:	array of byte;
};
smtpbuf: Iob;

smtpgetc(): int
{
	if(smtpbuf.nbyte > 0) {
		smtpbuf.nbyte--;
		return int smtpbuf.buf[smtpbuf.posn++];
	}
	if(smtpbuf.buf == nil)
		smtpbuf.buf = array[512] of byte;

	smtpbuf.posn = 0;
	n := sys->read(srv.dfd, smtpbuf.buf, len smtpbuf.buf);
	if(n < 0)
		return -1;

	smtpbuf.nbyte = n-1;
	return int smtpbuf.buf[smtpbuf.posn++];
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
