#
#  security routines implemented in limbo
#


Virgil: module
{
	PATH:	con "/dis/lib/virgil.dis";

	virgil:	fn(args: list of string): string;
};

Random: module
{
	PATH:	con "/dis/lib/random.dis";

	ReallyRandom:	con 0;
	NotQuiteRandom:	con 1;

	randomint: fn(which: int): int;
	randombuf: fn(which, n: int): array of byte;
};

#
#  secure socket layer emulator
#
SSL: module
{
	PATH:	con "/dis/lib/ssl.dis";

	connect: fn(fd: ref Sys->FD): (string, ref Sys->Connection);
	secret: fn(c: ref Sys->Connection, secretin, secretout: array of byte): string;
};


#
#  Encrypted Key Exchange protocol
#
Login: module 
{
	PATH:	con "/dis/lib/login.dis";

	login:	fn(id, password, dest: string): (string, ref Keyring->Authinfo);
	# the same on a connection already made; version is 2, or 1 for the original exchange
	loginfd:	fn(version: int, id, password: string, fd: ref Sys->FD): (string, ref Keyring->Authinfo);
	# the same, given the SHA-1 of the password in place of the password
	loginsecret:	fn(version: int, id: string, secret: array of byte, fd: ref Sys->FD): (string, ref Keyring->Authinfo);

	# What a signer may keep for a user in place of the SHA-1 of the password:
	# Verifiertag and 32 bytes from which the password's holder can be
	# recognised (by version 2 only) but with which nobody can log in.
	Verifiertag:	con "aucpace1";
	Verifierlen:	con 8+32;
	verifier:	fn(id: string, secret: array of byte): array of byte;
};

#
#  Station To Station protocol
#
Auth: module
{
	PATH:	con "/dis/lib/auth.dis";

	init: fn(): string;
	server: fn(algs: list of string, ai: ref Keyring->Authinfo, fd: ref Sys->FD, setid: int): (ref Sys->FD, string);
	client: fn(alg: string, ai: ref Keyring->Authinfo, fd: ref Sys->FD): (ref Sys->FD, string);
	auth:	fn(ai: ref Keyring->Authinfo, keyspec: string, alg: string, dfd: ref Sys->FD): (ref Sys->FD, ref Keyring->Authinfo, string);
	keyfile:	fn(keyspec: string): string;
	key:	fn(keyspec: string): ref Keyring->Authinfo;
};
