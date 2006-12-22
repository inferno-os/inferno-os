implement Allow;
include "sys.m";
	sys: Sys;
include "draw.m";
include "sets.m";
	sets: Sets;
	Set, set, None: import sets;
include "../spree.m";
	spree: Spree;
	Attributes, Range, Object, Clique, Member, rand: import spree;
include "allow.m";

Action: adt {
	tag:		int;
	member:	ref Member;
	action:	string;
};

actions: list of Action;
clique: ref Clique;

init(srvmod: Spree, g: ref Clique)
{
	sys = load Sys Sys->PATH;
	sets = load Sets Sets->PATH;
	(clique, spree) = (g, srvmod);
}

ILLEGALNAME: con "/";	# illegal char in member names, ahem.
archive(archiveobj: ref Object)
{
	i := 0;
	for (al := actions; al != nil; al = tl al) {
		a := hd al;
		pname: string;
		if (a.member != nil)
			pname = a.member.name;
		else
			pname = ILLEGALNAME;
		archiveobj.setattr(
			"allow" + string i++,
			sys->sprint("%d %s %s", a.tag, pname, a.action),
			None
		);
	}
}

unarchive(archiveobj: ref Object)
{
	for (i := 0; (s := archiveobj.getattr("allow" + string i)) != nil; i++) {
		(n, toks) := sys->tokenize(s, " ");
		p: ref Member = nil;
		if (hd tl toks != ILLEGALNAME) {
			# if the member is no longer around, ignore the action. XXX do we still need to do this?
			if ((p = clique.membernamed(hd tl toks)) == nil)
				continue;
		}
		sys->print("allow: adding action %d, %ux, %s\n", int hd toks, p, concat(tl tl toks));
		actions = Action(int hd toks, p, concat(tl tl toks)) :: actions;
	}
}

add(tag: int, member: ref Member, action: string)
{
#	sys->print("allow: add %d, member %ux, action: %s\n", tag, member, action);
	actions = (tag, member, action) :: actions;
}

del(tag: int, member: ref Member)
{
#	sys->print("allow: del %d\n", tag);
	na: list of Action;
	for (a := actions; a != nil; a = tl a) {
		action := hd a;
		if (action.tag == tag && (member == nil || action.member == member))
			continue;
		na = action :: na;
	}
	actions = na;
}

action(member: ref Member, cmd: string): (string, int, list of string)
{
	for (al := actions; al != nil; al = tl al) {
		a := hd al;
		if (a.member == nil || a.member == member) {
			(e, v) := match(member, a.action, cmd);
			if (e != nil || v != nil)
				return (e, a.tag, v);
		}
	}
	return ("you can't do that", -1, nil);
}

match(member: ref Member, pat, action: string): (string, list of string)
{
#	sys->print("allow: matching pat: '%s' against action '%s'\n", pat, action);
	toks: list of string;
	na := len action;
	if (na > 0 && action[na - 1] == '\n')
		na--;

	(i, j) := (0, 0);
	for (;;) {
		for (; i < len pat; i++)
			if (pat[i] != ' ')
				break;
		for (; j < na; j++)
			if (action[j] != ' ')
				break;
		for (i1 := i; i1 < len pat; i1++)
			if (pat[i1] == ' ')
				break;
		for (j1 := j; j1 < na; j1++)
			if (action[j1] == ' ')
				break;
		if (i == i1) {
			if (j == j1)
				break;
			return (nil, nil);
		}
		if (j == j1) {
			if (pat == "&")
				break;
			return (nil, nil);
		}
		pw := pat[i : i1];
		w := action[j : j1];
		case pw[0] {
		'*' =>
			toks = w :: toks;
		'&' =>
			toks = w :: toks;
			pat = "&";
			i1 = 0;
		'%' =>
			(ok, nw) := checkformat(member, pw[1], w);
			if (!ok)
				return ("invalid field value", nil);
			toks = nw :: toks;
		* =>
			if (w != pw)
				return (nil, nil);
			toks = w :: toks;
		}
		(i, j) = (i1, j1);
	}
	return (nil, revs(toks));
}

revs(l: list of string): list of string
{
	m: list of string;
	for (; l != nil; l = tl l)
		m = hd l :: m;
	return m;
}

checkformat(p: ref Member, fmt: int, w: string): (int, string)
{
	case fmt {
	'o' =>
		# object id
		if (isnum(w) && (o := p.obj(int w)) != nil)
			return (1, string o.id);
	'd' =>
		# integer
		if (isnum(w))
			return (1, w);
	'p' =>
		# member id
		if (isnum(w) && (member := clique.member(int w)) != nil)
			return (1, w);
	}
	return (0, nil);
}

isnum(w: string): int
{
	# XXX lazy for the time being...
	if (w != nil && ((w[0] >= '0' && w[0] <= '9') || w[0] == '-'))
		return 1;
	return 0;
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
