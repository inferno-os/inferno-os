implement Sexprs;

#
# full SDSI/SPKI S-expression reader
#
# Copyright © 2003-2004 Vita Nuova Holdings Limited
#

include "sys.m";
	sys: Sys;

include "encoding.m";
	base64: Encoding;
	base16: Encoding;

include "bufio.m";
	bufio: Bufio;
	Iobuf: import bufio;

include "sexprs.m";

Maxtoken: con 1024*1024;	# should be more than enough

Syntax: exception(string, big);
Here: con big -1;

Rd: adt[T]
	for {
	T =>
		getb:	fn(nil: self T): int;
		ungetb:	fn(nil: self T): int;
		offset:	fn(nil: self T): big;
	}
{
	t:	T;

	parseitem:	fn(rd: self ref Rd[T]): ref Sexp raises (Syntax);
	ws:	fn(rd: self ref Rd[T]): int;
	simplestring:	fn(rd: self ref Rd[T], c: int, hint: string): ref Sexp raises (Syntax);
	toclosing:	fn(rd: self ref Rd[T], c: int): string raises (Syntax);
	unquote:	fn(rd: self ref Rd[T]): string raises (Syntax);
};

init()
{
	sys = load Sys Sys->PATH;
	base64 = load Encoding Encoding->BASE64PATH;
	base16 = load Encoding Encoding->BASE16PATH;
	bufio = load Bufio Bufio->PATH;
	bufio->sopen("");
}

Sexp.read[T](t: T): (ref Sexp, string)
	for {
	T =>
		getb:	fn(nil: self T): int;
		ungetb:	fn(nil: self T): int;
		offset:	fn(nil: self T): big;
	}
{
	{
		rd := ref Rd[T](t);
		e := rd.parseitem();
		return (e, nil);
	}exception e {
	Syntax =>
		(diag, pos) := e;
		if(pos < big 0)
			pos += t.offset();
		return (nil, sys->sprint("%s at offset %bd", diag, pos));
	}
}

Sexp.parse(s: string): (ref Sexp, string, string)
{
	f := bufio->sopen(s);
	(e, diag) := Sexp.read(f);
	pos := int f.offset();
	return (e, s[pos:], diag);
}

Sexp.unpack(a: array of byte): (ref Sexp, array of byte, string)
{
	f := bufio->aopen(a);
	(e, diag) := Sexp.read(f);
	pos := int f.offset();
	return (e, a[pos:], diag);
}

Rd[T].parseitem(rd: self ref Rd[T]): ref Sexp raises (Syntax)
{
	p0 := rd.t.offset();
	{
		c := rd.ws();
		if(c < 0)
			return nil;
		case c {
		'{' =>
			a := rd.toclosing('}');
			f := bufio->aopen(base64->dec(a));
			ht: type Rd[ref Iobuf];
			nr := ref ht(f);
			return nr.parseitem();
		'(' =>
			lists: list of ref Sexp;
			while((c = rd.ws()) != ')'){
				if(c < 0)
					raise Syntax("unclosed '('", p0);
				rd.t.ungetb();
				e := rd.parseitem();	# we'll catch missing ) at top of loop
				lists = e :: lists;
			}
			rl := lists;
			lists = nil;
			for(; rl != nil; rl = tl rl)
				lists = hd rl :: lists;
			return ref Sexp.List(lists);
		'[' =>
			# display hint
			e := rd.simplestring(rd.t.getb(), nil);
			c = rd.ws();
			if(c != ']'){
				if(c >= 0)
					rd.t.ungetb();
				raise Syntax("missing ] in display hint", p0);
			}
			pick r := e {
			String =>
				return rd.simplestring(rd.ws(), r.s);
			* =>
				raise Syntax("illegal display hint", Here);
			}
		* =>
			return rd.simplestring(c, nil);
		}
	}exception{
	Syntax => raise;
	}
}

# skip white space
Rd[T].ws(rd: self ref Rd[T]): int
{
	while(isspace(c := rd.t.getb()))
		{}
	return c;
}

isspace(c: int): int
{
	return c == ' ' || c == '\r' || c == '\t' || c == '\n';
}

Rd[T].simplestring(rd: self ref Rd[T], c: int, hint: string): ref Sexp raises (Syntax)
{
	dec := -1;
	decs: string;
	if(c >= '0' && c <= '9'){
		for(dec = 0; c >= '0' && c <= '9'; c = rd.t.getb()){
			dec = dec*10 + c-'0';
			decs[len decs] = c;
		}
		if(dec < 0 || dec > Maxtoken)
			raise Syntax("implausible token length", Here);
	}
	{
		case c {
		'"' =>
			text := rd.unquote();
			return ref Sexp.String(text, hint);
		'|' =>
			return sform(base64->dec(rd.toclosing(c)), hint);
		'#' =>
			return sform(base16->dec(rd.toclosing(c)), hint);
		* =>
			if(c == ':' && dec >= 0){	# raw bytes
				a := array[dec] of byte;
				for(i := 0; i < dec; i++){
					c = rd.t.getb();
					if(c < 0)
						raise Syntax("missing bytes in raw token", Here);
					a[i] = byte c;
				}
				return sform(a, hint);
			}
			#s := decs;
			if(decs != nil)
				raise Syntax("token can't start with a digit", Here);
			s: string;	# <token> by definition is always printable; never utf-8
			while(istokenc(c)){
				s[len s] = c;
				c = rd.t.getb();
			}
			if(s == nil)
				raise Syntax("missing token", Here);	# consume c to ensure progress on error
			if(c >= 0)
				rd.t.ungetb();
			return ref Sexp.String(s, hint);
		}
	}exception{
	Syntax => raise;
	}
}

sform(a: array of byte, hint: string): ref Sexp
{
	if(istextual(a))
		return ref Sexp.String(string a, hint);
	return ref Sexp.Binary(a, hint);
}

Rd[T].toclosing(rd: self ref Rd[T], end: int): string raises (Syntax)
{
	s: string;
	p0 := rd.t.offset();
	while((c := rd.t.getb()) != end){
		if(c < 0)
			raise Syntax(sys->sprint("missing closing '%c'", end), p0);
		s[len s] = c;
	}
	return s;
}

hex(c: int): int
{
	if(c >= '0' && c <= '9')
		return c-'0';
	if(c >= 'a' && c <= 'f')
		return 10+(c-'a');
	if(c >= 'A' && c <= 'F')
		return 10+(c-'A');
	return -1;
}

Rd[T].unquote(rd: self ref Rd[T]): string raises (Syntax)
{
	os: string;

	p0 := rd.t.offset();
	while((c := rd.t.getb()) != '"'){
		if(c < 0)
			raise Syntax("unclosed quoted string", p0);
		if(c == '\\'){
			e0 := rd.t.offset();
			c = rd.t.getb();
			if(c < 0)
				break;
			case c {
			'\r' =>
				c = rd.t.getb();
				if(c != '\n')
					rd.t.ungetb();
				continue;
			'\n' =>
				c = rd.t.getb();
				if(c != '\r')
					rd.t.ungetb();
				continue;
			'b' =>
				c = '\b';
			'f' =>
				c = '\f';
			'n' =>
				c = '\n';
			'r' =>
				c = '\r';
			't' =>
				c = '\t';
			'v' =>
				c = '\v';
			'0' to '7' =>
				oct := 0;
				for(i := 0;;){
					if(!(c >= '0' && c <= '7'))
						raise Syntax("illegal octal escape", e0);
					oct = (oct<<3) | (c-'0');
					if(++i == 3)
						break;
					c = rd.t.getb();
				}
				c = oct & 16rFF;
			'x' =>
				c0 := hex(rd.t.getb());
				c1 := hex(rd.t.getb());
				if(c0 < 0 || c1 < 0)
					raise Syntax("illegal hex escape", e0);
				c = (c0<<4) | c1;
			* =>
				;	# as-is
			}
		}
		os[len os] = c;
	}
	return os;
}

hintlen(s: string): int
{
	if(s == nil)
		return 0;
	n := len array of byte s;
	return len sys->aprint("[%d:]", n) + n;
}

Sexp.packedsize(e: self ref Sexp): int
{
	if(e == nil)
		return 0;
	pick r := e{
	String =>
		n := len array of byte r.s;
		return hintlen(r.hint) + len sys->aprint("%d:", n) + n;
	Binary =>
		n := len r.data;
		return hintlen(r.hint) + len sys->aprint("%d:", n) + n;
	List =>
		n := 1;	# '('
		for(l := r.l; l != nil; l = tl l)
			n += (hd l).packedsize();
		return n+1;	# + ')'
	}
}

packbytes(a: array of byte, b: array of byte): array of byte
{
	n := len b;
	c := sys->aprint("%d:", n);
	a[0:] = c;
	a[len c:] = b;
	return a[len c+n:];
}

packhint(a: array of byte, s: string): array of byte
{
	if(s == nil)
		return a;
	a[0] = byte '[';
	a = packbytes(a[1:], array of byte s);
	a[0] = byte ']';
	return a[1:];
}

pack(e: ref Sexp, a: array of byte): array of byte
{
	if(e == nil)
		return array[0] of byte;
	pick r := e{
	String =>
		if(r.hint != nil)
			a = packhint(a, r.hint);
		return packbytes(a, array of byte r.s);
	Binary =>
		if(r.hint != nil)
			a = packhint(a, r.hint);
		return packbytes(a, r.data);
	List =>
		a[0] = byte '(';
		a = a[1:];
		for(l := r.l; l != nil; l = tl l)
			a = pack(hd l, a);
		a[0] = byte ')';
		return a[1:];
	}
}

Sexp.pack(e: self ref Sexp): array of byte
{
	a := array[e.packedsize()] of byte;
	pack(e, a);
	return a;
}

Sexp.b64text(e: self ref Sexp): string
{
	return "{" + base64->enc(e.pack()) + "}";
}

Sexp.text(e: self ref Sexp): string
{
	if(e == nil)
		return "";
	pick r := e{
	String =>
		s := quote(r.s);
		if(r.hint == nil)
			return s;
		return "["+quote(r.hint)+"]"+s;
	Binary =>
		h := r.hint;
		if(h != nil)
			h = "["+quote(h)+"]";
		if(len r.data <= 4)
			return sys->sprint("%s#%s#", h, base16->enc(r.data));
		return sys->sprint("%s|%s|", h, base64->enc(r.data));
	List =>
		s := "(";
		for(l := r.l; l != nil; l = tl l){
			s += (hd l).text();
			if(tl l != nil)
				s += " ";
		}
		return s+")";
	}
}

#An octet string that meets the following conditions may be given
#directly as a "token".
#
#	-- it does not begin with a digit
#
#	-- it contains only characters that are
#		-- alphabetic (upper or lower case),
#		-- numeric, or
#		-- one of the eight "pseudo-alphabetic" punctuation marks:
#			-   .   /   _   :  *  +  =  
#	(Note: upper and lower case are not equivalent.)
#	(Note: A token may begin with punctuation, including ":").

istokenc(c: int): int
{
	return c >= '0' && c <= '9' ||
		c >= 'a' && c <= 'z' || c >= 'A' && c <= 'Z' ||
		c == '-' || c == '.' || c == '/' || c == '_' || c == ':' || c == '*' || c == '+' || c == '=';
}

istoken(s: string): int
{
	if(s == nil)
		return 0;
	for(i := 0; i < len s; i++)
		case s[i] {
		'0' to '9' =>
			if(i == 0)
				return 0;
		'a' to 'z' or 'A' to 'Z' or
		'-' or '.' or '/' or '_' or ':' or '*' or '+' or '=' =>
			break;
		* =>
			return 0;
		}
	return 1;
}

# should the data qualify as binary or text?
# the if(0) version accepts valid Unicode sequences
# could use [display] to control character set?
istextual(a: array of byte): int
{
	for(i := 0; i < len a;){
		if(0){
			(c, n, ok) := sys->byte2char(a, i);
			if(!ok || c < ' ' && !isspace(c) || c >= 16r7F)
				return 0;
			i += n;
		}else{
			c := int a[i++];
			if(c < ' ' && !isspace(c) || c >= 16r7F)
				return 0;
		}
	}
	return 1;
}

esc(c: int): string
{
	case c {
	'"' =>	return "\\\"";
	'\\' =>	return "\\\\";
	'\b' =>	return "\\b";
	'\f' =>	return "\\f";
	'\n' =>	return "\\n";
	'\t' =>	return "\\t";
	'\r' =>	return "\\r";
	'\v' =>	return "\\v";
	* =>
		if(c < ' ' || c >= 16r7F)
			return sys->sprint("\\x%.2ux", c & 16rFF);
	}
	return nil;
}

quote(s: string): string
{
	if(istoken(s))
		return s;
	for(i := 0; i < len s; i++)
		if((v := esc(s[i])) != nil){
			os := "\"" + s[0:i] + v;
			while(++i < len s){
				if((v = esc(s[i])) != nil)
					os += v;
				else
					os[len os] = s[i];
			}
			os[len os] = '"';
			return os;
		}
	return "\""+s+"\"";
}

#
# other S expression operations
#
Sexp.islist(e: self ref Sexp): int
{
	return e != nil && tagof e == tagof Sexp.List;
}

Sexp.els(e: self ref Sexp): list of ref Sexp
{
	if(e == nil)
		return nil;
	pick s := e {
	List =>
		return s.l;
	* =>
		return nil;
	}
}

Sexp.op(e: self ref Sexp): string
{
	if(e == nil)
		return nil;
	pick s := e {
	String =>
		return s.s;
	Binary =>
		return nil;
	List =>
		if(s.l == nil)
			return nil;
		pick t := hd s.l {
		String =>
			return t.s;
		* =>
			return nil;
		}
	}
	return nil;
}

Sexp.args(e: self ref Sexp): list of ref Sexp
{
	if((l := e.els()) != nil)
		return tl l;
	return nil;
}

Sexp.asdata(e: self ref Sexp): array of byte
{
	if(e == nil)
		return nil;
	pick s := e {
	List =>
		return nil;
	String =>
		return array of byte s.s;
	Binary =>
		return s.data;
	}
}

Sexp.astext(e: self ref Sexp): string
{
	if(e == nil)
		return nil;
	pick s := e {
	List =>
		return nil;
	String =>
		return s.s;
	Binary =>
		return string s.data;	# questionable; should possibly treat it as latin-1
	}
}

Sexp.eq(e1: self ref Sexp, e2: ref Sexp): int
{
	if(e1 == e2)
		return 1;
	if(e1 == nil || e2 == nil || tagof e1 != tagof e2)
		return 0;
	pick s1 := e1 {
	List =>
		pick s2 := e2 {
		List =>
			l1 := s1.l;
			l2 := s2.l;
			for(; l1 != nil; l1 = tl l1){
				if(l2 == nil || !(hd l1).eq(hd l2))
					return 0;
				l2 = tl l2;
			}
			return l2 == nil;
		}
	String =>
		pick s2 := e2 {
		String =>
			return s1.s == s2.s && s1.hint == s2.hint;
		}
	Binary =>
		pick s2 := e2 {
		Binary =>
			if(len s1.data != len s2.data || s1.hint != s2.hint)
				return 0;
			for(i := 0; i < len s1.data; i++)
				if(s1.data[i] != s2.data[i])
					return 0;
			return 1;
		}
	}
	return 0;
}

Sexp.copy(e: self ref Sexp): ref Sexp
{
	if(e == nil)
		return nil;
	pick r := e {
	List =>
		rl: list of ref Sexp;
		for(l := r.l; l != nil; l = tl l)
			rl = (hd l).copy() :: rl;
		for(l = nil; rl != nil; rl = tl rl)
			l = hd rl :: l;
		return ref Sexp.List(l);
	String =>
		return ref *r;	# safe because .s and .hint are strings, immutable
	Binary =>
		b: array of byte;
		if((a := r.data) != nil){
			b = array[len a] of byte;
			b[0:] = a;
		}
		return ref Sexp.Binary(b, r.hint);
	}
}
