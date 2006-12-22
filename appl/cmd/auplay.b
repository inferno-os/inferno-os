implement AuPlay;

include "sys.m";
include "draw.m";

sys:	Sys;
FD:	import sys;
stderr:	ref FD;

include "string.m";

str:	String;

prog:	string;
play:	int;
Magic:	con "rate";
data:	con "/dev/audio";
ctl:	con "/dev/audioctl";
buffz:	con Sys->ATOMICIO;

AuPlay: module
{
	init:	fn(ctxt: ref Draw->Context, argv: list of string);
};

process(f: string)
{
	buff := array[buffz] of byte;
	inf := sys->open(f, Sys->OREAD);
	if (inf == nil) {
		sys->fprint(stderr, "%s: could not open %s: %r\n", prog, f);
		return;
	}
	n := sys->read(inf, buff, buffz);
	if (n < 0) {
		sys->fprint(stderr, "%s: could not read %s: %r\n", prog, f);
		return;
	}
	if (n < 10 || string buff[0:4] != Magic) {
		sys->fprint(stderr, "%s: %s: not an audio file\n", prog, f);
		return;
	}
	i := 0;
	for (;;) {
		if (i == n) {
			sys->fprint(stderr, "%s: %s: bad header\n", prog, f);
			return;
		}
		if (buff[i] == byte '\n') {
			i++;
			if (i == n) {
				sys->fprint(stderr, "%s: %s: bad header\n", prog, f);
				return;
			}
			if (buff[i] == byte '\n') {
				i++;
				if ((i % 4) != 0) {
					sys->fprint(stderr, "%s: %s: unpadded header\n", prog, f);
					return;
				}
				break;
			}
		}
		else
			i++;
	}
	if (!play) {
		sys->write(stderr, buff, i - 1);
		return;
	}
	df := sys->open(data, Sys->OWRITE);
	if (df == nil) {
		sys->fprint(stderr, "%s: could not open %s: %r\n", prog, data);
		return;
	}
	cf := sys->open(ctl, Sys->OWRITE);
	if (cf == nil) {
		sys->fprint(stderr, "%s: could not open %s: %r\n", prog, ctl);
		return;
	}
	if (sys->write(cf, buff, i - 1) < 0) {
		sys->fprint(stderr, "%s: could not write %s: %r\n", prog, ctl);
		return;
	}
	if (n > i && sys->write(df, buff[i:n], n - i) < 0) {
		sys->fprint(stderr, "%s: could not write %s: %r\n", prog, data);
		return;
	}
	if (sys->stream(inf, df, Sys->ATOMICIO) < 0) {
		sys->fprint(stderr, "%s: could not stream %s: %r\n", prog, data);
		return;
	}
}

init(nil: ref Draw->Context, argv: list of string)
{
	sys = load Sys Sys->PATH;
	str = load String String->PATH;
	stderr = sys->fildes(2);
	p := hd argv;
	v := tl argv;
	(nil, b) := str->splitr(p, "/");
	if (b != nil)
		p = b;
	(b, nil) = str->splitr(p, ".");
	if (b != nil)
		p = b[0:len b - 1];
	prog = p;
	play = prog == "auplay";
	while (v != nil) {
		process(hd v);
		v = tl v;
	}
}
