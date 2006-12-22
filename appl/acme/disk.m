Diskm : module {
	PATH : con "/dis/acme/disk.dis";

	init : fn(mods : ref Dat->Mods);

	Disk : adt {
		fd : ref Sys->FD;
		addr : int;		# length of temp file
		free : array of ref Dat->Block;

		init : fn() : ref Disk;
		new : fn(d : self ref Disk, n : int) : ref Dat->Block;
		release : fn(d : self ref Disk, b : ref Dat->Block);
		read : fn(d : self ref Disk, b : ref Dat->Block, s : ref Dat->Astring, n : int);
		write : fn(d : self ref Disk, b : ref Dat->Block, s : string, n : int) : ref Dat->Block;
	};

	tempfile: fn() : ref Sys->FD;
};
