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
	Selection, Cmember: import cardlib;
	dTOP, dLEFT, oRIGHT, EXPAND, FILLX, FILLY, Stackspec: import Cardlib;
include "tricks.m";
	tricks: Tricks;
	Trick: import tricks;
include "../gather.m";

clique: ref Clique;
CLICK, SAY: con iota;

scores: ref Object;
deck, pile: ref Object;
hands, taken: array of ref Object;
leader, turn: ref Cmember;
trick: ref Trick;

Trickpilespec := Stackspec(
	"display",		# style
	4,			# maxcards
	0,			# conceal
	"trick pile"	# title
);

Handspec := Stackspec(
	"display",
	13,
	1,
	""
);

Takenspec := Stackspec(
	"pile",
	52,
	0,
	"tricks"
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
		sys->print("whist: cannot load %s: %r\n", Allow->PATH);
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
		sys->print("whist: cannot load %s: %r\n", Cardlib->PATH);
		return "bad module";
	}

	tricks = load Tricks Tricks->PATH;
	if (tricks == nil) {
		sys->print("hearts: cannot load %s: %r\n", Tricks->PATH);
		return "bad module";
	}

	return nil;
}

maxmembers(): int
{
	return 4;
}

readfile(nil: int, nil: big, nil: int): array of byte
{
	return nil;
}

propose(members: array of string): string
{
	if (len members < 2)
		return "need at least two members";
	if (len members > 4)
		return "too many members";
	return nil;
}

archive()
{
	archiveobj := cardlib->archive();
	allow->archive(archiveobj);

	cardlib->setarchivename(scores, "scores");
	cardlib->setarchivename(deck, "deck");
	cardlib->setarchivename(pile, "pile");
	cardlib->archivearray(hands, "hands");
	cardlib->archivearray(taken, "taken");
	if (leader != nil)
		archiveobj.setattr("leader", string leader.ord, None);
	if (turn != nil)
		archiveobj.setattr("turn", string turn.ord, None);
	trick.archive(archiveobj, "trick");
}

start(members: array of ref Member, archived: int)
{
	cardlib->init(spree, clique);
	tricks->init(spree, clique, cardlib);
	if (archived) {
		archiveobj := cardlib->unarchive();
		allow->unarchive(archiveobj);

		scores = cardlib->getarchiveobj("scores");
		deck = cardlib->getarchiveobj("deck");
		pile = cardlib->getarchiveobj("pile");
		hands = cardlib->getarchivearray("hands");
		taken = cardlib->getarchivearray("taken");

		o := archiveobj.getattr("leader");
		if (o != nil)
			leader = Cmember.index(int o);
		o = archiveobj.getattr("turn");
		if (o != nil)
			turn = Cmember.index(int o);
		trick = Trick.unarchive(archiveobj, "trick");
	} else {
		pset := None;
		for (i := 0; i < len members; i++) {
			Cmember.join(members[i], i);
			pset = pset.add(members[i].id);
		}
		# member 0 layout visible to member 0 and everyone else but other member.
		# could be All.del(members[1].id) but doing it this way extends to many-member cliques.
		Cmember.index(0).layout.lay.setvisibility(All.X(A&~B, pset).add(members[0].id));
		deck = clique.newobject(nil, All, "stack");
		cardlib->makecards(deck, (0, 13), nil);
		cardlib->shuffle(deck);
		scores = clique.newobject(nil, All, "scoretable");
		startclique();
		n := cardlib->nmembers();
		leader = Cmember.index(rand(n));
		starthand();
		titles := "";
		for (i = 0; i < n; i++)
			titles += members[i].name + " ";
		clique.newobject(scores, All, "score").setattr("score", titles, All);
	}
}

command(p: ref Member, cmd: string): string
{
	(err, tag, toks) := allow->action(p, cmd);
	if (err != nil)
		return err;
	cp := Cmember.find(p);
	if (cp == nil)
		return "you're only watching";
	case tag {
	CLICK =>
		# click stackid index
		stack := p.obj(int hd tl toks);
		if (stack != trick.hands[cp.ord])
			return "not yours";
		err = trick.play(cp.ord, int hd tl tl toks);
		if (err != nil)
			return err;

		turn = turn.next(1);
		if (turn == leader) {			# come full circle
			winner := Cmember.index(trick.winner);
			remark(sys->sprint("%s won the trick", winner.p.name));
			cardlib->discard(pile, taken[winner.ord], 0);
			nmembers := cardlib->nmembers();
			taken[winner.ord].setattr("title",
				string (len taken[winner.ord].children / nmembers) +
				" tricks", All);
			o := winner.obj;
			trick = nil;
			s := "";
			for (i := 0; i < nmembers; i++) {
				if (i == winner.ord)
					s += "1 ";
				else
					s += "0 ";
			}
			clique.newobject(scores, All, "score").setattr("score", s, All);
			if (len hands[winner.ord].children > 0) {
				leader = turn = winner;
				trick = Trick.new(pile, -1, hands, nil);
			} else {
				remark("one round down, some to go");
				leader = turn  = nil;		# XXX this round over
			}
		}
		canplay(turn);
	SAY =>
		clique.action("say member " + string p.id + ": '" + joinwords(tl toks) + "'", nil, nil, All);
	}
	return nil;
}

startclique()
{
	entry := clique.newobject(nil, All, "widget entry");
	entry.setattr("command", "say", All);
	cardlib->addlayobj("entry", nil, nil, dTOP|FILLX, entry);
	cardlib->addlayframe("arena", nil, nil, dTOP|EXPAND|FILLX|FILLY, dTOP);
	cardlib->maketable("arena");

	pile = cardlib->newstack(nil, nil, Trickpilespec);
	cardlib->addlayobj(nil, "public", nil, dTOP|oRIGHT, pile);
	n := cardlib->nmembers();
	hands = array[n] of ref Object;
	taken = array[n] of ref Object;
	tt := clique.newobject(nil, All, "widget menu");
	tt.setattr("text", "hello", All);
	for (ml := "one" :: "two" :: "three" :: nil; ml != nil; ml = tl ml) {
		o := clique.newobject(tt, All, "menuentry");
		o.setattr("text", hd ml, All);
		o.setattr("command", hd ml, All);
	}
	for (i := 0; i < n; i++) {
		cp := Cmember.index(i);
		hands[i] = cardlib->newstack(cp.obj, cp.p, Handspec);
		taken[i] = cardlib->newstack(cp.obj, cp.p, Takenspec);
		p := "p" + string i;
		cardlib->addlayframe(p + ".f", p, nil, dLEFT|oRIGHT, dTOP);
		cardlib->addlayobj(nil, p + ".f", cp.layout, dTOP, tt);
		cardlib->addlayobj(nil, p + ".f", nil, dTOP, hands[i]);
		cardlib->addlayobj(nil, "p" + string i, nil, dLEFT|oRIGHT, taken[i]);
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

suitrank := array[] of {
	Cardlib->CLUBS => 0,
	Cardlib->DIAMONDS => 1,
	Cardlib->SPADES => 2,
	Cardlib->HEARTS => 3
};

starthand()
{
	cardlib->deal(deck, 13, hands, 0);
	for (i := 0; i < len hands; i++)
		cardlib->sort(hands[i], nil, suitrank);
	trick = Trick.new(pile, -1, hands, nil);
	turn = leader;
	canplay(turn);
}

canplay(cp: ref Cmember)
{
	allow->del(CLICK, nil);
	for (i := 0; i < cardlib->nmembers(); i++) {
		ccp := Cmember.index(i);
		v := None.add(ccp.p.id);
		ccp.obj.setattr("status", nil, v);
		hands[i].setattr("actions", nil, v);
	}
	if (cp != nil && cp.ord != -1) {
		allow->add(CLICK, cp.p, "click %d %d");
		v := None.add(cp.p.id);
		cp.obj.setattr("status", "Your turn", v);
		hands[cp.ord].setattr("actions", "click", v);
	}
}

remark(s: string)
{
	clique.action("remark " + s, nil, nil, All);
}
