implement Ethrpc;

#
# Ethereum JSON-RPC client.
#
# Speaks the standard Ethereum JSON-RPC API over HTTPS.
# Used by wallet9p for balance queries and transaction submission.
#
# Default endpoint: https://sepolia.base.org (Base Sepolia testnet)
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

include "webclient.m";
	webclient: Webclient;
	Header, Response: import webclient;

include "ethrpc.m";

rpcurl: string;
reqid: int;

init(url: string): string
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
	webclient = load Webclient Webclient->PATH;
	if(webclient == nil)
		return "cannot load Webclient";
	err := webclient->init();
	if(err != nil)
		return "webclient: " + err;

	if(url == nil || url == "")
		url = "https://sepolia.base.org";
	rpcurl = url;
	reqid = 1;
	return nil;
}

setrpc(url: string)
{
	rpcurl = url;
}

#
# eth_chainId
#
chainid(): (int, string)
{
	(result, err) := rpccall("eth_chainId", "[]");
	if(err != nil)
		return (0, err);
	return (hexnum(getresultstr(result)), nil);
}

#
# eth_getBalance
# Returns wei as decimal string
#
getbalance(addr: string): (string, string)
{
	params := "[\"" + addr + "\",\"latest\"]";
	(result, err) := rpccall("eth_getBalance", params);
	if(err != nil)
		return (nil, err);
	hex := getresultstr(result);
	return (hextowei(hex), nil);
}

#
# ERC-20 balanceOf via eth_call
# Returns token units as decimal string
#
tokenbalance(token: string, addr: string): (string, string)
{
	# balanceOf(address) = 0x70a08231 + address padded to 32 bytes
	paddedaddr := padaddr(addr);
	calldata := "0x70a08231" + paddedaddr;

	(result, err) := ethcall(calldata, token);
	if(err != nil)
		return (nil, err);
	return (hextowei(result), nil);
}

#
# eth_getTransactionCount (nonce)
#
getnonce(addr: string): (int, string)
{
	params := "[\"" + addr + "\",\"latest\"]";
	(result, err) := rpccall("eth_getTransactionCount", params);
	if(err != nil)
		return (0, err);
	return (hexnum(getresultstr(result)), nil);
}

#
# eth_sendRawTransaction
#
sendrawtx(rawtx: string): (string, string)
{
	hexdata := rawtx;
	if(len hexdata < 2 || hexdata[0:2] != "0x")
		hexdata = "0x" + hexdata;
	params := "[\"" + hexdata + "\"]";
	(result, err) := rpccall("eth_sendRawTransaction", params);
	if(err != nil)
		return (nil, err);
	return (getresultstr(result), nil);
}

#
# eth_getTransactionReceipt
#
getreceipt(txhash: string): (ref TxReceipt, string)
{
	params := "[\"" + txhash + "\"]";
	(result, err) := rpccall("eth_getTransactionReceipt", params);
	if(err != nil)
		return (nil, err);

	rv := getresult(result);
	if(rv == nil || rv.isnull())
		return (nil, nil);	# pending — no receipt yet

	status := hexnum(jvgetstr(rv, "status"));
	blocknumber := jvgetstr(rv, "blockNumber");
	gasused := jvgetstr(rv, "gasUsed");

	return (ref TxReceipt(status, txhash, blocknumber, gasused), nil);
}

#
# Poll for receipt
#
waitreceipt(txhash: string, timeoutsec: int): (ref TxReceipt, string)
{
	# Poll every 2 seconds
	polls := timeoutsec / 2;
	if(polls < 1)
		polls = 1;

	for(i := 0; i < polls; i++) {
		(receipt, err) := getreceipt(txhash);
		if(err != nil)
			return (nil, err);
		if(receipt != nil)
			return (receipt, nil);
		sys->sleep(2000);
	}
	return (nil, "timeout waiting for receipt: " + txhash);
}

#
# eth_call (generic contract read)
#
ethcall(calldata: string, contract: string): (string, string)
{
	params := "[{\"to\":\"" + contract + "\",\"data\":\"" + calldata + "\"},\"latest\"]";
	(result, err) := rpccall("eth_call", params);
	if(err != nil)
		return (nil, err);
	return (getresultstr(result), nil);
}

#
# Hex/decimal conversions
#

# 0x hex → decimal string (for wei values up to 2^63)
hextowei(hex: string): string
{
	if(hex == nil || hex == "" || hex == "0x0" || hex == "0x")
		return "0";
	s := hex;
	if(len s >= 2 && s[0:2] == "0x")
		s = s[2:];
	# Strip leading zeros
	while(len s > 1 && s[0] == '0')
		s = s[1:];
	if(s == "" || s == "0")
		return "0";

	# Convert hex to big, then to decimal string
	v := big 0;
	for(i := 0; i < len s; i++) {
		c := s[i];
		d := 0;
		if(c >= '0' && c <= '9')
			d = c - '0';
		else if(c >= 'a' && c <= 'f')
			d = c - 'a' + 10;
		else if(c >= 'A' && c <= 'F')
			d = c - 'A' + 10;
		v = v * big 16 + big d;
	}
	return sys->sprint("%bd", v);
}

# Decimal string → 0x hex
weitohex(wei: string): string
{
	if(wei == nil || wei == "" || wei == "0")
		return "0x0";
	v := big 0;
	for(i := 0; i < len wei; i++) {
		c := wei[i];
		if(c >= '0' && c <= '9')
			v = v * big 10 + big (c - '0');
	}
	if(v == big 0)
		return "0x0";

	# Convert to hex
	hex := "";
	while(v > big 0) {
		d := int (v & big 16rf);
		if(d < 10)
			hex[len hex] = '0' + d;
		else
			hex[len hex] = 'a' + d - 10;
		v = v >> 4;
	}
	# Reverse
	result := "0x";
	for(i = len hex - 1; i >= 0; i--)
		result[len result] = hex[i];
	return result;
}

# Wei → ETH string (18 decimal places, trimmed)
weitoeth(wei: string): string
{
	return weitotoken(wei, 18);
}

# Wei → token string with given decimals
weitotoken(wei: string, decimals: int): string
{
	if(wei == nil || wei == "" || wei == "0")
		return "0";

	# Pad to at least decimals+1 digits
	s := wei;
	while(len s <= decimals)
		s = "0" + s;

	# Insert decimal point
	intpart := s[0:len s - decimals];
	fracpart := s[len s - decimals:];

	# Trim trailing zeros from fraction
	while(len fracpart > 1 && fracpart[len fracpart - 1] == '0')
		fracpart = fracpart[0:len fracpart - 1];

	if(fracpart == "0")
		return intpart;
	return intpart + "." + fracpart;
}

#
# JSON-RPC call
#
rpccall(method: string, params: string): (ref JValue, string)
{
	id := reqid++;
	body := "{\"jsonrpc\":\"2.0\",\"method\":\"" + method +
		"\",\"params\":" + params +
		",\"id\":" + string id + "}";

	hdrs := Header("Content-Type", "application/json") :: nil;
	(resp, err) := webclient->request("POST", rpcurl, hdrs, array of byte body);
	if(err != nil)
		return (nil, method + ": " + err);
	if(resp.statuscode != 200)
		return (nil, sys->sprint("%s: HTTP %d", method, resp.statuscode));

	jv := parsejson(string resp.body);
	if(jv == nil)
		return (nil, method + ": invalid JSON response");

	# Check for JSON-RPC error
	errobj := jv.get("error");
	if(errobj != nil && errobj.isobject()) {
		emsg := jvgetstr(errobj, "message");
		return (nil, method + ": " + emsg);
	}

	return (jv, nil);
}

#
# JSON helpers
#

parsejson(s: string): ref JValue
{
	iob := bufio->sopen(s);
	if(iob == nil)
		return nil;
	(jv, nil) := json->readjson(iob);
	return jv;
}

getresult(jv: ref JValue): ref JValue
{
	if(jv == nil)
		return nil;
	return jv.get("result");
}

getresultstr(jv: ref JValue): string
{
	rv := getresult(jv);
	if(rv == nil)
		return "";
	if(rv.isstring()) {
		pick sv := rv {
		String => return sv.s;
		}
	}
	return rv.text();
}

jvgetstr(jv: ref JValue, field: string): string
{
	v := jv.get(field);
	if(v == nil)
		return "";
	if(v.isstring()) {
		pick sv := v {
		String => return sv.s;
		}
	}
	return v.text();
}

# Parse 0x hex to int
hexnum(s: string): int
{
	if(s == nil || s == "")
		return 0;
	if(len s >= 2 && s[0:2] == "0x")
		s = s[2:];
	v := 0;
	for(i := 0; i < len s; i++) {
		c := s[i];
		if(c >= '0' && c <= '9')
			v = v * 16 + (c - '0');
		else if(c >= 'a' && c <= 'f')
			v = v * 16 + (c - 'a' + 10);
		else if(c >= 'A' && c <= 'F')
			v = v * 16 + (c - 'A' + 10);
	}
	return v;
}

# Pad an address to 32 bytes (64 hex chars), left-padded with zeros
# Input: "0xABCD..." → output: "000000000000000000000000ABCD..."
padaddr(addr: string): string
{
	s := addr;
	if(len s >= 2 && s[0:2] == "0x")
		s = s[2:];
	while(len s < 64)
		s = "0" + s;
	return s;
}
