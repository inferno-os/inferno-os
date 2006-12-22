implement WmMan;

include "sys.m";
	sys: Sys;
include "draw.m";
	draw: Draw;
include "tk.m";
	tk: Tk;
include "tkclient.m";
	tkclient: Tkclient;
include "plumbmsg.m";
include "man.m";
	man: Man;

WmMan: module {
	init: fn (ctxt: ref Draw->Context, argv: list of string);
};

window: ref Tk->Toplevel;

W: adt {
	textwidth: fn(nil: self ref W, text: Parseman->Text): int;
};

ROMAN: con "/fonts/lucidasans/unicode.7.font";
BOLD: con "/fonts/lucidasans/typelatin1.7.font";
ITALIC: con "/fonts/lucidasans/italiclatin1.7.font";
HEADING1: con "/fonts/lucidasans/boldlatin1.7.font";
HEADING2: con "/fonts/lucidasans/italiclatin1.7.font";
rfont, bfont, ifont, h1font, h2font: ref Draw->Font;

GOATTR: con Parseman->ATTR_LAST << iota;
MANPATH: con "/man/1/man";
INDENT: con 40;

metrics: Parseman->Metrics;
parser: Parseman;


tkconfig := array [] of {
	"frame .input",
	"frame .view",
	"text .view.t -state disabled -width 0 -height 0 -bg white -yscrollcommand {.view.yscroll set} -xscrollcommand {.view.xscroll set}",
	"scrollbar .view.yscroll -orient vertical -command {.view.t yview}",
	"scrollbar .view.xscroll -orient horizontal -command {.view.t xview}",
	"entry .input.e -bg white",
	"button .input.back -state disabled -bitmap small_color_left.bit -command {send nav b}",
	"button .input.forward -state disabled -bitmap small_color_right.bit -command {send nav f}",

	"pack .input.back .input.forward -side left -anchor w",
	"pack .input.e -expand 1 -fill x",

 	"pack .view.yscroll -fill y -side left",
 	"pack .view.t -expand 1 -fill both",
	
	"bind .input.e <Key-\n> {send nav e}",
	"bind .input.e <Button-1> +{grab set .input.e}",
	"bind .input.e <ButtonRelease-1> +{grab release .input.e}",
	"bind .view.t <Button-1> +{grab set .view.t}",
	"bind .view.t <ButtonRelease-1> +{grab release .view.t}",
	"bind .view.t <ButtonRelease-3> {send plumb %x %y}",

	"pack .input -fill x",
	"pack .view -expand 1 -fill both",
	"pack propagate . 0",
	". configure -width 500 -height 500",
	"focus .input.e",
};

History: adt {
	prev: cyclic ref History;
	next: cyclic ref History;
	topline: string;
	searchstart: string;
	searchend: string;
	pick {
	Search =>
		search: list of string;
	Go =>
		path: string;
	}
};

history: ref History;


init(ctxt: ref Draw->Context, argv: list of string)
{
	doplumb := 0;

	sys = load Sys Sys->PATH;
	if (ctxt == nil) {
		sys->fprint(sys->fildes(2), "man: no window context\n");
		raise "fail:bad context";
	}
	sys->pctl(Sys->NEWPGRP, nil);

	draw = load Draw Draw->PATH;
	if (draw == nil)
		loaderr("Draw");

	tk = load Tk Tk->PATH;
	if (tk == nil)
		loaderr(Tk->PATH);

	man = load Man Man->PATH;
	if (man == nil)
		loaderr(Man->PATH);

	tkclient = load Tkclient Tkclient->PATH;
	if (tkclient == nil)
		loaderr(Tkclient->PATH);

	parser = load Parseman Parseman->PATH;
	if (parser == nil)
		loaderr(Parseman->PATH);
	parser->init();

	plumber := load Plumbmsg Plumbmsg->PATH;
	if (plumber != nil) {
		if (plumber->init(1, nil, 0) >= 0)
			doplumb = 1;
	}

	argv = tl argv;

	rfont = draw->(Draw->Font).open(ctxt.display, ROMAN);
	bfont = draw->(Draw->Font).open(ctxt.display, BOLD);
	ifont = draw->(Draw->Font).open(ctxt.display, ITALIC);
	h1font = draw->(Draw->Font).open(ctxt.display, HEADING1);
	h2font = draw->(Draw->Font).open(ctxt.display, HEADING2);

	em := draw->rfont.width("m");
	en := draw->rfont.width("n");
	metrics = Parseman->Metrics(490, 80, em, en, 14, 40, 20);

	tkclient->init();
	buts := Tkclient->Resize | Tkclient->Hide;
	winctl: chan of string;
	(window, winctl) = tkclient->toplevel(ctxt, nil, "Man", buts);
	nav := chan of string;
	plumb := chan of string;
	tk->namechan(window, nav, "nav");
	tk->namechan(window, plumb, "plumb");
	for(tc:=0; tc<len tkconfig; tc++)
		tkcmd(window, tkconfig[tc]);
	if ((err := tkcmd(window, "variable lasterror")) != nil) {
		sys->fprint(sys->fildes(2), "man: tk initialization failed: %s\n", err);
		raise "fail:tk";
	}
	fittoscreen(window);
	tkcmd(window, "update");
	mktags();

	vw := int tkcmd(window, ".view.t cget -actwidth") - 10;
	if (vw <= 0)
		vw = 1;
	metrics.pagew = vw;

	linechan := chan of list of (int, Parseman->Text);
	man->loadsections(nil);

	pidc := chan of int;

	if (argv != nil) {
		if (hd argv == "-f") {
			first: ref History;
			for (argv = tl argv; argv != nil; argv = tl argv) {
				hnode := ref History.Go(history, nil, "", "", "", hd argv);
				if (history != nil)
					history.next = hnode;
				history = hnode;
				if (first == nil)
					first = history;
			}
			history = first;
		} else
			history = ref History.Search(nil, nil, "", "", "", argv);
	}

	if (history == nil)
		history = ref History.Go(nil, nil, "", "", "", MANPATH);

	setbuttons();
	spawn printman(pidc, linechan, history);
	layoutpid := <- pidc;
	tkclient->onscreen(window, nil);
	tkclient->startinput(window, "kbd"::"ptr"::nil);
	for (;;) alt {
	s := <-window.ctxt.kbd =>
		tk->keyboard(window, s);
	s := <-window.ctxt.ptr =>
		tk->pointer(window, *s);
	s := <-window.ctxt.ctl or
	s = <-window.wreq or
	s = <-winctl =>
		e := tkclient->wmctl(window, s);
		if (e == nil && s[0] == '!') {
			topline := tkcmd(window, ".view.t yview");
			(nil, toptoks) := sys->tokenize(topline, " ");
			if (toptoks != nil)
				history.topline = hd toptoks;
			vw = int tkcmd(window, ".view.t cget -actwidth") - 10;
			if (vw <= 0)
				vw = 1;
			if (vw != metrics.pagew) {
				if (layoutpid != -1)
					kill(layoutpid);
				metrics.pagew = vw;
				tkcmd(window, ".view.t delete 1.0 end");
				tkcmd(window, "update");
				spawn printman(pidc, linechan, history);
				layoutpid = <- pidc;
			}
		}
	line := <- linechan =>
		if (line == nil) {
			# layout done
			if (history.topline != "") {
				topline := tkcmd(window, ".view.t yview");
				(nil, toptoks) := sys->tokenize(topline, " ");
				if (toptoks != nil)
					if (hd toptoks == "0")
						tkcmd(window, ".view.t yview moveto " + history.topline);
			}
			tkcmd(window, "update");
		} else
			setline(line);
	go := <- nav =>
		topline := tkcmd(window, ".view.t yview");
		(nil, toptoks) := sys->tokenize(topline, " ");
		if (toptoks != nil)
			history.topline = hd toptoks;
		case go[0] {
		'f' =>
			# forward
			history = history.next;
			setbuttons();
			if (layoutpid != -1)
				kill(layoutpid);
			tkcmd(window, ".view.t delete 1.0 end");
			tkcmd(window, "update");
			spawn printman(pidc, linechan, history);
			layoutpid = <- pidc;
		'b' =>
			# back
			history = history.prev;
			setbuttons();
			if (layoutpid != -1)
				kill(layoutpid);
			tkcmd(window, ".view.t delete 1.0 end");
			tkcmd(window, "update");
			spawn printman(pidc, linechan, history);
			layoutpid = <- pidc;
		'e' or 'l' =>
			t := "";
			if (go[0] == 'l') {
				# link
				t = go[1:];
			} else {
				# entry
				t = tkcmd(window, ".input.e get");
				for (i := 0; i < len t; i++)
					if (!(t[i] == ' ' || t[i] == '\t'))
						break;
				if (i == len t)
					break;
				t = t[i:];
				if (t[0] == '/' || t[0] == '?') {
					search(t);
					break;
				}
			}
			(n, toks) := sys->tokenize(t, " \t");
			if (n == 0)
				continue;
			h := ref History.Search(history, nil, "", "", "", toks);
			history.next = h;
			history = h;
			setbuttons();
			if (layoutpid != -1)
				kill(layoutpid);
			tkcmd(window, ".view.t delete 1.0 end");
			tkcmd(window, "update");
			spawn printman(pidc, linechan, history);
			layoutpid = <- pidc;
		'g' =>
			# goto file
			h := ref History.Go(history, nil, "", "", "", go[1:]);
			history.next = h;
			history = h;
			setbuttons();
			if (layoutpid != 0)
				kill(layoutpid);
			tkcmd(window, ".view.t delete 1.0 end");
			tkcmd(window, "update");
			spawn printman(pidc, linechan, history);
			layoutpid = <- pidc;
		}
	p := <- plumb =>
		if (!doplumb)
			break;
		(nil, l) := sys->tokenize(p, " ");
		x := int hd l;
		y := int hd tl l;
		index := tkcmd(window, ".view.t index @"+string x+","+string y);		
		selindex := tkcmd(window, ".view.t tag ranges sel");
		insel := 0;
		if(selindex != "")
			insel = tkcmd(window, ".view.t compare sel.first <= "+index)=="1" &&
				tkcmd(window, ".view.t compare sel.last >= "+index)=="1";
		text := "";
		attr := "";
		if (insel)
			text = tkcmd(window, ".view.t get sel.first sel.last");
		else{
			# have line with text in it
			# now extract whitespace-bounded string around click
			(nil, w) := sys->tokenize(index, ".");
			charno := int hd tl w;
			left := tkcmd(window, ".view.t index {"+index+" linestart}");
			right := tkcmd(window, ".view.t index {"+index+" lineend}");
			line := tkcmd(window, ".view.t get "+left+" "+right);
			for(i:=charno; i>0; --i)
				if(line[i-1]==' ' || line[i-1]=='\t')
					break;
			for(j:=charno; j<len line; j++)
				if(line[j]==' ' || line[j]=='\t')
					break;
			text = line[i:j];
			attr = "click="+string (charno-i);
		}
		msg := ref Plumbmsg->Msg(
			"WmMan",
			"",
			"",
			"text",
			attr,
			array of byte text);
		plumber->msg.send();

	layoutpid = <- pidc =>
		;
	}
}

search(pat: string)
{
	dir: string;
	start: string;
	if (pat[0] == '/') {
		dir = "-forwards";
		start = history.searchend;
	} else {
		dir = "-backwards";
		start = history.searchstart;
	}
	pat = pat[1:];
	if (start == "")
		start = "1.0";
	r := tkcmd(window, ".view.t search " + dir + " -- " + tk->quote(pat) + " " + start);
	if (r != nil) {
		history.searchstart = r;
		history.searchend = r + "+" + string len pat + "c";
		tkcmd(window, ".view.t tag remove sel 1.0 end");
		tkcmd(window, ".view.t tag add sel " + history.searchstart + " " + history.searchend);
		tkcmd(window, ".view.t see " + r);
		tkcmd(window, "update");
	}
}

setbuttons()
{
	if (history.prev == nil)
		tkcmd(window, ".input.back configure -state disabled");
	else
		tkcmd(window, ".input.back configure -state normal");
	if (history.next == nil)
		tkcmd(window, ".input.forward configure -state disabled");
	else
		tkcmd(window, ".input.forward configure -state normal");
}

dolayout(linechan: chan of list of (int, Parseman->Text), path: string)
{
	fd := sys->open(path, Sys->OREAD);
	if (fd == nil) {
		layouterror(linechan, sys->sprint("cannot open file %s: %r", path));
		return;
	}
	w: ref W;
	parser->parseman(fd, metrics, 0, w, linechan);
}

printman(pidc: chan of int, linechan: chan of list of (int, Parseman->Text), h: ref History)
{
	pidc <-= sys->pctl(0, nil);
	args: list of string;
	pick hp := h {
		Search =>
			args = hp.search;
		Go =>
			dolayout(linechan, hp.path);
			pidc <-= -1;
			return;
	}
	sections: list of string;
	argstext := "";
	addsections := 1;
	keywords: list of string;
	for (; args != nil; args = tl args) {
		arg := hd args;
		if (arg == nil)
			continue;
		if (addsections && !isint(arg)) {
			addsections = 0;
			keywords = args;
		}
		if (addsections)
			sections = arg :: sections;
		argstext = argstext + " " + arg;
	}
	manpages := man->getfiles(sections, keywords);
	pagelist := sortpages(manpages);
	if (len pagelist == 1) {
		(nil, path, nil) := hd pagelist;
		dolayout(linechan, path);
		pidc <-= -1;
		return;
	}

	tt := Parseman->Text(Parseman->FONT_ROMAN, 0, "Search:", 1, nil);
	at := Parseman->Text(Parseman->FONT_BOLD, 0, argstext, 0, nil);
	linechan <-= (0, tt)::(0, at)::nil;
	tt.text = "";
	linechan <-= (0, tt)::nil;

	if (pagelist == nil) {
		donet := Parseman->Text(Parseman->FONT_ROMAN, 0, "No matches", 0, nil);
		linechan <-= (INDENT, donet) :: nil;
		linechan <-= nil;
		pidc <-= -1;
		return;
	}

	linelist: list of list of Parseman->Text;
	pathlist: list of Parseman->Text;
	
	maxkwlen := 0;
	comma := Parseman->Text(Parseman->FONT_ROMAN, 0, ", ", 0, "");
	for (; pagelist != nil; pagelist = tl pagelist) {
		(n, p, kwl) := hd pagelist;
		l := 0;
		keywords: list of Parseman->Text = nil;
		for (; kwl != nil; kwl = tl kwl) {
			kw := hd kwl;
			kwt := Parseman->Text(Parseman->FONT_ITALIC, GOATTR, kw, 0, p);
			nt := Parseman->Text(Parseman->FONT_ROMAN, GOATTR, "(" + string n + ")", 0, p);
			l += textwidth(kwt) + textwidth(nt);
			if (keywords != nil) {
				l += textwidth(comma);
				keywords = nt :: kwt :: comma :: keywords;
			} else
				keywords = nt :: kwt :: nil;
		}
		if (l > maxkwlen)
			maxkwlen = l;
		linelist = keywords :: linelist;
		ptext := Parseman->Text(Parseman->FONT_ROMAN, GOATTR, p, 0, "");
		pathlist = ptext :: pathlist;
	}

	for (; pathlist != nil; (pathlist, linelist) = (tl pathlist, tl linelist)) {
		line := (10 + INDENT + maxkwlen, hd pathlist) :: nil;
		for (ll := hd linelist; ll != nil; ll = tl ll) {
			litem := hd ll;
			if (tl ll == nil)
				line = (INDENT, litem) :: line;
			else
				line = (0, litem) :: line;
		}
		linechan <-= line;
	}
	linechan <-= nil;
	pidc <-= -1;
}

layouterror(linechan: chan of list of (int, Parseman->Text), msg: string)
{
	text := "ERROR: " + msg;
	t := Parseman->Text(Parseman->FONT_ROMAN, 0, text, 0, nil);
	linechan <-= (0, t)::nil;
	linechan <-= nil;
}

loaderr(modname: string)
{
	sys->print("cannot load %s module: %r\n", modname);
	raise "fail:init";
}

W.textwidth(nil: self ref W, text: Parseman->Text): int
{
	return textwidth(text);
}

textwidth(text: Parseman->Text): int
{
	f: ref Draw->Font;
	if (text.heading == 1)
		f = h1font;
	else if (text.heading == 2)
		f = h2font;
	else {
		case text.font {
		Parseman->FONT_ROMAN =>
			f = rfont;
		Parseman->FONT_BOLD =>
			f = bfont;
		Parseman->FONT_ITALIC =>
			f = ifont;
		* =>
			return 8 * len text.text;
		}
	}
	return draw->f.width(text.text);
}

lnum := 0;

setline(line: list of (int, Parseman->Text))
{
	tabstr := "";
	linestr := "";
	lastoff := 0;
	curfont := Parseman->FONT_ROMAN;
	curlink := "";
	curgtag := "";
	curheading := 0;
	fonttext := "";

	for (l := line; l != nil; l = tl l) {
		(offset, nil) := hd l;
		if (offset != 0) {
			lastoff = offset;
			if (tabstr != "")
				tabstr[len tabstr] = ' ';
			tabstr = tabstr + string offset;
		}
	}
	# fudge up tabs for rest of line
	if (lastoff != 0)
		tabstr = tabstr + " " + string lastoff + " " + string (lastoff + INDENT);
	ttag := "";
	gtag := "";
	if (tabstr != nil)
		ttag = tabtag(tabstr) + " ";

	for (l = line; l != nil; l = tl l) {
		(offset, text) := hd l;
		gtag = "";
		if (text.link != nil) {
			if (text.attr & GOATTR)
				gtag = gotag(text.link) + " ";
			else {
				gtag = linktag(text.link) + " ";
			}
		}
		if (offset != 0)
			fonttext[len fonttext] = '\t';
		if (text.font != curfont || text.link != curlink || text.heading != curheading || gtag != curgtag) {
			# need to change tags
			linestr = linestr + " " + tk->quote(fonttext) + " {" + ttag + curgtag + fonttag(curfont, curheading) + "}";
			ttag = "";
			curgtag = gtag;
			fonttext = "";
			curfont = text.font;
			curlink = text.link;
			curheading = text.heading;
		}
		fonttext = fonttext + text.text;
	}
	if (fonttext != nil)
		linestr = linestr + " " + tk->quote(fonttext) + " {" + ttag + curgtag + fonttag(curfont, curheading) + "}";
	tkcmd(window, ".view.t insert end " + linestr);
	tkcmd(window, ".view.t insert end {\n}");
	# only update on every other line
	if (lnum++ & 1)
		tkcmd(window, "update");
}

mktags()
{
	tkcmd(window, ".view.t tag configure ROMAN -font " + ROMAN);
	tkcmd(window, ".view.t tag configure BOLD -font " + BOLD);
	tkcmd(window, ".view.t tag configure ITALIC -font " + ITALIC);
	tkcmd(window, ".view.t tag configure H1 -font " + HEADING1);
	tkcmd(window, ".view.t tag configure H2 -font " + HEADING2);
}

fonttag(font, heading: int): string
{
	if (heading == 1)
		return "H1";
	if (heading == 2)
		return "H2";
	case font {
	Parseman->FONT_ROMAN =>
		return "ROMAN";
	Parseman->FONT_BOLD =>
		return "BOLD";
	Parseman->FONT_ITALIC =>
		return "ITALIC";
	}
	return nil;
}

nexttag := 0;
lasttabstr := "";
lasttagname := "";

tabtag(tabstr: string): string
{
	if (tabstr == lasttabstr)
		return lasttagname;
	lasttagname = "TAB" + string nexttag++;
	lasttabstr = tabstr;
	tkcmd(window, ".view.t tag configure " + lasttagname + " -tabs " + tk->quote(tabstr));
	return lasttagname;
}

# optimise this!
gotag(path: string): string
{
	cmd := "{send nav g" + path + "}";
	name := "GO" + string nexttag++;
	tkcmd(window, ".view.t tag bind " + name + " <ButtonRelease-1> +" + cmd);
	tkcmd(window, ".view.t tag configure " + name + " -fg green");
	return name;
}

# and this!
linktag(search: string): string
{
	cmd := tk->quote("send nav l" + search);
	name := "LN" + string nexttag++;
	tkcmd(window, ".view.t tag bind " + name + " <ButtonRelease-1> +" + cmd);
	tkcmd(window, ".view.t tag configure " + name + " -fg green");
	return name;
}

isint(s: string): int
{
	for (i := 0; i < len s; i++)
		if (s[i] < '0' || s[i] > '9')
			return 0;
	return 1;
}

kill(pid: int)
{
	pctl := sys->open("/prog/" + string pid + "/ctl", Sys->OWRITE);
	if (pctl != nil) {
		poison := array of byte "kill";
		sys->write(pctl, poison, len poison);
	}
}

revsortuniq(strlist: list of string): list of string
{
	strs := array [len strlist] of string;
	for (i := 0; strlist != nil; (i, strlist) = (i+1, tl strlist))
		strs[i] = hd strlist;

	# simple sort (ascending)
	for (i = 0; i < len strs - 1; i++) {
		for (j := i+1; j < len strs; j++)
			if (strs[i] < strs[j])
				(strs[i], strs[j]) = (strs[j], strs[i]);
	}

	# construct list (result is descending)
	r: list of string;
	prev := "";
	for (i = 0; i < len strs; i++) {
		if (strs[i] != prev) {
			r = strs[i] :: r;
			prev = strs[i];
		}
	}
	return r;
}

sortpages(pagelist: list of (int, string, string)): list of (int, string, list of string)
{
	pages := array [len pagelist] of (int, string, string);
	for (i := 0; pagelist != nil; (i, pagelist) = (i+1, tl pagelist))
		pages[i] = hd pagelist;

	for (i = 0; i < len pages - 1; i++) {
		for (j := i+1; j < len pages; j++) {
			(nil, nil, ipath) := pages[i];
			(nil, nil, jpath) := pages[j];
			if (ipath > jpath)
				(pages[i], pages[j]) = (pages[j], pages[i]);
		}
	}

	r: list of (int, string, list of string);
	filecmds: list of string;
	lastfile := "";
	lastsect := 0;
	for (i = 0; i < len pages; i++) {
		(section, cmd, file) := pages[i];
		if (lastfile == "") {
			lastfile = file;
			lastsect = section;
		}

		if (file != lastfile) {
			r = (lastsect, lastfile, filecmds) :: r;
			lastfile = file;
			lastsect = section;
			filecmds = nil;
		}
		filecmds = cmd :: filecmds;
	}
	if (filecmds != nil)
		r = (lastsect, lastfile, revsortuniq(filecmds)) :: r;
	return r;
}

fittoscreen(win: ref Tk->Toplevel)
{
	Point, Rect: import draw;
	if (win.image == nil || win.image.screen == nil)
		return;
	r := win.image.screen.image.r;
	scrsize := Point((r.max.x - r.min.x), (r.max.y - r.min.y));
	bd := int tkcmd(win, ". cget -bd");
	winsize := Point(int tkcmd(win, ". cget -actwidth") + bd * 2, int tkcmd(win, ". cget -actheight") + bd * 2);
	if (winsize.x > scrsize.x)
		tkcmd(win, ". configure -width " + string (scrsize.x - bd * 2));
	if (winsize.y > scrsize.y)
		tkcmd(win, ". configure -height " + string (scrsize.y - bd * 2));
	actr: Rect;
	actr.min = Point(int tkcmd(win, ". cget -actx"), int tkcmd(win, ". cget -acty"));
	actr.max = actr.min.add((int tkcmd(win, ". cget -actwidth") + bd*2,
				int tkcmd(win, ". cget -actheight") + bd*2));
	(dx, dy) := (actr.dx(), actr.dy());
	if (actr.max.x > r.max.x)
		(actr.min.x, actr.max.x) = (r.max.x - dx, r.max.x);
	if (actr.max.y > r.max.y)
		(actr.min.y, actr.max.y) = (r.max.y - dy, r.max.y);
	if (actr.min.x < r.min.x)
		(actr.min.x, actr.max.x) = (r.min.x, r.min.x + dx);
	if (actr.min.y < r.min.y)
		(actr.min.y, actr.max.y) = (r.min.y, r.min.y + dy);
	tkcmd(win, ". configure -x " + string actr.min.x + " -y " + string actr.min.y);
}

tkcmd(top: ref Tk->Toplevel, s: string): string
{
	e := tk->cmd(top, s);
	if (e != nil && e[0] == '!') {
		sys->print("tk error %s on '%s'\n", e, s);
	}
	return e;
}
