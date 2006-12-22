implement Calculator;

include "sys.m";
	sys: Sys;
include "draw.m";
include "arg.m";
	arg: Arg;
include "bufio.m";
	bufio: Bufio;
	Iobuf: import bufio;
include "math.m";
	maths: Math;
include "rand.m";
	rand: Rand;
include "daytime.m";
	daytime: Daytime;

Calculator: module
{
	init: fn(nil: ref Draw->Context, argv: list of string);
};

init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	arg = load Arg Arg->PATH;
	bufio = load Bufio Bufio->PATH;
	maths = load Math Math->PATH;
	rand = load Rand Rand->PATH;
	daytime = load Daytime Daytime->PATH;

	maths->FPcontrol(0, Math->INVAL|Math->ZDIV|Math->OVFL|Math->UNFL|Math->INEX);

	rand->init(daytime->now());
	rand->init(rand->rand(Big)^rand->rand(Big));
	daytime = nil;

	arg->init(args);
	while((c := arg->opt()) != 0){
		case(c){
		'b' =>
			bits = 1;
		'd' =>
			debug = 1;
		's' =>
			strict = 1;
		}
	}
	gargs = args = arg->argv();
	if(args == nil){
		stdin = 1;
		bin = bufio->fopen(sys->fildes(0), Sys->OREAD);
	}
	else if(tl args == nil)
		bin = bufio->open(hd args, Sys->OREAD);

	syms = array[Hash] of ref Sym;

	pushscope();
	for(i := 0; keyw[i].t0 != nil; i++)
		enter(keyw[i].t0, keyw[i].t1);
	for(i = 0; conw[i].t0 != nil; i++)
		adddec(conw[i].t0, Ocon, conw[i].t1, 0);
	for(i = 0; varw[i].t0 != nil; i++)
		adddec(varw[i].t0, Ovar, varw[i].t1, 0);
	for(i = 0; funw[i].t0 != nil; i++)
		adddec(funw[i].t0, Olfun, real funw[i].t1, funw[i].t2);
	
	deg = lookup(Deg).dec;
	pbase = lookup(Base).dec;
	errdec = ref Dec;

	pushscope();
	for(;;){
		e: ref Node;

		{
			t := lex();
			if(t == Oeof)
				break;
			unlex(t);
			ls := lexes;
			e = stat(1);
			ckstat(e, Onothing, 0);
			if(ls == lexes){
				t = lex();
				error(nil, sys->sprint("syntax error near %s", opstring(t)));
				unlex(t);
			}
			consume(Onl);
		}
		exception ex{
			Eeof =>
				e = nil;
				err("premature eof");
				skip();
			"*" =>
				e = nil;
				err(ex);
				skip();
		}
		if(0 && debug)
			prtree(e, 0);
		if(e != nil && e.op != Ofn){
			(k, v) := (Onothing, 0.0);
			{
				(k, v) = estat(e);
			}
			exception ex{
			"*" =>
				e = nil;
				err(ex);
			}
			if(pexp(e))
				printnum(v, "\n");
			if(k == Oexit)
				exit;
		}
	}
	popscope();
	popscope();
}

bits: int;
debug: int;
strict: int;

None: con -2;
Eof: con -1;
Eeof: con "eof";

Hash: con 16;
Big: con 1<<30;
Maxint: con 16r7FFFFFFF;
Nan: con Math->NaN;
Infinity: con Math->Infinity;
Pi: con Math->Pi;
Eps: con 1E-10;
Bigeps: con 1E-2;
Ln2: con 0.6931471805599453;
Ln10: con 2.302585092994046;
Euler: con 2.71828182845904523536;
Gamma: con 0.57721566490153286060;
Phi: con 1.61803398874989484820;

Oeof,
Ostring, Onum, Oident, Ocon, Ovar, Ofun, Olfun,
Oadd, Osub, Omul, Odiv, Omod, Oidiv, Oexp, Oand, Oor, Oxor, Olsh, Orsh,
Oadde, Osube, Omule, Odive, Omode, Oidive, Oexpe, Oande, Oore, Oxore, Olshe, Orshe,
Oeq, One, Ogt, Olt, Oge, Ole,
Oinc, Opreinc, Opostinc, Odec, Opredec, Opostdec,
Oandand, Ooror,
Oexc, Onot, Ofact, Ocom,
Oas, Odas,
Oplus, Ominus, Oinv,
Ocomma, Oscomma, Oquest, Ocolon,
Onand, Onor, Oimp, Oimpby, Oiff,
Olbr, Orbr, Olcbr, Orcbr,  Oscolon, Onl,
Onothing,
Oprint, Oread,
Oif, Oelse, Ofor, Owhile, Odo, Obreak, Ocont, Oexit, Oret, Ofn, Oinclude,
Osigma, Opi, Ocfrac, Oderiv, Ointeg, Osolve,
Olog, Olog10, Olog2, Ologb, Oexpf, Opow, Osqrt, Ocbrt, Ofloor, Oceil, Omin, Omax, Oabs, Ogamma, Osign, Oint, Ofrac, Oround, Oerf, Oatan2, Osin, Ocos, Otan, Oasin, Oacos, Oatan, Osinh, Ocosh, Otanh, Oasinh, Oacosh, Oatanh, Orand,
Olast: con iota;

Binary: con (1<<8);
Preunary:	con (1<<9);
Postunary: con (1<<10);
Assoc: con (1<<11);
Rassoc: con (1<<12);
Prec: con Binary-1;

opss := array[Olast] of
{
	"eof",
	"string",
	"number",
	"identifier",
	"constant",
	"variable",
	"function",
	"library function",
	"+",
	"-",
	"*",
	"/",
	"%",
	"//",
	"&",
	"|",
	"^",
	"<<",
	">>",
	"+=",
	"-=",
	"*=",
	"/=",
	"%=",
	"//=",
	"&=",
	"|=",
	"^=",
	"<<=",
	">>=",
	"==",
	"!=",
	">",
	"<",
	">=",
	"<=",
	"++",
	"++",
	"++",
	"--",
	"--",
	"--",
	"**",
	"&&",
	"||",
	"!",
	"!",
	"!",
	"~",
	"=",
	":=",
	"+",
	"-",
	"1/",
	",",
	",",
	"?",
	":",
	"↑",
	"↓",
	"->",
	"<-",
	"<->",
	"(",
	")",
	"{",
	"}",
	";",
	"\n",
	"",
};

ops := array[Olast] of
{
	Oeof =>	0,
	Ostring =>	17,
	Onum =>	17,
	Oident =>	17,
	Ocon =>	17,
	Ovar =>	17,
	Ofun =>	17,
	Olfun =>	17,
	Oadd =>	12|Binary|Assoc|Preunary,
	Osub =>	12|Binary|Preunary,
	Omul =>	13|Binary|Assoc,
	Odiv =>	13|Binary,
	Omod =>	13|Binary,
	Oidiv =>	13|Binary,
	Oexp =>	14|Binary|Rassoc,
	Oand =>	8|Binary|Assoc,
	Oor =>	6|Binary|Assoc,
	Oxor =>	7|Binary|Assoc,
	Olsh =>	11|Binary,
	Orsh =>	11|Binary,
	Oadde =>	2|Binary|Rassoc,
	Osube =>	2|Binary|Rassoc,
	Omule =>	2|Binary|Rassoc,
	Odive =>	2|Binary|Rassoc,
	Omode =>	2|Binary|Rassoc,
	Oidive =>	2|Binary|Rassoc,
	Oexpe =>	2|Binary|Rassoc,
	Oande =>	2|Binary|Rassoc,
	Oore =>	2|Binary|Rassoc,
	Oxore =>	2|Binary|Rassoc,
	Olshe =>	2|Binary|Rassoc,
	Orshe =>	2|Binary|Rassoc,
	Oeq =>	9|Binary,
	One =>	9|Binary,
	Ogt =>	10|Binary,
	Olt =>	10|Binary,
	Oge =>	10|Binary,
	Ole =>	10|Binary,
	Oinc =>	15|Rassoc|Preunary|Postunary,
	Opreinc =>	15|Rassoc|Preunary,
	Opostinc =>	15|Rassoc|Postunary,
	Odec =>	15|Rassoc|Preunary|Postunary,
	Opredec =>	15|Rassoc|Preunary,
	Opostdec =>	15|Rassoc|Postunary,
	Oandand =>	5|Binary|Assoc,
	Ooror =>	4|Binary|Assoc,
	Oexc =>	15|Rassoc|Preunary|Postunary,
	Onot =>	15|Rassoc|Preunary,
	Ofact =>	15|Rassoc|Postunary,
	Ocom =>	15|Rassoc|Preunary,
	Oas =>	2|Binary|Rassoc,
	Odas =>	2|Binary|Rassoc,
	Oplus =>	15|Rassoc|Preunary,
	Ominus =>	15|Rassoc|Preunary,
	Oinv =>	15|Rassoc|Postunary,
	Ocomma =>	1|Binary|Assoc,
	Oscomma =>	1|Binary|Assoc,
	Oquest =>	3|Binary|Rassoc,
	Ocolon =>	3|Binary|Rassoc,
	Onand =>	8|Binary,
	Onor =>	6|Binary,
	Oimp =>	9|Binary,
	Oimpby =>	9|Binary,
	Oiff =>	10|Binary|Assoc,
	Olbr =>	16,
	Orbr =>	16,
	Onothing =>	0,
};

Deg: con "degrees";
Base: con "printbase";
Limit: con "solvelimit";
Step: con "solvestep";

keyw := array[] of
{
	("include",	Oinclude),
	("if",	Oif),
	("else",	Oelse),
	("for",	Ofor),
	("while",	Owhile),
	("do",	Odo),
	("break",	Obreak),
	("continue",	Ocont),
	("exit",	Oexit),
	("return",	Oret),
	("print",	Oprint),
	("read",	Oread),
	("fn",	Ofn),
	("",	0),
};

conw := array[] of
{
	("π",	Pi),
	("Pi", Pi),
	("e",	Euler),
	("γ",	Gamma),
	("Gamma",	Gamma),
	("φ",	Phi),
	("Phi",	Phi),
	("∞",	Infinity),
	("Infinity",	Infinity),
	("NaN",	Nan),
	("Nan",	Nan),
	("nan",	Nan),
	("",	0.0),
};

varw := array[] of
{
	(Deg, 0.0),
	(Base, 10.0),
	(Limit, 100.0),
	(Step, 1.0),
	("", 0.0),
};

funw := array[] of
{
	("log",	Olog,	1),
	("ln",		Olog,	1),
	("log10",	Olog10,	1),
	("log2",	Olog2,	1),
	("logb",	Ologb,	2),
	("exp",	Oexpf,	1),
	("pow",	Opow,	2),
	("sqrt",	Osqrt,	1),
	("cbrt",	Ocbrt,	1),
	("floor",	Ofloor,	1),
	("ceiling",	Oceil,	1),
	("min",	Omin,	2),
	("max",	Omax,	2),
	("abs",	Oabs,	1),
	("Γ",	Ogamma,	1),
	("gamma",	Ogamma,	1),
	("sign",	Osign,	1),
	("int",	Oint,	1),
	("frac",	Ofrac,	1),
	("round",	Oround,	1),
	("erf",	Oerf,	1),
	("atan2",	Oatan2,	2),
	("sin",	Osin,	1),
	("cos",	Ocos,	1),
	("tan",	Otan,	1),
	("asin",	Oasin,	1),
	("acos",	Oacos,	1),
	("atan",	Oatan,	1),
	("sinh",	Osinh,	1),
	("cosh",	Ocosh,	1),
	("tanh",	Otanh,	1),
	("asinh",	Oasinh,	1),
	("acosh",	Oacosh,	1),
	("atanh",	Oatanh,	1),
	("rand",	Orand,	0),
	("Σ",	Osigma,	3),
	("sigma",	Osigma,	3),
	("Π",	Opi,	3),
	("pi",	Opi,	3),
	("cfrac", Ocfrac,	3),
	("Δ",	Oderiv,	2),
	("differential",	Oderiv,	2),
	("∫",	Ointeg,	3),
	("integral",	Ointeg,	3),
	("solve",	Osolve,	1),
	("",	0,	0),
};

stdin: int;
bin: ref Iobuf;
lineno: int = 1;
file: string;
iostack: list of (int, int, int, string, ref Iobuf);
geof: int;
garg: string;
gargs: list of string;
bufc: int = None;
buft: int = Olast;
lexes: int;
lexval: real;
lexstr: string;
lexsym: ref Sym;
syms: array of ref Sym;
deg: ref Dec;
pbase: ref Dec;
errdec: ref Dec;
inloop: int;
infn: int;

Node: adt
{
	op: int;
	left: cyclic ref Node;
	right: cyclic ref Node;
	val: real;
	str: string;
	dec: cyclic ref Dec;
	src: int;
};

Dec: adt
{
	kind: int;
	scope: int;
	sym: cyclic ref Sym;
	val: real;
	na: int;
	code: cyclic ref Node;
	old: cyclic ref Dec;
	next: cyclic ref Dec;
};

Sym: adt
{
	name: string;
	kind: int;
	dec: cyclic ref Dec;
	next: cyclic ref Sym;
};

opstring(t: int): string
{
	s := opss[t];
	if(s != nil)
		return s;
	for(i := 0; keyw[i].t0 != nil; i++)
		if(t == keyw[i].t1)
			return keyw[i].t0;
	for(i = 0; funw[i].t0 != nil; i++)
		if(t == funw[i].t1)
			return funw[i].t0;
	return s;
}

err(s: string)
{
	sys->print("error: %s\n", s);
}

error(n: ref Node, s: string)
{
	if(n != nil)
		lno := n.src;
	else
		lno = lineno;
	s = sys->sprint("line %d: %s", lno, s);
	if(file != nil)
		s = sys->sprint("file %s: %s", file, s);
	raise s;
}

fatal(s: string)
{
	sys->print("fatal: %s\n", s);
	exit;
}

stack(s: string, f: ref Iobuf)
{
	iostack = (bufc, buft, lineno, file, bin) :: iostack;
	bufc = None;
	buft = Olast;
	lineno = 1;
	file = s;
	bin = f;
}

unstack()
{
	(bufc, buft, lineno, file, bin) = hd iostack;
	iostack = tl iostack;
}

doinclude(s: string)
{
	f := bufio->open(s, Sys->OREAD);
	if(f == nil)
		error(nil, sys->sprint("cannot open %s", s));
	stack(s, f);
}

getc(): int
{
	if((c := bufc) != None)
		bufc = None;
	else if(bin != nil)
		c = bin.getc();
	else{
		if(garg == nil){
			if(gargs == nil){
				if(geof == 0){
					geof = 1;
					c = '\n';
				}
				else
					c = Eof;
			}
			else{
				garg = hd gargs;
				gargs = tl gargs;
				c = ' ';
			}
		}
		else{
			c = garg[0];
			garg = garg[1: ];
		}
	}
	if(c == Eof && iostack != nil){
		unstack();
		return getc();
	}
	return c;
}

ungetc(c: int)
{
	bufc = c;
}

slash(c: int): int
{
	if(c != '\\')
		return c;
	nc := getc();
	case(nc){
	'b' => return '\b';
	'f' => return '\f';
	'n' => return '\n';
	'r' => return '\r';
	't' => return '\t';
	}
	return nc;
}

lexstring(): int
{
	sp := "";
	while((c := getc()) != '"'){
		if(c == Eof)
			raise Eeof;
		sp[len sp] = slash(c);
	}
	lexstr = sp;
	return Ostring;
}

lexchar(): int
{
	while((c := getc()) != '\''){
		if(c == Eof)
			raise Eeof;
		lexval = real slash(c);
	}
	return Onum;
}

basev(c: int, base: int): int
{
	if(c >= 'a' && c <= 'z')
		c += 10-'a';
	else if(c >= 'A' && c <= 'Z')
		c += 10-'A';
	else if(c >= '0' && c <= '9')
		c -= '0';
	else
		return -1;
	if(c >= base)
		error(nil, "bad digit");
	return c;
}

lexe(base: int): int
{
	neg := 0;
	v := big 0;
	c := getc();
	if(c == '-')
		neg = 1;
	else
		ungetc(c);
	for(;;){
		c = getc();
		cc := basev(c, base);
		if(cc < 0){
			ungetc(c);
			break;
		}
		v = big base*v+big cc;
	}
	if(neg)
		v = -v;
	return int v;
}

lexnum(): int
{
	base := 10;
	exp := 0;
	r := f := e := 0;
	v := big 0;
	c := getc();
	if(c == '0'){
		base = 8;
		c = getc();
		if(c == '.'){
			base = 10;
			ungetc(c);
		}
		else if(c == 'x' || c == 'X')
			base = 16;
		else
			ungetc(c);
	}
	else
		ungetc(c);
	for(;;){
		c = getc();
		if(!r && (c == 'r' || c == 'R')){
			if(f || e)
				error(nil, "bad base");
			r = 1;
			base = int v;
			if(base < 2 || base > 36)
				error(nil, "bad base");
			v = big 0;
			continue;
		}
		if(c == '.'){
			if(f || e)
				error(nil, "bad real");
			f = 1;
			continue;
		}
		if(base == 10 && (c == 'e' || c == 'E')){
			if(e)
				error(nil, "bad E part");
			e = 1;
			exp = lexe(base);
			continue;
		}
		cc := basev(c, base);
		if(cc < 0){
			ungetc(c);
			break;
		}
		v = big base*v+big cc;
		if(f)
			f++;
	}
	lexval = real v;
	if(f)
		lexval /= real base**(f-1);
	if(exp){
		if(exp > 0)
			lexval *= real base**exp;
		else
			lexval *= maths->pow(real base, real exp);
	}
	return Onum;
}

lexid(): int
{
	sp := "";
	for(;;){
		c := getc();
		if(c >= 'a' && c <= 'z' || c >= 'A' && c <= 'Z' || c >= '0' && c <= '9' || c >= 'α' && c <=  'ω' || c >= 'Α' && c <= 'Ω' || c == '_')
			sp[len sp] = c;
		else{
			ungetc(c);
			break;
		}
	}
	lexsym = enter(sp, Oident);
	return lexsym.kind;
}

follow(c: int, c1: int, c2: int): int
{
	nc := getc();
	if(nc == c)
		return c1;
	ungetc(nc);
	return c2;
}

skip()
{
	if((t := buft) != Olast){
		lex();
		if(t == Onl)
			return;
	}
	for(;;){
		c := getc();
		if(c == Eof){
			ungetc(c);
			return;
		}
		if(c == '\n'){
			lineno++;
			return;
		}
	}
}

lex(): int
{
	lexes++;
	if((t := buft) != Olast){
		buft = Olast;
		if(t == Onl)
			lineno++;
		return t;
	}
	for(;;){
		case(c := getc()){
		Eof =>
			return Oeof;
		'#' =>
			while((c = getc()) != '\n'){
				if(c == Eof)
					raise Eeof;
			}
			lineno++;
		'\n' =>
			lineno++;
			return Onl;
		' ' or
		'\t' or
		'\r' or
		'\v' =>
			;
		'"' =>
			return lexstring();
		'\'' =>
			return lexchar();
		'0' to '9' =>
			ungetc(c);
			return lexnum();
		'a' to 'z' or
		'A' to 'Z' or
		'α' to 'ω' or
		'Α' to 'Ω' or
		'_' =>
			ungetc(c);
			return lexid();
		'+' =>
			c = getc();
			if(c == '=')
				return Oadde;
			ungetc(c);
			return follow('+', Oinc, Oadd);
		'-' =>
			c = getc();
			if(c == '=')
				return Osube;
			if(c == '>')
				return Oimp;
			ungetc(c);
			return follow('-', Odec, Osub);
		'*' =>
			c = getc();
			if(c == '=')
				return Omule;
			if(c == '*')
				return follow('=', Oexpe, Oexp);
			ungetc(c);
			return Omul;
		'/' =>
			c = getc();
			if(c == '=')
				return Odive;
			if(c == '/')
				return follow('=', Oidive, Oidiv);
			ungetc(c);
			return Odiv;
		'%' =>
			return follow('=', Omode, Omod);
		'&' =>
			c = getc();
			if(c == '=')
				return Oande;
			ungetc(c);
			return follow('&', Oandand, Oand);
		'|' =>
			c = getc();
			if(c == '=')
				return Oore;
			ungetc(c);
			return follow('|', Ooror, Oor);
		'^' =>
			return follow('=', Oxore, Oxor);
		'=' =>
			return follow('=', Oeq, Oas);
		'!' =>
			return follow('=', One, Oexc);
		'>' =>
			c = getc();
			if(c == '=')
				return Oge;
			if(c == '>')
				return follow('=', Orshe, Orsh);
			ungetc(c);
			return Ogt;
		'<' =>
			c = getc();
			if(c == '=')
				return Ole;
			if(c == '<')
				return follow('=', Olshe, Olsh);
			if(c == '-')
				return follow('>', Oiff, Oimpby);
			ungetc(c);
			return Olt;
		'(' =>
			return Olbr;
		')' =>
			return Orbr;
		'{' =>
			return Olcbr;
		'}' =>
			return Orcbr;
		'~' =>
			return Ocom;
		'.' =>
			ungetc(c);
			return lexnum();
		',' =>
			return Ocomma;
		'?' =>
			return Oquest;
		':' =>
			return follow('=', Odas, Ocolon);
		';' =>
			return Oscolon;
		'↑' =>
			return Onand;
		'↓' =>
			return Onor;
		'∞' =>
			lexval = Infinity;
			return Onum;
		* =>
			error(nil, sys->sprint("bad character %c", c));
		}
	}
}

unlex(t: int)
{
	lexes--;
	buft = t;
	if(t == Onl)
		lineno--;
}

mustbe(t: int)
{
	nt := lex();
	if(nt != t)
		error(nil, sys->sprint("expected %s not %s", opstring(t), opstring(nt)));
}

consume(t: int)
{
	nt := lex();
	if(nt != t)
		unlex(nt);
}

elex(): int
{
	t := lex();
	if(binary(t))
		return t;
	if(hexp(t)){
		unlex(t);
		return Oscomma;
	}
	return t;
}

hexp(o: int): int
{
	return preunary(o) || o == Olbr || atom(o);
}

atom(o: int): int
{
	return o >= Ostring && o <= Olfun;
}

asop(o: int): int
{
	return o == Oas || o == Odas || o >= Oadde && o <= Orshe || o >= Oinc && o <= Opostdec;
}

preunary(o: int): int
{
	return ops[o]&Preunary;
}

postunary(o: int): int
{
	return ops[o]&Postunary;
}

binary(o: int): int
{
	return ops[o]&Binary;
}

prec(o: int): int
{
	return ops[o]&Prec;
}

assoc(o: int): int
{
	return ops[o]&Assoc;
}

rassoc(o: int): int
{
	return ops[o]&Rassoc;
}

preop(o: int): int
{
	case(o){
	Oadd => return Oplus;
	Osub => return Ominus;
	Oinc => return Opreinc;
	Odec => return Opredec;
	Oexc => return Onot;
	}
	return o;
}

postop(o: int): int
{
	case(o){
	Oinc => return Opostinc;
	Odec => return Opostdec;
	Oexc => return Ofact;
	}
	return o;
}

prtree(p: ref Node, in: int)
{
	if(p == nil)
		return;
	for(i := 0; i < in; i++)
		sys->print("    ");
	sys->print("%s ", opstring(p.op));
	case(p.op){
	Ostring =>
		sys->print("%s", p.str);
	Onum =>
		sys->print("%g", p.val);
	Ocon or
	Ovar =>
		sys->print("%s(%g)", p.dec.sym.name, p.dec.val);
	Ofun or
	Olfun =>
		sys->print("%s", p.dec.sym.name);
	}
	sys->print("\n");
	# sys->print(" - %d\n", p.src);
	prtree(p.left, in+1);
	prtree(p.right, in+1);
}

tree(o: int, l: ref Node, r: ref Node): ref Node
{
	p := ref Node;
	p.op = o;
	p.left = l;
	p.right = r;
	p.src = lineno;
	if(asop(o)){
		if(o >= Oadde && o <= Orshe){
			p = tree(Oas, l, p);
			p.right.op += Oadd-Oadde;
		}
	}
	return p;
}

itree(n: int): ref Node
{
	return vtree(real n);
}

vtree(v: real): ref Node
{
	n := tree(Onum, nil, nil);
	n.val = v;
	return n;
}

ltree(s: string, a: ref Node): ref Node
{
	n := tree(Olfun, a, nil);
	n.dec = lookup(s).dec;
	return n;
}

ptree(n: ref Node, p: real): ref Node
{
	if(isinteger(p)){
		i := int p;
		if(i == 0)
			return itree(1);
		if(i == 1)
			return n;
		if(i == -1)
			return tree(Oinv, n, nil);
		if(i < 0)
			return tree(Oinv, tree(Oexp, n, itree(-i)), nil);
	}
	return tree(Oexp, n, vtree(p));
}

iscon(n: ref Node): int
{
	return n.op == Onum || n.op == Ocon;
}

iszero(n: ref Node): int
{
	return iscon(n) && eval(n) == 0.0;
}

isone(n: ref Node): int
{
	return iscon(n) && eval(n) == 1.0;
}

isnan(n: ref Node): int
{
	return iscon(n) && maths->isnan(eval(n));
}

isinf(n: ref Node): int
{
	return iscon(n) && (v := eval(n)) == Infinity || v == -Infinity;
}

stat(scope: int): ref Node
{
	e1, e2, e3, e4: ref Node;

	consume(Onl);
	t := lex();
	case(t){
	Olcbr =>
		if(scope)
			pushscope();
		for(;;){
			e2 = stat(1);
			if(e1 == nil)
				e1 = e2;
			else
				e1 = tree(Ocomma, e1, e2);
			consume(Onl);
			t = lex();
			if(t == Oeof)
				raise Eeof;
			if(t == Orcbr)
				break;
			unlex(t);
		}
		if(scope)
			popscope();
		return e1;
	Oprint or
	Oread or
	Oret =>
		if(t == Oret && !infn)
			error(nil, "return not in fn");
		e1= tree(t, expr(0, 1), nil);
		consume(Oscolon);
		if(t == Oread)
			allvar(e1.left);
		return e1;
	Oif =>
		# mustbe(Olbr);
		e1 = expr(0, 1);
		# mustbe(Orbr);
		e2 = stat(1);
		e3 = nil;
		consume(Onl);
		t = lex();
		if(t == Oelse)
			e3 = stat(1);
		else
			unlex(t);
		return tree(Oif, e1, tree(Ocomma, e2, e3));
	Ofor =>
		inloop++;
		mustbe(Olbr);
		e1 = expr(0, 1);
		mustbe(Oscolon);
		e2 = expr(0, 1);
		mustbe(Oscolon);
		e3 = expr(0, 1);
		mustbe(Orbr);
		e4 = stat(1);
		inloop--;
		return tree(Ocomma, e1, tree(Ofor, e2, tree(Ocomma, e4, e3)));
	Owhile =>
		inloop++;
		# mustbe(Olbr);
		e1 = expr(0, 1);
		# mustbe(Orbr);
		e2 = stat(1);
		inloop--;
		return tree(Ofor, e1, tree(Ocomma, e2, nil));
	Odo =>
		inloop++;
		e1 = stat(1);
		consume(Onl);
		mustbe(Owhile);
		# mustbe(Olbr);
		e2 = expr(0, 1);
		# mustbe(Orbr);
		consume(Oscolon);
		inloop--;
		return tree(Odo, e1, e2);
	Obreak or
	Ocont or
	Oexit =>
		if((t == Obreak || t == Ocont) && !inloop)
			error(nil, "break/continue not in loop");
		consume(Oscolon);
		return tree(t, nil, nil);
	Ofn =>
		if(infn)
			error(nil, "nested functions not allowed");
		infn++;
		mustbe(Oident);
		s := lexsym;
		d := mkdec(s, Ofun, 1);
		d.code = tree(Ofn, nil, nil);
		pushscope();
		(d.na, d.code.left) = args(0);
		allvar(d.code.left);
		pushparams(d.code.left);
		d.code.right = stat(0);
		popscope();
		infn--;
		return d.code;
	Oinclude =>
		e1 = expr(0, 0);
		if(e1.op != Ostring)
			error(nil, "bad include file");
		consume(Oscolon);
		doinclude(e1.str);
		return nil;
	* =>
		unlex(t);
		e1 = expr(0, 1);
		consume(Oscolon);
		if(debug)
			prnode(e1);
		return e1;
	}
	return nil;
}

ckstat(n: ref Node, parop: int, pr: int)
{
	if(n == nil)
		return;
	pr |= n.op == Oprint;
	ckstat(n.left, n.op, pr);
	ckstat(n.right, n.op, pr);
	case(n.op){
	Ostring =>
		if(!pr || parop != Oprint && parop != Ocomma)
			error(n, "illegal string operation");
	}
}
	
pexp(e: ref Node): int
{
	if(e == nil)
		return 0;
	if(e.op == Ocomma)
		return pexp(e.right);
	return e.op >= Ostring && e.op <= Oiff && !asop(e.op);
}

expr(p: int, zok: int): ref Node
{
	n := exp(p, zok);
	ckexp(n, Onothing);
	return n;
}

exp(p: int, zok: int): ref Node
{
	l := prim(zok);
	if(l == nil)
		return nil;
	while(binary(t := elex()) && (o := prec(t)) >= p){
		if(rassoc(t))
			r := exp(o, 0);
		else
			r = exp(o+1, 0);
		if(t == Oscomma)
			t = Ocomma;
		l = tree(t, l, r);
	}
	if(t != Oscomma)
		unlex(t);
	return l;
}

prim(zok: int): ref Node
{
	p: ref Node;
	na: int;

	t := lex();
	if(preunary(t)){
		t = preop(t);
		return tree(t, exp(prec(t), 0), nil);
	}
	case(t){
	Olbr =>
		p = exp(0, zok);
		mustbe(Orbr);
	Ostring =>
		p = tree(t, nil, nil);
		p.str = lexstr;
	Onum =>
		p = tree(t, nil ,nil);
		p.val = lexval;
	Oident =>
		s := lexsym;
		d := s.dec;
		if(d == nil)
			d = mkdec(s, Ovar, 0);
		case(t = d.kind){
		Ocon or
		Ovar =>
			p = tree(t, nil, nil);
			p.dec = d;
		Ofun or
		Olfun =>
			p = tree(t, nil, nil);
			p.dec = d;
			(na, p.left) = args(prec(t));
			if(!(t == Olfun && d.val == real Osolve && na == 2))
			if(na != d.na)
				error(p, "wrong number of arguments");
			if(t == Olfun){
				case(int d.val){
				Osigma or
				Opi or
				Ocfrac or
				Ointeg =>
					if((op := p.left.left.left.op) != Oas && op != Odas)
						error(p.left, "expression not an assignment");
				Oderiv =>
					if((op := p.left.left.op) != Oas && op != Odas)
						error(p.left, "expression not an assignment");
				}
			}
		}
	* =>
		unlex(t);
		if(!zok)
			error(nil, "missing expression");
		return nil;
	}
	while(postunary(t = lex())){
		t = postop(t);
		p = tree(t, p, nil);
	}
	unlex(t);
	return p;	
}

ckexp(n: ref Node, parop: int)
{
	if(n == nil)
		return;
	o := n.op;
	l := n.left;
	r := n.right;
	if(asop(o))
		var(l);
	case(o){
	Ovar =>
		s := n.dec.sym;
		d := s.dec;
		if(d == nil){
			if(strict)
				error(n, sys->sprint("%s undefined", s.name));
			d = mkdec(s, Ovar, 1);
		}
		n.dec = d;
	Odas =>
		ckexp(r, o);
		l.dec = mkdec(l.dec.sym, Ovar, 1);
	* =>
		ckexp(l, o);
		ckexp(r, o);
		if(o == Oquest && r.op != Ocolon)
			error(n, "bad '?' operator");
		if(o == Ocolon && parop != Oquest)
			error(n, "bad ':' operator");
	}
}

commas(n: ref Node): int
{
	if(n == nil || n.op == Ofun || n.op == Olfun)
		return 0;
	c := commas(n.left)+commas(n.right);
	if(n.op == Ocomma)
		c++;
	return c;
}

allvar(n: ref Node)
{
	if(n == nil)
		return;
	if(n.op == Ocomma){
		allvar(n.left);
		allvar(n.right);
		return;
	}
	var(n);
}

args(p: int): (int, ref Node)
{
	if(!p)
		mustbe(Olbr);
	a := exp(p, 1);
	if(!p)
		mustbe(Orbr);
	na := 0;
	if(a != nil)
		na = commas(a)+1;
	return (na, a);
}

hash(s: string): int
{
	l := len s;
	h := 4104;
	for(i := 0; i < l; i++)
		h = 1729*h ^ s[i];
	if(h < 0)
		h = -h;
	return h&(Hash-1);
}

enter(sp: string, k: int): ref Sym
{
	for(s := syms[hash(sp)]; s != nil; s = s.next){
		if(sp == s.name)
			return s;
	}
	s = ref Sym;
	s.name = sp;
	s.kind = k;
	h := hash(sp);
	s.next = syms[h];
	syms[h] = s;
	return s;
}

lookup(sp: string): ref Sym
{
	return enter(sp, Oident);
}

mkdec(s: ref Sym, k: int, dec: int): ref Dec
{
	d := ref Dec;
	d.kind = k;
	d.val = 0.0;
	d.na = 0;
	d.sym = s;
	d.scope = 0;
	if(dec)
		pushdec(d);
	return d;
}

adddec(sp: string, k: int, v: real, n: int): ref Dec
{
	d := mkdec(enter(sp, Oident), k, 1);
	d.val = v;
	d.na = n;
	return d;
}

scope: int;
curscope: ref Dec;
scopes: list of ref Dec;

pushscope()
{
	scope++;
	scopes = curscope :: scopes;
	curscope = nil;
}

popscope()
{
	popdecs();
	curscope = hd scopes;
	scopes = tl scopes;
	scope--;
}

pushparams(n: ref Node)
{
	if(n == nil)
		return;
	if(n.op == Ocomma){
		pushparams(n.left);
		pushparams(n.right);
		return;
	}
	n.dec = mkdec(n.dec.sym, Ovar, 1);
}

pushdec(d: ref Dec)
{
	if(0 && debug)
		sys->print("dec %s scope %d\n", d.sym.name, scope);
	d.scope = scope;
	s := d.sym;
	if(s.dec != nil && s.dec.scope == scope)
		error(nil, sys->sprint("redeclaration of %s", s.name));
	d.old = s.dec;
	s.dec = d;
	d.next = curscope;
	curscope = d;
}

popdecs()
{
	nd: ref Dec;
	for(d := curscope; d != nil; d = nd){
		d.sym.dec = d.old;
		d.old = nil;
		nd = d.next;
		d.next = nil;
	}
	curscope = nil;
}

estat(n: ref Node): (int, real)
{
	k: int;
	v: real;

	if(n == nil)
		return (Onothing, 0.0);
	l := n.left;
	r := n.right;
	case(n.op){
	Ocomma =>
		(k, v) = estat(l);
		if(k == Oexit || k == Oret || k == Obreak || k == Ocont)
			return (k, v);
		return estat(r);
	Oprint =>
		v = print(l);
		return (Onothing, v);
	Oread =>
		v = read(l);
		return (Onothing, v);
	Obreak or
	Ocont or
	Oexit =>
		return (n.op, 0.0);
	Oret =>
		return (Oret, eval(l));
	Oif =>
		v = eval(l);
		if(int v)
			return estat(r.left);
		else if(r.right != nil)
			return estat(r.right);
		else
			return (Onothing, v);
	Ofor =>
		for(;;){
			v = eval(l);
			if(!int v)
				break;
			(k, v) = estat(r.left);
			if(k == Oexit || k == Oret)
				return (k, v);
			if(k == Obreak)
				break;
			if(r.right != nil)
				v = eval(r.right);
		}
		return (Onothing, v);
	Odo =>
		for(;;){
			(k, v) = estat(l);
			if(k == Oexit || k == Oret)
				return (k, v);
			if(k == Obreak)
				break;
			v = eval(r);
			if(!int v)
				break;
		}
		return (Onothing, v);
	* =>
		return (Onothing, eval(n));
	}
	return (Onothing, 0.0);
}

eval(e: ref Node): real
{
	lv, rv: real;

	if(e == nil)
		return 1.0;
	o := e.op;
	l := e.left;
	r := e.right;
	if(o != Ofun && o != Olfun)
		lv = eval(l);
	if(o != Oandand && o != Ooror && o != Oquest)
		rv = eval(r);
	case(o){
	Ostring =>
		return 0.0;
	Onum =>
		return e.val;
	Ocon or
	Ovar =>
		return e.dec.val;
	Ofun =>
		return call(e.dec, l);
	Olfun =>
		return libfun(int e.dec.val, l);
	Oadd =>
		return lv+rv;
	Osub =>
		return lv-rv;
	Omul =>
		return lv*rv;
	Odiv =>
		return lv/rv;
	Omod =>
		return real (big lv%big rv);
	Oidiv =>
		return real (big lv/big rv);
	Oand =>
		return real (big lv&big rv);
	Oor =>
		return real (big lv|big rv);
	Oxor =>
		return real (big lv^big rv);
	Olsh =>
		return real (big lv<<int rv);
	Orsh =>
		return real (big lv>>int rv);
	Oeq =>
		return real (lv == rv);
	One =>
		return real (lv != rv);
	Ogt =>
		return real (lv > rv);
	Olt =>
		return real (lv < rv);
	Oge =>
		return real (lv >= rv);
	Ole =>
		return real (lv <= rv);
	Opreinc =>
		l.dec.val += 1.0;
		return l.dec.val;
	Opostinc =>
		l.dec.val += 1.0;
		return l.dec.val-1.0;
	Opredec =>
		l.dec.val -= 1.0;
		return l.dec.val;
	Opostdec =>
		l.dec.val -= 1.0;
		return l.dec.val+1.0;
	Oexp =>
		if(isinteger(rv) && rv >= 0.0)
			return lv**int rv;
		return maths->pow(lv, rv);
	Oandand =>
		if(!int lv)
			return lv;
		return eval(r);
	Ooror =>
		if(int lv)
			return lv;
		return eval(r);
	Onot =>
		return real !int lv;
	Ofact =>
		if(isinteger(lv) && lv >= 0.0){
			n := int lv;
			lv = 1.0;
			for(i := 2; i <= n; i++)
				lv *= real i;
			return lv;
		}
		return gamma(lv+1.0);
	Ocom =>
		return real ~big lv;
	Oas or
	Odas =>
		l.dec.val = rv;
		return rv;
	Oplus =>
		return lv;
	Ominus =>
		return -lv;
	Oinv =>
		return 1.0/lv;
	Ocomma =>
		return rv;
	Oquest =>
		if(int lv)
			return eval(r.left);
		else
			return eval(r.right);
	Onand =>
		return real !(int lv&int rv);
	Onor =>
		return real !(int lv|int rv);
	Oimp =>
		return real (!int lv|int rv);
	Oimpby =>
		return real (int lv|!int rv);
	Oiff =>
		return real !(int lv^int rv);
	* =>
		fatal(sys->sprint("case %s in eval", opstring(o)));
	}
	return 0.0;
}

var(e: ref Node)
{
	if(e == nil || e.op != Ovar || e.dec.kind != Ovar)
		error(e, "expected a variable");
}

libfun(o: int, a: ref Node): real
{
	a1, a2: real;

	case(o){
	Osolve =>
		return solve(a);
	Osigma or
	Opi or
	Ocfrac =>
		return series(o, a);
	Oderiv =>
		return differential(a);
	Ointeg =>
		return integral(a);
	}
	v := 0.0;
	if(a != nil && a.op == Ocomma){
		a1 = eval(a.left);
		a2 = eval(a.right);
	}
	else
		a1 = eval(a);
	case(o){
	Olog =>
		v = maths->log(a1);
	Olog10 =>
		v = maths->log10(a1);
	Olog2 =>
		v = maths->log(a1)/maths->log(2.0);
	Ologb =>
		v = maths->log(a1)/maths->log(a2);
	Oexpf =>
		v = maths->exp(a1);
	Opow =>
		v = maths->pow(a1, a2);
	Osqrt =>
		v = maths->sqrt(a1);
	Ocbrt =>
		v = maths->cbrt(a1);
	Ofloor =>
		v = maths->floor(a1);
	Oceil =>
		v = maths->ceil(a1);
	Omin =>
		v = maths->fmin(a1, a2);
	Omax =>
		v = maths->fmax(a1, a2);
	Oabs =>
		v = maths->fabs(a1);
	Ogamma =>
		v = gamma(a1);
	Osign =>
		if(a1 > 0.0)
			v = 1.0;
		else if(a1 < 0.0)
			v = -1.0;
		else
			v = 0.0;
	Oint =>
		(vi, nil) := maths->modf(a1);
		v = real vi;
	Ofrac =>
		(nil, v) = maths->modf(a1);
	Oround =>
		v = maths->rint(a1);
	Oerf =>
		v = maths->erf(a1);
	Osin =>
		v = maths->sin(D2R(a1));
	Ocos =>
		v = maths->cos(D2R(a1));
	Otan =>
		v = maths->tan(D2R(a1));
	Oasin =>
		v = R2D(maths->asin(a1));
	Oacos =>
		v = R2D(maths->acos(a1));
	Oatan =>
		v = R2D(maths->atan(a1));
	Oatan2 =>
		v = R2D(maths->atan2(a1, a2));
	Osinh =>
		v = maths->sinh(a1);
	Ocosh =>
		v = maths->cosh(a1);
	Otanh =>
		v = maths->tanh(a1);
	Oasinh =>
		v = maths->asinh(a1);
	Oacosh =>
		v = maths->acosh(a1);
	Oatanh =>
		v = maths->atanh(a1);
	Orand =>
		v = real rand->rand(Big)/real Big;
	* =>
		fatal(sys->sprint("case %s in libfun", opstring(o)));
	}
	return v;
}

series(o: int, a: ref Node): real
{
	p0, p1, q0, q1: real;

	l := a.left;
	r := a.right;
	if(o == Osigma)
		v := 0.0;
	else if(o == Opi)
		v = 1.0;
	else{
		p0 = q1 = 0.0;
		p1 = q0 = 1.0;
		v = Infinity;
	}
	i := l.left.left.dec;
	ov := i.val;
	i.val = eval(l.left.right);
	eq := 0;
	for(;;){
		rv := eval(l.right);
		if(i.val > rv)
			break;
		lv := v;
		ev := eval(r);
		if(o == Osigma)
			v += ev;
		else if(o == Opi)
			v *= ev;
		else{
			t := ev*p1+p0;
			p0 = p1;
			p1 = t;
			t = ev*q1+q0;
			q0 = q1;
			q1 = t;
			v = p1/q1;
		}
		if(v == lv && rv == Infinity){
			eq++;
			if(eq > 100)
				break;
		}
		else
			eq = 0;
		i.val += 1.0;
	}
	i.val = ov;
	return v;
}

pushe(a: ref Node, l: list of real): list of real
{
	if(a == nil)
		return l;
	if(a.op == Ocomma){
		l = pushe(a.left, l);
		return pushe(a.right, l);
	}
	l = eval(a) :: l;
	return l;
}

pusha(f: ref Node, l: list of real, nl: list of real): (list of real, list of real)
{
	if(f == nil)
		return (l, nl);
	if(f.op == Ocomma){
		(l, nl) = pusha(f.left, l, nl);
		return pusha(f.right, l, nl);
	}
	l = f.dec.val :: l;
	f.dec.val = hd nl;
	return (l, tl nl);
}

pop(f: ref Node, l: list of real): list of real
{
	if(f == nil)
		return l;
	if(f.op == Ocomma){
		l = pop(f.left, l);
		return pop(f.right, l);
	}
	f.dec.val = hd l;
	return tl l;
}

rev(l: list of real): list of real
{
	nl: list of real;
	
	for( ; l != nil; l = tl l)
		nl = hd l :: nl;
	return nl;
}

call(d: ref Dec, a: ref Node): real
{
	l: list of real;

	nl := rev(pushe(a, nil));
	(l, nil) = pusha(d.code.left, nil, nl);
	l = rev(l);
	(k, v) := estat(d.code.right);
	l = pop(d.code.left, l);
	if(k == Oexit)
		exit;
	return v;
}

print(n: ref Node): real
{
	if(n == nil)
		return 0.0;
	if(n.op == Ocomma){
		print(n.left);
		return print(n.right);
	}
	if(n.op == Ostring){
		sys->print("%s", n.str);
		return 0.0;
	}
	v := eval(n);
	printnum(v, "");
	return v;
}

read(n: ref Node): real
{
	bio: ref Iobuf;

	if(n == nil)
		return 0.0;
	if(n.op == Ocomma){
		read(n.left);
		return read(n.right);
	}
	sys->print("%s ? ", n.dec.sym.name);
	if(!stdin){
		bio = bufio->fopen(sys->fildes(0), Sys->OREAD);
		stack(nil, bio);
	}
	lexnum();
	consume(Onl);
	n.dec.val = lexval;
	if(!stdin && bin == bio)
		unstack();
	return n.dec.val;
}

isint(v: real): int
{
	return v >= -real Maxint && v <= real Maxint;
}

isinteger(v: real): int
{
	return v == real int v && isint(v);
}

split(v: real): (int, real)
{
	# v >= 0.0
	n := int v;
	if(real n > v)
		n--;
	return (n, v-real n);
}

n2c(n: int): int
{
	if(n < 10)
		return n+'0';
	return n-10+'a';
}

gamma(v: real): real
{
	(s, lg) := maths->lgamma(v);
	return real s*maths->exp(lg);
}

D2R(a: real): real
{
	if(deg.val != 0.0)
		a *= Pi/180.0;
	return a;
}

R2D(a: real): real
{
	if(deg.val != 0.0)
		a /= Pi/180.0;
	return a;
}

side(n: ref Node): int
{
	if(n == nil)
		return 0;
	if(asop(n.op) || n.op == Ofun)
		return 1;
	return side(n.left) || side(n.right);
}

sametree(n1: ref Node, n2: ref Node): int
{
	if(n1 == n2)
		return 1;
	if(n1 == nil || n2 == nil)
		return 0;
	if(n1.op != n2.op)
		return 0;
	case(n1.op){
	Ostring =>
		return n1.str == n2.str;
	Onum =>
		return n1.val == n2.val;
	Ocon or
	Ovar =>
		return n1.dec == n2.dec;
	Ofun or
	Olfun =>
		return n1.dec == n2.dec && sametree(n1.left, n2.left);
	* =>
		return sametree(n1.left, n2.left) && sametree(n1.right, n2.right);
	}
	return 0;
}

simplify(n: ref Node): ref Node
{
	if(n == nil)
		return nil;
	op := n.op;
	l := n.left = simplify(n.left);
	r := n.right = simplify(n.right);
	if(l != nil && iscon(l) && (r == nil || iscon(r))){
		if(isnan(l))
			return l;
		if(r != nil && isnan(r))
			return r;
		return vtree(eval(n));
	}
	case(op){
		Onum or
		Ocon or
		Ovar or
		Olfun or
		Ocomma =>
			return n;
		Oplus =>
			return l;
		Ominus =>
			if(l.op == Ominus)
				return l.left;
		Oinv =>
			if(l.op == Oinv)
				return l.left;
		Oadd =>
			if(iszero(l))
				return r;
			if(iszero(r))
				return l;
			if(sametree(l, r))
				return tree(Omul, itree(2), l);
		Osub =>
			if(iszero(l))
				return simplify(tree(Ominus, r, nil));
			if(iszero(r))
				return l;
			if(sametree(l, r))
				return itree(0);
		Omul =>
			if(iszero(l))
				return l;
			if(iszero(r))
				return r;
			if(isone(l))
				return r;
			if(isone(r))
				return l;
			if(sametree(l, r))
				return tree(Oexp, l, itree(2));
		Odiv =>
			if(iszero(l))
				return l;
			if(iszero(r))
				return vtree(Infinity);
			if(isone(l))
				return ptree(r, -1.0);
			if(isone(r))
				return l;
			if(sametree(l, r))
				return itree(1);
		Oexp =>
			if(iszero(l))
				return l;
			if(iszero(r))
				return itree(1);
			if(isone(l))
				return l;
			if(isone(r))
				return l;
		* =>
			fatal(sys->sprint("case %s in simplify", opstring(op)));
	}
	return n;
}

deriv(n: ref Node, d: ref Dec): ref Node
{
	if(n == nil)
		return nil;
	op := n.op;
	l := n.left;
	r := n.right;
	case(op){
		Onum or
		Ocon =>
			n = itree(0);
		Ovar =>
			if(d == n.dec)
				n = itree(1);
			else
				n = itree(0);
		Olfun =>
			case(int n.dec.val){
				Olog =>
					n = ptree(l, -1.0);
				Olog10 =>
					n = ptree(tree(Omul, l, vtree(Ln10)), -1.0);
				Olog2 =>
					n = ptree(tree(Omul, l, vtree(Ln2)), -1.0);
				Oexpf =>
					n = n;
				Opow =>
					return deriv(tree(Oexp, l.left, l.right), d);
				Osqrt =>
					return deriv(tree(Oexp, l, vtree(0.5)), d);
				Ocbrt =>
					return deriv(tree(Oexp, l, vtree(1.0/3.0)), d);
				Osin =>
					n = ltree("cos", l);
				Ocos =>
					n = tree(Ominus, ltree("sin", l), nil);
				Otan =>
					n = ptree(ltree("cos", l), -2.0);
				Oasin =>
					n = ptree(tree(Osub, itree(1), ptree(l, 2.0)), -0.5);
				Oacos =>
					n = tree(Ominus, ptree(tree(Osub, itree(1), ptree(l, 2.0)), -0.5), nil);
				Oatan =>
					n = ptree(tree(Oadd, itree(1), ptree(l, 2.0)), -1.0);
				Osinh =>
					n = ltree("cosh", l);
				Ocosh =>
					n = ltree("sinh", l);
				Otanh =>
					n = ptree(ltree("cosh", l), -2.0);
				Oasinh =>
					n = ptree(tree(Oadd, itree(1), ptree(l, 2.0)), -0.5);
				Oacosh =>
					n = ptree(tree(Osub, ptree(l, 2.0), itree(1)), -0.5);
				Oatanh =>
					n = ptree(tree(Osub, itree(1), ptree(l, 2.0)), -1.0);
				* =>
					return vtree(Nan);
			}
			return tree(Omul, n, deriv(l, d));
		Oplus or
		Ominus =>
			n = tree(op, deriv(l, d), nil);
		Oinv =>
			n = tree(Omul, tree(Ominus, ptree(l, -2.0), nil), deriv(l, d));
		Oadd or
		Osub or
		Ocomma =>
			n = tree(op, deriv(l, d), deriv(r, d));
		Omul =>
			n = tree(Oadd, tree(Omul, deriv(l, d), r), tree(Omul, l, deriv(r, d)));
		Odiv =>
			n = tree(Osub, tree(Omul, deriv(l, d), r), tree(Omul, l, deriv(r, d)));
			n = tree(Odiv, n, ptree(r, 2.0));
		Oexp =>
			nn := tree(Oadd, tree(Omul, deriv(l, d), tree(Odiv, r, l)), tree(Omul, ltree("log", l), deriv(r, d)));
			n = tree(Omul, n, nn);
		* =>
			n = vtree(Nan);
	}
	return n;
}

derivative(n: ref Node, d: ref Dec): ref Node
{
	n = simplify(deriv(n, d));
	if(isnan(n))
		error(n, "no derivative");
	if(debug)
		prnode(n);
	return n;
}

newton(f: ref Node, e: ref Node, d: ref Dec, v1: real, v2: real): (int, real)
{
	v := (v1+v2)/2.0;
	lv := 0.0;
	its := 0;
	for(;;){
		lv = v;
		d.val = v;
		v = eval(e);
		# if(v < v1 || v > v2)
		#	return (0, 0.0);
		if(maths->isnan(v))
			return (0, 0.0);
		if(its > 100 || fabs(v-lv) < Eps)
			break;
		its++;
	}
	if(fabs(v-lv) > Bigeps || fabs(eval(f)) > Bigeps)
		return (0, 0.0);
	return (1, v);
}

solve(n: ref Node): real
{
	d: ref Dec;

	if(n == nil)
		return Nan;
	if(n.op == Ocomma){	# solve(..., var)
		var(n.right);
		d = n.right.dec;
		n = n.left;
		if(!varmem(n, d))
			error(n, "variable not in equation");
	}
	else{
		d = findvar(n, nil);
		if(d == nil)
			error(n, "variable missing");
		if(d == errdec)
			error(n, "one variable only required");
	}
	if(n.op == Oeq)
		n.op = Osub;
	dn := derivative(n, d);
	var := tree(Ovar, nil, nil);
	var.dec = d;
	nr := tree(Osub, var, tree(Odiv, n, dn));
	ov := d.val;
	lim := lookup(Limit).dec.val;
	step := lookup(Step).dec.val;
	rval := Infinity;
	d.val = -lim-step;
	v1 := 0.0;
	v2 := eval(n);
	for(v := -lim; v <= lim; v += step){
		d.val = v;
		v1 = v2;
		v2 = eval(n);
		if(maths->isnan(v2))	# v == nan, v <= nan, v >= nan all give 1
			continue;
		if(fabs(v2) < Eps){
			if(v >= -lim && v <= lim && v != rval){
				printnum(v, " ");
				rval = v;
			}
		}
		else if(v1*v2 <= 0.0){
			(f, rv) := newton(n, nr, var.dec, v-step, v);
			if(f && rv >= -lim && rv <= lim && rv != rval){
				printnum(rv, " ");
				rval = rv;
			}
		}
	}
	d.val = ov;
	if(rval == Infinity)
		error(n, "no roots found");
	else
		sys->print("\n");
	return rval;
}

differential(n: ref Node): real
{
	x := n.left.left.dec;
	ov := x.val;
	v := evalx(derivative(n.right, x), x, eval(n.left.right));
	x.val = ov;
	return v;
}

integral(n: ref Node): real
{
	l := n.left;
	r := n.right;
	x := l.left.left.dec;
	ov := x.val;
	a := eval(l.left.right);
	b := eval(l.right);
	h := b-a;
	end := evalx(r, x, a) + evalx(r, x, b);
	odd := even := 0.0;
	oldarea := 0.0;
	area := h*end/2.0;
	for(i := 1; i < 1<<16; i <<= 1){
		even += odd;
		odd = 0.0;
		xv := a+h/2.0;
		for(j := 0; j < i; j++){
			odd += evalx(r, x, xv);
			xv += h;
		}
		h /= 2.0;
		oldarea = area;
		area = h*(end+4.0*odd+2.0*even)/3.0;
		if(maths->isnan(area))
			error(n, "integral not found");
		if(fabs(area-oldarea) < Eps)
			break;
	}
	if(fabs(area-oldarea) > Bigeps)
		error(n, "integral not found");
	x.val = ov;
	return area;
}

evalx(n: ref Node, d: ref Dec, v: real): real
{
	d.val = v;
	return eval(n);
}

findvar(n: ref Node, d: ref Dec): ref Dec
{
	if(n == nil)
		return d;
	d = findvar(n.left, d);
	d = findvar(n.right, d);
	if(n.op == Ovar){
		if(d == nil)
			d = n.dec;
		if(n.dec != d)
			d = errdec;
	}
	return d;
}

varmem(n: ref Node, d: ref Dec): int
{
	if(n == nil)
		return 0;
	if(n.op == Ovar)
		return d == n.dec;
	return varmem(n.left, d) || varmem(n.right, d);
}

fabs(r: real): real
{
	if(r < 0.0)
		return -r;
	return r;
}

cvt(v: real, base: int): string
{
	if(base == 10)
		return sys->sprint("%g", v);
	neg := 0;
	if(v < 0.0){
		neg = 1;
		v = -v;
	}
	if(!isint(v)){
		n := 0;
		lg := maths->log(v)/maths->log(real base);
		if(lg < 0.0){
			(n, nil) = split(-lg);
			v *= real base**n;
			n = -n;
		}
		else{
			(n, nil) = split(lg);
			v /= real base**n;
		}
		s := cvt(v, base) + "E" + string n;
		if(neg)
			s = "-" + s;
		return s;
	}
	(n, f) := split(v);
	s := "";
	do{
		r := n%base;
		n /= base;
		s[len s] = n2c(r);
	}while(n != 0);
	ls := len s;
	for(i := 0; i < ls/2; i++){
		t := s[i];
		s[i] = s[ls-1-i];
		s[ls-1-i] = t;
	}
	if(f != 0.0){
		s[len s] = '.';
		for(i = 0; i < 16 && f != 0.0; i++){
			f *= real base;
			(n, f) = split(f);
			s[len s] = n2c(n);
		}
	}
	s = string base + "r" + s;
	if(neg)
		s = "-" + s;
	return s;
}

printnum(v: real, s: string)
{
	base := int pbase.val;
	if(!isinteger(pbase.val) || base < 2 || base > 36)
		base = 10;
	sys->print("%s%s", cvt(v, base), s);
	if(bits){
		r := array[1] of real;
		b := array[8] of byte;
		r[0] = v;
		maths->export_real(b, r);
		for(i := 0; i < 8; i++)
			sys->print("%2.2x ", int b[i]);
		sys->print("\n");
	}
}

Left, Right, Pre, Post: con 1<<iota;

lspace := array[] of { 0, 0, 2, 3, 4, 5, 0, 0, 0, 9, 10, 0, 0, 0, 0, 0, 0, 0 };
rspace := array[] of { 0, 1, 2, 3, 4, 5, 0, 0, 0, 9, 10, 0, 0, 0, 0, 0, 0, 0 };

preced(op1: int, op2: int, s: int): int
{
	br := 0;
	p1 := prec(op1);
	p2 := prec(op2);
	if(p1 > p2)
		br = 1;
	else if(p1 == p2){
		if(op1 == op2){
			if(rassoc(op1))
				br = s == Left;
			else
				br = s == Right && !assoc(op1);
		}
		else{
			if(rassoc(op1))
				br = s == Left;
			else
				br = s == Right && op1 != Oadd;
			if(postunary(op1) && preunary(op2))
				br = 1;
		}
	}
	return br;
}

prnode(n: ref Node)
{
	pnode(n, Onothing, Pre);
	sys->print("\n");
}

pnode(n: ref Node, opp: int, s: int)
{
	if(n == nil)
		return;
	op := n.op;
	if(br := preced(opp, op, s))
		sys->print("(");
	if(op == Oas && n.right.op >= Oadd && n.right.op <= Orsh && n.left == n.right.left){
		pnode(n.left, op, Left);
		sys->print(" %s ", opstring(n.right.op+Oadde-Oadd));
		pnode(n.right.right, op, Right);
	}
	else if(binary(op)){
		p := prec(op);
		pnode(n.left, op, Left);
		if(lspace[p])
			sys->print(" ");
		sys->print("%s", opstring(op));
		if(rspace[p])
			sys->print(" ");
		pnode(n.right, op, Right);
	}
	else if(op == Oinv){	# cannot print postunary -1
		sys->print("%s", opstring(op));
		pnode(n.left, Odiv, Right);
	}
	else if(preunary(op)){
		sys->print("%s", opstring(op));
		pnode(n.left, op, Pre);
	}
	else if(postunary(op)){
		pnode(n.left, op, Post);
		sys->print("%s", opstring(op));
	}
	else{
		case(op){
		Ostring =>
			sys->print("%s", n.str);
		Onum =>
			sys->print("%g", n.val);
		Ocon or
		Ovar =>
			sys->print("%s", n.dec.sym.name);
		Ofun or
		Olfun =>
			sys->print("%s(", n.dec.sym.name);
			pnode(n.left, Onothing, Pre);
			sys->print(")");
		* =>
			fatal(sys->sprint("bad op %s in pnode()", opstring(op)));
		}
	}
	if(br)
		sys->print(")");
}
