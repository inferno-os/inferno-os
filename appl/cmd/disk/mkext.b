implement Mkext;

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

Mkext: module
{
	init:	fn(nil: ref Draw->Context, nil: list of string);
};

LEN: con Sys->ATOMICIO;
NFLDS: con 6;		# filename, modes, uid, gid, mtime, bytes

bin: ref Iobuf;
uflag := 0;
tflag := 0;
hflag := 0;
vflag := 0;
fflag := 0;
qflag := 1;
stderr: ref Sys->FD;
bout: ref Iobuf;
argv0 := "mkext";

usage()
{
	fprint(stderr, "Usage: mkext [-h] [-u] [-v] [-f] [-t] [-q] [-d dest-fs] [file ...]\n");
	raise "fail:usage";
}

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

	destdir := "";
	arg->init(args);
	while((c := arg->opt()) != 0)
		case c {
		'd' =>
			destdir = arg->arg();
			if(destdir == nil)
				error("destination directory name missing");
		'f' =>
			fflag = 1;

		'h' =>
			hflag = 1;
			bout = bufio->fopen(sys->fildes(1), Sys->OWRITE);
			if(bout == nil)
				error(sys->sprint("can't access standard output: %r"));
		'u' =>
			uflag = 1;
		't' =>
			tflag = 1;
		'v' =>
			vflag = 1;
		'q' =>
			qflag = 0;
		* =>
			usage();
		}
	args = arg->argv();

	bin = bufio->fopen(sys->fildes(0), Sys->OREAD);
	if(bin == nil)
		error(sys->sprint("can't access standard input: %r"));
	while((p := bin.gets('\n')) != nil){
		if(p == "end of archive\n"){
			fprint(stderr, "done\n");
			quit(nil);
		}
		fields: list of string;
		nf: int;
		if(qflag){
			fields = str->unquoted(p);
			nf = len fields;
		}else
			(nf, fields) = sys->tokenize(p, " \t\n");
		if(nf != NFLDS){
			warn("too few fields in file header");
			continue;
		}
		name := hd fields;
		fields = tl fields;
		(mode, nil) := str->toint(hd fields, 8);
		fields = tl fields;
		uid := hd fields;
		fields = tl fields;
		gid := hd fields;
		fields = tl fields;
		(mtime, nil) := str->toint(hd fields, 10);
		fields = tl fields;
		(bytes, nil) := str->tobig(hd fields, 10);
		if(args != nil){
			if(!selected(name, args)){
				if(bytes != big 0)
					seekpast(bytes);
				continue;
			}
			mkdirs(destdir, name);
		}
		name = destdir+name;
		if(hflag){
			bout.puts(sys->sprint("%s %s %s %s %ud %bd\n",
				quoted(name), octal(mode), uid, gid, mtime, bytes));
			if(bytes != big 0)
				seekpast(bytes);
			continue;
		}
		if(mode & Sys->DMDIR)
			mkdir(name, mode, mtime, uid, gid);
		else
			extract(name, mode, mtime, uid, gid, bytes);
	}
	fprint(stderr, "premature end of archive\n");
	quit("eof");
}

quit(s: string)
{
	if(bout != nil)
		bout.flush();
	if(s != nil)
		raise "fail: "+s;
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
		#sys->print("mkdir %s\n", basedir);
		create(basedir, Sys->OREAD, 8r775|Sys->DMDIR);

		if(tl names == nil)
			break;
		basedir = basedir + "/" + hd names;
		names = tl names;
	}
}

mkdir(name: string, mode: int, mtime: int, uid: string, gid: string)
{
	d: Dir;
	i: int;

	fd := create(name, Sys->OREAD, mode);
	if(fd == nil){
		(i, d) = sys->stat(name);
		if(i < 0 || !(d.mode & Sys->DMDIR)){
			warn(sys->sprint("can't make directory %s: %r", name));
			return;
		}
	}else{
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
	if(tflag)
		d.mtime = mtime;
	if(uflag){
		d.uid = uid;
		d.gid = gid;
		d.mtime = mtime;
	}
	d.mode = mode;
	if(sys->wstat(name, d) < 0)
		warn(sys->sprint("can't set modes for %s: %r", name));
	if(uflag){
		(i, d) = sys->stat(name);
		if(i < 0)
			warn(sys->sprint("can't reread modes for %s: %r", name));
		if(d.mtime != mtime)
			warn(sys->sprint("%s: time mismatch %ud %ud\n", name, mtime, d.mtime));
		if(uid != d.uid)
			warn(sys->sprint("%s: uid mismatch %s %s", name, uid, d.uid));
		if(gid != d.gid)
			warn(sys->sprint("%s: gid mismatch %s %s", name, gid, d.gid));
	}
}

extract(name: string, mode: int, mtime: int, uid: string, gid: string, bytes: big)
{
	n: int;

	if(vflag)
		sys->print("x %s %bd bytes\n", name, bytes);

	sfd := create(name, Sys->OWRITE, mode);
	if(sfd == nil) {
		if(!fflag || sys->remove(name) == -1 ||
		    (sfd = create(name, Sys->OWRITE, mode)) == nil) {
			warn(sys->sprint("can't make file %s: %r", name));
			seekpast(bytes);
			return;
		}
	}
	b := bufio->fopen(sfd, Bufio->OWRITE);
	if (b == nil) {
		warn(sys->sprint("can't open file %s for bufio : %r", name));
		seekpast(bytes);
		return;
	}
	buf := array [LEN] of byte;
	for(tot := big 0; tot < bytes; tot += big n){
		n = len buf;
		if(tot + big n > bytes)
			n = int(bytes - tot);
		n = bin.read(buf, n);
		if(n <= 0)
			error(sys->sprint("premature eof reading %s", name));
		if(b.write(buf, n) != n)
			warn(sys->sprint("error writing %s: %r", name));
	}

	(i, nil) := sys->fstat(b.fd);
	if(i < 0)
		warn(sys->sprint("can't stat %s: %r", name));
	d := sys->nulldir;
	(nil, p) := str->splitr(name, "/");
	if(p == nil)
		p = name;
	d.name = p;
	if(tflag || uflag)
		d.mtime = mtime;
	if(uflag){
		d.uid = uid;
		d.gid = gid;
	}
	d.mode = mode;
	if(b.flush() == Bufio->ERROR)
		warn(sys->sprint("error writing %s: %r", name));
	if(sys->fwstat(b.fd, d) < 0)
		warn(sys->sprint("can't set modes for %s: %r", name));
	if(uflag){
		(i, d) = sys->fstat(b.fd);
		if(i < 0)
			warn(sys->sprint("can't reread modes for %s: %r", name));
		if(d.mtime != mtime)
			warn(sys->sprint("%s: time mismatch %ud %ud\n", name, mtime, d.mtime));
		if(d.uid != uid)
			warn(sys->sprint("%s: uid mismatch %s %s", name, uid, d.uid));
		if(d.gid != gid)
			warn(sys->sprint("%s: gid mismatch %s %s", name, gid, d.gid));
	}
	b.close();
}

seekpast(bytes: big)
{
	n: int;

	buf := array [LEN] of byte;
	for(tot := big 0; tot < bytes; tot += big n){
		n = len buf;
		if(tot + big n > bytes)
			n = int(bytes - tot);
		n = bin.read(buf, n);
		if(n <= 0)
			error("premature eof");
	}
}

error(s: string)
{
	fprint(stderr, "%s: %s\n", argv0, s);
	quit("error");
}

warn(s: string)
{
	fprint(stderr, "%s: %s\n", argv0, s);
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
		d.mode = omode | 8r222;		# ensure parent is writable
		if(sys->wstat(p, d) < 0) {
			warn(sys->sprint("can't set modes for %s: %r", p));
			return nil;
		}
		fd = sys->create(name, rw, mode);
		d.mode = omode;
		sys->wstat(p, d);
	}
	return fd;
}

quoted(s: string): string
{
	if(qflag)
		for(i:=0; i<len s; i++)
			if((c := s[i]) == ' ' || c == '\t' || c == '\n' || c == '\'')
				return str->quoted(s :: nil);
	return s;
}
