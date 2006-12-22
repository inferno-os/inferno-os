Arch : module
{
	PATH : con "/dis/install/arch.dis";

	Ahdr : adt {
		name : string;
		modestr : string;
		d : ref Sys->Dir;
	};

	Archive : adt {
		b : ref Bufio->Iobuf;
		nexthdr : int;
		canseek : int;
		pid : int;
		hdr : ref Ahdr;
		err : string;
	};

	init: fn(bio: Bufio);

	openarch: fn(name : string) : ref Archive;
	openarchfs: fn(name : string) : ref Archive;
	openarchgz: fn(name : string) : (string, ref Sys->FD);
	gethdr: fn(ar : ref Archive) : ref Ahdr;
	getfile: fn(ar : ref Archive, bout : ref Bufio->Iobuf, n : int) : string;
	drain: fn(ar : ref Archive, n : int) : int;
	closearch: fn(ar : ref Archive);

	puthdr: fn(b : ref Bufio->Iobuf, name : string, d : ref Sys->Dir);
	putstring: fn(b : ref Bufio->Iobuf, s : string);
	putfile: fn(b : ref Bufio->Iobuf, f : string, n : int) : string;
	putend: fn(b : ref Bufio->Iobuf);

	addperms: fn(p: int);
};
