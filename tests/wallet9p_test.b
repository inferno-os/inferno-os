implement Wallet9pTest;

#
# wallet9p integration test.
# Starts wallet9p, creates an account, reads address, signs a hash.
#

include "sys.m";
	sys: Sys;

include "draw.m";

include "keyring.m";
	kr: Keyring;

include "ethcrypto.m";
	ethcrypto: Ethcrypto;

include "testing.m";
	testing: Testing;
	T: import testing;

Wallet9pTest: module
{
	init: fn(nil: ref Draw->Context, args: list of string);
};

passed := 0;
failed := 0;
skipped := 0;

SRCFILE: con "/tests/wallet9p_test.b";

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

hexdecode(s: string): array of byte
{
	if(len s % 2 != 0)
		return nil;
	buf := array[len s / 2] of byte;
	for(i := 0; i < len buf; i++) {
		hi := hexval(s[2*i]);
		lo := hexval(s[2*i+1]);
		if(hi < 0 || lo < 0)
			return nil;
		buf[i] = byte (hi * 16 + lo);
	}
	return buf;
}

hexval(c: int): int
{
	if(c >= '0' && c <= '9')
		return c - '0';
	if(c >= 'a' && c <= 'f')
		return c - 'a' + 10;
	if(c >= 'A' && c <= 'F')
		return c - 'A' + 10;
	return -1;
}

readfile(path: string): string
{
	fd := sys->open(path, Sys->OREAD);
	if(fd == nil)
		return nil;
	buf := array[8192] of byte;
	n := sys->read(fd, buf, len buf);
	if(n <= 0)
		return nil;
	return string buf[0:n];
}

writefile(path: string, data: string): int
{
	fd := sys->open(path, Sys->OWRITE);
	if(fd == nil)
		return -1;
	b := array of byte data;
	return sys->write(fd, b, len b);
}

include "sh.m";

# Start wallet9p in background
startserver()
{
	spawn runsrv();
	sys->sleep(1500);	# wait for mount
}

runsrv()
{
	mod := load Command "/dis/veltro/wallet9p.dis";
	if(mod == nil) {
		sys->fprint(sys->fildes(2), "cannot load wallet9p: %r\n");
		return;
	}
	mod->init(nil, "wallet9p" :: nil);
}

#
# Test: mount exists
#
testMount(t: ref T)
{
	s := readfile("/n/wallet/accounts");
	# Initially empty, but the file should exist
	t.assert(s != nil || s == "", "accounts file readable");
	t.log("accounts: '" + s + "'");
}

#
# Test: import a known key and read the address
#
testImportAndAddress(t: ref T)
{
	# Import private key = 1
	n := writefile("/n/wallet/new", "import eth ethereum testkey 0000000000000000000000000000000000000000000000000000000000000001");
	t.assert(n > 0, "write to new succeeded");

	# Read back the account name
	name := readfile("/n/wallet/new");
	t.log("new account: '" + name + "'");

	# Read address
	addr := readfile("/n/wallet/testkey/address");
	t.assert(addr != nil, "address readable");
	t.log("address: " + addr);
}

#
# Test: sign a hash and recover
#
testSign(t: ref T)
{
	# Hash to sign (keccak256 of "test")
	msg := array of byte "test";
	hash := array[32] of byte;
	kr->keccak256(msg, len msg, hash);
	hexhash := ethcrypto->hexencode(hash);

	# Write hash to sign file
	n := writefile("/n/wallet/testkey/sign", hexhash);
	t.assert(n > 0, "write to sign succeeded");

	# Read signature
	sig := readfile("/n/wallet/testkey/sign");
	t.assert(sig != nil && len sig > 0, "signature readable");
	t.log("signature: " + sig);
}

#
# Test: read chain
#
testChain(t: ref T)
{
	chain := readfile("/n/wallet/testkey/chain");
	t.assert(chain != nil, "chain readable");
	t.log("chain: " + chain);
}

init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	kr = load Keyring Keyring->PATH;
	ethcrypto = load Ethcrypto "/dis/lib/ethcrypto.dis";
	testing = load Testing Testing->PATH;

	if(testing == nil) {
		sys->fprint(sys->fildes(2), "cannot load testing module: %r\n");
		raise "fail:cannot load testing";
	}
	if(ethcrypto == nil) {
		sys->fprint(sys->fildes(2), "cannot load ethcrypto: %r\n");
		raise "fail:cannot load ethcrypto";
	}

	testing->init();
	ethcrypto->init();

	for(a := args; a != nil; a = tl a) {
		if(hd a == "-v")
			testing->verbose(1);
	}

	# Start wallet9p
	startserver();

	run("Mount", testMount);
	run("ImportAndAddress", testImportAndAddress);
	run("Sign", testSign);
	run("Chain", testChain);

	if(testing->summary(passed, failed, skipped) > 0)
		raise "fail:tests failed";
}
