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

	if(dest == nil)
		dest = "$SIGNER";
	for(j:=0; j<len dest && dest[j] != '!'; j++)
		break;
	if(j >= len dest)
		dest = "net!"+dest+"!inflogin";	# BUG: must do better

	(ok, lc) := sys->dial(dest, nil);
	if(ok < 0)
		return (sys->sprint("can't contact login service: %r"), nil);

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

	# user->CA	ivec (32 bytes: 20 for key derivation salt + 12 for AEAD nonce)
	ivec := rand->randombuf(rand->ReallyRandom, 32);
	if(kr->putbytearray(c.dfd, ivec, len ivec) < 0)
		return (sys->sprint("can't send initialization vector: %r"), nil);

	# Derive 32-byte ChaCha20-Poly1305 key from password + IV
	# HKDF-like: key = SHA-256(SHA-256(password) || ivec[0:20])
	pwbuf := array of byte password;
	pwdigest := array[Keyring->SHA256dlen] of byte;
	kr->sha256(pwbuf, len pwbuf, pwdigest, nil);
	keymaterial := array[Keyring->SHA256dlen + 20] of byte;
	keymaterial[0:] = pwdigest;
	keymaterial[Keyring->SHA256dlen:] = ivec[0:20];
	aeadkey := array[Keyring->SHA256dlen] of byte;
	kr->sha256(keymaterial, len keymaterial, aeadkey, nil);
	nonce := ivec[20:32];

	# CA -> user	AEAD-encrypted alpha**r0 mod p
	# Receive ciphertext + 16-byte Poly1305 tag
	ciphertext: array of byte;
	authtag: array of byte;
	(ciphertext, err) = kr->getbytearray(c.dfd);
	if(err != nil){
		if(err == "failure")
			return ("name or secret incorrect (alpha**r0 mod p)", nil);
		return ("remote:" + err, nil);
	}
	(authtag, err) = kr->getbytearray(c.dfd);
	if(err != nil)
		return ("remote:" + err, nil);

	# Decrypt with ChaCha20-Poly1305 (AEAD - authenticates and decrypts)
	plaintext := kr->ccpolydecrypt(ciphertext, nil, authtag, aeadkey, nonce);
	if(plaintext == nil)
		return ("name or secret incorrect (AEAD decryption failed)", nil);
	alphar0 := IPint.b64toip(string plaintext);

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
	if(sys->fprint(c.cfd, "alg sha256") < 0)
		return (sys->sprint("can't push alg sha256: %r"), nil);

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
