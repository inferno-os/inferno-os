implement Signer;

include "sys.m";
	sys: Sys;

include "draw.m";

include "ipints.m";
	ipints: IPints;
	IPint: import ipints;

include "crypt.m";
	crypt: Crypt;

include "oldauth.m";
	oldauth: Oldauth;

include "msgio.m";
	msgio: Msgio;

include "keyring.m";
include "security.m";
	random: Random;

Signer: module
{
	init:	fn(ctxt: ref Draw->Context, argv: list of string);
};

# size in bits of modulus for public keys
PKmodlen:		con 512;

# size in bits of modulus for diffie hellman
DHmodlen:		con 512;

stderr, stdin, stdout: ref Sys->FD;

init(nil: ref Draw->Context, nil: list of string)
{
	sys = load Sys Sys->PATH;
	random = load Random Random->PATH;
	ipints = load IPints IPints->PATH;
	crypt = load Crypt Crypt->PATH;
	oldauth = load Oldauth Oldauth->PATH;
	oldauth->init();
	msgio = load Msgio Msgio->PATH;
	msgio->init();

	stdin = sys->fildes(0);
	stdout = sys->fildes(1);
	stderr = sys->fildes(2);

	sys->pctl(Sys->FORKNS, nil);
	if(sys->chdir("/keydb") < 0){
		sys->fprint(stderr, "signer: no key database\n");
		raise "fail:no keydb";
	}

	err := sign();
	if(err != nil){
		sys->fprint(stderr, "signer: %s\n", err);
		raise "fail:error";
	}
}

sign(): string
{
	info := signerkey("signerkey");
	if(info == nil)
		return "can't read key";

	# send public part to client
	mypkbuf := array of byte oldauth->pktostr(crypt->sktopk(info.mysk), info.owner);
	msgio->sendmsg(stdout, mypkbuf, len mypkbuf);
	alphabuf := array of byte info.alpha.iptob64();
	msgio->sendmsg(stdout, alphabuf, len alphabuf);
	pbuf := array of byte info.p.iptob64();
	msgio->sendmsg(stdout, pbuf, len pbuf);

	# get client's public key
	hisPKbuf := msgio->getmsg(stdin);
	if(hisPKbuf == nil)
		return "caller hung up";
	(hisPK, hisname) := oldauth->strtopk(string hisPKbuf);
	if(hisPK == nil)
		return "illegal caller PK";

	# hash, sign, and blind
	state := crypt->sha1(hisPKbuf, len hisPKbuf, nil, nil);
	cert := oldauth->sign(info.mysk, info.owner, 0, state, "sha1");

	# sanity clause
	state = crypt->sha1(hisPKbuf, len hisPKbuf, nil, nil);
	if(oldauth->verify(info.mypk, cert, state) == 0)
		return "bad signer certificate";

	certbuf := array of byte oldauth->certtostr(cert);
	blind := random->randombuf(random->ReallyRandom, len certbuf);
	for(i := 0; i < len blind; i++)
		certbuf[i] = certbuf[i] ^ blind[i];

	# sum PKs and blinded certificate
	state = crypt->md5(mypkbuf, len mypkbuf, nil, nil);
	crypt->md5(hisPKbuf, len hisPKbuf, nil, state);
	digest := array[Keyring->MD5dlen] of byte;
	crypt->md5(certbuf, len certbuf, digest, state);

	# save sum and blinded cert in a file
	file := "signed/"+hisname;
	fd := sys->create(file, Sys->OWRITE, 8r600);
	if(fd == nil)
		return "can't create "+file+sys->sprint(": %r");
	if(msgio->sendmsg(fd, blind, len blind) < 0 ||
	   msgio->sendmsg(fd, digest, len digest) < 0){
		sys->remove(file);
		return "can't write "+file+sys->sprint(": %r");
	}

	# send blinded cert to client
	msgio->sendmsg(stdout, certbuf, len certbuf);

	return nil;
}

signerkey(filename: string): ref Oldauth->Authinfo
{
	info := oldauth->readauthinfo(filename);
	if(info != nil)
		return info;

	# generate a local key
	info = ref Oldauth->Authinfo;
	info.mysk = crypt->genSK("elgamal", PKmodlen);
	info.mypk = crypt->sktopk(info.mysk);
	info.spk = crypt->sktopk(info.mysk);
	myPKbuf := array of byte oldauth->pktostr(info.mypk, "*");
	state := crypt->sha1(myPKbuf, len myPKbuf, nil, nil);
	info.cert = oldauth->sign(info.mysk, "*", 0, state, "sha1");
	(info.alpha, info.p) = crypt->dhparams(DHmodlen);

	if(oldauth->writeauthinfo(filename, info) < 0){
		sys->fprint(stderr, "can't write signerkey file: %r\n");
		return nil;
	}

	return info;
}
