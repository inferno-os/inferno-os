Diskblocks: module {
	PATH: con "/dis/lib/diskblocks.dis";

	Block: adt {
		addr:	big;	# address on file
		n:	int;	# size in bytes
	};

	Disk: adt {
		fd: ref Sys->FD;
		addr: big;		# length of temp file
		free: array of list of ref Block;
		maxblock:	int;
		gran:	int;
		lock:	chan of int;

		init:	fn(fd: ref Sys->FD, gran: int, maxblock: int): ref Disk;
		new:	fn(d: self ref Disk, n: int): ref Block;
		release:	fn(d: self ref Disk, b: ref Block);
		read:	fn(d: self ref Disk, b: ref Block, a: array of byte, n: int): int;
		write:	fn(d: self ref Disk, b: ref Block, a: array of byte, n: int): ref Block;
	};

	init: fn();
	tempfile: fn(): ref Sys->FD;
};
