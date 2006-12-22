Keyset: module
{
	PATH:	con "/dis/lib/keyset.dis";

	init:	fn(): string;
	pkhash:	fn(pk: string): string;
	keysforsigner:	fn(signername: string, spk: string, user: string, dir: string): (list of (string, string, string), string);
};
