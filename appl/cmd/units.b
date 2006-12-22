implement Units;

#line	2	"units.y"
#
# subject to the Lucent Public License 1.02
#
include "sys.m";
	sys: Sys;

include "draw.m";

include "bufio.m";
	bufio: Bufio;
	Iobuf: import bufio;

include "math.m";
	math: Math;

include "arg.m";

Ndim: con 15;	# number of dimensions
Nvar: con 203;	# hash table size
Maxe: con 695.0;	# log of largest number

Node: adt
{
	val:	real;
	dim:	array of int;	# [Ndim] schar

	mk:	fn(v: real): Node;
	text:	fn(n: self Node): string;
	add:	fn(a: self Node, b: Node): Node;
	sub:	fn(a: self Node, b: Node): Node;
	mul:	fn(a: self Node, b: Node): Node;
	div:	fn(a: self Node, b: Node): Node;
	xpn:	fn(a: self Node, b: int): Node;
	copy: fn(a: self Node): Node;
};
Var: adt
{
	name:	string;
	node:	Node;
};
Prefix: adt
{
	val:	real;
	pname:	string;
};

digval := 0;
fi: ref Iobuf;
fund := array[Ndim] of ref Var;
line: string;
lineno := 0;
linep := 0;
nerrors := 0;
peekrune := 0;
retnode1: Node;
retnode2: Node;
retnode: Node;
sym: string;
vars := array[Nvar] of list of ref Var;
vflag := 0;

YYSTYPE: adt {
	node:	Node;
	var:	ref Var;
	numb:	int;
	val:	real;
};

YYLEX: adt {
	lval: YYSTYPE;
	lex: fn(l: self ref YYLEX): int;
	error: fn(l: self ref YYLEX, msg: string);
};
  
Units: module {

	init:	fn(nil: ref Draw->Context, args: list of string);
VAL: con	57346;
VAR: con	57347;
SUP: con	57348;

};
YYEOFCODE: con 1;
YYERRCODE: con 2;
YYMAXDEPTH: con 200;

#line	203	"units.y"


init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	bufio = load Bufio Bufio->PATH;
	math = load Math Math->PATH;

	arg := load Arg Arg->PATH;
	arg->init(args);
	arg->setusage("units [-v] [file]");
	while((o := arg->opt()) != 0)
		case o {
		'v' => vflag = 1;
		* => arg->usage();
	}
	args = arg->argv();
	arg = nil;

	file := "/lib/units";
	if(args != nil)
		file = hd args;
	fi = bufio->open(file, Sys->OREAD);
	if(fi == nil) {
		sys->fprint(sys->fildes(2), "units: cannot open %s: %r\n", file);
		raise "fail:open";
	}
	lex := ref YYLEX;

	#
	# read the 'units' file to
	# develop a database
	#
	lineno = 0;
	for(;;) {
		lineno++;
		if(readline())
			break;
		if(len line == 0 || line[0] == '/')
			continue;
		peekrune = ':';
		yyparse(lex);
	}

	#
	# read the console to
	# print ratio of pairs
	#
	fi = bufio->fopen(sys->fildes(0), Sys->OREAD);
	lineno = 0;
	for(;;) {
		if(lineno & 1)
			sys->print("you want: ");
		else
			sys->print("you have: ");
		if(readline())
			break;
		peekrune = '?';
		nerrors = 0;
		yyparse(lex);
		if(nerrors)
			continue;
		if(lineno & 1) {
			isspcl: int;
			(isspcl, retnode) = specialcase(retnode2, retnode1);
			if(isspcl)
				sys->print("\tis %s\n", retnode.text());
			else {
				retnode = retnode2.div(retnode1);
				sys->print("\t* %s\n", retnode.text());
				retnode = retnode1.div(retnode2);
				sys->print("\t/ %s\n", retnode.text());
			}
		} else
			retnode2 = retnode1.copy();
		lineno++;
	}
	sys->print("\n");
}

YYLEX.lex(lex: self ref YYLEX): int
{
	c := peekrune;
	peekrune = ' ';

	while(c == ' ' || c == '\t'){
		if(linep >= len line)
			return 0;	# -1?
		c = line[linep++];
	}
	case c {
	'0' to '9' or '.' =>
		digval = c;
		(lex.lval.val, peekrune) = readreal(gdigit, lex);
		return VAL;
	'×' =>
		return '*';
	'÷' =>
		return '/';
	'¹' or
	'ⁱ' =>
		lex.lval.numb = 1;
		return SUP;
	'²' or
	'⁲' =>
		lex.lval.numb = 2;
		return SUP;
	'³' or
	'⁳' =>
		lex.lval.numb = 3;
		return SUP;
	* =>
		if(ralpha(c)){
			sym = "";
			for(i:=0;; i++) {
				sym[i] = c;
				if(linep >= len line){
					c = ' ';
					break;
				}
				c = line[linep++];
				if(!ralpha(c))
					break;
			}
			peekrune = c;
			lex.lval.var = lookup(0);
			return VAR;
		}
	}
	return c;
}

#
# all characters that have some
# meaning. rest are usable as names
#
ralpha(c: int): int
{
	case c {
	0 or
	'+'  or
	'-'  or
	'*'  or
	'/'  or
	'['  or
	']'  or
	'('  or
	')'  or
	'^'  or
	':'  or
	'?'  or
	' '  or
	'\t'  or
	'.'  or
	'|'  or
	'#'  or
	'¹'  or
	'ⁱ'  or
	'²'  or
	'⁲'  or
	'³'  or
	'⁳'  or
	'×'  or
	'÷'  =>
		return 0;
	}
	return 1;
}

gdigit(nil: ref YYLEX): int
{
	c := digval;
	if(c) {
		digval = 0;
		return c;
	}
	if(linep >= len line)
		return 0;
	return line[linep++];
}

YYLEX.error(lex: self ref YYLEX, s: string)
{
	#
	# hack to intercept message from yaccpar
	#
	if(s == "syntax error") {
		lex.error(sys->sprint("syntax error, last name: %s", sym));
		return;
	}
	sys->print("%d: %s\n\t%s\n", lineno, line, s);
	nerrors++;
	if(nerrors > 5) {
		sys->print("too many errors\n");
		raise "fail:errors";
	}
}

yyerror(s: string)
{
	l := ref YYLEX;
	l.error(s);
}

Node.mk(v: real): Node
{
	return (v, array[Ndim] of {* => 0});
}

Node.add(a: self Node, b: Node): Node
{
	c := Node.mk(fadd(a.val, b.val));
	for(i:=0; i<Ndim; i++) {
		d := a.dim[i];
		c.dim[i] = d;
		if(d != b.dim[i])
			yyerror("add must be like units");
	}
	return c;
}

Node.sub(a: self Node, b: Node): Node
{
	c := Node.mk(fadd(a.val, -b.val));
	for(i:=0; i<Ndim; i++) {
		d := a.dim[i];
		c.dim[i] = d;
		if(d != b.dim[i])
			yyerror("sub must be like units");
	}
	return c;
}

Node.mul(a: self Node, b: Node): Node
{
	c := Node.mk(fmul(a.val, b.val));
	for(i:=0; i<Ndim; i++)
		c.dim[i] = a.dim[i] + b.dim[i];
	return c;
}

Node.div(a: self Node, b: Node): Node
{
	c := Node.mk(fdiv(a.val, b.val));
	for(i:=0; i<Ndim; i++)
		c.dim[i] = a.dim[i] - b.dim[i];
	return c;
}

Node.xpn(a: self Node, b: int): Node
{
	c := Node.mk(1.0);
	if(b < 0) {
		b = -b;
		for(i:=0; i<b; i++)
			c = c.div(a);
	} else
		for(i:=0; i<b; i++)
			c = c.mul(a);
	return c;
}

Node.copy(a: self Node): Node
{
	c := Node.mk(a.val);
	c.dim[0:] = a.dim;
	return c;
}

specialcase(a, b: Node): (int, Node)
{
	c := Node.mk(0.0);
	d1 := 0;
	d2 := 0;
	for(i:=1; i<Ndim; i++) {
		d := a.dim[i];
		if(d) {
			if(d != 1 || d1)
				return (0, c);
			d1 = i;
		}
		d = b.dim[i];
		if(d) {
			if(d != 1 || d2)
				return (0, c);
			d2 = i;
		}
	}
	if(d1 == 0 || d2 == 0)
		return (0, c);

	if(fund[d1].name == "°C" &&
	   fund[d2].name == "°F" &&
	   b.val == 1.0) {
		c = b.copy();
		c.val = a.val * 9. / 5. + 32.;
		return (1, c);
	}

	if(fund[d1].name == "°F" &&
	   fund[d2].name == "°C" &&
	   b.val == 1.0) {
		c = b.copy();
		c.val = (a.val - 32.) * 5. / 9.;
		return (1, c);
	}
	return (0, c);
}

printdim(d: int, n: int): string
{
	s := "";
	if(n) {
		v := fund[d];
		if(v != nil)
			s += " "+v.name;
		else
			s += sys->sprint(" [%d]", d);
		case n {
		1 =>
			;
		2 =>
			s += "²";
		3 =>
			s += "³";
		4 =>
			s += "⁴";
		* =>
			s += sys->sprint("^%d", n);
		}
	}
	return s;
}

Node.text(n: self Node): string
{
	str := sys->sprint("%.7g", n.val);
	f := 0;
	for(i:=1; i<len n.dim; i++) {
		d := n.dim[i];
		if(d > 0)
			str += printdim(i, d);
		else if(d < 0)
			f = 1;
	}

	if(f) {
		str += " /";
		for(i=1; i<len n.dim; i++) {
			d := n.dim[i];
			if(d < 0)
				str += printdim(i, -d);
		}
	}

	return str;
}

readline(): int
{
	linep = 0;
	line = "";
	for(i:=0;; i++) {
		c := fi.getc();
		if(c < 0)
			return 1;
		if(c == '\n')
			return 0;
		line[i] = c;
	}
}

lookup(f: int): ref Var
{
	h := 0;
	for(i:=0; i < len sym; i++)
		h = h*13 + sym[i];
	if(h < 0)
		h ^= int 16r80000000;
	h %= len vars;

	for(vl:=vars[h]; vl != nil; vl = tl vl)
		if((hd vl).name == sym)
			return hd vl;
	if(f)
		return nil;
	v := ref Var(sym, Node.mk(0.0));
	vars[h] = v :: vars[h];

	p := 1.0;
	for(;;) {
		p = fmul(p, pname());
		if(p == 0.0)
			break;
		w := lookup(1);
		if(w != nil) {
			v.node = w.node.copy();
			v.node.val = fmul(v.node.val, p);
			break;
		}
	}
	return v;
}

prefix: array of Prefix = array[] of {
	(1e-24,	"yocto"),
	(1e-21,	"zepto"),
	(1e-18,	"atto"),
	(1e-15,	"femto"),
	(1e-12,	"pico"),
	(1e-9,	"nano"),
	(1e-6,	"micro"),
	(1e-6,	"μ"),
	(1e-3,	"milli"),
	(1e-2,	"centi"),
	(1e-1,	"deci"),
	(1e1,	"deka"),
	(1e2,	"hecta"),
	(1e2,	"hecto"),
	(1e3,	"kilo"),
	(1e6,	"mega"),
	(1e6,	"meg"),
	(1e9,	"giga"),
	(1e12,	"tera"),
	(1e15,	"peta"),
	(1e18,	"exa"),
	(1e21,	"zetta"),
	(1e24,	"yotta")
};

pname(): real
{
	#
	# rip off normal prefices
	#
Pref:
	for(i:=0; i < len prefix; i++) {
		p := prefix[i].pname;
		for(j:=0; j < len p; j++)
			if(j >= len sym || p[j] != sym[j])
				continue Pref;
		sym = sym[j:];
		return prefix[i].val;
	}

	#
	# rip off 's' suffixes
	#
	for(j:=0; j < len sym; j++)
		;
	j--;
	# j>1 is special hack to disallow ms finding m
	if(j > 1 && sym[j] == 's') {
		sym = sym[0:j];
		return 1.0;
	}
	return 0.0;
}

#
# reads a floating-point number
#

readreal[T](f: ref fn(t: T): int, vp: T): (real, int)
{
	s := "";
	c := f(vp);
	while(c == ' ' || c == '\t')
		c = f(vp);
	if(c == '-' || c == '+'){
		s[len s] = c;
		c = f(vp);
	}
	start := len s;
	while(c >= '0' && c <= '9'){
		s[len s] = c;
		c = f(vp);
	}
	if(c == '.'){
		s[len s] = c;
		c = f(vp);
		while(c >= '0' && c <= '9'){
			s[len s] = c;
			c = f(vp);
		}
	}
	if(len s > start && (c == 'e' || c == 'E')){
		s[len s] = c;
		c = f(vp);
		if(c == '-' || c == '+'){
			s[len s] = c;
			c = f(vp);
		}
		while(c >= '0' && c <= '9'){
			s[len s] = c;
			c = f(vp);
		}
	}
	return (real s, c);
}

#
# careful floating point
#

fmul(a, b: real): real
{
	l: real;

	if(a <= 0.0) {
		if(a == 0.0)
			return 0.0;
		l = math->log(-a);
	} else
		l = math->log(a);

	if(b <= 0.0) {
		if(b == 0.0)
			return 0.0;
		l += math->log(-b);
	} else
		l += math->log(b);

	if(l > Maxe) {
		yyerror("overflow in multiply");
		return 1.0;
	}
	if(l < -Maxe) {
		yyerror("underflow in multiply");
		return 0.0;
	}
	return a*b;
}

fdiv(a, b: real): real
{
	l: real;

	if(a <= 0.0) {
		if(a == 0.0)
			return 0.0;
		l = math->log(-a);
	} else
		l = math->log(a);

	if(b <= 0.0) {
		if(b == 0.0) {
			yyerror("division by zero");
			return 1.0;
		}
		l -= math->log(-b);
	} else
		l -= math->log(b);

	if(l > Maxe) {
		yyerror("overflow in divide");
		return 1.0;
	}
	if(l < -Maxe) {
		yyerror("underflow in divide");
		return 0.0;
	}
	return a/b;
}

fadd(a, b: real): real
{
	return a + b;
}
yyexca := array[] of {-1, 1,
	1, -1,
	-2, 0,
};
YYNPROD: con 21;
YYPRIVATE: con 57344;
yytoknames: array of string;
yystates: array of string;
yydebug: con 0;
YYLAST:	con 41;
yyact := array[] of {
   8,  10,   7,   9,  16,  17,  12,  11,  20,  21,
  15,  31,  23,   6,   4,  12,  11,  22,  13,   5,
   1,  27,  28,   0,  14,  30,  29,  13,  20,  20,
  25,  26,   0,  24,  18,  19,  16,  17,   2,   0,
   3,
};
yypact := array[] of {
  31,-1000,   9,  11,   2,  26,  22,  11,   3,  -3,
-1000,-1000,-1000,  11,  26,-1000,  11,  11,  11,  11,
   3,-1000,  11,  11,  -6,  22,  22,  11,  11,  -3,
-1000,-1000,
};
yypgo := array[] of {
   0,  20,  19,   1,   3,   0,   2,  13,
};
yyr1 := array[] of {
   0,   1,   1,   1,   1,   2,   2,   2,   7,   7,
   7,   6,   6,   5,   5,   5,   4,   4,   3,   3,
   3,
};
yyr2 := array[] of {
   0,   3,   3,   2,   1,   1,   3,   3,   1,   3,
   3,   1,   2,   1,   2,   3,   1,   3,   1,   1,
   3,
};
yychk := array[] of {
-1000,  -1,   7,   9,   5,  -2,  -7,  -6,  -5,  -4,
  -3,   5,   4,  16,  -2,   8,  10,  11,  12,  13,
  -5,   6,  14,  15,  -2,  -7,  -7,  -6,  -6,  -4,
  -3,  17,
};
yydef := array[] of {
   0,  -2,   0,   4,   0,   3,   5,   8,  11,  13,
  16,  18,  19,   0,   1,   2,   0,   0,   0,   0,
  12,  14,   0,   0,   0,   6,   7,   9,  10,  15,
  17,  20,
};
yytok1 := array[] of {
   1,   3,   3,   3,   3,   3,   3,   3,   3,   3,
   3,   3,   3,   3,   3,   3,   3,   3,   3,   3,
   3,   3,   3,   3,   3,   3,   3,   3,   3,   3,
   3,   3,   3,   3,   3,   8,   3,   3,   3,   3,
  16,  17,  12,  10,   3,  11,   3,  13,   3,   3,
   3,   3,   3,   3,   3,   3,   3,   3,   7,   3,
   3,   3,   3,   9,   3,   3,   3,   3,   3,   3,
   3,   3,   3,   3,   3,   3,   3,   3,   3,   3,
   3,   3,   3,   3,   3,   3,   3,   3,   3,   3,
   3,   3,   3,   3,  14,   3,   3,   3,   3,   3,
   3,   3,   3,   3,   3,   3,   3,   3,   3,   3,
   3,   3,   3,   3,   3,   3,   3,   3,   3,   3,
   3,   3,   3,   3,  15,
};
yytok2 := array[] of {
   2,   3,   4,   5,   6,
};
yytok3 := array[] of {
   0
};

YYSys: module
{
	FD: adt
	{
		fd:	int;
	};
	fildes:		fn(fd: int): ref FD;
	fprint:		fn(fd: ref FD, s: string, *): int;
};

yysys: YYSys;
yystderr: ref YYSys->FD;

YYFLAG: con -1000;

# parser for yacc output

yytokname(yyc: int): string
{
	if(yyc > 0 && yyc <= len yytoknames && yytoknames[yyc-1] != nil)
		return yytoknames[yyc-1];
	return "<"+string yyc+">";
}

yystatname(yys: int): string
{
	if(yys >= 0 && yys < len yystates && yystates[yys] != nil)
		return yystates[yys];
	return "<"+string yys+">\n";
}

yylex1(yylex: ref YYLEX): int
{
	c : int;
	yychar := yylex.lex();
	if(yychar <= 0)
		c = yytok1[0];
	else if(yychar < len yytok1)
		c = yytok1[yychar];
	else if(yychar >= YYPRIVATE && yychar < YYPRIVATE+len yytok2)
		c = yytok2[yychar-YYPRIVATE];
	else{
		n := len yytok3;
		c = 0;
		for(i := 0; i < n; i+=2) {
			if(yytok3[i+0] == yychar) {
				c = yytok3[i+1];
				break;
			}
		}
		if(c == 0)
			c = yytok2[1];	# unknown char
	}
	if(yydebug >= 3)
		yysys->fprint(yystderr, "lex %.4ux %s\n", yychar, yytokname(c));
	return c;
}

YYS: adt
{
	yyv: YYSTYPE;
	yys: int;
};

yyparse(yylex: ref YYLEX): int
{
	if(yydebug >= 1 && yysys == nil) {
		yysys = load YYSys "$Sys";
		yystderr = yysys->fildes(2);
	}

	yys := array[YYMAXDEPTH] of YYS;

	yyval: YYSTYPE;
	yystate := 0;
	yychar := -1;
	yynerrs := 0;		# number of errors
	yyerrflag := 0;		# error recovery flag
	yyp := -1;
	yyn := 0;

yystack:
	for(;;){
		# put a state and value onto the stack
		if(yydebug >= 4)
			yysys->fprint(yystderr, "char %s in %s", yytokname(yychar), yystatname(yystate));

		yyp++;
		if(yyp >= len yys)
			yys = (array[len yys * 2] of YYS)[0:] = yys;
		yys[yyp].yys = yystate;
		yys[yyp].yyv = yyval;

		for(;;){
			yyn = yypact[yystate];
			if(yyn > YYFLAG) {	# simple state
				if(yychar < 0)
					yychar = yylex1(yylex);
				yyn += yychar;
				if(yyn >= 0 && yyn < YYLAST) {
					yyn = yyact[yyn];
					if(yychk[yyn] == yychar) { # valid shift
						yychar = -1;
						yyp++;
						if(yyp >= len yys)
							yys = (array[len yys * 2] of YYS)[0:] = yys;
						yystate = yyn;
						yys[yyp].yys = yystate;
						yys[yyp].yyv = yylex.lval;
						if(yyerrflag > 0)
							yyerrflag--;
						if(yydebug >= 4)
							yysys->fprint(yystderr, "char %s in %s", yytokname(yychar), yystatname(yystate));
						continue;
					}
				}
			}
		
			# default state action
			yyn = yydef[yystate];
			if(yyn == -2) {
				if(yychar < 0)
					yychar = yylex1(yylex);
		
				# look through exception table
				for(yyxi:=0;; yyxi+=2)
					if(yyexca[yyxi] == -1 && yyexca[yyxi+1] == yystate)
						break;
				for(yyxi += 2;; yyxi += 2) {
					yyn = yyexca[yyxi];
					if(yyn < 0 || yyn == yychar)
						break;
				}
				yyn = yyexca[yyxi+1];
				if(yyn < 0){
					yyn = 0;
					break yystack;
				}
			}

			if(yyn != 0)
				break;

			# error ... attempt to resume parsing
			if(yyerrflag == 0) { # brand new error
				yylex.error("syntax error");
				yynerrs++;
				if(yydebug >= 1) {
					yysys->fprint(yystderr, "%s", yystatname(yystate));
					yysys->fprint(yystderr, "saw %s\n", yytokname(yychar));
				}
			}

			if(yyerrflag != 3) { # incompletely recovered error ... try again
				yyerrflag = 3;
	
				# find a state where "error" is a legal shift action
				while(yyp >= 0) {
					yyn = yypact[yys[yyp].yys] + YYERRCODE;
					if(yyn >= 0 && yyn < YYLAST) {
						yystate = yyact[yyn];  # simulate a shift of "error"
						if(yychk[yystate] == YYERRCODE)
							continue yystack;
					}
	
					# the current yyp has no shift onn "error", pop stack
					if(yydebug >= 2)
						yysys->fprint(yystderr, "error recovery pops state %d, uncovers %d\n",
							yys[yyp].yys, yys[yyp-1].yys );
					yyp--;
				}
				# there is no state on the stack with an error shift ... abort
				yyn = 1;
				break yystack;
			}

			# no shift yet; clobber input char
			if(yydebug >= 2)
				yysys->fprint(yystderr, "error recovery discards %s\n", yytokname(yychar));
			if(yychar == YYEOFCODE) {
				yyn = 1;
				break yystack;
			}
			yychar = -1;
			# try again in the same state
		}
	
		# reduction by production yyn
		if(yydebug >= 2)
			yysys->fprint(yystderr, "reduce %d in:\n\t%s", yyn, yystatname(yystate));
	
		yypt := yyp;
		yyp -= yyr2[yyn];
#		yyval = yys[yyp+1].yyv;
		yym := yyn;
	
		# consult goto table to find next state
		yyn = yyr1[yyn];
		yyg := yypgo[yyn];
		yyj := yyg + yys[yyp].yys + 1;
	
		if(yyj >= YYLAST || yychk[yystate=yyact[yyj]] != -yyn)
			yystate = yyact[yyg];
		case yym {
			
1=>
#line	90	"units.y"
{
		f := yys[yypt-1].yyv.var.node.dim[0];
		yys[yypt-1].yyv.var.node = yys[yypt-0].yyv.node.copy();
		yys[yypt-1].yyv.var.node.dim[0] = 1;
		if(f)
			yyerror(sys->sprint("redefinition of %s", yys[yypt-1].yyv.var.name));
		else if(vflag)
			sys->print("%s\t%s\n", yys[yypt-1].yyv.var.name, yys[yypt-1].yyv.var.node.text());
	}
2=>
#line	100	"units.y"
{
		for(i:=1; i<Ndim; i++)
			if(fund[i] == nil)
				break;
		if(i >= Ndim) {
			yyerror("too many dimensions");
			i = Ndim-1;
		}
		fund[i] = yys[yypt-1].yyv.var;

		f := yys[yypt-1].yyv.var.node.dim[0];
		yys[yypt-1].yyv.var.node = Node.mk(1.0);
		yys[yypt-1].yyv.var.node.dim[0] = 1;
		yys[yypt-1].yyv.var.node.dim[i] = 1;
		if(f)
			yyerror(sys->sprint("redefinition of %s", yys[yypt-1].yyv.var.name));
		else if(vflag)
			sys->print("%s\t#\n", yys[yypt-1].yyv.var.name);
	}
3=>
#line	120	"units.y"
{
		retnode1 = yys[yypt-0].yyv.node.copy();
	}
4=>
#line	124	"units.y"
{
		retnode1 = Node.mk(1.0);
	}
5=>
yyval.node = yys[yyp+1].yyv.node;
6=>
#line	131	"units.y"
{
		yyval.node = yys[yypt-2].yyv.node.add(yys[yypt-0].yyv.node);
	}
7=>
#line	135	"units.y"
{
		yyval.node = yys[yypt-2].yyv.node.sub(yys[yypt-0].yyv.node);
	}
8=>
yyval.node = yys[yyp+1].yyv.node;
9=>
#line	142	"units.y"
{
		yyval.node = yys[yypt-2].yyv.node.mul(yys[yypt-0].yyv.node);
	}
10=>
#line	146	"units.y"
{
		yyval.node = yys[yypt-2].yyv.node.div(yys[yypt-0].yyv.node);
	}
11=>
yyval.node = yys[yyp+1].yyv.node;
12=>
#line	153	"units.y"
{
		yyval.node = yys[yypt-1].yyv.node.mul(yys[yypt-0].yyv.node);
	}
13=>
yyval.node = yys[yyp+1].yyv.node;
14=>
#line	160	"units.y"
{
		yyval.node = yys[yypt-1].yyv.node.xpn(yys[yypt-0].yyv.numb);
	}
15=>
#line	164	"units.y"
{
		for(i:=1; i<Ndim; i++)
			if(yys[yypt-0].yyv.node.dim[i]) {
				yyerror("exponent has units");
				yyval.node = yys[yypt-2].yyv.node;
				break;
			}
		if(i >= Ndim) {
			i = int yys[yypt-0].yyv.node.val;
			if(real i != yys[yypt-0].yyv.node.val)
				yyerror("exponent not integral");
			yyval.node = yys[yypt-2].yyv.node.xpn(i);
		}
	}
16=>
yyval.node = yys[yyp+1].yyv.node;
17=>
#line	182	"units.y"
{
		yyval.node = yys[yypt-2].yyv.node.div(yys[yypt-0].yyv.node);
	}
18=>
#line	188	"units.y"
{
		if(yys[yypt-0].yyv.var.node.dim[0] == 0) {
			yyerror(sys->sprint("undefined %s", yys[yypt-0].yyv.var.name));
			yyval.node = Node.mk(1.0);
		} else
			yyval.node = yys[yypt-0].yyv.var.node.copy();
	}
19=>
#line	196	"units.y"
{
		yyval.node = Node.mk(yys[yypt-0].yyv.val);
	}
20=>
#line	200	"units.y"
{
		yyval.node = yys[yypt-1].yyv.node;
	}
		}
	}

	return yyn;
}
