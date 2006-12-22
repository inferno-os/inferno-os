MemFS : module {
	PATH : con "/dis/lib/memfs.dis";
	init : fn() : string;
	newfs : fn (maxsz : int) : ref Sys->FD;
};
