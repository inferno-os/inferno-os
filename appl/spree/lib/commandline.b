implement Commandline;

include "sys.m";
	sys: Sys;
include "draw.m";
include "tk.m";
	tk: Tk;
include "tkclient.m";
	tkclient: Tkclient;
include "commandline.m";

Debug: con 0;

nomodule(modpath: string)
{
	sys->fprint(stderr(), "fibs: couldn't load %s: %r\n", modpath);
	raise "fail:bad module";
}

init()
{	sys = load Sys Sys->PATH;

	tk = load Tk Tk->PATH;
	if (tk == nil) nomodule(Tk->PATH);

	tkclient = load Tkclient Tkclient->PATH;
	if (tkclient == nil) nomodule(Tkclient->PATH);
	tkclient->init();
}

Cmdline.new(top: ref Tk->Toplevel, w, textopts: string): (ref Cmdline, chan of string)
{
	window_cfg := array[] of {
		"frame " + w,
		"scrollbar " + w + ".scroll -command {" + w + ".t yview}",
		"text " + w + ".t -yscrollcommand {" + w + ".scroll set} " + textopts,
		"pack " + w + ".scroll -side left -fill y",
		"pack " + w + ".t -fill both -expand 1",
	
		"bind " + w + ".t <Key> {send evch k {%A}}",
		"bind " + w + ".t <Control-d> {send evch k {%A}}",
		"bind " + w + ".t <Control-u> {send evch k {%A}}",
		"bind " + w + ".t <Control-w> {send evch k {%A}}",
		"bind " + w + ".t <Control-h> {send evch k {%A}}",
		# treat button 2 and button 3 the same so we're alright with a 2-button mouse
		"bind " + w + ".t <ButtonPress-2> {send evch b %x %y}",
		"bind " + w + ".t <ButtonPress-3> {send evch b %x %y}",
		w + ".t mark set outpoint end",
		w + ".t mark gravity outpoint left",
		w + ".t mark set inpoint end",
		w + ".t mark gravity inpoint left",
	};
	evch := chan of string;
	tk->namechan(top, evch, "evch");

	for (i := 0; i < len window_cfg; i++) {
		e := cmd(top, window_cfg[i]);
		if (e != nil && e[0] == '!')
			break;
	}

	err := tk->cmd(top, "variable lasterror");
	if (err != nil) {
		sys->fprint(stderr(), "error in commandline config: %s\n", err);
		raise "fail:commandline config error";
	}
	cmd(top, w + ".t mark set insert end;" + w + ".t see insert");
	return (ref Cmdline(w, top), evch);
}

Cmdline.focus(cmdl: self ref Cmdline)
{
	cmd(cmdl.top, "focus " + cmdl.w + ".t");
}

Cmdline.event(cmdl: self ref Cmdline, e: string): list of string
{
	case e[0] {
	'k' =>
		return handle_key(cmdl, e[2:]);
	'b' =>
		;
	}
	return nil;
}

BS:		con 8;		# ^h backspace character
BSW:		con 23;		# ^w bacspace word
BSL:		con 21;		# ^u backspace line

handle_key(cmdl: ref Cmdline, c: string): list of string
{
	(w, top) := (cmdl.w, cmdl.top);
	# don't allow editing of the text before the inpoint.
	if (int cmd(top, w + ".t compare insert < inpoint"))
		return nil;
	lines: list of string;
	char := c[1];
	if (char == '\\')
		char = c[2];
	case char {
	* =>
		cmd(top, w + ".t insert insert "+c+" {}");
	'\n' =>
		cmd(top, w + ".t insert insert "+c+" {}");
		lines = sendinput(cmdl);
	BSL or BSW or BS =>
		delpoint: string;
		case char {
		BSL =>	delpoint = "{insert linestart}";
		BSW =>	delpoint = "{insert -1char wordstart}";	# wordstart isn't ideal
		BS  =>	delpoint = "{insert-1char}";
		}
		if (int cmd(top, w + ".t compare inpoint < " + delpoint))
			cmd(top, w + ".t delete "+delpoint+" insert");
		else
			cmd(top, w + ".t delete inpoint insert");
	}
	cmd(top, w + ".t see insert;update");
	return lines;
}

sendinput(cmdl: ref Cmdline): list of string
{
	(w, top) := (cmdl.w, cmdl.top);
	# loop through all the lines that have been entered,
	# processing each one in turn.
	nl, lines: list of string;
	for (;;) {
		input: string;
		input = cmd(top, w + ".t get inpoint end");
		if (len input == 0)
			break;
		for (i := 0; i < len input; i++)
			if (input[i] == '\n')
				break;
		if (i >= len input)
			break;
		cmd(top, w + ".t mark set outpoint inpoint+"+string (i+1)+"chars");
		cmd(top, w + ".t mark set inpoint outpoint");
		lines = input[0:i+1] :: lines;
	}
	for (; lines != nil; lines = tl lines)
		nl = hd lines :: nl;
	return nl;
}

add(cmdl: ref Cmdline, t: string, n: int)
{
	(w, top) := (cmdl.w, cmdl.top);
	cmd(top, w + ".t insert outpoint " + t);
	cmd(top, w + ".t mark set outpoint outpoint+"+string n+"chars");
	cmd(top, w + ".t mark set inpoint outpoint");
	cmd(top, w + ".t see insert");
}

Cmdline.tagaddtext(cmdl: self ref Cmdline, t: list of (string, string))
{
	txt := "";
	n := 0;
	for (; t != nil; t = tl t) {
		(tags, s) := hd t;
		txt += " " + tk->quote(s) + " {" + tags + "}";
		n += len s;
	}
	add(cmdl, txt, n);
}

Cmdline.addtext(cmdl: self ref Cmdline, txt: string)
{
	if (Debug) sys->print("%s", txt);
	add(cmdl, tk->quote(txt) + " {}" , len txt);
}

Cmdline.maketag(cmdl: self ref Cmdline, name, options: string)
{
	cmd(cmdl.top, cmdl.w + ".t tag configure " + name + " " + options);
}

stderr(): ref Sys->FD
{
	return sys->fildes(2);
}

cmd(top: ref Tk->Toplevel, s: string): string
{
	e := tk->cmd(top, s);
	if (e != nil && e[0] == '!')
		sys->fprint(stderr(), "cmd error on '%s': %s\n", s, e);
	return e;
}
