IPints: module
{
	PATH:	con	"$IPints";

	# infinite precision integers
	IPint: adt
	{
		x:	int;	# dummy for C compiler for runt.h

		# conversions
		iptob64:	fn(i: self ref IPint): string;
		iptob64z:	fn(i: self ref IPint): string;
		b64toip:	fn(str: string): ref IPint;
		iptobytes:	fn(i: self ref IPint): array of byte;
		iptobebytes:	fn(i: self ref IPint): array of byte;
		bytestoip:	fn(buf: array of byte): ref IPint;
		bebytestoip:	fn(mag: array of byte): ref IPint;
		inttoip:	fn(i: int): ref IPint;
		iptoint:	fn(i: self ref IPint): int;
		iptostr:	fn(i: self ref IPint, base: int): string;
		strtoip:	fn(str: string, base: int): ref IPint;

		# create a random large integer
		random:		fn(nbits: int): ref IPint;

		# operations
		bits:		fn(i: self ref IPint): int;
		expmod:	fn(base: self ref IPint, exp, mod: ref IPint): ref IPint;
		invert:	fn(base: self ref IPint, mod: ref IPint): ref IPint;
		add:		fn(i1: self ref IPint, i2: ref IPint): ref IPint;
		sub:		fn(i1: self ref IPint, i2: ref IPint): ref IPint;
		neg:		fn(i: self ref IPint): ref IPint;
		mul:		fn(i1: self ref IPint, i2: ref IPint): ref IPint;
		div:		fn(i1: self ref IPint, i2: ref IPint): (ref IPint, ref IPint);
		mod:	fn(i1: self ref IPint, i2: ref IPint): ref IPint;
		eq:		fn(i1: self ref IPint, i2: ref IPint): int;
		cmp:		fn(i1: self ref IPint, i2: ref IPint): int;
		copy:	fn(i: self ref IPint): ref IPint;

		# shifts
		shl:	fn(i: self ref IPint, n: int): ref IPint;
		shr:	fn(i: self ref IPint, n: int): ref IPint;

		# bitwise
		and:	fn(i1: self ref IPint, i2: ref IPint): ref IPint;
		ori:	fn(i1: self ref IPint, i2: ref IPint): ref IPint;
		xor:	fn(i1: self ref IPint, i2: ref IPint): ref IPint;
		not:	fn(i1: self ref IPint): ref IPint;
	};

	# primes
	probably_prime:	fn(n: ref IPint, nrep: int): int;
	genprime:	fn(nbits: int, nrep: int): ref IPint;
	genstrongprime:	fn(nbits: int, nrep: int): ref IPint;
	gensafeprime:	fn(nbits: int, nrep: int): (ref IPint, ref IPint);
	DSAprimes:	fn(): (ref IPint, ref IPint, array of byte);
};
