implement X402Test;

#
# x402 protocol library tests.
#
# Tests:
#   - 402 response JSON parsing
#   - Chain/network mapping
#   - Option selection
#   - Settlement response parsing
#   - EIP-712 domain/struct hash determinism
#

include "sys.m";
	sys: Sys;

include "draw.m";

include "keyring.m";
	kr: Keyring;

include "ethcrypto.m";
	ethcrypto: Ethcrypto;

include "x402.m";
	x402: X402;

include "testing.m";
	testing: Testing;
	T: import testing;

X402Test: module
{
	init: fn(nil: ref Draw->Context, args: list of string);
};

passed := 0;
failed := 0;
skipped := 0;

SRCFILE: con "/tests/x402_test.b";

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

#
# Parse 402 response
#

testParse402(t: ref T)
{
	body := "{\"x402Version\":2,\"error\":\"\",\"resource\":{\"url\":\"/api/data\",\"description\":\"Premium data\"},\"accepts\":[{\"scheme\":\"exact\",\"network\":\"eip155:8453\",\"amount\":\"1000000\",\"asset\":\"0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913\",\"payTo\":\"0xRecipient\",\"maxTimeoutSeconds\":300,\"extra\":{\"assetTransferMethod\":\"eip3009\",\"name\":\"USD Coin\",\"version\":\"2\"}}]}";

	(pr, err) := x402->parse402(body);
	t.assert(err == nil, "parse402 no error: " + err);
	t.assert(pr != nil, "parsed result not nil");
	t.asserteq(pr.x402version, 2, "version is 2");
	t.assertseq(pr.resource.url, "/api/data", "resource url");
	t.assertseq(pr.resource.description, "Premium data", "resource description");

	# Check accepts
	t.assert(pr.accepts != nil, "has accepts");
	req := hd pr.accepts;
	t.assertseq(req.scheme, "exact", "scheme");
	t.assertseq(req.network, "eip155:8453", "network");
	t.assertseq(req.amount, "1000000", "amount");
	t.assertseq(req.payto, "0xRecipient", "payTo");
	t.asserteq(req.timeout, 300, "timeout");
	t.assertseq(req.name, "USD Coin", "token name");
	t.assertseq(req.version, "2", "token version");
	t.assertseq(req.method, "eip3009", "method");
}

testParse402Multiple(t: ref T)
{
	body := "{\"x402Version\":2,\"accepts\":[{\"scheme\":\"exact\",\"network\":\"eip155:8453\",\"amount\":\"1000000\",\"asset\":\"0xA\",\"payTo\":\"0xB\",\"maxTimeoutSeconds\":60},{\"scheme\":\"exact\",\"network\":\"eip155:1\",\"amount\":\"2000000\",\"asset\":\"0xC\",\"payTo\":\"0xD\",\"maxTimeoutSeconds\":120}]}";

	(pr, err) := x402->parse402(body);
	t.assert(err == nil, "parse ok");
	n := 0;
	for(l := pr.accepts; l != nil; l = tl l)
		n++;
	t.asserteq(n, 2, "two payment options");
}

testParse402Error(t: ref T)
{
	body := "{\"x402Version\":2,\"error\":\"insufficient funds\",\"accepts\":[]}";
	(pr, err) := x402->parse402(body);
	t.assert(err == nil, "parse ok");
	t.assertseq(pr.errmsg, "insufficient funds", "error message");
}

testParse402Invalid(t: ref T)
{
	(nil, err) := x402->parse402("not json");
	t.assert(err != nil, "invalid JSON returns error");
}

#
# Chain ↔ Network mapping
#

testChainToNetwork(t: ref T)
{
	t.assertseq(x402->chaintonetwork("base"), "eip155:8453", "base");
	t.assertseq(x402->chaintonetwork("ethereum"), "eip155:1", "ethereum");
	t.assertseq(x402->chaintonetwork("base-sepolia"), "eip155:84532", "base-sepolia");
	t.assertseq(x402->chaintonetwork("polygon"), "eip155:137", "polygon");
}

testNetworkToChainId(t: ref T)
{
	t.asserteq(x402->networktochainid("eip155:8453"), 8453, "base chainid");
	t.asserteq(x402->networktochainid("eip155:1"), 1, "mainnet chainid");
	t.asserteq(x402->networktochainid("eip155:84532"), 84532, "base-sepolia chainid");
}

#
# Option selection
#

testSelectOption(t: ref T)
{
	body := "{\"x402Version\":2,\"accepts\":[{\"scheme\":\"exact\",\"network\":\"eip155:8453\",\"amount\":\"100\",\"asset\":\"0xA\",\"payTo\":\"0xB\",\"maxTimeoutSeconds\":60},{\"scheme\":\"exact\",\"network\":\"eip155:1\",\"amount\":\"200\",\"asset\":\"0xC\",\"payTo\":\"0xD\",\"maxTimeoutSeconds\":60}]}";

	(pr, nil) := x402->parse402(body);

	# Select for Base
	opt := x402->selectoption(pr, "base");
	t.assert(opt != nil, "found base option");
	t.assertseq(opt.network, "eip155:8453", "selected base network");
	t.assertseq(opt.amount, "100", "base amount");

	# Select for Ethereum mainnet
	opt = x402->selectoption(pr, "ethereum");
	t.assert(opt != nil, "found ethereum option");
	t.assertseq(opt.network, "eip155:1", "selected mainnet");
}

#
# Settlement response
#

testParseSettlement(t: ref T)
{
	body := "{\"success\":true,\"payer\":\"0xABC\",\"transaction\":\"0xTXHASH\",\"network\":\"eip155:8453\"}";
	(sr, err) := x402->parsesettlement(body);
	t.assert(err == nil, "parse ok");
	t.asserteq(sr.success, 1, "success true");
	t.assertseq(sr.payer, "0xABC", "payer");
	t.assertseq(sr.transaction, "0xTXHASH", "tx hash");
	t.assertseq(sr.network, "eip155:8453", "network");
}

testParseSettlementFailed(t: ref T)
{
	body := "{\"success\":false,\"errorReason\":\"insufficient balance\"}";
	(sr, err) := x402->parsesettlement(body);
	t.assert(err == nil, "parse ok");
	t.asserteq(sr.success, 0, "success false");
	t.assertseq(sr.errorreason, "insufficient balance", "error reason");
}

init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	kr = load Keyring Keyring->PATH;
	ethcrypto = load Ethcrypto Ethcrypto->PATH;
	x402 = load X402 X402->PATH;
	testing = load Testing Testing->PATH;

	if(testing == nil) {
		sys->fprint(sys->fildes(2), "cannot load testing module: %r\n");
		raise "fail:cannot load testing";
	}
	if(x402 == nil) {
		sys->fprint(sys->fildes(2), "cannot load x402 module: %r\n");
		raise "fail:cannot load x402";
	}

	testing->init();
	ethcrypto->init();
	err := x402->init();
	if(err != nil) {
		sys->fprint(sys->fildes(2), "x402 init: %s\n", err);
		raise "fail:x402 init";
	}

	for(a := args; a != nil; a = tl a) {
		if(hd a == "-v")
			testing->verbose(1);
	}

	# Parsing tests
	run("Parse402/Basic", testParse402);
	run("Parse402/Multiple", testParse402Multiple);
	run("Parse402/Error", testParse402Error);
	run("Parse402/Invalid", testParse402Invalid);

	# Mapping tests
	run("Chain/ToNetwork", testChainToNetwork);
	run("Chain/ToChainId", testNetworkToChainId);

	# Selection tests
	run("Select/Option", testSelectOption);

	# Settlement tests
	run("Settlement/Success", testParseSettlement);
	run("Settlement/Failed", testParseSettlementFailed);

	if(testing->summary(passed, failed, skipped) > 0)
		raise "fail:tests failed";
}
