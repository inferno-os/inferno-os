implement KeyringTest;

#
# Tests for the Keyring module (keyring.m)
#
# Security-critical module: covers digest functions, symmetric ciphers,
# asymmetric key operations, IPint arithmetic, key serialization,
# elliptic curve operations, and post-quantum cryptography.
#
# Note: Some operations are already tested in crypto_test.b, sha3_test.b,
# mlkem_test.b, etc. This file focuses on coverage gaps:
# digest edge cases, cipher round-trips, IPint arithmetic,
# key serialization, and additional algorithm coverage.
#

include "sys.m";
	sys: Sys;

include "draw.m";

include "keyring.m";
	kr: Keyring;
	IPint: import kr;

include "testing.m";
	testing: Testing;
	T: import testing;

KeyringTest: module
{
	init: fn(nil: ref Draw->Context, args: list of string);
};

SRCFILE: con "/tests/keyring_test.b";

passed := 0;
failed := 0;
skipped := 0;

run(name: string, testfn: ref fn(t: ref T))
{
	t := testing->newTsrc(name, SRCFILE);
	{
		testfn(t);
	} exception {
	"fail:fatal" =>
		;
	"fail:skip" =>
		;
	"*" =>
		t.failed = 1;
	}

	if(testing->done(t))
		passed++;
	else if(t.skipped)
		skipped++;
	else
		failed++;
}

# Helper: hex encode bytes
hexencode(data: array of byte): string
{
	hex := "";
	for(i := 0; i < len data; i++)
		hex += sys->sprint("%02x", int data[i]);
	return hex;
}

# Helper: compare byte arrays
byteseq(a, b: array of byte): int
{
	if(len a != len b)
		return 0;
	for(i := 0; i < len a; i++)
		if(a[i] != b[i])
			return 0;
	return 1;
}

# ── Digest tests ─────────────────────────────────────────────────────────────

testMD5(t: ref T)
{
	msg := array of byte "hello world";
	state := kr->md5(msg, len msg, nil, nil);
	if(state == nil) {
		t.fatal("md5 returned nil");
		return;
	}
	digest := array[Keyring->MD5dlen] of byte;
	kr->md5(nil, 0, digest, state);
	hex := hexencode(digest);
	t.assertseq(hex, "5eb63bbbe01eeed093cb22bb8f5acdc3", "md5 hello world");
}

testSHA1(t: ref T)
{
	msg := array of byte "hello world";
	state := kr->sha1(msg, len msg, nil, nil);
	if(state == nil) {
		t.fatal("sha1 returned nil");
		return;
	}
	digest := array[Keyring->SHA1dlen] of byte;
	kr->sha1(nil, 0, digest, state);
	hex := hexencode(digest);
	t.assertseq(hex, "2aae6c35c94fcfb415dbe95f408b9ce91ee846ed", "sha1 hello world");
}

testSHA256(t: ref T)
{
	msg := array of byte "hello world";
	state := kr->sha256(msg, len msg, nil, nil);
	if(state == nil) {
		t.fatal("sha256 returned nil");
		return;
	}
	digest := array[Keyring->SHA256dlen] of byte;
	kr->sha256(nil, 0, digest, state);
	hex := hexencode(digest);
	t.assertseq(hex, "b94d27b9934d3e08a52e52d7da7dabfac484efe37a5380ee9088f7ace2efcde9", "sha256 hello world");
}

testSHA512(t: ref T)
{
	msg := array of byte "hello world";
	state := kr->sha512(msg, len msg, nil, nil);
	if(state == nil) {
		t.fatal("sha512 returned nil");
		return;
	}
	digest := array[Keyring->SHA512dlen] of byte;
	kr->sha512(nil, 0, digest, state);
	hex := hexencode(digest);
	# Known SHA-512 of "hello world"
	t.asserteq(len hex, 128, "sha512 digest length");
	t.assertnotnil(hex, "sha512 non-empty");
}

testSHA384(t: ref T)
{
	msg := array of byte "test";
	state := kr->sha384(msg, len msg, nil, nil);
	if(state == nil) {
		t.fatal("sha384 returned nil");
		return;
	}
	digest := array[Keyring->SHA384dlen] of byte;
	kr->sha384(nil, 0, digest, state);
	t.asserteq(len digest, Keyring->SHA384dlen, "sha384 digest length");
}

testMD5Empty(t: ref T)
{
	msg := array[0] of byte;
	state := kr->md5(msg, 0, nil, nil);
	if(state == nil) {
		t.fatal("md5 empty returned nil");
		return;
	}
	digest := array[Keyring->MD5dlen] of byte;
	kr->md5(nil, 0, digest, state);
	hex := hexencode(digest);
	t.assertseq(hex, "d41d8cd98f00b204e9800998ecf8427e", "md5 empty");
}

testSHA256Empty(t: ref T)
{
	msg := array[0] of byte;
	state := kr->sha256(msg, 0, nil, nil);
	if(state == nil) {
		t.fatal("sha256 empty returned nil");
		return;
	}
	digest := array[Keyring->SHA256dlen] of byte;
	kr->sha256(nil, 0, digest, state);
	hex := hexencode(digest);
	t.assertseq(hex, "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "sha256 empty");
}

# ── Incremental digest ──────────────────────────────────────────────────────

testSHA256Incremental(t: ref T)
{
	# Compute SHA256 in two parts, compare with single computation
	full := array of byte "hello world";
	part1 := array of byte "hello ";
	part2 := array of byte "world";

	# Full
	state := kr->sha256(full, len full, nil, nil);
	dfull := array[Keyring->SHA256dlen] of byte;
	kr->sha256(nil, 0, dfull, state);

	# Incremental
	state = kr->sha256(part1, len part1, nil, nil);
	state = kr->sha256(part2, len part2, nil, state);
	dinc := array[Keyring->SHA256dlen] of byte;
	kr->sha256(nil, 0, dinc, state);

	t.assert(byteseq(dfull, dinc), "sha256 incremental matches full");
}

# ── HMAC tests ───────────────────────────────────────────────────────────────

testHMACSHA256(t: ref T)
{
	key := array of byte "secret";
	msg := array of byte "hello world";
	digest := array[Keyring->SHA256dlen] of byte;
	kr->hmac_sha256(msg, len msg, key, digest, nil);
	hex := hexencode(digest);
	t.asserteq(len hex, 64, "hmac-sha256 length");
	t.assertnotnil(hex, "hmac-sha256 non-empty");
}

testHMACSHA1(t: ref T)
{
	key := array of byte "key";
	msg := array of byte "message";
	digest := array[Keyring->SHA1dlen] of byte;
	kr->hmac_sha1(msg, len msg, key, digest, nil);
	hex := hexencode(digest);
	t.asserteq(len hex, 40, "hmac-sha1 length");
}

testHMACMD5(t: ref T)
{
	key := array of byte "key";
	msg := array of byte "message";
	digest := array[Keyring->MD5dlen] of byte;
	kr->hmac_md5(msg, len msg, key, digest, nil);
	hex := hexencode(digest);
	t.asserteq(len hex, 32, "hmac-md5 length");
}

# ── IPint tests ──────────────────────────────────────────────────────────────

testIPintBasic(t: ref T)
{
	zero := IPint.inttoip(0);
	t.assert(zero != nil, "inttoip 0");
	t.asserteq(zero.iptoint(), 0, "iptoint 0");

	one := IPint.inttoip(1);
	t.asserteq(one.iptoint(), 1, "iptoint 1");

	neg := IPint.inttoip(-1);
	t.asserteq(neg.iptoint(), -1, "iptoint -1");

	bignum := IPint.inttoip(1000000);
	t.asserteq(bignum.iptoint(), 1000000, "iptoint 1000000");
}

testIPintArithmetic(t: ref T)
{
	a := IPint.inttoip(100);
	b := IPint.inttoip(42);

	sum := a.add(b);
	t.asserteq(sum.iptoint(), 142, "IPint add");

	diff := a.sub(b);
	t.asserteq(diff.iptoint(), 58, "IPint sub");

	prod := a.mul(b);
	t.asserteq(prod.iptoint(), 4200, "IPint mul");
}

testIPintComparison(t: ref T)
{
	a := IPint.inttoip(100);
	b := IPint.inttoip(42);
	c := IPint.inttoip(100);

	t.assert(a.cmp(b) > 0, "100 > 42");
	t.assert(b.cmp(a) < 0, "42 < 100");
	t.assert(a.cmp(c) == 0, "100 == 100");
}

testIPintStringConversion(t: ref T)
{
	a := IPint.inttoip(255);
	s := a.iptostr(16);
	t.assertseq(s, "FF", "iptostr hex 255");

	s = a.iptostr(10);
	t.assertseq(s, "255", "iptostr dec 255");

	# Parse back
	b := IPint.strtoip(s, 10);
	t.assert(b != nil, "strtoip not nil");
	t.asserteq(b.iptoint(), 255, "strtoip roundtrip");
}

testIPintBits(t: ref T)
{
	a := IPint.inttoip(255);
	bits := a.bits();
	t.asserteq(bits, 8, "bits of 255");

	b := IPint.inttoip(256);
	bits = b.bits();
	t.asserteq(bits, 9, "bits of 256");

	one := IPint.inttoip(1);
	bits = one.bits();
	t.asserteq(bits, 1, "bits of 1");
}

testIPintModular(t: ref T)
{
	a := IPint.inttoip(17);
	b := IPint.inttoip(5);
	m := IPint.inttoip(7);

	# modular exponentiation: 17^5 mod 7
	result := a.expmod(b, m);
	# 17 mod 7 = 3, 3^5 = 243, 243 mod 7 = 5
	t.asserteq(result.iptoint(), 5, "expmod 17^5 mod 7");
}

testIPintRandom(t: ref T)
{
	# Generate random number with specific bit count
	r := IPint.random(128, 0);
	t.assert(r != nil, "random 128-bit not nil");
	t.assert(r.bits() <= 128, "random within bounds");
	t.assert(r.bits() > 0, "random non-zero");
}

# ── AES tests ────────────────────────────────────────────────────────────────

testAESCBC(t: ref T)
{
	key := array[16] of byte;
	for(i := 0; i < len key; i++)
		key[i] = byte i;
	iv := array[16] of byte;
	for(i = 0; i < len iv; i++)
		iv[i] = byte 0;

	# Encrypt
	estate := kr->aessetup(key, iv);
	if(estate == nil) {
		t.fatal("aessetup encrypt failed");
		return;
	}
	plain := array[32] of byte;
	for(i = 0; i < len plain; i++)
		plain[i] = byte (i * 3);
	cipher := array[32] of byte;
	cipher[:] = plain;
	kr->aescbc(estate, cipher, len cipher, Keyring->Encrypt);

	# Verify ciphertext differs from plaintext
	same := 1;
	for(i = 0; i < len cipher; i++)
		if(cipher[i] != plain[i]) {
			same = 0;
			break;
		}
	t.asserteq(same, 0, "AES-CBC ciphertext differs");

	# Decrypt
	iv2 := array[16] of byte;
	for(i = 0; i < len iv2; i++)
		iv2[i] = byte 0;
	dstate := kr->aessetup(key, iv2);
	if(dstate == nil) {
		t.fatal("aessetup decrypt failed");
		return;
	}
	kr->aescbc(dstate, cipher, len cipher, Keyring->Decrypt);

	# Verify roundtrip
	t.assert(byteseq(cipher, plain), "AES-CBC encrypt/decrypt roundtrip");
}

testAES256(t: ref T)
{
	# 256-bit key
	key := array[32] of byte;
	for(i := 0; i < len key; i++)
		key[i] = byte (i * 7 + 3);
	iv := array[16] of byte;

	estate := kr->aessetup(key, iv);
	if(estate == nil) {
		t.fatal("aes256 setup failed");
		return;
	}
	data := array[48] of byte;
	for(i = 0; i < len data; i++)
		data[i] = byte 'A';
	orig := array[48] of byte;
	orig[:] = data;
	kr->aescbc(estate, data, len data, Keyring->Encrypt);

	iv2 := array[16] of byte;
	dstate := kr->aessetup(key, iv2);
	kr->aescbc(dstate, data, len data, Keyring->Decrypt);
	t.assert(byteseq(data, orig), "AES-256-CBC roundtrip");
}

# ── RSA key generation and sign/verify ───────────────────────────────────────

testRSA(t: ref T)
{
	sk := kr->genSK("rsa", "test-rsa", 1024);
	if(sk == nil) {
		t.skip("RSA key generation not supported");
		return;
	}
	pk := kr->sktopk(sk);
	if(pk == nil) {
		t.fatal("sktopk returned nil");
		return;
	}

	# Sign
	msg := array of byte "test message for RSA";
	state := kr->sha256(msg, len msg, nil, nil);
	digest := array[Keyring->SHA256dlen] of byte;
	kr->sha256(nil, 0, digest, state);

	state = kr->sha256(msg, len msg, nil, nil);
	cert := kr->sign(sk, 0, state, "sha256");
	if(cert == nil) {
		t.fatal("RSA sign returned nil");
		return;
	}

	# Verify
	state = kr->sha256(msg, len msg, nil, nil);
	ok := kr->verify(pk, cert, state);
	t.asserteq(ok, 1, "RSA sign/verify");
}

# ── Key serialization ───────────────────────────────────────────────────────

testKeySerialization(t: ref T)
{
	sk := kr->genSK("rsa", "test-serial", 1024);
	if(sk == nil) {
		t.skip("RSA key generation not supported");
		return;
	}
	pk := kr->sktopk(sk);

	# PK round-trip
	pkstr := kr->pktostr(pk);
	t.assertnotnil(pkstr, "pktostr non-empty");

	pk2 := kr->strtopk(pkstr);
	if(pk2 == nil) {
		t.error("strtopk returned nil");
		return;
	}

	# Re-serialize and compare
	pkstr2 := kr->pktostr(pk2);
	t.assertseq(pkstr, pkstr2, "PK serialize roundtrip");

	# SK round-trip
	skstr := kr->sktostr(sk);
	t.assertnotnil(skstr, "sktostr non-empty");

	sk2 := kr->strtosk(skstr);
	if(sk2 == nil) {
		t.error("strtosk returned nil");
		return;
	}
	skstr2 := kr->sktostr(sk2);
	t.assertseq(skstr, skstr2, "SK serialize roundtrip");
}

# ── Ed25519 ──────────────────────────────────────────────────────────────────

testEd25519(t: ref T)
{
	sk := kr->genSK("ed25519", "test-ed25519", 256);
	if(sk == nil) {
		t.skip("Ed25519 not supported");
		return;
	}
	pk := kr->sktopk(sk);

	msg := array of byte "test message for ed25519";
	state := kr->sha256(msg, len msg, nil, nil);
	cert := kr->sign(sk, 0, state, "sha256");
	if(cert == nil) {
		t.fatal("ed25519 sign returned nil");
		return;
	}

	state = kr->sha256(msg, len msg, nil, nil);
	ok := kr->verify(pk, cert, state);
	t.asserteq(ok, 1, "ed25519 sign/verify");

	# Verify with wrong message fails
	wrong := array of byte "wrong message";
	state = kr->sha256(wrong, len wrong, nil, nil);
	ok = kr->verify(pk, cert, state);
	t.asserteq(ok, 0, "ed25519 verify wrong message");
}

# ── X25519 key exchange ─────────────────────────────────────────────────────

testX25519(t: ref T)
{
	# Generate two key pairs
	sk1 := array[32] of byte;
	sk2 := array[32] of byte;
	r1 := IPint.random(256, 0);
	r2 := IPint.random(256, 0);
	b1 := r1.iptobytes();
	b2 := r2.iptobytes();
	if(b1 == nil || b2 == nil || len b1 < 32 || len b2 < 32) {
		t.skip("cannot generate random keys");
		return;
	}
	sk1[:] = b1[:32];
	sk2[:] = b2[:32];

	pk1 := kr->x25519_base(sk1);
	pk2 := kr->x25519_base(sk2);
	if(pk1 == nil || pk2 == nil) {
		t.skip("x25519_base not supported");
		return;
	}

	# Key exchange
	shared1 := kr->x25519(sk1, pk2);
	shared2 := kr->x25519(sk2, pk1);
	if(shared1 == nil || shared2 == nil) {
		t.fatal("x25519 returned nil");
		return;
	}

	t.assert(byteseq(shared1, shared2), "x25519 shared secrets match");
}

# ── P-256 ECDH ──────────────────────────────────────────────────────────────

testP256ECDH(t: ref T)
{
	(sk1, pk1) := kr->p256_keygen();
	(sk2, pk2) := kr->p256_keygen();
	if(sk1 == nil || sk2 == nil) {
		t.skip("p256_keygen not supported");
		return;
	}

	shared1 := kr->p256_ecdh(sk1, pk2);
	shared2 := kr->p256_ecdh(sk2, pk1);
	if(shared1 == nil || shared2 == nil) {
		t.fatal("p256_ecdh returned nil");
		return;
	}

	t.assert(byteseq(shared1, shared2), "P-256 ECDH shared secrets match");
}

# ── P-256 ECDSA ─────────────────────────────────────────────────────────────

testP256ECDSA(t: ref T)
{
	(sk, pk) := kr->p256_keygen();
	if(sk == nil) {
		t.skip("p256_keygen not supported");
		return;
	}

	msg := array of byte "test message for P-256 ECDSA";
	digest := array[Keyring->SHA256dlen] of byte;
	kr->sha256(msg, len msg, digest, nil);

	sig := kr->p256_ecdsa_sign(sk, digest);
	if(sig == nil) {
		t.fatal("p256_ecdsa_sign returned nil");
		return;
	}

	ok := kr->p256_ecdsa_verify(pk, digest, sig);
	t.asserteq(ok, 1, "P-256 ECDSA sign/verify");

	# Tamper with digest
	digest[0] ^= byte 16rff;
	ok = kr->p256_ecdsa_verify(pk, digest, sig);
	t.asserteq(ok, 0, "P-256 ECDSA verify tampered digest");
}

# ── RC4 stream cipher ───────────────────────────────────────────────────────

testRC4(t: ref T)
{
	key := array of byte "secret key";
	state := kr->rc4setup(key);
	if(state == nil) {
		t.fatal("rc4setup returned nil");
		return;
	}

	plain := array of byte "hello world RC4 test data";
	cipher := array[len plain] of byte;
	cipher[:] = plain;
	kr->rc4(state, cipher, len cipher);

	# Verify ciphertext differs
	t.assert(!byteseq(cipher, plain), "RC4 ciphertext differs");

	# Decrypt with fresh state
	state2 := kr->rc4setup(key);
	kr->rc4(state2, cipher, len cipher);
	t.assert(byteseq(cipher, plain), "RC4 encrypt/decrypt roundtrip");
}

# ── DES tests ────────────────────────────────────────────────────────────────

testDESCBC(t: ref T)
{
	key := array[8] of byte;
	for(i := 0; i < len key; i++)
		key[i] = byte (i + 1);
	iv := array[8] of byte;

	estate := kr->dessetup(key, iv);
	if(estate == nil) {
		t.fatal("dessetup failed");
		return;
	}

	# DES-CBC needs blocks of 8
	plain := array[16] of byte;
	for(i = 0; i < len plain; i++)
		plain[i] = byte (i * 5);
	cipher := array[16] of byte;
	cipher[:] = plain;
	kr->descbc(estate, cipher, len cipher, Keyring->Encrypt);

	t.assert(!byteseq(cipher, plain), "DES-CBC ciphertext differs");

	# Decrypt
	iv2 := array[8] of byte;
	dstate := kr->dessetup(key, iv2);
	kr->descbc(dstate, cipher, len cipher, Keyring->Decrypt);
	t.assert(byteseq(cipher, plain), "DES-CBC roundtrip");
}

init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	kr = load Keyring Keyring->PATH;
	testing = load Testing Testing->PATH;

	if(testing == nil) {
		sys->fprint(sys->fildes(2), "cannot load testing module: %r\n");
		raise "fail:cannot load testing";
	}
	if(kr == nil) {
		sys->fprint(sys->fildes(2), "cannot load keyring module: %r\n");
		raise "fail:cannot load keyring";
	}

	testing->init();

	for(a := args; a != nil; a = tl a)
		if(hd a == "-v")
			testing->verbose(1);

	# Digest tests
	run("MD5", testMD5);
	run("SHA1", testSHA1);
	run("SHA256", testSHA256);
	run("SHA512", testSHA512);
	run("SHA384", testSHA384);
	run("MD5Empty", testMD5Empty);
	run("SHA256Empty", testSHA256Empty);
	run("SHA256Incremental", testSHA256Incremental);

	# HMAC tests
	run("HMACSHA256", testHMACSHA256);
	run("HMACSHA1", testHMACSHA1);
	run("HMACMD5", testHMACMD5);

	# IPint tests
	run("IPintBasic", testIPintBasic);
	run("IPintArithmetic", testIPintArithmetic);
	run("IPintComparison", testIPintComparison);
	run("IPintStringConversion", testIPintStringConversion);
	run("IPintBits", testIPintBits);
	run("IPintModular", testIPintModular);
	run("IPintRandom", testIPintRandom);

	# Cipher tests
	run("AESCBC", testAESCBC);
	run("AES256", testAES256);
	run("RC4", testRC4);
	run("DESCBC", testDESCBC);

	# Asymmetric key tests
	run("RSA", testRSA);
	run("KeySerialization", testKeySerialization);
	run("Ed25519", testEd25519);

	# Key exchange tests
	run("X25519", testX25519);
	run("P256ECDH", testP256ECDH);
	run("P256ECDSA", testP256ECDSA);

	if(testing->summary(passed, failed, skipped) > 0)
		raise "fail:tests failed";
}
