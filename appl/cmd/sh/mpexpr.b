implement Shellbuiltin;

include "sys.m";
	sys: Sys;
include "draw.m";
include "keyring.m";
	keyring: Keyring;
	IPint: import keyring;
include "sh.m";
	sh: Sh;
	Listnode, Context: import sh;
	myself: Shellbuiltin;

Big: type ref IPint;
Zero: Big;
One: Big;
initbuiltin(ctxt: ref Context, shmod: Sh): string
{
	sys = load Sys Sys->PATH;
	keyring = load Keyring Keyring->PATH;
	sh = shmod;
	myself = load Shellbuiltin "$self";
	if (myself == nil)
		ctxt.fail("bad module", sys->sprint("expr: cannot load self: %r"));

	Zero = IPint.inttoip(0);
	One = IPint.inttoip(1);
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
OR, XOR, UMINUS, SHL, SHR, NOT, BNOT, NEQ, REP, SEQ,
BITS, EXPMOD, INVERT, RAND, EXP: con iota;

runbuiltin(ctxt: ref Sh->Context, nil: Sh,
			cmd: list of ref Sh->Listnode, nil: int): string
{
	case (hd cmd).word {
	"ntest" =>
		if (len cmd != 2)
			ctxt.fail("usage", "usage: ntest n");
		if(strtoip(ctxt, (hd tl cmd).word).eq(Zero))
			return "false";
	}
	return nil;
}

runsbuiltin(ctxt: ref Sh->Context, nil: Sh,
			cmd: list of ref Sh->Listnode): list of ref Listnode
{
	# only one sbuiltin: expr.
	stk: list of Big;
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
		"bits" =>
			(op, nops) = (BITS, 1);
		"expmod" =>
			(op, nops) = (EXPMOD, 3);
		"invert" =>
			(op, nops) = (INVERT, 2);
		"rand" =>
			(op, nops) = (RAND, 1);
		"exp" or "xx" or "**" =>
			(op, nops) = (EXP, 2);
		}
		if (op == -1){
			if (w == nil || (w[0] != '-' && (w[0] < '0' || w[0] > '9')))
				ctxt.fail("usage", sys->sprint("expr: unknown operator '%s'", w));
			stk = strtoip(ctxt, w) :: stk;
		}else
			stk = operator(ctxt, stk, op, nops, lastop, lastn, w, lastname);
		lastop = op;
		lastn = nops;
		lastname = w;
	}
	r: list of ref Listnode;
	for (; stk != nil; stk = tl stk)
		r = ref Listnode(nil, iptostr(hd stk, radix)) :: r;
	return r;
}

opts(ctxt: ref Context, cmd: list of ref Listnode): (list of ref Listnode, int)
{
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
	if (r <= 0 || (r > 36 && r != 64))
		ctxt.fail("usage", "expr: invalid radix " + string r);
	return (tl cmd, int w);
}

operator(ctxt: ref Context, stk: list of Big, op, nops, lastop, lastn: int,
		opname, lastopname: string): list of Big
{
	al: list of Big;
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
oper(ctxt: ref Context, args: list of Big, op, lastop, lastn: int,
		lastopname: string, stk: list of Big): list of Big
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
	n3 := Zero;
	n2 := Zero;
	n1 := hd args;
	if (tl args != nil){
		n2 = hd tl args;
		if(tl tl args != nil)
			n3 = hd tl tl args;
	}
	r := Zero;
	case op {
	EQ =>	r = mki(n1.eq(n2));
	NEQ =>	r = mki(!n1.eq(n2));
	GT =>	r = mki(n1.cmp(n2) > 0);
	LT =>	r = mki(n1.cmp(n2) < 0);
	GE =>	r = mki(n1.cmp(n2) >= 0);
	LE =>	r = mki(n1.cmp(n2) <= 0);
	PLUS =>	r = n1.add(n2);
	MINUS =>	r = n1.sub(n2);
	NOT	 =>	r = mki(n1.eq(Zero));
	DIVIDE =>
			if (n2.eq(Zero))
				ctxt.fail("divide by zero", "expr: division by zero");
			(r, nil) = n1.div(n2);
	MOD =>
			if (n2.eq(Zero))
				ctxt.fail("divide by zero", "expr: division by zero");
			(nil, r) = n1.div(n2);
	TIMES =>
			r = n1.mul(n2);
	AND =>	r = bitop(ipand, n1, n2);
	OR =>	r = bitop(ipor, n1, n2);
	XOR =>	r = bitop(ipxor, n1, n2);
	UMINUS => r = n1.neg();
	BNOT =>	r = n1.neg().sub(One);
	SHL =>	r = n1.shl(n2.iptoint());
	SHR =>	r = n1.shr(n2.iptoint());
	SEQ =>	return seq(n1, n2, stk);
	BITS =>	r = mki(n1.bits());
	EXPMOD =>	r = n1.expmod(n2, n3);
	EXP =>	r = n1.expmod(n2, nil);
	RAND =>	r = IPint.random(0, n1.iptoint());
	INVERT =>	r = n1.invert(n2);
	}
	return r :: stk;
}

# won't work if op(0, 0) != 0
bitop(op: ref fn(n1, n2: Big): Big, n1, n2: Big): Big
{
	bits := max(n1.bits(), n2.bits());
	return signedmag(op(twoscomp(n1, bits), twoscomp(n2, bits)), bits);
}	

onebits(n: int): Big
{
	return One.shl(n).sub(One);
}

# return a two's complement version of n,
# sign-extended to b bits if negative.
# sign bit is at 1<<b.
twoscomp(n: Big, b: int): Big
{
	if(n.cmp(Zero) >= 0)
		return n;
	return n.not().ori(onebits(b).xor(onebits(n.bits()))).add(One);
}

# return conventional representation of n,
# where n is in two's complement form in b bits.
signedmag(n: Big, b: int): Big
{
	if(n.and(One.shl(b)).eq(Zero))
		return n;
	return n.sub(One).not().and(onebits(b)).neg();
}

max(x, y: int): int
{
	if(x > y)
		return x;
	else
		return y;
}

seq(n1, n2: Big, stk: list of Big): list of Big
{
	incr := mki(1);
	if (n2.cmp(n1) < 0)
		incr = mki(-1);
	for (; !n1.eq(n2); n1 = n1.add(incr))
		stk = n1 :: stk;
	return n1 :: stk;
}

strtoip(ctxt: ref Context, s: string): Big
{
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
		return IPint.strtoip(s, 10);
	if (radix == 0 || (radix > 36 && radix != 64))
		ctxt.fail("usage", "expr: bad number " + t);
	n := Zero;
	case radix {
	10 or 16 or 64 =>
		n = IPint.strtoip(s, radix);
	* =>
		r := mki(radix);
		for (i = 0; i < len s; i++) {
			if ('0' <= s[i] && s[i] <= '9')
				n = n.mul(r).add(mki(s[i] - '0'));
			else if ('a' <= s[i] && s[i] < 'a' + radix - 10)
				n = n.mul(r).add(mki(s[i] - 'a' + 10));
			else if ('A' <= s[i] && s[i]  < 'A' + radix - 10)
				n = n.mul(r).add(mki(s[i] - 'A' + 10));
			else
				break;
		}
	}
	if(neg)
		return n.neg();
	return n;
}

iptostr(n: Big, radix: int): string
{
	neg := n.cmp(Zero) < 0;
	t: string;
	case radix {
	2 or 4 or 16 or 32 =>
		b := n.iptobebytes();
		rbits := log2(radix);
		bits := roundup(n.bits(), rbits);
		for(i := bits - rbits; i >= 0; i -= rbits){
			d := 0;
			for(j := 0; j < rbits; j++)
				d |= getbit(b, i+j) << j;
			t[len t] = digit(d);
		}
	10 =>
		return n.iptostr(radix);
	64 =>
		t = n.iptostr(radix);
		if(neg)
			t = t[1:];
	* =>
		if(neg)
			n = n.neg();
		r := mki(radix);
		s: string;
		do{
			d: Big;
			(n, d) = n.div(r);
			s[len s] = digit(d.iptoint());
		}while(n.cmp(Zero) > 0);
		t = s;
		for (i := len s - 1; i >= 0; i--)
			t[len s - 1 - i] = s[i];
	}
	t = string radix + "r" + t;
	if (neg)
		return "-" + t;
	return t;
}

mki(i: int): Big
{
	return IPint.inttoip(i);
}

b2s(b: array of byte): string
{
	s := "";
	for(i := 0; i < len b; i++)
		s += sys->sprint("%.2x", int b[i]);
	return s;
}

# count from least significant bit.
getbit(b: array of byte, bit: int): int
{
	if((i := bit >> 3) >= len b){
		return 0;
	}else{
		return (int b[len b - i -1] >> (bit&7)) & 1;
	}
}

digit(d: int): int
{
	if(d < 10)
		return '0' + d;
	else
		return 'a' + d - 10;
}

log2(x: int): int
{
	case x {
	2 =>	return 1;
	4 =>	return 2;
	8 => return 3;
	16 => return 4;
	32 => return 5;
	}
	return 0;
}

roundup(n: int, m: int): int
{
	return m*((n+m-1)/m);
}

# these functions are to get around the fact that the limbo compiler isn't
# currently considering ref fn(x: self X, ...) compatible with ref fn(x: X, ...).
ipand(n1, n2: Big): Big
{
	return n1.and(n2);
}

ipor(n1, n2: Big): Big
{
	return n1.ori(n2);
}


ipxor(n1, n2: Big): Big
{
	return n1.xor(n2);
}
