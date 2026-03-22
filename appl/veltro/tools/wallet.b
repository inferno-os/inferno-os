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
		"  wallet network                               Show current network\n" +
		"  wallet network <name>                        Switch network\n" +
		"  wallet pay <account> <wei> <address>         Send ETH (amount in wei)\n" +
		"  wallet pay <account> usdc <amount> <address> Send USDC (amount in base units, 6 decimals)\n\n" +
		"Networks: Ethereum Sepolia, Base Sepolia, Ethereum Mainnet, Base\n\n" +
		"Examples:\n" +
		"  wallet accounts\n" +
		"  wallet balance myaccount\n" +
		"  wallet network Base Sepolia\n" +
		"  wallet pay myaccount 1000 0xRecipientAddress          Send 1000 wei\n" +
		"  wallet pay myaccount usdc 1000000 0xRecipientAddress  Send 1 USDC\n\n" +
		"Notes:\n" +
		"  - ETH amounts are always in wei (1 ETH = 10^18 wei, 1 gwei = 10^9 wei)\n" +
		"  - USDC amounts are in base units (1 USDC = 1000000)\n" +
		"  - Private keys are never exposed to the agent\n" +
		"  - Budget limits are enforced server-side\n";
}

exec(args: string): string
{
	# Normalize: strip wrapping quotes, collapse whitespace
	args = stripquotes(args);
	(nil, toks) := sys->tokenize(args, " \t\n");
	if(toks == nil)
		return "usage: wallet <command> [args]\nRun 'wallet' with no args for help.";

	cmd := hd toks;
	rest := tl toks;

	# Handle doubled command name: "wallet wallet accounts" → "wallet accounts"
	if(cmd == "wallet" && rest != nil) {
		cmd = hd rest;
		rest = tl rest;
	}

	case cmd {
	"accounts" =>
		return doaccounts();
	"address" =>
		if(rest == nil)
			return "error: missing account name\nexample: wallet address myaccount";
		return doread(stripquotes(hd rest), "address");
	"balance" =>
		if(rest == nil)
			return "error: missing account name\nexample: wallet balance myaccount";
		return doread(stripquotes(hd rest), "balance");
	"chain" =>
		if(rest == nil)
			return "error: missing account name\nexample: wallet chain myaccount";
		return doread(stripquotes(hd rest), "chain");
	"sign" =>
		if(rest == nil || tl rest == nil)
			return "error: need account and hash\nexample: wallet sign myaccount a1b2c3...64hexchars";
		return dosign(stripquotes(hd rest), stripquotes(hd tl rest));
	"history" =>
		if(rest == nil)
			return "error: missing account name\nexample: wallet history myaccount";
		return doread(stripquotes(hd rest), "history");
	"pay" =>
		if(rest == nil || tl rest == nil)
			return "error: need account, amount, and recipient\n" +
				"example: wallet pay myaccount 1000 0x742d35Cc6634C0532925a3b844Bc9\n" +
				"example: wallet pay myaccount usdc 1000000 0x742d35Cc6634C0532925a3b844Bc9";
		return dopay(stripquotes(hd rest), tl rest);
	"network" =>
		if(rest == nil)
			return donetwork(nil);
		# Rejoin network name (may have spaces)
		nname := "";
		for(r := rest; r != nil; r = tl r) {
			if(nname != "")
				nname += " ";
			nname += hd r;
		}
		return donetwork(nname);
	"help" =>
		if(rest == nil)
			return doc();
		return cmdhelp(hd rest);
	* =>
		return "error: unknown command '" + cmd + "'\n" +
			"valid commands: accounts, address, balance, chain, history, pay, network, sign\n" +
			"example: wallet accounts";
	}
}

# Strip wrapping double or single quotes from a string
stripquotes(s: string): string
{
	if(s == nil || len s < 2)
		return s;
	if((s[0] == '"' && s[len s - 1] == '"') ||
	   (s[0] == '\'' && s[len s - 1] == '\''))
		return s[1:len s - 1];
	return s;
}

# Focused help for a specific command
cmdhelp(cmd: string): string
{
	case cmd {
	"accounts" =>
		return "wallet accounts\n\nList all wallet account names, one per line.";
	"balance" =>
		return "wallet balance <account>\n\nShow USDC and ETH balance for the named account.\nexample: wallet balance myaccount";
	"pay" =>
		return "wallet pay <account> <wei> <address>\n" +
			"wallet pay <account> usdc <amount> <address>\n\n" +
			"Send ETH (in wei) or USDC (in base units, 6 decimals).\n" +
			"examples:\n" +
			"  wallet pay myaccount 1000 0x742d35Cc...\n" +
			"  wallet pay myaccount usdc 1000000 0x742d35Cc...";
	"network" =>
		return "wallet network\n" +
			"wallet network <name>\n\n" +
			"Show or switch the active network.\n" +
			"Available: Ethereum Sepolia, Base Sepolia, Ethereum Mainnet, Base\n" +
			"example: wallet network Base Sepolia";
	* =>
		return "no specific help for '" + cmd + "'\n" + doc();
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

donetwork(name: string): string
{
	if(name == nil) {
		# Read current network
		s := readfile(WALLET_MOUNT + "/ctl");
		if(s == nil)
			return "cannot read wallet ctl";
		return s;
	}
	# Set network — reconstruct name with spaces for multi-word names
	# e.g. "Base" or "Ethereum Sepolia" or "Base Sepolia"
	n := writefile(WALLET_MOUNT + "/ctl", "network " + name);
	if(n <= 0)
		return sys->sprint("network switch failed: %r");
	return "network set to " + name;
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
