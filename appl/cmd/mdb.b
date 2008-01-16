implement Mdb;

include "sys.m";
	sys: Sys;
	stderr: ref Sys->FD;
	print, sprint: import sys;

include "draw.m";
include "string.m";
	str: String;
include "bufio.m";
	bufio: Bufio;
	Iobuf: import bufio;
include "dis.m";
	dis: Dis;
	Inst, Type, Data, Link, Mod: import dis;
	XMAGIC: import Dis;
	MUSTCOMPILE, DONTCOMPILE: import Dis;
	AMP, AFP, AIMM, AXXX, AIND, AMASK: import Dis;
	ARM, AXNON, AXIMM, AXINF, AXINM: import Dis;
	DEFB, DEFW, DEFS, DEFF, DEFA, DIND, DAPOP, DEFL: import Dis;
disfile: string;
m: ref Mod;

Mdb: module
{
	init: fn(nil: ref Draw->Context, argv: list of string);
};

mfd: ref Sys->FD;
dot := 0;
lastaddr := 0;
count := 1;

atoi(s: string): int
{
        b := 10;
        if(s == nil)
                return 0;
        if(s[0] == '0') {
                b = 8;
                s = s[1:];
                if(s == nil)
                        return 0;
                if(s[0] == 'x' || s[0] == 'X') {
                        b = 16;
                        s = s[1:];
                }
        }
        n: int;
        (n, nil) = str->toint(s, b);
        return n;
}

eatws(s: string): string
{
	for (i := 0; i < len s; i++)
		if (s[i] != ' ' && s[i] != '\t')
			return s[i:];
	return nil;
}

eatnum(s: string): string
{
	if(len s == 0)
		return s;
	while(gotnum(s) || gotalpha(s))
		s = s[1:];
	return s;
}

gotnum(s: string): int
{
	if(len s == 0)
		return 0;
	if(s[0] >= '0' && s[0] <= '9')
		return 1;
	else
		return 0;
}

gotalpha(s: string): int
{
	if(len s == 0)
		return 0;
	if((s[0] >= 'a' && s[0] <= 'z') || (s[0] >= 'A' && s[0] <= 'Z'))
		return 1;
	else
		return 0;
}

getexpr(s: string): (string, int, int)
{
	ov: int;
	v := 0;
	op := '+';
	for(;;) {
		ov = v;
		s = eatws(s);
		if(s == nil)
			return (nil, 0, 0);
		if(s[0] == '.' || s[0] == '+' || s[0] == '^') {
			v = dot;
			s = s[1:];
		} else if(s[0] == '"') {
			v = lastaddr;
			s = s[1:];
		} else if(s[0] == '(') {
			(s, v, nil) = getexpr(s[1:]);
			s = s[1:];
		} else if(gotnum(s)) {
			v = atoi(s);
			s = eatnum(s);
		} else
			return (s, 0, 0);
		case op {
		'+' => v = ov+v;
		'-' => v = ov-v;
		'*' => v = ov*v;
		'%' => v = ov/v;
		'&' => v = ov&v;
		'|' => v = ov|v;
		}
		if(s == nil)
			return (nil, v, 1);
		case s[0] {
		'+' or '-' or '*' or '%' or '&' or '|' =>
			op = s[0]; s = s[1:];
		* =>
			return (eatws(s), v, 1);
		}
	}
}

lastcmd := "";

docmd(s: string)
{
	ok: int;
	n: int;
	s = eatws(s);
	(s, n, ok) = getexpr(s);
	if(ok) {
		dot = n; 
		lastaddr = n;
	}
	count = 1;
	if(s != nil && s[0] == ',') {
		(s, n, ok) = getexpr(s[1:]);
		if(ok)
			count = n;
	}
	if(s == nil && (s = lastcmd) == nil) 
		return;
	lastcmd = s;
	cmd := s[0];
	case cmd {
	'?' or '/' =>
		case s[1] {
		'w' =>
			writemem(2, s[2:]);
		'W' =>
			writemem(4, s[2:]);
		'i' =>
			das();
		* =>
			dumpmem(s[1:], cmd);
		}
	'$' =>
		case s[1] {
		'D' =>
			desc();
		'h' =>
			hdr();
		'l' =>
			link();
		'i' =>
			imports();
		'd' =>
			dat();
		'H' =>
			handlers();
		's' =>
			if(m != nil)
				print("%s\n", m.srcpath);
		}
	'=' =>
		dumpmem(s[1:], cmd);
	* =>
		sys->fprint(stderr, "invalid cmd: %c\n", cmd);
	}
}

octal(n: int, d: int): string
{
	s: string;
	do {
		s = string (n%8) + s;
		n /= 8;
	} while(d-- > 1);
	return "0" + s;
}

printable(c: int): string
{
	case c {
	32 to 126 =>
		return sprint("%c", c);
	'\n' =>
		return "\\n";
	'\r' =>
		return "\\r";
	'\b' =>
		return "\\b";
	'\a' =>
		return "\\a";
	'\v' =>
		return "\\v";
	* =>
		return sprint("\\x%2.2x", c);
	}
		
}

dumpmem(s: string, t: int)
{
	n := 0;
	c := count;
	while(c-- > 0) for(p:=0; p<len s; p++) {
		fmt := s[p];
		case fmt {
		'b' or 'c' or 'C' =>
			n = 1;
		'x' or 'd' or 'u' or 'o' =>
			n = 2; 
		'X' or 'D' or 'U' or 'O' =>
			n = 4;
		's' or 'S' or 'r' or 'R' =>
			print("'%c' format not yet supported\n", fmt);
			continue;
		'n' =>
			print("\n");
			continue;
		'+' =>
			dot++;
			continue;
		'-' =>
			dot--;
			continue;
		'^' =>
			dot -= n;
			continue;
		* =>
			print("unknown format '%c'\n", fmt);
			continue;
		}
		b := array[n] of byte;
		v: int;
		if(t == '=')
			v = dot;
		else {
			sys->seek(mfd, big dot, Sys->SEEKSTART);
			sys->read(mfd, b, len b);
			v = 0;
			for(i := 0; i < n; i++)
				v |= int b[i] << (8*i);
		}
		case fmt {
		'c' => print("%c", v);
		'C' => print("%s", printable(v));
		'b' => print("%#2.2ux ", v);
		'x' => print("%#4.4ux ", v);
		'X' => print("%#8.8ux ", v);
		'd' => print("%-4d ", v);
		'D' => print("%-8d ", v);
		'u' => print("%-4ud ", v);
		'U' => print("%-8ud ", v);
		'o' => print("%s ", octal(v, 6));
		'O' => print("%s ", octal(v, 11));
		}
		if(t != '=')
			dot += n;
	}
	print("\n");
}

writemem(n: int, s: string)
{
	v: int;
	ok: int;
	s = eatws(s);
	sys->seek(mfd, big dot, Sys->SEEKSTART);
	for(;;) {
		(s, v, ok) = getexpr(s);
		if(!ok)
			return;
		b := array[n] of byte;
		for(i := 0; i < n; i++)
			b[i] = byte (v >> (8*i));
		if (sys->write(mfd, b, len b) != len b)
			sys->fprint(stderr, "mdb: write error: %r\n");
	}
}

usage()
{
	sys->fprint(stderr, "usage: mdb [-w] file [command]\n");
	raise "fail:usage";
}

writeable := 0;

init(nil: ref Draw->Context, argv: list of string)
{
	sys = load Sys Sys->PATH;
	stderr = sys->fildes(2);
	str = load String String->PATH;
	if (str == nil) {
		sys->fprint(stderr, "mdb: cannot load %s: %r\n", String->PATH);
		raise "fail:bad module";
	}
	bufio = load Bufio Bufio->PATH;
	if (bufio == nil) {
		sys->fprint(stderr, "mdb: cannot load %s: %r\n", Bufio->PATH);
		raise "fail:bad module";
	}
	dis = load Dis Dis->PATH;
	dis->init();

	if (len argv < 2)
		usage();
	if (argv != nil)
		argv = tl argv;
	if (argv != nil && len hd argv && (hd argv)[0] == '-') {
		if (hd argv != "-w")
			usage();
		writeable = 1;
		argv = tl argv;
	}
	if (argv == nil)
		usage();
	fname := hd argv;
	argv = tl argv;
	cmd := "";
	if(argv != nil)
		cmd = hd argv;

	oflags := Sys->OREAD;
	if (writeable)
		oflags = Sys->ORDWR;
	mfd = sys->open(fname, oflags);
	if(mfd == nil) {
		sys->fprint(stderr, "mdb: cannot open %s: %r\n", fname);
		raise "fail:cannot open";
	}
	(m, nil) = dis->loadobj(fname);

	if(cmd != nil)
		docmd(cmd);
	else {
		stdin := bufio->fopen(sys->fildes(0), Sys->OREAD);
		while ((s := stdin.gets('\n')) != nil) {
			if (s[len s -1] == '\n')
				s = s[0:len s - 1];
			docmd(s);
		}
	}
}

link()
{
	if(m == nil || m.magic == 0)
		return;

	for(i := 0; i < m.lsize; i++) {
		l := m.links[i];
		print("	link %d,%d, 0x%ux, \"%s\"\n",
					l.desc, l.pc, l.sig, l.name);
	}
}

imports()
{
	if(m == nil || m.magic == 0)
		return;

	mi := m.imports;
	for(i := 0; i < len mi; i++) {
		a := mi[i];
		for(j := 0; j < len a; j++) {
			ai := a[j];
			print("	import 0x%ux, \"%s\"\n", ai.sig, ai.name);
		}
	}
}

handlers()
{
	if(m == nil || m.magic == 0)
		return;

	hs := m.handlers;
	for(i := 0; i < len hs; i++) {
		h := hs[i];
		tt := -1;
		for(j := 0; j < len m.types; j++) {
			if(h.t == m.types[j]) {
				tt = j;
				break;
			}
		}
		print("	%d-%d, o=%d, e=%d t=%d\n", h.pc1, h.pc2, h.eoff, h.ne, tt);
		et := h.etab;
		for(j = 0; j < len et; j++) {
			e := et[j];
			if(e.s == nil)
				print("		%d	*\n", e.pc);
			else
				print("		%d	\"%s\"\n", e.pc, e.s);
		}
	}
}

desc()
{
	if(m == nil || m.magic == 0)
		return;

	for(i := 0; i < m.tsize; i++) {
		h := m.types[i];
		s := sprint("	desc $%d, %d, \"", i, h.size);
		for(j := 0; j < h.np; j++)
			s += sprint("%.2ux", int h.map[j]);
		s += "\"\n";
		print("%s", s);
	}
}

hdr()
{
	if(m == nil || m.magic == 0)
		return;
	s := sprint("%.8ux Version %d Dis VM\n", m.magic, m.magic - XMAGIC + 1);
	s += sprint("%.8ux Runtime flags %s\n", m.rt, rtflag(m.rt));
	s += sprint("%8d bytes per stack extent\n\n", m.ssize);


	s += sprint("%8d instructions\n", m.isize);
	s += sprint("%8d data size\n", m.dsize);
	s += sprint("%8d heap type descriptors\n", m.tsize);
	s += sprint("%8d link directives\n", m.lsize);
	s += sprint("%8d entry pc\n", m.entry);
	s += sprint("%8d entry type descriptor\n\n", m.entryt);

	if(m.sign == nil)
		s += "Module is Insecure\n";
	print("%s", s);
}

rtflag(flag: int): string
{
	if(flag == 0)
		return "";

	s := "[";

	if(flag & MUSTCOMPILE)
		s += "MustCompile";
	if(flag & DONTCOMPILE) {
		if(flag & MUSTCOMPILE)
			s += "|";
		s += "DontCompile";
	}
	s[len s] = ']';

	return s;
}

das()
{
	if(m == nil || m.magic == 0)
		return;

	for(i := dot;  count-- > 0 && i < m.isize; i++) {
		if(i % 10 == 0)
			print("#%d\n", i);
		print("\t%s\n", dis->inst2s(m.inst[i]));
	}
}

dat()
{
	if(m == nil || m.magic == 0)
		return;
	print("	var @mp, %d\n", m.types[0].size);

	s := "";
	for(d := m.data; d != nil; d = tl d) {
		pick dat := hd d {
		Bytes =>
			s = sprint("\tbyte @mp+%d", dat.off);
			for(n := 0; n < dat.n; n++)
				s += sprint(",%d", int dat.bytes[n]);
		Words =>
			s = sprint("\tword @mp+%d", dat.off);
			for(n := 0; n < dat.n; n++)
				s += sprint(",%d", dat.words[n]);
		String =>
			s = sprint("\tstring @mp+%d, \"%s\"", dat.off, mapstr(dat.str));
		Reals =>
			s = sprint("\treal @mp+%d", dat.off);
			for(n := 0; n < dat.n; n++)
				s += sprint(", %g", dat.reals[n]);
			break;
		Array =>
			s = sprint("\tarray @mp+%d,$%d,%d", dat.off, dat.typex, dat.length);
		Aindex =>
			s = sprint("\tindir @mp+%d,%d", dat.off, dat.index);
		Arestore =>
			s = "\tapop";
			break;
		Bigs =>
			s = sprint("\tlong @mp+%d", dat.off);
			for(n := 0; n < dat.n; n++)
				s += sprint(", %bd", dat.bigs[n]);
		}
		print("%s\n", s);
	}
}

mapstr(s: string): string
{
	for(i := 0; i < len s; i++)
		if(s[i] == '\n')
			s = s[0:i] + "\\n" + s[i+1:];
	return s;
}
