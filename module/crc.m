Crc: module
{
	PATH: con "/dis/lib/crc.dis";

	CRCstate: adt {
		crc: int;
		crctab: array of int;
		reg: int;
	};

	# setup crc table with given polynomial (if 0 default polynomial used) 
	# (the polynomial has an implicit top bit set)
	# reg is the initial value of the CRC register 
	# (usually 0 but 16rfffffffrf in the CRC32 algorithm for example)
	init: fn(poly: int, reg: int): ref CRCstate;

	# calculate crc of first nb bytes in given array of bytes and return its value
	# may be called repeatedly to calculate crc of a series of arrays of bytes
	crc :	fn(state: ref CRCstate, buf: array of byte, nb: int): int;

	# reset crc state to its initial value
	reset: fn(state: ref CRCstate);
};
