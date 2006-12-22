implement Calc;

#line	2	"calc.y"
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
Calc: module {

	parseexpr: fn(s: string, a, b, c: big): (big, string);
	init:	fn(nil: ref Draw->Context, nil: list of string);
NUMBER: con	57346;
UNARYMINUS: con	57347;

};
YYEOFCODE: con 1;
YYERRCODE: con 2;
YYMAXDEPTH: con 200;

#line	68	"calc.y"


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

yyexca := array[] of {-1, 1,
	1, -1,
	-2, 0,
};
YYNPROD: con 12;
YYPRIVATE: con 57344;
yytoknames: array of string;
yystates: array of string;
yydebug: con 0;
YYLAST:	con 30;
yyact := array[] of {
   8,   9,  10,  11,   3,  12,   7,   2,  12,  19,
   1,   4,   5,   6,  13,  14,  15,  16,  17,  18,
   8,   9,  10,  11,   0,  12,  10,  11,   0,  12,
};
yypact := array[] of {
   0,-1000,  15,-1000,-1000,-1000,   0,   0,   0,   0,
   0,   0,-1000,  -5,-1000,  19,  19,  -2,  -2,-1000,
};
yypgo := array[] of {
   0,   7,  10,
};
yyr1 := array[] of {
   0,   2,   1,   1,   1,   1,   1,   1,   1,   1,
   1,   1,
};
yyr2 := array[] of {
   0,   1,   1,   1,   1,   3,   3,   3,   3,   3,
   2,   2,
};
yychk := array[] of {
-1000,  -2,  -1,   4,  11,  12,  13,   6,   5,   6,
   7,   8,  10,  -1,  -1,  -1,  -1,  -1,  -1,  14,
};
yydef := array[] of {
   0,  -2,   1,   2,   3,   4,   0,   0,   0,   0,
   0,   0,  10,   0,  11,   6,   7,   8,   9,   5,
};
yytok1 := array[] of {
   1,   3,   3,   3,   3,   3,   3,   3,   3,   3,
   3,   3,   3,   3,   3,   3,   3,   3,   3,   3,
   3,   3,   3,   3,   3,   3,   3,   3,   3,   3,
   3,   3,   3,   3,   3,   3,  12,  10,   3,   3,
  13,  14,   7,   5,   3,   6,  11,   8,
};
yytok2 := array[] of {
   2,   3,   4,   9,
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
#line	54	"calc.y"
{ yyexp = yys[yypt-0].yyv.e; return 0; }
2=>
yyval.e = yys[yyp+1].yyv.e;
3=>
#line	57	"calc.y"
{ yyval.e = mkOP(DOT, nil, nil); }
4=>
#line	58	"calc.y"
{ yyval.e = mkOP(DOLLAR, nil, nil); }
5=>
#line	59	"calc.y"
{ yyval.e = yys[yypt-1].yyv.e; }
6=>
#line	60	"calc.y"
{ yyval.e = mkOP(ADD, yys[yypt-2].yyv.e, yys[yypt-0].yyv.e); }
7=>
#line	61	"calc.y"
{ yyval.e = mkOP(SUB, yys[yypt-2].yyv.e, yys[yypt-0].yyv.e); }
8=>
#line	62	"calc.y"
{ yyval.e = mkOP(MUL, yys[yypt-2].yyv.e, yys[yypt-0].yyv.e); }
9=>
#line	63	"calc.y"
{ yyval.e = mkOP(DIV, yys[yypt-2].yyv.e, yys[yypt-0].yyv.e); }
10=>
#line	64	"calc.y"
{ yyval.e = mkOP(FRAC, yys[yypt-1].yyv.e, nil); }
11=>
#line	65	"calc.y"
{ yyval.e = mkOP(NEG, yys[yypt-0].yyv.e, nil); }
		}
	}

	return yyn;
}
