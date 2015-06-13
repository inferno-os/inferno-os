Ninep: module
{
	PATH:	con "/dis/lib/ninep.dis";

	VERSION:	con "9P2000";
	MAXWELEM:	con 16;

	NOTAG:	con 16rFFFF;
	NOFID:	con int ~0;	# 32 bits in this version of 9P

	BIT8SZ:	con 1;
	BIT16SZ:	con 2;
	BIT32SZ:	con 4;
	BIT64SZ:	con 8;
	QIDSZ:	con BIT8SZ+BIT32SZ+BIT64SZ;

	STATFIXLEN:	con BIT16SZ+QIDSZ+5*BIT16SZ+4*BIT32SZ+BIT64SZ;	# amount of fixed length data in a stat buffer
	IOHDRSZ:	con 24;	# room for Twrite/Rread header
	DEFIOUNIT: con 8192;	# `reasonable' iounit
	DEFMSIZE:	con IOHDRSZ+DEFIOUNIT;	# usable default for fversion and iounit

	Tversion,		# 100
	Rversion,
	Tauth,		# 102
	Rauth,
	Tattach,		# 104
	Rattach,
	Terror,		# 106, illegal
	Rerror,
	Tflush,		#108
	Rflush,
	Twalk,		# 110
	Rwalk,
	Topen,		# 112
	Ropen,
	Tcreate,		# 114
	Rcreate,
	Tread,		# 116
	Rread,
	Twrite,		# 118
	Rwrite,
	Tclunk,		# 120
	Rclunk,
	Tremove,		# 122
	Rremove,
	Tstat,		# 124
	Rstat,
	Twstat,		#126
	Rwstat,
	Tmax: con 100+iota;

	ERRMAX:	con 128;

	OREAD:	con 0; 		# open for read
	OWRITE:	con 1; 		# write
	ORDWR:	con 2; 		# read and write
	OEXEC:	con 3; 		# execute, == read but check execute permission
	OTRUNC:	con 16; 		# or'ed in (except for exec), truncate file first
	ORCLOSE: con 64; 		# or'ed in, remove on close

	# mode bits in Dir.mode used by the protocol
	DMDIR:		con int 1<<31;		# mode bit for directory
	DMAPPEND:	con int 1<<30;		# mode bit for append-only files
	DMEXCL:		con int 1<<29;		# mode bit for exclusive use files
	DMAUTH:		con int 1<<27;		# mode bit for authentication files

	# Qid.qtype
	QTDIR:	con 16r80;
	QTAPPEND:	con 16r40;
	QTEXCL:	con 16r20;
	QTAUTH:	con 16r08;
	QTFILE:	con 16r00;

	Tmsg: adt {
		tag: int;
		pick {
		Readerror =>
			error: string;		# tag is unused in this case
		Version =>
			msize: int;
			version: string;
		Auth =>
			afid: int;
			uname, aname: string;
		Attach =>
			fid, afid: int;
			uname, aname: string;
		Flush =>
			oldtag: int;
		Walk =>
			fid, newfid: int;
			names: array of string;
		Open =>
			fid, mode: int;
		Create =>
			fid: int;
			name: string;
			perm, mode: int;
		Read =>
			fid: int;
			offset: big;
			count: int;
		Write =>
			fid: int;
			offset: big;
			data: array of byte;
		Clunk or
		Stat or
		Remove => 
			fid: int;
		Wstat =>
			fid: int;
			stat: Sys->Dir;
		}

		read:	fn(fd: ref Sys->FD, msize: int): ref Tmsg;
		unpack:	fn(a: array of byte): (int, ref Tmsg);
		pack:	fn(nil: self ref Tmsg): array of byte;
		packedsize:	fn(nil: self ref Tmsg): int;
		text:	fn(nil: self ref Tmsg): string;
		mtype: fn(nil: self ref Tmsg): int;
	};

	Rmsg: adt {
		tag: int;
		pick {
		Readerror =>
			error: string;		# tag is unused in this case
		Version =>
			msize: int;
			version: string;
		Auth =>
			aqid: Sys->Qid;
		Attach =>
			qid: Sys->Qid;
		Flush =>
		Error =>
			ename: string;
		Clunk or
		Remove or
		Wstat =>
		Walk =>
			qids: array of Sys->Qid;
		Create or
		Open =>
			qid: Sys->Qid;
			iounit: int;
		Read =>
			data: array of byte;
		Write =>
			count: int;
		Stat =>
			stat: Sys->Dir;
		}

		read:	fn(fd: ref Sys->FD, msize: int): ref Rmsg;
		unpack:	fn(a: array of byte): (int, ref Rmsg);
		pack:	fn(nil: self ref Rmsg): array of byte;
		packedsize:	fn(nil: self ref Rmsg): int;
		text:	fn(nil: self ref Rmsg): string;
		mtype: fn(nil: self ref Rmsg): int;
		write: fn(nil: self ref Rmsg, fd: ref Sys->FD, msize: int): int;
	};

	init:	fn();

	readmsg:	fn(fd: ref Sys->FD, msize: int): (array of byte, string);
	istmsg:	fn(f: array of byte): int;

	compatible:	fn(t: ref Tmsg.Version, msize: int, version: string): (int, string);

	packdirsize:	fn(d: Sys->Dir): int;
	packdir:	fn(d: Sys->Dir): array of byte;
	unpackdir: fn(f: array of byte): (int, Sys->Dir);
	dir2text:	fn(d: Sys->Dir): string;
	qid2text:	fn(q: Sys->Qid): string;

	utflen:	fn(s: string): int;
};
