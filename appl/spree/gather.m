Gatherengine: module {
	init:			fn(srvmod: Spree, clique: ref Spree->Clique, argv: list of string, archived: int): string;
	propose:		fn(members: array of string): string;
	start:			fn(members: array of ref Spree->Member, archived: int);
	command:	fn(member: ref Spree->Member, e: string): string;
	readfile:		fn(f: int, offset: big, n: int): array of byte;
	archive:		fn();
	clienttype:	fn(): string;
	maxmembers:	fn(): int;
};
