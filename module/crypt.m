#
#  basic cryptography routines implemented in C
#
Crypt: module
{
	PATH:	con	"$Crypt";

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

	# digests
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
	md4: fn(buf: array of byte, n: int, digest: array of byte, state: ref DigestState):
		ref DigestState;
	md5: fn(buf: array of byte, n: int, digest: array of byte, state: ref DigestState):
		ref DigestState;

	hmac_sha1: fn(data: array of byte, n: int, key: array of byte, digest: array of byte, state: ref DigestState):
		ref DigestState;
	hmac_md5: fn(data: array of byte, n: int, key: array of byte, digest: array of byte, state: ref DigestState):
		ref DigestState;

	SHA1dlen: con 20;
	SHA224dlen:	con 28;
	SHA256dlen: con 32;
	SHA384dlen: con 48;
	SHA512dlen: con 64;
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
	dhparams: fn(nbits: int): (ref IPints->IPint, ref IPints->IPint);

	# public key
	PK: adt
	{
		pick {
		RSA =>
			n:	ref IPints->IPint;		# modulus
			ek:	ref IPints->IPint;		# exp (encryption key)
		Elgamal =>
			p:	ref IPints->IPint;		# modulus
			alpha: ref IPints->IPint;		# generator
			key:	ref IPints->IPint;		# encryption key (alpha**secret mod p)
		DSA =>
			p:	ref IPints->IPint;	# modulus
			q:	ref IPints->IPint;	# group order, q divides p-1
			alpha: ref IPints->IPint;	# group generator
			key:	ref IPints->IPint;	# encryption key (alpha**secret mod p)
		}
	};
	
	# secret key (private/public key pair)
	SK: adt
	{
		pick {
		RSA =>
			pk:	ref PK.RSA;
			dk:	ref IPints->IPint;		# exp (decryption key)
			p:	ref IPints->IPint;		# q in pkcs
			q:	ref IPints->IPint;		# p in pkcs
			# precomputed crt values
			kp:	ref IPints->IPint;		# k mod p-1
			kq:	ref IPints->IPint;		# k mod q-1
			c2:	ref IPints->IPint;		# for converting residues to number
		Elgamal =>
			pk:	ref PK.Elgamal;
			secret:	ref IPints->IPint;	# decryption key
		DSA =>
			pk:	ref PK.DSA;
			secret:	ref IPints->IPint;	# decryption key
		}
	};

	# public key signature
	PKsig: adt
	{
		# could just have list or array of ref IPints->IPint
		pick {
		RSA =>
			n:	ref IPints->IPint;
		Elgamal =>
			r:	ref IPints->IPint;
			s:	ref IPints->IPint;
		DSA =>
			r:	ref IPints->IPint;
			s:	ref IPints->IPint;
		}
	};

	# RSA keys
	rsagen:	fn(nlen: int, elen: int, nrep: int): ref SK.RSA;
	rsafill:	fn(n: ref IPints->IPint, ek: ref IPints->IPint, dk: ref IPints->IPint, p: ref IPints->IPint, q: ref IPints->IPint): ref SK.RSA;
	rsadecrypt:	fn(k: ref SK.RSA, m: ref IPints->IPint): ref IPints->IPint;
	rsaencrypt:	fn(k: ref PK.RSA, m: ref IPints->IPint): ref IPints->IPint;

	# Elgamal
	eggen:	fn(nlen: int, nrep: int): ref SK.Elgamal;

	# DSA
	dsagen:	fn(oldpk: ref PK.DSA): ref SK.DSA;

	# generic signature functions
	genSK: 	fn(algname: string, length: int): ref SK;
	genSKfromPK: fn(pk: ref PK): ref SK;
	sign:		fn(sk: ref SK, m: ref IPints->IPint): ref PKsig;
	verify:	fn(pk: ref PK, sig: ref PKsig, m: ref IPints->IPint): int;
	sktopk:	fn(sk: ref SK): ref PK;

	# modern primitives; byte arrays throughout, nil on a bad argument
	X25519len:	con 32;
	Ed25519seedlen:	con 32;
	Ed25519siglen:	con 64;
	XChachakeylen:	con 32;
	XChachanoncelen:	con 24;
	Polytaglen:	con 16;
	MLKEM768eklen:	con 1184;
	MLKEM768dklen:	con 2400;
	MLKEM768ctlen:	con 1088;
	MLDSA65seedlen:	con 32;
	MLDSA65pklen:	con 1952;
	MLDSA65siglen:	con 3309;

	x25519:	fn(secret: array of byte, point: array of byte): array of byte;
	x25519base:	fn(secret: array of byte): array of byte;
	# Elligator 2: a point for a 32-byte field element (RFC 9380's map for curve25519), for CPace
	x25519map:	fn(fe: array of byte): array of byte;
	ed25519pub:	fn(seed: array of byte): array of byte;
	ed25519sign:	fn(seed: array of byte, msg: array of byte): array of byte;
	ed25519verify:	fn(pub: array of byte, msg: array of byte, sig: array of byte): int;
	hkdfsha256:	fn(salt: array of byte, ikm: array of byte, info: array of byte, n: int): array of byte;
	# seal returns ciphertext then a 16-byte tag; open returns nil if the tag is wrong
	xchachapolyseal:	fn(key: array of byte, nonce: array of byte, ad: array of byte, plain: array of byte): array of byte;
	xchachapolyopen:	fn(key: array of byte, nonce: array of byte, ad: array of byte, sealed: array of byte): array of byte;
	# ML-KEM-768 (FIPS 203): keygen gives (encapsulation key, decapsulation key),
	# encap gives (ciphertext, shared secret)
	mlkem768keygen:	fn(): (array of byte, array of byte);
	mlkem768encap:	fn(ek: array of byte): (array of byte, array of byte);
	mlkem768decap:	fn(dk: array of byte, ct: array of byte): array of byte;
	# deterministic forms, for known-answer tests only
	mlkem768keygenderand:	fn(coins: array of byte): (array of byte, array of byte);
	mlkem768encapderand:	fn(ek: array of byte, coins: array of byte): (array of byte, array of byte);
	# ML-DSA-65 (FIPS 204): the secret key is its 32-byte seed; signing is
	# deterministic; ctx is the context string (nil or up to 255 bytes).
	# sign returns nil on bad arguments
	mldsa65pub:	fn(seed: array of byte): array of byte;
	mldsa65sign:	fn(seed: array of byte, msg: array of byte, ctx: array of byte): array of byte;
	mldsa65verify:	fn(pk: array of byte, msg: array of byte, ctx: array of byte, sig: array of byte): int;
};
