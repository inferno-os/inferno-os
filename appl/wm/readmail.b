implement WmReadmail;

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

include "string.m";
	str: String;

include "keyring.m";
	kr: Keyring;

WmReadmail: module
{
	init:	fn(ctxt: ref Draw->Context, args: list of string);
};

WmSendmail: module
{
	init:	fn(ctxt: ref Draw->Context, args: list of string);
};

srv: Sys->Connection;
main: ref Toplevel;
ctxt: ref Context;
nmesg: int;
cmesg: int;
map: array of byte;
Ok, Deleted: con iota;
username: string;

mail_cfg := array[] of {
	"frame .top",
	"label .top.l -bitmap email.bit",
	"frame .top.con",
	"frame .top.con.b",
	"button .top.con.b.con -bitmap mailcon -command {send msg connect}",
	"bind .top.con.b.con <Enter> +{.top.status configure -text {connect/disconnect to mail server}}",
	"button .top.con.b.next -bitmap mailnext -command {send msg next}",
	"bind .top.con.b.next <Enter> +{.top.status configure -text {next message}}",
	"button .top.con.b.prev -bitmap mailprev -command {send msg prev}",
	"bind .top.con.b.prev <Enter> +{.top.status configure -text {previous message}}",
	"button .top.con.b.del -bitmap maildel -command {send msg dele}",
	"bind .top.con.b.del <Enter> +{.top.status configure -text {delete message}}",
	"button .top.con.b.reply -bitmap mailreply -command {send msg reply}",
	"bind .top.con.b.reply <Enter> +{.top.status configure -text {reply to message}}",
	"button .top.con.b.fwd -bitmap mailforward",
	"bind .top.con.b.fwd <Enter> +{.top.status configure -text {forward message}}",
	"button .top.con.b.hdr -bitmap mailhdr -command {send msg hdrs}",
	"bind .top.con.b.hdr <Enter> +{.top.status configure -text {fetch message headers}}",
	"button .top.con.b.save -bitmap mailsave -command {send msg save}",
	"bind .top.con.b.save <Enter> +{.top.status configure -text {save message}}",
	"pack .top.con.b.con .top.con.b.prev .top.con.b.next .top.con.b.del .top.con.b.reply .top.con.b.fwd .top.con.b.hdr .top.con.b.save -padx 2 -side left",
	"label .top.status -text {not connected ...} -anchor w",
	"pack .top.l -side left",
	"pack .top.con -side left -padx 10",
	"pack .top.con.b .top.status -in .top.con -fill x -expand 1",
	"frame .hdr",
	"scrollbar .hdr.scroll -command {.hdr.t yview}",
	"text .hdr.t -height 3c -yscrollcommand {.hdr.scroll set} -bg white",
	"frame .hdr.pad -width 2c",
	"pack .hdr.t -side left -fill x -expand 1",
	"pack .hdr.scroll -side left -fill y",
	"pack .hdr.pad",
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
	"label .l.s -text {Secret:} -anchor w",
	"pack .l.h .l.u .l.s -fill both -expand 1",
	"frame .e",
	"entry .e.h",
	"entry .e.u",
	"entry .e.s -show •",
	"pack .e.h .e.u .e.s -fill x",
	"frame .f -borderwidth 2 -relief raised",
	"pack .l .e -fill both -expand 1 -side left -in .f",
	"pack .f",
	"pack .b -fill x -expand 1",
	"bind .e.h <Key-\n> {send cmd ok}",
	"bind .e.u <Key-\n> {send cmd ok}",
	"bind .e.s <Key-\n> {send cmd ok}",
	"focus .e.s",
};

hdr_cfg := array[] of {
	"scrollbar .sh -orient horizontal -command {.f.l xview}",
	"scrollbar .f.sv -command {.f.l yview}",
	"frame .f",
	"listbox .f.l -width 80w -height 20h -yscrollcommand { .f.sv set} -xscrollcommand { .sh set}",
	"pack .f.l -side left -fill both -expand 1",
	"pack .f.sv -side left -fill y",
	"pack .f -fill both -expand 1",
	"pack .sh -fill x",
	"pack propagate . 0",
	"bind .f.l <Double-Button> { send tomain [.f.l get [.f.l curselection]] }",
	"update",
};

init(xctxt: ref Context, argv: list of string)
{
	sys = load Sys Sys->PATH;
	if (xctxt == nil) {
		sys->fprint(sys->fildes(2), "readmail: no window context\n");
		raise "fail:bad context";
	}
	draw = load Draw Draw->PATH;
	tk = load Tk Tk->PATH;
	tkclient = load Tkclient Tkclient->PATH;
	dialog = load Dialog Dialog->PATH;
	selectfile = load Selectfile Selectfile->PATH;
	str = load String String->PATH;
	kr = load Keyring Keyring->PATH;

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

	titlectl := chan of string;
	(main, titlectl) = tkclient->toplevel(ctxt, tkargs, "Readmail: Reader", Tkclient->Appl);

	msg := chan of string;
	tk->namechan(main, msg, "msg");
	hdr := chan of string;

	for (c:=0; c<len mail_cfg; c++)
		tk->cmd(main, mail_cfg[c]);
	tkclient->onscreen(main, nil);
	tkclient->startinput(main, "kbd"::"ptr"::nil);

	for(;;) alt {
		s := <-main.ctxt.kbd =>
			tk->keyboard(main, s);
		s := <-main.ctxt.ptr =>
			tk->pointer(main, *s);
		s := <-main.ctxt.ctl or
		s = <-main.wreq or
		s = <-titlectl =>
			if(s == "exit") {
				if(srv.dfd != nil) {
					status("Updating mail box...");
					pop3cmd("QUIT");
				}
				return;
			}
			tkclient->wmctl(main, s);
	cmd := <-msg =>
		case cmd {
		"connect" =>
			if(srv.dfd == nil) {
				connect(main);
				if(srv.dfd != nil)
					initialize();
				break;
			}
			disconnect();
		"prev" =>
			if(cmesg > nmesg) {
				status("no more messages.");
				break;
			}
			for(new := cmesg+1; new <= nmesg; new++) {
				if(map[new] == byte Ok) {
					cmesg = new;
					loadmesg();
					break;
				}
			}
		"next" =>
			for(new := cmesg-1; new >= 1; new--) {
				if(map[new] == byte Ok) {
					cmesg = new;
					loadmesg();
					break;
				}
			}
		"dele" =>
			delete();
			if(cmesg > 0) {
				cmesg--;
				loadmesg();
			}
		"hdrs" =>
			headers(hdr);
		"save" =>
			save();
		"reply" =>
			reply();
		}
	get := <-hdr =>
		new := int get;
		if(new < 1 || new > nmesg || map[new] != byte Ok)
			break;		
		cmesg = new;
		loadmesg();
	}
}

headers(tomain: chan of string)
{
	(hdr, hdrctl) := tkclient->toplevel(ctxt, nil,
				"Readmail: Headers", Tkclient->Appl);

	tk->namechan(hdr, tomain, "tomain");

	for (c:=0; c<len hdr_cfg; c++)
		tk->cmd(hdr, hdr_cfg[c]);

	for(i := 1; i <= nmesg; i++) {
		if(map[i] == byte Deleted) {
			info := sys->sprint("%4d ...Deleted...\n", i);
			tk->cmd(hdr, ".f.l insert 0 '"+info);
			continue;
		}
		if(topit(hdr, i) == 0)
			break;
		alt {
		s := <-hdrctl =>
			if(s == "exit")
				return;
			tkclient->wmctl(hdr, s);
		* =>
			;
		}
		if((i%10) == 9)
			tk->cmd(hdr, "update");
	}
	tk->cmd(hdr, "update");
	tkclient->onscreen(hdr, nil);
	tkclient->startinput(hdr, "kbd"::"ptr"::nil);

	spawn hproc(hdrctl, hdr);
}

trunc(name: string): string
{
	for(i := 0; i < len name; i++)
		if(name[i] == '<')
			break;
	i++;
	if(i >= len name)
		return name;
	for(j := i; j < len name; j++)
		if(name[j] == '>')
			break;
	return name[i:j];
}

topit(hdr: ref Toplevel, msg: int): int
{
	(err, s) := pop3cmd("TOP "+string msg+" 0");
	if(err != nil) {
		dialog->prompt(ctxt, hdr.image, "error -fg red", "POP3 Error",
				"Ecountered a problem fetching headers\n"+err,
				0, "Dismiss"::nil);
		return 0;
	}

	size := int s;
	b := pop3body(size);
	if(b == nil)
		return 0;

	from := getfield("from", b);
	from = trunc(from);
	date := getfield("date", b);
	subj := getfield("subject", b);
	if(len subj > 20)
		subj = subj[0:19];

	if(len subj > 0)
		info := sys->sprint("%4d %5d %s \"%s\" %s", msg, size, from, subj, date);
	else
		info = sys->sprint("%4d %5d %s %s", msg, size, from, date);

	tk->cmd(hdr, ".f.l insert 0 '"+info);
	return 1;
}

mapdown(b: array of byte): string
{
	lb := len b;
	l := array[lb] of byte;
	for(i := 0; i < lb; i++) {
		c := b[i];
		if(c >= byte 'A' && c <= byte 'Z')
			c += byte('a' - 'A');
		l[i] = c;
	}
	return string l;	
}

getfield(key: string, text: array of byte): string
{
	key[len key] = ':';
	lk := len key;
	cl := byte key[0];
	cu := cl - byte ('a' - 'A');

	lc: byte;
	for(i := 0; i < len text - lk; i++) {
		t := text[i];
		if(t == byte '\n' && lc == byte '\n')		# end header
			break;
		lc = t;
		if(t != cu && t != cl)
			continue;
		if(key == mapdown(text[i:i+lk])) {
			i += lk+1;
			for(j := i+1; j < len text; j++) {
				c := text[j];
				if(c == byte '\r' || c == byte '\n')
					break;
			}
			return string text[i:j];
		}
	}
	return "";
}

hproc(wmctl: chan of string, top: ref Toplevel)
{
	for(;;) {
		alt {
		s := <-top.ctxt.kbd =>
			tk->keyboard(top, s);
		s := <-top.ctxt.ptr =>
			tk->pointer(top, *s);
		s := <-top.ctxt.ctl or
		s = <-top.wreq or
		s = <-wmctl =>
			if(s == "exit")
				return;
			tkclient->wmctl(top, s);
		}
	}
}

reply()
{
	if(cmesg == 0) {
		dialog->prompt(ctxt, main.image, "error -fg red", "Reply",
					"No message to reply to",
					0, "Abort"::nil);
		return;
	}

	hdr := tk->cmd(main, ".hdr.t get 1.0 end");
	if(hdr == "") {
		dialog->prompt(ctxt, main.image, "error -fg red", "Reply",
					"Mail has no header to reply to",
					0, "Abort"::nil);
		return;
	}

	wmsender := load WmSendmail "/dis/wm/sendmail.dis";
	if(wmsender == nil) {
		dialog->prompt(ctxt, main.image, "error -fg red", "Reply",
				"Failed to load mail sender:\n"+sys->sprint("%r"),
				0, "Abort"::nil);
		return;
	}

	spawn wmsender->init(ctxt, "sendmail" :: hdr :: nil);
}

save()
{
	if(cmesg == 0) {
		dialog->prompt(ctxt, main.image, "error -fg red", "Save",
				"No current message",
				0, "Continue"::nil);
		return;
	}
	pat := list of {
		"*.let (Saved mail)",
		"* (All files)"
	};

	fd: ref Sys->FD;
	fname: string;
	for(;;) {
		fname = selectfile->filename(ctxt, main.image, "Save in Mailbox",
					pat, "/usr/"+username+"/mail");
		if(fname == nil)
			return;

		fd = sys->create(fname, sys->OWRITE, 8r660);
		if(fd != nil)
			break;

		labs := list of {
			"New name",
			"Abort"
		};

		r := dialog->prompt(ctxt, main.image, "error -fg red", "Save",
				"Failed to create "+sys->sprint("%s\n%r", fname),
				0, labs);
		if(r == 1)
			return;
	}
	s := tk->cmd(main, ".hdr.t get 1.0 end");
	b := array of byte s;
	r := sys->write(fd, b, len b);
	if(r < 0) {
		dialog->prompt(ctxt, main.image, "error -fg red", "Save",
				"Error writing file"+sys->sprint("%s\n%r", fname),
				0, "Continue (not saved)":: nil);
		return;
	}
	s = tk->cmd(main, ".body.t get 1.0 end");
	b = array of byte s;
	n := sys->write(fd, b, len b);
	if(n < 0) {
		dialog->prompt(ctxt, main.image, "error -fg red", "Save",
				"Error writing file"+sys->sprint("%s\n%r", fname),
				0, "Continue (not saved)":: nil);
		return;
	}
	status("wrote "+string(n+r)+" bytes.");
}

delete()
{
	if(srv.dfd == nil) {
		dialog->prompt(ctxt, main.image, "warning -fg yellow", "Delete",
				"You must be connected to delete messages",
				0, "Continue"::nil);
		return;
	}
	(err, s) := pop3cmd("DELE "+string cmesg);
	if(err != nil) {
		dialog->prompt(ctxt, main.image, "error -fg red", "Delete",
				"Encountered POP3 problem during delete\n"+err,
				0, "Continue"::nil);
		return;
	}
	map[cmesg] = byte Deleted;
	status(s);
}

status(msg: string)
{
	tk->cmd(main, ".top.status configure -text {"+msg+"}; update");
}

disconnect()
{
	(err, s) := pop3cmd("QUIT");
	srv.dfd = nil;
	tk->cmd(main, ".top.con configure -text Connect");
	if(err != nil) {
		dialog->prompt(ctxt, main.image, "error -fg red", "Disconnect",
				"POP3 protocol problem\n"+err,
				0, "Proceed"::nil);
		return;
	}
	status(s);
}

connect(parent: ref Toplevel)
{
	(t, conctl) := tkclient->toplevel(ctxt, postposn(parent),
				"Connection Parameters", 0);

	cmd := chan of string;
	tk->namechan(t, cmd, "cmd");

	for (c:=0; c<len con_cfg; c++)
		tk->cmd(t, con_cfg[c]);

	username = rf("/dev/user");
	sv := rf("/usr/"+username+"/mail/popserver");
	if(sv != "")
		tk->cmd(t, ".e.h insert 0 '"+sv);

	u := tk->cmd(t, ".e.u get");
	if(u == "")
		tk->cmd(t, ".e.u insert 0 '"+username);

	tk->cmd(t, "update");
	tkclient->onscreen(t, nil);
	tkclient->startinput(t, "kbd"::"ptr"::nil);

	for(;;) alt {
	s := <-t.ctxt.kbd =>
		tk->keyboard(t, s);
	s := <-t.ctxt.ptr =>
		tk->pointer(t, *s);
	s := <-t.ctxt.ctl or
	s = <-t.wreq or
	s = <-conctl =>
		if(s == "exit")
			return;
		tkclient->wmctl(t, s);
	s := <-cmd =>
		if(s == "can")
			return;
		server := tk->cmd(t, ".e.h get");
		if(server == "") {
			dialog->prompt(ctxt, t.image, "error -fg red", "Connect",
					"You must supply a server address",
					0, "Proceed"::nil);
			break;
		}
		user := tk->cmd(t, ".e.u get");
		if(user == "") {
			dialog->prompt(ctxt, t.image, "error -fg red", "Connect",
					"You must supply a user name",
					0, "Proceed"::nil);
			break;
		}
		pass := tk->cmd(t, ".e.s get");
		if(pass == "") {
			dialog->prompt(ctxt, t.image, "error -fg red", "Connect",
					"You must give a secret or password",
					0, "Proceed"::nil);
			break;
		}
		if(dialer(t, server, user, pass) != 0)
			return;
		status("not connected");
	}
	srv.dfd = nil;
}

initialize()
{
	(err, s) := pop3cmd("STAT");
	if(err != nil) {
		dialog->prompt(ctxt, main.image, "error -fg red", "Mailbox Status",
				"The following error occurred while "+
				    "checking your mailbox:\n"+err,
				0, "Dismiss"::nil);
		srv.dfd = nil;
		status("not connected");
		return;
	}

	tk->cmd(main, ".top.con configure -text Disconnect; update");
	nmesg = int s;
	if(nmesg == 0) {
		status("There are no messages.");
		return;
	}

	map = array[nmesg+1] of byte;
	for(i := 0; i <= nmesg; i++)
		map[i] = byte Ok;

	s = "";
	if(nmesg > 1)
		s = "s";
	status("You have "+string nmesg+" message"+s);
	cmesg = nmesg;
	loadmesg();
}

loadmesg()
{
	if(srv.dfd == nil) {
		dialog->prompt(ctxt, main.image, "warning -fg yellow", "Read",
				"You must be connected to read messages",
				0, "Continue"::nil);
		return;
	}
	(err, s) := pop3cmd("RETR "+sys->sprint("%d", cmesg));
	if(err != nil) {
		dialog->prompt(ctxt, main.image, "error -fg red", "Read",
				"Error retrieving message:\n"+err,
				0, "Continue"::nil);
		return;
	}

	tk->cmd(main, ".hdr.t delete 1.0 end; .body.t delete 1.0 end");
	size := int s;

	status("reading "+string size+" bytes ...");

	b := pop3body(size);

	(headr, body) := split(string b);
	b = nil;
	tk->cmd(main, ".hdr.t insert end '"+headr);
	tk->cmd(main, ".body.t insert end '"+body);
	tk->cmd(main, ".hdr.t see 1.0; .body.t see 1.0");
	status("read message "+string cmesg+" of "+string nmesg+" , ready...");
}

split(text: string): (string, string)
{
	c, lc: int;
	hdr, body: string;

	hp := 0;
	for(i := 0; i < len text; i++) {
		c = text[i];
		if(c == '\r')
			continue;
		hdr[hp++] = c;
		if(lc == '\n' && c == '\n')
			break;
		lc = c;
	}
	bp := 0;
	while(i < len text) {
		c = text[i++];
		if(c != '\r')
			body[bp++] = c;
	}
	return (hdr, body);
}

dialer(t: ref Toplevel, server, user, pass: string): int
{
	ok: int;

	for(;;) {
		status("dialing server...");
		(ok, srv) = sys->dial(netmkaddr(server, nil, "110"), nil);
		if(ok >= 0)
			break;

			labs := list of {
				"Retry",
				"Cancel"
			};
			ok = dialog->prompt(ctxt, t.image, "error -fg", "Connect",
					"The following error occurred while\n"+
					 "dialing the server: "+sys->sprint("%r"),
					0, labs);
			if(ok != 0)
				return 0;
	}
	status("connected...");
	(err, s) := pop3resp();
	if(err != nil) {
		dialog->prompt(ctxt, t.image, "error -fg red", "Connect",
				 "An error occurred during sign on.\n"+err,
				0, "Proceed"::nil);
		return 0;
	}
	status(s);
	(nil, s) = str->splitl(s, "<");
	(chal, nil) := str->splitr(s, ">");
	if(chal != nil){
		ca := array of byte chal;
		digest := array[kr->MD5dlen] of byte;
		md5state := kr->md5(ca, len ca, nil, nil);
		pa := array of byte pass;
		kr->md5(pa, len pa, digest, md5state);
		s = nil;
		for(i := 0; i < kr->MD5dlen; i++)
			s  += sys->sprint("%2.2ux", int digest[i]);
		(err, s) = pop3cmd("APOP "+user+" "+s);
		if(err == nil) {
			status("ready to serve...");
			return 1;
		} else {
			dialog->prompt(ctxt, t.image, "error -fg red", "Connect",
				 "Challenge/response failed.\n"+err,
				0, "Proceed"::nil);
			return 0;
		}
	}
	(err, s) = pop3cmd("USER "+user);
	if(err != nil) {
		dialog->prompt(ctxt, t.image, "error -fg red", "Connect",
				 "An error occurred during login.\n"+err,
				0, "Proceed"::nil);
		return 0;
	}
	(err, s) = pop3cmd("PASS "+pass);
	if(err != nil) {
		dialog->prompt(ctxt, t.image, "error -fg red", "Connect",
				 "An error occurred during login.\n"+err,
				0, "Proceed"::nil);
		return 0;
	}
	status("ready to serve...");
	return 1;
}

rf(file: string): string
{
	fd := sys->open(file, sys->OREAD);
	if(fd == nil)
		return "";

	buf := array[Sys->NAMEMAX] of byte;
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

#
# Talk POP3
#
pop3cmd(cmd: string): (string, string)
{
	cmd += "\r\n";
#	sys->print("->%s", cmd);
	b := array of byte cmd;
	l := len b;
	n := sys->write(srv.dfd, b, l);
	if(n != l)
		return ("send to server:"+sys->sprint("%r"), nil);

	return pop3resp();
}

pop3resp(): (string, string)
{
	s := "";
	i := 0;
	lastc := 0;
	for(;;) {
		c := pop3getc();
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
	if(s[0:3] == "+OK") {
		i = 3;
		while(i < len s && s[i] == ' ')
			i++;
		return (nil, s[i:]);
	}
	if(s[0:4] == "-ERR") {
		i = 4;
		while(s[i] == ' ' && i < len s)
			i++;
		return (s[i:], nil);
	}
	return ("invalid server response", nil);
}

pop3body(size: int): array of byte
{
	size += 512;
	b := array[size] of byte;

	cnt := emptypopbuf(b);
	size -= cnt;

	for(;;) {

		if(cnt > 5 && string b[cnt-5:cnt] == "\r\n.\r\n") {
			b = b[0:cnt-5];
			break;
		}
		# resize buffer
		if(size == 0) {
			nb := array[len b + 4096] of byte;
			nb[0:] = b;
			size = len nb - len b;
			b = nb;
			nb = nil;
		}
		n := sys->read(srv.dfd, b[cnt:], len b - cnt);
		if(n <= 0) {
			dialog->prompt(ctxt, main.image, "error -fg red", "Read",
				sys->sprint("Error retrieving message: %r"),
					0, "Continue"::nil);
			return nil;
		}
		size -= n;
		cnt += n;
	}
	return b;
}

Iob: adt
{
	nbyte:	int;
	posn:	int;
	buf:	array of byte;
};
popbuf: Iob;

pop3getc(): int
{
	if(popbuf.nbyte > 0) {
		popbuf.nbyte--;
		return int popbuf.buf[popbuf.posn++];
	}
	if(popbuf.buf == nil)
		popbuf.buf = array[512] of byte;

	popbuf.posn = 0;
	n := sys->read(srv.dfd, popbuf.buf, len popbuf.buf);
	if(n < 0)
		return -1;

	popbuf.nbyte = n-1;
	return int popbuf.buf[popbuf.posn++];
}

emptypopbuf(a: array of byte) : int
{
	i := popbuf.nbyte;

	if (i) {
		a[0:] = popbuf.buf[popbuf.posn:(popbuf.posn+popbuf.nbyte)];
		popbuf.nbyte = 0;
	}
	
	return i;
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
