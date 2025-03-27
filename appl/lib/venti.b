implement Venti;

include "sys.m";
	sys: Sys;
	sprint: import sys;
include "venti.m";

BIT8SZ:	con 1;
BIT16SZ:	con 2;
BIT32SZ:	con 4;
BIT48SZ:	con 6;
SCORE:	con 20;
STR:		con BIT16SZ;
H: con BIT16SZ+BIT8SZ+BIT8SZ;		# minimum header length: size[2] op[1] tid[1]
Rootnamelen: con 128;

versions := array[] of {"02"};

blankroot: Root;
blankentry: Entry;

init()
{
	sys = load Sys Sys->PATH;
}

hdrlen := array[Tmax] of {
Rerror =>	H+STR,							# size[2] Rerror tid[1] error[s]
Tping =>	H,								# size[2] Tping tid[1]
Rping => 	H,								# size[2] Rping tid[1]
Thello =>	H+STR+STR+BIT8SZ+BIT8SZ+BIT8SZ,	# size[2] Thello tid[1] version[s] uid[s] crypto[1] cryptos[n] codecs[n]
Rhello =>	H+STR+BIT8SZ+BIT8SZ,				# size[2] Rhello tid[1] sid[s] crypto[1] codec[1]
Tgoodbye => H,							# size[2] Tgoodbye tid[1]
Tread =>	H+SCORE+BIT8SZ+BIT8SZ+BIT16SZ,	# size[2] Tread tid[1] score[20] type[1] pad[1] n[2]
Rread => H,								# size[2] Rread tid[1] data
Twrite => H+BIT8SZ+3,						# size[2] Twrite tid[1] type[1] pad[3]
Rwrite => H+SCORE,							# size[2] Rwrite tid[1] score[20
Tsync => H,								# size[2] Tsync tid[1]
Rsync => H,								# size[2] Rsync tid[1]
};

tag2type := array[] of {
tagof Vmsg.Rerror => Rerror,
tagof Vmsg.Tping => Tping,
tagof Vmsg.Rping => Rping,
tagof Vmsg.Thello => Thello,
tagof Vmsg.Rhello => Rhello,
tagof Vmsg.Tgoodbye => Tgoodbye,
tagof Vmsg.Tread => Tread,
tagof Vmsg.Rread => Rread,
tagof Vmsg.Twrite => Twrite,
tagof Vmsg.Rwrite => Rwrite,
tagof Vmsg.Tsync => Tsync,
tagof Vmsg.Rsync => Rsync,
};

msgname := array[] of {
tagof Vmsg.Rerror => "Rerror",
tagof Vmsg.Tping => "Tping",
tagof Vmsg.Rping => "Rping",
tagof Vmsg.Thello => "Thello",
tagof Vmsg.Rhello => "Rhello",
tagof Vmsg.Tgoodbye => "Tgoodbye",
tagof Vmsg.Tread => "Tread",
tagof Vmsg.Rread => "Rread",
tagof Vmsg.Twrite => "Twrite",
tagof Vmsg.Rwrite => "Rwrite",
tagof Vmsg.Tsync => "Tsync",
tagof Vmsg.Rsync => "Rsync",
};

zero := array[] of {
	byte 16rda, byte 16r39, byte 16ra3, byte 16ree, byte 16r5e,
	byte 16r6b, byte 16r4b, byte 16r0d, byte 16r32, byte 16r55,
	byte 16rbf, byte 16ref, byte 16r95, byte 16r60, byte 16r18,
	byte 16r90, byte 16raf, byte 16rd8, byte 16r07, byte 16r09
};
	

Vmsg.read(fd: ref Sys->FD): (ref Vmsg, string)
{
	(msg, err) := readmsg(fd);
	if(err != nil)
		return (nil, err);
	if(msg == nil)
		return (nil, "eof reading message");
	(nil, m) := Vmsg.unpack(msg);
	if(m == nil)
		return (nil, sys->sprint("bad venti message format: %r"));
	return (m, nil);
}

Vmsg.unpack(f: array of byte): (int, ref Vmsg)
{
	if(len f < H) {
		sys->werrstr("message too small");
		return (0, nil);
	}
	size := (int f[0] << 8) | int f[1];		# size does not include self
	size += BIT16SZ;
	if(len f != size){
		if(len f < size){
			sys->werrstr("need more data");
			return (0, nil);		# need more data
		}
		f = f[0:size];			# trim to exact length
	}
	mtype := int f[2];
	if(mtype >= len hdrlen || size < hdrlen[mtype]){
		sys->werrstr("mtype out of range");
		return (-1, nil);
	}
	tid := int f[3];
	m: ref Vmsg;
	case mtype {
	Thello =>
		uid: string;
		cryptos, codecs: array of byte;

		(version, o) := gstring(f, H);
		(uid, o) = gstring(f, o);
		if(o < 0 || o >= len f)
			break;
		cryptostrength := int f[o++];
		(cryptos, o) = gbytes(f, o);
		(codecs, o) = gbytes(f, o);
		if(o != len f)
			break;
		m = ref Vmsg.Thello(1, tid, version, uid, cryptostrength, cryptos, codecs);
	Tping =>
		m = ref Vmsg.Tping(1, tid);
	Tgoodbye =>
		m = ref Vmsg.Tgoodbye(1, tid);
	Tread =>
		score := Score(f[H:H+SCORE]);
		etype := int f[H+SCORE];
		n := (int f[H+SCORE+2] << 8) | int f[H+SCORE+3];
		m = ref Vmsg.Tread(1, tid, score, etype, n);
	Twrite =>
		etype := int f[H];
		m = ref Vmsg.Twrite(1, tid, etype, f[H+4:]);
	Tsync =>
		m = ref Vmsg.Tsync(1, tid);
	Rhello =>
		(sid, o) := gstring(f, H);
		if(o+2 != len f)
			break;
		crypto := int f[o++];
		codec := int f[o++];
		m = ref Vmsg.Rhello(0, tid, sid, crypto, codec);
	Rping =>
		m = ref Vmsg.Rping(0, tid);
	Rread =>
		m = ref Vmsg.Rread(0, tid, f[H:]);
	Rwrite =>
		m = ref Vmsg.Rwrite(0, tid, Score(f[H:H+SCORE]));
	Rsync =>
		m = ref Vmsg.Rsync(0, tid);
	Rerror =>
		(err, o) := gstring(f, H);
		if(o < 0)
			break;
		m = ref Vmsg.Rerror(0, tid, err);
	* =>
		sys->werrstr("unrecognised mtype " + string mtype);
		return (-1, nil);
	}
	if(m == nil) {
		sys->werrstr("bad message size");
		return (-1, nil);
	}
	return (size, m);
}

Vmsg.pack(gm: self ref Vmsg): array of byte
{
	if(gm == nil)
		return nil;
	ds := gm.packedsize();
	if(ds <= 0)
		return nil;
	d := array[ds] of byte;
	d[0] = byte ((ds - 2) >> 8);
	d[1] = byte (ds - 2);
	d[2] = byte tag2type[tagof gm];
	d[3] = byte gm.tid;
	pick m := gm {
	Thello =>
		o := pstring(d, H, m.version);
		o = pstring(d, o, m.uid);
		d[o++] = byte m.cryptostrength;
		d[o++] = byte len m.cryptos;
		d[o:] = m.cryptos;
		o += len m.cryptos;
		d[o++] = byte len m.codecs;
		d[o:] = m.codecs;
		o += len m.codecs;
	Tping =>
		;
	Tgoodbye =>
		;
	Tread =>
		d[H:] = m.score.a;
		d[H+SCORE] = byte m.etype;
		d[H+SCORE+2] = byte (m.n >> 8);
		d[H+SCORE+3] = byte m.n;
	Twrite =>
		d[H] = byte m.etype;
		d[H+4:] = m.data;
	Tsync =>
		;
	Rhello =>
		o := pstring(d, H, m.sid);
		d[o++] = byte m.crypto;
		d[o++] = byte m.codec;
	Rping =>
		;
	Rread =>
		d[H:] = m.data;
	Rwrite =>
		d[H:] = m.score.a;
	Rsync =>
		;
	Rerror =>
		pstring(d, H, m.e);
	* =>
		return nil;
	}
	return d;
}

Vmsg.packedsize(gm: self ref Vmsg): int
{
	mtype := tag2type[tagof gm];
	if(mtype <= 0)
		return 0;
	ml := hdrlen[mtype];
	pick m := gm {
	Thello =>
		ml += utflen(m.version) + utflen(m.uid) + len m.cryptos + len m.codecs;
	Rhello =>
		ml += utflen(m.sid);
	Rread =>
		ml += len m.data;
	Twrite =>
		ml += len m.data;
	Rerror =>
		ml += utflen(m.e);
	}
	return ml;
}

Vmsg.text(gm: self ref Vmsg): string
{
	if(gm == nil)
		return "(nil)";
	s := sys->sprint("%s(%d", msgname[tagof gm], gm.tid);
	pick m := gm {
	* =>
		s += ",ILLEGAL";
	Thello =>
		s += sys->sprint(", %#q, %#q, %d, [", m.version, m.uid, m.cryptostrength);
		if(len m.cryptos > 0){
			s += string int m.cryptos[0];
			for(i := 1; i < len m.cryptos; i++)
				s += "," + string int m.cryptos[i];
		}
		s += "], [";
		if(len m.codecs > 0){
			s += string int m.codecs[0];
			for(i := 1; i < len m.codecs; i++)
				s += "," + string int m.codecs[i];
		}
		s += "]";
	Tping =>
		;
	Tgoodbye =>
		;
	Tread =>
		s += sys->sprint(", %s, %d, %d", m.score.text(), m.etype, m.n);
	Twrite =>
		s += sys->sprint(", %d, data[%d]", m.etype, len m.data);
	Tsync =>
		;
	Rhello =>
		s += sys->sprint(", %#q, %d, %d", m.sid, m.crypto, m.codec);
	Rping =>
	Rread =>
		s += sys->sprint(", data[%d]", len m.data);
	Rwrite =>
		s += ", " + m.score.text();
	Rsync =>
		;
	Rerror =>
		s += sys->sprint(", %#q", m.e);
	}
	return s + ")";
}

Session.new(fd: ref Sys->FD): ref Session
{
	s := "venti-";
	for(i := 0; i < len versions; i++){
		if(i != 0)
			s[len s] = ':';
		s += versions[i];
	}
	s += "-libventi\n";
	d := array of byte s;
	if(sys->write(fd, d, len d) != len d)
		return nil;
	version := readversion(fd, "venti-", versions);
	if(version == nil)
		return nil;
	session := ref Session(fd, version);
	(r, e) := session.rpc(ref Vmsg.Thello(1, 0, version, nil, 0, nil, nil));
	if(r == nil){
		sys->werrstr("hello failed: " + e);
		return nil;
	}
	return ref Session(fd, version);
}

Session.read(s: self ref Session, score: Score, etype: int, maxn: int): array of byte
{
	if (Score.eq(score, Score.zero()) {
		return array[0] of byte;
	}

	(gm, err) := s.rpc(ref Vmsg.Tread(1, 0, score, etype, maxn));
	if(gm == nil){
		sys->werrstr(err);
		return nil;
	}
	pick m := gm {
	Rread =>
		return m.data;
	}
	return nil;
}

Session.write(s: self ref Session, etype: int, data: array of byte): (int, Score)
{
	(gm, err) := s.rpc(ref Vmsg.Twrite(1, 0, etype, data));
	if(gm == nil){
		sys->werrstr(err);
		return (-1, Score(nil));
	}
	pick m := gm {
	Rwrite =>
		return (0, m.score);
	}
	return (-1, Score(nil));
}

Session.sync(s: self ref Session): int
{
	(gm, err) := s.rpc(ref Vmsg.Tsync(1, 0));
	if(gm == nil){
		sys->werrstr(err);
		return -1;
	}
	return 0;
}

Session.rpc(s: self ref Session, m: ref Vmsg): (ref Vmsg, string)
{
	d := m.pack();
	if(sys->write(s.fd, d, len d) != len d)
		return (nil, "write failed");
	(grm, err) := Vmsg.read(s.fd);
	if(grm == nil)
		return (nil, err);
	if(grm.tid != m.tid)
		return (nil, "message tags don't match");
	if(grm.istmsg)
		return (nil, "reply message is a t-message");
	pick rm := grm {
	Rerror =>
		return (nil, rm.e);
	}
	if(tagof(grm) != tagof(m) + 1)
		return (nil, "reply message is of wrong type");
	return (grm, nil);
}

readversion(fd: ref Sys->FD, prefix: string, versions: array of string): string
{
	buf := array[Maxstringsize] of byte;
	i := 0;
	for(;;){
		if(i >= len buf){
			sys->werrstr("initial version string too long");
			return nil;
		}
		if(readn(fd, buf[i:], 1) != 1){
			sys->werrstr("eof on version string");
			return nil;
		}
		c := int buf[i];
		if(c == '\n')
			break;
		if(c < ' ' || c > 16r7f || i < len prefix && prefix[i] != c){
			sys->werrstr("bad version string");
			return nil;
		}
		i++;
	}
	if(i < len prefix){
		sys->werrstr("bad version string");
		return nil;
	}
#sys->fprint(sys->fildes(2), "read version %#q\n", string buf[0:i]);
	v := string buf[len prefix:i];
	i = 0;
	for(;;){
		for(j := i; j < len v && v[j] != ':' && v[j] != '-'; j++)
			;
		vv := v[i:j];
#sys->fprint(sys->fildes(2), "checking %#q\n", vv);
		for(k := 0; k < len versions; k++)
			if(versions[k] == vv)
				return vv;
		i = j;
		if(i >= len v || v[i] != ':'){
			sys->werrstr("unknown version");
			return nil;
		}
		i++;
	}
	sys->werrstr("unknown version");
	return nil;
}


Score.eq(a: self Score, b: Score): int
{
	for(i := 0; i < SCORE; i++)
		if(a.a[i] != b.a[i])
			return 0;
	return 1;
}

Score.zero(): Score
{
	return Score(zero);
}

Score.parse(s: string): (int, Score)
{
	if(len s != Scoresize * 2)
		return (-1, Score(nil));
	score := array[Scoresize] of {* => byte 0};
	for(i := 0; i < len s; i++){
		c := s[i];
		case s[i] {
		'0' to '9' =>
			c -= '0';
		'a' to 'f' =>
			c -= 'a' - 10;
		'A' to 'F' =>
			c -= 'A' - 10;
		* =>
			return (-1, Score(nil));
		}
		if((i & 1) == 0)
			c <<= 4;
		score[i>>1] |= byte c;
	}
	return (0, Score(score));
}

Score.text(a: self Score): string
{
	s := "";
	for(i := 0; i < SCORE; i++)
		s += sys->sprint("%.2ux", int a.a[i]);
	return s;
}

readn(fd: ref Sys->FD, buf: array of byte, nb: int): int
{
	for(nr := 0; nr < nb;){
		n := sys->read(fd, buf[nr:], nb-nr);
		if(n <= 0){
			if(nr == 0)
				return n;
			break;
		}
		nr += n;
	}
	return nr;
}

readmsg(fd: ref Sys->FD): (array of byte, string)
{
	sbuf := array[BIT16SZ] of byte;
	if((n := readn(fd, sbuf, BIT16SZ)) != BIT16SZ){
		if(n == 0)
			return (nil, nil);
		return (nil, sys->sprint("%r"));
	}
	ml := (int sbuf[0] << 8) | int sbuf[1];
	if(ml < BIT16SZ)
		return (nil, "invalid venti message size");
	buf := array[ml + BIT16SZ] of byte;
	buf[0:] = sbuf;
	if((n = readn(fd, buf[BIT16SZ:], ml)) != ml){
		if(n == 0)
			return (nil, "venti message truncated");
		return (nil, sys->sprint("%r"));
	}
	return (buf, nil);
}

pstring(a: array of byte, o: int, s: string): int
{
	sa := array of byte s;	# could do conversion ourselves
	n := len sa;
	a[o] = byte (n >> 8);
	a[o+1] = byte n;
	a[o+2:] = sa;
	return o+STR+n;
}

gstring(a: array of byte, o: int): (string, int)
{
	if(o < 0 || o+STR > len a)
		return (nil, -1);
	l := (int a[o] << 8) | int a[o+1];
	if(l > Maxstringsize)
		return (nil, -1);
	o += STR;
	e := o+l;
	if(e > len a)
		return (nil, -1);
	return (string a[o:e], e);
}

gbytes(a: array of byte, o: int): (array of byte, int)
{
	if(o < 0 || o+1 > len a)
		return (nil, -1);
	n := int a[o];
	if(1+n > len a)
		return (nil, -1);
	no := o+1+n;
	return (a[o+1:no], no);
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
	prev := gscore(d, o);
	if(!prev.eq(Score(array[Scoresize] of {* => byte 0})))
		r.prev = ref prev;
	return r;
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
		sys->werrstr(sprint("bad length, have %d, want %d", i, len d));
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

checksize(n: int): int
{
	if(n < 256 || n > Maxlumpsize) {
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
	b0 := (((((int f[i+0] << 8) | int f[i+1]) << 8) | int f[i+2]) << 8) | int f[i+3];
	b1 := (((((int f[i+4] << 8) | int f[i+5]) << 8) | int f[i+6]) << 8) | int f[i+7];
	return (big b0 << 32) | (big b1 & 16rFFFFFFFF);
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
