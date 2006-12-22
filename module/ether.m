Ether: module
{
	PATH:	con "/dis/lib/ether.dis";
	Eaddrlen:	con 6;

	init:	fn();
	parse:	fn(s: string): array of byte;
	text:	fn(a: array of byte): string;
	addressof:	fn(dev: string): array of byte;
	eqaddr:	fn(a, b: array of byte): int;
};
