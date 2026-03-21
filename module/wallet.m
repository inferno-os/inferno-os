Wallet: module {
	PATH:	con "/dis/lib/wallet.dis";

	init:	fn(): string;

	# Account types
	ACCT_ETH:	con 0;	# Ethereum/Base (secp256k1)
	ACCT_SOL:	con 1;	# Solana (Ed25519)
	ACCT_STRIPE:	con 2;	# Fiat (Stripe API key)

	Account: adt {
		name:		string;
		accttype:	int;
		chain:		string;	# "base", "ethereum", "solana"
		address:	string;	# public address (hex with 0x or base58)
	};

	# Account management (keys in factotum)
	createaccount:	fn(name: string, accttype: int, chain: string): (ref Account, string);
	importaccount:	fn(name: string, accttype: int, chain: string, privkey: array of byte): (ref Account, string);
	loadaccount:	fn(name: string): (ref Account, string);
	listaccounts:	fn(): list of ref Account;

	# Signing (retrieves key from factotum, signs, zeroes key)
	signhash:	fn(acct: ref Account, hash: array of byte): (array of byte, string);

	# Budget enforcement
	Budget: adt {
		maxpertx:	big;	# max per transaction (smallest unit)
		maxpersess:	big;	# max per session
		spent:		big;	# spent this session
		currency:	string;	# "USDC", "ETH", "USD"
	};

	setbudget:	fn(acct: ref Account, b: ref Budget);
	checkbudget:	fn(acct: ref Account, amount: big): string;
		# returns nil if OK, error string if over budget
	recordspend:	fn(acct: ref Account, amount: big);
};
