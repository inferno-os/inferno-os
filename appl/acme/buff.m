Bufferm : module {
	PATH : con "/dis/acme/buff.dis";

	init : fn(mods : ref Dat->Mods);

	newbuffer : fn() : ref Buffer;

	Buffer : adt {
		nc : int;
		c : ref Dat->Astring;		# cache
		cnc : int;		# bytes in cache
		cmax : int;	# size of allocated cache
		cq : int;		# position of cache
		cdirty : int;	# cache needs to be written
		cbi : int;		# index of cache Block
		bl : array of ref Dat->Block;	# array of blocks
		nbl : int;		# number of blocks

		insert : fn(b : self ref Buffer, n : int, s : string, m : int);
		delete : fn(b : self ref Buffer, n : int, m : int);
		# replace : fn(b : self ref Buffer, q0 : int, q1 : int, s : string, n : int);
		loadx : fn(b : self ref Buffer, n : int, fd : ref Sys->FD) : int;
		read : fn(b : self ref Buffer, n : int, s : ref Dat->Astring, p, m : int);
		close : fn(b : self ref Buffer);
		reset : fn(b : self ref Buffer);
		sizecache : fn(b : self ref Buffer, n : int);
		flush : fn(b : self ref Buffer);
		setcache : fn(b : self ref Buffer, n : int);
		addblock : fn(b : self ref Buffer, n : int, m : int);
		delblock : fn(b : self ref Buffer, n : int);
	};

	loadfile: fn(fd: ref Sys->FD, q1: int, fun: int, b: ref Bufferm->Buffer, f: ref Filem->File): int;
};
