
SELF:	con	"$self";		# Language support for loading my instance

Sys: module
{
	PATH:	con	"$Sys";

	Maxint:	con	2147483647;

	# Unique file identifier for file objects
	Qid: adt
	{
		path:	big;
		vers:	int;
		qtype:	int;
	};

	QTDIR:	con 16r80;
	QTAPPEND:	con 16r40;
	QTEXCL:	con 16r20;
	QTAUTH:	con 16r08;
	QTTMP:	con 16r04;
	QTFILE:	con 0;

	# Return from stat and directory read
	Dir: adt
	{
		name:	string;
		uid:	string;
		gid:	string;
		muid:	string;
		qid:	Qid;
		mode:	int;
		atime:	int;
		mtime:	int;
		length:	big;
		dtype:	int;
		dev:	int;
	};
	nulldir:	con Dir(nil, nil, nil, nil, (~big 0, ~0, ~0), ~0, ~0, ~0, ~big 0, ~0, ~0);
	zerodir:	con Dir(nil, nil, nil, nil, (big 0, 0, 0), 0, 0, 0, big 0, 0, 0);

	# File descriptor
	#
	FD: adt
	{
		fd:	int;
	};

	# Network connection returned by dial
	#
	Connection: adt
	{
		dfd:	ref FD;
		cfd:	ref FD;
		dir:	string;
	};

	# File IO structures returned from file2chan
	# read:  (offset, bytes, fid, chan)
	# write: (offset, data, fid, chan)
	#
	Rread:	type chan of (array of byte, string);
	Rwrite:	type chan of (int, string);
	FileIO: adt
	{
		read:	chan of (int, int, int, Rread);
		write:	chan of (int, array of byte, int, Rwrite);
	};

	# Maximum read which will be completed atomically;
	# also the optimum block size
	#
	ATOMICIO:	con 8192;

	SEEKSTART:	con 0;
	SEEKRELA:	con 1;
	SEEKEND:	con 2;

	NAMEMAX:	con 256;
	ERRMAX:		con 128;
	WAITLEN:	con ERRMAX+64;

	OREAD:		con 0;
	OWRITE:		con 1;
	ORDWR:		con 2;
	OTRUNC:		con 16;
	ORCLOSE:	con 64;
	OEXCL:		con 16r1000;

	DMDIR:		con int 1<<31;
	DMAPPEND:	con int 1<<30;
	DMEXCL:		con int 1<<29;
	DMAUTH:		con int 1<<27;
	DMTMP:		con int 1<<26;

	MREPL:		con 0;
	MBEFORE:	con 1;
	MAFTER:		con 2;
	MCREATE:	con 4;
	MCACHE:		con 16;

	NEWFD:		con (1<<0);
	FORKFD:		con (1<<1);
	NEWNS:		con (1<<2);
	FORKNS:		con (1<<3);
	NEWPGRP:	con (1<<4);
	NODEVS:		con (1<<5);
	NEWENV:		con (1<<6);
	FORKENV:	con (1<<7);

	EXPWAIT:	con 0;
	EXPASYNC:	con 1;

	UTFmax:		con 3;
	UTFerror:	con 16r80;

	announce:	fn(addr: string): (int, Connection);
	aprint:		fn(s: string, *): array of byte;
	bind:		fn(s, on: string, flags: int): int;
	byte2char:	fn(buf: array of byte, n: int): (int, int, int);
	char2byte:	fn(c: int, buf: array of byte, n: int): int;
	chdir:		fn(path: string): int;
	create:		fn(s: string, mode, perm: int): ref FD;
	dial:		fn(addr, local: string): (int, Connection);
	dirread:	fn(fd: ref FD): (int, array of Dir);
	dup:		fn(old, new: int): int;
	export:		fn(c: ref FD, dir: string, flag: int): int;
	fauth:		fn(fd: ref FD, aname: string): ref FD;
	fd2path:	fn(fd: ref FD): string;
	fildes:		fn(fd: int): ref FD;
	file2chan:	fn(dir, file: string): ref FileIO;
	fprint:		fn(fd: ref FD, s: string, *): int;
	fstat:		fn(fd: ref FD): (int, Dir);
	fversion:	fn(fd: ref FD, msize: int, version: string): (int, string);
	fwstat:		fn(fd: ref FD, d: Dir): int;
	iounit:		fn(fd: ref FD): int;
	listen:		fn(c: Connection): (int, Connection);
	millisec:	fn(): int;
	mount:		fn(fd: ref FD, afd: ref FD, on: string, flags: int, spec: string): int;
	open:		fn(s: string, mode: int): ref FD;
	pctl:		fn(flags: int, movefd: list of int): int;
	pipe:		fn(fds: array of ref FD): int;
	print:		fn(s: string, *): int;
	pread:	fn(fd: ref FD, buf: array of byte, n: int, off: big): int;
	pwrite:	fn(fd: ref FD, buf: array of byte, n: int, off: big): int;
	read:		fn(fd: ref FD, buf: array of byte, n: int): int;
	remove:		fn(s: string): int;
	seek:		fn(fd: ref FD, off: big, start: int): big;
	sleep:		fn(period: int): int;
	sprint:		fn(s: string, *): string;
	stat:		fn(s: string): (int, Dir);
	stream:		fn(src, dst: ref FD, bufsiz: int): int;
	tokenize:	fn(s, delim: string): (int, list of string);
	unmount:	fn(s1: string, s2: string): int;
	utfbytes:	fn(buf: array of byte, n: int): int;
	werrstr:	fn(s: string): int;
	write:		fn(fd: ref FD, buf: array of byte, n: int): int;
	wstat:		fn(s: string, d: Dir): int;
};
