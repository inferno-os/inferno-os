implement Ftest;
#
# test file permissions or attributes
#

include "sys.m";
	sys: Sys;
include "draw.m";

stderr: ref Sys->FD;

Ftest: module
{
	init:	fn(ctxt: ref Draw->Context, argv: list of string);
};

Topr, Topw, Topx, Tope, Topf, Topd, Tops: con iota;

init(nil: ref Draw->Context, argl: list of string)
{
	if(argl == nil)
		return;

	sys = load Sys Sys->PATH;
	stderr = sys->fildes(2);

	if (tl argl == nil)
		usage();

	a := hd tl argl;
	argl = tl tl argl;
	ok := 0;
	case a {
	"-f" =>
		ok = filck(nxtarg(argl), Topf);
	"-d" =>
		ok = filck(nxtarg(argl), Topd);
	"-r" =>
		ok = filck(nxtarg(argl), Topr);
	"-w" =>
		ok = filck(nxtarg(argl), Topw);
	"-x" =>
		ok = filck(nxtarg(argl), Topx);
	"-e" =>
		ok = filck(nxtarg(argl), Tope);
	"-s" =>
		ok = filck(nxtarg(argl), Tops);
	"-t" =>
		fd := 1;
		if (argl != nil) {
			if (!isint(hd argl)) {
				sys->fprint(stderr, "ftest: bad argument to -t\n");
				usage();
			}
			fd = int hd argl;
		}
		ok = isatty(fd);
	* =>
		sys->fprint(stderr, "test: unknown option %s\n", a);
		usage();
	}
	if (!ok)
		raise "fail:false";
}

nxtarg(argl: list of string): string
{
	if(argl == nil) {
		sys->fprint(stderr, "test: argument expected\n");
		usage();
	}
	return hd argl;
}

usage()
{
	sys->fprint(stderr, "usage: (ftest -fdrwxes file)|(ftest -t fdno)\n");
	raise "fail:usage";
}

isint(s: string): int
{
	if(s == nil)
		return 0;
	for(i := 0; i < len s; i++)
		if(s[i] < '0' || s[i] > '9')
			return 0;
	return 1;
}


filck(fname: string, Top: int): int
{
	(ok, dir) := sys->stat(fname);

	if(ok >= 0) {
		ok = 0;
		case Top {
		Topr =>	# readable
			ok = permck(dir, 8r004);
		Topw =>	# writable
			ok = permck(dir, 8r002);
		Topx =>	# executable
			ok = permck(dir, 8r001);
		Tope =>	# exists
			ok = 1;
		Topf =>	# is a regular file
			ok = (dir.mode & Sys->DMDIR) == 0;
		Topd =>	# is a directory
			ok = (dir.mode & Sys->DMDIR) != 0;
		Tops =>	# has length > 0
			ok = dir.length > big 0;
		}
	}

	return ok > 0;
}

permck(dir: Sys->Dir, mask: int): int
{
	uid, gid: string;
	fd := sys->open("/dev/user", Sys->OREAD);
	if(fd != nil) {
		buf := array [28] of byte;
		n := sys->read(fd, buf, len buf);
		if(n > 0)
			uid = string buf[0:n];
	}
	# how do I find out what my group is?
	
	ok := dir.mode & mask<<0;
	if(!ok && dir.gid == gid)
		ok = dir.mode & mask<<3;
	if(!ok && dir.uid == uid)
		ok = dir.mode & mask<<6;

	return ok > 0;
}

isatty(fd: int): int
{
	d1, d2: Sys->Dir;

	ok: int;
	(ok, d1) = sys->fstat(sys->fildes(fd));
	if(ok < 0)
		return 0;
	(ok, d2) = sys->stat("/dev/cons");
	if(ok < 0)
		return 0;

	return d1.dtype==d2.dtype && d1.dev==d2.dev && d1.qid.path==d2.qid.path;
}
