implement X402;

#
# x402 payment protocol library.
#
# Implements the x402 v2 specification for HTTP 402 payment flows.
# Parses 402 responses, constructs signed payment payloads,
# and formats PAYMENT-SIGNATURE headers.
#
# References:
#   https://github.com/coinbase/x402
#   specs/x402-specification-v2.md
#   specs/schemes/exact/scheme_exact_evm.md
#

include "sys.m";
	sys: Sys;

include "draw.m";

include "keyring.m";
	kr: Keyring;

include "bufio.m";
	bufio: Bufio;

include "json.m";
	json: JSON;
	JValue: import json;

include "ethcrypto.m";
	ethcrypto: Ethcrypto;

include "x402.m";

init(): string
{
	sys = load Sys Sys->PATH;
	if(sys == nil)
		return "cannot load Sys";
	kr = load Keyring Keyring->PATH;
	if(kr == nil)
		return "cannot load Keyring";
	bufio = load Bufio Bufio->PATH;
	if(bufio == nil)
		return "cannot load Bufio";
	json = load JSON JSON->PATH;
	if(json == nil)
		return "cannot load JSON";
	json->init(bufio);
	ethcrypto = load Ethcrypto Ethcrypto->PATH;
	if(ethcrypto == nil)
		return "cannot load Ethcrypto";
	err := ethcrypto->init();
	if(err != nil)
		return "ethcrypto: " + err;
	return nil;
}

#
# Parse a 402 response body into PaymentRequired.
#
parse402(body: string): (ref PaymentRequired, string)
{
	jv := parsestr(body);
	if(jv == nil)
		return (nil, "invalid JSON in 402 response");

	x402ver := getint(jv, "x402Version");
	errmsg := getstr(jv, "error");

	# Parse resource
	rjv := jv.get("resource");
	resource: ref ResourceInfo;
	if(rjv != nil && rjv.isobject())
		resource = ref ResourceInfo(
			getstr(rjv, "url"),
			getstr(rjv, "description"),
			getstr(rjv, "mimeType")
		);

	# Parse accepts array
	ajv := jv.get("accepts");
	accepts: list of ref PaymentReq;
	if(ajv != nil && ajv.isarray()) {
		pick a := ajv {
		Array =>
			for(i := len a.a - 1; i >= 0; i--) {
				pjv := a.a[i];
				if(pjv != nil && pjv.isobject()) {
					# Parse extra fields
					ejv := pjv.get("extra");
					method := "";
					tname := "";
					tversion := "";
					if(ejv != nil && ejv.isobject()) {
						method = getstr(ejv, "assetTransferMethod");
						tname = getstr(ejv, "name");
						tversion = getstr(ejv, "version");
					}
					pr := ref PaymentReq(
						getstr(pjv, "scheme"),
						getstr(pjv, "network"),
						getstr(pjv, "amount"),
						getstr(pjv, "asset"),
						getstr(pjv, "payTo"),
						getint(pjv, "maxTimeoutSeconds"),
						tname,
						tversion,
						method
					);
					accepts = pr :: accepts;
				}
			}
		}
	}

	return (ref PaymentRequired(x402ver, errmsg, resource, accepts), nil);
}

#
# Select the best payment option matching the given chain.
#
selectoption(pr: ref PaymentRequired, chain: string): ref PaymentReq
{
	if(pr == nil)
		return nil;

	network := chaintonetwork(chain);

	# First pass: exact network match
	for(l := pr.accepts; l != nil; l = tl l) {
		req := hd l;
		if(req.network == network)
			return req;
	}

	# Second pass: any EVM network
	for(l = pr.accepts; l != nil; l = tl l) {
		req := hd l;
		if(len req.network > 7 && req.network[0:7] == "eip155:")
			return req;
	}

	# Fallback: first option
	if(pr.accepts != nil)
		return hd pr.accepts;

	return nil;
}

#
# Build and sign a payment authorization.
#
# Constructs an EIP-3009 authorization:
# 1. Build authorization struct (from, to, value, validAfter, validBefore, nonce)
# 2. Hash with EIP-712 domain separator
# 3. Sign via /n/wallet/{acct}/sign
# 4. Encode as JSON, base64 for PAYMENT-SIGNATURE header
#
authorize(req: ref PaymentReq, resource: ref ResourceInfo,
	  acctname: string): (string, string)
{
	if(req == nil)
		return (nil, "nil payment requirement");

	# Read the wallet address
	addrstr := readfile("/n/wallet/" + acctname + "/address");
	if(addrstr == nil)
		return (nil, "cannot read wallet address for " + acctname);
	addrstr = strip(addrstr);

	# Current time + timeout for validity window
	now := daytime();
	validafter := string now;
	validbefore := string (now + req.timeout);

	# Generate nonce (random 32 bytes, hex-encoded)
	noncebuf := array[32] of byte;
	readrandom(noncebuf);
	nonce := ethcrypto->hexencode(noncebuf);

	# Build EIP-712 domain separator hash
	# Domain: { name: tokenName, version: tokenVersion, chainId, verifyingContract: asset }
	chainid := networktochainid(req.network);
	domainhash := eip712domainhash(req.name, req.version, chainid, req.asset);

	# Build struct hash for TransferWithAuthorization
	# TransferWithAuthorization(address from, address to, uint256 value,
	#   uint256 validAfter, uint256 validBefore, bytes32 nonce)
	structhash := eip712structhash(addrstr, req.payto, req.amount,
		validafter, validbefore, nonce);

	# EIP-712 hash
	msghash := ethcrypto->eip712hash(domainhash, structhash);
	if(msghash == nil)
		return (nil, "EIP-712 hash failed");

	# Sign via wallet9p — use single fd for write then read (same fid)
	hexhash := ethcrypto->hexencode(msghash);
	signpath := "/n/wallet/" + acctname + "/sign";
	fd := sys->open(signpath, Sys->ORDWR);
	if(fd == nil)
		return (nil, sys->sprint("cannot open %s: %r", signpath));
	wb := array of byte hexhash;
	n := sys->write(fd, wb, len wb);
	if(n <= 0)
		return (nil, sys->sprint("sign write failed: %r"));
	# Read back signature on same fd
	rbuf := array[256] of byte;
	sys->seek(fd, big 0, Sys->SEEKSTART);
	rn := sys->read(fd, rbuf, len rbuf);
	if(rn <= 0)
		return (nil, "no signature returned");
	sigstr := string rbuf[0:rn];
	sigstr = strip(sigstr);

	# Build PaymentPayload JSON
	authobj := json->jvobject(
		("from", json->jvstring(addrstr)) ::
		("to", json->jvstring(req.payto)) ::
		("value", json->jvstring(req.amount)) ::
		("validAfter", json->jvstring(validafter)) ::
		("validBefore", json->jvstring(validbefore)) ::
		("nonce", json->jvstring(nonce)) ::
		nil
	);

	payloadobj := json->jvobject(
		("signature", json->jvstring("0x" + sigstr)) ::
		("authorization", authobj) ::
		nil
	);

	resourceobj := json->jvobject(nil);
	if(resource != nil) {
		resourceobj = json->jvobject(
			("url", json->jvstring(resource.url)) ::
			nil
		);
	}

	# Build accepted (echo back the requirement we're paying)
	acceptedobj := json->jvobject(
		("scheme", json->jvstring(req.scheme)) ::
		("network", json->jvstring(req.network)) ::
		("amount", json->jvstring(req.amount)) ::
		("asset", json->jvstring(req.asset)) ::
		("payTo", json->jvstring(req.payto)) ::
		("maxTimeoutSeconds", json->jvint(req.timeout)) ::
		nil
	);

	fullpayload := json->jvobject(
		("x402Version", json->jvint(VERSION)) ::
		("resource", resourceobj) ::
		("accepted", acceptedobj) ::
		("payload", payloadobj) ::
		nil
	);

	payloadjson := fullpayload.text();
	return (payloadjson, nil);
}

#
# Parse settlement response.
#
parsesettlement(body: string): (ref SettlementResp, string)
{
	jv := parsestr(body);
	if(jv == nil)
		return (nil, "invalid JSON in settlement response");

	success := 0;
	sv := jv.get("success");
	if(sv != nil && sv.istrue())
		success = 1;

	return (ref SettlementResp(
		success,
		getstr(jv, "errorReason"),
		getstr(jv, "payer"),
		getstr(jv, "transaction"),
		getstr(jv, "network")
	), nil);
}

#
# Chain name ↔ CAIP-2 network mapping
#

chaintonetwork(chain: string): string
{
	if(chain == "base" || chain == "base-mainnet")
		return "eip155:8453";
	if(chain == "base-sepolia")
		return "eip155:84532";
	if(chain == "ethereum" || chain == "mainnet")
		return "eip155:1";
	if(chain == "ethereum-sepolia" || chain == "sepolia")
		return "eip155:11155111";
	if(chain == "polygon")
		return "eip155:137";
	if(chain == "arbitrum")
		return "eip155:42161";
	if(chain == "optimism")
		return "eip155:10";
	return "eip155:1";	# default to mainnet
}

networktochainid(network: string): int
{
	# Parse "eip155:NNNN" → NNNN
	if(len network > 7 && network[0:7] == "eip155:") {
		rest := network[7:];
		id := 0;
		for(i := 0; i < len rest; i++) {
			c := rest[i];
			if(c >= '0' && c <= '9')
				id = id * 10 + (c - '0');
			else
				break;
		}
		return id;
	}
	return 1;	# default mainnet
}

#
# EIP-712 helpers
#

# Hash the EIP-712 domain separator
# keccak256(abi.encode(typeHash, nameHash, versionHash, chainId, verifyingContract))
eip712domainhash(name: string, version: string, chainid: int, contract: string): array of byte
{
	# EIP712Domain type hash:
	# keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)")
	typehashstr := array of byte "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)";
	typehash := array[32] of byte;
	kr->keccak256(typehashstr, len typehashstr, typehash);

	# keccak256(name)
	namebytes := array of byte name;
	namehash := array[32] of byte;
	kr->keccak256(namebytes, len namebytes, namehash);

	# keccak256(version)
	versionbytes := array of byte version;
	versionhash := array[32] of byte;
	kr->keccak256(versionbytes, len versionbytes, versionhash);

	# chainId as uint256 (32 bytes, big-endian, zero-padded)
	chainidbytes := pad32(ethcrypto->bigtobytes(big chainid));

	# verifyingContract as address (20 bytes, left-padded to 32)
	contractaddr := ethcrypto->strtoaddr(contract);
	contractpadded := pad32addr(contractaddr);

	# Concatenate: typeHash || nameHash || versionHash || chainId || contract
	encoded := array[5 * 32] of byte;
	encoded[0:] = typehash;
	encoded[32:] = namehash;
	encoded[64:] = versionhash;
	encoded[96:] = chainidbytes;
	encoded[128:] = contractpadded;

	result := array[32] of byte;
	kr->keccak256(encoded, len encoded, result);
	return result;
}

# Hash the TransferWithAuthorization struct
eip712structhash(sender: string, recipient: string, value: string,
	validafter: string, validbefore: string, nonce: string): array of byte
{
	# Struct type hash
	typehashstr := array of byte "TransferWithAuthorization(address from,address to,uint256 value,uint256 validAfter,uint256 validBefore,bytes32 nonce)";
	typehash := array[32] of byte;
	kr->keccak256(typehashstr, len typehashstr, typehash);

	# Encode each field as 32-byte ABI-encoded value
	fromaddr := pad32addr(ethcrypto->strtoaddr(sender));
	toaddr := pad32addr(ethcrypto->strtoaddr(recipient));
	valuebytes := pad32(strtobigbytes(value));
	afterbytes := pad32(strtobigbytes(validafter));
	beforebytes := pad32(strtobigbytes(validbefore));

	# nonce is bytes32 (already 32 bytes as hex)
	noncebytes := ethcrypto->hexdecode(nonce);
	if(noncebytes == nil || len noncebytes != 32)
		noncebytes = array[32] of byte;

	# Concatenate
	encoded := array[7 * 32] of byte;
	encoded[0:] = typehash;
	encoded[32:] = fromaddr;
	encoded[64:] = toaddr;
	encoded[96:] = valuebytes;
	encoded[128:] = afterbytes;
	encoded[160:] = beforebytes;
	encoded[192:] = noncebytes;

	result := array[32] of byte;
	kr->keccak256(encoded, len encoded, result);
	return result;
}

# Pad bytes to 32 bytes (left-padded with zeros for uint256)
pad32(b: array of byte): array of byte
{
	r := array[32] of byte;
	for(i := 0; i < 32; i++)
		r[i] = byte 0;
	if(b != nil) {
		off := 32 - len b;
		if(off < 0) off = 0;
		n := len b;
		if(n > 32) n = 32;
		r[off:] = b[0:n];
	}
	return r;
}

# Pad a 20-byte address to 32 bytes (left-padded)
pad32addr(addr: array of byte): array of byte
{
	r := array[32] of byte;
	for(i := 0; i < 32; i++)
		r[i] = byte 0;
	if(addr != nil && len addr == 20)
		r[12:] = addr;
	return r;
}

# Convert decimal string to big-endian bytes
strtobigbytes(s: string): array of byte
{
	if(s == nil || s == "")
		return array[0] of byte;
	v := big 0;
	for(i := 0; i < len s; i++) {
		c := s[i];
		if(c >= '0' && c <= '9')
			v = v * big 10 + big (c - '0');
	}
	return ethcrypto->bigtobytes(v);
}

#
# JSON helpers
#

parsestr(s: string): ref JValue
{
	iob := bufio->sopen(s);
	if(iob == nil)
		return nil;
	(jv, nil) := json->readjson(iob);
	return jv;
}

getstr(jv: ref JValue, field: string): string
{
	v := jv.get(field);
	if(v == nil)
		return "";
	if(v.isstring()) {
		pick sv := v {
		String =>
			return sv.s;
		}
	}
	return v.text();
}

getint(jv: ref JValue, field: string): int
{
	v := jv.get(field);
	if(v == nil)
		return 0;
	if(v.isint()) {
		pick iv := v {
		Int =>
			return int iv.value;
		}
	}
	return 0;
}

#
# File I/O helpers
#

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

strip(s: string): string
{
	while(len s > 0 && (s[len s - 1] == '\n' || s[len s - 1] == '\r' || s[len s - 1] == ' '))
		s = s[0:len s - 1];
	return s;
}

daytime(): int
{
	fd := sys->open("/dev/time", Sys->OREAD);
	if(fd == nil)
		return 0;
	buf := array[64] of byte;
	n := sys->read(fd, buf, len buf);
	if(n <= 0)
		return 0;
	# /dev/time returns microseconds; convert to seconds
	s := string buf[0:n];
	usec := big 0;
	for(i := 0; i < len s; i++) {
		c := s[i];
		if(c >= '0' && c <= '9')
			usec = usec * big 10 + big (c - '0');
	}
	return int (usec / big 1000000);
}

readrandom(buf: array of byte)
{
	fd := sys->open("/dev/random", Sys->OREAD);
	if(fd != nil)
		sys->read(fd, buf, len buf);
}
