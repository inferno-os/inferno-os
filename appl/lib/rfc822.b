implement RFC822;

include "sys.m";
	sys: Sys;

include "bufio.m";
	bufio: Bufio;
	Iobuf: import bufio;
	
include "rfc822.m";

include "string.m";
	str: String;

include "daytime.m";
	daytime: Daytime;
	Tm: import daytime;

Minrequest: con 512;	# more than enough for most requests

Suffix: adt {
	suffix: string;
	generic: string;
	specific: string;
	encoding: string;
};

SuffixFile: con "/lib/mimetype";
mtime := 0;
qid: Sys->Qid;

suffixes: list of ref Suffix;

nomod(s: string)
{
	raise sys->sprint("internal: can't load %s: %r", s);
}

init(b: Bufio)
{
	sys = load Sys Sys->PATH;
	bufio = b;
	str = load String String->PATH;
	if(str == nil)
		nomod(String->PATH);
	daytime = load Daytime Daytime->PATH;
	if(daytime == nil)
		nomod(Daytime->PATH);
	readsuffixfile();
}

readheaders(fd: ref Iobuf, limit: int): array of (string, array of byte)
{
	n := 0;
	s := 0;
	b := array[Minrequest] of byte;
	nline := 0;
	lines: list of array of byte;
	while((c := fd.getb()) >= 0){
		if(c == '\r'){
			c = fd.getb();
			if(c < 0)
				break;
			if(c != '\n'){
				fd.ungetb();
				c = '\r';
			}
		}
		if(n >= len b){
			if(len b >= limit)
				return nil;
			ab := array[n+512] of byte;
			ab[0:] = b;
			b = ab;
		}
		b[n++] = byte c;
		if(c == '\n'){
			if(n == 1 || b[n-2] == byte '\n')
				break;	# empty line
			c = fd.getb();
			if(c < 0)
				break;
			if(c != ' ' && c != '\t'){	# not continued
				fd.ungetb();
				lines = b[s: n] :: lines;
				nline++;
				s = n;
			}else
				b[n-1] = byte ' ';
		}
	}
	if(n == 0)
		return nil;
	b = b[0: n];
	if(n != s){
		lines = b[s:n] :: lines;
		nline++;
	}
	a := array[nline] of (string, array of byte);
	for(; lines != nil; lines = tl lines){
		b = hd lines;
		name := "";
		for(i := 0; i < len b; i++)
			if(b[i] == byte ':'){
				name = str->tolower(string b[0:i]);
				b = b[i+1:];
				break;
			}
		a[--nline] = (name, b);
	}
	return a;
}

#
# *(";" parameter) used in transfer-extension, media-type and media-range
# parameter = attribute "=" value
# attribute = token
# value = token | quoted-string
#
parseparams(ps: ref Rfclex): list of (string, string)
{
	l: list of (string, string);
	do{
		if(ps.lex() != Word)
			break;
		attr := ps.wordval;
		if(ps.lex() != '=' || ps.lex() != Word && ps.tok != QString)
			break;
		l = (attr, ps.wordval) :: l;
	}while(ps.lex() == ';');
	ps.unlex();
	return rev(l);
}

#
# 1#transfer-coding
#
mimefields(ps: ref Rfclex): list of (string, list of (string, string))
{
	rf: list of (string, list of (string, string));
	do{
		if(ps.lex() == Word){
			w := ps.wordval;
			if(ps.lex() == ';'){
				rf = (w, parseparams(ps)) :: rf;
				ps.lex();
			}else
				rf = (w, nil) :: rf;
		}
	}while(ps.tok == ',');
	ps.unlex();
	f: list of (string, list of (string, string));
	for(; rf != nil; rf = tl rf)
		f = hd rf :: f;
	return f;
}

#	#(media-type | (media-range [accept-params]))	; Content-Type and Accept
#
#       media-type     = type "/" subtype *( ";" parameter )
#       type           = token
#       subtype        = token
#	LWS must not be used between type and subtype, nor between attribute and value (in parameter)
#
#	media-range = ("*/*" | type "/*" | type "/" subtype ) *(";' parameter)
#    	accept-params  = ";" "q" "=" qvalue *( accept-extension )
#	accept-extension = ";" token [ "=" ( token | quoted-string ) ]
#
#	1#( ( charset | "*" )[ ";" "q" "=" qvalue ] )		; Accept-Charset
#	1#( codings [ ";" "q" "=" qvalue ] )			; Accept-Encoding
#	1#( language-range [ ";" "q" "=" qvalue ] )		; Accept-Language
#
#	codings = ( content-coding | "*" )
#
parsecontent(ps: ref Rfclex, multipart: int, head: list of ref Content): list of ref Content
{
	do{
		if(ps.lex() == Word){
			generic := ps.wordval;
			specific := "*";
			if(ps.lex() == '/'){
				if(ps.lex() != Word)
					break;
				specific = ps.wordval;
				if(!multipart && specific != "*")
					break;
			}else if(multipart)
				break;	# syntax error
			else
				ps.unlex();
			params: list of (string, string) = nil;
			if(ps.lex() == ';'){
				params = parseparams(ps);
				ps.lex();
			}
			head = Content.mk(generic, specific, params) :: head;	# order reversed, but doesn't matter
		}
	}while(ps.tok == ',');
	ps.unlex();
	return head;
}

rev(l: list of (string, string)): list of (string, string)
{
	rl: list of (string, string);
	for(; l != nil; l = tl l)
		rl = hd l :: rl;
	return rl;
}

Rfclex.mk(a: array of byte): ref Rfclex
{
	ps := ref Rfclex;
	ps.fd = bufio->aopen(a);
	ps.tok = '\n';
	ps.eof = 0;
	return ps;
}

Rfclex.getc(ps: self ref Rfclex): int
{
	c := ps.fd.getb();
	if(c < 0)
		ps.eof = 1;
	return c;
}

Rfclex.ungetc(ps: self ref Rfclex)
{
	if(!ps.eof)
		ps.fd.ungetb();
}

Rfclex.lex(ps: self ref Rfclex): int
{
	if(ps.seen != nil){
		(ps.tok, ps.wordval) = hd ps.seen;
		ps.seen = tl ps.seen;
	}else
		ps.tok = lex1(ps, 0);
	return ps.tok;
}

Rfclex.unlex(ps: self ref Rfclex)
{
	ps.seen = (ps.tok, ps.wordval) :: ps.seen;
}

Rfclex.skipws(ps: self ref Rfclex): int
{
	return lex1(ps, 1);
}

#
# rfc 2822/rfc 1521 lexical analyzer
#
lex1(ps: ref Rfclex, skipwhite: int): int
{
	ps.wordval = nil;
	while((c := ps.getc()) >= 0){
		case c {
		 '(' =>
			level := 1;
			while((c = ps.getc()) != Bufio->EOF && c != '\n'){
				if(c == '\\'){
					c = ps.getc();
					if(c == Bufio->EOF)
						return '\n';
					continue;
				}
				if(c == '(')
					level++;
				else if(c == ')' && --level == 0)
					break;
			}
 		' ' or '\t' or '\r' or 0 =>
			;
 		'\n' =>
			return '\n';
		')' or '<' or '>' or '[' or ']' or '@' or '/' or ',' or
		';' or ':' or '?' or '=' =>
			if(skipwhite){
				ps.ungetc();
				return c;
			}
			return c;

 		'"' =>
			if(skipwhite){
				ps.ungetc();
				return c;
			}
			word(ps,"\"");
			ps.getc();		# skip the closing quote 
			return QString;

 		* =>
			ps.ungetc();
			if(skipwhite)
				return c;
			word(ps,"\"()<>@,;:/[]?={}\r\n \t");
			return Word;
		}
	}
	return '\n';
}

# return the rest of an rfc 822 line, not including \r or \n
# do not map to lower case

Rfclex.line(ps: self ref Rfclex): string
{
	s := "";
	while((c := ps.getc()) != Bufio->EOF && c != '\n' && c != '\r'){
		if(c == '\\'){
			c = ps.getc();
			if(c == Bufio->EOF)
				break;
		}
		s[len s] = c;
	}
	ps.tok = '\n';
	ps.wordval = s;
	return s;
}

word(ps: ref Rfclex, stop: string)
{
	w := "";
	while((c := ps.getc()) != Bufio->EOF){
		if(c == '\r')
			c = ' ';
		if(c == '\\'){
			c = ps.getc();
			if(c == Bufio->EOF)
				break;
		}else if(str->in(c,stop)){
			ps.ungetc();
			break;
		}
		if(c >= 'A' && c <= 'Z')
			c += 'a' - 'A';
		w[len w] = c;
	}
	ps.wordval = w;
}

readsuffixfile(): string
{
	iob := bufio->open(SuffixFile, Bufio->OREAD);
	if(iob == nil)
		return sys->sprint("cannot open %s: %r", SuffixFile);
	for(n := 1; (line := iob.gets('\n')) != nil; n++){
		(s, nil) := parsesuffix(line);
		if(s != nil)
			suffixes =  s :: suffixes;
	}
	return nil;
}

parsesuffix(line: string): (ref Suffix, string)
{
	(line, nil) = str->splitstrl(line, "#");
	if(line == nil)
		return (nil, nil);
	(n, slist) := sys->tokenize(line,"\n\t ");
	if(n == 0)
		return (nil, nil);
	if(n < 4)
		return (nil, "too few fields");
	s := ref Suffix;
	s.suffix = hd slist;
	slist = tl slist;
	s.generic = hd slist;
	if (s.generic == "-")
		s.generic = "";	
	slist = tl slist;
	s.specific = hd slist;
	if (s.specific == "-")
		s.specific = "";	
	slist = tl slist;
	s.encoding = hd slist;
	if (s.encoding == "-")
		s.encoding = "";
	if((s.generic == nil || s.specific == nil) && s.encoding == nil)
		return (nil, nil);
	return (s, nil);
}

#
# classify by file suffix
#
suffixclass(name: string): (ref Content, ref Content)
{
	typ, enc: ref Content;

	p := str->splitstrr(name, "/").t1;
	if(p != nil)
		name = p;

	for(;;){
		(name, p) = suffix(name);	# TO DO: match below is case sensitive
		if(p == nil)
			break;
		for(l := suffixes; l != nil; l = tl l){
			s := hd l;
			if(p == s.suffix){	
				if(s.generic != nil && typ == nil)
					typ = Content.mk(s.generic, s.specific, nil);
				if(s.encoding != nil && enc == nil)
					enc = Content.mk(s.encoding, "", nil);
				if(typ != nil && enc != nil)
					break;
			}
		}
	}
	return (typ, enc);
}

suffix(s: string): (string, string)
{
	for(n := len s; --n >= 0;)
		if(s[n] == '.')
			return (s[0: n], s[n:]);
	return (s, nil);
}

#
#  classify by initial contents of file
#
dataclass(a: array of byte): (ref Content, ref Content)
{
	utf8 := 0;
	for(i := 0; i < len a;){
		c := int a[i];
		if(c < 16r80){
			if(c < 32 && c != '\n' && c != '\r' && c != '\t' && c != '\v' && c != '\f')
				return (nil, nil);
			i++;
		}else{
			utf8 = 1;
			(r, l, nil) := sys->byte2char(a, i);
			if(r == Sys->UTFerror)
				return (nil, nil);
			i += l;
		}
	}
	if(utf8)
		params := ("charset", "utf-8") :: nil;
	return (Content.mk("text", "plain", params), nil);
}

Content.mk(generic, specific: string, params: list of (string, string)): ref Content
{
	c := ref Content;	
	c.generic = generic;
	c.specific = specific;
	c.params = params;
	return c;
}

Content.check(me: self ref Content, oks: list of ref Content): int
{
	if(oks == nil)
		return 1;
	g := str->tolower(me.generic);
	s := str->tolower(me.specific);
	for(; oks != nil; oks = tl oks){
		ok := hd oks;
		if((ok.generic == g || ok.generic=="*") &&
		   (s == nil || ok.specific == s || ok.specific=="*"))
			return 1;
	}
	return 0;
}

Content.text(c: self ref Content): string
{
	if((s := c.specific) != nil)
		s = c.generic+"/"+s;
	else
		s = c.generic;
	for(l := c.params; l != nil; l = tl l){
		(n, v) := hd l;
		s += sys->sprint(";%s=%s", n, quote(v));
	}
	return s;
}

#
# should probably be in a Mime or HTTP module
#

Quotable: con "()<>@,;:\\\"/[]?={} \t";

quotable(s: string): int
{
	for(i := 0; i < len s; i++)
		if(str->in(s[i], Quotable))
			return 1;
	return 0;
}

quote(s: string): string
{
	if(!quotable(s))
		return s;
	q :=  "\"";
	for(i := 0; i < len s; i++){
		if(str->in(s[i], Quotable))
			q[len q] = '\\';
		q[len q] = s[i];
	}
	q[len q] = '"';
	return q;
}

weekdays := array[] of {
	"Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"
};

months := array[] of {
	"Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"
};

# print dates in the format
# Wkd, DD Mon YYYY HH:MM:SS GMT

sec2date(t: int): string
{
	tm := daytime->gmt(t);
	return sys->sprint("%s, %.2d %s %.4d %.2d:%.2d:%.2d GMT",
		weekdays[tm.wday], tm.mday, months[tm.mon], tm.year+1900,
		tm.hour, tm.min, tm.sec);	
}

# parse dates of formats
# Wkd, DD Mon YYYY HH:MM:SS GMT
# Weekday, DD-Mon-YY HH:MM:SS GMT
# Wkd Mon ( D|DD) HH:MM:SS YYYY
# plus anything similar

date2sec(date: string): int
{
	tm := daytime->string2tm(date);
	if(tm == nil || tm.year < 70 || tm.zone != "GMT")
		t := 0;
	else
		t = daytime->tm2epoch(tm);
	return t;
}

now(): int
{
	return daytime->now();
}

time(): string
{
	return sec2date(daytime->now());
}
