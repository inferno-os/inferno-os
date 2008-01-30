Msgio: module
{
	PATH:	con "/dis/lib/msgio.dis";

	init:	fn();

	Maxmsg: con 4096;

	# message io on a delimited connection (ssl for example)
	#  messages >= Maxmsg bytes are truncated
	#  errors > 64 bytes are truncated
	# getstring and getbytearray return (result, error).
	getstring: fn(fd: ref Sys->FD): (string, string);
	putstring: fn(fd: ref Sys->FD, s: string): int;
	getbytearray: fn(fd: ref Sys->FD): (array of byte, string);
	putbytearray: fn(fd: ref Sys->FD, a: array of byte, n: int): int;
	puterror: fn(fd: ref Sys->FD, s: string): int;

	# to send and receive messages when ssl isn't pushed
	getmsg: fn(fd: ref Sys->FD): array of byte;
	sendmsg: fn(fd: ref Sys->FD, buf: array of byte, n: int): int;
	senderrmsg: fn(fd: ref Sys->FD, s: string): int;
};
