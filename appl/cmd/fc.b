implement Fc;
include "sys.m";
	sys: Sys;
include "draw.m";
include "math.m";
	math: Math;
include "string.m";
	str: String;
include "regex.m";
	regex: Regex;

Fc: module {
	init: fn(nil: ref Draw->Context, argv: list of string);
};


UNARY, BINARY, SPECIAL: con iota;

oSWAP, oDUP, oREP, oSUM, oPRNUM, oMULT,
oPLUS, oMINUS, oDIV, oDIVIDE, oMOD, oSHIFTL, oSHIFTR,
oAND, oOR, oXOR, oNOT, oUMINUS, oFACTORIAL,
oPOW, oHYPOT, oATAN2, oJN, oYN, oSCALBN, oCOPYSIGN,
oFDIM, oFMIN, oFMAX, oNEXTAFTER, oREMAINDER, oFMOD,
oPOW10, oSQRT, oEXP, oEXPM1, oLOG, oLOG10, oLOG1P,
oCOS, oCOSH, oSIN, oSINH, oTAN, oTANH, oACOS, oASIN, oACOSH,
oASINH, oATAN, oATANH, oERF, oERFC,
oJ0, oJ1, oY0, oY1, oILOGB, oFABS, oCEIL,
oFLOOR, oFINITE, oISNAN, oRINT, oLGAMMA, oMODF,
oDEG, oRAD: con iota;
Op: adt {
	name: string;
	kind:	int;
	op: int;
};

ops := array[] of {
Op
("swap",	SPECIAL, oSWAP),
("dup",		SPECIAL, oDUP),
("rep",		SPECIAL, oREP),
("sum",		SPECIAL, oSUM),
("p",			SPECIAL, oPRNUM),
("x",			BINARY, oMULT),
("×",			BINARY, oMULT),
("pow",		BINARY, oPOW),
("xx",		BINARY, oPOW),
("+",			BINARY, oPLUS),
("-",			BINARY, oMINUS),
("/",			BINARY, oDIVIDE),
("div",		BINARY, oDIV),
("%",			BINARY, oMOD),
("shl",		BINARY, oSHIFTL),
("shr",		BINARY, oSHIFTR),
("and",		BINARY, oAND),
("or",		BINARY, oOR),
("⋀",			BINARY, oAND),
("⋁",			BINARY, oOR),
("xor",		BINARY, oXOR),
("not",		UNARY, oNOT),
("_",			UNARY, oUMINUS),
("factorial",	UNARY, oFACTORIAL),
("!",			UNARY, oFACTORIAL),
("pow",		BINARY, oPOW),
("hypot",		BINARY, oHYPOT),
("atan2",		BINARY, oATAN2),
("jn",			BINARY, oJN),
("yn",		BINARY, oYN),
("scalbn",		BINARY, oSCALBN),
("copysign",	BINARY, oCOPYSIGN),
("fdim",		BINARY, oFDIM),
("fmin",		BINARY, oFMIN),
("fmax",		BINARY, oFMAX),
("nextafter",	BINARY, oNEXTAFTER),
("remainder",	BINARY, oREMAINDER),
("fmod",		BINARY, oFMOD),
("pow10",		UNARY, oPOW10),
("sqrt",		UNARY, oSQRT),
("exp",		UNARY, oEXP),
("expm1",		UNARY, oEXPM1),
("log",		UNARY, oLOG),
("log10",		UNARY, oLOG10),
("log1p",		UNARY, oLOG1P),
("cos",		UNARY, oCOS),
("cosh",		UNARY, oCOSH),
("sin",		UNARY, oSIN),
("sinh",		UNARY, oSINH),
("tan",		UNARY, oTAN),
("tanh",		UNARY, oTANH),
("acos",		UNARY, oACOS),
("asin",		UNARY, oASIN),
("acosh",		UNARY, oACOSH),
("asinh",		UNARY, oASINH),
("atan",		UNARY, oATAN),
("atanh",		UNARY, oATANH),
("erf",		UNARY, oERF),
("erfc",		UNARY, oERFC),
("j0",			UNARY, oJ0),
("j1",			UNARY, oJ1),
("y0",		UNARY, oY0),
("y1",		UNARY, oY1),
("ilogb",		UNARY, oILOGB),
("fabs",		UNARY, oFABS),
("ceil",		UNARY, oCEIL),
("floor",		UNARY, oFLOOR),
("finite",		UNARY, oFINITE),
("isnan",		UNARY, oISNAN),
("rint",		UNARY, oRINT),
("rad",		UNARY, oRAD),
("deg",		UNARY, oDEG),
("lgamma",	SPECIAL, oLGAMMA),
("modf",		SPECIAL, oMODF),
};

nHEX, nBINARY, nOCTAL, nRADIX1, nRADIX2, nREAL, nCHAR: con iota;
pats0 := array[] of {
nHEX => "-?0[xX][0-9a-fA-F]+",
nBINARY => "-?0[bB][01]+",
nOCTAL => "-?0[0-7]+",
nRADIX1 => "-?[0-9][rR][0-8]+",
nRADIX2 => "-?[0-3][0-9][rR][0-9a-zA-Z]+",
nREAL => "-?(([0-9]+(\\.[0-9]+)?)|([0-9]*(\\.[0-9]+)))([eE]-?[0-9]+)?",
nCHAR => "@.",
};
RADIX, ANNOTATE, CHAR: con 1 << (iota + 10);

outbase := 10;
pats: array of Regex->Re;
stack: list of real;
last_op: Op;
stderr: ref Sys->FD;

usage()
{
	sys->fprint(stderr,
		"usage: fc [-xdbB] [-r radix] <postfix expression>\n" +
		"option specifies output format:\n" +
		"\t-d decimal (default)\n" +
		"\t-x hex\n" +
		"\t-o octal\n" +
		"\t-b binary\n" +
		"\t-B annotated binary\n" +
		"\t-c character\n" +
		"\t-r <radix> specified base in Limbo 99r9999 format\n" +
		"operands are decimal(default), hex(0x), octal(0), binary(0b), radix(99r)\n");
	sys->fprint(stderr, "operators are:\n");
	for (i := 0; i < len ops; i++)
		sys->fprint(stderr, "%s ", ops[i].name);
	sys->fprint(stderr, "\n");
	raise "fail:usage";
}

init(nil: ref Draw->Context, argv: list of string)
{
	sys = load Sys Sys->PATH;
	stderr = sys->fildes(2);
	math = load Math Math->PATH;
	regex = load Regex Regex->PATH;
	if (regex == nil) {
		sys->fprint(stderr, "fc: cannot load %s: %r\n", Regex->PATH);
		raise "fail:error";
	}

	initpats();

	if (argv == nil || tl argv == nil)
		return;
	argv = tl argv;
	a := hd argv;
	if (len a > 1 && a[0] == '-' && number(a).t0 == 0) {
		case a[1] {
		'd' =>
			outbase = 10;
		'x' =>
			outbase = 16;
		'o' =>
			outbase = 8;
		'b' =>
			outbase = 2;
		'c' =>
			outbase = CHAR;
		'r' =>
			r := 0;
			if (len a > 2)
				r = int a[2:];
			else if (tl argv == nil)
				usage();
			else {
				argv = tl argv;
				r = int hd argv;
			}
			if (r < 2 || r > 36)
				usage();
			outbase = r | RADIX;
		'B' =>
			outbase = 2 | ANNOTATE;
		* =>
			sys->fprint(stderr, "fc: unknown option -%c\n", a[1]);
			usage();
		}
		argv = tl argv;
	}

	math->FPcontrol(0, Math->INVAL|Math->ZDIV|Math->OVFL|Math->UNFL|Math->INEX);

	for (; argv != nil; argv = tl argv) {
		(ok, x) := number(hd argv);
		if (ok)
			stack = x :: stack;
		else {
			op := find(hd argv);
			exec(op);
			last_op = op;
		}
	}

	sp: list of real;
	for (; stack != nil; stack = tl stack)
		sp = hd stack :: sp;

	# print stack bottom first
	for (; sp != nil; sp = tl sp)
		printnum(hd sp);
}

printnum(n: real)
{
	case outbase {
	CHAR =>
		sys->print("@%c\n", int n);
	2 =>
		sys->print("%s\n", binary(big n));
	2 | ANNOTATE =>
		sys->print("%s\n", annotatebinary(big n));
	8 =>
		sys->print("%#bo\n", big n);
	10 =>
		sys->print("%g\n", n);
	16 =>
		sys->print("%#bx\n", big n);
	* =>
		if ((outbase & RADIX) == 0)
			error("unknown output base " + string outbase);
		sys->print("%s\n", big2string(big n, outbase & ~RADIX));
	}
}

# convert to binary string, keeping multiples of 8 digits.
binary(n: big): string
{
	s := "0b";
	for (j := 7; j > 0; j--)
		if ((n & (big 16rff << (j * 8))) != big 0)
			break;
	for (i := 63; i >= 0; i--)
		if (i / 8 <= j)
			s[len s] = (int (n >> i) & 1) + '0';
	return s;
}

annotatebinary(n: big): string
{
	s := binary(n);
	a := s + "\n  ";
	ndig := len s - 2;
	for (i := ndig - 1; i >= 0; i--)
		a[len a] = (i % 10) + '0';
	if (ndig < 10)
		return a;
	a += "\n  ";
	for (i = ndig - 1; i >= 10; i--) {
		if (i % 10 == 0)
			a[len a] = (i / 10) + '0';
		else
			a[len a] = ' ';
	}
	return a;
}

find(name: string): Op
{
	# XXX could do binary search here if we weren't a lousy performer anyway
	for (i := 0; i < len ops; i++)
		if (name == ops[i].name)
			break;
	if (i == len ops)
		error("invalid operator '" + name + "'");
	return ops[i];
}

exec(op: Op)
{
	case op.kind {
	UNARY =>
		unaryop(op.name, op.op);
	BINARY =>
		binaryop(op.name, op.op);
	SPECIAL =>
		specialop(op.name, op.op);
	}
}

unaryop(name: string, op: int)
{
	assure(1, name);
	v := hd stack;
	case op {
	oNOT =>
		v = real !(int v);
	oUMINUS =>
		v = -v;
	oFACTORIAL =>
		n := int v;
		v = 1.0;
		while (n > 0)
			v *= real n--;
	oPOW10 =>
		v = math->pow10(int v);
	oSQRT =>
		v = math->sqrt(v);
	oEXP =>
		v = math->exp(v);
	oEXPM1 =>
		v = math->expm1(v);
	oLOG =>
		v = math->log(v);
	oLOG10 =>
		v = math->log10(v);
	oLOG1P =>
		v = math->log1p(v);
	oCOS =>
		v = math->cos(v);
	oCOSH =>
		v = math->cosh(v);
	oSIN =>
		v = math->sin(v);
	oSINH =>
		v = math->sinh(v);
	oTAN =>
		v = math->tan(v);
	oTANH =>
		v = math->tanh(v);
	oACOS =>
		v = math->acos(v);
	oASIN =>
		v = math->asin(v);
	oACOSH =>
		v = math->acosh(v);
	oASINH =>
		v = math->asinh(v);
	oATAN =>
		v = math->atan(v);
	oATANH =>
		v = math->atanh(v);
	oERF =>
		v = math->erf(v);
	oERFC =>
		v = math->erfc(v);
	oJ0 =>
		v = math->j0(v);
	oJ1 =>
		v = math->j1(v);
	oY0 =>
		v = math->y0(v);
	oY1 =>
		v = math->y1(v);
	oILOGB =>
		v = real math->ilogb(v);
	oFABS =>
		v = math->fabs(v);
	oCEIL =>
		v = math->ceil(v);
	oFLOOR =>
		v = math->floor(v);
	oFINITE =>
		v = real math->finite(v);
	oISNAN =>
		v = real math->isnan(v);
	oRINT =>
		v = math->rint(v);
	oRAD =>
		v = (v / 360.0) * 2.0 * Math->Pi;
	oDEG =>
		v = v / (2.0 * Math->Pi) * 360.0;
	* =>
		error("unknown unary operator '" + name + "'");
	}
	stack = v :: tl stack;
}

binaryop(name: string, op: int)
{
	assure(2, name);
	v1 := hd stack;
	v0 := hd tl stack;
	case op {
	oMULT =>
		v0 = v0 * v1;
	oPLUS =>
		v0 = v0 + v1;
	oMINUS =>
		v0 = v0 - v1;
	oDIVIDE =>
		v0 = v0 / v1;
	oDIV =>
		v0 = real (big v0 / big v1);
	oMOD =>
		v0 = real (big v0 % big v1);
	oSHIFTL =>
		v0 = real (big v0 << int v1);
	oSHIFTR =>
		v0 = real (big v0 >> int v1);
	oAND =>
		v0 = real (big v0 & big v1);
	oOR =>
		v0 = real (big v0 | big v1);
	oXOR =>
		v0 = real (big v0 ^ big v1);
	oPOW =>
		v0 = math->pow(v0, v1);
	oHYPOT =>
		v0 = math->hypot(v0, v1);
	oATAN2 =>
		v0 = math->atan2(v0, v1);
	oJN =>
		v0 = math->jn(int v0, v1);
	oYN =>
		v0 = math->yn(int v0, v1);
	oSCALBN =>
		v0 = math->scalbn(v0, int v1);
	oCOPYSIGN =>
		v0 = math->copysign(v0, v1);
	oFDIM =>
		v0 = math->fdim(v0, v1);
	oFMIN =>
		v0 = math->fmin(v0, v1);
	oFMAX =>
		v0 = math->fmax(v0, v1);
	oNEXTAFTER =>
		v0 = math->nextafter(v0, v1);
	oREMAINDER =>
		v0 = math->remainder(v0, v1);
	oFMOD =>
		v0 = math->fmod(v0, v1);
	* =>
		error("unknown binary operator '" + name + "'");
	}
	stack = v0 :: tl tl stack;
}

specialop(name: string, op: int)
{
	case op {
	oSWAP =>
		assure(2, name);
		stack = hd tl stack :: hd stack :: tl tl stack;
	oDUP =>
		assure(1, name);
		stack = hd stack :: stack;
	oREP =>
		if (last_op.kind != BINARY)
			error("invalid operator '" + last_op.name + "' for rep");
		while (stack != nil && tl stack != nil)
			exec(last_op);
	oSUM =>
		for (sum := 0.0; stack != nil; stack = tl stack)
			sum += hd stack;
		stack = sum :: nil;
	oPRNUM =>
		assure(1, name);
		printnum(hd stack);
		stack = tl stack;
	oLGAMMA =>
		assure(1, name);
		(s, lg) := math->lgamma(hd stack);
		stack = lg :: real s :: tl stack;
	oMODF =>
		assure(1, name);
		(i, r) := math->modf(hd stack);
		stack = r :: real i :: tl stack;
	* =>
		error("unknown operator '" + name + "'");
	}
}

initpats()
{
	pats = array[len pats0] of Regex->Re;
	for (i := 0; i < len pats0; i++) {
		(re, e) := regex->compile("^" + pats0[i] + "$", 0);
		if (re == nil) {
			sys->fprint(stderr, "fc: bad number pattern '^%s$': %s\n", pats0[i], e);
			raise "fail:error";
		}
		pats[i] = re;
	}
}

number(s: string): (int, real)
{
	case s {
	"pi" or
	"π" =>
		return (1, Math->Pi);
	"e" =>
		return (1, 2.71828182845904509);
	"nan" or
	"NaN" =>
		return (1, Math->NaN);
	"-nan" or
	"-NaN" =>
		return (1, -Math->NaN);
	"infinity" or
	"Infinity" or
	"∞" =>
		return (1, Math->Infinity);
	"-infinity" or
	"-Infinity" or
	"-∞" =>
		return (1, -Math->Infinity);
	"eps" or
	"macheps" =>
		return (1, Math->MachEps);
	}
	for (i := 0; i < len pats; i++) {
		if (regex->execute(pats[i], s) != nil)
			break;
	}
	case i {
	nHEX =>
		return base(s, 2, 16);
	nBINARY =>
		return base(s, 2, 2);
	nOCTAL =>
		return base(s, 1, 8);
	nRADIX1 =>
		return base(s, 2, int s);
	nRADIX2 =>
		return base(s, 3, int s);
	nREAL =>
		return (1, real s);
	nCHAR =>
		return (1, real s[1]);
	}
	return (0, Math->NaN);
}

base(s: string, i: int, radix: int): (int, real)
{
	neg := s[0] == '-';
	if (neg)
		i++;
	n := big 0;
	if (radix == 10)
		n = big s[i:];
	else if (radix == 0 || radix > 36)
		return (0, Math->NaN);
	else {
		for (; i < len s; i++) {
			c := s[i];
			if ('0' <= c && c <= '9')
				n = (n * big radix) + big(c - '0');
			else if ('a' <= c && c < 'a' + radix - 10)
				n = (n * big radix) + big(c - 'a' + 10);
			else if ('A' <= c && c  < 'A' + radix - 10)
				n = (n * big radix) + big(c - 'A' + 10);
			else
				return (0, Math->NaN);
		}
	}
	if (neg)
		n = -n;
	return (1, real n);
}

# stolen from /appl/cmd/sh/expr.b
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

error(e: string)
{
	sys->fprint(stderr, "fc: %s\n", e);
	raise "fail:error";
}

assure(n: int, opname: string)
{
	if (len stack < n)
		error("stack too small for op '" + opname + "'");
}
