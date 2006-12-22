Palmfile: module {

	PATH:	con "/dis/lib/palmfile.dis";

	DBInfo: adt {
		name:	string;
		attr:		int;
		dtype:	string;	# database type (byte[4])
		version:	int;	# defined by application
		creator:	string;	# creating application (byte[4])
		ctime:	int;
		mtime:	int;
		btime:	int;	# last backup
		modno:	int;	# modification number: set to zero
		uidseed:	int;	# unique record ID seed (unused, set to zero)

		# used internally and by the database access protocol
		appinfo:	int;	# AppInfo offset
		sortinfo:	int;	# SortInfo offset

		# the following are used by the database access protocol
		index:	int;
		more:	int;

		new:		fn(name: string, attr: int, dtype: string, version: int, creator: string): ref DBInfo;
	};

	# file attributes:

	Fresource:	con 1<<0;		# file is .prc not .pdb
	Fronly:		con 1<<1;		# read only
	Fappinfodirty:	con 1<<2;
	Fbackup:		con 1<<3;		# no conduit exists
	Foverwrite:	con 1<<4;		# overwrite older copy if present
	Freset:		con 1<<5;		# reset after installation
	Fprivate:		con 1<<6;		# don't allow copy of this to be beamed

	Record: adt {
		id:	int;	# resource: ID; data: unique record ID
		index:	int;
		name:	int;	# byte[4]: resource record only
		attr:	int;	# data record only
		cat:	int;	# category
		data:	array of byte;

#		new:	fn(size: int): ref Record;
	};

	Entry: adt {
		id:	int;	# resource: id; record: unique ID
		offset:	int;
		size:	int;
		name:	int;	# resource entry only
		attr:	int;	# record entry only
	};

	# record attributes:

	Rdelete:	con 16r80; # delete next sync
	Rdirty:	con 16r40; # record modified
	Rinuse:	con 16r20; # record in use
	Rsecret:	con 16r10; # record is secret
	Rarchive:	con 16r08; # archive next sync
	Rmcat:	con 16r0F; # mask for category field in Entry.attrs

	# common form of category data in appinfo
	Categories: adt {
		renamed:	int;	# which categories have been renamed
		labels:	array of string;	# 16 category names
		uids:		array of int;	# corresponding unique IDs
		lastuid:	int;		# last unique ID assigned
		appdata:	array of byte;	# remaining data is application-specific

		new:		fn(labels: array of string): ref Categories;
		unpack:	fn(a: array of byte): ref Categories;
		pack:	fn(c: self ref Categories): array of byte;
		mkidmap:	fn(c: self ref Categories): array of int;
	};

	Pfile: adt {
		fname:	string;
		f:	ref Bufio->Iobuf;
		mode:	int;

		info:	ref DBInfo;
		appinfo:	array of byte;
		sortinfo:	array of int;

		uidseed:	int;
		entries:	array of ref Entry;

		open:	fn(nil: string, mode: int): (ref Pfile, string);
#		create:	fn(nil: string, mode: int, perm: int, nil: ref DBInfo): ref Pfile;
		close:	fn(nil: self ref Pfile): int;

		stat:		fn(nil: self ref Pfile): ref DBInfo;
#		wstat:	fn(nil: self ref Pfile, nil: ref DBInfo);

		read:		fn(nil: self ref Pfile, index: int): (ref Record, string);
#		readid:	fn(nil: self ref Pfile, nil: int): (ref Record, string);
#		append:	fn(nil: self ref Pfile, r: ref Record): int;

#		setappinfo:	fn(nil: self ref Pfile, nil: array of byte);
#		setsortinfo:	fn(nil: self ref Pfile, nil: array of int);
	};

	Doc: adt {
		file:	ref Pfile;
		version:	int;
		length:	int;	# uncompressed
		nrec:		int;	# text records only
		recsize:	int;	# uncompressed
		position:	int;
		sizes:	array of int;	# sizes of uncompressed records

		open:	fn(file: ref Pfile): (ref Doc, string);
		read:		fn(nil: self ref Doc, i: int): (string, string);
		iscompressed:	fn(nil: self ref Doc): int;
		unpacktext:	fn(d: self ref Doc, a: array of byte): (string, string);
		textlength:	fn(d: self ref Doc, a: array of byte): int;
	};

	init:	fn(): string;

	# name mapping
	filename:	fn(s: string): string;
	dbname:	fn(s: string): string;

	# Latin-1 to string conversion
	gets:	fn(a: array of byte): string;
	puts:	fn(a: array of byte, s: string);

	# big-endian conversion
	get2:	fn(a: array of byte): int;
	get3:	fn(a: array of byte): int;
	get4:	fn(a: array of byte): int;
	put2:	fn(a: array of byte, v: int);
	put3:	fn(a: array of byte, v: int);
	put4:	fn(a: array of byte, v: int);
};
