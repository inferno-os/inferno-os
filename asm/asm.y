%{
#include "asm.h"
union {
	uvlong	l;
	double	d;
} u;
%}

%union
{
	Inst*	inst;
	Addr*	addr;
	vlong	ival;
	double	fval;
	String*	string;
	Sym*	sym;
	List*	list;
}

%left	'|'
%left	'^'
%left	'&'
%left	'<' '>'
%left	'+' '-'
%left	'*' '/' '%'

%type<inst>	label ilist inst
%type<ival>	con expr heapid
%type<addr>	addr raddr mem roff
%type<list>	elist
%type<string>	ptrs
%token<ival>	TOKI0 TOKI1 TOKI2 TOKI3 TCONST
%token		TOKSB TOKFP TOKHEAP TOKDB TOKDW TOKDL TOKDF TOKDS TOKVAR
%token		TOKEXT TOKMOD TOKLINK TOKENTRY TOKARRAY TOKINDIR TOKAPOP TOKLDTS TOKEXCS TOKEXC TOKETAB TOKSRC
%token<sym>	TID
%token<fval>	TFCONST
%token<string>	TSTRING

%%
prog	: ilist
	{
		assem($1);
	}
	;

ilist	:
	{ $$ = nil; }
	| ilist label
	{
		if($2 != nil) {
			$2->link = $1;
			$$ = $2;
		}
		else
			$$ = $1;
	}
	;

label	: TID ':' inst
	{
		$3->sym = $1;
		$$ = $3;
	}
	| TOKHEAP heapid ',' expr ptrs
	{
		heap($2, $4, $5);
		$$ = nil;
	}
	| data
	{
		$$ = nil;
	}
	| inst
	;

heapid	: '$' expr
	{
		$$ = $2;
	}
	| TID
	{
		$1->value = heapid++;
		$$ = $1->value;
	}
	;

ptrs	:
	{ $$ = nil; }
	| ',' TSTRING
	{
		$$ = $2;
	}
	;

elist	: expr
	{
		$$ = newi($1, nil);
	}
	| elist ',' expr
	{
		$$ = newi($3, $1);
	}
	;

inst	: TOKI3 addr ',' addr
	{
		$$ = ai($1);
		$$->src = $2;
		$$->dst = $4;
	}
	| TOKI3 addr ',' raddr ',' addr
	{
		$$ = ai($1);
		$$->src = $2;
		$$->reg = $4;
		$$->dst = $6;
	}
	| TOKI2 addr ',' addr
	{
		$$ = ai($1);
		$$->src = $2;
		$$->dst = $4;
	}
	| TOKI1 addr
	{
		$$ = ai($1);
		$$->dst = $2;
	}
	| TOKI0
	{
		$$ = ai($1);
	}
	;

data	: TOKDB expr ',' elist
	{
		data(DEFB, $2, $4);
	}
	| TOKDW expr ',' elist
	{
		data(DEFW, $2, $4);
	}
	| TOKDL expr ',' elist
	{
		data(DEFL, $2, $4);
	}
	| TOKDF expr ',' TCONST
	{
		data(DEFF, $2, newi(dtocanon((double)$4), nil));
	}
	| TOKDF expr ',' TFCONST
	{
		data(DEFF, $2, newi(dtocanon($4), nil));
	}
	| TOKDF expr ',' TID
	{
		if(strcmp($4->name, "Inf") == 0 || strcmp($4->name, "Infinity") == 0) {
			u.l = 0x7ff0000000000000;
			data(DEFF, $2, newi(dtocanon(u.d), nil));
		} else if(strcmp($4->name, "NaN") == 0) {
			u.l = 0x7fffffffffffffff;
			data(DEFF, $2, newi(dtocanon(u.d), nil));
		} else
			diag("bad value for real: %s", $4->name);
	}
	| TOKDF expr ',' '-' TCONST
	{
		data(DEFF, $2, newi(dtocanon(-(double)$5), nil));
	}
	| TOKDF expr ',' '-' TFCONST
	{
		data(DEFF, $2, newi(dtocanon(-$5), nil));
	}
	| TOKDF expr ',' '-' TID
	{
		if(strcmp($5->name, "Inf") == 0 || strcmp($5->name, "Infinity") == 0) {
			u.l = 0xfff0000000000000;
			data(DEFF, $2, newi(dtocanon(u.d), nil));
		} else
			diag("bad value for real: %s", $5->name);
	}
	| TOKDS expr ',' TSTRING
	{
		data(DEFS, $2, news($4, nil));
	}
	| TOKVAR TID ',' expr
	{
		if($2->ds != 0)
			diag("%s declared twice", $2->name);
		$2->ds = $4;
		$2->value = dseg;
		dseg += $4;
	}
	| TOKEXT expr ',' expr ',' TSTRING
	{
		ext($2, $4, $6);
	}
	| TOKLINK expr ',' expr ',' expr ',' TSTRING
	{
		mklink($2, $4, $6, $8);
	}
	| TOKMOD TID
	{
		if(module != nil)
			diag("this module already defined as %s", $2->name);
		else
			module = $2;
	}
	| TOKENTRY expr ',' expr
	{
		if(pcentry >= 0)
			diag("this module already has entry point %d, %d" , pcentry, dentry);
		pcentry = $2;
		dentry = $4;
	}
	| TOKARRAY expr ',' heapid ',' expr
	{
		data(DEFA, $2, newa($4, $6));
	}
	| TOKINDIR expr ',' expr
	{
		data(DIND, $2, newa($4, 0));
	}
	| TOKAPOP
	{
		data(DAPOP, 0, newa(0, 0));
	}
	| TOKLDTS TID ',' expr
	{
		ldts($4);
	}
	| TOKEXCS expr
	{
		excs($2);
	}
	| TOKEXC expr ',' expr ',' expr ',' expr ',' expr ',' expr
	{
		exc($2, $4, $6, $8, $10, $12);
	}
	| TOKETAB TSTRING ',' expr
	{
		etab($2, $4);
	}
	| TOKETAB '*' ',' expr
	{
		etab(nil, $4);
	}
	| TOKSRC TSTRING
	{
		source($2);
	}
	;

raddr	: '$' expr
	{
		$$ = aa($2);
		$$->mode = AXIMM;
		if($$->val > 0x7FFF || $$->val < -0x8000)
			diag("immediate %d too large for middle operand", $$->val);
	}
	| roff
	{
		if($1->mode == AMP)
			$1->mode = AXINM;
		else
			$1->mode = AXINF;
		if($1->mode == AXINM && (ulong)$1->val > 0xFFFF)
			diag("register offset %d(mp) too large", $1->val);
		if($1->mode == AXINF && (ulong)$1->val > 0xFFFF)
			diag("register offset %d(fp) too large", $1->val);
		$$ = $1;
	}
	;

addr	: '$' expr
	{
		$$ = aa($2);
		$$->mode = AIMM;
	}
	| TID
	{
		$$ = aa(0);
		$$->sym = $1;
	}
	| mem
	;

mem	: '*' roff
	{
		$2->mode |= AIND;
		$$ = $2;
	}
	| expr '(' roff ')'
	{
		$3->mode |= AIND;
		if($3->val & 3)
			diag("indirect offset must be word size");
		if($3->mode == (AMP|AIND) && ((ulong)$3->val > 0xFFFF || (ulong)$1 > 0xFFFF))
			diag("indirect offset %d(%d(mp)) too large", $1, $3->val);
		if($3->mode == (AFP|AIND) && ((ulong)$3->val > 0xFFFF || (ulong)$1 > 0xFFFF))
			diag("indirect offset %d(%d(fp)) too large", $1, $3->val);
		$3->off = $3->val;
		$3->val = $1;
		$$ = $3;
	}
	| roff
	;

roff	: expr '(' TOKSB ')'
	{
		$$ = aa($1);
		$$->mode = AMP;
	}
	| expr '(' TOKFP ')'
	{
		$$ = aa($1);
		$$->mode = AFP;
	}
	;

con	: TCONST
	| TID
	{
		$$ = $1->value;
	}
	| '-' con
	{
		$$ = -$2;
	}
	| '+' con
	{
		$$ = $2;
	}
	| '~' con
	{
		$$ = ~$2;
	}
	| '(' expr ')'
	{
		$$ = $2;
	}
	;

expr:	con
	| expr '+' expr
	{
		$$ = $1 + $3;
	}
	| expr '-' expr
	{
		$$ = $1 - $3;
	}
	| expr '*' expr
	{
		$$ = $1 * $3;
	}
	| expr '/' expr
	{
		$$ = $1 / $3;
	}
	| expr '%' expr
	{
		$$ = $1 % $3;
	}
	| expr '<' '<' expr
	{
		$$ = $1 << $4;
	}
	| expr '>' '>' expr
	{
		$$ = $1 >> $4;
	}
	| expr '&' expr
	{
		$$ = $1 & $3;
	}
	| expr '^' expr
	{
		$$ = $1 ^ $3;
	}
	| expr '|' expr
	{
		$$ = $1 | $3;
	}
	;
