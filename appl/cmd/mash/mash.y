%{
include	"mash.m";

#
#	mash parser.  Thread safe.
#
%}

%module Mashparse
{
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
}

%{
	lib:		Mashlib;

	Cmd, Item, Stab, Env:		import lib;
%}

%left				Lcase Lfor Lif Lwhile Loffparen	# low prec
%left				Lelse
%left				Lpipe
%left				Leqeq Lmatch Lnoteq
%right			Lcons
%left				Lcaret
%left				Lnot Lhd Ltl Llen
%type	<flag>	term
%type	<item>	item wgen witem word redir sword
%type	<items>	asimple list
%type	<cmd>	case cases cmd cmda cmds cmdt complex
%type	<cmd>	epilog expr cbrace cobrace obrace simple
%token	<item>	Lword
%token			Lbackq Lcolon Lcolonmatch Ldefeq Leq Lmatched Lquote
%token			Loncurly Lonparen Loffcurly Loffparen Lat
%token			Lgreat Lgreatgreat Lless Llessgreat
%token			Lfn Lin Lrescue
%token			Land Leof Lsemi
%token			Lerror

%%

script	: tcmds
		;

tcmds	: # empty
		| tcmds xeq
		;

xeq		: cmda
			{ $1.xeq(e.yyenv); }
		| Leof
		| error
		;

cmdt		: # empty
			{ $$ = nil; }
		| cmdt cmda
			{ $$ = Cmd.cmd2(Cseq, $1, $2); }
		;

cmda	: cmd term
			{ $$ = $1.mkcmd(e.yyenv, $2); }
		;

cmds		: cmdt
		| cmdt cmd
			{ $$ = Cmd.cmd2(Cseq, $1, $2.mkcmd(e.yyenv, 0)); }
		;

cmd		: simple
		| complex
		| cmd Lpipe cmd
			{  $$ = Cmd.cmd2(Cpipe, $1, $3); }
		;

simple	: asimple
			{ $$ = e.yyenv.mksimple($1); }
		| asimple Lcolon list cobrace
			{
				$4.words = e.yyenv.mklist($3);
				$$ = Cmd.cmd1w(Cdepend, $4, e.yyenv.mklist($1));
			}
		;

complex	: Loncurly cmds Loffcurly epilog
			{ $$ = $4.cmde(Cgroup, $2, nil); }
		| Lat Loncurly cmds Loffcurly epilog
			{ $$ = $5.cmde(Csubgroup, $3, nil); }
		| Lfor Lonparen sword Lin list Loffparen cmd
			{ $$ = Cmd.cmd1i(Cfor, $7, $3); $$.words = lib->revitems($5); }
		| Lif Lonparen expr Loffparen cmd
			{ $$ = Cmd.cmd2(Cif, $3, $5); }
		| Lif Lonparen expr Loffparen cmd Lelse cmd
			{ $$ = Cmd.cmd2(Cif, $3, Cmd.cmd2(Celse, $5, $7)); }
		| Lwhile Lonparen expr Loffparen cmd
			{ $$ = Cmd.cmd2(Cwhile, $3, $5); }
		| Lcase expr Loncurly cases Loffcurly
			{ $$ = Cmd.cmd2(Ccase, $2, $4.rotcases()); }
		| sword Leq list
			{ $$ = Cmd.cmdiw(Ceq, $1, $3); }
		| sword Ldefeq list
			{ $$ = Cmd.cmdiw(Cdefeq, $1, $3); }
		| Lfn word obrace
			{ $$ = Cmd.cmd1i(Cfn, $3, $2); }
		| Lrescue word obrace
			{ $$ = Cmd.cmd1i(Crescue, $3, $2); }
		| word Lcolonmatch word cbrace
			{
				$4.item = $3;
				$$ = Cmd.cmd1i(Crule, $4, $1);
			}
		;

cbrace	: Lcolon Loncurly cmds Loffcurly
			{ $$ = Cmd.cmd1(Clistgroup, $3); }
		| Loncurly cmds Loffcurly
			{ $$ = Cmd.cmd1(Cgroup, $2); }
		;

cobrace	: # empty
			{ $$ = Cmd.cmd1(Cnop, nil); }
		| cbrace
		;

obrace	: # empty
			{ $$ = nil; }
		| Loncurly cmds Loffcurly
			{ $$ = $2; }
		;

cases		: # empty
			{ $$ = nil; }
		| cases case
			{ $$ = Cmd.cmd2(Ccases, $1, $2); }
		;

case		: expr Lmatched cmda
			{ $$ = Cmd.cmd2(Cmatched, $1, $3); }
		;

asimple	: word
			{ $$ = $1 :: nil; }
		| asimple item
			{ $$ = $2 :: $1; }
		;

item		: witem
		| redir
		;

witem	: word
		| wgen
		;

wgen		: Lbackq Loncurly cmds Loffcurly
			{ $$ = Item.itemc(Ibackq, $3); }
		| Lquote Loncurly cmds Loffcurly
			{ $$ = Item.itemc(Iquote, $3); }
		| Lless Loncurly cmds Loffcurly
			{ $$ = Item.itemc(Iinpipe, $3); }
		| Lgreat Loncurly cmds Loffcurly
			{ $$ = Item.itemc(Ioutpipe, $3); }
		;

word		: Lword
		| word Lcaret word
			{ $$ = Item.item2(Icaret, $1, $3); }
		| Lonparen expr Loffparen
			{ $$ = Item.itemc(Iexpr, $2); }
		;

sword	: Lword
			{ $$ = $1.sword(e.yyenv); }
		;

list		: # empty
			{ $$ = nil; }
		| list witem
			{ $$ = $2 :: $1; }
		;

epilog	: # empty
			{ $$ = ref Cmd; $$.error = 0; }
		| epilog redir
			{ $$ = $1; $1.cmdio(e.yyenv, $2); }
		;

redir		: Lless word
			{ $$ = Item.itemr(Rin, $2); }
		| Lgreat word
			{ $$ = Item.itemr(Rout, $2); }
		| Lgreatgreat word
			{ $$ = Item.itemr(Rappend, $2); }
		| Llessgreat word
			{ $$ = Item.itemr(Rinout, $2); }
		;

term		: Lsemi
			{ $$ = 0; }
		| Leof
			{ $$ = 0; }
		| Land
			{ $$ = 1; }
		;

expr		: Lword
			{ $$ = Cmd.cmd1i(Cword, nil, $1); }
		| wgen
			{ $$ = Cmd.cmd1i(Cword, nil, $1); }
		| Lonparen expr Loffparen
			{ $$ = $2; }
		| expr Lcaret expr
			{ $$ = Cmd.cmd2(Ccaret, $1, $3); }
		| Lhd expr
			{ $$ = Cmd.cmd1(Chd, $2); }
		| Ltl expr
			{ $$ = Cmd.cmd1(Ctl, $2); }
		| Llen expr
			{ $$ = Cmd.cmd1(Clen, $2); }
		| Lnot expr
			{ $$ = Cmd.cmd1(Cnot, $2); }
		| expr Lcons expr
			{ $$ = Cmd.cmd2(Ccons, $1, $3); }
		| expr Leqeq expr
			{ $$ = Cmd.cmd2(Ceqeq, $1, $3); }
		| expr Lnoteq expr
			{ $$ = Cmd.cmd2(Cnoteq, $1, $3); }
		| expr Lmatch expr
			{ $$ = Cmd.cmd2(Cmatch, $1, $3); }
		;
%%

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
