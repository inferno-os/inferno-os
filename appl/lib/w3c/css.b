implement CSS;

#
# CSS2 parsing module
#
# CSS2.1 style sheets 
#
# Copyright © 2001, 2005 Vita Nuova Holdings Limited.  All rights reserved.
#

include "sys.m";
	sys: Sys;

include "css.m";

B, NUMBER, IDENT, STRING, URL, PERCENTAGE, UNIT,
	HASH, ATKEYWORD, IMPORTANT, IMPORT, PSEUDO, CLASS, INCLUDES,
	DASHMATCH, FUNCTION: con 16rE000+iota;

toknames := array[] of{
	B-B => "Zero",
	NUMBER-B => "NUMBER",
	IDENT-B => "IDENT",
	STRING-B => "STRING",
	URL-B => "URL",
	PERCENTAGE-B => "PERCENTAGE",
	UNIT-B => "UNIT",
	HASH-B => "HASH",
	ATKEYWORD-B => "ATKEYWORD",
	IMPORTANT-B => "IMPORTANT",
	CLASS-B => "CLASS",
	INCLUDES-B => "INCLUDES",
	DASHMATCH-B => "DASHMATCH",
	PSEUDO-B => "PSEUDO",
	FUNCTION-B => "FUNCTION",
};

printdiag := 0;

init(d: int)
{
	sys = load Sys Sys->PATH;
	printdiag = d;
}

parse(s: string): (ref Stylesheet, string)
{
	return stylesheet(ref Cparse(-1, 0, nil, nil, Clex.new(s,1)));
}

parsedecl(s: string): (list of ref Decl, string)
{
	return (declarations(ref Cparse(-1, 0, nil, nil, Clex.new(s,0))), nil);
}

ptok(c: int): string
{
	if(c < 0)
		return "eof";
	if(c == 0)
		return "zero?";
	if(c >= B)
		return sys->sprint("%s", toknames[c-B]);
	return sys->sprint("%c", c);
}

Cparse: adt {
	lookahead:	int;
	eof:	int;
	value:	string;
	suffix:	string;
	cs:	ref Clex;

	get:	fn(nil: self ref Cparse): int;
	look:	fn(nil: self ref Cparse): int;
	unget:	fn(nil: self ref Cparse, tok: int);
	skipto:	fn(nil: self ref Cparse, followset: string): int;
	synerr:	fn(nil: self ref Cparse, s: string);
};

Cparse.get(p: self ref Cparse): int
{
	if((c := p.lookahead) >= 0){
		p.lookahead = -1;
		return c;
	}
	if(p.eof)
		return -1;
	(c, p.value, p.suffix) = csslex(p.cs);
	if(c < 0)
		p.eof = 1;
	if(printdiag > 1)
		sys->print("lex: %s v=%s s=%s\n", ptok(c), p.value, p.suffix);
	return c;
}

Cparse.look(p: self ref Cparse): int
{
	c := p.get();
	p.unget(c);
	return c;
}

Cparse.unget(p: self ref Cparse, c: int)
{
	if(p.lookahead >= 0)
		raise "css: internal error: Cparse.unget";
	p.lookahead = c;	# note that p.value and p.suffix are assumed to be those of c
}

Cparse.skipto(p: self ref Cparse, followset: string): int
{
	while((c := p.get()) >= 0)
		for(i := 0; i < len followset; i++)
			if(followset[i] == c){
				p.unget(c);
				return c;
			}
	return -1;
}

Cparse.synerr(p: self ref Cparse, s: string)
{
	p.cs.synerr(s);
}

#
# stylesheet:
#	["@charset" STRING ';']?
#	[CDO|CDC]* [import [CDO|CDC]*]*
#	[[ruleset | media | page ] [CDO|CDC]*]*
# import:
#	"@import" [STRING|URL] [ medium [',' medium]*]? ';'
# media:
#	"@media" medium [',' medium]* '{' ruleset* '}'
# medium:
#	IDENT
# page:
#	"@page" pseudo_page? '{' declaration [';' declaration]* '}'
# pseudo_page:
#	':' IDENT
#

stylesheet(p: ref Cparse): (ref Stylesheet, string)
{
	charset: string;
	if(atkeywd(p, "@charset")){
		if(itisa(p, STRING)){
			charset = p.value;
			itisa(p, ';');
		}else
			p.synerr("bad @charset declaration");
	}
	imports: list of ref Import;
	while(atkeywd(p, "@import")){
		c := p.get();
		if(c == STRING || c == URL){
			name := p.value;
			media: list of string;
			c = p.get();
			if(c == IDENT){	# optional medium [, ...]
				p.unget(c);
				media = medialist(p);
			}
			imports = ref Import(name, media) :: imports;
		}else
			p.synerr("bad @import");
		if(c != ';'){
			p.synerr("missing ; in @import");
			p.unget(c);
			if(p.skipto(";}") < 0)
				break;
		}
	}
	imports = rev(imports);

	stmts: list of ref Statement;
	do{
		while((c := p.get()) == ATKEYWORD)
			case p.value {
			"@media" =>	# medium[,medium]* { ruleset*}
				media := medialist(p);
				if(!itisa(p, '{')){
					p.synerr("bad @media");
					skipatrule("@media", p);
					continue;
				}
				rules: list of ref Statement.Ruleset;
				do{
					rule := checkrule(p);
					if(rule != nil)
						rules = rule :: rules;
				}while(!itisa(p, '}') && !p.eof);
				stmts = ref Statement.Media(media, rev(rules)) :: stmts;
			"@page" =>	# [:ident]? { declaration [; declaration]* }
				pseudo: string;
				if(itisa(p, PSEUDO))
					pseudo = p.value;
				if(!itisa(p, '{')){
					p.synerr("bad @page");
					skipatrule("@page", p);
					continue;
				}
				decls := declarations(p);
				if(!itisa(p, '}')){
					p.synerr("unclosed @page declaration block");
					skipatrule("@page", p);
					continue;
				}
				stmts = ref Statement.Page(pseudo, decls) :: stmts;
			* =>
				skipatrule(p.value, p);	# skip unknown or misplaced at-rule
			}
		p.unget(c);
		rule := checkrule(p);
		if(rule != nil)
			stmts = rule :: stmts;
	}while(!p.eof);
	rl := stmts;
	stmts = nil;
	for(; rl != nil; rl = tl rl)
		stmts = hd rl :: stmts;
	return (ref Stylesheet(charset, imports, stmts), nil);
}

checkrule(p: ref Cparse): ref Statement.Ruleset
{
	(rule, err) := ruleset(p);
	if(rule == nil){
		if(err != nil){
			p.synerr(sys->sprint("bad ruleset: %s", err));
			p.get();	# make some progress
		}
	}
	return rule;
}

medialist(p: ref Cparse): list of string
{
	media: list of string;
	do{
		c := p.get();
		if(c != IDENT){
			p.unget(c);
			p.synerr("missing medium identifier");
			break;
		}
		media = p.value :: media;
	}while(itisa(p, ','));
	return rev(media);
}

itisa(p: ref Cparse, expect: int): int
{
	if((c := p.get()) == expect)
		return 1;
	p.unget(c);
	return 0;
}

atkeywd(p: ref Cparse, expect: string): int
{
	if((c := p.get()) == ATKEYWORD && p.value == expect)
		return 1;
	p.unget(c);
	return 0;
}

skipatrule(name: string, p: ref Cparse)
{
	if(printdiag)
		sys->print("skip unimplemented or misplaced %s\n", name);
	if((c := p.get()) == '{'){	# block
		for(nesting := '}' :: nil; nesting != nil && c >= 0; nesting = tl nesting){
			while((c = p.cs.getc()) >= 0 && c != hd nesting)
				case c {
				'{' =>
					nesting = '}' :: nesting;
				'(' =>
					nesting = ')' :: nesting;
				'[' =>
					nesting = ']' :: nesting;
				'"' or '\'' =>
					quotedstring(p.cs, c);
				}
		}
	}else{
		while(c >= 0 && c != ';')
			c = p.get();
	}
}

# ruleset:
#	selector [','  S* selector]* '{' S* declaration [';' S* declaration]* '}' S*

ruleset(p: ref Cparse): (ref Statement.Ruleset, string)
{
	selectors: list of list of (int, list of ref Select);
	c := -1;
	do{
		s := selector(p);
		if(s == nil){
			if(p.eof)
				return (nil, nil);
			p.synerr("expected selector");
			if(p.skipto(",{}") < 0)
				return (nil, nil);
			c = p.look();
		}else
			selectors = s :: selectors;
	}while((c = p.get()) == ',');
	if(c != '{')
		return (nil, "expected declaration block");
	sl := selectors;
	selectors = nil;
	for(; sl != nil; sl = tl sl)
		selectors = hd sl :: selectors;
	decls := declarations(p);
	if(!itisa(p, '}')){
		p.synerr("unclosed declaration block");
	}
	return (ref Statement.Ruleset(selectors, decls), nil);
}

declarations(p: ref Cparse): list of ref Decl
{
	decls: list of ref Decl;
	c: int;
	do{
		(d, e) := declaration(p);
		if(d != nil)
			decls = d :: decls;
		else if(e != nil){
			p.synerr("ruleset declaration: "+e);
			if((c = p.skipto(";}")) < 0)
				break;
		}
	}while((c = p.get()) == ';');
	p.unget(c);
	l := decls;
	for(decls = nil; l != nil; l = tl l)
		decls = hd l :: decls;
	return decls;
}

# selector:
#	simple_selector [combinator simple_selector]*
# combinator:
#	'+' S* | '>' S* | /* empty */
#

selector(p: ref Cparse): list of (int, list of ref Select)
{
	sel: list of (int, list of ref Select);
	op := ' ';
	while((s := selector1(p)) != nil){
		sel = (op, s) :: sel;
		if((c := p.look()) == '+' || c == '>')
			op = p.get();
		else
			op = ' ';
	}
	l: list of (int, list of ref Select);
	for(; sel != nil; sel = tl sel)
		l = hd sel :: l;
	return l;
}

#
# simple_selector:
#	element_name? [HASH | class | attrib | pseudo]* S*
# element_name:
#	IDENT | '*'
# class:
#	'.' IDENT
# attrib:
#	'[' S* IDENT S* [ [ '=' | INCLUDES | DASHMATCH ] S* [IDENT | STRING] S* ]? ']'
# pseudo
#	':' [ IDENT | FUNCTION S* IDENT? S* ')' ]

selector1(p: ref Cparse): list of ref Select
{
	sel: list of ref Select;
	c := p.get();
	if(c == IDENT)
		sel = ref Select.Element(p.value) :: sel;
	else if(c== '*')
		sel = ref Select.Any("*") :: sel;
	else
		p.unget(c);
Sel:
	for(;;){
		c = p.get();
		case c {
		HASH =>
			sel = ref Select.ID(p.value) :: sel;
		CLASS =>
			sel = ref Select.Class(p.value) :: sel;
		'[' =>
			if(!itisa(p, IDENT))
				break;
			name := p.value;
			case c = p.get() {
			'=' =>
				sel = ref Select.Attrib(name, "=", optaval(p)) :: sel;
			INCLUDES =>
				sel = ref Select.Attrib(name, "~=", optaval(p)) :: sel;
			DASHMATCH =>
				sel = ref Select.Attrib(name, "|=", optaval(p)) :: sel;
			* =>
				sel = ref Select.Attrib(name, nil, nil) :: sel;
				p.unget(c);
			}
			if((c = p.get()) != ']'){
				p.synerr("bad attribute syntax");
				p.unget(c);
				break Sel;
			}
		PSEUDO =>
			case c = p.get() {
			IDENT =>
				sel = ref Select.Pseudo(p.value) :: sel;
			FUNCTION =>
				name := p.value;
				case c = p.get() {
				IDENT =>
					sel = ref Select.Pseudofn(name, lowercase(p.value)) :: sel;
				')' =>
					p.unget(c);
					sel = ref Select.Pseudofn(name, nil) :: sel;
				* =>
					p.synerr("bad pseudo-function syntax");
					p.unget(c);
					break Sel;
				}
				if((c = p.get()) != ')'){
					p.synerr("missing ')' for pseudo-function");
					p.unget(c);
					break Sel;
				}
			* =>
				p.synerr(sys->sprint("unexpected :pseudo: %s:%s", ptok(c), p.value));
				p.unget(c);
				break Sel;
			}
		* =>
			p.unget(c);
			break Sel;
		}
		# qualifiers must be adjacent to the first item, and each other
		c = p.cs.getc();
		p.cs.ungetc(c);
		if(isspace(c))
			break;
	}
	sl := sel;
	for(sel = nil; sl != nil; sl = tl sl)
		sel = hd sl :: sel;
	return sel;
}

optaval(p: ref Cparse): ref Value
{
	case c := p.get() {
	IDENT =>
		return ref Value.Ident(' ', p.value);
	STRING =>
		return ref Value.String(' ', p.value);
	* =>
		p.unget(c);
		return nil;
	}
}

# declaration:
#	property ':' S* expr prio?
#  |	/* empty */
# property:
#	IDENT
# prio:
#	IMPORTANT S*	/* ! important */

declaration(p: ref Cparse): (ref Decl, string)
{
	c := p.get();
	if(c != IDENT){
		p.unget(c);
		return (nil, nil);
	}
	prop := lowercase(p.value);
	c = p.get();
	if(c != ':'){
		p.unget(c);
		return (nil, "missing :");
	}
	values := expr(p);
	if(values == nil)
		return (nil, "missing expression(s)");
	prio := 0;
	if(p.look() == IMPORTANT){
		p.get();
		prio = 1;
	}
	return (ref Decl(prop, values, prio), nil);
}

# expr:
#	term [operator term]*
# operator:
#	'/' | ',' | /* empty */

expr(p: ref Cparse): list of ref Value
{
	values: list of ref Value;
	sep := ' ';
	while((t := term(p, sep)) != nil){
		values = t :: values;
		if((c := p.look()) == '/' || c == ',')
			sep = p.get();		# need something fancier here?
		else
			sep = ' ';
	}
	vl := values;
	for(values = nil; vl != nil; vl = tl vl)
		values = hd vl :: values;
	return values;
}

#
# term:
#	unary_operator? [NUMBER | PERCENTAGE | LENGTH | EMS | EXS | ANGLE | TIME | FREQ | function]
#	| STRING | IDENT | URI | RGB | UNICODERANGE | hexcolour
# function:
#	FUNCTION expr ')'
# unary_operator:
#	'-' | '+'
# hexcolour:
#	HASH S*
#
# LENGTH, EMS, ... FREQ have been combined into UNIT here
#
# TO DO: UNICODERANGE

term(p: ref Cparse, sep: int): ref Value
{
	prefix: string;
	case p.look(){
	'+' or '-' =>
		prefix[0] = p.get();
	}
	c := p.get();
	case c {
	NUMBER =>
		return ref Value.Number(sep, prefix+p.value);
	PERCENTAGE =>
		return ref Value.Percentage(sep, prefix+p.value);
	UNIT =>
		return ref Value.Unit(sep, prefix+p.value, p.suffix);
	}
	if(prefix != nil)
		p.synerr("+/- before non-numeric");
	case c {
	STRING =>
		return ref Value.String(sep, p.value);
	IDENT =>
		return ref Value.Ident(sep, lowercase(p.value));
	URL =>
		return ref Value.Url(sep, p.value);
	HASH =>
		# could check value: 3 or 6 hex digits
		(r, g, b) := torgb(p.value);
		if(r < 0)
			return nil;
		return ref Value.Hexcolour(sep, p.value, (r,g,b));
	FUNCTION =>
		name := p.value;
		args := expr(p);
		c = p.get();
		if(c != ')'){
			p.synerr(sys->sprint("missing ')' for function %s", name));
			return nil;
		}
		if(name == "rgb"){
			if(len args != 3){
				p.synerr("wrong number of arguments to rgb()");
				return nil;
			}
			r := colourof(hd args);
			g := colourof(hd tl args);
			b := colourof(hd tl tl args);
			if(r < 0 || g < 0 || b < 0){
				p.synerr("invalid rgb() parameters");
				return nil;
			}
			return ref Value.RGB(sep, args, (r,g,b));
		}
		return ref Value.Function(sep, name, args);
	* =>
		p.unget(c);
		return nil;
	}
}

torgb(s: string): (int, int, int)
{
	case len s {
	3 =>
		r := hex(s[0]);
		g := hex(s[1]);
		b := hex(s[2]);
		if(r >= 0 && g >= 0 && b >= 0)
			return ((r<<4)|r, (g<<4)|g, (b<<4)|b);
	6 =>
		v := 0;
		for(i := 0; i < 6; i++){
			n := hex(s[i]);
			if(n < 0)
				return (-1, 0, 0);
			v = (v<<4) | n;
		}
		return (v>>16, (v>>8)&16rFF, v&16rFF);
	}
	return (-1, 0, 0);
}

colourof(v: ref Value): int
{
	pick r := v {
	Number =>
		return clip(int r.value, 0, 255);
	Percentage =>
		# just the integer part
		return clip((int r.value*255 + 50)/100, 0, 255);
	* =>
		return -1;
	}
}

clip(v: int, l: int, u: int): int
{
	if(v < l)
		return l;
	if(v > u)
		return u;
	return v;
}

rev[T](l: list of T): list of T
{
	t: list of T;
	for(; l != nil; l = tl l)
		t = hd l :: t;
	return t;
}

Clex: adt {
	context:	list of int;	# characters
	input:	string;
	lim:	int;
	n:	int;
	lineno:	int;

	new:	fn(s: string, lno: int): ref Clex;
	getc:	fn(cs: self ref Clex): int;
	ungetc:	fn(cs: self ref Clex, c: int);
	synerr:	fn(nil: self ref Clex, s: string);
};

Clex.new(s: string, lno: int): ref Clex
{
	return ref Clex(nil, s, len s, 0, lno);
}

Clex.getc(cs: self ref Clex): int
{
	if(cs.context != nil){
		c := hd cs.context;
		cs.context = tl cs.context;
		return c;
	}
	if(cs.n >= cs.lim)
		return -1;
	c := cs.input[cs.n++];
	if(c == '\n')
		cs.lineno++;
	return c;
}

Clex.ungetc(cs: self ref Clex, c: int)
{
	cs.context = c :: cs.context;
}

Clex.synerr(cs: self ref Clex, s: string)
{
	if(printdiag)
		sys->fprint(sys->fildes(2), "%d: err: %s\n", cs.lineno, s);
}

csslex(cs: ref Clex): (int, string, string)
{
	for(;;){
		c := skipws(cs);
		if(c < 0)
			return (-1, nil, nil);
		case c {
		'<' =>
			if(seq(cs, "!--"))
				break;		# <!-- ignore HTML comment start (CDO)
			return (c, nil, nil);
		'-' =>
			if(seq(cs, "->"))
				break;		# --> ignore HTML comment end (CDC)
			return (c, nil, nil);
		':' =>
			c = cs.getc();
			cs.ungetc(c);
			if(isnamec(c, 0))
				return (PSEUDO, nil, nil);
			return (':', nil, nil);
		'#' =>
			c = cs.getc();
			if(isnamec(c, 1))
				return (HASH, name(cs, c), nil);
			cs.ungetc(c);
			return ('#', nil, nil);
		'/' =>
			if(subseq(cs, '*', 1, 0)){
				comment(cs);
				break;
			}
			return (c, nil, nil);
		'\'' or '"' =>
			return (STRING, quotedstring(cs, c), nil);
		'0' to '9' or '.' =>
			if(c == '.'){
				d := cs.getc();
				cs.ungetc(d);
				if(!isdigit(d)){
					if(isnamec(d, 1))
						return (CLASS, name(cs, cs.getc()), nil);
					return ('.', nil, nil);
				}
				# apply CSS2 treatment: .55 is a number not a class
			}
			val := number(cs, c);
			c = cs.getc();
			if(c == '%')
				return (PERCENTAGE, val, "%");
			if(isnamec(c, 0))	# use CSS2 interpetation
				return (UNIT, val, lowercase(name(cs, c)));
			cs.ungetc(c);
			return (NUMBER, val, nil);
		'\\' =>
			d := cs.getc();
			if(d >= ' ' && d <= '~' || islatin1(d)){	# probably should handle it in name
				wd := name(cs, d);
				return (IDENT, "\\"+wd, nil);
			}
			cs.ungetc(d);
			return ('\\', nil, nil);
		'@' =>
			c = cs.getc();
			if(isnamec(c, 0))	# @something
				return (ATKEYWORD, "@"+lowercase(name(cs,c)), nil);
			cs.ungetc(c);
			return ('@', nil, nil);
		'!' =>
			c = skipws(cs);
			if(isnamec(c, 0)){	# !something
				wd := name(cs, c);
				if(lowercase(wd) == "important")
					return (IMPORTANT, nil, nil);
				pushback(cs, wd);
			}else
				cs.ungetc(c);
			return ('!', nil, nil);
		'~' =>
			if(subseq(cs, '=', 1, 0))
				return (INCLUDES, "~=", nil);
			return ('~', nil, nil);
		'|' =>
			if(subseq(cs, '=', 1, 0))
				return (DASHMATCH, "|=", nil);
			return ('|', nil, nil);
		* =>
			if(isnamec(c, 0)){
				wd := name(cs, c);
				d := cs.getc();
				if(d != '('){
					cs.ungetc(d);
					return (IDENT, wd, nil);
				}
				val := lowercase(wd);
				if(val == "url")
					return (URL, url(cs), nil);	# bizarre special case
				return (FUNCTION, val, nil);
			}
			return (c, nil, nil);
		}

	}
}

skipws(cs: ref Clex): int
{
	for(;;){
		while((c := cs.getc()) == ' ' || c == '\t' || c == '\n'  || c == '\r' || c == '\f')
			;
		if(c != '/')
			return c;
		c = cs.getc();
		if(c != '*'){
			cs.ungetc(c);
			return '/';
		}
		comment(cs);
	}
}

seq(cs: ref Clex, s: string): int
{
	for(i := 0; i < len s; i++)
		if((c := cs.getc()) != s[i])
			break;
	if(i == len s)
		return 1;
	cs.ungetc(c);
	while(i > 0)
		cs.ungetc(s[--i]);
	if(c < 0)
		return -1;
	return 0;
}

subseq(cs: ref Clex, a: int, t: int, e: int): int
{
	if((c := cs.getc()) != a){
		cs.ungetc(c);
		return e;
	}
	return t;
}

pushback(cs: ref Clex, wd: string)
{
	for(i := len wd; --i >= 0;)
		cs.ungetc(wd[i]);
}

comment(cs: ref Clex)
{
	while((c := cs.getc()) != '*' || (c = cs.getc()) != '/')
		if(c < 0) {
			# end of file in comment
			break;
		}
}

number(cs: ref Clex, c: int): string
{
	s: string;
	for(; isdigit(c); c = cs.getc())
		s[len s] = c;
	if(c != '.'){
		cs.ungetc(c);
		return s;
	}
	if(!isdigit(c = cs.getc())){
		cs.ungetc(c);
		cs.ungetc('.');
		return s;
	}
	s[len s] = '.';
	do{
		s[len s] = c;
	}while(isdigit(c = cs.getc()));
	cs.ungetc(c);
	return s;
}

name(cs: ref Clex, c: int): string
{
	s: string;
	for(; isnamec(c, 1); c = cs.getc()){
		s[len s] = c;
		if(c == '\\'){
			c = cs.getc();
			if(isescapable(c))
				s[len s] = c;
		}
	}
	cs.ungetc(c);
	return s;
}

isescapable(c: int): int
{
	return c >= ' ' && c <= '~' || isnamec(c, 1);
}

islatin1(c: int): int
{
	return c >= 16rA1 && c <= 16rFF;	# printable latin-1
}

isnamec(c: int, notfirst: int): int
{
	return c >= 'A' && c <= 'Z' || c >= 'a' && c <= 'z' || c == '\\' ||
		notfirst && (c >= '0' && c <= '9' || c == '-') ||
		c >= 16rA1 && c <= 16rFF;	# printable latin-1
}

isxdigit(c: int): int
{
	return c>='0' && c<='9' || c>='a'&&c<='f' || c>='A'&&c<='F';
}

isdigit(c: int): int
{
	return c >= '0' && c <= '9';
}

isspace(c: int): int
{
	return c == ' ' || c == '\t' || c == '\n' || c == '\r' || c == '\f';
}

hex(c: int): int
{
	if(c >= '0' && c <= '9')
		return c-'0';
	if(c >= 'A' && c <= 'F')
		return c-'A' + 10;
	if(c >= 'a' && c <= 'f')
		return c-'a' + 10;
	return -1;
}

quotedstring(cs: ref Clex, delim: int): string
{
	s: string;
	while((c := cs.getc()) != delim){
		if(c < 0){
			cs.synerr("end-of-file in string");
			return s;
		}
		if(c == '\\'){
			c = cs.getc();
			if(c < 0){
				cs.synerr("end-of-file in string");
				return s;
			}
			if(isxdigit(c)){
				# unicode escape
				n := 0;
				for(i := 0;;){
					n = (n<<4) | hex(c);
					c = cs.getc();
					if(!isxdigit(c) || ++i >= 6){
						if(!isspace(c))
							cs.ungetc(c);	# CSS2 ignores the first white space following
						break;
					}
				}
				s[len s] = n;
			}else if(c == '\n'){
				;	# escaped newline
			}else if(isescapable(c))
				s[len s] = c;
		}else if(c)
			s[len s] = c;
	}
	return s;
}

url(cs: ref Clex): string
{
	s: string;
	c := skipws(cs);
	if(c != '"' && c != '\''){	# not a quoted string
		while(c != ' ' && c != '\n' && c != '\'' && c != '"' && c != ')'){
			s[len s] = c;
			c = cs.getc();
			if(c == '\\'){
				c = cs.getc();
				if(c < 0){
					cs.synerr("end of file in url parameter");
					break;
				}
				if(c == ' ' || c == '\'' || c == '"' || c == ')')
					s[len s] = c;
				else{
					cs.synerr("invalid escape sequence in url");
					s[len s] = '\\';
					s[len s] = c;
				}
				c = cs.getc();
			}
		}
		cs.ungetc(c);
#		if(s == nil)
#			p.synerr("empty parameter to url");
	}else
		s = quotedstring(cs, c);
	if((c = skipws(cs)) != ')'){
		cs.synerr("unclosed parameter to url");
		cs.ungetc(c);
	}
	return s;
}

lowercase(s: string): string
{
	for(i := 0; i < len s; i++)
		if((c := s[i]) >= 'A' && c <= 'Z')
			s[i] = c-'A' + 'a';
	return s;
}
