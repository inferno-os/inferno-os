#
# adapted from /sys/include/disk.h on Plan 9: subject to the Lucent Public License 1.02
#
Disks: module
{
	PATH: con "/dis/lib/disks.dis";

	# disk partition interface
	Disk: adt {
		prefix:	string;
		part:	string;
		fd:	ref Sys->FD;
		wfd:	ref Sys->FD;
		ctlfd:	ref Sys->FD;
		rdonly:	int;
		dtype:	string;	# "file", "sd" or "floppy"

		secs:	big;
		secsize:	int;
		size:	big;
		offset:	big;	# within larger disk, perhaps
		width:	int;	# of disk size in bytes as decimal string
		c:	int;	# geometry: cyl, head, sectors
		h:	int;
		s:	int;
		chssrc:	string; # "part", "disk" or "guess"

		open:	fn(f: string, mode: int, noctl: int): ref Disk;
		readn:	fn(d: self ref Disk, buf: array of byte, n: int): int;
	};

	init:	fn();
	readn:	fn(fd: ref Sys->FD, buf: array of byte, n: int): int;

	# PC partition grot
	PCpart: adt {
		active:	int;	# Active or 0
		ptype:	int;
		base:	big;	# base block address: 0 or first extended partition in chain
		offset:	big;	# block offset from base to partition
		size:		big;	# in sectors

		extract:	fn(a: array of byte, d: ref Disk): PCpart;
		bytes:	fn(p: self PCpart, d: ref Disk): array of byte;
	};
	Toffset:	con 446;	# offset of partition table in sector
	TentrySize:	con 2+2*3+4+4;	# partition table entry size
	NTentry:	con 4;	# number of table entries
	Magic0:	con 16r55;
	Magic1:	con 16rAA;
	Active:	con 16r80;	# partition is active
	Type9: 	con 16r39;	# partition type used by Plan 9 and Inferno

	chstext:	fn(p: array of byte): string;
};
