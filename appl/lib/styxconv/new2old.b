implement Styxconv;

include "sys.m";
	sys: Sys;
include "osys.m";
include "nsys.m";
include "draw.m";
include "styx.m";
	nstyx: Styx;
	Tmsg, Rmsg: import nstyx;
include "ostyx.m";
	ostyx: OStyx;
	OTmsg, ORmsg: import ostyx;
include "styxconv.m";

# todo: map fids > ffff into 16 bits

DEBUG: con 1;

Fid: adt
{
	fid: int;
	isdir: int;
	n: int;			# size of last new client dirread request.
	soff: int;			# dir offset on old server.
	coff: int;			# dir offset on new client.
	next: cyclic ref Fid;
};

Req: adt {
	tag: int;
	oldtag: int;					# if it's a flush.
	rp: ref Reqproc;
	next: cyclic ref Req;
	flushes: list of ref Rmsg.Flush;		# flushes awaiting req finish.
};

Reqproc: adt {
	newtmsg: chan of ref Tmsg;		# convproc -> reqproc, once per req.
	newrmsg: chan of ref Rmsg;		# reqproc -> convproc, once per req

	oldtmsg: chan of ref OTmsg;		# reqproc -> convproc
	oldrmsg: chan of ref ORmsg;		# convproc -> reqproc

	flushable: int;

	new: fn(): ref Reqproc;
	rpc: fn(rp: self ref Reqproc, otm: ref OTmsg): ref ORmsg;
};

tags: ref Req;
avail: chan of ref Reqproc;
fids: ref Fid;
nprocs := 0;

init()
{
	sys = load Sys Sys->PATH;
	if(sys == nil)
		nomod("Sys", Sys->PATH);
	nstyx = load Styx Styx->PATH;
	if(nstyx == nil)
		nomod("Styx", Styx->PATH);
	ostyx = load OStyx OStyx->PATH;
	if(ostyx == nil)
		nomod("OStyx", OStyx->PATH);

	ostyx->init();
	nstyx->init();
	avail = chan of ref Reqproc;
}

styxconv(newclient: ref Sys->FD, oldsrv: ref Sys->FD)
{
	newtmsg := chan of ref Tmsg;
	oldrmsg := chan of ref ORmsg;

	killpids := chan[2] of int;
	spawn readnewtmsgs(killpids, newclient, newtmsg);
	spawn readoldrmsgs(killpids, oldsrv, oldrmsg);

converting:
	for(;;)alt{
	ntm := <-newtmsg =>
		if(DEBUG)
			sys->fprint(sys->fildes(2), "-> %s\n", ntm.text());
		if(ntm == nil)
			break converting;
		ns2os(ntm, newclient, oldsrv);
	orm := <-oldrmsg =>
		if(DEBUG)
			sys->fprint(sys->fildes(2), "	<- %s\n", ostyx->rmsg2s(orm));
		if(orm == nil)
			break converting;
		t := looktag(orm.tag);
		if(t == nil){
			warning("reply by old-server to non-existent tag");
			break;
		}
		pick rm := orm {
		Flush =>
			ot := looktag(t.oldtag);
			# if it's an Rflush of a request-in-progress,
			# we send it to the reqproc, which
			# can then clean up as it likes.
			if(ot != nil){
				if(ot.rp != nil){
					if(ot.rp.flushable){
						ot.rp.oldrmsg <-= rm;
						# reqproc is bound to finish after a flush
						reqreply(ot, newclient, oldsrv);
					}else {
						# hold flush reply for later
						ot.flushes = ref Rmsg.Flush(rm.tag) :: ot.flushes;
					}
					break;
				}
				deletetag(t.oldtag);
			}
			NRsend(newclient, ref Rmsg.Flush(rm.tag));
			deletetag(rm.tag);
		* =>
			if(t.rp != nil){
				t.rp.oldrmsg <-= orm;
				reqreply(t, newclient, oldsrv);
			}else{
				os2ns(orm, newclient);
				deletetag(orm.tag);
			}
		}
	}
	# kill off active reqprocs
	for(; tags != nil; tags = tags.next){
		if(tags.rp != nil){
			tags.rp.oldrmsg <-= nil;
			nprocs--;
		}
	}
	# kill off idle reqprocs
	while(nprocs > 0){
		rp := <-avail;
		rp.newtmsg <-= nil;
		nprocs--;
	}
	# kill off message readers
	kill(<-killpids);
	kill(<-killpids);
}

# process one response from the request proc.
# request proc can respond by sending a new tmsg to the old server
# or by sending an rmsg to the new client, in which case
# it implicitly signals that it has finished processing the request.
# the actual reply might be an Rflush, signifying that
# the request has been aborted.
reqreply(t: ref Req, newclient: ref Sys->FD, oldsrv: ref Sys->FD)
{
	rp := t.rp;
	alt{
	nrm := <-rp.newrmsg =>
		# request is done when process sends rmsg
		pick rm := nrm {
		Flush =>
			deletetag(t.tag);
		}
		deletetag(nrm.tag);
		NRsend(newclient, nrm);
		for(; t.flushes != nil; t.flushes = tl t.flushes)
			NRsend(newclient, hd t.flushes);

	otm := <-rp.oldtmsg =>
		OTsend(oldsrv, otm);
	}
}


# T messages: forward on, reply immediately, or start processing.
ns2os(tm0: ref Tmsg, newclient, oldsrv: ref Sys->FD)
{
	otm: ref OTmsg;

	t := ref Req(tm0.tag, -1, nil, nil, nil);
	pick tm := tm0{
	Readerror =>
		exit;
	Version =>
		(s, v) := nstyx->compatible(tm, nstyx->MAXRPC, nil);
		NRsend(newclient, ref Rmsg.Version(tm.tag, s, v));
		return;
	Auth =>
		NRsend(newclient, ref Rmsg.Error(tm.tag, "authorization not required"));
		return;
	Walk =>
		storetag(t);
		t.rp = Reqproc.new();
		t.rp.newtmsg <-= tm;
		reqreply(t, newclient, oldsrv);
		return;
	Attach =>
		otm = ref OTmsg.Attach(tm.tag, tm.fid, tm.uname, tm.aname);
	Flush =>
		t.oldtag = tm.oldtag;
		otm = ref OTmsg.Flush(tm.tag, tm.oldtag);
	Open =>
		otm = ref OTmsg.Open(tm.tag, tm.fid, tm.mode);
	Create =>
		otm = ref OTmsg.Create(tm.tag, tm.fid, tm.perm, tm.mode, tm.name);
	Read =>
		fp := findfid(tm.fid);
		count := tm.count;
		offset := tm.offset;
		if(fp != nil && fp.isdir){
			fp.n = count;
			count = (count/OStyx->DIRLEN)*OStyx->DIRLEN;
			if(int offset != fp.coff){
				NRsend(newclient, ref Rmsg.Error(tm.tag, "unexpected offset in dirread"));
				return;
			}
			offset = big fp.soff;
		}
		otm = ref OTmsg.Read(tm.tag, tm.fid, count, offset);
	Write =>
		otm = ref OTmsg.Write(tm.tag, tm.fid, tm.offset, tm.data);
	Clunk =>
		otm = ref OTmsg.Clunk(tm.tag, tm.fid);
	Remove =>
		otm = ref OTmsg.Remove(tm.tag, tm.fid);
	Stat =>
		otm = ref OTmsg.Stat(tm.tag, tm.fid);
	Wstat =>
		otm = ref OTmsg.Wstat(tm.tag, tm.fid, nd2od(tm.stat));
	* =>
		fatal("bad T message");
	}
	storetag(t);
	OTsend(oldsrv, otm);
}

# R messages: old to new
os2ns(orm0: ref ORmsg, newclient: ref Sys->FD)
{
	rm: ref Rmsg;

	rm = nil;
	pick orm := orm0 {
	Error =>
		rm = ref Rmsg.Error(orm.tag, orm.err);
	Flush =>
		rm = ref Rmsg.Flush(orm.tag);
	Clone =>
		rm = ref Rmsg.Walk(orm.tag, nil);
	Walk =>
		fatal("walk rmsgs should be dealt with be walkreqproc");
	Open =>
		setfid(orm.fid, orm.qid);
		rm = ref Rmsg.Open(orm.tag, oq2nq(orm.qid), 0);
	Create =>
		setfid(orm.fid, orm.qid);
		rm = ref Rmsg.Create(orm.tag, oq2nq(orm.qid), 0);
	Read =>
		fp := findfid(orm.fid);
		data := orm.data;
		if(fp != nil && fp.isdir)
			data = ods2nds(data, fp.n);
		fp.coff += len data;
		fp.soff += len orm.data;
		rm = ref Rmsg.Read(orm.tag, data);
	Write =>
		rm = ref Rmsg.Write(orm.tag, orm.count);
	Clunk =>
		rm = ref Rmsg.Clunk(orm.tag);
		deletefid(orm.fid);
	Remove =>
		rm = ref Rmsg.Remove(orm.tag);
		deletefid(orm.fid);
	Stat =>
		rm = ref Rmsg.Stat(orm.tag, od2nd(orm.stat));
	Wstat =>
		rm = ref Rmsg.Wstat(orm.tag);
	Attach =>
		newfid(orm.fid, orm.qid.path & OSys->CHDIR);
		rm = ref Rmsg.Attach(orm.tag, oq2nq(orm.qid));
	* =>
		fatal("bad R message");
	}
	NRsend(newclient, rm);
}

Reqproc.rpc(rp: self ref Reqproc, otm: ref OTmsg): ref ORmsg
{
	rp.oldtmsg <-= otm;
	m := <-rp.oldrmsg;
	if(m == nil)
		exit;
	return m;
}

Reqproc.new(): ref Reqproc
{
	alt{
	rp := <-avail =>
		return rp;
	* =>
		rp := ref Reqproc(
			chan of ref Tmsg,
			chan of ref Rmsg,
			chan of ref OTmsg,
			chan of ref ORmsg,
			1);
		spawn reqproc(rp);
		nprocs++;
		return rp;
	}
}

reqproc(rp: ref Reqproc)
{
	for(;;){
		tm := <-rp.newtmsg;
		if(tm == nil)
			return;
		rm: ref Rmsg;
		pick m := tm {
		Walk =>
			rm = walkreq(m, rp);
		* =>
			fatal("non-walk req passed to reqproc");
		}
		rp.flushable = 1;
		rp.newrmsg <-= rm;
		avail <-= rp;
	}
}

# note that although this is in a separate process,
# whenever it's not in Reqproc.rpc, the styxconv
# process is blocked, so although state is shared,
# there are no race conditions.
walkreq(tm: ref Tmsg.Walk, rp: ref Reqproc): ref Rmsg
{
	cloned := 0;
	n := len tm.names;
	if(tm.newfid != tm.fid){
		cloned = 1;
		pick rm := rp.rpc(ref OTmsg.Clone(tm.tag, tm.fid, tm.newfid)) {
		Clone =>
			;
		Error =>
			return ref Rmsg.Error(tm.tag, rm.err);
		Flush =>
			return ref Rmsg.Flush(rm.tag);
		* =>
			fatal("unexpected reply to OTmsg.Clone");
		}
		cloned = 1;
	}
	qids := array[n] of NSys->Qid;
	finalqid: OSys->Qid;

	# make sure we don't get flushed in an unwindable state.
	rp.flushable = n == 1 || cloned;
	for(i := 0; i < n; i++){
		pick rm := rp.rpc(ref OTmsg.Walk(tm.tag, tm.newfid, tm.names[i])) {
		Walk =>
			qids[i] = oq2nq(rm.qid);
			finalqid = rm.qid;
		Flush =>
			if(cloned){
				rp.flushable = 0;
				rp.rpc(ref OTmsg.Clunk(tm.tag, tm.newfid));
			}
			return ref Rmsg.Flush(rm.tag);
		Error =>
			if(cloned){
				rp.flushable = 0;
				rp.rpc(ref OTmsg.Clunk(tm.tag, tm.newfid));
			}
			if(i == 0)
				return ref Rmsg.Error(tm.tag, rm.err);
			return ref Rmsg.Walk(tm.tag, qids[0:i]);
		}
	}
	if(cloned)
		clonefid(tm.fid, tm.newfid);
	if(n > 0)
		setfid(tm.newfid, finalqid);
	return ref Rmsg.Walk(tm.tag, qids);
}

storetag(t: ref Req)
{
	t.next = tags;
	tags = t;
}

looktag(tag: int): ref Req
{
	for(t := tags; t != nil; t = t.next)
		if(t.tag == tag)
			return t;
	return nil;
}

deletetag(tag: int)
{
	prev: ref Req;
	t := tags;
	while(t != nil){
		if(t.tag == tag){
			next := t.next;
			t.next = nil;
			if(prev != nil)
				prev.next = next;
			else
				tags = next;
			t = next;
		}else{
			prev = t;
			t = t.next;
		}
	}
}

newfid(fid: int, isdir: int): ref Fid
{
	f := ref Fid;
	f.fid = fid;
	f.isdir = isdir;
	f.n = f.soff = f.coff = 0;
	f.next = fids;
	fids = f;
	return f;
}

clonefid(ofid: int, fid: int): ref Fid
{
	if((f := findfid(ofid)) != nil){
		nf := newfid(fid, f.isdir);
		return nf;
	}
	warning("clone of non-existent fid");
	return newfid(fid, 0);
}

deletefid(fid: int)
{
	lf: ref Fid;

	for(f := fids; f != nil; f = f.next){
		if(f.fid == fid){
			if(lf == nil)
				fids = f.next;
			else
				lf.next = f.next;
			return;
		}
		lf = f;
	}
}

findfid(fid: int): ref Fid
{
	for(f := fids; f != nil; f = f.next)
		if(f.fid == fid)
			return f;
	return nil;
}

setfid(fid: int, qid: OSys->Qid)
{
	f := findfid(fid);
	if(f == nil){
		warning(sys->sprint("cannot find fid %d", fid));
	}else{
		f.isdir = qid.path & OSys->CHDIR;
	}
}

om2nm(om: int): int
{
	# DMDIR == CHDIR
	return om;
}

nm2om(m: int): int
{
	# DMDIR == CHDIR
	return m&~(NSys->DMAPPEND|NSys->DMEXCL|NSys->DMAUTH);
}

oq2nq(oq: OSys->Qid): NSys->Qid
{
	q: NSys->Qid;

	isdir := oq.path&OSys->CHDIR;
	q.path = big (oq.path&~OSys->CHDIR);
	q.vers = oq.vers;
	q.qtype = 0;
	if(isdir)
		q.qtype |= NSys->QTDIR;
	return q;
}
	
nq2oq(q: NSys->Qid): OSys->Qid
{
	oq: OSys->Qid;

	isdir := q.qtype&NSys->QTDIR;
	oq.path = int q.path;
	oq.vers = q.vers;
	if(isdir)
		oq.path |= OSys->CHDIR;
	return oq;
}

od2nd(od: OSys->Dir): NSys->Dir
{
	d: NSys->Dir;

	d.name = od.name;
	d.uid = od.uid;
	d.gid = od.gid;
	d.muid = od.uid;
	d.qid = oq2nq(od.qid);
	d.mode = om2nm(od.mode);
	d.atime = od.atime;
	d.mtime = od.mtime;
	d.length = big od.length;
	d.dtype = od.dtype;
	d.dev = od.dev;
	return d;
}

nd2od(d: NSys->Dir): OSys->Dir
{
	od: OSys->Dir;

	od.name = d.name;
	od.uid = d.uid;
	od.gid = d.gid;
	od.qid = nq2oq(d.qid);
	od.mode = nm2om(d.mode);
	od.atime = d.atime;
	od.mtime = d.mtime;
	od.length = int d.length;
	od.dtype = d.dtype;
	od.dev = d.dev;
	return od;
}

ods2nds(ob: array of byte, max: int): array of byte
{
	od: OSys->Dir;

	m := len ob;
	if(m % OStyx->DIRLEN != 0)
		fatal(sys->sprint("bad dir len %d", m));
	m /= OStyx->DIRLEN;
	n := 0;
	p := ob;
	for(i := 0; i < m; i++){
		(p, od) = ostyx->convM2D(p);
		d := od2nd(od);
		nn := nstyx->packdirsize(d);
		if(n+nn > max)	# might just happen with long file names
			break;
		n += nn;
	}
	m = i;
	b := array[n] of byte;
	n = 0;
	p = ob;
	for(i = 0; i < m; i++){
		(p, od) = ostyx->convM2D(p);
		d := od2nd(od);
		q := nstyx->packdir(d);
		nn := len q;
		b[n: ] = q[0: nn];
		n += nn;
	}
	return b;
}
		
OTsend(fd: ref Sys->FD, otm: ref OTmsg): int
{
	if(DEBUG)
		sys->fprint(sys->fildes(2), "	-> %s\n", ostyx->tmsg2s(otm));
	s := array[OStyx->MAXRPC] of byte;
	n := ostyx->tmsg2d(otm, s);
	if(n < 0)
		return -1;
	return sys->write(fd, s, n);
}

NRsend(fd: ref Sys->FD, rm: ref Rmsg): int
{
	if(DEBUG)
		sys->fprint(sys->fildes(2), "<- %s\n", rm.text());
	s := rm.pack();
	if(s == nil)
		return -1;
	return sys->write(fd, s, len s);
}

readnewtmsgs(pidc: chan of int, newclient: ref Sys->FD, newtmsg: chan of ref Tmsg)
{
	pidc <-= sys->pctl(0, nil);
	for(;;){
		newtmsg <-= Tmsg.read(newclient, nstyx->MAXRPC);
	}
}

readoldrmsgs(pidc: chan of int, oldsrv: ref Sys->FD, oldrmsg: chan of ref ORmsg)
{
	pidc <-= sys->pctl(0, nil);
	for(;;){
		oldrmsg <-= ORmsg.read(oldsrv);
	}
}

warning(err: string)
{
	sys->fprint(sys->fildes(2), "warning: %s\n", err);
}

fatal(err: string)
{
	sys->fprint(sys->fildes(2), "%s\n", err);
	exit;
}

nomod(mod: string, path: string)
{
	fatal(sys->sprint("can't load %s(%s): %r", mod, path));
}

kill(pid: int)
{
	sys->fprint(sys->open("#p/"+string pid+"/ctl", Sys->OWRITE), "kill");
}
