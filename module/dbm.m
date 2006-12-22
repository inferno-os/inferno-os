Dbm: module
{
	PATH: con "/dis/lib/dbm.dis";

	Datum:	type array of byte;

	Dbf: adt {
		create:	fn(file: string, perm: int): ref Dbf;
		open:	fn(file: string, flags: int): ref Dbf;

		fetch:	fn(db: self ref Dbf, key: Datum): Datum;
		delete:	fn(db: self ref Dbf, key: Datum): int;
		store:	fn(db: self ref Dbf, key: Datum, dat: Datum, replace: int): int;
		firstkey:	fn(db: self ref Dbf): Datum;
		nextkey:	fn(db: self ref Dbf, key: Datum): Datum;

		flush:	fn(db: self ref Dbf);

		isrdonly:	fn(db: self ref Dbf): int;

		dirf:	ref Sys->FD;	# directory
		pagf:	ref Sys->FD;	# page
		flags:	int;
		maxbno:	int;	# last `bno' in page file
		bitno:	int;
		hmask:	int;
		blkno:	int;	# current page to read/write
		pagbno:	int;	# current page in pagbuf
		pagbuf:	array of byte;	# [PBLKSIZ]
		dirbno:	int;	# current block in dirbuf
		dirbuf:	array of byte;	# [DBLKSIZ]
	};

	init:	fn();
};
