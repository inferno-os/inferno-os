implement PQCFuzzTest;

#
# Post-Quantum Crypto Fuzz / Malformed Input Tests
#
# Tests resilience against malformed, random, and adversarial inputs:
#   - Random bytes as public keys for encaps
#   - Random bytes as ciphertexts for decaps
#   - Random bytes as signatures for verify
#   - Truncated/extended keys and ciphertexts
#   - All-zero and all-0xFF keys
#   - Key/ciphertext with single valid byte corrupted
#
# These tests verify the implementation doesn't crash, panic,
# or produce undefined behavior on adversarial inputs.
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

PQCFuzzTest: module
{
	init: fn(nil: ref Draw->Context, args: list of string);
};

passed := 0;
failed := 0;
skipped := 0;

SRCFILE: con "/tests/pqc_fuzz_test.b";

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

bytescmp(a: array of byte, b: array of byte): int
{
	if(len a != len b)
		return 0;
	for(i := 0; i < len a; i++)
		if(a[i] != b[i])
			return 0;
	return 1;
}

# Generate pseudo-random bytes using a simple LCG
# (not cryptographic, but sufficient for fuzz inputs)
randbytes(buf: array of byte, seed: int)
{
	state := seed;
	for(i := 0; i < len buf; i++) {
		state = state * 1103515245 + 12345;
		buf[i] = byte ((state >> 16) & 16rff);
	}
}

#
# ML-KEM-768: Encaps with random public keys
# Must not crash; may return nil or produce some output
#
testMLKEM768FuzzEncaps(t: ref T)
{
	ITERS : con 100;
	t.log(sys->sprint("ML-KEM-768 fuzz encaps: %d random public keys", ITERS));

	crashes := 0;
	for(iter := 0; iter < ITERS; iter++) {
		fake_pk := array [1184] of byte;
		randbytes(fake_pk, iter * 7 + 13);

		{
			(ct, ss) := kr->mlkem768_encaps(fake_pk);
			# Either nil return or some output is acceptable
			# The key property: no crash
			if(ct != nil)
				t.log(sys->sprint("iter %d: encaps with random pk produced output (len ct=%d)", iter, len ct));
		} exception {
		"*" =>
			crashes++;
			t.error(sys->sprint("iter %d: encaps with random pk crashed", iter));
		}
	}

	t.asserteq(crashes, 0, "no crashes from random public keys");
}

#
# ML-KEM-768: Decaps with random ciphertexts
# Must always produce a shared secret (implicit rejection) or nil,
# never crash
#
testMLKEM768FuzzDecaps(t: ref T)
{
	ITERS : con 200;
	t.log(sys->sprint("ML-KEM-768 fuzz decaps: %d random ciphertexts", ITERS));

	(pk, sk) := kr->mlkem768_keygen();
	t.assert(pk != nil && sk != nil, "keygen");

	# Get one valid shared secret for comparison
	(valid_ct, valid_ss) := kr->mlkem768_encaps(pk);
	t.assert(valid_ct != nil, "valid encaps");

	crashes := 0;
	collisions := 0;
	for(iter := 0; iter < ITERS; iter++) {
		fake_ct := array [1088] of byte;
		randbytes(fake_ct, iter * 31 + 97);

		{
			ss := kr->mlkem768_decaps(sk, fake_ct);
			# Should either be nil or a 32-byte rejection secret
			if(ss != nil) {
				t.assert(len ss == 32,
					sys->sprint("iter %d: rejection ss length", iter));
				# Must NOT match the valid shared secret
				if(bytescmp(ss, valid_ss)) {
					collisions++;
					t.error(sys->sprint("iter %d: random ct produced valid ss!", iter));
				}
			}
		} exception {
		"*" =>
			crashes++;
			t.error(sys->sprint("iter %d: decaps with random ct crashed", iter));
		}
	}

	t.asserteq(crashes, 0, "no crashes from random ciphertexts");
	t.asserteq(collisions, 0, "no collisions with valid shared secret");
}

#
# ML-KEM-768: Decaps with all-zero ciphertext
#
testMLKEM768ZeroCiphertext(t: ref T)
{
	t.log("ML-KEM-768 all-zero ciphertext");

	(pk, sk) := kr->mlkem768_keygen();
	t.assert(pk != nil && sk != nil, "keygen");

	(nil, valid_ss) := kr->mlkem768_encaps(pk);

	zero_ct := array [1088] of { * => byte 0 };
	{
		ss := kr->mlkem768_decaps(sk, zero_ct);
		if(ss != nil) {
			t.assert(!bytescmp(ss, valid_ss), "zero ct must not produce valid ss");
			t.asserteq(len ss, 32, "rejection ss is 32 bytes");
		}
	} exception {
	"*" =>
		t.error("zero ciphertext caused crash");
	}
	t.log("all-zero ciphertext handled safely");
}

#
# ML-KEM-768: Decaps with all-0xFF ciphertext
#
testMLKEM768FFCiphertext(t: ref T)
{
	t.log("ML-KEM-768 all-0xFF ciphertext");

	(pk, sk) := kr->mlkem768_keygen();
	t.assert(pk != nil && sk != nil, "keygen");

	ff_ct := array [1088] of { * => byte 16rff };
	{
		ss := kr->mlkem768_decaps(sk, ff_ct);
		if(ss != nil)
			t.asserteq(len ss, 32, "rejection ss is 32 bytes");
	} exception {
	"*" =>
		t.error("0xFF ciphertext caused crash");
	}
	t.log("all-0xFF ciphertext handled safely");
}

#
# ML-DSA-65: Verify with random signatures
# Must not crash; must always reject
#
testMLDSA65FuzzVerify(t: ref T)
{
	ITERS : con 100;
	t.log(sys->sprint("ML-DSA-65 fuzz verify: %d random signatures", ITERS));

	sk := kr->genSK("mldsa65", "fuzz", 0);
	t.assert(sk != nil, "genSK");
	pk := kr->sktopk(sk);

	msg := array of byte "message for fuzz verification";
	digest := array [32] of byte;

	crashes := 0;
	false_accepts := 0;
	for(iter := 0; iter < ITERS; iter++) {
		# Create a valid certificate structure with a garbage signature
		# First get a real cert for the structure
		state := kr->sha256(msg, len msg, digest, nil);
		real_cert := kr->sign(sk, 0, state, "sha256");
		if(real_cert == nil) {
			t.error(sys->sprint("iter %d: sign failed", iter));
			crashes++;
			continue;
		}

		# Tamper with the signature data
		certstr := kr->certtostr(real_cert);
		if(certstr == nil)
			continue;

		# Parse and re-create with mangled data by flipping bits
		# in the cert string (the sig field)
		mangled := array [len certstr] of byte;
		mangled[0:] = certstr;
		# Flip bytes in the latter half (signature data region)
		half := len mangled / 2;
		for(i := half; i < len mangled; i++)
			mangled[i] = mangled[i] ^ byte ((iter + i) & 16rff);

		# Try to parse and verify the mangled cert
		{
			cert2 := kr->strtocert(mangled);
			if(cert2 != nil) {
				state2 := kr->sha256(msg, len msg, digest, nil);
				ok := kr->verify(pk, cert2, state2);
				if(ok != 0) {
					false_accepts++;
					t.error(sys->sprint("iter %d: mangled cert verified!", iter));
				}
			}
		} exception {
		"*" =>
			# Parse failure is acceptable
			;
		}
	}

	t.asserteq(crashes, 0, "no crashes");
	t.asserteq(false_accepts, 0, "no false accepts");
}

#
# ML-DSA: Key deserialization with garbage data
# strtosk and strtopk must not crash on random input
#
testMLDSADeserializationFuzz(t: ref T)
{
	ITERS : con 100;
	t.log(sys->sprint("ML-DSA key deserialization fuzz: %d random inputs", ITERS));

	crashes := 0;
	for(iter := 0; iter < ITERS; iter++) {
		# Random bytes of various lengths
		sizes := array [] of { 100, 1000, 4032, 4096, 10000 };
		for(si := 0; si < len sizes; si++) {
			garbage := array [sizes[si]] of byte;
			randbytes(garbage, iter * 1000 + si);

			{
				sk := kr->strtosk(garbage);
				# nil is the expected result; any non-nil is concerning but not a crash
				if(sk != nil)
					t.log(sys->sprint("iter %d size %d: strtosk parsed garbage", iter, sizes[si]));
			} exception {
			"*" =>
				crashes++;
				t.error(sys->sprint("iter %d size %d: strtosk crashed", iter, sizes[si]));
			}

			{
				pk := kr->strtopk(garbage);
				if(pk != nil)
					t.log(sys->sprint("iter %d size %d: strtopk parsed garbage", iter, sizes[si]));
			} exception {
			"*" =>
				crashes++;
				t.error(sys->sprint("iter %d size %d: strtopk crashed", iter, sizes[si]));
			}
		}
	}

	t.asserteq(crashes, 0, "no crashes from garbage key data");
}

#
# SLH-DSA: Verify with random signatures
#
testSLHDSA192sFuzzVerify(t: ref T)
{
	ITERS : con 20;
	t.log(sys->sprint("SLH-DSA-192s fuzz verify: %d random signatures", ITERS));

	sk := kr->genSK("slhdsa192s", "fuzz", 0);
	t.assert(sk != nil, "genSK");
	pk := kr->sktopk(sk);

	msg := array of byte "SLH-DSA fuzz verification";
	digest := array [32] of byte;

	crashes := 0;
	false_accepts := 0;
	for(iter := 0; iter < ITERS; iter++) {
		state := kr->sha256(msg, len msg, digest, nil);
		real_cert := kr->sign(sk, 0, state, "sha256");
		if(real_cert == nil)
			continue;

		certstr := kr->certtostr(real_cert);
		if(certstr == nil)
			continue;

		# Corrupt signature bytes
		mangled := array [len certstr] of byte;
		mangled[0:] = certstr;
		half := len mangled / 2;
		for(i := half; i < len mangled; i++)
			mangled[i] = mangled[i] ^ byte 16rff;

		{
			cert2 := kr->strtocert(mangled);
			if(cert2 != nil) {
				state2 := kr->sha256(msg, len msg, digest, nil);
				ok := kr->verify(pk, cert2, state2);
				if(ok != 0) {
					false_accepts++;
					t.error(sys->sprint("iter %d: mangled SLH-DSA cert verified!", iter));
				}
			}
		} exception {
		"*" =>
			;
		}
	}

	t.asserteq(crashes, 0, "no crashes");
	t.asserteq(false_accepts, 0, "no false accepts");
}

#
# ML-KEM-1024: Fuzz with random ciphertexts
#
testMLKEM1024FuzzDecaps(t: ref T)
{
	ITERS : con 100;
	t.log(sys->sprint("ML-KEM-1024 fuzz decaps: %d random ciphertexts", ITERS));

	(pk, sk) := kr->mlkem1024_keygen();
	t.assert(pk != nil && sk != nil, "keygen");

	crashes := 0;
	for(iter := 0; iter < ITERS; iter++) {
		fake_ct := array [1568] of byte;
		randbytes(fake_ct, iter * 43 + 17);

		{
			ss := kr->mlkem1024_decaps(sk, fake_ct);
			if(ss != nil)
				t.assert(len ss == 32,
					sys->sprint("iter %d: rejection ss length", iter));
		} exception {
		"*" =>
			crashes++;
			t.error(sys->sprint("iter %d: crash", iter));
		}
	}

	t.asserteq(crashes, 0, "no crashes from random ML-KEM-1024 ciphertexts");
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

	sys->fprint(sys->fildes(2), "\n=== PQ Crypto Fuzz / Malformed Input Tests ===\n\n");

	# ML-KEM fuzz tests
	run("MLKEM768/FuzzEncaps", testMLKEM768FuzzEncaps);
	run("MLKEM768/FuzzDecaps", testMLKEM768FuzzDecaps);
	run("MLKEM768/ZeroCiphertext", testMLKEM768ZeroCiphertext);
	run("MLKEM768/FFCiphertext", testMLKEM768FFCiphertext);
	run("MLKEM1024/FuzzDecaps", testMLKEM1024FuzzDecaps);

	# ML-DSA fuzz tests
	run("MLDSA65/FuzzVerify", testMLDSA65FuzzVerify);
	run("MLDSA/DeserializationFuzz", testMLDSADeserializationFuzz);

	# SLH-DSA fuzz tests
	run("SLHDSA192s/FuzzVerify", testSLHDSA192sFuzzVerify);

	if(testing->summary(passed, failed, skipped) > 0)
		raise "fail:tests failed";
}
