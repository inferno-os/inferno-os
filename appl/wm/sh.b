implement WmSh;

include "sys.m";
	sys: Sys;
	FileIO: import sys;

include "draw.m";
	draw: Draw;
	Context, Rect: import draw;

include "tk.m";
	tk: Tk;

include "tkclient.m";
	tkclient: Tkclient;

include	"plumbmsg.m";
	plumbmsg: Plumbmsg;
	Msg: import plumbmsg;

include "workdir.m";

include "string.m";
	str: String;

include "arg.m";

WmSh: module
{
	init:	fn(ctxt: ref Draw->Context, args: list of string);
};

Command: type WmSh;

BSW:		con 23;		# ^w bacspace word
BSL:		con 21;		# ^u backspace line
EOT:		con 4;		# ^d end of file
ESC:		con 27;		# hold mode

# XXX line-based limits are inadequate - memory is still
# blown if a client writes a very long line.
HIWAT:	con 2000;	# maximum number of lines in transcript
LOWAT:	con 1500;	# amount to reduce to after high water

Name:	con "Shell";

Rdreq: adt
{
	off:	int;
	nbytes:	int;
	fid:	int;
	rc:	chan of (array of byte, string);
};

shwin_cfg := array[] of {
	"menu .m",
	".m add command -text noscroll -command {send edit noscroll}",
	".m add command -text cut -command {send edit cut}",
	".m add command -text paste -command {send edit paste}",
	".m add command -text snarf -command {send edit snarf}",
	".m add command -text send -command {send edit send}",
	"frame .b -bd 1 -relief ridge",
	"frame .ft -bd 0",
	"scrollbar .ft.scroll -command {send scroll t}",
	"text .ft.t -bd 1 -relief flat -yscrollcommand {send scroll s} -bg white -selectforeground black -selectbackground #CCCCCC",
	".ft.t tag configure sel -relief flat",
	"pack .ft.scroll -side left -fill y",
	"pack .ft.t -fill both -expand 1",
	"pack .Wm_t -fill x",
	"pack .b -anchor w -fill x",
	"pack .ft -fill both -expand 1",
	"focus .ft.t",
	"bind .ft.t <Key> {send keys {%A}}",
	"bind .ft.t <Control-d> {send keys {%A}}",
	"bind .ft.t <Control-h> {send keys {%A}}",
	"bind .ft.t <Control-w> {send keys {%A}}",
	"bind .ft.t <Control-u> {send keys {%A}}",
	"bind .ft.t <Button-1> +{send but1 pressed}",
	"bind .ft.t <Double-Button-1> +{send but1 pressed}",
	"bind .ft.t <ButtonRelease-1> +{send but1 released}",
	"bind .ft.t <ButtonPress-2> {send but2 %X %Y}",
	"bind .ft.t <Motion-Button-2-Button-1> {}",
	"bind .ft.t <Motion-ButtonPress-2> {}",
	"bind .ft.t <ButtonPress-3> {send but3 pressed}",
	"bind .ft.t <ButtonRelease-3> {send but3 released %x %y}",
	"bind .ft.t <Motion-Button-3> {}",
	"bind .ft.t <Motion-Button-3-Button-1> {}",
	"bind .ft.t <Double-Button-3> {}",
	"bind .ft.t <Double-ButtonRelease-3> {}",
};

rdreq: list of Rdreq;
menuindex := "0";
holding := 0;
haskbdfocus := 0;
plumbed := 0;
rawon := 0;
rawinput := "";
scrolling := 1;
partialread: array of byte;
cwd := "";
width, height, font: string;

events: list of string;
evrdreq: list of Rdreq;
winname: string;

badmod(p: string)
{
	sys->print("wm/sh: cannot load %s: %r\n", p);
	raise "fail:bad module";
}

init(ctxt: ref Context, argv: list of string)
{
	sys = load Sys Sys->PATH;
	draw = load Draw Draw->PATH;
	tk = load Tk Tk->PATH;

	tkclient = load Tkclient Tkclient->PATH;
	if (tkclient == nil)
		badmod(Tkclient->PATH);

	str = load String String->PATH;
	if (str == nil)
		badmod(String->PATH);

	arg := load Arg Arg->PATH;
	if (arg == nil)
		badmod(Arg->PATH);
	arg->init(argv);

	plumbmsg = load Plumbmsg Plumbmsg->PATH;

	sys->pctl(Sys->FORKNS | Sys->NEWPGRP | Sys->FORKENV, nil);

	tkclient->init();
	if (ctxt == nil)
		ctxt = tkclient->makedrawcontext();
	if(ctxt == nil){
		sys->fprint(sys->fildes(2), "sh: no window context\n");
		raise "fail:bad context";
	}

	if(plumbmsg != nil && plumbmsg->init(1, nil, 0) >= 0){
		plumbed = 1;
		workdir := load Workdir Workdir->PATH;
		cwd = workdir->init();
	}

	shargs: list of string;
	while ((opt := arg->opt()) != 0) {
		case opt {
		'w' =>
			width = arg->arg();
		'h' =>
			height = arg->arg();
		'f' =>
			font = arg->arg();
		'c' =>
			a := arg->arg();
			if (a == nil) {
				sys->print("usage: wm/sh [-ilxvn] [-w width] [-h height] [-f font] [-c command] [file [args...]\n");
				raise "fail:usage";
			}
			shargs = a :: "-c" :: shargs;
		'i' or 'l' or 'x' or 'v' or 'n' =>
			shargs = sys->sprint("-%c", opt) :: shargs;
		}
	}
	argv = arg->argv();
	for (; shargs != nil; shargs = tl shargs)
		argv = hd shargs :: argv;

	winname = Name + " " + cwd;

	spawn main(ctxt, argv);
}

task(t: ref Tk->Toplevel)
{
	tkclient->wmctl(t, "task");
}

atend(t: ref Tk->Toplevel, w: string): int
{
	s := cmd(t, w+" yview");
	for(i := 0; i < len s; i++)
		if(s[i] == ' ')
			break;
	return i == len s - 2 && s[i+1] == '1';
}

main(ctxt: ref Draw->Context, argv: list of string)
{
	(t, titlectl) := tkclient->toplevel(ctxt, "", winname, Tkclient->Appl);
	wm := t.ctxt;

	edit := chan of string;
	tk->namechan(t, edit, "edit");

	keys := chan of string;
	tk->namechan(t, keys, "keys");

	butcmd := chan of string;
	tk->namechan(t, butcmd, "button");

	event := chan of string;
	tk->namechan(t, event, "action");

	scroll := chan of string;
	tk->namechan(t, scroll, "scroll");

	but1 := chan of string;
	tk->namechan(t, but1, "but1");
	but2 := chan of string;
	tk->namechan(t, but2, "but2");
	but3 := chan of string;
	tk->namechan(t, but3, "but3");
	button1 := 0;
	button3 := 0;

	for (i := 0; i < len shwin_cfg; i++)
		cmd(t, shwin_cfg[i]);
	(menuw, nil) := itemsize(t, ".m");
	if (font != nil) {
		if (font[0] != '/' && (len font == 1 || font[0:2] != "./"))
			font = "/fonts/" + font;
		cmd(t, ".ft.t configure -font " + font);
	}
	cmd(t, ".ft.t configure -width 65w -height 20h");
	cmd(t, "pack propagate . 0");
	if(width != nil)
		cmd(t, ". configure -width " + width);
	if(height != nil)
		cmd(t, ". configure -height " + height);
	tkclient->onscreen(t, nil);
	tkclient->startinput(t, "ptr" :: "kbd" :: nil);

	ioc := chan of (int, ref FileIO, ref FileIO, string, ref FileIO);
	spawn newsh(ctxt, ioc, argv);

	(nil, file, filectl, consfile, shctl) := <-ioc;
	if(file == nil || filectl == nil || shctl == nil) {
		sys->print("newsh: shell cons creation failed\n");
		return;
	}
	dummyfwrite := chan of (int, array of byte, int, Sys->Rwrite);
	fwrite := file.write;

	rdrpc: Rdreq;

	# outpoint is place in text to insert characters printed by programs
	cmd(t, ".ft.t mark set outpoint 1.0; .ft.t mark gravity outpoint left");

	for(;;) alt {
	c := <-wm.kbd =>
		tk->keyboard(t, c);
	m := <-wm.ptr =>
		tk->pointer(t, *m);
	c := <-wm.ctl or
	c = <-t.wreq or
	c = <-titlectl =>
		(nil, flds) := sys->tokenize(c, " \t");
		if(flds != nil && hd flds == "haskbdfocus" && tl flds != nil){
			haskbdfocus = int hd tl flds;
			setcols(t);
		}
		tkclient->wmctl(t, c);
	ecmd := <-edit =>
		editor(t, ecmd);
		sendinput(t);

	c := <-keys =>
		char := c[1];
		if(char == '\\')
			char = c[2];
		if(char != ESC)
			cut(t, 1);
		if(rawon){
			if(int cmd(t, ".ft.t compare insert >= outpoint")){
				rawinput[len rawinput] = char;
				sendinput(t);
				break;
			}
		}
		case char {
		* =>
			cmd(t, ".ft.t insert insert "+c);
		'\n' or
		EOT =>
			cmd(t, ".ft.t insert insert "+c);
			sendinput(t);
		'\b' =>
			cmd(t, ".ft.t tkTextDelIns -c");
		BSL =>
			cmd(t, ".ft.t tkTextDelIns -l");
		BSW =>
			cmd(t, ".ft.t tkTextDelIns -w");
		ESC =>
			setholding(t, !holding);
		}
		cmd(t, ".ft.t see insert;update");

	c := <-but1 =>
		button1 = (c == "pressed");
		button3 = 0;	# abort any pending button 3 action

	c := <-but2 =>
		if(button1){
			cut(t, 1);
			cmd(t, "update");
			break;
		}
		(nil, l) := sys->tokenize(c, " ");
		x := int hd l - menuw/2;
		y := int hd tl l - int cmd(t, ".m yposition "+menuindex) - 10;
		cmd(t, ".m activate "+menuindex+"; .m post "+string x+" "+string y+
			"; update");
		button3 = 0;	# abort any pending button 3 action

	c := <-but3 =>
		if(c == "pressed"){
			button3 = 1;
			if(button1){
				paste(t);
				sendinput(t);
				cmd(t, "update");
			}
			break;
		}
		if(plumbed == 0 || button3 == 0 || button1 != 0)
			break;
		button3 = 0;
		# plumb message triggered by release of button 3
		(nil, l) := sys->tokenize(c, " ");
		x := int hd tl l;
		y := int hd tl tl l;
		index := cmd(t, ".ft.t index @"+string x+","+string y);
		selindex := cmd(t, ".ft.t tag ranges sel");
		if(selindex != "")
			insel := cmd(t, ".ft.t compare sel.first <= "+index)=="1" &&
				cmd(t, ".ft.t compare sel.last >= "+index)=="1";
		else
			insel = 0;
		attr := "";
		if(insel)
			text := tk->cmd(t, ".ft.t get sel.first sel.last");
		else{
			# have line with text in it
			# now extract whitespace-bounded string around click
			(nil, w) := sys->tokenize(index, ".");
			charno := int hd tl w;
			left := cmd(t, ".ft.t index {"+index+" linestart}");
			right := cmd(t, ".ft.t index {"+index+" lineend}");
			line := tk->cmd(t, ".ft.t get "+left+" "+right);
			for(i=charno; i>0; --i)
				if(line[i-1]==' ' || line[i-1]=='\t')
					break;
			for(j:=charno; j<len line; j++)
				if(line[j]==' ' || line[j]=='\t')
					break;
			text = line[i:j];
			attr = "click="+string (charno-i);
		}
		msg := ref Msg(
			"WmSh",
			"",
			cwd,
			"text",
			attr,
			array of byte text);
		if(msg.send() < 0)
			sys->fprint(sys->fildes(2), "sh: plumbing write error: %r\n");
	c := <-butcmd =>
		simulatetype(t, tkunquote(c));
		sendinput(t);
		cmd(t, "update");
	c := <-event =>
		events = str->append(tkunquote(c), events);
		if (evrdreq != nil) {
			rc := (hd evrdreq).rc;
			rc <-= (array of byte hd events, nil);
			evrdreq = tl evrdreq;
			events = tl events;
		}
	rdrpc = <-shctl.read =>
		if(rdrpc.rc == nil)
			continue;
		if (events != nil) {
			rdrpc.rc <-= (array of byte hd events, nil);
			events = tl events;
		} else
			evrdreq = rdrpc :: evrdreq;
	(nil, data, nil, wc) := <-shctl.write =>
		if (wc == nil)
			break;
		if ((err := shctlcmd(t, string data)) != nil)
			wc <-= (0, err);
		else
			wc <-= (len data, nil);
	rdrpc = <-filectl.read =>
		if(rdrpc.rc == nil)
			continue;
		rdrpc.rc <-= (nil, "not allowed");
	(nil, data, nil, wc) := <-filectl.write =>
		if(wc == nil) {
			# consctl closed - revert to cooked mode
			# XXX should revert only on *last* close?
			rawon = 0;
			continue;
		}
		(nc, cmdlst) := sys->tokenize(string data, " \n");
		if(nc == 1) {
			case hd cmdlst {
			"rawon" =>
				rawon = 1;
				rawinput = "";
				# discard previous input
				advance := string (len tk->cmd(t, ".ft.t get outpoint end") +1);
				cmd(t, ".ft.t mark set outpoint outpoint+" + advance + "chars");
				partialread = nil;
			"rawoff" =>
				rawon = 0;
				partialread = nil;
			"holdon" =>
				setholding(t, 1);
				cmd(t, "update");
			"holdoff" =>
				setholding(t, 0);
				cmd(t, "update");
			* =>
				wc <-= (0, "unknown consctl request");
				continue;
			}
			wc <-= (len data, nil);
			continue;
		}
		wc <-= (0, "unknown consctl request");

	rdrpc = <-file.read =>
		if(rdrpc.rc == nil) {
			(ok, nil) := sys->stat(consfile);
			if (ok < 0)
				return;
			continue;
		}
		append(rdrpc);
		sendinput(t);

	c := <-scroll =>
		if(c[0] == 't'){
			cmd(t, ".ft.t yview "+c[1:]+";update");
			if(scrolling)
				fwrite = file.write;
			else if(atend(t, ".ft.t"))
				fwrite = file.write;
			else
				fwrite = dummyfwrite;
		}else{
			cmd(t, ".ft.scroll set "+c[1:]+";update");
			if(atend(t, ".ft.t") && fwrite == dummyfwrite)
				fwrite = file.write;
		}
	(nil, data, nil, wc) := <-fwrite =>
		if(wc == nil) {
			(ok, nil) := sys->stat(consfile);
			if (ok < 0)
				return;
			continue;
		}
		needscroll := atend(t, ".ft.t");
		cdata := cursorcontrol(t, string data);
		ncdata := string len cdata + "chars;";
		cmd(t, ".ft.t insert outpoint '"+ cdata);
		wc <-= (len data, nil);
		data = nil;
		s := ".ft.t mark set outpoint outpoint+" + ncdata;
		if(!atend(t, ".ft.t") && scrolling == 0)
			fwrite = dummyfwrite;
		else if(needscroll)
			s += ".ft.t see outpoint;";
		s += "update";
		cmd(t, s);
		nlines := int cmd(t, ".ft.t index end");
		if(nlines > HIWAT){
			s = ".ft.t delete 1.0 "+ string (nlines-LOWAT) +".0;update";
			cmd(t, s);
		}
	}
}

setholding(t: ref Tk->Toplevel, hold: int)
{
	if(hold == holding)
		return;
	holding = hold;
	if(!holding){
		tkclient->settitle(t, winname);
		sendinput(t);
	}else
		tkclient->settitle(t, winname+" (holding)");
	setcols(t);
}

setcols(t: ref Tk->Toplevel)
{
	fgcol := "black";
	if(holding){
		if(haskbdfocus)
			fgcol = "#000099FF";	# DMedblue
		else
			fgcol = "#005DBBFF";	# DGreyblue
	}else{
		if(haskbdfocus)
			fgcol = "black";
		else
			fgcol = "#666666FF";	# dark grey
	}
	cmd(t, ".ft.t configure -foreground "+fgcol+" -selectforeground "+fgcol);
	cmd(t, ".ft.t tag configure sel -foreground "+fgcol);
}

tkunquote(s: string): string
{
	if (s == nil)
		return nil;
	t: string;
	if (s[0] != '{' || s[len s - 1] != '}')
		return s;
	for (i := 1; i < len s - 1; i++) {
		if (s[i] == '\\')
			i++;
		t[len t] = s[i];
	}
	return t;
}

buttonid := 0;
shctlcmd(win: ref Tk->Toplevel, c: string): string
{
	toks := str->unquoted(c);
	if (toks == nil)
		return "null command";
	n := len toks;
	case hd toks {
	"button" or
	"action"=>
		# (button|action) title sendtext
		if (n != 3)
			return "bad usage";
		id := ".b.b" + string buttonid++;
		cmd(win, "button " + id + " -text " + tk->quote(hd tl toks) +
				" -command 'send " + hd toks + " " + tk->quote(hd tl tl toks));
		cmd(win, "pack " + id + " -side left");
		cmd(win, "pack propagate .b 0");
	"clear" =>
		cmd(win, "pack propagate .b 1");
		for (i := 0; i < buttonid; i++)
			cmd(win, "destroy .b.b" + string i);
		buttonid = 0;
	"cwd" =>
		if (n != 2)
			return "bad usage";
		cwd = hd tl toks;
		winname = Name + " " + cwd;
		tkclient->settitle(win, winname);
	* =>
		return "bad command";
	}
	cmd(win, "update");
	return nil;
}


RPCread: type (int, int, int, chan of (array of byte, string));

append(r: RPCread)
{
	t := r :: nil;
	while(rdreq != nil) {
		t = hd rdreq :: t;
		rdreq = tl rdreq;
	}
	rdreq = t;
}

insat(t: ref Tk->Toplevel, mark: string): int
{
	return cmd(t, ".ft.t compare insert == "+mark) == "1";
}

insininput(t: ref Tk->Toplevel): int
{
	if(cmd(t, ".ft.t compare insert >= outpoint") != "1")
		return 0;
	return cmd(t, ".ft.t compare {insert linestart} == {outpoint linestart}") == "1";
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

cursorcontrol(t: ref Tk->Toplevel, s: string): string
{
	l := len s;
	for(i := 0; i < l; i++) {
		case s[i] {
		    '\b' =>
			pre := "";
			rem := "";
			if(i + 1 < l)
				rem = s[i+1:];
			if(i == 0) {	# erase existing character in line
				if(tk->cmd(t, ".ft.t get " +
					"{outpoint linestart} outpoint") != "")
				    cmd(t, ".ft.t delete outpoint-1char");
			} else {
				if(s[i-1] != '\n')	# don't erase newlines
					i--;
				if(i)
					pre = s[:i];
			}
			s = pre + rem;
			l = len s;
			i = len pre - 1;
		    '\r' =>
			s[i] = '\n';
			if(i + 1 < l && s[i+1] == '\n')	# \r\n
				s = s[:i] + s[i+1:];
			else if(i > 0 && s[i-1] == '\n')	# \n\r
				s = s[:i-1] + s[i:];
			l = len s;
		    '\0' =>
			s[i] = Sys->UTFerror;
		}
	}
	return s;
}

editor(t: ref Tk->Toplevel, ecmd: string)
{
	s, snarf: string;

	case ecmd {
	"scroll" =>
		menuindex = "0";
		scrolling = 1;
		cmd(t, ".m entryconfigure 0 -text noscroll -command {send edit noscroll}");
	"noscroll" =>
		menuindex = "0";
		scrolling = 0;
		cmd(t, ".m entryconfigure 0 -text scroll -command {send edit scroll}");
	"cut" =>
		menuindex = "1";
		cut(t, 1);
	"paste" =>
		menuindex = "2";
		paste(t);
	"snarf" =>
		menuindex = "3";
		if(cmd(t, ".ft.t tag ranges sel") == "")
			break;
		snarf = tk->cmd(t, ".ft.t get sel.first sel.last");
		tkclient->snarfput(snarf);
	"send" =>
		menuindex = "4";
		if(cmd(t, ".ft.t tag ranges sel") != ""){
			snarf = tk->cmd(t, ".ft.t get sel.first sel.last");
			tkclient->snarfput(snarf);
		}else{
			snarf = tkclient->snarfget();
		}
		if(snarf != "")
			s = snarf;
		else
			return;
		if(s[len s-1] != '\n' && s[len s-1] != EOT)
			s[len s] = '\n';
		simulatetype(t, s);
	}
	cmd(t, "update");
}

simulatetype(t: ref Tk->Toplevel, s: string)
{
	if(rawon){
		rawinput += s;
	}else{
		cmd(t, ".ft.t see end; .ft.t insert end '"+s);
		cmd(t, ".ft.t mark set insert end");
		tk->cmd(t, ".ft.t tag remove sel sel.first sel.last");
	}
}

cut(t: ref Tk->Toplevel, snarfit: int)
{
	if(cmd(t, ".ft.t tag ranges sel") == "")
		return;
	if(snarfit)
		tkclient->snarfput(tk->cmd(t, ".ft.t get sel.first sel.last"));
	cmd(t, ".ft.t delete sel.first sel.last");
}

paste(t: ref Tk->Toplevel)
{
	snarf := tkclient->snarfget();
	if(snarf == "")
		return;
	cut(t, 0);
	if(rawon && int cmd(t, ".ft.t compare insert >= outpoint")){
		rawinput += snarf;
	}else{
		cmd(t, ".ft.t insert insert '"+snarf);
		cmd(t, ".ft.t tag add sel insert-"+string len snarf+"chars insert");
	}
}

sendinput(t: ref Tk->Toplevel)
{
	input: string;
	if(rawon)
		input = rawinput;
	else
		input = tk->cmd(t, ".ft.t get outpoint end");
	if(rdreq == nil || (input == nil && len partialread == 0))
		return;
	r := hd rdreq;
	(chars, bytes, partial) := triminput(r.nbytes, input, partialread);
	if(bytes == nil)
		return;	# no terminator yet
	rdreq = tl rdreq;

	alt {
	r.rc <-= (bytes, nil) =>
		# check that it really was sent
		alt {
		r.rc <-= (nil, nil) =>
			;
		* =>
			return;
		}
	* =>
		return;	# requester has disappeared; ignore his request and try another
	}
	if(rawon)
		rawinput = rawinput[chars:];
	else
		cmd(t, ".ft.t mark set outpoint outpoint+" + string chars + "chars");
	partialread = partial;
}

# read at most nr bytes from the input string, returning the number of characters
# consumed, the bytes to be read, and any remaining bytes from a partially
# read multibyte UTF character.
triminput(nr: int, input: string, partial: array of byte): (int, array of byte, array of byte)
{
	if(nr <= len partial)
		return (0, partial[0:nr], partial[nr:]);
	if(holding)
		return (0, nil, partial);

	# keep the array bounds within sensible limits
	if(nr > len input*Sys->UTFmax)
		nr = len input*Sys->UTFmax;
	buf := array[nr+Sys->UTFmax] of byte;
	t := len partial;
	buf[0:] = partial;

	hold := !rawon;
	i := 0;
	while(i < len input){
		c := input[i++];
		# special case for ^D - don't read the actual ^D character
		if(!rawon && c == EOT){
			hold = 0;
			break;
		}

		t += sys->char2byte(c, buf, t);
		if(c == '\n' && !rawon){
			hold = 0;
			break;
		}
		if(t >= nr)
			break;
	}
	if(hold){
		for(j := i; j < len input; j++){
			c := input[j];
			if(c == '\n' || c == EOT)
				break;
		}
		if(j == len input)
			return (0, nil, partial);
		# strip ^D when next read would read it, otherwise
		# we'll give premature EOF.
		if(i == j && input[i] == EOT)
			i++;
	}
	partial = nil;
	if(t > nr){
		partial = buf[nr:t];
		t = nr;
	}
	return (i, buf[0:t], partial);
}

newsh(ctxt: ref Context, ioc: chan of (int, ref FileIO, ref FileIO, string, ref FileIO),
			args: list of string)
{
	pid := sys->pctl(sys->NEWFD, nil);

	sh := load Command "/dis/sh.dis";
	if(sh == nil) {
		ioc <-= (0, nil, nil, nil, nil);
		return;
	}

	tty := "cons."+string pid;

	sys->bind("#s","/chan",sys->MBEFORE);
	fio := sys->file2chan("/chan", tty);
	fioctl := sys->file2chan("/chan", tty + "ctl");
	shctl := sys->file2chan("/chan", "shctl");
	ioc <-= (pid, fio, fioctl, "/chan/"+tty, shctl);
	if(fio == nil || fioctl == nil || shctl == nil)
		return;

	sys->bind("/chan/"+tty, "/dev/cons", sys->MREPL);
	sys->bind("/chan/"+tty+"ctl", "/dev/consctl", sys->MREPL);

	fd0 := sys->open("/dev/cons", sys->OREAD|sys->ORCLOSE);
	fd1 := sys->open("/dev/cons", sys->OWRITE);
	fd2 := sys->open("/dev/cons", sys->OWRITE);

	{
		sh->init(ctxt, "sh" :: "-n" :: args);
	}exception{
	"fail:*" =>
		exit;
	}
}

cmd(top: ref Tk->Toplevel, c: string): string
{
	s:= tk->cmd(top, c);
#	sys->print("* %s\n", c);
	if (s != nil && s[0] == '!')
		sys->fprint(sys->fildes(2), "wmsh: tk error on '%s': %s\n", c, s);
	return s;
}

itemsize(top: ref Tk->Toplevel, item: string): (int, int)
{
	w := int tk->cmd(top, item + " cget -actwidth");
	h := int tk->cmd(top, item + " cget -actheight");
	b := int tk->cmd(top, item + " cget -borderwidth");
	return (w+b, h+b);
}
