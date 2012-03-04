Rabin: module
{
	PATH:	con "/dis/lib/rabin.dis";
	init:	fn(bufio: Bufio);

	debug:	int;

	open:	fn(rcfg: ref Rcfg, b: ref Iobuf, min, max: int): (ref Rfile, string);

	Rcfg: adt {
		prime, width, mod: int;
		tab:	array of int;

		mk:	fn(prime, width, mod: int): (ref Rcfg, string);
	};

	Rfile: adt {
		b:	ref Iobuf;
		rcfg:	ref Rcfg;
		min, max:	int;
		buf:	array of byte;
		n:	int;
		state:	int;
		off:	big;

		read:	fn(r: self ref Rfile): (array of byte, big, string);
	};
};
