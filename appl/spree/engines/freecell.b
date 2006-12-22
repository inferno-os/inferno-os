implement Gatherengine;

include "sys.m";
	sys: Sys;
include "draw.m";
include "sets.m";
	sets: Sets;
	Set, set, A, B, All, None: import sets;
include "../spree.m";
	spree: Spree;
	Attributes, Range, Object, Clique, Member, rand: import spree;
include "allow.m";
	allow: Allow;
include "cardlib.m";
	cardlib: Cardlib;
	Selection, Cmember, Card: import cardlib;
	getcard: import cardlib;
	dTOP, dRIGHT, dLEFT, oRIGHT, oDOWN,
	aCENTRERIGHT, aCENTRELEFT, aUPPERRIGHT,
	EXPAND, FILLX, FILLY, Stackspec: import Cardlib;
include "../gather.m";

clique: ref Clique;

open: array of ref Object;		# [8]
cells: array of ref Object;		# [4]
acepiles: array of ref Object;	# [4]
txpiles: array of ref Object;	# [len open + len cells]
deck: ref Object;

fnames := array[] of {
"qua",
"quack",
"quackery",
"quad",
"quadrangle",
"quadrangular",
"quadrant",
"quadratic",
"quadrature",
"quadrennial",
};
dir(name: string, perm: int, owner: string): Sys->Dir
{
	d := Sys->zerodir;
	d.name = name;
	d.uid = owner;
	d.gid = owner;
	d.qid.qtype = (perm >> 24) & 16rff;
	d.mode = perm;
	# d.atime = now;
	# d.mtime = now;
	return d;
}


suitsout := array[4] of {* => -1};

mainmember: ref Cmember;

CLICK: con iota;

Openspec := Stackspec(
	"display",		# style
	19,			# maxcards
	0,			# conceal
	""			# title
);

Pilespec := Stackspec(
	"pile",		# style
	19,			# maxcards
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

maxmembers(): int
{
	return 1;
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
	sets = load Sets Sets->PATH;
	if (sets == nil) {
		sys->print("whist: cannot load %s: %r\n", Sets->PATH);
		return "bad module";
	}
	cardlib = load Cardlib Cardlib->PATH;
	if (cardlib == nil) {
		sys->print("whist: cannot load %s: %r\n", Cardlib->PATH);
		return "bad module";
	}
	cardlib->init(spree, clique);
	g.fcreate(0, -1, dir("data", 8r555|Sys->DMDIR, "spree"));
	for(i := 0; i < len fnames; i++)
		g.fcreate(i + 1, 0, dir(fnames[i], 8r444, "arble"));
	return nil;
}

propose(members: array of string): string
{
	if (len members != 1)
		return "one member only";
	return nil;
}

start(members: array of ref Member, archived: int)
{
sys->print("freecell: starting\n");
	if (archived) {
		archiveobj := cardlib->unarchive();
		open = cardlib->getarchivearray("open");
		cells = cardlib->getarchivearray("cells");
		acepiles = cardlib->getarchivearray("acepiles");
		txpiles = cardlib->getarchivearray("txpiles");
		deck = cardlib->getarchiveobj("deck");
		for (i := 0; i < len suitsout; i++)
			suitsout[i] = int archiveobj.getattr("suitsout" + string i);
		mainmember = Cmember.findid(int archiveobj.getattr("mainmember"));
		allow->unarchive(archiveobj);
		archiveobj.delete();
	} else {
		sys->print("freecell: starting afresh\n");
		mainmember = Cmember.join(members[0], -1);
		mainmember.layout.lay.setvisibility(All);
		startclique();
		movefree();
		allow->add(CLICK, members[0], "click %o %d");
	}
}

readfile(f: int, boffset: big, n: int): array of byte
{
	offset := int boffset;
	f--;
	if (f < 0 || f >= len fnames)
		return nil;
	data := array of byte fnames[f];
	if (offset >= len data)
		return nil;
	if (offset + n > len data)
		n = len data - offset;
	return data[offset:offset + n];
}

archive()
{
	sys->print("freecell: archiving\n");
	archiveobj := cardlib->archive();
	cardlib->archivearray(open, "open");
	cardlib->archivearray(cells, "cells");
	cardlib->archivearray(acepiles, "acepiles");
	cardlib->archivearray(txpiles, "txpiles");
	cardlib->setarchivename(deck, "deck");
	for (i := 0; i < len suitsout; i++)
		archiveobj.setattr("suitsout" + string i, string suitsout[i], None);
	archiveobj.setattr("mainmember", string mainmember.id, None);
	allow->archive(archiveobj);
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
	CLICK =>
		# click stack index
		stack := clique.objects[int hd tl toks];
		nc := len stack.children;
		idx := int hd tl tl toks;
		sel := cp.sel;
		stype := stack.getattr("type");
		if (sel.isempty() || sel.stack == stack) {
			if (idx < 0 || idx >= len stack.children)
				return "invalid index";
			case stype {
			"cell" or
			"open" =>
				select(cp, stack, (idx, nc));
			* =>
				return "you can't move cards from there";
			}
		} else {
			from := sel.stack;
			case stype {
			"acepile" =>
				if (sel.r.end != sel.r.start + 1)
					return "only one card at a time!";
				addtoacepile(sel.stack);
				sel.set(nil);
				movefree();
			"open" =>
				c := getcard(sel.stack.children[sel.r.start]);
				col := !isred(c.suit);
				n := c.number + 1;
				for (i := sel.r.start; i < sel.r.end; i++) {
					c2 := getcard(sel.stack.children[i]);
					if (isred(c2.suit) == col)
						return "bad colour sequence";
					if (c2.number != n - 1)
						return "bad number sequence";
					n = c2.number;
					col = isred(c2.suit);
				}
				if (nc != 0) {
					c2 := getcard(stack.children[nc - 1]);
					if (isred(c2.suit) == isred(c.suit) || c2.number != c.number + 1)
						return "opposite colours, descending, only";
				}
				r := sel.r;
				selstack := sel.stack;
				sel.set(nil);
				fc := freecells(stack);
				if (r.end - r.start - 1 > len fc)
					return "not enough free cells";
				n = 0;
				for (i = r.end - 1; i >= r.start + 1; i--)
					selstack.transfer((i, i + 1), fc[n++], -1);
				selstack.transfer((i, i + 1), stack, -1);
				while (--n >= 0)
					fc[n].transfer((0, 1), stack, -1);
				movefree();
			"cell" =>
				if (sel.r.end - sel.r.start > 1 || nc > 0)
					return "only one card allowed there";
				sel.transfer(stack, -1);
				movefree();
			* =>
				return "can't move there";
			}
		}
	}
	return nil;
}

freecells(dest: ref Object): array of ref Object
{
	fc := array[len txpiles] of ref Object;
	n := 0;
	for (i := 0; i < len txpiles; i++)
		if (len txpiles[i].children == 0 && txpiles[i] != dest)
			fc[n++] = txpiles[i];
	return fc[0:n];
}

# move any cards that can be moved.
movefree()
{
	nmoved := 1;
	while (nmoved > 0) {
		nmoved = 0;
		for (i := 0; i < len txpiles; i++) {
			pile := txpiles[i];
			nc := len pile.children;
			if (nc == 0)
				continue;
			card := getcard(pile.children[nc - 1]);
			if (suitsout[card.suit] != card.number - 1)
				continue;
			# card can be moved; now make sure there's no card out
			# that might be moved onto this card
			for (j := 0; j < len suitsout; j++)
				if (isred(j) != isred(card.suit) && card.number > 1 && suitsout[j] < card.number - 1)
					break;
			if (j == len suitsout) {
				addtoacepile(pile);
				nmoved++;
			}
		}
	}
}

addtoacepile(pile: ref Object)
{
	nc := len pile.children;
	if (nc == 0)
		return;
	card := getcard(pile.children[nc - 1]);
	for (i := 0; i < len acepiles; i++) {
		anc := len acepiles[i].children;
		if (anc == 0) {
			if (card.number == 0)
				break;
			continue;
		}
		acard := getcard(acepiles[i].children[anc - 1]);
		if (acard.suit == card.suit && acard.number == card.number - 1)
			break;
	}
	if (i < len acepiles) {
		pile.transfer((nc - 1, nc), acepiles[i], -1);
		suitsout[card.suit] = card.number;
	}
}

startclique()
{
	addlayobj, addlayframe: import cardlib;

	open = array[8] of {* => newstack(nil, Openspec, "open", nil)};
	acepiles = array[4] of {* => newstack(nil, Untitledpilespec, "acepile", nil)};
	cells = array[4] of {* => newstack(nil, Untitledpilespec, "cell", "cell")};
	for (i := 0; i < len cells; i++)
		cells[i].setattr("showsize", "0", All);

	txpiles = array[12] of ref Object;
	txpiles[0:] = open;
	txpiles[len open:] = cells;
	deck = clique.newobject(nil, All, "stack");

	cardlib->makecards(deck, (0, 13), nil);

	addlayframe("arena", nil, nil, dTOP|EXPAND|FILLX|FILLY, dTOP);
	addlayframe("top", "arena", nil, dTOP|EXPAND, dTOP);
	addlayframe("bot", "arena", nil, dTOP|EXPAND, dTOP);
	for (i = 0; i < 4; i++)
		addlayobj(nil, "top", nil, dRIGHT, acepiles[i]);
	for (i = 0; i < 4; i++)
		addlayobj(nil, "top", nil, dLEFT, cells[i]);
	for (i = 0; i < len open; i++)
		addlayobj(nil, "bot", nil, dLEFT|oDOWN|EXPAND, open[i]);
	deal();
}

deal()
{
	cardlib->shuffle(deck);
	cardlib->deal(deck, 7, open, 0);
}

newstack(parent: ref Object, spec: Stackspec, stype, title: string): ref Object
{
	stack := cardlib->newstack(parent, nil, spec);
	stack.setattr("type", stype, None);
	stack.setattr("actions", "click", All);
	stack.setattr("title", title, All);
	return stack;
}

isred(suit: int): int
{
	return suit == Cardlib->DIAMONDS || suit == Cardlib->HEARTS;
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

#randstate := 1;
#srand(seed: int)
#{
#        randstate = seed;
#}
#
#rand(): int
#{
#	randstate = randstate * 214013 + 2531011;
#	return (randstate >> 16) & 0x7fff;
#}
##From: jimh@MICROSOFT.com (Jim Horne)
##
##I'm happy to share the card shuffle algorithm, but I warn you,
##it does depend on the rand() and srand() function built into MS
##compilers.  The good news is that I believe these work the same
##for all our compilers.
##
##I use cards.dll which has it's own mapping of numbers (0-51) to
##cards.  The following will give you the idea.  Play around with
##this and you'll be able to generate all the cliques.
##
##Go ahead and post the code.  People might as well have fun with it.
##Please keep me posted on anything interesting that comes of it.  
##Thanks.
#
#msdeal(cliquenumber: int): array of array of Card
#{
#	deck := array[52] of Card;
#	for (i := 0; i < len deck; i++)	# put unique card in each deck loc.
#		deck[i] = Card(i % 4, i / 4, 0);
#	wleft := 52;				# cards left to be chosen in shuffle
#	cards := array[8] of {* => array[7] of Card};
#	max := array[8] of {* => 0};
#	srand(cliquenumber);
#	for (i = 0; i < 52; i++)	{
#		j := rand() % wleft;
#		card[i % 8][i / 8] = deck[j];
#		max[i % 8] = i / 8;
#		deck[j] = deck[--wleft];
#	}
#	for (i = 0; i < len cards; i++)
#		cards[i] = cards[i][0:max[i]];
#	return cards;
#}
