implement MLDSAStressTest;

#
# ML-DSA (FIPS 204) Production Stress Tests
#
# Heavy-duty stress testing of ML-DSA-65 and ML-DSA-87:
#   - 100 keygen+sign+verify cycles for ML-DSA-65
#   - 50 keygen+sign+verify cycles for ML-DSA-87
#   - Multiple messages per key (signature reuse testing)
#   - Empty message signing
#   - Large message signing (64KB)
#   - Binary message signing (all byte values)
#   - Signature malleability testing
#   - Serialization stress (round-trip through sktostr/strtosk)
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

MLDSAStressTest: module
{
	init: fn(nil: ref Draw->Context, args: list of string);
};

passed := 0;
failed := 0;
skipped := 0;

SRCFILE: con "/tests/mldsa_stress_test.b";

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

signverify(t: ref T, algname: string, sk: ref Keyring->SK, pk: ref Keyring->PK,
	msg: array of byte, label: string): int
{
	digest := array [32] of byte;
	state := kr->sha256(msg, len msg, digest, nil);
	cert := kr->sign(sk, 0, state, "sha256");
	if(cert == nil) {
		t.error(label + ": sign returned nil");
		return 0;
	}

	state2 := kr->sha256(msg, len msg, digest, nil);
	ok := kr->verify(pk, cert, state2);
	if(ok == 0) {
		t.error(label + ": verify failed");
		return 0;
	}
	return 1;
}

#
# Test ML-DSA-65: 100 keygen+sign+verify cycles
#
testMLDSA65MassCycles(t: ref T)
{
	ITERS : con 100;
	t.log(sys->sprint("ML-DSA-65 mass cycles: %d iterations", ITERS));

	failures := 0;
	for(iter := 0; iter < ITERS; iter++) {
		sk := kr->genSK("mldsa65", "stress", 0);
		if(sk == nil) {
			t.error(sys->sprint("iter %d: genSK failed", iter));
			failures++;
			continue;
		}
		pk := kr->sktopk(sk);
		if(pk == nil) {
			t.error(sys->sprint("iter %d: sktopk failed", iter));
			failures++;
			continue;
		}

		msg := array of byte sys->sprint("stress message iteration %d", iter);
		if(!signverify(t, "mldsa65", sk, pk, msg,
			sys->sprint("iter %d", iter)))
			failures++;

		if(iter % 25 == 24)
			t.log(sys->sprint("  ... completed %d/%d", iter+1, ITERS));
	}

	t.asserteq(failures, 0, sys->sprint("ML-DSA-65: %d/%d passed", ITERS - failures, ITERS));
}

#
# Test ML-DSA-87: 50 keygen+sign+verify cycles
#
testMLDSA87MassCycles(t: ref T)
{
	ITERS : con 50;
	t.log(sys->sprint("ML-DSA-87 mass cycles: %d iterations", ITERS));

	failures := 0;
	for(iter := 0; iter < ITERS; iter++) {
		sk := kr->genSK("mldsa87", "stress", 0);
		if(sk == nil) {
			t.error(sys->sprint("iter %d: genSK failed", iter));
			failures++;
			continue;
		}
		pk := kr->sktopk(sk);

		msg := array of byte sys->sprint("ML-DSA-87 stress iteration %d", iter);
		if(!signverify(t, "mldsa87", sk, pk, msg,
			sys->sprint("iter %d", iter)))
			failures++;

		if(iter % 10 == 9)
			t.log(sys->sprint("  ... completed %d/%d", iter+1, ITERS));
	}

	t.asserteq(failures, 0, sys->sprint("ML-DSA-87: %d/%d passed", ITERS - failures, ITERS));
}

#
# Test signing multiple distinct messages with the same key
# Verifies the rejection sampling loop handles diverse inputs
#
testMLDSA65MultiMessage(t: ref T)
{
	MSGS : con 200;
	t.log(sys->sprint("ML-DSA-65 multi-message: %d messages per key", MSGS));

	sk := kr->genSK("mldsa65", "multi", 0);
	t.assert(sk != nil, "genSK");
	pk := kr->sktopk(sk);
	t.assert(pk != nil, "sktopk");

	failures := 0;
	for(i := 0; i < MSGS; i++) {
		msg := array of byte sys->sprint("message number %d of %d", i, MSGS);
		if(!signverify(t, "mldsa65", sk, pk, msg,
			sys->sprint("msg %d", i)))
			failures++;
	}

	t.asserteq(failures, 0, sys->sprint("multi-message: %d/%d verified", MSGS - failures, MSGS));
}

#
# Test empty message signing
#
testMLDSA65EmptyMessage(t: ref T)
{
	t.log("ML-DSA-65 empty message signing");

	sk := kr->genSK("mldsa65", "empty", 0);
	t.assert(sk != nil, "genSK");
	pk := kr->sktopk(sk);

	msg := array [0] of byte;
	t.assert(signverify(t, "mldsa65", sk, pk, msg, "empty message") != 0,
		"empty message sign+verify");
}

#
# Test large message signing (64KB)
#
testMLDSA65LargeMessage(t: ref T)
{
	t.log("ML-DSA-65 large message signing (64KB)");

	sk := kr->genSK("mldsa65", "large", 0);
	t.assert(sk != nil, "genSK");
	pk := kr->sktopk(sk);

	# Create 64KB message with pattern
	msg := array [65536] of byte;
	for(i := 0; i < len msg; i++)
		msg[i] = byte (i & 16rff);

	t.assert(signverify(t, "mldsa65", sk, pk, msg, "64KB message") != 0,
		"large message sign+verify");
}

#
# Test binary message (all byte values 0x00-0xFF)
#
testMLDSA65BinaryMessage(t: ref T)
{
	t.log("ML-DSA-65 binary message (all byte values)");

	sk := kr->genSK("mldsa65", "binary", 0);
	t.assert(sk != nil, "genSK");
	pk := kr->sktopk(sk);

	# Message containing every possible byte value
	msg := array [256] of byte;
	for(i := 0; i < 256; i++)
		msg[i] = byte i;

	t.assert(signverify(t, "mldsa65", sk, pk, msg, "binary message") != 0,
		"binary message sign+verify");

	# All zeros message
	msg2 := array [256] of { * => byte 0 };
	t.assert(signverify(t, "mldsa65", sk, pk, msg2, "all-zeros") != 0,
		"all-zeros message sign+verify");

	# All 0xFF message
	msg3 := array [256] of { * => byte 16rff };
	t.assert(signverify(t, "mldsa65", sk, pk, msg3, "all-ff") != 0,
		"all-0xFF message sign+verify");
}

#
# Test message tampering detection at various granularities
#
testMLDSA65TamperDetection(t: ref T)
{
	t.log("ML-DSA-65 tamper detection");

	sk := kr->genSK("mldsa65", "tamper", 0);
	t.assert(sk != nil, "genSK");
	pk := kr->sktopk(sk);

	msg := array of byte "original message for tamper detection testing";
	digest := array [32] of byte;
	state := kr->sha256(msg, len msg, digest, nil);
	cert := kr->sign(sk, 0, state, "sha256");
	t.assert(cert != nil, "sign");

	# Verify original
	state2 := kr->sha256(msg, len msg, digest, nil);
	ok := kr->verify(pk, cert, state2);
	t.assert(ok != 0, "original verifies");

	# Tamper: single bit flip at various positions
	failures := 0;
	for(bit := 0; bit < len msg * 8; bit += 8) {
		pos := bit / 8;
		tampered := array [len msg] of byte;
		tampered[0:] = msg;
		tampered[pos] = tampered[pos] ^ byte 16r01;

		state3 := kr->sha256(tampered, len tampered, digest, nil);
		ok2 := kr->verify(pk, cert, state3);
		if(ok2 != 0) {
			t.error(sys->sprint("tamper at byte %d not detected", pos));
			failures++;
		}
	}

	t.asserteq(failures, 0, sys->sprint("all %d byte positions detected", len msg));
}

#
# Test serialization stress: serialize and deserialize keys 50 times,
# verify signatures work with deserialized keys
#
testMLDSA65SerializationStress(t: ref T)
{
	ITERS : con 50;
	t.log(sys->sprint("ML-DSA-65 serialization stress: %d round-trips", ITERS));

	failures := 0;
	for(iter := 0; iter < ITERS; iter++) {
		sk := kr->genSK("mldsa65", "serial", 0);
		if(sk == nil) {
			t.error(sys->sprint("iter %d: genSK failed", iter));
			failures++;
			continue;
		}
		pk := kr->sktopk(sk);

		# Serialize and deserialize
		skstr := kr->sktostr(sk);
		if(skstr == nil) {
			t.error(sys->sprint("iter %d: sktostr failed", iter));
			failures++;
			continue;
		}
		sk2 := kr->strtosk(skstr);
		if(sk2 == nil) {
			t.error(sys->sprint("iter %d: strtosk failed", iter));
			failures++;
			continue;
		}

		pkstr := kr->pktostr(pk);
		pk2 := kr->strtopk(pkstr);
		if(pk2 == nil) {
			t.error(sys->sprint("iter %d: strtopk failed", iter));
			failures++;
			continue;
		}

		# Sign with deserialized sk, verify with deserialized pk
		msg := array of byte sys->sprint("serialization stress %d", iter);
		if(!signverify(t, "mldsa65", sk2, pk2, msg,
			sys->sprint("iter %d", iter)))
			failures++;
	}

	t.asserteq(failures, 0, sys->sprint("serialization: %d/%d passed", ITERS - failures, ITERS));
}

#
# SLH-DSA stress tests (fewer iterations since it's slower)
#

testSLHDSA192sMassCycles(t: ref T)
{
	ITERS : con 20;
	t.log(sys->sprint("SLH-DSA-192s mass cycles: %d iterations", ITERS));

	failures := 0;
	for(iter := 0; iter < ITERS; iter++) {
		sk := kr->genSK("slhdsa192s", "stress", 0);
		if(sk == nil) {
			t.error(sys->sprint("iter %d: genSK failed", iter));
			failures++;
			continue;
		}
		pk := kr->sktopk(sk);

		msg := array of byte sys->sprint("SLH-DSA-192s stress %d", iter);
		if(!signverify(t, "slhdsa192s", sk, pk, msg,
			sys->sprint("iter %d", iter)))
			failures++;

		if(iter % 5 == 4)
			t.log(sys->sprint("  ... completed %d/%d", iter+1, ITERS));
	}

	t.asserteq(failures, 0, sys->sprint("SLH-DSA-192s: %d/%d passed", ITERS - failures, ITERS));
}

testSLHDSA256sMassCycles(t: ref T)
{
	ITERS : con 10;
	t.log(sys->sprint("SLH-DSA-256s mass cycles: %d iterations", ITERS));

	failures := 0;
	for(iter := 0; iter < ITERS; iter++) {
		sk := kr->genSK("slhdsa256s", "stress", 0);
		if(sk == nil) {
			t.error(sys->sprint("iter %d: genSK failed", iter));
			failures++;
			continue;
		}
		pk := kr->sktopk(sk);

		msg := array of byte sys->sprint("SLH-DSA-256s stress %d", iter);
		if(!signverify(t, "slhdsa256s", sk, pk, msg,
			sys->sprint("iter %d", iter)))
			failures++;
	}

	t.asserteq(failures, 0, sys->sprint("SLH-DSA-256s: %d/%d passed", ITERS - failures, ITERS));
}

#
# Test empty and edge-case messages for SLH-DSA
#
testSLHDSA192sEdgeCases(t: ref T)
{
	t.log("SLH-DSA-192s edge case messages");

	sk := kr->genSK("slhdsa192s", "edge", 0);
	t.assert(sk != nil, "genSK");
	pk := kr->sktopk(sk);

	# Empty message
	msg0 := array [0] of byte;
	t.assert(signverify(t, "slhdsa192s", sk, pk, msg0, "empty") != 0, "empty message");

	# Single byte
	msg1 := array [1] of { * => byte 16r42 };
	t.assert(signverify(t, "slhdsa192s", sk, pk, msg1, "one-byte") != 0, "single byte");

	# All zeros
	msg2 := array [256] of { * => byte 0 };
	t.assert(signverify(t, "slhdsa192s", sk, pk, msg2, "all-zeros") != 0, "256 zeros");

	# All 0xFF
	msg3 := array [256] of { * => byte 16rff };
	t.assert(signverify(t, "slhdsa192s", sk, pk, msg3, "all-ff") != 0, "256 x 0xFF");
}

#
# Cross-algorithm rejection: ensure PQ signatures don't verify
# with classical algorithm keys and vice versa
#
testCrossAlgIsolation(t: ref T)
{
	t.log("Cross-algorithm isolation test");

	# Generate keys for each algorithm
	sk_mldsa65 := kr->genSK("mldsa65", "cross", 0);
	sk_mldsa87 := kr->genSK("mldsa87", "cross", 0);
	sk_slhdsa192 := kr->genSK("slhdsa192s", "cross", 0);
	sk_ed := kr->genSK("ed25519", "cross", 0);

	t.assert(sk_mldsa65 != nil, "genSK mldsa65");
	t.assert(sk_mldsa87 != nil, "genSK mldsa87");
	t.assert(sk_slhdsa192 != nil, "genSK slhdsa192s");
	t.assert(sk_ed != nil, "genSK ed25519");

	pk_mldsa87 := kr->sktopk(sk_mldsa87);
	pk_slhdsa192 := kr->sktopk(sk_slhdsa192);
	pk_ed := kr->sktopk(sk_ed);

	# Sign with mldsa65
	msg := array of byte "cross-algorithm isolation test";
	digest := array [32] of byte;
	state := kr->sha256(msg, len msg, digest, nil);
	cert := kr->sign(sk_mldsa65, 0, state, "sha256");
	t.assert(cert != nil, "mldsa65 sign");

	# Must not verify with other algorithms
	state2 := kr->sha256(msg, len msg, digest, nil);
	ok := kr->verify(pk_mldsa87, cert, state2);
	t.assert(ok == 0, "mldsa65 sig must not verify with mldsa87 key");

	state3 := kr->sha256(msg, len msg, digest, nil);
	ok2 := kr->verify(pk_slhdsa192, cert, state3);
	t.assert(ok2 == 0, "mldsa65 sig must not verify with slhdsa192s key");

	state4 := kr->sha256(msg, len msg, digest, nil);
	ok3 := kr->verify(pk_ed, cert, state4);
	t.assert(ok3 == 0, "mldsa65 sig must not verify with ed25519 key");
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

	sys->fprint(sys->fildes(2), "\n=== PQ Signature Production Stress Tests ===\n\n");

	# ML-DSA tests
	run("MLDSA65/MassCycles", testMLDSA65MassCycles);
	run("MLDSA87/MassCycles", testMLDSA87MassCycles);
	run("MLDSA65/MultiMessage", testMLDSA65MultiMessage);
	run("MLDSA65/EmptyMessage", testMLDSA65EmptyMessage);
	run("MLDSA65/LargeMessage", testMLDSA65LargeMessage);
	run("MLDSA65/BinaryMessage", testMLDSA65BinaryMessage);
	run("MLDSA65/TamperDetection", testMLDSA65TamperDetection);
	run("MLDSA65/SerializationStress", testMLDSA65SerializationStress);

	# SLH-DSA tests
	run("SLHDSA192s/MassCycles", testSLHDSA192sMassCycles);
	run("SLHDSA256s/MassCycles", testSLHDSA256sMassCycles);
	run("SLHDSA192s/EdgeCases", testSLHDSA192sEdgeCases);

	# Cross-algorithm
	run("CrossAlg/Isolation", testCrossAlgIsolation);

	if(testing->summary(passed, failed, skipped) > 0)
		raise "fail:tests failed";
}
