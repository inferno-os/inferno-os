Palm: module {

	#
	# basic Palm data types
	#

	PATH:	con "/dis/lib/palm.dis";

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

		# the following is used by the database access protocol
		index:	int;

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
	Fstream:		con 1<<7;		# file is an array of bytes, not a database

	# extended (misc) attributes for Desklink->ReadDBList
	Fnosync:		con (1<<7)<<16;
	Frambased:	con (1<<6)<<16;

	Noindex:		con 16rFFFF;	# unknown index

	Record: adt {
		id:	int;	# unique record ID (24 bits)
		attr:	int;	# record attributes
		cat:	int;	# category
		data:	array of byte;

		new:	fn(id: int, attr: int, cat: int, size: int): ref Record;
	};

	# Record.attr values:

	Rdelete:	con 16r80; # delete next sync
	Rdirty:	con 16r40; # record modified
	Rinuse:	con 16r20; # record in use
	Rsecret:	con 16r10; # record is secret
	Rarchive:	con 16r08; # archive next sync
	Rmcat:	con 16r0F; # mask for category field in Palmdb->Entry.attrs

	Resource: adt {
		name:	int;	# byte[4]: resource name or type
		id:	int;	# resource ID (16 bits)
		data:	array of byte;

		new:	fn(name: int, id: int, size: int): ref Resource;
	};

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

	Doc: adt {
		m:	Palmdb;
		file:	ref Palmdb->PDB;
		version:	int;
		length:	int;	# uncompressed
		nrec:		int;	# text records only
		recsize:	int;	# uncompressed
		position:	int;
		sizes:	array of int;	# sizes of uncompressed records

		open:	fn(m: Palmdb, file: ref Palmdb->PDB): (ref Doc, string);
		read:		fn(nil: self ref Doc, i: int): (string, string);
		iscompressed:	fn(nil: self ref Doc): int;
		unpacktext:	fn(d: self ref Doc, a: array of byte): (string, string);
		textlength:	fn(d: self ref Doc, a: array of byte): int;
	};

	init:	fn(): string;

	# name mapping
	filename:	fn(s: string): string;
	dbname:	fn(s: string): string;

	# convert between resource/application ID and string
	id2s:	fn(id: int): string;
	s2id:	fn(s: string): int;

	# time conversion
	pilot2epoch:	fn(t: int): int;
	epoch2pilot:	fn(t: int): int;

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

	# argument wrapping for Desklink and CMP 2.x
	ArgIDbase: con 16r20;		# first argument ID
	argsize:	fn(args: array of (int, array of byte)): int;
	packargs:	fn(out: array of byte, args: array of (int, array of byte)): array of byte;
	unpackargs:	fn(argc: int, reply: array of byte): (array of (int, array of byte), string);

};

Palmdb: module {

	PATH:	con "/dis/lib/palmdb.dis";

	DB: adt {
		x:	int;			# instance index, used internally

		mode:	int;
		attr:		int;		# essential database attributes

		open:	fn(nil: string, mode: int): (ref DB, string);
		create:	fn(nil: string, mode: int, perm: int, nil: ref Palm->DBInfo): (ref DB, string);
		close:	fn(nil: self ref DB): string;

		stat:		fn(nil: self ref DB): ref Palm->DBInfo;
		wstat:	fn(nil: self ref DB, nil: ref Palm->DBInfo, flags: int);

		rdappinfo:	fn(nil: self ref DB): (array of byte, string);
		wrappinfo:	fn(nil: self ref DB, nil: array of byte): string;

		rdsortinfo:	fn(nil: self ref DB): (array of int, string);
		wrsortinfo:	fn(nil: self ref DB, nil: array of int): string;

		readidlist:	fn(nil: self ref DB, sort: int): array of int;
		nentries:	fn(nil: self ref DB): int;
		resetsyncflags:	fn(nil: self ref DB): string;

		records:	fn(nil: self ref DB): ref PDB;
		resources:	fn(nil: self ref DB): ref PRC;
	};

	# database files (.pdb, .doc, and most others)
	PDB: adt {
		db:	ref DB;

		read:		fn(nil: self ref PDB, index: int): ref Palm->Record;
		readid:	fn(nil: self ref PDB, id: int): (ref Palm->Record, int);

		resetnext:	fn(nil: self ref PDB): int;
		readnextmod:	fn(nil: self ref PDB): (ref Palm->Record, int);
#			DLP 1.1 functions:
#		readnextincat(nil: self ref DB, cat: int): (ref Palm->Record, string);
#		readnextmodincat(nil: self ref DB, cat: int): (ref Palm->Record, string);

		write:	fn(nil: self ref PDB, r: ref Palm->Record): string;

		truncate:	fn(nil: self ref PDB): string;
		delete:	fn(nil: self ref PDB, id: int): string;
		deletecat:	fn(nil: self ref PDB, cat: int): string;
		purge:	fn(nil: self ref PDB): string;

		movecat:	fn(nil: self ref PDB, old: int, new: int): string;

	};

	# resource files (.prc)
	PRC: adt {
		db:	ref DB;

		# read by index, or by type & id
		read:		fn(nil: self ref PRC, index: int): ref Palm->Resource;
		readtype:	fn(nil: self ref PRC, name: int, id: int): (ref Palm->Resource, int);

		# write by type and id only (desklink)
		write:	fn(nil: self ref PRC, r: ref Palm->Resource): string;

		truncate:	fn(nil: self ref PRC): string;
		delete:	fn(nil: self ref PRC, name: int, id: int): string;
	};

	# open modes (not the same as Sys->)
	OREAD:		con 16r80;
	OWRITE:		con 16r40;
	ORDWR:		con OREAD|OWRITE;
	OEXCL:		con 16r20;
	OSECRET:		con 16r10;

	init:	fn(m: Palm): string;
};
