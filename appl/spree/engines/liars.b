implement Engine;

include "sys.m";
	sys: Sys;
include "draw.m";
include "../spree.m";
	spree: Spree;
	Attributes, Range, Object, Clique, Member, rand: import spree;

MAXPLAYERS: con 32;

clique: ref Clique;

# each member is described by a state machine.
# a member progresses through the following states:
#
# Notplaying
# 	istart			-> Havedice
# 	otherstarts	-> Waiting
# Havedice
# 	declare		-> Waiting
# 	look			-> Looking
# Looking
# 	expose		-> Looking
# 	unexpose		-> Looking
# 	declare		-> Waiting
# 	roll			-> Rolled
# Rolled
# 	expose		-> Rolled
# 	unexpose		-> Rolled
# 	declare		-> Waiting
# Waiting
# 	queried		-> Queried
# 	lost			-> Havedice
# Queried
# 	reject,win		-> Waiting
# 	reject,lose	-> Havedice
# 	accept		-> Havedice


plate, cup, space, members: ref Object;
dice := array[5] of ref Object;

declared: int;

# member states
Notplaying, Havedice, Looking, Rolled, Waiting, Queried: con iota;

# info on a particular member
Info: adt {
	state:	int;
	id:		int;
	member:	ref Object;
	action:	ref Object;
};

info := array[MAXPLAYERS] of ref Info;
plorder := array[MAXPLAYERS] of int;	# map member id to their place around the table
nplaying := 0;
nmembers := 0;
turn := 0;

clienttype(): string
{
	return "none";
}

init(g: ref Clique, srvmod: Spree): string
{
	sys = load Sys Sys->PATH;
	clique = g;
	spree = srvmod;

	plate = clique.newobject(nil, ~0, "plate");
	cup = clique.newobject(plate, 0, "cup");
	space = clique.newobject(plate, ~0, "space");
	members = clique.newobject(nil, ~0, "members");

	for (i := 0; i < len dice; i++) {
		dice[i] = clique.newobject(cup, ~0, "die");
		dice[i].setattr("number", string rand(6), ~0);
	}

	return nil;
}

join(member: ref Member): string
{
	check();
	pmask := 1 << member.id;

	ord := nmembers++;
	inf := info[ord] = ref Info;
	inf.state = -1;
	inf.id = member.id;
	inf.action = clique.newobject(nil, pmask, "actions" + string member.id);
	plorder[member.id] = ord;
	setstate(ord, Notplaying);
	check();
	return nil;
}
	
leave(member: ref Member)
{
	check();

	ord := plorder[member.id];
	state := info[ord].state;
	info[ord] = nil;
	for (i := 0; i < nmembers; i++)
		if (i != ord)
			setstate(i, Notplaying);
	nmembers--;
	nplaying = 0;
	clique.action("say member " + string ord + " has left. the clique stops.", nil, nil, ~0);
	check();
}

currmember: ref Member;
currcmd: string;
command(member: ref Member, cmd: string): string
{
	check();
	e := ref Sys->Exception;
	if (sys->rescue("parse:*", e) == Sys->EXCEPTION) {
		sys->rescued(Sys->ONCE, nil);
		check();
		currmember = nil;
		currcmd = nil;
		return e.name[6:];
	}
	currmember = member;
	currcmd = cmd;
	(nlines, lines) := sys->tokenize(cmd, "\n");
	assert(nlines > 0, "unknown command");
	(n, toks) := sys->tokenize(hd lines, " ");
	assert(n > 0, "unknown command");
	pmask := 1 << member.id;
	ord := plorder[member.id];
	state := info[ord].state;
	case hd toks {
	"say" or
	"show" or
	"showme" =>
		case hd toks {
		"say" =>
			clique.action("say member " + string member.id + ": '" + (hd lines)[4:] + "'", nil, nil, ~0);
		"show" =>			# show [memberid]
			p: ref Member = nil;
			if (n == 2) {
				memberid := int hd tl toks;
				p = clique.member(memberid);
				assert(p != nil, "bad memberid");
			}
			clique.show(p);
		"showme" =>
			clique.show(member);
		}
		currmember = nil;
		currcmd = nil;
		return nil;
	}
	case state {
	Notplaying =>
		case hd toks {
		"start" =>
			assert(nplaying == 0, "clique is in progress");
			assert(nmembers > 1, "need at least two members");
			newinfo := array[len info] of ref Info;
			members.deletechildren((0, len members.children));
			j := 0;
			for (i := 0; i < len info; i++)
				if (info[i] != nil)
					newinfo[j++] = info[i];
			info = newinfo;
			nplaying = nmembers;
			for (i = 0; i < nplaying; i++) {
				info[i].member = clique.newobject(members, ~0, nil);
				info[i].member.setattr("id", string info[i].id, ~0);
			}
			turn = rand(nplaying);
			start();
		* =>
			assert(0, "you are not playing");
		}
	Havedice =>
		case hd toks {
		"declare" =>
			# declare hand
			declare(ord, tl toks);
		"look" =>
			cup.setattr("raised", "1", ~0);
			cup.setvisibility(pmask);
			setstate(ord, Looking);
		* =>
			assert(0, "bad command");
		}
	Looking =>
		case hd toks {
		"expose" or
		"unexpose" =>
			expose(n, toks);
		"declare" =>
			declare(ord, tl toks);
		"roll" =>
			# roll index...
			# XXX should be able to roll in the open too
			for (toks = tl toks; toks != nil; toks = tl toks) {
				index := int hd toks;
				checkrange((index, index), cup);
				cup.children[index].setattr("number", string rand(6), ~0);
			}
			setstate(ord, Rolled);
		* =>
			assert(0, "bad command");
		}
	Rolled =>
		case hd toks {
		"expose" or
		"unexpose" =>
			expose(n, toks);
		"declare" =>
			declare(ord, tl toks);
		* =>
			assert(0, "bad command");
		}
	Waiting =>
		assert(0, "not your turn");
	Queried =>
		case hd toks {
		"reject" =>
			# lift the cup!
			cup.transfer((0, len cup.children), space, len space.children);
			assert(len space.children == 5, "lost a die somewhere!");
			dvals := array[5] of int;
			for (i := 0; i < 5; i++)
				dvals[i] = int space.children[i].getattr("number");
			actval := value(dvals);
			if (actval >= declared) {
				# declaration was correct; rejector loses
				clique.action("say member " + string ord + " loses.", nil, nil, ~0);
				turn = ord;
				start();
			} else {
				# liar caught out. rejector wins.
				clique.action("say member " + string turn + " was lying...", nil, nil, ~0);
				start();
			}
		"accept" =>
			# dice accepted, turn moves on
			# XXX should allow for anticlockwise play
			newturn := (turn + 1) % nplaying;
			plate.setattr("owner", string newturn, ~0);
			setstate(ord, Havedice);
			setstate(turn, Waiting);
		}
	}
	check();
	currmember = nil;
	currcmd = nil;
	return nil;
}

expose(n: int, toks: list of string)
{
	# (un)expose index
	assert(n == 2, Eusage);
	(src, dest) := (cup, space);
	if (hd toks == "unexpose")
		(src, dest) = (space, cup);
	index := int hd tl toks;
	checkrange((index, index+1), cup);
	src.transfer((index, index+1), dest, len dest.children);
}

start()
{
	clique.action("start", nil, nil, ~0);
	space.transfer((0, len space.children), cup, len cup.children);
	cup.setvisibility(0);
	for (i := 0; i < len dice; i++)
		dice[i].setattr("number", string rand(6), ~0);

	plate.setattr("owner", string turn, ~0);
	for (i = 0; i < nplaying; i++) {
		if (i == turn)
			setstate(i, Havedice);
		else
			setstate(i, Waiting);
	}
	declared = 0;
}

declare(ord: int, toks: list of string)
{
	cup.setvisibility(0);
	assert(len toks == 1 && len hd toks == 5, "bad declaration");
	d := hd toks;
	v := array[5] of {* => 0};
	for (i := 0; i < 5; i++) {
		v[i] = (hd toks)[i] - '0';
		assert(v[i] >= 0 && v[i] <= 5, "bad declaration");
	}
	newval := value(v);
	assert(newval > declared, "declaration not high enough");
	declared = newval;

	setstate(turn, Waiting);
	setstate((turn + 1) % nplaying, Queried);
}

# check that range is valid for object's children
checkrange(r: Range, o: ref Object)
{
	assert(r.start >= 0 && r.start < len o.children &&
			r.end >= r.start && r.end >= 0 &&
			r.end <= len o.children,
			"index out of range");
}

setstate(ord: int, state: int)
{
	poss: string;
	case state {
	Notplaying =>
		poss = "start";
	Havedice =>
		poss = "declare look";
	Looking =>
		poss = "expose unexpose declare roll";
	Rolled =>
		poss = "expose unexpose declare";
	Waiting =>
		poss = "";
	Queried =>
		poss = "accept reject";
	* =>
		sys->print("liarclique: unknown state %d, member %d\n", state, ord);
		sys->raise("panic");
	}
	info[ord].action.setattr("actions", poss, 1<<info[ord].id);
	info[ord].state = state;
}

obj(ext: int): ref Object
{
	assert((o := currmember.obj(ext)) != nil, "bad object");
	return o;
}

Eusage: con "bad command usage";

assert(b: int, err: string)
{
	if (b == 0) {
		sys->print("cardclique: error '%s' on %s", err, currcmd);
		sys->raise("parse:" + err);
	}
}

checkobj(o: ref Object, what: string)
{
	if (o != nil && o.id == -1) {
		clique.show(currmember);
		sys->print("object %d has been deleted unexpectedly (%s)\n", o.id, what);
		sys->raise("panic");
	}
}

check()
{
}

NOTHING, PAIR, TWOPAIRS, THREES, LOWSTRAIGHT,
FULLHOUSE, HIGHSTRAIGHT, FOURS, FIVES: con iota;

what := array[] of {
NOTHING => "nothing",
PAIR => "pair",
TWOPAIRS => "twopairs",
THREES => "threes",
LOWSTRAIGHT => "lowstraight",
FULLHOUSE => "fullhouse",
HIGHSTRAIGHT => "highstraight",
FOURS => "fours",
FIVES => "fives"
};
	
same(dice: array of int): int
{
	x := dice[0];
	for (i := 0; i < len dice; i++)
		if (dice[i] != x)
			return 0;
	return 1;
}

val(hi, lo: int): int
{
	return hi * 100000 + lo;
}

D: con 10;

value(dice: array of int): int
{
	mergesort(dice, array[5] of int);

	for (i := 0; i < 5; i++)
		sys->print("%d ", dice[i]);
	sys->print("\n");

	# five of a kind
	x := dice[0];
	if (same(dice))
		return val(FIVES, dice[0]);

	# four of a kind
	if (same(dice[1:]))
		return val(FOURS, dice[0] + dice[1]*D);
	if (same(dice[0:4]))
		return val(FOURS, dice[4] + dice[0]*D);

	# high straight
	if (dice[0] == 1 && dice[1] == 2 && dice[2] == 3 &&
			dice[3] == 4 && dice[4] == 5)
		return val(HIGHSTRAIGHT, 0);

	# full house
	if (same(dice[0:3]) && same(dice[3:5]))
		return val(FULLHOUSE, dice[0]*D + dice[4]);
	if (same(dice[0:2]) && same(dice[2:5]))
		return val(FULLHOUSE, dice[4]*D + dice[0]);

	# low straight
	if (dice[0] == 0 && dice[1] == 1 && dice[2] == 2 &&
			dice[3] == 3 && dice[4] == 4)
		return val(LOWSTRAIGHT, 0);
	# three of a kind
	if (same(dice[0:3]))
		return val(THREES, dice[3] + dice[4]*D + dice[0]*D*D);
	if (same(dice[1:4]))
		return val(THREES, dice[0] + dice[4]*D + dice[1]*D*D);
	if (same(dice[2:5]))
		return val(THREES, dice[0] + dice[1]*D + dice[2]*D*D);

	for (i = 0; i < 4; i++)
		if (same(dice[i:i+2]))
			break;
	case i {
	4 =>
		return val(NOTHING, dice[0] + dice[1]*D + dice[2]*D*D +
				dice[3]*D*D*D + dice[4]*D*D*D*D);
	3 =>
		return val(PAIR, dice[0] + dice[1]*D + dice[2]*D*D + dice[3]*D*D*D);
	2 =>
		return val(PAIR, dice[0] + dice[1]*D + dice[4]*D*D + dice[2]*D*D*D);
	}
	h := array[5] of int;
	h[0:] = dice;
	if (i == 1)
		(h[0], h[2]) = (h[2], h[0]);
	# pair is in first two dice
	if (same(h[2:4]))
		return val(TWOPAIRS, h[4] + h[2]*D + h[0]*D*D);
	if (same(h[3:5]))
		return val(TWOPAIRS, h[2] + h[0]*D + h[4]*D*D);
	return val(PAIR, dice[2] + dice[3]*D + dice[4]*D*D + dice[0]*D*D*D);
}

mergesort(a, b: array of int)
{
	r := len a;
	if (r > 1) {
		m := (r-1)/2 + 1;
		mergesort(a[0:m], b[0:m]);
		mergesort(a[m:], b[m:]);
		b[0:] = a;
		for ((i, j, k) := (0, m, 0); i < m && j < r; k++) {
			if (b[i] > b[j])
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
