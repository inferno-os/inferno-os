#
# adapted from /sys/include/disk.h on Plan 9: subject to the Lucent Public License 1.02
#
ScsiIO: module
{
	PATH: con "/dis/lib/scsiio.dis";

	# SCSI interface
	Scsi: adt {
		lock:	chan of int;
		inquire:	string;
		rawfd:	ref Sys->FD;
		nchange:	int;
		changetime:	int;

		open:	fn(f: string): ref Scsi;
		rawcmd:	fn(s: self ref Scsi, c: array of byte, d: array of byte, io: int): int;
		cmd:		fn(s: self ref Scsi, c: array of byte, d: array of byte, io: int): int;
		ready:	fn(s: self ref Scsi): int;
	};

	Sread, Swrite, Snone: con iota;

	scsierror:	fn(asc: int, ascq: int): string;

	init:	fn(verbose: int);
};
