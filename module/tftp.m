Tftp: module
{
	PATH: con "/dis/lib/tftp.dis";
	init: fn(progress: int);
	receive: fn(host: string, filename: string, fd: ref Sys->FD): string;
};
