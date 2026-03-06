implement SLHDSATest;

#
# SLH-DSA (FIPS 205) tests
#
# Tests SLH-DSA-SHAKE-192s and SLH-DSA-SHAKE-256s digital signatures
# via Keyring SigAlgVec:
#   - Key generation (genSK) produces valid keys
#   - Sign/verify round-trip works
#   - Wrong-key verification fails
#   - Signature tampering detection
#   - Key serialization (sktostr/strtosk, pktostr/strtopk)
#   - Cross-level rejection (sign with 192s, verify with 256s)
#   - Stress test (multiple keygen+sign+verify cycles)
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

SLHDSATest: module
{
	init: fn(nil: ref Draw->Context, args: list of string);
};

passed := 0;
failed := 0;
skipped := 0;

SRCFILE: con "/tests/slhdsa_test.b";

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

testSLHDSA192sKeygen(t: ref T)
{
	sk := kr->genSK("slhdsa192s", "test-owner", 0);
	t.assert(sk != nil, "genSK slhdsa192s produced key");
	t.assertseq(sk.sa.name, "slhdsa192s", "algorithm name");

	pk := kr->sktopk(sk);
	t.assert(pk != nil, "sktopk produced public key");
	t.assertseq(pk.sa.name, "slhdsa192s", "pk algorithm name");
}

testSLHDSA192sSignVerify(t: ref T)
{
	sk := kr->genSK("slhdsa192s", "signer", 0);
	t.assert(sk != nil, "genSK");

	pk := kr->sktopk(sk);
	t.assert(pk != nil, "sktopk");

	msg := array of byte "test message for SLH-DSA-SHAKE-192s";
	digest := array [32] of byte;
	state := kr->sha256(msg, len msg, digest, nil);

	cert := kr->sign(sk, 0, state, "sha256");
	t.assert(cert != nil, "sign produced certificate");

	state2 := kr->sha256(msg, len msg, digest, nil);
	ok := kr->verify(pk, cert, state2);
	t.assert(ok != 0, "verify succeeded");
}

testSLHDSA192sWrongKey(t: ref T)
{
	sk1 := kr->genSK("slhdsa192s", "signer1", 0);
	sk2 := kr->genSK("slhdsa192s", "signer2", 0);
	pk2 := kr->sktopk(sk2);

	msg := array of byte "test message";
	digest := array [32] of byte;
	state := kr->sha256(msg, len msg, digest, nil);

	cert := kr->sign(sk1, 0, state, "sha256");
	t.assert(cert != nil, "sign produced certificate");

	state2 := kr->sha256(msg, len msg, digest, nil);
	ok := kr->verify(pk2, cert, state2);
	t.assert(ok == 0, "verify with wrong key fails");
}

testSLHDSA192sSigTamper(t: ref T)
{
	sk := kr->genSK("slhdsa192s", "tamper-test", 0);
	pk := kr->sktopk(sk);

	msg := array of byte "tamper detection test";
	digest := array [32] of byte;
	state := kr->sha256(msg, len msg, digest, nil);

	cert := kr->sign(sk, 0, state, "sha256");
	t.assert(cert != nil, "sign produced certificate");

	# Verify with different message (message tampering)
	msg2 := array of byte "TAMPERED message";
	state3 := kr->sha256(msg2, len msg2, digest, nil);
	ok := kr->verify(pk, cert, state3);
	t.assert(ok == 0, "verify with tampered message fails");
}

testSLHDSA192sSerialization(t: ref T)
{
	sk := kr->genSK("slhdsa192s", "serial-test", 0);
	t.assert(sk != nil, "genSK");

	pk := kr->sktopk(sk);
	t.assert(pk != nil, "sktopk");

	# Serialize and deserialize SK
	skstr := kr->sktostr(sk);
	t.assert(skstr != nil, "sktostr produced string");
	t.assert(len skstr > 0, "sktostr non-empty");

	sk2 := kr->strtosk(skstr);
	t.assert(sk2 != nil, "strtosk parsed key");
	t.assertseq(sk2.sa.name, "slhdsa192s", "deserialized sk algorithm");

	# Serialize and deserialize PK
	pkstr := kr->pktostr(pk);
	t.assert(pkstr != nil, "pktostr produced string");

	pk2 := kr->strtopk(pkstr);
	t.assert(pk2 != nil, "strtopk parsed key");
	t.assertseq(pk2.sa.name, "slhdsa192s", "deserialized pk algorithm");

	# Sign with deserialized SK, verify with deserialized PK
	msg := array of byte "serialization round-trip";
	digest := array [32] of byte;
	state := kr->sha256(msg, len msg, digest, nil);
	cert := kr->sign(sk2, 0, state, "sha256");
	t.assert(cert != nil, "sign with deserialized key");

	state2 := kr->sha256(msg, len msg, digest, nil);
	ok := kr->verify(pk2, cert, state2);
	t.assert(ok != 0, "verify with deserialized key");
}

testSLHDSA256sKeygen(t: ref T)
{
	sk := kr->genSK("slhdsa256s", "test-owner", 0);
	t.assert(sk != nil, "genSK slhdsa256s produced key");
	t.assertseq(sk.sa.name, "slhdsa256s", "algorithm name");

	pk := kr->sktopk(sk);
	t.assert(pk != nil, "sktopk produced public key");
}

testSLHDSA256sSignVerify(t: ref T)
{
	sk := kr->genSK("slhdsa256s", "signer", 0);
	t.assert(sk != nil, "genSK");

	pk := kr->sktopk(sk);
	t.assert(pk != nil, "sktopk");

	msg := array of byte "test message for SLH-DSA-SHAKE-256s";
	digest := array [32] of byte;
	state := kr->sha256(msg, len msg, digest, nil);

	cert := kr->sign(sk, 0, state, "sha256");
	t.assert(cert != nil, "sign produced certificate");

	state2 := kr->sha256(msg, len msg, digest, nil);
	ok := kr->verify(pk, cert, state2);
	t.assert(ok != 0, "verify succeeded");
}

testSLHDSA256sWrongKey(t: ref T)
{
	sk1 := kr->genSK("slhdsa256s", "signer1", 0);
	sk2 := kr->genSK("slhdsa256s", "signer2", 0);
	pk2 := kr->sktopk(sk2);

	msg := array of byte "test message for wrong key";
	digest := array [32] of byte;
	state := kr->sha256(msg, len msg, digest, nil);

	cert := kr->sign(sk1, 0, state, "sha256");
	t.assert(cert != nil, "sign produced certificate");

	state2 := kr->sha256(msg, len msg, digest, nil);
	ok := kr->verify(pk2, cert, state2);
	t.assert(ok == 0, "verify with wrong key fails");
}

testSLHDSA256sSerialization(t: ref T)
{
	sk := kr->genSK("slhdsa256s", "serial-test", 0);
	t.assert(sk != nil, "genSK");

	pk := kr->sktopk(sk);
	t.assert(pk != nil, "sktopk");

	skstr := kr->sktostr(sk);
	t.assert(skstr != nil, "sktostr produced string");

	sk2 := kr->strtosk(skstr);
	t.assert(sk2 != nil, "strtosk parsed key");
	t.assertseq(sk2.sa.name, "slhdsa256s", "deserialized sk algorithm");

	pkstr := kr->pktostr(pk);
	t.assert(pkstr != nil, "pktostr produced string");

	pk2 := kr->strtopk(pkstr);
	t.assert(pk2 != nil, "strtopk parsed key");
	t.assertseq(pk2.sa.name, "slhdsa256s", "deserialized pk algorithm");

	msg := array of byte "256s serialization test";
	digest := array [32] of byte;
	state := kr->sha256(msg, len msg, digest, nil);
	cert := kr->sign(sk2, 0, state, "sha256");
	t.assert(cert != nil, "sign with deserialized key");

	state2 := kr->sha256(msg, len msg, digest, nil);
	ok := kr->verify(pk2, cert, state2);
	t.assert(ok != 0, "verify with deserialized key");
}

testCrossLevelReject(t: ref T)
{
	sk192 := kr->genSK("slhdsa192s", "cross-test", 0);
	sk256 := kr->genSK("slhdsa256s", "cross-test", 0);
	pk256 := kr->sktopk(sk256);

	msg := array of byte "cross-level rejection test";
	digest := array [32] of byte;
	state := kr->sha256(msg, len msg, digest, nil);

	# Sign with 192s
	cert := kr->sign(sk192, 0, state, "sha256");
	t.assert(cert != nil, "sign with 192s succeeded");

	# Verify with 256s key should fail (different algorithm)
	state2 := kr->sha256(msg, len msg, digest, nil);
	ok := kr->verify(pk256, cert, state2);
	t.assert(ok == 0, "cross-level verification fails");
}

testSLHDSA192sStress(t: ref T)
{
	t.log("stress test: 3 iterations of keygen+sign+verify");
	for(i := 0; i < 3; i++){
		sk := kr->genSK("slhdsa192s", "stress", 0);
		t.assert(sk != nil, sys->sprint("iteration %d: genSK", i));
		pk := kr->sktopk(sk);

		msg := array of byte sys->sprint("stress message %d", i);
		digest := array [32] of byte;
		state := kr->sha256(msg, len msg, digest, nil);
		cert := kr->sign(sk, 0, state, "sha256");
		t.assert(cert != nil, sys->sprint("iteration %d: sign", i));

		state2 := kr->sha256(msg, len msg, digest, nil);
		ok := kr->verify(pk, cert, state2);
		t.assert(ok != 0, sys->sprint("iteration %d: verify", i));
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

	sys->fprint(sys->fildes(1), "\n=== SLH-DSA (FIPS 205) Tests ===\n\n");

	run("SLHDSA192s/keygen", testSLHDSA192sKeygen);
	run("SLHDSA192s/sign-verify", testSLHDSA192sSignVerify);
	run("SLHDSA192s/wrong-key", testSLHDSA192sWrongKey);
	run("SLHDSA192s/sig-tamper", testSLHDSA192sSigTamper);
	run("SLHDSA192s/serialization", testSLHDSA192sSerialization);
	run("SLHDSA256s/keygen", testSLHDSA256sKeygen);
	run("SLHDSA256s/sign-verify", testSLHDSA256sSignVerify);
	run("SLHDSA256s/wrong-key", testSLHDSA256sWrongKey);
	run("SLHDSA256s/serialization", testSLHDSA256sSerialization);
	run("SLHDSA/cross-level-reject", testCrossLevelReject);
	run("SLHDSA192s/stress", testSLHDSA192sStress);

	if(testing->summary(passed, failed, skipped) > 0)
		raise "fail:tests failed";
}
