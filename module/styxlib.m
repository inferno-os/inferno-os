#
# deprecated: use styxservers(2) instead
#

Styxlib: module
{
	PATH: con "/dis/lib/styxlib.dis";
	Chan: adt {
		fid: int;
		qid: Sys->Qid;
		open: int;
		mode: int;
		uname: string;
		path: string;
		data: array of byte;

		isdir: fn(c: self ref Chan): int;
	};

	Dirtab: adt {
		name: string;
		qid: Sys->Qid;
		length: big;
		perm: int;
	};

	Styxserver: adt {
		fd: ref Sys->FD;
		chans: array of list of ref Chan;
		uname: string;
		msize: int;

		new: fn(fd: ref Sys->FD): (chan of ref Styx->Tmsg, ref Styxserver);
		reply: fn(srv: self ref Styxserver, m: ref Styx->Rmsg): int;

		fidtochan: fn(srv: self ref Styxserver, fid: int): ref Chan;
		newchan: fn(srv: self ref Styxserver, fid: int): ref Chan;
		chanfree: fn(srv: self ref Styxserver, c: ref Chan);
		chanlist: fn(srv: self ref Styxserver): list of ref Chan;
		clone: fn(srv: self ref Styxserver, c: ref Chan, fid: int): ref Chan;

		devversion: fn(srv: self ref Styxserver, m: ref Styx->Tmsg.Version): int;
		devauth: fn(srv: self ref Styxserver, m: ref Styx->Tmsg.Auth);
		devattach: fn(srv: self ref Styxserver, m: ref Styx->Tmsg.Attach): ref Chan;
		devflush: fn(srv: self ref Styxserver, m: ref Styx->Tmsg.Flush);
		devwalk: fn(srv: self ref Styxserver, m: ref Styx->Tmsg.Walk,
							gen: Dirgenmod, tab: array of Dirtab): ref Chan;
		devclunk: fn(srv: self ref Styxserver, m: ref Styx->Tmsg.Clunk): ref Chan;
		devstat: fn(srv: self ref Styxserver, m: ref Styx->Tmsg.Stat,
							gen: Dirgenmod, tab: array of Dirtab);
		devdirread: fn(srv: self ref Styxserver, m: ref Styx->Tmsg.Read,
							gen: Dirgenmod, tab: array of Dirtab);
		devopen: fn(srv: self ref Styxserver, m: ref Styx->Tmsg.Open,
							gen: Dirgenmod, tab: array of Dirtab): ref Chan;
		devremove: fn(srv: self ref Styxserver, m: ref Styx->Tmsg.Remove): ref Chan;
	};

	init:	fn(s: Styx): string;

	readbytes: fn(m: ref Styx->Tmsg.Read, d: array of byte): ref Styx->Rmsg.Read;
	readnum: fn(m: ref Styx->Tmsg.Read, val, size: int): ref Styx->Rmsg.Read;
	readstr: fn(m: ref Styx->Tmsg.Read, d: string): ref Styx->Rmsg.Read;

	openok: fn(omode, perm: int, uname, funame, fgname: string): int;
	openmode: fn(o: int): int;
	
	devdir: fn(c: ref Chan, qid: Sys->Qid, n: string, length: big,
				user: string, perm: int): Sys->Dir;

	dirgenmodule: fn(): Dirgenmod;
	dirgen: fn(srv: ref Styxserver, c: ref Chan, tab: array of Dirtab, i: int): (int, Sys->Dir);

	Einuse		: con "fid already in use";
	Ebadfid		: con "bad fid";
	Eopen		: con "fid already opened";
	Enotfound	: con "file does not exist";
	Enotdir		: con "not a directory";
	Eperm		: con "permission denied";
	Ebadarg		: con "bad argument";
	Eexists		: con "file already exists";
};


Dirgenmod: module {
	dirgen: fn(srv: ref Styxlib->Styxserver, c: ref Styxlib->Chan,
			tab: array of Styxlib->Dirtab, i: int): (int, Sys->Dir);
};
