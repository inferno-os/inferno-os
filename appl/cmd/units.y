%{
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
  
%}
%module Units
{
	init:	fn(nil: ref Draw->Context, args: list of string);
}

%type	<node>	prog expr expr0 expr1 expr2 expr3 expr4

%token	<val>	VAL
%token	<var>	VAR
%token	<numb>	SUP
%%
prog:
	':' VAR expr
	{
		f := $2.node.dim[0];
		$2.node = $3.copy();
		$2.node.dim[0] = 1;
		if(f)
			yyerror(sys->sprint("redefinition of %s", $2.name));
		else if(vflag)
			sys->print("%s\t%s\n", $2.name, $2.node.text());
	}
|	':' VAR '#'
	{
		for(i:=1; i<Ndim; i++)
			if(fund[i] == nil)
				break;
		if(i >= Ndim) {
			yyerror("too many dimensions");
			i = Ndim-1;
		}
		fund[i] = $2;

		f := $2.node.dim[0];
		$2.node = Node.mk(1.0);
		$2.node.dim[0] = 1;
		$2.node.dim[i] = 1;
		if(f)
			yyerror(sys->sprint("redefinition of %s", $2.name));
		else if(vflag)
			sys->print("%s\t#\n", $2.name);
	}
|	'?' expr
	{
		retnode1 = $2.copy();
	}
|	'?'
	{
		retnode1 = Node.mk(1.0);
	}

expr:
	expr4
|	expr '+' expr4
	{
		$$ = $1.add($3);
	}
|	expr '-' expr4
	{
		$$ = $1.sub($3);
	}

expr4:
	expr3
|	expr4 '*' expr3
	{
		$$ = $1.mul($3);
	}
|	expr4 '/' expr3
	{
		$$ = $1.div($3);
	}

expr3:
	expr2
|	expr3 expr2
	{
		$$ = $1.mul($2);
	}

expr2:
	expr1
|	expr2 SUP
	{
		$$ = $1.xpn($2);
	}
|	expr2 '^' expr1
	{
		for(i:=1; i<Ndim; i++)
			if($3.dim[i]) {
				yyerror("exponent has units");
				$$ = $1;
				break;
			}
		if(i >= Ndim) {
			i = int $3.val;
			if(real i != $3.val)
				yyerror("exponent not integral");
			$$ = $1.xpn(i);
		}
	}

expr1:
	expr0
|	expr1 '|' expr0
	{
		$$ = $1.div($3);
	}

expr0:
	VAR
	{
		if($1.node.dim[0] == 0) {
			yyerror(sys->sprint("undefined %s", $1.name));
			$$ = Node.mk(1.0);
		} else
			$$ = $1.node.copy();
	}
|	VAL
	{
		$$ = Node.mk($1);
	}
|	'(' expr ')'
	{
		$$ = $2;
	}
%%

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
