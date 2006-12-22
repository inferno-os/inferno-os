implement Tricks;
include "sys.m";
	sys: Sys;
include "draw.m";
include "sets.m";
	sets: Sets;
	Set, All, None: import sets;
include "../spree.m";
	spree: Spree;
	Attributes, Range, Object, Clique, Member: import spree;
include "cardlib.m";
	cardlib: Cardlib;
	Card, getcard: import cardlib;
include "tricks.m";

clique: ref Clique;

init(mod: Spree, g: ref Clique, cardlibmod: Cardlib)
{
	sys = load Sys Sys->PATH;
	sets = load Sets Sets->PATH;
	if (sets == nil)
		panic(sys->sprint("cannot load %s: %r", Sets->PATH));
	clique = g;
	spree = mod;
	cardlib = cardlibmod;
}

defaultrank := array[13] of {12, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11};

# XXX should take a "rank" array so that we can cope with custom
# card ranking
Trick.new(pile: ref Object, trumps: int, hands: array of ref Object, rank: array of int): ref Trick
{
	t := ref Trick;
	t.highcard = t.startcard = Card(-1, -1, -1);
	t.winner = -1;
	t.trumps = trumps;
	t.pile = pile;
	t.hands = hands;
	if (rank == nil)
		rank = defaultrank;
	t.rank = rank;
	return t;
}

Trick.archive(t: self ref Trick, archiveobj: ref Object, name: string)
{
	a := clique.newobject(archiveobj, None, "trick");
	cardlib->setarchivename(a, name);
	a.setattr("trumps", string t.trumps, None);
	a.setattr("winner", string t.winner, None);
	a.setattr("startcard.n", string t.startcard.number, None);
	a.setattr("startcard.suit", string t.startcard.suit, None);
	a.setattr("highcard.n", string t.highcard.number, None);
	a.setattr("highcard.suit", string t.highcard.suit, None);
	cardlib->setarchivename(t.pile, name + ".pile");
	cardlib->archivearray(t.hands, name);
	for (i := 0; i < len t.rank; i++)
		if (t.rank[i] != defaultrank[i])
			break;
	if (i < len t.rank) {
		r := "";
		for (i = 0; i < len t.rank; i++)
			r += " " + string t.rank[i];
		a.setattr("rank", r, None);
	}
}

Trick.unarchive(nil: ref Object, name: string): ref Trick
{
	t := ref Trick;
	a := cardlib->getarchiveobj(name);
	t.trumps = int a.getattr("trumps");
	t.winner = int a.getattr("winner");
	t.startcard.number = int a.getattr("startcard.n");
	t.startcard.suit = int a.getattr("startcard.suit");
	t.highcard.number = int a.getattr("highcard.n");
	t.highcard.suit = int a.getattr("highcard.suit");
	t.pile = cardlib->getarchiveobj(name + ".pile");
	t.hands = cardlib->getarchivearray(name);
	r := a.getattr("rank");
	if (r != nil) {
		(nil, toks) := sys->tokenize(r, " ");
		t.rank = array[len toks] of int;
		i := 0;
		for (; toks != nil; toks = tl toks)
			t.rank[i++] = int hd toks;
	} else
		t.rank = defaultrank;
	return t;
}

Trick.play(t: self ref Trick, ord, idx: int): string
{
	stack := t.hands[ord];
	if (idx < 0 || idx >= len stack.children)
		return "invalid card to play";

	c := getcard(stack.children[idx]);
	c.number = t.rank[c.number];
	if (len t.pile.children == 0) {
		t.winner = ord;
		t.startcard = t.highcard = c;
	} else {
		if (c.suit != t.startcard.suit) {
			if (containssuit(stack, t.startcard.suit))
				return "you must play the suit that was led";
			if (c.suit == t.trumps &&
					(t.highcard.suit != t.trumps ||
					c.number > t.highcard.number)) {
				t.highcard = c;
				t.winner = ord;
			}
		} else if (c.suit == t.highcard.suit && c.number > t.highcard.number) {
			t.highcard = c;
			t.winner = ord;
		}
	}

	stack.transfer((idx, idx + 1), t.pile, len t.pile.children);
	stack.setattr("n", string (int stack.getattr("n") - 1), All);
	return nil;
}

containssuit(stack: ref Object, suit: int): int
{
	ch := stack.children;
	n := len ch;
	for (i := 0; i < n; i++)
		if (getcard(ch[i]).suit == suit)
			return 1;
	return 0;
}

panic(e: string)
{
	sys->fprint(sys->fildes(2), "tricks panic: %s\n", e);
	raise "panic";
}
