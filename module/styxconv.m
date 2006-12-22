Styxconv: module
{
	PATH: con "/dis/lib/styxconv/styxconv.dis";
	
	# call first
	init: fn();
	# spawn and synchronize
	styxconv: fn(in: ref Sys->FD, out: ref Sys->FD, sync: chan of int);
};
