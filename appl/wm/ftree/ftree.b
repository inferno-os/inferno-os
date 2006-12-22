implement Ftree;

include "sys.m";
	sys: Sys;
include "draw.m";
	draw: Draw;
	Point, Rect: import draw;
include "tk.m";
	tk: Tk;
include "tkclient.m";
	tkclient: Tkclient;
include "readdir.m";
	readdir: Readdir;
include "items.m";
	items: Items;
	Item, Expander: import items;
include "plumbmsg.m";
	plumbmsg: Plumbmsg;
	Msg: import plumbmsg;
include "sh.m";
	sh: Sh;
include "popup.m";
	popup: Popup;
include "cptree.m";
	cptree: Cptree;
include "string.m";
	str: String;
include "arg.m";
	arg: Arg;

stderr: ref Sys->FD;

Ftree: module {
	init: fn(ctxt: ref Draw->Context, argv: list of string);
};

Tree: adt {
	fname: string;
	pick {
	L =>
	N =>
		e: ref Expander;
		sub: cyclic array of ref Tree;
	}
};

tkcmds := array[] of {
	"frame .top",
	"label .top.l -text |",
	"pack .top.l -side left -expand 1 -fill x",
	"frame .f",
	"canvas .c -yscrollcommand {.f.s set}",
	"scrollbar .f.s -command {.c yview}",
	"pack .f.s -side left -fill y",
	"pack .c -side top -in .f -fill both -expand 1",
	"pack .top -anchor w",
	"pack .f -fill both -expand 1",
	"pack propagate . 0",
	".top.l configure -text {}",
};

badmodule(p: string)
{
	sys->fprint(stderr, "ftree: cannot load %s: %r\n", p);
	raise "fail:bad module";
}

tkwin: ref Tk->Toplevel;
root := "/";

cpfile := "";

usage()
{
	sys->fprint(stderr, "usage: ftree [-e] [-E] [-p] [-d] [root]\n");
	raise "fail:usage";
}

plumbinprogress := 0;
disallow := 1;
plumbed: chan of int;
roottree: ref Tree.N;
rootitem: Item;
runplumb := 1;

init(ctxt: ref Draw->Context, argv: list of string)
{
	loadmods();
	if (ctxt == nil) {
		sys->fprint(sys->fildes(2), "ftree: no window context\n");
		raise "fail:bad context";
	}
	draw = load Draw Draw->PATH;
	noexit := 0;
	winopts := Tkclient->Resize | Tkclient->Hide;
	arg->init(argv);
	while ((opt := arg->opt()) != 0) {
		case opt {
		'e' =>
			(noexit, winopts) = (1, Tkclient->Resize);
		'E' =>
			(noexit, winopts) = (1, 0);
		'p' =>
			(noexit, winopts) = (0, 0);
		'd' =>
			disallow = 0;
		'P' =>
			runplumb = 1;
		* =>
			usage();
		}
	}
	argv = arg->argv();
	if (argv != nil && tl argv != nil)
		usage();
	if (argv != nil) {
		root = hd argv;
		(ok, s) := sys->stat(root);
		if (ok == -1) {
			sys->fprint(stderr, "ftree: %s: %r\n", root);
			raise "fail:bad root";
		} else if ((s.mode & Sys->DMDIR) == 0) {
			sys->fprint(stderr, "ftree: %s is not a directory\n", root);
			raise "fail:bad root";
		}
	}

	sys->pctl(Sys->NEWPGRP|Sys->FORKNS, nil);

	(win, wmctl) := tkclient->toplevel(ctxt, nil, "Ftree", winopts);
	tkwin = win;
	for (i := 0; i < len tkcmds; i++)
		cmd(win, tkcmds[i]);
	fittoscreen(win);
	cmd(win, "update");

	event := chan of string;
	tk->namechan(win, event, "event");

	clickfile := chan of string;
	tk->namechan(win, clickfile, "clickfile");

	sys->bind("#s", "/chan", Sys->MBEFORE);
	fio := sys->file2chan("/chan", "plumbstart");
	if (fio == nil) {
		sys->fprint(stderr, "ftree: cannot make /chan/plumbstart: %r\n");
		raise "fail:error";
	}
	nsfio := sys->file2chan("/chan", "nsupdate");
	if (nsfio == nil)  {
		sys->fprint(stderr, "ftree: cannot make /chan/nsupdate: %r\n");
		raise "fail:error";
	}

	if (runplumb){
		if((err := sh->run(ctxt, "plumber" :: "-n" :: "-w" :: "-c/chan/plumbstart" :: nil)) != nil)
			sys->fprint(stderr, "ftree: can't start plumber: %s\n", err);
	}

	plumbmsg = load Plumbmsg Plumbmsg->PATH;
	if (plumbmsg != nil && plumbmsg->init(1, nil, 0) == -1) {
		sys->fprint(stderr, "ftree: no plumber\n");
		plumbmsg = nil;
	}

	nschanged := chan of string;
	roottree = ref Tree.N("/", Expander.new(win, ".c"), nil);
	rootitem = roottree.e.make(items->maketext(win, ".c", "/", "/"));
	cmd(win, ".c configure -width " + string rootitem.r.dx() + " -height " + string rootitem.r.dy() +
		" -scrollregion {" + r2s(rootitem.r) + "}");
	sendevent("/", "expand");
	tkclient->onscreen(win, nil);
	tkclient->startinput(win, "ptr"::nil);
	cmd(win, "update");

	plumbed = chan of int;
	for (;;) alt {
	key := <-win.ctxt.kbd =>
		tk->keyboard(win, key);
	m := <-win.ctxt.ptr =>
		tk->pointer(win, *m);
	s := <-win.ctxt.ctl or
	s = <-win.wreq or
	s = <-wmctl =>
		if (noexit && s == "exit")
			s = "task";
		tkclient->wmctl(win, s);
	s := <-event =>
		(target, ev) := eventtarget(s);
		sendevent(target, ev);
	m := <-clickfile =>
		(n, toks) := sys->tokenize(m, " ");
		(b, s) := (hd toks, hd tl toks);
		if (b == "menu") {
			c := chan of (ref Tree, Item, chan of Item);
			nsu := chan of string;
			spawn menuproc(c, nsu);
			found := operate(s, c);
			if (found) {
				if ((upd := <-nsu) != nil)
					updatens(upd);
			}
		} else if (b == "plumb")
			plumbit(s);
	ok := <-plumbed =>
		colour := "#00ff00";
		if (!ok)
			colour = "red";
		cmd(tkwin, ".c itemconfigure highlight -fill " + colour);
		cmd(tkwin, "update");
		plumbinprogress = 0;
	s := <-nschanged =>
		sys->print("got nschanged: %s\n", s);
		updatens(s);
	(nil, nil, nil, rc) := <-nsfio.read =>
		if (rc != nil)
			readreply(rc, nil, "permission denied");
	(nil, data, nil, wc) := <-nsfio.write =>
		if (wc == nil)
			break;
		s := cleanname(string data);
		if (len s >= len root && s[0:len root] == root) {
			s = s[len root:];
			if (s == nil)
				s = "/";
			if (s[0] == '/')
				updatens(s);
		}
		writereply(wc, len data, nil);
	(nil, nil, nil, rc) := <-fio.read =>
		if (rc != nil)
			readreply(rc, nil, "permission denied");
	(nil, data, nil, wc) := <-fio.write =>
		if (wc == nil)
			break;
		s := string data;
		if (len s == 0 || s[0] != 's')
			writereply(wc, 0, "invalid write");
		cmd := str->unquoted(s);
		if (cmd == nil || tl cmd == nil || tl tl cmd == nil) {
			writereply(wc, 0, "invalid write");
		} else {
			if (hd tl tl cmd == "+ftree")
				runsubftree(ctxt, tl tl tl cmd);
			else
				sh->run(ctxt, "{$* &}" :: tl tl cmd);
			writereply(wc, len data, nil);
		}
	}
}

runsubftree(ctxt: ref Draw->Context, c: list of string)
{
	if (len c < 2) {
		return;
	}
	cmd(tkwin, ". unmap");
	sh->run(ctxt, c);
	cmd(tkwin, ". map");
}

sendevent(target, ev: string)
{
	c := chan of (ref Tree, Item, chan of Item);
	spawn sendeventproc(ev, c);
	operate(target, c);
	cmd(tkwin, "update");
}

# non-blocking reply to read request, in case client has gone away.
readreply(reply: Sys->Rread, data: array of byte, err: string)
{
	alt {
	reply <-= (data, err) =>;
	* =>;
	}
}

# non-blocking reply to write request, in case client has gone away.
writereply(reply: Sys->Rwrite, count: int, err: string)
{
	alt {
	reply <-= (count, err) =>;
	* =>;
	}
}

plumbit(f: string)
{
	if (!plumbinprogress) {
		highlight(f, "yellow", 2000);
		spawn plumbproc(root + f, plumbed);
		plumbinprogress = 1;
	}
}

plumbproc(f: string, plumbed: chan of int)
{
	if (plumbmsg == nil || (ref Msg("browser", nil, nil, "text", nil, array of byte f)).send() == -1) {
		sys->fprint(stderr, "ftree: cannot plumb %s\n", f);
		plumbed <-= 0;
	} else
		plumbed <-= 1;
}

loadmods()
{
	sys = load Sys Sys->PATH;
	stderr = sys->fildes(2);
	draw = load Draw Draw->PATH;
	tk = load Tk Tk->PATH;
	tkclient = load Tkclient Tkclient->PATH;
	if (tkclient == nil)
		badmodule(Tkclient->PATH);
	tkclient->init();

	readdir = load Readdir Readdir->PATH;
	if (readdir == nil)
		badmodule(Readdir->PATH);

	str = load String String->PATH;
	if (str == nil)
		badmodule(String->PATH);

	items = load Items Items->PATH;
	if (items == nil)
		badmodule(Items->PATH);
	items->init();

	sh = load Sh Sh->PATH;
	if (sh == nil)
		badmodule(Sh->PATH);

	popup = load Popup Popup->PATH;
	if (popup == nil)
		badmodule(Popup->PATH);
	popup->init();

	cptree = load Cptree Cptree->PATH;
	if (cptree == nil)
		badmodule(Cptree->PATH);
	cptree->init();

	arg = load Arg Arg->PATH;
	if (arg == nil)
		badmodule(Arg->PATH);
}

updatens(s: string)
{
	sys->print("updatens(%s)\n", s);
	(target, ev) := eventtarget(s);
	spawn rereadproc(c := chan of (ref Tree, Item, chan of Item));
	operate(target, c);
	cmd(tkwin, "update");
}

nsupdatereaderproc(fd: ref Sys->FD, path: string, nschanged: chan of string)
{
	buf := array[Sys->ATOMICIO] of byte;
	while ((n := sys->read(fd, buf, len buf)) > 0) {
		s := string buf[0:n];
		nschanged <-= path + string buf[0:n-1];
	}
	sys->print("nsupdate gave eof: (%r)\n");
}

sendeventproc(ev: string, c: chan of (ref Tree, Item, chan of Item))
{
	(tree, it, replyc) := <-c;
	if (replyc == nil)
		return;
	pick t := tree {
	N =>
		if (ev == "expand")
			expand(t, it);
		else if (ev == "contract")
			t.sub = nil;
		it = t.e.event(it, ev);
	}
	replyc <-= it;
}

Open, Copy, Paste, Remove: con iota;

menu := array[] of {
Open => "Open",
Copy => "Copy",
Paste => "Paste into",
Remove => "Remove",
};

screenx(cvs: string, x: int): int
{
	return x - int cmd(tkwin, cvs + " canvasx 0");
}

screeny(cvs: string, y: int): int
{
	return y - int cmd(tkwin, cvs + " canvasy 0");
}

menuproc(c: chan of (ref Tree, Item, chan of Item), nsu: chan of string)
{
	(tree, it, replyc) := <-c;
	if (replyc == nil)
		return;

	p := Point(screenx(".c", it.r.min.x), screeny(".c", it.r.min.y));
	m := array[len menu] of string;
	for (i := 0; i < len m; i++)
		m[i] = menu[i] + " " + tree.fname;
	n := post(tkwin, p, m, 0);
	upd: string;
	if (n >= 0) {
		case n {
		Copy =>
			cpfile = it.name;
		Paste =>
			if (cpfile == nil)
				notice("no file in snarf buffer");
			else {
				cp(cpfile, it.name);
				upd = it.name;
			}
		Remove =>
			if ((e := rm(it.name)) != nil)
				notice(e);
			upd = parent(it.name);
		Open =>
			plumbit(it.name);
		}
	}

#	id := cmd(tkwin, ".c create rectangle " + r2s(it.r) + " -fill yellow");
	replyc <-= it;
	nsu <-= upd;
}

post(win: ref Tk->Toplevel, p: Point, a: array of string, n: int): int
{
	rc := popup->post(win, p, a, n);
	for(;;)alt{
	r := <-rc =>
		return r;
	key := <-win.ctxt.kbd =>
		tk->keyboard(win, key);
	m := <-win.ctxt.ptr =>
		tk->pointer(win, *m);
	s := <-win.ctxt.ctl or
	s = <-win.wreq =>
		tkclient->wmctl(win, s);
	}
}

highlight(f: string, colour: string, time: int)
{
	spawn highlightproc(c := chan of (ref Tree, Item, chan of Item), colour, time);
	operate(f, c);
	tk->cmd(tkwin, "update");
}

unhighlight()
{
	cmd(tkwin, ".c delete highlight");
	tk->cmd(tkwin, "update");
}

hpid := -1;
highlightproc(c: chan of (ref Tree, Item, chan of Item), colour: string, time: int)
{
	(tree, it, replyc) := <-c;
	if (replyc == nil)
		return;
	r: Rect;
	pick t  := tree {
	N =>
		r = t.e.titleitem.r.addpt(it.r.min);
	L =>
		r = it.r;
	}
	id := cmd(tkwin, ".c create rectangle " + r2s(r) + " -fill " + colour + " -tags highlight");
	cmd(tkwin, ".c lower " + id);
	kill(hpid);
	sync := chan of int;
	spawn highlightsleepproc(sync, time);
	hpid = <-sync;
	replyc <-= it;
}

highlightsleepproc(sync: chan of int, time: int)
{
	sync <-= sys->pctl(0, nil);
	sys->sleep(time);
	cmd(tkwin, ".c delete highlight");
	cmd(tkwin, "update");
}

operate(towhom: string, c: chan of (ref Tree, Item, chan of Item)): int
{
	towhom = cleanname(towhom);
	(ok, it) := operate1(roottree, rootitem, towhom, towhom, c);
	if (!it.eq(rootitem)) {
		cmd(tkwin, ".c configure -width " + string it.r.dx() + " -height " + string it.r.dy() +
			" -scrollregion {" + r2s(it.r) + "}");
		rootitem = it;
	}
	if (!ok)
		c <-= (nil, it, nil);
	return ok;
}

blankitem: Item;
operate1(tree: ref Tree, it: Item, towhom, below: string,
		c: chan of (ref Tree, Item, chan of Item)): (int, Item)	
{
#	sys->print("operate on %s, towhom: %s, below: %s\n", it.name, towhom, below);
	n: ref Tree.N;
	replyc := chan of Item;
	if (it.name != towhom) {
		pick t := tree {
		L =>
			return (0, it);
		N =>
			n = t;
		}
		below = dropelem(below);
		if (below == nil)
			return (0, it);
		path := pathcat(it.name, below);
		if (len n.e.children != len n.sub) {
			sys->fprint(stderr, "inconsistent children in %s (%d vs sub %d)\n", it.name, len n.e.children, len n.sub);
			return (0, it);
		}
		for (i := 0; i < len n.e.children; i++) {
			f := n.e.children[i].name;
#			sys->print("checking %s against child %s\n", path, f);
			if (len path >= len f && path[0:len f] == f &&
					(len path == len f || path[len f] == '/')) {
				break;
			}
		}
		if (i == len n.e.children)
			return (0, it);
		oldit := n.e.children[i].addpt(it.r.min);
		(ok, nit) := operate1(n.sub[i], oldit, towhom, below, c);
		if (nit.eq(oldit))
			return (ok, it);
#		sys->print("childchanged({%s, [%s]}, %d, {%s, [%s]})\n",
#				it.name, r2s(it.r), i, nit.name, r2s(nit.r));
		n.e.children[i] = nit.subpt(it.r.min);
		return (ok, n.e.childrenchanged(it));
	}
	c <-= (tree, it, replyc);
	return (1, <-replyc);
}


dropelem(below: string): string
{
	if (below[0] == '/')
		return below[1:];
	for (i := 1; i < len below; i++)
		if (below[i] == '/')
			break;
	if (i == len below)
		return nil;
	return below[i+1:];
}

cleanname(s: string): string
{
	t := "";
	i := 0;
	while (i < len s)
		if ((t[len t] = s[i++]) == '/')
			while (i < len s && s[i] == '/')
				i++;
	if (len t > 1 && t[len t - 1] == '/')
		t = t[0:len t - 1];
	return t;
}

pathcat(s1, s2: string): string
{
	if (s1 == nil || s2 == nil)
		return s1 + s2;
	if (s1[len s1 - 1] != '/' && s2[0] != '/')
		return s1 + "/" + s2;
	return s1 + s2;
}

# read the directory referred to by t.
expand(t: ref Tree.N, it: Item)
{
	(d, n) := readdir->init(root + it.name, Readdir->NAME|Readdir->COMPACT);
	if (d == nil) {
		sys->print("readdir failed: %r\n");
		d = array[0] of ref Sys->Dir;
	}
	sortit(d);
	t.sub = array[len d] of ref Tree;
	t.e.children = array[len d] of Item;
	for (i := 0; i < len d; i++) {
		tagname := pathcat(it.name, d[i].name);
		(t.sub[i], t.e.children[i]) = makenode(d[i].mode & Sys->DMDIR, d[i].name, tagname);
		# make coords relative to parent
		t.e.children[i] = t.e.children[i].subpt(it.r.min);
	}
}

makenode(isdir: int, title, tagname: string): (ref Tree, Item)
{
	tree: ref Tree;
	it: Item;
	if (isdir) {
		e := Expander.new(tkwin, ".c");
		tree = ref Tree.N(title, e, nil);
		it = e.make(items->maketext(tkwin, ".c", tagname, title));
		cmd(tkwin, ".c bind " + e.titleitem.name +
			" <Button-1> {send clickfile menu " + tagname + "}");
	} else {
		tree = ref Tree.L(title);
		it = items->maketext(tkwin, ".c", tagname, title);
		cmd(tkwin, ".c bind " + tagname +
			" <ButtonRelease-2> {send clickfile plumb " + tagname + "}");
		cmd(tkwin, ".c bind " + tagname +
			" <Button-1> {send clickfile menu " + tagname + "}");
	}
	return (tree, it);
}

rereadproc(c: chan of (ref Tree, Item, chan of Item))
{
	(tree, it, replyc) := <-c;
	if (replyc == nil)
		return;
	pick t := tree {
	L =>
		replyc <-= it;
	N =>
		replyc <-= reread(t, it);
	}
}

# re-read tree & update recursively as necessary.
# _it_ is the tree's Item, in absolute coords.
reread(tree: ref Tree.N, it: Item): Item
{
	(d, n) := readdir->init(root + it.name, Readdir->NAME|Readdir->COMPACT);
	sortit(d);
	sys->print("re-reading %s (was %d, now %d)\n", it.name, len tree.sub, len d);

	sub := tree.sub;
	newsub := array[len d] of ref Tree;
	newchildren := array[len d] of Item;
	i := j := 0;
	while (i < len sub || j < len d) {
		cmp: int;
		if (i >= len sub)
			cmp = 1;
		else if (j >= len d)
			cmp = -1;
		else {
			cmp = entrycmp(sub[i].fname, tagof(sub[i]) == tagof(Tree.N),
					d[j].name, d[j].mode & Sys->DMDIR);
		}
		if (cmp == 0) {
			# entry remains the same, but maybe it's changed type.
			if ((tagof(sub[i]) == tagof(Tree.N)) != ((d[j].mode & Sys->DMDIR) != 0)) {
				# delete old item and make new one...
				tagname := tree.e.children[i].name;
				cmd(tkwin, ".c delete " + tagname);
				(newsub[j], newchildren[j]) =
					makenode(d[j].mode & Sys->DMDIR, d[j].name, tagname);
				newchildren[j] = newchildren[j].subpt(it.r.min);
			} else {
				nit := tree.e.children[i];
				pick t := sub[i] {
				N =>
					if (t.e.expanded)
						nit = reread(t, nit.addpt(it.r.min)).subpt(it.r.min);
				}
				(newsub[j], newchildren[j]) = (sub[i], nit);
			}
			i++;
			j++;
		} else if (cmp > 0) {
			# new entry, d[j]
			tagname := pathcat(it.name, d[j].name);
			(newsub[j], newchildren[j]) =
				makenode(d[j].mode & Sys->DMDIR, d[j].name, tagname);
			newchildren[j] = newchildren[j].subpt(it.r.min);
			j++;
		} else {
			# entry has been deleted, sub[i]
			cmd(tkwin, ".c delete " + tree.e.children[i].name);
			i++;
		}
	}
	(tree.sub, tree.e.children) = (newsub, newchildren);
	return tree.e.childrenchanged(it);
}

entrycmp(s1: string, isdir1: int, s2: string, isdir2: int): int
{
	if (!isdir1 == !isdir2) {
		if (s1 > s2)
			return 1;
		else if (s1 < s2)
			return -1;
		else
			return 0;
	} else if (isdir1)
		return -1;
	else
		return 1;
}

sortit(d: array of ref Sys->Dir)
{
	da := array[len d] of ref Sys->Dir;
	fa := array[len d] of ref Sys->Dir;
	nd := nf := 0;
	for (i := 0; i < len d; i++) {
		if (d[i].mode & Sys->DMDIR)
			da[nd++] = d[i];
		else
			fa[nf++] = d[i];
	}
	d[0:] = da[0:nd];
	d[nd:] = fa[0:nf];
}

eventtarget(s: string): (string, string)
{
	for (i := 0; i < len s; i++)
		if (s[i] == ' ')
			return (s[0:i], s[i+1:]);
	return (s, nil);
}

cmd(top: ref Tk->Toplevel, s: string): string
{
	e := tk->cmd(top, s);
	if (e != nil && e[0] == '!')
		sys->fprint(sys->fildes(2), "ftree: tk error %s on '%s'\n", e, s);
	return e;
}

r2s(r: Rect): string
{
	return string r.min.x + " " + string r.min.y + " " +
			string r.max.x + " " + string r.max.y;
}

p2s(p: Point): string
{
	return string p.x + " " + string p.y;
}

fittoscreen(win: ref Tk->Toplevel)
{
	Point: import draw;
	if (win.image == nil || win.image.screen == nil)
		return;
	r := win.image.screen.image.r;
	scrsize := Point((r.max.x - r.min.x), (r.max.y - r.min.y));
	bd := int cmd(win, ". cget -bd");
	winsize := Point(int cmd(win, ". cget -actwidth") + bd * 2, int cmd(win, ". cget -actheight") + bd * 2);
	if (winsize.x > scrsize.x)
		cmd(win, ". configure -width " + string (scrsize.x - bd * 2));
	if (winsize.y > scrsize.y)
		cmd(win, ". configure -height " + string (scrsize.y - bd * 2));
	actr: Rect;
	actr.min = Point(int cmd(win, ". cget -actx"), int cmd(win, ". cget -acty"));
	actr.max = actr.min.add((int cmd(win, ". cget -actwidth") + bd*2,
				int cmd(win, ". cget -actheight") + bd*2));
	(dx, dy) := (actr.dx(), actr.dy());
	if (actr.max.x > r.max.x)
		(actr.min.x, actr.max.x) = (r.min.x - dx, r.max.x - dx);
	if (actr.max.y > r.max.y)
		(actr.min.y, actr.max.y) = (r.min.y - dy, r.max.y - dy);
	if (actr.min.x < r.min.x)
		(actr.min.x, actr.max.x) = (r.min.x, r.min.x + dx);
	if (actr.min.y < r.min.y)
		(actr.min.y, actr.max.y) = (r.min.y, r.min.y + dy);
	cmd(win, ". configure -x " + string actr.min.x + " -y " + string actr.min.y);
}

cp(src, dst: string)
{
	if(disallow){
		notice("permission denied");
		return;
	}
	progressch := chan of string;
	warningch := chan of (string, chan of int);
	finishedch := chan of string;
	spawn cptree->copyproc(root + src, root + dst, progressch, warningch, finishedch);
loop: for (;;) alt {
	m := <-progressch =>
		status(m);
	(m, r) := <-warningch =>
		notice("warning: " + m);
		sys->sleep(1000);
		r <-= 1;
	m := <-finishedch =>
		status(m);
		break loop;
	}
}

parent(f: string): string
{
	f = cleanname(f);
	for (i := len f - 1; i >= 0; i--)
		if (f[i] == '/')
			break;
	if (i > 0)
		f = f[0:i];
	return f;
}

notice(s: string)
{
	status(s);
}

status(s: string)
{
	cmd(tkwin, ".top.l configure -text '" + s);
	cmd(tkwin, "update");
}

rm(name: string): string
{
	if(disallow)
		return "permission denied";
	name = root + name;
	if(sys->remove(name) < 0) {
		e := sys->sprint("%r");
		(ok, d) := sys->stat(name);
		if(ok >= 0 && (d.mode & Sys->DMDIR) != 0)
			return rmdir(name);
		return e;
	}
	return nil;
}

rmdir(name: string): string
{
	(d, n) := readdir->init(name, Readdir->NONE|Readdir->COMPACT);
	for(i := 0; i < n; i++) {
		path := name+"/"+d[i].name;
		e: string;
		if(d[i].mode & Sys->DMDIR)
			e = rmdir(path);
		else if (sys->remove(path) == -1)
			e = sys->sprint("cannot remove %s: %r", path);
		if (e != nil)
			return e;
	}
	if (sys->remove(name) == -1)
		return sys->sprint("cannot remove %s: %r", name);
	return nil;
}

kill(pid: int)
{
	if ((fd := sys->open("/prog/"+string pid+"/ctl", Sys->OWRITE)) != nil)
		sys->write(fd, array of byte "kill", 4);
}
