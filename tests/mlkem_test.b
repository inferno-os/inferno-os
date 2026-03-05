implement MLKEMTest;

#
# ML-KEM (FIPS 203) tests
#
# Tests ML-KEM-768 and ML-KEM-1024 key encapsulation:
#   - Key generation
#   - Encapsulation / decapsulation round-trip
#   - Shared secret agreement
#   - Rejection of wrong keys
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

	# Shared secrets must match
	match := 1;
	for(i := 0; i < 32; i++) {
		if(ss_enc[i] != ss_dec[i]) {
			match = 0;
			break;
		}
	}
	t.asserteq(match, 1, "encaps/decaps shared secrets agree");
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
	match := 1;
	for(i := 0; i < 32; i++) {
		if(ss_enc[i] != ss_wrong[i]) {
			match = 0;
			break;
		}
	}
	t.asserteq(match, 0, "wrong key produces different shared secret (implicit rejection)");
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

		ok := 1;
		for(i := 0; i < 32; i++) {
			if(ss_enc[i] != ss_dec[i]) {
				ok = 0;
				break;
			}
		}
		if(ok != 1) {
			t.error(sys->sprint("iteration %d: shared secrets differ", iter));
			failures++;
		}
	}

	t.asserteq(failures, 0, sys->sprint("ML-KEM-768 stress: %d/10 passed", 10 - failures));
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

	match := 1;
	for(i := 0; i < 32; i++) {
		if(ss_enc[i] != ss_dec[i]) {
			match = 0;
			break;
		}
	}
	t.asserteq(match, 1, "ML-KEM-1024 encaps/decaps shared secrets agree");
	t.log("ss=" + hexencode(ss_enc, 32));
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

	run("MLKEM768/KeyGen", testMLKEM768KeyGen);
	run("MLKEM768/Roundtrip", testMLKEM768Roundtrip);
	run("MLKEM768/WrongKey", testMLKEM768WrongKey);
	run("MLKEM768/Stress", testMLKEM768Stress);
	run("MLKEM1024/Roundtrip", testMLKEM1024Roundtrip);

	if(testing->summary(passed, failed, skipped) > 0)
		raise "fail:tests failed";
}
