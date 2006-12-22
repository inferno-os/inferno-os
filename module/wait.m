Wait: module
{
	PATH:	con "/dis/lib/wait.dis";

	init:	fn();
	read:	fn(fd: ref Sys->FD): (int, string, string);
	monitor:	fn(fd: ref Sys->FD): (int, chan of (int, string, string));
	parse:	fn(status: string): (int, string, string);
};
