#
#	Dependency/rule routines.
#

DHASH:	con 127;	# dephash size

#
#	Initialize.  "make -clear" calls this.
#
initdep()
{
	dephash = array[DHASH] of list of ref Target;
	rules = nil;
}

#
#	Lookup a target in dephash, maybe add it.
#
target(s: string, insert: int): ref Target
{
	h := hash->fun1(s, DHASH);
	l := dephash[h];
	while (l != nil) {
		if ((hd l).target == s)
			return hd l;
		l = tl l;
	}
	if (!insert)
		return nil;
	t := ref Target(s, nil);
	dephash[h] = t :: dephash[h];
	return t;
}

adddep(s: string, d: ref Depend)
{
	t := target(s, 1);
	t.depends = d :: t.depends;
}

#
#	Dependency (:) command.
#	Evaluate lhs and rhs, make dependency, and add to the targets.
#
Cmd.depend(c: self ref Cmd, e: ref Env)
{
	if ((e.flags & ETop) == 0) {
		e.report("dependency not at top level");
		return;
	}
	if (dephash == nil)
		initdep();
	w := pass1(e, c.words);
	if (w == nil)
		return;
	l := pass2(e, w);
	if (l == nil)
		return;
	r: list of string;
	if (c.left.words != nil) {
		w = pass1(e, c.left.words);
		if (w == nil)
			return;
		r = pass2(e, w);
		if (r == nil)
			return;
	}
	d := ref Depend(l, r, c.left.op, c.left.left, 0);
	while (l != nil) {
		adddep(hd l, d);
		l = tl l;
	}
}

#
#	Evaluate rule lhs and break into path components.
#
rulelhs(e: ref Env, i: ref Item): ref Lhs
{
	i = i.ieval1(e);
	if (i == nil)
		return nil;
	(s, l, nil) := i.ieval2(e);
	if (l != nil) {
		e.report("rule pattern evaluates to a list");
		return nil;
	}
	if (s == nil) {
		e.report("rule pattern evaluates to nil");
		return nil;
	}
	(n, p) := sys->tokenize(s, "/");
	return ref Lhs(s, p, n);
}

#
#	Rule (:~) command.
#	First pass of rhs evaluation is done here.
#
Cmd.rule(c: self ref Cmd, e: ref Env)
{
	if (e.flags & ETop) {
		l := rulelhs(e, c.item);
		if (l == nil)
			return;
		r := c.left.item.ieval1(e);
		if (r == nil)
			return;
		rules = ref Rule(l, r, c.left.op, c.left.left) :: rules;
	} else
		e.report("rule not at top level");
}

Target.find(s: string): ref Target
{
	if (dephash == nil)
		return nil;
	return target(s, 0);
}

#
#	Match a path element.
#
matchelem(p, s: string): int
{
	m := len p;
	n := len s;
	if (m == n && p == s)
		return 1;
	for (i := 0; i < m; i++) {
		if (p[i] == '*') {
			j := i + 1;
			if (j == m)
				return 1;
			q := p[j:];
			do {
				if (matchelem(q, s[i:]))
					return 1;
			} while (++i < n);
			return 0;
		} else if (i >= n || p[i] != s[i])
			return 0;
	}
	return 0;
}

#
#	Match a path element and return a list of sub-matches.
#
matches(p, s: string): (int, list of string)
{
	m := len p;
	n := len s;
	for (i := 0; i < m; i++) {
		if (p[i] == '*') {
			j := i + 1;
			if (j == m)
				return (1, s[i:] :: nil);
			q := p[j:];
			do {
				(r, l) := matches(q, s[i:]);
				if (r)
					return (1, s[j - 1: i] :: l);
			} while (++i < n);
			return (0, nil);
		} else if (i >= n || p[i] != s[i])
			return (0, nil);
	}
	return (m == n, nil);
}

#
#	Rule match.
#
Rule.match(r: self ref Rule, a, n: int, t: list of string): int
{
	l := r.lhs;
	if (l.count != n || (l.text[0] == '/') != a)
		return 0;
	for (e := l.elems; e != nil; e = tl e) {
		if (!matchelem(hd e, hd t))
			return 0;
		t = tl t;
	}
	return 1;
}

#
#	Rule match with array of sub-matches.
#
Rule.matches(r: self ref Rule, t: list of string): array of string
{
	m: list of list of string;
	c := 1;
	for (e := r.lhs.elems; e != nil; e = tl e) {
		(x, l) := matches(hd e, hd t);
		if (!x)
			return nil;
		if (l != nil) {
			c += len l;
			m = revstrs(l) :: m;
		}
		t = tl t;
	}
	a := array[c] of string;
	while (m != nil) {
		for (l := hd m; l != nil; l = tl l)
			a[--c] = hd l;
		m = tl m;
	}
	return a;
}

#
#	Return list of rules that match a string.
#
rulematch(s: string): list of ref Rule
{
	m: list of ref Rule;
	a := s[0] == '/';
	(n, t) := sys->tokenize(s, "/");
	for (l := rules; l != nil; l = tl l) {
		r := hd l;
		if (r.match(a, n, t))
			m = r :: m;
	}
	return m;
}
