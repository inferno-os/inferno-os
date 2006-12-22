implement Dbfs;

#
# Copyright © 1999, 2002 Vita Nuova Limited.  All rights reserved.
#

# Enhanced to include record locking, index field generation and update notification

# TO DO:
#	make writing & reading more like real files; don't ignore offsets.
#	open with OTRUNC should work.
#	provide some way of compacting a dbfs file.

include "sys.m";
	sys: Sys;
	Qid: import Sys;

include "draw.m";

include "arg.m";

include "styx.m";
	styx: Styx;
	Rmsg, Tmsg: import styx;

include "styxservers.m";
	styxservers: Styxservers;
	Styxserver, Fid, Navigator, Navop: import styxservers;
	Enotfound, Eperm, Ebadfid, Ebadarg: import styxservers;

include "string.m";
	str: String;

include "bufio.m";
	bufio: Bufio;
	Iobuf: import bufio;

include "sh.m";
	sh: Sh;

Record: adt {
	id:		int;			# file number in directory (if block is allocated)
	offset:	int;			# start of data
	count:	int;			# length of block (excluding header)
	datalen:	int;			# length of data (-1 if block is free)
	vers:		int;			# version

	new:		fn(offset: int, length: int): ref Record;
	qid:		fn(r: self ref Record): Sys->Qid;
};

# Record lock
Lock: adt {
	qpath: big;
	fid:	int;
};

HEADLEN: con 10;
MINSIZE: con 20;

Database: adt {
	file:		ref Iobuf;
	records:	array of ref Record;
	maxid:	int;
	locking:	int;
	locklist:	list of Lock;
	indexing:	int;
	stats:	int;
	index:	int;
	s_reads:	int;
	s_writes:	int;
	s_creates:	int;
	s_removes:	int;
	updcmd:	string;
	vers:		int;

	build:	fn(f: ref Iobuf, locking, indexing: int, stats: int, updcmd: string): (ref Database, string);
	write:	fn(db: self ref Database, n: int, data: array of byte): int;
	read:		fn(db: self ref Database, n: int): array of byte;
	remove:	fn(db: self ref Database, n: int);
	create:	fn(db: self ref Database, data: array of byte): ref Record;
	updated:	fn(db: self ref Database);
	lock:		fn(db: self ref Database, c: ref Styxservers->Fid): int;
	unlock:	fn(db: self ref Database, c: ref Styxservers->Fid);
	ownlock:	fn(db: self ref Database, c: ref Styxservers->Fid): int;
};

Dbfs: module
{
	init:	fn(ctxt: ref Draw->Context, nil: list of string);
};

Qdir, Qnew, Qdata, Qindex, Qstats: con iota;

stderr: ref Sys->FD;
database: ref Database;
context: ref Draw->Context;
user: string;
Eremoved: con "file removed";
Egreg: con "thermal problems";
Elocked: con "open/create -- file is locked";

usage()
{
	sys->fprint(stderr, "Usage: dbfs [-abcelrxD][-u cmd] file mountpoint\n");
	raise "fail:usage";
}

nomod(s: string)
{
	sys->fprint(stderr, "dbfs: can't load %s: %r\n", s);
	raise "fail:load";
}

init(ctxt: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	stderr = sys->fildes(2);
	context = ctxt;
	sys->pctl(Sys->FORKFD|Sys->NEWPGRP, nil);
	styx = load Styx Styx->PATH;
	if(styx == nil)
		nomod(Styx->PATH);
	styx->init();
	styxservers = load Styxservers Styxservers->PATH;
	if(styxservers == nil)
		nomod(Styxservers->PATH);
	styxservers->init(styx);
	str = load String String->PATH;
	if(str == nil)
		nomod(String->PATH);
	bufio = load Bufio Bufio->PATH;
	if(bufio == nil)
		nomod(Bufio->PATH);

	arg := load Arg Arg->PATH;
	if(arg == nil)
		nomod(Arg->PATH);
	arg->init(args);
	flags := Sys->MREPL;
	copt := 0;
	empty := 0;
	locking := 0;
	stats := 0;
	indexing := 0;
	updcmd := "";
	while((o := arg->opt()) != 0)
		case o {
		'a' =>	flags = Sys->MAFTER;
		'b' =>	flags = Sys->MBEFORE;
		'r' =>		flags = Sys->MREPL;
		'c' =>	copt = 1;
		'e' =>	empty = 1;
		'l' =>		locking = 1;
		'u' =>	updcmd = arg->arg();
				if(updcmd == nil)
					usage();
		'x' =>	indexing = 1;
				stats = 1;
		'D' =>	styxservers->traceset(1);
		* =>		usage();
		}
	args = arg->argv();
	arg = nil;

	if(len args != 2)
		usage();
	if(copt)
		flags |= Sys->MCREATE;
	file := hd args;
	args = tl args;
	mountpt := hd args;

	if(updcmd != nil){
		sh = load Sh Sh->PATH;
		if(sh == nil)
			nomod(Sh->PATH);
	}

	df := bufio->open(file, Sys->ORDWR);
	if(df == nil && empty){
		(rc, d) := sys->stat(file);
		if(rc < 0)
			df = bufio->create(file, Sys->ORDWR, 8r600);
	}
	if(df == nil){
		sys->fprint(stderr, "dbfs: can't open %s: %r\n", file);
		raise "fail:cannot open file";
	}
	(db, err) := Database.build(df, locking, indexing, stats, updcmd);
	if(db == nil){
		sys->fprint(stderr, "dbfs: can't read %s: %s\n", file, err);
		raise "fail:cannot read db";
	}
	database = db;

	sys->pctl(Sys->FORKFD, nil);

	user = rf("/dev/user");
	if(user == nil)
		user = "inferno";

	fds := array[2] of ref Sys->FD;
	if(sys->pipe(fds) < 0){
		sys->fprint(stderr, "dbfs: can't create pipe: %r\n");
		raise "fail:pipe";
	}

	navops := chan of ref Navop;
	spawn navigator(navops);

	(tchan, srv) := Styxserver.new(fds[0], Navigator.new(navops), big Qdir);
	fds[0] = nil;

	pidc := chan of int;
	spawn serveloop(tchan, srv, pidc, navops);
	<-pidc;

	if(sys->mount(fds[1], nil, mountpt, flags, nil) < 0) {
		sys->fprint(stderr, "dbfs: mount failed: %r\n");
		raise "fail:bad mount";
	}
}

rf(f: string): string
{
	fd := sys->open(f, Sys->OREAD);
	if(fd == nil)
		return nil;
	b := array[Sys->NAMEMAX] of byte;
	n := sys->read(fd, b, len b);
	if(n < 0)
		return nil;
	return string b[0:n];
}

serveloop(tchan: chan of ref Tmsg, srv: ref Styxserver, pidc: chan of int, navops: chan of ref Navop)
{
	pidc <-= sys->pctl(Sys->FORKNS|Sys->NEWFD, stderr.fd::1::2::database.file.fd.fd::srv.fd.fd::nil);
#	stderr = sys->fildes(stderr.fd);
	database.file.fd = sys->fildes(database.file.fd.fd);
Serve:
	while((gm := <-tchan) != nil){
		pick m := gm {
		Readerror =>
			sys->fprint(stderr, "dbfs: fatal read error: %s\n", m.error);
			break Serve;
		Open =>
			c := srv.getfid(m.fid);
			open(srv, m);
		Read =>
			(c, err) := srv.canread(m);
			if(c == nil) {
				srv.reply(ref Rmsg.Error(m.tag, err));
				break;
			}
			if(c.qtype & Sys->QTDIR){
				srv.read(m);
				break;
			}
			case TYPE(c.path) {
			Qindex =>
				if(database.index < 0) {
					srv.reply(ref Rmsg.Error(m.tag, Eperm));
					break;
				}
				if (m.offset > big 0) {
					srv.reply(ref Rmsg.Read(m.tag, nil));
					break;
				}
				reply := array of byte string ++database.index;
				if(m.count < len reply)
					reply = reply[:m.count];
				srv.reply(ref Rmsg.Read(m.tag, reply));
			Qstats =>
				if (m.offset > big 0) {
					srv.reply(ref Rmsg.Read(m.tag, nil));
					break;
				}
				reply := array of byte sys->sprint("%d %d %d %d", database.s_reads, database.s_writes,
												database.s_creates, database.s_removes);
				if(m.count < len reply) reply = reply[:m.count];
				srv.reply(ref Rmsg.Read(m.tag, reply));
			Qdata =>
				recno := id2recno(FILENO(c.path));
				if(recno == -1)
					srv.reply(ref Rmsg.Error(m.tag, Eremoved));
				else
					srv.reply(styxservers->readbytes(m, database.read(recno)));
			* =>
				srv.reply(ref Rmsg.Error(m.tag, Egreg));
			}
		Write =>
			(c, err) := srv.canwrite(m);
			if(c == nil){
				srv.reply(ref Rmsg.Error(m.tag, err));
				break;
			}
			if(!database.ownlock(c)) {
				# shouldn't happen: open checks
				srv.reply(ref Rmsg.Error(m.tag, Elocked));
				break;
			}
			case TYPE(c.path) {
			Qindex =>
				if(database.index >= 0) {
					srv.reply(ref Rmsg.Error(m.tag, Eperm));
					break;
				}
				database.index = int string m.data;
				srv.reply(ref Rmsg.Write(m.tag, len m.data));
			Qdata =>
				recno := id2recno(FILENO(c.path));
				if(recno == -1)
					srv.reply(ref Rmsg.Error(m.tag, "phase error"));
				else {
					changed := 1;
					if(database.updcmd != nil){
						oldrec := database.read(recno);
						changed = !eqbytes(m.data, oldrec);
					}
					if(changed && database.write(recno, m.data) == -1){
						srv.reply(ref Rmsg.Error(m.tag, sys->sprint("%r")));
						break;
					}
					if(changed)
						database.updated();	# run the command before reply
					srv.reply(ref Rmsg.Write(m.tag, len m.data));
				}
			* =>
				srv.reply(ref Rmsg.Error(m.tag, Eperm));
			}
		Clunk =>
			c := srv.getfid(m.fid);
			if(c != nil)
				database.unlock(c);
			srv.clunk(m);
		Remove =>
			c := srv.getfid(m.fid);
			database.unlock(c);
			if(c == nil || c.qtype & Sys->QTDIR || TYPE(c.path) != Qdata){
				# let it diagnose all the errors
				srv.remove(m);
				break;
			}
			recno := id2recno(FILENO(c.path));
			if(recno == -1)
				srv.reply(ref Rmsg.Error(m.tag, "phase error"));
			else {
				database.remove(recno);
				database.updated();
				srv.reply(ref Rmsg.Remove(m.tag));
			}
			srv.delfid(c);
		* =>
			srv.default(gm);
		}
	}
	navops <-= nil;		# shut down navigator
}

eqbytes(a, b: array of byte): int
{
	if(len a != len b)
		return 0;
	for(i := 0; i < len a; i++)
		if(a[i] != b[i])
			return 0;
	return 1;
}

id2recno(id: int): int
{
	recs := database.records;
	for(i := 0; i < len recs; i++)
		if(recs[i].datalen >= 0 && recs[i].id == id)
			return i;
	return -1;
}
	
open(srv: ref Styxserver, m: ref Tmsg.Open): ref Fid
{
	(c, mode, d, err) := srv.canopen(m);
	if(c == nil){
		srv.reply(ref Rmsg.Error(m.tag, err));
		return nil;
	}
	if(TYPE(c.path) == Qnew){
		# generate new file
		if(c.uname != user){
			srv.reply(ref Rmsg.Error(m.tag, Eperm));
			return nil;
		}
		r := database.create(array[0] of byte);
		if(r == nil) {
			srv.reply(ref Rmsg.Error(m.tag, "create -- i/o error"));
			return nil;
		}
		(d, nil) = dirgen(QPATH(r.id, Qdata));
	}
	if(m.mode & Sys->OTRUNC) {
		# TO DO
	}
	c.open(mode, d.qid);
	if(database.locking && TYPE(c.path) == Qdata && (m.mode & (Sys->OWRITE|Sys->ORDWR))) {
		if(!database.lock(c)) {
			srv.reply(ref Rmsg.Error(m.tag, Elocked));
			return nil;
		}
	}
	srv.reply(ref Rmsg.Open(m.tag, d.qid, srv.iounit()));
	return c;
}

dirslot(n: int): int
{
	for(i := 0; i < len database.records; i++){
		r := database.records[i];
		if(r != nil && r.datalen >= 0){
			if(n == 0)
				return i;
			n--;
		}
	}
	return -1;
}

dir(qid: Sys->Qid, name: string, length: big, uid: string, perm: int): ref Sys->Dir
{
	d := ref sys->zerodir;
	d.qid = qid;
	if(qid.qtype & Sys->QTDIR)
		perm |= Sys->DMDIR;
	d.mode = perm;
	d.name = name;
	d.uid = uid;
	d.gid = uid;
	d.length = length;
	return d;
}

dirgen(p: big): (ref Sys->Dir, string)
{
	case TYPE(p) {
	Qdir =>
		return (dir(Qid(QPATH(0, Qdir),database.vers,Sys->QTDIR), "/", big 0, user, 8r700), nil);
	Qnew =>
		return (dir(Qid(QPATH(0, Qnew),0,Sys->QTFILE), "new", big 0, user, 8r600), nil);
	Qindex =>
		return (dir(Qid(QPATH(0, Qindex),0,Sys->QTFILE), "index", big 0, user, 8r600), nil);
	Qstats =>
		return (dir(Qid(QPATH(0, Qstats),0,Sys->QTFILE), "stats", big 0, user, 8r400), nil);
	* =>
		n := id2recno(FILENO(p));
		if(n < 0 || n >= len database.records)
			return (nil, nil);
		r := database.records[n];
		if(r == nil || r.datalen < 0)
			return (nil, Enotfound);
		l := r.datalen;
		if(l < 0)
			l = 0;
		return (dir(r.qid(), sys->sprint("%d", r.id), big l, user, 8r600), nil);
	}
}

navigator(navops: chan of ref Navop)
{
	while((m := <-navops) != nil){
		pick n := m {
		Stat =>
			n.reply <-= dirgen(n.path);
		Walk =>
			if(int n.path != Qdir){
				n.reply <-= (nil, "not a directory");
				break;
			}
			case n.name {
			".." =>
				;	# nop
			"new" =>
				n.path = QPATH(0, Qnew);
			"stats" =>
				if(!database.indexing){
					n.reply <-= (nil, Enotfound);
					continue;
				}
				n.path = QPATH(0, Qstats);
			"index" =>
				if(!database.indexing){
					n.reply <-= (nil, Enotfound);
					continue;
				}
				n.path = QPATH(0, Qindex);
			* =>
				if(len n.name < 1 || !(n.name[0]>='0' && n.name[0]<='9')){	# weak test for now
					n.reply <-= (nil, Enotfound);
					continue;
				}
				n.path = QPATH(int n.name, Qdata);
			}
			n.reply <-= dirgen(n.path);
		Readdir =>
			if(int m.path != Qdir){
				n.reply <-= (nil, "not a directory");
				break;
			}
			o := 1;	# Qnew;
			stats := -1;
			indexing := -1;
			if(database.indexing)
				indexing = o++;
			if(database.stats)
				stats = o++;
		    Dread:
			for(i := n.offset; --n.count >= 0; i++){
				case i {
				0 =>
					n.reply <-= dirgen(QPATH(0,Qnew));
				* =>
					if(i == indexing)
						n.reply <-= dirgen(QPATH(0, Qindex));
					if(i == stats)
						n.reply <-= dirgen(QPATH(0, Qstats));
					j := dirslot(i-o);	# n² but fine if the file will be small
					if(j < 0)
						break Dread;
					r := database.records[j];
					n.reply <-= dirgen(QPATH(r.id,Qdata));
				}
			}
			n.reply <-= (nil, nil);
		}
	}
}

QPATH(w, q: int): big
{
	return big ((w<<8)|q);
}

TYPE(path: big): int
{
	return int path & 16rFF;
}

FILENO(path: big): int
{
	return (int path >> 8) & 16rFFFFFF;
}

Database.build(f: ref Iobuf, locking, indexing, stats: int, updcmd: string): (ref Database, string)
{
	rl: list of ref Record;
	offset := 0;
	maxid := 0;
	for(;;) {
		d := array[HEADLEN] of byte;
		n := f.read(d, HEADLEN);
		if(n < HEADLEN)
			break;
		orig := s := string d;
		if(len s != HEADLEN)
			return (nil, "found bad header");
		r := ref Record;
		r.vers = 0;
		(r.count, s) = str->toint(s, 10);
		(r.datalen, s) = str->toint(s, 10);
		if(s != "\n")
			return (nil, sys->sprint("found bad header '%s'\n", orig));
		r.offset = offset + HEADLEN;
		offset += r.count + HEADLEN;
		f.seek(big offset, Bufio->SEEKSTART);
		r.id = maxid++;
		rl = r :: rl;
	}
	db := ref Database(f, array[maxid] of ref Record, maxid, locking, nil, indexing, stats, -1, 0, 0, 0, 0, updcmd, 0);
	for(i := len db.records - 1; i >= 0; i--) {
		db.records[i] = hd rl;
		rl = tl rl;
	}
	return (db, nil);
}

Database.write(db: self ref Database, recno: int, data: array of byte): int
{
	db.s_writes++;
	r := db.records[recno];
	r.vers++;
	if(len data <= r.count) {
		if(r.count - len data >= HEADLEN + MINSIZE)
			splitrec(db, recno, len data);
		writerec(db, recno, data);
		db.file.flush();
	} else {
		freerec(db, recno);
		n := allocrec(db, len data);
		if(n == -1)
			return -1;		# BUG: we lose the original data in this case.
		db.records[n].id = r.id;
		db.write(n, data);
	}
	return 0;
}

Database.create(db: self ref Database, data: array of byte): ref Record
{
	db.s_creates++;
	db.vers++;
	n := allocrec(db, len data);
	if(n < 0)
		return nil;
	if(db.write(n, data) < 0){
		freerec(db, n);
		return nil;
	}
	r := db.records[n];
	r.id = db.maxid++;
	return r;
}

Database.read(db: self ref Database, recno: int): array of byte
{
	db.s_reads++;
	r := db.records[recno];
	if(r.datalen <= 0)
		return nil;
	db.file.seek(big r.offset, Bufio->SEEKSTART);
	d := array[r.datalen] of byte;
	n := db.file.read(d, r.datalen);
	if(n != r.datalen) {
		sys->fprint(stderr, "dbfs: only read %d bytes (expected %d)\n", n, r.datalen);
		return nil;
	}
	return d;
}

Database.remove(db: self ref Database, recno: int)
{
	db.s_removes++;
	db.vers++;
	freerec(db, recno);
	db.file.flush();
}

Database.updated(db: self ref Database)
{
	if(db.updcmd != nil)
		sh->system(context, db.updcmd);
}

# Locking - try to lock a record

Database.lock(db: self ref Database, c: ref Styxservers->Fid): int
{
	if(TYPE(c.path) != Qdata || !db.locking)
		return 1;
	for(ll := db.locklist; ll != nil; ll = tl ll) {
		lock := hd ll;
		if(lock.qpath == c.path)
			return lock.fid == c.fid;
	}
	db.locklist = (c.path, c.fid) :: db.locklist;
	return 1;
}


# Locking - unlock a record

Database.unlock(db: self ref Database, c: ref Styxservers->Fid)
{
	if(TYPE(c.path) != Qdata || !db.locking)
		return;
	ll := db.locklist;
	db.locklist = nil;
	for(; ll != nil; ll = tl ll){
		lock := hd ll;
		if(lock.qpath == c.path && lock.fid == c.fid){
			# not replaced on list
		}else
			db.locklist = hd ll :: db.locklist;
	}
}


# Locking - check if Fid c has the lock on its record

Database.ownlock(db: self ref Database, c: ref Styxservers->Fid): int
{
	if(TYPE(c.path) != Qdata || !db.locking)
		return 1;
	for(ll := db.locklist; ll != nil; ll = tl ll) {
		lock := hd ll;
		if(lock.qpath == c.path)
			return lock.fid == c.fid;
	}
	return 0;
}

Record.new(offset: int, length: int): ref Record
{
	return ref Record(-1, offset, length, -1, 0);
}

Record.qid(r: self ref Record): Qid
{
	return Qid(QPATH(r.id,Qdata), r.vers, Sys->QTFILE);
}

freerec(db: ref Database, recno: int)
{
	nr := len db.records;
	db.records[recno].datalen = -1;
	for(i := recno; i >= 0; i--)
		if(db.records[i].datalen != -1)
			break;
	f := i + 1;
	nb := 0;
	for(i = f; i < nr; i++) {
		if(db.records[i].datalen != -1)
			break;
		nb += db.records[i].count + HEADLEN;
	}
	db.records[f].count = nb - HEADLEN;
	writeheader(db.file, db.records[f]);
	# could blank out freed entries here if we cared.
	if(i < nr && f < i)
		db.records[f+1:] = db.records[i:];
	db.records = db.records[0:nr - (i - f - 1)];
}

splitrec(db: ref Database, recno: int, pos: int)
{
	a := array[len db.records + 1] of ref Record;
	a[0:] = db.records[0:recno+1];
	if(recno < len db.records - 1)
		a[recno+2:] = db.records[recno+1:];
	db.records = a;
	r := a[recno];
	a[recno+1] = Record.new(r.offset + pos + HEADLEN, r.count - HEADLEN - pos);
	r.count = pos;
	writeheader(db.file, a[recno+1]);
}

writerec(db: ref Database, recno: int, data: array of byte): int
{
	db.records[recno].datalen = len data;
	if(writeheader(db.file, db.records[recno]) == -1)
		return -1;
	if(db.file.write(data, len data) == Bufio->ERROR)
		return -1;
	return 0;
}

writeheader(f: ref Iobuf, r: ref Record): int
{
	f.seek(big r.offset - big HEADLEN, Bufio->SEEKSTART);
	if(f.puts(sys->sprint("%4d %4d\n", r.count, r.datalen)) == Bufio->ERROR) {
		sys->fprint(stderr, "dbfs: error writing header (id %d, offset %d, count %d, datalen %d): %r\n",
					r.id, r.offset, r.count, r.datalen);
		return -1;
	}
	return 0;
}

# finds or creates a record of the requisite size; does not mark it as allocated.
allocrec(db: ref Database, nb: int): int
{
	if(nb < MINSIZE)
		nb = MINSIZE;
	best := -1;
	n := -1;
	for(i := 0; i < len db.records; i++) {
		r := db.records[i];
		if(r.datalen == -1) {
			avail := r.count - nb;
			if(avail >= 0 && (n == -1 || avail < best)) {
				best = avail;
				n = i;
			}
		}
	}
	if(n != -1)
		return n;
	nr := len db.records;
	a := array[nr + 1] of ref Record;
	a[0:] = db.records[0:];
	offset := 0;
	if(nr > 0)
		offset = a[nr-1].offset + a[nr-1].count;
	db.file.seek(big offset, Bufio->SEEKSTART);
	if(db.file.write(array[nb + HEADLEN] of {* => byte(0)}, nb + HEADLEN) == Bufio->ERROR
			|| db.file.flush() == Bufio->ERROR) {
		sys->fprint(stderr, "dbfs: write of new entry failed: %r\n");
		return -1;
	}
	a[nr] = Record.new(offset + HEADLEN, nb);
	db.records = a;
	return nr;
}

now(fd: ref Sys->FD): int
{
	if(fd == nil)
		return 0;
	buf := array[128] of byte;
	sys->seek(fd, big 0, 0);
	n := sys->read(fd, buf, len buf);
	if(n < 0)
		return 0;
	t := (big string buf[0:n]) / big 1000000;
	return int t;
}
