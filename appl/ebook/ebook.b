implement Ebook;

include "sys.m";
	sys: Sys;
include "draw.m";
	draw: Draw;
	Point, Rect: import draw;
include "tk.m";
	tk: Tk;
include "tkclient.m";
	tkclient: Tkclient;
include "bufio.m";
	bufio: Bufio;
	Iobuf: import bufio;
include "string.m";
	str: String;
include "keyboard.m";
include "url.m";
	url: Url;
	ParsedUrl: import url;
include "xml.m";
include "stylesheet.m";
include "cssparser.m";
include "oebpackage.m";
	oebpackage: OEBpackage;
	Package: import oebpackage;
include "reader.m";
	reader: Reader;
	Datasource, Mark, Block: import reader;
include "profile.m";
	profile: Profile;
include "arg.m";

Doprofile: con 0;

# TO DO
# - error notices.
# + indexes based on display size and font information.
# - navigation by spine contents
# - navigation by guide, tour contents
# - searching?

Ebook: module {
	init: fn(ctxt: ref Draw->Context, argv: list of string);
};

Font: con "/fonts/charon/plain.small.font";
LASTPAGE: con 16r7fffffff;

Book: adt {
	win: ref Tk->Toplevel;
	evch: string;
	size:	Point;
	w: string;
	showannot: int;

	d: ref Document;
	pkg: ref OEBpackage->Package;
	fallbacks: list of (string, string);
	item: ref OEBpackage->Item;
	page: int;
	indexprogress: chan of int;

	sequence: list of ref OEBpackage->Item;		# currently selected sequence

	new:		fn(f: string, win: ref Tk->Toplevel, w: string, evch: string, size: Point,
					indexprogress: chan of int): (ref Book, string);
	gotolink:	fn(book: self ref Book, where: string): string;
	gotopage:	fn(book: self ref Book, page: int);
	goto:	fn(book: self ref Book, m: ref Bookmark);
	mark:	fn(book: self ref Book): ref Bookmark;
	forward:	fn(book: self ref Book);
	back:	fn(book: self ref Book);
	showannotations: fn(book: self ref Book, showannot: int);
	show:	fn(book: self ref Book, item: ref OEBpackage->Item);
	title:		fn(book: self ref Book): string;
};

Bookmark: adt {
	item:		ref OEBpackage->Item;
	page:	int;		# XXX should be fileoffset
};

Document: adt {
	w:		string;
	p:		ref Page;		# current page
	firstmark:	ref Mark;		# start  of first element on current page
	endfirstmark:	ref Mark;	# end of first element on current page
	lastmark:	ref Mark;		# start of last element on current page
	endlastmark:	ref Mark;	# end of last element on current page (nil if we're there)
	nextoffset:	int;		# y offset of first element on next page
	datasrc:	ref Datasource;
	indexed:	int;
	pagenum:	int;
	size:		Point;
	index:	ref Index;
	annotations: array of ref Annotation;
	showannot: int;
	item:		ref OEBpackage->Item;
	fallbacks:	list of (string, string);
	indexprogress: chan of int;

	new:		fn(i: ref OEBpackage->Item, fallbacks: list of (string, string),
				win: ref Tk->Toplevel, w: string, size: Point, evch: string,
				indexprogress: chan of int): (ref Document, string);
	fileoffset:	fn(d: self ref Document): int;
	title:		fn(d: self ref Document): string;
	goto:	fn(d: self ref Document, n: int): int;
	gotooffset:	fn(d: self ref Document, o: int);
	gotolink:	fn(d: self ref Document, name: string): int;

	addannotation: fn(d: self ref Document, a: ref Annotation);
	delannotation: fn(d: self ref Document, a: ref Annotation);
	getannotation: fn(d: self ref Document, fileoffset: int): ref Annotation;
	updateannotation: fn(d: self ref Document, a: ref Annotation);
	showannotations: fn(d: self ref Document, show: int);
	writeannotations: fn(d: self ref Document): string;
};


Index: adt {
	rq:		chan of (int, chan of (int, (ref Mark, int)));
	linkrq:	chan of (string, chan of int);
	indexed:	chan of (array of (ref Mark, int), ref Links);
	d:		ref Datasource;
	size:		Point;
	length:	int;			# length of index file
	f:		string;		# name of index file

	new:		fn(i: ref OEBpackage->Item, d:  ref Datasource, size: Point, force: int,
				indexprogress: chan of int): ref Index;
	get:		fn(i: self ref Index, n: int): (int, (ref Mark, int));
	getlink:	fn(i: self ref Index, name: string): int;
	abort:	fn(i: self ref Index);
	stop:	fn(i: self ref Index);
};

Page: adt {
	win:		ref Tk->Toplevel;
	w:		string;
	min, max:	int;
	height:	int;
	yorigin:	int;
	bmargin:	int;

	new:		fn(win: ref Tk->Toplevel, w: string): ref Page;
	del:		fn(p: self ref Page);
	append:	fn(p: self ref Page, b: Block);
	remove:	fn(p: self ref Page, atend: int):  Block;
	scrollto:	fn(p: self ref Page, y: int);
	count:	fn(p: self ref Page): int;
	bbox:	fn(p: self ref Page, n: int): Rect;
	bboxw:	fn(p: self ref Page, w: string): Rect;
	canvasr:	fn(p: self ref Page, r: Rect): Rect;
	window:	fn(p: self ref Page, n: int): string;
	maxy:	fn(p: self ref Page): int;
	conceal:	fn(p: self ref Page, y: int);
	visible:	fn(p: self ref Page): int;
	getblock:	fn(p: self ref Page, n: int): Block;
};

Annotationwidth: con "20w";
Spikeradius: con 3;

Annotation: adt {
	fileoffset: int;
	text: string;
};

stderr: ref Sys->FD;
warningch: chan of (Xml->Locator, string);
debug := 0;

usage()
{
	sys->fprint(stderr, "usage: ebook [-m] bookfile\n");
	raise "fail:usage";
}

Flatopts: con "-bg white -relief flat -activebackground white -activeforeground black";
Menubutopts: con "-bg white -relief ridge -activebackground white -activeforeground black";

gctxt: ref Draw->Context;

init(ctxt: ref Draw->Context, argv: list of string)
{
	gctxt = ctxt;
	loadmods();

	size := Point(400, 600);
	arg := load Arg Arg->PATH;
	if(arg == nil)
		badmodule(Arg->PATH);
	arg->init(argv);
	while((opt := arg->opt()) != 0)
		case opt {
		'm' =>
			size = Point(240, 320);
		'd' =>
			debug = 1;
		* =>
			usage();
		}
	argv = arg->argv();
	arg = nil;
	if (len argv != 1)
		usage();

	sys->pctl(Sys->NEWPGRP, nil);
	reader->init(ctxt.display);
	(win, ctlchan) := tkclient->toplevel(ctxt, nil, hd argv, Tkclient->Hide);
	cch := chan of string;
	tk->namechan(win, cch, "c");

	evch := chan of string;
	tk->namechan(win, evch, "evch");

	cmd(win, "frame .f -bg white");
	cmd(win, "button .f.up -text {↑} -command {send evch up}" + Flatopts);
	cmd(win, "button .f.down -text {↓} -command {send evch down}" + Flatopts);
	cmd(win, "button .f.next -text {→} -command {send evch forward}" + Flatopts);
	cmd(win, "button .f.prev -text {←} -command {send evch back}" + Flatopts);
	cmd(win, "label .f.pagenum -text 0 -bg white -relief flat  -bd 0 -width 8w -anchor e");
	cmd(win, "menubutton .f.annot -menu .f.annot.m " + Menubutopts + " -text {Opts}");
	cmd(win, "menu .f.annot.m");
	cmd(win, ".f.annot.m add checkbutton -text {Annotations} -command {send evch annot} -variable annot");
	cmd(win, ".f.annot.m invoke 0");
	cmd(win, "pack .f.annot -side left");
	cmd(win, "pack .f.pagenum .f.down .f.up  .f.next .f.prev -side right");
	cmd(win, "focus .");
	cmd(win, "bind .Wm_t <Button-1> +{focus .}");
	cmd(win, "bind .Wm_t.title <Button-1> +{focus .}");
	cmd(win, sys->sprint("bind . <Key-%c> {send evch up}", Keyboard->Up));
	cmd(win, sys->sprint("bind . <Key-%c> {send evch down}", Keyboard->Down));
	cmd(win, sys->sprint("bind . <Key-%c> {send evch forward}", Keyboard->Right));
	cmd(win, sys->sprint("bind . <Key-%c> {send evch back}", Keyboard->Left));
	cmd(win, "pack .f -side top -fill x");

	# pack a temporary frame to see what size we're actually allocated.
	cmd(win, "frame .tmp");
	cmd(win, "pack .tmp -side top -fill both -expand 1");
	cmd(win, "pack propagate . 0");
	cmd(win, ". configure -width " + string size.x + " -height " + string size.y);
#	fittoscreen(win);
	size.x = int cmd(win, ".tmp cget -actwidth");
	size.y = int cmd(win, ".tmp cget -actheight");
	cmd(win, "destroy .tmp");

	spawn showpageproc(win, ".f.pagenum", indexprogress := chan of int, pageprogress := chan of string);

	(book, e) := Book.new(hd argv, win, ".d", "evch", size, indexprogress);
	if (book == nil) {
		pageprogress <-= nil;
		sys->fprint(sys->fildes(2), "ebook: cannot open book: %s\n", e);
		raise "fail:error";
	}
	if (book.pkg.guide != nil) {
		makemenu(win, ".f.guide", "Guide", book.pkg.guide);
		cmd(win, "pack .f.guide -before .f.pagenum -side left");
	}
		
	cmd(win, "pack .d -side top -fill both -expand 1");
	tkclient->onscreen(win, nil);
	tkclient->startinput(win, "kbd"::"ptr"::nil);
	warningch = chan of (Xml->Locator, string);
	spawn warningproc(warningch);
	spawn handlerproc(book, evch, exitedch := chan of int, pageprogress);
	for (;;) alt {
	s := <-win.ctxt.kbd =>
		tk->keyboard(win, s);
	s := <-win.ctxt.ptr =>
		tk->pointer(win, *s);
	s := <-win.ctxt.ctl or
	s = <-win.wreq or
	s = <-ctlchan =>
		if (s == "exit") {
			evch <-= "exit";
			<-exitedch;
		}
		tkclient->wmctl(win, s);
	}
}

makemenu(win: ref Tk->Toplevel, w: string, title: string, items: list of ref OEBpackage->Reference)
{
	cmd(win, "menubutton " + w + " -menu " + w + ".m " + Menubutopts + " -text '" + title);
	m := w + ".m";
	cmd(win, "menu " + m);
	for (; items != nil; items = tl items) {
		item := hd items;
		# assumes URLs can't have '{}' in them.
		cmd(win, m + " add command -text " + tk->quote(item.title) +
			" -command {send evch goto " + item.href + "}");
	}
}

loadmods()
{
	sys = load Sys Sys->PATH;
	stderr = sys->fildes(2);
	draw = load Draw Draw->PATH;
	tk = load Tk Tk->PATH;
	bufio = load Bufio Bufio->PATH;

	str = load String String->PATH;
	if (str == nil)
		badmodule(String->PATH);

	url = load Url Url->PATH;
	if (url == nil)
		badmodule(Url->PATH);
	url->init();

	tkclient = load Tkclient Tkclient->PATH;
	if (tkclient == nil)
		badmodule(Tkclient->PATH);
	tkclient->init();

	reader = load Reader Reader->PATH;
	if (reader == nil)
		badmodule(Reader->PATH);

	xml := load Xml Xml->PATH;
	if (xml == nil)
		badmodule(Xml->PATH);
	xml->init();

	oebpackage = load OEBpackage OEBpackage->PATH;
	if (oebpackage == nil)
		badmodule(OEBpackage->PATH);
	oebpackage->init(xml);

	if (Doprofile) {
		profile = load Profile Profile->PATH;
		if (profile == nil)
			badmodule(Profile->PATH);
		profile->init();
		profile->sample(10);
	}
}

showpageproc(win: ref Tk->Toplevel, w: string, indexprogress: chan of int, pageprogress: chan of string)
{
	page := "0";
	indexed: int;
	for (;;) {
		alt {
		page = <-pageprogress =>;
		indexed = <-indexprogress =>;
		}
		if (page == nil)
			exit;
		cmd(win, w + " configure -text {" + page + "/" + string indexed + "}");
		cmd(win, "update");
	}
}

handlerproc(book: ref Book, evch: chan of string, exitedch: chan of int, pageprogress: chan of string)
{
	win := book.win;
	newplace(book, pageprogress);
	hist, fhist: list of ref Bookmark;
	cmd(win, "update");
	for (;;) {
		(w, c) := splitword(<-evch);
		if (Doprofile)
			profile->start();
#sys->print("event '%s' '%s'\n", w, c);
		(olditem, oldpage) := (book.item, book.page);
		case w {
		"exit" =>
			book.show(nil);		# force annotations to be written out.
			exitedch <-= 1;
			exit;
		"forward" =>
			book.forward();
		"back" =>
			book.back();
		"up" =>
			if (hist != nil) {
				bm := book.mark();
				book.goto(hd hist);
				(hist, fhist) = (tl hist, bm :: fhist);
			}
		"down" =>
			if (fhist != nil) {
				bm := book.mark();
				book.goto(hd fhist);
				(hist, fhist) = (bm :: hist, tl fhist);
			}
		"goto" =>
			(hist, fhist) = (book.mark() :: hist, nil);
			e := book.gotolink(c);
			if (e != nil)
				notice("error getting link: " + e);

		"ds" =>			# an event from a datasource-created widget
			if (book.d == nil) {
				oops("stray event 'ds " + c + "'");
				break;
			}
			event := book.d.datasrc.event(c);
			if (event == nil) {
				oops(sys->sprint("nil event on 'ds %s'", c));
				break;
			}
			pick ev := event {
			Link =>
				if (ev.url != nil) {
					(hist, fhist) = (book.mark() :: hist, nil);
					e := book.gotolink(ev.url);
					if (e != nil)
						notice("error getting link: " + e);
				}
			Texthit =>
				a := ref Annotation(ev.fileoffset, nil);
				spawn excessevents(evch);
				editannotation(win, a);
				evch <-= nil;
				book.d.addannotation(a);
			}
		"annotclick" =>
			a := book.d.getannotation(int c);
			if (a == nil) {
				notice("cannot find annotation at " + c);
				break;
			}
			editannotation(win, a);
			book.d.updateannotation(a);
		"annot" =>
			book.showannotations(int cmd(win, "variable annot"));
		* =>
			oops(sys->sprint("unknown event  '%s' '%s'", w, c));
		}
		if (olditem != book.item || oldpage != book.page)
			newplace(book, pageprogress);
		cmd(win, "update");
		cmd(win, "focus .");
		if (Doprofile)
			profile->stop();
	}
}

excessevents(evch: chan of string)
{
	while ((s := <-evch) != nil)
		oops("excess: " + s);
}

newplace(book: ref Book, pageprogress: chan of string)
{
	pageprogress <-= book.item.id + "." + string (book.page + 1);
	tkclient->settitle(book.win, book.title());
}

editannotation(pwin: ref Tk->Toplevel, annot: ref Annotation)
{
	(win, ctlchan) := tkclient->toplevel(gctxt,
			"-x " + cmd(pwin, ". cget -actx") +
			" -y " + cmd(pwin, ". cget -acty"), "Annotation", Tkclient->Appl);
	cmd(win, "scrollbar .s -orient vertical -command {.t yview}");
	cmd(win, "text .t -yscrollcommand {.s set}");
	cmd(win, "pack .s -side left -fill y");
	cmd(win, "pack .t -side top -fill both -expand 1");
	cmd(win, "pack propagate . 0");
	cmd(win, ". configure -width " + cmd(pwin, ". cget -width"));
	cmd(win, ".t insert end '" + annot.text);
	cmd(win, "update");
	# XXX tk bug forces us to do this here rather than earlier
	cmd(win, "focus .t");
	cmd(win, "update");
	tkclient->onscreen(win, nil);
	tkclient->startinput(win, "kbd"::"ptr"::nil);
	for (;;) alt {
	c := <-win.ctxt.kbd =>
		tk->keyboard(win, c);
	c := <-win.ctxt.ptr =>
		tk->pointer(win, *c);
	c := <-win.ctxt.ctl or
	c = <-win.wreq or
	c = <-ctlchan =>
		case c {
		"task" =>
			cmd(pwin, ". unmap");
			tkclient->wmctl(win, c);
			cmd(pwin, ". map");
			cmd(win, "raise .");
			cmd(win, "update");
		"exit" =>
			annot.text = trim(cmd(win, ".t get 1.0 end"));
			return;
		* =>
			tkclient->wmctl(win, c);
		}
	}
}

warningproc(c: chan of (Xml->Locator, string))
{
	for (;;) {
		(loc, msg) := <-c;
		if (msg == nil)
			break;
		warning(sys->sprint("%s:%d: %s", loc.systemid, loc.line, msg));
	}
}

openpackage(f: string): (ref OEBpackage->Package, string)
{
	(pkg, e) := oebpackage->open(f, warningch);
	if (pkg == nil)
		return (nil, e);
	nmissing := pkg.locate();
	if (nmissing > 0)
		warning(string nmissing + " items missing from manifest");
	for (i := pkg.manifest; i != nil; i = tl i)
		(hd i).file = cleanname((hd i).file);
	return (pkg, nil);
}

blankbook: Book;
Book.new(f: string, win: ref Tk->Toplevel, w: string, evch: string, size: Point,
			indexprogress: chan of int): (ref Book, string)
{
	(pkg, e) := openpackage(f);
	if (pkg == nil)
		return (nil, e);
	# give section numbers to all the items in the manifest.
	# items in the spine are named sequentially;
	# other items are given letters corresponding to their order in the manifest.
	for (items := pkg.manifest; items != nil; items = tl items)
		(hd items).id = nil;
	i := 1;
	for (items = pkg.spine; items != nil; items = tl items)
		(hd items).id = string i++;
	i = 0;
	for (items = pkg.manifest; items != nil; items = tl items) {
		if ((hd items).id == nil) {
			c := 'A';
			if (i >= 26)
				c = 'α';
			(hd items).id = sys->sprint("%c", c + i);
			i++;
		}
	}
	fallbacks: list of (string, string);
	for (items = pkg.manifest; items != nil; items = tl items) {
		item := hd items;
		if (item.fallback != nil)
			fallbacks = (item.file, item.fallback.file) :: fallbacks;
	}

	book := ref blankbook;
	book.win = win;
	book.evch = evch;
	book.size = size;
	book.w = w;
	book.pkg = pkg;
	book.sequence = pkg.spine;
	book.fallbacks = fallbacks;
	book.indexprogress = indexprogress;

	cmd(win, "frame " + w + " -bg white");

	if (book.sequence != nil) {
		book.show(hd book.sequence);
		if (book.d != nil)
			book.page = book.d.goto(0);
	}
	return (book, nil);
}

Book.title(book: self ref Book): string
{
	if (book.d != nil)
		return book.d.title();
	return nil;
}

Book.mark(book: self ref Book): ref Bookmark
{
	if (book.d != nil)
		return ref Bookmark(book.item, book.page);
	return nil;
}

Book.goto(book: self ref Book, m: ref Bookmark)
{
	if (m != nil) {
		book.show(m.item);
		book.gotopage(m.page);
	}
}

Book.gotolink(book: self ref Book, href: string): string
{
	fromfile: string;
	if (book.item != nil)
		fromfile = book.item.file;
	(u, err) := makerelativeurl(fromfile, href);
	if (u == nil)
		return err;
	if (book.d == nil || book.item.file != u.path) {
		for (i := book.pkg.manifest; i != nil; i = tl i)
			if ((hd i).file == u.path)
				break;
		if (i == nil)
			return "item '" + u.path + "' not found in manifest";
		book.show(hd i);
	}
	if (book.d != nil) {
		if (u.frag != nil) {
			if (book.d.gotolink(u.frag) == -1) {
				warning(sys->sprint("link '%s' not found in '%s'", u.frag, book.item.file));
				book.d.goto(0);
			} else
				book.page = book.d.pagenum;
		} else
			book.d.goto(0);
		book.page = book.d.pagenum;
	}
	return nil;	
}

makerelativeurl(fromfile: string, href: string): (ref ParsedUrl, string)
{
	dir := "";
	for(n := len fromfile; --n >= 0;) {
		if(fromfile[n] == '/') {
			dir = fromfile[0:n+1];
			break;
		}
	}
	u := url->makeurl(href);
	if(u.scheme != Url->FILE && u.scheme != Url->NOSCHEME)
		return (nil, sys->sprint("URL scheme %s not yet supported", url->schemes[u.scheme]));
	if(u.host != "localhost" && u.host != nil)
		return (nil, "non-local URLs not supported");
	path := u.path;
	if (path == nil)
		u.path = fromfile;
	else {
		if(u.pstart != "/")
			path = dir+path;	# TO DO: security
		(ok, d) := sys->stat(path);
		if(ok < 0)
			return (nil, sys->sprint("'%s': %r", path));
		u.path = path;
	}
	return (u, nil);
}

Book.gotopage(book: self ref Book, page: int)
{
	if (book.d != nil)
		book.page = book.d.goto(page);
}

#if (goto(next page)) doesn't move on) {
#	if (currentdocument is in sequence and it's not the last) {
#		close(document);
#		open(next in sequence)
#		goto(page 0)
#	}
#}
Book.forward(book: self ref Book)
{
	if (book.item == nil)
		return;
	if (book.d != nil) {
		n := book.d.goto(book.page + 1);
		if (n > book.page) {
			book.page = n;
			return;
		}
	}

	# can't move further on, so try for next in sequence.
	for (seq := book.sequence; seq != nil; seq = tl seq)
		if (hd seq == book.item)
			break;
	# not found in current sequence, or nothing following it: nowhere to go.
	if (seq == nil || tl seq == nil)
		return;
	book.show(hd tl seq);
	if (book.d != nil)
		book.page = book.d.goto(0);
}

Book.back(book: self ref Book)
{
	if (book.item == nil)
		return;
	if (book.d != nil) {
		n := book.d.goto(book.page - 1);
		if (n < book.page) {
			book.page = n;
			return;
		}
	}

	# can't move back, so try for previous in sequence
	prev: ref OEBpackage->Item;
	for (seq := book.sequence; seq != nil; (prev, seq) = (hd seq, tl seq))
		if (hd seq == book.item)
			break;

	# not found in current sequence, or no previous: nowhere to go
	if (seq == nil || prev == nil)
		return;

	book.show(prev);
	if (book.d != nil)
		book.page = book.d.goto(LASTPAGE);
}

Book.show(book: self ref Book, item: ref OEBpackage->Item)
{
	if (book.item == item)
		return;
	if (book.d != nil) {
		book.d.writeannotations();
		book.d.index.stop();
		cmd(book.win, "destroy " + book.d.w);
		book.d = nil;
	}
	if (item == nil)
		return;

	(d, e) := Document.new(item,  book.fallbacks, book.win, book.w + ".d", book.size, book.evch, book.indexprogress);
	if (d == nil) {
		notice(sys->sprint("cannot load item %s: %s", item.href, e));
		return;
	}
	d.showannotations(book.showannot);
	cmd(book.win, "pack " + book.w + ".d -fill both");
	book.page = -1;
	book.d = d;
	book.item = item;
}

Book.showannotations(book: self ref Book, showannot: int)
{
	book.showannot = showannot;
	if (book.d != nil)
		book.d.showannotations(showannot);
}

#actions:
#	goto link
#		if (link is to current document) {
#			goto(link)
#		} else {
#			close(document)
#			open(linked-to document)
#			goto(link);
#		}
#
#	next page
#		if (goto(next page)) doesn't move on) {
#			if (currentdocument is in sequence and it's not the last) {
#				close(document);
#				open(next in sequence)
#				goto(page 0)
#			}
#		}
#
#	previous page
#		if (page > 0) {
#			goto(page - 1);
#		} else {
#			if (currentdocument is in sequence and it's not the first) {
#				close(document)
#				open(previous in sequence)
#				goto(last page)
#			}

displayannotation(d: ref Document, r: Rect, annot: ref Annotation)
{
	tag := "o" + string annot.fileoffset;
	(win, w) := (d.p.win, d.p.w);
	a := cmd(win, w + " create text 0 0 -anchor nw -tags {annot " + tag + "}" +
			" -width " + Annotationwidth +
			" -text '" + annot.text);
	er := s2r(cmd(win, w + " bbox " + a));
	delta := er.min;

	# desired rectangle for text entry box
	er = Rect((r.min.x - Spikeradius, r.max.y), (r.min.x - Spikeradius + er.dx(), r.max.y + er.dy()));
	# make sure it's on screen
	if (er.max.x > d.size.x)
		er = er.subpt((er.max.x - d.size.x, 0));

	cmd(win, w + " create polygon" +
		" " + p2s(er.min) +
		" " + p2s((r.min.x - Spikeradius, er.min.y)) +
		" " + p2s(r.min) +
		" " + p2s((r.min.x + Spikeradius, er.min.y)) +
		" " + p2s((er.max.x, er.min.y)) +
		" " + p2s(er.max) +
		" " + p2s((er.min.x, er.max.y)) +
		" -fill yellow -tags {annot " + tag + "}");
	cmd(win, w + " coords " + a + " " + p2s(er.min.sub(delta)));
	cmd(win, w + " bind " + tag + " <Button-1> {" + w + " raise " + tag + "}");
	cmd(win, w + " bind " + tag + " <Double-Button-1> {send evch annotclick " + string annot.fileoffset + "}");
	cmd(win, w + " raise " + a);
}

badmodule(s: string)
{
	sys->fprint(stderr, "ebook: can't load %s: %r\n", s);
	raise "fail:load";
}

blankdoc: Document;
Document.new(i: ref OEBpackage->Item, fallbacks: list of (string, string),
		win: ref Tk->Toplevel, w: string, size: Point, evch: string,
		indexprogress: chan of int): (ref Document, string)
{
	if (i.mediatype != "text/x-oeb1-document")
		return (nil, "invalid mediatype: " + i.mediatype);
	if (i.file == nil)
		return (nil, "not found: " + i.missing);

	(datasrc, e) := Datasource.new(i.file, fallbacks, win, size.x, evch, warningch);
	if (datasrc == nil)
		return (nil, e);

	d := ref blankdoc;
	d.item = i;
	d.w = w;
	d.p = Page.new(win, w + ".p");
	d.datasrc = datasrc;
	d.pagenum = -1;
	d.size = size;
	d.indexprogress = indexprogress;
	d.index = Index.new(i, datasrc, size, 0, indexprogress);
	cmd(win, "frame " + w + " -width " + string size.x + " -height " + string size.y);
	cmd(win, "pack propagate " + w + " 0");
	cmd(win, "pack " + w + ".p -side top -fill both");
	d.annotations = readannotations(i.file + ".annot");
	d.showannot = 0;
	return (d, nil);
}

Document.fileoffset(nil: self ref Document): int
{
	# get nearest file offset corresponding to top of current page.
	# XXX
	return 0;
}

Document.gotooffset(nil: self ref Document, nil: int)
{
#	d.goto(d.index.pageforfileoffset(offset));
	# XXX
}

Document.title(d: self ref Document): string
{
	return d.datasrc.title;
}

Document.gotolink(d: self ref Document, name: string): int
{
	n := d.index.getlink(name);
	if (n != -1)
		return d.goto(n);
	return -1;
}

# this is much too involved for its own good.
Document.goto(d: self ref Document, n: int): int
{
	win := d.datasrc.win;
	pw := d.w + ".p";
	if (n == d.pagenum)
		return n;

	m: ref Mark;
	offset := -999;

	# before committing ourselves, make sure that the page exists.
	(n, (m, offset)) = d.index.get(n);
	if (m == nil || n == d.pagenum)
		return d.pagenum;

	b: Block;
	# remove appropriate element, in case we want to use it in the new page.
	if (n > d.pagenum)
		b = d.p.remove(1);
	else
		b = d.p.remove(0);

	# destroy the old page and make a new one.
	d.p.del();
	d.p = Page.new(win, pw);
	cmd(win, "pack " + pw + " -side top -fill both -expand 1");

	if (n == d.pagenum + 1 && d.lastmark != nil) {
if(debug)sys->print("page 1 forward\n");
		# sanity check:
		# if d.nextoffset or d.lastmark doesn't match the offset and mark we've obtained
		# fpr this page from the index, then the index is invalid, so reindex and recurse
		if (d.nextoffset != offset || !d.lastmark.eq(m)) {
			notice(sys->sprint("invalid index, reindexing; (index offset: %d, actually %d; mark: %d, actually: %d)\n",
				offset, d.nextoffset, d.lastmark.fileoffset(), m.fileoffset()));
			d.index.abort();
			d.index = Index.new(d.item, d.datasrc, d.size, 1, d.indexprogress);
			d.pagenum = -1;
			d.firstmark = d.endfirstmark = d.lastmark = d.endlastmark = nil;
			d.nextoffset = 0;
			return d.goto(n);
		}

		# if moving to the next page, we don't need to look up in the index;
		# just continue on from where we currently are, transferring the
		# last item on the current page to the first on the next.
		d.p.append(b);
		b.w = nil;
		d.p.scrollto(d.nextoffset);
		d.firstmark = d.lastmark;
		if (d.endlastmark != nil) {
			d.endfirstmark = d.endlastmark;
			d.datasrc.goto(d.endfirstmark);
		} else
			d.endfirstmark = d.datasrc.mark();
		(d.lastmark, nil) = fillpage(d.p, d.size, d.datasrc, d.firstmark, nil, nil);
		d.endlastmark = nil;
		offset = d.nextoffset;
	} else {
		d.p.scrollto(offset);
		if (n == d.pagenum - 1) {
if(debug)sys->print("page 1 back\n");
			# moving to the previous page: re-use the first item on
			# the current page as the last on the previous.
			newendfirst: ref Mark;
			if (!m.eq(d.firstmark)) {
				d.datasrc.goto(m);
				newendfirst = fillpageupto(d.p, d.datasrc, d.firstmark);
			} else
				newendfirst = d.endfirstmark;
			d.p.append(b);
			b.w = nil;
			(d.endfirstmark, d.lastmark, d.endlastmark) =
				(newendfirst, d.firstmark, d.endfirstmark);
		} else if (n > d.pagenum && m.eq(d.lastmark)) {
if(debug)sys->print("page forward, same start element\n");
			# moving forward: if new page starts with same element
			# that this page ends with, then reuse it.
			d.p.append(b);
			b.w = nil;
			if (d.endlastmark != nil) {
				d.datasrc.goto(d.endlastmark);
				d.endfirstmark = d.endlastmark;
			} else
				d.endfirstmark = d.datasrc.mark();
			
			(d.lastmark, nil) = fillpage(d.p, d.size, d.datasrc, m, nil, nil);
			d.endlastmark = nil;
		} else {
if(debug)sys->print("page goto arbitrary\n");
			# XXX could optimise when moving several pages back,
			# by limiting fillpage so that it stopped if it got to d.firstmark,
			# upon which we could re-use the first widget from the current page.
			d.datasrc.goto(m);
			(d.lastmark, d.endfirstmark) = fillpage(d.p, d.size, d.datasrc, m, nil, nil);
			if (d.endfirstmark == nil)
				d.endfirstmark = d.datasrc.mark();
			d.endlastmark = nil;
		}
		d.firstmark = m;
	}
	d.nextoffset = coverpartialline(d.p, d.datasrc, d.size);
	if (b.w != nil)
		cmd(win, "destroy " + b.w);
	d.pagenum = n;
	if (d.showannot)
		makeannotations(d, currentannotations(d));
if (debug)sys->print("page %d; firstmark is %d; yoffset: %d, nextoffset: %d; %d items\n", n, d.firstmark.fileoffset(), d.p.yorigin, d.nextoffset, d.p.count());
if(debug)sys->print("now at page %d, offset: %d, nextoffset: %d\n", n, d.p.yorigin, d.nextoffset);
	return n;
}

# fill up a page of size _size_ from d;
# m1 marks the start of the first item (already on the page).
# m2 marks the end of the item marked by m1.
# return (lastmark¸ endfirstmark)
# endfirstmark marks the end of the first item placed on the page;
# lastmark marks the start of the last item that overlaps
# the end of the page (or nil at eof).
fillpage(p: ref Page, size: Point, d: ref Datasource,
		m1, m2: ref Mark, linkch: chan of (string, string, string)): (ref Mark, ref Mark)
{
	endfirst: ref Mark;
	err: string;
	b: Block;
	while (p.maxy() < size.y) {
		m1 = d.mark();
		# if we've been round once and only once,
		# then m1 marks the end of the first element
		if (b.w != nil && endfirst == nil)
			endfirst = m1;
		(b, err) = d.next(linkch);
		if (err != nil) {
			notice(err);
			return (nil, endfirst);
		}
		if (b.w == nil)
			return (nil, endfirst);
		p.append(b);
	}
	if (endfirst == nil)
		endfirst = m2;
	return (m1, endfirst);
}

# fill a page up until a mark is reached (which is known to be on the page).
# return endfirstmark.
fillpageupto(p: ref Page, d: ref Datasource, upto: ref Mark): ref Mark
{
	endfirstmark: ref Mark;
	while (!d.atmark(upto)) {
		(b, err) := d.next(nil);
		if (b.w == nil) {
			notice("unexpected EOF");
			return nil;
		}
		p.append(b);
		if (endfirstmark == nil)
			endfirstmark = d.mark();
	}
	return endfirstmark;
}

# cover the last partial line on the page; return the y offset
# of the start of that line in the item containing it. (including top margin)
coverpartialline(p: ref Page, d: ref Datasource, size: Point): int
{
	# conceal any trailing partially concealed line.
	lastn := p.count() - 1;
	b := p.getblock(lastn);
	r := p.bbox(lastn);
	if (r.max.y >= size.y) {
		if (r.min.y < size.y) {
			offset := d.linestart(p.window(lastn), size.y - r.min.y);
			# guard against items larger than the whole page.
			if (r.min.y + offset <= 0)
				return size.y - r.min.y;
			p.conceal(r.min.y + offset);
			# if before first line, ensure that we get whole of top margin on next page.
			if (offset == 0) {
				p.conceal(size.y);
				return 0;
			}
			return offset + b.tmargin;
		} else {
			p.conceal(size.y);
			return 0;		# ensure that we get whole of top margin on next page.
		}
	}
	p.conceal(size.y);
	return r.dy() + b.tmargin;
}

Document.getannotation(d: self ref Document, fileoffset: int): ref Annotation
{
	annotations := d.annotations;
	for (i := 0; i < len annotations; i++)
		if (annotations[i].fileoffset == fileoffset)
			return annotations[i];
	return nil;
}

Document.showannotations(d: self ref Document, show: int)
{
	if (!show == !d.showannot)
		return;
	d.showannot = show;
	if (show) {
		makeannotations(d, currentannotations(d));
	} else {
		cmd(d.datasrc.win, d.p.w + " delete annot");
	}
}

Document.updateannotation(d: self ref Document, annot: ref Annotation)
{
	if (annot.text == nil)
		d.delannotation(annot);
	if (d.showannot) {
		# XXX this loses the z-order of the annotation
		cmd(d.datasrc.win, d.p.w + " delete o" + string annot.fileoffset);
		if (annot.text != nil)
			makeannotations(d, array[] of {annot});
	}
}

Document.delannotation(d: self ref Document, annot: ref Annotation)
{
	for (i := 0; i < len d.annotations; i++)
		if (d.annotations[i].fileoffset == annot.fileoffset)
			break;
	if (i == len d.annotations) {
		oops("trying to delete non-existent annotation");
		return;
	}
	d.annotations[i:] = d.annotations[i+1:];
	d.annotations[len d.annotations - 1] = nil;
	d.annotations = d.annotations[0:len d.annotations - 1];
}

Document.writeannotations(d: self ref Document): string
{
	if ((iob := bufio->create(d.item.file + ".annot", Sys->OWRITE, 8r666)) == nil)
		return sys->sprint("cannot create %s.annot: %r\n", d.item.file);
	a: list of string;
	for (i := 0; i < len d.annotations; i++)
		a = string d.annotations[i].fileoffset :: d.annotations[i].text :: a;
	iob.puts(str->quoted(a));
	iob.close();
	return nil;
}

Document.addannotation(d: self ref Document, a: ref Annotation)
{
	if (a.text == nil)
		return;
	annotations := d.annotations;
	for (i := 0; i < len annotations; i++)
		if (annotations[i].fileoffset >= a.fileoffset)
			break;
	if (i < len annotations && annotations[i].fileoffset == a.fileoffset) {
		oops("there's already an annotation there");
		return;
	}
	newa := array[len annotations + 1] of ref Annotation;
	newa[0:] = annotations[0:i];
	newa[i] = a;
	newa[i + 1:] = annotations[i:];
	d.annotations = newa;
	d.updateannotation(a);
}

makeannotations(d: ref Document, annots: array of ref Annotation)
{
	n := d.p.count();
	endy := d.p.visible();
	for (i := j := 0; i < n && j < len annots; ) {
		do {
			(ok, r) := d.datasrc.rectforfileoffset(d.p.window(i), annots[j].fileoffset);
			# XXX this assumes that y-origins at increasing offsets are monotonically increasing;
			# this ain't necessarily the case (think tables)
			if (!ok)
				break;
			r = r.addpt((0, d.p.bbox(i).min.y));
			if (r.min.y >= 0 && r.max.y <= endy)
				displayannotation(d, d.p.canvasr(r), annots[j]);
			j++;
		} while (j < len annots);
		i++;
	}
}

# get all annotations on current page, arranged in fileoffset order.
currentannotations(d: ref Document): array of ref Annotation
{
	if (d.firstmark == nil)
		return nil;
	o1 := d.firstmark.fileoffset();
	o2: int;
	if (d.endlastmark != nil)
		o2 = d.endlastmark.fileoffset();
	else
		o2 = d.datasrc.fileoffset();
	annotations := d.annotations;
	for (i := 0; i < len annotations; i++)
		if (annotations[i].fileoffset >= o1)
			break;
	a1 := i;
	for (; i < len annotations; i++)
		if (annotations[i].fileoffset > o2)
			break;
	return annotations[a1:i];
}

readannotations(f: string): array of ref Annotation
{
	s: string;
	if ((iob := bufio->open(f, Sys->OREAD)) == nil)
		return nil;
	while ((c := iob.getc()) >= 0)
		s[len s] = c;
	a := str->unquoted(s);
	n := len a / 2;
	annotations := array[n] of ref Annotation;
	for (i := n - 1; i >= 0; i--) {
		annotations[i] = ref Annotation(int hd a, hd tl a);
		a = tl tl a;
	}
	return annotations;
}

Index.new(item: ref OEBpackage->Item, d:  ref Datasource, size: Point,
		force: int, indexprogress: chan of int): ref Index
{
	i := ref Index;
	i.rq = chan of (int, chan of (int, (ref Mark, int)));
	i.linkrq = chan of (string, chan of int);
	f := item.file + ".i";
	i.length = 0;
	(ok, sinfo) := sys->stat(item.file);
	if (ok != -1)
		i.length = int sinfo.length;
	if (!force) {
		indexf := bufio->open(f, Sys->OREAD);
		if (indexf != nil) {
			(pages, links, err) := readindex(indexf, i.length, size, d);
			indexprogress <-= len pages;
			if (err != nil)
				warning(sys->sprint("cannot read index file %s: %s", f, err));
			else {
				spawn preindexeddealerproc(i.rq, i.linkrq, pages, links);
				return i;
			}
		}
	}
#sys->print("reindexing %s\n", f);
	i.d = d.copy();
	i.size = size;
	i.f = f;
	i.indexed = chan of (array of (ref Mark, int), ref Links);
	spawn indexproc(i.d, size,
		c := chan of (ref Mark, int),
		linkch := chan of string);
	spawn indexdealerproc(i.f, c, i.rq, i.linkrq, chan of (int, chan of int), linkch, i.indexed, indexprogress);
#	i.get(LASTPAGE);
	return i;
}

Index.abort(i: self ref Index)
{
	i.rq <-= (0, nil);
	# XXX kill off old indexing proc too.
}

Index.stop(i: self ref Index)
{
	if (i.indexed != nil) {
		# wait for indexing to complete, so that we can write it out without interruption.
		(pages, links) := <-i.indexed;
		writeindex(i.d, i.length, i.size, i.f, pages, links);
		
	}
	i.rq <-= (0, nil);
}

preindexeddealerproc(rq: chan of (int, chan of (int, (ref Mark, int))), linkrq: chan of (string, chan of int),
		pages: array of (ref Mark, int), links: ref Links)
{
	for (;;) alt {
	(n, reply) := <-rq =>
		if (reply == nil)
			exit;
		if (n < 0)
			n = 0;
		else if (n >= len pages)
			n = len pages - 1;
		# XXX are we justified in assuming there's at least one page?
		reply <-= (n, pages[n]);
	(name, reply) := <-linkrq =>
		reply <-= links.get(name);
	}
}
		
readindex(indexf: ref Iobuf, length: int, size: Point, d: ref Datasource): (array of (ref Mark, int), ref Links, string)
{
	# n pages
	s := indexf.gets('\n');
	(n, toks) := sys->tokenize(s, " ");
	if (n != 2 || hd tl toks != "pages\n" || int hd toks < 1)
		return (nil, nil, "invalid index file");
	npages := int hd toks;

	# size x y
	s = indexf.gets('\n');
	(n, toks) = sys->tokenize(s, " ");
	if (n != 3 || hd toks != "size")
		return (nil, nil, "invalid index file");
	if (int hd tl toks != size.x || int hd tl tl toks != size.y)
		return (nil, nil, "index for different sized window");
	
	# length n
	s = indexf.gets('\n');
	(n, toks) = sys->tokenize(s, " ");
	if (n != 2 || hd toks != "length")
		return (nil, nil, "invalid index file");
	if (int hd tl toks != length)
		return (nil, nil, "index for file of different length");
	
	pages := array[npages] of (ref Mark, int);
	for (i := 0; i < npages; i++) {
		ms := indexf.gets('\n');
		os := indexf.gets('\n');
		if (ms == nil || os == nil)
			return (nil, nil, "premature EOF on index");
		(m, o) := (d.str2mark(ms), int os);
		if (m == nil)
			return (nil, nil, "invalid mark");
		pages[i] = (m, o);
	}
	(links, err) := Links.read(indexf);
	if (links == nil)
		return (nil, nil, "readindex: " + err);
	return (pages, links, nil);
}

# index format:
# %d pages
# size %d %d
# length %d
# page0mark
# page0yoffset
# page1mark
# ....
# linkname pagenum
# ...
writeindex(d: ref Datasource, length: int, size: Point, f: string, pages: array of (ref Mark, int), links: ref Links)
{
	indexf := bufio->create(f, Sys->OWRITE, 8r666);
	if (indexf == nil) {
		notice(sys->sprint("cannot create index '%s': %r", f));
		return;
	}
	indexf.puts(string len pages + " pages\n");
	indexf.puts(sys->sprint("size %d %d\n", size.x, size.y));
	indexf.puts(sys->sprint("length %d\n", length));
	for (i := 0; i < len pages; i++) {
		(m, o) := pages[i];
		indexf.puts(d.mark2str(m));
		indexf.putc('\n');
		indexf.puts(string o);
		indexf.putc('\n');
	}
	links.write(indexf);
	indexf.close();
}

Index.get(i: self ref Index, n: int): (int, (ref Mark, int))
{
	c := chan of (int, (ref Mark, int));
	i.rq <-= (n, c);
	return <-c;
}

Index.getlink(i: self ref Index, name: string): int
{
	c := chan of int;
	i.linkrq <-= (name, c);
	return <-c;
}

# deal out indexes as and when they become available.
indexdealerproc(nil: string,
	c: chan of (ref Mark, int),
	rq: chan of (int, chan of (int, (ref Mark, int))),
	linkrq: chan of (string, chan of int),
	offsetrq: chan of (int, chan of int),
	linkch: chan of string,
	indexed: chan of (array of (ref Mark, int), ref Links),
	indexprogress: chan of int)
{
	pages := array[4] of (ref Mark, int);
	links := Links.new();
	rqs: list of (int, chan of (int, (ref Mark, int)));
	linkrqs: list of (string, chan of int);
	indexedch := chan of (array of (ref Mark, int), ref Links);
	npages := 0;
	finished := 0;
	for (;;) alt {
	(m, offset) := <-c =>
		if (m == nil) {
if(debug)sys->print("finished indexing; %d pages\n", npages);
			indexedch = indexed;
			pages = pages[0:npages];
			finished = 1;
			for (; linkrqs != nil; linkrqs = tl linkrqs)
				(hd linkrqs).t1 <-= -1;
		} else {
			if (npages == len pages)
				pages = (array[npages * 2] of (ref Mark, int))[0:] = pages;
			pages[npages++] = (m, offset);
			indexprogress <-= npages;
		}
		r := rqs;
		for (rqs = nil; r != nil; r = tl r) {
			(n, reply) := hd r;
			if (n < npages)
				reply <-= (n, pages[n]);
			else if (finished)
				reply <-= (npages - 1, pages[npages - 1]);
			else
				rqs = hd r :: rqs;
		}
	(name, reply) := <-linkrq =>
		n := links.get(name);
		if (n != -1)
			reply <-= n;
		else if (finished)
			reply <-= -1;
		else
			linkrqs = (name, reply) :: linkrqs;
	(offset, reply) := <-offsetrq =>
		reply <-= -1;		# XXX fix it.
#		if (finished && (npages == 0 || offset >= pages[npages - 1].fileoffset
#		if (i := 0; i < npages; i++)

	(n, reply) := <-rq =>
		if (reply == nil)
			exit;
		if (n < 0)
			n = 0;
		if (n < npages)
			reply <-= (n, pages[n]);
		else if (finished)
			reply <-= (npages - 1, pages[npages - 1]);
		else
			rqs = (n, reply) :: rqs;
	name := <-linkch =>
		links.put(name, npages - 1);
		r := linkrqs;
		for (linkrqs = nil; r != nil; r = tl r) {
			(rqname, reply) := hd r;
			if (rqname == name)
				reply <-= npages - 1;
			else
				linkrqs = hd r :: linkrqs;
		}
	indexedch <-= (pages, links) =>
		;
	}
}

# accumulate links temporarily while filling a page.
linkproc(linkch: chan of (string, string, string),
		terminate: chan of int,
		reply: chan of list of (string, string, string))
{
	links: list of (string, string, string);
	for (;;) {
		alt {
		<-terminate =>
			exit;
		(name, w, where) := <-linkch =>
			if (name != nil) {
				links = (name, w, where) :: links;
			} else {
				reply <-= links;
				links = nil;
			}
		}
	}
}

# generate index values for each page and send them on
# to indexdealerproc to be served up on demand.
indexproc(d: ref Datasource, size: Point, c: chan of (ref Mark, int),
		linkpagech: chan of string)
{
	spawn linkproc(linkch := chan of (string, string, string),
			terminate := chan of int,
			reply := chan of list of (string, string, string));
	win := d.win;
	p := Page.new(win, ".ip");

	mark := d.mark();
	c <-= (mark, 0);

	links: list of (string, string, string);	# (linkname, widgetname, tag)
	for (;;) {
startoffset := mark.fileoffset();
		(mark, nil) = fillpage(p, size, d, mark, nil, linkch);

		offset := coverpartialline(p, d, size);
if (debug)sys->print("page index %d items starting at %d, nextyoffset: %d\n", p.count(), startoffset, offset);
		linkch <-= (nil, nil, nil);
		for (l := <-reply; l != nil; l = tl l)
			links = hd l :: links;
		links = sendlinks(p, size, d, links, linkpagech);
		if (mark == nil)
			break;
		c <-= (mark, offset);
		b := p.remove(1);
		p.del();
		p = Page.new(win, ".ip");
		p.append(b);
		p.scrollto(offset);
	}
	p.del();
	terminate <-= 1;
	c <-= (nil, 0);
}

# send down ch the name of all the links that reside on the current page.
# return any links that were not on the current page.
sendlinks(p: ref Page, nil: Point, d: ref Datasource,
	links: list of (string, string, string), ch: chan of string): list of (string, string, string)
{
	nlinks: list of (string, string, string);
	vy := p.visible();
	for (; links != nil; links = tl links) {
		(name, w, where) := hd links;
		r := p.bboxw(w);
		y := r.min.y + d.linkoffset(w, where);
		if (y < vy)
			ch <-= name;
		else
			nlinks = hd links :: nlinks;
	}
	return nlinks;
}

Links: adt {
	a: array of list of (string, int);
	new: fn(): ref Links;
	read: fn(iob: ref Iobuf): (ref Links, string);
	get:	fn(l: self ref Links, name: string): int;
	put:	fn(l: self ref Links, name: string, pagenum: int);
	write: fn(l: self ref Links, iob: ref Iobuf);
};

Links.new(): ref Links
{
	return ref Links(array[31] of list of (string, int));
}

Links.write(l: self ref Links, iob: ref Iobuf)
{
	for (i := 0; i < len l.a; i++) {
		for (ll := l.a[i]; ll != nil; ll = tl ll) {
			(name, page) := hd ll;
			iob.puts(sys->sprint("%s %d\n", name, page));
		}
	}
}

Links.read(iob: ref Iobuf): (ref Links, string)
{
	l := Links.new();
	while ((s := iob.gets('\n')) != nil) {
		(n, toks) := sys->tokenize(s, " ");
		if (n != 2)
			return (nil, "expected 2 words, got " + string n);
		l.put(hd toks, int hd tl toks);
	}
	return (l, nil);
}

Links.get(l: self ref Links, name: string): int
{
	for (ll := l.a[hashfn(name, len l.a)]; ll != nil; ll = tl ll)
		if ((hd ll).t0 == name)
			return (hd ll).t1;
	return -1;
}

Links.put(l: self ref Links, name: string, pageno: int)
{
	v := hashfn(name, len l.a);
	l.a[v] = (name, pageno) :: l.a[v];
}

blankpage: Page;
Page.new(win: ref Tk->Toplevel, w: string): ref Page
{
	cmd(win, "canvas " + w + " -bg white");
	col := cmd(win, w + " cget -bg");
	cmd(win, w + " create rectangle -1 -1 -1 -1 -fill " + col + " -outline " + col + " -tags conceal");
	p := ref blankpage;
	p.win = win;
	p.w = w;
	setscrollregion(p);
	return p;
}

Page.del(p: self ref Page)
{
	n := p.count();
	for (i := 0; i < n; i++)
		cmd(p.win, "destroy " + p.window(i));
	cmd(p.win, "destroy " + p.w);
}

# convert a rectangle as returned by Page.window()
# to a rectangle in canvas coordinates
Page.canvasr(p: self ref Page, r: Rect): Rect
{
	return r.addpt((0, p.yorigin));
}

Pagewidth: con 5000;		# max page width

# create an area on the page, from y downwards.
Page.conceal(p: self ref Page, y: int)
{
	cmd(p.win, p.w + " coords conceal 0 " + string (y + p.yorigin) +
			" " + string Pagewidth +
			" " + string p.height);
	cmd(p.win, p.w + " raise conceal");
}

# return vertical space in the page that's not concealed.
Page.visible(p: self ref Page): int
{
	r := s2r(cmd(p.win, p.w + " coords conceal"));
	return r.min.y - p.yorigin;
}
	
Page.window(p: self ref Page, n: int): string
{
	return cmd(p.win, p.w + " itemcget n" + string (n + p.min) + " -window");
}

Page.append(p: self ref Page, b: Block)
{
	h := int cmd(p.win, b.w + " cget -height") + 2 * int cmd(p.win, b.w + " cget -bd");

	n := p.max++;
	y := p.height;

	gap := p.bmargin;
	if (b.tmargin > gap)
		gap = b.tmargin;

	cmd(p.win, p.w + " create window 0 " + string (y + gap) + " -window " + b.w +
			" -tags {elem" +
				" n" + string n +
				" t" + string b.tmargin +
				" b" + string  b.bmargin +
				"} -anchor nw");

	p.height += h + gap;
	p.bmargin = b.bmargin;
	setscrollregion(p);
}

Page.remove(p: self ref Page, atend: int): Block
{
	if (p.min == p.max)
		return Block(nil, 0, 0);
	n: int;
	if (atend) 
		n = --p.max;
	else
		n = p.min++;

	b := getblock(p, n);
	h := int cmd(p.win, b.w + " cget -height") + 2 * int cmd(p.win, b.w + " cget -bd");

	if (p.min == p.max) {
		p.bmargin = 0;
		h += b.tmargin;
	} else if (atend) {
		c := getblock(p, p.max - 1);
		if (c.bmargin > b.tmargin)
			h += c.bmargin;
		else
			h += b.tmargin;
		p.bmargin = c.bmargin;
	} else {
		c := getblock(p, p.min);
		if (c.tmargin > b.bmargin)
			h += c.tmargin;
		else
			h += b.bmargin;
		h += b.tmargin;
	}

	p.height -= h;
	cmd(p.win, p.w + " delete n" + string n);
	if (!atend)
		cmd(p.win, p.w + " move elem 0 -" + string h);
	setscrollregion(p);

	return b;
}

getblock(p: ref Page, n: int): Block
{
	tag := "n" + string n;
	b := Block(cmd(p.win, p.w + " itemcget " + tag + " -window"), 0, 0);
	(nil, toks) := sys->tokenize(cmd(p.win, p.w + " gettags " + tag), " ");
	for (; toks != nil; toks = tl toks) {
		c := (hd toks)[0];
		if (c == 't')
			b.tmargin = int (hd toks)[1:];
		else if (c == 'b')
			b.bmargin = int (hd toks)[1:];
	}
	return b;
}

# scroll the page so y is at the top left visible in the canvas widget.
Page.scrollto(p: self ref Page, y: int)
{
	p.yorigin = y;
	setscrollregion(p);
	cmd(p.win, p.w + " yview moveto 0");
}

# return max y coord of bottom of last item, where y=0
# is at top visible part of canvas.
Page.maxy(p: self ref Page): int
{
	return p.height - p.yorigin;
}

Page.count(p: self ref Page): int
{
	return p.max - p.min;
}

# XXX what should bbox do about margins? ignoring seems ok for the moment.
Page.bbox(p: self ref Page, n: int): Rect
{
	if (p.count() == 0)
		return ((0, 0), (0, 0));
	tag := "n" + string (n + p.min);
	return s2r(cmd(p.win, p.w + " bbox " + tag)).subpt((0, p.yorigin));
}

Page.bboxw(p: self ref Page, w: string): Rect
{
	# XXX inefficient algorithm. do better later.
	n := p.count();
	for (i := 0; i < n; i++)
		if (p.window(i) == w)
			return p.bbox(i);
	sys->fprint(sys->fildes(2), "ebook: bboxw requested for invalid window %s\n", w);
	return ((0, 0), (0, 0));
}

Page.getblock(p: self ref Page, n: int): Block
{
	return getblock(p, n + p.min);
}

printpage(p: ref Page)
{
	n := p.count();
	for (i := 0; i < n; i++) {
		r := p.bbox(i);
		dx := r.max.sub(r.min);
		sys->print("	%d: %s %d %d +%d +%d\n", i, p.window(i), 
			r.min.x, r.min.y, dx.x, dx.y);
	}
	sys->print("	conceal: %s\n", cmd(p.win, p.w + " bbox conceal"));
}

setscrollregion(p: ref Page)
{
	cmd(p.win, p.w + " configure -scrollregion {0 " + string p.yorigin + " " + string Pagewidth + " " + string p.height + "}");
}

notice(s: string)
{
	sys->print("notice: %s\n", s);
}

warning(s: string)
{
	notice("warning: " + s);
}

oops(s: string)
{
	sys->print("oops: %s\n", s);
}

cmd(win: ref Tk->Toplevel, s: string): string
{
#	sys->print("%ux	%s\n", win, s);
	r := tk->cmd(win, s);
#	sys->print("	-> %s\n", r);
	if (len r > 0 && r[0] == '!') {
		sys->fprint(stderr, "ebook: error executing '%s': %s\n", s, r);
		raise "tk error";
	}
	return r;
}

s2r(s: string): Rect
{
	(n, toks) := sys->tokenize(s, " ");
	if (n != 4) {
		sys->print("'%s' is not a rectangle!\n", s);
		raise "bad conversion";
	}
	r: Rect;
	(r.min.x, toks) = (int hd toks, tl toks);
	(r.min.y, toks) = (int hd toks, tl toks);
	(r.max.x, toks) = (int hd toks, tl toks);
	(r.max.y, toks) = (int hd toks, tl toks);
	return r;
}

p2s(p: Point): string
{
	return string p.x + " " + string p.y;
}

r2s(r: Rect): string
{
	return string r.min.x + " " + string r.min.y + " " +
			string r.max.x + " " + string r.max.y;
}
	
trim(s: string): string
{
	for (i := len s - 1; i >= 0; i--)
		if (s[i] != ' ' && s[i] != '\t' && s[i] != '\n')
			break;
	return s[0:i+1];
}

splitword(s: string): (string, string)
{
	for (i := 0; i < len s; i++)
		if (s[i] == ' ')
			return (s[0:i], s[i + 1:]);
	return (s, nil);
}

# compress ../ references and do other cleanups
cleanname(name: string): string
{
	# compress multiple slashes
	n := len name;
	for(i:=0; i<n-1; i++)
		if(name[i]=='/' && name[i+1]=='/'){
			name = name[0:i]+name[i+1:];
			--i;
			n--;
		}
	#  eliminate ./
	for(i=0; i<n-1; i++)
		if(name[i]=='.' && name[i+1]=='/' && (i==0 || name[i-1]=='/')){
			name = name[0:i]+name[i+2:];
			--i;
			n -= 2;
		}
	found: int;
	do{
		# compress xx/..
		found = 0;
		for(i=1; i<=n-3; i++)
			if(name[i:i+3] == "/.."){
				if(i==n-3 || name[i+3]=='/'){
					found = 1;
					break;
				}
			}
		if(found)
			for(j:=i-1; j>=0; --j)
				if(j==0 || name[j-1]=='/'){
					i += 3;		# character beyond ..
					if(i<n && name[i]=='/')
						++i;
					name = name[0:j]+name[i:];
					n -= (i-j);
					break;
				}
	} while(found);
	# eliminate trailing .
	if(n>=2 && name[n-2]=='/' && name[n-1]=='.')
		--n;
	if(n == 0)
		return ".";
	if(n != len name)
		name = name[0:n];
	return name;
}


hashfn(s: string, n: int): int
{
	h := 0;
	m := len s;
	for(i:=0; i<m; i++){
		h = 65599*h+s[i];
	}
	return (h & 16r7fffffff) % n;
}
