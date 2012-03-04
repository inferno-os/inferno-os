Styxservers: module
{
	PATH: con "/dis/lib/styxservers.dis";

	Fid: adt {
		fid:		int;		# client's fid
		path:		big;		# file's 64-bit unique path
		qtype:	int;		# file's qid type (eg, Sys->QTDIR if directory)
		isopen:	int;		# non-zero if file is open
		mode:	int;		# if open, the open mode
		doffset:	(int, int);	# (internal) cache of directory offset
		uname:	string;	# user name from original attach
		param:	string;	# attach aname from original attach
		data:		array of byte;	# application data

		clone:	fn(f: self ref Fid, nf: ref Fid): ref Fid;
		open:	fn(f: self ref Fid, mode: int, qid: Sys->Qid);
		walk:	fn(f: self ref Fid, qid: Sys->Qid);
	};

	Navigator: adt {
		c:		chan of ref Navop;
		reply:	chan of (ref Sys->Dir, string);

		new:		fn(c: chan of ref Navop): ref Navigator;
		stat:		fn(t: self ref Navigator, q: big): (ref Sys->Dir, string);
		walk:	fn(t: self ref Navigator, parentq: big, name: string): (ref Sys->Dir, string);
		readdir:	fn(t: self ref Navigator, q: big, offset, count: int): array of ref Sys->Dir;
	};

	Navop: adt {
		reply:	chan of (ref Sys->Dir, string);	# channel for reply
		path:		big;		# file or directory path
		pick {
		Stat =>
		Walk =>
			name: string;
		Readdir =>
			offset:	int;	# index (origin 0) of first directory entry to return
			count: 	int;	# number of directory entries requested
		}
	};

	Styxserver: adt {
		fd:		ref Sys->FD;		# file server end of connection
		fids:		array of list of ref Fid;	# hash table of fids
		fidlock:	chan of int;
		t:		ref Navigator;	# name space navigator for this server
		rootpath:	big;		# Qid.path of root of its name space
		msize:	int;		# negotiated Styx message size
		replychan:	chan of ref Styx->Rmsg;

		new:		fn(fd: ref Sys->FD, t: ref Navigator, rootpath: big): (chan of ref Styx->Tmsg, ref Styxserver);
		reply:	fn(srv: self ref Styxserver, m: ref Styx->Rmsg): int;
		replydirect:	fn(srv: self ref Styxserver, m: ref Styx->Rmsg): int;
		error:	fn(srv: self ref Styxserver, m: ref Styx->Tmsg, msg: string);

		# protocol operations
		attach:	fn(srv: self ref Styxserver, m: ref Styx->Tmsg.Attach): ref Fid;
		clunk:	fn(srv: self ref Styxserver, m: ref Styx->Tmsg.Clunk): ref Fid;
		walk:	fn(srv: self ref Styxserver, m: ref Styx->Tmsg.Walk): ref Fid;
		open:	fn(srv: self ref Styxserver, m: ref Styx->Tmsg.Open): ref Fid;
		read:		fn(srv: self ref Styxserver, m: ref Styx->Tmsg.Read): ref Fid;
		remove:	fn(srv: self ref Styxserver, m: ref Styx->Tmsg.Remove): ref Fid;
		stat:		fn(srv: self ref Styxserver, m: ref Styx->Tmsg.Stat);

		default:	fn(srv: self ref Styxserver, gm: ref Styx->Tmsg);

		# check validity but don't reply
		cancreate:	fn(srv: self ref Styxserver, m: ref Styx->Tmsg.Create): (ref Fid, int, ref Sys->Dir, string);
		canopen:		fn(srv: self ref Styxserver, m: ref Styx->Tmsg.Open): (ref Fid, int, ref Sys->Dir, string);
		canremove:	fn(srv: self ref Styxserver, m: ref Styx->Tmsg.Remove): (ref Fid, big, string);
		canread:		fn(srv: self ref Styxserver, m: ref Styx->Tmsg.Read): (ref Fid, string);
		canwrite:		fn(srv: self ref Styxserver, m: ref Styx->Tmsg.Write): (ref Fid, string);

		# fid management
		getfid:	fn(srv: self ref Styxserver, fid: int): ref Fid;
		newfid:	fn(srv: self ref Styxserver, fid: int): ref Fid;
		delfid:	fn(srv: self ref Styxserver, c: ref Fid);
		allfids:	fn(srv: self ref Styxserver): list of ref Fid;

		iounit:	fn(srv: self ref Styxserver): int;
	};

	init:		fn(styx: Styx);
	traceset:	fn(on: int);

	readbytes: fn(m: ref Styx->Tmsg.Read, d: array of byte): ref Styx->Rmsg.Read;
	readstr: fn(m: ref Styx->Tmsg.Read, s: string): ref Styx->Rmsg.Read;

	openok:	fn(uname: string, omode, perm: int, fuid, fgid: string): int;
	openmode: fn(o: int): int;
	
	Einuse:	con "fid already in use";
	Ebadfid:	con "bad fid";
	Eopen:	con "fid already opened";
	Enotfound:	con "file does not exist";
	Enotdir:	con "not a directory";
	Eperm:	con "permission denied";
	Ebadarg:	con "bad argument";
	Eexists:	con "file already exists";
	Emode:	con "open/create -- unknown mode";
	Eoffset:	con "read/write -- bad offset";
	Ecount:	con "read/write -- count negative or exceeds msgsize";
	Enotopen: con "read/write -- on non open fid";
	Eaccess:	con "read/write -- not open in suitable mode";
	Ename:		con "bad character in file name";
	Edot:		con ". and .. are illegal names";
};

Nametree: module {
	PATH: con "/dis/lib/nametree.dis";
	Tree: adt {
		c:		chan of ref Treeop;
		reply:	chan of string;

		quit:		fn(t: self ref Tree);
		create:	fn(t: self ref Tree, parent: big, d: Sys->Dir): string;
		wstat:	fn(t: self ref Tree, path: big, d: Sys->Dir): string;
		remove:	fn(t: self ref Tree, path: big): string;
		getpath:	fn(t: self ref Tree, path: big): string;
	};
	Treeop: adt {
		reply: chan of string;
		q: big;
		pick {
		Create or
		Wstat =>
			d: Sys->Dir;
		Remove =>
		Getpath =>
		}
	};
	init:		fn();
	start:		fn(): (ref Tree, chan of ref Styxservers->Navop);
};
