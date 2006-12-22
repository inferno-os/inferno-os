implement Uudecode;

include "sys.m";
	sys : Sys;
include "draw.m";
include "string.m";
	str : String;
include "bufio.m";
	bufio : Bufio;
	Iobuf : import bufio;

Uudecode : module
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
	fatal("usage: uudecode [ -p ] [ encodedfile... ]");
}

init(nil : ref Draw->Context, argv : list of string)
{
	fd : ref Sys->FD;

	tostdout := 0;
	sys = load Sys Sys->PATH;
	str = load String String->PATH;
	bufio = load Bufio Bufio->PATH;
	argv = tl argv;
	if (argv != nil && hd argv == "-p") {
		tostdout = 1;
		argv = tl argv;
	}
	if (argv != nil) {
		for (; argv != nil; argv = tl argv) {
			fd = sys->open(hd argv, Sys->OREAD);
			if (fd == nil)
				fatal(sys->sprint("cannot open %s", hd argv));
			decode(fd, tostdout);
		}
	}
	else
		decode(sys->fildes(0), tostdout);
}

code(c : byte) : int
{
	return (int c - ' ')&16r3f;
}

LEN : con 45;
			
decode(ifd : ref Sys->FD, tostdout : int)
{
	mode : int;
	ofile : string;

	bio := bufio->fopen(ifd, Bufio->OREAD);
	if (bio == nil)
		fatal("cannot open input for buffered io: %r");
	while ((s := bio.gets('\n')) != nil) {
		if (len s >= 6 && s[0:6] == "begin ") {
			(n, l) := sys->tokenize(s, " \n");
			if (n < 3)
				fatal("bad begin line");
			(mode, nil) = str->toint(hd tl l, 8);
			ofile = hd tl tl l;
			break;
		}
	}
	if (ofile == nil)
		fatal("no begin line");
	if (tostdout)
		ofd := sys->fildes(1);
	else {
		if (ofile[0] == '~')	# ~user/file
			ofile = "/usr/" + ofile[1:];
		ofd = sys->create(ofile, Sys->OWRITE, 8r666);
		if (ofd == nil)
			fatal(sys->sprint("cannot create %s: %r", ofile));
	}
	ob := array[LEN] of byte;
	while ((s = bio.gets('\n')) != nil) {
		b := array of byte s;
		n := code(b[0]);
		if (n == 0 && (len b != 2 || b[1] != byte '\n'))
			fatal("bad 0 count line");
		if (n <= 0)
			break;
		if (n > LEN)
			fatal("too many bytes on line");
		e := 0; f := 0;
		if (n%3 == 1) {
			e = 2; f = 4;
		}
		else if (n%3 == 2) {
			e = 3; f = 4;
		}
		if (len b < 4*(n/3)+e+2 || len b > 4*(n/3)+f+2)
			fatal("bad uuencode count");
		b = b[1:];
		i := 0;
		nl := n;
		for (j := 0; nl > 0; j += 4) {
			if (nl >= 1)
				ob[i++] = byte (code(b[j+0])<<2 | code(b[j+1])>>4);
			if (nl >= 2)
				ob[i++] = byte (code(b[j+1])<<4 | code(b[j+2])>>2);
			if (nl >= 3)
				ob[i++] = byte (code(b[j+2])<<6 | code(b[j+3])>>0);
			nl -= 3;
		}
		if (sys->write(ofd, ob, i) != i)
			fatal("bad write to output: %r");	
	}
	s = bio.gets('\n');
	if (s == nil || len s < 4 || s[0:4] != "end\n")
		fatal("missing end line");
	if (!tostdout) {
		d := sys->nulldir;
		d.mode = mode;
		if (sys->fwstat(ofd, d) < 0)
			fatal(sys->sprint("cannot wstat %s: %r", ofile));
	}
}
