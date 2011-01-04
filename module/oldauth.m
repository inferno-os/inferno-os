Oldauth: module
{
	PATH:	con "/dis/lib/oldauth.dis";

	init:	fn();

	# Inferno certificate
	Certificate: adt
	{
		sa:	string;	# signature algorithm
		ha:	string;		# hash algorithm
		signer:	string;	# name of signer
		exp:	int;		# expiration date
		sig:	ref Crypt->PKsig;
	};

	# authentication info
	Authinfo: adt
	{
		mysk:	ref Crypt->SK;			# my private key
		mypk:	ref Crypt->PK;			# my public key
		owner:	string;	# owner of mypk for certificate
		cert:	ref Certificate;	# signature of my public key
		spk:	ref Crypt->PK;			# signers public key
		alpha:	ref IPints->IPint;		# diffie helman parameters
		p:	ref IPints->IPint;
	};

	# auth io
	readauthinfo: fn(filename: string): ref Authinfo;
	writeauthinfo: fn(filename: string, info: ref Authinfo): int;

	# convert types to text in a canonical form
	certtostr: fn (c: ref Certificate): string;
	pktostr: fn (pk: ref Crypt->PK, owner: string): string;
	sktostr: fn (sk: ref Crypt->SK, owner: string): string;

	# parse text into types
	strtocert: fn (s: string): ref Certificate;
	strtopk: fn (s: string): (ref Crypt->PK, string);
	strtosk: fn (s: string): (ref Crypt->SK, string);

	# create and verify Certificates
	sign: fn (sk: ref Crypt->SK, signer: string, exp: int, state: ref Crypt->DigestState, ha: string):
		ref Certificate;
	verify: fn (pk: ref Crypt->PK, cert: ref Certificate, state: ref Crypt->DigestState):
		int;
};
