%{
#include "limbo.h"
%}

%union
{
	struct{
		Src	src;
		union{
			Sym	*idval;
			Long	ival;
			Real	rval;
		}v;
	}tok;
	Decl	*ids;
	Node	*node;
	Type	*type;
	Typelist *types;
}

%type	<type>	type fnarg fnargret fnargretp adtk fixtype iditype dotiditype
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
		$$->src.start = $1->src.start;
		$$->src.stop = $5.stop;
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
		$1->src.stop = $6.stop;
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
		$1->src.stop = $7.stop;
		$$ = adtdecl($1, rotater($6));
		$$->ty->polys = $4;
		$$->ty->val = rotater($8);
	}
	| ids ':' Ladt polydec Lfor '{' tpolys '}' '{' fields '}'
	{
		$1->src.stop = $11.stop;
		$$ = adtdecl($1, rotater($10));
		$$->ty->polys = $4;
		$$->ty->val = rotater($7);
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
		Decl *d;

		for(d = $1; d != nil; d = d->next)
			d->cyc = 1;
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
		$1->right->right = $2;
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
		typeids($1, mktype(&$1->src.start, &$1->src.stop, Tadtpick, nil, nil));
	}
	| pfbody dfields ptags Llabs
	{
		$1->right->right = $2;
		$$ = mkn(Opickdecl, $1, mkn(Oseq, fielddecl(Dtag, $3), nil));
		typeids($3, mktype(&$3->src.start, &$3->src.stop, Tadtpick, nil, nil));
	}
	| pfbody error ptags Llabs
	{
		$$ = mkn(Opickdecl, nil, mkn(Oseq, fielddecl(Dtag, $3), nil));
		typeids($3, mktype(&$3->src.start, &$3->src.stop, Tadtpick, nil, nil));
	}
	;

ptags	: rptags
	{
		$$ = revids($1);
	}
	;

rptags	: Lid
	{
		$$ = mkids(&$<tok.src>1, $1, nil, nil);
	}
	| rptags Lor Lid
	{
		$$ = mkids(&$<tok.src>3, $3, nil, $1);
	}
	;

ids	: rids
	{
		$$ = revids($1);
	}
	;

rids	: Lid
	{
		$$ = mkids(&$<tok.src>1, $1, nil, nil);
	}
	| rids ',' Lid
	{
		$$ = mkids(&$<tok.src>3, $3, nil, $1);
	}
	;

fixtype	: Lfix '(' exp ',' exp ')'
	{
		$$ = mktype(&$1.start, &$6.stop, Tfix, nil, nil);
		$$->val = mkbin(Oseq, $3, $5);
	}
	|	Lfix '(' exp ')'
	{
		$$ = mktype(&$1.start, &$4.stop, Tfix, nil, nil);
		$$->val = $3;
	}
	;

types	: type
	{
		$$ = addtype($1, nil);
	}
	|	Lcyclic type
	{
		$$ = addtype($2, nil);
		$2->flags |= CYCLIC;
	}
	| types ',' type
	{
		$$ = addtype($3, $1);
	}
	| types ',' Lcyclic type
	{
		$$ = addtype($4, $1);
		$4->flags |= CYCLIC;
	}
	;

type	: Ltid
	{
		$$ = mkidtype(&$<tok.src>1, $1);
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
		$$ = mkarrowtype(&$1->src.start, &$<tok.src>3.stop, $1, $3);
	}
	| type Lmdot Lid '[' types ']'
	{
		$$ = mkarrowtype(&$1->src.start, &$<tok.src>3.stop, $1, $3);
		$$ = mkinsttype(&$1->src, $$, $5);
	}
	| Lref type
	{
		$$ = mktype(&$1.start, &$2->src.stop, Tref, $2, nil);
	}
	| Lchan Lof type
	{
		$$ = mktype(&$1.start, &$3->src.stop, Tchan, $3, nil);
	}
	| '(' tuplist ')'
	{
		if($2->next == nil)
			$$ = $2->ty;
		else
			$$ = mktype(&$1.start, &$3.stop, Ttuple, nil, revids($2));
	}
	| Larray Lof type
	{
		$$ = mktype(&$1.start, &$3->src.stop, Tarray, $3, nil);
	}
	| Llist Lof type
	{
		$$ = mktype(&$1.start, &$3->src.stop, Tlist, $3, nil);
	}
	| Lfn polydec fnargretp raises
	{
		$3->src.start = $1.start;
		$3->polys = $2;
		$3->u.eraises = $4;
		$$ = $3;
	}
	| fixtype
/*
	| Lexcept
	{
		$$ = mktype(&$1.start, &$1.stop, Texception, nil, nil);
		$$->cons = 1;
	}
	| Lexcept '(' tuplist ')'
	{
		$$ = mktype(&$1.start, &$4.stop, Texception, nil, revids($3));
		$$->cons = 1;
	}
*/
	;

iditype	: Lid
	{
		$$ = mkidtype(&$<tok.src>1, $1);
	}
	| Lid '[' types ']'
	{
		$$ = mkinsttype(&$<tok.src>1, mkidtype(&$<tok.src>1, $1), $3);
	}
	;

dotiditype	: type '.' Lid
	{
		$$ = mkdottype(&$1->src.start, &$<tok.src>3.stop, $1, $3);
	}
	| type '.' Lid '[' types ']'
	{
		$$ = mkdottype(&$1->src.start, &$<tok.src>3.stop, $1, $3);
		$$ = mkinsttype(&$1->src, $$, $5);
	}
	;

tuplist	: type
	{
		$$ = mkids(&$1->src, nil, $1, nil);
	}
	| tuplist ',' type
	{
		$$ = mkids(&$1->src, nil, $3, $1);
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
		$$ = mktype(&$1.start, &$3.stop, Tfn, tnone, $2);
	}
	| '(' '*' ')'
	{
		$$ = mktype(&$1.start, &$3.stop, Tfn, tnone, nil);
		$$->varargs = 1;
	}
	| '(' ftypes ',' '*' ')'
	{
		$$ = mktype(&$1.start, &$5.stop, Tfn, tnone, $2);
		$$->varargs = 1;
	}
	;

fnargret: fnarg %prec ':'
	{
		$$ = $1;
	}
	| fnarg ':' type
	{
		$1->tof = $3;
		$1->src.stop = $3->src.stop;
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
		$$->val = rotater($4);
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
		Decl *d;

		$$ = typeids($1, $3);
		for(d = $$; d != nil; d = d->next)
			d->implicit = 1;
	}
	| idterms ':' type
	{
		$$ = mkids(&$1->src, enter("junk", 0), $3, nil);
		$$->store = Darg;
		yyerror("illegal argument declaraion");
	}
	| idterms ':' adtk
	{
		$$ = mkids(&$1->src, enter("junk", 0), $3, nil);
		$$->store = Darg;
		yyerror("illegal argument declaraion");
	}
	;

nids	: nrids
	{
		$$ = revids($1);
	}
	;

nrids	: Lid
	{
		$$ = mkids(&$<tok.src>1, $1, nil, nil);
		$$->store = Darg;
	}
	| Lnil
	{
		$$ = mkids(&$1, nil, nil, nil);
		$$->store = Darg;
	}
	| nrids ',' Lid
	{
		$$ = mkids(&$<tok.src>3, $3, nil, $1);
		$$->store = Darg;
	}
	| nrids ',' Lnil
	{
		$$ = mkids(&$3, nil, nil, $1);
		$$->store = Darg;
	}
	;

/*
adttype	: Lid
	{
		$$ = mkidtype(&$<tok.src>1, $1);
	}
	| adttype '.' Lid
	{
		$$ = mkdottype(&$1->src.start, &$<tok.src>3.stop, $1, $3);
	}
	| adttype Lmdot Lid
	{
		$$ = mkarrowtype(&$1->src.start, &$<tok.src>3.stop, $1, $3);
	}
	| Lref adttype
	{
		$$ = mktype(&$1.start, &$2->src.stop, Tref, $2, nil);
	}
	;

adtk	:	Lself adttype
	{
		$$ = $2;
	}
	;
*/

adtk	: Lself iditype
	{
		$$ = $2;
	}
	| Lself Lref iditype
	{
		$$ = mktype(&$<tok.src>2.start, &$<tok.src>3.stop, Tref, $3, nil);
	}
	| Lself dotiditype
	{
		$$ = $2;
	}
	| Lself Lref dotiditype
	{
		$$ = mktype(&$<tok.src>2.start, &$<tok.src>3.stop, Tref, $3, nil);
	}
	;

fndef	: fnname fnargretp raises fbody
	{
		$$ = fndecl($1, $2, $4);
		nfns++;
		/* patch up polydecs */
		if($1->op == Odot){
			if($1->right->left != nil){
				$2->polys = $1->right->left->decl;
				$1->right->left = nil;
			}
			if($1->left->op == Oname && $1->left->left != nil){
				$$->decl = $1->left->left->decl;
				$1->left->left = nil;
			}
		}
		else{
			if($1->left != nil){
				$2->polys = $1->left->decl;
				$1->left = nil;
			}
		}
		$2->u.eraises = $3;
		$$->src = $1->src;
	}
	;

raises	: Lraises '(' idlist ')'
	{
		$$ = mkn(Otuple, rotater($3), nil);
		$$->src.start = $1.start;
		$$->src.stop = $4.stop;
	}
	|	Lraises idatom
	{
		$$ = mkn(Otuple, mkunary(Oseq, $2), nil);
		$$->src.start = $1.start;
		$$->src.stop = $2->src.stop;
	}
	|	/* empty */	%prec Lraises
	{
		$$ = nil;
	}
	;

fbody	: '{' stmts '}'
	{
		if($2 == nil){
			$2 = mkn(Onothing, nil, nil);
			$2->src.start = curline();
			$2->src.stop = $2->src.start;
		}
		$$ = rotater($2);
		$$->src.start = $1.start;
		$$->src.stop = $3.stop;
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
		$$ = mkname(&$<tok.src>1, $1);
		if($2 != nil){
			$$->left = mkn(Onothing, nil ,nil);
			$$->left->decl = $2;
		}
	}
	| fnname '.' Lid polydec
	{
		$$ = mkbin(Odot, $1, mkname(&$<tok.src>3, $3));
		if($4 != nil){
			$$->right->left = mkn(Onothing, nil ,nil);
			$$->right->left->decl = $4;
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
		$$->src.start = curline();
		$$->src.stop = $$->src.start;
	}
	| error '}'
	{
		$$ = mkn(Onothing, nil, nil);
		$$->src.start = curline();
		$$->src.stop = $$->src.start;
	}
	| error '{' stmts '}'
	{
		$$ = mkn(Onothing, nil, nil);
		$$->src.start = curline();
		$$->src.stop = $$->src.start;
	}
	| '{' stmts '}'
	{
		if($2 == nil){
			$2 = mkn(Onothing, nil, nil);
			$2->src.start = curline();
			$2->src.stop = $2->src.start;
		}
		$$ = mkscope(rotater($2));
	}
	| elists ':' type ';'
	{
		yyerror("illegal declaration");
		$$ = mkn(Onothing, nil, nil);
		$$->src.start = curline();
		$$->src.stop = $$->src.start;
	}
	| elists ':' type '=' exp';'
	{
		yyerror("illegal declaration");
		$$ = mkn(Onothing, nil, nil);
		$$->src.start = curline();
		$$->src.stop = $$->src.start;
	}
	| zexp ';'
	{
		$$ = $1;
	}
	| Lif '(' exp ')' stmt
	{
		$$ = mkn(Oif, $3, mkunary(Oseq, $5));
		$$->src.start = $1.start;
		$$->src.stop = $5->src.stop;
	}
	| Lif '(' exp ')' stmt Lelse stmt
	{
		$$ = mkn(Oif, $3, mkbin(Oseq, $5, $7));
		$$->src.start = $1.start;
		$$->src.stop = $7->src.stop;
	}
	| bclab Lfor '(' zexp ';' zexp ';' zexp ')' stmt
	{
		$$ = mkunary(Oseq, $10);
		if($8->op != Onothing)
			$$->right = $8;
		$$ = mkbin(Ofor, $6, $$);
		$$->decl = $1;
		if($4->op != Onothing)
			$$ = mkbin(Oseq, $4, $$);
	}
	| bclab Lwhile '(' zexp ')' stmt
	{
		$$ = mkn(Ofor, $4, mkunary(Oseq, $6));
		$$->src.start = $2.start;
		$$->src.stop = $6->src.stop;
		$$->decl = $1;
	}
	| bclab Ldo stmt Lwhile '(' zexp ')' ';'
	{
		$$ = mkn(Odo, $6, $3);
		$$->src.start = $2.start;
		$$->src.stop = $7.stop;
		$$->decl = $1;
	}
	| Lbreak bctarg ';'
	{
		$$ = mkn(Obreak, nil, nil);
		$$->decl = $2;
		$$->src = $1;
	}
	| Lcont bctarg ';'
	{
		$$ = mkn(Ocont, nil, nil);
		$$->decl = $2;
		$$->src = $1;
	}
	| Lreturn zexp ';'
	{
		$$ = mkn(Oret, $2, nil);
		$$->src = $1;
		if($2->op == Onothing)
			$$->left = nil;
		else
			$$->src.stop = $2->src.stop;
	}
	| Lspawn exp ';'
	{
		$$ = mkn(Ospawn, $2, nil);
		$$->src.start = $1.start;
		$$->src.stop = $2->src.stop;
	}
	| Lraise zexp ';'
	{
		$$ = mkn(Oraise, $2, nil);
		$$->src.start = $1.start;
		$$->src.stop = $2->src.stop;
	}
	| bclab Lcase exp '{' cqstmts '}'
	{
		$$ = mkn(Ocase, $3, caselist($5, nil));
		$$->src = $3->src;
		$$->decl = $1;
	}
	| bclab Lalt '{' qstmts '}'
	{
		$$ = mkn(Oalt, caselist($4, nil), nil);
		$$->src = $2;
		$$->decl = $1;
	}
	| bclab Lpick Lid Ldeclas exp '{' pstmts '}'
	{
		$$ = mkn(Opick, mkbin(Odas, mkname(&$<tok.src>3, $3), $5), caselist($7, nil));
		$$->src.start = $<tok.src>3.start;
		$$->src.stop = $5->src.stop;
		$$->decl = $1;
	}
	| Lexit ';'
	{
		$$ = mkn(Oexit, nil, nil);
		$$->src = $1;
	}
	| '{' stmts '}' Lexcept idexc '{' eqstmts '}'
	{
		if($2 == nil){
			$2 = mkn(Onothing, nil, nil);
			$2->src.start = curline();
			$2->src.stop = curline();
		}
		$2 = mkscope(rotater($2));
		$$ = mkbin(Oexstmt, $2, mkn(Oexcept, $5, caselist($7, nil)));
	}
/*
	| stmt Lexcept idexc '{' eqstmts '}'
	{
		$$ = mkbin(Oexstmt, $1, mkn(Oexcept, $3, caselist($5, nil)));
	}
*/
	;

bclab	:
	{
		$$ = nil;
	}
	| ids ':'
	{
		if($1->next != nil)
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
		$$ = mkids(&$<tok.src>1, $1, nil, nil);
	}
	;

qstmts	: qbodies stmts
	{
		$1->left->right->right = $2;
		$$ = $1;
	}
	;

qbodies	: qual Llabs
	{
		$$ = mkunary(Oseq, mkscope(mkunary(Olabel, rotater($1))));
	}
	| qbodies stmts qual Llabs
	{
		$1->left->right->right = $2;
		$$ = mkbin(Oseq, mkscope(mkunary(Olabel, rotater($3))), $1);
	}
	;

cqstmts	: cqbodies stmts
	{
		$1->left->right = mkscope($2);
		$$ = $1;
	}
	;

cqbodies	: qual Llabs
	{
		$$ = mkunary(Oseq, mkunary(Olabel, rotater($1)));
	}
	| cqbodies stmts qual Llabs
	{
		$1->left->right = mkscope($2);
		$$ = mkbin(Oseq, mkunary(Olabel, rotater($3)), $1);
	}
	;

eqstmts	: eqbodies stmts
	{
		$1->left->right = mkscope($2);
		$$ = $1;
	}
	;

eqbodies	: qual Llabs
	{
		$$ = mkunary(Oseq, mkunary(Olabel, rotater($1)));
	}
	| eqbodies stmts qual Llabs
	{
		$1->left->right = mkscope($2);
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
		$$->src = $1;
	}
	| qual Lor qual
	{
		$$ = mkbin(Oseq, $1, $3);
	}
	| error
	{
		$$ = mkn(Onothing, nil, nil);
		$$->src.start = curline();
		$$->src.stop = $$->src.start;
	}
	;

pstmts	: pbodies stmts
	{
		$1->left->right = mkscope($2);
		$$ = $1;
	}
	;

pbodies	: pqual Llabs
	{
		$$ = mkunary(Oseq, mkunary(Olabel, rotater($1)));
	}
	| pbodies stmts pqual Llabs
	{
		$1->left->right = mkscope($2);
		$$ = mkbin(Oseq, mkunary(Olabel, rotater($3)), $1);
	}
	;

pqual	: Lid
	{
		$$ = mkname(&$<tok>1.src, $1);
	}
	| '*'
	{
		$$ = mkn(Owild, nil, nil);
		$$->src = $1;
	}
	| pqual Lor pqual
	{
		$$ = mkbin(Oseq, $1, $3);
	}
	| error
	{
		$$ = mkn(Onothing, nil, nil);
		$$->src.start = curline();
		$$->src.stop = $$->src.start;
	}
	;

zexp	:
	{
		$$ = mkn(Onothing, nil, nil);
		$$->src.start = curline();
		$$->src.stop = $$->src.start;
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
	| exp Ldeclas exp
	{
		$$ = mkbin(Odas, $1, $3);
	}
	| Lload Lid exp %prec Lload
	{
		$$ = mkn(Oload, $3, nil);
		$$->src.start = $<tok.src.start>1;
		$$->src.stop = $3->src.stop;
		$$->ty = mkidtype(&$<tok.src>2, $2);
	}
	| exp Lexp exp
	{
		$$ = mkbin(Oexp, $1, $3);
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
		$2->src.start = $1.start;
		$$ = $2;
	}
	| '-' monexp
	{
		$$ = mkunary(Oneg, $2);
		$$->src.start = $1.start;
	}
	| '!' monexp
	{
		$$ = mkunary(Onot, $2);
		$$->src.start = $1.start;
	}
	| '~' monexp
	{
		$$ = mkunary(Ocomp, $2);
		$$->src.start = $1.start;
	}
	| '*' monexp
	{
		$$ = mkunary(Oind, $2);
		$$->src.start = $1.start;
	}
	| Linc monexp
	{
		$$ = mkunary(Opreinc, $2);
		$$->src.start = $1.start;
	}
	| Ldec monexp
	{
		$$ = mkunary(Opredec, $2);
		$$->src.start = $1.start;
	}
	| Lcomm monexp
	{
		$$ = mkunary(Orcv, $2);
		$$->src.start = $1.start;
	}
	| Lhd monexp
	{
		$$ = mkunary(Ohd, $2);
		$$->src.start = $1.start;
	}
	| Ltl monexp
	{
		$$ = mkunary(Otl, $2);
		$$->src.start = $1.start;
	}
	| Llen monexp
	{
		$$ = mkunary(Olen, $2);
		$$->src.start = $1.start;
	}
	| Lref monexp
	{
		$$ = mkunary(Oref, $2);
		$$->src.start = $1.start;
	}
	| Ltagof monexp
	{
		$$ = mkunary(Otagof, $2);
		$$->src.start = $1.start;
	}
	| Larray '[' exp ']' Lof type
	{
		$$ = mkn(Oarray, $3, nil);
		$$->ty = mktype(&$1.start, &$6->src.stop, Tarray, $6, nil);
		$$->src = $$->ty->src;
	}
	| Larray '[' exp ']' Lof '{' initlist '}'
	{
		$$ = mkn(Oarray, $3, $7);
		$$->src.start = $1.start;
		$$->src.stop = $8.stop;
	}
	| Larray '[' ']' Lof '{' initlist '}'
	{
		$$ = mkn(Onothing, nil, nil);
		$$->src.start = $2.start;
		$$->src.stop = $3.stop;
		$$ = mkn(Oarray, $$, $6);
		$$->src.start = $1.start;
		$$->src.stop = $7.stop;
	}
	| Llist Lof '{' celist '}'
	{
		$$ = etolist($4);
		$$->src.start = $1.start;
		$$->src.stop = $5.stop;
	}
	| Lchan Lof type
	{
		$$ = mkn(Ochan, nil, nil);
		$$->ty = mktype(&$1.start, &$3->src.stop, Tchan, $3, nil);
		$$->src = $$->ty->src;
	}
	| Lchan '[' exp ']' Lof type
	{
		$$ = mkn(Ochan, $3, nil);
		$$->ty = mktype(&$1.start, &$6->src.stop, Tchan, $6, nil);
		$$->src = $$->ty->src;
	}
	| Larray Lof Ltid monexp
	{
		$$ = mkunary(Ocast, $4);
		$$->ty = mktype(&$1.start, &$4->src.stop, Tarray, mkidtype(&$<tok.src>3, $3), nil);
		$$->src = $$->ty->src;
	}
	| Ltid monexp
	{
		$$ = mkunary(Ocast, $2);
		$$->src.start = $<tok.src>1.start;
		$$->ty = mkidtype(&$$->src, $1);
	}
	| Lid monexp
	{
		$$ = mkunary(Ocast, $2);
		$$->src.start = $<tok.src>1.start;
		$$->ty = mkidtype(&$$->src, $1);
	}
	| fixtype monexp
	{
		$$ = mkunary(Ocast, $2);
		$$->src.start = $<tok.src>1.start;
		$$->ty = $1;
	}
	;

term	: idatom
	| term '(' zelist ')'
	{
		$$ = mkn(Ocall, $1, $3);
		$$->src.start = $1->src.start;
		$$->src.stop = $4.stop;
	}
	| '(' elist ')'
	{
		$$ = $2;
		if($2->op == Oseq)
			$$ = mkn(Otuple, rotater($2), nil);
		else
			$$->flags |= PARENS;
		$$->src.start = $1.start;
		$$->src.stop = $3.stop;
	}
	| term '.' Lid
	{
		$$ = mkbin(Odot, $1, mkname(&$<tok.src>3, $3));
	}
	| term Lmdot term
	{
		$$ = mkbin(Omdot, $1, $3);
	}
	| term '[' export ']'
	{
		$$ = mkbin(Oindex, $1, $3);
		$$->src.stop = $4.stop;
	}
	| term '[' zexp ':' zexp ']'
	{
		if($3->op == Onothing)
			$3->src = $4;
		if($5->op == Onothing)
			$5->src = $4;
		$$ = mkbin(Oslice, $1, mkbin(Oseq, $3, $5));
		$$->src.stop = $6.stop;
	}
	| term Linc
	{
		$$ = mkunary(Oinc, $1);
		$$->src.stop = $2.stop;
	}
	| term Ldec
	{
		$$ = mkunary(Odec, $1);
		$$->src.stop = $2.stop;
	}
	| Lsconst
	{
		$$ = mksconst(&$<tok.src>1, $1);
	}
	| Lconst
	{
		$$ = mkconst(&$<tok.src>1, $1);
		if($1 > 0x7fffffff || $1 < -0x7fffffff)
			$$->ty = tbig;
		$$ = $$;
	}
	| Lrconst
	{
		$$ = mkrconst(&$<tok.src>1, $1);
	}
	| term '[' exportlist ',' export ']'
	{
		$$ = mkbin(Oindex, $1, rotater(mkbin(Oseq, $3, $5)));
		$$->src.stop = $6.stop;
	}
	;

idatom	: Lid
	{
		$$ = mkname(&$<tok.src>1, $1);
	}
	| Lnil
	{
		$$ = mknil(&$<tok.src>1);
	}
	;

idterm	: '(' idlist ')'
	{
		$$ = mkn(Otuple, rotater($2), nil);
		$$->src.start = $1.start;
		$$->src.stop = $3.stop;
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

texp	:	Ltid
	{
		$$ = mkn(Otype, nil, nil);
		$$->ty = mkidtype(&$<tok.src>1, $1);
		$$->src = $$->ty->src;
	}
	| Larray Lof type
	{
		$$ = mkn(Otype, nil, nil);
		$$->ty = mktype(&$1.start, &$3->src.stop, Tarray, $3, nil);
		$$->src = $$->ty->src;
	}
	| Llist Lof type
	{
		$$ = mkn(Otype, nil, nil);
		$$->ty = mktype(&$1.start, &$3->src.stop, Tlist, $3, nil);
		$$->src = $$->ty->src;
	}
	| Lcyclic type
	{
		$$ = mkn(Otype, nil ,nil);
		$$->ty = $2;
		$$->ty->flags |= CYCLIC;
		$$->src = $$->ty->src;
	}
	;

idexc	: Lid
	{
		$$ = mkname(&$<tok.src>1, $1);
	}
	|	/* empty */
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
		$$->src = $1->src;
	}
	| qual Llabs exp
	{
		$$ = mkbin(Oelem, rotater($1), $3);
	}
	;

/*
tpoly	: ids Llabs '{' dfields '}'
	{
		$$ = typedecl($1, mktype(&$1->src.start, &$5.stop, Tpoly, nil, nil));
		$$->left = rotater($4);
	}
	;

tpolys	: tpoly
	{
		$$ = $1;
	}
	| tpolys tpoly
	{
		$$ = mkbin(Oseq, $1, $2);
	}
	;
*/

tpolys	: tpoly dfields
	{
		if($1->op == Oseq)
			$1->right->left = rotater($2);
		else
			$1->left = rotater($2);
		$$ = $1;
	}
	;

tpoly	: ids Llabs
	{
		$$ = typedecl($1, mktype(&$1->src.start, &$2.stop, Tpoly, nil, nil));
	}
	| tpoly dfields ids Llabs
	{
		if($1->op == Oseq)
			$1->right->left = rotater($2);
		else
			$1->left = rotater($2);
		$$ = mkbin(Oseq, $1, typedecl($3, mktype(&$3->src.start, &$4.stop, Tpoly, nil, nil)));
	}
	;

%%

static	char	*mkfileext(char*, char*, char*);
static	void	usage(void);

static	int	dosym;
static	int	toterrors;
static	ulong	canonnanbits[] = { 0x7fffffff, 0xffffffff};
static	char*	infile;

#define SLASHMOD	"/module"

static char*
getroot(void)
{
	int n;
	char *e, *l, *s;

	if((e = getenv("EMU")) != nil){
		for(s = e; *e != '\0'; e++){
			if(*e == '-' && *(e+1) == 'r' && (e == s || *(e-1) == ' ' || *(e-1) == '\t')){
				e += 2;
				l = strchr(e, ' ');
				if(l != nil)
					*l = '\0';
				if((n = strlen(e)) > 0){
					s = malloc(n+1);
					strcpy(s, e);
					return s;
				}
			}
		}
	}
	if((e = getenv("ROOT")) != nil)
		return strdup(e);
	return nil;
}

void
main(int argc, char *argv[])
{
	char *s, *ofile, *ext, *root;
	int i;

	FPinit();
	FPcontrol(0, INVAL|ZDIV|OVFL|UNFL|INEX);
	canonnan = canontod(canonnanbits);

	fmtinstall('D', dotconv);
	fmtinstall('I', instconv);
	fmtinstall('K', declconv);
	fmtinstall('k', storeconv);
	fmtinstall('L', lineconv);
	fmtinstall('M', mapconv);
	fmtinstall('n', nodeconv);		/* exp structure */
	fmtinstall('O', opconv);
	fmtinstall('g', gfltconv);
	fmtinstall('Q', etconv);		/* src expression with type */
	fmtinstall('R', ctypeconv);		/* c equivalent type */
	fmtinstall('P', ctypeconv);		/* c equivalent type - pointer type */
	fmtinstall('T', typeconv);		/* source style types */
	fmtinstall('t', stypeconv);		/* structurally descriptive type */
	fmtinstall('U', srcconv);
	fmtinstall('v', expconv);		/* src expression */
	fmtinstall('V', expconv);		/* src expression in '' */
	lexinit();
	typeinit();
	optabinit();

	gendis = 1;
	asmsym = 0;
	maxerr = 20;
	ofile = nil;
	ext = nil;
	ARGBEGIN{
	case 'D':
		/*
		 * debug flags:
		 *
		 * a	alt compilation
		 * A	array constructor compilation
		 * b	boolean and branch compilation
		 * c	case compilation
		 * d	function declaration
		 * D	descriptor generation
		 * e	expression compilation
		 * E	addressable expression compilation
		 * f	print arguments for compiled functions
		 * F	constant folding
		 * g	print out globals
		 * m	module declaration and type checking
		 * n	nil references
		 * s	print sizes of output file sections
		 * S	type signing
		 * t	type checking function bodies
		 * T	timing
		 * v	global var and constant compilation
		 * x	adt verification
		 * Y	tuple compilation
		 * z Z	bug fixes
		 */
		s = ARGF();
		while(s && *s)
			debug[*s++] = 1;
		break;
	case 'I':
		s = ARGF();
		if(s == nil)
			usage();
		addinclude(s);
		break;
	case 'G':
		asmsym = 1;
		break;
	case 'S':
		gendis = 0;
		break;
	case 'a':
		emitstub = 1;
		break;
	case 'A':
		emitstub = emitdyn = 1;
		break;
	case 'c':
		mustcompile = 1;
		break;
	case 'C':
		dontcompile = 1;
		break;
	case 'e':
		maxerr = 1000;
		break;
	case 'f':
		isfatal = 1;
		break;
	case 'F':
		newfnptr = 1;
		break;
	case 'g':
		dosym = 1;
		break;
	case 'i':
		dontinline = 1;
		break;
	case 'o':
		ofile = ARGF();
		break;
	case 'O':
		optims = 1;
		break;
	case 's':
		s = ARGF();
		if(s != nil)
			fixss = atoi(s);
		break;
	case 't':
		emittab = ARGF();
		if(emittab == nil)
			usage();
		break;
	case 'T':
		emitcode = ARGF();
		if(emitcode == nil)
			usage();
		break;
	case 'd':
		emitcode = ARGF();
		if(emitcode == nil)
			usage();
		emitdyn = 1;
		break;
	case 'w':
		superwarn = dowarn;
		dowarn = 1;
		break;
	case 'x':
		ext = ARGF();
		break;
	case 'X':
		signdump = ARGF();
		break;
	case 'z':
		arrayz = 1;
		break;
	default:
		usage();
		break;
	}ARGEND

	if((root = getroot()) != nil){
		char *r;

		r = malloc(strlen(root)+strlen(SLASHMOD)+1);
		strcpy(r, root);
		strcat(r, SLASHMOD);
		addinclude(r);
		free(root);
	}
	else
		addinclude(INCPATH);

	if(argc == 0){
		usage();
	}else if(ofile != nil){
		if(argc != 1)
			usage();
		translate(argv[0], ofile, mkfileext(ofile, ".dis", ".sbl"));
	}else{
		if(ext == nil){
			ext = ".s";
			if(gendis)
				ext = ".dis";
		}
		for(i = 0; i < argc; i++){
			s = strrchr(argv[i], '/');
			if(s == nil)
				s = argv[i];
			else
				s++;
			if(argc > 1)
				print("%s:\n", argv[i]);
			ofile = mkfileext(s, ".b", ext);
			translate(argv[i], ofile, mkfileext(ofile, ext, ".sbl"));
		}
	}
	if(toterrors)
		exits("errors");
	exits(0);
}

static void
usage(void)
{
	fprint(2, "usage: limbo [-CGSacgwe] [-I incdir] [-o outfile] [-{T|t|d} module] [-D debug] file ...\n");
	exits("usage");
}

static char*
mkfileext(char *file, char *oldext, char *ext)
{
	char *ofile;
	int n, n2;

	n = strlen(file);
	n2 = strlen(oldext);
	if(n >= n2 && strcmp(&file[n-n2], oldext) == 0)
		n -= n2;
	ofile = malloc(n + strlen(ext) + 1);
	memmove(ofile, file, n);
	strcpy(ofile+n, ext);
	return ofile;
}

void
translate(char *in, char *out, char *dbg)
{
	Decl *entry;
	int doemit;

	infile = in;
	outfile = out;
	symfile = dbg;
	errors = 0;
	bins[0] = Bopen(in, OREAD);
	if(bins[0] == nil){
		fprint(2, "can't open %s: %r\n", in);
		toterrors++;
		return;
	}
	doemit = emitstub || emittab || emitcode;
	if(!doemit){
		bout = Bopen(out, OWRITE);
		if(bout == nil){
			fprint(2, "can't open %s: %r\n", out);
			toterrors++;
			Bterm(bins[0]);
			return;
		}
		if(dosym){
			bsym = Bopen(dbg, OWRITE);
			if(bsym == nil)
				fprint(2, "can't open %s: %r\n", dbg);
		}
	}

	lexstart(in);

	popscopes();
	typestart();
	declstart();

	yyparse();

	entry = typecheck(!doemit);

	modcom(entry);

	fns = nil;
	nfns = 0;
	descriptors = nil;

	if(bout != nil)
		Bterm(bout);
	if(bsym != nil)
		Bterm(bsym);
	toterrors += errors;
	if(errors && bout != nil)
		remove(out);
	if(errors && bsym != nil)
		remove(dbg);
}

void
trapFPE(unsigned exception[5], int value[2])
{
	/* can't happen; it's just here to keep FPinit happy. */
	USED(exception);
	USED(value);
}

static char *
win2inf(char *s)
{
	int nt = 0;
	char *t;

	if(strlen(s) > 1 && s[1] == ':'){
		s[1] = '/';
		s++;
		nt = 1;
	}
	for(t = s; *t != '\0'; t++){
		if(*t == '\\')
			*t = '/';
		if(nt)
			*t = tolower(*t);
	}
	return s;
}

/*
static char *
pwd(void)
{
	int ok, qid, l1, l2;
	Dir d;
	char *p;
	char hd[64], buf[128], path[256];
	static char *cd;

	if(cd != nil)
		return cd;
	*hd = *path = '\0';
	qid = -1;
	strcpy(buf, ".");
	for(;;){
		ok = dirstat(buf, &d);
		if(ok < 0)
			return "";
		if(d.qid.path == qid && strcmp(d.name, hd) == 0)
			break;
		l1 = strlen(d.name);
		l2 = strlen(path);
		memmove(path+l1+1, path, l2+1);
		memcpy(path+1, d.name, l1);
		path[0] = '/';
		strcpy(hd, d.name);
		qid = d.qid.path;
		strcat(buf, "/..");
	}
	p = win2inf(path);
	while(*p == '/' && p[1] == '/')
		p++;
	cd = malloc(strlen(p)+1);
	strcpy(cd, p);
	return cd;
}
*/

static char *
cleann(char *s)
{
	char *p, *r, *t;
	char buf[256];

	r = t = malloc(strlen(s)+1);
	strcpy(t, s);
	t = win2inf(t);
	if(*t != '/'){
		/* p = pwd(); */
		p = win2inf(getwd(buf, sizeof(buf)));
		s = malloc(strlen(p)+strlen(t)+2);
		strcpy(s, p);
		strcat(s, "/");
		strcat(s, t);
	}
	else{
		s = malloc(strlen(t)+1);
		strcpy(s, t);
	}
	free(r);
	/* print("cleann: %s\n", p); */
	return cleanname(s);
}

char *
srcpath(char *name, int nlen)
{
	int l1, l2;
	char *r, *srcp, *t;

	srcp = cleann(infile);
	r = getroot();
	if(r == nil){
		l1 = strlen(INCPATH);
		r = malloc(l1+1);
		strcpy(r, INCPATH);
		if(l1 >= strlen(SLASHMOD) && strcmp(r+l1-strlen(SLASHMOD), SLASHMOD) == 0)
			r[l1-strlen(SLASHMOD)] = '\0';
	}
	t = cleann(r);
	free(r);
	r = t;
	/* srcp relative to r */
	l1 = strlen(srcp);
	l2 = strlen(r);
	if(l1 >= l2 && strncmp(srcp, r, l2) == 0){
		/* nothing to do */
	}else
		l2 = 0;
	strncpy(name, srcp+l2, nlen);
	name[nlen-1] = '\0';
	free(r);
	free(srcp);
	/* print("srcpath: %s\n", name); */
	return name;
}
