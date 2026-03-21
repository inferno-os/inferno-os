implement Ethcrypto;

#
# Ethereum cryptographic utilities.
# Faithful translation of go-ethereum's crypto/crypto.go and rlp/encode.go.
#
# Provides:
#   - Ethereum address derivation from secp256k1 public keys
#   - EIP-55 mixed-case checksum addresses
#   - RLP encoding (Recursive Length Prefix)
#   - EIP-155 transaction signing
#   - EIP-712 typed data hashing
#

include "sys.m";
	sys: Sys;

include "keyring.m";
	kr: Keyring;

include "ethcrypto.m";

init(): string
{
	sys = load Sys Sys->PATH;
	if(sys == nil)
		return "cannot load Sys";
	kr = load Keyring Keyring->PATH;
	if(kr == nil)
		return "cannot load Keyring";
	return nil;
}

#
# Address derivation (go-ethereum: crypto.PubkeyToAddress)
#
# addr = keccak256(pubkey[1:])[12:]
# pubkey must be 65-byte uncompressed (0x04 || x || y)
#
pubkeytoaddr(pub: array of byte): array of byte
{
	if(pub == nil || len pub != 65 || pub[0] != byte 16r04)
		return nil;
	hash := array[32] of byte;
	kr->keccak256(pub[1:], 64, hash);
	addr := array[20] of byte;
	addr[0:] = hash[12:32];
	return addr;
}

#
# EIP-55 mixed-case checksum address encoding
# (go-ethereum: common.Address.Hex)
#
# 1. Lowercase hex-encode the 20-byte address
# 2. Keccak-256 hash the lowercase hex string
# 3. For each hex digit: if corresponding hash nibble >= 8, uppercase it
#
addrtostr(addr: array of byte): string
{
	if(addr == nil || len addr != 20)
		return "";

	# lowercase hex
	hex := "";
	for(i := 0; i < 20; i++)
		hex += sys->sprint("%02x", int addr[i]);

	# hash of lowercase hex
	hexbytes := array of byte hex;
	hash := array[32] of byte;
	kr->keccak256(hexbytes, len hexbytes, hash);

	# apply checksum
	result := "0x";
	for(i = 0; i < 40; i++) {
		# get hash nibble at position i
		hashbyte := hash[i/2];
		nibble: int;
		if(i % 2 == 0)
			nibble = int hashbyte >> 4;
		else
			nibble = int hashbyte & 16rf;

		c := hex[i];
		if(nibble >= 8 && c >= 'a' && c <= 'f')
			c = c - 'a' + 'A';
		result[len result] = c;
	}
	return result;
}

#
# Parse hex address string to 20 bytes
#
strtoaddr(s: string): array of byte
{
	# strip 0x prefix
	if(len s >= 2 && s[0] == '0' && (s[1] == 'x' || s[1] == 'X'))
		s = s[2:];
	if(len s != 40)
		return nil;
	return hexdecode(s);
}

#
# RLP encoding (go-ethereum: rlp/encode.go)
#
# Rules:
#   - Single byte [0x00, 0x7f]: itself
#   - String 0-55 bytes: 0x80+len, then string
#   - String >55 bytes: 0xb7+len-of-len, then len, then string
#   - List 0-55 bytes: 0xc0+len, then concatenated items
#   - List >55 bytes: 0xf7+len-of-len, then len, then items
#

rlpencode_bytes(s: array of byte): array of byte
{
	if(s == nil)
		s = array[0] of byte;

	slen := len s;

	# single byte
	if(slen == 1 && s[0] <= byte 16r7f)
		return s;

	# short string (0-55 bytes)
	if(slen <= 55) {
		r := array[1 + slen] of byte;
		r[0] = byte (16r80 + slen);
		r[1:] = s;
		return r;
	}

	# long string (>55 bytes)
	lenb := encodelen(slen);
	r := array[1 + len lenb + slen] of byte;
	r[0] = byte (16rb7 + len lenb);
	r[1:] = lenb;
	r[1 + len lenb:] = s;
	return r;
}

rlpencode_list(items: list of array of byte): array of byte
{
	# concatenate all items
	total := 0;
	for(l := items; l != nil; l = tl l)
		total += len hd l;

	payload := array[total] of byte;
	off := 0;
	for(l = items; l != nil; l = tl l) {
		item := hd l;
		payload[off:] = item;
		off += len item;
	}

	# short list (0-55 bytes)
	if(total <= 55) {
		r := array[1 + total] of byte;
		r[0] = byte (16rc0 + total);
		r[1:] = payload;
		return r;
	}

	# long list (>55 bytes)
	lenb := encodelen(total);
	r := array[1 + len lenb + total] of byte;
	r[0] = byte (16rf7 + len lenb);
	r[1:] = lenb;
	r[1 + len lenb:] = payload;
	return r;
}

#
# RLP-encode an unsigned integer.
# Integers are big-endian with no leading zeros.
# Zero is encoded as empty string (0x80).
#
rlpencode_uint(v: big): array of byte
{
	if(v == big 0)
		return array[] of { byte 16r80 };

	b := bigtobytes(v);
	return rlpencode_bytes(b);
}

# Encode a length as big-endian bytes (no leading zeros)
encodelen(n: int): array of byte
{
	if(n < 256)
		return array[] of { byte n };
	if(n < 65536)
		return array[] of { byte (n >> 8), byte n };
	if(n < 16777216)
		return array[] of { byte (n >> 16), byte (n >> 8), byte n };
	return array[] of { byte (n >> 24), byte (n >> 16), byte (n >> 8), byte n };
}

#
# Big-endian encoding of big int (minimal bytes, no leading zeros)
#
bigtobytes(v: big): array of byte
{
	if(v == big 0)
		return array[0] of byte;

	# find number of bytes needed
	nbytes := 0;
	tmp := v;
	while(tmp > big 0) {
		nbytes++;
		tmp = tmp >> 8;
	}

	b := array[nbytes] of byte;
	for(i := nbytes - 1; i >= 0; i--) {
		b[i] = byte (v & big 16rff);
		v = v >> 8;
	}
	return b;
}

#
# EIP-155 transaction signing
# (go-ethereum: core/types/transaction_signing.go)
#
# 1. RLP-encode [nonce, gasprice, gaslimit, to, value, data, chainid, 0, 0]
# 2. Keccak-256 hash the RLP
# 3. secp256k1_sign(privkey, hash) -> sig[65]
# 4. Extract r, s, v; adjust v = sig[64] + chainid*2 + 35
# 5. RLP-encode [nonce, gasprice, gaslimit, to, value, data, v, r, s]
#
signtx(tx: ref EthTx, privkey: array of byte): array of byte
{
	if(tx == nil || privkey == nil || len privkey != 32)
		return nil;

	dstbytes := tx.dst;
	if(dstbytes == nil)
		dstbytes = array[0] of byte;

	databytes := tx.data;
	if(databytes == nil)
		databytes = array[0] of byte;

	# Build unsigned tx fields for signing hash
	fields: list of array of byte;
	fields = rlpencode_uint(big tx.chainid) :: fields;
	fields = rlpencode_uint(big 0) :: fields;		# empty r
	fields = rlpencode_uint(big 0) :: fields;		# empty s
	fields = rlpencode_bytes(databytes) :: fields;
	fields = rlpencode_uint(tx.value) :: fields;
	fields = rlpencode_bytes(dstbytes) :: fields;
	fields = rlpencode_uint(tx.gaslimit) :: fields;
	fields = rlpencode_uint(tx.gasprice) :: fields;
	fields = rlpencode_uint(tx.nonce) :: fields;
	# reverse to get correct order
	ordered: list of array of byte;
	for(; fields != nil; fields = tl fields)
		ordered = hd fields :: ordered;

	unsigned := rlpencode_list(ordered);

	# Keccak-256 hash for signing
	hash := array[32] of byte;
	kr->keccak256(unsigned, len unsigned, hash);

	# Sign
	sig := kr->secp256k1_sign(privkey, hash);
	if(sig == nil || len sig != 65)
		return nil;

	# Extract r, s (32 bytes each), v (1 byte)
	rbytes := sig[0:32];
	sbytes := sig[32:64];
	recid := int sig[64];

	# EIP-155: v = recid + chainid*2 + 35
	v := big (recid + tx.chainid * 2 + 35);

	# Build signed tx
	signed: list of array of byte;
	signed = rlpencode_bytes(sbytes) :: signed;
	signed = rlpencode_bytes(rbytes) :: signed;
	signed = rlpencode_uint(v) :: signed;
	signed = rlpencode_bytes(databytes) :: signed;
	signed = rlpencode_uint(tx.value) :: signed;
	signed = rlpencode_bytes(dstbytes) :: signed;
	signed = rlpencode_uint(tx.gaslimit) :: signed;
	signed = rlpencode_uint(tx.gasprice) :: signed;
	signed = rlpencode_uint(tx.nonce) :: signed;
	# reverse
	signedordered: list of array of byte;
	for(; signed != nil; signed = tl signed)
		signedordered = hd signed :: signedordered;

	return rlpencode_list(signedordered);
}

#
# EIP-712 typed data hash
# hash = keccak256(0x19 || 0x01 || domainSep || structHash)
#
eip712hash(domainsep: array of byte, structhash: array of byte): array of byte
{
	if(domainsep == nil || len domainsep != 32 ||
	   structhash == nil || len structhash != 32)
		return nil;

	msg := array[2 + 32 + 32] of byte;
	msg[0] = byte 16r19;
	msg[1] = byte 16r01;
	msg[2:] = domainsep;
	msg[34:] = structhash;

	hash := array[32] of byte;
	kr->keccak256(msg, len msg, hash);
	return hash;
}

#
# Hex utilities
#

hexencode(b: array of byte): string
{
	if(b == nil)
		return "";
	s := "";
	for(i := 0; i < len b; i++)
		s += sys->sprint("%02x", int b[i]);
	return s;
}

hexdecode(s: string): array of byte
{
	if(len s % 2 != 0)
		return nil;
	# strip 0x prefix
	if(len s >= 2 && s[0] == '0' && (s[1] == 'x' || s[1] == 'X'))
		s = s[2:];
	buf := array[len s / 2] of byte;
	for(i := 0; i < len buf; i++) {
		hi := hextoval(s[2*i]);
		lo := hextoval(s[2*i+1]);
		if(hi < 0 || lo < 0)
			return nil;
		buf[i] = byte (hi * 16 + lo);
	}
	return buf;
}

hextoval(c: int): int
{
	if(c >= '0' && c <= '9')
		return c - '0';
	if(c >= 'a' && c <= 'f')
		return c - 'a' + 10;
	if(c >= 'A' && c <= 'F')
		return c - 'A' + 10;
	return -1;
}
