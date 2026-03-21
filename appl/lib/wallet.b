implement Wallet;

#
# Wallet library: account management with factotum-backed key storage.
#
# Keys are stored in factotum as:
#   key proto=pass service=wallet-eth-{name} user=key !password={hex-privkey}
#   key proto=pass service=wallet-sol-{name} user=key !password={hex-ed25519-seed}
#   key proto=pass service=wallet-stripe-{name} user=key !password={stripe-secret-key}
#

include "sys.m";
	sys: Sys;

include "keyring.m";
	kr: Keyring;

include "factotum.m";
	factotum: Factotum;

include "ethcrypto.m";
	ethcrypto: Ethcrypto;

include "wallet.m";

# Per-account budget storage (in-memory, keyed by account name)
budgets: list of (string, ref Budget);

init(): string
{
	sys = load Sys Sys->PATH;
	if(sys == nil)
		return "cannot load Sys";
	kr = load Keyring Keyring->PATH;
	if(kr == nil)
		return "cannot load Keyring";
	ethcrypto = load Ethcrypto Ethcrypto->PATH;
	if(ethcrypto == nil)
		return "cannot load Ethcrypto";
	err := ethcrypto->init();
	if(err != nil)
		return "ethcrypto: " + err;
	factotum = load Factotum Factotum->PATH;
	if(factotum == nil)
		return "cannot load Factotum";
	factotum->init();
	return nil;
}

#
# Create a new account: generate keys, store in factotum, return Account.
#
createaccount(name: string, accttype: int, chain: string): (ref Account, string)
{
	if(name == nil || name == "")
		return (nil, "empty account name");

	if(accttype == ACCT_ETH) {
		(priv, pub) := kr->secp256k1_keygen();
		if(priv == nil || pub == nil)
			return (nil, "key generation failed");

		addr := ethcrypto->pubkeytoaddr(pub);
		if(addr == nil) {
			zeroarray(priv);
			return (nil, "address derivation failed");
		}

		err := storekey(name, accttype, priv);
		if(err != nil) {
			zeroarray(priv);
			return (nil, err);
		}
		addrstr := ethcrypto->addrtostr(addr);
		zeroarray(priv);
		return (ref Account(name, accttype, chain, addrstr), nil);
	}

	if(accttype == ACCT_SOL) {
		# Solana uses Ed25519 — 32-byte seed
		seed := array[32] of byte;
		randread(seed);
		err := storekey(name, accttype, seed);
		if(err != nil) {
			zeroarray(seed);
			return (nil, err);
		}
		zeroarray(seed);
		return (ref Account(name, accttype, chain, ""), nil);
	}

	if(accttype == ACCT_STRIPE)
		return (nil, "use importaccount for Stripe (API key required)");

	return (nil, "unknown account type");
}

#
# Import an existing account with a known private key.
#
importaccount(name: string, accttype: int, chain: string, privkey: array of byte): (ref Account, string)
{
	if(name == nil || name == "")
		return (nil, "empty account name");
	if(privkey == nil || len privkey == 0)
		return (nil, "empty private key");

	addrstr := "";

	if(accttype == ACCT_ETH) {
		if(len privkey != 32)
			return (nil, "ETH private key must be 32 bytes");
		pub := kr->secp256k1_pubkey(privkey);
		if(pub == nil)
			return (nil, "public key derivation failed");
		addr := ethcrypto->pubkeytoaddr(pub);
		if(addr == nil)
			return (nil, "address derivation failed");
		addrstr = ethcrypto->addrtostr(addr);
	} else if(accttype == ACCT_SOL) {
		if(len privkey != 32)
			return (nil, "Solana seed must be 32 bytes");
	} else if(accttype == ACCT_STRIPE) {
		addrstr = "stripe:" + name;
	} else
		return (nil, "unknown account type");

	err := storekey(name, accttype, privkey);
	if(err != nil)
		return (nil, err);

	return (ref Account(name, accttype, chain, addrstr), nil);
}

#
# Load an account from factotum (verify key exists, derive address).
#
loadaccount(name: string): (ref Account, string)
{
	if(name == nil || name == "")
		return (nil, "empty account name");

	# Try each account type
	for(atype := ACCT_ETH; atype <= ACCT_STRIPE; atype++) {
		svc := servicekey(name, atype);
		(nil, password) := factotum->getuserpasswd("proto=pass service=" + svc);
		if(password != nil && password != "") {
			chain := "";
			addrstr := "";
			if(atype == ACCT_ETH) {
				chain = "ethereum";
				privkey := ethcrypto->hexdecode(password);
				if(privkey != nil && len privkey == 32) {
					pub := kr->secp256k1_pubkey(privkey);
					addr := ethcrypto->pubkeytoaddr(pub);
					if(addr != nil)
						addrstr = ethcrypto->addrtostr(addr);
					zeroarray(privkey);
				}
			} else if(atype == ACCT_SOL) {
				chain = "solana";
			} else if(atype == ACCT_STRIPE) {
				chain = "stripe";
				addrstr = "stripe:" + name;
			}
			return (ref Account(name, atype, chain, addrstr), nil);
		}
	}
	return (nil, "account not found: " + name);
}

#
# List all wallet accounts from factotum.
#
listaccounts(): list of ref Account
{
	accounts: list of ref Account;

	fd := sys->open("/mnt/factotum/ctl", Sys->OREAD);
	if(fd == nil)
		return nil;

	buf := array[8192] of byte;
	all := "";
	for(;;) {
		n := sys->read(fd, buf, len buf);
		if(n <= 0)
			break;
		all += string buf[0:n];
	}

	# Parse lines looking for service=wallet-*
	line := "";
	for(i := 0; i < len all; i++) {
		if(all[i] == '\n') {
			acct := parsefactotumline(line);
			if(acct != nil)
				accounts = acct :: accounts;
			line = "";
		} else
			line[len line] = all[i];
	}
	if(line != "") {
		acct := parsefactotumline(line);
		if(acct != nil)
			accounts = acct :: accounts;
	}

	return accounts;
}

parsefactotumline(line: string): ref Account
{
	svc := findattr(line, "service");
	if(svc == nil || len svc < 12)
		return nil;

	if(svc[0:7] != "wallet-")
		return nil;

	rest := svc[7:];
	atype := -1;
	name := "";

	if(len rest > 4 && rest[0:4] == "eth-") {
		atype = ACCT_ETH;
		name = rest[4:];
	} else if(len rest > 4 && rest[0:4] == "sol-") {
		atype = ACCT_SOL;
		name = rest[4:];
	} else if(len rest > 7 && rest[0:7] == "stripe-") {
		atype = ACCT_STRIPE;
		name = rest[7:];
	}

	if(atype < 0 || name == "")
		return nil;

	chain := "";
	if(atype == ACCT_ETH)
		chain = "ethereum";
	else if(atype == ACCT_SOL)
		chain = "solana";
	else if(atype == ACCT_STRIPE)
		chain = "stripe";

	return ref Account(name, atype, chain, "");
}

findattr(line: string, attr: string): string
{
	target := attr + "=";
	for(i := 0; i <= len line - len target; i++) {
		if(line[i:i+len target] == target) {
			start := i + len target;
			end := start;
			while(end < len line && line[end] != ' ' && line[end] != '\t')
				end++;
			return line[start:end];
		}
	}
	return nil;
}

#
# Sign a hash using the account's private key.
#
signhash(acct: ref Account, hash: array of byte): (array of byte, string)
{
	if(acct == nil)
		return (nil, "nil account");
	if(hash == nil || len hash == 0)
		return (nil, "empty hash");

	svc := servicekey(acct.name, acct.accttype);
	(nil, password) := factotum->getuserpasswd("proto=pass service=" + svc);
	if(password == nil || password == "")
		return (nil, "no key in factotum for " + acct.name);

	if(acct.accttype == ACCT_ETH) {
		privkey := ethcrypto->hexdecode(password);
		if(privkey == nil || len privkey != 32)
			return (nil, "invalid key in factotum");
		sig := kr->secp256k1_sign(privkey, hash);
		zeroarray(privkey);
		if(sig == nil)
			return (nil, "signing failed");
		return (sig, nil);
	}

	if(acct.accttype == ACCT_SOL) {
		seed := ethcrypto->hexdecode(password);
		if(seed == nil || len seed != 32)
			return (nil, "invalid key in factotum");
		sig := kr->ed25519_sign(seed, hash);
		zeroarray(seed);
		if(sig == nil)
			return (nil, "signing failed");
		return (sig, nil);
	}

	if(acct.accttype == ACCT_STRIPE)
		return (nil, "Stripe accounts don't sign hashes");

	return (nil, "unknown account type");
}

#
# Budget enforcement
#

setbudget(acct: ref Account, b: ref Budget)
{
	if(acct == nil || b == nil)
		return;
	newlist: list of (string, ref Budget);
	for(l := budgets; l != nil; l = tl l) {
		(bname, nil) := hd l;
		if(bname != acct.name)
			newlist = hd l :: newlist;
	}
	budgets = (acct.name, b) :: newlist;
}

checkbudget(acct: ref Account, amount: big): string
{
	if(acct == nil)
		return "nil account";

	b := getbudget(acct.name);
	if(b == nil)
		return nil;

	if(b.maxpertx > big 0 && amount > b.maxpertx)
		return sys->sprint("amount %bd exceeds per-tx limit %bd %s",
			amount, b.maxpertx, b.currency);

	if(b.maxpersess > big 0 && b.spent + amount > b.maxpersess)
		return sys->sprint("amount %bd would exceed session limit %bd %s (spent: %bd)",
			amount, b.maxpersess, b.currency, b.spent);

	return nil;
}

recordspend(acct: ref Account, amount: big)
{
	if(acct == nil)
		return;
	b := getbudget(acct.name);
	if(b != nil)
		b.spent += amount;
}

getbudget(name: string): ref Budget
{
	for(l := budgets; l != nil; l = tl l) {
		(n, b) := hd l;
		if(n == name)
			return b;
	}
	return nil;
}

#
# Internal helpers
#

servicekey(name: string, accttype: int): string
{
	if(accttype == ACCT_ETH)
		return "wallet-eth-" + name;
	if(accttype == ACCT_SOL)
		return "wallet-sol-" + name;
	if(accttype == ACCT_STRIPE)
		return "wallet-stripe-" + name;
	return "wallet-unknown-" + name;
}

storekey(name: string, accttype: int, key: array of byte): string
{
	svc := servicekey(name, accttype);
	hexkey := ethcrypto->hexencode(key);

	cmd := "key proto=pass service=" + svc + " user=key !password=" + hexkey;
	fd := sys->open("/mnt/factotum/ctl", Sys->OWRITE);
	if(fd == nil)
		return sys->sprint("cannot open factotum: %r");

	b := array of byte cmd;
	n := sys->write(fd, b, len b);
	if(n != len b)
		return sys->sprint("factotum write failed: %r");

	return nil;
}

zeroarray(a: array of byte)
{
	if(a == nil)
		return;
	for(i := 0; i < len a; i++)
		a[i] = byte 0;
}

randread(buf: array of byte)
{
	fd := sys->open("/dev/random", Sys->OREAD);
	if(fd != nil)
		sys->read(fd, buf, len buf);
}
