implement Calendar;

#
# Copyright © 2000 Vita Nuova Limited. All rights reserved.
#

include "sys.m";
	sys: Sys;
include "draw.m";
	draw: Draw;
	Font, Point, Rect: import draw;
include "daytime.m";
	daytime: Daytime;
	Tm: import Daytime;
include "tk.m";
	tk: Tk;
include "tkclient.m";
	tkclient: Tkclient;
include "dialog.m";
	dialog: Dialog;
include "readdir.m";
include "translate.m";
	translate: Translate;
	Dict: import translate;
include "arg.m";
	arg: Arg;
include "sh.m";

Calendar: module {
	init: fn(ctxt: ref Draw->Context, argv: list of string);
};

Cal: adt {
	w: string;
	dx, dy: int;
	onepos: int;
	top: ref Tk->Toplevel;
	sched: ref Schedule;
	date: int;
	marked: array of int;
	make: fn(top: ref Tk->Toplevel, sched: ref Schedule, w: string): (ref Cal, chan of string);
	show: fn(cal: self ref Cal, date: int);
	mark: fn(cal: self ref Cal, ent: Entry);
};

Entry: adt {
	date: int;		# YYYYMMDD
	mark: int;
};

Sentry: adt {
	ent: Entry;
	file: int;
};

Schedule: adt {
	dir: string;
	entries: array of Sentry;
	new: fn(dir: string): (ref Schedule, string);
	getentry: fn(sched: self ref Schedule, date: int): (int, Entry);
	readentry: fn(sched: self ref Schedule, date: int): (Entry, string);
	setentry: fn(sched: self ref Schedule, ent: Entry, data: string): (int, string);
};

Markset: adt {
	new: fn(top: ref Tk->Toplevel, cal: ref Cal, w: string): (ref Markset, chan of string);
	set: fn(m: self ref Markset, kind: int);
	get: fn(m: self ref Markset): int;
	ctl: fn(m: self ref Markset, c: string);

	top: ref Tk->Toplevel;
	cal: ref Cal;
	w: string;
	curr: int;
};

DBFSPATH: con "/dis/rawdbfs.dis";
SCHEDDIR: con "/mnt/schedule";

stderr: ref Sys->FD;
dict: ref Dict;
font := "/fonts/lucidasans/unicode.7.font";
days, months: array of string;

packcmds := array[] of {
"pack .ctf.show .ctf.set .ctf.date -side right",
"pack .ctf -side top -fill x",

"pack .cf.head.fwd .cf.head.bwd .cf.head.date -side right",
"pack .cf.head -side top -fill x",
"pack .cf.cal -side top",
"pack .cf -side top",

"pack .schedf.head.fwd .schedf.head.bwd .schedf.head.date .schedf.head.markset"
	+ " .schedf.head.save .schedf.head.del -side right",
"pack .schedf.head -side top -fill x",
"pack .schedf.tf.scroll -side left -fill y",
"pack .schedf.tf.t -side top -fill both -expand 1",
"pack .schedf.tf -side top -fill both -expand 1",
"pack .schedf -side top -fill both -expand 1",
};

Savebut: con ".schedf.head.save";
Delbut: con ".schedf.head.del";

usage()
{
	sys->fprint(stderr, "usage: calendar [-f font] [/mnt/schedule | schedfile]\n");
	raise "fail:usage";
}

init(ctxt: ref Draw->Context, argv: list of string)
{
	loadmods();
	if (ctxt == nil) {
		sys->fprint(sys->fildes(2), "calendar: no window context\n");
		raise "fail:bad context";
	}
	days = Xa(array[] of {"Sun", "Mon", "Tue", "Wed", "Thu", "Fri",  "Sat"});
	months = Xa(array[] of {"Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"});
	arg->init(argv);
	while ((opt := arg->opt()) != 0) {
		case opt {
		'f' =>
			if ((font = arg->arg()) == nil)
				usage();
		* =>
			usage();
		}
	}
	argv = arg->argv();
	scheddir := SCHEDDIR;
	if (argv != nil)
		scheddir = hd argv;
	(top, wmctl) := tkclient->toplevel(ctxt, "", X("Calendar"), Tkclient->Appl);
	if (top == nil) {
		sys->fprint(stderr, "cal: cannot make window: %r\n");
		raise "fail:cannot make window";
	}
	(sched, err) := Schedule.new(scheddir);
	if (sched == nil)
		sys->fprint(stderr, "cal: cannot load schedule: %s\n", err);
	currtime := daytime->local(daytime->now());
	if (currtime == nil) {
		sys->fprint(stderr, "cannot get local time: %r\n");
		raise "fail:failed to get local time";
	}
	date := tm2date(currtime);
	sys->pctl(Sys->NEWPGRP|Sys->FORKNS, nil);

	cmdch := chan of string;
	tk->namechan(top, cmdch, "cmd");
	wincmds := array[] of {
	"frame .ctf",
	"button .ctf.set -text {"+X("Set")+"} -command {send cmd settime}",
	"button .ctf.show -text {"+X("Show")+"} -command {send cmd showtime}",
	
	"frame .cf -bd 2 -relief raised",
	"frame .cf.head",
	"button .cf.head.bwd -text {<<} -command {send cmd bwdmonth}",
	"button .cf.head.fwd -text {>>} -command {send cmd fwdmonth}",
	"label .cf.head.date -text {XXX 0000}",
	
	"frame .schedf -bd 2 -relief raised",
	"frame .schedf.head",
	"button .schedf.head.save -text {"+X("Save")+"} -command {send cmd save}",
	"button .schedf.head.del -text {"+X("Del")+"} -command {send cmd del}",
	"label .schedf.head.date -text {0000/00/00}",
	"canvas .schedf.head.markset",
	"button .schedf.head.bwd -text {<<} -command {send cmd bwdday}",
	"button .schedf.head.fwd -text {>>} -command {send cmd fwdday}",
	"frame .schedf.tf",
	"scrollbar .schedf.tf.scroll -command {.schedf.tf.t yview}",
	"text .schedf.tf.t -wrap word -yscrollcommand {.schedf.tf.scroll set} -height 7h -width 20w",
	"bind .schedf.tf.t <Key> +{send cmd dirty}",
	};
	tkcmds(top, wincmds);
	(cal, calch) := Cal.make(top, sched, ".cf.cal");
	sync := chan of int;
	spawn clock(top, ".ctf.date", sync);
	clockpid := <-sync;
	(ms, msch) := Markset.new(top, cal, ".schedf.head.markset");
	tkcmds(top, packcmds);
	if (sched == nil)
		cmd(top, "pack forget .schedf");

	showdate(top, cal, ms, date);
	cmd(top, "pack propagate . 0");
	cmd(top, "update");
	if (date < 19700002)
		raisesettime(ctxt, top);

	setting := 0;
	dirty := 0;
	empty := scheduleempty(top);
	currsched := 0;

	tkclient->onscreen(top, nil);
	tkclient->startinput(top, "kbd"::"ptr"::nil);

	for (;;) {
		enable(top, Savebut, dirty);
		enable(top, Delbut, !empty);
		cmd(top, "update");
		ndate := date;
		alt {
		c := <-calch =>
			(y,m,d) := date2ymd(date);
			d = int c;
			ndate = ymd2date(y,m,d);
		c := <-msch =>
			ms.ctl(c);
			cal.mark(Entry(date, ms.get()));
			dirty = 1;
		c := <-cmdch =>
			case c {
			"dirty" =>
				dirty = 1;
				nowempty := scheduleempty(top);
				if (nowempty != empty) {
					if (nowempty) {
						ms.set(0);
						cal.mark(Entry(date, 0));
					} else {
						ms.set(1);
						cal.mark(Entry(date, ms.get()));
					}
					empty = nowempty;
				}
			"bwdmonth" =>
				ndate = decmonth(date);
			"fwdmonth" =>
				ndate = incmonth(date);
			"bwdday" =>
				ndate = adddays(date, -1);
			"fwdday" =>
				ndate = adddays(date, 1);
			"del" =>
				if (!empty) {
					cmd(top, ".schedf.tf.t delete 1.0 end");
					empty = 1;
					dirty = 1;
					cal.mark(Entry(date, 0));
				}
			"save" =>
				if (dirty && save(ctxt, top, cal, ms, date) != -1)
					dirty = 0;
			"settime" =>
				raisesettime(ctxt, top);
			"showtime" =>
				ndate = tm2date(daytime->local(daytime->now()));
			* =>
				sys->fprint(stderr, "cal: unknown command '%s'\n", c);
			}
		s := <-top.ctxt.kbd =>
			tk->keyboard(top, s);
		s := <-top.ctxt.ptr =>
			tk->pointer(top, *s);
		c := <-top.ctxt.ctl or
		c = <-top.wreq or
		c = <-wmctl =>
			if (c == "exit" && dirty)
				save(ctxt, top, cal, ms, date);
			tkclient->wmctl(top, c);
		}
		if (ndate != date) {
			e := 0;
			if (dirty)
				e = save(ctxt, top, cal, ms, date);
			if (e != -1) {
				dirty = 0;
				showdate(top, cal, ms, ndate);
				empty = scheduleempty(top);
				date = ndate;
				cmd(top, "update");
			}
		}
	}
}

Markset.new(top: ref Tk->Toplevel, cal: ref Cal, w: string): (ref Markset, chan of string)
{
	cmd(top, w+" configure -width "+string (cal.dx * 2 + 6) +
				" -height "+string (cal.dy + 4));
	ch := chan of string;
	tk->namechan(top, ch, "markcmd");
	return (ref Markset(top, cal, w, 0), ch);
}

Markset.set(m: self ref Markset, kind: int)
{
	cmd(m.top, m.w + " delete x");
	if (kind > 0) {
		(shape, col) := kind2shapecol(kind);
		id := cmd(m.top, m.w + " create " +
			shapestr(m.cal, (m.cal.dx/2+2, m.cal.dy/2+2), Square) +
			" -fill " + colours[col] + " -tags x");
		cmd(m.top, m.w + " bind " + id + " <ButtonRelease-1> {send markcmd col}");
		id = cmd(m.top, m.w + " create " +
			shapestr(m.cal, (m.cal.dx * 3 / 2+4, m.cal.dy/2+2), shape) +
			" -tags x -width 2");
		cmd(m.top, m.w + " bind " + id + " <ButtonRelease-1> {send markcmd shape}");
	}
	m.curr = kind;
}

Markset.get(m: self ref Markset): int
{
	return m.curr;
}

Markset.ctl(m: self ref Markset, c: string)
{
	(shape, col) := kind2shapecol(m.curr);
	case c {
	"col" => col = (col + 1) % len colours;
	"shape" => shape = (shape + 1) % Numshapes;
	}
	m.set(shapecol2kind((shape, col)));
}

scheduleempty(top: ref Tk->Toplevel): int
{
	return int cmd(top, ".schedf.tf.t compare 1.0 == end");
}

enable(top: ref Tk->Toplevel, but: string, enable: int)
{
	cmd(top, but + " configure -state " +
		(array[] of {"disabled", "normal"})[!!enable]);
}

save(ctxt: ref Draw->Context, top: ref Tk->Toplevel, cal: ref Cal, ms: ref Markset, date: int): int
{
	s := cmd(top, ".schedf.tf.t get 1.0 end");
	empty := scheduleempty(top);
	mark := ms.get();
	if (empty)
		mark = 0;
	ent := Entry(date, mark);
	cal.mark(ent);
	(ok, err) := cal.sched.setentry(ent, s);
	if (ok == -1) {
		notice(ctxt, top, "Cannot save entry: " + err);
		return -1;
	}
	return 0;
}

notice(ctxt: ref Draw->Context, top: ref Tk->Toplevel, s: string)
{
	dialog->prompt(ctxt, top.image, nil, "Notice", s, 0, "OK"::nil);
}

showdate(top: ref Tk->Toplevel, cal: ref Cal, ms: ref Markset, date: int)
{
	(y,m,d) := date2ymd(date);
 	cal.show(date);
	cmd(top, ".cf.head.date configure -text {" + sys->sprint("%.4d/%.2d", y, m+1) + "}");
	cmd(top, ".schedf.head.date configure -text {" + sys->sprint("%.4d/%.2d/%.2d", y, m+1, d) + "}");
	(ent, s) := cal.sched.readentry(date);
	ms.set(ent.mark);
	cmd(top, ".schedf.tf.t delete 1.0 end; .schedf.tf.t insert 1.0 '" + s);
}

nomod(s: string)
{
	sys->fprint(stderr, "cal: cannot load %s: %r\n", s);
	raise "fail:bad module";
}

loadmods()
{
	sys = load Sys Sys->PATH;
	stderr = sys->fildes(2);
	draw = load Draw Draw->PATH;
	tk = load Tk Tk->PATH;
	daytime = load Daytime Daytime->PATH;
	if (daytime == nil)
		nomod(Daytime->PATH);
	tkclient = load Tkclient Tkclient->PATH;
	if (tkclient == nil)
		nomod(Tkclient->PATH);
	translate = load Translate Translate->PATH;
	if(translate != nil){
		translate->init();
		(dict, nil) = translate->opendict(translate->mkdictname("", "calendar"));
	}
	tkclient->init();
	arg = load Arg Arg->PATH;
	if (arg == nil)
		nomod(Arg->PATH);
	dialog = load Dialog Dialog->PATH;
	if(dialog == nil)
		nomod(Dialog->PATH);
	dialog->init();
}

s2a(s: string, min, max: int, sep: string): array of int
{
	(ntoks, toks) := sys->tokenize(s, sep);
	if (ntoks < min || ntoks > max)
		return nil;
	a := array[max] of int;
	for (i := 0; toks != nil; toks = tl toks) {
		if (!isnum(hd toks))
			return nil;
		a[i++] = int hd toks;
	}
	return a[0:i];
}

validtm(t: ref Daytime->Tm): int
{
	if (t.hour < 0 || t.hour > 23
			|| t.min < 0 || t.min > 59
			|| t.sec < 0 || t.sec > 59
			|| t.mday < 1 || t.mday > 31
			|| t.mon < 0 || t.mon > 11
			|| t.year < 70 || t.year > 137)
		return 0;
	if (t.mon == 1 && dysize(t.year+1900) > 365)
		return t.mday <= 29;
	return t.mday <= dmsize[t.mon];
}

clock(top: ref Tk->Toplevel, w: string, sync: chan of int)
{
	cmd(top, "label " + w);	
	fd := sys->open("/dev/time", Sys->OREAD);
	if (fd == nil) {
		sync <-= -1;
		return;
	}
	buf := array[128] of byte;
	for (;;) {
		sys->seek(fd, big 0, Sys->SEEKSTART);
		n := sys->read(fd, buf, len buf);
		if (n < 0) {
			sys->fprint(stderr, "cal: could not read time: %r\n");
			if (sync != nil)
				sync <-= -1;
			break;
		}
		ms := big string buf[0:n] / big 1000;
		ct := ms / big 1000;
		t := daytime->local(int ct);

		s := sys->sprint("%s %s %d %.2d:%.2d.%.2d",
			days[t.wday], months[t.mon], t.mday, t.hour, t.min, t.sec);
		cmd(top, w + " configure -text {" + s + "}");
		cmd(top, "update");
		if (sync != nil) {
			sync <-= sys->pctl(0, nil);
			sync = nil;
		}
		sys->sleep(int ((ct + big 1) * big 1000 - ms));
	}
}

# "the world is the lord's and all it contains,
# save the highlands and islands, which belong to macbraynes"
Cal.make(top: ref Tk->Toplevel, sched: ref Schedule, w: string): (ref Cal, chan of string)
{
	f := Font.open(top.display, font);
	if (f == nil) {
		sys->fprint(stderr, "cal: could not open font %s: %r\n", font);
		font = cmd(top, ". cget -font");
		f = Font.open(top.display, font);
	}
	if (f == nil)
		return (nil, nil);
	maxw := 0;
	for (i := 0; i < 7; i++) {
		if ((dw := f.width(days[i] + " ")) > maxw)
			maxw = dw;
	}
	for (i = 10; i < 32; i++) {
		if ((dw := f.width(string i + " ")) > maxw)
			maxw = dw;
	}
	cal := ref Cal;
	cal.w = w;
	cal.dx = maxw;
	cal.dy = f.height;
	cal.onepos = 0;
	cal.top = top;
	cal.sched = sched;
	cal.marked = array[31] of {* => 0};
	cmd(top, "canvas " + w + " -width " + string (cal.dx * 7) + " -height " + string (cal.dy * 7));
	for (i = 0; i < 7; i++)
		cmd(top, w + " create text " + posstr(daypos(cal, i, 0))
				+ " -text " + days[i] + " -font " + font);
	ch := chan of string;
	tk->namechan(top, ch, "ch" + w);
	return (cal, ch);
}

Cal.show(cal: self ref Cal, date: int)
{
	if (date == cal.date)
		return;
	mon := (date / 100) % 100;
	year := date / 10000;
	cmd(cal.top, cal.w + " delete curr");
	if (cal.date / 100 != date / 100) {
		cmd(cal.top, cal.w + " delete date");
		cmd(cal.top, cal.w + " delete mark");
		for (i := 0; i < len cal.marked; i++)
			cal.marked[i] = 0;
		(md, wd) := monthinfo(mon, year);
		base := year * 10000 + mon * 100;
		cal.onepos = wd;
		for (i = 0; i < 6; i++) {
			for (j := 0; j < 7; j++) {
				d := i * 7 + j - wd;
				if (d >= 0 && d < md) {
					id := cmd(cal.top, cal.w + " create text " + posstr(daypos(cal, j, i+1))
						+ " -tags date -text " + string (d+1)
						+ " -font " + font);
					cmd(cal.top, cal.w + " bind " + id +
						" <ButtonRelease-1> {send ch" + cal.w + " " + string (d+1) + "}");
					(ok, ent) := cal.sched.getentry(base + d + 1);
					if (ok != -1)
						cal.mark(ent);
				}
			}
		}
	}
	if (cal.sched != nil) {
		e := date % 100 - 1 + cal.onepos;
		p := daypos(cal, e % 7, e / 7 + 1);
		cmd(cal.top, cal.w + " create " + shapestr(cal, p, Square) +
				" -tags curr -width 3");
	}
	cal.date = date;
}

Cal.mark(cal: self ref Cal, ent: Entry)
{
	if (ent.date / 100 != ent.date / 100)
		return;
	(nil, nil, d) := date2ymd(ent.date);
	d--;
	cmd(cal.top, cal.w + " delete m" + string d);
	if (ent.mark) {
		e := d + cal.onepos;
		p := daypos(cal, e % 7, e / 7 + 1);
		id := cmd(cal.top, cal.w + " create " + itemshape(cal, p, ent.mark) +
				" -tags {mark m"+string d + "}");
		cmd(cal.top, cal.w + " bind " + id +
				" <ButtonRelease-1> {send ch" + cal.w + " " + string (d+1) + "}");
		cmd(cal.top, cal.w + " lower " + id);
	}
	cal.marked[d] = ent.mark;
}

Oval, Diamond, Square, Numshapes: con iota;

colours := array[] of {
	"red",
	"yellow",
	"#00eeee",
	"white"
};

kind2shapecol(kind: int): (int, int)
{
	kind = (kind - 1) & 16rffff;
	return ((kind & 16rff) % Numshapes, (kind >> 8) % len colours);
}

shapecol2kind(shapecol: (int, int)): int
{
	(shape, colour) := shapecol;
	return (shape + (colour << 8)) + 1;
}

itemshape(cal: ref Cal, centre: Point, kind: int): string
{
	(shape, colour) := kind2shapecol(kind);
	return shapestr(cal, centre, shape) + " -fill " + colours[colour];
}

shapestr(cal: ref Cal, p: Point, kind: int): string
{
	(hdx, hdy) := (cal.dx / 2, cal.dy / 2);
	case kind {
	Oval =>
		r := Rect((p.x - hdx, p.y - hdy), (p.x + hdx, p.y + hdy));
		return "oval " + rectstr(r);
	Diamond =>
		return "polygon " + string (p.x - hdx) + " " + string p.y + " " +
					string p.x + " " + string (p.y - hdy) + " " +
					string (p.x + hdx) + " " + string p.y + " " +
					string p.x + " " + string (p.y + hdy) +
				" -outline black";
	Square =>
		r := Rect((p.x - hdx, p.y - hdy), (p.x + hdx, p.y + hdy));
		return "rectangle " + rectstr(r);
	* =>
		sys->fprint(stderr, "cal: unknown shape %d\n", kind);
		return nil;
	}
}
		
rectstr(r: Rect): string
{
	return string r.min.x + " " + string r.min.y + " " +
			string r.max.x + " " + string r.max.y;
}

posstr(p: Point): string
{
	return string p.x + " " + string p.y;
}

# return centre point of position for day.
daypos(cal: ref Cal, d, w: int): Point
{
	return Point(d * cal.dx + cal.dx / 2, w * cal.dy + cal.dy / 2);
}

body2entry(body: string): (int, Entry, string)
{
	for (i := 0; i < len body; i++)
		if (body[i] == '\n')
			break;
	if (i == len body)
		return (-1, (-1, -1), "invalid schedule header (no newline)");
	(n, toks) := sys->tokenize(body[0:i], " \t\n");
	if (n < 2)
		return (-1, (-1, -1), "invalid schedule header (too few fields)");
	date := int hd toks;
	(y, m, d) := (date / 10000, (date / 100) % 100, date%100);
	if (y < 1970 || y > 2037 || m > 12 || m < 1 || d > 31 || d < 1)
		return (-1, (-1,-1), sys->sprint("invalid date (%.8d) in schedule header", date));
	e := Entry(ymd2date(y, m-1, d), int hd tl toks);
	return (0, e, body[i+1:]);
}

startdbfs(f: string): (string, string)
{
	dbfs := load Command DBFSPATH;
	if (dbfs == nil)
		return (nil, sys->sprint("cannot load %s: %r", DBFSPATH));
	sync := chan of string;
	spawn rundbfs(sync, dbfs, f, SCHEDDIR);
	e := <-sync;
	if (e != nil)
		return (nil, e);
	return (SCHEDDIR, nil);
}

rundbfs(sync: chan of string, dbfs: Command, f, d: string)
{
	sys->pctl(Sys->FORKFD, nil);
	{
		dbfs->init(nil, "dbfs" :: "-r" :: f :: d :: nil);
		sync <-= nil;
	}exception e{
	"fail:*" =>
		sync <-= "dbfs failed: " + e[5:];
		exit;
	}
}

Schedule.new(d: string): (ref Schedule, string)
{
	(rc, info) := sys->stat(d);
	if (rc == -1)
		return (nil, sys->sprint("cannot find %s: %r", d));
	if ((info.mode & Sys->DMDIR) == 0) {
		err: string;
		(d, err) = startdbfs(d);
		if (d == nil)
			return (nil, err);
	}
	(rc, nil) = sys->stat(d + "/new");
	if (rc == -1)
		return (nil, "no dbfs mounted on " + d);
		
	readdir := load Readdir Readdir->PATH;
	if (readdir == nil)
		return (nil, sys->sprint("cannot load %s: %r", Readdir->PATH));
	sched := ref Schedule;
	sched.dir = d;
	(de, nil) := readdir->init(d, Readdir->NONE);
	if (de == nil)
		return (nil, "could not read schedule directory");
	buf := array[Sys->ATOMICIO] of byte;
	sched.entries = array[len de] of Sentry;
	ne := 0;
	for (i := 0; i < len de; i++) {
		if (!isnum(de[i].name))
			continue;
		f := d + "/" + de[i].name;
		fd := sys->open(f, Sys->OREAD);
		if (fd == nil) {
			sys->fprint(stderr, "cal: cannot open %s: %r\n", f);
		} else {
			n := sys->read(fd, buf, len buf);
			if (n == -1) {
				sys->fprint(stderr, "cal: error reading %s: %r\n", f);
			} else {
				(ok, e, err) := body2entry(string buf[0:n]);
				if (ok == -1)
					sys->fprint(stderr, "cal: error on entry %s: %s\n", f, err);
				else
					sched.entries[ne++] = (e, int de[i].name);
				err = nil;
			}
		}
	}
	sched.entries = sched.entries[0:ne];
	sortentries(sched.entries);
	return (sched, nil);
}

Schedule.getentry(sched: self ref Schedule, date: int): (int, Entry)
{
	if (sched == nil)
		return (-1, (-1, -1));
	ent := search(sched, date);
	if (ent == -1)
		return (-1, (-1,-1));
	return (0, sched.entries[ent].ent);
}

Schedule.readentry(sched: self ref Schedule, date: int): (Entry, string)
{
	if (sched == nil)
		return ((-1, -1), nil);
	ent := search(sched, date);
	if (ent == -1)
		return ((-1, -1), nil);
	(nil, fno) := sched.entries[ent];

	f := sched.dir + "/" + string fno;
	fd := sys->open(f, Sys->OREAD);
	if (fd == nil) {
		sys->fprint(stderr, "cal: cannot open %s: %r", f);
		return ((-1, -1), nil);
	}
	buf := array[Sys->ATOMICIO] of byte;
	n := sys->read(fd, buf, len buf);
	if (n == -1) {
		sys->fprint(stderr, "cal: cannot read %s: %r", f);
		return ((-1, -1), nil);
	}
	(ok, e, body) := body2entry(string buf[0:n]);
	if (ok == -1) {
		sys->fprint(stderr, "cal: couldn't get body in file %s: %s\n", f, body);
		return ((-1, -1), nil);
	}
	return (e, body);
}	

writeentry(fd: ref Sys->FD, ent: Entry, data: string): (int, string)
{
	ent.date += 100;
	b := array of byte (sys->sprint("%d %d\n", ent.date, ent.mark) + data);
	if (len b > Sys->ATOMICIO)
		return (-1, "entry is too long");
	if (sys->write(fd, b, len b) != len b)
		return (-1, sys->sprint("cannot write entry: %r"));
	return (0, nil);
}
	
Schedule.setentry(sched: self ref Schedule, ent: Entry, data: string): (int, string)
{
	if (sched == nil)
		return (-1, "no schedule");
	idx := search(sched, ent.date);
	if (idx == -1) {
		if (data == nil)
			return (0, nil);
		fd := sys->open(sched.dir + "/new", Sys->OWRITE);
		if (fd == nil)
			return (-1, sys->sprint("cannot open new: %r"));
		(ok, info) := sys->fstat(fd);
		if (ok == -1)
			return (-1, sys->sprint("cannot stat new: %r"));
		if (!isnum(info.name))
			return (-1, "new dbfs entry is not numeric");
		err: string;
		(ok, err) = writeentry(fd, ent, data);
		if (ok == -1)
			return (ok, err);
		(fd, data) = (nil, nil);
		e := sched.entries;
		for (i := 0; i < len e; i++)
			if (ent.date < e[i].ent.date)
				break;
		ne := array[len e + 1] of Sentry;
		(ne[0:],  ne[i], ne[i+1:]) = (e[0:i], (ent, int info.name), e[i:]);
		sched.entries = ne;
		return (0, nil);
	} else {
		fno := sched.entries[idx].file;
		f := sched.dir + "/" + string fno;
		if (data == nil) {
			sys->remove(f);
			sched.entries[idx:] = sched.entries[idx+1:];
			sched.entries = sched.entries[0:len sched.entries - 1];
			return (0, nil);
		} else {
			sched.entries[idx] = (ent, fno);
			fd := sys->open(f, Sys->OWRITE);
			if (fd == nil)
				return (-1, sys->sprint("cannot open %s: %r", sched.dir + "/" + string fno));
			return writeentry(fd, ent, data);
		}
	}
}

search(sched: ref Schedule, date: int): int
{
	e := sched.entries;
	lo := 0;
	hi := len e - 1;
	while (lo <= hi) {
		mid := (lo + hi) / 2;
		if (date < e[mid].ent.date)
			hi = mid - 1;
		else if (date > e[mid].ent.date)
			lo = mid + 1;
		else
			return mid;
	}
	return -1;
}

sortentries(a: array of Sentry)
{
	m: int;
	n := len a;
	for(m = n; m > 1; ) {
		if(m < 5)
			m = 1;
		else
			m = (5*m-1)/11;
		for(i := n-m-1; i >= 0; i--) {
			tmp := a[i];
			for(j := i+m; j <= n-1 && tmp.ent.date > a[j].ent.date; j += m)
				a[j-m] = a[j];
			a[j-m] = tmp;
		}
	}
}

raisesettime(ctxt: ref Draw->Context, top: ref Tk->Toplevel)
{
	panelcmds := array[] of {
	"frame .d",
	"label .d.title -text {"+X("Date (YYYY/MM/DD):")+"}",
	"entry .d.de -width 11w}",
	"frame .t",
	"label .t.title -text {"+X("Time (HH:MM.SS):")+"}",
	"entry .t.te -width 11w}",
	"frame .b",
	"button .b.set -text Set -command {send cmd set}",
	"button .b.cancel -text Cancel -command {send cmd cancel}",
	"pack .d .t .b -side top -fill x",
	"pack .d.de .d.title -side right",
	"pack .t.te .t.title -side right",
	"pack .b.set .b.cancel -side right",
	};
	fd := sys->open("/dev/time", Sys->OWRITE);
	if (fd == nil) {
		notice(ctxt, top, X("Cannot set time: ") + sys->sprint("%r"));
		return;
	}
	(panel, wmctl) := tkclient->toplevel(ctxt, "",	X("Set Time"), 0);
	tkcmds(panel, panelcmds);
	cmdch := chan of string;
	tk->namechan(panel, cmdch, "cmd");
	t := daytime->local(daytime->now());
	if (t.year < 71)
		(t.year, t.mon, t.mday) = (100, 0, 1);
	cmd(panel, ".d.de insert 0 " + sys->sprint("%.4d/%.2d/%.2d",
				t.year+1900, t.mon+1, t.mday));
	cmd(panel, ".t.te insert 0 " + sys->sprint("%.2d:%.2d.%.2d", t.hour, t.min, t.sec));
	#cmd(panel, "grab set ."); XXX should, but not a good idea with global tk.
	# wouldn't work with current dialog->prompt() either...
	cmd(panel, "update");
	tkclient->onscreen(panel, nil);
	tkclient->startinput(panel, "kbd"::"ptr"::nil);

loop: for (;;) alt {
	s := <-panel.ctxt.kbd =>
		tk->keyboard(panel, s);
	s := <-panel.ctxt.ptr =>
		tk->pointer(panel, *s);
	c := <-cmdch =>
		case c {
		"set" =>
			err := settime(fd, cmd(panel, ".d.de get"), cmd(panel, ".t.te get"));
			if (err == nil)
				break loop;
			notice(ctxt, panel, X("Cannot set time: ") + err);
		"cancel" =>
			break loop;
		* =>;
		}
	c := <-wmctl =>
		case c {
		"exit" =>
			break loop;
		* =>
			tkclient->wmctl(panel, c);
		}
	}
}

settime(tfd: ref Sys->FD, date, time: string): string
{
	da := s2a(date, 3, 3, "/");
	if (da == nil)
		return X("Invalid date syntax");
	ta := s2a(time, 2, 3, ":.");
	if (ta == nil)
		return X("Invalid time syntax");
	t := ref blanktm;
	if (da[2] > 1000)
		(da[0], da[1], da[2]) = (da[2], da[1], da[0]);
	(t.year, t.mon, t.mday) = (da[0]-1900, da[1]-1, da[2]);
	if (len ta == 3)
		(t.hour, t.min, t.sec) = (ta[0], ta[1], ta[2]);
	else
		(t.hour, t.min, t.sec) = (ta[0], ta[1], 0);
	if (!validtm(t))
		return X("Invalid time or date given");
	s := string daytime->tm2epoch(t) + "000000";
	if (sys->fprint(tfd, "%s", s) == -1)
		return X("write failed:") + sys->sprint(" %r");
	return nil;
}
	

cmd(top: ref Tk->Toplevel, cmd: string): string
{
	e := tk->cmd(top, cmd);
	if (e != nil && e[0] == '!')
		sys->fprint(stderr, "cal: tk error on '%s': %s\n", cmd, e);
	return e;
}

tkcmds(top: ref Tk->Toplevel, a: array of string)
{
	for (i := 0; i < len a; i++)
		cmd(top, a[i]);
}

isnum(s: string): int
{
	for (i := 0; i < len s; i++)
		if (s[i] < '0' || s[i] > '9')
			return 0;
	return 1;
}

tm2date(t: ref Tm): int
{
	if (t == nil)
		return 19700001;
	return ymd2date(t.year+1900, t.mon, t.mday);
}

date2ymd(date: int): (int, int, int)
{
	return (date / 10000, (date / 100) % 100, date%100);
}

ymd2date(y, m, d: int): int
{
	return d + m* 100 + y * 10000;
}

adddays(date, delta: int): int
{
	t := ref blanktm;
	t.mday = date % 100;
	t.mon = (date / 100) % 100;
	t.year = (date / 10000) - 1900;
	t.hour = 12;
	e := daytime->tm2epoch(t);
	e += delta * 24 * 60 * 60;
	t = daytime->gmt(e);
	if (!validtm(t))
		return date;
	return tm2date(t);
}

incmonth(date: int): int
{
	(y,m,d) := date2ymd(date);
	if (m < 11)
		m++;
	else if (y < 2037)
		(y, m) = (y+1, 0);
	(n, nil) := monthinfo(m, y);
	if (d > n)
		d = n;
	return ymd2date(y,m,d);
}

decmonth(date: int): int
{
	(y,m,d) := date2ymd(date);
	if (m > 0)
		m--;
	else if (y > 1970)
		(y, m) = (y-1, 11);
	(n, nil) := monthinfo(m, y);
	if (d > n)
		d = n;
	return ymd2date(y,m,d);
}

dmsize := array[] of {
	31, 28, 31, 30, 31, 30,
	31, 31, 30, 31, 30, 31
};

dysize(y: int): int
{
	if( (y%4) == 0 && (y % 100 != 0 || y % 400 == 0) )
		return 366;
	return 365;
}

blanktm: Tm;

# return number of days in month and
# starting day of month/year.
monthinfo(mon, year: int): (int, int)
{
	t  := ref blanktm;
	t.mday = 1;
	t.mon = mon;
	t.year = year - 1900;
	t = daytime->gmt(daytime->tm2epoch(t));
	md := dmsize[mon];
	if (dysize(year) == 366 && t.mon == 1)
		md++;
	return (md, t.wday);
}

X(s: string): string
{
	#sys->print("\"%s\"\n", s);
	if (dict == nil)
		return s;
	return dict.xlate(s);
}

Xa(a: array of string): array of string
{
	for (i := 0; i < len a; i++)
		a[i] = X(a[i]);
	return a;
}

