implement MLDSATest;

#
# ML-DSA (FIPS 204) tests
#
# Tests ML-DSA-65 and ML-DSA-87 digital signatures via Keyring SigAlgVec:
#   - Key generation (genSK) produces valid keys
#   - Sign/verify round-trip works
#   - Wrong-key verification fails
#   - Key serialization (sktostr/strtosk, pktostr/strtopk)
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

MLDSATest: module
{
	init: fn(nil: ref Draw->Context, args: list of string);
};

passed := 0;
failed := 0;
skipped := 0;

SRCFILE: con "/tests/mldsa_test.b";

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

testMLDSA65Keygen(t: ref T)
{
	sk := kr->genSK("mldsa65", "test-owner", 0);
	t.assert(sk != nil, "genSK mldsa65 produced key");
	t.assertseq(sk.sa.name, "mldsa65", "algorithm name");

	pk := kr->sktopk(sk);
	t.assert(pk != nil, "sktopk produced public key");
	t.assertseq(pk.sa.name, "mldsa65", "pk algorithm name");
}

testMLDSA65SignVerify(t: ref T)
{
	sk := kr->genSK("mldsa65", "signer", 0);
	t.assert(sk != nil, "genSK");

	pk := kr->sktopk(sk);
	t.assert(pk != nil, "sktopk");

	# Create a message hash using SHA-256
	msg := array of byte "test message for ML-DSA-65";
	digest := array [32] of byte;
	state := kr->sha256(msg, len msg, digest, nil);

	# Sign
	cert := kr->sign(sk, 0, state, "sha256");
	t.assert(cert != nil, "sign produced certificate");

	# Verify
	state2 := kr->sha256(msg, len msg, digest, nil);
	ok := kr->verify(pk, cert, state2);
	t.assert(ok != 0, "verify succeeded");
}

testMLDSA65WrongKey(t: ref T)
{
	sk1 := kr->genSK("mldsa65", "signer1", 0);
	sk2 := kr->genSK("mldsa65", "signer2", 0);
	pk2 := kr->sktopk(sk2);

	msg := array of byte "test message";
	digest := array [32] of byte;
	state := kr->sha256(msg, len msg, digest, nil);

	cert := kr->sign(sk1, 0, state, "sha256");
	t.assert(cert != nil, "sign produced certificate");

	# Verify with wrong key should fail
	state2 := kr->sha256(msg, len msg, digest, nil);
	ok := kr->verify(pk2, cert, state2);
	t.assert(ok == 0, "verify with wrong key fails");
}

testMLDSA65Serialization(t: ref T)
{
	sk := kr->genSK("mldsa65", "serial-test", 0);
	t.assert(sk != nil, "genSK");

	pk := kr->sktopk(sk);
	t.assert(pk != nil, "sktopk");

	# Serialize and deserialize SK
	skstr := kr->sktostr(sk);
	t.assert(skstr != nil, "sktostr produced string");
	t.assert(len skstr > 0, "sktostr non-empty");

	sk2 := kr->strtosk(skstr);
	t.assert(sk2 != nil, "strtosk parsed key");
	t.assertseq(sk2.sa.name, "mldsa65", "deserialized sk algorithm");

	# Serialize and deserialize PK
	pkstr := kr->pktostr(pk);
	t.assert(pkstr != nil, "pktostr produced string");

	pk2 := kr->strtopk(pkstr);
	t.assert(pk2 != nil, "strtopk parsed key");
	t.assertseq(pk2.sa.name, "mldsa65", "deserialized pk algorithm");

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

testMLDSA87Keygen(t: ref T)
{
	sk := kr->genSK("mldsa87", "test-owner", 0);
	t.assert(sk != nil, "genSK mldsa87 produced key");
	t.assertseq(sk.sa.name, "mldsa87", "algorithm name");

	pk := kr->sktopk(sk);
	t.assert(pk != nil, "sktopk produced public key");
}

testMLDSA87SignVerify(t: ref T)
{
	sk := kr->genSK("mldsa87", "signer", 0);
	t.assert(sk != nil, "genSK");

	pk := kr->sktopk(sk);
	t.assert(pk != nil, "sktopk");

	msg := array of byte "test message for ML-DSA-87";
	digest := array [32] of byte;
	state := kr->sha256(msg, len msg, digest, nil);

	cert := kr->sign(sk, 0, state, "sha256");
	t.assert(cert != nil, "sign produced certificate");

	state2 := kr->sha256(msg, len msg, digest, nil);
	ok := kr->verify(pk, cert, state2);
	t.assert(ok != 0, "verify succeeded");
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

	run("MLDSA65/keygen", testMLDSA65Keygen);
	run("MLDSA65/sign-verify", testMLDSA65SignVerify);
	run("MLDSA65/wrong-key", testMLDSA65WrongKey);
	run("MLDSA65/serialization", testMLDSA65Serialization);
	run("MLDSA87/keygen", testMLDSA87Keygen);
	run("MLDSA87/sign-verify", testMLDSA87SignVerify);

	if(testing->summary(passed, failed, skipped) > 0)
		raise "fail:tests failed";
}
