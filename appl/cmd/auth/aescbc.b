implement Aescbc;

#
# broadly transliterated from the Plan 9 command
#

include "sys.m";
	sys: Sys;

include "draw.m";

include "bufio.m";
	bufio: Bufio;
	Iobuf: import bufio;

include "keyring.m";
	kr: Keyring;
	AESbsize, MD5dlen, SHA1dlen: import Keyring;

include "arg.m";

Aescbc: module
{
	init:	fn(nil: ref Draw->Context, nil: list of string);
};

#
# encrypted file: v2hdr, 16 byte IV, AES-CBC(key, random || file), HMAC_SHA1(md5(key), AES-CBC(random || file))
#

Checkpat: con "XXXXXXXXXXXXXXXX";
Checklen: con len Checkpat;
Bufsize: con 4096;
AESmaxkey: con 32;

V2hdr: con "AES CBC SHA1  2\n";

bin: ref Iobuf;
bout: ref Iobuf;
stderr: ref Sys->FD;

init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	kr = load Keyring Keyring->PATH;
	bufio = load Bufio Bufio->PATH;

	sys->pctl(Sys->FORKFD, nil);
	stderr = sys->fildes(2);
	arg := load Arg Arg->PATH;
	arg->init(args);
	arg->setusage("auth/aescbc -d [-k key] [-f keyfile] <file.aes >clear.txt\n  or: auth/aescbc -e [-k key] [-f keyfile] <clear.txt >file.aes");
	encrypt := -1;
	keyfile: string;
	pass: string;
	while((o := arg->opt()) != 0)
		case o {
		'd' or 'e' =>
			if(encrypt >= 0)
				arg->usage();
			encrypt = o == 'e';
		'f' =>
			keyfile = arg->earg();
		'k' =>
			pass = arg->earg();
		* =>
			arg->usage();
		}
	args = arg->argv();
	if(args != nil || encrypt < 0)
		arg->usage();
	arg = nil;

	bin = bufio->fopen(sys->fildes(0), Bufio->OREAD);
	bout = bufio->fopen(sys->fildes(1), Bufio->OWRITE);

	buf := array[Bufsize+SHA1dlen] of byte;	# Checklen <= SHA1dlen

	pwd: array of byte;
	if(keyfile != nil){
		fd := sys->open(keyfile, Sys->OREAD);
		if(fd == nil)
			error(sys->sprint("can't open %q: %r", keyfile), "keyfile");
		n := sys->readn(fd, buf, len buf);
		while(n > 0 && buf[n-1] == byte '\n')
			n--;
		if(n <= 0)
			error("no key", "no key");
		pwd = buf[0:n];
	}else{
		if(pass == nil)
			pass = readpassword("password");
		if(pass == nil)
			error("no key", "no key");
		pwd = array of byte pass;
		for(i := 0;  i < len pass; i++)
			pass[i] = 0;
	}
	key := array[AESmaxkey] of byte;
	key2 := array[SHA1dlen] of byte;
	dstate := kr->sha1(array of byte "aescbc file", 11, nil, nil);
	kr->sha1(pwd, len pwd, key2, dstate);
	for(i := 0; i < len pwd; i++)
		pwd[i] = byte 0;
	key[0:] = key2[0:MD5dlen];
	nkey := MD5dlen;
	kr->md5(key, nkey, key2, nil);	# protect key even if HMAC_SHA1 is broken
	key2 = key2[0:MD5dlen];

	if(encrypt){
		Write(array of byte V2hdr, AESbsize);
		genrandom(buf, 2*AESbsize); # CBC is semantically secure if IV is unpredictable.
		aes := kr->aessetup(key[0:nkey], buf);  # use first AESbsize bytes as IV
		kr->aescbc(aes, buf[AESbsize:], AESbsize, Keyring->Encrypt);  # use second AESbsize bytes as initial plaintext
		Write(buf, 2*AESbsize);
		dstate = kr->hmac_sha1(buf[AESbsize:], AESbsize, key2, nil, nil);
		while((n := bin.read(buf, Bufsize)) > 0){
			kr->aescbc(aes, buf, n, Keyring->Encrypt);
			Write(buf, n);
			dstate = kr->hmac_sha1(buf, n, key2, nil, dstate);
			if(n < Bufsize)
				break;
		}
		if(n < 0)
			error(sys->sprint("read error: %r"), "read error");
		kr->hmac_sha1(nil, 0, key2, buf, dstate);
		Write(buf, SHA1dlen);
	}else{	# decrypt
		Read(buf, AESbsize);
		if(string buf[0:AESbsize] == V2hdr){
			Read(buf, 2*AESbsize);	# read IV and random initial plaintext
			aes := kr->aessetup(key[0:nkey], buf);
			dstate = kr->hmac_sha1(buf[AESbsize:], AESbsize, key2, nil, nil);
			kr->aescbc(aes, buf[AESbsize:], AESbsize, Keyring->Decrypt);
			Read(buf, SHA1dlen);
			while((n := bin.read(buf[SHA1dlen:], Bufsize)) > 0){
				dstate = kr->hmac_sha1(buf, n, key2, nil, dstate);
				kr->aescbc(aes, buf, n, Keyring->Decrypt);
				Write(buf, n);
				buf[0:] = buf[n:n+SHA1dlen];	# these bytes are not yet decrypted
			}
			kr->hmac_sha1(nil, 0, key2, buf[SHA1dlen:], dstate);
			if(!eqbytes(buf, buf[SHA1dlen:], SHA1dlen))
				error("decrypted file failed to authenticate", "failed to authenticate");
		}else{	# compatibility with past mistake; assume we're decrypting secstore files
			aes := kr->aessetup(key[0:AESbsize], buf);
			Read(buf, Checklen);
			kr->aescbc(aes, buf, Checklen, Keyring->Decrypt);
			while((n := bin.read(buf[Checklen:], Bufsize)) > 0){
				kr->aescbc(aes, buf[Checklen:], n, Keyring->Decrypt);
				Write(buf, n);
				buf[0:] = buf[n:n+Checklen];
			}
			if(string buf[0:Checklen] != Checkpat)
				error("decrypted file failed to authenticate", "failed to authenticate");
		}
	}
	bout.flush();
}

error(s: string, why: string)
{
	bout.flush();
	sys->fprint(stderr, "aescbc: %s\n", s);
	raise "fail:"+why;
}

eqbytes(a: array of byte, b: array of byte, n: int): int
{
	if(len a < n || len b < n)
		return 0;
	for(i := 0; i < n; i++)
		if(a[i] != b[i])
			return 0;
	return 1;
}

Read(buf: array of byte, n: int)
{
	if(bin.read(buf, n) != n){
		sys->fprint(sys->fildes(2), "aescbc: unexpectedly short read\n");
		raise "fail:read error";
	}
}

Write(buf: array of byte, n: int)
{
	if(bout.write(buf,  n) != n){
		sys->fprint(sys->fildes(2), "aescbc: write error: %r\n");
		raise "fail:write error";
	}
}

readpassword(prompt: string): string
{
	cons := sys->open("/dev/cons", Sys->ORDWR);
	if(cons == nil)
		return nil;
	stdin := bufio->fopen(cons, Sys->OREAD);
	if(stdin == nil)
		return nil;
	cfd := sys->open("/dev/consctl", Sys->OWRITE);
	if (cfd == nil || sys->fprint(cfd, "rawon") <= 0)
		sys->fprint(stderr, "aescbc: warning: cannot hide typed password\n");
	s: string;
L:
	for(;;){
		sys->fprint(cons, "%s: ", prompt);
		s = "";
		while ((c := stdin.getc()) >= 0){
			case c {
			'\n' =>
				break L;
			'\b' or 8r177 =>
				if(len s > 0)
					s = s[0:len s - 1];
			'u' & 8r037 =>
				sys->fprint(cons, "\n");
				continue L;
			* =>
				s[len s] = c;
			}
		}
	}
	sys->fprint(cons, "\n");
	return s;
}

genrandom(b: array of byte, n: int)
{
	fd := sys->open("/dev/notquiterandom", Sys->OREAD);
	if(fd == nil){
		sys->fprint(stderr, "aescbc: can't open /dev/notquiterandom: %r\n");
		raise "fail:random";
	}
	if(sys->read(fd, b, n) != n){
		sys->fprint(stderr, "aescbc: can't read random numbers: %r\n");
		raise "fail:read random";
	}
}
