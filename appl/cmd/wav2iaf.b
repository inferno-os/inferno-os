implement Wav2Iaf;

include "sys.m";
include "draw.m";
include	"bufio.m";

sys:	Sys;
FD:	import sys;
bufio:	Bufio;
Iobuf:	import bufio;

stderr:	ref FD;
inf:	ref Iobuf;
prog:	string;
buff4:	array of byte;

pad	:= array[] of { "  ", " ", "", "   " };

Wav2Iaf: module
{
	init:	fn(ctxt: ref Draw->Context, argv: list of string);
};

ioerror()
{
	sys->fprint(stderr, "%s: read error: %r\n", prog);
	exit;
}

shortfile(diag: string)
{
	sys->fprint(stderr, "%s: short read: %s\n", prog, diag);
	exit;
}

error(s: string)
{
	sys->fprint(stderr, "%s: bad wave file: %s\n", prog, s);
	exit;
}

get(c: int, s: string)
{
	n := inf.read(buff4, c);
	if (n < 0)
		ioerror();
	if (n != c)
		shortfile("expected " + s);
}

gets(c: int, s: string) : string
{
	get(c, s);
	return string buff4[0:c];
}

need(s: string)
{
	get(4, s);
	if (string buff4 != s) {
		sys->fprint(stderr, "%s: not a wave file\n", prog);
		exit;
	}
}

getl(s: string) : int
{
	get(4, s);
	return int buff4[0] + (int buff4[1] << 8) + (int buff4[2] << 16) + (int buff4[3] << 24);
}

getw(s: string) : int
{
	get(2, s);
	return int buff4[0] + (int buff4[1] << 8);
}

skip(n: int)
{
	while (n > 0) {
		inf.getc();
		n--;
	}
}

bufcp(s, d: ref Iobuf, n: int)
{
	while (n > 0) {
		b := s.getb();
		if (b < 0) {
			if (b == Bufio->EOF)
				sys->fprint(stderr, "%s: short input file\n", prog);
			else
				sys->fprint(stderr, "%s: read error: %r\n", prog);
			exit;
		}
		d.putb(byte b);
		n--;
	}
}

init(nil: ref Draw->Context, argv: list of string)
{
	l: int;
	a: string;

	sys = load Sys Sys->PATH;
	stderr = sys->fildes(2);
	prog = hd argv;
	argv = tl argv;
	bufio = load Bufio Bufio->PATH;
	if (bufio == nil)
		sys->fprint(stderr, "%s: could not load %s: %r\n", prog, Bufio->PATH);
	if (argv == nil) {
		inf = bufio->fopen(sys->fildes(0), Bufio->OREAD);
		if (inf == nil) {
			sys->fprint(stderr, "%s: could not fopen stdin: %r\n", prog);
			exit;
		}
	}
	else if (tl argv != nil) {
		sys->fprint(stderr, "usage: %s [infile]\n", prog);
		exit;
	}
	else {
		inf = bufio->open(hd argv, Sys->OREAD);
		if (inf == nil) {
			sys->fprint(stderr, "%s: could not open %s: %r\n", prog, hd argv);
			exit;
		}
	}
	buff4 = array[4] of byte;
	need("RIFF");
	getl("length");
	need("WAVE");
	for (;;) {
		a = gets(4, "tag");
		l = getl("length");
		if (a == "fmt ")
			break;
		skip(l);
	}
	if (getw("format") != 1)
		error("not PCM");
	chans := getw("channels");
	rate := getl("rate");
	getl("AvgBytesPerSec");
	getw("BlockAlign");
	bits := getw("bits");
	l -= 16;
	do {
		skip(l);
		a = gets(4, "tag");
		l = getl("length");
	}
	while (a != "data");
	outf := bufio->fopen(sys->fildes(1), Sys->OWRITE);
	if (outf == nil) {
		sys->fprint(stderr, "%s: could not fopen stdout: %r\n", prog);
		exit;
	}
	s := "rate\t" + string rate + "\n"
		+  "chans\t" + string chans + "\n"
		+  "bits\t" + string bits + "\n"
		+  "enc\tpcm";
	outf.puts(s);
	outf.puts(pad[len s % 4]);
	outf.puts("\n\n");
	bufcp(inf, outf, l);
	outf.flush();
}
