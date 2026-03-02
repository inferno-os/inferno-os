implement SSLTransportTest;

#
# SSL transport tests — verifies AES-CBC and SHA-256 in the kernel SSL device (#D)
#
# Tests:
# - New algorithms advertised in encalgs/hashalgs
# - AES-256-CBC + SHA-256 data round-trip through pipe
# - AES-128-CBC + SHA-256 data round-trip through pipe
# - AES-256-CBC encryption-only round-trip (no digest)
#

include "sys.m";
	sys: Sys;

include "draw.m";

include "keyring.m";

include "security.m";
	ssl: SSL;

include "testing.m";
	testing: Testing;
	T: import testing;

SSLTransportTest: module
{
	init: fn(nil: ref Draw->Context, args: list of string);
};

SRCFILE: con "/tests/ssl_transport_test.b";

passed := 0;
failed := 0;
skipped := 0;

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

# Read a string from a file descriptor
readstring(fd: ref Sys->FD): string
{
	if(fd == nil)
		return nil;
	buf := array[512] of byte;
	n := sys->read(fd, buf, len buf);
	if(n <= 0)
		return nil;
	return string buf[0:n];
}

# Read algorithm lists from the SSL device by cloning a connection
readalgs(): (list of string, list of string)
{
	# Clone an SSL connection to read its algorithm files
	(rc, nil) := sys->stat("#D");
	if(rc < 0)
		return (nil, nil);
	dir := "#D";
	(rc, nil) = sys->stat("#D/ssl");
	if(rc >= 0)
		dir = "#D/ssl";
	cfd := sys->open(dir+"/clone", Sys->ORDWR);
	if(cfd == nil)
		return (nil, nil);
	slot := readstring(cfd);
	if(slot == nil)
		return (nil, nil);
	sdir := dir + "/" + slot;
	(nil, encalgs) := sys->tokenize(readstring(sys->open(sdir+"/encalgs", Sys->OREAD)), " \t\n");
	(nil, hashalgs) := sys->tokenize(readstring(sys->open(sdir+"/hashalgs", Sys->OREAD)), " \t\n");
	return (encalgs, hashalgs);
}

# Check that new algorithms appear in the SSL device's advertised lists
testAlgorithmAdvertised(t: ref T)
{
	(encalgs, hashalgs) := readalgs();
	if(encalgs == nil) {
		t.skip("cannot read SSL algorithm lists");
		return;
	}

	# Check for aes_128_cbc and aes_256_cbc
	found128 := 0;
	found256 := 0;
	for(el := encalgs; el != nil; el = tl el) {
		if(hd el == "aes_128_cbc")
			found128 = 1;
		if(hd el == "aes_256_cbc")
			found256 = 1;
	}
	t.assert(found128, "aes_128_cbc in encalgs");
	t.assert(found256, "aes_256_cbc in encalgs");

	# Check for sha256
	foundsha := 0;
	for(hl := hashalgs; hl != nil; hl = tl hl) {
		if(hd hl == "sha256")
			foundsha = 1;
	}
	t.assert(foundsha, "sha256 in hashalgs");
}

# Set up two SSL connections over a pipe, configure algorithm, return (side_a, side_b)
# Secret must be long enough for the chosen cipher (48 bytes covers AES-256 + 16-byte IV)
sslpair(t: ref T, alg: string, secret: array of byte): (ref Sys->Connection, ref Sys->Connection)
{
	p := array[2] of ref Sys->FD;
	if(sys->pipe(p) < 0) {
		t.fatal(sys->sprint("pipe failed: %r"));
		return (nil, nil);
	}

	(erra, ca) := ssl->connect(p[0]);
	if(erra != nil) {
		t.fatal("ssl connect side A: " + erra);
		return (nil, nil);
	}

	(errb, cb) := ssl->connect(p[1]);
	if(errb != nil) {
		t.fatal("ssl connect side B: " + errb);
		return (nil, nil);
	}

	# Set secrets on both sides (symmetric: same key for in and out)
	err := ssl->secret(ca, secret, secret);
	if(err != nil) {
		t.fatal("secret side A: " + err);
		return (nil, nil);
	}

	err = ssl->secret(cb, secret, secret);
	if(err != nil) {
		t.fatal("secret side B: " + err);
		return (nil, nil);
	}

	# Set algorithm on both sides
	if(sys->fprint(ca.cfd, "alg %s", alg) < 0) {
		t.fatal(sys->sprint("alg side A: %r"));
		return (nil, nil);
	}
	if(sys->fprint(cb.cfd, "alg %s", alg) < 0) {
		t.fatal(sys->sprint("alg side B: %r"));
		return (nil, nil);
	}

	return (ca, cb);
}

# Write data on one SSL connection, read on the other, compare
roundtrip(t: ref T, alg: string, secret: array of byte, plaintext: array of byte)
{
	(ca, cb) := sslpair(t, alg, secret);
	if(ca == nil)
		return;

	# Spawn reader on side B
	result := chan of (array of byte, string);
	spawn reader(cb.dfd, len plaintext, result);

	# Write plaintext on side A
	n := sys->write(ca.dfd, plaintext, len plaintext);
	if(n != len plaintext) {
		t.fatal(sys->sprint("write: wanted %d, got %d: %r", len plaintext, n));
		return;
	}
	t.log(sys->sprint("wrote %d bytes", n));

	# Read result from side B
	(got, err) := <-result;
	if(err != nil) {
		t.fatal("read side B: " + err);
		return;
	}

	t.asserteq(len got, len plaintext, "received length");

	# Compare byte-by-byte
	for(i := 0; i < len plaintext; i++) {
		if(got[i] != plaintext[i]) {
			t.error(sys->sprint("mismatch at byte %d: got 16r%2.2ux want 16r%2.2ux", i, int got[i], int plaintext[i]));
			return;
		}
	}
	t.log("data verified OK");
}

reader(dfd: ref Sys->FD, expect: int, result: chan of (array of byte, string))
{
	buf := array[expect + 256] of byte;
	total := 0;
	while(total < expect) {
		n := sys->read(dfd, buf[total:], len buf - total);
		if(n <= 0) {
			result <-= (nil, sys->sprint("read returned %d at offset %d: %r", n, total));
			return;
		}
		total += n;
	}
	result <-= (buf[0:total], nil);
}

# 48-byte secret: 32-byte AES-256 key + 16-byte IV
mksecret256(): array of byte
{
	s := array[48] of byte;
	for(i := 0; i < len s; i++)
		s[i] = byte ((i * 37 + 7) % 256);
	return s;
}

# 32-byte secret: 16-byte AES-128 key + 16-byte IV
mksecret128(): array of byte
{
	s := array[32] of byte;
	for(i := 0; i < len s; i++)
		s[i] = byte ((i * 53 + 13) % 256);
	return s;
}

testdata(): array of byte
{
	# 200 bytes of varied data — not a multiple of 16 to exercise padding
	s := array[200] of byte;
	for(i := 0; i < len s; i++)
		s[i] = byte ((i * 71 + 3) % 256);
	return s;
}

# AES-256-CBC + SHA-256 round-trip
testAES256SHA256(t: ref T)
{
	roundtrip(t, "aes_256_cbc sha256", mksecret256(), testdata());
}

# AES-128-CBC + SHA-256 round-trip
testAES128SHA256(t: ref T)
{
	roundtrip(t, "aes_128_cbc sha256", mksecret128(), testdata());
}

# AES-256-CBC encryption only (no digest)
testAES256Only(t: ref T)
{
	roundtrip(t, "aes_256_cbc", mksecret256(), testdata());
}

# SHA-256 digest only (no encryption)
testSHA256Only(t: ref T)
{
	# Secret only needs to be non-empty for digest
	secret := array[20] of byte;
	for(i := 0; i < len secret; i++)
		secret[i] = byte (i + 1);
	roundtrip(t, "sha256", secret, testdata());
}

init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	ssl = load SSL SSL->PATH;
	if(ssl == nil) {
		sys->fprint(sys->fildes(2), "cannot load SSL module: %r\n");
		raise "fail:cannot load SSL";
	}
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

	run("AlgorithmAdvertised", testAlgorithmAdvertised);
	run("AES256_SHA256", testAES256SHA256);
	run("AES128_SHA256", testAES128SHA256);
	run("AES256_Only", testAES256Only);
	run("SHA256_Only", testSHA256Only);

	if(testing->summary(passed, failed, skipped) > 0)
		raise "fail:tests failed";
}
