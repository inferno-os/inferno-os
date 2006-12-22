implement Sed;

#
# partial sed implementation borrowed from plan9 sed.
#

include "sys.m";
	sys: Sys;
include "draw.m";
include "arg.m";
	arg: Arg;
include "bufio.m";
	bufio: Bufio;
	Iobuf: import bufio;
include "string.m";
	str: String;
include "regex.m";
	regex: Regex;
	Re: import regex;

Sed : module {
	init: fn(ctxt: ref Draw->Context, argv: list of string);
};


false, true: con iota;
bool: type int;

Addr: adt {
	pick {
		None =>
		Dollar =>
		Line =>
			line: int;
		Regex =>
			re: Re;
	}
};

Sedcom: adt {
	command: fn(c: self ref Sedcom);
	executable: fn(c: self ref Sedcom) : int;

	ad1, ad2: ref Addr;
	negfl: bool;
	active: int;

	pick {
	S =>
		gfl, pfl: int;
		re: Re;
		b: ref Iobuf;
		rhs: string;
	D or CD or P or Q or EQ or G or CG or H or CH or N or CN or X or CP or L=>
	A or C or I =>
		text: string;
	R =>
		filename: string;
	W =>
		b: ref Iobuf;
	Y =>
		map: list of (int, int);
	B or T or Lab =>
		lab: string;
	}
};

dflag := false;
nflag := false;
gflag := false;
sflag := 0;

delflag := 0;
dolflag := 0;
fhead := 0;
files: list of string;
fout: ref Iobuf;
infile: ref Iobuf;
jflag := 0;
lastregex:  Re;
linebuf: string;
filename := "";
lnum := 0;
peekc := 0;

holdsp := "";
patsp := "";

cmds: list of ref Sedcom;
appendlist: list of ref Sedcom;
bufioflush: list of ref Iobuf;

init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;

	if ((arg = load Arg Arg->PATH) == nil)
		fatal(sys->sprint("could not load %s: %r", Arg->PATH));

	if ((bufio = load Bufio Bufio->PATH) == nil)
		fatal(sys->sprint("could not load %s: %r", Bufio->PATH));

	if ((str = load String String->PATH) == nil)
		fatal(sys->sprint("could not load %s: %r", String->PATH));

	if ((regex = load Regex Regex->PATH) == nil)
		fatal(sys->sprint("could not load %s: %r", Regex->PATH));

	arg->init(args);

	compfl := 0;
	while ((c := arg->opt()) != 0)
		case c {
		'n' =>
			nflag = true;
		'g' =>
			gflag = true;
		'e' =>
			if ((s := arg->arg()) == nil)
				usage();
			filename = "";
			cmds = compile(bufio->sopen(s + "\n"), cmds);
			compfl = 1;
		'f' => if ((filename = arg->arg()) == nil)
				usage();
			b := bufio->open(filename, bufio->OREAD);
			if (b == nil)
				fatal(sys->sprint("couldn't open '%s': %r", filename));
			cmds = compile(b, cmds);
			compfl = 1;
		'd' =>
			dflag = true;
		* =>
			usage();
		}
	args = arg->argv();
	if (compfl == 0) {
		if (len args == 0)
			fatal("missing pattern");
		filename = "";
		cmds = compile(bufio->sopen(hd args + "\n"), cmds);
		args = tl args;
	}

	# reverse command list, we could compile addresses here if required
	l: list of ref Sedcom;
	for (p := cmds; p != nil; p = tl p) {
		l = hd p :: l;
	}
	cmds = l;

	# add files to file list (and reverse to get in right order)
	f: list of string;
	if (len args == 0)
		f = "" :: f;
	else for (; len args != 0; args = tl args)
		f = hd args :: f;
	for (;f != nil; f = tl f)
		files = hd f :: files;

	if ((fout = bufio->fopen(sys->fildes(1), bufio->OWRITE)) == nil)
		fatal(sys->sprint("couldn't buffer stdout: %r"));
	bufioflush = fout :: bufioflush;
	lnum = 0;
	execute(cmds);
	exits(nil);
}

depth := 0;
maxdepth: con 20;
cmdend := array [maxdepth] of string;
cmdcnt := array [maxdepth] of int;

compile(b: ref Iobuf, l: list of ref Sedcom) : list of ref Sedcom
{
	lnum = 1;

nextline:
	for (;;) {
		err: int;
		(err, linebuf) = getline(b);
		if (err < 0)
			break;
		
		s := linebuf;

		do {
			rep: ref Sedcom;
			ad1, ad2: ref Addr;
			negfl := 0;

			if (s != "")
				s = str->drop(s, " \t;");

			if (s == "" || s[0] == '#')
				continue nextline;

			# read addresses
			(s, ad1) = address(s);
			pick a := ad1 {
			None =>
				ad2 = ref Addr.None();
			* =>
				if (s != "" && (s[0] == ',' || s[0] == ';')) {
					(s, ad2) = address(s[1:]);
				}
				else {
					ad2 = ref Addr.None();
				}
			}

			s = str->drop(s, " \t");

			if (s != "" && str->in(s[0], "!")) {
				negfl = true;
				s = str->drop(s, "!");
			}
			s = str->drop(s, " \t");
			if (s == "")
				break;
			c := s[0]; s = s[1:];

			# mop up commands that got two addresses but only want one.
			case c {
				'a' or 'c' or 'q' or '=' or 'i' =>
					if (tagof ad2 != tagof Addr.None)
						fatal(sys->sprint("only one address allowed:  '%s'",
						      linebuf));
			}

			case c {
			* =>
				fatal(sys->sprint("unrecognised command: '%s' (%c)",
					linebuf, c));
			'a' =>
				if (s != "" && s[0] == '\\')
					s = s[1:];
				if (s == "" || s[0] != '\n')
					fatal("unexpected characters in a command: " + s);
				rep = ref Sedcom.A (ad1, ad2, negfl, 0, s[1:]);
				s = "";
			'c' =>
				if (s != "" && s[0] == '\\')
					s = s[1:];
				if (s == "" || s[0] != '\n')
					fatal("unexpected characters in c command: " + s);
				rep = ref Sedcom.C (ad1, ad2, negfl, 0, s[1:]);
				s = "";
			'i' =>
				if (s != "" && s[0] == '\\')
					s = s[1:];
				if (s == "" || s[0] != '\n')
					fatal("unexpected characters in i command: " + s);
				rep = ref Sedcom.I (ad1, ad2, negfl, 0, s[1:]);
				s = "";
			'r' =>
				s = str->drop(s, " \t");
				rep = ref Sedcom.R (ad1, ad2, negfl, 0, s);
				s = "";
			'w' =>
				if (s != "")
					s = str->drop(s, " \t");
				if (s == "")
					fatal("no filename in w command: " + linebuf);
				bo := bufio->open(s, bufio->OWRITE);
				if (bo == nil)
					bo = bufio->create(s, bufio->OWRITE, 8r666);
				if (bo == nil)
					fatal(sys->sprint("can't create output file: '%s'", s));
				bufioflush = bo :: bufioflush;
				rep = ref Sedcom.W (ad1, ad2, negfl, 0, bo);
				s = "";
				
			'd' =>
				rep = ref Sedcom.D (ad1, ad2, negfl, 0);
			'D' =>
				rep = ref Sedcom.CD (ad1, ad2, negfl, 0);
			'p' =>
				rep = ref Sedcom.P (ad1, ad2, negfl, 0);
			'P' =>
				rep = ref Sedcom.CP (ad1, ad2, negfl, 0);
			'q' =>
				rep = ref Sedcom.Q (ad1, ad2, negfl, 0);
			'=' =>
				rep = ref Sedcom.EQ (ad1, ad2, negfl, 0);
			'g' =>
				rep = ref Sedcom.G (ad1, ad2, negfl, 0);
			'G' =>
				rep = ref Sedcom.CG (ad1, ad2, negfl, 0);
			'h' =>
				rep = ref Sedcom.H (ad1, ad2, negfl, 0);
			'H' =>
				rep = ref Sedcom.CH (ad1, ad2, negfl, 0);
			'n' =>
				rep = ref Sedcom.N (ad1, ad2, negfl, 0);
			'N' =>
				rep = ref Sedcom.CN (ad1, ad2, negfl, 0);
			'x' =>
				rep = ref Sedcom.X (ad1, ad2, negfl, 0);
			'l' =>
				rep = ref Sedcom.L (ad1, ad2, negfl, 0);
 			'y' =>
				if (s == "")
					fatal("expected args: " + linebuf);
				seof := s[0:1];
				s = s[1:];
				if (s == "")
					fatal("no lhs: " + linebuf);
				(lhs, s2) := str->splitl(s, seof);
				if (s2 == "")
					fatal("no lhs terminator: " + linebuf);
				s2 = s2[1:];
				(rhs, s4) := str->splitl(s2, seof);
				if (s4 == "")
					fatal("no rhs: " + linebuf);
				s = s4[1:];
				if (len lhs != len rhs)
					fatal("y command needs same length sets: " + linebuf);
				map: list of (int, int);
				for (i := 0; i < len lhs; i++)
					map = (lhs[i], rhs[i]) :: map;
				rep = ref Sedcom.Y (ad1, ad2, negfl, 0, map);
			's' =>
				seof := s[0:1];
				re: Re;
				(re, s) = recomp(s);
				rhs: string;
				(s, rhs) = compsub(seof + s);

				gfl := gflag;
				pfl := 0;

				if (s != "" && s[0] == 'g') {
					gfl = 1;
					s = s[1:];
				}
				if (s != "" && s[0] == 'p') {
					pfl = 1;
					s = s[1:];
				}
				if (s != "" && s[0] == 'P') {
					pfl = 2;
					s = s[1:];
				}

				b: ref Iobuf = nil;
				if (s != "" && s[0] == 'w') {
					s = s[1:];
					if (s != "")
						s = str->drop(s, " \t");
					if (s == "")
						fatal("no filename in s with w: " + linebuf);
					b = bufio->open(s, bufio->OWRITE);
					if (b == nil)
						b = bufio->create(s, bufio->OWRITE, 8r666);
					if (b == nil)
						fatal(sys->sprint("can't create output file: '%s'", s));
					bufioflush = b :: bufioflush;
					s = "";
				}
				rep = ref Sedcom.S (ad1, ad2, negfl, 0, gfl, pfl, re, b, rhs);
			':' =>
				if (s != "")
					s = str->drop(s, " \t");
				(lab, s1) := str->splitl(s, " \t;#");
				s = s1;
				if (lab == "")
					fatal(sys->sprint("null label: '%s'", linebuf));
				if (findlabel(lab))
					fatal(sys->sprint("duplicate label: '%s'", lab));
				rep = ref Sedcom.Lab (ad1, ad2, negfl, 0, lab);
			'b' or 't' =>
				if (s != "")
					s = str->drop(s, " \t");
				(lab, s1) := str->splitl(s, " \t;#");
				s = s1;
				if (c == 'b')
					rep = ref Sedcom.B (ad1, ad2, negfl, 0, lab);
				else
					rep = ref Sedcom.T (ad1, ad2, negfl, 0, lab);
			'{' =>
				# replace { with branch to }.
				lab := mklab(depth);
				depth++;
				rep = ref Sedcom.B (ad1, ad2, !negfl, 0, lab);
				s = ";" + s;
			'}' =>
				if (tagof ad1 != tagof Addr.None)
					fatal("did not expect address:" + linebuf);
				if (--depth < 0)
					fatal("too many }'s: " + linebuf);
				lab := mklab(depth);
				cmdcnt[depth]++;
				rep = ref Sedcom.Lab ( ad1, ad2, negfl, 0, lab);
				s = ";" + s;
			}

			l = rep :: l;
		} while (s != nil && str->in(s[0], ";{}"));

		if (s != nil)
			fatal("leftover junk: " + s);
	}
	return l;
}

findlabel(lab: string) : bool
{
	for (l := cmds; l != nil; l = tl l)
		pick x := hd l {
		Lab =>
			if (x.lab == lab)
				return true;
		}
	return false;
}

mklab(depth: int): string
{
	return "_" + string cmdcnt[depth] + "_" + string depth;
}

Sedcom.command(c: self ref Sedcom)
{
	pick x := c {
	S =>
		m: bool;
		(m, patsp) = substitute(x, patsp);
		if (m) {
			case x.pfl {
			0 =>
				;
			1 =>
				fout.puts(patsp + "\n");
			* =>
				l: string;
				(l, patsp) = str->splitl(patsp, "\n");
				fout.puts(l + "\n");
				break;
			}
			if (x.b != nil)
				x.b.puts(patsp + "\n");
		}
	P =>
		fout.puts(patsp + "\n");
	CP =>
		(s, nil) := str->splitl(patsp, "\n");
		fout.puts(s + "\n");
	A =>
		appendlist = c :: appendlist;
	R =>
		appendlist = c :: appendlist;
	C =>
		delflag++;
		if (c.active == 1)
			fout.puts(x.text + "\n");
	I =>
		fout.puts(x.text + "\n");
	W =>
		x.b.puts(patsp + "\n");
	G =>
		patsp = holdsp;
	CG =>
		patsp += holdsp;
	H =>
		holdsp = patsp;
	CH =>
		holdsp += patsp;
	X =>
		(holdsp, patsp) = (patsp, holdsp);
	Y =>
		# yes this is O(N²).
		for (i := 0; i < len patsp; i++)
			for (h := x.map; h != nil; h = tl h) {
				(s, d) := hd h;
				if (patsp[i] == s)
					patsp[i] = d;
			}
	D =>
		delflag++;
	CD =>
		# loose upto \n.
		(s1, s2) := str->splitl(patsp, "\n");
		if (s2 == nil)
			patsp = s1;
		else if (len s2 > 1)
			patsp = s2[1:];
		else
			patsp = "";
		jflag++;
	Q =>
		if (!nflag)
			fout.puts(patsp + "\n");
		arout();
		exits(nil);
	N =>
		if (!nflag)
			fout.puts(patsp + "\n");
		arout();
		n: int;
		(patsp, n) = gline();
		if (n < 0)
			delflag++;
	CN =>
		arout();
		(ns, n) := gline();
		if (n < 0)
			delflag++;
		patsp += "\n" + ns;
	EQ =>
		fout.puts(sys->sprint("%d\n", lnum));
	Lab =>
		# labels don't do anything.
	B =>
		jflag = true;
	T =>
		if (sflag) {
			sflag = false;
			jflag = true;
		}
	L =>
		col := 0;
		cc := 0;
		for (i := 0; i < len patsp; i++) {
			s := "";
			cc = patsp[i];
			if (cc >= 16r20 && cc < 16r7F && cc != '\n')
				s[len s] = cc;
			else
				s = trans(cc);
			for (j := 0; j < len s; j++) {
				fout.putc(s[j]);
				if (col++ > 71) {
					fout.puts("\\\n");
					col = 0;
				}
			}
		}
		if (cc == ' ')
			fout.puts("\\n");
		fout.putc('\n');
	* =>
		fatal("unhandled command");
	}
}

trans(ch: int) : string
{
	case ch {
	'\b' =>
		return "\\b";
	'\n' =>
		return "\\n";
	'\r' =>
		return "\\r";
	'\t' =>
		return "\\t";
	'\\' =>
		return "\\\\";
	* =>
		return sys->sprint("\\u%4x", ch);
	}
}

getline(b: ref Iobuf) : (int, string)
{
	w : string;

	lnum++;

	while ((c := b.getc()) != bufio->EOF) {
		r := c;
		if (r == '\\') {
			w[len w] = r;
			if ((c = b.getc()) == bufio->EOF)
				break;
			r = c;
		}
		else if (r == '\n')
			return (1, w);
		w[len w] = r;
	}
	return (-1, w);
}

address(s: string) : (string, ref Addr)
{
	case s[0] {
	'$' =>
		return (s[1:], ref Addr.Dollar());
	'/' =>
		(r, s1) := recomp(s);
		if (r == nil)
			r = lastregex;
		if (r == nil)
			fatal("First RE in address may not be null");
		return (s1, ref Addr.Regex(r));
	'0' to '9' =>
		(lno, ls) := str->toint(s, 10);
		if (lno == 0)
			fatal("line no 0 is illegal address");
		return (ls, ref Addr.Line(lno));
	* =>
		return (s, ref Addr.None());
	}
}

recomp(s :string) : (Re, string)
{
	expbuf := "";

	seof := s[0]; s = s[1:];
	if (s[0] == seof)
		return (nil, s[1:]); # //

	c := s[0]; s = s[1:];
	do {
		if (c == '\0' || c == '\n')
			fatal("too much text: " + linebuf);
		if (c == '\\') {
			expbuf[len expbuf] = c;
			c = s[0]; s = s[1:];
			if (c == 'n')
				c = '\n';
		}
		expbuf[len expbuf] = c;
		c = s[0]; s = s[1:];
	} while (c != seof);

	(r, err) := regex->compile(expbuf, 1);
	if (r == nil)
		fatal(sys->sprint("%s '%s'", err, expbuf));

	lastregex = r;

	return (r, s);
}

compsub(s: string): (string, string)
{
	seof := s[0];
	rhs := "";
	for (i := 1; i < len s; i++) {
		r := s[i];
		if (r == seof)
			break;
		if (r == '\\') {
			rhs[len rhs] = r;
			if(++i >= len s)
				break;
			r = s[i];
		}
		rhs[len rhs] = r;
	}
	if (i >= len s)
		fatal(sys->sprint("no closing %c in replacement text: %s", seof,  linebuf));
	return (s[i+1:], rhs);
}		

execute(l: list of ref Sedcom)
{
	for (;;) {
		n: int;

		(patsp, n) = gline();
		if (n < 0)
			break;

cmdloop:
		for (p := l; p != nil;) {
			c := hd p;
			if (!c.executable()) {
				p = tl p;
				continue;
			}

			c.command();

			if (delflag)
				break;
			if (jflag) {
				jflag = 0;
				pick x := c {
				B or T =>
					if (p == nil)
						break cmdloop;
					for (p = l; p != nil; p = tl p) {
						pick cc := hd p {
						Lab =>
							if (cc.lab == x.lab)
								continue cmdloop;
						}
					}
					break cmdloop; # unmatched branch => end of script
				* =>
					# don't branch.
				}
			}
			else
				p = tl p;
		}
		if (!nflag && !delflag)
			fout.puts(patsp + "\n");
		arout();
		delflag = 0;
	}
}

Sedcom.executable(c: self ref Sedcom) : int
{
	if (c.active) {
		if (c.active == 1)
			c.active = 2;
		pick x := c.ad2 {
		None =>
			c.active = 0;
		Dollar =>
			return !c.negfl;
		Line =>
			if (lnum <= x.line) {
				if (x.line == lnum)
					c.active = 0;
				return !c.negfl;
			}
			c.active = 0;
			return c.negfl;
		Regex =>
			if (match(x.re, patsp))
				c.active = false;
			return !c.negfl;
		}
	}
	pick x := c.ad1 {
	None =>
		return !c.negfl;
	Dollar =>
		if (dolflag)
			return !c.negfl;
	Line =>
		if (x.line == lnum) {
			c.active = 1;
			return !c.negfl;
		}
	Regex =>
		if (match(x.re, patsp)) {
			c.active = 1;
			return !c.negfl;
		}
	}
	return c.negfl;
}

arout()
{
	a: list of ref Sedcom;

	while (appendlist != nil) {
		a = hd appendlist :: a;
		appendlist = tl appendlist;
	}

	for (; a != nil; a = tl a)
		pick x := hd a {
		A =>
			fout.puts(x.text + "\n");
		R =>
			if ((b := bufio->open(x.filename, bufio->OREAD)) == nil)
				fatal(sys->sprint("couldn't open '%s'", x.filename));
			while ((c := b.getc()) != bufio->EOF)
				fout.putc(c);
			b.close();
		* =>
			fatal("unexpected command on appendlist");
		}
}

match(re: Re, s: string) : bool
{
	if (re != nil && regex->execute(re, s) != nil)
		return true;
	else
		return false;
}

substitute(c: ref Sedcom.S, s: string) : (bool, string)
{
	if (!match(c.re, s))
		return (false, s);
	sflag = true;
	start := 0;

	do {
		se := (start, len s);
		if ((m := regex->executese(c.re, s, se, true, true)) == nil)
			break;
		(l, r) := m[0];
		rep := "";
		for (i := 0; i < len c.rhs; i++){
			if (c.rhs[i] != '\\' )
				rep[len rep] = c.rhs[i];
			else {
				i++;
				case c.rhs[i] {
				'0' to '9' =>
					n := c.rhs[i] - '0';
					# elide if too big
					if (n < len m) {
						(beg, end) := m[n];
						rep += s[beg:end];
					}
				'n' =>
					rep[len rep] = '\n';
				* =>
					rep[len rep] = c.rhs[i];
				}
			}
		}
		s = s[0:l] + rep + s[r:];
		start++;
	} while (c.gfl);
	return (true, s);
}

gline() : (string, int)
{
	if (infile == nil && opendatafile() < 0)
		return (nil, -1);

	sflag = false;
	lnum++;

	s := "";
	do {
		c := peekc;
		if (c == 0)
			c = infile.getc();
		for (; c != bufio->EOF; c = infile.getc()) {
			if (c == '\n') {
				if ((peekc = infile.getc()) == bufio->EOF)
					if (fhead == 0)
						dolflag = 1;
				return (s, 1);
			}
			s[len s] = c;
		}
		if (len s != 0) {
			peekc = bufio->EOF;
			if (fhead == 0)
				dolflag = 1;
			return (s, 1);
		}
		peekc = 0;
		infile = nil;			
	} while (opendatafile() > 0);
	infile = nil;
	return (nil, -1);
}

opendatafile() : int
{
	if (files == nil)
		return -1;
	if (hd files != nil) {
		if ((infile = bufio->open(hd files, bufio->OREAD)) == nil)
			fatal(sys->sprint("can't open '%s'", hd files));
	}
	else if ((infile = bufio->fopen(sys->fildes(0), bufio->OREAD)) == nil)
		fatal("can't buffer stdin");

	files = tl files;
	return 1;	
}

dbg(s: string)
{
	if (dflag)
		sys->print("dbg: %s\n", s);
}

usage()
{
	sys->fprint(stderr(), "usage: %s [-ngd] [-e expr] [-f file] [expr] [file...]\n",
		arg->progname());
	exits("usage");
}

fatal(s: string)
{
	f := filename;
	if (f == nil)
		f = "<stdin>";
	sys->fprint(stderr(), "%s:%d %s\n", f, lnum, s);
	exits("error");
}

exits(e: string)
{
	for(; bufioflush != nil; bufioflush = tl bufioflush)
		(hd bufioflush).flush();
	if (e != nil)
		raise "fail:" + e;
	exit;
}

stderr() : ref Sys->FD
{
	return sys->fildes(2);
}
