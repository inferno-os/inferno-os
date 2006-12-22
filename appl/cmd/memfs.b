implement MemFS;

include "sys.m";
	sys: Sys;
	OTRUNC, ORCLOSE, OREAD, OWRITE: import Sys;
include "styx.m";
	styx: Styx;
	Tmsg, Rmsg: import styx;
include "styxlib.m";
	styxlib: Styxlib;
	Styxserver: import styxlib;
include "draw.m";
include "arg.m";

MemFS: module {
	init: fn(ctxt: ref Draw->Context, args: list of string);
};


blksz : con 512;
Efull : con "filesystem full";

Memfile : adt {
	name : string;
	owner : string;
	qid : Sys->Qid;
	perm : int;
	atime : int;
	mtime : int;
	nopen : int;
	data : array of array of byte;			# allocated in blks, no holes
	length : int;
	parent : cyclic ref Memfile;	# Dir entry linkage
	kids : cyclic ref Memfile;
	prev : cyclic ref Memfile;
	next : cyclic ref Memfile;
	hashnext : cyclic ref Memfile;	# Qid hash linkage
};

Qidhash : adt {
	buckets : array of ref Memfile;
	nextqid : int;
	new : fn () : ref Qidhash;
	add : fn (h : self ref Qidhash, mf : ref Memfile);
	remove : fn (h : self ref Qidhash, mf : ref Memfile);
	lookup : fn (h : self ref Qidhash, qid : Sys->Qid) : ref Memfile;
};

timefd: ref Sys->FD;

init(nil: ref Draw->Context, argv: list of string)
{
	sys = load Sys Sys->PATH;
	styx = checkload(load Styx Styx->PATH, Styx->PATH);
	styxlib = checkload(load Styxlib Styxlib->PATH, Styxlib->PATH);
	arg := checkload(load Arg Arg->PATH, Arg->PATH);

	amode := Sys->MREPL;
	maxsz := 16r7fffffff;
	srv := 0;
	mntpt := "/tmp";

	arg->init(argv);
	arg->setusage("memfs [-s] [-rab] [-m size] [mountpoint]");
	while((opt := arg->opt()) != 0) {
		case opt{
		's' =>
			srv = 1;
		'r' =>
			amode = Sys->MREPL;
		'a' =>
			amode = Sys->MAFTER;
		'b' =>
			amode = Sys->MBEFORE;
		'm' =>
			maxsz = int arg->earg();
		* =>
			arg->usage();
		}
	}
	argv = arg->argv();
	arg = nil;
	if (argv != nil)
		mntpt = hd argv;

	srvfd: ref Sys->FD;
	mntfd: ref Sys->FD;
	if (srv)
		srvfd = sys->fildes(0);
	else {
		p := array [2] of ref Sys->FD;
		if (sys->pipe(p) == -1)
			error(sys->sprint("cannot create pipe: %r"));
		mntfd = p[0];
		srvfd = p[1];
	}
	styx->init();
	styxlib->init(styx);
	timefd = sys->open("/dev/time", sys->OREAD);

	(tc, styxsrv) := Styxserver.new(srvfd);
	if (srv)
		memfs(maxsz, tc, styxsrv, nil);
	else {
		sync := chan of int;
		spawn memfs(maxsz, tc, styxsrv, sync);
		<-sync;
		if (sys->mount(mntfd, nil, mntpt, amode | Sys->MCREATE, nil) == -1)
			error(sys->sprint("failed to mount onto %s: %r", mntpt));
	}
}

checkload[T](x: T, p: string): T
{
	if(x == nil)
		error(sys->sprint("cannot load %s: %r", p));
	return x;
}

stderr(): ref Sys->FD
{
	return sys->fildes(2);
}

error(e: string)
{
	sys->fprint(stderr(), "memfs: %s\n", e);
	raise "fail:error";
}

freeblks: int;

memfs(maxsz : int, tc : chan of ref Tmsg, srv : ref Styxserver, sync: chan of int)
{
	sys->pctl(Sys->NEWNS, nil);
	if (sync != nil)
		sync <-= 1;
	freeblks = (maxsz / blksz);
	qhash := Qidhash.new();

	# init root
	root := newmf(qhash, nil, "memfs", srv.uname, 8r755 | Sys->DMDIR);
	root.parent = root;

	while((tmsg := <-tc) != nil) {
#		sys->print("%s\n", tmsg.text());
	Msg:
		pick tm := tmsg {
		Readerror =>
			break;
		Version =>
			srv.devversion(tm);
		Auth =>
			srv.devauth(tm);
		Flush =>
			srv.reply(ref Rmsg.Flush(tm.tag));
		Walk =>
			(err, c, mf) := fidtomf(srv, qhash, tm.fid);
			if (err != "") {
				srv.reply(ref Rmsg.Error(tm.tag, err));
				continue;
			}
			nc: ref styxlib->Chan;
			if (tm.newfid != tm.fid) {
				nc = srv.clone(c, tm.newfid);
				if (nc == nil) {
					srv.reply(ref Rmsg.Error(tm.tag, "fid in use"));
					continue;
				}
				c = nc;
			}
			qids: array of Sys->Qid;
			if (len tm.names > 0) {
				oqid := c.qid;
				opath := c.path;
				qids = array[len tm.names] of Sys->Qid;
				wmf := mf;
				for (i := 0; i < len tm.names; i++) {
					wmf = dirlookup(wmf, tm.names[i]);
					if (wmf == nil) {
						if (nc == nil) {
							c.qid = oqid;
							c.path = opath;
						} else
							srv.chanfree(nc);
						if (i == 0)
							srv.reply(ref Rmsg.Error(tm.tag, Styxlib->Enotfound));
						else
							srv.reply(ref Rmsg.Walk(tm.tag, qids[0:i]));
						break Msg;
					}
					c.qid = wmf.qid;
					qids[i] = wmf.qid;
				}
			}
			srv.reply(ref Rmsg.Walk(tm.tag, qids));
		Open =>
			(err, c, mf) := fidtomf(srv, qhash, tm.fid);
			if (err == "" && c.open)
				err = Styxlib->Eopen;
			if (err == "" && !modeok(tm.mode, mf.perm, c.uname, mf.owner))
				err = Styxlib->Eperm;
			if (err == "" && (mf.perm & Sys->DMDIR) && (tm.mode & (OTRUNC|OWRITE|ORCLOSE)))
				err = Styxlib->Eperm;
			if (err == "" && (tm.mode & ORCLOSE)) {
				p := mf.parent;
				if (p == nil || !modeok(OWRITE, p.perm, c.uname, p.owner))
					err = Styxlib->Eperm;
			}

			if (err != "") {
				srv.reply(ref Rmsg.Error(tm.tag, err));
				continue;
			}

			c.open = 1;
			c.mode = tm.mode;
			c.qid.vers = mf.qid.vers;
			mf.nopen++;
			if (tm.mode & OTRUNC) {
				# OTRUNC cannot be set for a directory
				# always at least one blk so don't need to check fs limit
				freeblks += (len mf.data);
				mf.data = nil;
				freeblks--;
				mf.data = array[1] of {* => array [blksz] of byte};
				mf.length = 0;
				mf.mtime = now();
			}
			srv.reply(ref Rmsg.Open(tm.tag, mf.qid, Styx->MAXFDATA));
		Create =>
			(err, c, parent) := fidtomf(srv, qhash, tm.fid);
			if (err == "" && c.open)
				err = Styxlib->Eopen;
			if (err == "" && !(parent.qid.qtype & Sys->QTDIR))
				err = Styxlib->Enotdir;
			if (err == "" && !modeok(OWRITE, parent.perm, c.uname, parent.owner))
				err = Styxlib->Eperm;
			if (err == "" && (tm.perm & Sys->DMDIR) && (tm.mode & (OTRUNC|OWRITE|ORCLOSE)))
				err = Styxlib->Eperm;
			if (err == "" && dirlookup(parent, tm.name) != nil)
				err = Styxlib->Eexists;

			if (err != "") {
				srv.reply(ref Rmsg.Error(tm.tag, err));
				continue;
			}

			isdir := tm.perm & Sys->DMDIR;
			if (!isdir && freeblks <= 0) {
				srv.reply(ref Rmsg.Error(tm.tag, Efull));
				continue;
			}

			# modify perms as per Styx specification...
			perm : int;
			if (isdir)
				perm = (tm.perm&~8r777) | (parent.perm&tm.perm&8r777);
			else
				perm = (tm.perm&(~8r777|8r111)) | (parent.perm&tm.perm& 8r666);

			nmf := newmf(qhash, parent, tm.name, c.uname, perm);
			if (!isdir) {
				freeblks--;
				nmf.data = array[1] of {* => array [blksz] of byte};
			}

			# link in the new MemFile
			nmf.next = parent.kids;
			if (parent.kids != nil)
				parent.kids.prev = nmf;
			parent.kids = nmf;

			c.open = 1;
			c.mode = tm.mode;
			c.qid = nmf.qid;
			nmf.nopen = 1;
			srv.reply(ref Rmsg.Create(tm.tag, nmf.qid, Styx->MAXFDATA));
		Read =>
			(err, c, mf) := fidtomf(srv, qhash, tm.fid);
			if (err == "" && !c.open)
				err = Styxlib->Ebadfid;

			if (err != "") {
				srv.reply(ref Rmsg.Error(tm.tag, err));
				continue;
			}
			data: array of byte = nil;
			if (mf.perm & Sys->DMDIR)
				data = dirdata(mf, int tm.offset, tm.count);
			else
				data = filedata(mf, int tm.offset, tm.count);
			mf.atime = now();
			srv.reply(ref Rmsg.Read(tm.tag, data));
		Write =>
			(err, c, mf) := fidtomf(srv, qhash, tm.fid);
			if (c != nil && !c.open)
				err = Styxlib->Ebadfid;
			if (err == nil && (mf.perm & Sys->DMDIR))
				err = Styxlib->Eperm;
			if (err == nil)
				err = writefile(mf, int tm.offset, tm.data);
			if (err != nil) {
				srv.reply(ref Rmsg.Error(tm.tag, err));
				continue;
			}
			srv.reply(ref Rmsg.Write(tm.tag, len tm.data));
		Clunk =>
			(err, c, mf) := fidtomf(srv, qhash, tm.fid);
			if (c != nil)
				srv.chanfree(c);
			if (err != nil) {
				srv.reply(ref Rmsg.Error(tm.tag, err));
				continue;
			}
			if (c.open) {
				if (c.mode & ORCLOSE)
					unlink(mf);
				mf.nopen--;
				freeblks += delfile(qhash, mf);
			}
			srv.reply(ref Rmsg.Clunk(tm.tag));
		Stat =>
			(err, c, mf) := fidtomf(srv, qhash, tm.fid);
			if (err != nil) {
				srv.reply(ref Rmsg.Error(tm.tag, err));
				continue;
			}
			srv.reply(ref Rmsg.Stat(tm.tag, fileinfo(mf)));
		Remove =>
			(err, c, mf) := fidtomf(srv, qhash, tm.fid);
			if (err != nil) {
				srv.reply(ref Rmsg.Error(tm.tag, err));
				continue;
			}
			srv.chanfree(c);
			parent := mf.parent;
			if (!modeok(OWRITE, parent.perm, c.uname, parent.owner))
				err = Styxlib->Eperm;
			if (err == "" && (mf.perm & Sys->DMDIR) && mf.kids != nil)
				err = "directory not empty";
			if (err == "" && mf == root)
				err = "root directory";
			if (err != nil) {
				srv.reply(ref Rmsg.Error(tm.tag, err));
				continue;
			}

			unlink(mf);
			if (c.open)
				mf.nopen--;
			freeblks += delfile(qhash, mf);
			srv.reply(ref Rmsg.Remove(tm.tag));
		Wstat =>
			(err, c, mf) := fidtomf(srv, qhash, tm.fid);
			stat := tm.stat;
			perm := mf.perm & ~Sys->DMDIR;
			if (err == nil && stat.name != mf.name) {
				parent := mf.parent;
				if (!modeok(OWRITE, parent.perm, c.uname, parent.owner))
					err = Styxlib->Eperm;
				else if (dirlookup(parent, stat.name) != nil)
					err = Styxlib->Eexists;
			}
			if (err == nil && (stat.mode != mf.perm || stat.mtime != mf.mtime)) {
				if (c.uname != mf.owner)
					err = Styxlib->Eperm;
			}
			if (err != nil) {
				srv.reply(ref Rmsg.Error(tm.tag, err));
				continue;
			}
			isdir := mf.perm & Sys->DMDIR;
			if(stat.name != nil)
				mf.name = stat.name;
			if(stat.mode != ~0)
				mf.perm = stat.mode | isdir;
			if(stat.mtime != ~0)
				mf.mtime = stat.mtime;
 			if(stat.uid != nil)
 				mf.owner = stat.uid;
			t := now();
			mf.atime = t;
			mf.parent.mtime = t;
			# not supporting group id at the moment
			srv.reply(ref Rmsg.Wstat(tm.tag));
		Attach =>
			c := srv.newchan(tm.fid);
			if (c == nil) {
				srv.reply(ref Rmsg.Error(tm.tag, Styxlib->Einuse));
				continue;
			}
			c.uname = tm.uname;
			c.qid = root.qid;
			srv.reply(ref Rmsg.Attach(tm.tag, c.qid));
		}
	}
}

writefile(mf: ref Memfile, offset: int, data: array of byte): string
{
	if(mf.perm & Sys->DMAPPEND)
		offset = mf.length;
	startblk := offset/blksz;
	nblks := ((len data + offset) - (startblk * blksz))/blksz;
	lastblk := startblk + nblks;
	need := lastblk + 1 - len mf.data;
	if (need > 0) {
		if (need > freeblks)
			return Efull;
		mf.data = (array [lastblk+1] of array of byte)[:] = mf.data;
		freeblks -= need;
	}
	mf.length = max(mf.length, offset + len data);

	# handle (possibly incomplete first block) separately
	offset %= blksz;
	end := min(blksz-offset, len data);
	if (mf.data[startblk] == nil)
		mf.data[startblk] = array [blksz] of byte;
	mf.data[startblk++][offset:] = data[:end];

	ix := blksz - offset;
	while (ix < len data) {
		if (mf.data[startblk] == nil)
			mf.data[startblk] = array [blksz] of byte;
		end = min(ix+blksz,len data);
		mf.data[startblk++][:] = data[ix:end];
		ix += blksz;
	}
	mf.mtime = now();
	return nil;
}

filedata(mf: ref Memfile, offset, n: int): array of byte
{
	if (offset +n > mf.length)
		n = mf.length - offset;
	if (n == 0)
		return nil;

	data := array [n] of byte;
	startblk := offset/blksz;
	offset %= blksz;
	rn := min(blksz - offset, n);
	data[:] = mf.data[startblk++][offset:offset+rn];
	ix := blksz - offset;
	while (ix < n) {
		rn = blksz;
		if (ix+rn > n)
			rn = n - ix;
		data[ix:] = mf.data[startblk++][:rn];
		ix += blksz;
	}
	return data;
}

QHSIZE: con 256;
QHMASK: con QHSIZE-1;

Qidhash.new() : ref Qidhash
{
	qh := ref Qidhash;
	qh.buckets = array [QHSIZE] of ref Memfile;
	qh.nextqid = 0;
	return qh;
}

Qidhash.add(h : self ref Qidhash, mf : ref Memfile)
{
	path := h.nextqid++;
	mf.qid = Sys->Qid(big path, 0, Sys->QTFILE);
	bix := path & QHMASK;
	mf.hashnext = h.buckets[bix];
	h.buckets[bix] = mf;
}

Qidhash.remove(h : self ref Qidhash, mf : ref Memfile)
{

	bix := int mf.qid.path & QHMASK;
	prev : ref Memfile;
	for (cur := h.buckets[bix]; cur != nil; cur = cur.hashnext) {
		if (cur == mf)
			break;
		prev = cur;
	}
	if (cur != nil) {
		if (prev != nil)
			prev.hashnext = cur.hashnext;
		else
			h.buckets[bix] = cur.hashnext;
		cur.hashnext = nil;
	}
}

Qidhash.lookup(h : self ref Qidhash, qid : Sys->Qid) : ref Memfile
{
	bix := int qid.path & QHMASK;
	for (mf := h.buckets[bix]; mf != nil; mf = mf.hashnext)
		if (mf.qid.path == qid.path)
			break;
	return mf;
}

newmf(qh : ref Qidhash, parent : ref Memfile, name, owner : string, perm : int) : ref Memfile
{
	# qid gets set by Qidhash.add()
	t := now();
	mf := ref Memfile (name, owner, Sys->Qid(big 0,0,Sys->QTFILE), perm, t, t, 0, nil, 0, parent, nil, nil, nil, nil);
	qh.add(mf);
	if(perm & Sys->DMDIR)
		mf.qid.qtype = Sys->QTDIR;
	return mf;
}

fidtomf(srv : ref Styxserver, qh : ref Qidhash, fid : int) : (string, ref Styxlib->Chan, ref Memfile)
{
	c := srv.fidtochan(fid);
	if (c == nil)
		return (Styxlib->Ebadfid, nil, nil);
	mf := qh.lookup(c.qid);
	if (mf == nil)
		return (Styxlib->Enotfound, c, nil);
	return (nil, c, mf);
}

unlink(mf : ref Memfile)
{
	parent := mf.parent;
	if (parent == nil)
		return;
	if (mf.next != nil)
		mf.next.prev = mf.prev;
	if (mf.prev != nil)
		mf.prev.next = mf.next;
	else
		mf.parent.kids = mf.next;
	mf.parent = nil;
	mf.prev = nil;
	mf.next = nil;
}

delfile(qh : ref Qidhash, mf : ref Memfile) : int
{
	if (mf.nopen <= 0 && mf.parent == nil && mf.kids == nil
	&& mf.prev == nil && mf.next == nil) {
		qh.remove(mf);
		nblks := len mf.data;
		mf.data = nil;
		return nblks;
	}
	return 0;
}

dirlookup(dir : ref Memfile, name : string) : ref Memfile
{
	if (name == ".")
		return dir;
	if (name == "..")
		return dir.parent;
	for (mf := dir.kids; mf != nil; mf = mf.next) {
		if (mf.name == name)
			break;
	}
	return mf;
}

access := array[] of {8r400, 8r200, 8r600, 8r100};
modeok(mode, perm : int, user, owner : string) : int
{
	if(mode >= (OTRUNC|ORCLOSE|OREAD|OWRITE))
		return 0;

	# not handling groups!
	if (user != owner)
		perm <<= 6;
	
	if ((mode & OTRUNC) && !(perm & 8r200))
		return 0;

	a := access[mode &3];
	if ((a & perm) != a)
		return 0;
	return 1;
}

dirdata(dir : ref Memfile, start, n : int) : array of byte
{
	data := array[Styx->MAXFDATA] of byte;
	for (k := dir.kids; start > 0 && k != nil; k = k.next) {
		a := styx->packdir(fileinfo(k));
		start -= len a;
	}
	r := 0;
	for (; r < n && k != nil; k = k.next) {
		a := styx->packdir(fileinfo(k));
		if(r+len a > n)
			break;
		data[r:] = a;
		r += len a;
	}
	return data[0:r];
}

fileinfo(f : ref Memfile) : Sys->Dir
{
	dir := sys->zerodir;
	dir.name = f.name;
	dir.uid = f.owner;
	dir.gid = "memfs";
	dir.qid = f.qid;
	dir.mode = f.perm;
	dir.atime = f.atime;
	dir.mtime = f.mtime;
	dir.length = big f.length;
	dir.dtype = 0;
	dir.dev = 0;
	return dir;
}

min(a, b : int) : int
{
	if (a < b)
		return a;
	return b;
}

max(a, b : int) : int
{
	if (a > b)
		return a;
	return b;
}

now(): int
{
	if (timefd == nil)
		return 0;
	buf := array[128] of byte;
	sys->seek(timefd, big 0, 0);
	n := sys->read(timefd, buf, len buf);
	if(n < 0)
		return 0;

	t := (big string buf[0:n]) / big 1000000;
	return int t;
}
