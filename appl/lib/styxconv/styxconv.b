implement Styxconv;

include "sys.m";
	sys: Sys;
include "osys.m";
include "draw.m";
include "styx.m";
	styx: Styx;
	Tmsg, Rmsg: import styx;
include "ostyx.m";
	ostyx: OStyx;
	OTmsg, ORmsg: import ostyx;
include "styxconv.m";

DEBUG: con 0;

Fid: adt
{
	fid: int;
	qid: OSys->Qid;
	n: int;
	odri: int;
	dri: int;
	next: cyclic ref Fid;
};

fids: ref Fid;

init()
{
	sys = load Sys Sys->PATH;
	if(sys == nil)
		nomod("Sys", Sys->PATH);
	styx = load Styx Styx->PATH;
	if(styx == nil)
		nomod("Styx", Styx->PATH);
	ostyx = load OStyx OStyx->PATH;
	if(ostyx == nil)
		nomod("OStyx", OStyx->PATH);

	styx->init();
}

nomod(mod: string, path: string)
{
	fatal(sys->sprint("can't load %s(%s): %r", mod, path));
}

fatal(err: string)
{
	sys->fprint(sys->fildes(2), "%s\n", err);
	exit;
}

newfid(fid: int, qid: OSys->Qid): ref Fid
{
	f := ref Fid;
	f.fid = fid;
	f.qid = qid;
	f.n = f.odri = f.dri = 0;
	f.next = fids;
	fids = f;
	return f;
}

clonefid(ofid: int, fid: int): ref Fid
{
	if((f := findfid(ofid)) != nil)
		return newfid(fid, f.qid);
	return newfid(fid, (0, 0));
}

deletefid(fid: int)
{
	lf: ref Fid;

	for(f := fids; f != nil; f = f.next)
		if(f.fid == fid){
			if(lf == nil)
				fids = f.next;
			else
				lf.next = f.next;
			return;
		}
}

findfid(fid: int): ref Fid
{
	for(f := fids; f != nil && f.fid != fid; f = f.next)
		;
	return f;
}

setfid(fid: int, qid: OSys->Qid)
{
	if((f := findfid(fid)) != nil)
		f.qid = qid;
}

om2nm(om: int): int
{
	# DMDIR == CHDIR
	return om;
}

nm2om(m: int): int
{
	# DMDIR == CHDIR
	return m&~(Sys->DMAPPEND|Sys->DMEXCL|Sys->DMAUTH);
}

oq2nq(oq: OSys->Qid): Sys->Qid
{
	q: Sys->Qid;

	isdir := oq.path&OSys->CHDIR;
	q.path = big (oq.path&~OSys->CHDIR);
	q.vers = oq.vers;
	q.qtype = 0;
	if(isdir)
		q.qtype |= Sys->QTDIR;
	return q;
}
	
nq2oq(q: Sys->Qid): OSys->Qid
{
	oq: OSys->Qid;

	isdir := q.qtype&Sys->QTDIR;
	oq.path = int q.path;
	oq.vers = q.vers;
	if(isdir)
		oq.path |= OSys->CHDIR;
	return oq;
}

od2nd(od: OSys->Dir): Sys->Dir
{
	d: Sys->Dir;

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

nd2od(d: Sys->Dir): OSys->Dir
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

ods2nds(fp: ref Fid, ob: array of byte): array of byte
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
		nn := styx->packdirsize(d);
		if(n+nn > fp.n)	# might just happen with long file names
			break;
		n += nn;
	}
	m = i;
	fp.odri += m*OStyx->DIRLEN;
	fp.dri += n;
	b := array[n] of byte;
	n = 0;
	p = ob;
	for(i = 0; i < m; i++){
		(p, od) = ostyx->convM2D(p);
		d := od2nd(od);
		q := styx->packdir(d);
		nn := len q;
		b[n: ] = q[0: nn];
		n += nn;
	}
	return b;
}
		
Tsend(fd: ref Sys->FD, otm: ref OTmsg): int
{
	if(DEBUG)
		sys->print("OT: %s\n", ostyx->tmsg2s(otm));
	s := array[OStyx->MAXRPC] of byte;
	n := ostyx->tmsg2d(otm, s);
	if(n < 0)
		return -1;
	return sys->write(fd, s, n);
}

Rsend(fd: ref Sys->FD, rm: ref Rmsg): int
{
	if(DEBUG)
		sys->print("NR: %s\n", rm.text());
	s := rm.pack();
	if(s == nil)
		return -1;
	return sys->write(fd, s, len s);
}

Trecv(fd: ref Sys->FD): ref Tmsg
{
	tm := Tmsg.read(fd, Styx->MAXRPC);
	if(tm == nil)
		exit;
	if(DEBUG)
		sys->print("NT: %s\n", tm.text());
	return tm;
}

Rrecv(fd: ref Sys->FD): ref ORmsg
{
	orm := ORmsg.read(fd, OStyx->MAXRPC);
	if(orm == nil)
		exit;
	if(DEBUG)
		sys->print("OR: %s\n", ostyx->rmsg2s(orm));
	return orm;
}

clunkfid(fd2: ref Sys->FD, tm: ref Tmsg.Walk)
{
	deletefid(tm.newfid);
	otm := ref OTmsg.Clunk(tm.tag, tm.newfid);
	Tsend(fd2, otm);
	os2ns(Rrecv(fd2));	# should check return
}

# T messages: new to old (mostly)
ns2os(tm0: ref Tmsg, fd2: ref Sys->FD): (ref OTmsg, ref Rmsg)
{
	otm: ref OTmsg;
	rm: ref Rmsg;
	i, j: int;
	err: string;

	otm = nil;
	rm = nil;
	pick tm := tm0{
	Version =>
		(s, v) := styx->compatible(tm, Styx->MAXRPC, nil);
		rm = ref Rmsg.Version(tm.tag, s, v);
	Auth =>
		rm = ref Rmsg.Error(tm.tag, "authorization not required");
	Attach =>
		newfid(tm.fid, (0, 0));
		otm = ref OTmsg.Attach(tm.tag, tm.fid, tm.uname, tm.aname);
	Readerror =>
		exit;
	Flush =>
		otm = ref OTmsg.Flush(tm.tag, tm.oldtag);
	Walk =>
		# multiple use of tag ok I think
		n := len tm.names;
		if(tm.newfid != tm.fid){
			clonefid(tm.fid, tm.newfid);
			if(n != 0){
				otm = ref OTmsg.Clone(tm.tag, tm.fid, tm.newfid);
				Tsend(fd2, otm);
				os2ns(Rrecv(fd2));	# should check return
			}
		}
		qids := array[n] of Sys->Qid;
		if(n == 0)
			otm = ref OTmsg.Clone(tm.tag, tm.fid, tm.newfid);
		else if(n == 1){
			otm = ref OTmsg.Walk(tm.tag, tm.newfid, tm.names[0]);
			Tsend(fd2, otm);
			rm = os2ns(Rrecv(fd2));
			pick rm0 := rm{
			Readerror =>
				exit;
			Error =>
				if(tm.newfid != tm.fid)
					clunkfid(fd2, tm);
			Walk =>
			* =>
				fatal("bad Rwalk message");
			}
			otm = nil;
		}
		else{
			loop:
			for(i = 0; i < n; i++){
				otm = ref OTmsg.Walk(tm.tag, tm.newfid, tm.names[i]);
				Tsend(fd2, otm);
				rm = os2ns(Rrecv(fd2));
				pick rm0 := rm{
				Readerror =>
					exit;
				Error =>
					err = rm0.ename;
					break loop;
				Walk =>
					qids[i] = rm0.qids[0];
				* =>
					fatal("bad Rwalk message");
				}
			}
			if(i != n && i != 0 && tm.fid == tm.newfid){
				for(j = 0; j < i; j++){
					otm = ref OTmsg.Walk(tm.tag, tm.fid, "..");
					Tsend(fd2, otm);
					rm = os2ns(Rrecv(fd2));
					pick rm0 := rm{
					Readerror =>
						exit;
					Walk =>
					* =>
						fatal("cannot retrieve fid");
					}
				}
			}
			if(i != n && tm.newfid != tm.fid)
				clunkfid(fd2, tm);
			otm = nil;
			if(i == 0)
				rm = ref Rmsg.Error(tm.tag, err);
			else
				rm = ref Rmsg.Walk(tm.tag, qids[0: i]);
		}
	Open =>
		otm = ref OTmsg.Open(tm.tag, tm.fid, tm.mode);
	Create =>
		otm = ref OTmsg.Create(tm.tag, tm.fid, tm.perm, tm.mode, tm.name);
	Read =>
		fp := findfid(tm.fid);
		count := tm.count;
		offset := tm.offset;
		if(fp != nil && fp.qid.path&OSys->CHDIR){
			fp.n = count;
			count = (count/OStyx->DIRLEN)*OStyx->DIRLEN;
			if(int offset != fp.dri)
				fatal("unexpected offset in Read");
			offset = big fp.odri;
		}
		otm = ref OTmsg.Read(tm.tag, tm.fid, count, offset);
	Write =>
		otm = ref OTmsg.Write(tm.tag, tm.fid, tm.offset, tm.data);
	Clunk =>
		deletefid(tm.fid);
		otm = ref OTmsg.Clunk(tm.tag, tm.fid);
	Remove =>
		deletefid(tm.fid);
		otm = ref OTmsg.Remove(tm.tag, tm.fid);
	Stat =>
		otm = ref OTmsg.Stat(tm.tag, tm.fid);
	Wstat =>
		otm = ref OTmsg.Wstat(tm.tag, tm.fid, nd2od(tm.stat));
	* =>
		fatal("bad T message");
	}
	if(otm == nil && rm == nil || otm != nil && rm != nil)
		fatal("both nil or not in ns2os");
	return (otm, rm);
}

# R messages: old to new
os2ns(orm0: ref ORmsg): ref Rmsg
{
	rm: ref Rmsg;

	rm = nil;
	pick orm := orm0{
	Error =>
		rm = ref Rmsg.Error(orm.tag, orm.err);
	Flush =>
		rm = ref Rmsg.Flush(orm.tag);
	Clone =>
		rm = ref Rmsg.Walk(orm.tag, nil);
	Walk =>
		setfid(orm.fid, orm.qid);
		rm = ref Rmsg.Walk(orm.tag, array[1] of { * => oq2nq(orm.qid) });
	Open =>
		setfid(orm.fid, orm.qid);
		rm = ref Rmsg.Open(orm.tag, oq2nq(orm.qid), 0);
	Create =>
		setfid(orm.fid, orm.qid);
		rm = ref Rmsg.Create(orm.tag, oq2nq(orm.qid), 0);
	Read =>
		fp := findfid(orm.fid);
		data := orm.data;
		if(fp != nil && fp.qid.path&OSys->CHDIR)
			data = ods2nds(fp, data);
		rm = ref Rmsg.Read(orm.tag, data);
	Write =>
		rm = ref Rmsg.Write(orm.tag, orm.count);
	Clunk =>
		rm = ref Rmsg.Clunk(orm.tag);
	Remove =>
		rm = ref Rmsg.Remove(orm.tag);
	Stat =>
		rm = ref Rmsg.Stat(orm.tag, od2nd(orm.stat));
	Wstat =>
		rm = ref Rmsg.Wstat(orm.tag);
	Attach =>
		setfid(orm.fid, orm.qid);
		rm = ref Rmsg.Attach(orm.tag, oq2nq(orm.qid));
	* =>
		fatal("bad R message");
	}
	if(rm == nil)
		fatal("nil in os2ns");
	return rm;
}

styxconv(fd1: ref Sys->FD, fd2: ref Sys->FD, c: chan of int)
{
	c <-= sys->pctl(0, nil);
	for(;;){
		tm := Trecv(fd1);
		(otm, rm) := ns2os(tm, fd2);
		if(otm != nil){
			Tsend(fd2, otm);
			orm := Rrecv(fd2);
			rm = os2ns(orm);
		}
		Rsend(fd1, rm);	
	}
}
