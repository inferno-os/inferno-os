#
#	Miscellaneous routines.
#

Cmd.cmd1(op: int, l: ref Cmd): ref Cmd
{
	return ref Cmd(op, nil, l, nil, nil, nil, nil, 0);
}

Cmd.cmd2(op: int, l, r: ref Cmd): ref Cmd
{
	return ref Cmd(op, nil, l, r, nil, nil, nil, 0);
}

Cmd.cmd1i(op: int, l: ref Cmd, i: ref Item): ref Cmd
{
	return ref Cmd(op, nil, l, nil, i, nil, nil, 0);
}

Cmd.cmd1w(op: int, l: ref Cmd, w: list of ref Item): ref Cmd
{
	return ref Cmd(op, w, l, nil, nil, nil, nil, 0);
}

Cmd.cmde(c: self ref Cmd, op: int, l, r: ref Cmd): ref Cmd
{
	c.op = op;
	c.left = l;
	c.right = r;
	return c;
}

Cmd.cmdiw(op: int, i: ref Item, w: list of ref Item): ref Cmd
{
	return ref Cmd(op, revitems(w), nil, nil, i, nil, nil, 0);
}

Pin, Pout:	con 1 << iota;

rdmap := array[] of
{
	Rin => Pin,
	Rout or Rappend => Pout,
	Rinout => Pin | Pout,
};

rdsymbs := array[] of
{
	Rin => "<",
	Rout => ">",
	Rappend => ">>",
	Rinout => "<>",
};

ionames := array[] of
{
	Pin => "input",
	Pout => "ouput",
	Pin | Pout => "input/output",
};

#
#	Check a pipeline for ambiguities.
#
Cmd.checkpipe(c: self ref Cmd, e: ref Env, f: int): int
{
	if (c.error)
		return 0;
	if (c.op == Cpipe) {
		if (!c.left.checkpipe(e, f | Pout))
			return 0;
		if (!c.right.checkpipe(e, f | Pin))
			return 0;
	}
	if (f) {
		t := 0;
		for (l := c.redirs; l != nil; l = tl l)
			t |= rdmap[(hd l).op];
		f &= t;
		if (f) {
			e.report(sys->sprint("%s redirection conflicts with pipe", ionames[f]));
			return 0;
		}
	}
	return 1;
}

#
#	Update a command with another redirection.
#
Cmd.cmdio(c: self ref Cmd, e: ref Env, i: ref Item)
{
	f := 0;
	for (l := c.redirs; l != nil; l = tl l)
		f |= rdmap[(hd l).op];
	r := i.redir;
	f &= rdmap[r.op];
	if (f != 0) {
		e.report(sys->sprint("repeat %s redirection", ionames[f]));
		c.error = 1;
	}
	c.redirs = r :: c.redirs;
}

#
#	Make a basic command.
#
Cmd.mkcmd(c: self ref Cmd, e: ref Env, async: int): ref Cmd
{
	if (!c.checkpipe(e, 0))
		return nil;
	if (async)
		return ref Cmd(Casync, nil, c, nil, nil, nil, nil, 0);
	else
		return c;
}

#
#	Rotate parse tree of cases.
#
Cmd.rotcases(c: self ref Cmd): ref Cmd
{
	l := c;
	c = nil;
	while (l != nil) {
		t := l.right;
		l.right = c;
		c = l;
		l = l.left;
		c.left = t;
	}
	return c;
}

Item.item1(op: int, l: ref Item): ref Item
{
	return ref Item(op, nil, l, nil, nil, nil);
}

Item.item2(op: int, l, r: ref Item): ref Item
{
	return ref Item(op, nil, l, r, nil, nil);
}

Item.itemc(op: int, c: ref Cmd): ref Item
{
	return ref Item(op, nil, nil, nil, c, nil);
}

#
#	Make an item from a list of strings.
#
Item.iteml(l: list of string): ref Item
{
	if (l != nil && tl l == nil)
		return Item.itemw(hd l);
	r: list of string;
	while (l != nil) {
		r = (hd l) :: r;
		l = tl l;
	}
	c := ref Cmd;
	c.op = Clist;
	c.value = revstrs(r);
	return Item.itemc(Iexpr, c);
}

Item.itemr(op: int, i: ref Item): ref Item
{
	return ref Item(Iredir, nil, nil, nil, nil, ref Redir(op, i));
}

qword:	Word = (nil, Wquoted, (0, nil));

Item.itemw(s: string): ref Item
{
	w := ref qword;
	w.text = s;
	return ref Item(Iword, w, nil, nil, nil, nil);
}

revitems(l: list of ref Item): list of ref Item
{
	r: list of ref Item;
	while (l != nil) {
		r = (hd l) :: r;
		l = tl l;
	}
	return r;
}

revstrs(l: list of string): list of string
{
	r: list of string;
	while (l != nil) {
		r = (hd l) :: r;
		l = tl l;
	}
	return r;
}

prepend(l: list of string, r: list of string): list of string
{
	while (r != nil) {
		l = (hd r) :: l;
		r = tl r;
	}
	return l;
}

concat(l: list of string): string
{
	s := hd l;
	for (;;) {
		l = tl l;
		if (l == nil)
			return s;
		s += " ";
		s += hd l;
	}
}

#
#	Make an item list, no redirections allowed.
#
Env.mklist(e: self ref Env, l: list of ref Item): list of ref Item
{
	r: list of ref Item;
	while (l != nil) {
		i := hd l;
		if (i.op == Iredir)
			e.report("redirection in list");
		else
			r = i :: r;
		l = tl l;
	}
	return r;
}

#
#	Make a simple command.
#
Env.mksimple(e: self ref Env, l: list of ref Item): ref Cmd
{
	r: list of ref Item;
	c := ref Cmd;
	c.op = Csimple;
	c.error = 0;
	while (l != nil) {
		i := hd l;
		if (i.op == Iredir)
			c.cmdio(e, i);
		else
			r = i :: r;
		l = tl l;
	}
	c.words = r;
	return c;
}

Env.diag(e: self ref Env, s: string): string
{
	return where(e) + s;
}

Env.usage(e: self ref Env, s: string)
{
	e.report("usage: " + s);
}

Env.report(e: self ref Env, s: string)
{
	sys->fprint(e.stderr, "%s\n", e.diag(s));
	if (e.flags & ERaise)
		exits("error");
}

Env.error(e: self ref Env, s: string)
{
	e.report(s);
	cleanup();
}

panic(s: string)
{
	raise "panic: " + s;
}

prprompt(n: int)
{
	case n {
	0 =>
		sys->print("%s", prompt);
	1 =>
		sys->print("%s", contin);
	}
}

Env.couldnot(e: self ref Env, what, who: string)
{
	sys->fprint(e.stderr, "could not %s %s: %r\n", what, who);
	exits("system error");
}

cleanup()
{
	exit;
}

exits(s: string)
{
	raise "fail: mash " + s;
}
