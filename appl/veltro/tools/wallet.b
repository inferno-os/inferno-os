implement ToolWallet;

#
# wallet - Veltro tool for cryptocurrency and fiat payments
#
# Provides wallet operations to Veltro agents via the wallet9p
# filesystem at /n/wallet/.  The agent writes commands, the tool
# reads/writes the appropriate wallet9p files.
#
# The agent NEVER sees private keys — signing happens inside
# wallet9p, which retrieves keys from factotum.
#
# Usage:
#   wallet accounts                    List all wallet accounts
#   wallet address <account>           Show public address
#   wallet balance <account>           Show balance
#   wallet chain <account>             Show chain name
#   wallet sign <account> <hexhash>    Sign a 32-byte hash (hex-encoded)
#   wallet history <account>           Show recent transactions
#   wallet pay <account> <args>        Execute a payment (not yet implemented)
#

include "sys.m";
	sys: Sys;

include "draw.m";

include "string.m";
	str: String;

include "../tool.m";

ToolWallet: module {
	init: fn(): string;
	name: fn(): string;
	doc:  fn(): string;
	exec: fn(args: string): string;
};

WALLET_MOUNT: con "/n/wallet";

init(): string
{
	sys = load Sys Sys->PATH;
	if(sys == nil)
		return "cannot load Sys";
	str = load String String->PATH;
	if(str == nil)
		return "cannot load String";
	return nil;
}

name(): string
{
	return "wallet";
}

doc(): string
{
	return "Wallet - Cryptocurrency and fiat payment operations\n\n" +
		"Usage:\n" +
		"  wallet accounts                              List all wallet accounts\n" +
		"  wallet address <account>                     Show public address\n" +
		"  wallet balance <account>                     Show balance (USDC + ETH)\n" +
		"  wallet chain <account>                       Show blockchain network\n" +
		"  wallet history <account>                     Show recent transactions\n" +
		"  wallet pay <account> <wei> <address>         Send ETH (amount in wei)\n" +
		"  wallet pay <account> usdc <amount> <address> Send USDC (amount in base units, 6 decimals)\n\n" +
		"Examples:\n" +
		"  wallet pay myaccount 1000 0xRecipientAddress          Send 1000 wei\n" +
		"  wallet pay myaccount 1000000 0xRecipientAddress       Send 0.001 gwei\n" +
		"  wallet pay myaccount usdc 1000000 0xRecipientAddress  Send 1 USDC\n\n" +
		"Notes:\n" +
		"  - ETH amounts are always in wei (1 ETH = 10^18 wei, 1 gwei = 10^9 wei)\n" +
		"  - USDC amounts are in base units (1 USDC = 1000000)\n" +
		"  - Private keys are never exposed to the agent\n" +
		"  - Budget limits are enforced server-side\n";
}

exec(args: string): string
{
	(nil, toks) := sys->tokenize(args, " \t\n");
	if(toks == nil)
		return "usage: wallet <command> [args]\nRun 'wallet' with no args for help.";

	cmd := hd toks;
	rest := tl toks;

	case cmd {
	"accounts" =>
		return doaccounts();
	"address" =>
		if(rest == nil)
			return "usage: wallet address <account>";
		return doread(hd rest, "address");
	"balance" =>
		if(rest == nil)
			return "usage: wallet balance <account>";
		return doread(hd rest, "balance");
	"chain" =>
		if(rest == nil)
			return "usage: wallet chain <account>";
		return doread(hd rest, "chain");
	"sign" =>
		if(rest == nil || tl rest == nil)
			return "usage: wallet sign <account> <hexhash>";
		return dosign(hd rest, hd tl rest);
	"history" =>
		if(rest == nil)
			return "usage: wallet history <account>";
		return doread(hd rest, "history");
	"pay" =>
		if(rest == nil || tl rest == nil)
			return "usage: wallet pay <account> <amount> <recipient>\n" +
				"       wallet pay <account> usdc <amount> <recipient>";
		return dopay(hd rest, tl rest);
	* =>
		return "unknown wallet command: " + cmd + "\n" + doc();
	}
}

doaccounts(): string
{
	s := readfile(WALLET_MOUNT + "/accounts");
	if(s == nil || s == "")
		return "no accounts configured. Use 'keyring' to add wallet credentials.";
	return s;
}

doread(acct: string, file: string): string
{
	path := WALLET_MOUNT + "/" + acct + "/" + file;
	s := readfile(path);
	if(s == nil)
		return sys->sprint("cannot read %s: %r", path);
	return str->take(s, "^\n") ;
}

dosign(acct: string, hexhash: string): string
{
	# Validate hex hash looks reasonable
	if(len hexhash != 64)
		return "hash must be 64 hex characters (32 bytes)";

	# Write hash to sign file
	path := WALLET_MOUNT + "/" + acct + "/sign";
	n := writefile(path, hexhash);
	if(n <= 0)
		return sys->sprint("sign failed: %r");

	# Read back signature
	sig := readfile(path);
	if(sig == nil || sig == "")
		return "no signature returned";

	return str->take(sig, "^\n");
}

dopay(acct: string, args: list of string): string
{
	# Build pay command: join remaining args
	cmd := "";
	for(; args != nil; args = tl args) {
		if(cmd != "")
			cmd += " ";
		cmd += hd args;
	}

	path := WALLET_MOUNT + "/" + acct + "/pay";
	n := writefile(path, cmd);
	if(n <= 0)
		return sys->sprint("pay failed: %r");

	# Read back txhash
	result := readfile(path);
	if(result == nil || result == "")
		return "transaction submitted (no hash returned)";
	return "tx: " + str->take(result, "^\n");
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
