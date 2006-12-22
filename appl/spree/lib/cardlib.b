implement Cardlib;
include "sys.m";
	sys: Sys;
include "draw.m";
include "sets.m";
	sets: Sets;
	Set, set, A, B, All, None: import sets;
include "../spree.m";
	spree: Spree;
	Attributes, Range, Object, Clique, Member, rand: import spree;
include "objstore.m";
	objstore: Objstore;
include "cardlib.m";

MAXPLAYERS: con 4;

Layobject: adt {
	lay:		ref Object;
	name:	string;
	packopts:		int;
	pick {
	Obj =>
		obj:		ref Object;		# nil if it's a frame
	Frame =>
		facing:	int;				# only valid if for frames
	}
};

clique:	ref Clique;
cmembers: array of ref Cmember;
cpids := array[8] of list of ref Cmember;

# XXX first string is unnecessary as it's held in the Layobject anyway?
layouts := array[17] of list of (string, ref Layout, ref Layobject);
maxlayid := 1;
cmemberid := 1;

archiveobjs: array of list of (string, ref Object);

defaultrank := array[13] of {12, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11};
defaultsuitrank := array[] of {CLUBS => 0, DIAMONDS => 1, HEARTS => 2, SPADES => 3};

table := array[] of {
	0 =>	array[] of {
		(-1, dTOP|EXPAND, dBOTTOM, dTOP),
	},
	1 => array [] of {
		(0, dBOTTOM|FILLX, dBOTTOM, dTOP),
		(-1, dTOP|EXPAND, dBOTTOM, dTOP),
	},
	2 => array[] of {
		(0, dBOTTOM|FILLX, dBOTTOM, dTOP),
		(1, dTOP|FILLX, dTOP, dBOTTOM),
		(-1, dTOP|EXPAND, dBOTTOM, dTOP)
	},
	3 => array[] of {
		(2, dRIGHT|FILLY, dRIGHT, dLEFT),
		(0, dBOTTOM|FILLX, dBOTTOM, dTOP),
		(1, dTOP|FILLX, dTOP, dBOTTOM),
		(-1, dRIGHT|EXPAND, dBOTTOM, dTOP)
	},
	4 => array[] of {
		(1, dLEFT|FILLY, dLEFT, dRIGHT),
		(3, dRIGHT|FILLY, dRIGHT, dLEFT),
		(0, dBOTTOM|FILLX, dBOTTOM, dTOP),
		(2, dTOP|FILLX, dTOP, dBOTTOM),
		(-1, dRIGHT|EXPAND, dBOTTOM, dTOP)
	},
};


init(mod: Spree, g: ref Clique)
{
	sys = load Sys Sys->PATH;
	sets = load Sets Sets->PATH;
	if (sets == nil)
		panic(sys->sprint("cannot load %s: %r", Sets->PATH));
	objstore = load Objstore Objstore->PATH;
	if (objstore == nil)
		panic(sys->sprint("cannot load %s: %r", Objstore->PATH));
	objstore->init(mod, g);
	clique = g;
	spree = mod;
}

archive(): ref Object
{
	for (i := 0; i < len cmembers; i++) {
		cp := cmembers[i];
		setarchivename(cp.obj, "member" + string i);
		setarchivename(cp.layout.lay, "layout" + string i);
		sel := cp.sel;
		if (sel.stack != nil)
			setarchivename(sel.stack, "sel" + string i);
	}
	for (i = 0; i < len layouts; i++) {
		for (ll := layouts[i]; ll != nil; ll = tl ll) {
			(name, lay, layobj) := hd ll;
			if (name != nil)
				layobj.lay.setattr("layname", name, None);
			pick l := layobj {
			Frame =>
				l.lay.setattr("facing", sides[l.facing], None);
			Obj =>
				setarchivename(l.obj, "layid" + l.obj.getattr("layid"));
			}
		}
	}
	# XXX should archive layouts that aren't particular to a member.
	archiveobj := clique.newobject(nil, None, "archive");
	setarchivename(archiveobj, "archive");
	archiveobj.setattr("maxlayid", string maxlayid, None);
	archiveobj.setattr("cmemberid", string cmemberid, None);
	return archiveobj;
}

setarchivename(o: ref Object, name: string)
{
	objstore->setname(o, name);
}

getarchiveobj(name: string): ref Object
{
	return objstore->get(name);
}

archivearray(a: array of ref Object, name: string)
{
	for (i := 0; i < len a; i++)
		objstore->setname(a[i], name + string i);
}

getarchivearray(name: string): array of ref Object
{
	l: list of ref Object;
	for (i := 0; ; i++) {
		o := objstore->get(name + string i);
		if (o == nil)
			break;
		l = o :: l;
	}
	a := array[i] of ref Object;
	for (; l != nil; l = tl l)
		a[--i] = hd l;
	return a;
}

unarchive(): ref Object
{
	objstore->unarchive();
	archiveobj := getarchiveobj("archive");
	cpl: list of ref Cmember;
	for (i := 0; (o := getarchiveobj("member" + string i)) != nil; i++) {
		cp := ref Cmember(
			i,
			int o.getattr("id"),
			clique.membernamed(o.getattr("name")),
			o,
			ref Layout(getarchiveobj("layout" + string i)),
			ref Selection(getarchiveobj("sel" + string i), -1, 1, (0, 0), nil)
		);
		cp.sel.ownerid = cp.id;
		sel := cp.sel;
		if (sel.stack != nil && (selstr := sel.stack.getattr("sel")) != nil) {
			(n, val) := sys->tokenize(selstr, " ");
			if (tl val != nil && hd tl val == "-")
				(sel.r.start, sel.r.end) = (int hd val, int hd tl tl val);
			else {
				idxl: list of int;
				sel.isrange = 0;
				for (; val != nil; val = tl val)
					idxl = int hd val :: idxl;
				sel.idxl = idxl;
			}
		}
		lay := cp.layout.lay;
		# there should be exactly one child, of type "layframe"
		if (len lay.children != 1 || lay.children[0].objtype != "layframe")
			panic("invalid layout");
		x := strhash(nil, len layouts);
		layouts[x] = (nil, cp.layout, obj2layobj(lay.children[0])) :: layouts[x];
		unarchivelayoutobj(cp.layout, lay.children[0]);
		cpl = cp :: cpl;
	}
	cmembers = array[len cpl] of ref Cmember;
	for (; cpl != nil; cpl = tl cpl) {
		cp := hd cpl;
		cmembers[cp.ord] = cp;
		idx := cp.id % len cpids;
		cpids[idx] = cp :: cpids[idx];
	}
		
	maxlayid = int archiveobj.getattr("maxlayid");
	cmemberid = int archiveobj.getattr("cmemberid");
	return archiveobj;
}

unarchivelayoutobj(layout: ref Layout, o: ref Object)
{
	for (i := 0; i < len o.children; i++) {
		child := o.children[i];
		layobj := obj2layobj(child);
		if (layobj.name != nil) {
			x := strhash(layobj.name, len layouts);
			layouts[x] = (layobj.name, layout, layobj) :: layouts[x];
		}
		if (tagof(layobj) == tagof(Layobject.Frame))
			unarchivelayoutobj(layout, child);
	}
}

obj2layobj(o: ref Object): ref Layobject
{
	case o.objtype {
	"layframe" =>
		return ref Layobject.Frame(
			o,
			o.getattr("layname"),
			s2packopts(o.getattr("opts")),
			searchopt(sides, o.getattr("facing"))
		);
	"layobj" =>
		return ref Layobject.Obj(
			o,
			o.getattr("layname"),
			s2packopts(o.getattr("opts")),
			getarchiveobj("layid" + o.getattr("layid"))
		);
	* =>
		panic("invalid layobject found, of type '" + o.objtype + "'");
		return nil;
	}
}

Cmember.join(member: ref Member, ord: int): ref Cmember
{
	cmembers = (array[len cmembers + 1] of ref Cmember)[0:] = cmembers;
	if (ord == -1)
		ord = len cmembers - 1;
	else {
		cmembers[ord + 1:] = cmembers[ord:len cmembers - 1];
		for (i := ord + 1; i < len cmembers; i++)
			cmembers[i].ord = i;
	}
	cp := cmembers[ord] = ref Cmember(ord, cmemberid++, member, nil, nil, nil);
	cp.obj = clique.newobject(nil, All, "member");
	cp.obj.setattr("id", string cp.id, All);
	cp.obj.setattr("name", member.name, All);
	cp.obj.setattr("you", string cp.id, None.add(member.id));
	cp.obj.setattr("cliquetitle", clique.fname, All);
	cp.layout = newlayout(cp.obj, None.add(member.id));
	cp.sel = ref Selection(nil, cp.id, 1, (0, 0), nil);

	idx := cp.id % len cpids;
	cpids[idx] = cp :: cpids[idx];
	return cp;
}

Cmember.find(p: ref Member): ref Cmember
{
	id := p.id;
	for (i := 0; i < len cmembers; i++)
		if (cmembers[i].p.id == id)
			return cmembers[i];
	return nil;
}

Cmember.index(ord: int): ref Cmember
{
	if (ord < 0 || ord >= len cmembers)
		return nil;
	return cmembers[ord];
}

Cmember.next(cp: self ref Cmember, fwd: int): ref Cmember
{
	if (!fwd)
		return cp.prev(1);
	x := cp.ord + 1;
	if (x >= len cmembers)
		x = 0;
	return cmembers[x];
}

Cmember.prev(cp: self ref Cmember, fwd: int): ref Cmember
{
	if (!fwd)
		return cp.next(1);
	x := cp.ord - 1;
	if (x < 0)
		x = len cmembers - 1;
	return cmembers[x];
}
	
Cmember.leave(cp: self ref Cmember)
{
	ord := cp.ord;
	cmembers[ord] = nil;
	cmembers[ord:] = cmembers[ord + 1:];
	cmembers[len cmembers - 1] = nil;
	cmembers = cmembers[0:len cmembers - 1];
	for (i := ord; i < len cmembers; i++)
		cmembers[i].ord = i;
	cp.obj.delete();
	dellayout(cp.layout);
	cp.layout = nil;
	idx := cp.id % len cpids;
	l: list of ref Cmember;
	ll := cpids[idx];
	for (; ll != nil; ll = tl ll)
		if (hd ll != cp)
			l = hd ll :: l;
	cpids[idx] = l;
	cp.ord = -1;
}

Cmember.findid(id: int): ref Cmember
{
	for (l := cpids[id % len cpids]; l != nil; l = tl l)
		if ((hd l).id == id)
			return hd l;
	return nil;
}

newstack(parent: ref Object, owner: ref Member, spec: Stackspec): ref Object
{
	vis := All;
	if (spec.conceal) {
		vis = None;
		if (owner != nil)
			vis = vis.add(owner.id);
	}
	o := clique.newobject(parent, vis, "stack");
	o.setattr("maxcards", string spec.maxcards, All);
	o.setattr("style", spec.style, All);

	# XXX provide some means for this to contain the member's name?
	o.setattr("title", spec.title, All);
	return o;
}

makecard(deck: ref Object, c: Card, rear: string): ref Object
{
	card := clique.newobject(deck, None, "card");
	card.setattr("face", string c.face, All);
	vis := None;
	if(c.face)
		vis = All;
	card.setattr("number", string (c.number * 4 + c.suit), vis);
	if (rear != nil)
		card.setattr("rear", rear, All);
	return card;
}

makecards(deck: ref Object, r: Range, rear: string)
{
	for (i := r.start; i < r.end; i++)
		for(suit := 0; suit < 4; suit++)
			makecard(deck, (suit, i, 0), rear);
}

# deal n cards to each member, if possible.
# deal in chunks for efficiency.
# if accuracy is required (e.g. dealing from an unshuffled
# deck containing known cards) then this'll have to change.
deal(deck: ref Object, n: int, stacks: array of ref Object, first: int)
{
	ncards := len deck.children;
	ord := 0;
	permember := n;
	leftover := 0;
	if (n * len stacks > ncards) {
		# if trying to deal more cards than we've got,
		# deal all that we've got, distributing the remainder fairly.
		permember = ncards / len stacks;
		leftover = ncards % len stacks;
	}
	for (i := 0; i < len stacks; i++) {
		n = permember;
		if (leftover > 0) {
			n++;
			leftover--;
		}
		priv := stacks[(first + i) % len stacks];
		deck.transfer((ncards - n, ncards), priv, len priv.children);
		priv.setattr("n", string (int priv.getattr("n") + n), All);
		# make cards visible to member
		for (j := len priv.children - n; j < len priv.children; j++)
			setface(priv.children[j], 1);

		ncards -= n;
	}
}

setface(card: ref Object, face: int)
{
	# XXX check parent stack style and if it's a pile,
	# only expose a face up card at the top.

	card.setattr("face", string face, All);
	if (face)
		card.setattrvisibility("number", All);
	else
		card.setattrvisibility("number", None);
}

nmembers(): int
{
	return len cmembers;
}

getcard(card: ref Object): Card
{
	n := int card.getattr("number");
	(suit, num) := (n % 4, n / 4);
	return Card(suit, num, int card.getattr("face"));
}

getcards(stack: ref Object): array of Card
{
	a := array[len stack.children] of Card;
	for (i := 0; i < len a; i++)
		a[i] = getcard(stack.children[i]);
	return a;
}

discard(stk, pile: ref Object, facedown: int)
{
	n := len stk.children;
	if (facedown)
		for (i := 0; i < n; i++)
			setface(stk.children[i], 0);
	stk.transfer((0, n), pile, len pile.children);
}

# shuffle children into a random order.  first we make all the children
# invisible (which will cause them to be deleted in the clients) then
# shuffle to our heart's content, and make visible again...
shuffle(o: ref Object)
{
	ovis := o.visibility;
	o.setvisibility(None);
	a := o.children;
	n := len a;
	for (i := 0; i < n; i++) {
		j := i + rand(n - i);
		(a[i], a[j]) = (a[j], a[i]);
	}
	o.setvisibility(ovis);
}

sort(o: ref Object, rank, suitrank: array of int)
{
	if (rank == nil)
		rank = defaultrank;
	if (suitrank == nil)
		suitrank = defaultsuitrank;
	ovis := o.visibility;
	o.setvisibility(None);
	cardmergesort(o.children, array[len o.children] of ref Object, rank, suitrank);
	o.setvisibility(ovis);
}

cardcmp(a, b: ref Object, rank, suitrank: array of int): int
{
	c1 := getcard(a);
	c2 := getcard(b);
	if (suitrank[c1.suit] != suitrank[c2.suit])
		return suitrank[c1.suit] - suitrank[c2.suit];
	return rank[c1.number] - rank[c2.number];
}

cardmergesort(a, b: array of ref Object, rank, suitrank: array of int)
{
	r := len a;
	if (r > 1) {
		m := (r-1)/2 + 1;
		cardmergesort(a[0:m], b[0:m], rank, suitrank);
		cardmergesort(a[m:], b[m:], rank, suitrank);
		b[0:] = a;
		for ((i, j, k) := (0, m, 0); i < m && j < r; k++) {
			if (cardcmp(b[i], b[j], rank, suitrank) > 0)
				a[k] = b[j++];
			else
				a[k] = b[i++];
		}
		if (i < m)
			a[k:] = b[i:m];
		else if (j < r)
			a[k:] = b[j:r];
	}
}

# reverse and flip all cards in stack.
flip(stack: ref Object)
{
	ovis := stack.visibility;
	stack.setvisibility(None);
	a := stack.children;
	(n, m) := (len a, len a / 2);
	for (i := 0; i < m; i++) {
		j := n - i - 1;
		(a[i], a[j]) = (a[j], a[i]);
	}
	for (i = 0; i < n; i++)
		setface(a[i], !int a[i].getattr("face"));
	stack.setvisibility(ovis);
}

selection(stack: ref Object): ref Selection
{
	if ((owner := stack.getattr("owner")) != nil &&
			(cp := Cmember.findid(int owner)) != nil)
		return cp.sel;
	return nil;
}

Selection.set(sel: self ref Selection, stack: ref Object)
{
	if (stack == sel.stack)
		return;
	if (stack != nil) {
		oldowner := stack.getattr("owner");
		if (oldowner != nil) {
			oldcp := Cmember.findid(int oldowner);
			if (oldcp != nil)
				oldcp.sel.set(nil);
		}
	}
	if (sel.stack != nil)
		sel.stack.setattr("owner", nil, All);
	sel.stack = stack;
	sel.isrange = 1;
	sel.r = (0, 0);
	sel.idxl = nil;
	setsel(sel);
}

Selection.setexcl(sel: self ref Selection, stack: ref Object): int
{
	if (stack != nil && (oldowner := stack.getattr("owner")) != nil)
		if ((cp := Cmember.findid(int oldowner)) != nil && !cp.sel.isempty())
			return 0;
	sel.set(stack);
	return 1;
}

Selection.owner(sel: self ref Selection): ref Cmember
{
	return Cmember.findid(sel.ownerid);
}

Selection.setrange(sel: self ref Selection, r: Range)
{
	if (!sel.isrange) {
		sel.idxl = nil;
		sel.isrange = 1;
	}
	sel.r = r;
	setsel(sel);
}

Selection.addindex(sel: self ref Selection, i: int)
{
	if (sel.isrange) {
		sel.r = (0, 0);
		sel.isrange = 0;
	}
	ll: list of int;
	for (l := sel.idxl; l != nil; l = tl l) {
		if (hd l >= i)
			break;
		ll = hd l :: ll;
	}
	if (l != nil && hd l == i)
		return;
	l = i :: l;
	for (; ll != nil; ll = tl ll)
		l = hd ll :: l;
	sel.idxl = l;
	setsel(sel);
}

Selection.delindex(sel: self ref Selection, i: int)
{
	if (sel.isrange) {
		sys->print("cardlib: delindex from range-type selection\n");
		return;
	}
	ll: list of int;
	for (l := sel.idxl; l != nil; l = tl l) {
		if (hd l == i) {
			l = tl l;
			break;
		}
		ll = hd l :: ll;
	}
	for (; ll != nil; ll = tl ll)
		l = hd ll :: l;
	sel.idxl = l;
	setsel(sel);
}

Selection.isempty(sel: self ref Selection): int
{
	if (sel.stack == nil)
		return 1;
	if (sel.isrange)
		return sel.r.start == sel.r.end;
	return sel.idxl == nil;
}

Selection.isset(sel: self ref Selection, index: int): int
{
	if (sel.isrange)
		return index >= sel.r.start && index < sel.r.end;
	for (l := sel.idxl; l != nil; l = tl l)
		if (hd l == index)
			return 1;
	return 0;
}

Selection.transfer(sel: self ref Selection, dst: ref Object, index: int)
{
	if (sel.isempty())
		return;
	src := sel.stack;
	if (sel.isrange) {
		r := sel.r;
		sel.set(nil);
		src.transfer(r, dst, index);
	} else {
		if (sel.stack == dst) {
			sys->print("cardlib: cannot move multisel to same stack\n");
			return;
		}
		xl := l := sel.idxl;
		sel.set(nil);
		rl: list of Range;
		for (; l != nil; l = tl l) {
			r := Range(hd l, hd l);
			last := l;
			# concatenate adjacent items, for efficiency.
			for (l = tl l; l != nil; (last, l) = (l, tl l)) {
				if (hd l != r.end + 1)
					break;
				r.end = hd l;
			}
			rl = (r.start, r.end + 1) :: rl;
			l = last;
		}
		# do ranges in reverse, so that later ranges
		# aren't affected by earlier ones.
		if (index == -1)
			index = len dst.children;
		for (; rl != nil; rl = tl rl)
			src.transfer(hd rl, dst, index);
	}
}

setsel(sel: ref Selection)
{
	if (sel.stack == nil)
		return;
	s := "";
	if (sel.isrange) {
		if (sel.r.end > sel.r.start)
			s = string sel.r.start + " - " + string sel.r.end;
	} else {
		if (sel.idxl != nil) {
			s = string hd sel.idxl;
			for (l := tl sel.idxl; l != nil; l = tl l)
				s += " " + string hd l;
		}
	}
	if (s != nil)
		sel.stack.setattr("owner", string sel.owner().id, All);
	else
		sel.stack.setattr("owner", nil, All);
	vis := None.add(sel.owner().p.id);
	sel.stack.setattr("sel", s, vis);
	sel.stack.setattrvisibility("sel", vis);
}

newlayout(parent: ref Object, vis: Set): ref Layout
{
	l := ref Layout(clique.newobject(parent, vis, "layout"));
	x := strhash(nil, len layouts);
	layobj := ref Layobject.Frame(nil, "", dTOP|EXPAND|FILLX|FILLY, dTOP);
	layobj.lay = clique.newobject(l.lay, All, "layframe");
	layobj.lay.setattr("opts", packopts2s(layobj.packopts), All);
	layouts[x] = (nil, l, layobj) :: layouts[x];
#	sys->print("[%d] => ('%s', %ux, %ux) (new layout)\n", x, "", l, layobj);
	return l;
}

addlayframe(name, parent: string, layout: ref Layout, packopts: int, facing: int)
{
#	sys->print("addlayframe('%s', %ux, name: %s\n", parent, layout, name);
	addlay(parent, layout, ref Layobject.Frame(nil, name, packopts, facing));
}

addlayobj(name, parent: string, layout: ref Layout, packopts: int, obj: ref Object)
{
#	sys->print("addlayobj('%s', %ux, name: %s, obj %d\n", parent, layout, name, obj.id);
	addlay(parent, layout, ref Layobject.Obj(nil, name, packopts, obj));
}

addlay(parent: string, layout: ref Layout, layobj: ref Layobject)
{
	a := layouts;
	name := layobj.name;
	x := strhash(name, len a);
	added := 0;
	for (nl := a[strhash(parent, len a)]; nl != nil; nl = tl nl) {
		(s, lay, parentlay) := hd nl;
		if (s == parent && (layout == nil || layout == lay)) {
			pick p := parentlay {
			Obj =>
				sys->fprint(sys->fildes(2),
					"cardlib: cannot add layout to non-frame: %d\n", p.obj.id);
			Frame =>
				nlayobj := copylayobj(layobj);
				nlayobj.packopts = packoptsfacing(nlayobj.packopts, p.facing);
				o: ref Object;
				pick lo := nlayobj {
				Obj =>
					o = clique.newobject(p.lay, All, "layobj");
					id := lo.obj.getattr("layid");
					if (id == nil) {
						id = string maxlayid++;
						lo.obj.setattr("layid", id, All);
					}
					o.setattr("layid", id, All);
				Frame =>
					o = clique.newobject(p.lay, All, "layframe");
					lo.facing = (lo.facing + p.facing) % 4;
				}
				o.setattr("opts", packopts2s(nlayobj.packopts), All);
				nlayobj.lay = o;
				if (name != nil)
					a[x] = (name, lay, nlayobj) :: a[x];
				added++;
			}
		}
	}
	if (added == 0)
		sys->print("no parent found, adding '%s', parent '%s', layout %ux\n",
			layobj.name, parent, layout);
#	sys->print("%d new entries\n", added);
}

maketable(parent: string)
{
	# make a table for all current members.
	plcount := len cmembers;
	packopts := table[plcount];
	for (i := 0; i < plcount; i++) {
		layout := cmembers[i].layout;
		for (j := 0; j < len packopts; j++) {
			(ord, outer, inner, facing) := packopts[j];
			name := "public";
			if (ord != -1)
				name = "p" + string ((ord + i) % plcount);
			addlayframe("@" + name, parent, layout, outer, dTOP);
			addlayframe(name, "@" + name, layout, inner, facing);
		}
	}
}

dellay(name: string, layout: ref Layout)
{
	a := layouts;
	x := strhash(name, len a);
	rl: list of (string, ref Layout, ref Layobject);
	for (nl := a[x]; nl != nil; nl = tl nl) {
		(s, lay, layobj) := hd nl;
		if (s != name || (layout != nil && layout != lay))
			rl = hd nl :: rl;
	}
	a[x] = rl;
}

dellayout(layout: ref Layout)
{
	for (i := 0; i < len layouts; i++) {
		ll: list of (string, ref Layout, ref Layobject);
		for (nl := layouts[i]; nl != nil; nl = tl nl) {
			(s, lay, layobj) := hd nl;
			if (lay != layout)
				ll = hd nl :: ll;
		}
		layouts[i] = ll;
	}
}

copylayobj(obj: ref Layobject): ref Layobject
{
	pick o := obj {
	Frame =>
		return ref *o;
	Obj =>
		return ref *o;
	}
	return nil;
}

packoptsfacing(opts, facing: int): int
{
	if (facing == dTOP)
		return opts;
	nopts := 0;

	# 4 directions
	nopts |= (facing + (opts & dMASK)) % 4;

	# 2 orientations
	nopts |= ((facing + ((opts & oMASK) >> oSHIFT)) % 4) << oSHIFT;

	# 8 anchorpoints (+ centre)
	a := (opts & aMASK);
	if (a != aCENTRE)
		a = ((((a >> aSHIFT) - 1 + facing * 2) % 8) + 1) << aSHIFT;
	nopts |= a;

	# two fill options
	if (facing % 2) {
		if (opts & FILLX)
			nopts |= FILLY;
		if (opts & FILLY)
			nopts |= FILLX;
	} else
		nopts |= (opts & (FILLX | FILLY));

	nopts |= (opts & EXPAND);
	return nopts;
}

# these arrays are dependent on the ordering of
# the relevant constants defined in cardlib.m

sides := array[] of {"top", "left", "bottom", "right"};
anchors := array[] of {"centre", "n", "nw", "w", "sw", "s", "se", "e", "ne"};
orientations := array[] of {"right", "up", "left", "down"};
fills := array[] of {"none", "x", "y", "both"};

packopts2s(opts: int): string
{
	s := orientations[(opts & oMASK) >> oSHIFT] +
			" -side " + sides[opts & dMASK];
	if ((opts & aMASK) != aCENTRE)
		s += " -anchor " + anchors[(opts & aMASK) >> aSHIFT];
	if (opts & EXPAND)
		s += " -expand 1";
	if (opts & (FILLX | FILLY))
		s += " -fill " + fills[(opts & FILLMASK) >> FILLSHIFT];
	return s;
}

searchopt(a: array of string, s: string): int
{
	for (i := 0; i < len a; i++)
		if (a[i] == s)
			return i;
	panic("unknown pack option '" + s + "'");
	return 0;
}

s2packopts(s: string): int
{
	(nil, toks) := sys->tokenize(s, " ");
	if (toks == nil)
		panic("invalid packopts: " + s);
	p := searchopt(orientations, hd toks) << oSHIFT;
	for (toks = tl toks; toks != nil; toks = tl tl toks) {
		if (tl toks == nil)
			panic("invalid packopts: " + s);
		arg := hd tl toks;
		case hd toks {
		"-anchor" =>
			p |= searchopt(anchors, arg) << aSHIFT;
		"-fill" =>
			p |= searchopt(fills, arg) << FILLSHIFT;
		"-side" =>
			p |= searchopt(sides, arg) << dSHIFT;
		"-expand" =>
			if (int hd tl toks)
				p |= EXPAND;
		* =>
			panic("unknown pack option: " + hd toks);
		}
	}
	return p;
}

panic(e: string)
{
	sys->fprint(sys->fildes(2), "cardlib panic: %s\n", e);
	raise "panic";
}

assert(b: int, err: string)
{
	if (b == 0)
		raise "parse:" + err;
}

# from Aho Hopcroft Ullman
strhash(s: string, n: int): int
{
	h := 0;
	m := len s;
	for(i := 0; i<m; i++){
		h = 65599 * h + s[i];
	}
	return (h & 16r7fffffff) % n;
}
