implement Secstored;

#
# secstored - Secstore server for Infernode
#
# Implements the Plan 9 secstore server protocol (PAK authentication,
# encrypted file storage).  Compatible with the existing secstore
# client library (appl/lib/secstore.b) and CLI (appl/cmd/auth/secstore.b).
#
# Usage:
#   auth/secstored [-d] [-s storedir] [-a addr]
#
# Options:
#   -d            debug mode (verbose logging)
#   -s storedir   directory for user data (default: /usr/inferno/secstore)
#   -a addr       listen address (default: tcp!*!5356)
#
# Storage layout:
#   storedir/
#     <user>/
#       PAK          PAK verifier (hexHi) for this user
#       <filename>   encrypted file blobs
#
# Setup:
#   Use auth/secstore-setup to create user accounts.
#

include "sys.m";
	sys: Sys;

include "draw.m";

include "dial.m";
	dialler: Dial;

include "keyring.m";
	kr: Keyring;
	DigestState, IPint: import kr;
	AESbsize: import kr;

include "security.m";
	ssl: SSL;

include "encoding.m";
	base64: Encoding;

include "readdir.m";

include "arg.m";

include "string.m";
	str: String;

Secstored: module
{
	init: fn(nil: ref Draw->Context, nil: list of string);
};

VERSION: con "secstore";
Maxfilesize: con 128*1024;
Maxmsg: con 4096;

debug := 0;
storedir := "/usr/inferno/secstore";
sname := "secstore";	# server identity for PAK

# PAK parameters — same as client (from secstore.b)
PAKparams: adt {
	q:	ref IPint;
	p:	ref IPint;
	r:	ref IPint;
	g:	ref IPint;
};

pak: ref PAKparams;

init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	kr = load Keyring Keyring->PATH;
	ssl = load SSL SSL->PATH;
	base64 = load Encoding Encoding->BASE64PATH;
	dialler = load Dial Dial->PATH;
	str = load String String->PATH;

	if(kr == nil || ssl == nil || base64 == nil || dialler == nil || str == nil)
		fatal("cannot load required modules");

	initPAKparams();

	addr := "tcp!*!5356";
	arg := load Arg Arg->PATH;
	if(arg != nil){
		arg->init(args);
		arg->setusage("auth/secstored [-d] [-s storedir] [-a addr]");
		while((o := arg->opt()) != 0)
			case o {
			'd' =>	debug++;
			's' =>	storedir = arg->earg();
			'a' =>	addr = arg->earg();
			* =>	arg->usage();
			}
		args = arg->argv();
		if(args != nil)
			arg->usage();
	}

	# Ensure store directory exists
	sys->create(storedir, Sys->OREAD, Sys->DMDIR | 8r700);

	log(sys->sprint("listening on %s, store=%s", addr, storedir));

	conn := dialler->announce(addr);
	if(conn == nil)
		fatal(sys->sprint("can't announce %s: %r", addr));

	for(;;){
		lconn := dialler->listen(conn);
		if(lconn == nil){
			log(sys->sprint("listen failed: %r"));
			continue;
		}
		spawn serve(lconn);
	}
}

serve(lconn: ref Dial->Connection)
{
	sys->pctl(Sys->NEWPGRP|Sys->FORKFD, nil);

	dfd := dialler->accept(lconn);
	if(dfd == nil){
		log("accept failed");
		return;
	}

	# Wrap with SSL
	(err, sslconn) := ssl->connect(dfd);
	if(err != nil){
		log("ssl connect: " + err);
		return;
	}

	if(debug)
		log("new connection (ssl ok)");

	# Try reading raw fd first to diagnose cross-host issue
	if(debug){
		tbuf := array[16] of byte;
		tn := sys->read(dfd, tbuf, len tbuf);
		log(sys->sprint("raw fd read test: n=%d", tn));
		if(tn > 0)
			log(sys->sprint("raw data: %q", string tbuf[:tn]));
	}

	# PAK authentication
	(user, hexHi) := pakserver(sslconn);
	if(user == nil){
		log("PAK auth failed");
		return;
	}

	log("authenticated: " + user);

	# Send OK
	sys->fprint(sslconn.dfd, "OK");

	# Handle file operations
	fileloop(sslconn, user, hexHi);
}

# ── PAK Server Protocol ──────────────────────────────────────

pakserver(conn: ref Dial->Connection): (string, string)
{
	fd := conn.dfd;

	# Read client hello: "secstore\tPAK\nC=<user>\nm=<hexm>\n"
	buf := array[4096] of byte;
	n := sys->read(fd, buf, len buf);
	if(n <= 0){
		if(debug)
			log(sys->sprint("PAK initial read failed: n=%d", n));
		return (nil, nil);
	}
	hello := string buf[0:n];

	# Parse the hello
	if(debug)
		log(sys->sprint("PAK hello (%d bytes): %q", len hello, hello));
	(nf, flds) := sys->tokenize(hello, "\n");
	if(debug)
		log(sys->sprint("PAK tokenized: %d fields", nf));
	if(nf < 3){
		writerr(fd, "bad hello");
		return (nil, nil);
	}

	# First line: "secstore\tPAK"
	hdr := hd flds; flds = tl flds;
	if(debug)
		log(sys->sprint("PAK hdr: %q", hdr));
	if(hdr != "secstore\tPAK"){
		writerr(fd, "bad protocol");
		return (nil, nil);
	}

	# C=<user>
	C := ex("C=", hd flds); flds = tl flds;
	if(C == nil){
		writerr(fd, "no user");
		return (nil, nil);
	}

	# m=<hexm>
	hexm := ex("m=", hd flds);
	if(hexm == nil){
		writerr(fd, "no m");
		return (nil, nil);
	}

	# Handle cansecstore probe (m=0)
	if(hexm == "0"){
		hexHi := readverifier(C);
		if(hexHi != nil)
			sys->fprint(fd, "!account exists");
		else
			sys->fprint(fd, "!no account");
		return (nil, nil);
	}

	# Look up user's PAK verifier
	hexHi := readverifier(C);
	if(hexHi == nil){
		writerr(fd, "no account");
		return (nil, nil);
	}
	Hi := IPint.strtoip(hexHi, 64);
	m := IPint.strtoip(hexm, 64);

	# Server picks random y, computes mu = g^y mod p
	y := mod(IPint.random(240, 240), pak.q);
	if(y.eq(IPint.inttoip(0)))
		y = IPint.inttoip(1);
	mu := pak.g.expmod(y, pak.p);
	hexmu := mu.iptostr(64);

	# Compute shared secret: sigma = (m * Hi)^y mod p
	sigma := mod(m.mul(Hi), pak.p).expmod(y, pak.p);
	hexsigma := sigma.iptostr(64);

	# Compute server verification hash
	digest := shorthash("server", C, sname, hexm, hexmu, hexsigma, hexHi);
	ks := base64->enc(digest);

	# Send mu, k (server hash), S (server name)
	if(debug)
		log(sys->sprint("PAK sending mu=%s... k=%s S=%s", hexmu[:20], ks, sname));
	if(sys->fprint(fd, "mu=%s\nk=%s\nS=%s\n", hexmu, ks, sname) < 0){
		return (nil, nil);
	}

	# Read client verification: "k'=<hash>\n"
	n = sys->read(fd, buf, len buf);
	if(n <= 0){
		if(debug)
			log(sys->sprint("PAK client read failed: n=%d", n));
		return (nil, nil);
	}
	s := string buf[0:n];

	kprime := ex("k'=", s);
	if(kprime == nil){
		# Strip trailing newline
		if(len s > 0 && s[len s - 1] == '\n')
			s = s[:len s - 1];
		kprime = ex("k'=", s);
	}
	if(kprime == nil){
		writerr(fd, "no client verifier");
		return (nil, nil);
	}
	# Strip trailing newline from kprime
	if(len kprime > 0 && kprime[len kprime - 1] == '\n')
		kprime = kprime[:len kprime - 1];

	# Verify client hash
	digest = shorthash("client", C, sname, hexm, hexmu, hexsigma, hexHi);
	kc := base64->enc(digest);
	if(debug)
		log(sys->sprint("PAK client k'=%q expected=%q", kprime, kc));
	if(kprime != kc){
		writerr(fd, "client verifier didn't match");
		return (nil, nil);
	}

	# Set session secret (direction=1 for server, opposite of client's 0)
	digest = shorthash("session", C, sname, hexm, hexmu, hexsigma, hexHi);

	# Zero sigma
	for(i := 0; i < len hexsigma; i++)
		hexsigma[i] = 0;

	secretin := array[Keyring->SHA1dlen] of byte;
	secretout := array[Keyring->SHA1dlen] of byte;
	# Server reverses client's direction: client out=HMAC("two"), so server in=HMAC("two")
	kr->hmac_sha1(digest, len digest, array of byte "one", secretout, nil);
	kr->hmac_sha1(digest, len digest, array of byte "two", secretin, nil);
	e := ssl->secret(conn, secretin, secretout);
	if(e != nil){
		log("setsecret: " + e);
		return (nil, nil);
	}
	erasekey(digest);

	if(sys->fprint(conn.cfd, "alg sha256 aes_128_cbc") < 0)
		return (nil, nil);

	return (C, hexHi);
}

# ── File Operations ───────────────────────────────────────────

fileloop(conn: ref Dial->Connection, user: string, nil: string)
{
	fd := conn.dfd;
	buf := array[Maxmsg] of byte;

	for(;;){
		n := sys->read(fd, buf, len buf);
		if(n <= 0)
			break;
		line := string buf[0:n];
		# Strip trailing newline
		if(len line > 0 && line[len line - 1] == '\n')
			line = line[:len line - 1];

		if(debug)
			log("cmd: " + line);

		# Parse command
		cmd := line;
		arg := "";
		for(i := 0; i < len line; i++){
			if(line[i] == ' '){
				cmd = line[0:i];
				arg = line[i+1:];
				break;
			}
		}

		case cmd {
		"GET" =>
			doget(fd, user, arg);
		"PUT" =>
			doput(fd, user, arg);
		"RM" =>
			dorm(user, arg);
		"BYE" =>
			break;
		* =>
			writerr(fd, "unknown command");
		}
	}
}

doget(fd: ref Sys->FD, user: string, name: string)
{
	if(name == nil || name == ""){
		sys->fprint(fd, "-1");
		return;
	}

	# Sanitize filename (no slashes, no ..)
	if(!safename(name)){
		sys->fprint(fd, "-1");
		return;
	}

	path := userpath(user, name);
	rfd := sys->open(path, Sys->OREAD);
	if(rfd == nil){
		sys->fprint(fd, "-1");
		return;
	}

	# Read entire file
	data := array[Maxfilesize] of byte;
	total := 0;
	for(;;){
		n := sys->read(rfd, data[total:], len data - total);
		if(n <= 0)
			break;
		total += n;
	}

	if(debug)
		log(sys->sprint("GET %s: %d bytes", name, total));

	# Send size, then data
	sys->fprint(fd, "%d", total);
	if(total > 0){
		for(off := 0; off < total;){
			chunk := total - off;
			if(chunk > Maxmsg)
				chunk = Maxmsg;
			sys->write(fd, data[off:off+chunk], chunk);
			off += chunk;
		}
	}
}

doput(fd: ref Sys->FD, user: string, name: string)
{
	if(name == nil || name == "" || !safename(name))
		return;

	# Read size
	buf := array[64] of byte;
	n := sys->read(fd, buf, len buf);
	if(n <= 0)
		return;
	size := int string buf[0:n];
	if(size < 0 || size > Maxfilesize)
		return;

	# Read data
	data := array[size] of byte;
	for(nr := 0; nr < size;){
		n = sys->read(fd, data[nr:], size - nr);
		if(n <= 0)
			return;
		nr += n;
	}

	if(debug)
		log(sys->sprint("PUT %s: %d bytes", name, size));

	# Ensure user directory exists
	sys->create(userpath(user, ""), Sys->OREAD, Sys->DMDIR | 8r700);

	# Write file
	path := userpath(user, name);
	wfd := sys->create(path, Sys->OWRITE, 8r600);
	if(wfd == nil){
		log(sys->sprint("can't create %s: %r", path));
		return;
	}
	sys->write(wfd, data, len data);
}

dorm(user: string, name: string)
{
	if(name == nil || name == "" || !safename(name))
		return;

	if(debug)
		log("RM " + name);

	path := userpath(user, name);
	sys->remove(path);
}

# ── PAK Crypto (mirrors secstore.b client code) ──────────────

initPAKparams()
{
	if(pak != nil)
		return;
	lpak := ref PAKparams;
	lpak.q = IPint.strtoip("E0F0EF284E10796C5A2A511E94748BA03C795C13", 16);
	lpak.p = IPint.strtoip("C41CFBE4D4846F67A3DF7DE9921A49D3B42DC33728427AB159CEC8CBB"+
		"DB12B5F0C244F1A734AEB9840804EA3C25036AD1B61AFF3ABBC247CD4B384224567A86"+
		"3A6F020E7EE9795554BCD08ABAD7321AF27E1E92E3DB1C6E7E94FAAE590AE9C48F96D9"+
		"3D178E809401ABE8A534A1EC44359733475A36A70C7B425125062B1142D", 16);
	lpak.r = IPint.strtoip("DF310F4E54A5FEC5D86D3E14863921E834113E060F90052AD332B3241"+
		"CEF2497EFA0303D6344F7C819691A0F9C4A773815AF8EAECFB7EC1D98F039F17A32A7E"+
		"887D97251A927D093F44A55577F4D70444AEBD06B9B45695EC23962B175F266895C67D"+
		"21C4656848614D888A4", 16);
	lpak.g = IPint.strtoip("2F1C308DC46B9A44B52DF7DACCE1208CCEF72F69C743ADD4D23271734"+
		"44ED6E65E074694246E07F9FD4AE26E0FDDD9F54F813C40CB9BCD4338EA6F242AB94CD"+
		"410E676C290368A16B1A3594877437E516C53A6EEE5493A038A017E955E218E7819734"+
		"E3E2A6E0BAE08B14258F8C03CC1B30E0DDADFCF7CEDF0727684D3D255F1", 16);
	pak = lpak;
}

mod(a, b: ref IPint): ref IPint
{
	return a.div(b).t1;
}

shaz(s: string, digest: array of byte, state: ref DigestState): ref DigestState
{
	a := array of byte s;
	state = kr->sha1(a, len a, digest, state);
	erasekey(a);
	return state;
}

shorthash(mess: string, C: string, S: string, m: string, mu: string, sigma: string, Hi: string): array of byte
{
	state := shaz(mess, nil, nil);
	state = shaz(C, nil, state);
	state = shaz(S, nil, state);
	state = shaz(m, nil, state);
	state = shaz(mu, nil, state);
	state = shaz(sigma, nil, state);
	state = shaz(Hi, nil, state);
	state = shaz(mess, nil, state);
	state = shaz(C, nil, state);
	state = shaz(S, nil, state);
	state = shaz(m, nil, state);
	state = shaz(mu, nil, state);
	state = shaz(sigma, nil, state);
	digest := array[Keyring->SHA1dlen] of byte;
	shaz(Hi, digest, state);
	return digest;
}

erasekey(a: array of byte)
{
	for(i := 0; i < len a; i++)
		a[i] = byte 0;
}

# ── User/File Management ─────────────────────────────────────

readverifier(user: string): string
{
	if(!safename(user))
		return nil;
	path := storedir + "/" + user + "/PAK";
	fd := sys->open(path, Sys->OREAD);
	if(fd == nil)
		return nil;
	buf := array[1024] of byte;
	n := sys->read(fd, buf, len buf);
	if(n <= 0)
		return nil;
	s := string buf[0:n];
	# Strip trailing whitespace
	while(len s > 0 && (s[len s-1] == '\n' || s[len s-1] == ' '))
		s = s[:len s-1];
	return s;
}

userpath(user: string, name: string): string
{
	if(name == "" || name == nil)
		return storedir + "/" + user;
	return storedir + "/" + user + "/" + name;
}

safename(name: string): int
{
	if(name == nil || len name == 0)
		return 0;
	if(name == ".." || name[0] == '/')
		return 0;
	for(i := 0; i < len name; i++)
		if(name[i] == '/' || name[i] == 0)
			return 0;
	return 1;
}

# ── Utilities ─────────────────────────────────────────────────

ex(tag: string, s: string): string
{
	if(len s < len tag || s[0:len tag] != tag)
		return nil;
	return s[len tag:];
}

writerr(fd: ref Sys->FD, s: string)
{
	sys->fprint(fd, "!%s", s);
}

log(s: string)
{
	sys->fprint(sys->fildes(2), "secstored: %s\n", s);
}

fatal(s: string)
{
	sys->fprint(sys->fildes(2), "secstored: %s\n", s);
	raise "fail:error";
}
