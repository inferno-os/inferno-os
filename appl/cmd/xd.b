implement Xd;

#
# based on Plan9 xd
#

include "sys.m";
include "draw.m";
include "bufio.m";

Xd: module  
{
	init: fn(ctxt: ref Draw->Context, argv: list of string);
};

sys : Sys;
bufio : Bufio;
Iobuf : import bufio;
stdin, stdout, stderr : ref Sys->FD;

wbytes := array [] of {
	1,
	2,
	4,
	8,
};
fmtchars : con "odx";
fmtbases := array [] of {
	8,
	10,
	16,
};
fwidths := array [] of {
	3,	# 1o
	3,	# 1d
	2,	# 1x
	6,	# 2o
	5,	# 2d
	4,	# 2x
	11,	# 4o
	10,	# 4d
	8,	# 4x
	22,	# 8o
	20,	# 8d
	16,	# 8x
};

bytepos := array [16] of { * => 0 };

formats := array [10] of (int, int, int);	# (nbytes, base, fieldwidth)
nformats := 0;
addrbase := 16;
repeats := 0;
swab := 0;
flush := 0;
addr := big 0;
output : ref Iobuf;
pad : string;


init(nil : ref Draw->Context, argv : list of string)
{
	sys = load Sys Sys->PATH;
	stdin  = sys->fildes(0);
	stdout = sys->fildes(1);
	stderr = sys->fildes(2);

	bufio = load Bufio Bufio->PATH;
	if (bufio == nil) {
		sys->fprint(stderr, "cannot load bufio: %r\n");
		raise "fail:init";
	}
	output = bufio->fopen(stdout, Sys->OWRITE);
	if (argv == nil)
		raise "fail:bad argv";

	pad = string array [32] of { * => byte ' ' };

	for (argv = tl argv; argv != nil; argv = tl argv) {
		arg := hd argv;
		if (arg == nil)
			continue;
		if (arg[0] != '-')
			break;

		if (len arg == 2) {
			case arg[1] {
			'c' =>
				addformat(0, 256);
			'r' =>
				repeats = 1;
			's' =>
				swab = 1;
			'u' =>
				flush = 1;
			* =>
				usage();
			}
			continue;
		}
		# XXX should allow -x1, -x
		if (len arg == 3) {
			n := 0;
			baseix := strchr(fmtchars,arg[2]);
			if (baseix == -1)
				usage();
			case arg[1] {
			'a' =>
				addrbase = fmtbases[baseix];
				continue;
			'b' or '1' =>	n = 0;
			'w' or '2' =>	n = 1;
			'l' or '4' =>	n = 2;
			'v' or '8' =>	n = 3;
			* =>
				usage();
			}
			addformat(n, baseix);
			continue;
		}
		usage();
	}
	if (nformats == 0)
		addformat(2, 2);	# "4x"

	if (argv == nil)
		dump(nil, 0);
	else if (tl argv == nil)
		dump(hd argv, 0);
	else {
		for (; argv != nil; argv = tl argv) {
			dump(hd argv, 1);
		}
	}
}

usage()
{
	sys->fprint(stderr, "usage: xd [-u] [-r] [-s] [-a{odx}] [-c|{b1w2l4v8}{odx}] ... file ...\n");
	raise "fail:usage";
}

strchr(s : string, ch : int) : int
{
	for (ix := 0; ix < len s; ix++)
		if (s[ix] == ch)
			return ix;
	return -1;
}

addformat(widix, baseix : int)
{
	nbytes := wbytes[widix];
	if (nformats >= len formats) {
		sys->fprint(stderr, "xd: too many formats\n");
		raise "fail:error";
	}
	fw : int;
	if (baseix == 256) {
		# special -c case
		formats[nformats++] = (nbytes, 256, 2);
		fw = 2;
	} else {
		fw = fwidths[baseix + (widix *len fmtbases)];
		formats[nformats++] = (nbytes, fmtbases[baseix], fw);
	}
	bpos := 0;
	for (ix := 0; ix < 16; ix += nbytes) {
		if (bytepos[ix] >= bpos)
			bpos = bytepos[ix];
		else {
			d := bpos - bytepos[ix];
			for (dix := ix; dix < 16; dix++)
				bytepos[dix] += d;
		}
		bpos += fw + 1;
	}
}

dump(path : string, title : int)
{
	input := bufio->fopen(stdin, Sys->OREAD);
	zeros := array [16] of {* => byte 0};

	if (path != nil) {
		input = bufio->open(path, Sys->OREAD);
		if (input == nil) {
			sys->fprint(stderr, "xd: cannot open %s: %r\n", path);
			raise "fail:cannot open";
		}
	}

	if (title) {
		output.puts(path);
		output.putc('\n');
	}

	addr = big 0;
	star := 0;
	obuf: array of byte;

	for (;;) {
		n := 0;
		buf := array [16] of byte;
		while (n < 16 && (r := input.read(buf[n:], 16 - n)) > 0)
			n += r;
		if (n < 16)
			buf[n:] = zeros[n:];
		if (swab)
			doswab(buf);
		if (n == 16 && repeats) {
			if (obuf != nil && buf[0]==obuf[0]) {
				for (i := 0; i < 16; i++)
					if (obuf[i] != buf[i])
						break;
				if (i == 16) {
					addr += big 16;
					if (star == 0) {
						star++;
						output.puts("*\n");
					}
					continue;
				}
			}
			obuf = buf;
			star = 0;
		}
		for (fmt := 0; fmt < nformats; fmt++) {
			if (fmt == 0)
				output.puts(big2str(addr, 7, addrbase, '0'));
			else
				output.puts(big2str(addr, 7, addrbase, ' '));
			output.putc(' ');
			(w, b, fw) := formats[fmt];
			pdata(fw, w, b, n, buf);
			output.putc('\n');
			if (flush)
				output.flush();
		}
		addr += big n;
		if (n < 16) {
			output.puts(big2str(addr, 7, addrbase, '0'));
			output.putc('\n');
			if (flush)
				output.flush();
			break;
		}
	}
	output.flush();
}

hexchars : con "0123456789abcdef";

big2str(b : big, minw, base, padc  : int) : string
{
	s := "";
	do {
		d := int (b % big base);
		s[len s] = hexchars[d];
		b /= big base;
	} while (b > big 0);
	t := "";
	if (len s < minw)
		t = string array [minw] of { * => byte padc };
	else
		t = s;
	for (i := len s - 1; i >= 0; i--)
		t[len t - 1 - i] = s[i];
	return t;
}

pdata(fw, n, base, dlen : int, data : array of byte)
{
	nout := 0;
	text := "";

	for (i := 0; i < dlen; i += n) {
		if (i != 0) {
			padlen := bytepos[i] - nout;
			output.puts(pad[0:padlen]);
			nout += padlen;
		}
		if (base == 256) {
			# special -c case
			ch := int data[i];
			case ch {
			'\t' =>	text = "\\t";
			'\r' =>	text = "\\r";
			'\n' =>	text = "\\n";
			'\b' =>	text = "\\b";
			* =>
				if (ch >= 16r7f || ' ' > ch)
					text = sys->sprint("%.2x", ch);
				else
					text = sys->sprint("%c", ch);
			}
		} else {
			v := big data[i];
			for (ix := 1; ix < n; ix++)
				v = (v << 8) + big data[i+ix];
			text = big2str(v, fw, base, '0');
		}
		output.puts(text);
		nout += len text;
	}
}

doswab(b : array of byte)
{
	ix := 0;
	for (i := 0; i < 4; i++) {
		(b[ix], b[ix+3]) = (b[ix+3], b[ix]);
		(b[ix+1], b[ix+2]) = (b[ix+2], b[ix+1]);
		ix += 4;
	}
}
