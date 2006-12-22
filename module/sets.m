Sets: module {
	A: con 2r1010;
	B: con 2r1100;

	PATH: con "/dis/lib/sets.dis";

	init:		fn();
	set:		fn(): Set;
	str2set:	fn(str: string): Set;
	bytes2set:	fn(d: array of byte): Set;
	Set: adt {
		m:	int;
		a:	array of int;

		X:		fn(s1: self Set, o: int, s2: Set): Set;
		add:		fn(s: self Set, n: int): Set;
		addlist:	fn(s: self Set, ns: list of int): Set;
		# dellist:	fn(s: self Set, ns: list of int): Set;
		del:		fn(s: self Set, n: int): Set;
		invert:	fn(s: self Set): Set;

		eq:		fn(s1: self Set, s2: Set): int;
		holds:	fn(s: self Set, n: int): int;
		isempty:	fn(s: self Set): int;
		msb:		fn(s: self Set): int;
		limit:		fn(s: self Set): int;

		str:		fn(s: self Set): string;
		bytes:	fn(s: self Set, n: int): array of byte;
		debugstr:	fn(s: self Set): string;
	};
	All: con Set(~0, nil);
	None: con Set(0, nil);
};
