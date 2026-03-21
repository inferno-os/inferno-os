X402: module {
	PATH:	con "/dis/lib/x402.dis";

	init:	fn(): string;

	# x402 protocol version
	VERSION:	con 2;

	# Payment requirements from a 402 response
	PaymentReq: adt {
		scheme:		string;		# "exact"
		network:	string;		# CAIP-2 format, e.g. "eip155:8453"
		amount:		string;		# amount in base units (wei)
		asset:		string;		# token contract address
		payto:		string;		# recipient address
		timeout:	int;		# maxTimeoutSeconds
		# extra fields for EVM
		name:		string;		# token name (e.g. "USD Coin")
		version:	string;		# token version (e.g. "2")
		method:		string;		# "eip3009" or "permit2"
	};

	# Resource info from 402 response
	ResourceInfo: adt {
		url:		string;
		description:	string;
		mimetype:	string;
	};

	# Full 402 response
	PaymentRequired: adt {
		x402version:	int;
		errmsg:		string;
		resource:	ref ResourceInfo;
		accepts:	list of ref PaymentReq;
	};

	# Settlement response from server after payment
	SettlementResp: adt {
		success:	int;
		errorreason:	string;
		payer:		string;
		transaction:	string;
		network:	string;
	};

	# Parse a 402 response body (JSON) into PaymentRequired
	parse402:	fn(body: string): (ref PaymentRequired, string);

	# Select the best payment option from accepts list
	# Prefers EVM networks the wallet supports
	selectoption:	fn(pr: ref PaymentRequired, chain: string): ref PaymentReq;

	# Build a payment payload and sign it
	# Returns base64-encoded JSON for the PAYMENT-SIGNATURE header
	authorize:	fn(req: ref PaymentReq, resource: ref ResourceInfo,
			   acctname: string): (string, string);

	# Parse a settlement response from the server
	parsesettlement:	fn(body: string): (ref SettlementResp, string);

	# Map chain name to CAIP-2 network identifier
	chaintonetwork:	fn(chain: string): string;
	networktochainid:	fn(network: string): int;
};
