implement Charon;

include "common.m";
include "debug.m";

sys: Sys;
CU: CharonUtils;
	ByteSource, MaskedImage, CImage, ImageCache, ReqInfo, Header, 
	ResourceState, config, max, min, X: import CU;

D: Draw;
	Point, Rect, Font, Image, Display, Screen: import D;

S: String;
U: Url;
	Parsedurl: import U;
L: Layout;
	Frame, Loc, Control: import L;
I: Img;
	ImageSource: import I;

B: Build;
	Item, Dimen: import B;

E: Events;
	Event: import E;

J: Script;

G: Gui;

C : Ctype;

include "sh.m"; 

# package up info related to a navigation command
GoSpec: adt {
	kind: int;				# GoNormal, etc.
	url: ref Parsedurl;		# destination (absolute)
	meth: int;				# HGet or HPost
	body: string;			# used if HPost
	target: string;			# name of target frame
	auth: string;			# optional auth info
	histnode: ref HistNode;	# if kind is GoHistnode

	newget: fn(kind: int, url: ref Parsedurl, target: string) : ref GoSpec;
	newpost: fn(url: ref Parsedurl, body, target: string) : ref GoSpec;
	newspecial: fn(kind: int, histnode: ref HistNode) : ref GoSpec;
	equal: fn(a: self ref GoSpec, b: ref GoSpec) : int;
};

GoNormal, GoReplace, GoLink, GoHistnode, GoSettext: con iota;

# Information about a set of frames making up the screen
DocConfig: adt {
	framename: string;		# nonempty, except possibly for topconfig
	title: string;
	initconfig: int;			# true unless this is a frameset and some subframe changed
	gospec: cyclic ref GoSpec;
	# TODO: add current y pos and form field values

	equal: fn(a: self ref DocConfig, b: ref DocConfig) : int;
	equalarray: fn(a1: array of ref DocConfig, a2: array of ref DocConfig) : int;
};

# Information about a particular screen configuration
HistNode: adt {
	topconfig: cyclic ref DocConfig;			# config of top (whole doc, or frameset root)
	kidconfigs: cyclic array of ref DocConfig;	# configs for kid frames (if a frameset)
	preds: cyclic list of ref HistNode;	# edges in (via normal navigation)
	succs: cyclic list of ref HistNode;	# edges out (via normal navigation)
	findid : int;
	findchain : cyclic list of ref HistNode;

	addedge: fn(a: self ref HistNode, b: ref HistNode, atob: int);
	copy: fn(a: self ref HistNode) : ref HistNode;
};

History: adt {
	h: array of ref HistNode;	# all visited HistNodes, in LRU order
	n: int;				# h[0:n] is valid part of h
	findid : int;

	add: fn(h: self ref History, f: ref Frame, g: ref GoSpec, navkind: int);
	update: fn(h: self ref History, f: ref Frame);
	find: fn(h: self ref History, k: int) : ref HistNode;
	print: fn(h: self ref History);
	histinfo: fn(h: self ref History) : (int, string, string, string);
	findurl: fn(h: self ref History, s: string) : ref HistNode;
};

# Authentication strings
AuthInfo: adt {
	realm: string;
	credentials: string;
};

auths: list of ref AuthInfo = nil;

history : ref History;
keyfocus: ref Control;
mouseover: ref B->Anchor;
mouseoverfr: ref Frame;
grabctl: ref Control;
popupctl: ref Control;

SP : con 8;			# a spacer for between controls
SP2 : con 4;			# half of SP
SP3 : con 2;
pgrp := 0;
gopgrp := 0;
dbg := 0;
warn := 0;
dbgres := 0;
doscripts := 0;

top, curframe: ref Frame;
mainwin: ref Image;
p0 := Point(0,0);

context: ref Draw->Context;
opener: chan of string;

sendopener(s: string)
{
	if(opener != nil){
		alt{
			opener <- = s =>
				;
			* =>
				;
		}
	}
}

hasopener(): int
{
	return opener != nil;
}

init(ctxt: ref Draw->Context, argl: list of string)
{
	chctxt := ref Context(ctxt, argl, nil, nil, nil);
	initc(chctxt);
}

initc(ctxt: ref Context)
{
	sys = load Sys Sys->PATH;
	if (ctxt == nil)
		fatalerror("bad args\n");
	opener = ctxt.c;
	argl := ctxt.args;
	context = ctxt.ctxt;

	(retval, nil) := sys->stat("/net/tcp");
	if(retval < 0)
		sys->bind("#I", "/net", sys->MREPL);
	(retval, nil) = sys->stat("/net/cs");
	if(retval < 0)
		startcs();

	pgrp = sys->pctl(sys->NEWPGRP, nil);
	CU = load CharonUtils CharonUtils->PATH;
	if(CU == nil)
		fatalerror(sys->sprint("Couldn't load %s\n", CharonUtils->PATH));

	ech := chan of ref Event;
	errpath := CU->init(load Charon SELF, CU, argl, ech, ctxt.cksrv, ctxt.ckclient);
	if(errpath != "")
		fatalerror(sys->sprint("Couldn't load %s\n", errpath));
	ctxt = nil;

	sys = load Sys Sys->PATH;
	D = load Draw Draw->PATH;
	S = load String String->PATH;
	U = load Url Url->PATH;
	if (U != nil)
		U->init();
	E = CU->E;
	L = CU->L;
	I = CU->I;
	B = CU->B;
	J = CU->J;
	G = CU->G;
	C = CU->C;

	dbg = int (CU->config).dbg['d'];
	warn = dbg ||  int (CU->config).dbg['w'];
	dbgres = int (CU->config).dbg['r'];
	doscripts = (CU->config).doscripts && J != nil;
	if(dbg && (CU->config).dbgfile != "") {
		dfile := sys->create((CU->config).dbgfile, sys->OWRITE, 8r666);
		if(dfile != nil) {
			sys->dup(dfile.fd, 1);
		}
	}
	curres := ResourceState.cur();
	newres: ResourceState;
	if(dbgres) {
		(CU->startres).print("starting resources");
		curres = ResourceState.cur();
	}

	context = G->init(context, CU);
	if(dbgres) {
		newres = ResourceState.cur();
		newres.since(curres).print("difference after G->init (made screen windows)");
		curres = newres;
	}
	mainwin = G->mainwin;

	# L->init() was deferred until after G was inited
	L->init(CU);
	if(dbgres) {
		newres = ResourceState.cur();
		newres.since(curres).print("difference after L->init (loaded Build, Lex)");
		curres = newres;
	}
	(CU->imcache).init();
	if(dbgres) {
		newres = ResourceState.cur();
		newres.since(curres).print("difference after (CU->imcache).init");
		curres = newres;
	}
	start();
	if(J != nil)
		J->frametreechanged(top);
	startpage := config.starturl;
	g := GoSpec.newget(GoNormal, CU->makeabsurl(startpage), "_top");
	if(dbgres) {
		newres = ResourceState.cur();
		newres.since(curres).print("difference after initial configure");
		curres = newres;
	}
	spawn plumbwatch();
	spawn go(g);

	sendopener("B");

Forloop:
	for(;;) {
		ev := <- ech;

		if(dbg > 1) {
			pick de := ev {
			Emouse =>
				if(dbg > 2 || de.mtype != E->Mmove)
					sys->print("%s\n", ev.tostring());
			* =>
				sys->print("%s\n", ev.tostring());
			}
		}
		pick  e := ev {
		Ekey =>
			g = nil;
			case e.keychar {
			E->Kdown =>
				curframe.yscroll(L->CAscrollpage, -1);
			E->Kup =>
				curframe.yscroll(L->CAscrollpage, 1);
			E->Khome =>
				curframe.yscroll(L->CAscrollpage, -10000);
			E->Kend => 
				curframe.yscroll(L->CAscrollpage, 10000);	
			E->Kaup =>
				curframe.yscroll(L->CAscrollline, -1);
			E->Kadown => 
				curframe.yscroll(L->CAscrollline, 1);	
			* =>
				handlekey(e);
			}
		Emouse =>
			g = handlemouse(e);
		Ereshape =>
			mainwin = G->mainwin;
			redraw(1);
			curframe = top;
			g = GoSpec.newspecial(GoHistnode, history.find(0));
		Equit =>
			break Forloop;
		Estop =>
			if(gopgrp != 0)
				stop();
			g = nil;
		Eback =>
			g = GoSpec.newspecial(GoHistnode, history.find(-1));
		Efwd =>
			g = GoSpec.newspecial(GoHistnode, history.find(1));
		Eform =>
			formaction(e.frameid, e.formid, e.ftype, 0);
			g = nil;
		Eformfield =>
			formfieldaction(e.frameid, e.formid, e.fieldid, e.fftype);
			g = nil;
		Ego =>
			case e.gtype {
			E->EGnormal =>
				url := CU->makeabsurl(e.url);
				if (url != nil)
					g = GoSpec.newget(GoNormal,url, e.target);
				else
					g = nil;
			E->EGreplace =>
				g = GoSpec.newget(GoReplace, U->parse(e.url), e.target);
			E->EGreload =>
				g = GoSpec.newspecial(GoHistnode, history.find(0));
			E->EGforward =>
				g = GoSpec.newspecial(GoHistnode, history.find(1));
			E->EGback =>
				g = GoSpec.newspecial(GoHistnode, history.find(-1));
			E->EGdelta =>
				g = GoSpec.newspecial(GoHistnode, history.find(e.delta));
			E->EGlocation =>
				g = GoSpec.newspecial(GoHistnode, history.findurl(e.url));
			}
		Esubmit =>
			if(e.subkind == CU->HGet)
				g = GoSpec.newget(GoNormal, e.action, e.target);
			else {
				g = GoSpec.newpost(e.action, e.data, e.target);
			}
		Escroll =>
			f := findframe(top, e.frameid);
			if (f != nil)
				f.scrollabs(e.pt);
			g = nil;
		Escrollr =>
			f := findframe(top, e.frameid);
			if (f != nil)
				f.scrollrel(e.pt);
			g = nil;
		Esettext =>
			f := findframe(top, e.frameid);
			if (f != nil)
				g = ref GoSpec (GoSettext, e.url, 0, e.text, f.name, "", nil);
		Elostfocus =>
			setfocus(nil);
			g = nil;
		Edismisspopup =>
			if (popupctl != nil)
				setfocus(popupctl.donepopup());
			popupctl = nil;
			grabctl = nil;
		}

		if (g == nil)
			continue;

		if (g.kind != GoSettext) {
			if (g.url != nil) {
				scheme := g.url.scheme;
				if (scheme == "javascript") {
					if (doscripts)
						spawn dojsurl(g);
					continue;
				}
				if (!CU->schemeok(scheme)) {
					url := g.url.tostring();
					if (plumbsend(url, "url") == -1)
						G->setstatus(X("bad URL", "gui")+": "+url);
					continue;
				}
			}
		}

		if(gopgrp != 0)
			stop();
		spawn go(g);
	}
	finish();
}

mkprog(c: Command, ctxt: ref Draw->Context, args: list of string)
{
	sys->pctl(Sys->NEWPGRP|Sys->NEWFD, list of {0, 1, 2});
	c->init(ctxt, args);
}

start()
{
	top = Frame.new();
	curframe = top;
	history = ref History(nil, 0, 0);
	
	keyfocus = nil;
	mouseover = nil;
	redraw(1);
}

redraw(resized: int)
{
	im := mainwin;
	if(resized) {
#		top.r = im.r.inset(2*L->ReliefBd);
		top.r = im.r;
		top.cim = mainwin;
		top.reset();
		(CU->imcache).resetlimits();
	}
	im.clipr = im.r;
#	L->drawrelief(im, top.r.inset(-L->ReliefBd), L->ReliefRaised);
#	L->drawrelief(im, top.r, L->ReliefSunk);
	L->drawfill(im, top.r, CU->White);
	G->flush(im.r);
#	im.clipr = top.r;
}

# Return a Loc representing a control in the frame f
frameloc(c: ref Control, f: ref Frame) : ref Loc
{
	loc := Loc.new();
	loc.add(L->LEframe, f.r.min);
	loc.le[loc.n-1].frame = f;
	if (c != nil) {
		loc.add(L->LEcontrol, c.r.min);
		loc.le[loc.n-1].control = c;
	}
	return loc;
}

resetkeyfocus(f: ref Frame)
{
	# determine if focus is in frame f or one of its sub-frames
	if (keyfocus == nil)
		return;

	for (focusf := keyfocus.f; focusf != nil; focusf = focusf.parent) {
		if (focusf == f) {
			keyfocus = nil;
			break;
		}
	}
	# current focus not in frameset being modified - leave as is
}

ctlmouse(e: ref Event.Emouse, ctl, grab: ref Control): ref Control
{
	ev := E->SEnone;
	(action, newgrab) := ctl.domouse(e.p, e.mtype, grab);
	case (action) {
	L->CAbuttonpush =>
		if(doscripts && ctl.ff != nil && ctl.ff.evmask)
			ev = E->SEonclick;
		else
			pushaction(ctl, e.p.sub(ctl.r.min));
	L->CAkeyfocus =>
		setfocus(ctl);
	L->CAchanged =>
		# Select Formfield - selection has changed
		ev = E->SEonchange;
	L->CAselected =>
		# text input Formfield - text selection has changed
		ev = E->SEonselect;
	L->CAdopopup =>
		popupctl = ctl.dopopup();
		if (popupctl != nil)
			setfocus(popupctl);
	L->CAdonepopup =>
		setfocus(ctl.donepopup());
		ev = E->SEonchange;
		popupctl = nil;
	}
	if (doscripts && ctl.ff != nil && (ctl.ff.evmask & ev)) {
		se := ref E->ScriptEvent(ev, ctl.f.id, ctl.ff.form.formid, ctl.ff.fieldid,
				-1, -1, e.p.x, e.p.y, 1, nil, nil, 0);
		J->jevchan <-= se;
	}
	return newgrab;
}

mainwinmouse(e: ref Event.Emouse) : (ref GoSpec, ref Control)
{
	p := e.p;
	g : ref GoSpec;
	ctl : ref Control;
	newgrab : ref Control;
	domouseout := 0;
	loc : ref Loc;
	if(mouseover != nil)
		domouseout = 1;

	loc = top.find(p, nil);
	if(loc != nil) {
		if(dbg > 1)
			loc.print("mouse loc");
		f := loc.lastframe();
		hasscripts := f.doc.hasscripts;
		if(e.mtype != E->Mmove)
			curframe = f;
		n1 := loc.n-1;
		case loc.le[n1].kind {
		L->LEitem =>
			it := loc.le[n1].item;
			if (it.anchorid < 0)
				break;

			a : ref Build->Anchor = nil;
			for(al := f.doc.anchors; al != nil; al = tl al) {
				a = hd al;
				if(a.index == it.anchorid)
					break;
			}
			if (al == nil)
				break;

			if(dbg > 1)
				sys->print("in anchor %d, href=%s\n", a.index, a.href.tostring());
			if(doscripts && a.evmask) {
				if(a == mouseover) {
					domouseout = 0;	# still over same anchor
				} else if(e.mtype == E->Mmove) {
					if(domouseout) {
						if(mouseover.evmask & E->SEonmouseout) {
							se := ref E->ScriptEvent(E->SEonmouseout, mouseoverfr.id, -1, -1, mouseover.index, -1, 0, 0, 0, nil, nil, 0);
							J->jevchan <-= se;
						}
						domouseout = 0;
					}
					mouseover = a;
					mouseoverfr = f;
					if(a.evmask & E->SEonmouseover) {
						se := ref E->ScriptEvent(E->SEonmouseover, f.id, -1, -1, a.index, -1, e.p.x, e.p.y, 0, nil, nil, 0);
						J->jevchan <-= se;
					}
				}
				if (e.mtype == E->Mlbuttonup || e.mtype == E->Mldrop) {
					if(a.evmask & E->SEonclick) {
						se := ref E->ScriptEvent(E->SEonclick, f.id, -1, -1, a.index, -1, 0, 0, 0, nil, nil, 0);
						J->jevchan <-= se;
						break;
					}
					ctl = nil;
				}
			}
			if(e.mtype == E->Mlbuttonup || e.mtype == E->Mldrop) {
				g = anchorgospec(it, a, loc.pos);
				if (g == nil)
					break;
			} else if(e.mtype == E->Mmbuttonup) {
				g = anchorgospec(it, a, loc.pos);
				if (g == nil)
					break;
				url := g.url.tostring();
				G->setstatus(url);
				G->snarfput(url);
				g = nil;
			}
		L->LEcontrol =>
			ctl = loc.le[n1].control;
		}
	}
	if (ctl != nil)
		newgrab = ctlmouse(e, ctl, nil);
	if(newgrab == nil && domouseout && doscripts) {
		if(mouseover.evmask & E->SEonmouseout) {
			se := ref E->ScriptEvent(E->SEonmouseout,
				mouseoverfr.id, -1, -1, mouseover.index, -1, 0, 0, 0, nil, nil, 0);
			J->jevchan <-= se;
		}
		mouseoverfr = nil;
		mouseover = nil;
	}
	return (g, newgrab);
}

dojsurl(g : ref GoSpec)
{
	f := curframe;
	case g.target {
	"_top" =>
		f = top;
	"_self" =>
		; # curframe is already OK
	"_parent" =>
		if(f.parent != nil)
			f = f.parent;
	"_blank" =>
		f = top; # we don't create new browsers...
	* =>
		# this is recommended "current practice"
		f = findnamedframe(f, g.target);
		if(f == nil) {
			f = findnamedframe(top, g.target);
			if(f == nil)
				f = top;
		}
	}

	jev := ref E->ScriptEvent (E->SEscript, f.id, -1, -1, -1, -1, 0, 0, 0, g.url.path, chan of string, 0);
	J->jevchan <-= jev;
	v := <- jev.reply;
	if (v != nil) {
		ev := ref Event.Esettext(f.id, g.url, v);
		E->evchan <-= ev;
	}
}

# If mouse event results in command to navigate somewhere else,
# return a GoSpec ref, else nil.
handlemouse(e: ref Event.Emouse): ref GoSpec
{
	g: ref GoSpec;
	ctl := grabctl;
	if (popupctl != nil)
		ctl = popupctl;
	if (ctl != nil)
		grabctl = ctlmouse(e, ctl, grabctl);
	else if (e.p.in(mainwin.r))
		(g, grabctl) = mainwinmouse(e);
	return g;
}

setfocus(newc : ref Control)
{
	newf, oldf: ref Frame;
	if (newc != nil)
		newf = newc.f;

	oldc := keyfocus;
	if (oldc != nil)
		oldf = oldc.f;
	
	if (oldc != nil && oldc != newc)
		oldc.losefocus(1);
	if (oldf != nil && oldf != newf)
		oldf.focus(0, 1);
	if (newf != nil && newf != oldf)
		newf.focus(1,1);
	if (newc != nil && newc != oldc)
		newc.gainfocus(1);
	keyfocus = newc;
}

handlekey(e: ref Event.Ekey)
{
	c := keyfocus;
	if (c == nil)
		return;

	pick ce := c {
	Centry =>
		case c.dokey(e.keychar) {
		L->CAreturnkey =>
			if(c.ff != nil) {
				spawn form_submit(c.f, c.ff.form, p0, c, 1);
				return;
			}
		L->CAtabkey =>
			# if control in a form - move focus to next focus-able control
			if (c.ff != nil) {
				found := 0;
				form := c.ff.form;
				nextff : ref B->Formfield;
				for (ffl := form.fields; ffl != nil; ffl = tl ffl) {
					ff := hd ffl;
					if (ff == c.ff) {
						found = 1;
						continue;
					}
					if (ff.ftype == B->Ftext || ff.ftype == B->Fpassword) {
						if (nextff == nil || found)
							nextff = ff;
						if (found)
							break;
					}
				}
				if (nextff != nil)
					formfield_focus(c.f, nextff);
			}
		}
	}
	return;
}

fileexist(file: string) :int
{
		fd := sys->open(file, sys->OREAD);
		if (fd == nil)
			return 0;
		else
			return 1;
}

go(g: ref GoSpec)
{
	gopgrp = sys->pctl(sys->NEWPGRP, nil);
	spawn goproc(g);

	# got to make netget the thread with the gopgrp thread,
	# since it runs until killed, and killing a pgrp needs an active
	# thread
	CU->netget();
}

goproc(g: ref GoSpec)
{
	origkind := g.kind;
	hn : ref HistNode = nil;
	doctext := "";
	case origkind {
	GoNormal or
	GoReplace or
	GoSettext =>
		;
	GoHistnode =>
		hn = g.histnode;
		if(hn == nil)
			return;
		g = hn.topconfig.gospec;
	}
	case g.target {
	"_top" =>
		curframe = top;
	"_self" =>
		; # curframe is already OK
	"_parent" =>
		if(curframe.parent != nil)
			curframe = curframe.parent;
	"_blank" =>
		curframe = top; # we don't create new browsers...
	* =>
		# this is recommended "current practice"
		curframe = findnamedframe(curframe, g.target);
		if(curframe == nil) {
			curframe = findnamedframe(top, g.target);
			if(curframe == nil)
				curframe = top;
		}
	}

	f := curframe;
	if(dbg) {
		sys->print("\n\nGO TO %s\n", g.url.tostring());
		if(g.target != "_top")
			sys->print("target frame name=%s\n", f.name);
	}
	G->progress <-= (-1, G->Pstart, 0, "");
	err := "";
	status := "Done";

	if((origkind == GoNormal || origkind == GoReplace || origkind == GoLink) && g.url.frag != "" 
			&& f.doc != nil && f.doc.src != nil && CU->urlequal(g.url, f.doc.src))
		go_local(f, g.url.frag);
	else {
		if (g.kind == GoSettext)
			settext(g, f, g.body);
		else
			err = get(g, f, origkind, hn);

		if(doscripts && J->defaultStatus != "")
			status = J->defaultStatus;
	}
	if(err != nil) {
		status = err;
		G->progress <-= (-1, G->Perr, 100, err);
	} else 
		G->progress <-= (-1, G->Pdone, 0, nil);
		
	G->setstatus(status);
	checkrefresh(f);
}

settext(g : ref GoSpec, f : ref Frame, text : string) : string
{
	sdest := g.url.tostring();
	G->setstatus(X("Fetching", "gui") + " " + sdest);
	bs := CU->stringreq(text);
	G->seturl(sdest);
	history.add(f, g, GoNormal);
	resetkeyfocus(f);
	L->layout(f, bs, 0);
	if (J != nil)
		J->framedone(f, f.doc.hasscripts);
	history.update(f);
	error := "";
	if(f.kids != nil) {
		if(J != nil)
			J->frametreechanged(f);
		nkids := len f.kids;
		kdone := chan of (ref Frame, string);
		for(kl := f.kids; kl != nil; kl = tl kl) {
			k := hd kl;
			if(k.src != nil) {
				gs := GoSpec.newget(GoNormal, k.src, "_self");
				if(dbg)
					sys->print("get child frame %s\n", gs.url.tostring());
				spawn getproc(gs, k, GoNormal, nil, kdone);
			}
		}
		while (nkids--) {
			(k, e) := <- kdone;
			if (error != nil)
				error = e;
			checkrefresh(k);
		}
	}

	if (J != nil) {
#this code should be split off as it is duplicated from get()
		# at this point all sub-frames and images have been loaded
		# Optimise this! so as only do it if a doc in the frameset
		# has script/event code
		J->jevchan <-= ref E->ScriptEvent(E->SEonload, f.id, -1, -1, -1, -1, -1, -1, -1, nil, nil, 0);
		if (doscripts && f.doc.hasscripts) {
			for(itl := f.doc.images; itl != nil; itl = tl itl) {
				it := hd itl;
				if(it.genattr == nil || !it.genattr.evmask)
					continue;
				ev := E->SEnone;
				pick im := it {
				Iimage =>
					case im.ci.complete {
					# correct to equate these two ?
					Img->Mimnone or
					Img->Mimerror =>
						ev = E->SEonerror;
					Img->Mimdone =>
						ev = E->SEonload;
					}
					if(im.genattr.evmask & ev)
						J->jevchan <-= ref E->ScriptEvent(ev, f.id, -1, -1, -1, im.imageid, -1, -1, -1, nil, nil, 0);
				}
			}
		}
	}
	return error;
}

getproc(g: ref GoSpec, f: ref Frame, origkind: int, hn: ref HistNode, done : chan of (ref Frame, string))
{
	done <-= (f, get(g, f, origkind, hn));
}

get(g: ref GoSpec, f: ref Frame, origkind: int, hn: ref HistNode) : string
{
	curres, newres: ResourceState;
	if(dbgres) {
		(CU->imcache).clear();
		curres = ResourceState.cur();
	}
	sdest := g.url.tostring();
        G->setstatus(X("Fetching", "gui") + " " + sdest);
	bsmain : ref ByteSource;
	hdr : ref Header;
	ri := ref ReqInfo(g.url, g.meth, array of byte g.body, g.auth, g.target);
	authtried := 0;
	realm := "";
	auth := "";
	error := "";
	for(nredirs := 0; ; nredirs++) {
		bsmain = CU->startreq(ri);
		error = bsmain.err;
		if(error != "") {
			CU->freebs(bsmain);
			return error;
		}
		CU->waitreq(bsmain::nil);
		error = bsmain.err;
		if(error != "") {
			CU->freebs(bsmain);
			return error;
		}
		hdr = bsmain.hdr;
		(use, e, challenge, newurl) := CU->hdraction(bsmain, 1, nredirs);
		error = e;
		if(challenge != nil) {
			if(authtried) {
				# we already tried once; give up
				error = "Need authorization";
				use = 1;
			}
			else {
				(realm, auth) = getauth(challenge);
				if(auth != "") {
					ri.auth = auth;
					authtried = 1;
					CU->freebs(bsmain);
					continue;
				}
				else {
					error = "Need authorization";
					use = 1;
				}
			}
		}
		if (error == nil) {
			if (hdr.code != CU->HCOk)
				error = CU->hcphrase(hdr.code);
			if(authtried) {
				# it succeeded; add to auths list so don't have to ask again
				auths = ref AuthInfo(realm, auth) :: auths;
			}
		}
		if(newurl != nil) {
			ri.url = newurl;
			# some sites (e.g., amazon.com) assume that POST turns into
			# GET on redirect (maybe this is just http 1.0?)
			ri.method = CU->HGet;
			CU->freebs(bsmain);
			continue;
		}
		if(use == 0) {
			CU->freebs(bsmain);
			return error;
		}
		break;
	}
	if(dbgres > 1) {
		newres = ResourceState.cur();
		newres.since(curres).print("resources to get header");
		curres = newres;
	}
	if(hdr.mtype == CU->TextHtml || hdr.mtype == CU->TextPlain ||
					I->supported(hdr.mtype)) {
		G->seturl(sdest);
		history.add(f, g, origkind);
		resetkeyfocus(f);
		srcdata := L->layout(f, bsmain, origkind == GoLink);
		if (J != nil)
			J->framedone(f, f.doc.hasscripts);
		history.update(f);
		if(dbgres > 1) {
			newres = ResourceState.cur();
			newres.since(curres).print("resources to get page and do layout");
			curres = newres;
		}
		if(f.kids != nil) {
			if(J != nil)
				J->frametreechanged(f);
			i := 0;
			nkids := len f.kids;
			kdone := chan of (ref Frame, string);
			for(kl := f.kids; kl != nil; kl = tl kl) {
				k := hd kl;
				if(k.src != nil) {
					if(hn != nil)
						gs := hn.kidconfigs[i].gospec;
					else
						gs = GoSpec.newget(GoNormal, k.src, "_self");
					if(dbg)
						sys->print("get child frame %s\n", gs.url.tostring());
					gokind := GoLink;
					if (origkind != GoLink)
						gokind = GoNormal;
					spawn getproc(gs, k, gokind, nil, kdone);
				}
				i++;
			}
			while (nkids--) {
				(k, err) := <- kdone;
				if (error == nil)
					# we currently only capture the first error
					# as we only have one palce to report it
					error = err;
				checkrefresh(k);
			}
		}

		if (J != nil) {
			# at this point all sub-frames and images have been loaded
			J->jevchan <-= ref E->ScriptEvent(E->SEonload, f.id, -1, -1, -1, -1, -1, -1, -1, nil, nil, 0);
			if (doscripts && f.doc.hasscripts) {
				for(itl := f.doc.images; itl != nil; itl = tl itl) {
					it := hd itl;
					if(it.genattr == nil || !it.genattr.evmask)
						continue;
					ev := E->SEnone;
					pick im := it {
					Iimage =>
						case im.ci.complete {
						# correct to equate these two ?
						Img->Mimnone or
						Img->Mimerror =>
							ev = E->SEonerror;
						Img->Mimdone =>
							ev = E->SEonload;
						}
						if(im.genattr.evmask & ev)
							J->jevchan <-= ref E->ScriptEvent(ev, f.id, -1, -1, -1, im.imageid, -1, -1, -1, nil, nil, 0);
					}
				}
			}
		}

		if(g.url.frag != "")
			go_local(f, g.url.frag);
	}
	else {
		error = X("Unsupported media type", "gui")+ " "+CU->mnames[hdr.mtype];
		# Optionally put a save-as dialog up here.
		if((CU->config).offersave)
			dosaveas(bsmain);
		CU->freebs(bsmain);
	}
	if(dbgres == 1) {
		newres = ResourceState.cur();
		newres.since(curres).print("resources to do page");
		curres = newres;
	}
	return error;
}

# Scroll frame f so that destination hyperlink loc is at top of view
go_local(f: ref Frame, loc: string)
{
	if(dbg)
		sys->print("go to local destination %s\n", loc);
	for(ld := f.doc.dests; ld != nil; ld = tl ld) {
		d := hd ld;
		if(d.name == loc) {
			dloc := f.find(p0, d.item);
			if(dloc == nil) {
				if(warn)
					sys->print("couldn't find item for destination anchor %s\n", loc);
				return;
			}
			p := f.sptolp(dloc.le[dloc.n-1].pos);
			f.yscroll(L->CAscrollabs, p.y);
			return;
		}
	}
	# special location names...
	l := S->tolower(loc);
	if(l == "top" || l == "home"){
		f.yscroll(L->CAscrollabs, 0);
		return;
	}
	if(l == "end" || l=="bottom"){
		f.yscroll(L->CAscrollabs, f.totalr.max.y);
		return;
	}
	if(warn)
		sys->print("couldn't find destination anchor %s\n", loc);
}

stripwhite(s: string) : string
{
	j := 0;
	n := len s;
	for(i := 0; i < n; i++) {
		c := s[i];
		if(c < C->NCTYPE && C->ctype[c]==C->W)
			continue;
		s[j++] = c;
	}
	if(j < n)
		s = s[0:j];
	return s;
}

# If refresh has been set in f (i.e., client pull),
# pause the appropriate amount of time and then go to new place
checkrefresh(f: ref Frame)
{
	if(f.doc != nil && f.doc.refresh != "") {
		seconds := 0;
		url : ref Parsedurl = nil;
		refresh := stripwhite(f.doc.refresh);
		(n, l) := sys->tokenize(refresh, ";");
		if(n > 0) {
			seconds = int hd l;
			if(n > 1) {
				s := hd tl l;
				if(len s > 4 && S->tolower(s[0:4]) == "url=") {
					url = U->mkabs(U->parse(s[4:]), f.doc.base);
				}
			}
		}
		spawn dorefresh(f, seconds, url);
	}
}

dorefresh(f: ref Frame, seconds: int, url: ref Parsedurl)
{
	sys->sleep(seconds * 1000);
	e : ref Event;
	if(url == nil)
		e = ref Event.Ego(nil, f.name, 0, E->EGreload);
	else
		e = ref Event.Ego(url.tostring(), f.name, 0, E->EGnormal);
	E->evchan <-= e;
}

# Do depth first search from f, looking for frame with given name.
findnamedframe(f: ref Frame, name: string) : ref Frame
{
	if(f.name == name)
		return f;
	for(l := f.kids; l != nil; l = tl l) {
		k := hd l;
		a := findnamedframe(k, name);
		if(a != nil)
			return a;
	}
	return nil;
}

# Similar, but look for frame id, starting from f
findframe(f: ref Frame, id: int) : ref Frame
{
	if(f.id == id)
		return f;
	for(l := f.kids; l != nil; l = tl l) {
		k := hd l;
		a := findframe(k, id);
		if(a != nil)
			return a;
	}
	return nil;
}

# Return Gospec resulting from button up in anchor a, at offset pos inside item it.
anchorgospec(it: ref Item, a: ref B->Anchor, p: Point) : ref GoSpec
{
	g : ref GoSpec;
	u := a.href;
	target := a.target;
	pick i := it {
	Iimage =>
		ci := i.ci;
		if(ci.mims != nil) {
			if(i.map != nil) {
				(u, target) = findhit(i.map, p, ci.width, ci.height);
			}
			else if(u != nil && u.scheme != "javascript" && (it.state&B->IFsmap)) {
				# copy u, add ?x,y
				x := min(max(p.x-(int i.hspace + int i.border),0),ci.width-1);
				y := min(max(p.y-(int i.vspace + int i.border),0),ci.height-1);
				u = ref *a.href;
				u.query = string x + "," + string y;
			}
		}
	Ifloat =>
		return anchorgospec(i.item, a, p);
	}

	if(u != nil)
		g = GoSpec.newget(GoLink, u, target);
	return g;
}

# Control c has been pushed.
# Find the form it is in and perform required action (reset, or submit).
pushaction(c: ref Control, pt: Point)
{
	pick b := c {
	Cbutton =>
		ff := b.ff;
		f := b.f;
		if(ff != nil) {
			case ff.ftype {
			B->Fsubmit or B->Fimage =>
				spawn form_submit(c.f, ff.form, pt, c, 1);
			B->Freset =>
				spawn form_reset(f, ff.form);
			}
		}
	}
}

# if onsubmit==1, then raise onsubmit event (if handler present)
form_submit(fr: ref Frame, frm: ref B->Form, p: Point, submitctl: ref Control, onsubmit: int)
{
	submitfield : ref B->Formfield;
	if (submitctl != nil)
		submitfield = submitctl.ff;

	if(submitctl != nil && tagof(submitctl) == tagof(Control.Centry)) {
		# Via CR, so only submit if there is a submit button (first one is the default)
		firstsubmit : ref B->Formfield;
		for(l := frm.fields; l != nil; l = tl l) {
			f := hd l;
			if (f.ftype == B->Fsubmit) {
				firstsubmit = f;
				break;
			}
		}
		if (firstsubmit == nil)
			return;
		submitfield = firstsubmit;
	}
	if(doscripts && fr.doc.hasscripts && onsubmit && (frm.evmask & E->SEonsubmit)) {
		c := chan of string;
		J->jevchan <-= ref E->ScriptEvent(E->SEonsubmit, fr.id, frm.formid, -1, -1, -1, -1, -1, -1, nil, c, 0);
		if(<-c == nil)
			return;
	}
	v := "";
	sep := "";
	radiodone : list of string = nil;
floop:
	for(l := frm.fields; l != nil; l = tl l) {
		f := hd l;
		if(f.name == "")
			continue;
		val := "";
		c: ref Control;
		if(f.ctlid >= 0)
			c = fr.controls[f.ctlid];
		case f.ftype {
			B->Ftext or B->Fpassword or B->Ftextarea =>
				if(c != nil)
					pick e := c {
					Centry =>
						val = e.s;
					}
				if(val != "" && f.name == "_ISINDEX_") {
					# just the index terms after the "?"
					if(sep != "")
						v = v + sep;
					sep = "&";
					v = v + ucvt(val);
					break floop;
				}
			B->Fcheckbox or B->Fradio =>
				if(f.ftype == B->Fradio) {
					# Need the following to catch case where there
					# is more than one radiobutton with the same name
					# and value.
					for(rl := radiodone; rl != nil; rl = tl rl)
						if(hd rl == f.name)
							continue floop;
				}
				checked := 0;
				if(c != nil)
					pick cb := c {
					Ccheckbox =>
						checked = cb.flags & L->CFactive;
					}
				if(checked) {
					val = f.value;
					if(f.ftype == B->Fradio)
						radiodone = f.name :: radiodone;
				}
				else
					continue;
			B->Fhidden =>
				val = f.value;
			B->Fsubmit =>
				if(submitctl != nil && f == submitctl.ff && f.name != "_no_name_submit_")
					val = f.value;
				else
					continue;
			B->Fselect =>
				if(c != nil)
					pick s := c {
					Cselect =>
						for(i := 0; i < len s.options; i++) {
							if(s.options[i].selected) {
								if(sep != "")
									v = v + sep;
								sep = "&";
								v = v + ucvt(f.name) + "=" + ucvt(s.options[i].value);
							}
						}
						continue;
					}
			B->Fimage =>
				if(submitctl != nil && f == submitctl.ff) {
					if(sep != "")
						v = v + sep;
					sep = "&";
					v = v + ucvt(f.name + ".x") + "=" + ucvt(string max(p.x,0))
						+ sep + ucvt(f.name + ".y") + "=" + ucvt(string max(p.y,0));
					continue;
				}
		}
#		if(val != "") {
			if(sep != "")
				v = v + sep;
			sep = "&";
			v = v + ucvt(f.name) + "=" + ucvt(val);
#		}
	}
	action := ref *frm.action;
	if (frm.method == CU->HGet) {
		if (action.query != "" && v != "")
			action.query += "&";
		action.query += v;
		v = "";
	}
#	action.query = v;
	E->evchan <-= ref Event.Esubmit(frm.method, action, v, frm.target);
}

hexdigit := "0123456789ABCDEF";
urlchars := array [128] of {
	'a' to 'z' => byte 1,
	'A' to 'Z' => byte 1,
	'0' to '9' => byte 1,
	'-' or '/' or '$' or '_' or '@' or '.' or '!' or '*' or '\'' or '(' or ')' => byte 1,
	* => byte 0
};

ucvt(s: string): string
{
	b := array of byte s;
	u := "";
	for(i := 0; i < len b; i++) {
		c := int b[i];
		if (c < len urlchars && int urlchars[c])
			u[len u] = c;
		else if(c == ' ')
			u[len u] = '+';
		else {
			u[len u] = '%';
			u[len u] = hexdigit[(c>>4)&15];
			u[len u] = hexdigit[c&15];
		}
	}
	return u;
}

form_reset(fr: ref Frame, frm: ref B->Form)
{
	if(doscripts && fr.doc.hasscripts && (frm.evmask & E->SEonreset)) {
		c := chan of string;
		J->jevchan <-= ref E->ScriptEvent(E->SEonreset, fr.id, frm.formid, -1, -1, -1, -1, -1, -1, nil, c, 0);
		if(<-c == nil)
			return;
	}
	for(fl := frm.fields; fl != nil; fl = tl fl) {
		a := hd fl;
		if(a.ctlid >= 0)
			fr.controls[a.ctlid].reset();
	}
#	fr.cim.flush(D->Flushnow);
}

formaction(frameid, formid, ftype, onsubmit: int)
{
	if(dbg > 1)
		sys->print("formaction %d %d %d %d\n", frameid, formid, ftype, onsubmit);
	f := findframe(top, frameid);
	if(f != nil) {
		d := f.doc;
		if(d != nil) {
			for(fl := d.forms; fl != nil; fl = tl fl) {
				frm := hd fl;
				if(frm.formid == formid) {
					if(ftype == E->EFsubmit)
						spawn form_submit(f, frm, Point(0,0), nil, onsubmit);
					else
						spawn form_reset(f, frm);
				}
			}
		}
	}
}

formfield_blur(f: ref Frame, ff: ref B->Formfield)
{
	if(ff.ftype != B->Fhidden) {
		c := f.controls[ff.ctlid];
		if(!(c.flags & L->CFhasfocus))
			return;
		# lose focus quietly - don't raise "onblur" event for the given control
		c.losefocus(0);
		setfocus(nil);
	}
}

formfield_focus(f: ref Frame, ff: ref B->Formfield)
{
	if(ff.ftype != B->Fhidden) {
		c := f.controls[ff.ctlid];
		if(c.flags & L->CFhasfocus)
			return;
		# gain focus quietly - don't raise "onfocus" event for the given control
		c.gainfocus(0);
		setfocus(c);
	}
}

# simulate a mouse click, but don't trigger onclick event
formfield_click(f: ref Frame, frm: ref B->Form, ff: ref B->Formfield)
{
	c := f.controls[ff.ctlid];
	case ff.ftype {
	B->Fcheckbox or
	B->Fradio or
	B->Fbutton =>
		c.domouse(p0, E->Mlbuttonup, nil);
	B->Fsubmit =>
		spawn form_submit(f, frm, p0, c, 1);
	B->Freset =>
		spawn form_reset(f, frm);
	}
}

formfield_select(f: ref Frame, ff: ref B->Formfield)
{
	case ff.ftype {
	B->Ftext or
	B->Fselect or
	B->Ftextarea =>
		ctl := f.controls[ff.ctlid];
		pick c := ctl {
		Centry =>
			c.sel = (0, len c.s);
			ctl.draw(1);
		}
	}
}

formfieldaction(frameid, formid, fieldid, fftype: int)
{
	if(dbg > 1)
		sys->print("formfieldaction %d %d %d %d\n", frameid, formid, fieldid, fftype);
	f := findframe(top, frameid);
	if(f == nil || f.doc == nil)
		return;

	# find form in frame
	frm : ref B->Form;
	for(fl := f.doc.forms; fl != nil; fl = tl fl) {
		if((hd fl).formid == formid) {
			frm = hd fl;
			break;
		}
	}
	if(frm == nil)
		return;

	# find formfield in form
	ff : ref B->Formfield;
	for(ffl := frm.fields; ffl != nil; ffl = tl ffl) {
		if((hd ffl).fieldid == fieldid) {
			ff = hd ffl;
			break;
		}
	}
	if(ff == nil || ff.ctlid < 0)
		return;

	# perform action
	case fftype {
	E->EFFblur =>
		formfield_blur(f, ff);
	E->EFFfocus =>
		formfield_focus(f, ff);
	E->EFFclick =>
		formfield_click(f, frm, ff);
	E->EFFselect =>
		formfield_select(f, ff);
	E->EFFredraw =>
		c := f.controls[ff.ctlid];
		pick ctl := c {
		Cselect =>
			sel := 0;
			for (i := 0; i < len ctl.options; i++) {
				if (ctl.options[i].selected) {
					sel = i;
					break;
				}
			}
			if (sel > len ctl.options - ctl.nvis)
				sel = len ctl.options - ctl.nvis;
			ctl.first = sel;
		}
		c.draw(1);
	}
}

# Find hit in a local map
findhit(map: ref B->Map, p: Point, w, h: int) : (ref Parsedurl, string)
{
	x := p.x;
	y := p.y;
	dflt : ref Parsedurl = nil;
	dflttarg := "";
	for(al := map.areas; al != nil; al = tl al) {
		a := hd al;
		c := a.coords;
		nc := len c;
		x1 := 0;
		y1 := 0;
		x2 := 0;
		y2 := 0;
		if(nc >= 2) {
			x1 = d2pix(c[0], w);
			y1= d2pix(c[1], h);
			if(nc > 2) {
				x2 = d2pix(c[2], w);
				if(nc > 3)
					y2 = d2pix(c[3], h);
			}
		}
		hit := 0;
		case a.shape {
		"rect" or "rectangle" =>
			if(nc == 4)
				hit = x1 <= x && x <= x2 &&
					y1 <= y && y <= y2;
		"circ" or "circle" =>
			if(nc == 3) {
				xd := x - x1;
				yd := y - y1;
				hit = xd*xd + yd*yd <= x2*x2;
			}
		"poly" or "polygon" =>
			np := nc / 2;
			hit = 0;
			xr := real x;
			yr := real y;
			j := np - 1;
			for(i := 0; i < np; j = i++) {
				xi := real d2pix(c[2*i], w);
				yi := real d2pix(c[2*i+1], h);
				xj := real d2pix(c[2*j], w);
				yj := real d2pix(c[2*j+1], h);
				if ((((yi<=yr) && (yr<yj)) ||
				     ((yj<=yr) && (yr<yi))) &&
				    (xr < (xj - xi) * (yr - yi) / (yj - yi) + xi))
					hit = !hit;
			}
		"def" or "default" =>
			dflt = a.href;
			dflttarg = a.target;
		}
		if(hit)
			return (a.href, a.target);
	}
	return (dflt, dflttarg);
}

d2pix(d: B->Dimen, tot: int) : int
{
	ans := d.spec();
	if(d.kind() == B->Dpercent)
		ans = (ans * tot) / 100;
	return ans;
}
GoSpec.newget(kind: int, url: ref Parsedurl, target: string) : ref GoSpec
{
	return ref GoSpec(kind, url, CU->HGet, "", target, "", nil);
}

GoSpec.newpost(url: ref Parsedurl, body, target: string) : ref GoSpec
{
	return ref GoSpec(GoNormal, url, CU->HPost, body, target, "", nil);
}

GoSpec.newspecial(kind: int, hn: ref HistNode) : ref GoSpec
{
	return ref GoSpec(kind, nil, 0, "", "", "", hn);
}

GoSpec.equal(a: self ref GoSpec, b: ref GoSpec) : int
{
	if(a.url == nil || b.url == nil)
		return 0;
	return CU->urlequal(a.url, b.url) && a.meth == b.meth && a.body == b.body;
}

DocConfig.equal(a: self ref DocConfig, b: ref DocConfig) : int
{
	return a.framename == b.framename && a.gospec.equal(b.gospec);
}

DocConfig.equalarray(a1: array of ref DocConfig, a2: array of ref DocConfig) : int
{
	n := len a1;
	if(n != len a2)
		return 0;
	for(i := 0; i < n; i++) {
		if(a1[i] == nil || a2[i] == nil)
			continue;
		if(!(a1[i]).equal(a2[i]))
			return 0;
	}
	return 1;
}

# Put b in a.succs (if atob is true) or a.preds (if atob is false)
# at front of list.
# If it is already in the list, move it to the front.
HistNode.addedge(a: self ref HistNode, b: ref HistNode, atob: int)
{
	if(atob)
		oldl := a.succs;
	else
		oldl = a.preds;
	there := 0;
	for(l := oldl; l != nil; l = tl l)
		if(hd l == b) {
			there = 1;
			break;
		}
	if(there)
		newl := b :: remhnode(oldl, b);
	else
		newl = b :: oldl;
	if(atob)
		a.succs = newl;
	else
		a.preds = newl;
}

# return copy of l with hn removed (known that hn
# occurs at most once)
remhnode(l: list of ref HistNode, hn: ref HistNode) : list of ref HistNode
{
	if(l == nil)
		return nil;
	hdl := hd l;
	if(hdl == hn)
		return tl l;
	return hdl :: remhnode(tl l, hn);
}

# Copy of a, with new kidconfigs array (so that it can be changed independent
# of a), and clear the preds and succs.
HistNode.copy(a: self ref HistNode) : ref HistNode
{
	n := len a.kidconfigs;
	kc : array of ref DocConfig = nil;
	if(n > 0) {
		kc = array[n] of ref DocConfig;
		for(i := 0; i < n; i++)
			kc[i] = a.kidconfigs[i];
	}
	return ref HistNode(a.topconfig, kc, nil, nil, -1, nil);
}

# This is called just before layout of f with result of getting g.
# (we don't yet know doctitle and whether this is a frameset).
# If navkind is not GoHistnode, update the history graph; but if
# navkind is GoReplace, replace oldcur with the new HistNode.
# In any case reorder the history array to put latest last in array.
History.add(h: self ref History, f: ref Frame, g: ref GoSpec, navkind: int)
{
	if(len h.h <= h.n) {
		newh := array[len h.h + 20] of ref HistNode;
		newh[0:] = h.h;
		h.h = newh;
	}
	oldcur : ref HistNode;
	if(h.n > 0)
		oldcur = h.h[h.n-1];
	dc := ref DocConfig(f.name, g.url.tostring(), navkind != GoHistnode, g);
	hnode := ref HistNode(dc, nil, nil, nil, -1, nil);
	if(f == top) {
		g.target = "_top";
	}
	else if(oldcur != nil) {
		# oldcur should be a frameset and f should be a kid in it
		kidpos := -1;
		for(i := 0; i < len oldcur.kidconfigs; i++) {
			kc := oldcur.kidconfigs[i];
			if(kc != nil && kc.framename == f.name) {
				kidpos = i;
				break;
			}
		}
		if(kidpos == -1) {
			if(dbg)
				sys->print("history botch\n");
		}
		else {
			hnode = oldcur.copy();
			hnode.kidconfigs[kidpos] = dc;
		}
	}
	# see if equivalent node to hnode is already in history
	hnodepos := -1;
	for(i := 0; i < h.n; i++) {
		if(hnode.topconfig.equal(h.h[i].topconfig)) {
			if((hnode.kidconfigs==nil && h.h[i].topconfig.initconfig) ||
			   DocConfig.equalarray(hnode.kidconfigs, h.h[i].kidconfigs)) {
				hnodepos = i;
				hnode = h.h[i];
				break;
			}
		}
	}
	if(hnodepos == -1) {
		if(navkind == GoReplace && h.n > 0)
			h.n--;
		hnodepos = h.n;
		h.h[h.n++] = hnode;
	}
	if(oldcur != nil && hnode != oldcur && navkind != GoHistnode) {
		oldcur.addedge(hnode, 1);
		if(navkind != GoReplace)
			hnode.addedge(oldcur, 0);
		else if(oldcur.preds != nil)
			hnode.addedge(hd oldcur.preds, 0);
	}
	if(hnodepos != h.n-1) {
		# move hnode to h.n-1, and shift rest back
		for(k := hnodepos; k < h.n-1; k++)
			h.h[k] = h.h[k+1];
		h.h[h.n-1] = hnode;
	}
	G->backbutton(hnode.preds != nil);
	G->fwdbutton(hnode.succs != nil);
}

# This is called just after layout of f.
# Now we can put in correct doctitle, and make kids array if necessary.
History.update(h: self ref History, f: ref Frame)
{
	hnode := h.h[h.n-1];
	if(f == top) {
		hnode.topconfig.title = f.doc.doctitle;
		if(f.kids != nil && hnode.kidconfigs == nil) {
			kc := array[len f.kids] of ref DocConfig;
			i := 0;
			for(l := f.kids; l != nil; l = tl l) {
				kf := hd l;
				if(kf.src != nil)
					kc[i] = ref DocConfig(kf.name, kf.src.tostring(), 1,  GoSpec.newget(GoNormal, kf.src, "_self"));
				i++;
			}
			hnode.kidconfigs = kc;
		}
	}
	else {
		# hnode should be a frameset and f should be a kid in it
		for(i := 0; i < len hnode.kidconfigs; i++) {
			kc := hnode.kidconfigs[i];
			if(kc != nil && kc.framename == f.name) {
				hnode.kidconfigs[i].title = f.doc.doctitle;
				return;
			}
		}
		if(dbg)
			sys->print("history update botch\n");
	}
}

# Find the gokind node (-1==Back, 0==Same, +1==Forward)
# other gokind values come from JavaScript's History.go(delta)
History.find(h: self ref History, gokind: int) : ref HistNode
{
	if(h.n > 0) {
		cur := h.h[h.n-1];
		case gokind {
		1 =>
			if(cur.succs != nil)
				return hd cur.succs;
		-1 =>
			if(cur.preds != nil)
				return hd cur.preds;
		0 =>
			return cur;
		* =>
# BUG: follows circularities: gives rise to different behaviour to other
# browsers but maintains the property of find(n) being equivalent to
# the user pressing the (forward/back) button n times

			h.findid++;
			while (gokind != 0 && cur != nil) {
				hn : list of ref HistNode;
				if (gokind > 0) {
					gokind--;
					hn = cur.succs;
				} else {
					gokind++;
					hn = cur.preds;
				}
				if (cur.findid == h.findid)
					hn = cur.findchain;
				else
					cur.findid = h.findid;
				if (hn != nil) {
					cur.findchain = tl hn;
					cur = hd hn;
				} else
					cur = nil;
			}
			return cur;
		}
	}
	return nil;
}

# for debugging
History.print(h: self ref History)
{
	sys->print("History\n");
	for(i := 0; i < h.n; i++) {
		hn := history.h[i];
		sys->print("Node %d:\n", i);
		dc := hn.topconfig;
		sys->print("\tframe=%s, target=%s, url=%s\n", dc.framename, dc.gospec.target, dc.gospec.url.tostring());
		if(hn.kidconfigs != nil) {
			for(j := 0; j < len hn.kidconfigs; j++) {
				dc = hn.kidconfigs[j];
				if(dc != nil)
					sys->print("\t\t%d: frame=%s, target=%s, url=%s\n",
							j, dc.framename, dc.gospec.target, dc.gospec.url.tostring());
			}
		}
		if(hn.preds != nil)
			printhnodeindices(h, "Preds", hn.preds);
		if(hn.succs != nil)
			printhnodeindices(h, "Succs", hn.succs);
	}
	sys->print("\n");
}

# helpers for JavaScript's History object
History.histinfo(h: self ref History) : (int, string, string, string)
{
	length := 0;
	current, next, previous : string;

	if(h.n > 0) {
		hn := h.h[h.n-1];
		length = len hn.succs + len hn.preds + 1;
		current = hn.topconfig.gospec.url.tostring();
		if(hn.succs != nil) {
			fwd := hd hn.succs;
			next = fwd.topconfig.gospec.url.tostring();
		}
		if(hn.preds != nil) {
			back := hd hn.preds;
			previous = back.topconfig.gospec.url.tostring();
		}
	}
	return (length, current, next, previous);
}

histinfo() : (int, string, string, string)
{
	return history.histinfo();
}

# does URL in hn contain s as a substring?
isurlsubstring(hn: ref HistNode, s: string) : int
{
	url := hn.topconfig.gospec.url.tostring();
	(l, r) := S->splitstrl(url, s);
	if(r != nil)
		return 1;
	return 0;
}

# for JavaScript's History.go(location)
# find nearest history entry whose URL contains s as a substring
# (search forward and backward from current "in parallel"?)
History.findurl(h: self ref History, s: string) : ref HistNode
{
	if(h.n > 0) {
		hn := h.h[h.n-1];
		if(isurlsubstring(hn, s))
			return hn;
		fwd := hn.succs;
		back := hn.preds;
		while(fwd != nil && back != nil) {
			if(fwd != nil) {
				if(isurlsubstring(hd fwd, s))
					return hd fwd;
				fwd = tl fwd;
			}
			if(back != nil) {
				if(isurlsubstring(hd back, s))
					return hd back;
				back = tl back;
			}
		}
	}
	return nil;
}

printhnodeindices(h: ref History, label: string, l: list of ref HistNode)
{
	sys->print("\t%s:", label);
	for( ; l != nil; l = tl l) {
		hn := hd l;
		for(i := 0; i < h.n; i++) {
			if(hn == h.h[i]) {
				sys->print(" %d", i);
				break;
			}
		}
		if(i == h.n)
			sys->print(" ?");
	}
	sys->print("\n");
}

dumphistory()
{
	fname := config.userdir + "/history.html";
	fd := sys->create(fname, sys->OWRITE, 8r600);
	if(fd == nil) {
		if(warn)
			sys->print("can't create history file\n");
		return;
	}
	line := "<HEAD><TITLE>History</TITLE>\n<META HTTP-EQUIV=\"content-type\" CONTENT=\"text/html; charset=utf8\">\n</HEAD>\n<BODY>\n";
	buf := array[Sys->ATOMICIO] of byte;
	aline := array of byte line;
	buf[0:] = aline;
	bufpos := len aline;
	for(i := history.n-1; i >= 0; i--) {
		hn := history.h[i];
		dc := hn.topconfig;
		line = "<A HREF=" + dc.gospec.url.tostring() + " TARGET=\"_top\">" + dc.title + "</A><BR>\n";
		if(hn.kidconfigs != nil) {
			line += "<UL>";
			for(j := 0; j < len hn.kidconfigs; j++) {
				dc = hn.kidconfigs[j];
				if(dc != nil) {
					line += "<LI><A HREF=" + dc.gospec.url.tostring() +
						" TARGET=\"" + dc.framename + "\">" +
						dc.title + "</A>\n";
				}
			}
			line += "</UL>";
		}
		aline = array of byte line;
		if(bufpos + len aline > Sys->ATOMICIO) {
			sys->write(fd, buf, bufpos);
			bufpos = 0;
		}
		buf[bufpos:] = aline;
		bufpos += len aline;
	}
	if(bufpos > 0)
		sys->write(fd, buf, bufpos);
}

# getauth returns the (realm, credentials), with "" for the credentials
# if we fail in getting authorization for some reason
getauth(chal: string) : (string, string)
{
	if(len chal < 12 || S->tolower(chal[0:12]) != "basic realm=") {
		if(dbg || warn)
			sys->print("unrecognized authorization challenge: %s\n", chal);
		return ("", "");
	}
	realm := chal[12:];
	if(realm[0] == '"')
		realm = realm[1:len realm - 1];
	for(al := auths; al != nil; al = tl al) {
		a := hd al;
		if(realm == a.realm)
			return (realm, a.credentials);
	}
	
	c := chan of (int, string);
	(code, uname, pword) := G->auth(realm);
	if(code != 1)
		return (nil, nil);
	cred := uname + ":" + pword;
	cred = tobase64(cred);
	return (realm, cred);
}

# Convert string to the base64 encoding
tobase64(a: string) : string
{
	n := len a;
	if(n == 0)
		return "";
	out := "";
	j := 0;
	i := 0;
	while(i < n) {
		x := a[i++] << 16;
		if(i < n)
			x |= (a[i++]&255) << 8;
		if(i < n)
			x |= (a[i++]&255);
		out[j++] = c64(x>>18);
		out[j++] = c64(x>>12);
		out[j++] = c64(x>> 6);
		out[j++] = c64(x);
	}
	nmod3 := n % 3;
	if(nmod3 != 0) {
		out[j-1] = '=';
		if(nmod3 == 1)
			out[j-2] = '=';
	}
	return out;
}

c64(c: int) : int
{
	v : con "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
	return v[c&63];
}

dosaveas(bsmain: ref ByteSource)
{
	(code, ans) := G->prompt("Save as", nil);
	if (code == -1)
		return;
	if(code == 1 && ans != "") {
		if(ans[0] != '/')
			ans = config.userdir + "/" + ans;
		fd := sys->create(ans, sys->OWRITE, 8r644);
		if(fd == nil) {
			G->alert(X("Couldn't create", "gui") + " " + ans);
			return;
		}
		G->setstatus(X("Saving", "gui") + " " + bsmain.hdr.actual.tostring());
		# TODO: should really use a different protocol that
		# doesn't require getting whole file before proceeding
		s := "";
		while(!bsmain.eof) {
			CU->waitreq(bsmain::nil);
			if(bsmain.err != "") {
				s = bsmain.err;
				break;
			}
		}
		if(s == "") {
			flen := bsmain.edata;
			for(i := 0; i < bsmain.edata; ) {
				n := sys->write(fd, bsmain.data[i:flen], flen-i);
				if(n <= 0)
					break;
				i += n;
			}
			if(i != flen)
				s = "whole file not written";
		}
		if(s == "")
			s = X("Created", "gui") + " " + ans;
		G->setstatus(X("Created", "gui") + " " + ans);
		# G->alert(s);
	}
	CU->freebs(bsmain);
}

fatalerror(msg: string)
{
	sys->print("Fatal error: %s\n", msg);
	finish();
}

pctoloc(mod: string, pc: int) : string
{
	ans := sys->sprint("pc=%d", pc);
	db := load Debug Debug->PATH;
	if(db == nil)
		return ans;
	Sym : import db;
	db->init();
	modname := mod;
	for(i := 0; i < len mod; i++)
		if(mod[i] == '[') {
			modname = mod[0:i];
			break;
		}
	sblname := "";
	case modname {
	"Build" =>
		sblname = "build.sbl";
	"CharonUtils" =>
		sblname = "chutils.sbl";
	"Gui" =>
		sblname = "gui.sbl";
	"Img" =>
		sblname = "img.sbl";
	"Layout" =>
		sblname = "layout.sbl";
	"Lex" =>
		sblname = "lex.sbl";
	"Test" =>
		sblname = "test.sbl";
	}
	if(sblname == "")
		return ans;
	(sym, nil) := db->sym(sblname);
	if(sym == nil)
		return ans;
	src := sym.pctosrc(pc);
	if(src == nil)
		return ans;
	return sys->sprint("%s:%d", src.start.file, src.start.line);
}

startcs()
{
	cs := load Command "/dis/ndb/cs.dis";
	if (cs == nil) {
		sys->print("failed to start cs\n");
		return;
	}
	spawn cs->init(nil, nil);
	sys->sleep(1000);
}

startcharon(url: string, c: chan of string)
{
	ctxt := ref Context;
	ctxt.ctxt = context;
	ctxt.args = "charon" :: url :: nil;
	ctxt.c = c;
	ctxt.cksrv = CU->CK;
	ctxt.ckclient = CU->ckclient;
	ch := load Charon "/dis/charon.dis";
	fdl := list of {0, 1, 2};
	if (CU->ckclient != nil)
		fdl = (CU->ckclient).fd.fd :: fdl;
	if(ch != nil){
		sys->pctl(Sys->NEWPGRP|Sys->NEWFD, fdl);
		ch->initc(ctxt);
	}
}

# Kill all processes spawned by us, and exit
finish()
{
	if (CU != nil) {
		CU->kill(pgrp, 1);
		if(gopgrp != 0)
			CU->kill(gopgrp, 1);
	}
	if(plumb != nil)
		plumb->shutdown();
	sendopener("E");
	exit;
}

include "plumbmsg.m";
	plumb: Plumbmsg;
	Msg: import plumb;

plumbwatch()
{
	plumb = load Plumbmsg Plumbmsg->PATH;
	if (plumb == nil)
		return;
	if (plumb->init(1, (CU->config).plumbport, 0) == -1) {
		# try to set up plumbing for sending only
		if (plumb->init(1, nil, 0) == -1)
			plumb = nil;
		return;
	}
	while ((m := Msg.recv()) != nil) {
		if (m.kind == "text") {
			u := CU->makeabsurl(string m.data);
			if (u != nil)
				E->evchan <-= ref Event.Ego(u.tostring(), "_top", 0, E->EGnormal);
		}
	}
}

plumbsend(s, dest: string): int
{
	if (plumb == nil)
		return -1;
	if (dest != nil)
		dest = "type="+dest;
	msg := ref Msg((CU->config).plumbport, nil, "", "text", dest, array of byte s);
	if (msg.send() < 0)
		return -1;
	return 0;
}

stop()
{
	stopped := X("Stopped", "gui");
	G->progress <-= (-1, G->Paborted, 0, stopped);
	G->setstatus(stopped);
	CU->abortgo(gopgrp);
}

gettop(): ref Layout->Frame
{
	return top;
}
