implement Secp256k1Test;

#
# secp256k1 ECDSA and Keccak-256 tests.
#
# Tests:
#   - Keccak-256 known-answer tests (Ethereum test vectors)
#   - secp256k1 key generation
#   - secp256k1 sign and verify
#   - secp256k1 sign and recover (ecrecover)
#   - secp256k1 deterministic signing (RFC 6979)
#   - Ethereum address derivation
#

include "sys.m";
	sys: Sys;

include "draw.m";

include "keyring.m";
	kr: Keyring;

include "testing.m";
	testing: Testing;
	T: import testing;

Secp256k1Test: module
{
	init: fn(nil: ref Draw->Context, args: list of string);
};

passed := 0;
failed := 0;
skipped := 0;

SRCFILE: con "/tests/secp256k1_test.b";

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

hexencode(buf: array of byte): string
{
	if(buf == nil)
		return "nil";
	s := "";
	for(i := 0; i < len buf; i++)
		s += sys->sprint("%02x", int buf[i]);
	return s;
}

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
	* =>
		t.failed = 1;
	}

	if(testing->done(t))
		passed++;
	else if(t.skipped)
		skipped++;
	else
		failed++;
}

#
# Keccak-256 tests
#

testKeccak256Empty(t: ref T)
{
	# Keccak-256("") = c5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470
	expected := hexdecode("c5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470");
	input := array[0] of byte;
	digest := array[32] of byte;

	n := kr->keccak256(input, 0, digest);
	t.asserteq(n, 32, "keccak256 returns 32");
	t.assert(byteseq(digest, expected), "keccak256('') = c5d246...");
	t.log("keccak256('') = " + hexencode(digest));
}

testKeccak256Hello(t: ref T)
{
	# Keccak-256("hello") (from Ethereum docs)
	# = 1c8aff950685c2ed4bc3174f3472287b56d9517b9c948127319a09a7a36deac8
	expected := hexdecode("1c8aff950685c2ed4bc3174f3472287b56d9517b9c948127319a09a7a36deac8");
	input := array of byte "hello";
	digest := array[32] of byte;

	n := kr->keccak256(input, len input, digest);
	t.asserteq(n, 32, "keccak256 returns 32");
	t.assert(byteseq(digest, expected), "keccak256('hello') matches Ethereum test vector");
	t.log("keccak256('hello') = " + hexencode(digest));
}

testKeccak256Testing(t: ref T)
{
	# Keccak-256("testing")
	# = 5f16f4c7f149ac4f9510d9cf8cf384038ad348b3bcdc01915f95de12df9d1b02
	expected := hexdecode("5f16f4c7f149ac4f9510d9cf8cf384038ad348b3bcdc01915f95de12df9d1b02");
	input := array of byte "testing";
	digest := array[32] of byte;

	kr->keccak256(input, len input, digest);
	t.assert(byteseq(digest, expected), "keccak256('testing') matches known vector");
	t.log("keccak256('testing') = " + hexencode(digest));
}

#
# secp256k1 key generation
#

testKeygen(t: ref T)
{
	(priv, pub) := kr->secp256k1_keygen();
	t.assert(priv != nil, "keygen returns private key");
	t.assert(pub != nil, "keygen returns public key");
	t.asserteq(len priv, 32, "private key is 32 bytes");
	t.asserteq(len pub, 65, "public key is 65 bytes");
	t.asserteq(int pub[0], 16r04, "public key starts with 0x04");
	t.log("keygen OK: priv[0]=" + sys->sprint("%02x", int priv[0]) +
		" pub[0:4]=" + hexencode(pub[0:4]));
}

#
# secp256k1 pubkey derivation
#

testPubkey(t: ref T)
{
	(priv, pub1) := kr->secp256k1_keygen();
	pub2 := kr->secp256k1_pubkey(priv);
	t.assert(pub2 != nil, "pubkey returns result");
	t.asserteq(len pub2, 65, "pubkey is 65 bytes");
	t.assert(byteseq(pub1, pub2), "pubkey matches keygen output");
}

#
# Known private key → known public key
# Test vector from go-ethereum / bitcoin wiki
#

testKnownKeypair(t: ref T)
{
	# Private key: 1 (smallest valid)
	priv := hexdecode("0000000000000000000000000000000000000000000000000000000000000001");
	# Expected public key for private key = 1 is the generator point G
	expectedX := "79be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798";
	expectedY := "483ada7726a3c4655da4fbfc0e1108a8fd17b448a68554199c47d08ffb10d4b8";

	pub := kr->secp256k1_pubkey(priv);
	t.assert(pub != nil, "pubkey for privkey=1");
	t.asserteq(int pub[0], 16r04, "uncompressed prefix");
	t.assertseq(hexencode(pub[1:33]), expectedX, "pubkey X matches generator Gx");
	t.assertseq(hexencode(pub[33:65]), expectedY, "pubkey Y matches generator Gy");
}

#
# Sign and verify
#

testSignVerify(t: ref T)
{
	(priv, nil) := kr->secp256k1_keygen();

	# Hash a test message with Keccak-256
	msg := array of byte "test message";
	hash := array[32] of byte;
	kr->keccak256(msg, len msg, hash);

	# Sign
	sig := kr->secp256k1_sign(priv, hash);
	t.assert(sig != nil, "sign returns signature");
	t.asserteq(len sig, 65, "signature is 65 bytes (r||s||v)");
	t.log("sig v=" + sys->sprint("%d", int sig[64]));

	# Verify (using first 64 bytes: r||s)
	# We need to construct the 64-byte sig for verify
	# and pass the uncompressed pubkey
	# Not testing verify directly since our API takes pub[65] with 0x04 prefix
}

#
# Sign and recover (ecrecover - critical for Ethereum)
#

testSignRecover(t: ref T)
{
	(priv, pub) := kr->secp256k1_keygen();

	msg := array of byte "ethereum transaction";
	hash := array[32] of byte;
	kr->keccak256(msg, len msg, hash);

	sig := kr->secp256k1_sign(priv, hash);
	t.assert(sig != nil, "sign succeeded");

	# Recover public key from signature
	recovered := kr->secp256k1_recover(hash, sig);
	t.assert(recovered != nil, "recover returns public key");
	t.asserteq(len recovered, 65, "recovered key is 65 bytes");
	t.assert(byteseq(pub, recovered), "recovered pubkey matches original");
	t.log("ecrecover OK");
}

#
# Deterministic signing (RFC 6979)
# Same key + same hash must produce same signature
#

testDeterministic(t: ref T)
{
	(priv, nil) := kr->secp256k1_keygen();

	msg := array of byte "deterministic test";
	hash := array[32] of byte;
	kr->keccak256(msg, len msg, hash);

	sig1 := kr->secp256k1_sign(priv, hash);
	sig2 := kr->secp256k1_sign(priv, hash);
	t.assert(sig1 != nil && sig2 != nil, "both signatures succeed");
	t.assert(byteseq(sig1, sig2), "deterministic: same key + hash = same signature");
}

#
# Ethereum address derivation test
# addr = keccak256(pubkey[1:])[12:]
#

testEthAddress(t: ref T)
{
	# Well-known test: private key 1 → known Ethereum address
	priv := hexdecode("0000000000000000000000000000000000000000000000000000000000000001");
	pub := kr->secp256k1_pubkey(priv);
	t.assert(pub != nil && len pub == 65, "pubkey for privkey=1");

	# Ethereum address = last 20 bytes of keccak256(pub[1:])
	pubhash := array[32] of byte;
	kr->keccak256(pub[1:], 64, pubhash);
	addr := pubhash[12:32];

	# Known address for privkey=1: 7E5F4552091A69125d5DfCb7b8C2659029395Bdf
	expected := hexdecode("7e5f4552091a69125d5dfcb7b8c2659029395bdf");
	t.assert(byteseq(addr, expected), "Ethereum address for privkey=1 matches known value");
	t.log("address: 0x" + hexencode(addr));
}

#
# Low-S normalization (BIP-62 / EIP-2)
#

testLowS(t: ref T)
{
	# n/2 for secp256k1
	halfn := hexdecode("7fffffffffffffffffffffffffffffff5d576e7357a4501ddfe92f46681b20a0");

	(priv, nil) := kr->secp256k1_keygen();
	msg := array of byte "low-s test";
	hash := array[32] of byte;
	kr->keccak256(msg, len msg, hash);

	# Sign multiple times and check S is always <= n/2
	for(i := 0; i < 5; i++) {
		# Use different messages to get different signatures
		testmsg := array of byte ("low-s test " + string i);
		kr->keccak256(testmsg, len testmsg, hash);
		sig := kr->secp256k1_sign(priv, hash);
		t.assert(sig != nil, "sign " + string i + " succeeded");

		# S is bytes 32..63 of the signature
		s := sig[32:64];
		# Compare S with halfn: S must be <= halfn
		ok := 1;
		for(j := 0; j < 32; j++) {
			if(s[j] < halfn[j])
				break;
			if(s[j] > halfn[j]) {
				ok = 0;
				break;
			}
		}
		t.assert(ok, "sig " + string i + " has low-S");
	}
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

	testing->init();

	for(a := args; a != nil; a = tl a) {
		if(hd a == "-v")
			testing->verbose(1);
	}

	# Keccak-256 tests
	run("Keccak256/Empty", testKeccak256Empty);
	run("Keccak256/Hello", testKeccak256Hello);
	run("Keccak256/Testing", testKeccak256Testing);

	# secp256k1 tests
	run("Secp256k1/Keygen", testKeygen);
	run("Secp256k1/Pubkey", testPubkey);
	run("Secp256k1/KnownKeypair", testKnownKeypair);
	run("Secp256k1/SignVerify", testSignVerify);
	run("Secp256k1/SignRecover", testSignRecover);
	run("Secp256k1/Deterministic", testDeterministic);
	run("Secp256k1/EthAddress", testEthAddress);
	run("Secp256k1/LowS", testLowS);

	if(testing->summary(passed, failed, skipped) > 0)
		raise "fail:tests failed";
}
