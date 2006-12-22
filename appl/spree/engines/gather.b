implement Engine;

include "sys.m";
	sys: Sys;
include "draw.m";
include "sets.m";
	sets: Sets;
	Set, set, A, B, All, None: import sets;
include "../spree.m";
	spree: Spree;
	archives: Archives;
	Attributes, Range, Object, Clique, Member, rand: import spree;
include "daytime.m";
	daytime: Daytime;
include "../gather.m";

clique: ref Clique;

started := 0;
halted := 0;
suspended: Set;		# set of members currently suspended from the clique.
count := 0;
nmembers := 0;
title := "unknown";
cliquemod: Gatherengine;

members: Set;
watchers: Set;

invited: list of string;

# options:
# <n> cliquemodule opts
init(srvmod: Spree, g: ref Clique, argv: list of string): string
{
	sys = load Sys Sys->PATH;
	clique = g;
	spree = srvmod;
	sets = load Sets Sets->PATH;
	if (sets == nil) {
		sys->print("gather: cannot load %s: %r\n", Sets->PATH);
		return "bad module";
	}
	sets->init();
	daytime = load Daytime Daytime->PATH;
	if (daytime == nil) {
		sys->print("gather: cannot load %s: %r\n", Daytime->PATH);
		return "bad module";
	}
	archives = load Archives Archives->PATH;
	if (archives == nil) {
		sys->print("gather: cannot load %s: %r\n", Archives->PATH);
		return "bad module";
	}
	archives->init(srvmod);
	argv = tl argv;
	n := len argv;
	if (n < 2)
		return "bad init options";
	count = int hd argv;
	if (count != -1 && count <= 0)
		return "bad gather count";
	argv = tl argv;
	if (count < len clique.archive.members)
		count = len clique.archive.members;
	cliquemod = load Gatherengine "/dis/spree/engines/" + hd argv + ".dis";
	if (cliquemod == nil)
		return sys->sprint("bad module: %r");
	title = concat(argv);
	e := cliquemod->init(srvmod, clique, tl argv, len clique.archive.members > 0);
	if (e != nil)
		return e;
	if (len clique.archive.members > 0) {
		for (i := 0; i < len clique.archive.members; i++)
			invited = clique.archive.members[i] :: invited;
	} else
		invited = clique.owner() :: nil;
	for (inv := invited; inv != nil; inv = tl inv)
		clique.notify(clique.parentid, "invite " + hd inv);
	clique.notify(clique.parentid, "title (" + title + ")");
	return nil;
}

join(p: ref Member, cmd: string, susp: int): string
{
sys->print("gather: %s[%d] joining '%s' (suspended: %d)\n", p.name, p.id, cmd, susp);
	case cmd {
	"join" =>
		if (started) {
			if (!susp || !halted)
				return "clique has already started";
			suspended = suspended.del(p.id);
			if (suspended.eq(None)) {
				halted = 0;
				# XXX inform participants that clique is starting again
			}
			pset := None.add(p.id);
			clique.action("clienttype " + cliquemod->clienttype(), nil, nil, pset);
			clique.breakmsg(pset);
			return nil;
		}
		for (inv := invited;  inv != nil; inv = tl inv)
			if (hd inv == p.name || hd inv == "all")
				break;
		if (inv == nil)
			return "you have not been invited";
		if (nmembers >= cliquemod->maxmembers() || (count != -1 && nmembers >= count))
			return "too many members already";
		if (len clique.archive.members > 0) {
			for (i := 0; i < len clique.archive.members; i++)
				if (p.name == clique.archive.members[i])
					break;
			if (i == len clique.archive.members)
				return "you are not part of that clique";
		}
		nmembers++;
		members = members.add(p.id);
		clique.notify(clique.parentid, "join " + p.name);
		s := None.add(p.id);
		# special case for single member cliques: don't need a gather client as we can start right now.
		if (cliquemod->maxmembers() == 1)
			return startclique();
		clique.action("clienttype gather", nil, nil, s);
		clique.breakmsg(s);
		clique.action("title " + title, nil, nil, s);
		clique.action("join " + p.name, nil, nil, All);
	"watch" =>
		if (susp)
			return "you cannot watch if you are playing";
		watchers = watchers.add(p.id);
		s := None.add(p.id);
		if (started)
			clique.action("clienttype " + cliquemod->clienttype(), nil, nil, s);
		else
			clique.action("clienttype gather", nil, nil, s);
		clique.breakmsg(s);
		if (!started)
			clique.action("watch " + p.name, nil, nil, All);
	* =>
		return "unknown join request";
	}
	return nil;
}

leave(p: ref Member): int
{
	if (members.holds(p.id)) {
		if (started) {
			suspended = suspended.add(p.id);
			if (suspended.eq(members)) {
				cliquemod->archive();
				name := spree->newarchivename();
				e := archives->write(clique,
					("title", concat(tl tl clique.archive.argv)) :: 
					("date", string daytime->now()) :: nil,
					name, members);
				if (e != nil)
					sys->print("warning: cannot archive clique: %s\n", e);
				else
					clique.notify(clique.parentid, "archived " + name);
				clique.hangup();
				return 1;
			} else {
				halted = 1;
				return 0;
			}
		}

		members = members.del(p.id);
		nmembers--;
		clique.notify(clique.parentid, "leave " + p.name);
		if (nmembers == 0)
			clique.hangup();
	} else {
		watchers = watchers.del(p.id);
		clique.action("unwatch " + p.name, nil, nil, All);
	}
	return 1;
}

notify(nil: int, note: string)
{
	(n, toks) := sys->tokenize(note, " ");
	case hd toks {
	"invite" =>
		invited = hd tl toks :: invited;
	"uninvite" =>
		inv := invited;
		for (invited = nil; inv != nil; inv = tl inv)
			if (hd inv != hd tl toks)
				invited = hd inv :: invited;
	* =>
		sys->print("gather: unknown notification '%s'\n", note);
	}
}

command(p: ref Member, cmd: string): string
{
	if (halted)
		return "clique is halted for the time being";
	if (started) {
		if (!members.holds(p.id)) {
sys->print("members (%s) doesn't hold %s[%d]\n", members.str(), p.name, p.id);
			return "you are only watching";
		}
		return cliquemod->command(p, cmd);
	}

	(n, toks) := sys->tokenize(cmd, " \n");
	if (n == 0)
		return "bad command";
	case hd toks {
	"start" =>
		if (len clique.archive.members == 0 && p.name != clique.owner())
			return "only the owner can start a clique";
		if (count != -1 && nmembers != count)
			return "need " + string count + " members";
		return startclique();
	"chat" =>
		clique.action("chat " + p.name + " " + concat(tl toks), nil, nil, All);
	* =>
		return "unknown command";
	}
	return nil;
}

startclique(): string
{
	# XXX could randomly shuffle members here

	pa := array[nmembers] of ref Member;
	names := array[nmembers] of string;
	j := nmembers;
	for (i := members.limit(); i >= 0; i--)
		if (members.holds(i)) {
			pa[--j] = clique.member(i);
			names[j] = pa[j].name;
		}
	e := cliquemod->propose(names);
	if (e != nil)
		return e;
	clique.action("clienttype " + cliquemod->clienttype(), nil, nil, All);
	clique.breakmsg(All);
	cliquemod->start(pa, len clique.archive.members > 0);
	clique.start();
	started = 1;
	clique.notify(clique.parentid, "started");
	clique.notify(clique.parentid, "title " + concat(tl tl clique.archive.argv));
	return nil;
}

readfile(f: int, offset: big, n: int): array of byte
{
	if (!started)
		return nil;
	return cliquemod->readfile(f, offset, n);
}

concat(l: list of string): string
{
	if (l == nil)
		return nil;
	s := hd l;
	for (l = tl l; l != nil; l = tl l)
		s += " " + hd l;
	return s;
}
