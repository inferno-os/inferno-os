Attrdb: module
{
	PATH:	con "/dis/lib/attrdb.dis";

	Attr: adt {
		attr:	string;
		val:	string;
		tag:	int;		# application-defined data, initially 0
	};

	Tuples: adt {
		n:	int;
		pairs:	list of ref Attr;

		hasattr:	fn(t: self ref Tuples, attr: string): int;
		haspair:	fn(t: self ref Tuples, attr: string, value: string): int;
		find:	fn(t: self ref Tuples, attr: string): list of ref Attr;
		findbyattr:	fn(t: self ref Tuples, attr: string, value: string, rattr: string): list of ref Attr;
	};

	Dbentry: adt {
		n:	int;
		lines:	list of ref Tuples;

		find:	fn(e: self ref Dbentry, attr: string): list of (ref Tuples, list of ref Attr);
		findfirst:	fn(e: self ref Dbentry, attr: string): string;
		findpair:	fn(e: self ref Dbentry, attr: string, value: string): list of ref Tuples;
		findbyattr:	fn(e: self ref Dbentry, attr: string, value: string, rattr: string): list of (ref Tuples, list of ref Attr);
	};

	Dbptr: adt {
		dbs:	list of ref Dbf;
		index:	ref Attrindex->Index;
		pick{
		Direct =>
			offset:	int;
		Hash =>
			current:	int;
			next:	int;
		}
	};

	Dbf: adt {
		fd:	ref Bufio->Iobuf;
		name:	string;
		dir:	ref Sys->Dir;
		indices:	list of ref Attrindex->Index;
		lockc:	chan of int;

		open:	fn(path: string): ref Dbf;
		sopen:	fn(data: string): ref Dbf;
		changed:	fn(f: self ref Dbf): int;
		reopen:	fn(f: self ref Dbf): int;

		# for supporting commands:
		readentry:	fn(dbf: self ref Dbf, offset: int, attr: string, value: string, useval: int): (ref Dbentry, int, int);
	};

	Db: adt {
		dbs:		list of ref Dbf;

		open:	fn(path: string): ref Db;
		sopen:	fn(data: string): ref Db;
		append:	fn(db1: self ref Db, db2: ref Db): ref Db;
		changed:	fn(db: self ref Db): int;
		reopen:	fn(db: self ref Db): int;

		find:	fn(db: self ref Db, start: ref Dbptr, attr: string): (ref Dbentry, ref Dbptr);
		findpair:	fn(db: self ref Db, start: ref Dbptr, attr: string, value: string): (ref Dbentry, ref Dbptr);
		findbyattr:	fn(db: self ref Db, start: ref Dbptr, attr: string, value: string, rattr: string): (ref Dbentry, ref Dbptr);
	};

	init:	fn(): string;

	parseentry:	fn(s: string, lno: int): (ref Dbentry, int, string);
	parseline:	fn(s: string, lno: int): (ref Tuples, string);
};

Attrindex: module
{
	PATH:	con "/dis/lib/attrhash.dis";

	Index: adt {
		fd:	ref Sys->FD;
		attr:	string;
		mtime:	int;
		size:	int;
		tab:	array of byte;

		open:	fn(dbf: Attrdb->Dbf, attr: string, fd: ref Sys->FD): ref Index;
	};

	init:	fn(): string;
};

Attrhash: module
{
	PATH:	con "/dis/lib/attrhash.dis";

	NDBPLEN: con 3;	# file pointer length in bytes
	NDBHLEN:	con 4+4;	# file header length (mtime[4], length[4])
	NDBSPEC:	con 1<<23;	# flag bit for something special
	NDBCHAIN: con NDBSPEC;	# pointer to collision chain
	NDBNAP:	con NDBSPEC | 1;	# not a pointer

	init:	fn(): string;
	attrindex:	fn(): Attrindex;
	hash:	fn(s: string, hlen: int): int;
	get3, get4:	fn(a: array of byte): int;
};
