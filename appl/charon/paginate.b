implement Paginate;

include "common.m";
include "print.m";
include "paginate.m";

sys: Sys;
print: Print;
L: Layout;
D: Draw;

Frame, Lay, Line, Control: import Layout;
Docinfo: import Build;
Image, Display, Rect, Point: import D;
Item: import Build;
MaskedImage: import CharonUtils;

disp: ref Display;
p0: Point;
nulimg: ref Image;

DPI: con 110;

init(layout: Layout, draw: Draw, display: ref Draw->Display): string
{
	sys = load Sys Sys->PATH;
	L = layout;
	D = draw;
	disp = display;
	if (L == nil || D == nil || disp == nil)
		return "bad args";
	print = load Print Print->PATH;
	if (print == nil)
		return sys->sprint("cannot load module %s: %r", Print->PATH);
	print->init();
#nullfd := sys->open("/dev/null", Sys->OWRITE);
#print->set_printfd(nullfd);
	p0 = Point(0, 0);
	nulimg = disp.newimage(((0, 0), (1, 1)), 3, 0, 0);
	return nil;
}

paginate(frame: ref Layout->Frame, orient: int, pnums, cancel: chan of int, result: chan of (string, ref Pageset))
{
	pidc := chan of int;
	spawn watchdog(pidc, cancel, nil, sys->pctl(0, nil));
	watchpid := <- pidc;

	if (frame.kids != nil) {
		result <-= ("cannot print frameset", nil);
		kill(watchpid);
		return;
	}

	defp := print->get_defprinter();
	if (defp == nil) {
		result <-= ("no default printer", nil);
		kill(watchpid);
		return;
	}

	# assuming printer's X & Y resolution are the same
	if (orient == PORTRAIT)
		defp.popt.orientation = Print->PORTRAIT;
	else
		defp.popt.orientation = Print->LANDSCAPE;
	(dpi, pagew, pageh) := print->get_size(defp);
	pagew = (DPI * pagew)/dpi;
	pageh = (DPI * pageh)/dpi;

	pfr := copyframe(frame);
	pr := Rect(p0, (pagew, pageh));
	pfr.r = pr;
	pfr.cr = pr;
	pfr.viewr = pr;
	l := pfr.layout;
	L->relayout(pfr, l, pagew, l.just);
	maxy := l.height + l.margin; # don't include bottom margin
	prctxt := ref Layout->Printcontext;
	pfr.prctxt = prctxt;
	pfr.cim = nulimg;
	pnum := 1;
	startys : list of int;

	for (y := 0; y < maxy;) {
		startys = y :: startys;
		pnums <-= pnum++;
		endy := y + pageh;
		prctxt.endy = pageh;
		pfr.viewr.min.y = y;
		pfr.viewr.max.y = endy;
		L->drawall(pfr);
		y += prctxt.endy;
	}

	# startys are in reverse order
	ys : list of int;
	for (; startys != nil; startys = tl startys)
		ys = hd startys :: ys;

	pageset := ref Pageset(defp, pfr, ys);
	result <-= (nil, pageset);
	kill(watchpid);
}

printpageset(pset: ref Pageset, pnums, cancel: chan of int)
{
	pidc := chan of int;
	stopdog := chan of int;
	spawn watchdog(pidc, cancel, stopdog, sys->pctl(0, nil));
	watchpid := <- pidc;

	frame := pset.frame;
	pageh := frame.cr.dy();
	white := disp.rgb2cmap(255, 255, 255);
	prctxt := frame.prctxt;
	l := frame.layout;
	maxy := l.height + l.margin; # don't include bottom margin
	maxy = max(maxy, pageh);
	pnum := 1;

	for (pages := pset.pages; pages != nil; pages = tl pages) {
		y := hd pages;
		if (y + pageh > maxy)
			pageh = maxy - y;
		frame.cr.max.y = pageh;
		frame.cim = disp.newimage(frame.cr, 3, 0, white);
		if (frame.cim == nil) {
			pnums <-= -1;
			kill(watchpid);
			return;
		}
		pnums <-= pnum++;
		endy := y + pageh;
		prctxt.endy = pageh;
		frame.viewr.min.y = y;
		frame.viewr.max.y = endy;
		L->drawall(frame);
		stopdog <-= 1;
#start := sys->millisec();
		if (print->print_image(pset.printer, disp, frame.cim, 100, cancel) == -1) {
			# cancelled
			kill(watchpid);
			return;
		}
		stopdog <-= 1;
#sys->print("PAGE %d: %dms\n", pnum -1, sys->millisec()-start);
	}
	pnums <-= -1;
	kill(watchpid);
}

watchdog(pidc, cancel, pause: chan of int, pid: int)
{
	pidc <-= sys->pctl(0, nil);
	if (pause == nil)
		pause = chan of int;
	for (;;) alt {
	<- cancel =>
		kill(pid);
		return;
	<- pause =>
		<- pause;
	}
}

kill(pid: int)
{
	sys->fprint(sys->open("/prog/" + string pid +"/ctl", Sys->OWRITE), "kill");
}

killgrp(pid: int)
{
	sys->fprint(sys->open("/prog/" + string pid +"/ctl", Sys->OWRITE), "killgrp");
}

max(a, b: int): int
{
	if (a > b)
		return a;
	return b;
}

copyframe(f: ref Frame): ref Frame
{

	zr := Draw->Rect(p0, p0);
	newf := ref Frame(
		-1,			# id
		nil,			# doc
		nil,			# src
		" PRINT FRAME ",	# name
		f.marginw,	# marginw
		f.marginh,	# marginh
		0,			# framebd
		Build->FRnoscroll,	# flags
		nil,			# layout - filled in below, needs this frame ref
		nil,			# sublays - filled in by geometry code
		0,			# sublayid
		nil,			# controls - filled in below, needs this frame ref
		0,			# controlid - filled in below
		nil,			# cim
		zr,			# r
		zr,			# cr
		zr,			# totalr
		zr,			# viewr
		nil,			# vscr
		nil,			# hscr
		nil,			# parent
		nil,			# kids
		0,			# animpid
		nil			# prctxt
	);

	newf.doc = copydoc(f, newf, f.doc);
	controls := array [len f.controls] of ref Control;
	for (i := 0; i < len controls; i++)
		controls[i] = copycontrol(f, newf, f.controls[i]);
	newf.layout = copylay(f, newf, f.layout);
	newf.controls = controls;
	newf.controlid = len controls;

	return newf;
}

copysublay(oldf, f: ref Frame, oldid:int): int
{
	if (oldid < 0)
		return -1;
	if (f.sublayid >= len f.sublays)
		f.sublays = (array [len f.sublays + 30] of ref Lay)[:] = f.sublays;
	id := f.sublayid++;
	lay := copylay(oldf, f, oldf.sublays[oldid]);
	f.sublays[id] = lay;
	return id;
}

copydoc(oldf, f : ref Frame, doc: ref Build->Docinfo): ref Docinfo
{
	background := copybackground(oldf, f, doc.background);
	newdoc := ref Build->Docinfo(
		nil,		#src
		nil,		#base
		nil,		#referrer
		nil,		#doctitle
		background,
		nil,		#backgrounditem
		doc.text, doc.link, doc.vlink, doc.alink,
		nil,		#target
		nil,		#refresh
		nil,		#chset
		nil,		#lastModified
		0,		#scripttype
		0,		#hasscripts
		nil,		#events
		0,		#evmask
		nil,		#kidinfo
		0,		#frameid
		nil,		#anchors
		nil,		#dests
		nil,		#forms
		nil,		#tables
		nil,		#maps
		nil		#images
	);
	return newdoc;
}

copylay(oldf, f: ref Frame, l: ref Lay): ref Lay
{
	start := copyline(oldf, f, nil, l.start);
	end := start;
	for (line := l.start.next; line != nil; line = line.next)
		end = copyline(oldf, f, end, line);

	newl := ref Lay(
		start,
		end,
		l.targetwidth,		# targetwidth
		l.width,		# width
		l.height,		# height
		l.margin,	# margin
		nil,		# floats - filled in by geometry code
		copybackground(oldf, f, l.background),
		l.just,
		Layout->Lchanged
	);
	start.flags = end.flags = byte 0;
	return newl;
}

copycontrol(oldf, f: ref Frame, ctl: ref Control): ref Control
{
	if (ctl == nil)
		return nil;

	pick c := ctl {
	Cbutton =>
		return ref Control.Cbutton(f, nil, c.r, c.flags, nil, c.pic, c.picmask, c.dpic, c.dpicmask, c.label, c.dorelief);
	Centry =>
		scr := copycontrol(oldf, f, c.scr);
		return ref Control.Centry(f, nil, c.r, c.flags, nil, scr, c.s, c.sel, c.left, c.linewrap, 0);
	Ccheckbox=>
		return ref Control.Ccheckbox(f, nil, c.r, c.flags, nil, c.isradio);
	Cselect =>
		scr := copycontrol(oldf, f, c.scr);
		options := (array [len c.options] of Build->Option)[:] = c.options;
		return ref Control.Cselect(f, nil, c.r, c.flags, nil, nil, scr, c.nvis, c.first, options);
	Clistbox =>
		hscr := copycontrol(oldf, f, c.hscr);
		vscr := copycontrol(oldf, f, c.vscr);
		options := (array [len c.options] of Build->Option)[:] = c.options;
		return ref Control.Clistbox(f, nil, c.r, c.flags, nil, hscr, vscr, c.nvis, c.first, c.start, c.maxcol, options, nil);
	Cscrollbar =>
		# do not copy ctl as this is set by those associated controls
		return ref Control.Cscrollbar(f, nil, c.r, c.flags, nil, c.top, c.bot, c.mindelta, c.deltaval, nil, c.holdstate);
	Canimimage =>
		bg := copybackground(oldf, f, c.bg);
		return ref Control.Canimimage(f, nil, c.r, c.flags, nil, c.cim, 0, 0, big 0, bg);
	Clabel =>
		return ref Control.Clabel(f, nil, c.r, c.flags, nil, c.s);
	* =>
		return nil;
	}
}

copyline(oldf, f: ref Frame, prev, l: ref Line): ref Line
{
	if (l == nil)
		return nil;
	cp := ref *l;
	items := copyitems(oldf, f, l.items);
	newl := ref Line (items, nil, prev, l.pos, l.width, l.height, l.ascent, Layout->Lchanged);
	if (prev != nil)
		prev.next = newl;
	return newl;
}

copyitems(oldf, f: ref Frame, items: ref Item): ref Item
{
	if (items == nil)
		return nil;
	item := copyitem(oldf, f, items);
	end := item;
	for (items = items.next; items != nil; items = items.next) {
		end.next = copyitem(oldf, f, items);
		end = end.next;
	}
	return item;
}

copyitem(oldf, f : ref Frame, item: ref Item): ref Item
{
	if (item == nil)
		return nil;
	pick it := item {
	Itext =>
		return ref Item.Itext(
			nil, it.width, it.height, it.ascent, 0, it.state, nil,
			it.s, it.fnt, it.fg, it.voff, it.ul);
	Irule =>
		return ref Item.Irule(
			nil, it.width, it.height, it.ascent, 0, it.state, nil,
			it.align, it.noshade, it.size, it.wspec);
	Iimage =>
		# need to copy the image to prevent
		# ongoing image fetches from messing up our layout
		ci := copycimage(it.ci);
		return ref Item.Iimage(
			nil, it.width, it.height, it.ascent, 0, it.state, nil,
			it.imageid, ci, it.imwidth, it.imheight, it.altrep,
			nil, it.name, -1, it.align, it.hspace, it.vspace, it.border);
	Iformfield =>
		return ref Item.Iformfield(
			nil, it.width, it.height, it.ascent, 0, it.state, nil,
			copyformfield(oldf, f, it.formfield)
		);
	Itable =>
		return ref Item.Itable(
			nil, it.width, it.height, it.ascent, 0, it.state, nil,
			copytable(oldf, f, it.table));
	Ifloat =>
		items := copyitem(oldf, f, it.item);
		return ref Item.Ifloat(
			nil, it.width, it.height, it.ascent, 0, it.state, nil,
			items, it.x, it.y, it.side, byte 0);
	Ispacer =>
		return ref Item.Ispacer(
			nil, it.width, it.height, it.ascent, 0, it.state, nil,
			it.spkind, it.fnt);
	* =>
		return nil;
	}
}

copycimage(ci: ref CharonUtils->CImage): ref CharonUtils->CImage
{
	if (ci == nil)
		return nil;
	mims : array of ref MaskedImage;
	if (len ci.mims > 0)
		# if len> 1 then animated, but we only want first frame
		mims = array [1] of {0 => ci.mims[0]};
	return ref CharonUtils->CImage(nil, nil, nil, 0, ci.width, ci.height, nil, mims, 0);
}

copyformfield(oldf, f: ref Frame, ff: ref Build->Formfield): ref Build->Formfield
{
	image := copyitem(oldf, f, ff.image);
	# should be safe to reference Option list
	newff := ref Build->Formfield(
		ff.ftype, 0, nil, ff.name, ff.value, ff.size, ff.maxlength, ff.rows,
		ff.cols, ff.flags, ff.options, image, ff.ctlid, nil, 0
	);
	return newff;
}

copytable(oldf, f: ref Frame, tbl: ref Build->Table): ref Build->Table
{
	nrow := tbl.nrow;
	ncol := tbl.ncol;
	caption_lay := copysublay(oldf, f, tbl.caption_lay);
	cols := (array [ncol] of Build->Tablecol)[:] = tbl.cols;
	rows := array [nrow] of ref Build->Tablerow;
	for (i := 0; i < nrow; i++) {
		r := tbl.rows[i];
		rows[i] = ref Build->Tablerow(nil, r.height, r.ascent, r.align, r.background, r.pos, r.flags);
	}

	cells : list of ref Build->Tablecell;
	grid := array [nrow] of {* => array [ncol] of ref Build->Tablecell};
	for (rix := 0; rix < nrow; rix++) {
		rowcells: list of ref Build->Tablecell = nil;
		for (colix := 0; colix < ncol; colix++) {
			cell := copytablecell(oldf, f, tbl.grid[rix][colix]);
			if (cell == nil)
				continue;
			grid[rix][colix] = cell;
			cells = cell :: cells;
			rowcells = cell :: rowcells;
		}
		# reverse the row cells;
		rcells : list of ref Build->Tablecell = nil;
		for (; rowcells != nil; rowcells = tl rowcells)
			rcells = hd rowcells :: rcells;
		rows[rix].cells = rcells;
	}

	# reverse the cells
	sllec: list of ref Build->Tablecell;
	for (; cells != nil; cells = tl cells)
		sllec = hd cells :: sllec;
	cells = sllec;

	return ref Build->Table(
		tbl.tableid,	# tableid
		nrow,		# nrow
		ncol,			# ncol
		len cells,		# ncell
		tbl.align,		# align
		tbl.width,		# width
		tbl.border,	# border
		tbl.cellspacing,	# cellspacing
		tbl.cellpadding,	# cellpadding
		tbl.background,	# background
		nil,			# caption
		tbl.caption_place,	# caption_place
		caption_lay,	# caption_lay
		nil,			# currows
		cols,			# cols
		rows,		# rows
		cells,		# cells
		tbl.totw,		# totw
		tbl.toth,		# toth
		tbl.caph,		# caph
		tbl.availw,	# availw
		grid,			# grid
		nil,			# tabletok
		Layout->Lchanged		# flags
	);
}

copytablecell(oldf, f: ref Frame, cell: ref Build->Tablecell): ref Build->Tablecell
{
	if (cell == nil)
		return nil;

	layid := copysublay(oldf, f, cell.layid);
	background := copybackground(oldf, f, cell.background);
	newcell := ref Build->Tablecell(
		cell.cellid,
		nil,	# content
		layid,
		cell.rowspan, cell.colspan, cell.align,
		cell.flags, cell.wspec, cell.hspec,
		background, cell.minw, cell.maxw,
		cell.ascent, cell.row, cell.col, cell.pos);
	return newcell;
}

copybackground(oldf, f: ref Frame, bg: Build->Background): Build->Background
{
	img := copyitem(oldf, f, bg.image);
	if (img != nil) {
		pick i := img {
		Iimage =>
			bg.image = i;
		}
	}
	return bg;
}
