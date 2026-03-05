implement MLKEMTest;

#
# ML-KEM (FIPS 203) tests
#
# Tests ML-KEM-768 and ML-KEM-1024 key encapsulation:
#   - Key generation with size validation
#   - Encapsulation / decapsulation round-trip
#   - Shared secret agreement
#   - Wrong key implicit rejection
#   - Ciphertext tampering detection
#   - Key uniqueness across keygen calls
#   - ML-KEM-1024 negative tests
#   - Stress test (10 iterations)
#

include "sys.m";
	sys: Sys;

include "draw.m";

include "keyring.m";
	kr: Keyring;

include "testing.m";
	testing: Testing;
	T: import testing;

MLKEMTest: module
{
	init: fn(nil: ref Draw->Context, args: list of string);
};

passed := 0;
failed := 0;
skipped := 0;

SRCFILE: con "/tests/mlkem_test.b";

# Convert byte array to hex string (truncated)
hexencode(buf: array of byte, maxlen: int): string
{
	if(buf == nil)
		return "nil";
	s := "";
	n := len buf;
	if(n > maxlen)
		n = maxlen;
	for(i := 0; i < n; i++)
		s += sys->sprint("%02x", int buf[i]);
	if(len buf > maxlen)
		s += "...";
	return s;
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

# helper: compare byte arrays
bytescmp(a: array of byte, b: array of byte): int
{
	if(len a != len b)
		return 0;
	for(i := 0; i < len a; i++)
		if(a[i] != b[i])
			return 0;
	return 1;
}

#
# Test ML-KEM-768 key generation
#
testMLKEM768KeyGen(t: ref T)
{
	t.log("Testing ML-KEM-768 key generation...");

	(pk, sk) := kr->mlkem768_keygen();
	if(pk == nil) {
		t.fatal("mlkem768_keygen returned nil pk");
		return;
	}
	if(sk == nil) {
		t.fatal("mlkem768_keygen returned nil sk");
		return;
	}

	t.asserteq(len pk, 1184, "ML-KEM-768 public key length");
	t.asserteq(len sk, 2400, "ML-KEM-768 secret key length");
	t.log("pk=" + hexencode(pk, 16) + " sk=" + hexencode(sk, 16));
}

#
# Test ML-KEM-768 encaps/decaps round-trip
#
testMLKEM768Roundtrip(t: ref T)
{
	t.log("Testing ML-KEM-768 encaps/decaps round-trip...");

	(pk, sk) := kr->mlkem768_keygen();
	if(pk == nil || sk == nil) {
		t.fatal("keygen failed");
		return;
	}

	(ct, ss_enc) := kr->mlkem768_encaps(pk);
	if(ct == nil) {
		t.fatal("encaps returned nil ciphertext");
		return;
	}
	if(ss_enc == nil) {
		t.fatal("encaps returned nil shared secret");
		return;
	}

	t.asserteq(len ct, 1088, "ML-KEM-768 ciphertext length");
	t.asserteq(len ss_enc, 32, "ML-KEM-768 shared secret length");

	ss_dec := kr->mlkem768_decaps(sk, ct);
	if(ss_dec == nil) {
		t.fatal("decaps returned nil");
		return;
	}
	t.asserteq(len ss_dec, 32, "decaps shared secret length");

	t.assert(bytescmp(ss_enc, ss_dec), "encaps/decaps shared secrets agree");
	t.log("ss_enc=" + hexencode(ss_enc, 32));
	t.log("ss_dec=" + hexencode(ss_dec, 32));
}

#
# Test ML-KEM-768 wrong key rejection
#
testMLKEM768WrongKey(t: ref T)
{
	t.log("Testing ML-KEM-768 wrong key rejection...");

	(pk1, sk1) := kr->mlkem768_keygen();
	(nil, sk2) := kr->mlkem768_keygen();
	if(pk1 == nil || sk1 == nil || sk2 == nil) {
		t.fatal("keygen failed");
		return;
	}

	# Encaps with pk1
	(ct, ss_enc) := kr->mlkem768_encaps(pk1);
	if(ct == nil || ss_enc == nil) {
		t.fatal("encaps failed");
		return;
	}

	# Decaps with wrong sk (sk2) - should get implicit rejection (different ss)
	ss_wrong := kr->mlkem768_decaps(sk2, ct);
	if(ss_wrong == nil) {
		t.log("decaps with wrong key returned nil (acceptable)");
		return;
	}

	# With implicit rejection, we get a deterministic but wrong shared secret
	t.assert(!bytescmp(ss_enc, ss_wrong), "wrong key produces different shared secret (implicit rejection)");
}

#
# Test ML-KEM-768 ciphertext tampering
#
testMLKEM768CtTamper(t: ref T)
{
	t.log("Testing ML-KEM-768 ciphertext tampering...");

	(pk, sk) := kr->mlkem768_keygen();
	if(pk == nil || sk == nil) {
		t.fatal("keygen failed");
		return;
	}

	(ct, ss_enc) := kr->mlkem768_encaps(pk);
	if(ct == nil || ss_enc == nil) {
		t.fatal("encaps failed");
		return;
	}

	# Tamper with ciphertext: flip bits in several positions
	ct_tampered := array [len ct] of byte;
	ct_tampered[0:] = ct;
	ct_tampered[0] = ct_tampered[0] ^ byte 16rff;
	ct_tampered[len ct / 2] = ct_tampered[len ct / 2] ^ byte 16raa;
	ct_tampered[len ct - 1] = ct_tampered[len ct - 1] ^ byte 16r55;

	ss_tampered := kr->mlkem768_decaps(sk, ct_tampered);
	if(ss_tampered == nil) {
		t.log("decaps with tampered ct returned nil (acceptable)");
		return;
	}

	# Implicit rejection: tampered ct gives a deterministic but wrong ss
	t.assert(!bytescmp(ss_enc, ss_tampered), "tampered ciphertext produces different shared secret");
}

#
# Test ML-KEM-768 key uniqueness
#
testMLKEM768KeyUniqueness(t: ref T)
{
	t.log("Testing ML-KEM-768 key uniqueness...");

	(pk1, sk1) := kr->mlkem768_keygen();
	(pk2, sk2) := kr->mlkem768_keygen();
	if(pk1 == nil || pk2 == nil || sk1 == nil || sk2 == nil) {
		t.fatal("keygen failed");
		return;
	}

	t.assert(!bytescmp(pk1, pk2), "two keygen calls produce different public keys");
	t.assert(!bytescmp(sk1, sk2), "two keygen calls produce different secret keys");
}

#
# Test ML-KEM-768 shared secret uniqueness per encaps call
#
testMLKEM768SsUniqueness(t: ref T)
{
	t.log("Testing ML-KEM-768 encaps randomness...");

	(pk, sk) := kr->mlkem768_keygen();
	if(pk == nil || sk == nil) {
		t.fatal("keygen failed");
		return;
	}

	(ct1, ss1) := kr->mlkem768_encaps(pk);
	(ct2, ss2) := kr->mlkem768_encaps(pk);
	if(ct1 == nil || ct2 == nil || ss1 == nil || ss2 == nil) {
		t.fatal("encaps failed");
		return;
	}

	# Each encaps call uses fresh randomness -> different ct and ss
	t.assert(!bytescmp(ct1, ct2), "two encaps calls produce different ciphertexts");
	t.assert(!bytescmp(ss1, ss2), "two encaps calls produce different shared secrets");

	# Both must still decaps correctly
	ss1d := kr->mlkem768_decaps(sk, ct1);
	ss2d := kr->mlkem768_decaps(sk, ct2);
	t.assert(bytescmp(ss1, ss1d), "first encaps/decaps agrees");
	t.assert(bytescmp(ss2, ss2d), "second encaps/decaps agrees");
}

#
# Test ML-KEM-768 multiple round-trips (stress)
#
testMLKEM768Stress(t: ref T)
{
	t.log("ML-KEM-768 stress test - 10 iterations...");

	failures := 0;
	for(iter := 0; iter < 10; iter++) {
		(pk, sk) := kr->mlkem768_keygen();
		if(pk == nil || sk == nil) {
			t.error(sys->sprint("iteration %d: keygen failed", iter));
			failures++;
			continue;
		}

		(ct, ss_enc) := kr->mlkem768_encaps(pk);
		if(ct == nil || ss_enc == nil) {
			t.error(sys->sprint("iteration %d: encaps failed", iter));
			failures++;
			continue;
		}

		ss_dec := kr->mlkem768_decaps(sk, ct);
		if(ss_dec == nil) {
			t.error(sys->sprint("iteration %d: decaps returned nil", iter));
			failures++;
			continue;
		}

		if(!bytescmp(ss_enc, ss_dec)) {
			t.error(sys->sprint("iteration %d: shared secrets differ", iter));
			failures++;
		}
	}

	t.asserteq(failures, 0, sys->sprint("ML-KEM-768 stress: %d/10 passed", 10 - failures));
}

#
# Test ML-KEM-1024 key generation
#
testMLKEM1024KeyGen(t: ref T)
{
	t.log("Testing ML-KEM-1024 key generation...");

	(pk, sk) := kr->mlkem1024_keygen();
	if(pk == nil || sk == nil) {
		t.fatal("mlkem1024_keygen failed");
		return;
	}

	t.asserteq(len pk, 1568, "ML-KEM-1024 public key length");
	t.asserteq(len sk, 3168, "ML-KEM-1024 secret key length");
}

#
# Test ML-KEM-1024 round-trip
#
testMLKEM1024Roundtrip(t: ref T)
{
	t.log("Testing ML-KEM-1024 encaps/decaps round-trip...");

	(pk, sk) := kr->mlkem1024_keygen();
	if(pk == nil || sk == nil) {
		t.fatal("mlkem1024_keygen failed");
		return;
	}

	t.asserteq(len pk, 1568, "ML-KEM-1024 public key length");
	t.asserteq(len sk, 3168, "ML-KEM-1024 secret key length");

	(ct, ss_enc) := kr->mlkem1024_encaps(pk);
	if(ct == nil || ss_enc == nil) {
		t.fatal("encaps failed");
		return;
	}

	t.asserteq(len ct, 1568, "ML-KEM-1024 ciphertext length");
	t.asserteq(len ss_enc, 32, "shared secret length");

	ss_dec := kr->mlkem1024_decaps(sk, ct);
	if(ss_dec == nil) {
		t.fatal("decaps returned nil");
		return;
	}

	t.assert(bytescmp(ss_enc, ss_dec), "ML-KEM-1024 encaps/decaps shared secrets agree");
	t.log("ss=" + hexencode(ss_enc, 32));
}

#
# Test ML-KEM-1024 wrong key rejection
#
testMLKEM1024WrongKey(t: ref T)
{
	t.log("Testing ML-KEM-1024 wrong key rejection...");

	(pk1, nil) := kr->mlkem1024_keygen();
	(nil, sk2) := kr->mlkem1024_keygen();

	(ct, ss_enc) := kr->mlkem1024_encaps(pk1);
	if(ct == nil || ss_enc == nil) {
		t.fatal("encaps failed");
		return;
	}

	ss_wrong := kr->mlkem1024_decaps(sk2, ct);
	if(ss_wrong == nil) {
		t.log("decaps with wrong key returned nil (acceptable)");
		return;
	}

	t.assert(!bytescmp(ss_enc, ss_wrong), "ML-KEM-1024 wrong key implicit rejection");
}

#
# Test ML-KEM-1024 ciphertext tampering
#
testMLKEM1024CtTamper(t: ref T)
{
	t.log("Testing ML-KEM-1024 ciphertext tampering...");

	(pk, sk) := kr->mlkem1024_keygen();
	if(pk == nil || sk == nil) {
		t.fatal("keygen failed");
		return;
	}

	(ct, ss_enc) := kr->mlkem1024_encaps(pk);
	if(ct == nil || ss_enc == nil) {
		t.fatal("encaps failed");
		return;
	}

	ct_tampered := array [len ct] of byte;
	ct_tampered[0:] = ct;
	ct_tampered[0] = ct_tampered[0] ^ byte 16rff;

	ss_tampered := kr->mlkem1024_decaps(sk, ct_tampered);
	if(ss_tampered == nil) {
		t.log("decaps with tampered ct returned nil (acceptable)");
		return;
	}

	t.assert(!bytescmp(ss_enc, ss_tampered), "ML-KEM-1024 tampered ciphertext implicit rejection");
}

#
# Test ML-KEM-1024 stress
#
testMLKEM1024Stress(t: ref T)
{
	t.log("ML-KEM-1024 stress test - 5 iterations...");

	failures := 0;
	for(iter := 0; iter < 5; iter++) {
		(pk, sk) := kr->mlkem1024_keygen();
		if(pk == nil || sk == nil) {
			t.error(sys->sprint("iteration %d: keygen failed", iter));
			failures++;
			continue;
		}

		(ct, ss_enc) := kr->mlkem1024_encaps(pk);
		if(ct == nil || ss_enc == nil) {
			t.error(sys->sprint("iteration %d: encaps failed", iter));
			failures++;
			continue;
		}

		ss_dec := kr->mlkem1024_decaps(sk, ct);
		if(ss_dec == nil) {
			t.error(sys->sprint("iteration %d: decaps returned nil", iter));
			failures++;
			continue;
		}

		if(!bytescmp(ss_enc, ss_dec)) {
			t.error(sys->sprint("iteration %d: shared secrets differ", iter));
			failures++;
		}
	}

	t.asserteq(failures, 0, sys->sprint("ML-KEM-1024 stress: %d/5 passed", 5 - failures));
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
		sys->fprint(sys->fildes(2), "cannot load Testing: %r\n");
		raise "fail:cannot load Testing";
	}

	testing->init();

	for(a := args; a != nil; a = tl a) {
		if(hd a == "-v")
			testing->verbose(1);
	}

	sys->fprint(sys->fildes(2), "\n=== ML-KEM (FIPS 203) Tests ===\n\n");

	# ML-KEM-768 tests
	run("MLKEM768/KeyGen", testMLKEM768KeyGen);
	run("MLKEM768/Roundtrip", testMLKEM768Roundtrip);
	run("MLKEM768/WrongKey", testMLKEM768WrongKey);
	run("MLKEM768/CtTamper", testMLKEM768CtTamper);
	run("MLKEM768/KeyUniqueness", testMLKEM768KeyUniqueness);
	run("MLKEM768/SsUniqueness", testMLKEM768SsUniqueness);
	run("MLKEM768/Stress", testMLKEM768Stress);

	# ML-KEM-1024 tests
	run("MLKEM1024/KeyGen", testMLKEM1024KeyGen);
	run("MLKEM1024/Roundtrip", testMLKEM1024Roundtrip);
	run("MLKEM1024/WrongKey", testMLKEM1024WrongKey);
	run("MLKEM1024/CtTamper", testMLKEM1024CtTamper);
	run("MLKEM1024/Stress", testMLKEM1024Stress);

	if(testing->summary(passed, failed, skipped) > 0)
		raise "fail:tests failed";
}
