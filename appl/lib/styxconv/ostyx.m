OStyx: module
{
	PATH: con "/dis/lib/styxconv/ostyx.dis";

	Chan: adt {
		fid: int;
		qid: OSys->Qid;
		open: int;
		mode: int;
		uname: string;
		path: string;
		data: array of byte;
	};

	Styxserver: adt {
		fd: ref Sys->FD;
		chans: array of list of ref Chan;

		new: fn(fd: ref Sys->FD): (chan of ref OTmsg, ref Styxserver);
		reply: fn(srv: self ref Styxserver, m: ref ORmsg): int;
		fidtochan: fn(srv: self ref Styxserver, fid: int): ref Chan;
		newchan: fn(srv: self ref Styxserver, fid: int): ref Chan;
		chanfree: fn(srv: self ref Styxserver, c: ref Chan);
		devclone: fn(srv: self ref Styxserver, m: ref OTmsg.Clone): ref Chan;
	};

	d2tmsg: fn(d: array of byte): (int, ref OTmsg);
	d2rmsg: fn(d: array of byte): (int, ref ORmsg);
	tmsg2d: fn(gm: ref OTmsg, d: array of byte): int;
	rmsg2d: fn(m: ref ORmsg, d: array of byte): int;
	tmsg2s: fn(m: ref OTmsg): string;				# for debugging
	rmsg2s: fn(m: ref ORmsg): string;				# for debugging
	convD2M: fn(d: array of byte, f: OSys->Dir): array of byte;
	convM2D: fn(d: array of byte): (array of byte, OSys->Dir);

	OTmsg: adt {
		tag: int;
		pick {
		Readerror =>
			error: string;		# tag is unused in this case
		Nop =>
		Flush =>
			oldtag: int;
		Clone =>
			fid, newfid: int;
		Walk =>
			fid: int;
			name: string;
		Open =>
			fid, mode: int;
		Create =>
			fid, perm, mode: int;
			name: string;
		Read =>
			fid, count: int;
			offset: big;
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
			stat: OSys->Dir;
		Attach =>
			fid: int;
			uname, aname: string;
		}
	};

	ORmsg: adt {
		tag: int;
		pick {
		Nop or
		Flush =>
		Error =>
			err: string;
		Clunk or
		Remove or
		Clone or
		Wstat =>
			fid: int;
		Walk or
		Create or
		Open or
		Attach =>
			fid: int;
			qid: OSys->Qid;
		Read =>
			fid: int;
			data: array of byte;
		Write =>
			fid, count: int;
		Stat =>
			fid: int;
			stat: OSys->Dir;
		}

		read:	fn(fd: ref Sys->FD, msize: int): ref ORmsg;
	};

	MAXRPC: con 128 + OSys->ATOMICIO;
	DIRLEN: con 116;

	Tnop,		#  0 
	Rnop,		#  1 
	Terror,		#  2, illegal 
	Rerror,		#  3 
	Tflush,		#  4 
	Rflush,		#  5 
	Tclone,		#  6 
	Rclone,		#  7 
	Twalk,		#  8 
	Rwalk,		#  9 
	Topen,		# 10 
	Ropen,		# 11 
	Tcreate,		# 12 
	Rcreate,		# 13 
	Tread,		# 14 
	Rread,		# 15 
	Twrite,		# 16 
	Rwrite,		# 17 
	Tclunk,		# 18 
	Rclunk,		# 19 
	Tremove,		# 20 
	Rremove,		# 21 
	Tstat,		# 22 
	Rstat,		# 23 
	Twstat,		# 24 
	Rwstat,		# 25 
	Tsession,		# 26
	Rsession,		# 27
	Tattach,		# 28 
	Rattach,		# 29
	Tmax		: con iota;

	Einuse		: con "fid already in use";
	Ebadfid		: con "bad fid";
	Eopen		: con "fid already opened";
	Enotfound	: con "file does not exist";
	Enotdir		: con "not a directory";
	Eperm		: con "permission denied";
	Ebadarg		: con "bad argument";
	Eexists		: con "file already exists";
};
