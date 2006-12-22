#
# External loader interface
#
Nilmod: module
{
};

Loader: module
{
	PATH:	con	"$Loader";

	Inst: adt
	{
		op:	byte;
		addr:	byte;
		src:	int;
		mid:	int;
		dst:	int;
	};

	Typedesc: adt
	{
		size:	int;
		map:	array of byte;
	};

	Link: adt
	{
		name:	string;
		sig:	int;
		pc:	int;
		tdesc:	int;
	};

	Niladt: adt
	{
	};

	ifetch:		fn(mp: Nilmod): array of Inst;
	tdesc:		fn(mp: Nilmod): array of Typedesc;
	newmod:		fn(name: string, ss, nlink: int,
				inst: array of Inst, data: ref Niladt): Nilmod;
	tnew:		fn(mp: Nilmod, size: int, map: array of byte): int;
	link:		fn(mp: Nilmod): array of Link;
	ext:		fn(mp: Nilmod, idx, pc: int, tdesc: int): int;
	dnew:		fn(size: int, map: array of byte): ref Niladt;
	compile:	fn(mp: Nilmod, flag: int): int;
};
