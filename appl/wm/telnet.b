implement WmTelnet;

include "sys.m";
	sys: Sys;
	Connection: import sys;

include "draw.m";
	draw: Draw;
	Context: import draw;

include "tk.m";
	tk: Tk;

include "tkclient.m";
	tkclient: Tkclient;

include "dialog.m";
	dialog: Dialog;

WmTelnet: module
{
	init:	fn(ctxt: ref Draw->Context, args: list of string);
};

Iob: adt
{
	fd:	ref Sys->FD;
	t:	ref Tk->Toplevel;
	out:	cyclic ref Iob;
	buf:	array of byte;
	ptr:	int;
	nbyte:	int;
};

BS:		con 8;		# ^h backspace character
BSW:		con 23;		# ^w bacspace word
BSL:		con 21;		# ^u backspace line
EOT:		con 4;		# ^d end of file
ESC:		con 27;		# hold mode

HIWAT:	con 2000;	# maximum number of lines in transcript
LOWAT:	con 1500;	# amount to reduce to after high water

Name:	con "Telnet";
ctxt:	ref Context;
cmds:	chan of string;
net:	Connection;
stderr: ref Sys->FD;
mcrlf:	int;
netinp:	ref Iob;

# control characters
Se:		con 240;	# end subnegotiation
NOP:		con 241;
Mark:		con 242;	# data mark
Break:		con 243;
Interrupt:	con 244;
Abort:		con 245;	# TENEX ^O
AreYouThere:	con 246;
Erasechar:	con 247;	# erase last character
Eraseline:	con 248;	# erase line
GoAhead:	con 249;	# half duplex clear to send
Sb:		con 250;	# start subnegotiation
Will:		con 251;
Wont:		con 252;
Do:		con 253;
Dont:		con 254;
Iac:		con 255;

# options
Binary,	Echo,	SGA,	Stat,	Timing,
Det,	Term,	EOR,	Uid,	Outmark,
Ttyloc,	M3270,	Padx3,	Window,	Speed,
Flow,	Line,	Xloc,	Extend: con iota;

Opt: adt
{
	name:	string;
	code:	int;
	noway:	int;	
	remote:	int;		# remote value
	local:	int;		# local value
};

opt := array[] of
{
	Binary	=> Opt("binary",			0,	0,	0, 	0),
	Echo		=> Opt("echo",				1,  	0, 	0,	0),
	SGA		=> Opt("suppress Go Ahead",	3,  	0, 	0,	0),
	Stat		=> Opt("status",			5,  	1, 	0,	0),
	Timing	=> Opt("timing",			6,  	1, 	0,	0),
	Det		=> Opt("det",				20, 	1, 	0,	0),
	Term	=> Opt("terminal",			24, 	0, 	0,	0),
	EOR		=> Opt("end of record",		25, 	1, 	0,	0),
	Uid		=> Opt("uid",				26, 	1, 	0,	0),
	Outmark	=> Opt("outmark",			27, 	1, 	0,	0),
	Ttyloc	=> Opt("ttyloc",				28, 	1, 	0,	0),
	M3270	=> Opt("3270 mode",		29, 	1, 	0,	0),
	Padx3	=> Opt("pad x.3",			30, 	1, 	0,	0),
	Window	=> Opt("window size",		31, 	1, 	0,	0),
	Speed	=> Opt("speed",			32, 	1, 	0,	0),
	Flow		=> Opt("flow control",		33, 	1, 	0,	0),
	Line		=> Opt("line mode",			34, 	0, 	0,	0),
	Xloc		=> Opt("X display loc",		35, 	1, 	0,	0),
	Extend	=> Opt("Extended",			255, 	1, 	0,	0),
};

shwin_cfg := array[] of {
	"menu .m",
	".m add command -text Cut -command {send edit cut}",
	".m add command -text Paste -command {send edit paste}",
	".m add command -text Snarf -command {send edit snarf}",
	".m add command -text Send -command {send edit send}",
	"frame .ft",
	"scrollbar .ft.scroll -command {.ft.t yview}",
	"text .ft.t -width 70w -height 25h -yscrollcommand {.ft.scroll set}",
	"frame .mb",
	"menubutton .mb.c -text Connect -menu .mbc",
	"menubutton .mb.t -text Terminal -menu .mbt",
	"menu .mbc",
	".mbc add command -text {Remote System} -command {send cmd con}",
	".mbc add command -text {Disconnect} -state disabled -command {send cmd dis}",
	".mbc add command -text {Exit} -command {send cmd exit}",
	".mbc add separator",
	"menu .mbt",
	".mbt add checkbutton -text {Line Mode} -command {send cmd line}",
	".mbt add checkbutton -text {Map CR to LF} -command {send cmd crlf}",
	"pack .mb.c .mb.t -side left",
	"pack .ft.scroll -side left -fill y",
	"pack .ft.t -fill both -expand 1",
	"pack .mb -fill x",
	"pack .ft -fill both -expand 1",
	"pack propagate . 0",
	"focus .ft.t",
	"bind .ft.t <Key> {send keys {%A}}",
	"bind .ft.t <Control-d> {send keys {%A}}",
	"bind .ft.t <Control-h> {send keys {%A}}",
	"bind .ft.t <ButtonPress-3> {send but3 %X %Y}",
	"bind .ft.t <ButtonRelease-3> {}",
	"bind .ft.t <DoubleButton-3> {}",
	"bind .ft.t <Double-ButtonRelease-3> {}",
	"bind .ft.t <ButtonPress-2> {}",
	"bind .ft.t <ButtonRelease-2> {}",
	"update"
};

connect_cfg := array[] of {
	"frame .fl",
	"label .fl.h -text Host",
	"label .fl.p -text Port",
	"pack .fl.h .fl.p",
	"frame .el",
	"entry .el.h",
	"entry .el.p",
	".el.p insert end 'telnet",
	"pack .el.h .el.p",
	"pack .Wm_t -fill x",
	"pack .fl .el -side left",
	"focus .el.h",
	"bind .el.h <Key-\n> {send cmd ok}",
	"bind .el.p <key-\n> {send cmd ok}",
	"update"
};

connected_cfg := array[] of {
	"focus .ft.t",
	".mbc entryconfigure 0 -state disabled",
	".mbc entryconfigure 1 -state normal"
};

menuindex := "0";
holding := 0;

init(C: ref Context, argv: list of string)
{
	sys = load Sys Sys->PATH;
	if (C == nil) {
		sys->fprint(sys->fildes(2), "telnet: no window context\n");
		raise "fail:bad context";
	}
	draw = load Draw Draw->PATH;
	tk = load Tk Tk->PATH;
	tkclient = load Tkclient Tkclient->PATH;
	dialog = load Dialog Dialog->PATH;

	ctxt = C;
	tkclient->init();
	dialog->init();

	sys->pctl(Sys->NEWPGRP, nil);
	stderr = sys->fildes(2);

	tkargs := "";
	argv = tl argv;
	if(argv != nil) {
		tkargs = hd argv;
		argv = tl argv;
	}
	(t, titlectl) := tkclient->toplevel(ctxt, tkargs, Name, Tkclient->Appl);

	edit := chan of string;
	tk->namechan(t, edit, "edit");
	for (cc:=0; cc<len shwin_cfg; cc++)
		tk->cmd(t, shwin_cfg[cc]);

	keys := chan of string;
	tk->namechan(t, keys, "keys");

	but3 := chan of string;
	tk->namechan(t, but3, "but3");

	cmds = chan of string;
	tk->namechan(t, cmds, "cmd");

	# outpoint is place in text to insert characters printed by programs
	tk->cmd(t, ".ft.t mark set outpoint end; .ft.t mark gravity outpoint left");
	tkclient->onscreen(t, nil);
	tkclient->startinput(t, "kbd"::"ptr"::nil);

	for(;;) alt {
	s := <-t.ctxt.kbd =>
		tk->keyboard(t, s);
	s := <-t.ctxt.ptr =>
		tk->pointer(t, *s);
	s := <-t.ctxt.ctl or
	s = <-t.wreq or
	s = <-titlectl =>
		if(s == "exit") {
			kill();
			return;
		}
		tkclient->wmctl(t, s);
	ecmd := <-edit =>
		editor(t, ecmd);
		sendinput(t);

	c := <-keys =>
		if(opt[Echo].local == 0) {
			sys->fprint(net.dfd, "%c", c[1]);
			break;
		}
		cut(t, 1);
		char := c[1];
		if(char == '\\')
			char = c[2];
		update := ";.ft.t see insert;update";
		case char{
		* =>
			tk->cmd(t, ".ft.t insert insert "+c+update);
		'\n' or EOT =>
			tk->cmd(t, ".ft.t insert insert "+c+update);
			sendinput(t);
		BS =>
			if(!insat(t, "outpoint"))
				tk->cmd(t, ".ft.t delete insert-1chars"+update);
		ESC =>
			holding ^= 1;
			color := "blue";
			if(!holding){
				color = "black";
				tkclient->settitle(t, Name);
				sendinput(t);
			}else
				tkclient->settitle(t, Name+" (holding)");
			tk->cmd(t, ".ft.t configure -foreground "+color+update);
		BSL =>
			if(insininput(t))
				tk->cmd(t, ".ft.t delete outpoint insert"+update);
			else
				tk->cmd(t, ".ft.t delete {insert linestart} insert"+update);
		BSW =>
			if(insat(t, "outpoint"))
				break;
			a0 := isalnum(tk->cmd(t, ".ft.t get insert-1chars"));
			a1 := isalnum(tk->cmd(t, ".ft.t get insert"));
			start: string;
			if(a0 && a1)	# middle of word
				start = "{insert wordstart}";
			else if(a0)		# end of word
				start = "{insert-1chars wordstart}";
			else{	# beginning or not in word; must search
				s: string;
				for(n:=1; ;){
					s = tk->cmd(t, ".ft.t get insert-"+ string n +"chars");
					if(s=="" || s=="\n"){
						start = "insert-"+ string n+"chars";
						break;
					}
					n++;
					if(isalnum(s)){
						start = "{insert-"+ string n+"chars wordstart}";
						break;
					}
				}
				
			}
			# don't ^w across outpoint
			if(tk->cmd(t, ".ft.t compare insert >= outpoint") == "1"
			&& tk->cmd(t, ".ft.t compare "+start+" < outpoint") == "1")
				start = "outpoint";
			tk->cmd(t, ".ft.t delete " + start + " insert"+update);
		}

	c := <-but3 =>
		(nil, l) := sys->tokenize(c, " ");
		x := int hd l - 50;
		y := int hd tl l - int tk->cmd(t, ".m yposition "+menuindex) - 10;
		tk->cmd(t, ".m activate "+menuindex+"; .m post "+string x+" "+string y+
			"; grab set .m; update");

	c := <-cmds =>
		case c {
		"con" =>
			tk->cmd(t, ".mb.c configure -state disabled");
			connect(t);
			tk->cmd(t, ".mb.c configure -state normal; update");
		"dis" =>
			tkclient->settitle(t, "Telnet");
			tk->cmd(t, ".mbc entryconfigure 0 -state normal");
			tk->cmd(t, ".mbc entryconfigure 1 -state disabled");
			net.cfd = nil;
			net.dfd = nil;
			kill();
		"exit" =>
			kill();
			return;
		"crlf" =>
			mcrlf = !mcrlf;
			break;
		"line" =>
			if(opt[Line].local == 0)
				send3(netinp, Iac, Will, opt[Line].code);
			else
				send3(netinp, Iac, Wont, opt[Line].code);
		}
	}
}

insat(t: ref Tk->Toplevel, mark: string): int
{
	return tk->cmd(t, ".ft.t compare insert == "+mark) == "1";
}

insininput(t: ref Tk->Toplevel): int
{
	if(tk->cmd(t, ".ft.t compare insert >= outpoint") != "1")
		return 0;
	return tk->cmd(t, ".ft.t compare {insert linestart} == {outpoint linestart}") == "1";
}

isalnum(s: string): int
{
	if(s == "")
		return 0;
	c := s[0];
	if('a' <= c && c <= 'z')
		return 1;
	if('A' <= c && c <= 'Z')
		return 1;
	if('0' <= c && c <= '9')
		return 1;
	if(c == '_')
		return 1;
	if(c > 16rA0)
		return 1;
	return 0;
}

editor(t: ref Tk->Toplevel, ecmd: string)
{
	s, snarf: string;

	case ecmd {
	"cut" =>
		menuindex = "0";
		cut(t, 1);
	
	"paste" =>
		menuindex = "1";
		snarf = tkclient->snarfget();
		if(snarf == "")
			break;
		cut(t, 0);
		tk->cmd(t, ".ft.t insert insert '"+snarf);
		sendinput(t);

	"snarf" =>
		menuindex = "2";
		if(tk->cmd(t, ".ft.t tag ranges sel") == "")
			break;
		snarf = tk->cmd(t, ".ft.t get sel.first sel.last");
		tkclient->snarfput(snarf);

	"send" =>
		menuindex = "3";
		if(tk->cmd(t, ".ft.t tag ranges sel") != ""){
			snarf = tk->cmd(t, ".ft.t get sel.first sel.last");
			tkclient->snarfput(snarf);
		}else
			snarf = tkclient->snarfget();
		if(snarf != "")
			s = snarf;
		else
			return;
		if(s[len s-1] != '\n' && s[len s-1] != EOT)
			s[len s] = '\n';
		tk->cmd(t, ".ft.t see end; .ft.t insert end '"+s);
		tk->cmd(t, ".ft.t mark set insert end");
		tk->cmd(t, ".ft.t tag remove sel sel.first sel.last");
	}
	tk->cmd(t, "update");
}

cut(t: ref Tk->Toplevel, snarfit: int)
{
	if(tk->cmd(t, ".ft.t tag ranges sel") == "")
		return;
	if(snarfit)
		tkclient->snarfput(tk->cmd(t, ".ft.t get sel.first sel.last"));
	tk->cmd(t, ".ft.t delete sel.first sel.last");
}

sendinput(t: ref Tk->Toplevel)
{
	if(holding)
		return;
	input := tk->cmd(t, ".ft.t get outpoint end");
	slen := len input;
	if(slen == 0)
		return;

	for(i := 0; i < slen; i++)
		if(input[i] == '\n' || input[i] == EOT)
			break;

	if(i >= slen)
		return;

	advance := string (i+1);
	if(input[i] == EOT)
		input = input[0:i];
	else
		input = input[0:i+1];

	sys->fprint(net.dfd, "%s", input);
	tk->cmd(t, ".ft.t mark set outpoint outpoint+" + advance + "chars");
}

kill()
{
	path := sys->sprint("#p/%d/ctl", sys->pctl(0, nil));
	fd := sys->open(path, sys->OWRITE);
	if(fd != nil)
		sys->fprint(fd, "killgrp");
}

connect(t: ref Tk->Toplevel)
{
	(b, titlectl) := tkclient->toplevel(ctxt, nil, "Connect", 0);
	for (c:=0; c<len connect_cfg; c++)
		tk->cmd(b, connect_cfg[c]);

	cmd := chan of string;
	tk->namechan(b, cmd, "cmd");
	tkclient->onscreen(b, nil);
	tkclient->startinput(b, "kbd"::"ptr"::nil);

loop:	for(;;) alt {
		s := <-b.ctxt.kbd =>
			tk->keyboard(b, s);
		s := <-b.ctxt.ptr =>
			tk->pointer(b, *s);
		s := <-b.ctxt.ctl or
		s = <-b.wreq or
		s = <-titlectl =>
			if(s == "exit")
				return;
			tkclient->wmctl(b, s);
	<-cmd =>
		break loop;		
	}

	addr := sys->sprint("tcp!%s!%s",
			tk->cmd(b, ".el.h get"),
			tk->cmd(b, ".el.p get"));

	tkclient->settitle(b, "Dialing");
	tk->cmd(b, "update");

	ok: int;
	(ok, net) = sys->dial(addr, nil);
	if(ok < 0) {
		dialog->prompt(ctxt, b.image, "error -fg red",
			"Connect", "Connection to host failed\n"+sys->sprint("%r"),
			0, "Stop connect" :: nil);
		return;
	}

	tkclient->settitle(t, "Telnet - "+addr);
	for (c=0; c<len connected_cfg; c++)
		tk->cmd(b, connected_cfg[c]);

	spawn fromnet(t);
}

flush(t: ref Tk->Toplevel, data: array of byte)
{
	cdata := string data;
	ncdata := string len cdata + "chars;";
	moveins := insat(t, "outpoint");
	tk->cmd(t, ".ft.t insert outpoint '"+ cdata);
	s := ".ft.t mark set outpoint outpoint+" + ncdata;
	s += ".ft.t see outpoint;";
	if(moveins)
		s += ".ft.t mark set insert insert+" + ncdata;
	s += "update";
	tk->cmd(t, s);
	nlines := int tk->cmd(t, ".ft.t index end");
	if(nlines > HIWAT){
		s = ".ft.t delete 1.0 "+ string (nlines-LOWAT) +".0;update";
		tk->cmd(t, s);
	}
}

iobnew(fd: ref Sys->FD, t: ref Tk->Toplevel, out: ref Iob, size: int): ref Iob
{
	iob := ref Iob;
	iob.fd = fd;
	iob.t = t;
	iob.out = out;
	iob.buf = array[size] of byte;
	iob.nbyte = 0;
	iob.ptr = 0;
	return iob;
}

iobget(iob: ref Iob): int
{
	if(iob.nbyte == 0) {
		if(iob.out != nil)
			iobflush(iob.out);
		iob.nbyte = sys->read(iob.fd, iob.buf, len iob.buf);
		if(iob.nbyte <= 0)
			return iob.nbyte;
		iob.ptr = 0;
	}
	iob.nbyte--;
	return int iob.buf[iob.ptr++];
}

iobput(iob: ref Iob, c: int)
{
	iob.buf[iob.ptr++] = byte c;
	if(iob.ptr == len iob.buf)
		iobflush(iob);
}

iobflush(iob: ref Iob)
{
	if(iob.fd == nil) {
		flush(iob.t, iob.buf[0:iob.ptr]);
		iob.ptr = 0;
	}
}

fromnet(t: ref Tk->Toplevel)
{
	conout := iobnew(nil, t, nil, 2048);
	netinp = iobnew(net.dfd, nil, conout, 2048);

	crnls := 0;
	freenl := 0;

loop:	for(;;) {
		c := iobget(netinp);
		case c {
		-1 =>
			cmds <-= "dis";
			return;
		'\n' =>				# skip nl after string of cr's */
			if(!opt[Binary].local && !mcrlf) {
				crnls++;
				if(freenl == 0)
					break;
				freenl = 0;
				continue loop;
			}
		'\r' =>
			if(!opt[Binary].local && !mcrlf) {
				if(crnls++ == 0){
					freenl = 1;
					c = '\n';
					break;
				}
				continue loop;
			}
		Iac  =>
			c = iobget(netinp);
			if(c == Iac)
				break;
			iobflush(conout);
			if(control(netinp, c) < 0)
				return;

			continue loop;	
		}
		iobput(conout, c);
	}
}

control(bp: ref Iob, c: int): int
{
	case c {
	AreYouThere =>
		sys->fprint(net.dfd, "Inferno telnet V1.0\r\n");
	Sb =>
		return sub(bp);
	Will =>
		return will(bp);
	Wont =>
		return wont(bp);
	Do =>
		return doit(bp);
	Dont =>
		return dont(bp);
	Se =>
		sys->fprint(stderr, "telnet: SE without an SB\n");
	-1 =>
		return -1;
	*  =>
		break;
	}
	return 0;
}

sub(bp: ref Iob): int
{
	subneg: string;
	i := 0;
	for(;;){
		c := iobget(bp);
		if(c == Iac) {
			c = iobget(bp);
			if(c == Se)
				break;
			subneg[i++] = Iac;
		}
		if(c < 0)
			return -1;
		subneg[i++] = c;
	}
	if(i == 0)
		return 0;

	sys->fprint(stderr, "sub %d %d n = %d\n", subneg[0], subneg[1], i);

	for(i = 0; i < len opt; i++)
		if(opt[i].code == subneg[0])
			break;

	if(i >= len opt)
		return 0;

	case i {
	Term =>
		sbsend(opt[Term].code, array of byte "dumb");	
	}

	return 0;
}

sbsend(code: int, data: array of byte): int
{
	buf := array[4+len data+2] of byte;
	o := 4+len data;

	buf[0] = byte Iac;
	buf[1] = byte Sb;
	buf[2] = byte code;
	buf[3] = byte 0;
	buf[4:] = data;
	buf[o] = byte Iac;
	o++;
	buf[o] = byte Se;

	return sys->write(net.dfd, buf, len buf);
}

will(bp: ref Iob): int
{
	c := iobget(bp);
	if(c < 0)
		return -1;

	sys->fprint(stderr, "will %d\n", c);

	for(i := 0; i < len opt; i++)
		if(opt[i].code == c)
			break;

	if(i >= len opt) {
		send3(bp, Iac, Dont, c);
		return 0;
	}

	rv := 0;
	if(opt[i].noway)
		send3(bp, Iac, Dont, c);
	else
	if(opt[i].remote == 0)
		rv |= send3(bp, Iac, Do, c);

	if(opt[i].remote == 0)
		rv |= change(bp, i, Will);
	opt[i].remote = 1;
	return rv;
}

wont(bp: ref Iob): int
{
	c := iobget(bp);
	if(c < 0)
		return -1;

	sys->fprint(stderr, "wont %d\n", c);

	for(i := 0; i < len opt; i++)
		if(opt[i].code == c)
			break;

	if(i >= len opt)
		return 0;

	rv := 0;
	if(opt[i].remote) {
		rv |= change(bp, i, Wont);
		rv |= send3(bp, Iac, Dont, c);
	}
	opt[i].remote = 0;
	return rv;
}

doit(bp: ref Iob): int
{
	c := iobget(bp);
	if(c < 0)
		return -1;

	sys->fprint(stderr, "do %d\n", c);

	for(i := 0; i < len opt; i++)
		if(opt[i].code == c)
			break;

	if(i >= len opt || opt[i].noway) {
		send3(bp, Iac, Wont, c);
		return 0;
	}
	rv := 0;
	if(opt[i].local == 0) {
		rv |= change(bp, i, Do);
		rv |= send3(bp, Iac, Will, c);
	}
	opt[i].local = 1;
	return rv;
}

dont(bp: ref Iob): int
{
	c := iobget(bp);
	if(c < 0)
		return -1;

	sys->fprint(stderr, "dont %d\n", c);

	for(i := 0; i < len opt; i++)
		if(opt[i].code == c)
			break;

	if(i >= len opt || opt[i].noway)
		return 0;

	rv := 0;
	if(opt[i].local){
		opt[i].local = 0;
		rv |= change(bp, i, Dont);
		rv |= send3(bp, Iac, Wont, c);
	}
	opt[i].local = 0;
	return rv;
}

change(nil: ref Iob, nil: int, nil: int): int
{
	return 0;
}

send3(bp: ref Iob, c0: int, c1: int, c2: int): int
{
	buf := array[3] of byte;

	buf[0] = byte c0;
	buf[1] = byte c1;
	buf[2] = byte c2;

	t: string;
	case c0 {
	Will => t = "Will";
	Wont => t = "Wont";
	Do =>	t = "Do";
	Dont => t = "Dont";
	}
	if(t != nil)
		sys->fprint(stderr, "r %s %d\n", t, c1);

	r := sys->write(bp.fd, buf, 3);
	if(r != 3)
		return -1;
	return 0;
}
