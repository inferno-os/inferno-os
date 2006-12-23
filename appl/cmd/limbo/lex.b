Leof:		con -1;
Linestart:	con 0;

Mlower,
Mupper,
Munder,
Mdigit,
Msign,
Mexp,
Mhex,
Mradix:		con byte 1 << iota;
Malpha:		con Mupper|Mlower|Munder;

HashSize:	con 1024;

Keywd: adt
{
	name:	string;
	token:	int;
};

#
# internals
#
savec:		int;
files:		array of ref File;			# files making up the module, sorted by absolute line
nfiles:		int;
lastfile := 0;						# index of last file looked up
incpath :=	array[MaxIncPath] of string;
symbols :=	array[HashSize] of ref Sym;
strings :=	array[HashSize] of ref Sym;
map :=		array[256] of byte;
bins :=		array [MaxInclude] of ref Iobuf;
bin:		ref Iobuf;
linestack :=	array[MaxInclude] of (int, int);
lineno:		int;
linepos:	int;
bstack:		int;
lasttok:	int;
lastyylval:	YYSTYPE;
dowarn:		int;
maxerr:		int;
dosym:		int;
toterrors:	int;
fabort:		int;
srcdir:		string;
outfile:	string;
stderr:		ref Sys->FD;
dontinline:	int;

escmap :=	array[256] of
{
	'\'' =>		'\'',
	'"' =>		'"',
	'\\' =>		'\\',
	'a' =>		'\a',
	'b' =>		'\b',
	'f' =>			'\f',
	'n' =>		'\n',
	'r' =>		'\r',
	't' =>		'\t',
	'v' =>		'\v',
	'0' =>		'\u0000',

	* =>		-1
};
unescmap :=	array[256] of 
{
	'\'' =>		'\'',
	'"' =>		'"',
	'\\' =>		'\\',
	'\a' =>		'a',
	'\b' =>		'b',
	'\f' =>		'f',
	'\n' =>		'n',
	'\r' =>		'r',
	'\t' =>		't',
	'\v' =>		'v',
	'\u0000' =>	'0',

	* =>		0
};

keywords := array [] of
{
	Keywd("adt",		Ladt),
	Keywd("alt",		Lalt),
	Keywd("array",		Larray),
	Keywd("big",		Ltid),
	Keywd("break",		Lbreak),
	Keywd("byte",		Ltid),
	Keywd("case",		Lcase),
	Keywd("chan",		Lchan),
	Keywd("con",		Lcon),
	Keywd("continue",	Lcont),
	Keywd("cyclic",		Lcyclic),
	Keywd("do",		Ldo),
	Keywd("dynamic",	Ldynamic),
	Keywd("else",		Lelse),
	Keywd("exception",	Lexcept),
	Keywd("exit",		Lexit),
	Keywd("fixed",	Lfix),
	Keywd("fn",		Lfn),
	Keywd("for",		Lfor),
	Keywd("hd",		Lhd),
	Keywd("if",		Lif),
	Keywd("implement",	Limplement),
	Keywd("import",		Limport),
	Keywd("include",	Linclude),
	Keywd("int",		Ltid),
	Keywd("len",		Llen),
	Keywd("list",		Llist),
	Keywd("load",		Lload),
	Keywd("module",		Lmodule),
	Keywd("nil",		Lnil),
	Keywd("of",		Lof),
	Keywd("or",		Lor),
	Keywd("pick",		Lpick),
	Keywd("raise",	Lraise),
	Keywd("raises",	Lraises),
	Keywd("real",		Ltid),
	Keywd("ref",		Lref),
	Keywd("return",		Lreturn),
	Keywd("self",		Lself),
	Keywd("spawn",		Lspawn),
	Keywd("string",		Ltid),
	Keywd("tagof",		Ltagof),
	Keywd("tl",		Ltl),
	Keywd("to",		Lto),
	Keywd("type",		Ltype),
	Keywd("while",		Lwhile),
};

tokwords := array[] of
{
	Keywd("&=",	Landeq),
	Keywd("|=",	Loreq),
	Keywd("^=",	Lxoreq),
	Keywd("<<=",	Llsheq),
	Keywd(">>=",	Lrsheq),
	Keywd("+=",	Laddeq),
	Keywd("-=",	Lsubeq),
	Keywd("*=",	Lmuleq),
	Keywd("/=",	Ldiveq),
	Keywd("%=",	Lmodeq),
	Keywd("**=",	Lexpeq),
	Keywd(":=",	Ldeclas),
	Keywd("||",	Loror),
	Keywd("&&",	Landand),
	Keywd("::",	Lcons),
	Keywd("==",	Leq),
	Keywd("!=",	Lneq),
	Keywd("<=",	Lleq),
	Keywd(">=",	Lgeq),
	Keywd("<<",	Llsh),
	Keywd(">>",	Lrsh),
	Keywd("<-",	Lcomm),
	Keywd("++", 	Linc),
	Keywd("--",	Ldec),
	Keywd("->", 	Lmdot),
	Keywd("=>", 	Llabs),
	Keywd("**",	Lexp),
	Keywd("EOF",	Leof),
};

lexinit()
{
	for(i := 0; i < 256; i++){
		map[i] = byte 0;
		if(i == '_' || i > 16ra0)
			map[i] |= Munder;
		if(i >= 'A' && i <= 'Z')
			map[i] |= Mupper;
		if(i >= 'a' && i <= 'z')
			map[i] |= Mlower;
		if(i >= 'A' && i <= 'F' || i >= 'a' && i <= 'f')
			map[i] |= Mhex;
		if(i == 'e' || i == 'E')
			map[i] |= Mexp;
		if(i == 'r' || i == 'R')
			map[i] |= Mradix;
		if(i == '-' || i == '+')
			map[i] |= Msign;
		if(i >= '0' && i <= '9')
			map[i] |= Mdigit;
	}

	for(i = 0; i < len keywords; i++)
		enter(keywords[i].name, keywords[i].token);
}

cmap(c: int): byte
{
	if(c<0)
		return byte 0;
	if(c<256)
		return map[c];
	return Mlower;
}

lexstart(in: string)
{
	savec = 0;
	bstack = 0;
	nfiles = 0;
	addfile(ref File(in, 1, 0, -1, nil, 0, -1));
	bin = bins[bstack];
	lineno = 1;
	linepos = Linestart;

	(srcdir, nil) = str->splitr(in, "/");
}

getc(): int
{
	if(c := savec){
		if(savec >= 0){
			linepos++;
			savec = 0;
		}
		return c;
	}
	c = bin.getc();
	if(c < 0){
		savec = -1;
		return savec;
	}
	linepos++;
	return c;
}

#
# dumps '\u0000' chararcters
#
ungetc(c: int)
{
	if(c > 0)
		linepos--;
	savec = c;
}

addinclude(s: string)
{
	for(i := 0; i < MaxIncPath; i++){
		if(incpath[i] == nil){
			incpath[i] = s;
			return;
		}
	}
	fatal("out of include path space");
}

addfile(f: ref File): int
{
	if(lastfile >= nfiles)
		lastfile = 0;
	if(nfiles >= len files){
		nf := array[nfiles+32] of ref File;
		nf[0:] = files;
		files = nf;
	}
	files[nfiles] = f;
	return nfiles++;
}

#
# include a new file
#
includef(file: ref Sym)
{
	linestack[bstack] = (lineno, linepos);
	bstack++;
	if(bstack >= MaxInclude)
		fatal(lineconv(lineno<<PosBits)+": include file depth too great");
	buf := file.name;
	if(buf[0] != '/')
		buf = srcdir+buf;
	b := bufio->open(buf, Bufio->OREAD);
	for(i := 0; b == nil && i < MaxIncPath && incpath[i] != nil && file.name[0] != '/'; i++){
		buf = incpath[i] + "/" + file.name;
		b = bufio->open(buf, Bufio->OREAD);
	}
	bins[bstack] = b;
	if(bins[bstack] == nil){
		yyerror("can't include "+file.name+": "+sprint("%r"));
		bstack--;
	}else{
		addfile(ref File(buf, lineno+1, -lineno, lineno, nil, 0, -1));
		lineno++;
		linepos = Linestart;
	}
	bin = bins[bstack];
}

#
# we hit eof in the current file
# revert to the file which included it.
#
popinclude()
{
	savec = 0;
	bstack--;
	bin = bins[bstack];
	(oline, opos) := linestack[bstack];
	(f, ln) := fline(oline);
	lineno++;
	linepos = opos;
	addfile(ref File(f.name, lineno, ln-lineno, f.in, f.act, f.actoff, -1));
}

#
# convert an absolute Line into a file and line within the file
#
fline(absline: int): (ref File, int)
{
	if(absline < files[lastfile].abs
	|| lastfile+1 < nfiles && absline >= files[lastfile+1].abs){
		lastfile = 0;
		l := 0;
		r := nfiles - 1;
		while(l <= r){
			m := (r + l) / 2;
			s := files[m].abs;
			if(s <= absline){
				l = m + 1;
				lastfile = m;
			}else
				r = m - 1;
		}
	}
	return (files[lastfile], absline + files[lastfile].off);
}

#
# read a comment; process #line file renamings
#
lexcom(): int
{
	i := 0;
	buf := "";
	while((c := getc()) != '\n'){
		if(c == Bufio->EOF)
			return -1;
		buf[i++] = c;
	}

	lineno++;
	linepos = Linestart;

	if(len buf < 6
	|| buf[len buf - 1] != '"'
	|| buf[:5] != "line " && buf[:5] != "line\t")
		return 0;
	for(s := 5; buf[s] == ' ' || buf[s] == '\t'; s++)
		;
	if((cmap(buf[s]) & Mdigit) == byte 0)
		return 0;
	n := 0;
	for(; (cmap(c = buf[s]) & Mdigit) != byte 0; s++)
		n = n * 10 + c - '0';
	for(; buf[s] == ' ' || buf[s] == '\t'; s++)
		;
	if(buf[s++] != '"')
		return 0;
	buf = buf[s:len buf - 1];
	f := files[nfiles - 1];
	if(n == f.off+lineno && buf == f.name)
		return 1;
	act := f.name;
	actline := lineno + f.off;
	if(f.act != nil){
		actline += f.actoff;
		act = f.act;
	}
	addfile(ref File(buf, lineno, n-lineno, f.in, act, actline - n, -1));

	return 1;
}

curline(): Line
{
	return (lineno << PosBits) | (linepos & PosMask);
}

lineconv(line: Line): string
{
	line >>= PosBits;
	if(line < 0)
		return "<noline>";
	(f, ln) := fline(line);
	s := "";
	if(f.in >= 0){
		s = ": " + lineconv(f.in << PosBits);
	}
	if(f.act != nil)
		s = " [ " + f.act + ":" + string(f.actoff+ln) + " ]" + s;
	return f.name + ":" + string ln + s;
}

posconv(s: Line): string
{
	if(s < 0)
		return "nopos";
	spos := s & PosMask;
	s >>= PosBits;
	(f, ln) := fline(s);
	return f.name + ":" + string ln + "." + string spos;
}

srcconv(src: Src): string
{
	s := posconv(src.start);
	s[len s] = ',';
	s += posconv(src.stop);
	return s;
}

lexid(c: int): int
{
	id := "";
	i := 0;
	for(;;){
		if(i < StrSize)
			id[i++] = c;
		c = getc();
		if(c == Bufio->EOF
		|| (cmap(c) & (Malpha|Mdigit)) == byte 0){
			ungetc(c);
			break;
		}
	}
	sym := enter(id, Lid);
	t := sym.token;
	if(t == Lid || t == Ltid)
		yyctxt.lval.tok.v.idval = sym;
	return t;
}

maxfast := array[37] of
{
	2 =>	31,
	4 =>	15,
	8 =>	10,
	10 =>	9,
	16 =>	7,
	32 =>	6,
	* =>	0,
};

strtoi(t: string, bbase: big): big
{
	#
	# do the first part in ints
	#
	v := 0;
	bv: big;
	base := int bbase;
	n := maxfast[base];

	neg := 0;
	i := 0;
	if(i < len t && t[i] == '-'){
		neg = 1;
		i++;
	}else if(i < len t && t[i] == '+')
		i++;

	for(; i < len t; i++){
		c := t[i];
		if(c >= '0' && c <= '9')
			c -= '0';
		else if(c >= 'a' && c <= 'z')
			c -= 'a' - 10;
		else
			c -= 'A' - 10;
		if(c >= base){
			yyerror("digit '"+t[i:i+1]+"' is not radix "+string base);
			return big -1;
		}
		if(i < n)
			v = v * base + c;
		else{
			if(i == n)
				bv = big v;
			bv = bv * bbase + big c;
		}
	}
	if(i <= n)
		bv = big v;
	if(neg)
		return -bv;
	return bv;
}

digit(c: int, base: int): int
{
	ck: byte;
	cc: int;

	cc = c;
	ck = cmap(c);
	if((ck & Mdigit) != byte 0)
		c -= '0';
	else if((ck & Mlower) != byte 0)
		c = c - 'a' + 10;
	else if((ck & Mupper) != byte 0)
		c = c - 'A' + 10;
	else if((ck & Munder) != byte 0)
		;
	else
		return -1;
	if(c >= base){
		s := "z";
		s[0] = cc;
		yyerror("digit '" + s + "' not radix " + string base);
	}
	return c;
}

strtodb(t: string, base: int): real
{
	num, dem, rbase: real;
	neg, eneg, dig, exp, c, d: int;

	t[len t] = 0;

	num = 0.0;
	rbase = real base;
	neg = 0;
	dig = 0;
	exp = 0;
	eneg = 0;

	i := 0;
	c = t[i++];
	if(c == '-' || c == '+'){
		if(c == '-')
			neg = 1;
		c = t[i++];
	}
	while((d = digit(c, base)) >= 0){
		num = num*rbase + real d;
		c = t[i++];
	}
	if(c == '.')
		c = t[i++];
	while((d = digit(c, base)) >= 0){
		num = num*rbase + real d;
		dig++;
		c = t[i++];
	}
	if(c == 'e' || c == 'E'){
		c = t[i++];
		if(c == '-' || c == '+'){
			if(c == '-'){
				dig = -dig;
				eneg = 1;
			}
			c = t[i++];
		}
		while((d = digit(c, base)) >= 0){
			exp = exp*base + d;
			c = t[i++];
		}
	}
	exp -= dig;
	if(exp < 0){
		exp = -exp;
		eneg = !eneg;
	}
	dem = rpow(rbase, exp);
	if(eneg)
		num /= dem;
	else
		num *= dem;
	if(neg)
		return -num;
	return num;
}

#
# parse a numeric identifier
# format [0-9]+(r[0-9A-Za-z]+)?
# or ([0-9]+(\.[0-9]*)?|\.[0-9]+)([eE][+-]?[0-9]+)?
#
lexnum(c: int): int
{
	Int, Radix, RadixSeen, Frac, ExpSeen, ExpSignSeen, Exp, FracB: con iota;

	i := 0;
	buf := "";
	buf[i++] = c;
	state := Int;
	if(c == '.')
		state = Frac;
	radix := "";

done:	for(;;){
		c = getc();
		if(c == Bufio->EOF){
			yyerror("end of file in numeric constant");
			return Leof;
		}

		ck := cmap(c);
		case state{
		Int =>
			if((ck & Mdigit) != byte 0)
				break;
			if((ck & Mexp) != byte 0){
				state = ExpSeen;
				break;
			}
			if((ck & Mradix) != byte 0){
				radix = buf;
				buf = "";
				i = 0;
				state = RadixSeen;
				break;
			}
			if(c == '.'){
				state = Frac;
				break;
			}
			break done;
		RadixSeen or
		Radix =>
			if((ck & (Mdigit|Malpha)) != byte 0){
				state = Radix;
				break;
			}
			if(c == '.'){
				state = FracB;
				break;
			}
			break done;
		Frac =>
			if((ck & Mdigit) != byte 0)
				break;
			if((ck & Mexp) != byte 0)
				state = ExpSeen;
			else
				break done;
		FracB =>
			if((ck & (Mdigit|Malpha)) != byte 0)
				break;
			break done;
		ExpSeen =>
			if((ck & Msign) != byte 0){
				state = ExpSignSeen;
				break;
			}
			if((ck & Mdigit) != byte 0){
				state = Exp;
				break;
			}
			break done;
		ExpSignSeen or
		Exp =>
			if((ck & Mdigit) != byte 0){
				state = Exp;
				break;
			}
			break done;
		}
		buf[i++] = c;
	}

	ungetc(c);
	v: big;
	case state{
	* =>
		yyerror("malformed numerical constant '"+radix+buf+"'");
		yyctxt.lval.tok.v.ival = big 0;
		return Lconst;
	Radix =>
		v = strtoi(radix, big 10);
		if(v < big 2 || v > big 36){
			yyerror("radix '"+radix+"' is not between 2 and 36");
			break;
		}
		v = strtoi(buf[1:], v);
	Int =>
		v = strtoi(buf, big 10);
	Frac or
	Exp =>
		yyctxt.lval.tok.v.rval = real buf;
		return Lrconst;
	FracB =>
		v = strtoi(radix, big 10);
		if(v < big 2 || v > big 36){
			yyerror("radix '"+radix+"' is not between 2 and 36");
			break;
		}
		yyctxt.lval.tok.v.rval = strtodb(buf[1:], int v);
		return Lrconst;
	}
	yyctxt.lval.tok.v.ival = v;
	return Lconst;
}

escchar(): int
{
	c := getc();
	if(c == Bufio->EOF)
		return Bufio->EOF;
	if(c == 'u'){
		v := 0;
		for(i := 0; i < 4; i++){
			c = getc();
			ck := cmap(c);
			if(c == Bufio->EOF || (ck & (Mdigit|Mhex)) == byte 0){
				yyerror("malformed \\u escape sequence");
				ungetc(c);
				break;
			}
			if((ck & Mdigit) != byte 0)
				c -= '0';
			else if((ck & Mlower) != byte 0)
				c = c - 'a' + 10;
			else if((ck & Mupper) != byte 0)
				c = c - 'A' + 10;
			v = v * 16 + c;
		}
		return v;
	}
	if(c < len escmap && (v := escmap[c]) >= 0)
		return v;
	s := "";
	s[0] = c;
	yyerror("unrecognized escape \\"+s);
	return c;
}

lexstring()
{
	s := "";
	i := 0;
loop:	for(;;){
		case c := getc(){
		'\\' =>
			c = escchar();
			if(c != Bufio->EOF)
				s[i++] = c;
		Bufio->EOF =>
			yyerror("end of file in string constant");
			break loop;
		'\n' =>
			yyerror("newline in string constant");
			lineno++;
			linepos = Linestart;
			break loop;
		'"' =>
			break loop;
		* =>
			s[i++] = c;
		}
	}
	yyctxt.lval.tok.v.idval = enterstring(s);
}

lex(): int
{
	for(;;){
		yyctxt.lval.tok.src.start = (lineno << PosBits) | (linepos & PosMask);
		case c := getc(){
		Bufio->EOF =>
			bin.close();
			if(bstack == 0)
				return Leof;
			popinclude();
		'#' =>
			if(lexcom() < 0){
				bin.close();
				if(bstack == 0)
					return Leof;
				popinclude();
			}
		'\n' =>
			lineno++;
			linepos = Linestart;
		' ' or
		'\t' or
		'\r' or
		'\v' =>
			;
		'"' =>
			lexstring();
			return Lsconst;
		'\'' =>
			c = getc();
			if(c == '\\')
				c = escchar();
			if(c == Bufio->EOF){
				yyerror("end of file in character constant");
				return Bufio->EOF;
			}else
				yyctxt.lval.tok.v.ival = big c;
			c = getc();
			if(c != '\''){
				yyerror("missing closing '");
				ungetc(c);
			}
			return Lconst;
		'(' or
		')' or
		'[' or
		']' or
		'{' or
		'}' or
		',' or
		';' or
		'~' =>
			return c;
		':' =>
			c = getc();
			if(c == ':')
				return Lcons;
			if(c == '=')
				return Ldeclas;
			ungetc(c);
			return ':';
		'.' =>
			c = getc();
			ungetc(c);
			if(c != Bufio->EOF && (cmap(c) & Mdigit) != byte 0)
				return lexnum('.');
			return '.';
		'|' =>
			c = getc();
			if(c == '=')
				return Loreq;
			if(c == '|')
				return Loror;
			ungetc(c);
			return '|';
		'&' =>
			c = getc();
			if(c == '=')
				return Landeq;
			if(c == '&')
				return Landand;
			ungetc(c);
			return '&';
		'^' =>
			c = getc();
			if(c == '=')
				return Lxoreq;
			ungetc(c);
			return '^';
		'*' =>
			c = getc();
			if(c == '=')
				return Lmuleq;
			if(c == '*'){
				c = getc();
				if(c == '=')
					return Lexpeq;
				ungetc(c);
				return Lexp;
			}
			ungetc(c);
			return '*';
		'/' =>
			c = getc();
			if(c == '=')
				return Ldiveq;
			ungetc(c);
			return '/';
		'%' =>
			c = getc();
			if(c == '=')
				return Lmodeq;
			ungetc(c);
			return '%';
		'=' =>
			c = getc();
			if(c == '=')
				return Leq;
			if(c == '>')
				return Llabs;
			ungetc(c);
			return '=';
		'!' =>
			c = getc();
			if(c == '=')
				return Lneq;
			ungetc(c);
			return '!';
		'>' =>
			c = getc();
			if(c == '=')
				return Lgeq;
			if(c == '>'){
				c = getc();
				if(c == '=')
					return Lrsheq;
				ungetc(c);
				return Lrsh;
			}
			ungetc(c);
			return '>';
		'<' =>
			c = getc();
			if(c == '=')
				return Lleq;
			if(c == '-')
				return Lcomm;
			if(c == '<'){
				c = getc();
				if(c == '=')
					return Llsheq;
				ungetc(c);
				return Llsh;
			}
			ungetc(c);
			return '<';
		'+' =>
			c = getc();
			if(c == '=')
				return Laddeq;
			if(c == '+')
				return Linc;
			ungetc(c);
			return '+';
		'-' =>
			c = getc();
			if(c == '=')
				return Lsubeq;
			if(c == '-')
				return Ldec;
			if(c == '>')
				return Lmdot;
			ungetc(c);
			return '-';
		'0' to '9' =>
			return lexnum(c);
		* =>
			if((cmap(c) & Malpha) != byte 0)
				return lexid(c);
			s := "";
			s[0] = c;
			yyerror("unknown character '"+s+"'");
		}
	}
}

YYLEX.lex(nil: self ref YYLEX): int
{
	t := lex();
	yyctxt.lval.tok.src.stop = (lineno << PosBits) | (linepos & PosMask);
	lasttok = t;
	lastyylval = yyctxt.lval;
	return t;
}

toksp(t: int): string
{
	case(t){
		Lconst =>
			return sprint("%bd", lastyylval.tok.v.ival);
		Lrconst =>
			return sprint("%f", lastyylval.tok.v.rval);
		Lsconst =>
			return sprint("\"%s\"", lastyylval.tok.v.idval.name);
		Ltid or Lid =>
			return lastyylval.tok.v.idval.name;
	}
	for(i := 0; i < len keywords; i++)
		if(t == keywords[i].token)
			return keywords[i].name;
	for(i = 0; i < len tokwords; i++)
		if(t == tokwords[i].token)
			return tokwords[i].name;
	if(t < 0 || t > 255)
		fatal(sprint("bad token %d in toksp()", t));
	buf := "Z";
	buf[0] = t;
	return buf;
}

enterstring(name: string): ref Sym
{
	h := 0;
	n := len name;
	for(i := 0; i < n; i++){
		c := d := name[i];
		c ^= c << 6;
		h += (c << 11) ^ (c >> 1);
		h ^= (d << 14) + (d << 7) + (d << 4) + d;
	}

	h &= HashSize-1;
	for(s := strings[h]; s != nil; s = s.next){
		sn := s.name;
		if(len sn == n && sn == name)
			return s;
	}


	s = ref Sym;
	s.token = -1;
	s.name = name;
	s.hash = h;
	s.next = strings[h];
	strings[h] = s;
	return s;
}

stringcat(s, t: ref Sym): ref Sym
{
	return enterstring(s.name+t.name);
}

enter(name: string, token: int): ref Sym
{
	h := 0;
	n := len name;
	for(i := 0; i < n; i++){
		c := d := name[i];
		c ^= c << 6;
		h += (c << 11) ^ (c >> 1);
		h ^= (d << 14) + (d << 7) + (d << 4) + d;
	}

	h &= HashSize-1;
	for(s := symbols[h]; s != nil; s = s.next){
		sn := s.name;
		if(len sn == n && sn == name)
			return s;
	}

	if(token == 0)
		token = Lid;
	s = ref Sym;
	s.token = token;
	s.name = name;
	s.hash = h;
	s.next = symbols[h];
	symbols[h] = s;
	return s;
}

stringpr(sym: ref Sym): string
{
	s := sym.name;
	n := len s;
	if(n > 10)
		n = 10;
	sb := "\"";
	for(i := 0; i < n; i++){
		case c := s[i]{
		'\\' or
		'"' or
		'\n' or
		'\r' or
		'\t' or
		'\b' or
		'\a' or
		'\v' or
		'\u0000' =>
			sb[len sb] = '\\';
			sb[len sb] = unescmap[c];
		* =>
			sb[len sb] = c;
		}
	}
	if(n != len s)
		sb += "...";
	sb[len sb] = '"';
	return sb;
}

warn(line: Line, msg: string)
{
	if(errors || !dowarn)
		return;
	fprint(stderr, "%s: warning: %s\n", lineconv(line), msg);
}

nwarn(n: ref Node, msg: string)
{
	if(errors || !dowarn)
		return;
	fprint(stderr, "%s: warning: %s\n", lineconv(n.src.start), msg);
}

error(line: Line, msg: string)
{
	errors++;
	if(errors > maxerr)
		return;
	fprint(stderr, "%s: %s\n", lineconv(line), msg);
	if(errors == maxerr)
		fprint(stderr, "too many errors, stopping\n");
}

nerror(n: ref Node, msg: string)
{
	errors++;
	if(errors > maxerr)
		return;
	fprint(stderr, "%s: %s\n", lineconv(n.src.start), msg);
	if(errors == maxerr)
		fprint(stderr, "too many errors, stopping\n");
}

YYLEX.error(nil: self ref YYLEX, msg: string)
{
	errors++;
	if(errors > maxerr)
		return;
	if(lasttok != 0)
		fprint(stderr, "%s: near ` %s ` : %s\n", lineconv(lineno<<PosBits), toksp(lasttok), msg);
	else
		fprint(stderr, "%s: %s\n", lineconv(lineno<<PosBits), msg);
	if(errors == maxerr)
		fprint(stderr, "too many errors, stopping\n");
}

yyerror(msg: string)
{
	yyctxt.error(msg);
}

fatal(msg: string)
{
	if(errors == 0 || fabort)
		fprint(stderr, "fatal limbo compiler error: %s\n", msg);
	if(bout != nil)
		sys->remove(outfile);
	if(fabort){
		n: ref Node;
		if(n.ty == nil);	# abort
	}
	raise "fail:error";
}

hex(v, n: int): string
{
	return sprint("%.*ux", n, v);
}

bhex(v: big, n: int): string
{
	return sprint("%.*bux", n, v);
}
