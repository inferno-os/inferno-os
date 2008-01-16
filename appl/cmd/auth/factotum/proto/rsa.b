implement Authproto;

# SSH RSA authentication.
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

include "keyring.m";
	kr: Keyring;
	IPint, RSAsk, RSApk: import kr;

include "../authio.m";
	authio: Authio;
	Aattr, Aval, Aquery: import Authio;
	Attr, IO, Key, Authinfo: import authio;
	eqbytes, memrandom: import authio;
	lookattrval: import authio;


init(f: Authio): string
{
	authio = f;
	sys = load Sys Sys->PATH;
	kr = load Keyring Keyring->PATH;
#	base16 = load Encoding Encoding->BASE16PATH;
	return nil;
}

interaction(attrs: list of ref Attr, io: ref IO): string
{
	role := lookattrval(attrs, "role");
	if(role == nil)
		return "role not specified";
	if(role != "client")
		return "only client role supported";
	sk: ref RSAsk;
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
				m := sk.decrypt(chal);
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

ipint(attrs: list of ref Attr, name: string): ref IPint raises Badkey
{
	s := lookattrval(attrs, name);
	if(s == nil)
		raise Badkey("missing attribute "+name);
	m := IPint.strtoip(s, 16);
	if(m == nil)
		raise Badkey("invalid value for "+name);
	return m;
}

keytorsa(k: ref Key): (ref RSAsk, string)
{
	sk := ref RSAsk;
	sk.pk = ref RSApk;
	{
		sk.pk.ek = ipint(k.attrs, "ek");
		sk.pk.n = ipint(k.attrs, "n");
		sk.dk = ipint(k.secrets, "!dk");
		sk.p = ipint(k.secrets, "!p");
		sk.q = ipint(k.secrets, "!q");
		sk.kp = ipint(k.secrets, "!kp");
		sk.kq = ipint(k.secrets, "!kq");
		sk.c2 = ipint(k.secrets, "!c2");
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
