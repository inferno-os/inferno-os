#
#  security routines implemented in C
#
Keyring: module
{
	PATH:	con	"$Keyring";

	# infinite precision integers
	IPint: adt
	{
		x:	int;	# dummy for C compiler for runt.h

		# conversions
		iptob64:	fn(i: self ref IPint): string;
		iptob64z:	fn(i: self ref IPint): string;
		b64toip:	fn(str: string): ref IPint;
		iptobytes:	fn(i: self ref IPint): array of byte;
		iptobebytes:	fn(i: self ref IPint): array of byte;
		bytestoip:	fn(buf: array of byte): ref IPint;
		bebytestoip:	fn(mag: array of byte): ref IPint;
		inttoip:	fn(i: int): ref IPint;
		iptoint:	fn(i: self ref IPint): int;
		iptostr:	fn(i: self ref IPint, base: int): string;
		strtoip:	fn(str: string, base: int): ref IPint;

		# create a random large integer using the accelerated generator
		random:		fn(minbits, maxbits: int): ref IPint;

		# operations
		bits:		fn(i: self ref IPint): int;
		expmod:	fn(base: self ref IPint, exp, mod: ref IPint): ref IPint;
		invert:	fn(base: self ref IPint, mod: ref IPint): ref IPint;
		add:		fn(i1: self ref IPint, i2: ref IPint): ref IPint;
		sub:		fn(i1: self ref IPint, i2: ref IPint): ref IPint;
		neg:		fn(i: self ref IPint): ref IPint;
		mul:		fn(i1: self ref IPint, i2: ref IPint): ref IPint;
		div:		fn(i1: self ref IPint, i2: ref IPint): (ref IPint, ref IPint);
		mod:	fn(i1: self ref IPint, i2: ref IPint): ref IPint;
		eq:		fn(i1: self ref IPint, i2: ref IPint): int;
		cmp:		fn(i1: self ref IPint, i2: ref IPint): int;
		copy:	fn(i: self ref IPint): ref IPint;

		# shifts
		shl:	fn(i: self ref IPint, n: int): ref IPint;
		shr:	fn(i: self ref IPint, n: int): ref IPint;

		# bitwise
		and:	fn(i1: self ref IPint, i2: ref IPint): ref IPint;
		ori:	fn(i1: self ref IPint, i2: ref IPint): ref IPint;
		xor:	fn(i1: self ref IPint, i2: ref IPint): ref IPint;
		not:	fn(i1: self ref IPint): ref IPint;
	};

	# signature algorithm
	SigAlg: adt
	{
		name:	string;
		# C function pointers are hidden
	};
	
	# generic public key
	PK: adt
	{
		sa:	ref SigAlg;	# signature algorithm
		owner:	string;		# owner's name
		# key and system parameters are hidden
	};
	
	# generic secret key
	SK: adt
	{
		sa:	ref SigAlg;	# signature algorithm
		owner:	string;		# owner's name
		# key and system parameters are hidden
	};

	# generic certificate
	Certificate: adt
	{
		sa:	ref SigAlg;	# signature algorithm
		ha:	string;		# hash algorithm
		signer:	string;		# name of signer
		exp:	int;		# expiration date
		# actual signature is hidden
	};

	# state held while creating digests
	DigestState: adt
	{
		x:	int;		# dummy for C compiler for runt.h
		# all the state is hidden

		copy:	fn(d: self ref DigestState): ref DigestState;
	};

	# expanded AES key + state for chaining
	AESstate: adt
	{
		x:	int;		# dummy for C compiler for runt.h
		# all the state is hidden
	};

	# expanded DES key + state for chaining
	DESstate: adt
	{
		x:	int;		# dummy for C compiler for runt.h
		# all the state is hidden
	};

	# expanded IDEA key + state for chaining
	IDEAstate: adt
	{
		x:	int;		# dummy for C compiler for runt.h
		# all the state is hidden
	};

	# expanded RC4 key + encryption state
	RC4state: adt
	{
		x:	int;		# dummy for C compiler for runt.h
		# all the state is hidden
	};

	# expanded Blowfish key + state for chaining
	BFstate: adt
	{
		x:	int;		# dummy for C compiler for runt.h
		# all the state is hidden
	};

	# authentication info
	Authinfo: adt
	{
		mysk:	ref SK;			# my private key
		mypk:	ref PK;			# my public key
		cert:	ref Certificate;	# signature of my public key
		spk:	ref PK;			# signers public key
		alpha:	ref IPint;		# diffie helman parameters
		p:	ref IPint;
	};

	# convert types to byte strings
	certtostr: fn (c: ref Certificate): string;
	pktostr: fn (pk: ref PK): string;
	sktostr: fn (sk: ref SK): string;

	# parse byte strings into types
	strtocert: fn (s: string): ref Certificate;
	strtopk: fn (s: string): ref PK;
	strtosk: fn (s: string): ref SK;

	# convert types to attr/value pairs
	certtoattr: fn (c: ref Certificate): string;
	pktoattr: fn (pk: ref PK): string;
	sktoattr: fn (sk: ref SK): string;

	# parse a/v pairs into types
#	attrtocert: fn (s: string): ref Certificate;
#	attrtopk: fn (s: string): ref PK;
#	attrtosk: fn (s: string): ref SK;

	# create and verify signatures
	sign: fn (sk: ref SK, exp: int, state: ref DigestState, ha: string):
		ref Certificate;
	verify: fn (pk: ref PK, cert: ref Certificate, state: ref DigestState):
		int;
	signm: fn (sk: ref SK, m: ref IPint, ha: string):
		ref Certificate;
	verifym: fn (pk: ref PK, cert: ref Certificate, m: ref IPint):
		int;

	# generate keys
	genSK: fn (algname, owner: string, length: int): ref SK; 
	genSKfromPK: fn (pk: ref PK, owner: string): ref SK;
	sktopk: fn (sk: ref SK): ref PK;

	# digests
	md4: fn(buf: array of byte, n: int, digest: array of byte, state: ref DigestState):
		ref DigestState;
	md5: fn(buf: array of byte, n: int, digest: array of byte, state: ref DigestState):
		ref DigestState;
	sha1: fn(buf: array of byte, n: int, digest: array of byte, state: ref DigestState):
		ref DigestState;
	sha224: fn(buf: array of byte, n: int, digest: array of byte, state: ref DigestState):
		ref DigestState;
	sha256: fn(buf: array of byte, n: int, digest: array of byte, state: ref DigestState):
		ref DigestState;
	sha384: fn(buf: array of byte, n: int, digest: array of byte, state: ref DigestState):
		ref DigestState;
	sha512: fn(buf: array of byte, n: int, digest: array of byte, state: ref DigestState):
		ref DigestState;

	hmac_sha1: fn(data: array of byte, n: int, key: array of byte, digest: array of byte, state: ref DigestState):
		ref DigestState;
	hmac_md5: fn(data: array of byte, n: int, key: array of byte, digest: array of byte, state: ref DigestState):
		ref DigestState;

	SHA1dlen:	con 20;
	SHA224dlen:	con 28;
	SHA256dlen:	con 32;
	SHA384dlen:	con 48;
	SHA512dlen:	con 64;
	MD5dlen:	con 16;
	MD4dlen:	con 16;

	# encryption interfaces
	Encrypt:	con 0;
	Decrypt:	con 1;

	AESbsize:	con 16;

	aessetup: fn(key: array of byte, ivec: array of byte): ref AESstate;
	aescbc: fn(state: ref AESstate, buf: array of byte, n: int, direction: int);

	DESbsize: con 8;

	dessetup: fn(key: array of byte, ivec: array of byte): ref DESstate;
	desecb: fn(state: ref DESstate, buf: array of byte, n: int, direction: int);
	descbc: fn(state: ref DESstate, buf: array of byte, n: int, direction: int);

	IDEAbsize: con 8;

	ideasetup: fn(key: array of byte, ivec: array of byte): ref IDEAstate;
	ideaecb: fn(state: ref IDEAstate, buf: array of byte, n: int, direction: int);
	ideacbc: fn(state: ref IDEAstate, buf: array of byte, n: int, direction: int);

	BFbsize: con 8;

	blowfishsetup: fn(key: array of byte, ivec: array of byte): ref BFstate;
#	blowfishecb: fn(state: ref BFstate, buf: array of byte, n: int, direction: int);
	blowfishcbc: fn(state: ref BFstate, buf: array of byte, n: int, direction: int);

	rc4setup:	fn(seed: array of byte): ref RC4state;
	rc4:	fn(state: ref RC4state, buf: array of byte, n: int);
	rc4skip:	fn(state: ref RC4state, n: int);
	rc4back:	fn(state: ref RC4state, n: int);

	# create an alpha and p for diffie helman exchanges
	dhparams: fn(nbits: int): (ref IPint, ref IPint);

	# comm link authentication is symmetric
	auth: fn(fd: ref Sys->FD, info: ref Authinfo, setid: int): (string, array of byte);

	# auth io
	readauthinfo: fn(filename: string): ref Authinfo;
	writeauthinfo: fn(filename: string, info: ref Authinfo): int;

	# message io on a delimited connection (ssl for example)
	#  messages > 4096 bytes are truncated
	#  errors > 64 bytes are truncated
	# getstring and getbytearray return (result, error).
	getstring: fn(fd: ref Sys->FD): (string, string);
	putstring: fn(fd: ref Sys->FD, s: string): int;
	getbytearray: fn(fd: ref Sys->FD): (array of byte, string);
	putbytearray: fn(fd: ref Sys->FD, a: array of byte, n: int): int;
	puterror: fn(fd: ref Sys->FD, s: string): int;

	# to send and receive messages when ssl isn't pushed
	getmsg: fn(fd: ref Sys->FD): array of byte;
	sendmsg: fn(fd: ref Sys->FD, buf: array of byte, n: int): int;
	senderrmsg: fn(fd: ref Sys->FD, s: string): int;

	RSApk: adt {
		n:	ref IPint;		# modulus
		ek:	ref IPint;		# exp (encryption key)

		encrypt:	fn(k: self ref RSApk, m: ref IPint): ref IPint;
		verify:	fn(k: self ref RSApk, sig: ref RSAsig, m: ref IPint): int;
	};

	RSAsk: adt {
		pk:	ref RSApk;
		dk:	ref IPint;		# exp (decryption key)
		p:	ref IPint;		# q in pkcs
		q:	ref IPint;		# p in pkcs

		# precomputed crt values
		kp:	ref IPint;		# k mod p-1
		kq:	ref IPint;		# k mod q-1
		c2:	ref IPint;		# for converting residues to number

		gen:	fn(nlen: int, elen: int, nrep: int): ref RSAsk;
		fill:	fn(n: ref IPint, e: ref IPint, d: ref IPint, p: ref IPint, q: ref IPint): ref RSAsk;
		decrypt:	fn(k: self ref RSAsk, m: ref IPint): ref IPint;
		sign:	fn(k: self ref RSAsk, m: ref IPint): ref RSAsig;
	};

	RSAsig: adt {
		n:	ref IPint;
	};

	DSApk: adt {
		p:	ref IPint;	# modulus
		q:	ref IPint;	# group order, q divides p-1
		alpha: ref IPint;	# group generator
		key:	ref IPint;	# encryption key (alpha**secret mod p)

		verify:	fn(k: self ref DSApk, sig: ref DSAsig, m: ref IPint): int;
	};

	DSAsk: adt {
		pk:	ref DSApk;
		secret:	ref IPint;	# decryption key

		gen:	fn(oldpk: ref DSApk): ref DSAsk;
		sign:	fn(k: self ref DSAsk, m: ref IPint): ref DSAsig;
	};

	DSAsig: adt {
		r:	ref IPint;
		s:	ref IPint;
	};

	EGpk: adt {
		p:	ref IPint;		# modulus
		alpha: ref IPint;		# generator
		key:	ref IPint;		# encryption key (alpha**secret mod p)

		verify:	fn(k: self ref EGpk, sig: ref EGsig, m: ref IPint): int;
	};

	EGsk: adt {
		pk:	ref EGpk;
		secret:	ref IPint;	# decryption key

		gen:	fn(nlen: int, nrep: int): ref EGsk;
		sign:	fn(k: self ref EGsk, m: ref IPint): ref EGsig;
	};

	EGsig: adt {
		r:	ref IPint;
		s:	ref IPint;
	};

};
