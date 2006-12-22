# Benchmarking

Bench: module
{
	PATH:	con "$Bench";

	FD: adt
	{
		fd:	int;
	};

	microsec:		fn(): big;
	reset:		fn();
	read:			fn(fd: ref FD, buf: array of byte, n: int): int;
	disablegc:		fn();
	enablegc:		fn();
};