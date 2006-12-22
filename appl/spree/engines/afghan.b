implement Gatherengine;

include "sys.m";
	sys: Sys;
include "draw.m";
include "sets.m";
	All, None: import Sets;
include "../spree.m";
	spree: Spree;
	Attributes, Range, Object, Clique, Member, rand: import spree;
include "allow.m";
	allow: Allow;
include "cardlib.m";
	cardlib: Cardlib;
	Selection, Cmember: import cardlib;
	dTOP, dLEFT, oLEFT, oRIGHT, EXPAND, FILLX, FILLY, aUPPERCENTRE,
	Stackspec: import Cardlib;
include "../gather.m";

CLICK, REDEAL: con iota;

clique: ref Clique;
rows: array of ref Object;		# [10]
central: array of ref Object;	# [4]
chokey, deck: ref Object;
direction := 0;
nredeals := 0;

Rowpilespec := Stackspec(
	"display",		# style
	10,			# maxcards
	0,			# conceal
	nil			# title
);

Centralpilespec := Stackspec(
	"pile",
	13,
	0,
	nil
);

clienttype(): string
{
	return "cards";
}

maxmembers(): int
{
	return 1;
}

readfile(nil: int, nil: big, nil: int): array of byte
{
	return nil;
}

init(srvmod: Spree, g: ref Clique, nil: list of string, nil: int): string
{
	sys = load Sys Sys->PATH;
	clique = g;
	spree = srvmod;
	allow = load Allow Allow->PATH;
	if (allow == nil) {
		sys->print("whist: cannot load %s: %r\n", Allow->PATH);
		return "bad module";
	}
	allow->init(spree, clique);
	cardlib = load Cardlib Cardlib->PATH;
	if (cardlib == nil) {
		sys->print("whist: cannot load %s: %r\n", Cardlib->PATH);
		return "bad module";
	}
	cardlib->init(spree, clique);
	return nil;
}

propose(members: array of string): string
{
	if (len members != 1)
		return "one member only";
	return nil;
}

archive()
{
	archiveobj := cardlib->archive();
	allow->archive(archiveobj);
	cardlib->archivearray(rows, "rows");
	cardlib->archivearray(central, "central");
	cardlib->setarchivename(chokey, "chokey");
	cardlib->setarchivename(deck, "deck");
	archiveobj.setattr("direction", string direction, None);
	archiveobj.setattr("nredeals", string nredeals, None);
}

start(members: array of ref Member, archived: int)
{
	if (archived) {
		archiveobj := cardlib->unarchive();
		allow->unarchive(archiveobj);
		rows = cardlib->getarchivearray("rows");
		central = cardlib->getarchivearray("central");
		chokey = cardlib->getarchiveobj("chokey");
		deck = cardlib->getarchiveobj("deck");
		direction = int archiveobj.getattr("direction");
		nredeals = int archiveobj.getattr("nredeals");
	} else {
		p := members[0];
		Cmember.join(p, -1).layout.lay.setvisibility(All);
		startclique();
		allow->add(CLICK, p, "click %o %d");
	}
}

command(p: ref Member, cmd: string): string
{
	(err, tag, toks) := allow->action(p, cmd);
	if (err != nil)
		return err;
	cp := Cmember.find(p);
	if (cp == nil)
		return "you are not playing";

	case tag {
	REDEAL =>
		if (nredeals >= 3)
			return "no more redeals";
		redeal();
		nredeals++;
	CLICK =>
		# click stack index
		stack := clique.objects[int hd tl toks];
		nc := len stack.children;
		idx := int hd tl tl toks;
		sel := cp.sel;
		stype := stack.getattr("type");

		if (sel.isempty() || sel.stack == stack) {
			# selecting a card to move
			if (idx < 0 || idx >= len stack.children)
				return "invalid index";
			case stype {
			"row" or
			"chokey" =>
				select(cp, stack, (nc - 1, nc));
			* =>
				return "you can't move cards from there";
			}
		} else {
			# selecting a stack to move to.
			card := cardlib->getcard(sel.stack.children[sel.r.start]);
			case stype {
			"central" =>
				top := cardlib->getcard(stack.children[nc - 1]);
				if (direction == 0) {
					if (card.number != (top.number + 1) % 13 &&
							card.number != (top.number + 12) % 13)
						return "out of sequence";
					if (card.suit != top.suit)
						return "wrong suit";
					direction = card.number - top.number;
				} else {
					if (card.number != (top.number + direction + 13) % 13)
						return "out of sequence";
					if (card.suit != top.suit)
						return "wrong suit";
				}
			"row" =>
				if (nc == 0 || sel.stack.getattr("type") == "chokey")
					return "you wish!";
				top := cardlib->getcard(stack.children[nc - 1]);
				if (card.suit != top.suit)
					return "wrong suit";
				if (card.number != (top.number + 1) % 13 &&
						card.number != (top.number + 12) % 13)
					return "out of sequence";
			"chokey" =>
				if (nc != 0)
					return "only one card allowed there";
			* =>
				return "can't move there";
			}
			sel.transfer(stack, -1);
		}
	}
	return nil;
}

startclique()
{
	addlayobj, addlayframe: import cardlib;

	entry := clique.newobject(nil, All, "widget entry");
	entry.setattr("command", "say", All);

	but := clique.newobject(nil, All, "widget button");
	but.setattr("text", "Redeal", All);
	but.setattr("command", "redeal", All);
	allow->add(REDEAL, Cmember.index(0).p, "redeal");

	addlayframe("topf", nil, nil, dTOP|EXPAND|FILLX|aUPPERCENTRE, dTOP);
	addlayobj(nil, "topf", nil, dLEFT, but);
	addlayobj(nil, "topf", nil, dLEFT|EXPAND|FILLX, entry);

	addlayframe("arena", nil, nil, dTOP|EXPAND|FILLX|FILLY, dTOP);

	addlayframe("left", "arena", nil, dLEFT|EXPAND, dTOP);
	addlayframe("central", "arena", nil, dLEFT|EXPAND, dTOP);
	addlayframe("right", "arena", nil, dLEFT|EXPAND, dTOP);

	rows = array[10] of {* => newstack(nil, Rowpilespec, "row")};
	central = array[4] of {* => newstack(nil, Centralpilespec, "central")};
	chokey = newstack(nil, Centralpilespec, "chokey");

	deck = clique.newobject(nil, All, "stack");
	cardlib->makecards(deck, (0, 13), nil);
	cardlib->shuffle(deck);

	for (i := 0; i < 5; i++)
		addlayobj(nil, "left", nil, dTOP|oRIGHT, rows[i]);
	for (i = 5; i < 10; i++)
		addlayobj(nil, "right", nil, dTOP|oRIGHT, rows[i]);
	for (i = 0; i < 4; i++)
		addlayobj(nil, "central", nil, dTOP, central[i]);
	addlayobj(nil, "central", nil, dTOP, chokey);

	for (i = 0; i < 52; i++)
		cardlib->setface(deck.children[i], 1);
	# get top card from deck for central piles.
	c := deck.children[len deck.children - 1];
	v := cardlib->getcard(c);
	j := 0;
	for (i = len deck.children - 1; i >= 0; i--) {
		w := cardlib->getcard(deck.children[i]);
		if (w.number == v.number)
			deck.transfer((i, i + 1), central[j++], -1);
	}
	for (i = 0; i < 10; i += 5) {
		for (j = i; j < i + 4; j++)
			deck.transfer((0, 5), rows[j], -1);
		deck.transfer((0, 4), rows[j], -1);
	}
}

redeal()
{
	for (i := 0; i < len rows; i++)
		cardlib->discard(rows[i], deck, 0);
	cardlib->shuffle(deck);

	i = 0;
	while ((n := len deck.children) > 0) {
		l, r: int;
		if (n >= 10)
			l = r = 5;
		else {
			l = n / 2;
			r = n - l;
		}
		deck.transfer((0, l), rows[i], 0);
		deck.transfer((0, r), rows[i + 5], 0);
		i++;
	}

	n = cardlib->nmembers();
	for (i = 0; i < n; i++)
		Cmember.index(i).sel.set(nil);
}

newstack(parent: ref Object, spec: Stackspec, stype: string): ref Object
{
	stack := cardlib->newstack(parent, nil, spec);
	stack.setattr("type", stype, None);
	stack.setattr("actions", "click", All);
	return stack;
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

archivearray(a: array of ref Object, name: string)
{
	for (i := 0; i < len a; i++)
		cardlib->setarchivename(a[i], name + string i);
}

unarchivearray(a: array of ref Object, name: string)
{
	for (i := 0; i < len a; i++)
		a[i] = cardlib->getarchiveobj(name + string i);
}
