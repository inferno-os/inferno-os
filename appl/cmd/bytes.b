implement Bytes;
include "sys.m";
	sys: Sys;
	stderr: ref Sys->FD;
include "draw.m";
include "bufio.m";
	bufio: Bufio;
	Iobuf: import bufio;

stdin, stdout: ref Iobuf;

Bytes: module {
	init: fn(nil: ref Draw->Context, argv: list of string);
};

usage()
{
	sys->fprint(stderr, "usage: bytes start end [bytes]\n");
	raise "fail:usage";
}

END: con 16r7fffffff;
init(nil: ref Draw->Context, argv: list of string)
{
	sys = load Sys Sys->PATH;
	stderr = sys->fildes(2);
	bufio = load Bufio Bufio->PATH;
	if (bufio == nil) {
		sys->fprint(stderr, "bytes: cannot load %s: %r\n", Bufio->PATH);
		raise "fail:bad module";
	}
	stdin = bufio->fopen(sys->fildes(0), Sys->OREAD);
	stdout = bufio->fopen(sys->fildes(1), Sys->OWRITE);
	start := end := END;
	if (len argv < 3)
		usage();
	argv = tl argv;
	if (hd argv != "end")
		start = int hd argv;
	argv = tl argv;
	if (hd argv != "end")
		end = int hd argv;
	if (end < start) {
		sys->fprint(stderr, "bytes: out of order range\n");
		raise "fail:bad range";
	}
	argv = tl argv;
	if (argv == nil)
		showbytes(start, end);
	else {
		if (tl argv != nil)
			usage();
		b := s2bytes(hd argv);
		setbytes(start, end, b);
	}
	stdout.close();
}

showbytes(start, end: int)
{
	buf := array[Sys->ATOMICIO] of byte;
	hold := array[Sys->UTFmax] of byte;
	tot := 0;
	nhold := 0;
	while (tot < end && (n := stdin.read(buf[nhold:], len buf - nhold)) > 0) {
		sys->fprint(stderr, "bytes: read %d bytes\n", n);
		if (tot + n < start)
			continue;
		sb := 0;
		eb := n;
		if (start > tot)
			sb = start - tot;
		if (tot + n > end)
			eb = end - tot;
		nhold = putbytes(buf[sb:eb], hold);
		buf[0:] = hold[0:nhold];
		tot += n - nhold;
	}
	sys->fprint(stderr, "out of loop\n");
	flushbytes(hold[0:nhold]);
}

setbytes(start, end: int, d: array of byte)
{
	buf := array[Sys->ATOMICIO] of byte;
	tot := 0;
	while ((n := stdin.read(buf, len buf)) > 0) {
		if (tot + n < start || tot >= end) {
			stdout.write(buf, n);
			continue;
		}
		if (tot <= start) {
			stdout.write(buf[0:start-tot], start-tot);
			stdout.write(d, len d);
			if (end == END)
				return;
		}
		if (tot + n >= end)
			stdout.write(buf[end - tot:], n - (end - tot));
		tot += n;
	}
	if (tot == start || start == END)
		stdout.write(d, len d);
}

putbytes(d: array of byte, hold: array of byte): int
{
	i := 0;
	while (i < len d) {
		(c, n, ok) := sys->byte2char(d, i);
		if (ok && n > 0) {
			if (c == '\\')
				stdout.putc('\\');
			stdout.putc(c);
		} else {
			if (n == 0) {
				hold[0:] = d[i:];
				return len d - i;
			} else {
				putbyte(d[i]);
				n = 1;
			}
		}
		i += n;
	}
	return 0;
}

flushbytes(hold: array of byte)
{
	for (i := 0; i < len hold; i++)
		putbyte(hold[i]);
}

putbyte(b: byte)
{
	stdout.puts(sys->sprint("\\%2.2X", int b));
}

isbschar(c: int): int
{
	case c {
	'n' or 'r' or 't' or 'v' =>
		return 1;
	}
	return 0;
}

s2bytes(s: string): array of byte
{
	d := array[len s + 2] of byte;
	j := 0;
	for (i := 0; i < len s; i++) {
		if (s[i] == '\\') {
			if (i >= len s - 1 || (!isbschar(s[i+1]) && i >= len s - 2)) {
				sys->fprint(stderr, "bytes: invalid backslash sequence\n");
				raise "fail:bad args";
			}
			d = assure(d, j + 1);
			if (isbschar(s[i+1])) {
				case s[i+1] {
				'n' =>	d[j++] = byte '\n';
				'r' =>		d[j++] = byte '\r';
				't' =>		d[j++] = byte '\t';
				'v' =>	d[j++] = byte '\v';
				'\\' =>	d[j++] = byte '\\';
				* =>
					sys->fprint(stderr, "bytes: invalid backslash sequence\n");
					raise "fail:bad args";
				}
				i++;
			} else if (!ishex(s[i+1]) || !ishex(s[i+2])) {
				sys->fprint(stderr, "bytes: invalid backslash sequence\n");
				raise "fail:bad args";
			} else {
				d[j++] = byte ((hex(s[i+1]) << 4) + hex(s[i+2]));
				i += 2;
			}
		} else {
			d = assure(d, j + 3);
			j += sys->char2byte(s[i], d, j);
		}
	}
	return d[0:j];
}

assure(d: array of byte, n: int): array of byte
{
	if (len d >= n)
		return d;
	nd := array[n] of byte;
	nd[0:] = d;
	return nd;
}

ishex(c: int): int
{
	return (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F');
}

hex(c: int): int
{
	case c {
	'0' to '9' =>
		return c - '0';
	'a' to 'f' =>
		return c - 'a' + 10;
	'A' to 'F' =>
		return c-  'A' + 10;
	}
	return 0;
}
