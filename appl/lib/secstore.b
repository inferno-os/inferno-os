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
	random: Random;

include "encoding.m";
	base64: Encoding;

include "secstore.m";


init()
{
	sys = load Sys Sys->PATH;
	kr = load Keyring Keyring->PATH;
	ssl = load SSL SSL->PATH;
	random = load Random Random->PATH;
	base64 = load Encoding Encoding->BASE64PATH;
	if(base64 == nil)
		raise "fail:cannot load base64";
	dialler = load Dial Dial->PATH;
	if(dialler == nil)
		raise "fail:cannot load Dial";
	initPAKparams();
}

# PAK_Hi cache — deterministic function of (user, pwhash), expensive to compute
cached_pakhi_user: string;
cached_pakhi_pwhash: array of byte;
cached_pakhi_hexHi: string;
cached_pakhi_H: ref IPint;

pwhash_eq(a, b: array of byte): int
{
	if(a == nil || b == nil)
		return 0;
	if(len a != len b)
		return 0;
	for(i := 0; i < len a; i++)
		if(a[i] != b[i])
			return 0;
	return 1;
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
	# Pre-compute PAK crypto before dialing to avoid TCP idle timeout.
	# Use cached PAK_Hi if (user, pwhash) match — avoids expensive modexp.
	hexHi: string;
	H: ref IPint;
	if(cached_pakhi_user == user && pwhash_eq(cached_pakhi_pwhash, pwhash)
	   && cached_pakhi_hexHi != nil) {
		sys->fprint(sys->fildes(2), "secstore: step 1: PAK_Hi (cached)\n");
		hexHi = cached_pakhi_hexHi;
		H = cached_pakhi_H;
	} else {
		sys->fprint(sys->fildes(2), "secstore: step 1: PAK_Hi...\n");
		(hexHi, H, nil) = PAK_Hi(user, pwhash);
		# Cache for next time
		cached_pakhi_user = user;
		cached_pakhi_pwhash = array[len pwhash] of byte;
		cached_pakhi_pwhash[0:] = pwhash;
		cached_pakhi_hexHi = hexHi;
		cached_pakhi_H = H;
	}
	sys->fprint(sys->fildes(2), "secstore: step 2: random...\n");
	x := mod(IPint.random(240, 240), pak.q);
	if(x.eq(IPint.inttoip(0)))
		x = IPint.inttoip(1);
	sys->fprint(sys->fildes(2), "secstore: step 3: g^x mod p...\n");
	gx := pak.g.expmod(x, pak.p);
	sys->fprint(sys->fildes(2), "secstore: step 4: m = gx*H mod p...\n");
	m := mod(gx.mul(H), pak.p);
	hexm := m.iptostr(64);
	sys->fprint(sys->fildes(2), "secstore: PAK pre-computed, dialing...\n");

	conn := dial(addr);
	if(conn == nil){
		sys->werrstr(sys->sprint("can't dial %s: %r", addr));
		return (nil, nil, sys->sprint("%r"));
	}
	(sname, diag) := authprecomp(conn, user, hexHi, x, hexm);
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
	if(conn == nil){
		sys->fprint(sys->fildes(2), "secstore: dial %s failed: %r\n", netaddr);
		return nil;
	}
	sys->fprint(sys->fildes(2), "secstore: dialed %s, fd=%d\n", netaddr, conn.dfd.fd);
	(err, sslconn) := ssl->connect(conn.dfd);
	if(err != nil){
		sys->fprint(sys->fildes(2), "secstore: ssl connect failed: %s\n", err);
		sys->werrstr(err);
	} else
		sys->fprint(sys->fildes(2), "secstore: ssl ok, dir=%s\n", sslconn.dir);
	return sslconn;
}

authprecomp(conn: ref Dial->Connection, user: string, hexHi: string, x: ref IPint, hexm: string): (string, string)
{
	sname := PAKclientprecomp(conn, user, hexHi, x, hexm);
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

putfile(conn: ref Dial->Connection, name: string, data: array of byte): int
{
	if(len data > Maxfilesize){
		sys->werrstr("file too long");
		return -1;
	}
	fd := conn.dfd;
	if(sys->fprint(fd, "PUT %s\n", name) < 0)
		return -1;
	if(sys->fprint(fd, "%d", len data) < 0)
		return -1;
	for(o := 0; o < len data;){
		n := len data-o;
		if(n > Maxmsg)
			n = Maxmsg;
		if(sys->write(fd, data[o:o+n], n) != n)
			return -1;
		o += n;
	}
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

encrypt(file: array of byte, key: array of byte): array of byte
{
	dat := array[AESbsize+len file+Checklen] of byte;
	iv := random->randombuf(random->NotQuiteRandom, AESbsize);
	if(len iv != AESbsize)
		return nil;
	dat[:] = iv;
	dat[len iv:] = file;
	dat[len iv+len file:] = array of byte Checkpat;
	state := kr->aessetup(key, iv);
	if(state == nil){
		sys->werrstr("can't set AES state");
		return nil;
	}
	kr->aescbc(state, dat[AESbsize:], len dat-AESbsize, Keyring->Encrypt);
	return dat;
}

# ── Modern crypto (AES-256-GCM, HMAC-SHA256 key derivation) ──

SGCM_MAGIC: con "SGCM1\n";
SGCM_NONCE_LEN: con 12;
SGCM_TAG_LEN: con 16;
SGCM_KDF_ROUNDS: con 10000;

#
# Derive a 32-byte AES-256 key from a password using iterated HMAC-SHA256.
#
mkfilekey2(s: string): array of byte
{
	pass := array of byte s;
	salt := array of byte "secstore filekey";
	key := array[Keyring->SHA256dlen] of byte;

	# First round
	kr->hmac_sha256(salt, len salt, pass, key, nil);

	# Iterate
	for(i := 1; i < SGCM_KDF_ROUNDS; i++){
		prev := array[Keyring->SHA256dlen] of byte;
		prev[0:] = key;
		kr->hmac_sha256(prev, len prev, pass, key, nil);
	}

	erasekey(pass);
	return key;
}

#
# Encrypt with AES-256-GCM.
# Output format: "SGCM1\n" + 12-byte nonce + ciphertext + 16-byte GCM tag
# AAD is the magic header for domain separation.
#
encrypt2(file: array of byte, key: array of byte): array of byte
{
	magic := array of byte SGCM_MAGIC;

	# Generate random nonce using host CSPRNG
	nonce := random->randombuf(random->ReallyRandom, SGCM_NONCE_LEN);
	if(nonce == nil || len nonce != SGCM_NONCE_LEN){
		sys->werrstr("can't generate nonce");
		return nil;
	}

	state := kr->aesgcmsetup(key, nonce);
	if(state == nil){
		sys->werrstr("can't set AES-GCM state");
		return nil;
	}
	(ciphertext, tag) := kr->aesgcmencrypt(state, file, magic);
	if(ciphertext == nil || tag == nil){
		sys->werrstr("AES-GCM encryption failed");
		return nil;
	}

	# Build output: magic + nonce + ciphertext + tag
	outlen := len magic + SGCM_NONCE_LEN + len ciphertext + len tag;
	out := array[outlen] of byte;
	off := 0;
	out[off:] = magic;
	off += len magic;
	out[off:] = nonce;
	off += SGCM_NONCE_LEN;
	out[off:] = ciphertext;
	off += len ciphertext;
	out[off:] = tag;
	return out;
}

#
# Decrypt with auto-format detection.
# If the file starts with "SGCM1\n", uses AES-256-GCM with key.
# Otherwise falls back to legacy AES-CBC with legacykey.
# legacykey may be nil if only GCM files are expected.
#
decrypt2(file: array of byte, key: array of byte, legacykey: array of byte): array of byte
{
	magic := array of byte SGCM_MAGIC;
	length := len file;

	# Check for modern format
	if(length >= len magic){
		ismodern := 1;
		for(i := 0; i < len magic; i++)
			if(file[i] != magic[i]){
				ismodern = 0;
				break;
			}
		if(ismodern){
			# Modern AES-GCM format
			off := len magic;
			if(length - off < SGCM_NONCE_LEN + SGCM_TAG_LEN){
				sys->werrstr("file too short for GCM nonce+tag");
				return nil;
			}
			nonce := file[off:off+SGCM_NONCE_LEN];
			off += SGCM_NONCE_LEN;
			ciphertext := file[off:length-SGCM_TAG_LEN];
			tag := file[length-SGCM_TAG_LEN:length];

			state := kr->aesgcmsetup(key, nonce);
			if(state == nil){
				sys->werrstr("can't set AES-GCM state");
				return nil;
			}
			plaintext := kr->aesgcmdecrypt(state, ciphertext, magic, tag);
			if(plaintext == nil){
				sys->werrstr("GCM decryption failed (wrong key?)");
				return nil;
			}
			return plaintext;
		}
	}

	# Fall back to legacy AES-CBC
	if(legacykey == nil){
		sys->werrstr("legacy format but no legacy key");
		return nil;
	}
	return decrypt(file, legacykey);
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
# PAKclient with pre-computed values — sends hello immediately after connect
# without blocking on expensive crypto while holding an open connection.
#
PAKclientprecomp(conn: ref Dial->Connection, C: string, hexHi: string, x: ref IPint, hexm: string): string
{
	dfd := conn.dfd;

	# Send hello immediately — crypto was pre-computed
	sys->fprint(sys->fildes(2), "secstore: PAKclient sending pre-computed hello\n");
	if(sys->fprint(dfd, "%s\tPAK\nC=%s\nm=%s\n", VERSION, C, hexm) < 0){
		sys->fprint(sys->fildes(2), "secstore: PAKclient hello write failed: %r\n");
		return nil;
	}
	sys->fprint(sys->fildes(2), "secstore: PAKclient hello sent, waiting for response\n");

	# recv g**y, S, check hash1(g**xy)
	s := readstr(dfd);
	if(s == nil){
		e := sys->sprint("%r");
		writerr(dfd, "couldn't read g**y");
		sys->werrstr(e);
		return nil;
	}
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
	if(sys->fprint(conn.cfd, "alg sha256 aes_128_cbc") < 0)
		return nil;
	return S;
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

	sys->fprint(sys->fildes(2), "secstore: PAK_Hi starting...\n");
	(hexHi, H, nil) := PAK_Hi(C, pwhash);
	sys->fprint(sys->fildes(2), "secstore: PAK_Hi done, computing m...\n");

	# random 1<=x<=q-1; send C, m=g**x H
	x := mod(IPint.random(240, 240), pak.q);
	if(x.eq(IPint.inttoip(0)))
		x = IPint.inttoip(1);
	m := mod(pak.g.expmod(x, pak.p).mul(H), pak.p);
	hexm := m.iptostr(64);

	sys->fprint(sys->fildes(2), "secstore: PAKclient crypto done, writing hello to fd=%d\n", dfd.fd);
	if(sys->fprint(dfd, "%s\tPAK\nC=%s\nm=%s\n", VERSION, C, hexm) < 0){
		sys->fprint(sys->fildes(2), "secstore: PAKclient hello write failed: %r\n");
		return nil;
	}
	sys->fprint(sys->fildes(2), "secstore: PAKclient hello sent, waiting for response\n");

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
	if(sys->fprint(conn.cfd, "alg sha256 aes_128_cbc") < 0)
		return nil;
	return S;
}

ex(tag: string, s: string): string
{
	if(len s < len tag || s[0:len tag] != tag)
		return nil;
	return s[len tag:];
}
