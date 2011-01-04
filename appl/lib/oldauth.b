implement Oldauth;

#
# TO DO
#	- more error checking?
#	- details of auth error handling
#

include "sys.m";
	sys: Sys;

include "ipints.m";
	ipints: IPints;
	IPint: import ipints;

include "crypt.m";
	crypt: Crypt;
	PK, SK, PKsig: import crypt;

include "msgio.m";
	msgio: Msgio;

include "oldauth.m";

init()
{
	sys = load Sys Sys->PATH;
	ipints = load IPints IPints->PATH;
	crypt = load Crypt Crypt->PATH;
	msgio = load Msgio Msgio->PATH;
	msgio->init();
}

efmt()
{
	sys->werrstr("input or format error");
}

readauthinfo(filename: string): ref Authinfo
{
	fd := sys->open(filename, Sys->OREAD);
	if(fd == nil)
		return nil;
	a := array[5] of string;
	for(i := 0; i < len a; i++){
		(s, err) := getstr(fd);
		if(err != nil){
			sys->werrstr(sys->sprint("%q: input or format error", filename));
			return nil;
		}
		a[i] = s;
	}
	info := ref Authinfo;
	(info.spk, nil) = strtopk(a[0]);
	info.cert = strtocert(a[1]);
	(info.mysk, info.owner) = strtosk(a[2]);
	if(info.spk == nil || info.cert == nil || info.mysk == nil){
		efmt();
		return nil;
	}
	info.mypk = crypt->sktopk(info.mysk);
	info.alpha = IPint.strtoip(a[3], 64);
	info.p = IPint.strtoip(a[4], 64);
	if(info.alpha == nil || info.p == nil){
		efmt();
		return nil;
	}
	return info;
}

writeauthinfo(filename: string, info: ref Authinfo): int
{
	if(info.alpha == nil || info.p == nil ||
	   info.spk == nil || info.mysk == nil || info.cert == nil){
		sys->werrstr("invalid authinfo");
		return -1;
	}
	a := array[5] of string;
	a[0] = pktostr(info.spk, info.cert.signer);	# signer's public key
	a[1] = certtostr(info.cert);	# certificate for my public key
	a[2] = sktostr(info.mysk, info.owner);	# my secret/public key
	a[3] = b64(info.alpha);	# diffie hellman base
	a[4] = b64(info.p);	# diffie hellman modulus
	fd := sys->open(filename, Sys->OWRITE|Sys->OTRUNC);
	if(fd == nil){
		fd = sys->create(filename, Sys->OWRITE, 8r600);
		if(fd == nil){
			fd = sys->open(filename, Sys->OWRITE);
			if(fd == nil)
				return -1;
		}
	}
	for(i := 0; i < len a; i++)
		if(sendstr(fd, a[i]) <= 0)
			return -1;
	return 0;
}

sendstr(fd: ref Sys->FD, s: string): int
{
	a := array of byte s;
	return msgio->sendmsg(fd, a, len a);
}

getstr(fd: ref Sys->FD): (string, string)
{
	b := msgio->getmsg(fd);
	if(b == nil)
		return (nil, sys->sprint("%r"));
	return (string b, nil);
}

certtostr(c: ref Certificate): string
{
	s := sys->sprint("%s\n%s\n%s\n%ud\n", c.sa, c.ha, c.signer, c.exp);
	pick r := c.sig {
	RSA =>
		s += b64(r.n)+"\n";
	Elgamal =>
		s += b64(r.r)+"\n"+b64(r.s)+"\n";
	DSA =>
		s += b64(r.r)+"\n"+b64(r.s)+"\n";
	* =>
		raise "unknown key type";
	}
	return s;
}

pktostr(pk: ref PK, owner: string): string
{
	pick k := pk {
	RSA =>
		s := sys->sprint("rsa\n%s\n", owner);
		s += b64(k.n)+"\n"+b64(k.ek)+"\n";
		return s;
	Elgamal =>
		s := sys->sprint("elgamal\n%s\n", owner);
		s += b64(k.p)+"\n"+b64(k.alpha)+"\n"+b64(k.key)+"\n";
		return s;
	DSA =>
		s := sys->sprint("dsa\n%s\n", owner);
		s += b64(k.p)+"\n"+b64(k.q)+"\n"+b64(k.alpha)+"\n"+b64(k.key)+"\n";
		return s;
	* =>
		raise "unknown key type";
	}
}

sktostr(sk: ref SK, owner: string): string
{
	pick k := sk {
	RSA =>
		s := sys->sprint("rsa\n%s\n", owner);
		s += b64(k.pk.n)+"\n"+b64(k.pk.ek)+"\n"+b64(k.dk)+"\n"+
			b64(k.p)+"\n"+b64(k.q)+"\n"+
			b64(k.kp)+"\n"+b64(k.kq)+"\n"+
			k.c2.iptob64()+"\n";
		return s;
	Elgamal =>
		pk := k.pk;
		s := sys->sprint("elgamal\n%s\n", owner);
		s += b64(pk.p)+"\n"+b64(pk.alpha)+"\n"+b64(pk.key)+"\n"+b64(k.secret)+"\n";
		return s;
	DSA =>
		pk := k.pk;
		s := sys->sprint("dsa\n%s\n", owner);
		s += b64(pk.p)+"\n"+b64(pk.q)+"\n"+b64(pk.alpha)+"\n"+b64(k.secret)+"\n";
		return s;
	* =>
		raise "unknown key type";
	}
}

fields(s: string): array of string
{
	(nf, flds) := sys->tokenize(s, "\n^");
	a := array[nf] of string;
	for(i := 0; i < len a; i++){
		a[i] = hd flds;
		flds = tl flds;
	}
	return a;
}

bigs(a: array of string): array of ref IPint
{
	b := array[len a] of ref IPint;
	for(i := 0; i < len b; i++){
		b[i] = IPint.strtoip(a[i], 64);
		if(b[i] == nil)
			return nil;
	}
	return b;
}

need[T](a: array of T, min: int): int
{
	if(len a < min){
		efmt();
		return 1;
	}
	return 0;
}

strtocert(s: string): ref Certificate
{
	f := fields(s);
	if(need(f, 4))
		return nil;
	sa := f[0];
	ha := f[1];
	signer := f[2];
	exp := int big f[3];	# unsigned
	b := bigs(f[4:]);
	case f[0] {
	"rsa" =>
		if(need(b, 1))
			return nil;
		return ref Certificate(sa, ha, signer, exp, ref PKsig.RSA(b[0]));
	"elgamal" =>
		if(need(b, 2))
			return nil;
		return ref Certificate(sa, ha, signer, exp, ref PKsig.Elgamal(b[0], b[1]));
	"dsa" =>
		if(need(b, 2))
			return nil;
		return ref Certificate(sa, ha, signer, exp, ref PKsig.DSA(b[0], b[1]));
	* =>
		sys->werrstr("unknown algorithm: "+f[0]);
		return nil;
	}
}

strtopk(s: string): (ref PK, string)
{
	f := fields(s);
	if(need(f, 3))
		return (nil, "format error");
	sa := f[0];
	owner := f[1];
	b := bigs(f[2:]);
	case sa {
	"rsa" =>
		if(need(b, 2))
			return (nil, "format error");
		return (ref PK.RSA(b[0], b[1]), owner);
	"elgamal" =>
		if(need(b, 3))
			return (nil, "format error");
		return (ref PK.Elgamal(b[0], b[1], b[2]), owner);
	"dsa" =>
		if(need(b, 4))
			return (nil, "format error");
		return (ref PK.DSA(b[0], b[1], b[2], b[3]), owner);
	* =>
		return (nil, "unknown algorithm: "+f[0]);
	}
}

strtosk(s: string): (ref SK, string)
{
	f := fields(s);
	if(need(f, 3))
		return (nil, "format error");
	sa := f[0];
	owner := f[1];
	b := bigs(f[2:]);
	case sa {
	"rsa" =>
		if(need(b, 8))
			return (nil, "format error");
		return (ref SK.RSA(ref PK.RSA(b[0], b[1]), b[2], b[3], b[4], b[5], b[6], b[7]), owner);
	"elgamal" =>
		if(need(b, 4))
			return (nil, "format error");
		return (ref SK.Elgamal(ref PK.Elgamal(b[0], b[1], b[2]), b[3]), owner);
	"dsa" =>
		if(need(b, 5))
			return (nil, "format error");
		return (ref SK.DSA(ref PK.DSA(b[0], b[1], b[2], b[3]), b[4]), owner);
	* =>
		return (nil, "unknown algorithm: "+f[0]);
	}
}

skalg(sk: ref SK): string
{
	if(sk == nil)
		return "nil";
	case tagof sk {
	tagof SK.RSA =>	return "rsa";
	tagof SK.Elgamal =>	return "elgamal";
	tagof SK.DSA =>	return "dsa";
	* =>	return "gok";
	}
}

sign(sk: ref SK, signer: string, exp: int, state: ref Crypt->DigestState, ha: string): ref Certificate
{
	# add signer name and expiration time to hash
	if(state == nil)
		return nil;
	a := sys->aprint("%s %d", signer, exp);
	digest := hash(ha, a, state);
	if(digest == nil)
		return nil;
	b := IPint.bebytestoip(digest);
	return ref Certificate(skalg(sk), ha, signer, exp, crypt->sign(sk, b));
}

verify(pk: ref PK, cert: ref Certificate, state: ref Crypt->DigestState): int
{
	if(state == nil)
		return 0;
	a := sys->aprint("%s %d", cert.signer, cert.exp);
	digest := hash(cert.ha, a, state);
	if(digest == nil)
		return 0;
	b := IPint.bebytestoip(digest);
	return crypt->verify(pk, cert.sig, b);
}

hash(ha: string, a: array of byte, state: ref Crypt->DigestState): array of byte
{
	digest: array of byte;
	case ha {
	"sha" or "sha1" =>
		digest = array[Crypt->SHA1dlen] of byte;
		crypt->sha1(a, len a, digest, state);
	"md5" =>
		digest = array[Crypt->MD5dlen] of byte;
		crypt->md5(a, len a, digest, state);
	* =>
		# don't bother with md4
		sys->werrstr("unimplemented algorithm: "+ha);
		return nil;
	}
	return digest;
}

b64(ip: ref IPint): string
{
	return ip.iptob64z();
}
