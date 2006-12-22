implement Mashbuiltin;

#
#	"make" builtin, defines:
#
#	depends	- print dependencies
#	make		- make-like command
#	match	- print details of rule matches
#	rules		- print rules
#

include	"mash.m";
include	"mashparse.m";

verbose:	con 0;	# debug output

mashlib:	Mashlib;

Cmd, Env, Item, Stab:	import mashlib;
Depend, Rule, Target:	import mashlib;
sys, bufio, hash:		import mashlib;

Iobuf:	import bufio;

#
#	Interface to catch the use as a command.
#
init(nil: ref Draw->Context, args: list of string)
{
	raise "fail: " + hd args + " not loaded";
}

#
#	Used by whatis.
#
name(): string
{
	return "make";
}

#
#	Install commands.
#
mashinit(nil: list of string, lib: Mashlib, this: Mashbuiltin, e: ref Env)
{
	mashlib = lib;
	e.defbuiltin("depends", this);
	e.defbuiltin("make", this);
	e.defbuiltin("match", this);
	e.defbuiltin("rules", this);
}

#
#	Execute a builtin.
#
mashcmd(e: ref Env, l: list of string)
{
	s := hd l;
	l = tl l;
	case s {
	"depends" =>
		out := e.outfile();
		if (out == nil)
			return;
		if (l == nil)
			alldeps(out);
		else
			depends(out, l);
		out.close();
	"make" =>
		domake(e, l);
	"match" =>
		domatch(e, l);
	"rules" =>
		out := e.outfile();
		if (out == nil)
			return;
		if (l == nil)
			allrules(out);
		else
			rules(out, l);
		out.close();
	}
}

#
#	Node states.
#
SUnknown, SNoexist, SExist, SStale, SMade, SDir, SDirload
	: con iota;

#
#	Node flags.
#
#	FMark	- marked as in progress
#
FMark
	: con 1 << iota;

Node: adt
{
	name:	string;
	state:		int;
	flags:		int;
	mtime:	int;
};

#
#	Step in implicit chain.
#
Step:	type (ref Rule, array of string, ref Node);

#
#	Implicit match.
#
Match: adt
{
	node:	ref Node;
	path:		list of Step;
};

NSIZE:	con 127;	# node hash size
DSIZE:	con 32;	# number of dir entries for read

ntab:		array of list of ref Node;	# node hash table

initnodes()
{
	ntab = array[NSIZE] of list of ref Node;
}

#
#	Find node for a pathname.
#
getnode(s: string): ref Node
{
	h := hash->fun1(s, NSIZE);
	for (l := ntab[h]; l != nil; l = tl l) {
		n := hd l;
		if (n.name == s)
			return n;
	}
	r := ref Node(s, SUnknown, 0, 0);
	ntab[h] = r :: ntab[h];
	return r;
}

#
#	Make a pathname from a dir and an entry.
#
mkpath(d, s: string): string
{
	if (d == ".")
		return s;
	else if (d == "/")
		return "/" + s;
	else
		return d + "/" + s;
}

#
#	Load a directory.
#
loaddir(s: string)
{
	if (verbose)
		sys->print("loaddir %s\n", s);
	fd := sys->open(s, Sys->OREAD);
	if (fd == nil)
		return;
	for (;;) {
		(c, dbuf) := sys->dirread(fd);
		if(c <= 0)
			break;
		for (i := 0; i < c; i++) {
			n := getnode(mkpath(s, dbuf[i].name));
			if (dbuf[i].mode & Sys->DMDIR)
				n.state = SDir;
			else
				n.state = SExist;
			n.mtime = dbuf[i].mtime;
		}
	}
}

#
#	Load a file.  Get its node, maybe stat it or loaddir.
#
loadfile(s: string): ref Node
{
	n := getnode(s);
	if (n.state == SUnknown) {
		if (verbose)
			sys->print("stat %s\n", s);
		(ok, d) := sys->stat(s);
		if (ok >= 0) {
			n.mtime = d.mtime;
			if (d.mode & Sys->DMDIR) {
				loaddir(s);
				n.state = SDirload;
			} else
				n.state = SExist;
		} else
			n.state = SNoexist;
	} else if (n.state == SDir) {
		loaddir(s);
		n.state = SDirload;
	}
	return n;
}

#
#	Get the node for a file and load the directories in its path.
#
getfile(s: string): ref Node
{
	d: string;
	n := len s;
	while (n >= 2 && s[0:2] == "./") {
		n -= 2;
		s = s[2:];
	}
	if (n > 0 && s[0] == '/') {
		d = "/";
		s = s[1:];
	} else
		d = ".";
	(nil, l) := sys->tokenize(s, "/");
	for (;;) {
		w := loadfile(d);
		if (l == nil)
			return w;
		s = hd l;
		l = tl l;
		d = mkpath(d, s);
	}
}

#
#	If a dependency rule makes more than one target propogate SMade.
#
propagate(l: list of string)
{
	if (tl l == nil)
		return ;
	while (l != nil) {
		s := hd l;
		if (verbose)
			sys->print("propogate to %s\n", s);
		getfile(s).state = SMade;
		l = tl l;
	}
}

#
#	Try to make a node, or mark it as stale.
#	Return -1 on (reported) error, 0 on fail, 1 on success.
#
explicit(e: ref Env, t: ref Target, n: ref Node): int
{
	d: ref Depend;
	for (l := t.depends; l != nil ; l = tl l) {
		if ((hd l).op != Cnop) {
			if (d != nil) {
				e.report(sys->sprint("make: too many rules for %s", t.target));
				return -1;
			}
			d = hd l;
		}
	}
	for (l = t.depends; l != nil ; l = tl l) {
		for (u := (hd l).depends; u != nil; u = tl u) {
			s := hd u;
			m := getfile(s);
			x := make(e, m, s);
			if (x < 0) {
				sys->print("don't know how to make %s\n", s);
				return x;
			}
			if (m.state == SMade || m.mtime > n.mtime) {
				if (verbose)
					sys->print("%s makes %s stale\n", s, t.target);
				n.state = SStale;
			}
		}
	}
	if (d != nil) {
		if (n.state == SNoexist || n.state == SStale) {
			if (verbose)
				sys->print("build %s with explicit rule\n", t.target);
			e = e.copy();
			e.flags |= mashlib->EEcho | Mashlib->ERaise;
			e.flags &= ~mashlib->EInter;
			d.cmd.xeq(e);
			propagate(d.targets);
			n.state = SMade;
		} else if (verbose)
			sys->print("%s up to date\n", t.target);
		return 1;
	}
	return 0;
}

#
#	Report multiple implicit chains of equal length.
#
multimatch(e: ref Env, n: ref Node, l: list of Match)
{
	e.report(sys->sprint("%d rules match for %s", len l, n.name));
	f := e.stderr;
	while (l != nil) {
		m := hd l;
		sys->fprint(f, "%s", m.node.name);
		for (p := m.path; p != nil; p = tl p) {
			(nil, nil, t) := hd p;
			sys->fprint(f, " -> %s", t.name);
		}
		sys->fprint(f, "\n");
		l = tl l;
	}
}

cycle(e: ref Env, n: ref Node)
{
	e.report(sys->sprint("make: cycle in dependencies for target %s", n.name));
}

#
#	Mark the nodes in an implicit chain.
#
markchain(e: ref Env, l: list of Step): int
{
	while (tl l != nil) {
		(nil, nil, n) := hd l;
		if (n.flags & FMark) {
			cycle(e, n);
			return 0;
		}
		n.flags |= FMark;
		l = tl l;
	}
	return 1;
}

#
#	Unmark the nodes in an implicit chain.
#
unmarkchain(l: list of Step): int
{
	while (tl l != nil) {
		(nil, nil, n) := hd l;
		n.flags &= ~FMark;
		l = tl l;
	}
	return 1;
}

#
#	Execute an implicit rule chain.
#
xeqmatch(e: ref Env, b, n: ref Node, l: list of Step): int
{
	if (!markchain(e, l))
		return -1;
	if (verbose)
		sys->print("making %s for implicit rule chain\n", n.name);
	e.args = nil;
	x := make(e, n, n.name);
	if (x < 0) {
		sys->print("don't know how to make %s\n", n.name);
		return x;
	}
	if (n.state == SMade || n.mtime > b.mtime || b.state == SStale) {
		e = e.copy();
		e.flags |= mashlib->EEcho | Mashlib->ERaise;
		e.flags &= ~mashlib->EInter;
		for (;;) {
			(r, a, t) := hd l;
			if (verbose)
				sys->print("making %s with implicit rule\n", t.name);
			e.args = a;
			r.cmd.xeq(e);
			t.state = SMade;
			l = tl l;
			if (l == nil)
				break;
			t.flags &= ~FMark;
		}
	} else
		unmarkchain(l);
	return 1;
}

#
#	Find the shortest implicit rule chain.
#
implicit(e: ref Env, base: ref Node): int
{
	win, lose: list of Match;
	l: list of ref Rule;
	cand := Match(base, nil) :: nil;
	do {
		# cand - list of candidate chains
		# lose - list of extended chains that lose
		# win	 - list of extended chains that win
		lose = nil;
	match:
		# for each candidate
		for (c := cand; c != nil; c = tl c) {
			(b, x) := hd c;
			s := b.name;
			# find rules that match end of chain
			m := mashlib->rulematch(s);
			l = nil;
			# exclude rules already in the chain
		exclude:
			for (n := m; n != nil; n = tl n) {
				r := hd n;
				for (y := x; y != nil; y = tl y) {
					(u, nil, nil) := hd y;
					if (u == r)
						continue exclude;
				}
				l = r :: l;
			}
			if (l == nil)
				continue match;
			(nil, t) := sys->tokenize(s, "/");
			# for each new rule that matched
			for (n = l; n != nil; n = tl n) {
				r := hd n;
				a := r.matches(t);
				if (a == nil) {
					e.report("rule match cock up");
					return -1;
				}
				a[0] = s;
				e.args = a;
				# eval rhs
				(v, nil, nil) := r.rhs.ieval2(e);
				if (v == nil)
					continue;
				y := (r, a, b) :: x;
				z := getfile(v);
				# winner or loser
				if (z.state != SNoexist || Target.find(v) != nil)
					win = (z, y) :: win;
				else
					lose = (z, y) :: lose;
			}
		}
		# winner should be unique
		if (win != nil) {
			if (tl win != nil) {
				multimatch(e, base, win);
				return -1;
			} else {
				(a, p) := hd win;
				return xeqmatch(e, base, a, p);
			}
		}
		# losers are candidates in next round
		cand = lose;
	} while (cand != nil);
	return 0;
}

#
#	Make a node (recursive).
#	Return -1 on (reported) error, 0 on fail, 1 on success.
#
make(e: ref Env, n: ref Node, s: string): int
{
	if (n == nil)
		n = getfile(s);
	if (verbose)
		sys->print("making %s\n", n.name);
	if (n.state == SMade)
		return 1;
	if (n.flags & FMark) {
		cycle(e, n);
		return -1;
	}
	n.flags |= FMark;
	t := Target.find(s);
	if (t != nil) {
		x := explicit(e, t, n);
		if (x != 0) {
			n.flags &= ~FMark;
			return x;
		}
	}
	x := implicit(e, n);
	n.flags &= ~FMark;
	if (x != 0)
		return x;
	if (n.state == SExist)
		return 0;
	return -1;
}

makelevel:	int = 0;	# count recursion

#
#	Make driver routine.  Maybe initialize and handle exceptions.
#
domake(e: ref Env, l: list of string)
{
	if ((e.flags & mashlib->ETop) == 0) {
		e.report("make not at top level");
		return;
	}
	inited := 0;
	if (makelevel > 0)
		inited = 1;
	makelevel++;
	if (l == nil)
		l = "default" :: nil;
	while (l != nil) {
		s := hd l;
		l = tl l;
		if (s[0] == '-') {
			case s {
			"-clear" =>
				mashlib->initdep();
			* =>
				e.report("make: unknown option: " + s);
			}
		} else {
			if (!inited) {
				initnodes();
				inited = 1;
			}
			{
				if (make(e, nil, s) < 0) {
					sys->print("don't know how to make %s\n", s);
					raise "fail: make error";
				}
			}exception x{
			mashlib->FAILPAT =>
				makelevel--;
				raise x;
			}
		}
	}
	makelevel--;
}

#
#	Print dependency/rule command.
#
prcmd(out: ref Iobuf, op: int, c: ref Cmd)
{
	if (op == Clistgroup)
		out.putc(':');
	if (c != nil) {
		out.puts("{ ");
		out.puts(c.text());
		out.puts(" }");
	} else
		out.puts("{}");
}

#
#	Print details of rule matches.
#
domatch(e: ref Env, l: list of string)
{
	out := e.outfile();
	if (out == nil)
		return;
	e = e.copy();
	while (l != nil) {
		s := hd l;
		out.puts(sys->sprint("%s:\n", s));
		m := mashlib->rulematch(s);
		(nil, t) := sys->tokenize(s, "/");
		while (m != nil) {
			r := hd m;
			out.puts(sys->sprint("\tlhs %s\n", r.lhs.text));
			a := r.matches(t);
			if (a != nil) {
				a[0] = s;
				n := len a;
				for (i := 0; i < n; i++)
					out.puts(sys->sprint("\t$%d '%s'\n", i, a[i]));
				e.args = a;
				(v, w, nil) := r.rhs.ieval2(e);
				if (v != nil)
					out.puts(sys->sprint("\trhs '%s'\n", v));
				else
					out.puts(sys->sprint("\trhs list %d\n", len w));
				if (r.cmd != nil) {
					out.putc('\t');
					prcmd(out, r.op, r.cmd);
					out.puts(";\n");
				}
			} else
				out.puts("\tcock up\n");
			m = tl m;
		}
		l = tl l;
	}
	out.close();
}

#
#	Print word list.
#
prwords(out: ref Iobuf, l: list of string, pre: int)
{
	while (l != nil) {
		if (pre)
			out.putc(' ');
		out.puts(mashlib->quote(hd l));
		if (!pre)
			out.putc(' ');
		l = tl l;
	}
}

#
#	Print dependency.
#
prdep(out: ref Iobuf, d: ref Depend)
{
	prwords(out, d.targets, 0);
	out.putc(':');
	prwords(out, d.depends, 1);
	if (d.op != Cnop) {
		out.putc(' ');
		prcmd(out, d.op, d.cmd);
	}
	out.puts(";\n");
}

#
#	Print all dependencies, avoiding duplicates.
#
alldep(out: ref Iobuf, d: ref Depend, pass: int)
{
	case pass {
	0 =>
		d.mark = 0;
	1 =>
		if (!d.mark) {
			prdep(out, d);
			d.mark = 1;
		}
	}
}

#
#	Print all dependencies.
#
alldeps(out: ref Iobuf)
{
	a := mashlib->dephash;
	n := len a;
	for (p := 0; p < 2; p++)
		for (i := 0; i < n; i++)
			for (l := a[i]; l != nil; l = tl l)
				for (d := (hd l).depends; d != nil; d = tl d)
					alldep(out, hd d, p);
}

#
#	Print dependencies.
#
depends(out: ref Iobuf, l: list of string)
{
	while (l != nil) {
		s := hd l;
		out.puts(s);
		out.puts(":\n");
		t := Target.find(s);
		if (t != nil) {
			for (d := t.depends; d != nil; d = tl d)
				prdep(out, hd d);
		}
		l = tl l;
	}
}

#
#	Print rule.
#
prrule(out: ref Iobuf, r: ref Rule)
{
	out.puts(r.lhs.text);
	out.puts(" :~ ");
	out.puts(r.rhs.text());
	out.putc(' ');
	prcmd(out, r.op, r.cmd);
	out.puts(";\n");
}

#
#	Print all rules.
#
allrules(out: ref Iobuf)
{
	for (l := mashlib->rules; l != nil; l = tl l)
		prrule(out, hd l);
}

#
#	Print matching rules.
#
rules(out: ref Iobuf, l: list of string)
{
	while (l != nil) {
		s := hd l;
		out.puts(s);
		out.puts(":\n");
		r := mashlib->rulematch(s);
		while (r != nil) {
			prrule(out, hd r);
			r = tl r;
		}
		l = tl l;
	}
}
