implement Inst;

include "sys.m";
	sys: Sys;
	Dir, sprint, fprint: import sys;
include "draw.m";
include "bufio.m";
	bufio: Bufio;
	Iobuf: import bufio;
include "string.m";
	str: String;
include "arg.m";
	arg: Arg;
include "keyring.m";
	keyring : Keyring;
include "arch.m";
	arch : Arch;
include "wrap.m";
	wrap : Wrap;

Inst: module
{
	init:	fn(nil: ref Draw->Context, nil: list of string);
};

LEN: con Sys->ATOMICIO;

tflag := 0;
uflag := 0;
hflag := 0;
vflag := 0;
fflag := 1;
stderr: ref Sys->FD;
bout: ref Iobuf;
argv0 := "inst";
oldw, w : ref Wrap->Wrapped;
root := "/";
force := 0;
stoponerr := 1;

# membogus(argv: list of string)
# {
#
# }

init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	stderr = sys->fildes(2);
	bufio = load Bufio Bufio->PATH;
	if(bufio == nil)
		error(sys->sprint("cannot load %s: %r\n", Bufio->PATH));

	str = load String String->PATH;
	if(str == nil)
		error(sys->sprint("cannot load %s: %r\n", String->PATH));

	arg = load Arg Arg->PATH;
	if(arg == nil)
		error(sys->sprint("cannot load %s: %r\n", Arg->PATH));
	keyring = load Keyring Keyring->PATH;
	if(keyring == nil)
		error(sys->sprint("cannot load %s: %r\n", Keyring->PATH));
	arch = load Arch Arch->PATH;
	if(arch == nil)
		error(sys->sprint("cannot load %s: %r\n", Arch->PATH));
	arch->init(bufio);
	wrap = load Wrap Wrap->PATH;
	if(wrap == nil)
		error(sys->sprint("cannot load %s: %r\n", Wrap->PATH));
	wrap->init(bufio);
	arg->init(args);
	while((c := arg->opt()) != 0)
		case c {
		'f' =>
			fflag = 0;
		'h' =>
			hflag = 1;
			bout = bufio->fopen(sys->fildes(1), Sys->OWRITE);
			if(bout == nil)
				error(sys->sprint("can't access standard output: %r"));
		't' =>
			tflag = 1;
		'u' =>
			uflag = 1;
		'v' =>
			vflag = 1;
		'r' =>
			root = arg->arg();
			if (root == nil)
				fatal("root missing");
		'F' =>
			force = 1;
		'c' =>
			stoponerr = 0;
		* =>
			usage();
		}
	args = arg->argv();
	if (args == nil)
		usage();
	ar := arch->openarch(hd args);
	if(ar == nil || ar.b == nil)
		error(sys->sprint("can't access %s: %r", hd args));
	w = wrap->openwraphdr(hd args, root, nil, 0);
	if (w == nil)
		fatal("no such package found");
	if(w.nu != 1)
		fatal("strange package: more than one piece");
	if (force == 0)
		oldw = wrap->openwrap(w.name, root, 0);
	if (force == 0 && w.u[0].utime && (oldw == nil || oldw.tfull < w.u[0].utime)){
		tfull: int;
		if(oldw == nil)
			tfull = -1;
		else
			tfull = oldw.tfull;
		fatal(sys->sprint("need %s version of %s already installed (pkg %d)", wrap->now2string(w.u[0].utime, 0), w.name, tfull));
	}
	args = tl args;
	digest := array[Keyring->MD5dlen] of byte;
	digest0 := array[Keyring->MD5dlen] of byte;
	digest1 := array[Keyring->MD5dlen] of byte;

	while ((a := arch->gethdr(ar)) != nil) {
		why := "";
		docopy := 0;
		if(force)
			docopy = 1;
		else if(a.d.mode & Sys->DMDIR)
			docopy = 1;
		else if(wrap->md5file(root+a.name, digest) < 0)
			docopy = 1;
		else{
			wrap->md5filea(root+a.name, digest1);
			(ok, t) := wrap->getfileinfo(oldw, a.name, digest, nil, digest1);
			if (ok >= 0) {
				if(t > w.u[0].time){
					docopy = 0;
					why = "version from newer package exists";
				}
				else
					docopy = 1;
			}
			else {
				(ok, t) = wrap->getfileinfo(oldw, a.name, nil, nil, nil);
				if(ok >= 0){
					docopy = 0;
					why = "locally modified";
				}
				else{
					docopy = 0;
					why = "locally created";
				}
			}
		}
		if(!docopy){
			wrap->md5sum(ar.b, digest0, int a.d.length);
			if(wrap->memcmp(digest, digest0, Keyring->MD5dlen))
				skipfile(a.name, why);
			continue;
		}
		if(args != nil){
			if(!selected(a.name, args)){
				arch->drain(ar, int a.d.length);
				continue;
			}
			if (!hflag)
				mkdirs(root, a.name);
		}
		name := pathcat(root, a.name);
		if(hflag){
			bout.puts(sys->sprint("%s %uo %s %s %ud %d\n",
				name, a.d.mode, a.d.uid, a.d.gid, a.d.mtime, int a.d.length));
			arch->drain(ar, int a.d.length);
			continue;
		}
		if(a.d.mode & Sys->DMDIR)
			mkdir(name, a.d);
		else
			extract(ar, name, a.d);
	}
	arch->closearch(ar);
	if(ar.err == nil){
		# fprint(stderr, "done\n");
		quit(nil);
	}
	else {
		fprint(stderr, "%s\n", ar.err);
		quit("eof");
	}
}

skipfile(f : string, why : string)
{
	sys->fprint(stderr, "skipping %s: %s\n", f, why);
}

skiprmfile(f: string, why: string)
{
	sys->fprint(stderr, "not removing %s: %s\n", f, why);
}

doremove(s : string)
{
	p := pathcat(root, s);
	digest := array[Keyring->MD5dlen] of { * => byte 0 };
	digest1 := array[Keyring->MD5dlen] of { * => byte 0 };
	if(wrap->md5file(p, digest) < 0)
		;
	else{
		wrap->md5filea(p, digest1);
		(ok, nil) := wrap->getfileinfo(oldw, s, digest, nil, digest1);
		if(force == 0 && ok < 0)
			skiprmfile(p, "locally modified");
		else{
			if (vflag)
				sys->print("rm %s\n", p);
			remove(p);
		}
	}
}

quit(s: string)
{
	if (s == nil) {
		p := w.u[0].dir + "/remove";
		if ((b := bufio->open(p, Bufio->OREAD)) != nil) {
			while ((t := b.gets('\n')) != nil) {
				lt := len t;
				if (t[lt-1] == '\n')
					t = t[0:lt-1];
				doremove(t);
			}
		}
	}
	if(bout != nil)
		bout.flush();
	if(wrap != nil)
		wrap->end();
	if(s != nil)
		raise "fail: "+s;
	else
		fprint(stderr, "done\n");
	exit;
}

fileprefix(prefix, s: string): int
{
	n := len prefix;
	m := len s;
	if(n > m || !str->prefix(prefix, s))
		return 0;
	if(m > n && s[n] != '/')
		return 0;
	return 1;
}

selected(s: string, args: list of string): int
{
	for(; args != nil; args = tl args)
		if(fileprefix(hd args, s))
			return 1;
	return 0;
}

mkdirs(basedir, name: string)
{
	(nil, names) := sys->tokenize(name, "/");
	while(names != nil) {
		create(basedir, Sys->OREAD, 8r775|Sys->DMDIR);
		if(tl names == nil)
			break;
		basedir = basedir + "/" + hd names;
		names = tl names;
	}
}

mkdir(name: string, dir : ref Sys->Dir)
{
	d: Dir;
	i: int;

	if(vflag) {
		MTPT : con "/n/remote";
		s := name;
		if (len name >= len MTPT && name[0:len MTPT] == MTPT)
			s = name[len MTPT:];
		sys->print("installing directory %s\n", s);
	}
	fd := create(name, Sys->OREAD, dir.mode);
	if(fd == nil) {
		err := sys->sprint("%r");
		(i, d) = sys->stat(name);
		if(i < 0 || !(d.mode & Sys->DMDIR)){
			werr(sys->sprint("can't make directory %s: %s", name, err));
			return;
		}
	}
	else {
		(i, d) = sys->fstat(fd);
		if(i < 0)
			warn(sys->sprint("can't stat %s: %r", name));
		fd = nil;
	}
	d = sys->nulldir;
	(nil, p) := str->splitr(name, "/");
	if(p == nil)
		p = name;
	d.name = p;
	d.mode = dir.mode;
	if(tflag || uflag)
		d.mtime = dir.mtime;
	if(uflag){
		d.uid = dir.uid;
		d.gid = dir.gid;
	}
	fd = nil;
	if(sys->wstat(name, d) < 0){
		e := sys->sprint("%r");
		if(wstat(name, d) < 0)
			warn(sys->sprint("can't set modes for %s: %s", name, e));
	}
	if(uflag){
		(i, d) = sys->stat(name);
		if(i < 0)
			warn(sys->sprint("can't reread modes for %s: %r", name));
		if(dir.uid != d.uid)
			warn(sys->sprint("%s: uid mismatch %s %s", name, dir.uid, d.uid));
		if(dir.gid != d.gid)
			warn(sys->sprint("%s: gid mismatch %s %s", name, dir.gid, d.gid));
	}
}

extract(ar : ref Arch->Archive, name: string, dir : ref Sys->Dir)
{
	sfd := create(name, Sys->OWRITE, dir.mode);
	if(sfd == nil) {
		if(!fflag || remove(name) == -1 ||
		    (sfd = create(name, Sys->OWRITE, dir.mode)) == nil) {
			werr(sys->sprint("can't make file %s: %r", name));
			arch->drain(ar, int dir.length);
			return;
		}
	}
	b := bufio->fopen(sfd, Bufio->OWRITE);
	if (b == nil) {
		warn(sys->sprint("can't open file %s for bufio : %r", name));
		arch->drain(ar, int dir.length);
		return;
	}
	err := arch->getfile(ar, b, int dir.length);
	if (err != nil) {
		if (len err >= 9 && err[0:9] == "premature")
			fatal(err);
		else
			warn(err);
	}
	(i, d) := sys->fstat(b.fd);
	if(i < 0)
		warn(sys->sprint("can't stat %s: %r", name));
	d = sys->nulldir;
	(nil, p) := str->splitr(name, "/");
	if(p == nil)
		p = name;
	d.name = p;
	d.mode = dir.mode;
	if(tflag || uflag)
		d.mtime = dir.mtime;
	if(uflag){
		d.uid = dir.uid;
		d.gid = dir.gid;
	}
	if(b.flush() == Bufio->ERROR)
		werr(sys->sprint("error writing %s: %r", name));
	b.close();
	sfd = nil;
	if(sys->wstat(name, d) < 0){
		e := sys->sprint("%r");
		if(wstat(name, d) < 0)
			warn(sys->sprint("can't set modes for %s: %s", name, e));
	}
	if(uflag){
		(i, d) = sys->stat(name);
		if(i < 0)
			warn(sys->sprint("can't reread modes for %s: %r", name));
		if(d.uid != dir.uid)
			warn(sys->sprint("%s: uid mismatch %s %s", name, dir.uid, d.uid));
		if(d.gid != dir.gid)
			warn(sys->sprint("%s: gid mismatch %s %s", name, dir.gid, d.gid));
	}
}

error(s: string)
{
	fprint(stderr, "%s: %s\n", argv0, s);
	quit("error");
}

werr(s: string)
{
	fprint(stderr, "%s: %s\n", argv0, s);
	if(stoponerr)
		quit("werr");
}
	
warn(s: string)
{
	fprint(stderr, "%s: %s\n", argv0, s);
}

usage()
{
	fprint(stderr, "Usage: inst [-h] [-u] [-v] [-f] [-c] [-F] [-r dest-root] [file ...]\n");
	raise "fail: usage";
}

fatal(s : string)
{
	sys->fprint(stderr, "inst: %s\n", s);
	if(wrap != nil)
		wrap->end();
	exit;
}

parent(name : string) : string
{
	slash := -1;
	for (i := 0; i < len name; i++)
		if (name[i] == '/')
			slash = i;
	if (slash > 0)
		return name[0:slash];
	return "/";
}

create(name : string, rw : int, mode : int) : ref Sys->FD
{
	fd := sys->create(name, rw, mode);
	if (fd == nil) {
		p := parent(name);
		(ok, d) := sys->stat(p);
		if (ok < 0)
			return nil;
		omode := d.mode;
		d = sys->nulldir;
		d.mode = omode | 8r222;	# ensure parent is writable
		sys->wstat(p, d);
		fd = sys->create(name, rw, mode);
		d.mode = omode;
		sys->wstat(p, d);
	}
	return fd;
}

remove(name : string) : int
{
	if (sys->remove(name) < 0) {
		(ok, d) := sys->stat(name);
		if (ok < 0)
			return -1;
		omode := d.mode;
		d.mode |= 8r222;
		sys->wstat(name, d);
		if (sys->remove(name) >= 0)
			return 0;
		d.mode = omode;
		sys->wstat(name, d);
		return -1;
	}
	return 0;
}

wstat(name : string, d : Dir) : int
{
	(ok, dir) := sys->stat(name);
	if (ok < 0)
		return -1;
	omode := dir.mode;
	dir.mode |= 8r222;
	sys->wstat(name, dir);
	if (sys->wstat(name, d) >= 0)
		return 0;
	dir.mode = omode;
	sys->wstat(name, dir);
	return -1;
}

pathcat(s : string, t : string) : string
{
	if (s == nil) return t;
	if (t == nil) return s;
	slashs := s[len s - 1] == '/';
	slasht := t[0] == '/';
	if (slashs && slasht)
		return s + t[1:];
	if (!slashs && !slasht)
		return s + "/" + t;
	return s + t;
}
