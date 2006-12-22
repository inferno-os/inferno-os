implement Keyset;

include "sys.m";
	sys: Sys;
include "keyring.m";
	keyring: Keyring;
include "daytime.m";
	daytime: Daytime;
include "readdir.m";

include "keyset.m";

PKHASHLEN: con Keyring->SHA1dlen * 2;

init(): string
{
	sys = load Sys Sys->PATH;
	keyring = load Keyring Keyring->PATH;
	if(keyring == nil)
		return cant(Keyring->PATH);
	daytime = load Daytime Daytime->PATH;
	if(daytime == nil)
		return cant(Daytime->PATH);
	return nil;
}

cant(s: string): string
{
	return sys->sprint("can't load %s: %r", s);
}

pkhash(pk: string): string
{
	d := array of byte pk;
	digest := array[Keyring->SHA1dlen] of byte;
	keyring->sha1(d, len d, digest, nil);
	s := "";
	for(i := 0; i < len digest; i++)
		s += sys->sprint("%2.2ux", int digest[i]);
	return s;
}

keysforsigner(signername: string, spkhash: string, user: string, dir: string): (list of (string, string, string), string)
{
	if(spkhash != nil && len spkhash != PKHASHLEN)
		return (nil, "invalid hash string");
	if(dir == nil){
		if(user == nil)
			user = readname("/dev/user");
		if(user == nil)
			dir = "/lib/keyring";
		else
			dir = "/usr/" + user + "/keyring";
	}
	readdir := load Readdir Readdir->PATH;
	if(readdir == nil)
		return (nil, sys->sprint("can't load Readdir: %r"));
	now := daytime->now();
	(a, ok) := readdir->init(dir, Readdir->COMPACT|Readdir->MTIME);
	if(ok < 0)
		return (nil, sys->sprint("can't open %s: %r", dir));
	keys: list of (string, string, string);
	for(i := 0; i < len a; i++){
		if(a[i].mode & Sys->DMDIR)
			continue;
		f := dir + "/" + a[i].name;
		info := keyring->readauthinfo(f);
		if(info == nil || info.cert == nil || info.cert.exp != 0 && info.cert.exp < now)
			continue;
		if(signername != nil && info.cert.signer != signername)
			continue;
		if(spkhash != nil && pkhash(keyring->pktostr(info.spk)) != spkhash)
			continue;
		keys = (f, info.mypk.owner, info.cert.signer) :: keys;
	}
	return (keys, nil);
}

readname(f: string): string
{
	fd := sys->open(f, Sys->OREAD);
	if(fd == nil)
		return nil;
	buf := array[Sys->NAMEMAX] of byte;
	n := sys->read(fd, buf, len buf);
	if(n <= 0)
		return nil;
	return string buf[0:n];
}
