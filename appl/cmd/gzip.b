implement Gzip;

include "sys.m";
	sys:	Sys;
	print, fprint: import sys;

include "draw.m";

include "string.m";
	str: String;

include "daytime.m";
	daytime: Daytime;

include "bufio.m";
	bufio:	Bufio;
	Iobuf: import bufio;

include "filter.m";
	deflate: Filter;

DEFLATEPATH: con "/dis/lib/deflate.dis";

Gzip: module
{
	init:	fn(ctxt: ref Draw->Context, argv: list of string);
};

Arg: adt
{
	argv:	list of string;
	c:	int;
	opts:	string;

	init:	fn(argv: list of string): ref Arg;
	opt:	fn(arg: self ref Arg): int;
	arg:	fn(arg: self ref Arg): string;
};

argv0:	con "gzip";
stderr:	ref Sys->FD;
debug	:= 0;
verbose	:= 0;
level	:= 0;

usage()
{
	fprint(stderr, "usage: %s [-vD1-9] [file ...]\n", argv0);
	raise "fail:usage";
}

nomod(path: string)
{
	sys->fprint(stderr, "%s: cannot load %s: %r\n", argv0, path);
	raise "fail:bad module";
}

init(nil: ref Draw->Context, argv: list of string)
{
	sys = load Sys Sys->PATH;
	stderr = sys->fildes(2);
	bufio = load Bufio Bufio->PATH;
	if (bufio == nil)
		nomod(Bufio->PATH);
	str = load String String->PATH;
	if (str == nil)
		nomod(String->PATH);
	daytime = load Daytime Daytime->PATH;
	if (daytime == nil)
		nomod(Daytime->PATH);
	deflate = load Filter DEFLATEPATH;
	if(deflate == nil)
		nomod(DEFLATEPATH);

	arg := Arg.init(argv);
	level = 6;
	while(c := arg.opt()){
		case c{
		'D' =>
			debug++;
		'v' =>
			verbose++;
		'1' to  '9' =>
			level = c - '0';
		* =>
			usage();
		}
	}

	deflate->init();

	argv = arg.argv;

	ok := 1;
	if(len argv == 0){
		bin := bufio->fopen(sys->fildes(0), Bufio->OREAD);
		bout := bufio->fopen(sys->fildes(1), Bufio->OWRITE);
		ok = gzip(nil, daytime->now(), bin, bout, "stdin", "stdout");
		bout.close();
		bin.close();
	}else{
		for(; argv != nil; argv = tl argv)
			ok &= gzipf(hd argv);
	}
	exit;
}

gzipf(file: string): int
{
	bin := bufio->open(file, Bufio->OREAD);
	if(bin == nil){
		fprint(stderr, "%s: can't open %s: %r\n", argv0, file);
		return 0;
	}
	(ok, dir) := sys->fstat(bin.fd);
	if(ok >= 0)
		mtime := dir.mtime;
	else
		mtime = daytime->now();

	(nil, ofile) := str->splitr(file, "/");
	ofile += ".gz";
	bout := bufio->create(ofile, Bufio->OWRITE, 8r666);
	if(bout == nil){
		fprint(stderr, "%s: can't open %s: %r\n", argv0, ofile);
		bin.close();
		return 0;
	}

	ok = gzip(file, mtime, bin, bout, file, ofile);
	bout.close();
	bin.close();
	if (ok)
		sys->remove(file);
	else
		sys->remove(ofile);
		
	return ok;
}

gzip(nil: string, nil: int, bin, bout: ref Iobuf, fin, fout: string): int
{
	param := "h" + string level;
	incount := outcount := 0;
	if (debug)
		param += "dv";
	rq := deflate->start(param);

	for (;;) {
		pick m := <-rq {
		Fill =>
			n := bin.read(m.buf, len m.buf);
			m.reply <-= n;
			if (n == -1) {
				sys->fprint(stderr, "%s: error reading %s: %r\n", argv0, fin);
				return 0;
			}
			incount += n;
		Result =>
			n := len m.buf;
			if (bout.write(m.buf, n) != n) {
				sys->fprint(stderr, "%s: error writing %s: %r\n", argv0, fout);
				m.reply <-= -1;
				return 0;
			}
			m.reply <-= 0;
			outcount += n;
		Info =>
			sys->fprint(stderr, "%s\n", m.msg);
		Finished =>
			comp := 0.0;
			if (incount > 0)
				comp = 1.0 - real outcount / real incount;
			if (verbose)
				sys->fprint(stderr, "%s: %5.2f%%\n", fin, comp * 100.0);
			return 1;
		Error =>
			sys->fprint(stderr, "%s: error compressing %s: %s\n", argv0, fin, m.e);
			return 0;
		}
	}
}

fatal(msg: string)
{
	fprint(stderr, "%s: %s\n", argv0, msg);
	exit;
}

Arg.init(argv: list of string): ref Arg
{
	if(argv != nil)
		argv = tl argv;
	return ref Arg(argv, 0, nil);
}

Arg.opt(arg: self ref Arg): int
{
	if(arg.opts != ""){
		arg.c = arg.opts[0];
		arg.opts = arg.opts[1:];
		return arg.c;
	}
	if(arg.argv == nil)
		return arg.c = 0;
	arg.opts = hd arg.argv;
	if(len arg.opts < 2 || arg.opts[0] != '-')
		return arg.c = 0;
	arg.argv = tl arg.argv;
	if(arg.opts == "--")
		return arg.c = 0;
	arg.c = arg.opts[1];
	arg.opts = arg.opts[2:];
	return arg.c;
}

Arg.arg(arg: self ref Arg): string
{
	s := arg.opts;
	arg.opts = "";
	if(s != "")
		return s;
	if(arg.argv == nil)
		return "";
	s = hd arg.argv;
	arg.argv = tl arg.argv;
	return s;
}
