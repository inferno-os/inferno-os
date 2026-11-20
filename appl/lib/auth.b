# Inferno authentication protocol
#
# Version 2 (the default): a hybrid X25519 + ML-KEM-768 key exchange, both
# ends signing a hash of everything said, HKDF-SHA256 to one key for each
# direction, and chacha20poly1305 records from the ssl device (or none,
# if both ends agree to that under their signatures).
#
# Version 1 (the original station-to-station exchange over a fixed
# Diffie-Hellman group, see auth(6)) is spoken only when asked for: by a
# client whose algorithm is "v1" or begins "v1/", and by a server whose
# algorithm list includes "v1". Neither end falls back to it.
#
implement Auth;

include "sys.m";
	sys: Sys;

include "keyring.m";
	kr: Keyring;
	IPint: import kr;
	SK, PK, Certificate, DigestState: import Keyring;

include "ipints.m";
include "crypt.m";
	crypt: Crypt;

include "security.m";
	ssl: SSL;
	random: Random;

include "daytime.m";

Aead: con "chacha20poly1305";
Maxmsg: con 9999;		# the most a four-digit count allows
Xlen: con 32;			# X25519 keys and secrets
Eklen: con 1184;		# ML-KEM-768 encapsulation key
Ctlen: con 1088;		# ML-KEM-768 ciphertext
Label: con "inferno auth 2";

# string exceptions inside this module: Fail is our complaint, to be sent
# to the peer; Remote is the peer's complaint, or a dead link
Fail: con "auth fail:";
Remote: con "auth remote:";

init(): string
{
	if(sys == nil)
		sys = load Sys Sys->PATH;
	return nil;	
}

loadmods(): string
{
	if(sys == nil)
		sys = load Sys Sys->PATH;
	if(kr == nil)
		kr = load Keyring Keyring->PATH;
	if(kr == nil)
		return sys->sprint("can't load %s: %r", Keyring->PATH);
	return nil;
}

loadv2(): string
{
	if(crypt == nil)
		crypt = load Crypt Crypt->PATH;
	if(crypt == nil)
		return sys->sprint("can't load %s: %r", Crypt->PATH);
	if(random == nil)
		random = load Random Random->PATH;
	if(random == nil)
		return sys->sprint("can't load %s: %r", Random->PATH);
	return nil;
}

server(algs: list of string, ai: ref Keyring->Authinfo, fd: ref Sys->FD, setid: int): (ref Sys->FD, string)
{
	if((err := loadmods()) != nil)
		return (nil, err);

	# a version 1 client announces itself without waiting; so does ours
	v: string;
	{
		v = string getmsg(fd);
	}exception e{
	"auth *" =>
		return (nil, what(e));
	}
	v1ok := 0;
	nalgs: list of string;
	for(l := algs; l != nil; l = tl l)
		if(hd l == "v1")
			v1ok = 1;
		else
			nalgs = hd l :: nalgs;
	if(v1ok)
		algs = nalgs;

	case v {
	"1" =>
		if(!v1ok){
			senderrmsg(fd, "version 1 authentication not accepted");
			return (nil, "client offers only version 1 authentication");
		}
		return server1(algs, ai, fd, setid);
	"2" =>
		;
	* =>
		senderrmsg(fd, "incompatible authentication protocol");
		return (nil, "incompatible authentication protocol");
	}

	(id, alg, cs, sc, e) := auth2(fd, ai, 1, nil, algs);
	if(e != nil){
		if(setid)
			setuser("nobody");
		return (nil, e);
	}
	if(setid)
		setuser(id);
	if(alg == "none")
		return (fd, id);
	return push(fd, cs, sc, alg, id);
}

client(alg: string, ai: ref Keyring->Authinfo, fd: ref Sys->FD): (ref Sys->FD, string)
{
	if((err := loadmods()) != nil)
		return (nil, err);
	if(alg == "v1")
		return client1("none", ai, fd);
	if(len alg > 3 && (alg[0:3] == "v1/" || alg[0:3] == "v1 "))
		return client1(alg[3:], ai, fd);

	(id, calg, cs, sc, e) := auth2(fd, ai, 0, alg, nil);
	if(e != nil)
		return (nil, e);
	if(calg == "none")
		return (fd, id);
	return push(fd, sc, cs, calg, id);
}

auth(ai: ref Keyring->Authinfo, keyspec: string, alg: string, fd: ref Sys->FD): (ref Sys->FD, ref Keyring->Authinfo, string)
{
	if((err := loadmods()) != nil)
		return (nil, nil, err);
	if(ai == nil && keyspec != nil){
		ai = key(keyspec);
		if(ai == nil)
			return (nil, nil, sys->sprint("can't obtain key: %r"));
	}
	(c, id_or_err) := client(alg, ai, fd);
	return (c, nil, id_or_err);
}

push(fd: ref Sys->FD, secretin, secretout: array of byte, alg: string, id: string): (ref Sys->FD, string)
{
	ssl = load SSL SSL->PATH;
	if(ssl == nil)
		return (nil, sys->sprint("can't load ssl: %r"));
	(c, err) := pushssl(fd, secretin, secretout, alg);
	if(c == nil)
		return (nil, "push ssl: " + err);
	return (c, id);
}

# an exception's text without its prefix
what(e: string): string
{
	for(i := 0; i < len e; i++)
		if(e[i] == ':')
			return e[i+1:];
	return e;
}

setuser(id: string)
{
	fd := sys->open("#c/user", Sys->OWRITE);
	if(fd != nil)
		sys->fprint(fd, "%s", id);
}

#
# messages before ssl is pushed, in the format of version 1:
# a four-digit count and a newline, then that many bytes;
# an error has "!" and a three-digit count. Unlike Keyring's
# getmsg these take the four digits at their word (up to 9999).
#
sendmsg(fd: ref Sys->FD, m: array of byte)
{
	if(len m > Maxmsg)
		raise Remote+"message too long to send";
	h := array of byte sys->sprint("%4.4d\n", len m);
	b := array[len h + len m] of byte;
	b[0:] = h;
	b[len h:] = m;
	if(write(fd, b) != len b)
		raise Remote+sys->sprint("remote: write error: %r");
}

senderrmsg(fd: ref Sys->FD, e: string)
{
	m := array of byte e;
	if(len m > 255)
		m = m[0:255];
	h := array of byte sys->sprint("!%3.3d\n", len m);
	b := array[len h + len m] of byte;
	b[0:] = h;
	b[len h:] = m;
	write(fd, b);
}

# A write to a pipe whose other end has gone raises an exception as well
# as failing. (Compiled code, emu -c1, can miss the handler: its search
# has no program counter for a function that is inside a built-in call.)
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
putm(fd: ref Sys->FD, th: ref DigestState, who: int, m: array of byte): ref DigestState
{
	sendmsg(fd, m);
	return addmsg(th, who, m);
}

getm(fd: ref Sys->FD, th: ref DigestState, who: int): (ref DigestState, array of byte)
{
	m := getmsg(fd);
	return (addmsg(th, who, m), m);
}

addmsg(th: ref DigestState, who: int, m: array of byte): ref DigestState
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

# the peer's key, if its certificate is our signer's and still valid
checkcert(ai: ref Keyring->Authinfo, certb, pkb: array of byte): ref PK
{
	cert := kr->strtocert(string certb);
	if(cert == nil)
		raise Fail+"bad certificate";
	pk := kr->strtopk(string pkb);
	if(pk == nil)
		raise Fail+"bad public key";
	if(verify(ai.spk, cert, pkb) == 0)
		raise Fail+"pk doesn't match certificate";
	if(cert.exp != 0 && cert.exp <= now())
		raise Fail+"certificate expired";
	return pk;
}

sigtext(role: string, T: array of byte): array of byte
{
	l := array of byte (Label + " " + role);
	b := array[len l + 1 + len T] of byte;
	b[0:] = l;
	b[len l] = byte 0;
	b[len l + 1:] = T;
	return b;
}

mksig(ai: ref Keyring->Authinfo, role: string, T: array of byte): array of byte
{
	b := sigtext(role, T);
	c: ref Certificate;
	if(bytesigner(ai.mysk.sa.name))
		c = kr->sign(ai.mysk, 0, kr->sha256(b, len b, nil, nil), "sha256");
	else
		c = kr->sign(ai.mysk, 0, kr->sha1(b, len b, nil, nil), "sha1");
	if(c == nil)
		raise Fail+"can't sign";
	return array of byte kr->certtostr(c);
}

checksig(pk: ref PK, sig: array of byte, role: string, T: array of byte)
{
	c := kr->strtocert(string sig);
	if(c == nil)
		raise Fail+"bad signature";
	b := sigtext(role, T);
	state: ref DigestState;
	if(bytesigner(pk.sa.name)){
		if(c.ha != "sha256")
			raise Fail+"bad signature";
		state = kr->sha256(b, len b, nil, nil);
	}else{
		if(c.ha != "sha1" && c.ha != "sha")
			raise Fail+"bad signature";
		state = kr->sha1(b, len b, nil, nil);
	}
	if(kr->verify(pk, c, state) == 0)
		raise Fail+"signature does not match the exchange";
}

# the algorithms that sign bytes, and take sha256; the older ones keep sha1
bytesigner(alg: string): int
{
	return alg == "ed25519" || alg == "ed25519mldsa65";
}

kdf(T, ikm: array of byte, what: string): array of byte
{
	return crypt->hkdfsha256(T, ikm, array of byte (Label + " " + what), 32);
}

verify(pk: ref PK, cert: ref Certificate, buf: array of byte): int
{
	state: ref DigestState;
	case cert.ha {
	"sha" or "sha1" =>
		state = kr->sha1(buf, len buf, nil, nil);
	"md5" =>
		state = kr->md5(buf, len buf, nil, nil);
	"md4" =>
		state = kr->md4(buf, len buf, nil, nil);
	"sha256" =>
		state = kr->sha256(buf, len buf, nil, nil);
	"sha512" =>
		state = kr->sha512(buf, len buf, nil, nil);
	* =>
		return 0;
	}
	return kr->verify(pk, cert, state);
}

#
# version 2
#
# c: "2"				s: "2"
# c: alg, X25519 key || ML-KEM key, certificate, public key
# s: alg, X25519 key || ML-KEM ciphertext, certificate, public key,
#    signature, confirmation
# c: signature, confirmation		s: "OK"
#
# T = SHA-256 of the label and the eight messages before the signatures,
# each with a direction byte and a four-byte count. Each end signs its role
# and T with the key its certificate vouches for. The key material is the
# ML-KEM secret then the X25519 secret, and every key is
# HKDF-SHA256(salt T, that material, a label).
#
# returns (peer's name, record algorithm, client-to-server key, server-to-client key, error)
#
auth2(fd: ref Sys->FD, ai: ref Keyring->Authinfo, isserver: int, alg: string, algs: list of string): (string, string, array of byte, array of byte, string)
{
	if((err := loadv2()) != nil){
		senderrmsg(fd, "no version 2 authentication here");
		return (nil, nil, nil, nil, err);
	}
	r: (string, string, array of byte, array of byte, string);
	{
		if(isserver)
			r = server2(fd, ai, algs);
		else
			r = client2(fd, ai, alg);
	}exception e{
	"auth fail:*" =>
		senderrmsg(fd, what(e));
		return (nil, nil, nil, nil, what(e));
	"auth remote:*" =>
		return (nil, nil, nil, nil, what(e));
	}
	return r;
}

client2(fd: ref Sys->FD, ai: ref Keyring->Authinfo, alg: string): (string, string, array of byte, array of byte, string)
{
	sendmsg(fd, array of byte "2");
	if(ai == nil)
		raise Fail+"no authentication information";
	v := string getmsg(fd);
	if(v != "2")
		raise Fail+"server offers only version "+v+" authentication";

	if(alg != "none")
		alg = Aead;	# every other name meant "protect the link"
	xsk := random->randombuf(Random->ReallyRandom, Xlen);
	(ek, dk) := crypt->mlkem768keygen();
	if(xsk == nil || len xsk != Xlen || ek == nil)
		raise Fail+"can't make keys";
	kex := array[Xlen+Eklen] of byte;
	kex[0:] = crypt->x25519base(xsk);
	kex[Xlen:] = ek;

	th := kr->sha256(array of byte Label, len Label + 1, nil, nil);
	th = putm(fd, th, 'c', array of byte alg);
	th = putm(fd, th, 'c', kex);
	th = putm(fd, th, 'c', array of byte kr->certtostr(ai.cert));
	th = putm(fd, th, 'c', array of byte kr->pktostr(ai.mypk));

	salg, skex, scert, spk: array of byte;
	(th, salg) = getm(fd, th, 's');
	(th, skex) = getm(fd, th, 's');
	(th, scert) = getm(fd, th, 's');
	(th, spk) = getm(fd, th, 's');
	T := array[Keyring->SHA256dlen] of byte;
	kr->sha256(nil, 0, T, th);

	if(string salg != alg)
		raise Fail+"server chose algorithm "+string salg;
	if(len skex != Xlen+Ctlen)
		raise Fail+"bad key exchange message";
	hispk := checkcert(ai, scert, spk);
	checksig(hispk, getmsg(fd), "server", T);

	ikm := array[2*Xlen] of byte;
	ss := crypt->mlkem768decap(dk, skex[Xlen:]);
	xs := crypt->x25519(xsk, skex[0:Xlen]);
	if(ss == nil || xs == nil || allzero(xs))
		raise Fail+"bad key exchange value";
	ikm[0:] = ss;
	ikm[Xlen:] = xs;
	if(!eq(getmsg(fd), kdf(T, ikm, "confirm s")))
		raise Fail+"key confirmation failed";

	sendmsg(fd, mksig(ai, "client", T));
	sendmsg(fd, kdf(T, ikm, "confirm c"));
	if(string getmsg(fd) != "OK")
		raise Fail+"no final acknowledgement";
	return (hispk.owner, alg, kdf(T, ikm, "c2s"), kdf(T, ikm, "s2c"), nil);
}

server2(fd: ref Sys->FD, ai: ref Keyring->Authinfo, algs: list of string): (string, string, array of byte, array of byte, string)
{
	# the client's "2" has been read
	sendmsg(fd, array of byte "2");
	if(ai == nil)
		raise Fail+"no server certificate";

	th := kr->sha256(array of byte Label, len Label + 1, nil, nil);
	calg, ckex, ccert, cpk: array of byte;
	(th, calg) = getm(fd, th, 'c');
	(th, ckex) = getm(fd, th, 'c');
	(th, ccert) = getm(fd, th, 'c');
	(th, cpk) = getm(fd, th, 'c');

	alg := string calg;
	case alg {
	Aead =>
		;
	"none" =>
		# as before, an empty list accepts anything
		if(algs != nil){
			for(l := algs; l != nil; l = tl l)
				if(hd l == "none")
					break;
			if(l == nil)
				raise Fail+"unsupported client algorithm: none";
		}
	* =>
		raise Fail+"unsupported client algorithm: "+alg;
	}
	if(len ckex != Xlen+Eklen)
		raise Fail+"bad key exchange message";
	hispk := checkcert(ai, ccert, cpk);

	xsk := random->randombuf(Random->ReallyRandom, Xlen);
	(ct, ss) := crypt->mlkem768encap(ckex[Xlen:]);
	if(xsk == nil || len xsk != Xlen || ct == nil || ss == nil)
		raise Fail+"can't make keys";
	xs := crypt->x25519(xsk, ckex[0:Xlen]);
	if(xs == nil || allzero(xs))
		raise Fail+"bad key exchange value";
	kex := array[Xlen+Ctlen] of byte;
	kex[0:] = crypt->x25519base(xsk);
	kex[Xlen:] = ct;
	ikm := array[2*Xlen] of byte;
	ikm[0:] = ss;
	ikm[Xlen:] = xs;

	th = putm(fd, th, 's', calg);
	th = putm(fd, th, 's', kex);
	th = putm(fd, th, 's', array of byte kr->certtostr(ai.cert));
	th = putm(fd, th, 's', array of byte kr->pktostr(ai.mypk));
	T := array[Keyring->SHA256dlen] of byte;
	kr->sha256(nil, 0, T, th);
	sendmsg(fd, mksig(ai, "server", T));
	sendmsg(fd, kdf(T, ikm, "confirm s"));

	checksig(hispk, getmsg(fd), "client", T);
	if(!eq(getmsg(fd), kdf(T, ikm, "confirm c")))
		raise Fail+"key confirmation failed";
	sendmsg(fd, array of byte "OK");
	return (hispk.owner, alg, kdf(T, ikm, "c2s"), kdf(T, ikm, "s2c"), nil);
}

now(): int
{
	daytime := load Daytime Daytime->PATH;
	if(daytime == nil)
		return 0;
	return daytime->now();
}

allzero(a: array of byte): int
{
	x := 0;
	for(i := 0; i < len a; i++)
		x |= int a[i];
	return x == 0;
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

#
# version 1
#

client1(alg: string, ai: ref Keyring->Authinfo, fd: ref Sys->FD): (ref Sys->FD, string)
{
	if(alg == nil)
		alg = "none";

	# mutual authentication
	id_or_err: string;
	secret: array of byte;
	{
		(id_or_err, secret) = auth1c(fd, ai, alg);
		if(secret == nil)
			return (nil, id_or_err);
	}exception{
	"write on closed pipe" =>
		# the server gave its reason, if it had one, before it went
		if(id_or_err == nil)
			id_or_err = "remote: hung up";
		return (nil, id_or_err);
	}

	# don't push ssl if server supports no ssl connection
	if(alg == "none")
		return (fd, id_or_err);

	return push(fd, secret, secret, alg, id_or_err);
}

# Keyring's auth and the client's choice of algorithm; in a function
# of its own so that client1 can catch a closed pipe (see write0)
auth1c(fd: ref Sys->FD, ai: ref Keyring->Authinfo, alg: string): (string, array of byte)
{
	(id_or_err, secret) := kr->auth(fd, ai, 0);
	if(secret == nil)
		return (id_or_err, nil);
	buf := array of byte alg;
	if(kr->sendmsg(fd, buf, len buf) < 0)
		return (sys->sprint("can't send ssl algorithm: %r"), nil);
	return (id_or_err, secret);
}

# the server's side once the client's "1" has been read
server1(algs: list of string, ai: ref Keyring->Authinfo, fd: ref Sys->FD, setid: int): (ref Sys->FD, string)
{
	(id, secret, err) := auth1(fd, ai);
	if(err != nil){
		if(setid)
			setuser("nobody");
		return (nil, err);
	}
	if(setid)
		setuser(id);

	# have got a secret, get algorithm from client
	# check if the client algorithm is in the server algorithm list
	# client algorithm ::= ident (' ' ident)*
	# where ident is defined by ssl(3)
	algbuf := string kr->getmsg(fd);
	if(algbuf == nil)
		return (nil, sys->sprint("can't read client ssl algorithm: %r"));
	alg := "";
	(nil, calgs) := sys->tokenize(algbuf, " /");
	for(; calgs != nil; calgs = tl calgs){
		calg := hd calgs;
		if(algs != nil){	# otherwise we suck it and see
			for(sl := algs; sl != nil; sl = tl sl)
				if(hd sl == calg)
					break;
			if(sl == nil)
				return (nil, "unsupported client algorithm: " + calg);
		}
		alg += calg + " ";
	}
	if(alg != nil)
		alg = alg[0:len alg - 1];

	# don't push ssl if server supports nossl
	if(alg == nil || alg == "none")
		return (fd, id);

	return push(fd, secret, secret, alg, id);
}

#
# Keyring's auth (see auth(6)), less its first step, the exchange of
# version numbers, which the caller has done; after
# appl/cmd/auth/factotum/proto/infauth.b
#
auth1(fd: ref Sys->FD, ai: ref Keyring->Authinfo): (string, array of byte, string)
{
	err: string;
	id: string;
	secret: array of byte;
	{
		sendmsg(fd, array of byte "1");
		if(ai == nil)
			raise Fail+"no server certificate";

		# generate alpha**r0
		p := ai.p;
		low := p.shr(p.bits()/4);
		r0 := rand(low, p);
		alphar0 := ai.alpha.expmod(r0, p);

		# send alpha**r0 mod p, mycert, and mypk
		sendmsg(fd, array of byte alphar0.iptob64z());
		sendmsg(fd, array of byte kr->certtostr(ai.cert));
		sendmsg(fd, array of byte kr->pktostr(ai.mypk));

		# get alpha**r1 mod p, hiscert, hispk
		alphar1 := IPint.b64toip(string getmsg(fd));
		if(alphar1 == nil || p.cmp(alphar1) <= 0)
			raise Fail+"implausible parameter value";
		# if alpha**r1 == alpha**r0, someone may be trying a replay
		if(alphar0.eq(alphar1))
			raise Fail+"possible replay attack";
		certb := getmsg(fd);
		pkb := getmsg(fd);
		hispk := checkcert(ai, certb, pkb);

		# sign alpha**r0 and alpha**r1 and send
		b := array of byte (alphar0.iptob64z() + alphar1.iptob64z());
		c := kr->sign(ai.mysk, 0, kr->sha1(b, len b, nil, nil), "sha1");
		if(c == nil)
			raise Fail+"can't sign";
		sendmsg(fd, array of byte kr->certtostr(c));

		# get signature of alpha**r1 and alpha**r0 and verify
		c = kr->strtocert(string getmsg(fd));
		if(c == nil)
			raise Fail+"alpha**r1 doesn't match certificate";
		if(verify(hispk, c, array of byte (alphar1.iptob64z() + alphar0.iptob64z())) == 0)
			raise Fail+"bad certificate";

		# we are now authenticated and have a common secret, alpha**(r0*r1)
		id = hispk.owner;
		secret = alphar1.expmod(r0, p).iptobebytes();
		sendmsg(fd, array of byte "OK");
	}exception e{
	"auth fail:*" =>
		err = what(e);
		senderrmsg(fd, err);
	"auth remote:*" =>
		return (nil, nil, what(e));
	}

	{
		while(string getmsg(fd) != "OK")
			;
	}exception e{
	"auth *" =>
		return (nil, nil, what(e));
	}
	if(err != nil)
		return (nil, nil, err);
	return (id, secret, nil);
}

rand(p, q: ref IPint): ref IPint
{
	if(p.cmp(q) > 0)
		(p, q) = (q, p);
	diff := q.sub(p);
	if(diff.cmp(IPint.inttoip(2)) < 0)
		return IPint.inttoip(0);
	l := diff.bits();
	T := IPint.inttoip(1).shl(l);
	l = ((l + 7) / 8) * 8;
	slop := T.div(diff).t1;
	r: ref IPint;
	do{
		r = IPint.random(0, l);
	}while(r.cmp(slop) < 0);
	return r.div(diff).t1.add(p);
}

dump(b: array of byte): string
{
	s := "";
	for(i := 0; i < len b; i++)
		s += sys->sprint("%.2ux", int b[i]);
	return s;
}

# push an SSLv2 Record Layer onto the fd
pushssl(fd: ref Sys->FD, secretin, secretout: array of byte, alg: string): (ref Sys->FD, string)
{
	(err, c) := ssl->connect(fd);
	if(err != nil)
		return (nil, "can't connect ssl: " + err);

	err = ssl->secret(c, secretin, secretout);
	if(err != nil)
		return (nil, "can't write secret: " + err);

	if(sys->fprint(c.cfd, "alg %s", alg) < 0)
		return (nil, sys->sprint("can't push algorithm %s: %r", alg));

	return (c.dfd, nil);
}

key(keyspec: string): ref Keyring->Authinfo
{
	f := keyfile(keyspec);
	if(f == nil)
		return nil;
	kr = load Keyring Keyring->PATH;
	if(kr == nil){
		sys->werrstr(sys->sprint("can't load %s: %r", Keyring->PATH));
		return nil;
	}
	return kr->readauthinfo(f);
}

#
# look for key in old style keyring directory;
# closest match to [net!]addr[!svc]
#

keyfile(keyspec: string): string
{
	if(sys == nil)
		sys = load Sys Sys->PATH;
	al := parseattr(keyspec);
	keyname := get(al, "key");
	if(keyname != nil){
		# explicit keyname overrides rest of spec
		if(keyname[0] == '/' ||
		   len keyname > 2 && keyname[0:2]=="./" ||
		   len keyname > 3 && keyname[0:3]=="../")
			return keyname;	# don't add directory
		return keydir()+keyname;
	}
	net := "net";
	svc := get(al, "service");
	addr := get(al, "server");
	(nf, flds) := sys->tokenize(addr, "!");	# compatibility
	if(nf > 1){
		net = hd flds;
		addr = hd tl flds;
	}
	if(addr != nil)
		keyname = addr;
	else
		keyname = "default";
	kd := keydir();
	dom := get(al, "dom");
	if(dom != nil){
		if((cert := exists(kd+dom)) != nil)
			return cert;
	}
	if(keyname == "default")
		return kd+"default";
	if(net == "net")
		l := "net!" :: "tcp!" :: nil;
	else
		l = net+"!" :: nil;
	if(svc != nil){
		for(nl := l; nl != nil; nl = tl nl){
			cert := exists(kd+(hd nl)+keyname+"!"+svc);	# most specific
			if(cert != nil)
				return cert;
		}
	}
	for(nl := l; nl != nil; nl = tl nl){
		cert := exists(kd+(hd nl)+keyname);
		if(cert != nil)
			return cert;
	}
	cert := exists(kd+keyname);	# unadorned
	if(cert != nil)
		return cert;
	if(keyname != "default"){
		cert = exists(kd+"default");
		if(cert != nil)
			return cert;
	}
	return kd+keyname;
}

keydir(): string
{
	fd := sys->open("/dev/user", Sys->OREAD);
	if(fd == nil)
		return nil;
	b := array[Sys->NAMEMAX] of byte;
	nr := sys->read(fd, b, len b);
	if(nr <= 0){
		sys->werrstr("can't read /dev/user");
		return nil;
	}
	user := string b[0:nr];
	return "/usr/" + user + "/keyring/";
}

exists(f: string): string
{
	(ok, nil) := sys->stat(f);
	if(0)sys->fprint(sys->fildes(2), "exists: %q %d\n", f, ok>=0);
	if(ok >= 0)
		return f;
	return nil;
}

Aattr, Aval, Aquery: con iota;

Attr: adt {
	tag:	int;
	name:	string;
	val:	string;
};

parseattr(s: string): list of ref Attr
{
	(nil, fld) := sys->tokenize(s, " \t\n");	# should do quoting; later
	rfld := fld;
	for(fld = nil; rfld != nil; rfld = tl rfld)
		fld = (hd rfld) :: fld;
	attrs: list of ref Attr;
	for(; fld != nil; fld = tl fld){
		n := hd fld;
		a := "";
		tag := Aattr;
		for(i:=0; i<len n; i++)
			if(n[i] == '='){
				a = n[i+1:];
				n = n[0:i];
				tag = Aval;
			}
		if(len n == 0)
			continue;
		if(tag == Aattr && len n > 1 && n[len n-1] == '?'){
			tag = Aquery;
			n = n[0:len n-1];
		}
		attrs = ref Attr(tag, n, a) :: attrs;
	}
	return attrs;
}

get(al: list of ref Attr, n: string): string
{
	for(; al != nil; al = tl al)
		if((a := hd al).name == n && a.tag == Aval)
			return a.val;
	return nil;
}
