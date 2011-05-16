Vac: module {
	PATH:	con "/dis/lib/vac.dis";
	init:	fn();

	dflag:	int;

	# mode bits
	Modeperm: con 8r777;
	Modesticky,
	Modesetuid,
	Modesetgid,
	Modeappend,
	Modeexcl,
	Modesymlink,
	Modedir,
	Modehidden,
	Modesystem,
	Modearchive,
	Modetemp,
	Modesnapshot,
	Modedev,
	Modenamedpipe: con 1<<(9+iota);

	Metablocksize:	con 12;
	Metaentrysize:	con 4;

	Dsize:	con 8*1024;

	# DirPlan9, DirNT & DirGen not valid in version >= 9
	DirPlan9,
	DirNT,
	DirQidspace,
	DirGen: con 1+iota;

	Direntry: adt {
		version:	int;
		elem:	string;
		entry, gen:	int;
		mentry, mgen:	int;
		qid:	big;
		uid, gid, mid:	string;
		mtime, mcount, ctime, atime, mode, emode: int;
		qidspace:	int;
		qidoff:		big;
		qidmax:		big;

		new:	fn(): ref Direntry;
		mk:	fn(d: Sys->Dir): ref Direntry;
		mkdir:	fn(de: self ref Direntry): ref Sys->Dir;
		pack:	fn(de: self ref Direntry): array of byte;
		unpack:	fn(d: array of byte): ref Direntry;
	};

	Metablock: adt {
		size, free, maxindex, nindex:	int;

		new:	fn(): ref Metablock;
		pack:	fn(mb: self ref Metablock, d: array of byte);
		unpack:	fn(d: array of byte): ref Metablock;
	};

	Metaentry: adt {
		offset, size:	int;

		pack:	fn(me: self ref Metaentry, d: array of byte);
		unpack:	fn(d: array of byte, i: int): ref Metaentry;
	};

	# single block
	Page: adt {
		d:	array of byte;
		o:	int;

		new:	fn(dsize: int): ref Page;
		add:	fn(p: self ref Page, s: Venti->Score);
		full:	fn(p: self ref Page): int;
		data:	fn(p: self ref Page): array of byte;
	};

	# hash tree file
	File: adt {
		p:	array of ref Page;
		dtype, dsize:	int;
		size:	big;
		s:	ref Venti->Session;

		new:	fn(s: ref Venti->Session, dtype, dsize: int): ref File;
		write:	fn(f: self ref File, d: array of byte): int;
		finish:	fn(f: self ref File): ref Venti->Entry;
	};

	# for writing venti directories
	Sink: adt {
		f:	ref File;
		d:	array of byte;
		nd, ne:	int;

		new:	fn(s: ref Venti->Session, dsize: int): ref Sink;
		add:	fn(m: self ref Sink, e: ref Venti->Entry): int;
		finish:	fn(m: self ref Sink): ref Venti->Entry;
	};

	Mentry: adt {
		elem:	string;
		me:	ref Metaentry;

		cmp:	fn(a, b: ref Mentry): int;
	};

	# for writing directory entries (meta blocks, meta entries, direntries)
	MSink: adt {
		f: 	ref File;
		de:	array of byte;
		nde:	int;
		l:	list of ref Mentry;

		new:	fn(s: ref Venti->Session, dsize: int): ref MSink;
		add:	fn(m: self ref MSink, de: ref Direntry): int;
		finish:	fn(m: self ref MSink): ref Venti->Entry;
	};

	# for reading pages from a hash tree referenced by an entry
	Source: adt {
		session:	ref Venti->Session;
		e:	ref Venti->Entry;
		dsize:	int;  # real dsize

		new:	fn(s: ref Venti->Session, e: ref Venti->Entry): ref Source;
		get:	fn(s: self ref Source, i: big, d: array of byte): int;
	};

	# for reading from a hash tree while keeping offset
	Vacfile: adt {
		s:	ref Source;
		o:	big;

		mk:	fn(s: ref Source): ref Vacfile;
		new:	fn(session: ref Venti->Session, e: ref Venti->Entry): ref Vacfile;
		read:	fn(v: self ref Vacfile, d: array of byte, n: int): int;
		seek:	fn(v: self ref Vacfile, offset: big): big;
		pread:	fn(v: self ref Vacfile, d: array of byte, n: int, offset: big): int;
	};

	# for listing contents of a vac directory and walking to path elements
	Vacdir: adt {
		vf:	ref Vacfile;
		ms:	ref Source;
		p:	big;
		i:	int;

		mk:	fn(vf: ref Vacfile, ms: ref Source): ref Vacdir;
		new:	fn(session: ref Venti->Session, e, me: ref Venti->Entry): ref Vacdir;
		walk:	fn(v: self ref Vacdir, elem: string): ref Direntry;
		open:	fn(v: self ref Vacdir, de: ref Direntry): (ref Venti->Entry, ref Venti->Entry);
		readdir:	fn(v: self ref Vacdir): (int, ref Direntry);
		rewind:		fn(v: self ref Vacdir);
	};

	vdroot:	fn(session: ref Venti->Session, score: Venti->Score): (ref Vacdir, ref Direntry, string);
};
