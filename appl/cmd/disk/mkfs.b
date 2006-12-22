implement Mkfs;

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

Mkfs: module
{
	init:	fn(nil: ref Draw->Context, nil: list of string);
};

LEN: con Sys->ATOMICIO;
HUNKS: con 128;

Kfs, Fs, Archive: con iota;	# types of destination file sytems

File: adt {
	new:	string;
	elem:	string;
	old:	string;
	uid:	string;
	gid:	string;
	mode:	int;
};

b: ref Iobuf;
bout: ref Iobuf;			# stdout when writing archive
newfile: string;
oldfile: string;
proto: string;
cputype: string;
users: string;
oldroot: string;
newroot: string;
prog := "mkfs";
lineno := 0;
buf: array of byte;
zbuf: array of byte;
buflen := 1024-8;
indent: int;
verb: int;
modes: int;
ream: int;
debug: int;
xflag: int;
qflag := 1;
sfd: ref Sys->FD;
fskind: int;	# Kfs, Fs, Archive
user: string;
stderr: ref Sys->FD;
usrid, grpid : string;
setuid: int;
	
usage()
{
	fprint(stderr, "usage: %s [-apqrvx] [-d root] [-n kfsname] [-s src-fs] [-u userfile] [-z n] proto ...\n", prog);
	quit("usage");
}

init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	bufio = load Bufio Bufio->PATH;
	str = load String String->PATH;
	arg = load Arg Arg->PATH;

	sys->pctl(Sys->NEWPGRP|Sys->FORKNS|Sys->FORKFD, nil);

	stderr = sys->fildes(2);
	if(arg == nil)
		error(sys->sprint("can't load %s: %r", Arg->PATH));

	user = getuser();
	if(user == nil)
		user = "none";
	name := "";
	file := ref File;
	file.new = "";
	file.old = nil;
	file.mode = 0;
	oldroot = "";
	newroot = "/n/kfs";
	users = nil;
	fskind = Kfs;	# i suspect Inferno default should be different
	arg->init(args);
	while((c := arg->opt()) != 0)
		case c {
		'a' =>
			fskind = Archive;
			newroot = "";
			bout = bufio->fopen(sys->fildes(1), Sys->OWRITE);
			if(bout == nil)
				error(sys->sprint("can't open standard output for archive: %r"));
		'd' =>
			fskind = Fs;
			newroot = reqarg("destination directory (-d)");
		'D' =>
			debug = 1;
		'n' =>
			name = reqarg("kfs instance name (-n)");
		'p' =>
			modes = 1;
		'q' =>
			qflag = 0;
		'r' =>
			ream = 1;
		's' =>
			oldroot = reqarg("source directory (-d)");
		'u' =>
			users = reqarg("/adm/users file (-u)");
		'v' =>
			verb = 1;
		'x' =>
			xflag = 1;
		'z' =>
			(buflen, nil) = str->toint(reqarg("buffer length (-z)"), 10);
			buflen -= 8;	# qid.path and tag at end of each kfs block
		'U' => 
			usrid = reqarg("user name (-U)");
		'G' =>
			grpid = reqarg("group name (-G)");
		'S' =>
			setuid = 1;
		* =>
			usage();
		}

	args = arg->argv();
	if(args == nil)
		usage();

	buf = array [buflen] of byte;
	zbuf = array [buflen] of { * => byte 0 };

	mountkfs(name);
	kfscmd("allow");
	proto = "users";
	setusers();
	cputype = getenv("cputype");
	if(cputype == nil)
		cputype = "dis";

	errs := 0;
	for(; args != nil; args = tl args){
		proto = hd args;
		fprint(stderr, "processing %s\n", proto);

		b = bufio->open(proto, Sys->OREAD);
		if(b == nil){
			fprint(stderr, "%s: can't open %s: %r: skipping\n", prog, proto);
			errs++;
			continue;
		}

		lineno = 0;
		indent = 0;
		mkfs(file, -1);
		b.close();
	}
	fprint(stderr, "file system made\n");
	kfscmd("disallow");
	kfscmd("sync");
	if(errs)
		quit("skipped protos");
	if(fskind == Archive){
		bout.puts("end of archive\n");
		if(bout.flush() == Bufio->ERROR)
			error(sys->sprint("write error: %r"));
	}
}

quit(why: string)
{
	if(bout != nil)
		bout.flush();
	if(why != nil)
		raise "fail:"+why;
	exit;
}

reqarg(what: string): string
{
	if((o := arg->arg()) == nil){
		sys->fprint(stderr, "%s: missing %s\n", prog, what);
		quit("usage");
	}
	return o;
}

mkfs(me: ref File, level: int)
{
	(child, fp) := getfile(me);
	if(child == nil)
		return;
	if(child.elem == "+" || child.elem == "*" || child.elem == "%"){
		rec := child.elem[0] == '+';
		filesonly := child.elem[0] == '%';
		child.new = me.new;
		setnames(child);
		mktree(child, rec, filesonly);
		(child, fp) = getfile(me);
	}
	while(child != nil && indent > level){
		if(mkfile(child))
			mkfs(child, indent);
		(child, fp) = getfile(me);
	}
	if(child != nil){
		b.seek(fp, 0);
		lineno--;
	}
}

mktree(me: ref File, rec: int, filesonly: int)
{
	fd := sys->open(oldfile, Sys->OREAD);
	if(fd == nil){
		warn(sys->sprint("can't open %s: %r", oldfile));
		return;
	}

	child := ref *me;
	r := ref Rec(nil, 0);
	for(;;){
		(n, d) := sys->dirread(fd);
		if(n <= 0)
			break;
		for(i := 0; i < n; i++)
		  	if (!recall(d[i].name, r)) {
				if(filesonly && d[i].mode & Sys->DMDIR)
					continue;
				child.new = mkpath(me.new, d[i].name);
				if(me.old != nil)
					child.old = mkpath(me.old, d[i].name);
				child.elem = d[i].name;
				setnames(child);
				if(copyfile(child, ref d[i], 1) && rec)
					mktree(child, rec, filesonly);
		  	}
	}
}

# Recall namespace fix
# -- remove duplicates (could use Readdir->init(,Readdir->COMPACT))
# obc

Rec: adt
{
	ad: array of string;
	l: int;
};

AL : con HUNKS;
recall(e : string, r : ref Rec) : int
{
	if (r.ad == nil) r.ad = array[AL] of string;
	# double array
	if (r.l >= len r.ad) {
		nar := array[2*(len r.ad)] of string;
		nar[0:] = r.ad;
		r.ad = nar;
	}
	for(i := 0; i < r.l; i++)
		if (r.ad[i] == e) return 1;
	r.ad[r.l++] = e;
	return 0;
}

mkfile(f: ref File): int
{
	(i, dir) := sys->stat(oldfile);
	if(i < 0){
		warn(sys->sprint("can't stat file %s: %r", oldfile));
		skipdir();
		return 0;
	}
	return copyfile(f, ref dir, 0);
}

copyfile(f: ref File, d: ref Dir, permonly: int): int
{
	mode: int;

	if(xflag && bout != nil){
		bout.puts(sys->sprint("%s\t%d\t%bd\n", quoted(f.new), d.mtime, d.length));
		return (d.mode & Sys->DMDIR) != 0;
	}
	d.name = f.elem;
	if(d.dtype != 'M' && d.dtype != 'U'){		# hmm... Indeed!
		d.uid = "inferno";
		d.gid = "inferno";
		mode = (d.mode >> 6) & 7;
		d.mode |= mode | (mode << 3);
	}
	if(f.uid != "-")
		d.uid = f.uid;
	if(f.gid != "-")
		d.gid = f.gid;
	if(fskind == Fs && !setuid){	# new system: set to nil
		d.uid = user;
		d.gid = user;
	}
	if (usrid != nil)
		d.uid = usrid;
	if (grpid != nil)
		d.gid = grpid;
	if(f.mode != ~0){
		if(permonly)
			d.mode = (d.mode & ~8r666) | (f.mode & 8r666);
		else if((d.mode&Sys->DMDIR) != (f.mode&Sys->DMDIR))
			warn(sys->sprint("inconsistent mode for %s", f.new));
		else
			d.mode = f.mode;
	}
	if(!uptodate(d, newfile)){
		if(d.mode & Sys->DMDIR)
			mkdir(d);
		else {
			if(verb)
				fprint(stderr, "%s\n", f.new);
			copy(d);
		}
	}else if(modes){
		nd := sys->nulldir;
		nd.mode = d.mode;
		nd.mtime = d.mtime;
		nd.gid = d.gid;
		if(sys->wstat(newfile, nd) < 0)
			warn(sys->sprint("can't set modes for %s: %r", f.new));
		# do the uid separately since different file systems object
		nd = sys->nulldir;
		nd.uid = d.uid;
		sys->wstat(newfile, nd);
	}
	return (d.mode & Sys->DMDIR) != 0;
}


# check if file to is up to date with
# respect to the file represented by df

uptodate(df: ref Dir, newf: string): int
{
	if(fskind == Archive || ream)
		return 0;
	(i, dt) := sys->stat(newf);
	if(i < 0)
		return 0;
	return dt.mtime >= df.mtime;
}

copy(d: ref Dir)
{
	t: ref Sys->FD;
	n: int;

	f := sys->open(oldfile, Sys->OREAD);
	if(f == nil){
		warn(sys->sprint("can't open %s: %r", oldfile));
		return;
	}
	t = nil;
	if(fskind == Archive)
		arch(d);
	else{
		(dname, fname) := str->splitr(newfile, "/");
		if(fname == nil)
			error(sys->sprint("internal temporary file error (%s)", dname));
		cptmp := dname+"__mkfstmp";
		t = sys->create(cptmp, Sys->OWRITE, 8r666);
		if(t == nil){
			warn(sys->sprint("can't create %s: %r", newfile));
			return;
		}
	}

	for(tot := big 0;; tot += big n){
		n = sys->read(f, buf, buflen);
		if(n < 0){
			warn(sys->sprint("can't read %s: %r", oldfile));
			break;
		}
		if(n == 0)
			break;
		if(fskind == Archive){
			if(bout.write(buf, n) != n)
				error(sys->sprint("write error: %r"));
		}else if(buf[0:buflen] == zbuf[0:buflen]){
			if(sys->seek(t, big buflen, 1) < big 0)
				error(sys->sprint("can't write zeros to %s: %r", newfile));
		}else if(sys->write(t, buf, n) < n)
			error(sys->sprint("can't write %s: %r", newfile));
	}
	f = nil;
	if(tot != d.length){
		warn(sys->sprint("wrong number bytes written to %s (was %bd should be %bd)",
			newfile, tot, d.length));
		if(fskind == Archive){
			warn("seeking to proper position");
			bout.seek(d.length - tot, 1);
		}
	}
	if(fskind == Archive)
		return;
	sys->remove(newfile);
	nd := sys->nulldir;
	nd.name = d.name;
	nd.mode = d.mode;
	nd.mtime = d.mtime;
	if(sys->fwstat(t, nd) < 0)
		error(sys->sprint("can't move tmp file to %s: %r", newfile));
	nd = sys->nulldir;
	nd.gid = d.gid;
	if(sys->fwstat(t, nd) < 0)
		warn(sys->sprint("can't set group id of %s to %s: %r", newfile, d.gid));
	nd.gid = nil;
	nd.uid = d.uid;
	sys->fwstat(t, nd);
}

mkdir(d: ref Dir)
{
	if(fskind == Archive){
		arch(d);
		return;
	}
	fd := sys->create(newfile, Sys->OREAD, d.mode);
	nd := sys->nulldir;
	nd.mode = d.mode;
	nd.gid = d.gid;
	nd.mtime = d.mtime;
	if(fd == nil){
		(i, d1) := sys->stat(newfile);
		if(i < 0 || !(d1.mode & Sys->DMDIR))
			error(sys->sprint("can't create %s", newfile));
		if(sys->wstat(newfile, nd) < 0)
			warn(sys->sprint("can't set modes for %s: %r", newfile));
		nd = sys->nulldir;
		nd.uid = d.uid;
		sys->wstat(newfile, nd);
		return;
	}
	if(sys->fwstat(fd, nd) < 0)
		warn(sys->sprint("can't set modes for %s: %r", newfile));
	nd = sys->nulldir;
	nd.uid = d.uid;
	sys->fwstat(fd, nd);
}

arch(d: ref Dir)
{
	bout.puts(sys->sprint("%s %s %s %s %ud %bd\n",
		quoted(newfile), octal(d.mode), d.uid, d.gid, d.mtime, d.length));
}

mkpath(prefix, elem: string): string
{
	return sys->sprint("%s/%s", prefix, elem);
}

setnames(f: ref File)
{
	newfile = newroot+f.new;
	if(f.old != nil){
		if(f.old[0] == '/')
			oldfile = oldroot+f.old;
		else
			oldfile = f.old;
	}else
		oldfile = oldroot+f.new;
}

#
# skip all files in the proto that
# could be in the current dir
#
skipdir()
{
	if(indent < 0)
		return;
	level := indent;
	for(;;){
		indent = 0;
		fp := b.offset();
		p := b.gets('\n');
		lineno++;
		if(p == nil){
			indent = -1;
			return;
		}
		for(j := 0; (c := p[j++]) != '\n';)
			if(c == ' ')
				indent++;
			else if(c == '\t')
				indent += 8;
			else
				break;
		if(indent <= level){
			b.seek(fp, 0);
			lineno--;
			return;
		}
	}
}

getfile(old: ref File): (ref File, big)
{
	f: ref File;
	p, elem: string;
	c: int;

	if(indent < 0)
		return (nil, big 0);
	fp := b.offset();
	do {
		indent = 0;
		p = b.gets('\n');
		lineno++;
		if(p == nil){
			indent = -1;
			return (nil, big 0);
		}
		for(; (c = p[0]) != '\n'; p = p[1:])
			if(c == ' ')
				indent++;
			else if(c == '\t')
				indent += 8;
			else
				break;
	} while(c == '\n' || c == '#');
	f = ref File;
	(elem, p) = getname(p);
	if(debug)
		fprint(stderr, "getfile: %s root %s\n", elem, old.new);
	f.new = mkpath(old.new, elem);
	(nil, f.elem) = str->splitr(f.new, "/");
	if(f.elem == nil)
		error(sys->sprint("can't find file name component of %s", f.new));
	(f.mode, p) = getmode(p);
	(f.uid, p) = getname(p);
	if(f.uid == nil)
		f.uid = "-";
	(f.gid, p) = getname(p);
	if(f.gid == nil)
		f.gid = "-";
	f.old = getpath(p);
	if(f.old == "-")
		f.old = nil;
	setnames(f);

	if(debug)
		printfile(f);

	return (f, fp);
}

getpath(p: string): string
{
	for(; (c := p[0]) == ' ' || c == '\t'; p = p[1:])
		;
	for(n := 0; (c = p[n]) != '\n' && c != ' ' && c != '\t'; n++)
		;
	return p[0:n];
}

getname(p: string): (string, string)
{
	for(; (c := p[0]) == ' ' || c == '\t'; p = p[1:])
		;
	i := 0;
	s := "";
	quoted := 0;
	for(; (c = p[0]) != '\n' && (c != ' ' && c != '\t' || quoted); p = p[1:]){
			if(quoted && c == '\'' && p[1] == '\'')
				p = p[1:];
			else if(c == '\'' && qflag){
				quoted = !quoted;
				continue;
			}
			s[i++] = c;
	}
	if(len s > 0 && s[0] == '$'){
		s = getenv(s[1:]);
		if(s == nil)
			error(sys->sprint("can't read environment variable %s", s));
	}
	return (s, p);
}

getenv(s: string): string
{
	if(s == "user")
		return getuser();
	return readfile("/env/"+s);
}

getuser(): string
{
	return readfile("/dev/user");
}

readfile(f: string): string
{
	fd := sys->open(f, Sys->OREAD);
	if(fd != nil){
		a := array[256] of byte;
		n := sys->read(fd, a, len a);
		if(n > 0)
			return string a[0:n];
	}
	return nil;
}

getmode(p: string): (int, string)
{
	s: string;

	(s, p) = getname(p);
	if(s == nil || s == "-")
		return (~0, p);
	os := s;
	m := 0;
	if(s[0] == 'd'){
		m |= Sys->DMDIR;
		s = s[1:];
	}
	if(s[0] == 'a'){
		m |= Sys->DMAPPEND;
		s = s[1:];
	}
	if(s[0] == 'l'){
		m |= Sys->DMEXCL;
		s = s[1:];
	}

	for(i:=0; i<len s || i < 3; i++)
		if(i >= len s || !(s[i]>='0' && s[i]<='7')){
			warn(sys->sprint("bad mode specification %s", os));
			return (~0, p);
		}
	(v, nil) := str->toint(s, 8);
	return (m|v, p);
}

quoted(s: string): string
{
	if(qflag)
		return sys->sprint("%q", s);
	return s;
}

setusers()
{
	if(fskind != Kfs)
		return;
	file := ref File;
	m := modes;
	modes = 1;
	file.uid = "adm";
	file.gid = "adm";
	file.mode = Sys->DMDIR|8r775;
	file.new = "/adm";
	file.elem = "adm";
	file.old = nil;
	setnames(file);
	mkfile(file);
	file.new = "/adm/users";
	file.old = users;
	file.elem = "users";
	file.mode = 8r664;
	setnames(file);
	mkfile(file);
	kfscmd("user");
	mkfile(file);
	file.mode = Sys->DMDIR|8r775;
	file.new = "/adm";
	file.old = "/adm";
	file.elem = "adm";
	setnames(file);
	mkfile(file);
	modes = m;
}

# this isn't right for the current #K
mountkfs(name: string)
{
	kname: string;

	if(fskind != Kfs)
		return;
	if(name != nil)
		kname = sys->sprint("/srv/kfs.%s", name);
	else
		kname = "/srv/kfs";
	fd := sys->open(kname, Sys->ORDWR);
	if(fd == nil){
		fprint(stderr, "%s: can't open %s: %r\n", prog, kname);
		quit("open kfs");
	}
	if(sys->mount(fd, nil, "/n/kfs", Sys->MREPL|Sys->MCREATE, "") < 0){
		fprint(stderr, "%s: can't mount kfs on /n/kfs: %r\n", prog);
		quit("mount kfs");
	}
	kname += ".cmd";
	sfd = sys->open(kname, Sys->ORDWR);
	if(sfd == nil){
		fprint(stderr, "%s: can't open %s: %r\n", prog, kname);
		quit("open kfscmd");
	}
}

kfscmd(cmd: string)
{
	if(fskind != Kfs || sfd == nil)
		return;
	a := array of byte cmd;
	if(sys->write(sfd, a, len a) != len a){
		fprint(stderr, "%s: error writing %s: %r", prog, cmd);
		return;
	}
	for(;;){
		reply := array[4*1024] of byte;
		n := sys->read(sfd, reply, len reply);
		if(n <= 0)
			return;
		s := string reply[0:n];
		if(s == "done" || s == "success")
			return;
		if(s == "unknown command"){
			fprint(stderr, "%s: command %s not recognized\n", prog, cmd);
			return;
		}
	}
}

error(s: string)
{
	fprint(stderr, "%s: %s: %d: %s\n", prog, proto, lineno, s);
	kfscmd("disallow");
	kfscmd("sync");
	quit("error");
}

warn(s: string)
{
	fprint(stderr, "%s: %s: %d: %s\n", prog, proto, lineno, s);
}

printfile(f: ref File)
{
	if(f.old != nil)
		fprint(stderr, "%s from %s %s %s %s\n", f.new, f.old, f.uid, f.gid, octal(f.mode));
	else
		fprint(stderr, "%s %s %s %s\n", f.new, f.uid, f.gid, octal(f.mode));
}

octal(i: int): string
{
	s := "";
	do {
		t: string;
		t[0] = '0' + (i&7);
		s = t+s;
	} while((i = (i>>3)&~(7<<29)) != 0);
	return s;
}
