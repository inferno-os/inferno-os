implement Wmprof;

include "sys.m";
	sys: Sys;
include "bufio.m";
	bufio: Bufio;
	Iobuf: import bufio;
include "draw.m";
	draw: Draw;
include "tk.m";
	tk: Tk;
include "tkclient.m";
	tkclient: Tkclient;
include "arg.m";
	arg: Arg;
include "profile.m";

Prof: module{
	init0: fn(ctxt: ref Draw->Context, argv: list of string): Profile->Prof;
};

prof: Prof;

Wmprof: module{
	init: fn(ctxt: ref Draw->Context, argl: list of string);
};

usage(s: string)
{
	sys->fprint(sys->fildes(2), "wm/prof: %s\n", s);
	sys->fprint(sys->fildes(2), "usage: wm/prof [-e] [-m modname]... cmd [arg ... ]");
	exit;
}

TXTBEGIN: con 3;

init(ctxt: ref Draw->Context, argl: list of string)
{
	sys = load Sys Sys->PATH;
	bufio = load Bufio Bufio->PATH;
	draw = load Draw Draw->PATH;
	tk = load Tk Tk->PATH;
	tkclient = load Tkclient Tkclient->PATH;
	arg = load Arg Arg->PATH;
	
	if(ctxt == nil)
		fatal("wm not running");
	sys->pctl(Sys->NEWPGRP, nil);

	arg->init(argl);
	while((o := arg->opt()) != 0){
		case(o){
			'e' => ;
			'm' =>
				if(arg->arg() == nil)
					usage("missing module/file");
			's' =>
				if(arg->arg() == nil)
					usage("missing sample rate");
			* => 
				usage(sys->sprint("unknown option -%c", o));
		}
	}

	stats := execprof(ctxt, argl);
	if(stats.mods == nil)
		exit;

	tkclient->init();
	(win, wmc) := tkclient->toplevel(ctxt, nil, hd argl, Tkclient->Resize|Tkclient->Hide);
	tkc := chan of string;
	tk->namechan(win, tkc, "tkc");
	for(i := 0; i < len wincfg; i++)
		cmd(win, wincfg[i]);
	tkclient->onscreen(win, nil);
	tkclient->startinput(win, "kbd"::"ptr"::nil);
	createmenu(win, stats);
	curc := 0;
	cura := newprint(win, stats, curc);
	
	for(;;){
		alt{
			c := <-win.ctxt.kbd =>
				tk->keyboard(win, c);
			c := <-win.ctxt.ptr =>
				tk->pointer(win, *c);
			c := <-win.ctxt.ctl or
			c = <-win.wreq or
			c = <-wmc =>
				tkclient->wmctl(win, c);
			c := <- tkc =>
				(nil, toks) := sys->tokenize(c, " ");
				case(hd toks){
					"b" =>
						if(curc > 0)
							cura = newprint(win, stats, --curc);
					"f" =>
						if(curc < len stats.mods - 1)
							cura = newprint(win, stats, ++curc);
					"s" =>
						if(cura  != nil)
							scroll(win, cura);
					"m" =>
						x := cmd(win, ".f cget actx");
						y := cmd(win, ".f cget acty");
						cmd(win, ".f.menu post " + x + " " + y);
					* =>
						curc = int hd toks;
						cura = newprint(win, stats, curc);
				}
		}
	}
}

execprof(ctxt: ref Draw->Context, argl: list of string): Profile->Prof
{
	{
		prof = load Prof "/dis/prof.dis";
		if(prof == nil)
			fatal("cannot load profiler");
		return prof->init0(ctxt, hd argl :: "-g" :: tl argl);
	}
	exception{
		"fail:*" =>
			return (nil, 0, nil);
	}
	return (nil, 0, nil);
}

newprint(win: ref Tk->Toplevel, p: Profile->Prof, i: int): array of int
{
	cmd(win, ".f.t delete 1.0 end");
	cmd(win, "update");
	m0, m1: list of Profile->Modprof;
	for(m := p.mods; m != nil && --i >= 0; m = tl m)
		m0 = m;
	if(m == nil)
		return nil;
	m1 = tl m;	
	(name, nil, spath, nil, line, nil, nil, tot, nil, nil) := hd m;
	name0 := name1 := "nil";
	if(m0 != nil)
		name0 = (hd m0).name;
	if(m1 != nil)
		name1 = (hd m1).name;
	a := len name;
	name += sys->sprint(" (%d%%) ", percent(tot, p.total));
	cmd(win, ".f.t insert end {" + name + "        <- " + name0 + "        -> " + name1 + "}");
	tag := gettag(win, tot, p.total);
	cmd(win, ".f.t tag add " + tag + " " + "1.0" + " " + "1." + string a);
	cmd(win, ".f.t insert end \n\n");
	cmd(win, "update");
	lineno := TXTBEGIN;
	bio := bufio->open(spath, Bufio->OREAD);
	if(bio == nil)
		return nil;
	i = 1;
	ll := len line;
	while((s := bio.gets('\n')) != nil){
		f := 0;
		if(i < ll)
			f = line[i];
		a = len s;
		if(f > 0)
			s = sys->sprint("%d%%\t%s", percent(f, tot), s);
		else
			s = sys->sprint("- \t%s", s);
		b := len s;
		cmd(win, ".f.t insert end " + tk->quote(s));
		tag = gettag(win, f, tot);
		cmd(win, ".f.t tag add " + tag + " " + string lineno + "." + string (b-a) + " " + string lineno + "." + string (b-1));
		cmd(win, "update");
		lineno++;
		i++;
	}
	return line;
}

index(win: ref Tk->Toplevel, x: int, y: int): int
{
	t := cmd(win, ".f.t index @" + string x + "," + string y);
	(nil, l) := sys->tokenize(t, ".");
# sys->print("%d,%d -> %s\n", x, y, t);
	return int hd l;
}

winextent(win: ref Tk->Toplevel): (int, int)
{
	w := int cmd(win, ".f.t cget -actwidth");
	h := int cmd(win, ".f.t cget -actheight");
	lw := index(win, 0, 0);
	uw := index(win, w-1, h-1);
	return (lw, uw);
}

see(win: ref Tk->Toplevel, line: int)
{
	cmd(win, ".f.t see " + string line + ".0");
	cmd(win, "update");	
}

scroll(win: ref Tk->Toplevel, line: array of int)
{
	(nil, uw) := winextent(win);
	lno := TXTBEGIN;
	ll := len line;
	for(i := 1; i < ll; i++){
		n := line[i];
		if(n > 0 && lno > uw){
			see(win, lno);
			return;
		}
		lno++;
	}
	lno = TXTBEGIN;
	ll = len line;
	for(i = 1; i < ll; i++){
		n := line[i];
		if(n > 0){
			see(win, lno);
			return;
		}
		lno++;
	}
}

cmd(top: ref Tk->Toplevel, s: string): string
{
	# sys->print("%s\n", s);
	e := tk->cmd(top, s);
	if (e != nil && e[0] == '!')
		sys->fprint(sys->fildes(2), "tk error on '%s': %s\n", s, e);
	return e;
}

fatal(s: string)
{
	sys->fprint(sys->fildes(2), "%s\n", s);
	exit;
}

MENUMAX: con 20;

createmenu(top: ref Tk->Toplevel, p: Profile->Prof )
{
	mn := ".f.menu";
	cmd(top, "menu " + mn);
	i := j := 0;
	for(m := p.mods; m != nil; m = tl m){
		name := (hd m).name;
		cmd(top, mn + " add command -label " + name + " -command {send tkc " + string i + "}");
		i++;
		j++;
		if(j == MENUMAX && tl m != nil){
			cmd(top, mn + " add cascade -label MORE -menu " + mn + ".menu");
			mn += ".menu";
			cmd(top, "menu " + mn);
			j = 0;
		}
	}
}

tags := array[256]  of { * => byte 0 };

gettag(win: ref Tk->Toplevel, n: int, d: int): string
{
	i := int ((real n/real d) * real 15);
	if(i < 0 || i > 15)
		i = 0;
	s := "tag" + string i;
	if(tags[i] == byte 0){
		rgb := "#" + hex2(255-64*0)+hex2(255-64*(i/4))+hex2(255-64*(i%4));
		cmd(win, ".f.t tag configure " + s + " -fg black -bg " + rgb);
		tags[i] = byte 1;
	}
	return s;
}

percent(n: int, d: int): int
{
	return int ((real n/real d) * real 100);
}

hex(i: int): int
{
	if(i < 10)
		return i+'0';
	else
		return i-10+'A';
}

hex2(i: int): string
{
	s := "00";
	s[0] = hex(i/16);
	s[1] = hex(i%16);
	return s;
}

wincfg := array[] of {
	"frame .f",
	"text .f.t -width 809 -height 500 -state disabled -wrap char -bg white -yscrollcommand {.f.s set}",
	"scrollbar .f.s -orient vertical -command {.f.t yview}",
	"frame .i",
	"button .i.b -bitmap small_color_left.bit -command {send tkc b}",
	"button .i.f -bitmap small_color_right.bit -command {send tkc f}",
	"button .i.s -bitmap small_find.bit -command {send tkc s}",
	"button .i.m -bitmap small_reload.bit -command {send tkc m}",

	"pack .i.b -side left",
	"pack .i.f -side left",
	"pack .i.s -side left",
	"pack .i.m -side left",

	"pack .f.s -fill y -side left",
	"pack .f.t -fill both -expand 1",

	"pack .i -fill x",
	"pack .f -fill both -expand 1",
	"pack propagate . 0",

	"update",
};