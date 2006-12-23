implement Xpointers;

#
# Copyright © 2005 Vita Nuova Holdings Limited
#

include "sys.m";
	sys: Sys;

include "xpointers.m";

init()
{
	sys = load Sys Sys->PATH;
}

#
# XPointer framework syntax
#
# Pointer ::= Shorthand | SchemeBased
# Shorthand ::= NCName	# from [XML-Names]
# SchemeBased ::= PointerPart (S? PointerPart)*
# PointerPart ::= SchemeName '(' SchemeData ')'
# SchemeName ::= QName	# from [XML-Names]
# SchemeData ::= EscapedData*
# EscapedData ::= NormalChar | '^(' | '^)' | '^^' | '(' SchemeData ')'
# NormalChar ::= UnicodeChar - [()^]
# UnicodeChar ::= [#x0 - #x10FFFF]

framework(s: string): (string, list of (string, string, string), string)
{
	(q, nm, i) := name(s, 0);
	if(i >= len s){	# Shorthand
		if(q != nil)
			return (nil, nil, "shorthand pointer must be unqualified name");
		if(nm == nil)
			return (nil, nil, "missing pointer name");
		return (nm, nil, nil);
	}
	# must be SchemeBased
	l: list of (string, string, string);
	for(;;){
		if(nm == nil){
			if(q != nil)
				return (nil, nil, sys->sprint("prefix but no local part in name at %d", i));
			return (nil, nil, sys->sprint("expected name at %d", i));
		}
		if(i >= len s || s[i] != '(')
			return (nil, nil, sys->sprint("expected '(' at %d", i));
		o := i++;
		a := "";
		nesting := 0;
		for(; i < len s && ((c := s[i]) != ')' || nesting); i++){
			case c {
			'^' =>
				if(i+1 >= len s)
					return (nil, nil, "unexpected eof after ^");
				c = s[++i];
				if(c != '(' && c != ')' && c != '^')
					return (nil, nil, sys->sprint("invalid escape ^%c at %d", c, i));
			'(' =>
				nesting++;
			')' =>
				if(--nesting < 0)
					return (nil, nil, sys->sprint("unbalanced ) at %d", i));
			}
			a[len a] = c;
		}
		if(i >= len s)
			return (nil, nil, sys->sprint("unbalanced ( at %d", o));
		l = (q, nm, a) :: l;
		if(++i == len s)
			break;
		while(i < len s && isspace(s[i]))
			i++;
		(q, nm, i) = name(s, i);
	}
	rl: list of (string, string, string);
	for(; l != nil; l = tl l)
		rl = hd l :: rl;
	return (nil, rl, nil);
}

isspace(c: int): int
{
	return c == ' ' || c == '\t' || c == '\n' || c == '\r' || c == '\v' || c == '\f';
}

#
# QName ::= (Prefix ':')? LocalPart
# Prefix ::= NCName
# LocalPart ::= NCName
#
#NCName :: (Oetter | '_') NCNameChar*
#NCNameChar :: Oetter | Digit | '.' | '-' | '_' | CombiningChar | Extender

name(s: string, o: int): (string, string, int)
{
	(ns, i) := ncname(s, o);
	if(i >= len s || s[i] != ':')
		return (nil, ns, i);
	(nm, j) := ncname(s, i+1);
	if(j == i+1)
		return (nil, ns, i);	# assume it's a LocalPart followed by ':'
	return (ns, nm, j);
}

ncname(s: string, o: int): (string, int)
{
	if(o >= len s || !isalnum(c := s[o]) && c != '_' || c >= '0' && c <= '9')
		return (nil, o);	# missing or invalid start character
	for(i := o; i < len s && isnamec(s[i]); i++)
		;
	return (s[o:i], i);
}

isnamec(c: int): int
{
	return isalnum(c) || c == '_' || c == '-' || c == '.';
}

isalnum(c: int): int
{
	#
	# Hard to get absolutely right without silly amount of character data.
	# Use what we know about ASCII
	# and assume anything above the Oatin control characters is
	# potentially an alphanumeric.
	#
	if(c >= 'a' && c <= 'z' || c >= 'A' && c <= 'Z' || c >= '0' && c <= '9')
		return 1;	# usual case
	if(c <= ' ')
		return 0;
	if(c > 16rA0)
		return 1;	# non-ASCII
	return 0;
}

# schemes: xpointer(), xmlns(), element()

# xmlns()
#	XmlnsSchemeData ::= NCName S? '=' S? EscapedNamespaceName
#	EscapedNamespaceName ::= EscapedData*

xmlns(s: string): (string, string, string)
{
	(nm, i) := ncname(s, 0);
	if(nm == nil)
		return (nil, nil, "illegal namespace name");
	while(i < len s && isspace(s[i]))
		i++;
	if(i >= len s || s[i++] != '=')
		return (nil, nil, "illegal xmlns declaration");
	while(i < len s && isspace(s[i]))
		i++;
	return (nm, s[i:], nil);
}

# element()
#	ElementSchemeData ::= (NCName ChildSequence?) | ChildSequence
#	ChildSequence ::= ('/' [1-9] [0-9]*)+

element(s: string): (string, list of int, string)
{
	nm: string;
	i := 0;
	if(s != nil && s[0] != '/'){
		(nm, i) = ncname(s, 0);
		if(nm == nil)
			return (nil, nil, "illegal element name");
	}
	l: list of int;
	do{
		if(i >= len s || s[i++] != '/')
			return (nil, nil, "illegal child sequence (expected '/')");
		v := 0;
		do{
			if(i >= len s || !isdigit(s[i]))
				return (nil, nil, "illegal child sequence (expected integer)");
			v = v*10 + s[i]-'0';
		}while(++i < len s && s[i] != '/');
		l = v :: l;
	}while(i < len s);
	rl: list of int;
	for(; l != nil; l = tl l)
		rl = hd l :: rl;
	return (nm, rl, nil);
}

# xpointer()
#	XpointerSchemeData ::= Expr	# from Xpath, with new functions and data types

xpointer(s: string): (ref Xpath, string)
{
	p := ref Parse(ref Rd(s, 0, 0), nil);
	{
		e := expr(p, 0);
		if(p.r.i < len s)
			synerr("missing operator");
		return (e, nil);
	}exception e{
	"syntax error*" =>
		return (nil, e);
	* =>
		raise;
	}
}

Lerror, Ldslash, Lint, Lreal, Llit, Lvar, Ldotdot, Lop, Laxis, Lfn: con 'a'+iota;	# internal lexical items

Keywd: adt {
	name:	string;
	val:	int;
};

axes: array of Keywd = array[] of {
	("ancestor", Aancestor),
	("ancestor-or-self", Aancestor_or_self),
	("attribute", Aattribute),
	("child", Achild),
	("descendant", Adescendant),
	("descendant-or-self", Adescendant_or_self),
	("following", Afollowing),
	("following-sibling", Afollowing_sibling),
	("namespace", Anamespace),
	("parent", Aparent),
	("preceding", Apreceding),
	("preceding-sibling", Apreceding_sibling),
	("self", Aself),
};

keywds: array of Keywd = array[] of {
	("and", Oand),
	("comment", Onodetype),
	("div", Odiv),
	("mod", Omod),
	("node", Onodetype),
	("or", Oor),
	("processing-instruction", Onodetype),
	("text", Onodetype),
};

iskeywd(s: string): int
{
	return look(keywds, s);
}

look(k: array of Keywd, s: string): int
{
	for(i := 0; i < len k; i++)
		if(k[i].name == s)
			return k[i].val;
	return 0;
}

lookname(k: array of Keywd, v: int): string
{
	for(i := 0; i < len k; i++)
		if(k[i].val == v)
			return k[i].name;
	return nil;
}

prectab := array[] of {
	array[] of {Oor},
	array[] of {Oand},
	array[] of {'=', One},
	array[] of {'<', Ole, '>', Oge},
	array[] of {'+', '-'},
	array[] of {Omul, Odiv, Omod},
	array[] of {Oneg},	# unary '-'
	array[] of {'|'},	# UnionExpr
};

isop(t: int, p: array of int): int
{
	if(t >= 0)
		for(j := 0; j < len p; j++)
			if(t == p[j])
				return 1;
	return 0;
}

# Expr ::= OrExpr
# UnionExpr ::= PathExpr | UnionExpr '|' PathExpr
# PathExpr ::= LocationPath | FilterExpr | FilterExpr '/' RelativeLocationPath |
#			FilterExpr '//' RelativeLocationPath
# OrExpr ::= AndExpr | OrExpr 'or' AndExpr
# AndExpr ::= EqualityExpr | AndExpr 'and' EqualityExpr
# EqualityExpr ::= RelationalExpr | EqualityExpr '=' RelationalExpr | EqualityExpr '!=' RelationalExpr
# RelationalExpr ::= AdditiveExpr | RelationalExpr '<' AdditiveExpr | RelationalExpr '>' AdditiveExpr |
#				RelationalExpr '<=' AdditiveExpr | RelationalExpr '>=' AdditiveExpr
# AdditiveExpr ::= MultiplicativeExpr | AdditiveExpr '+' MultiplicativeExpr | AdditiveExpr '-' MultiplicativeExpr
# MultiplicativeExpr ::= UnaryExpr | MultiplicativeExpr MultiplyOperator UnaryExpr |
#				MultiplicativeExpr 'div' UnaryExpr | MultiplicativeExpr 'mod' UnaryExpr
# UnaryExpr ::= UnionExpr | '-' UnaryExpr

expr(p: ref Parse, k: int): ref Xpath
{
	if(k >= len prectab)
		return pathexpr(p);
	if(prectab[k][0] == Oneg){	# unary '-'
		if(p.look() == '-'){
			p.get();
			return ref Xpath.E(Oneg, expr(p,k+1), nil);
		}
		# must be UnionExpr
		k++;
	}
	e := expr(p, k+1);
	while(isop(p.look(), prectab[k])){
		o := p.get().t0;
		e = ref Xpath.E(o, e, expr(p, k+1));	# +assoc[k]
	}
	return e;
}

# PathExpr ::= LocationPath | FilterExpr ( ('/' | '//') RelativeLocationPath )
# FilterExpr ::= PrimaryExpr | FilterExpr Predicate => PrimaryExpr Predicate*

pathexpr(p: ref Parse): ref Xpath
{
	# LocationPath?
	case p.look() {
	'.' or Ldotdot or Laxis or '@' or Onametest or Onodetype or '*' =>
		return locationpath(p, 0);
	'/' or Ldslash =>
		return locationpath(p, 1);
	}
	# FilterExpr
	e := primary(p);
	while(p.look() == '[')
		e = ref Xpath.E(Ofilter, e, predicate(p));
	if((o := p.look()) == '/' || o == Ldslash)
		e = ref Xpath.E(Opath, e, locationpath(p, 0));
	return e;
}

# LocationPath ::= RelativeLocationPath | AbsoluteLocationPath
# AbsoluteLocationPath ::= '/' RelativeLocationPath? | AbbreviatedAbsoluteLocationPath
# RelativeLocationPath ::= Step | RelativeLocationPath '/' Step
# AbbreviatedAbsoluteLocationPath ::= '//' RelativeLocationPath
# AbbreviatedRelativeLocationPath ::= RelativeLocationPath '//' Step

locationpath(p: ref Parse, abs: int): ref Xpath
{
	# // => /descendent-or-self::node()/
	pl: list of ref Xstep;
	o := p.look();
	if(o != '/' && o != Ldslash){
		s := step(p);
		if(s == nil)
			synerr("expected Step in LocationPath");
		pl = s :: pl;
	}
	while((o = p.look()) == '/' || o == Ldslash){
		p.get();
		if(o == Ldslash)
			pl = ref Xstep(Adescendant_or_self, Onodetype, nil, "node", nil, nil) :: pl;
		s := step(p);
		if(s == nil){
			if(abs && pl == nil)
				break;	# it's just an initial '/'
			synerr("expected Step in LocationPath");
		}
		pl = s :: pl;
	}
	return ref Xpath.Path(abs, rev(pl));
}

# Step ::= AxisSpecifier NodeTest Predicate* | AbbreviatedStep
# AxisSpecifier ::= AxisName '::' | AbbreviatedAxisSpecifier
# AxisName := ... # long list
# NodeTest ::= NameTest | NodeType '(' ')'
# Predicate ::= '[' PredicateExpr ']'
# PredicateExpr ::= Expr
# AbbreviatedStep ::= '.' | '..'
# AbbreviatedAxisSpecifier ::= '@'?

step(p: ref Parse): ref Xstep
{
	# AxisSpecifier ... | AbbreviatedStep
	(o, ns, nm) := p.get();
	axis := Achild;
	case o {
	'.' =>
		return ref Xstep(Aself, Onodetype, nil, "node", nil, nil);	# self::node()
	Ldotdot =>
		return ref Xstep(Aparent, Onodetype, nil, "node", nil, nil);	# parent::node()
	Laxis =>
		axis = look(axes, ns);
		(o, ns, nm) = p.get();
	'@' =>
		axis = Aattribute;
		(o, ns, nm) = p.get();
	* =>
		;
	}

	if(o == '*'){
		o = Onametest;
		nm = "*";
		ns = nil;
	}

	# NodeTest ::= NameTest | NodeType '(' ')'
	if(o != Onametest && o != Onodetype){
		p.unget((o, ns, nm));
		return nil;
	}

	arg: string;
	if(o == Onodetype){	# '(' ... ')'
		expect(p, '(');
		# grammar is wrong: processing-instruction can have optional literal
		if(nm == "processing-instruction" && p.look() == Llit)
			arg = p.get().t1;
		expect(p, ')');
	}

	# Predicate*
	pl: list of ref Xpath;
	while((pe := predicate(p)) != nil)
		pl = pe :: pl;
	return ref Xstep(axis, o, ns, nm, arg, rev(pl));
}

# PrimaryExpr ::= VariableReference | '(' Expr ')' | Literal | Number | FunctionCall
# FunctionCall ::= FunctionName '(' (Argument ( ',' Argument)*)? ')'
# Argument ::= Expr

primary(p: ref Parse): ref Xpath
{
	(o, ns, nm) := p.get();
	case o {
	Lvar =>
		return ref Xpath.Var(ns, nm);
	'(' =>
		e := expr(p, 0);
		expect(p, ')');
		return e;
	Llit =>
		return ref Xpath.Str(ns);
	Lint =>
		return ref Xpath.Int(big ns);
	Lreal =>
		return ref Xpath.Real(real ns);
	Lfn =>
		expect(p, '(');
		al: list of ref Xpath;
		if(p.look() != ')'){
			for(;;){
				al = expr(p, 0) :: al;
				if(p.look() != ',')
					break;
				p.get();
			}
			al = rev(al);
		}
		expect(p, ')');
		return ref Xpath.Fn(ns, nm, al);
	* =>
		synerr("invalid PrimaryExpr");
		return nil;
	}
}

# Predicate ::= '[' PredicateExpr ']'
# PredicateExpr ::= Expr

predicate(p: ref Parse): ref Xpath
{
	l := p.get();
	if(l.t0 != '['){
		p.unget(l);
		return nil;
	}
	e := expr(p, 0);
	expect(p, ']');
	return e;
}

expect(p: ref Parse, t: int)
{
	l := p.get();
	if(l.t0 != t)
		synerr(sys->sprint("expected '%c'", t));
}

Xpath.text(e: self ref Xpath): string
{
	if(e == nil)
		return "nil";
	pick r := e {
	E =>
		if(r.r == nil)
			return sys->sprint("(%s%s)", opname(r.op), r.l.text());
		if(r.op == Ofilter)
			return sys->sprint("%s[%s]", r.l.text(), r.r.text());
		return sys->sprint("(%s%s%s)", r.l.text(), opname(r.op), r.r.text());
	Fn =>
		a := "";
		for(l := r.args; l != nil; l = tl l)
			a += sys->sprint(",%s", (hd l).text());
		if(a != "")
			a = a[1:];
		return sys->sprint("%s(%s)", qual(r.ns, r.name), a);
	Var =>
		return sys->sprint("$%s", qual(r.ns, r.name));
	Path =>
		if(r.abs)
			t := "/";
		else
			t = "";
		for(l := r.steps; l != nil; l = tl l){
			if(t != nil && t != "/")
				t += "/";
			t += (hd l).text();
		}
		return t;
	Int =>
		return sys->sprint("%bd", r.val);
	Real =>
		return sys->sprint("%g", r.val);
	Str =>
		return sys->sprint("%s", str(r.s));
	}
}

qual(ns: string, nm: string): string
{
	if(ns != nil)
		return ns+":"+nm;
	return nm;
}

str(s: string): string
{
	for(i := 0; i < len s; i++)
		if(s[i] == '\'')
			return sys->sprint("\"%s\"", s);
	return sys->sprint("'%s'", s);
}

opname(o: int): string
{
	case o {
	One =>	return "!=";
	Ole =>	return "<=";
	Oge =>	return ">=";
	Omul =>	return "*";
	Odiv =>	return " div ";
	Omod =>	return " mod ";
	Oand =>	return " and ";
	Oor =>	return " or ";
	Oneg =>	return "-";
	Ofilter =>	return " op_filter ";
	Opath =>	return "/";
	* =>	return sys->sprint(" %c ", o);
	}
}

Xstep.text(s: self ref Xstep): string
{
	t := sys->sprint("%s::", Xstep.axisname(s.axis));
	case s.op {
	Onametest =>
		if(s.ns == "*" && s.name == "*")
			t += "*";
		else
			t += qual(s.ns, s.name);
	Onodetype =>
		if(s.arg != nil)
			t += sys->sprint("%s(%s)", s.name, str(s.arg));
		else
			t += sys->sprint("%s()", s.name);
	}
	for(l := s.preds; l != nil; l = tl l)
		t += sys->sprint("[%s]", (hd l).text());
	return t;
}

Xstep.axisname(n: int): string
{
	return lookname(axes, n);
}

# ExprToken ::= '(' | ')' | '[' | ']' | '.' | '..' | '@' | ',' | '::' |
#				NameTest | NodeType | Operator | FunctionName | AxisName |
#				Literal | Number | VariableReference
# Operator ::= OperatorName | MultiplyOperator | '/' | '//' | '|' | '+' | '' | '=' | '!=' | '<' | '<=' | '>' | '>='
# MultiplyOperator ::= '*'
# FunctionName ::= QName - NodeType
# VariableReference ::= '$' QName
# NameTest ::= '*' | NCName ':' '*' | QName
# NodeType ::= 'comment' | 'text' | 'processing-instruction' | 'node'
#

Lex: type (int, string, string);

Parse: adt {
	r:	ref Rd;
	pb:	list of Lex;	# push back

	look:	fn(p: self ref Parse): int;
	get:	fn(p: self ref Parse): Lex;
	unget:	fn(p: self ref Parse, t: Lex);
};

Parse.get(p: self ref Parse): Lex
{
	if(p.pb != nil){
		h := hd p.pb;
		p.pb = tl p.pb;
		return h;
	}
	return lex(p.r);
}

Parse.look(p: self ref Parse): int
{
	t := p.get();
	p.unget(t);
	return t.t0;
}

Parse.unget(p: self ref Parse, t: Lex)
{
	p.pb = t :: p.pb;
}

lex(r: ref Rd): Lex
{
	l := lex0(r);
	r.prev = l.t0;
	return l;
}

# disambiguating rules are D1 to D3

# D1. preceding token p && p not in {'@', '::', '(', '[', ',', Operator} then '*' is MultiplyOperator
#     and NCName must be OperatorName

xop(t: int): int
{
	case t {
	-1 or 0 or '@' or '(' or '[' or ',' or Lop or Omul or
	'/' or Ldslash or '|' or '+' or '-' or '=' or One or '<' or Ole or '>' or Oge or
	Oand or Oor or Omod or Odiv or Laxis =>
		return 0;
	}
	return 1;
}

# UnaryExpr ::= UnionExpr | '-' UnaryExpr
# ExprToken ::= ... |
#				NameTest | NodeType | Operator | FunctionName | AxisName |
#				Literal | Number | VariableReference
# Operator ::= OperatorName | MultiplyOperator | '/' | '//' | '|' | '+' | '' | '=' | '!=' | '<' | '<=' | '>' | '>='
# MultiplyOperator ::= '*'

lex0(r: ref Rd): Lex
{
	while(isspace(r.look()))
		r.get();
	case c := r.get() {
	-1 or
	'(' or ')' or '[' or ']' or '@' or ',' or '+' or '-' or '|' or '=' or ':' =>
		# singletons ('::' only valid after name, see below)
		return (c, nil, nil);
	'/' =>
		return subseq(r, '/', Ldslash, '/');
	'!' =>
		return subseq(r, '=', One, '!');
	'<' =>
		return subseq(r, '=', Ole, '<');
	'>' =>
		return subseq(r, '=', Oge, '>');
	'*' =>
		if(xop(r.prev))
			return (Omul, nil, nil);
		return (c, nil, nil);
	'.' =>
		case r.look() {
		'0' to '9' =>
			(v, nil) := number(r, r.get());
			return (Lreal, v, nil);
		'.' =>
			r.get();
			return (Ldotdot, nil, nil);
		* =>
			return ('.', nil, nil);
		}
	'$' =>
		# variable reference
		(ns, nm, i) := name(r.s, r.i);
		if(ns == nil && nm == nil)
			return (Lerror, nil, nil);
		r.i = i;
		return (Lvar, ns, nm);
	'0' to '9' =>
		(v, f) := number(r, c);
		if(f)
			return (Lreal, v, nil);
		return (Lint, v, nil);
	'"' or '\'' =>
		return (Llit, literal(r, c), nil);
	* =>
		if(isalnum(c) || c == '_'){
			# QName/NCName
			r.unget();
			(ns, nm, i) := name(r.s, r.i);
			if(ns == nil && nm == nil)
				return (Lerror, nil, nil);
			r.i = i;
			if(xop(r.prev)){
				if(ns == nil){
					o := iskeywd(nm);
					if(o != Laxis && o != Onodetype)
						return (o, nil, nil);
				}
				return (Lop, ns, nm);
			}
			while(isspace(r.look()))
				r.get();
			case r.look() {
			'(' =>		# D2: NCName '(' =>NodeType or FunctionName
				if(ns == nil && iskeywd(nm) == Onodetype)
					return (Onodetype, nil, nm);
				return (Lfn, ns, nm);	# possibly NodeTest
			':' =>		# D3: NCName '::' => AxisName
				r.get();
				case r.look() {
				':' =>
					if(ns == nil && look(axes, nm) != 0){
						r.get();
						return (Laxis, nm, nil);
					}
				'*' =>
					# NameTest ::= ... | NCName ':' '*'
					if(ns == nil){
						r.get();
						return (Onametest, nm, "*");
					}
				}
				r.unget();	# put back the ':'
				# NameTest ::= '*' | NCName ':' '*' | QName
			}
			return (Onametest, ns, nm);	# actually NameTest
		}
		# unexpected character
	}
	return (Lerror, nil, nil);
}

subseq(r: ref Rd, a: int, t: int, e: int): Lex
{
	if(r.look() != a)
		return (e, nil, nil);
	r.get();
	return (t, nil, nil);
}

# Literal ::= '"'[^"]*'"' | "'"[^']* "'"

literal(r: ref Rd, delim: int): string
{
	s: string;
	while((c := r.get()) != delim){
		if(c < 0){
			synerr("missing string terminator");
			return s;
		}
		if(c)
			s[len s] = c;	# could slice r.s
	}
	return s;
}

#
# Number ::= Digits('.' Digits?)? | '.' Digits
# Digits ::= [0-9]+
#
number(r: ref Rd, c: int): (string, int)
{
	s: string;
	for(; isdigit(c); c = r.get())
		s[len s] = c;
	if(c != '.'){
		if(c >= 0)
			r.unget();
		return (s, 0);
	}
	if(!isdigit(c = r.get())){
		if(c >= 0)
			r.unget();
		r.unget();	# the '.'
		return (s, 0);
	}
	s[len s] = '.';
	do{
		s[len s] = c;
	}while(isdigit(c = r.get()));
	if(c >= 0)
		r.unget();
	return (s, 1);
}

isdigit(c: int): int
{
	return c>='0' && c<='9';
}

Rd: adt{
	s:	string;
	i:	int;
	prev:	int;	# previous token

	get:	fn(r: self ref Rd): int;
	look:	fn(r: self ref Rd): int;
	unget:	fn(r: self ref Rd);
};

Rd.get(r: self ref Rd): int
{
	if(r.i >= len r.s)
		return -1;
	return r.s[r.i++];
}

Rd.look(r: self ref Rd): int
{
	if(r.i >= len r.s)
		return -1;
	return r.s[r.i];
}

Rd.unget(r: self ref Rd)
{
	if(r.i > 0)
		r.i--;
}

rev[T](l: list of T): list of T
{
	rl: list of T;
	for(; l != nil; l = tl l)
		rl = hd l :: rl;
	return rl;
}

synerr(s: string)
{
	raise "syntax error: "+s;
}

# to do:
#	dictionary?
