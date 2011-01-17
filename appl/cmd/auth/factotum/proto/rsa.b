implement Authproto;

# SSH RSA authentication
#
# this version is compatible with Plan 9 factotum
# Plan 9 port's factotum works differently, and eventually
# we'll support both (the role= attribute distinguishes the cases), but not today
#
# Client protocol:
#	read public key
#		if you don't like it, read another, repeat
#	write challenge
#	read response
# all numbers are hexadecimal biginits parsable with strtomp.
#

include "sys.m";
	sys: Sys;
	Rread, Rwrite: import Sys;

include "draw.m";

include "ipints.m";
	ipints: IPints;
	IPint: import ipints;
include "crypt.m";
	crypt: Crypt;
	SK, PK: import crypt;

include "../authio.m";
	authio: Authio;
	Aattr, Aval, Aquery: import Authio;
	Attr, IO, Key: import authio;
	eqbytes, memrandom: import authio;
	findattrval: import authio;


init(f: Authio): string
{
	authio = f;
	sys = load Sys Sys->PATH;
	ipints = load IPints IPints->PATH;
	crypt = load Crypt Crypt->PATH;
	return nil;
}

interaction(attrs: list of ref Attr, io: ref IO): string
{
	role := findattrval(attrs, "role");
	if(role == nil)
		return "role not specified";
	if(role != "client")
		return "only client role supported";
	sk: ref SK.RSA;
	keys: list of ref Key;
	err: string;
	for(;;){
		waitread(io);
		(keys, err) = io.findkeys(attrs, "");
		if(keys != nil)
			break;
		io.error(err);
	}
	for(; keys != nil; keys = tl keys){
		(sk, err) = keytorsa(hd keys);
		if(sk != nil){
			r := array of byte sk.pk.n.iptostr(16);
			while(!io.reply2read(r, len r))
				waitread(io);
			data := io.rdwr();
			if(data != nil){
				chal := IPint.strtoip(string data, 16);
				if(chal == nil){
					io.error("invalid challenge value");
					continue;
				}
				m := crypt->rsadecrypt(sk, chal);
				b := array of byte m.iptostr(16);
				io.write(b, len b);
				io.done(nil);
				return nil;
			}
		}
	}
	for(;;){
		io.error("no key matches "+authio->attrtext(attrs));
		waitread(io);
	}
}

waitread(io: ref IO)
{
	while(io.rdwr() != nil)
		io.error("no current key");
}

Badkey: exception(string);

kv(key: ref Key, name: string): ref IPint raises Badkey
{
	if(name[0] == '!')
		a := authio->findattrval(key.secrets, name);
	else
		a = authio->findattrval(key.attrs, name);
	if(a == nil)
		raise Badkey("missing attribute "+name);
	m := IPint.strtoip(a, 16);
	if(m == nil)
		raise Badkey("bad value for "+name);
	return m;
}

keytorsa(k: ref Key): (ref SK.RSA, string)
{
	sk := ref SK.RSA;
	sk.pk = ref PK.RSA;
	{
		sk.pk.ek = kv(k, "ek");
		sk.pk.n = kv(k, "n");
		sk.dk = kv(k, "!dk");
		sk.p = kv(k, "!p");
		sk.q = kv(k, "!q");
		sk.kp = kv(k, "!kp");
		sk.kq = kv(k, "!kq");
		sk.c2 = kv(k, "!c2");
	}exception e{
	Badkey =>
		return (nil, "rsa key "+e);
	}
	return (sk, nil);
}

keycheck(k: ref Authio->Key): string
{
	return keytorsa(k).t1;
}
