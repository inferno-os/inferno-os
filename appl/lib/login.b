# Inferno login: a certificate from a signer, for a password
#
# Version 2 (the default, see login(6)): CPace over X25519, an
# ML-KEM-768 exchange beside it, keys from both by HKDF-SHA256 over a
# hash of everything said, confirmation each way, then chacha20poly1305
# records for the keys and certificate. Someone without the password,
# watching or taking either part, can test one guess for each run.
# The secret CPace starts from is made afresh for each run, in the
# manner of AuCPace: the signer needs only a verifier W for the user,
# the public key of a secret key w that the password gives, and sends a
# fresh public key X; the secret is the X25519 value both can compute,
# the user from w and X, the signer from W and X's secret key. So what
# the signer stores lets it check a password but not log in.
#
# Version 1 is the original Encrypted Key Exchange, in which the
# signer's Diffie-Hellman value is hidden by 40-bit RC4 keyed from the
# password; it is spoken only when asked for, and never as a fallback.
#
implement Login;

include "sys.m";
	sys: Sys;

include "keyring.m";
	kr: Keyring;
	IPint: import kr;

include "ipints.m";
include "crypt.m";
	crypt: Crypt;

include "cpace.m";
	cpace: Cpace;

include "security.m";
	ssl: SSL;

include "dial.m";

include "string.m";

Label: con "inferno login 2";
Maxmsg: con 9999;
Noncelen: con 16;
Eklen: con 1184;	# ML-KEM-768 encapsulation key
Ctlen: con 1088;	# ML-KEM-768 ciphertext
Aead: con "chacha20poly1305";
Patience: con 20*1000;	# for a signer's first answer, in ms

# exceptions inside this module, as in auth.b
Fail: con "login fail:";
Remote: con "login remote:";

# see login(6); a dest that starts "v1 " asks for version 1
login(id, password, dest: string): (string, ref Keyring->Authinfo)
{
	sys = load Sys Sys->PATH;
	dial := load Dial Dial->PATH;
	if(dial == nil)
		return nomod(Dial->PATH);

	version := 2;
	if(len dest > 3 && dest[0:3] == "v1 "){
		version = 1;
		dest = dest[3:];
	}
	if(dest == nil)
		dest = "$SIGNER";
	dest = dial->netmkaddr(dest, "net", "inflogin");
	lc := dial->dial(dest, nil);
	if(lc == nil)
		return (sys->sprint("can't contact login service: %s: %r", dest), nil);
	return loginfd(version, id, password, lc.dfd);
}

loginfd(version: int, id, password: string, fd: ref Sys->FD): (string, ref Keyring->Authinfo)
{
	sys = load Sys Sys->PATH;
	kr = load Keyring Keyring->PATH;
	if(kr == nil)
		return nomod(Keyring->PATH);
	pwbuf := array of byte password;
	digest := array[Keyring->SHA1dlen] of byte;
	kr->sha1(pwbuf, len pwbuf, digest, nil);
	return loginsecret(version, id, digest, fd);
}

# secret is the SHA-1 of the password, all either version makes of it
loginsecret(version: int, id: string, secret: array of byte, fd: ref Sys->FD): (string, ref Keyring->Authinfo)
{
	sys = load Sys Sys->PATH;
	kr = load Keyring Keyring->PATH;
	if(kr == nil)
		return nomod(Keyring->PATH);
	ssl = load SSL SSL->PATH;
	if(ssl == nil)
		return nomod(SSL->PATH);
	if(len secret != Keyring->SHA1dlen)
		return ("bad secret", nil);
	case version {
	1 =>
		return login1(id, secret, fd);
	2 =>
		;
	* =>
		return ("no such version of the login protocol", nil);
	}
	crypt = load Crypt Crypt->PATH;
	if(crypt == nil)
		return nomod(Crypt->PATH);
	cpace = load Cpace Cpace->PATH;
	if(cpace == nil)
		return nomod(Cpace->PATH);
	if((e := cpace->init()) != nil)
		return (e, nil);

	r: (string, ref Keyring->Authinfo);
	{
		r = login2(id, secret, fd);
	}exception ex{
	"login fail:*" =>
		senderrmsg(fd, what(ex));
		return (what(ex), nil);
	"login remote:*" =>
		return (what(ex), nil);
	}
	return r;
}

#
# version 2
#
# c: "2"					s: "2"
# c: name, nonce[16], ML-KEM key
# s: nonce[16], X, Ys, ML-KEM ciphertext
# c: Yc, confirmation				s: confirmation
# then in chacha20poly1305 records:
# s: signer's public key, alpha, p		c: user's public key
# s: certificate
#
login2(id: string, secret: array of byte, fd: ref Sys->FD): (string, ref Keyring->Authinfo)
{
	sendmsg(fd, array of byte "2");
	v := string firstmsg(fd);
	if(v != "2")
		raise Fail+"signer offers only version "+v+" of the login protocol";

	rnd := random(Noncelen+Cpace->Sharelen);
	(ek, dk) := crypt->mlkem768keygen();
	if(rnd == nil || ek == nil)
		raise Fail+"can't make keys";
	nc := rnd[0:Noncelen];
	yc := rnd[Noncelen:];
	name := array of byte id;

	th := kr->sha256(array of byte Label, len Label + 1, nil, nil);
	th = putm(fd, th, 'c', name);
	th = putm(fd, th, 'c', nc);
	th = putm(fd, th, 'c', ek);

	ns, x, ys, ct: array of byte;
	(th, ns) = getm(fd, th, 's');
	(th, x) = getm(fd, th, 's');
	(th, ys) = getm(fd, th, 's');
	(th, ct) = getm(fd, th, 's');
	if(len ns != Noncelen || len x != 32 || len ys != Cpace->Sharelen || len ct != Ctlen)
		raise Fail+"bad message from signer";

	# this run's secret: ours with the signer's fresh key
	prs := crypt->x25519(wkey(id, secret), x);
	if(prs == nil || allzero(prs))
		raise Fail+"bad key exchange value";
	sid := cat(nc, ns);
	g := cpace->generator(prs, cpace->lvcat(array of byte Label :: name :: nil), sid);
	pc := cpace->share(g, yc);
	th = putm(fd, th, 'c', pc);
	T := array[Keyring->SHA256dlen] of byte;
	kr->sha256(nil, 0, T, th);

	isk := cpace->isk(sid, yc, ys, ys, array of byte "signer", pc, name);
	ss := crypt->mlkem768decap(dk, ct);
	if(isk == nil || ss == nil)
		raise Fail+"bad key exchange value";
	ikm := cat(ss, isk);

	sendmsg(fd, kdf(T, ikm, "confirm c"));
	if(!eq(getmsg(fd), kdf(T, ikm, "confirm s")))
		raise Fail+"signer does not know the secret";

	(err, c) := ssl->connect(fd);
	if(c == nil)
		return ("can't push ssl: " + err, nil);
	fd = nil;
	err = ssl->secret(c, kdf(T, ikm, "s2c"), kdf(T, ikm, "c2s"));
	if(err != nil)
		return ("can't set secrets: " + err, nil);
	if(sys->fprint(c.cfd, "alg %s", Aead) < 0)
		return (sys->sprint("can't push alg %s: %r", Aead), nil);

	# the signer's public key and the Diffie-Hellman parameters version 1 of auth(6) uses
	info := ref Keyring->Authinfo;
	s: string;
	(s, err) = kr->getstring(c.dfd);
	if(err != nil)
		return ("can't get signer's public key: " + err, nil);
	info.spk = kr->strtopk(s);
	if(info.spk == nil)
		return ("bad public key from signer", nil);
	(s, err) = kr->getstring(c.dfd);
	if(err != nil)
		return ("can't get alpha: " + err, nil);
	info.alpha = IPint.b64toip(s);
	(s, err) = kr->getstring(c.dfd);
	if(err != nil)
		return ("can't get p: " + err, nil);
	info.p = IPint.b64toip(s);

	# generate a key pair of the signer's kind, and have it certified
	info.mysk = kr->genSKfromPK(info.spk, id);
	if(info.mysk == nil)
		return ("can't make a key", nil);
	info.mypk = kr->sktopk(info.mysk);
	pks := kr->pktostr(info.mypk);
	if(kr->putstring(c.dfd, pks) < 0)
		return (sys->sprint("can't send your public key: %r"), nil);
	(s, err) = kr->getstring(c.dfd);
	if(err != nil)
		return ("can't get certificate: " + err, nil);
	info.cert = kr->strtocert(s);
	if(info.cert == nil || !certifies(info.spk, info.cert, array of byte pks))
		return ("the certificate is not the signer's for this key", nil);
	return (nil, info);
}

# the X25519 secret key the password gives its user: HKDF-SHA256 of
# the password's SHA-1, with the user's name
wkey(id: string, secret: array of byte): array of byte
{
	l := array of byte (Label + " verifier");
	n := array of byte id;
	info := array[len l + 1 + len n] of byte;
	info[0:] = l;
	info[len l] = byte 0;
	info[len l + 1:] = n;
	return crypt->hkdfsha256(nil, secret, info, 32);
}

# what a signer keeps to recognise that key's holder: a tag, and its public key
verifier(id: string, secret: array of byte): array of byte
{
	if(sys == nil)
		sys = load Sys Sys->PATH;
	if(crypt == nil)
		crypt = load Crypt Crypt->PATH;
	if(crypt == nil || len secret != Keyring->SHA1dlen)
		return nil;
	w := wkey(id, secret);
	if(w == nil)
		return nil;
	return cat(array of byte Verifiertag, crypt->x25519base(w));
}

allzero(a: array of byte): int
{
	x := 0;
	for(i := 0; i < len a; i++)
		x |= int a[i];
	return x == 0;
}

certifies(pk: ref Keyring->PK, cert: ref Keyring->Certificate, buf: array of byte): int
{
	state: ref Keyring->DigestState;
	case cert.ha {
	"sha" or "sha1" =>
		state = kr->sha1(buf, len buf, nil, nil);
	"sha256" =>
		state = kr->sha256(buf, len buf, nil, nil);
	"sha512" =>
		state = kr->sha512(buf, len buf, nil, nil);
	* =>
		return 0;
	}
	return kr->verify(pk, cert, state);
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

#
# messages before ssl is pushed, as in auth(6): a four-digit count and a
# newline, then that many bytes; an error has "!" and a three-digit count
#
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
		raise Remote+sys->sprint("remote: write error: %r");
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
		raise Remote+"remote: hung up";
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
		raise Remote+"remote: hung up";
	if(iserr)
		raise Remote+"remote: "+string m;
	return m;
}

# The signer's first message. A signer that has only version 1 takes our
# version for the start of a long record and says nothing, so do not wait
# for ever.
firstmsg(fd: ref Sys->FD): array of byte
{
	rc := chan of (array of byte, string);
	pidc := chan of int;
	spawn reader(fd, rc, pidc);
	rpid := <-pidc;
	spawn timer(Patience, pidc);
	tpid := <-pidc;
	alt{
	(m, e) := <-rc =>
		kill(tpid);
		if(e != nil)
			raise e;
		return m;
	<-pidc =>
		kill(rpid);
		raise Remote+"no answer: the signer may have only version 1 of the login protocol";
	}
}

reader(fd: ref Sys->FD, rc: chan of (array of byte, string), pidc: chan of int)
{
	pidc <-= sys->pctl(0, nil);
	{
		rc <-= (getmsg(fd), nil);
	}exception e{
	"login *" =>
		rc <-= (nil, e);
	}
}

timer(ms: int, c: chan of int)
{
	c <-= sys->pctl(0, nil);
	sys->sleep(ms);
	c <-= 0;
}

kill(pid: int)
{
	fd := sys->open("#p/" + string pid + "/ctl", Sys->OWRITE);
	if(fd != nil)
		sys->fprint(fd, "kill");
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

# send a message and add it to the transcript
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
# version 1: the Inferno Encrypt Key Exchange Protocol
#
# Copyright © 1995-1999 Lucent Techologies Inc.  All rights reserved.
#
# This code uses methods that are subject to one or more patents
# held by Lucent Technologies Inc.  Its use outside Inferno
# requires a separate licence from Lucent.
#
login1(id: string, digest: array of byte, fd: ref Sys->FD): (string, ref Keyring->Authinfo)
{
	# push ssl, leave in clear mode for now
	(err, c) := ssl->connect(fd);
	if(c == nil)
		return ("can't push ssl: " + err, nil);
	fd = nil;

	# user->CA	name
	if(kr->putstring(c.dfd, id) < 0)
		return (sys->sprint("can't send user name: %r"), nil);

	# CA->user	ACK
	(s, why) := kr->getstring(c.dfd);
	if(why != nil)
		return ("remote: " + why, nil);
	if(s != id)
		return ("unexpected reply from signer: " + s, nil);

	# user->CA	ivec
	ivec := random(8);
	if(ivec == nil)
		return ("can't get random bytes", nil);
	if(kr->putbytearray(c.dfd, ivec, len ivec) < 0)
		return (sys->sprint("can't send initialization vector: %r"), nil);

	# start encrypting
	pwbuf := array[8] of byte;
	for(i := 0; i < 8; i++)
		pwbuf[i] = digest[i] ^ digest[8+i];
	for(i = 0; i < 4; i++)
		pwbuf[i] ^= digest[16+i];
	for(i = 0; i < 8; i++)
		pwbuf[i] ^= ivec[i];
	err = ssl->secret(c, pwbuf, pwbuf);
	if(err != nil)
		return ("can't set secret: " + err, nil);
	if(sys->fprint(c.cfd, "alg rc4") < 0)
		return (sys->sprint("can't push alg rc4: %r"), nil);
	#if(sys->fprint(c.cfd, "alg desebc") < 0)
	#	return (sys->sprint("can't push alg desecb: %r"), nil);

	# CA -> user	key(alpha**r0 mod p)
	(s, err) = kr->getstring(c.dfd);
	if(err != nil){
		if(err == "failure") # calculated secret is wrong
			return ("name or secret incorrect (alpha**r0 mod p)", nil);
		return ("remote:" + err, nil);
	}

	# stop encrypting
	if(sys->fprint(c.cfd, "alg clear") < 0)
		return (sys->sprint("can't push alg clear: %r"), nil);
	alphar0 := IPint.b64toip(s);
	if(alphar0 == nil)
		return ("name or secret incorrect", nil);	# with a wrong secret the signer's messages decrypt to rubbish

	# CA->user	alpha
	(s, err) = kr->getstring(c.dfd);
	if(err != nil){
		if(err == "failure")
			return ("name or secret incorrect (alpha)", nil);
		return ("remote: " + err, nil);
	}
	info := ref Keyring->Authinfo;
	info.alpha = IPint.b64toip(s);
	if(info.alpha == nil)
		return ("name or secret incorrect", nil);	# with a wrong secret the signer's messages decrypt to rubbish

	# CA->user	p
	(s, err) = kr->getstring(c.dfd);
	if(err != nil){
		if(err == "failure")
			return ("name or secret incorrect (p)", nil);
		return ("remote: " + err, nil);
	}
	info.p = IPint.b64toip(s);
	if(info.p == nil)
		return ("name or secret incorrect", nil);	# with a wrong secret the signer's messages decrypt to rubbish

	# sanity check
	bits := info.p.bits();
	abits := info.alpha.bits();
	if(abits > bits || abits < 2)
		return ("bogus diffie hellman constants", nil);

	# generate our random diffie hellman part
	r1 := kr->IPint.random(bits/4, bits);
	alphar1 := info.alpha.expmod(r1, info.p);

	# user->CA	alpha**r1 mod p
	if(kr->putstring(c.dfd, alphar1.iptob64()) < 0)
		return (sys->sprint("can't send (alpha**r1 mod p): %r"), nil);

	# compute alpha**(r0*r1) mod p
	alphar0r1 := alphar0.expmod(r1, info.p);

	# turn on digesting
	secret := alphar0r1.iptobytes();
	err = ssl->secret(c, secret, secret);
	if(err != nil)
		return ("can't set digesting: " + err, nil);
	if(sys->fprint(c.cfd, "alg sha1") < 0)
		return (sys->sprint("can't push alg sha1: %r"), nil);

	# CA->user	CA's public key, SHA(CA's public key + secret)
	(s, err) = kr->getstring(c.dfd);
	if(err != nil)
		return ("can't get signer's public key: " + err, nil);

	info.spk = kr->strtopk(s);
	if(info.spk == nil)
		return ("bad public key from signer", nil);

	# generate a key pair
	info.mysk = kr->genSKfromPK(info.spk, id);
	if(info.mysk == nil)
		return ("can't generate a key like the signer's", nil);
	info.mypk = kr->sktopk(info.mysk);

	# user->CA	user's public key, SHA(user's public key + secret)
	if(kr->putstring(c.dfd, kr->pktostr(info.mypk)) < 0)
		return (sys->sprint("can't send your public: %r"), nil);

	# CA->user	user's public key certificate
	(s, err) = kr->getstring(c.dfd);
	if(err != nil)
		return ("can't get certificate: " + err, nil);

	info.cert = kr->strtocert(s);
	if(info.cert == nil)
		return ("bad certificate from signer", nil);
	return(nil, info);
}

nomod(mod: string): (string, ref Keyring->Authinfo)
{
	return (sys->sprint("can't load module %s: %r", mod), nil);
}
