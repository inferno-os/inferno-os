implement Xml;

#
# Portions copyright © 2002 Vita Nuova Holdings Limited
#
#
# Derived from saxparser.b Copyright © 2001-2002 by John Powers or his employer
#

# TO DO:
# - provide a way of getting attributes out of <?...?> (process) requests,
# so that we can process stylesheet requests given in that way.

include "sys.m";
	sys: Sys;
include "bufio.m";
	bufio: Bufio;
	Iobuf: import bufio;
include "string.m";
	str: String;
include "hash.m";
	hash: Hash;
	HashTable: import hash;
include "xml.m";

Parcel: adt {
	pick {
	Start or
	Empty =>
		name: string;
		attrs: Attributes;
	End =>
		name: string;
	Text =>
		ch: string;
		ws1, ws2: int;
	Process =>
		target: string;
		data: string;
	Error =>
		loc:	Locator;
		msg:	string;
	Doctype =>
		name:	string;
		public:	int;
		params:	list of string;
	Stylesheet =>
		attrs: Attributes;
	EOF =>
	}
};

entinit := array[] of {
	("AElig", "Æ"),
	("OElig", "Œ"),
	("aelig", "æ"),
	("amp", "&"),
	("apos", "\'"),
	("copy", "©"),
	("gt", ">"),
	("ldquo", "``"),
	("lt", "<"),
	("mdash", "-"),		# XXX ??
	("oelig", "œ"),
	("quot", "\""),
	("rdquo", "''"),
	("rsquo", "'"),
	("trade", "™"),
	("nbsp", "\u00a0"),
};
entdict: ref HashTable;

init(): string
{
	sys = load Sys Sys->PATH;
	bufio = load Bufio Bufio->PATH;
	if (bufio == nil)
		return sys->sprint("cannot load %s: %r", Bufio->PATH);
	str = load String String->PATH;
	if (str == nil)
		return sys->sprint("cannot load %s: %r", String->PATH);
	hash = load Hash Hash->PATH;
	if (hash == nil)
		return sys->sprint("cannot load %s: %r", Hash->PATH);
	entdict = hash->new(23);
	for (i := 0; i < len entinit; i += 1) {
		(key, value) := entinit[i];
		entdict.insert(key, (0, 0.0, value));
	}
	return nil;
}

blankparser: Parser;

open(srcfile: string, warning: chan of (Locator, string), preelem: string): (ref Parser, string)
{
	x := ref blankparser;
	x.in = bufio->open(srcfile, Bufio->OREAD);
	if (x.in == nil)
		return (nil, sys->sprint("cannot open %s: %r", srcfile));
	# ignore utf16 intialisation character (yuck)
	c := x.in.getc();
	if (c != 16rfffe && c != 16rfeff)
		x.in.ungetc();
	x.estack = nil;
	x.loc = Locator(1, srcfile, "");
	x.warning = warning;
	x.preelem = preelem;
	return (x, "");
}

Parser.next(x: self ref Parser): ref Item
{
	curroffset := x.fileoffset;
	currloc := x.loc;
	# read up until end of current item
	while (x.actdepth > x.readdepth) {
		pick p := getparcel(x) {
		Start =>
			x.actdepth++;
		End =>
			x.actdepth--;
		EOF =>
			x.actdepth = 0;			# premature EOF closes all tags
		Error =>
			return ref Item.Error(curroffset, x.loc, x.errormsg);
		}
	}
	if (x.actdepth < x.readdepth) {
		x.fileoffset = int x.in.offset();
		return nil;
	}
	gp := getparcel(x);
	item: ref Item;
	pick p := gp {
	Start =>
		x.actdepth++;
		item = ref Item.Tag(curroffset, p.name, p.attrs);
	End =>
		x.actdepth--;
		item = nil;
	EOF =>
		x.actdepth = 0;
		item = nil;
	Error =>
		x.actdepth = 0;			# XXX is this the right thing to do?
		item = ref Item.Error(curroffset, currloc, x.errormsg);
	Text =>
		item = ref Item.Text(curroffset, p.ch, p.ws1, p.ws2);
	Process =>
		item = ref Item.Process(curroffset, p.target, p.data);
	Empty =>
		item = ref Item.Tag(curroffset, p.name, p.attrs);
	Doctype =>
		item = ref Item.Doctype(curroffset, p.name, p.public, p.params);
	Stylesheet =>
		item = ref Item.Stylesheet(curroffset, p.attrs);
	}
	x.fileoffset = int x.in.offset();
	return item;
}

Parser.atmark(x: self ref Parser, m: ref Mark): int
{
	return  int x.in.offset() == m.offset;
}

Parser.down(x: self ref Parser)
{
	x.readdepth++;
}

Parser.up(x: self ref Parser)
{
	x.readdepth--;
}

# mark is only defined after a next(), not after up() or down().
# this means that we don't have to record lots of state when going up or down levels.
Parser.mark(x: self ref Parser): ref Mark
{
	return ref Mark(x.estack, x.loc.line, int x.in.offset(), x.readdepth);
}

Parser.goto(x: self ref Parser, m: ref Mark)
{
	x.in.seek(big m.offset, Sys->SEEKSTART);
	x.fileoffset = m.offset;
	x.eof = 0;
	x.estack = m.estack;
	x.loc.line = m.line;
	x.readdepth = m.readdepth;
	x.actdepth = len x.estack;
}

Mark.str(m: self ref Mark): string
{
	# assume that neither the filename nor any of the tags contain spaces.
	# format:
	# offset readdepth linenum [tag...]
	# XXX would be nice if the produced string did not contain
	# any spaces so it could be treated as a word in other contexts.
	s := sys->sprint("%d %d %d", m.offset, m.readdepth, m.line);
	for (t := m.estack; t != nil; t = tl t)
		s += " " + hd t;
	return s;
}

Parser.str2mark(p: self ref Parser, s: string): ref Mark
{
	(n, toks) := sys->tokenize(s, " ");
	if (n < 3)
		return nil;
	m := ref Mark(nil, p.loc.line, 0, 0);
	(m.offset, toks) = (int hd toks, tl toks);
	(m.readdepth, toks) = (int hd toks, tl toks);
	(m.line, toks) = (int hd toks, tl toks);
	m.estack = toks;
	return m;
}

getparcel(x: ref Parser): ref Parcel
{
	{
		p: ref Parcel;
		while (!x.eof && p == nil) {
			c := getc(x);
			if (c == '<')
				p = element(x);
			else {
				ungetc(x);
				p = characters(x);
			}
		}
		if (p == nil)
			p = ref Parcel.EOF;
		return p;
	}
	exception e{
		"sax:*" =>
			return ref Parcel.Error(x.loc, x.errormsg);
	}
}

parcelstr(gi: ref Parcel): string
{
	if (gi == nil)
		return "nil";
	pick i := gi {
	Start =>
		return sys->sprint("Start: %s", i.name);
	Empty =>
		return sys->sprint("Empty: %s", i.name);
	End =>
		return "End";
	Text =>
		return "Text";
	Doctype =>
		return sys->sprint("Doctype: %s", i.name);
	Stylesheet =>
		return "Stylesheet";
	Error =>
		return "Error: " + i.msg;
	EOF =>
		return "EOF";
	* =>
		return "Unknown";
	}
}

element(x: ref Parser): ref Parcel
{
	# <tag ...>
	elemname := xmlname(x);
	c: int;
	if (elemname != "") {
		attrs := buildattrs(x);
		skipwhite(x);
		c = getc(x);
		isend := 0;
		if (c == '/')
			isend = 1;
		else
			ungetc(x);
		expect(x, '>');

		if (isend)
			return ref Parcel.Empty(elemname, attrs);
		else {
			startelement(x, elemname);
			return ref Parcel.Start(elemname, attrs);
		}
	# </tag>
	} else if ((c = getc(x)) == '/') {
		elemname = xmlname(x);
		if (elemname != "") {
			expect(x, '>');
			endelement(x, elemname);
			return ref Parcel.End(elemname);
		}
		else
			error(x, sys->sprint("illegal beginning of tag: '%c'", c));
	# <?tag ... ?>
	} else if (c == '?') {
		elemname = xmlname(x);
		if (elemname != "") {
			# this special case could be generalised if there were many
			# processing instructions that took attributes like this.
			if (elemname == "xml-stylesheet") {
				attrs := buildattrs(x);
				balancedstring(x, "?>");
				return ref Parcel.Stylesheet(attrs);
			} else {
				data := balancedstring(x, "?>");
				return ref Parcel.Process(elemname, data);
			}
		}
	} else if (c == '!') {
		c = getc(x);
		case c {
		'-' =>
			# <!-- comment -->
			if(getc(x) == '-'){
				balancedstring(x, "-->");
				return nil;
			}
		'[' =>
			# <![CDATA[...]]
			s := xmlname(x);
			if(s == "CDATA" && getc(x) == '['){
				data := balancedstring(x, "]]>");
				return ref Parcel.Text(data, 0, 0);
			}
		* =>
			# <!declaration
			ungetc(x);
			s := xmlname(x);
			case s {
			"DOCTYPE" =>
				# <!DOCTYPE name (SYSTEM "filename" | PUBLIC "pubid" "uri"?)? ("[" decls "]")?>
				skipwhite(x);
				name := xmlname(x);
				if(name == nil)
					break;
				id := "";
				uri := "";
				public := 0;
				skipwhite(x);
				case sort := xmlname(x) {
				"SYSTEM" =>
					id = xmlstring(x, 1);
				"PUBLIC" =>
					public = 1;
					id = xmlstring(x, 1);
					skipwhite(x);
					c = getc(x);
					ungetc(x);
					if(c == '"' || c == '\'')
						uri = xmlstring(x, 1);
				* =>
					error(x, sys->sprint("unknown DOCTYPE: %s", sort));
					return nil;
				}
				skipwhite(x);
				if(getc(x) == '['){
					error(x, "cannot handle DOCTYPE with declarations");
					return nil;
				}
				ungetc(x);
				skipwhite(x);
				if(getc(x) == '>')
					return ref Parcel.Doctype(name, public, id :: uri :: nil);
			"ELEMENT" or "ATTRLIST" or "NOTATION" or "ENTITY" =>
				# don't interpret internal DTDs
				# <!ENTITY name ("value" | SYSTEM "filename")>
				s = gets(x, '>');
				if(s == nil || s[len s-1] != '>')
					error(x, "end of file in declaration");
				return nil;
			* =>
				error(x, sys->sprint("unknown declaration: %s", s));
			}
		}
		error(x, "invalid XML declaration");
	} else
		error(x, sys->sprint("illegal beginning of tag: %c", c));
	return nil;
}

characters(x: ref Parser): ref Parcel
{
	p: ref Parcel;
	content := gets(x, '<');
	if (len content > 0) {
		if (content[len content - 1] == '<') {
			ungetc(x);
			content = content[0:len content - 1];
		}
		ws1, ws2: int;
		if (x.ispre) {
			content = substituteentities(x, content);
			ws1 = ws2 = 0;
		} else
			(content, ws1, ws2) = substituteentities_sp(x, content);
		if (content != nil || ws1)
			p = ref Parcel.Text(content, ws1, ws2);
	}
	return p;
}

startelement(x: ref Parser, name: string)
{
	x.estack = name :: x.estack;
	if (name == x.preelem)
		x.ispre++;
}

endelement(x: ref Parser, name: string)
{
	if (x.estack != nil && name == hd x.estack) {
		x.estack = tl x.estack;
		if (name == x.preelem)
			x.ispre--;
	} else {
		starttag := "";
		if (x.estack != nil)
			starttag = hd x.estack;
		warning(x, sys->sprint("<%s></%s> mismatch", starttag, name));

		# invalid XML but try to recover anyway to reduce turnaround time on fixing errors.
		# loop back up through the tag stack to see if there's a matching tag, in which case
		# jump up in the stack to that, making some rude assumptions about the
		# way Parcels are handled at the top level.
		n := 0;
		for (t := x.estack; t != nil; (t, n) = (tl t, n + 1))
			if (hd t == name)
				break;
		if (t != nil) {
			x.estack = tl t;
			x.actdepth -= n;
		}
	}
}

buildattrs(x: ref Parser): Attributes
{
	attrs: list of Attribute;

	attr: Attribute;
	for (;;) {
		skipwhite(x);
		attr.name = xmlname(x);
		if (attr.name == nil)
			break;
		skipwhite(x);
		c := getc(x);
		if(c != '='){
			ungetc(x);
			attr.value = nil;
		}else
			attr.value = xmlstring(x, 1);
		attrs = attr :: attrs;
	}
	return Attributes(attrs);
}

xmlstring(x: ref Parser, dosub: int): string
{
	skipwhite(x);
	s := "";
	delim := getc(x);
	if (delim == '\"' || delim == '\'') {
		s = gets(x, delim);
		n := len s;
		if (n == 0 || s[n-1] != delim)
			error(x, "unclosed string at end of file");
		s = s[0:n-1];	# TO DO: avoid copy
		if(dosub)
			s = substituteentities(x, s);
	} else
		error(x, sys->sprint("illegal string delimiter: %c", delim));
	return s;
}

xmlname(x: ref Parser): string
{
	name := "";
	ch := getc(x);
	case ch {
	'_' or ':' or
	'a' to 'z' or
	'A' to 'Z' or
	16r100 to 16rd7ff or
	16re000 or 16rfffd =>
		name[0] = ch;
loop:
		for (;;) {
			case ch = getc(x) {
			'_' or '-' or ':' or '.' or
			'a' to 'z' or
			'0' to '9' or
			'A' to 'Z' or
			16r100 to 16rd7ff or
			16re000 to 16rfffd =>
				name[len name] = ch;
			* =>
				break loop;
			}
		}
	}
	ungetc(x);
	return name;
}

substituteentities(x: ref Parser, buff: string): string
{
	i := 0;
	while (i < len buff) {
		if (buff[i] == '&') {
			(t, j) := translateentity(x, buff, i);
			# XXX could be quicker
			buff = buff[0:i] + t + buff[j:];
			i += len t;
		} else
			i++;
	}
	return buff;
}

# subsitute entities, squashing whitespace along the way.
substituteentities_sp(x: ref Parser, buf: string): (string, int, int)
{
	firstwhite := 0;
	# skip initial white space
	for (i := 0; i < len buf; i++) {
		c := buf[i];
		if (c != ' ' && c != '\t' && c != '\n' && c != '\r')
			break;
		firstwhite = 1;
	}

	lastwhite := 0;
	s := "";
	for (; i < len buf; i++) {
		c := buf[i];
		if (c == ' ' || c == '\t' || c == '\n' || c == '\r')
			lastwhite = 1;
		else {
			if (lastwhite) {
				s[len s] = ' ';
				lastwhite = 0;
			}
			if (c == '&') {
				# should &x20; count as whitespace?
				(ent, j) := translateentity(x, buf, i);
				i = j - 1;
				s += ent;
			} else
				s[len s] = c;
		}
	}
	return (s, firstwhite, lastwhite);
}

translateentity(x: ref Parser, s: string, i: int): (string, int)
{
	i++;
	for (j := i; j < len s; j++)
		if (s[j] == ';')
			break;
	ent := s[i:j];
	if (j == len s) {
		if (len ent > 10)
			ent = ent[0:11] + "...";
		warning(x, sys->sprint("missing ; at end of entity (&%s)", ent));
		return (nil, i);
	}
	j++;
	if (ent == nil) {
		warning(x, "empty entity");
		return ("", j);
	}
	if (ent[0] == '#') {
		n: int;
		rem := ent;
		if (len ent >= 3 && ent[1] == 'x')
			(n, rem) = str->toint(ent[2:], 16);
		else if (len ent >= 2)
			(n, rem) = str->toint(ent[1:], 10);
		if (rem != nil) {
			warning(x, sys->sprint("unrecognized entity (&%s)", ent));
			return (nil, j);
		}
		ch: string = nil;
		ch[0] = n;
		return (ch, j);
	}
	hv := entdict.find(ent);
	if (hv == nil) {
		warning(x, sys->sprint("unrecognized entity (&%s)", ent));
		return (nil, j);
	}
	return (hv.s, j);
}

balancedstring(x: ref Parser, eos: string): string
{
	s := "";
	instring := 0;
	quote: int;

	for (i := 0; i < len eos; i++)
		s[len s] = ' ';

	skipwhite(x);
	while ((c := getc(x)) != Bufio->EOF) {
		s[len s] = c;
		if (instring) {
			if (c == quote)
				instring = 0;
		} else if (c == '\"' || c == '\'') {
			quote = c;
			instring = 1;
		} else if (s[len s - len eos : len s] == eos)
			return s[len eos : len s - len eos];
	}
	error(x, sys->sprint("unexpected end of file while looking for \"%s\"", eos));
	return "";
}

skipwhite(x: ref Parser)
{
	while ((c := getc(x)) == ' ' || c == '\t' || c == '\n' || c == '\r')
		;
	ungetc(x);
}

expectwhite(x: ref Parser)
{
	if ((c := getc(x)) != ' ' && c != '\t' && c != '\n' && c != '\r')
		error(x, "expecting white space");
	skipwhite(x);
}

expect(x: ref Parser, ch: int)
{
	skipwhite(x);
	c := getc(x);
	if (c != ch)
		error(x, sys->sprint("expecting %c", ch));
}

getc(x: ref Parser): int
{
	if (x.eof)
		return Bufio->EOF;
	ch := x.in.getc();
	if (ch == Bufio->EOF)
		x.eof = 1;
	else if (ch == '\n')
		x.loc.line++;
	x.lastnl = ch == '\n';
	return ch;
}

gets(x: ref Parser, delim: int): string
{
	if (x.eof)
		return "";
	s := x.in.gets(delim);
	for (i := 0; i < len s; i++)
		if (s[i] == '\n')
			x.loc.line++;
	if (s == "")
		x.eof = 1;
	else
		x.lastnl = s[len s - 1] == '\n';
	return s;
}

ungetc(x: ref Parser)
{
	if (x.eof)
		return;
	x.in.ungetc();
	x.loc.line -= x.lastnl;
}

Attributes.all(al: self Attributes): list of Attribute
{
	return al.attrs;
}

Attributes.get(attrs: self Attributes, name: string): string
{
	for (a := attrs.attrs; a != nil; a = tl a)
		if ((hd a).name == name)
			return (hd a).value;
	return nil;
}

warning(x: ref Parser, msg: string)
{
	if (x.warning != nil)
		x.warning <-= (x.loc, msg);
}

error(x: ref Parser, msg: string)
{
	x.errormsg = msg;
	raise "sax:error";
}
