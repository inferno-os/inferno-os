implement Mashbuiltin;

#
#	"tk" builtin.
#
#	tk clear		- clears the text frame
#	tk def button name value
#	tk def ibutton name value image
#	tk def menu name
#	tk def item menu name value
#	tk dialog title mesg default label ...
#	tk dump			- print commands to reconstruct toolbar
#	tk dump name ...
#	tk env			- update tk execution env
#	tk file title dir pattern ...
#	tk geom
#	tk layout name ...
#	tk notice message
#	tk sel			- print selection
#	tk sget			- print snarf
#	tk sput string		- put snarf
#	tk string mesg		- get string
#	tk taskbar string
#	tk text			- print window text
#

include	"mash.m";
include	"mashparse.m";
include	"wmlib.m";
include	"dialog.m";
include	"selectfile.m";

mashlib:	Mashlib;
wmlib:		Wmlib;
dialog:	Dialog;
selectfile:	Selectfile;

Env, Stab, Symb:	import mashlib;
sys, bufio, tk:		import mashlib;
gtop, gctxt, ident:	import mashlib;

Iobuf:	import bufio;

tkitems:	ref Stab;
tklayout:	list of string;
tkenv:	ref Env;
tkserving:	int = 0;

Cbutton, Cibutton, Cmenu:	con Cprivate + iota;

Cmark:	con 3;
BUTT:	con ".b.";

#
#	Interface to catch the use as a command.
#
init(nil: ref Draw->Context, args: list of string)
{
	raise "fail: " + hd args + " not loaded";
}

#
#	Used by whatis.
#
name(): string
{
	return "tk";
}

#
#	Install command and initialize state.
#
mashinit(nil: list of string, lib: Mashlib, this: Mashbuiltin, e: ref Env)
{
	mashlib = lib;
	if (gctxt == nil) {
		e.report("tk: no graphics context");
		return;
	}
	if (gtop == nil) {
		e.report("tk: not run from wmsh");
		return;
	}
	wmlib = load Wmlib Wmlib->PATH;
	if (wmlib == nil) {
		e.report(sys->sprint("tk: could not load %s: %r", Wmlib->PATH));
		return;
	}
	dialog = load Dialog Dialog->PATH;
	if (dialog == nil) {
		e.report(sys->sprint("tk: could not load %s: %r", Dialog->PATH));
		return;
	}
	selectfile = load Selectfile Selectfile->PATH;
	if (selectfile == nil) {
		e.report(sys->sprint("tk: could not load %s: %r", Selectfile->PATH));
		return;
	}
	wmlib->init();
	dialog->init();
	selectfile->init();
	e.defbuiltin("tk", this);
	tkitems = Stab.new();
}

#
#	Execute the "tk" builtin.
#
mashcmd(e: ref Env, l: list of string)
{
	# must lock
	l = tl l;
	if (l == nil)
		return;
	s := hd l;
	l = tl l;
	case s {
	"clear" =>
		if (l != nil) {
			e.usage("tk clear");
			return;
		}
		clear(e);
	"def" =>
		define(e, l);
	"dialog" =>
		if (len l < 4) {
			e.usage("tk dialog title mesg default label ...");
			return;
		}
		dodialog(e, l);
	"dump" =>
		dump(e, l);
	"env" =>
		if (l != nil) {
			e.usage("tk env");
			return;
		}
		tkenv = e.clone();
		tkenv.flags |= mashlib->ETop;
	"file" =>
		if (len l < 3) {
			e.usage("tk file title dir pattern ...");
			return;
		}
		dofile(e, hd l, hd tl l, tl tl l);
	"geom" =>
		if (l != nil) {
			e.usage("tk geom");
			return;
		}
		e.output(wmlib->geom(gtop));
	"layout" =>
		layout(e, l);
	"notice" =>
		if (len l != 1) {
			e.usage("tk notice message");
			return;
		}
		notice(hd l);
	"sel" =>
		if (l != nil) {
			e.usage("tk sel");
			return;
		}
		sel(e);
	"sget" =>
		if (l != nil) {
			e.usage("tk sget");
			return;
		}
		e.output(wmlib->snarfget());
	"sput" =>
		if (len l != 1) {
			e.usage("tk sput string");
			return;
		}
		wmlib->snarfput(hd l);
	"string" =>
		if (len l != 1) {
			e.usage("tk string mesg");
			return;
		}
		e.output(dialog->getstring(gctxt, gtop.image, hd l));
		focus(e);
	"taskbar" =>
		if (len l != 1) {
			e.usage("tk taskbar string");
			return;
		}
		e.output(wmlib->taskbar(gtop, hd l));
	"text" =>
		if (l != nil) {
			e.usage("tk text");
			return;
		}
		text(e);
	* =>
		e.report(sys->sprint("tk: unknown command: %s", s));
	}
}

#
#	Execute tk command and check for error.
#
tkcmd(e: ref Env, s: string): string
{
	if (e != nil && (e.flags & mashlib->EDumping))
		sys->fprint(e.stderr, "+ %s\n", s);
	r := tk->cmd(gtop, s);
	if (r != nil && r[0] == '!' && e != nil)
		sys->fprint(e.stderr, "tk: %s\n\tcommand was %s\n", r[1:], s);
	return r;
}

focus(e: ref Env)
{
	tkcmd(e, "focus .ft.t");
}

#
#	Serve loop.
#
tkserve(mash: chan of string)
{
	mashlib->reap();
	for (;;) {
		cmd := <-mash;
		if (mashlib->servechan != nil && len cmd > 1) {
			cmd[len cmd - 1] = '\n';
			mashlib->servechan <-= array of byte cmd[1:];
		}
	}
}

notname(e: ref Env, s: string)
{
	e.report(sys->sprint("tk: %s: malformed name", s));
}

#
#	Define a button, menu or item.
#
define(e: ref Env, l: list of string)
{
	if (l == nil) {
		e.usage("tk def definition");
		return;
	}
	s := hd l;
	l = tl l;
	case s {
	"button" =>
		if (len l != 2) {
			e.usage("tk def button name value");
			return;
		}
		s = hd l;
		if (!ident(s)) {
			notname(e, s);
			return;
		}
		i := tkitems.update(s, Svalue, tl l, nil, nil);
		i.tag = Cbutton;
	"ibutton" =>
		if (len l != 3) {
			e.usage("tk def ibutton name value path");
			return;
		}
		s = hd l;
		if (!ident(s)) {
			notname(e, s);
			return;
		}
		i := tkitems.update(s, Svalue, tl l, nil, nil);
		i.tag = Cibutton;
	"menu" =>
		if (len l != 1) {
			e.usage("tk def menu name");
			return;
		}
		s = hd l;
		if (!ident(s)) {
			notname(e, s);
			return;
		}
		i := tkitems.update(s, Svalue, nil, nil, nil);
		i.tag = Cmenu;
	"item" =>
		if (len l != 3) {
			e.usage("tk def item menu name value");
			return;
		}
		s = hd l;
		i := tkitems.find(s);
		if (i == nil || i.tag != Cmenu) {
			e.report(s + ": not a menu");
			return;
		}
		l = tl l;
		i.value = updateitem(i.value, hd l, hd tl l);
	* =>
		e.report("tk: " + s + ": unknown command");
	}
}

#
#	Update a menu item.
#
updateitem(l: list of string, c, v: string): list of string
{
	r: list of string;
	while (l != nil) {
		w := hd l;
		l = tl l;
		d := hd l;
		l = tl l;
		if (d == c) {
			r = c :: v :: r;
			c = nil;
		} else
			r = d :: w :: r;
	}
	if (c != nil)
		r = c :: v :: r;
	return mashlib->revstrs(r);
}

items(e: ref Env, l: list of string): list of ref Symb
{
	r: list of ref Symb;
	while (l != nil) {
		i := tkitems.find(hd l);
		if (i == nil) {
			e.report(hd l + ": not an item");
			return nil;
		}
		r = i :: r;
		l = tl l;
	}
	return r;
}

deleteall(e: ref Env, l: list of string)
{
	while (l != nil) {
		tkcmd(e, "destroy " + BUTT + hd l);
		l = tl l;
	}
}

sendcmd(c: string): string
{
	return tk->quote("send mash " + tk->quote(c));
}

addbutton(e: ref Env, w, t, c: string)
{
	tkcmd(e, sys->sprint("button %s%s -%s %s -command %s", BUTT, t, w, t, sendcmd(c)));
}

addimage(e: ref Env, t, f: string)
{
	r := tkcmd(nil, sys->sprint("image create bitmap %s -file %s.bit -maskfile %s.mask", t, f, f));
	if (r != nil && r[0] == '!')
		tkcmd(e, sys->sprint("image create bitmap %s -file %s.bit", t, f));
}

additem(e: ref Env, s: ref Symb)
{
	case s.tag {
	Cbutton =>
		addbutton(e, "text", s.name, hd s.value);
	Cibutton =>
		addimage(e, s.name, hd tl s.value);
		addbutton(e, "image", s.name, hd s.value);
	Cmenu =>
		t := s.name;
		tkcmd(e, sys->sprint("menubutton %s%s -text %s -menu %s%s.menu -underline -1", BUTT, t, t, BUTT,t));
		t += ".menu";
		tkcmd(e, "menu " + BUTT + t);
		t = BUTT + t;
		l := s.value;
		while (l != nil) {
			v := sendcmd(hd l);
			l = tl l;
			c := tk->quote(hd l);
			l = tl l;
			tkcmd(e, sys->sprint("%s add command -label %s -command %s", t, c, v));
		}
	}
}

pack(e: ref Env, l: list of string)
{
	s := "pack";
	while (l != nil) {
		s += sys->sprint(" %s%s", BUTT, hd l);
		l = tl l;
	}
	s += " -side left";
	tkcmd(e, s);
}

propagate(e: ref Env)
{
	tkcmd(e, "pack propagate . 0");
	tkcmd(e, "update");
}

unmark(r: list of ref Symb)
{
	while (r != nil) {
		s := hd r;
		case s.tag {
		Cbutton + Cmark or Cibutton + Cmark or Cmenu + Cmark =>
			s.tag -= Cmark;
		}
		r = tl r;
	}
}

#
#	Check that the layout tags are unique.
#
unique(e: ref Env, r: list of ref Symb): int
{
	u := 1;
loop:
	for (l := r; l != nil; l = tl l) {
		s := hd l;
		case s.tag {
		Cbutton + Cmark or Cibutton + Cmark or Cmenu + Cmark =>
			e.report(sys->sprint("layout: tag %s repeated", s.name));
			u = 0;
			break loop;
		Cbutton or Cibutton or Cmenu =>
			s.tag += Cmark;
		}
	}
	unmark(r);
	return u;
}

#
#	Update the button bar layout and the environment.
#	Maybe spawn the server.
#
layout(e: ref Env, l: list of string)
{
	r := items(e, l);
	if (r == nil && l != nil)
		return;
	if (!unique(e, r))
		return;
	if (tklayout != nil)
		deleteall(e, tklayout);
	n := len r;
	a := array[n] of ref Symb;
	while (--n >= 0) {
		a[n] = hd r;
		r = tl r;
	}
	n = len a;
	for (i := 0; i < n; i++)
		additem(e, a[i]);
	pack(e, l);
	propagate(e);
	tklayout = l;
	tkenv = e.clone();
	tkenv.flags |= mashlib->ETop;
	if (!tkserving) {
		tkserving = 1;
		mash := chan of string;
		tk->namechan(gtop, mash, "mash");
		spawn tkserve(mash);
		mashlib->startserve = 1;
	}
}

dumpbutton(out: ref Iobuf, w: string, s: ref Symb)
{
	out.puts(sys->sprint("tk def %s %s %s", w, s.name, mashlib->quote(hd s.value)));
	if (s.tag == Cibutton)
		out.puts(sys->sprint(" %s", mashlib->quote(hd tl s.value)));
	out.puts(";\n");
}

#
#	Print commands to reconstruct toolbar.
#
dump(e: ref Env, l: list of string)
{
	r: list of ref Symb;
	if (l != nil)
		r = items(e, l);
	else
		r = tkitems.all();
	out := e.outfile();
	if (out == nil)
		return;
	while (r != nil) {
		s := hd r;
		case s.tag {
		Cbutton =>
			dumpbutton(out, "button", s);
		Cibutton =>
			dumpbutton(out, "ibutton", s);
		Cmenu =>
			t := s.name;
			out.puts(sys->sprint("tk def menu %s;\n", t));
			i := s.value;
			while (i != nil) {
				v := hd i;
				i = tl i;
				c := hd i;
				i = tl i;
				out.puts(sys->sprint("tk def item %s %s %s;\n", t, c, mashlib->quote(v)));
			}
		}
		r = tl r;
	}
	if (l == nil) {
		out.puts("tk layout");
		for (l = tklayout; l != nil; l = tl l) {
			out.putc(' ');
			out.puts(hd l);
		}
		out.puts(";\n");
	}
	out.close();
}

clear(e: ref Env)
{
	tkcmd(e, ".ft.t delete 1.0 end; update");
}

dofile(e: ref Env, title, dir: string, pats: list of string)
{
	e.output(selectfile->filename(gctxt, gtop.image, title, pats, dir));
}

sel(e: ref Env)
{
	sel := tkcmd(e, ".ft.t tag ranges sel");
	if (sel != nil) {
		s := tkcmd(e, ".ft.t dump " + sel);
		e.output(s);
	}
}

text(e: ref Env)
{
	sel := tkcmd(e, ".ft.t tag ranges sel");
	if (sel != nil)
		tkcmd(e, ".ft.t tag remove sel " + sel);
	s := tkcmd(e, ".ft.t dump 1.0 end");
	if (sel != nil)
		tkcmd(e, ".ft.t tag add sel " + sel);
	e.output(s);
}

notice0 := array[] of
{
	"frame .f -borderwidth 2 -relief groove -padx 3 -pady 3",
	"frame .f.f",
	"label .f.f.l -bitmap error -foreground red",
};

notice1 := array[] of
{
	"button .f.b -text {  OK  } -command {send cmd done}",
	"pack .f.f.l .f.f.m -side left -expand 1 -padx 10 -pady 10",
	"pack .f.f .f.b -padx 10 -pady 10",
	"pack .f",
	"update; cursor -default",
};

notice(mesg: string)
{
	x := int tk->cmd(gtop, ". cget -x");
	y := int tk->cmd(gtop, ". cget -y");
	where := sys->sprint("-x %d -y %d", x + 30, y + 30);
	t := tk->toplevel(gctxt.screen, where + " -borderwidth 2 -relief raised");
	cmd := chan of string;
	tk->namechan(t, cmd, "cmd");
	wmlib->tkcmds(t, notice0);
	tk->cmd(t, "label .f.f.m -text '" + mesg);
	wmlib->tkcmds(t, notice1);
	<- cmd;
}

dodialog(e: ref Env, l: list of string)
{
	title := hd l;
	l = tl l;
	msg := hd l;
	l = tl l;
	x := dialog->prompt(gctxt, gtop.image, nil, title, msg, int hd l, tl l);
	e.output(string x);
	focus(e);
}
