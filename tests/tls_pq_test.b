implement TLSPQTest;

#
# TLS Post-Quantum hybrid key exchange tests
#
# Tests the ML-KEM-768 + X25519 hybrid key exchange components:
#   - ML-KEM-768 keygen produces correct key sizes for TLS key share
#   - Hybrid shared secret derivation (ML-KEM + X25519)
#   - Key size validation for hybrid key share framing
#

include "sys.m";
	sys: Sys;

include "draw.m";

include "keyring.m";
	kr: Keyring;

include "testing.m";
	testing: Testing;
	T: import testing;

TLSPQTest: module
{
	init: fn(nil: ref Draw->Context, args: list of string);
};

passed := 0;
failed := 0;
skipped := 0;

SRCFILE: con "/tests/tls_pq_test.b";

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

# Test that hybrid key share sizes are correct for TLS framing
# Client key share: mlkem_pk(1184) + x25519_pub(32) = 1216 bytes
# Server response: mlkem_ct(1088) + x25519_pub(32) = 1120 bytes
testHybridKeySizes(t: ref T)
{
	(mlkem_pk, mlkem_sk) := kr->mlkem768_keygen();

	# Client key share size = ML-KEM-768 pk + X25519 public key
	x25519_priv := array [32] of byte;
	for(i := 0; i < 32; i++)
		x25519_priv[i] = byte i;
	x25519_pub := kr->x25519_base(x25519_priv);

	client_share_len := len mlkem_pk + len x25519_pub;
	t.asserteq(client_share_len, 1216, "client hybrid key share = 1216 bytes");

	# Simulate server: encapsulate to get ciphertext
	(ct, ss_server) := kr->mlkem768_encaps(mlkem_pk);
	server_share_len := len ct + 32;	# ct + x25519 public key
	t.asserteq(server_share_len, 1120, "server hybrid response = 1120 bytes");
}

# Test hybrid shared secret derivation
# Combined secret = mlkem_ss(32) || x25519_ss(32) = 64 bytes
testHybridSharedSecret(t: ref T)
{
	# ML-KEM-768 keypair (client)
	(mlkem_pk, mlkem_sk) := kr->mlkem768_keygen();

	# X25519 keypair (client)
	client_x25519_priv := array [32] of byte;
	for(i := 0; i < 32; i++)
		client_x25519_priv[i] = byte (i + 1);
	client_x25519_pub := kr->x25519_base(client_x25519_priv);

	# Server side: encapsulate + generate X25519
	(mlkem_ct, mlkem_ss_server) := kr->mlkem768_encaps(mlkem_pk);
	server_x25519_priv := array [32] of byte;
	for(i := 0; i < 32; i++)
		server_x25519_priv[i] = byte (i + 42);
	server_x25519_pub := kr->x25519_base(server_x25519_priv);

	# Server computes X25519 shared secret
	x25519_ss_server := kr->x25519(server_x25519_priv, client_x25519_pub);

	# Client side: decapsulate + X25519
	mlkem_ss_client := kr->mlkem768_decaps(mlkem_sk, mlkem_ct);
	x25519_ss_client := kr->x25519(client_x25519_priv, server_x25519_pub);

	# Both sides should agree on ML-KEM shared secret
	t.assert(byteseq(mlkem_ss_server, mlkem_ss_client), "ML-KEM shared secrets match");

	# Both sides should agree on X25519 shared secret
	t.assert(byteseq(x25519_ss_server, x25519_ss_client), "X25519 shared secrets match");

	# Combined hybrid secret = mlkem_ss || x25519_ss
	t.asserteq(len mlkem_ss_client, 32, "ML-KEM ss = 32 bytes");
	t.asserteq(len x25519_ss_client, 32, "X25519 ss = 32 bytes");

	# Total hybrid shared secret = 64 bytes
	combined_len := len mlkem_ss_client + len x25519_ss_client;
	t.asserteq(combined_len, 64, "hybrid shared secret = 64 bytes");
}

# Test multiple round-trips for consistency
testHybridMultipleRoundTrips(t: ref T)
{
	for(trial := 0; trial < 3; trial++) {
		(pk, sk) := kr->mlkem768_keygen();
		(ct, ss1) := kr->mlkem768_encaps(pk);
		ss2 := kr->mlkem768_decaps(sk, ct);
		t.assert(byteseq(ss1, ss2),
			sys->sprint("round-trip %d: shared secrets match", trial));
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

	run("Hybrid/key-sizes", testHybridKeySizes);
	run("Hybrid/shared-secret", testHybridSharedSecret);
	run("Hybrid/multiple-round-trips", testHybridMultipleRoundTrips);

	if(testing->summary(passed, failed, skipped) > 0)
		raise "fail:tests failed";
}
