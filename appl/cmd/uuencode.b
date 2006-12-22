implement Uuencode;

include "sys.m";
	sys : Sys;
include "draw.m";

Uuencode : module
{
	init : fn(nil : ref Draw->Context, argv : list of string);
};

fatal(s : string)
{
	sys->fprint(sys->fildes(2), "%s\n", s);
	exit;
}

usage()
{
	fatal("usage: uuencode [ sourcefile ] remotefile");
}

init(nil : ref Draw->Context, argv : list of string)
{
	fd : ref Sys->FD;
	mode : int;

	sys = load Sys Sys->PATH;
	argv = tl argv;
	if (argv == nil)
		usage();
	if (tl argv != nil) {
		fd = sys->open(hd argv, Sys->OREAD);
		if (fd == nil)
			fatal(sys->sprint("cannot open %s", hd argv));
		(ok, d) := sys->fstat(fd);
		if (ok < 0)
			fatal(sys->sprint("cannot stat %s: %r", hd argv));
		if (d.mode & Sys->DMDIR)
			fatal("cannot uuencode a directory");
		mode = d.mode;
		argv = tl argv;
	}
	else {
		fd = sys->fildes(0);
		mode = 8r666;
	}
	if (tl argv != nil)
		usage();
	sys->print("begin %o %s\n", mode, hd argv);
	encode(fd);
	sys->print("end\n");
}

LEN : con 45;

code(c : int) : byte
{
	return byte ((c&16r3f) + ' ');
}

encode(ifd : ref Sys->FD)
{
	c, d, e : int;

	ofd := sys->fildes(1);
	ib := array[LEN] of byte;
	ob := array[4*LEN/3 + 2] of byte;
	for (;;) {
		n := sys->read(ifd, ib, LEN);
		if (n < 0)
			fatal("cannot read input file: %r");
		if (n == 0)
			break;
		i := 0;
		ob[i++] = code(n);
		for (j := 0; j < n; j += 3) {
			c = int ib[j];
			ob[i++] = code((0<<6)&16r00 | (c>>2)&16r3f);
			if (j+1 < n)
				d = int ib[j+1];
			else
				d = 0;
			ob[i++] = code((c<<4)&16r30 | (d>>4)&16r0f);
			if (j+2 < n)
				e = int ib[j+2];
			else
				e = 0;
			ob[i++] = code((d<<2)&16r3c | (e>>6)&16r03);
			ob[i++] = code((e<<0)&16r3f | (0>>8)&16r00);
		}
		ob[i++] = byte '\n';
		if (sys->write(ofd, ob, i) != i)
			fatal("bad write to output: %r");
	}
	ob[0] = code(0);
	ob[1] = byte '\n';
	if (sys->write(ofd, ob, 2) != 2)
		fatal("bad write to output: %r");
}

