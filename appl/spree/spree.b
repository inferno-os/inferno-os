implement Spree;

include "sys.m";
	sys: Sys;
include "readdir.m";
	readdir: Readdir;
include "styx.m";
	Rmsg, Tmsg: import Styx;
include "styxservers.m";
	styxservers: Styxservers;
	Styxserver, Fid, Eperm, Navigator: import styxservers;
	nametree: Nametree;
include "draw.m";
include "arg.m";
include "sets.m";
	sets: Sets;
	Set, set, A, B, All, None: import sets;
include "spree.m";
	archives: Archives;
	Archive: import archives;

stderr: ref Sys->FD;
myself: Spree;

Debug: con 0;
Update: adt {
	pick {
	Set =>
		o:		ref Object;
		objid:	int;			# member-specific id
		attr:		ref Attribute;
	Transfer =>
		srcid:	int;			# parent object
		from:	Range;		# range within src to transfer
		dstid:	int;			# destination object
		index:	int;			# insertion point
	Create =>
		objid:	int;
		parentid:	int;
		visibility:	Sets->Set;
		objtype:	string;
	Delete =>
		parentid:	int;
		r:		Range;
		objs:		array of int;
	Setvisibility =>
		objid:	int;
		visibility:	Sets->Set;		# set of members that can see it
	Action =>
		s:		string;
		objs:		list of int;
		rest:		string;
	Break =>
		# break in transmission
	}
};

T: type ref Update;
Queue: adt {
	h, t: list of T; 
	put: fn(q: self ref Queue, s: T);
	get: fn(q: self ref Queue): T;
	isempty: fn(q: self ref Queue): int;
	peek: fn(q: self ref Queue): T;
};

Openfid: adt {
	fid:		int;
	uname:	string;
	fileid:	int;
	member:	ref Member;		# nil for non-clique files.
	updateq:	ref Queue;
	readreq:	ref Tmsg.Read;
	hungup:	int;
	# alias:	string;		# could use this to allow a member to play themselves

	new:		fn(fid: ref Fid, file: ref Qfile): ref Openfid;
	find:		fn(fid: int): ref Openfid;
	close:	fn(fid: self ref Openfid);
#	cmd:		fn(fid: self ref Openfid, cmd: string): string;
};

Qfile: adt {
	id:		int;				# index into files array
	owner:	string;
	qid:		Sys->Qid;
	ofids:	list of ref Openfid;		# list of all fids that are holding this open
	needsupdate:	int;			# updates have been added since last updateall

	create:	fn(parent: big, d: Sys->Dir): ref Qfile;
	delete:	fn(f: self ref Qfile);
};

# which updates do we send even though the clique isn't yet started?
alwayssend := array[] of {
	tagof(Update.Set) => 0,
	tagof(Update.Transfer) => 0,
	tagof(Update.Create) => 0,
	tagof(Update.Delete) => 0,
	tagof(Update.Setvisibility) => 0,
	tagof(Update.Action) => 1,
	tagof(Update.Break) => 1,
};

srv:		ref Styxserver;
tree:		ref Nametree->Tree;
cliques:	array of ref Clique;
qfiles:	array of ref Qfile;
fids :=	array[47] of list of ref Openfid;	# hash table
lobby:	ref Clique;
Qroot:	big;
sequence := 0;

fROOT,
fGAME,
fNAME,
fGAMEDIR,
fGAMEDATA: con iota;

GAMEDIR: con "/n/remote";
ENGINES: con "/dis/spree/engines";
ARCHIVEDIR: con "/lib/spreearchive";

badmod(p: string)
{
	sys->fprint(stderr, "spree: cannot load %s: %r\n", p);
	raise "fail:bad module";
}

init(nil: ref Draw->Context, nil: list of string)
{
	sys = load Sys Sys->PATH;
	stderr = sys->fildes(2);
	myself = load Spree "$self";

	styx := load Styx Styx->PATH;
	if (styx == nil)
		badmod(Styx->PATH);
	styx->init();

	styxservers = load Styxservers Styxservers->PATH;
	if (styxservers == nil)
		badmod(Styxservers->PATH);
	styxservers->init(styx);
 
	nametree = load Nametree Nametree->PATH;
	if (nametree == nil)
		badmod(Nametree->PATH);
	nametree->init();

	sets = load Sets Sets->PATH;
	if (sets == nil)
		badmod(Sets->PATH);
	sets->init();

	readdir = load Readdir Readdir->PATH;
	if (readdir == nil)
		badmod(Readdir->PATH);

	archives = load Archives Archives->PATH;
	if (archives == nil)
		badmod(Archives->PATH);
	archives->init(myself);

	initrand();

	navop: chan of ref Styxservers->Navop;
	(tree, navop) = nametree->start();
	tchan: chan of ref Tmsg;
	Qroot = mkqid(fROOT, 0);
	(tchan, srv) = Styxserver.new(sys->fildes(0), Navigator.new(navop), Qroot);
	nametree->tree.create(Qroot, dir(Qroot, ".", 8r555|Sys->DMDIR, "spree"));
	nametree->tree.create(Qroot, dir(mkqid(fNAME, 0), "name", 8r444, "spree"));
	(lobbyid, nil, err) := lobby.new(ref Archive("lobby" :: nil, nil, nil, nil), "spree");
	if (lobbyid == -1) {
		sys->fprint(stderr, "spree: couldn't start lobby: %s\n", err);
		raise "fail:no lobby";
	}
	sys->pctl(Sys->FORKNS, nil);
	for (;;) {
		gm := <-tchan;
		if (gm == nil || tagof(gm) == tagof(Tmsg.Readerror)) {
			if (gm != nil) {
				pick m := gm {
				Readerror =>
					sys->print("spree: read error: %s\n", m.error);
				}
			}
			sys->print("spree: exiting\n");
			exit;
		} else {
			e := handletmsg(gm);
			if (e != nil)
				srv.reply(ref Rmsg.Error(gm.tag, e));
		}
	}
}


dir(qidpath: big, name: string, perm: int, owner: string): Sys->Dir
{
	DM2QT: con 24;
	d := Sys->zerodir;
	d.name = name;
	d.uid = owner;
	d.gid = owner;
	d.qid.path = qidpath;
	d.qid.qtype = (perm >> DM2QT) & 16rff;
	d.mode = perm;
	# d.atime = now;
	# d.mtime = now;
	return d;
}

handletmsg(tmsg: ref Tmsg): string
{
	pick m := tmsg {
	Open =>
		(fid, omode, d, err) := srv.canopen(m);
		if (fid == nil)
			return err;
		if (d.qid.qtype & Sys->QTDIR) {
			srv.default(m);
			return nil;
		}
		case qidkind(d.qid.path) {
		fGAMEDATA =>
			fid.open(m.mode, Sys->Qid(fid.path, fid.qtype, 0));
			srv.reply(ref Rmsg.Open(m.tag, Sys->Qid(fid.path, fid.qtype, 0), 0));
		fGAME =>
			f := qid2file(d.qid.path);
			if (f == nil)
				return "cannot find qid";
			ofid := Openfid.new(fid, f);
			err = openfile(ofid);
			if (err != nil) {
				ofid.close();
				return err;
			}
			fid.open(m.mode, f.qid);
			srv.reply(ref Rmsg.Open(m.tag, Sys->Qid(fid.path, fid.qtype, 0), 0));
		* =>
			srv.default(m);
		}
		updateall();
	Read =>
		(fid, err) := srv.canread(m);
		if (fid == nil)
			return err;
		if (fid.qtype & Sys->QTDIR) {
			srv.default(m);
			return nil;
		}
		case qidkind(fid.path) {
		fGAMEDATA =>
			f := qidindex(fid.path);
			id := f & 16rffff;
			f = (f >> 16) & 16rffff;
			data := cliques[id].mod->readfile(f, m.offset, m.count);
			srv.reply(ref Rmsg.Read(m.tag, data));
		fGAME =>
			ff := Openfid.find(m.fid);
			if (ff.readreq != nil)
				return "duplicate read";
			ff.readreq = m;
			sendupdate(ff);
		fNAME =>
			srv.reply(styxservers->readstr(m, fid.uname));
		* =>
			return "darn rats!";
		}
	Write =>
		(fid, err) := srv.canwrite(m);
		if (fid == nil)
			return err;
		ff := Openfid.find(m.fid);
		err = command(ff, string m.data);
		if (err != nil) {
			updateall();
			return err;
		}
		srv.reply(ref Rmsg.Write(m.tag, len m.data));
		updateall();		# XXX might we need to do this on error too?
	Clunk =>
		fid := srv.clunk(m);
		if (fid != nil) {
			clunked(fid);
			updateall();
		}
	Flush =>
		for (i := 0; i < len qfiles; i++) {
			if (qfiles[i] == nil)
				continue;
			for (ol := qfiles[i].ofids; ol != nil; ol = tl ol) {
				ofid := hd ol;
				if (ofid.readreq != nil && ofid.readreq.tag == m.oldtag)
					ofid.readreq = nil;
			}
		}
		srv.reply(ref Rmsg.Flush(m.tag));
# Removed => clunked too.
	* =>
		srv.default(tmsg);
	}
	return nil;
}

clunked(fid: ref Fid)
{
	if (!fid.isopen || (fid.qtype & Sys->QTDIR))
		return;
	ofid := Openfid.find(fid.fid);
	if (ofid == nil)
		return;
	if (ofid.member != nil)
		memberleaves(ofid.member);
	ofid.close();
	f := qfiles[ofid.fileid];
	# if it's the last close, and clique is hung up, then remove clique from
	# directory hierarchy.
	if (f.ofids == nil && qidkind(f.qid.path) == fGAME) {
		g := cliques[qidindex(f.qid.path)];
		if (g.hungup) {
			stopclique(g);
			nametree->tree.remove(mkqid(fGAMEDIR, g.id));
			f.delete();
			cliques[g.id] = nil;
		}
	}
}

mkqid(kind, i: int): big
{
	return big kind | (big i << 4);
}

qidkind(qid: big): int
{
	return int (qid & big 16rf);
}

qidindex(qid: big): int
{
	return int (qid >> 4);
}

qid2file(qid: big): ref Qfile
{
	for (i := 0; i < len qfiles; i++) {
		f := qfiles[i];
		if (f != nil && f.qid.path == qid)
			return f;
	}
	return nil;
}

Qfile.create(parent: big, d: Sys->Dir): ref Qfile
{
	nametree->tree.create(parent, d);
	for (i := 0; i < len qfiles; i++)
		if (qfiles[i] == nil)
			break;
	if (i == len qfiles)
		qfiles = (array[len qfiles + 1] of ref Qfile)[0:] = qfiles;
	f := qfiles[i] = ref Qfile(i, d.uid, d.qid, nil, 0);
	return f;
}

Qfile.delete(f: self ref Qfile)
{
	nametree->tree.remove(f.qid.path);
	qfiles[f.id] = nil;
}

Openfid.new(fid: ref Fid, file: ref Qfile): ref Openfid
{
	i := fid.fid % len fids;
	ofid := ref Openfid(fid.fid, fid.uname, file.id, nil, ref Queue, nil, 0);
	fids[i] = ofid :: fids[i];
	file.ofids = ofid :: file.ofids;
	return ofid;
}

Openfid.find(fid: int): ref Openfid
{
	for (ol := fids[fid % len fids]; ol != nil; ol = tl ol)
		if ((hd ol).fid == fid)
			return hd ol;
	return nil;
}
	
Openfid.close(ofid: self ref Openfid)
{
	i := ofid.fid % len fids;
	newol: list of ref Openfid;
	for (ol := fids[i]; ol != nil; ol = tl ol)
		if (hd ol != ofid)
			newol = hd ol :: newol;
	fids[i] = newol;
	newol = nil;
	for (ol = qfiles[ofid.fileid].ofids; ol != nil; ol = tl ol)
		if (hd ol != ofid)
			newol = hd ol :: newol;
	qfiles[ofid.fileid].ofids = newol;
}

openfile(ofid: ref Openfid): string
{
	name := ofid.uname;
	f := qfiles[ofid.fileid];
	if (qidkind(f.qid.path) == fGAME) {
		if (cliques[qidindex(f.qid.path)].hungup)
			return "hungup";
		i := 0;
		for (o := f.ofids; o != nil; o = tl o) {
			if ((hd o) != ofid && (hd o).uname == name)
				return "you cannot join a clique twice";
			i++;
		}
		if (i > MAXPLAYERS)
			return "too many members";
	}
	return nil;
}

# process a client's command; return a non-nil string on error.
command(ofid: ref Openfid, cmd: string): string
{
	err: string;
	f := qfiles[ofid.fileid];
	qid := f.qid.path;
	if (ofid.hungup)
		return "hung up";
	if (cmd == nil) {
		ofid.hungup = 1;
		sys->print("hanging up file %s for user %s, fid %d\n", nametree->tree.getpath(f.qid.path), ofid.uname, ofid.fid);
		return nil;
	}
	case qidkind(qid) {
	fGAME =>
		clique := cliques[qidindex(qid)];
		if (ofid.member == nil)
			err = newmember(clique, ofid, cmd);
		else
			err = cliquerequest(clique, ref Rq.Command(ofid.member, cmd));
	* =>
		err = "invalid command " + string qid;		# XXX dud error message
	}
	return err;
}

Clique.notify(src: self ref Clique, dstid: int, cmd: string)
{
	if (cmd == nil)
		return;		# don't allow faking of clique exit.
	if (dstid < 0 || dstid >= len cliques) {
		if (dstid != -1)
			sys->fprint(stderr, "%d cannot notify invalid %d: '%s'\n", src.id, dstid, cmd);
		return;
	}
	dst := cliques[dstid];
	if (dst.parentid != src.id && dstid != src.parentid) {
		sys->fprint(stderr, "%d cannot notify %d: '%s'\n", src.id, dstid, cmd);
		return;
	}
	src.notes = (src.id, dstid, cmd) :: src.notes;
}

# add a new member to a clique.
# it should already have been checked that the member's name
# isn't a duplicate of another in the same clique.
newmember(clique: ref Clique, ofid: ref Openfid, cmd: string): string
{
	name := ofid.uname;

	# check if member was suspended, and give them their old id back
	# if so, otherwise find first free id.
	for (s := clique.suspended; s != nil; s = tl s)
		if ((hd s).name == name)
			break;
	id: int;
	suspended := 0;
	member: ref Member;
	if (s != nil) {
		member = hd s;
		# remove from suspended list
		q := tl s;
		for (t := clique.suspended; t != s; t = tl t)
			q = hd t :: q;
		clique.suspended = q;
		suspended = 1;
		member.suspended = 0;
	} else {
		for (id = 0; clique.memberids.holds(id); id++)
			;
		member = ref Member(id, clique.id, nil, nil, nil, name, 0, 0);
		clique.memberids = clique.memberids.add(member.id);
	}

	q := ofid.updateq;
	ofid.member = member;

	started := clique.started;
	err := cliquerequest(clique, ref Rq.Join(member, cmd, suspended));
	if (err != nil) {
		member.del(0);
		if (suspended) {
			member.suspended = 1;
			clique.suspended = member :: clique.suspended;
		}
		return err;
	}
	if (started) {
		qrecreateobject(q, member, clique.objects[0], nil);
		qfiles[ofid.fileid].needsupdate = 1;
	}
	member.updating = 1;
	return nil;
}

Clique.start(clique: self ref Clique)
{
	if (clique.started)
		return;

	for (ol := qfiles[clique.fileid].ofids; ol != nil; ol = tl ol)
		if ((hd ol).member != nil)
			qrecreateobject((hd ol).updateq, (hd ol).member, clique.objects[0], nil);
	clique.started = 1;
}

Blankclique: Clique;
maxcliqueid := 0;
Clique.new(parent: self ref Clique, archive: ref Archive, owner: string): (int, string, string)
{
	for (id := 0; id < len cliques; id++)
		if (cliques[id] == nil)
			break;
	if (id == len cliques)
		cliques = (array[len cliques + 1] of ref Clique)[0:] = cliques;

	mod := load Engine ENGINES +"/" + hd archive.argv + ".dis";
	if (mod == nil)
		return (-1, nil, sys->sprint("cannot load engine: %r"));

	dirq := mkqid(fGAMEDIR, id);
	fname := string maxcliqueid++;
	e := nametree->tree.create(Qroot, dir(dirq, fname, 8r555|Sys->DMDIR, owner));
	if (e != nil)
		return (-1, nil, e);
	f := Qfile.create(dirq, dir(mkqid(fGAME, id), "ctl", 8r666, owner));
	objs: array of ref Object;
	if (archive.objects != nil) {
		objs = archive.objects;
		for (i := 0; i < len objs; i++)
			objs[i].cliqueid = id;
	} else
		objs = array[] of {ref Object(0, Attributes.new(), All, -1, nil, id, nil)};

	memberids := None;
	suspended: list of ref Member;
	for (i := 0; i < len archive.members; i++) {
		suspended = ref Member(i, id, nil, nil, nil, archive.members[i], 0, 1) :: suspended;
		memberids = memberids.add(i);
	}

	archive = ref *archive;
	archive.objects = nil;

	g := cliques[id] = ref Clique(
		id,			# id
		f.id,			# fileid
		fname,		# fname
		objs,			# objects
		archive,		# archive
		nil,			# freelist
		mod,		# mod
		memberids,		# memberids
		suspended,
		chan of ref Rq,	# request
		chan of string,	# reply
		0,			# hungup
		0,			# started
		-1,			# parentid
		nil			# notes
	);
	if (parent != nil) {
		g.parentid = parent.id;
		g.notes = parent.notes;
	}
	spawn cliqueproc(g);
	e = cliquerequest1(g, ref Rq.Init);
	if (e != nil) {
		stopclique(g);
		nametree->tree.remove(dirq);
		f.delete();
		cliques[id] = nil;
		return (-1, nil, e);
	}
	# only send notifications if the clique was successfully created, otherwise
	# pretend it never existed.
	if (parent != nil) {
		parent.notes = g.notes;
		g.notes = nil;
	}
	return (g.id, fname, nil);
}

# as a special case, if parent is nil, we use the root object.
Clique.newobject(clique: self ref Clique, parent: ref Object, visibility: Set, objtype: string): ref Object
{
	if (clique.freelist == nil)
		(clique.objects, clique.freelist) =
			makespace(clique.objects, clique.freelist);
	id := hd clique.freelist;
	clique.freelist = tl clique.freelist;

	if (parent == nil)
		parent = clique.objects[0];
	obj := ref Object(id, Attributes.new(), visibility, parent.id, nil, clique.id, objtype);

	n := len parent.children;
	newchildren := array[n + 1] of ref Object;
	newchildren[0:] = parent.children;
	newchildren[n] = obj;
	parent.children = newchildren;
	clique.objects[id] = obj;
	applycliqueupdate(clique, ref Update.Create(id, parent.id, visibility, objtype), All);
	if (Debug)
		sys->print("new %d, parent %d, visibility %s\n", obj.id, parent.id, visibility.str());
	return obj;
}

Clique.hangup(clique: self ref Clique)
{
	if (clique.hungup)
		return;
sys->print("clique.hangup(%s)\n", clique.fname);
	f := qfiles[clique.fileid];
	for (ofids := f.ofids; ofids != nil; ofids = tl ofids)
		(hd ofids).hungup = 1;
	f.needsupdate = 1;
	clique.hungup = 1;
	if (clique.parentid != -1) {
		clique.notes = (clique.id, clique.parentid, nil) :: clique.notes;
		clique.parentid = -1;
	}
	# orphan children
	# XXX could be more efficient for childless cliques by keeping child count
	for(i := 0; i < len cliques; i++)
		if (cliques[i] != nil && cliques[i].parentid == clique.id)
			cliques[i].parentid = -1;
}

stopclique(clique: ref Clique)
{
	clique.hangup();
	if (clique.request != nil)
		clique.request <-= nil;
}

Clique.breakmsg(clique: self ref Clique, whoto: Set)
{	
	applycliqueupdate(clique, ref Update.Break, whoto);
}

Clique.action(clique: self ref Clique, cmd: string,
			objs: list of int, rest: string, whoto: Set)
{
	applycliqueupdate(clique, ref Update.Action(cmd, objs, rest), whoto);
}

Clique.member(clique: self ref Clique, id: int): ref Member
{
	for (ol := qfiles[clique.fileid].ofids; ol != nil; ol = tl ol)
		if ((hd ol).member != nil && (hd ol).member.id == id)
			return (hd ol).member;
	for (s := clique.suspended; s != nil; s = tl s)
		if ((hd s).id == id)
			return hd s;
	return nil;
}

Clique.membernamed(clique: self ref Clique, name: string): ref Member
{
	for (ol := qfiles[clique.fileid].ofids; ol != nil; ol = tl ol)
		if ((hd ol).uname == name)
			return (hd ol).member;
	for (s := clique.suspended; s != nil; s = tl s)
		if ((hd s).name == name)
			return hd s;
	return nil;
}

Clique.owner(clique: self ref Clique): string
{
	return qfiles[clique.fileid].owner;
}

Clique.fcreate(clique: self ref Clique, f: int, parent: int, d: Sys->Dir): string
{
	pq: big;
	if (parent == -1)
		pq = mkqid(fGAMEDIR, clique.id);
	else
		pq = mkqid(fGAMEDATA, clique.id | (parent<<16));
	d.qid.path = mkqid(fGAMEDATA, clique.id | (f<<16));
	d.mode &= ~8r222;
	return nametree->tree.create(pq, d);
}

Clique.fremove(clique: self ref Clique, f: int): string
{
	return nametree->tree.remove(mkqid(fGAMEDATA, clique.id | (f<<16)));
}

# debugging...
Clique.show(nil: self ref Clique, nil: ref Member)
{
#	sys->print("**************** all objects:\n");
#	showobject(clique, clique.objects[0], p, 0, ~0);
#	if (p == nil) {
#		f := qfiles[clique.fileid];
#		for (ol := f.ofids; ol != nil; ol = tl ol) {
#			p = (hd ol).member;
#			if (p == nil) {
#				sys->print("lurker (name '%s')\n",
#					(hd ol).uname);
#				continue;
#			}
#			sys->print("member %d, '%s': ext->obj ", p.id, p.name);
#			for (j := 0; j < len p.ext2obj; j++)
#				if (p.ext2obj[j] != nil)
#					sys->print("%d->%d[%d] ", j, p.ext2obj[j].id, p.ext(p.ext2obj[j].id));
#			sys->print("\n");
#		}
#	}
}

cliquerequest(clique: ref Clique, rq: ref Rq): string
{
	e := cliquerequest1(clique, rq);
	sendnotifications(clique);
	return e;
}

cliquerequest1(clique: ref Clique, rq: ref Rq): string
{
	if (clique.request == nil)
		return "clique has exited";
	clique.request <-= rq;
	err := <-clique.reply;
	if (clique.hungup && clique.request != nil) {
		clique.request <-= nil;
		clique.request = nil;
	}
	return err;
}

sendnotifications(clique: ref Clique)
{
	notes, pending: list of (int, int, string);
	(pending, clique.notes) = (clique.notes, nil);
	n := 0;
	while (pending != nil) {
		for (notes = nil; pending != nil; pending = tl pending)
			notes = hd pending :: notes;
		for (; notes != nil; notes = tl notes) {
			(srcid, dstid, cmd) := hd notes;
			dst := cliques[dstid];
			if (!dst.hungup) {
				dst.notes = pending;
				cliquerequest1(dst, ref Rq.Notify(srcid, cmd));
				(pending, dst.notes) = (dst.notes, nil);
			}
		}
		if (n++ > 50)
			panic("probable loop in clique notification");	# XXX probably shouldn't panic, but useful for debugging
	}
}

cliqueproc(clique: ref Clique)
{
	wfd := sys->open("/prog/" + string sys->pctl(0, nil) + "/wait", Sys->OREAD);
	spawn cliqueproc1(clique);
	buf := array[Sys->ATOMICIO] of byte;
	n := sys->read(wfd, buf, len buf);
	sys->print("spree: clique '%s' exited: %s\n", clique.fname, string buf[0:n]);
	clique.hangup();
	clique.request = nil;
	clique.reply <-= "clique exited";
}

cliqueproc1(clique: ref Clique)
{
	for (;;) {
		rq := <-clique.request;
		if (rq == nil)
			break;
		reply := "";
		pick r := rq {
		Init =>
			reply = clique.mod->init(myself, clique, clique.archive.argv);
		Join =>
			reply = clique.mod->join(r.member, r.cmd, r.suspended);
		Command =>
			reply = clique.mod->command(r.member, r.cmd);
		Leave =>
			if (clique.mod->leave(r.member) == 0)
				reply = "suspended";
		Notify =>
			clique.mod->notify(r.srcid, r.cmd);
		* =>
			panic("unknown engine request, tag " + string tagof(rq));
		}
		clique.reply <-= reply;
	}
	sys->print("spree: clique '%s' exiting\n", clique.fname);
}

Member.ext(member: self ref Member, id: int): int
{
	obj2ext := member.obj2ext;
	if (id >= len obj2ext || id < 0)
		return -1;
	return obj2ext[id];
}

Member.obj(member: self ref Member, ext: int): ref Object
{
	if (ext < 0 || ext >= len member.ext2obj)
		return nil;
	return member.ext2obj[ext];
}

# allocate an object in a member's map.
memberaddobject(p: ref Member, o: ref Object)
{
	if (p.freelist == nil)
		(p.ext2obj, p.freelist) = makespace(p.ext2obj, p.freelist);
	ext := hd p.freelist;
	p.freelist = tl p.freelist;

	if (o.id >= len p.obj2ext) {
		oldmap := p.obj2ext;
		newmap := array[o.id + 10] of int;
		newmap[0:] = oldmap;
		for (i := len oldmap; i < len newmap; i++)
			newmap[i] = -1;
		p.obj2ext = newmap;
	}
	p.obj2ext[o.id] = ext;
	p.ext2obj[ext] = o;
	if (Debug)
		sys->print("addobject member %d, internal %d, external %d\n", p.id, o.id, ext);
}

# delete an object from a member's map.
memberdelobject(member: ref Member, id: int)
{
	if (id >= len member.obj2ext) {
		sys->fprint(stderr, "spree: bad delobject (member %d, id %d, len obj2ext %d)\n",
				member.id, id, len member.obj2ext);
		return;
	}
	ext := member.obj2ext[id];
	member.ext2obj[ext] = nil;
	member.obj2ext[id] = -1;
	member.freelist = ext :: member.freelist;
	if (Debug)
		sys->print("delobject member %d, internal %d, external %d\n", member.id, id, ext);
}

memberleaves(member: ref Member)
{
	clique := cliques[member.cliqueid];
	sys->print("member %d leaving clique %d\n", member.id, member.cliqueid);

	suspend := 0;
	if (!clique.hungup)
		suspend = cliquerequest(clique, ref Rq.Leave(member)) != nil;
	member.del(suspend);
}

resetvisibilities(o: ref Object, id: int)
{
	o.visibility = setreset(o.visibility, id);
	a := o.attrs.a;
	for (i := 0; i < len a; i++) {
		for (al := a[i]; al != nil; al = tl al) {
			(hd al).visibility = setreset((hd al).visibility, id);
			(hd al).needupdate = setreset((hd al).needupdate, id);
		}
	}
	for (i = 0; i < len o.children; i++)
		resetvisibilities(o.children[i], id);
}

# remove a member from their clique.
# the client is still there, but won't get any clique updates.
Member.del(member: self ref Member, suspend: int)
{
	clique := cliques[member.cliqueid];
	if (!member.suspended) {
		for (ofids := qfiles[clique.fileid].ofids; ofids != nil; ofids = tl ofids)
			if ((hd ofids).member == member) {
				(hd ofids).member = nil;
				(hd ofids).hungup = 1;
				# XXX purge update queue?
			}
		# go through all clique objects and attributes, resetting
		# permissions for member id to their default values.
		if (suspend) {
			member.obj2ext = nil;
			member.ext2obj = nil;
			member.freelist = nil;
			member.updating = 0;
			member.suspended = 1;
			clique.suspended = member :: clique.suspended;
		}
	} else if (!suspend) {
		ns: list of ref Member;
		for (s := clique.suspended; s != nil; s = tl s)
			if (hd s != member)
				ns = hd s :: ns;
		clique.suspended = ns;
	}
	if (!suspend) {
		resetvisibilities(clique.objects[0], member.id);
		clique.memberids = clique.memberids.del(member.id);
	}
}

Clique.members(clique: self ref Clique): list of ref Member
{
	pl := clique.suspended;
	for (ofids := qfiles[clique.fileid].ofids; ofids != nil; ofids = tl ofids)
		if ((hd ofids).member != nil)
			pl = (hd ofids).member :: pl;
	return pl;
}

Object.delete(o: self ref Object)
{
	clique := cliques[o.cliqueid];
	if (o.parentid != -1) {
		parent := clique.objects[o.parentid];
		siblings := parent.children;
		for (i := 0; i < len siblings; i++)
			if (siblings[i] == o)
				break;
		if (i == len siblings)
			panic("object " + string o.id + " not found in parent");
		parent.deletechildren((i, i+1));
	} else
		sys->fprint(stderr, "spree: cannot delete root object\n");
}

Object.deletechildren(parent: self ref Object, r: Range)
{
	if (len parent.children == 0)
		return;
	clique := cliques[parent.cliqueid];
	n := r.end - r.start;
	objs := array[r.end - r.start] of int;
	children := parent.children;
	for (i := r.start; i < r.end; i++) {
		o := children[i];
		objs[i - r.start] = o.id;
		o.deletechildren((0, len o.children));
		clique.objects[o.id] = nil;
		clique.freelist = o.id :: clique.freelist;
		o.id = -1;
		o.parentid = -1;
	}
	children[r.start:] = children[r.end:];
	for (i = len children - n; i < len children; i++)
		children[i] = nil;
	if (n < len children)
		parent.children = children[0:len children - n];
	else
		parent.children = nil;

	if (Debug) {
		sys->print("+del from %d, range [%d %d], objs: ", parent.id, r.start, r.end);
		for (i = 0; i < len objs; i++)
			sys->print("%d ", objs[i]);
		sys->print("\n");
	}
	applycliqueupdate(clique, ref Update.Delete(parent.id, r, objs), All);
}

# move a range of objects from src and insert them at index in dst.
Object.transfer(src: self ref Object, r: Range, dst: ref Object, index: int)
{
	if (index == -1)
		index = len dst.children;
	if (src == dst && index >= r.start && index <= r.end)
		return;
	n := r.end - r.start;
	objs := src.children[r.start:r.end];
	newchildren := array[len src.children - n] of ref Object;
	newchildren[0:] = src.children[0:r.start];
	newchildren[r.start:] = src.children[r.end:];
	src.children = newchildren;

	if (Debug) {
		sys->print("+transfer from %d[%d,%d] to %d[%d], objs: ",
			src.id, r.start, r.end, dst.id, index);
		for (x := 0; x < len objs; x++)
			sys->print("%d ", objs[x].id);
		sys->print("\n");
	}

	nindex := index;

	# if we've just removed some cards from the destination,
	# then adjust the destination index accordingly.
	if (src == dst && nindex > r.start) {
		if (nindex < r.end)
			nindex = r.start;
		else
			nindex -= n;
	}
	newchildren = array[len dst.children + n] of ref Object;
	newchildren[0:] = dst.children[0:index];
	newchildren[nindex + n:] = dst.children[nindex:];
	newchildren[nindex:] = objs;
	dst.children = newchildren;

	for (i := 0; i < len objs; i++)
		objs[i].parentid = dst.id;

	clique := cliques[src.cliqueid];
	applycliqueupdate(clique,
		ref Update.Transfer(src.id, r, dst.id, index),
		All);
}

# visibility is only set when the attribute is newly created.
Object.setattr(o: self ref Object, name, val: string, visibility: Set)
{
	(changed, attr) := o.attrs.set(name, val, visibility);
	if (changed) {
		attr.needupdate = All;
		applycliqueupdate(cliques[o.cliqueid], ref Update.Set(o, o.id, attr), objvisibility(o));
	}
}

Object.getattr(o: self ref Object, name: string): string
{
	attr := o.attrs.get(name);
	if (attr == nil)
		return nil;
	return attr.val;
}

# set visibility of an object - reveal any uncovered descendents
# if necessary.
Object.setvisibility(o: self ref Object, visibility: Set)
{
	if (o.visibility.eq(visibility))
		return;
	o.visibility = visibility;
	applycliqueupdate(cliques[o.cliqueid], ref Update.Setvisibility(o.id, visibility), objvisibility(o));
}

Object.setattrvisibility(o: self ref Object, name: string, visibility: Set)
{
	attr := o.attrs.get(name);
	if (attr == nil) {
		sys->fprint(stderr, "spree: setattrvisibility, no attribute '%s', id %d\n", name, o.id);
		return;
	}
	if (attr.visibility.eq(visibility))
		return;
	# send updates to anyone that has needs updating,
	# is in the new visibility list, but not in the old one.
	ovisibility := objvisibility(o);
	before := ovisibility.X(A&B, attr.visibility);
	after := ovisibility.X(A&B, visibility);
	attr.visibility = visibility;
	applycliqueupdate(cliques[o.cliqueid], ref Update.Set(o, o.id, attr), before.X(~A&B, after));
}

# an object's visibility is the intersection
# of the visibility of all its parents.
objvisibility(o: ref Object): Set
{
	clique := cliques[o.cliqueid];
	visibility := All;
	for (id := o.parentid; id != -1; id = o.parentid) {
		o = clique.objects[id];
		visibility = visibility.X(A&B, o.visibility);
	}
	return visibility;
}

makespace(objects: array of ref Object,
		freelist: list of int): (array of ref Object, list of int)
{
	if (freelist == nil) {
		na := array[len objects + 10] of ref Object;
		na[0:] = objects;
		for (j := len na - 1; j >= len objects; j--)
			freelist = j :: freelist;
		objects = na;
	}
	return (objects, freelist);
}

updateall()
{
	for (i := 0; i < len qfiles; i++) {
		f := qfiles[i];
		if (f != nil && f.needsupdate) {
			for (ol := f.ofids; ol != nil; ol = tl ol)
				sendupdate(hd ol);
			f.needsupdate = 0;
		}
	}
}

applyupdate(f: ref Qfile, upd: ref Update)
{
	for (ol := f.ofids; ol != nil; ol = tl ol)
		(hd ol).updateq.put(upd);
	f.needsupdate = 1;
}

# send update to members in the clique in the needupdate set.
applycliqueupdate(clique: ref Clique, upd: ref Update, needupdate: Set)
{
	always := alwayssend[tagof(upd)];
	if (needupdate.isempty() || (!clique.started && !always))
		return;
	f := qfiles[clique.fileid];
	for (ol := f.ofids; ol != nil; ol = tl ol) {
		ofid := hd ol;
		member := ofid.member;
		if (member != nil && needupdate.holds(member.id) && (member.updating || always))
			queueupdate(ofid.updateq, member, upd);
	}
	f.needsupdate = 1;
}

# transform an outgoing update according to the visibility
# of the object(s) concerned.
# the update concerned has already occurred.
queueupdate(q: ref Queue, p: ref Member, upd: ref Update)
{
	clique := cliques[p.cliqueid];
	pick u := upd {
	Set =>
		if (p.ext(u.o.id) != -1 && u.attr.needupdate.holds(p.id)) {
			q.put(ref Update.Set(u.o, p.ext(u.o.id), u.attr));
			u.attr.needupdate = u.attr.needupdate.del(p.id);
		} else
			u.attr.needupdate = u.attr.needupdate.add(p.id);

	Transfer =>
		# if moving from an invisible object, create the objects
		# temporarily in the source object, and then transfer from that.
		# if moving to an invisible object, delete the objects.
		# if moving from invisible to invisible, do nothing.
		src := clique.objects[u.srcid];
		dst := clique.objects[u.dstid];
		fromvisible := objvisibility(src).X(A&B, src.visibility).holds(p.id);
		tovisible := objvisibility(dst).X(A&B, dst.visibility).holds(p.id);
		if (fromvisible || tovisible) {
			# N.B. objects are already in destination object at this point.
			(r, index, srcid) := (u.from, u.index, u.srcid);

			# XXX this scheme is all very well when the parent of src
			# or dst is visible, but not when it's not... in that case
			# we should revert to the old scheme of deleting objects in src
			# or recreating them in dst as appropriate.
			if (!tovisible) {
				# transfer objects to destination, then delete them,
				# so client knows where they've gone.
				q.put(ref Update.Transfer(p.ext(srcid), r, p.ext(u.dstid), 0));
				qdelobjects(q, p, dst, (u.index, u.index + r.end - r.start), 0);
				break;
			}
			if (!fromvisible) {
				# create at the end of source object,
				# then transfer into correct place in destination.
				n := r.end - r.start;
				for (i := 0; i < n; i++) {
					o := dst.children[index + i];
					qrecreateobject(q, p, o, src);
				}
				r = (0, n);
			}
			if (p.ext(srcid) == -1 || p.ext(u.dstid) == -1)
				panic("external objects do not exist");
			q.put(ref Update.Transfer(p.ext(srcid), r, p.ext(u.dstid), index));
		}
	Create =>
		dst := clique.objects[u.parentid];
		if (objvisibility(dst).X(A&B, dst.visibility).holds(p.id)) {
			memberaddobject(p, clique.objects[u.objid]);
			q.put(ref Update.Create(p.ext(u.objid), p.ext(u.parentid), u.visibility, u.objtype));
		}
	Delete =>
		# we can only get this update when all the children are
		# leaf nodes.
		o := clique.objects[u.parentid];
		if (objvisibility(o).X(A&B, o.visibility).holds(p.id)) {
			r := u.r;
			extobjs := array[len u.objs] of int;
			for (i := 0; i < len u.objs; i++) {
				extobjs[i] = p.ext(u.objs[i]);
				memberdelobject(p, u.objs[i]);
			}
			q.put(ref Update.Delete(p.ext(o.id), u.r, extobjs));
		}
	Setvisibility =>
		# if the object doesn't exist for this member, don't do anything.
		# else if there are children, check whether they exist, and
		# create or delete them as necessary.
		if (p.ext(u.objid) != -1) {
			o := clique.objects[u.objid];
			if (len o.children > 0) {
				visible := u.visibility.holds(p.id);
				made := p.ext(o.children[0].id) != -1;
				if (!visible && made)
					qdelobjects(q, p, o, (0, len o.children), 0);
				else if (visible && !made)
					for (i := 0; i < len o.children; i++)
						qrecreateobject(q, p, o.children[i], nil);
			}
			q.put(ref Update.Setvisibility(p.ext(u.objid), u.visibility));
		}
	Action =>
		s := u.s;
		for (ol := u.objs; ol != nil; ol = tl ol)
			s += " " + string p.ext(hd ol);
		s += " " + u.rest;
		q.put(ref Update.Action(s, nil, nil));
	* =>
		q.put(upd);
	}
}

# queue deletions for o; we pretend to the client that
# the deletions are at index.
qdelobjects(q: ref Queue, p: ref Member, o: ref Object, r: Range, index: int)
{
	if (r.start >= r.end)
		return;
	children := o.children;
	extobjs := array[r.end - r.start] of int;
	for (i := r.start; i < r.end; i++) {
		c := children[i];
		qdelobjects(q, p, c, (0, len c.children), 0);
		extobjs[i - r.start] = p.ext(c.id);
		memberdelobject(p, c.id);
	}
	q.put(ref Update.Delete(p.ext(o.id), (index, index + (r.end - r.start)), extobjs));
}

# parent visibility now allows o to be seen, so recreate
# it for the member. (if parent is non-nil, pretend we're creating it there)
qrecreateobject(q: ref Queue, p: ref Member, o: ref Object, parent: ref Object)
{
	memberaddobject(p, o);
	parentid := o.parentid;
	if (parent != nil)
		parentid = parent.id;
	q.put(ref Update.Create(p.ext(o.id), p.ext(parentid), o.visibility, o.objtype));
	recreateattrs(q, p, o);
	if (o.visibility.holds(p.id)) {
		a := o.children;
		for (i := 0; i < len a; i++)
			qrecreateobject(q, p, a[i], nil);
	}
}

recreateattrs(q: ref Queue, p: ref Member, o: ref Object)
{
	a := o.attrs.a;
	for (i := 0; i < len a; i++) {
		for (al := a[i]; al != nil; al = tl al) {
			attr := hd al;
			q.put(ref Update.Set(o, p.ext(o.id), attr));
		}
	}
}

CONTINUATION := array[] of {byte '\n', byte '*'};

# send the client as many updates as we can fit in their read request
# (if there are some updates to send and there's an outstanding read request)
sendupdate(ofid: ref Openfid)
{
	clique: ref Clique;
	if (ofid.readreq == nil || (ofid.updateq.isempty() && !ofid.hungup))
		return;
	m := ofid.readreq;
	q := ofid.updateq;
	if (ofid.hungup) {
		srv.reply(ref Rmsg.Read(m.tag, nil));
		q.h = q.t = nil;
		return;
	}
	data := array[m.count] of byte;
	nb := 0;
	plid := -1;
	if (ofid.member != nil) {
		plid = ofid.member.id;
		clique = cliques[ofid.member.cliqueid];
	}
	avail := len data - len CONTINUATION;
Putdata:
	for (; !q.isempty(); q.get()) {
		upd := q.peek();
		pick u := upd {
		Set =>
			if (plid != -1 && !objvisibility(u.o).X(A&B, u.attr.visibility).holds(plid)) {
				u.attr.needupdate = u.attr.needupdate.add(plid);
				continue Putdata;
			}
		Break =>
			if (nb > 0) {
				q.get();
				break Putdata;
			}
			continue Putdata;
		}
		d := array of byte update2s(upd, plid);
		if (len d + nb > avail)
			break;
		data[nb:] = d;
		nb += len d;
	}
	err := "";
	if (nb == 0) {
		if (q.isempty())
			return;
		err = "short read";
	} else if (!q.isempty()) {
		data[nb:] = CONTINUATION;
		nb += len CONTINUATION;
	}
	data = data[0:nb];
			
	if (err != nil)
		srv.reply(ref Rmsg.Error(m.tag, err));
	else
		srv.reply(ref Rmsg.Read(m.tag, data));
	ofid.readreq = nil;
}

# convert an Update adt to a string.
update2s(upd: ref Update, plid: int): string
{
	s: string;
	pick u := upd {
	Create =>
		objtype := u.objtype;
		if (objtype == nil)
			objtype = "nil";
		s = sys->sprint("create %d %d %d %s\n", u.objid, u.parentid, u.visibility.holds(plid) != 0, objtype);
	Transfer =>
		# tx src dst dstindex start end
		if (u.srcid == -1 || u.dstid == -1)
			panic("src or dst object is -1");
		s = sys->sprint("tx %d %d %d %d %d\n",
			u.srcid, u.dstid, u.from.start, u.from.end, u.index);
	Delete =>
		s = sys->sprint("del %d %d %d", u.parentid, u.r.start, u.r.end);
		for (i := 0; i < len u.objs; i++)
			s += " " + string u.objs[i];
		s[len s] = '\n';
	Set =>
		s = sys->sprint("set %d %s %s\n", u.objid, u.attr.name, u.attr.val);
	Setvisibility =>
		s = sys->sprint("vis %d %d\n", u.objid, u.visibility.holds(plid) != 0);
	Action =>
		s = u.s + "\n";
	* =>
		sys->fprint(stderr, "unknown update tag %d\n", tagof(upd));
	}
	return s;
}

Queue.put(q: self ref Queue, s: T)
{
	q.t = s :: q.t;
}

Queue.get(q: self ref Queue): T
{
	s: T;
	if(q.h == nil){
		q.h = revlist(q.t);
		q.t = nil;
	}
	if(q.h != nil){
		s = hd q.h;
		q.h = tl q.h;
	}
	return s;
}

Queue.peek(q: self ref Queue): T
{
	s: T;
	if (q.isempty())
		return s;
	s = q.get();
	q.h = s :: q.h;
	return s;
}

Queue.isempty(q: self ref Queue): int
{
	return q.h == nil && q.t == nil;
}

revlist(ls: list of T) : list of T
{
	rs: list of T;
	for (; ls != nil; ls = tl ls)
		rs = hd ls :: rs;
	return rs;
}

Attributes.new(): ref Attributes
{
	return ref Attributes(array[7] of list of ref Attribute);
}

Attributes.get(attrs: self ref Attributes, name: string): ref Attribute
{
	for (al := attrs.a[strhash(name, len attrs.a)]; al != nil; al = tl al)
		if ((hd al).name == name)
			return hd al;
	return nil;
}

# return (haschanged, attr)
Attributes.set(attrs: self ref Attributes, name, val: string, visibility: Set): (int, ref Attribute)
{
	h := strhash(name, len attrs.a);
	for (al := attrs.a[h]; al != nil; al = tl al) {
		attr := hd al;
		if (attr.name == name) {
			if (attr.val == val)
				return (0, attr);
			attr.val = val;
			return (1, attr);
		}
	}
	attr := ref Attribute(name, val, visibility, All);
	attrs.a[h] = attr :: attrs.a[h];
	return (1, attr);
}

setreset(set: Set, i: int): Set
{
	if (set.msb())
		return set.add(i);
	return set.del(i);
}

# from Aho Hopcroft Ullman
strhash(s: string, n: int): int
{
	h := 0;
	m := len s;
	for(i := 0; i<m; i++){
		h = 65599 * h + s[i];
	}
	return (h & 16r7fffffff) % n;
}

panic(s: string)
{
	cliques[0].show(nil);
	sys->fprint(stderr, "panic: %s\n", s);
	raise "panic";
}

randbits: chan of int;

initrand()
{
	randbits = chan of int;
	spawn randproc();
}

randproc()
{
	fd := sys->open("/dev/notquiterandom", Sys->OREAD);
	if (fd == nil) {
		sys->print("cannot open /dev/random: %r\n");
		exit;
	}
	randbits <-= sys->pctl(0, nil);
	buf := array[1] of byte;
	while ((n := sys->read(fd, buf, len buf)) > 0) {
		b := buf[0];
		for (i := byte 1; i != byte 0; i <<= 1)
			randbits <-= (b & i) != byte 0;
	}
}

rand(n: int): int
{
	x: int;
	for (nbits := 0; (1 << nbits) < n; nbits++)
		x ^= <-randbits << nbits;
	x ^= <-randbits << nbits;
	x &= (1 << nbits) - 1;
	i := 0;
	while (x >= n) {
		x ^= <-randbits << i;
		i = (i + 1) % nbits;
	}
	return x;
}

archivenum := -1;

newarchivename(): string
{
	if (archivenum == -1) {
		(d, nil) := readdir->init(ARCHIVEDIR, Readdir->MTIME|Readdir->COMPACT);
		for (i := 0; i < len d; i++) {
			name := d[i].name;
			if (name != nil && name[0] == 'a') {
				for (j := 1; j < len name; j++)
					if (name[j] < '0' || name[j] > '9')
						break;
				if (j == len name && int name[1:] > archivenum)
					archivenum = int name[1:];
			}
		}
		archivenum++;
	}
	return ARCHIVEDIR + "/a" + string archivenum++;
}

archivenames(): list of string
{
	names: list of string;
	(d, nil) := readdir->init(ARCHIVEDIR, Readdir->MTIME|Readdir->COMPACT);
	for (i := 0; i < len d; i++)
		if (len d[i].name < 4 || d[i].name[len d[i].name - 4:] != ".old")
			names = ARCHIVEDIR + "/" + d[i].name ::  names;
	return names;
}
