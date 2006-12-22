implement Dossrv;

include "sys.m";
	sys: Sys;

include "draw.m";

include "arg.m";

include "daytime.m";
	daytime: Daytime;

include "styx.m";
	styx: Styx;
	Tmsg, Rmsg: import styx;

Dossrv: module
{
        init:   fn(ctxt: ref Draw->Context, args: list of string);
        system:   fn(ctxt: ref Draw->Context, args: list of string): string;
};

arg0 := "dossrv";

deffile: string;
pflag := 0;
debug := 0;

usage(iscmd: int): string
{
	sys->fprint(sys->fildes(2), "usage: %s [-v] [-s] [-F] [-c] [-S secpertrack] [-f devicefile] [-m mountpoint]\n", arg0);
	if(iscmd)
		raise "fail:usage";
	return "usage";
}

init(nil: ref Draw->Context, args: list of string)
{
	e := init2(nil, args, 1);
	if(e != nil){
		sys->fprint(sys->fildes(2), "%s: %s\n", arg0, e);
		raise "fail:error";
	}
}

system(nil: ref Draw->Context, args: list of string): string
{
	e := init2(nil, args, 0);
	if(e != nil)
		sys->fprint(sys->fildes(2), "%s: %s\n", arg0, e);
	return e;
}

nomod(s: string): string
{
	return sys->sprint("can't load %s: %r", s);
}

init2(nil: ref Draw->Context, args: list of string, iscmd: int): string
{
	sys = load Sys Sys->PATH;

	pipefd := array[2] of ref Sys->FD;

	srvfile := "/n/dos"; 
	deffile = "";	# no default, for safety
	sectors := 0;
	stdin := 0;

	arg := load Arg Arg->PATH;
	if(arg == nil)
		return nomod(Arg->PATH);
	arg->init(args);
	arg0 = arg->progname();
	while((o := arg->opt()) != 0) {
		case o {
		'v' =>
			if(debug & STYX_MESS)
				debug |= VERBOSE;
			debug |= STYX_MESS;
		'F' =>
			debug |= FAT_INFO;
		'c' =>
			debug |= CLUSTER_INFO;
			iodebug = 1;
		'S' =>
			s := arg->arg();
			if(s != nil && s[0]>='0' && s[0]<='9')
				sectors = int s;
			else
				return usage(iscmd);
		's' =>
			stdin = 1;
		'f' =>
			deffile = arg->arg();
			if(deffile == nil)
				return usage(iscmd);
		'm' =>
			srvfile = arg->arg();
			if(srvfile == nil)
				return usage(iscmd);
		'p' =>
			pflag++;
		* =>
			return usage(iscmd);
		}
	}
	args = arg->argv();
	arg = nil;

	if(deffile == "" || !stdin && srvfile == "")
		return usage(iscmd);

	styx = load Styx Styx->PATH;
	if(styx == nil)
		return nomod(Styx->PATH);
	styx->init();

	daytime = load Daytime Daytime->PATH;
	if(daytime == nil)
		return nomod(Daytime->PATH);

	iotrackinit(sectors);

	if(!stdin) {
		if(sys->pipe(pipefd) < 0)
			return sys->sprint("can't create pipe: %r");
	}else{
		pipefd[0] = nil;
		pipefd[1] = sys->fildes(1);
	}

	dossetup();

	spawn dossrv(pipefd[1]);

	if(!stdin) {
		if(sys->mount(pipefd[0], nil, srvfile, sys->MREPL|sys->MCREATE, deffile) < 0)
			return sys->sprint("mount %s: %r", srvfile);
	}

	return nil;
}

#
# Styx server
#

	Enevermind,
	Eformat,
	Eio,
	Enomem,
	Enonexist,
	Enotdir,
	Enofid,
	Efidopen,
	Efidinuse,
	Eexist,
	Eperm,
	Enofilsys,
	Eauth,
	Econtig,
	Efull,
	Eopen,
	Ephase: con iota;

errmsg := array[] of {
	Enevermind	=> "never mind",
	Eformat		=> "unknown format",
	Eio		=> "I/O error",
	Enomem		=> "server out of memory",
	Enonexist	=> "file does not exist",
	Enotdir => "not a directory",
	Enofid => "no such fid",
	Efidopen => "fid already open",
	Efidinuse => "fid in use",
	Eexist		=> "file exists",
	Eperm		=> "permission denied",
	Enofilsys	=> "no file system device specified",
	Eauth		=> "authentication failed",
	Econtig =>	"out of contiguous disk space",
	Efull =>	"file system full",
	Eopen =>	"invalid open mode",
	Ephase => "phase error -- directory entry not found",
};

e(n: int): ref Rmsg.Error
{
	if(n < 0 || n >= len errmsg)
		return ref Rmsg.Error(0, "it's thermal problems");
	return ref Rmsg.Error(0, errmsg[n]);
}

dossrv(rfd: ref Sys->FD)
{
	sys->pctl(Sys->NEWFD, rfd.fd :: 2 :: nil);
	rfd = sys->fildes(rfd.fd);
	data := array[Styx->MAXRPC] of byte;
	while((t := Tmsg.read(rfd, 0)) != nil){
		if(debug & STYX_MESS)
			chat(sys->sprint("%s...", t.text()));

		r: ref Rmsg;
		pick m := t {
		Readerror =>
			panic(sys->sprint("mount read error: %s", m.error));
		Version =>
 			r = rversion(m);
		Auth =>
			r = rauth(m);
		Flush =>
 			r = rflush(m);
		Attach =>
 			r = rattach(m);
		Walk =>
 			r = rwalk(m);
		Open =>
 			r = ropen(m);
		Create =>
 			r = rcreate(m);
		Read =>
 			r = rread(m);
		Write =>
 			r = rwrite(m);
		Clunk =>
 			r = rclunk(m);
		Remove =>
 			r = rremove(m);
		Stat =>
 			r = rstat(m);
		Wstat =>
 			r = rwstat(m);
		* =>
			panic("Styx mtype");
		}
		pick m := r {
		Error =>
			r.tag = t.tag;
		}
		rbuf := r.pack();
		if(rbuf == nil)
			panic("Rmsg.pack");
		if(debug & STYX_MESS)
			chat(sys->sprint("%s\n", r.text()));
		if(styx->write(rfd, rbuf, len rbuf) != len rbuf)
			panic("mount write");
	}

	if(debug & STYX_MESS)
		chat("server EOF\n");
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
	root := xfile(t.fid, Clean);
	if(root == nil)
		return e(Eio);
	if(t.aname == nil)
		t.aname = deffile;
	(xf, ec) := getxfs(t.aname);
	root.xf = xf;
	if(xf == nil) {
		if(root!=nil)
			xfile(t.fid, Clunk);
		return ref Rmsg.Error(t.tag, ec);
	}
	if(xf.fmt == 0 && dosfs(xf) < 0){
		if(root!=nil)
			xfile(t.fid, Clunk);
		return e(Eformat);
	}

	root.qid = Sys->Qid(big 0, 0, Sys->QTDIR);
	root.xf.rootqid = root.qid;
	return ref Rmsg.Attach(t.tag, root.qid);
}

clone(ofl: ref Xfile, newfid: int): ref Xfile
{
	nfl := xfile(newfid, Clean);
	next := nfl.next;
	*nfl = *ofl;
	nfl.ptr = nil;
	nfl.next = next;
	nfl.fid = newfid;
	refxfs(nfl.xf, 1);
	if(ofl.ptr != nil){
		dp := ref *ofl.ptr;
		dp.p = nil;
		dp.d = nil;
		nfl.ptr = dp;
	}
	return nfl;
}

walk1(f: ref Xfile, name: string): ref Rmsg.Error
{
	if((f.qid.qtype & Sys->QTDIR) == 0){
		if(debug)
			chat(sys->sprint("qid.path=0x%bx...", f.qid.path));
		return e(Enotdir);
	}

	if(name == ".")	# can't happen
		return nil;

	if(name== "..") {
		if(f.qid.path == f.xf.rootqid.path) {
			if (debug)
				chat("walkup from root...");
			return nil;
		}
		(r,dp) := walkup(f);
		if(r < 0)
			return e(Enonexist);

		f.ptr = dp;
		if(dp.addr == 0) {
			f.qid.path = f.xf.rootqid.path;
			f.qid.qtype = Sys->QTFILE;
		} else {
			f.qid.path = QIDPATH(dp);
			f.qid.qtype = Sys->QTDIR;
		}
	} else {
		if(getfile(f) < 0)
			return e(Enonexist);
		(r,dp) := searchdir(f, name, 0,1);
		putfile(f);
		if(r < 0)
			return e(Enonexist);

		f.ptr = dp;
		f.qid.path = QIDPATH(dp);
		f.qid.qtype = Sys->QTFILE;
		if(dp.addr == 0)
			f.qid.path = f.xf.rootqid.path;
		else {
			d := Dosdir.arr2Dd(dp.p.iobuf[dp.offset:dp.offset+DOSDIRSIZE]);
			if((int d.attr & DDIR) !=  0)
				f.qid.qtype = Sys->QTDIR;
		}
		putfile(f);
	}
	return nil;
}

rwalk(t: ref Tmsg.Walk): ref Rmsg
{
	f := xfile(t.fid, Asis);
	if(f==nil) {
		if(debug)
			chat("no xfile...");
		return e(Enofid);
	}
	nf: ref Xfile;
	if(t.newfid != t.fid)
		f = nf = clone(f, t.newfid);
	qids: array of Sys->Qid;
	if(len t.names > 0){
		savedqid := f.qid;
		savedptr := f.ptr;
		qids = array[len t.names] of Sys->Qid;
		for(i := 0; i < len t.names; i++){
			e := walk1(f, t.names[i]);
			if(e != nil){
				f.qid = savedqid;
				f.ptr = savedptr;
				if(nf != nil)
					xfile(t.newfid, Clunk);
				if(i == 0)
					return e;
				return ref Rmsg.Walk(t.tag, qids[0:i]);
			}
			qids[i] = f.qid;
		}
	}
	return ref Rmsg.Walk(t.tag, qids);
}

ropen(t: ref Tmsg.Open): ref Rmsg
{
	attr: int;

	omode := 0;
	f := xfile(t.fid, Asis);
	if(f == nil)
		return e(Enofid);
	if((f.flags&Omodes) != 0)
		return e(Efidopen);

	dp := f.ptr;
	if(dp.paddr && (t.mode & Styx->ORCLOSE) != 0) {
		# check on parent directory of file to be deleted
		p := getsect(f.xf, dp.paddr);
		if(p == nil)
			return e(Eio);
		# 11 is the attr byte offset in a FAT directory entry
		attr = int p.iobuf[dp.poffset+11];
		putsect(p);
		if((attr & int DRONLY) != 0)
			return e(Eperm);
		omode |= Orclose;
	} else if(t.mode & Styx->ORCLOSE)
		omode |= Orclose;

	if(getfile(f) < 0)
		return e(Enonexist);

	if(dp.addr != 0) {
		d := Dosdir.arr2Dd(dp.p.iobuf[dp.offset:dp.offset+DOSDIRSIZE]);
		attr = int d.attr;
	} else
		attr = int DDIR;

	case t.mode & 7 {
	Styx->OREAD or
	Styx->OEXEC =>
		omode |= Oread;
	Styx->ORDWR =>
		omode |= Oread;
		omode |= Owrite;
		if(attr & int (DRONLY|DDIR)) {
			putfile(f);
			return e(Eperm);
		}
	Styx->OWRITE =>
		omode |= Owrite;
		if(attr & int (DRONLY|DDIR)) {
			putfile(f);
			return e(Eperm);
		}
	* =>
		putfile(f);
		return e(Eopen);
	}

	if(t.mode & Styx->OTRUNC) {
		if((attr & int DDIR)!=0 || (attr & int DRONLY) != 0) {
			putfile(f);
			return e(Eperm);
		}

		if(truncfile(f) < 0) {
			putfile(f);
			return e(Eio);
		}
	}

	f.flags |= omode;
	putfile(f);
	return ref Rmsg.Open(t.tag, f.qid, Styx->MAXFDATA);
}

mkdentry(xf: ref Xfs, ndp: ref Dosptr, name: string, sname: string, islong: int, nattr: byte, start: array of byte, length: array of byte): int
{
	ndp.p = getsect(xf, ndp.addr);
	if(ndp.p == nil)
		return Eio;
	if(islong && (r := putlongname(xf, ndp, name, sname)) < 0){
		putsect(ndp.p);
		if(r == -2)
			return Efull;
		return Eio;
	}

	nd := ref Dosdir(".       ","   ",byte 0,array[10] of { * => byte 0},
			array[2] of { * => byte 0}, array[2] of { * => byte 0},
			array[2] of { * => byte 0},array[4] of { * => byte 0});

	nd.attr = nattr;
	puttime(nd);
	nd.start[0: ] = start[0: 2];
	nd.length[0: ] = length[0: 4];

	if(islong)
		putname(sname[0:8]+"."+sname[8:11], nd);
	else
		putname(name, nd);
	ndp.p.iobuf[ndp.offset: ] = Dosdir.Dd2arr(nd);
	ndp.p.flags |= BMOD;
	return 0;
}

rcreate(t: ref Tmsg.Create): ref Rmsg
{
	bp: ref Dosbpb;
	omode:=0;
	start:=0;
	sname := "";
	islong :=0;

	f := xfile(t.fid, Asis);
	if(f == nil)
		return e(Enofid);
	if((f.flags&Omodes) != 0)
		return e(Efidopen);
	if(getfile(f)<0)
		return e(Eio);

	pdp := f.ptr;
	if(pdp.addr != 0)
		pd := Dosdir.arr2Dd(pdp.p.iobuf[pdp.offset:pdp.offset+DOSDIRSIZE]);
	else
		pd = nil;

	if(pd != nil)
		attr := int pd.attr;
	else
		attr = DDIR;

	if(!(attr & DDIR) || (attr & DRONLY)) {
		putfile(f);
		return e(Eperm);
	}

	if(t.mode & Styx->ORCLOSE)
		omode |= Orclose;

	case (t.mode & 7) {
	Styx->OREAD or
	Styx->OEXEC =>
		omode |= Oread;
	Styx->OWRITE or
	Styx->ORDWR =>
		if ((t.mode & 7) == Styx->ORDWR)
			omode |= Oread;
		omode |= Owrite;
		if(t.perm & Sys->DMDIR){
			putfile(f);
			return e(Eperm);
		}
	* =>
		putfile(f);
		return e(Eopen);
	}

	if(t.name=="." || t.name=="..") {
		putfile(f);
		return e(Eperm);
	}

	(r,ndp) := searchdir(f, t.name, 1, 1);
	if(r < 0) {
		putfile(f);
		if(r == -2)
			return e(Efull);
		return e(Eexist);
	}

	nds := name2de(t.name);
	if(nds > 0) {
		# long file name, find "new" short name
		i := 1;
		for(;;) {
			sname = long2short(t.name, i);
			(r1, tmpdp) := searchdir(f, sname, 0, 0);
			if(r1 < 0)
				break;
			putsect(tmpdp.p);
			i++;
		}
		islong = 1;
	}

	# allocate first cluster, if making directory
	if(t.perm & Sys->DMDIR) {
		bp = f.xf.ptr;
		start = falloc(f.xf);
		if(start <= 0) {
			putfile(f);
			return e(Efull);
		}
	}

	 # now we're committed
	if(pd != nil) {
		puttime(pd);
		pdp.p.flags |= BMOD;
	}

	f.ptr = ndp;
	ndp.p = getsect(f.xf, ndp.addr);
	if(ndp.p == nil ||
	   islong && putlongname(f.xf, ndp, t.name, sname) < 0){
		putsect(pdp.p);
		if(ndp.p != nil)
			putsect(ndp.p);
		return e(Eio);
	}

	nd := ref Dosdir(".       ","   ",byte 0,array[10] of { * => byte 0},
			array[2] of { * => byte 0}, array[2] of { * => byte 0},
			array[2] of { * => byte 0},array[4] of { * => byte 0});

	if((t.perm & 8r222) == 0)
		nd.attr |= byte DRONLY;

	puttime(nd);
	nd.start[0] = byte start;
	nd.start[1] = byte (start>>8);

	if(islong)
		putname(sname[0:8]+"."+sname[8:11], nd);
	else
		putname(t.name, nd);

	f.qid.path = QIDPATH(ndp);
	if(t.perm & Sys->DMDIR) {
		nd.attr |= byte DDIR;
		f.qid.qtype |= Sys->QTDIR;
		xp := getsect(f.xf, bp.dataaddr+(start-2)*bp.clustsize);
		if(xp == nil) {
			if(ndp.p!=nil)
				putfile(f);
			putsect(pdp.p);
			return e(Eio);
		}
		xd := ref *nd;
		xd.name = ".       ";
		xd.ext = "   ";
		xp.iobuf[0:] = Dosdir.Dd2arr(xd);
		if(pd!=nil)
			xd = ref *pd;
		else{
			xd = ref Dosdir("..      ","   ",byte 0,
				array[10] of { * => byte 0},
				array[2] of { * => byte 0},
				array[2] of { * => byte 0},
				array[2] of { * => byte 0},
				array[4] of { * => byte 0});

			puttime(xd);
			xd.attr = byte DDIR;
		}
		xd.name="..      ";
		xd.ext="   ";
		xp.iobuf[DOSDIRSIZE:] = Dosdir.Dd2arr(xd);
		xp.flags |= BMOD;
		putsect(xp);
	}else
		f.qid.qtype = Sys->QTFILE;

	ndp.p.flags |= BMOD;
	tmp := Dosdir.Dd2arr(nd);
	ndp.p.iobuf[ndp.offset:]= tmp;
	putfile(f);
	putsect(pdp.p);

	f.flags |= omode;
	return ref Rmsg.Create(t.tag, f.qid, Styx->MAXFDATA);
}

rread(t: ref Tmsg.Read): ref Rmsg
{
	r: int;
	data: array of byte;

	if(((f:=xfile(t.fid, Asis))==nil) ||
	    (f.flags&Oread == 0))
		return e(Eio);

	if((f.qid.qtype & Sys->QTDIR) != 0) {
		if(getfile(f) < 0)
			return e(Eio);
		(r, data) = readdir(f, int t.offset, t.count);
	} else {
		if(getfile(f) < 0)
			return e(Eio);
		(r,data) = readfile(f, int t.offset, t.count);
	}
	putfile(f);

	if(r < 0)
		return e(Eio);
	return ref Rmsg.Read(t.tag, data[0:r]);
}

rwrite(t: ref Tmsg.Write): ref Rmsg
{
	if(((f:=xfile(t.fid, Asis))==nil) ||
	   !(f.flags&Owrite))
		return e(Eio);
	if(getfile(f) < 0)
		return e(Eio);
	r := writefile(f, t.data, int t.offset, len t.data);
	putfile(f);
	if(r < 0){
		if(r == -2)
			return e(Efull);
		return e(Eio);
	}
	return ref Rmsg.Write(t.tag, r);
}

rclunk(t: ref Tmsg.Clunk): ref Rmsg
{
	xfile(t.fid, Clunk);
	sync();
	return ref Rmsg.Clunk(t.tag);
}

doremove(f: ref Xfs, dp: ref Dosptr)
{
	dp.p.iobuf[dp.offset] = byte DOSEMPTY;
	dp.p.flags |= BMOD;
	for(prevdo := dp.offset-DOSDIRSIZE; prevdo >= 0; prevdo-=DOSDIRSIZE){
		if (dp.p.iobuf[prevdo+11] != byte DLONG)
			break;
		dp.p.iobuf[prevdo] = byte DOSEMPTY;
	}

	if (prevdo <= 0 && dp.prevaddr != -1){
		p := getsect(f,dp.prevaddr);
		for(prevdo = f.ptr.sectsize-DOSDIRSIZE; prevdo >= 0; prevdo-=DOSDIRSIZE) {
			if(p.iobuf[prevdo+11] != byte DLONG)
				break;
			p.iobuf[prevdo] = byte DOSEMPTY;
			p.flags |= BMOD;
		}
		putsect(p);
	}
}

rremove(t: ref Tmsg.Remove): ref Rmsg
{
	f := xfile(t.fid, Asis);
	if(f == nil)
		return e(Enofid);

	if(!f.ptr.addr) {
		if(debug)
			chat("root...");
		xfile(t.fid, Clunk);
		sync();
		return e(Eperm);
	}

	# check on parent directory of file to be deleted
	parp := getsect(f.xf, f.ptr.paddr);
	if(parp == nil) {
		xfile(t.fid, Clunk);
		sync();
		return e(Eio);
	}

	pard := Dosdir.arr2Dd(parp.iobuf[f.ptr.poffset:f.ptr.poffset+DOSDIRSIZE]);
	if(f.ptr.paddr && (int pard.attr & DRONLY)) {
		if(debug)
			chat("parent read-only...");
		putsect(parp);
		xfile(t.fid, Clunk);
		sync();
		return e(Eperm);
	}

	if(getfile(f) < 0){
		if(debug)
			chat("getfile failed...");
		putsect(parp);
		xfile(t.fid, Clunk);
		sync();
		return e(Eio);
	}

	dattr := int f.ptr.p.iobuf[f.ptr.offset+11];
	if(dattr & DDIR && emptydir(f) < 0){
		if(debug)
			chat("non-empty dir...");
		putfile(f);
		putsect(parp);
		xfile(t.fid, Clunk);
		sync();
		return e(Eperm);
	}
	if(f.ptr.paddr == 0 && dattr&DRONLY) {
		if(debug)
			chat("read-only file in root directory...");
		putfile(f);
		putsect(parp);
		xfile(t.fid, Clunk);
		sync();
		return e(Eperm);
	}

	doremove(f.xf, f.ptr);

	if(f.ptr.paddr) {
		puttime(pard);
		parp.flags |= BMOD;
	}

	parp.iobuf[f.ptr.poffset:] = Dosdir.Dd2arr(pard);
	putsect(parp);
	err := 0;
	if(truncfile(f) < 0)
		err = Eio;

	putfile(f);
	xfile(t.fid, Clunk);
	sync();
	if(err)
		return e(err);
	return ref Rmsg.Remove(t.tag);
}

rstat(t: ref Tmsg.Stat): ref Rmsg
{
	f := xfile(t.fid, Asis);
	if(f == nil)
		return e(Enofid);
	if(getfile(f) < 0)
		return e(Eio);
	dir := dostat(f);
	putfile(f);
	return ref Rmsg.Stat(t.tag, *dir);
}

dostat(f: ref Xfile): ref Sys->Dir
{
	islong :=0;
	prevdo: int;
	longnamebuf:="";

	# get file info.
	dir := getdir(f.ptr.p.iobuf[f.ptr.offset:f.ptr.offset+DOSDIRSIZE],
					f.ptr.addr, f.ptr.offset);
	# get previous entry
	if(f.ptr.prevaddr == -1) {
		# maybe extended, but will never cross sector boundary...
		# short filename at beginning of sector..
		if(f.ptr.offset!=0) {
			for(prevdo = f.ptr.offset-DOSDIRSIZE; prevdo >=0; prevdo-=DOSDIRSIZE) {
				prevdattr := f.ptr.p.iobuf[prevdo+11];
				if(prevdattr != byte DLONG)
					break;
				islong = 1;
				longnamebuf += getnamesect(f.ptr.p.iobuf[prevdo:prevdo+DOSDIRSIZE]);
			}
		}
	} else {
		# extended and will cross sector boundary.
		for(prevdo = f.ptr.offset-DOSDIRSIZE; prevdo >=0; prevdo-=DOSDIRSIZE) {
			prevdattr := f.ptr.p.iobuf[prevdo+11];
			if(prevdattr != byte DLONG)
				break;
			islong = 1;
			longnamebuf += getnamesect(f.ptr.p.iobuf[prevdo:prevdo+DOSDIRSIZE]);
		}
		if (prevdo < 0) {
			p := getsect(f.xf,f.ptr.prevaddr);
			for(prevdo = f.xf.ptr.sectsize-DOSDIRSIZE; prevdo >=0; prevdo-=DOSDIRSIZE){
				prevdattr := p.iobuf[prevdo+11];
				if(prevdattr != byte DLONG)
					break;
				islong = 1;
				longnamebuf += getnamesect(p.iobuf[prevdo:prevdo+DOSDIRSIZE]);
			}
			putsect(p);
		}
	}
	if(islong)
		dir.name = longnamebuf;
	return dir;
}

nameok(elem: string): int
{
	isfrog := array[256] of {
	# NUL
	1, 1, 1, 1, 1, 1, 1, 1,
	# BKS
	1, 1, 1, 1, 1, 1, 1, 1,
	# DLE
	1, 1, 1, 1, 1, 1, 1, 1,
	# CAN
	1, 1, 1, 1, 1, 1, 1, 1,
#	' ' =>	1,
	'/' =>	1, 16r7f =>	1, * => 0
	};

	for(i:=0; i < len elem; i++) {
		if(isfrog[elem[i]])
			return -1;
	}
	return 0;
}

rwstat(t: ref Tmsg.Wstat): ref Rmsg
{
	f := xfile(t.fid, Asis);
	if(f == nil)
		return e(Enofid);

	if(getfile(f) < 0)
		return e(Eio);

	dp := f.ptr;

	if(dp.addr == 0){	# root
		putfile(f);
		return e(Eperm);
	}

	changes := 0;
	dir := dostat(f);
	wdir := ref t.stat;

	if(dir.uid != wdir.uid || dir.gid != wdir.gid){
		putfile(f);
		return e(Eperm);
	}

	if(dir.mtime != wdir.mtime || ((dir.mode^wdir.mode) & 8r777))
		changes = 1;

	if((wdir.mode & 7) != ((wdir.mode >> 3) & 7)
	|| (wdir.mode & 7) != ((wdir.mode >> 6) & 7)){
		putfile(f);
		return e(Eperm);
	}

	if(dir.name != wdir.name){
		# temporarily disable this
		# g.errno = Eperm;
		# putfile(f);
		# return;

		#
		# grab parent directory of file to be changed and check for write perm
		# rename also disallowed for read-only files in root directory
		#
		parp := getsect(f.xf, dp.paddr);
		if(parp == nil){
			putfile(f);
			return e(Eio);
		}
		# pard := Dosdir.arr2Dd(parp.iobuf[dp.poffset: dp.poffset+DOSDIRSIZE]);
		pardattr := int parp.iobuf[dp.poffset+11];
		dpd := Dosdir.arr2Dd(dp.p.iobuf[dp.offset: dp.offset+DOSDIRSIZE]);
		if(dp.paddr != 0 && int pardattr & DRONLY
		|| dp.paddr == 0 && int dpd.attr & DRONLY){
			putsect(parp);
			putfile(f);
			return e(Eperm);
		}

		#
		# retrieve info from old entry
		#
		oaddr := dp.addr;
		ooffset := dp.offset;
		d := dpd;
		od := *d;
		# start := getstart(f.xf, d);
		start := d.start;
		length := d.length;
		attr := d.attr;

		#
		# temporarily release file to allow other directory ops:
		# walk to parent, validate new name
		# then remove old entry
		#
		putfile(f);
		pf := ref *f;
		pdp := ref Dosptr(dp.paddr, dp.poffset, 0, 0, 0, 0, -1, -1, parp, nil);
		# if(pdp.addr != 0)
		# 	pdpd := Dosdir.arr2Dd(parp.iobuf[pdp.offset: pdp.offset+DOSDIRSIZE]);
		# else
		# 	pdpd = nil;
		pf.ptr = pdp;
		if(wdir.name == "." || wdir.name == ".."){
			putsect(parp);
			return e(Eperm);
		}
		islong := 0;
		sname := "";
		nds := name2de(wdir.name);
		if(nds > 0) {
			# long file name, find "new" short name
			i := 1;
			for(;;) {
				sname = long2short(wdir.name, i);
				(r1, tmpdp) := searchdir(f, sname, 0, 0);
				if(r1 < 0)
					break;
				putsect(tmpdp.p);
				i++;
			}
			islong = 1;
		}else{
			(b, e) := dosname(wdir.name);
			sname = b+e;
		}
		# (r, ndp) := searchdir(pf, wdir.name, 1, 1);
		# if(r < 0){
		#	putsect(parp);
		#	g.errno = Eperm;
		#	return;
		# }
		if(getfile(f) < 0){
			putsect(parp);
			return e(Eio);
		}
		doremove(f.xf, dp);
		putfile(f);

		#
		# search for dir entry again, since we may be able to use the old slot,
		# and we need to set up the naddr field if a long name spans the block.
		# create new entry.
		#
		r := 0;
		(r, dp) = searchdir(pf, sname, 1, islong);
		if(r < 0){
			putsect(parp);
			return e(Ephase);
		}
		if((r = mkdentry(pf.xf, dp, wdir.name, sname, islong, attr, start, length)) != 0){
			putsect(parp);
			return e(r);
		}
		putsect(parp);

		#
		# relocate up other fids to the same file, if it moved
		#
		f.ptr = dp;
		f.qid.path = QIDPATH(dp);
		if(oaddr != dp.addr || ooffset != dp.offset)
			dosptrreloc(f, dp, oaddr, ooffset);
		changes = 1;
		# f = nil;
	}

	if(changes){
		d := Dosdir.arr2Dd(dp.p.iobuf[dp.offset:dp.offset+DOSDIRSIZE]);
		putdir(d, wdir);
		dp.p.iobuf[dp.offset: ] = Dosdir.Dd2arr(d);
		dp.p.flags |= BMOD;
	}
	if(f != nil)
		putfile(f);
	sync();
	return ref Rmsg.Wstat(t.tag);
}

#
# FAT file system format
#

Dospart: adt {
	active: byte;
	hstart: byte;
	cylstart: array of byte;
	typ: byte;
	hend: byte;
	cylend: array of byte;
	start: array of byte;
	length: array of byte;
};

Dosboot: adt {
	arr2Db:	fn(arr: array of byte): ref Dosboot;
	magic:	array of byte;
	version:	array of byte;
	sectsize:	array of byte;
	clustsize:	byte;
	nresrv:	array of byte;
	nfats:	byte;
	rootsize:	array of byte;
	volsize:	array of byte;
	mediadesc:	byte;
	fatsize:	array of byte;
	trksize:	array of byte;
	nheads:	array of byte;
	nhidden:	array of byte;
	bigvolsize:	array of byte;
	driveno:	byte;
	bootsig:	byte;
	volid:	array of byte;
	label:	array of byte;
};

Dosbpb: adt {
	sectsize: int;	# in bytes 
	clustsize: int;	# in sectors 
	nresrv: int;	# sectors 
	nfats: int;	# usually 2 
	rootsize: int;	# number of entries 
	volsize: int;	# in sectors 
	mediadesc: int;
	fatsize: int;	# in sectors 
	fatclusters: int;
	fatbits: int;	# 12 or 16 
	fataddr: int; #big;	# sector number 
	rootaddr: int; #big;
	dataaddr: int; #big;
	freeptr: int; #big;	# next free cluster candidate 
};

Dosdir: adt {
	Dd2arr:	fn(d: ref Dosdir): array of byte;
	arr2Dd:	fn(arr: array of byte): ref Dosdir;
	name:	string;
	ext:		string;
	attr:		byte;
	reserved:	array of byte;
	time:		array of byte;
	date:		array of byte;
	start:		array of byte;
	length:	array of byte;
};

Dosptr: adt {
	addr:	int;	# of file's directory entry 
	offset:	int;
	paddr:	int;	# of parent's directory entry 
	poffset:	int;
	iclust:	int;	# ordinal within file 
	clust:	int;
	prevaddr:	int;
	naddr:	int;
	p:	ref Iosect;
	d:	ref Dosdir;
};

Asis, Clean, Clunk: con iota;

FAT12: con byte 16r01;
FAT16: con byte 16r04;
FATHUGE: con byte 16r06;
DMDDO: con 16r54;
DRONLY: con 16r01;
DHIDDEN: con 16r02;
DSYSTEM: con 16r04;
DVLABEL: con 16r08;
DDIR: con 16r10;
DARCH: con 16r20;
DLONG: con DRONLY | DHIDDEN | DSYSTEM | DVLABEL;
DMLONG: con DLONG | DDIR | DARCH;

DOSDIRSIZE: con 32;
DOSEMPTY: con 16rE5;
DOSRUNES: con 13;

FATRESRV: con 2;

Oread: con  1;
Owrite: con  2;
Orclose: con  4;
Omodes: con  3;

VERBOSE, STYX_MESS, FAT_INFO, CLUSTER_INFO: con (1 << iota);

nowt, nowt1: int;
tzoff: int;

#
# because we map all incoming short names from all upper to all lower case,
# and FAT cannot store mixed case names in short name form,
# we'll declare upper case as unacceptable to decide whether a long name
# is needed on output.  thus, long names are always written in the case
# in the system call, and are always read back as written; short names
# are produced by the common case of writing all lower case letters
#
isdos := array[256] of {
	'a' to 'z' => 1, 'A' to 'Z' => 0, '0' to '9' => 1,
	' ' => 1, '$' => 1, '%' => 1, '"' => 1, '-' => 1, '_' => 1, '@' => 1,
	'~' => 1, '`' => 1, '!' => 1, '(' => 1, ')' => 1, '{' => 1, '}' => 1, '^' => 1,
	'#' => 1, '&' => 1,
	* => 0
};

dossetup()
{
	nowt = daytime->now();
	nowt1 = sys->millisec();
	tzoff = daytime->local(0).tzoff;
}

# make xf into a Dos file system... or die trying to.
dosfs(xf: ref Xfs): int
{
	mbroffset := 0;
	i: int;
	p: ref Iosect;

Dmddo:
	for(;;) {
		for(i=2; i>0; i--) {
			p = getsect(xf, 0);
			if(p == nil)
				return -1;

			if((mbroffset == 0) && (p.iobuf[0] == byte 16re9))
				break;
			
			# Check if the jump displacement (magic[1]) is too 
			# short for a FAT. DOS 4.0 MBR has a displacement of 8.
			if(p.iobuf[0] == byte 16reb &&
			   p.iobuf[2] == byte 16r90 &&
			   p.iobuf[1] != byte 16r08)
				break;

			if(i < 2 ||
			   p.iobuf[16r1fe] != byte 16r55 ||
			   p.iobuf[16r1ff] != byte 16raa) {
				i = 0;
				break;
			}

			dp := 16r1be;
			for(j:=4; j>0; j--) {
				if(debug) {
					chat(sys->sprint("16r%2.2ux (%d,%d) 16r%2.2ux (%d,%d) %d %d...",
					int p.iobuf[dp], int p.iobuf[dp+1], 
					bytes2short(p.iobuf[dp+2: dp+4]),
					int p.iobuf[dp+4], int p.iobuf[dp+5], 
					bytes2short(p.iobuf[dp+6: dp+8]),
					bytes2int(p.iobuf[dp+8: dp+12]), 
					bytes2int(p.iobuf[dp+12:dp+16])));
				}

				# Check for a disc-manager partition in the MBR.
				# Real MBR is at lba 63. Unfortunately it starts
				# with 16rE9, hence the check above against magic.
				if(int p.iobuf[dp+4] == DMDDO) {
					mbroffset = 63*Sectorsize;
					putsect(p);
					purgebuf(xf);
					xf.offset += mbroffset;
					break Dmddo;
				}
				
				# Make sure it really is the right type, other
				# filesystems can look like a FAT
				# (e.g. OS/2 BOOT MANAGER).
				if(p.iobuf[dp+4] == FAT12 ||
				   p.iobuf[dp+4] == FAT16 ||
				   p.iobuf[dp+4] == FATHUGE)
					break;
				dp+=16;
			}

			if(j <= 0) {
				if(debug)
					chat("no active partition...");
				putsect(p);
				return -1;
			}

			offset := bytes2int(p.iobuf[dp+8:dp+12])* Sectorsize;
			putsect(p);
			purgebuf(xf);
			xf.offset = mbroffset+offset;
		}
		break;
	}
	if(i <= 0) {
		if(debug)
			chat("bad magic...");
		putsect(p);
		return -1;
	}

	b := Dosboot.arr2Db(p.iobuf);
	if(debug & FAT_INFO)
		bootdump(b);

	bp := ref Dosbpb;
	xf.ptr = bp;
	xf.fmt = 1;

	bp.sectsize = bytes2short(b.sectsize);
	bp.clustsize = int b.clustsize;
	bp.nresrv = bytes2short(b.nresrv);
	bp.nfats = int b.nfats;
	bp.rootsize = bytes2short(b.rootsize);
	bp.volsize = bytes2short(b.volsize);
	if(bp.volsize == 0)
		bp.volsize = bytes2int(b.bigvolsize);
	bp.mediadesc = int b.mediadesc;
	bp.fatsize = bytes2short(b.fatsize);

	bp.fataddr = int bp.nresrv;
	bp.rootaddr = bp.fataddr + bp.nfats*bp.fatsize;
	i = bp.rootsize*DOSDIRSIZE + bp.sectsize-1;
	i /= bp.sectsize;
	bp.dataaddr = bp.rootaddr + i;
	bp.fatclusters = FATRESRV+(bp.volsize - bp.dataaddr)/bp.clustsize;
	if(bp.fatclusters < 4087)
		bp.fatbits = 12;
	else
		bp.fatbits = 16;
	bp.freeptr = 2;
	if(debug & FAT_INFO){
		chat(sys->sprint("fatbits=%d (%d clusters)...",
			bp.fatbits, bp.fatclusters));
		for(i=0; i< int b.nfats; i++)
			chat(sys->sprint("fat %d: %d...",
				i, bp.fataddr+i*bp.fatsize));
		chat(sys->sprint("root: %d...", bp.rootaddr));
		chat(sys->sprint("data: %d...", bp.dataaddr));
	}
	putsect(p);
	return 0;
}

QIDPATH(dp: ref Dosptr): big
{
	return big (dp.addr*(Sectorsize/DOSDIRSIZE) + dp.offset/DOSDIRSIZE);
}

isroot(addr: int): int
{
	return addr == 0;
}

getfile(f: ref Xfile): int
{
	dp := f.ptr;
	if(dp.p!=nil)
		panic("getfile");
	if(dp.addr < 0)
		panic("getfile address");
	p := getsect(f.xf, dp.addr);
	if(p == nil)
		return -1;

	dp.d = nil;
	if(!isroot(dp.addr)) {
		if(f.qid.path != QIDPATH(dp)){
			if(debug) {
				chat(sys->sprint("qid mismatch f=0x%x d=0x%x...",
					int f.qid.path, int QIDPATH(dp)));
			}
			putsect(p);
			return -1;
		}
	#	dp.d = Dosdir.arr2Dd(p.iobuf[dp.offset:dp.offset+DOSDIRSIZE]);
	}
	dp.p = p;
	return 0;
}

putfile(f: ref Xfile)
{
	dp := f.ptr;
	if(dp.p==nil)
		panic("putfile");
	putsect(dp.p);
	dp.p = nil;
	dp.d = nil;
}

getstart(nil: ref Xfs, d: ref Dosdir): int
{
	start := bytes2short(d.start);
#	if(xf.isfat32)
#		start |= bytes2short(d.hstart)<<16;
	return start;
}

putstart(nil: ref Xfs, d: ref Dosdir, start: int)
{
	d.start[0] = byte start;
	d.start[1] = byte (start>>8);
#	if(xf.isfat32){
#		d.hstart[0] = start>>16;
#		d.hstart[1] = start>>24;
#	}
}

#
# return the disk cluster for the iclust cluster in f
#
fileclust(f: ref Xfile, iclust: int, cflag: int): int
{

	bp := f.xf.ptr;
	dp := f.ptr;
	if(isroot(dp.addr))
		return -1;		# root directory for old FAT format does not start on a cluster boundary
	d := dp.d;
	if(d == nil){
		if(dp.p == nil)
			panic("fileclust");
		d = Dosdir.arr2Dd(dp.p.iobuf[dp.offset:dp.offset+DOSDIRSIZE]);
	}
	next := 0;
	start := getstart(f.xf, d);
	if(start == 0) {
		if(!cflag)
			return -1;
		start = falloc(f.xf);
		if(start <= 0)
			return -1;
		puttime(d);
		putstart(f.xf, d, start);
		dp.p.iobuf[dp.offset:] = Dosdir.Dd2arr(d);
		dp.p.flags |= BMOD;
		dp.clust = 0;
	}

	clust, nskip: int;
	if(dp.clust == 0 || iclust < dp.iclust) {
		clust = start;
		nskip = iclust;
	} else {
		clust = dp.clust;
		nskip = iclust - dp.iclust;
	}

	if(debug & CLUSTER_INFO  && nskip > 0)
		chat(sys->sprint("clust %d, skip %d...", clust, nskip));

	if(clust <= 0)
		return -1;

	if(nskip > 0) {
		while(--nskip >= 0) {
			next = getfat(f.xf, clust);
			if(debug & CLUSTER_INFO)
				chat(sys->sprint(".%d", next));
			if(next <= 0){
				if(!cflag)
					break;
				next = falloc(f.xf);
				if(next <= 0)
					return -1;
				putfat(f.xf, clust, next);
			}
			clust = next;
		}
		if(next <= 0)
			return -1;
		dp.clust = clust;
		dp.iclust = iclust;
	}
	if(debug & CLUSTER_INFO)
		chat(sys->sprint(" clust(%d)=0x%x...", iclust, clust));
	return clust;
}

#
# return the disk sector for the isect disk sector in f,
# allocating space if necessary and cflag is set
#
fileaddr(f: ref Xfile, isect: int, cflag: int): int
{
	bp := f.xf.ptr;
	dp := f.ptr;
	if(isroot(dp.addr)) {
		if(isect*bp.sectsize >= bp.rootsize*DOSDIRSIZE)
			return -1;
		return bp.rootaddr + isect;
	}
	clust := fileclust(f, isect/bp.clustsize, cflag);
	if(clust < 0)
		return -1;
	return clust2sect(bp, clust) + isect%bp.clustsize;
}

#
# look for a directory entry matching name
# always searches for long names which match a short name
#
# if creating (cflag is set), set address of available slot and allocate next cluster if necessary
#
searchdir(f: ref Xfile, name: string, cflag: int, lflag: int): (int, ref Dosptr)
{
	xf := f.xf;
	bp := xf.ptr;
	addr1 := -1;
	addr2 := -1;
	prevaddr1 := -1;
	o1 := 0;
	dp :=  ref Dosptr(0,0,0,0,0,0,-1,-1,nil,nil);	# prevaddr and naddr are -1
	dp.paddr = f.ptr.addr;
	dp.poffset = f.ptr.offset;
	islong :=0;
	buf := "";

	need := 1;
	if(lflag && cflag)
		need += name2de(name);
	if(!lflag) {
		name = name[0:8]+"."+name[8:11];
		i := len name -1;
		while(i >= 0 && (name[i]==' ' || name[i] == '.'))
			i--;
		name = name[0:i+1];
	}

	addr := -1;
	prevaddr: int;
	have := 0;
	for(isect:=0;; isect++) {
		prevaddr = addr;
		addr = fileaddr(f, isect, cflag);
		if(addr < 0)
			break;
		p := getsect(xf, addr);
		if(p == nil)
			break;
		for(o:=0; o<bp.sectsize; o+=DOSDIRSIZE) {
			dattr := int p.iobuf[o+11];
			dname0 := p.iobuf[o];
			if(dname0 == byte 16r00) {
				if(debug)
					chat("end dir(0)...");
				putsect(p);
				if(!cflag)
					return (-1, nil);

				#
				# addr1 and o1 are the start of the dirs
				# addr2 is the optional second cluster used if the long name
				# entry does not fit within the addr1 cluster
				# have tells us the number of contiguous free dirs
				# starting at addr1.o1; need is the number needed to hold the long name
				#
				if(addr1 < 0){
					addr1 = addr;
					prevaddr1 = prevaddr;
					o1 = o;
				}
				nleft := (bp.sectsize-o)/DOSDIRSIZE;
				if(addr2 < 0 && nleft+have < need){
					addr2 = fileaddr(f, isect+1, cflag);
					if(addr2 < 0){
						if(debug)
							chat("end dir(2)...");
						return (-2, nil);
					}
				}else if(addr2 < 0)
					addr2 = addr;
				if(addr2 == addr1)
					addr2 = -1;
				if(debug)
					chat(sys->sprint("allocate addr1=%d,%d addr2=%d for %s nleft=%d have=%d need=%d", addr1, o1, addr2, name, nleft, have, need));
				dp.addr = addr1;
				dp.offset = o1;
				dp.prevaddr = prevaddr1;
				dp.naddr = addr2;
				return (0, dp);
			}

			if(dname0 == byte DOSEMPTY) {
				if(debug)
					chat("empty...");
				have++;
				if(addr1 == -1){
					addr1 = addr;
					o1 = o;
					prevaddr1 = prevaddr;
				}
				if(addr2 == -1 && have >= need)
					addr2 = addr;
				continue;
			}
			have = 0;
			if(addr2 == -1)
				addr1 = -1;

			if(0 && lflag && debug)
				dirdump(p.iobuf[o:o+DOSDIRSIZE],addr,o);

			if((dattr & DMLONG) == DLONG) {
				if(!islong)
					buf = "";
				islong = 1;
				buf = getnamesect(p.iobuf[o:o+DOSDIRSIZE]) + buf;	# getnamesect should return sum
				continue;
			}
			if(dattr & DVLABEL) {
				islong = 0;
				continue;
			}

			if(!islong || !lflag) 
				buf = getname(p.iobuf[o:o+DOSDIRSIZE]);
			islong = 0;

			if(debug)
				chat(sys->sprint("cmp: [%s] [%s]", buf, name));
			if(mystrcmp(buf, name) != 0) {
				buf="";
				continue;
			}
			if(debug)
				chat("found\n");

			if(cflag) {
				putsect(p);
				return (-1,nil);
			}

			dp.addr = addr;
			dp.prevaddr = prevaddr;
			dp.offset = o;
			dp.p = p;
			#dp.d = Dosdir.arr2Dd(p.iobuf[o:o+DOSDIRSIZE]);
			return (0, dp);
		}
		putsect(p);
	}
	if(debug)
		chat("end dir(1)...");
	if(!cflag)
		return (-1, nil);
	#
	# end of root directory or end of non-root directory on cluster boundary
	#
	if(addr1 < 0){
		addr1 = fileaddr(f, isect, 1);
		if(addr1 < 0)
			return (-2, nil);
		prevaddr1 = prevaddr;
		o1 = 0;
	}else{
		if(addr2 < 0 && have < need){
			addr2 = fileaddr(f, isect, 1);
			if(addr2 < 0)
				return (-2, nil);
		}
	}
	if(addr2 == addr1)
		addr2 = -1;
	dp.addr = addr1;
	dp.offset = o1;
	dp.prevaddr = prevaddr1;
	dp.naddr = addr2;
	return (0, dp);
}

emptydir(f: ref Xfile): int
{
	for(isect:=0;; isect++) {
		addr := fileaddr(f, isect, 0);
		if(addr < 0)
			break;

		p := getsect(f.xf, addr);
		if(p == nil)
			return -1;

		for(o:=0; o<f.xf.ptr.sectsize; o+=DOSDIRSIZE) {
			dname0 := p.iobuf[o];
			dattr := int p.iobuf[o+11];

			if(dname0 == byte 16r00) {
				putsect(p);
				return 0;
			}

			if(dname0 == byte DOSEMPTY || dname0 == byte '.')
				continue;

			if(dattr & DVLABEL)
				continue;		# ignore any long name entries: it's empty if there are no short ones

			putsect(p);
			return -1;
		}
		putsect(p);
	}
	return 0;
}

readdir(f:ref Xfile, offset: int, count: int): (int, array of byte)
{
	xf := f.xf;
	bp := xf.ptr;
	rcnt := 0;
	buf := array[Styx->MAXFDATA] of byte;
	islong :=0;
	longnamebuf:="";

	if(count <= 0)
		return (0, nil);

Read:
	for(isect:=0;; isect++) {
		addr := fileaddr(f, isect, 0);
		if(addr < 0)
			break;
		p := getsect(xf, addr);
		if(p == nil)
			return (-1,nil);

		for(o:=0; o<bp.sectsize; o+=DOSDIRSIZE) {
			dname0 := int p.iobuf[o];
			dattr := int p.iobuf[o+11];

			if(dname0 == 16r00) {
				putsect(p);
				break Read;
			}

			if(dname0 == DOSEMPTY)
				continue;

			if(dname0 == '.') {
				dname1 := int p.iobuf[o+1];
				if(dname1 == ' ' || dname1 == 0)
					continue;
				dname2 := int p.iobuf[o+2];
				if(dname1 == '.' &&
				  (dname2 == ' ' || dname2 == 0))
					continue;
			}

			if((dattr & DMLONG) == DLONG) {
				if(!islong)
					longnamebuf = "";
				longnamebuf = getnamesect(p.iobuf[o:o+DOSDIRSIZE]) + longnamebuf;
				islong = 1;
				continue;
			}
			if(dattr & DVLABEL) {
				islong = 0;
				continue;
			}

			dir := getdir(p.iobuf[o:o+DOSDIRSIZE], addr, o);
			if(islong) {
				dir.name = longnamebuf;
				longnamebuf = "";
				islong = 0;
			}
			d := styx->packdir(*dir);
			if(offset > 0) {
				offset -= len d;
				islong = 0;
				continue;
			}
			if(rcnt+len d > count){
				putsect(p);
				break Read;
			}
			buf[rcnt:] = d;
			rcnt += len d;
			if(rcnt >= count) {
				putsect(p);
				break Read;
			}
		}
		putsect(p);
	}

	return (rcnt, buf[0:rcnt]);
}

walkup(f: ref Xfile): (int, ref Dosptr)
{
	bp := f.xf.ptr;
	dp := f.ptr;
	o: int;
	ndp:= ref Dosptr(0,0,0,0,0,0,-1,-1,nil,nil);
	ndp.addr = dp.paddr;
	ndp.offset = dp.poffset;

	if(debug)
		chat(sys->sprint("walkup: paddr=0x%x...", dp.paddr));

	if(dp.paddr == 0)
		return (0,ndp);

	p := getsect(f.xf, dp.paddr);
	if(p == nil)  
		return (-1,nil);

	if(debug)
		dirdump(p.iobuf[dp.poffset:dp.poffset+DOSDIRSIZE],dp.paddr,dp.poffset);

	xd := Dosdir.arr2Dd(p.iobuf[dp.poffset:dp.poffset+DOSDIRSIZE]);
	start := getstart(f.xf, xd);
	if(debug & CLUSTER_INFO)
		if(debug)
			chat(sys->sprint("start=0x%x...", start));
	putsect(p);
	if(start == 0)
		return (-1,nil);

	#
	# check that parent's . points to itself
	#
	p = getsect(f.xf, bp.dataaddr + (start-2)*bp.clustsize);
	if(p == nil)
		return (-1,nil);

	if(debug)
		dirdump(p.iobuf,0,0);

	xd = Dosdir.arr2Dd(p.iobuf);
	if(p.iobuf[0]!= byte '.' ||
	   p.iobuf[1]!= byte ' ' ||
	   start != getstart(f.xf, xd)) { 
 		if(p!=nil) 
			putsect(p);
		return (-1,nil);
	}

	if(debug)
		dirdump(p.iobuf[DOSDIRSIZE:],0,0);

	#
	# parent's .. is the next entry, and has start of parent's parent
	#
	xd = Dosdir.arr2Dd(p.iobuf[DOSDIRSIZE:]);
	if(p.iobuf[32] != byte '.' || p.iobuf[33] != byte '.') { 
 		if(p != nil) 
			putsect(p);
		return (-1,nil);
	}

	#
	# we're done if parent is root
	#
	pstart := getstart(f.xf, xd);
	putsect(p);
	if(pstart == 0)
		return (0, ndp);

	#
	# check that parent's . points to itself
	#
	p = getsect(f.xf, clust2sect(bp, pstart));
	if(p == nil) {
		if(debug)
			chat(sys->sprint("getsect %d failed\n", pstart));
		return (-1,nil);
	}
	if(debug)
		dirdump(p.iobuf,0,0);
	xd = Dosdir.arr2Dd(p.iobuf);
	if(p.iobuf[0]!= byte '.' ||
	   p.iobuf[1]!=byte ' ' || 
	   pstart!=getstart(f.xf, xd)) { 
 		if(p != nil) 
			putsect(p);
		return (-1,nil);
	}

	#
	# parent's parent's .. is the next entry, and has start of parent's parent's parent
	#
	if(debug)
		dirdump(p.iobuf[DOSDIRSIZE:],0,0);

	xd = Dosdir.arr2Dd(p.iobuf[DOSDIRSIZE:]);
	if(xd.name[0] != '.' || xd.name[1] !=  '.') { 
 		if(p != nil) 
			putsect(p);
		return (-1,nil);
	}
	ppstart :=getstart(f.xf, xd);
	putsect(p);

	#
	# open parent's parent's parent, and walk through it until parent's paretn is found
	# need this to find parent's parent's addr and offset
	#
	ppclust := ppstart;
	# TO DO: FAT32
	if(ppclust != 0)
		k := clust2sect(bp, ppclust);
	else
		k = bp.rootaddr;
	p = getsect(f.xf, k);
	if(p == nil) {
		if(debug)
			chat(sys->sprint("getsect %d failed\n", k));
		return (-1,nil);
	}

	if(debug)
		dirdump(p.iobuf,0,0);

	if(ppstart) {
		xd = Dosdir.arr2Dd(p.iobuf);
		if(p.iobuf[0]!= byte '.' ||
		   p.iobuf[1]!= byte ' ' || 
		   ppstart!=getstart(f.xf, xd)) { 
 			if(p!=nil) 
				putsect(p);
			return (-1,nil);
		}
	}

	for(so:=1; ;so++) {
		for(o=0; o<bp.sectsize; o+=DOSDIRSIZE) {
			xdname0 := p.iobuf[o];
			if(xdname0 == byte 16r00) {
				if(debug)
					chat("end dir\n");
 				if(p != nil) 
					putsect(p);
				return (-1,nil);
			}

			if(xdname0 == byte DOSEMPTY)
				continue;

			#xd = Dosdir.arr2Dd(p.iobuf[o:o+DOSDIRSIZE]);
			xdstart:= p.iobuf[o+26:o+28];	# TO DO: getstart
			if(bytes2short(xdstart) == pstart) {
				putsect(p);
				ndp.paddr = k;
				ndp.poffset = o;
				return (0,ndp);
			}
		}
		if(ppclust) {
			if(so%bp.clustsize == 0) {
				ppstart = getfat(f.xf, ppstart);
				if(ppstart < 0){
					if(debug)
						chat(sys->sprint("getfat %d fail\n", 
							ppstart));
 					if(p != nil) 
						putsect(p);
					return (-1,nil);
				}
			}
			k = clust2sect(bp, ppclust) + 
				so%bp.clustsize;
		}
		else {
			if(so*bp.sectsize >= bp.rootsize*DOSDIRSIZE) { 
 				if(p != nil) 
					putsect(p);
				return (-1,nil);
			}
			k = bp.rootaddr + so;
		}
		putsect(p);
		p = getsect(f.xf, k);
		if(p == nil) {
			if(debug)
				chat(sys->sprint("getsect %d failed\n", k));
			return (-1,nil);
		}
	}
	putsect(p);
	ndp.paddr = k;
	ndp.poffset = o;
	return (0,ndp);
}

readfile(f: ref Xfile, offset: int, count: int): (int, array of byte)
{
	xf := f.xf;
	bp := xf.ptr;
	dp := f.ptr;

	length := bytes2int(dp.p.iobuf[dp.offset+28:dp.offset+32]);
	rcnt := 0;
	if(offset >= length)
		return (0,nil);
 	buf := array[Styx->MAXFDATA] of byte;
	if(offset+count >= length)
		count = length - offset;
	isect := offset/bp.sectsize;
	o := offset%bp.sectsize;
	while(count > 0) {
		addr := fileaddr(f, isect++, 0);
		if(addr < 0)
			break;
		c := bp.sectsize - o;
		if(c > count)
			c = count;
		p := getsect(xf, addr);
		if(p == nil)
			return (-1, nil);
		buf[rcnt:] = p.iobuf[o:o+c];
		putsect(p);
		count -= c;
		rcnt += c;
		o = 0;
	}
	return (rcnt, buf[0:rcnt]);
}

writefile(f: ref Xfile, buf: array of byte, offset,count: int): int
{
	xf := f.xf;
	bp := xf.ptr;
	dp := f.ptr;
	addr := 0;
	c: int;
	rcnt := 0;
	p: ref Iosect;

	d := dp.d;
	if(d == nil)
		d = Dosdir.arr2Dd(dp.p.iobuf[dp.offset:dp.offset+DOSDIRSIZE]);
	isect := offset/bp.sectsize;

	o := offset%bp.sectsize;
	while(count > 0) {
		addr = fileaddr(f, isect++, 1);
		if(addr < 0)
			break;
		c = bp.sectsize - o;
		if(c > count)
			c = count;
		if(c == bp.sectsize){
			p = getosect(xf, addr);
			if(p == nil)
				return -1;
			p.flags = 0;
		}else{
			p = getsect(xf, addr);
			if(p == nil)
				return -1;
		}
		p.iobuf[o:] = buf[rcnt:rcnt+c];
		p.flags |= BMOD;
		putsect(p);
		count -= c;
		rcnt += c;
		o = 0;
	}
	if(rcnt <= 0 && addr < 0)
		return -2;
	length := 0;
	dlen := bytes2int(d.length);
	if(rcnt > 0)
		length = offset+rcnt;
	else if(dp.addr && dp.clust) {
		c = bp.clustsize*bp.sectsize;
		if(dp.iclust > (dlen+c-1)/c)
			length = c*dp.iclust;
	}
	if(length > dlen) {
		d.length[0] = byte length;
		d.length[1] = byte (length>>8);
		d.length[2] = byte (length>>16);
		d.length[3] = byte (length>>24);
	}
	puttime(d);
	dp.p.flags |= BMOD;
	dp.p.iobuf[dp.offset:] = Dosdir.Dd2arr(d);
	return rcnt;
}

truncfile(f: ref Xfile): int
{
	xf := f.xf;
	bp := xf.ptr;
	dp := f.ptr;
	d := Dosdir.arr2Dd(dp.p.iobuf[dp.offset:dp.offset+DOSDIRSIZE]);

	clust := getstart(f.xf, d);
	putstart(f.xf, d, 0);
	while(clust > 0) {
		next := getfat(xf, clust);
		putfat(xf, clust, 0);
		clust = next;
	}

	d.length[0] = byte 0;
	d.length[1] = byte 0;
	d.length[2] = byte 0;
	d.length[3] = byte 0;

	dp.p.iobuf[dp.offset:] = Dosdir.Dd2arr(d);
	dp.iclust = 0;
	dp.clust = 0;
	dp.p.flags |= BMOD;

	return 0;
}

getdir(arr: array of byte, addr,offset: int) :ref Sys->Dir 
{
	dp := ref Sys->Dir;

	if(arr == nil || addr == 0) {
		dp.name = "";
		dp.qid.path = big 0;
		dp.qid.qtype = Sys->QTDIR;
		dp.length = big 0;
		dp.mode = Sys->DMDIR|8r777;
	}
	else {
		dp.name = getname(arr);
		for(i:=0; i < len dp.name; i++)
			if(dp.name[i]>='A' && dp.name[i]<='Z')
				dp.name[i] = dp.name[i]-'A'+'a';

		# dp.qid.path = bytes2short(d.start); 
		dp.qid.path = big (addr*(Sectorsize/DOSDIRSIZE) + offset/DOSDIRSIZE);
		dattr := int arr[11];

		if(dattr & DRONLY)
			dp.mode = 8r444;
		else
			dp.mode = 8r666;

		dp.atime = gtime(arr);
		dp.mtime = dp.atime;
		if(dattr & DDIR) {
			dp.length = big 0;
			dp.qid.qtype |= Styx->QTDIR;
			dp.mode |= Sys->DMDIR|8r111;
		}
		else 
			dp.length = big bytes2int(arr[28:32]);

		if(dattr & DSYSTEM){
			dp.mode |= Styx->DMEXCL;
			dp.qid.qtype |= Styx->QTEXCL;
		}
	}

	dp.qid.vers = 0;
	dp.dtype = 0;
	dp.dev = 0;
	dp.uid = "dos";
	dp.gid = "srv";

	return dp;
}

putdir(d: ref Dosdir, dp: ref Sys->Dir)
{
	if(dp.mode & 2)
		d.attr &= byte ~DRONLY;
	else
		d.attr |= byte DRONLY;

	if(dp.mode & Styx->DMEXCL)
		d.attr |= byte DSYSTEM;
	else
		d.attr &= byte ~DSYSTEM;
	xputtime(d, dp.mtime);
}

getname(arr: array of byte): string
{
	p: string;
	for(i:=0; i<8; i++) {
		c := int arr[i];
		if(c == 0 || c == ' ')
			break;
		if(i == 0 && c == 16r05)
			c = 16re5;
		p[len p] = c;
	}
	for(i=8; i<11; i++) {
		c := int arr[i];
		if(c == 0 || c == ' ')
			break;
		if(i == 8)
			p[len p] = '.';
		p[len p] = c;
	}

	return p;
}

dosname(p: string): (string, string)
{
	name := "        ";
	for(i := 0; i < len p && i < 8; i++) {
		c := p[i];
		if(c >= 'a' && c <= 'z')
			c += 'A'-'a';
		else if(c == '.')
			break;
		name[i] = c;
	}
	ext := "   ";
	for(j := len p - 1; j >= i; j--) {
		if(p[j] == '.') {
			q := 0;
			for(j++; j < len p && q < 3; j++) {
				c := p[j];
				if(c >= 'a' && c <= 'z')
					c += 'A'-'a';
				ext[q++] = c;
			}
			break;
		}
	}
	return (name, ext);
}

putname(p: string, d: ref Dosdir)
{
	if ((int d.attr & DLONG) == DLONG)
		panic("putname of long name");
	(d.name, d.ext) = dosname(p);
}

mystrcmp(s1, s2: string): int
{
	n := len s1;
	if(n != len s2)
		return 1;

	for(i := 0; i < n; i++) {
		c := s1[i];
		if(c >= 'A' && c <= 'Z')
			c -= 'A'-'a';
		d := s2[i];
		if(d >= 'A' && d <= 'Z')
			d -= 'A'-'a';
		if(c != d)
			return 1;
	}
	return 0;
}

#
# return the length of a long name in directory
# entries or zero if it's normal dos
#
name2de(p: string): int
{
	ext := 0;
	name := 0;

	for(end := len p; --end >= 0 && p[end] != '.';)
		ext++;

	if(end > 0) {
		name = end;
		for(i := 0; i < end; i++) {
			if(p[i] == '.')
				return (len p+DOSRUNES-1)/DOSRUNES;
		}
	}
	else {
		name = ext;
		ext = 0;
	}

	if(name <= 8 && ext <= 3 && isvalidname(p))
		return 0;

	return (len p+DOSRUNES-1)/DOSRUNES;
}

isvalidname(s: string): int
{
	dot := 0;
	for(i := 0; i < len s; i++)
		if(s[i] == '.') {
			if(++dot > 1 || i == len s-1)
				return 0;
		} else if(s[i] > len isdos || isdos[s[i]] == 0)
			return 0;
	return 1;
}

getnamesect(arr: array of byte): string
{
	s: string;
	c: int;

	for(i := 1; i < 11; i += 2) {
		c = int arr[i] | (int arr[i+1] << 8);
		if(c == 0)
			return s;
		s[len s] = c;
	}
	for(i = 14; i < 26; i += 2) {
		c = int arr[i] | (int arr[i+1] << 8);
		if(c == 0)
			return s;
		s[len s] = c;
	}
	for(i = 28; i < 32; i += 2) {
		c = int arr[i] | (int arr[i+1] << 8);
		if(c == 0)
			return s;
		s[len s] = c;
	}
	return s;
}

# takes a long filename and converts to a short dos name, with a tag number.
long2short(src: string,val: int): string
{
	dst :="           ";
	skip:=0;
	xskip:=0;
	ext:=len src-1;
	while(ext>=0 && src[ext]!='.')
		ext--;

	if (ext < 0)
		ext=len src -1;

	# convert name eliding periods 
	j:=0;
	for(name := 0; name < ext && j<8; name++){
		c := src[name];
		if(c!='.' && c!=' ' && c!='\t') {
			if(c>='a' && c<='z')
				dst[j++] = c-'a'+'A';
			else
				dst[j++] = c;
		}	
		else
			skip++;
	}

	# convert extension 
	j=8;
	for(xname := ext+1; xname < len src && j<11; xname++) {
		c := src[xname];
		if(c!=' ' && c!='\t'){
			if (c>='a' && c<='z')
				dst[j++] = c-'a'+'A';
			else
				dst[j++] = c;
		}else
			xskip++;
	}
	
	# add tag number
	j =1; 
	for(i:=val; i > 0; i/=10)
		j++;

	if (8-j<name) 
		name = 8-j;
	else
		name -= skip;

	dst[name]='~';
	for(; val > 0; val /= 10)
		dst[name+ --j] = (val%10)+'0';

	if(debug)
		chat(sys->sprint("returning dst [%s] src [%s]\n",dst,src));

	return dst;			
}

getfat(xf: ref Xfs, n: int): int
{
	bp := xf.ptr;
	k := 0; 

	if(n < 2 || n >= bp.fatclusters)
		return -1;
	fb := bp.fatbits;
	k = (fb*n) >> 3;
	if(k < 0 || k >= bp.fatsize*bp.sectsize)
		panic("getfat");

	sect := k/bp.sectsize + bp.fataddr;
	o := k%bp.sectsize;
	p := getsect(xf, sect);
	if(p == nil)
		return -1;
	k = int p.iobuf[o++];
	if(o >= bp.sectsize) {
		putsect(p);
		p = getsect(xf, sect+1);
		if(p == nil)
			return -1;
		o = 0;
	}
	k |= int p.iobuf[o++]<<8;
	if(fb == 32){
		# fat32 is really fat28
		k |= int p.iobuf[o++] << 16;
		k |= (int p.iobuf[o] & 16r0F) << 24;
		fb = 28;
	}
	putsect(p);
	if(fb == 12) {
		if(n&1)
			k >>= 4;
		else
			k &= 16rfff;
	}

	if(debug & FAT_INFO)
		chat(sys->sprint("fat(0x%x)=0x%x...", n, k));

	#
	# check for out of range
	#
	if(k >= (1<<fb) - 8)
		return -1;
	return k;
}

putfat(xf: ref Xfs, n, val: int)
{
	bp := xf.ptr;
	if(n < 2 || n >= bp.fatclusters)
		panic(sys->sprint("putfat n=%d", n));
	k := (bp.fatbits*n) >> 3;
	if(k >= bp.fatsize*bp.sectsize)
		panic("putfat");
	sect := k/bp.sectsize + bp.fataddr;
	for(; sect<bp.rootaddr; sect+=bp.fatsize) {
		o := k%bp.sectsize;
		p := getsect(xf, sect);
		if(p == nil)
			continue;
		case bp.fatbits {
		12 =>
			if(n&1) {
				p.iobuf[o] &= byte 16r0f;
				p.iobuf[o++] |= byte (val<<4);
				if(o >= bp.sectsize) {
					p.flags |= BMOD;
					putsect(p);
					p = getsect(xf, sect+1);
					if(p == nil)
						continue;
					o = 0;
				}
				p.iobuf[o] = byte (val>>4);
			}
			else {
				p.iobuf[o++] = byte val;
				if(o >= bp.sectsize) {
					p.flags |= BMOD;
					putsect(p);
					p = getsect(xf, sect+1);
					if(p == nil)
						continue;
					o = 0;
				}
				p.iobuf[o] &= byte 16rf0;
				p.iobuf[o] |= byte ((val>>8)&16r0f);
			}
		16 =>
			p.iobuf[o++] = byte val;
			p.iobuf[o] = byte (val>>8);
		32 =>	# fat32 is really fat28
			p.iobuf[o++] = byte val;
			p.iobuf[o++] = byte (val>>8);
			p.iobuf[o++] = byte (val>>16);
			p.iobuf[o] = byte ((int p.iobuf[o] & 16rF0) | ((val>>24) & 16r0F));
		* =>
			panic("putfat fatbits");
		}

		p.flags |= BMOD;
		putsect(p);
	}
}

falloc(xf: ref Xfs): int
{
	bp := xf.ptr;
	n := bp.freeptr;
	for(;;) {
		if(getfat(xf, n) == 0)
			break;
		if(++n >= bp.fatclusters)
			n = FATRESRV;
		if(n == bp.freeptr)
			return 0;
	}
	bp.freeptr = n+1;
	if(bp.freeptr >= bp.fatclusters)
		bp.freeptr = FATRESRV;
	putfat(xf, n, int 16rffffffff);
	k := clust2sect(bp, n);
	for(i:=0; i<bp.clustsize; i++) {
		p := getosect(xf, k+i);
		if(p == nil)
			return -1;
		for(j:=0; j<len p.iobuf; j++)
			p.iobuf[j] = byte 0;
		p.flags = BMOD;
		putsect(p);
	}
	return n;
}

clust2sect(bp: ref Dosbpb, clust: int): int
{
	return bp.dataaddr + (clust - FATRESRV)*bp.clustsize;
}

sect2clust(bp: ref Dosbpb, sect: int): int
{
	c := (sect - bp.dataaddr) / bp.clustsize + FATRESRV;
	# assert(sect == clust2sect(bp, c));
	return c;
}

bootdump(b: ref Dosboot)
{
	chat(sys->sprint("magic: 0x%2.2x 0x%2.2x 0x%2.2x\n",
		int b.magic[0], int b.magic[1], int b.magic[2]));
	chat(sys->sprint("version: \"%8.8s\"\n", string b.version));
	chat(sys->sprint("sectsize: %d\n", bytes2short(b.sectsize)));
	chat(sys->sprint("allocsize: %d\n", int b.clustsize));
	chat(sys->sprint("nresrv: %d\n", bytes2short(b.nresrv)));
	chat(sys->sprint("nfats: %d\n", int b.nfats));
	chat(sys->sprint("rootsize: %d\n", bytes2short(b.rootsize)));
	chat(sys->sprint("volsize: %d\n", bytes2short(b.volsize)));
	chat(sys->sprint("mediadesc: 0x%2.2x\n", int b.mediadesc));
	chat(sys->sprint("fatsize: %d\n", bytes2short(b.fatsize)));
	chat(sys->sprint("trksize: %d\n", bytes2short(b.trksize)));
	chat(sys->sprint("nheads: %d\n", bytes2short(b.nheads)));
	chat(sys->sprint("nhidden: %d\n", bytes2int(b.nhidden)));
	chat(sys->sprint("bigvolsize: %d\n", bytes2int(b.bigvolsize)));
	chat(sys->sprint("driveno: %d\n", int b.driveno));
	chat(sys->sprint("bootsig: 0x%2.2x\n", int b.bootsig));
	chat(sys->sprint("volid: 0x%8.8x\n", bytes2int(b.volid)));
	chat(sys->sprint("label: \"%11.11s\"\n", string b.label));
}

xputtime(d: ref Dosdir, s: int)
{
	if(s == 0)
		t := daytime->local((sys->millisec() - nowt1)/1000 + nowt);
	else
		t = daytime->local(s);
	x := (t.hour<<11) | (t.min<<5) | (t.sec>>1);
	d.time[0] = byte x;
	d.time[1] = byte (x>>8);
	x = ((t.year-80)<<9) | ((t.mon+1)<<5) | t.mday;
	d.date[0] = byte x;
	d.date[1] = byte (x>>8);
}

puttime(d: ref Dosdir)
{
	xputtime(d, 0);
}

gtime(a: array of byte): int
{
	tm := ref Daytime->Tm;
	i := bytes2short(a[22:24]);	# dos time
	tm.hour = i >> 11;
	tm.min = (i>>5) & 63;
	tm.sec = (i & 31) << 1;
	i = bytes2short(a[24:26]);	# dos date
	tm.year = 80 + (i>>9);
	tm.mon = ((i>>5) & 15) - 1;
	tm.mday = i & 31;
	tm.tzoff = tzoff;	# DOS time is local time
	return daytime->tm2epoch(tm);
}

dirdump(arr: array of byte, addr, offset: int)
{
	if(!debug)
		return;
	attrchar:= "rhsvda67";
	d := Dosdir.arr2Dd(arr);
	buf := sys->sprint("\"%.8s.%.3s\" ", d.name, d.ext);
	p_i:=7;

	for(i := 16r80; i != 0; i >>= 1) {
		if((d.attr & byte i) ==  byte i)
			ch := attrchar[p_i];
		else 
			ch = '-'; 
		buf += sys->sprint("%c", ch);
		p_i--;
	}

	i = bytes2short(d.time);
	buf += sys->sprint(" %2.2d:%2.2d:%2.2d", i>>11, (i>>5)&63, (i&31)<<1);
	i = bytes2short(d.date);
	buf += sys->sprint(" %2.2d.%2.2d.%2.2d", 80+(i>>9), (i>>5)&15, i&31);
	buf += sys->sprint(" %d %d", bytes2short(d.start), bytes2short(d.length));
	buf += sys->sprint(" %d %d\n",addr,offset);
	chat(buf);
}

putnamesect(longname: string, curslot: int, first: int, sum: int, a: array of byte)
{
	for(i := 0; i < DOSDIRSIZE; i++)
		a[i] = byte 16rFF;
	if(first)
		a[0] = byte (16r40 | curslot);
	else 
		a[0] = byte curslot;
	a[11] = byte DLONG;
	a[12] = byte 0;
	a[13] = byte sum;
	a[26] = byte 0;
	a[27] = byte 0;
	# a[1:1+10] = characters 1 to 5
	n := len longname;
	j := (curslot-1)*DOSRUNES;
	for(i = 1; i < 1+10; i += 2){
		c := 0;
		if(j < n)
			c = longname[j++];
		a[i] = byte c;
		a[i+1] = byte (c >> 8);
		if(c == 0)
			return;
	}
	# a[14:14+12] = characters 6 to 11
	for(i = 14; i < 14+12; i += 2){
		c := 0;
		if(j < n)
			c = longname[j++];
		a[i] = byte c;
		a[i+1] = byte (c >> 8);
		if(c == 0)
			return;
	}
	# a[28:28+4] characters 12 to 13
	for(i = 28; i < 28+4; i += 2){
		c := 0;
		if(j < n)
			c = longname[j++];
		a[i] = byte c;
		a[i+1] = byte (c>>8);
		if(c == 0)
			return;
	}
}

putlongname(xf: ref Xfs, ndp: ref Dosptr, name: string, sname: string): int
{
	bp := xf.ptr;
	first := 1;
	sum := aliassum(sname);
	for(nds := (len name+DOSRUNES-1)/DOSRUNES; nds > 0; nds--) {
		putnamesect(name, nds, first, sum, ndp.p.iobuf[ndp.offset:]);
		first = 0;
		ndp.offset += DOSDIRSIZE;
		if(ndp.offset == bp.sectsize) {
			if(debug)
				chat(sys->sprint("long name %s entry %d/%d crossing sector, addr=%d, naddr=%d", name, nds, (len name+DOSRUNES-1)/DOSRUNES, ndp.addr, ndp.naddr));
			ndp.p.flags |= BMOD;
			putsect(ndp.p);
			ndp.p = nil;
			ndp.d = nil;

			# switch to the next cluster for the next long entry or the subsequent normal dir. entry
			# naddr must be set up correctly by searchdir because we'll need one or the other

			ndp.prevaddr = ndp.addr;
			ndp.addr = ndp.naddr;
			ndp.naddr = -1;
			if(ndp.addr < 0)
				return -1;
			ndp.p = getsect(xf, ndp.addr);
			if(ndp.p == nil)
				return -1;
			ndp.offset = 0;
		}
	}
	return 0;
}

bytes2int(a: array of byte): int 
{
	return (((((int a[3] << 8) | int a[2]) << 8) | int a[1]) << 8) | int a[0];
}

bytes2short(a: array of byte): int 
{
	return (int a[1] << 8) | int a[0];
}

chat(s: string)
{
	if(debug)
		sys->fprint(sys->fildes(2), "%s", s);
}

panic(s: string)
{
	sys->fprint(sys->fildes(2), "dosfs: panic: %s\n", s);
	if(pflag)
		<-chan of int;	# hang here
	raise "fail:panic";
}

Dosboot.arr2Db(arr: array of byte): ref Dosboot
{
	db := ref Dosboot;
	db.magic = arr[0:3];
	db.version = arr[3:11];
	db.sectsize = arr[11:13];
	db.clustsize = arr[13];
	db.nresrv = arr[14:16];
	db.nfats = arr[16];
	db.rootsize = arr[17:19];
	db.volsize = arr[19:21];
	db.mediadesc = arr[21];
	db.fatsize = arr[22:24];
	db.trksize = arr[24:26];
	db.nheads = arr[26:28];
	db.nhidden = arr[28:32];
	db.bigvolsize = arr[32:36];
	db.driveno = arr[36];
	db.bootsig = arr[38];
	db.volid = arr[39:43];
	db.label = arr[43:54];
	return db;
}

Dosdir.arr2Dd(arr: array of byte): ref Dosdir
{
	dir := ref Dosdir;
	for(i := 0; i < 8; i++)
		dir.name[len dir.name] = int arr[i];
	for(; i < 11; i++)
		dir.ext[len dir.ext] = int arr[i];
	dir.attr = arr[11];
	dir.reserved = arr[12:22];
	dir.time = arr[22:24];
	dir.date = arr[24:26];
	dir.start = arr[26:28];
	dir.length = arr[28:32];
	return dir;
}

Dosdir.Dd2arr(d: ref Dosdir): array of byte
{
	a := array[32] of byte;
	i:=0;
	for(j := 0; j < len d.name; j++)
		a[i++] = byte d.name[j];
	for(; j<8; j++)
		a[i++]= byte 0;
	for(j=0; j<len d.ext; j++)
		a[i++] = byte d.ext[j];
	for(; j<3; j++)
		a[i++]= byte 0;
	a[i++] = d.attr;
	for(j=0; j<10; j++)
		a[i++] = d.reserved[j];
	for(j=0; j<2; j++)
		a[i++] = d.time[j];
	for(j=0; j<2; j++)
		a[i++] = d.date[j];
	for(j=0; j<2; j++)
		a[i++] = d.start[j];
	for(j=0; j<4; j++)
		a[i++] = d.length[j];
	return a;
}

#
# checksum of short name for use in long name directory entries
# assumes sname is already padded correctly to 8+3
#
aliassum(sname: string): int
{
	i := 0;
	for(sum:=0; i<11; i++)
		sum = (((sum&1)<<7)|((sum&16rfe)>>1))+sname[i];
	return sum;
}

#
# track i/o
#

# An Xfs represents the root of an external file system, anchored
# to the server and the client
Xfs: adt {
	next:cyclic ref Xfs;
	name: string;	# of file containing external f.s. 
	qid: Sys->Qid;	# of file containing external f.s. 
	refn: int;		# attach count 
	rootqid: Sys->Qid;	# of inferno constructed root directory 
	dev: ref Sys->FD;  # FD of the file containing external f.s.
	fmt: int;		# successfully read format
	offset: int;		# offset in sectors to file system
	ptr: ref Dosbpb;
};

# An Xfile represents the mapping of fid's & qid's to the server.
Xfile: adt {
	next: cyclic ref Xfile;		# in hash bucket 
	client: int;
	fid: int;
	flags: int;
	qid: Sys->Qid;
	xf: ref Xfs;
	ptr: ref Dosptr;
};

Iosect: adt
{
	next: cyclic ref Iosect;
	flags: int;
	t: cyclic ref Iotrack;
	iobuf: array of byte;
};

Iotrack: adt 
{
	flags: int;
	xf: ref Xfs;
	addr: int;
	next: cyclic ref Iotrack;		# in lru list 
	prev: cyclic ref Iotrack;
	hnext: cyclic ref Iotrack;		# in hash list 
	hprev: cyclic ref Iotrack;
	refn: int;
	tp: cyclic ref Track;
};

Track: adt
{
	create: fn(): ref Track;
	p: cyclic array of ref Iosect;
	buf: array of byte;
};

BMOD: con	1<<0;
BIMM: con	1<<1;
BSTALE: con	1<<2;

HIOB: con 31;	# a prime 
NIOBUF: con 20;

Sectorsize: con 512;
Sect2trk: con 9;	# default

hiob := array[HIOB+1] of ref Iotrack;		# hash buckets + lru list
iobuf := array[NIOBUF] of ref Iotrack;		# the real ones
freelist: ref Iosect;
sect2trk := Sect2trk;
trksize := Sect2trk*Sectorsize;

FIDMOD: con 127;	# prime
xhead:		ref Xfs;
client:		int;

xfiles := array[FIDMOD] of ref Xfile;
iodebug := 0;

iotrackinit(sectors: int)
{
	if(sectors <= 0)
		sectors = 9;
	sect2trk = sectors;
	trksize = sect2trk*Sectorsize;

	freelist = nil;

	for(i := 0;i < FIDMOD; i++)
		xfiles[i] = ref Xfile(nil,0,0,0,Sys->Qid(big 0,0,0),nil,nil);

	for(i = 0; i <= HIOB; i++)
		hiob[i] = ref Iotrack;

	for(i = 0; i < HIOB; i++) {
		hiob[i].hprev = hiob[i];
		hiob[i].hnext = hiob[i];
		hiob[i].refn = 0;
		hiob[i].addr = 0;
	}
	hiob[i].prev = hiob[i];
	hiob[i].next = hiob[i];
	hiob[i].refn = 0;
	hiob[i].addr = 0;

	for(i=0;i<NIOBUF;i++)
		iobuf[i] = ref Iotrack;

	for(i=0; i<NIOBUF; i++) {
		iobuf[i].hprev = iobuf[i].hnext = iobuf[i];
		iobuf[i].prev = iobuf[i].next = iobuf[i];
		iobuf[i].refn=iobuf[i].addr=0;
		iobuf[i].flags = 0;
		if(hiob[HIOB].next != iobuf[i]) {
			iobuf[i].prev.next = iobuf[i].next;
			iobuf[i].next.prev = iobuf[i].prev;
			iobuf[i].next = hiob[HIOB].next;
			iobuf[i].prev = hiob[HIOB];
			hiob[HIOB].next.prev = iobuf[i];
			hiob[HIOB].next = iobuf[i];
		}
		iobuf[i].tp =  Track.create();
	}
}

Track.create(): ref Track
{
	t := ref Track;
	t.p = array[sect2trk] of ref Iosect;
	t.buf = array[trksize] of byte;
	return t;
}

getsect(xf: ref Xfs, addr: int): ref Iosect
{
	return getiosect(xf, addr, 1);
}

getosect(xf: ref Xfs, addr: int): ref Iosect
{
	return getiosect(xf, addr, 0);
}

# get the sector corresponding to the address addr.
getiosect(xf: ref Xfs, addr , rflag: int): ref Iosect
{
	# offset from beginning of track.
	toff := addr %  sect2trk;

	# address of beginning of track.
	taddr := addr -  toff;
	t := getiotrack(xf, taddr);

	if(rflag && t.flags&BSTALE) {
		if(tread(t) < 0)
			return nil;

		t.flags &= ~BSTALE;
	}

	t.refn++;
	if(t.tp.p[toff] == nil) {
		p := newsect();
		t.tp.p[toff] = p;
		p.flags = t.flags&BSTALE;
		p.t = t;
		p.iobuf = t.tp.buf[toff*Sectorsize:(toff+1)*Sectorsize];
	}
	return t.tp.p[toff];
}

putsect(p: ref Iosect)
{
	t: ref Iotrack;

	t = p.t;
	t.flags |= p.flags;
	p.flags = 0;
	t.refn--;
	if(t.refn < 0)
		panic("putsect: refcount");

	if(t.flags & BIMM) {
		if(t.flags & BMOD)
			twrite(t);
		t.flags &= ~(BMOD|BIMM);
	}
}

# get the track corresponding to addr
# (which is the address of the beginning of a track
getiotrack(xf: ref Xfs, addr: int): ref Iotrack
{
	p: ref Iotrack;
	mp := hiob[HIOB];
	
	if(iodebug)
		chat(sys->sprint("iotrack %d,%d...", xf.dev.fd, addr));

	# find bucket in hash table.
	h := (xf.dev.fd<<24) ^ addr;
	if(h < 0)
		h = ~h;
	h %= HIOB;
	hp := hiob[h];

	out: for(;;){
		loop: for(;;) {
		 	# look for it in the active list
			for(p = hp.hnext; p != hp; p=p.hnext) {
				if(p.addr != addr || p.xf != xf)
					continue;
				if(p.addr == addr && p.xf == xf) {
					break out;
				}
				continue loop;
			}
		
		 	# not found
		 	# take oldest unref'd entry
			for(p = mp.prev; p != mp; p=p.prev)
				if(p.refn == 0 )
					break;
			if(p == mp) {
				if(iodebug)
					chat("iotrack all ref'd\n");
				continue loop;
			}

			if((p.flags & BMOD)!= 0) {
				twrite(p);
				p.flags &= ~(BMOD|BIMM);
				continue loop;
			}
			purgetrack(p);
			p.addr = addr;
			p.xf = xf;
			p.flags = BSTALE;
			break out;
		}
	}

	if(hp.hnext != p) {
		p.hprev.hnext = p.hnext;
		p.hnext.hprev = p.hprev;			
		p.hnext = hp.hnext;
		p.hprev = hp;
		hp.hnext.hprev = p;
		hp.hnext = p;
	}
	if(mp.next != p) {
		p.prev.next = p.next;
		p.next.prev = p.prev;
		p.next = mp.next;
		p.prev = mp;
		mp.next.prev = p;
		mp.next = p;			
	}
	return p;
}

purgetrack(t: ref Iotrack)
{
	refn := sect2trk;
	for(i := 0; i < sect2trk; i++) {
		if(t.tp.p[i] == nil) {
			--refn;
			continue;
		}
		freesect(t.tp.p[i]);
		--refn;
		t.tp.p[i]=nil;
	}
	if(t.refn != refn)
		panic("purgetrack");
	if(refn!=0)
		panic("refn not 0");
}

twrite(t: ref Iotrack): int
{
	if(iodebug)
		chat(sys->sprint("[twrite %d...", t.addr));

	if((t.flags & BSTALE)!= 0) {
		refn:=0;
		for(i:=0; i<sect2trk; i++)
			if(t.tp.p[i]!=nil)
				++refn;

		if(refn < sect2trk) {
			if(tread(t) < 0) {
				if (iodebug)
					chat("error]");
				return -1;
			}
		}
		else
			t.flags &= ~BSTALE;
	}

	if(devwrite(t.xf, t.addr, t.tp.buf) < 0) {
		if(iodebug)
			chat("error]");
		return -1;
	}

	if(iodebug)
		chat(" done]");

	return 0;
}

tread(t: ref Iotrack): int
{
	refn := 0;
	rval: int;

	for(i := 0; i < sect2trk; i++)
		if(t.tp.p[i] != nil)
			++refn;

	if(iodebug)
		chat(sys->sprint("[tread %d...", t.addr));

	tbuf := t.tp.buf;
	if(refn != 0)
		tbuf = array[trksize] of byte;

	rval = devread(t.xf, t.addr, tbuf);
	if(rval < 0) {
		if(iodebug)
			chat("error]");
		return -1;
	}

	if(refn != 0) {
		for(i=0; i < sect2trk; i++) {
			if(t.tp.p[i] == nil) {
				t.tp.buf[i*Sectorsize:]=tbuf[i*Sectorsize:(i+1)*Sectorsize];
				if(iodebug)
					chat(sys->sprint("%d ", i));
			}
		}
	}

	if(iodebug)
		chat("done]");

	t.flags &= ~BSTALE;
	return 0;
}

purgebuf(xf: ref Xfs)
{
	for(p := 0; p < NIOBUF; p++) {
		if(iobuf[p].xf != xf)
			continue;
		if(iobuf[p].xf == xf) {
			if((iobuf[p].flags & BMOD) != 0)
				twrite(iobuf[p]);

			iobuf[p].flags = BSTALE;
			purgetrack(iobuf[p]);
		}
	}
}

sync()
{
	for(p := 0; p < NIOBUF; p++) {
		if(!(iobuf[p].flags & BMOD))
			continue;

		if(iobuf[p].flags & BMOD){
			twrite(iobuf[p]);
			iobuf[p].flags &= ~(BMOD|BIMM);
		}
	}
}


newsect(): ref Iosect
{
	if((p := freelist)!=nil)	{
		freelist = p.next;
		p.next = nil;
	} else
		p = ref Iosect(nil, 0, nil,nil);

	return p;
}

freesect(p: ref Iosect)
{
	p.next = freelist;
	freelist = p;
}


# devio from here
deverror(name: string, xf: ref Xfs, addr,n,nret: int): int
{
	if(nret < 0) {
		if(iodebug)
			chat(sys->sprint("%s errstr=\"%r\"...", name));
		xf.dev = nil;
		return -1;
	}
	if(iodebug)
		chat(sys->sprint("dev %d sector %d, %s: %d, should be %d\n",
			xf.dev.fd, addr, name, nret, n));

	panic(name);
	return -1;
}

devread(xf: ref Xfs, addr: int, buf: array of byte): int
{
	if(xf.dev==nil)
		return -1;

	sys->seek(xf.dev, big (xf.offset+addr*Sectorsize), sys->SEEKSTART);
	nread := sys->read(xf.dev, buf, trksize);
	if(nread != trksize)
		return deverror("read", xf, addr, trksize, nread);

	return 0;
}

devwrite(xf: ref Xfs, addr: int, buf: array of byte): int
{
	if(xf.dev == nil)
		return -1;

	sys->seek(xf.dev, big (xf.offset+addr*Sectorsize), 0);
	nwrite := sys->write(xf.dev, buf, trksize);
	if(nwrite != trksize)
		return deverror("write", xf, addr, trksize , nwrite);

	return 0;
}

devcheck(xf: ref Xfs): int
{
	buf := array[Sectorsize] of byte;

	if(xf.dev == nil)
		return -1;

	sys->seek(xf.dev, big 0, sys->SEEKSTART);
	if(sys->read(xf.dev, buf, Sectorsize) != Sectorsize){
		xf.dev = nil;
		return -1;
	}

	return 0;
}

# setup and return the Xfs associated with "name"

getxfs(name: string): (ref Xfs, string)
{
	if(name == nil)
		return (nil, "no file system device specified");

	
	 # If the name passed is of the form 'name:offset' then
	 # offset is used to prime xf->offset. This allows accessing
	 # a FAT-based filesystem anywhere within a partition.
	 # Typical use would be to mount a filesystem in the presence
	 # of a boot manager programm at the beginning of the disc.
	
	offset := 0;
	for(i := 0;i < len name; i++)
		if(name[i]==':')
			break;

	if(i < len name) {
		offset = int name[i+1:];
		if(offset < 0)
			return (nil, "invalid device offset to file system");
		offset *= Sectorsize;
		name = name[0:i];
	}

	fd := sys->open(name, Sys->ORDWR);
	if(fd == nil) {
		if(iodebug)
			chat(sys->sprint("getxfs: open(%s) failed: %r\n", name));
		return (nil, sys->sprint("can't open %s: %r", name));
	}

	(rval,dir) := sys->fstat(fd);
	if(rval < 0)
		return (nil, sys->sprint("can't stat %s: %r", name));
	
	# lock down the list of xf's.
	fxf: ref Xfs;
	for(xf := xhead; xf != nil; xf = xf.next) {
		if(xf.refn == 0) {
			if(fxf == nil)
				fxf = xf;
			continue;
		}
		if(xf.qid.path != dir.qid.path || xf.qid.vers != dir.qid.vers)
			continue;

		if(xf.name!= name || xf.dev == nil)
			continue;

		if(devcheck(xf) < 0) # look for media change
			continue;

		if(offset && xf.offset != offset)
			continue;

		if(iodebug)
			chat(sys->sprint("incref \"%s\", dev=%d...",
				xf.name, xf.dev.fd));

		++xf.refn;
		return (xf, nil);
	}
	
	# this xf doesn't exist, make a new one and stick it on the list.
	if(fxf == nil){
		fxf = ref Xfs;
		fxf.next = xhead;
		xhead = fxf;
	}

	if(iodebug)
		chat(sys->sprint("alloc \"%s\", dev=%d...", name, fd.fd));

	fxf.name = name;
	fxf.refn = 1;
	fxf.qid = dir.qid;
	fxf.dev = fd;
	fxf.fmt = 0;
	fxf.offset = offset;
	return (fxf, nil);
}

refxfs(xf: ref Xfs, delta: int)
{
	xf.refn += delta;
	if(xf.refn == 0) {
		if (iodebug)
			chat(sys->sprint("free \"%s\", dev=%d...",
				xf.name, xf.dev.fd));

		purgebuf(xf);
		if(xf.dev !=nil)
			xf.dev = nil;
	}
}

xfile(fid, flag: int): ref Xfile
{
	pf: ref Xfile;

	# find hashed file list in LRU? table.
	k := (fid^client)%FIDMOD;

	# find if this fid is in the hashed file list.
	f:=xfiles[k];
	for(pf = nil; f != nil; f = f.next) {
		if(f.fid == fid && f.client == client)
			break;
		pf=f;
	}
	
	# move this fid to the front of the list if it was further down.
	if(f != nil && pf != nil){
		pf.next = f.next;
		f.next = xfiles[k];
		xfiles[k] = f;
	}

	case flag {
	* =>
		panic("xfile");
	Asis =>
		if(f != nil && f.xf != nil && f.xf.dev == nil)
			return nil;
		return f;
	Clean =>
		break;
	Clunk =>
		if(f != nil) {
			xfiles[k] = f.next;
			clean(f);
		}
		return nil;
	}

	# clean it up ..
	if(f != nil)
		return clean(f);

	# f wasn't found in the hashtable, make a new one and add it
	f = ref Xfile;
	f.next = xfiles[k];
	xfiles[k] = f;
	# sort out the fid, etc.
	f.fid = fid;
	f.client = client;
	f.flags = 0;
	f.qid = Sys->Qid(big 0, 0, Styx->QTFILE);
	f.xf = nil;
	f.ptr = ref Dosptr(0,0,0,0,0,0,-1,-1,nil,nil);
	return f;
}

clean(f: ref Xfile): ref Xfile
{
	f.ptr = nil;
	if(f.xf != nil) {
		refxfs(f.xf, -1);
		f.xf = nil;
	}
	f.flags = 0;
	f.qid = Sys->Qid(big 0, 0, 0);
	return f;
}

#
# the file at <addr, offset> has moved
# relocate the dos entries of all fids in the same file
#
dosptrreloc(f: ref Xfile, dp: ref Dosptr, addr: int, offset: int)
{
	i: int;
	p: ref Xfile;
	xdp: ref Dosptr;

	for(i=0; i < FIDMOD; i++){
		for(p = xfiles[i]; p != nil; p = p.next){
			xdp = p.ptr;
			if(p != f && p.xf == f.xf
			&& xdp != nil && xdp.addr == addr && xdp.offset == offset){
				*xdp = *dp;
				xdp.p = nil;
				# xdp.d = nil;
				p.qid.path = big QIDPATH(xdp);
			}
		}
	}
}
