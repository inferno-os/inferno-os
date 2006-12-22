Keyreps: module
{
	PATH: con "/dis/lib/spki/keyreps.dis";
	init: fn();
	Keyrep: adt {
		alg:	string;
		owner:	string;
		els:	list of (string, ref Keyring->IPint);
		pick{	# keeps a type distance between public and private keys
		PK =>
		SK =>
		}

		pk:	fn(pk: ref Keyring->PK): ref Keyrep.PK;
		sk:	fn(sk: ref Keyring->SK): ref Keyrep.SK;
		mkpk:	fn(k: self ref Keyrep): (ref Keyring->PK, int);
		mksk:	fn(k: self ref Keyrep): ref Keyring->SK;
		get:	fn(k: self ref Keyrep, n: string): ref Keyring->IPint;
		getb:	fn(k: self ref Keyrep, n: string): array of byte;
		eq:	fn(k1: self ref Keyrep, k2: ref Keyrep): int;
		mkkey: fn(k: self ref Keyrep): ref SPKI->Key;
	};
};
