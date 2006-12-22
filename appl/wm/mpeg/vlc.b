implement Vlc;

include "sys.m";
include "draw.m";
include "bufio.m";

#
#	Construct expanded Vlc (variable length code) tables
#	from vlc description files.
#

sys: Sys;
bufio: Bufio;
Iobuf: import bufio;

stderr: ref Sys->FD;

sv: adt
{
	s:	int;
	v:	string;
};

s2list: type list of (string, string);
bits, size: int;
table: array of sv;
prog: string;
undef: string = "UNDEF";
xfixed: int = 0;
complete: int = 0;
paren: int = 0;

Vlc: module
{
	init:	fn(nil: ref Draw->Context, args: list of string);
};

init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	stderr = sys->fildes(2);
	sargs := makestr(args);
	prog = hd args;
	args = tl args;
	bufio = load Bufio Bufio->PATH;
	if (bufio == nil) {
		sys->fprint(stderr, "%s: could not load %s: %r\n", prog, Bufio->PATH);
		return;
	}
	inf := bufio->fopen(sys->fildes(0), Bufio->OREAD);
	if (inf == nil) {
		sys->fprint(stderr, "%s: fopen stdin failed: %r\n", prog);
		return;
	}
	while (args != nil && len hd args && (a := hd args)[0] == '-') {
	flag:
		for (x := 1; x < len a; x++) {
			case a[x] {
			'c' =>
				complete = 1;
			'f' =>
				xfixed = 1;
			'p' =>
				paren = 1;
			'u' =>
				if (++x == len a) {
					args = tl args;
					if (args == nil)
						usage();
					undef = hd args;
				} else
					undef = a[x:];
				break flag;
			* =>
				usage();
				return;
			}
		}
		args = tl args;
	}
	vlc := "vlc";
	if (args != nil) {
		if (tl args != nil) {
			usage();
			return;
		}
		vlc = hd args;
	}
	il: s2list;
	while ((l := inf.gets('\n')) != nil) {
		if (l[0] == '#')
			continue;
		(n, t) := sys->tokenize(l, " \t\n");
		if (n != 2) {
			sys->fprint(stderr, "%s: bad input: %s", prog, l);
			return;
		}
		il = (hd t, hd tl t) :: il;
	}
	(n, nl) := expand(il);
	bits = n;
	size = 1 << bits;
	table = array[size] of sv;
	maketable(nl);
	printtable(vlc, sargs);
}

usage()
{
	sys->fprint(stderr, "usage: %s [-cfp] [-u undef] [stem]\n", prog);
}

makestr(l: list of string): string
{
	s, t: string;
	while (l != nil) {
		s = s + t + hd l;
		t = " ";
		l = tl l;
	}
	return s;
}

expand(l: s2list): (int, s2list)
{
	nl: s2list;
	max := 0;
	while (l != nil) {
		(bs, val) := hd l;
		n := len bs;
		if (n > max)
			max = n;
		if (bs[n - 1] == 's') {
			t := bs[:n - 1];
			nl = (t + "0", val) :: (t + "1", "-" + val) :: nl;
		} else
			nl = (bs, val) :: nl;
		l = tl l;
	}
	return (max, nl);
}

maketable(l: s2list)
{
	while (l != nil) {
		(bs, val) := hd l;
		z := len bs;
		if (xfixed && z != bits)
			error(sys->sprint("string %s too short", bs));
		s := bits - z;
		v := value(bs) << s;
		n := 1 << s;
		for (i := 0; i < n; i++) {
			if (table[v].v != nil)
				error(sys->sprint("repeat match for %x", v));
			table[v] = (z, val);
			v++;
		}
		l = tl l;
	}
}

value(s: string): int
{
	n := len s;
	v := 0;
	for (i := 0; i < n; i++) {
		case s[i] {
		'0' =>
			v <<= 1;
		'1'=>
			v = (v << 1) | 1;
		* =>
			error("bad bitstream: " + s);
		}
	}
	return v;
}

printtable(s, a: string)
{
	sys->print("# %s\n", a);
	sys->print("%s_size: con %d;\n", s, size);
	sys->print("%s_bits: con %d;\n", s, bits);
	sys->print("%s_table:= array[] of {\n", s);
	for (i := 0; i < size; i++) {
		if (table[i].v != nil) {
			if (xfixed) {
				if (paren)
					sys->print("\t(%s),\n", table[i].v);
				else
					sys->print("\t%s,\n", table[i].v);
			} else
				sys->print("\t(%d, %s),\n", table[i].s, table[i].v);
		} else if (!complete) {
			if (xfixed) {
				if (paren)
					sys->print("\t(%s),\n", undef);
				else
					sys->print("\t%s,\n", undef);
			} else
				sys->print("\t(0, %s),\n", undef);
		} else
			error(sys->sprint("no match for %x", i));
	}
	sys->print("};\n");
}

error(s: string)
{
	sys->fprint(stderr, "%s: error: %s\n", prog, s);
	exit;
}
