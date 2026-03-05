implement LuciPres;

#
# lucipres - Presentation zone for Lucifer
#
# Standard wmclient app: gets its window Image from lucifer's wmsrv
# (preswmloop), so it can in future run remotely via 9cpu.
# Usage: lucipres [mountpt [actid]]
# args passed by lucifer: "lucipres" mountpt actid_string
#

include "sys.m";
	sys: Sys;

include "draw.m";
	draw: Draw;
	Font, Point, Rect, Image, Display, Screen, Pointer, Wmcontext: import draw;

include "bufio.m";

include "imagefile.m";

include "pdf.m";

include "mermaid.m";

include "rlayout.m";

include "menu.m";

include "viewport.m";

include "plumbmsg.m";

include "wmclient.m";
	wmclient: Wmclient;

LuciPres: module
{
	PATH: con "/dis/lucipres.dis";
	init: fn(ctxt: ref Draw->Context, args: list of string);
	deliverevent: fn(ev: string);
};

# --- Color constants ---
COLBG:		con int 16r080808FF;
COLBORDER:	con int 16r131313FF;
COLHEADER:	con int 16r0A0A0AFF;
COLACCENT:	con int 16rE8553AFF;
COLTEXT:	con int 16rCCCCCCFF;
COLTEXT2:	con int 16r999999FF;
COLDIM:		con int 16r444444FF;
COLLABEL:	con int 16r333333FF;

# --- ADTs ---

Artifact: adt {
	id:	string;
	atype:	string;
	label:	string;
	data:	string;
	rendimg: ref Image;
	pdfpage: int;
	rendering: int;
	zoom:	int;
	appstatus: string;	# "launching"|"running"|"dead" (type=app only)
	panx:	int;		# horizontal pan offset (pixels)
	pany:	int;		# vertical pan offset (pixels)
};

TabRect: adt {
	r:  Rect;
	id: string;
};

Attr: adt {
	key: string;
	val: string;
};

# --- Module state ---

rlay: Rlayout;
DocNode: import rlay;

pdfmod: PDF;
Doc: import pdfmod;

mermaidmod: Mermaid;

menumod: Menu;
Popup: import menumod;

vpmod: Viewport;
View: import vpmod;

plumbmod: Plumbmsg;
Msg: import plumbmod;

stderr: ref Sys->FD;
win: ref Wmclient->Window;
mainwin: ref Image;
backbuf: ref Image;		# off-screen back buffer for double-buffered redraw
display_g: ref Display;
mainfont: ref Font;
monofont_g: ref Font;
mountpt_g: string;
actid_g := -1;
preseventch: chan of string;

# Colors
bgcol: ref Image;
bordercol: ref Image;
headercol: ref Image;
accentcol: ref Image;
textcol: ref Image;
text2col: ref Image;
dimcol: ref Image;
labelcol: ref Image;

# Presentation state
artifacts: list of ref Artifact;
nart := 0;
centeredart: string;
artrendw := 0;
maxpresscrollpx := 0;
maxpanx := 0;
pres_viewport_h := 400;

# Tab state
tablayout: array of ref TabRect;
ntabs := 0;
tabscrolloff := 0;
tabstrip_miny := 0;
tabstrip_maxy := 0;
prescontentr: Rect;

# PDF nav rects
pdfnavprev: Rect;
pdfnavnext: Rect;

# Pixels per tab for button-2 drag scroll sensitivity
TABDRAGPX: con 60;

# --- init (standard wmclient app interface) ---

init(ctxt: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	draw = load Draw Draw->PATH;
	stderr = sys->fildes(2);

	wmclient = load Wmclient Wmclient->PATH;
	if(wmclient == nil) {
		sys->fprint(sys->fildes(2), "lucipres: cannot load wmclient: %r\n");
		return;
	}
	wmclient->init();

	# Parse args: "lucipres" mountpt actid
	a := args;
	if(a != nil) a = tl a;	# skip "lucipres"
	if(a != nil) { mountpt_g = hd a; a = tl a; }
	else mountpt_g = "/n/ui";
	if(a != nil) { actid_g = strtoint(hd a); a = tl a; }

	if(ctxt == nil)
		ctxt = wmclient->makedrawcontext();
	display_g = ctxt.display;

	# Allocate bgcol first — win.onscreen("max") triggers putimage() inside
	# wmclient which fills the zone image with Draw->White.  We need bgcol
	# ready so we can immediately overwrite that White before any flush.
	bgcol = display_g.color(COLBG);

	# Create window via the wmsrv in lucifer (preswmloop)
	# Plain: no border decoration — we're an embedded zone, not a top-level app
	win = wmclient->window(ctxt, "Presentation", Wmclient->Plain);
	wmclient->win.reshape(((0, 0), (100, 100)));
	wmclient->win.onscreen("max");
	# putimage() just filled the pres sub-image with White.  Overwrite now.
	if(win.screen != nil && win.screen.image != nil)
		win.screen.image.draw(win.screen.image.r, bgcol, nil, (0, 0));
	wmclient->win.startinput("ptr" :: nil);
	mainwin = win.image;

	# Allocate remaining colors
	bordercol = display_g.color(COLBORDER);
	headercol = display_g.color(COLHEADER);
	accentcol = display_g.color(COLACCENT);
	textcol = display_g.color(COLTEXT);
	text2col = display_g.color(COLTEXT2);
	dimcol = display_g.color(COLDIM);
	labelcol = display_g.color(COLLABEL);

	# Load fonts
	mainfont = Font.open(display_g, "/fonts/dejavu/DejaVuSans/unicode.14.font");
	if(mainfont == nil)
		mainfont = Font.open(display_g, "*default*");
	monofont_g = Font.open(display_g, "/fonts/dejavu/DejaVuSansMono/unicode.14.font");
	if(monofont_g == nil)
		monofont_g = mainfont;

	# Load rlayout
	rlay = load Rlayout Rlayout->PATH;
	if(rlay != nil)
		rlay->init(display_g);

	# Load menu module
	menumod = load Menu Menu->PATH;
	if(menumod != nil)
		menumod->init(display_g, mainfont);

	# Load viewport
	vpmod = load Viewport Viewport->PATH;

	# Load plumbmsg
	plumbmod = load Plumbmsg Plumbmsg->PATH;

	# Channel for serializing events from background goroutines (rendermermaid,
	# deliverevent) to the main loop goroutine.
	preseventch = chan[8] of string;

	if(actid_g >= 0)
		loadpresentation();

	redrawpres();

	# Event loop
	prevbuttons := 0;
	b2tabdragging := 0;
	b2dragstartx := 0;
	b2dragstartoff := 0;
	for(;;) alt {
	p := <-win.ctxt.ptr =>
		if(wmclient->win.pointer(*p) == 0) {
			wasdown := prevbuttons;
			prevbuttons = p.buttons;

			# Scroll wheel
			if(p.buttons & 8) {
				intabstrip := (tabstrip_maxy > tabstrip_miny &&
					p.xy.y >= tabstrip_miny && p.xy.y < tabstrip_maxy);
				if(intabstrip) {
					if(tabscrolloff > 0)
						tabscrolloff--;
				} else
					prescroll(-1);
				redrawpres();
			} else if(p.buttons & 16) {
				intabstrip := (tabstrip_maxy > tabstrip_miny &&
					p.xy.y >= tabstrip_miny && p.xy.y < tabstrip_maxy);
				if(intabstrip) {
					if(tabscrolloff < nart - 1)
						tabscrolloff++;
				} else
					prescroll(1);
				redrawpres();
			}

			# Button-1 just pressed
			if(p.buttons == 1 && wasdown == 0) {
				tabclicked := 0;
				# Tab clicks
				for(ti := 0; ti < ntabs; ti++) {
					if(tablayout[ti].r.contains(p.xy)) {
						if(tablayout[ti].id != centeredart) {
							centeredart = tablayout[ti].id;
							if(actid_g >= 0)
								writetofile(
									sys->sprint("%s/activity/%d/presentation/ctl",
										mountpt_g, actid_g),
									"center id=" + centeredart);
						}
						tabclicked = 1;
						redrawpres();
						break;
					}
				}
				# PDF page navigation
				if(!tabclicked) {
					if(pdfnavprev.max.x > pdfnavprev.min.x &&
							pdfnavprev.contains(p.xy)) {
						pdfart := findartifact(centeredart);
						if(pdfart != nil && pdfart.pdfpage > 0) {
							pdfart.pdfpage--;
							pdfart.rendimg = nil;
							pdfart.pany = 0;
							pdfart.panx = 0;
							redrawpres();
						}
						tabclicked = 1;
					} else if(pdfnavnext.max.x > pdfnavnext.min.x &&
							pdfnavnext.contains(p.xy)) {
						pdfart := findartifact(centeredart);
						if(pdfart != nil) {
							pdfart.pdfpage++;
							pdfart.rendimg = nil;
							pdfart.pany = 0;
							pdfart.panx = 0;
							redrawpres();
						}
						tabclicked = 1;
					}
				}
				# Drag in content area
				if(!tabclicked && prescontentr.contains(p.xy)) {
					dart := findartifact(centeredart);
					if(dart != nil && dart.atype != "app") {
						handledrag(dart, p.xy);
						prevbuttons = 0;
					}
				}
			}

			# Button-2 drag in tab strip for horizontal tab scrolling
			intabstrip2 := (tabstrip_maxy > tabstrip_miny &&
				p.xy.y >= tabstrip_miny && p.xy.y < tabstrip_maxy);
			if(p.buttons & 2) {
				if(intabstrip2) {
					if(b2tabdragging == 0) {
						b2tabdragging = 1;
						b2dragstartx = p.xy.x;
						b2dragstartoff = tabscrolloff;
					} else {
						delta := (b2dragstartx - p.xy.x) / TABDRAGPX;
						newoff := b2dragstartoff + delta;
						if(newoff < 0) newoff = 0;
						if(newoff >= nart) newoff = nart - 1;
						if(newoff < 0) newoff = 0;
						if(newoff != tabscrolloff) {
							tabscrolloff = newoff;
							redrawpres();
						}
					}
				}
			} else
				b2tabdragging = 0;

			# Button-3: context menu
			if((p.buttons & 4) != 0 && (wasdown & 4) == 0) {
				if(menumod != nil) {
					handlecontextmenu(p);
					prevbuttons = 0;
					redrawpres();
				}
			}
		}
	ev := <-preseventch =>
		if(ev != "render")
			handleevent(ev);
		redrawpres();
	e := <-win.ctl or
	e = <-win.ctxt.ctl =>
		if(e == "exit")
			return;
		wmclient->win.wmctl(e);
		if(win.image != mainwin) {
			mainwin = win.image;
			# putimage() in wmclient fills the zone image with Draw->White.
			# Immediately overwrite with bgcol so no white flash reaches the display.
			if(win.screen != nil && win.screen.image != nil)
				win.screen.image.draw(win.screen.image.r, bgcol, nil, (0,0));
			for(al := artifacts; al != nil; al = tl al)
				(hd al).rendimg = nil;
			artrendw = 0;
			redrawpres();
		}
	}
}

deliverevent(ev: string)
{
	alt {
	preseventch <-= ev =>
		;
	* =>
		;
	}
}

handleevent(ev: string)
{
	if(ev == "presentation current") {
		s := readfile(sys->sprint("%s/activity/%d/presentation/current",
			mountpt_g, actid_g));
		if(s != nil) {
			centeredart = strip(s);
		}
	} else if(hasprefix(ev, "presentation new ")) {
		id := strip(ev[len "presentation new ":]);
		if(id != "")
			loadartifact(id);
	} else if(hasprefix(ev, "presentation kill ")) {
		# "presentation kill <id>" — app was killed; remove its tab.
		#
		# MUST be handled BEFORE the catch-all "presentation " branch below.
		# Without this case, "presentation kill clock" falls through to:
		#   updateartifact("kill clock") → loadartifact("kill clock")
		# which creates a bogus "kill clock" tab in the tab bar.
		#
		# luciuisrv emits both "presentation kill <id>" and then
		# "presentation delete <id>" when the kill ctl command is processed.
		# Handling kill here is belt-and-suspenders — delete will also fire.
		id := strip(ev[len "presentation kill ":]);
		if(id != "")
			deleteartifact(id);
	} else if(hasprefix(ev, "presentation delete ")) {
		id := strip(ev[len "presentation delete ":]);
		if(id != "")
			deleteartifact(id);
	} else if(hasprefix(ev, "presentation app ")) {
		# "presentation app <id> status=<s>" — update appstatus field
		rest := ev[len "presentation app ":] ;
		# split rest into first word (id) and remainder (attrs)
		sppos := 0;
		for(; sppos < len rest && rest[sppos] != ' ' && rest[sppos] != '	'; sppos++)
			;
		appid := strip(rest[0:sppos]);
		attrs2 := "";
		if(sppos < len rest)
			attrs2 = strip(rest[sppos:]);
		status := "";
		needle := "status=";
		for(si := 0; si + len needle <= len attrs2; si++) {
			if(attrs2[si:si + len needle] == needle) {
				status = strip(attrs2[si + len needle:]);
				break;
			}
		}
		if(appid != "" && status != "") {
			for(aal := artifacts; aal != nil; aal = tl aal) {
				if((hd aal).id == appid) {
					(hd aal).appstatus = status;
					break;
				}
			}
		}
	} else if(hasprefix(ev, "presentation ")) {
		id := strip(ev[len "presentation ":]);
		if(id != "")
			updateartifact(id);
	}
}

# --- Drawing ---

redrawpres()
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
	drawpresentation(mainwin.r);
	if(backbuf != nil) {
		mainwin = front;
		mainwin.draw(mainwin.r, backbuf, nil, backbuf.r.min);
	}
	mainwin.flush(Draw->Flushnow);
}

drawpresentation(zone: Rect)
{
	pad := 8;
	pdfnavprev = Rect((0,0),(0,0));
	pdfnavnext = Rect((0,0),(0,0));
	al: list of ref Artifact;
	centart: ref Artifact;

	centart = nil;
	for(al = artifacts; al != nil; al = tl al) {
		if((hd al).id == centeredart) {
			centart = hd al;
			break;
		}
	}
	if(centart == nil && artifacts != nil)
		centart = hd artifacts;

	if(centart == nil) {
		drawcentertext(zone, "No artifacts");
		return;
	}

	# Tab strip at top
	tabh := mainfont.height + 12;
	tabr := Rect((zone.min.x, zone.min.y), (zone.max.x, zone.min.y + tabh));
	mainwin.draw(tabr, headercol, nil, (0, 0));

	tabstrip_miny = tabr.min.y;
	tabstrip_maxy = tabr.max.y;

	tablayout = array[nart + 1] of ref TabRect;
	ntabs = 0;

	tx := zone.min.x + pad;
	tskip := tabscrolloff;
	for(al = artifacts; al != nil; al = tl al) {
		art := hd al;
		if(tskip > 0) { tskip--; continue; }
		tw := mainfont.width(art.label);
		if(tx + tw + pad > zone.max.x)
			break;
		active := 0;
		if(art.id == centart.id)
			active = 1;
		tcol := text2col;
		if(active) {
			tcol = textcol;
			mainwin.draw(Rect((tx, tabr.max.y - 3), (tx + tw, tabr.max.y - 1)),
				accentcol, nil, (0, 0));
		}
		mainwin.text((tx, tabr.min.y + 6), tcol, (0, 0), mainfont, art.label);
		# Status dot for app tabs
		if(art.atype == "app") {
			dotcol: ref Image;
			if(art.appstatus == "running")
				dotcol = display_g.color(Draw->Green);
			else
				dotcol = dimcol;
			dotx := tx + tw + 4;
			doty := tabr.min.y + (tabr.dy() - 5) / 2;
			mainwin.draw(Rect((dotx, doty), (dotx + 5, doty + 5)), dotcol, nil, (0, 0));
		}
		if(ntabs < len tablayout)
			tablayout[ntabs++] = ref TabRect(
				Rect((tx, tabr.min.y), (tx + tw + 20, tabr.max.y)), art.id);
		tx += tw + 20;
	}

	# Separator below tabs
	mainwin.draw(Rect((zone.min.x, tabr.max.y), (zone.max.x, tabr.max.y + 1)),
		bordercol, nil, (0, 0));

	# Content area
	contentr := Rect((zone.min.x, tabr.max.y + 1), (zone.max.x, zone.max.y));
	prescontentr = contentr;
	contentw := contentr.dx() - 2 * pad;

	# Invalidate render caches on width change
	if(contentw != artrendw) {
		for(al = artifacts; al != nil; al = tl al)
			(hd al).rendimg = nil;
		artrendw = contentw;
	}

	contenty := contentr.min.y + pad;
	pres_viewport_h = contentr.dy() - 2 * pad;

	case centart.atype {
	"markdown" or "doc" =>
		if(centart.rendimg == nil)
		if(rlay != nil)
		if(centart.data != "") {
			codebg := display_g.color(int 16r1A1A2AFF);
			zw := contentw * 100 / artzoom(centart);
			style := ref Rlayout->Style(
				zw, 4,
				mainfont, monofont_g,
				textcol, bgcol, accentcol, codebg,
				100
			);
			(img, nil) := rlay->render(rlay->parsemd(centart.data), style);
			centart.rendimg = img;
		}
		if(centart.rendimg != nil) {
			imgh := centart.rendimg.r.dy();
			imgw := centart.rendimg.r.dx();
			newmax := imgh - pres_viewport_h;
			if(newmax < 0) newmax = 0;
			maxpresscrollpx = newmax;
			if(centart.pany > maxpresscrollpx)
				centart.pany = maxpresscrollpx;
			newmaxx := imgw - contentw;
			if(newmaxx < 0) newmaxx = 0;
			maxpanx = newmaxx;
			if(centart.panx > maxpanx)
				centart.panx = maxpanx;
			srcy := centart.pany;
			srcx := centart.panx;
			dsty := contentr.min.y + pad;
			enddsty := dsty + (imgh - srcy);
			if(enddsty > contentr.max.y) enddsty = contentr.max.y;
			if(dsty < enddsty)
				mainwin.draw(
					Rect((contentr.min.x + pad, dsty),
					     (contentr.min.x + pad + contentw, enddsty)),
					centart.rendimg, nil, (srcx, srcy));
		} else
			drawcentertext(contentr, "(empty)");
	"text" or "code" =>
		if(centart.atype == "code") {
			codebg2 := display_g.color(int 16r1A1A2AFF);
			mainwin.draw(contentr, codebg2, nil, (0, 0));
		}
		ls := splitlines(centart.data);
		total_h := listlen(ls) * monofont_g.height;
		newmax2 := total_h - pres_viewport_h;
		if(newmax2 < 0) newmax2 = 0;
		maxpresscrollpx = newmax2;
		if(centart.pany > maxpresscrollpx)
			centart.pany = maxpresscrollpx;
		# Compute max horizontal pan from widest line
		maxlinew := 0;
		for(wlm := ls; wlm != nil; wlm = tl wlm) {
			lw := monofont_g.width(hd wlm);
			if(lw > maxlinew) maxlinew = lw;
		}
		newmaxx2 := maxlinew - contentw;
		if(newmaxx2 < 0) newmaxx2 = 0;
		maxpanx = newmaxx2;
		if(centart.panx > maxpanx)
			centart.panx = maxpanx;
		y2 := contenty - centart.pany;
		wl: list of string;
		for(wl = ls; wl != nil; wl = tl wl) {
			if(y2 + monofont_g.height > contentr.max.y)
				break;
			if(y2 >= contentr.min.y)
				mainwin.text((contentr.min.x + pad - centart.panx, y2),
					textcol, (0, 0), monofont_g, hd wl);
			y2 += monofont_g.height;
		}
		if(centart.data == "")
			drawcentertext(contentr, "(empty)");
	"pdf" =>
		navh := mainfont.height + 8;
		pdfcontent := Rect(contentr.min, (contentr.max.x, contentr.max.y - navh));
		pdfnav := Rect((contentr.min.x, contentr.max.y - navh), contentr.max);
		mainwin.draw(pdfnav, headercol, nil, (0, 0));
		pagestr := sys->sprint("Page %d", centart.pdfpage + 1);
		psw := mainfont.width(pagestr);
		psy := pdfnav.min.y + (navh - mainfont.height) / 2;
		midx := pdfnav.min.x + pdfnav.dx() / 2;
		mainwin.text((midx - psw/2, psy), textcol, (0, 0), mainfont, pagestr);
		prevlabel := " < ";
		plw := mainfont.width(prevlabel);
		plx := midx - psw/2 - plw - 8;
		if(centart.pdfpage > 0) {
			mainwin.text((plx, psy), accentcol, (0, 0), mainfont, prevlabel);
			pdfnavprev = Rect((plx, pdfnav.min.y), (plx + plw, pdfnav.max.y));
		} else {
			mainwin.text((plx, psy), dimcol, (0, 0), mainfont, prevlabel);
		}
		nextlabel := " > ";
		nlw := mainfont.width(nextlabel);
		nlx := midx + psw/2 + 8;
		mainwin.text((nlx, psy), accentcol, (0, 0), mainfont, nextlabel);
		pdfnavnext = Rect((nlx, pdfnav.min.y), (nlx + nlw, pdfnav.max.y));
		pres_viewport_h = pdfcontent.dy() - 2 * pad;
		if(centart.rendimg == nil)
			centart.rendimg = renderpdfpage(centart.data, centart.pdfpage,
				96 * artzoom(centart) / 100);
		if(centart.rendimg != nil) {
			imgh3 := centart.rendimg.r.dy();
			imgw3 := centart.rendimg.r.dx();
			newmax3 := imgh3 - pres_viewport_h;
			if(newmax3 < 0) newmax3 = 0;
			maxpresscrollpx = newmax3;
			if(centart.pany > maxpresscrollpx)
				centart.pany = maxpresscrollpx;
			newmaxx3 := imgw3 - contentw;
			if(newmaxx3 < 0) newmaxx3 = 0;
			maxpanx = newmaxx3;
			if(centart.panx > maxpanx)
				centart.panx = maxpanx;
			srcy3 := centart.pany;
			srcx3 := centart.panx;
			dsty3 := pdfcontent.min.y + pad;
			enddsty3 := dsty3 + (imgh3 - srcy3);
			if(enddsty3 > pdfcontent.max.y) enddsty3 = pdfcontent.max.y;
			if(dsty3 < enddsty3)
				mainwin.draw(
					Rect((pdfcontent.min.x + pad, dsty3),
					     (pdfcontent.min.x + pad + contentw, enddsty3)),
					centart.rendimg, nil, (srcx3, srcy3));
		} else
			drawcentertext(pdfcontent, "cannot render PDF");
	"image" =>
		if(centart.rendimg == nil)
			centart.rendimg = renderimage(centart.data);
		if(centart.rendimg != nil) {
			imgh4 := centart.rendimg.r.dy();
			imgw4 := centart.rendimg.r.dx();
			newmax4 := imgh4 - pres_viewport_h;
			if(newmax4 < 0) newmax4 = 0;
			maxpresscrollpx = newmax4;
			if(centart.pany > maxpresscrollpx)
				centart.pany = maxpresscrollpx;
			newmaxx4 := imgw4 - contentw;
			if(newmaxx4 < 0) newmaxx4 = 0;
			maxpanx = newmaxx4;
			if(centart.panx > maxpanx)
				centart.panx = maxpanx;
			srcy4 := centart.pany;
			srcx4 := centart.panx;
			dsty4 := contentr.min.y + pad;
			enddsty4 := dsty4 + (imgh4 - srcy4);
			if(enddsty4 > contentr.max.y) enddsty4 = contentr.max.y;
			if(dsty4 < enddsty4)
				mainwin.draw(
					Rect((contentr.min.x + pad, dsty4),
					     (contentr.min.x + pad + contentw, enddsty4)),
					centart.rendimg, nil, (srcx4, srcy4));
		} else
			drawcentertext(contentr, "cannot render image");
	"mermaid" =>
		if(centart.rendimg == nil) {
			if(centart.rendering == 0 && centart.data != "") {
				centart.rendering = 1;
				mermw := contentw * 100 / artzoom(centart);
				spawn rendermermaid(centart, mermw);
			}
			if(centart.rendering == 1)
				drawcentertext(contentr, "Rendering diagram...");
			else if(centart.rendering == 2) {
				codebg3 := display_g.color(int 16r1A1A2AFF);
				mainwin.draw(contentr, codebg3, nil, (0, 0));
				ls3 := splitlines(centart.data);
				total_h3 := listlen(ls3) * monofont_g.height;
				newmax5 := total_h3 - pres_viewport_h;
				if(newmax5 < 0) newmax5 = 0;
				maxpresscrollpx = newmax5;
				if(centart.pany > maxpresscrollpx)
					centart.pany = maxpresscrollpx;
				maxpanx = 0;
				y5 := contenty - centart.pany;
				wl5: list of string;
				for(wl5 = ls3; wl5 != nil; wl5 = tl wl5) {
					if(y5 + monofont_g.height > contentr.max.y)
						break;
					if(y5 >= contentr.min.y)
						mainwin.text((contentr.min.x + pad, y5),
							textcol, (0, 0), monofont_g, hd wl5);
					y5 += monofont_g.height;
				}
			}
		} else {
			imgh5 := centart.rendimg.r.dy();
			imgw5 := centart.rendimg.r.dx();
			newmax5b := imgh5 - pres_viewport_h;
			if(newmax5b < 0) newmax5b = 0;
			maxpresscrollpx = newmax5b;
			if(centart.pany > maxpresscrollpx)
				centart.pany = maxpresscrollpx;
			newmaxx5 := imgw5 - contentw;
			if(newmaxx5 < 0) newmaxx5 = 0;
			maxpanx = newmaxx5;
			if(centart.panx > maxpanx)
				centart.panx = maxpanx;
			srcy5 := centart.pany;
			srcx5 := centart.panx;
			dsty5 := contentr.min.y + pad;
			enddsty5 := dsty5 + (imgh5 - srcy5);
			if(enddsty5 > contentr.max.y) enddsty5 = contentr.max.y;
			if(dsty5 < enddsty5)
				mainwin.draw(
					Rect((contentr.min.x + pad, dsty5),
					     (contentr.min.x + pad + contentw, enddsty5)),
					centart.rendimg, nil, (srcx5, srcy5));
		}
	"table" =>
		trows := splitlines(centart.data);
		if(centart.data == "") {
			drawcentertext(contentr, "(empty table)");
		} else {
			ncols6 := 0;
			for(trl6 := trows; trl6 != nil; trl6 = tl trl6) {
				n6 := tabcountcols(hd trl6);
				if(n6 > ncols6) ncols6 = n6;
			}
			if(ncols6 == 0) {
				drawcentertext(contentr, "(no columns)");
			} else {
				colw6 := array[ncols6] of {* => 20};
				for(trl6 = trows; trl6 != nil; trl6 = tl trl6) {
					if(tabissep(hd trl6)) continue;
					cells6 := tabparsecells(hd trl6);
					ci6 := 0;
					for(; cells6 != nil && ci6 < ncols6; cells6 = tl cells6) {
						w6 := mainfont.width(hd cells6) + 12;
						if(w6 > colw6[ci6]) colw6[ci6] = w6;
						ci6++;
					}
				}
				# Compute total table width for horizontal pan
				tabtotalw := 0;
				for(twi := 0; twi < ncols6; twi++)
					tabtotalw += colw6[twi];
				rowh6 := mainfont.height + 8;
				nrows6 := listlen(trows);
				total_h6 := nrows6 * rowh6;
				newmax6 := total_h6 - pres_viewport_h;
				if(newmax6 < 0) newmax6 = 0;
				maxpresscrollpx = newmax6;
				if(centart.pany > maxpresscrollpx)
					centart.pany = maxpresscrollpx;
				newmaxx6 := tabtotalw - contentw;
				if(newmaxx6 < 0) newmaxx6 = 0;
				maxpanx = newmaxx6;
				if(centart.panx > maxpanx)
					centart.panx = maxpanx;
				yt6 := contenty - centart.pany;
				isheader6 := 1;
				for(trl6 = trows; trl6 != nil; trl6 = tl trl6) {
					rline6 := hd trl6;
					if(tabissep(rline6)) {
						if(yt6 >= contentr.min.y && yt6 < contentr.max.y)
							mainwin.draw(
								Rect((contentr.min.x + pad, yt6),
								     (contentr.max.x - pad, yt6 + 1)),
								bordercol, nil, (0, 0));
						yt6 += 3;
						isheader6 = 0;
						continue;
					}
					if(yt6 + rowh6 > contentr.max.y) break;
					if(yt6 + rowh6 > contentr.min.y) {
						if(isheader6)
							mainwin.draw(
								Rect((contentr.min.x + pad, yt6),
								     (contentr.max.x - pad, yt6 + rowh6)),
								headercol, nil, (0, 0));
						cells6 := tabparsecells(rline6);
						ci6 := 0;
						xt6 := contentr.min.x + pad - centart.panx;
						celcol6: ref Image;
						for(; cells6 != nil && ci6 < ncols6; cells6 = tl cells6) {
							if(isheader6) celcol6 = labelcol;
							else celcol6 = textcol;
							if(yt6 >= contentr.min.y)
								mainwin.text((xt6 + 4, yt6 + 4),
									celcol6, (0, 0), mainfont, hd cells6);
							xt6 += colw6[ci6];
							ci6++;
						}
					}
					if(isheader6) isheader6 = 0;
					yt6 += rowh6;
				}
			}
		}
	"app" =>
		# App window is at higher z-order covering the content area;
		# show placeholder only while the app is still launching.
		if(centart.appstatus != "running")
			drawcentertext(contentr, "Launching " + centart.label + "...");
	* =>
		if(centart.atype != "") {
			mainwin.text((contentr.min.x + pad, contenty),
				labelcol, (0, 0), mainfont, "[" + centart.atype + "]");
			contenty += mainfont.height + 4;
		}
		if(centart.data == "")
			drawcentertext(contentr, "(empty)");
		else {
			ls2 := wraptext(centart.data, contentw);
			wl2: list of string;
			for(wl2 = ls2; wl2 != nil; wl2 = tl wl2) {
				if(contenty + mainfont.height > contentr.max.y)
					break;
				mainwin.text((contentr.min.x + pad, contenty),
					textcol, (0, 0), mainfont, hd wl2);
				contenty += mainfont.height;
			}
		}
	}
}

drawcentertext(r: Rect, text: string)
{
	tw := mainfont.width(text);
	tx := r.min.x + (r.dx() - tw) / 2;
	ty := r.min.y + (r.dy() - mainfont.height) / 2;
	mainwin.text((tx, ty), dimcol, (0, 0), mainfont, text);
}

# --- Scroll and drag ---

# Scroll the current artifact vertically.
# dir: -1 = up, 1 = down.
# Uses Viewport for boundary detection: when a PDF is at the bottom
# and the user scrolls down, advance to the next page (like Xenith).
prescroll(dir: int)
{
	art := findartifact(centeredart);
	if(art == nil)
		return;

	step := mainfont.height * 3;
	if(vpmod != nil) {
		step = vpmod->scrollstep(pres_viewport_h);
		v := ref View(art.panx, art.pany, 0, 0, 0, 0);
		v.contentw = art.panx + 1;  # dummy — not clamping x here
		v.contenth = maxpresscrollpx + pres_viewport_h;
		v.vieww = 1;
		v.viewh = pres_viewport_h;
		boundary := vpmod->scrolly(v, dir, step);
		art.pany = v.pany;

		# Page navigation at boundary (PDFs)
		if(art.atype == "pdf" && boundary != 0) {
			if(boundary > 0) {
				# At bottom — next page
				art.pdfpage++;
				art.rendimg = nil;
				art.pany = 0;
				art.panx = 0;
			} else if(art.pdfpage > 0) {
				# At top — previous page, start at bottom
				art.pdfpage--;
				art.rendimg = nil;
				art.pany = 16r7FFFFFFF;  # clamped during render
				art.panx = 0;
			}
		}
	} else {
		# Fallback without viewport module
		if(dir > 0) {
			art.pany += step;
			if(art.pany > maxpresscrollpx)
				art.pany = maxpresscrollpx;
		} else {
			art.pany -= step;
			if(art.pany < 0)
				art.pany = 0;
		}
	}
}

# Drag the current artifact content by mouse movement.
# Follows the same pattern as Xenith's imagedrag(): track initial
# position, compute delta, clamp via Viewport, redraw each move.
handledrag(art: ref Artifact, startpt: Point)
{
	startpx := art.panx;
	startpy := art.pany;

	for(;;) {
		np := <-win.ctxt.ptr;
		if((np.buttons & 1) == 0)
			break;

		dx := startpt.x - np.xy.x;
		dy := startpt.y - np.xy.y;

		if(vpmod != nil) {
			v := ref View(0, 0, 0, 0, 0, 0);
			v.contentw = maxpanx + prescontentr.dx();
			v.contenth = maxpresscrollpx + pres_viewport_h;
			v.vieww = prescontentr.dx();
			v.viewh = pres_viewport_h;
			vpmod->drag(v, startpx, startpy, dx, dy);
			art.panx = v.panx;
			art.pany = v.pany;
		} else {
			art.panx = startpx + dx;
			art.pany = startpy + dy;
			if(art.panx < 0) art.panx = 0;
			if(art.panx > maxpanx) art.panx = maxpanx;
			if(art.pany < 0) art.pany = 0;
			if(art.pany > maxpresscrollpx) art.pany = maxpresscrollpx;
		}
		redrawpres();
	}
}

# --- Context menu ---

handlecontextmenu(p: ref Pointer)
{
	artid := "";
	for(ti := 0; ti < ntabs; ti++)
		if(tablayout[ti].r.contains(p.xy)) {
			artid = tablayout[ti].id;
			break;
		}
	if(artid == "" && prescontentr.max.x > prescontentr.min.x &&
			prescontentr.contains(p.xy))
		artid = centeredart;

	if(artid == "")
		return;

	art := findartifact(artid);
	# App type: Kill menu
	if(art != nil && art.atype == "app") {
		killitems := array[] of {"Kill"};
		killpop := menumod->new(killitems);
		killresult := killpop.show(mainwin, p.xy, win.ctxt.ptr);
		if(killresult == 0 && actid_g >= 0)
			writetofile(
				sys->sprint("%s/activity/%d/presentation/ctl",
					mountpt_g, actid_g),
				"kill id=" + artid);
		return;
	}
	# All non-app types get Zoom In/Out and Reset View
	items := array[] of {"Close", "Zoom In", "Zoom Out", "Reset View", "Export"};
	pop := menumod->new(items);
	result := pop.show(mainwin, p.xy, win.ctxt.ptr);
	case result {
	0 =>
		deleteartifactui(artid);
	1 =>
		# Zoom In
		if(art != nil) {
			art.zoom = artzoom(art) + 25;
			if(art.zoom > 400) art.zoom = 400;
			art.rendimg = nil;
		}
	2 =>
		# Zoom Out
		if(art != nil) {
			art.zoom = artzoom(art) - 25;
			if(art.zoom < 25) art.zoom = 25;
			art.rendimg = nil;
		}
	3 =>
		# Reset View — zoom to 100%, pan to origin
		if(art != nil) {
			art.zoom = 0;
			art.panx = 0;
			art.pany = 0;
			art.rendimg = nil;
		}
	4 =>
		exportartifact(art);
	}
}

# --- Namespace loading ---

loadpresentation()
{
	artifacts = nil;
	nart = 0;
	centeredart = "";

	base := sys->sprint("%s/activity/%d/presentation", mountpt_g, actid_g);
	s := readfile(base + "/current");
	if(s != nil)
		centeredart = strip(s);

	fd := sys->open(base, Sys->OREAD);
	if(fd == nil)
		return;
	for(;;) {
		(n, dirs) := sys->dirread(fd);
		if(n <= 0)
			break;
		for(di := 0; di < n; di++) {
			nm := dirs[di].name;
			if(nm == "ctl" || nm == "current" || nm == ".." || nm == ".")
				continue;
			if(!(dirs[di].mode & Sys->DMDIR))
				continue;
			artbase := base + "/" + nm;
			atype := readfile(artbase + "/type");
			if(atype != nil) atype = strip(atype);
			label := readfile(artbase + "/label");
			if(label != nil) label = strip(label);
			data := readfile(artbase + "/data");
			appstatus := readfile(artbase + "/appstatus");
			if(atype == nil || atype == "") atype = "text";
			if(label == nil || label == "") label = nm;
			if(data == nil) data = "";
			if(appstatus == nil) appstatus = "";
			else appstatus = strip(appstatus);
			art := ref Artifact(nm, atype, label, data, nil, 0, 0, 0, appstatus, 0, 0);
			artifacts = art :: artifacts;
			nart++;
		}
	}
	artifacts = revarts(artifacts);
}

loadartifact(id: string)
{
	base := sys->sprint("%s/activity/%d/presentation/%s", mountpt_g, actid_g, id);
	atype := readfile(base + "/type");
	if(atype != nil) atype = strip(atype);
	label := readfile(base + "/label");
	if(label != nil) label = strip(label);
	data := readfile(base + "/data");
	appstatus2 := readfile(base + "/appstatus");
	if(atype == nil || atype == "") atype = "text";
	if(label == nil || label == "") label = id;
	if(data == nil) data = "";
	if(appstatus2 == nil) appstatus2 = "";
	else appstatus2 = strip(appstatus2);
	art := ref Artifact(id, atype, label, data, nil, 0, 0, 0, appstatus2, 0, 0);
	artifacts = appendart(artifacts, art);
	nart++;
}

updateartifact(id: string)
{
	base := sys->sprint("%s/activity/%d/presentation/%s", mountpt_g, actid_g, id);
	atype := readfile(base + "/type");
	if(atype != nil) atype = strip(atype);
	label := readfile(base + "/label");
	if(label != nil) label = strip(label);
	data := readfile(base + "/data");
	for(al := artifacts; al != nil; al = tl al) {
		art := hd al;
		if(art.id == id) {
			if(atype != nil && atype != "") art.atype = atype;
			if(label != nil && label != "") art.label = label;
			if(data != nil) {
				art.data = data;
				art.rendimg = nil;
				art.rendering = 0;
			}
			return;
		}
	}
	loadartifact(id);
}

deleteartifact(id: string)
{
	nal: list of ref Artifact;
	for(al := artifacts; al != nil; al = tl al)
		if((hd al).id != id)
			nal = (hd al) :: nal;
	artifacts = revarts(nal);
	nart--;
	if(nart < 0) nart = 0;
	if(centeredart == id) {
		if(artifacts != nil)
			centeredart = (hd artifacts).id;
		else
			centeredart = "";
	}
	if(tabscrolloff >= nart && nart > 0)
		tabscrolloff = nart - 1;
	if(nart == 0)
		tabscrolloff = 0;
}

deleteartifactui(id: string)
{
	if(actid_g >= 0)
		writetofile(
			sys->sprint("%s/activity/%d/presentation/ctl", mountpt_g, actid_g),
			"delete id=" + id);
}

exportartifact(art: ref Artifact)
{
	if(art == nil)
		return;
	if(art.atype == "pdf" || art.atype == "image") {
		if(plumbmod != nil) {
			msg := ref Msg("lucipres", "edit", "/",
				"text", "action=showdata", array of byte art.data);
			if(msg.send() >= 0)
				return;
		}
		writetosnarf(art.data);
	} else
		writetosnarf(art.data);
}

findartifact(id: string): ref Artifact
{
	for(al := artifacts; al != nil; al = tl al)
		if((hd al).id == id)
			return hd al;
	return nil;
}

artzoom(art: ref Artifact): int
{
	if(art.zoom == 0)
		return 100;
	return art.zoom;
}

# --- Renderers ---

renderpdfpage(path: string, page: int, dpi: int): ref Image
{
	if(pdfmod == nil) {
		pdfmod = load PDF PDF->PATH;
		if(pdfmod != nil)
			pdfmod->init(display_g);
	}
	if(pdfmod == nil)
		return nil;
	fdata := readfilebytes(path);
	if(fdata == nil)
		return nil;
	(doc, err) := pdfmod->open(fdata, "");
	if(doc == nil) {
		sys->fprint(stderr, "lucipres: pdf open %s: %s\n", path, err);
		return nil;
	}
	(img, nil) := doc.renderpage(page, dpi);
	doc.close();
	return img;
}

renderimage(path: string): ref Image
{
	bufio := load Bufio Bufio->PATH;
	if(bufio == nil)
		return nil;
	remap := load Imageremap Imageremap->PATH;
	if(remap == nil)
		return nil;
	remap->init(display_g);
	rdpath := RImagefile->READPNGPATH;
	for(ei := len path - 1; ei >= 0; ei--) {
		if(path[ei] == '.') {
			ext := path[ei:];
			if(ext == ".jpg" || ext == ".jpeg")
				rdpath = RImagefile->READJPGPATH;
			else if(ext == ".gif")
				rdpath = RImagefile->READGIFPATH;
			break;
		}
	}
	reader := load RImagefile rdpath;
	if(reader == nil)
		return nil;
	reader->init(bufio);
	fd := bufio->open(path, Bufio->OREAD);
	if(fd == nil)
		return nil;
	(raw, nil) := reader->read(fd);
	if(raw == nil)
		return nil;
	(img, nil) := remap->remap(raw, display_g, 0);
	return img;
}

rendermermaid(art: ref Artifact, imgw: int)
{
	if(mermaidmod == nil) {
		mermaidmod = load Mermaid Mermaid->PATH;
		if(mermaidmod != nil)
			mermaidmod->init(display_g, mainfont, monofont_g);
	}
	if(mermaidmod == nil) {
		sys->fprint(stderr, "lucipres: cannot load mermaid: %r\n");
		art.rendering = 2;
		alt { preseventch <-= "render" => ; * => ; }
		return;
	}
	img: ref Image;
	err: string;
	{
		(img, err) = mermaidmod->render(art.data, imgw);
	} exception e {
	"*" =>
		sys->fprint(stderr, "lucipres: rendermermaid exception: %s\n", e);
		art.rendering = 2;
		alt { preseventch <-= "render" => ; * => ; }
		return;
	}
	if(img == nil) {
		sys->fprint(stderr, "lucipres: rendermermaid failed: %s\n", err);
		art.rendering = 2;
	} else {
		art.rendimg = img;
		art.rendering = 0;
	}
	alt { preseventch <-= "render" => ; * => ; }
}

# --- Table rendering helpers ---

trimcell(s: string): string
{
	i := 0;
	while(i < len s && (s[i] == ' ' || s[i] == '\t')) i++;
	j := len s;
	while(j > i && (s[j-1] == ' ' || s[j-1] == '\t' || s[j-1] == '\n')) j--;
	if(i >= j) return "";
	return s[i:j];
}

tabparsecells(line: string): list of string
{
	cells: list of string;
	i := 0;
	n := len line;
	while(i < n && (line[i] == ' ' || line[i] == '\t')) i++;
	if(i < n && line[i] == '|') i++;
	while(i < n) {
		j := i;
		while(j < n && line[j] != '|') j++;
		cell := trimcell(line[i:j]);
		cells = cell :: cells;
		if(j >= n) break;
		i = j + 1;
	}
	if(cells != nil && hd cells == "")
		cells = tl cells;
	rev: list of string;
	for(; cells != nil; cells = tl cells)
		rev = hd cells :: rev;
	return rev;
}

tabissep(line: string): int
{
	cells := tabparsecells(line);
	if(cells == nil) return 0;
	for(; cells != nil; cells = tl cells) {
		c := hd cells;
		if(len c == 0) return 0;
		for(i := 0; i < len c; i++) {
			ch := c[i];
			if(ch != '-' && ch != ':' && ch != ' ')
				return 0;
		}
	}
	return 1;
}

tabcountcols(line: string): int
{
	n := 0;
	for(cl := tabparsecells(line); cl != nil; cl = tl cl)
		n++;
	return n;
}

# --- Word wrap / split ---

wraptext(text: string, maxw: int): list of string
{
	if(text == nil || text == "")
		return "" :: nil;

	lines: list of string;
	line := "";

	i := 0;
	while(i < len text) {
		while(i < len text && (text[i] == ' ' || text[i] == '\t'))
			i++;
		if(i >= len text)
			break;
		wstart := i;
		while(i < len text && text[i] != ' ' && text[i] != '\t' && text[i] != '\n')
			i++;
		word := text[wstart:i];

		if(i < len text && text[i] == '\n') {
			if(line != "")
				line += " " + word;
			else
				line = word;
			lines = line :: lines;
			line = "";
			i++;
			continue;
		}

		candidate: string;
		if(line != "")
			candidate = line + " " + word;
		else
			candidate = word;

		if(mainfont.width(candidate) > maxw && line != "") {
			lines = line :: lines;
			line = word;
		} else {
			line = candidate;
		}
	}
	if(line != "")
		lines = line :: lines;
	if(lines == nil)
		return "" :: nil;

	rev: list of string;
	for(; lines != nil; lines = tl lines)
		rev = hd lines :: rev;
	return rev;
}

splitlines(text: string): list of string
{
	if(text == nil || text == "")
		return "" :: nil;
	lines: list of string;
	i := 0;
	linestart := 0;
	while(i < len text) {
		if(text[i] == '\n') {
			lines = text[linestart:i] :: lines;
			linestart = i + 1;
		}
		i++;
	}
	if(linestart < len text)
		lines = text[linestart:] :: lines;
	rev: list of string;
	for(; lines != nil; lines = tl lines)
		rev = hd lines :: rev;
	return rev;
}

# --- Attribute parsing (shared) ---

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

# --- Helpers ---

writetosnarf(text: string)
{
	fd := sys->open("/dev/snarf", Sys->OWRITE);
	if(fd == nil)
		return;
	b := array of byte text;
	sys->write(fd, b, len b);
}

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

readfilebytes(path: string): array of byte
{
	fd := sys->open(path, Sys->OREAD);
	if(fd == nil)
		return nil;
	data := array[0] of byte;
	buf := array[8192] of byte;
	for(;;) {
		n := sys->read(fd, buf, len buf);
		if(n <= 0)
			break;
		newdata := array[len data + n] of byte;
		newdata[0:] = data;
		newdata[len data:] = buf[0:n];
		data = newdata;
	}
	if(len data == 0)
		return nil;
	return data;
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

listlen(l: list of string): int
{
	n := 0;
	for(; l != nil; l = tl l)
		n++;
	return n;
}

revarts(l: list of ref Artifact): list of ref Artifact
{
	r: list of ref Artifact;
	for(; l != nil; l = tl l)
		r = hd l :: r;
	return r;
}

appendart(l: list of ref Artifact, a: ref Artifact): list of ref Artifact
{
	if(l == nil)
		return a :: nil;
	r: list of ref Artifact;
	for(; l != nil; l = tl l)
		r = hd l :: r;
	r = a :: r;
	result: list of ref Artifact;
	for(; r != nil; r = tl r)
		result = hd r :: result;
	return result;
}
