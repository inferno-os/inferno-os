implement Samtk;

include "sys.m";
sys: Sys;
sprint, FD: import sys;

include "draw.m";
draw:	Draw;

include "samterm.m";
Context, Flayer, Text, Section: import Samterm;

include "tkclient.m";

include "samtk.m";

ctxt: ref Context;

tk:	Tk;
tkclient:	Tkclient;

tksam1 := array[] of {
	"frame .w",
	"scrollbar .w.s -command {send scroll}",
	"text .w.t -width 80w -height 8h",
	"pack .w.s -side left -fill y",
	"pack .w.t -fill both -expand 1",
	"pack .Wm_t -fill x",
	"pack .w -fill both -expand 1",
	"pack propagate . 0",
};

tkwork1 := array[] of {
	"frame .w",
	"scrollbar .w.s -command {send scroll}",
	"text .w.t -width 80w -height 20h",
	"pack .w.s -side left -fill y",
	"pack .w.t -fill both -expand 1",
	"pack .Wm_t -fill x",
	"pack .w -fill both -expand 1",
	"pack propagate . 0",
};

tkcmdlist := array[] of {
	"bind .w.t <Key> {send keys {%A}}",
	"bind .w.t <Key-\b> {send keys {%A}}",
	"bind .w.s <ButtonRelease-1> +{send scroll %s %b %y}",
	"bind .w.t <ButtonPress-1> +{send button1 %s %b %x %y}",
	"bind .w.t <ButtonRelease-1> +{send button1 %s %b %x %y}",
	"bind .w.t <Double-ButtonPress-1> {send button1 2 %b %x %y}",
	"bind .w.t <Double-ButtonRelease-1> {send button1 3 %b %x %y}",
	"bind .w.t <ButtonPress-2> {.m2 post %x %y; grab set .m2}",
	"bind .w.t <ButtonPress-3> {.m3 post %x %y; grab set .m3}",
	"bind . <Configure> {send titlesel resize}",
	"focus .w.t",
	"update"
};

menuidx := array[2] of {"0","0"};

init(c: ref Context)
{
	ctxt = c;
	sys = load Sys Sys->PATH;
	draw = load Draw Draw->PATH;
	tk = load Tk Tk->PATH;

	tkclient = load Tkclient Tkclient->PATH;
	tkclient->init();

	scrollpos = scrolllines = 0;
}

x := 10;
y := 10;

newflayer(tag, tp: int): ref Flayer
{
	if (ctxt.which != nil) {
		tk->cmd(ctxt.which.t,
			".Wm_t.title configure -background blue; update");
	}
	(t, cmdc) := tkclient->toplevel(ctxt.ctxt.screen, "-borderwidth 1 -relief raised", "SamTerm", Tkclient->Appl);
	tk->cmd(t, ". configure -x "+string x+" -y "+string y+"; update");

	if (x == 10 && y == 10) {
		y = 200;
	} else {
		x += 40;
		y += 40;
	}

	n := chanadd();
	ctxt.titlesel[n] = cmdc;
	tk->namechan(t, ctxt.menu3sel[n], "menu3");
	tk->namechan(t, ctxt.menu2sel[n], "menu2");
	tk->namechan(t, ctxt.buttonsel[n], "button1");
	tk->namechan(t, ctxt.keysel[n], "keys");
	tk->namechan(t, ctxt.scrollsel[n], "scroll");
	tk->namechan(t, ctxt.titlesel[n], "titlesel");

	lines: int;
	if (tp) {
		lines = 8;
		tkclient->tkcmds(t, tksam1);
		mkmenu2c(t);
	} else {
		lines = 20;
		tkclient->tkcmds(t, tkwork1);
		mkmenu2(t);
	}
	mkmenu3(t);
	tkclient->tkcmds(t, tkcmdlist);

	f := ref Flayer(
		tag,		# tag
		t,		# t
		"SamTerm",	# tkwin
		(0, 0),		# scope
		(0, 0),		# dot
		int tk->cmd(t, ".w.t cget actwidth"),		# screen width
		int tk->cmd(t, ".w.t cget actheight") / lines,	# lineheigth
		lines,		# lines
		(0, 1),		# scrollbar
		-1		# typepoint
	);
	ctxt.flayers[n] = f;
	return f;
}

menu2str := array [] of {
	"cut",
	"paste",
	"snarf",
	"look",
#	"exch",
	"send",		# storage for last pattern
};

menu3str := array [] of {
	"new",
	"zerox",
	"close",
	"write",
};

mkmenu2c(t: ref Tk->Toplevel)
{
	menus := array [NMENU2+1] of string;

	menus[0] = "menu .m2";
	for (i := 0; i < NMENU2; i++) {
		menus[i+1] = addmenuitem(2, "menu2", menu2str[i]);
	}
	tkclient->tkcmds(t, menus);
}

mkmenu2(t: ref Tk->Toplevel)
{
	menus := array [NMENU2+1] of string;

	menus[0] = "menu .m2";
	for (i := 0; i < NMENU2-1; i++) {
		menus[i+1] = addmenuitem(2, "menu2", menu2str[i]);
	}
	menus[NMENU2] = addmenuitem(2, "edit", "/");
	tkclient->tkcmds(t, menus);
}

mkmenu3(t: ref Tk->Toplevel)
{
	menus := array [NMENU3+len ctxt.menus+1] of string;

	menus[0] = "menu .m3";
	for (i := 0; i < NMENU3; i++) {
		menus[i+1] = addmenuitem(3, "menu3", menu3str[i]);
	}
	for (i = 0; i < len ctxt.menus; i++) {
		menus[i+NMENU3+1] = addmenuitem(3, "menu3", ctxt.menus[i].name);
	}
	tkclient->tkcmds(t, menus);
}

addmenuitem(d: int, m, s: string): string
{
	return sprint(".m%d add command -text %s -command {send %s %s}",
		d, s, m, s);
}

menuins(pos: int, s: string)
{
	for (i := 0; i < len ctxt.flayers; i++)
	   tk->cmd(ctxt.flayers[i].t,
	      sprint(".m3 insert %d command -text %s -command {send menu3 %s}",
		pos + NMENU3, s, s));
}

menudel(pos: int)
{
	for (i := 0; i < len ctxt.flayers; i++)
	    tk->cmd(ctxt.flayers[i].t, sprint(".m3 delete %d", pos + NMENU3));
}

hsetpat(s: string)
{
	for (i := 0; i < len ctxt.flayers; i++) {
	    fl := ctxt.flayers[i];
	    if (fl.tag != ctxt.cmd.tag) {
		tk->cmd(fl.t, ".m2 entryconfigure "
		        + string Search
		        + " -command {send menu2 search} -text '/" + s);
	    }
	}
}

lastsearchstring := "//";

setmenu(num : int,c : string){
		fl := ctxt.flayers[num];
		(nil, l) := sys->tokenize(c, " ");
		x1 := int hd l - 50;
		y1 := int hd tl l - int tk->cmd(fl.t, ".m"+string num+" yposition "+menuidx[num-2]) 
								- 10;
		tk->cmd(fl.t, ".m"+string num+" activate "+menuidx[num-2]+
			"; .m"+string num+" post "+string x1+" "+string y1+
			"; grab set .m"+string num+"; update");
}

titlectl(win: int, menu: string)
{
	tkclient->wmctl(ctxt.flayers[win].t, menu);
}

flraise(t: ref Text, fl: ref Flayer)
{
	nfls: list of ref Flayer;

	nfls = nil;
	t.flayers = fl :: dellist(t.flayers, fl);
	tk->cmd(fl.t, "raise .; focus .w.t; update");
}

dellist(fls: list of ref Flayer, fl: ref Flayer): list of ref Flayer
{
	if (fls == nil) return nil;
	if (hd fls == fl) return dellist(tl fls, fl);
	return hd fls :: dellist(tl fls, fl);
}

append(fls: list of ref Flayer, fl: ref Flayer): list of ref Flayer
{
	if (fls == nil) return fl :: nil;
	return hd fls :: append(tl fls, fl);
}

focus(fl: ref Flayer)
{
	tk->cmd(fl.t, "focus .w.t; update");
}

newcur(t: ref Text, fl: ref Flayer)
{
	if (ctxt.which == fl) return;
	flraise(t, fl);
	ctxt.which = fl;
	if (t != ctxt.cmd)
		ctxt.work = fl;
}

settitle(t: ref Text, s: string)
{
	sd := "";
	sz := "";
	if (t.state & Samterm->Dirty) sd = " (Dirty)";
	if (t != ctxt.cmd && (t.state & Samterm->LDirty)) sd = " (Modified)";
	if (len t.flayers > 1) sz = " (Zeroxed)";
	for (fls := t.flayers; fls != nil; fls = tl fls) {
		fl := hd fls;
		fl.tkwin = s;
		tkclient->settitle(fl.t, s + sd + sz);
		tk->cmd(fl.t, "update");
	}
}

resize(fl: ref Flayer)
{
	fl.lines = int tk->cmd(fl.t, ".w.t cget actheight") / fl.lineheigth;
}

allflayers(s: string)
{
	for (i := 0; i < len ctxt.texts; i++)
		for (fls := ctxt.texts[i].flayers; fls != nil; fls = tl fls) {
			fl := hd fls;
			tk->cmd(fl.t, s);
		}
}

setdot(fl: ref Flayer, l1, l2: int)
{
	tk->cmd(fl.t, ".w.t tag remove sel 0.0 end");

	fl.dot.first = l1;
	fl.dot.last = l2;
	if (l2 <= fl.scope.first)
		tk->cmd(fl.t, ".w.t mark set insert 0.0");
	else if (fl.scope.last <= l1)
		tk->cmd(fl.t, ".w.t mark set insert end");
	else {
		tk->cmd(fl.t, sprint(".w.t mark set insert 0.0+%dchars",
				l1-fl.scope.first));
		if (l1 != l2)
			tk->cmd(fl.t, sprint(".w.t tag add sel 0.0+%dchars 0.0+%dchars",
				l1-fl.scope.first,
				l2-fl.scope.first));
	}
	tk->cmd(fl.t, "update");
}

panic(s: string)
{
	stderr := sys->fildes(2);
	sys->fprint(stderr, "Panic: %s\n", s);
	f := sys->sprint("#p/%d/ctl", ctxt.pgrp);
	if ((fd := sys->open(f, sys->OWRITE)) != nil)
		sys->write(fd, array of byte "killgrp\n", 8);
	exit;
}

whichmenu(tag: int): int
{
	for (i := 0; i < len ctxt.menus; i++)
		if (ctxt.menus[i].tag == tag)
			return i;
	return -1;
}

whichtext(tag: int): int
{
	for (i := 0; i < len ctxt.texts; i++)
		if (ctxt.texts[i].tag == tag)
			return i;
	return -1;
}

setscrollbar(t: ref Text, fl: ref Flayer)
{
	ll := real t.nrunes;
	f1 := 0.0; f2 := 1.0;
	if (ll != 0.0) {
		f1 = real fl.scope.first / ll;
		if (fl.scope.last > t.nrunes)
			f2 = 1.0;
		else
			f2 = real fl.scope.last / ll;
	}
	fl.scrollbar = fl.scope;
	tk->cmd(fl.t, sprint(".w.s set %f %f; update", f1, f2));
}

buttonselect(fl: ref Flayer, s: string): int
{
	tag := fl.tag;
	if ((i := whichtext(tag)) < 0) panic("buttonselect: whichtext");
	t := ctxt.texts[i];

	(n, l) := sys->tokenize(s, " ");
	if (n != 4) panic("buttonselect");

	# ignore mouse down -- wait for mouse up
	if (hd l == "1" || hd l == "3") return 0;

	if (ctxt.which != fl) {
		if (ctxt.menus[i].text != ctxt.cmd)
			ctxt.work = fl;
		newcur(t, fl);
#		setdot(fl, fl.dot.first, fl.dot.first);
		return 0;
	}

	if (hd l == "2") {
		# Double click
		l = tl tl l;
		s = tk->cmd(fl.t, ".w.t index @" + hd l + "," + hd tl l);
		fl.dot.first = fl.dot.last = coord2pos(t, fl, s);
		return 1;
	}

	rg := tk->cmd(fl.t, ".w.t tag ranges sel");
	if (rg == "") {
		# Nothing selected, find insertion point
		l = tl tl l;
		s = tk->cmd(fl.t, ".w.t index @" + hd l + "," + hd tl l);
		fl.dot.first = fl.dot.last = coord2pos(t, fl, s);
	} else {
		(n, l) = sys->tokenize(rg, " ");
		#if (n == 4 && hd tl l == hd tl tl l)
		#	lst := hd tl tl tl l;
		#else if (n != 2) panic("buttonselect: tag ranges");
		#else lst = hd tl l;
		# We only have one contiguous selection, so, take the
		# first as dot.first and the last as dot.last
		fst:=hd l;
		lst:=fst;
		while(l!=nil){
			lst=hd l;
			l = tl l;
		}
		fl.dot.first = coord2pos(t, fl, fst);
		fl.dot.last = coord2pos(t, fl, lst);
		tk->cmd(fl.t, ".w.t mark set insert " + fst);
		tk->cmd(fl.t, "update");
	}
	return 0;
}

coord2pos(t: ref Text, fl: ref Flayer, s: string): int
{
	x, y: int;

	(n, l) := sys->tokenize(s, ".");
	if (n != 2) panic("coord2pos");
	y = (int hd l) - 1;
	x = int hd tl l;
	if (x == 0 && y == 0) return fl.scope.first;
	first := fl.scope.first;
	for (scts := t.sects; scts != nil; scts = tl scts) {
		sct := hd scts;
		if (first >= sct.nrunes) {
			first -= sct.nrunes;
			continue;
		}
		if (first > 0) i := first; else i = 0;
		while (i < len sct.text) {
			if (y) {
				if (sct.text[i++] == '\n') y--;
			} else {
				if (x <= 1)
					return fl.scope.first - first + i + x;
				if (sct.text[i++] == '\n') panic("coord2pos");
				x--;
			}
		}
		if (len sct.text < sct.nrunes) panic("coord2pos: hole");
		first -= sct.nrunes;
	}
	if (x <= 0 && y == 0) return t.nrunes;
	panic("coord2pos: can't find");
	return(-1);
}

scrollpos, scrolllines: int;

scroll(fl: ref Flayer, s: string): (int, int)
{
	tag := fl.tag;
	if ((i := whichtext(tag)) < 0) panic("scroll: whichtext");
	t := ctxt.texts[i];
	(n, l) := sys->tokenize(s, " ");
	height := fl.scrollbar.last - fl.scrollbar.first;
	length := t.nrunes;
	case (hd l) {
	"0" =>
		if (n != 3) panic("scroll: format");
		return (scrollpos, scrolllines);
	"moveto" =>
		if (n != 2) panic("scroll: format");
		f := real hd tl l;
		if (f < 0.0) f = 0.0;
		if (f > 1.0) f = 1.0;
		scrollpos = int (f * real length) - height/2;
		scrolllines = 1;
	"scroll" =>
		if (n != 3) panic("scroll: format");
		l = tl l;
		n = int hd l;
		case(hd tl l) {
		"page" =>
			if (n < 0) {
				scrollpos = fl.scrollbar.first;
				scrolllines = fl.lines;
				break;
			}
			scrollpos = fl.scrollbar.last;
			scrolllines = 0;
		"unit" =>
			if (n < 0) {
				scrollpos = fl.scrollbar.first - 1;
				scrolllines = 1;
				break;
			}
			(p, q) := rasplines(t.sects, fl.scrollbar.first, 1);
			if (p > 0) {
				scrollpos = p;
				scrolllines = 0;
			} else {
				scrollpos = fl.scrollbar.first;
				scrolllines = 0;
			}
		}
	* =>
		panic("scroll: input");
	}
	if (scrollpos > length)
		scrollpos = length;
	if (scrollpos < 0) {
		scrollpos = 0;
		scrolllines = 0;
	}
	if (length != 0)
		tk->cmd(fl.t, sprint(".w.s set %f %f",
			real scrollpos / real length,
			real (scrollpos + height) / real length));
	else
		tk->cmd(fl.t, ".w.s set 0.0 1.0");
	tk->cmd(fl.t, "update");
	return (-1, -1);
}

flclear(fl: ref Flayer)
{
	tk->cmd(fl.t, ".w.t delete 0.0 end");
	tk->cmd(fl.t, "update");
}

flinsert(fl: ref Flayer, l: int, s: string)
{
	offset := l-fl.scope.first;
	tk->cmd(fl.t, ".w.t insert 0.0+" + string offset + "chars '" + s);
	setdot(fl, fl.dot.first, fl.dot.last);
}

fldelexcess(fl: ref Flayer)
{
	tk->cmd(fl.t, ".w.t delete " + string (fl.lines+1) + ".0 end");
}

fldelete(fl: ref Flayer, l1, l2: int)
{
	s: string;
	if (l1 <= fl.scope.first) {
		if (l2 >= fl.scope.last) {
			s = sprint(".w.t delete 0.0 end");
			fl.scope.first = fl.scope.last = l1;
		} else {
			s = sprint(".w.t delete 0.0 0.0+%dchars",
				l2 - fl.scope.first);
			fl.scope.last -= l2 - l1;
			fl.scope.first = l1;
		}
	} else {
		if (l2 >= fl.scope.last) {
			s = sprint(".w.t delete 0.0+%dchars end",
				l1 - fl.scope.first);
			fl.scope.last = l1;
		} else {
			s = sprint(".w.t delete 0.0+%dchars 0.0+%dchars",
				l1 - fl.scope.first, l2 - fl.scope.first);
			fl.scope.last -= l2 - l1;	
		}
	}
	if (fl.dot.first >= l2) fl.dot.first -= l2-l1;
	else if (fl.dot.first > l1) fl.dot.first = l1;
	if (fl.dot.last >= l2) fl.dot.last -= l2-l1;
	else if (fl.dot.last > l1) fl.dot.last = l1;
	tk->cmd(fl.t, s);
	setdot(fl, fl.dot.first, fl.dot.last);
	tk->cmd(fl.t, "update");
}

# Calculate position forward or backward nlines lines from pos.
# If lines > 0 count forward, if lines < 0 count backward.\
# Returns a pair, (position, nlines).  Nlines is the remaining
# number of lines to be found.  If non-zero, beginning or end of
# rasp was encountered while still counting, or a hole was
# encountered.  In the former case, position will be 0 or nrunes,
# in the latter case, position will be set to -1.
# To search to the beginning of the current line, set nlines to -1;

rasplines(scts: list of ref Section, pos, nlines: int): (int, int)
{
	p, i: int;
	if (nlines < 0) {
		if (scts != nil) {
			sct := hd scts; scts = tl scts;
			if (pos > sct.nrunes) {
				(p, nlines) =
				    rasplines(scts, pos - sct.nrunes, nlines);
				if (p < 0) return (p, nlines);
				pos = p + sct.nrunes;
				if (nlines == 0) return (pos, 0);
			}
			if (pos > len sct.text) return (-1, nlines);
			for (p = pos-1; p >= 0; p--) {
				if (sct.text[p] == '\n') nlines++;
				if (nlines == 0) return (p+1, 0);
			}
		}
		return (0, nlines);
	} else {
		p = 0;
		while (scts != nil) {
			sct := hd scts; scts = tl scts;
			if (pos < sct.nrunes) {
				for (i = pos; i < len sct.text; i++) {
					if (sct.text[i] == '\n') nlines--;
					if (nlines == 0) return (p+i+1, 0);
				}
				if (i < sct.nrunes) return (-1, nlines);
			}
			pos -= sct.nrunes;
			if (pos < 0) pos = 0;
			p += sct.nrunes;
		}
		return (p, nlines);
	}
}

chanadd(): int
{
	l := len ctxt.flayers;

	keysel := array [l+1] of chan of string;
	keysel[0:] = ctxt.keysel;
	keysel[l] = chan of string;
	ctxt.keysel = keysel;
	scrollsel := array [l+1] of chan of string;
	scrollsel[0:] = ctxt.scrollsel;
	scrollsel[l] = chan of string;
	ctxt.scrollsel = scrollsel;
	buttonsel := array [l+1] of chan of string;
	buttonsel[0:] = ctxt.buttonsel;
	buttonsel[l] = chan of string;
	ctxt.buttonsel = buttonsel;
	menu2sel := array [l+1] of chan of string;
	menu2sel[0:] = ctxt.menu2sel;
	menu2sel[l] = chan of string;
	ctxt.menu2sel = menu2sel;
	menu3sel := array [l+1] of chan of string;
	menu3sel[0:] = ctxt.menu3sel;
	menu3sel[l] = chan of string;
	ctxt.menu3sel = menu3sel;
	titlesel := array [l+1] of chan of string;
	titlesel[0:] = ctxt.titlesel;
	titlesel[l] = chan of string;
	ctxt.titlesel = titlesel;
	flayers := array [l+1] of ref Flayer;
	flayers[0:] = ctxt.flayers;
	flayers[l] = nil;
	ctxt.flayers = flayers;
	return l;
}

chandel(n: int)
{
	l := len ctxt.flayers;
	if (n >= l)
		panic("chandel");

	keysel := array [l-1] of chan of string;
	keysel[0:] = ctxt.keysel[0:n];
	keysel[n:] = ctxt.keysel[n+1:];
	ctxt.keysel = keysel;
	scrollsel := array [l-1] of chan of string;
	scrollsel[0:] = ctxt.scrollsel[0:n];
	scrollsel[n:] = ctxt.scrollsel[n+1:];
	ctxt.scrollsel = scrollsel;
	buttonsel := array [l-1] of chan of string;
	buttonsel[0:] = ctxt.buttonsel[0:n];
	buttonsel[n:] = ctxt.buttonsel[n+1:];
	ctxt.buttonsel = buttonsel;
	menu2sel := array [l-1] of chan of string;
	menu2sel[0:] = ctxt.menu2sel[0:n];
	menu2sel[n:] = ctxt.menu2sel[n+1:];
	ctxt.menu2sel = menu2sel;
	menu3sel := array [l-1] of chan of string;
	menu3sel[0:] = ctxt.menu3sel[0:n];
	menu3sel[n:] = ctxt.menu3sel[n+1:];
	ctxt.menu3sel = menu3sel;
	titlesel := array [l-1] of chan of string;
	titlesel[0:] = ctxt.titlesel[0:n];
	titlesel[n:] = ctxt.titlesel[n+1:];
	ctxt.titlesel = titlesel;
	flayers := array [l-1] of ref Flayer;
	flayers[0:] = ctxt.flayers[0:n];
	flayers[n:] = ctxt.flayers[n+1:];
	ctxt.flayers = flayers;
}
