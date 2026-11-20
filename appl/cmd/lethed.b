implement Lethed;

#
# lethed [-v] [-A] [-C alg] [-a addr] [-u owner] [-t ticketkey] [-e lifetime]
#	[-w window] [-k keyfile ...] [-U userdir] [-s signers] [-r revoked] root
#
# A Lethe server (docs/lethe.md in Purgatorio, protocol lethe1): serves the
# tree at root, read-only, keeping no state between requests. Because root
# is a name in this process's name space, it can be anything mountable.
#
# With -k, -U or -s it gives tickets to clients whose Ed25519 key it trusts
# (Tauth, and Tauth2 with the hybrid X25519 + ML-KEM-768 exchange) and
# answers their sealed requests under their own names. With -A it also
# answers clear requests, as the user none.
#

include "sys.m";
	sys: Sys;
	Qid, Dir: import Sys;
include "draw.m";
include "arg.m";
include "dial.m";
	dial: Dial;
include "styx.m";
	styx: Styx;
include "readdir.m";
	readdir: Readdir;
include "ipints.m";
include "crypt.m";
	crypt: Crypt;
include "daytime.m";
	daytime: Daytime;

Lethed: module
{
	init: fn(nil: ref Draw->Context, args: list of string);
};

# outer frame types
Tauth:	con 1;
Rauth:	con 2;
Treq:	con 3;
Rreq:	con 4;
Rerror:	con 5;
Tclear:	con 9;
Rclear:	con 10;
Tauth2:	con 11;
Rauth2:	con 12;
Treqref:	con 13;

# rights
Rread:	con 1;
Rgrantable:	con 7;
Rrefs:	con 16r20;	# in a grant: this server takes ticket references
Rpq:	con 16r40;	# in a ticket: it came from the hybrid exchange

# kinds of proof
Kkey, Kcert, Khkey, Khcert, Kgocert: con iota;	# Kgocert is ours: kind 1 in Purgatorio-Go's Tauth2

Noncelen:	con 24;
Taglen:	con 16;
Treflen:	con 8;
Edsiglen:	con 64;
Hybsiglen:	con 3373;	# Ed25519 + ML-DSA-65
Hybkeylen:	con 1984;
Nrefs:	con 4096;

# inner ops
OTstat:	con 16r10;
ORstat:	con 16r11;
OTread:	con 16r12;
ORread:	con 16r13;
OTreaddir:	con 16r14;
ORreaddir:	con 16r15;
OTdigest:	con 16r16;
OTwalk:	con 16r18;
ORwalk:	con 16r19;
ORerror:	con 16r7f;

Maxframe:	con 65536;
Maxread:	con 32768;
Maxwalk:	con 64;
Maxelem:	con 255;
Maxpath:	con 1024;

Enotexist:	con "file does not exist";
Eperm:	con "permission denied";
Enotdir:	con "not a directory";
Eisdir:	con "file is a directory";
Ename:	con "file name syntax";
Ebadmsg:	con "bad lethe message";
Enotimpl:	con "not implemented";
Efailed:	con "authentication failed";
Erevoked:	con "certificate revoked";

# who a request is answered for
Who: adt {
	uname:	string;
	owner:	int;	# whether the user can own a file; a clear request cannot
	rights:	int;
	prefix:	string;
};

Ticket: adt {
	master:	array of byte;
	issued:	big;
	expires:	big;
	rights:	int;
	uname:	string;
	prefix:	string;
};

Tref: adt {
	tref:	array of byte;
	t:	ref Ticket;
};

Cert: adt {
	name:	string;
	key:	array of byte;
	expires:	big;
	signers:	list of (array of byte, array of byte);	# key, signature
};

Trust: adt {
	keys:	list of string;	# key ids held directly
	signers:	list of string;
	revoked:	list of string;
	damaged:	int;	# the revocation list did not parse: fail closed
};

root: string;
stderr: ref Sys->FD;
verbose := 0;
clear := 0;
sealedmode := 0;
needpq := 0;	# -C x25519mlkem768
needpqsig := 0;	# -C mldsa65
owner: string;	# -u: the name every file is owned by
lifetime := 3600;
window := 60;
tkey: array of byte;	# the ticket key
tkeyid: array of byte;
keyfiles: list of string;
userdir, signersfile, revokedfile: string;
refs: array of ref Tref;
rndc: chan of (int, chan of array of byte);

init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	stderr = sys->fildes(2);
	styx = load Styx Styx->PATH;
	dial = load Dial Dial->PATH;
	readdir = load Readdir Readdir->PATH;
	arg := load Arg Arg->PATH;
	if(styx == nil || dial == nil || readdir == nil || arg == nil)
		fatal("cannot load modules");
	styx->init();

	addr := "tcp!*!5640";
	tkeyfile: string;
	arg->init(args);
	arg->setusage("lethed [-v] [-A] [-C alg] [-a addr] [-u owner] [-t ticketkey] [-e lifetime] [-w window] [-k keyfile ...] [-U userdir] [-s signers] [-r revoked] root");
	while((o := arg->opt()) != 0)
		case o {
		'A' =>	clear = 1;
		'v' =>	verbose = 1;
		'a' =>	addr = arg->earg();
		'u' =>	owner = arg->earg();
		't' =>	tkeyfile = arg->earg();
		'e' =>	lifetime = int arg->earg();
		'w' =>	window = int arg->earg();
		'k' =>	keyfiles = arg->earg() :: keyfiles;
		'U' =>	userdir = arg->earg();
		's' =>	signersfile = arg->earg();
		'r' =>	revokedfile = arg->earg();
		'C' =>
			(nil, algs) := sys->tokenize(arg->earg(), "/");
			for(; algs != nil; algs = tl algs)
				case hd algs {
				"x25519" =>	;
				"x25519mlkem768" =>	needpq = 1;
				"mldsa65" =>	needpqsig = 1;
				* =>	fatal("unknown algorithm "+hd algs);
				}
		* =>	arg->usage();
		}
	args = arg->argv();
	if(len args != 1)
		arg->usage();
	sealedmode = keyfiles != nil || userdir != nil || signersfile != nil;
	if(!clear && !sealedmode)
		fatal("server trusts no keys: give -k, -U or -s, or -A for the clear mode");
	if(sealedmode){
		crypt = load Crypt Crypt->PATH;
		daytime = load Daytime Daytime->PATH;
		if(crypt == nil || daytime == nil)
			fatal("cannot load crypto modules");
		for(l := keyfiles; l != nil; l = tl l)
			if(keyfileid(hd l) == nil)
				fatal(hd l+": not a public key file");
		if(tkeyfile != nil){
			tkey = readall(tkeyfile);
			if(tkey == nil || len tkey != 32)
				fatal(tkeyfile+": not a ticket key (32 bytes)");
		}
		rndc = chan of (int, chan of array of byte);
		spawn rndproc(truerandom(32));
		if(tkey == nil)
			tkey = rnd(32);
		tkeyid = sha256(cat(array of byte "lethe1 ticket key", cat(array[1] of {byte 0}, tkey)))[0:4];
		refs = array[Nrefs] of ref Tref;
	}
	root = hd args;
	while(len root > 1 && root[len root-1] == '/')
		root = root[0:len root-1];
	(ok, d) := sys->stat(root);
	if(ok < 0 || (d.mode & Sys->DMDIR) == 0)
		fatal(sys->sprint("%s: not a directory", root));

	c := dial->announce(dial->netmkaddr(addr, "tcp", "5640"));
	if(c == nil)
		fatal(sys->sprint("announce %s: %r", addr));
	sys->fprint(stderr, "lethed: listening on %s\n", addr);
	spawn listener(c);
}

fatal(s: string)
{
	sys->fprint(stderr, "lethed: %s\n", s);
	raise "fail:error";
}

listener(c: ref Dial->Connection)
{
	for(;;){
		nc := dial->listen(c);
		if(nc == nil){
			sys->fprint(stderr, "lethed: listen: %r\n");
			return;
		}
		fd := dial->accept(nc);
		if(fd != nil)
			spawn conn(fd);
	}
}

#
# little-endian packing
#

p16(a: array of byte, o: int, v: int): int
{
	a[o] = byte v;
	a[o+1] = byte (v>>8);
	return o+2;
}

p32(a: array of byte, o: int, v: int): int
{
	a[o] = byte v;
	a[o+1] = byte (v>>8);
	a[o+2] = byte (v>>16);
	a[o+3] = byte (v>>24);
	return o+4;
}

pqid(a: array of byte, o: int, q: Qid): int
{
	a[o] = byte q.qtype;
	o = p32(a, o+1, q.vers);
	o = p32(a, o, int q.path);
	return p32(a, o, int (q.path>>32));
}

g16(a: array of byte, o: int): int
{
	return int a[o] | (int a[o+1] << 8);
}

g32(a: array of byte, o: int): int
{
	return int a[o] | (int a[o+1] << 8) | (int a[o+2] << 16) | (int a[o+3] << 24);
}

g64(a: array of byte, o: int): big
{
	return (big g32(a, o) & big 16rFFFFFFFF) | (big g32(a, o+4) << 32);
}

# gstr returns the string at o and the offset after it, or -1 if it does not fit
gstr(a: array of byte, o: int): (string, int)
{
	if(o < 0 || o+2 > len a)
		return (nil, -1);
	n := g16(a, o);
	if(o+2+n > len a)
		return (nil, -1);
	return (string a[o+2:o+2+n], o+2+n);
}

readn(fd: ref Sys->FD, a: array of byte): int
{
	for(n := 0; n < len a; ){
		m := sys->read(fd, a[n:], len a - n);
		if(m <= 0)
			return -1;
		n += m;
	}
	return n;
}

#
# one connection: a frame in, a frame out
#

conn(fd: ref Sys->FD)
{
	hdr := array[10] of byte;
	for(;;){
		if(readn(fd, hdr) < 0)
			return;
		size := g32(hdr, 0);
		if(size < 10 || size > Maxframe){
			reply(fd, Rerror, 0, estr(Ebadmsg));
			return;
		}
		body := array[size-10] of byte;
		if(readn(fd, body) < 0)
			return;
		id := g32(hdr, 6);
		if(int hdr[4] != 1){
			reply(fd, Rerror, id, estr("unknown lethe version"));
			continue;
		}
		typ := int hdr[5];
		out: array of byte;
		err: string;
		{
		case typ {
		Tclear =>
			if(clear)
				out = frame(Rclear, id, request(ref Who("none", 0, Rread, "/"), body));
			else
				err = "authentication required";
		Tauth or Tauth2 =>
			if(!sealedmode)
				err = "authentication not required";
			else if(typ == Tauth && needpq)
				err = "post-quantum key exchange required";
			else
				(out, err) = auth(typ == Tauth2, id, body);
		Treq or Treqref =>
			if(!sealedmode)
				err = "bad ticket";
			else
				(out, err) = sealedreq(typ, hdr, body);
		* =>
			err = Ebadmsg;
		}
		} exception {
		* =>
			# a frame that broke the decoder is a bad frame, not a dead server
			out = nil;
			err = Ebadmsg;
		}
		if(err != nil){
			if(verbose)
				sys->fprint(stderr, "lethed: refused: %s\n", err);
			out = frame(Rerror, id, estr(err));
		}
		if(sys->write(fd, out, len out) != len out)
			return;
	}
}

# header is the first 10 bytes of a frame of size bytes
header(typ, id, size: int): array of byte
{
	h := array[10] of byte;
	p32(h, 0, size);
	h[4] = byte 1;
	h[5] = byte typ;
	p32(h, 6, id);
	return h;
}

frame(typ, id: int, body: array of byte): array of byte
{
	return cat(header(typ, id, 10+len body), body);
}

reply(fd: ref Sys->FD, typ, id: int, body: array of byte)
{
	f := frame(typ, id, body);
	sys->write(fd, f, len f);
}

# estr is the body of an outer Rerror: ename s[2]
estr(e: string): array of byte
{
	b := array of byte e;
	a := array[2+len b] of byte;
	p16(a, 0, len b);
	a[2:] = b;
	return a;
}

# ierr is an inner Rerror
ierr(e: string): array of byte
{
	b := array of byte e;
	a := array[1+2+len b] of byte;
	a[0] = byte ORerror;
	p16(a, 1, len b);
	a[3:] = b;
	return a;
}

request(who: ref Who, b: array of byte): array of byte
{
	if(len b < 1)
		return ierr(Ebadmsg);
	op := int b[0];
	if(verbose)
		sys->fprint(stderr, "lethed: op %#x, %d bytes\n", op, len b);
	case op {
	OTstat =>
		(path, o) := gstr(b, 1);
		if(o != len b)
			return ierr(Ebadmsg);
		return rstat(who, path);
	OTread =>
		(path, o) := gstr(b, 1);
		if(o < 0 || o+8+4+1+4 != len b)
			return ierr(Ebadmsg);
		return rread(who, path, g64(b, o), g32(b, o+8), int b[o+12], g32(b, o+13));
	OTreaddir =>
		(path, o) := gstr(b, 1);
		(cookie, o2) := gstr(b, o);
		if(o2 < 0 || o2+4 != len b)
			return ierr(Ebadmsg);
		return rreaddir(who, path, cookie, g32(b, o2));
	OTwalk =>
		(path, o) := gstr(b, 1);
		if(o < 0 || o+2 > len b)
			return ierr(Ebadmsg);
		n := g16(b, o);
		o += 2;
		if(n > Maxwalk)
			return ierr(Ebadmsg);
		names := array[n] of string;
		for(i := 0; i < n; i++){
			(names[i], o) = gstr(b, o);
			if(o < 0)
				return ierr(Ebadmsg);
		}
		if(o != len b)
			return ierr(Ebadmsg);
		return rwalk(who, path, names);
	}
	if(op >= 16r20 && op <= 16r2f)
		return ierr(Eperm);	# writes: the tree is read-only
	return ierr(Enotimpl);
}

#
# names and permission
#

okelem(s: string): int
{
	if(s == nil || s == "" || s == "." || s == ".." || len array of byte s > Maxelem)
		return 0;
	for(i := 0; i < len s; i++)
		if(s[i] == '/' || s[i] == 0)
			return 0;
	return 1;
}

# split checks a path and returns its elements; ok is 0 for a bad path
split(path: string): (int, list of string)
{
	if(path == nil || len path == 0 || path[0] != '/' || len array of byte path > Maxpath)
		return (0, nil);
	if(path == "/")
		return (1, nil);
	if(path[len path-1] == '/')
		return (0, nil);
	(nil, l) := sys->tokenize(path, "/");
	n := 0;
	for(t := l; t != nil; t = tl t){
		if(!okelem(hd t))
			return (0, nil);
		n += 1 + len hd t;
	}
	if(n != len path)	# an empty element (//) was dropped by tokenize
		return (0, nil);
	return (1, l);
}

# syserr turns the system's error string into the bare Inferno string
syserr(): string
{
	e := sys->sprint("%r");
	if(len e > 0 && e[0] == '\''){
		for(i := 1; i < len e; i++)
			if(e[i] == '\''){
				if(i+2 <= len e)
					e = e[i+2:];
				break;
			}
	}
	if(e == "does not exist" || e == "directory entry not found" || e == "No such file or directory")
		return Enotexist;
	return e;
}

# allowed says whether who may use d for bit (4 read, 1 search): the
# owner's bits for its owner, else the other bits.
allowed(who: ref Who, d: ref Dir, bit: int): int
{
	if(who.owner && d.uid == who.uname)
		return (d.mode>>6) & bit;
	return d.mode & bit;
}

within(p, prefix: string): int
{
	if(prefix == "/" || p == prefix)
		return 1;
	return len p > len prefix && p[0:len prefix] == prefix && p[len prefix] == '/';
}

dostat(name: string): (int, ref Dir)
{
	(r, d) := sys->stat(name);
	if(r < 0)
		return (r, nil);
	if(owner != nil)
		d.uid = owner;
	return (0, ref d);
}

# lookup stats path as who may: the ticket must reach it, and every
# directory above it must be searchable. It returns the name in this name
# space and the entry.
lookup(who: ref Who, path: string): (string, ref Dir, string)
{
	(ok, elems) := split(path);
	if(!ok)
		return (nil, nil, Ename);
	if((who.rights & Rread) == 0 || !within(path, who.prefix))
		return (nil, nil, Eperm);
	name := root;
	(r, d) := dostat(name);
	if(r < 0)
		return (nil, nil, syserr());
	for(; elems != nil; elems = tl elems){
		if((d.mode & Sys->DMDIR) == 0)
			return (nil, nil, Enotdir);
		if(!allowed(who, d, 1))
			return (nil, nil, Eperm);
		name += "/" + hd elems;
		(r, d) = dostat(name);
		if(r < 0)
			return (nil, nil, syserr());
	}
	return (name, d, nil);
}

#
# the operations
#

rstat(who: ref Who, path: string): array of byte
{
	(nil, d, err) := lookup(who, path);
	if(err != nil)
		return ierr(err);
	if(path == "/")
		d.name = "/";
	st := styx->packdir(*d);
	a := array[1+len st] of byte;
	a[0] = byte ORstat;
	a[1:] = st;
	return a;
}

rread(who: ref Who, path: string, offset: big, count, cond, vers: int): array of byte
{
	(name, d, err) := lookup(who, path);
	if(err != nil)
		return ierr(err);
	if(d.mode & Sys->DMDIR)
		return ierr(Eisdir);
	if(!allowed(who, d, 4))
		return ierr(Eperm);
	if(count < 0 || count > Maxread)
		count = Maxread;
	data := array[0] of byte;
	unchanged := 0;
	if(cond == 1 && vers == d.qid.vers)
		unchanged = 1;
	else{
		fd := sys->open(name, Sys->OREAD);
		if(fd == nil)
			return ierr(syserr());
		# the entry and the data must be of one version
		(r, nd) := sys->fstat(fd);
		if(r < 0)
			return ierr(syserr());
		if(owner != nil)
			nd.uid = owner;
		d = ref nd;
		buf := array[count] of byte;
		n := 0;
		while(n < count){
			m := sys->pread(fd, buf[n:], count-n, offset+big n);
			if(m < 0)
				return ierr(syserr());
			if(m == 0)
				break;
			n += m;
		}
		data = buf[0:n];
	}
	a := array[1+13+1+4+len data] of byte;
	a[0] = byte ORread;
	o := pqid(a, 1, d.qid);
	a[o++] = byte unchanged;
	o = p32(a, o, len data);
	a[o:] = data;
	return a;
}

rreaddir(who: ref Who, path, cookie: string, count: int): array of byte
{
	(name, d, err) := lookup(who, path);
	if(err != nil)
		return ierr(err);
	if((d.mode & Sys->DMDIR) == 0)
		return ierr(Enotdir);
	if(!allowed(who, d, 4))
		return ierr(Eperm);
	if(count < 0 || count > Maxread)
		count = Maxread;
	# names in byte order, so a page resumes after the last name sent
	(dirs, n) := readdir->init(name, Readdir->NAME|Readdir->COMPACT);
	if(n < 0)
		return ierr(syserr());
	buf := array[count] of byte;
	used := 0;
	last := "";
	more := 0;
	for(i := 0; i < n; i++){
		if(cookie != nil && cookie != "" && dirs[i].name <= cookie)
			continue;
		if(owner != nil)
			dirs[i].uid = owner;
		st := styx->packdir(*dirs[i]);
		if(used + len st > count){
			more = 1;
			break;
		}
		buf[used:] = st;
		used += len st;
		last = dirs[i].name;
	}
	if(!more)
		last = "";
	lb := array of byte last;
	a := array[1+13+2+len lb+4+used] of byte;
	a[0] = byte ORreaddir;
	o := pqid(a, 1, d.qid);
	o = p16(a, o, len lb);
	a[o:] = lb;
	o += len lb;
	o = p32(a, o, used);
	a[o:] = buf[0:used];
	return a;
}

rwalk(who: ref Who, path: string, names: array of string): array of byte
{
	(name, d, err) := lookup(who, path);
	if(err != nil)
		return ierr(err);	# a failure at path itself is the plain error
	if(path == "/")
		d.name = "/";
	qids := array[len names] of Qid;
	nq := 0;
	ename := "";
	for(i := 0; i < len names; i++){
		if(!okelem(names[i])){
			ename = Ename;
			break;
		}
		if((d.mode & Sys->DMDIR) == 0){
			ename = Enotdir;
			break;
		}
		if(!allowed(who, d, 1)){
			ename = Eperm;
			break;
		}
		name += "/" + names[i];
		(r, nd) := dostat(name);
		if(r < 0){
			ename = syserr();
			break;
		}
		d = nd;
		qids[nq++] = d.qid;
	}
	st := array[0] of byte;
	if(ename == "")
		st = styx->packdir(*d);
	eb := array of byte ename;
	a := array[1+2+13*nq+2+len eb+len st] of byte;
	a[0] = byte ORwalk;
	o := p16(a, 1, nq);
	for(i = 0; i < nq; i++)
		o = pqid(a, o, qids[i]);
	o = p16(a, o, len eb);
	a[o:] = eb;
	o += len eb;
	a[o:] = st;
	return a;
}

#
# The sealed mode: tickets, and requests under them.
#

cat(a, b: array of byte): array of byte
{
	c := array[len a + len b] of byte;
	c[0:] = a;
	c[len a:] = b;
	return c;
}

p64(a: array of byte, o: int, v: big): int
{
	o = p32(a, o, int v);
	return p32(a, o, int (v>>32));
}

pstr(a: array of byte, o: int, s: string): int
{
	b := array of byte s;
	o = p16(a, o, len b);
	a[o:] = b;
	return o+len b;
}

eq(a, b: array of byte): int
{
	if(len a != len b)
		return 0;
	for(i := 0; i < len a; i++)
		if(a[i] != b[i])
			return 0;
	return 1;
}

sha256(a: array of byte): array of byte
{
	d := array[32] of byte;
	crypt->sha256(a, len a, d, nil);
	return d;
}

# expand is HKDF-Expand(prk, info, 32): one block of HMAC-SHA256
expand(prk: array of byte, info: string): array of byte
{
	ipad := array[64] of {* => byte 16r36};
	opad := array[64] of {* => byte 16r5c};
	for(i := 0; i < len prk; i++){
		ipad[i] ^= prk[i];
		opad[i] ^= prk[i];
	}
	inner := sha256(cat(ipad, cat(array of byte info, array[1] of {byte 1})));
	return sha256(cat(opad, inner));
}

# truerandom reads n bytes of /dev/random, which is slow (tens of bytes a
# second in emu) and may return fewer than asked
truerandom(n: int): array of byte
{
	fd := sys->open("/dev/random", Sys->OREAD);
	if(fd == nil)
		fatal(sys->sprint("/dev/random: %r"));
	buf := array[n] of byte;
	if(readn(fd, buf) < 0)
		fatal(sys->sprint("/dev/random: %r"));
	return buf;
}

# rndproc hands out random bytes, for keys and nonces: SHA-256 of a seed
# from /dev/random and a counter. The seed is replaced after each use, so
# what was given out cannot be worked out from what is held now. One proc
# owns the state, so no two callers get the same bytes.
rndproc(seed: array of byte)
{
	ctr := big 0;
	c := array[9] of byte;
	for(;;){
		(n, rc) := <-rndc;
		out := array[n] of byte;
		for(o := 0; o < n; o += 32){
			p64(c, 0, ctr++);
			c[8] = byte 0;
			d := sha256(cat(seed, c));
			m := n-o;
			if(m > 32)
				m = 32;
			out[o:] = d[0:m];
		}
		c[8] = byte 1;
		seed = sha256(cat(seed, c));
		rc <-= out;
	}
}

rnd(n: int): array of byte
{
	rc := chan of array of byte;
	rndc <-= (n, rc);
	return <-rc;
}

now(): big
{
	return big daytime->now();
}

readall(name: string): array of byte
{
	fd := sys->open(name, Sys->OREAD);
	if(fd == nil)
		return nil;
	buf := array[0] of byte;
	b := array[8192] of byte;
	while((n := sys->read(fd, b, len b)) > 0){
		if(len buf + n > 1024*1024)
			return nil;
		buf = cat(buf, b[0:n]);
	}
	if(n < 0)
		return nil;
	return buf;
}

hex(a: array of byte): string
{
	s := "";
	for(i := 0; i < len a; i++)
		s += sys->sprint("%.2ux", int a[i]);
	return s;
}

hexv(c: int): int
{
	if(c >= '0' && c <= '9')
		return c-'0';
	if(c >= 'a' && c <= 'f')
		return c-'a'+10;
	return -1;
}

# unhex decodes exactly n bytes of lower-case hex, or returns nil
unhex(s: string, n: int): array of byte
{
	if(len s != 2*n)
		return nil;
	a := array[n] of byte;
	for(i := 0; i < n; i++){
		hi := hexv(s[2*i]);
		lo := hexv(s[2*i+1]);
		if(hi < 0 || lo < 0)
			return nil;
		a[i] = byte ((hi<<4)|lo);
	}
	return a;
}

#
# Signatures by kind. Kinds 0 and 1 are Ed25519 (a key, a pgcert1); kinds 2
# and 3 are the hybrid Ed25519 + ML-DSA-65 (a 1,984-byte key, a pgcert2).
# These three functions are the only places that know the difference.
#

# siglen is the length of a proof's signature, or -1 for an unknown kind
siglen(kind: int): int
{
	case kind {
	Kkey or Kcert =>
		return Edsiglen;
	Khkey or Khcert or Kgocert =>
		return Hybsiglen;
	}
	return -1;
}

# keyid names a key in a trust list: 64 hex digits for an Ed25519 key,
# mldsa65: and the hex of SHA-256("pghybrid1 key" 0 || key) for a hybrid one
keyid(key: array of byte): string
{
	case len key {
	32 =>
		return hex(key);
	Hybkeylen =>
		return "mldsa65:"+hex(sha256(cat(array of byte "pghybrid1 key", cat(array[1] of {byte 0}, key))));
	}
	return nil;
}

# sigverify checks sig over msg by key, whose length says which kind it is.
# A hybrid key is an Ed25519 key and an ML-DSA-65 key, and its signature
# one of each over "pghybrid1" 0 || msg; both are checked, and both must hold.
sigverify(key, msg, sig: array of byte): int
{
	case len key {
	32 =>
		return len sig == Edsiglen && crypt->ed25519verify(key, msg, sig);
	Hybkeylen =>
		if(len sig != Hybsiglen)
			return 0;
		m := cat(array of byte "pghybrid1", cat(array[1] of {byte 0}, msg));
		ok := crypt->ed25519verify(key[0:32], m, sig[0:Edsiglen]);
		ok &= crypt->mldsa65verify(key[32:], m, nil, sig[Edsiglen:]);
		return ok;
	}
	return 0;
}

#
# Trust: the files named on the command line, read at every Tauth.
#

keyfileid(name: string): string
{
	k := readall(name);
	if(k == nil)
		return nil;
	return keyid(k);
}

# idof parses one id of a key list: 64 hex digits, perhaps after mldsa65:
# (a hybrid key's id as Purgatorio writes it) or pq: (as Purgatorio-Go does)
idof(s: string): string
{
	h := s;
	if(len s > 8 && s[0:8] == "mldsa65:")
		h = s[8:];
	else if(len s > 3 && s[0:3] == "pq:")
		h = s[3:];
	if(unhex(h, 32) == nil)
		return nil;
	return s;
}

# keylist parses a key list: one id a line, then perhaps a comment. With
# strict set a bad line spoils the list (ok is 0); otherwise it is skipped.
keylist(name: string, strict: int): (list of string, int)
{
	b := readall(name);
	if(b == nil)
		return (nil, 0);
	(nil, lines) := sys->tokenize(string b, "\n");
	l: list of string;
	for(; lines != nil; lines = tl lines){
		line := hd lines;
		if(len line > 0 && line[len line-1] == '\r')
			line = line[0:len line-1];
		(n, w) := sys->tokenize(line, " \t");
		if(n == 0 || line[0] == '#')
			continue;
		id: string;
		if(line[0] != ' ' && line[0] != '\t')
			id = idof(hd w);
		if(id == nil){
			if(strict)
				return (nil, 0);
			continue;
		}
		l = id :: l;
	}
	return (l, 1);
}

trust(uname: string): ref Trust
{
	t := ref Trust(nil, nil, nil, 0);
	for(l := keyfiles; l != nil; l = tl l)
		if((id := keyfileid(hd l)) != nil)
			t.keys = id :: t.keys;
	if(userdir != nil && (uid := keyfileid(userdir+"/"+uname+"/key.pub")) != nil)
		t.keys = uid :: t.keys;
	if(signersfile != nil)
		(t.signers, nil) = keylist(signersfile, 0);
	if(revokedfile != nil){
		(ok, nil) := sys->stat(revokedfile);
		if(ok >= 0){
			# there but unreadable or malformed: every proof fails
			(rl, good) := keylist(revokedfile, 1);
			t.revoked = rl;
			t.damaged = !good;
		}
	}
	return t;
}

# haskey says whether a list names key. An Ed25519 key is listed by its
# hex. A hybrid key is listed by a fingerprint behind a marker, of which
# there are two: mldsa65: and SHA-256("pghybrid1 key" 0 || key), or pq:
# and SHA-256("pgkey2" 0 || key). Either way an entry has a kind, and a
# hybrid entry is never matched by an Ed25519 key.
haskey(l: list of string, key: array of byte): int
{
	if(has(l, keyid(key)))
		return 1;
	if(len key == Hybkeylen)
		return has(l, "pq:"+hex(sha256(cat(array of byte "pgkey2", cat(array[1] of {byte 0}, key)))));
	return 0;
}

has(l: list of string, s: string): int
{
	for(; l != nil; l = tl l)
		if(hd l == s)
			return 1;
	return 0;
}

validname(s: string): int
{
	if(s == nil || s == "" || s == "." || s == ".." || len array of byte s > 255)
		return 0;
	for(i := 0; i < len s; i++){
		c := s[i];
		if(c <= ' ' || c == 16r7f || c == '/' || c == ':' || c == 16ra0 || c == 16r85)
			return 0;
	}
	return 1;
}

# parsecert parses a certificate line of the kind asked for:
#	pgcert1 <name> <key> <expires> <signer>:<signature> ...
#	pgcert2 <name> mldsa65:<key> <expires> mldsa65:<signer>:<signature> ...
# A pgcert1 has Ed25519 keys and signatures throughout and at most 8
# signatures; a pgcert2 has hybrid ones, each key written whole, and at
# most 4. Purgatorio-Go writes a pgcert2 of its own (form Cgo): the same
# fields and the same signed body, but in unpadded base64url with no
# markers, and at most 8 signatures:
#	pgcert2 <name> <key> <expires> <signer>:<signature> ...
# It is strict: the line must be what the encoder writes.
C1, C2, Cgo: con iota;
parsecert(b: array of byte, form: int): ref Cert
{
	tag := "pgcert1";
	mark := "";
	klen := 32;
	slen := Edsiglen;
	maxsig := 8;
	if(form != C1){
		tag = "pgcert2";
		klen = Hybkeylen;
		slen = Hybsiglen;
	}
	if(form == C2){
		mark = "mldsa65:";
		maxsig = 4;
	}
	# the lengths of a key and a signature in text
	kt := 2*klen;
	st := 2*slen;
	if(form == Cgo){
		kt = (klen*4+2)/3;
		st = (slen*4+2)/3;
	}
	if(len b > 0 && b[len b-1] == byte '\n')
		b = b[0:len b-1];
	text := string b;
	if(len array of byte text != len b)
		return nil;
	w: list of string;
	j := 0;
	for(i := 0; i <= len text; i++)
		if(i == len text || text[i] == ' '){
			w = text[j:i] :: w;
			j = i+1;
		}
	words: list of string;
	for(; w != nil; w = tl w)
		words = hd w :: words;
	if(len words < 5 || len words > 4+maxsig || hd words != tag)
		return nil;
	words = tl words;
	c := ref Cert(hd words, nil, big 0, nil);
	if(!validname(c.name))
		return nil;
	words = tl words;
	c.key = untext(unmark(hd words, mark), klen, form);
	if(c.key == nil)
		return nil;
	words = tl words;
	e := hd words;
	if(e == "" || len e > 20 || len e > 1 && e[0] == '0')
		return nil;
	for(i = 0; i < len e; i++)
		if(e[i] < '0' || e[i] > '9')
			return nil;
	c.expires = big e;
	if(string c.expires != e)
		return nil;
	sl: list of (array of byte, array of byte);
	for(words = tl words; words != nil; words = tl words){
		s := unmark(hd words, mark);
		if(len s != kt+1+st || s[kt] != ':')
			return nil;
		signer := untext(s[0:kt], klen, form);
		sig := untext(s[kt+1:], slen, form);
		if(signer == nil || sig == nil)
			return nil;
		for(t := sl; t != nil; t = tl t){
			(k, nil) := hd t;
			if(eq(k, signer))
				return nil;
		}
		sl = (signer, sig) :: sl;
	}
	c.signers = sl;
	return c;
}

# untext decodes n bytes written in hex or, for Purgatorio-Go's
# certificates, in unpadded base64url; nil unless s is exactly that
untext(s: string, n: int, form: int): array of byte
{
	if(form != Cgo)
		return unhex(s, n);
	if(len s != (n*4+2)/3)
		return nil;
	a := array[n] of byte;
	o := 0;
	acc := 0;
	bits := 0;
	for(i := 0; i < len s; i++){
		c := s[i];
		v: int;
		if(c >= 'A' && c <= 'Z')
			v = c-'A';
		else if(c >= 'a' && c <= 'z')
			v = c-'a'+26;
		else if(c >= '0' && c <= '9')
			v = c-'0'+52;
		else if(c == '-')
			v = 62;
		else if(c == '_')
			v = 63;
		else
			return nil;
		acc = ((acc<<6)|v) & 16rffff;
		bits += 6;
		if(bits >= 8){
			bits -= 8;
			if(o >= n)
				return nil;
			a[o++] = byte (acc>>bits);
		}
	}
	# the bits left over must be zero, as a strict decoder wants
	if(o != n || (acc & ((1<<bits)-1)) != 0)
		return nil;
	return a;
}

# unmark removes the marker a hybrid key carries in text; a word without
# it comes back empty, which is no key
unmark(s, mark: string): string
{
	if(mark == nil)
		return s;
	if(len s < len mark || s[0:len mark] != mark)
		return "";
	return s[len mark:];
}

# certbody is what each signer of a certificate signs; the certificate's
# kind is that of its key
certbody(c: ref Cert): array of byte
{
	nb := array of byte c.name;
	a := array[8+1+len nb+len c.key+8] of byte;
	if(len c.key == Hybkeylen)
		a[0:] = array of byte "pgcert2";
	else
		a[0:] = array of byte "pgcert1";
	a[7] = byte 0;
	a[8] = byte len nb;
	a[9:] = nb;
	a[9+len nb:] = c.key;
	p64(a, 9+len nb+len c.key, c.expires);
	return a;
}

# checkcert says whether the trust takes c for uname: nil, or the error
checkcert(t: ref Trust, c: ref Cert, uname: string): string
{
	if(t.damaged || haskey(t.revoked, c.key))
		return Erevoked;
	if(haskey(t.keys, c.key))
		return nil;
	if(uname != c.name)
		return "certificate name mismatch";
	n := now();
	if(c.expires != big 0 && n >= c.expires)
		return "certificate expired";
	body := certbody(c);
	revoked := 0;
	for(l := c.signers; l != nil; l = tl l){
		(signer, sig) := hd l;
		if(haskey(t.signers, signer) && sigverify(signer, body, sig)){
			if(!haskey(t.revoked, signer))
				return nil;
			revoked = 1;
		}
	}
	if(revoked)
		return Erevoked;
	return "untrusted signer";
}

# checkproof checks a Tauth's kind, body and signature over signed: nil,
# or the error.
checkproof(t: ref Trust, kind: int, body, sig, signed: array of byte, uname: string): string
{
	case kind {
	Kkey or Khkey =>
		if(t.damaged)
			return Erevoked;
		if(len body != 32 && kind == Kkey || len body != Hybkeylen && kind == Khkey)
			return Efailed;
		if(needpqsig && kind == Kkey)
			return "post-quantum signature required";
		if(!haskey(t.keys, body) || !sigverify(body, signed, sig))
			return Efailed;
		if(haskey(t.revoked, body))
			return Erevoked;
		return nil;
	Kcert =>
		c := parsecert(body, C1);
		if(c == nil)
			return Efailed;
		if(needpqsig)
			return "post-quantum signature required";
		if(!sigverify(c.key, signed, sig))
			return Efailed;
		return checkcert(t, c, uname);
	Khcert or Kgocert =>
		form := C2;
		if(kind == Kgocert)
			form = Cgo;
		c := parsecert(body, form);
		if(c == nil || !sigverify(c.key, signed, sig))
			return Efailed;
		return checkcert(t, c, uname);
	}
	return Efailed;
}

# okek says whether ek is a well-formed ML-KEM-768 encapsulation key:
# every 12-bit coefficient below q, as FIPS 203 has the encapsulator check
okek(ek: array of byte): int
{
	if(len ek != Crypt->MLKEM768eklen)
		return 0;
	for(i := 0; i+2 < 1152; i += 3){
		c0 := int ek[i] | ((int ek[i+1] & 16rf) << 8);
		c1 := (int ek[i+1] >> 4) | (int ek[i+2] << 4);
		if(c0 >= 3329 || c1 >= 3329)
			return 0;
	}
	return 1;
}

# auth answers a Tauth (or a Tauth2, when hybrid) with a whole Rauth
# frame, or an error for an outer Rerror.
#	Tauth  = eph_c[32] rights u8 prefix s[2] uname s[2] kind u8 body s[2] signature
#	Tauth2 = eph_c[32] ek[1184] rights ... signature
auth(hybrid: int, id: int, b: array of byte): (array of byte, string)
{
	o := 32;
	if(hybrid)
		o += Crypt->MLKEM768eklen;
	if(len b < o+1)
		return (nil, Ebadmsg);
	ephc := b[0:32];
	ek := b[32:o];
	rights := int b[o++];
	prefix, uname: string;
	(prefix, o) = gstr(b, o);
	(uname, o) = gstr(b, o);
	if(o < 0 || o+1+2 > len b)
		return (nil, Ebadmsg);
	kind := int b[o++];
	n := g16(b, o);
	o += 2;
	if(o+n > len b)
		return (nil, Ebadmsg);
	body := b[o:o+n];
	o += n;
	sig := b[o:];
	# Purgatorio-Go's Tauth2 has the same fields but counts its kinds from
	# the hybrid key (0 a hybrid key, 1 its pgcert2) and gives the signature
	# a length. The two layouts cannot be confused: with kind 0 or 1 ours
	# ends in a 64-byte signature and Go's in a counted 3,373-byte one, and
	# the kind byte and the body are under the signature in both.
	if(kind > Khcert)
		return (nil, Efailed);
	if(hybrid && (kind == Kkey || kind == Kcert) && len sig == 2+Hybsiglen && g16(sig, 0) == Hybsiglen){
		sig = sig[2:];
		if(kind == Kkey)
			kind = Khkey;
		else
			kind = Kgocert;
	}
	if(siglen(kind) >= 0 && len sig != siglen(kind) || siglen(kind) < 0 && len sig != Edsiglen && len sig != Hybsiglen)
		return (nil, Ebadmsg);
	(okp, nil) := split(prefix);
	if(!okp || !validname(uname))
		return (nil, Efailed);
	t := trust(uname);
	if(t.keys == nil && t.signers == nil){
		if(clear)
			return (nil, "authentication not required");
		return (nil, "server trusts no keys");
	}
	context := "lethe1 auth";
	if(hybrid)
		context = "lethe2 auth";
	signed := cat(cat(array of byte context, array[1] of {byte 0}), b[0:o]);
	if(siglen(kind) < 0)
		return (nil, Efailed);
	err := checkproof(t, kind, body, sig, signed, uname);
	if(err != nil)
		return (nil, err);
	granted := rights & Rread & Rgrantable;
	if(granted == 0)
		return (nil, Eperm);

	e := rnd(32);
	ephs := crypt->x25519base(e);
	x := crypt->x25519(e, ephc);
	zero := 1;
	for(i := 0; x != nil && i < len x; i++)
		if(x[i] != byte 0)
			zero = 0;
	if(zero)
		return (nil, Efailed);
	ct := array[0] of byte;
	ikm := x;
	label := "lethe1 master";
	pq := 0;
	if(hybrid){
		if(!okek(ek))
			return (nil, Efailed);
		k: array of byte;
		(ct, k) = crypt->mlkem768encap(ek);
		if(ct == nil || k == nil)
			return (nil, Efailed);
		ikm = cat(k, x);	# the ML-KEM secret first
		label = "lethe2 master";
		pq = Rpq;
	}
	transcript := cat(cat(signed, ephs), ct);
	master := crypt->hkdfsha256(sha256(transcript), ikm, array of byte label, 32);
	tn := now();
	tk := ref Ticket(master, tn, tn + big lifetime, granted|pq, uname, prefix);
	sealed := sealticket(tk);
	# grant = now u64 expires u64 rights u8 prefix s[2] ticket s[2]
	pb := array of byte prefix;
	grant := array[8+8+1+2+len pb+2+len sealed] of byte;
	g := p64(grant, 0, tk.issued);
	g = p64(grant, g, tk.expires);
	grant[g++] = byte (granted|Rrefs);
	g = pstr(grant, g, prefix);
	g = p16(grant, g, len sealed);
	grant[g:] = sealed;
	nonce := rnd(Noncelen);
	typ := Rauth2;
	if(!hybrid){
		# say, under the seal, that this server could have done the hybrid exchange
		nonce[Noncelen-8:] = array of byte "lethe2pq";
		typ = Rauth;
	}
	hdr := header(typ, id, 10+32+len ct+Noncelen+len grant+Taglen);
	s2c := expand(master, "lethe1 s2c");
	sg := crypt->xchachapolyseal(s2c, nonce, cat(cat(hdr, ephs), ct), grant);
	if(sg == nil)
		return (nil, Efailed);
	if(verbose)
		sys->fprint(stderr, "lethed: ticket for %s, rights %d, prefix %s, %s exchange\n", uname, granted, prefix, label[0:6]);
	return (cat(cat(cat(cat(hdr, ephs), ct), nonce), sg), nil);
}

# ticket = keyid u32 || nonce[24] || seal(ticket key, "lethe1 ticket" 0 || keyid, plain)
# plain  = master[32] issued u64 expires u64 rights u8 uname s[2] prefix s[2]
ticketaad(): array of byte
{
	return cat(cat(array of byte "lethe1 ticket", array[1] of {byte 0}), tkeyid);
}

sealticket(t: ref Ticket): array of byte
{
	ub := array of byte t.uname;
	pb := array of byte t.prefix;
	plain := array[32+8+8+1+2+len ub+2+len pb] of byte;
	plain[0:] = t.master;
	o := p64(plain, 32, t.issued);
	o = p64(plain, o, t.expires);
	plain[o++] = byte t.rights;
	o = pstr(plain, o, t.uname);
	pstr(plain, o, t.prefix);
	nonce := rnd(Noncelen);
	return cat(cat(tkeyid, nonce), crypt->xchachapolyseal(tkey, nonce, ticketaad(), plain));
}

openticket(b: array of byte): (ref Ticket, string)
{
	if(len b < 4+Noncelen+Taglen || len b > 4+Noncelen+Taglen+32+17+2+255+2+Maxpath)
		return (nil, "bad ticket");
	if(!eq(b[0:4], tkeyid))
		return (nil, "unknown ticket key");
	plain := crypt->xchachapolyopen(tkey, b[4:4+Noncelen], ticketaad(), b[4+Noncelen:]);
	if(plain == nil || len plain < 32+8+8+1)
		return (nil, "bad ticket");
	t := ref Ticket(plain[0:32], g64(plain, 32), g64(plain, 40), int plain[48], nil, nil);
	o: int;
	(t.uname, o) = gstr(plain, 49);
	(t.prefix, o) = gstr(plain, o);
	if(o != len plain)
		return (nil, "bad ticket");
	return (t, nil);
}

# The tickets requests have opened under, by reference: soft state, one
# ticket a slot, so a newer ticket may push an older one out. A client whose
# ticket is gone is told so and sends the ticket again.
refslot(tref: array of byte): int
{
	return (int tref[0] | (int tref[1] << 8)) % Nrefs;
}

tref(ticket: array of byte): array of byte
{
	return sha256(cat(cat(array of byte "lethe1 ticket ref", array[1] of {byte 0}), ticket))[0:Treflen];
}

# sealedreq answers a Treq or Treqref with a whole Rreq frame, or an error
# for an outer Rerror.
#	Treq    = ticket s[2] nonce[24] seal(c2s, header || ticket, time u64 || request)
#	Treqref = tref[8] nonce[24] seal(c2s, header || tref, time u64 || request)
#	Rreq    = nonce[24] seal(s2c, header || request nonce, reply)
sealedreq(typ: int, hdr, b: array of byte): (array of byte, string)
{
	tk: ref Ticket;
	name: array of byte;	# the ticket or its reference, as the request names it
	o: int;
	if(typ == Treq){
		if(len b < 2)
			return (nil, Ebadmsg);
		n := g16(b, 0);
		o = 2+n;
		if(o+Noncelen+Taglen > len b)
			return (nil, Ebadmsg);
		name = b[2:o];
		err: string;
		(tk, err) = openticket(name);
		if(err != nil)
			return (nil, err);
	}else{
		o = Treflen;
		if(o+Noncelen+Taglen > len b)
			return (nil, Ebadmsg);
		name = b[0:o];
		r := refs[refslot(name)];
		if(r == nil || !eq(r.tref, name))
			return (nil, "unknown ticket reference");
		tk = r.t;
	}
	tn := now();
	if(tn >= tk.expires){
		if(typ == Treqref){
			refs[refslot(name)] = nil;
			return (nil, "unknown ticket reference");
		}
		return (nil, "ticket expired");
	}
	if(needpq && (tk.rights & Rpq) == 0)
		return (nil, "post-quantum key exchange required");
	c2s := expand(tk.master, "lethe1 c2s");
	s2c := expand(tk.master, "lethe1 s2c");
	nonce := b[o:o+Noncelen];
	plain := crypt->xchachapolyopen(c2s, nonce, cat(hdr, name), b[o+Noncelen:]);
	if(plain == nil)
		return (nil, "bad record mac");
	# a ticket the request opened under is one the client holds: keep it
	if(typ == Treq){
		tr := tref(name);
		refs[refslot(tr)] = ref Tref(tr, tk);
	}
	if(len plain < 8)
		return (nil, "request expired");
	d := g64(plain, 0) - tn;
	if(d < big 0)
		d = -d;
	if(d > big window)
		return (nil, "request expired");
	who := ref Who(tk.uname, 1, tk.rights, tk.prefix);
	if(verbose && typ == Treqref)
		sys->fprint(stderr, "lethed: request by ticket reference\n");
	reply := request(who, plain[8:]);
	rn := rnd(Noncelen);
	id := g32(hdr, 6);
	rh := header(Rreq, id, 10+Noncelen+len reply+Taglen);
	return (cat(cat(rh, rn), crypt->xchachapolyseal(s2c, rn, cat(rh, nonce), reply)), nil);
}
