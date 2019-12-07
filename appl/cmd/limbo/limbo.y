%{
include "limbo.m";
include "draw.m";

%}

%module Limbo
{
	init:		fn(ctxt: ref Draw->Context, argv: list of string);

	YYSTYPE: adt{
		tok:	Tok;
		ids:	ref Decl;
		node:	ref Node;
		ty:	ref Type;
		types:	ref Typelist;
	};

	YYLEX: adt {
		lval: YYSTYPE;
		lex: fn(nil: self ref YYLEX): int;
		error: fn(nil: self ref YYLEX, err: string);
	};
}

%{
	#
	# lex.b
	#
	signdump:	string;			# name of function for sig debugging
	superwarn:	int;
	debug:		array of int;
	noline:		Line;
	nosrc:		Src;
	arrayz:		int;
	oldcycles:	int;
	emitcode:	string;			# emit stub routines for system module functions
	emitdyn: int;				# emit as above but for dynamic modules
	emitsbl:	string;			# emit symbol file for sysm modules
	emitstub:	int;			# emit type and call frames for system modules
	emittab:	string;			# emit table of runtime functions for this module
	errors:		int;
	mustcompile:	int;
	dontcompile:	int;
	asmsym:		int;			# generate symbols in assembly language?
	bout:		ref Bufio->Iobuf;	# output file
	bsym:		ref Bufio->Iobuf;	# symbol output file; nil => no sym out
	gendis:		int;			# generate dis or asm?
	fixss:		int;
	newfnptr:	int;		# ISELF and -ve indices
	optims: int;

	#
	# decls.b
	#
	scope:		int;
	# impmod:		ref Sym;		# name of implementation module
	impmods:		ref Decl;		# name of implementation module(s)
	nildecl:	ref Decl;		# declaration for limbo's nil
	selfdecl:	ref Decl;		# declaration for limbo's self

	#
	# types.b
	#
	tany:		ref Type;
	tbig:		ref Type;
	tbyte:		ref Type;
	terror:		ref Type;
	tint:		ref Type;
	tnone:		ref Type;
	treal:		ref Type;
	tstring:	ref Type;
	texception:	ref Type;
	tunknown:	ref Type;
	tfnptr:	ref Type;
	rtexception:	ref Type;
	descriptors:	ref Desc;		# list of all possible descriptors
	tattr:		array of Tattr;

	#
	# nodes.b
	#
	opcommute:	array of int;
	oprelinvert:	array of int;
	isused:		array of int;
	casttab:	array of array of int;	# instruction to cast from [1] to [2]

	nfns:		int;			# functions defined
	nfnexp:		int;
	fns:		array of ref Decl;	# decls for fns defined
	tree:		ref Node;		# root of parse tree

	parset:		int;			# time to parse
	checkt:		int;			# time to typecheck
	gent:		int;			# time to generate code
	writet:		int;			# time to write out code
	symt:		int;			# time to write out symbols
%}

%type	<ty>	type fnarg fnargret fnargretp adtk fixtype iditype dotiditype
%type	<ids>	ids rids nids nrids tuplist forms ftypes ftype
		bclab bctarg ptags rptags polydec
%type	<node>	zexp exp monexp term elist zelist celist
		idatom idterms idterm idlist
		initlist elemlist elem qual
		decl topdecls topdecl fndef fbody stmt stmts qstmts qbodies cqstmts cqbodies
		mdecl adtdecl mfield mfields field fields fnname
		pstmts pbodies pqual pfields pfbody pdecl dfield dfields
		eqstmts eqbodies idexc edecl raises tpoly tpolys texp export exportlist forpoly
%type	<types>	types

%right	<tok.src>	'=' Landeq Loreq Lxoreq Llsheq Lrsheq
			Laddeq Lsubeq Lmuleq Ldiveq Lmodeq Lexpeq Ldeclas
%left	<tok.src>	Lload
%left	<tok.src>	Loror
%left	<tok.src>	Landand
%right	<tok.src>	Lcons
%left	<tok.src>	'|'
%left	<tok.src>	'^'
%left	<tok.src>	'&'
%left	<tok.src>	Leq Lneq
%left	<tok.src>	'<' '>' Lleq Lgeq
%left	<tok.src>	Llsh Lrsh
%left	<tok.src>	'+' '-'
%left	<tok.src>	'*' '/' '%'
%right <tok.src> Lexp
%right	<tok.src>	Lcomm

%left	<tok.src>	'(' ')' '[' ']' Linc Ldec Lof Lref
%right	<tok.src>	Lif Lelse Lfn ':' Lexcept Lraises
%left	<tok.src>	Lmdot
%left	<tok.src>	'.'

%left	<tok.src>	Lto
%left	<tok.src>	Lor


%nonassoc	<tok.v.rval>	Lrconst
%nonassoc	<tok.v.ival>	Lconst
%nonassoc	<tok.v.idval>	Lid Ltid Lsconst
%nonassoc	<tok.src>	Llabs Lnil
			'!' '~' Llen Lhd Ltl Ltagof
			'{' '}' ';'
			Limplement Limport Linclude
			Lcon Ltype Lmodule Lcyclic
			Ladt Larray Llist Lchan Lself
			Ldo Lwhile Lfor Lbreak
			Lalt Lcase Lpick Lcont
			Lreturn Lexit Lspawn Lraise Lfix
			Ldynamic
%%
prog	: Limplement ids ';'
	{
		impmods = $2;
	} topdecls
	{
		tree = rotater($5);
	}
	| topdecls
	{
		impmods = nil;
		tree = rotater($1);
	}
	;

topdecls: topdecl
	| topdecls topdecl
	{
		if($1 == nil)
			$$ = $2;
		else if($2 == nil)
			$$ = $1;
		else
			$$ = mkbin(Oseq, $1, $2);
	}
	;

topdecl	: error ';'
	{
		$$ = nil;
	}
	| decl
	| fndef
	| adtdecl ';'
	| mdecl ';'
	| idatom '=' exp ';'
	{
		$$ = mkbin(Oas, $1, $3);
	}
	| idterm '=' exp ';'
	{
		$$ = mkbin(Oas, $1, $3);
	}
	| idatom Ldeclas exp ';'
	{
		$$ = mkbin(Odas, $1, $3);
	}
	| idterm Ldeclas exp ';'
	{
		$$ = mkbin(Odas, $1, $3);
	}
	| idterms ':' type ';'
	{
		yyerror("illegal declaration");
		$$ = nil;
	}
	| idterms ':' type '=' exp ';'
	{
		yyerror("illegal declaration");
		$$ = nil;
	}
	;

idterms : idterm
	| idterms ',' idterm
	{
		$$ = mkbin(Oseq, $1, $3);
	}
	;

decl	: Linclude Lsconst ';'
	{
		includef($2);
		$$ = nil;
	}
	| ids ':' Ltype type ';'
	{
		$$ = typedecl($1, $4);
	}
	| ids ':' Limport exp ';'
	{
		$$ = importdecl($4, $1);
		$$.src.start = $1.src.start;
		$$.src.stop = $5.stop;
	}
	| ids ':' type ';'
	{
		$$ = vardecl($1, $3);
	}
	| ids ':' type '=' exp ';'
	{
		$$ = mkbin(Ovardecli, vardecl($1, $3), varinit($1, $5));
	}
	| ids ':' Lcon exp ';'
	{
		$$ = condecl($1, $4);
	}
	| edecl
	;

edecl	: ids ':' Lexcept ';'
	{
		$$ = exdecl($1, nil);
	}
	| ids ':' Lexcept '(' tuplist ')' ';'
	{
		$$ = exdecl($1, revids($5));
	}
	;

mdecl	: ids ':' Lmodule '{' mfields '}'
	{
		$1.src.stop = $6.stop;
		$$ = moddecl($1, rotater($5));
	}
	;

mfields	:
	{
		$$ = nil;
	}
	| mfields mfield
	{
		if($1 == nil)
			$$ = $2;
		else if($2 == nil)
			$$ = $1;
		else
			$$ = mkn(Oseq, $1, $2);
	}
	| error
	{
		$$ = nil;
	}
	;

mfield	: ids ':' type ';'
	{
		$$ = fielddecl(Dglobal, typeids($1, $3));
	}
	| adtdecl ';'
	| ids ':' Ltype type ';'
	{
		$$ = typedecl($1, $4);
	}
	| ids ':' Lcon exp ';'
	{
		$$ = condecl($1, $4);
	}
	| edecl
	;

adtdecl	: ids ':' Ladt polydec '{' fields '}' forpoly
	{
		$1.src.stop = $7.stop;
		$$ = adtdecl($1, rotater($6));
		$$.ty.polys = $4;
		$$.ty.val = rotater($8);
	}
	| ids ':' Ladt polydec Lfor '{' tpolys '}' '{' fields '}'
	{
		$1.src.stop = $11.stop;
		$$ = adtdecl($1, rotater($10));
		$$.ty.polys = $4;
		$$.ty.val = rotater($7);
	}
	;

forpoly	:
	{
		$$ = nil;
	}
	| Lfor '{' tpolys '}'
	{
		$$ = $3;
	}
	;

fields	:
	{
		$$ = nil;
	}
	| fields field
	{
		if($1 == nil)
			$$ = $2;
		else if($2 == nil)
			$$ = $1;
		else
			$$ = mkn(Oseq, $1, $2);
	}
	| error
	{
		$$ = nil;
	}
	;

field	: dfield
	| pdecl
	| ids ':' Lcon exp ';'
	{
		$$ = condecl($1, $4);
	}
	;

dfields	:
	{
		$$ = nil;
	}
	| dfields dfield
	{
		if($1 == nil)
			$$ = $2;
		else if($2 == nil)
			$$ = $1;
		else
			$$ = mkn(Oseq, $1, $2);
	}
	;

dfield	: ids ':' Lcyclic type ';'
	{
		for(d := $1; d != nil; d = d.next)
			d.cyc = byte 1;
		$$ = fielddecl(Dfield, typeids($1, $4));
	}
	| ids ':' type ';'
	{
		$$ = fielddecl(Dfield, typeids($1, $3));
	}
	;

pdecl	: Lpick '{' pfields '}'
	{
		$$ = $3;
	}
	;

pfields	: pfbody dfields
	{
		$1.right.right = $2;
		$$ = $1;
	}
	| pfbody error
	{
		$$ = nil;
	}
	| error
	{
		$$ = nil;
	}
	;

pfbody	: ptags Llabs
	{
		$$ = mkn(Opickdecl, nil, mkn(Oseq, fielddecl(Dtag, $1), nil));
		typeids($1, mktype($1.src.start, $1.src.stop, Tadtpick, nil, nil));
	}
	| pfbody dfields ptags Llabs
	{
		$1.right.right = $2;
		$$ = mkn(Opickdecl, $1, mkn(Oseq, fielddecl(Dtag, $3), nil));
		typeids($3, mktype($3.src.start, $3.src.stop, Tadtpick, nil, nil));
	}
	| pfbody error ptags Llabs
	{
		$$ = mkn(Opickdecl, nil, mkn(Oseq, fielddecl(Dtag, $3), nil));
		typeids($3, mktype($3.src.start, $3.src.stop, Tadtpick, nil, nil));
	}
	;

ptags	: rptags
	{
		$$ = revids($1);
	}
	;

rptags	: Lid
	{
		$$ = mkids($<tok.src>1, $1, nil, nil);
	}
	| rptags Lor Lid
	{
		$$ = mkids($<tok.src>3, $3, nil, $1);
	}
	;

ids	: rids
	{
		$$ = revids($1);
	}
	;

rids	: Lid
	{
		$$ = mkids($<tok.src>1, $1, nil, nil);
	}
	| rids ',' Lid
	{
		$$ = mkids($<tok.src>3, $3, nil, $1);
	}
	;

fixtype	: Lfix '(' exp ',' exp ')'
	{
		$$ = mktype($1.start, $6.stop, Tfix, nil, nil);
		$$.val = mkbin(Oseq, $3, $5);
	}
	|	Lfix '(' exp ')'
	{
		$$ = mktype($1.start, $4.stop, Tfix, nil, nil);
		$$.val = $3;
	}
	;

types	: type
	{
		$$ = addtype($1, nil);
	}
	|	Lcyclic type
	{
		$$ = addtype($2, nil);
		$2.flags |= CYCLIC;
	}
	| types ',' type
	{
		$$ = addtype($3, $1);
	}
	| types ',' Lcyclic type
	{
		$$ = addtype($4, $1);
		$4.flags |= CYCLIC;
	}
	;

type	: Ltid
	{
		$$ = mkidtype($<tok.src>1, $1);
	}
	| iditype
	{
		$$ = $1;
	}
	| dotiditype
	{
		$$ = $1;
	}
	| type Lmdot Lid
	{
		$$ = mkarrowtype($1.src.start, $<tok.src>3.stop, $1, $3);
	}
	| type Lmdot Lid '[' types ']'
	{
		$$ = mkarrowtype($1.src.start, $<tok.src>3.stop, $1, $3);
		$$ = mkinsttype($1.src, $$, $5);
	}
	| Lref type
	{
		$$ = mktype($1.start, $2.src.stop, Tref, $2, nil);
	}
	| Lchan Lof type
	{
		$$ = mktype($1.start, $3.src.stop, Tchan, $3, nil);
	}
	| '(' tuplist ')'
	{
		if($2.next == nil)
			$$ = $2.ty;
		else
			$$ = mktype($1.start, $3.stop, Ttuple, nil, revids($2));
	}
	| Larray Lof type
	{
		$$ = mktype($1.start, $3.src.stop, Tarray, $3, nil);
	}
	| Llist Lof type
	{
		$$ = mktype($1.start, $3.src.stop, Tlist, $3, nil);
	}
	| Lfn polydec fnargretp raises
	{
		$3.src.start = $1.start;
		$3.polys = $2;
		$3.eraises = $4;
		$$ = $3;
	}
	| fixtype
#	| Lexcept
#	{
#		$$ = mktype($1.start, $1.stop, Texception, nil, nil);
#		$$.cons = byte 1;
#	}
#	| Lexcept '(' tuplist ')'
#	{
#		$$ = mktype($1.start, $4.stop, Texception, nil, revids($3));
#		$$.cons = byte 1;
#	}
	;

iditype	: Lid
	{
		$$ = mkidtype($<tok.src>1, $1);
	}
	| Lid '[' types ']'
	{
		$$ = mkinsttype($<tok.src>1, mkidtype($<tok.src>1, $1), $3);
	}
	;

dotiditype	: type '.' Lid
	{
		$$ = mkdottype($1.src.start, $<tok.src>3.stop, $1, $3);
	}
	| type '.' Lid '[' types ']'
	{
		$$ = mkdottype($1.src.start, $<tok.src>3.stop, $1, $3);
		$$ = mkinsttype($1.src, $$, $5);
	}
	;

tuplist	: type
	{
		$$ = mkids($1.src, nil, $1, nil);
	}
	| tuplist ',' type
	{
		$$ = mkids($1.src, nil, $3, $1);
	}
	;

polydec	:
	{
		$$ = nil;
	}
	|	'[' ids ']'
	{
		$$ = polydecl($2);
	}
	;

fnarg	: '(' forms ')'
	{
		$$ = mktype($1.start, $3.stop, Tfn, tnone, $2);
	}
	| '(' '*' ')'
	{
		$$ = mktype($1.start, $3.stop, Tfn, tnone, nil);
		$$.varargs = byte 1;
	}
	| '(' ftypes ',' '*' ')'
	{
		$$ = mktype($1.start, $5.stop, Tfn, tnone, $2);
		$$.varargs = byte 1;
	}
	;

fnargret: fnarg %prec ':'
	{
		$$ = $1;
	}
	| fnarg ':' type
	{
		$1.tof = $3;
		$1.src.stop = $3.src.stop;
		$$ = $1;
	}
	;

fnargretp:	fnargret %prec '='
	{
		$$ = $1;
	}
	| fnargret Lfor '{' tpolys '}'
	{
		$$ = $1;
		$$.val = rotater($4);
	}
	;

forms	:
	{
		$$ = nil;
	}
	| ftypes
	;

ftypes	: ftype
	| ftypes ',' ftype
	{
		$$ = appdecls($1, $3);
	}
	;

ftype	: nids ':' type
	{
		$$ = typeids($1, $3);
	}
	| nids ':' adtk
	{
		$$ = typeids($1, $3);
		for(d := $$; d != nil; d = d.next)
			d.implicit = byte 1;
	}
	| idterms ':' type
	{
		$$ = mkids($1.src, enter("junk", 0), $3, nil);
		$$.store = Darg;
		yyerror("illegal argument declaration");
	}
	| idterms ':' adtk
	{
		$$ = mkids($1.src, enter("junk", 0), $3, nil);
		$$.store = Darg;
		yyerror("illegal argument declaration");
	}
	;

nids	: nrids
	{
		$$ = revids($1);
	}
	;

nrids	: Lid
	{
		$$ = mkids($<tok.src>1, $1, nil, nil);
		$$.store = Darg;
	}
	| Lnil
	{
		$$ = mkids($1, nil, nil, nil);
		$$.store = Darg;
	}
	| nrids ',' Lid
	{
		$$ = mkids($<tok.src>3, $3, nil, $1);
		$$.store = Darg;
	}
	| nrids ',' Lnil
	{
		$$ = mkids($3, nil, nil, $1);
		$$.store = Darg;
	}
	;

adtk	: Lself iditype
	{
		$$ = $2;
	}
	| Lself Lref iditype
	{
		$$ = mktype($<tok.src>2.start, $<tok.src>3.stop, Tref, $3, nil);
	}
	| Lself dotiditype
	{
		$$ = $2;
	}
	| Lself Lref dotiditype
	{
		$$ = mktype($<tok.src>2.start, $<tok.src>3.stop, Tref, $3, nil);
	}
	;

fndef	: fnname fnargretp raises fbody
	{
		$$ = fndecl($1, $2, $4);
		nfns++;
		# patch up polydecs
		if($1.op == Odot){
			if($1.right.left != nil){
				$2.polys = $1.right.left.decl;
				$1.right.left = nil;
			}
			if($1.left.op == Oname && $1.left.left != nil){
				$$.decl = $1.left.left.decl;
				$1.left.left = nil;
			}
		}
		else{
			if($1.left != nil){
				$2.polys = $1.left.decl;
				$1.left = nil;
			}
		}
		$2.eraises = $3;
		$$.src = $1.src;
	}
	;

raises	: Lraises '(' idlist ')'
	{
		$$ = mkn(Otuple, rotater($3), nil);
		$$.src.start = $1.start;
		$$.src.stop = $4.stop;
	}
	|	Lraises idatom
	{
		$$ = mkn(Otuple, mkunary(Oseq, $2), nil);
		$$.src.start = $1.start;
		$$.src.stop = $2.src.stop;
	}
	|	%prec Lraises
	{
		$$ = nil;
	}
	;

fbody	: '{' stmts '}'
	{
		if($2 == nil){
			$2 = mkn(Onothing, nil, nil);
			$2.src.start = curline();
			$2.src.stop = $2.src.start;
		}
		$$ = rotater($2);
		$$.src.start = $1.start;
		$$.src.stop = $3.stop;
	}
	| error '}'
	{
		$$ = mkn(Onothing, nil, nil);
	}
	| error '{' stmts '}'
	{
		$$ = mkn(Onothing, nil, nil);
	}
	;

fnname	: Lid polydec
	{
		$$ = mkname($<tok.src>1, $1);
		if($2 != nil){
			$$.left = mkn(Onothing, nil ,nil);
			$$.left.decl = $2;
		}
	}
	| fnname '.' Lid polydec
	{
		$$ = mkbin(Odot, $1, mkname($<tok.src>3, $3));
		if($4 != nil){
			$$.right.left = mkn(Onothing, nil ,nil);
			$$.right.left.decl = $4;
		}
	}
	;

stmts	:
	{
		$$ = nil;
	}
	| stmts decl
	{
		if($1 == nil)
			$$ = $2;
		else if($2 == nil)
			$$ = $1;
		else
			$$ = mkbin(Oseq, $1, $2);
	}
	| stmts stmt
	{
		if($1 == nil)
			$$ = $2;
		else
			$$ = mkbin(Oseq, $1, $2);
	}
	;

elists	: '(' elist ')'
	| elists ',' '(' elist ')'
	;

stmt	: error ';'
	{
		$$ = mkn(Onothing, nil, nil);
		$$.src.start = curline();
		$$.src.stop = $$.src.start;
	}
	| error '}'
	{
		$$ = mkn(Onothing, nil, nil);
		$$.src.start = curline();
		$$.src.stop = $$.src.start;
	}
	| error '{' stmts '}'
	{
		$$ = mkn(Onothing, nil, nil);
		$$.src.start = curline();
		$$.src.stop = $$.src.start;
	}
	| '{' stmts '}'
	{
		if($2 == nil){
			$2 = mkn(Onothing, nil, nil);
			$2.src.start = curline();
			$2.src.stop = $2.src.start;
		}
		$$ = mkscope(rotater($2));
	}
	| elists ':' type ';'
	{
		yyerror("illegal declaration");
		$$ = mkn(Onothing, nil, nil);
		$$.src.start = curline();
		$$.src.stop = $$.src.start;
	}
	| elists ':' type '=' exp';'
	{
		yyerror("illegal declaration");
		$$ = mkn(Onothing, nil, nil);
		$$.src.start = curline();
		$$.src.stop = $$.src.start;
	}
	| zexp ';'
	{
		$$ = $1;
	}
	| Lif '(' exp ')' stmt
	{
		$$ = mkn(Oif, $3, mkunary(Oseq, $5));
		$$.src.start = $1.start;
		$$.src.stop = $5.src.stop;
	}
	| Lif '(' exp ')' stmt Lelse stmt
	{
		$$ = mkn(Oif, $3, mkbin(Oseq, $5, $7));
		$$.src.start = $1.start;
		$$.src.stop = $7.src.stop;
	}
	| bclab Lfor '(' zexp ';' zexp ';' zexp ')' stmt
	{
		$$ = mkunary(Oseq, $10);
		if($8.op != Onothing)
			$$.right = $8;
		$$ = mkbin(Ofor, $6, $$);
		$$.decl = $1;
		if($4.op != Onothing)
			$$ = mkbin(Oseq, $4, $$);
	}
	| bclab Lwhile '(' zexp ')' stmt
	{
		$$ = mkn(Ofor, $4, mkunary(Oseq, $6));
		$$.src.start = $2.start;
		$$.src.stop = $6.src.stop;
		$$.decl = $1;
	}
	| bclab Ldo stmt Lwhile '(' zexp ')' ';'
	{
		$$ = mkn(Odo, $6, $3);
		$$.src.start = $2.start;
		$$.src.stop = $7.stop;
		$$.decl = $1;
	}
	| Lbreak bctarg ';'
	{
		$$ = mkn(Obreak, nil, nil);
		$$.decl = $2;
		$$.src = $1;
	}
	| Lcont bctarg ';'
	{
		$$ = mkn(Ocont, nil, nil);
		$$.decl = $2;
		$$.src = $1;
	}
	| Lreturn zexp ';'
	{
		$$ = mkn(Oret, $2, nil);
		$$.src = $1;
		if($2.op == Onothing)
			$$.left = nil;
		else
			$$.src.stop = $2.src.stop;
	}
	| Lspawn exp ';'
	{
		$$ = mkn(Ospawn, $2, nil);
		$$.src.start = $1.start;
		$$.src.stop = $2.src.stop;
	}
	| Lraise zexp ';'
	{
		$$ = mkn(Oraise, $2, nil);
		$$.src.start = $1.start;
		$$.src.stop = $2.src.stop;
	}
	| bclab Lcase exp '{' cqstmts '}'
	{
		$$ = mkn(Ocase, $3, caselist($5, nil));
		$$.src = $3.src;
		$$.decl = $1;
	}
	| bclab Lalt '{' qstmts '}'
	{
		$$ = mkn(Oalt, caselist($4, nil), nil);
		$$.src = $2;
		$$.decl = $1;
	}
	| bclab Lpick Lid Ldeclas exp '{' pstmts '}'
	{
		$$ = mkn(Opick, mkbin(Odas, mkname($<tok.src>3, $3), $5), caselist($7, nil));
		$$.src.start = $<tok.src>3.start;
		$$.src.stop = $5.src.stop;
		$$.decl = $1;
	}
	| Lexit ';'
	{
		$$ = mkn(Oexit, nil, nil);
		$$.src = $1;
	}
	| '{' stmts '}' Lexcept idexc '{' eqstmts '}'
	{
		if($2 == nil){
			$2 = mkn(Onothing, nil, nil);
			$2.src.start = $2.src.stop = curline();
		}
		$2 = mkscope(rotater($2));
		$$ = mkbin(Oexstmt, $2, mkn(Oexcept, $5, caselist($7, nil)));
	}
#	| stmt Lexcept idexc '{' eqstmts '}'
#	{
#		$$ = mkbin(Oexstmt, $1, mkn(Oexcept, $3, caselist($5, nil)));
#	}
	;

bclab	:
	{
		$$ = nil;
	}
	| ids ':'
	{
		if($1.next != nil)
			yyerror("only one identifier allowed in a label");
		$$ = $1;
	}
	;

bctarg	:
	{
		$$ = nil;
	}
	| Lid
	{
		$$ = mkids($<tok.src>1, $1, nil, nil);
	}
	;

qstmts	: qbodies stmts
	{
		$1.left.right.right = $2;
		$$ = $1;
	}
	;

qbodies	: qual Llabs
	{
		$$ = mkunary(Oseq, mkscope(mkunary(Olabel, rotater($1))));
	}
	| qbodies stmts qual Llabs
	{
		$1.left.right.right = $2;
		$$ = mkbin(Oseq, mkscope(mkunary(Olabel, rotater($3))), $1);
	}
	;

cqstmts	: cqbodies stmts
	{
		$1.left.right = mkscope($2);
		$$ = $1;
	}
	;

cqbodies	: qual Llabs
	{
		$$ = mkunary(Oseq, mkunary(Olabel, rotater($1)));
	}
	| cqbodies stmts qual Llabs
	{
		$1.left.right = mkscope($2);
		$$ = mkbin(Oseq, mkunary(Olabel, rotater($3)), $1);
	}
	;

eqstmts	: eqbodies stmts
	{
		$1.left.right = mkscope($2);
		$$ = $1;
	}
	;

eqbodies	: qual Llabs
	{
		$$ = mkunary(Oseq, mkunary(Olabel, rotater($1)));
	}
	| eqbodies stmts qual Llabs
	{
		$1.left.right = mkscope($2);
		$$ = mkbin(Oseq, mkunary(Olabel, rotater($3)), $1);
	}
	;

qual	: exp
	| exp Lto exp
	{
		$$ = mkbin(Orange, $1, $3);
	}
	| '*'
	{
		$$ = mkn(Owild, nil, nil);
		$$.src = $1;
	}
	| qual Lor qual
	{
		$$ = mkbin(Oseq, $1, $3);
	}
	| error
	{
		$$ = mkn(Onothing, nil, nil);
		$$.src.start = curline();
		$$.src.stop = $$.src.start;
	}
	;

pstmts	: pbodies stmts
	{
		$1.left.right = mkscope($2);
		$$ = $1;
	}
	;

pbodies	: pqual Llabs
	{
		$$ = mkunary(Oseq, mkunary(Olabel, rotater($1)));
	}
	| pbodies stmts pqual Llabs
	{
		$1.left.right = mkscope($2);
		$$ = mkbin(Oseq, mkunary(Olabel, rotater($3)), $1);
	}
	;

pqual	: Lid
	{
		$$ = mkname($<tok>1.src, $1);
	}
	| '*'
	{
		$$ = mkn(Owild, nil, nil);
		$$.src = $1;
	}
	| pqual Lor pqual
	{
		$$ = mkbin(Oseq, $1, $3);
	}
	| error
	{
		$$ = mkn(Onothing, nil, nil);
		$$.src.start = curline();
		$$.src.stop = $$.src.start;
	}
	;

zexp	:
	{
		$$ = mkn(Onothing, nil, nil);
		$$.src.start = curline();
		$$.src.stop = $$.src.start;
	}
	| exp
	;

exp	: monexp
	| exp '=' exp
	{
		$$ = mkbin(Oas, $1, $3);
	}
	| exp Landeq exp
	{
		$$ = mkbin(Oandas, $1, $3);
	}
	| exp Loreq exp
	{
		$$ = mkbin(Ooras, $1, $3);
	}
	| exp Lxoreq exp
	{
		$$ = mkbin(Oxoras, $1, $3);
	}
	| exp Llsheq exp
	{
		$$ = mkbin(Olshas, $1, $3);
	}
	| exp Lrsheq exp
	{
		$$ = mkbin(Orshas, $1, $3);
	}
	| exp Laddeq exp
	{
		$$ = mkbin(Oaddas, $1, $3);
	}
	| exp Lsubeq exp
	{
		$$ = mkbin(Osubas, $1, $3);
	}
	| exp Lmuleq exp
	{
		$$ = mkbin(Omulas, $1, $3);
	}
	| exp Ldiveq exp
	{
		$$ = mkbin(Odivas, $1, $3);
	}
	| exp Lmodeq exp
	{
		$$ = mkbin(Omodas, $1, $3);
	}
	| exp Lexpeq exp
	{
		$$ = mkbin(Oexpas, $1, $3);
	}
	| exp Lcomm '=' exp
	{
		$$ = mkbin(Osnd, $1, $4);
	}
	| exp Lcomm exp
	{
		$$ = mkbin(Osnd, $1, $3);
	}
	| exp Ldeclas exp
	{
		$$ = mkbin(Odas, $1, $3);
	}
	| Lload Lid exp %prec Lload
	{
		$$ = mkn(Oload, $3, nil);
		$$.src.start = $<tok.src.start>1;
		$$.src.stop = $3.src.stop;
		$$.ty = mkidtype($<tok.src>2, $2);
	}
	| exp Lexp exp
	{
		$$ = $$ = mkbin(Oexp, $1, $3);
	}
	| exp '*' exp
	{
		$$ = mkbin(Omul, $1, $3);
	}
	| exp '/' exp
	{
		$$ = mkbin(Odiv, $1, $3);
	}
	| exp '%' exp
	{
		$$ = mkbin(Omod, $1, $3);
	}
	| exp '+' exp
	{
		$$ = mkbin(Oadd, $1, $3);
	}
	| exp '-' exp
	{
		$$ = mkbin(Osub, $1, $3);
	}
	| exp Lrsh exp
	{
		$$ = mkbin(Orsh, $1, $3);
	}
	| exp Llsh exp
	{
		$$ = mkbin(Olsh, $1, $3);
	}
	| exp '<' exp
	{
		$$ = mkbin(Olt, $1, $3);
	}
	| exp '>' exp
	{
		$$ = mkbin(Ogt, $1, $3);
	}
	| exp Lleq exp
	{
		$$ = mkbin(Oleq, $1, $3);
	}
	| exp Lgeq exp
	{
		$$ = mkbin(Ogeq, $1, $3);
	}
	| exp Leq exp
	{
		$$ = mkbin(Oeq, $1, $3);
	}
	| exp Lneq exp
	{
		$$ = mkbin(Oneq, $1, $3);
	}
	| exp '&' exp
	{
		$$ = mkbin(Oand, $1, $3);
	}
	| exp '^' exp
	{
		$$ = mkbin(Oxor, $1, $3);
	}
	| exp '|' exp
	{
		$$ = mkbin(Oor, $1, $3);
	}
	| exp Lcons exp
	{
		$$ = mkbin(Ocons, $1, $3);
	}
	| exp Landand exp
	{
		$$ = mkbin(Oandand, $1, $3);
	}
	| exp Loror exp
	{
		$$ = mkbin(Ooror, $1, $3);
	}
	;

monexp	: term
	| '+' monexp
	{
		$2.src.start = $1.start;
		$$ = $2;
	}
	| '-' monexp
	{
		$$ = mkunary(Oneg, $2);
		$$.src.start = $1.start;
	}
	| '!' monexp
	{
		$$ = mkunary(Onot, $2);
		$$.src.start = $1.start;
	}
	| '~' monexp
	{
		$$ = mkunary(Ocomp, $2);
		$$.src.start = $1.start;
	}
	| '*' monexp
	{
		$$ = mkunary(Oind, $2);
		$$.src.start = $1.start;
	}
	| Linc monexp
	{
		$$ = mkunary(Opreinc, $2);
		$$.src.start = $1.start;
	}
	| Ldec monexp
	{
		$$ = mkunary(Opredec, $2);
		$$.src.start = $1.start;
	}
	| Lcomm monexp
	{
		$$ = mkunary(Orcv, $2);
		$$.src.start = $1.start;
	}
	| Lhd monexp
	{
		$$ = mkunary(Ohd, $2);
		$$.src.start = $1.start;
	}
	| Ltl monexp
	{
		$$ = mkunary(Otl, $2);
		$$.src.start = $1.start;
	}
	| Llen monexp
	{
		$$ = mkunary(Olen, $2);
		$$.src.start = $1.start;
	}
	| Lref monexp
	{
		$$ = mkunary(Oref, $2);
		$$.src.start = $1.start;
	}
	| Ltagof monexp
	{
		$$ = mkunary(Otagof, $2);
		$$.src.start = $1.start;
	}
	| Larray '[' exp ']' Lof type
	{
		$$ = mkn(Oarray, $3, nil);
		$$.ty = mktype($1.start, $6.src.stop, Tarray, $6, nil);
		$$.src = $$.ty.src;
	}
	| Larray '[' exp ']' Lof '{' initlist '}'
	{
		$$ = mkn(Oarray, $3, $7);
		$$.src.start = $1.start;
		$$.src.stop = $8.stop;
	}
	| Larray '[' ']' Lof '{' initlist '}'
	{
		$$ = mkn(Onothing, nil, nil);
		$$.src.start = $2.start;
		$$.src.stop = $3.stop;
		$$ = mkn(Oarray, $$, $6);
		$$.src.start = $1.start;
		$$.src.stop = $7.stop;
	}
	| Llist Lof '{' celist '}'
	{
		$$ = etolist($4);
		$$.src.start = $1.start;
		$$.src.stop = $5.stop;
	}
	| Lchan Lof type
	{
		$$ = mkn(Ochan, nil, nil);
		$$.ty = mktype($1.start, $3.src.stop, Tchan, $3, nil);
		$$.src = $$.ty.src;
	}
	| Lchan '[' exp ']' Lof type
	{
		$$ = mkn(Ochan, $3, nil);
		$$.ty = mktype($1.start, $6.src.stop, Tchan, $6, nil);
		$$.src = $$.ty.src;
	}
	| Larray Lof Ltid monexp
	{
		$$ = mkunary(Ocast, $4);
		$$.ty = mktype($1.start, $4.src.stop, Tarray, mkidtype($<tok.src>3, $3), nil);
		$$.src = $$.ty.src;
	}
	| Ltid monexp
	{
		$$ = mkunary(Ocast, $2);
		$$.src.start = $<tok.src>1.start;
		$$.ty = mkidtype($$.src, $1);
	}
	| Lid monexp
	{
		$$ = mkunary(Ocast, $2);
		$$.src.start = $<tok.src>1.start;
		$$.ty = mkidtype($$.src, $1);
	}
	| fixtype monexp
	{
		$$ = mkunary(Ocast, $2);
		$$.src.start = $<tok.src>1.start;
		$$.ty = $1;
	}
	;

term	: idatom
	| term '(' zelist ')'
	{
		$$ = mkn(Ocall, $1, $3);
		$$.src.start = $1.src.start;
		$$.src.stop = $4.stop;
	}
	| '(' elist ')'
	{
		$$ = $2;
		if($2.op == Oseq)
			$$ = mkn(Otuple, rotater($2), nil);
		else
			$$.flags |= byte PARENS;
		$$.src.start = $1.start;
		$$.src.stop = $3.stop;
	}
	| Lfn fnargret
	{
#		n := mkdeclname($1, mkids($1, enter(".fn"+string nfnexp++, 0), nil, nil));
#		$<node>$ = fndef(n, $2);
#		nfns++;
	} fbody
	{
#		$$ = fnfinishdef($<node>3, $4);
#		$$ = mkdeclname($1, $$.left.decl);
		yyerror("urt unk");
		$$ = nil;
	}
	| term '.' Lid
	{
		$$ = mkbin(Odot, $1, mkname($<tok.src>3, $3));
	}
	| term Lmdot term
	{
		$$ = mkbin(Omdot, $1, $3);
	}
	| term '[' export ']'
	{
		$$ = mkbin(Oindex, $1, $3);
		$$.src.stop = $4.stop;
	}
	| term '[' zexp ':' zexp ']'
	{
		if($3.op == Onothing)
			$3.src = $4;
		if($5.op == Onothing)
			$5.src = $4;
		$$ = mkbin(Oslice, $1, mkbin(Oseq, $3, $5));
		$$.src.stop = $6.stop;
	}
	| term Linc
	{
		$$ = mkunary(Oinc, $1);
		$$.src.stop = $2.stop;
	}
	| term Ldec
	{
		$$ = mkunary(Odec, $1);
		$$.src.stop = $2.stop;
	}
	| Lsconst
	{
		$$ = mksconst($<tok.src>1, $1);
	}
	| Lconst
	{
		$$ = mkconst($<tok.src>1, $1);
		if($1 > big 16r7fffffff || $1 < big -16r7fffffff)
			$$.ty = tbig;
	}
	| Lrconst
	{
		$$ = mkrconst($<tok.src>1, $1);
	}
	| term '[' exportlist ',' export ']'
	{
		$$ = mkbin(Oindex, $1, rotater(mkbin(Oseq, $3, $5)));
		$$.src.stop = $6.stop;
	}
	;

idatom	: Lid
	{
		$$ = mkname($<tok.src>1, $1);
	}
	| Lnil
	{
		$$ = mknil($<tok.src>1);
	}
	;

idterm	: '(' idlist ')'
	{
		$$ = mkn(Otuple, rotater($2), nil);
		$$.src.start = $1.start;
		$$.src.stop = $3.stop;
	}
	;

exportlist	: export
	| exportlist ',' export
	{
		$$ = mkbin(Oseq, $1, $3);
	}
	;

export	: exp
	|	texp
	;

texp	: Ltid
	{
		$$ = mkn(Otype, nil, nil);
		$$.ty = mkidtype($<tok.src>1, $1);
		$$.src = $$.ty.src;
	}
	| Larray Lof type
	{
		$$ = mkn(Otype, nil, nil);
		$$.ty = mktype($1.start, $3.src.stop, Tarray, $3, nil);
		$$.src = $$.ty.src;
	}
	| Llist Lof type
	{
		$$ = mkn(Otype, nil, nil);
		$$.ty = mktype($1.start, $3.src.stop, Tlist, $3, nil);
		$$.src = $$.ty.src;
	}
	| Lcyclic type
	{
		$$ = mkn(Otype, nil ,nil);
		$$.ty = $2;
		$$.ty.flags |= CYCLIC;
		$$.src = $$.ty.src;
	}
	;

idexc	: Lid
	{
		$$ = mkname($<tok.src>1, $1);
	}
	|	# empty
	{
		$$ = nil;
	}
	;

idlist	: idterm
	| idatom
	| idlist ',' idterm
	{
		$$ = mkbin(Oseq, $1, $3);
	}
	| idlist ',' idatom
	{
		$$ = mkbin(Oseq, $1, $3);
	}
	;

zelist	:
	{
		$$ = nil;
	}
	| elist
	{
		$$ = rotater($1);
	}
	;

celist	: elist
	| elist ','
	;

elist	: exp
	| elist ',' exp
	{
		$$ = mkbin(Oseq, $1, $3);
	}
	;

initlist	: elemlist
	{
		$$ = rotater($1);
	}
	| elemlist ','
	{
		$$ = rotater($1);
	}
	;

elemlist	: elem
	| elemlist ',' elem
	{
		$$ = mkbin(Oseq, $1, $3);
	}
	;

elem	: exp
	{
		$$ = mkn(Oelem, nil, $1);
		$$.src = $1.src;
	}
	| qual Llabs exp
	{
		$$ = mkbin(Oelem, rotater($1), $3);
	}
	;

tpolys	: tpoly dfields
	{
		if($1.op == Oseq)
			$1.right.left = rotater($2);
		else
			$1.left = rotater($2);
		$$ = $1;
	}
	;

tpoly	: ids Llabs
	{
		$$ = typedecl($1, mktype($1.src.start, $2.stop, Tpoly, nil, nil));
	}
	| tpoly dfields ids Llabs
	{
		if($1.op == Oseq)
			$1.right.left = rotater($2);
		else
			$1.left = rotater($2);
		$$ = mkbin(Oseq, $1, typedecl($3, mktype($3.src.start, $4.stop, Tpoly, nil, nil)));
	}
	;

%%

include "ipints.m";
include "crypt.m";

sys:	Sys;
	print, fprint, sprint: import sys;

bufio:	Bufio;
	Iobuf: import bufio;

str:		String;

crypt:Crypt;
	md5: import crypt;

math:	Math;
	import_real, export_real, isnan: import math;

yyctxt: ref YYLEX;

canonnan: real;

debug	= array[256] of {* => 0};

noline	= -1;
nosrc	= Src(-1, -1);

infile:	string;

# front end
include "arg.m";
include "lex.b";
include "types.b";
include "nodes.b";
include "decls.b";

include "typecheck.b";

# back end
include "gen.b";
include "ecom.b";
include "asm.b";
include "dis.b";
include "sbl.b";
include "stubs.b";
include "com.b";
include "optim.b";

init(nil: ref Draw->Context, argv: list of string)
{
	s: string;

	sys = load Sys Sys->PATH;
	crypt = load Crypt Crypt->PATH;
	math = load Math Math->PATH;
	bufio = load Bufio Bufio->PATH;
	if(bufio == nil){
		sys->print("can't load %s: %r\n", Bufio->PATH);
		raise("fail:bad module");
	}
	str = load String String->PATH;
	if(str == nil){
		sys->print("can't load %s: %r\n", String->PATH);
		raise("fail:bad module");
	}

	stderr = sys->fildes(2);
	yyctxt = ref YYLEX;

	math->FPcontrol(0, Math->INVAL|Math->ZDIV|Math->OVFL|Math->UNFL|Math->INEX);
	na := array[1] of {0.};
	import_real(array[8] of {byte 16r7f, * => byte 16rff}, na);
	canonnan = na[0];
	if(!isnan(canonnan))
		fatal("bad canonical NaN");

	lexinit();
	typeinit();
	optabinit();

	gendis = 1;
	asmsym = 0;
	maxerr = 20;
	ofile := "";
	ext := "";

	arg := Arg.init(argv);
	while(c := arg.opt()){
		case c{
		'Y' =>
			emitsbl = arg.arg();
			if(emitsbl == nil)
				usage();
		'C' =>
			dontcompile = 1;
		'D' =>
			#
			# debug flags:
			#
			# a	alt compilation
			# A	array constructor compilation
			# b	boolean and branch compilation
			# c	case compilation
			# d	function declaration
			# D	descriptor generation
			# e	expression compilation
			# E	addressable expression compilation
			# f	print arguments for compiled functions
			# F	constant folding
			# g	print out globals
			# m	module declaration and type checking
			# n	nil references
			# s	print sizes of output file sections
			# S	type signing
			# t	type checking function bodies
			# T	timing
			# v	global var and constant compilation
			# x	adt verification
			# Y	tuple compilation
			# z Z	bug fixes
			#
			s = arg.arg();
			for(i := 0; i < len s; i++){
				c = s[i];
				if(c < len debug)
					debug[c] = 1;
			}
		'I' =>
			s = arg.arg();
			if(s == "")
				usage();
			addinclude(s);
		'G' =>
			asmsym = 1;
		'S' =>
			gendis = 0;
		'a' =>
			emitstub = 1;
		'A' =>
			emitstub = emitdyn = 1;
		'c' =>
			mustcompile = 1;
		'e' =>
			maxerr = 1000;
		'f' =>
			fabort = 1;
		'F' =>
			newfnptr = 1;
		'g' =>
			dosym = 1;
		'i' =>
			dontinline = 1;
		'o' =>
			ofile = arg.arg();
		'O' =>
			optims = 1;
		's' =>
			s = arg.arg();
			if(s != nil)
				fixss = int s;
		't' =>
			emittab = arg.arg();
			if(emittab == nil)
				usage();
		'T' =>
			emitcode = arg.arg();
			if(emitcode == nil)
				usage();
		'd' =>
			emitcode = arg.arg();
			if(emitcode == nil)
				usage();
			emitdyn = 1;
		'w' =>
			superwarn = dowarn;
			dowarn = 1;
		'x' =>
			ext = arg.arg();
		'X' =>
			signdump = arg.arg();
		'z' =>
			arrayz = 1;
		'y' =>
			oldcycles = 1;
		* =>
			usage();
		}
	}

	addinclude("/module");

	argv = arg.argv;
	arg = nil;

	if(argv == nil){
		usage();
	}else if(ofile != nil){
		if(len argv != 1)
			usage();
		translate(hd argv, ofile, mkfileext(ofile, ".dis", ".sbl"));
	}else{
		pr := len argv != 1;
		if(ext == ""){
			ext = ".s";
			if(gendis)
				ext = ".dis";
		}
		for(; argv != nil; argv = tl argv){
			file := hd argv;
			(nil, s) = str->splitr(file, "/");
			if(pr)
				print("%s:\n", s);
			out := mkfileext(s, ".b", ext);
			translate(file, out, mkfileext(out, ext, ".sbl"));
		}
	}
	if (toterrors > 0)
		raise("fail:errors");
}

usage()
{
	fprint(stderr, "usage: limbo [-GSagwe] [-I incdir] [-o outfile] [-{T|t|d} module] [-D debug] file ...\n");
	raise("fail:usage");
}

mkfileext(file, oldext, ext: string): string
{
	n := len file;
	n2 := len oldext;
	if(n >= n2 && file[n-n2:] == oldext)
		file = file[:n-n2];
	return file + ext;
}

translate(in, out, dbg: string)
{
	infile = in;
	outfile = out;
	errors = 0;
	bins[0] = bufio->open(in, Bufio->OREAD);
	if(bins[0] == nil){
		fprint(stderr, "can't open %s: %r\n", in);
		toterrors++;
		return;
	}
	doemit := emitcode != "" || emitstub || emittab != "" || emitsbl != "";
	if(!doemit){
		bout = bufio->create(out, Bufio->OWRITE, 8r666);
		if(bout == nil){
			fprint(stderr, "can't open %s: %r\n", out);
			toterrors++;
			bins[0].close();
			return;
		}
		if(dosym){
			bsym = bufio->create(dbg, Bufio->OWRITE, 8r666);
			if(bsym == nil)
				fprint(stderr, "can't open %s: %r\n", dbg);
		}
	}

	lexstart(in);

	popscopes();
	typestart();
	declstart();
	nfnexp = 0;

	parset = sys->millisec();
	yyparse(yyctxt);
	parset = sys->millisec() - parset;

	checkt = sys->millisec();
	entry := typecheck(!doemit);
	checkt = sys->millisec() - checkt;

	modcom(entry);

	fns = nil;
	nfns = 0;
	descriptors = nil;

	if(debug['T'])
		print("times: parse=%d type=%d: gen=%d write=%d symbols=%d\n",
			parset, checkt, gent, writet, symt);

	if(bout != nil)
		bout.close();
	if(bsym != nil)
		bsym.close();
	toterrors += errors;
	if(errors && bout != nil)
		sys->remove(out);
	if(errors && bsym != nil)
		sys->remove(dbg);
}

pwd(): string
{
	workdir := load Workdir Workdir->PATH;
	if(workdir == nil)
		cd := "/";
	else
		cd = workdir->init();
	# sys->print("pwd: %s\n", cd);
	return cd;
}

cleanname(s: string): string
{
	ls, path: list of string;

	if(s == nil)
		return nil;
	if(s[0] != '/' && s[0] != '\\')
		(nil, ls) = sys->tokenize(pwd(), "/\\");
	for( ; ls != nil; ls = tl ls)
		path = hd ls :: path;
	(nil, ls) = sys->tokenize(s, "/\\");
	for( ; ls != nil; ls = tl ls){
		n := hd ls;
		if(n == ".")
			;
		else if (n == ".."){
			if(path != nil)
				path = tl path;
		}
		else
			path = n :: path;
	}
	p := "";
	for( ; path != nil; path = tl path)
		p = "/" + hd path + p;
	if(p == nil)
		p = "/";
	# sys->print("cleanname: %s\n", p);
	return p;
}

srcpath(): string
{
	srcp := cleanname(infile);
	# sys->print("srcpath: %s\n", srcp);
	return srcp;
}
