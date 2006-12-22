implement UBFa;

#
# UBF(A) data encoding interpreter
#

include "sys.m";
	sys: Sys;

include "bufio.m";
	bufio: Bufio;
	Iobuf: import bufio;

include "ubfa.m";

Syntax: exception(string);
Badwrite: exception;

dict: array of list of string;
dictlock: chan of int;

init(m: Bufio)
{
	sys = load Sys Sys->PATH;
	bufio = m;

	dict = array[74] of list of string;
	dictlock = chan[1] of int;
}

uvatom(s: string): ref UValue.Atom
{
	return ref UValue.Atom(uniq(s));
}

uvint(i: int): ref UValue.Int
{
	return ref UValue.Int(i);
}

uvbig(i: big): ref UValue.Int
{
	return ref UValue.Int(int i);
}

uvbinary(a: array of byte): ref UValue.Binary
{
	return ref UValue.Binary(a);
}

uvstring(s: string): ref UValue.String
{
	return ref UValue.String(s);
}

uvtuple(a: array of ref UValue): ref UValue.Tuple
{
	return ref UValue.Tuple(a);
}

uvlist(l: list of ref UValue): ref UValue.List
{
	return ref UValue.List(l);
}

uvtag(s: string, o: ref UValue): ref UValue.Tag
{
	return ref UValue.Tag(uniq(s), o);
}

# needed only to avoid O(n) len s.s
Stack: adt {
	s:	list of ref UValue;
	n:	int;

	new:	fn(): ref Stack;
	pop:	fn(s: self ref Stack): ref UValue raises(Syntax);
	push:	fn(s: self ref Stack, o: ref UValue);
};

Stack.new(): ref Stack
{
	return ref Stack(nil, 0);
}

Stack.pop(s: self ref Stack): ref UValue raises(Syntax)
{
	if(--s.n < 0 || s.s == nil)
		raise Syntax("parse stack underflow");
	v := hd s.s;
	s.s = tl s.s;
	return v;
}

Stack.push(s: self ref Stack, o: ref UValue)
{
	s.s = o :: s.s;
	s.n++;
}

Parse: adt {
	input:	ref Iobuf;
	stack:	ref Stack;
	reg:		array of ref UValue;

	getb:		fn(nil: self ref Parse): int raises(Syntax);
	unget:	fn(nil: self ref Parse);
};

Parse.getb(p: self ref Parse): int raises(Syntax)
{
	c := p.input.getb();
	if(c < 0){
		if(c == Bufio->EOF)
			raise Syntax("unexpected end-of-file");
		raise Syntax(sys->sprint("read error: %r"));
	}
	return c;
}

Parse.unget(p: self ref Parse)
{
	p.input.ungetb();
}

uniq(s: string): string
{
	if(s == nil)
		return "";
	dictlock <-= 1;
	h := 0;
	for(i:=0; i<len s; i++){
		h = (h<<4) + s[i];
		if((g := h & int 16rF0000000) != 0)
			h ^= ((g>>24) & 16rFF) | g;
	}
	h = (h & Sys->Maxint)%len dict;
	for(l := dict[h]; l != nil; l = tl l)
		if(hd l == s){
			s = hd l;	# share space
			break;
		}
	if(l == nil)
		dict[h] = s :: dict[h];
	<-dictlock;
	return s;
}

writeubf(out: ref Iobuf, obj: ref UValue): int
{
	{
		# write it out, put final '$'
		if(out != nil)
			writeobj(out, obj);
		putc(out, '$');
		return 0;
	}exception{
	Badwrite =>
		return -1;
	}
}

readubf(input: ref Iobuf): (ref UValue, string)
{
	{
		return (getobj(ref Parse(input, Stack.new(), array[256] of ref UValue)), nil);
	}exception e{
	Syntax =>
		return (nil, sys->sprint("ubf error: offset %bd: %s", input.offset(), e));
	}
}

UValue.isatom(o: self ref UValue): int
{
	return tagof o == tagof UValue.Atom;
}

UValue.isstring(o: self ref UValue): int
{
	return tagof o == tagof UValue.String;
}

UValue.isint(o: self ref UValue): int
{
	return tagof o == tagof UValue.Int;
}

UValue.islist(o: self ref UValue): int
{
	return tagof o == tagof UValue.List;
}

UValue.istuple(o: self ref UValue): int
{
	return tagof o == tagof UValue.Tuple;
}

UValue.isbinary(o: self ref UValue): int
{
	return tagof o == tagof UValue.Binary;
}

UValue.istag(o: self ref UValue): int
{
	return tagof o == tagof UValue.Tag;
}

UValue.isop(o: self ref UValue, op: string, arity: int): int
{
	pick r := o {
	Tuple =>
		if(len r.a > 0 && (arity <= 0 || len r.a == arity))
			pick s := r.a[0] {
			Atom =>
				return s.name == op;
			String =>
				return s.s == op;
			}
	}
	return 0;
}

UValue.op(o: self ref UValue, arity: int): string
{
	pick r := o {
	Tuple =>
		if(len r.a > 0 && (arity <= 0 || len r.a == arity))
			pick s := r.a[0] {
			Atom =>
				return  s.name;
			String =>
				return s.s;
			}
	}
	return nil;
}

UValue.args(o: self ref UValue, arity: int): array of ref UValue
{
	pick r := o {
	Tuple =>
		if(len r.a > 0 && (arity <= 0 || len r.a == arity))
			return r.a[1:];
	}
	return nil;
}

UValue.els(o: self ref UValue): list of ref UValue
{
	pick r := o {
	List =>
		return r.l;
	}
	return nil;
}

UValue.val(o: self ref UValue): int
{
	pick r :=  o {
	Int =>
		return r.value;
	}
	return 0;
}

UValue.objtag(o: self ref UValue): string
{
	pick r := o {
	Tag =>
		return r.name;
	}
	return nil;
}

UValue.obj(o: self ref UValue): ref UValue
{
	pick r := o {
	Tag =>
		return r.o;
	}
	return o;
}

UValue.binary(o: self ref UValue): array of byte
{
	pick r := o {
	Atom =>
		return array of byte r.name;
	String =>
		return array of byte r.s;
	Binary =>
		return r.a;
	}
	return nil;
}

UValue.text(o: self ref UValue): string
{
	pick r := o {
	Atom =>
		return r.name;
	String =>
		return r.s;
	Int =>
		return string r.value;
	Tuple =>
		s := "{";
		for(i := 0; i < len r.a; i++)
			s += " "+r.a[i].text();
		return s+"}";
	List =>
		s := "[";
		for(l := r.l; l != nil; l = tl l)
			s += " "+(hd l).text();
		return s+"]";
	Binary =>
		s := "<<";
		for(i := 0; i < len r.a; i++)
			s += sys->sprint(" %.2ux", int r.a[i]);
		return s+">>";
	Tag =>
		return "{'$TYPE', "+r.name+", "+r.o.text()+"}";
	* =>
		return "unknown";
	}
}

UValue.eq(o: self ref UValue, v: ref UValue): int
{
	if(v == nil)
		return 0;
	if(o == v)
		return 1;
	pick r := o {
	Atom =>
		pick s := v {
		Atom =>
			return r.name == s.name;
		}
		return 0;
	String =>
		pick s := v {
		String =>
			return r.s == s.s;
		}
		return 0;
	Int =>
		pick s := v {
		Int =>
			return r.value == s.value;
		}
	Tuple =>
		pick s := v {
		Tuple =>
			if(len r.a != len s.a)
				return 0;
			for(i := 0; i < len r.a; i++)
				if(!r.a[i].eq(s.a[i]))
					return 0;
			return 1;
		}
		return 0;
	List =>
		pick s := v {
		List =>
			l1 := r.l;
			l2 := s.l;
			while(l1 != nil && l2 != nil){
				if(!(hd l1).eq(hd l2))
					return 0;
				l1 = tl l1;
				l2 = tl l2;
			}
			return l1 == l2;
		}
		return 0;
	Binary =>
		pick s := v {
		Binary =>
			if(len r.a != len s.a)
				return 0;
			for(i := 0; i < len r.a; i++)
				if(r.a[i] != s.a[i])
					return 0;
			return 1;
		}
		return 0;
	Tag =>
		pick s := v {
		Tag =>
			return r.name == s.name && r.o.eq(s.o);
		}
		return 0;
	* =>
		raise "ubf: bad object";	# can't happen
	}
}

S: con byte 1;

special := array[256] of {
	'\n' or '\r' or '\t' or ' ' or ',' => S,
	'}' => S, '$' => S, '>' => S, '#' => S, '&' => S,
	'"' => S, '\'' => S, '{' => S, '~' => S, '-' => S,
	'0' to '9' => S, '%' => S, '`' => S, * => byte 0
};

getobj(p: ref Parse): ref UValue raises(Syntax)
{
	{
		for(;;){
			case p.getb() {
			'\n' or '\r' or '\t' or ' ' or ',' =>
				;	# white space
			'%' =>
				while((c := p.getb()) != '%'){
					if(c == '\\'){	# do comments really use \?
						c = p.getb();
						if(c != '\\' && c != '%')
							raise Syntax("invalid escape in comment");
					}
				}
			'}' =>
				a := array[p.stack.n] of ref UValue;
				for(i := len a; --i >= 0;)
					a[i] = p.stack.pop();
				return ref UValue.Tuple(a);
			'$' =>
				if(p.stack.n != 1)
					raise Syntax("unbalanced stack: size "+string p.stack.n);
				return p.stack.pop();
			'>' =>
				r := p.getb();
				if(special[r] == S)
					raise Syntax("invalid register name");
				p.reg[r] = p.stack.pop();
			'`' =>
				t := uniq(readdelimitedstring(p, '`'));
				p.stack.push(ref UValue.Tag(t, p.stack.pop()));
			* =>
				p.unget();
				p.stack.push(readobj(p));
			}
		}
	}exception{
	Syntax =>
		raise;
	}
}

readobj(p: ref Parse): ref UValue raises(Syntax)
{
	{
	 	case c := p.getb() {
		'#' =>
			return ref UValue.List(nil);
		'&' =>
			a := p.stack.pop();
			b := p.stack.pop();
			pick r := b {
			List =>
				return ref UValue.List(a :: r.l);	# not changed in place: might be shared register value
			* =>
				raise Syntax("can't make cons with cdr "+b.text());
			}
		'"' =>
			return ref UValue.String(readdelimitedstring(p, c));
		'\'' =>
			return ref UValue.Atom(uniq(readdelimitedstring(p, c)));
		'{' =>
			obj := getobj(ref Parse(p.input, Stack.new(), p.reg));
			if(!obj.istuple())
				raise Syntax("expected tuple: obj");
			return obj;
		'~' =>
			o := p.stack.pop();
			if(!o.isint())
				raise Syntax("expected Int before ~");
			n := o.val();
			if(n < 0)
				raise Syntax("negative length for binary");
			a := array[n] of byte;
			n = p.input.read(a, len a);
			if(n != len a){
				if(n != Bufio->ERROR)
					sys->werrstr("short read");
				raise Syntax(sys->sprint("cannot read binary data: %r"));
			}
			if(p.getb() != '~')
				raise Syntax("missing closing ~");
			return ref UValue.Binary(a);
		'-' or '0' to '9' =>
			p.unget();
			return ref UValue.Int(int readinteger(p));
		* =>
			if(p.reg[c] != nil)
				return p.reg[c];
			p.unget();	# point to error
			raise Syntax(sys->sprint("invalid start character/undefined register #%.2ux",c));
		}
	}exception{
	Syntax =>
		raise;
	}
}

readdelimitedstring(p: ref Parse, delim: int): string raises(Syntax)
{
	{
		s := "";
		while((c := p.input.getc()) != delim){	# note: we'll use UTF-8
			if(c < 0){
				if(c == Bufio->ERROR)
					raise Syntax(sys->sprint("read error: %r"));
				raise Syntax("unexpected end of file");
			}
			if(c == '\\'){
				c = p.getb();
				if(c != '\\' && c != delim)
					raise Syntax("invalid escape");
			}
			s[len s] = c;
		}
		return s;
	}exception{
	Syntax =>
		raise;
	}
}

readinteger(p: ref Parse): big raises(Syntax)
{
	sign := 1;
	c := p.getb();
	if(c == '-'){
		sign = -1;
		c = p.getb();
		if(!(c >= '0' && c <= '9'))
			raise Syntax("expected integer literal");
	}
	for(n := big 0; c >= '0' && c <= '9'; c = p.getb()){
		n = n*big 10 + big((c-'0')*sign);
		if(n > big Sys->Maxint || n < big(-Sys->Maxint-1))
			raise Syntax("integer overflow");
	}
	p.unget();
	return n;
}

writeobj(out: ref Iobuf, o: ref UValue) raises(Badwrite)
{
	{
		pick r := o {
		Atom =>
			writedelimitedstring(out, r.name, '\'');
		String =>
			writedelimitedstring(out, r.s, '"');
		Int =>
			puts(out, string r.value);
		Tuple =>	# { el * }
			putc(out, '{');
			for(i := 0; i < len r.a; i++){
				if(i != 0)
					putc(out, ' ');
				writeobj(out, r.a[i]);
			}
			putc(out, '}');
		List =>	# # eN & eN-1 & ... & e0 &
			putc(out, '#');
			# put them out in reverse order, each followed by '&'
			rl: list of ref UValue;
			for(l := r.l; l != nil; l = tl l)
				rl = hd l :: rl;
			for(; rl != nil; rl = tl rl){
				writeobj(out, hd rl);
				putc(out, '&');
			}
		Binary =>	# Int ~data~
			puts(out, string len r.a);
			putc(out, '~');
			if(out.write(r.a, len r.a) != len r.a)
				raise Badwrite;
			putc(out, '~');
		Tag =>	# obj `tag`
			writeobj(out, r.o);
			writedelimitedstring(out, r.name, '`');
		* =>
			raise "ubf: unknown object";	# can't happen
		}
	}exception{
	Badwrite =>
		raise;
	}
}

writedelimitedstring(out: ref Iobuf, s: string, d: int) raises(Badwrite)
{
	{
		putc(out, d);
		for(i := 0; i < len s; i++){
			c := s[i];
			if(c == d || c == '\\')
				putc(out, '\\');
			putc(out, c);
		}
		putc(out, d);
	}exception{
	Badwrite =>
		raise;
	}
}

puts(out: ref Iobuf, s: string) raises(Badwrite)
{
	if(out.puts(s) == Bufio->ERROR)
		raise Badwrite;
}

putc(out: ref Iobuf, c: int) raises(Badwrite)
{
	if(out.putc(c) == Bufio->ERROR)
		raise Badwrite;
}
