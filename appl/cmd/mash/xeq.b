#
#	Command execution.
#

#
#	Entry from parser.
#
Cmd.xeq(c: self ref Cmd, e: ref Env)
{
	if (e.flags & EDumping) {
		s := c.text();
		f := e.outfile();
		f.puts(s);
		if (s != nil && s[len s - 1] != '&')
			f.putc(';');
		f.putc('\n');
		f.close();
		f = nil;
	}
	if ((e.flags & ENoxeq) == 0)
		c.xeqit(e, 1);
}

#
#	Execute a command.  Tail recursion.
#
Cmd.xeqit(c: self ref Cmd, e: ref Env, wait: int)
{
tail:	for (;;) {
	if (c == nil)
		return;
	case c.op {
	Csimple =>
		c.simple(e, wait);
	Casync =>
		e = e.clone();
		e.in = e.devnull();
		e.wait = nil;
		spawn c.left.xeqit(e, 1);
	Cgroup =>
		if (c.redirs != nil) {
			(ok, in, out) := mkredirs(e, c.redirs);
			if (!ok)
				return;
			e = e.copy();
			e.in = in;
			e.out = out;
			c.left.xeqit(e, 1);	
		} else {
			c = c.left;
			continue tail;
		}
	Csubgroup =>
		e = e.clone();
		if (c.redirs != nil) {
			(ok, in, out) := mkredirs(e, c.redirs);
			if (!ok)
				return;
			e.in = in;
			e.out = out;
		}
		c = c.left;
		continue tail;
	Cseq =>
		c.left.xeqit(e, 1);	
		c = c.right;
		continue tail;
	Cpipe =>
		do {
			fds := e.pipe();
			if (fds == nil)
				return;
			n := e.clone();
			n.out = fds[0];
			c.left.xeqit(n, 0);
			n = nil;
			e = e.clone();
			e.in = fds[1];
			fds = nil;
			c = c.right;
		} while (c.op == Cpipe);
		continue tail;
	Cif =>
		t := c.left.truth(e);
		if (c.right.op == Celse) {
			if (t)
				c.right.left.xeqit(e, wait);
			else
				c.right.right.xeqit(e, wait);
		} else if (t)
			c.right.xeqit(e, wait);
	Celse =>
		panic("unexpected else");
	Cwhile =>
		while (c.left.truth(e))
			c.right.xeqit(e, wait);
	Cfor =>
		(ok, l) := evalw(c.words, e);
		if (!ok)
			return;
		s := c.item.word.text;
		c = c.left;
		while (l != nil) {
			e.let(s, (hd l) :: nil);
			c.xeqit(e, 1);
			l = tl l;
		}
	Ccase =>
		(s1, l1) := c.left.eeval(e);
		r := c.right;
		while (r != nil) {
			l := r.left;
			(s2, l2) := l.left.eeval(e);
			if (match2(e, s1, l1, s2, l2)) {
				c = l.right;
				continue tail;
			}
			r = r.right;
		}
	Ceq =>
		c.assign(e, 0);
	Cdefeq =>
		c.assign(e, 1);
	Cfn =>
		(s, nil, nil) := c.item.ieval(e);
		if (!ident(s)) {
			e.report("bad function name");
			return;
		}
		e.define(s, c.left);
	Crescue =>
		e.report("rescue not implemented");
	Cdepend =>
		c.depend(e);
	Crule =>
		c.rule(e);
	* =>
		sys->print("number %d\n", c.op);
	} return; } # tail recursion
}

#
#	Execute quote or backquote generator.  Return generated item.
#
Cmd.quote(c: self ref Cmd, e: ref Env, back: int): ref Item
{
	e = e.copy();
	fds := e.pipe();
	if (fds == nil)
		return nil;
	e.out = fds[0];
	in := bufio->fopen(fds[1], Bufio->OREAD);
	if (in == nil)
		e.couldnot("fopen", "pipe");
	c.xeqit(e, 0);
	fds = nil;
	e = nil;
	if (back) {
		l: list of string;
		while ((s := in.gets('\n')) != nil) {
			(nil, r) := sys->tokenize(s, " \t\r\n");
			l = prepend(l, r);
		}
		return Item.iteml(revstrs(l));
	} else {
		s := in.gets('\n');
		if (s != nil && s[len s - 1] == '\n')
			s = s[:len s - 1];
		return Item.itemw(s);
	}
}

#
#	Execute serve generator.
#
Cmd.serve(c: self ref Cmd, e: ref Env, write: int): ref Item
{
	e = e.clone();
	fds := e.pipe();
	if (fds == nil)
		return nil;
	if (write)
		e.in = fds[0];
	else
		e.out = fds[0];
	s := e.servefd(fds[1], write);
	if (s == nil)
		return nil;
	c.xeqit(e, 0);
	return Item.itemw(s);
}

#
#	Expression evaluation, first pass.
#	Parse tree is copied and word items are evaluated.
#	nil return for error is propagated.
#
Cmd.eeval1(c: self ref Cmd, e: ref Env): ref Cmd
{
	case c.op {
	Cword =>
		l := c.item.ieval1(e);
		if (l == nil)
			return nil;
		return Cmd.cmd1i(Cword, nil, l);
	Chd or Ctl or Clen or Cnot =>
		l := c.left.eeval1(e);
		if (l == nil)
			return nil;
		return Cmd.cmd1(c.op, l);
	Ccaret or Ccons or Ceqeq or Cnoteq or Cmatch =>
		l := c.left.eeval1(e);
		r := c.right.eeval1(e);
		if (l == nil || r == nil)
			return nil;
		return Cmd.cmd2(c.op, l, r);
	}
	panic("expr1: bad op");
	return nil;
}

#
#	Expression evaluation, second pass.
#	Returns a tuple (singleton, list, expand flag).
#
Cmd.eeval2(c: self ref Cmd, e: ref Env): (string, list of string, int)
{
	case c.op {
	Cword =>
		return c.item.ieval2(e);
	Clist =>
		return (nil, c.value, 0);
	Ccaret =>
		(s1, l1, x1) := c.left.eeval2(e);
		(s2, l2, x2) := c.right.eeval2(e);
		return caret(s1, l1, x1, s2, l2, x2);
	Chd =>
		(s, l, x) := c.left.eeval2(e);
		if (s != nil)
			return (s, nil, x);
		if (l != nil)
			return (hd l, nil, 0);
	Ctl =>
		(s, l, nil) := c.left.eeval2(e);
		if (s != nil)
			break;
		if (l != nil)
			return (nil, tl l, 0);
	Clen =>
		(s, l, nil) := c.left.eeval2(e);
		if (s != nil)
			return ("1", nil, 0);
		return (string len l, nil, 0);
	Cnot =>
		(s, l, nil) := c.left.eeval2(e);
		if (s == nil && l == nil)
			return (TRUE, nil, 0);
	Ccons =>
		(s1, l1, nil) := c.left.eeval2(e);
		(s2, l2, nil) := c.right.eeval2(e);
		if (s1 != nil) {
			if (s2 != nil)
				return (nil, s1 :: s2 :: nil, 0);
			if (l2 != nil)
				return (nil, s1 :: l2, 0);
			return (s1, nil, 0);
		} else if (l1 != nil) {
			if (s2 != nil)
				return (nil, prepend(s2 :: nil, revstrs(l1)), 0);
			if (l2 != nil)
				return (nil, prepend(l2, revstrs(l1)), 0);
			return (nil, l1, 0);
		} else
			return (s2, l2, 0);
	Ceqeq =>
		if (c.evaleq(e))
			return (TRUE, nil, 0);
	Cnoteq =>
		if (!c.evaleq(e))
			return (TRUE, nil, 0);
	Cmatch =>
		if (c.evalmatch(e))
			return (TRUE, nil, 0);
	* =>
		panic("expr2: bad op");
	}
	return (nil, nil, 0);
}

#
#	Evaluate expression.  1st pass, 2nd pass, maybe glob.
#
Cmd.eeval(c: self ref Cmd, e: ref Env): (string, list of string)
{
	c = c.eeval1(e);
	if (c == nil)
		return (nil, nil);
	(s, l, x) := c.eeval2(e);
	if (x && s != nil)
		(s, l) = glob(e, s);
	return (s, l);
}

#
#	Assignment - let or set.
#
Cmd.assign(c: self ref Cmd, e: ref Env, def: int)
{
	i := c.item;
	if (i == nil)
		return;
	(ok, v) := evalw(c.words, e);
	if (!ok)
		return;
	s := c.item.word.text;
	if (def)
		e.let(s, v);
	else
		e.set(s, v);
}

#
#	Evaluate command and test for non-empty.
#
Cmd.truth(c: self ref Cmd, e: ref Env): int
{
	(s, l) := c.eeval(e);
	return s != nil || l != nil;
}

#
#	Evaluate word.
#
evalw(l: list of ref Item, e: ref Env): (int, list of string)
{
	if (l == nil)
		return (1, nil);
	w := pass1(e, l);
	if (w == nil)
		return (0, nil);
	return (1, pass2(e, w));
}

#
#	Evaluate list of items, pass 1 - reverses.
#
pass1(e: ref Env, l: list of ref Item): list of ref Item
{
	r: list of ref Item;
	while (l != nil) {
		i := (hd l).ieval1(e);
		if (i == nil)
			return nil;
		r = i :: r;
		l = tl l;
	}
	return r;
}

#
#	Evaluate list of items, pass 2 with globbing - reverses (restores order).
#
pass2(e: ref Env, l: list of ref Item): list of string
{
	r: list of string;
	while (l != nil) {
		(s, t, x) := (hd l).ieval2(e);
		if (x && s != nil)
			(s, t) = glob(e, s);
		if (s != nil)
			r = s :: r;
		else if (t != nil)
			r = prepend(r, revstrs(t));
		l = tl l;
	}
	return r;
}

#
#	Simple command.  Maybe a function.
#
Cmd.simple(c: self ref Cmd, e: ref Env, wait: int)
{
	w := pass1(e, c.words);
	if (w == nil)
		return;
	s := pass2(e, w);
	if (s == nil)
		return;
	if (e.flags & EEcho)
		echo(e, s);
	(ok, in, out) := mkredirs(e, c.redirs);
	if (ok)
		e.runit(s, in, out, wait);
}

#
#	Cmd name and arglist.  Maybe a function.
#
Env.runit(e: self ref Env, s: list of string, in, out: ref Sys->FD, wait: int)
{
	d := e.func(hd s);
	if (d != nil) {
		if (e.level >= MAXELEV) {
			e.report(hd s + ": function nesting too deep");
			return;
		}
		e = e.copy();
		e.level++;
		e.in = in;
		e.out = out;
		e.local = Stab.new();
		e.local.assign(ARGS, tl s);
		d.xeqit(e, wait);
	} else
		exec(s, e, in, out, wait);
}

#
#	Item evaluation, first pass.  Copy parse tree.  Expand variables.
#	Call first pass of expression evaluation.  Execute generators.
#
Item.ieval1(i: self ref Item, e: ref Env): ref Item
{
	if (i == nil)
		return nil;
	case i.op {
	Icaret or Iicaret =>
		l := i.left.ieval1(e);
		r := i.right.ieval1(e);
		if (l == nil || r == nil)
			return nil;
		return Item.item2(i.op, l, r);
	Idollar or Idollarq=>
		s := e.dollar(i.word.text);
		if (s == nil) {
			e.undefined(i.word.text);
			return nil;
		}
		if (s.value == empty)
			return Item.itemw(nil);
		if (i.op == Idollar)
			return Item.iteml(s.value);
		else
			return Item.itemw(concat(s.value));
	Iword or Imatch =>
		return i;
	Iexpr =>
		l := i.cmd.eeval1(e);
		if (l == nil)
			return nil;
		return Item.itemc(Iexpr, l);
	Ibackq =>
		return i.cmd.quote(e, 1);
	Iquote =>
		return i.cmd.quote(e, 0);
	Iinpipe =>
		return i.cmd.serve(e, 0);
	Ioutpipe =>
		return i.cmd.serve(e, 1);
	}
	panic("ieval1: bad op");
	return nil;
}

#
#	Item evaluation, second pass.  Outer level carets.  Expand matches.
#	Call second pass of expression evaluation.  
#
Item.ieval2(i: self ref Item, e: ref Env): (string, list of string, int)
{
	case i.op {
	Icaret or Iicaret =>
		return i.caret(e);
	Imatch =>
		return (e.arg(i.word.text), nil, 0);
	Idollar or Idollarq =>
		panic("ieval2: unexpected $");
	Iword =>
		return (i.word.text, nil, i.word.flags & Wexpand);
	Iexpr =>
		return i.cmd.eeval2(e);
	Ibackq or Iinpipe or Ioutpipe =>
		panic("ieval2: unexpected generator");
	}
	panic("ieval2: bad op");
	return (nil, nil, 0);
}

#
#	Item evaluation.
#
Item.ieval(i: self ref Item, e: ref Env): (string, list of string, int)
{
	i = i.ieval1(e);
	if (i == nil)
		return (nil, nil, 0);
	return i.ieval2(e);
}

#
#	Redirection item evaluation.
#
Item.reval(i: self ref Item, e: ref Env): (int, string)
{
	(s, l, nil) := i.ieval(e);
	if (s == nil) {
		if (l == nil)
			e.report("null redirect");
		else
			e.report("list for redirect");
		return (0, nil);
	}
	return (1, s);
}

#
#	Make redirection names.
#
mkrdnames(e: ref Env, l: list of ref Redir): (int, array of string)
{
	f := array[Rcount] of string;
	while (l != nil) {
		r := hd l;
		(ok, s) := r.word.reval(e);
		if (!ok)
			return (0, nil);
		f[r.op] = s;
		l = tl l;
	}
	return (1, f);
}

#
#	Perform redirections.
#
mkredirs(e: ref Env, l: list of ref Redir): (int, ref Sys->FD, ref Sys->FD)
{
	(ok, f) := mkrdnames(e, l);
	if (!ok)
		return (0, nil, nil);
	return redirect(e, f, e.in, e.out);
}
