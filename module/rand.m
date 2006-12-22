Rand: module
{
	PATH:	con "/dis/lib/rand.dis";
	init:	fn(seed: int);
	rand:       fn(modulus: int): int;
	bigrand:    fn(modulus: big): big;
};
