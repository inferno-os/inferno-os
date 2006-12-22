implement Selectfile;

include "sys.m";
	sys: Sys;
	Dir: import sys;

include "draw.m";
	draw: Draw;
	Screen, Rect, Point: import draw;

include "tk.m";
	tk: Tk;

include "string.m";
	str: String;

include "tkclient.m";
	tkclient: Tkclient;

include "workdir.m";

include "readdir.m";
	readdir: Readdir;

include "filepat.m";
	filepat: Filepat;

include "selectfile.m";

Browser: adt {
	top:		ref Tk->Toplevel;
	ncols:	int;
	colwidth:	int;
	w:		string;
	init:		fn(top: ref Tk->Toplevel, w: string, colwidth: string): (ref Browser, chan of string);

	addcol:	fn(c: self ref Browser, t: string, d: array of string);
	delete:	fn(c: self ref Browser, colno: int);
	selection:	fn(c: self ref Browser, cno: int): string;
	select:	fn(b: self ref Browser, cno: int, e: string);
	entries:	fn(b: self ref Browser, cno: int): array of string;
	resize:	fn(c: self ref Browser);
};

BState: adt {
	b:			ref Browser;
	bpath:		string;		# path currently displayed in browser
	epath:		string;		# path entered by user
	dirfetchpid:	int;
	dirfetchpath:	string;
};

filename_config := array[] of {
	"entry .e -bg white",
	"frame .pf",
	"entry .pf.e",
	"label .pf.t -text {Filter:}",
	"entry .pats",
	"bind .e <Key> +{send ech key}",
	"bind .e <Key-\n> {send ech enter}",
	"bind .e {<Key-\t>} {send ech expand}",
	"bind .pf.e <Key-\n> {send ech setpat}",
	"bind . <Configure> {send ech config}",
	"pack .b -side top -fill both -expand 1",
	"pack .pf.t -side left",
	"pack .pf.e -side top -fill x",
	"pack .pf -side top -fill x",
	"pack .e -side top -fill x",
	"pack propagate . 0",
};

debugging := 0;
STEP: con 20;

init(): string
{
	sys = load Sys Sys->PATH;
	draw = load Draw Draw->PATH;
	tk = load Tk Tk->PATH;
	tkclient = load Tkclient Tkclient->PATH;
	tkclient->init();
	str = load String String->PATH;
	readdir = load Readdir Readdir->PATH;
	filepat = load Filepat Filepat->PATH;
	return nil;
}

filename(ctxt: ref Draw->Context, parent: ref Draw->Image,
		title: string,
		pats: list of string,
		dir: string): string
{
	patstr: string;

	if (dir == nil || dir == ".") {
		wd := load Workdir Workdir->PATH;
		if ((dir = wd->init()) != nil) {
			(ok, nil) := sys->stat(dir);
			if (ok == -1)
				dir = nil;
		}
		wd = nil;
	}
	if (dir == nil)
		dir = "/";
	(pats, patstr) = makepats(pats);
	where := localgeom(parent);
	if (title == nil)
		title = "Open";
	(top, wch) := tkclient->toplevel(ctxt, where+" -bd 1", # -font /fonts/misc/latin1.6x13.font", 
			title, Tkclient->Popup|Tkclient->Resize|Tkclient->OK);
	(b, colch) := Browser.init(top, ".b", "16w");
	entrych := chan of string;
	tk->namechan(top, entrych, "ech");
	tkcmds(top, filename_config);
	cmd(top, ". configure -width " + string (b.colwidth * 3) + " -height 20h");
	cmd(top, ".e insert 0 '" + dir);
	cmd(top, ".pf.e insert 0 '" + patstr);
	s := ref BState(b, nil, dir, -1, nil);
	s.b.resize();
	dfch := chan of (string, array of ref Sys->Dir);
	if (parent == nil)
		centre(top);
	tkclient->onscreen(top, nil);
	tkclient->startinput(top, "kbd" :: "ptr" :: nil);
loop: for (;;) {
		if (debugging) {
			sys->print("filename: before sync, bpath: '%s'; epath: '%s'\n",
				s.bpath, s.epath);
		}
		bsync(s, dfch, pats);
		if (debugging) {
			sys->print("filename: after sync, bpath: '%s'; epath: '%s'", s.bpath, s.epath);
			if (s.dirfetchpid == -1)
				sys->print("\n");
			else
				sys->print("; fetching '%s' (pid %d)\n", s.dirfetchpath, s.dirfetchpid);
		}
		cmd(top, "focus .e");
		cmd(top, "update");
		alt {
		c := <-top.ctxt.kbd =>
			tk->keyboard(top, c);
		p := <-top.ctxt.ptr =>
			tk->pointer(top, *p);
		c := <-top.ctxt.ctl or
		c = <-top.wreq =>
			tkclient->wmctl(top, c);
		c := <-colch =>
			double := c[0] == 'd';
			c = c[1:];
			(bpath, nbpath, elem) := (s.bpath, "", "");
			for (cno := 0; cno <= int c; cno++) {
				(elem, bpath) = nextelem(bpath);
				nbpath = pathcat(nbpath, elem);
			}
			nsel := s.b.selection(int c);
			if (nsel != nil)
				nbpath = pathcat(nbpath, nsel);
			s.epath = nbpath;
			cmd(top, ".e delete 0 end");
			cmd(top, ".e insert 0 '" + s.epath);
			if (double)
				break loop;
		c := <-entrych =>
			case c {
			"enter" =>
				break loop;
			"config" =>
				s.b.resize();
			"key" =>
				s.epath = cmdget(top, ".e get");
			"expand" =>
				cmd(top, ".e delete 0 end");
				cmd(top, ".e insert 0 '" + s.bpath);
				s.epath = s.bpath;
			"setpat" =>
				patstr = cmdget(top, ".pf.e get");
				if (patstr == "  debug  ")
					debugging = !debugging;
				else {
					(nil, pats) = sys->tokenize(patstr, " ");
					s.b.delete(0);
					s.bpath = nil;
				}
			}
		c := <-wch =>
			if (c == "ok")
				break loop;
			if (c == "exit") {
				s.epath = nil;
				break loop;
			}
			tkclient->wmctl(top, c);
		(t, d) := <-dfch =>
			ds := array[len d] of string;
			for (i := 0; i < len d; i++) {
				n := d[i].name;
				if ((d[i].mode & Sys->DMDIR) != 0)
					n[len n] = '/';
				ds[i] = n;
			}
			s.b.addcol(t, ds);
			ds = nil;
			d = nil;
			s.bpath = s.dirfetchpath;
			s.dirfetchpid = -1;
		}
	}
	if (s.dirfetchpid != -1)
		kill(s.dirfetchpid);
	return s.epath;
}

bsync(s: ref BState, dfch: chan of (string, array of ref Sys->Dir), pats: list of string)
{
	(epath, bpath) := (s.epath, s.bpath);
	cno := 0;
	prefix, e1, e2: string = "";

	# find maximal prefix of epath and bpath.
	for (;;) {
		p1, p2: string;
		(e1, p1) = nextelem(epath);
		(e2, p2) = nextelem(bpath);
		if (e1 == nil || e1 != e2)
			break;
		prefix = pathcat(prefix, e1);
		(epath, bpath) = (p1, p2);
		cno++;
	}

	if (epath == nil) {
		if (bpath != nil) {
			s.b.delete(cno);
			s.b.select(cno - 1, nil);
			s.bpath = prefix;
		}
		return;
	}

	# if the paths have no prefix in common then we're starting
	# at a different root - don't do anything until
	# we know we have at least one full element.
	# even then, if it's not a directory, we have to ignore it.
	if (cno == 0 && islastelem(epath))
		return;

	if (e1 != nil && islastelem(epath)) {
		# find first prefix-matching entry.
		match := "";
		for ((i, ents) := (0, s.b.entries(cno - 1)); i < len ents; i++) {
			m := ents[i];
			if (len m >= len e1 && m[0:len e1] == e1) {
				match = deslash(m);
				break;
			}
		}
		if (match != nil) {
			if (match == e2 && islastelem(bpath))
				return;

			epath = pathcat(match,  epath[len e1:]);
			e1 = match;
			if (e1 == e2)
				cno++;
		} else {
			s.b.delete(cno);
			s.bpath = prefix;
			return;
		}
	}

	s.b.delete(cno);
	s.b.select(cno - 1, e1);
	np := pathcat(prefix, e1);
	if (s.dirfetchpid != -1) {
		if (np == s.dirfetchpath)
			return;
		kill(s.dirfetchpid);
		s.dirfetchpid = -1;
	}
	(ok, dir) := sys->stat(np);
	if (ok != -1 && (dir.mode & Sys->DMDIR) != 0) {
		sync := chan of int;
		spawn dirfetch(np, e1, sync, dfch, pats);
		s.dirfetchpid = <-sync;
		s.dirfetchpath = np;
	} else if (ok != -1)
		s.bpath = np;
	else
		s.bpath = prefix;
}

dirfetch(p: string, t: string, sync: chan of int,
		dfch: chan of (string, array of ref Sys->Dir),
		pats: list of string)
{
	sync <-= sys->pctl(0, nil);
	(a, e) := readdir->init(p, Readdir->NAME|Readdir->COMPACT);
	if (e != -1) {
		j := 0;
		for (i := 0; i < len a; i++) {
			pl := pats;
			if ((a[i].mode & Sys->DMDIR) == 0) {
				for (; pl != nil; pl = tl pl)
					if (filepat->match(hd pl, a[i].name))
						break;
			}
			if (pl != nil || pats == nil)
				a[j++] = a[i];
		}
		a = a[0:j];
	}
	dfch <-= (t, a);
}

dist(top: ref Tk->Toplevel, s: string): int
{
	cmd(top, "frame .xxxx -width " + s);
	d := int cmd(top, ".xxxx cget -width");
	cmd(top, "destroy .xxxx");
	return d;
}
	
Browser.init(top: ref Tk->Toplevel, w: string, colwidth: string): (ref Browser, chan of string)
{
	b := ref Browser;
	b.top = top;
	b.ncols = 0;
	b.colwidth = dist(top, colwidth);
	b.w = w;
	cmd(b.top, "frame " + b.w);
	cmd(b.top, "canvas " + b.w + ".c -width 0 -height 0 -xscrollcommand {" + b.w + ".s set}");
	cmd(b.top, "frame " + b.w + ".c.f -bd 0");
	cmd(b.top, "pack propagate " + b.w + ".c.f 0");
	cmd(b.top, b.w + ".c create window 0 0 -tags win -window " + b.w + ".c.f -anchor nw");
	cmd(b.top, "scrollbar "+b.w+".s -command {"+b.w+".c xview} -orient horizontal");
	cmd(b.top, "bind "+b.w+".c <Configure> {"+b.w+".c itemconfigure win -height ["+b.w+".c cget -actheight]}");
	cmd(b.top, "pack "+b.w+".c -side top -fill both -expand 1");
	cmd(b.top, "pack "+b.w+".s -side top -fill x");
	ch := chan of string;
	tk->namechan(b.top, ch, "colch");
	return (b, ch);
}

xview(top: ref Tk->Toplevel, w: string): (real, real)
{
	s := tk->cmd(top, w + " xview");
	if (s != nil && s[0] != '!') {
		(n, v) := sys->tokenize(s, " ");
		if (n == 2)
			return (real hd v, real hd tl v);
	}
	return (0.0, 0.0);
}

setscrollregion(b: ref Browser)
{
	(w, h) := (b.colwidth * (b.ncols + 1), int cmd(b.top, b.w + ".c cget -actheight"));
	cmd(b.top, b.w+".c.f configure -width " + string w + " -height " + string h);
#	w := int cmd(b.top, b.w+".c.f cget -actwidth");
#	w += int cmd(b.top, b.w+".c cget -actwidth") - b.colwidth;
#	h := int cmd(b.top, b.w+".c.f cget -actheight");
	if (w > 0 && h > 0)
		cmd(b.top, b.w + ".c configure -scrollregion {0 0 " + string w + " " + string h + "}");
	(start, end) := xview(b.top, b.w+".c");
	if (end > 1.0)
		cmd(b.top, b.w+".c xview scroll left 0 units");
}

Browser.addcol(b: self ref Browser, title: string, d: array of string)
{
	ncol := string b.ncols++;

	f := b.w + ".c.f.d" + ncol;
	cmd(b.top, "frame " + f + " -bg green -width " + string b.colwidth);

	t := f + ".t";
	cmd(b.top, "label " + t + " -text " + tk->quote(title) + " -bg black -fg white");

	sb := f + ".s";
	lb := f + ".l";
	cmd(b.top, "scrollbar " + sb +
		" -command {" + lb + " yview}");

	cmd(b.top, "listbox " + lb +
		" -selectmode browse" +
		" -yscrollcommand {" + sb + " set}" +
		" -bd 2");

	cmd(b.top, "bind " + lb + " <ButtonRelease-1> +{send colch s " + ncol + "}");
	cmd(b.top, "bind " + lb + " <Double-Button-1> +{send colch d " + ncol + "}");
	cmd(b.top, "pack propagate " + f + " 0");
	cmd(b.top, "pack " + t + " -side top -fill x");
	cmd(b.top, "pack " + sb + " -side left -fill y");
	cmd(b.top, "pack " + lb + " -side left -fill both -expand 1");
	cmd(b.top, "pack " + f + " -side left -fill y");
	for (i := 0; i < len d; i++)
		cmd(b.top, lb + " insert end '" + d[i]);
	setscrollregion(b);
	seecol(b, b.ncols - 1);
}

Browser.resize(b: self ref Browser)
{
	if (b.ncols == 0)
		return;
	setscrollregion(b);
}

seecol(b: ref Browser, cno: int)
{
	w := b.w + ".c.f.d" + string cno;
	min := int cmd(b.top, w + " cget -actx");
	max := min + int cmd(b.top, w + " cget -actwidth") +
			2 * int cmd(b.top, w + " cget -bd");
	min = int cmd(b.top, b.w+".c canvasx " + string min);
	max = int cmd(b.top, b.w +".c canvasx " + string max);

	# see first the right edge; then the left edge, to ensure
	# that the start of a column is visible, even if the window
	# is narrower than one column.
	cmd(b.top, b.w + ".c see " + string max + " 0");
	cmd(b.top, b.w + ".c see " + string min + " 0");
}

Browser.delete(b: self ref Browser, colno: int)
{
	while (b.ncols > colno)
		cmd(b.top, "destroy " + b.w+".c.f.d" + string --b.ncols);
	setscrollregion(b);
}

Browser.selection(b: self ref Browser, cno: int): string
{
	if (cno >= b.ncols || cno < 0)
		return nil;
	l := b.w+".c.f.d" + string cno + ".l";
	sel := cmd(b.top, l + " curselection");
	if (sel == nil)
		return nil;
	return cmdget(b.top, l + " get " + sel);
}

Browser.select(b: self ref Browser, cno: int, e: string)
{
	if (cno < 0 || cno >= b.ncols)
		return;
	l := b.w+".c.f.d" + string cno + ".l";
	cmd(b.top, l + " selection clear 0 end");
	if (e == nil)
		return;
	ents := b.entries(cno);
	for (i := 0; i < len ents; i++) {
		if (deslash(ents[i]) == e) {
			cmd(b.top, l + " selection set " + string i);
			cmd(b.top, l + " see " + string i);
			return;
		}
	}
}

Browser.entries(b: self ref Browser, cno: int): array of string
{
	if (cno < 0 || cno >= b.ncols)
		return nil;
	l := b.w+".c.f.d" + string cno + ".l";
	nent := int cmd(b.top, l + " index end") + 1;
	ents := array[nent] of string;
	for (i := 0; i < len ents; i++)
		ents[i] = cmdget(b.top, l + " get " + string i);
	return ents;
}

# turn each pattern of the form "*.b (Limbo files)" into "*.b".
# ignore '*' as it's a hangover from a past age.
makepats(pats: list of string): (list of string, string)
{
	np: list of string;
	s := "";
	for (; pats != nil; pats = tl pats) {
		p := hd pats;
		for (i := 0; i < len p; i++)
			if (p[i] == ' ')
				break;
		pat := p[0:i];
		if (p != "*") {
			np = p[0:i] :: np;
			s += hd np;
			if (tl pats != nil)
				s[len s] = ' ';
		}
	}
	return (np, s);
}

widgetwidth(top: ref Tk->Toplevel, w: string): int
{
	return int cmd(top, w + " cget -width") + 2 * int cmd(top, w + " cget -bd");
}

skipslash(path: string): string
{
	for (i := 0; i < len path; i++)
		if (path[i] != '/')
			return path[i:];
	return nil;
}

nextelem(path: string): (string, string)
{
	if (path == nil)
		return (nil, nil);
	if (path[0] == '/')
		return ("/", skipslash(path));
	for (i := 0; i < len path; i++)
		if (path[i] == '/')
			break;
	return (path[0:i], skipslash(path[i:]));
}

islastelem(path: string): int
{
	for (i := 0; i < len path; i++)
		if (path[i] == '/')
			return 0;
	return 1;
}

pathcat(path, elem: string): string
{
	if (path != nil && path[len path - 1] != '/')
		path[len path] = '/';
	return path + elem;
}

# remove a possible trailing slash
deslash(s: string): string
{
	if (len s > 0 && s[len s - 1] == '/')
		s = s[0:len s - 1];
	return s;
}

#
# find upper left corner for subsidiary child window (always at constant
# position relative to parent)
#
localgeom(im: ref Draw->Image): string
{
	if (im == nil)
		return nil;

	return sys->sprint("-x %d -y %d", im.r.min.x+STEP, im.r.min.y+STEP);
}

centre(t: ref Tk->Toplevel)
{
	org: Point;
	org.x = t.screenr.dx() / 2 - int cmd(t, ". cget -width") / 2;
	org.y = t.screenr.dy() / 3 - int cmd(t, ". cget -height") / 2;
	if (org.y < 0)
		org.y = 0;
	cmd(t, ". configure -x " + string org.x + " -y " + string org.y);
}

tkcmds(top: ref Tk->Toplevel, a: array of string)
{
	n := len a;
	for(i := 0; i < n; i++)
		tk->cmd(top, a[i]);
}

topopts := array[] of {
	"font"
#	, "bd"			# Wait for someone to ask for these
#	, "relief"		# Note: colors aren't inherited, it seems
};

opts(top: ref Tk->Toplevel) : string
{
	if (top == nil)
		return nil;
	opts := "";
	for ( i := 0; i < len topopts; i++ ) {
		cfg := tk->cmd(top, ". cget " + topopts[i]);
		if ( cfg != "" && cfg[0] != '!' )
			opts += " -" + topopts[i] + " " + tk->quote(cfg);
	}
	return opts;
}
 
kill(pid: int): int
{
	fd := sys->open("/prog/"+string pid+"/ctl", Sys->OWRITE);
	if (fd == nil)
		return -1;
	if (sys->write(fd, array of byte "kill", 4) != 4)
		return -1;
	return 0;
}
Showtk: con 0;

cmd(top: ref Tk->Toplevel, s: string): string
{
	if (Showtk)
		sys->print("%s\n", s);
	e := tk->cmd(top, s);
	if (e != nil && e[0] == '!')
		sys->fprint(sys->fildes(2), "tkclient: tk error %s on '%s'\n", e, s);
	return e;
}

cmdget(top: ref Tk->Toplevel, s: string): string
{
	if (Showtk)
		sys->print("%s\n", s);
	tk->cmd(top, "variable lasterror");
	e := tk->cmd(top, s);
	lerr := tk->cmd(top, "variable lasterror");
	if (lerr != nil) sys->fprint(sys->fildes(2), "tkclient: tk error %s on '%s'\n", e, s);
	return e;
}
