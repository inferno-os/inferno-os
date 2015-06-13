implement Ninep;

include "sys.m";
	sys: Sys;

include "9p.m";

STR: con BIT16SZ;	# string length
TAG: con BIT16SZ;
FID: con BIT32SZ;
QID: con BIT8SZ+BIT32SZ+BIT64SZ;
LEN: con BIT16SZ;	# stat and qid array lengths
COUNT: con BIT32SZ;
OFFSET: con BIT64SZ;

H: con BIT32SZ+BIT8SZ+BIT16SZ;	# minimum header length: size[4] type tag[2]

#
# the following array could be shorter if it were indexed by (type-Tversion)
#
hdrlen := array[Tmax] of
{
Tversion =>	H+COUNT+STR,	# size[4] Tversion tag[2] msize[4] version[s]
Rversion =>	H+COUNT+STR,	# size[4] Rversion tag[2] msize[4] version[s]

Tauth =>	H+FID+STR+STR,		# size[4] Tauth tag[2] afid[4] uname[s] aname[s]
Rauth =>	H+QID,			# size[4] Rauth tag[2] aqid[13]

Rerror =>	H+STR,		# size[4] Rerror tag[2] ename[s]

Tflush =>	H+TAG,		# size[4] Tflush tag[2] oldtag[2]
Rflush =>	H,			# size[4] Rflush tag[2]

Tattach =>	H+FID+FID+STR+STR,	# size[4] Tattach tag[2] fid[4] afid[4] uname[s] aname[s]
Rattach =>	H+QID,		# size[4] Rattach tag[2] qid[13]

Twalk =>	H+FID+FID+LEN,	# size[4] Twalk tag[2] fid[4] newfid[4] nwname[2] nwname*(wname[s])
Rwalk =>	H+LEN,		# size[4] Rwalk tag[2] nwqid[2] nwqid*(wqid[13])

Topen =>	H+FID+BIT8SZ,		# size[4] Topen tag[2] fid[4] mode[1]
Ropen =>	H+QID+COUNT,	# size[4] Ropen tag[2] qid[13] iounit[4]

Tcreate =>	H+FID+STR+BIT32SZ+BIT8SZ,	# size[4] Tcreate tag[2] fid[4] name[s] perm[4] mode[1]
Rcreate =>	H+QID+COUNT,	# size[4] Rcreate tag[2] qid[13] iounit[4]

Tread =>	H+FID+OFFSET+COUNT,	# size[4] Tread tag[2] fid[4] offset[8] count[4]
Rread =>	H+COUNT,		# size[4] Rread tag[2] count[4] data[count]

Twrite =>	H+FID+OFFSET+COUNT,	# size[4] Twrite tag[2] fid[4] offset[8] count[4] data[count]
Rwrite =>	H+COUNT,	# size[4] Rwrite tag[2] count[4]

Tclunk =>	H+FID,	# size[4] Tclunk tag[2] fid[4]
Rclunk =>	H,		# size[4] Rclunk tag[2]

Tremove =>	H+FID,	# size[4] Tremove tag[2] fid[4]
Rremove =>	H,	# size[4] Rremove tag[2]

Tstat =>	H+FID,	# size[4] Tstat tag[2] fid[4]
Rstat =>	H+LEN,	# size[4] Rstat tag[2] stat[n]

Twstat =>	H+FID+LEN,	# size[4] Twstat tag[2] fid[4] stat[n]
Rwstat =>	H,	# size[4] Rwstat tag[2]
};

init()
{
	sys = load Sys Sys->PATH;
}

utflen(s: string): int
{
	# the domain is 16-bit unicode only, which is all that Inferno now implements
	n := l := len s;
	for(i:=0; i<l; i++)
		if((c := s[i]) > 16r7F){
			n++;
			if(c > 16r7FF)
				n++;
		}
	return n;
}

packdirsize(d: Sys->Dir): int
{
	return STATFIXLEN+utflen(d.name)+utflen(d.uid)+utflen(d.gid)+utflen(d.muid);
}

packdir(f: Sys->Dir): array of byte
{
	ds := packdirsize(f);
	a := array[ds] of byte;
	# size[2]
	a[0] = byte (ds-LEN);
	a[1] = byte ((ds-LEN)>>8);
	# type[2]
	a[2] = byte f.dtype;
	a[3] = byte (f.dtype>>8);
	# dev[4]
	a[4] = byte f.dev;
	a[5] = byte (f.dev>>8);
	a[6] = byte (f.dev>>16);
	a[7] = byte (f.dev>>24);
	# qid.type[1]
	# qid.vers[4]
	# qid.path[8]
	pqid(a, 8, f.qid);
	# mode[4]
	a[21] = byte f.mode;
	a[22] = byte (f.mode>>8);
	a[23] = byte (f.mode>>16);
	a[24] = byte (f.mode>>24);
	# atime[4]
	a[25] = byte f.atime;
	a[26] = byte (f.atime>>8);
	a[27] = byte (f.atime>>16);
	a[28] = byte (f.atime>>24);
	# mtime[4]
	a[29] = byte f.mtime;
	a[30] = byte (f.mtime>>8);
	a[31] = byte (f.mtime>>16);
	a[32] = byte (f.mtime>>24);
	# length[8]
	p64(a, 33, big f.length);
	# name[s]
	i := pstring(a, 33+BIT64SZ, f.name);
	i = pstring(a, i, f.uid);
	i = pstring(a, i, f.gid);
	i = pstring(a, i, f.muid);
	if(i != len a)
		raise "assertion: Ninep->packdir: bad count";	# can't happen unless packedsize is wrong
	return a;
}

pqid(a: array of byte, o: int, q: Sys->Qid): int
{
	a[o] = byte q.qtype;
	v := q.vers;
	a[o+1] = byte v;
	a[o+2] = byte (v>>8);
	a[o+3] = byte (v>>16);
	a[o+4] = byte (v>>24);
	v = int q.path;
	a[o+5] = byte v;
	a[o+6] = byte (v>>8);
	a[o+7] = byte (v>>16);
	a[o+8] = byte (v>>24);
	v = int (q.path >> 32);
	a[o+9] = byte v;
	a[o+10] = byte (v>>8);
	a[o+11] = byte (v>>16);
	a[o+12] = byte (v>>24);
	return o+QID;
}

pstring(a: array of byte, o: int, s: string): int
{
	sa := array of byte s;	# could do conversion ourselves
	n := len sa;
	a[o] = byte n;
	a[o+1] = byte (n>>8);
	a[o+2:] = sa;
	return o+LEN+n;
}

p32(a: array of byte, o: int, v: int): int
{
	a[o] = byte v;
	a[o+1] = byte (v>>8);
	a[o+2] = byte (v>>16);
	a[o+3] = byte (v>>24);
	return o+BIT32SZ;
}

p64(a: array of byte, o: int, b: big): int
{
	i := int b;
	a[o] = byte i;
	a[o+1] = byte (i>>8);
	a[o+2] = byte (i>>16);
	a[o+3] = byte (i>>24);
	i = int (b>>32);
	a[o+4] = byte i;
	a[o+5] = byte (i>>8);
	a[o+6] = byte (i>>16);
	a[o+7] = byte (i>>24);
	return o+BIT64SZ;
}

unpackdir(a: array of byte): (int, Sys->Dir)
{
	dir: Sys->Dir;

	if(len a < STATFIXLEN)
		return (0, dir);
	# size[2]
	sz := ((int a[1] << 8) | int a[0])+LEN;	# bytes this packed dir should occupy
	if(len a < sz)
		return (0, dir);
	# type[2]
	dir.dtype = (int a[3]<<8) | int a[2];
	# dev[4]
	dir.dev = (((((int a[7] << 8) | int a[6]) << 8) | int a[5]) << 8) | int a[4];
	# qid.type[1]
	# qid.vers[4]
	# qid.path[8]
	dir.qid = gqid(a, 8);
	# mode[4]
	dir.mode = (((((int a[24] << 8) | int a[23]) << 8) | int a[22]) << 8) | int a[21];
	# atime[4]
	dir.atime = (((((int a[28] << 8) | int a[27]) << 8) | int a[26]) << 8) | int a[25];
	# mtime[4]
	dir.mtime = (((((int a[32] << 8) | int a[31]) << 8) | int a[30]) << 8) | int a[29];
	# length[8]
	v0 := (((((int a[36] << 8) | int a[35]) << 8) | int a[34]) << 8) | int a[33];
	v1 := (((((int a[40] << 8) | int a[39]) << 8) | int a[38]) << 8) | int a[37];
	dir.length = (big v1 << 32) | (big v0 & 16rFFFFFFFF);
	# name[s], uid[s], gid[s], muid[s]
	i: int;
	(dir.name, i) = gstring(a, 41);
	(dir.uid, i) = gstring(a, i);
	(dir.gid, i) = gstring(a, i);
	(dir.muid, i) = gstring(a, i);
	if(i != sz)
		return (0, dir);
	return (i, dir);
}

gqid(f: array of byte, i: int): Sys->Qid
{
	qtype := int f[i];
	vers := (((((int f[i+4] << 8) | int f[i+3]) << 8) | int f[i+2]) << 8) | int f[i+1];
	i += BIT8SZ+BIT32SZ;
	path0 := (((((int f[i+3] << 8) | int f[i+2]) << 8) | int f[i+1]) << 8) | int f[i];
	i += BIT32SZ;
	path1 := (((((int f[i+3] << 8) | int f[i+2]) << 8) | int f[i+1]) << 8) | int f[i];
	path := (big path1 << 32) | (big path0 & 16rFFFFFFFF);
	return (path, vers, qtype);
}

g32(f: array of byte, i: int): int
{
	return (((((int f[i+3] << 8) | int f[i+2]) << 8) | int f[i+1]) << 8) | int f[i];
}

g64(f: array of byte, i: int): big
{
	b0 := (((((int f[i+3] << 8) | int f[i+2]) << 8) | int f[i+1]) << 8) | int f[i];
	b1 := (((((int f[i+7] << 8) | int f[i+6]) << 8) | int f[i+5]) << 8) | int f[i+4];
	return (big b1 << 32) | (big b0 & 16rFFFFFFFF);
}

gstring(a: array of byte, o: int): (string, int)
{
	if(o < 0 || o+STR > len a)
		return (nil, -1);
	l := (int a[o+1] << 8) | int a[o];
	o += STR;
	e := o+l;
	if(e > len a)
		return (nil, -1);
	return (string a[o:e], e);
}

ttag2type := array[] of {
tagof Tmsg.Readerror => 0,
tagof Tmsg.Version => Tversion,
tagof Tmsg.Auth => Tauth,
tagof Tmsg.Attach => Tattach,
tagof Tmsg.Flush => Tflush,
tagof Tmsg.Walk => Twalk,
tagof Tmsg.Open => Topen,
tagof Tmsg.Create => Tcreate,
tagof Tmsg.Read => Tread,
tagof Tmsg.Write => Twrite,
tagof Tmsg.Clunk => Tclunk,
tagof Tmsg.Stat => Tstat,
tagof Tmsg.Remove => Tremove,
tagof Tmsg.Wstat => Twstat,
};

Tmsg.mtype(t: self ref Tmsg): int
{
	return ttag2type[tagof t];
}

Tmsg.packedsize(t: self ref Tmsg): int
{
	mtype := ttag2type[tagof t];
	if(mtype <= 0)
		return 0;
	ml := hdrlen[mtype];
	pick m := t {
	Version =>
		ml += utflen(m.version);
	Auth =>
		ml += utflen(m.uname)+utflen(m.aname);
	Attach =>
		ml += utflen(m.uname)+utflen(m.aname);
	Walk =>
		for(i:=0; i<len m.names; i++)
			ml += STR+utflen(m.names[i]);
	Create =>
		ml += utflen(m.name);
	Write =>
		ml += len m.data;
	Wstat =>
		ml += packdirsize(m.stat);
	}
	return ml;
}

Tmsg.pack(t: self ref Tmsg): array of byte
{
	if(t == nil)
		return nil;
	ds := t.packedsize();
	if(ds <= 0)
		return nil;
	d := array[ds] of byte;
	d[0] = byte ds;
	d[1] = byte (ds>>8);
	d[2] = byte (ds>>16);
	d[3] = byte (ds>>24);
	d[4] = byte ttag2type[tagof t];
	d[5] = byte t.tag;
	d[6] = byte (t.tag >> 8);
	pick m := t {
	Version =>
		p32(d, H, m.msize);
		pstring(d, H+COUNT, m.version);
	Auth =>
		p32(d, H, m.afid);
		o := pstring(d, H+FID, m.uname);
		pstring(d, o, m.aname);
	Flush =>
		v := m.oldtag;
		d[H] = byte v;
		d[H+1] = byte (v>>8);
	Attach =>
		p32(d, H, m.fid);
		p32(d, H+FID, m.afid);
		o := pstring(d, H+2*FID, m.uname);
		pstring(d, o, m.aname);
	Walk =>
		d[H] = byte m.fid;
		d[H+1] = byte (m.fid>>8);
		d[H+2] = byte (m.fid>>16);
		d[H+3] = byte (m.fid>>24);
		d[H+FID] = byte m.newfid;
		d[H+FID+1] = byte (m.newfid>>8);
		d[H+FID+2] = byte (m.newfid>>16);
		d[H+FID+3] = byte (m.newfid>>24);
		n := len m.names;
		d[H+2*FID] = byte n;
		d[H+2*FID+1] = byte (n>>8);
		o := H+2*FID+LEN;
		for(i := 0; i < n; i++)
			o = pstring(d, o, m.names[i]);
	Open =>
		p32(d, H, m.fid);
		d[H+FID] = byte m.mode;
	Create =>
		p32(d, H, m.fid);
		o := pstring(d, H+FID, m.name);
		p32(d, o, m.perm);
		d[o+BIT32SZ] = byte m.mode;
	Read =>
		p32(d, H, m.fid);
		p64(d, H+FID, m.offset);
		p32(d, H+FID+OFFSET, m.count);
	Write =>
		p32(d, H, m.fid);
		p64(d, H+FID, m.offset);
		n := len m.data;
		p32(d, H+FID+OFFSET, n);
		d[H+FID+OFFSET+COUNT:] = m.data;
	Clunk or Remove or Stat =>
		p32(d, H, m.fid);
	Wstat =>
		p32(d, H, m.fid);
		stat := packdir(m.stat);
		n := len stat;
		d[H+FID] = byte n;
		d[H+FID+1] = byte (n>>8);
		d[H+FID+LEN:] = stat;
	* =>
		raise sys->sprint("assertion: Ninep->Tmsg.pack: bad tag: %d", tagof t);
	}
	return d;
}

Tmsg.unpack(f: array of byte): (int, ref Tmsg)
{
	if(len f < H)
		return (0, nil);
	size := (int f[1] << 8) | int f[0];
	size |= ((int f[3] << 8) | int f[2]) << 16;
	if(len f != size){
		if(len f < size)
			return (0, nil);	# need more data
		f = f[0:size];	# trim to exact length
	}
	mtype := int f[4];
	if(mtype >= len hdrlen || (mtype&1) != 0 || size < hdrlen[mtype])
		return (-1, nil);

	tag := (int f[6] << 8) | int f[5];
	fid := 0;
	if(hdrlen[mtype] >= H+FID)
		fid = g32(f, H);	# fid is always in same place: extract it once for all if there

	# return out of each case body for a legal message;
	# break out of the case for an illegal one

Decode:
	case mtype {
	* =>
		sys->print("styx: Tmsg.unpack: bad type %d\n", mtype);
	Tversion =>
		msize := fid;
		(version, o) := gstring(f, H+COUNT);
		if(o <= 0)
			break;
		return (o, ref Tmsg.Version(tag, msize, version));
	Tauth =>
		(uname, o1) := gstring(f, H+FID);
		(aname, o2) := gstring(f, o1);
		if(o2 <= 0)
			break;
		return (o2, ref Tmsg.Auth(tag, fid, uname, aname));
	Tflush =>
		oldtag := (int f[H+1] << 8) | int f[H];
		return (H+TAG, ref Tmsg.Flush(tag, oldtag));
	Tattach =>
		afid := g32(f, H+FID);
		(uname, o1) := gstring(f, H+2*FID);
		(aname, o2) := gstring(f, o1);
		if(o2 <= 0)
			break;
		return (o2, ref Tmsg.Attach(tag, fid, afid, uname, aname));
	Twalk =>
		newfid := g32(f, H+FID);
		n := (int f[H+2*FID+1] << 8) | int f[H+2*FID];
		if(n > MAXWELEM)
			break;
		o := H+2*FID+LEN;
		names: array of string = nil;
		if(n > 0){
			names = array[n] of string;
			for(i:=0; i<n; i++){
				(names[i], o) = gstring(f, o);
				if(o <= 0)
					break Decode;
			}
		}
		return (o, ref Tmsg.Walk(tag, fid, newfid, names));
	Topen =>
		return (H+FID+BIT8SZ, ref Tmsg.Open(tag, fid, int f[H+FID]));
	Tcreate =>
		(name, o) := gstring(f, H+FID);
		if(o <= 0 || o+BIT32SZ+BIT8SZ > len f)
			break;
		perm := g32(f, o);
		o += BIT32SZ;
		mode := int f[o++];
		return (o, ref Tmsg.Create(tag, fid, name, perm, mode));
	Tread =>
		offset := g64(f, H+FID);
		count := g32(f, H+FID+OFFSET);
		return (H+FID+OFFSET+COUNT, ref Tmsg.Read(tag, fid, offset, count));
	Twrite =>
		offset := g64(f, H+FID);
		count := g32(f, H+FID+OFFSET);
		O: con H+FID+OFFSET+COUNT;
		if(count > len f-O)
			break;
		data := f[O:O+count];
		return (O+count, ref Tmsg.Write(tag, fid, offset, data));
	Tclunk =>
		return (H+FID, ref Tmsg.Clunk(tag, fid));
	Tremove =>
		return (H+FID, ref Tmsg.Remove(tag, fid));
	Tstat =>
		return (H+FID, ref Tmsg.Stat(tag, fid));
	Twstat =>
		n := int (f[H+FID+1]<<8) | int f[H+FID];
		if(len f < H+FID+LEN+n)
			break;
		(ds, stat) := unpackdir(f[H+FID+LEN:]);
		if(ds != n){
			sys->print("Ninep->Tmsg.unpack: wstat count: %d/%d\n", ds, n);	# temporary
			break;
		}
		return (H+FID+LEN+n, ref Tmsg.Wstat(tag, fid, stat));
	}
	return (-1, nil);		# illegal
}

tmsgname := array[] of {
tagof Tmsg.Readerror => "Readerror",
tagof Tmsg.Version => "Version",
tagof Tmsg.Auth => "Auth",
tagof Tmsg.Attach => "Attach",
tagof Tmsg.Flush => "Flush",
tagof Tmsg.Walk => "Walk",
tagof Tmsg.Open => "Open",
tagof Tmsg.Create => "Create",
tagof Tmsg.Read => "Read",
tagof Tmsg.Write => "Write",
tagof Tmsg.Clunk => "Clunk",
tagof Tmsg.Stat => "Stat",
tagof Tmsg.Remove => "Remove",
tagof Tmsg.Wstat => "Wstat",
};

Tmsg.text(t: self ref Tmsg): string
{
	if(t == nil)
		return "nil";
	s := sys->sprint("Tmsg.%s(%ud", tmsgname[tagof t], t.tag);
	pick m:= t {
	* =>
		return s + ",ILLEGAL)";
	Readerror =>
		return s + sys->sprint(",\"%s\")", m.error);
	Version =>
		return s + sys->sprint(",%d,\"%s\")", m.msize, m.version);
	Auth =>
		return s + sys->sprint(",%ud,\"%s\",\"%s\")", m.afid, m.uname, m.aname);
	Flush =>
		return s + sys->sprint(",%ud)", m.oldtag);
	Attach =>
		return s + sys->sprint(",%ud,%ud,\"%s\",\"%s\")", m.fid, m.afid, m.uname, m.aname);
	Walk =>
		s += sys->sprint(",%ud,%ud", m.fid, m.newfid);
		if(len m.names != 0){
			s += ",array[] of {";
			for(i := 0; i < len m.names; i++){
				c := ",";
				if(i == 0)
					c = "";
				s += sys->sprint("%s\"%s\"", c, m.names[i]);
			}
			s += "}";
		}else
			s += ",nil";
		return s + ")";
	Open =>
		return s + sys->sprint(",%ud,%d)", m.fid, m.mode);
	Create =>
		return s + sys->sprint(",%ud,\"%s\",8r%uo,%d)", m.fid, m.name, m.perm, m.mode);
	Read =>
		return s + sys->sprint(",%ud,%bd,%ud)", m.fid, m.offset, m.count);
	Write =>
		return s + sys->sprint(",%ud,%bd,array[%d] of byte)", m.fid, m.offset, len m.data);
	Clunk or
	Remove or
	Stat =>
		return s + sys->sprint(",%ud)", m.fid);
	Wstat =>
		return s + sys->sprint(",%ud,%s)", m.fid, dir2text(m.stat));
	}
}

Tmsg.read(fd: ref Sys->FD, msglim: int): ref Tmsg
{
	(msg, err) := readmsg(fd, msglim);
	if(err != nil)
		return ref Tmsg.Readerror(0, err);
	if(msg == nil)
		return nil;
	(nil, m) := Tmsg.unpack(msg);
	if(m == nil)
		return ref Tmsg.Readerror(0, "bad 9P T-message format");
	return m;
}

rtag2type := array[] of {
tagof Rmsg.Version	=> Rversion,
tagof Rmsg.Auth	=> Rauth,
tagof Rmsg.Error	=> Rerror,
tagof Rmsg.Flush	=> Rflush,
tagof Rmsg.Attach	=> Rattach,
tagof Rmsg.Walk	=> Rwalk,
tagof Rmsg.Open	=> Ropen,
tagof Rmsg.Create	=> Rcreate,
tagof Rmsg.Read	=> Rread,
tagof Rmsg.Write	=> Rwrite,
tagof Rmsg.Clunk	=> Rclunk,
tagof Rmsg.Remove	=> Rremove,
tagof Rmsg.Stat	=> Rstat,
tagof Rmsg.Wstat	=> Rwstat,
};

Rmsg.mtype(r: self ref Rmsg): int
{
	return rtag2type[tagof r];
}

Rmsg.packedsize(r: self ref Rmsg): int
{
	mtype := rtag2type[tagof r];
	if(mtype <= 0)
		return 0;
	ml := hdrlen[mtype];
	pick m := r {
	Version =>
		ml += utflen(m.version);
	Error =>
		ml += utflen(m.ename);
	Walk =>
		ml += QID*len m.qids;
	Read =>
		ml += len m.data;
	Stat =>
		ml += packdirsize(m.stat);
	}
	return ml;
}

Rmsg.pack(r: self ref Rmsg): array of byte
{
	if(r == nil)
		return nil;
	ps := r.packedsize();
	if(ps <= 0)
		return nil;
	d := array[ps] of byte;
	d[0] = byte ps;
	d[1] = byte (ps>>8);
	d[2] = byte (ps>>16);
	d[3] = byte (ps>>24);
	d[4] = byte rtag2type[tagof r];
	d[5] = byte r.tag;
	d[6] = byte (r.tag >> 8);
	pick m := r {
	Version =>
		p32(d, H, m.msize);
		pstring(d, H+BIT32SZ, m.version);
	Auth =>
		pqid(d, H, m.aqid);
	Flush or
	Clunk or
	Remove or
	Wstat =>
		;	# nothing more required
	Error	=>
		pstring(d, H, m.ename);
	Attach =>
		pqid(d, H, m.qid);
	Walk =>
		n := len m.qids;
		d[H] = byte n;
		d[H+1] = byte (n>>8);
		o := H+LEN;
		for(i:=0; i<n; i++){
			pqid(d, o, m.qids[i]);
			o += QID;
		}
	Create or
	Open =>
		pqid(d, H, m.qid);
		p32(d, H+QID, m.iounit);
	Read =>
		v := len m.data;
		d[H] = byte v;
		d[H+1] = byte (v>>8);
		d[H+2] = byte (v>>16);
		d[H+3] = byte (v>>24);
		d[H+4:] = m.data;
	Write =>
		v := m.count;
		d[H] = byte v;
		d[H+1] = byte (v>>8);
		d[H+2] = byte (v>>16);
		d[H+3] = byte (v>>24);
	Stat =>
		stat := packdir(m.stat);
		v := len stat;
		d[H] = byte v;
		d[H+1] = byte (v>>8);
		d[H+2:] = stat;		# should avoid copy?
	* =>
		raise sys->sprint("assertion: Ninep->Rmsg.pack: missed case: tag %d", tagof r);
	}
	return d;
}

Rmsg.unpack(f: array of byte): (int, ref Rmsg)
{
	if(len f < H)
		return (0, nil);
	size := (int f[1] << 8) | int f[0];
	size |= ((int f[3] << 8) | int f[2]) << 16;	# size includes itself
	if(len f != size){
		if(len f < size)
			return (0, nil);	# need more data
		f = f[0:size];	# trim to exact length
	}
	mtype := int f[4];
	if(mtype >= len hdrlen || (mtype&1) == 0 || size < hdrlen[mtype])
		return (-1, nil);

	tag := (int f[6] << 8) | int f[5];

	# return out of each case body for a legal message;
	# break out of the case for an illegal one

	case mtype {
	* =>
		sys->print("Ninep->Rmsg.unpack: bad type %d\n", mtype);	# temporary
	Rversion =>
		msize := g32(f, H);
		(version, o) := gstring(f, H+BIT32SZ);
		if(o <= 0)
			break;
		return (o, ref Rmsg.Version(tag, msize, version));
	Rauth =>
		return (H+QID, ref Rmsg.Auth(tag, gqid(f, H)));
	Rflush =>
		return (H, ref Rmsg.Flush(tag));
	Rerror =>
		(ename, o) := gstring(f, H);
		if(o <= 0)
			break;
		return (o, ref Rmsg.Error(tag, ename));
	Rclunk =>
		return (H, ref Rmsg.Clunk(tag));
	Rremove =>
		return (H, ref Rmsg.Remove(tag));
	Rwstat=>
		return (H, ref Rmsg.Wstat(tag));
	Rattach =>
		return (H+QID, ref Rmsg.Attach(tag, gqid(f, H)));
	Rwalk =>
		nqid := (int f[H+1] << 8) | int f[H];
		if(len f < H+LEN+nqid*QID)
			break;
		o := H+LEN;
		qids := array[nqid] of Sys->Qid;
		for(i:=0; i<nqid; i++){
			qids[i] = gqid(f, o);
			o += QID;
		}
		return (o, ref Rmsg.Walk(tag, qids));
	Ropen =>
		return (H+QID+COUNT, ref Rmsg.Open(tag, gqid(f, H), g32(f, H+QID)));
	Rcreate=>
		return (H+QID+COUNT, ref Rmsg.Create(tag, gqid(f, H), g32(f, H+QID)));
	Rread =>
		count := g32(f, H);
		if(len f < H+COUNT+count)
			break;
		data := f[H+COUNT:H+COUNT+count];
		return (H+COUNT+count, ref Rmsg.Read(tag, data));
	Rwrite =>
		return (H+COUNT, ref Rmsg.Write(tag, g32(f, H)));
	Rstat =>
		n := (int f[H+1] << 8) | int f[H];
		if(len f < H+LEN+n)
			break;
		(ds, d) := unpackdir(f[H+LEN:]);
		if(ds <= 0)
			break;
		if(ds != n){
			sys->print("Ninep->Rmsg.unpack: stat count: %d/%d\n", ds, n);		# temporary
			break;
		}
		return (H+LEN+n, ref Rmsg.Stat(tag, d));
	}
	return (-1, nil);		# illegal
}

rmsgname := array[] of {
tagof Rmsg.Version => "Version",
tagof Rmsg.Auth => "Auth",
tagof Rmsg.Attach => "Attach",
tagof Rmsg.Error => "Error",
tagof Rmsg.Flush => "Flush",
tagof Rmsg.Walk => "Walk",
tagof Rmsg.Create => "Create",
tagof Rmsg.Open => "Open",
tagof Rmsg.Read => "Read",
tagof Rmsg.Write => "Write",
tagof Rmsg.Clunk => "Clunk",
tagof Rmsg.Remove => "Remove",
tagof Rmsg.Stat => "Stat",
tagof Rmsg.Wstat => "Wstat",
};

Rmsg.text(r: self ref Rmsg): string
{
	if(sys == nil)
		sys = load Sys Sys->PATH;
	if(r == nil)
		return "nil";
	s := sys->sprint("Rmsg.%s(%ud", rmsgname[tagof r], r.tag);
	pick m := r {
	* =>
		return s + "ERROR)";
	Readerror =>
		return s + sys->sprint(",\"%s\")", m.error);
	Version =>
		return s + sys->sprint(",%d,\"%s\")", m.msize, m.version);
	Auth =>
		return s+sys->sprint(",%s)", qid2text(m.aqid));
	Error =>
		return s+sys->sprint(",\"%s\")", m.ename);
	Flush or
	Clunk or
	Remove or
	Wstat =>
		return s+")";
	Attach =>
		return s+sys->sprint(",%s)", qid2text(m.qid));
	Walk	 =>
		s += ",array[] of {";
		for(i := 0; i < len m.qids; i++){
			c := "";
			if(i != 0)
				c = ",";
			s += sys->sprint("%s%s", c, qid2text(m.qids[i]));
		}
		return s+"})";
	Create or
	Open =>
		return s+sys->sprint(",%s,%d)", qid2text(m.qid), m.iounit);
	Read =>
		return s+sys->sprint(",array[%d] of byte)", len m.data);
	Write =>
		return s+sys->sprint(",%d)", m.count);
	Stat =>
		return s+sys->sprint(",%s)", dir2text(m.stat));
	}
}

Rmsg.read(fd: ref Sys->FD, msglim: int): ref Rmsg
{
	(msg, err) := readmsg(fd, msglim);
	if(err != nil)
		return ref Rmsg.Readerror(0, err);
	if(msg == nil)
		return nil;
	(nil, m) := Rmsg.unpack(msg);
	if(m == nil)
		return ref Rmsg.Readerror(0, "bad 9P R-message format");
	return m;
}

Rmsg.write(m: self ref Rmsg, fd: ref Sys->FD, msize: int): int
{
	if(msize == 0)
		m = ref Rmsg.Error(m.tag, "Tversion not seen");
	d := m.pack();
	if(msize != 0 && len d > msize){
		m = ref Rmsg.Error(m.tag, "9P reply didn't fit");
		d = m.pack();
	}
	n := len d;
	if(sys->write(fd, d, n) != n)
		return -1;
	return 0;
}

dir2text(d: Sys->Dir): string
{
	return sys->sprint("Dir(\"%s\",\"%s\",\"%s\",%s,8r%uo,%d,%d,%bd,16r%ux,%d)",
		d.name, d.uid, d.gid, qid2text(d.qid), d.mode, d.atime, d.mtime, d.length, d.dtype, d.dev);
}

qid2text(q: Sys->Qid): string
{
	return sys->sprint("Qid(16r%ubx,%d,16r%.2ux)", q.path, q.vers, q.qtype);
}

readmsg(fd: ref Sys->FD, msglim: int): (array of byte, string)
{
	if(msglim <= 0)
		msglim = DEFMSIZE;
	sbuf := array[BIT32SZ] of byte;
	if((n := sys->readn(fd, sbuf, BIT32SZ)) != BIT32SZ){
		if(n == 0)
			return (nil, nil);
		return (nil, sys->sprint("%r"));
	}
	ml := (int sbuf[1] << 8) | int sbuf[0];
	ml |= ((int sbuf[3] << 8) | int sbuf[2]) << 16;
	if(ml <= BIT32SZ)
		return (nil, "invalid 9P message size");
	if(ml > msglim)
		return (nil, "9P message longer than agreed");
	buf := array[ml] of byte;
	buf[0:] = sbuf;
	if((n = sys->readn(fd, buf[BIT32SZ:], ml-BIT32SZ)) != ml-BIT32SZ){
		if(n == 0)
			return (nil, "9P message truncated");
		return (nil, sys->sprint("%r"));
	}
	return (buf, nil);
}

istmsg(f: array of byte): int
{
	if(len f < H)
		return -1;
	return (int f[BIT32SZ] & 1) == 0;
}

compatible(t: ref Tmsg.Version, msize: int, version: string): (int, string)
{
	if(version == nil)
		version = VERSION;
	if(t.msize < msize)
		msize = t.msize;
	v := t.version;
	if(len v < 2 || v[0:2] != "9P")
		return (msize, "unknown");
	for(i:=2; i<len v; i++)
		if((c := v[i]) == '.'){
			v = v[0:i];
			break;
		}else if(!(c >= '0' && c <= '9'))
			return (msize, "unknown");	# fussier than Plan 9
	if(v < VERSION)
		return (msize, "unknown");
	if(v < version)
		version = v;
	return (msize, version);
}
