implement Fcp;

include "sys.m";
	sys: Sys;
include "draw.m";
include "arg.m";
include "readdir.m";
	readdir: Readdir;

Fcp: module
{
	init:	fn(nil: ref Draw->Context, argv: list of string);
};

stderr: ref Sys->FD;
errors := 0;

fdc: chan of (ref Sys->FD, ref Sys->FD);

init(nil: ref Draw->Context, argv: list of string)
{
	sys = load Sys Sys->PATH;
	stderr = sys->fildes(2);

	arg := load Arg Arg->PATH;
	if (arg == nil) {
		sys->fprint(stderr, "fcp: cannot load %s: %r\n", Arg->PATH);
		raise "fail:bad module";
	}
	recursive := 0;
	nreaders := nwriters := 8;
	arg->init(argv);
	arg->setusage("\tfcp [-r] [-R nproc] [-W nproc] src target\n\tfcp [-r] [-R nproc] [-W nproc] src ... directory");
	while ((opt := arg->opt()) != 0) {
		case opt {
		'R' =>
			nreaders = int arg->earg();
		'W' =>
			nwriters = int arg->earg();
		'r' =>
			recursive = 1;
		* =>
			arg->usage();
		}
	}
	if(nreaders < 1 || nwriters < 1)
		arg->usage();
	if(nreaders > 1 || nwriters > 1){
		fdc = chan of (ref Sys->FD, ref Sys->FD);
		spawn mstream(fdc, Sys->ATOMICIO, nreaders, nwriters);
	}
	argv = arg->argv();
	argc := len argv;
	if (argc < 2)
		arg->usage();
	arg = nil;

	dst: string;
	for (t := argv; t != nil; t = tl t)
		dst = hd t;

	(ok, dir) := sys->stat(dst);
	todir := (ok != -1 && (dir.mode & Sys->DMDIR));
	if (argc > 2 && !todir) {
		sys->fprint(stderr, "fcp: %s  not a directory\n", dst);
		raise "fail:error";
	}
	if (recursive)
		cpdir(argv, dst);
	else {
		for (; tl argv != nil; argv = tl argv) {
			if (todir)
				cp(hd argv, dst, basename(hd argv));
			else
				cp(hd argv, dst, nil);
		}
	}
	if(fdc != nil)
		fdc <-= (nil, nil);
	if (errors)
		raise "fail:error";
}

basename(s: string): string
{
	for ((nil, ls) := sys->tokenize(s, "/"); ls != nil; ls = tl ls)
		s = hd ls;
	return s;
}

cp(src, dst: string, newname: string)
{
	ok: int;
	ds, dd: Sys->Dir;

	if (newname != nil)
		dst += "/" + newname;
	(ok, ds) = sys->stat(src);
	if (ok < 0) {
		warning(sys->sprint("%s: %r", src));
		return;
	}
	if (ds.mode & Sys->DMDIR) {
		warning(src + " is a directory");
		return;
	}
	(ok, dd) = sys->stat(dst);
	if (ok != -1 &&
			ds.qid.path == dd.qid.path &&
			ds.dev == dd.dev &&
			ds.dtype == dd.dtype) {
		warning(src + " and " + dst + " are the same file");
		return;
	}
	sfd := sys->open(src, sys->OREAD);
	if (sfd == nil) {
		warning(sys->sprint("cannot open %s: %r", src));
		return;
	}
	dfd := sys->create(dst, sys->OWRITE, ds.mode);
	if (dfd == nil) {
		warning(sys->sprint("cannot create %s: %r", dst));
		return;
	}
	copy(sfd, dfd, src, dst);
}

mkdir(d: string, mode: int): int
{
	dfd := sys->create(d, sys->OREAD, sys->DMDIR | mode);
	if (dfd == nil) {
		warning(sys->sprint("cannot make directory %s: %r", d));
		return -1;
	}
	return 0;
}

copy(sfd, dfd: ref Sys->FD, src, dst: string): int
{
	if(fdc != nil){
		fdc <-= (sfd, dfd);
		return 0;
	}
	buf := array[Sys->ATOMICIO] of byte;
	for (;;) {
		r := sys->read(sfd, buf, Sys->ATOMICIO);
		if (r < 0) {
			warning(sys->sprint("error reading %s: %r", src));
			return -1;
		}
		if (r == 0)
			return 0;
		if (sys->write(dfd, buf, r) != r) {
			warning(sys->sprint("error writing %s: %r", dst));
			return -1;
		}
	}
}

cpdir(argv: list of string, dst: string)
{
	readdir = load Readdir Readdir->PATH;
	if (readdir == nil) {
		sys->fprint(stderr, "fcp: cannot load %s: %r\n", Readdir->PATH);
		raise "fail:bad module";
	}
	cache = array[NCACHE] of list of ref Sys->Dir;
	dexists := 0;
	(ok, dd) := sys->stat(dst);
	 # destination file exists
	if (ok != -1) {
		if ((dd.mode & Sys->DMDIR) == 0) {
			warning(dst + ": destination not a directory");
			return;
		}
		dexists = 1;
	}
	for (; tl argv != nil; argv = tl argv) {
		ds: Sys->Dir;
		src := hd argv;
		(ok, ds) = sys->stat(src);
		if (ok < 0) {
			warning(sys->sprint("can't stat %s: %r", src));
			continue;
		}
		if ((ds.mode & Sys->DMDIR) == 0) {
			cp(hd argv, dst, basename(hd argv));
		} else if (dexists) {
			if (ds.qid.path==dd.qid.path &&
					ds.dev==dd.dev &&
					ds.dtype==dd.dtype) {
				warning("cannot copy " + src + " into itself");
				continue;
			}
			copydir(src, dst + "/" + basename(src), ds.mode);
		} else {
			copydir(src, dst, ds.mode);
		}
	}
}

copydir(src, dst: string, srcmode: int)
{
	(ok, nil) := sys->stat(dst);
	if (ok != -1) {
		warning("cannot copy " + src + " onto another directory");
		return;
	}
	tmode := srcmode | 8r777;	# Fix for Nt
	if (mkdir(dst, tmode) == -1)
		return;
	(entries, n) := readdir->init(src, Readdir->COMPACT);
	for (i := 0; i < n; i++) {
		e := entries[i];
		path := src + "/" + e.name;
		if ((e.mode & Sys->DMDIR) == 0)
			cp(path, dst, e.name);
		else if (seen(e))
			warning(path + ": directory loop found");
		else
			copydir(path, dst + "/" + e.name, e.mode);
	}
	chmod(dst, srcmode);
}

# Avoid loops in tangled namespaces. (from du.b)
NCACHE: con 64; # must be power of two
cache: array of list of ref sys->Dir;

seen(dir: ref sys->Dir): int
{
	savlist := cache[int dir.qid.path&(NCACHE-1)];
	for(c := savlist; c!=nil; c = tl c){
		sav := hd c;
		if(dir.qid.path==sav.qid.path &&
			dir.dtype==sav.dtype && dir.dev==sav.dev)
			return 1;
	}
	cache[int dir.qid.path&(NCACHE-1)] = dir :: savlist;
	return 0;
}

warning(e: string)
{
	sys->fprint(stderr, "fcp: %s\n", e);
	errors++;
}

chmod(s: string, mode: int): int
{
	(ok, d) := sys->stat(s);
	if (ok < 0)
		return -1;

	if(d.mode == mode)
		return 0;
	d = sys->nulldir;
	d.mode = mode;
	if (sys->wstat(s, d) < 0) {
		warning(sys->sprint("cannot wstat %s: %r", s));
		return -1;
	}
	return 0;
}

mstream(fdc: chan of (ref Sys->FD, ref Sys->FD), bufsize: int, nin, nout: int)
{
	inc := chan of (ref Sys->FD, big, int, ref Sys->FD);
	outc := chan of (ref Sys->FD, big, array of byte);
	for(i := 0; i < nin; i++)
		spawn readproc(inc, outc);
	for(i = 0; i < nout; i++)
		spawn writeproc(outc);
	while(((src, dst) := <-fdc).t0 != nil){
		(ok, stat) := sys->fstat(src);
		if(ok == -1)
			continue;
		tot := stat.length;
		o := big 0;
		while((n := tot - o) > big 0){
			if(n < big bufsize)
				inc <-= (src, o, int n, dst);
			else
				inc <-= (src, o, bufsize, dst);
			o += big bufsize;
		}
	}
	for(i = 0; i < nin; i++)
		inc <-= (nil, big 0, 0, nil);
	for(i = 0; i < nout; i++)
		outc <-= (nil, big 0, nil);
}

readproc(inc: chan of (ref Sys->FD, big, int, ref Sys->FD), outc: chan of (ref Sys->FD, big, array of byte))
{
	buf: array of byte;
	while(((src, o, nb, dst) := <-inc).t0 != nil){
		if(len buf < nb)
			buf = array[nb*2] of byte;
		n := sys->pread(src, buf, nb, o);
		if(n > 0){
			outc <-= (dst, o, buf[0:n]);
			buf = buf[n:];
		}
	}
}

writeproc(outc: chan of (ref Sys->FD, big, array of byte))
{
	while(((dst, o, buf) := <-outc).t0 != nil)
		sys->pwrite(dst, buf, len buf, o);
}
