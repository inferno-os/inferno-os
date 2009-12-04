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

DEBUG: con 0;

# convert from old styx client to new styx server.
# more straightforward than the other way around
# because there's an almost exactly 1-1 mapping
# between message types. (the exception is Tversion,
# but we do that synchronously anyway).

# todo: map qids > ffffffff into 32 bits.

Msize: con nstyx->IOHDRSZ + OSys->ATOMICIO;
Fid: adt
{
	fid: int;
	isdir: int;
	n: int;			# size of last new client dirread request.
	soff: int;			# dir offset on new server.
	coff: int;			# dir offset on old client.
	next: cyclic ref Fid;
	extras: array of byte;	# packed old styx dir structures
};

Req: adt {
	tag: int;
	fid: int;
	oldtag: int;			# if it's a flush.
	newfid: int;			# if it's a clone
	next: cyclic ref Req;
};

tags: ref Req;
fids: ref Fid;

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
}

styxconv(oldclient, newsrv: ref Sys->FD)
{
	oldtmsg := chan of ref OTmsg;
	newrmsg := chan of ref Rmsg;

	killpids := chan[2] of int;
	spawn readoldtmsgs(killpids, oldclient, oldtmsg);
	spawn readnewrmsgs(killpids, newsrv, newrmsg);
	# XXX difficulty: what happens if the server isn't responding
	# and the client hangs up? we won't know about it.
	# but we don't want to know about normal t-messages
	# piling up either, so we don't want to alt on oldtmsg too.
	NTsend(newsrv, ref Tmsg.Version(nstyx->NOTAG, Msize, "9P2000"));
	pick nrm := <-newrmsg {
	Version =>
		if(DEBUG)
			sys->fprint(sys->fildes(2), "	<- %s\n", nrm.text());
		if(nrm.msize < Msize)
			fatal("message size too small");
	Error =>
		fatal("versioning failed: " + nrm.ename);
	* =>
		fatal("bad response to Tversion: " + nrm.text());
	}

converting:
	for(;;)alt{
	otm := <-oldtmsg =>
		if(DEBUG)
			sys->fprint(sys->fildes(2), "-> %s\n", ostyx->tmsg2s(otm));
		if(otm == nil || tagof(otm) == tagof(OTmsg.Readerror))
			break converting;
		oc2ns(otm, oldclient, newsrv);
	nrm := <-newrmsg =>
		if(DEBUG)
			sys->fprint(sys->fildes(2), "	<- %s\n", nrm.text());
		if(nrm == nil || tagof(nrm) == tagof(Rmsg.Readerror))
			break converting;
		t := looktag(nrm.tag);
		if(t == nil){
			warning("reply by new-server to non-existent tag");
			break;
		}
		ns2oc(t, nrm, oldclient);
		deletetag(nrm.tag);
	}

	kill(<-killpids);
	kill(<-killpids);
}

# T messages: forward on or reply immediately
oc2ns(tm0: ref OTmsg, oldclient, newsrv: ref Sys->FD)
{
	ntm: ref Tmsg;

	t := ref Req(tm0.tag, -1, -1, -1, nil);
	pick tm := tm0{
	Nop =>
		ORsend(oldclient, ref ORmsg.Nop(tm.tag));
		return;
	Attach =>
		t.fid = tm.fid;
		ntm = ref Tmsg.Attach(tm.tag, tm.fid, nstyx->NOFID, tm.uname, tm.aname);
	Clone =>
		t.fid = tm.fid;
		t.newfid = tm.newfid;
		ntm = ref Tmsg.Walk(tm.tag, tm.fid, tm.newfid, nil);
	Walk =>
		t.fid = tm.fid;
		ntm = ref Tmsg.Walk(tm.tag, tm.fid, tm.fid, array[] of {tm.name});
	Flush =>
		t.oldtag = tm.oldtag;
		ntm = ref Tmsg.Flush(tm.tag, tm.oldtag);
	Open =>
		t.fid = tm.fid;
		ntm = ref Tmsg.Open(tm.tag, tm.fid, tm.mode);
	Create =>
		t.fid = tm.fid;
		ntm = ref Tmsg.Create(tm.tag, tm.fid, tm.name, tm.perm, tm.mode);
	Read =>
		t.fid = tm.fid;
		fp := findfid(tm.fid);
		count := tm.count;
		offset := tm.offset;
		if(fp.isdir){
			count = (count/OStyx->DIRLEN)*OStyx->DIRLEN;
			# if we got some extra entries last time,
			# then send 'em back this time.
			extras := fp.extras;
			if(len extras > 0){
				if(count > len extras)
					count = len extras;
				ORsend(oldclient, ref ORmsg.Read(tm.tag, t.fid, fp.extras[0:count]));
				fp.extras = extras[count:];
				fp.coff += count;
				return;
			}
			fp.n = count;
			if(int offset != fp.coff){
				ORsend(oldclient, ref ORmsg.Error(tm.tag, "unexpected offset in dirread"));
				return;
			}
			offset = big fp.soff;
		}
		ntm = ref Tmsg.Read(tm.tag, tm.fid, offset, count);
	Write =>
		t.fid = tm.fid;
		ntm = ref Tmsg.Write(tm.tag, tm.fid, tm.offset, tm.data);
	Clunk =>
		t.fid = tm.fid;
		ntm = ref Tmsg.Clunk(tm.tag, tm.fid);
	Remove =>
		t.fid = tm.fid;
		ntm = ref Tmsg.Remove(tm.tag, tm.fid);
	Stat =>
		t.fid = tm.fid;
		ntm = ref Tmsg.Stat(tm.tag, tm.fid);
	Wstat =>
		t.fid = tm.fid;
		ntm = ref Tmsg.Wstat(tm.tag, tm.fid, od2nd(tm.stat));
	* =>
		fatal("bad T message");
	}
	storetag(t);
	NTsend(newsrv, ntm);
}

# R messages: new to old
ns2oc(t: ref Req, nrm0: ref Rmsg, oldclient: ref Sys->FD)
{
	rm: ref ORmsg;
	pick nrm := nrm0{
	Error =>
		rm = ref ORmsg.Error(nrm.tag, nrm.ename);
	Flush =>
		rm = ref ORmsg.Flush(nrm.tag);
		deletetag(t.oldtag);
	Walk =>
		if(len nrm.qids == 0){
			clonefid(t.fid, t.newfid);
			rm = ref ORmsg.Clone(nrm.tag, t.fid);
		}else{
			q := nrm.qids[0];
			setfid(t.fid, q);
			rm = ref ORmsg.Walk(nrm.tag, t.fid, nq2oq(q));
		}
	Open =>
		setfid(t.fid, nrm.qid);
		rm = ref ORmsg.Open(nrm.tag, t.fid, nq2oq(nrm.qid));
	Create =>
		setfid(t.fid, nrm.qid);
		rm = ref ORmsg.Create(nrm.tag, t.fid, nq2oq(nrm.qid));
	Read =>
		fp := findfid(t.fid);
		data := nrm.data;
		if(fp != nil && fp.isdir){
			data = nds2ods(data);
			if(len data > fp.n){
				fp.extras = data[fp.n:];
				data = data[0:fp.n];
			}
			fp.coff += len data;
			fp.soff += len nrm.data;
		}
		rm = ref ORmsg.Read(nrm.tag, t.fid, data);
	Write =>
		rm = ref ORmsg.Write(nrm.tag, t.fid, nrm.count);
	Clunk =>
		deletefid(t.fid);
		rm = ref ORmsg.Clunk(nrm.tag, t.fid);
	Remove =>
		deletefid(t.fid);
		rm = ref ORmsg.Remove(nrm.tag, t.fid);
	Stat =>
		rm = ref ORmsg.Stat(nrm.tag, t.fid, nd2od(nrm.stat));
	Wstat =>
		rm = ref ORmsg.Wstat(nrm.tag, t.fid);
	Attach =>
		newfid(t.fid, nrm.qid.qtype & NSys->QTDIR);
		rm = ref ORmsg.Attach(nrm.tag, t.fid, nq2oq(nrm.qid));
	* =>
		fatal("bad R message");
	}
	ORsend(oldclient, rm);
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
	if((f := findfid(ofid)) != nil)
		return newfid(fid, f.isdir);
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
	for(f := fids; f != nil && f.fid != fid; f = f.next)
		;
	return f;
}

setfid(fid: int, qid: NSys->Qid)
{
	if((f := findfid(fid)) != nil)
		f.isdir = qid.qtype & NSys->QTDIR;
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

nds2ods(ob: array of byte): array of byte
{
	i := 0;
	n := 0;
	ds: list of NSys->Dir;
	while(i < len ob){
		(size, d) := nstyx->unpackdir(ob[i:]);
		if(size == 0)
			break;
		ds = d :: ds;
		i += size;
		n++;
	}
	b := array[OStyx->DIRLEN * n] of byte;
	for(i = (n - 1) * OStyx->DIRLEN; i >= 0; i -= OStyx->DIRLEN){
		ostyx->convD2M(b[i:], nd2od(hd ds));
		ds = tl ds;
	}
	return b;
}

NTsend(fd: ref Sys->FD, ntm: ref Tmsg)
{
	if(DEBUG)
		sys->fprint(sys->fildes(2), "	-> %s\n", ntm.text());
	s := ntm.pack();
	sys->write(fd, s, len s);
}

ORsend(fd: ref Sys->FD, orm: ref ORmsg)
{
	if(DEBUG)
		sys->fprint(sys->fildes(2), "<- %s\n", ostyx->rmsg2s(orm));
	s := array[OStyx->MAXRPC] of byte;
	n := ostyx->rmsg2d(orm, s);
	if(n > 0)
		sys->write(fd, s, n);
}

readoldtmsgs(pidc: chan of int, oldclient: ref Sys->FD, oldtmsg: chan of ref OTmsg)
{
	pidc <-= sys->pctl(0, nil);
	for(;;){
		oldtmsg <-= OTmsg.read(oldclient);
	}
}

readnewrmsgs(pidc: chan of int, newsrv: ref Sys->FD, newrmsg: chan of ref Rmsg)
{
	pidc <-= sys->pctl(0, nil);
	for(;;){
		newrmsg <-= Rmsg.read(newsrv, Msize);
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
