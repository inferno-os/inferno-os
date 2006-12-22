StringIntTab: module
{
	PATH: con "/dis/lib/strinttab.dis";

	StringInt: adt{
		key: string;
		val: int;
	};

	# Binary search of t (which must be sorted) for key.
	# Returns (found, val).
	lookup: fn(t: array of StringInt, key: string) : (int, int);

	# Linear search of t for first pair with given val.
	# Returns key (nil if no match).
	revlookup: fn(t: array of StringInt, val: int) : string;
};
