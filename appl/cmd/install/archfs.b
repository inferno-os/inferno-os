implement Archfs;

include "sys.m";
	sys : Sys;
include "draw.m";
include "bufio.m";
	bufio : Bufio;
include "arg.m";
	arg : Arg;
include "string.m";
	str : String;
include "daytime.m";
	daytime : Daytime;
include "styx.m";
	styx: Styx;
include "archfs.m";
include "arch.m";
	arch : Arch;

# add write some day

Iobuf : import bufio;
Tmsg, Rmsg: import styx;

Einuse		: con "fid already in use";
Ebadfid		: con "bad fid";
Eopen		: con "fid already opened";
Enotfound	: con "file does not exist";
Enotdir		: con "not a directory";
Eperm		: con "permission denied";
Ebadarg		: con "bad argument";
Eexists		: con "file already exists";

UID : con "inferno";
GID : con "inferno";

DEBUG: con 0;

Dir : adt {
	dir : Sys->Dir;
	offset : int;
	parent : cyclic ref Dir;
	child : cyclic ref Dir;
	sibling : cyclic ref Dir;
};

Fid : adt {
	fid : int;
	open: int;
	dir : ref Dir;
	next : cyclic ref Fid;
};

HTSZ : con 32;
fidtab := array[HTSZ] of ref Fid;

root : ref Dir;
qid : int;
mtpt := "/mnt";
bio : ref Iobuf;
buf : array of byte;
skip := 0;

# Archfs : module
# {
# 	init : fn(ctxt : ref Draw->Context, args : list of string);
# };

init(nil : ref Draw->Context, args : list of string)
{
	init0(nil, args, nil);
}

initc(args : list of string, c : chan of int)
{
	init0(nil, args, c);
}

chanint : chan of int;

init0(nil : ref Draw->Context, args : list of string, chi : chan of int)
{
	chanint = chi;
	sys = load Sys Sys->PATH;
	bufio = load Bufio Bufio->PATH;
	arg = load Arg Arg->PATH;
	str = load String String->PATH;
	daytime = load Daytime Daytime->PATH;
	styx = load Styx Styx->PATH;
	arch = load Arch Arch->PATH;
	if (bufio == nil || arg == nil || styx == nil || arch == nil)
		fatal("failed to load modules", 1);
	styx->init();
	arch->init(bufio);
	arg->init(args);
	while ((c := arg->opt()) != 0) {
		case c {
			'm' =>
				mtpt = arg->arg();
				if (mtpt == nil)
					fatal("mount point missing", 1);
			's' =>
				skip = 1;
		}
	}
	args = arg->argv();
	if (args == nil)
		fatal("missing archive file", 1);
	buf = array[Sys->ATOMICIO] of byte;
	# root = newdir("/", UID, GID, 8r755|Sys->DMDIR, daytime->now());
	root = newdir(basename(mtpt), UID, GID, 8r755|Sys->DMDIR, daytime->now());
	root.parent = root;
	readarch(hd args, tl args);
	p := array[2] of ref Sys->FD;
	if(sys->pipe(p) < 0)
		fatal("can't create pipe", 1);
	ch := chan of ref Tmsg;
	sync := chan of int;
	spawn reader(p[1], ch, sync);
	<- sync;
	pidch := chan of int;
	spawn serve(p[1], ch, pidch);
	pid := <- pidch;
	if(sys->mount(p[0], nil, mtpt, Sys->MREPL, nil) < 0)
		fatal(sys->sprint("cannot mount archive on %s: %r", mtpt), 1);
	p[0] = p[1] = nil;
	if (chi != nil) {
		chi <-= pid;
		chanint = nil;
	}
}

reply(fd: ref Sys->FD, m: ref Rmsg): int
{
	if(DEBUG)
		sys->fprint(sys->fildes(2), "R: %s\n", m.text());
	s := m.pack();
	if(s == nil)
		return -1;
	return sys->write(fd, s, len s);
}

error(fd: ref Sys->FD, m: ref Tmsg, e : string)
{
	reply(fd, ref Rmsg.Error(m.tag, e));
}

reader(fd: ref Sys->FD, ch: chan of ref Tmsg, sync: chan of int)
{
	sys->pctl(Sys->NEWFD|Sys->NEWNS, fd.fd :: nil);
	sync <-= 1;
	while((m := Tmsg.read(fd, Styx->MAXRPC)) != nil && tagof m != tagof Tmsg.Readerror)
		ch <-= m;
	ch <-= m;
}

serve(fd: ref Sys->FD, ch : chan of ref Tmsg, pidch : chan of int)
{
	e : string;
	f : ref Fid;

	pidch <-= sys->pctl(0, nil);
	for (;;) {
		m0 := <- ch;
		if (m0 == nil)
			return;
		if(DEBUG)
			sys->fprint(sys->fildes(2), "T: %s\n", m0.text());
		pick m := m0 {
			Readerror =>
				fatal("read error on styx server", 1);
			Version =>
				(s, v) := styx->compatible(m, Styx->MAXRPC, Styx->VERSION);
				reply(fd, ref Rmsg.Version(m.tag, s, v));
			Auth =>
				error(fd, m, "no authentication required");
			Flush =>
				reply(fd, ref Rmsg.Flush(m.tag));
			Walk =>
				(f, e) = mapfid(m.fid);
				if (e != nil) {
					error(fd, m, e);
					continue;
				}
				if (f.open) {
					error(fd, m, Eopen);
					continue;
				}
				err := 0;
				dir := f.dir;
				nq := 0;
				nn := len m.names;
				qids := array[nn] of Sys->Qid;
				if(nn > 0){
					for(k := 0; k < nn; k++){
						if ((dir.dir.mode & Sys->DMDIR) == 0) {
							if(k == 0){
								error(fd, m, Enotdir);
								err = 1;
							}
							break;
						}
						dir  = lookup(dir, m.names[k]);
						if (dir == nil) {
							if(k == 0){
								error(fd, m, Enotfound);
								err = 1;
							}
							break;
						}
						qids[nq++] = dir.dir.qid;
					}
				}
				if(err)
					continue;
				if(nq < nn)
					qids = qids[0: nq];
				if(nq == nn){
					if(m.newfid != m.fid){
						f = newfid(m.newfid);
						if (f == nil) {
							error(fd, m, Einuse);
							continue;
						}
					}
					f.dir = dir;
				}
				reply(fd, ref Rmsg.Walk(m.tag, qids));
			Open =>
				(f, e) = mapfid(m.fid);
				if (e != nil) {
					error(fd, m, e);
					continue;
				}
				if (m.mode & (Sys->OWRITE|Sys->ORDWR|Sys->OTRUNC|Sys->ORCLOSE)) {
					error(fd, m, Eperm);
					continue;
				}
				f.open = 1;
				reply(fd, ref Rmsg.Open(m.tag, f.dir.dir.qid, Styx->MAXFDATA));
			Create =>
				error(fd, m, Eperm);
			Read =>
				(f, e) = mapfid(m.fid);
				if (e != nil) {
					error(fd, m, e);
					continue;
				}
				data := readdir(f.dir, int m.offset, m.count);
				reply(fd, ref Rmsg.Read(m.tag, data));
			Write =>
				error(fd, m, Eperm);				
			Clunk =>
				(f, e) = mapfid(m.fid);
				if (e != nil) {
					error(fd, m, e);
					continue;
				}
				freefid(f);
				reply(fd, ref Rmsg.Clunk(m.tag));
			Stat =>
				(f, e) = mapfid(m.fid);
				if (e != nil) {
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
				if (f == nil) {
					error(fd, m, Einuse);
					continue;
				}
				f.dir = root;
				reply(fd, ref Rmsg.Attach(m.tag, f.dir.dir.qid));
			* =>
				fatal("unknown styx message", 1);
		}
	}
}

newfid(fid : int) : ref Fid
{
	(f, nil) := mapfid(fid);
	if(f != nil)
		return nil;
	f = ref Fid;
	f.fid = fid;
	f.open = 0;
	hv := hashval(fid);
	f.next = fidtab[hv];
	fidtab[hv] = f;
	return f;
}

freefid(f: ref Fid)
{
	hv := hashval(f.fid);
	lf : ref Fid;
	for(ff := fidtab[hv]; ff != nil; ff = ff.next){
		if(f == ff){
			if(lf == nil)
				fidtab[hv] = ff.next;
			else
				lf.next = ff.next;
			return;
		}
		lf = ff;
	}
	fatal("cannot find fid", 1);
}
	
mapfid(fid : int) : (ref Fid, string)
{
	hv := hashval(fid);
	for (f := fidtab[hv]; f != nil; f = f.next)
		if (int f.fid == fid)
			break;
	if (f == nil)
		return (nil, Ebadfid);
	if (f.dir == nil)
		return (nil, Enotfound);
	return (f, nil);
}

hashval(n : int) : int
{
	return (n & ~Sys->DMDIR)%HTSZ;
}

readarch(f : string, args : list of string)
{
	ar := arch->openarchfs(f);
	if(ar == nil || ar.b == nil)
		fatal(sys->sprint("cannot open %s(%r)\n", f), 1);
	bio = ar.b;
	while ((a := arch->gethdr(ar)) != nil) {
		if (args != nil) {
			if (!selected(a.name, args)) {
				if (skip)
					return;
				arch->drain(ar, int a.d.length);
				continue;
			}
			mkdirs("/", a.name);
		}
		d := mkdir(a.name, a.d.mode, a.d.mtime, a.d.uid, a.d.gid, 0);
		if((a.d.mode & Sys->DMDIR) == 0) {
			d.dir.length = a.d.length;
			d.offset = int bio.offset();
		}
		arch->drain(ar, int a.d.length);
	}
	if (ar.err != nil)
		fatal(ar.err, 0);
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

basename(f : string) : string
{
	for (i := len f; i > 0; ) 
		if (f[--i] == '/')
			return f[i+1:];
	return f;
}

split(p : string) : (string, string)
{
	if (p == nil)
		fatal("nil string in split", 1);
	if (p[0] != '/')
		fatal("p0 not / in split", 1);
	while (p[0] == '/')
		p = p[1:];
	i := 0;
	while (i < len p && p[i] != '/')
		i++;
	if (i == len p)
		return (p, nil);
	else
		return (p[0:i], p[i:]);
}

mkdirs(basedir, name: string)
{
	(nil, names) := sys->tokenize(name, "/");
	while(names != nil) {
		# sys->print("mkdir %s\n", basedir);
		mkdir(basedir, 8r775|Sys->DMDIR, daytime->now(), UID, GID, 1);
		if(tl names == nil)
			break;
		basedir = basedir + "/" + hd names;
		names = tl names;
	}
}

readdir(d : ref Dir, offset : int, n : int) : array of byte
{
	if (d.dir.mode & Sys->DMDIR)
		return readd(d, offset, n);
	else
		return readf(d, offset, n);
}
	
readd(d : ref Dir, o : int, n : int) : array of byte
{
	k := 0;
	m := 0;
	b := array[n] of byte;
	for (s := d.child; s != nil; s = s.sibling) {
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

readf(d : ref Dir, offset : int, n : int) : array of byte
{
	leng := int d.dir.length;
	if (offset+n > leng)
		n = leng-offset;
	if (n <= 0 || offset < 0)
		return nil;
	bio.seek(big (d.offset+offset), Bufio->SEEKSTART);
	a := array[n] of byte;
	p := 0;
	m := 0;
	for ( ; n != 0; n -= m) {
		l := len buf;
		if (n < l)
			l = n;
		m = bio.read(buf, l);
		if (m <= 0 || m != l)
			fatal("premature eof", 1);
		a[p:] = buf[0:m];
		p += m;
	}
	return a;
}

mkdir(f : string, mode : int, mtime : int, uid : string, gid : string, existsok : int) : ref Dir
{
	if (f == "/")
		return nil;
	d := newdir(basename(f), uid, gid, mode, mtime);
	addfile(d, f, existsok);
	return d;
}

addfile(d : ref Dir, path : string, existsok : int)
{
	elem : string;

	opath := path;
	p := prev := root;
	basedir := "";
# sys->print("addfile %s : %s\n", d.dir.name, path);
	while (path != nil) {
		(elem, path) = split(path);
		basedir += "/" + elem;
		op := p;
		p = lookup(p, elem);
		if (path == nil) {
			if (p != nil) {
				if (!existsok && (p.dir.mode&Sys->DMDIR) == 0)
					sys->fprint(sys->fildes(2), "addfile: %s already there", opath);
					# fatal(sys->sprint("addfile: %s already there", opath), 1);
				return;
			}
			if (prev.child == nil)
				prev.child = d;
			else {
				for (s := prev.child; s.sibling != nil; s = s.sibling)
					;
				s.sibling = d;
			}
			d.parent = prev;
		}
		else {
			if (p == nil) {
				mkdir(basedir, 8r775|Sys->DMDIR, daytime->now(), UID, GID, 1);
				p = lookup(op, elem);
				if (p == nil)
					fatal("bad file system", 1);
			}
		}
		prev = p;
	}
}

lookup(p : ref Dir, f : string) : ref Dir
{
	if ((p.dir.mode&Sys->DMDIR) == 0) 
		fatal("not a directory in lookup", 1);
	if (f == ".")
		return p;
	if (f == "..")
		return p.parent;
	for (d := p.child; d != nil; d = d.sibling)
		if (d.dir.name == f)
			return d;
	return nil;
}

newdir(name, uid, gid : string, mode, mtime : int) : ref Dir
{
	dir : Sys->Dir;

	dir.name = name;
	dir.uid = uid;
	dir.gid = gid;
	dir.qid.path = big (qid++);
	if(mode&Sys->DMDIR)
		dir.qid.qtype = Sys->QTDIR;
	else
		dir.qid.qtype = Sys->QTFILE;
	dir.qid.vers = 0;
	dir.mode = mode;
	dir.atime = dir.mtime = mtime;
	dir.length = big 0;
	dir.dtype = 'X';
	dir.dev = 0;

	d := ref Dir;
	d.dir = dir;
	d.offset = 0;
	return d;
}

# pr(d : ref Dir)
# {
#	dir := d.dir;
#	sys->print("%s %s %s %x %x %x %d %d %d %d %d %d\n",
#		dir.name, dir.uid, dir.gid, dir.qid.path, dir.qid.vers, dir.mode, dir.atime, dir.mtime, dir.length, dir.dtype, dir.dev, d.offset);
# }

fatal(e : string, pr: int)
{
	if(pr){
		sys->fprint(sys->fildes(2), "fatal: %s\n", e);
		if (chanint != nil)
			chanint <-= -1;
	}
	else{
		# probably not an archive file
		if (chanint != nil)
			chanint <-= -2;
	}
	exit;
}
