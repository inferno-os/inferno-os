implement Styxlib;

#
# Copyright © 1999 Vita Nuova Limited.  All rights reserved.
# Revisions copyright © 2002 Vita Nuova Holdings Limited.  All rights reserved.
#

include "sys.m";
	sys: Sys;
include "styx.m";
	styx: Styx;
	Tmsg, Rmsg: import styx;

include "styxlib.m";

CHANHASHSIZE: con 32;
starttime: int;
timefd: ref Sys->FD;

DEBUG: con 0;

init(s: Styx): string
{
	sys = load Sys Sys->PATH;
	styx = s;	# our caller inits
	return nil;
}

Styxserver.new(fd: ref Sys->FD): (chan of ref Tmsg, ref Styxserver)
{
	starttime = now();
	srv := ref Styxserver(fd, array[CHANHASHSIZE] of list of ref Chan, getuname(), 0);
	if(fd == nil)
		return (nil, srv);
	tchan := chan of ref Tmsg;
	sync := chan of int;
	spawn tmsgreader(fd, srv, tchan, sync);
	<-sync;
	return (tchan, srv);
}

now(): int
{
	if(timefd == nil){
		timefd = sys->open("/dev/time", sys->OREAD);
		if(timefd == nil)
			return 0;
	}
	buf := array[64] of byte;
	sys->seek(timefd, big 0, 0);
	n := sys->read(timefd, buf, len buf);
	if(n < 0)
		return 0;

	t := (big string buf[0:n]) / big 1000000;
	return int t;
}


getuname(): string
{
	if ((fd := sys->open("/dev/user", Sys->OREAD)) == nil)
		return "unknown";
	buf := array[Sys->NAMEMAX] of byte;
	n := sys->read(fd, buf, len buf);
	if (n <= 0)
		return "unknown";
	return string buf[0:n];
}

tmsgreader(fd: ref Sys->FD, srv: ref Styxserver, tchan: chan of ref Tmsg, sync: chan of int)
{
	sys->pctl(Sys->NEWFD|Sys->NEWNS, fd.fd :: nil);
	sync <-= 1;
	fd = sys->fildes(fd.fd);
	while((m := Tmsg.read(fd, srv.msize)) != nil && tagof m != tagof Tmsg.Readerror){
		tchan <-= m;
		m = nil;
	}
	tchan <-= m;
}

Styxserver.reply(srv: self ref Styxserver, m: ref Rmsg): int
{
	if (DEBUG) 
		sys->fprint(sys->fildes(2), "%s\n", m.text());
	a := m.pack();
	if(a == nil)
		return -1;
	return sys->write(srv.fd, a, len a);
}

Styxserver.devversion(srv: self ref Styxserver, m: ref Tmsg.Version): int
{
	if(srv.msize <= 0)
		srv.msize = Styx->MAXRPC;
	(msize, version) := styx->compatible(m, srv.msize, Styx->VERSION);
	if(msize < 128){
		srv.reply(ref Rmsg.Error(m.tag, "unusable message size"));
		return -1;
	}
	srv.msize = msize;
	srv.reply(ref Rmsg.Version(m.tag, msize, version));
	return 0;
}

Styxserver.devauth(srv: self ref Styxserver, m: ref Tmsg.Auth)
{
	srv.reply(ref Rmsg.Error(m.tag, "authentication not required"));
}

Styxserver.devattach(srv: self ref Styxserver, m: ref Tmsg.Attach): ref Chan
{
	c := srv.newchan(m.fid);
	if (c == nil) {
		srv.reply(ref Rmsg.Error(m.tag, Einuse));
		return nil;
	}
	c.uname = m.uname;
	c.qid.qtype = Sys->QTDIR;
	c.qid.path = big 0;
	c.path = "dev";
	srv.reply(ref Rmsg.Attach(m.tag, c.qid));
	return c;
}

Styxserver.clone(srv: self ref Styxserver, oc: ref Chan, newfid: int): ref Chan
{
	c := srv.newchan(newfid);
	if (c == nil) 
		return nil;
	c.qid = oc.qid;
	c.uname  = oc.uname;
	c.open = oc.open;
	c.mode = oc.mode;
	c.path = oc.path;
	c.data = oc.data;
	return c;
}

Styxserver.devflush(srv: self ref Styxserver, m: ref Tmsg.Flush)
{
	srv.reply(ref Rmsg.Flush(m.tag));
}

Styxserver.devwalk(srv: self ref Styxserver, m: ref Tmsg.Walk,
							gen: Dirgenmod, tab: array of Dirtab): ref Chan
{
	c := srv.fidtochan(m.fid);
	if (c == nil) {
		srv.reply(ref Rmsg.Error(m.tag, Ebadfid));
		return nil;
	}
	if (c.open) {
		srv.reply(ref Rmsg.Error(m.tag, Eopen));
		return nil;
	}
	if (!c.isdir()) {
		srv.reply(ref Rmsg.Error(m.tag, Enotdir));
		return nil;
	}
	# should check permissions here?
	qids: array of Sys->Qid;
	cc := ref *c;	# walk a temporary copy
	if(len m.names > 0){
		qids = array[len m.names] of Sys->Qid;
		for(i := 0; i < len m.names; i++){
			for(k := 0;; k++){
				(ok, d) := gen->dirgen(srv, cc, tab, k);
				if(ok < 0){
					if(i == 0)
						srv.reply(ref Rmsg.Error(m.tag, Enotfound));
					else
						srv.reply(ref Rmsg.Walk(m.tag, qids[0:i]));
					return nil;
				}
				if (d.name == m.names[i]) {
					cc.qid = d.qid;
					cc.path = d.name;
					qids[i] = cc.qid;
					break;
				}
			}
		}
	}
	# successful walk
	if(m.newfid != m.fid){
		# clone/walk
		nc := srv.clone(cc, m.newfid);
		if(nc == nil){
			srv.reply(ref Rmsg.Error(m.tag, Einuse));
			return nil;
		}
		c = nc;
	}else{
		# walk c itself
		c.qid = cc.qid;
		c.path = cc.path;
	}
	srv.reply(ref Rmsg.Walk(m.tag, qids));
	return c;
}

Styxserver.devclunk(srv: self ref Styxserver, m: ref Tmsg.Clunk): ref Chan
{
	c := srv.fidtochan(m.fid);
	if (c == nil) {
		srv.reply(ref Rmsg.Error(m.tag, Ebadfid));
		return nil;
	}
	srv.chanfree(c);
	srv.reply(ref Rmsg.Clunk(m.tag));
	return c;
}

Styxserver.devstat(srv: self ref Styxserver, m: ref Tmsg.Stat,
							gen: Dirgenmod, tab: array of Dirtab)
{
	c := srv.fidtochan(m.fid);
	if (c == nil) {
		srv.reply(ref Rmsg.Error(m.tag, Ebadfid));
		return;
	}
	i := 0;
	(ok, d) := gen->dirgen(srv, c, tab, i++);
	while (ok >= 0) {
		if (ok > 0 && c.qid.path == d.qid.path) {
			srv.reply(ref Rmsg.Stat(m.tag, d));
			return;
		}
		(ok, d) = gen->dirgen(srv, c, tab, i++);
	}
	# auto-generate entry for directory if not found.
	# XXX this is asking for trouble, as the permissions given
	# on stat() of a directory can be different from those given
	# when reading the directory's entry in its parent dir.
	if (c.qid.qtype & Sys->QTDIR)
		srv.reply(ref Rmsg.Stat(m.tag, devdir(c, c.qid, c.path, big 0, srv.uname, Sys->DMDIR|8r555)));
	else
		srv.reply(ref Rmsg.Error(m.tag, Enotfound));
}

Styxserver.devdirread(srv: self ref Styxserver, m: ref Tmsg.Read,
							gen: Dirgenmod, tab: array of Dirtab)
{
	c := srv.fidtochan(m.fid);
	if (c == nil) {
		srv.reply(ref Rmsg.Error(m.tag, Ebadfid));
		return;
	}
	offset := int m.offset;
	data := array[m.count] of byte;
	start := 0;
	n := 0;
	for (k := 0;; k++) {
		(ok, d) := gen->dirgen(srv, c, tab, k);
		if(ok < 0){
			srv.reply(ref Rmsg.Read(m.tag, data[0:n]));
			return;
		}
		size := styx->packdirsize(d);
		if(start < offset){
			start += size;
			continue;
		}
		if(n+size > m.count)
			break;
		data[n:] = styx->packdir(d);
		n += size;
	}
	srv.reply(ref Rmsg.Read(m.tag, data[0:n]));
}

Styxserver.devopen(srv: self ref Styxserver, m: ref Tmsg.Open,
							gen: Dirgenmod, tab: array of Dirtab): ref Chan
{
	c := srv.fidtochan(m.fid);
	if (c == nil) {
		srv.reply(ref Rmsg.Error(m.tag, Ebadfid));
		return nil;
	}
	omode := m.mode;
	i := 0;
	(ok, d) := gen->dirgen(srv, c, tab, i++);
	while (ok >= 0) {
		# XXX dev.c checks vers as well... is that desirable?
		if (ok > 0 && c.qid.path == d.qid.path) {
			if (openok(omode, d.mode, c.uname, d.uid, d.gid)) {
				c.qid.vers = d.qid.vers;
				break;
			}
			srv.reply(ref Rmsg.Error(m.tag, Eperm));
			return nil;
		}
		(ok, d) = gen->dirgen(srv, c, tab, i++);
	}
	if ((c.qid.qtype & Sys->QTDIR) && omode != Sys->OREAD) {
		srv.reply(ref Rmsg.Error(m.tag, Eperm));
		return nil;
	}
	if ((c.mode = openmode(omode)) == -1) {
		srv.reply(ref Rmsg.Error(m.tag, Ebadarg));
		return nil;
	}
	c.open = 1;
	c.mode = omode;
	srv.reply(ref Rmsg.Open(m.tag, c.qid, Styx->MAXFDATA));
	return c;
}

Styxserver.devremove(srv: self ref Styxserver, m: ref Tmsg.Remove): ref Chan
{
	c := srv.fidtochan(m.fid);
	if (c == nil) {
		srv.reply(ref Rmsg.Error(m.tag, Ebadfid));
		return nil;
	}
	srv.chanfree(c);
	srv.reply(ref Rmsg.Error(m.tag, Eperm));
	return c;
}

Styxserver.fidtochan(srv: self ref Styxserver, fid: int): ref Chan
{
	for (l := srv.chans[fid & (CHANHASHSIZE-1)]; l != nil; l = tl l)
		if ((hd l).fid == fid)
			return hd l;
	return nil;
}

Styxserver.chanfree(srv: self ref Styxserver, c: ref Chan)
{
	slot := c.fid & (CHANHASHSIZE-1);
	nl: list of ref Chan;
	for (l := srv.chans[slot]; l != nil; l = tl l)
		if ((hd l).fid != c.fid)
			nl = (hd l) :: nl;
	srv.chans[slot] = nl;
}

Styxserver.chanlist(srv: self ref Styxserver): list of ref Chan
{
	cl: list of ref Chan;
	for (i := 0; i < len srv.chans; i++)
		for (l := srv.chans[i]; l != nil; l = tl l)
			cl = hd l :: cl;
	return cl;
}

Styxserver.newchan(srv: self ref Styxserver, fid: int): ref Chan
{
	# fid already in use
	if ((c := srv.fidtochan(fid)) != nil)
		return nil;
	c = ref Chan;
	c.qid = Sys->Qid(big 0, 0, Sys->QTFILE);
	c.open = 0;
	c.mode = 0;
	c.fid = fid;
	slot := fid & (CHANHASHSIZE-1);
	srv.chans[slot] = c :: srv.chans[slot];
	return c;
}

devdir(nil: ref Chan, qid: Sys->Qid, name: string, length: big,
				user: string, perm: int): Sys->Dir
{
	d: Sys->Dir;
	d.name = name;
	d.qid = qid;
	d.dtype = 'X';
	d.dev = 0;		# XXX what should this be?
	d.mode = perm;
	if (qid.qtype & Sys->QTDIR)
		d.mode |= Sys->DMDIR;
	d.atime = starttime;	# XXX should be better than this.
	d.mtime = starttime;
	d.length = length;
	d.uid = user;
	d.gid = user;
	return d;
}

readbytes(m: ref Tmsg.Read, d: array of byte): ref Rmsg.Read
{
	r := ref Rmsg.Read(m.tag, nil);
	offset := int m.offset;
	if (offset >= len d)
		return r;
	e := offset + m.count;
	if (e > len d)
		e = len d;
	r.data = d[offset:e];
	return r;
}

readnum(m: ref Tmsg.Read, val, size: int): ref Rmsg.Read
{
	return readbytes(m, sys->aprint("%-*d", size, val));
}

readstr(m: ref Tmsg.Read, d: string): ref Rmsg.Read
{
	return readbytes(m, array of byte d);
}

dirgenmodule(): Dirgenmod
{
	return load Dirgenmod "$self";
}

dirgen(srv: ref Styxserver, c: ref Styxlib->Chan,
				tab: array of Dirtab, i: int): (int, Sys->Dir)
{
	d: Sys->Dir;
	if (tab == nil || i >= len tab)
		return (-1, d);
	return (1, devdir(c, tab[i].qid, tab[i].name, tab[i].length, srv.uname, tab[i].perm));
}

openmode(o: int): int
{
	OTRUNC, ORCLOSE, OREAD, ORDWR: import Sys;
	if(o >= (OTRUNC|ORCLOSE|ORDWR))
		return -1;
	o &= ~(OTRUNC|ORCLOSE);
	if(o > ORDWR)
		return -1;
	return o;
}

access := array[] of {8r400, 8r200, 8r600, 8r100};
openok(omode, perm: int, uname, funame, nil: string): int
{
	# XXX what should we do about groups?
	# this is inadequate anyway:
	# OTRUNC
	# user should be allowed to open it if permission
	# is allowed to others.
	mode: int;
	if (uname == funame)
		mode = perm;
	else
		mode = perm << 6;

	t := access[omode & 3];
	return ((t & mode) == t);
}	

Chan.isdir(c: self ref Chan): int
{
	return (c.qid.qtype & Sys->QTDIR) != 0;
}
