Styxconv: module
{
	PATHOLD2NEW: con "/dis/lib/styxconv/old2new.dis";
	PATHNEW2OLD: con "/dis/lib/styxconv/new2old.dis";

	# call first
	init: fn();
	# spawn and synchronize
	styxconv: fn(client: ref Sys->FD, server: ref Sys->FD);
};
