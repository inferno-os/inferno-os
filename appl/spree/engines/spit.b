implement Gatherengine;

include "sys.m";
	sys: Sys;
include "draw.m";
include "sets.m";
	sets: Sets;
	Set, All, None, A, B: import sets;
include "../spree.m";
	spree: Spree;
	Attributes, Range, Object, Clique, Member, rand: import spree;
include "allow.m";
	allow: Allow;
include "cardlib.m";
	cardlib: Cardlib;
	Selection, Cmember, Card: import cardlib;
	dTOP, dLEFT, dBOTTOM, oDOWN, EXPAND, FILLX, FILLY, aCENTRELEFT, Stackspec: import Cardlib;
include "../gather.m";

clique: ref Clique;
CLICK, SPIT, SAY, SHOW: con iota;
playing := 0;
dealt := 0;
deck: ref Object;
buttons: ref Object;
winner: ref Member;

Dmember: adt {
	spare:	ref Object;
	row:		array of ref Object;
	centre:	ref Object;
};

dmembers := array[2] of ref Dmember;

Openspec := Stackspec(
	"display",		# style
	4,			# maxcards
	0,			# conceal
	""			# title
);

Pilespec := Stackspec(
	"pile",		# style
	13,			# maxcards
	0,			# conceal
	"pile"		# title
);

Untitledpilespec := Stackspec(
	"pile",		# style
	13,			# maxcards
	0,			# conceal
	""			# title
);

clienttype(): string
{
	return "cards";
}


init(srvmod: Spree, g: ref Clique, nil: list of string, nil: int): string
{
	sys = load Sys Sys->PATH;
	clique = g;
	spree = srvmod;

	allow = load Allow Allow->PATH;
	if (allow == nil) {
		sys->print("spit: cannot load %s: %r\n", Allow->PATH);
		return "bad module";
	}
	allow->init(spree, clique);
	sets = load Sets Sets->PATH;
	if (sets == nil) {
		sys->print("spit: cannot load %s: %r\n", Sets->PATH);
		return "bad module";
	}
	sets->init();

	cardlib = load Cardlib Cardlib->PATH;
	if (cardlib == nil) {
		sys->print("spit: cannot load %s: %r\n", Cardlib->PATH);
		return "bad module";
	}
	cardlib->init(spree, clique);

	return nil;
}

maxmembers(): int
{
	return 2;
}

readfile(nil: int, nil: big, nil: int): array of byte
{
	return nil;
}

propose(members: array of string): string
{
	if (len members != 2)
		return "need exactly two members";
	return nil;
}

archive()
{
	archiveobj := cardlib->archive();
	allow->archive(archiveobj);
	for (i := 0; i < len dmembers; i++) {
		dp := dmembers[i];
		s := "d" + string i + "_";
		cardlib->setarchivename(dp.spare, s + "spare");
		cardlib->setarchivename(dp.centre, s + "centre");
		for (j := 0; j < len dp.row; j++)
			cardlib->setarchivename(dp.row[j], s + "row" + string j);
	}
	archiveobj.setattr("playing", string playing, None);
	archiveobj.setattr("dealt", string dealt, None);
	cardlib->setarchivename(deck, "deck");
}

start(members: array of ref Member, archived: int)
{
	cardlib->init(spree, clique);
	if (archived) {
		archiveobj := cardlib->unarchive();
		allow->unarchive(archiveobj);
		playing = int archiveobj.getattr("playing");
		dealt = int archiveobj.getattr("dealt");
		deck = cardlib->getarchiveobj("deck");
		for (i := 0; i < len dmembers; i++) {
			dp := dmembers[i] = ref Dmember;
			s := "d" + string i + "_";
			dp.spare = cardlib->getarchiveobj(s + "spare");
			dp.centre = cardlib->getarchiveobj(s + "centre");
			dp.row = array[4] of ref Object;
			for (j := 0; j < len dp.row; j++)
				dp.row[j] = cardlib->getarchiveobj(s + "row" + string j);
		}
	} else {
		buttons = clique.newobject(nil, All, "buttons");
		pset := None;
		for (i := 0; i < len members; i++) {
			Cmember.join(members[i], i);
			pset = pset.add(members[i].id);
		}
		# member 0 layout visible to member 0 and everyone else but other member.
		# could be All.del(members[1].id) but doing it this way extends to many-member cliques.
		Cmember.index(0).layout.lay.setvisibility(All.X(A&~B, pset).add(members[0].id));
		layout();
		deal();
		dealt = 1;
		playing = 0;
		allow->add(SPIT, nil, "spit");
		allow->add(SAY, nil, "say &");
		allow->add(SHOW, nil, "show");
	}
}

command(p: ref Member, cmd: string): string
{
	(err, tag, toks) := allow->action(p, cmd);
	if (err != nil){
		if(winner != nil){
			if(winner == p)
				return "game has finished: you have won";
			return "game has finished: you have lost";
		}
		return err;
	}
	cp := Cmember.find(p);
	if (cp == nil)
		return "you're only watching";
	case tag {
	SPIT =>
		if (!dealt) {
			deal();
			dealt = 1;
		} else if (!playing) {
			go();
			allow->add(CLICK, nil, "click %o %d");
			playing = 1;
		} else if (!canplay(!cp.ord)) {
			go();
		} else
			return "it is possible to play";
		
	CLICK =>
		stack := clique.objects[int hd tl toks];
		nc := len stack.children;
		idx := int hd tl tl toks;
		sel := cp.sel;
		stype := stack.getattr("type");
		d := dmembers[cp.ord];
		if (sel.isempty() || sel.stack == stack) {
			# selecting a card to move
			if (idx < 0 || idx >= len stack.children)
				return "invalid index";
			if (owner(stack) != cp)
				return "not yours, don't touch!";
			case stype {
			"row" =>
				card := getcard(stack.children[nc - 1]);
				if (card.face == 0)
					cardlib->setface(stack.children[nc - 1], 1);
				else
					select(cp, stack, (nc - 1, nc));
			* =>
				return "you can't move cards from there";
			}
		} else {
			# selecting a stack to move to.
			case stype {
			"centre" =>
				card := getcard(sel.stack.children[sel.r.start]);
				onto := getcard(stack.children[nc - 1]);
				if ((card.number + 1) % 13 != onto.number &&
						(card.number + 12) % 13 != onto.number) {
					sel.set(nil);
					return "out of sequence";
				}
				sel.transfer(stack, -1);
				for (i := 0; i < len d.row; i++)
					if (len d.row[i].children > 0)
						break;
				if (i == len d.row) {
					if (len d.spare.children == 0) {
						remark(p.name + " has won");
						winner = p;
						allow->del(CLICK, nil);
						allow->del(SPIT, nil);
						clearsel();
					} else
						finish(cp);
				}
			"row" =>
				if (owner(stack) != cp) {
					sel.set(nil);
					return "not yours, don't touch!";
				}
				if (nc != 0) {
					sel.set(nil);
					return "cannot stack cards";
				}
				sel.transfer(stack, -1);
			* =>
				sel.set(nil);
				return "can't move there";
			}
		}
		
	SAY =>
		clique.action("say member " + string p.id + ": '" + concat(tl toks) + "'", nil, nil, All);

	SHOW =>
		clique.show(nil);
	}
	return nil;
}

canplay(ord: int): int
{
	d := dmembers[ord];
	nmulti := nfree := 0;
	for (j := 0; j < len d.row; j++) {
		s1 := d.row[j];
		if (len s1.children > 0) {
			nmulti += len s1.children > 1;
			card1 := getcard(s1.children[len s1.children - 1]);
			for (k := 0; k < 2; k++) {
				s2 := dmembers[k].centre;
				if (len s2.children > 0) {
					card2 := getcard(s2.children[len s2.children - 1]);
					if ((card1.number + 1) % 13 == card2.number ||
							(card1.number + 12) % 13 == card2.number)
						return 1;
				}
			}
		} else
			nfree++;
	}
	return nmulti > 0 && nfree > 0;
}

bottomdiscard(src, dst: ref Object)
{
	cardlib->flip(src);
	for (i := 0; i < len src.children; i++)
		cardlib->setface(src.children[i], 0);
	src.transfer((0, len src.children), dst, 0);
}

finish(winner: ref Cmember)
{
	loser := dmembers[!winner.ord];
	for (i := 0; i < 2; i++) {
		d := dmembers[i];
		bottomdiscard(d.centre, loser.spare);
		for (j := 0; j < len d.row; j++)
			bottomdiscard(d.row[j], loser.spare);
	}
	playing = 0;
	dealt = 0;
	allow->del(CLICK, nil);
	allow->add(SPIT, nil, "spit");
	clearsel();
}

go()
{
	for (i := 0; i < 2; i++) {
		d := dmembers[i];
		n := len d.spare.children;
		if (n > 0)
			d.spare.transfer((n - 1, n), d.centre, -1);
		else if ((m := len dmembers[!i].spare.children) > 0)
			dmembers[!i].spare.transfer((m - 1, m), d.centre, -1);
		else {
			# both members' spare piles are used up; use central piles instead
			for (j := 0; j < 2; j++) {
				cardlib->discard(dmembers[j].centre, dmembers[j].spare, 0);
				cardlib->flip(dmembers[j].spare);
			}
			go();
			return;
		}
		cardlib->setface(d.centre.children[len d.centre.children - 1], 1);
	}
}

getcard(card: ref Object): Card
{
	return cardlib->getcard(card);
}

select(cp: ref Cmember, stack: ref Object, r: Range)
{
	if (cp.sel.isempty()) {
		cp.sel.set(stack);
		cp.sel.setrange(r);
	} else {
		if (cp.sel.r.start == r.start && cp.sel.r.end == r.end)
			cp.sel.set(nil);
		else
			cp.sel.setrange(r);
	}
}

owner(stack: ref Object): ref Cmember
{
	parent := clique.objects[stack.parentid];
	n := cardlib->nmembers();
	for (i := 0; i < n; i++) {
		cp := Cmember.index(i);
		if (cp.obj == parent)
			return cp;
	}
	return nil;
}

layout()
{
	for (i := 0; i < 2; i++) {
		cp := Cmember.index(i);
		d := dmembers[i] = ref Dmember;
		d.spare = newstack(cp.obj, Untitledpilespec, "spare");
		d.row = array[4] of {* => newstack(cp.obj, Openspec, "row")};
		d.centre = newstack(cp.obj, Untitledpilespec, "centre");
	}
	deck = clique.newobject(nil, All, "stack");
	cardlib->makecards(deck, (0, 13), "0");
	cardlib->shuffle(deck);

	entry := clique.newobject(nil, All, "widget entry");
	entry.setattr("command", "say", All);
	cardlib->addlayobj(nil, nil, nil, dTOP|FILLX, entry);

	cardlib->addlayframe("arena", nil, nil, dTOP|EXPAND|FILLX|FILLY, dTOP);
	maketable("arena");
	spitbutton := newbutton("spit", "Spit!");
	for (i = 0; i < 2; i++) {
		d := dmembers[i];
		f := "p" + string i;

		subf := "f" + string i;
		cardlib->addlayframe(subf, f, nil, dLEFT, dTOP);
		cardlib->addlayobj(nil, subf, Cmember.index(i).layout, dTOP, spitbutton);
		cardlib->addlayobj(nil, subf, nil, dTOP, d.spare);
		for (j := 0; j < len d.row; j++)
			cardlib->addlayobj(nil, f, nil, dLEFT|EXPAND|oDOWN, d.row[j]);
		cardlib->addlayobj(nil, "centre", nil, dLEFT|EXPAND, d.centre);
	}
}

newbutton(cmd, text: string): ref Object
{
	but := clique.newobject(nil, All, "widget button");
	but.setattr("command", cmd, All);
	but.setattr("text", text, All);
	return but;
}

settopface(stack: ref Object, face: int)
{
	n := len stack.children;
	if (n > 0)
		cardlib->setface(stack.children[n - 1], face);
}

transfertop(src, dst: ref Object, index: int)
{
	n := len src.children;
	src.transfer((n - 1, n), dst, index);
}

deal()
{
	clearsel();
	n := len deck.children;
	if (n > 0) {
		deck.transfer((0, n / 2), dmembers[0].spare, 0);
		deck.transfer((0, len deck.children), dmembers[1].spare, 0);
	}

	for (i := 0; i < 2; i++) {
		d := dmembers[i];
loop:		for (j := 0; j < len d.row; j++) {
			for (k := j; k < len d.row; k++) {
				if (len d.spare.children == 0)
					break loop;
				transfertop(d.spare, d.row[k], -1);
			}
		}
		for (j = 0; j < len d.row; j++)
			settopface(d.row[j], 1);
	}
}

maketable(parent: string)
{
	addlayframe: import cardlib;

	for (i := 0; i < 2; i++) {
		layout := Cmember.index(i).layout;
		addlayframe("p" + string !i, parent, layout, dTOP|EXPAND, dBOTTOM);
		addlayframe("p" + string i, parent, layout, dBOTTOM|EXPAND, dTOP);
		addlayframe("centre", parent, layout, dTOP|EXPAND, dTOP);
	}
}

newstack(parent: ref Object, spec: Stackspec, stype: string): ref Object
{
	stack := cardlib->newstack(parent, nil, spec);
	stack.setattr("type", stype, None);
	stack.setattr("actions", "click", All);
	return stack;
}

concat(v: list of string): string
{
	if (v == nil)
		return nil;
	s := hd v;
	for (v = tl v; v != nil; v = tl v)
		s += " " + hd v;
	return s;
}

remark(s: string)
{
	clique.action("remark " + s, nil, nil, All);
}

clearsel()
{
	n := cardlib->nmembers();
	for (i := 0; i < n; i++)
		Cmember.index(i).sel.set(nil);
}
