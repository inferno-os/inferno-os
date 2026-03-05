implement SHA3Test;

#
# SHA-3 is tested indirectly through ML-KEM and ML-DSA which use
# SHAKE-128/256 internally. This test verifies the SHA-3 functions
# are accessible through the C library by exercising the PQ crypto
# round-trip (which depends on SHA-3 correctness).
#
# Direct SHA-3 test vectors can be added once SHA-3 is exposed
# through the Keyring module.
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

# SHA-3 is exercised by ML-KEM-768 keygen+encaps+decaps round-trip
testSHA3viaMlkem(t: ref T)
{
	t.log("Testing SHA-3 via ML-KEM-768 round-trip (SHAKE-128/256 used internally)");

	(pk, sk) := kr->mlkem768_keygen();
	t.assert(pk != nil, "ML-KEM-768 keygen produced pk");
	t.assert(sk != nil, "ML-KEM-768 keygen produced sk");
	t.asserteq(len pk, kr->MLKEM768_PKLEN, "pk length");
	t.asserteq(len sk, kr->MLKEM768_SKLEN, "sk length");

	(ct, ss1) := kr->mlkem768_encaps(pk);
	t.assert(ct != nil, "encaps produced ciphertext");
	t.assert(ss1 != nil, "encaps produced shared secret");
	t.asserteq(len ct, kr->MLKEM768_CTLEN, "ct length");
	t.asserteq(len ss1, kr->MLKEM768_SSLEN, "ss length");

	ss2 := kr->mlkem768_decaps(sk, ct);
	t.assert(ss2 != nil, "decaps produced shared secret");

	# Shared secrets must match
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

	if(testing == nil) {
		sys->fprint(sys->fildes(2), "cannot load testing module: %r\n");
		raise "fail:cannot load testing";
	}

	testing->init();

	for(a := args; a != nil; a = tl a) {
		if(hd a == "-v")
			testing->verbose(1);
	}

	run("SHA3-via-MLKEM", testSHA3viaMlkem);

	if(testing->summary(passed, failed, skipped) > 0)
		raise "fail:tests failed";
}
