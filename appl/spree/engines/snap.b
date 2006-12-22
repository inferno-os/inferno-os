implement Engine;

include "sys.m";
	sys: Sys;
include "draw.m";
include "../spree.m";
	spree: Spree;
	Attributes, Range, Object, Clique, Member, rand: import spree;
include "allow.m";
	allow: Allow;
include "cardlib.m";
	cardlib: Cardlib;
	publicstack: import cardlib;
	VERT, HORIZ, TOP, BOTTOM, LEFT, RIGHT, Stackspec: import Cardlib;

clique: ref Clique;
PLAY, START, SAY, SNAP: con iota;

started := 0;

buttons: ref Object;
scores: ref Object;
deck: ref Object;

HAND, PILE: con iota;

hands := array[2] of ref Object;
piles := array[2] of ref Object;

publicspec: array of Stackspec;

privatespec := array[] of {
	HAND => Stackspec(Cardlib->sPILE,
			52,
			0,
			"hand",
			HORIZ,
			BOTTOM),
	PILE => Stackspec(Cardlib->sPILE,
			52,
			0,
			"pile",
			HORIZ,
			TOP),
};

oneplayed := 0;			# true if only one member's put down a card so far

MINPLAYERS: con 2;
MAXPLAYERS: con 2;

clienttype(): string
{
	return "cards";
}

init(g: ref Clique, srvmod: Spree): string
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
	allow->add(SAY, nil, "say &");

	cardlib = load Cardlib Cardlib->PATH;
	if (cardlib == nil) {
		sys->print("whist: cannot load %s: %r\n", Cardlib->PATH);
		return "bad module";
	}

	cardlib->init(clique, spree);
	deck = clique.newobject(nil, ~0, "stack");
	cardlib->makepack(deck, (0, 52), 1);
	cardlib->shuffle(deck);
	buttons = clique.newobject(nil, ~0, "buttons");
	scores = clique.newobject(nil, ~0, "scoretable");

	return nil;
}

join(p: ref Member): string
{
	sys->print("%s(%d) joining\n", p.name(), p.id);
	if (!started && cardlib->nmembers() < MAXPLAYERS) {
		(nil, err) := cardlib->join(p, -1);
		if (err == nil) {
			if (cardlib->nmembers() == MINPLAYERS) {
				mkbutton("Start", "start");
				allow->add(START, nil, "start");
			}
		} else
			sys->print("error on join: %s\n", err);
	}
	return nil;
}
		
leave(p: ref Member)
{
	cardlib->leave(p);
	started == 0;
	if (cardlib->nmembers() < MINPLAYERS) {
		buttons.deletechildren((0, len buttons.children));
		allow->del(START, nil);
	}
}

command(p: ref Member, cmd: string): string
{
	e := ref Sys->Exception;
	if (sys->rescue("parse:*", e) == Sys->EXCEPTION) {
		sys->rescued(Sys->ONCE, nil);
		return e.name[6:];
	}
	(err, tag, toks) := allow->action(p, cmd);
	if (err != nil)
		return err;
	case tag {
	START =>
		buttons.deletechildren((0, len buttons.children));
		allow->del(START, nil);
		allow->add(SNAP, nil, "snap");
		mkbutton("Snap!", "snap");
		cardlib->startclique(publicspec, privatespec);
		for (i := 0; i < 2; i++) {
			hands[i] = cardlib->info(i).stacks[HAND];
			piles[i] = cardlib->info(i).stacks[PILE];
		}
		deck.transfer((0, 26), hands[0], 0);
		deck.transfer((0, 26), hands[1], 0);
		canplay(0);
		canplay(1);

	PLAY =>
		# click index
		ord := cardlib->order(p);
		inf := cardlib->info(ord);

		hand := hands[ord];
		pile := piles[ord];
		hand.transfer((len hand.children - 1, len hand.children), pile, len pile.children);
		cardlib->setface(pile.children[len pile.children - 1], 1);
		cantplay(ord);
		oneplayed = !oneplayed;
		if (!oneplayed || len hands[!ord].children == 0) {
			for (i := 0; i < 2; i++)
				if (len hands[i].children > 0)
					canplay(i);
		}
	SNAP =>
		# snap
		ord := cardlib->order(p);
		inf := cardlib->info(ord);
		if (oneplayed)		# XXX allow for case where one person has no cards.
			return "must wait for two cards to be put down";
		if (len piles[0].children == 0 || len piles[1].children == 0)
			return "no cards";
		c0 := cardlib->getcard(piles[0].children[len piles[0].children - 1]);
		c1 := cardlib->getcard(piles[1].children[len piles[0].children - 1]);
		if (c0.number != c1.number) {
			remark(p.name() + " said snap wrongly!");
			return "cards must be the same";
		} else {
			transferall(piles[!ord], piles[ord], len piles[ord].children);
			flipstack(piles[ord]);
			transferall(piles[ord], hands[ord], 0);
			if (len hands[!ord].children == 0)
				remark(p.name() + " has won!");
			oneplayed = 0;
			for (i := 0; i < 2; i++)
				if (len hands[i].children > 0)
					canplay(i);
				else
					cantplay(i);
		}
	SAY =>
		clique.action("say member " + string p.id + ": '" + joinwords(tl toks) + "'", nil, nil, ~0);
	}
	return nil;
}

transferall(stack, into: ref Object, idx: int)
{
	stack.transfer((0, len stack.children), into, idx);
}

flipstack(stack: ref Object)
{
	for (i := 0; i < len stack.children; i++) {
		card := stack.children[i];
		cardlib->setface(card, ! int card.getattr("face"));
	}
}

joinwords(v: list of string): string
{
	if (v == nil)
		return nil;
	s := hd v;
	for (v = tl v; v != nil; v = tl v)
		s += " " + hd v;
	return s;
}

canplay(ord: int)
{
	inf := cardlib->info(ord);
	allow->del(PLAY, inf.p);
	allow->add(PLAY, inf.p, "click %d");
	inf.stacks[HAND].setattr("actions", "click", 1<<inf.p.id);
}

cantplay(ord: int)
{
	inf := cardlib->info(ord);
	allow->del(PLAY, inf.p);
	inf.stacks[HAND].setattr("actions", nil, 1<<inf.p.id);
}

member(ord: int): ref Member
{
	return cardlib->info(ord).p;
}

remark(s: string)
{
	clique.action("remark " + s, nil, nil, ~0);
}

mkbutton(text, cmd: string): ref Object
{
	but := clique.newobject(buttons, ~0, "button");
	but.setattr("text", text, ~0);
	but.setattr("command", cmd, ~0);
	return but;
}
