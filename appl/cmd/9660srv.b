implement ISO9660;

include "sys.m";
	sys: Sys;
	Dir, Qid, QTDIR, QTFILE, DMDIR: import sys;

include "draw.m";

include "daytime.m";
	daytime:	Daytime;

include "string.m";
	str: String;

include "styx.m";
	styx: Styx;
	Rmsg, Tmsg: import styx;

include "arg.m";

ISO9660: module
{
	init:	fn(nil: ref Draw->Context, nil: list of string);
};

Sectorsize: con 2048;
Maxname: con 256;

Enonexist:	con "file does not exist";
Eperm:	con "permission denied";
Enofile:	con "no file system specified";
Eauth:	con "authentication failed";
Ebadfid:	con	"invalid fid";
Efidinuse:	con	"fid already in use";
Enotdir:	con	"not a directory";
Esyntax:	con	"file name syntax";

devname: string;

chatty := 0;
showstyx := 0;
progname := "9660srv";
stderr: ref Sys->FD;
noplan9 := 0;
nojoliet := 0;
norock := 0;

usage()
{
	sys->fprint(sys->fildes(2), "usage: %s [-rabc] [-9JR] [-s] cd_device dir\n", progname);
	raise "fail:usage";
}

init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;

	sys->pctl(Sys->FORKFD|Sys->NEWPGRP, nil);
	stderr = sys->fildes(2);

	if(args != nil)
		progname = hd args;
	styx = load Styx Styx->PATH;
	if(styx == nil)
		noload(Styx->PATH);
	styx->init();

	if(args != nil)
		progname = hd args;
	mountopt := Sys->MREPL;
	copt := 0;
	stdio := 0;

	arg := load Arg Arg->PATH;
	if(arg == nil)
		noload(Arg->PATH);
	arg->init(args);
	while((c := arg->opt()) != 0)
		case c {
		'v' or 'D' => chatty = 1; showstyx = 1;
		'r' => mountopt = Sys->MREPL;
		'a' => mountopt = Sys->MAFTER;
		'b' => mountopt = Sys->MBEFORE;
		'c' => copt = Sys->MCREATE;
		's' => stdio = 1;
		'9' => noplan9 = 1;
		'J' => nojoliet = 1;
		'R' => norock = 1;
		* => usage();
		}
	args = arg->argv();
	arg = nil;

	if(args == nil || tl args == nil)
		usage();
	what := hd args;
	mountpt := hd tl args;

	daytime = load Daytime Daytime->PATH;
	if(daytime == nil)
		noload(Daytime->PATH);

	iobufinit(Sectorsize);

	pip := array[2] of ref Sys->FD;
	if(stdio){
		pip[0] = sys->fildes(0);
		pip[1] = sys->fildes(1);
	}else
		if(sys->pipe(pip) < 0)
			error(sys->sprint("can't create pipe: %r"));

	devname = what;

	sync := chan of int;
	spawn fileserve(pip[1], sync);
	<-sync;

	if(sys->mount(pip[0], nil, mountpt, mountopt|copt, nil) < 0) {
		sys->fprint(sys->fildes(2), "%s: mount %s %s failed: %r\n", progname, what, mountpt);
		exit;
	}
}

noload(s: string)
{
	sys->fprint(sys->fildes(2), "%s: can't load %s: %r\n", progname, s);
	raise "fail:load";
}

error(p: string)
{
	sys->fprint(sys->fildes(2), "9660srv: %s\n", p);
	raise "fail:error";
}

fileserve(rfd: ref Sys->FD, sync: chan of int)
{
	sys->pctl(Sys->NEWFD|Sys->FORKNS, list of {2, rfd.fd});
	rfd = sys->fildes(rfd.fd);
	stderr = sys->fildes(2);
	sync <-= 1;
	while((m := Tmsg.read(rfd, 0)) != nil){
		if(showstyx)
			chat(sys->sprint("%s...", m.text()));
		r: ref Rmsg;
		pick t := m {
		Readerror =>
			error(sys->sprint("mount read error: %s", t.error));
		Version =>
 			r = rversion(t);
		Auth =>
			r = rauth(t);
		Flush =>
 			r = rflush(t);
		Attach =>
 			r = rattach(t);
		Walk =>
 			r = rwalk(t);
		Open =>
 			r = ropen(t);
		Create =>
 			r = rcreate(t);
		Read =>
 			r = rread(t);
		Write =>
 			r = rwrite(t);
		Clunk =>
 			r = rclunk(t);
		Remove =>
 			r = rremove(t);
		Stat =>
 			r = rstat(t);
		Wstat =>
 			r = rwstat(t);
		* =>
			error(sys->sprint("invalid T-message tag: %d", tagof m));
		}
		pick e := r {
		Error =>
			r.tag = m.tag;
		}
		rbuf := r.pack();
		if(rbuf == nil)
			error("bad R-message conversion");
		if(showstyx)
			chat(r.text()+"\n");
		if(styx->write(rfd, rbuf, len rbuf) != len rbuf)
			error(sys->sprint("connection write error: %r"));
	}

	if(chatty)
		chat("server end of file\n");
}

E(s: string): ref Rmsg.Error
{
	return ref Rmsg.Error(0, s);
}

rversion(t: ref Tmsg.Version): ref Rmsg
{
	(msize, version) := styx->compatible(t, Styx->MAXRPC, Styx->VERSION);
	return ref Rmsg.Version(t.tag, msize, version);
}

rauth(t: ref Tmsg.Auth): ref Rmsg
{
	return ref Rmsg.Error(t.tag, "authentication not required");
}

rflush(t: ref Tmsg.Flush): ref Rmsg
{
	return ref Rmsg.Flush(t.tag);
}

rattach(t: ref Tmsg.Attach): ref Rmsg
{
	dname := devname;
	if(t.aname != "")
		dname = t.aname;
	(dev, err) := devattach(dname, Sys->OREAD, Sectorsize);
	if(dev == nil)
		return E(err);

	xf := Xfs.new(dev);
	root := cleanfid(t.fid);
	root.qid = Sys->Qid(big 0, 0, Sys->QTDIR);
	root.xf = xf;
	err = root.attach();
	if(err != nil){
		clunkfid(t.fid);
		return E(err);
	}
	xf.rootqid = root.qid;
	return ref Rmsg.Attach(t.tag, root.qid);
}

walk1(f: ref Xfile, name: string): string
{
	if(!(f.qid.qtype & Sys->QTDIR))
		return Enotdir;
	case name {
	"." =>
		return nil;	# nop, but shouldn't happen
	".." =>
		if(f.qid.path==f.xf.rootqid.path)
			return nil;
		return f.walkup();
	* =>
		return f.walk(name);
	}
}

rwalk(t: ref Tmsg.Walk): ref Rmsg
{
	f:=findfid(t.fid);
	if(f == nil)
		return E(Ebadfid);
	nf, sf: ref Xfile;
	if(t.newfid != t.fid){
		nf = cleanfid(t.newfid);
		if(nf == nil)
			return E(Efidinuse);
		f.clone(nf);
		f = nf;
	}else
		sf = f.save();

	qids: array of Sys->Qid;
	if(len t.names > 0){
		qids = array[len t.names] of Sys->Qid;
		for(i := 0; i < len t.names; i++){
			e := walk1(f, t.names[i]);
			if(e != nil){
				if(nf != nil){
					nf.clunk();
					clunkfid(t.newfid);
				}else
					f.restore(sf);
				if(i == 0)
					return E(e);
				return ref Rmsg.Walk(t.tag, qids[0:i]);
			}
			qids[i] = f.qid;
		}
	}
	return ref Rmsg.Walk(t.tag, qids);
}

ropen(t: ref Tmsg.Open): ref Rmsg
{
	f := findfid(t.fid);
	if(f == nil)
		return E(Ebadfid);
	if(f.flags&Omodes)
		return E("open on open file");
	e := f.open(t.mode);
	if(e != nil)
		return E(e);
	f.flags = openflags(t.mode);
	return ref Rmsg.Open(t.tag, f.qid, Styx->MAXFDATA);
}

rcreate(t: ref Tmsg.Create): ref Rmsg
{
	name := t.name;
	if(name == "." || name == "..")
		return E(Esyntax);
	f := findfid(t.fid);
	if(f == nil)
		return E(Ebadfid);
	if(f.flags&Omodes)
		return E("create on open file");
	if(!(f.qid.qtype&Sys->QTDIR))
		return E("create in non-directory");
	e := f.create(name, t.perm, t.mode);
	if(e != nil)
		return E(e);
	f.flags = openflags(t.mode);
	return ref Rmsg.Create(t.tag, f.qid, Styx->MAXFDATA);
}

rread(t: ref Tmsg.Read): ref Rmsg
{
	err: string;

	f := findfid(t.fid);
	if(f == nil)
		return E(Ebadfid);
	if (!(f.flags&Oread))
		return E("file not opened for reading");
	if(t.count < 0 || t.offset < big 0)
		return E("negative offset or count");
	b := array[Styx->MAXFDATA] of byte;
	count: int;
	if(f.qid.qtype & Sys->QTDIR)
		(count, err) = f.readdir(b, int t.offset, t.count);
	else
		(count, err) = f.read(b, int t.offset, t.count);
	if(err != nil)
		return E(err);
	if(count != len b)
		b = b[0:count];
	return ref Rmsg.Read(t.tag, b);
}

rwrite(nil: ref Tmsg.Write): ref Rmsg
{
	return E(Eperm);
}

rclunk(t: ref Tmsg.Clunk): ref Rmsg
{
	f := findfid(t.fid);
	if(f == nil)
		return E(Ebadfid);
	f.clunk();
	clunkfid(t.fid);
	return ref Rmsg.Clunk(t.tag);
}

rremove(t: ref Tmsg.Remove): ref Rmsg
{
	f := findfid(t.fid);
	if(f == nil)
		return E(Ebadfid);
	f.clunk();
	clunkfid(t.fid);
	return E(Eperm);
}

rstat(t: ref Tmsg.Stat): ref Rmsg
{
	f := findfid(t.fid);
	if(f == nil)
		return E(Ebadfid);
	(dir, nil) := f.stat();
	return ref Rmsg.Stat(t.tag, *dir);
}

rwstat(nil: ref Tmsg.Wstat): ref Rmsg
{
	return E(Eperm);
}

openflags(mode: int): int
{
	flags := 0;
	case mode & ~(Sys->OTRUNC|Sys->ORCLOSE) {
	Sys->OREAD =>
		flags = Oread;
	Sys->OWRITE =>
		flags = Owrite;
	Sys->ORDWR =>
		flags = Oread|Owrite;
	}
	if(mode & Sys->ORCLOSE)
		flags |= Orclose;
	return flags;
}

chat(s: string)
{
	if(chatty)
		sys->fprint(stderr, "%s", s);
}

Fid: adt {
	fid:	int;
	file:	ref Xfile;
};

FIDMOD: con 127;	# prime
fids := array[FIDMOD] of list of ref Fid;

hashfid(fid: int): (ref Fid, array of list of ref Fid)
{
	nl: list of ref Fid;

	hp := fids[fid%FIDMOD:];
	nl = nil;
	for(l := hp[0]; l != nil; l = tl l){
		f := hd l;
		if(f.fid == fid){
			l = tl l;	# excluding f
			for(; nl != nil; nl = tl nl)
				l = (hd nl) :: l;	# put examined ones back, in order
			hp[0] = l;
			return (f, hp);
		} else
			nl = f :: nl;
	}
	return (nil, hp);
}

findfid(fid: int): ref Xfile
{
	(f, hp) := hashfid(fid);
	if(f == nil){
		chat("unassigned fid");
		return nil;
	}
	hp[0] = f :: hp[0];
	return f.file;
}

cleanfid(fid: int): ref Xfile
{
	(f, hp) := hashfid(fid);
	if(f != nil){
		chat("fid in use");
		return nil;
	}
	f = ref Fid;
	f.fid = fid;
	f.file = Xfile.new();
	hp[0] = f :: hp[0];
	return f.file.clean();
}

clunkfid(fid: int)
{
	(f, nil) := hashfid(fid);
	if(f != nil)
		f.file.clean();
}

#
#
#

Xfs: adt {
	d:	ref Device;
	inuse:	int;
	issusp:	int;	# system use sharing protocol in use?
	suspoff:	int;	# LEN_SKP, if so
	isplan9:	int;	# has Plan 9-specific directory info
	isrock:	int;	# is rock ridge
	rootqid:	Sys->Qid;
	ptr:	int;	# tag for private data

	new:	fn(nil: ref Device): ref Xfs;
	incref:	fn(nil: self ref Xfs);
	decref:	fn(nil: self ref Xfs);
};

Xfile:	adt {
	xf:	ref Xfs;
	flags:	int;
	qid:	Sys->Qid;
	ptr:	ref Isofile;	# tag for private data

	new:		fn(): ref Xfile;
	clean:	fn(nil: self ref Xfile): ref Xfile;

	save:		fn(nil: self ref Xfile): ref Xfile;
	restore:	fn(nil: self ref Xfile, s: ref Xfile);

	attach:	fn(nil: self ref Xfile): string;
	clone:	fn(nil: self ref Xfile, nil: ref Xfile);
	walkup:	fn(nil: self ref Xfile): string;
	walk:	fn(nil: self ref Xfile, nil: string): string;
	open:	fn(nil: self ref Xfile, nil: int): string;
	create:	fn(nil: self ref Xfile, nil: string, nil: int, nil: int): string;
	readdir:	fn(nil: self ref Xfile, nil: array of byte, nil: int, nil: int): (int, string);
	read:		fn(nil: self ref Xfile, nil: array of byte, nil: int, nil: int): (int, string);
	write:	fn(nil: self ref Xfile, nil: array of byte, nil: int, nil: int): (int, string);
	clunk:	fn(nil: self ref Xfile);
	remove:	fn(nil: self ref Xfile): string;
	stat:		fn(nil: self ref Xfile): (ref Sys->Dir, string);
	wstat:	fn(nil: self ref Xfile, nil: ref Sys->Dir): string;
};

Oread, Owrite, Orclose: con 1<<iota;
Omodes: con 3;	# mask

VOLDESC: con 16;	# sector number

Drec: adt {
	reclen:	int;
	attrlen:	int;
	addr:	int;	# should be big?
	size:	int;	# should be big?
	date:	array of byte;
	time:	int;
	tzone:	int;	# not in high sierra
	flags:	int;
	unitsize:	int;
	gapsize:	int;
	vseqno:	int;
	name:	array of byte;
	data:	array of byte;	# system extensions
};

Isofile: adt {
	fmt:	int;	# 'z' if iso, 'r' if high sierra
	blksize:	int;
	offset:	int;	# true offset when reading directory
	doffset:	int;	# styx offset when reading directory
	d:	ref Drec;
};

Xfile.new(): ref Xfile
{
	f := ref Xfile;
	return f.clean();
}

Xfile.clean(f: self ref Xfile): ref Xfile
{
	if(f.xf != nil){
		f.xf.decref();
		f.xf = nil;
	}
	f.ptr = nil;
	f.flags = 0;
	f.qid = Qid(big 0, 0, 0);
	return f;
}

Xfile.save(f: self ref Xfile): ref Xfile
{
	s := ref Xfile;
	*s = *f;
	s.ptr = ref *f.ptr;
	s.ptr.d = ref *f.ptr.d;
	return s;
}

Xfile.restore(f: self ref Xfile, s: ref Xfile)
{
	f.flags = s.flags;
	f.qid = s.qid;
	*f.ptr = *s.ptr;
}

Xfile.attach(root: self ref Xfile): string
{
	fmt := 0;
	blksize := 0;
	haveplan9 := 0;
	dirp: ref Block;
	dp := ref Drec;
	for(a:=VOLDESC;a<VOLDESC+100;a++){
		p := Block.get(root.xf.d, a);
		if(p == nil){
			if(dirp != nil)
				dirp.put();
			return "can't read volume descriptor";
		}
		v := p.data;	# Voldesc
		if(eqs(v[0:7], "\u0001CD001\u0001")){		# ISO
			if(dirp != nil)
				dirp.put();
			dirp = p;
			fmt = 'z';
			convM2Drec(v[156:], dp, 0);	# v.z.desc.rootdir
			blksize = l16(v[128:]);	# v.z.desc.blksize
			if(chatty)
				chat(sys->sprint("iso, blksize=%d...", blksize));
			haveplan9 = eqs(v[8:8+6], "PLAN 9");	# v.z.boot.sysid
			if(haveplan9){
				if(noplan9) {
					chat("ignoring plan9");
					haveplan9 = 0;
				}else{
					fmt = '9';
					chat("plan9 iso...");
				}
			}
			continue;
		}
		if(eqs(v[8:8+7], "\u0001CDROM\u0001")){	# high sierra
			if(dirp != nil)
				dirp.put();
			dirp = p;
			fmt = 'r';
			convM2Drec(v[180:], dp, 1);	# v.r.desc.rootdir
			blksize = l16(v[136:]);	# v.r.desc.blksize
			if(chatty)
				chat(sys->sprint("high sierra, blksize=%d...", blksize));
			continue;
		}
		if(haveplan9==0 && !nojoliet && eqs(v[0:7], "\u0002CD001\u0001")){
			q := v[88:];	# v.z.desc.escapes
			if(q[0] == byte 16r25 && q[1] == byte 16r2F &&
			   (q[2] == byte 16r40 || q[2] == byte 16r43 || q[2] == byte 16r45)){	# joliet, it appears
				if(dirp != nil)
					dirp.put();
				dirp = p;
				fmt = 'J';
				convM2Drec(v[156:], dp, 0);	# v.z.desc.rootdir
				if(blksize != l16(v[128:]))	# v.z.desc.blksize
					sys->fprint(stderr, "9660srv: warning: suspicious Joliet block size: %d\n", l16(v[128:]));
				chat("joliet...");
				continue;
			}
		}else{
			p.put();
			if(v[0] == byte 16rFF)
				break;
		}
	}

	if(fmt ==  0){
		if(dirp != nil)
			dirp.put();
		return "CD format not recognised";
	}

	if(chatty)
		showdrec(stderr, fmt, dp);
	if(blksize > Sectorsize){
		dirp.put();
		return "blocksize too big";
	}
	fp := iso(root);
	root.xf.isplan9 = haveplan9;
	fp.fmt = fmt;
	fp.blksize = blksize;
	fp.offset = 0;
	fp.doffset = 0;
	fp.d = dp;
	root.qid.path = big dp.addr;
	root.qid.qtype = QTDIR;
	root.qid.vers = 0;
	dirp.put();
	dp = ref Drec;
	if(getdrec(root, dp) >= 0){
		s := dp.data;
		n := len s;
		if(n >= 7 && s[0] == byte 'S' && s[1] == byte 'P' && s[2] == byte 7 &&
		   s[3] == byte 1 && s[4] == byte 16rBE && s[5] == byte 16rEF){
			root.xf.issusp = 1;
			root.xf.suspoff = int s[6];
			n -= root.xf.suspoff;
			s = s[root.xf.suspoff:];
			while(n >= 4){
				l := int s[2];
				if(s[0] == byte 'E' && s[1] == byte 'R'){
					if(int s[4] == 10 && eqs(s[8:18], "RRIP_1991A"))
						root.xf.isrock = 1;
					break;
				} else if(s[0] == byte 'C' && s[1] == byte 'E' && int s[2] >= 28){
					(s, n) = getcontin(root.xf.d, s);
					continue;
				} else if(s[0] == byte 'R' && s[1] == byte 'R'){
					if(!norock)
						root.xf.isrock = 1;
					break;	# can skip search for ER
				} else if(s[0] == byte 'S' && s[1] == byte 'T')
					break;
				s = s[l:];
				n -= l;
			}
		}
	}
	if(root.xf.isrock)
		chat("Rock Ridge...");
	fp.offset = 0;
	fp.doffset = 0;
	return nil;
}

Xfile.clone(oldf: self ref Xfile, newf: ref Xfile)
{
	*newf = *oldf;
	newf.ptr = nil;
	newf.xf.incref();
	ip := iso(oldf);
	np := iso(newf);
	*np = *ip;	# might not be right; shares ip.d
}

Xfile.walkup(f: self ref Xfile): string
{
	pf := Xfile.new();
	ppf := Xfile.new();
	e := walkup(f, pf, ppf);
	pf.clunk();
	ppf.clunk();
	return e;
}

walkup(f, pf, ppf: ref Xfile): string
{
	e := opendotdot(f, pf);
	if(e != nil)
		return sys->sprint("can't open pf: %s", e);
	paddr := iso(pf).d.addr;
	if(iso(f).d.addr == paddr)
		return nil;
	e = opendotdot(pf, ppf);
	if(e != nil)
		return sys->sprint("can't open ppf: %s", e);
	d := ref Drec;
	while(getdrec(ppf, d) >= 0){
		if(d.addr == paddr){
			newdrec(f, d);
			f.qid.path = big paddr;
			f.qid.qtype = QTDIR;
			f.qid.vers = 0;
			return nil;
		}
	}
	return "can't find addr of ..";
}

Xfile.walk(f: self ref Xfile, name: string): string
{
	ip := iso(f);
	if(!f.xf.isplan9){
		for(i := 0; i < len name; i++)
			if(name[i] == ';')
				break;
		if(i >= Maxname)
			i = Maxname-1;
		name = name[0:i];
	}
	if(chatty)
		chat(sys->sprint("%d \"%s\"...", len name, name));
	ip.offset = 0;
	dir := ref Dir;
	d := ref Drec;
	while(getdrec(f, d) >= 0) {
		dvers := rzdir(f.xf, dir, ip.fmt, d);
		if(name != dir.name)
			continue;
		newdrec(f, d);
		f.qid.path = dir.qid.path;
		f.qid.qtype = dir.qid.qtype;
		f.qid.vers = dir.qid.vers;
		if(dvers){
			# versions ignored
		}
		return nil;
	}
	return Enonexist;
}

Xfile.open(f: self ref Xfile, mode: int): string
{
	if(mode != Sys->OREAD)
		return Eperm;
	ip := iso(f);
	ip.offset = 0;
	ip.doffset = 0;
	return nil;
}

Xfile.create(nil: self ref Xfile, nil: string, nil: int, nil: int): string
{
	return Eperm;
}

Xfile.readdir(f: self ref Xfile, buf: array of byte, offset: int, count: int): (int, string)
{
	ip := iso(f);
	d := ref Dir;
	drec := ref Drec;
	if(offset < ip.doffset){
		ip.offset = 0;
		ip.doffset = 0;
	}
	rcnt := 0;
	while(rcnt < count && getdrec(f, drec) >= 0){
		if(len drec.name == 1){
			if(drec.name[0] == byte 0)
				continue;
			if(drec.name[0] == byte 1)
				continue;
		}
		rzdir(f.xf, d, ip.fmt, drec);
		d.qid.vers = f.qid.vers;
		a := styx->packdir(*d);
		if(ip.doffset < offset){
			ip.doffset += len a;
			continue;
		}
		if(rcnt+len a > count)
			break;
		buf[rcnt:] = a;		# BOTCH: copy
		rcnt += len a;
	}
	ip.doffset += rcnt;
	return (rcnt, nil);
}

Xfile.read(f: self ref Xfile, buf: array of byte, offset: int, count: int): (int, string)
{
	ip := iso(f);
	if(offset >= ip.d.size)
		return (0, nil);
	if(offset+count > ip.d.size)
		count = ip.d.size - offset;
	addr := (ip.d.addr+ip.d.attrlen)*ip.blksize + offset;
	o := addr % Sectorsize;
	addr /= Sectorsize;
	if(chatty)
		chat(sys->sprint("d.addr=0x%x, addr=0x%x, o=0x%x...", ip.d.addr, addr, o));
	n := Sectorsize - o;
	rcnt := 0;
	while(count > 0){
		if(n > count)
			n = count;
		p := Block.get(f.xf.d, addr);
		if(p == nil)
			return (-1, "i/o error");
		buf[rcnt:] = p.data[o:o+n];
		p.put();
		count -= n;
		rcnt += n;
		addr++;
		o = 0;
		n = Sectorsize;
	}
	return (rcnt, nil);
}

Xfile.write(nil: self ref Xfile, nil: array of byte, nil: int, nil: int): (int, string)
{
	return (-1, Eperm);
}

Xfile.clunk(f: self ref Xfile)
{
	f.ptr = nil;
}

Xfile.remove(nil: self ref Xfile): string
{
	return Eperm;
}

Xfile.stat(f: self ref Xfile): (ref Dir, string)
{
	ip := iso(f);
	d := ref Dir;
	rzdir(f.xf, d, ip.fmt, ip.d);
	d.qid.vers = f.qid.vers;
	if(d.qid.path==f.xf.rootqid.path){
		d.qid.path = big 0;
		d.qid.qtype = QTDIR;
	}
	return (d, nil);
}

Xfile.wstat(nil: self ref Xfile, nil: ref Dir): string
{
	return Eperm;
}

Xfs.new(d: ref Device): ref Xfs
{
	xf := ref Xfs;
	xf.inuse = 1;
	xf.d = d;
	xf.isplan9 = 0;
	xf.issusp = 0;
	xf.isrock = 0;
	xf.suspoff = 0;
	xf.ptr = 0;
	xf.rootqid = Qid(big 0, 0, QTDIR);
	return xf;
}

Xfs.incref(xf: self ref Xfs)
{
	xf.inuse++;
}

Xfs.decref(xf: self ref Xfs)
{
	xf.inuse--;
	if(xf.inuse == 0){
		if(xf.d != nil)
			xf.d.detach();
	}
}

showdrec(fd: ref Sys->FD, fmt: int, d: ref Drec)
{
	if(d.reclen == 0)
		return;
	sys->fprint(fd, "%d %d %d %d ",
		d.reclen, d.attrlen, d.addr, d.size);
	sys->fprint(fd, "%s 0x%2.2x %d %d %d ",
		rdate(d.date, fmt), d.flags,
		d.unitsize, d.gapsize, d.vseqno);
	sys->fprint(fd, "%d %s", len d.name, nstr(d.name));
	syslen := len d.data;
	if(syslen != 0)
		sys->fprint(fd, " %s", nstr(d.data));
	sys->fprint(fd, "\n");
}

newdrec(f: ref Xfile, dp: ref Drec)
{
	x := iso(f);
	n := ref Isofile;
	n.fmt = x.fmt;
	n.blksize = x.blksize;
	n.offset = 0;
	n.doffset = 0;
	n.d = dp;
	f.ptr = n;
}

getdrec(f: ref Xfile, d: ref Drec): int
{
	if(f.ptr == nil)
		return -1;
	boff := 0;
	ip := iso(f);
	size := ip.d.size;
	while(ip.offset<size){
		addr := (ip.d.addr+ip.d.attrlen)*ip.blksize + ip.offset;
		boff = addr % Sectorsize;
		if(boff > Sectorsize-34){
			ip.offset += Sectorsize-boff;
			continue;
		}
		p := Block.get(f.xf.d, addr/Sectorsize);
		if(p == nil)
			return -1;
		nb := int p.data[boff];
		if(nb >= 34) {
			convM2Drec(p.data[boff:], d, ip.fmt=='r');
			#chat(sys->sprint("off %d", ip.offset));
			#showdrec(stderr, ip.fmt, d);
			p.put();
			ip.offset += nb + (nb&1);
			return 0;
		}
		p.put();
		p = nil;
		ip.offset += Sectorsize-boff;
	}
	return -1;
}

# getcontin returns a slice of the Iobuf, valid until next i/o call
getcontin(d: ref Device, a: array of byte): (array of byte, int)
{
	bn := l32(a[4:]);
	off := l32(a[12:]);
	n := l32(a[20:]);
	p := Block.get(d, bn);
	if(p == nil)
		return (nil, 0);
	return (p.data[off:off+n], n);
}

iso(f: ref Xfile): ref Isofile
{
	if(f.ptr == nil){
		f.ptr = ref Isofile;
		f.ptr.d = ref Drec;
	}
	return f.ptr;
}

opendotdot(f: ref Xfile, pf: ref Xfile): string
{
	d := ref Drec;
	ip := iso(f);
	ip.offset = 0;
	if(getdrec(f, d) < 0)
		return "opendotdot: getdrec(.) failed";
	if(len d.name != 1 || d.name[0] != byte 0)
		return "opendotdot: no . entry";
	if(d.addr != ip.d.addr)
		return "opendotdot: bad . address";
	if(getdrec(f, d) < 0)
		return "opendotdot: getdrec(..) failed";
	if(len d.name != 1 || d.name[0] != byte 1)
		return "opendotdot: no .. entry";

	pf.xf = f.xf;
	pip := iso(pf);
	pip.fmt = ip.fmt;
	pip.blksize = ip.blksize;
	pip.offset = 0;
	pip.doffset = 0;
	pip.d = d;
	return nil;
}

rzdir(fs: ref Xfs, d: ref Dir, fmt: int, dp: ref Drec): int
{
	Hmode, Hname: con 1<<iota;
	vers := -1;
	have := 0;
	d.qid.path = big dp.addr;
	d.qid.vers = 0;
	d.qid.qtype = QTFILE;
	n := len dp.name;
	if(n == 1) {
		case int dp.name[0] {
		0 => d.name = "."; have |= Hname;
		1 =>	d.name = ".."; have |= Hname;
		* =>	d.name = ""; d.name[0] = tolower(int dp.name[0]);
		}
	} else {
		if(fmt == 'J'){	# Joliet, 16-bit Unicode
			d.name = "";
			for(i:=0; i<n; i+=2){
				r := (int dp.name[i]<<8) | int dp.name[i+1];
				d.name[len d.name] = r;
			}
		}else{
			if(n >= Maxname)
				n = Maxname-1;
			d.name = "";
			for(i:=0; i<n && int dp.name[i] != '\r'; i++)
				d.name[i] = tolower(int dp.name[i]);
		}
	}

	if(fs.isplan9 && dp.reclen>34+len dp.name) {
		#
		# get gid, uid, mode and possibly name
		# from plan9 directory extension
		#
		s := dp.data;
		n = int s[0];
		if(n)
			d.name = string s[1:1+n];
		l := 1+n;
		n = int s[l++];
		d.uid = string s[l:l+n];
		l += n;
		n = int s[l++];
		d.gid = string s[l:l+n];
		l += n;
		if(l & 1)
			l++;
		d.mode = l32(s[l:]);
		if(d.mode & DMDIR)
			d.qid.qtype = QTDIR;
	} else {
		d.mode = 8r444;
		case fmt {
		'z' =>
			if(fs.isrock)
				d.gid = "ridge";
			else
				d.gid = "iso";
		'r' =>
			d.gid = "sierra";
		'J' =>
			d.gid = "joliet";
		* =>
			d.gid = "???";
		}
		flags := dp.flags;
		if(flags & 2){
			d.qid.qtype = QTDIR;
			d.mode |= DMDIR|8r111;
		}
		d.uid = "cdrom";
		for(i := 0; i < len d.name; i++)
			if(d.name[i] == ';') {
				vers = int string d.name[i+1:];	# inefficient
				d.name = d.name[0:i];	# inefficient
				break;
			}
		n = len dp.data - fs.suspoff;
		if(fs.isrock && n >= 4){
			s := dp.data[fs.suspoff:];
			nm := 0;
			while(n >= 4 && have != (Hname|Hmode)){
				l := int s[2];
				if(s[0] == byte 'P' && s[1] == byte 'X' && s[3] == byte 1){
					# posix file attributes
					mode := l32(s[4:12]);
					d.mode = mode & 8r777;
					if((mode & 8r170000) == 8r0040000){
						d.mode |= DMDIR;
						d.qid.qtype = QTDIR;
					}
					have |= Hmode;
				} else if(s[0] == byte 'N' && s[1] == byte 'M' && s[3] == byte 1){
					# alternative name
					flags = int s[4];
					if((flags & ~1) == 0){
						if(nm == 0){
							d.name = string s[5:l];
							nm = 1;
						} else
							d.name += string s[5:l];
						if(flags == 0)
							have |= Hname;	# no more
					}
				} else if(s[0] == byte 'C' && s[1] == byte 'E' && int s[2] >= 28){
					(s, n) = getcontin(fs.d, s);
					continue;
				} else if(s[0] == byte 'S' && s[1] == byte 'T')
					break;
				n -= l;
				s = s[l:];
			}
		}
	}
	d.length = big 0;
	if((d.mode & DMDIR) == 0)
		d.length = big dp.size;
	d.dtype = 0;
	d.dev = 0;
	d.atime = dp.time;
	d.mtime = d.atime;
	return vers;
}

convM2Drec(a: array of byte, d: ref Drec, highsierra: int)
{
	d.reclen = int a[0];
	d.attrlen = int a[1];
	d.addr = int l32(a[2:10]);
	d.size = int l32(a[10:18]);
	d.time = gtime(a[18:24]);
	d.date = array[7] of byte;
	d.date[0:] = a[18:25];
	if(highsierra){
		d.tzone = 0;
		d.flags = int a[24];
		d.unitsize = 0;
		d.gapsize = 0;
		d.vseqno = 0;
	} else {
		d.tzone = int a[24];
		d.flags = int a[25];
		d.unitsize = int a[26];
		d.gapsize = int a[27];
		d.vseqno = l32(a[28:32]);
	}
	n := int a[32];
	d.name = array[n] of byte;
	d.name[0:] = a[33:33+n];
	n += 33;
	if(n & 1)
		n++;	# check this
	syslen := d.reclen - n;
	if(syslen > 0){
		d.data = array[syslen] of byte;
		d.data[0:] = a[n:n+syslen];
	} else
		d.data = nil;
}

nstr(p: array of byte): string
{
	q := "";
	n := len p;
	for(i := 0; i < n; i++){
		if(int p[i] == '\\')
			q[len q] = '\\';
		if(' ' <= int p[i] && int p[i] <= '~')
			q[len q] = int p[i];
		else
			q += sys->sprint("\\%2.2ux", int p[i]);
	}
	return q;
}

rdate(p: array of byte, fmt: int): string
{
	c: int;

	s := sys->sprint("%2.2d.%2.2d.%2.2d %2.2d:%2.2d:%2.2d",
		int p[0], int p[1], int p[2], int p[3], int p[4], int p[5]);
	if(fmt == 'z'){
		htz := int p[6];
		if(htz >= 128){
			htz = 256-htz;
			c = '-';
		}else
			c = '+';
		s += sys->sprint(" (%c%.1f)", c, real htz/2.0);
	}
	return s;
}

dmsize := array[] of {
	31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31,
};

dysize(y: int): int
{
	if((y%4) == 0)
		return 366;
	return 365;
}

gtime(p: array of byte): int	# yMdhms
{
	y:=int p[0]; M:=int p[1]; d:=int p[2];
	h:=int p[3]; m:=int p[4]; s:=int p[5];;
	if(y < 70)
		return 0;
	if(M < 1 || M > 12)
		return 0;
	if(d < 1 || d > dmsize[M-1])
		return 0;
	if(h > 23)
		return 0;
	if(m > 59)
		return 0;
	if(s > 59)
		return 0;
	y += 1900;
	t := 0;
	for(i:=1970; i<y; i++)
		t += dysize(i);
	if(dysize(y)==366 && M >= 3)
		t++;
	M--;
	while(M-- > 0)
		t += dmsize[M];
	t += d-1;
	t = 24*t + h;
	t = 60*t + m;
	t = 60*t + s;
	return t;
}

l16(p: array of byte): int
{
	v := (int p[1]<<8)| int p[0];
	if (v >= 16r8000)
		v -= 16r10000;
	return v;
}

l32(p: array of byte): int
{
	return (((((int p[3]<<8)| int p[2])<<8)| int p[1])<<8)| int p[0];
}

eqs(a: array of byte, b: string): int
{
	if(len a != len b)
		return 0;
	for(i := 0; i < len a; i++)
		if(int a[i] != b[i])
			return 0;
	return 1;
}

tolower(c: int): int
{
	if(c >= 'A' && c <= 'Z')
		return c-'A' + 'a';
	return c;
}

#
# I/O buffers
#

Device: adt {
	inuse:	int;	# attach count
	name:	string;	# of underlying file
	fd:	ref Sys->FD;
	sectorsize:	int;
	qid:	Sys->Qid;	# (qid,dtype,dev) identify uniquely
	dtype:	int;
	dev:	int;

	detach:	fn(nil: self ref Device);
};

Block: adt {
	dev:	ref Device;
	addr:	int;
	data:	array of byte;

	# internal
	next:	cyclic ref Block;
	prev:	cyclic ref Block;
	busy:	int;

	get:	fn(nil: ref Device, addr: int): ref Block;
	put:	fn(nil: self ref Block);
};

devices:	list of ref Device;

NIOB:	con 100;	# for starters
HIOB:	con 127;	# prime

hiob := array[HIOB] of list of ref Block;	# hash buckets
iohead:	ref Block;
iotail:	ref Block;
bufsize := 0;

iobufinit(bsize: int)
{
	bufsize = bsize;
	for(i:=0; i<NIOB; i++)
		newblock();
}

newblock(): ref Block
{
	p := ref Block;
	p.busy = 0;
	p.addr = -1;
	p.dev = nil;
	p.data = array[bufsize] of byte;
	p.next = iohead;
	if(iohead != nil)
		iohead.prev = p;
	iohead = p;
	if(iotail == nil)
		iotail = p;
	return p;
}

Block.get(dev: ref Device, addr: int): ref Block
{
	p: ref Block;

	dh := hiob[addr%HIOB:];
	for(l := dh[0]; l != nil; l = tl l) {
		p = hd l;
		if(p.addr == addr && p.dev == dev) {
			p.busy++;
			return p;
		}
	}
	# Find a non-busy buffer from the tail
	for(p = iotail; p != nil && p.busy; p = p.prev)
		;
	if(p == nil)
		p = newblock();

	# Delete from hash chain
	if(p.addr >= 0) {
		hp := hiob[p.addr%HIOB:];
		l = nil;
		for(f := hp[0]; f != nil; f = tl f)
			if(hd f != p)
				l = (hd f) :: l;
		hp[0] = l;
	}

	# Hash and fill
	p.addr = addr;
	p.dev = dev;
	p.busy++;
	sys->seek(dev.fd, big addr*big dev.sectorsize, 0);
	if(sys->read(dev.fd, p.data, dev.sectorsize) != dev.sectorsize){
		p.addr = -1;	# stop caching
		p.put();
		purge(dev);
		return nil;
	}
	dh[0] = p :: dh[0];
	return p;
}

Block.put(p: self ref Block)
{
	p.busy--;
	if(p.busy < 0)
		panic("Block.put");

	if(p == iohead)
		return;

	# Link onto head for lru
	if(p.prev != nil) 
		p.prev.next = p.next;
	else
		iohead = p.next;

	if(p.next != nil)
		p.next.prev = p.prev;
	else
		iotail = p.prev;

	p.prev = nil;
	p.next = iohead;
	iohead.prev = p;
	iohead = p;
}

purge(dev: ref Device)
{
	for(i := 0; i < HIOB; i++){
		l := hiob[i];
		hiob[i] = nil;
		for(; l != nil; l = tl l){	# reverses bucket's list, but never mind
			p := hd l;
			if(p.dev == dev)
				p.busy = 0;
			else
				hiob[i] = p :: hiob[i];
		}
	}
}

devattach(name: string, mode: int, sectorsize: int): (ref Device, string)
{
	if(sectorsize > bufsize)
		return (nil, "sector size too big");
	fd := sys->open(name, mode);
	if(fd == nil)
		return(nil, sys->sprint("%s: can't open: %r", name));
	(rc, dir) := sys->fstat(fd);
	if(rc < 0)
		return (nil, sys->sprint("%r"));
	for(dl := devices; dl != nil; dl = tl dl){
		d := hd dl;
		if(d.qid.path != dir.qid.path || d.qid.vers != dir.qid.vers)
			continue;
		if(d.dtype != dir.dtype || d.dev != dir.dev)
			continue;
		d.inuse++;
		if(chatty)
			sys->print("inuse=%d, \"%s\", dev=%H...\n", d.inuse, d.name, d.fd);
		return (d, nil);
	}
	if(chatty)
		sys->print("alloc \"%s\", dev=%H...\n", name, fd);
	d := ref Device;
	d.inuse = 1;
	d.name = name;
	d.qid = dir.qid;
	d.dtype = dir.dtype;
	d.dev = dir.dev;
	d.fd = fd;
	d.sectorsize = sectorsize;
	devices = d :: devices;
	return (d, nil);
}

Device.detach(d: self ref Device)
{
	d.inuse--;
	if(d.inuse < 0)
		panic("putxdata");
	if(chatty)
		sys->print("decref=%d, \"%s\", dev=%H...\n", d.inuse, d.name, d.fd);
	if(d.inuse == 0){
		if(chatty)
			sys->print("purge...\n");
		purge(d);
		dl := devices;
		devices = nil;
		for(; dl != nil; dl = tl dl)
			if((hd dl) != d)
				devices = (hd dl) :: devices;
	}
}

panic(s: string)
{
	sys->print("panic: %s\n", s);
	a: array of byte;
	a[5] = byte 0; # trap
}
