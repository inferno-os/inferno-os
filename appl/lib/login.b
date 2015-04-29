# Inferno Encrypt Key Exchange Protocol
#
# Copyright © 1995-1999 Lucent Techologies Inc.  All rights reserved.
#
# This code uses methods that are subject to one or more patents
# held by Lucent Technologies Inc.  Its use outside Inferno
# requires a separate licence from Lucent.
#
implement Login;

include "sys.m";
	sys: Sys;

include "keyring.m";
	kr: Keyring;
	IPint: import kr;

include "security.m";

include "dial.m";

include "string.m";

# see login(6)
login(id, password, dest: string): (string, ref Keyring->Authinfo)
{
	sys = load Sys Sys->PATH;
	kr = load Keyring Keyring->PATH;
	if(kr == nil)
		return nomod(Keyring->PATH);

	ssl := load SSL SSL->PATH;
	if(ssl == nil)
		return nomod(SSL->PATH);

	rand := load Random Random->PATH;
	if(rand == nil)
		return nomod(Random->PATH);

	dial := load Dial Dial->PATH;
	if(dial == nil)
		return nomod(Dial->PATH);

	if(dest == nil)
		dest = "$SIGNER";
	dest = dial->netmkaddr(dest, "net", "inflogin");
	lc := dial->dial(dest, nil);
	if(lc == nil)
		return (sys->sprint("can't contact login service: %s: %r", dest), nil);

	# push ssl, leave in clear mode for now
	(err, c) := ssl->connect(lc.dfd);
	if(c == nil)
		return ("can't push ssl: " + err, nil);
	lc.dfd = nil;
	lc.cfd = nil;

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
	ivec := rand->randombuf(rand->ReallyRandom, 8);
	if(kr->putbytearray(c.dfd, ivec, len ivec) < 0)
		return (sys->sprint("can't send initialization vector: %r"), nil);

	# start encrypting
	pwbuf := array of byte password;
	digest := array[Keyring->SHA1dlen] of byte;
	kr->sha1(pwbuf, len pwbuf, digest, nil);
	pwbuf = array[8] of byte;
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

	# CA->user	alpha
	(s, err) = kr->getstring(c.dfd);
	if(err != nil){
		if(err == "failure")
			return ("name or secret incorrect (alpha)", nil);
		return ("remote: " + err, nil);
	}
	info := ref Keyring->Authinfo;
	info.alpha = IPint.b64toip(s);

	# CA->user	p
	(s, err) = kr->getstring(c.dfd);
	if(err != nil){
		if(err == "failure")
			return ("name or secret incorrect (p)", nil);
		return ("remote: " + err, nil);
	}
	info.p = IPint.b64toip(s);

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

	# generate a key pair
	info.mysk = kr->genSKfromPK(info.spk, id);
	info.mypk = kr->sktopk(info.mysk);

	# user->CA	user's public key, SHA(user's public key + secret)
	if(kr->putstring(c.dfd, kr->pktostr(info.mypk)) < 0)
		return (sys->sprint("can't send your public: %r"), nil);

	# CA->user	user's public key certificate
	(s, err) = kr->getstring(c.dfd);
	if(err != nil)
		return ("can't get certificate: " + err, nil);

	info.cert = kr->strtocert(s);
	return(nil, info);
}

nomod(mod: string): (string, ref Keyring->Authinfo)
{
	return (sys->sprint("can't load module %s: %r", mod), nil);
}
