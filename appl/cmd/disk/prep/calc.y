%{
#
# from Plan 9.  subject to the Lucent Public License 1.02
#

include "sys.m";
	sys: Sys;

include "draw.m";

	NUM,
	DOT,
	DOLLAR,
	ADD,
	SUB,
	MUL,
	DIV,
	FRAC,
	NEG: con iota;

Exp: adt {
	ty:	int;
	n:	big;
	e1, e2:	cyclic ref Exp;
};

YYSTYPE: adt {
	e:	ref Exp;
};
yyexp: ref Exp;

YYLEX: adt {
	s:	string;
	n:	int;
	lval: YYSTYPE;
	lex: fn(l: self ref YYLEX): int;
	error: fn(l: self ref YYLEX, msg: string);
};
%}
%module Calc
{
	parseexpr: fn(s: string, a, b, c: big): (big, string);
	init:	fn(nil: ref Draw->Context, nil: list of string);
}

%token <e> NUMBER

%type <e> expr

%left '+' '-'
%left '*' '/'
%left UNARYMINUS '%'
%%
top:	expr	{ yyexp = $1; return 0; }

expr:	NUMBER
	| '.'	{ $$ = mkOP(DOT, nil, nil); }
	| '$'	{ $$ = mkOP(DOLLAR, nil, nil); }
	| '(' expr ')'	{ $$ = $2; }
	| expr '+' expr	{ $$ = mkOP(ADD, $1, $3); }
	| expr '-' expr 	{ $$ = mkOP(SUB, $1, $3); }
	| expr '*' expr	{ $$ = mkOP(MUL, $1, $3); }
	| expr '/' expr	{ $$ = mkOP(DIV, $1, $3); }
	| expr '%'		{ $$ = mkOP(FRAC, $1, nil); }
	| '-' expr %prec UNARYMINUS	{ $$ = mkOP(NEG, $2, nil); }
	;

%%

mkNUM(x: big): ref Exp
{
	return ref Exp(NUM, x, nil, nil);
}

mkOP(ty: int, e1: ref Exp, e2: ref Exp): ref Exp
{
	return ref Exp(ty, big 0, e1, e2);
}

dot, size, dollar: big;

YYLEX.lex(l: self ref YYLEX): int
{
	while(l.n < len l.s && isspace(l.s[l.n]))
		l.n++;

	if(l.n == len l.s)
		return -1;

	if(isdigit(l.s[l.n])){
		for(o := l.n; o < len l.s && isdigit(l.s[o]); o++)
			;
		l.lval.e = mkNUM(big l.s[l.n:o]);
		l.n = o;
		return NUMBER;
	}

	return l.s[l.n++];
}

isdigit(c: int): int
{
	return c >= '0' && c <= '9';
}

isspace(c: int): int
{
	return c == ' ' || c == '\t' || c == '\n' || c == '\r' || c == '\v' || c == '\f';
}

YYLEX.error(nil: self ref YYLEX, s: string)
{
	raise s;
}

eval(e: ref Exp): big
{
	case e.ty {
	NUM =>
		return e.n;
	DOT =>
		return dot;
	DOLLAR =>
		return dollar;
	ADD =>
		return eval(e.e1)+eval(e.e2);
	SUB =>
		return eval(e.e1)-eval(e.e2);
	MUL =>
		return eval(e.e1)*eval(e.e2);
	DIV =>
		i := eval(e.e2);
		if(i == big 0)
			raise "division by zero";
		return eval(e.e1)/i;
	FRAC =>
		return (size*eval(e.e1))/big 100;
	NEG =>
		return -eval(e.e1);
	* =>
		raise "invalid operator";
	}
}

parseexpr(s: string, xdot: big, xdollar: big, xsize: big): (big, string)
{
	dot = xdot;
	size = xsize;
	dollar = xdollar;
	l := ref YYLEX(s, 0, YYSTYPE(nil));
	{
		yyparse(l);
		if(yyexp == nil)
			return (big 0, "nil yylval?");
		return (eval(yyexp), nil);
	}exception e{
	"*" =>
		return (big 0, e);
	}
}

init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;

	while((args = tl args) != nil){
		(r, e) := parseexpr(hd args, big 1000, big 1000000, big 1000000);
		if(e != nil)
			sys->print("%s\n", e);
		else
			sys->print("%bd\n", r);
	}
}

