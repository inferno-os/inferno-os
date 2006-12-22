implement PKCS;

include "sys.m";
	sys				: Sys;

include "keyring.m";
	keyring				: Keyring;
	IPint				: import keyring;
	DESstate			: import keyring;

include "security.m";
	random				: Random;

include "asn1.m";
	asn1				: ASN1;
	Elem, Oid			: import asn1;

include "pkcs.m";

# pkcs object identifiers

objIdTab = array [] of {
	id_pkcs =>			Oid(array [] of {1,2,840,113549,1}),
	id_pkcs_1 =>			Oid(array [] of {1,2,840,113549,1,1}),
	id_pkcs_rsaEncryption => 	Oid(array [] of {1,2,840,113549,1,1,1}),
	id_pkcs_md2WithRSAEncryption => Oid(array [] of {1,2,840,113549,1,1,2}),
	id_pkcs_md4WithRSAEncryption => Oid(array [] of {1,2,840,113549,1,1,3}),
	id_pkcs_md5WithRSAEncryption =>	Oid(array [] of {1,2,840,113549,1,1,4}),

	id_pkcs_3 =>			Oid(array [] of {1,2,840,113549,1,3}),
	id_pkcs_dhKeyAgreement =>	Oid(array [] of {1,2,840,113549,1,3,1}),

	id_pkcs_5 =>			Oid(array [] of {1,2,840,113549,1,5}),
	id_pkcs_pbeWithMD2AndDESCBC => 	Oid(array [] of {1,2,840,113549,1,5,1}),
	id_pkcs_pbeWithMD5AndDESCBC =>	Oid(array [] of {1,2,840,113549,1,5,3}),

	id_pkcs_7 =>			Oid(array [] of {1,2,840,113549,1,7}),
	id_pkcs_data =>			Oid(array [] of {1,2,840,113549,1,7,1}),
	id_pkcs_singnedData => 		Oid(array [] of {1,2,840,113549,1,7,2}),
	id_pkcs_envelopedData =>	Oid(array [] of {1,2,840,113549,1,7,3}),
	id_pkcs_signedAndEnvelopedData => 	
					Oid(array [] of {1,2,840,113549,1,7,4}),
	id_pkcs_digestData =>		Oid(array [] of {1,2,840,113549,1,7,5}),
	id_pkcs_encryptedData =>	Oid(array [] of {1,2,840,113549,1,7,6}),

	id_pkcs_9 =>			Oid(array [] of {1,2,840,113549,1,9}),
	id_pkcs_emailAddress => 	Oid(array [] of {1,2,840,113549,1,9,1}),
	id_pkcs_unstructuredName =>	Oid(array [] of {1,2,840,113549,1,9,2}),
	id_pkcs_contentType =>		Oid(array [] of {1,2,840,113549,1,9,3}),
	id_pkcs_messageDigest =>	Oid(array [] of {1,2,840,113549,1,9,4}),
	id_pkcs_signingTime =>		Oid(array [] of {1,2,840,113549,1,9,5}),
	id_pkcs_countersignature =>	Oid(array [] of {1,2,840,113549,1,9,6}),
	id_pkcs_challengePassword =>	Oid(array [] of {1,2,840,113549,1,9,7}),
	id_pkcs_unstructuredAddress =>	Oid(array [] of {1,2,840,113549,1,9,8}),
	id_pkcs_extCertAttrs =>		Oid(array [] of {1,2,840,113549,1,9,9}),
	id_algorithm_shaWithDSS =>	Oid(array [] of {1,3,14,3,2,13})
};

# [public]
# initialize PKCS module

init(): string
{
	sys = load Sys Sys->PATH;
	if(sys == nil)
		return "load sys module failed";

	keyring = load Keyring Keyring->PATH;
	if(keyring == nil)
		return "load keyring module failed";

	random = load Random Random->PATH;
	if(random == nil)
		return "load random module failed";

	asn1 = load ASN1 ASN1->PATH;
	if(asn1 == nil)
		return "load asn1 module failed";
	asn1->init();

	return "";
}

# [public]
# Encrypt data according to PKCS#1, with given blocktype, using given key.

rsa_encrypt(data: array of byte, key: ref RSAKey, blocktype: int)
	: (string, array of byte)
{
	if(key == nil) 
		return ("null pkcs#1 key", nil);
	k := key.modlen;
	dlen := len data;
	if(k < 12 || dlen > k-11)
		return ("bad parameters for pkcs#1", nil);
	padlen := k-3-dlen;
	pad := random->randombuf(Random->NotQuiteRandom, padlen);
	for(i:=0; i < padlen; i++) {
		if(blocktype == 0)
			pad[i] = byte 0;
		else if(blocktype == 1)
			pad[i] = byte 16rff;
		else if(pad[i] == byte 0)
			pad[i] = byte 1;
	}
	eb := array[k] of byte;
	eb[0] = byte 0;
	eb[1] = byte blocktype;
	eb[2:] = pad[0:];
	eb[padlen+2] = byte 0;
	eb[padlen+3:] = data[0:];
	return ("", rsacomp(eb, key));
}

# [public]
# Decrypt data according to PKCS#1, with given key.
# If public is true, expect a block type of 0 or 1, else 2.

rsa_decrypt(data: array of byte, key: ref RSAKey, public: int) 
	: (string, array of byte)
{
	eb := rsacomp(data, key);
	k := key.modlen;
	if(len eb == k) {
		bt := int eb[1];
		if(int eb[0] == 0 && ((public && (bt == 0 || bt == 1)) || (!public && bt == 2))) {
			for(i := 2; i < k; i++)
				if(eb[i] == byte 0)
					break;
			if(i < k-1) {
				ans := array[k-(i+1)] of byte;
				ans[0:] = eb[i+1:];
				return ("", ans);
			}
		}
	}
	return ("pkcs1 decryption error", nil);
}

# [private]
# Do RSA computation on block according to key, and pad
# result on left with zeros to make it key.modlen long.

rsacomp(block: array of byte, key: ref RSAKey): array of byte
{
	x := keyring->IPint.bebytestoip(block);
	y := x.expmod(key.exponent, key.modulus);
	ybytes := y.iptobebytes();
	k := key.modlen;
	ylen := len ybytes;
	if(ylen < k) {
		a := array[k] of { * =>  byte 0};
		a[k-ylen:] = ybytes[0:];
		ybytes = a;
	}
	else if(ylen > k) {
		# assume it has leading zeros (mod should make it so)
		a := array[k] of byte;
		a[0:] = ybytes[ylen-k:];
		ybytes = a;
	}
	return ybytes;
}

# [public]

rsa_sign(data: array of byte, sk: ref RSAKey, algid: int): (string, array of byte)
{
	# digesting and add proper padding to it
	ph := padhash(data, algid);

	return rsa_encrypt(ph, sk, 0); # blocktype <- padding with zero
}

# [public]

rsa_verify(data, signature: array of byte, pk: ref RSAKey, algid: int): int
{
	# digesting and add proper padding to it
	ph := padhash(data, algid);
    
	(err, orig) := rsa_decrypt(signature, pk, 0); # blocktype ?
	if(err != "" || !byte_cmp(orig, ph))
		return 0;

	return 1;
}

# [private]
# padding block A
PA := array [] of {
	byte 16r30, byte 16r20, byte 16r30, byte 16r0c, 
	byte 16r06, byte 16r08, byte 16r2a, byte 16r86, 
	byte 16r48, byte 16r86, byte 16rf7, byte 16r0d, 
	byte 16r02
};

# [private]
# padding block B
PB := array [] of {byte 16r05, byte 16r00, byte 16r04, byte 16r10};

# [private]
# require either md5 or md2 of 16 bytes digest
# length of padded digest = 13 + 1 + 4 + 16

padhash(data: array of byte, algid: int): array of byte
{
	padded := array [34] of byte;
	case algid {
	MD2_WithRSAEncryption =>
		padded[13] = byte 2;
		# TODO: implement md2 in keyring module
		# keyring->md2(data, len data, padded[18:], nil);

	MD5_WithRSAEncryption =>	
		padded[13] = byte 5;
		keyring->md5(data, len data, padded[18:], nil);
	* =>
		return nil;
	}
	padded[0:] = PA;
	padded[14:] = PB;

	return padded;
}

# [private]
# compare byte to byte of two array of byte

byte_cmp(a, b: array of byte): int
{
	if(len a != len b)
		return 0;

	for(i := 0; i < len a; i++) {
		if(a[i] != b[i])
			return 0;
	}

	return 1;
}

# [public]

RSAKey.bits(key: self ref RSAKey): int
{
	return key.modulus.bits();
}

# [public]
# Decode an RSAPublicKey ASN1 type, defined as:
#
#	RSAPublickKey :: SEQUENCE {
#		modulus INTEGER,
#		publicExponent INTEGER
#	}

decode_rsapubkey(a: array of byte): (string, ref RSAKey)
{
parse:
	for(;;) {
		(err, e) := asn1->decode(a);
		if(err != "")
			break parse;
		(ok, el) := e.is_seq();
		if(!ok || len el != 2)
			break parse;
		modbytes, expbytes: array of byte;
		(ok, modbytes) = (hd el).is_bigint();
		if(!ok)
			break parse;
		modulus := IPint.bebytestoip(modbytes);
		# get modlen this way, because sometimes it
		# comes with leading zeros that are to be ignored!
		mbytes := modulus.iptobebytes();
		modlen := len mbytes;
		(ok, expbytes) = (hd tl el).is_bigint();
		if(!ok)
			break parse;
		exponent := keyring->IPint.bebytestoip(expbytes);
		return ("", ref RSAKey(modulus, modlen, exponent));
	}
	return ("rsa public key: syntax error", nil);
}


# [public]
# generate a pair of DSS public and private keys

generateDSSKeyPair(strength: int): (ref DSSPublicKey, ref DSSPrivateKey)
{
	# TODO: need add getRandBetween in IPint
	return (nil, nil);
}

# [public]

dss_sign(a: array of byte, sk: ref DSSPrivateKey): (string, array of byte)
{
	#signature, digest: array of byte;

	#case hash {
	#Keyring->MD4 =>
	#	digest = array [Keyring->MD4dlen] of byte;
	#	keyring->md4(a, len a, digest, nil);
	#Keyring->MD5 =>
	#	digest = array [Keyring->MD5dlen] of byte;
	#	keyring->md5(a, len a, digest, nil);
	#Keyring->SHA =>
	#	digest = array [Keyring->SHA1dlen] of byte;
	#	keyring->sha1(a, len a, digest, nil);
	#* =>
	#	return ("unknown hash algorithm", nil);
	#}

	# TODO: add gcd or getRandBetween in Keyring->IPint
	return ("unsupported error", nil);
}

# [public]

dss_verify(a, signa: array of byte, pk: ref DSSPublicKey): int
{
	unsigned: array of byte;

	#case hash {
	#Keyring->MD4 =>
	#	digest = array [Keyring->MD4dlen] of byte;
	#	keyring->md4(a, len a, digest, nil);
	#Keyring->MD5 =>
	#	digest = array [Keyring->MD5dlen] of byte;
	#	keyring->md5(a, len a, digest, nil);
	#Keyring->SHA =>
	#	digest = array [Keyring->SHA1dlen] of byte;
	#	keyring->sha1(a, len a, digest, nil);
	#* =>
	#	return 0;
	#}

	# get unsigned from signa and compare it with digest

	if(byte_cmp(unsigned, a))
		return 1;

	return 0;
}

# [public]
decode_dsspubkey(a: array of byte): (string, ref DSSPublicKey)
{
	return ("unsupported error", nil);
}


# [public]
# generate DH parameters with prime length at least (default) 512 bits

generateDHParams(primelen: int): ref DHParams
{
	# prime - at least 512 bits
	if(primelen < 512) # DHmodlen
		primelen = 512;

	# generate prime and base (generator) integers
	(p, g) := keyring->dhparams(primelen);
	if(p == nil || g == nil)
		return nil;

	return ref DHParams(p, g, 0);
}

# [public]
# generate public and private key pair
# Note: use iptobytes as integer to octet string conversion
#	and bytestoip as octect string to integer reversion

setupDHAgreement(dh: ref DHParams): (ref DHPrivateKey, ref DHPublicKey)
{
	if(dh == nil || dh.prime == nil || dh.base == nil)
		return (nil, nil);

	# prime length in bits
	bits := dh.prime.bits();

	# generate random private key of length between bits/4 and bits
	x := IPint.random(bits/4, bits);
	if(x == nil)
		return (nil, nil);
	dh.privateValueLength = x.bits();

	# calculate public key
	y := dh.base.expmod(x, dh.prime);
	if(y == nil)
		return (nil, nil);

	return (ref DHPrivateKey(dh, y, x), ref DHPublicKey(dh, x));
}

# [public]
# The second phase of Diffie-Hellman key agreement

computeDHAgreedKey(dh: ref DHParams, mysk, upk: ref IPint)
	: array of byte
{
	if(mysk == nil || upk == nil)
		return nil;

	# exponential - calculate agreed key (shared secret)
	z := upk.expmod(mysk, dh.prime);

	# integer to octet conversion
	return z.iptobebytes();
}

# [public]
# ASN1 encoding

decode_dhpubkey(a: array of byte): (string, ref DHPublicKey)
{
	return ("unsupported error", nil);
}


# [public]
# Digest the concatenation of password and salt with count iterations of
# selected message-digest algorithm (either md2 or md5).
# The first 8 bytes of the message digest become the DES key.
# The last 8 bytes of the message digest become the initializing vector IV.

generateDESKey(pw: array of byte, param: ref PBEParams, alg: int)
	: (ref DESstate, array of byte, array of byte)
{
	if(param.iterationCount < 1)
		return (nil, nil, nil);

	# concanate password and salt
	pwlen := len pw;
	pslen := pwlen + len param.salt;
	ps := array [pslen] of byte;
	ps[0:] = pw;
	ps[pwlen:] = param.salt;
	key, iv: array of byte;

	# digest iterations
	case alg {
	PBE_MD2_DESCBC =>
		ds : ref Keyring->DigestState = nil;
		# TODO: implement md2 in keyring module
		#result := array [Keyring->MD2dlen] of byte;
		#for(i := 0; i < param.iterationCount; i++)
		#	ds = keyring->md2(ps, pslen, nil, ds);	
		#keyring->md2(ps, pslen, result, ds);	
		#key = result[0:8];
		#iv = result[8:];

	PBE_MD5_DESCBC =>
		ds: ref Keyring->DigestState = nil;
		result := array [Keyring->MD5dlen] of byte;
		for(i := 0; i < param.iterationCount; i++) 
			ds = keyring->md5(ps, pslen, nil, ds);
		keyring->md5(ps, pslen, result, ds);
		key = result[0:8];
		iv = result[8:];

	* =>
		return (nil, nil, nil);
	}

	state := keyring->dessetup(key, iv);

	return (state, key, iv);
}

# [public]
# The message M and a padding string PS shall be formatted into
# an octet string EB
# 	EB = M + PS
# where
#	PS = 1 if M mod 8 = 7;
#	PS = 2 + 2 if M mod 8 = 6;
#	...
#	PS = 8 + 8 + 8 + 8 + 8 + 8 + 8 + 8 if M mod 8 = 0;

pbe_encrypt(state: ref DESstate, m: array of byte): array of byte
{
	mlen := len m;
	padvalue :=  mlen % 8;
	pdlen := 8 - padvalue;

	eb := array [mlen + pdlen] of byte;
	eb[0:] = m;
	for(i := mlen; i < pdlen; i++)
		eb[i] = byte padvalue;

	keyring->descbc(state, eb, len eb, Keyring->Encrypt);

	return eb;
}

# [public]

pbe_decrypt(state: ref DESstate, eb: array of byte): array of byte
{
	eblen := len eb;
	if(eblen%8 != 0) # must a multiple of 8 bytes
		return nil;

	keyring->descbc(state, eb, eblen, Keyring->Decrypt);	

	# remove padding
	for(i := eblen -8; i < 8; i++) {
		if(int eb[i] == i) {
			for(j := i; j < 8; j++)
				if(int eb[j] != i)
					break;
			if(j == 8)
				break;
		}
	}

	return eb[0:i];
}

# [public]

PrivateKeyInfo.encode(p: self ref PrivateKeyInfo): (string, array of byte)
{

	return ("unsupported error", nil);
}

# [public]

PrivateKeyInfo.decode(a: array of byte): (string, ref PrivateKeyInfo)
{
	return ("unsupported error", nil);
}

# [public]

EncryptedPrivateKeyInfo.encode(p: self ref EncryptedPrivateKeyInfo)
	: (string, array of byte)
{

	return ("unsupported error", nil);
}

# [public]

EncryptedPrivateKeyInfo.decode(a: array of byte)
	: (string, ref EncryptedPrivateKeyInfo)
{
	return ("unsupported error", nil);
}

# [public]

decode_extcertorcert(a: array of byte): (int, int, array of byte)
{
	(err, all) := asn1->decode(a);
	if(err == "") {

	}
}

# [public]

encode_extcertorcert(a: array of byte, which: int): (int, array of byte)
{

}

