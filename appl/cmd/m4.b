implement M4;

include "sys.m";
	sys: Sys;

include "draw.m";

include "bufio.m";
	bufio: Bufio;
	Iobuf: import bufio;

include "sh.m";

include "arg.m";

M4: module
{
	init:	fn(nil: ref Draw->Context, nil: list of string);
};

NHASH: con 131;

Name: adt {
	name:	string;
	repl:	string;
	impl:	ref fn(nil: array of string);
	dol:	int;	# repl contains $[0-9]

	text:	fn(n: self ref Name): string;
};

names := array[NHASH] of list of ref Name;

File: adt {
	name:	string;
	line:	int;
	fp:	ref Iobuf;
};

Param: adt {
	s:	string;
};

pushedback: string;
pushedp := 0;	# next available index in pushedback
diverted := array[10] of string;
curdiv := 0;
curarg: ref Param;	# non-nil if collecting argument string
instack: list of ref File;
lquote := '`';
rquote := '\'';
initcom := "#";
endcom := "\n";
bout: ref Iobuf;
sh: Sh;

init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	bufio = load Bufio Bufio->PATH;

	bout = bufio->fopen(sys->fildes(1), Sys->OWRITE);

	define("inferno", "inferno");

	builtin("changecom", dochangecom);
	builtin("changequote", dochangequote);
	builtin("define", dodefine);
	builtin("divert", dodivert);
	builtin("divnum", dodivnum);
	builtin("dnl", dodnl);
	builtin("dumpdef", dodumpdef);
	builtin("errprint", doerrprint);
	builtin("eval", doeval);
	builtin("ifdef", doifdef);
	builtin("ifelse", doifelse);
	builtin("include", doinclude);
	builtin("incr", doincr);
	builtin("index", doindex);
	builtin("len", dolen);
	builtin("maketemp", domaketemp);
	builtin("sinclude", dosinclude);
	builtin("substr", dosubstr);
	builtin("syscmd", dosyscmd);
	builtin("translit", dotranslit);
	builtin("undefine", doundefine);
	builtin("undivert", doundivert);

	arg := load Arg Arg->PATH;
	arg->setusage("m4 [-Dname[=value]] [-Uname] [file ...]");
	arg->init(args);

	while((o := arg->opt()) != 0){
		case o {
		'D' =>
			s := arg->earg();
			for(i := 0; i < len s; i++)
				if(s[i] == '='){
					define(s[0: i], s[i+1:]);
					break;
				}
			if(i == len s)
				define(s[0: i], "");
		'U' =>
			undefine(arg->earg());
		* =>
			arg->usage();
		}
	}
	args = arg->argv();
	arg = nil;

	if(args != nil){
		for(; args != nil; args = tl args){
			f := bufio->open(hd args, Sys->OREAD);
			if(f == nil)
				error(sys->sprint("can't open %s: %r", hd args));
			pushfile(hd args, f);
			scan();
		}
	}else{
		pushfile("standard input", bufio->fopen(sys->fildes(0), Sys->OREAD));
		scan();
	}
	bout.flush();
}

scan()
{
	while((c := getc()) >= 0){
		if(isalpha(c))
			called(c);	
		else if(c == lquote)
			quoted();
		else if(initcom != nil && initcom[0] == c)
			comment();
		else
			putc(c);
	}
}

error(s: string)
{
	where := "";
	if(instack != nil){
		ios := hd instack;
		where = sys->sprint(" %s:%d:", ios.name, ios.line);
	}
	sys->fprint(sys->fildes(2), "m4:%s %s\n", where, s);
	raise "fail:error";
}

pushfile(name: string, fp: ref Iobuf)
{
	instack = ref File(name, 1, fp) :: instack;
}

called(c: int)
{
	tok: string;
	do{
		tok[len tok] = c;
		c = getc();
	}while(isalpha(c) || c >= '0' && c <= '9');
	def := lookup(tok);
	if(def == nil){
		pushc(c);
		puts(tok);
		return;
	}
	if(c != '('){	# no parameters
		pushc(c);
		expand(def, array[] of {tok});
		return;
	}
	# collect arguments, allowing for nested parentheses;
	# on ')' expand definition, further expanding $n references therein
	argstack := def.name :: nil;	# $0
	savearg := curarg;	# save parameter (if any) for outer call
	curarg = ref Param("");
	nesting := 0;	# () depth
	skipws();
	for(;;){
		if((c = getc()) < 0)
			error("EOF in parameters");
		if(isalpha(c))
			called(c);
		else if(c == lquote)
			quoted();
		else{
			if(c == '(')
				nesting++;
			if(nesting > 0){
				if(c == ')')
					nesting--;
				putc(c);
			}else if(c == ','){
				argstack = curarg.s :: argstack;
				curarg = ref Param("");
				skipws();
			}else if(c == ')')
				break;
			else
				putc(c);
		}
	}
	argstack = curarg.s :: argstack;
	curarg = savearg;	# restore outer parameter (if any)
	# build arguments
	narg := len argstack;
	args := array[narg] of string;
	for(; argstack != nil; argstack = tl argstack)
		args[--narg] = hd argstack;
	expand(def, args);
}

quoted()
{
	nesting :=0;
	while((c := getc()) != rquote || nesting > 0){
		if(c < 0)
			error("EOF in string");
		if(c == rquote)
			nesting--;
		else if(c == lquote)
			nesting++;
		putc(c);
	}
}

comment()
{
	for(i := 1; i < len initcom; i++){
		if((c := getc()) != initcom[i]){
			if(c < 0)
				error("EOF in comment");
			pushc(c);
			pushs(initcom[1: i]);
			putc(initcom[0]);
			return;
		}
	}
	puts(initcom);
	for(i = 0; i < len endcom;){
		c := getc();
		if(c < 0)
			error("EOF in comment");
		putc(c);
		if(c == endcom[i])
			i++;
		else
			i = c == endcom[0];
	}
}

skipws()
{
	while(isspace(c := getc()))
		{}
	pushc(c);
}

isspace(c: int): int
{
	return c == ' ' || c == '\t' || c == '\n' || c == '\r';
}

isname(s: string): int
{
	if(s == nil || !isalpha(s[0]))
		return 0;
	for(i := 1; i < len s; i++)
		if(!(isalpha(s[i]) || s[i]>='0' && s[i]<='9'))
			return 0;
	return 1;
}

isalpha(c: int): int
{
	return c >= 'a' && c <= 'z' || c >= 'A' && c <= 'Z' || c == '_' || c > 16r80;
}

hash(name: string): int
{
	h := 0;
	for(i := 0; i < len name; i++)
		h = h*65599 + name[i];
	return (h & ~(1<<31)) % NHASH;
}

builtin(name: string, impl: ref fn(nil: array of string))
{
	h := hash(name);
	n := ref Name(name, nil, impl, 0);
	names[h] = n :: names[h];
}

define(name: string, repl: string)
{
	h := hash(name);
	dol := hasdol(repl);
	for(l := names[h]; l != nil; l = tl l){
		n := hd l;
		if(n.name == name){
			n.impl = nil;
			n.repl = repl;
			n.dol = dol;
			return;
		}
	}
	n := ref Name(name, repl, nil, dol);
	names[h] = n :: names[h];
}

lookup(name: string): ref Name
{
	h := hash(name);
	for(l := names[h]; l != nil; l = tl l)
		if((hd l).name == name)
			return hd l;
	return nil;
}

undefine(name: string)
{
	h := hash(name);
	rl: list of ref Name;
	for(l := names[h]; l != nil; l = tl l){
		if((hd l).name == name){
			l = tl l;
			for(; rl != nil; rl = tl rl)
				l = hd rl :: l;
			names[h] = l;
			return;
		}else
			rl = hd l :: rl;
	}
}

Name.text(n: self ref Name): string
{
	if(n.impl != nil)
		return sys->sprint("builtin %q", n.name);
	return sys->sprint("%c%s%c", lquote, n.repl, rquote);
}

dodumpdef(args: array of string)
{
	if(len args > 1){
		for(i := 1; i < len args; i++)
			if((n := lookup(args[i])) != nil)
				sys->fprint(sys->fildes(2), "%q	%s\n", n.name, n.text());
	}else{
		for(i := 0; i < len names; i++)
			for(l := names[i]; l != nil; l = tl l)
				sys->fprint(sys->fildes(2), "%q %s\n", (hd l).name, (hd l).text());
	}
}

pushs(s: string)
{
	for(i := len s; --i >= 0;)
		pushedback[pushedp++] = s[i];
}

pushc(c: int)
{
	if(c >= 0)
		pushedback[pushedp++] = c;
}

getc(): int
{
	if(pushedp > 0)
		return pushedback[--pushedp];
	for(; instack != nil; instack = tl instack){
		ios := hd instack;
		c := ios.fp.getc();
		if(c >= 0){
			if(c == '\n')
				ios.line++;
			return c;
		}
	}
	return -1;
}

puts(s: string)
{
	if(curarg != nil)
		curarg.s += s;
	else if(curdiv > 0)
		diverted[curdiv] += s;
	else if(curdiv == 0)
		bout.puts(s);
}

putc(c: int)
{
	if(curarg != nil){
		# stow in argument collection buffer
		curarg.s[len curarg.s] = c;
	}else if(curdiv > 0){
		l := len diverted[curdiv];
		diverted[curdiv][l] = c;
	}else if(curdiv == 0)
		bout.putc(c);
}

expand(def: ref Name, args: array of string)
{
	if(def.impl != nil){
		def.impl(args);
		return;
	}
	if(def.repl == def.name || def.repl == "$0"){
		puts(def.name);
		return;
	}
	if(!def.dol || def.repl == nil){
		pushs(def.repl);
		return;
	}
	# expand $n
	s := def.repl;
	for(i := len s; --i >= 1;){
		if(s[i-1] == '$' && (c := s[i]-'0') >= 0 && c <= 9){
			if(c < len args)
				pushs(args[c]);
			i--;
		}else
			pushc(s[i]);
	}
	if(i >= 0)
		pushc(s[0]);
}

hasdol(s: string): int
{
	for(i := 0; i < len s; i++)
		if(s[i] == '$')
			return 1;
	return 0;
}

dodefine(args: array of string)
{
	if(len args > 2)
		define(args[1], args[2]);
	else if(len args > 1)
		define(args[1], "");
}

doundefine(args: array of string)
{
	for(i := 1; i < len args; i++)
		undefine(args[i]);
}

doeval(args: array of string)
{
	if(len args > 1)
		pushs(string eval(args[1]));
}

dodivert(args: array of string)
{
	if(len args > 1){
		n := int args[1];
		if(n < 0 || n >= len diverted)
			n = -1;
		curdiv = n;
	}else
		curdiv = 0;
}

dodivnum(nil: array of string)
{
	pushs(string curdiv);
}

doundivert(args: array of string)
{
	if(len args <= 1){	# do all but current, in order
		for(i := 1; i < len diverted; i++){
			if(i != curdiv){
				puts(diverted[i]);
				diverted[i] = nil;
			}
		}
	}else{	# do those specified
		for(i := 1; i < len args; i++){
			n := int args[i];
			if(n > 0 && n < len diverted && n != curdiv){
				puts(diverted[n]);
				diverted[n] = nil;
			}
		}
	}
}

doifdef(args: array of string)
{
	if(len args < 2)
		return;
	n := lookup(args[1]);
	if(n != nil)
		pushs(args[2]);
	else if(len args > 2)
		pushs(args[3]);
}

doifelse(args: array of string)
{
	for(i := 1; i+2 < len args; i += 3){
		if(args[i] == args[i+1]){
			pushs(args[i+2]);
			return;
		}
	}
	if(i > 2 && i == len args-1)
		pushs(args[i]);
}

doincr(args: array of string)
{
	if(len args > 1)
		pushs(string (int args[1] + 1));
}

doindex(args: array of string)
{
	if(len args > 2){
		a := args[1];
		b := args[2];
		for(i := 0; i+len b <= len a; i++){
			if(a[i: i+len b] == b){
				pushs(string i);
				return;
			}
		}
		pushs("-1");
	}
}

doinclude(args: array of string)
{
	for(i := len args; --i >= 1;){
		fp := bufio->open(args[i], Sys->OREAD);
		if(fp == nil)
			error(sys->sprint("can't open %s: %r", args[i]));
		pushfile(args[i], fp);
	}
}

dosinclude(args: array of string)
{
	for(i := len args; --i >= 1;){
		fp := bufio->open(args[i], Sys->OREAD);
		if(fp != nil)
			pushfile(args[i], fp);
	}
}

clip(v, l, u: int): int
{
	if(v < l)
		return l;
	if(v > u)
		return u;
	return v;
}

dosubstr(args: array of string)
{
	if(len args > 2){
		l := len args[1];
		o := clip(int args[2], 0, l);
		n := l;
		if(len args > 3)
			n = clip(int args[3], 0, l);
		if((n += o) > l)
			n = l;
		pushs(args[1][o: n]);
	}
}

cindex(s: string, c: int): int
{
	for(i := 0; i < len s; i++)
		if(s[i] == c)
			return i;
	return -1;
}

dotranslit(args: array of string)
{
	if(len args < 3)
		return;
	s := args[1];
	f := args[2];
	t := "";
	if(len args > 3)
		t = args[3];
	o := "";
	for(i := 0; i < len s; i++){
		if((j := cindex(f, s[i])) >= 0){
			if(j < len t)
				o[len o] = t[j];
		}else
			o[len o] = s[i];
	}
	pushs(o);
}

doerrprint(args: array of string)
{
	s := "";
	for(i := 1; i < len args; i++)
		s += " "+args[i];
	if(s != nil)
		sys->fprint(sys->fildes(2), "m4:%s\n", s);
}

dolen(args: array of string)
{
	if(len args > 1)
		puts(string len args[1]);
}

dochangecom(args: array of string)
{
	case len args {
	1 =>
		initcom = "";
		endcom = "";
	2 =>
		initcom = args[1];
		endcom = "\n";
	* =>
		initcom = args[1];
		endcom = args[2];
		if(endcom == "")
			endcom = "\n";
	}
}

dochangequote(args: array of string)
{
	case len args {
	1 =>
		lquote = '`';
		rquote = '\'';
	2 =>
		if(args[1] != nil)
			lquote = rquote = args[1][0];
	* =>
		if(args[1] != nil)
			lquote = args[1][0];
		if(args[2] != nil)
			rquote = args[2][0];
	}
}

dodnl(nil: array of string)
{
	while((c := getc()) >= 0 && c != '\n')
		{}
}

domaketemp(args: array of string)
{
	if(len args > 1)
		pushs(mktemp(args[1]));
}

dosyscmd(args: array of string)
{
	if(len args > 1){
		{
			if(sh == nil){
				sh = load Sh Sh->PATH;
				if(sh == nil)
					raise sys->sprint("load: can't load %s: %r", Sh->PATH);
			}
			sh->system(nil, args[1]);
		}exception e{
		"load:*" =>
			error(e);
		}
	}
}

sysname: string;

mktemp(s: string): string
{
	if(sysname == nil)
		sysname = readfile("/dev/sysname", "m4");
	# trim trailing X's
	for (x := len s; --x >= 0;)
		if(s[x] == 'X'){
			while(x > 0 && s[x-1] == 'X')
				x--;
			s = s[0: x];
			break;
		}
	# add system name, process ID and 'a'
	if(s != nil)
		s += ".";
	s += sys->sprint("%s.%.10uda", sysname, sys->pctl(0, nil));
	while(sys->stat(s).t0 >= 0){
		if(s[len s-1] == 'z')
			error("out of temp files: "+s);
		s[len s-1]++;
	}
	return s;
}

readfile(name: string, default: string): string
{
	fd := sys->open(name, Sys->OREAD);
	if(fd == nil)
		return default;
	buf := array[Sys->NAMEMAX] of byte;
	n := sys->read(fd, buf, len buf);
	if(n <= 0)
		return default;
	return string buf[0: n];
}

#
# expressions provided use Limbo operators (C with signed shift and **),
# instead of original m4 ones (where | and & were || and &&, and ^ was power),
# but that's true of later unix m4 implementations too
#

Oeof, Ogok, Oge, Ole, One, Oeq, Opow, Oand, Oor, Orsh, Olsh, Odigits: con 'a'+iota;
Syntax, Badeval: exception;
evalin: string;
evalp := 0;

eval(s: string): int
{
	evalin = s;
	evalp = 0;
	looked = -1;
	{
		v := expr(1);
		if(evalp < len evalin)
			raise Syntax;
		return v;
	}exception{
	Syntax =>
		error(sys->sprint("syntax error: %q %q", evalin[0: evalp], evalin[evalp:]));
		return 0;
	Badeval =>
		error(sys->sprint("zero divide in %q", evalin));
		return 0;
	}
}

eval1(op: int, v1, v2: int): int raises Badeval
{
	case op{
	'+' =>	return v1 + v2;
	'-' =>	return v1 - v2;
	'*' =>		return v1 * v2;
	'%' =>
		if(v2 == 0)
			raise Badeval;	# division by zero
		return v1 % v2;
	'/' =>
		if(v2 == 0)
			raise Badeval;	# division by zero
		return v1 / v2;
	Opow =>
		if(v2 < 0)
			raise Badeval;
		return v1 ** v2;
	'&' =>	return v1 & v2;
	'|' =>		return v1 | v2;
	'^' =>	return v1 ^ v2;
	Olsh =>	return v1 << v2;
	Orsh =>	return v1 >> v2;
	Oand =>	return v1 && v2;
	Oor =>	return v1 || v2;
	'<' =>	return v1 < v2;
	'>' =>	return v1 > v2;
	Ole =>	return v1 <= v2;
	Oge =>	return v1 >= v2;
	One =>	return v1 != v2;
	Oeq =>	return v1 == v2;
	* =>
		sys->print("unknown op: %c\n", op);	# shouldn't happen
		raise Badeval;
	}
}

priority(c: int): int
{
	case c {
	Oor =>	return 1;
	Oand =>	return 2;
	'|' =>		return 3;
	'^' =>	return 4;
	'&' =>	return 5;
	Oeq or One =>	return 6;
	'<' or '>' or Oge or Ole => return 7;
	Olsh or Orsh =>	return 8;
	'+' or '-' => return 9;
	'*' or '/' or '%' => return 10;
	Opow =>	return 11;
	* =>	return 0;
	}
}

rightassoc(c: int): int
{
	return c == Opow;
}

expr(prec: int): int raises(Syntax, Badeval)
{
	{
		v := primary();
		while(priority(look()) >= prec){
			op := lex();
			r := priority(op) + !rightassoc(op);
			v = eval1(op, v, expr(r));
		}
		return v;
	}exception{
	Syntax or Badeval =>
		raise;
	}
}

primary(): int raises Syntax
{
	{
		case lex() {
		'(' =>
			v := expr(1);
			if(lex() != ')')
				raise Syntax;
			return v;
		'+' =>	
			return primary();
		'-' =>
			return -primary();
		'!' =>
			return !primary();
		'~' =>
			return ~primary();
		Odigits =>
			return yylval;
		* =>
			raise Syntax;
		}
	}exception{
	Syntax =>
		raise;
	}
}

yylval := 0;
looked := -1;

look(): int
{
	looked = lex();
	return looked;
}

lex(): int
{
	if((c := looked) >= 0){
		looked = -1;
		return c;	# if Odigits, assumes yylval untouched
	}
	while(evalp < len evalin && isspace(evalin[evalp]))
		evalp++;
	if(evalp >= len evalin)
		return Oeof;
	case c = evalin[evalp++] {
	'*' =>
		return ifnext('*', Opow, '*');
	'>' =>
		return ifnext('=', Oge, ifnext('>', Orsh, '>'));
	'<' =>
		return ifnext('=', Ole, ifnext('<', Olsh, '<'));
	'=' =>
		return ifnext('=', Oeq, Oeq);
	'!' =>
		return ifnext('=', One, '!');
	'|' =>
		return ifnext('|', Oor, '|');
	'&' =>
		return ifnext('&', Oand, '&');
	'0' to '9' =>
		evalp--;
		n := 0;
		while(evalp < len evalin && (c = evalin[evalp]) >= '0' && c <= '9'){
			n = n*10 + (c-'0');
			evalp++;
		}
		yylval = n;
		return Odigits;
	* =>
		return c;
	}
}

ifnext(a, t, f: int): int
{
	if(evalp < len evalin && evalin[evalp] == a){
		evalp++;
		return t;
	}
	return f;
}
