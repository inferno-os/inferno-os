%{
#include "cc.h"
%}
%union	{
	Node*	node;
	Sym*	sym;
	Type*	type;
	struct
	{
		Type*	t;
		char	c;
	} tycl;
	struct
	{
		Type*	t1;
		Type*	t2;
	} tyty;
	struct
	{
		char*	s;
		long	l;
	} sval;
	long	lval;
	double	dval;
	vlong	vval;
}
%type	<sym>	ltag
%type	<lval>	gctname cname gname tname
%type	<lval>	gctnlist zgnlist tnlist
%type	<type>	tlist etlist sbody complex
%type	<tycl>	types etypes
%type	<node>	zarglist arglist zcexpr
%type	<node>	name block stmnt cexpr expr xuexpr pexpr
%type	<node>	zelist elist adecl slist uexpr string lstring sstring slstring
%type	<node>	xdecor xdecor2 labels label ulstmnt
%type	<node>	adlist edecor tag qual qlist
%type	<node>	abdecor abdecor1 abdecor2 abdecor3
%type	<node>	zexpr lexpr init ilist

%left	';'
%left	','
%right	'=' LPE LME LMLE LDVE LMDE LRSHE LLSHE LANDE LXORE LORE
%right	'?' ':'
%left	LOROR
%left	LANDAND
%left	'|'
%left	'^'
%left	'&'
%left	LEQ LNE
%left	'<' '>' LLE LGE
%left	LLSH LRSH
%left	'+' '-'
%left	'*' '/' '%'
%right	LMM LPP LMG '.' '[' '('

%token	<sym>	LNAME LCTYPE LSTYPE
%token	<dval>	LFCONST LDCONST
%token	<vval>	LCHARACTER LCONST LLCONST LUCONST LULCONST LVLCONST LUVLCONST
%token	<sval>	LSTRING LLSTRING
%token		LAUTO LBREAK LCASE LCHAR LCONTINUE LDEFAULT LDO
%token		LDOUBLE LELSE LEXTERN LFLOAT LFOR LGOTO
%token	LIF LINT LLONG LREGISTER LRETURN LSHORT LSIZEOF LUSED
%token	LSTATIC LSTRUCT LSWITCH LTYPEDEF LUNION LUNSIGNED LWHILE
%token	LVOID LENUM LSIGNED LCONSTNT LVOLATILE LSET LSIGNOF LVLONG
%%
prog:
|	prog xdecl

/*
 * external declarator
 */
xdecl:
	zctlist ';'
	{
		dodecl(xdecl, lastclass, lasttype, Z, 1);
	}
|	zctlist xdlist ';'
|	zctlist xdecor
	{
		lastdcl = T;
		dodecl(xdecl, lastclass, lasttype, $2, 0);
		if(lastdcl == T || lastdcl->etype != TFUNC) {
			diag($2, "not a function");
			lastdcl = types[TFUNC];
		}
		thisfn = lastdcl;
		markdcl();
		firstdcl = dclstack;
		argmark($2, 0);
	}
	pdecl
	{
		argmark($2, 1);
	}
	block
	{
		$6->blk = 0;
		codgen($6, $2, lineno);
		revertdcl();
	}

xdlist:
	xdecor
	{
		dodecl(xdecl, lastclass, lasttype, $1, 1);
	}
|	xdecor
	{
		$1 = dodecl(xdecl, lastclass, lasttype, $1, 0);
	}
	'=' init
	{
		$4 = doinit($1->sym, $1->type, 0L, $4);
		$4 = new(ODAS, $1, $4);
		$4->type = $1->type;
		$4->lineno = $1->lineno;
		vtgen($4);
	}
|	xdlist ',' xdlist

xdecor:
	xdecor2
|	'*' zgnlist xdecor
	{
		$$ = new(OIND, $3, Z);
		$$->garb = simpleg($2);
	}

xdecor2:
	tag
|	'(' xdecor ')'
	{
		$$ = $2;
	}
|	xdecor2 '(' zarglist ')'
	{
		$$ = new(OFUNC, $1, $3);
		/* outfun($$); */
	}
|	xdecor2 '[' zexpr ']'
	{
		$$ = new(OARRAY, $1, $3);
	}

/*
 * automatic declarator
 */
adecl:
	{
		$$ = Z;
	}
|	adecl ctlist ';'
	{
		$$ = dodecl(adecl, lastclass, lasttype, Z, 1);
		if($1 != Z)
			if($$ != Z)
				$$ = new(OLIST, $1, $$);
			else
				$$ = $1;
	}
|	adecl ctlist adlist ';'
	{
		$$ = $1;
		if($3 != Z) {
			$$ = $3;
			if($1 != Z)
				$$ = new(OLIST, $1, $3);
		}
	}

adlist:
	xdecor
	{
		$$ = dodecl(adecl, lastclass, lasttype, $1, 1);
		if($$->sym->class == CSTATIC)
			$$ = Z;
	}
|	xdecor
	{
		$1 = dodecl(adecl, lastclass, lasttype, $1, 0);
	}
	'=' init
	{
		/* long w; */

		/* w = $1->sym->type->width; */
		$$ = doinit($1->sym, $1->type, 0L, $4);
		/* $$ = contig($1->sym, $$, w); */
		$$ = new(ODAS, $1, $$);
		$$->type = $1->type;
		$$->lineno = $1->lineno;
		vtgen($$);
		if($1->sym->class == CSTATIC)
			$$ = Z;
	}
|	adlist ',' adlist
	{
		$$ = $1;
		if($3 != Z) {
			$$ = $3;
			if($1 != Z)
				$$ = new(OLIST, $1, $3);
		}
	}

/*
 * parameter declarator
 */
pdecl:
|	pdecl ctlist pdlist ';'

pdlist:
	xdecor
	{
		dodecl(pdecl, lastclass, lasttype, $1, 1);
	}
|	pdlist ',' pdlist

/*
 * structure element declarator
 */
edecl:
	etlist
	{
		lasttype = $1;
	}
	zedlist ';'
|	edecl etlist
	{
		lasttype = $2;
	}
	zedlist ';'

zedlist:					/* extension */
	{
		lastfield = 0;
		edecl(CXXX, lasttype, S);
	}
|	edlist

edlist:
	edecor
	{
		dodecl(edecl, CXXX, lasttype, $1, 1);
	}
|	edlist ',' edlist

edecor:
	xdecor
	{
		lastbit = 0;
		firstbit = 1;
	}
|	tag ':' lexpr
	{
		$$ = new(OBIT, $1, $3);
	}
|	':' lexpr
	{
		$$ = new(OBIT, Z, $2);
	}

/*
 * abstract declarator
 */
abdecor:
	{
		$$ = (Z);
	}
|	abdecor1

abdecor1:
	'*' zgnlist
	{
		$$ = new(OIND, (Z), Z);
		$$->garb = simpleg($2);
	}
|	'*' zgnlist abdecor1
	{
		$$ = new(OIND, $3, Z);
		$$->garb = simpleg($2);
	}
|	abdecor2

abdecor2:
	abdecor3
|	abdecor2 '(' zarglist ')'
	{
		$$ = new(OFUNC, $1, $3);
	}
|	abdecor2 '[' zexpr ']'
	{
		$$ = new(OARRAY, $1, $3);
	}

abdecor3:
	'(' ')'
	{
		$$ = new(OFUNC, (Z), Z);
	}
|	'[' zexpr ']'
	{
		$$ = new(OARRAY, (Z), $2);
	}
|	'(' abdecor1 ')'
	{
		$$ = $2;
	}

init:
	expr
|	'{' ilist '}'
	{
		$$ = new(OINIT, invert($2), Z);
	}

qual:
	'[' lexpr ']'
	{
		$$ = new(OARRAY, $2, Z);
	}
|	'.' ltag
	{
		$$ = new(OELEM, Z, Z);
		$$->sym = $2;
	}
|	qual '='

qlist:
	init ','
|	qlist init ','
	{
		$$ = new(OLIST, $1, $2);
	}
|	qual
|	qlist qual
	{
		$$ = new(OLIST, $1, $2);
	}

ilist:
	qlist
|	init
|	qlist init
	{
		$$ = new(OLIST, $1, $2);
	}

zarglist:
	{
		$$ = Z;
	}
|	arglist
	{
		$$ = invert($1);
	}


arglist:
	name
|	tlist abdecor
	{
		$$ = new(OPROTO, $2, Z);
		$$->type = $1;
	}
|	tlist xdecor
	{
		$$ = new(OPROTO, $2, Z);
		$$->type = $1;
	}
|	'.' '.' '.'
	{
		$$ = new(ODOTDOT, Z, Z);
	}
|	arglist ',' arglist
	{
		$$ = new(OLIST, $1, $3);
	}

block:
	'{' adecl slist '}'
	{
		$$ = invert($3);
		if($2 != Z)
			$$ = new(OLIST, $2, $$);
		if($$ == Z)
			$$ = new(ONUL, Z, Z);
		$$->blk = 1;
	}

slist:
	{
		$$ = Z;
	}
|	slist stmnt
	{
		if($1 == Z)
			$$ = $2;
		else
			$$ = new(OLIST, $1, $2);
	}

labels:
	label
|	labels label
	{
		$$ = new(OLIST, $1, $2);
	}

label:
	LCASE expr ':'
	{
		$$ = new(OCASE, $2, Z);
		$$->lineno = $2->lineno;
	}
|	LDEFAULT ':'
	{
		$$ = new(OCASE, Z, Z);
	}
|	LNAME ':'
	{
		$$ = new(OLABEL, dcllabel($1, 1), Z);
		$1->lineno = lineno;
	}

stmnt:
	error ';'
	{
		$$ = Z;
	}
|	ulstmnt
|	labels ulstmnt
	{
		$$ = new(OLIST, $1, $2);
	}

ulstmnt:
	zcexpr ';'
	{
		if($$ == Z)
			$$ = new(ONUL, Z, Z);
		$$->kind = KEXP;
	}
|	{
		markdcl();
	}
	block
	{
		revertdcl();
		$$ = $2;
	}
|	LIF '(' cexpr ')' stmnt
	{
		$$ = new(OIF, $3, new(OLIST, $5, Z));
		$$->lineno = $3->lineno;
		$5->blk = 0;
	}
|	LIF '(' cexpr ')' stmnt LELSE stmnt
	{
		$$ = new(OIF, $3, new(OLIST, $5, $7));
		$$->lineno = $3->lineno;
		$5->blk = $7->blk = 0;
	}
|	LFOR '(' zcexpr ';' zcexpr ';' zcexpr ')' stmnt
	{
		$$ = new(OFOR, new(OLIST, $5, new(OLIST, $3, $7)), $9);
		if($3 != Z)
			$$->lineno = $3->lineno;
		else if($5 != Z)
			$$->lineno = $5->lineno;
		else if($7 != Z)
			$$->lineno = $7->lineno;
		else
			$$->lineno = line($9);
		$9->blk = 0;
	}
|	LWHILE '(' cexpr ')' stmnt
	{
		$$ = new(OWHILE, $3, $5);
		$$->lineno = $3->lineno;
		$5->blk = 0;
	}
|	LDO stmnt LWHILE '(' cexpr ')' ';'
	{
		$$ = new(ODWHILE, $5, $2);
		$$->lineno = line($2);
		$2->blk = 0;
	}
|	LRETURN zcexpr ';'
	{
		$$ = new(ORETURN, $2, Z);
		$$->type = thisfn->link;
		if($2 != Z)
			$$->lineno = $2->lineno;
	}
|	LSWITCH '(' cexpr ')' stmnt
	{
		$$ = new(OSWITCH, $3, $5);
		$$->lineno = $3->lineno;
		$5->blk = 0;
	}
|	LBREAK ';'
	{
		$$ = new(OBREAK, Z, Z);
	}
|	LCONTINUE ';'
	{
		$$ = new(OCONTINUE, Z, Z);
	}
|	LGOTO LNAME ';'
	{
		$$ = new(OGOTO, dcllabel($2, 0), Z);
		$2->lineno = lineno;
	}
|	LUSED '(' zelist ')' ';'
	{
		$$ = new(OUSED, $3, Z);
		$$->lineno = line($3);
	}
|	LSET '(' zelist ')' ';'
	{
		$$ = new(OSET, $3, Z);
		$$->lineno = line($3);
	}

zcexpr:
	{
		$$ = Z;
	}
|	cexpr

zexpr:
	{
		$$ = Z;
	}
|	lexpr

lexpr:
	expr
	{
		$$ = new(OCAST, $1, Z);
		$$->type = types[TLONG];
	}

cexpr:
	expr
|	cexpr ',' cexpr
	{
		$$ = new(OCOMMA, $1, $3);
	}

expr:
	xuexpr
|	expr '*' expr
	{
		$$ = new(OMUL, $1, $3);
	}
|	expr '/' expr
	{
		$$ = new(ODIV, $1, $3);
	}
|	expr '%' expr
	{
		$$ = new(OMOD, $1, $3);
	}
|	expr '+' expr
	{
		$$ = new(OADD, $1, $3);
	}
|	expr '-' expr
	{
		$$ = new(OSUB, $1, $3);
	}
|	expr LRSH expr
	{
		$$ = new(OASHR, $1, $3);
	}
|	expr LLSH expr
	{
		$$ = new(OASHL, $1, $3);
	}
|	expr '<' expr
	{
		$$ = new(OLT, $1, $3);
	}
|	expr '>' expr
	{
		$$ = new(OGT, $1, $3);
	}
|	expr LLE expr
	{
		$$ = new(OLE, $1, $3);
	}
|	expr LGE expr
	{
		$$ = new(OGE, $1, $3);
	}
|	expr LEQ expr
	{
		$$ = new(OEQ, $1, $3);
	}
|	expr LNE expr
	{
		$$ = new(ONE, $1, $3);
	}
|	expr '&' expr
	{
		$$ = new(OAND, $1, $3);
	}
|	expr '^' expr
	{
		$$ = new(OXOR, $1, $3);
	}
|	expr '|' expr
	{
		$$ = new(OOR, $1, $3);
	}
|	expr LANDAND expr
	{
		$$ = new(OANDAND, $1, $3);
	}
|	expr LOROR expr
	{
		$$ = new(OOROR, $1, $3);
	}
|	expr '?' cexpr ':' expr
	{
		$$ = new(OCOND, $1, new(OLIST, $3, $5));
	}
|	expr '=' expr
	{
		$$ = new(OAS, $1, $3);
	}
|	expr LPE expr
	{
		$$ = new(OASADD, $1, $3);
	}
|	expr LME expr
	{
		$$ = new(OASSUB, $1, $3);
	}
|	expr LMLE expr
	{
		$$ = new(OASMUL, $1, $3);
	}
|	expr LDVE expr
	{
		$$ = new(OASDIV, $1, $3);
	}
|	expr LMDE expr
	{
		$$ = new(OASMOD, $1, $3);
	}
|	expr LLSHE expr
	{
		$$ = new(OASASHL, $1, $3);
	}
|	expr LRSHE expr
	{
		$$ = new(OASASHR, $1, $3);
	}
|	expr LANDE expr
	{
		$$ = new(OASAND, $1, $3);
	}
|	expr LXORE expr
	{
		$$ = new(OASXOR, $1, $3);
	}
|	expr LORE expr
	{
		$$ = new(OASOR, $1, $3);
	}

xuexpr:
	uexpr
|	'(' tlist abdecor ')' xuexpr
	{
		$$ = new(OCAST, $5, Z);
		dodecl(NODECL, CXXX, $2, $3, 1);
		$$->type = lastdcl;
	}
|	'(' tlist abdecor ')' '{' ilist '}'	/* extension */
	{
		$$ = new(OSTRUCT, $6, Z);
		dodecl(NODECL, CXXX, $2, $3, 1);
		$$->type = lastdcl;
	}

uexpr:
	pexpr
|	'*' xuexpr
	{
		$$ = new(OIND, $2, Z);
	}
|	'&' xuexpr
	{
		$$ = new(OADDR, $2, Z);
	}
|	'+' xuexpr
	{
		$$ = new(OPOS, $2, Z);
	}
|	'-' xuexpr
	{
		$$ = new(ONEG, $2, Z);
	}
|	'!' xuexpr
	{
		$$ = new(ONOT, $2, Z);
	}
|	'~' xuexpr
	{
		$$ = new(OCOM, $2, Z);
	}
|	LPP xuexpr
	{
		$$ = new(OPREINC, $2, Z);
	}
|	LMM xuexpr
	{
		$$ = new(OPREDEC, $2, Z);
	}
|	LSIZEOF uexpr
	{
		$$ = new(OSIZE, $2, Z);
	}
|	LSIGNOF uexpr
	{
		$$ = new(OSIGN, $2, Z);
	}

pexpr:
	'(' cexpr ')'
	{
		$$ = $2;
	}
|	LSIZEOF '(' tlist abdecor ')'
	{
		$$ = new(OSIZE, Z, Z);
		dodecl(NODECL, CXXX, $3, $4, 1);
		$$->type = lastdcl;
	}
|	LSIGNOF '(' tlist abdecor ')'
	{
		$$ = new(OSIGN, Z, Z);
		dodecl(NODECL, CXXX, $3, $4, 1);
		$$->type = lastdcl;
	}
|	pexpr '(' zelist ')'
	{
		$$ = new(OFUNC, $1, Z);
		if($1->op == ONAME)
		if($1->type == T)
			dodecl(xdecl, CXXX, types[TINT], $$, 1);
		$$->right = invert($3);
		$$->kind = KEXP;
	}
|	pexpr '[' cexpr ']'
	{
		$$ = new(OARRIND, $1, $3);
	}
|	pexpr LMG ltag
	{
		$$ = new(ODOTIND, $1, Z);
		$$->sym = $3;
	}
|	pexpr '.' ltag
	{
		$$ = new(ODOT, $1, Z);
		$$->sym = $3;
	}
|	pexpr LPP
	{
		$$ = new(OPOSTINC, $1, Z);
	}
|	pexpr LMM
	{
		$$ = new(OPOSTDEC, $1, Z);
	}
|	name
|	LCHARACTER
	{
		$$ = new(OCONST, Z, Z);
		$$->type = types[TINT];
		$$->vconst = $1;
		$$->kind = KCHR;
	}
|	LCONST
	{
		$$ = new(OCONST, Z, Z);
		$$->type = types[TINT];
		$$->vconst = $1;
		$$->kind = lastnumbase;
	}
|	LLCONST
	{
		$$ = new(OCONST, Z, Z);
		$$->type = types[TLONG];
		$$->vconst = $1;
		$$->kind = lastnumbase;
	}
|	LUCONST
	{
		$$ = new(OCONST, Z, Z);
		$$->type = types[TUINT];
		$$->vconst = $1;
		$$->kind = lastnumbase;
	}
|	LULCONST
	{
		$$ = new(OCONST, Z, Z);
		$$->type = types[TULONG];
		$$->vconst = $1;
		$$->kind = lastnumbase;
	}
|	LDCONST
	{
		$$ = new(OCONST, Z, Z);
		$$->type = types[TDOUBLE];
		$$->fconst = $1;
		$$->cstring = strdup(symb);
		$$->kind = lastnumbase;
	}
|	LFCONST
	{
		$$ = new(OCONST, Z, Z);
		$$->type = types[TFLOAT];
		$$->fconst = $1;
		$$->cstring = strdup(symb);
		$$->kind = lastnumbase;
	}
|	LVLCONST
	{
		$$ = new(OCONST, Z, Z);
		$$->type = types[TVLONG];
		$$->vconst = $1;
		$$->kind = lastnumbase;
	}
|	LUVLCONST
	{
		$$ = new(OCONST, Z, Z);
		$$->type = types[TUVLONG];
		$$->vconst = $1;
		$$->kind = lastnumbase;
	}
|	string
|	lstring

sstring:
	LSTRING
	{
		$$ = new(OSTRING, Z, Z);
		$$->type = typ(TARRAY, types[TCHAR]);
		$$->type->width = $1.l + 1;
		$$->cstring = $1.s;
		$$->sym = symstring;
	}

string:
	sstring
	{
		$$ = $1;
	}
|	string sstring
	{
		char *s;
		int n1, n2;

		n1 = $1->type->width - 1;
		n2 = $2->type->width - 1;
		s = alloc(n1+n2+MAXALIGN);

		memcpy(s, $1->cstring, n1);
		memcpy(s+n1, $2->cstring, n2);
		s[n1+n2] = 0;

		$1->left = new(OCAT, ncopy($1), $2);

		$$ = $1;
		$$->type->width += n2;
		$$->cstring = s;
	}

slstring:
	LLSTRING
	{
		$$ = new(OLSTRING, Z, Z);
		$$->type = typ(TARRAY, types[TUSHORT]);
		$$->type->width = $1.l + sizeof(TRune);
		$$->rstring = (TRune*)$1.s;
		$$->sym = symstring;
	}

lstring:
	slstring
	{
		$$ = $1;
	}
|	lstring slstring
	{
		char *s;
		int n1, n2;

		n1 = $1->type->width - sizeof(TRune);
		n2 = $2->type->width - sizeof(TRune);
		s = alloc(n1+n2+MAXALIGN);

		memcpy(s, $1->rstring, n1);
		memcpy(s+n1, $2->rstring, n2);
		*(TRune*)(s+n1+n2) = 0;

		$1->left = new(OCAT, ncopy($1), $2);

		$$ = $1;
		$$->type->width += n2;
		$$->rstring = (TRune*)s;
	}

zelist:
	{
		$$ = Z;
	}
|	elist

elist:
	expr
|	elist ',' elist
	{
		$$ = new(OLIST, $1, $3);
	}

sbody:
	'{'
	{
		$<tyty>$.t1 = strf;
		$<tyty>$.t2 = strl;
		strf = T;
		strl = T;
		lastbit = 0;
		firstbit = 1;
	}
	edecl '}'
	{
		$$ = strf;
		strf = $<tyty>2.t1;
		strl = $<tyty>2.t2;
	}

zctlist:
	{
		lastclass = CXXX;
		lasttype = types[TINT];
	}
|	ctlist

etypes:
	complex
	{
		$$.t = $1;
		$$.c = CXXX;
	}
|	tnlist
	{
		$$.t = simplet($1);
		$$.c = simplec($1);
	}

types:
	complex
	{
		$$.t = $1;
		$$.c = CXXX;
	}
|	complex gctnlist
	{
		$$.t = $1;
		$$.c = simplec($2);
		if($2 & ~BCLASS & ~BGARB)
			diag(Z, "illegal combination of types 1: %Q/%T", $2, $1);
	}
|	gctnlist
	{
		$$.t = simplet($1);
		$$.c = simplec($1);
		$$.t = garbt($$.t, $1);
	}
|	gctnlist complex
	{
		$$.t = $2;
		$$.c = simplec($1);
		$$.t = garbt($$.t, $1);
		if($1 & ~BCLASS & ~BGARB)
			diag(Z, "illegal combination of types 2: %Q/%T", $1, $2);
	}
|	gctnlist complex gctnlist
	{
		$$.t = $2;
		$$.c = simplec($1|$3);
		$$.t = garbt($$.t, $1|$3);
		if(($1|$3) & ~BCLASS & ~BGARB || $3 & BCLASS)
			diag(Z, "illegal combination of types 3: %Q/%T/%Q", $1, $2, $3);
	}

etlist:
	zgnlist etypes
	{
		$$ = $2.t;
		if($2.c != CXXX)
			diag(Z, "illegal combination of class 4: %s", cnames[$2.c]);
		$$ = garbt($$, $1);
	}

tlist:
	types
	{
		$$ = $1.t;
		if($1.c != CXXX)
			diag(Z, "illegal combination of class 4: %s", cnames[$1.c]);
	}

ctlist:
	types
	{
		lasttype = $1.t;
		lastclass = $1.c;
	}

complex:
	LSTRUCT ltag
	{
		dotag($2, TSTRUCT, 0);
		$$ = $2->suetag;
		$2->lineno = lineno;
	}
|	LSTRUCT ltag
	{
		dotag($2, TSTRUCT, autobn);
		saveline = $2->lineno = lineno;
	}
	sbody
	{
		$$ = $2->suetag;
		if($$->link != T)
			diag(Z, "redeclare tag: %s", $2->name);
		$$->link = $4;
		$$->lineno = saveline;
		suallign($$);
	}
|	LSTRUCT
	{
		saveline = lineno;
	}
	sbody
	{
		char buf[128];

		taggen++;
		sprint(symb, "%s_adt_%d", outmod(buf, -1), taggen);
		$$ = dotag(lookup(), TSTRUCT, autobn);
		$$->link = $3;
		$$->lineno = saveline;
		lookup()->lineno = saveline;
		suallign($$);
	}
|	LUNION ltag
	{
		dotag($2, TUNION, 0);
		$$ = $2->suetag;
		$2->lineno = lineno;
	}
|	LUNION ltag
	{
		dotag($2, TUNION, autobn);
		saveline = $2->lineno = lineno;
	}
	sbody
	{
		$$ = $2->suetag;
		if($$->link != T)
			diag(Z, "redeclare tag: %s", $2->name);
		$$->link = $4;
		$$->lineno = saveline;
		suallign($$);
	}
|	LUNION
	{
		saveline = lineno;
	}
	sbody
	{
		char buf[128];

		taggen++;
		sprint(symb, "%s_adt_%d", outmod(buf, -1), taggen);
		$$ = dotag(lookup(), TUNION, autobn);
		$$->link = $3;
		$$->lineno = saveline;
		lookup()->lineno = saveline;
		suallign($$);
	}
|	LENUM ltag
	{
		dotag($2, TENUM, 0);
		$$ = $2->suetag;
		if($$->link == T)
			$$->link = types[TINT];
		$$ = $$->link;
		$2->lineno = lineno;
	}
|	LENUM ltag
	{
		dotag($2, TENUM, autobn);
		$2->lineno = lineno;
	}
	'{'
	{
		en.tenum = T;
		en.cenum = T;
	}
	enum '}'
	{
		$$ = $2->suetag;
		if($$->link != T)
			diag(Z, "redeclare tag: %s", $2->name);
		if(en.tenum == T) {
			diag(Z, "enum type ambiguous: %s", $2->name);
			en.tenum = types[TINT];
		}
		$$->link = en.tenum;
		$$ = en.tenum;
		etgen(nil);
	}
|	LENUM '{'
	{
		en.tenum = T;
		en.cenum = T;
	}
	enum '}'
	{
		$$ = en.tenum;
		etgen(nil);
	}
|	LCTYPE
	{
		$$ = tcopy($1->type);
	}
|	LSTYPE
	{
		$$ = tcopy($1->type);
	}

tnlist:
	tname
|	tnlist tname
	{
		$$ = typebitor($1, $2);
	}

gctnlist:
	gctname
|	gctnlist gctname
	{
		$$ = typebitor($1, $2);
	}

zgnlist:
	{
		$$ = 0;
	}
|	zgnlist gname
	{
		$$ = typebitor($1, $2);
	}

gctname:
	tname
|	gname
|	cname

enum:
	LNAME
	{
		doenum($1, Z);
		$1->lineno = lineno;
	}
|	LNAME '=' expr
	{
		doenum($1, $3);
		$1->lineno = lineno;
	}
|	enum ','
|	enum ',' enum

tname:	/* type words */
	LCHAR { $$ = BCHAR; }
|	LSHORT { $$ = BSHORT; }
|	LINT { $$ = BINT; }
|	LLONG { $$ = BLONG; }
|	LSIGNED { $$ = BSIGNED; }
|	LUNSIGNED { $$ = BUNSIGNED; }
|	LFLOAT { $$ = BFLOAT; }
|	LDOUBLE { $$ = BDOUBLE; }
|	LVOID { $$ = BVOID; }
|	LVLONG { $$ = BVLONG|BLONG; }

cname:	/* class words */
	LAUTO { $$ = BAUTO; }
|	LSTATIC { $$ = BSTATIC; }
|	LEXTERN { $$ = BEXTERN; }
|	LTYPEDEF { $$ = BTYPEDEF; }
|	LREGISTER { $$ = BREGISTER; }

gname:
	LCONSTNT { $$ = BCONSTNT; }
|	LVOLATILE { $$ = BVOLATILE; }

name:
	LNAME
	{
		$$ = new(ONAME, Z, Z);
		if($1->class == CLOCAL)
			$1 = mkstatic($1);
		$$->sym = $1;
		$$->type = $1->type;
	}
tag:
	ltag
	{
		$$ = new(ONAME, Z, Z);
		$$->sym = $1;
		$$->type = $1->type;
	}
ltag:
	LNAME
|	LCTYPE
|	LSTYPE

%%
