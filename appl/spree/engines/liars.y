%{


YYSTYPE: adt {
};

YYLEX: adt {
	lval: YYSTYPE;
	lex: fn(l: self ref YYLEX): int;
	error: fn(l: self ref YYLEX, err: string);
	toks: list of string;
};
%}

%module Sh {
	# module definition is in shell.m
}
%token A ALL AND BROKEN FIVE FOUR FUCK FULL HIGH
%token HOUSE KIND LOW NOTHING OF ON PAIR PAIRS STRAIGHT THREE TWO VALUE

%start phrase
%%
phrase: nothing
	| pair
	| twopairs
	| threes
	| lowstraight
	| fullhouse
	| highstraight
	| fours
	| fives

pair:	PAIR
	| PAIR ofsomething ',' extras

nothing: NOTHING
	| BROKEN STRAIGHT
	| FUCK ALL

twopairs: TWO PAIRS moretuppers
	| TWO VALUE optcomma TWO VALUE and_a VALUE
	| PAIR OF VALUE ',' PAIR OF VALUE and_a VALUE

moretuppers:
	|	',' VALUE ',' VALUE and_a VALUE

threes:	THREE OF A KIND extras
	| THREE VALUE extras

lowstraight: LOW STRAIGHT

fullhouse:	FULL HOUSE
	| FULL HOUSE optcomma VALUE
	| FULL HOUSE optcomma VALUE ON VALUE
	| FULL HOUSE optcomma VALUE HIGH

highstraight:	HIGH STRAIGHT

fours:	FOUR OF A KIND extras
	| FOUR VALUE extras

fives:	FIVE OF A KIND
	|	FIVE VALUE
and_a:	# null
	|	AND A
optcomma:
	|	','
extras: VALUE
	| extras VALUE
%%

Tok: adt {
	s: string;
	tok: int;
	val: int;
};

known := array of {
Tok("an", A, -1),
Tok("a",  A, -1),
Tok("all",  ALL, -1),
Tok("and",  AND, -1),
Tok("broken",  BROKEN, -1),
Tok(",",  ',', -1),
Tok("five",  FIVE, -1),
Tok("5",	FIVE, -1),
Tok("four",  FOUR, -1),
Tok("4", FOUR, -1),
Tok("fuck",  FUCK, -1),
Tok("full",  FULL, -1),
Tok("high",  HIGH, -1),
Tok("house",  HOUSE, -1),
Tok("kind",  KIND, -1),
Tok("low",  LOW, -1),
Tok("nothing",  NOTHING, -1),
Tok("of",  OF, -1),
Tok("on",  ON, -1),
Tok("pair",  PAIR, -1),
Tok("pairs",  PAIRS, -1),
Tok("straight",  STRAIGHT, -1),
Tok("three",  THREE, -1),
Tok("3", THREE, -1),
Tok("two",  TWO, -1),
Tok("2", TWO, -1),

Tok("A", VALUE, 5),
Tok("K", VALUE, 4),
Tok("Q", VALUE, 3),
Tok("J", VALUE, 2),
Tok("10", VALUE, 1),
Tok("9", VALUE, 0),

Tok("ace"
};

YYLEX.lex(l: self ref YYLEX): int
{
	if (l.toks == nil)
		return -1;
	t := hd l.toks;
	for (i := 0; i < len known; i++) {
		if (known[i].t0 == t)
			return known[i].t1;
		
	case hd l.toks {


%token A ALL AND BROKEN FIVE FOUR FUCK FULL HIGH
%token HOUSE KIND LOW NOTHING OF ON PAIR PAIRS STRAIGHT THREE TWO VALUE
%token END

}