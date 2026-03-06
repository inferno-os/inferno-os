implement LuciCtx;

#
# lucictx - Context zone for Lucifer
#
# Receives a sub-Image from the WM tiler (lucifer) and renders the
# context zone into it.  Runs as an independent goroutine.
# Handles resource mounting/unmounting, tool management, and namespace binding.
#

include "sys.m";
	sys: Sys;

include "draw.m";
	draw: Draw;
	Font, Point, Rect, Image, Display, Screen, Pointer: import draw;

include "lucitheme.m";

include "menu.m";

LuciCtx: module
{
	PATH: con "/dis/lucictx.dis";
	init: fn(img: ref Draw->Image, dsp: ref Draw->Display,
	         font: ref Draw->Font,
	         mountpt: string, actid: int,
	         mouse: chan of ref Draw->Pointer,
	         evch:  chan of string,
	         rsz:   chan of ref Draw->Image,
	         req:   chan of string);
};

# Resource mounting base
MNT_BASE: con "/tmp/veltro/mnt";

# --- ADTs ---

PinnedPath: adt {
	label:   string;
	srcpath: string;
	mntdir:  string;
};

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

# Section expand/collapse state
avail_expanded := 1;
toolsec_expanded := 1;
toolavail_expanded := 0;

# Tool management state
activetoolset: list of string;
knowntoolnames: list of string;
pinnedpaths: list of ref PinnedPath;

# Channel references (for filebrowser access)
mousech_g: chan of ref Pointer;
ctxreqch_g: chan of string;
rszch_g: chan of ref Image;

# Section header rects
availhdrrect: Rect;
toolsechdrrect: Rect;
toolavailhdrrect: Rect;

# Catalog entry rects (populated by drawcontext each frame)
ctxentryrects: array of Rect;
nctxentryrects := 0;

# Tool section rects
toolplusrects: array of Rect;
ntoolplusrects := 0;
toolentryrects: array of Rect;
ntoolentryrects := 0;

# Gap rects
gapmenurects: array of Rect;
ngapmenurects := 0;

# Browse / pinned rects
browserect: Rect;
pinnedminusrects: array of Rect;
npinnedminusrects := 0;

# Mounted catalog entry rects (catalog entries with mntpath != "" shown in Mounted section)
catmountedminusrects: array of Rect;
ncatmountedminusrects := 0;
catmountedces: array of ref CatalogEntry;

# File browser state (module-level to avoid stack allocation in inner loop)
brow_dirrects:  array of Rect;
brow_dirnames:  array of string;
brow_ndirs := 0;
brow_filerects: array of Rect;
brow_filenames: array of string;
brow_nfiles := 0;
brow_backrect:   Rect;
brow_bindrect:   Rect;
brow_cancelrect: Rect;

# --- init ---

init(img: ref Draw->Image, dsp: ref Draw->Display,
     font: ref Draw->Font,
     mountpt: string, actid: int,
     mouse: chan of ref Draw->Pointer,
     evch:  chan of string,
     rsz:   chan of ref Draw->Image,
     req:   chan of string)
{
	sys = load Sys Sys->PATH;
	draw = load Draw Draw->PATH;
	stderr = sys->fildes(2);

	mainwin = img;
	display_g = dsp;
	mainfont = font;
	mountpt_g = mountpt;
	actid_g = actid;
	mousech_g = mouse;
	ctxreqch_g = req;
	rszch_g = rsz;

	# Create colors from theme
	lucitheme := load Lucitheme Lucitheme->PATH;
	th := lucitheme->gettheme();
	bgcol = dsp.color(th.bg);
	accentcol = dsp.color(th.accent);
	textcol = dsp.color(th.text);
	text2col = dsp.color(th.text2);
	dimcol = dsp.color(th.dim);
	labelcol = dsp.color(th.label);
	greencol = dsp.color(th.green);
	yellowcol = dsp.color(th.yellow);
	redcol = dsp.color(th.red);
	progbgcol = dsp.color(th.progbg);
	progfgcol = dsp.color(th.progfg);

	# Load menu module
	menumod = load Menu Menu->PATH;
	if(menumod != nil)
		menumod->init(display_g, mainfont);

	# Initialize tool management state — sync from running tools9p if available
	{
		toolsraw := readfile("/tool/tools");
		if(toolsraw != nil && len toolsraw > 0) {
			(nil, tl0) := sys->tokenize(toolsraw, "\n");
			activetoolset = tl0;
		} else {
			# Fallback if tools9p not yet running
			activetoolset = "read" :: "list" :: "find" :: "search" ::
				"write" :: "edit" :: "present" :: "ask" ::
				"diff" :: "json" :: "git" :: "memory" ::
				"websearch" :: "http" :: "mail" ::
				"spawn" :: "gap" :: nil;
		}
	}
	toolsec_expanded = 1;
	toolavail_expanded = 0;
	knowntoolnames = scantoolcatalog();
	pinnedpaths = nil;
	avail_expanded = 1;

	if(actid >= 0)
		loadcontext();
	loadpinnedpaths();

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

			# Tool section header toggle
			if(toolsechdrrect.max.x > toolsechdrrect.min.x &&
					toolsechdrrect.contains(p.xy)) {
				if(toolsec_expanded)
					toolsec_expanded = 0;
				else
					toolsec_expanded = 1;
				tabclicked = 1;
				redrawctx();
			}

			# Tool available sub-section header toggle
			if(!tabclicked && toolsec_expanded &&
					toolavailhdrrect.max.x > toolavailhdrrect.min.x &&
					toolavailhdrrect.contains(p.xy)) {
				if(toolavail_expanded)
					toolavail_expanded = 0;
				else
					toolavail_expanded = 1;
				tabclicked = 1;
				redrawctx();
			}

			# Active tool click — remove on left-click anywhere on entry row
			if(!tabclicked && toolsec_expanded) {
				for(pi := 0; pi < ntoolentryrects; pi++) {
					if(toolentryrects[pi].contains(p.xy)) {
						tidx := 0;
						for(tp := activetoolset; tp != nil; tp = tl tp) {
							if(tidx == pi) {
								removetool(hd tp);
								tabclicked = 1;
								break;
							}
							tidx++;
						}
						break;
					}
				}
			}

			# Available tool click — add on left-click anywhere on entry row
			if(!tabclicked && toolsec_expanded && toolavail_expanded) {
				for(pi := 0; pi < ntoolplusrects; pi++) {
					if(toolplusrects[pi].contains(p.xy)) {
						kidx := 0;
						for(kp := knowntoolnames; kp != nil; kp = tl kp) {
							kname := hd kp;
							isact := 0;
							for(ap := activetoolset; ap != nil; ap = tl ap)
								if(hd ap == kname) { isact = 1; break; }
							if(isact)
								continue;
							if(kidx == pi) {
								addtool(kname);
								tabclicked = 1;
								break;
							}
							kidx++;
						}
						break;
					}
				}
			}

			# Namespaces section heading toggle
			if(!tabclicked &&
					availhdrrect.max.x > availhdrrect.min.x &&
					availhdrrect.contains(p.xy)) {
				if(avail_expanded)
					avail_expanded = 0;
				else
					avail_expanded = 1;
				tabclicked = 1;
				redrawctx();
			}

			# Browse button click
			if(!tabclicked && avail_expanded &&
					browserect.max.x > browserect.min.x &&
					browserect.contains(p.xy)) {
				fpath := filebrowser("/");
				if(fpath != nil && fpath != "")
					bindpath(fpath);
				prevbuttons = 0;
				tabclicked = 1;
				redrawctx();
			}

			# Pinned path click — unbind
			if(!tabclicked && avail_expanded) {
				for(pi := 0; pi < npinnedminusrects; pi++) {
					if(pinnedminusrects[pi].contains(p.xy)) {
						ppidx := 0;
						for(pp2 := pinnedpaths; pp2 != nil; pp2 = tl pp2) {
							if(ppidx == pi) {
								unbindpath(hd pp2);
								tabclicked = 1;
								break;
							}
							ppidx++;
						}
						break;
					}
				}
			}

			# Catalog entry click — toggle mount/unmount
			if(!tabclicked && avail_expanded) {
				for(pi := 0; pi < nctxentryrects; pi++) {
					if(ctxentryrects[pi].contains(p.xy)) {
						k := 0;
						for(cl := catalog; cl != nil; cl = tl cl) {
							if(k == pi) {
								ce := hd cl;
								if(ce.mntpath == "")
									mountresource(ce);
								else
									unmountresource(ce);
								tabclicked = 1;
								break;
							}
							k++;
						}
						break;
					}
				}
			}

			# Mounted catalog entry click — unmount
			if(!tabclicked && avail_expanded) {
				for(pi := 0; pi < ncatmountedminusrects; pi++) {
					if(catmountedminusrects[pi].contains(p.xy)) {
						if(catmountedces != nil && pi < len catmountedces &&
								catmountedces[pi] != nil) {
							unmountresource(catmountedces[pi]);
							tabclicked = 1;
						}
						break;
					}
				}
			}
		}

		# Button-3: context menus
		if((p.buttons & 4) != 0 && (wasdown & 4) == 0) {
			# Tool entry right-click
			if(toolsec_expanded) {
				for(tei := 0; tei < ntoolentryrects; tei++) {
					if(toolentryrects[tei].contains(p.xy)) {
						if(menumod != nil) {
							titems := array[] of {"Remove"};
							tpop := menumod->new(titems);
							tres := tpop.show(mainwin, p.xy, mouse);
							if(tres == 0) {
								tidx2 := 0;
								for(tp2 := activetoolset; tp2 != nil; tp2 = tl tp2) {
									if(tidx2 == tei) {
										removetool(hd tp2);
										break;
									}
									tidx2++;
								}
							}
							redrawctx();
						}
						prevbuttons = 0;
						break;
					}
				}
			}

			# Gap right-click
			for(gei := 0; gei < ngapmenurects; gei++) {
				if(gapmenurects[gei].contains(p.xy)) {
					gapdesc := "";
					gidx := 0;
					for(gp2 := gaps; gp2 != nil; gp2 = tl gp2) {
						if(gidx == gei) {
							gapdesc = (hd gp2).desc;
							break;
						}
						gidx++;
					}
					if(menumod != nil) {
						# Count inactive tools for menu size
						nitems := 1;  # "Resolve"
						for(kp2 := knowntoolnames; kp2 != nil; kp2 = tl kp2) {
							kn2 := hd kp2;
							act2 := 0;
							for(ap2 := activetoolset; ap2 != nil; ap2 = tl ap2)
								if(hd ap2 == kn2) { act2 = 1; break; }
							if(!act2) nitems++;
						}
						nitems++;  # "Browse path..."

						gitems := array[nitems] of string;
						gitems[0] = "Resolve";
						giidx := 1;
						for(kp3 := knowntoolnames; kp3 != nil; kp3 = tl kp3) {
							kn3 := hd kp3;
							act3 := 0;
							for(ap3 := activetoolset; ap3 != nil; ap3 = tl ap3)
								if(hd ap3 == kn3) { act3 = 1; break; }
							if(!act3)
								gitems[giidx++] = "Add tool: " + kn3;
						}
						gitems[giidx] = "Browse path...";

						gpop := menumod->new(gitems);
						gres := gpop.show(mainwin, p.xy, mouse);
						if(gres == 0) {
							resolvegap(gapdesc);
						} else if(gres > 0 && gres < nitems - 1) {
							tname := gitems[gres][len "Add tool: ":];
							addtool(tname);
							resolvegap(gapdesc);
						} else if(gres == nitems - 1) {
							fpath2 := filebrowser("/");
							if(fpath2 != nil && fpath2 != "") {
								bindpath(fpath2);
								resolvegap(gapdesc);
							}
						}
						redrawctx();
					}
					prevbuttons = 0;
					break;
				}
			}

			# Pinned path right-click — unmount
			if(avail_expanded) {
				for(ppi := 0; ppi < npinnedminusrects; ppi++) {
					if(pinnedminusrects[ppi].contains(p.xy)) {
						if(menumod != nil) {
							pitems := array[] of {"Remove"};
							ppop := menumod->new(pitems);
							pres := ppop.show(mainwin, p.xy, mouse);
							if(pres == 0) {
								ppidx2 := 0;
								for(pp3 := pinnedpaths; pp3 != nil; pp3 = tl pp3) {
									if(ppidx2 == ppi) {
										unbindpath(hd pp3);
										break;
									}
									ppidx2++;
								}
							}
							redrawctx();
						}
						prevbuttons = 0;
						break;
					}
				}
			}

			# Mounted catalog entry right-click — unmount
			if(avail_expanded) {
				for(mci := 0; mci < ncatmountedminusrects; mci++) {
					if(catmountedminusrects[mci].contains(p.xy)) {
						if(menumod != nil) {
							mitems := array[] of {"Remove"};
							mpop := menumod->new(mitems);
							mres := mpop.show(mainwin, p.xy, mouse);
							if(mres == 0) {
								if(catmountedces != nil && mci < len catmountedces &&
										catmountedces[mci] != nil)
									unmountresource(catmountedces[mci]);
							}
							redrawctx();
						}
						prevbuttons = 0;
						break;
					}
				}
			}

			# Catalog entry right-click
			for(ei := 0; ei < nctxentryrects; ei++) {
				if(ctxentryrects[ei].contains(p.xy)) {
					k := 0;
					for(cl := catalog; cl != nil; cl = tl cl) {
						if(k == ei) {
							ce := hd cl;
							if(menumod != nil) {
								citems: array of string;
								if(ce.mntpath == "")
									citems = array[] of {"Add"};
								else
									citems = array[] of {"Remove"};
								cpop := menumod->new(citems);
								cres := cpop.show(mainwin, p.xy, mouse);
								if(cres == 0) {
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
					prevbuttons = 0;
					break;
				}
			}
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

	# Reset entry rects and counters at start of each frame
	ngapmenurects = 0;
	ntoolplusrects = 0;
	ntoolentryrects = 0;
	nctxentryrects = 0;
	npinnedminusrects = 0;
	ncatmountedminusrects = 0;
	toolavailhdrrect = Rect((0, 0), (0, 0));
	browserect = Rect((0, 0), (0, 0));

	# --- Resources section (non-tool entries only) ---
	hasnontools := 0;
	for(rchk := resources; rchk != nil; rchk = tl rchk)
		if((hd rchk).rtype != "tool") { hasnontools = 1; break; }

	if(hasnontools) {
		mainwin.text((zone.min.x + pad, y), labelcol, (0, 0), mainfont, "Resources");
		y += mainfont.height + 4;

		for(rp := resources; rp != nil; rp = tl rp) {
			res := hd rp;
			if(res.rtype == "tool")
				continue;
			if(y + mainfont.height > zone.max.y)
				break;
			if(res.lastused > 0 && now - res.lastused > 120000)
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

	# --- Tools section ---
	if(y + mainfont.height > zone.max.y)
		return;
	{
		ind := "▸";
		if(toolsec_expanded) ind = "▾";
		mainwin.text((zone.min.x + pad, y), labelcol, (0, 0), mainfont, "Tools " + ind);
		toolsechdrrect = Rect((zone.min.x, y), (zone.max.x, y + mainfont.height));
		y += mainfont.height + 4;

		if(toolsec_expanded) {
			toolentryrects = array[64] of Rect;

			for(tp := activetoolset; tp != nil; tp = tl tp) {
				tname := hd tp;
				if(y + mainfont.height > zone.max.y)
					break;

				# Activity indicator — look up tool in resources list
				indcol2 := dimcol;
				for(rp2 := resources; rp2 != nil; rp2 = tl rp2) {
					res2 := hd rp2;
					if(res2.rtype == "tool" &&
							(res2.path == tname || res2.label == tname)) {
						if(res2.status == "active" ||
								(res2.lastused > 0 && now - res2.lastused < 3000))
							indcol2 = accentcol;
						else if(res2.status == "streaming")
							indcol2 = greencol;
						break;
					}
				}

				if(ntoolentryrects < len toolentryrects)
					toolentryrects[ntoolentryrects++] = Rect(
						(zone.min.x, y), (zone.max.x, y + mainfont.height));

				tindy := y + (mainfont.height - indh) / 2;
				mainwin.draw(Rect(
					(zone.min.x + pad, tindy),
					(zone.min.x + pad + indw, tindy + indh)),
					indcol2, nil, (0, 0));
				mainwin.text((zone.min.x + pad + indw + 6, y),
					text2col, (0, 0), mainfont, tname);
				y += mainfont.height + 2;
			}

			# Available sub-section
			if(y + mainfont.height <= zone.max.y) {
				y += 4;
				ind2 := "▸";
				if(toolavail_expanded) ind2 = "▾";
				mainwin.text((zone.min.x + pad + 8, y), dimcol, (0, 0), mainfont,
					"Available " + ind2);
				toolavailhdrrect = Rect((zone.min.x, y), (zone.max.x, y + mainfont.height));
				y += mainfont.height + 2;

				if(toolavail_expanded) {
					toolplusrects = array[64] of Rect;

					for(kp := knowntoolnames; kp != nil; kp = tl kp) {
						kname := hd kp;
						if(y + mainfont.height > zone.max.y)
							break;
						# Skip tools already active
						isact := 0;
						for(ap := activetoolset; ap != nil; ap = tl ap)
							if(hd ap == kname) { isact = 1; break; }
						if(isact)
							continue;

						mainwin.text((zone.min.x + pad + 12, y), dimcol, (0, 0),
							mainfont, "○ " + kname);
						if(ntoolplusrects < len toolplusrects)
							toolplusrects[ntoolplusrects++] = Rect(
								(zone.min.x, y),
								(zone.max.x, y + mainfont.height));
						y += mainfont.height + 2;
					}
				}
			}
		}
		y += secgap;
	}

	# --- Gaps section ---
	if(gaps != nil) {
		if(y + mainfont.height > zone.max.y)
			return;
		mainwin.text((zone.min.x + pad, y), labelcol, (0, 0), mainfont, "Gaps");
		y += mainfont.height + 4;

		gapmenurects = array[32] of Rect;
		for(gp := gaps; gp != nil; gp = tl gp) {
			gap := hd gp;
			if(y + mainfont.height > zone.max.y)
				break;
			if(ngapmenurects < len gapmenurects)
				gapmenurects[ngapmenurects++] = Rect(
					(zone.min.x, y), (zone.max.x, y + mainfont.height));
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
		for(bp := bgtasks; bp != nil; bp = tl bp) {
			bg := hd bp;
			if(y + mainfont.height + barh + 4 > zone.max.y)
				break;

			blabel := bg.label;
			if(bg.status != nil && bg.status != "")
				blabel += " [" + bg.status + "]";
			mainwin.text((zone.min.x + pad, y), text2col, (0, 0), mainfont, blabel);
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

	# --- Namespaces section (renamed from "Available") ---
	if(y + mainfont.height > zone.max.y)
		return;
	{
		if(resources != nil || gaps != nil || bgtasks != nil || activetoolset != nil)
			y += secgap;
		nind := "▸";
		if(avail_expanded) nind = "▾";
		mainwin.text((zone.min.x + pad, y), labelcol, (0, 0), mainfont, "Namespaces " + nind);
		availhdrrect = Rect((zone.min.x, y), (zone.max.x, y + mainfont.height));
		y += mainfont.height + 4;

		if(avail_expanded) {
			# ─ Mounted ─ subsection: pinned paths + mounted catalog entries
			hasmounted := pinnedpaths != nil;
			if(!hasmounted) {
				for(mck := catalog; mck != nil; mck = tl mck)
					if((hd mck).mntpath != "") { hasmounted = 1; break; }
			}
			if(hasmounted && y + mainfont.height <= zone.max.y) {
				mainwin.text((zone.min.x + pad, y), dimcol, (0, 0), mainfont, "─ Mounted ─");
				y += mainfont.height + 2;

				# Pinned paths
				if(pinnedpaths != nil) {
					pinnedminusrects = array[32] of Rect;
					for(pp := pinnedpaths; pp != nil; pp = tl pp) {
						ppath := hd pp;
						if(y + mainfont.height > zone.max.y)
							break;
						mainwin.text((zone.min.x + pad, y), greencol, (0, 0), mainfont,
							"● " + ppath.label);
						if(npinnedminusrects < len pinnedminusrects)
							pinnedminusrects[npinnedminusrects++] = Rect(
								(zone.min.x, y),
								(zone.max.x, y + mainfont.height));
						y += mainfont.height + 2;
					}
				}

				# Mounted catalog entries
				catmountedminusrects = array[32] of Rect;
				catmountedces = array[32] of ref CatalogEntry;
				for(ml := catalog; ml != nil; ml = tl ml) {
					mce := hd ml;
					if(mce.mntpath == "")
						continue;
					if(y + mainfont.height > zone.max.y)
						break;
					mainwin.text((zone.min.x + pad, y), greencol, (0, 0), mainfont,
						"● " + mce.name);
					if(ncatmountedminusrects < len catmountedminusrects) {
						catmountedminusrects[ncatmountedminusrects] = Rect(
							(zone.min.x, y),
							(zone.max.x, y + mainfont.height));
						catmountedces[ncatmountedminusrects] = mce;
						ncatmountedminusrects++;
					}
					y += mainfont.height + 2;
				}
				y += 2;
			}

			# Browse button
			if(y + mainfont.height <= zone.max.y) {
				mainwin.text((zone.min.x + pad, y), text2col, (0, 0), mainfont, "Browse...");
				browserect = Rect((zone.min.x, y), (zone.max.x, y + mainfont.height));
				y += mainfont.height + 4;
			}

			# Catalog entries (all: mounted ● and unmounted ○)
			if(catalog != nil) {
				glyphw := mainfont.width("○ ");
				ctxentryrects = array[32] of Rect;

				if(y + mainfont.height <= zone.max.y) {
					mainwin.text((zone.min.x + pad, y), dimcol, (0, 0), mainfont, "─ Available ─");
					y += mainfont.height + 2;
				}

				for(cl := catalog; cl != nil; cl = tl cl) {
					ce := hd cl;
					if(y + mainfont.height > zone.max.y)
						break;
					if(nctxentryrects < len ctxentryrects)
						ctxentryrects[nctxentryrects++] = Rect(
							(zone.min.x, y), (zone.max.x, y + mainfont.height));
					cglyph := "○";
					cgcol := dimcol;
					if(ce.mntpath != "") {
						cglyph = "●";
						cgcol = text2col;
					}
					mainwin.text((zone.min.x + pad, y), cgcol, (0, 0), mainfont, cglyph);
					mainwin.text((zone.min.x + pad + glyphw, y), text2col, (0, 0), mainfont, ce.name);
					y += mainfont.height + 2;
				}
			}
		}
	}

	if(resources == nil && gaps == nil && bgtasks == nil &&
			catalog == nil && pinnedpaths == nil && activetoolset == nil)
		drawcentertext(zone, "No context");
}

drawcentertext(r: Rect, text: string)
{
	tw := mainfont.width(text);
	tx := r.min.x + (r.dx() - tw) / 2;
	ty := r.min.y + (r.dy() - mainfont.height) / 2;
	mainwin.text((tx, ty), dimcol, (0, 0), mainfont, text);
}

# --- File browser ---

drawbrowser(curpath: string, dirs, files: list of string, scroll: int)
{
	zone := mainwin.r;
	pad := 8;
	lineH := mainfont.height + 2;
	y := zone.min.y + pad;

	mainwin.draw(zone, bgcol, nil, (0, 0));

	# Header row: ↑  <path>  Bind ✕
	# Nerd Font icons: U+EAA1 (cod-arrow_up), U+EB15 (cod-link), U+EA76 (cod-close)
	upicon   := "\uEAA1";
	bindlbl  := "\uEB15 Bind";
	closeicon := "\uEA76";
	backw   := mainfont.width(upicon);
	cancelw := mainfont.width(closeicon);
	bindw   := mainfont.width(bindlbl);

	brow_backrect = Rect((zone.min.x + pad, y),
		(zone.min.x + pad + backw, y + lineH));
	mainwin.text((zone.min.x + pad, y), accentcol, (0, 0), mainfont, upicon);

	# Path — truncate from left if too wide
	pathx   := zone.min.x + pad + backw + 6;
	pathend := zone.max.x - pad - cancelw - 6 - bindw - 4;
	disp    := curpath;
	while(len disp > 1 && mainfont.width(disp) > pathend - pathx)
		disp = disp[1:];
	mainwin.text((pathx, y), text2col, (0, 0), mainfont, disp);

	brow_bindrect = Rect(
		(zone.max.x - pad - cancelw - 6 - bindw, y),
		(zone.max.x - pad - cancelw - 6, y + lineH));
	mainwin.text((zone.max.x - pad - cancelw - 6 - bindw, y),
		greencol, (0, 0), mainfont, bindlbl);

	brow_cancelrect = Rect(
		(zone.max.x - pad - cancelw, y),
		(zone.max.x - pad, y + lineH));
	mainwin.text((zone.max.x - pad - cancelw, y), redcol, (0, 0), mainfont, closeicon);

	y += lineH + 2;
	mainwin.draw(Rect((zone.min.x + pad, y), (zone.max.x - pad, y + 1)), dimcol, nil, (0, 0));
	y += 4;

	# --- Multi-column grid layout (Navigator style) ---
	#
	# Calculate column width from widest entry, then pack as many columns
	# as fit in the zone.  scroll counts in rows (each row holds ncols entries).

	usablew := zone.dx() - 2 * pad;
	maxentw := 40;
	for(dw := dirs; dw != nil; dw = tl dw) {
		w := mainfont.width(hd dw + "/");
		if(w > maxentw) maxentw = w;
	}
	for(fw := files; fw != nil; fw = tl fw) {
		w := mainfont.width(hd fw);
		if(w > maxentw) maxentw = w;
	}
	colw  := maxentw + 14;	# entry + inter-column gap
	ncols := usablew / colw;
	if(ncols < 1) ncols = 1;
	if(ncols > 6) ncols = 6;

	skip := scroll * ncols;	# entries to skip due to scroll

	if(brow_dirrects == nil) {
		brow_dirrects = array[512] of Rect;
		brow_dirnames = array[512] of string;
		brow_filerects = array[512] of Rect;
		brow_filenames = array[512] of string;
	}
	brow_ndirs  = 0;
	brow_nfiles = 0;

	# Layout state for visible entries
	vcol  := 0;	# column within current visible row (0..ncols-1)
	vcur  := y;	# y of current visible row

	abs := 0;	# absolute entry index across dirs then files

	# Draw directories
	for(dl := dirs; dl != nil; dl = tl dl) {
		if(abs >= skip) {
			cx := zone.min.x + pad + vcol * colw;
			if(vcur + lineH <= zone.max.y - pad) {
				if(brow_ndirs < len brow_dirrects) {
					brow_dirrects[brow_ndirs] = Rect(
						(cx, vcur), (cx + colw, vcur + lineH));
					brow_dirnames[brow_ndirs] = hd dl;
					brow_ndirs++;
				}
				mainwin.text((cx, vcur), text2col, (0, 0), mainfont, hd dl + "/");
			}
			vcol++;
			if(vcol >= ncols) {
				vcol  = 0;
				vcur += lineH;
			}
		}
		abs++;
	}

	# Separator between dirs and files
	if(files != nil) {
		if(vcol != 0) {
			vcol  = 0;
			vcur += lineH;
		}
		if(vcur + 3 < zone.max.y - pad)
			mainwin.draw(Rect((zone.min.x + pad, vcur + 2),
				(zone.max.x - pad, vcur + 3)), dimcol, nil, (0, 0));
		vcur += 6;

		for(fl := files; fl != nil; fl = tl fl) {
			if(abs >= skip) {
				cx := zone.min.x + pad + vcol * colw;
				if(vcur + lineH <= zone.max.y - pad) {
					if(brow_nfiles < len brow_filerects) {
						brow_filerects[brow_nfiles] = Rect(
							(cx, vcur), (cx + colw, vcur + lineH));
						brow_filenames[brow_nfiles] = hd fl;
						brow_nfiles++;
					}
					mainwin.text((cx, vcur), dimcol, (0, 0), mainfont, hd fl);
				}
				vcol++;
				if(vcol >= ncols) {
					vcol  = 0;
					vcur += lineH;
				}
			}
			abs++;
		}
	}

	mainwin.flush(Draw->Flushnow);
}

filebrowser(startpath: string): string
{
	curpath := startpath;
	if(curpath == nil || curpath == "")
		curpath = "/";

	scroll := 0;
	result := "";
	prevbut := 0;

	for(;;) {
		# Collect directory entries
		dirs: list of string;
		files: list of string;

		fd := sys->open(curpath, Sys->OREAD);
		if(fd != nil) {
			for(;;) {
				(n, ds) := sys->dirread(fd);
				if(n <= 0)
					break;
				for(di := 0; di < len ds; di++) {
					if(ds[di].mode & Sys->DMDIR)
						dirs = ds[di].name :: dirs;
					else
						files = ds[di].name :: files;
				}
			}
		}
		dirs = sortstrlist(dirs);
		files = sortstrlist(files);

		# Draw browser UI (populates brow_* module-level arrays)
		drawbrowser(curpath, dirs, files, scroll);

		# Wait for mouse event or zone resize
		p: ref Pointer;
		alt {
		p = <-mousech_g =>
			;
		newimg := <-rszch_g =>
			mainwin = newimg;
			continue;
		}
		wasdown2 := prevbut;
		prevbut = p.buttons;

		# Mouse wheel scroll
		if(p.buttons & 8) {
			if(scroll > 0) scroll--;
			continue;
		}
		if(p.buttons & 16) {
			scroll++;
			continue;
		}

		# Button-3: cancel
		if((p.buttons & 4) != 0 && (wasdown2 & 4) == 0) {
			result = nil;
			break;
		}

		# Button-1 just pressed
		if(p.buttons == 1 && wasdown2 == 0) {
			# Cancel button
			if(brow_cancelrect.max.x > brow_cancelrect.min.x &&
					brow_cancelrect.contains(p.xy)) {
				result = nil;
				break;
			}
			# Back ([<]) button
			if(brow_backrect.max.x > brow_backrect.min.x &&
					brow_backrect.contains(p.xy)) {
				parent := pathparent(curpath);
				if(parent != curpath) {
					curpath = parent;
					scroll = 0;
				}
				continue;
			}
			# Bind current directory
			if(brow_bindrect.max.x > brow_bindrect.min.x &&
					brow_bindrect.contains(p.xy)) {
				result = curpath;
				break;
			}
			# Directory entry: navigate into it
			clicked := 0;
			for(di2 := 0; di2 < brow_ndirs; di2++) {
				if(brow_dirrects[di2].contains(p.xy)) {
					if(curpath == "/")
						curpath = "/" + brow_dirnames[di2];
					else
						curpath = curpath + "/" + brow_dirnames[di2];
					scroll = 0;
					clicked = 1;
					break;
				}
			}
			if(clicked)
				continue;
			# File entries are displayed for context but not selectable —
			# only [bind] (current directory) is actionable.
		}
	}

	return result;
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

pathbase(s: string): string
{
	if(s == nil || s == "")
		return "";
	# Remove trailing slashes
	while(len s > 1 && s[len s - 1] == '/')
		s = s[0:len s - 1];
	# Find last /
	i := len s - 1;
	while(i > 0 && s[i] != '/')
		i--;
	if(s[i] == '/')
		return s[i + 1:];
	return s;
}

pathparent(s: string): string
{
	if(s == nil || s == "" || s == "/")
		return "/";
	# Remove trailing slashes
	while(len s > 1 && s[len s - 1] == '/')
		s = s[0:len s - 1];
	i := len s - 1;
	while(i > 0 && s[i] != '/')
		i--;
	if(i == 0)
		return "/";
	return s[0:i];
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

	if(ce.rtype == "path") {
		# Local filesystem path: route through tools9p so lucibridge
		# binds it in the agent namespace (not lucifer's).
		writetofile("/tool/ctl", "bindpath " + ce.dial);
		writetofile(mountpt_g + "/ctl",
			"catalog mounted name=" + ce.name + " path=" + ce.dial);
	} else {
		# Network mount via dial: mount into lucifer's namespace at
		# /tmp/veltro/mnt/<slug> (network catalog mounts are separate
		# from agent namespace management).
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
		writetofile(mountpt_g + "/ctl",
			"catalog mounted name=" + ce.name + " path=" + mntdir);
	}
}

unmountresource(ce: ref CatalogEntry)
{
	if(ce == nil || ce.mntpath == "")
		return;
	if(ce.rtype == "path") {
		writetofile("/tool/ctl", "unbindpath " + ce.mntpath);
	} else {
		sys->unmount(nil, ce.mntpath);
	}
	writetofile(mountpt_g + "/ctl", "catalog unmounted " + ce.name);
}

scantoolcatalog(): list of string
{
	fd := sys->open("/dis/veltro/tools", Sys->OREAD);
	if(fd == nil)
		return nil;
	result: list of string;
	for(;;) {
		(n, ds) := sys->dirread(fd);
		if(n <= 0)
			break;
		for(i := 0; i < len ds; i++) {
			nm := ds[i].name;
			if(len nm > 4 && nm[len nm - 4:] == ".dis")
				result = nm[0:len nm - 4] :: result;
		}
	}
	return sortstrlist(result);
}

sortstrlist(l: list of string): list of string
{
	n := 0;
	for(p := l; p != nil; p = tl p)
		n++;
	if(n == 0)
		return nil;
	a := array[n] of string;
	i := 0;
	for(p = l; p != nil; p = tl p)
		a[i++] = hd p;
	# Insertion sort
	for(i = 1; i < n; i++) {
		v := a[i];
		j := i - 1;
		while(j >= 0 && a[j] > v) {
			a[j + 1] = a[j];
			j--;
		}
		a[j + 1] = v;
	}
	result: list of string;
	for(i = n - 1; i >= 0; i--)
		result = a[i] :: result;
	return result;
}

addtool(name: string)
{
	# Guard: skip if already active
	for(tp := activetoolset; tp != nil; tp = tl tp)
		if(hd tp == name)
			return;
	activetoolset = name :: activetoolset;
	writetofile(mountpt_g + "/ctl",
		"resource add path=" + name + " label=" + name + " type=tool status=idle");
	writetofile("/tool/ctl", "add " + name);
	loadcontext();
	redrawctx();
}

removetool(name: string)
{
	newlist: list of string;
	for(tp := activetoolset; tp != nil; tp = tl tp)
		if(hd tp != name)
			newlist = hd tp :: newlist;
	activetoolset = revstrlist(newlist);
	writetofile(mountpt_g + "/ctl", "resource remove " + name);
	writetofile("/tool/ctl", "remove " + name);
	loadcontext();
	redrawctx();
}

resolvegap(desc: string)
{
	writetofile(mountpt_g + "/ctl", "gap resolve desc=" + desc);
	loadcontext();
	redrawctx();
}

bindpath(srcpath: string)
{
	# Register in tools9p; lucibridge reads /tool/paths and binds in its namespace.
	writetofile("/tool/ctl", "bindpath " + srcpath);
	loadpinnedpaths();
	loadcontext();
	redrawctx();
}

unbindpath(pp: ref PinnedPath)
{
	if(pp == nil)
		return;
	writetofile("/tool/ctl", "unbindpath " + pp.srcpath);
	loadpinnedpaths();
	loadcontext();
	redrawctx();
}

# Rebuild pinnedpaths from /tool/paths (authoritative source in tools9p).
loadpinnedpaths()
{
	raw := readfile("/tool/paths");
	(nil, ptl) := sys->tokenize(raw, "\n");
	pinnedpaths = nil;
	for(p := ptl; p != nil; p = tl p) {
		src := hd p;
		if(src == "")
			continue;
		base := pathbase(src);
		if(base == nil || base == "")
			base = "path";
		pinnedpaths = ref PinnedPath(base, src, "") :: pinnedpaths;
	}
	# Reverse to match tools9p order (tools9p prepends, so list is reversed)
	rev: list of ref PinnedPath;
	for(q := pinnedpaths; q != nil; q = tl q)
		rev = hd q :: rev;
	pinnedpaths = rev;
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

revstrlist(l: list of string): list of string
{
	r: list of string;
	for(; l != nil; l = tl l)
		r = hd l :: r;
	return r;
}
