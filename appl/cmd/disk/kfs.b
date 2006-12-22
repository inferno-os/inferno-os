implement Kfs;

#
# Copyright © 1991-2003 Lucent Technologies Inc.
# Limbo version Copyright © 2004 Vita Nuova Holdings Limited
#

#
# TO DO:
#	- sync proc; Bmod; process structure
#	- swiz?

include "sys.m";
	sys: Sys;
	Qid, Dir: import Sys;
	DMEXCL, DMAPPEND, DMDIR: import Sys;
	QTEXCL, QTAPPEND, QTDIR: import Sys;

include "draw.m";

include "styx.m";
	styx: Styx;
	Tmsg, Rmsg: import styx;
	NOFID, OEXEC, ORCLOSE, OREAD, OWRITE, ORDWR, OTRUNC: import Styx;
	IOHDRSZ: import Styx;

include "daytime.m";
	daytime: Daytime;
	now: import daytime;

include "arg.m";

Kfs: module
{
	init:	fn(nil: ref Draw->Context, nil: list of string);
};

MAXBUFSIZE:	con 16*1024;

#
#  fundamental constants
#
NAMELEN: con 28;	# size of names, including null byte
NDBLOCK:	con 6;	# number of direct blocks in Dentry
MAXFILESIZE:	con big 16r7FFFFFFF;	# Plan 9's limit (kfs's size is signed)

SUPERADDR: con 1;
ROOTADDR: con 2;

QPDIR:	con int (1<<31);
QPNONE: con 0;
QPROOT: con 1;
QPSUPER: con 2;

#
# don't change, these are the mode bits on disc
#
DALLOC: con 16r8000;
DDIR:	con 16r4000;
DAPND:	con 16r2000;
DLOCK:	con 16r1000;
DREAD:	con 4;
DWRITE:	con 2;
DEXEC:	con 1;

#
# other constants
#

MINUTE:	con 60;
TLOCK:	con 5*MINUTE;
NTLOCK:	con 200;	# number of active file locks

Buffering: con 1;

FID1, FID2, FID3: con 1+iota;

None: con 0;	# user ID for "none"
Noworld: con 9999;	# conventional id for "noworld" group

Lock: adt
{
	c: chan of int;
	new:	fn(): ref Lock;
	lock:	fn(c: self ref Lock);
	canlock:	fn(c: self ref Lock): int;
	unlock:	fn(c: self ref Lock);
};

Dentry: adt
{
	name:	string;
	uid:	int;
	gid:	int;
	muid:	int;	# not set by plan 9's kfs
	mode:	int;	# mode bits on disc: DALLOC etc
	qid:	Qid;	# 9p1 format on disc
	size:	big;	# only 32-bits on disc, and Plan 9 limits it to signed
	atime:	int;
	mtime:	int;

	iob:	ref Iobuf;	# locked block containing directory entry, when in memory
	buf:	array of byte;	# pointer into block to packed directory entry, when in memory
	mod:	int;	# bits of buf that need updating

	unpack:	fn(a: array of byte): ref Dentry;
	get:	fn(p: ref Iobuf, slot: int): ref Dentry;
	geta:	fn(d: ref Device, addr: int, slot: int, qpath: int, mode: int): (ref Dentry, string);
	getd:	fn(f: ref File, mode: int): (ref Dentry, string);
	put:	fn(d: self ref Dentry);
	access:	fn(d: self ref Dentry, f: int, uid: int);
	change:	fn(d: self ref Dentry, f: int);
	release:	fn(d: self ref Dentry);
	getblk:	fn(d: self ref Dentry, a: int, tag: int): ref Iobuf;
	getblk1:	fn(d: self ref Dentry, a: int, tag: int): ref Iobuf;
	rel2abs:	fn(d: self ref Dentry, a: int, tag: int, putb: int): int;
	trunc:	fn(d: self ref Dentry, uid: int);
	update:	fn(d: self ref Dentry);
	print:	fn(d: self ref Dentry);
};

Uname, Uids, Umode, Uqid, Usize, Utime: con 1<<iota;	# Dentry.mod

#
# disc structure:
#	Tag:	pad[2] tag[2] path[4]
Tagsize: con 2+2+4;

Tag: adt
{
	tag:	int;
	path:	int;

	unpack:	fn(a: array of byte): Tag;
	pack:	fn(t: self Tag, a: array of byte);
};

Superb: adt
{
	iob:	ref Iobuf;

	fstart:	int;
	fsize:	int;
	tfree:	int;
	qidgen:	int;		# generator for unique ids

	fsok:	int;

	fbuf:	array of byte;	# nfree[4] free[FEPERBLK*4]; aliased into containing block

	get:	fn(dev: ref Device, flags: int): ref Superb;
	touched:	fn(s: self ref Superb);
	put:	fn(s: self ref Superb);
	print:	fn(s: self ref Superb);

	pack:	fn(s: self ref Superb, a: array of byte);
	unpack:	fn(a: array of byte): ref Superb;
};

Device: adt
{
	fd:	ref Sys->FD;
	ronly:	int;
	# could put locks here if necessary
	# partitioning by ds(3)
};

#
# one for each locked qid
#
Tlock: adt
{
	dev:	ref Device;
	time:	int;
	qpath:	int;
	file:	cyclic ref File;	# TO DO: probably not needed
};

File: adt
{
	qlock:	chan of int;
	qid:	Qid;
	wpath:	ref Wpath;
	tlock:	cyclic ref Tlock;		# if file is locked
	fs:	ref Device;
	addr:	int;
	slot:	int;
	lastra:	int;		# read ahead address
	fid:	int;
	uid:	int;
	open:	int;
	cons:	int;	# if opened by console
	doffset: big;	# directory reading
	dvers:	int;
	dslot:	int;

	new:	fn(fid: int): ref File;
	access:	fn(f: self ref File, d: ref Dentry, mode: int): int;
	lock:	fn(f: self ref File);
	unlock:	fn(f: self ref File);
};

FREAD, FWRITE, FREMOV, FWSTAT: con 1<<iota;	# File.open

Chan: adt
{
	fd:	ref Sys->FD;			# fd request came in on
#	rlock, wlock: QLock;		# lock for reading/writing messages on cp
	flags:	int;
	flist:	list of ref File;			# active files
	fqlock:	chan of int;
#	reflock:	RWLock;		# lock for Tflush
	msize:	int;			# version

	new:	fn(fd: ref Sys->FD): ref Chan;
	getfid:	fn(c: self ref Chan, fid: int, flag: int): ref File;
	putfid:	fn(c: self ref Chan, f: ref File);
	flock: fn(nil: self ref Chan);
	funlock:	fn(nil: self ref Chan);
};

Hiob: adt
{
	link:	ref Iobuf;	# TO DO: eliminate circular list
	lk:	ref Lock;
	niob: int;

	newbuf:	fn(h: self ref Hiob): ref Iobuf;
};

Iobuf: adt
{
	qlock:	chan of int;
	dev:	ref Device;
	fore:	cyclic ref Iobuf;		# lru hash chain
	back:	cyclic ref Iobuf;		# for lru
	iobuf:	array of byte;		# only active while locked
	xiobuf:	array of byte;	# "real" buffer pointer
	addr:	int;
	flags:	int;

	get:	fn(dev: ref Device, addr: int, flags: int):ref Iobuf;
	put:	fn(iob: self ref Iobuf);
	lock:	fn(iob: self ref Iobuf);
	canlock:	fn(iob: self ref Iobuf): int;
	unlock:	fn(iob: self ref Iobuf);

	checktag:	fn(iob: self ref Iobuf, tag: int, qpath: int): int;
	settag:	fn(iob: self ref Iobuf, tag: int, qpath: int);
};

Wpath: adt
{
	up: cyclic ref Wpath;		# pointer upwards in path
	addr: int;		# directory entry addr
	slot: int;		# directory entry slot
};

#
#  error codes generated from the file server
#
Eaccess: con "access permission denied";
Ealloc: con "phase error -- directory entry not allocated";
Eauth: con "authentication failed";
Eauthmsg: con "kfs: authentication not required";
Ebadspc: con "attach -- bad specifier";
Ebadu: con "attach -- privileged user";
Ebroken: con "close/read/write -- lock is broken";
Echar: con "bad character in directory name";
Econvert: con "protocol botch";
Ecount: con "read/write -- count too big";
Edir1: con "walk -- in a non-directory";
Edir2: con "create -- in a non-directory";
Edot: con "create -- . and .. illegal names";
Eempty: con "remove -- directory not empty";
Eentry: con "directory entry not found";
Eexist: con "create -- file exists";
Efid: con "unknown fid";
Efidinuse: con "fid already in use";
Efull: con "file system full";
Elocked: con "open/create -- file is locked";
Emode: con "open/create -- unknown mode";
Ename: con "create/wstat -- bad character in file name";
Enotd: con "wstat -- attempt to change directory";
Enotg: con "wstat -- not in group";
Enotl: con "wstat -- attempt to change length";
Enotm: con "wstat -- unknown type/mode";
Enotu: con "wstat -- not owner";
Eoffset: con "read/write -- offset negative";
Eopen: con "read/write -- on non open fid";
Ephase: con "phase error -- cannot happen";
Eqid: con "phase error -- qid does not match";
Eqidmode: con "wstat -- qid.qtype/dir.mode mismatch";
Eronly: con "file system read only";
Ersc: con "it's russ's fault.  bug him.";
Esystem: con "kfs system error";
Etoolong: con "name too long";
Etoobig: con "write -- file size limit";
Ewalk: con "walk -- too many (system wide)";

#
#  tags on block
#
Tnone,
Tsuper,			# the super block
Tdir,			# directory contents
Tind1,			# points to blocks
Tind2,			# points to Tind1
Tfile,			# file contents
Tfree,			# in free list
Tbuck,			# cache fs bucket
Tvirgo,			# fake worm virgin bits
Tcache,			# cw cache things
MAXTAG: con iota;

#
#  flags to Iobuf.get
#
	Bread,	# read the block if miss
	Bprobe,	# return null if miss
	Bmod,	# set modified bit in buffer
	Bimm,	# set immediate bit in buffer
	Bres:		# never renamed
	con 1<<iota;

#
#  check flags
#
	Crdall,	# read all files
	Ctag,	# rebuild tags
	Cpfile,	# print files
	Cpdir,	# print directories
	Cfree,	# rebuild free list
	Cream,	# clear all bad tags
	Cbad,	# clear all bad blocks
	Ctouch,	# touch old dir and indir
	Cquiet:	# report just nasty things
	con 1<<iota;

#
#  buffer size variables, determined by RBUFSIZE
#
RBUFSIZE: int;
BUFSIZE: int;
DIRPERBUF: int;
INDPERBUF: int;
INDPERBUF2: int;
FEPERBUF: int;

emptyblock: array of byte;

wrenfd: ref Sys->FD;
thedevice: ref Device;
devnone: ref Device;
wstatallow := 0;
writeallow := 0;
writegroup := 0;

ream := 0;
readonly := 0;
noatime := 0;
localfs: con 1;
conschan: ref Chan;
consuid := -1;
consgid := -1;
debug := 0;
kfsname: string;
consoleout: chan of string;
mainlock: ref Lock;
pids: list of int;

noqid: Qid;

init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	styx = load Styx Styx->PATH;
	daytime = load Daytime Daytime->PATH;

	styx->init();


	arg := load Arg Arg->PATH;
	if(arg == nil)
		error(sys->sprint("can't load %s: %r", Arg->PATH));
	arg->init(args);
	arg->setusage("disk/kfs [-r [-b bufsize]] [-cADPRW] [-n name] kfsfile");
	bufsize := 1024;
	nocheck := 0;
	while((o := arg->opt()) != 0)
		case o {
		'c' => nocheck = 1;
		'r' =>	ream = 1;
		'b' => bufsize = int arg->earg();
		'D' => debug = !debug;
		'P' => writeallow = 1;
		'W' => wstatallow = 1;
		'R' => readonly = 1;
		'A' => noatime = 1;	# mainly useful for flash
		'n' => kfsname = arg->earg();
		* =>	arg->usage();
		}
	args = arg->argv();
	if(args == nil)
		arg->usage();
	arg = nil;

	devnone = ref Device(nil, 1);
	mainlock = Lock.new();

	conschan = Chan.new(nil);
	conschan.msize = Styx->MAXRPC;

	mode := Sys->ORDWR;
	if(readonly)
		mode = Sys->OREAD;
	wrenfd = sys->open(hd args, mode);
	if(wrenfd == nil)
		error(sys->sprint("can't open %s: %r", hd args));
	thedevice = ref Device(wrenfd, readonly);
	if(ream){
		if(bufsize <= 0 || bufsize % 512 || bufsize > MAXBUFSIZE)
			error(sys->sprint("invalid block size %d", bufsize));
		RBUFSIZE = bufsize;
		wrenream(thedevice);
	}else{
		if(!wreninit(thedevice))
			error("kfs magic in trouble");
	}
	BUFSIZE = RBUFSIZE - Tagsize;
	DIRPERBUF = BUFSIZE / Dentrysize;
	INDPERBUF = BUFSIZE / 4;
	INDPERBUF2 = INDPERBUF * INDPERBUF;
	FEPERBUF = (BUFSIZE - Super1size - 4) / 4;
	emptyblock = array[RBUFSIZE] of {* => byte 0};

	iobufinit(30);

	if(ream){
		superream(thedevice, SUPERADDR);
		rootream(thedevice, ROOTADDR);
		wstatallow = writeallow = 1;
	}
	if(wrencheck(wrenfd))
		error("kfs super/root in trouble");

	if(!ream && !superok(0)){
		sys->print("kfs needs check\n");
		if(!nocheck)
			check(thedevice, Cquiet|Cfree);
	}

	(d, e) := Dentry.geta(thedevice, ROOTADDR, 0, QPROOT, Bread);
	if(d != nil && !(d.mode & DDIR))
		e = "not a directory";
	if(e != nil)
		error("bad root: "+e);
	if(debug)
		d.print();
	d.put();

	sys->pctl(Sys->FORKFD|Sys->NEWPGRP, nil);

	sys->pctl(Sys->NEWFD, wrenfd.fd :: 0 :: 1 :: 2 :: nil);
	wrenfd = sys->fildes(wrenfd.fd);
	thedevice.fd = wrenfd;

	c := chan of int;

	if(Buffering){
		spawn syncproc(c);
		pid := <-c;
		if(pid)
			pids = pid :: pids;
	}
	spawn consinit(c);
	pid := <- c;
	if(pid)
		pids = pid :: pids;

	spawn kfs(sys->fildes(0));
}

error(s: string)
{
	sys->fprint(sys->fildes(2), "kfs: %s\n", s);
	for(; pids != nil; pids = tl pids)
		kill(hd pids);
	raise "fail:error";
}

panic(s: string)
{
	sys->fprint(sys->fildes(2), "kfs: panic: %s\n", s);
	for(; pids != nil; pids = tl pids)
		kill(hd pids);
	raise "panic";
}

syncproc(c: chan of int)
{
	c <-= 0;
}

shutdown()
{
	for(; pids != nil; pids = tl pids)
		kill(hd pids);
	# TO DO: when Bmod deferred, must sync
	# sync super block
	if(superok(1)){
		# ;
	}
	iobufclear();
}

kill(pid: int)
{
	fd := sys->open("#p/"+string pid+"/ctl", Sys->OWRITE);
	if(fd != nil)
		sys->fprint(fd, "kill");
}

#
# limited file system support for console
#
kattach(fid: int): string
{
	return applycons(ref Tmsg.Attach(1, fid, NOFID, "adm", "")).t1;
}

kopen(oldfid: int, newfid: int, names: array of string, mode: int): string
{
	(r1, e1) := applycons(ref Tmsg.Walk(1, oldfid, newfid, names));
	if(r1 != nil){
		pick m := r1 {
		Walk =>
			if(len m.qids != len names){
				kclose(newfid);
				cprint(Eexist);
				return Eexist;
			}
		* =>
			return "unexpected reply";
		}
		(r1, e1) = applycons(ref Tmsg.Open(1, newfid, mode));
		if(e1 != nil){
			kclose(newfid);
			cprint(sys->sprint("open: %s", e1));
		}
	}
	return e1;
}

kread(fid: int, offset: int, nbytes: int): (array of byte, string)
{
	(r, e) := applycons(ref Tmsg.Read(1, fid, big offset, nbytes));
	if(r != nil){
		pick m := r {
		Read =>
			return (m.data, nil);
		* =>
			return (nil, "unexpected reply");
		}
	}
	cprint(sys->sprint("read error: %s", e));
	return (nil, e);
}

kclose(fid: int)
{
	applycons(ref Tmsg.Clunk(1, fid));
}

applycons(t: ref Tmsg): (ref Rmsg, string)
{
	r := apply(conschan, t);
	pick m := r {
	Error =>
		if(debug)
			cprint(sys->sprint("%s: %s\n", t.text(), m.ename));
		return (nil, m.ename);
	}
	return (r, nil);
}

#
# always reads /adm/users in userinit(), then
# optionally serves the command file, if used.
#
Req: adt {
	nbytes:	int;
	rc:	chan of (array of byte, string);
};

consinit(c: chan of int)
{
	kattach(FID1);
	userinit();
	if(kfsname == nil){
		c <-= 0;
		exit;
	}
	cfname := "kfs."+kfsname+".cmd";
	sys->bind("#s", "/chan", Sys->MBEFORE);
	file := sys->file2chan("/chan", cfname);
	if(file == nil)
		error(sys->sprint("can't create /chan/%s: %r", cfname));
	c <-= sys->pctl(0, nil);
	consc := chan of string;
	checkend := chan of int;
	cdata: array of byte;
	pending: ref Req;
	cfid := -1;
	for(;;) alt{
	(nil, nbytes, fid, rc) := <-file.read =>
		if(rc == nil)
			break;
		if(cfid == -1)
			cfid = fid;
		if(fid != cfid || pending != nil){
			rc <-= (nil, "kfs.cmd is busy");
			break;
		}
		if(cdata != nil){
			cdata = reply(rc, nbytes, cdata);
			break;
		}
		if(nbytes <= 0 || consoleout == nil){
			rc <-= (nil, nil);
			break;
		}
		pending = ref Req(nbytes, rc);
		consc = consoleout;
	(nil, data, fid, wc) := <-file.write =>
		if(cfid == -1)
			cfid = fid;
		if(wc == nil){
			if(fid == cfid){
				cfid = -1;
				pending = nil;
				cdata = nil;	# discard unread data from last command
				if((consc = consoleout) == nil)
					consc = chan of string;
			}
			break;
		}
		if(fid != cfid){
			wc <-= (0, "kfs.cmd is busy");
			break;
		}
		(nf, fld) := sys->tokenize(string data, " \t\n\r");
		if(nf < 1){
			wc <-= (0, "illegal kfs request");
			break;
		}
		case hd fld {
		"check" =>
			if(consoleout != nil){
				wc <-= (0, "check in progress");
				break;
			}
			f := 0;
			if(nf > 1){
				f = checkflags(hd tl fld);
				if(f < 0){
					wc <-= (0, "illegal check flag: "+hd tl fld);
					break;
				}
			}
			consoleout = chan of string;
			spawn checkproc(checkend, f);
			wc <-= (len data, nil);
			consc = consoleout;
		"users" or "user" =>
			cmd_users();
			wc <-= (len data, nil);
		"sync" =>
			# nothing TO DO until writes are buffered
			wc <-= (len data, nil);
		"allow" =>
			wstatallow = writeallow = 1;
			wc <-= (len data, nil);
		"allowoff" or "disallow" =>
			wstatallow = writeallow = 0;
			wc <-= (len data, nil);
		* =>
			wc <-= (0, "unknown kfs request");
			continue;
		}
	<-checkend =>
		consoleout = nil;
		consc = chan of string;
	s := <-consc =>
		#sys->print("<-%s\n", s);
		req := pending;
		pending = nil;
		if(req != nil)
			cdata = reply(req.rc, req.nbytes, array of byte s);
		else
			cdata = array of byte s;
		if(cdata != nil && cfid != -1)
			consc = chan of string;
	}
}

reply(rc: chan of (array of byte, string), nbytes: int, a: array of byte): array of byte
{
	if(len a < nbytes)
		nbytes = len a;
	rc <-= (a[0:nbytes], nil);
	if(nbytes == len a)
		return nil;
	return a[nbytes:];
}

checkproc(c: chan of int, flags: int)
{
	mainlock.lock();
	check(thedevice, flags);
	mainlock.unlock();
	c <-= 1;
}

#
# normal kfs service
#
kfs(rfd: ref Sys->FD)
{
	cp := Chan.new(rfd);
	while((t := Tmsg.read(rfd, cp.msize)) != nil){
		if(debug)
			sys->print("<- %s\n", t.text());
		r := apply(cp, t);
		pick m := r {
		Error =>
			r.tag = t.tag;
		}
		if(debug)
			sys->print("-> %s\n", r.text());
		rbuf := r.pack();
		if(rbuf == nil)
			panic("Rmsg.pack");
		if(sys->write(rfd, rbuf, len rbuf) != len rbuf)
			panic("mount write");
	}
	shutdown();
}

apply(cp: ref Chan, t: ref Tmsg): ref Rmsg
{
	mainlock.lock();	# TO DO: this is just to keep console and kfs from colliding
	r: ref Rmsg;
	pick m := t {
	Readerror =>
		error(sys->sprint("mount read error: %s", m.error));
	Version =>
		r = rversion(cp, m);
	Auth =>
		r = rauth(cp, m);
	Flush =>
		r = rflush(cp, m);
	Attach =>
		r = rattach(cp, m);
	Walk =>
		r = rwalk(cp, m);
	Open =>
		r = ropen(cp, m);
	Create =>
		r = rcreate(cp, m);
	Read =>
		r = rread(cp, m);
	Write =>
		r = rwrite(cp, m);
	Clunk =>
		r = rclunk(cp, m);
	Remove =>
		r = rremove(cp, m);
	Stat =>
		r = rstat(cp, m);
	Wstat =>
		r = rwstat(cp, m);
	* =>
		panic("Styx mtype");
		return nil;
	}
	mainlock.unlock();
	return r;
}

rversion(cp: ref Chan, t: ref Tmsg.Version): ref Rmsg
{
	cp.msize = RBUFSIZE+IOHDRSZ;
	if(cp.msize < Styx->MAXRPC)
		cp.msize = Styx->MAXRPC;
	(msize, version) := styx->compatible(t, Styx->MAXRPC, Styx->VERSION);
	if(msize < 256)
		return ref Rmsg.Error(t.tag, "message size too small");
	return ref Rmsg.Version(t.tag, msize, version);
}

rauth(nil: ref Chan, t: ref Tmsg.Auth): ref Rmsg
{
	return ref Rmsg.Error(t.tag, Eauthmsg);
}

rflush(nil: ref Chan, t: ref Tmsg.Flush): ref Rmsg
{
	# runlock(cp.reflock);
	# wlock(cp.reflock);
	# wunlock(cp.reflock);
	# rlock(cp.reflock);
	return ref Rmsg.Flush(t.tag);
}

err(t: ref Tmsg, s: string): ref Rmsg.Error
{
	return ref Rmsg.Error(t.tag, s);
}

ferr(t: ref Tmsg, s: string, file: ref File, p: ref Iobuf): ref Rmsg.Error
{
	if(p != nil)
		p.put();
	if(file != nil)
		file.unlock();
	return ref Rmsg.Error(t.tag, s);
}

File.new(fid: int): ref File
{
	f := ref File;
	f.qlock = chan[1] of int;
	f.fid = fid;
	f.cons = 0;
	f.tlock = nil;
	f.wpath = nil;
	f.doffset = big 0;
	f.dvers = 0;
	f.dslot = 0;
	f.uid = None;
	f.cons = 0;
#	f.cuid = None;
	return f;
}

#
# returns a locked file structure
#

Chan.getfid(cp: self ref Chan, fid: int, flag: int): ref File
{
	if(fid == NOFID)
		return nil;
	cp.flock();
	for(l := cp.flist; l != nil; l = tl l){
		f := hd l;
		if(f.fid == fid){
			cp.funlock();
			if(flag)
				return nil;	# fid in use
			f.lock();
			if(f.fid == fid)
				return f;
			f.unlock();
			cp.flock();
		}
	}
	if(flag == 0){
		sys->print("kfs: cannot find %H.%ud", cp, fid);
		cp.funlock();
		return nil;
	}
	f := File.new(fid);
	f.lock();
	cp.flist = f :: cp.flist;
	cp.funlock();
	return f;
}

Chan.putfid(cp: self ref Chan, f: ref File)
{
	cp.flock();
	nl: list of ref File;
	for(x := cp.flist; x != nil; x = tl x)
		if(hd x != f)
			nl = hd x :: nl;
	cp.flist = nl;
	cp.funlock();
	f.unlock();
}

File.lock(f: self ref File)
{
	f.qlock <-= 1;
}

File.unlock(f: self ref File)
{
	<-f.qlock;
}

Chan.new(fd: ref Sys->FD): ref Chan
{
	c := ref Chan;
	c.fd = fd;
	c.fqlock = chan[1] of int;
#	rlock, wlock: QLock;		# lock for reading/writing messages on cp
	c.flags = 0;
#	reflock:	RWLock;		# lock for Tflush
	c.msize = 0;	# set by rversion
	return c;
}

Chan.flock(c: self ref Chan)
{
	c.fqlock <-= 1;
}

Chan.funlock(c: self ref Chan)
{
	<-c.fqlock;
}

rattach(cp: ref Chan, t: ref Tmsg.Attach): ref Rmsg
{
	if(t.aname != "" && t.aname != "main")
		return err(t, Ebadspc);
	file := cp.getfid(t.fid, 1);
	if(file == nil)
		return err(t, Efidinuse);
	p := Iobuf.get(thedevice, ROOTADDR, Bread);
	if(p == nil){
		cp.putfid(file);
		return err(t, "can't access root block");
	}
	d := Dentry.get(p, 0);
	if(d == nil || p.checktag(Tdir, QPROOT) || (d.mode & DALLOC) == 0 || (d.mode & DDIR) == 0){
		p.put();
		cp.putfid(file);
		return err(t, Ealloc);
	}
	if(file.access(d, DEXEC)){
		p.put();
		cp.putfid(file);
		return err(t, Eaccess);
	}
	d.access(FREAD, file.uid);
	file.fs = thedevice;
	file.qid = d.qid;
	file.addr = p.addr;
	file.slot = 0;
	file.open = 0;
	file.uid = strtouid(t.uname);
	file.wpath = nil;
	p.put();
	qid := file.qid;
	file.unlock();
	return ref Rmsg.Attach(t.tag, qid);
}

clone(nfile: ref File, file: ref File)
{
	nfile.qid = file.qid;
	nfile.wpath = file.wpath;
	nfile.fs = file.fs;
	nfile.addr = file.addr;
	nfile.slot = file.slot;
	nfile.uid = file.uid;
#	nfile.cuid = None;
	nfile.open = file.open & ~FREMOV;
}

walkname(file: ref File, wname: string): (string, Qid)
{
	#
	# File must not have been opened for I/O by an open
	# or create message and must represent a directory.
	#
	if(file.open != 0)
		return (Emode, noqid);

	(d, e) := Dentry.getd(file, Bread);
	if(d == nil)
		return (e, noqid);
	if(!(d.mode & DDIR)){
		d.put();
		return (Edir1, noqid);
	}

	#
	# For walked elements the implied user must
	# have permission to search the directory.
	#
	if(file.access(d, DEXEC)){
		d.put();
		return (Eaccess, noqid);
	}
	d.access(FREAD, file.uid);

	if(wname == "." || wname == ".." && file.wpath == nil){
		d.put();
		return (nil, file.qid);
	}

	d1: ref Dentry;	# entry for wname, if found
	slot: int;

	if(wname == ".."){
		d.put();
		addr := file.wpath.addr;
		slot = file.wpath.slot;
		(d1, e) = Dentry.geta(file.fs, addr, slot, QPNONE, Bread);
		if(d1 == nil)
			return (e, noqid);
		file.wpath = file.wpath.up;
	}else{

	Search:
		for(addr := 0; ; addr++){
			if(d.iob == nil){
				(d, e) = Dentry.getd(file, Bread);
				if(d == nil)
					return (e, noqid);
			}
			p1 := d.getblk1(addr, 0);
			if(p1 == nil || p1.checktag(Tdir, int d.qid.path)){
				if(p1 != nil)
					p1.put();
				return (Eentry, noqid);
			}
			for(slot = 0; slot < DIRPERBUF; slot++){
				d1 = Dentry.get(p1, slot);
				if(!(d1.mode & DALLOC))
					continue;
				if(wname != d1.name)
					continue;
				#
				# update walk path
				#
				file.wpath = ref Wpath(file.wpath, file.addr, file.slot);
				slot += DIRPERBUF*addr;
				break Search;
			}
			p1.put();
		}
		d.put();
	}

	file.addr = d1.iob.addr;
	file.slot = slot;
	file.qid = d1.qid;
	d1.put();
	return (nil, file.qid);
}

rwalk(cp: ref Chan, t: ref Tmsg.Walk): ref Rmsg
{
	nfile, tfile: ref File;
	q: Qid;

	# The file identified by t.fid must be valid in the
	# current session and must not have been opened for I/O
	# by an open or create message.

	if((file := cp.getfid(t.fid, 0)) == nil)
		return err(t, Efid);
	if(file.open != 0)
		return ferr(t, Emode, file, nil);

	# If newfid is not the same as fid, allocate a new file;
	# a side effect is checking newfid is not already in use (error);
	# if there are no names to walk this will be equivalent to a
	# simple 'clone' operation.
	# Otherwise, fid and newfid are the same and if there are names
	# to walk make a copy of 'file' to be used during the walk as
	# 'file' must only be updated on success.
	# Finally, it's a no-op if newfid is the same as fid and t.nwname
	# is 0.

	nwqid := 0;
	if(t.newfid != t.fid){
		if((nfile = cp.getfid(t.newfid, 1)) == nil)
			return ferr(t, Efidinuse, file, nil);
	}
	else if(len t.names != 0)
		nfile = tfile = File.new(NOFID);
	else{
		file.unlock();
		return ref Rmsg.Walk(t.tag, nil);
	}
	clone(nfile, file);

	r := ref Rmsg.Walk(t.tag, array[len t.names] of Qid);
	error: string;
	for(nwname := 0; nwname < len t.names; nwname++){
		(error, q) = walkname(nfile, t.names[nwname]);
		if(error != nil)
			break;
		r.qids[nwqid++] = q;
	}

	if(len t.names == 0){

		# Newfid must be different to fid (see above)
		# so this is a simple 'clone' operation - there's
		# nothing to do except unlock unless there's
		# an error.

		nfile.unlock();
		if(error != nil)
			cp.putfid(nfile);
	}else if(nwqid < len t.names){
		#
		# Didn't walk all elements, 'clunk' nfile
		# and leave 'file' alone.
		# Clear error if some of the elements were
		# walked OK.
		#
		if(nfile != tfile)
			cp.putfid(nfile);
		if(nwqid != 0)
			error = nil;
		r.qids = r.qids[0:nwqid];
	}else{
		#
		# Walked all elements. If newfid is the same
		# as fid must update 'file' from the temporary
		# copy used during the walk.
		# Otherwise just unlock (when using tfile there's
		# no need to unlock as it's a local).
		#
		if(nfile == tfile){
			file.qid = nfile.qid;
			file.wpath = nfile.wpath;
			file.addr = nfile.addr;
			file.slot = nfile.slot;
		}else
			nfile.unlock();
	}
	file.unlock();

	if(error != nil)
		return err(t, error);
	return r;
}

ropen(cp: ref Chan, f: ref Tmsg.Open): ref Rmsg
{
	wok := cp == conschan || writeallow;

	if((file := cp.getfid(f.fid, 0)) == nil)
		return err(f, Efid);

	#
	# if remove on close, check access here
	#
	ro := isro(file.fs) || (writegroup && !ingroup(file.uid, writegroup));
	if(f.mode & ORCLOSE){
		if(ro)
			return ferr(f, Eronly, file, nil);
		#
		# check on parent directory of file to be deleted
		#
		if(file.wpath == nil || file.wpath.addr == file.addr)
			return ferr(f, Ephase, file, nil);
		p := Iobuf.get(file.fs, file.wpath.addr, Bread);
		if(p == nil || p.checktag(Tdir, QPNONE))
			return ferr(f, Ephase, file, p);
		if((d := Dentry.get(p, file.wpath.slot)) == nil || !(d.mode & DALLOC))
			return ferr(f, Ephase, file, p);
		if(file.access(d, DWRITE))
			return ferr(f, Eaccess, file, p);
		p.put();
	}
	(d, e) := Dentry.getd(file, Bread);
	if(d == nil)
		return ferr(f, e, file, nil);
	p := d.iob;
	qid := d.qid;
	fmod: int;
	case f.mode & 7 {

	OREAD =>
		if(file.access(d, DREAD) && !wok)
			return ferr(f, Eaccess, file, p);
		fmod = FREAD;

	OWRITE =>
		if((d.mode & DDIR) || (file.access(d, DWRITE) && !wok))
			return ferr(f, Eaccess, file, p);
		if(ro)
			return ferr(f, Eronly, file, p);
		fmod = FWRITE;

	ORDWR =>
		if((d.mode & DDIR)
		|| (file.access(d, DREAD) && !wok)
		|| (file.access(d, DWRITE) && !wok))
			return ferr(f, Eaccess, file, p);
		if(ro)
			return ferr(f, Eronly, file, p);
		fmod = FREAD+FWRITE;

	OEXEC =>
		if((d.mode & DDIR) || (file.access(d, DEXEC) && !wok))
			return ferr(f, Eaccess, file, p);
		fmod = FREAD;

	* =>
		return ferr(f, Emode, file, p);
	}
	if(f.mode & OTRUNC){
		if((d.mode & DDIR) || (file.access(d, DWRITE) && !wok))
			return ferr(f, Eaccess, file, p);
		if(ro)
			return ferr(f, Eronly, file, p);
	}
	if(d.mode & DLOCK){
		if((t := tlocked(file, d)) == nil)
			return ferr(f, Elocked, file, p);
		file.tlock = t;
		t.file = file;
	}
	if(f.mode & ORCLOSE)
		fmod |= FREMOV;
	file.open = fmod;
	if((f.mode & OTRUNC) && !(d.mode & DAPND)){
		d.trunc(file.uid);
		qid.vers = d.qid.vers;
	}
	file.lastra = 1;
	p.put();
	file.unlock();
	return ref Rmsg.Open(f.tag, qid, cp.msize-IOHDRSZ);
}

rcreate(cp: ref Chan, f: ref Tmsg.Create): ref Rmsg
{
	wok := cp == conschan || writeallow;

	if((file := cp.getfid(f.fid, 0)) == nil)
		return err(f, Efid);
	if(isro(file.fs) || (writegroup && !ingroup(file.uid, writegroup)))
		return ferr(f, Eronly, file, nil);

	(d, e) := Dentry.getd(file, Bread);
	if(e != nil)
		return ferr(f, e, file, nil);
	p := d.iob;
	if(!(d.mode & DDIR))
		return ferr(f, Edir2, file, p);
	if(file.access(d, DWRITE) && !wok)
		return ferr(f, Eaccess, file, p);
	d.access(FREAD, file.uid);

	#
	# Check the name is valid and will fit in an old
	# directory entry.
	#
	if((l := checkname9p2(f.name)) == 0)
		return ferr(f, Ename, file, p);
	if(l+1 > NAMELEN)
		return ferr(f, Etoolong, file, p);
	if(f.name == "." || f.name == "..")
		return ferr(f, Edot, file, p);

	addr1 := 0;	# block with first empty slot, if any
	slot1 := 0;
	for(addr := 0; ; addr++){
		if((p1 := d.getblk(addr, 0)) == nil){
			if(addr1 != 0)
				break;
			p1 = d.getblk(addr, Tdir);
		}
		if(p1 == nil)
			return ferr(f, Efull, file, p);
		if(p1.checktag(Tdir, int d.qid.path)){
			p1.put();
			return ferr(f, Ephase, file, p);
		}
		for(slot := 0; slot < DIRPERBUF; slot++){
			d1 := Dentry.get(p1, slot);
			if(!(d1.mode & DALLOC)){
				if(addr1 == 0){
					addr1 = p1.addr;
					slot1 = slot + addr*DIRPERBUF;
				}
				continue;
			}
			if(f.name == d1.name){
				p1.put();
				return ferr(f, Eexist, file, p);
			}
		}
		p1.put();
	}

	fmod: int;

	case f.mode & 7 {
	OEXEC or
	OREAD =>		# seems only useful to make directories
		fmod = FREAD;

	OWRITE =>
		fmod = FWRITE;

	ORDWR =>
		fmod = FREAD+FWRITE;

	* =>
		return ferr(f, Emode, file, p);
	}
	if(f.perm & DMDIR)
		if((f.mode & OTRUNC) || (f.perm & DMAPPEND) || (fmod & FWRITE))
			return ferr(f, Eaccess, file, p);

	# do it

	path := qidpathgen(file.fs);
	if((p1 := Iobuf.get(file.fs, addr1, Bread|Bimm|Bmod)) == nil)
		return ferr(f, Ephase, file, p);
	d1 := Dentry.get(p1, slot1);
	if(d1 == nil || p1.checktag(Tdir, int d.qid.path)){
		p.put();
		return ferr(f, Ephase, file, p1);
	}
	if(d1.mode & DALLOC){
		p.put();
		return ferr(f, Ephase, file, p1);
	}

	d1.name = f.name;
	if(cp == conschan){
		d1.uid = consuid;
		d1.gid = consgid;
	}
	else{
		d1.uid = file.uid;
		d1.gid = d.gid;
		f.perm &= d.mode | ~8r666;
		if(f.perm & DMDIR)
			f.perm &= d.mode | ~8r777;
	}
	d1.qid.path = big path;
	d1.qid.vers = 0;
	d1.mode = DALLOC | (f.perm & 8r777);
	if(f.perm & DMDIR)
		d1.mode |= DDIR;
	if(f.perm & DMAPPEND)
		d1.mode |= DAPND;
	t: ref Tlock;
	if(f.perm & DMEXCL){
		d1.mode |= DLOCK;
		t = tlocked(file, d1);
		# if nil, out of tlock structures
	}
	d1.access(FWRITE, file.uid);
	d1.change(~0);
	d1.update();
	qid := mkqid(path, 0, d1.mode);
	p1.put();
	d.change(~0);
	d.access(FWRITE, file.uid);
	d.update();
	p.put();

	#
	# do a walk to new directory entry
	#
	file.wpath = ref Wpath(file.wpath, file.addr, file.slot);
	file.qid = qid;
	file.tlock = t;
	if(t != nil)
		t.file = file;
	file.lastra = 1;
	if(f.mode & ORCLOSE)
		fmod |= FREMOV;
	file.open = fmod;
	file.addr = addr1;
	file.slot = slot1;
	file.unlock();
	return ref Rmsg.Create(f.tag, qid, cp.msize-IOHDRSZ);
}

dirread(cp: ref Chan, f: ref Tmsg.Read, file: ref File, d: ref Dentry): ref Rmsg
{
	p1: ref Iobuf;
	d1: ref Dentry;

	count := f.count;
	data := array[count] of byte;
	offset := f.offset;
	iounit := cp.msize-IOHDRSZ;

	# Pick up where we left off last time if nothing has changed,
	# otherwise must scan from the beginning.

	addr, slot: int;
	start: big;

	if(offset == file.doffset){	# && file.qid.vers == file.dvers
		addr = file.dslot/DIRPERBUF;
		slot = file.dslot%DIRPERBUF;
		start = offset;
	}
	else{
		addr = 0;
		slot = 0;
		start = big 0;
	}

	nread := 0;
Dread:
	for(;;){
		if(d.iob == nil){
			#
			# This is just a check to ensure the entry hasn't
			# gone away during the read of each directory block.
			#
			e: string;
			(d, e) = Dentry.getd(file, Bread);
			if(d == nil)
				return ferr(f, e, file, nil);
		}
		p1 = d.getblk1(addr, 0);
		if(p1 == nil)
			break;
		if(p1.checktag(Tdir, QPNONE))
			return ferr(f, Ephase, file, p1);

		for(; slot < DIRPERBUF; slot++){
			d1 = Dentry.get(p1, slot);
			if(!(d1.mode & DALLOC))
				continue;
			dir := dir9p2(d1);
			n := styx->packdirsize(dir);
			if(n > count-nread){
				p1.put();
				break Dread;
			}
			data[nread:] = styx->packdir(dir);
			start += big n;
			if(start < offset)
				continue;
			if(count < n){
				p1.put();
				break Dread;
			}
			count -= n;
			nread += n;
			offset += big n;
		}
		p1.put();
		slot = 0;
		addr++;
	}

	file.doffset = offset;
	file.dvers = file.qid.vers;
	file.dslot = slot+DIRPERBUF*addr;

	d.put();
	file.unlock();
	return ref Rmsg.Read(f.tag, data[0:nread]);
}

rread(cp: ref Chan, f: ref Tmsg.Read): ref Rmsg
{
	if((file := cp.getfid(f.fid, 0)) == nil)
		return err(f, Efid);
	if(!(file.open & FREAD))
		return ferr(f, Eopen, file, nil);
	count := f.count;
	iounit := cp.msize-IOHDRSZ;
	if(count < 0 || count > iounit)
		return ferr(f, Ecount, file, nil);
	offset := f.offset;
	if(offset < big 0)
		return ferr(f, Eoffset, file, nil);

	(d, e) := Dentry.getd(file, Bread);
	if(d == nil)
		return ferr(f, e, file, nil);
	if((t := file.tlock) != nil){
		tim := now();
		if(t.time < tim || t.file != file){
			d.put();
			return ferr(f, Ebroken, file, nil);
		}
		# renew the lock
		t.time = tim + TLOCK;
	}
	d.access(FREAD, file.uid);
	if(d.mode & DDIR)
		return dirread(cp, f, file, d);

	if(offset+big count > d.size)
		count = int (d.size - offset);
	if(count < 0)
		count = 0;
	data := array[count] of byte;
	nread := 0;
	while(count > 0){
		if(d.iob == nil){
			# must check and reacquire entry
			(d, e) = Dentry.getd(file, Bread);
			if(d == nil)
				return ferr(f, e, file, nil);
		}
		addr := int (offset / big BUFSIZE);
		if(addr == file.lastra+1)
			;	# dbufread(p, d, addr+1);
		file.lastra = addr;
		o := int (offset % big BUFSIZE);
		n := BUFSIZE - o;
		if(n > count)
			n = count;
		p1 := d.getblk1(addr, 0);
		if(p1 != nil){
			if(p1.checktag(Tfile, QPNONE)){
				p1.put();
				return ferr(f, Ephase, file, nil);
			}
			data[nread:] = p1.iobuf[o:o+n];
			p1.put();
		}else
			data[nread:] = emptyblock[0:n];
		count -= n;
		nread += n;
		offset += big n;
	}
	d.put();
	file.unlock();
	return ref Rmsg.Read(f.tag, data[0:nread]);
}

rwrite(cp: ref Chan, f: ref Tmsg.Write): ref Rmsg
{
	if((file := cp.getfid(f.fid, 0)) == nil)
		return err(f, Efid);
	if(!(file.open & FWRITE))
		return ferr(f, Eopen, file, nil);
	if(isro(file.fs) || (writegroup && !ingroup(file.uid, writegroup)))
		return ferr(f, Eronly, file, nil);
	count := len f.data;
	if(count < 0 || count > cp.msize-IOHDRSZ)
		return ferr(f, Ecount, file, nil);
	offset := f.offset;
	if(offset < big 0)
		return ferr(f, Eoffset, file, nil);

	(d, e) := Dentry.getd(file, Bread|Bmod);
	if(d == nil)
		return ferr(f, e, file, nil);
	if((t := file.tlock) != nil){
		tim := now();
		if(t.time < tim || t.file != file){
			d.put();
			return ferr(f, Ebroken, file, nil);
		}
		# renew the lock
		t.time = tim + TLOCK;
	}
	d.access(FWRITE, file.uid);
	if(d.mode & DAPND)
		offset = d.size;
	end := offset + big count;
	if(end > d.size){
		if(end > MAXFILESIZE)
			return ferr(f, Etoobig, file, nil);
		d.size = end;
		d.change(Usize);
	}
	d.update();

	nwrite := 0;
	while(count > 0){
		if(d.iob == nil){
			# must check and reacquire entry
			(d, e) = Dentry.getd(file, Bread|Bmod);
			if(d == nil)
				return ferr(f, e, file, nil);
		}
		addr := int (offset / big BUFSIZE);
		o := int (offset % big BUFSIZE);
		n := BUFSIZE - o;
		if(n > count)
			n = count;
		qpath := int d.qid.path;
		p1 := d.getblk1(addr, Tfile);
		if(p1 == nil)
			return ferr(f, Efull, file, nil);
		if(p1.checktag(Tfile, qpath)){
			p1.put();
			return ferr(f, Ealloc, file, nil);
		}
		p1.iobuf[o:] = f.data[nwrite:nwrite+n];
		p1.flags |= Bmod;
		p1.put();
		count -= n;
		nwrite += n;
		offset += big n;
	}
	d.put();
	file.unlock();
	return ref Rmsg.Write(f.tag, nwrite);
}

doremove(f: ref File, iscon: int): string
{
	if(isro(f.fs) || f.cons == 0 && (writegroup && !ingroup(f.uid, writegroup)))
		return Eronly;
	#
	# check permission on parent directory of file to be deleted
	#
	if(f.wpath == nil || f.wpath.addr == f.addr)
		return Ephase;
	(d1, e1) := Dentry.geta(f.fs, f.wpath.addr, f.wpath.slot, QPNONE, Bread);
	if(e1 != nil)
		return e1;
	if(!iscon && f.access(d1, DWRITE)){
		d1.put();
		return Eaccess;
	}
	d1.access(FWRITE, f.uid);
	d1.put();

	#
	# check on file to be deleted
	#
	(d, e) := Dentry.getd(f, Bread);
	if(e != nil)
		return e;

	#
	# if deleting a directory, make sure it is empty
	#
	if(d.mode & DDIR)
	for(addr:=0; (p1 := d.getblk(addr, 0)) != nil; addr++){
		if(p1.checktag(Tdir, int d.qid.path)){
			p1.put();
			d.put();
			return Ephase;
		}
		for(slot:=0; slot<DIRPERBUF; slot++){
			d1 = Dentry.get(p1, slot);
			if(!(d1.mode & DALLOC))
				continue;
			p1.put();
			d.put();
			return Eempty;
		}
		p1.put();
	}

	#
	# do it
	#
	d.trunc(f.uid);
	d.buf[0:] = emptyblock[0:Dentrysize];
	d.put();
	return nil;
}

clunk(cp: ref Chan, file: ref File, remove: int, wok: int): string
{
	if((t := file.tlock) != nil){
		if(t.file == file)
			t.time = 0;		# free the lock
		file.tlock = nil;
	}
	if(remove)
		error := doremove(file, wok);
	file.open = 0;
	file.wpath = nil;
	cp.putfid(file);

	return error;
}

rclunk(cp: ref Chan, t: ref Tmsg.Clunk): ref Rmsg
{
	if((file := cp.getfid(t.fid, 0)) == nil)
		return err(t, Efid);
	clunk(cp, file, file.open & FREMOV, 0);
	return ref Rmsg.Clunk(t.tag);
}

rremove(cp: ref Chan, t: ref Tmsg.Remove): ref Rmsg
{
	if((file := cp.getfid(t.fid, 0)) == nil)
		return err(t, Efid);
	e :=  clunk(cp, file, 1, cp == conschan);
	if(e != nil)
		return err(t, e);
	return ref Rmsg.Remove(t.tag);
}

rstat(cp: ref Chan, f: ref Tmsg.Stat): ref Rmsg
{
	if((file := cp.getfid(f.fid, 0)) == nil)
		return err(f, Efid);
	(d, e) := Dentry.getd(file, Bread);
	if(d == nil)
		return ferr(f, e, file, nil);
	dir := dir9p2(d);
	if(d.qid.path == big QPROOT)	# stat of root gives time
		dir.atime = now();
	d.put();
	if(styx->packdirsize(dir) > cp.msize-IOHDRSZ)
		return ferr(f, Ersc, file, nil);
	file.unlock();

	return ref Rmsg.Stat(f.tag, dir);
}

rwstat(cp: ref Chan, f: ref Tmsg.Wstat): ref Rmsg
{
	if((file := cp.getfid(f.fid, 0)) == nil)
		return err(f, Efid);

	# if user none, can't do anything unless in allow mode

	if(file.uid == None && !wstatallow)
		return ferr(f, Eaccess, file, nil);

	if(isro(file.fs) || (writegroup && !ingroup(file.uid, writegroup)))
		return ferr(f, Eronly, file, nil);

	#
	# first get parent
	#
	p1: ref Iobuf;
	d1: ref Dentry;
	if(file.wpath != nil){
		p1 = Iobuf.get(file.fs, file.wpath.addr, Bread);
		if(p1 == nil)
			return ferr(f, Ephase, file, p1);
		d1 = Dentry.get(p1, file.wpath.slot);
		if(d1 == nil || p1.checktag(Tdir, QPNONE) || !(d1.mode & DALLOC))
			return ferr(f, Ephase, file, p1);
	}

	#
	# now the file
	#
	(d, e) := Dentry.getd(file, Bread);
	if(d == nil)
		return ferr(f, e, file, p1);

	#
	# Convert the message and fix up
	# fields not to be changed.
	#
	dir := f.stat;
	if(dir.uid == nil)
		uid := d.uid;
	else
		uid = strtouid(dir.uid);
	if(dir.gid == nil)
		gid := d.gid;
	else
		gid = strtouid(dir.gid);
	if(dir.name == nil)
		dir.name = d.name;
	else{
		if((l := checkname9p2(dir.name)) == 0){
			d.put();
			return ferr(f, Ename, file, p1);
		}
		if(l+1 > NAMELEN){
			d.put();
			return ferr(f, Etoolong, file, p1);
		}
	}

	# Before doing sanity checks, find out what the
	# new 'mode' should be:
	# if 'type' and 'mode' are both defaults, take the
	# new mode from the old directory entry;
	# else if 'type' is the default, use the new mode entry;
	# else if 'mode' is the default, create the new mode from
	# 'type' or'ed with the old directory mode;
	# else neither are defaults, use the new mode but check
	# it agrees with 'type'.

	if(dir.qid.qtype == 16rFF && dir.mode == ~0){
		dir.mode = d.mode & 8r777;
		if(d.mode & DLOCK)
			dir.mode |= DMEXCL;
		if(d.mode & DAPND)
			dir.mode |= DMAPPEND;
		if(d.mode & DDIR)
			dir.mode |= DMDIR;
	}
	else if(dir.qid.qtype == 16rFF){
		# nothing to do
	}
	else if(dir.mode == ~0)
		dir.mode = (dir.qid.qtype<<24)|(d.mode & 8r777);
	else if(dir.qid.qtype != ((dir.mode>>24) & 16rFF)){
		d.put();
		return ferr(f, Eqidmode, file, p1);
	}

	# Check for unknown type/mode bits
	# and an attempt to change the directory bit.

	if(dir.mode & ~(DMDIR|DMAPPEND|DMEXCL|8r777)){
		d.put();
		return ferr(f, Enotm, file, p1);
	}
	if(d.mode & DDIR)
		mode := DMDIR;
	else
		mode = 0;
	if((dir.mode^mode) & DMDIR){
		d.put();
		return ferr(f, Enotd, file, p1);
	}

	if(dir.mtime == ~0)
		dir.mtime = d.mtime;
	if(dir.length == ~big 0)
		dir.length = big d.size;


	# Currently, can't change length.

	if(dir.length != big d.size){
		d.put();
		return ferr(f, Enotl, file, p1);
	}


	# if chown,
	# must be god
	# wstatallow set to allow chown during boot

	if(uid != d.uid && !wstatallow){
		d.put();
		return ferr(f, Enotu, file, p1);
	}

	# if chgroup,
	# must be either
	#	a) owner and in new group
	#	b) leader of both groups
	# wstatallow and writeallow are set to allow chgrp during boot

	while(gid != d.gid){
		if(wstatallow || writeallow)
			break;
		if(d.uid == file.uid && ingroup(file.uid, gid))
			break;
		if(leadgroup(file.uid, gid))
			if(leadgroup(file.uid, d.gid))
				break;
		d.put();
		return ferr(f, Enotg, file, p1);
	}

	# if rename,
	# must have write permission in parent

	while(d.name != dir.name){

		# drop entry to prevent deadlock, then
		# check that destination name is valid and unique

		d.put();
		if(checkname9p2(dir.name) == 0 || d1 == nil)
			return ferr(f, Ename, file, p1);
		if(dir.name == "." || dir.name == "..")
			return ferr(f, Edot, file, p1);


		for(addr := 0; ; addr++){
			if((p := d1.getblk(addr, 0)) == nil)
				break;
			if(p.checktag(Tdir, int d1.qid.path)){
				p.put();
				continue;
			}
			for(slot := 0; slot < DIRPERBUF; slot++){
				d = Dentry.get(p, slot);
				if(!(d.mode & DALLOC))
					continue;
				if(dir.name == d.name){
					p.put();
					return ferr(f, Eexist, file, p1);
				}
			}
			p.put();
		}

		# reacquire entry

		(d, nil) = Dentry.getd(file, Bread);
		if(d == nil)
			return ferr(f, Ephase, file, p1);

		if(wstatallow || writeallow) # set to allow rename during boot
			break;
		if(d1 == nil || file.access(d1, DWRITE)){
			d.put();
			return ferr(f, Eaccess, file, p1);
		}
		break;
	}

	# if mode/time, either
	#	a) owner
	#	b) leader of either group

	mode = dir.mode & 8r777;
	if(dir.mode & DMAPPEND)
		mode |= DAPND;
	if(dir.mode & DMEXCL)
		mode |= DLOCK;
	while(d.mtime != dir.mtime || ((d.mode^mode) & (DAPND|DLOCK|8r777))){
		if(wstatallow)			# set to allow chmod during boot
			break;
		if(d.uid == file.uid)
			break;
		if(leadgroup(file.uid, gid))
			break;
		if(leadgroup(file.uid, d.gid))
			break;
		d.put();
		return ferr(f, Enotu, file, p1);
	}
	d.mtime = dir.mtime;
	d.uid = uid;
	d.gid = gid;
	d.mode = (mode & (DAPND|DLOCK|8r777)) | (d.mode & (DALLOC|DDIR));

	d.name = dir.name;
	d.access(FWSTAT, file.uid);
	d.change(~0);
	d.put();

	if(p1 != nil)
		p1.put();
	file.unlock();

	return ref Rmsg.Wstat(f.tag);
}

superok(set: int): int
{
	sb := Superb.get(thedevice, Bread|Bmod|Bimm);
	ok := sb.fsok;
	sb.fsok = set;
	if(debug)
		sb.print();
	sb.touched();
	sb.put();
	return ok;
}

# little-endian
get2(a: array of byte, o: int): int
{
	return (int a[o+1]<<8) | int a[o];
}

get2s(a: array of byte, o: int): int
{
	v := (int a[o+1]<<8) | int a[o];
	if(v & 16r8000)
		v |= ~0 << 8;
	return v;
}

get4(a: array of byte, o: int): int
{
	return (int a[o+3]<<24) | (int a[o+2] << 16) | (int a[o+1]<<8) | int a[o];
}

put2(a: array of byte, o: int, v: int)
{
	a[o] = byte v;
	a[o+1] = byte (v>>8);
}

put4(a: array of byte, o: int, v: int)
{
	a[o] = byte v;
	a[o+1] = byte (v>>8);
	a[o+2] = byte (v>>16);
	a[o+3] = byte (v>>24);
}

Tag.unpack(a: array of byte): Tag
{
	return Tag(get2(a,2), get4(a,4));
}

Tag.pack(t: self Tag, a: array of byte)
{
	put2(a, 0, 0);
	put2(a, 2, t.tag);
	if(t.path != QPNONE)
		put4(a, 4, t.path & ~QPDIR);
}

Superb.get(dev: ref Device, flags: int): ref Superb
{
	p := Iobuf.get(dev, SUPERADDR, flags);
	if(p == nil)
		return nil;
	if(p.checktag(Tsuper, QPSUPER)){
		p.put();
		return nil;
	}
	sb := Superb.unpack(p.iobuf);
	sb.iob = p;
	return sb;
}

Superb.touched(s: self ref Superb)
{
	s.iob.flags |= Bmod;
}

Superb.put(sb: self ref Superb)
{
	if(sb.iob == nil)
		return;
	if(sb.iob.flags & Bmod)
		sb.pack(sb.iob.iobuf);
	sb.iob.put();
	sb.iob = nil;
}

#  this is the disk structure
# Superb:
#	Super1;
#	Fbuf	fbuf;
# Fbuf:
#	nfree[4]
#	free[]	# based on BUFSIZE
#  Super1:
#	long	fstart;
#	long	fsize;
#	long	tfree;
#	long	qidgen;		# generator for unique ids
#	long	fsok;		# file system ok
#	long	roraddr;	# dump root addr
#	long	last;		# last super block addr
#	long	next;		# next super block addr

Ofstart: con 0;
Ofsize: con Ofstart+4;
Otfree: con Ofsize+4;
Oqidgen: con Otfree+4;
Ofsok: con Oqidgen+4;
Ororaddr: con Ofsok+4;
Olast: con Ororaddr+4;
Onext: con Olast+4;
Super1size: con Onext+4;

Superb.unpack(a: array of byte): ref Superb
{
	s := ref Superb;
	s.fstart = get4(a, Ofstart);
	s.fsize = get4(a, Ofsize);
	s.tfree = get4(a, Otfree);
	s.qidgen = get4(a, Oqidgen);
	s.fsok = get4(a, Ofsok);
	s.fbuf = a[Super1size:];
	return s;
}

Superb.pack(s: self ref Superb, a: array of byte)
{
	put4(a, Ofstart, s.fstart);
	put4(a, Ofsize, s.fsize);
	put4(a, Otfree, s.tfree);
	put4(a, Oqidgen, s.qidgen);
	put4(a, Ofsok, s.fsok);
}

Superb.print(sb: self ref Superb)
{
	sys->print("fstart=%ud fsize=%ud tfree=%ud qidgen=%ud fsok=%d\n",
		sb.fstart, sb.fsize, sb.tfree, sb.qidgen, sb.fsok);
}

Dentry.get(p: ref Iobuf, slot: int): ref Dentry
{
	if(p == nil)
		return nil;
	buf := p.iobuf[(slot%DIRPERBUF)*Dentrysize:];
	d := Dentry.unpack(buf);
	d.iob = p;
	d.buf = buf;
	return d;
}

Dentry.geta(fs: ref Device, addr: int, slot: int, qpath: int, mode: int): (ref Dentry, string)
{
	p := Iobuf.get(fs, addr, mode);
	if(p == nil || p.checktag(Tdir, qpath)){
		if(p != nil)
			p.put();
		return (nil, Ealloc);
	}
	d := Dentry.get(p, slot);
	if(d == nil || !(d.mode & DALLOC)){
		p.put();
		return (nil, Ealloc);
	}
	return (d, nil);
}

Dentry.getd(file: ref File, mode: int): (ref Dentry, string)
{
	(d, e) := Dentry.geta(file.fs, file.addr, file.slot, QPNONE, mode);	# QPNONE should be file.wpath's path
	if(e != nil)
		return (nil, e);
	if(file.qid.path != d.qid.path || (file.qid.qtype&QTDIR) != (d.qid.qtype&QTDIR)){
		d.put();
		return (nil, Eqid);
	}
	return (d, nil);
}

#  this is the disk structure:
#	char	name[NAMELEN];
#	short	uid;
#	short	gid;		[2*2]
#	ushort	mode;
#		#define	DALLOC	0x8000
#		#define	DDIR	0x4000
#		#define	DAPND	0x2000
#		#define	DLOCK	0x1000
#		#define	DREAD	0x4
#		#define	DWRITE	0x2
#		#define	DEXEC	0x1
#	[ushort muid]		[2*2]
#	Qid.path;			[4]
#	Qid.version;		[4]
#	long	size;			[4]
#	long	dblock[NDBLOCK];
#	long	iblock;
#	long	diblock;
#	long	atime;
#	long	mtime;

Oname: con 0;
Ouid: con Oname+NAMELEN;
Ogid: con Ouid+2;
Omode: con Ogid+2;
Omuid: con Omode+2;
Opath: con Omuid+2;
Overs: con Opath+4;
Osize: con Overs+4;
Odblock: con Osize+4;
Oiblock: con Odblock+NDBLOCK*4;
Odiblock: con Oiblock+4;
Oatime: con Odiblock+4;
Omtime: con Oatime+4;
Dentrysize: con Omtime+4;

Dentry.unpack(a: array of byte): ref Dentry
{
	d := ref Dentry;
	for(i:=0; i<NAMELEN; i++)
		if(int a[i] == 0)
			break;
	d.name = string a[0:i];
	d.uid = get2s(a, Ouid);
	d.gid = get2s(a, Ogid);
	d.mode = get2(a, Omode);
	d.muid = get2(a, Omuid);	# note: not set by Plan 9's kfs
	d.qid = mkqid(get4(a, Opath), get4(a, Overs), d.mode);
	d.size = big get4(a, Osize) & big 16rFFFFFFFF;
	d.atime = get4(a, Oatime);
	d.mtime = get4(a, Omtime);
	d.mod = 0;
	return d;
}

Dentry.change(d: self ref Dentry, f: int)
{
	d.mod |= f;
}

Dentry.update(d: self ref Dentry)
{
	f := d.mod;
	d.mod = 0;
	if(d.iob == nil || (d.iob.flags & Bmod) == 0){
		if(f != 0)
			panic("Dentry.update");
		return;
	}
	a := d.buf;
	if(f & Uname){
		b := array of byte d.name;
		for(i := 0; i < NAMELEN; i++)
			if(i < len b)
				a[i] = b[i];
			else
				a[i] = byte 0;
	}
	if(f & Uids){
		put2(a, Ouid, d.uid);
		put2(a, Ogid, d.gid);
	}
	if(f & Umode)
		put2(a, Omode, d.mode);
	if(f & Uqid){
		path := int d.qid.path;
		if(d.mode & DDIR)
			path |= QPDIR;
		put4(a, Opath, path);
		put4(a, Overs, d.qid.vers);
	}
	if(f & Usize)
		put4(a, Osize, int d.size);
	if(f & Utime){
		put4(a, Omtime, d.mtime);
		put4(a, Oatime, d.atime);
	}
	d.iob.flags |= Bmod;
}

Dentry.access(d: self ref Dentry, f: int, uid: int)
{
	if((p := d.iob) != nil && !readonly){
		if((f & (FWRITE|FWSTAT)) == 0 && noatime)
			return;
		if(f & (FREAD|FWRITE|FWSTAT)){
			d.atime = now();
			put4(d.buf, Oatime, d.atime);
			p.flags |= Bmod;
		}
		if(f & FWRITE){
			d.mtime = now();
			put4(d.buf, Omtime, d.mtime);
			d.muid = uid;
			put2(d.buf, Omuid, uid);
			d.qid.vers++;
			put4(d.buf, Overs, d.qid.vers);
			p.flags |= Bmod;
		}
	}
}

#
# release the directory entry buffer and thus the
# lock on both buffer and entry, typically during i/o,
# to be reacquired later if needed
#
Dentry.release(d: self ref Dentry)
{
	if(d.iob != nil){
		d.update();
		d.iob.put();
		d.iob = nil;
		d.buf = nil;
	}
}

Dentry.getblk(d: self ref Dentry, a: int, tag: int): ref Iobuf
{
	addr := d.rel2abs(a, tag, 0);
	if(addr == 0)
		return nil;
	return Iobuf.get(thedevice, addr, Bread);
}

#
# same as Dentry.buf but calls d.release
# to reduce interference.
#
Dentry.getblk1(d: self ref Dentry, a: int, tag: int): ref Iobuf
{
	addr := d.rel2abs(a, tag, 1);
	if(addr == 0)
		return nil;
	return Iobuf.get(thedevice, addr, Bread);
}

Dentry.rel2abs(d: self ref Dentry, a: int, tag: int, putb: int): int
{
	if(a < 0){
		sys->print("Dentry.rel2abs: neg\n");
		return 0;
	}
	p := d.iob;
	if(p == nil || d.buf == nil)
		panic("nil iob");
	data := d.buf;
	qpath := int d.qid.path;
	dev := p.dev;
	if(a < NDBLOCK){
		addr := get4(data, Odblock+a*4);
		if(addr == 0 && tag){
			addr = balloc(dev, tag, qpath);
			put4(data, Odblock+a*4, addr);
			p.flags |= Bmod|Bimm;
		}
		if(putb)
			d.release();
		return addr;
	}
	a -= NDBLOCK;
	if(a < INDPERBUF){
		addr := get4(data, Oiblock);
		if(addr == 0 && tag){
			addr = balloc(dev, Tind1, qpath);
			put4(data, Oiblock, addr);
			p.flags |= Bmod|Bimm;
		}
		if(putb)
			d.release();
		return  indfetch(dev, qpath, addr, a, Tind1, tag);
	}
	a -= INDPERBUF;
	if(a < INDPERBUF2){
		addr := get4(data, Odiblock);
		if(addr == 0 && tag){
			addr = balloc(dev, Tind2, qpath);
			put4(data, Odiblock, addr);
			p.flags |= Bmod|Bimm;
		}
		if(putb)
			d.release();
		addr = indfetch(dev, qpath, addr, a/INDPERBUF, Tind2, Tind1);
		return indfetch(dev, qpath, addr, a%INDPERBUF, Tind1, tag);
	}
	if(putb)
		d.release();
	sys->print("Dentry.buf: trip indirect\n");
	return 0;
}

indfetch(dev: ref Device, path: int, addr: int, a: int, itag: int, tag: int): int
{
	if(addr == 0)
		return 0;
	bp := Iobuf.get(dev, addr, Bread);
	if(bp == nil){
		sys->print("ind fetch bp = nil\n");
		return 0;
	}
	if(bp.checktag(itag, path)){
		sys->print("ind fetch tag\n");
		bp.put();
		return 0;
	}
	addr = get4(bp.iobuf, a*4);
	if(addr == 0 && tag){
		addr = balloc(dev, tag, path);
		if(addr != 0){
			put4(bp.iobuf, a*4, addr);
			bp.flags |= Bmod;
			if(localfs || tag == Tdir)
				bp.flags |= Bimm;
			bp.settag(itag, path);
		}
	}
	bp.put();
	return addr;
}

balloc(dev: ref Device, tag: int, qpath: int): int
{
	# TO DO: cache superblock to reduce pack/unpack
	sb := Superb.get(dev, Bread|Bmod);
	if(sb == nil)
		panic("balloc: super block");
	n := get4(sb.fbuf, 0);
	n--;
	sb.tfree--;
	if(n < 0 || n >= FEPERBUF)
		panic("balloc: bad freelist");
	a := get4(sb.fbuf, 4+n*4);
	if(n == 0){
		if(a == 0){
			sb.tfree = 0;
			sb.touched();
			sb.put();
			return 0;
		}
		bp := Iobuf.get(dev, a, Bread);
		if(bp == nil || bp.checktag(Tfree, QPNONE)){
			if(bp != nil)
				bp.put();
			sb.put();
			return 0;
		}
		sb.fbuf[0:] = bp.iobuf[0:(FEPERBUF+1)*4];
		sb.touched();
		bp.put();
	}else{
		put4(sb.fbuf, 0, n);
		sb.touched();
	}
	bp := Iobuf.get(dev, a, Bmod);
	bp.iobuf[0:] = emptyblock;
	bp.settag(tag, qpath);
	if(tag == Tind1 || tag == Tind2 || tag == Tdir)
		bp.flags |= Bimm;
	bp.put();
	sb.put();
	return a;
}

bfree(dev: ref Device, addr: int, d: int)
{
	if(addr == 0)
		return;
	if(d > 0){
		d--;
		p := Iobuf.get(dev, addr, Bread);
		if(p != nil){
			for(i:=INDPERBUF-1; i>=0; i--){
				a := get4(p.iobuf, i*4);
				bfree(dev, a, d);
			}
			p.put();
		}
	}

	# stop outstanding i/o
	p := Iobuf.get(dev, addr, Bprobe);
	if(p != nil){
		p.flags &= ~(Bmod|Bimm);
		p.put();
	}

	s := Superb.get(dev, Bread|Bmod);
	if(s == nil)
		panic("bfree: super block");
	addfree(dev, addr, s);
	s.put();
}

addfree(dev: ref Device, addr: int, sb: ref Superb)
{
	if(addr >= sb.fsize){
		sys->print("addfree: bad addr %ud\n", addr);
		return;
	}
	n := get4(sb.fbuf, 0);
	if(n < 0 || n > FEPERBUF)
		panic("addfree: bad freelist");
	if(n >= FEPERBUF){
		p := Iobuf.get(dev, addr, Bmod);
		if(p == nil)
			panic("addfree: Iobuf.get");
		p.iobuf[0:] = sb.fbuf[0:(1+FEPERBUF)*4];
		sb.fbuf[0:] = emptyblock[0:(1+FEPERBUF)*4];	# clear it for debugging
		p.settag(Tfree, QPNONE);
		p.put();
		n = 0;
	}
	put4(sb.fbuf, 4+n*4, addr);
	put4(sb.fbuf, 0, n+1);
	sb.tfree++;
	if(addr >= sb.fsize)
		sb.fsize = addr+1;
	sb.touched();
}

qidpathgen(dev: ref Device): int
{
	sb := Superb.get(dev, Bread|Bmod);
	if(sb == nil)
		panic("qidpathgen: super block");
	sb.qidgen++;
	path := sb.qidgen;
	sb.touched();
	sb.put();
	return path;
}

Dentry.trunc(d: self ref Dentry, uid: int)
{
	p := d.iob;
	data := d.buf;
	bfree(p.dev, get4(data, Odiblock), 2);
	put4(data, Odiblock, 0);
	bfree(p.dev, get4(data, Oiblock), 1);
	put4(data, Oiblock, 0);
	for(i:=NDBLOCK-1; i>=0; i--){
		bfree(p.dev, get4(data, Odblock+i*4), 0);
		put4(data, Odblock+i*4, 0);
	}
	d.size = big 0;
	d.change(Usize);
	p.flags |= Bmod|Bimm;
	d.access(FWRITE, uid);
	d.update();
}

Dentry.put(d: self ref Dentry)
{
	p := d.iob;
	if(p == nil || d.buf == nil)
		return;
	d.update();
	p.put();
	d.iob = nil;
	d.buf = nil;
}

Dentry.print(d: self ref Dentry)
{
	sys->print("name=%#q uid=%d gid=%d mode=#%8.8ux qid.path=#%bux qid.vers=%ud size=%bud\n",
		d.name, d.uid, d.gid, d.mode, d.qid.path, d.qid.vers, d.size);
	p := d.iob;
	if(p != nil && (data := p.iobuf) != nil){
		sys->print("\tdblock=");
		for(i := 0; i < NDBLOCK; i++)
			sys->print(" %d", get4(data, Odblock+i*4));
		sys->print(" iblock=%ud diblock=%ud\n", get4(data, Oiblock), get4(data, Odiblock));
	}
}

HWidth: con 5;	# buffers per line

hiob: array of ref Hiob;

iobufinit(niob: int)
{
	nhiob := niob/HWidth;
	while(!prime(nhiob))
		nhiob++;
	hiob = array[nhiob] of {* => ref Hiob(nil, Lock.new(), 0)};
	# allocate the buffers now
	for(i := 0; i < len hiob; i++){
		h := hiob[i];
		while(h.niob < HWidth)
			h.newbuf();
	}
}

iobufclear()
{
	# eliminate the cyclic references
	for(i := 0; i < len hiob; i++){
		h := hiob[i];
		while(--h.niob >= 0){
			p := hiob[i].link;
			hiob[i].link = p.fore;
			p.fore = p.back = nil;
			p = nil;
		}
	}
}

prime(n: int): int
{
	if((n%2) == 0)
		return 0;
	for(i:=3;; i+=2) {
		if((n%i) == 0)
			return 0;
		if(i*i >= n)
			return 1;
	}
}

Hiob.newbuf(hb: self ref Hiob): ref Iobuf
{
	# hb must be locked
	p := ref Iobuf;
	p.qlock = chan[1] of int;
	q := hb.link;
	if(q != nil){
		p.fore = q;
		p.back = q.back;
		q.back = p;
		p.back.fore = p;
	}else{
		hb.link = p;
		p.fore = p;
		p.back = p;
	}
	p.dev = devnone;
	p.addr = -1;
	p.flags = 0;
	p.xiobuf = array[RBUFSIZE] of byte;
	hb.niob++;
	return p;
}

Iobuf.get(dev: ref Device, addr: int, flags: int): ref Iobuf
{
	hb := hiob[addr%len hiob];
	p: ref Iobuf;
Search:
	for(;;){
		hb.lk.lock();
		s := hb.link;

		# see if it's active
		p = s;
		do{
			if(p.addr == addr && p.dev == dev){
				if(p != s){
					p.back.fore = p.fore;
					p.fore.back = p.back;
					p.fore = s;
					p.back = s.back;
					s.back = p;
					p.back.fore = p;
					hb.link = p;
				}
				hb.lk.unlock();
				p.lock();
				if(p.addr != addr || p.dev != dev){
					# lost race
					p.unlock();
					continue Search;
				}
				p.flags |= flags;
				p.iobuf = p.xiobuf;
				return p;
			}
		}while((p = p.fore) != s);
		if(flags == Bprobe){
			hb.lk.unlock();
			return nil;
		}

		# steal the oldest unlocked buffer
		do{
			p = s.back;
			if(p.canlock()){
				# TO DO: if Bmod, write it out and restart Hashed
				# for now we needn't because Iobuf.put is synchronous
				if(p.flags & Bmod)
					sys->print("Bmod unexpected (%ud)\n", p.addr);
				hb.link = p;
				p.dev = dev;
				p.addr = addr;
				p.flags = flags;
				break Search;
			}
			s = p;
		}while(p != hb.link);

		# no unlocked blocks available; add a new one
		p = hb.newbuf();
		p.lock();	# return it locked
		break;
	}

	p.dev = dev;
	p.addr = addr;
	p.flags = flags;
	hb.lk.unlock();
	p.iobuf = p.xiobuf;
	if(flags & Bread){
		if(wrenread(dev.fd, addr, p.iobuf)){
			eprint(sys->sprint("error reading block %ud: %r", addr));
			p.flags = 0;
			p.dev = devnone;
			p.addr = -1;
			p.iobuf = nil;
			p.unlock();
			return nil;
		}
	}
	return p;
}

Iobuf.put(p: self ref Iobuf)
{
	if(p.flags & Bmod)
		p.flags |= Bimm;	# temporary; see comment in Iobuf.get
	if(p.flags & Bimm){
		if(!(p.flags & Bmod))
			eprint(sys->sprint("imm and no mod (%d)", p.addr));
		if(!wrenwrite(p.dev.fd, p.addr, p.iobuf))
			p.flags &= ~(Bmod|Bimm);
		else
			panic(sys->sprint("error writing block %ud: %r", p.addr));
	}
	p.iobuf = nil;
	p.unlock();
}

Iobuf.lock(p: self ref Iobuf)
{
	p.qlock <-= 1;
}

Iobuf.canlock(p: self ref Iobuf): int
{
	alt{
	p.qlock <-= 1 =>
		return 1;
	* =>
		return 0;
	}
}

Iobuf.unlock(p: self ref Iobuf)
{
	<-p.qlock;
}

File.access(f: self ref File, d: ref Dentry, m: int): int
{
	if(wstatallow)
		return 0;

	# none gets only other permissions

	if(f.uid != None){
		if(f.uid == d.uid)	# owner
			if((m<<6) & d.mode)
				return 0;
		if(ingroup(f.uid, d.gid))	# group membership
			if((m<<3) & d.mode)
				return 0;
	}

	#
	# other access for everyone except members of group "noworld"
	#
	if(m & d.mode){
		#
		# walk directories regardless.
		# otherwise it's impossible to get
		# from the root to noworld's directories.
		#
		if((d.mode & DDIR) && (m == DEXEC))
			return 0;
		if(!ingroup(f.uid, Noworld))
			return 0;
	}
	return 1;
}

tagname(t: int): string
{
	case t {
	Tnone =>	return "Tnone";
	Tsuper =>	return "Tsuper";
	Tdir => return "Tdir";
	Tind1 => return "Tind1";
	Tind2 => return "Tind2";
	Tfile => return "Tfile";
	Tfree => return "Tfree";
	Tbuck => return "Tbuck";
	Tvirgo => return "Tvirgo";
	Tcache => return "Tcache";
	* =>	return sys->sprint("%d", t);
	}
}

Iobuf.checktag(p: self ref Iobuf, tag: int, qpath: int): int
{
	t := Tag.unpack(p.iobuf[BUFSIZE:]);
	if(t.tag != tag){
		if(1)
			eprint(sys->sprint("	tag = %s; expected %s; addr = %ud\n",
				tagname(t.tag), tagname(tag), p.addr));
		return 2;
	}
	if(qpath != QPNONE){
		qpath &= ~QPDIR;
		if(qpath != t.path){
			if(qpath == (t.path&~QPDIR))	# old bug
				return 0;
			if(1)
				eprint(sys->sprint("	tag/path = %ux; expected %s/%ux\n",
					t.path, tagname(tag), qpath));
			return 1;
		}
	}
	return 0;
}

Iobuf.settag(p: self ref Iobuf, tag: int, qpath: int)
{
	Tag(tag, qpath).pack(p.iobuf[BUFSIZE:]);
	p.flags |= Bmod;
}

badmagic := 0;
wmagic := "kfs wren device\n";

wrenream(dev: ref Device)
{
	if(RBUFSIZE % 512)
		panic(sys->sprint("kfs: bad buffersize(%d): restart a multiple of 512", RBUFSIZE));
	if(RBUFSIZE > MAXBUFSIZE)
		panic(sys->sprint("kfs: bad buffersize(%d): must be at most %d", RBUFSIZE, MAXBUFSIZE));
	sys->print("kfs: reaming the file system using %d byte blocks\n", RBUFSIZE);
	buf := array[RBUFSIZE] of {* => byte 0};
	buf[256:] = sys->aprint("%s%d\n", wmagic, RBUFSIZE);
	if(sys->seek(dev.fd, big 0, 0) < big 0 || sys->write(dev.fd, buf, len buf) != len buf)
		panic("can't ream disk");
}

wreninit(dev: ref Device): int
{
	(ok, nil) := sys->fstat(dev.fd);
	if(ok < 0)
		return 0;
	buf := array[MAXBUFSIZE] of byte;
	sys->seek(dev.fd, big 0, 0);
	n := sys->read(dev.fd, buf, len buf);
	if(n < len buf)
		return 0;
	badmagic = 0;
	RBUFSIZE = 1024;
	if(string buf[256:256+len wmagic] != wmagic){
		badmagic = 1;
		return 0;
	}
	RBUFSIZE = int string buf[256+len wmagic:256+len wmagic+12];
	if(RBUFSIZE % 512)
		error("bad block size");
	return 1;
}

wrenread(fd: ref Sys->FD, addr: int, a: array of byte): int
{
	return sys->pread(fd, a, len a, big addr * big RBUFSIZE) != len a;
}

wrenwrite(fd: ref Sys->FD, addr: int, a: array of byte): int
{
	return sys->pwrite(fd, a, len a, big addr * big RBUFSIZE) != len a;
}

wrentag(buf: array of byte, tag: int, qpath: int): int
{
	t := Tag.unpack(buf[BUFSIZE:]);
	return t.tag != tag || (qpath&~QPDIR) != t.path;
}

wrencheck(fd: ref Sys->FD): int
{
	if(badmagic)
		return 1;
	buf := array[RBUFSIZE] of byte;
	if(wrenread(fd, SUPERADDR, buf) || wrentag(buf, Tsuper, QPSUPER) ||
	    wrenread(fd, ROOTADDR, buf) || wrentag(buf, Tdir, QPROOT))
		return 1;
	d0 := Dentry.unpack(buf);
	if(d0.mode & DALLOC)
		return 0;
	return 1;
}

wrensize(dev: ref Device): int
{
	(ok, d) := sys->fstat(dev.fd);
	if(ok < 0)
		return -1;
	return int (d.length / big RBUFSIZE);
}

checkname9p2(s: string): int
{
	for(i := 0; i < len s; i++)
		if(s[i] <= 8r40)
			return 0;
	return styx->utflen(s);
}

isro(d: ref Device): int
{
	return d == nil || d.ronly;
}

tlocks: list of ref Tlock;

tlocked(f: ref File, d: ref Dentry): ref Tlock
{
	tim := now();
	path := int d.qid.path;
	t1: ref Tlock;
	for(l := tlocks; l != nil; l = tl l){
		t := hd l;
		if(t.qpath == path && t.time >= tim && t.dev == f.fs)
			return nil;	# it's locked
		if(t.file == nil || t1 == nil && t.time < tim)
			t1 = t;
	}
	t := t1;
	if(t == nil)
		t = ref Tlock;
	t.dev = f.fs;
	t.qpath = path;
	t.time = tim + TLOCK;
	tlocks = t :: tlocks;
	return t;
}

mkqid(path: int, vers: int, mode: int): Qid
{
	qid: Qid;

	qid.path = big (path & ~QPDIR);
	qid.vers = vers;
	qid.qtype = 0;
	if(mode & DDIR)
		qid.qtype |= QTDIR;
	if(mode & DAPND)
		qid.qtype |= QTAPPEND;
	if(mode & DLOCK)
		qid.qtype |= QTEXCL;
	return qid;
}

dir9p2(d: ref Dentry): Sys->Dir
{
	dir: Sys->Dir;

	dir.name = d.name;
	dir.uid = uidtostr(d.uid);
	dir.gid = uidtostr(d.gid);
	dir.muid = uidtostr(d.muid);
	dir.qid = d.qid;
	dir.mode = d.mode & 8r777;
	if(d.mode & DDIR)
		dir.mode |= DMDIR;
	if(d.mode & DAPND)
		dir.mode |= DMAPPEND;
	if(d.mode & DLOCK)
		dir.mode |= DMEXCL;
	dir.atime = d.atime;
	dir.mtime = d.mtime;
	dir.length = big d.size;
	dir.dtype = 0;
	dir.dev = 0;
	return dir;
}

rootream(dev: ref Device, addr: int)
{
	p := Iobuf.get(dev, addr, Bmod|Bimm);
	p.iobuf[0:] = emptyblock;
	p.settag(Tdir, QPROOT);
	d := Dentry.get(p, 0);
	d.name = "/";
	d.uid = -1;
	d.gid = -1;
	d.mode = DALLOC | DDIR |
		((DREAD|DWRITE|DEXEC) << 6) |
		((DREAD|DWRITE|DEXEC) << 3) |
		((DREAD|DWRITE|DEXEC) << 0);
	d.qid.path = big QPROOT;
	d.qid.vers = 0;
	d.qid.qtype = QTDIR;
	d.atime = now();
	d.mtime = d.atime;
	d.change(~0);
	d.access(FREAD|FWRITE, -1);
	d.update();
	p.put();
}

superream(dev: ref Device, addr: int)
{
	fsize := wrensize(dev);
	if(fsize <= 0)
		panic("file system device size");
	p := Iobuf.get(dev, addr, Bmod|Bimm);
	p.iobuf[0:] = emptyblock;
	p.settag(Tsuper, QPSUPER);
	sb := ref Superb;
	sb.iob = p;
	sb.fstart = 1;
	sb.fsize = fsize;
	sb.qidgen = 10;
	sb.tfree = 0;
	sb.fsok = 0;
	sb.fbuf = p.iobuf[Super1size:];
	put4(sb.fbuf, 0, 1);	# nfree = 1
	for(i := fsize-1; i>=addr+2; i--)
		addfree(dev, i, sb);
	sb.put();
}

eprint(s: string)
{
	sys->print("kfs: %s\n", s);
}

#
# /adm/users
#
# uid:user:leader:members[,...]

User: adt {
	uid:	int;
	name:	string;
	leader:	int;
	mem:	list of int;
};

users: list of ref User;

admusers := array[] of {
	(-1, "adm", "adm"),
	(None, "none", "adm"),
	(Noworld, "noworld", nil),
	(10000, "sys", nil),
	(10001, "upas", "upas"),
	(10002, "bootes", "bootes"),
	(10006, "inferno", nil),
};

userinit()
{
	if(!cmd_users() && users == nil){
		cprint("initializing minimal user table");
		defaultusers();
	}
	writegroup = strtouid("write");
}

cmd_users(): int
{
	if(kopen(FID1, FID2, array[] of {"adm", "users"}, OREAD) != nil)
		return 0;
	buf: array of byte;
	for(off := 0;;){
		(a, e) := kread(FID2, off, Styx->MAXFDATA);
		if(e != nil){
			cprint("/adm/users read error: "+e);
			return 0;
		}
		if(len a == 0)
			break;
		off += len a;
		if(buf != nil){
			c := array[len buf + len a] of byte;
			if(buf != nil)
				c[0:] = buf;
			c[len buf:] = a;
			buf = c;
		}else
			buf = a;
	}
	kclose(FID2);

	# (uid:name:lead:mem,...\n)+
	(nl, lines) := sys->tokenize(string buf, "\n");
	if(nl == 0){
		cprint("empty /adm/users");
		return 0;
	}
	oldusers := users;
	users = nil;

	# first pass: enter id:name
	for(l := lines; l != nil; l = tl l){
		uid, name, r: string;
		s := hd l;
		if(s == "" || s[0] == '#')
			continue;
		(uid, r) = field(s, ':');
		(name, r) = field(r, ':');
		if(uid == nil || name == nil || string int uid != uid){
			cprint("invalid /adm/users line: "+hd l);
			users = oldusers;
			return 0;
		}
		adduser(int uid, name, nil, nil);
	}

	# second pass: groups and leaders
	for(l = lines; l != nil; l = tl l){
		s := hd l;
		if(s == "" || s[0] == '#')
			continue;
		name, lead, mem, r: string;
		(nil, r) = field(s, ':');	# skip id
		(name, r) = field(r, ':');
		(lead, mem) = field(r, ':');
		(nil, mems) := sys->tokenize(mem, ",\n");
		if(name == nil || lead == nil && mems == nil)
			continue;
		u := finduname(name);
		if(lead != nil){
			lu := strtouid(lead);
			if(lu != None)
				u.leader = lu;
			else if(lead != nil)
				u.leader = u.uid;	# mimic kfs not fs
		}
		mids: list of int = nil;
		for(; mems != nil; mems = tl mems){
			lu := strtouid(hd mems);
			if(lu != None)
				mids = lu :: mids;
		}
		u.mem = mids;
	}

	if(debug)
	for(x := users; x != nil; x = tl x){
		u := hd x;
		sys->print("%d : %q : %d :", u.uid, u.name, u.leader);
		for(y := u.mem; y != nil; y = tl y)
			sys->print(" %d", hd y);
		sys->print("\n");
	}
	return 1;
}

field(s: string, c: int): (string, string)
{
	for(i := 0; i < len s; i++)
		if(s[i] == c)
			return (s[0:i], s[i+1:]);
	return (s, nil);
}

defaultusers()
{
	for(i := 0; i < len admusers; i++){
		(id, name, leader) := admusers[i];
		adduser(id, name, leader, nil);
	}
}

finduname(s: string): ref User
{
	for(l := users; l != nil; l = tl l){
		u := hd l;
		if(u.name == s)
			return u;
	}
	return nil;
}

uidtostr(id: int): string
{
	if(id == None)
		return "none";
	for(l := users; l != nil; l = tl l){
		u := hd l;
		if(u.uid == id)
			return u.name;
	}
	return sys->sprint("#%d", id);
}

leadgroup(ui: int, gi: int): int
{
	for(l := users; l != nil; l = tl l){
		u := hd l;
		if(u.uid == gi){
			if(u.leader == ui)
				return 1;
			if(u.leader == 0)
				return ingroup(ui, gi);
			return 0;
		}
	}
	return 0;
}

strtouid(s: string): int
{
	if(s == "none")
		return None;
	u := finduname(s);
	if(u != nil)
		return u.uid;
	return 0;
}

ingroup(uid: int, gid: int): int
{
	if(uid == gid)
		return 1;
	for(l := users; l != nil; l = tl l){
		u := hd l;
		if(u.uid == gid){
			for(m := u.mem; m != nil; m = tl m)
				if(hd m == uid)
					return 1;
			return 0;
		}
	}
	return 0;
}

baduname(s: string): int
{
	n := checkname9p2(s);
	if(n == 0 || n+1 > NAMELEN || s == "." || s == ".."){
		sys->print("kfs: illegal user name %q\n", s);
		return 1;
	}
	return 0;
}

adduser(id: int, name: string, leader: string, mem: list of string)
{
	if(baduname(name))
		return;
	for(l := users; l != nil; l = tl l){
		u := hd l;
		if(u.uid == id){
			sys->print("kfs: duplicate user ID %d (name %q)\n", id, u.name);
			return;
		}else if(u.name == name){
			sys->print("kfs: duplicate user name %q (id %d)\n", name, u.uid);
			return;
		}
	}
	if(name == leader)
		lid := id;
	else if(leader == nil)
		lid = 0;
	else if(!baduname(leader))
		lid = strtouid(leader);
	else
		return;
	memid: list of int;
	for(; mem != nil; mem = tl mem){
		if(baduname(hd mem))
			return;
		x := strtouid(hd mem);
		if(x != 0)
			memid = x :: memid;
	}
	u := ref User(id, name, lid, memid);
	users = u :: users;
}

Lock.new(): ref Lock
{
	return ref Lock(chan[1] of int);
}

Lock.lock(l: self ref Lock)
{
	l.c <-= 1;
}

Lock.canlock(l: self ref Lock): int
{
	alt{
	l.c <-= 1 =>
		return 1;
	* =>
		return 0;
	}
}

Lock.unlock(l: self ref Lock)
{
	<-l.c;
}

#
# kfs check, could be a separate module if that seemed important
#

MAXDEPTH: con 100;
MAXNAME: con 4000;

Map: adt {
	lo, hi:	int;
	bits:	array of byte;
	nbad:	int;
	ndup:	int;
	nmark:	int;

	new:	fn(lo, hi: int): ref Map;
	isset:	fn(b: self ref Map, a: int): int;
	mark:	fn(b: self ref Map, a: int): string;
};

Check: adt {
	dev:	ref Device;

	amap:	ref Map;
	qmap:	ref Map;

	name:	string;
	nfiles:	int;
	maxq:	int;

	mod:	int;
	flags:	int;
	oldblock:	int;

	depth:	int;
	maxdepth:	int;

	check:	fn(c: self ref Check);
	touch:	fn(c: self ref Check, a: int): int;
	checkdir:	fn(c: self ref Check, a: int, qpath: int): int;
	checkindir:	fn(c: self ref Check, a: int, d: ref Dentry, qpath: int): int;
	maked:	fn(c: self ref Check, a: int, s: int, qpath: int): ref Dentry;
	modd:	fn(c: self ref Check, a: int, s: int, d: ref Dentry);
	fsck:		fn(c: self ref Check, d: ref Dentry): int;
	xread:	fn(c: self ref Check, a: int, qpath: int);
	xtag:		fn(c: self ref Check, a: int, tag: int, qpath: int): ref Iobuf;
	ckfreelist:	fn(c: self ref Check, sb: ref Superb);
	mkfreelist:	fn(c: self ref Check, sb: ref Superb);
	amark:	fn(c: self ref Check, a: int): int;
	fmark:	fn(c: self ref Check, a: int): int;
	missing:	fn(c: self ref Check, sb: ref Superb);
	qmark:	fn(c: self ref Check, q: int);
};

check(dev: ref Device, flag: int)
{
	#mainlock.wlock();
	#mainlock.wunlock();
	c := ref Check;
	c.dev = dev;
	c.nfiles = 0;
	c.maxq = 0;
	c.mod = 0;
	c.flags = flag;
	c.oldblock = 0;
	c.depth = 0;
	c.maxdepth = 0;
	c.check();
}

checkflags(s: string): int
{
	f := 0;
	for(i := 0; i < len s; i++)
		case s[i] {
		'r' =>	f |= Crdall;
		't' => f |= Ctag;
		'P' => f |= Cpfile;
		'p' => f |= Cpdir;
		'f' => f |= Cfree;
		'c' => f |= Cream;
		'd' => f |= Cbad;
		'w' => f |= Ctouch;
		'q' => f |= Cquiet;
		'v' => ;	# old verbose flag; ignored
		* =>	return -1;
	}
	return f;
}

Check.check(c: self ref Check)
{
	sbaddr := SUPERADDR;
	p := c.xtag(sbaddr, Tsuper, QPSUPER);
	if(p == nil){
		cprint(sys->sprint("bad superblock"));
		return;
	}
	sb := Superb.unpack(p.iobuf);
	sb.iob = p;

	fstart := sb.fstart;
	if(fstart != 1){
		cprint(sys->sprint("invalid superblock"));
		return;
	}
	fsize := sb.fsize;
	if(fsize < fstart || fsize > wrensize(c.dev)){
		cprint(sys->sprint("invalid size in superblock"));
		return;
	}
	c.amap = Map.new(fstart, fsize);

	nqid := sb.qidgen+100;		# not as much of a botch
	if(nqid > 1024*1024*8)
		nqid = 1024*1024*8;
	if(nqid < 64*1024)
		nqid = 64*1024;
	c.qmap = Map.new(0, nqid);

	c.mod = 0;
	c.depth = 0;
	c.maxdepth = 0;

	if(c.amark(sbaddr))
		{}

	if(!(c.flags & Cquiet))
		cprint(sys->sprint("checking file system: %s", "main"));
	c.nfiles = 0;
	c.maxq = 0;

	d := c.maked(ROOTADDR, 0, QPROOT);
	if(d != nil){
		if(c.amark(ROOTADDR))
			{}
		if(c.fsck(d))
			c.modd(ROOTADDR, 0, d);
		if(--c.depth != 0)
			cprint("depth not zero on return");
	}
	if(sb.qidgen < c.maxq)
		cprint(sys->sprint("qid generator low path=%d maxq=%d", sb.qidgen, c.maxq));

	nqbad := c.qmap.nbad + c.qmap.ndup;
	c.qmap = nil;	# could use to implement resequence

	ndup := c.amap.ndup;
	nused := c.amap.nmark;

	c.amap.ndup = c.amap.nmark = 0;	# reset for free list counts
	if(c.flags & Cfree){
		c.name = "free list";
		c.mkfreelist(sb);
		sb.qidgen = c.maxq;
		p.settag(Tsuper, QPNONE);
	}else
		c.ckfreelist(sb);

	nbad := c.amap.nbad;
	nfdup := c.amap.ndup;
	nfree := c.amap.nmark;
	# leave amap for missing, below

	if(c.mod){
		cprint("file system was modified");
		p.settag(Tsuper, QPNONE);
	}

	if(!(c.flags & Cquiet)){
		cprint(sys->sprint("%8d files", c.nfiles));
		cprint(sys->sprint("%8d blocks in the file system", fsize-fstart));
		cprint(sys->sprint("%8d used blocks", nused));
		cprint(sys->sprint("%8d free blocks", sb.tfree));
	}
	if(!(c.flags & Cfree)){
		if(nfree != sb.tfree)
			cprint(sys->sprint("%8d free blocks found", nfree));
		if(nfdup)
			cprint(sys->sprint("%8d blocks duplicated in the free list", nfdup));
		if(fsize-fstart-nused-nfree)
			cprint(sys->sprint("%8d missing blocks", fsize-fstart-nused-nfree));
	}
	if(ndup)
		cprint(sys->sprint("%8d address duplications", ndup));
	if(nbad)
		cprint(sys->sprint("%8d bad block addresses", nbad));
	if(nqbad)
		cprint(sys->sprint("%8d bad qids", nqbad));
	if(!(c.flags & Cquiet))
		cprint(sys->sprint("%8d maximum qid path", c.maxq));
	c.missing(sb);

	sb.put();
}

Check.touch(c: self ref Check, a: int): int
{
	if((c.flags&Ctouch) && a){
		p := Iobuf.get(c.dev, a, Bread|Bmod);
		if(p != nil)
			p.put();
		return 1;
	}
	return 0;
}

Check.checkdir(c: self ref Check, a: int, qpath: int): int
{
	ns := len c.name;
	dmod := c.touch(a);
	for(i:=0; i<DIRPERBUF; i++){
		nd := c.maked(a, i, qpath);
		if(nd == nil)
			break;
		if(c.fsck(nd)){
			c.modd(a, i, nd);
			dmod++;
		}
		c.depth--;
		c.name = c.name[0:ns];
	}
	c.name = c.name[0:ns];
	return dmod;
}

Check.checkindir(c: self ref Check, a: int, d: ref Dentry, qpath: int): int
{
	dmod := c.touch(a);
	p := c.xtag(a, Tind1, qpath);
	if(p == nil)
		return dmod;
	for(i:=0; i<INDPERBUF; i++){
		a = get4(p.iobuf, i*4);
		if(a == 0)
			continue;
		if(c.amark(a)){
			if(c.flags & Cbad){
				put4(p.iobuf, i*4, 0);
				p.flags |= Bmod;
			}
			continue;
		}
		if(d.mode & DDIR)
			dmod += c.checkdir(a, qpath);
		else if(c.flags & Crdall)
			c.xread(a, qpath);
	}
	p.put();
	return dmod;
}

Check.fsck(c: self ref Check, d: ref Dentry): int
{
	p: ref Iobuf;
	i: int;
	a, qpath: int;

	if(++c.depth >= c.maxdepth){
		c.maxdepth = c.depth;
		if(c.maxdepth >= MAXDEPTH){
			cprint(sys->sprint("max depth exceeded: %s", c.name));
			return 0;
		}
	}
	dmod := 0;
	if(!(d.mode & DALLOC))
		return 0;
	c.nfiles++;

	ns := len c.name;
	i = styx->utflen(d.name);
	if(i >= NAMELEN){
		d.name[NAMELEN-1] = 0;	# TO DO: not quite right
		cprint(sys->sprint("%q.name (%q) not terminated", c.name, d.name));
		return 0;
	}
	ns += i;
	if(ns >= MAXNAME){
		cprint(sys->sprint("%q.name (%q) name too large", c.name, d.name));
		return 0;
	}
	c.name += d.name;

	if(d.mode & DDIR){
		if(ns > 1)
			c.name += "/";
		if(c.flags & Cpdir)
			cprint(sys->sprint("%s", c.name));
	} else if(c.flags & Cpfile)
		cprint(sys->sprint("%s", c.name));

	qpath = int d.qid.path & ~QPDIR;
	c.qmark(qpath);
	if(qpath > c.maxq)
		c.maxq = qpath;
	for(i=0; i<NDBLOCK; i++){
		a = get4(d.buf, Odblock+i*4);
		if(a == 0)
			continue;
		if(c.amark(a)){
			put4(d.buf, Odblock+i*4, 0);
			dmod++;
			continue;
		}
		if(d.mode & DDIR)
			dmod += c.checkdir(a, qpath);
		else if(c.flags & Crdall)
			c.xread(a, qpath);
	}
	a = get4(d.buf, Oiblock);
	if(a){
		if(c.amark(a)){
			put4(d.buf, Oiblock, 0);
			dmod++;
		}
		else
			dmod += c.checkindir(a, d, qpath);
	}

	a = get4(d.buf, Odiblock);
	if(a && c.amark(a)){
		put4(d.buf, Odiblock, 0);
		return dmod + 1;
	}
	dmod += c.touch(a);
	p = c.xtag(a, Tind2, qpath);
	if(p != nil){
		for(i=0; i<INDPERBUF; i++){
			a = get4(p.iobuf, i*4);
			if(a == 0)
				continue;
			if(c.amark(a)){
				if(c.flags & Cbad){
					put4(p.iobuf, i*4, 0);
					p.flags |= Bmod;
				}
				continue;
			}
			dmod += c.checkindir(a, d, qpath);
		}
		p.put();
	}
	return dmod;
}

Check.ckfreelist(c: self ref Check, sb: ref Superb)
{
	c.name = "free list";
	cprint(sys->sprint("check %s", c.name));
	fb := sb.fbuf;
	a := SUPERADDR;
	p: ref Iobuf;
	lo := 0;
	hi := 0;
	for(;;){
		n := get4(fb, 0);		# nfree
		if(n < 0 || n > FEPERBUF){
			cprint(sys->sprint("check: nfree bad %d", a));
			break;
		}
		for(i:=1; i<n; i++){
			a = get4(fb, 4+i*4);	# free[i]
			if(a && !c.fmark(a)){
				if(!lo || lo > a)
					lo = a;
				if(!hi || hi < a)
					hi = a;
			}
		}
		a = get4(fb, 4);	# free[0]
		if(a == 0)
			break;
		if(c.fmark(a))
			break;
		if(!lo || lo > a)
			lo = a;
		if(!hi || hi < a)
			hi = a;
		if(p != nil)
			p.put();
		p = c.xtag(a, Tfree, QPNONE);
		if(p == nil)
			break;
		fb = p.iobuf;
	}
	if(p != nil)
		p.put();
	cprint(sys->sprint("lo = %d; hi = %d", lo, hi));
}

#
# make freelist from scratch
#
Check.mkfreelist(c: self ref Check, sb: ref Superb)
{
	sb.fbuf[0:] = emptyblock[0:(FEPERBUF+1)*4];
	sb.tfree = 0;
	put4(sb.fbuf, 0, 1);	# nfree = 1
	for(a:=sb.fsize-sb.fstart-1; a >= 0; a--){
		i := a>>3;
		if(i < 0 || i >= len c.amap.bits)
			continue;
		b := byte (1 << (a&7));
		if((c.amap.bits[i] & b) != byte 0)
			continue;
		addfree(c.dev, sb.fstart+a, sb);
		c.amap.bits[i] |= b;
	}
	sb.iob.flags |= Bmod;
}

#
# makes a copy of a Dentry's representation on disc so that
# the rest of the much larger iobuf can be freed.
#
Check.maked(c: self ref Check, a: int, s: int, qpath: int): ref Dentry
{
	p := c.xtag(a, Tdir, qpath);
	if(p == nil)
		return nil;
	d := Dentry.get(p, s);
	if(d == nil)
		return nil;
	copy := array[len d.buf] of byte;
	copy[0:] = d.buf;
	d.put();
	d.buf = copy;
	return d;
}

Check.modd(c: self ref Check, a: int, s: int, d1: ref Dentry)
{
	if(!(c.flags & Cbad))
		return;
	p := Iobuf.get(c.dev, a, Bread);
	d := Dentry.get(p, s);
	if(d == nil){
		if(p != nil)
			p.put();
		return;
	}
	d.buf[0:] = d1.buf;
	p.flags |= Bmod;
	p.put();
}

Check.xread(c: self ref Check, a: int, qpath: int)
{
	p := c.xtag(a, Tfile, qpath);
	if(p != nil)
		p.put();
}

Check.xtag(c: self ref Check, a: int, tag: int, qpath: int): ref Iobuf
{
	if(a == 0)
		return nil;
	p := Iobuf.get(c.dev, a, Bread);
	if(p == nil){
		cprint(sys->sprint("check: \"%s\": xtag: p null", c.name));
		if(c.flags & (Cream|Ctag)){
			p = Iobuf.get(c.dev, a, Bmod);
			if(p != nil){
				p.iobuf[0:] = emptyblock;
				p.settag(tag, qpath);
				c.mod++;
				return p;
			}
		}
		return nil;
	}
	if(p.checktag(tag, qpath)){
		cprint(sys->sprint("check: \"%s\": xtag: checktag", c.name));
		if(c.flags & Cream)
			p.iobuf[0:] = emptyblock;
		if(c.flags & (Cream|Ctag)){
			p.settag(tag, qpath);
			c.mod++;
		}
		return p;
	}
	return p;
}

Check.amark(c: self ref Check, a: int): int
{
	e := c.amap.mark(a);
	if(e != nil){
		cprint(sys->sprint("check: \"%s\": %s %d", c.name, e, a));
		return e != "dup";	# don't clear dup blocks because rm might repair
	}
	return 0;
}

Check.fmark(c: self ref Check,a: int): int
{
	e := c.amap.mark(a);
	if(e != nil){
		cprint(sys->sprint("check: \"%s\": %s %d", c.name, e, a));
		return 1;
	}
	return 0;
}

Check.missing(c: self ref Check, sb: ref Superb)
{
	n := 0;
	for(a:=sb.fsize-sb.fstart-1; a>=0; a--){
		i := a>>3;
		b := byte (1 << (a&7));
		if((c.amap.bits[i] & b) == byte 0){
			cprint(sys->sprint("missing: %d", sb.fstart+a));
			n++;
		}
		if(n > 10){
			cprint(sys->sprint(" ..."));
			break;
		}
	}
}

Check.qmark(c: self ref Check, qpath: int)
{
	e := c.qmap.mark(qpath);
	if(e != nil){
		if(c.qmap.nbad+c.qmap.ndup < 20)
			cprint(sys->sprint("check: \"%s\": qid %s 0x%ux", c.name, e, qpath));
	}
}

Map.new(lo, hi: int): ref Map
{
	m := ref Map;
	n := (hi-lo+7)>>3;
	m.bits = array[n] of {* => byte 0};
	m.lo = lo;
	m.hi = hi;
	m.nbad = 0;
	m.ndup = 0;
	m.nmark = 0;
	return m;
}

Map.isset(m: self ref Map, i: int): int
{
	if(i < m.lo || i >= m.hi)
		return -1;	# hard to say
	i -= m.lo;
	return (m.bits[i>>3] & byte (1<<(i&7))) != byte 0;
}

Map.mark(m: self ref Map, i: int): string
{
	if(i < m.lo || i >= m.hi){
		m.nbad++;
		return "out of range";
	}
	i -= m.lo;
	b := byte (1 << (i&7));
	i >>= 3;
	if((m.bits[i] & b) != byte 0){
		m.ndup++;
		return "dup";
	}
	m.bits[i] |= b;
	m.nmark++;
	return nil;
}

cprint(s: string)
{
	if(consoleout != nil)
		consoleout <-= s+"\n";
	else
		eprint(s);
}
