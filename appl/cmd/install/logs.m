Logs: module
{
	PATH:	con "/dis/install/logs.dis";

	Entry: adt
	{
		seq:	big;	# time<<32 | gen
		action:	int;
		path:	string;
		serverpath:	string;
		x:	int;
		d:	Sys->Dir;
		contents:	list of string;	# MD5 hash of content, most recent first

		read:	fn(in: ref Bufio->Iobuf): (ref Entry, string);
		remove:	fn(e: self ref Entry);
		removed:	fn(e: self ref Entry): int;
		update:	fn(e: self ref Entry, n: ref Entry);
		text:	fn(e: self ref Entry): string;
		dbtext:	fn(e: self ref Entry): string;
		sumtext:	fn(e: self ref Entry): string;
		logtext:	fn(e: self ref Entry): string;
	};

	Db: adt
	{
		name:	string;
		state:	array of ref Entry;
		nstate:	int;
		stateht:	array of list of ref Entry;

		new:	fn(name: string): ref Db;
		entry:	fn(db: self ref Db, seq: big, name: string, d: Sys->Dir): ref Entry;
		look:	fn(db: self ref Db, name: string): ref Entry;
		sort:	fn(db: self ref Db, byname: int);
	};

	Byseq, Byname: con iota;

	init:	fn(bio: Bufio): string;

	S:	fn(s: string): string;
	mkpath:	fn(root: string, name: string): string;
};
