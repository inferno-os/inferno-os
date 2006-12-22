#
#	Symbol table routines.  A symbol table becomes copy-on-write
#	when it is cloned.  The first modification will copy the hash table.
#	Every list is then copied on first modification.
#

#
#	Copy a hash list.
#
cpsymbs(l: list of ref Symb): list of ref Symb
{
	r: list of ref Symb;
	while (l != nil) {
		r = (ref *hd l) :: r;
		l = tl l;
	}
	return r;
}

#
#	New symbol table.
#
Stab.new(): ref Stab
{
	return ref Stab(array[SHASH] of list of ref Symb, 0, 0);
}

#
#	Clone a symbol table.  Copy Stab and mark contents copy-on-write.
#
Stab.clone(t: self ref Stab): ref Stab
{
	t.copy = 1;
	t.wmask = SMASK;
	return ref *t;
}

#
#	Update symbol table entry, or add new entry.
#
Stab.update(t: self ref Stab, s: string, tag: int, v: list of string, f: ref Cmd, b: Mashbuiltin): ref Symb
{
	if (t.copy) {
		a := array[SHASH] of list of ref Symb;
		a[:] = t.tab[:];
		t.tab = a;
		t.copy = 0;
	}
	x := hash->fun1(s, SHASH);
	l := t.tab[x];
	if (t.wmask & (1 << x)) {
		l = cpsymbs(l);
		t.tab[x] = l;
		t.wmask &= ~(1 << x);
	}
	r := l;
	while (r != nil) {
		h := hd r;
		if (h.name == s) {
			case tag {
			Svalue =>
				h.value = v;
			Sfunc =>
				h.func = f;
			Sbuiltin =>
				h.builtin = b;
			}
			return h;
		}
		r = tl r;
	}
	n := ref Symb(s, v, f, b, 0);
	t.tab[x] = n :: l;
	return n;
}

#
#	Make a list of a symbol table's contents.
#
Stab.all(t: self ref Stab): list of ref Symb
{
	r: list of ref Symb;
	for (i := 0; i < SHASH; i++) {
		for (l := t.tab[i]; l != nil; l = tl l)
			r = (ref *hd l) :: r;
	}
	return r;
}

#
#	Assign a list of strings to a variable.  The distinguished value
#	"empty" is used to distinguish nil value from undefined.
#
Stab.assign(t: self ref Stab, s: string, v: list of string)
{
	if (v == nil)
		v = empty;
	t.update(s, Svalue, v, nil, nil);
}

#
#	Define a builtin.
#
Stab.defbuiltin(t: self ref Stab, s: string, b: Mashbuiltin)
{
	t.update(s, Sbuiltin, nil, nil, b);
}

#
#	Define a function.
#
Stab.define(t: self ref Stab, s: string, f: ref Cmd)
{
	t.update(s, Sfunc, nil, f, nil);
}

#
#	Symbol table lookup.
#
Stab.find(t: self ref Stab, s: string): ref Symb
{
	l := t.tab[hash->fun1(s, SHASH)];
	while (l != nil) {
		h := hd l;
		if (h.name == s)
			return h;
		l = tl l;
	}
	return nil;
}

#
#	Function lookup.
#
Stab.func(t: self ref Stab, s: string): ref Cmd
{
	v := t.find(s);
	if (v == nil)
		return nil;
	return v.func;
}

#
#	New environment.
#
Env.new(): ref Env
{
	return ref Env(Stab.new(), nil, ETop, nil, nil, nil, nil, nil, nil, 0);
}

#
#	Clone environment.  No longer top-level or interactive.
#
Env.clone(e: self ref Env): ref Env
{
	e = e.copy();
	e.flags &= ~(ETop | EInter);
	e.global = e.global.clone();
	if (e.local != nil)
		e.local = e.local.clone();
	return e;
}

#
#	Copy environment.
#
Env.copy(e: self ref Env): ref Env
{
	return ref *e;
}

#
#	Fetch $n argument.
#
Env.arg(e: self ref Env, s: string): string
{
	n := int s;
	if (e.args == nil || n >= len e.args)
		return "$" + s;
	else
		return e.args[n];
}

#
#	Lookup builtin.
#
Env.builtin(e: self ref Env, s: string): Mashbuiltin
{
	v := e.global.find(s);
	if (v == nil)
		return nil;
	return v.builtin;
}

#
#	Define a builtin.
#
Env.defbuiltin(e: self ref Env, s: string, b: Mashbuiltin)
{
	e.global.defbuiltin(s, b);
}

#
#	Define a function.
#
Env.define(e: self ref Env, s: string, f: ref Cmd)
{
	e.global.define(s, f);
}

#
#	Value of a shell variable (check locals then globals).
#
Env.dollar(e: self ref Env, s: string): ref Symb
{
	if (e.local != nil) {
		l := e.local.find(s);
		if (l != nil && l.value != nil)
			return l;
	}
	g := e.global.find(s);
	if (g != nil && g.value != nil)
		return g;
	return nil;
}

#
#	Lookup a function.
#
Env.func(e: self ref Env, s: string): ref Cmd
{
	v := e.global.find(s);
	if (v == nil)
		return nil;
	return v.func;
}

#
#	Local assignment.
#
Env.let(e: self ref Env, s: string, v: list of string)
{
	if (e.local == nil)
		e.local = Stab.new();
	e.local.assign(s, v);
}

#
#	Assignment.  Update local or define global.
#
Env.set(e: self ref Env, s: string, v: list of string)
{
	if (e.local != nil && e.local.find(s) != nil)
		e.local.assign(s, v);
	else
		e.global.assign(s, v);
}

#
#	Report undefined.
#
Env.undefined(e: self ref Env, s: string)
{
	e.report(s + ": undefined");
}
