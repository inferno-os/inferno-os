Bloomfilter: module {
	PATH:	con "/dis/lib/bloomfilter.dis";
	init:		fn();
	# logm is log base 2 of the number of bits in the bloom filter.
	# k is number of independent hashes of d that are entered into the filter.
	filter:	fn(d: array of byte, logm, k: int): Sets->Set;
};
