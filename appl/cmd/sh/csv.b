implement Shellbuiltin;

# parse/generate comma-separated values.

include "sys.m";
	sys: Sys;
include "draw.m";
include "sh.m";
	sh: Sh;
	Listnode, Context: import sh;
	myself: Shellbuiltin;
include "bufio.m";
	bufio: Bufio;
	Iobuf: import bufio;

initbuiltin(ctxt: ref Context, shmod: Sh): string
{
	sys = load Sys Sys->PATH;
	sh = shmod;
	myself = load Shellbuiltin "$self";
	if (myself == nil)
		ctxt.fail("bad module", sys->sprint("csv: cannot load self: %r"));
	bufio = load Bufio Bufio->PATH;
	if (bufio == nil)
		ctxt.fail("bad module",
			sys->sprint("csv: cannot load: %s: %r", Bufio->PATH));
	ctxt.addbuiltin("getcsv", myself);
	ctxt.addsbuiltin("csv", myself);
	return nil;
}

whatis(nil: ref Sh->Context, nil: Sh, nil: string, nil: int): string
{
	return nil;
}

getself(): Shellbuiltin
{
	return myself;
}

runbuiltin(c: ref Sh->Context, nil: Sh,
			cmd: list of ref Sh->Listnode, last: int): string
{
	return builtin_getcsv(c, cmd, last);
}

runsbuiltin(c: ref Sh->Context, nil: Sh,
			cmd: list of ref Sh->Listnode): list of ref Listnode
{
	return sbuiltin_csv(c, cmd);
}

builtin_getcsv(ctxt: ref Context, argv: list of ref Listnode, nil: int) : string
{
	n := len argv;
	if (n != 2 || !iscmd(hd tl argv))
		builtinusage(ctxt, "getcsv {cmd}");
	cmd := hd tl argv :: ctxt.get("*");
	stdin := bufio->fopen(sys->fildes(0), Sys->OREAD);
	if (stdin == nil)
		ctxt.fail("bad input", sys->sprint("getcsv: cannot open stdin: %r"));
	status := "";
	ctxt.push();
	for(;;){
		{
			for (;;) {
				line: list of ref Listnode = nil;
				sl := readcsvline(stdin);
				if (sl == nil)
					break;
				for (; sl != nil; sl = tl sl)
					line = ref Listnode(nil, hd sl) :: line;
				ctxt.setlocal("line", line);
				status = setstatus(ctxt, ctxt.run(cmd, 0));
			}
			ctxt.pop();
			return status;
		}
		exception e{
			"fail:*" =>
				ctxt.pop();
				if (loopexcept(e) == BREAK)
					return status;
				ctxt.push();
		}
	}
}

CONTINUE, BREAK: con iota;
loopexcept(ename: string): int
{
	case ename[5:] {
	"break" =>
		return BREAK;
	"continue" =>
		return CONTINUE;
	* =>
		raise ename;
	}
	return 0;
}

iscmd(n: ref Listnode): int
{
	return n.cmd != nil || (n.word != nil && n.word[0] == '{');
}
	
builtinusage(ctxt: ref Context, s: string)
{
	ctxt.fail("usage", "usage: " + s);
}

setstatus(ctxt: ref Context, val: string): string
{
	ctxt.setlocal("status", ref Listnode(nil, val) :: nil);
	return val;
}

# in csv format, is it possible to distinguish between a line containing
# one empty field and a line containing no fields at all?
# what does each one look like?
readcsvline(iob: ref Iobuf): list of string
{
	sl: list of string;

	for(;;) {
		(s, eof) := readcsvword(iob);
		if (sl == nil && s == nil && eof)
			return nil;

		c := Bufio->EOF;
		if (!eof)
			c = iob.getc();
		sl = s :: sl;
		if (c == '\n' || c == Bufio->EOF)
			return sl;
	}
}

sbuiltin_csv(nil: ref Context, val: list of ref Listnode): list of ref Listnode
{
	val = tl val;
	if (val == nil)
		return nil;
	s := s2qv(word(hd val));
	for (val = tl val; val != nil; val = tl val)
		s += "," + s2qv(word(hd val));
	return ref Listnode(nil, s) :: nil;
}

s2qv(s: string): string
{
	needquote := 0;
	needscan := 0;
	for (i := 0; i < len s; i++) {
		c := s[i];
		if (c == '\n' || c == ',')
			needquote = 1;
		else if (c == '"') {
			needquote = 1;
			needscan = 1;
		}
	}
	if (!needquote)
		return s;
	if (!needscan)
		return "\"" + s + "\"";
	r := "\"";
	for (i = 0; i < len s; i++) {
		c := s[i];
		if (c == '"')
			r[len r] = c;
		r[len r] = c;
	}
	r[len r] = '"';
	return r;
}

readcsvword(iob: ref Iobuf): (string, int)
{
	s := "";
	case c := iob.getc() {
	'"' =>
		for (;;) {
			case c = iob.getc() {
			Bufio->EOF =>
				return (s, 1);
			'"' =>
				case c = iob.getc() {
				'"' =>
					s[len s] = '"';
				'\n' or
				',' =>
					iob.ungetc();
					return (s, 0);
				Bufio->EOF =>
					return (s, 1);
				* =>
					# illegal
					iob.ungetc();
					(t, eof) := readcsvword(iob);
					return (s + t, eof);
				}
			* =>
				s[len s] = c;
			}
		}
	',' or
	'\n' =>
		iob.ungetc();
		return (s, 0);
	Bufio->EOF =>
		return (nil, 1);
	* =>
		s[len s] = c;
		for (;;) {
			case c = iob.getc() {
			',' or
			'\n' =>
				iob.ungetc();
				return (s, 0);
			'"' =>
				# illegal
				iob.ungetc();
				(t, eof) := readcsvword(iob);
				return (s + t, eof);
			Bufio->EOF =>
				return (s, 1);
			* =>
				s[len s] = c;
			}
		}
	}
}

word(n: ref Listnode): string
{
	if (n.word != nil)
		return n.word;
	if (n.cmd != nil)
		n.word = sh->cmd2string(n.cmd);
	return n.word;
}
