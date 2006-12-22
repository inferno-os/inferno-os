implement Cards;
include "sys.m";
	sys: Sys;
include "draw.m";
	draw: Draw;
	Point, Rect, Display, Image, Font: import draw;
include "tk.m";
	tk: Tk;
include "tkclient.m";
	tkclient: Tkclient;
include "math.m";
	math: Math;

Cards: module {
	init: fn(ctxt: ref Draw->Context, argv: list of string);
};

# fairly general card clique client.
# inherent restrictions:
#	no dragging of cards visible over the net; it's unclear how
#		to handle the coordinate spaces involved

Object: adt {
	id:				int;
	pick {
	Card =>
		parentid:		int;
		face:			int;			# 1 is face up
		number:		int;
		rear:			int;
	Member =>
		cid:			int;
		name:		string;
	Stack =>
		o:			ref Layobject.Stack;
	Widget =>
		o:			ref Layobject.Widget;
	Menuentry =>
		parentid:		int;
		text:			string;
	Layoutframe =>
		lay:			ref Layout.Frame;
	Layoutobj =>
		lay:			ref Layout.Obj;
	Scoretable =>
		scores:		array of ref Object.Score;
	Score =>
		row:			array of (int, string);
		height:		int;
	Button =>
	Other =>
	}
};

# specify how an object is laid out.
Layout: adt {
	id:			int;
	parentid:		int;
	opts:			string;		# pack options
	orientation:	int;
	pick {
	Frame =>
		lays:		cyclic array of ref Layout;
	Obj =>
		layid:	int;			# reference to layid of laid-out object
	}
};

# an object which can be laid out on the canvas
Layobject: adt {
	id:			int;
	parentid:		int;
	w:			string;
	size:			Point;
	needrepack:	int;
	orientation:	int;
	layid:		int;
	pick {
	Stack =>
		style:		int;
		cards:		array of ref Object.Card;	# fake objects when invisible
		pos:			Point;		# top-left origin of first card in stack
		delta:		Point;		# card offset delta.
		animq:		ref Queue;	# queue of pending animations.
		actions:		int;
		maxcards:	int;
		title:			string;
		visible:		int;
		n:			int;			# for concealed stacks, n cards in stack.
		ownerid:		int;			# owner of selection
		sel:			ref Selection;
		showsize,
		hassize:		int;
	Widget =>
		wtype:		string;
		entries:		array of ref Object.Menuentry;
		cmd:			string;		# only used for entry widgets
		width:		int;
	}
};
	
Animation: adt {
	tag:		string;					# canvas tag common to cards being moved.
	srcpt:	Point;					# where cards are coming from.
	cards:	array of ref Object.Card;		# objects being transferred.
	dstid:	int;
	index:	int;
	waitch:	chan of ref Animation;		# notification comes on this chan when finished.
};

Selection: adt {
	pick {
	XRange =>
		r: Range;
	Indexes =>
		idxl: list of int;
	Empty =>
	}
};

MAXPLAYERS: con 4;

# layout actions
lFRAME, lOBJECT: con iota;

# possible actions on a card on a stack.
aCLICK: con 1<<iota;

# styles of stack display
styDISPLAY, styPILE: con iota;

# orientations
oLEFT, oRIGHT, oUP, oDOWN: con iota;

Range: adt {
	start, end: int;
};

T: type ref Animation;
Queue: adt {
	h, t: list of T; 
	put: fn(q: self ref Queue, s: T);
	get: fn(q: self ref Queue): T;
	isempty: fn(q: self ref Queue): int;
	peek: fn(q: self ref Queue): T;
};

configcmds := array[] of {
"frame .buts",
"frame .cf",
"canvas .c -width 400 -height 450 -bg green",
"label .status -text 0",
"checkbutton .buts.scores -text {Show scores} -command {send cmd scores}",
"button .buts.sizetofit -text {Fit} -command {send cmd sizetofit}",
"checkbutton .buts.debug -text {Debug} -variable debug -command {send cmd debug}",
"pack .buts.sizetofit .buts.debug .status -in .buts -side left",
"pack .buts -side top -fill x",
"pack  .c -in .cf -side top -fill both -expand 1",
"pack .cf -side top -fill both -expand 1",
"bind .c <Button-1> {send cmd b1 %X %Y}",
"bind .c <ButtonRelease-1} {send cmd b1r %X %Y}",
"bind .c <Button-2> {send cmd b2 %X %Y}",
"bind .c <ButtonRelease-2> {send cmd b2r %X %Y}",
"bind .c <ButtonPress-3> {send cmd b3 %X %Y}",
"bind .c <ButtonRelease-3> {send cmd b3r %X %Y}",
"bind . <Configure> {send cmd config}",
"pack propagate .buts 0",
".status configure -text {}",
"pack propagate . 0",
};

objects: 		array of ref Object;
layobjects := array[20] of list of ref Layobject;
members := array[8] of list of ref Object.Member;
win: 			ref Tk->Toplevel;
drawctxt:		ref Draw->Context;
me:			ref Object.Member;
layout:		ref Layout;
scoretable:	ref Object.Scoretable;
showingscores := 0;
debugging := 0;

stderr:		ref Sys->FD;
animfinishedch: chan of (ref Animation, chan of chan of ref Animation);
yieldch:		chan of int;
cardlockch: 	chan of int;
notifych:		chan of string;
tickregisterch, tickunregisterch: chan of chan of int;
starttime :=	0;
cvsfont: 		ref Font;

packwin:		ref Tk->Toplevel;	# invisible; used to steal tk's packing algorithms...
packobjs:		list of ref Layobject;
repackobjs:	list of ref Layobject;
needresize := 0;
needrepack := 0;

animid := 0;
fakeid := -2;		# ids allocated to "fake" cards in private hands; descending
nimages := 0;
Hiddenpos := Point(5000, 5000);

cliquefd: ref Sys->FD;

init(ctxt: ref Draw->Context, nil: list of string)
{
	sys = load Sys Sys->PATH;
	stderr = sys->fildes(2);
	draw = load Draw Draw->PATH;
	tk = load Tk Tk->PATH;
	math = load Math Math->PATH;
	tkclient = load Tkclient Tkclient->PATH;
	if (tkclient == nil) {
		sys->fprint(stderr, "cards: cannot load %s: %r\n", Tkclient->PATH);
		raise "fail:bad module";
	}
	tkclient->init();
	drawctxt = ctxt;
	client1();
}

# maximum number of rears (overridden by actual rear images)
rearcolours := array[] of {
	int 16r0000ccff,
	int 16rff0000ff,
	int 16rffff00ff,
	int 16r008000ff,
	int 16rffffffff,
	int 16rffaa00ff,
	int 16r00ffffff,
	int 16r808080ff,
	int 16r00ff00ff,
	int 16r800000ff,
	int 16r800080ff,
};
Rearborder := 3;
Border := 6;
Selectborder := 3;
cardsize: Point;
carddelta := Point(12, 15);		# offset in order to see card number/suit
Selectcolour := "red";
Textfont := "/fonts/pelm/unicode.8.font";

client1()
{
	cliquefd = sys->fildes(0);
	if (readconfig() == -1)
		raise "fail:error";

	winctl: chan of string;
	(win, winctl) = tkclient->toplevel(drawctxt, "-font " + Textfont,
		"Cards", Tkclient->Appl);
	cmd(win, ". unmap");
	bcmd := chan of string;
	tk->namechan(win, bcmd, "cmd");
	srvcmd := chan of string;
	tk->namechan(win, srvcmd, "srv");

	if (readcardimages() == -1)
		raise "fail:error";
	for (i := 0; i < len configcmds; i++)
		cmd(win, configcmds[i]);
	tkclient->onscreen(win, nil);
	tkclient->startinput(win, "kbd"::"ptr"::nil);

	fontname := cmd(win, ".c cget -font");
	cvsfont = Font.open(drawctxt.display, fontname);
	if (cvsfont == nil) {
		sys->fprint(stderr, "cards: cannot open font %s: %r\n", fontname);
		raise "fail:error";
	}
	fontname = nil;

	cardlockch = chan of int;
	spawn lockproc();

	yieldch = chan of int;
	spawn yieldproc();

	notifych = chan of string;
	spawn notifierproc();

	updatech := chan of array of byte;
	spawn readproc(cliquefd, updatech);

	spawn updateproc(updatech);
	b1down := 0;

	tickregisterch = chan of chan of int;
	tickunregisterch = chan of chan of int;
	spawn timeproc();
	spawn eventproc(win);

	for (;;) alt {
	c := <-bcmd =>
		(n, toks) := sys->tokenize(c, " ");
		case hd toks {
		"b3" =>
			curp := Point(int cmd(win, ".c canvasx " + hd tl toks),
				int cmd(win, ".c canvasy " + hd tl tl toks));
			b3raise(bcmd, curp);
		"b2" =>
			curp := Point(int cmd(win, ".c canvasx " + hd tl toks),
				int cmd(win, ".c canvasy " + hd tl tl toks));
			dopan(bcmd, "b2", curp);
		"b1" =>
			if (!b1down) {
				# b1 x y
				# x and y in screen coords
				curp := Point(int cmd(win, ".c canvasx " + hd tl toks),
					int cmd(win, ".c canvasy " + hd tl tl toks));
				b1down = b1action(bcmd, curp);
			}
		"b1r" =>
			b1down = 0;
		"entry" =>
			id := int hd tl toks;
			lock();
			cc := "";
			pick o := objects[id] {
			Widget =>
				cc = o.o.cmd;
			* =>
				sys->print("entry message from unknown obj: id %d\n", id);
			}
			unlock();
			if (cc != nil) {
				w := ".buts." + string id + ".b";
				s := cmd(win, w + " get");
				cardscmd(cc + " " + s);
				cmd(win, w + " selection range 0 end");
				cmd(win, "update");
			}
		"config" =>
			lock();
			needresize = 1;
			updatearena();
			unlock();
			cmd(win, "update");
		"scores" =>
			if (scoretable == nil)
				break;
			if (!showingscores) {
				cmd(win, ".c move score " + string -Hiddenpos.x + " " + string -Hiddenpos.y);
				cmd(win, ".c raise score");
			} else
				cmd(win, ".c move score " + p2s(Hiddenpos));
			cmd(win, "update");
			showingscores = !showingscores;
		"sizetofit" =>
			lock();
			sizetofit();
			unlock();
			cmd(win, "update");
		"debug" =>
			debugging = int cmd(win, "variable debug");
		}
	c := <-srvcmd =>		# from button or menu entry
		cardscmd(c);
	s := <-win.ctxt.ctl or
	s = <-win.wreq or
	s = <-winctl =>
		if (s == "exit")
			sys->write(cliquefd, array[0] of byte, 0);
		tkclient->wmctl(win, s);
	}
}

eventproc(win: ref Tk->Toplevel)
{
	for(;;)alt{
	s := <-win.ctxt.kbd =>
		tk->keyboard(win, s);
	s := <-win.ctxt.ptr =>
		tk->pointer(win, *s);
	}
}

readproc(fd: ref Sys->FD, updatech: chan of array of byte)
{
	buf := rest := array[Sys->ATOMICIO * 2] of byte;
	while ((n := sys->read(fd, rest, Sys->ATOMICIO)) > 0) {
		updatech <-= rest[0:n];
		rest = rest[n:];
		if (len rest < Sys->ATOMICIO)
			buf = rest = array[Sys->ATOMICIO * 2] of byte;
	}
	updatech <-= nil;
}


b1action(bcmd: chan of string, p: Point): int
{
	(hitsomething, id) := hitcard(p);
	if (!hitsomething) {
		dopan(bcmd, "b1", p);
		return 0;
	}
	if (id < 0) {		# either error, or someone else's private card
		sys->print("no card hit (%d)\n", id);
		return 1;
	}
	lock();
	if (objects[id] == nil) {
		notify("it's gone");
		unlock();
		return 1;
	}
	stack: ref Layobject.Stack;
	index := -1;
	pick o := objects[id] {
	Card =>
		card := o;
		parentid := card.parentid;
		stack = stackobj(parentid);
		for (index = 0; index < len stack.cards; index++)
			if (stack.cards[index] == card)
				break;
		if (index == len stack.cards)
			index = -1;
	Stack =>
		stack = o.o;
	* =>
		unlock();
		return 1;
	}
	actions := stack.actions;
	stackid := stack.id;
	unlock();
	# XXX potential problems when object ids get reused.
	# the object id that we saw before the unlock()
	# might now refer to a different object, so the user
	# might be performing a different action to the one intended.
	# this should be changed throughout... hmm.
	if (actions == 0) {
		notify("no way josé");
		sys->print("no way: stack %d, actions %d\n", stackid, actions);
		return 1;
	}
	cardscmd("click " + string stackid + " " + string index);
	return 1;
}

dopan(bcmd: chan of string, b: string, p: Point)
{
	r := b + "r";
	for (;;) {
		(n, toks) := sys->tokenize(<-bcmd, " ");
		if (hd toks == b) {
			pan(p, (int hd tl toks, int hd tl tl toks));
			p = Point(int cmd(win, ".c canvasx " + hd tl toks),
				int cmd(win, ".c canvasy " + hd tl tl toks));
			cmd(win, "update");
		} else if (hd toks == r)
			return;
	}
}

b3raise(bcmd: chan of string, p: Point)
{
	currcard := -1;
	above := "";
loop:	for (;;) {
		(nil, id) := hitcard(p);
		if (id != currcard) {
			if (currcard != -1 && above != nil)
				cmd(win, ".c lower i" + string currcard + " " + above);
			if (id == -1 || tagof(objects[id]) != tagof(Object.Card)) {
				above = nil;
				currcard = -1;
			} else {
				above = cmd(win, ".c find above i" + string id);
				cmd(win, ".c raise i" + string id);
				cmd(win, "update");
				currcard = id;
			}
		}
		(nil, toks) := sys->tokenize(<-bcmd, " ");
		case hd toks {
		"b3" =>
			p = Point(int cmd(win, ".c canvasx " + hd tl toks),
				int cmd(win, ".c canvasy " + hd tl tl toks));
		"b3r" =>
			break loop;
		}
	}
	if (currcard != -1 && above != nil) {
		cmd(win, ".c lower i" + string currcard + " " + above);
		cmd(win, "update");
	}
}

hitcard(p: Point): (int, int)
{
	(nil, hitids) := sys->tokenize(cmd(win, ".c find overlapping " + r2s((p, p))), " ");
	if (hitids == nil)
		return (0, -1);
	ids: list of string;
	for (; hitids != nil; hitids = tl hitids)
		ids = hd hitids :: ids;
	for (; ids != nil; ids = tl ids) {
		(nil, tags) := sys->tokenize(cmd(win, ".c gettags " + hd ids), " ");
		for (; tags != nil; tags = tl tags) {
			tag := hd tags;
			if (tag[0] == 'i' || tag[0] == 'r' || tag[0] == 'n' || tag[0] == 'N')
				return (1, int (hd tags)[1:]);
			if (tag[0] == 's')		# ignore selection
				break;
		}
		if (tags == nil)
			break;
	}
	return (1, -1);
}

cardscmd(s: string): int
{
	if (debugging)
		sys->print("cmd: %s\n", s);
	if (sys->fprint(cliquefd, "%s", s) == -1) {
		err := sys->sprint("%r");
		notify(err);
		sys->print("cmd error on '%s': %s\n", s, err);
		return 0;
	}
	return 1;
}

updateproc(updatech: chan of array of byte)
{
	wfd := sys->open("/prog/" + string sys->pctl(0, nil) + "/wait", Sys->OREAD);
	spawn updateproc1(updatech);
	buf := array[Sys->ATOMICIO] of byte;
	n := sys->read(wfd, buf, len buf);
	sys->print("updateproc process exited: %s\n", string buf[0:n]);
}

updateproc1(updatech: chan of array of byte)
{
	animfinishedch = chan of (ref Animation, chan of chan of ref Animation);
	first := 1;
	for (;;) {
		alt {
		v := <-animfinishedch =>
			lock();
			animterminated(v);
			updatearena();
			cmd(win, "update");
			unlock();
		u := <-updatech =>
			if (u == nil) {
				# XXX notify user that clique has been hung up somehow
				exit;
			}
			moretocome := 0;
			if (len u > 2 && u[len u-1] == byte '*' && u[len u-2] == byte '\n') {
				u = u[0:len u - 2];
				moretocome = 1;
			}
			(nil, lines) := sys->tokenize(string u, "\n");
			lock();
			starttime = sys->millisec();
			for (; lines != nil; lines = tl lines)
				applyupdate(hd lines);
			updatearena();
			if (!moretocome) {
				if (first) {
					sizetofit();
					first = 0;
				}
				cmd(win, "update");
			}
			unlock();
		}
	}
}

updatearena()
{
	if (needrepack)
		repackall();
	if (needresize)
		resizeall();
	for (pstk := repackobjs; pstk != nil; pstk = tl pstk)
		repackobj(hd pstk);
	repackobjs = nil;
}

applyupdate(s: string)
{
	if (debugging) {
		sys->print("update: %s\n", s);
#		showtk = 1;
	}
	(nt, toks) := sys->tokenize(s, " ");
	case hd toks {
	"create" =>
		# create id parentid vis type
		id := int hd tl toks;
		if (id >= len objects)
			objects = (array[len objects + 10] of ref Object)[0:] = objects;
		if (objects[id] != nil)
			panic(sys->sprint("object %d already exists!", id));
		parentid := int hd tl tl toks;
		vis := int hd tl tl tl toks;
		objtype := tl tl tl tl toks;
		case hd objtype {
		"stack" =>
			objects[id] = makestack(id, parentid, vis);
			needrepack = 1;
		"card" =>
			stk := stackobj(parentid);
			completeanim(stk);
			if (!stk.visible) {
				# if creating in a private stack, we assume
				# that the cards were there already, and
				# just make them real again.

				# first find a fake card.
				for (i := 0; i < len stk.cards; i++)
					if (stk.cards[i].id < 0)
						break;
				c: ref Object.Card;
				if (i == len stk.cards) {
					# no fake cards - we'll create one instead.
					# this can happen if we've entered halfway through
					# a clique, so don't know how many cards people
					# are holding.
					c = makecard(id, stk);
					insertcards(stk, array[] of {c}, len stk.cards);
				} else {
					c = stk.cards[i];
					changecardid(c, id);
				}
				objects[id] = c;
			} else {
				objects[id] = c := makecard(id, stk);
				insertcards(stk, array[] of {c}, len stk.cards);
			}
		"widget" =>
			objects[id] = makewidget(id, parentid, hd tl objtype);
		"menuentry" =>
			objects[id] = makemenuentry(id, parentid, tl objtype);
		"member" =>
			objects[id] = ref Object.Member(id, -1, "");
		"layframe" =>
			lay := ref Layout.Frame(id, parentid, "", -1, nil);
			objects[id] = ref Object.Layoutframe(id, lay);
			addlayout(lay);
		"layobj" =>
			lay := ref Layout.Obj(id, parentid, "", -1, -1);
			objects[id] = ref Object.Layoutobj(id, lay);
			addlayout(lay);
		"scoretable" =>
			if (scoretable != nil)
				panic("cannot make two scoretables");
			scoretable = objects[id] = ref Object.Scoretable(id, nil);
		"score" =>
			pick l := objects[parentid] {
			Scoretable =>
				nl := array[len l.scores + 1] of ref Object.Score;
				nl[0:] = l.scores;
				nl[len nl - 1] = objects[id] = ref Object.Score(id, nil, 0);
				l.scores = nl;
				cmd(win, "pack .buts.scores -side left");
			* =>
				panic("score created outside scoretable object");
			}
		"button" =>
			objects[id] = ref Object.Button(id);
			cmd(win, "button .buts." + string id);
			cmd(win, "pack .buts." + string id + " -side left");
		* =>
			if (parentid != -1)
				sys->print("cards: unknown objtype: '%s'\n", hd objtype);
			objects[id] = ref Object.Other(id);
		}

	"tx" =>
		# tx src dst start end dstindex
		src, dst: ref Layobject.Stack;
		index: int;
		r: Range;
		(src, toks) = (stackobj(int hd tl toks), tl tl toks);
		(dst, toks) = (stackobj(int hd toks), tl toks);
		(r.start, toks) =  (int hd toks, tl toks);
		(r.end, toks) =  (int hd toks, tl toks);
		(index, toks) = (int hd toks, tl toks);
		transfer(src, r, dst, index);

	"del" =>
		# del parent start end objs...
		oo := objects[int hd tl toks];	# parent
		r := Range(int hd tl tl toks, int hd tl tl tl toks);
		pick o := oo {
		Stack =>			# deleting cards from a stack.
			stk := o.o;
			completeanim(stk);
			if (!stk.visible) {
				# if deleting from a private area, we assume the cards aren't
				# actually being deleted at all, but merely becoming
				# invisible, so turn them into fakes.
				for (i := r.start; i < r.end; i++) {
					card := stk.cards[i];
					objects[card.id] = nil;
					changecardid(card, --fakeid);
					cardsetattr(card, "face", "0" :: nil);
				}
			} else {
				cards := extractcards(stk, r);
				for (i := 0; i < len cards; i++)
					destroy(cards[i]);
			}
		Layoutframe =>		# deleting the layout specification.
			lay := o.lay;
			if (r.start != 0 || r.end != len lay.lays)
				panic("cannot partially delete layouts");
			for (i := r.start; i < r.end; i++)
				destroy(objects[lay.lays[i].id]);
			lay.lays = nil;
			needrepack = 1;
		Widget =>
			# must be a menu widget
			cmd(win, ".buts." + string o.id + ".m delete " +
				string r.start + " " + string r.end);
		* =>
			for (objs := tl tl tl tl toks; objs != nil; objs = tl objs)
				destroy(objects[int hd objs]);
		}

	"set" =>
		# set obj attr val
		id := int hd tl toks;
		(attr, val) := (hd tl tl toks, tl tl tl toks);
		pick o := objects[id] {
		Card =>
			cardsetattr(o, attr, val);
		Widget =>
			widgetsetattr(o.o, attr, val);
		Stack =>
			stacksetattr(o.o, attr, val);
		Member =>
			membersetattr(o, attr, val);
		Layoutframe =>
			laysetattr(o.lay, attr, val);
		Layoutobj =>
			laysetattr(o.lay, attr, val);
		Score =>
			scoresetattr(o, attr, val);
		Button =>
			buttonsetattr(o, attr, val);
		Menuentry =>
			menuentrysetattr(o, attr, val);
		* =>
			sys->fprint(stderr, "unknown attr set on object(tag %d), %s\n", tagof(objects[id]), s);
		}

	"say" or
	"remark" =>
		notify(join(tl toks));
	* =>
		sys->fprint(stderr, "cards: unknown update message '%s'\n", s);
	}
}

addlayout(lay: ref Layout)
{
	pick lo := objects[lay.parentid] {
	Layoutframe =>
		l := lo.lay;
		nl := array[len l.lays + 1] of ref Layout;
		nl[0:] = l.lays;
		nl[len nl - 1] = lay;
		l.lays = nl;
	* =>
		if (layout == nil)
			layout = lay;
		else
			panic("cannot make two layout objects");
	}
}

makestack(id, parentid: int, vis: int): ref Object.Stack
{
	o := ref Object.Stack(
		id,
		ref Layobject.Stack(
			id,
			parentid,
			"",			# pack widget name
			(0, 0),		# size
			0,			# needrepack
			-1,			# orientation
			-1,			# layid
			-1,			# style
			nil,			# cards
			Hiddenpos,	# pos
			(0, 0),		# delta
			ref Queue,
			0,			# actions
			0,			# maxcards
			"",			# title
			vis,			# visible
			0,			# n
			-1,			# ownerid
			ref Selection.Empty,		# sel
			1,			# showsize
			0			# hassize
		)
	);
	cmd(win, ".c create rectangle -10 -10 -10 -10 -width 3 -tags r" + string id);
	return o;
}

makewidget(id, parentid: int, wtype: string): ref Object.Widget
{
	wctype := wtype;
	if (wtype == "menu")
		wctype = "menubutton";
	# XXX the widget is put in a frame 'cos of bugs in the canvas
	# to do with size propagation.
	w := cmd(win, "frame .buts." + string id + " -bg transparent");
	cmd(win, wctype + " " + w + ".b");
	cmd(win, "pack " + w + ".b -fill both -expand 1");
	case wtype {
	"menu" =>
		cmd(win, "menu " + w + ".m");
		cmd(win, w + ".b configure -menu " + w + ".m" +
			" -relief raised");
	"entry" =>
		cmd(win, "bind " + w + ".b <Key-\n> {send cmd entry " + string id + "}");
	}
	cmd(win, ".c create window -1000 -1000 -tags r" + string id +
		" -window " + w + " -anchor nw");
	o := ref Object.Widget(
		id,
		ref Layobject.Widget(
			id,
			parentid,
			nil,		# w
			(0, 0),	# size
			0,		# needrepack
			-1,		# orientation
			-1,		# style

			wtype,
			nil,		# entries
			"",		# cmd
			0		# width
		)
	);
	return o;
}

menutitleid := 0;		# hack to identify menu entries
makemenuentry(id, parentid: int, nil: list of string): ref Object.Menuentry
{
	m := ".buts." + string parentid + ".m";
	t := "@" + string menutitleid++;
	cmd(win, m + " add command -text " + t);
	return ref Object.Menuentry(id, parentid, t);
}

makecard(id: int, stack: ref Layobject.Stack): ref Object.Card
{
	cmd(win, ".c create image 5000 5000 -anchor nw -tags i" + string id);
	return ref Object.Card(id, stack.id, -1, -1, 0);
}

buttonsetattr(b: ref Object.Button, attr: string, val: list of string)
{
	w := ".buts." + string b.id;
	case attr {
	"text" =>
		cmd(win, w + " configure -text '" + join(val));
	"command" =>
		cmd(win, w + " configure -command 'send srv " + join(val));
	* =>
		sys->print("unknown attribute on button: %s\n", attr);
	}
}

widgetsetattr(b: ref Layobject.Widget, attr: string, val: list of string)
{
	w := ".buts." + string b.id + ".b";
	case attr {
	"text" =>
		t := join(val);
		if (b.wtype == "entry") {
			cmd(win, w + " delete 0 end");
			cmd(win, w + " insert 0 '" + t);
			cmd(win, w + " select 0 end");		# XXX ??
		} else {
			cmd(win, w + " configure -text '" + t);
			needresize = 1;
		}
	"command" =>
		case b.wtype {
		"button" =>
			cmd(win, w + " configure -command 'send srv " + join(val));
		"entry" =>
			b.cmd = join(val);
		}
	"width" =>		# width in characters
		b.width = int hd val;
		sys->print("configuring %s for width %s\n", w, hd val);
		cmd(win, w + " configure -width " + hd val + "w");
		needresize = 1;
	"layid" =>
		setlayid(b, int hd val);
	* =>
		sys->print("unknown attribute on button: %s\n", attr);
	}
}

findmenuentry(m: string, title: string): int
{
	end := int cmd(win, m + " index end");
	for (i := 0; i <= end; i++) {
		t := cmd(win, m + " entrycget " + string i + " -text");
		if (t == title)
			return i;
	}
	return -1;
}

menuentrysetattr(e: ref Object.Menuentry, attr: string, val: list of string)
{
	m := ".buts." + string e.parentid + ".m";
	idx := findmenuentry(m, e.text);
	if (idx == -1) {
		sys->print("couldn't find menu entry '%s'\n", e.text);
		return;
	}
	case attr {
	"text" =>
		t := join(val);
		cmd(win, m + " entryconfigure " + string idx +" -text '" + t);
		e.text = t;
	"command" =>
		cmd(win, m + " entryconfigure " + string idx +
				" -command 'send srv " + join(val));
	* =>
		sys->print("unknown attribute on menu entry: %s\n", attr);
	}
}

stacksetattr(stack: ref Layobject.Stack, attr: string, val: list of string)
{
	id := string stack.id;
	case attr {
	"maxcards" =>
		stack.maxcards = int hd val;
		needresize = 1;
	"layid" =>
		setlayid(stack, int hd val);
	"showsize" =>
		stack.showsize = int hd val;
		showsize(stack);
	"title" =>
		title := join(val);
		if (title != stack.title) {
			if (stack.title == nil) {
				cmd(win, ".c create text 5000 6000 -anchor n -tags t" + string id +
					" -fill #ffffaa");
				needresize = 1;
			} else if (title == nil) {
				cmd(win, ".c delete t" + string id);
				needresize = 1;
			}
			if (title != nil)
				cmd(win, ".c itemconfigure t" + string id + " -text '" + title);
			stack.title = title;
		}
	"n" =>
		# there are "n" cards in this stack, honest guv.
		n := int hd val;
		if (!stack.visible) {
			if (n > len stack.cards) {
				a := array[n - len stack.cards] of ref Object.Card;
				for (i := 0; i < len a; i++) {
					a[i] = makecard(--fakeid, stack);
					cardsetattr(a[i], "face", "0" :: nil);
				}
				insertcards(stack, a, len stack.cards);
			} else if (n < len stack.cards) {
				for (i := len stack.cards - 1; i >= n; i--)
					if (stack.cards[i].id >= 0)
						break;
				cards := extractcards(stack, (i + 1, len stack.cards));
				for (i = 0; i < len cards; i++)
					destroy(cards[i]);
			}
		}
		stack.n = n;
	"style" =>
		case hd val {
		"pile" =>
			stack.style = styPILE;
		"display" =>
			stack.style = styDISPLAY;
		* =>
			sys->print("unknown stack style '%s'\n", hd val);
		}
		needresize = 1;
	"owner" =>
		if (val != nil)
			stack.ownerid = int hd val;
		else
			stack.ownerid = -1;
		changesel(stack, stack.sel);
	"sel" =>
		sel: ref Selection;
		if (val == nil)
			sel = ref Selection.Empty;
		else if (tl val != nil && hd tl val == "-")
			sel = ref Selection.XRange((int hd val, int hd tl tl val));
		else {
			idxl: list of int;
			for (; val != nil; val = tl val)
				idxl = int hd val :: idxl;
			sel = ref Selection.Indexes(idxl);
		}
		changesel(stack, sel);
	* =>
		if (len attr >= len "actions" && attr[0:len "actions"] == "actions") {
			oldactions := stack.actions;
			act := 0;
			for (; val != nil; val = tl val) {
				case hd val {
				"click" =>
					act |= aCLICK;
				* =>
					sys->print("unknown action '%s'\n", hd val);
				}
			}
			stack.actions = act;
		} else
			sys->fprint(stderr, "bad stack attr '%s'\n", attr);
	}
}

showsize(stack: ref Layobject.Stack)
{
	id := string stack.id;
	needsize := stack.showsize && len stack.cards > 0 && stack.style == styPILE;
	if (needsize != stack.hassize) {
		if (stack.hassize)
			cmd(win, ".c delete n" + id + " N" + id);
		else {
			cmd(win, ".c create rectangle -5000 0 0 0  -fill #ffffaa -tags n" + id);
			cmd(win, ".c create text -5000 0 -anchor sw -fill red -tags N" + id);
		}
		stack.hassize = needsize;
	}
	if (needsize) {
		cmd(win, ".c itemconfigure N" + id + " -text " + string len stack.cards);
		sr := cardrect(stack, (len stack.cards - 1, len stack.cards));
		cmd(win, ".c coords N" + id + " " + p2s((sr.min.x, sr.max.y)));
		bbox := cmd(win, ".c bbox N" + id);
		cmd(win, ".c coords n" + id + " " + bbox);
		cmd(win, ".c raise n" + id + "; .c raise N" + id);
	}
}		

changesel(stack: ref Layobject.Stack, newsel: ref Selection)
{
	sid := "s" + string stack.id;
	cmd(win, ".c delete " + sid);

	if (me != nil && stack.ownerid == me.cid) {
		pick sel := newsel {
		Indexes =>
			for (l := sel.idxl; l != nil; l = tl l) {
				s := cmd(win, ".c create rectangle " +
					r2s(cardrect(stack, (hd l, hd l + 1)).inset(-1)) +
					" -width " + string Selectborder +
					" -outline " + Selectcolour +
					" -tags {" + sid + " " + sid + "." + string hd l + "}");
				cmd(win, ".c lower " + s + " i" + string stack.cards[hd l].id);
			}
		XRange =>
			cmd(win, ".c create rectangle " +
					r2s(cardrect(stack, sel.r).inset(-1)) +
					" -outline " + Selectcolour +
					" -width " + string Selectborder +
					" -tags " + sid);
		}
	}
	stack.sel = newsel;
}

cardsetattr(card: ref Object.Card, attr: string, val: list of string)
{
	id := string card.id;
	case attr {
	"face" =>
		card.face = int hd val;
		if (card.face) {
			if (card.number != -1)
				cmd(win, ".c itemconfigure i" + id + " -image c" + string card.number );
		} else
			cmd(win, ".c itemconfigure i" + id + " -image rear" + string card.rear);
	"number" =>
		card.number = int hd val;
		if (card.face)
			cmd(win, ".c itemconfigure i" + id + " -image c" + string card.number );
	"rear" =>
		card.rear = int hd val;
		if (card.face == 0)
			cmd(win, ".c itemconfigure i" + id + " -image rear" + string card.rear);
	* =>
		sys->print("unknown attribute on card: %s\n", attr);
	}
}

setlayid(layobj: ref Layobject, layid: int)
{
	if (layobj.layid != -1)
		panic("obj already has a layout id (" + string layobj.layid + ")");
	layobj.layid = layid;
	x := layobj.layid % len layobjects;
	layobjects[x] = layobj :: layobjects[x];
	needrepack = 1;
}

membersetattr(p: ref Object.Member, attr: string, val: list of string)
{
	case attr {
	"you" =>
		me = p;
		p.cid = int hd val;
		for (i := 0; i < len objects; i++) {
			if (objects[i] != nil) {
				pick o := objects[i] {
				Stack =>
					if (o.o.ownerid == p.cid)
						objneedsrepack(o.o);
				}
			}
		}
	"name" =>
		p.name = hd val;
	"id" =>
		p.cid = int hd val;
	"status" =>
		if (p == me)
			cmd(win, ".status configure -text '" + join(val));
	"cliquetitle" =>
		if (p == me)
			tkclient->settitle(win, join(val));
	* =>
		sys->print("unknown attribute on member: %s\n", attr);
	}
}

laysetattr(lay: ref Layout, attr: string, val: list of string)
{
	case attr {
	"opts" =>
		# orientation opts
		case hd val {
		"up" =>
			lay.orientation = oUP;
		"down" =>
			lay.orientation = oDOWN;
		"left" =>
			lay.orientation = oLEFT;
		"right" =>
			lay.orientation = oRIGHT;
		* =>
			sys->print("unknown orientation '%s'\n", hd val);
		}
		lay.opts = join(tl val);
	"layid" =>
#		sys->print("layout obj %d => layid %s\n", lay.id, hd val);
		pick l := lay {
		Obj =>
			l.layid = int hd val;
			needrepack = 1;
		* =>
			sys->print("cannot set layid on Layout.Frame!\n");
		}
	* =>
		sys->print("unknown attribute on lay: %s\n", attr);
	}
	needrepack = 1;
}

scoresetattr(score: ref Object.Score, attr: string, val: list of string)
{
	if (attr != "score")
		return;
	cmd(win, ".c delete score");

	Padx: con 10;		# padding to the right of each item
	Pady: con 6;		# padding below each item.

	n := len val;
	row := score.row = array[n] of (int, string);
	height := 0;

	# calculate values for this row
	for ((col, vl) := (0, val); vl != nil; (col, vl) = (col + 1, tl vl)) {
		v := hd vl;
		size := textsize(v);
		size.y += Pady;
		if (size.y > height)
			height = size.y;
		row[col] = (size.x + Padx, v);
	}
	score.height = height;
	totheight := 0;
	scores := scoretable.scores;

	# calculate number of columns
	ncols := 0;
	for (i := 0; i < len scores; i++)
		if (len scores[i].row > ncols)
			ncols = len scores[i].row;

	# calculate column widths
	colwidths := array[ncols] of {* => 0};
	for (i = 0; i < len scores; i++) {
		r := scores[i].row;
		for (j := 0; j < len r; j++) {
			(w, nil) := r[j];
			if (w > colwidths[j])
				colwidths[j] = w;
		}
		totheight += scores[i].height;
	}
	# create all table items
	p := Hiddenpos;
	for (i = 0; i < len scores; i++) {
		p.x = Hiddenpos.x;
		r := scores[i].row;
		for (j := 0; j < len r; j++) {
			(w, text) := r[j];
			cmd(win, ".c create text " + p2s(p) + " -anchor nw -tags {score scoreent}-text '" + text);
			p.x += colwidths[j];
		}
		p.y += scores[i].height;
	}
	r := Rect(Hiddenpos, p);
	r.min.x -= Padx;
	r.max.y -= Pady / 2;

	cmd(win, ".c create rectangle " + r2s(r) + " -fill #ffffaa -tags score");

	# horizontal lines
	y := 0;
	for (i = 0; i < len scores - 1; i++) {
		ly := y + scores[i].height - Pady / 2;
		cmd(win, ".c create line " + r2s(((r.min.x, ly), (r.max.x, ly))) + " -fill gray -tags score");
		y += scores[i].height;
	}

	cmd(win, ".c raise scoreent");
	cmd(win, ".c move score " + p2s(Hiddenpos.sub(r.min)));
}

textsize(s: string): Point
{
	return (cvsfont.width(s), cvsfont.height);
}

changecardid(c: ref Object.Card, newid: int)
{
	(nil, tags) := sys->tokenize(cmd(win, ".c gettags i" + string c.id), " ");
	for (; tags != nil; tags = tl tags) {
		tag := hd tags;
		if (tag[0] >= '0' && tag[0] <= '9')
			break;
	}
	cvsid := hd tags;
	cmd(win, ".c dtag " + cvsid + " i" + string c.id);
	c.id = newid;
	cmd(win, ".c addtag i" + string c.id + " withtag " + cvsid);
}

stackobj(id: int): ref Layobject.Stack
{
	obj := objects[id];
	if (obj == nil)
		panic("nil stack object");
	pick o := obj {
	Stack =>
		return o.o;
	* =>
		panic("expected obj " + string id + " to be a stack");
	}
	return nil;
}

# if there are updates pending on the stack,
# then wait for them all to finish before we can do
# any operations on the stack (e.g. insert, delete, create, etc)
completeanim(stk: ref Layobject.Stack)
{
	while (!stk.animq.isempty())
		animterminated(<-animfinishedch);
}

transfer(src: ref Layobject.Stack, r: Range, dst: ref Layobject.Stack, index: int)
{
	# we don't bother animating movement within a stack; maybe later?
	if (src == dst) {
		transfercards(src, r, dst, index);
		return;
	}
	completeanim(src);

	if (!src.visible) {
		# cards being transferred out of private area should
		# have already been created, but check anyway.
		if (r.start != 0)
			panic("bad transfer out of private");
		for (i := 0; i < r.end; i++)
			if (src.cards[i].id < 0)
				panic("cannot transfer fake card");
	}

	startanimating(newanimation(src, r), dst, index);
}

objneedsrepack(obj: ref Layobject)
{
	if (!obj.needrepack) {
		obj.needrepack = 1;
		repackobjs = obj :: repackobjs;
	}
}

repackobj(obj: ref Layobject)
{
	pick o := obj {
	Stack =>
		cards := o.cards;
		pos := o.pos;
		delta := o.delta;
		for (i := 0; i < len cards; i++) {
			p := pos.add(delta.mul(i));
			id := string cards[i].id;
			cmd(win, ".c coords i" + id + " " + p2s(p));
			cmd(win, ".c raise i" + id);		# XXX could be more efficient.
			cmd(win, ".c lower s" + string o.id + "." + string i + " i" + id);
		}
		changesel(o, o.sel);
		showsize(o);
	}
	obj.needrepack = 0;
}

cardrect(stack: ref Layobject.Stack, r: Range): Rect
{
	if (r.start == r.end)
		return ((-10, -10), (-10, -10));
	cr := Rect((0, 0), cardsize).addpt(stack.pos);
	delta := stack.delta;
	return union(cr.addpt(delta.mul(r.start)), cr.addpt(delta.mul(r.end - 1)));
}

repackall()
{
	sys->print("repackall()\n");
	needrepack = 0;
	if (layout == nil) {
		sys->print("no layout\n");
		return;
	}
	if (packwin == nil) {
		# use an unmapped tk window to do our packing arrangements
		packwin = tk->toplevel(drawctxt.display, "-bd 0");
		packwin.wreq = nil;			# stop window requests piling up.
	}
	cmd(packwin, "destroy " + cmd(packwin, "pack slaves ."));
	packobjs = nil;
	packit(layout, ".0");
	sys->print("%d packobjs\n", len packobjs);
	needresize = 1;
}

# make the frames for the objects to be laid out, in the
# offscreen window.
packit(lay: ref Layout, f: string)
{
	cmd(packwin, "frame " + f);
	cmd(packwin, "pack " + f + " " + lay.opts);
	pick l := lay {
	Frame =>
		for (i := 0; i < len l.lays; i++)
			packit(l.lays[i], f + "." + string i);
	Obj =>
		if ((obj := findlayobject(l.layid)) != nil) {
			obj.w = f;
			obj.orientation = l.orientation;
			packobjs = obj :: packobjs;
		} else
			sys->print("cannot find layobject %d\n", l.layid);
	}
}

sizetofit()
{
	if (packobjs == nil)
		return;
	cmd(packwin, "pack propagate . 1");
	cmd(packwin, ". configure -width 0 -height 0");	# make sure propagation works.
	csz := actsize(packwin, ".");
	cmd(win, "bind . <Configure> {}");
	cmd(win, "pack propagate . 1");
	cmd(win, ". configure -width 0 -height 0");

	cmd(win, ".c configure -width " + string csz.x + " -height " + string csz.y
			+ " -scrollregion {0 0 " + p2s(csz) + "}");
	winr := actrect(win, ".");
	screenr := win.image.screen.image.r;
	if (!winr.inrect(screenr)) {
		if (winr.dx() > screenr.dx())
			(winr.min.x, winr.max.x) = (screenr.min.x, screenr.max.x);
		if (winr.dy() > screenr.dy())
			(winr.min.y, winr.max.y) = (screenr.min.y, screenr.max.y);
		if (winr.max.x > screenr.max.x)
			(winr.min.x, winr.max.x) = (screenr.max.x - winr.dx(), screenr.max.x);
		if (winr.max.y > screenr.max.y)
			(winr.min.y, winr.max.y) = (screenr.max.y - winr.dy(), screenr.max.y);
	}
	cmd(win, "pack propagate . 0");
	cmd(win, ". configure " +
			" -x " + string winr.min.x +
			" -y " + string winr.min.y +
			" -width " + string winr.dx() +
			" -height " + string winr.dy());
	needresize = 1;
	updatearena();
	cmd(win, "bind . <Configure> {send cmd config}");
}

setorigin(r: Rect, p: Point): Rect
{
	sz := Point(r.max.x - r.min.x, r.max.y - r.min.y);
	return (p, p.add(sz));
}

resizeall()
{
	needresize = 0;
	if (packobjs == nil)
		return;
	cmd(packwin, "pack propagate . 1");
	cmd(packwin, ". configure -width 0 -height 0");	# make sure propagation works.
	for (sl := packobjs; sl != nil; sl = tl sl) {
		obj := hd sl;
		sizeobj(obj);
		cmd(packwin, obj.w + " configure -width " + string obj.size.x +
			" -height " + string obj.size.y);
	}
	csz := actsize(packwin, ".");
	sz := actsize(win, ".cf");
	if (sz.x > csz.x || sz.y > csz.y) {
		cmd(packwin, "pack propagate . 0");
		if (sz.x > csz.x) {
			cmd(packwin, ". configure -width " + string sz.x);
			cmd(win, ".c xview moveto 0");
			csz.x = sz.x;
		}
		if (sz.y > csz.y) {
			cmd(packwin, ". configure -height " + string sz.y);
			cmd(win, ".c yview moveto 0");
			csz.y = sz.y;
		}
	}
	cmd(win, ".c configure -width " + string csz.x + " -height " + string csz.y
			+ " -scrollregion {0 0 " + p2s(csz) + "}");
	onscreen();
	for (sl = packobjs; sl != nil; sl = tl sl) {
		obj := hd sl;
		r := actrect(packwin, obj.w);
		positionobj(obj, r);
	}
}

# make sure that there aren't any unnecessary blank
# bits in the scroll area.
onscreen()
{
	(n, toks) := sys->tokenize(cmd(win, ".c xview"), " ");
	cmd(win, ".c xview moveto " + hd toks);
	(n, toks) = sys->tokenize(cmd(win, ".c yview"), " ");
	cmd(win, ".c yview moveto " + hd toks);
}

# work out the size of an object to be laid out.
sizeobj(obj: ref Layobject)
{
	pick o := obj {
	Stack =>
		delta := Point(0, 0);
		case o.style {
		styDISPLAY =>
			case o.orientation {
			oRIGHT =>	delta.x = carddelta.x;
			oLEFT =>		delta.x = -carddelta.x;
			oDOWN =>	delta.y = carddelta.y;
			oUP =>		delta.y = -carddelta.y;
			}
		styPILE =>
			;	# no offset
		}
		o.delta = delta;
		r := Rect((0, 0), size(cardrect(o, (0, max(len o.cards, o.maxcards)))));
		if (o.title != nil) {
			p := Point(r.min.x + r.dx() / 2, r.min.y);
			tr := s2r(cmd(win, ".c bbox t" + string o.id));
			tbox := Rect((p.x - tr.dx() / 2, p.y - tr.dy()), (p.x + tr.dx() / 2, p.y));
			r = union(r, tbox);
		}
		o.size = r.max.sub(r.min).add((Border * 2, Border * 2));
#		sys->print("sized stack %d => %s\n", o.id, p2s(o.size));
	Widget =>
		w := ".buts." + string o.id;
		o.size.x = int cmd(win, w + " cget -width");
		o.size.y = int cmd(win, w + " cget -height");
#		sys->print("sized widget %d (%s) => %s\n", o.id,
#			cmd(win, "winfo class " + w + ".b"), p2s(o.size));
	}
}

# set a laid-out object's position on the canvas, given
# its allocated rectangle, r.
positionobj(obj: ref Layobject, r: Rect)
{
	pick o := obj {
	Stack =>
#		sys->print("positioning stack %d, r %s\n", o.id, r2s(r));
		delta := o.delta;
		sz := o.size.sub((Border * 2, Border * 2));
		r.min.x += (r.dx() - sz.x) / 2;
		r.min.y += (r.dy() - sz.y) / 2;
		r.max = r.min.add(sz);
		if (o.title != nil) {
			cmd(win, ".c coords t" +string o.id + " " +
				string (r.min.x + r.dx() / 2) + " " + string r.min.y);
			tr := s2r(cmd(win, ".c bbox t" + string o.id));
			r.min.y = tr.max.y;
			sz = size(cardrect(o, (0, max(len o.cards, o.maxcards))));
			r.min.x += (r.dx() - sz.x) / 2;
			r.min.y += (r.dy() - sz.y) / 2;
			r.max = r.min.add(sz);
		}
		o.pos = r.min;
		if (delta.x < 0)
			o.pos.x = r.max.x - cardsize.x;
		if (delta.y < 0)
			o.pos.y = r.max.y - cardsize.y;
		cmd(win, ".c coords r" + string o.id + " " + r2s(r.inset(-(Border / 2))));
		objneedsrepack(o);
	Widget =>
#		sys->print("positioning widget %d, r %s\n", o.id, r2s(r));
		cmd(win, ".c coords r" + string o.id + " " + p2s(r.min));
		bd := int cmd(win, ".buts." + string o.id + " cget -bd");
		cmd(win, ".c itemconfigure r" + string o.id +
			" -width " + string (r.dx() - bd * 2) +
			" -height " + string (r.dy() - bd * 2));
	}
}

size(r: Rect): Point
{
	return r.max.sub(r.min);
}

transfercards(src: ref Layobject.Stack, r: Range, dst: ref Layobject.Stack, index: int)
{
	cards := extractcards(src, r);
	n := r.end - r.start;
	# if we've just removed some cards from the destination,
	# then adjust the destination index accordingly.
	if (src == dst && index > r.start) {
		if (index < r.end)
			index = r.start;
		else
			index -= n;
	}
	insertcards(dst, cards, index);
}

extractcards(src: ref Layobject.Stack, r: Range): array of ref Object.Card
{
	if (len src.cards > src.maxcards)
		needresize = 1;
	deltag(src.cards[r.start:r.end], "c" + string src.id);
	n := r.end - r.start;
	cards := src.cards[r.start:r.end];
	newcards := array[len src.cards - n] of ref Object.Card;
	newcards[0:] = src.cards[0:r.start];
	newcards[r.start:] = src.cards[r.end:];
	src.cards = newcards;
	objneedsrepack(src);		# XXX not necessary if moving from top?
	return cards;
}

insertcards(dst: ref Layobject.Stack, cards: array of ref Object.Card, index: int)
{
	n := len cards;
	newcards := array[len dst.cards + n] of ref Object.Card;
	newcards[0:] = dst.cards[0:index];
	newcards[index + n:] = dst.cards[index:];
	newcards[index:] = cards;
	dst.cards = newcards;

	for (i := 0; i < len cards; i++)
		cards[i].parentid = dst.id;
	addtag(dst.cards[index:index + n], "c" + string dst.id);
	objneedsrepack(dst);		# XXX not necessary if adding to top?
	if (len dst.cards > dst.maxcards)
		needresize = 1;
}

destroy(obj: ref Object)
{
	if (obj.id >= 0)
		objects[obj.id] = nil;
	id := string obj.id;
	pick o := obj {
	Card =>
		cmd(win, ".c delete i" + id);	# XXX crashed here once...
	Widget =>
		cmd(win, ".c delete r" + id);
		w := ".buts." + id;
		cmd(win, "destroy " + w);
		dellayobject(o.o);
	Stack =>
		completeanim(o.o);
		cmd(win, ".c delete r" + id + " s" + id + " n" + id + " N" + id);
		if (o.o.title != nil)
			cmd(win, ".c delete t" + id);
		cmd(win, ".c delete c" + id);		# any remaining "fake" cards
		needrepack = 1;
		dellayobject(o.o);
	Button =>
		cmd(win, "destroy .buts." + string o.id);
	Member =>
		if (o.cid != -1) {
			# XXX remove member from members hash.
		}
	Layoutobj =>
		if ((l := findlayobject(o.lay.layid)) != nil) {
			# XXX are we sure they're not off-screen anyway?
			cmd(win, ".c move r" + string l.id + " 5000 5000");
			cmd(win, ".c move c" + string l.id + " 5000 5000");
			cmd(win, ".c move N" + string l.id + " 5000 5000");
			cmd(win, ".c move n" + string l.id + " 5000 5000");
			cmd(win, ".c move s" + string l.id + " 5000 5000");
		}
		if (layout == o.lay)
			layout = nil;
	Layoutframe =>
		if (layout == o.lay)
			layout = nil;
	}
}

dellayobject(lay: ref Layobject)
{
	if (lay.layid == -1)
		return;
	x := lay.layid % len layobjects;
	nl: list of ref Layobject;
	for (ll := layobjects[x]; ll != nil; ll = tl ll)
		if ((hd ll).layid != lay.layid)
			nl = hd ll :: nl;
	layobjects[x] = nl;
}

findlayobject(layid: int): ref Layobject
{
	if (layid == -1)
		return nil;
	for (ll := layobjects[layid % len layobjects]; ll != nil; ll = tl ll)
		if ((hd ll).layid == layid)
			return hd ll;
	return nil;
}

deltag(cards: array of ref Object.Card, tag: string)
{
	for (i := 0; i < len cards; i++)
		cmd(win, ".c dtag i" + string cards[i].id + " " + tag);
}

addtag(cards: array of ref Object.Card, tag: string)
{
	for (i := 0; i < len cards; i++)
		cmd(win, ".c addtag " + tag + " withtag i" + string cards[i].id);
}

join(v: list of string): string
{
	if (v == nil)
		return nil;
	s := hd v;
	for (v = tl v; v != nil; v = tl v)
		s += " " + hd v;
	return s;
}

notify(s: string)
{
	notifych <-= s;
}

notifierproc()
{
	notifypid := -1;
	sync := chan of int;
	for (;;) {
		s := <-notifych;
		kill(notifypid);
		spawn notifyproc(s, sync);
		notifypid = <-sync;
	}
}

notifyproc(s: string, sync: chan of int)
{
	sync <-= sys->pctl(0, nil);
	cmd(win, ".c delete notify");
	id := cmd(win, ".c create text " + p2s(visibleorigin()) + " -anchor nw -fill red -tags notify -text '" + s);
	bbox := cmd(win, ".c bbox " + id);
	cmd(win, ".c create rectangle " + bbox + " -fill #ffffaa -tags notify");
	cmd(win, ".c raise " + id);
	cmd(win, "update");
	sys->sleep(1500);
	cmd(win, ".c delete notify");
	cmd(win, "update");
}

# move canvas so that canvas point canvp lies under
# screen point scrp.
pan(canvp, scrp: Point)
{
	o := Point(int cmd(win, ".c cget -actx"), int cmd(win, ".c cget -acty"));
	co := canvp.sub(scrp.sub(o));
	sz := Point(int cmd(win, ".c cget -width"), int cmd(win, ".c cget -height"));

	cmd(win, ".c xview moveto " + string (real co.x / real sz.x));
	cmd(win, ".c yview moveto " + string (real co.y / real sz.y));
}

# return the top left point that's currently visible
# in the canvas, taking into account scrolling.
visibleorigin(): Point
{
	(scrx, scry) := (cmd(win, ".c cget -actx"), cmd(win, ".c cget -acty"));
	return Point (int cmd(win, ".c canvasx " + scrx),
		int cmd(win, ".c canvasy " + scry));
}

s2r(s: string): Rect
{
	r: Rect;
	(n, toks) := sys->tokenize(s, " ");
	if (n < 4)
		panic("malformed rectangle " + s);
	(r.min.x, toks) = (int hd toks, tl toks);
	(r.min.y, toks) = (int hd toks, tl toks);
	(r.max.x, toks) = (int hd toks, tl toks);
	(r.max.y, toks) = (int hd toks, tl toks);
	return r;
}

r2s(r: Rect): string
{
	return sys->sprint("%d %d %d %d", r.min.x, r.min.y, r.max.x, r.max.y);
}

p2s(p: Point): string
{
	return string p.x + " " + string p.y;
}

union(r1, r2: Rect): Rect
{
	if (r1.min.x > r2.min.x)
		r1.min.x = r2.min.x;
	if (r1.min.y > r2.min.y)
		r1.min.y = r2.min.y;

	if (r1.max.x < r2.max.x)
		r1.max.x = r2.max.x;
	if (r1.max.y < r2.max.y)
		r1.max.y = r2.max.y;
	return r1;
}
 
kill(pid: int)
{
	if ((fd := sys->open("/prog/"+string pid+"/ctl", Sys->OWRITE)) != nil)
		sys->write(fd, array of byte "kill", 4);
}

lockproc()
{
	for (;;) {
		<-cardlockch;
		cardlockch <-=1;
	}
}

lock()
{
	cardlockch <-= 1;
}

unlock()
{
	<-cardlockch;
}

openimage(file: string, id: string): Point
{
	if (tk->cmd(win, "image create bitmap " + id + " -file " + file)[0] == '!')
		return (0, 0);
	return (int tk->cmd(win, "image width " + id),
				int tk->cmd(win, "image height " + id));
}

# read images into tk.
readimages(dir: string, prefix: string): (int, Point)
{
	displ := drawctxt.display;
	if (cardsize.x > 0 && cardsize.y > 0 &&
			(img := displ.open(dir + "/" + prefix + ".all.bit")) != nil) {
		if (img.r.dx() % cardsize.x != 0 || img.r.dy() != cardsize.y)
			sys->fprint(stderr, "cards: inconsistent complete image, ignoring\n");
		else {
			n := img.r.dx() / cardsize.x;
			x := img.r.min.x;
			sys->print("found %d cards in complete image\n", n);
			for (i := 0; i < n; i++) {
				c := displ.newimage(((0, 0), cardsize), img.chans, 0, 0);
				c.draw(c.r, img, nil, (x, 0));
				id := prefix + string i;
				cmd(win, "image create bitmap " + id);
				tk->putimage(win, id, c, nil);
				x += cardsize.x;
			}
			return (n, cardsize);
		}
	}
				
	size := openimage("@" + dir + "/" + prefix + "0.bit", prefix + "0");
	if (size.x == 0) {
		sys->print("no first image (filename: '%s')\n", dir + "/" + prefix + "0.bit");
		return (0, (0, 0));
	}
	i := 1;
	for (;;) {
		nsize := openimage("@" + dir + "/" + prefix + string i + ".bit", prefix + string i);
		if (nsize.x == 0)
			break;
		if (!nsize.eq(size))
			sys->fprint(stderr, "warning: inconsistent image size in %s/%s%d.bit, " +
				"[%d %d] vs [%d %d]\n", dir, prefix, i, size.x, size.y, nsize.x, nsize.y);
		i++;
	}
	return (i, size);
}

newanimation(src: ref Layobject.Stack, r: Range): ref Animation
{
	a := ref Animation;
	a.srcpt = src.pos.add(src.delta.mul(r.start));
	cards := extractcards(src, r);
	a.cards = cards;
	a.waitch = chan of ref Animation;
	return a;
}

startanimating(a: ref Animation, dst: ref Layobject.Stack, index: int)
{
	q := dst.animq;
	if (q.isempty())
		spawn animqueueproc(a.waitch);

	a.tag = "a" + string animid++;
	addtag(a.cards, a.tag);
	q.put(a);
	a.dstid = dst.id;
	a.index = index;
	spawn animproc(a);
}

SPEED: con 1.5;			# animation speed in pixels/millisec

animproc(a: ref Animation)
{
	tick := chan of int;
	dst := stackobj(a.dstid);
	if (dst == nil)
		panic("animation destination has gone!");
	dstpt := dst.pos.add(dst.delta.mul(a.index));
	srcpt := a.srcpt;
	d := dstpt.sub(srcpt);
	# don't bother animating if moving to or from a hidden stack.
	if (!srcpt.eq(Hiddenpos) && !dst.pos.eq(Hiddenpos) && !d.eq((0, 0))) {
		mag := math->sqrt(real(d.x * d.x + d.y * d.y));
		(vx, vy) := (real d.x / mag, real d.y / mag);
		currpt := a.srcpt;		# current position of cards
		t0 := starttime;
		dt := int (mag / SPEED);
		t := 0;
		tickregister(tick);
		cmd(win, ".c raise " + a.tag);
		while (t < dt) {
			s := real t * SPEED;
			p := Point(srcpt.x + int (s * vx), srcpt.y + int (s * vy));
			dp := p.sub(currpt);
			cmd(win, ".c move " + a.tag + " " + string dp.x + " " + string dp.y);
			currpt = p;
			t = <-tick - t0;
		}
		tickunregister(tick);
		cmd(win, "update");
	}
	a.waitch <-= a;
}

tickregister(tick: chan of int)
{
	tickregisterch <-= tick;
}

tickunregister(tick: chan of int)
{
	tickunregisterch <-= tick;
}

tickproc(tick: chan of int)
{
	for (;;)
		tick <-= 1;
}

timeproc()
{
	reg: list of chan of int;
	dummytick := chan of int;
	realtick := chan of int;
	tick := dummytick;
	spawn tickproc(realtick);
	for (;;) {
		alt {
		c := <-tickregisterch =>
			if (reg == nil)
				tick = realtick;
			reg = c :: reg;
		c := <-tickunregisterch =>
			r: list of chan of int;
			for (; reg != nil; reg = tl reg)
				if (hd reg != c)
					r = hd reg :: r;
			reg = r;
			if (reg == nil)
				tick = dummytick;
		<-tick =>
			t := sys->millisec();
			for (r := reg; r != nil; r = tl r) {
				alt {
				hd r <-= t =>
					;
				* =>
					;
				}
			}
			cmd(win, "update");
		}
	}
}

yield()
{
	yieldch <-= 1;
}

yieldproc()
{
	for (;;)
		<-yieldch;
}


# send completed animations down animfinishedch;
# wait for a reply, which is either a new animation to wait
# for (the next in the queue) or nil, telling us to exit
animqueueproc(waitch: chan of ref Animation)
{
	rc := chan of chan of ref Animation;
	while (waitch != nil) {
		animfinishedch <-= (<-waitch, rc);
		waitch = <-rc;
	}
}

# an animation has finished.
# move the cards into their final place in the stack,
# remove the animation from the queue it's on,
# and inform the mediating process of the next animation process in the queue.
animterminated(v: (ref Animation, chan of chan of ref Animation))
{
	(a, rc) := v;
	deltag(a.cards, a.tag);
	dst := stackobj(a.dstid);
	insertcards(dst, a.cards, a.index);
	repackobj(dst);
	cmd(win, "update");
	q := dst.animq;
	q.get();
	if (q.isempty())
		rc <-= nil;
	else {
		a = q.peek();
		rc <-= a.waitch;
	}
}

actrect(win: ref Tk->Toplevel, w: string): Rect
{
	r: Rect;
	r.min.x = int cmd(win, w + " cget -actx") + int cmd(win, w + " cget -bd");
	r.min.y = int cmd(win, w + " cget -acty") + int cmd(win, w + " cget -bd");
	r.max.x = r.min.x + int cmd(win, w + " cget -actwidth");
	r.max.y = r.min.y + int cmd(win, w + " cget -actheight");
	return r;
}

actsize(win: ref Tk->Toplevel, w: string): Point
{
	return (int cmd(win, w + " cget -actwidth"), int cmd(win, w + " cget -actheight"));
}

Queue.put(q: self ref Queue, s: T)
{
	q.t = s :: q.t;
}

Queue.get(q: self ref Queue): T
{
	s: T;
	if(q.h == nil){
		q.h = revlist(q.t);
		q.t = nil;
	}
	if(q.h != nil){
		s = hd q.h;
		q.h = tl q.h;
	}
	return s;
}

Queue.peek(q: self ref Queue): T
{
	s: T;
	if (q.isempty())
		return s;
	s = q.get();
	q.h = s :: q.h;
	return s;
}

Queue.isempty(q: self ref Queue): int
{
	return q.h == nil && q.t == nil;
}

revlist(ls: list of T) : list of T
{
	rs: list of T;
	for (; ls != nil; ls = tl ls)
		rs = hd ls :: rs;
	return rs;
}

readconfig(): int
{
	for (lines := readconfigfile("/icons/cards/config"); lines != nil; lines = tl lines) {
		t := hd lines;
		case hd t {
		"rearborder" =>
			Rearborder = int hd tl t;
		"border" =>
			Border = int hd tl t;
		"selectborder" =>
			Selectborder = int hd tl t;
		"xdelta" =>
			carddelta.x = int hd tl t;
		"ydelta" =>
			carddelta.y = int hd tl t;
		"font" =>
			Textfont = hd tl t;
		"selectcolour" =>
			Selectcolour = hd tl t;
		"cardsize" =>
			if (len t != 3)
				sys->fprint(stderr, "cards: invalid value for cardsize attribute\n");
			else
				cardsize = (int hd tl t, int hd tl tl t);
		* =>
			sys->fprint(stderr, "cards: unknown config attribute: %s\n", hd t);
		}
	}
	return 0;
}

readcardimages(): int
{
	(nimages, cardsize) = readimages("/icons/cards", "c");
 	if (nimages == 0) {
		sys->fprint(stderr, "cards: no card images found\n");
		return -1;
	}
	sys->print("%d card images found\n", nimages);

	(nrears, rearsize) := readimages("/icons/cardrears", "rear");
	if (nrears > 0 && !rearsize.eq(cardsize)) {
		sys->fprint(stderr, "cards: card rear sizes don't match card sizes (%s vs %s)\n", p2s(rearsize), p2s(cardsize));
		return -1;
	}
	sys->print("%d card rear images found\n", nrears);
	cr := Rect((0, 0), cardsize);
	for (i := nrears; i < len rearcolours; i++) {
		cmd(win, "image create bitmap rear" + string i);
		img := drawctxt.display.newimage(cr, Draw->XRGB32, 0, Draw->Black);
		img.draw(cr.inset(Rearborder),
			drawctxt.display.color(rearcolours[i] - nrears), nil, (0, 0));
		tk->putimage(win, "rear" + string i, img, nil);
	}
	return 0;
}

readconfigfile(f: string): list of list of string
{
	sys->print("opening config file '%s'\n", f);
	fd := sys->open(f, Sys->OREAD);
	if (fd == nil)
		return nil;
	buf := array[Sys->ATOMICIO] of byte;
	nb := sys->read(fd, buf, len buf);
	if (nb <= 0)
		return nil;
	(nil, lines) := sys->tokenize(string buf[0:nb], "\r\n");
	r: list of list of string;
	for (; lines != nil; lines = tl lines) {
		(n, toks) := sys->tokenize(hd lines, " \t");
		if (n == 0)
			continue;
		if (n < 2)
			sys->fprint(stderr, "cards: invalid config line: %s\n", hd lines);
		else
			r = toks :: r;
	}
	return r;
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

panic(s: string)
{
	sys->fprint(stderr, "cards: panic: %s\n", s);
	raise "panic";
}

showtk := 0;
cmd(top: ref Tk->Toplevel, s: string): string
{
	if (showtk)
		sys->print("tk: %s\n", s);
	e := tk->cmd(top, s);
	if (e != nil && e[0] == '!') {
		sys->fprint(stderr, "tk error %s on '%s'\n", e, s);
		raise "panic";
	}
	return e;
}

max(a, b: int): int
{
	if (a > b)
		return a;
	return b;
}
