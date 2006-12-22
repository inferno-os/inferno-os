implement Gunzip;

include "sys.m";
	sys:	Sys;
	fprint, sprint: import sys;

include "draw.m";

include "string.m";
	str: String;

include "bufio.m";
	bufio:	Bufio;
	Iobuf:	import bufio;

include "filter.m";
	inflate: Filter;

Gunzip: module
{
	init:	fn(ctxt: ref Draw->Context, argv: list of string);
};

argv0:	con "gunzip";
stderr:	ref Sys->FD;

INFLATEPATH: con "/dis/lib/inflate.dis";

init(nil: ref Draw->Context, argv: list of string)
{
	sys = load Sys Sys->PATH;
	stderr = sys->fildes(2);
	bufio = load Bufio Bufio->PATH;
	if (bufio == nil)
		fatal(sys->sprint("cannot load %s: %r", Bufio->PATH));
	str = load String String->PATH;
	if (bufio == nil)
		fatal(sys->sprint("cannot load %s: %r", String->PATH));
	inflate = load Filter INFLATEPATH;
	if (inflate == nil)
		fatal(sys->sprint("cannot load %s: %r", INFLATEPATH));

	inflate->init();

	if(argv != nil)
		argv = tl argv;

	ok := 1;
	if(len argv == 0){
		bin := bufio->fopen(sys->fildes(0), Bufio->OREAD);
		bout := bufio->fopen(sys->fildes(1), Bufio->OWRITE);
		ok = gunzip(bin, bout, "stdin", "stdout");
		bout.close();
	} else {
		for(; argv != nil; argv = tl argv)
			ok &= gunzipf(hd argv);
	}
	if(ok == 0)
		raise "fail:errors";
}

gunzipf(file: string): int
{
	bin := bufio->open(file, Bufio->OREAD);
	if(bin == nil){
		fprint(stderr, "%s: can't open %s: %r\n", argv0, file);
		return 0;
	}

	(nil, ofile) := str->splitr(file, "/");
	n := len ofile;
	if(n < 4 || ofile[n-3:] != ".gz"){
		fprint(stderr, "%s: .gz extension required: %s\n", argv0, file);
		bin.close();
		return 0;
	} else
		ofile = ofile[:n-3];
	bout := bufio->create(ofile, Bufio->OWRITE, 8r666);
	if(bout == nil){
		fprint(stderr, "%s: can't open %s: %r\n", argv0, ofile);
		bin.close();
		return 0;
	}

	ok := gunzip(bin, bout, file, ofile);
	bin.close();
	bout.close();
	if(ok) {
		# did possibly rename file and update modification time here.
		if (sys->remove(file) == -1)
			sys->fprint(stderr, "%s: cannot remove %s: %r\n", argv0, file);
	}

	return ok;
}

gunzip(bin, bout: ref Iobuf, fin, fout: string): int
{
	rq := inflate->start("h");
	for(;;) {
		pick m := <-rq {
		Fill =>
			n := bin.read(m.buf, len m.buf);
			m.reply <-= n;
			if (n == -1) {
				sys->fprint(stderr, "%s: %s: read error: %r\n", argv0, fin);
				return 0;
			}
		Result =>
			if (len m.buf > 0) {
				n := bout.write(m.buf, len m.buf);
				if (n != len m.buf) {
					m.reply <-= -1;
					sys->fprint(stderr, "%s: %s: write error: %r\n", argv0, fout);
					return 0;
				}
				m.reply <-= 0;
			}
		#Info =>
		#	if m.msg begins with "file", it's the original filename of the compressed file.
		#	if m.msg begins with "mtime", it's the original modification time.
		Finished =>
			if (bout.flush() != 0) {
				sys->fprint(stderr, "%s: %s: flush error: %r\n", argv0, fout);
				return 0;
			}
			return 1;
		Error =>
			sys->fprint(stderr, "%s: %s: inflate error: %s\n", argv0, fin, m.e);
			return 0;
		}
	}
}

fatal(msg: string)
{
	fprint(stderr, "%s: %s\n", argv0, msg);
	raise "fail:error";
}
