implement Secstore;

#
# interact with the Plan 9 secstore
#

include "sys.m";
	sys: Sys;

include "dial.m";
	dialler: Dial;

include "keyring.m";
	kr: Keyring;
	DigestState, IPint: import kr;
	AESbsize, AESstate: import kr;

include "security.m";
	ssl: SSL;

include "encoding.m";
	base64: Encoding;

include "secstore.m";


init()
{
	sys = load Sys Sys->PATH;
	kr = load Keyring Keyring->PATH;
	ssl = load SSL SSL->PATH;
	base64 = load Encoding Encoding->BASE64PATH;
	dialler = load Dial Dial->PATH;
	initPAKparams();
}

privacy(): int
{
	fd := sys->open("#p/"+string sys->pctl(0, nil)+"/ctl", Sys->OWRITE);
	if(fd == nil || sys->fprint(fd, "private") < 0)
		return 0;
	return 1;
}

connect(addr: string, user: string, pwhash: array of byte): (ref Dial->Connection, string, string)
{
	conn := dial(addr);
	if(conn == nil){
		sys->werrstr(sys->sprint("can't dial %s: %r", addr));
		return (nil, nil, sys->sprint("%r"));
	}
	(sname, diag) := auth(conn, user, pwhash);
	if(sname == nil){
		sys->werrstr(sys->sprint("can't authenticate: %s", diag));
		return (nil, nil, sys->sprint("%r"));
	}
	return (conn, sname, diag);
}

dial(netaddr: string): ref Dial->Connection
{
	if(netaddr == nil)
		netaddr = "net!$auth!secstore";
	conn := dialler->dial(netaddr, nil);
	if(conn == nil)
		return nil;
	(err, sslconn) := ssl->connect(conn.dfd);
	if(err != nil)
		sys->werrstr(err);
	return sslconn;
}

auth(conn: ref Dial->Connection, user: string, pwhash: array of byte): (string, string)
{
	sname := PAKclient(conn, user, pwhash);
	if(sname == nil)
		return (nil, sys->sprint("%r"));
	s := readstr(conn.dfd);
	if(s == "STA")
		return (sname, "need pin");
	if(s != "OK"){
		if(s != nil)
			sys->werrstr(s);
		return (nil, sys->sprint("%r"));
	}
	return (sname, nil);
}

cansecstore(netaddr: string, user: string): int
{
	conn := dial(netaddr);
	if(conn == nil)
		return 0;
	if(sys->fprint(conn.dfd, "secstore\tPAK\nC=%s\nm=0\n", user) < 0)
		return 0;
	buf := array[128] of byte;
	n := sys->read(conn.dfd, buf, len buf);
	if(n <= 0)
		return 0;
	return string buf[0:n] == "!account exists";
}

sendpin(conn: ref Dial->Connection, pin: string): int
{
	if(sys->fprint(conn.dfd, "STA%s", pin) < 0)
		return -1;
	s := readstr(conn.dfd);
	if(s != "OK"){
		if(s != nil)
			sys->werrstr(s);
		return -1;
	}
	return 0;
}

files(conn: ref Dial->Connection): list of (string, int, string, string, array of byte)
{
	file := getfile(conn, ".", 0);
	if(file == nil)
		return nil;
	rl: list of (string, int, string, string, array of byte);
	for(linelist := lines(file); linelist != nil; linelist = tl linelist){
		s := string hd linelist;
		# factotum\t2552 Dec  9 13:04:49 GMT 2005 n9wSk45SPDxgljOIflGQoXjOkjs=
		for(i := 0; i < len s && s[i] != '\t' && s[i] != ' '; i++){}	# can be trailing spaces
		name := s[0:i];
		for(; i < len s && (s[i] == ' ' || s[i] == '\t'); i++){}
		for(j := i; j  < len s && s[j] != ' '; j++){}
		size := int s[i+1:j];
		for(i = j; i < len s && s[i] == ' '; i++){}
		date := s[i:i+24];
		i += 24+1;
		for(j = i; j < len s && s[j] != '\n'; j++){}
		sha1 := s[i:j];
		rl = (name, int size, date, sha1, base64->dec(sha1)) :: rl;
	}
	l: list of (string, int, string, string, array of byte);
	for(; rl != nil; rl = tl rl)
		l = hd rl :: l;
	return l;
}

getfile(conn: ref Dial->Connection, name: string, maxsize: int): array of byte
{
	fd := conn.dfd;
	if(maxsize <= 0)
		maxsize = Maxfilesize;
	if(sys->fprint(fd, "GET %s\n", name) < 0 ||
	   (s := readstr(fd)) == nil){
		sys->werrstr(sys->sprint("can't get %q: %r", name));
		return nil;
	}
	nb := int s;
	if(nb == -1){
		sys->werrstr(sys->sprint("remote file %q does not exist", name));
		return nil;
	}
	if(nb < 0 || nb > maxsize){
		sys->werrstr(sys->sprint("implausible file size %d for %q", nb, name));
		return nil;
	}
	file := array[nb] of byte;
	for(nr := 0; nr < nb;){
		n :=  sys->read(fd, file[nr:], nb-nr);
		if(n < 0){
			sys->werrstr(sys->sprint("error reading %q: %r", name));
			return nil;
		}
		if(n == 0){
			sys->werrstr(sys->sprint("empty file chunk reading %q at offset %d", name, nr));
			return nil;
		}
		nr += n;
	}
	return file;
}

remove(conn: ref Dial->Connection, name: string): int
{
	if(sys->fprint(conn.dfd, "RM %s\n", name) < 0)
		return -1;

	return 0;
}

bye(conn: ref Dial->Connection)
{
	if(conn != nil){
		if(conn.dfd != nil)
			sys->fprint(conn.dfd, "BYE");
		conn.dfd = nil;
		conn.cfd = nil;
	}
}

mkseckey(s: string): array of byte
{
	key := array of byte s;
	skey := array[Keyring->SHA1dlen] of byte;
	kr->sha1(key, len key, skey, nil);
	erasekey(key);
	return skey;
}

Checkpat: con "XXXXXXXXXXXXXXXX";	# it's what Plan 9's aescbc uses
Checklen: con len Checkpat;

mkfilekey(s: string): array of byte
{
	key := array of byte s;
	skey := array[Keyring->SHA1dlen] of byte;
	sha := kr->sha1(array of byte "aescbc file", 11, nil, nil);
	kr->sha1(key, len key, skey, sha);
	erasekey(key);
	erasekey(skey[AESbsize:]);
	return skey[0:AESbsize];
}

decrypt(file: array of byte, key: array of byte): array of byte
{
	length := len file;
	if(length == 0)
		return file;
	if(length < AESbsize+Checklen)
		return nil;
	state := kr->aessetup(key, file[0:AESbsize]);
	if(state == nil){
		sys->werrstr("can't set AES state");
		return nil;
	}
	kr->aescbc(state, file[AESbsize:], length-AESbsize, Keyring->Decrypt);
	if(string file[length-Checklen:] != Checkpat){
		sys->werrstr("file did not decrypt correctly");
		return nil;
	}
	return file[AESbsize: length-Checklen];
}

lines(file: array of byte): list of array of byte
{
	rl: list of array of byte;
	for(i := 0; i < len file;){
		for(j := i; j < len file; j++)
			if(file[j] == byte '\n'){
				j++;
				break;
			}
		rl = file[i:j] :: rl;
		i = j;
	}
	l: list of array of byte;
	for(; rl != nil; rl = tl rl)
		l = (hd rl) :: l;
	return l;
}

readstr(fd: ref Sys->FD): string
{
	buf := array[500] of byte;
	n := sys->read(fd, buf, len buf);
	if(n < 0)
		return nil;
	s := string buf[0:n];
	if(s[0] == '!'){
		sys->werrstr(s[1:]);
		return nil;
	}
	return s;
}

writerr(fd: ref Sys->FD, s: string)
{
	sys->fprint(fd, "!%s", s);
	sys->werrstr(s);
}

setsecret(conn: ref Dial->Connection, sigma: array of byte, direction: int): string
{
	secretin := array[Keyring->SHA1dlen] of byte;
	secretout := array[Keyring->SHA1dlen] of byte;
	if(direction != 0){
		kr->hmac_sha1(sigma, len sigma, array of byte "one", secretout, nil);
		kr->hmac_sha1(sigma, len sigma, array of byte "two", secretin, nil);
	}else{
		kr->hmac_sha1(sigma, len sigma, array of byte "two", secretout, nil);
		kr->hmac_sha1(sigma, len sigma, array of byte "one", secretin, nil);
	}
	return ssl->secret(conn, secretin, secretout);
}

erasekey(a: array of byte)
{
	for(i := 0; i < len a; i++)
		a[i] = byte 0;
}

#
# the following must only be used to talk to a Plan 9 secstore
#

VERSION: con "secstore";

PAKparams: adt {
	q:	ref IPint;
	p:	ref IPint;
	r:	ref IPint;
	g:	ref IPint;
};

pak: ref PAKparams;

# from seed EB7B6E35F7CD37B511D96C67D6688CC4DD440E1E

initPAKparams()
{
	if(pak != nil)
		return;
	lpak := ref PAKparams;
	lpak.q = IPint.strtoip("E0F0EF284E10796C5A2A511E94748BA03C795C13", 16);
	lpak.p = IPint.strtoip("C41CFBE4D4846F67A3DF7DE9921A49D3B42DC33728427AB159CEC8CBB"+
		"DB12B5F0C244F1A734AEB9840804EA3C25036AD1B61AFF3ABBC247CD4B384224567A86"+
		"3A6F020E7EE9795554BCD08ABAD7321AF27E1E92E3DB1C6E7E94FAAE590AE9C48F96D9"+
		"3D178E809401ABE8A534A1EC44359733475A36A70C7B425125062B1142D", 16);
	lpak.r = IPint.strtoip("DF310F4E54A5FEC5D86D3E14863921E834113E060F90052AD332B3241"+
		"CEF2497EFA0303D6344F7C819691A0F9C4A773815AF8EAECFB7EC1D98F039F17A32A7E"+
		"887D97251A927D093F44A55577F4D70444AEBD06B9B45695EC23962B175F266895C67D"+
		"21C4656848614D888A4", 16);
	lpak.g = IPint.strtoip("2F1C308DC46B9A44B52DF7DACCE1208CCEF72F69C743ADD4D23271734"+
		"44ED6E65E074694246E07F9FD4AE26E0FDDD9F54F813C40CB9BCD4338EA6F242AB94CD"+
		"410E676C290368A16B1A3594877437E516C53A6EEE5493A038A017E955E218E7819734"+
		"E3E2A6E0BAE08B14258F8C03CC1B30E0DDADFCF7CEDF0727684D3D255F1", 16);
	pak = lpak;	# atomic store
}

# H = (sha(ver,C,sha(passphrase)))^r mod p,
# a hash function expensive to attack by brute force.

longhash(ver: string, C: string, passwd: array of byte): ref IPint
{
	aver := array of byte ver;
	aC := array of byte C;
	Cp := array[len aver + len aC + len passwd] of byte;
	Cp[0:] = aver;
	Cp[len aver:] = aC;
	Cp[len aver+len aC:] = passwd;
	buf := array[7*Keyring->SHA1dlen] of byte;
	for(i := 0; i < 7; i++){
		key := array[] of { byte('A'+i) };
		kr->hmac_sha1(Cp, len Cp, key, buf[i*Keyring->SHA1dlen:], nil);
	}
	erasekey(Cp);
	return mod(IPint.bebytestoip(buf), pak.p).expmod(pak.r, pak.p);	# H
}

mod(a, b: ref IPint): ref IPint
{
	return a.div(b).t1;
}

shaz(s: string, digest: array of byte, state: ref DigestState): ref DigestState
{
	a := array of byte s;
	state = kr->sha1(a, len a, digest, state);
	erasekey(a);
	return state;
}

# Hi = H^-1 mod p
PAK_Hi(C: string, passhash: array of byte): (string, ref IPint, ref IPint)
{
	H := longhash(VERSION, C, passhash);
	Hi := H.invert(pak.p);
	return (Hi.iptostr(64), H, Hi);
}

# another, faster, hash function for each party to
# confirm that the other has the right secrets.

shorthash(mess: string, C: string, S: string, m: string, mu: string, sigma: string, Hi: string): array of byte
{
	state := shaz(mess, nil, nil);
	state = shaz(C, nil, state);
	state = shaz(S, nil, state);
	state = shaz(m, nil, state);
	state = shaz(mu, nil, state);
	state = shaz(sigma, nil, state);
	state = shaz(Hi, nil, state);
	state = shaz(mess, nil, state);
	state = shaz(C, nil, state);
	state = shaz(S, nil, state);
	state = shaz(m, nil, state);
	state = shaz(mu, nil, state);
	state = shaz(sigma, nil, state);
	digest := array[Keyring->SHA1dlen] of byte;
	shaz(Hi, digest, state);
	return digest;
}

#
# On input, conn provides an open channel to the server;
#	C is the name this client calls itself;
#	pass is the user's passphrase
# On output, session secret has been set in conn
#	(unless return code is negative, which means failure).
#
PAKclient(conn: ref Dial->Connection, C: string, pwhash: array of byte): string
{
	dfd := conn.dfd;

	(hexHi, H, nil) := PAK_Hi(C, pwhash);

	# random 1<=x<=q-1; send C, m=g**x H
	x := mod(IPint.random(240), pak.q);
	if(x.eq(IPint.inttoip(0)))
		x = IPint.inttoip(1);
	m := mod(pak.g.expmod(x, pak.p).mul(H), pak.p);
	hexm := m.iptostr(64);

	if(sys->fprint(dfd, "%s\tPAK\nC=%s\nm=%s\n", VERSION, C, hexm) < 0)
		return nil;

	# recv g**y, S, check hash1(g**xy)
	s := readstr(dfd);
	if(s == nil){
		e := sys->sprint("%r");
		writerr(dfd, "couldn't read g**y");
		sys->werrstr(e);
		return nil;
	}
	# should be: "mu=%s\nk=%s\nS=%s\n"
	(nf, flds) := sys->tokenize(s, "\n");
	if(nf != 3){
		writerr(dfd, "verifier syntax  error");
		return nil;
	}
	hexmu := ex("mu=", hd flds); flds = tl flds;
	ks := ex("k=", hd flds); flds = tl flds;
	S := ex("S=", hd flds);
	if(hexmu == nil || ks == nil || S == nil){
		writerr(dfd, "verifier syntax error");
		return nil;
	}
	mu := IPint.strtoip(hexmu, 64);
	sigma := mu.expmod(x, pak.p);
	hexsigma := sigma.iptostr(64);
	digest := shorthash("server", C, S, hexm, hexmu, hexsigma, hexHi);
	kc := base64->enc(digest);
	if(ks != kc){
		writerr(dfd, "verifier didn't match");
		return nil;
	}

	# send hash2(g**xy)
	digest = shorthash("client", C, S, hexm, hexmu, hexsigma, hexHi);
	kc = base64->enc(digest);
	if(sys->fprint(dfd, "k'=%s\n", kc) < 0)
		return nil;

	# set session key
	digest = shorthash("session", C, S, hexm, hexmu, hexsigma, hexHi);
	for(i := 0; i < len hexsigma; i++)
		hexsigma[i] = 0;

	err := setsecret(conn, digest, 0);
	if(err != nil)
		return nil;
	erasekey(digest);
	if(sys->fprint(conn.cfd, "alg sha1 rc4_128") < 0)
		return nil;
	return S;
}

ex(tag: string, s: string): string
{
	if(len s < len tag || s[0:len tag] != tag)
		return nil;
	return s[len tag:];
}
