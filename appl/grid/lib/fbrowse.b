implement FBrowse;

#
# Copyright © 2003 Vita Nuova Holdings Limited.  All rights reserved.
#


include "sys.m";
	sys : Sys;
include "draw.m";
	draw: Draw;
	Rect: import draw;
include "tk.m";
	tk: Tk;
include "tkclient.m";
	tkclient: Tkclient;
include "readdir.m";
	readdir: Readdir;
include "workdir.m";
include "sh.m";
	sh: Sh;
include "grid/pathreader.m";
	reader: PathReader;
include "grid/browser.m";
	browser: Browser;
	Browse, Select, File, Parameter,
	DESELECT, SELECT, TOGGLE: import browser;
include "grid/fbrowse.m";

br: ref Browse;

init(ctxt : ref Draw->Context, title, root, currdir: string): string
{
	sys = load Sys Sys->PATH;
	if (sys == nil)
		badmod(Sys->PATH);
	draw = load Draw Draw->PATH;
	if (draw == nil)
		badmod(Draw->PATH);
	readdir = load Readdir Readdir->PATH;
	if (readdir == nil)
		badmod(Readdir->PATH);
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
	sh = load Sh Sh->PATH;
	if (sh == nil)
		badmod(Sh->PATH);
	browser = load Browser Browser->PATH;
	if (browser == nil)
		badmod(Browser->PATH);
	browser->init();
	reader = load PathReader "$self";
	if (reader == nil)
		sys->print("cannot load reader!\n");
	sys->pctl(sys->NEWPGRP, nil);
	if (root == nil)
		root = "/";
	sys->chdir(root);
	if (currdir == nil)
		currdir = workdir->init();
	if (root[len root - 1] != '/')
		root[len root] = '/';
	if (currdir[len currdir - 1] != '/')
		currdir[len currdir] = '/';
	
	(top, titlebar) := tkclient->toplevel(ctxt,"", title , tkclient->OK | tkclient->Appl);
	browsechan := chan of string;
	tk->namechan(top, browsechan, "browsechan");
	br = Browse.new(top, "browsechan", root, root, 2, reader);
	br.addopened(File (root, nil), 1);
	br.gotoselectfile(File (currdir, nil));
	for (ik := 0; ik < len mainscreen; ik++)
		tkcmd(top,mainscreen[ik]);
	butchan := chan of string;
	tk->namechan(top, butchan, "butchan");
	
	tkcmd(top, "pack .f -fill both -expand 1; pack propagate . 0");
	tkcmd(top, ". configure -height 300 -width 300");

	tkcmd(top, "update");
	released := 1;
	title = "";
	
	tkclient->onscreen(top, nil);
	resize(top, ctxt.display.image);
	tkclient->startinput(top, "kbd"::"ptr"::nil);

	path: string;

	main: for (;;) {
		alt {
		s := <-top.ctxt.kbd =>
			tk->keyboard(top, s);
		s := <-top.ctxt.ptr =>
			tk->pointer(top, *s);
		inp := <-browsechan =>
			(nil, lst) := sys->tokenize(inp, " \n\t");
			selected := br.getselected(1);
			case hd lst {
				"double1pane1" =>
					tkpath := hd tl lst;
					file := br.getpath(tkpath);
					br.defaultaction(lst, file);
					(n, dir) := sys->stat(file.path);
					if (n == -1 || dir.mode & sys->DMDIR)
						break;
					if ((len dir.name > 4 && dir.name[len dir.name - 4:] == ".dis") || 
						dir.mode & 8r111)
						spawn send(butchan, "run "+tkpath);
					else if (dir.mode & 8r222)
						spawn send(butchan, "write "+tkpath);
					else if (dir.mode & 8r444)
							spawn send(butchan, "open "+tkpath);
				* =>
					br.defaultaction(lst, nil);
			}
			if (!File.eq(selected, br.getselected(1)))
				actionbutton(top, br.selected[1].file.path, br.selected[1].tkpath);
			tkcmd(top, "update");
		inp := <-butchan =>
			(nil, lst) := sys->tokenize(inp, " \n\t");
			case hd lst {
				"refresh" =>
					br.refresh();
				"shell" =>
					path = br.getselected(1).path;
					if (path == nil)
						sys->chdir(root);
					else
						sys->chdir(path);
					sh->run(ctxt, "/dis/wm/sh.dis" :: nil);

				"run" =>
					spawn run(ctxt, br.getselected(1).path);
				"read" =>							
					wtitle := tkcmd(top, hd tl lst+" cget text");
					spawn openfile(ctxt, br.getselected(1).path, wtitle,0);
				"write" =>
					wtitle := tkcmd(top, hd tl lst+" cget text");
					spawn openfile(ctxt, br.getselected(1).path, wtitle,1);
			}
			tkcmd(top, "update");
		
		title = <-top.ctxt.ctl or
		title = <-top.wreq or
		title = <-titlebar =>
			if (title == "exit" || title == "ok")
				break main;
			e := tkclient->wmctl(top, title);
			if (e != nil && e[0] == '!')
				br.resize();
		}
	}
	if (title == "ok")
		return br.getselected(1).path;
	return "";
}

send(chanout: chan of string, s: string)
{
	chanout <-= s;
}

resize(top: ref Tk->Toplevel, img: ref Draw->Image)
{
	if (img != nil) {
		scw := img.r.dx();
		sch := img.r.dy();
		ww := int tkcmd(top, ". cget -width");
		wh := int tkcmd(top, ". cget -height");
		if (ww > scw)
			tkcmd(top, ". configure -x 0 -width "+string scw);
		if (wh > sch)
			tkcmd(top, ". configure -y 0 -height "+string sch);
	}
}

mainscreen := array[] of {
	"frame .f",
	"frame .f.ftop",
	"button .f.ftop.bs -text {Shell} -command {send butchan shell} -font /fonts/charon/bold.normal.font",
	"button .f.ftop.br -text {Refresh} -command {send butchan refresh} -font /fonts/charon/bold.normal.font",
	"grid .f.ftop.bs .f.ftop.br -row 0",
	"grid columnconfigure .f.ftop 2 -minsize 30",
	"grid .f.ftop -row 0 -column 0 -pady 2 -sticky w",
	"label .f.l -text { } -height 1 -bg red",
	"grid .f.l -row 1 -sticky ew",
	"grid .fbrowse -in .f -row 2 -column 0 -sticky nsew",
	"grid rowconfigure .f 2 -weight 1",
	"grid columnconfigure .f 0 -weight 1",

	"bind .Wm_t <Button-1> +{focus .Wm_t}",
	"bind .Wm_t.title <Button-1> +{focus .Wm_t}",
	"focus .Wm_t",
};

readpath(file: File): (array of ref sys->Dir, int)
{
	(dirs, nil) := readdir->init(file.path, readdir->NAME | readdir->COMPACT);
	return (dirs, 0);
}

run(ctxt: ref Draw->Context, file: string)
{
	sys->pctl(sys->FORKNS | sys->NEWPGRP, nil);
	sys->chdir(browser->prevpath(file));
	sh->run(ctxt, file :: nil);
}

openscr := array[] of {
	"frame .f",
	"scrollbar .f.sy -command {.f.t yview}",
	"text .f.t -yscrollcommand {.f.sy set} -bg white -font /fonts/charon/plain.normal.font",
	"pack .f.sy -side left -fill y",
	"pack .f.t -fill both -expand 1",
	"bind .Wm_t <Button-1> +{focus .Wm_t}",
	"bind .Wm_t.title <Button-1> +{focus .Wm_t}",
	"focus .f.t",
};

fopensize := ("", "");

plumbing := array[] of {
	("bit", "wm/view"),
	("jpg", "wm/view"),
};

freader(top: ref Tk->Toplevel, fd: ref sys->FD, sync: chan of int)
{
	sync <-= sys->pctl(0,nil);
	buf := array[8192] of byte;
	for (;;) {
		i := sys->read(fd, buf, len buf);
		if (i < 1)
			return;
		s :="";
		for (j := 0; j < i; j++) {
			c := int buf[j];
			if (c == '{' || c == '}')
				s[len s] = '\\';
			s[len s] = c;
		}
		tk->cmd(top, ".f.t insert end {"+s+"}; update");
	}
}

openfile(ctxt: ref draw->Context, file, title: string, writeable: int)
{
	ext := getext(file);
	plumb := getplumb(ext);
	if (plumb != nil) {
		sh->run(ctxt, plumb :: file :: nil);
		return;
	}
	button := tkclient->Appl;
	if (writeable)
		button = button | tkclient->OK;
	(top, titlebar) := tkclient->toplevel(ctxt, "", title, button);
	tkcmds(top, openscr);
	tkcmd(top,"pack .f -fill both -expand 1");
	tkcmd(top,"pack propagate . 0");
	(w,h) := fopensize;
	if (w != "" && h != "")
		tkcmd(top, ". configure -width "+w+" -height "+h);
	killpid := -1;
	fd := sys->open(file, sys->OREAD);
	if (fd != nil) {
		sync := chan of int;
		spawn freader(top, fd, sync);
		killpid = <-sync;
	}
	tkcmd(top, "update");
	tkclient->onscreen(top, nil);
	tkclient->startinput(top, "kbd"::"ptr"::nil);
	main: for (;;) {
		alt {
		s := <-top.ctxt.kbd =>
			tk->keyboard(top, s);
		s := <-top.ctxt.ptr =>
			tk->pointer(top, *s);

		title = <-top.ctxt.ctl or
		title = <-top.wreq or
		title = <-titlebar =>
			if (title == "exit" || title == "ok")
				break main;
			tkclient->wmctl(top, title);
		}
	}
	if (killpid != -1)
		kill(killpid);
	fopensize = (tkcmd(top, ". cget -width"), tkcmd(top, ". cget -height"));
	if (title == "ok") {
		(n, dir) := sys->stat(file);
		if (n != -1) {
			fd = sys->create(file, sys->OWRITE, dir.mode);
			if (fd != nil) {
				s := tkcmd(top, ".f.t get 1.0 end");
				sys->fprint(fd,"%s",s);
				fd = nil;
			}
		}
	}
}	

badmod(path: string)
{
	sys->print("FBrowse: failed to load: %s\n",path);
	exit;
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

nactionbuttons := 0;
actionbutton(top: ref Tk->Toplevel, path, tkpath: string)
{
	(n, dir) := sys->stat(path);
	for (i := 0; i < nactionbuttons; i++) {
		tkcmd(top, "grid forget .f.ftop.baction"+string i);
		tkcmd(top, "destroy .f.ftop.baction"+string i);
	}
	if (path == nil || n == -1 || dir.mode & sys->DMDIR) {
		nactionbuttons = 0;
		return;
	}
	buttons : list of (string,string) = nil;
	
	if (dir.mode & 8r222)
		buttons = ("Open", "write "+tkpath) :: buttons;
	else if (dir.mode & 8r444)
		buttons = ("Open", "read "+tkpath) :: buttons;
	if (len dir.name > 4 && dir.name[len dir.name - 4:] == ".dis" || dir.mode & 8r111)
		buttons = ("Run", "run "+tkpath) :: buttons;

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

getext(file: string): string
{
	(nil, lst) := sys->tokenize(file, ".");
	for (; tl lst != nil; lst = tl lst)
		;
	return hd lst;
}

getplumb(ext: string): string
{
	for (i := 0; i < len plumbing; i++)
		if (ext == plumbing[i].t0)
			return plumbing[i].t1;
	return nil;
}

kill(pid: int)
{
	if ((fd := sys->open("/prog/" + string pid + "/ctl", Sys->OWRITE)) != nil)
		sys->fprint(fd, "kill");
}
