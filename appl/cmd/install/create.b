implement Create;

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
include "daytime.m";
include "keyring.m";
	keyring : Keyring;
include "sh.m";
include "wrap.m";
	wrap : Wrap;
include "arch.m";
	arch : Arch;
include "proto.m";
	proto : Proto;
include "protocaller.m";
	protocaller : Protocaller;

WARN, ERROR, FATAL : import Protocaller;

Create: module{
	init:	fn(nil: ref Draw->Context, nil: list of string);
	protofile: fn(new : string, old : string, d : ref Sys->Dir);
	protoerr: fn(lev : int, line : int, err : string);
};

bout: ref Iobuf;			# stdout when writing archive
protof: string;
notesf: string;
oldroot: string;
buf: array of byte;
buflen := 1024-8;
verb: int;
xflag: int;
stderr: ref Sys->FD;
uid, gid : string;
desc : string;
pass : int;
update : int;
md5s : ref Keyring->DigestState;
w : ref Wrap->Wrapped;
root := "/";
prefix, notprefix: list of string;
onlist: list of (string, string);	# NEW
remfile: string;

n2o(n: string): string
{
	for(onl := onlist; onl != nil; onl = tl onl)
		if((hd onl).t1 == n)
			return (hd onl).t0;
	return n;
}

init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	bufio = load Bufio Bufio->PATH;
	str = load String String->PATH;
	arg = load Arg Arg->PATH;
	wrap = load Wrap Wrap->PATH;
	wrap->init(bufio);
	arch = load Arch Arch->PATH;
	arch->init(bufio);
	daytime := load Daytime Daytime->PATH;
	now := daytime->now();
	# {
	#	for(i := 0; i < 21; i++){
	#		n := now+(i-9)*100000000;
	#		sys->print("%d	->	%s\n", n, wrap->now2string(n));
	#		if(wrap->string2now(wrap->now2string(n)) != n)
	#			sys->print("%d wrong\n", n);
	#	}
	# }
	daytime = nil;
	proto = load Proto Proto->PATH;
	protocaller = load Protocaller "$self";

	sys->pctl(Sys->NEWPGRP|Sys->FORKNS|Sys->FORKFD, nil);
	stderr = sys->fildes(2);
	if(arg == nil)
		error(sys->sprint("can't load %s: %r", Arg->PATH));
	name := "";
	desc = "inferno";
	tostdout := 0;
	not := 0;
	arg->init(args);
	while((c := arg->opt()) != 0)
		case c {
		'n' =>
			not = 1;
		'o' =>
			tostdout = 1;
		'p' =>
			protof = reqarg("proto file (-p)");
		'r' => 
			root = reqarg("root directory (-r)");
		's' =>
			oldroot = reqarg("source directory (-d)");
		'u' =>
			update = 1;
		'v' =>
			verb = 1;
		'x' =>
			xflag = 1;
		'N' =>
			uid = reqarg("user name (-U)");
		'G' =>
			gid = reqarg("group name (-G)");
		'd' or 'D' =>
			desc = reqarg("product description (-D)");
		't' =>
			rt := reqarg("package time (-t)");
			now = int rt;
		'i' =>
			notesf = reqarg("file (-i)");
		'R' =>
			remfile = reqarg("remove file (-R)");
		'P' =>
			arch->addperms(0);
		* =>
			usage();
		}

	args = arg->argv();
	if(args == nil)
		usage();
	if (tostdout || xflag) {
		bout = bufio->fopen(sys->fildes(1), Sys->OWRITE);
		if(bout == nil)
			error(sys->sprint("can't open standard output for archive: %r"));
	}
	else {
		# ar := sys->sprint("%ud", now);
		ar := wrap->now2string(now, 0);
		bout = bufio->create(ar, Sys->OWRITE, 8r664);
		if(bout == nil)
			error(sys->sprint("can't create %s for archive: %r", ar));
		sys->print("archiving package %s to %s\n", hd args, ar);
	}
	buf = array [buflen] of byte;
	name = hd args;
	if(update){
		if(not)
			notprefix = tl args;
		else
			prefix = tl args;
	}
	else if (tl args != nil)
		fatal("only one name allowed");
	if (!xflag)
		digest := wrapinit(name, now);
	fprint(stderr, "processing %s\n", protof);
	proto->rdproto(protof, oldroot, protocaller);
	if (!xflag)
		wrapend(digest);
	if (!xflag)
		fprint(stderr, "file system made\n");
	arch->putend(bout);
	exits();
}

protofile(new : string, old : string, d : ref Sys->Dir)
{
	if(xflag && bout != nil){
		bout.puts(sys->sprint("%s\t%d\t%bd\n", new, d.mtime, d.length));
		return;
	}
	d.uid = uid;
	d.gid = gid;
	if (!(d.mode & Sys->DMDIR)) {
		# if(verb)
		#	fprint(stderr, "%s\n", new);
		f := sys->open(old, Sys->OREAD);
		if(f == nil){
			warn(sys->sprint("can't open %s: %r", old));
			return;
		}
	}
	mkarch(new, old, d);
}

protoerr(lev : int, line : int, err : string)
{
	s := "line " + string line + " : " + err;
	case lev {
		WARN => warn(s);
		ERROR => error(s);
		FATAL => fatal(s);
	}
}

quit()
{
	if(bout != nil)
		bout.flush();
	exits();
}

reqarg(what: string): string
{
	if((o := arg->arg()) == nil){
		sys->fprint(stderr, "missing %s\n", what);
		exits();
	}
	return o;
}

puthdr(f : string, d: ref Dir)
{
	if (d.mode & Sys->DMDIR)
		d.length = big 0;
	arch->puthdr(bout, f, d);
}

error(s: string)
{
	fprint(stderr, "%s: %s\n", protof, s);
	quit();
}

fatal(s: string)
{
	fprint(stderr, "fatal: %s\n", s);
	exits();
}
 
warn(s: string)
{
	fprint(stderr, "%s: %s\n", protof, s);
}
	
usage()
{
	fprint(stderr, "usage: install/create [-ovx] [-N uid] [-G gid] [-r root] [-d desc] [-s src-fs] [-p proto] name\n");
	fprint(stderr, "or install/create -u [-ovx] [-N uid] [-G gid] [-r root] [-d desc] [-s src-fs] [-p proto] old-package [prefix ...]\n");
	exits();
}

wrapinit(name : string, t : int) : array of byte
{
	rmfile : string;
	rmfd: ref Sys->FD;

	if (uid == nil)
		uid = "inferno";
	if (gid == nil)
		gid = "inferno";
	if (update) {
		w = wrap->openwraphdr(name, root, nil, 0);
		if (w == nil)
			fatal("no such package found");
		# ignore any updates - NEW commented out
		# while (w.nu > 0 && w.u[w.nu-1].typ == wrap->UPD)
		#	w.nu--;

		# w.nu = 1;	NEW commented out
		if (protof == nil)
			protof = w.u[0].dir + "/proto";
		name = w.name;
	}
	else {
		if (protof == nil)
			fatal("proto file missing");
	}
	(md5file, md5fd) := opentemp("wrap.md5", t);
	if (md5fd == nil)
		fatal(sys->sprint("cannot create %s", md5file));
	keyring = load Keyring Keyring->PATH;
	md5s = keyring->md5(nil, 0, nil, nil);
	md5b := bufio->fopen(md5fd, Bufio->OWRITE);
	if (md5b == nil)
		fatal(sys->sprint("cannot open %s", md5file));
	fprint(stderr, "wrap pass %s\n", protof);
	obout := bout;
	bout = md5b;
	pass = 0;
	proto->rdproto(protof, oldroot, protocaller);
	bout.flush();
	bout = md5b = nil;
	digest := array[keyring->MD5dlen] of { * => byte 0 };
	keyring->md5(nil, 0, digest, md5s);
	md5s = nil;
	(md5sort, md5sfd) := opentemp("wrap.md5s", t);
	if (md5sfd == nil)
		fatal(sys->sprint("cannot create %s", md5sort));
	endc := chan of int;
	md5fd = nil;	# close md5file
	spawn fsort(md5sfd, md5file, endc);
	md5sfd = nil;
	res := <- endc;
	if (res < 0)
		fatal("sort failed");
	if (update) {
		(rmfile, rmfd) = opentemp("wrap.rm", t);
		if (rmfd == nil)
			fatal(sys->sprint("cannot create %s", rmfile));
		rmed: list of string;
		for(i := w.nu-1; i >= 0; i--){	# NEW does loop
			w.u[i].bmd5.seek(big 0, Bufio->SEEKSTART);
			while ((p := w.u[i].bmd5.gets('\n')) != nil) {
				if(prefix != nil && !wrap->match(p, prefix))
					continue;
				if(notprefix != nil && !wrap->notmatch(p, notprefix))
					continue;
				(q, nil) := str->splitl(p, " ");
				q = pathcat(root, q);
				(ok, nil) := sys->stat(q);
				if(ok < 0)
					(ok, nil) = sys->stat(n2o(q));
				if (len q >= 7 && q[len q - 7:] == "emu.new")	# quick hack for now
					continue;
				if (ok < 0){
					for(r := rmed; r != nil; r = tl r)	# NEW to avoid duplication
						if(hd r == q)
							break;
					if(r == nil){
						# sys->fprint(rmfd, "%s\n", q);
						rmed = q :: rmed;
					}
				}
			}
		}
		for(r := rmed; r != nil; r = tl r)
			sys->fprint(rmfd, "%s\n", hd r);
		if(remfile != nil){
			rfd := sys->open(remfile, Sys->OREAD);
			rbuf := array[128] of byte;
			for(;;){
				n := sys->read(rfd, rbuf, 128);
				if(n <= 0)
					break;
				sys->write(rmfd, rbuf, n);
			}
		}
		rmfd = nil;
		rmed = nil;
	}
	bout = obout;
	if (update)
		wrap->putwrap(bout, name, t, desc, w.tfull, prefix == nil && notprefix == nil, uid, gid);
	else
		wrap->putwrap(bout, name, t, desc, 0, 1, uid, gid);
	wrap->putwrapfile(bout, name, t, "proto", protof, uid, gid);
	wrap->putwrapfile(bout, name, t, "md5sum", md5sort, uid, gid);
	if (update)
		wrap->putwrapfile(bout, name, t, "remove", rmfile, uid, gid);
	if(notesf != nil)
		wrap->putwrapfile(bout, name, t, "notes", notesf, uid, gid);
	md5s = keyring->md5(nil, 0, nil, nil);
	pass = 1;
	return digest;
}

wrapend(digest : array of byte)
{
	digest0 := array[keyring->MD5dlen] of { * => byte 0 };
	keyring->md5(nil, 0, digest0, md5s);
	md5s = nil;
	if (wrap->memcmp(digest, digest0, keyring->MD5dlen) != 0)
		warn(sys->sprint("files changed underfoot %s %s", wrap->md5conv(digest), wrap->md5conv(digest0)));
}

mkarch(new : string, old : string, d : ref Dir)
{
	if(pass == 0 && old != new)
		onlist = (old, new) :: onlist;
	if(prefix != nil && !wrap->match(new, prefix))
		return;
	if(notprefix != nil && !wrap->notmatch(new, notprefix))
		return;
	digest := array[keyring->MD5dlen] of { * => byte 0 };
	wrap->md5file(old, digest);
	(ok, nil) := wrap->getfileinfo(w, new, digest, nil, nil);
	if (ok >= 0)
		return;
	n := array of byte new;
	keyring->md5(n, len n, nil, md5s);
	if (pass == 0) {
		bout.puts(sys->sprint("%s %s\n", new, wrap->md5conv(digest)));
		return;
	}
	if(verb)
		fprint(stderr, "%s\n", new);
	puthdr(new, d);
	if(!(d.mode & Sys->DMDIR)) {
		err := arch->putfile(bout, old, int d.length);
		if (err != nil)
			warn(err);
	}
}

fsort(fd : ref Sys->FD, file : string, c : chan of int)
{
	sys->pctl(Sys->FORKFD, nil);
	sys->dup(fd.fd, 1);
	cmd := "/dis/sort.dis";
	m := load Command cmd;
	if(m == nil) {
		c <-= -1;
		return;
	}
	m->init(nil, cmd :: file :: nil);
	c <-= 0;
}

tmpfiles: list of string;

opentemp(prefix: string, t: int): (string, ref Sys->FD)
{
	name := sys->sprint("/tmp/%s.%ud.%d", prefix, t, sys->pctl(0, nil));
	fd := sys->create(name, Sys->ORDWR, 8r666);
	# fd := sys->create(name, Sys->ORDWR | Sys->ORCLOSE, 8r666); not on Nt
	tmpfiles = name :: tmpfiles;
	return (name, fd);
}

exits()
{
	wrap->end();
	for( ; tmpfiles != nil; tmpfiles = tl tmpfiles)
		sys->remove(hd tmpfiles);
	exit;
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
