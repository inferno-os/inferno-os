implement Logind;

#
# certification service (signer): see login(6) and logind(8)
#
# logind [-1] [-k keydb] [-s signerkey]
#
# It speaks version 2 of the login protocol (CPace from the user's
# stored secret or verifier, beside an ML-KEM-768 exchange). With -1 it
# also serves clients that have only version 1, the original exchange,
# for users whose entry is still the SHA-1 of the password.
#

include "sys.m";
	sys: Sys;

include "draw.m";

include "keyring.m";
	kr: Keyring;
	IPint: import kr;

include "ipints.m";
include "crypt.m";
	crypt: Crypt;

include "cpace.m";
	cpace: Cpace;

include "dial.m";

include "security.m";
	ssl: SSL;
	login: Login;

include "daytime.m";
	daytime: Daytime;

include "arg.m";

Logind: module
{
	init:	fn(ctxt: ref Draw->Context, argv: list of string);
};

TimeLimit: con 5*60*1000;	# five minutes
keydb := "/mnt/keys";
signerfile := "/keydb/signerkey";
oldtoo := 0;

Label: con "inferno login 2";
Maxmsg: con 9999;
Noncelen: con 16;
Eklen: con 1184;	# ML-KEM-768 encapsulation key
Aead: con "chacha20poly1305";
Badsecret: con "name or secret incorrect";

Fail: con "login fail:";
Remote: con "login remote:";

stderr: ref Sys->FD;
 
init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	stderr = sys->open("/dev/cons", sys->OWRITE);

	kr = load Keyring Keyring->PATH;

	ssl = load SSL SSL->PATH;
	if(ssl == nil)
		nomod(SSL->PATH);

	daytime = load Daytime Daytime->PATH;
	if(daytime == nil) 
		nomod(Daytime->PATH);

	crypt = load Crypt Crypt->PATH;
	if(crypt == nil)
		nomod(Crypt->PATH);
	cpace = load Cpace Cpace->PATH;
	if(cpace == nil)
		nomod(Cpace->PATH);
	if((e := cpace->init()) != nil)
		fatal(e);

	login = load Login Login->PATH;
	if(login == nil)
		nomod(Login->PATH);

	arg := load Arg Arg->PATH;
	if(arg != nil && args != nil){
		arg->init(args);
		arg->setusage("logind [-1] [-k keydb] [-s signerkey]");
		while((o := arg->opt()) != 0)
			case o {
			'1' =>	oldtoo = 1;
			'k' =>	keydb = arg->earg();
			's' =>	signerfile = arg->earg();
			* =>	arg->usage();
			}
		arg = nil;
	}

	# impose time out to ensure dead network connections recovered well before TCP/IP's long time out

	grpid := sys->pctl(Sys->NEWPGRP,nil);
	pidc := chan of int;
	spawn stalker(pidc, grpid);
	tpid := <-pidc;
	err := serve(sys->fildes(0));
	if(err != nil)
		sys->fprint(stderr, "logind: %s\n", err);
	kill(tpid, "kill");
}

#
# A version 2 client starts with a count in digits; a version 1 client
# starts an ssl record, whose first byte has its top bit set.
#
serve(fd: ref Sys->FD): string
{
	first := array[1] of byte;
	if(sys->read(fd, first, 1) != 1)
		return "client hung up";
	if((int first[0] & 16r80) == 0){
		err: string;
		{
			err = dologin2(fd, first);
		}exception e{
		"login fail:*" =>
			senderrmsg(fd, what(e));
			return what(e);
		"login remote:*" =>
			return what(e);
		}
		return err;
	}
	if(!oldtoo){
		# say so in the form a version 1 client reads: an ssl record holding an error string
		m := array of byte "version 1 of the login protocol is not accepted";
		b := array[3 + len m] of byte;
		b[0] = byte (16r80 | ((len m + 1) >> 8));
		b[1] = byte (len m + 1);
		b[2] = byte 16rFF;
		b[3:] = m;
		write(fd, b);
		return "client offers only version 1 of the login protocol";
	}

	# The ssl device must see the whole conversation, and the first byte
	# has been read: give it a pipe, fed with that byte and then the rest.
	p := array[2] of ref Sys->FD;
	if(sys->pipe(p) < 0)
		return sys->sprint("pipe: %r");
	write(p[0], first);
	gone := chan of int;
	done := chan of int;
	pidc := chan of int;
	spawn relay(fd, p[0], gone, pidc);
	rpid := <-pidc;
	spawn relay(p[0], fd, done, pidc);
	r2pid := <-pidc;
	(err, c) := ssl->connect(p[1]);
	p[0] = p[1] = nil;
	if(c == nil)
		return "pushing ssl: " + err;
	# the exchange has a process of its own, to be stopped if the client goes:
	# the pipe cannot tell it so
	rc := chan of string;
	spawn worker1(c, rc, pidc);
	wpid := <-pidc;
	c = nil;
	alt{
	err = <-rc =>
		# our end of the pipe is closed; wait for what we said to go out
		<-done;
		kill(rpid, "kill");
	<-gone =>
		kill(wpid, "kill");
		kill(r2pid, "kill");
		err = "client hung up";
	}
	return err;
}

worker1(c: ref Sys->Connection, rc: chan of string, pidc: chan of int)
{
	pidc <-= sys->pctl(0, nil);
	err := dologin1(c);
	if(err != nil)
		kr->puterror(c.dfd, err);
	c = nil;
	rc <-= err;
}

relay(src, dst: ref Sys->FD, done: chan of int, pidc: chan of int)
{
	pidc <-= sys->pctl(0, nil);
	buf := array[8192] of byte;
	while((n := sys->read(src, buf, len buf)) > 0)
		if(write(dst, buf[0:n]) != n)
			break;
	if(done != nil)
		done <-= 1;
}

#
# version 2; the first byte of the client's version message has been read
#
dologin2(fd: ref Sys->FD, first: array of byte): string
{
	h := array[5] of byte;
	h[0] = first[0];
	if(readn(fd, h[1:], 4) != 4)
		return "client hung up";
	if(string h != "0001\n" || readn(fd, h, 1) != 1 || h[0] != byte '2')
		raise Fail+"incompatible login protocol";
	sendmsg(fd, array of byte "2");

	(info, err) := signerkey(signerfile);
	if(info == nil)
		raise Fail+"can't read signer's own key: "+err;

	th := kr->sha256(array of byte Label, len Label + 1, nil, nil);
	name, nc, ek: array of byte;
	(th, name) = getm(fd, th, 'c');
	(th, nc) = getm(fd, th, 'c');
	(th, ek) = getm(fd, th, 'c');
	if(len name == 0 || len name > Sys->NAMEMAX || len nc != Noncelen || len ek != Eklen)
		raise Fail+"bad message from client";
	id := string name;

	# The user's verifier W: stored, or made from a stored SHA-1 of the
	# password. Someone with no entry, or an expired one, is led through
	# the same exchange with a verifier nobody has the key to, to learn
	# no more than that the name or the secret was wrong.
	rnd := random(Noncelen+Cpace->Sharelen+Keyring->SHA1dlen+32);
	if(rnd == nil)
		raise Fail+"can't make keys";
	ns := rnd[0:Noncelen];
	ys := rnd[Noncelen:Noncelen+Cpace->Sharelen];
	nobody := rnd[Noncelen+Cpace->Sharelen:Noncelen+Cpace->Sharelen+Keyring->SHA1dlen];
	x := rnd[Noncelen+Cpace->Sharelen+Keyring->SHA1dlen:];
	why: string;
	pw: array of byte;
	userexp := 0;
	if(!okname(id))
		why = "bad name";
	else if((pw = getsecret(id)) == nil)
		why = sys->sprint("no password entry for %s: %r", id);
	else if(len pw < Keyring->SHA1dlen)
		why = "bad password for "+id+": not SHA1 hashed?";
	else if((userexp = getexpiry(id)) < 0)
		why = sys->sprint("expiry time for %s: %r", id);
	if(why != nil)
		pw = nobody;
	# the same work whichever form is stored
	W: array of byte;
	if(isverifier(pw)){
		login->verifier(id, nobody);
		W = pw;
	}else
		W = login->verifier(id, pw[0:Keyring->SHA1dlen]);
	if(W == nil || len W != Login->Verifierlen)
		raise Fail+"can't make keys";
	# this run's secret: a fresh key of ours with the user's
	prs := crypt->x25519(x, W[len Login->Verifiertag:]);
	if(prs == nil || allzero(prs)){
		if(why == nil)
			why = "bad verifier for "+id;
		prs = nobody;
	}

	sid := cat(nc, ns);
	g := cpace->generator(prs, cpace->lvcat(array of byte Label :: name :: nil), sid);
	ps := cpace->share(g, ys);
	(ct, ss) := crypt->mlkem768encap(ek);
	if(ps == nil || ct == nil || ss == nil)
		raise Fail+"can't make keys";
	th = putm(fd, th, 's', ns);
	th = putm(fd, th, 's', crypt->x25519base(x));
	th = putm(fd, th, 's', ps);
	th = putm(fd, th, 's', ct);

	pc: array of byte;
	(th, pc) = getm(fd, th, 'c');
	T := array[Keyring->SHA256dlen] of byte;
	kr->sha256(nil, 0, T, th);
	isk := cpace->isk(sid, ys, pc, ps, array of byte "signer", pc, name);
	if(isk == nil)
		raise Fail+"bad key exchange value";
	ikm := cat(ss, isk);

	# the client shows it has the secret before it is shown anything
	if(!eq(getmsg(fd), kdf(T, ikm, "confirm c")) || why != nil){
		senderrmsg(fd, Badsecret);
		if(why == nil)
			why = "wrong secret for "+id;
		return why;
	}
	sendmsg(fd, kdf(T, ikm, "confirm s"));

	c: ref Sys->Connection;
	(err, c) = ssl->connect(fd);
	if(c == nil)
		return "pushing ssl: " + err;
	err = ssl->secret(c, kdf(T, ikm, "c2s"), kdf(T, ikm, "s2c"));
	if(err != nil)
		return "can't set ssl secrets: "+err;
	if(sys->fprint(c.cfd, "alg %s", Aead) < 0)
		return sys->sprint("can't push alg %s: %r", Aead);
	err = certify(c, info, id, userexp);
	if(err != nil)
		kr->puterror(c.dfd, err);
	return err;
}

certify(c: ref Sys->Connection, info: ref Keyring->Authinfo, id: string, userexp: int): string
{
	# our public key, and the parameters version 1 of auth(6) uses
	if(kr->putstring(c.dfd, kr->pktostr(kr->sktopk(info.mysk))) < 0 ||
	   kr->putstring(c.dfd, info.alpha.iptob64()) < 0 ||
	   kr->putstring(c.dfd, info.p.iptob64()) < 0)
		return sys->sprint("can't send signer's public key: %r");

	# get his public key
	(s, err) := kr->getstring(c.dfd);
	if(err != nil)
		return "client public key: "+err;
	hisPKbuf := array of byte s;
	hisPK := kr->strtopk(s);
	if(hisPK == nil)
		return "bad public key";
	if(hisPK.owner != id)
		return "pk name doesn't match user name";

	# sign and return
	cert := signpk(info.mysk, userexp, hisPKbuf);
	if(cert == nil)
		return "can't sign";
	if(kr->putstring(c.dfd, kr->certtostr(cert)) < 0)
		return sys->sprint("can't send certificate: %r");
	return nil;
}

# a name is one element of a path under keydb
okname(s: string): int
{
	if(s == "." || s == "..")
		return 0;
	for(i := 0; i < len s; i++)
		if(s[i] == '/' || s[i] <= ' ')
			return 0;
	return 1;
}

# an entry that is a verifier, not the SHA-1 of a password: see login(6)
isverifier(a: array of byte): int
{
	t := array of byte Login->Verifiertag;
	return len a == Login->Verifierlen && eq(a[0:len t], t);
}

allzero(a: array of byte): int
{
	x := 0;
	for(i := 0; i < len a; i++)
		x |= int a[i];
	return x == 0;
}

kdf(T, ikm: array of byte, what: string): array of byte
{
	return crypt->hkdfsha256(T, ikm, array of byte (Label + " " + what), 32);
}

random(n: int): array of byte
{
	fd := sys->open("/dev/random", Sys->OREAD);
	if(fd == nil)
		return nil;
	b := array[n] of byte;
	if(readn(fd, b, n) != n)
		return nil;
	return b;
}

cat(a, b: array of byte): array of byte
{
	c := array[len a + len b] of byte;
	c[0:] = a;
	c[len a:] = b;
	return c;
}

# without stopping at the first difference
eq(a, b: array of byte): int
{
	if(len a != len b)
		return 0;
	x := 0;
	for(i := 0; i < len a; i++)
		x |= int a[i] ^ int b[i];
	return x == 0;
}

what(e: string): string
{
	for(i := 0; i < len e; i++)
		if(e[i] == ':')
			return e[i+1:];
	return e;
}

# messages before ssl is pushed, as in appl/lib/login.b
write0(fd: ref Sys->FD, b: array of byte): int
{
	return sys->write(fd, b, len b);
}

write(fd: ref Sys->FD, b: array of byte): int
{
	n := -1;
	{
		n = write0(fd, b);
	}exception{
	"write on closed pipe" =>
		sys->werrstr("write on closed pipe");
		n = -1;
	}
	return n;
}

sendmsg(fd: ref Sys->FD, m: array of byte)
{
	if(len m > Maxmsg)
		raise Remote+"message too long to send";
	b := cat(array of byte sys->sprint("%4.4d\n", len m), m);
	if(write(fd, b) != len b)
		raise Remote+sys->sprint("write error: %r");
}

senderrmsg(fd: ref Sys->FD, e: string)
{
	m := array of byte e;
	if(len m > 255)
		m = m[0:255];
	write(fd, cat(array of byte sys->sprint("!%3.3d\n", len m), m));
}

getmsg(fd: ref Sys->FD): array of byte
{
	h := array[5] of byte;
	if(readn(fd, h, 5) != 5)
		raise Remote+"client hung up";
	iserr := h[0] == byte '!';
	n := 0;
	for(i := iserr; i < 4; i++){
		c := int h[i];
		if(c < '0' || c > '9')
			raise Fail+"bad message count";
		n = n*10 + c - '0';
	}
	if(h[4] != byte '\n')
		raise Fail+"bad message count";
	m := array[n] of byte;
	if(readn(fd, m, n) != n)
		raise Remote+"client hung up";
	if(iserr)
		raise Remote+"client: "+string m;
	return m;
}

readn(fd: ref Sys->FD, buf: array of byte, n: int): int
{
	for(t := 0; t < n; ){
		m := sys->read(fd, buf[t:], n-t);
		if(m <= 0)
			break;
		t += m;
	}
	return t;
}

putm(fd: ref Sys->FD, th: ref Keyring->DigestState, who: int, m: array of byte): ref Keyring->DigestState
{
	sendmsg(fd, m);
	return addmsg(th, who, m);
}

getm(fd: ref Sys->FD, th: ref Keyring->DigestState, who: int): (ref Keyring->DigestState, array of byte)
{
	m := getmsg(fd);
	return (addmsg(th, who, m), m);
}

addmsg(th: ref Keyring->DigestState, who: int, m: array of byte): ref Keyring->DigestState
{
	h := array[5] of byte;
	n := len m;
	h[0] = byte who;
	h[1] = byte (n>>24);
	h[2] = byte (n>>16);
	h[3] = byte (n>>8);
	h[4] = byte n;
	th = kr->sha256(h, len h, nil, th);
	return kr->sha256(m, n, nil, th);
}

#
# version 1
#
dologin1(c: ref Dial->Connection): string
{
	ivec: array of byte;

	(info, err) := signerkey(signerfile);
	if(info == nil)
		return "can't read signer's own key: "+err;

	# get user name; ack
	s: string;
	(s, err) = kr->getstring(c.dfd);
	if(err != nil)
		return err;
	name := s;
	kr->putstring(c.dfd, name);

	# get initialization vector
	(ivec, err) = kr->getbytearray(c.dfd);
	if(err != nil)
		return "can't get initialization vector: "+err;

	# lookup password
	pw := getsecret(s);
	if(pw == nil)
		return sys->sprint("no password entry for %s: %r", s);
	if(len pw < Keyring->SHA1dlen)
		return "bad password for "+s+": not SHA1 hashed?";
	if(isverifier(pw))
		return "the entry for "+s+" serves only version 2 of the login protocol";
	userexp := getexpiry(s);
	if(userexp < 0)
		return sys->sprint("expiry time for %s: %r", s);

	# generate our random diffie hellman part
	bits := info.p.bits();
	r0 := kr->IPint.random(bits/4, bits);

	# generate alpha0 = alpha**r0 mod p
	alphar0 := info.alpha.expmod(r0, info.p);

	# start encrypting
	pwbuf := array[8] of byte;
	for(i := 0; i < 8; i++)
		pwbuf[i] = pw[i] ^ pw[8+i];
	for(i = 0; i < 4; i++)
		pwbuf[i] ^= pw[16+i];
	for(i = 0; i < 8; i++)
		pwbuf[i] ^= ivec[i];
	err = ssl->secret(c, pwbuf, pwbuf);
	if(err != nil)
		return "can't set ssl secret: "+err;

	if(sys->fprint(c.cfd, "alg rc4") < 0)
		return sys->sprint("can't push alg rc4: %r");

	# send P(alpha**r0 mod p)
	if(kr->putstring(c.dfd, alphar0.iptob64()) < 0)
		return sys->sprint("can't send (alpha**r0 mod p): %r");

	# stop encrypting
	if(sys->fprint(c.cfd, "alg clear") < 0)
		return sys->sprint("can't clear alg: %r");

	# send alpha, p
	if(kr->putstring(c.dfd, info.alpha.iptob64()) < 0 ||
	   kr->putstring(c.dfd, info.p.iptob64()) < 0)
		return sys->sprint("can't send alpha, p: %r");

	# get alpha**r1 mod p
	(s, err) = kr->getstring(c.dfd);
	if(err != nil)
		return "can't get alpha**r1 mod p:"+err;
	alphar1 := kr->IPint.b64toip(s);

	# compute alpha**(r0*r1) mod p
	alphar0r1 := alphar1.expmod(r0, info.p);

	# turn on digesting
	secret := alphar0r1.iptobytes();
	err = ssl->secret(c, secret, secret);
	if(err != nil)
		return "can't set digest secret: "+err;
	if(sys->fprint(c.cfd, "alg sha1") < 0)
		return sys->sprint("can't push alg sha1: %r");

	# send our public key
	if(kr->putstring(c.dfd, kr->pktostr(kr->sktopk(info.mysk))) < 0)
		return sys->sprint("can't send signer's public key: %r");

	# get his public key
	(s, err) = kr->getstring(c.dfd);
	if(err != nil)
		return "client public key: "+err;
	hisPKbuf := array of byte s;
	hisPK := kr->strtopk(s);
	if(hisPK.owner != name)
		return "pk name doesn't match user name";

	# sign and return
	cert := signpk(info.mysk, userexp, hisPKbuf);
	if(cert == nil)
		return "can't sign";

	if(kr->putstring(c.dfd, kr->certtostr(cert)) < 0)
		return sys->sprint("can't send certificate: %r");

	return nil;
}

nomod(mod: string)
{
	fatal(sys->sprint("can't load %s: %r",mod));
}

fatal(msg: string)
{
	sys->fprint(stderr, "logind: %s\n", msg);
	exit;
}

signerkey(filename: string): (ref Keyring->Authinfo, string)
{

	info := kr->readauthinfo(filename);
	if(info == nil)
		return (nil, sys->sprint("readauthinfo %r"));

	# validate signer key
	now := daytime->now();
	if(info.cert.exp != 0 && info.cert.exp < now)
		return (nil, sys->sprint("signer key expired"));

	return (info, nil);
}

getsecret(id: string): array of byte
{
	fd := sys->open(sys->sprint("%s/%s/secret", keydb, id), Sys->OREAD);
	if(fd == nil)
		return nil;
	(ok, d) := sys->fstat(fd);
	if(ok < 0)
		return nil;
	a := array[int d.length] of byte;
	n := sys->read(fd, a, len a);
	if(n < 0)
		return nil;
	return a[0:n];
}

getexpiry(id: string): int
{
	fd := sys->open(sys->sprint("%s/%s/expire", keydb, id), Sys->OREAD);
	if(fd == nil)
		return -1;
	a := array[Sys->NAMEMAX] of byte;
	n := sys->read(fd, a, len a);
	if(n < 0)
		return -1;
	s := string a[0:n];
	if(s == "never")
		return 0;
	if(s == "expired"){
		sys->werrstr(sys->sprint("entry for %s expired", id));
		return -1;
	}
	return int s;
}

stalker(pidc: chan of int, killpid: int)
{
	pidc <-= sys->pctl(0, nil);
	sys->sleep(TimeLimit);
	sys->fprint(stderr, "logind: login timed out\n");
	kill(killpid, "killgrp");
}

kill(pid: int, how: string)
{
	fd := sys->open("#p/" + string pid + "/ctl", Sys->OWRITE);
	if(fd == nil || sys->fprint(fd, "%s", how) < 0)
		sys->fprint(stderr, "logind: can't %s %d: %r\n", how, pid);
}

# the algorithms that sign bytes take sha256; the older ones keep sha1
signpk(sk: ref Keyring->SK, expiry: int, buf: array of byte): ref Keyring->Certificate
{
	case sk.sa.name {
	"ed25519" or "ed25519mldsa65" =>
		return kr->sign(sk, expiry, kr->sha256(buf, len buf, nil, nil), "sha256");
	}
	return kr->sign(sk, expiry, kr->sha1(buf, len buf, nil, nil), "sha1");
}

