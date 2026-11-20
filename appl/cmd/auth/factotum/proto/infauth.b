implement Authproto;

include "sys.m";
	sys: Sys;
include "draw.m";
include "keyring.m";
	keyring: Keyring;
	IPint: import keyring;
	SK, PK, Certificate, DigestState: import Keyring;
include "security.m";
	random: Random;
include "ipints.m";
include "crypt.m";
	crypt: Crypt;
include "bufio.m";
include "sexprs.m";
	sexprs: Sexprs;
	Sexp: import sexprs;
include "spki.m";
	spki: SPKI;
include "daytime.m";
	daytime: Daytime;
include "keyreps.m";
	keyreps: Keyreps;
	Keyrep: import keyreps;
include "../authio.m";
	authio: Authio;
	Aattr, Aval, Aquery: import Authio;
	Attr, IO, Key, Authinfo: import authio;

# at end of authentication, sign a hash of the authenticated username and
# a secret known only to factotum. that certificate can act as
# a later proof that this factotum has authenticated that user,
# and hence factotum will disclose certificates that allow disclosure
# only to that username.

Debug: con 0;

Maxmsg: con 4000;

Error0, Error1: exception(string);

init(f: Authio): string
{
	authio = f;
	sys = load Sys Sys->PATH;
	spki = load SPKI SPKI->PATH;
	spki->init();
	sexprs = load Sexprs Sexprs->PATH;
	sexprs->init();
	keyring = load Keyring Keyring->PATH;
	daytime = load Daytime Daytime->PATH;
	# the tree's keyreps.dis no longer matches keyreps.m (and has no
	# source); without it a principal is given as the key's text
	keyreps = load Keyreps Keyreps->PATH;
	if(keyreps != nil)
		keyreps->init();
	return nil;
}

interaction(attrs: list of ref Attr, io: ref IO): string
{
	ai: ref Authinfo;
	(key, err) := io.findkey(attrs, "proto=infauth");
	if(key == nil)
		return err;
	info: ref Keyring->Authinfo;
	(info, err) = keytoauthinfo(key);
	if(info == nil)
		return err;
	anysigner := int authio->lookattrval(key.attrs, "anysigner");
	# version 2 of auth(6) unless the request or the key says version=1
	if(attrval(attrs, key, "version") != "1")
		return interaction2(attrs, io, key, info, anysigner);
	rattrs: list of ref Sexp;
	{
		# send auth protocol version number
		sendmsg(io, array of byte "1");

		# get auth protocol version number
		if(int string getmsg(io) != 1)
			raise Error0("incompatible authentication protocol");

		# generate alpha**r0
		p := info.p;
		low := p.shr(p.bits()/4);
		r0 := rand(low, p, Random->NotQuiteRandom);
		αr0 := info.alpha.expmod(r0, p);
		# trim(αr0);	the IPint library should do this for us, i think.

		# send alpha**r0 mod p, mycert, and mypk
		sendmsg(io, array of byte αr0.iptob64());
		sendmsg(io, array of byte keyring->certtostr(info.cert));
		sendmsg(io, array of byte keyring->pktostr(info.mypk));

		# get alpha**r1 mod p, hiscert, hispk
		αr1 := IPint.b64toip(string getmsg(io));

		# trying a fast one
		if(p.cmp(αr1) <= 0)
			raise Error0("implausible parameter value");

		# if alpha**r1 == alpha**r0, someone may be trying a replay
		if(αr0.eq(αr1))
			raise Error0("possible replay attack");

		hiscert := keyring->strtocert(string getmsg(io));
		if(hiscert == nil && !anysigner)
			raise Error0(sys->sprint("bad certificate: %r"));

		buf := getmsg(io);
		hispk := keyring->strtopk(string buf);
		if(!anysigner){
			# verify their public key
			if(verify(info.spk, hiscert, buf) == 0)
				raise Error0("pk doesn't match certificate");	# likely the signers don't match.

			# check expiration date - in seconds of epoch
			if(hiscert.exp != 0 && hiscert.exp <= now())
				raise Error0("certificate expired");
		}
		buf = nil;

		# sign alpha**r0 and alpha**r1 and send
		αcert := sign(info.mysk, "sha", 0, array of byte (αr0.iptob64() + αr1.iptob64()));
		sendmsg(io, array of byte keyring->certtostr(αcert));

		# get signature of alpha**r1 and alpha**r0 and verify
		αcert = keyring->strtocert(string getmsg(io));
		if(αcert == nil)
			raise Error0("alpha**r1 doesn't match certificate");

		if(verify(hispk, αcert, array of byte (αr1.iptob64() + αr0.iptob64())) == 0)
			raise Error0(sys->sprint("bad certificate: %r"));

		ai = ref Authinfo;
		# we are now authenticated and have a common secret, alpha**(r0*r1)
		if(!anysigner)
			rattrs = sl(ss("signer") :: principal(info.spk) :: nil) :: rattrs;
		rattrs = sl(ss("remote-pk") :: principal(hispk) :: nil) :: rattrs;
		rattrs = sl(ss("local-pk") :: principal(info.mypk) :: nil) :: rattrs;
		rattrs = sl(ss("secret") :: sb(αr1.expmod(r0, p).iptobytes()) :: nil) :: rattrs;
		ai.suid = hispk.owner;
		ai.cuid = info.mypk.owner;
		sendmsg(io, array of byte "OK");
	}exception e{
	Error0 =>
		err = e;
		senderr(io, e);
		break;
	Error1 =>
		senderr(io, "failed");	# acknowledge error
		return remote(e);
	}

	{	
		while(string getmsg(io) != "OK")
			;
	}exception e{
	Error0 =>
		return e;
	Error1 =>
		return remote(e);
	}
	if(err != nil)
		return err;

	return negotiatecrypto(io, key, ai, rattrs);
}

#
# Version 2 of auth(6), as appl/lib/auth.b speaks it: a hybrid X25519 +
# ML-KEM-768 key exchange, both ends signing a hash of everything said,
# HKDF-SHA256 to a key for each direction. The key or the request must
# say role=client or role=server. The result's secret holds secretin and
# secretout (this end's keys for ssl(3), 32 bytes each) and alg, which is
# chacha20poly1305 or none.
#
Aead: con "chacha20poly1305";
Xlen: con 32;
Eklen: con 1184;
Ctlen: con 1088;
Label: con "inferno auth 2";
Fail: con "infauth fail:";	# our complaint, sent to the peer
Remote: con "infauth remote:";	# the peer's

attrval(attrs: list of ref Attr, key: ref Key, name: string): string
{
	v := authio->lookattrval(attrs, name);
	if(v == nil)
		v = authio->lookattrval(key.attrs, name);
	return v;
}

interaction2(attrs: list of ref Attr, io: ref IO, key: ref Key, info: ref Keyring->Authinfo, anysigner: int): string
{
	if(crypt == nil)
		crypt = load Crypt Crypt->PATH;
	if(random == nil)
		random = load Random Random->PATH;
	if(crypt == nil || random == nil)
		return sys->sprint("infauth: can't load Crypt or Random: %r");
	role := attrval(attrs, key, "role");
	if(role != "client" && role != "server")
		return "infauth: version 2 needs role=client or role=server (or version=1)";
	ai: ref Authinfo;
	{
		ai = exchange2(attrs, io, key, info, anysigner, role == "server");
	}exception e{
	"infauth fail:*" =>
		senderr(io, e[len Fail:]);
		return e[len Fail:];
	"infauth remote:*" =>
		return remote(e[len Remote:]);
	}
	if(role == "server")
		ai.cap = capability(nil, ai.suid);
	io.done(ai);
	return nil;
}

exchange2(attrs: list of ref Attr, io: ref IO, key: ref Key, info: ref Keyring->Authinfo, anysigner: int, isserver: int): ref Authinfo
{
	v, alg: string;
	me, peer: int;
	if(isserver){
		(me, peer) = ('s', 'c');
		v = string gmsg(io);
		if(v == "1")
			raise Fail+"version 1 authentication not accepted";
		if(v != "2")
			raise Fail+"incompatible authentication protocol";
		sendmsg(io, array of byte "2");
	}else{
		(me, peer) = ('c', 's');
		sendmsg(io, array of byte "2");
		v = string gmsg(io);
		if(v != "2")
			raise Fail+"server offers only version "+v+" authentication";
		alg = attrval(attrs, key, ":alg");
		if(alg == nil)
			alg = attrval(attrs, key, "alg");
		if(alg != "none")
			alg = Aead;
	}

	th := keyring->sha256(array of byte Label, len Label + 1, nil, nil);
	xsk := random->randombuf(Random->ReallyRandom, Xlen);
	if(xsk == nil || len xsk != Xlen)
		raise Fail+"can't make keys";
	xpk := crypt->x25519base(xsk);
	ikm := array[2*Xlen] of byte;
	hiscert, hispkb: array of byte;
	mycert := array of byte keyring->certtostr(info.cert);
	mypk := array of byte keyring->pktostr(info.mypk);

	if(isserver){
		calg := gmsg(io);
		ckex := gmsg(io);
		hiscert = gmsg(io);
		hispkb = gmsg(io);
		th = addmsg(addmsg(addmsg(addmsg(th, peer, calg), peer, ckex), peer, hiscert), peer, hispkb);
		alg = string calg;
		if(alg == "none"){
			(nil, algs) := sys->tokenize(attrval(attrs, key, "algs"), " ");
			for(l := algs; l != nil; l = tl l)
				if(hd l == "none")
					break;
			if(algs != nil && l == nil)
				raise Fail+"unsupported client algorithm: none";
		}else if(alg != Aead)
			raise Fail+"unsupported client algorithm: "+alg;
		if(len ckex != Xlen+Eklen)
			raise Fail+"bad key exchange message";
		(ct, ss) := crypt->mlkem768encap(ckex[Xlen:]);
		xs := crypt->x25519(xsk, ckex[0:Xlen]);
		if(ct == nil || ss == nil || xs == nil || allzero(xs))
			raise Fail+"bad key exchange value";
		ikm[0:] = ss;
		ikm[Xlen:] = xs;
		kex := array[Xlen+Ctlen] of byte;
		kex[0:] = xpk;
		kex[Xlen:] = ct;
		sendmsg(io, calg);
		sendmsg(io, kex);
		sendmsg(io, mycert);
		sendmsg(io, mypk);
		th = addmsg(addmsg(addmsg(addmsg(th, me, calg), me, kex), me, mycert), me, mypk);
	}else{
		(ek, dk) := crypt->mlkem768keygen();
		if(ek == nil)
			raise Fail+"can't make keys";
		kex := array[Xlen+Eklen] of byte;
		kex[0:] = xpk;
		kex[Xlen:] = ek;
		balg := array of byte alg;
		sendmsg(io, balg);
		sendmsg(io, kex);
		sendmsg(io, mycert);
		sendmsg(io, mypk);
		th = addmsg(addmsg(addmsg(addmsg(th, me, balg), me, kex), me, mycert), me, mypk);
		salg := gmsg(io);
		skex := gmsg(io);
		hiscert = gmsg(io);
		hispkb = gmsg(io);
		th = addmsg(addmsg(addmsg(addmsg(th, peer, salg), peer, skex), peer, hiscert), peer, hispkb);
		if(string salg != alg)
			raise Fail+"server chose algorithm "+string salg;
		if(len skex != Xlen+Ctlen)
			raise Fail+"bad key exchange message";
		ss := crypt->mlkem768decap(dk, skex[Xlen:]);
		xs := crypt->x25519(xsk, skex[0:Xlen]);
		if(ss == nil || xs == nil || allzero(xs))
			raise Fail+"bad key exchange value";
		ikm[0:] = ss;
		ikm[Xlen:] = xs;
	}
	T := array[Keyring->SHA256dlen] of byte;
	keyring->sha256(nil, 0, T, th);

	# the peer's key, if its certificate is our signer's and still valid
	cert := keyring->strtocert(string hiscert);
	hispk := keyring->strtopk(string hispkb);
	if(hispk == nil)
		raise Fail+"bad public key";
	if(!anysigner){
		if(cert == nil)
			raise Fail+"bad certificate";
		if(verify(info.spk, cert, hispkb) == 0)
			raise Fail+"pk doesn't match certificate";
		if(cert.exp != 0 && cert.exp <= now())
			raise Fail+"certificate expired";
	}

	if(isserver){
		sendmsg(io, mksig(info, "server", T));
		sendmsg(io, kdf(T, ikm, "confirm s"));
		checksig(hispk, gmsg(io), "client", T);
		if(!eq(gmsg(io), kdf(T, ikm, "confirm c")))
			raise Fail+"key confirmation failed";
		sendmsg(io, array of byte "OK");
	}else{
		checksig(hispk, gmsg(io), "server", T);
		if(!eq(gmsg(io), kdf(T, ikm, "confirm s")))
			raise Fail+"key confirmation failed";
		sendmsg(io, mksig(info, "client", T));
		sendmsg(io, kdf(T, ikm, "confirm c"));
		if(string gmsg(io) != "OK")
			raise Fail+"no final acknowledgement";
	}

	c2s := kdf(T, ikm, "c2s");
	s2c := kdf(T, ikm, "s2c");
	(sin, sout) := (s2c, c2s);
	if(isserver)
		(sin, sout) = (c2s, s2c);
	rattrs: list of ref Sexp;
	rattrs = sl(ss("alg") :: ss(alg) :: nil) :: rattrs;
	if(!anysigner)
		rattrs = sl(ss("signer") :: principal(info.spk) :: nil) :: rattrs;
	rattrs = sl(ss("secretout") :: sb(sout) :: nil) :: rattrs;
	rattrs = sl(ss("secretin") :: sb(sin) :: nil) :: rattrs;
	ai := ref Authinfo;
	ai.suid = hispk.owner;
	ai.cuid = info.mypk.owner;
	ai.secret = sl(rattrs).pack();
	return ai;
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
	th = keyring->sha256(h, len h, nil, th);
	return keyring->sha256(m, n, nil, th);
}

bytesigner(alg: string): int
{
	return alg == "ed25519" || alg == "ed25519mldsa65";
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

mksig(info: ref Keyring->Authinfo, role: string, T: array of byte): array of byte
{
	ha := "sha1";
	if(bytesigner(info.mysk.sa.name))
		ha = "sha256";
	c := sign(info.mysk, ha, 0, sigtext(role, T));
	if(c == nil)
		raise Fail+"can't sign";
	return array of byte keyring->certtostr(c);
}

checksig(pk: ref PK, sig: array of byte, role: string, T: array of byte)
{
	c := keyring->strtocert(string sig);
	if(c == nil)
		raise Fail+"bad signature";
	if(bytesigner(pk.sa.name)){
		if(c.ha != "sha256")
			raise Fail+"bad signature";
	}else if(c.ha != "sha1" && c.ha != "sha")
		raise Fail+"bad signature";
	if(verify(pk, c, sigtext(role, T)) == 0)
		raise Fail+"signature does not match the exchange";
}

kdf(T, ikm: array of byte, what: string): array of byte
{
	return crypt->hkdfsha256(T, ikm, array of byte (Label + " " + what), 32);
}

allzero(a: array of byte): int
{
	x := 0;
	for(i := 0; i < len a; i++)
		x |= int a[i];
	return x == 0;
}

eq(a, b: array of byte): int
{
	if(len a != len b)
		return 0;
	x := 0;
	for(i := 0; i < len a; i++)
		x |= int a[i] ^ int b[i];
	return x == 0;
}

# getmsg with exceptions that survive the trip through a caller
gmsg(io: ref IO): array of byte
{
	while((buf := io.read()) == nil || len buf < 5)
		io.toosmall(5);
	if(len buf != 5)
		raise Fail+"bad message count";
	h := string buf;
	iserr := h[0] == '!';
	m := 0;
	for(i := iserr; i < 4; i++){
		if(h[i] < '0' || h[i] > '9')
			raise Fail+"bad message count";
		m = m*10 + h[i] - '0';
	}
	if(m == 0)
		buf = array[0] of byte;
	else{
		while((buf = io.read()) == nil || len buf < m)
			io.toosmall(m);
		if(len buf != m)
			raise Fail+"bad message length";
	}
	if(iserr)
		raise Remote+string buf;
	return buf;
}

remote(s: string): string
{
	# account for strange earlier interface
	if(len s < 6 || s[0: 6] != "remote")
		return "remote: "+s;
	return s;
}

# TO DO: exchange attr/value pairs, covered by hmac (use part of secret up to hmac block size of 64 bytes)
# the old scheme can be distinguished either by a prefix "attrs " or simply because the string contains "=",
# and the server side can then reply.  the hmac is to prevent tampering.
negotiatecrypto(io: ref IO, key: ref Key, ai: ref Authinfo, attrs: list of ref Sexp): string
{
	role := authio->lookattrval(key.attrs, "role");
	alg: string;
	{
		if(role == "client"){
			alg = authio->lookattrval(key.attrs, ":alg");
			if(alg == nil)
				alg = authio->lookattrval(key.attrs, "alg");	# old way
			if(alg == nil)
				alg = "md5/rc4_256";
			sendmsg(io, array of byte alg);
		}else if(role == "server"){
			alg = string getmsg(io);
			if(!algcompatible(alg, sys->tokenize(authio->lookattrval(key.attrs, "algs"), " ").t1))
				raise Error0("unsupported client algorithm");
		}
	}exception e{
	Error0 or
	Error1 =>
		return e;
	}

	if(alg != nil)
		attrs = sl(ss("alg") :: ss(alg) :: nil) :: attrs;
	ai.secret = sl(attrs).pack();
	if(role == "server")
		ai.cap = capability(nil, ai.suid);

	io.done(ai);
	return nil;
}

capability(ufrom, uto: string): string
{
	capfd := sys->open("#¤/caphash", Sys->OWRITE);
	if(capfd == nil)
		return nil;
	key := IPint.random(0, 160).iptob64();
	if(key == nil)
		return nil;

	users := uto;
	if(ufrom != nil)
		users = ufrom+"@"+uto;
	digest := array[Keyring->SHA1dlen] of byte;
	ausers := array of byte users;
	keyring->hmac_sha1(ausers, len ausers, array of byte key, digest, nil);
	if(sys->write(capfd, digest, len digest) < 0)
		return nil;
	return users+"@"+key;
}

algcompatible(nil: string, nil: list of string): int
{
	return 1;	# XXX
}

principal(pk: ref Keyring->PK): ref Sexp
{
	if(keyreps == nil)
		return sb(array of byte keyring->pktostr(pk));
	return spki->(Keyrep.pk(pk).mkkey()).sexp();
}

ipint(i: int): ref IPint
{
	return IPint.inttoip(i);
}

rand(p, q: ref IPint, nil: int): ref IPint
{
	if(p.cmp(q) > 0)
		(p, q) = (q, p);
	diff := q.sub(p);
	q = nil;
	if(diff.cmp(ipint(2)) < 0){
		sys->print("rand range must be at least 2");
		return IPint.inttoip(0);
	}
	l := diff.bits();
	T := ipint(1).shl(l);
	l = ((l + 7) / 8) * 8;
	slop := T.div(diff).t1;
	r: ref IPint;
	do{
		r = IPint.random(0, l);
	}while(r.cmp(slop) < 0);
	r = r.div(diff).t1.add(p);
	return r;
}

now(): int
{
	return daytime->now();
}

Hashfn: type ref fn(a: array of byte, alen: int, digest: array of byte, state: ref DigestState): ref DigestState;

hashalg(ha: string): Hashfn
{
	case ha {
	"sha" or
	"sha1" =>
		return keyring->sha1;
	"md4" =>
		return keyring->md4;
	"md5" =>
		return keyring->md5;
	"sha256" =>
		return keyring->sha256;
	"sha512" =>
		return keyring->sha512;
	}
	return nil;
}

sign(sk: ref SK, ha: string, exp: int, buf: array of byte): ref Certificate
{
	state := hashalg(ha)(buf, len buf, nil, nil);
	return keyring->sign(sk, exp, state, ha);
}

verify(pk: ref PK, cert: ref Certificate, buf: array of byte): int
{
	state := hashalg(cert.ha)(buf, len buf, nil, nil);
	return keyring->verify(pk, cert, state);
}

getmsg(io: ref IO): array of byte raises (Error0, Error1)
{
	while((buf := io.read()) == nil || (n := len buf) < 5)
		io.toosmall(5);
	if(len buf != 5)
		raise Error0("io error: (impossible?) msg length " + string n);
	h := string buf;
	if(h[0] == '!')
		m := int h[1:];
	else
		m = int h;
	while((buf = io.read()) == nil || (n = len buf) < m)
		io.toosmall(m);
	if(len buf != m)
		raise Error0("io error: (impossible?) msg length " + string m);
	if(h[0] == '!'){
		if(0)
			sys->print("got remote error: %q, len %d\n", string buf, len string buf);
		raise Error1(string buf);
	}
	return buf;
}

sendmsg(io: ref IO, buf: array of byte)
{
	h := sys->aprint("%4.4d\n", len buf);
	io.write(h, len h);
	io.write(buf, len buf);
}

senderr(io: ref IO, e: string)
{
	buf := array of byte e;
	h := sys->aprint("!%3.3d\n", len buf);
	io.write(h, len h);
	io.write(buf, len buf);
}

# both the s-expression and k=v form are interim, until all
# the factotum implementations can manage public keys
# the s-expression form was the original one used by Inferno factotum
# the form in which Authinfo components are separate attributes is the
# one now used by Plan 9 and Plan 9 Ports factotum implementations
keytoauthinfo(key:ref Key): (ref Keyring->Authinfo, string)
{
	if((s := authio->lookattrval(key.secrets, "!authinfo")) != nil)
		return strtoauthinfo(s);
	# TO DO: could look up authinfo by hash
	ai := ref Keyring->Authinfo;
	if((s = kv(key.secrets, "!sk")) == nil || (ai.mysk = keyring->strtosk(s)) == nil)
		return (nil, "bad secret key");
	if((s = kv(key.attrs, "pk")) == nil || (ai.mypk = keyring->strtopk(s)) == nil)
		return (nil, "bad public key");
	if((s = kv(key.attrs, "cert")) == nil || (ai.cert = keyring->strtocert(s)) == nil)
		return (nil, "bad certificate");
	if((s = kv(key.attrs, "spk")) == nil || (ai.spk = keyring->strtopk(s)) == nil)
		return (nil, "bad signer public key");
	if((s = kv(key.attrs, "dh-alpha")) == nil || (ai.alpha = IPint.strtoip(s, 16)) == nil)
		return (nil, "bad value for alpha");
	if((s = kv(key.attrs, "dh-p")) == nil || (ai.p = IPint.strtoip(s, 16)) == nil)
		return (nil, "bad value for p");
	return (ai, nil);
}

kv(a: list of ref Attr, name: string): string
{
	return rnl(authio->lookattrval(a, name));
}

rnl(s: string): string
{
	for(i := 0; i < len s; i++)
		if(s[i] == '^')
			s[i] = '\n';
	return s;
}

# s-expression form
strtoauthinfo(s: string): (ref Keyring->Authinfo, string)
{
	(se, err, nil) := Sexp.parse(s);
	if(se == nil)
		return (nil, err);
	els := se.els();
	if(len els != 5)
		return (nil, "bad authinfo contents");
	ai := ref Keyring->Authinfo;
	if((ai.spk = keyring->strtopk((hd els).astext())) == nil)
		return (nil, "bad signer public key");
	els = tl els;
	if((ai.cert = keyring->strtocert((hd els).astext())) == nil)
		return (nil, "bad certificate");
	els = tl els;
	if((ai.mysk = keyring->strtosk((hd els).astext())) == nil)
		return (nil, "bad secret/public key");
	if((ai.mypk = keyring->sktopk(ai.mysk)) == nil)
		return (nil, "cannot make pk from sk");
	els = tl els;
	if((ai.alpha = IPint.bytestoip((hd els).asdata())) == nil)
		return (nil, "bad value for alpha");
	els = tl els;
	if((ai.p = IPint.bytestoip((hd els).asdata())) == nil)
		return (nil, "bad value for p");
	return (ai, nil);
}
	
authinfotostr(ai: ref Keyring->Authinfo): string
{
	return (ref Sexp.List(
		ss(keyring->pktostr(ai.spk)) ::
		ss(keyring->certtostr(ai.cert)) ::
		ss(keyring->sktostr(ai.mysk)) ::
		sb(ai.alpha.iptobytes()) ::
		sb(ai.p.iptobytes()) ::
		nil
	)).b64text();
}

ss(s: string): ref Sexp.String
{
	return ref Sexp.String(s, nil);
}

sb(d: array of byte): ref Sexp.Binary
{
	return ref Sexp.Binary(d, nil);
}

sl(l: list of ref Sexp): ref Sexp
{
	return ref Sexp.List(l);
}

keycheck(nil: ref Authio->Key): string
{
	return nil;
}
