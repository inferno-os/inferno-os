implement MLKEMTest;

#
# ML-KEM (FIPS 203) tests
#
# Tests ML-KEM-768 and ML-KEM-1024 key encapsulation:
#   - Key generation produces correct-sized outputs
#   - Encapsulation/decapsulation round-trip yields matching shared secrets
#   - Wrong key decapsulation produces different shared secret (implicit rejection)
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

testMLKEM768Keygen(t: ref T)
{
	(pk, sk) := kr->mlkem768_keygen();
	t.assert(pk != nil, "pk not nil");
	t.assert(sk != nil, "sk not nil");
	t.asserteq(len pk, kr->MLKEM768_PKLEN, "pk length = 1184");
	t.asserteq(len sk, kr->MLKEM768_SKLEN, "sk length = 2400");
}

testMLKEM768RoundTrip(t: ref T)
{
	(pk, sk) := kr->mlkem768_keygen();

	(ct, ss_enc) := kr->mlkem768_encaps(pk);
	t.assert(ct != nil, "ciphertext not nil");
	t.assert(ss_enc != nil, "shared secret not nil");
	t.asserteq(len ct, kr->MLKEM768_CTLEN, "ct length = 1088");
	t.asserteq(len ss_enc, kr->MLKEM768_SSLEN, "ss length = 32");

	ss_dec := kr->mlkem768_decaps(sk, ct);
	t.assert(ss_dec != nil, "decaps shared secret not nil");
	t.asserteq(len ss_dec, kr->MLKEM768_SSLEN, "decaps ss length = 32");

	t.assert(byteseq(ss_enc, ss_dec), "shared secrets match");
}

testMLKEM768WrongKey(t: ref T)
{
	(pk1, sk1) := kr->mlkem768_keygen();
	(pk2, sk2) := kr->mlkem768_keygen();

	# Encapsulate to pk1, try to decaps with sk2
	(ct, ss_enc) := kr->mlkem768_encaps(pk1);
	ss_wrong := kr->mlkem768_decaps(sk2, ct);
	t.assert(ss_wrong != nil, "wrong-key decaps returns non-nil (implicit rejection)");
	t.assert(!byteseq(ss_enc, ss_wrong), "wrong-key shared secret differs");
}

testMLKEM1024Keygen(t: ref T)
{
	(pk, sk) := kr->mlkem1024_keygen();
	t.assert(pk != nil, "pk not nil");
	t.assert(sk != nil, "sk not nil");
	t.asserteq(len pk, kr->MLKEM1024_PKLEN, "pk length = 1568");
	t.asserteq(len sk, kr->MLKEM1024_SKLEN, "sk length = 3168");
}

testMLKEM1024RoundTrip(t: ref T)
{
	(pk, sk) := kr->mlkem1024_keygen();

	(ct, ss_enc) := kr->mlkem1024_encaps(pk);
	t.assert(ct != nil, "ciphertext not nil");
	t.assert(ss_enc != nil, "shared secret not nil");
	t.asserteq(len ct, kr->MLKEM1024_CTLEN, "ct length = 1568");
	t.asserteq(len ss_enc, kr->MLKEM1024_SSLEN, "ss length = 32");

	ss_dec := kr->mlkem1024_decaps(sk, ct);
	t.assert(ss_dec != nil, "decaps shared secret not nil");
	t.assert(byteseq(ss_enc, ss_dec), "shared secrets match");
}

testMLKEM1024WrongKey(t: ref T)
{
	(pk1, sk1) := kr->mlkem1024_keygen();
	(pk2, sk2) := kr->mlkem1024_keygen();

	(ct, ss_enc) := kr->mlkem1024_encaps(pk1);
	ss_wrong := kr->mlkem1024_decaps(sk2, ct);
	t.assert(ss_wrong != nil, "wrong-key decaps returns non-nil (implicit rejection)");
	t.assert(!byteseq(ss_enc, ss_wrong), "wrong-key shared secret differs");
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

	run("MLKEM768/keygen", testMLKEM768Keygen);
	run("MLKEM768/round-trip", testMLKEM768RoundTrip);
	run("MLKEM768/wrong-key", testMLKEM768WrongKey);
	run("MLKEM1024/keygen", testMLKEM1024Keygen);
	run("MLKEM1024/round-trip", testMLKEM1024RoundTrip);
	run("MLKEM1024/wrong-key", testMLKEM1024WrongKey);

	if(testing->summary(passed, failed, skipped) > 0)
		raise "fail:tests failed";
}
