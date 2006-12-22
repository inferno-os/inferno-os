implement Eval;
include "sys.m";
	sys: Sys;
include "draw.m";
include "sh.m";
	sh: Sh;
	n_BLOCK,  n_VAR, n_BQ, n_BQ2, n_REDIR,
	n_DUP, n_LIST, n_SEQ, n_CONCAT, n_PIPE, n_ADJ,
	n_WORD, n_NOWAIT, n_SQUASH, n_COUNT,
	n_ASSIGN, n_LOCAL: import sh;
include "alphabet/reports.m";
	reports: Reports;
		Report, report: import reports;
include "alphabet.m";

# XXX /usr/inferno/appl/alphabet/eval.b:189: function call type mismatch
# ... a remarkably uninformative error message!

checkload[T](m: T, path: string): T
{
	if(m != nil)
		return m;
	sys->fprint(sys->fildes(2), "eval: cannot load %s: %r\n", path);
	raise "fail:bad module";
}

init()
{
	sys = load Sys Sys->PATH;
	reports = checkload(load Reports Reports->PATH, Reports->PATH);
	sh = checkload(load Sh Sh->PATH, Sh->PATH);
}

WORD, VALUE: con iota;

# to do:
# - change value letters to more appropriate (e.g. fs->f, entries->e, gate->g).
# - allow shell $variable expansions

Evalstate: adt[V, M, C]
	for {
	V =>
		dup:	fn(t: self V): V;
		free:		fn(t: self V, used: int);
		gets:		fn(t: self V): string;
		isstring:	fn(t: self V): int;
		type2s:	fn(tc: int): string;
		typec:	fn(t: self V): int;
	M =>
		find: fn(c: C, s: string): (M, string);
		typesig:	fn(m: self M): string;
		run:		fn(m: self M, c: C,
					errorc: chan of string,
					opts: list of (int, list of V), args: list of V): V;
		mks:		fn(c: C, s: string): V;
		mkc: 	fn(c: C, cmd: ref Sh->Cmd): V;
		typename2c: fn(s: string): int;
		cvt:		fn(c: C, v: V, tc: int, errorc: chan of string): V;
	}
{
	ctxt: C;
	errorc: chan of string;

	expr:	fn(e: self ref Evalstate, c: ref Sh->Cmd, env: Env[V]): V;
	runcmd:	fn(e: self ref Evalstate, cmd: ref Sh->Cmd, arg0: V, args: list of V): V;
	getargs:	fn(e: self ref Evalstate, c: ref Sh->Cmd, env: Env[V]): (ref Sh->Cmd, list of V);
	getvar:	fn(e: self ref Evalstate, c: ref Sh->Cmd, env: Env[V]): V;
};

Env: adt[V]
	for {
	V =>
		free: fn(v: self V, used: int);
		dup:	fn(v: self V): V;
	}
{
	items: array of V;

	new: fn(args: list of V, nilval: V): Env[V];
	get:	fn(t: self Env, id: int): V;
	discard: fn(t: self Env);
};

Context[V, M, Ectxt].eval(expr: ref Sh->Cmd, ctxt: Ectxt, errorc: chan of string,
	args: list of V): V
{
	if(expr == nil){
		discardlist(nil, args);
		return nil;
	}
	nilv: V;
	e := ref Evalstate[V, M, Ectxt](ctxt, errorc);
	{
		return e.runcmd(expr, nilv, args);
	} exception x {
	"error:*" =>
		report(e.errorc, x);
		return nil;
	}
}

Evalstate[V,M,C].expr(e: self ref Evalstate, c: ref Sh->Cmd, env: Env[V]): V
{
	op: ref Sh->Cmd;
	args: list of V;
	arg0: V;
	case c.ntype {
	n_PIPE =>
		if(c.left == nil){
			# N.B. side effect on env.
			arg0 = env.items[0];
			env.items[0] = nil;
			env.items = env.items[1:];
		}else
			arg0 = e.expr(c.left, env);
		{
			(op, args) = e.getargs(c.right, env);
		} exception {
		"error:*" =>
			arg0.free(0);
			raise;
		}
	n_ADJ or
	n_WORD or
	n_BLOCK or
	n_BQ2 =>
		(op, args) = e.getargs(c, env);
	* =>
		raise "error: expected pipe, adj or word, got " + sh->cmd2string(c);
	}

	return e.runcmd(op, arg0, args);
}

# a b c -> adj(adj('a', 'b'), 'c')
Evalstate[V,M,C].getargs(e: self ref Evalstate, c: ref Sh->Cmd, env: Env[V]): (ref Sh->Cmd, list of V)
{
	# do a quick sanity check of module/command-block type
	for(d := c; d.ntype == n_ADJ; d = d.left)
		;
	if(d.ntype != n_WORD && d.ntype != n_BLOCK)
		raise "error: expected word or block, got "+sh->cmd2string(d);
	args: list of V;
	for(; c.ntype == n_ADJ; c = c.left){
		r: V;
		case c.right.ntype {
		n_VAR =>
			r = e.getvar(c.right.left, env);
		n_BLOCK =>
			r = e.expr(c.right.left, env);
		n_WORD =>
			r = M.mks(e.ctxt, deglob(c.right.word));
		n_BQ2 =>
			r = M.mkc(e.ctxt, c.right.left);
		* =>
			discardlist(nil, args);
			raise "error: syntax error: expected var, block or word. got "+sh->cmd2string(c);
		}
		args = r :: args;
	}
	return (c, args);
}
	
Evalstate[V,M,C].getvar(nil: self ref Evalstate, c: ref Sh->Cmd, env: Env[V]): V
{
	if(c == nil || c.ntype != n_WORD)
		raise "error: bad variable name";
	var := deglob(c.word);
	v := env.get(int var);
	if(v == nil)
		raise sys->sprint("error: $%q not defined or cannot be reused", var);
	return v;
}

# get rid of GLOB characters left there by the shell.
deglob(s: string): string
{
	j := 0;
	for (i := 0; i < len s; i++) {
		if (s[i] != Sh->GLOB) {
			if (i != j)		# a worthy optimisation???
				s[j] = s[i];
			j++;
		}
	}
	if (i == j)
		return s;
	return s[0:j];
}

Evalstate[V,M,C].runcmd(e: self ref Evalstate, cmd: ref Sh->Cmd, arg0: V, args: list of V): V
{
	m: M;
	sig: string;
	err: string;
	if(cmd.ntype == n_WORD){
		(m, err) = M.find(e.ctxt, cmd.word);
		if(err != nil){
			discardlist(nil, arg0::args);
			raise sys->sprint("error: cannot load %q: %s", cmd.word, err);
		}
		sig = m.typesig();
	}else{
		(sig, cmd, err) = blocksig0(m, e.ctxt, cmd);
		if(sig == nil){
			discardlist(nil, arg0::args);
			raise sys->sprint("error: invalid command: %s", err);
		}
	}
	ok: int;
	opts: list of (int, list of V);
	x: M;
	(ok, opts, args) = cvtargs(x, e.ctxt, sig, cmd, arg0, args, e.errorc);
	if(ok == -1){
		x: V;
		discardlist(opts, args);
		raise "error: usage: " + sh->cmd2string(cmd)+" "+cmdusage(x, sig);
	}
	if(m != nil){
		r := m.run(e.ctxt, e.errorc, opts, args);
		if(r == nil)
			raise "error: command failed";
		return r;
	}else{
		v: V;	# XXX prevent spurious (?) compiler error message: "type polymorphic type does not have a 'discard' function"
		env := Env[V].new(args, v);
		{
			v = e.expr(cmd, env);
			env.discard();
			return v;
		} exception ex {
		"error:*" =>
			env.discard();
			raise;
		}
	}
}

# {(fd string); walk $2 | merge {unbundle $1}}
blocksig[M, Ectxt](nilm: M, ctxt: Ectxt, e: ref Sh->Cmd): (string, string)
	for{
	M =>
		typename2c: fn(s: string): int;
		find:	fn(c: Ectxt, s: string): (M, string);
		typesig: fn(m: self M): string;
	}
{
	(sig, nil, err) := blocksig0(nilm, ctxt, e);
	return (sig, err);
}

# {(fd string); walk $2 | merge {unbundle $1}}
blocksig0[M, Ectxt](nilm: M, ctxt, e: ref Sh->Cmd): (string, ref Sh->Cmd, string)
	for{
	M =>
		typename2c: fn(s: string): int;
		find:	fn(c: Ectxt, s: string): (M, string);
		typesig: fn(m: self M): string;
	}
{
	if(e == nil || e.ntype != n_BLOCK)
		return (nil, nil, "expected block, got "+sh->cmd2string(e));
	e = e.left;

	
	if(e == nil || e.ntype != n_SEQ || e.left == nil || e.left.ntype != n_LIST){
		(ptc, err) := pipesig(nilm, ctxt, e);
		if(err != nil)
			return (nil, nil, err);
		sig := "a";
		if(ptc != -1)
			sig[len sig] = ptc;
		return (sig, e, nil);
	}

	r := e.right;
	e = e.left.left;
	if(e == nil)
		return ("a", r, nil);
	argt: list of string;
	while(e.ntype == n_ADJ){
		if(e.right.ntype != n_WORD)
			return (nil, nil, "bad declaration: expected word, got "+sh->cmd2string(e.right));
		argt = deglob(e.right.word) :: argt;
		e = e.left;
	}
	if(e.ntype != n_WORD)
		return (nil, nil, "bad declaration: expected word, got "+sh->cmd2string(e));
	argt = e.word :: argt;
	i := 1;
	sig := "a";
	(ptc, err) := pipesig(nilm, ctxt, r);
	if(err != nil)
		return (nil, nil, err);
	if(ptc != -1)
		sig[len sig] = ptc;

	for(a := argt; a != nil; a = tl a){
		tc := M.typename2c(hd a);
		if(tc == -1)
			return (nil, nil, sys->sprint("unknown type %q", hd a));
		sig[len sig] = tc;
		i++;
	}
	return (sig, r, nil);
}

# if e represents an expression with an empty first pipe element,
# return the type of its first argument (-1 if it doesn't).
# string represents error if module doesn't have a first argument.
pipesig[M, Ectxt](nilm: M, ctxt: Ectxt, e: ref Sh->Cmd): (int, string)
	for{
	M =>
		typename2c: fn(s: string): int;
		find:	fn(c: Ectxt, s: string): (M, string);
		typesig: fn(m: self M): string;
	}
{
	if(e == nil)
		return (-1, nil);
	for(; e.ntype == n_PIPE; e = e.left){
		if(e.left == nil){
			# find actual module that's being called.
			for(e = e.right; e.ntype == n_ADJ; e = e.left)
				;
			sig: string;
			if(e.ntype == n_WORD){
				(m, err) := M.find(ctxt, e.word);
				if(m == nil)
					return (-1, err);
				sig = m.typesig();
			}
			else if(e.ntype == n_BLOCK){
				err: string;
				(sig, nil, err) = blocksig0(nilm, ctxt, e);
				if(sig == nil)
					return (-1, err);
			}else
				return (-1, "expected word or block, got "+sh->cmd2string(e));
			if(len sig < 2)
				return (-1, "cannot pipe into "+sh->cmd2string(e));
			return (sig[1], nil);
		}
	}
	return (-1, nil);
}

cvtargs[M,V,C](nil: M, ctxt: C, otype: string, cmd: ref Sh->Cmd, arg0: V, args: list of V, errorc: chan of string): (int, list of (int, list of V), list of V)
	for{
	V =>
		typec: fn(v: self V): int;
		isstring: fn(v: self V): int;
		type2s: fn(tc: int): string;
		gets: fn(v: self V): string;
	M =>
		cvt: fn(c: C, v: V, tc: int, errorc: chan of string): V;
		mks: fn(c: C, s: string): V;
	}
{
	ok: int;
	opts: list of (int, list of V);
	(nil, at, t) := splittype(otype);
	x: M;
	(ok, opts, args) = cvtopts(x, ctxt, t, cmd, args, errorc);
	if(arg0 != nil)
		args = arg0 :: args;
	if(ok == -1)
		return (-1, opts, args);
	if(len at > 0 && at[0] == '*'){
		report(errorc, sys->sprint("error: invalid type descriptor %#q for %s", at, sh->cmd2string(cmd)));
		return (-1, opts, args);
	}
	n := len args;
	if(at != nil && at[len at - 1] == '*'){
		tc := at[len at - 2];
		at = at[0:len at - 2];
		for(i := len at; i < n; i++)
			at[i] = tc;
	}
	if(n != len at){
		report(errorc, sys->sprint("error: wrong number of arguments (%d/%d) to %s", n, len at, sh->cmd2string(cmd)));
		return (-1, opts, args);
	}
	d: list of V;
	(ok, args, d) = cvtvalues(x, ctxt, at, cmd, args, errorc);
	if(ok == -1)
		args = join(args, d);
	return (ok, opts, args);
}

cvtvalues[M,V,C](nil: M, ctxt: C, t: string, cmd: ref Sh->Cmd, args: list of V, errorc: chan of string): (int, list of V, list of V)
	for{
	V =>
		type2s: fn(tc: int): string;
		typec: fn(v: self V): int;
	M =>
		cvt: fn(c: C, v: V, tc: int, errorc: chan of string): V;
	}
{
	cargs: list of V;
	for(i := 0; i < len t; i++){
		tc := t[i];
		if(args == nil){
			report(errorc, sys->sprint("error: missing argument of type %s for %s", V.type2s(tc), sh->cmd2string(cmd)));
			return (-1, cargs, args);
		}
		v := M.cvt(ctxt, hd args, tc, errorc);
		if(v == nil){
			report(errorc, "error: conversion failed for "+sh->cmd2string(cmd));
			return (-1, cargs, tl args);
		}
		cargs = v :: cargs;
		args = tl args;
	}
	return (0, rev(cargs), args);
}

cvtopts[M,V,C](nil: M, ctxt: C, opttype: string, cmd: ref Sh->Cmd, args: list of V, errorc: chan of string): (int, list of (int, list of V), list of V)
	for{
	V =>
		type2s: fn(tc: int): string;
		isstring: fn(v: self V): int;
		typec: fn(v: self V): int;
		gets: fn(v: self V): string;
	M =>
		cvt: fn(c: C, v: V, tc: int, errorc: chan of string): V;
		mks: fn(c: C, s: string): V;
	}
{
	if(opttype == nil)
		return (0, nil, args);
	opts: list of (int, list of V);
getopts:
	while(args != nil){
		s := "";
		if((hd args).isstring()){
			s = (hd args).gets();
			if(s == nil || s[0] != '-' || len s == 1)
				s = nil;
			else if(s == "--"){
				args = tl args;
				s = nil;
			}
		}
		if(s == nil)
			return (0, opts, args);
		s = s[1:];
		while(len s > 0){
			opt := s[0];
			if(((ok, t) := opttypes(opt, opttype)).t0 == -1){
				report(errorc, sys->sprint("error: unknown option -%c for %s", opt, sh->cmd2string(cmd)));
				return (-1, opts, args);
			}
			if(t == nil){
				s = s[1:];
				opts = (opt, nil) :: opts;
			}else{
				if(len s > 1)
					args = M.mks(ctxt, s[1:]) :: tl args;
				else
					args = tl args;
				vl: list of V;
				x: M;
				(ok, vl, args) = cvtvalues(x, ctxt, t, cmd, args, errorc);
				if(ok == -1)
					return (-1, opts, join(vl, args));
				opts = (opt, vl) :: opts;
				continue getopts;
			}
		}
		args = tl args;
	}
	return (0, opts, args);
}

discardlist[V](ol: list of (int, list of V), vl: list of V)
	for{
	V =>
		free: fn(v: self V, used: int);
	}
{
	for(; ol != nil; ol = tl ol)
		for(ovl := (hd ol).t1; ovl != nil; ovl = tl ovl)
			vl = (hd ovl) :: vl;
	for(; vl != nil; vl = tl vl)
		(hd vl).free(0);
}

# true if a module with type sig t1 is compatible with a caller that expects t0
typecompat(t0, t1: string): int
{
	(rt0, at0, ot0) := splittype(t0);
	(rt1, at1, ot1) := splittype(t1);

	if((rt0 != rt1 && rt0 != 'a') || at0 != at1)	# XXX could do better for repeated args.
		return 0;

	for(i := 1; i < len ot0; i++){
		for(j := i; j < len ot0; j++)
			if(ot0[j] == '-')
				break;
		(ok, t) := opttypes(ot0[i], ot1);
		if(ok == -1 || ot0[i+1:j] != t)
			return 0;
		i = j;
	}
	return 1;
}

splittype(t: string): (int, string, string)
{
	if(t == nil)
		return (-1, nil, nil);
	for(i := 1; i < len t; i++)
		if(t[i] == '-')
			break;
	return (t[0], t[1:i], t[i:]);
}

opttypes(opt: int, opts: string): (int, string)
{
	for(i := 1; i < len opts; i++){
		if(opts[i] == opt && opts[i-1] == '-'){
			for(j := i+1; j < len opts; j++)
				if(opts[j] == '-')
					break;
			return (0, opts[i+1:j]);
		}
	}
	return (-1, nil);
}

usage2sig[V](nil: V, u: string): (string, string)
	for{
	V =>
		typename2c: fn(s: string): int;
	}
{
	u[len u] = '\0';

	i := 0;
	t: int;
	tok: string;

	# options
	opts: string;
	for(;;){
		(t, tok, i) = optstok(u, i);
		if(t != '[')
			break;
		o := i;
		(t, tok, i) = optstok(u, i);
		if(t != '-'){
			i = o;
			t = '[';
			break;
		}
		for(j := 0; j < len tok; j++){
			opts[len opts] = '-';
			opts[len opts] = tok[j];
		}
		for(;;){
			(t, tok, i) = optstok(u, i);
			if(t == ']')
				break;
			if(t != 't')
				return (nil, sys->sprint("bad option syntax, got '%c'", t));
			tc := V.typename2c(tok);
			if(tc == -1)
				return (nil, "unknown type: "+tok);
			opts[len opts] = tc;
		}
	}

	# arguments
	args: string;
parseargs:
	for(;;){
		case t {
		'>' =>
			break parseargs;
		'[' =>
			(t, tok, i) = optstok(u, i);
			if(t != 't')
				return (nil, "bad argument syntax");
			tc := V.typename2c(tok);
			if(tc == -1)
				return (nil, "unknown type: "+tok);
			if(((t, nil, i) = optstok(u, i)).t0 != '*')
				return (nil, "bad argument syntax");
			if(((t, nil, i) = optstok(u, i)).t0 != ']')
				return (nil, "bad argument syntax");
			if(((t, nil, i) = optstok(u, i)).t0 != '>')
				return (nil, "bad argument syntax");
			args[len args] = tc;
			args[len args] = '*';
			break parseargs;
		't' =>
			tc := V.typename2c(tok);
			if(tc == -1)
				return (nil, "unknown type: "+tok);
			args[len args] = tc;
			(t, tok, i) = optstok(u, i);
		* =>
			return (nil, "no return type");
		}
	}

	# return type
	(t, tok, i) = optstok(u, i);
	if(t != 't')
		return (nil, "expected return type");
	tc := V.typename2c(tok);
	if(tc == -1)
		return (nil, "unknown type: "+tok);
	r: string;
	r[0] = tc;
	r += args;
	r += opts;
	return (r, nil);
}

optstok(u: string, i: int): (int, string, int)
{
	while(u[i] == ' ')
		i++;
	case u[i] {
	'\0' =>
		return (-1, nil, i);
	'-' =>
		i++;
		if(u[i] == '>')
			return ('>', nil, i+1);
		start := i;
		while((c := u[i]) != '\0'){
			if(c == ']' || c == ' ')
				break;
			i++;
		}
		return ('-', u[start:i], i);
	'[' =>
		return (u[i], nil, i+1);
	']' =>
		return (u[i], nil, i+1);
	'.' =>
		start := i;
		while(u[i] == '.')
			i++;
		if(i - start < 3)
			raise "parse:error at '.'";
		return ('*', nil, i);
	* =>
		start := i;
		while((c := u[i]) != '\0'){
			if(c == ' ' || c == ']' || c == '-' || (c == '.' && u[i+1] == '.'))
				return ('t', u[start:i], i);
			i++;
		}
		return ('t', u[start:i], i);
	}
}

cmdusage[V](nil: V, t: string): string
	for{
	V =>
		type2s: fn(c: int): string;
	}
{
	if(t == nil)
		return "-> bad";
	for(oi := 0; oi < len t; oi++)
		if(t[oi] == '-')
			break;
	s := "";
	if(oi < len t){
		single, multi: string;
		for(i := oi; i < len t - 1;){
			for(j := i + 1; j < len t; j++)
				if(t[j] == '-')
					break;

			optargs := t[i+2:j];
			if(optargs == nil)
				single[len single] = t[i+1];
			else{
				multi += sys->sprint(" [-%c", t[i+1]);
				for (k := 0; k < len optargs; k++)
					multi += " " + V.type2s(optargs[k]);
				multi += "]";
			}
			i = j;
		}
		if(single != nil)
			s += " [-" + single + "]";
		s += multi;
	}
	multi := 0;
	if(oi > 2 && t[oi - 1] == '*'){
		multi = 1;
		oi -= 2;
	}
	for(k := 1; k < oi; k++)
		s += " " + V.type2s(t[k]);
	if(multi)
		s += " [" + V.type2s(t[k]) + "...]";
	s += " -> " + V.type2s(t[0]);
	if(s[0] == ' ')
		s=s[1:];
	return s;
}

Env[V].new(args: list of V, nilval: V): Env[V]
{
	if(args == nil)
		return Env(nil);
	e := Env[V](array[len args] of {* => nilval});
	for(i := 0; args != nil; args = tl args)
		e.items[i++] = hd args;
	return e;
}

Env[V].get(t: self Env, id: int): V
{
	id--;
	if(id < 0 || id >= len t.items)
		return nil;
	x := t.items[id];
	if((y := x.dup()) == nil){
		t.items[id] = nil;
		y = x;
	}
	return y;
}

Env[V].discard(t: self Env)
{
	for(i := 0; i < len t.items; i++)
		t.items[i].free(0);
}

rev[T](x: list of T): list of T
{
	l: list of T;
	for(; x != nil; x = tl x)
		l = hd x :: l;
	return l;
}

# join x to y, leaving result in arbitrary order.
join[T](x, y: list of T): list of T
{
	if(len x > len y)
		(x, y) = (y, x);
	for(; x != nil; x = tl x)
		y = hd x :: y;
	return y;
}
