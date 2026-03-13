implement Awk;

#
# awk - pattern-directed scanning and processing language
# Plan 9 / Inferno port (BWK awk heritage)
#

include "sys.m";
	sys: Sys;

include "draw.m";

include "bufio.m";
	bufio: Bufio;
	Iobuf: import bufio;

include "arg.m";
	arg: Arg;

include "string.m";
	str: String;

include "regex.m";
	regex: Regex;

include "math.m";
	math: Math;

include "rand.m";
	randmod: Rand;

Awk: module
{
	init:	fn(nil: ref Draw->Context, nil: list of string);
};

# Token types
TNONE, TEOF, TNUMBER, TSTRING, TREGEX, TIDENT, TFUNC: con iota;
TLPAREN, TRPAREN, TLBRACE, TRBRACE, TLBRACKET, TRBRACKET: con 100 + iota;
TSEMICOLON, TCOMMA, TNEWLINE: con 110 + iota;
TPLUS, TMINUS, TSTAR, TSLASH, TPERCENT, TCARET: con 120 + iota;
TASSIGN, TADDASSIGN, TSUBASSIGN, TMULASSIGN, TDIVASSIGN, TMODASSIGN: con 130 + iota;
TEQ, TNE, TLT, TLE, TGT, TGE: con 140 + iota;
TAND, TOR, TNOT, TMATCH, TNOTMATCH: con 150 + iota;
TINCR, TDECR: con 160 + iota;
TDOLLAR, TIN, TPIPE, TAPPEND: con 170 + iota;
TCONCAT, TQMARK, TCOLON: con 180 + iota;
TPOWASSIGN: con 190;
# Keywords
TBEGIN, TEND, TIF, TELSE, TWHILE, TFOR, TDO: con 200 + iota;
TBREAK, TCONTINUE, TNEXT, TEXIT, TRETURN, TDELETE: con 210 + iota;
TPRINT, TPRINTF, TGETLINE, TFUNCTION: con 220 + iota;

# Value flags
VNUM: con 1;
VSTR: con 2;

Val: adt {
	num:	real;
	s:	string;
	flags:	int;
};

# Symbol table entry
Sym: adt {
	name:	string;
	val:	ref Val;
	arr:	ref Assoc;
};

# Associative array
Assoc: adt {
	items:	list of (string, ref Val);

	get:	fn(a: self ref Assoc, key: string): ref Val;
	set:	fn(a: self ref Assoc, key: string, v: ref Val);
	del:	fn(a: self ref Assoc, key: string);
	keys:	fn(a: self ref Assoc): list of string;
};

# AST node
Node: adt {
	pick {
	Num	=> val: real;
	Str	=> val: string;
	Regex	=> re: Regex->Re; pat: string;
	Ident	=> name: string;
	Field	=> expr: cyclic ref Node;
	Unary	=> op: int; operand: cyclic ref Node; post: int;
	Binary	=> op: int; left, right: cyclic ref Node;
	Assign	=> op: int; dst, src: cyclic ref Node;
	In	=> var: string; arr: string;
	Match	=> expr: cyclic ref Node; re: Regex->Re; pat: string; neg: int;
	Index	=> arr: string; idx: cyclic ref Node;
	Call	=> name: string; args: cyclic list of ref Node;
	Print	=> args: cyclic list of ref Node; dst: cyclic ref Node; append: int; format: int;
	If	=> cond, tbody, fbody: cyclic ref Node;
	While	=> cond, body: cyclic ref Node;
	DoWhile	=> body, cond: cyclic ref Node;
	For	=> init, cond, incr, body: cyclic ref Node;
	ForIn	=> var: string; arr: string; body: cyclic ref Node;
	Block	=> stmts: cyclic list of ref Node;
	Return	=> val: cyclic ref Node;
	Delete	=> arr: string; idx: cyclic ref Node;
	Next	=> ;
	Exit	=> val: cyclic ref Node;
	Getline	=> var: cyclic ref Node; src: cyclic ref Node; cmd: int;
	Cond	=> cond, texpr, fexpr: cyclic ref Node;
	}
};

# Pattern-action rule
Rule: adt {
	begin:	int;
	end:	int;
	pat:	ref Node;
	pat2:	ref Node;
	action:	ref Node;
	inrange:	int;
};

# User-defined function
Func: adt {
	name:	string;
	params:	list of string;
	body:	ref Node;
};

# Lexer state
Lex: adt {
	src:	string;
	pos:	int;
	tok:	int;
	numval:	real;
	strval:	string;
	prevnl:	int;	# was previous token a newline

	init:	fn(l: self ref Lex, s: string);
	next:	fn(l: self ref Lex): int;
	peek:	fn(l: self ref Lex): int;
};

# Globals
stderr: ref Sys->FD;
safe := 0;
rules: list of ref Rule;
funcs: list of ref Func;
symtab: list of ref Sym;
fields: array of string;
nfields := 0;
reclength := 0;
openfiles: list of (string, ref Iobuf);

# Built-in variable names
fs_var := " ";
rs_var := "\n";
ofs_var := " ";
ors_var := "\n";
ofmt_var := "%.6g";
subsep_var := "\034";
nr_var := 0;
fnr_var := 0;
filename_var := "";
rstart_var := 0;
rlength_var := -1;
randseed := 0;

usage()
{
	sys->fprint(stderr, "usage: awk [-F fs] [-v var=val] [-f progfile] [-safe] ['prog'] [file ...]\n");
	raise "fail:usage";
}

fatal(s: string)
{
	sys->fprint(stderr, "awk: %s\n", s);
	raise "fail:error";
}

# ========== Associative array methods ==========

Assoc.get(a: self ref Assoc, key: string): ref Val
{
	for(l := a.items; l != nil; l = tl l) {
		(k, v) := hd l;
		if(k == key)
			return v;
	}
	return nil;
}

Assoc.set(a: self ref Assoc, key: string, v: ref Val)
{
	nl: list of (string, ref Val);
	found := 0;
	for(l := a.items; l != nil; l = tl l) {
		(k, ov) := hd l;
		if(k == key) {
			nl = (k, v) :: nl;
			found = 1;
		} else
			nl = (k, ov) :: nl;
	}
	if(!found)
		nl = (key, v) :: nl;
	a.items = nl;
}

Assoc.del(a: self ref Assoc, key: string)
{
	nl: list of (string, ref Val);
	for(l := a.items; l != nil; l = tl l) {
		(k, v) := hd l;
		if(k != key)
			nl = (k, v) :: nl;
	}
	a.items = nl;
}

Assoc.keys(a: self ref Assoc): list of string
{
	kl: list of string;
	for(l := a.items; l != nil; l = tl l) {
		(k, nil) := hd l;
		kl = k :: kl;
	}
	return kl;
}

# ========== Value operations ==========

mknum(n: real): ref Val
{
	return ref Val(n, nil, VNUM);
}

mkstr(s: string): ref Val
{
	return ref Val(0.0, s, VSTR);
}

mknumstr(n: real, s: string): ref Val
{
	return ref Val(n, s, VNUM|VSTR);
}

numval(v: ref Val): real
{
	if(v == nil)
		return 0.0;
	if(v.flags & VNUM)
		return v.num;
	if(v.flags & VSTR) {
		(n, nil) := str->toint(v.s, 10);
		# try as real if int conversion gets 0 and string isn't "0"
		if(n == 0 && v.s != "0" && v.s != "") {
			# simple real parse
			return real v.s;
		}
		return real n;
	}
	return 0.0;
}

strval(v: ref Val): string
{
	if(v == nil)
		return "";
	if(v.flags & VSTR)
		return v.s;
	if(v.flags & VNUM) {
		n := v.num;
		if(n == real int n)
			return string int n;
		return sys->sprint(ofmt_var, n);
	}
	return "";
}

boolval(v: ref Val): int
{
	if(v == nil)
		return 0;
	if(v.flags & VNUM)
		return v.num != 0.0;
	if(v.flags & VSTR)
		return v.s != "" && v.s != "0";
	return 0;
}

# ========== Symbol table ==========

getsym(name: string): ref Sym
{
	for(l := symtab; l != nil; l = tl l) {
		s := hd l;
		if(s.name == name)
			return s;
	}
	s := ref Sym(name, mknum(0.0), nil);
	symtab = s :: symtab;
	return s;
}

getvar(name: string): ref Val
{
	# built-in variables
	case name {
	"FS" => return mkstr(fs_var);
	"RS" => return mkstr(rs_var);
	"OFS" => return mkstr(ofs_var);
	"ORS" => return mkstr(ors_var);
	"OFMT" => return mkstr(ofmt_var);
	"NR" => return mknum(real nr_var);
	"FNR" => return mknum(real fnr_var);
	"NF" => return mknum(real nfields);
	"FILENAME" => return mkstr(filename_var);
	"RSTART" => return mknum(real rstart_var);
	"RLENGTH" => return mknum(real rlength_var);
	"SUBSEP" => return mkstr(subsep_var);
	}
	s := getsym(name);
	return s.val;
}

setvar(name: string, v: ref Val)
{
	case name {
	"FS" => fs_var = strval(v);
	"RS" => rs_var = strval(v);
	"OFS" => ofs_var = strval(v);
	"ORS" => ors_var = strval(v);
	"OFMT" => ofmt_var = strval(v);
	"NR" => nr_var = int numval(v);
	"FNR" => fnr_var = int numval(v);
	"NF" =>
		nf := int numval(v);
		if(nf < nfields) {
			nfields = nf;
			rebuildrecord();
		} else {
			while(nfields < nf) {
				growfields(nfields + 1);
				fields[nfields] = "";
				nfields++;
			}
			rebuildrecord();
		}
	"RSTART" => rstart_var = int numval(v);
	"RLENGTH" => rlength_var = int numval(v);
	"SUBSEP" => subsep_var = strval(v);
	* =>
		s := getsym(name);
		s.val = v;
	}
}

getarray(name: string): ref Assoc
{
	s := getsym(name);
	if(s.arr == nil)
		s.arr = ref Assoc(nil);
	return s.arr;
}

# ========== Field handling ==========

growfields(n: int)
{
	if(n >= len fields) {
		newf := array[n + 16] of string;
		for(i := 0; i < len fields; i++)
			newf[i] = fields[i];
		for(i = len fields; i < len newf; i++)
			newf[i] = "";
		fields = newf;
	}
}

splitrecord(rec: string)
{
	if(fs_var == " ") {
		# default: split on whitespace, skip leading/trailing
		(nfields, fl) := sys->tokenize(rec, " \t");
		growfields(nfields);
		i := 0;
		for(; fl != nil; fl = tl fl) {
			fields[i] = hd fl;
			i++;
		}
	} else if(len fs_var == 1) {
		# single-char delimiter, preserve empty fields
		delim := fs_var[0];
		nfields = 0;
		start := 0;
		for(i := 0; i <= len rec; i++) {
			if(i == len rec || rec[i] == delim) {
				growfields(nfields);
				fields[nfields] = rec[start:i];
				nfields++;
				start = i + 1;
			}
		}
	} else {
		# regex field separator
		(re, err) := regex->compile(fs_var, 0);
		if(re == nil) {
			# fallback to literal
			nfields = 0;
			start := 0;
			for(i := 0; i <= len rec; i++) {
				found := 0;
				if(i <= len rec - len fs_var) {
					found = 1;
					for(j := 0; j < len fs_var; j++) {
						if(rec[i+j] != fs_var[j]) {
							found = 0;
							break;
						}
					}
				}
				if(i == len rec || found) {
					growfields(nfields);
					fields[nfields] = rec[start:i];
					nfields++;
					if(found)
						start = i + len fs_var;
					else
						start = i + 1;
				}
			}
		} else {
			nfields = 0;
			s := rec;
			for(;;) {
				if(s == nil || len s == 0) {
					growfields(nfields);
					fields[nfields] = s;
					nfields++;
					break;
				}
				result := regex->execute(re, s);
				if(result == nil) {
					growfields(nfields);
					fields[nfields] = s;
					nfields++;
					break;
				}
				(ms, me) := result[0];
				if(ms == me && ms == 0) {
					# zero-length match at start, take one char
					growfields(nfields);
					fields[nfields] = s[0:1];
					nfields++;
					s = s[1:];
					continue;
				}
				growfields(nfields);
				fields[nfields] = s[:ms];
				nfields++;
				s = s[me:];
			}
		}
	}
}

rebuildrecord()
{
	rec := "";
	for(i := 0; i < nfields; i++) {
		if(i > 0)
			rec += ofs_var;
		rec += fields[i];
	}
	growfields(0);
	fields[0] = rec;	# not really; $0 is separate
	reclength = len rec;
}

getfield(n: int): string
{
	if(n == 0) {
		# rebuild $0
		rec := "";
		for(i := 0; i < nfields; i++) {
			if(i > 0)
				rec += ofs_var;
			rec += fields[i];
		}
		return rec;
	}
	if(n < 1 || n > nfields)
		return "";
	return fields[n-1];
}

setfield(n: int, s: string)
{
	if(n == 0) {
		# reassign $0, re-split
		splitrecord(s);
		return;
	}
	if(n < 1)
		return;
	while(n > nfields) {
		growfields(nfields);
		fields[nfields] = "";
		nfields++;
	}
	fields[n-1] = s;
}


# ========== Lexer ==========

isdigit(c: int): int { return c >= '0' && c <= '9'; }
isalpha(c: int): int { return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '_'; }
isalnum(c: int): int { return isdigit(c) || isalpha(c); }
isspace(c: int): int { return c == ' ' || c == '\t' || c == '\r'; }

Lex.init(l: self ref Lex, s: string)
{
	l.src = s;
	l.pos = 0;
	l.tok = TNONE;
	l.numval = 0.0;
	l.strval = "";
	l.prevnl = 1;
}

Lex.peek(l: self ref Lex): int
{
	if(l.pos >= len l.src)
		return -1;
	return l.src[l.pos];
}

Lex.next(l: self ref Lex): int
{
	# skip whitespace and comments
	for(;;) {
		if(l.pos >= len l.src) {
			l.tok = TEOF;
			return TEOF;
		}
		c := l.src[l.pos];
		if(c == ' ' || c == '\t' || c == '\r') {
			l.pos++;
			continue;
		}
		if(c == '#') {
			while(l.pos < len l.src && l.src[l.pos] != '\n')
				l.pos++;
			continue;
		}
		if(c == '\\' && l.pos+1 < len l.src && l.src[l.pos+1] == '\n') {
			l.pos += 2;	# line continuation
			continue;
		}
		break;
	}

	c := l.src[l.pos];

	# newline
	if(c == '\n') {
		l.pos++;
		l.tok = TNEWLINE;
		l.prevnl = 1;
		return TNEWLINE;
	}

	l.prevnl = 0;

	# number
	if(isdigit(c) || (c == '.' && l.pos+1 < len l.src && isdigit(l.src[l.pos+1]))) {
		start := l.pos;
		while(l.pos < len l.src && isdigit(l.src[l.pos]))
			l.pos++;
		if(l.pos < len l.src && l.src[l.pos] == '.') {
			l.pos++;
			while(l.pos < len l.src && isdigit(l.src[l.pos]))
				l.pos++;
		}
		if(l.pos < len l.src && (l.src[l.pos] == 'e' || l.src[l.pos] == 'E')) {
			l.pos++;
			if(l.pos < len l.src && (l.src[l.pos] == '+' || l.src[l.pos] == '-'))
				l.pos++;
			while(l.pos < len l.src && isdigit(l.src[l.pos]))
				l.pos++;
		}
		# hex
		if(l.pos == start+1 && l.src[start] == '0' && l.pos < len l.src && (l.src[l.pos] == 'x' || l.src[l.pos] == 'X')) {
			l.pos++;
			while(l.pos < len l.src && (isdigit(l.src[l.pos]) || (l.src[l.pos] >= 'a' && l.src[l.pos] <= 'f') || (l.src[l.pos] >= 'A' && l.src[l.pos] <= 'F')))
				l.pos++;
		}
		l.strval = l.src[start:l.pos];
		l.numval = real l.strval;
		l.tok = TNUMBER;
		return TNUMBER;
	}

	# string
	if(c == '"') {
		l.pos++;
		s := "";
		while(l.pos < len l.src && l.src[l.pos] != '"') {
			if(l.src[l.pos] == '\\' && l.pos+1 < len l.src) {
				l.pos++;
				case l.src[l.pos] {
				'n' => s[len s] = '\n';
				't' => s[len s] = '\t';
				'r' => s[len s] = '\r';
				'\\' => s += "\\";
				'"' => s += "\"";
				'/' => s += "/";
				'a' => s[len s] = '\a';
				'b' => s[len s] = '\b';
				* => s[len s] = l.src[l.pos];
				}
				l.pos++;
			} else {
				s[len s] = l.src[l.pos];
				l.pos++;
			}
		}
		if(l.pos < len l.src)
			l.pos++;	# skip closing quote
		l.strval = s;
		l.tok = TSTRING;
		return TSTRING;
	}

	# regex - only in pattern context
	if(c == '/' && canberegex(l)) {
		l.pos++;
		pat := "";
		while(l.pos < len l.src && l.src[l.pos] != '/') {
			if(l.src[l.pos] == '\\' && l.pos+1 < len l.src) {
				pat[len pat] = l.src[l.pos];
				l.pos++;
				pat[len pat] = l.src[l.pos];
				l.pos++;
			} else {
				pat[len pat] = l.src[l.pos];
				l.pos++;
			}
		}
		if(l.pos < len l.src)
			l.pos++;	# skip closing /
		l.strval = pat;
		l.tok = TREGEX;
		return TREGEX;
	}

	# identifier / keyword
	if(isalpha(c)) {
		start := l.pos;
		while(l.pos < len l.src && isalnum(l.src[l.pos]))
			l.pos++;
		l.strval = l.src[start:l.pos];
		case l.strval {
		"BEGIN" => l.tok = TBEGIN;
		"END" => l.tok = TEND;
		"if" => l.tok = TIF;
		"else" => l.tok = TELSE;
		"while" => l.tok = TWHILE;
		"for" => l.tok = TFOR;
		"do" => l.tok = TDO;
		"break" => l.tok = TBREAK;
		"continue" => l.tok = TCONTINUE;
		"next" => l.tok = TNEXT;
		"exit" => l.tok = TEXIT;
		"return" => l.tok = TRETURN;
		"delete" => l.tok = TDELETE;
		"print" => l.tok = TPRINT;
		"printf" => l.tok = TPRINTF;
		"getline" => l.tok = TGETLINE;
		"function" => l.tok = TFUNCTION;
		"in" => l.tok = TIN;
		* => l.tok = TIDENT;
		}
		return l.tok;
	}

	# operators
	l.pos++;
	case c {
	'(' => l.tok = TLPAREN;
	')' => l.tok = TRPAREN;
	'{' => l.tok = TLBRACE;
	'}' => l.tok = TRBRACE;
	'[' => l.tok = TLBRACKET;
	']' => l.tok = TRBRACKET;
	';' => l.tok = TSEMICOLON;
	',' => l.tok = TCOMMA;
	'$' => l.tok = TDOLLAR;
	'?' => l.tok = TQMARK;
	':' => l.tok = TCOLON;
	'+' =>
		if(l.pos < len l.src && l.src[l.pos] == '+') { l.pos++; l.tok = TINCR; }
		else if(l.pos < len l.src && l.src[l.pos] == '=') { l.pos++; l.tok = TADDASSIGN; }
		else l.tok = TPLUS;
	'-' =>
		if(l.pos < len l.src && l.src[l.pos] == '-') { l.pos++; l.tok = TDECR; }
		else if(l.pos < len l.src && l.src[l.pos] == '=') { l.pos++; l.tok = TSUBASSIGN; }
		else l.tok = TMINUS;
	'*' =>
		if(l.pos < len l.src && l.src[l.pos] == '=') { l.pos++; l.tok = TMULASSIGN; }
		else l.tok = TSTAR;
	'/' =>
		if(l.pos < len l.src && l.src[l.pos] == '=') { l.pos++; l.tok = TDIVASSIGN; }
		else l.tok = TSLASH;
	'%' =>
		if(l.pos < len l.src && l.src[l.pos] == '=') { l.pos++; l.tok = TMODASSIGN; }
		else l.tok = TPERCENT;
	'^' =>
		if(l.pos < len l.src && l.src[l.pos] == '=') { l.pos++; l.tok = TPOWASSIGN; }
		else l.tok = TCARET;
	'=' =>
		if(l.pos < len l.src && l.src[l.pos] == '=') { l.pos++; l.tok = TEQ; }
		else l.tok = TASSIGN;
	'!' =>
		if(l.pos < len l.src && l.src[l.pos] == '=') { l.pos++; l.tok = TNE; }
		else if(l.pos < len l.src && l.src[l.pos] == '~') { l.pos++; l.tok = TNOTMATCH; }
		else l.tok = TNOT;
	'<' =>
		if(l.pos < len l.src && l.src[l.pos] == '=') { l.pos++; l.tok = TLE; }
		else l.tok = TLT;
	'>' =>
		if(l.pos < len l.src && l.src[l.pos] == '=') { l.pos++; l.tok = TGE; }
		else if(l.pos < len l.src && l.src[l.pos] == '>') { l.pos++; l.tok = TAPPEND; }
		else l.tok = TGT;
	'~' => l.tok = TMATCH;
	'|' =>
		if(l.pos < len l.src && l.src[l.pos] == '|') { l.pos++; l.tok = TOR; }
		else l.tok = TPIPE;
	'&' =>
		if(l.pos < len l.src && l.src[l.pos] == '&') { l.pos++; l.tok = TAND; }
		else { l.tok = TNONE; fatal("unexpected &"); }
	* =>
		fatal(sys->sprint("unexpected character '%c'", c));
		l.tok = TNONE;
	}
	return l.tok;
}

canberegex(l: ref Lex): int
{
	# regex can appear after: ( , ; { } ~ !~ || && ! == != < <= > >= newline + - * / % ^
	# not after: ) ] number string ident ++ --
	case l.tok {
	TNONE or TNEWLINE or TLPAREN or TCOMMA or TSEMICOLON or
	TLBRACE or TRBRACE or TMATCH or TNOTMATCH or TOR or TAND or
	TNOT or TEQ or TNE or TLT or TLE or TGT or TGE or
	TPLUS or TMINUS or TSTAR or TSLASH or TPERCENT or TCARET or
	TASSIGN or TADDASSIGN or TSUBASSIGN or TMULASSIGN or TDIVASSIGN or
	TMODASSIGN or TPOWASSIGN or TPRINT or TPRINTF or TRETURN or TDO =>
		return 1;
	}
	return 0;
}

# ========== Parser ==========

lex: ref Lex;

expect(tok: int)
{
	if(lex.tok != tok)
		fatal(sys->sprint("expected token %d, got %d near '%s'", tok, lex.tok, lex.strval));
	lex.next();
}

skipnl()
{
	while(lex.tok == TNEWLINE || lex.tok == TSEMICOLON)
		lex.next();
}

parse(prog: string): (list of ref Rule, list of ref Func)
{
	lex = ref Lex;
	lex.init(prog);
	lex.next();

	rl: list of ref Rule;
	fl: list of ref Func;

	skipnl();
	while(lex.tok != TEOF) {
		if(lex.tok == TFUNCTION) {
			fl = parsefunc() :: fl;
		} else {
			rl = parserule() :: rl;
		}
		skipnl();
	}

	# reverse lists
	rrl: list of ref Rule;
	for(; rl != nil; rl = tl rl)
		rrl = hd rl :: rrl;

	rfl: list of ref Func;
	for(; fl != nil; fl = tl fl)
		rfl = hd fl :: rfl;

	return (rrl, rfl);
}

parsefunc(): ref Func
{
	expect(TFUNCTION);
	if(lex.tok != TIDENT)
		fatal("expected function name");
	name := lex.strval;
	lex.next();

	expect(TLPAREN);
	params: list of string;
	if(lex.tok != TRPAREN) {
		if(lex.tok != TIDENT)
			fatal("expected parameter name");
		params = lex.strval :: nil;
		lex.next();
		while(lex.tok == TCOMMA) {
			lex.next();
			if(lex.tok != TIDENT)
				fatal("expected parameter name");
			params = lex.strval :: params;
			lex.next();
		}
		# reverse
		rp: list of string;
		for(; params != nil; params = tl params)
			rp = hd params :: rp;
		params = rp;
	}
	expect(TRPAREN);
	skipnl();
	body := parseblock();
	return ref Func(name, params, body);
}

parserule(): ref Rule
{
	r := ref Rule(0, 0, nil, nil, nil, 0);

	if(lex.tok == TBEGIN) {
		r.begin = 1;
		lex.next();
		skipnl();
		if(lex.tok == TLBRACE)
			r.action = parseblock();
		else
			fatal("expected { after BEGIN");
	} else if(lex.tok == TEND) {
		r.end = 1;
		lex.next();
		skipnl();
		if(lex.tok == TLBRACE)
			r.action = parseblock();
		else
			fatal("expected { after END");
	} else if(lex.tok == TLBRACE) {
		# no pattern, just action
		r.action = parseblock();
	} else {
		# pattern
		r.pat = parseexpr();
		skipnl();
		if(lex.tok == TCOMMA) {
			# range pattern
			lex.next();
			skipnl();
			r.pat2 = parseexpr();
			skipnl();
		}
		if(lex.tok == TLBRACE)
			r.action = parseblock();
		# else: default action is print $0
	}
	return r;
}

parseblock(): ref Node
{
	expect(TLBRACE);
	skipnl();
	stmts: list of ref Node;
	while(lex.tok != TRBRACE && lex.tok != TEOF) {
		s := parsestmt();
		if(s != nil)
			stmts = s :: stmts;
		skipnl();
	}
	expect(TRBRACE);

	# reverse
	rs: list of ref Node;
	for(; stmts != nil; stmts = tl stmts)
		rs = hd stmts :: rs;

	return ref Node.Block(rs);
}

parsestmt(): ref Node
{
	skipnl();
	case lex.tok {
	TLBRACE =>
		return parseblock();
	TIF =>
		return parseif();
	TWHILE =>
		return parsewhile();
	TFOR =>
		return parsefor();
	TDO =>
		return parsedo();
	TPRINT =>
		return parseprint(0);
	TPRINTF =>
		return parseprint(1);
	TDELETE =>
		return parsedelete();
	TNEXT =>
		lex.next();
		return ref Node.Next;
	TEXIT =>
		lex.next();
		val: ref Node;
		if(lex.tok != TNEWLINE && lex.tok != TSEMICOLON && lex.tok != TRBRACE && lex.tok != TEOF)
			val = parseexpr();
		return ref Node.Exit(val);
	TRETURN =>
		lex.next();
		rval: ref Node;
		if(lex.tok != TNEWLINE && lex.tok != TSEMICOLON && lex.tok != TRBRACE && lex.tok != TEOF)
			rval = parseexpr();
		return ref Node.Return(rval);
	TBREAK =>
		lex.next();
		raise "break";	# handled by loop constructs
	TCONTINUE =>
		lex.next();
		raise "continue";
	* =>
		e := parseexpr();
		return e;
	}
}

parseif(): ref Node
{
	expect(TIF);
	expect(TLPAREN);
	cond := parseexpr();
	expect(TRPAREN);
	skipnl();
	tbody := parsestmt();
	fbody: ref Node;
	skipnl();
	if(lex.tok == TELSE) {
		lex.next();
		skipnl();
		fbody = parsestmt();
	}
	return ref Node.If(cond, tbody, fbody);
}

parsewhile(): ref Node
{
	expect(TWHILE);
	expect(TLPAREN);
	cond := parseexpr();
	expect(TRPAREN);
	skipnl();
	body := parsestmt();
	return ref Node.While(cond, body);
}

parsefor(): ref Node
{
	expect(TFOR);
	expect(TLPAREN);
	skipnl();

	# check for "for (var in arr)"
	if(lex.tok == TIDENT) {
		saved_pos := lex.pos;
		saved_tok := lex.tok;
		saved_str := lex.strval;
		varname := lex.strval;
		lex.next();
		if(lex.tok == TIN) {
			lex.next();
			if(lex.tok != TIDENT)
				fatal("expected array name in for-in");
			arrname := lex.strval;
			lex.next();
			expect(TRPAREN);
			skipnl();
			body := parsestmt();
			return ref Node.ForIn(varname, arrname, body);
		}
		# not for-in, backtrack
		lex.pos = saved_pos;
		lex.tok = saved_tok;
		lex.strval = saved_str;
		# re-parse the identifier
		# actually let's just re-lex from saved pos minus length of identifier
		lex.pos = saved_pos - len varname;
		lex.next();
	}

	initn: ref Node;
	if(lex.tok != TSEMICOLON)
		initn = parseexpr();
	expect(TSEMICOLON);
	skipnl();
	condn: ref Node;
	if(lex.tok != TSEMICOLON)
		condn = parseexpr();
	expect(TSEMICOLON);
	skipnl();
	incrn: ref Node;
	if(lex.tok != TRPAREN)
		incrn = parseexpr();
	expect(TRPAREN);
	skipnl();
	body := parsestmt();
	return ref Node.For(initn, condn, incrn, body);
}

parsedo(): ref Node
{
	expect(TDO);
	skipnl();
	body := parsestmt();
	skipnl();
	if(lex.tok != TWHILE)
		fatal("expected while after do body");
	expect(TWHILE);
	expect(TLPAREN);
	cond := parseexpr();
	expect(TRPAREN);
	return ref Node.DoWhile(body, cond);
}

parseprint(format: int): ref Node
{
	lex.next();	# skip print/printf

	args: list of ref Node;
	dst: ref Node;
	append := 0;

	if(lex.tok != TNEWLINE && lex.tok != TSEMICOLON && lex.tok != TRBRACE &&
	   lex.tok != TEOF && lex.tok != TPIPE && lex.tok != TGT && lex.tok != TAPPEND) {
		args = parseprintexpr() :: nil;
		while(lex.tok == TCOMMA) {
			lex.next();
			args = parseprintexpr() :: args;
		}
		# reverse
		ra: list of ref Node;
		for(; args != nil; args = tl args)
			ra = hd args :: ra;
		args = ra;
	}

	if(lex.tok == TGT || lex.tok == TAPPEND) {
		if(lex.tok == TAPPEND)
			append = 1;
		lex.next();
		dst = parseprimary();
	} else if(lex.tok == TPIPE) {
		lex.next();
		dst = parseprimary();
		append = 2;	# pipe
	}

	return ref Node.Print(args, dst, append, format);
}

parsedelete(): ref Node
{
	expect(TDELETE);
	if(lex.tok != TIDENT)
		fatal("expected array name after delete");
	name := lex.strval;
	lex.next();
	idx: ref Node;
	if(lex.tok == TLBRACKET) {
		lex.next();
		idx = parseexpr();
		expect(TRBRACKET);
	}
	return ref Node.Delete(name, idx);
}

# ========== Expression parser (precedence climbing) ==========

parseexpr(): ref Node
{
	return parseassign();
}

parseprintexpr(): ref Node
{
	# like parseexpr but stops at > >> |
	return parsecond();
}

parseassign(): ref Node
{
	left := parsecond();

	case lex.tok {
	TASSIGN or TADDASSIGN or TSUBASSIGN or
	TMULASSIGN or TDIVASSIGN or TMODASSIGN or TPOWASSIGN =>
		op := lex.tok;
		lex.next();
		right := parseassign();
		return ref Node.Assign(op, left, right);
	}
	return left;
}

parsecond(): ref Node
{
	e := parseor();
	if(lex.tok == TQMARK) {
		lex.next();
		texpr := parseassign();
		expect(TCOLON);
		fexpr := parseassign();
		return ref Node.Cond(e, texpr, fexpr);
	}
	return e;
}

parseor(): ref Node
{
	left := parseand();
	while(lex.tok == TOR) {
		lex.next();
		right := parseand();
		left = ref Node.Binary(TOR, left, right);
	}
	return left;
}

parseand(): ref Node
{
	left := parsein();
	while(lex.tok == TAND) {
		lex.next();
		right := parsein();
		left = ref Node.Binary(TAND, left, right);
	}
	return left;
}

parsein(): ref Node
{
	left := parsematch();
	if(lex.tok == TIN) {
		# left must be an ident or index expression
		lex.next();
		if(lex.tok != TIDENT)
			fatal("expected array name after in");
		arr := lex.strval;
		lex.next();
		# extract var name from left
		pick lp := left {
		Ident =>
			return ref Node.In(lp.name, arr);
		* =>
			# for expressions like (a SUBSEP b) in arr, use "_expr_"
			# and handle at eval time via Match node
			return ref Node.In("_expr_", arr);
		}
	}
	return left;
}

parsematch(): ref Node
{
	left := parsecompare();
	while(lex.tok == TMATCH || lex.tok == TNOTMATCH) {
		neg := lex.tok == TNOTMATCH;
		lex.next();
		if(lex.tok == TREGEX) {
			pat := lex.strval;
			(re, err) := regex->compile(pat, 0);
			if(re == nil)
				fatal(sys->sprint("bad regex /%s/: %s", pat, err));
			lex.next();
			left = ref Node.Match(left, re, pat, neg);
		} else {
			# dynamic regex from expression
			right := parseprimary();
			binop := TMATCH;
			if(neg)
				binop = TNOTMATCH;
			left = ref Node.Binary(binop, left, right);
		}
	}
	return left;
}

parsecompare(): ref Node
{
	left := parseconcat();
	case lex.tok {
	TLT or TLE or TGT or TGE or TEQ or TNE =>
		op := lex.tok;
		lex.next();
		right := parseconcat();
		return ref Node.Binary(op, left, right);
	}
	return left;
}

parseconcat(): ref Node
{
	left := parseadd();
	# concatenation: two expressions adjacent (no operator)
	# concat if next token can start an expression and is not an operator
	while(canconcatenate()) {
		right := parseadd();
		left = ref Node.Binary(TCONCAT, left, right);
	}
	return left;
}

canconcatenate(): int
{
	case lex.tok {
	TNUMBER or TSTRING or TIDENT or TDOLLAR or
	TLPAREN or TNOT or TINCR or TDECR or TMINUS =>
		return 1;
	}
	return 0;
}

parseadd(): ref Node
{
	left := parsemul();
	while(lex.tok == TPLUS || lex.tok == TMINUS) {
		op := lex.tok;
		lex.next();
		right := parsemul();
		left = ref Node.Binary(op, left, right);
	}
	return left;
}

parsemul(): ref Node
{
	left := parsepower();
	while(lex.tok == TSTAR || lex.tok == TSLASH || lex.tok == TPERCENT) {
		op := lex.tok;
		lex.next();
		right := parsepower();
		left = ref Node.Binary(op, left, right);
	}
	return left;
}

parsepower(): ref Node
{
	left := parseunary();
	if(lex.tok == TCARET) {
		lex.next();
		right := parsepower();	# right-associative
		left = ref Node.Binary(TCARET, left, right);
	}
	return left;
}

parseunary(): ref Node
{
	case lex.tok {
	TNOT =>
		lex.next();
		operand := parseunary();
		return ref Node.Unary(TNOT, operand, 0);
	TMINUS =>
		lex.next();
		operand := parseunary();
		return ref Node.Unary(TMINUS, operand, 0);
	TPLUS =>
		lex.next();
		return parseunary();
	TINCR =>
		lex.next();
		operand := parseunary();
		return ref Node.Unary(TINCR, operand, 0);
	TDECR =>
		lex.next();
		operand := parseunary();
		return ref Node.Unary(TDECR, operand, 0);
	}
	return parsepostfix();
}

parsepostfix(): ref Node
{
	left := parseprimary();
	while(lex.tok == TINCR || lex.tok == TDECR) {
		op := lex.tok;
		lex.next();
		left = ref Node.Unary(op, left, 1);	# post=1
	}
	return left;
}

parseprimary(): ref Node
{
	case lex.tok {
	TNUMBER =>
		n := lex.numval;
		lex.next();
		return ref Node.Num(n);
	TSTRING =>
		s := lex.strval;
		lex.next();
		return ref Node.Str(s);
	TREGEX =>
		pat := lex.strval;
		(re, err) := regex->compile(pat, 0);
		if(re == nil)
			fatal(sys->sprint("bad regex /%s/: %s", pat, err));
		lex.next();
		# standalone regex means: $0 ~ /regex/
		return ref Node.Match(ref Node.Field(ref Node.Num(0.0)), re, pat, 0);
	TDOLLAR =>
		lex.next();
		e := parseprimary();
		return ref Node.Field(e);
	TLPAREN =>
		lex.next();
		e := parseexpr();
		expect(TRPAREN);
		return e;
	TIDENT =>
		name := lex.strval;
		lex.next();
		if(lex.tok == TLPAREN) {
			# function call
			return parsecall(name);
		}
		if(lex.tok == TLBRACKET) {
			# array subscript
			lex.next();
			idx := parseexpr();
			expect(TRBRACKET);
			return ref Node.Index(name, idx);
		}
		return ref Node.Ident(name);
	TGETLINE =>
		return parsegetline();
	}
	fatal(sys->sprint("unexpected token %d", lex.tok));
	return nil;
}

parsecall(name: string): ref Node
{
	expect(TLPAREN);
	args: list of ref Node;
	if(lex.tok != TRPAREN) {
		args = parseexpr() :: nil;
		while(lex.tok == TCOMMA) {
			lex.next();
			args = parseexpr() :: args;
		}
		# reverse
		ra: list of ref Node;
		for(; args != nil; args = tl args)
			ra = hd args :: ra;
		args = ra;
	}
	expect(TRPAREN);
	return ref Node.Call(name, args);
}

parsegetline(): ref Node
{
	lex.next();	# skip getline
	var: ref Node;
	src: ref Node;
	cmd := 0;

	# getline [var] [< file]
	if(lex.tok == TIDENT && lex.tok != TLT) {
		# peek ahead to see if this is a var or start of next stmt
		var = ref Node.Ident(lex.strval);
		lex.next();
	}
	if(lex.tok == TLT) {
		lex.next();
		src = parseprimary();
	}

	return ref Node.Getline(var, src, cmd);
}

# ========== Interpreter ==========

eval(n: ref Node): ref Val
{
	if(n == nil)
		return mknum(0.0);

	pick p := n {
	Num =>
		return mknum(p.val);
	Str =>
		return mkstr(p.val);
	Regex =>
		# $0 ~ /regex/
		result := regex->execute(p.re, getfield(0));
		if(result != nil)
			return mknum(1.0);
		return mknum(0.0);
	Ident =>
		return getvar(p.name);
	Field =>
		idx := int numval(eval(p.expr));
		return mkstr(getfield(idx));
	Unary =>
		return evalunary(p.op, p.operand, p.post);
	Binary =>
		return evalbinary(p.op, p.left, p.right);
	Assign =>
		return evalassign(p.op, p.dst, p.src);
	In =>
		a := getarray(p.arr);
		v := a.get(p.var);
		if(v != nil)
			return mknum(1.0);
		return mknum(0.0);
	Match =>
		s := strval(eval(p.expr));
		result := regex->execute(p.re, s);
		matched := result != nil;
		if(p.neg)
			matched = !matched;
		if(matched)
			return mknum(1.0);
		return mknum(0.0);
	Index =>
		a := getarray(p.arr);
		key := strval(eval(p.idx));
		v := a.get(key);
		if(v == nil)
			return mkstr("");
		return v;
	Call =>
		return evalcall(p.name, p.args);
	Print =>
		evalprint(p.args, p.dst, p.append, p.format);
		return mknum(0.0);
	If =>
		if(boolval(eval(p.cond)))
			exec(p.tbody);
		else if(p.fbody != nil)
			exec(p.fbody);
		return mknum(0.0);
	While =>
		{
			for(;;) {
				if(!boolval(eval(p.cond)))
					break;
				{
					exec(p.body);
				} exception e {
				"continue" =>
					continue;
				"break" =>
					break;
				"*" =>
					raise e;
				}
			}
		} exception e2 {
		"break" =>
			;
		"*" =>
			raise e2;
		}
		return mknum(0.0);
	DoWhile =>
		{
			for(;;) {
				{
					exec(p.body);
				} exception e {
				"continue" =>
					;
				"break" =>
					break;
				"*" =>
					raise e;
				}
				if(!boolval(eval(p.cond)))
					break;
			}
		} exception e2 {
		"break" =>
			;
		"*" =>
			raise e2;
		}
		return mknum(0.0);
	For =>
		if(p.init != nil)
			eval(p.init);
		{
			for(;;) {
				if(p.cond != nil && !boolval(eval(p.cond)))
					break;
				{
					exec(p.body);
				} exception e {
				"continue" =>
					;
				"break" =>
					break;
				"*" =>
					raise e;
				}
				if(p.incr != nil)
					eval(p.incr);
			}
		} exception e2 {
		"break" =>
			;
		"*" =>
			raise e2;
		}
		return mknum(0.0);
	ForIn =>
		a := getarray(p.arr);
		kl := a.keys();
		{
			for(; kl != nil; kl = tl kl) {
				setvar(p.var, mkstr(hd kl));
				{
					exec(p.body);
				} exception e {
				"continue" =>
					continue;
				"break" =>
					break;
				"*" =>
					raise e;
				}
			}
		} exception e2 {
		"break" =>
			;
		"*" =>
			raise e2;
		}
		return mknum(0.0);
	Block =>
		for(sl := p.stmts; sl != nil; sl = tl sl)
			eval(hd sl);
		return mknum(0.0);
	Return =>
		v: ref Val;
		if(p.val != nil)
			v = eval(p.val);
		else
			v = mknum(0.0);
		raise "return:" + strval(v);
	Delete =>
		a := getarray(p.arr);
		if(p.idx != nil) {
			key := strval(eval(p.idx));
			a.del(key);
		} else {
			# delete entire array
			s := getsym(p.arr);
			s.arr = ref Assoc(nil);
		}
		return mknum(0.0);
	Next =>
		raise "next";
	Exit =>
		code := 0;
		if(p.val != nil)
			code = int numval(eval(p.val));
		raise "exit:" + string code;
	Getline =>
		return evalgetline(p.var, p.src, p.cmd);
	Cond =>
		if(boolval(eval(p.cond)))
			return eval(p.texpr);
		return eval(p.fexpr);
	}
	return mknum(0.0);
}

exec(n: ref Node)
{
	eval(n);
}

evalunary(op: int, operand: ref Node, post: int): ref Val
{
	case op {
	TNOT =>
		if(boolval(eval(operand)))
			return mknum(0.0);
		return mknum(1.0);
	TMINUS =>
		return mknum(-numval(eval(operand)));
	TINCR or TDECR =>
		v := numval(eval(operand));
		newv: real;
		if(op == TINCR)
			newv = v + 1.0;
		else
			newv = v - 1.0;
		assignto(operand, mknum(newv));
		if(post)
			return mknum(v);
		return mknum(newv);
	}
	return mknum(0.0);
}

evalbinary(op: int, left, right: ref Node): ref Val
{
	case op {
	TPLUS =>
		return mknum(numval(eval(left)) + numval(eval(right)));
	TMINUS =>
		return mknum(numval(eval(left)) - numval(eval(right)));
	TSTAR =>
		return mknum(numval(eval(left)) * numval(eval(right)));
	TSLASH =>
		r := numval(eval(right));
		if(r == 0.0)
			fatal("division by zero");
		return mknum(numval(eval(left)) / r);
	TPERCENT =>
		r := numval(eval(right));
		if(r == 0.0)
			fatal("modulo by zero");
		return mknum(real(int numval(eval(left)) % int r));
	TCARET =>
		return mknum(math->pow(numval(eval(left)), numval(eval(right))));
	TCONCAT =>
		return mkstr(strval(eval(left)) + strval(eval(right)));
	TLT =>
		return mkcmp(eval(left), eval(right), -1, -1);
	TLE =>
		return mkcmp(eval(left), eval(right), -1, 0);
	TGT =>
		return mkcmp(eval(left), eval(right), 1, 1);
	TGE =>
		return mkcmp(eval(left), eval(right), 1, 0);
	TEQ =>
		return mkcmp(eval(left), eval(right), 0, 0);
	TNE =>
		lv := eval(left);
		rv := eval(right);
		r := docmp(lv, rv);
		if(r != 0)
			return mknum(1.0);
		return mknum(0.0);
	TOR =>
		if(boolval(eval(left)))
			return mknum(1.0);
		if(boolval(eval(right)))
			return mknum(1.0);
		return mknum(0.0);
	TAND =>
		if(!boolval(eval(left)))
			return mknum(0.0);
		if(!boolval(eval(right)))
			return mknum(0.0);
		return mknum(1.0);
	TMATCH =>
		s := strval(eval(left));
		pat := strval(eval(right));
		(re, nil) := regex->compile(pat, 0);
		if(re == nil)
			return mknum(0.0);
		result := regex->execute(re, s);
		if(result != nil)
			return mknum(1.0);
		return mknum(0.0);
	TNOTMATCH =>
		s := strval(eval(left));
		pat := strval(eval(right));
		(re, nil) := regex->compile(pat, 0);
		if(re == nil)
			return mknum(1.0);
		result := regex->execute(re, s);
		if(result == nil)
			return mknum(1.0);
		return mknum(0.0);
	}
	return mknum(0.0);
}

mkcmp(lv, rv: ref Val, want, also: int): ref Val
{
	r := docmp(lv, rv);
	if(r == want || r == also)
		return mknum(1.0);
	return mknum(0.0);
}

docmp(lv, rv: ref Val): int
{
	# if both look numeric, compare numerically
	if((lv.flags & VNUM) && (rv.flags & VNUM)) {
		ln := numval(lv);
		rn := numval(rv);
		if(ln < rn) return -1;
		if(ln > rn) return 1;
		return 0;
	}
	# string comparison
	ls := strval(lv);
	rs := strval(rv);
	if(ls < rs) return -1;
	if(ls > rs) return 1;
	return 0;
}

evalassign(op: int, dst, src: ref Node): ref Val
{
	sv := eval(src);
	case op {
	TASSIGN =>
		assignto(dst, sv);
		return sv;
	TADDASSIGN =>
		ov := numval(eval(dst));
		nv := mknum(ov + numval(sv));
		assignto(dst, nv);
		return nv;
	TSUBASSIGN =>
		ov := numval(eval(dst));
		nv := mknum(ov - numval(sv));
		assignto(dst, nv);
		return nv;
	TMULASSIGN =>
		ov := numval(eval(dst));
		nv := mknum(ov * numval(sv));
		assignto(dst, nv);
		return nv;
	TDIVASSIGN =>
		ov := numval(eval(dst));
		dv := numval(sv);
		if(dv == 0.0) fatal("division by zero");
		nv := mknum(ov / dv);
		assignto(dst, nv);
		return nv;
	TMODASSIGN =>
		ov := int numval(eval(dst));
		dv := int numval(sv);
		if(dv == 0) fatal("modulo by zero");
		nv := mknum(real(ov % dv));
		assignto(dst, nv);
		return nv;
	TPOWASSIGN =>
		ov := numval(eval(dst));
		nv := mknum(math->pow(ov, numval(sv)));
		assignto(dst, nv);
		return nv;
	}
	return sv;
}

assignto(dst: ref Node, v: ref Val)
{
	pick d := dst {
	Ident =>
		setvar(d.name, v);
	Field =>
		idx := int numval(eval(d.expr));
		setfield(idx, strval(v));
	Index =>
		a := getarray(d.arr);
		key := strval(eval(d.idx));
		a.set(key, v);
	* =>
		fatal("invalid assignment target");
	}
}

# ========== Built-in functions ==========

evalcall(name: string, args: list of ref Node): ref Val
{
	# check user-defined functions first
	for(fl := funcs; fl != nil; fl = tl fl) {
		f := hd fl;
		if(f.name == name)
			return calluserfunc(f, args);
	}

	# built-in functions
	case name {
	"length" =>
		if(args == nil)
			return mknum(real len getfield(0));
		return mknum(real len strval(eval(hd args)));
	"substr" =>
		return builtin_substr(args);
	"index" =>
		return builtin_index(args);
	"split" =>
		return builtin_split(args);
	"sub" =>
		return builtin_sub(args, 0);
	"gsub" =>
		return builtin_sub(args, 1);
	"match" =>
		return builtin_match(args);
	"sprintf" =>
		return builtin_sprintf(args);
	"tolower" =>
		if(args == nil) fatal("tolower requires 1 argument");
		s := strval(eval(hd args));
		r := "";
		for(i := 0; i < len s; i++) {
			c := s[i];
			if(c >= 'A' && c <= 'Z')
				c = c - 'A' + 'a';
			r[len r] = c;
		}
		return mkstr(r);
	"toupper" =>
		if(args == nil) fatal("toupper requires 1 argument");
		s := strval(eval(hd args));
		r := "";
		for(i := 0; i < len s; i++) {
			c := s[i];
			if(c >= 'a' && c <= 'z')
				c = c - 'a' + 'A';
			r[len r] = c;
		}
		return mkstr(r);
	"sin" =>
		if(args == nil) fatal("sin requires 1 argument");
		return mknum(math->sin(numval(eval(hd args))));
	"cos" =>
		if(args == nil) fatal("cos requires 1 argument");
		return mknum(math->cos(numval(eval(hd args))));
	"atan2" =>
		if(args == nil || tl args == nil) fatal("atan2 requires 2 arguments");
		return mknum(math->atan2(numval(eval(hd args)), numval(eval(hd tl args))));
	"exp" =>
		if(args == nil) fatal("exp requires 1 argument");
		return mknum(math->exp(numval(eval(hd args))));
	"log" =>
		if(args == nil) fatal("log requires 1 argument");
		return mknum(math->log(numval(eval(hd args))));
	"sqrt" =>
		if(args == nil) fatal("sqrt requires 1 argument");
		return mknum(math->sqrt(numval(eval(hd args))));
	"int" =>
		if(args == nil) fatal("int requires 1 argument");
		return mknum(real int numval(eval(hd args)));
	"rand" =>
		return mknum(real randmod->rand(1000000) / 1000000.0);
	"srand" =>
		oldseed := randseed;
		if(args != nil)
			randseed = int numval(eval(hd args));
		else
			randseed = 0;	# could use time
		randmod->init(randseed);
		return mknum(real oldseed);
	"system" =>
		if(safe)
			fatal("system not allowed in safe mode");
		if(args == nil) fatal("system requires 1 argument");
		# limited implementation - just return 0
		# full implementation would need os(1) or cmd device
		return mknum(0.0);
	"close" =>
		if(args == nil) fatal("close requires 1 argument");
		fname := strval(eval(hd args));
		closefile(fname);
		return mknum(0.0);
	* =>
		fatal(sys->sprint("unknown function: %s", name));
	}
	return mknum(0.0);
}

calluserfunc(f: ref Func, args: list of ref Node): ref Val
{
	# save old values of params and locals
	saved: list of (string, ref Val);
	params := f.params;
	avals := args;
	for(; params != nil; params = tl params) {
		name := hd params;
		old := getvar(name);
		saved = (name, old) :: saved;
		if(avals != nil) {
			setvar(name, eval(hd avals));
			avals = tl avals;
		} else
			setvar(name, mknum(0.0));
	}

	retval := mknum(0.0);
	{
		eval(f.body);
	} exception e {
	"return:*" =>
		rstr := e[7:];
		# try to parse as number
		retval = mkstr(rstr);
		(n, rest) := str->toint(rstr, 10);
		if(rest == nil || rest == "")
			retval = mknum(real n);
		else {
			rv := real rstr;
			if(rv != 0.0 || rstr == "0" || rstr == "0.0")
				retval = mknum(rv);
		}
	"*" =>
		# restore and re-raise
		for(; saved != nil; saved = tl saved) {
			(name, val) := hd saved;
			setvar(name, val);
		}
		raise e;
	}

	# restore old values
	for(; saved != nil; saved = tl saved) {
		(name, val) := hd saved;
		setvar(name, val);
	}

	return retval;
}

builtin_substr(args: list of ref Node): ref Val
{
	if(args == nil) fatal("substr requires 2-3 arguments");
	s := strval(eval(hd args));
	args = tl args;
	if(args == nil) fatal("substr requires 2-3 arguments");
	m := int numval(eval(hd args));
	args = tl args;
	if(m < 1) m = 1;
	if(m > len s + 1) m = len s + 1;
	start := m - 1;
	if(args != nil) {
		n := int numval(eval(hd args));
		if(n < 0) n = 0;
		end := start + n;
		if(end > len s) end = len s;
		return mkstr(s[start:end]);
	}
	return mkstr(s[start:]);
}

builtin_index(args: list of ref Node): ref Val
{
	if(args == nil || tl args == nil) fatal("index requires 2 arguments");
	s := strval(eval(hd args));
	t := strval(eval(hd tl args));
	if(len t == 0)
		return mknum(0.0);
	for(i := 0; i <= len s - len t; i++) {
		found := 1;
		for(j := 0; j < len t; j++) {
			if(s[i+j] != t[j]) {
				found = 0;
				break;
			}
		}
		if(found)
			return mknum(real(i + 1));
	}
	return mknum(0.0);
}

builtin_split(args: list of ref Node): ref Val
{
	if(args == nil || tl args == nil) fatal("split requires 2-3 arguments");
	s := strval(eval(hd args));
	args = tl args;

	# array name from node
	arrname := "";
	pick an := hd args {
	Ident =>
		arrname = an.name;
	* =>
		fatal("split: second argument must be array name");
	}
	args = tl args;

	sep := fs_var;
	if(args != nil)
		sep = strval(eval(hd args));

	# clear array
	sym := getsym(arrname);
	sym.arr = ref Assoc(nil);
	a := sym.arr;

	count := 0;
	if(sep == " ") {
		(count, fl) := sys->tokenize(s, " \t");
		i := 1;
		for(; fl != nil; fl = tl fl) {
			a.set(string i, mkstr(hd fl));
			i++;
		}
	} else if(len sep == 1) {
		delim := sep[0];
		start := 0;
		for(i := 0; i <= len s; i++) {
			if(i == len s || s[i] == delim) {
				count++;
				a.set(string count, mkstr(s[start:i]));
				start = i + 1;
			}
		}
	} else {
		# regex separator
		(re, nil) := regex->compile(sep, 0);
		if(re == nil) {
			# literal
			count = 1;
			a.set("1", mkstr(s));
		} else {
			rest := s;
			for(;;) {
				if(rest == nil || len rest == 0) {
					count++;
					a.set(string count, mkstr(rest));
					break;
				}
				result := regex->execute(re, rest);
				if(result == nil) {
					count++;
					a.set(string count, mkstr(rest));
					break;
				}
				(ms, me) := result[0];
				count++;
				a.set(string count, mkstr(rest[:ms]));
				rest = rest[me:];
			}
		}
	}
	return mknum(real count);
}

builtin_sub(args: list of ref Node, global: int): ref Val
{
	if(args == nil || tl args == nil) fatal("sub/gsub requires 2-3 arguments");

	# first arg is regex
	pat := strval(eval(hd args));
	(re, err) := regex->compile(pat, 0);
	if(re == nil)
		fatal(sys->sprint("bad regex: %s", err));

	# second arg is replacement
	repl := strval(eval(hd tl args));

	# third arg is target (default $0)
	target: ref Node;
	if(tl tl args != nil)
		target = hd tl tl args;
	else
		target = ref Node.Field(ref Node.Num(0.0));

	s := strval(eval(target));
	nsubs := 0;
	result := "";
	pos := 0;

	for(;;) {
		if(pos > len s)
			break;
		remaining := s[pos:];
		matches := regex->execute(re, remaining);
		if(matches == nil) {
			result += remaining;
			break;
		}
		(ms, me) := matches[0];
		result += remaining[:ms];
		# process replacement: & means matched text
		matched := remaining[ms:me];
		for(i := 0; i < len repl; i++) {
			if(repl[i] == '&')
				result += matched;
			else if(repl[i] == '\\' && i+1 < len repl) {
				i++;
				result[len result] = repl[i];
			} else
				result[len result] = repl[i];
		}
		nsubs++;
		pos += ms + me;
		if(ms == me)
			pos++;	# prevent infinite loop on zero-length match
		if(!global)
			break;
		if(ms == me && pos <= len s)
			result[len result] = s[pos-1];
	}
	# for non-global, append rest
	if(!global && pos <= len s && nsubs > 0) {
		remaining := s[pos:];
		result += remaining;
	}

	if(nsubs > 0)
		assignto(target, mkstr(result));
	return mknum(real nsubs);
}

builtin_match(args: list of ref Node): ref Val
{
	if(args == nil || tl args == nil) fatal("match requires 2 arguments");
	s := strval(eval(hd args));
	pat := strval(eval(hd tl args));
	(re, nil) := regex->compile(pat, 0);
	if(re == nil) {
		rstart_var = 0;
		rlength_var = -1;
		return mknum(0.0);
	}
	result := regex->execute(re, s);
	if(result == nil) {
		rstart_var = 0;
		rlength_var = -1;
		return mknum(0.0);
	}
	(ms, me) := result[0];
	rstart_var = ms + 1;
	rlength_var = me - ms;
	return mknum(real rstart_var);
}

builtin_sprintf(args: list of ref Node): ref Val
{
	if(args == nil) fatal("sprintf requires at least 1 argument");
	fmt := strval(eval(hd args));
	args = tl args;
	return mkstr(dosprintf(fmt, args));
}

dosprintf(fmt: string, args: list of ref Node): string
{
	result := "";
	i := 0;
	while(i < len fmt) {
		if(fmt[i] == '%') {
			if(i+1 < len fmt && fmt[i+1] == '%') {
				result += "%";
				i += 2;
				continue;
			}
			# parse format specifier
			fmtstart := i;
			i++;
			# flags
			while(i < len fmt && (fmt[i] == '-' || fmt[i] == '+' || fmt[i] == ' ' || fmt[i] == '0' || fmt[i] == '#'))
				i++;
			# width
			if(i < len fmt && fmt[i] == '*') {
				i++;
				# consume width from args
				if(args != nil) {
					eval(hd args);
					args = tl args;
				}
			} else {
				while(i < len fmt && isdigit(fmt[i]))
					i++;
			}
			# precision
			if(i < len fmt && fmt[i] == '.') {
				i++;
				if(i < len fmt && fmt[i] == '*') {
					i++;
					if(args != nil) {
						eval(hd args);
						args = tl args;
					}
				} else {
					while(i < len fmt && isdigit(fmt[i]))
						i++;
				}
			}
			if(i >= len fmt)
				break;
			conv := fmt[i];
			i++;
			fmtspec := fmt[fmtstart:i];

			if(args == nil) {
				result += fmtspec;
				continue;
			}
			v := eval(hd args);
			args = tl args;

			case conv {
			'd' or 'i' =>
				result += sys->sprint(fmtspec, int numval(v));
			'o' =>
				result += sys->sprint(fmtspec, int numval(v));
			'x' or 'X' =>
				result += sys->sprint(fmtspec, int numval(v));
			'f' or 'e' or 'E' or 'g' or 'G' =>
				result += sys->sprint(fmtspec, numval(v));
			's' =>
				result += sys->sprint(fmtspec, strval(v));
			'c' =>
				n := int numval(v);
				if(n == 0) n = int (strval(v))[0];
				result[len result] = n;
			* =>
				result += fmtspec;
			}
		} else if(fmt[i] == '\\') {
			i++;
			if(i < len fmt) {
				case fmt[i] {
				'n' => result += "\n";
				't' => result += "\t";
				'r' => result += "\r";
				'\\' => result += "\\";
				'"' => result += "\"";
				'/' => result += "/";
				* => result[len result] = fmt[i];
				}
				i++;
			}
		} else {
			result[len result] = fmt[i];
			i++;
		}
	}
	return result;
}

# ========== Print and I/O ==========

evalprint(args: list of ref Node, dst: ref Node, append: int, format: int)
{
	out := "";
	if(format) {
		# printf
		if(args == nil)
			return;
		fmt := strval(eval(hd args));
		out = dosprintf(fmt, tl args);
	} else {
		# print
		first := 1;
		for(al := args; al != nil; al = tl al) {
			if(!first)
				out += ofs_var;
			out += strval(eval(hd al));
			first = 0;
		}
		if(args == nil)
			out = getfield(0);
		out += ors_var;
	}

	if(dst == nil) {
		sys->print("%s", out);
	} else {
		fname := strval(eval(dst));
		if(append == 2) {
			# pipe - limited implementation
			if(safe)
				fatal("pipe output not allowed in safe mode");
			sys->print("%s", out);	# fallback
		} else {
			if(safe)
				fatal("file output not allowed in safe mode");
			f := getopenfile(fname, append);
			if(f != nil) {
				f.puts(out);
				f.flush();
			}
		}
	}
}

getopenfile(fname: string, append: int): ref Iobuf
{
	for(ol := openfiles; ol != nil; ol = tl ol) {
		(name, f) := hd ol;
		if(name == fname)
			return f;
	}

	mode := Sys->OWRITE;
	fd: ref Sys->FD;
	if(append == 1) {
		fd = sys->open(fname, Sys->OWRITE);
		if(fd != nil)
			sys->seek(fd, big 0, Sys->SEEKEND);
	}
	if(fd == nil)
		fd = sys->create(fname, Sys->OWRITE, 8r644);
	if(fd == nil) {
		sys->fprint(stderr, "awk: can't open %s: %r\n", fname);
		return nil;
	}
	f := bufio->fopen(fd, Bufio->OWRITE);
	openfiles = (fname, f) :: openfiles;
	return f;
}

closefile(fname: string)
{
	nl: list of (string, ref Iobuf);
	for(ol := openfiles; ol != nil; ol = tl ol) {
		(name, f) := hd ol;
		if(name == fname)
			f.flush();
		else
			nl = (name, f) :: nl;
	}
	openfiles = nl;
}

closeallfiles()
{
	for(ol := openfiles; ol != nil; ol = tl ol) {
		(nil, f) := hd ol;
		f.flush();
	}
	openfiles = nil;
}

evalgetline(var: ref Node, src: ref Node, nil: int): ref Val
{
	line: string;

	if(src != nil) {
		fname := strval(eval(src));
		if(safe)
			fatal("getline from file not allowed in safe mode");
		f := getopenreadfile(fname);
		if(f == nil)
			return mknum(-1.0);
		line = f.gets('\n');
		if(line == nil)
			return mknum(0.0);
	} else {
		# getline from current input - not straightforward
		# simplified: return 0
		return mknum(0.0);
	}

	# strip trailing newline
	if(len line > 0 && line[len line - 1] == '\n')
		line = line[:len line - 1];

	if(var != nil)
		assignto(var, mkstr(line));
	else {
		setfield(0, line);
		splitrecord(line);
	}
	nr_var++;
	return mknum(1.0);
}

readfiles: list of (string, ref Iobuf);

getopenreadfile(fname: string): ref Iobuf
{
	for(ol := readfiles; ol != nil; ol = tl ol) {
		(name, f) := hd ol;
		if(name == fname)
			return f;
	}

	f := bufio->open(fname, Bufio->OREAD);
	if(f == nil)
		return nil;
	readfiles = (fname, f) :: readfiles;
	return f;
}

# ========== Main execution engine ==========

run(inputfiles: list of string)
{
	# initialize
	fields = array[64] of string;
	for(i := 0; i < len fields; i++)
		fields[i] = "";
	nfields = 0;

	# execute BEGIN rules
	for(rl := rules; rl != nil; rl = tl rl) {
		r := hd rl;
		if(r.begin && r.action != nil) {
			{
				exec(r.action);
			} exception e {
			"exit:*" =>
				closeallfiles();
				return;
			"*" =>
				raise e;
			}
		}
	}

	# process input files
	if(inputfiles == nil)
		inputfiles = "-" :: nil;

	{
		for(; inputfiles != nil; inputfiles = tl inputfiles) {
			fname := hd inputfiles;

			# check for var=val assignment
			eqpos := -1;
			for(i = 0; i < len fname; i++) {
				if(fname[i] == '=') {
					eqpos = i;
					break;
				}
			}
			if(eqpos > 0 && isalpha(fname[0])) {
				allident := 1;
				for(i = 0; i < eqpos; i++) {
					if(!isalnum(fname[i])) {
						allident = 0;
						break;
					}
				}
				if(allident) {
					setvar(fname[:eqpos], mkstr(fname[eqpos+1:]));
					continue;
				}
			}

			f: ref Iobuf;
			if(fname == "-")
				f = bufio->fopen(sys->fildes(0), Bufio->OREAD);
			else {
				f = bufio->open(fname, Bufio->OREAD);
				if(f == nil) {
					sys->fprint(stderr, "awk: can't open %s: %r\n", fname);
					continue;
				}
			}
			filename_var = fname;
			fnr_var = 0;
			processfile(f);
		}
	} exception e {
	"exit:*" =>
		;	# fall through to END
	"*" =>
		raise e;
	}

	# execute END rules
	for(rl = rules; rl != nil; rl = tl rl) {
		r := hd rl;
		if(r.end && r.action != nil) {
			{
				exec(r.action);
			} exception e {
			"exit:*" =>
				;
			"*" =>
				raise e;
			}
		}
	}

	closeallfiles();
}

processfile(f: ref Iobuf)
{
	for(;;) {
		line: string;
		if(rs_var == "\n") {
			line = f.gets('\n');
		} else if(len rs_var == 1) {
			line = f.gets(rs_var[0]);
		} else {
			# RS="" means blank-line separated records
			# or single char RS
			line = f.gets('\n');
		}
		if(line == nil)
			break;

		# strip record separator
		if(len line > 0) {
			if(rs_var == "\n" && line[len line - 1] == '\n')
				line = line[:len line - 1];
			else if(len rs_var == 1 && line[len line - 1] == rs_var[0])
				line = line[:len line - 1];
		}

		# strip \r if present (for \r\n files)
		if(len line > 0 && line[len line - 1] == '\r')
			line = line[:len line - 1];

		nr_var++;
		fnr_var++;
		splitrecord(line);

		{
			for(rl := rules; rl != nil; rl = tl rl) {
				r := hd rl;
				if(r.begin || r.end)
					continue;

				matched := 0;
				if(r.pat == nil) {
					matched = 1;
				} else if(r.pat2 != nil) {
					# range pattern
					if(r.inrange) {
						matched = 1;
						if(boolval(eval(r.pat2)))
							r.inrange = 0;
					} else if(boolval(eval(r.pat))) {
						matched = 1;
						r.inrange = 1;
					}
				} else {
					matched = boolval(eval(r.pat));
				}

				if(matched) {
					if(r.action != nil)
						exec(r.action);
					else
						sys->print("%s\n", getfield(0));
				}
			}
		} exception e {
		"next" =>
			continue;
		"*" =>
			raise e;
		}
	}
}

# ========== Main entry point ==========

init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	stderr = sys->fildes(2);
	bufio = load Bufio Bufio->PATH;
	str = load String String->PATH;
	regex = load Regex Regex->PATH;
	math = load Math Math->PATH;
	randmod = load Rand Rand->PATH;

	if(bufio == nil || str == nil || regex == nil || math == nil || randmod == nil)
		fatal("cannot load required modules");

	randmod->init(0);

	arg = load Arg Arg->PATH;
	arg->init(args);

	progtext := "";
	progfile := "";
	vlist: list of (string, string);

	# handle -safe before normal arg parsing
	# scan for -safe and remove it, since arg module does single-char opts
	nargs: list of string;
	for(al := args; al != nil; al = tl al) {
		if(hd al == "-safe")
			safe = 1;
		else
			nargs = hd al :: nargs;
	}
	# reverse
	rargs: list of string;
	for(; nargs != nil; nargs = tl nargs)
		rargs = hd nargs :: rargs;
	args = rargs;

	arg->init(args);
	while((c := arg->opt()) != 0)
		case c {
		'F' =>
			fs_var = arg->earg();
		'v' =>
			s := arg->earg();
			eqpos := -1;
			for(i := 0; i < len s; i++) {
				if(s[i] == '=') {
					eqpos = i;
					break;
				}
			}
			if(eqpos < 0)
				fatal("-v requires var=value");
			vlist = (s[:eqpos], s[eqpos+1:]) :: vlist;
		'f' =>
			progfile = arg->earg();
		* =>
			usage();
		}

	args = arg->argv();

	if(progfile != "") {
		fd := sys->open(progfile, Sys->OREAD);
		if(fd == nil)
			fatal(sys->sprint("can't open %s: %r", progfile));
		buf := array[65536] of byte;
		n := sys->read(fd, buf, len buf);
		if(n < 0)
			fatal(sys->sprint("error reading %s: %r", progfile));
		progtext = string buf[:n];
	} else {
		if(args == nil)
			usage();
		progtext = hd args;
		args = tl args;
	}

	# parse program
	(rules, funcs) = parse(progtext);

	# apply -v assignments
	for(; vlist != nil; vlist = tl vlist) {
		(name, val) := hd vlist;
		setvar(name, mkstr(val));
	}

	# run
	{
		run(args);
	} exception e {
	"fail:*" =>
		raise e;
	"exit:*" =>
		;
	"*" =>
		raise e;
	}
}
