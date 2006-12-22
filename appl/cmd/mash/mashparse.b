implement Mashparse;

#line	2	"mash.y"
include	"mash.m";

#
#	mash parser.  Thread safe.
#
Mashparse: module {

	PATH:	con "/dis/lib/mashparse.dis";

	init:		fn(l: Mashlib);
	parse:	fn(e: ref Mashlib->Env);

	YYSTYPE: adt
	{
		cmd:		ref Mashlib->Cmd;
		item:		ref Mashlib->Item;
		items:	list of ref Mashlib->Item;
		flag:		int;
	};

	YYETYPE:	type ref Mashlib->Env;
Lcase: con	57346;
Lfor: con	57347;
Lif: con	57348;
Lwhile: con	57349;
Loffparen: con	57350;
Lelse: con	57351;
Lpipe: con	57352;
Leqeq: con	57353;
Lmatch: con	57354;
Lnoteq: con	57355;
Lcons: con	57356;
Lcaret: con	57357;
Lnot: con	57358;
Lhd: con	57359;
Ltl: con	57360;
Llen: con	57361;
Lword: con	57362;
Lbackq: con	57363;
Lcolon: con	57364;
Lcolonmatch: con	57365;
Ldefeq: con	57366;
Leq: con	57367;
Lmatched: con	57368;
Lquote: con	57369;
Loncurly: con	57370;
Lonparen: con	57371;
Loffcurly: con	57372;
Lat: con	57373;
Lgreat: con	57374;
Lgreatgreat: con	57375;
Lless: con	57376;
Llessgreat: con	57377;
Lfn: con	57378;
Lin: con	57379;
Lrescue: con	57380;
Land: con	57381;
Leof: con	57382;
Lsemi: con	57383;
Lerror: con	57384;

};

#line	28	"mash.y"
	lib:		Mashlib;

	Cmd, Item, Stab, Env:		import lib;
YYEOFCODE: con 1;
YYERRCODE: con 2;
YYMAXDEPTH: con 150;

#line	244	"mash.y"


init(l: Mashlib)
{
	lib = l;
}

parse(e: ref Env)
{
	y := ref YYENV;
	y.yyenv = e;
	y.yysys = lib->sys;
	y.yystderr = e.stderr;
	yyeparse(y);
}

yyerror(e: ref YYENV, s: string)
{
	e.yyenv.report(s);
	e.yyenv.suck();
}

yyelex(e: ref YYENV): int
{
	return e.yyenv.lex(e.yylval);
}
yyexca := array[] of {-1, 1,
	1, -1,
	-2, 0,
-1, 2,
	1, 1,
	-2, 0,
-1, 21,
	24, 51,
	25, 51,
	-2, 48,
};
YYNPROD: con 75;
YYPRIVATE: con 57344;
yytoknames: array of string;
yystates: array of string;
yydebug: con 0;
YYLAST:	con 249;
yyact := array[] of {
   7,  20,   4,  49,  41,  47, 110,  65, 103,  95,
  17,  24,  32, 112,  33, 146, 142,  38,  39,  28,
  59,  60, 140, 129,  40,  64,  22,  46,  63,  35,
  36,  34,  37, 128, 127,  38,  67,  69,  70,  71,
  27,  26,  25,  76,  22,  75, 126, 111,  77,  74,
  45,  80,  81,  38,  44,  78,  88,  89,  90,  91,
  92,  68,  22,  98,  99,  93,  94,  32, 124,  33,
  97, 106,  62, 107,  38,  39, 104, 108, 109, 104,
  68,  40, 105,  22,  66, 105,  56, 143,  55, 116,
 117, 118, 119, 120,  73,  32,  32,  33,  33,  38,
  39, 122, 132,  36, 131,  37,  40, 123,  22,  72,
 125,  56,  43,  55, 135, 136,  58,  57, 133,  62,
 134, 139,  38,   6,  62,  16,  13,  14,  15, 141,
  66,  22,  96,  67,  69,  62,  32,  79,  33,  84,
  83,  21,  24,  61, 147, 148, 144,  24, 149,  11,
  22,   3,  12,  16,  13,  14,  15,  18,   2,  19,
   1,   5,  85,  87,  86,  84,  83,   8, 101,  21,
  54,  51,  52,  53,  48,  39,   9,  11,  22,  82,
  12,  40,  42,  50, 137,  18,  56,  19,  55,  54,
  51,  52,  53,  48,  39, 115, 138,  38,  39, 130,
  40,  10,  50,  29,  40,  56,  22,  55, 102,  56,
  31,  55,  85,  87,  86,  84,  83, 121,  23,  30,
  85,  87,  86,  84,  83, 114,   0, 145,  85,  87,
  86,  84,  83, 113,   0,   0,  85,  87,  86,  84,
  83, 100,   0,   0,  85,  87,  86,  84,  83,
};
yypact := array[] of {
-1000,-1000, 121,-1000,-1000,-1000,-1000,   1,-1000,-1000,
  -3,-1000,  84,  25,  21,  -2, 173,  92,  15,  15,
 120,-1000, 173,-1000, 149,-1000,-1000,-1000,-1000,-1000,
-1000,-1000, 109,-1000, 102,  33,  15,  15,-1000,  81,
  66,  19, 149,-1000, 117, 173, 173, 151,-1000,-1000,
 173, 173, 173, 173, 173,  56,  52,-1000,-1000, 104,
 104,  15,  15, 233,-1000,  54,-1000, 109,-1000, 109,
 109, 109,-1000,-1000,-1000,-1000,   1,  17, -24,-1000,
 225, 217,-1000, 173, 173, 173, 173, 173, 209,-1000,
-1000,-1000,-1000, 177, 177,-1000,-1000,-1000,  57,-1000,
-1000,-1000,-1000,-1000,  40,-1000,  16,   4,   3,  -7,
  70,-1000,-1000, 149, 149, 154,-1000, 125, 125, 125,
 125,-1000,  -8,-1000,-1000, -14,-1000,-1000,-1000,-1000,
-1000,  15,  15,  70,  79, 137, 132,-1000,-1000, 201,
-1000, -15,-1000, 149, 149, 149,-1000, 132, 132,-1000,
};
yypgo := array[] of {
   0, 218, 203,   3, 208,   1, 199,  10, 201,   7,
 196, 195,   0,   2,   4, 182, 176,   6,   5,   8,
 168,   9, 167, 160, 158, 151,
};
yyr1 := array[] of {
   0,  23,  24,  24,  25,  25,  25,  15,  15,  13,
  14,  14,  12,  12,  12,  22,  22,  16,  16,  16,
  16,  16,  16,  16,  16,  16,  16,  16,  16,  19,
  19,  20,  20,  21,  21,  11,  11,  10,   8,   8,
   2,   2,   4,   4,   3,   3,   3,   3,   5,   5,
   5,   7,   9,   9,  17,  17,   6,   6,   6,   6,
   1,   1,   1,  18,  18,  18,  18,  18,  18,  18,
  18,  18,  18,  18,  18,
};
yyr2 := array[] of {
   0,   1,   0,   2,   1,   1,   1,   0,   2,   2,
   1,   2,   1,   1,   3,   1,   4,   4,   5,   7,
   5,   7,   5,   5,   3,   3,   3,   3,   4,   4,
   3,   0,   1,   0,   3,   0,   2,   3,   1,   2,
   1,   1,   1,   1,   4,   4,   4,   4,   1,   3,
   3,   1,   0,   2,   0,   2,   2,   2,   2,   2,
   1,   1,   1,   1,   1,   3,   3,   2,   2,   2,
   2,   3,   3,   3,   3,
};
yychk := array[] of {
-1000, -23, -24, -25, -13,  40,   2, -12, -22, -16,
  -8,  28,  31,   5,   6,   7,   4,  -7,  36,  38,
  -5,  20,  29,  -1,  10,  41,  40,  39,  22,  -2,
  -4,  -6,  -5,  -3,  34,  32,  33,  35,  20,  21,
  27, -14, -15,  28,  29,  29,  29, -18,  20,  -3,
  29,  17,  18,  19,  16,  34,  32,  25,  24,  -5,
  -5,  23,  15, -18, -12,  -9,  28,  -5,  28,  -5,
  -5,  -5,  28,  28,  30, -13, -12, -14,  -7,  20,
 -18, -18,  28,  15,  14,  11,  13,  12, -18, -18,
 -18, -18, -18,  -9,  -9, -21,  28, -21,  -5,  -5,
   8, -20,  -4, -19,  22,  28, -14, -14, -14, -14,
 -17,  30,  37,   8,   8, -11, -18, -18, -18, -18,
 -18,   8, -14, -19,  28, -14,  30,  30,  30,  30,
  -6,  34,  32, -17,  -9, -12, -12,  30, -10, -18,
  30, -14,  30,   8,   9,  26,  30, -12, -12, -13,
};
yydef := array[] of {
   2,  -2,  -2,   3,   4,   5,   6,   0,  12,  13,
  15,   7,   0,   0,   0,   0,   0,   0,   0,   0,
  38,  -2,   0,   9,   0,  60,  61,  62,  52,  39,
  40,  41,  42,  43,   0,   0,   0,   0,  48,   0,
   0,   0,  10,   7,   0,   0,   0,   0,  63,  64,
   0,   0,   0,   0,   0,   0,   0,  52,  52,  33,
  33,   0,   0,   0,  14,  31,   7,  56,   7,  57,
  58,  59,   7,   7,  54,   8,  11,   0,   0,  51,
   0,   0,  35,   0,   0,   0,   0,   0,   0,  67,
  68,  69,  70,  24,  25,  26,   7,  27,   0,  49,
  50,  16,  53,  32,   0,   7,   0,   0,   0,   0,
  17,  54,  52,   0,   0,   0,  66,  71,  72,  73,
  74,  65,   0,  28,   7,   0,  46,  47,  44,  45,
  55,   0,   0,  18,   0,  20,  22,  23,  36,   0,
  34,   0,  30,   0,   0,   0,  29,  19,  21,  37,
};
yytok1 := array[] of {
   1,
};
yytok2 := array[] of {
   2,   3,   4,   5,   6,   7,   8,   9,  10,  11,
  12,  13,  14,  15,  16,  17,  18,  19,  20,  21,
  22,  23,  24,  25,  26,  27,  28,  29,  30,  31,
  32,  33,  34,  35,  36,  37,  38,  39,  40,  41,
  42,
};
yytok3 := array[] of {
   0
};

YYFLAG: con -1000;

# parser for yacc output
YYENV: adt
{
	yylval:	ref YYSTYPE;	# lexical value
	yyval:	YYSTYPE;		# goto value
	yyenv:	YYETYPE;		# useer environment
	yynerrs:	int;			# number of errors
	yyerrflag:	int;			# error recovery flag
	yysys:	Sys;
	yystderr:	ref Sys->FD;
};

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

yylex1(e: ref YYENV): int
{
	c, yychar : int;
	yychar = yyelex(e);
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
		e.yysys->fprint(e.yystderr, "lex %.4ux %s\n", yychar, yytokname(c));
	return c;
}

YYS: adt
{
	yyv: YYSTYPE;
	yys: int;
};

yyparse(): int
{
	return yyeparse(nil);
}

yyeparse(e: ref YYENV): int
{
	if(e == nil)
		e = ref YYENV;
	if(e.yylval == nil)
		e.yylval = ref YYSTYPE;
	if(e.yysys == nil) {
		e.yysys = load Sys "$Sys";
		e.yystderr = e.yysys->fildes(2);
	}

	yys := array[YYMAXDEPTH] of YYS;

	yystate := 0;
	yychar := -1;
	e.yynerrs = 0;
	e.yyerrflag = 0;
	yyp := -1;
	yyn := 0;

yystack:
	for(;;){
		# put a state and value onto the stack
		if(yydebug >= 4)
			e.yysys->fprint(e.yystderr, "char %s in %s", yytokname(yychar), yystatname(yystate));

		yyp++;
		if(yyp >= YYMAXDEPTH) {
			yyerror(e, "yacc stack overflow");
			yyn = 1;
			break yystack;
		}
		yys[yyp].yys = yystate;
		yys[yyp].yyv = e.yyval;

		for(;;){
			yyn = yypact[yystate];
			if(yyn > YYFLAG) {	# simple state
				if(yychar < 0)
					yychar = yylex1(e);
				yyn += yychar;
				if(yyn >= 0 && yyn < YYLAST) {
					yyn = yyact[yyn];
					if(yychk[yyn] == yychar) { # valid shift
						yychar = -1;
						yyp++;
						if(yyp >= YYMAXDEPTH) {
							yyerror(e, "yacc stack overflow");
							yyn = 1;
							break yystack;
						}
						yystate = yyn;
						yys[yyp].yys = yystate;
						yys[yyp].yyv = *e.yylval;
						if(e.yyerrflag > 0)
							e.yyerrflag--;
						if(yydebug >= 4)
							e.yysys->fprint(e.yystderr, "char %s in %s", yytokname(yychar), yystatname(yystate));
						continue;
					}
				}
			}
		
			# default state action
			yyn = yydef[yystate];
			if(yyn == -2) {
				if(yychar < 0)
					yychar = yylex1(e);
		
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
			if(e.yyerrflag == 0) { # brand new error
				yyerror(e, "syntax error");
				e.yynerrs++;
				if(yydebug >= 1) {
					e.yysys->fprint(e.yystderr, "%s", yystatname(yystate));
					e.yysys->fprint(e.yystderr, "saw %s\n", yytokname(yychar));
				}
			}

			if(e.yyerrflag != 3) { # incompletely recovered error ... try again
				e.yyerrflag = 3;
	
				# find a state where "error" is a legal shift action
				while(yyp >= 0) {
					yyn = yypact[yys[yyp].yys] + YYERRCODE;
					if(yyn >= 0 && yyn < YYLAST) {
						yystate = yyact[yyn];  # simulate a shift of "error"
						if(yychk[yystate] == YYERRCODE) {
							yychar = -1;
							continue yystack;
						}
					}
	
					# the current yyp has no shift on "error", pop stack
					if(yydebug >= 2)
						e.yysys->fprint(e.yystderr, "error recovery pops state %d, uncovers %d\n",
							yys[yyp].yys, yys[yyp-1].yys );
					yyp--;
				}
				# there is no state on the stack with an error shift ... abort
				yyn = 1;
				break yystack;
			}

			# no shift yet; clobber input char
			if(yydebug >= 2)
				e.yysys->fprint(e.yystderr, "error recovery discards %s\n", yytokname(yychar));
			if(yychar == YYEOFCODE) {
				yyn = 1;
				break yystack;
			}
			yychar = -1;
			# try again in the same state
		}
	
		# reduction by production yyn
		if(yydebug >= 2)
			e.yysys->fprint(e.yystderr, "reduce %d in:\n\t%s", yyn, yystatname(yystate));
	
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
			
4=>
#line	63	"mash.y"
{ yys[yypt-0].yyv.cmd.xeq(e.yyenv); }
7=>
#line	69	"mash.y"
{ e.yyval.cmd = nil; }
8=>
#line	71	"mash.y"
{ e.yyval.cmd = Cmd.cmd2(Cseq, yys[yypt-1].yyv.cmd, yys[yypt-0].yyv.cmd); }
9=>
#line	75	"mash.y"
{ e.yyval.cmd = yys[yypt-1].yyv.cmd.mkcmd(e.yyenv, yys[yypt-0].yyv.flag); }
10=>
e.yyval.cmd = yys[yyp+1].yyv.cmd;
11=>
#line	80	"mash.y"
{ e.yyval.cmd = Cmd.cmd2(Cseq, yys[yypt-1].yyv.cmd, yys[yypt-0].yyv.cmd.mkcmd(e.yyenv, 0)); }
12=>
e.yyval.cmd = yys[yyp+1].yyv.cmd;
13=>
e.yyval.cmd = yys[yyp+1].yyv.cmd;
14=>
#line	86	"mash.y"
{  e.yyval.cmd = Cmd.cmd2(Cpipe, yys[yypt-2].yyv.cmd, yys[yypt-0].yyv.cmd); }
15=>
#line	90	"mash.y"
{ e.yyval.cmd = e.yyenv.mksimple(yys[yypt-0].yyv.items); }
16=>
#line	92	"mash.y"
{
				yys[yypt-0].yyv.cmd.words = e.yyenv.mklist(yys[yypt-1].yyv.items);
				e.yyval.cmd = Cmd.cmd1w(Cdepend, yys[yypt-0].yyv.cmd, e.yyenv.mklist(yys[yypt-3].yyv.items));
			}
17=>
#line	99	"mash.y"
{ e.yyval.cmd = yys[yypt-0].yyv.cmd.cmde(Cgroup, yys[yypt-2].yyv.cmd, nil); }
18=>
#line	101	"mash.y"
{ e.yyval.cmd = yys[yypt-0].yyv.cmd.cmde(Csubgroup, yys[yypt-2].yyv.cmd, nil); }
19=>
#line	103	"mash.y"
{ e.yyval.cmd = Cmd.cmd1i(Cfor, yys[yypt-0].yyv.cmd, yys[yypt-4].yyv.item); e.yyval.cmd.words = lib->revitems(yys[yypt-2].yyv.items); }
20=>
#line	105	"mash.y"
{ e.yyval.cmd = Cmd.cmd2(Cif, yys[yypt-2].yyv.cmd, yys[yypt-0].yyv.cmd); }
21=>
#line	107	"mash.y"
{ e.yyval.cmd = Cmd.cmd2(Cif, yys[yypt-4].yyv.cmd, Cmd.cmd2(Celse, yys[yypt-2].yyv.cmd, yys[yypt-0].yyv.cmd)); }
22=>
#line	109	"mash.y"
{ e.yyval.cmd = Cmd.cmd2(Cwhile, yys[yypt-2].yyv.cmd, yys[yypt-0].yyv.cmd); }
23=>
#line	111	"mash.y"
{ e.yyval.cmd = Cmd.cmd2(Ccase, yys[yypt-3].yyv.cmd, yys[yypt-1].yyv.cmd.rotcases()); }
24=>
#line	113	"mash.y"
{ e.yyval.cmd = Cmd.cmdiw(Ceq, yys[yypt-2].yyv.item, yys[yypt-0].yyv.items); }
25=>
#line	115	"mash.y"
{ e.yyval.cmd = Cmd.cmdiw(Cdefeq, yys[yypt-2].yyv.item, yys[yypt-0].yyv.items); }
26=>
#line	117	"mash.y"
{ e.yyval.cmd = Cmd.cmd1i(Cfn, yys[yypt-0].yyv.cmd, yys[yypt-1].yyv.item); }
27=>
#line	119	"mash.y"
{ e.yyval.cmd = Cmd.cmd1i(Crescue, yys[yypt-0].yyv.cmd, yys[yypt-1].yyv.item); }
28=>
#line	121	"mash.y"
{
				yys[yypt-0].yyv.cmd.item = yys[yypt-1].yyv.item;
				e.yyval.cmd = Cmd.cmd1i(Crule, yys[yypt-0].yyv.cmd, yys[yypt-3].yyv.item);
			}
29=>
#line	128	"mash.y"
{ e.yyval.cmd = Cmd.cmd1(Clistgroup, yys[yypt-1].yyv.cmd); }
30=>
#line	130	"mash.y"
{ e.yyval.cmd = Cmd.cmd1(Cgroup, yys[yypt-1].yyv.cmd); }
31=>
#line	134	"mash.y"
{ e.yyval.cmd = Cmd.cmd1(Cnop, nil); }
32=>
e.yyval.cmd = yys[yyp+1].yyv.cmd;
33=>
#line	139	"mash.y"
{ e.yyval.cmd = nil; }
34=>
#line	141	"mash.y"
{ e.yyval.cmd = yys[yypt-1].yyv.cmd; }
35=>
#line	145	"mash.y"
{ e.yyval.cmd = nil; }
36=>
#line	147	"mash.y"
{ e.yyval.cmd = Cmd.cmd2(Ccases, yys[yypt-1].yyv.cmd, yys[yypt-0].yyv.cmd); }
37=>
#line	151	"mash.y"
{ e.yyval.cmd = Cmd.cmd2(Cmatched, yys[yypt-2].yyv.cmd, yys[yypt-0].yyv.cmd); }
38=>
#line	155	"mash.y"
{ e.yyval.items = yys[yypt-0].yyv.item :: nil; }
39=>
#line	157	"mash.y"
{ e.yyval.items = yys[yypt-0].yyv.item :: yys[yypt-1].yyv.items; }
40=>
e.yyval.item = yys[yyp+1].yyv.item;
41=>
e.yyval.item = yys[yyp+1].yyv.item;
42=>
e.yyval.item = yys[yyp+1].yyv.item;
43=>
e.yyval.item = yys[yyp+1].yyv.item;
44=>
#line	169	"mash.y"
{ e.yyval.item = Item.itemc(Ibackq, yys[yypt-1].yyv.cmd); }
45=>
#line	171	"mash.y"
{ e.yyval.item = Item.itemc(Iquote, yys[yypt-1].yyv.cmd); }
46=>
#line	173	"mash.y"
{ e.yyval.item = Item.itemc(Iinpipe, yys[yypt-1].yyv.cmd); }
47=>
#line	175	"mash.y"
{ e.yyval.item = Item.itemc(Ioutpipe, yys[yypt-1].yyv.cmd); }
48=>
e.yyval.item = yys[yyp+1].yyv.item;
49=>
#line	180	"mash.y"
{ e.yyval.item = Item.item2(Icaret, yys[yypt-2].yyv.item, yys[yypt-0].yyv.item); }
50=>
#line	182	"mash.y"
{ e.yyval.item = Item.itemc(Iexpr, yys[yypt-1].yyv.cmd); }
51=>
#line	186	"mash.y"
{ e.yyval.item = yys[yypt-0].yyv.item.sword(e.yyenv); }
52=>
#line	190	"mash.y"
{ e.yyval.items = nil; }
53=>
#line	192	"mash.y"
{ e.yyval.items = yys[yypt-0].yyv.item :: yys[yypt-1].yyv.items; }
54=>
#line	196	"mash.y"
{ e.yyval.cmd = ref Cmd; e.yyval.cmd.error = 0; }
55=>
#line	198	"mash.y"
{ e.yyval.cmd = yys[yypt-1].yyv.cmd; yys[yypt-1].yyv.cmd.cmdio(e.yyenv, yys[yypt-0].yyv.item); }
56=>
#line	202	"mash.y"
{ e.yyval.item = Item.itemr(Rin, yys[yypt-0].yyv.item); }
57=>
#line	204	"mash.y"
{ e.yyval.item = Item.itemr(Rout, yys[yypt-0].yyv.item); }
58=>
#line	206	"mash.y"
{ e.yyval.item = Item.itemr(Rappend, yys[yypt-0].yyv.item); }
59=>
#line	208	"mash.y"
{ e.yyval.item = Item.itemr(Rinout, yys[yypt-0].yyv.item); }
60=>
#line	212	"mash.y"
{ e.yyval.flag = 0; }
61=>
#line	214	"mash.y"
{ e.yyval.flag = 0; }
62=>
#line	216	"mash.y"
{ e.yyval.flag = 1; }
63=>
#line	220	"mash.y"
{ e.yyval.cmd = Cmd.cmd1i(Cword, nil, yys[yypt-0].yyv.item); }
64=>
#line	222	"mash.y"
{ e.yyval.cmd = Cmd.cmd1i(Cword, nil, yys[yypt-0].yyv.item); }
65=>
#line	224	"mash.y"
{ e.yyval.cmd = yys[yypt-1].yyv.cmd; }
66=>
#line	226	"mash.y"
{ e.yyval.cmd = Cmd.cmd2(Ccaret, yys[yypt-2].yyv.cmd, yys[yypt-0].yyv.cmd); }
67=>
#line	228	"mash.y"
{ e.yyval.cmd = Cmd.cmd1(Chd, yys[yypt-0].yyv.cmd); }
68=>
#line	230	"mash.y"
{ e.yyval.cmd = Cmd.cmd1(Ctl, yys[yypt-0].yyv.cmd); }
69=>
#line	232	"mash.y"
{ e.yyval.cmd = Cmd.cmd1(Clen, yys[yypt-0].yyv.cmd); }
70=>
#line	234	"mash.y"
{ e.yyval.cmd = Cmd.cmd1(Cnot, yys[yypt-0].yyv.cmd); }
71=>
#line	236	"mash.y"
{ e.yyval.cmd = Cmd.cmd2(Ccons, yys[yypt-2].yyv.cmd, yys[yypt-0].yyv.cmd); }
72=>
#line	238	"mash.y"
{ e.yyval.cmd = Cmd.cmd2(Ceqeq, yys[yypt-2].yyv.cmd, yys[yypt-0].yyv.cmd); }
73=>
#line	240	"mash.y"
{ e.yyval.cmd = Cmd.cmd2(Cnoteq, yys[yypt-2].yyv.cmd, yys[yypt-0].yyv.cmd); }
74=>
#line	242	"mash.y"
{ e.yyval.cmd = Cmd.cmd2(Cmatch, yys[yypt-2].yyv.cmd, yys[yypt-0].yyv.cmd); }
		}
	}

	return yyn;
}
