implement Archfs;

include "sys.m";
	sys: Sys;
include "draw.m";

include "bufio.m";
	bufio: Bufio;

include "string.m";
	str: String;

include "daytime.m";
	daytime: Daytime;

include "styx.m";
	styx: Styx;
	NOFID: import Styx;

include "arg.m";

Archfs: module
{
	init:	fn(nil: ref Draw->Context, nil: list of string);
};

Ahdr: adt {
	name: string;
	modestr: string;
	d: ref Sys->Dir;
};

Archive: adt {
	b: ref Bufio->Iobuf;
	nexthdr: big;
	canseek: int;
	hdr: ref Ahdr;
	err: string;
};

Iobuf: import bufio;
Tmsg, Rmsg: import styx;

Einuse		: con "fid already in use";
Ebadfid		: con "bad fid";
Eopen		: con "fid already opened";
Enotfound	: con "file does not exist";
Enotdir		: con "not a directory";
Eperm		: con "permission denied";

UID: con "inferno";
GID: con "inferno";

debug := 0;

Dir: adt {
	dir: Sys->Dir;
	offset: big;
	parent: cyclic ref Dir;
	child: cyclic ref Dir;
	sibling: cyclic ref Dir;
};

Fid: adt {
	fid:	int;
	open:	int;
	dir:	ref Dir;
};

HTSZ: con 32;
fidtab := array[HTSZ] of list of ref Fid;

root: ref Dir;
qid: int;
mtpt := "/mnt/arch";
bio: ref Iobuf;
buf: array of byte;
skip := 0;

init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	bufio = load Bufio Bufio->PATH;
	str = load String String->PATH;
	daytime = load Daytime Daytime->PATH;
	styx = load Styx Styx->PATH;
	if(bufio == nil || styx == nil || daytime == nil || str == nil)
		fatal("failed to load modules");
	styx->init();

	flags := Sys->MREPL;
	arg := load Arg Arg->PATH;
	if(arg == nil)
		fatal("failed to load "+Arg->PATH);
	arg->init(args);
	arg->setusage("archfs [-ab] [-m mntpt] archive [prefix ...]");
	while((c := arg->opt()) != 0){
		case c {
		'D' =>
			debug = 1;
		'a' =>
			flags = Sys->MAFTER;
		'b' =>
			flags = Sys->MBEFORE;
		'm' =>
			mtpt = arg->earg();
		's' =>
			skip = 1;
		* =>
			arg->usage();
		}
	}
	args = arg->argv();
	if(args == nil)
		arg->usage();
	arg = nil;

	buf = array[Sys->ATOMICIO] of byte;
	# root = newdir("/", UID, GID, 8r755|Sys->DMDIR, daytime->now());
	root = newdir(basename(mtpt), UID, GID, 8r555|Sys->DMDIR, daytime->now());
	root.parent = root;
	readarch(hd args, tl args);
	p := array[2] of ref Sys->FD;
	if(sys->pipe(p) < 0)
		fatal("can't create pipe");
	pidch := chan of int;
	spawn serve(p[1], pidch);
	pid := <- pidch;
	if(sys->mount(p[0], nil, mtpt, flags, nil) < 0)
		fatal(sys->sprint("cannot mount archive on %s: %r", mtpt));
}

reply(fd: ref Sys->FD, m: ref Rmsg): int
{
	if(debug)
		sys->fprint(sys->fildes(2), "-> %s\n", m.text());
	s := m.pack();
	if(s == nil)
		return -1;
	return sys->write(fd, s, len s);
}

error(fd: ref Sys->FD, m: ref Tmsg, e: string)
{
	reply(fd, ref Rmsg.Error(m.tag, e));
}

serve(fd: ref Sys->FD, pidch: chan of int)
{
	e: string;
	f: ref Fid;

	pidch <-= sys->pctl(Sys->NEWNS|Sys->NEWFD, 1 :: 2 :: fd.fd :: bio.fd.fd :: nil);
	bio.fd = sys->fildes(bio.fd.fd);
	fd = sys->fildes(fd.fd);
Work:
	while((m0 := Tmsg.read(fd, Styx->MAXRPC)) != nil){
		if(debug)
			sys->fprint(sys->fildes(2), "<- %s\n", m0.text());
		pick m := m0 {
		Readerror =>
			fatal("read error on styx server");
		Version =>
			(s, v) := styx->compatible(m, Styx->MAXRPC, Styx->VERSION);
			reply(fd, ref Rmsg.Version(m.tag, s, v));
		Auth =>
			error(fd, m, "authentication not required");
		Flush =>
			reply(fd, ref Rmsg.Flush(m.tag));
		Walk =>
			(f, e) = mapfid(m.fid);
			if(e != nil){
				error(fd, m, e);
				continue;
			}
			if(f.open){
				error(fd, m, Eopen);
				continue;
			}
			dir := f.dir;
			nq := 0;
			nn := len m.names;
			qids := array[nn] of Sys->Qid;
			if(nn > 0){
				for(k := 0; k < nn; k++){
					if((dir.dir.mode & Sys->DMDIR) == 0){
						if(k == 0){
							error(fd, m, Enotdir);
							continue Work;
						}
						break;
					}
					dir  = lookup(dir, m.names[k]);
					if(dir == nil){
						if(k == 0){
							error(fd, m, Enotfound);
							continue Work;
						}
						break;
					}
					qids[nq++] = dir.dir.qid;
				}
			}
			if(nq < nn)
				qids = qids[0: nq];
			if(nq == nn){
				if(m.newfid != m.fid){
					f = newfid(m.newfid);
					if(f == nil){
						error(fd, m, Einuse);
						continue Work;
					}
				}
				f.dir = dir;
			}
			reply(fd, ref Rmsg.Walk(m.tag, qids));
		Open =>
			(f, e) = mapfid(m.fid);
			if(e != nil){
				error(fd, m, e);
				continue;
			}
			if(m.mode != Sys->OREAD){
				error(fd, m, Eperm);
				continue;
			}
			f.open = 1;
			reply(fd, ref Rmsg.Open(m.tag, f.dir.dir.qid, Styx->MAXFDATA));
		Create =>
			error(fd, m, Eperm);
		Read =>
			(f, e) = mapfid(m.fid);
			if(e != nil){
				error(fd, m, e);
				continue;
			}
			data := read(f.dir, m.offset, m.count);
			reply(fd, ref Rmsg.Read(m.tag, data));
		Write =>
			error(fd, m, Eperm);				
		Clunk =>
			(f, e) = mapfid(m.fid);
			if(e != nil){
				error(fd, m, e);
				continue;
			}
			freefid(f);
			reply(fd, ref Rmsg.Clunk(m.tag));
		Stat =>
			(f, e) = mapfid(m.fid);
			if(e != nil){
				error(fd, m, e);
				continue;
			}
			reply(fd, ref Rmsg.Stat(m.tag, f.dir.dir));
		Remove =>
			error(fd, m, Eperm);
		Wstat =>
			error(fd, m, Eperm);
		Attach =>
			f = newfid(m.fid);
			if(f == nil){
				error(fd, m, Einuse);
				continue;
			}
			f.dir = root;
			reply(fd, ref Rmsg.Attach(m.tag, f.dir.dir.qid));
		* =>
			fatal("unknown styx message");
		}
	}
}

newfid(fid: int): ref Fid
{
	if(fid == NOFID)
		return nil;
	hv := hashval(fid);
	ff: ref Fid;
	for(l := fidtab[hv]; l != nil; l = tl l){
		f := hd l;
		if(f.fid == fid)
			return nil;
		if(ff == nil && f.fid == NOFID)
			ff = f;
	}
	if((f := ff) == nil){
		f = ref Fid;
		fidtab[hv] = f :: fidtab[hv];
	}
	f.fid = fid;
	f.open = 0;
	return f;
}

freefid(f: ref Fid)
{
	hv := hashval(f.fid);
	for(l := fidtab[hv]; l != nil; l = tl l)
		if(hd l == f){
			f.fid = NOFID;
			f.dir = nil;
			f.open = 0;
			return;
		}
	fatal("cannot find fid");
}
	
mapfid(fid: int): (ref Fid, string)
{
	if(fid == NOFID)
		return (nil, Ebadfid);
	hv := hashval(fid);
	for(l := fidtab[hv]; l != nil; l = tl l){
		f := hd l;
		if(f.fid == fid){
			if(f.dir == nil)
				return (nil, Enotfound);
			return (f, nil);
		}
	}
	return (nil, Ebadfid);
}

hashval(n: int): int
{
	n %= HTSZ;
	if(n < 0)
		n += HTSZ;
	return n;
}

readarch(f: string, args: list of string)
{
	ar := openarch(f);
	if(ar == nil || ar.b == nil)
		fatal(sys->sprint("cannot open %s: %r", f));
	bio = ar.b;
	while((a := gethdr(ar)) != nil){
		if(args != nil){
			if(!selected(a.name, args)){
				if(skip)
					return;
				#drain(ar, int a.d.length);
				continue;
			}
			mkdirs("/", a.name);
		}
		d := mkdir(a.name, a.d.mode, a.d.mtime, a.d.uid, a.d.gid, 0);
		if((a.d.mode & Sys->DMDIR) == 0){
			d.dir.length = a.d.length;
			d.offset = bio.offset();
		}
		#drain(ar, int a.d.length);
	}
	if(ar.err != nil)
		fatal(ar.err);
}

selected(s: string, args: list of string): int
{
	for(; args != nil; args = tl args)
		if(fileprefix(hd args, s))
			return 1;
	return 0;
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

basename(f: string): string
{
	for(i := len f; i > 0; ) 
		if(f[--i] == '/')
			return f[i+1:];
	return f;
}

split(p: string): (string, string)
{
	if(p == nil)
		fatal("nil string in split");
	if(p[0] != '/')
		fatal("p0 not / in split");
	while(p[0] == '/')
		p = p[1:];
	i := 0;
	while(i < len p && p[i] != '/')
		i++;
	if(i == len p)
		return (p, nil);
	else
		return (p[0:i], p[i:]);
}

mkdirs(basedir, name: string)
{
	(nil, names) := sys->tokenize(name, "/");
	while(names != nil){
		# sys->print("mkdir %s\n", basedir);
		mkdir(basedir, 8r775|Sys->DMDIR, daytime->now(), UID, GID, 1);
		if(tl names == nil)
			break;
		basedir = basedir + "/" + hd names;
		names = tl names;
	}
}

read(d: ref Dir, offset: big, n: int): array of byte
{
	if(d.dir.mode & Sys->DMDIR)
		return readdir(d, int offset, n);
	return readfile(d, offset, n);
}
	
readdir(d: ref Dir, o: int, n: int): array of byte
{
	k := 0;
	m := 0;
	b := array[n] of byte;
	for(s := d.child; s != nil; s = s.sibling){
		l := styx->packdirsize(s.dir);
		if(k < o){
			k += l;
			continue;
		}
		if(m+l > n)
			break;
		b[m: ] = styx->packdir(s.dir);
		m += l;
	}
	return b[0: m];
}

readfile(d: ref Dir, offset: big, n: int): array of byte
{
	if(offset+big n > d.dir.length)
		n = int(d.dir.length-offset);
	if(n <= 0 || offset < big 0)
		return nil;
	bio.seek(d.offset+offset, Bufio->SEEKSTART);
	a := array[n] of byte;
	p := 0;
	m := 0;
	for( ; n != 0; n -= m){
		l := len buf;
		if(n < l)
			l = n;
		m = bio.read(buf, l);
		if(m <= 0 || m != l)
			fatal("premature eof");
		a[p:] = buf[0:m];
		p += m;
	}
	return a;
}

mkdir(f: string, mode: int, mtime: int, uid: string, gid: string, existsok: int): ref Dir
{
	if(f == "/")
		return nil;
	d := newdir(basename(f), uid, gid, mode, mtime);
	addfile(d, f, existsok);
	return d;
}

addfile(d: ref Dir, path: string, existsok: int)
{
	elem: string;

	opath := path;
	p := prev := root;
	basedir := "";
# sys->print("addfile %s: %s\n", d.dir.name, path);
	while(path != nil){
		(elem, path) = split(path);
		basedir += "/" + elem;
		op := p;
		p = lookup(p, elem);
		if(path == nil){
			if(p != nil){
				if(!existsok && (p.dir.mode&Sys->DMDIR) == 0)
					sys->fprint(sys->fildes(2), "addfile: %s already there", opath);
					# fatal(sys->sprint("addfile: %s already there", opath));
				return;
			}
			if(prev.child == nil)
				prev.child = d;
			else {
				for(s := prev.child; s.sibling != nil; s = s.sibling)
					;
				s.sibling = d;
			}
			d.parent = prev;
		}
		else {
			if(p == nil){
				mkdir(basedir, 8r775|Sys->DMDIR, daytime->now(), UID, GID, 1);
				p = lookup(op, elem);
				if(p == nil)
					fatal("bad file system");
			}
		}
		prev = p;
	}
}

lookup(p: ref Dir, f: string): ref Dir
{
	if((p.dir.mode&Sys->DMDIR) == 0) 
		fatal("not a directory in lookup");
	if(f == ".")
		return p;
	if(f == "..")
		return p.parent;
	for(d := p.child; d != nil; d = d.sibling)
		if(d.dir.name == f)
			return d;
	return nil;
}

newdir(name, uid, gid: string, mode, mtime: int): ref Dir
{
	dir := sys->zerodir;
	dir.name = name;
	dir.uid = uid;
	dir.gid = gid;
	dir.mode = mode;
	dir.qid.path = big (qid++);
	dir.qid.qtype = mode>>24;
	dir.qid.vers = 0;
	dir.atime = dir.mtime = mtime;
	dir.length = big 0;

	d := ref Dir;
	d.dir = dir;
	d.offset = big 0;
	return d;
}

prd(d: ref Dir)
{
	dir := d.dir;
	sys->print("%q %q %q %bx %x %x %d %d %bd %d %d %bd\n",
		dir.name, dir.uid, dir.gid, dir.qid.path, dir.qid.vers, dir.mode, dir.atime, dir.mtime, dir.length, dir.dtype, dir.dev, d.offset);
}

fatal(e: string)
{
	sys->fprint(sys->fildes(2), "archfs: %s\n", e);
	raise "fail:error";
}

openarch(file: string): ref Archive
{
	b := bufio->open(file, Bufio->OREAD);
	if(b == nil)
		return nil;
	ar := ref Archive;
	ar.b = b;
	ar.nexthdr = big 0;
	ar.canseek = 1;
	ar.hdr = ref Ahdr;
	ar.hdr.d = ref Sys->Dir;
	return ar;
}

NFLDS: con 6;

gethdr(ar: ref Archive): ref Ahdr
{
	a := ar.hdr;
	b := ar.b;
	m := b.offset();
	n := ar.nexthdr;
	if(m != n){
		if(ar.canseek)
			b.seek(n, Bufio->SEEKSTART);
		else {
			if(m > n)
				fatal(sys->sprint("bad offset in gethdr: m=%bd n=%bd", m, n));
			if(drain(ar, int(n-m)) < 0)
				return nil;
		}
	}
	if((s := b.gets('\n')) == nil){
		ar.err = "premature end of archive";
		return nil;
	}
	if(s == "end of archive\n")
		return nil;
	(nf, fs) := sys->tokenize(s, " \t\n");
	if(nf != NFLDS){
		ar.err = "too few fields in file header";
		return nil;
	}
	a.name = hd fs;						fs = tl fs;
	(a.d.mode, nil) = str->toint(hd fs, 8);		fs = tl fs;
	a.d.uid = hd fs;						fs = tl fs;
	a.d.gid = hd fs;						fs = tl fs;
	(a.d.mtime, nil) = str->toint(hd fs, 10);	fs = tl fs;
	(tmp, nil) := str->toint(hd fs, 10);		fs = tl fs;
	a.d.length = big tmp;
	ar.nexthdr = b.offset()+a.d.length;
	return a;
}

drain(ar: ref Archive, n: int): int
{
	while(n > 0){
		m := n;
		if(m > len buf)
			m = len buf;
		p := ar.b.read(buf, m);
		if(p != m){
			ar.err = "unexpectedly short read";
			return -1;
		}
		n -= m;
	}
	return 0;	
}
