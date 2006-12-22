#
#	Lexical analyzer.
#

lexdebug	: con 0;

#
#	Import tokens from parser.
#
Land,
Lat,
Lbackq,
Lcaret,
Lcase,
Lcolon,
Lcolonmatch,
Lcons,
Ldefeq,
Lelse,
Leof,
Leq,
Leqeq,
Lerror,
Lfn,
Lfor,
Lgreat,
Lgreatgreat,
Lhd,
Lif,
Lin,
Llen,
Lless,
Llessgreat,
Lmatch,
Lmatched,
Lnot,
Lnoteq,
Loffcurly,
Loffparen,
Loncurly,
Lonparen,
Lpipe,
Lquote,
Lrescue,
Lsemi,
Ltl,
Lwhile,
Lword
	: import Mashparse;

KWSIZE:	con 31;	# keyword hashtable size
NCTYPE:	con 128;	# character class array size

ALPHA,
NUMERIC,
ONE,
WS,
META
	:	con 1 << iota;

keywords := array[] of
{
	("case",	Lcase),
	("else",	Lelse),
	("fn",		Lfn),
	("for",	Lfor),
	("hd",	Lhd),
	("if",		Lif),
	("in",		Lin),
	("len",	Llen),
	("rescue",	Lrescue),
	("tl",		Ltl),
	("while",	Lwhile)
};

ctype := array[NCTYPE] of
{
	0 or ' ' or '\t' or '\n' or '\r' or '\v' => WS,
	':' or '#' or ';' or '&' or '|' or '^' or '$' or '=' or '@'
	 	or '~'  or '`'or '{' or '}' or '(' or ')' or '<' or '>' => ONE,
	'a' to 'z' or 'A' to 'Z' or '_' => ALPHA,
	'0' to '9' => NUMERIC,
	'*' or '[' or ']' or '?' => META,
	* => 0
};

keytab:	ref HashTable;

#
#	Initialize hashtable.
#
initlex()
{
	keytab = hash->new(KWSIZE);
	for (i := 0; i < len keywords; i++) {
		(s, v) := keywords[i];
		keytab.insert(s, HashVal(v, 0.0, nil));
	}
}

#
#	Keyword value, or -1.
#
keyval(i: ref Item): int
{
	if (i.op != Iword)
		return -1;
	w := i.word;
	if (w.flags & Wquoted)
		return -1;
	v := keytab.find(w.text);
	if (v == nil)
		return -1;
	return v.i;
}

#
#	Attach a source file to an environment.
#
Env.fopen(e: self ref Env, fd: ref Sys->FD, s: string)
{
	in := bufio->fopen(fd, Bufio->OREAD);
	if (in == nil)
		e.error(sys->sprint("could not fopen %s: %r\n", s));
	e.file = ref File(in, s, 1, 0);
}

#
#	Attach a source string to an environment.
#
Env.sopen(e: self ref Env, s: string)
{
	in := bufio->sopen(s);
	if (in == nil)
		e.error(sys->sprint("Bufio->sopen failed: %r\n"));
	e.file = ref File(in, "<string>", 1, 0);
}

#
#	Close source file.
#
fclose(e: ref Env, c: int)
{
	if (c == Bufio->ERROR)
		readerror(e, e.file);
	e.file.in.close();
	e.file = nil;
}

#
#	Character class routines.
#

isalpha(c: int): int
{
	return c >= NCTYPE || (c >= 0 && (ctype[c] & ALPHA) != 0);
}

isalnum(c: int): int
{
	return c >= NCTYPE || (c >= 0 && (ctype[c] & (ALPHA | NUMERIC)) != 0);
}

isdigit(c: int): int
{
	return c >= 0 && c < NCTYPE && (ctype[c] & NUMERIC) != 0;
}

isquote(c: int): int
{
	return c < NCTYPE && (c < 0 || (ctype[c] & (ONE | WS | META)) != 0);
}

isspace(c: int): int
{
	return c >= 0 && c < NCTYPE && (ctype[c] & WS) != 0;
}

isterm(c: int): int
{
	return c < NCTYPE && (c < 0 || (ctype[c] & (ONE | WS)) != 0);
}

#
#	Test for an identifier.
#
ident(s: string): int
{
	if (s == nil || !isalpha(s[0]))
		return 0;
	n := len s;
	for (x := 1; x < n; x++) {
		if (!isalnum(s[x]))
			return 0;
	}
	return 1;
}

#
#	Quote text.
#
enquote(s: string): string
{
	r := "'";
	j := 1;
	n := len s;
	for (i := 0; i < n; i++) {
		c := s[i];
		if (c == '\'' || c == '\\')
			r[j++] = '\\';
		r[j++] = c;
	}
	r[j] = '\'';
	return r;
}

#
#	Quote text if needed.
#
quote(s: string): string
{
	n := len s;
	for (i := 0; i < n; i++) {
		if (isquote(s[i]))
			return enquote(s);
	}
	return s;
}

#
#	Test for single word and identifier.
#
Item.sword(i: self ref Item, e: ref Env): ref Item
{
	if (i.op == Iword && ident(i.word.text))
		return i;
	e.report("malformed identifier: " + i.text());
	return nil;
}

readerror(e: ref Env, f: ref File)
{
	sys->fprint(e.stderr, "error reading %s: %r\n", f.name);
}

where(e: ref Env): string
{
	if ((e.flags & EInter) || e.file == nil)
		return nil;
	return e.file.name + ":" + string e.file.line + ": ";
}

#
#	Suck input (on error).
#
Env.suck(e: self ref Env)
{
	if (e.file == nil)
		return;
	in := e.file.in;
	while ((c := in.getc()) >= 0 && c != '\n')
		;
}

#
#	Lexical analyzer.
#
Env.lex(e: self ref Env, yylval: ref Mashparse->YYSTYPE): int
{
	i, r: ref Item;
reader:
	for (;;) {
		if (e.file == nil)
			return -1;
		f := e.file;
		in := f.in;
		while (isspace(c := in.getc())) {
			if (c == '\n')
				f.line++;
		}
		if (c < 0) {
			fclose(e, c);
			return Leof;
		}
		case c {
		':' =>
			if ((d := in.getc()) == ':')
				return Lcons;
			if (d == '=')
				return Ldefeq;
			if (d == '~')
				return Lcolonmatch;
			if (d >= 0)
				in.ungetc();
			return Lcolon;
		'#' =>
			for (;;) {
				if ((c = in.getc()) < 0) {
					fclose(e, c);
					return Leof;
				}
				if (c == '\n') {
					f.line++;
					continue reader;
				}
			}
		';' =>
			return Lsemi;
		'&' =>
			return Land;
		'|' =>
			return Lpipe;
		'^' =>
			return Lcaret;
		'@' =>
			return Lat;
		'!' =>
			if ((d := in.getc()) == '=')
				return Lnoteq;
			if (d >= 0)
				in.ungetc();
			return Lnot;
		'~' =>
			return Lmatch;
		'=' =>
			if ((d := in.getc()) == '>')
				return Lmatched;
			if (d == '=')
				return Leqeq;
			if (d >= 0)
				in.ungetc();
			return Leq;
		'`' =>
			return Lbackq;
		'"' =>
			return Lquote;
		'{' =>
			return Loncurly;
		'}' =>
			return Loffcurly;
		'(' =>
			return Lonparen;
		')' =>
			return Loffparen;
		'<' =>
			if ((d := in.getc()) == '>')
				return Llessgreat;
			if (d >= 0)
				in.ungetc();
			return Lless;
		'>' =>
			if ((d := in.getc()) == '>')
				return Lgreatgreat;
			if (d >= 0)
				in.ungetc();
			return Lgreat;
		'\\' =>
			if ((d := in.getc()) == '\n') {
				f.line++;
				continue reader;
			}
			if (d >= 0)
				in.ungetc();
		}
		# Loop over "carets for free".
		for (;;) {
			if (c == '$')
				(i, c) = getdollar(f);
			else
				(i, c) = getword(e, f, c);
			if (i == nil)
				return Lerror;
			if (isterm(c) && c != '$')
				break;
			if (r != nil)
				r = ref Item(Iicaret, nil, r, i, nil, nil);
			else
				r = i;
		}
		if (c >= 0)
			in.ungetc();
		if (r != nil)
			yylval.item = ref Item(Iicaret, nil, r, i, nil, nil);
		else if ((c = keyval(i)) >= 0)
			return c;
		else
			yylval.item = i;
		return Lword;
	}
}

#
#	Get $n or $word.
#
getdollar(f: ref File): (ref Item, int)
{
	s: string;
	in := f.in;
	l := f.line;
	o := Idollar;
	if (isdigit(c := in.getc())) {
		s[0] = c;
		n := 1;
		while (isdigit(c = in.getc()))
			s[n++] = c;
		o = Imatch;
	} else {
		if (c == '"') {
			o = Idollarq;
			c = in.getc();
		}
		if (isalpha(c)) {
			s[0] = c;
			n := 1;
			while (isalnum(c = in.getc()))
				s[n++] = c;
		} else {
			if (o == Idollar)
				s = "$";
			else
				s = "$\"";
			o = Iword;
		}
	}
	return (ref Item(o, ref Word(s, 0, Src(l, f.name)), nil, nil, nil, nil), c);
}

#
#	Get word with quoting.
#
getword(e: ref Env, f: ref File, c: int): (ref Item, int)
{
	s: string;
	in := f.in;
	l := f.line;
	wf := 0;
	n := 0;
	if (c == '\'') {
		wf = Wquoted;
	collect:
		while ((c = in.getc()) >= 0) {
			case c {
			'\'' =>
				c = in.getc();
				break collect;
			'\\' =>
				c = in.getc();
				if (c != '\'' && c != '\\') {
					if (c == '\n')
						continue collect;
					if (c >= 0)
						in.ungetc();
					c = '\\';
				}
			'\n' =>
				f.line++;
				e.report("newline in quoted word");
				return (nil, 0);
			}
			s[n++] = c;
		}
	} else {
		do {
			case c {
			'*' or '[' or '?' =>
				wf |= Wexpand;
			}
			s[n++] = c;
		} while (!isterm(c = in.getc()) && c != '\'');
	}
	if (lexdebug && s == "exit")
		exit;
	return (ref Item(Iword, ref Word(s, wf, Src(l, f.name)), nil, nil, nil, nil), c);
}

#
#	Get a line, mapping escape newline to space newline.
#
getline(in: ref Bufio->Iobuf): string
{
	if (inchan != nil) {
		alt {
		b := <-inchan =>
			if (inchan == nil)
				return nil;
			s := string b;
			n := len s;
			if (n > 1) {
				while (s[n - 2] == '\\' && s[n - 1] == '\n') {
					s[n - 2] = ' ';
					s[n - 1] = ' ';
					prprompt(1);
					b = <-inchan;
					if (b == nil)
						break;
					s += string b;
					n = len s;
				}
			}
			return s;
		b := <-servechan =>
			s := string b;
			sys->print("%s", s);
			return s;
		}
	} else {
		s := in.gets('\n');
		if (s == nil)
			return nil;
		n := len s;
		if (n > 1) {
			while (s[n - 2] == '\\' && s[n - 1] == '\n') {
				s[n - 2] = ' ';
				s[n - 1] = ' ';
				prprompt(1);
				t := in.gets('\n');
				if (t == nil)
					break;
				s += t;
				n = len s;
			}
		}
		return s;
	}
}

#
#	Interactive shell loop.
#
Env.interactive(e: self ref Env, fd: ref Sys->FD)
{
	in := bufio->fopen(fd, Sys->OREAD);
	if (in == nil)
		e.error(sys->sprint("could not fopen stdin: %r\n"));
	e.flags |= EInter;
	for (;;) {
		prprompt(0);
		if (startserve)
			e.serve();
		if ((s := getline(in)) == nil)
			exitmash();
		e.sopen(s);
		parse->parse(e);
		if (histchan != nil)
			histchan <-= array of byte s;
	}
}
