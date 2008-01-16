implement Dbfs;

#
# Copyright © 1999 Vita Nuova Limited.  All rights reserved.
# Revisions copyright © 2002 Vita Nuova Holdings Limited.  All rights reserved.
#

include "sys.m";
	sys: Sys;
	Qid: import Sys;

include "draw.m";

include "arg.m";

include "styx.m";
	styx: Styx;
	Tmsg, Rmsg: import styx;

include "styxservers.m";
	styxservers: Styxservers;
	Fid, Styxserver, Navigator, Navop: import styxservers;
	Enotfound, Eperm, Ebadarg: import styxservers;

include "bufio.m";
	bufio: Bufio;
	Iobuf: import bufio;

Record: adt {
	id:		int;		# file number in directory
	x:		int;		# index in file
	dirty:	int;		# modified but not written
	vers:		int;		# version
	data:		array of byte;

	new:		fn(x: array of byte): ref Record;
	print:	fn(r: self ref Record, fd: ref Sys->FD);
	qid:		fn(r: self ref Record): Sys->Qid;
};

Database: adt {
	name:	string;
	file:	ref Iobuf;
	records:	array of ref Record;
	dirty:	int;
	vers:		int;
	nextid:	int;

	findrec:	fn(db: self ref Database, id: int): ref Record;
};

Dbfs: module
{
	init: fn(nil: ref Draw->Context, nil: list of string);
};

Qdir, Qnew, Qdata: con iota;

clockfd: ref Sys->FD;
stderr: ref Sys->FD;
database: ref Database;
user: string;
Eremoved: con "file removed";

usage()
{
	sys->fprint(stderr, "Usage: dbfs [-a|-b|-ac|-bc] [-D] file mountpoint\n");
	raise "fail:usage";
}

nomod(s: string)
{
	sys->fprint(stderr, "dbfs: can't load %s: %r\n", s);
	raise "fail:load";
}

init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	sys->pctl(Sys->FORKFD|Sys->NEWPGRP, nil);
	stderr = sys->fildes(2);
	styx = load Styx Styx->PATH;
	if(styx == nil)
		nomod(Styx->PATH);
	styx->init();
	styxservers = load Styxservers Styxservers->PATH;
	if(styxservers == nil)
		nomod(Styxservers->PATH);
	styxservers->init(styx);
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
	while((o := arg->opt()) != 0)
		case o {
		'a' =>	flags = Sys->MAFTER;
		'b' =>	flags = Sys->MBEFORE;
		'c' =>	copt = 1;
		'e' =>	empty = 1;
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

	df := bufio->open(file, Sys->OREAD);
	if(df == nil && empty){
		(rc, nil) := sys->stat(file);
		if(rc < 0)
			df = bufio->create(file, Sys->OREAD, 8r600);
	}
	if(df == nil){
		sys->fprint(stderr, "dbfs: can't open %s: %r\n", file);
		raise "fail:open";
	}
	(db, err) := dbread(ref Database(file, df, nil, 0, 0, 0));
	if(db == nil){
		sys->fprint(stderr, "dbfs: can't read %s: %s\n", file, err);
		raise "fail:dbread";
	}
	db.file = nil;
#	dbprint(db);
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
		raise "fail:mount";
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

dbread(db: ref Database): (ref Database, string)
{
	db.file.seek(big 0, Sys->SEEKSTART);
	rl: list of ref Record;
	n := 0;
	for(;;){
		(r, err) := getrec(db);
		if(err != nil)
			return (nil, err);		# could press on without it, or make it the `file' contents
		if(r == nil)
			break;
		rl = r :: rl;
		n++;
	}
	db.nextid = n;
	db.records = array[n] of ref Record;
	for(; rl != nil; rl = tl rl){
		r := hd rl;
		n--;
		r.id = n;
		r.x = n;
		db.records[n] = r;
	}
	return (db, nil);
}

#
# a record is (.+\n)*\n
#
getrec(db: ref Database): (ref Record, string)
{
	r := ref Record(-1, -1, 0, 0, nil);
	data := "";
	for(;;){
		s := db.file.gets('\n');
		if(s == nil){
			if(data == nil)
				return (nil, nil);		# BUG: distinguish i/o error from EOF?
			break;
		}
		if(s[len s - 1] != '\n')
#			return (nil, "file missing newline");	# possibly truncated
			s += "\n";
		if(s == "\n")
			break;
		data += s;
	}
	r.data = array of byte data;
	return (r, nil);
}

dbsync(db: ref Database): int
{
	if(db.dirty){
		db.file = bufio->create(db.name, Sys->OWRITE, 8r666);
		if(db.file == nil)
			return -1;
		for(i := 0; i < len db.records; i++){
			r := db.records[i];
			if(r != nil && r.data != nil){
				if(db.file.write(r.data, len r.data) != len r.data)
					return -1;
				db.file.putc('\n');
			}
		}
		if(db.file.flush())
			return -1;
		db.file = nil;
		db.dirty = 0;
	}
	return 0;
}

dbprint(db: ref Database)
{
	stdout := sys->fildes(1);
	for(i := 0; i < len db.records; i++){
		db.records[i].print(stdout);
		sys->print("\n");
	}
}

Database.findrec(db: self ref Database, id: int): ref Record
{
	for(i:=0; i<len db.records; i++)
		if((r := db.records[i]) != nil && r.id == id)
			return r;
	return nil;
}

Record.new(fields: array of byte): ref Record
{
	n := len database.records;
	r := ref Record(n, n, 0, 0, fields);
	a := array[n+1] of ref Record;
	if(n)
		a[0:] = database.records[0:];
	a[n] = r;
	database.records = a;
	database.vers++;
	return r;
}

Record.print(r: self ref Record, fd: ref Sys->FD)
{
	if(r.data != nil)
		sys->write(fd, r.data, len r.data);
}

Record.qid(r: self ref Record): Sys->Qid
{
	return Sys->Qid(QPATH(r.x, Qdata), r.vers, Sys->QTFILE);
}

serveloop(tchan: chan of ref Tmsg, srv: ref Styxserver, pidc: chan of int, navops: chan of ref Navop)
{
	pidc <-= sys->pctl(Sys->FORKNS|Sys->NEWFD, 1::2::srv.fd.fd::nil);
Serve:
	while((gm := <-tchan) != nil){
		pick m := gm {
		Readerror =>
			sys->fprint(stderr, "dbfs: fatal read error: %s\n", m.error);
			break Serve;
		Open =>
			c := srv.getfid(m.fid);
			if(c == nil || TYPE(c.path) != Qnew){
				srv.open(m);		# default action
				break;
			}
			if(c.uname != user) {
				srv.reply(ref Rmsg.Error(m.tag, Eperm));
				break;
			}
			mode := styxservers->openmode(m.mode);
			if(mode < 0) {
				srv.reply(ref Rmsg.Error(m.tag, Ebadarg));
				break;
			}
			# generate new file, change Fid's qid to match
			r := Record.new(array[0] of byte);
			qid := r.qid();
			c.open(mode, qid);
			srv.reply(ref Rmsg.Open(m.tag, qid, srv.iounit()));
		Read =>
			(c, err) := srv.canread(m);
			if(c == nil){
				srv.reply(ref Rmsg.Error(m.tag, err));
				break;
			}
			if(c.qtype & Sys->QTDIR){
				srv.read(m);	# does readdir
				break;
			}
			r := database.records[FILENO(c.path)];
			if(r == nil)
				srv.reply(ref Rmsg.Error(m.tag, Eremoved));
			else
				srv.reply(styxservers->readbytes(m, r.data));
		Write =>
			(c, merr) := srv.canwrite(m);
			if(c == nil){
				srv.reply(ref Rmsg.Error(m.tag, merr));
				break;
			}
			(value, err) := data2rec(m.data);
			if(err != nil){
				srv.reply(ref Rmsg.Error(m.tag, err));
				break;
			}
			fno := FILENO(c.path);
			r := database.records[fno];
			if(r == nil){
				srv.reply(ref Rmsg.Error(m.tag, Eremoved));
				break;
			}
			r.data = value;
			r.vers++;
			database.dirty++;
			if(dbsync(database) == 0)
				srv.reply(ref Rmsg.Write(m.tag, len m.data));
			else
				srv.reply(ref Rmsg.Error(m.tag, sys->sprint("%r")));
		Clunk =>
			# a transaction-oriented dbfs could delay updating the record until clunk
			srv.clunk(m);
		Remove =>
			c := srv.getfid(m.fid);
			if(c == nil || c.qtype & Sys->QTDIR || TYPE(c.path) != Qdata){
				# let it diagnose all the errors
				srv.remove(m);
				break;
			}
			r := database.records[FILENO(c.path)];
			if(r != nil)
				r.data = nil;
			database.dirty++;
			srv.delfid(c);
			if(dbsync(database) == 0)
				srv.reply(ref Rmsg.Remove(m.tag));
			else
				srv.reply(ref Rmsg.Error(m.tag, sys->sprint("%r")));
		Wstat =>
			srv.default(gm);	# TO DO?
		* =>
			srv.default(gm);
		}
	}
	navops <-= nil;		# shut down navigator
}

dirslot(n: int): int
{
	for(i := 0; i < len database.records; i++){
		r := database.records[i];
		if(r != nil && r.data != nil){
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
	* =>
		n := FILENO(p);
		if(n < 0 || n >= len database.records)
			return (nil, nil);
		r := database.records[n];
		if(r == nil || r.data == nil)
			return (nil, Enotfound);
		return (dir(r.qid(), sys->sprint("%d", r.id), big len r.data, user, 8r600), nil);
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
			* =>
				if(len n.name < 1 || !(n.name[0]>='0' && n.name[0]<='9')){	# weak test for now
					n.reply <-= (nil, Enotfound);
					continue;
				}
				r := database.findrec(int n.name);
				if(r == nil){
					n.reply <-= (nil, Enotfound);
					continue;
				}
				n.path = QPATH(r.x, Qdata);
			}
			n.reply <-= dirgen(n.path);
		Readdir =>
			if(int m.path != Qdir){
				n.reply <-= (nil, "not a directory");
				break;
			}
			i := n.offset;
			if(i == 0)
				n.reply <-= dirgen(QPATH(0,Qnew));
			for(; --n.count >= 0 && (j := dirslot(i)) >= 0; i++)
				n.reply <-= dirgen(QPATH(j,Qdata));	# n² but the file will be small
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

FILENO(path: big) : int
{
	return (int path >> 8) & 16rFFFFFF;
}

#
# a record is (.+\n)*, without final empty line
#
data2rec(data: array of byte): (array of byte, string)
{
	s: string;
	for(b := data; len b > 0;){
		(b, s) = getline(b);
		if(s == nil || s[len s - 1] != '\n' || s == "\n")
			return (nil, "partial or malformed record");	# possibly truncated
	}
	return (data, nil);
}

getline(b: array of byte): (array of byte, string)
{
	n := len b;
	for(i := 0; i < n; i++){
		(ch, l, nil) := sys->byte2char(b, i);
		i += l;
		if(l == 0 || ch == '\n')
			break;
	}
	return (b[i:], string b[0:i]);
}
