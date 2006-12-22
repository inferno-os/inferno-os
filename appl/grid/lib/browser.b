implement Browser;

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
include "./pathreader.m";
include "./browser.m";

entryheight := "";

init()
{
	sys = load Sys Sys->PATH;
	if (sys == nil)
		badmod(Sys->PATH);
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
}

Browse.new(top: ref Tk->Toplevel, tkchanname, root, rlabel: string, nopanes: int, reader: PathReader): ref Browse
{
	b : Browse;
	b.top = top;
	b.tkchan = tkchanname;
	if (nopanes < 1 || nopanes > 2)
		return nil;
	b.nopanes = 2;
	b.bgnorm = bgnorm;
	b.bgselect = bgselect;
	b.selected = array[2] of { * => Selected (File(nil, nil), nil) };
	b.opened = (root, nil) :: nil;
	if (root == nil)
		return nil;
	if (root[len root - 1] != '/')
		root[len root] = '/';
	b.pane0width = "2 3";
	b.root = root;
	b.rlabel = rlabel;
	b.reader = reader;
	b.pane1 = File (nil, "-123");
	b.released = 1;
	tkcmds(top, pane0scr);

	tkcmds(top, pane1scr);
	tkcmd(top, "bind .fbrowse.lmov <Button-1> {send "+b.tkchan+" movdiv %X}");

	size := tkcmd(top, "grid size .fbrowse");
	p := isat(size, " ");
	tkcmd(top, "label .fbrowse.l -text { }  -anchor w -width 0" +
		" -font /fonts/charon/plain.normal.font");
	tkcmd(top, ".fbrowse.l configure -height "+tkcmd(top, ".fbrowse.l cget -height"));
	tkcmd(top, "grid .fbrowse.l -row 0 -column 0 -sticky ew -pady 2 -columnspan 4");
	rb := ref b;
	rb.newroot(b.root, b.rlabel);
	rb.changeview(nopanes);
	setbrowsescrollr(rb);
	return rb;
}

Browse.refresh(b: self ref Browse)
{
	scrval := tkcmd(b.top, ".fbrowse.sy1 get");
	p := isat(scrval, " ");
	p1 := b.pane1;
	b.newroot(b.root, b.rlabel);
	setbrowsescrollr(b);
	if (b.nopanes == 2)
		popdirpane1(b, p1);
	b.selectfile(1,DESELECT, File (nil, nil), nil);
	b.selectfile(0,DESELECT, File (nil, nil), nil);
	tkcmd(b.top, ".fbrowse.c1 yview moveto "+scrval[:p]+"; update");
}

bgnorm := "white";
bgselect := "#5555FF";

ft := " -font /fonts/charon/plain.normal.font";
fts := " -font /fonts/charon/plain.tiny.font";
ftb := " -font /fonts/charon/bold.normal.font";

Browse.gotoselectfile(b: self ref Browse, file: File): string
{
	(dir, tkpath) := b.gotopath(file, 0);
	if (tkpath == nil)
		return nil;
	# Select dir
	tkpath += ".l";
	if (dir.qid != nil)
		tkpath += "Q" + dir.qid;
	b.selectfile(0, SELECT, dir, tkpath);

	# If it is a file, select the file too
	if (!File.eq(file, dir)) {
		slaves := tkcmd(b.top, "grid slaves .fbrowse.fl2");
		(nil, lst) := sys->tokenize(slaves, " ");
		for (; lst != nil; lst = tl lst) {
			if (File.eq(file, *b.getpath(hd lst))) {
				b.selectfile(1, SELECT, file, hd lst);
				tkpath = hd lst;
				break;
			}
		}
		pane1see(b);
	}
	return tkpath;
}

pane1see(b: ref Browse)
{
	f := b.selected[1].tkpath;
	if (f == "")
		return;
	x1 := int tkcmd(b.top, f+" cget -actx") - int tkcmd(b.top, ".fbrowse.fl2 cget -actx");
	y1 := int tkcmd(b.top, f+" cget -acty") - int tkcmd(b.top, ".fbrowse.fl2 cget -acty");
	x2 := x1 + int tkcmd(b.top, f+" cget -actwidth");
	y2 := y1 + int tkcmd(b.top, f+" cget -actheight");
	tkcmd(b.top, sys->sprint(".fbrowse.c2 see %d %d %d %d", x1,y1,x2,y2));
}

Browse.opendir(b: self ref Browse, file: File, tkpath: string, action: int): int
{
	curr := tkcmd(b.top, tkpath+".lp cget -text");
	if ((action == OPEN || action == TOGGLE) && curr == "+") {
		tkcmd(b.top, tkpath+".lp configure -text {-} -relief sunken");
		popdirpane0(b, file, tkpath);
		seeframe(b.top, tkpath);
		b.addopened(file, 1);
		setbrowsescrollr(b);
		return 1;
	}
	else if ((action == CLOSE || action == TOGGLE) && curr == "-") {
		tkcmd(b.top, tkpath+".lp configure -text {+} -relief raised");
		slaves := tkcmd(b.top, "grid slaves "+tkpath+" -column 1");
		p := isat(slaves, " ");
		if (p != -1)
			tkcmd(b.top, "destroy "+slaves[p:]);
		slaves = tkcmd(b.top, "grid slaves "+tkpath+" -column 2");
		if (slaves != "")
			tkcmd(b.top, "destroy "+slaves);
		b.addopened(file, 0);
		setbrowsescrollr(b);
		return 1;
	}
	return 0;
}

Browse.addopened(b: self ref Browse, file: File, add: int)
{
	tmp : list of File = nil;
	for (; b.opened != nil; b.opened = tl b.opened) {
		dir := hd b.opened;
		if (!File.eq(file, dir))
			tmp = dir :: tmp;
	}
	if (add)
		tmp = file :: tmp;
	b.opened = tmp;
}

Browse.changeview(b: self ref Browse, nopanes: int)
{
	if (b.nopanes == nopanes)
		return;
	w := int tkcmd(b.top, ".fbrowse cget -actwidth");
	ws := int tkcmd(b.top, ".fbrowse.sy1 cget -width");
	if (nopanes == 1) {
		b.pane0width = tkcmd(b.top, ".fbrowse.c1 cget -actwidth") + " " +
						tkcmd(b.top, ".fbrowse.c2 cget -actwidth");
		tkcmd(b.top, "grid forget .fbrowse.sx2 .fbrowse.c2 .fbrowse.lmov");
		tkcmd(b.top, "grid columnconfigure .fbrowse 3 -weight 0");
	}
	else {
		(nil, wlist) := sys->tokenize(b.pane0width, " ");
		tkcmd(b.top, "grid columnconfigure .fbrowse 1 -weight "+hd wlist);
		tkcmd(b.top, "grid columnconfigure .fbrowse 3 -weight "+hd tl wlist);

		tkcmd(b.top, "grid .fbrowse.sx2 -row 3 -column 3 -sticky ew");
		tkcmd(b.top, "grid .fbrowse.c2 -row 2 -column 3 -sticky nsew");
		tkcmd(b.top, "grid .fbrowse.lmov -row 2 -column 2 -rowspan 2 -sticky ns");
	}
	b.nopanes = nopanes;
}

Browse.selectfile(b: self ref Browse, pane, action: int, file: File, tkpath: string)
{
	if (action == SELECT && b.selected[pane].tkpath == tkpath)
		return;
	if (b.selected[pane].tkpath != nil)
		tk->cmd(b.top, b.selected[pane].tkpath+" configure -bg "+bgnorm);
	if ((action == TOGGLE && b.selected[pane].tkpath == tkpath) || action == DESELECT) {
		if (pane == 0)
			popdirpane1(b, File (nil,nil));
		b.selected[pane] = (File(nil, nil), nil);
		return;
	}
	b.selected[pane] = (file, tkpath);
	tkcmd(b.top, tkpath+" configure -bg "+bgselect);
	if (pane == 0)
		popdirpane1(b, file);
}

Browse.resize(b: self ref Browse)
{
 	p1 := b.pane1;
 	b.pane1 = File (nil, nil);
 
 	if (p1.path != "")
 		popdirpane1(b, p1);

	if (b.selected[1].tkpath != nil) {
		s := b.selected[1];
		b.selectfile(1, DESELECT, s.file, s.tkpath);
		b.selectfile(1, SELECT, s.file, s.tkpath);
	}
}

setbrowsescrollr(b: ref Browse)
{
	h := tkcmd(b.top, ".fbrowse.fl cget -height");
	w := tkcmd(b.top, ".fbrowse.fl cget -width");
	tkcmd(b.top, ".fbrowse.c1 configure -scrollregion {0 0 "+w+" "+h+"}");
	if (b.nopanes == 2) {
		h = tkcmd(b.top, ".fbrowse.fl2 cget -height");
		w = tkcmd(b.top, ".fbrowse.fl2 cget -width");
		tkcmd(b.top, ".fbrowse.c2 configure -scrollregion {0 0 "+w+" "+h+"}");
	}
}

seeframe(top: ref Tk->Toplevel, frame: string)
{
	x := int tkcmd(top, frame+" cget -actx") - int tkcmd(top, ".fbrowse.fl cget -actx");
	y := int tkcmd(top, frame+" cget -acty")  - int tkcmd(top, ".fbrowse.fl cget -acty");
	w := int tkcmd(top, frame+" cget -width");
	h := int tkcmd(top, frame+" cget -height");
	wc := int tkcmd(top, ".fbrowse.c1 cget -width");
	hc := int tkcmd(top, ".fbrowse.c1 cget -height");
	if (w > wc)
		w = wc;
	if (h > hc)
		h = hc;
	tkcmd(top, sys->sprint(".fbrowse.c1 see %d %d %d %d",x,y,x+w,y+h));
}

# Goes to selected dir OR dir containing selected file
Browse.gotopath(b: self ref Browse, file: File, openfinal: int): (File, string)
{
	tkpath := ".fbrowse.fl.f0";
	path := b.root;
	testqid := "";
	testpath := "";
	close : list of string;
	trackbacklist : list of (string, list of string, list of string) = nil;
	trackback := 0;
	enddir := "";
	endfile := "";
	filetkpath := "";
	if (file.path[len file.path - 1] != '/') {
		# i.e. is not a directory
		p := isatback(file.path, "/");
		enddir = file.path[:p + 1];
	}
	if (enddir == path) {
		if (!dircontainsfile(b, File (path, nil), file))
			return (File (nil, nil), nil);
	}
	else {
		for(;;) {
			lst : list of string;
			if (trackback) {
				(path, lst, close) = hd trackbacklist;
				trackbacklist = tl trackbacklist;
				if (close != nil)
					b.opendir(File (hd close, hd tl close), hd tl tl close, CLOSE);
				trackback = 0;
			}
			else {
				frames := tkcmd(b.top, "grid slaves "+tkpath+" -column 1");
				(nil, lst) = sys->tokenize(frames, " ");
				if (lst != nil)
					lst = tl lst; # ignore first frame (name of parent dir);
			}
			found := 0;
			hasdups := 1;
			for (; lst != nil; lst = tl lst) {
				testpath = path;
				if (hasdups) {
					labels := tkcmd(b.top, "grid slaves "+hd lst+" -row 0");
					(nil, lst2) := sys->tokenize(labels, " ");
					testpath += tkcmd(b.top, hd tl lst2+" cget -text") + "/";
					testqid = getqidfromlabel(hd tl lst2);
					if (testqid == nil)
						hasdups = 0;
				}
				else
					testpath += tkcmd(b.top, hd lst+".l cget -text") + "/";
				if (len testpath <= len file.path && file.path[:len testpath] == testpath) {
					opened := 0;
					close = nil;
					if (openfinal || testpath != file.path)
						opened = b.opendir(File(testpath, testqid), hd lst, OPEN);
					if (opened)
						close = testpath :: testqid :: hd lst :: nil;
					if (tl lst != nil && hasdups)
						trackbacklist = (path, tl lst, close) :: trackbacklist;
					tkpath = hd lst;
					path = testpath;
					found = 1;
					break;
				}
			}
			if (enddir != nil && path == enddir)
				if (dircontainsfile(b, File(testpath, testqid), file))
					break;
			if (!found) {
				if (trackbacklist == nil)
					return (File (nil, nil), nil);
				trackback = 1;
			}
			else if (testpath == file.path && testqid == file.qid)
				break;
		}
	}
	seeframe(b.top, tkpath);
	dir := File (path, testqid);
	popdirpane1(b, dir);
	return (dir, tkpath);
}

dircontainsfile(b: ref Browse, dir, file: File): int
{
	(files, hasdups) := b.reader->readpath(dir);
	for (j := 0; j < len files; j++) {					
		if (files[j].name == file.path[len dir.path:] && 
				(!hasdups || files[j].qid.path == big file.qid))
			return 1;
	}
	return 0;
}

Browse.getpath(b: self ref Browse, f: string): ref File
{
	if (len f < 11 || f[:11] != ".fbrowse.fl")
		return nil;
	(nil, lst) := sys->tokenize(f, ".");
	lst = tl lst;
	if (hd lst == "fl2") {
		# i.e. is in pane 1
		qid := getqidfromlabel(f);
		return ref File (b.pane1.path + tk->cmd(b.top, f+" cget -text"), qid);
	}
	tkpath := ".fbrowse.fl.f0";
	path := b.root;
	lst = tl tl lst;
	started := 0;
#	sys->print("getpath: %s %s\n",tkpath, path);
	qid := "";
	for (; lst != nil; lst = tl lst) {
		tkpath += "."+hd lst;
		if ((hd lst)[0] == 'l') {
			qid = getqidfromlabel(tkpath);
			if (qid != nil)
				qid = "Q" + qid;
			if (len hd lst - len qid > 1)
				path += tk->cmd(b.top, tkpath+" cget -text");
		}
		else if ((hd lst)[0] == 'f') {
			qid = getqidfromframe(b,tkpath);
			if (qid != nil)
				qid = "Q"+qid;
			path += tk->cmd(b.top, tkpath+".l"+qid+" cget -text") + "/";
		}
#		sys->print("getpath: %s %s\n",tkpath, path);
	}
	# Temporary hack!
	if (qid != nil)
		qid = qid[1:];
	return ref File (path, qid);
}

setroot(b: ref Browse, rlabel, root: string)
{
	b.root = root;
	b.rlabel = rlabel;
	makedir(b, File (root, nil), ".fbrowse.fl.f0", rlabel, "0");
	tkcmd(b.top, "grid forget .fbrowse.fl.f0.lp");
}

getqidfromframe(b: ref Browse, frame: string): string
{
	tmp := tkcmd(b.top, "grid slaves "+frame+" -row 0");
	(nil, lst) := sys->tokenize(tmp, " \t\n");
	if (lst == nil)
		return nil;
	return getqidfromlabel(hd tl lst);
}

getqidfromlabel(label: string): string
{
	p := isatback(label, "Q");
	if (p != -1)
		return label[p+1:];
	return nil;
}

popdirpane0(b: ref Browse, dir : File, frame: string)
{
	(dirs, hasdups) := b.reader->readpath(dir);
	for (i := 0; i < len dirs; i++) {
		si := string i;
		f : string;
		dirqid := string dirs[i].qid.path;
		if (!hasdups)
			dirqid = nil;
		if (dirs[i].mode & sys->DMDIR) {
			f = frame + ".f"+si;
			makedir(b, File (dir.path+dirs[i].name, dirqid), f, dirs[i].name, string (i+1));
		}
		else {
			if (b.nopanes == 1) {
				f = frame + ".l"+si;
				makefile(b, f, dirs[i].name, string (i+1), dirqid);
			}
		}
	}
	dirs = nil;
}

isopened(b: ref Browse, dir: File): int
{
	for (tmp := b.opened; tmp != nil; tmp = tl tmp) {
		if (File.eq(hd tmp, dir))
			return 1;
	}
	return 0;
}

makefile(b: ref Browse, f, name, row, qid: string)
{
	if (qid != nil)
		f += "Q" + qid;
	bgcol := bgnorm;
#	if (f == selected[0].t1)
#		bgcol = bgselect;
	p := isat(name, "\0");
	if (p != -1) {
		tkcmd(b.top, "label "+f+" -text {"+name[:p]+"} -bg "+bgcol+ft);
		tkcmd(b.top, "label "+f+"b -text {"+name[p+1:]+"} -bg "+bgcol+ft);
		tkcmd(b.top, "grid "+f+" -row "+row+" -column 1 -sticky w -padx 5 -pady 2");
		tkcmd(b.top, "grid "+f+"b -row "+row+" -column 2 -sticky w -pady 2");
		tkcmd(b.top, "bind "+f+" <Button-2> {send "+b.tkchan+" but2pane1 "+f+"}");
		tkcmd(b.top, "bind "+f+" <ButtonRelease-2> {send "+b.tkchan+" release}");
	}
	else {
		tkcmd(b.top, "label "+f+" -text {"+name+"} -bg "+bgcol+ft);
		tkcmd(b.top, "grid "+f+" -row "+row+" -column 1 -sticky w -padx 5 -pady 2");
	}
	tkcmd(b.top, "bind "+f+" <Button-1> {send "+b.tkchan+" but1pane0 "+f+"}");
	tkcmd(b.top, "bind "+f+" <ButtonRelease-1> {send "+b.tkchan+" release}");
	tkcmd(b.top, "bind "+f+" <Button-2> {send "+b.tkchan+" but2pane0 "+f+"}");
	tkcmd(b.top, "bind "+f+" <ButtonRelease-2> {send "+b.tkchan+" release}");
	tkcmd(b.top, "bind "+f+" <Button-3> {send "+b.tkchan+" but3pane0 "+f+"}");
	tkcmd(b.top, "bind "+f+" <ButtonRelease-3> {send "+b.tkchan+" release}");
}

Browse.defaultaction(b: self ref Browse, lst: list of string, rfile: ref File)
{
	tkpath: string;
	file: File;
	if (len lst > 1) {
		tkpath = hd tl lst;
		if (len tkpath > 11 && tkpath[:11] == ".fbrowse.fl") {
			if (rfile == nil)
				file = *b.getpath(tkpath);
			else
				file = *rfile;
		}
	}
	case hd lst {
		"release" =>
			b.released = 1;
		"open" or "double1pane0" =>
			if (file.path == b.root)
				break;
			if (b.released) {
				b.selectfile(0, DESELECT, File(nil, nil), nil);
				b.selectfile(1, DESELECT, File(nil, nil), nil);
				b.opendir(file, prevframe(tkpath), TOGGLE);
				b.selectfile(0, SELECT, file, tkpath);
				b.released = 0;
			}
		"double1pane1" =>
			b.gotoselectfile(file);
		"but1pane0" =>
			if (b.released) {
				b.selectfile(1, DESELECT, File(nil, nil), nil);
				b.selectfile(0, TOGGLE, file, tkpath);
				b.released = 0;
			}
 		"but1pane1" =>
			if (b.released) {
				b.selectfile(1, TOGGLE, file, tkpath);
				b.released = 0;
			}
 		"movdiv" =>
			movdiv(b, int hd tl lst);
	}
}

prevframe(tkpath: string): string
{
	end := len tkpath;
	for (;;) {
		p := isatback(tkpath[:end], ".");
		if (tkpath[p+1] == 'f')
			return tkpath[:end];
		end = p;
	}
	return nil;
}

makedir(b: ref Browse, dir: File, f, name, row: string)
{
	bgcol := bgnorm;
	if (f == ".fbrowse.fl.f0")
		dir = File (b.root, nil);
#	if (name == "")
#		name = path;
	if (dir.path[len dir.path - 1] != '/')
		dir.path[len dir.path] = '/';
	if (File.eq(dir, b.selected[0].file))
		bgcol = bgselect;
	tkcmd(b.top, "frame "+f+" -bg white");
	label := f+".l";
	if (dir.qid != nil)
		label += "Q" + dir.qid;
	tkcmd(b.top, "label "+label+" -text {"+name+"} -bg "+bgcol+ftb);
	if (isopened(b, dir)) {
		popdirpane0(b, dir, f);
		tkcmd(b.top, "label "+f+".lp -text {-} -borderwidth 1 -relief sunken -height 8 -width 8"+fts);
	}
	else tkcmd(b.top, "label "+f+".lp -text {+} -borderwidth 1 -relief raised -height 8 -width 8"+fts);
	tkcmd(b.top, "bind "+label+" <Button-1> {send "+b.tkchan+" but1pane0 "+label+"}");
	tkcmd(b.top, "bind "+label+" <Double-Button-1> {send "+b.tkchan+" double1pane0 "+label+"}");
	tkcmd(b.top, "bind "+label+" <ButtonRelease-1> {send "+b.tkchan+" release}");
	tkcmd(b.top, "bind "+label+" <Button-3> {send "+b.tkchan+" but3pane0 "+label+"}");
	tkcmd(b.top, "bind "+label+" <ButtonRelease-3> {send "+b.tkchan+" release}");
	tkcmd(b.top, "bind "+label+" <Button-2> {send "+b.tkchan+" but2pane0 "+label+"}");
	tkcmd(b.top, "bind "+label+" <ButtonRelease-2> {send "+b.tkchan+" release}");

	tkcmd(b.top, "bind "+f+".lp <Button-1> {send "+b.tkchan+" open "+label+"}");
	tkcmd(b.top, "bind "+f+".lp <ButtonRelease-1> {send "+b.tkchan+" release}");
	tkcmd(b.top, "grid "+f+".lp -row 0 -column 0");
	tkcmd(b.top, "grid "+label+" -row 0 -column 1 -sticky w -padx 5 -pady 2 -columnspan 2");
	tkcmd(b.top, "grid "+f+" -row "+row+" -column 1 -sticky w -padx 5 -columnspan 2");
}

popdirpane1(b: ref Browse, dir: File)
{
#	if (path == b.pane1.path && qid == b.pane1.qid)
#		return;
	b.pane1 = dir;
	labelset(b, ".fbrowse.l", prevpath(dir.path+"/"));
	if (b.nopanes == 1)
		return;
	tkcmd(b.top, "destroy .fbrowse.fl2; frame .fbrowse.fl2 -bg white");
	tkcmd(b.top, ".fbrowse.c2 create window 0 0 -window .fbrowse.fl2 -anchor nw");
	if (dir.path == nil) {
		setbrowsescrollr(b);
		return;
	}
	(dirs, hasdups) := b.reader->readpath(dir);
#	if (path[len path - 1] == '/')
#		path = path[:len path - 1];
#	tkcmd(b.top, "label .fbrowse.fl2.l -text {"+path+"}");
	row := 0;
	col := 0;
	tkcmd(b.top, ".fbrowse.c2 see 0 0");
	ni := 0;
	n := (int tkcmd(b.top, ".fbrowse.c2 cget -actheight")) / 21;
	for (i := 0; i < len dirs; i++) {

		f := ".fbrowse.fl2.l"+string ni;
		if (hasdups)
			f += "Q" + string dirs[i].qid.path;
		name := dirs[i].name;
		isdir := dirs[i].mode & sys->DMDIR;
		if (isdir)
			name[len name]= '/';
		bgcol := bgnorm;
		# Sort this out later
		# if (path+"/"+name == selected[1].t0) {
		#	bgcol = bgselect;
		#	selected[1].t1 = f;
		#}
		tkcmd(b.top, "label "+f+" -text {"+name+"} -bg "+bgcol+ft);
		tkcmd(b.top, "bind "+f+" <Double-Button-1> {send "+b.tkchan+" double1pane1 "+f+"}");
		tkcmd(b.top, "bind "+f+" <Button-1> {send "+b.tkchan+" but1pane1 "+f+"}");
		tkcmd(b.top, "bind "+f+" <ButtonRelease-1> {send "+b.tkchan+" release}");
		tkcmd(b.top, "bind "+f+" <Button-3> {send "+b.tkchan+" but3pane1 "+f+" %X %Y}");
		tkcmd(b.top, "bind "+f+" <ButtonRelease-3> {send "+b.tkchan+" release}");
		tkcmd(b.top, "grid "+f+" -row "+string row+" -column "+string col+
					" -sticky w -padx 10 -pady 2");
		row++;
		if (row >= n) {
			row = 0;
			col++;
		}		
		ni++;
	}

	dirs = nil;
	setbrowsescrollr(b);
}

pane0scr := array[] of {
	"frame .fbrowse",

	"scrollbar .fbrowse.sy1 -command {.fbrowse.c1 yview}",
	"scrollbar .fbrowse.sx1 -command {.fbrowse.c1 xview} -orient horizontal",
	"canvas .fbrowse.c1 -yscrollcommand {.fbrowse.sy1 set} -xscrollcommand {.fbrowse.sx1 set} -bg white -width 50 -height 20 -borderwidth 2 -relief sunken -xscrollincrement 10 -yscrollincrement 21",
	"grid .fbrowse.sy1 -row 2 -column 0 -sticky ns -rowspan 2",
	"grid .fbrowse.sx1 -row 3 -column 1 -sticky ew",
	"grid .fbrowse.c1 -row 2 -column 1 -sticky nsew",
	"grid rowconfigure .fbrowse 2 -weight 1",
	"grid columnconfigure .fbrowse 1 -weight 2",

};

pane1scr := array[] of {
#	".fbrowse.c1 configure -width 146",
	"frame .fbrowse.fl2 -bg white",
	"label .fbrowse.fl2.l -text {}",
	"scrollbar .fbrowse.sx2 -command {.fbrowse.c2 xview} -orient horizontal",
	"label .fbrowse.lmov -text { } -relief sunken -borderwidth 2 -width 5",
	
	"canvas .fbrowse.c2 -xscrollcommand {.fbrowse.sx2 set} -bg white -width 50 -height 20 -borderwidth 2 -relief sunken -xscrollincrement 10 -yscrollincrement 21",
	".fbrowse.c2 create window 0 0 -window .fbrowse.fl2 -anchor nw",
	"grid .fbrowse.sx2 -row 3 -column 3 -sticky ew",
	"grid .fbrowse.c2 -row 2 -column 3 -sticky nsew",
	"grid .fbrowse.lmov -row 2 -column 2 -rowspan 2 -sticky ns",
	"grid columnconfigure .fbrowse 3 -weight 3",
};

Browse.newroot(b: self ref Browse, root, rlabel: string)
{
	tk->cmd(b.top, "destroy .fbrowse.fl");
	tkcmd(b.top, "frame .fbrowse.fl -bg white");
	tkcmd(b.top, ".fbrowse.c1 create window 0 0 -window .fbrowse.fl -anchor nw");
	b.pane1 = File (root, nil);
	setroot(b, rlabel, root);
	setbrowsescrollr(b);
}

Browse.showpath(b: self ref Browse, on: int)
{
	if (on == b.showpathlabel)
		return;
	if (on) {
		b.showpathlabel = 1;
		if (b.pane1.path != nil)
			labelset(b, ".fbrowse.l", prevpath(b.pane1.path+"/"));
	}
	else {
		b.showpathlabel = 0;
		tkcmd(b.top, ".fbrowse.l configure -text {}");
	}	
}

Browse.getselected(b: self ref Browse, pane: int): File
{
	return b.selected[pane].file;
}

labelset(b: ref Browse, label, text: string)
{
	if (!b.showpathlabel)
		return;
	if (text != nil) {
		tmp := b.rlabel;
		if (tmp[len tmp - 1] != '/')
			tmp[len tmp] = '/';
		text = tmp + text[len b.root:];
	}
	tkcmd(b.top, label + " configure -text {"+text+"}");
}

movdiv(b: ref Browse, x: int)
{
	x1 := int tkcmd(b.top, ".fbrowse.lmov cget -actx");
	x2 := x1 + int tkcmd(b.top, ".fbrowse.lmov cget -width");
	diff := 0;
	if (x < x1)
		diff = x - x1;
	if (x > x2)
		diff = x - x2;
	if (abs(diff) > 5) {
		w1 := int tkcmd(b.top, ".fbrowse.c1 cget -actwidth");
		w2 := int tkcmd(b.top, ".fbrowse.c2 cget -actwidth");
		if (w1 + diff < 36)
			diff = 36 - w1;
		if (w2 - diff < 36)
			diff = w2 - 36;
		w1 += diff;
		w2 -= diff;
		# sys->print("w1: %d w2: %d\n",w1,w2);
		tkcmd(b.top, "grid columnconfigure .fbrowse 1 -weight "+string w1);
		tkcmd(b.top, "grid columnconfigure .fbrowse 3 -weight "+string w2);
	}
}


dialog(ctxt: ref draw->Context, oldtop: ref Tk->Toplevel, butlist: list of string, title, msg: string): int
{
	(top, titlebar) := tkclient->toplevel(ctxt, "", title, tkclient->Popup);
	butchan := chan of string;
	tk->namechan(top, butchan, "butchan");
	tkcmd(top, "frame .f");
	tkcmd(top, "label .f.l -text {"+msg+"} -font /fonts/charon/plain.normal.font");
	tkcmd(top, "bind .Wm_t <Button-1> +{focus .}");
	tkcmd(top, "bind .Wm_t.title <Button-1> +{focus .}");

	l := len butlist;
	tkcmd(top, "grid .f.l -row 0 -column 0 -columnspan "+string l+" -sticky w -padx 10 -pady 5");
	i := 0;
	for(; butlist != nil; butlist = tl butlist) {
		si := string i;
		tkcmd(top, "button .f.b"+si+" -text {"+hd butlist+"} "+
			"-font /fonts/charon/plain.normal.font -command {send butchan "+si+"}");
		tkcmd(top, "grid .f.b"+si+" -row 1 -column "+si+" -padx 5 -pady 5");
		i++;
	}
	placement := "";
	if (oldtop != nil) {
		setcentre(oldtop, top);
		placement = "exact";
	}
	tkcmd(top, "pack .f; update; focus .");
	tkclient->onscreen(top, placement);
	tkclient->startinput(top, "kbd"::"ptr"::nil);
	for (;;) {
		alt {
		s := <-top.ctxt.kbd =>
			tk->keyboard(top, s);
		s := <-top.ctxt.ptr =>
			tk->pointer(top, *s);
		inp := <- butchan =>
			tkcmd(oldtop, "focus .");
			return int inp;
		title = <-top.ctxt.ctl or
		title = <-top.wreq or
		title = <-titlebar =>
			if (title == "exit") {
				tkcmd(oldtop, "focus .");
				return -1;
			}
			tkclient->wmctl(top, title);
		}
	}
}
######################## Select Functions #########################


setselectscrollr(s: ref Select, f: string)
{
	h := tkcmd(s.top, f+" cget -height");
	w := tkcmd(s.top, f+" cget -width");
	tkcmd(s.top, ".fselect.c configure -scrollregion {0 0 "+w+" "+h+"}");
}

Select.setscrollr(s: self ref Select, fname: string)
{
	frame := getframe(s, fname);
	if (frame != nil)
		setselectscrollr(s,frame.path);
}

Select.new(top: ref Tk->Toplevel, tkchanname: string): ref Select
{
	s: Select;
	s.top = top;
	s.tkchan = tkchanname;
	s.frames = nil;
	s.currfname = nil;
	s.currfid = nil;
	tkcmds(top, selectscr);
	if (entryheight == nil) {
		tkcmd(top, "entry .fselect.test");
		entryheight = " -height " + tkcmd(top, ".fselect.test cget -height");
		tkcmd(top, "destroy .fselect.test");
	}
	for (i := 1; i < 4; i++)
		tkcmd(top, "bind .fselect.c <ButtonRelease-"+string i+"> {send "+s.tkchan+" release}");
	return ref s;
}

selectscr := array[] of {
	"frame .fselect",
	"scrollbar .fselect.sy -command {.fselect.c yview}",
	"scrollbar .fselect.sx -command {.fselect.c xview} -orient horizontal",
	"canvas .fselect.c -yscrollcommand {.fselect.sy set} -xscrollcommand {.fselect.sx set} -bg white -width 414 -borderwidth 2 -relief sunken -height 180 -xscrollincrement 10 -yscrollincrement 19",

	"grid .fselect.sy -row 0 -column 0 -sticky ns -rowspan 2",
	"grid .fselect.sx -row 1 -column 1 -sticky ew",
	"grid .fselect.c -row 0 -column 1",
};

Select.addframe(s: self ref Select, fname, title: string)
{
	if (isat(fname, " ") != -1)
		return;
	f := ".fselect.f"+fname;
	tkcmd(s.top, "frame "+f+" -bg white");
	if (title != nil){
		tkcmd(s.top, "label "+f+".l -text {"+title+"} -bg white "+
			"-font /fonts/charon/bold.normal.font; "+
			"grid "+f+".l -row 0 -column 0 -columnspan 3 -sticky w");
	}
	fr: Frame;
	fr.name = fname;
	fr.path = f;
	fr.selected = nil;
	s.frames = ref fr :: s.frames;
}

getframe(s: ref Select, fname: string): ref Frame
{
	for (tmp := s.frames; tmp != nil; tmp = tl tmp)
		if ((hd tmp).name == fname)
			return hd tmp;
	return nil;
}

Select.delframe(s: self ref Select, fname: string)
{
	if (s.currfname == fname) {
		tkcmd(s.top, ".fselect.c delete " + s.currfid);
		s.currfid = nil;
		s.currfname = nil;
	}
	f := getframe(s,fname);
	if (f != nil) {
		tkcmd(s.top, "destroy "+f.path);
		tmp: list of ref Frame = nil;
		for (;s.frames != nil; s.frames = tl s.frames) {
			if ((hd s.frames).name != fname)
				tmp = hd s.frames :: tmp;
		}
		s.frames = tmp;
	}
}

Select.showframe(s: self ref Select, fname: string)
{
	if (s.currfid != nil)
		tkcmd(s.top, ".fselect.c delete " + s.currfid);
	f := getframe(s, fname);
	if (f != nil) {
		s.currfid = tkcmd(s.top, ".fselect.c create window 0 0 "+
				"-window "+f.path+" -anchor nw");
		s.currfname = fname;
	}
}

Select.addselection(s: self ref Select, fname, text: string, lp: list of ref Parameter, allowdups: int): string
{
	fr := getframe(s, fname);
	if (fr == nil)
		return nil;
	f := fr.path;
	if (!allowdups) {
		slv := tkcmd(s.top, "grid slaves "+f+" -column 0");
		(nil, slaves) := sys->tokenize(slv, " \t\n");
		for (; slaves != nil; slaves = tl slaves) {
			if (text == tkcmd(s.top, hd slaves+" cget -text"))
				return nil;
		}
	}
	font := " -font /fonts/charon/plain.normal.font";
	fontb := " -font /fonts/charon/bold.normal.font";
	(id, row) := newselected(s.top, f);
	sid := string id;
	label := f+".l"+sid;
	tkcmd(s.top, "label "+label+" -text {"+text+"} -bg white"+entryheight+font);
	gridpack := label+" ";
	paramno := 0;
	for (; lp != nil; lp = tl lp) {
		spn := string paramno;
		pframe := f+".f"+sid+"P"+spn;
		tkcmd(s.top, "frame "+pframe+" -bg white");
		pick p := hd lp {
		ArgIn =>
			tkp1 := pframe+".lA";
			tkp2 := pframe+".eA";

			tkcmd(s.top, "label "+tkp1+" -text {"+p.name+"} "+
					"-bg white "+entryheight+fontb);
			tkcmd(s.top, "entry "+tkp2+" -bg white -width 50 "+
					"-borderwidth 1"+entryheight+font);
			if (p.initval != nil)
				tkcmd(s.top, tkp2+" insert end {"+p.initval+"}");
			tkcmd(s.top, "grid "+tkp1+" "+tkp2+" -row 0");
			
		IntIn =>
			tkp1 := pframe+".sI";
			tkp2 := pframe+".lI";
			tkcmd(s.top, "scale "+tkp1+" -showvalue 0 -orient horizontal -height 20"+
				" -from "+string p.min+" -to "+string p.max+" -command {send "+
				s.tkchan+" scale "+tkp2+"}");
			tkcmd(s.top, tkp1+" set "+string p.initval);
			tkcmd(s.top, "label "+tkp2+" -text {"+string p.initval+"} "+
					"-bg white "+entryheight+fontb);
			tkcmd(s.top, "grid "+tkp1+" "+tkp2+" -row 0");
			
		}
		gridpack += " "+pframe;
		paramno++;
	}
	tkcmd(s.top, "grid "+gridpack+" -row "+row+" -sticky w");
	
	sendstr := " " + label + " %X %Y}";
	tkcmd(s.top, "bind "+label+" <Double-Button-1> {send "+s.tkchan+" double1"+sendstr);
	tkcmd(s.top, "bind "+label+" <Button-1> {send "+s.tkchan+" but1"+sendstr);
	tkcmd(s.top, "bind "+label+" <ButtonRelease-1> {send "+s.tkchan+" release}");
	tkcmd(s.top, "bind "+label+" <Button-2> {send "+s.tkchan+" but2"+sendstr);
	tkcmd(s.top, "bind "+label+" <ButtonRelease-2> {send "+s.tkchan+" release}");
	tkcmd(s.top, "bind "+label+" <Button-3> {send "+s.tkchan+" but3"+sendstr);
	tkcmd(s.top, "bind "+label+" <ButtonRelease-3> {send "+s.tkchan+" release}");
	setselectscrollr(s, f);
	if (s.currfname == fname) {
		y := int tkcmd(s.top, label+"  cget -acty") -
			int tkcmd(s.top, f+" cget -acty");
		h := int tkcmd(s.top, label+"  cget -height");
		tkcmd(s.top, ".fselect.c see 0 "+string (h+y));
	}
	return label;
}

newselected(top: ref Tk->Toplevel, frame: string): (int, string)
{
	(n, slaves) := sys->tokenize(tkcmd(top, "grid slaves "+frame+" -column 0"), " \t\n");
	id := 0;
	slaves = tl slaves; # Ignore Title
	for (;;) {
		if (isin(slaves, frame+".l"+string id))
			id++;
		else break;
	}
	return (id, string n);
}

isin(l: list of string, test: string): int
{
	for(tmpl := l; tmpl != nil; tmpl = tl tmpl)
		if (hd tmpl == test)
			return 1;
	return 0;
}

Select.delselection(s: self ref Select, fname, tkpath: string)
{
	f := getframe(s, fname);
	(row, nil) := getrowcol(s.top, tkpath);
	slaves := tkcmd(s.top, "grid slaves "+f.path+" -row "+row);
	# sys->print("row %s: deleting: %s\n",row,slaves);
	tkcmd(s.top, "grid rowdelete "+f.path+" "+row);
	tkcmd(s.top, "destroy "+slaves);
	# Select the next one if the item deleted was selected
	if (f.selected == tkpath) {
		f.selected = nil;
		for (;;) {
			slaves = tkcmd(s.top, "grid slaves "+f.path+" -row "+row);
			if (slaves != nil)
				break;
			r := (int row) - 1;
			if (r < 1)
				return;
			row = string r;
		}
		(nil, lst) := sys->tokenize(slaves, " ");
		if (lst != nil)
			s.select(fname, hd lst, SELECT);
	}
}

getrowcol(top: ref Tk->Toplevel, s: string): (string, string)
{
	row := "";
	col := "";
	(nil, lst) := sys->tokenize(tkcmd(top, "grid info "+s), " \t\n");
	for (; lst != nil; lst = tl lst) {	
		if (hd lst == "-row")
			row = hd tl lst;
		else if (hd lst == "-column")
			col = hd tl lst;
	}
	return (row, col);
}

Select.select(s: self ref Select, fname, tkpath: string, action: int)
{
	f := getframe(s, fname);
	if (action == SELECT && f.selected == tkpath)
		return;
	if (f.selected != nil)
		tkcmd(s.top, f.selected+" configure -bg "+bgnorm);
	if ((action == TOGGLE && f.selected == tkpath) || action == DESELECT)
		f.selected = nil;
	else {
		tkcmd(s.top, tkpath+" configure -bg "+bgselect);
		f.selected = tkpath;
	}
}

Select.defaultaction(s: self ref Select, lst: list of string)
{
	case hd lst {
		"but1" =>
			s.select(s.currfname, hd tl lst, TOGGLE);
		"scale" =>
			tkcmd(s.top, hd tl lst+" configure -text {"+hd tl tl lst+"}");
	}
}

Select.getselected(s: self ref Select, fname: string): string
{
	retlist : list of (int, list of ref Parameter) = nil;
	row := 1;
	f := getframe(s, fname);
	return f.selected;
}

Select.getselection(s: self ref Select, fname: string): list of (string, list of ref Parameter)
{
	retlist : list of (string, list of ref Parameter) = nil;
	row := 1;
	f := getframe(s, fname);
	for (;;) {
		slaves := tkcmd(s.top, "grid slaves "+f.path+" -row "+string (row++));
		# sys->print("slaves: %s\n",slaves);
		if (slaves == nil || slaves[0] == '!')
			break;
		(nil, lst) := sys->tokenize(slaves, " ");
		pos := isatback(hd lst, "l");
		tkpath := hd lst;
		lst = tl lst;
		lp : list of ref Parameter = nil;
		for (; lst != nil; lst = tl lst) {
			pslaves := tkcmd(s.top, "grid slaves "+hd lst);
			(nil, plist) := sys->tokenize(pslaves, " ");
			# sys->print("slaves of %s - hd plist: '%s'\n",hd lst, hd plist);
			case (hd plist)[len hd plist - 3:] {
				".eA" or ".lA" =>
					argname := tkcmd(s.top, hd lst+".lA cget -text");
					argval := tkcmd(s.top, hd lst+".eA get");
					lp = ref Parameter.ArgOut(argname, argval) :: lp;
				".sI" or ".lI" =>
					val := int tkcmd(s.top, hd lst+".lI cget -text");
					lp = ref Parameter.IntOut(val) :: lp;
			}
		}
		retlist = (tkpath, lp) :: retlist;	
	}
	return retlist;
}

Select.resize(s: self ref Select, width, height: int)
{
	ws := int tkcmd(s.top, ".fselect.sy cget -width");
	hs := int tkcmd(s.top, ".fselect.sx cget -height");

	tkcmd(s.top, ".fselect.c configure -width "+string (width - ws - 8)+
			" -height "+string (height - hs - 8));
	f := getframe(s, s.currfname);
	if (f != nil)
		setselectscrollr(s, f.path);

	tkcmd(s.top, "update");
}

File.eq(a,b: File): int
{
	if (a.path != b.path || a.qid != b.qid)
		return 0;
	return 1;
}


######################## General Functions ########################

setcentre(top1, top2: ref Tk->Toplevel)
{
	x1 := int tkcmd(top1, ". cget -actx");
	y1 := int tkcmd(top1, ". cget -acty");
	h1 := int tkcmd(top1, ". cget -height");
	w1 := int tkcmd(top1, ". cget -width");

	h2 := int tkcmd(top2, ".f cget -height");
	w2 := int tkcmd(top2, ".f cget -width");

	newx := (x1 + (w1 / 2)) - (w2/2);
	newy := (y1 + (h1 / 2)) - (h2/2);
	tkcmd(top2, ". configure -x "+string newx+" -y "+string newy);
}

abs(x: int): int
{
	if (x < 0)
		return -x;
	return x;
}

prevpath(path: string): string
{
	if (path == nil)
		return nil;
	p := isatback(path[:len path - 1], "/");
	if (p == -1)
		return nil;
	return path[:p+1];
}

isat(s, test: string): int
{
	if (len test > len s)
		return -1;
	for (i := 0; i < (1 + len s - len test); i++)
		if (test == s[i:i+len test])
			return i;
	return -1;
}

isatback(s, test: string): int
{
	if (len test > len s)
		return -1;
	for (i := len s - len test; i >= 0; i--)
		if (test == s[i:i+len test])
			return i;
	return -1;
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

badmod(path: string)
{
	sys->print("Browser: failed to load: %s\n",path);
	exit;
}
