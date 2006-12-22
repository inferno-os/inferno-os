implement Styxpersist;

#
# Copyright © 2004 Vita Nuova Holdings Limited
#

include "sys.m";
	sys: Sys;
include "draw.m";
include "styx.m";
	styx: Styx;
	Tmsg, Rmsg, NOFID, NOTAG: import styx;
include "rand.m";
	rand: Rand;
include "factotum.m";
	factotum: Factotum;
include "styxpersist.m";

NOTOPEN, DEAD, AUTH, OPEN: con iota;
NTAGHASH: con 32;
MAXBACKOFF: con 30*1000;
Estale: con "unable to reopen file";
Ebadtag: con "bad tag";
Epartial: con "operation possibly not completed";
Etypemismatch: con "tag type mismatch";
Debug: con 0;

Noqid: con Sys->Qid(big 0, 0, 0);
Nprocs: con 1;
Erroronpartial: con 1;

Table: adt[T] {
	items:	array of list of (int, T);
	nilval:	T;

	new: fn(nslots: int, nilval: T): ref Table[T];
	add:	fn(t: self ref Table, id: int, x: T): int;
	del:	fn(t: self ref Table, id: int): int;
	find:	fn(t: self ref Table, id: int): T;
};

Fid: adt {
	fid:		int;
	state:	int;
	omode:	int;
	qid:		Sys->Qid;
	uname:	string;
	aname:	string;
	authed:	int;
	path:		list of string;	# in reverse order.
};

Tag: adt {
	m: ref Tmsg;
	seq:		int;
	dead:	int;
	next: cyclic ref Tag;
};

Root: adt {
	refcount: int;
	attached: chan of int;	# [1]; holds attached status: -1 (can't), 0 (haven't), 1 (attached)
	fid: int;
	qid: Sys->Qid;
	uname: string;
	aname: string;
};

keyspec: string;

tags := array[NTAGHASH] of ref Tag;
fids: ref Table[ref Fid];
ntags := 0;
seqno := 0;

doneversion := 0;
msize := 0;
ver: string;

cfd, sfd: ref Sys->FD;
tmsg: chan of ref Tmsg;		# t-messages received from client
rmsg: chan of ref Rmsg;		# r-messages received from server.
rmsgpid := -1;

token: chan of (int, chan of (ref Fid, ref Root));		# [Nprocs] of (procid, workchan)
procrmsg: array of chan of ref Rmsg;

init(clientfd: ref Sys->FD, usefac: int, kspec: string): (chan of chan of ref Sys->FD, string)
{
	sys = load Sys Sys->PATH;
	styx = load Styx Styx->PATH;
	if(styx == nil)
		return (nil, sys->sprint("cannot load %q: %r", Styx->PATH));
	styx->init();
	rand = load Rand Rand->PATH;
	if (rand == nil)
		return (nil, sys->sprint("cannot load %q: %r", Rand->PATH));
	rand->init(sys->millisec());
	if(usefac){
		factotum = load Factotum Factotum->PATH;
		if(factotum == nil)
			return (nil, sys->sprint("cannot load %q: %r", Rand->PATH));
		factotum->init();
	}

	keyspec = kspec;
	connectc := chan of chan of ref Sys->FD;
	spawn styxpersistproc(clientfd, connectc);
	return (connectc, nil);
}

styxpersistproc(clientfd: ref Sys->FD, connectc: chan of chan of ref Sys->FD)
{
	fids = Table[ref Fid].new(11, nil);
	rmsg = chan of ref Rmsg;
	tmsg = chan of ref Tmsg;
	cfd = clientfd;
	spawn tmsgreader();
	connect(connectc);
	for(;;)alt{
	m := <-tmsg =>
		if(m == nil || tagof(m) == tagof(Tmsg.Readerror))
			quit();
		t := newtag(m);
		if(t == nil){
			sendrmsg(ref Rmsg.Error(m.tag, Ebadtag));
			continue;
		}
		if((rm := handletmsg(t)) != nil){
			sendrmsg(rm);
			gettag(m.tag, 1);
		}else{
			# XXX could be quicker about this as we don't rewrite messages
			sendtmsg(m);
		}
	m := <-rmsg =>
		if(m == nil || tagof(m) == tagof(Tmsg.Readerror)){
			if(Debug) sys->print("**************** reconnect {\n");
			do{
				connect(connectc);
			} while(resurrectfids() == 0);
			resurrecttags();
			if(Debug) sys->print("************** done reconnect }\n");
			continue;
		}

		t := gettag(m.tag, 1);
		if(t == nil){
			log(sys->sprint("unexpected tag %d, %s", m.tag, m.text()));
			continue;
		}
		if((e := handlermsg(m, t.m)) != nil)
			log(e);
		else{
			# XXX could be quicker about this as we don't rewrite messages
			sendrmsg(m);
		}
	}
}

quit()
{
	log("quitting...\n");
	# XXX shutdown properly
	exit;
}

log(s: string)
{
	sys->fprint(sys->fildes(2), "styxpersist: %s\n", s);
}

handletmsg(t: ref Tag): ref Rmsg
{
	fid := NOFID;
	pick m := t.m {
	Flush =>
		if(gettag(m.oldtag, 0) == nil)
			return ref Rmsg.Flush(m.tag);
	 * =>
		fid = tmsgfid(m);
	}
	if(fid != NOFID){
		f := getfid(fid);
		if(f.state == DEAD){
			if(tagof(t.m) == tagof(Tmsg.Clunk)){
				fids.del(f.fid);
				return ref Rmsg.Clunk(t.m.tag);
			}
			return ref Rmsg.Error(t.m.tag, Estale);
		}
	}
	return nil;
}

handlermsg(rm: ref Rmsg, tm: ref Tmsg): string
{
	if(tagof(rm) == tagof(Rmsg.Error) && 
			tagof(tm) != tagof(Tmsg.Remove) &&
			tagof(tm) != tagof(Tmsg.Clunk))
		return nil;
	if(tagof(rm) != tagof(Rmsg.Error) && rm.mtype() != tm.mtype()+1)
		return "type mismatch, got "+rm.text()+", reply to "+tm.text();

	pick m := tm {
	Auth =>
		fid := newfid(m.afid);	# XXX should we be concerned about this failing?
		fid.state = AUTH;
	Attach =>
		fid := newfid(m.fid);
		fid.uname = m.uname;
		fid.aname = m.aname;
		if(m.afid != NOFID)
			fid.authed = 1;
	Walk =>
		fid := getfid(m.fid);
		qids: array of Sys->Qid;
		n := 0;
		pick r := rm {
		Walk =>
			qids = r.qids;
		}
		if(len qids != len m.names)
			return nil;
		if(m.fid != m.newfid){
			newfid := newfid(m.newfid);
			*newfid = *fid;
			newfid.fid = m.newfid;
			fid = newfid;
		}
		for(i := 0; i < len qids; i++){
			if(m.names[i] == ".."){
				if(fid.path != nil)
					fid.path = tl fid.path;
			}else{
				fid.path = m.names[i] :: fid.path;
			}
			fid.qid = qids[i];
		}
	Open =>
		fid := getfid(m.fid);
		fid.state = OPEN;
		fid.omode = m.mode;
		pick r := rm {
		Open =>
			fid.qid = r.qid;
		}
	Create =>
		fid := getfid(m.fid);
		fid.state = OPEN;
		fid.omode = m.mode;
		pick r := rm {
		Create =>
			fid.qid = r.qid;
		}
	Clunk or
	Remove =>
		fids.del(m.fid);
	Wstat =>
		if(m.stat.name != nil){
			fid := getfid(m.fid);
			fid.path = m.stat.name :: tl fid.path;
		}
	}
	return nil;
}

# connect to destination with exponential backoff, setting sfd.
connect(connectc: chan of chan of ref Sys->FD)
{
	reply := chan of ref Sys->FD;
	sfd = nil;
	backoff := 0;
	for(;;){
		connectc <-= reply;
		fd := <-reply;
		if(fd != nil){
			kill(rmsgpid, "kill");
			sfd = fd;
			sync := chan of int;
			spawn rmsgreader(fd, sync);
			rmsgpid = <-sync;
			if(version() != -1)
				return;
			sfd = nil;
		}
		if(backoff == 0)
			backoff = 1000 + rand->rand(500) - 250;
		else if(backoff < MAXBACKOFF)
			backoff = backoff * 3 / 2;
		sys->sleep(backoff);
	}
}

# first time we use the version offered by the client,
# and record it; subsequent times we offer the response
# recorded initially.
version(): int
{
	if(doneversion)
		sendtmsg(ref Tmsg.Version(NOTAG, msize, ver));
	else{
		m := <-tmsg;
		if(m == nil)
			quit();
		if(m == nil || tagof(m) != tagof(Tmsg.Version)){
			log("invalid initial version message: "+m.text());
			quit();
		}
		sendtmsg(m);
	}
	if((gm := <-rmsg) == nil)
		return -1;
	pick m := gm {
	Readerror =>
		return -1;
	Version =>
		if(doneversion && (m.msize != msize || m.version != ver)){
			log("wrong msize/version on reconnect");
			# XXX is there any hope here - we could quit.
			return -1;
		}
		if(!doneversion){
			msize = m.msize;
			ver = m.version;
			doneversion = 1;
			sendrmsg(m);
		}
		return 0;
	* =>
		log("invalid reply to Tversion: "+m.text());
		return -1;
	}
}

resurrecttags()
{
	# make sure that we send the tmsgs in the same order that
	# they were sent originally.
	all := array[ntags] of ref Tag;
	n := 0;
	for(i := 0; i < len tags; i++){
		for(t := tags[i]; t != nil; t = t.next){
			fid := tmsgfid(t.m);
			if(fid != NOFID && (f := getfid(fid)) != nil){
				if(f.state == DEAD){
					sendrmsg(ref Rmsg.Error(t.m.tag, Estale));
						t.dead = 1;
					continue;
				}
				if(Erroronpartial){
					partial := 0;
					pick m := t.m {
					Create =>
						partial = 1;
					Remove =>
						partial = 1;
					Wstat =>
						partial = (m.stat.name != nil && f.path != nil && hd f.path != m.stat.name);
					Write =>
						partial = (f.qid.qtype & Sys->QTAPPEND);
					}
					if(partial)
						sendrmsg(ref Rmsg.Error(t.m.tag, Epartial));
				}
			}
			all[n++] = t;
		}
	}
	all = all[0:n];
	sort(all);
	for(i = 0; i < len all; i++){
		t := all[i];
		pick m := t.m {
		Flush =>
			ot := gettag(m.oldtag, 0);
			if(ot == nil || ot.dead){
				sendrmsg(ref Rmsg.Flush(t.m.tag));
				t.dead = 1;
				continue;
			}
		}
		sendtmsg(t.m);
	}
	tags = array[len tags] of ref Tag;
	ntags = 0;
	for(i = 0; i < len all; i++)
		if(all[i].dead == 0)
			newtag(all[i].m);
}

# re-open all the old fids, if possible.
# use up to Nprocs processes to keep latency down.
resurrectfids(): int
{
	procrmsg = array[Nprocs] of {* => chan[1] of ref Rmsg};
	spawn rmsgmarshal(finish := chan of int);
	getroot := chan of (int, string, string, chan of ref Root);
	usedroot := chan of ref Root;
	spawn fidproc(getroot, usedroot);
	token = chan[Nprocs] of (int, chan of (ref Fid, ref Root));
	for(i := 0; i < Nprocs; i++)
		token <-= (i, nil);

	for(i = 0; i < len fids.items; i++){
		for(fl := fids.items[i]; fl != nil; fl = tl fl){
			fid := (hd fl).t1;
			(procid, workc) := <-token;
			getroot <-= (1, fid.uname, fid.aname, reply := chan of ref Root);
			root := <-reply;
			if(workc == nil){
				workc = chan of (ref Fid, ref Root);
				spawn workproc(procid, workc, usedroot);
			}
			workc <-= (fid, root);
		}
	}

	for(i = 0; i < Nprocs; i++){
		(nil, workc) := <-token;
		if(workc != nil)
			workc <-= (nil, nil);
	}
	for(i = 0; i < Nprocs; i++){
		getroot <-= (0, nil, nil, reply := chan of ref Root);
		root := <-reply;
		if(<-root.attached > 0)
			clunk(0, root.fid);
	}
	usedroot <-= nil;
	return <-finish;
}

workproc(procid: int, workc: chan of (ref Fid, ref Root), usedroot: chan of ref Root)
{
	while(((fid, root) := <-workc).t0 != nil){
		# mark fid as dead only if it's a genuine server error, not if
		# the server has just hung up.
		if((err := resurrectfid(procid, fid, root)) != nil && sfd != nil){
			log(err);
			fid.state = DEAD;
		}
		usedroot <-= root;
		token <-= (procid, workc);
	}
}

resurrectfid(procid: int, fid: ref Fid, root: ref Root): string
{
	if(fid.state == AUTH)
		return "auth fid discarded";
	attached := <-root.attached;
	if(attached == -1){
		root.attached <-= -1;
		return "root attach failed";
	}
	if(!attached || root.uname != fid.uname || root.aname != fid.aname){
		if(attached)
			clunk(procid, root.fid);
		afid := NOFID;
		if(fid.authed){
			afid = fid.fid - 1;		# see unusedfid()
			if((err := auth(procid, afid, root.uname, root.aname)) != nil){
				log(err);
				afid = -1;
			}
		}
		(err, qid) := attach(procid, root.fid, afid, fid.uname, fid.aname);
		if(afid != NOFID)
			clunk(procid, afid);
		if(err != nil){
			root.attached <-= -1;
			return "attach failed: "+err;
		}
		root.uname = fid.uname;
		root.aname = fid.aname;
		root.qid = qid;
	}
	root.attached <-= 1;
	(err, qid) := walk(procid, root.fid, fid.fid, fid.path, root.qid);
	if(err != nil)
		return err;
	if(fid.state == OPEN && (err = openfid(procid, fid)) != nil){
		clunk(procid, fid.fid);
		return err;
	}
	return nil;
}

openfid(procid: int, fid: ref Fid): string
{
	(err, qid) := open(procid, fid.fid, fid.omode);
	if(err != nil)
		return err;
	if(qid.path != fid.qid.path || qid.qtype != fid.qid.qtype)
		return "qid mismatch on reopen";
	return nil;
}
			
# store up to Nprocs separate root fids and dole them out to those that want them.
fidproc(getroot: chan of (int, string, string, chan of ref Root), usedroot: chan of ref Root)
{
	roots := array[Nprocs] of ref Root;
	n := 0;
	maxfid := -1;
	for(;;)alt{
	(match, uname, aname, reply) := <-getroot =>
		for(i := 0; i < n; i++)
			if(match && roots[i].uname == uname && roots[i].aname == aname)
				break;
		if(i == n)
			for(i = 0; i < n; i++)
				if(roots[i].refcount == 0)
					break;
		if(i == n){
			maxfid = unusedfid(maxfid);
			roots[n] = ref Root(0, chan[1] of int, maxfid, Noqid, uname, aname);
			roots[n++].attached <-= 0;
		}
		roots[i].refcount++;
		reply <-= roots[i];
	r := <-usedroot =>
		if(r == nil)
			exit;	
		r.refcount--;
	}
}

clunk(procid: int, fid: int)
{
	pick m := fcall(ref Tmsg.Clunk(procid, fid)) {
	Error =>
		if(sfd != nil)
			log("error on clunk: " + m.ename);
	}
}

attach(procid, fid, afid: int, uname, aname: string): (string, Sys->Qid)
{
	pick m := fcall(ref Tmsg.Attach(procid, fid, afid, uname, aname)) {
	Attach =>
		return (nil, m.qid);
	Error =>
		return (m.ename, Noqid);
	}
	return (nil, Noqid);	# not reached
}

read(procid, fid: int, buf: array of byte): (int, string)
{
	# XXX assume that offsets are ignored of auth fid reads/writes
	pick m := fcall(ref Tmsg.Read(procid, fid, big 0, len buf)) {
	Error =>
		return (-1, m.ename);
	Read =>
		buf[0:] = m.data;
		return (len m.data, nil);
	}
	return (-1, nil);			# not reached
}

write(procid, fid: int, buf: array of byte): (int, string)
{
	# XXX assume that offsets are ignored of auth fid reads/writes
	pick m := fcall(ref Tmsg.Write(procid, fid, big 0, buf)) {
	Error =>
		sys->werrstr(m.ename);
		return (-1, sys->sprint("%r"));
	Write =>
		return (m.count, nil);
	}
	return (-1, nil);		# not reached
}

auth(procid, fid: int, uname, aname: string): string
{
	if(factotum == nil)
		return "no factotum available";

	pick m := fcall(ref Tmsg.Auth(procid, fid, uname, aname)) {
	Error =>
		return m.ename;
	}

	readc := chan of (array of byte, chan of (int, string));
	writec := chan of (array of byte, chan of (int, string));
	done := chan of (ref Factotum->Authinfo, string);
	spawn factotum->genproxy(readc, writec, done,
			sys->open("/mnt/factotum/rpc", Sys->ORDWR),
			"proto=p9any role=client "+keyspec);
	for(;;)alt{
	(buf, reply) := <-readc =>
		reply <-= read(procid, fid, buf);
	(buf, reply) := <-writec =>
		reply <-= write(procid, fid, buf);
	(authinfo, err) := <-done =>
		if(authinfo == nil){
			clunk(procid, fid);
			return err;
		}
		# XXX check that authinfo.cuid == uname?
		return nil;
	}
}

# path is in reverse order; assume fid != newfid on entry.
walk(procid: int, fid, newfid: int, path: list of string, qid: Sys->Qid): (string, Sys->Qid)
{
	names := array[len path] of string;
	for(i := len names - 1; i >= 0; i--)
		(names[i], path) = (hd path, tl path);
	do{
		w := names;
		if(len w > Styx->MAXWELEM)
			w = w[0:Styx->MAXWELEM];
		names = names[len w:];
		pick m := fcall(ref Tmsg.Walk(procid, fid, newfid, w)) {
		Error =>
			if(newfid == fid)
				clunk(procid, newfid);
			return ("walk error: "+m.ename, Noqid);
		Walk =>
			if(len m.qids != len w){
				if(newfid == fid)
					clunk(procid, newfid);
				return ("walk: file not found", Noqid);
			}
			if(len m.qids > 0)
				qid = m.qids[len m.qids - 1];
			fid = newfid;
		}
	}while(len names > 0);
	return (nil, qid);
}

open(procid: int, fid: int, mode: int): (string, Sys->Qid)
{
	pick m := fcall(ref Tmsg.Open(procid, fid, mode)) {
	Error =>
		return ("open: "+m.ename, Noqid);
	Open =>
		return (nil, m.qid);		# XXX what if iounit doesn't match the original?
	}
	return (nil, Noqid);		# not reached
}

fcall(m: ref Tmsg): ref Rmsg
{
	sendtmsg(m);
	pick rm := <-procrmsg[m.tag] {
	Readerror =>
		procrmsg[m.tag] <-= rm;
		return ref Rmsg.Error(rm.tag, rm.error);
	Error =>
		return rm;
	* =>
		if(rm.mtype() != m.mtype()+1)
			return ref Rmsg.Error(m.tag, Etypemismatch);
		return rm;
	}
}

# find an unused fid (and make sure that the one before it is unused
# too, in case we want to use it for an auth fid);
unusedfid(maxfid: int): int
{
	for(f := maxfid + 1; ; f++)
		if(fids.find(f) == nil && fids.find(f+1) == nil)
			return f + 1;
	abort("no unused fids - i don't believe it");
	return 0;
}

# XXX what about message length limitations?
sendtmsg(m: ref Tmsg)
{
	if(Debug) sys->print("%s\n", m.text());
	d := m.pack();
	if(sys->write(sfd, d, len d) != len d)
		log(sys->sprint("tmsg write failed: %r"));	# XXX could signal to redial
}

sendrmsg(m: ref Rmsg)
{
	d := m.pack();
	if(sys->write(cfd, d, len d) != len d){
		log(sys->sprint("rmsg write failed: %r"));
		quit();
	}
}

rmsgmarshal(finish: chan of int)
{
	for(;;)alt{
	finish <-= 1 =>
		exit;
	m := <-rmsg =>
		if(m == nil || tagof(m) == tagof(Rmsg.Readerror)){
			sfd = nil;
			for(i := 0; i < Nprocs; i++)
				procrmsg[i] <-= ref Rmsg.Readerror(NOTAG, "hung up");
			finish <-= 0;
			exit;
		}
		if(m.tag >= Nprocs){
			log("invalid reply message");
			break;
		}
		# XXX if the server replies with a tag that no-one's waiting for. we'll lock up.
		# (but is it much of a concern, given no flushes, etc?)
		procrmsg[m.tag] <-= m;
	}
}

rmsgreader(fd: ref Sys->FD, sync: chan of int)
{
	sync <-= sys->pctl(0, nil);
	m: ref Rmsg;
	do {
		m = Rmsg.read(fd, msize);
		if(Debug) sys->print("%s\n", m.text());
		rmsg <-= m;
	} while(m != nil && tagof(m) != tagof(Tmsg.Readerror));
}

tmsgreader()
{
	m: ref Tmsg;
	do{
		m = Tmsg.read(cfd, msize);
		tmsg <-= m;
	} while(m != nil && tagof(m) != tagof(Tmsg.Readerror));
}

abort(s: string)
{
	log(s);
	raise "abort";
}

tmsgfid(t: ref Tmsg): int
{
	fid := NOFID;
	pick m := t {
	Attach =>
		fid = m.afid;
	Walk =>
		fid = m.fid;
	Open =>
		fid = m.fid;
	Create =>
		fid = m.fid;
	Read =>
		fid = m.fid;
	Write =>
		fid = m.fid;
	Clunk or
	Stat or
	Remove =>
		fid = m.fid;
	Wstat =>
		fid = m.fid;
	}
	return fid;
}

blankfid: Fid;
newfid(fid: int): ref Fid
{
	f := ref blankfid;
	f.fid = fid;
	if(fids.add(fid, f) == 0){
		abort("duplicate fid "+string fid);
	}
	return f;
}

getfid(fid: int): ref Fid
{
	return fids.find(fid);
}

newtag(m: ref Tmsg): ref Tag
{
	# XXX what happens if the client sends a duplicate tag?
	t := ref Tag(m, seqno++, 0, nil);
	slot := t.m.tag & (NTAGHASH - 1);
	t.next = tags[slot];
	tags[slot] = t;
	ntags++;
	return t;
}

gettag(tag: int, destroy: int): ref Tag
{
	slot := tag & (NTAGHASH - 1);
	prev: ref Tag;
	for(t := tags[slot]; t != nil; t = t.next){
		if(t.m.tag == tag)
			break;
		prev = t;
	}
	if(t == nil || !destroy)
		return t;
	if(prev == nil)
		tags[slot] = t.next;
	else
		prev.next = t.next;
	ntags--;
	return t;
}

Table[T].new(nslots: int, nilval: T): ref Table[T]
{
	if(nslots == 0)
		nslots = 13;
	return ref Table[T](array[nslots] of list of (int, T), nilval);
}

Table[T].add(t: self ref Table[T], id: int, x: T): int
{
	slot := id % len t.items;
	for(q := t.items[slot]; q != nil; q = tl q)
		if((hd q).t0 == id)
			return 0;
	t.items[slot] = (id, x) :: t.items[slot];
	return 1;
}

Table[T].del(t: self ref Table[T], id: int): int
{
	slot := id % len t.items;
	
	p: list of (int, T);
	r := 0;
	for(q := t.items[slot]; q != nil; q = tl q){
		if((hd q).t0 == id){
			p = joinip(p, tl q);
			r = 1;
			break;
		}
		p = hd q :: p;
	}
	t.items[slot] = p;
	return r;
}

Table[T].find(t: self ref Table[T], id: int): T
{
	for(p := t.items[id % len t.items]; p != nil; p = tl p)
		if((hd p).t0 == id)
			return (hd p).t1;
	return t.nilval;
}

sort(a: array of ref Tag)
{
	mergesort(a, array[len a] of ref Tag);
}

mergesort(a, b: array of ref Tag)
{
	r := len a;
	if (r > 1) {
		m := (r-1)/2 + 1;
		mergesort(a[0:m], b[0:m]);
		mergesort(a[m:], b[m:]);
		b[0:] = a;
		for ((i, j, k) := (0, m, 0); i < m && j < r; k++) {
			if (b[i].seq > b[j].seq)
				a[k] = b[j++];
			else
				a[k] = b[i++];
		}
		if (i < m)
			a[k:] = b[i:m];
		else if (j < r)
			a[k:] = b[j:r];
	}
}

kill(pid: int, note: string): int
{
	fd := sys->open("#p/"+string pid+"/ctl", Sys->OWRITE);
	if(fd == nil || sys->fprint(fd, "%s", note) < 0)
		return -1;
	return 0;
}

# join x to y, leaving result in arbitrary order.
joinip[T](x, y: list of (int, T)): list of (int, T)
{
	if(len x > len y)
		(x, y) = (y, x);
	for(; x != nil; x = tl x)
		y = hd x :: y;
	return y;
}
