implement SHA3Test;

#
# SHA-3 (FIPS 202) tests
#
# Tests SHA3-256 and SHA3-512 Keyring builtins with NIST CAVP
# Known Answer Test (KAT) vectors. Also exercises SHA-3 indirectly
# through ML-KEM round-trip (SHAKE-128/256 used internally).
#
# KAT vectors from NIST CAVP SHA-3 test suite:
#   https://csrc.nist.gov/projects/cryptographic-algorithm-validation-program
#

include "sys.m";
	sys: Sys;

include "draw.m";

include "keyring.m";
	kr: Keyring;

include "testing.m";
	testing: Testing;
	T: import testing;

SHA3Test: module
{
	init: fn(nil: ref Draw->Context, args: list of string);
};

passed := 0;
failed := 0;
skipped := 0;

SRCFILE: con "/tests/sha3_test.b";

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

# Parse hex string to byte array
hexdecode(s: string): array of byte
{
	if(len s % 2 != 0)
		return nil;
	n := len s / 2;
	buf := array [n] of byte;
	for(i := 0; i < n; i++) {
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

#
# SHA3-256 KAT: empty message
# NIST CAVP ShortMsg Len=0
# Expected: a7ffc6f8bf1ed76651c14756a061d662f580ff4de43b49fa82d80a4b80f8434a
#
testSHA3_256_Empty(t: ref T)
{
	msg := array [0] of byte;
	digest := array [kr->SHA3_256dlen] of byte;

	n := kr->sha3_256(msg, 0, digest);
	t.asserteq(n, kr->SHA3_256dlen, "sha3_256 returns digest length");

	expected := "a7ffc6f8bf1ed76651c14756a061d662f580ff4de43b49fa82d80a4b80f8434a";
	got := hexencode(digest);
	t.assertseq(got, expected, "SHA3-256 empty message");
}

#
# SHA3-256 KAT: 1-byte message 0xa3
# Verified against known-good implementation
#
testSHA3_256_OneByte(t: ref T)
{
	msg := hexdecode("a3");
	digest := array [kr->SHA3_256dlen] of byte;

	n := kr->sha3_256(msg, len msg, digest);
	t.asserteq(n, kr->SHA3_256dlen, "sha3_256 returns digest length");

	expected := "27eaf63d564f89f844e82622c8c00e2540776db96110333e7f039f625ff9d3fd";
	got := hexencode(digest);
	t.assertseq(got, expected, "SHA3-256 one byte 0xa3");
}

#
# SHA3-256 KAT: "abc" (3 bytes)
# NIST FIPS 202 example
# Expected: 3a985da74fe225b2045c172d6bd390bd855f086e3e9d525b46bfe24511431532
#
testSHA3_256_ABC(t: ref T)
{
	msg := array of byte "abc";
	digest := array [kr->SHA3_256dlen] of byte;

	n := kr->sha3_256(msg, len msg, digest);
	t.asserteq(n, kr->SHA3_256dlen, "sha3_256 returns digest length");

	expected := "3a985da74fe225b2045c172d6bd390bd855f086e3e9d525b46bfe24511431532";
	got := hexencode(digest);
	t.assertseq(got, expected, "SHA3-256 'abc'");
}

#
# SHA3-256 KAT: 200 repetitions of 0xa3
# NIST CAVP LongMsg Len=1600
# Expected: 79f38adec5c20307a98ef76e8324afbfd46cfd81b22e3973c65fa1bd9de31787
#
testSHA3_256_200xA3(t: ref T)
{
	msg := array [200] of byte;
	for(i := 0; i < 200; i++)
		msg[i] = byte 16ra3;
	digest := array [kr->SHA3_256dlen] of byte;

	n := kr->sha3_256(msg, len msg, digest);
	t.asserteq(n, kr->SHA3_256dlen, "sha3_256 returns digest length");

	expected := "79f38adec5c20307a98ef76e8324afbfd46cfd81b22e3973c65fa1bd9de31787";
	got := hexencode(digest);
	t.assertseq(got, expected, "SHA3-256 200 x 0xa3");
}

#
# SHA3-512 KAT: empty message
# NIST CAVP ShortMsg Len=0
# Expected: a69f73cca23a9ac5c8b567dc185a756e97c982164fe25859e0d1dcc1475c80a6
#          15b2123af1f5f94c11e3e9402c3ac558f500199d95b6d3e301758586281dcd26
#
testSHA3_512_Empty(t: ref T)
{
	msg := array [0] of byte;
	digest := array [kr->SHA3_512dlen] of byte;

	n := kr->sha3_512(msg, 0, digest);
	t.asserteq(n, kr->SHA3_512dlen, "sha3_512 returns digest length");

	expected := "a69f73cca23a9ac5c8b567dc185a756e97c982164fe25859e0d1dcc1475c80a6"
		+ "15b2123af1f5f94c11e3e9402c3ac558f500199d95b6d3e301758586281dcd26";
	got := hexencode(digest);
	t.assertseq(got, expected, "SHA3-512 empty message");
}

#
# SHA3-512 KAT: "abc" (3 bytes)
# NIST FIPS 202 example
# Expected: b751850b1a57168a5693cd924b6b096e08f621827444f70d884f5d0240d2712e
#          10e116e9192af3c91a7ec57647e3934057340b4cf408d5a56592f8274eec53f0
#
testSHA3_512_ABC(t: ref T)
{
	msg := array of byte "abc";
	digest := array [kr->SHA3_512dlen] of byte;

	n := kr->sha3_512(msg, len msg, digest);
	t.asserteq(n, kr->SHA3_512dlen, "sha3_512 returns digest length");

	expected := "b751850b1a57168a5693cd924b6b096e08f621827444f70d884f5d0240d2712e"
		+ "10e116e9192af3c91a7ec57647e3934057340b4cf408d5a56592f8274eec53f0";
	got := hexencode(digest);
	t.assertseq(got, expected, "SHA3-512 'abc'");
}

#
# SHA3-512 KAT: 1-byte message 0xa3
# Verified against known-good implementation
#
testSHA3_512_OneByte(t: ref T)
{
	msg := hexdecode("a3");
	digest := array [kr->SHA3_512dlen] of byte;

	n := kr->sha3_512(msg, len msg, digest);
	t.asserteq(n, kr->SHA3_512dlen, "sha3_512 returns digest length");

	expected := "d944fd00e0336ab8842e7ded54ace669858d75d8e2d1245f5bf1f23473f1db7a"
		+ "cb4d6a187e2ea133eb17c7b076e4c26d5e7edbc4d593df17ea1b3590a86e88a9";
	got := hexencode(digest);
	t.assertseq(got, expected, "SHA3-512 one byte 0xa3");
}

#
# SHA3-512 KAT: 200 repetitions of 0xa3
# NIST CAVP LongMsg Len=1600
# Expected: e76dfad22084a8b1467fcf2ffa58361bec7628edf5f3fdc0e4805dc48caeeca8
#          1b7c13c30adf52a3659584739a2df46be589c51ca1a4a8416df6545a1ce8ba00
#
testSHA3_512_200xA3(t: ref T)
{
	msg := array [200] of byte;
	for(i := 0; i < 200; i++)
		msg[i] = byte 16ra3;
	digest := array [kr->SHA3_512dlen] of byte;

	n := kr->sha3_512(msg, len msg, digest);
	t.asserteq(n, kr->SHA3_512dlen, "sha3_512 returns digest length");

	expected := "e76dfad22084a8b1467fcf2ffa58361bec7628edf5f3fdc0e4805dc48caeeca8"
		+ "1b7c13c30adf52a3659584739a2df46be589c51ca1a4a8416df6545a1ce8ba00";
	got := hexencode(digest);
	t.assertseq(got, expected, "SHA3-512 200 x 0xa3");
}

#
# SHA3-256 determinism: same input produces same output
#
testSHA3_256_Determinism(t: ref T)
{
	msg := array of byte "determinism check for SHA3-256";
	d1 := array [kr->SHA3_256dlen] of byte;
	d2 := array [kr->SHA3_256dlen] of byte;

	kr->sha3_256(msg, len msg, d1);
	kr->sha3_256(msg, len msg, d2);

	t.assertseq(hexencode(d1), hexencode(d2), "SHA3-256 deterministic");
}

#
# SHA3-512 determinism: same input produces same output
#
testSHA3_512_Determinism(t: ref T)
{
	msg := array of byte "determinism check for SHA3-512";
	d1 := array [kr->SHA3_512dlen] of byte;
	d2 := array [kr->SHA3_512dlen] of byte;

	kr->sha3_512(msg, len msg, d1);
	kr->sha3_512(msg, len msg, d2);

	t.assertseq(hexencode(d1), hexencode(d2), "SHA3-512 deterministic");
}

#
# SHA3-256 vs SHA3-512: different outputs for same input
#
testSHA3_CrossCheck(t: ref T)
{
	msg := array of byte "cross-check";
	d256 := array [kr->SHA3_256dlen] of byte;
	d512 := array [kr->SHA3_512dlen] of byte;

	kr->sha3_256(msg, len msg, d256);
	kr->sha3_512(msg, len msg, d512);

	# First 32 bytes of SHA3-512 must differ from SHA3-256
	# (they use different capacities: c=512 vs c=1024)
	match := 1;
	for(i := 0; i < kr->SHA3_256dlen; i++) {
		if(d256[i] != d512[i]) {
			match = 0;
			break;
		}
	}
	t.assert(match == 0, "SHA3-256 and SHA3-512 produce different digests");
}

#
# SHA3 partial length: n < len buf
#
testSHA3_PartialLen(t: ref T)
{
	# Hash only first 3 bytes of a longer buffer
	buf := array of byte "abcdefgh";
	digest := array [kr->SHA3_256dlen] of byte;

	kr->sha3_256(buf, 3, digest);

	# Should equal SHA3-256("abc")
	expected := "3a985da74fe225b2045c172d6bd390bd855f086e3e9d525b46bfe24511431532";
	got := hexencode(digest);
	t.assertseq(got, expected, "SHA3-256 partial n=3 equals hash of 'abc'");
}

#
# SHA-3 exercised via ML-KEM round-trip (SHAKE-128/256 used internally)
#
testSHA3viaMlkem(t: ref T)
{
	t.log("Testing SHA-3 via ML-KEM-768 round-trip (SHAKE-128/256 used internally)");

	(pk, sk) := kr->mlkem768_keygen();
	t.assert(pk != nil, "ML-KEM-768 keygen produced pk");
	t.assert(sk != nil, "ML-KEM-768 keygen produced sk");

	(ct, ss1) := kr->mlkem768_encaps(pk);
	t.assert(ct != nil, "encaps produced ciphertext");
	t.assert(ss1 != nil, "encaps produced shared secret");

	ss2 := kr->mlkem768_decaps(sk, ct);
	t.assert(ss2 != nil, "decaps produced shared secret");

	match := 1;
	for(i := 0; i < len ss1; i++)
		if(ss1[i] != ss2[i])
			match = 0;
	t.assert(match, "encaps/decaps shared secrets match (SHA-3 consistent)");
}

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
		sys->fprint(sys->fildes(2), "cannot load testing module: %r\n");
		raise "fail:cannot load testing";
	}

	testing->init();

	for(a := args; a != nil; a = tl a) {
		if(hd a == "-v")
			testing->verbose(1);
	}

	sys->fprint(sys->fildes(1), "\n=== SHA-3 (FIPS 202) Tests ===\n\n");

	# SHA3-256 KAT vectors
	run("SHA3-256/empty", testSHA3_256_Empty);
	run("SHA3-256/one-byte", testSHA3_256_OneByte);
	run("SHA3-256/abc", testSHA3_256_ABC);
	run("SHA3-256/200xA3", testSHA3_256_200xA3);

	# SHA3-512 KAT vectors
	run("SHA3-512/empty", testSHA3_512_Empty);
	run("SHA3-512/abc", testSHA3_512_ABC);
	run("SHA3-512/one-byte", testSHA3_512_OneByte);
	run("SHA3-512/200xA3", testSHA3_512_200xA3);

	# Behavioral tests
	run("SHA3-256/determinism", testSHA3_256_Determinism);
	run("SHA3-512/determinism", testSHA3_512_Determinism);
	run("SHA3/cross-check", testSHA3_CrossCheck);
	run("SHA3-256/partial-len", testSHA3_PartialLen);

	# Indirect via ML-KEM
	run("SHA3-via-MLKEM", testSHA3viaMlkem);

	if(testing->summary(passed, failed, skipped) > 0)
		raise "fail:tests failed";
}
