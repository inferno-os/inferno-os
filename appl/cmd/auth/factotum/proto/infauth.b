implement Authproto;

include "sys.m";
	sys: Sys;
include "draw.m";
include "keyring.m";
	keyring: Keyring;
	IPint: import keyring;
	SK, PK, Certificate, DigestState: import Keyring;
include "security.m";
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
	keyreps = load Keyreps Keyreps->PATH;
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
