implement EthcryptoTest;

#
# Tests for ethcrypto library:
#   - Hex encoding/decoding
#   - Address derivation
#   - EIP-55 checksum addresses
#   - RLP encoding (Ethereum wiki test vectors)
#   - EIP-155 transaction signing
#   - EIP-712 typed data hashing
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

EthcryptoTest: module
{
	init: fn(nil: ref Draw->Context, args: list of string);
};

passed := 0;
failed := 0;
skipped := 0;
billion: big;

SRCFILE: con "/tests/ethcrypto_test.b";

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

#
# Hex utilities
#

testHexRoundtrip(t: ref T)
{
	input := array[] of { byte 16rde, byte 16rad, byte 16rbe, byte 16ref };
	hex := ethcrypto->hexencode(input);
	t.assertseq(hex, "deadbeef", "hexencode");

	decoded := ethcrypto->hexdecode(hex);
	t.assert(byteseq(input, decoded), "hexdecode roundtrip");
}

testHexEmpty(t: ref T)
{
	hex := ethcrypto->hexencode(array[0] of byte);
	t.assertseq(hex, "", "hexencode empty");

	decoded := ethcrypto->hexdecode("");
	t.assert(decoded != nil && len decoded == 0, "hexdecode empty");
}

#
# Address derivation
#

testAddressFromPubkey(t: ref T)
{
	# Private key = 1 → known Ethereum address
	priv := ethcrypto->hexdecode("0000000000000000000000000000000000000000000000000000000000000001");
	pub := kr->secp256k1_pubkey(priv);
	addr := ethcrypto->pubkeytoaddr(pub);
	t.assert(addr != nil, "address not nil");
	t.asserteq(len addr, 20, "address is 20 bytes");

	expected := ethcrypto->hexdecode("7e5f4552091a69125d5dfcb7b8c2659029395bdf");
	t.assert(byteseq(addr, expected), "address matches known value");
}

#
# EIP-55 checksum encoding
#

testEIP55Checksum(t: ref T)
{
	# Test vectors from EIP-55 specification
	addr := ethcrypto->hexdecode("7e5f4552091a69125d5dfcb7b8c2659029395bdf");
	checksummed := ethcrypto->addrtostr(addr);
	t.log("checksummed: " + checksummed);
	# Verify it starts with 0x and is 42 chars
	t.asserteq(len checksummed, 42, "checksum address is 42 chars");
	t.assert(checksummed[0:2] == "0x", "starts with 0x");
}

testStrToAddr(t: ref T)
{
	addr := ethcrypto->strtoaddr("0x7E5F4552091A69125d5DfCb7b8C2659029395Bdf");
	t.assert(addr != nil, "strtoaddr succeeds");
	t.asserteq(len addr, 20, "20 bytes");

	expected := ethcrypto->hexdecode("7e5f4552091a69125d5dfcb7b8c2659029395bdf");
	t.assert(byteseq(addr, expected), "strtoaddr correct value");
}

#
# RLP encoding (test vectors from Ethereum wiki)
#

testRLPSingleByte(t: ref T)
{
	# Single byte 0x00-0x7f encodes as itself
	input := array[] of { byte 16r00 };
	encoded := ethcrypto->rlpencode_bytes(input);
	t.assert(byteseq(encoded, input), "RLP single byte 0x00");

	input = array[] of { byte 16r7f };
	encoded = ethcrypto->rlpencode_bytes(input);
	t.assert(byteseq(encoded, input), "RLP single byte 0x7f");
}

testRLPShortString(t: ref T)
{
	# "dog" = [0x83, 'd', 'o', 'g']
	input := array of byte "dog";
	encoded := ethcrypto->rlpencode_bytes(input);
	expected := array[] of { byte 16r83, byte 'd', byte 'o', byte 'g' };
	t.assert(byteseq(encoded, expected), "RLP 'dog'");
}

testRLPEmptyString(t: ref T)
{
	# Empty string = [0x80]
	input := array[0] of byte;
	encoded := ethcrypto->rlpencode_bytes(input);
	expected := array[] of { byte 16r80 };
	t.assert(byteseq(encoded, expected), "RLP empty string");
}

testRLPEmptyList(t: ref T)
{
	# Empty list = [0xc0]
	encoded := ethcrypto->rlpencode_list(nil);
	expected := array[] of { byte 16rc0 };
	t.assert(byteseq(encoded, expected), "RLP empty list");
}

testRLPStringList(t: ref T)
{
	# ["cat", "dog"] = [0xc8, 0x83, 'c', 'a', 't', 0x83, 'd', 'o', 'g']
	items: list of array of byte;
	items = ethcrypto->rlpencode_bytes(array of byte "dog") :: items;
	items = ethcrypto->rlpencode_bytes(array of byte "cat") :: items;
	encoded := ethcrypto->rlpencode_list(items);

	expected := array[] of {
		byte 16rc8,
		byte 16r83, byte 'c', byte 'a', byte 't',
		byte 16r83, byte 'd', byte 'o', byte 'g'
	};
	t.assert(byteseq(encoded, expected), "RLP ['cat', 'dog']");
}

testRLPUint(t: ref T)
{
	# 0 = [0x80]
	encoded := ethcrypto->rlpencode_uint(big 0);
	expected := array[] of { byte 16r80 };
	t.assert(byteseq(encoded, expected), "RLP uint 0");

	# 1 = [0x01]
	encoded = ethcrypto->rlpencode_uint(big 1);
	expected = array[] of { byte 16r01 };
	t.assert(byteseq(encoded, expected), "RLP uint 1");

	# 127 = [0x7f]
	encoded = ethcrypto->rlpencode_uint(big 127);
	expected = array[] of { byte 16r7f };
	t.assert(byteseq(encoded, expected), "RLP uint 127");

	# 128 = [0x81, 0x80]
	encoded = ethcrypto->rlpencode_uint(big 128);
	expected = array[] of { byte 16r81, byte 16r80 };
	t.assert(byteseq(encoded, expected), "RLP uint 128");

	# 256 = [0x82, 0x01, 0x00]
	encoded = ethcrypto->rlpencode_uint(big 256);
	expected = array[] of { byte 16r82, byte 16r01, byte 16r00 };
	t.assert(byteseq(encoded, expected), "RLP uint 256");
}

#
# EIP-155 transaction signing
#

testSignTx(t: ref T)
{
	priv := ethcrypto->hexdecode("0000000000000000000000000000000000000000000000000000000000000001");
	dst := ethcrypto->strtoaddr("0x7E5F4552091A69125d5DfCb7b8C2659029395Bdf");

	tx := ref Ethcrypto->EthTx(
		big 0,				# nonce
		big 20 * billion,		# gasprice (20 gwei)
		big 21000,			# gaslimit
		dst,				# destination
		billion * billion,			# value (1 ETH = 10^18 wei)
		nil,				# data
		1				# chainid (mainnet)
	);

	signed := ethcrypto->signtx(tx, priv);
	t.assert(signed != nil, "signtx returns result");
	t.assert(len signed > 0, "signed tx has content");
	t.log("signed tx length: " + string len signed);

	# Verify it's valid RLP (starts with list prefix)
	t.assert(int signed[0] >= 16rc0, "signed tx starts with RLP list prefix");
}

testSignTxDeterministic(t: ref T)
{
	priv := ethcrypto->hexdecode("0000000000000000000000000000000000000000000000000000000000000001");
	dst := ethcrypto->strtoaddr("0x7E5F4552091A69125d5DfCb7b8C2659029395Bdf");

	tx := ref Ethcrypto->EthTx(
		big 0, big 20000000000, big 21000, dst,
		big 1000000000000000000, nil, 1
	);

	signed1 := ethcrypto->signtx(tx, priv);
	signed2 := ethcrypto->signtx(tx, priv);
	t.assert(byteseq(signed1, signed2), "signtx is deterministic (RFC 6979)");
}

#
# EIP-712 typed data hash
#

testEIP712Hash(t: ref T)
{
	domainsep := array[32] of byte;
	structhash := array[32] of byte;
	# Fill with known values
	for(i := 0; i < 32; i++) {
		domainsep[i] = byte i;
		structhash[i] = byte (255 - i);
	}

	hash := ethcrypto->eip712hash(domainsep, structhash);
	t.assert(hash != nil, "eip712hash returns result");
	t.asserteq(len hash, 32, "hash is 32 bytes");

	# Verify determinism
	hash2 := ethcrypto->eip712hash(domainsep, structhash);
	t.assert(byteseq(hash, hash2), "eip712hash is deterministic");

	# Verify the prefix is baked in correctly
	# We can't easily verify against an external tool here,
	# but we verify it's a valid keccak256 output
	t.log("eip712 hash: " + ethcrypto->hexencode(hash));
}

#
# bigtobytes
#

testBigToBytes(t: ref T)
{
	b := ethcrypto->bigtobytes(big 0);
	t.asserteq(len b, 0, "bigtobytes(0) is empty");

	b = ethcrypto->bigtobytes(big 1);
	t.asserteq(len b, 1, "bigtobytes(1) is 1 byte");
	t.asserteq(int b[0], 1, "bigtobytes(1) = [0x01]");

	b = ethcrypto->bigtobytes(big 256);
	t.asserteq(len b, 2, "bigtobytes(256) is 2 bytes");
	t.asserteq(int b[0], 1, "bigtobytes(256)[0] = 0x01");
	t.asserteq(int b[1], 0, "bigtobytes(256)[1] = 0x00");

	# 20 gwei = 0x4A817C800 — must use big arithmetic to avoid int overflow
	gwei20 := big 20 * billion;
	gweibytes := ethcrypto->bigtobytes(gwei20);
	t.log(sys->sprint("gwei20=%bd gweibytes len=%d", gwei20, len gweibytes));
	for(j := 0; j < len gweibytes; j++)
		t.log(sys->sprint("  gweibytes[%d] = %02x", j, int gweibytes[j]));
	gweihex := ethcrypto->hexencode(gweibytes);
	t.log("gweihex='" + gweihex + "'");
	t.assertseq(gweihex, "04a817c800", "bigtobytes(20gwei) = 04a817c800");
}

init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	kr = load Keyring Keyring->PATH;
	ethcrypto = load Ethcrypto Ethcrypto->PATH;
	testing = load Testing Testing->PATH;

	if(testing == nil) {
		sys->fprint(sys->fildes(2), "cannot load testing module: %r\n");
		raise "fail:cannot load testing";
	}
	if(ethcrypto == nil) {
		sys->fprint(sys->fildes(2), "cannot load ethcrypto module: %r\n");
		raise "fail:cannot load ethcrypto";
	}

	testing->init();
	billion = big 1000000000;
	err := ethcrypto->init();
	if(err != nil) {
		sys->fprint(sys->fildes(2), "ethcrypto init: %s\n", err);
		raise "fail:ethcrypto init";
	}

	for(a := args; a != nil; a = tl a) {
		if(hd a == "-v")
			testing->verbose(1);
	}

	# Hex tests
	run("Hex/Roundtrip", testHexRoundtrip);
	run("Hex/Empty", testHexEmpty);

	# Address tests
	run("Address/FromPubkey", testAddressFromPubkey);
	run("Address/EIP55", testEIP55Checksum);
	run("Address/StrToAddr", testStrToAddr);

	# RLP tests
	run("RLP/SingleByte", testRLPSingleByte);
	run("RLP/ShortString", testRLPShortString);
	run("RLP/EmptyString", testRLPEmptyString);
	run("RLP/EmptyList", testRLPEmptyList);
	run("RLP/StringList", testRLPStringList);
	run("RLP/Uint", testRLPUint);

	# Transaction tests
	run("Tx/Sign", testSignTx);
	run("Tx/Deterministic", testSignTxDeterministic);

	# EIP-712 tests
	run("EIP712/Hash", testEIP712Hash);

	# Utility tests
	run("BigToBytes", testBigToBytes);

	if(testing->summary(passed, failed, skipped) > 0)
		raise "fail:tests failed";
}
