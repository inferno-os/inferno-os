implement Cp;

include "sys.m";
	sys: Sys;

include "draw.m";
include "arg.m";

include "readdir.m";
	readdir: Readdir;

Cp: module
{
	init:	fn(nil: ref Draw->Context, args: list of string);
};

stderr: ref Sys->FD;
errors := 0;
gflag := 0;
uflag := 0;
xflag := 0;

init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	stderr = sys->fildes(2);

	arg := load Arg Arg->PATH;
	recursive := 0;
	arg->init(args);
	arg->setusage("\tcp [-gux] src target\n\tcp [-r] [-gux] src ... directory");
	while((opt := arg->opt()) != 0)
		case opt {
		'r' =>	recursive = 1;
		'g' => gflag = 1;
		'u' => uflag = gflag = 1;
		'x' => xflag = 1;
		* =>	arg->usage();
		}
	args = arg->argv();
	argc := len args;
	if(argc < 2)
		arg->usage();
	arg = nil;

	dst: string;
	for(t := args; t != nil; t = tl t)
		dst = hd t;

	(ok, dir) := sys->stat(dst);
	todir := (ok != -1 && (dir.mode & Sys->DMDIR));
	if(argc > 2 && !todir){
		sys->fprint(stderr, "cp: %s  not a directory\n", dst);
		raise "fail:error";
	}
	if(recursive)
		cpdir(args, dst);
	else{
		for(; tl args != nil; args = tl args){
			if(todir)
				cp(hd args, dst, basename(hd args));
			else
				cp(hd args, dst, nil);
		}
	}
	if(errors)
		raise "fail:error";
}

basename(s: string): string
{
	for((nil, ls) := sys->tokenize(s, "/"); ls != nil; ls = tl ls)
		s = hd ls;
	return s;
}

cp(src, dst: string, newname: string)
{
	dd: Sys->Dir;

	if(newname != nil)
		dst += "/" + newname;
	(ok, ds) := sys->stat(src);
	if(ok < 0){
		warning(sys->sprint("%s: %r", src));
		return;
	}
	if(ds.mode & Sys->DMDIR){
		warning(src + " is a directory");
		return;
	}
	(ok, dd) = sys->stat(dst);
	if(ok != -1 && samefile(ds, dd)){
		warning(src + " and " + dst + " are the same file");
		return;
	}
	sfd := sys->open(src, Sys->OREAD);
	if(sfd == nil){
		warning(sys->sprint("cannot open %s: %r", src));
		return;
	}
	dfd := sys->create(dst, Sys->OWRITE, ds.mode & 8r777);
	if(dfd == nil){
		warning(sys->sprint("cannot create %s: %r", dst));
		return;
	}
	if(copy(sfd, dfd, src, dst)!=0)
		return;
	if(wstat(dfd, ds, 0) < 0)
		warning(sys->sprint("can't wstat %s: %r", src));
}

copy(sfd, dfd: ref Sys->FD, src, dst: string): int
{
	buf := array[Sys->ATOMICIO] of byte;
	while((r := sys->read(sfd, buf, len buf)) > 0){
		if(sys->write(dfd, buf, r) != r){
			warning(sys->sprint("error writing %s: %r", dst));
			return -1;
		}
	}
	if(r < 0){
		warning(sys->sprint("error reading %s: %r", src));
		return -1;
	}
	return 0;
}

cpdir(args: list of string, dst: string)
{
	readdir = load Readdir Readdir->PATH;
	if(readdir == nil){
		sys->fprint(stderr, "cp: cannot load %s: %r\n", Readdir->PATH);
		raise "fail:bad module";
	}
	cache = array[NCACHE] of list of ref Sys->Dir;
	dexists := 0;
	(ok, dd) := sys->stat(dst);
	# destination file exists
	if(ok != -1){
		if((dd.mode & Sys->DMDIR) == 0){
			warning(dst + ": destination not a directory");
			return;
		}
		dexists = 1;
	}
	for(; tl args != nil; args = tl args){
		ds: Sys->Dir;
		src := hd args;
		(ok, ds) = sys->stat(src);
		if(ok < 0){
			warning(sys->sprint("can't stat %s: %r", src));
			continue;
		}
		if((ds.mode & Sys->DMDIR) == 0){
			cp(hd args, dst, basename(hd args));
		} else if(dexists){
			if(samefile(ds, dd)){
				warning("cannot copy " + src + " into itself");
				continue;
			}
			copydir(src, dst + "/" + basename(src), ds);
		} else
			copydir(src, dst, ds);
	}
}

copydir(src, dst: string, srcd: Sys->Dir)
{
	(ok, nil) := sys->stat(dst);
	if(ok != -1){
		warning("cannot copy " + src + " onto another directory");
		return;
	}
	tmode := srcd.mode | 8r777;	# Fix for Nt
	dfd := sys->create(dst, Sys->OREAD, Sys->DMDIR | tmode);
	if(dfd == nil){
		warning(sys->sprint("cannot make directory %s: %r", dst));
		return;
	}
	(entries, n) := readdir->init(src, Readdir->COMPACT);
	for(i := 0; i < n; i++){
		e := entries[i];
		path := src + "/" + e.name;
		if((e.mode & Sys->DMDIR) == 0)
			cp(path, dst, e.name);
		else if(seen(e))
			warning(path + ": directory loop found");
		else
			copydir(path, dst + "/" + e.name, *e);
	}
	if(wstat(dfd, srcd, 1) < 0)
		warning(sys->sprint("can't wstat %s: %r", dst));
}

wstat(dfd: ref Sys->FD, ds: Sys->Dir, mflag: int): int
{
	if(!xflag && !gflag && !uflag && !mflag)
		return 0;
	d := sys->nulldir;
	if(xflag)
		d.mtime = ds.mtime;
	if(xflag || mflag)
		d.mode = ds.mode;
	if(uflag)
		d.uid = ds.uid;
	if(gflag)
		d.gid = ds.gid;
	return sys->fwstat(dfd, d);
}

samefile(d1: Sys->Dir, d2: Sys->Dir): int
{
	return d1.dtype == d2.dtype && d1.dev == d2.dev &&
		d1.qid.qtype == d2.qid.qtype && d1.qid.path == d2.qid.path &&
		d1.qid.vers == d2.qid.vers;
}

# Avoid loops in tangled namespaces. (from du.b)
NCACHE: con 64; # must be power of two
cache: array of list of ref sys->Dir;

seen(dir: ref sys->Dir): int
{
	savlist := cache[int dir.qid.path&(NCACHE-1)];
	for(c := savlist; c!=nil; c = tl c)
		if(samefile(*dir, *hd c))
			return 1;
	cache[int dir.qid.path&(NCACHE-1)] = dir :: savlist;
	return 0;
}

warning(e: string)
{
	sys->fprint(stderr, "cp: %s\n", e);
	errors++;
}
