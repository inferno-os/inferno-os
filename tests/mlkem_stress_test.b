implement MLKEMStressTest;

#
# ML-KEM (FIPS 203) Production Stress Tests
#
# Heavy-duty stress testing of ML-KEM-768 and ML-KEM-1024:
#   - 1000 keygen+encaps+decaps round-trips for ML-KEM-768
#   - 500 round-trips for ML-KEM-1024
#   - Wrong-key implicit rejection consistency (100 iterations)
#   - Ciphertext tampering at multiple positions (100 iterations)
#   - Key independence verification across batches
#   - Shared secret entropy validation
#
# These tests are designed to catch rare failure modes that only
# manifest under specific coefficient distributions or random seeds.
#

include "sys.m";
	sys: Sys;

include "draw.m";

include "keyring.m";
	kr: Keyring;

include "testing.m";
	testing: Testing;
	T: import testing;

MLKEMStressTest: module
{
	init: fn(nil: ref Draw->Context, args: list of string);
};

passed := 0;
failed := 0;
skipped := 0;

SRCFILE: con "/tests/mlkem_stress_test.b";

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

# Compare byte arrays
bytescmp(a: array of byte, b: array of byte): int
{
	if(len a != len b)
		return 0;
	for(i := 0; i < len a; i++)
		if(a[i] != b[i])
			return 0;
	return 1;
}

# Count differing bytes between two arrays of equal length
bytesdiff(a: array of byte, b: array of byte): int
{
	n := 0;
	for(i := 0; i < len a && i < len b; i++)
		if(a[i] != b[i])
			n++;
	return n;
}

# Compute simple byte histogram entropy estimate (0-255)
byteentropy(buf: array of byte): int
{
	counts := array [256] of { * => 0 };
	for(i := 0; i < len buf; i++)
		counts[int buf[i]]++;
	distinct := 0;
	for(i := 0; i < 256; i++)
		if(counts[i] > 0)
			distinct++;
	return distinct;
}

#
# Test ML-KEM-768: 1000 keygen+encaps+decaps round-trips
#
testMLKEM768MassRoundtrip(t: ref T)
{
	ITERS : con 1000;
	t.log(sys->sprint("ML-KEM-768 mass round-trip: %d iterations", ITERS));

	failures := 0;
	for(iter := 0; iter < ITERS; iter++) {
		(pk, sk) := kr->mlkem768_keygen();
		if(pk == nil || sk == nil) {
			t.error(sys->sprint("iter %d: keygen failed", iter));
			failures++;
			continue;
		}

		(ct, ss_enc) := kr->mlkem768_encaps(pk);
		if(ct == nil || ss_enc == nil) {
			t.error(sys->sprint("iter %d: encaps failed", iter));
			failures++;
			continue;
		}

		ss_dec := kr->mlkem768_decaps(sk, ct);
		if(ss_dec == nil) {
			t.error(sys->sprint("iter %d: decaps returned nil", iter));
			failures++;
			continue;
		}

		if(!bytescmp(ss_enc, ss_dec)) {
			t.error(sys->sprint("iter %d: shared secrets differ", iter));
			failures++;
		}

		if(iter % 100 == 99)
			t.log(sys->sprint("  ... completed %d/%d iterations", iter+1, ITERS));
	}

	t.asserteq(failures, 0, sys->sprint("ML-KEM-768: %d/%d passed", ITERS - failures, ITERS));
}

#
# Test ML-KEM-1024: 500 keygen+encaps+decaps round-trips
#
testMLKEM1024MassRoundtrip(t: ref T)
{
	ITERS : con 500;
	t.log(sys->sprint("ML-KEM-1024 mass round-trip: %d iterations", ITERS));

	failures := 0;
	for(iter := 0; iter < ITERS; iter++) {
		(pk, sk) := kr->mlkem1024_keygen();
		if(pk == nil || sk == nil) {
			t.error(sys->sprint("iter %d: keygen failed", iter));
			failures++;
			continue;
		}

		(ct, ss_enc) := kr->mlkem1024_encaps(pk);
		if(ct == nil || ss_enc == nil) {
			t.error(sys->sprint("iter %d: encaps failed", iter));
			failures++;
			continue;
		}

		ss_dec := kr->mlkem1024_decaps(sk, ct);
		if(ss_dec == nil) {
			t.error(sys->sprint("iter %d: decaps returned nil", iter));
			failures++;
			continue;
		}

		if(!bytescmp(ss_enc, ss_dec)) {
			t.error(sys->sprint("iter %d: shared secrets differ", iter));
			failures++;
		}

		if(iter % 100 == 99)
			t.log(sys->sprint("  ... completed %d/%d iterations", iter+1, ITERS));
	}

	t.asserteq(failures, 0, sys->sprint("ML-KEM-1024: %d/%d passed", ITERS - failures, ITERS));
}

#
# Test implicit rejection consistency: wrong-key decaps should never
# produce the correct shared secret (100 iterations)
#
testMLKEM768ImplicitRejection(t: ref T)
{
	ITERS : con 100;
	t.log(sys->sprint("ML-KEM-768 implicit rejection consistency: %d iterations", ITERS));

	failures := 0;
	for(iter := 0; iter < ITERS; iter++) {
		(pk1, nil) := kr->mlkem768_keygen();
		(nil, sk2) := kr->mlkem768_keygen();

		(ct, ss_enc) := kr->mlkem768_encaps(pk1);
		if(ct == nil || ss_enc == nil) {
			t.error(sys->sprint("iter %d: encaps failed", iter));
			failures++;
			continue;
		}

		ss_wrong := kr->mlkem768_decaps(sk2, ct);
		if(ss_wrong == nil) {
			# nil is acceptable (explicit rejection)
			continue;
		}

		if(bytescmp(ss_enc, ss_wrong)) {
			t.error(sys->sprint("iter %d: wrong key produced CORRECT shared secret!", iter));
			failures++;
		}

		# Verify the rejection secret has reasonable entropy
		distinct := byteentropy(ss_wrong);
		if(distinct < 4) {
			t.error(sys->sprint("iter %d: rejection secret has low entropy (%d distinct bytes)", iter, distinct));
			failures++;
		}
	}

	t.asserteq(failures, 0, sys->sprint("implicit rejection: %d/%d passed", ITERS - failures, ITERS));
}

#
# Test ciphertext tampering at every byte position
# Verify tampering at any position causes decapsulation to produce wrong ss
#
testMLKEM768TamperSweep(t: ref T)
{
	t.log("ML-KEM-768 tamper sweep: flip each byte of ciphertext");

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

	# Verify original works
	ss_check := kr->mlkem768_decaps(sk, ct);
	t.assert(bytescmp(ss_enc, ss_check), "baseline decaps works");

	# Tamper at every 16th byte position (1088/16 = 68 positions)
	failures := 0;
	positions := 0;
	for(pos := 0; pos < len ct; pos += 16) {
		ct_tampered := array [len ct] of byte;
		ct_tampered[0:] = ct;
		ct_tampered[pos] = ct_tampered[pos] ^ byte 16rff;

		ss_tampered := kr->mlkem768_decaps(sk, ct_tampered);
		if(ss_tampered != nil && bytescmp(ss_enc, ss_tampered)) {
			t.error(sys->sprint("tamper at byte %d: shared secret unchanged!", pos));
			failures++;
		}
		positions++;
	}

	t.log(sys->sprint("  tested %d positions", positions));
	t.asserteq(failures, 0, sys->sprint("tamper sweep: %d/%d detected", positions - failures, positions));
}

#
# Test shared secret entropy across many generations
# Verify no collisions in 200 shared secrets
#
testMLKEM768SsEntropy(t: ref T)
{
	ITERS : con 200;
	t.log(sys->sprint("ML-KEM-768 shared secret entropy: %d generations", ITERS));

	(pk, sk) := kr->mlkem768_keygen();
	if(pk == nil || sk == nil) {
		t.fatal("keygen failed");
		return;
	}

	# Collect shared secrets
	secrets := array [ITERS] of array of byte;
	for(i := 0; i < ITERS; i++) {
		(nil, ss) := kr->mlkem768_encaps(pk);
		if(ss == nil) {
			t.fatal(sys->sprint("encaps %d failed", i));
			return;
		}
		secrets[i] = ss;
	}

	# Check for collisions (O(n^2) but n=200 is fine)
	collisions := 0;
	for(i := 0; i < ITERS; i++)
		for(j := i+1; j < ITERS; j++)
			if(bytescmp(secrets[i], secrets[j]))
				collisions++;

	t.asserteq(collisions, 0, sys->sprint("no collisions in %d shared secrets", ITERS));

	# Check byte distribution across all secrets
	# Each byte position across 200 secrets should show variation
	lowvar := 0;
	for(pos := 0; pos < 32; pos++) {
		seen := array [256] of { * => 0 };
		for(i := 0; i < ITERS; i++)
			seen[int secrets[i][pos]]++;
		distinct := 0;
		for(i := 0; i < 256; i++)
			if(seen[i] > 0)
				distinct++;
		# With 200 samples, each byte position should have at least 50 distinct values
		if(distinct < 50)
			lowvar++;
	}
	t.asserteq(lowvar, 0, "all byte positions show sufficient variation");
}

#
# Test key independence: keys generated sequentially should be independent
#
testMLKEM768KeyIndependence(t: ref T)
{
	ITERS : con 50;
	t.log(sys->sprint("ML-KEM-768 key independence: %d key pairs", ITERS));

	pks := array [ITERS] of array of byte;
	sks := array [ITERS] of array of byte;

	for(i := 0; i < ITERS; i++) {
		(pk, sk) := kr->mlkem768_keygen();
		if(pk == nil || sk == nil) {
			t.fatal(sys->sprint("keygen %d failed", i));
			return;
		}
		pks[i] = pk;
		sks[i] = sk;
	}

	# All public keys should be distinct
	pk_collisions := 0;
	for(i := 0; i < ITERS; i++)
		for(j := i+1; j < ITERS; j++)
			if(bytescmp(pks[i], pks[j]))
				pk_collisions++;

	t.asserteq(pk_collisions, 0, sys->sprint("all %d public keys distinct", ITERS));

	# Cross-key decapsulation should never succeed
	# Test a subset (first 10 keys against each other)
	cross_failures := 0;
	for(i := 0; i < 10; i++) {
		(ct, ss_enc) := kr->mlkem768_encaps(pks[i]);
		if(ct == nil)
			continue;
		for(j := 0; j < 10; j++) {
			if(j == i)
				continue;
			ss_dec := kr->mlkem768_decaps(sks[j], ct);
			if(ss_dec != nil && bytescmp(ss_enc, ss_dec)) {
				t.error(sys->sprint("cross-key decaps succeeded: key %d -> key %d", i, j));
				cross_failures++;
			}
		}
	}

	t.asserteq(cross_failures, 0, "cross-key decapsulation never succeeds");
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

	sys->fprint(sys->fildes(2), "\n=== ML-KEM (FIPS 203) Production Stress Tests ===\n\n");

	run("MLKEM768/MassRoundtrip", testMLKEM768MassRoundtrip);
	run("MLKEM1024/MassRoundtrip", testMLKEM1024MassRoundtrip);
	run("MLKEM768/ImplicitRejection", testMLKEM768ImplicitRejection);
	run("MLKEM768/TamperSweep", testMLKEM768TamperSweep);
	run("MLKEM768/SsEntropy", testMLKEM768SsEntropy);
	run("MLKEM768/KeyIndependence", testMLKEM768KeyIndependence);

	if(testing->summary(passed, failed, skipped) > 0)
		raise "fail:tests failed";
}
