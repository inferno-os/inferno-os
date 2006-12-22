implement Query;

#
# Copyright © 2003 Vita Nuova Holdings Limited.  All rights reserved.
#


include "sys.m";
	sys : Sys;
include "draw.m";
	draw: Draw;
	Display, Rect, Image: import draw;
include "tk.m";
	tk: Tk;
include "tkclient.m";
	tkclient: Tkclient;
include "readdir.m";
	readdir: Readdir;
include "sh.m";
include "workdir.m";
include "registries.m";
	registries: Registries;
	Service: import registries;
include "grid/pathreader.m";
	reader: PathReader;
include "grid/browser.m";
	browser: Browser;
	Browse, File: import browser;
include "grid/srvbrowse.m";
	srvbrowse: Srvbrowse;
include "grid/fbrowse.m";
include "grid/announce.m";
	announce: Announce;

srvfilter : list of list of (string, string);

Query : module {
	init : fn (context : ref Draw->Context, nil : list of string);
	readpath: fn (dir: File): (array of ref sys->Dir, int);
};

realinit()
{
	sys = load Sys Sys->PATH;
	if (sys == nil)
		badmod(Sys->PATH);
	readdir = load Readdir Readdir->PATH;
	if (readdir == nil)
		badmod(Readdir->PATH);
	draw = load Draw Draw->PATH;
	if (draw == nil)
		badmod(Draw->PATH);
	tk = load Tk Tk->PATH;
	if (tk == nil)
		badmod(Tk->PATH);
	tkclient = load Tkclient Tkclient->PATH;
	if (tkclient == nil)
		badmod(Tkclient->PATH);
	tkclient->init();
	workdir := load Workdir Workdir->PATH;
	if (workdir == nil)
		badmod(Workdir->PATH);
	registries = load Registries Registries->PATH;
	if (registries == nil)
		badmod(Registries->PATH);
	registries->init();
	browser = load Browser Browser->PATH;
	if (browser == nil)
		badmod(Browser->PATH);
	browser->init();
	srvbrowse = load Srvbrowse Srvbrowse->PATH;
	if (srvbrowse == nil)
		badmod(Srvbrowse->PATH);
	srvbrowse->init();
	announce = load Announce Announce->PATH;
	if (announce == nil)
		badmod(Announce->PATH);
	announce->init();
	reader = load PathReader "$self";
	if (reader == nil)
		badmod("PathReader");
}

init(ctxt : ref Draw->Context, nil: list of string)
{
	realinit();	
	spawn start(ctxt, 1);
}

start(ctxt: ref Draw->Context, standalone: int)
{
	sys->pctl(sys->FORKNS | sys->NEWPGRP, nil);
	if (ctxt == nil)
		ctxt = tkclient->makedrawcontext();

	if (standalone)
		sys->create("/tmp/query", sys->OREAD, sys->DMDIR | 8r777);
	root := "/";
	(top, titlebar) := tkclient->toplevel(ctxt,"","Query", tkclient->Appl);
	butchan := chan of string;
	tk->namechan(top, butchan, "butchan");
	browsechan := chan of string;
	tk->namechan(top, browsechan, "browsechan");
	br := Browse.new(top, "browsechan", "services/", "Services", 1, reader);
	br.addopened(File ("services/", nil), 1);
	srvbrowse->refreshservices(srvfilter);
	br.refresh();

	for (ik := 0; ik < len mainscreen; ik++)
		tkcmd(top,mainscreen[ik]);

	tkcmd(top, "pack .f -fill both -expand 1; pack propagate . 0");
	released := 1;
	title := "";
	resize(top, 400,400);
	tkclient->onscreen(top, nil);
	tkclient->startinput(top, "kbd"::"ptr"::nil);
	tkpath: string;
	main: for (;;) {
		alt {
		s := <-top.ctxt.kbd =>
			tk->keyboard(top, s);
		s := <-top.ctxt.ptr =>
			tk->pointer(top, *s);
		inp := <-browsechan =>
			(nil, lst) := sys->tokenize(inp, " \n\t");
			if (len lst > 1)
				tkpath = hd tl lst;
			selected := br.getselected(0);
			br.defaultaction(lst, nil);
			if (!File.eq(selected, br.getselected(0)))
				actionbutton(top, br.selected[0].file.path, br.selected[0].tkpath);		
			tkcmd(top, "update");
		inp := <-butchan =>
			# sys->print("inp: %s\n",inp);
			(nil, lst) := sys->tokenize(inp, " \n\t");
			if (len lst > 1)
				tkpath = hd tl lst;
			case hd lst {
				"search" =>
					if (tl lst == nil)
						spawn srvbrowse->searchwin(ctxt, butchan, nil);
					else {
						if (hd tl lst == "select") {
							file := hd tl tl lst;
							for (tmp := tl tl tl lst; tl tmp != nil; tmp = tl tmp)
								file += " "+hd tmp;
							qid := hd tmp;
							br.gotoselectfile(File (file, qid));
							actionbutton(top, br.selected[0].file.path, br.selected[0].tkpath);		
						}
						else if (hd tl lst == "search") {
							srvbrowse->refreshservices(srvfilter);
							br.refresh();			
						}
					}
				"refresh" =>
					# ! check to see if anything is mounted first
					srvbrowse->refreshservices(srvfilter);
					br.refresh();
				"mount" =>
					file := *br.getpath(tkpath);
					(nsrv, lsrv) := sys->tokenize(file.path, "/");
					if (nsrv == 3)
						spawn mountsrv(ctxt, file, getcoords(top));
			}
			tkcmd(top, "update");

		title = <-top.ctxt.ctl or
		title = <-top.wreq or
		title = <-titlebar =>
			if (title == "exit")
				break main;
			e := tkclient->wmctl(top, title);
			if (e == nil && title[0] == '!')
				(nil, lst) := sys->tokenize(title, " \t\n");
		}
	}
	killg(sys->pctl(0,nil));
}

resize(top: ref Tk->Toplevel, w, h: int)
{
	tkcmd(top, ". configure -x 0 -width "+string min(top.screenr.dx(), w));
	tkcmd(top, ". configure -y 0 -height "+string min(top.screenr.dy(), h));
}

min(a, b: int): int
{
	if (a < b)
		return a;
	return b;
}

nactionbuttons := 0;
actionbutton(top: ref Tk->Toplevel, path, tkpath: string)
{
	for (i := 0; i < nactionbuttons; i++) {
		tkcmd(top, "grid forget .f.ftop.baction"+string i);
		tkcmd(top, "destroy .f.ftop.baction"+string i);
	}
	if (path == nil) {
		nactionbuttons = 0;
		return;
	}
	(n, nil) := sys->tokenize(path, "/");
	buttons : list of (string, string) = nil;
	if (n == 3)
		buttons = ("Mount", "mount "+tkpath) :: buttons;

	nactionbuttons = len buttons;
	for (i = 0; i < nactionbuttons; i++) {
		name := ".f.ftop.baction"+string i+" ";
		(text,cmd) := hd buttons;
		tkcmd(top, "button "+name+"-text {"+text+"} "+
				"-font /fonts/charon/bold.normal.font "+
				"-command {send butchan "+cmd+"}");
		tkcmd(top, "grid "+name+" -row 0 -column "+string (4+i));
		buttons = tl buttons;
	}
}

kill(pid: int)
{
	if ((fd := sys->open("/prog/" + string pid + "/ctl", Sys->OWRITE)) != nil)
		sys->fprint(fd, "kill");
}

killg(pid: int)
{
	if ((fd := sys->open("/prog/" + string pid + "/ctl", Sys->OWRITE)) != nil)
		sys->fprint(fd, "killgrp");
}

mainscreen := array[] of {
	"frame .f",
	"frame .f.ftop",
	"variable opt command",
	"button .f.ftop.br -text {Refresh} -command {send butchan refresh} -font /fonts/charon/bold.normal.font",
	"button .f.ftop.bs -text {Search} -command {send butchan search} -font /fonts/charon/bold.normal.font",
  	"grid .f.ftop.br .f.ftop.bs -row 0",
	"grid columnconfigure .f.ftop 3 -minsize 30",
	"label .f.l -text { } -height 1 -bg red",
	"grid .f.l -row 1 -column 0 -sticky ew",
	"grid .f.ftop -row 0 -column 0 -pady 2 -sticky w",
	"grid .fbrowse -in .f -row 2 -column 0 -sticky nsew",
	
	"grid columnconfigure .f 0 -weight 1",
	"grid rowconfigure .f 2 -weight 1",

	"bind .Wm_t <Button-1> +{focus .Wm_t}",
	"bind .Wm_t.title <Button-1> +{focus .Wm_t}",
	"focus .Wm_t",
};

readpath(dir: File): (array of ref sys->Dir, int)
{
	return srvbrowse->servicepath2Dir(dir.path, int dir.qid);
}

badmod(path: string)
{
	sys->print("Query: failed to load %s: %r\n",path);
	exit;
}

mountscr := array[] of {
	"frame .f -borderwidth 2 -relief raised",
	"text .f.t -width 200 -height 60 -borderwidth 1 -bg white -font /fonts/charon/plain.normal.font",
	"button .f.b -text {Cancel} -command {send butchan cancel} -width 70 -font /fonts/charon/plain.normal.font",
	"grid .f.t -row 0 -column 0 -padx 10 -pady 10",
	"grid .f.b -row 1 -column 0 -sticky n",
	"grid rowconfigure .f 1 -minsize 30",
};

mountsrv(ctxt: ref Draw->Context, srvfile: File, coords: draw->Rect)
{
	(top, nil) := tkclient->toplevel(ctxt, "", nil, tkclient->Plain);
	ctlchan := chan of string;
	butchan := chan of string;
	tk->namechan(top, butchan, "butchan");
	tkcmds(top, mountscr);
	tkcmd(top, ". configure "+getcentre(top, coords)+"; pack .f; update");
	spawn mountit(ctxt, srvfile, ctlchan);
	pid := int <-ctlchan;
	tkclient->onscreen(top, "exact");
	tkclient->startinput(top, "kbd"::"ptr"::nil);
	for (;;) {
		alt {
		s := <-top.ctxt.kbd =>
			tk->keyboard(top, s);
		s := <-top.ctxt.ptr =>
			tk->pointer(top, *s);
		e := <- ctlchan =>
			if (e[0] == '!') {
				tkcmd(top, ".f.t insert end {"+e[1:]+"}");
				tkcmd(top, ".f.b configure -text {close}; update");
				pid = -1;
			}
			else if (e == "ok")
				return;
			else
				tkcmd(top, ".f.t insert end {"+e+"}; update");
		<- butchan =>
			if (pid != -1)
				kill(pid);
			return;
		}
	}
}

mountit(ctxt: ref Draw->Context, srvfile: File, ctlchan: chan of string)
{
	ctlchan <-= string sys->pctl(0,nil);

	n := 0;
	(nil, lst) := sys->tokenize(srvfile.path, "/");
	stype := hd tl lst;
	name := hd tl tl lst;
	addr := "";
	ctlchan <-= "Connecting...\n";
	lsrv := srvbrowse->servicepath2Service(srvfile.path, srvfile.qid);
	if (len lsrv < 1) {
		ctlchan <-= "!could not find service";
		return;
	}
	srvc := hd lsrv;

	ctlchan <-= "Mounting...\n";
	
	id := 0;
	dir : string;
	for (;;) {
		dir = "/tmp/query/"+string id;
		(n2, nil) := sys->stat(dir);
		if (n2 == -1) {
			fdtmp := sys->create(dir, sys->OREAD, sys->DMDIR | 8r777);
			if (fdtmp != nil)
				break;
		}
		else {
			(dirs2, nil) := readdir->init(dir, readdir->NAME | readdir->COMPACT);
			if (len dirs2 == 0)
				break;
		}
		id++;
	}
	attached := srvc.attach(nil, nil);
	if (attached == nil) {
		ctlchan <-= sys->sprint("!could not connect: %r");
		return;
	}
	if (sys->mount(attached.fd, nil, dir, sys->MREPL, nil) != -1) {
		ctlchan <-= "ok";
		fbrowse := load FBrowse FBrowse->PATH;
		if (fbrowse == nil)
			badmod(FBrowse->PATH);
		fbrowse->init(ctxt, srvfile.path, dir, dir);
		sys->unmount(nil, dir);
		attached = nil;
	}
	else
		ctlchan <-= sys->sprint("!mount failed: %r");
}

getcoords(top: ref Tk->Toplevel): draw->Rect
{
	h := int tkcmd(top, ". cget -height");
	w := int tkcmd(top, ". cget -width");
	x := int tkcmd(top, ". cget -actx");
	y := int tkcmd(top, ". cget -acty");
	r := draw->Rect((x,y),(x+w,y+h));
	return r;
}

getcentre(top: ref Tk->Toplevel, winr: draw->Rect): string
{
	h := int tkcmd(top, ".f cget -height");
	w := int tkcmd(top, ".f cget -width");
	midx := winr.min.x + (winr.dx() / 2);
	midy := winr.min.y + (winr.dy() / 2);
	newx := midx - (w/2);
	newy := midy - (h/2);
	return "-x "+string newx+" -y "+string newy;
}

tkcmd(top: ref Tk->Toplevel, cmd: string): string
{
	e := tk->cmd(top, cmd);
	if (e != "" && e[0] == '!')
		sys->print("Tk error: '%s': %s\n",cmd,e);
	return e;
}

tkcmds(top: ref Tk->Toplevel, a: array of string)
{
	for (j := 0; j < len a; j++)
		tkcmd(top, a[j]);
}
