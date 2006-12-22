implement Shellbuiltin;

include "sys.m";
	sys: Sys;
include "draw.m";
include "sh.m";
	sh: Sh;
	Listnode, Context: import sh;
	myself: Shellbuiltin;

initbuiltin(ctxt: ref Context, shmod: Sh): string
{
	sys = load Sys Sys->PATH;
	sh = shmod;
	myself = load Shellbuiltin "$self";
	if (myself == nil)
		ctxt.fail("bad module", sys->sprint("expr: cannot load self: %r"));

	ctxt.addsbuiltin("expr", myself);
	ctxt.addbuiltin("ntest", myself);
	return nil;
}

whatis(nil: ref Sh->Context, nil: Sh, nil: string, nil: int): string
{
	return nil;
}

getself(): Shellbuiltin
{
	return myself;
}

EQ, GT, LT, GE, LE, PLUS, MINUS, DIVIDE, AND, TIMES, MOD,
OR, XOR, UMINUS, SHL, SHR, NOT, BNOT, NEQ, REP, SEQ: con iota;

runbuiltin(ctxt: ref Sh->Context, nil: Sh,
			cmd: list of ref Sh->Listnode, nil: int): string
{
	case (hd cmd).word {
	"ntest" =>
		if (len cmd != 2)
			ctxt.fail("usage", "usage: ntest n");
		if (big (hd tl cmd).word == big 0)
			return "false";
	}
	return nil;
}

runsbuiltin(ctxt: ref Sh->Context, nil: Sh,
			cmd: list of ref Sh->Listnode): list of ref Listnode
{
	# only one sbuiltin: expr.
	stk: list of big;
	lastop := -1;
	lastn := -1;
	lastname := "";
	radix: int;
	(cmd, radix) = opts(ctxt, tl cmd);
	for (; cmd != nil; cmd = tl cmd) {
		w := (hd cmd).word;
		op := -1;
		nops := 2;
		case w {
		"+" =>
			op = PLUS; 
		"-" =>
			op = MINUS;
		"x" or "*" or "×" =>
			op = TIMES;
		"/" =>
			op = DIVIDE;
		"%" =>
			op = MOD;
		"and" =>
			op = AND;
		"or" =>
			op = OR;
		"xor" =>
			op = XOR;
		"_"=>
			(op, nops) = (UMINUS, 1);
		"<<" or "shl" =>
			op = SHL;
		">>" or "shr" =>
			op = SHR;
		"=" or "==" or "eq" =>
			op = EQ;
		"!=" or "neq" =>
			op = NEQ;
		">" or "gt" =>
			op = GT;
		"<" or "lt" =>
			op = LT;
		">=" or "ge" =>
			op = GE;
		"<=" or "le" =>
			op = LE;
		"!" or "not" =>
			(op, nops) = (NOT, 1);
		"~" =>
			(op, nops) = (BNOT, 1);
		"rep" =>
			(op, nops) = (REP, 0);
		"seq" =>
			(op, nops) = (SEQ, 2);
		}
		if (op == -1)
			stk = makenum(ctxt, w) :: stk;
		else 
			stk = operator(ctxt, stk, op, nops, lastop, lastn, w, lastname);
		lastop = op;
		lastn = nops;
		lastname = w;
	}
	r: list of ref Listnode;
	for (; stk != nil; stk = tl stk)
		r = ref Listnode(nil, big2string(hd stk, radix)) :: r;
	return r;
}

opts(ctxt: ref Context, cmd: list of ref Listnode): (list of ref Listnode, int)
{
	radix := 10;
	if (cmd == nil)
		return (nil, 10);
	w := (hd cmd).word;
	if (len w < 2)
		return (cmd, 10);
	if (w[0] != '-' || (w[1] >= '0' && w[1] <= '9'))
		return (cmd, 10);
	if (w[1] != 'r')
		ctxt.fail("usage", "usage: expr [-r radix] [arg...]");
	if (len w > 2)
		w = w[2:];
	else {
		if (tl cmd == nil)
			ctxt.fail("usage", "usage: expr [-r radix] [arg...]");
		cmd = tl cmd;
		w = (hd cmd).word;
	}
	r := int w;
	if (r <= 0 || r > 36)
		ctxt.fail("usage", "expr: invalid radix " + string r);
	return (tl cmd, int w);
}

operator(ctxt: ref Context, stk: list of big, op, nops, lastop, lastn: int,
		opname, lastopname: string): list of big
{
	al: list of big;
	for (i := 0; i < nops; i++) {
		if (stk == nil)
			ctxt.fail("empty stack",
				sys->sprint("expr: empty stack on op '%s'", opname));
		al = hd stk :: al;
		stk = tl stk;
	}
	return oper(ctxt, al, op, lastop, lastn, lastopname, stk);
}

# args are in reverse order
oper(ctxt: ref Context, args: list of big, op, lastop, lastn: int,
		lastopname: string, stk: list of big): list of big
{
	if (op == REP) {
		if (lastop == -1 || lastop == SEQ || lastn != 2)
			ctxt.fail("usage", "expr: bad operator for rep");
		if (stk == nil || tl stk == nil)
			return stk;
		while (tl stk != nil)
			stk = operator(ctxt, stk, lastop, 2, -1, -1, lastopname, nil);
		return stk;
	}
	n2 := big 0;
	n1 := hd args;
	if (tl args != nil)
		n2 = hd tl args;
	r := big 0;
	case op {
	EQ =>	r = big(n1 == n2);
	NEQ =>	r = big(n1 != n2);
	GT =>	r = big(n1 > n2);
	LT =>	r = big(n1 < n2);
	GE =>	r = big(n1 >= n2);
	LE =>	r = big(n1 <= n2);
	PLUS =>	r = big(n1 + n2);
	MINUS =>	r = big(n1 - n2);
	NOT	 =>	r = big(n1 != big 0);
	DIVIDE =>
			if (n2 == big 0)
				ctxt.fail("divide by zero", "expr: division by zero");
			r = n1 / n2;
	MOD =>
			if (n2 == big 0)
				ctxt.fail("divide by zero", "expr: division by zero");
			r = n1 % n2;
	TIMES =>	r = n1 * n2;
	AND =>	r = n1 & n2;
	OR =>	r = n1 | n2;
	XOR =>	r = n1 ^ n2;
	UMINUS => r = -n1;
	BNOT =>	r = ~n1;
	SHL =>	r = n1 << int n2;
	SHR =>	r = n1 >> int n2;
	SEQ =>	return seq(n1, n2, stk);
	}
	return r :: stk;
}

seq(n1, n2: big, stk: list of big): list of big
{
	incr := big 1;
	if (n2 < n1)
		incr = big -1;
	for (; n1 != n2; n1 += incr)
		stk = n1 :: stk;
	return n1 :: stk;
}

makenum(ctxt: ref Context, s: string): big
{
	if (s == nil || (s[0] != '-' && (s[0] < '0' || s[0] > '9')))
		ctxt.fail("usage", sys->sprint("expr: unknown operator '%s'", s));

	t := s;	
	if (neg := s[0] == '-')
		s = s[1:];
	radix := 10;
	for (i := 0; i < len s && i < 3; i++) {
		if (s[i] == 'r') {
			radix = int s;
			s = s[i+1:];
			break;
		}
	}
	if (radix == 10)
		return big t;
	if (radix == 0 || radix > 36)
		ctxt.fail("usage", "expr: bad number " + t);
	n := big 0;
	for (i = 0; i < len s; i++) {
		if ('0' <= s[i] && s[i] <= '9')
			n = (n * big radix) + big(s[i] - '0');
		else if ('a' <= s[i] && s[i] < 'a' + radix - 10)
			n = (n * big radix) + big(s[i] - 'a' + 10);
		else if ('A' <= s[i] && s[i]  < 'A' + radix - 10)
			n = (n * big radix) + big(s[i] - 'A' + 10);
		else
			break;
	}
	if (neg)
		return -n;
	return n;
}

big2string(n: big, radix: int): string
{
	if (neg := n < big 0) {
		n = -n;
	}
	s := "";
	do {
		c: int;
		d := int (n % big radix);
		if (d < 10)
			c = '0' + d;
		else
			c = 'a' + d - 10;
		s[len s] = c;
		n /= big radix;
	} while (n > big 0);
	t := s;
	for (i := len s - 1; i >= 0; i--)
		t[len s - 1 - i] = s[i];
	if (radix != 10)
		t = string radix + "r" + t;
	if (neg)
		return "-" + t;
	return t;
}
