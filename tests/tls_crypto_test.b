implement TLSCryptoTest;

#
# Tests for TLS crypto primitives against RFC/NIST test vectors:
#   - HMAC-SHA256/384/512 (RFC 4231)
#   - AES-GCM (NIST SP 800-38D)
#   - ChaCha20-Poly1305 (RFC 8439)
#   - X25519 (RFC 7748)
#   - P-256 ECDH (NIST CAVP KAS ECC CDH PrimitiveTest)
#   - P-256 ECDSA (RFC 6979 appendix A.2.5)
#   - P-384 ECDSA (RFC 6979 appendix A.2.6)
#

include "sys.m";
	sys: Sys;

include "draw.m";

include "keyring.m";
	kr: Keyring;

include "testing.m";
	testing: Testing;
	T: import testing;

TLSCryptoTest: module
{
	init: fn(nil: ref Draw->Context, args: list of string);
};

passed := 0;
failed := 0;
skipped := 0;

SRCFILE: con "/tests/tls_crypto_test.b";

run(name: string, testfn: ref fn(t: ref T))
{
	t := testing->newTsrc(name, SRCFILE);
	{
		testfn(t);
	} exception e {
	"fail:fatal" =>
		;
	"fail:skip" =>
		;
	"*" =>
		t.failed = 1;
		t.log("unexpected exception: " + e);
	}

	if(testing->done(t))
		passed++;
	else if(t.skipped)
		skipped++;
	else
		failed++;
}

# Convert hex string to byte array
hexdecode(s: string): array of byte
{
	if(len s % 2 != 0)
		return nil;
	buf := array[len s / 2] of byte;
	for(i := 0; i < len buf; i++) {
		hi := hexval(s[2*i]);
		lo := hexval(s[2*i+1]);
		if(hi < 0 || lo < 0)
			return nil;
		buf[i] = byte (hi * 16 + lo);
	}
	return buf;
}

hexval(c: int): int
{
	if(c >= '0' && c <= '9')
		return c - '0';
	if(c >= 'a' && c <= 'f')
		return c - 'a' + 10;
	if(c >= 'A' && c <= 'F')
		return c - 'A' + 10;
	return -1;
}

# Convert byte array to hex string
hexencode(buf: array of byte): string
{
	if(buf == nil)
		return "nil";
	s := "";
	for(i := 0; i < len buf; i++)
		s += sys->sprint("%02x", int buf[i]);
	return s;
}

# Compare two byte arrays
byteseq(a, b: array of byte): int
{
	if(a == nil && b == nil)
		return 1;
	if(a == nil || b == nil)
		return 0;
	if(len a != len b)
		return 0;
	for(i := 0; i < len a; i++)
		if(a[i] != b[i])
			return 0;
	return 1;
}

# Assert byte arrays equal, showing hex on failure
assertbytes(t: ref T, got, want: array of byte, msg: string)
{
	if(!byteseq(got, want)) {
		ghex := hexencode(got);
		whex := hexencode(want);
		if(len ghex > 80)
			ghex = ghex[0:80] + "...";
		if(len whex > 80)
			whex = whex[0:80] + "...";
		t.error(sys->sprint("%s:\n  got  %s\n  want %s", msg, ghex, whex));
	}
}

# Make array of n copies of byte b
makebytes(n: int, b: byte): array of byte
{
	buf := array[n] of byte;
	for(i := 0; i < n; i++)
		buf[i] = b;
	return buf;
}

# ============================================================
# HMAC-SHA256 tests (RFC 4231)
# ============================================================

testHMACSHA256(t: ref T)
{
	t.log("Testing HMAC-SHA256 against RFC 4231...");

	# Test Case 1: 20-byte key
	key1 := makebytes(20, byte 16r0b);
	data1 := array of byte "Hi There";
	want1 := hexdecode("b0344c61d8db38535ca8afceaf0bf12b"
		+ "881dc200c9833da726e9376c2e32cff7");
	digest1 := array[kr->SHA256dlen] of byte;
	kr->hmac_sha256(data1, len data1, key1, digest1, nil);
	assertbytes(t, digest1, want1, "HMAC-SHA256 TC1");

	# Test Case 2: short key "Jefe"
	key2 := array of byte "Jefe";
	data2 := array of byte "what do ya want for nothing?";
	want2 := hexdecode("5bdcc146bf60754e6a042426089575c7"
		+ "5a003f089d2739839dec58b964ec3843");
	digest2 := array[kr->SHA256dlen] of byte;
	kr->hmac_sha256(data2, len data2, key2, digest2, nil);
	assertbytes(t, digest2, want2, "HMAC-SHA256 TC2");

	# Test Case 6: key longer than block size (131 bytes > 64-byte block)
	# This tests the key-hashing path we fixed in hmac.c
	key6 := makebytes(131, byte 16raa);
	data6 := array of byte "Test Using Larger Than Block-Size Key - Hash Key First";
	want6 := hexdecode("60e431591ee0b67f0d8a26aacbf5b77f"
		+ "8e0bc6213728c5140546040f0ee37f54");
	digest6 := array[kr->SHA256dlen] of byte;
	kr->hmac_sha256(data6, len data6, key6, digest6, nil);
	assertbytes(t, digest6, want6, "HMAC-SHA256 TC6 (long key)");
}

# ============================================================
# HMAC-SHA384 tests (RFC 4231)
# ============================================================

testHMACSHA384(t: ref T)
{
	t.log("Testing HMAC-SHA384 against RFC 4231...");

	# Test Case 2
	key2 := array of byte "Jefe";
	data2 := array of byte "what do ya want for nothing?";
	want2 := hexdecode("af45d2e376484031617f78d2b58a6b1b"
		+ "9c7ef464f5a01b47e42ec3736322445e"
		+ "8e2240ca5e69e2c78b3239ecfab21649");
	digest2 := array[kr->SHA384dlen] of byte;
	kr->hmac_sha384(data2, len data2, key2, digest2, nil);
	assertbytes(t, digest2, want2, "HMAC-SHA384 TC2");

	# Test Case 6: key longer than block size (131 > 128-byte block for SHA-384)
	key6 := makebytes(131, byte 16raa);
	data6 := array of byte "Test Using Larger Than Block-Size Key - Hash Key First";
	want6 := hexdecode("4ece084485813e9088d2c63a041bc5b4"
		+ "4f9ef1012a2b588f3cd11f05033ac4c6"
		+ "0c2ef6ab4030fe8296248df163f44952");
	digest6 := array[kr->SHA384dlen] of byte;
	kr->hmac_sha384(data6, len data6, key6, digest6, nil);
	assertbytes(t, digest6, want6, "HMAC-SHA384 TC6 (long key)");
}

# ============================================================
# HMAC-SHA512 tests (RFC 4231)
# ============================================================

testHMACSHA512(t: ref T)
{
	t.log("Testing HMAC-SHA512 against RFC 4231...");

	# Test Case 2
	key2 := array of byte "Jefe";
	data2 := array of byte "what do ya want for nothing?";
	want2 := hexdecode("164b7a7bfcf819e2e395fbe73b56e0a3"
		+ "87bd64222e831fd610270cd7ea250554"
		+ "9758bf75c05a994a6d034f65f8f0e6fd"
		+ "caeab1a34d4a6b4b636e070a38bce737");
	digest2 := array[kr->SHA512dlen] of byte;
	kr->hmac_sha512(data2, len data2, key2, digest2, nil);
	assertbytes(t, digest2, want2, "HMAC-SHA512 TC2");

	# Test Case 6: key longer than block size (131 > 128-byte block for SHA-512)
	key6 := makebytes(131, byte 16raa);
	data6 := array of byte "Test Using Larger Than Block-Size Key - Hash Key First";
	want6 := hexdecode("80b24263c7c1a3ebb71493c1dd7be8b4"
		+ "9b46d1f41b4aeec1121b013783f8f352"
		+ "6b56d037e05f2598bd0fd2215d6a1e52"
		+ "95e64f73f63f0aec8b915a985d786598");
	digest6 := array[kr->SHA512dlen] of byte;
	kr->hmac_sha512(data6, len data6, key6, digest6, nil);
	assertbytes(t, digest6, want6, "HMAC-SHA512 TC6 (long key)");
}

# ============================================================
# AES-128-GCM tests (NIST SP 800-38D)
# ============================================================

testAESGCMEmpty(t: ref T)
{
	t.log("Testing AES-GCM with empty plaintext (NIST TC1)...");

	key := hexdecode("00000000000000000000000000000000");
	iv := hexdecode("000000000000000000000000");
	empty := array[0] of byte;
	wanttag := hexdecode("58e2fccefa7e3061367f1d57a4e7455a");

	state := kr->aesgcmsetup(key, iv);
	if(state == nil) {
		t.fatal("aesgcmsetup returned nil");
		return;
	}

	(ct, tag) := kr->aesgcmencrypt(state, empty, empty);
	t.asserteq(len ct, 0, "AES-GCM TC1 ciphertext should be empty");
	assertbytes(t, tag, wanttag, "AES-GCM TC1 tag");

	# Verify decryption
	state2 := kr->aesgcmsetup(key, iv);
	pt := kr->aesgcmdecrypt(state2, empty, empty, wanttag);
	if(pt == nil)
		t.error("AES-GCM TC1 decrypt returned nil (auth failed)");
	else
		t.asserteq(len pt, 0, "AES-GCM TC1 decrypted plaintext should be empty");
}

testAESGCMZeros(t: ref T)
{
	t.log("Testing AES-GCM with zero plaintext (NIST TC2)...");

	key := hexdecode("00000000000000000000000000000000");
	iv := hexdecode("000000000000000000000000");
	pt := hexdecode("00000000000000000000000000000000");
	wantct := hexdecode("0388dace60b6a392f328c2b971b2fe78");
	wanttag := hexdecode("ab6e47d42cec13bdf53a67b21257bddf");

	state := kr->aesgcmsetup(key, iv);
	if(state == nil) {
		t.fatal("aesgcmsetup returned nil");
		return;
	}

	(ct, tag) := kr->aesgcmencrypt(state, pt, array[0] of byte);
	assertbytes(t, ct, wantct, "AES-GCM TC2 ciphertext");
	assertbytes(t, tag, wanttag, "AES-GCM TC2 tag");

	# Verify round-trip decryption
	state2 := kr->aesgcmsetup(key, iv);
	dec := kr->aesgcmdecrypt(state2, wantct, array[0] of byte, wanttag);
	assertbytes(t, dec, pt, "AES-GCM TC2 round-trip");
}

testAESGCMData(t: ref T)
{
	t.log("Testing AES-GCM with data (NIST TC3)...");

	key := hexdecode("feffe9928665731c6d6a8f9467308308");
	iv := hexdecode("cafebabefacedbaddecaf888");
	pt := hexdecode(
		"d9313225f88406e5a55909c5aff5269a"
		+ "86a7a9531534f7da2e4c303d8a318a72"
		+ "1c3c0c95956809532fcf0e2449a6b525"
		+ "b16aedf5aa0de657ba637b391aafd255");
	wantct := hexdecode(
		"42831ec2217774244b7221b784d0d49c"
		+ "e3aa212f2c02a4e035c17e2329aca12e"
		+ "21d514b25466931c7d8f6a5aac84aa05"
		+ "1ba30b396a0aac973d58e091473f5985");
	wanttag := hexdecode("4d5c2af327cd64a62cf35abd2ba6fab4");

	state := kr->aesgcmsetup(key, iv);
	if(state == nil) {
		t.fatal("aesgcmsetup returned nil");
		return;
	}

	(ct, tag) := kr->aesgcmencrypt(state, pt, array[0] of byte);
	assertbytes(t, ct, wantct, "AES-GCM TC3 ciphertext");
	assertbytes(t, tag, wanttag, "AES-GCM TC3 tag");
}

testAESGCMWithAAD(t: ref T)
{
	t.log("Testing AES-GCM with AAD (NIST TC4)...");

	key := hexdecode("feffe9928665731c6d6a8f9467308308");
	iv := hexdecode("cafebabefacedbaddecaf888");
	pt := hexdecode(
		"d9313225f88406e5a55909c5aff5269a"
		+ "86a7a9531534f7da2e4c303d8a318a72"
		+ "1c3c0c95956809532fcf0e2449a6b525"
		+ "b16aedf5aa0de657ba637b39");
	aad := hexdecode("feedfacedeadbeeffeedfacedeadbeefabaddad2");
	wantct := hexdecode(
		"42831ec2217774244b7221b784d0d49c"
		+ "e3aa212f2c02a4e035c17e2329aca12e"
		+ "21d514b25466931c7d8f6a5aac84aa05"
		+ "1ba30b396a0aac973d58e091");
	wanttag := hexdecode("5bc94fbc3221a5db94fae95ae7121a47");

	state := kr->aesgcmsetup(key, iv);
	if(state == nil) {
		t.fatal("aesgcmsetup returned nil");
		return;
	}

	(ct, tag) := kr->aesgcmencrypt(state, pt, aad);
	assertbytes(t, ct, wantct, "AES-GCM TC4 ciphertext");
	assertbytes(t, tag, wanttag, "AES-GCM TC4 tag");

	# Verify decryption with correct tag
	state2 := kr->aesgcmsetup(key, iv);
	dec := kr->aesgcmdecrypt(state2, wantct, aad, wanttag);
	assertbytes(t, dec, pt, "AES-GCM TC4 round-trip");

	# Verify decryption fails with wrong tag
	badtag := hexdecode("00000000000000000000000000000000");
	state3 := kr->aesgcmsetup(key, iv);
	bad := kr->aesgcmdecrypt(state3, wantct, aad, badtag);
	if(bad != nil)
		t.error("AES-GCM TC4 decrypt should fail with wrong tag");
}

# ============================================================
# ChaCha20-Poly1305 tests (RFC 8439 section 2.8.2)
# ============================================================

testCCPolyEncrypt(t: ref T)
{
	t.log("Testing ChaCha20-Poly1305 against RFC 8439 §2.8.2...");

	key := hexdecode(
		"808182838485868788898a8b8c8d8e8f"
		+ "909192939495969798999a9b9c9d9e9f");
	nonce := hexdecode("070000004041424344454647");
	aad := hexdecode("50515253c0c1c2c3c4c5c6c7");
	pt := array of byte "Ladies and Gentlemen of the class of '99: If I could offer you only one tip for the future, sunscreen would be it.";
	wantct := hexdecode(
		"d31a8d34648e60db7b86afbc53ef7ec2"
		+ "a4aded51296e08fea9e2b5a736ee62d6"
		+ "3dbea45e8ca9671282fafb69da92728b"
		+ "1a71de0a9e060b2905d6a5b67ecd3b36"
		+ "92ddbd7f2d778b8c9803aee328091b58"
		+ "fab324e4fad675945585808b4831d7bc"
		+ "3ff4def08e4b7a9de576d26586cec64b"
		+ "6116");
	wanttag := hexdecode("1ae10b594f09e26a7e902ecbd0600691");

	(ct, tag) := kr->ccpolyencrypt(pt, aad, key, nonce);
	assertbytes(t, ct, wantct, "CC20P1305 ciphertext");
	assertbytes(t, tag, wanttag, "CC20P1305 tag");
}

testCCPolyDecrypt(t: ref T)
{
	t.log("Testing ChaCha20-Poly1305 decryption...");

	key := hexdecode(
		"808182838485868788898a8b8c8d8e8f"
		+ "909192939495969798999a9b9c9d9e9f");
	nonce := hexdecode("070000004041424344454647");
	aad := hexdecode("50515253c0c1c2c3c4c5c6c7");
	ct := hexdecode(
		"d31a8d34648e60db7b86afbc53ef7ec2"
		+ "a4aded51296e08fea9e2b5a736ee62d6"
		+ "3dbea45e8ca9671282fafb69da92728b"
		+ "1a71de0a9e060b2905d6a5b67ecd3b36"
		+ "92ddbd7f2d778b8c9803aee328091b58"
		+ "fab324e4fad675945585808b4831d7bc"
		+ "3ff4def08e4b7a9de576d26586cec64b"
		+ "6116");
	tag := hexdecode("1ae10b594f09e26a7e902ecbd0600691");
	wantpt := array of byte "Ladies and Gentlemen of the class of '99: If I could offer you only one tip for the future, sunscreen would be it.";

	pt := kr->ccpolydecrypt(ct, aad, tag, key, nonce);
	assertbytes(t, pt, wantpt, "CC20P1305 decrypt");

	# Verify decryption fails with wrong tag
	badtag := hexdecode("00000000000000000000000000000000");
	bad := kr->ccpolydecrypt(ct, aad, badtag, key, nonce);
	if(bad != nil)
		t.error("CC20P1305 decrypt should fail with wrong tag");
}

# ============================================================
# X25519 tests (RFC 7748 section 6.1)
# ============================================================

testX25519(t: ref T)
{
	t.log("Testing X25519 against RFC 7748 §6.1...");

	# Alice's keys
	alice_priv := hexdecode(
		"77076d0a7318a57d3c16c17251b26645"
		+ "df4c2f87ebc0992ab177fba51db92c2a");
	alice_pub_want := hexdecode(
		"8520f0098930a754748b7ddcb43ef75a"
		+ "0dbf3a0d26381af4eba4a98eaa9b4e6a");

	# Bob's keys
	bob_priv := hexdecode(
		"5dab087e624a8a4b79e17f8b83800ee6"
		+ "6f3bb1292618b6fd1c2f8b27ff88e0eb");
	bob_pub_want := hexdecode(
		"de9edb7d7b7dc1b4d35b61c2ece43537"
		+ "3f8343c85b78674dadfc7e146f882b4f");

	# Shared secret
	shared_want := hexdecode(
		"4a5d9d5ba4ce2de1728e3bf480350f25"
		+ "e07e21c947d19e3376f09b3c1e161742");

	# Test x25519_base: scalar * basepoint
	alice_pub := kr->x25519_base(alice_priv);
	if(alice_pub == nil) {
		t.fatal("x25519_base returned nil for Alice");
		return;
	}
	assertbytes(t, alice_pub, alice_pub_want, "Alice public key");

	bob_pub := kr->x25519_base(bob_priv);
	if(bob_pub == nil) {
		t.fatal("x25519_base returned nil for Bob");
		return;
	}
	assertbytes(t, bob_pub, bob_pub_want, "Bob public key");

	# Test x25519: ECDH shared secret
	shared_ab := kr->x25519(alice_priv, bob_pub_want);
	if(shared_ab == nil) {
		t.fatal("x25519(alice, bob) returned nil");
		return;
	}
	assertbytes(t, shared_ab, shared_want, "shared secret (Alice*Bob)");

	shared_ba := kr->x25519(bob_priv, alice_pub_want);
	if(shared_ba == nil) {
		t.fatal("x25519(bob, alice) returned nil");
		return;
	}
	assertbytes(t, shared_ba, shared_want, "shared secret (Bob*Alice)");

	# Both sides should agree
	assertbytes(t, shared_ab, shared_ba, "ECDH commutativity");
}

# ============================================================
# P-256 ECDH tests (NIST CAVP KAS ECC CDH PrimitiveTest)
# ============================================================

testP256ECDHVector0(t: ref T)
{
	t.log("Testing P-256 ECDH against NIST CAVP vector 0...");

	# Peer public key (QCAVSx, QCAVSy)
	peer_pub := hexdecode("04"
		+ "700c48f77f56584c5cc632ca65640db91b6bacce3a4df6b42ce7cc838833d287"
		+ "db71e509e3fd9b060ddb20ba5c51dcc5948d46fbf640dfe0441782cab85fa4ac");
	peer := kr->p256_make_point(peer_pub);
	if(peer == nil) {
		t.fatal("p256_make_point failed for peer");
		return;
	}

	# Our private key (dIUT)
	priv := hexdecode("7d7dc5f71eb29ddaf80d6214632eeae03d9058af1fb6d22ed80badb62bc1a534");

	# Expected shared secret (ZIUT = x-coordinate of dIUT * QCAVS)
	want := hexdecode("46fc62106420ff012e54a434fbdd2d25ccc5852060561e68040dd7778997bd7b");

	shared := kr->p256_ecdh(priv, peer);
	if(shared == nil) {
		t.fatal("p256_ecdh returned nil");
		return;
	}
	assertbytes(t, shared, want, "NIST CAVP P-256 ECDH vector 0");
}

testP256ECDHVector1(t: ref T)
{
	t.log("Testing P-256 ECDH against NIST CAVP vector 1...");

	peer_pub := hexdecode("04"
		+ "809f04289c64348c01515eb03d5ce7ac1a8cb9498f5caa50197e58d43a86a7ae"
		+ "b29d84e811197f25eba8f5194092cb6ff440e26d4421011372461f579271cda3");
	peer := kr->p256_make_point(peer_pub);
	if(peer == nil) {
		t.fatal("p256_make_point failed for peer");
		return;
	}

	priv := hexdecode("38f65d6dce47676044d58ce5139582d568f64bb16098d179dbab07741dd5caf5");
	want := hexdecode("057d636096cb80b67a8c038c890e887d1adfa4195e9b3ce241c8a778c59cda67");

	shared := kr->p256_ecdh(priv, peer);
	if(shared == nil) {
		t.fatal("p256_ecdh returned nil");
		return;
	}
	assertbytes(t, shared, want, "NIST CAVP P-256 ECDH vector 1");
}

testP256ECDHVector2(t: ref T)
{
	t.log("Testing P-256 ECDH against NIST CAVP vector 2...");

	peer_pub := hexdecode("04"
		+ "a2339c12d4a03c33546de533268b4ad667debf458b464d77443636440ee7fec3"
		+ "ef48a3ab26e20220bcda2c1851076839dae88eae962869a497bf73cb66faf536");
	peer := kr->p256_make_point(peer_pub);
	if(peer == nil) {
		t.fatal("p256_make_point failed for peer");
		return;
	}

	priv := hexdecode("1accfaf1b97712b85a6f54b148985a1bdc4c9bec0bd258cad4b3d603f49f32c8");
	want := hexdecode("2d457b78b4614132477618a5b077965ec90730a8c81a1c75d6d4ec68005d67ec");

	shared := kr->p256_ecdh(priv, peer);
	if(shared == nil) {
		t.fatal("p256_ecdh returned nil");
		return;
	}
	assertbytes(t, shared, want, "NIST CAVP P-256 ECDH vector 2");
}

# ============================================================
# P-256 ECDSA tests (RFC 6979 appendix A.2.5)
# ============================================================

# RFC 6979 P-256 key:
#   d  = C9AFA9D845BA75166B5C215767B1D6934E50C3DB36E89B127B8A622B120F6721
#   Qx = 60FED4BA255A9D31C961EB74C6356D68C049B8923B61FA6CE669622E60F29FB6
#   Qy = 7903FE1008B8BC99A41AE9E95628BC64F2F1B20C2D7E9F5177A3C294D4462299

testP256ECDSAVerifySample(t: ref T)
{
	t.log("Testing P-256 ECDSA verify: RFC 6979 message 'sample'...");

	pub_raw := hexdecode("04"
		+ "60fed4ba255a9d31c961eb74c6356d68c049b8923b61fa6ce669622e60f29fb6"
		+ "7903fe1008b8bc99a41ae9e95628bc64f2f1b20c2d7e9f5177a3c294d4462299");
	pub := kr->p256_make_point(pub_raw);
	if(pub == nil) {
		t.fatal("p256_make_point failed");
		return;
	}

	# SHA-256("sample") = af2bdbe1aa9b6ec1e2ade1d694f41fc71a831d0268e9891562113d8a62add1bf
	hash := hexdecode("af2bdbe1aa9b6ec1e2ade1d694f41fc71a831d0268e9891562113d8a62add1bf");

	# Known signature (r || s) from RFC 6979 A.2.5 with SHA-256
	sig := hexdecode(
		"efd48b2aacb6a8fd1140dd9cd45e81d69d2c877b56aaf991c34d0ea84eaf3716"
		+ "f7cb1c942d657c41d436c7a1b6e29f65f3e900dbb9aff4064dc4ab2f843acda8");

	result := kr->p256_ecdsa_verify(pub, hash, sig);
	t.assert(result == 1, "RFC 6979 'sample' signature verifies");
}

testP256ECDSAVerifyTest(t: ref T)
{
	t.log("Testing P-256 ECDSA verify: RFC 6979 message 'test'...");

	pub_raw := hexdecode("04"
		+ "60fed4ba255a9d31c961eb74c6356d68c049b8923b61fa6ce669622e60f29fb6"
		+ "7903fe1008b8bc99a41ae9e95628bc64f2f1b20c2d7e9f5177a3c294d4462299");
	pub := kr->p256_make_point(pub_raw);
	if(pub == nil) {
		t.fatal("p256_make_point failed");
		return;
	}

	# SHA-256("test") = 9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08
	hash := hexdecode("9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08");

	# Known signature (r || s) from RFC 6979 A.2.5 with SHA-256
	sig := hexdecode(
		"f1abb023518351cd71d881567b1ea663ed3efcf6c5132b354f28d3b0b7d38367"
		+ "019f4113742a2b14bd25926b49c649155f267e60d3814b4c0cc84250e46f0083");

	result := kr->p256_ecdsa_verify(pub, hash, sig);
	t.assert(result == 1, "RFC 6979 'test' signature verifies");
}

testP256ECDSAReject(t: ref T)
{
	t.log("Testing P-256 ECDSA rejection of invalid signatures...");

	pub_raw := hexdecode("04"
		+ "60fed4ba255a9d31c961eb74c6356d68c049b8923b61fa6ce669622e60f29fb6"
		+ "7903fe1008b8bc99a41ae9e95628bc64f2f1b20c2d7e9f5177a3c294d4462299");
	pub := kr->p256_make_point(pub_raw);
	if(pub == nil) {
		t.fatal("p256_make_point failed");
		return;
	}

	hash := hexdecode("af2bdbe1aa9b6ec1e2ade1d694f41fc71a831d0268e9891562113d8a62add1bf");
	sig := hexdecode(
		"efd48b2aacb6a8fd1140dd9cd45e81d69d2c877b56aaf991c34d0ea84eaf3716"
		+ "f7cb1c942d657c41d436c7a1b6e29f65f3e900dbb9aff4064dc4ab2f843acda8");

	# Flipped bit in hash
	badhash := array[32] of byte;
	badhash[0:] = hash;
	badhash[0] ^= byte 16r01;
	t.assert(kr->p256_ecdsa_verify(pub, badhash, sig) == 0, "rejects modified hash");

	# Flipped bit in r
	badsig := array[64] of byte;
	badsig[0:] = sig;
	badsig[0] ^= byte 16r01;
	t.assert(kr->p256_ecdsa_verify(pub, hash, badsig) == 0, "rejects modified r");

	# Flipped bit in s
	badsig[0:] = sig;
	badsig[32] ^= byte 16r01;
	t.assert(kr->p256_ecdsa_verify(pub, hash, badsig) == 0, "rejects modified s");

	# Wrong public key
	wrong_pub_raw := hexdecode("04"
		+ "700c48f77f56584c5cc632ca65640db91b6bacce3a4df6b42ce7cc838833d287"
		+ "db71e509e3fd9b060ddb20ba5c51dcc5948d46fbf640dfe0441782cab85fa4ac");
	wrong_pub := kr->p256_make_point(wrong_pub_raw);
	if(wrong_pub != nil)
		t.assert(kr->p256_ecdsa_verify(wrong_pub, hash, sig) == 0, "rejects wrong public key");
}

testP256ECDSASignVerify(t: ref T)
{
	t.log("Testing P-256 ECDSA sign/verify round-trip...");

	(priv, pub) := kr->p256_keygen();
	if(priv == nil || pub == nil) {
		t.fatal("keygen failed");
		return;
	}

	hash := hexdecode("af2bdbe1aa9b6ec1e2ade1d694f41fc71a831d0268e9891562113d8a62add1bf");
	sig := kr->p256_ecdsa_sign(priv, hash);
	if(sig == nil) {
		t.fatal("p256_ecdsa_sign returned nil");
		return;
	}
	t.assert(len sig == 64, "signature is 64 bytes (r||s)");
	t.assert(kr->p256_ecdsa_verify(pub, hash, sig) == 1, "own signature verifies");
}

# ============================================================
# P-384 ECDSA tests (RFC 6979 appendix A.2.6)
# ============================================================

# RFC 6979 P-384 key:
#   d  = 6B9D3DAD2E1B8C1C05B19875B6659F4DE23C3B667BF297BA9AA47740787137D8
#         96D5724E4C70A825F872C9EA60D2EDF5
#   Qx = EC3A4E415B4E19A4568618029F427FA5DA9A8BC4AE92E02E06AAE5286B300C64
#         DEF8F0EA9055866064A254515480BC13
#   Qy = 8015D9B72D7D57244EA8EF9AC0C621896708A59367F9DFB9F54CA84B3F1C9DB1
#         288B231C3AE0D4FE7344FD2533264720

testP384ECDSAVerifySample(t: ref T)
{
	t.log("Testing P-384 ECDSA verify: RFC 6979 message 'sample'...");

	# Uncompressed point: 04 || Qx[48] || Qy[48]
	pubkey := hexdecode("04"
		+ "ec3a4e415b4e19a4568618029f427fa5da9a8bc4ae92e02e06aae5286b300c64"
		+ "def8f0ea9055866064a254515480bc13"
		+ "8015d9b72d7d57244ea8ef9ac0c621896708a59367f9dfb9f54ca84b3f1c9db1"
		+ "288b231c3ae0d4fe7344fd2533264720");

	# SHA-384("sample")
	hash := hexdecode(
		"9a9083505bc92276aec4be312696ef7bf3bf603f4bbd381196a029f340585312"
		+ "313bca4a9b5b890efee42c77b1ee25fe");

	# Known signature (r[48] || s[48]) from RFC 6979 A.2.6 with SHA-384
	sig := hexdecode(
		"94edbb92a5ecb8aad4736e56c691916b3f88140666ce9fa73d64c4ea95ad133c"
		+ "81a648152e44acf96e36dd1e80fabe46"
		+ "99ef4aeb15f178cea1fe40db2603138f130e740a19624526203b6351d0a3a94f"
		+ "a329c145786e679e7b82c71a38628ac8");

	result := kr->p384_ecdsa_verify(pubkey, hash, sig);
	t.assert(result == 1, "RFC 6979 P-384 'sample' signature verifies");
}

testP384ECDSAVerifyTest(t: ref T)
{
	t.log("Testing P-384 ECDSA verify: RFC 6979 message 'test'...");

	pubkey := hexdecode("04"
		+ "ec3a4e415b4e19a4568618029f427fa5da9a8bc4ae92e02e06aae5286b300c64"
		+ "def8f0ea9055866064a254515480bc13"
		+ "8015d9b72d7d57244ea8ef9ac0c621896708a59367f9dfb9f54ca84b3f1c9db1"
		+ "288b231c3ae0d4fe7344fd2533264720");

	# SHA-384("test")
	hash := hexdecode(
		"768412320f7b0aa5812fce428dc4706b3cae50e02a64caa16a782249bfe8efc4"
		+ "b7ef1ccb126255d196047dfedf17a0a9");

	# Known signature (r[48] || s[48]) from RFC 6979 A.2.6 with SHA-384
	sig := hexdecode(
		"8203b63d3c853e8d77227fb377bcf7b7b772e97892a80f36ab775d509d7a5feb"
		+ "0542a7f0812998da8f1dd3ca3cf023db"
		+ "ddd0760448d42d8a43af45af836fce4de8be06b485e9b61b827c2f13173923e0"
		+ "6a739f040649a667bf3b828246baa5a5");

	result := kr->p384_ecdsa_verify(pubkey, hash, sig);
	t.assert(result == 1, "RFC 6979 P-384 'test' signature verifies");
}

testP384ECDSAReject(t: ref T)
{
	t.log("Testing P-384 ECDSA rejection of invalid signatures...");

	pubkey := hexdecode("04"
		+ "ec3a4e415b4e19a4568618029f427fa5da9a8bc4ae92e02e06aae5286b300c64"
		+ "def8f0ea9055866064a254515480bc13"
		+ "8015d9b72d7d57244ea8ef9ac0c621896708a59367f9dfb9f54ca84b3f1c9db1"
		+ "288b231c3ae0d4fe7344fd2533264720");

	hash := hexdecode(
		"9a9083505bc92276aec4be312696ef7bf3bf603f4bbd381196a029f340585312"
		+ "313bca4a9b5b890efee42c77b1ee25fe");

	sig := hexdecode(
		"94edbb92a5ecb8aad4736e56c691916b3f88140666ce9fa73d64c4ea95ad133c"
		+ "81a648152e44acf96e36dd1e80fabe46"
		+ "99ef4aeb15f178cea1fe40db2603138f130e740a19624526203b6351d0a3a94f"
		+ "a329c145786e679e7b82c71a38628ac8");

	# Flipped bit in hash
	badhash := array[48] of byte;
	badhash[0:] = hash;
	badhash[0] ^= byte 16r01;
	t.assert(kr->p384_ecdsa_verify(pubkey, badhash, sig) == 0, "rejects modified hash");

	# Flipped bit in r
	badsig := array[96] of byte;
	badsig[0:] = sig;
	badsig[0] ^= byte 16r01;
	t.assert(kr->p384_ecdsa_verify(pubkey, hash, badsig) == 0, "rejects modified r");

	# Flipped bit in s
	badsig[0:] = sig;
	badsig[48] ^= byte 16r01;
	t.assert(kr->p384_ecdsa_verify(pubkey, hash, badsig) == 0, "rejects modified s");

	# Wrong public key (different point on curve — use P-256 generator padded, which is NOT on P-384)
	wrong_pubkey := hexdecode("04"
		+ "6b17d1f2e12c4247f8bce6e563a440f277037d812deb33a0f4a13945d898c296"
		+ "000000000000000000000000000000000000000000000000"
		+ "4fe342e2fe1a7f9b8ee7eb4a7c0f9e162bce33576b315ececbb6406837bf51f5"
		+ "000000000000000000000000000000000000000000000000");
	t.assert(kr->p384_ecdsa_verify(wrong_pubkey, hash, sig) == 0, "rejects wrong public key");
}

# ============================================================
# P-256 ECDSA NIST CAVP SigVer tests
# ============================================================

testP256ECDSANist1(t: ref T)
{
	t.log("Testing P-256 ECDSA verify: NIST CAVP SigVer vector 1...");

	# NIST CAVP FIPS 186-3 SigVer.rsp [P-256,SHA-256]
	pub_raw := hexdecode("04"
		+ "e424dc61d4bb3cb7ef4344a7f8957a0c5134e16f7a67c074f82e6e12f49abf3c"
		+ "970eed7aa2bc48651545949de1dddaf0127e5965ac85d1243d6f60e7dfaee927");
	pub := kr->p256_make_point(pub_raw);
	if(pub == nil) {
		t.fatal("p256_make_point failed");
		return;
	}

	# SHA-256 hash of message
	hash := hexdecode("d1b8ef21eb4182ee270638061063a3f3c16c114e33937f69fb232cc833965a94");

	# Signature: r || s
	sig := hexdecode(
		"bf96b99aa49c705c910be33142017c642ff540c76349b9dab72f981fd9347f4f"
		+ "17c55095819089c2e03b9cd415abdf12444e323075d98f31920b9e0f57ec871c");

	result := kr->p256_ecdsa_verify(pub, hash, sig);
	t.assert(result == 1, "NIST CAVP P-256 SigVer vector 1");
}

testP256ECDSANist2(t: ref T)
{
	t.log("Testing P-256 ECDSA verify: Wycheproof tcId=3 vector...");

	# Wycheproof ecdsa_secp256r1_sha256_test.json, tcId=3
	pub_raw := hexdecode("04"
		+ "04aaec73635726f213fb8a9e64da3b8632e41495a944d0045b522eba7240fad5"
		+ "87d9315798aaa3a5ba01775787ced05eaaf7b4e09fc81d6d1aa546e8365d525d");
	pub := kr->p256_make_point(pub_raw);
	if(pub == nil) {
		t.fatal("p256_make_point failed");
		return;
	}

	# SHA-256("123400") = bb5a52f42f9c9261ed4361f59422a1e30036e7c32b270c8807a419feca605023
	hash := hexdecode("bb5a52f42f9c9261ed4361f59422a1e30036e7c32b270c8807a419feca605023");

	sig := hexdecode(
		"a8ea150cb80125d7381c4c1f1da8e9de2711f9917060406a73d7904519e51388"
		+ "f3ab9fa68bd47973a73b2d40480c2ba50c22c9d76ec217257288293285449b86");

	result := kr->p256_ecdsa_verify(pub, hash, sig);
	t.assert(result == 1, "Wycheproof P-256 tcId=3 signature verifies");
}

# ============================================================
# P-384 ECDSA NIST/Wycheproof SigVer tests
# ============================================================

testP384ECDSANist1(t: ref T)
{
	t.log("Testing P-384 ECDSA verify: Wycheproof tcId=3 vector...");

	# Wycheproof ecdsa_secp384r1_sha384_test.json, tcId=3
	pubkey := hexdecode("04"
		+ "29bdb76d5fa741bfd70233cb3a66cc7d44beb3b0663d92a8136650478bcefb61"
		+ "ef182e155a54345a5e8e5e88f064e5bc"
		+ "9a525ab7f764dad3dae1468c2b419f3b62b9ba917d5e8c4fb1ec47404a3fc764"
		+ "74b2713081be9db4c00e043ada9fc4a3");

	# SHA-384("123400")
	hash := hexdecode(
		"f9b127f0d81ebcd17b7ba0ea131c660d340b05ce557c82160e0f793de07d3817"
		+ "9023942871acb7002dfafdfffc8deace");

	# Signature: r[48] || s[48]
	sig := hexdecode(
		"234503fcca578121986d96be07fbc8da5d894ed8588c6dbcdbe974b4b813b21c"
		+ "52d20a8928f2e2fdac14705b0705498c"
		+ "cd7b9b766b97b53d1a80fc0b760af16a11bf4a59c7c367c6c7275dfb6e18a880"
		+ "91eed3734bf5cf41b3dc6fecd6d3baaf");

	result := kr->p384_ecdsa_verify(pubkey, hash, sig);
	t.assert(result == 1, "Wycheproof P-384 tcId=3 signature verifies");
}

testP384ECDSANist2(t: ref T)
{
	t.log("Testing P-384 ECDSA verify: Wycheproof tcId=4 vector...");

	# Wycheproof ecdsa_secp384r1_sha384_test.json, tcId=4 (message = 20 zero bytes)
	pubkey := hexdecode("04"
		+ "29bdb76d5fa741bfd70233cb3a66cc7d44beb3b0663d92a8136650478bcefb61"
		+ "ef182e155a54345a5e8e5e88f064e5bc"
		+ "9a525ab7f764dad3dae1468c2b419f3b62b9ba917d5e8c4fb1ec47404a3fc764"
		+ "74b2713081be9db4c00e043ada9fc4a3");

	# SHA-384(20 zero bytes)
	hash := hexdecode(
		"a5a2cb4f3870291de150e09ee864f3b2b3b342937ac719a149439185ad6a47bb"
		+ "4f23ae83ff20f0c8f0c79a1764244a63");

	# Signature: r[48] || s[48]
	sig := hexdecode(
		"5cad9ae1565f2588f86d821c2cc1b4d0fdf874331326568f5b0e130e4e0c0ec4"
		+ "97f8f5f564212bd2a26ecb782cf0a18d"
		+ "bf2e9d0980fbb00696673e7fbb03e1f854b9d7596b759a17bf6e6e67a95ea6c1"
		+ "664f82dc449ae5ea779abd99c78e6840");

	result := kr->p384_ecdsa_verify(pubkey, hash, sig);
	t.assert(result == 1, "Wycheproof P-384 tcId=4 signature verifies");
}

# ============================================================
# Main
# ============================================================

init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	kr = load Keyring Keyring->PATH;
	testing = load Testing Testing->PATH;

	if(kr == nil) {
		sys->fprint(sys->fildes(2), "cannot load Keyring: %r\n");
		raise "fail:cannot load Keyring";
	}

	if(testing == nil) {
		sys->fprint(sys->fildes(2), "cannot load Testing: %r\n");
		raise "fail:cannot load Testing";
	}

	testing->init();

	for(a := args; a != nil; a = tl a) {
		if(hd a == "-v")
			testing->verbose(1);
	}

	sys->fprint(sys->fildes(2), "\n=== TLS Crypto Primitive Tests ===\n\n");

	# HMAC tests
	run("HMAC/SHA256", testHMACSHA256);
	run("HMAC/SHA384", testHMACSHA384);
	run("HMAC/SHA512", testHMACSHA512);

	# AES-GCM tests
	run("AES-GCM/Empty", testAESGCMEmpty);
	run("AES-GCM/Zeros", testAESGCMZeros);
	run("AES-GCM/Data", testAESGCMData);
	run("AES-GCM/WithAAD", testAESGCMWithAAD);

	# ChaCha20-Poly1305 tests
	run("CCPoly/Encrypt", testCCPolyEncrypt);
	run("CCPoly/Decrypt", testCCPolyDecrypt);

	# X25519 tests
	run("X25519/RFC7748", testX25519);

	# P-256 ECDH tests (NIST CAVP)
	run("P256/ECDH/CAVP0", testP256ECDHVector0);
	run("P256/ECDH/CAVP1", testP256ECDHVector1);
	run("P256/ECDH/CAVP2", testP256ECDHVector2);

	# P-256 ECDSA tests (RFC 6979)
	run("P256/ECDSA/VerifySample", testP256ECDSAVerifySample);
	run("P256/ECDSA/VerifyTest", testP256ECDSAVerifyTest);
	run("P256/ECDSA/Reject", testP256ECDSAReject);
	run("P256/ECDSA/SignVerify", testP256ECDSASignVerify);

	# P-384 ECDSA tests (RFC 6979)
	run("P384/ECDSA/VerifySample", testP384ECDSAVerifySample);
	run("P384/ECDSA/VerifyTest", testP384ECDSAVerifyTest);
	run("P384/ECDSA/Reject", testP384ECDSAReject);

	# NIST/Wycheproof additional vectors
	run("P256/ECDSA/NIST1", testP256ECDSANist1);
	run("P256/ECDSA/NIST2", testP256ECDSANist2);
	run("P384/ECDSA/NIST1", testP384ECDSANist1);
	run("P384/ECDSA/NIST2", testP384ECDSANist2);

	if(testing->summary(passed, failed, skipped) > 0)
		raise "fail:tests failed";
}
