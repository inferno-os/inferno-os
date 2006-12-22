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
	Selection, Cmember, Card: import cardlib;
	getcard: import cardlib;
	dTOP, dRIGHT, dLEFT, oRIGHT, oDOWN,
	aCENTRERIGHT, aCENTRELEFT, aUPPERRIGHT, aUPPERCENTRE,
	EXPAND, FILLX, FILLY, Stackspec: import Cardlib;
include "../gather.m";

clique: ref Clique;

open: array of ref Object;		# [10]
deck: ref Object;
discard: ref Object;
dealbutton: ref Object;

CLICK, MORECARDS: con iota;

Openspec := Stackspec(
	"display",		# style
	19,			# maxcards
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
	cardlib->archivearray(open, "open");
	cardlib->setarchivename(deck, "deck");
	cardlib->setarchivename(discard, "discard");
	cardlib->setarchivename(dealbutton, "dealbutton");
}

start(members: array of ref Member, archived: int)
{
	cardlib->init(spree, clique);
	if (archived) {
		archiveobj := cardlib->unarchive();
		allow->unarchive(archiveobj);
		open = cardlib->getarchivearray("open");
		discard = cardlib->getarchiveobj("discard");
		deck = cardlib->getarchiveobj("deck");
		dealbutton = cardlib->getarchiveobj("dealbutton");
	} else {
		p := members[0];
		Cmember.join(p, -1).layout.lay.setvisibility(All);
		startclique();
		allow->add(CLICK, p, "click %o %d");
		allow->add(MORECARDS, p, "morecards");
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
			"open" =>
				select(cp, stack, (idx, nc));
			* =>
				return "you can't move cards from there";
			}
		} else {
			from := sel.stack;
			case stype {
			"open" =>
				c := getcard(sel.stack.children[sel.r.start]);
				n := c.number + 1;
				for (i := sel.r.start; i < sel.r.end; i++) {
					c2 := getcard(sel.stack.children[i]);
					if (c2.face == 0)
						return "cannot move face down cards";
					if (c2.number != n - 1)
						return "bad number sequence";
					n = c2.number;
				}
				if (nc != 0) {
					c2 := getcard(stack.children[nc - 1]);
					if (c2.number != c.number + 1)
						return "descending, only";
				}
				srcstack := sel.stack;
				sel.transfer(stack, -1);
				turntop(srcstack);

				nc = len stack.children;
				if (nc >= 13) {
					c = getcard(stack.children[nc - 1]);
					suit := c.suit;
					for (i = 0; i < 13; i++) {
						c = getcard(stack.children[nc - i - 1]);
						if (c.suit != suit || c.number != i)
							break;
					}
					if (i == 13) {
						stack.transfer((nc - 13, nc), discard, -1);
						turntop(stack);
					}
				}
			* =>
				return "can't move there";
			}
		}
	MORECARDS =>
		for (i := 0; i < 10; i++)
			if (len open[i].children == 0)
				return "spaces must be filled before redeal";
		for (i = 0; i < 10; i++) {
			if (len deck.children == 0)
				break;
			cp.sel.set(nil);
			cardlib->setface(deck.children[0], 1);
			deck.transfer((0, 1), open[i], -1);
		}
		setdealbuttontext();
	}
	return nil;
}

setdealbuttontext()
{
	dealbutton.setattr("text", sys->sprint("deal more (%d left)", len deck.children), All);
}

turntop(stack: ref Object)
{
	if (len stack.children > 0)
		cardlib->setface(stack.children[len stack.children - 1], 1);
}

startclique()
{
	addlayobj, addlayframe: import cardlib;
	open = array[10] of {* => newstack(nil, Openspec, "open", nil)};
	deck = clique.newobject(nil, All, "stack");
	discard = clique.newobject(nil, All, "stack");
	cardlib->makecards(deck, (0, 13), "0");
	cardlib->makecards(deck, (0, 13), "1");
	addlayframe("arena", nil, nil, dTOP|EXPAND|FILLX|FILLY, dTOP);
	addlayframe("top", "arena", nil, dTOP|EXPAND|FILLX|FILLY, dTOP);

	for (i := 0; i < 10; i++)
		addlayobj(nil, "top", nil, dLEFT|oDOWN|EXPAND|aUPPERCENTRE, open[i]);
	addlayframe("bot", "arena", nil, dTOP, dTOP);
	dealbutton = newbutton("morecards", "deal more");
	addlayobj(nil, "bot", nil, dLEFT, dealbutton);
	deal();
	setdealbuttontext();
}

deal()
{
	cardlib->shuffle(deck);
	for (i := 0; i < 10; i++) {
		deck.transfer((0, 4), open[i], 0);
		turntop(open[i]);
	}
}

newstack(parent: ref Object, spec: Stackspec, stype, title: string): ref Object
{
	stack := cardlib->newstack(parent, nil, spec);
	stack.setattr("type", stype, None);
	stack.setattr("actions", "click", All);
	stack.setattr("title", title, All);
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

newbutton(cmd, text: string): ref Object
{
	but := clique.newobject(nil, All, "widget button");
	but.setattr("command", cmd, All);
	but.setattr("text", text, All);
	return but;
}

