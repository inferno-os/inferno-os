implement Rand;

include "rand.m";

rsalt: big;

init(seed: int)
{
	rsalt = big seed;
}

MASK: con (big 1<<63)-(big 1);

rand(modulus: int): int
{
	rsalt = rsalt * big 1103515245 + big 12345;
	if(modulus <= 0)
		return 0;
	return int (((rsalt&MASK)>>10) % big modulus);
}

# 0 < modulus < 2^53
bigrand(modulus: big): big
{
	rsalt = rsalt * big 1103515245 + big 12345;
	if(modulus <= big 0)
		return big 0;
	return ((rsalt&MASK)>>10) % modulus;
}
