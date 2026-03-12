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
	perm:    string;  # "ro" or "rw" — from /tool/paths
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

NsEntry: adt {
	path:	string;		# /dev/time
	label:	string;		# System Clock
	perm:	string;		# ro, rw, cow
	mounted: int;		# 1 = accessible, 0 = not present
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
nsmanifest: list of ref NsEntry;
agentname := "Agent";
username := "user";

# Section expand/collapse state
agentns_expanded := 1;
toolsec_expanded := 1;
toolavail_expanded := 0;
userns_expanded := 0;

# Tool management state
activetoolset: list of string;
knowntoolnames: list of string;
pinnedpaths: list of ref PinnedPath;

# Path change tracking for timer-based namespace refresh
lastpathsraw := "";

# Channel references (for filebrowser access)
mousech_g: chan of ref Pointer;
ctxreqch_g: chan of string;
rszch_g: chan of ref Image;

# Scroll state for context zone
ctx_scroll := 0;		# pixel offset from top (0 = no scroll)
ctx_content_height := 0;	# total content height in pixels (set by drawcontext)

# Section header rects
agentnshdrrect: Rect;
toolsechdrrect: Rect;
toolavailhdrrect: Rect;
usernshdrrect: Rect;

# Agent namespace entry rects (populated by drawcontext each frame)
nsentryrects: array of Rect;
nnsentryrects := 0;
nsentry_pathrects: array of Rect;	# clickable path portion

# Catalog entry rects (for unmounted catalog entries at bottom of agent NS)
ctxentryrects: array of Rect;
nctxentryrects := 0;

# Tool section rects
toolplusrects: array of Rect;
ntoolplusrects := 0;
toolentryrects: array of Rect;
ntoolentryrects := 0;

# Browse rect (inside user namespace)
browserect: Rect;

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
	if(menumod == nil)
		sys->fprint(stderr, "lucictx: cannot load menu: %r\n");
	else
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
	agentns_expanded = 1;
	userns_expanded = 0;

	# Load agent name and user name
	loadagentname();
	un := readfile("/dev/user");
	if(un != nil && un != "")
		username = strip(un);

	if(actid >= 0)
		loadcontext();
	loadpinnedpaths();
	loadmanifest();

	# Snapshot current paths so timer detects future changes
	raw := readfile("/tool/paths");
	if(raw == nil) raw = "";
	lastpathsraw = raw;

	redrawctx();

	# Context flash timer (animate activity indicator fade-out)
	spawn ctxtimer(evch);

	# Event loop
	prevbuttons := 0;
	for(;;) alt {
	p := <-mouse =>
		wasdown := prevbuttons;
		prevbuttons = p.buttons;

		# Mouse wheel: scroll context zone
		if(p.buttons & 8) {
			scrollstep := mainfont.height + 2;
			if(ctx_scroll >= scrollstep)
				ctx_scroll -= scrollstep;
			else
				ctx_scroll = 0;
			redrawctx();
			continue;
		}
		if(p.buttons & 16) {
			scrollstep := mainfont.height + 2;
			maxscroll := ctx_content_height - mainwin.r.dy();
			if(maxscroll < 0)
				maxscroll = 0;
			ctx_scroll += scrollstep;
			if(ctx_scroll > maxscroll)
				ctx_scroll = maxscroll;
			redrawctx();
			continue;
		}

		# Button-1 just pressed
		if(p.buttons == 1 && wasdown == 0) {
			tabclicked := 0;

			# Agent Namespace header toggle
			if(agentnshdrrect.max.x > agentnshdrrect.min.x &&
					agentnshdrrect.contains(p.xy)) {
				if(agentns_expanded)
					agentns_expanded = 0;
				else
					agentns_expanded = 1;
				tabclicked = 1;
				redrawctx();
			}

			# Tool section header toggle
			if(!tabclicked &&
					toolsechdrrect.max.x > toolsechdrrect.min.x &&
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
			if(!tabclicked && toolsec_expanded) {
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

			# Agent NS entry path click — open file or browse directory
			if(!tabclicked && agentns_expanded) {
				for(pi := 0; pi < nnsentryrects; pi++) {
					if(nsentry_pathrects != nil &&
							pi < len nsentry_pathrects &&
							nsentry_pathrects[pi].max.x > nsentry_pathrects[pi].min.x &&
							nsentry_pathrects[pi].contains(p.xy)) {
						# Find the NsEntry at index pi
						nsi := 0;
						for(nsl := nsmanifest; nsl != nil; nsl = tl nsl) {
							if(nsi == pi) {
								nspath := (hd nsl).path;
								openpath(nspath);
								tabclicked = 1;
								break;
							}
							nsi++;
						}
						break;
					}
				}
			}

			# User Namespace header toggle
			if(!tabclicked &&
					usernshdrrect.max.x > usernshdrrect.min.x &&
					usernshdrrect.contains(p.xy)) {
				if(userns_expanded)
					userns_expanded = 0;
				else
					userns_expanded = 1;
				tabclicked = 1;
				redrawctx();
			}

			# Browse button click (inside user namespace)
			if(!tabclicked && userns_expanded &&
					browserect.max.x > browserect.min.x &&
					browserect.contains(p.xy)) {
				fpath := filebrowser("/");
				if(fpath != nil && fpath != "")
					bindpath(fpath);
				prevbuttons = 0;
				tabclicked = 1;
				redrawctx();
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

			# Agent NS entry right-click — unbind for pinned (user-bound) paths
			if(agentns_expanded && menumod != nil) {
				for(nei := 0; nei < nnsentryrects; nei++) {
					if(nsentryrects[nei].contains(p.xy)) {
						# Find the NsEntry at this index
						nsi2 := 0;
						for(nsl2 := nsmanifest; nsl2 != nil; nsl2 = tl nsl2) {
							if(nsi2 == nei) {
								nse := hd nsl2;
								# Only allow unbind for pinned paths (not infrastructure)
								pp2 := findpinnedpath(nse.path);
								if(pp2 != nil) {
									# Build context menu: toggle perm + unbind
									permlabel := "Set read-only";
									if(pp2.perm == "ro")
										permlabel = "Set read-write";
									nitems := array[] of {permlabel, "Unbind"};
									npop := menumod->new(nitems);
									nres := npop.show(mainwin, p.xy, mouse);
									if(nres == 0)
										togglepathperm(pp2);
									else if(nres == 1)
										unbindpath(pp2);
									redrawctx();
								}
								break;
							}
							nsi2++;
						}
						prevbuttons = 0;
						break;
					}
				}
			}

		}
	ev := <-evch =>
		handleevent(ev);
		redrawctx();
	newimg := <-rsz =>
		mainwin = newimg;
		# Clamp scroll for new window size
		maxscroll := ctx_content_height - mainwin.r.dy();
		if(maxscroll < 0)
			maxscroll = 0;
		if(ctx_scroll > maxscroll)
			ctx_scroll = maxscroll;
		redrawctx();
	}
}

ctxtimer(evch: chan of string)
{
	# Poll interval: fast (1s) while waiting for manifest to appear,
	# slower (5s) once it's loaded and only resource activity needs refresh.
	for(;;) {
		interval := 5000;
		if(nsmanifest == nil)
			interval = 1000;	# poll faster until manifest appears

		sys->sleep(interval);

		needtick := 0;

		# Always tick if manifest hasn't loaded yet
		if(nsmanifest == nil) {
			(ok, nil) := sys->stat("/tmp/veltro/.ns/manifest");
			if(ok >= 0)
				needtick = 1;
		}

		# Tick if /tool/paths changed (namespace bind/unbind from any source)
		if(!needtick) {
			curpaths := readfile("/tool/paths");
			if(curpaths == nil)
				curpaths = "";
			if(curpaths != lastpathsraw) {
				lastpathsraw = curpaths;
				needtick = 1;
			}
		}

		# Also tick for resource activity animation
		if(!needtick) {
			now := sys->millisec();
			for(r := resources; r != nil; r = tl r) {
				res := hd r;
				if(res.status == "active" || (res.lastused > 0 && now - res.lastused < 4000)) {
					needtick = 1;
					break;
				}
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
	if(hasprefix(ev, "context") || ev == "tick") {
		loadcontext();
		loadmanifest();
		loadagentname();
	}
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
	y := zone.min.y + pad - ctx_scroll;
	secgap := 12;
	indw := 10;
	indh := 10;
	now := sys->millisec();

	# Helper: test whether a row at y with given height is visible
	# Draw commands to off-screen coordinates are clipped by the image,
	# but we skip them explicitly to avoid wasted work.
	vis_top := zone.min.y;
	vis_bot := zone.max.y;

	# Reset entry rects and counters at start of each frame
	ntoolplusrects = 0;
	ntoolentryrects = 0;
	nctxentryrects = 0;
	nnsentryrects = 0;
	toolavailhdrrect = Rect((0, 0), (0, 0));
	browserect = Rect((0, 0), (0, 0));
	agentnshdrrect = Rect((0, 0), (0, 0));
	usernshdrrect = Rect((0, 0), (0, 0));

	# ============================================================
	# TOP HALF: Agent's world
	# ============================================================

	# --- Activity section (background tasks) ---
	if(bgtasks != nil) {
		if(y + mainfont.height > vis_top && y < vis_bot)
			mainwin.text((zone.min.x + pad, y), labelcol, (0, 0), mainfont, "Activity");
		y += mainfont.height + 4;

		barh := 6;
		for(bp := bgtasks; bp != nil; bp = tl bp) {
			bg := hd bp;

			blabel := bg.label;
			if(bg.status != nil && bg.status != "")
				blabel += " [" + bg.status + "]";
			if(y + mainfont.height > vis_top && y < vis_bot)
				mainwin.text((zone.min.x + pad, y), text2col, (0, 0), mainfont, blabel);
			y += mainfont.height + 2;

			if(bg.progress != nil && bg.progress != "") {
				pct := strtoint(bg.progress);
				if(pct < 0) pct = 0;
				if(pct > 100) pct = 100;
				barw := zone.dx() - 2 * pad;
				bary := y;
				if(bary + barh > vis_top && bary < vis_bot) {
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
				}
				y += barh + 4;
			}
		}
		y += secgap;
	}

	# --- Agent Namespace section ---
	{
		nind := "▸";
		if(agentns_expanded) nind = "▾";
		if(y + mainfont.height > vis_top && y < vis_bot)
			mainwin.text((zone.min.x + pad, y), labelcol, (0, 0), mainfont,
				agentname + " Namespace " + nind);
		agentnshdrrect = Rect((zone.min.x, y), (zone.max.x, y + mainfont.height));
		y += mainfont.height + 4;

		if(agentns_expanded) {
			nsentryrects = array[64] of Rect;
			nsentry_pathrects = array[64] of Rect;
			glyphw := mainfont.width("● ");

			for(nse := nsmanifest; nse != nil; nse = tl nse) {
				entry := hd nse;

				visible := y + mainfont.height > vis_top && y < vis_bot;

				# Store full row rect for hit-testing
				if(nnsentryrects < len nsentryrects) {
					nsentryrects[nnsentryrects] = Rect(
						(zone.min.x, y), (zone.max.x, y + mainfont.height));
				}

				# Glyph: ● mounted (green), ○ not mounted (dim)
				glyph := "●";
				gcol := greencol;
				if(!entry.mounted) {
					glyph = "○";
					gcol = dimcol;
				}
				if(visible)
					mainwin.text((zone.min.x + pad, y), gcol, (0, 0), mainfont, glyph);

				# Label
				labelx := zone.min.x + pad + glyphw;
				if(visible)
					mainwin.text((labelx, y), text2col, (0, 0), mainfont, entry.label);

				# Path (dimmer, clickable) — right of label
				labelw := mainfont.width(entry.label);
				pathx := labelx + labelw + 8;
				if(visible)
					mainwin.text((pathx, y), dimcol, (0, 0), mainfont, entry.path);

				# Store path rect for click-to-open
				pathw := mainfont.width(entry.path);
				if(nnsentryrects < len nsentry_pathrects) {
					nsentry_pathrects[nnsentryrects] = Rect(
						(pathx, y), (pathx + pathw, y + mainfont.height));
				}

				# Permission badge [ro]/[rw]/[cow] — right-aligned
				if(entry.mounted && visible) {
					badge := "[" + entry.perm + "]";
					badgew := mainfont.width(badge);
					badgex := zone.max.x - pad - badgew;
					badgecol := dimcol;
					if(entry.perm == "rw" || entry.perm == "cow")
						badgecol = yellowcol;
					mainwin.text((badgex, y), badgecol, (0, 0), mainfont, badge);
				}

				if(nnsentryrects < len nsentryrects)
					nnsentryrects++;

				y += mainfont.height + 2;

				# If not mounted, show hint on next line
				if(!entry.mounted) {
					if(y + mainfont.height > vis_top && y < vis_bot)
						mainwin.text((zone.min.x + pad + glyphw, y),
							dimcol, (0, 0), mainfont, "(not mounted)");
					y += mainfont.height + 2;
				}
			}

			# If manifest is empty, show a waiting hint
			if(nsmanifest == nil) {
				if(y + mainfont.height > vis_top && y < vis_bot)
					mainwin.text((zone.min.x + pad, y), dimcol, (0, 0),
						mainfont, "(waiting for agent)");
				y += mainfont.height + 2;
			}
		}
		y += secgap;
	}

	# --- Tools section (two-column layout) ---
	{
		ind := "▸";
		if(toolsec_expanded) ind = "▾";
		if(y + mainfont.height > vis_top && y < vis_bot)
			mainwin.text((zone.min.x + pad, y), labelcol, (0, 0), mainfont, "Tools " + ind);
		toolsechdrrect = Rect((zone.min.x, y), (zone.max.x, y + mainfont.height));
		y += mainfont.height + 4;

		if(toolsec_expanded) {
			toolentryrects = array[64] of Rect;
			toolplusrects = array[64] of Rect;

			# Two-column layout: enabled on left, available on right
			zonew := zone.dx();
			colw := zonew / 2;
			lcol := zone.min.x;
			rcol := zone.min.x + colw;

			# Column headers
			if(y + mainfont.height > vis_top && y < vis_bot) {
				mainwin.text((lcol + pad, y), dimcol, (0, 0), mainfont, "Enabled");
				mainwin.text((rcol + pad, y), dimcol, (0, 0), mainfont, "Available");
			}
			y += mainfont.height + 2;

			# Build available tools list (excluding active)
			availtools: list of string;
			for(kp := knowntoolnames; kp != nil; kp = tl kp) {
				kname := hd kp;
				isact := 0;
				for(ap := activetoolset; ap != nil; ap = tl ap)
					if(hd ap == kname) { isact = 1; break; }
				if(!isact)
					availtools = kname :: availtools;
			}
			# Reverse to preserve order
			ravail: list of string;
			for(; availtools != nil; availtools = tl availtools)
				ravail = hd availtools :: ravail;
			availtools = ravail;

			# Render both columns in parallel, row by row
			tp := activetoolset;
			avp := availtools;
			while(tp != nil || avp != nil) {
				visible := y + mainfont.height > vis_top && y < vis_bot;

				# Left column: enabled tool
				if(tp != nil) {
					tname := hd tp;

					# Activity indicator color
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
							(lcol, y), (rcol, y + mainfont.height));

					if(visible) {
						tindy := y + (mainfont.height - indh) / 2;
						mainwin.draw(Rect(
							(lcol + pad, tindy),
							(lcol + pad + indw, tindy + indh)),
							indcol2, nil, (0, 0));
						mainwin.text((lcol + pad + indw + 6, y),
							text2col, (0, 0), mainfont, tname);
					}

					tp = tl tp;
				}

				# Right column: available tool
				if(avp != nil) {
					aname := hd avp;

					if(visible)
						mainwin.text((rcol + pad, y), dimcol, (0, 0),
							mainfont, "○ " + aname);
					if(ntoolplusrects < len toolplusrects)
						toolplusrects[ntoolplusrects++] = Rect(
							(rcol, y),
							(zone.max.x, y + mainfont.height));

					avp = tl avp;
				}

				y += mainfont.height + 2;
			}
		}
		y += secgap;
	}

	# ============================================================
	# DIVIDER: horizontal rule separating agent world from user world
	# ============================================================
	{
		divy := y + 3;
		if(divy + 1 > vis_top && divy < vis_bot)
			mainwin.draw(Rect(
				(zone.min.x + pad, divy),
				(zone.max.x - pad, divy + 1)),
				dimcol, nil, (0, 0));
		y += 8;
	}

	# ============================================================
	# BOTTOM HALF: User's world
	# ============================================================

	# --- User Namespace section ---
	{
		uind := "▸";
		if(userns_expanded) uind = "▾";
		if(y + mainfont.height > vis_top && y < vis_bot)
			mainwin.text((zone.min.x + pad, y), labelcol, (0, 0), mainfont,
				username + " Namespace " + uind);
		usernshdrrect = Rect((zone.min.x, y), (zone.max.x, y + mainfont.height));
		y += mainfont.height + 4;

		if(userns_expanded) {
			# Browse button — clicking opens filebrowser
			if(y + mainfont.height > vis_top && y < vis_bot) {
				mainwin.text((zone.min.x + pad, y), text2col, (0, 0), mainfont,
					"Browse...");
			}
			browserect = Rect((zone.min.x, y), (zone.max.x, y + mainfont.height));
			y += mainfont.height + 4;

			# Show pinned paths
			if(pinnedpaths != nil) {
				for(pp := pinnedpaths; pp != nil; pp = tl pp) {
					ppath := hd pp;
					if(y + mainfont.height > vis_top && y < vis_bot) {
						mainwin.text((zone.min.x + pad, y), greencol, (0, 0), mainfont,
							"● " + ppath.label);
						mainwin.text((zone.min.x + pad + mainfont.width("● " + ppath.label) + 8, y),
							dimcol, (0, 0), mainfont, ppath.srcpath);
					}
					y += mainfont.height + 2;
				}
			}
		}
	}

	if(nsmanifest == nil && bgtasks == nil && catalog == nil && activetoolset == nil) {
		if(ctx_scroll == 0)
			drawcentertext(zone, "No context");
	}

	# Record total content height for scroll clamping
	ctx_content_height = y - (zone.min.y - ctx_scroll) + pad;
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
	if(mainwin == nil)
		return;
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
			if(mainwin == nil) {
				result = nil;
				break;
			}
			continue;
		}
		if(p == nil)
			continue;
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
			# File entry click: launch .dis apps or open in edit
			for(fi := 0; fi < brow_nfiles; fi++) {
				if(brow_filerects[fi].contains(p.xy)) {
					fpath: string;
					if(curpath == "/")
						fpath = "/" + brow_filenames[fi];
					else
						fpath = curpath + "/" + brow_filenames[fi];
					if(islaunchabledis(fpath))
						launchdisapp(fpath);
					else if(len fpath > 4 && fpath[len fpath - 4:] == ".dis")
						sys->fprint(sys->fildes(2), "lucictx: skipping non-launchable .dis: %s\n", fpath);
					else {
						has9p := ensureeditor();
						openineditor(fpath, has9p);
					}
					break;
				}
			}
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

loadagentname()
{
	s := readfile("/tmp/veltro/.ns/agentname");
	if(s != nil && s != "")
		agentname = strip(s);
	else
		agentname = "Agent";
}

loadmanifest()
{
	nsmanifest = nil;
	raw := readfile("/tmp/veltro/.ns/manifest");
	if(raw == nil)
		return;
	(nil, lines) := sys->tokenize(raw, "\n");
	for(; lines != nil; lines = tl lines) {
		line := hd lines;
		attrs := parseattrs(line);
		path := getattr(attrs, "path");
		if(path == nil || path == "")
			continue;
		label := getattr(attrs, "label");
		if(label == nil) label = path;
		perm := getattr(attrs, "perm");
		if(perm == nil) perm = "ro";
		# Check if path is currently accessible (in user namespace)
		mounted := 0;
		(ok, nil) := sys->stat(path);
		if(ok >= 0)
			mounted = 1;
		nsmanifest = ref NsEntry(path, label, perm, mounted) :: nsmanifest;
	}
	# Append pinned paths (user-bound via Browse) as agent NS entries.
	# These are paths the agent gains access to via /tool/paths → lucibridge.
	# If a pinned path already appears in the manifest (from -p at startup),
	# override its perm with the authoritative value from /tool/paths.
	for(pp := pinnedpaths; pp != nil; pp = tl pp) {
		p := hd pp;
		# Check if already in manifest (e.g. from -p flag at startup)
		existing: ref NsEntry;
		for(chk := nsmanifest; chk != nil; chk = tl chk)
			if((hd chk).path == p.srcpath) { existing = hd chk; break; }
		if(existing != nil) {
			# Override perm from /tool/paths (authoritative)
			existing.perm = p.perm;
			continue;
		}
		mounted := 0;
		(ok2, nil) := sys->stat(p.srcpath);
		if(ok2 >= 0)
			mounted = 1;
		nsmanifest = ref NsEntry(p.srcpath, p.label, p.perm, mounted) :: nsmanifest;
	}

	# Reverse to preserve manifest order (pinned paths appear at end)
	rev: list of ref NsEntry;
	for(q := nsmanifest; q != nil; q = tl q)
		rev = hd q :: rev;
	nsmanifest = rev;
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

openpath(path: string)
{
	if(path == nil || path == "")
		return;
	(ok, dir) := sys->stat(path);
	if(ok < 0) {
		sys->fprint(sys->fildes(2), "lucictx: openpath stat failed: %s: %r\n", path);
		return;
	}
	if(dir.mode & Sys->DMDIR) {
		# Directory: open file browser at this path
		fpath := filebrowser(path);
		if(fpath != nil && fpath != "")
			bindpath(fpath);
		redrawctx();
	} else if(islaunchabledis(path)) {
		# Launchable .dis app: run in presentation zone
		launchdisapp(path);
	} else if(len path > 4 && path[len path - 4:] == ".dis") {
		# Non-launchable .dis bytecode: skip (not useful in editor)
		sys->fprint(sys->fildes(2), "lucictx: skipping non-launchable .dis: %s\n", path);
	} else {
		# File: open in edit (ensure it's running first)
		has9p := ensureeditor();
		openineditor(path, has9p);
	}
}

# Allowed dis path prefixes for GUI app launch from context zone.
# Must match the whitelist in lucifer.b.
ALLOWED_DIS_PREFIXES: con "/dis/wm/:/dis/charon/:/dis/xenith/";

# Check if path is a launchable .dis app (ends in .dis, under allowed prefix).
islaunchabledis(path: string): int
{
	if(len path < 5 || path[len path - 4:] != ".dis")
		return 0;
	# Check allowed prefixes
	prefixes := "/dis/wm/" :: "/dis/charon/" :: "/dis/xenith/" :: nil;
	for(pl := prefixes; pl != nil; pl = tl pl) {
		pfx := hd pl;
		if(len path >= len pfx && path[0:len pfx] == pfx)
			return 1;
	}
	return 0;
}

# Launch a .dis app into the presentation zone.
# Derives a short id from the filename (e.g. "/dis/wm/clock.dis" -> "clock").
launchdisapp(path: string)
{
	# Extract app name from path for artifact id
	name := path;
	for(i := len path - 1; i >= 0; i--) {
		if(path[i] == '/') {
			name = path[i+1:];
			break;
		}
	}
	# Strip .dis suffix
	if(len name > 4 && name[len name - 4:] == ".dis")
		name = name[0:len name - 4];

	pctl := sys->sprint("%s/activity/%d/presentation/ctl", mountpt_g, actid_g);
	cmd := sys->sprint("create id=%s type=app label=%s dis=%s", name, name, path);
	writetofile(pctl, cmd);
	writetofile(pctl, "center id=" + name);
}

# Send "open <path>" to edit. Use 9P if available, else real-file IPC.
openineditor(path: string, has9p: int)
{
	cmd := "open " + path;
	if(has9p) {
		fd := sys->open("/edit/ctl", Sys->OWRITE);
		if(fd != nil) {
			b := array of byte cmd;
			n := sys->write(fd, b, len b);
			if(n == len b)
				return;
		}
		sys->fprint(sys->fildes(2), "lucictx: openineditor 9P failed, using real-file: %r\n");
	}
	# Real-file IPC: edit polls /tmp/veltro/edit/ctl on timer ticks
	wfd := sys->create("/tmp/veltro/edit/ctl", Sys->OWRITE, 8r666);
	if(wfd != nil) {
		b := array of byte cmd;
		sys->write(wfd, b, len b);
	}
}

# Ensure edit is running. If /edit/ctl doesn't exist, create a
# presentation artifact to launch it in the presentation zone.
ensureeditor(): int
{
	# Check 9P path first (fast, instant open)
	fd := sys->open("/edit/ctl", Sys->OREAD);
	if(fd != nil) {
		fd = nil;
		return 1;	# 9P available
	}
	# Launch via presentation system (harmless if already running)
	sys->fprint(sys->fildes(2), "lucictx: ensureeditor: launching edit\n");
	pctl := sys->sprint("%s/activity/%d/presentation/ctl", mountpt_g, actid_g);
	cmd := "create id=edit type=app dis=/dis/wm/edit.dis label=Edit";
	writetofile(pctl, cmd);
	writetofile(pctl, "center id=edit");
	# Poll until /edit/ctl appears
	for(i := 0; i < 20; i++) {
		sys->sleep(250);
		fd = sys->open("/edit/ctl", Sys->OREAD);
		if(fd != nil) {
			fd = nil;
			sys->fprint(sys->fildes(2), "lucictx: ensureeditor: 9P ready after %dms\n", (i+1)*250);
			return 1;
		}
	}
	sys->fprint(sys->fildes(2), "lucictx: ensureeditor: no 9P, using real-file IPC\n");
	return 0;
}

# Find a PinnedPath matching the given source path, or nil if not found.
findpinnedpath(path: string): ref PinnedPath
{
	for(pp := pinnedpaths; pp != nil; pp = tl pp)
		if((hd pp).srcpath == path)
			return hd pp;
	return nil;
}

bindpath(srcpath: string)
{
	# Register in tools9p; lucibridge reads /tool/paths and binds in its namespace.
	writetofile("/tool/ctl", "bindpath " + srcpath);
	loadpinnedpaths();
	loadmanifest();
	loadcontext();
	redrawctx();
}

unbindpath(pp: ref PinnedPath)
{
	if(pp == nil)
		return;
	writetofile("/tool/ctl", "unbindpath " + pp.srcpath);
	loadpinnedpaths();
	loadmanifest();
	loadcontext();
	redrawctx();
}

# Toggle a pinned path's permission between "ro" and "rw".
# Sends "setperm <path> <newperm>" to /tool/ctl.
togglepathperm(pp: ref PinnedPath)
{
	if(pp == nil)
		return;
	newperm := "ro";
	if(pp.perm == "ro")
		newperm = "rw";
	writetofile("/tool/ctl", "setperm " + pp.srcpath + " " + newperm);
	loadpinnedpaths();
	loadcontext();
	redrawctx();
}

# Rebuild pinnedpaths from /tool/paths (authoritative source in tools9p).
# Format: "path perm" per line (e.g. "/n/local/Users/pdfinn/tmp rw").
loadpinnedpaths()
{
	raw := readfile("/tool/paths");
	(nil, ptl) := sys->tokenize(raw, "\n");
	pinnedpaths = nil;
	for(p := ptl; p != nil; p = tl p) {
		line := hd p;
		if(line == "")
			continue;
		# Parse "path perm" — default perm is "rw" for backward compat
		(src, perm) := splitpathperm(line);
		if(src == "")
			continue;
		base := pathbase(src);
		if(base == nil || base == "")
			base = "path";
		pinnedpaths = ref PinnedPath(base, src, "", perm) :: pinnedpaths;
	}
	# Reverse to match tools9p order (tools9p prepends, so list is reversed)
	rev: list of ref PinnedPath;
	for(q := pinnedpaths; q != nil; q = tl q)
		rev = hd q :: rev;
	pinnedpaths = rev;
}

# Split "path [perm]" into (path, perm). Default perm is "rw".
splitpathperm(s: string): (string, string)
{
	for(i := len s - 1; i > 0; i--) {
		if(s[i] == ' ') {
			tail := s[i+1:];
			if(tail == "ro" || tail == "rw")
				return (s[0:i], tail);
			break;
		}
	}
	return (s, "rw");
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
	if(fd == nil) {
		sys->fprint(sys->fildes(2), "lucictx: writetofile open failed: %s: %r\n", path);
		return;
	}
	b := array of byte text;
	n := sys->write(fd, b, len b);
	if(n != len b)
		sys->fprint(sys->fildes(2), "lucictx: writetofile short write: %s: wrote %d of %d: %r\n", path, n, len b);
	else if(path == "/edit/ctl")
		sys->fprint(sys->fildes(2), "lucictx: writetofile OK: %s <- %s\n", path, text);
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
		if(n > 214748364)
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
