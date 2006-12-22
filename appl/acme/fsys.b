implement Fsys;

include "common.m";

sys : Sys;
styx : Styx;
styxaux : Styxaux;
acme : Acme;
dat : Dat;
utils : Utils;
look : Look;
windowm : Windowm;
xfidm : Xfidm;

QTDIR, QTFILE, QTAPPEND : import Sys;
DMDIR, DMAPPEND, Qid, ORCLOSE, OTRUNC, OREAD, OWRITE, ORDWR, Dir : import Sys;
sprint : import sys;
MAXWELEM, Rerror : import Styx;
Qdir,Qacme,Qcons,Qconsctl,Qdraw,Qeditout,Qindex,Qlabel,Qnew,QWaddr,QWbody,QWconsctl,QWctl,QWdata,QWeditout,QWevent,QWrdsel,QWwrsel,QWtag,QMAX : import Dat;
TRUE, FALSE : import Dat;
cxfidalloc, cerr : import dat;
Mntdir, Fid, Dirtab, Lock, Ref, Smsg0 : import dat;
Tmsg, Rmsg : import styx;
msize, version, fid, uname, aname, newfid, name, mode, offset, count, setmode : import styxaux;
Xfid : import xfidm;
row : import dat;
Column : import Columnm;
Window : import windowm;
lookid : import look;
warning, error : import utils;

init(mods : ref Dat->Mods)
{
	messagesize = Styx->MAXRPC;

	sys = mods.sys;
	styx = mods.styx;
	styxaux = mods.styxaux;
	acme = mods.acme;
	dat = mods.dat;
	utils = mods.utils;
	look = mods.look;
	windowm = mods.windowm;
	xfidm = mods.xfidm;
}

sfd, cfd : ref Sys->FD;

Nhash : con 16;
DEBUG : con 0;

fids := array[Nhash] of ref Fid;

Eperm := "permission denied";
Eexist := "file does not exist";
Enotdir := "not a directory";

dirtab := array[10] of {
	Dirtab ( ".",		QTDIR,		Qdir,			8r500|DMDIR ),
	Dirtab ( "acme",	QTDIR,		Qacme,		8r500|DMDIR ),
	Dirtab ( "cons",		QTFILE,		Qcons,		8r600 ),
	Dirtab ( "consctl",	QTFILE,		Qconsctl,		8r000 ),
	Dirtab ( "draw",		QTDIR,		Qdraw,		8r000|DMDIR ),
	Dirtab ( "editout",	QTFILE,		Qeditout,		8r200 ),
	Dirtab ( "index",	QTFILE,		Qindex,		8r400 ),
	Dirtab ( "label",		QTFILE,		Qlabel,		8r600 ),
	Dirtab ( "new",		QTDIR,		Qnew,		8r500|DMDIR ),
	Dirtab ( nil,		0,			0,			0 ),
};

dirtabw := array[12] of {
	Dirtab ( ".",		QTDIR,		Qdir,			8r500|DMDIR ),
	Dirtab ( "addr",		QTFILE,		QWaddr,		8r600 ),
	Dirtab ( "body",		QTAPPEND,	QWbody,		8r600|DMAPPEND ),
	Dirtab ( "ctl",		QTFILE,		QWctl,		8r600 ),
	Dirtab ( "consctl",	QTFILE,		QWconsctl,	8r200 ),
	Dirtab ( "data",		QTFILE,		QWdata,		8r600 ),
	Dirtab ( "editout",	QTFILE,		QWeditout,	8r200 ),
	Dirtab ( "event",	QTFILE,		QWevent,		8r600 ),
	Dirtab ( "rdsel",		QTFILE,		QWrdsel,		8r400 ),
	Dirtab ( "wrsel",	QTFILE,		QWwrsel,		8r200 ),
	Dirtab ( "tag",		QTAPPEND,	QWtag,		8r600|DMAPPEND ),
	Dirtab ( nil, 		0,			0,			0 ),
};

Mnt : adt {
	qlock : ref Lock;
	id : int;
	md : ref Mntdir;
};

mnt : Mnt;
user : string;
clockfd : ref Sys->FD;
closing := 0;

fsysinit() 
{
	p :  array of ref Sys->FD;

	p = array[2] of ref Sys->FD;
	if(sys->pipe(p) < 0)
		error("can't create pipe");
	cfd = p[0];
	sfd = p[1];
	clockfd = sys->open("/dev/time", Sys->OREAD);
	user = utils->getuser();
	if (user == nil)
		user = "Wile. E. Coyote";
	mnt.qlock = Lock.init();
	mnt.id = 0;
	spawn fsysproc();
}

fsyscfd() : int
{
	return cfd.fd;
}

QID(w, q : int) : int
{
	return (w<<8)|q;
}

FILE(q : Qid) : int
{
	return int q.path & 16rFF;
}

WIN(q : Qid) : int
{
	return (int q.path>>8) & 16rFFFFFF;
}

# nullsmsg : Smsg;
nullsmsg0 : Smsg0;

fsysproc()
{
	n, ok : int;
	x : ref Xfid;
	f : ref Fid;
	t : Smsg0;

	acme->fsyspid = sys->pctl(0, nil);
	x = nil;
	for(;;){
		if(x == nil){
			cxfidalloc <-= nil;
			x = <-cxfidalloc;
		}
		n = sys->read(sfd, x.buf, messagesize);
		if(n <= 0) {
			if (closing)
				break;
			error("i/o error on server channel");
		}
		(ok, x.fcall) = Tmsg.unpack(x.buf[0:n]);
		if(ok < 0)
			error("convert error in convM2S");
		if(DEBUG)
			utils->debug(sprint("%d:%s\n", x.tid, x.fcall.text()));
		pick fc := x.fcall {
			Version =>
				f = nil;
			Auth =>
				f = nil;
			* =>
				f = allocfid(fid(x.fcall));
		}
		x.f = f;
		pick fc := x.fcall {
			Readerror =>	x = fsyserror();
			Flush =>		x = fsysflush(x);
			Version =>	x = fsysversion(x);
			Auth =>		x = fsysauth(x);
			Attach =>		x = fsysattach(x, f);
			Walk =>		x = fsyswalk(x, f);
			Open =>		x = fsysopen(x, f);
			Create =>		x = fsyscreate(x);
			Read =>		x = fsysread(x, f);
			Write =>		x = fsyswrite(x);
			Clunk =>		x = fsysclunk(x, f);
			Remove =>	x = fsysremove(x);
			Stat =>		x = fsysstat(x, f);
			Wstat =>		x = fsyswstat(x);
			# Clone =>	x = fsysclone(x, f);
			* =>
				x = respond(x, t, "bad fcall type");
		}
	}
}

fsysaddid(dir : string, ndir : int, incl : array of string, nincl : int) : ref Mntdir
{
	m : ref Mntdir;
	id : int;

	mnt.qlock.lock();
	id = ++mnt.id;
	m = ref Mntdir;
	m.id = id;
	m.dir =  dir;
	m.refs = 1;	# one for Command, one will be incremented in attach
	m.ndir = ndir;
	m.next = mnt.md;
	m.incl = incl;
	m.nincl = nincl;
	mnt.md = m;
	mnt.qlock.unlock();
	return m;
}

fsysdelid(idm : ref Mntdir)
{
	m, prev : ref Mntdir;
	i : int;
	
	if(idm == nil)
		return;
	mnt.qlock.lock();
	if(--idm.refs > 0){
		mnt.qlock.unlock();
		return;
	}
	prev = nil;
	for(m=mnt.md; m != nil; m=m.next){
		if(m == idm){
			if(prev != nil)
				prev.next = m.next;
			else
				mnt.md = m.next;
			for(i=0; i<m.nincl; i++)
				m.incl[i] = nil;
			m.incl = nil;
			m.dir = nil;
			m = nil;
			mnt.qlock.unlock();
			return;
		}
		prev = m;
	}
	mnt.qlock.unlock();
	buf := sys->sprint("fsysdelid: can't find id %d\n", idm.id);
	cerr <-= buf;
}

#
# Called only in exec.l:run(), from a different FD group
#
fsysmount(dir : string, ndir : int, incl : array of string, nincl : int) : ref Mntdir
{
	m : ref Mntdir;

	# close server side so don't hang if acme is half-exited
	# sfd = nil;
	m = fsysaddid(dir, ndir, incl, nincl);
	buf := sys->sprint("%d", m.id);
	if(sys->mount(cfd, nil, "/mnt/acme", Sys->MREPL, buf) < 0){
		fsysdelid(m);
		return nil;
	}
	# cfd = nil;
	sys->bind("/mnt/acme", "/chan", Sys->MBEFORE);	# was MREPL
	if(sys->bind("/mnt/acme", "/dev", Sys->MBEFORE) < 0){
		fsysdelid(m);
		return nil;
	}
	return m;
}

fsysclose()
{
	closing = 1;
	# sfd = cfd = nil;
}

respond(x : ref Xfid, t0 : Smsg0, err : string) : ref Xfid
{
	t : ref Rmsg;

	# t = nullsmsg;
	tag := x.fcall.tag;
	# fid := fid(x.fcall);
	qid := t0.qid;
	if(err != nil)
		t = ref Rmsg.Error(tag, err);
	else
	pick fc := x.fcall {
		Readerror =>	t = ref Rmsg.Error(tag, err);
		Flush =>		t = ref Rmsg.Flush(tag);
		Version =>	t = ref Rmsg.Version(tag, t0.msize, t0.version);
		Auth =>		t = ref Rmsg.Auth(tag, qid);
		# Clone =>	t = ref Rmsg.Clone(tag, fid);
		Attach =>		t = ref Rmsg.Attach(tag, qid);
		Walk =>		t = ref Rmsg.Walk(tag, t0.qids);
		Open =>		t = ref Rmsg.Open(tag, qid, t0.iounit);
		Create =>		t = ref Rmsg.Create(tag, qid, 0);
		Read =>		if(t0.count == len t0.data)
						t = ref Rmsg.Read(tag, t0.data);
					else
						t = ref Rmsg.Read(tag, t0.data[0: t0.count]);
		Write =>		t = ref Rmsg.Write(tag, t0.count);
		Clunk =>		t = ref Rmsg.Clunk(tag);
		Remove =>	t = ref Rmsg.Remove(tag);
		Stat =>		t = ref Rmsg.Stat(tag, t0.stat);
		Wstat =>		t = ref Rmsg.Wstat(tag);
		
	}
	# t.qid = t0.qid;
	# t.count = t0.count;
	# t.data = t0.data;
	# t.stat = t0.stat;
	# t.fid = x.fcall.fid;
	# t.tag = x.fcall.tag;
	buf := t.pack();
	if(buf == nil)
		error("convert error in convS2M");
	if(sys->write(sfd, buf, len buf) != len buf)
		error("write error in respond");
	buf = nil;
	if(DEBUG)
		utils->debug(sprint("%d:r: %s\n", x.tid, t.text()));
	return x;
}

# fsysnop(x : ref Xfid) : ref Xfid
# {
# 	t : Smsg0;
# 
# 	return respond(x, t, nil);
# }

fsyserror() : ref Xfid
{
	error("sys error : Terror");
	return nil;
}

fsyssession(x : ref Xfid) : ref Xfid
{
	t : Smsg0;

	# BUG: should shut everybody down ??
	t = nullsmsg0;
	return respond(x, t, nil);
}

fsysversion(x : ref Xfid) : ref Xfid
{
	t : Smsg0;

	pick m := x.fcall {
		Version =>
			(t.msize, t.version) = styx->compatible(m, messagesize, nil);
			messagesize = t.msize;
			return respond(x, t, nil);
	}
	return respond(x, t, "acme: bad version");

	# ms := msize(x.fcall);
	# if(ms < 256)
	# 	return respond(x, t, "version: message size too small");
	# t.msize = messagesize = ms;
	# v := version(x.fcall);
	# if(len v < 6 || v[0: 6] != "9P2000")
	# 	return respond(x, t, "unrecognized 9P version");
	# t.version = "9P2000";
	# return respond(x, t, nil);
}

fsysauth(x : ref Xfid) : ref Xfid
{
	t : Smsg0;

	return respond(x, t, "acme: authentication not required");
}

fsysflush(x : ref Xfid) : ref Xfid
{
	x.c <-= Xfidm->Xflush;
	return nil;
}

fsysattach(x : ref Xfid, f : ref Fid) : ref Xfid
{
	t : Smsg0;
	id : int;
	m : ref Mntdir;

	if (uname(x.fcall) != user)
		return respond(x, t, Eperm);
	f.busy = TRUE;
	f.open = FALSE;
	f.qid = (Qid)(big Qdir, 0, QTDIR);
	f.dir = dirtab;
	f.nrpart = 0;
	f.w = nil;
	t.qid = f.qid;
	f.mntdir = nil;
	id = int aname(x.fcall);
	mnt.qlock.lock();
	for(m=mnt.md; m != nil; m=m.next)
		if(m.id == id){
			f.mntdir = m;
			m.refs++;
			break;
		}
	if(m == nil)
		cerr <-= "unknown id in attach";
	mnt.qlock.unlock();
	return respond(x, t, nil);
}

fsyswalk(x : ref Xfid, f : ref Fid) : ref Xfid
{
	t : Smsg0;
	c, i, j, id : int;
	path, qtype : int;
	d, dir : array of Dirtab;
	w : ref Window;
	nf : ref Fid;

	if(f.open)
		return respond(x, t, "walk of open file");
	if(fid(x.fcall) != newfid(x.fcall)){
		nf = allocfid(newfid(x.fcall));
		if(nf.busy)
			return respond(x, t, "newfid already in use");
		nf.busy = TRUE;
		nf.open = FALSE;
		nf.mntdir = f.mntdir;
		if(f.mntdir != nil)
			f.mntdir.refs++;
		nf.dir = f.dir;
		nf.qid = f.qid;
		nf.w = f.w;
		nf.nrpart = 0;	# not open, so must be zero
		if(nf.w != nil)
			nf.w.refx.inc();
		f = nf;	# walk f
	}

	qtype = QTFILE;
	wqids: list of Qid;
	err := string nil;
	id = WIN(f.qid);
	q := f.qid;
	names := styxaux->names(x.fcall);
	nwname := len names;

	if(nwname > 0){
		for(i = 0; i < nwname; i++){
			if((q.qtype & QTDIR) == 0){
				err = Enotdir;
				break;
			}

			name := names[i];
			if(name == ".."){
				path = Qdir;
				qtype = QTDIR;
				id = 0;
				if(w != nil){
					w.close();
					w = nil;
				}
				if(i == MAXWELEM){
					err = "name too long";
					break;
				}
				q.qtype = qtype;
				q.vers = 0;
				q.path = big QID(id, path);
				wqids = q :: wqids;
				continue;
			}

			# is it a numeric name?
			regular := 0;
			for(j=0; j < len name; j++) {
				c = name[j];
				if(c<'0' || '9'<c) {
					regular = 1;
					break;
				}
			}

			if (!regular) {
				# yes: it's a directory
				if(w != nil)	# name has form 27/23; get out before losing w
					break;
				id = int name;
				row.qlock.lock();
				w = lookid(id, FALSE);
				if(w == nil){
					row.qlock.unlock();
					break;
				}
				w.refx.inc();
				path = Qdir;
				qtype = QTDIR;
				row.qlock.unlock();
				dir = dirtabw;
				if(i == MAXWELEM){
					err = "name too long";
					break;
				}
				q.qtype = qtype;
				q.vers = 0;
				q.path = big QID(id, path);
				wqids = q :: wqids;
				continue;
			}
			else {
				# if(FILE(f.qid) == Qacme) 	# empty directory
				#	break;
				if(name == "new"){
					if(w != nil)
						error("w set in walk to new");
					cw := chan of ref Window;
					spawn x.walk(cw);
					w = <- cw;
					w.refx.inc();
					path = QID(w.id, Qdir);
					qtype = QTDIR;
					id = w.id;
					dir = dirtabw;
					# x.c <-= Xfidm->Xwalk;
					if(i == MAXWELEM){
						err = "name too long";
						break;
					}
					q.qtype = qtype;
					q.vers = 0;
					q.path = big QID(id, path);
					wqids = q :: wqids;
					continue;
				}

				if(id == 0)
					d = dirtab;
				else
					d = dirtabw;
				k := 1;	# skip '.'
				found := 0;
				for( ; d[k].name != nil; k++){
					if(name == d[k].name){
						path = d[k].qid;
						qtype = d[k].qtype;
						dir = d[k:];
						if(i == MAXWELEM){
							err = "name too long";
							break;
						}
						q.qtype = qtype;
						q.vers = 0;
						q.path = big QID(id, path);
						wqids = q :: wqids;
						found = 1;
						break;
					}
				}
				if(found)
					continue;
				break;	# file not found
			}
		}

		if(i == 0 && err == nil)
			err = Eexist;
	}

	nwqid := len wqids;
	if(nwqid > 0){
		t.qids = array[nwqid] of Qid;
		for(i = nwqid-1; i >= 0; i--){
			t.qids[i] = hd wqids;
			wqids = tl wqids;
		}
	}
	if(err != nil || nwqid < nwname){
		if(nf != nil){
			nf.busy = FALSE;
			fsysdelid(nf.mntdir);
		}
	}
	else if(nwqid == nwname){
		if(w != nil){
			f.w = w;
			w = nil;
		}
		if(dir != nil)
			f.dir = dir;
		f.qid = q;
	}

	if(w != nil)
		w.close();

	return respond(x, t, err);
}

fsysopen(x : ref Xfid, f : ref Fid) : ref Xfid
{
	t : Smsg0;
	m : int;

	# can't truncate anything, so just disregard
	setmode(x.fcall, mode(x.fcall)&~OTRUNC);
	# can't execute or remove anything
	if(mode(x.fcall)&ORCLOSE)
		return respond(x, t, Eperm);
	case(mode(x.fcall)){
	OREAD =>
		m = 8r400;
	OWRITE =>
		m = 8r200;
	ORDWR =>
		m = 8r600;
	* =>
		return respond(x, t, Eperm);
	}
	if(((f.dir[0].perm&~(DMDIR|DMAPPEND))&m) != m)
		return respond(x, t, Eperm);
	x.c <-= Xfidm->Xopen;
	return nil;
}

fsyscreate(x : ref Xfid) : ref Xfid
{
	t : Smsg0;

	return respond(x, t, Eperm);
}

idcmp(a, b : int) : int
{
	return a-b;
}

qsort(a : array of int, n : int)
{
	i, j : int;
	t : int;

	while(n > 1) {
		i = n>>1;
		t = a[0]; a[0] = a[i]; a[i] = t;
		i = 0;
		j = n;
		for(;;) {
			do
				i++;
			while(i < n && idcmp(a[i], a[0]) < 0);
			do
				j--;
			while(j > 0 && idcmp(a[j], a[0]) > 0);
			if(j < i)
				break;
			t = a[i]; a[i] = a[j]; a[j] = t;
		}
		t = a[0]; a[0] = a[j]; a[j] = t;
		n = n-j-1;
		if(j >= n) {
			qsort(a, j);
			a = a[j+1:];
		} else {
			qsort(a[j+1:], n);
			n = j;
		}
	}
}

fsysread(x : ref Xfid, f : ref Fid) : ref Xfid
{
	t : Smsg0;
	b : array of byte;
	i, id, n, o, e, j, k, nids : int;
	ids : array of int;
	d : array of Dirtab;
	dt : Dirtab;
	c : ref Column;
	clock : int;

	b = nil;
	if(f.qid.qtype & QTDIR){
		# if(int offset(x.fcall) % DIRLEN)
		#	return respond(x, t, "illegal offset in directory");
		if(FILE(f.qid) == Qacme){	# empty dir
			t.data = nil;
			t.count = 0;
			respond(x, t, nil);
			return x;
		}
		o = int offset(x.fcall);
		e = int offset(x.fcall)+count(x.fcall);
		clock = getclock();
		b = array[messagesize] of byte;
		id = WIN(f.qid);
		n = 0;
		if(id > 0)
			d = dirtabw;
		else
			d = dirtab;
		k = 1;	# first entry is '.' 
		leng := 0;
		for(i=0; d[k].name!=nil && i<e; i+=leng){
			bb := styx->packdir(dostat(WIN(x.f.qid), d[k], clock));
			leng = len bb;
			for (kk := 0; kk < leng; kk++)
				b[kk+n] = bb[kk];
			bb = nil;
			if(leng <= Styx->BIT16SZ)
				break;
			if(i >= o)
				n += leng;
			k++;
		}
		if(id == 0){
			row.qlock.lock();
			nids = 0;
			ids = nil;
			for(j=0; j<row.ncol; j++){
				c = row.col[j];
				for(k=0; k<c.nw; k++){
					oids := ids;
					ids = array[nids+1] of int;
					ids[0:] = oids[0:nids];
					oids = nil;
					ids[nids++] = c.w[k].id;
				}
			}
			row.qlock.unlock();
			qsort(ids, nids);
			j = 0;
			for(; j<nids && i<e; i+=leng){
				k = ids[j];
				dt.name = sys->sprint("%d", k);
				dt.qid = QID(k, 0);
				dt.qtype = QTDIR;
				dt.perm = DMDIR|8r700;
				bb := styx->packdir(dostat(k, dt, clock));
				leng = len bb;
				for (kk := 0; kk < leng; kk++)
					b[kk+n] = bb[kk];
				bb = nil;
				if(leng == 0)
					break;
				if(i >= o)
					n += leng;
				j++;
			}
			ids = nil;
		}
		t.data = b;
		t.count = n;
		respond(x, t, nil);
		b = nil;
		return x;
	}
	x.c <-= Xfidm->Xread;
	return nil;
}

fsyswrite(x : ref Xfid) : ref Xfid
{
	x.c <-= Xfidm->Xwrite;
	return nil;
}

fsysclunk(x : ref Xfid, f : ref Fid) : ref Xfid
{
	t : Smsg0;

	fsysdelid(f.mntdir);
	if(f.open){
		f.busy = FALSE;
		f.open = FALSE;
		x.c <-= Xfidm->Xclose;
		return nil;
	}
	if(f.w != nil)
		f.w.close();
	f.busy = FALSE;
	f.open = FALSE;
	return respond(x, t, nil);
}

fsysremove(x : ref Xfid) : ref Xfid
{
	t : Smsg0;

	return respond(x, t, Eperm);
}

fsysstat(x : ref Xfid, f : ref Fid) : ref Xfid
{
	t : Smsg0;

	t.stat = dostat(WIN(x.f.qid), f.dir[0], getclock());
	return respond(x, t, nil);
}

fsyswstat(x : ref Xfid) : ref Xfid
{
	t : Smsg0;

	return respond(x, t, Eperm);
}

allocfid(fid : int) : ref Fid
{	
	f, ff : ref Fid;
	fh : int;

	ff = nil;
	fh = fid&(Nhash-1);
	for(f=fids[fh]; f != nil; f=f.next)
		if(f.fid == fid)
			return f;
		else if(ff==nil && f.busy==FALSE)
			ff = f;
	if(ff != nil){
		ff.fid = fid;
		return ff;
	}
	f = ref Fid;
	f.busy = FALSE;
	f.rpart = array[Sys->UTFmax] of byte;
	f.nrpart = 0;
	f.fid = fid;
	f.next = fids[fh];
	fids[fh] = f;
	return f;
}

cbuf := array[32] of byte;

getclock() : int
{
	sys->seek(clockfd, big 0, 0);
	n := sys->read(clockfd, cbuf, len cbuf);
	return int string cbuf[0:n];
}

dostat(id : int, dir : Dirtab, clock : int) : Sys->Dir
{
	d : Dir;

	d.qid.path = big QID(id, dir.qid);
	d.qid.vers = 0;
	d.qid.qtype = dir.qtype;
	d.mode = dir.perm;
	d.length = big 0;	# would be nice to do better
	d.name = dir.name;
	d.uid = user;
	d.gid = user;
	d.atime = clock;
	d.mtime = clock;
	d.dtype = d.dev = 0;
	return d;
	# buf := styx->convD2M(d);
	# d = nil;
	# return buf;
}
