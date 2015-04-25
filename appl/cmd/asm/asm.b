implement Asm;

#line	2	"asm.y"

include "sys.m";
	sys: Sys;

include "draw.m";

include "bufio.m";
	bufio: Bufio;
	Iobuf: import bufio;

include "math.m";
	math: Math;
	export_real: import math;

include "string.m";
	str: String;

include "arg.m";

include "../limbo/isa.m";

YYSTYPE: adt {
	inst:	ref Inst;
	addr:	ref Addr;
	op:	int;
	ival:	big;
	fval:	real;
	str:	string;
	sym:	ref Sym;
	listv:	ref List;
};

YYLEX: adt {
	lval:	YYSTYPE;
	EOF:	con -1;
	lex:	fn(l: self ref YYLEX): int;
	error:	fn(l: self ref YYLEX, msg: string);

	numsym:	fn(l: self ref YYLEX, first: int): int;
	eatstring:	fn(l: self ref YYLEX);
};

Eof: con -1;
False: con 0;
True: con 1;
Strsize: con 1024;
Hashsize: con 128;

Addr: adt
{
	mode:	int;
	off:	int;
	val:	int;
	sym:	ref Sym;

	text:	fn(a: self ref Addr): string;
};

List: adt
{
	link:	cyclic ref List;
	addr:	int;
	typ:	int;
	pick{
	Int =>	ival: big;	# DEFB, DEFW, DEFL
	Bytes =>	b: array of byte;	# DEFF, DEFS
	Array =>	a: ref Array;	# DEFA
	}
};

Inst: adt
{
	op:	int;
	typ:	int;
	size:	int;
	reg:	ref Addr;
	src:	ref Addr;
	dst:	ref Addr;
	pc:	int;
	sym:	ref Sym;
	link:	cyclic ref Inst;

	text:	fn(i: self ref Inst): string;
};

Sym: adt
{
	name:	string;
	lexval:	int;
	value:	int;
	ds:	int;
};

Desc: adt
{
	id:	int;
	size:	int;
	np:	int;
	map:	array of byte;
	link:	cyclic ref Desc;
};

Array: adt
{
	i:	int;
	size:	int;
};

Link: adt
{
	desc:	int;
	addr:	int;
	typ:	int;
	name:	string;
	link:	cyclic ref Link;
};

Keywd: adt
{
	name:	string;
	op:	int;
	terminal:	int;
};

Ldts: adt
{
	n:	int;
	ldt:	list of ref Ldt;
};

Ldt: adt
{
	sign:	int;
	name:	string;
};

Exc: adt
{
	n1, n2, n3, n4, n5, n6: int;
	etab: list of ref Etab;
};

Etab: adt
{
	n: int;
	name:	string;
};

Asm: module {

	init:	fn(nil: ref Draw->Context, nil: list of string);
TOKI0: con	57346;
TOKI1: con	57347;
TOKI2: con	57348;
TOKI3: con	57349;
TCONST: con	57350;
TOKSB: con	57351;
TOKFP: con	57352;
TOKHEAP: con	57353;
TOKDB: con	57354;
TOKDW: con	57355;
TOKDL: con	57356;
TOKDF: con	57357;
TOKDS: con	57358;
TOKVAR: con	57359;
TOKEXT: con	57360;
TOKMOD: con	57361;
TOKLINK: con	57362;
TOKENTRY: con	57363;
TOKARRAY: con	57364;
TOKINDIR: con	57365;
TOKAPOP: con	57366;
TOKLDTS: con	57367;
TOKEXCS: con	57368;
TOKEXC: con	57369;
TOKETAB: con	57370;
TOKSRC: con	57371;
TID: con	57372;
TFCONST: con	57373;
TSTRING: con	57374;

};
YYEOFCODE: con 1;
YYERRCODE: con 2;
YYMAXDEPTH: con 200;

#line	527	"asm.y"


kinit()
{
	for(i := 0; keywds[i].name != nil; i++) {
		s := enter(keywds[i].name, keywds[i].terminal);
		s.value = keywds[i].op;
	}

	enter("desc", TOKHEAP);
	enter("mp", TOKSB);
	enter("fp", TOKFP);

	enter("byte", TOKDB);
	enter("word", TOKDW);
	enter("long", TOKDL);
	enter("real", TOKDF);
	enter("string", TOKDS);
	enter("var", TOKVAR);
	enter("ext", TOKEXT);
	enter("module", TOKMOD);
	enter("link", TOKLINK);
	enter("entry", TOKENTRY);
	enter("array", TOKARRAY);
	enter("indir", TOKINDIR);
	enter("apop", TOKAPOP);
	enter("ldts", TOKLDTS);
	enter("exceptions", TOKEXCS);
	enter("exception", TOKEXC);
	enter("exctab", TOKETAB);
	enter("source", TOKSRC);

	cmap['0'] = '\0'+1;
	cmap['z'] = '\0'+1;
	cmap['n'] = '\n'+1;
	cmap['r'] = '\r'+1;
	cmap['t'] = '\t'+1;
	cmap['b'] = '\b'+1;
	cmap['f'] = '\f'+1;
	cmap['a'] = '\a'+1;
	cmap['v'] = '\v'+1;
	cmap['\\'] = '\\'+1;
	cmap['"'] = '"'+1;
}

Bgetc(b: ref Iobuf): int
{
	return b.getb();
}

Bungetc(b: ref Iobuf)
{
	b.ungetb();
}

Bgetrune(b: ref Iobuf): int
{
	return b.getc();
}

Bputc(b: ref Iobuf, c: int)
{
	b.putb(byte c);
}

strchr(s: string, c: int): string
{
	for(i := 0; i < len s; i++)
		if(s[i] == c)
			return s[i:];
	return nil;
}

escchar(c: int): int
{
	buf := array[32] of byte;
	if(c >= '0' && c <= '9') {
		n := 1;
		buf[0] = byte c;
		for(;;) {
			c = Bgetc(bin);
			if(c == Eof)
				fatal(sys->sprint("%d: <eof> in escape sequence", line));
			if(strchr("0123456789xX", c) == nil) {
				Bungetc(bin);
				break;
			}
			buf[n++] = byte c;
		}
		return int string buf[0:n];
	}

	n := cmap[c];
	if(n == 0)
		return c;
	return n-1;
}

strbuf := array[Strsize] of byte;

resizebuf()
{
	t := array[len strbuf+Strsize] of byte;
	t[0:] = strbuf;
	strbuf = t;
}

YYLEX.eatstring(l: self ref YYLEX)
{
	esc := 0;
Scan:
	for(cnt := 0;;) {
		c := Bgetc(bin);
		case c {
		Eof =>
			fatal(sys->sprint("%d: <eof> in string constant", line));

		'\n' =>
			line++;
			diag("newline in string constant");
			break Scan;

		'\\' =>
			if(esc) {
				if(cnt >= len strbuf)
					resizebuf();
				strbuf[cnt++] = byte c;
				esc = 0;
				break;
			}
			esc = 1;

		'"' =>
			if(esc == 0)
				break Scan;
			c = escchar(c);
			esc = 0;
			if(cnt >= len strbuf)
				resizebuf();
			strbuf[cnt++] = byte c;

		* =>
			if(esc) {
				c = escchar(c);
				esc = 0;
			}
			if(cnt >= len strbuf)
				resizebuf();
			strbuf[cnt++] = byte c;
		}
	}
	l.lval.str = string strbuf[0: cnt];
}

eatnl()
{
	line++;
	for(;;) {
		c := Bgetc(bin);
		if(c == Eof)
			diag("eof in comment");
		if(c == '\n')
			return;
	}
}

YYLEX.lex(l: self ref YYLEX): int
{
	for(;;){
		c := Bgetc(bin);
		case c {
		Eof =>
			return Eof;
		'"' =>
			l.eatstring();
			return TSTRING;
		' ' or
		'\t' or
		'\r' =>
			continue;
		'\n' =>
			line++;
		'.' =>
			c = Bgetc(bin);
			Bungetc(bin);
			if(isdigit(c))
				return l.numsym('.');
			return '.';
		'#' =>
			eatnl();
		'(' or
		')' or
		';' or
		',' or
		'~' or
		'$' or
		'+' or
		'/' or
		'%' or
		'^' or
		'*' or
		'&' or
		'=' or
		'|' or
		'<' or
		'>' or
		'-' or
		':' =>
			return c;
		'\'' =>
			c = Bgetrune(bin);
			if(c == '\\')
				l.lval.ival = big escchar(Bgetc(bin));
			else
				l.lval.ival = big c;
			c = Bgetc(bin);
			if(c != '\'') {
				diag("missing '");
				Bungetc(bin);
			}
			return TCONST;

		* =>
			return l.numsym(c);
		}
	}
}

isdigit(c: int): int
{
	return c >= '0' && c <= '9';
}

isxdigit(c: int): int
{
	return c >= '0' && c <= '9' || c >= 'a' && c <= 'f' || c >= 'A' && c <= 'F';
}

isalnum(c: int): int
{
	return c >= 'a' && c <= 'z' || c >= 'A' && c <= 'Z' || isdigit(c);
}

YYLEX.numsym(l: self ref YYLEX, first: int): int
{
	Int, Hex, Frac, Expsign, Exp: con iota;
	state: int;

	symbol[0] = byte first;
	p := 0;

	if(first == '.')
		state = Frac;
	else
		state = Int;

	c: int;
	if(isdigit(int symbol[p++]) || state == Frac) {
	Collect:
		for(;;) {
			c = Bgetc(bin);
			if(c < 0)
				fatal(sys->sprint("%d: <eof> eating numeric", line));

			case state {
			Int =>
				if(isdigit(c))
					break;
				case c {
				'x' or
				'X' =>
					c = 'x';
					state = Hex;
				'.' =>
					state = Frac;
				'e' or
				'E' =>
					c = 'e';
					state = Expsign;
				* =>
					break Collect;
				}
			Hex =>
				if(!isxdigit(c))
					break Collect;
			Frac =>
				if(isdigit(c))
					break;
				if(c != 'e' && c != 'E')
					break Collect;
				c = 'e';
				state = Expsign;
			Expsign =>
				state = Exp;
				if(c == '-' || c == '+')
					break;
				if(!isdigit(c))
					break Collect;
			Exp =>
				if(!isdigit(c))
					break Collect;
			}
			symbol[p++] = byte c;
		}

		# break Collect
		lastsym = string symbol[0:p];
		Bungetc(bin);
		case state {
		Frac or
		Expsign or
		Exp =>
			l.lval.fval = real lastsym;
			return TFCONST;
		* =>
			if(len lastsym >= 3 && lastsym[0:2] == "0x")
				(l.lval.ival, nil) = str->tobig(lastsym[2:], 16);
			else
				(l.lval.ival, nil) = str->tobig(lastsym, 10);
			return TCONST;
		}
	}

	for(;;) {
		c = Bgetc(bin);
		if(c < 0)
			fatal(sys->sprint("%d <eof> eating symbols", line));
		# '$' and '/' can occur in fully-qualified Java class names
		if(c != '_' && c != '.' && c != '/' && c != '$' && !isalnum(c)) {
			Bungetc(bin);
			break;
		}
		symbol[p++] = byte c;
	}

	lastsym = string symbol[0:p];
	s := enter(lastsym,TID);
	case s.lexval {
	TOKI0 or
	TOKI1 or
	TOKI2 or
	TOKI3 =>
		l.lval.op = s.value;
	* =>
		l.lval.sym = s;
	}
	return s.lexval;
}

hash := array[Hashsize] of list of ref Sym;

enter(name: string, stype: int): ref Sym
{
	s := lookup(name);
	if(s != nil)
		return s;

	h := 0;
	for(p := 0; p < len name; p++)
		h = h*3 + name[p];
	if(h < 0)
		h = ~h;
	h %= Hashsize;

	s = ref Sym(name, stype, 0, 0);
	hash[h] = s :: hash[h];
	return s;
}

lookup(name: string): ref Sym
{
	h := 0;
	for(p := 0; p < len name; p++)
		h = h*3 + name[p];
	if(h < 0)
		h = ~h;
	h %= Hashsize;

	for(l := hash[h]; l != nil; l = tl l)
		if((s := hd l).name == name)
			return s;
	return nil;
}

YYLEX.error(l: self ref YYLEX, s: string)
{
	if(s == "syntax error") {
		l.error(sys->sprint("syntax error, near symbol '%s'", lastsym));
		return;
	}
	sys->print("%s %d: %s\n", file, line, s);
	if(nerr++ > 10) {
		sys->fprint(sys->fildes(2), "%s:%d: too many errors, giving up\n", file, line);
		sys->remove(ofile);
		raise "fail: yyerror";
	}
}

fatal(s: string)
{
	sys->fprint(sys->fildes(2), "asm: %d (fatal compiler problem) %s\n", line, s);
	raise "fail:"+s;
}

diag(s: string)
{
	srcline := line;
	sys->fprint(sys->fildes(2), "%s:%d: %s\n", file, srcline, s);
	if(nerr++ > 10) {
		sys->fprint(sys->fildes(2), "%s:%d: too many errors, giving up\n", file, line);
		sys->remove(ofile);
		raise "fail: error";
	}
}

zinst: Inst;

ai(op: int): ref Inst
{
	i := ref zinst;
	i.op = op;

	return i;
}

aa(val: big): ref Addr
{
	if(val <= big -1073741824 && val > big 1073741823)
		diag("offset out of range");
	return ref Addr(0, 0, int val, nil);
}

isoff2big(o: int): int
{
	return o < 0 || o > 16rFFFF;
}

inldt := 0;
nldts := 0;
aldts: list of ref Ldts;
curl: ref Ldts;
nexcs := 0;
aexcs: list of ref Exc;
cure: ref Exc;
srcpath: string;

bin: ref Iobuf;
bout: ref Iobuf;

line := 0;
heapid := 0;
symbol := array[1024] of byte;
lastsym: string;
nerr := 0;
cmap := array[256] of int;
file: string;

dlist: ref Desc;
dcout := 0;
dseg := 0;
dcount := 0;

mdata: ref List;
amodule: ref Sym;
links: ref Link;
linkt: ref Link;
nlink := 0;
listing := 0;
mustcompile := 0;
dontcompile := 0;
ofile: string;
dentry := 0;
pcentry := 0;

init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	math = load Math Math->PATH;
	bufio = load Bufio Bufio->PATH;
	str = load String String->PATH;

	arg := load Arg Arg->PATH;
	arg->setusage("asm [-l] file.s");
	arg->init(args);
	while((c := arg->opt()) != 0){
		case c {
		'C' =>	dontcompile++;
		'c' =>	mustcompile++;
		'l' =>		listing++;
		* =>		arg->usage();
		}
	}
	args = arg->argv();
	if(len args != 1)
		arg->usage();
	arg = nil;

	kinit();
	pcentry = -1;
	dentry = -1;

	file = hd args;
	bin = bufio->open(file, Bufio->OREAD);
	if(bin == nil) {
		sys->fprint(sys->fildes(2), "asm: can't open %s: %r\n", file);
		raise "fail: errors";
	}
	p := strrchr(file, '/');
	if(p == nil)
		p = file;
	else
		p = p[1:];
	ofile = mkfile(p, ".s", ".dis");
	bout = bufio->create(ofile, Bufio->OWRITE, 8r666);
	if(bout == nil){
		sys->fprint(sys->fildes(2), "asm: can't create: %s: %r\n", ofile);
		raise "fail: errors";
	}
	line = 1;
	yyparse(ref YYLEX);
	bout.close();

	if(nerr != 0){
		sys->remove(ofile);
		raise "fail: errors";
	}
}

strrchr(s: string, c: int): string
{
	for(i := len s; --i >= 0;)
		if(s[i] == c)
			return s[i:];
	return nil;
}

mkfile(file: string, oldext: string, ext: string): string
{
	n := len file;
	n2 := len oldext;
	if(n >= n2 && file[n-n2:] == oldext)
		n -= n2;
	return file[0:n] + ext;
}

opcode(i: ref Inst): int
{
	if(i.op < 0 || i.op >= len keywds)
		fatal(sys->sprint("internal error: invalid op %d (%#x)", i.op, i.op));
	return keywds[i.op].op;
}

Inst.text(i: self ref Inst): string
{
	if(i == nil)
		return "IZ";

	case keywds[i.op].terminal {
	TOKI0 =>
		return sys->sprint("%s", keywds[i.op].name);
	TOKI1 =>
		return sys->sprint("%s\t%s", keywds[i.op].name, i.dst.text());
	TOKI3 =>
		if(i.reg != nil) {
			pre := "";
			post := "";
			case i.reg.mode {
			AXIMM =>
				pre = "$";
				break;
			AXINF =>
				post = "(fp)";
				break;
			AXINM =>
				post = "(mp)";
			 	break;
			}
			return sys->sprint("%s\t%s, %s%d%s, %s", keywds[i.op].name, i.src.text(), pre, i.reg.val, post, i.dst.text());
		}
		return sys->sprint("%s\t%s, %s", keywds[i.op].name, i.src.text(), i.dst.text());
	TOKI2 =>
		return sys->sprint("%s\t%s, %s", keywds[i.op].name, i.src.text(), i.dst.text());
	* =>
		return "IGOK";
	}
}

Addr.text(a: self ref Addr): string
{
	if(a == nil)
		return "AZ";

	if(a.mode & AIND) {		
		case a.mode & ~AIND {
		AFP =>
			return sys->sprint("%d(%d(fp))", a.val, a.off);
		AMP =>
			return sys->sprint("%d(%d(mp))", a.val, a.off);
		}
	}
	else {
		case a.mode {
		AFP =>
			return sys->sprint("%d(fp)", a.val);
		AMP =>
			return sys->sprint("%d(mp)", a.val);
		AIMM =>
			return sys->sprint("$%d", a.val);
		}
	}

	return "AGOK";
}

append[T](l: list of T, v: T): list of T
{
	if(l == nil)
		return v :: nil;
	return hd l :: append(tl l, v);
}

newa(i: int, size: int): ref List
{
	a := ref Array(i, size);
	l := ref List.Array(nil, -1, 0, a);
	return l;
}

# does order matter?
newi(v: big, l: ref List): ref List
{
	n := ref List.Int(nil, -1, 0, v);
	if(l == nil)
		return n;

	for(t := l; t.link != nil; t = t.link)
		;
	t.link = n;

	return l;
}

news(s: string, l: ref List): ref List
{
	return ref List.Bytes(l, -1, 0, array of byte s);
}

newb(a: array of byte, l: ref List): ref List
{
	return ref List.Bytes(l, -1, 0, a);
}

digit(x: int): int
{
	if(x >= 'A' && x <= 'F')
		return x - 'A' + 10;
	if(x >= 'a' && x <= 'f')
		return x - 'a' + 10;
	if(x >= '0' && x <= '9')
		return x - '0';
	diag("bad hex value in pointers");
	return 0;
}

heap(id: int, size: int, ptr: string)
{
	d := ref Desc;
	d.id = id;
	d.size = size;
	size /= IBY2WD;
	d.map = array[size] of {* => byte 0};
	d.np = 0;
	if(dlist == nil)
		dlist = d;
	else {
		f: ref Desc;
		for(f = dlist; f.link != nil; f = f.link)
			;
		f.link = d;
	}
	d.link = nil;
	dcount++;

	if(ptr == nil)
		return;
	if(len ptr & 1) {
		diag("pointer descriptor has odd length");
		return;	
	}

	k := 0;
	l := len ptr;
	for(i := 0; i < l; i += 2) {
		d.map[k++] = byte ((digit(ptr[i])<<4)|digit(ptr[i+1]));
		if(k > size) {
			diag("pointer descriptor too long");
			break;
		}
	}
	d.np = k;
}

conout(val: int)
{
	if(val >= -64 && val <= 63) {
		Bputc(bout, val & ~16r80);
		return;
	}
	if(val >= -8192 && val <= 8191) {
		Bputc(bout, ((val>>8) & ~16rC0) | 16r80);
		Bputc(bout, val);
		return;
	}
	if(val < 0 && ((val >> 29) & 7) != 7
	|| val > 0 && (val >> 29) != 0)
		diag(sys->sprint("overflow in constant 0x%ux\n", val));
	Bputc(bout, (val>>24) | 16rC0);
	Bputc(bout, val>>16);
	Bputc(bout, val>>8);
	Bputc(bout, val);
}

aout(a: ref Addr)
{
	if(a == nil)
		return;
	if(a.mode & AIND)
		conout(a.off);
	conout(a.val);
}

Bputs(b: ref Iobuf, s: string)
{
	for(i := 0; i < len s; i++)
		Bputc(b, s[i]);
	Bputc(b, '\0');
}

lout()
{
	if(amodule == nil)
		amodule = enter("main", 0);

	Bputs(bout, amodule.name);

	for(l := links; l != nil; l = l.link) {
		conout(l.addr);
		conout(l.desc);
		Bputc(bout, l.typ>>24);
		Bputc(bout, l.typ>>16);
		Bputc(bout, l.typ>>8);
		Bputc(bout, l.typ);
		Bputs(bout, l.name);
	}
}

ldtout()
{
	conout(nldts);
	for(la := aldts; la != nil; la = tl la){
		ls := hd la;
		conout(ls.n);
		for(l := ls.ldt; l != nil; l = tl l){
			t := hd l;
			Bputc(bout, t.sign>>24);
			Bputc(bout, t.sign>>16);
			Bputc(bout, t.sign>>8);
			Bputc(bout, t.sign);
			Bputs(bout, t.name);
		}
	}
	conout(0);
}

excout()
{
	if(nexcs == 0)
		return;
	conout(nexcs);
	for(es := aexcs; es != nil; es = tl es){
		e := hd es;
		conout(e.n3);
		conout(e.n1);
		conout(e.n2);
		conout(e.n4);
		conout(e.n5|(e.n6<<16));
		for(ets := e.etab; ets != nil; ets = tl ets){
			et := hd ets;
			if(et.name != nil)
				Bputs(bout, et.name);
			conout(et.n);
		}
	}
	conout(0);
}

srcout()
{
	if(srcpath == nil)
		return;
	Bputs(bout, srcpath);
}

assem(i: ref Inst)
{
	f: ref Inst;
	while(i != nil){
		link := i.link;
		i.link = f;
		f = i;
		i = link;
	}
	i = f;

	pc := 0;
	for(f = i; f != nil; f = f.link) {
		f.pc = pc++;
		if(f.sym != nil)
			f.sym.value = f.pc;
	}

	if(pcentry >= pc)
		diag("entry pc out of range");
	if(dentry >= dcount)
		diag("entry descriptor out of range");

	conout(XMAGIC);
	hints := 0;
	if(mustcompile)
		hints |= MUSTCOMPILE;
	if(dontcompile)
		hints |= DONTCOMPILE;
	hints |= HASLDT;
	if(nexcs > 0)
		hints |= HASEXCEPT;
	conout(hints);		# Runtime flags
	conout(1024);		# default stack size
	conout(pc);
	conout(dseg);
	conout(dcount);
	conout(nlink);
	conout(pcentry);
	conout(dentry);

	for(f = i; f != nil; f = f.link) {
		if(f.dst != nil && f.dst.sym != nil) {
			f.dst.mode = AIMM;
			f.dst.val = f.dst.sym.value;
		}
		o := opcode(f);
		if(o == IRAISE){
			f.src = f.dst;
			f.dst = nil;
		}
		Bputc(bout, o);
		n := 0;
		if(f.src != nil)
			n |= src(f.src.mode);
		else
			n |= src(AXXX);
		if(f.dst != nil)
			n |= dst(f.dst.mode);
		else
			n |= dst(AXXX);
		if(f.reg != nil)
			n |= f.reg.mode;
		else
			n |= AXNON;
		Bputc(bout, n);
		aout(f.reg);
		aout(f.src);
		aout(f.dst);

		if(listing)
			sys->print("%4d %s\n", f.pc, f.text());
	}

	for(d := dlist; d != nil; d = d.link) {
		conout(d.id);
		conout(d.size);
		conout(d.np);
		for(n := 0; n < d.np; n++)
			Bputc(bout, int d.map[n]);
	}

	dout();
	lout();
	ldtout();
	excout();
	srcout();
}

data(typ: int, addr: big, l: ref List)
{
	if(inldt){
		ldtw(int intof(l));
		return;
	}

	l.typ = typ;
	l.addr = int addr;

	if(mdata == nil)
		mdata = l;
	else {
		for(f := mdata; f.link != nil; f = f.link)
			;
		f.link = l;
	}
}

ext(addr: int, typ: int, s: string)
{
	if(inldt){
		ldte(typ, s);
		return;
	}

	data(DEFW, big addr, newi(big typ, nil));

	n: ref List;
	for(i := 0; i < len s; i++)
		n = newi(big s[i], n);
	data(DEFB, big(addr+IBY2WD), n);

	if(addr+len s > dseg)
		diag("ext beyond mp");
}

mklink(desc: int, addr: int, typ: int, s: string)
{
	for(ls := links; ls != nil; ls = ls.link)
		if(ls.name == s)
			diag(sys->sprint("%s already defined", s));

	nlink++;
	l := ref Link;
	l.desc = desc;
	l.addr = addr;
	l.typ = typ;
	l.name = s;
	l.link = nil;

	if(links == nil)
		links = l;
	else
		linkt.link = l;
	linkt = l;
}

intof(l: ref List): big
{
	pick rl := l {
	Int =>
		return rl.ival;
	* =>
		raise "list botch";
	}
}

arrayof(l: ref List): ref Array
{
	pick rl := l {
	Array =>
		return rl.a;
	* =>
		raise "list botch";
	}
}

bytesof(l: ref List): array of byte
{
	pick rl := l {
	Bytes =>
		return rl.b;
	* =>
		raise "list botch";
	}
}

nel(l: ref List): (int, ref List)
{
	n := 1;
	for(e := l.link; e != nil && e.addr == -1; e = e.link)
		n++;
	return (n, e);
}

dout()
{
	e: ref List;
	n: int;
	for(l := mdata; l != nil; l = e) {
		case l.typ {
		DEFB =>
			(n, e) = nel(l);
			if(n < DMAX)
				Bputc(bout, dbyte(DEFB, n));
			else {
				Bputc(bout, dbyte(DEFB, 0));
				conout(n);
			}
			conout(l.addr);
			while(l != e) {
				Bputc(bout, int intof(l));
				l = l.link;
			}
			break;
		DEFW =>
			(n, e) = nel(l);
			if(n < DMAX)
				Bputc(bout, dbyte(DEFW, n));
			else {
				Bputc(bout, dbyte(DEFW, 0));
				conout(n);
			}
			conout(l.addr);
			while(l != e) {
				n = int intof(l);
				Bputc(bout, n>>24);
				Bputc(bout, n>>16);
				Bputc(bout, n>>8);
				Bputc(bout, n);
				l = l.link;
			}
			break;
		DEFL =>
			(n, e) = nel(l);
			if(n < DMAX)
				Bputc(bout, dbyte(DEFL, n));
			else {
				Bputc(bout, dbyte(DEFL, 0));
				conout(n);
			}
			conout(l.addr);
			while(l != e) {
				b := intof(l);
				Bputc(bout, int (b>>56));
				Bputc(bout, int (b>>48));
				Bputc(bout, int (b>>40));
				Bputc(bout, int (b>>32));
				Bputc(bout, int (b>>24));
				Bputc(bout, int (b>>16));
				Bputc(bout, int (b>>8));
				Bputc(bout, int b);
				l = l.link;
			}
			break;
		DEFF =>
			(n, e) = nel(l);
			if(n < DMAX)
				Bputc(bout, dbyte(DEFF, n));
			else {
				Bputc(bout, dbyte(DEFF, 0));
				conout(n);
			}
			conout(l.addr);
			while(l != e) {
				b := bytesof(l);
				Bputc(bout, int b[0]);
				Bputc(bout, int b[1]);
				Bputc(bout, int b[2]);
				Bputc(bout, int b[3]);
				Bputc(bout, int b[4]);
				Bputc(bout, int b[5]);
				Bputc(bout, int b[6]);
				Bputc(bout, int b[7]);
				l = l.link;
			}
			break;
		DEFS =>
			a := bytesof(l);
			n = len a;
			if(n < DMAX && n != 0)
				Bputc(bout, dbyte(DEFS, n));
			else {
				Bputc(bout, dbyte(DEFS, 0));
				conout(n);
			}
			conout(l.addr);
			for(i := 0; i < n; i++)
				Bputc(bout, int a[i]);

			e = l.link;
			break;
		DEFA =>
			Bputc(bout, dbyte(DEFA, 1));
			conout(l.addr);
			ar := arrayof(l);
			Bputc(bout, ar.i>>24);
			Bputc(bout, ar.i>>16);
			Bputc(bout, ar.i>>8);
			Bputc(bout, ar.i);
			Bputc(bout, ar.size>>24);
			Bputc(bout, ar.size>>16);
			Bputc(bout, ar.size>>8);
			Bputc(bout, ar.size);
			e = l.link;
			break;
		DIND =>
			Bputc(bout, dbyte(DIND, 1));
			conout(l.addr);
			Bputc(bout, 0);
			Bputc(bout, 0);
			Bputc(bout, 0);
			Bputc(bout, 0);
			e = l.link;
			break;
		DAPOP =>
			Bputc(bout, dbyte(DAPOP, 1));
			conout(0);
			e = l.link;
			break;
		}
	}

	Bputc(bout, dbyte(DEFZ, 0));
}

ldts(n: int)
{
	nldts = n;
	inldt = 1;
}

ldtw(n: int)
{
	ls := ref Ldts(n, nil);
	aldts = append(aldts, ls);
	curl = ls;
}

ldte(n: int, s: string)
{
	l := ref Ldt(n, s);
	curl.ldt = append(curl.ldt, l);
}

excs(n: int)
{
	nexcs = n;
}

exc(n1: int, n2: int, n3: int, n4: int, n5: int, n6: int)
{
	e := ref Exc;
	e.n1 = n1;
	e.n2 = n2;
	e.n3 = n3;
	e.n4 = n4;
	e.n5 = n5;
	e.n6 = n6;
	e.etab = nil;
	aexcs = append(aexcs, e);
	cure = e;
}

etab(s: string, n: int)
{
	et := ref Etab;
	et.n = n;
	et.name = s;
	cure.etab = append(cure.etab, et);
}

source(s: string)
{
	srcpath = s;
}

dtype(x: int): int
{
	return (x>>4)&16rF;
}

dbyte(x: int, l: int): int
{
	return (x<<4) | l;
}

dlen(x: int): int
{
	return x & (DMAX-1);
}

src(x: int): int
{
	return x<<3;
}

dst(x: int): int
{
	return x<<0;
}

dtocanon(d: real): array of byte
{
	b := array[8] of byte;
	export_real(b, array[] of {d});
	return b;
}

keywds: array of Keywd = array[] of
{
	("nop",		INOP,		TOKI0),
	("alt",		IALT,		TOKI3),
	("nbalt",	INBALT,		TOKI3),
	("goto",		IGOTO,		TOKI2),
	("call",		ICALL,		TOKI2),
	("frame",	IFRAME,		TOKI2),
	("spawn",	ISPAWN,		TOKI2),
	("runt",		IRUNT,		TOKI2),
	("load",		ILOAD,		TOKI3),
	("mcall",	IMCALL,		TOKI3),
	("mspawn",	IMSPAWN,	TOKI3),
	("mframe",	IMFRAME,	TOKI3),
	("ret",		IRET,		TOKI0),
	("jmp",		IJMP,		TOKI1),
	("case",		ICASE,		TOKI2),
	("exit",		IEXIT,		TOKI0),
	("new",		INEW,		TOKI2),
	("newa",		INEWA,		TOKI3),
	("newcb",	INEWCB,		TOKI1),
	("newcw",	INEWCW,		TOKI1),
	("newcf",	INEWCF,		TOKI1),
	("newcp",	INEWCP,		TOKI1),
	("newcm",	INEWCM,		TOKI2),
	("newcmp",	INEWCMP,	TOKI2),
	("send",		ISEND,		TOKI2),
	("recv",		IRECV,		TOKI2),
	("consb",	ICONSB,		TOKI2),
	("consw",	ICONSW,		TOKI2),
	("consp",	ICONSP,		TOKI2),
	("consf",	ICONSF,		TOKI2),
	("consm",	ICONSM,		TOKI3),
	("consmp",	ICONSMP,	TOKI3),
	("headb",	IHEADB,		TOKI2),
	("headw",	IHEADW,		TOKI2),
	("headp",	IHEADP,		TOKI2),
	("headf",	IHEADF,		TOKI2),
	("headm",	IHEADM,		TOKI3),
	("headmp",	IHEADMP,	TOKI3),
	("tail",		ITAIL,		TOKI2),
	("lea",		ILEA,		TOKI2),
	("indx",		IINDX,		TOKI3),
	("movp",		IMOVP,		TOKI2),
	("movm",		IMOVM,		TOKI3),
	("movmp",	IMOVMP,		TOKI3),
	("movb",		IMOVB,		TOKI2),
	("movw",		IMOVW,		TOKI2),
	("movf",		IMOVF,		TOKI2),
	("cvtbw",	ICVTBW,		TOKI2),
	("cvtwb",	ICVTWB,		TOKI2),
	("cvtfw",	ICVTFW,		TOKI2),
	("cvtwf",	ICVTWF,		TOKI2),
	("cvtca",	ICVTCA,		TOKI2),
	("cvtac",	ICVTAC,		TOKI2),
	("cvtwc",	ICVTWC,		TOKI2),
	("cvtcw",	ICVTCW,		TOKI2),
	("cvtfc",	ICVTFC,		TOKI2),
	("cvtcf",	ICVTCF,		TOKI2),
	("addb",		IADDB,		TOKI3),
	("addw",		IADDW,		TOKI3),
	("addf",		IADDF,		TOKI3),
	("subb",		ISUBB,		TOKI3),
	("subw",		ISUBW,		TOKI3),
	("subf",		ISUBF,		TOKI3),
	("mulb",		IMULB,		TOKI3),
	("mulw",		IMULW,		TOKI3),
	("mulf",		IMULF,		TOKI3),
	("divb",		IDIVB,		TOKI3),
	("divw",		IDIVW,		TOKI3),
	("divf",		IDIVF,		TOKI3),
	("modw",		IMODW,		TOKI3),
	("modb",		IMODB,		TOKI3),
	("andb",		IANDB,		TOKI3),
	("andw",		IANDW,		TOKI3),
	("orb",		IORB,		TOKI3),
	("orw",		IORW,		TOKI3),
	("xorb",		IXORB,		TOKI3),
	("xorw",		IXORW,		TOKI3),
	("shlb",		ISHLB,		TOKI3),
	("shlw",		ISHLW,		TOKI3),
	("shrb",		ISHRB,		TOKI3),
	("shrw",		ISHRW,		TOKI3),
	("insc",		IINSC,		TOKI3),
	("indc",		IINDC,		TOKI3),
	("addc",		IADDC,		TOKI3),
	("lenc",		ILENC,		TOKI2),
	("lena",		ILENA,		TOKI2),
	("lenl",		ILENL,		TOKI2),
	("beqb",		IBEQB,		TOKI3),
	("bneb",		IBNEB,		TOKI3),
	("bltb",		IBLTB,		TOKI3),
	("bleb",		IBLEB,		TOKI3),
	("bgtb",		IBGTB,		TOKI3),
	("bgeb",		IBGEB,		TOKI3),
	("beqw",		IBEQW,		TOKI3),
	("bnew",		IBNEW,		TOKI3),
	("bltw",		IBLTW,		TOKI3),
	("blew",		IBLEW,		TOKI3),
	("bgtw",		IBGTW,		TOKI3),
	("bgew",		IBGEW,		TOKI3),
	("beqf",		IBEQF,		TOKI3),
	("bnef",		IBNEF,		TOKI3),
	("bltf",		IBLTF,		TOKI3),
	("blef",		IBLEF,		TOKI3),
	("bgtf",		IBGTF,		TOKI3),
	("bgef",		IBGEF,		TOKI3),
	("beqc",		IBEQC,		TOKI3),
	("bnec",		IBNEC,		TOKI3),
	("bltc",		IBLTC,		TOKI3),
	("blec",		IBLEC,		TOKI3),
	("bgtc",		IBGTC,		TOKI3),
	("bgec",		IBGEC,		TOKI3),
	("slicea",	ISLICEA,	TOKI3),
	("slicela",	ISLICELA,	TOKI3),
	("slicec",	ISLICEC,	TOKI3),
	("indw",		IINDW,		TOKI3),
	("indf",		IINDF,		TOKI3),
	("indb",		IINDB,		TOKI3),
	("negf",		INEGF,		TOKI2),
	("movl",		IMOVL,		TOKI2),
	("addl",		IADDL,		TOKI3),
	("subl",		ISUBL,		TOKI3),
	("divl",		IDIVL,		TOKI3),
	("modl",		IMODL,		TOKI3),
	("mull",		IMULL,		TOKI3),
	("andl",		IANDL,		TOKI3),
	("orl",		IORL,		TOKI3),
	("xorl",		IXORL,		TOKI3),
	("shll",		ISHLL,		TOKI3),
	("shrl",		ISHRL,		TOKI3),
	("bnel",		IBNEL,		TOKI3),
	("bltl",		IBLTL,		TOKI3),
	("blel",		IBLEL,		TOKI3),
	("bgtl",		IBGTL,		TOKI3),
	("bgel",		IBGEL,		TOKI3),
	("beql",		IBEQL,		TOKI3),
	("cvtlf",	ICVTLF,		TOKI2),
	("cvtfl",	ICVTFL,		TOKI2),
	("cvtlw",	ICVTLW,		TOKI2),
	("cvtwl",	ICVTWL,		TOKI2),
	("cvtlc",	ICVTLC,		TOKI2),
	("cvtcl",	ICVTCL,		TOKI2),
	("headl",	IHEADL,		TOKI2),
	("consl",	ICONSL,		TOKI2),
	("newcl",	INEWCL,		TOKI1),
	("casec",	ICASEC,		TOKI2),
	("indl",		IINDL,		TOKI3),
	("movpc",	IMOVPC,		TOKI2),
	("tcmp",		ITCMP,		TOKI2),
	("mnewz",	IMNEWZ,		TOKI3),
	("cvtrf",	ICVTRF,		TOKI2),
	("cvtfr",	ICVTFR,		TOKI2),
	("cvtws",	ICVTWS,		TOKI2),
	("cvtsw",	ICVTSW,		TOKI2),
	("lsrw",		ILSRW,		TOKI3),
	("lsrl",		ILSRL,		TOKI3),
	("eclr",		IECLR,		TOKI0),
	("newz",		INEWZ,		TOKI2),
	("newaz",	INEWAZ,		TOKI3),
	("raise",	IRAISE,	TOKI1),
	("casel",	ICASEL,	TOKI2),
	("mulx",	IMULX,	TOKI3),
	("divx",	IDIVX,	TOKI3),
	("cvtxx",	ICVTXX,	TOKI3),
	("mulx0",	IMULX0,	TOKI3),
	("divx0",	IDIVX0,	TOKI3),
	("cvtxx0",	ICVTXX0,	TOKI3),
	("mulx1",	IMULX1,	TOKI3),
	("divx1",	IDIVX1,	TOKI3),
	("cvtxx1",	ICVTXX1,	TOKI3),
	("cvtfx",	ICVTFX,	TOKI3),
	("cvtxf",	ICVTXF,	TOKI3),
	("expw",	IEXPW,	TOKI3),
	("expl",	IEXPL,	TOKI3),
	("expf",	IEXPF,	TOKI3),
	("self",	ISELF,	TOKI1),
	(nil,	0, 0),
};
yyexca := array[] of {-1, 1,
	1, -1,
	-2, 0,
-1, 61,
	4, 54,
	5, 54,
	6, 54,
	7, 54,
	8, 54,
	9, 54,
	10, 54,
	11, 54,
	12, 54,
	13, 54,
	46, 54,
	-2, 46,
-1, 140,
	44, 44,
	-2, 50,
-1, 159,
	44, 43,
	-2, 45,
};
YYNPROD: con 70;
YYPRIVATE: con 57344;
yytoknames: array of string;
yystates: array of string;
include "y.debug";
yydebug: con 1;
YYLAST:	con 561;
yyact := array[] of {
  64,  59, 107,  65, 162, 161,  31, 160, 158,  34,
  42,  43,  44,  45, 156,  47,  48,  33,  50,  51,
  52,  30,  32,  54,  55, 148,  39,  38,  63,  66,
  67, 105, 100,  70,  99,  36,  98,  96,  90,  69,
  57, 172,  85,  81,  80,  79,  77,  78,  72,  73,
  74,  75,  76, 165, 163, 126, 151,  61,  58,  53,
  49, 101,  60,  41, 103,  40,  46, 102, 143, 144,
 106,  56, 108, 109, 110, 111, 112, 113, 153, 152,
 116, 117, 118,   7, 115, 114, 119, 108, 108, 120,
 121, 127, 128, 129, 130,   6, 132, 133, 134, 135,
 136, 131, 137,   1, 140, 103,  35, 145, 142, 146,
  29,  28,  27,  26,  68, 149, 150,   5,   8,   9,
  10,  11,  12,  13,  14,  16,  15,  17,  18,  19,
  20,  21,  22,  23,  24,  25,   4,  74,  75,  76,
 159,  62, 138, 125,   2,  82,  83,  84,   3, 164,
   0, 122,  29,  28,  27,  26, 166, 167, 168,   0,
 169,  81,  80,  79,  77,  78,  72,  73,  74,  75,
  76,   0, 173, 124, 123, 175,   0, 177,  81,  80,
  79,  77,  78,  72,  73,  74,  75,  76,  39,  38,
   0,   0,  39,  38,  63,   0,   0,  36, 143, 144,
   0,  36,   0, 141,  81,  80,  79,  77,  78,  72,
  73,  74,  75,  76,  72,  73,  74,  75,  76,  37,
 104,   0,   0,  61,   0,  41,   0,  40, 139,  41,
   0,  40,  81,  80,  79,  77,  78,  72,  73,  74,
  75,  76,   0,   0, 176,  81,  80,  79,  77,  78,
  72,  73,  74,  75,  76,  81,  80,  79,  77,  78,
  72,  73,  74,  75,  76,  77,  78,  72,  73,  74,
  75,  76, 174,  81,  80,  79,  77,  78,  72,  73,
  74,  75,  76,   0,   0, 171,  80,  79,  77,  78,
  72,  73,  74,  75,  76, 170,  81,  80,  79,  77,
  78,  72,  73,  74,  75,  76,   0,   0,   0,   0,
   0,   0,   0, 157,  81,  80,  79,  77,  78,  72,
  73,  74,  75,  76,  81,  80,  79,  77,  78,  72,
  73,  74,  75,  76,   0,   0, 155,  81,  80,  79,
  77,  78,  72,  73,  74,  75,  76,   0,   0,   0,
   0,   0,   0,   0, 154,  79,  77,  78,  72,  73,
  74,  75,  76,   0, 147,  81,  80,  79,  77,  78,
  72,  73,  74,  75,  76,   0,   0,  97,  81,  80,
  79,  77,  78,  72,  73,  74,  75,  76,  81,  80,
  79,  77,  78,  72,  73,  74,  75,  76,   0,   0,
   0,   0,   0,   0,   0,  95,  81,  80,  79,  77,
  78,  72,  73,  74,  75,  76,   0,   0,  94,   0,
   0,   0,   0,   0,   0,   0,   0,   0,  93,  81,
  80,  79,  77,  78,  72,  73,  74,  75,  76,   0,
   0,   0,   0,   0,   0,   0,  92,  81,  80,  79,
  77,  78,  72,  73,  74,  75,  76,  81,  80,  79,
  77,  78,  72,  73,  74,  75,  76,   0,   0,  91,
  81,  80,  79,  77,  78,  72,  73,  74,  75,  76,
   0,   0,   0,   0,   0,   0,   0,  89,   0,   0,
   0,   0,   0,   0,   0,   0,   0,  88,  81,  80,
  79,  77,  78,  72,  73,  74,  75,  76,   0,   0,
  87,  81,  80,  79,  77,  78,  72,  73,  74,  75,
  76,  39,  38,   0,   0,   0,   0,   0,   0,   0,
  36,   0,   0,   0,   0,   0,   0,   0,  86,  81,
  80,  79,  77,  78,  72,  73,  74,  75,  76,   0,
   0,  71,  37,   0,   0,   0,   0,   0,  41,   0,
  40,
};
yypact := array[] of {
-1000,-1000,  96,-1000, -22, -23,-1000,-1000, 512, 512,
 512, 512, 512,  26, 512, 512,  20, 512, 512, 512,
-1000,  19, 512, 512,  29,  16,  17,  17,  17,-1000,
 138,  -5, 512,-1000, 507,-1000,-1000,-1000, 512, 512,
 512, 512, 494, 466, 453, 443,  -6, 425, 402,-1000,
 384, 374, 361,  -7, 535, 333,  -8, -10,-1000, -12,
 512,-1000,-1000, 512, 174,-1000, -13,-1000,-1000, 512,
 535, 512, 512, 512, 512, 512, 512,  78,  76, 512,
 512, 512,-1000,-1000,-1000,  39, 512, 512, 133,  13,
 512, 512, 512, 512, -23, 512, 512, 512, 512, 512,
 183, 535,-1000, 157, 179,  17, 320, -19, 535, 126,
 126,-1000,-1000,-1000, 512, 512, 258, 349, 281,-1000,
 -19, -19,-1000,-1000,-1000,  38,-1000, 535, 310, 292,
 535, -30, 535, 535, 269, 535, 535,-1000, -36, 512,
-1000,  49, -40, -42, -43,-1000,-1000,  12, 512, 205,
 205,-1000,-1000,-1000,  11, 512, 512, 512,  17, 535,
-1000,-1000,-1000,-1000, 535,-1000, 251, 535, 241,-1000,
  -1, 512,-1000, 228, 512, 200, 512, 535,
};
yypgo := array[] of {
   0, 148, 144,  83, 106,   0,   6,   1, 142, 141,
   3,   2, 109, 103,  95,
};
yyr1 := array[] of {
   0,  13,   2,   2,   1,   1,   1,   1,   6,   6,
  12,  12,  11,  11,   3,   3,   3,   3,   3,  14,
  14,  14,  14,  14,  14,  14,  14,  14,  14,  14,
  14,  14,  14,  14,  14,  14,  14,  14,  14,  14,
  14,  14,  14,   8,   8,   7,   7,   7,   9,   9,
   9,  10,  10,   4,   4,   4,   4,   4,   4,   5,
   5,   5,   5,   5,   5,   5,   5,   5,   5,   5,
};
yyr2 := array[] of {
   0,   1,   0,   2,   3,   5,   1,   1,   2,   1,
   0,   2,   1,   3,   4,   6,   4,   2,   1,   4,
   4,   4,   4,   4,   4,   5,   5,   5,   4,   4,
   6,   8,   2,   4,   6,   4,   1,   4,   2,  12,
   4,   4,   2,   2,   1,   2,   1,   1,   2,   4,
   1,   4,   4,   1,   1,   2,   2,   2,   3,   1,
   3,   3,   3,   3,   3,   4,   4,   3,   3,   3,
};
yychk := array[] of {
-1000, -13,  -2,  -1,  40,  21, -14,  -3,  22,  23,
  24,  25,  26,  27,  28,  30,  29,  31,  32,  33,
  34,  35,  36,  37,  38,  39,  17,  16,  15,  14,
  43,  -6,  45,  40,  -5,  -4,  18,  40,  10,   9,
  48,  46,  -5,  -5,  -5,  -5,  40,  -5,  -5,  40,
  -5,  -5,  -5,  40,  -5,  -5,  42,  11,  42,  -7,
  45,  40,  -9,  11,  -5, -10,  -7,  -7,  -3,  44,
  -5,  44,   9,  10,  11,  12,  13,   7,   8,   6,
   5,   4,  -4,  -4,  -4,  -5,  44,  44,  44,  44,
  44,  44,  44,  44,  44,  44,  44,  44,  44,  44,
  44,  -5, -10,  -5,  46,  44,  -5, -11,  -5,  -5,
  -5,  -5,  -5,  -5,   7,   8,  -5,  -5,  -5,  47,
 -11, -11,  18,  41,  40,  10,  42,  -5,  -5,  -5,
  -5,  -6,  -5,  -5,  -5,  -5,  -5,  -7,  -8,  45,
 -10,  46, -10,  19,  20,  -7, -12,  44,  44,  -5,
  -5,  18,  41,  40,  44,  44,  44,  44,  44,  -5,
  47,  47,  47,  42,  -5,  42,  -5,  -5,  -5,  -7,
  44,  44,  42,  -5,  44,  -5,  44,  -5,
};
yydef := array[] of {
   2,  -2,   1,   3,   0,   0,   6,   7,   0,   0,
   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,
  36,   0,   0,   0,   0,   0,   0,   0,   0,  18,
   0,   0,   0,   9,   0,  59,  53,  54,   0,   0,
   0,   0,   0,   0,   0,   0,   0,   0,   0,  32,
   0,   0,   0,   0,  38,   0,   0,   0,  42,   0,
   0,  -2,  47,   0,   0,  50,   0,  17,   4,   0,
   8,   0,   0,   0,   0,   0,   0,   0,   0,   0,
   0,   0,  55,  56,  57,   0,   0,   0,   0,   0,
   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,
   0,  45,  48,   0,   0,   0,  10,  19,  12,  60,
  61,  62,  63,  64,   0,   0,  67,  68,  69,  58,
  20,  21,  22,  23,  24,   0,  28,  29,   0,   0,
  33,   0,  35,  37,   0,  40,  41,  14,   0,   0,
  -2,   0,   0,   0,   0,  16,   5,   0,   0,  65,
  66,  25,  26,  27,   0,   0,   0,   0,   0,  -2,
  49,  51,  52,  11,  13,  30,   0,  34,   0,  15,
   0,   0,  31,   0,   0,   0,   0,  39,
};
yytok1 := array[] of {
   1,   3,   3,   3,   3,   3,   3,   3,   3,   3,
   3,   3,   3,   3,   3,   3,   3,   3,   3,   3,
   3,   3,   3,   3,   3,   3,   3,   3,   3,   3,
   3,   3,   3,   3,   3,   3,  45,  13,   6,   3,
  46,  47,  11,   9,  44,  10,   3,  12,   3,   3,
   3,   3,   3,   3,   3,   3,   3,   3,  43,   3,
   7,   3,   8,   3,   3,   3,   3,   3,   3,   3,
   3,   3,   3,   3,   3,   3,   3,   3,   3,   3,
   3,   3,   3,   3,   3,   3,   3,   3,   3,   3,
   3,   3,   3,   3,   5,   3,   3,   3,   3,   3,
   3,   3,   3,   3,   3,   3,   3,   3,   3,   3,
   3,   3,   3,   3,   3,   3,   3,   3,   3,   3,
   3,   3,   3,   3,   4,   3,  48,
};
yytok2 := array[] of {
   2,   3,  14,  15,  16,  17,  18,  19,  20,  21,
  22,  23,  24,  25,  26,  27,  28,  29,  30,  31,
  32,  33,  34,  35,  36,  37,  38,  39,  40,  41,
  42,
};
yytok3 := array[] of {
   0
};

YYSys: module
{
	FD: adt
	{
		fd:	int;
	};
	fildes:		fn(fd: int): ref FD;
	fprint:		fn(fd: ref FD, s: string, *): int;
};

yysys: YYSys;
yystderr: ref YYSys->FD;

YYFLAG: con -1000;

# parser for yacc output

yytokname(yyc: int): string
{
	if(yyc > 0 && yyc <= len yytoknames && yytoknames[yyc-1] != nil)
		return yytoknames[yyc-1];
	return "<"+string yyc+">";
}

yystatname(yys: int): string
{
	if(yys >= 0 && yys < len yystates && yystates[yys] != nil)
		return yystates[yys];
	return "<"+string yys+">\n";
}

yylex1(yylex: ref YYLEX): int
{
	c : int;
	yychar := yylex.lex();
	if(yychar <= 0)
		c = yytok1[0];
	else if(yychar < len yytok1)
		c = yytok1[yychar];
	else if(yychar >= YYPRIVATE && yychar < YYPRIVATE+len yytok2)
		c = yytok2[yychar-YYPRIVATE];
	else{
		n := len yytok3;
		c = 0;
		for(i := 0; i < n; i+=2) {
			if(yytok3[i+0] == yychar) {
				c = yytok3[i+1];
				break;
			}
		}
		if(c == 0)
			c = yytok2[1];	# unknown char
	}
	if(yydebug >= 3)
		yysys->fprint(yystderr, "lex %.4ux %s\n", yychar, yytokname(c));
	return c;
}

YYS: adt
{
	yyv: YYSTYPE;
	yys: int;
};

yyparse(yylex: ref YYLEX): int
{
	if(yydebug >= 1 && yysys == nil) {
		yysys = load YYSys "$Sys";
		yystderr = yysys->fildes(2);
	}

	yys := array[YYMAXDEPTH] of YYS;

	yyval: YYSTYPE;
	yystate := 0;
	yychar := -1;
	yynerrs := 0;		# number of errors
	yyerrflag := 0;		# error recovery flag
	yyp := -1;
	yyn := 0;

yystack:
	for(;;){
		# put a state and value onto the stack
		if(yydebug >= 4)
			yysys->fprint(yystderr, "char %s in %s", yytokname(yychar), yystatname(yystate));

		yyp++;
		if(yyp >= len yys)
			yys = (array[len yys * 2] of YYS)[0:] = yys;
		yys[yyp].yys = yystate;
		yys[yyp].yyv = yyval;

		for(;;){
			yyn = yypact[yystate];
			if(yyn > YYFLAG) {	# simple state
				if(yychar < 0)
					yychar = yylex1(yylex);
				yyn += yychar;
				if(yyn >= 0 && yyn < YYLAST) {
					yyn = yyact[yyn];
					if(yychk[yyn] == yychar) { # valid shift
						yychar = -1;
						yyp++;
						if(yyp >= len yys)
							yys = (array[len yys * 2] of YYS)[0:] = yys;
						yystate = yyn;
						yys[yyp].yys = yystate;
						yys[yyp].yyv = yylex.lval;
						if(yyerrflag > 0)
							yyerrflag--;
						if(yydebug >= 4)
							yysys->fprint(yystderr, "char %s in %s", yytokname(yychar), yystatname(yystate));
						continue;
					}
				}
			}
		
			# default state action
			yyn = yydef[yystate];
			if(yyn == -2) {
				if(yychar < 0)
					yychar = yylex1(yylex);
		
				# look through exception table
				for(yyxi:=0;; yyxi+=2)
					if(yyexca[yyxi] == -1 && yyexca[yyxi+1] == yystate)
						break;
				for(yyxi += 2;; yyxi += 2) {
					yyn = yyexca[yyxi];
					if(yyn < 0 || yyn == yychar)
						break;
				}
				yyn = yyexca[yyxi+1];
				if(yyn < 0){
					yyn = 0;
					break yystack;
				}
			}

			if(yyn != 0)
				break;

			# error ... attempt to resume parsing
			if(yyerrflag == 0) { # brand new error
				yylex.error("syntax error");
				yynerrs++;
				if(yydebug >= 1) {
					yysys->fprint(yystderr, "%s", yystatname(yystate));
					yysys->fprint(yystderr, "saw %s\n", yytokname(yychar));
				}
			}

			if(yyerrflag != 3) { # incompletely recovered error ... try again
				yyerrflag = 3;
	
				# find a state where "error" is a legal shift action
				while(yyp >= 0) {
					yyn = yypact[yys[yyp].yys] + YYERRCODE;
					if(yyn >= 0 && yyn < YYLAST) {
						yystate = yyact[yyn];  # simulate a shift of "error"
						if(yychk[yystate] == YYERRCODE)
							continue yystack;
					}
	
					# the current yyp has no shift onn "error", pop stack
					if(yydebug >= 2)
						yysys->fprint(yystderr, "error recovery pops state %d, uncovers %d\n",
							yys[yyp].yys, yys[yyp-1].yys );
					yyp--;
				}
				# there is no state on the stack with an error shift ... abort
				yyn = 1;
				break yystack;
			}

			# no shift yet; clobber input char
			if(yydebug >= 2)
				yysys->fprint(yystderr, "error recovery discards %s\n", yytokname(yychar));
			if(yychar == YYEOFCODE) {
				yyn = 1;
				break yystack;
			}
			yychar = -1;
			# try again in the same state
		}
	
		# reduction by production yyn
		if(yydebug >= 2)
			yysys->fprint(yystderr, "reduce %d in:\n\t%s", yyn, yystatname(yystate));
	
		yypt := yyp;
		yyp -= yyr2[yyn];
#		yyval = yys[yyp+1].yyv;
		yym := yyn;
	
		# consult goto table to find next state
		yyn = yyr1[yyn];
		yyg := yypgo[yyn];
		yyj := yyg + yys[yyp].yys + 1;
	
		if(yyj >= YYLAST || yychk[yystate=yyact[yyj]] != -yyn)
			yystate = yyact[yyg];
		case yym {
			
1=>
#line	178	"asm.y"
{
		assem(yys[yypt-0].yyv.inst);
	}
2=>
#line	184	"asm.y"
{ yyval.inst = nil; }
3=>
#line	186	"asm.y"
{
		if(yys[yypt-0].yyv.inst != nil) {
			yys[yypt-0].yyv.inst.link = yys[yypt-1].yyv.inst;
			yyval.inst = yys[yypt-0].yyv.inst;
		}
		else
			yyval.inst = yys[yypt-1].yyv.inst;
	}
4=>
#line	197	"asm.y"
{
		yys[yypt-0].yyv.inst.sym = yys[yypt-2].yyv.sym;
		yyval.inst = yys[yypt-0].yyv.inst;
	}
5=>
#line	202	"asm.y"
{
		heap(int yys[yypt-3].yyv.ival, int yys[yypt-1].yyv.ival, yys[yypt-0].yyv.str);
		yyval.inst = nil;
	}
6=>
#line	207	"asm.y"
{
		yyval.inst = nil;
	}
7=>
yyval.inst = yys[yyp+1].yyv.inst;
8=>
#line	214	"asm.y"
{
		yyval.ival = yys[yypt-0].yyv.ival;
	}
9=>
#line	218	"asm.y"
{
		yys[yypt-0].yyv.sym.value = heapid++;
		yyval.ival = big yys[yypt-0].yyv.sym.value;
	}
10=>
#line	225	"asm.y"
{ yyval.str = nil; }
11=>
#line	227	"asm.y"
{
		yyval.str = yys[yypt-0].yyv.str;
	}
12=>
#line	233	"asm.y"
{
		yyval.listv = newi(yys[yypt-0].yyv.ival, nil);
	}
13=>
#line	237	"asm.y"
{
		yyval.listv = newi(yys[yypt-0].yyv.ival, yys[yypt-2].yyv.listv);
	}
14=>
#line	243	"asm.y"
{
		yyval.inst = ai(yys[yypt-3].yyv.op);
		yyval.inst.src = yys[yypt-2].yyv.addr;
		yyval.inst.dst = yys[yypt-0].yyv.addr;
	}
15=>
#line	249	"asm.y"
{
		yyval.inst = ai(yys[yypt-5].yyv.op);
		yyval.inst.src = yys[yypt-4].yyv.addr;
		yyval.inst.reg = yys[yypt-2].yyv.addr;
		yyval.inst.dst = yys[yypt-0].yyv.addr;
	}
16=>
#line	256	"asm.y"
{
		yyval.inst = ai(yys[yypt-3].yyv.op);
		yyval.inst.src = yys[yypt-2].yyv.addr;
		yyval.inst.dst = yys[yypt-0].yyv.addr;
	}
17=>
#line	262	"asm.y"
{
		yyval.inst = ai(yys[yypt-1].yyv.op);
		yyval.inst.dst = yys[yypt-0].yyv.addr;
	}
18=>
#line	267	"asm.y"
{
		yyval.inst = ai(yys[yypt-0].yyv.op);
	}
19=>
#line	273	"asm.y"
{
		data(DEFB, yys[yypt-2].yyv.ival, yys[yypt-0].yyv.listv);
	}
20=>
#line	277	"asm.y"
{
		data(DEFW, yys[yypt-2].yyv.ival, yys[yypt-0].yyv.listv);
	}
21=>
#line	281	"asm.y"
{
		data(DEFL, yys[yypt-2].yyv.ival, yys[yypt-0].yyv.listv);
	}
22=>
#line	285	"asm.y"
{
		data(DEFF, yys[yypt-2].yyv.ival, newb(dtocanon(real yys[yypt-0].yyv.ival), nil));
	}
23=>
#line	289	"asm.y"
{
		data(DEFF, yys[yypt-2].yyv.ival, newb(dtocanon(yys[yypt-0].yyv.fval), nil));
	}
24=>
#line	293	"asm.y"
{
		case yys[yypt-0].yyv.sym.name {
		"Inf" or "Infinity" =>
			b := array[] of {byte 16r7F, byte 16rF0, byte 0, byte 0, byte 0, byte 0, byte 0, byte 0};
			data(DEFF, yys[yypt-2].yyv.ival, newb(b, nil));
		"NaN" =>
			b := array[] of {byte 16r7F, byte 16rFF, byte 16rFF, byte 16rFF, byte 16rFF, byte 16rFF, byte 16rFF, byte 16rFF};
			data(DEFF, yys[yypt-2].yyv.ival, newb(b, nil));
		* =>
			diag(sys->sprint("bad value for real: %s", yys[yypt-0].yyv.sym.name));
		}
	}
25=>
#line	306	"asm.y"
{
		data(DEFF, yys[yypt-3].yyv.ival, newb(dtocanon(-real yys[yypt-0].yyv.ival), nil));
	}
26=>
#line	310	"asm.y"
{
		data(DEFF, yys[yypt-3].yyv.ival, newb(dtocanon(-yys[yypt-0].yyv.fval), nil));
	}
27=>
#line	314	"asm.y"
{
		case yys[yypt-0].yyv.sym.name {
		"Inf" or "Infinity" =>
			b := array[] of {byte 16rFF, byte 16rF0, byte 0, byte 0, byte 0, byte 0, byte 0, byte 0};
			data(DEFF, yys[yypt-3].yyv.ival, newb(b, nil));
		* =>
			diag(sys->sprint("bad value for real: %s", yys[yypt-0].yyv.sym.name));
		}
	}
28=>
#line	324	"asm.y"
{
		data(DEFS, yys[yypt-2].yyv.ival, news(yys[yypt-0].yyv.str, nil));
	}
29=>
#line	328	"asm.y"
{
		if(yys[yypt-2].yyv.sym.ds != 0)
			diag(sys->sprint("%s declared twice", yys[yypt-2].yyv.sym.name));
		yys[yypt-2].yyv.sym.ds = int yys[yypt-0].yyv.ival;
		yys[yypt-2].yyv.sym.value = dseg;
		dseg += int yys[yypt-0].yyv.ival;
	}
30=>
#line	336	"asm.y"
{
		ext(int yys[yypt-4].yyv.ival, int yys[yypt-2].yyv.ival, yys[yypt-0].yyv.str);
	}
31=>
#line	340	"asm.y"
{
		mklink(int yys[yypt-6].yyv.ival, int yys[yypt-4].yyv.ival, int yys[yypt-2].yyv.ival, yys[yypt-0].yyv.str);
	}
32=>
#line	344	"asm.y"
{
		if(amodule != nil)
			diag(sys->sprint("this module already defined as %s", yys[yypt-0].yyv.sym.name));
		else
			amodule = yys[yypt-0].yyv.sym;
	}
33=>
#line	351	"asm.y"
{
		if(pcentry >= 0)
			diag(sys->sprint("this module already has entry point %d, %d" , pcentry, dentry));
		pcentry = int yys[yypt-2].yyv.ival;
		dentry = int yys[yypt-0].yyv.ival;
	}
34=>
#line	358	"asm.y"
{
		data(DEFA, yys[yypt-4].yyv.ival, newa(int yys[yypt-2].yyv.ival, int yys[yypt-0].yyv.ival));
	}
35=>
#line	362	"asm.y"
{
		data(DIND, yys[yypt-2].yyv.ival, newa(int yys[yypt-0].yyv.ival, 0));
	}
36=>
#line	366	"asm.y"
{
		data(DAPOP, big 0, newa(0, 0));
	}
37=>
#line	370	"asm.y"
{
		ldts(int yys[yypt-0].yyv.ival);
	}
38=>
#line	374	"asm.y"
{
		excs(int yys[yypt-0].yyv.ival);
	}
39=>
#line	378	"asm.y"
{
		exc(int yys[yypt-10].yyv.ival, int yys[yypt-8].yyv.ival, int yys[yypt-6].yyv.ival, int yys[yypt-4].yyv.ival, int yys[yypt-2].yyv.ival, int yys[yypt-0].yyv.ival);
	}
40=>
#line	382	"asm.y"
{
		etab(yys[yypt-2].yyv.str, int yys[yypt-0].yyv.ival);
	}
41=>
#line	386	"asm.y"
{
		etab(nil, int yys[yypt-0].yyv.ival);
	}
42=>
#line	390	"asm.y"
{
		source(yys[yypt-0].yyv.str);
	}
43=>
#line	396	"asm.y"
{
		yyval.addr = aa(yys[yypt-0].yyv.ival);
		yyval.addr.mode = AXIMM;
		if(yyval.addr.val > 16r7FFF || yyval.addr.val < -16r8000)
			diag(sys->sprint("immediate %d too large for middle operand", yyval.addr.val));
	}
44=>
#line	403	"asm.y"
{
		if(yys[yypt-0].yyv.addr.mode == AMP)
			yys[yypt-0].yyv.addr.mode = AXINM;
		else
			yys[yypt-0].yyv.addr.mode = AXINF;
		if(yys[yypt-0].yyv.addr.mode == AXINM && isoff2big(yys[yypt-0].yyv.addr.val))
			diag(sys->sprint("register offset %d(mp) too large", yys[yypt-0].yyv.addr.val));
		if(yys[yypt-0].yyv.addr.mode == AXINF && isoff2big(yys[yypt-0].yyv.addr.val))
			diag(sys->sprint("register offset %d(fp) too large", yys[yypt-0].yyv.addr.val));
		yyval.addr = yys[yypt-0].yyv.addr;
	}
45=>
#line	417	"asm.y"
{
		yyval.addr = aa(yys[yypt-0].yyv.ival);
		yyval.addr.mode = AIMM;
	}
46=>
#line	422	"asm.y"
{
		yyval.addr = aa(big 0);
		yyval.addr.sym = yys[yypt-0].yyv.sym;
	}
47=>
yyval.addr = yys[yyp+1].yyv.addr;
48=>
#line	430	"asm.y"
{
		yys[yypt-0].yyv.addr.mode |= AIND;
		yyval.addr = yys[yypt-0].yyv.addr;
	}
49=>
#line	435	"asm.y"
{
		yys[yypt-1].yyv.addr.mode |= AIND;
		if(yys[yypt-1].yyv.addr.val & 3)
			diag("indirect offset must be word size");
		if(yys[yypt-1].yyv.addr.mode == (AMP|AIND) && (isoff2big(yys[yypt-1].yyv.addr.val) || isoff2big(int yys[yypt-3].yyv.ival)))
			diag(sys->sprint("indirect offset %bd(%d(mp)) too large", yys[yypt-3].yyv.ival, yys[yypt-1].yyv.addr.val));
		if(yys[yypt-1].yyv.addr.mode == (AFP|AIND) && (isoff2big(yys[yypt-1].yyv.addr.val) || isoff2big(int yys[yypt-3].yyv.ival)))
			diag(sys->sprint("indirect offset %bd(%d(fp)) too large", yys[yypt-3].yyv.ival, yys[yypt-1].yyv.addr.val));
		yys[yypt-1].yyv.addr.off = yys[yypt-1].yyv.addr.val;
		yys[yypt-1].yyv.addr.val = int yys[yypt-3].yyv.ival;
		yyval.addr = yys[yypt-1].yyv.addr;
	}
50=>
yyval.addr = yys[yyp+1].yyv.addr;
51=>
#line	451	"asm.y"
{
		yyval.addr = aa(yys[yypt-3].yyv.ival);
		yyval.addr.mode = AMP;
	}
52=>
#line	456	"asm.y"
{
		yyval.addr = aa(yys[yypt-3].yyv.ival);
		yyval.addr.mode = AFP;
	}
53=>
yyval.ival = yys[yyp+1].yyv.ival;
54=>
#line	464	"asm.y"
{
		yyval.ival = big yys[yypt-0].yyv.sym.value;
	}
55=>
#line	468	"asm.y"
{
		yyval.ival = -yys[yypt-0].yyv.ival;
	}
56=>
#line	472	"asm.y"
{
		yyval.ival = yys[yypt-0].yyv.ival;
	}
57=>
#line	476	"asm.y"
{
		yyval.ival = ~yys[yypt-0].yyv.ival;
	}
58=>
#line	480	"asm.y"
{
		yyval.ival = yys[yypt-1].yyv.ival;
	}
59=>
yyval.ival = yys[yyp+1].yyv.ival;
60=>
#line	487	"asm.y"
{
		yyval.ival = yys[yypt-2].yyv.ival + yys[yypt-0].yyv.ival;
	}
61=>
#line	491	"asm.y"
{
		yyval.ival = yys[yypt-2].yyv.ival - yys[yypt-0].yyv.ival;
	}
62=>
#line	495	"asm.y"
{
		yyval.ival = yys[yypt-2].yyv.ival * yys[yypt-0].yyv.ival;
	}
63=>
#line	499	"asm.y"
{
		yyval.ival = yys[yypt-2].yyv.ival / yys[yypt-0].yyv.ival;
	}
64=>
#line	503	"asm.y"
{
		yyval.ival = yys[yypt-2].yyv.ival % yys[yypt-0].yyv.ival;
	}
65=>
#line	507	"asm.y"
{
		yyval.ival = yys[yypt-3].yyv.ival << int yys[yypt-0].yyv.ival;
	}
66=>
#line	511	"asm.y"
{
		yyval.ival = yys[yypt-3].yyv.ival >> int yys[yypt-0].yyv.ival;
	}
67=>
#line	515	"asm.y"
{
		yyval.ival = yys[yypt-2].yyv.ival & yys[yypt-0].yyv.ival;
	}
68=>
#line	519	"asm.y"
{
		yyval.ival = yys[yypt-2].yyv.ival ^ yys[yypt-0].yyv.ival;
	}
69=>
#line	523	"asm.y"
{
		yyval.ival = yys[yypt-2].yyv.ival | yys[yypt-0].yyv.ival;
	}
		}
	}

	return yyn;
}
