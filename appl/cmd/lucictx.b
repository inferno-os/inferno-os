implement LuciCtx;

#
# lucictx - Context zone for Lucifer
#
# Receives a sub-Image from the WM tiler (lucifer) and renders the
# context zone into it.  Runs as an independent goroutine.
# Handles resource mounting/unmounting and catalog management.
#

include "sys.m";
	sys: Sys;

include "draw.m";
	draw: Draw;
	Font, Point, Rect, Image, Display, Screen, Pointer: import draw;

include "menu.m";

LuciCtx: module
{
	PATH: con "/dis/lucictx.dis";
	init: fn(img: ref Draw->Image, dsp: ref Draw->Display,
	         font: ref Draw->Font,
	         mountpt: string, actid: int,
	         mouse: chan of ref Draw->Pointer,
	         evch:  chan of string,
	         rsz:   chan of ref Draw->Image);
};

# Inline interface for loading tools9p
Tools9p: module {
	init: fn(ctxt: ref Draw->Context, args: list of string);
};

# --- Color constants ---
COLBG:		con int 16r080808FF;
COLACCENT:	con int 16rE8553AFF;
COLTEXT:	con int 16rCCCCCCFF;
COLTEXT2:	con int 16r999999FF;
COLDIM:		con int 16r444444FF;
COLLABEL:	con int 16r333333FF;
COLGREEN:	con int 16r44AA44FF;
COLYELLOW:	con int 16rAAAA44FF;
COLRED:		con int 16rAA4444FF;
COLPROGBG:	con int 16r1A1A1AFF;
COLPROGFG:	con int 16r3388CCFF;

# Resource mounting base
MNT_BASE: con "/tmp/veltro/mnt";

# --- ADTs ---

Resource: adt {
	path:	string;
	label:	string;
	rtype:	string;
	status:	string;
	via:	string;
	lastused: int;
};

Gap: adt {
	desc:	string;
	relevance: string;
};

BgTask: adt {
	label:	string;
	status:	string;
	progress: string;
};

CatalogEntry: adt {
	name:	string;
	desc:	string;
	rtype:	string;
	mntpath: string;
	dial:	string;
};

Attr: adt {
	key: string;
	val: string;
};

# --- Module-level state ---

stderr: ref Sys->FD;
mainwin: ref Image;
backbuf: ref Image;		# off-screen back buffer for double-buffered redraw
display_g: ref Display;
mainfont: ref Font;
mountpt_g: string;
actid_g := -1;

# Colors
bgcol: ref Image;
accentcol: ref Image;
textcol: ref Image;
text2col: ref Image;
dimcol: ref Image;
labelcol: ref Image;
greencol: ref Image;
yellowcol: ref Image;
redcol: ref Image;
progbgcol: ref Image;
progfgcol: ref Image;

menumod: Menu;
Popup: import menumod;

# Context state
resources: list of ref Resource;
gaps: list of ref Gap;
bgtasks: list of ref BgTask;
catalog: list of ref CatalogEntry;
avail_expanded := 1;
availhdrrect: Rect;

# Button rects (populated by drawcontext each frame)
plusrects: array of Rect;
nplusrects := 0;
minusrects: array of Rect;
nminusrects := 0;
ctxentryrects: array of Rect;
nctxentryrects := 0;

# --- init ---

init(img: ref Draw->Image, dsp: ref Draw->Display,
     font: ref Draw->Font,
     mountpt: string, actid: int,
     mouse: chan of ref Draw->Pointer,
     evch:  chan of string,
     rsz:   chan of ref Draw->Image)
{
	sys = load Sys Sys->PATH;
	draw = load Draw Draw->PATH;
	stderr = sys->fildes(2);

	mainwin = img;
	display_g = dsp;
	mainfont = font;
	mountpt_g = mountpt;
	actid_g = actid;

	# Create colors
	bgcol = dsp.color(COLBG);
	accentcol = dsp.color(COLACCENT);
	textcol = dsp.color(COLTEXT);
	text2col = dsp.color(COLTEXT2);
	dimcol = dsp.color(COLDIM);
	labelcol = dsp.color(COLLABEL);
	greencol = dsp.color(COLGREEN);
	yellowcol = dsp.color(COLYELLOW);
	redcol = dsp.color(COLRED);
	progbgcol = dsp.color(COLPROGBG);
	progfgcol = dsp.color(COLPROGFG);

	# Load menu module
	menumod = load Menu Menu->PATH;
	if(menumod != nil)
		menumod->init(display_g, mainfont);

	avail_expanded = 1;

	if(actid >= 0)
		loadcontext();

	redrawctx();

	# Context flash timer (animate activity indicator fade-out)
	spawn ctxtimer(evch);

	# Event loop
	prevbuttons := 0;
	for(;;) alt {
	p := <-mouse =>
		wasdown := prevbuttons;
		prevbuttons = p.buttons;
		# Button-1 just pressed
		if(p.buttons == 1 && wasdown == 0) {
			tabclicked := 0;
			# Available section heading toggle
			if(availhdrrect.max.x > availhdrrect.min.x &&
					availhdrrect.contains(p.xy)) {
				if(avail_expanded)
					avail_expanded = 0;
				else
					avail_expanded = 1;
				tabclicked = 1;
				redrawctx();
			}
			# [+] button: mount catalog entry
			if(!tabclicked) {
				for(pi := 0; pi < nplusrects; pi++) {
					if(plusrects[pi].contains(p.xy)) {
						j := 0;
						for(cl := catalog; cl != nil; cl = tl cl) {
							ce := hd cl;
							if(ce.mntpath == "") {
								if(j == pi) {
									mountresource(ce);
									tabclicked = 1;
									break;
								}
								j++;
							}
						}
						break;
					}
				}
			}
			# [-] button: unmount catalog entry
			if(!tabclicked) {
				for(pi := 0; pi < nminusrects; pi++) {
					if(minusrects[pi].contains(p.xy)) {
						j := 0;
						for(cl := catalog; cl != nil; cl = tl cl) {
							ce := hd cl;
							if(ce.mntpath != "") {
								if(j == pi) {
									unmountresource(ce);
									tabclicked = 1;
									break;
								}
								j++;
							}
						}
						break;
					}
				}
			}
		}
		# Button-3: context menu for catalog entries
		if((p.buttons & 4) != 0 && (wasdown & 4) == 0) {
			j := 0;
			for(ei := 0; ei < nctxentryrects; ei++) {
				if(ctxentryrects[ei].contains(p.xy)) {
					k := 0;
					for(cl := catalog; cl != nil; cl = tl cl) {
						if(k == j) {
							ce := hd cl;
							if(menumod != nil) {
								items: array of string;
								if(ce.mntpath == "")
									items = array[] of {"Add"};
								else
									items = array[] of {"Remove"};
								pop := menumod->new(items);
								result := pop.show(mainwin, p.xy, mouse);
								if(result == 0) {
									if(ce.mntpath == "")
										mountresource(ce);
									else
										unmountresource(ce);
								}
								redrawctx();
							}
							break;
						}
						k++;
					}
					break;
				}
				j++;
			}
			prevbuttons = 0;
		}
	ev := <-evch =>
		handleevent(ev);
		redrawctx();
	newimg := <-rsz =>
		mainwin = newimg;
		redrawctx();
	}
}

ctxtimer(evch: chan of string)
{
	for(;;) {
		sys->sleep(1000);
		needtick := 0;
		now := sys->millisec();
		for(r := resources; r != nil; r = tl r) {
			res := hd r;
			if(res.status == "active" || (res.lastused > 0 && now - res.lastused < 4000)) {
				needtick = 1;
				break;
			}
		}
		if(needtick)
			alt { evch <-= "tick" => ; * => ; }
	}
}

handleevent(ev: string)
{
	if(ev == "catalog" || ev == "tick")
		loadcatalog();
	if(ev == "catalog")
		return;
	if(hasprefix(ev, "context") || ev == "tick")
		loadcontext();
}

# --- Drawing ---

redrawctx()
{
	if(mainwin == nil)
		return;
	mr := mainwin.r;
	if(backbuf == nil || backbuf.r.dx() != mr.dx() || backbuf.r.dy() != mr.dy() ||
			backbuf.r.min.x != mr.min.x || backbuf.r.min.y != mr.min.y)
		backbuf = display_g.newimage(mr, mainwin.chans, 0, Draw->Nofill);
	front := mainwin;
	if(backbuf != nil)
		mainwin = backbuf;
	mainwin.draw(mainwin.r, bgcol, nil, (0, 0));
	drawcontext(mainwin.r);
	if(backbuf != nil) {
		mainwin = front;
		mainwin.draw(mainwin.r, backbuf, nil, backbuf.r.min);
	}
	mainwin.flush(Draw->Flushnow);
}

drawcontext(zone: Rect)
{
	pad := 8;
	y := zone.min.y + pad;
	secgap := 12;
	indw := 10;
	indh := 10;

	now := sys->millisec();

	# --- Resources section ---
	if(resources != nil) {
		mainwin.text((zone.min.x + pad, y), labelcol, (0, 0), mainfont, "Resources");
		y += mainfont.height + 4;

		for(r := resources; r != nil; r = tl r) {
			res := hd r;
			if(y + mainfont.height > zone.max.y)
				break;
			if(res.rtype != "tool" && res.lastused > 0 && now - res.lastused > 120000)
				continue;

			indcol := dimcol;
			if(res.status == "active" || (res.lastused > 0 && now - res.lastused < 3000))
				indcol = accentcol;
			else if(res.status == "streaming")
				indcol = greencol;
			else if(res.status == "stale")
				indcol = yellowcol;
			else if(res.status == "offline" || res.status == "error")
				indcol = redcol;

			indy := y + (mainfont.height - indh) / 2;
			mainwin.draw(Rect(
				(zone.min.x + pad, indy),
				(zone.min.x + pad + indw, indy + indh)),
				indcol, nil, (0, 0));

			label := res.label;
			if(label == nil || label == "")
				label = res.path;
			if(res.via != nil && res.via != "")
				label += " [" + res.via + "]";
			mainwin.text((zone.min.x + pad + indw + 6, y),
				text2col, (0, 0), mainfont, label);
			y += mainfont.height + 2;
		}
		y += secgap;
	}

	# --- Gaps section ---
	if(gaps != nil) {
		if(y + mainfont.height > zone.max.y)
			return;
		mainwin.text((zone.min.x + pad, y), labelcol, (0, 0), mainfont, "Gaps");
		y += mainfont.height + 4;

		for(g := gaps; g != nil; g = tl g) {
			gap := hd g;
			if(y + mainfont.height > zone.max.y)
				break;
			glyph := "●";
			gcol := text2col;
			if(gap.relevance == "high") {
				glyph = "▲";
				gcol = accentcol;
			} else if(gap.relevance == "low") {
				glyph = "○";
				gcol = dimcol;
			}
			mainwin.text((zone.min.x + pad, y), gcol, (0, 0), mainfont,
				glyph + " " + gap.desc);
			y += mainfont.height + 2;
		}
		y += secgap;
	}

	# --- Background tasks section ---
	if(bgtasks != nil) {
		if(y + mainfont.height > zone.max.y)
			return;
		mainwin.text((zone.min.x + pad, y), labelcol, (0, 0), mainfont, "Background");
		y += mainfont.height + 4;

		barh := 6;
		for(b := bgtasks; b != nil; b = tl b) {
			bg := hd b;
			if(y + mainfont.height + barh + 4 > zone.max.y)
				break;

			label := bg.label;
			if(bg.status != nil && bg.status != "")
				label += " [" + bg.status + "]";
			mainwin.text((zone.min.x + pad, y), text2col, (0, 0), mainfont, label);
			y += mainfont.height + 2;

			if(bg.progress != nil && bg.progress != "") {
				pct := strtoint(bg.progress);
				if(pct < 0) pct = 0;
				if(pct > 100) pct = 100;
				barw := zone.dx() - 2 * pad;
				bary := y;
				mainwin.draw(Rect(
					(zone.min.x + pad, bary),
					(zone.min.x + pad + barw, bary + barh)),
					progbgcol, nil, (0, 0));
				fillw := barw * pct / 100;
				if(fillw > 0)
					mainwin.draw(Rect(
						(zone.min.x + pad, bary),
						(zone.min.x + pad + fillw, bary + barh)),
						progfgcol, nil, (0, 0));
				y += barh + 4;
			}
		}
	}

	# --- Available Resources section ---
	nctxentryrects = 0;
	if(y + mainfont.height <= zone.max.y) {
		if(resources != nil || gaps != nil || bgtasks != nil)
			y += secgap;
		indicator := "▸";
		if(avail_expanded)
			indicator = "▾";
		hdrtext := "Available " + indicator;
		mainwin.text((zone.min.x + pad, y), labelcol, (0, 0), mainfont, hdrtext);
		availhdrrect = Rect((zone.min.x, y), (zone.max.x, y + mainfont.height));
		y += mainfont.height + 4;

		if(avail_expanded && catalog != nil) {
			glyphw := mainfont.width("○ ");
			plusw := mainfont.width("[+]");
			minusw := mainfont.width("[-]");
			plusrects = array[32] of Rect;
			nplusrects = 0;
			minusrects = array[32] of Rect;
			nminusrects = 0;
			ctxentryrects = array[32] of Rect;
			nctxentryrects = 0;
			for(cl := catalog; cl != nil; cl = tl cl) {
				ce := hd cl;
				if(y + mainfont.height > zone.max.y)
					break;
				if(nctxentryrects < len ctxentryrects)
					ctxentryrects[nctxentryrects++] = Rect(
						(zone.min.x, y),
						(zone.max.x, y + mainfont.height));
				glyph := "○";
				gcol := dimcol;
				if(ce.mntpath != "") {
					glyph = "●";
					gcol = text2col;
				}
				mainwin.text((zone.min.x + pad, y), gcol, (0, 0), mainfont, glyph);
				mainwin.text((zone.min.x + pad + glyphw, y), text2col, (0, 0), mainfont, ce.name);
				if(ce.mntpath == "") {
					mainwin.text((zone.max.x - pad - plusw, y), dimcol, (0, 0), mainfont, "[+]");
					if(nplusrects < len plusrects) {
						plusrects[nplusrects] = Rect(
							(zone.max.x - pad - plusw - 1, y),
							(zone.max.x - pad + 1, y + mainfont.height));
						nplusrects++;
					}
				} else {
					mainwin.text((zone.max.x - pad - minusw, y), dimcol, (0, 0), mainfont, "[-]");
					if(nminusrects < len minusrects) {
						minusrects[nminusrects] = Rect(
							(zone.max.x - pad - minusw - 1, y),
							(zone.max.x - pad + 1, y + mainfont.height));
						nminusrects++;
					}
				}
				y += mainfont.height + 2;
			}
		}
	}

	if(resources == nil && gaps == nil && bgtasks == nil && catalog == nil)
		drawcentertext(zone, "No context");
}

drawcentertext(r: Rect, text: string)
{
	tw := mainfont.width(text);
	tx := r.min.x + (r.dx() - tw) / 2;
	ty := r.min.y + (r.dy() - mainfont.height) / 2;
	mainwin.text((tx, ty), dimcol, (0, 0), mainfont, text);
}

# --- Namespace loading ---

loadcontext()
{
	# Resources
	resources = nil;
	base := sys->sprint("%s/activity/%d/context/resources", mountpt_g, actid_g);
	for(i := 0; ; i++) {
		s := readfile(sys->sprint("%s/%d", base, i));
		if(s == nil)
			break;
		s = strip(s);
		attrs := parseattrs(s);
		lu := 0;
		lus := getattr(attrs, "lastused");
		if(lus != nil) {
			lu = strtoint(lus);
			if(lu < 0) lu = 0;
		}
		resources = ref Resource(
			getattr(attrs, "path"),
			getattr(attrs, "label"),
			getattr(attrs, "type"),
			getattr(attrs, "status"),
			getattr(attrs, "via"),
			lu
		) :: resources;
	}
	resources = revres(resources);

	# Gaps
	gaps = nil;
	base = sys->sprint("%s/activity/%d/context/gaps", mountpt_g, actid_g);
	for(i = 0; ; i++) {
		s := readfile(sys->sprint("%s/%d", base, i));
		if(s == nil)
			break;
		s = strip(s);
		attrs := parseattrs(s);
		gaps = ref Gap(
			getattr(attrs, "desc"),
			getattr(attrs, "relevance")
		) :: gaps;
	}
	gaps = revgaps(gaps);

	# Background tasks
	bgtasks = nil;
	base = sys->sprint("%s/activity/%d/context/background", mountpt_g, actid_g);
	for(i = 0; ; i++) {
		s := readfile(sys->sprint("%s/%d", base, i));
		if(s == nil)
			break;
		s = strip(s);
		attrs := parseattrs(s);
		bgtasks = ref BgTask(
			getattr(attrs, "label"),
			getattr(attrs, "status"),
			getattr(attrs, "progress")
		) :: bgtasks;
	}
	bgtasks = revbg(bgtasks);

	loadcatalog();
}

loadcatalog()
{
	catalog = nil;
	for(i := 0; ; i++) {
		s := readfile(sys->sprint("%s/catalog/%d", mountpt_g, i));
		if(s == nil)
			break;
		s = strip(s);
		attrs := parseattrs(s);
		mntpath := getattr(attrs, "mntpath");
		if(mntpath == nil) mntpath = "";
		dial := getattr(attrs, "mount");
		if(dial == nil) dial = "";
		catalog = ref CatalogEntry(
			getattr(attrs, "name"),
			getattr(attrs, "desc"),
			getattr(attrs, "type"),
			mntpath,
			dial
		) :: catalog;
	}
	catalog = revcat(catalog);
}

# --- Resource mounting ---

slugify(s: string): string
{
	r := s;
	for(i := 0; i < len r; i++) {
		c := r[i];
		if(c >= 'A' && c <= 'Z')
			r[i] = c + ('a' - 'A');
		else if(c == ' ' || c == '\t')
			r[i] = '-';
	}
	return r;
}

ensuredir_mnt(mntdir: string)
{
	sys->create(MNT_BASE, Sys->OREAD, Sys->DMDIR | 8r777);
	sys->create(mntdir, Sys->OREAD, Sys->DMDIR | 8r777);
}

mountresource(ce: ref CatalogEntry)
{
	if(ce == nil || ce.dial == "")
		return;
	slug := slugify(ce.name);
	mntdir := MNT_BASE + "/" + slug;
	ensuredir_mnt(mntdir);
	(ok, conn) := sys->dial(ce.dial, nil);
	if(ok < 0) {
		sys->fprint(stderr, "lucictx: mount '%s': %r\n", ce.name);
		return;
	}
	if(sys->mount(conn.dfd, nil, mntdir, Sys->MREPL, "") < 0) {
		sys->fprint(stderr, "lucictx: mount '%s' at %s: %r\n", ce.name, mntdir);
		return;
	}
	# Notify luciuisrv
	writetofile(mountpt_g + "/ctl",
		"catalog mounted name=" + ce.name + " path=" + mntdir);
	# Respawn tools9p
	spawn spawnt9p();
}

unmountresource(ce: ref CatalogEntry)
{
	if(ce == nil || ce.mntpath == "")
		return;
	sys->unmount(nil, ce.mntpath);
	writetofile(mountpt_g + "/ctl", "catalog unmounted " + ce.name);
	spawn spawnt9p();
}

spawnt9p()
{
	t9p := load Tools9p "/dis/veltro/tools9p.dis";
	if(t9p == nil) {
		sys->fprint(stderr, "lucictx: cannot load tools9p: %r\n");
		return;
	}
	t9p->init(nil, "tools9p" :: "-m" :: "/tool" ::
		"read" :: "list" :: "find" :: "search" ::
		"write" :: "edit" :: "present" :: "ask" ::
		"diff" :: "json" :: "git" :: "memory" ::
		"websearch" :: "http" :: "mail" ::
		"spawn" :: "gap" :: nil);
}

# --- Attribute parsing ---

parseattrs(s: string): list of ref Attr
{
	kstarts := array[32] of int;
	eqposs := array[32] of int;
	nkp := 0;

	i := 0;
	while(i < len s && (s[i] == ' ' || s[i] == '\t'))
		i++;

	j := i;
	while(j < len s) {
		if(s[j] == '=') {
			kstart := j - 1;
			while(kstart > i && s[kstart - 1] != ' ' && s[kstart - 1] != '\t')
				kstart--;
			if(kstart >= 0 && kstart < j) {
				if(kstart == 0 || kstart == i || s[kstart - 1] == ' ' || s[kstart - 1] == '\t') {
					if(nkp >= len kstarts) {
						nks := array[len kstarts * 2] of int;
						nks[0:] = kstarts[0:nkp];
						kstarts = nks;
						neq := array[len eqposs * 2] of int;
						neq[0:] = eqposs[0:nkp];
						eqposs = neq;
					}
					kstarts[nkp] = kstart;
					eqposs[nkp] = j;
					nkp++;
				}
			}
		}
		j++;
	}

	attrs: list of ref Attr;
	for(k := 0; k < nkp; k++) {
		key := s[kstarts[k]:eqposs[k]];
		vstart := eqposs[k] + 1;
		vend: int;
		if(key != "text" && key != "data" && k + 1 < nkp) {
			vend = kstarts[k + 1];
			while(vend > vstart && (s[vend - 1] == ' ' || s[vend - 1] == '\t'))
				vend--;
		} else
			vend = len s;
		val := "";
		if(vstart < vend)
			val = s[vstart:vend];
		attrs = ref Attr(key, val) :: attrs;
		if(key == "text" || key == "data")
			break;
	}

	rev: list of ref Attr;
	for(; attrs != nil; attrs = tl attrs)
		rev = hd attrs :: rev;
	return rev;
}

getattr(attrs: list of ref Attr, key: string): string
{
	for(; attrs != nil; attrs = tl attrs)
		if((hd attrs).key == key)
			return (hd attrs).val;
	return nil;
}

# --- File I/O helpers ---

readfile(path: string): string
{
	fd := sys->open(path, Sys->OREAD);
	if(fd == nil)
		return nil;
	result := "";
	buf := array[8192] of byte;
	for(;;) {
		n := sys->read(fd, buf, len buf);
		if(n <= 0)
			break;
		result += string buf[0:n];
	}
	if(result == "")
		return nil;
	return result;
}

writetofile(path: string, text: string)
{
	fd := sys->open(path, Sys->OWRITE);
	if(fd == nil)
		return;
	b := array of byte text;
	sys->write(fd, b, len b);
}

strip(s: string): string
{
	while(len s > 0 && (s[len s - 1] == '\n' || s[len s - 1] == ' ' || s[len s - 1] == '\t'))
		s = s[0:len s - 1];
	return s;
}

strtoint(s: string): int
{
	n := 0;
	for(i := 0; i < len s; i++) {
		c := s[i];
		if(c < '0' || c > '9')
			return -1;
		n = n * 10 + (c - '0');
	}
	if(len s == 0)
		return -1;
	return n;
}

hasprefix(s, prefix: string): int
{
	return len s >= len prefix && s[0:len prefix] == prefix;
}

# --- List reversal helpers ---

revres(l: list of ref Resource): list of ref Resource
{
	r: list of ref Resource;
	for(; l != nil; l = tl l)
		r = hd l :: r;
	return r;
}

revgaps(l: list of ref Gap): list of ref Gap
{
	r: list of ref Gap;
	for(; l != nil; l = tl l)
		r = hd l :: r;
	return r;
}

revbg(l: list of ref BgTask): list of ref BgTask
{
	r: list of ref BgTask;
	for(; l != nil; l = tl l)
		r = hd l :: r;
	return r;
}

revcat(l: list of ref CatalogEntry): list of ref CatalogEntry
{
	r: list of ref CatalogEntry;
	for(; l != nil; l = tl l)
		r = hd l :: r;
	return r;
}
