implement Vac;

include "sys.m";
include "venti.m";
include "vac.m";

sys: Sys;
venti: Venti;

werrstr, sprint, fprint, fildes: import sys;
Roottype, Dirtype, Pointertype0, Datatype: import venti;
Score, Session, Scoresize: import venti;

dflag = 0;

# from venti.b
BIT8SZ:	con 1;
BIT16SZ:        con 2;
BIT32SZ:        con 4;
BIT48SZ:        con 6;
BIT64SZ:	con 8;

Rootnamelen:	con 128;
Rootversion:	con 2;
Direntrymagic:	con 16r1c4d9072;
Metablockmagic:	con 16r5656fc79;
Maxstringsize: con 1000;

blankroot: Root;
blankentry: Entry;
blankdirentry: Direntry;
blankmetablock: Metablock;
blankmetaentry: Metaentry;


init()
{
	sys = load Sys Sys->PATH;
	venti = load Venti Venti->PATH;
	venti->init();
}

pstring(a: array of byte, o: int, s: string): int
{
	sa := array of byte s;	# could do conversion ourselves
	n := len sa;
	a[o] = byte (n >> 8);
	a[o+1] = byte n;
	a[o+2:] = sa;
	return o+BIT16SZ+n;
}

gstring(a: array of byte, o: int): (string, int)
{
	if(o < 0 || o+BIT16SZ > len a)
		return (nil, -1);
	l := (int a[o] << 8) | int a[o+1];
	if(l > Maxstringsize)
		return (nil, -1);
	o += BIT16SZ;
	e := o+l;
	if(e > len a)
		return (nil, -1);
	return (string a[o:e], e);
}

gtstring(a: array of byte, o: int, n: int): string
{
	e := o + n;
	if(e > len a)
		return nil;
	for(i := o; i < e; i++)
		if(a[i] == byte 0)
			break;
	return string a[o:i];
}


Root.new(name, rtype: string, score: Score, blocksize: int, prev: ref Score): ref Root
{
	return ref Root(Rootversion, name, rtype, score, blocksize, prev);
}

Root.pack(r: self ref Root): array of byte
{
	d := array[Rootsize] of byte;
	i := 0;
	i = p16(d, i, r.version);
	i = ptstring(d, i, r.name, Rootnamelen);
	if(i < 0)
		return nil;
	i = ptstring(d, i, r.rtype, Rootnamelen);
	if(i < 0)
		return nil;
	i = pscore(d, i, r.score);
	i = p16(d, i, r.blocksize);
	if(r.prev == nil) {
		for(j := 0; j < Scoresize; j++)
			d[i+j] = byte 0;
		i += Scoresize;
	} else 
		i = pscore(d, i, *r.prev);
	if(i != len d) {
		sys->werrstr("root pack, bad length: "+string i);
		return nil;
	}
	return d;
}

Root.unpack(d: array of byte): ref Root
{
	if(len d != Rootsize){
		sys->werrstr("root entry is wrong length");
		return nil;
	}
	r := ref blankroot;
	r.version = g16(d, 0);
	if(r.version != Rootversion){
		sys->werrstr("unknown root version");
		return nil;
	}
	o := BIT16SZ;
	r.name = gtstring(d, o, Rootnamelen);
	o += Rootnamelen;
	r.rtype = gtstring(d, o, Rootnamelen);
	o += Rootnamelen;
	r.score = gscore(d, o);
	o += Scoresize;
	r.blocksize = g16(d, o);
	o += BIT16SZ;
	r.prev = ref gscore(d, o);
	return r;
}

Entry.new(psize, dsize, flags: int, size: big, score: Venti->Score): ref Entry
{
	return ref Entry(0, psize, dsize, (flags&Entrydepthmask)>>Entrydepthshift, flags, size, score);
}

Entry.pack(e: self ref Entry): array of byte
{
	d := array[Entrysize] of byte;
	i := 0;
	i = p32(d, i, e.gen);
	i = p16(d, i, e.psize);
	i = p16(d, i, e.dsize);
	e.flags |= e.depth<<Entrydepthshift;
	d[i++] = byte e.flags;
	for(j := 0; j < 5; j++)
		d[i++] = byte 0;
	i = p48(d, i, e.size);
	i = pscore(d, i, e.score);
	if(i != len d) {
		werrstr(sprint("bad length, have %d, want %d", i, len d));
		return nil;
	}
	return d;
}

Entry.unpack(d: array of byte): ref Entry
{
	if(len d != Entrysize){
		sys->werrstr("entry is wrong length");
		return nil;
	}
	e := ref blankentry;
	i := 0;
	e.gen = g32(d, i);
	i += BIT32SZ;
	e.psize = g16(d, i);
	i += BIT16SZ;
	e.dsize = g16(d, i);
	i += BIT16SZ;
	e.flags = int d[i];
	e.depth = (e.flags & Entrydepthmask) >> Entrydepthshift;
	e.flags &= ~Entrydepthmask;
	i += BIT8SZ;
	i += 5;			# skip something...
	e.size = g48(d, i);
	i += BIT48SZ;
	e.score = gscore(d, i);
	i += Scoresize;
	if((e.flags & Entryactive) == 0)
		return e;
	if(!checksize(e.psize) || !checksize(e.dsize)){
		sys->werrstr(sys->sprint("bad blocksize (%d or %d)", e.psize, e.dsize));
		return nil;
	}
	return e;
}

Direntry.new(): ref Direntry
{
	return ref Direntry(9, "", 0, 0, 0, 0, big 0, "", "", "", 0, 0, 0, 0, 0, 0);
}

Direntry.mk(d: Sys->Dir): ref Direntry
{
	atime := 0; # d.atime;
	mode := d.mode&Modeperm;
	if(d.mode&sys->DMAPPEND)
		mode |= Modeappend;
	if(d.mode&sys->DMEXCL)
		mode |= Modeexcl;
	if(d.mode&sys->DMDIR)
		mode |= Modedir;
	if(d.mode&sys->DMTMP)
		mode |= Modetemp;
	return ref Direntry(9, d.name, 0, 0, 0, 0, d.qid.path, d.uid, d.gid, d.muid, d.mtime, 0, 0, atime, mode, d.mode);
}

Direntry.mkdir(de: self ref Direntry): ref Sys->Dir
{
        d := ref sys->nulldir;
        d.name = de.elem;
        d.uid = de.uid;
        d.gid = de.gid;
        d.muid = de.mid;
        d.qid.path = de.qid;
        d.qid.vers = 0;
        d.qid.qtype = de.emode>>24;
        d.mode = de.emode;
        d.atime = de.atime;
        d.mtime = de.mtime;
        d.length = big 0;
        return d;
}

strlen(s: string): int
{
	return 2+len array of byte s;
}

Direntry.pack(de: self ref Direntry): array of byte
{
	# assume version 9
	length := 4+2+strlen(de.elem)+4+4+4+4+8+strlen(de.uid)+strlen(de.gid)+strlen(de.mid)+4+4+4+4+4; # + qidspace?

	d := array[length] of byte;
	i := 0;
	i = p32(d, i, Direntrymagic);
	i = p16(d, i, de.version);
	i = pstring(d, i, de.elem);
	i = p32(d, i, de.entry);
	if(de.version == 9) {
		i = p32(d, i, de.gen);
		i = p32(d, i, de.mentry);
		i = p32(d, i, de.mgen);
	}
	i = p64(d, i, de.qid);
	i = pstring(d, i, de.uid);
	i = pstring(d, i, de.gid);
	i = pstring(d, i, de.mid);
	i = p32(d, i, de.mtime);
	i = p32(d, i, de.mcount);
	i = p32(d, i, de.ctime);
	i = p32(d, i, de.atime);
	i = p32(d, i, de.mode);
	if(i != len d) {
		werrstr(sprint("bad length for direntry (expected %d, have %d)", len d, i));
		return nil;
	}
	return d;
}

Direntry.unpack(d: array of byte): ref Direntry
{
	{
		de := ref blankdirentry;
		i := 0;
		magic: int;
		(magic, i) = eg32(d, i);
		if(magic != Direntrymagic) {
			werrstr(sprint("bad magic (%x, want %x)", magic, Direntrymagic));
			return nil;
		}
		(de.version, i) = eg16(d, i);
		if(de.version != 8 && de.version != 9) {
			werrstr(sprint("bad version (%d)", de.version));
			return nil;
		}
		(de.elem, i) = egstring(d, i);
		(de.entry, i) = eg32(d, i);
		case de.version {
		8 =>
			de.gen = 0;
			de.mentry = de.entry+1;
			de.mgen = 0;
		9 =>
			(de.gen, i) = eg32(d, i);
			(de.mentry, i) = eg32(d, i);
			(de.mgen, i) = eg32(d, i);
		}
		(de.qid, i) = eg64(d, i);
		(de.uid, i) = egstring(d, i);
		(de.gid, i) = egstring(d, i);
		(de.mid, i) = egstring(d, i);
		(de.mtime, i) = eg32(d, i);
		(de.mcount, i) = eg32(d, i);
		(de.ctime, i) = eg32(d, i);
		(de.atime, i) = eg32(d, i);
		(de.mode, i) = eg32(d, i);
		de.emode = de.mode&Modeperm;
		if(de.mode&Modeappend)
			de.emode |= sys->DMAPPEND;
		if(de.mode&Modeexcl)
			de.emode |= sys->DMEXCL;
		if(de.mode&Modedir)
			de.emode |= sys->DMDIR;
		if(de.mode&Modetemp)
			de.emode |= sys->DMTMP;
		if(de.version == 9)
			; # xxx handle qid space?, can be in here
		return de;
	} exception e {
	"too small:*" =>
		werrstr("direntry "+e);
		return nil;
	* =>
		raise e;
	}
}


Metablock.new(): ref Metablock
{
	return ref Metablock(0, 0, 0, 0);
}

Metablock.pack(mb: self ref Metablock, d: array of byte)
{
	i := 0;
	i = p32(d, i, Metablockmagic);
	i = p16(d, i, mb.size);
	i = p16(d, i, mb.free);
	i = p16(d, i, mb.maxindex);
	i = p16(d, i, mb.nindex);
}

Metablock.unpack(d: array of byte): ref Metablock
{
	if(len d < Metablocksize) {
		werrstr(sprint("bad length for metablock (%d, want %d)", len d, Metablocksize));
		return nil;
	}
	i := 0;
	magic := g32(d, i);
	if(magic != Metablockmagic && magic != Metablockmagic+1) {
		werrstr(sprint("bad magic for metablock (%x, need %x)", magic, Metablockmagic));
		return nil;
	}
	i += BIT32SZ;

	mb := ref blankmetablock;
	mb.size = g16(d, i);
	i += BIT16SZ;
	mb.free = g16(d, i);
	i += BIT16SZ;
	mb.maxindex = g16(d, i);
	i += BIT16SZ;
	mb.nindex = g16(d, i);
	i += BIT16SZ;
	if(mb.nindex == 0) {
		werrstr("bad metablock, nindex=0");
		return nil;
	}
	return mb;
}

Metaentry.pack(me: self ref Metaentry, d: array of byte)
{
	i := 0;
	i = p16(d, i, me.offset);
	i = p16(d, i, me.size);
}

Metaentry.unpack(d: array of byte, i: int): ref Metaentry
{
	o := Metablocksize+i*Metaentrysize;
	if(o+Metaentrysize > len d) {
		werrstr(sprint("meta entry lies outside meta block, i=%d", i));
		return nil;
	}

	me := ref blankmetaentry;
	me.offset = g16(d, o);
	o += BIT16SZ;
	me.size = g16(d, o);
	o += BIT16SZ;
	if(me.offset+me.size > len d) {
		werrstr(sprint("meta entry points outside meta block, i=%d", i));
		return nil;
	}
	return me;
}


Page.new(dsize: int): ref Page
{
	psize := (dsize/Scoresize)*Scoresize;
	return ref Page(array[psize] of byte, 0);
}

Page.add(p: self ref Page, s: Score)
{
	for(i := 0; i < Scoresize; i++)
		p.d[p.o+i] = s.a[i];
	p.o += Scoresize;
}

Page.full(p: self ref Page): int
{
	return p.o+Scoresize > len p.d;
}

Page.data(p: self ref Page): array of byte
{
	for(i := p.o; i >= Scoresize; i -= Scoresize)
		if(!Score(p.d[i-Scoresize:i]).eq(Score.zero()))
			break;
	return p.d[:i];
}


File.new(s: ref Session, dtype, dsize: int): ref File
{
	p := array[1] of ref Page;
	p[0] = Page.new(dsize);
	return ref File(p, dtype, dsize, big 0, s);
}

fflush(f: ref File, last: int): (int, ref Entry)
{
	for(i := 0; i < len f.p; i++) {
		if(!last && !f.p[i].full())
			return (0, nil);
		if(last && f.p[i].o == Scoresize) {
			flags := Entryactive;
			if(f.dtype == Dirtype)
				flags |= Entrydir;
			flags |= i<<Entrydepthshift;
			score := Score(f.p[i].data());
			if(len score.a == 0)
				score = Score.zero();
			return (0, Entry.new(len f.p[i].d, f.dsize, flags, f.size, score));
		}
		(ok, score) := f.s.write(Pointertype0+i, f.p[i].data());
		if(ok < 0)
			return (-1, nil);
		f.p[i] = Page.new(f.dsize);
		if(i+1 == len f.p) {
			newp := array[len f.p+1] of ref Page;
			newp[:] = f.p;
			newp[len newp-1] = Page.new(f.dsize);
			f.p = newp;
		}
		f.p[i+1].add(score);
	}
	werrstr("internal error in fflush");
	return (-1, nil);
}

File.write(f: self ref File, d: array of byte): int
{
	(fok, nil) := fflush(f, 0);
	if(fok < 0)
		return -1;
	length := len d;
	for(i := len d; i > 0; i--)
		if(d[i-1] != byte 0)
			break;
	d = d[:i];
	(ok, score) := f.s.write(f.dtype, d);
	if(ok < 0)
		return -1;
	f.size += big length;
	f.p[0].add(score);
	return 0;
}

File.finish(f: self ref File): ref Entry
{
	(ok, e) := fflush(f, 1);
	if(ok < 0)
		return nil;
	return e;
}


Sink.new(s: ref Venti->Session, dsize: int): ref Sink
{
	dirdsize := (dsize/Entrysize)*Entrysize;
	return ref Sink(File.new(s, Dirtype, dsize), array[dirdsize] of byte, 0, 0);
}

Sink.add(m: self ref Sink, e: ref Entry): int
{
	ed := e.pack();
	if(ed == nil)
		return -1;
	n := len m.d - m.nd;
	if(n > len ed)
		n = len ed;
	m.d[m.nd:] = ed[:n];
	m.nd += n;
	if(n < len ed) {
		if(m.f.write(m.d) < 0)
			return -1;
		m.nd = len ed - n;
		m.d[:] = ed[n:];
	}
	return m.ne++;
}

Sink.finish(m: self ref Sink): ref Entry
{
	if(m.nd > 0)
		if(m.f.write(m.d[:m.nd]) < 0)
			return nil;
	e := m.f.finish();
	e.dsize = len m.d;
	return e;
}


elemcmp(a, b: array of byte, fossil: int): int
{
	for(i := 0; i < len a && i < len b; i++)
		if(a[i] != b[i])
			return (int a[i] - int b[i]);
	if(fossil)
		return len a - len b;
	return len b - len a;
}

Mentry.cmp(a, b: ref Mentry): int
{
	return elemcmp(array of byte a.elem, array of byte b.elem, 0);
}

MSink.new(s: ref Venti->Session, dsize: int): ref MSink
{
	return ref MSink(File.new(s, Datatype, dsize), array[dsize] of byte, 0, nil);
}

l2a[T](l: list of T): array of T
{
	a := array[len l] of T;
	i := 0;
	for(; l != nil; l = tl l)
		a[i++] = hd l;
	return a;
}

insertsort[T](a: array of T)
	for { T =>	cmp:	fn(a, b: T): int; }
{
	for(i := 1; i < len a; i++) {
		tmp := a[i];
		for(j := i; j > 0 && T.cmp(a[j-1], tmp) > 0; j--)
			a[j] = a[j-1];
		a[j] = tmp;
	}
}

mflush(m: ref MSink, last: int): int
{
	d := array[len m.de] of byte;

	me := l2a(m.l);
	insertsort(me);
	o := Metablocksize;
	deo := o+len m.l*Metaentrysize;
	for(i := 0; i < len me; i++) {
		me[i].me.offset += deo;
		me[i].me.pack(d[o:]);
		o += Metaentrysize;
	}
	d[o:] = m.de[:m.nde];
	o += m.nde;
	if(!last)
		while(o < len d)
			d[o++] = byte 0;

	mb := Metablock.new();
	mb.nindex = len m.l;
	mb.maxindex = mb.nindex;
	mb.free = 0;
	mb.size = o;
	mb.pack(d);

	if(m.f.write(d[:o]) < 0)
		return -1;
	m.nde = 0;
	m.l = nil;
	return 0;
}

MSink.add(m: self ref MSink, de: ref Direntry): int
{
	d := de.pack();
	if(d == nil)
		return -1;
say(sprint("msink: adding direntry, length %d", len d));
	if(Metablocksize+len m.l*Metaentrysize+m.nde + Metaentrysize+len d > len m.de)
		if(mflush(m, 0) < 0)
			return -1;
	m.de[m.nde:] = d;
	m.l = ref Mentry(de.elem, ref Metaentry(m.nde, len d))::m.l;
	m.nde += len d;
	return 0;
}

MSink.finish(m: self ref MSink): ref Entry
{
	if(m.nde > 0)
		mflush(m, 1);
	return m.f.finish();
}

Source.new(s: ref Session, e: ref Entry): ref Source
{
	dsize := e.dsize;
	if(e.flags&Entrydir)
		dsize = Entrysize*(dsize/Entrysize);
	return ref Source(s, e, dsize);
}

power(b, e: int): big
{
	r := big 1;
	while(e-- > 0)
		r *= big b;
	return r;
}

blocksize(e: ref Entry): int
{
	if(e.psize > e.dsize)
		return e.psize;
	return e.dsize;
}

Source.get(s: self ref Source, i: big, d: array of byte): int
{
	npages := (s.e.size+big (s.dsize-1))/big s.dsize;
	if(i*big s.dsize >= s.e.size)
		return 0;

	want := s.dsize;
	if(i == npages-big 1)
		want = int (s.e.size - i*big s.dsize);
	last := s.e.score;
	bsize := blocksize(s.e);
	buf: array of byte;

	npp := s.e.psize/Scoresize;	# scores per pointer block
	np := power(npp, s.e.depth-1);	# blocks referenced by score at this depth
	for(depth := s.e.depth; depth >= 0; depth--) {
		dtype := Pointertype0+depth-1;
		if(depth == 0) {
			dtype = Datatype;
			if(s.e.flags & Entrydir)
				dtype = Dirtype;
			bsize = want;
		}
		buf = s.session.read(last, dtype, bsize);
		if(buf == nil)
			return -1;
		if(depth > 0) {
			pi := int (i / np);
			i %= np;
			np /= big npp;
			o := (pi+1)*Scoresize;
			if(o <= len buf)
				last = Score(buf[o-Scoresize:o]);
			else
				last = Score.zero();
		}
	}
	for(j := len buf; j < want; j++)
		d[j] = byte 0;
	d[:] = buf;
	return want;
}


Vacfile.mk(s: ref Source): ref Vacfile
{
	return ref Vacfile(s, big 0);
}

Vacfile.new(s: ref Session, e: ref Entry): ref Vacfile
{
	return Vacfile.mk(Source.new(s, e));
}

Vacfile.seek(v: self ref Vacfile, offset: big): big
{
	v.o += offset;
	if(v.o > v.s.e.size)
		v.o = v.s.e.size;
	return v.o;
}

Vacfile.read(v: self ref Vacfile, d: array of byte, n: int): int
{
	have := v.pread(d, n, v.o);
	if(have > 0)
		v.o += big have;
	return have;
}

Vacfile.pread(v: self ref Vacfile, d: array of byte, n: int, offset: big): int
{
	dsize := v.s.dsize;
say(sprint("vf.preadn, len d %d, n %d, offset %bd", len d, n, offset));
	have := v.s.get(big (offset/big dsize), buf := array[dsize] of byte);
	if(have <= 0)
		return have;
say(sprint("vacfile.pread: have=%d dsize=%d", have, dsize));
	o := int (offset % big dsize);
	have -= o;
	if(have > n)
		have = n;
	if(have <= 0)
		return 0;
	d[:] = buf[o:o+have];
	return have;
}


Vacdir.mk(vf: ref Vacfile, ms: ref Source): ref Vacdir
{
	return ref Vacdir(vf, ms, big 0, 0);
}

Vacdir.new(session: ref Session, e, me: ref Entry): ref Vacdir
{
        vf := Vacfile.new(session, e);
        ms := Source.new(session, me);
        return Vacdir.mk(vf, ms);

}

mecmp(d: array of byte, i: int, elem: string, fromfossil: int): (int, int)
{
	me := Metaentry.unpack(d, i);
	if(me == nil)
		return (0, 1);
	o := me.offset+6;
	n := g16(d, o);
	o += BIT16SZ;
	if(o+n > len d) {
		werrstr("bad elem in direntry");
		return (0, 1);
	}
	return (elemcmp(d[o:o+n], array of byte elem, fromfossil), 0);
}

finddirentry(d: array of byte, elem: string): (int, ref Direntry)
{
	mb := Metablock.unpack(d);
	if(mb == nil)
		return (-1, nil);
	fromfossil := g32(d, 0) == Metablockmagic+1;

        left := 0;
        right := mb.nindex;
	while(left+1 != right) {
                mid := (left+right)/2;
		(c, err) := mecmp(d, mid, elem, fromfossil);
		if(err)
			return (-1, nil);
		if(c <= 0)
			left = mid;
		else
			right = mid;
		if(c == 0)
			break;
        }
	de := readdirentry(d, left, 0);
	if(de != nil && de.elem == elem)
		return (1, de);
	return (0, nil);
}

Vacdir.walk(v: self ref Vacdir, elem: string): ref Direntry
{
	i := big 0;
	for(;;) {
		n := v.ms.get(i, buf := array[v.ms.e.dsize] of byte);
		if(n < 0)
			return nil;
		if(n == 0)
			break;
		(ok, de) := finddirentry(buf[:n], elem);
		if(ok < 0)
			return nil;
		if(de != nil)
			return de;
		i++;
	}
	werrstr(sprint("no such file or directory"));
	return nil;
}

vfreadentry(vf: ref Vacfile, entry: int): ref Entry
{
say(sprint("vfreadentry: reading entry=%d", entry));
	ebuf := array[Entrysize] of byte;
	n := vf.pread(ebuf, len ebuf, big entry*big Entrysize);
	if(n < 0)
		return nil;
	if(n != len ebuf) {
		werrstr(sprint("bad archive, entry=%d not present (read %d, wanted %d)", entry, n, len ebuf));
		return nil;
	}
	e := Entry.unpack(ebuf);
	if(~e.flags&Entryactive) {
		werrstr("entry not active");
		return nil;
	}
	# p9p writes archives with Entrylocal set?
	if(0 && e.flags&Entrylocal) {
		werrstr("entry is local");
		return nil;
	}
say(sprint("vreadentry: have entry, score=%s", e.score.text()));
	return e;
}

Vacdir.open(vd: self ref Vacdir, de: ref Direntry): (ref Entry, ref Entry)
{
say(sprint("vacdir.open: opening entry=%d", de.entry));
	e := vfreadentry(vd.vf, de.entry);
	if(e == nil)
		return (nil, nil);
	isdir1 := de.mode & Modedir;
	isdir2 := e.flags & Entrydir;
	if(isdir1 && !isdir2 || !isdir1 && isdir2) {
		werrstr("direntry directory bit does not match entry directory bit");
		return (nil, nil);
	}
say(sprint("vacdir.open: have entry, score=%s size=%bd", e.score.text(), e.size));
	me: ref Entry;
	if(de.mode&Modedir) {
		me = vfreadentry(vd.vf, de.mentry);
		if(me == nil)
			return (nil, nil);
say(sprint("vacdir.open: have mentry, score=%s size=%bd", me.score.text(), e.size));
	}
	return (e, me);
}

readdirentry(buf: array of byte, i: int, allowroot: int): ref Direntry
{
	me := Metaentry.unpack(buf, i);
	if(me == nil)
		return nil;
	o := me.offset;
	de := Direntry.unpack(buf[o:o+me.size]);
	if(badelem(de.elem) && !(allowroot && de.elem == "/")) {
		werrstr(sprint("bad direntry: %s", de.elem));
		return nil;
	}
	return de;
}
	
has(c: int, s: string): int
{
	for(i := 0; i < len s; i++)
		if(s[i] == c)
			return 1;
	return 0;
}

badelem(elem: string): int
{
	return elem == "" || elem == "." || elem == ".." || has('/', elem) || has(0, elem);
}

vdreaddir(vd: ref Vacdir, allowroot: int): (int, ref Direntry)
{
say(sprint("vdreaddir: ms.e.size=%bd vd.p=%bd vd.i=%d", vd.ms.e.size, vd.p, vd.i));
	dsize := vd.ms.dsize;
	n := vd.ms.get(vd.p, buf := array[dsize] of byte);
	if(n <= 0)
		return (n, nil);
say(sprint("vdreaddir: have buf, length=%d e.size=%bd", n, vd.ms.e.size));
	mb := Metablock.unpack(buf);
	if(mb == nil)
		return (-1, nil);
	de := readdirentry(buf, vd.i, allowroot);
	if(de == nil)
		return (-1, nil);
	vd.i++;
	if(vd.i >= mb.nindex) {
		vd.p++;
		vd.i = 0;
	}
say("vdreaddir: have entry");
	return (1, de);
}

Vacdir.readdir(vd: self ref Vacdir): (int, ref Direntry)
{
	return vdreaddir(vd, 0);
}


Vacdir.rewind(vd: self ref Vacdir)
{
	vd.p = big 0;
	vd.i = 0;
}


vdroot(session: ref Session, score: Venti->Score): (ref Vacdir, ref Direntry, string)
{
	d := session.read(score, Roottype, Rootsize);
	if(d == nil)
		return (nil, nil, sprint("reading vac score: %r"));
	r := Root.unpack(d);
	if(r == nil)
		return (nil, nil, sprint("bad vac root block: %r"));
	say("have root");
	topscore := r.score;

	d = session.read(topscore, Dirtype, 3*Entrysize);
	if(d == nil)
		return (nil, nil, sprint("reading rootdir score: %r"));
	if(len d != 3*Entrysize) {
		say("top entries not in directory of 3 elements, assuming it's from fossil");
		if(len d % Entrysize != 0 && len d == 2*Entrysize != 0)	# what's in the second 40 bytes?  looks like 2nd 20 bytes of it is zero score
			return (nil, nil, sprint("bad fossil rootdir, have %d bytes, need %d or %d", len d, Entrysize, 2*Entrysize));
		e := Entry.unpack(d[:Entrysize]);
		if(e == nil)
			return (nil, nil, sprint("unpacking fossil top-level entry: %r"));
		topscore = e.score;
		d = session.read(topscore, Dirtype, 3*Entrysize);
		if(d == nil)
			return (nil, nil, sprint("reading fossil rootdir block: %r"));
		say("have fossil top entries");
	}
	say("have top entries");

	e := array[3] of ref Entry;
	j := 0;
	for(i := 0; i+Entrysize <= len d; i += Entrysize) {
		e[j] = Entry.unpack(d[i:i+Entrysize]);
		if(e[j] == nil)
			return (nil, nil, sprint("reading root entry %d: %r", j));
		j++;
	}
	say("top entries unpacked");

	mroot := Vacdir.mk(nil, Source.new(session, e[2]));
	(ok, de) := vdreaddir(mroot, 1);
	if(ok <= 0)
		return (nil, nil, sprint("reading root meta entry: %r"));

say(sprint("vdroot: new score=%s", score.text()));
	return (Vacdir.new(session, e[0], e[1]), de, nil);
}


checksize(n: int): int
{
	if(n < 256 || n > Venti->Maxlumpsize) {
		sys->werrstr("bad block size");
		return 0;
	}
	return 1;
}

gscore(f: array of byte, i: int): Score
{
	s := Score(array[Scoresize] of byte);
	s.a[0:] = f[i:i+Scoresize];
	return s;
}

g16(f: array of byte, i: int): int
{
	return (int f[i] << 8) | int f[i+1];
}

g32(f: array of byte, i: int): int
{
	return (((((int f[i+0] << 8) | int f[i+1]) << 8) | int f[i+2]) << 8) | int f[i+3];
}

g48(f: array of byte, i: int): big
{
	b1 := (((((int f[i+0] << 8) | int f[i+1]) << 8) | int f[i+2]) << 8) | int f[i+3];
	b0 := (int f[i+4] << 8) | int f[i+5];
	return (big b1 << 16) | big b0;
}

g64(f: array of byte, i: int): big
{
	b0 := (((((int f[i+3] << 8) | int f[i+2]) << 8) | int f[i+1]) << 8) | int f[i];
	b1 := (((((int f[i+7] << 8) | int f[i+6]) << 8) | int f[i+5]) << 8) | int f[i+4];
	return (big b1 << 32) | (big b0 & 16rFFFFFFFF);
}

p16(d: array of byte, i: int, v: int): int
{
	d[i+0] = byte (v>>8);
	d[i+1] = byte v;
	return i+BIT16SZ;
}

p32(d: array of byte, i: int, v: int): int
{
	p16(d, i+0, v>>16);
	p16(d, i+2, v);
	return i+BIT32SZ;
}

p48(d: array of byte, i: int, v: big): int
{
	p16(d, i+0, int (v>>32));
	p32(d, i+2, int v);
	return i+BIT48SZ;
}

p64(d: array of byte, i: int, v: big): int
{
	p32(d, i+0, int (v>>32));
	p32(d, i+4, int v);
	return i+BIT64SZ;
}

ptstring(d: array of byte, i: int, s: string, l: int): int
{
	a := array of byte s;
	if(len a > l) {
		sys->werrstr("string too long: "+s);
		return -1;
	}
	for(j := 0; j < len a; j++)
		d[i+j] = a[j];
	while(j < l)
		d[i+j++] = byte 0;
	return i+l;
}

pscore(d: array of byte, i: int, s: Score): int
{
	for(j := 0; j < Scoresize; j++)
		d[i+j] = s.a[j];
	return i+Scoresize;
}

echeck(f: array of byte, i: int, l: int)
{
	if(i+l > len f)
		raise sprint("too small: buffer length is %d, requested %d bytes starting at offset %d", len f, l, i);
}

egscore(f: array of byte, i: int): (Score, int)
{
	echeck(f, i, Scoresize);
	return (gscore(f, i), i+Scoresize);
}

egstring(a: array of byte, o: int): (string, int)
{
	(s, no) := gstring(a, o);
	if(no == -1)
		raise sprint("too small: string runs outside buffer (length %d)", len a);
	return (s, no);
}

eg16(f: array of byte, i: int): (int, int)
{
	echeck(f, i, BIT16SZ);
	return (g16(f, i), i+BIT16SZ);
}

eg32(f: array of byte, i: int): (int, int)
{
	echeck(f, i, BIT32SZ);
	return (g32(f, i), i+BIT32SZ);
}

eg48(f: array of byte, i: int): (big, int)
{
	echeck(f, i, BIT48SZ);
	return (g48(f, i), i+BIT48SZ);
}

eg64(f: array of byte, i: int): (big, int)
{
	echeck(f, i, BIT64SZ);
	return (g64(f, i), i+BIT64SZ);
}

say(s: string)
{
	if(dflag)
		fprint(fildes(2), "%s\n", s);
}
