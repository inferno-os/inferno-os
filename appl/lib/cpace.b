implement Cpace;

#
# CPace over X25519 with SHA-512, the initiator-responder form of
# draft-irtf-cfrg-cpace (sections 5, 6 and 7.2; test vectors in B.1).
#

include "sys.m";
	sys: Sys;
include "ipints.m";
include "crypt.m";
	crypt: Crypt;
include "cpace.m";

DSI: con "CPace255";
Hblock: con 128;	# SHA-512's input block

init(): string
{
	sys = load Sys Sys->PATH;
	crypt = load Crypt Crypt->PATH;
	if(crypt == nil)
		return sys->sprint("can't load %s: %r", Crypt->PATH);
	return nil;
}

# the length as LEB128, then the data
prepend(a: array of byte): array of byte
{
	n := len a;
	h := array[5] of byte;
	i := 0;
	for(;;){
		b := n & 16r7f;
		n >>= 7;
		if(n == 0){
			h[i++] = byte b;
			break;
		}
		h[i++] = byte (b | 16r80);
	}
	r := array[i + len a] of byte;
	r[0:] = h[0:i];
	r[i:] = a;
	return r;
}

lvcat(parts: list of array of byte): array of byte
{
	n := 0;
	l: list of array of byte;
	for(; parts != nil; parts = tl parts){
		p := prepend(hd parts);
		n += len p;
		l = p :: l;
	}
	r := array[n] of byte;
	for(; l != nil; l = tl l){
		n -= len hd l;
		r[n:] = hd l;
	}
	return r;
}

sha512(a: array of byte): array of byte
{
	d := array[Crypt->SHA512dlen] of byte;
	crypt->sha512(a, len a, d, nil);
	return d;
}

generator(prs, ci, sid: array of byte): array of byte
{
	# zeros fill the hash's first block after the secret
	nz := Hblock - 1 - len prepend(prs) - len prepend(array of byte DSI);
	if(nz < 0)
		nz = 0;
	zpad := array[nz] of {* => byte 0};
	s := lvcat(array of byte DSI :: prs :: zpad :: ci :: sid :: nil);
	return crypt->x25519map(sha512(s)[0:32]);
}

share(g, y: array of byte): array of byte
{
	if(len g != Sharelen || len y != Sharelen)
		return nil;
	return crypt->x25519(y, g);
}

isk(sid, y, peer: array of byte, ya, ada, yb, adb: array of byte): array of byte
{
	if(len y != Sharelen || len peer != Sharelen)
		return nil;
	k := crypt->x25519(y, peer);
	if(k == nil)
		return nil;
	# a share of small order gives the neutral element: refuse it
	x := 0;
	for(i := 0; i < len k; i++)
		x |= int k[i];
	if(x == 0)
		return nil;
	a := lvcat(array of byte (DSI + "_ISK") :: sid :: k :: nil);
	t := lvcat(ya :: ada :: yb :: adb :: nil);
	m := array[len a + len t] of byte;
	m[0:] = a;
	m[len a:] = t;
	return sha512(m);
}
