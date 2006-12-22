implement Archives;
include "sys.m";
	sys: Sys;
include "draw.m";
include "bufio.m";
	bufio: Bufio;
	Iobuf: import bufio;
include "sets.m";
	sets: Sets;
	Set, set, A, B, All, None: import sets;
include "string.m";
	str: String;
include "spree.m";
	spree: Spree;
	Clique, Member, Attributes, Attribute, Object: import spree;
	MAXPLAYERS: import Spree;

stderr: ref Sys->FD;

Qc: con " \t{}=\n";
Saveinfo: adt {
	clique: ref Clique;
	idmap: array of int;		# map clique id to archive id
	memberids:	Set;			# set of member ids to archive
};

Error: exception(string);

Cliqueparse: adt {
	iob:		ref Iobuf;
	line:		int;
	filename:	string;
	lasttok:	int;
	errstr:	string;

	gettok:	fn(gp: self ref Cliqueparse): (int, string) raises (Error);
	lgettok:	fn(gp: self ref Cliqueparse, t: int): string raises (Error);
	getline:	fn(gp: self ref Cliqueparse): list of string raises (Error);
	error:	fn(gp: self ref Cliqueparse, e: string) raises (Error);
};

WORD: con 16rff;

init(cliquemod: Spree)
{
	sys = load Sys Sys->PATH;
	stderr = sys->fildes(2);
	bufio = load Bufio Bufio->PATH;
	if (bufio == nil) {
		sys->fprint(stderr, "cliquearchive: cannot load %s: %r\n", Bufio->PATH);
		raise "fail:bad module";
	}
	sets = load Sets Sets->PATH;
	if (sets == nil) {
		sys->fprint(stderr, "cliquearchive: cannot load %s: %r\n", Sets->PATH);
		raise "fail:bad module";
	}
	str = load String String->PATH;
	if (str == nil) {
		sys->fprint(stderr, "cliquearchive: cannot load %s: %r\n", String->PATH);
		raise "fail:bad module";
	}
	sets->init();
	spree = cliquemod;
}

write(clique: ref Clique, info: list of (string, string), name: string, memberids: Sets->Set): string
{
	sys->print("saveclique, saving %d objects\n", objcount(clique.objects[0]));
	iob := bufio->create(name, Sys->OWRITE, 8r666);
	if (iob == nil)
		return sys->sprint("cannot open %s: %r", name);

	# integrate suspended members with current members
	# for the archive.

	si := ref Saveinfo(clique, array[memberids.limit()] of int, memberids);
	members := clique.members();
	pa := array[len members] of (string, int);
	for (i := 0; members != nil; members = tl members) {
		p := hd members;
		if (memberids.holds(p.id))
			pa[i++] = (p.name, p.id);
	}
	pa = pa[0:i];
	sortmembers(pa);		# ensure members stay in the same order when rearchived.
	pl: list of string;
	for (i = len pa - 1; i >= 0; i--) {
		si.idmap[pa[i].t1] = i;
		pl = pa[i].t0 :: pl;
	}
	iob.puts(quotedc("session" :: clique.archive.argv, Qc));
	iob.putc('\n');
	iob.puts(quotedc("members" :: pl, Qc));
	iob.putc('\n');
	il: list of string;
	for (; info != nil; info = tl info)
		il = (hd info).t0 :: (hd info).t1 :: il;
	iob.puts(quotedc("info" :: il, Qc));
	iob.putc('\n');
	writeobject(iob, 0, si, clique.objects[0]);
	iob.close();
	return nil;
}

writeobject(iob: ref Iobuf, depth: int, si: ref Saveinfo, obj: ref Object)
{
	indent(iob, depth);
	iob.puts(quotedc(obj.objtype :: nil, Qc));
	iob.putc(' ');
	iob.puts(mapset(si, obj.visibility).str());
	writeattrs(iob, si, obj);
	if (len obj.children > 0) {
		iob.puts(" {\n");
		for (i := 0; i < len obj.children; i++)
			writeobject(iob, depth + 1, si, obj.children[i]);
		indent(iob, depth);
		iob.puts("}\n");
	} else
		iob.putc('\n');
}

writeattrs(iob: ref Iobuf, si: ref Saveinfo, obj: ref Object)
{
	a := obj.attrs.a;
	n := 0;
	for (i := 0; i < len a; i++)
		n += len a[i];
	attrs := array[n] of ref Attribute;
	j := 0;
	for (i = 0; i < len a; i++)
		for (l := a[i]; l != nil; l = tl l)
			attrs[j++] = hd l;
	sortattrs(attrs);
	for (i = 0; i < len attrs; i++) {
		attr := attrs[i];
		if (attr.val == nil)
			continue;
		iob.putc(' ');
		iob.puts(quotedc(attr.name :: nil, Qc));
		vis := mapset(si, attr.visibility);
		if (!vis.eq(All))
			iob.puts("{" + vis.str() + "}");
		iob.putc('=');
		iob.puts(quotedc(attr.val :: nil, Qc));
	}
}

mapset(si: ref Saveinfo, s: Set): Set
{
	idmap := si.idmap;
	m := s.msb() != 0;
	limit := si.memberids.limit();
	r := None;
	for (i := 0; i < limit; i++)
		if (m == !s.holds(i))
			r = r.add(idmap[i]);
	if (m)
		r = All.X(A&~B, r);
	return r;
}

readheader(filename: string): (ref Archive, string)
{
	iob := bufio->open(filename, Sys->OREAD);
	if (iob == nil)
		return (nil, sys->sprint("cannot open '%s': %r", filename));
	gp := ref Cliqueparse(iob, 1, filename, Bufio->EOF, nil);

	{
		line := gp.getline();
		if (len line < 2 || hd line != "session")
			gp.error("expected 'session' line, got " + str->quoted(line));
		argv := tl line;
		line = gp.getline();
		if (line == nil || tl line == nil || hd line != "members")
			gp.error("expected 'members' line");
		members := l2a(tl line);
		line = gp.getline();
		if (line == nil || hd line != "info")
			gp.error("expected 'info' line");
		if (len tl line % 2 != 0)
			gp.error("'info' line must have an even number of fields");
		info: list of (string, string);
		for (line = tl line; line != nil; line = tl tl line)
			info = (hd line, hd tl line) :: info;
		arch := ref Archive(argv, members, info, nil);
		iob.close();
		return (arch, nil);
	} exception e {
	Error =>
		return (nil, x := e);
	}
}

read(filename: string): (ref Archive, string)
{
	iob := bufio->open(filename, Sys->OREAD);
	if (iob == nil)
		return (nil, sys->sprint("cannot open '%s': %r", filename));
	gp := ref Cliqueparse(iob, 1, filename, Bufio->EOF, nil);

	{
		line := gp.getline();
		if (len line < 2 || hd line != "session")
			gp.error("expected 'session' line, got " + str->quoted(line));
		argv := tl line;
		line = gp.getline();
		if (line == nil || tl line == nil || hd line != "members")
			gp.error("expected 'members' line");
		members := l2a(tl line);
		line = gp.getline();
		if (line == nil || hd line != "info")
			gp.error("expected 'info' line");
		if (len tl line % 2 != 0)
			gp.error("'info' line must have an even number of fields");
		info: list of (string, string);
		for (line = tl line; line != nil; line = tl tl line)
			info = (hd line, hd tl line) :: info;
		root := readobject(gp);
		if (root == nil)
			return (nil, filename + ": no root object found");
		n := objcount(root);
		arch := ref Archive(argv, members, info, array[n] of ref Object);
		arch.objects[0] = root;
		root.parentid = -1;
		root.id = 0;
		allocobjects(root, arch.objects, 1);
		iob.close();
		return (arch, nil);
	} exception e {
	Error =>
		return (nil, x := e);
	}
}

allocobjects(parent: ref Object, objects: array of ref Object, n: int): int
{
	base := n;
	children := parent.children;
	objects[n:] = children;
	n += len children;
	for (i := 0; i < len children; i++) {
		child := children[i];
		(child.id, child.parentid) = (base + i, parent.id);
		n = allocobjects(child, objects, n);
	}
	return n;
}

objcount(o: ref Object): int
{
	n := 1;
	a := o.children;
	for (i := 0; i < len a; i++)
		n += objcount(a[i]);
	return n;
}

readobject(gp: ref Cliqueparse): ref Object raises (Error)
{
	{
		# object format:
		# objtype visibility [attr[{vis}]=val]... [{\nchildren\n}]\n
		(t, s) := gp.gettok();			#{
		if (t == Bufio->EOF || t == '}')
			return nil;
		if (t != WORD)
			gp.error("expected WORD");
		objtype := s;
		vis := sets->str2set(gp.lgettok(WORD));
		attrs := Attributes.new();
		objs: array of ref Object;
	loop:	for (;;) {
			(t, s) = gp.gettok();
			case t {
			WORD =>
				attr := s;
				attrvis := All;
				(t, s) = gp.gettok();
				if (t == '{') {		#}
					attrvis = sets->str2set(gp.lgettok(WORD));	#{
					gp.lgettok('}');
					gp.lgettok('=');
				} else if (t != '=')
					gp.error("expected '='");
				val := gp.lgettok(WORD);
				attrs.set(attr, val, attrvis);
			'{' =>		#}
				gp.lgettok('\n');
				objl: list of ref Object;
				while ((obj := readobject(gp)) != nil)
					objl = obj :: objl;
				n := len objl;
				objs = array[n] of ref Object;
				for (n--; n >= 0; n--)
					(objs[n], objl) = (hd objl, tl objl);
				gp.lgettok('\n');
				break loop;
			'\n' =>
				break loop;
			* =>
				gp.error("expected WORD or '{'");	#}
			}
		}
		return ref Object(-1, attrs, vis, -1, objs, -1, objtype);
	} exception e {Error => raise e;}
}

Cliqueparse.error(gp: self ref Cliqueparse, e: string) raises (Error)
{
	raise Error(sys->sprint("%s:%d: parse error after %s: %s", gp.filename, gp.line,
			tok2str(gp.lasttok), e));
}

Cliqueparse.getline(gp: self ref Cliqueparse): list of string raises (Error)
{
	{
		line, nline: list of string;
		for (;;) {
			(t, s) := gp.gettok();
			if (t == '\n')
				break;
			if (t != WORD)
				gp.error("expected a WORD");
			line = s :: line;
		}
		for (; line != nil; line = tl line)
			nline = hd line :: nline;
		return nline;
	} exception e {Error => raise e;}
}

# get a token, which must be of type t.
Cliqueparse.lgettok(gp: self ref Cliqueparse, mustbe: int): string raises (Error)
{
	{
		(t, s) := gp.gettok();
		if (t != mustbe)
			gp.error("lgettok expected " + tok2str(mustbe));
		return s;
	} exception e {Error => raise e;}

}

Cliqueparse.gettok(gp: self ref Cliqueparse): (int, string) raises (Error)
{
	{
		iob := gp.iob;
		while ((c := iob.getc()) == ' ' || c == '\t')
			;
		t: int;
		s: string;
		case c {
		Bufio->EOF or
		Bufio->ERROR =>
			t = Bufio->EOF;
		'\n' =>
			gp.line++;
			t = '\n';
		'{' =>
			t = '{';
		'}' =>
			t = '}';
		'=' =>
			t = '=';
		'\'' =>
			for(;;) {
				while ((nc := iob.getc()) != '\'' && nc >= 0) {
					s[len s] = nc;
					if (nc == '\n')
						gp.line++;
				}
				if (nc == Bufio->EOF || nc == Bufio->ERROR)
					gp.error("unterminated quote");
				if (iob.getc() != '\'') {
					iob.ungetc();
					break;
				}
				s[len s] = '\'';	# 'xxx''yyy' becomes WORD(xxx'yyy)
			}
			t = WORD;
		* =>
			do {
				s[len s] = c;
				c = iob.getc();
				if (in(c, Qc)) {
					iob.ungetc();
					break;
				}
			} while (c >= 0);
			t = WORD;
		}
		gp.lasttok = t;
		return (t, s);
	} exception e {Error => raise e;}
}

tok2str(t: int): string
{
	case t {
	Bufio->EOF =>
		return "EOF";
	WORD =>
		return "WORD";
	'\n' =>
		return "'\\n'";
	* =>
		return sys->sprint("'%c'", t);
	}
}

# stolen from lib/string.b - should be part of interface in string.m
quotedc(argv: list of string, cl: string): string
{
	s := "";
	while (argv != nil) {
		arg := hd argv;
		for (i := 0; i < len arg; i++) {
			c := arg[i];
			if (c == ' ' || c == '\t' || c == '\n' || c == '\'' || in(c, cl))
				break;
		}
		if (i < len arg || arg == nil) {
			s += "'" + arg[0:i];
			for (; i < len arg; i++) {
				if (arg[i] == '\'')
					s[len s] = '\'';
				s[len s] = arg[i];
			}
			s[len s] = '\'';
		} else
			s += arg;
		if (tl argv != nil)
			s[len s] = ' ';
		argv = tl argv;
	}
	return s;
}

in(c: int, cl: string): int
{
	n := len cl;
	for (i := 0; i < n; i++)
		if (cl[i] == c)
			return 1;
	return 0;
}

indent(iob: ref Iobuf, depth: int)
{
	for (i := 0; i < depth; i++)
		iob.putc('\t');
}

sortmembers(p: array of (string, int))
{
	membermergesort(p, array[len p] of (string, int));
}

membermergesort(a, b: array of (string, int))
{
	r := len a;
	if (r > 1) {
		m := (r-1)/2 + 1;
		membermergesort(a[0:m], b[0:m]);
		membermergesort(a[m:], b[m:]);
		b[0:] = a;
		for ((i, j, k) := (0, m, 0); i < m && j < r; k++) {
			if (b[i].t1 > b[j].t1)
				a[k] = b[j++];
			else
				a[k] = b[i++];
		}
		if (i < m)
			a[k:] = b[i:m];
		else if (j < r)
			a[k:] = b[j:r];
	}
}

sortattrs(a: array of ref Attribute)
{
	attrmergesort(a, array[len a] of ref Attribute);
}

attrmergesort(a, b: array of ref Attribute)
{
	r := len a;
	if (r > 1) {
		m := (r-1)/2 + 1;
		attrmergesort(a[0:m], b[0:m]);
		attrmergesort(a[m:], b[m:]);
		b[0:] = a;
		for ((i, j, k) := (0, m, 0); i < m && j < r; k++) {
			if (b[i].name > b[j].name)
				a[k] = b[j++];
			else
				a[k] = b[i++];
		}
		if (i < m)
			a[k:] = b[i:m];
		else if (j < r)
			a[k:] = b[j:r];
	}
}

l2a(l: list of string): array of string
{
	n := len l;
	a := array[n] of string;
	for (i := 0; i < n; i++)
		(a[i], l) = (hd l, tl l);
	return a;
}