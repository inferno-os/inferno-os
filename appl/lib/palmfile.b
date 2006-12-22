implement Palmfile;

#
# Copyright © 2001-2002 Vita Nuova Holdings Limited.  All rights reserved.
#
# Based on ``Palm® File Format Specification'', Document Number 3008-004, 1 May 2001, by Palm Inc.
# Doc compression based on description by Paul Lucas, 18 August 1998
#

include "sys.m";
	sys: Sys;

include "daytime.m";
	daytime: Daytime;

include "bufio.m";
	bufio: Bufio;
	Iobuf: import bufio;

include "palmfile.m";


Dbhdrlen: con 72+6;
Datahdrsize: con 4+1+3;
Resourcehdrsize: con 4+2+4;

# Exact value of "Jan 1, 1970 0:00:00 GMT" - "Jan 1, 1904 0:00:00 GMT"
Epochdelta: con 2082844800;
tzoff := 0;

init(): string
{
	sys = load Sys Sys->PATH;
	bufio = load Bufio Bufio->PATH;
	daytime = load Daytime Daytime->PATH;
	if(bufio == nil || daytime == nil)
		return "can't load required module";
	tzoff = daytime->local(0).tzoff;
	return nil;
}

Eshort: con "file format error: too small";

Pfile.open(name: string, mode: int): (ref Pfile, string)
{
	if(mode != Sys->OREAD)
		return (nil, "invalid mode");
	fd := sys->open(name, mode);
	if(fd == nil)
		return (nil, sys->sprint("%r"));
	pf := mkpfile(name, mode);
	(ok, d) := sys->fstat(fd);
	if(ok < 0)
		return (nil, sys->sprint("%r"));
	length := int d.length;
	if(length == 0)
		return (nil, "empty file");

	f := bufio->fopen(fd, mode);	# automatically closed if open fails

	p := array[Dbhdrlen] of byte;
	if(f.read(p, Dbhdrlen) != Dbhdrlen)
		return (nil, "invalid file header: too short");

	ip := pf.info;
	ip.name = gets(p[0:32]);
	ip.attr = get2(p[32:]);
	ip.version = get2(p[34:]);
	ip.ctime = pilot2epoch(get4(p[36:]));
	ip.mtime = pilot2epoch(get4(p[40:]));
	ip.btime = pilot2epoch(get4(p[44:]));
	ip.modno = get4(p[48:]);
	ip.appinfo = get4(p[52:]);
	ip.sortinfo = get4(p[56:]);
	if(ip.appinfo < 0 || ip.sortinfo < 0 || (ip.appinfo|ip.sortinfo)&1)
		return (nil, "invalid header: bad offset");
	ip.dtype = xs(get4(p[60:]));
	ip.creator = xs(get4(p[64:]));
	pf.uidseed = ip.uidseed = get4(p[68:]);

	if(get4(p[72:]) != 0)
		return (nil, "chained headers not supported");	# Palm says to reject such files
	nrec := get2(p[76:]);
	if(nrec < 0)
		return (nil, sys->sprint("invalid header: bad record count: %d", nrec));

	esize := Datahdrsize;
	if(ip.attr & Fresource)
		esize = Resourcehdrsize;
	
	dataoffset := length;
	pf.entries = array[nrec] of ref Entry;
	if(nrec > 0){
		laste: ref Entry;
		buf := array[esize] of byte;
		for(i := 0; i < nrec; i++){
			if(f.read(buf, len buf) != len buf)
				return (nil, Eshort);
			e := ref Entry;
			if(ip.attr & Fresource){
				# resource entry: type[4], id[2], offset[4]
				e.name = get4(buf);
				e.id = get2(buf[4:]);
				e.offset = get4(buf[6:]);
				e.attr = 0;
			}else{
				# record entry: offset[4], attr[1], id[3]
				e.offset = get4(buf);
				e.attr = int buf[4];
				e.id = get3(buf[5:]);
				e.name = 0;
			}
			if(laste != nil)
				laste.size = e.offset - laste.offset;
			laste = e;
			pf.entries[i] = e;
		}
		if(laste != nil)
			laste.size = length - laste.offset;
		dataoffset = pf.entries[0].offset;
	}else{
		if(f.read(p, 2) != 2)
			return (nil, Eshort);	# discard placeholder bytes
	}

	n := 0;
	if(ip.appinfo > 0){
		n = ip.appinfo - int f.offset();
		while(--n >= 0)
			f.getb();
		if(ip.sortinfo)
			n = ip.sortinfo - ip.appinfo;
		else
			n = dataoffset - ip.appinfo;
		pf.appinfo = array[n] of byte;
		if(f.read(pf.appinfo, n) != n)
			return (nil, Eshort);
	}
	if(ip.sortinfo > 0){
		n = ip.sortinfo - int f.offset();
		while(--n >= 0)
			f.getb();
		n = (dataoffset-ip.sortinfo)/2;
		pf.sortinfo = array[n] of int;
		tmp := array[2*n] of byte;
		if(f.read(tmp, len tmp) != len tmp)
			return (nil, Eshort);
		for(i := 0; i < n; i++)
			pf.sortinfo[i] = get2(tmp[2*i:]);
	}
	pf.f = f;	# safe to save open file reference
	return (pf, nil);
}

Pfile.close(pf: self ref Pfile): int
{
	if(pf.f != nil){
		pf.f.close();
		pf.f = nil;
	}
	return 0;
}

Pfile.stat(pf: self ref Pfile): ref DBInfo
{
	return ref *pf.info;
}

Pfile.read(pf: self ref Pfile, i: int): (ref Record, string)
{
	if(i < 0 || i >= len pf.entries){
		if(i == len pf.entries)
			return (nil, nil);	# treat as end-of-file
		return (nil, "index out of range");
	}
	e := pf.entries[i];
	r := ref Record;
	r.index = i;
	nb := e.size;
	r.data = array[nb] of byte;
	pf.f.seek(big e.offset, 0);
	if(pf.f.read(r.data, nb) != nb)
		return (nil, sys->sprint("%r"));
	r.cat = e.attr & 16r0F;
	r.attr = e.attr & 16rF0;
	r.id = e.id;
	r.name = e.name;
	return (r, nil);
}

#Pfile.create(name: string, info: ref DBInfo): ref Pfile
#{
#}

#Pfile.wstat(pf: self ref Pfile, ip: ref DBInfo): string
#{
#	if(pf.mode != Sys->OWRITE)
#		return "not open for writing";
#	if((ip.attr & Fresource) != (pf.info.attr & Fresource))
#		return "cannot change file type";
#	# copy only a subset
#	pf.info.name = ip.name;
#	pf.info.attr = ip.attr;
#	pf.info.version = ip.version;
#	pf.info.ctime = ip.ctime;
#	pf.info.mtime = ip.mtime;
#	pf.info.btime = ip.btime;
#	pf.info.modno = ip.modno;
#	pf.info.dtype = ip.dtype;
#	pf.info.creator = ip.creator;
#	return nil;
#}

#Pfile.setappinfo(pf: self ref Pfile, data: array of byte): string
#{
#	if(pf.mode != Sys->OWRITE)
#		return "not open for writing";
#	pf.appinfo = array[len data] of byte;
#	pf.appinfo[0:] = data;
#}

#Pfile.setsortinfo(pf: self ref Pfile, sort: array of int): string
#{
#	if(pf.mode != Sys->OWRITE)
#		return "not open for writing";
#	pf.sortinfo = array[len sort] of int;
#	pf.sortinfo[0:] = sort;
#}

#
# internal function to extend entry list if necessary, and return a
# pointer to the next available slot
#
entryensure(pf: ref Pfile, i: int): ref Entry
{
	if(i < len pf.entries)
		return pf.entries[i];
	e := ref Entry(0, -1, 0, 0, 0);
	n := len pf.entries;
	if(n == 0)
		n = 64;
	else
		n = (i+63) & ~63;
	a := array[n] of ref Entry;
	a[0:] = pf.entries;
	a[i] = e;
	pf.entries = a;
	return e;
}

writefilehdr(pf: ref Pfile, mode: int, perm: int): string
{
	if(len pf.entries >= 64*1024)
		return "too many records for Palm file";	# is there a way to extend it?

	if((f := bufio->create(pf.fname, mode, perm)) == nil)
		return sys->sprint("%r");

	ip := pf.info;

	esize := Datahdrsize;
	if(ip.attr & Fresource)
		esize = Resourcehdrsize;
	offset := Dbhdrlen + esize*len pf.entries + 2;
	offset += 2;	# placeholder bytes or gap bytes
	ip.appinfo = 0;
	if(len pf.appinfo > 0){
		ip.appinfo = offset;
		offset += len pf.appinfo;
	}
	ip.sortinfo = 0;
	if(len pf.sortinfo > 0){
		ip.sortinfo = offset;
		offset += 2*len pf.sortinfo;	# 2-byte entries
	}
	p := array[Dbhdrlen] of byte;	# bigger than any entry as well
	puts(p[0:32], ip.name);
	put2(p[32:], ip.attr);
	put2(p[34:], ip.version);
	put4(p[36:], epoch2pilot(ip.ctime));
	put4(p[40:], epoch2pilot(ip.mtime));
	put4(p[44:], epoch2pilot(ip.btime));
	put4(p[48:], ip.modno);
	put4(p[52:], ip.appinfo);
	put4(p[56:], ip.sortinfo);
	put4(p[60:], sx(ip.dtype));
	put4(p[64:], sx(ip.creator));
	put4(p[68:], pf.uidseed);
	put4(p[72:], 0);		# next record list ID
	put2(p[76:], len pf.entries);

	if(f.write(p, Dbhdrlen) != Dbhdrlen)
		return ewrite(f);
	if(len pf.entries > 0){
		for(i := 0; i < len pf.entries; i++) {
			e := pf.entries[i];
			e.offset = offset;
			if(ip.attr & Fresource) {
				put4(p, e.name);
				put2(p[4:], e.id);
				put4(p[6:], e.offset);
			} else {
				put4(p, e.offset);
				p[4] = byte e.attr;
				put3(p[5:], e.id);
			}
			if(f.write(p, esize) != esize)
				return ewrite(f);
			offset += e.size;
		}
	}

	f.putb(byte 0);	# placeholder bytes (figure 1.4) or gap bytes (p. 15)
	f.putb(byte 0);

	if(ip.appinfo != 0){
		if(f.write(pf.appinfo, len pf.appinfo) != len pf.appinfo)
			return ewrite(f);
	}

	if(ip.sortinfo != 0){
		tmp := array[2*len pf.sortinfo] of byte;
		for(i := 0; i < len pf.sortinfo; i++)
			put2(tmp[2*i:], pf.sortinfo[i]);
		if(f.write(tmp, len tmp) != len tmp)
			return ewrite(f);
	}

	if(f.flush() != 0)
		return ewrite(f);

	return nil;
}

ewrite(f: ref Iobuf): string
{
	e := sys->sprint("write error: %r");
	f.close();
	return e;
}

Doc.open(file: ref Pfile): (ref Doc, string)
{
	if(file.info.dtype != "TEXt" || file.info.creator != "REAd")
		return (nil, "not a Doc file: wrong type or creator");
	(r, err) := file.read(0);
	if(r == nil){
		if(err == nil)
			err = "no directory record";
		return (nil, sys->sprint("not a valid Doc file: %s", err));
	}
	a := r.data;
	if(len a < 16)
		return (nil, sys->sprint("not a valid Doc file: bad length: %d", len a));
	maxrec := len file.entries-1;
	d := ref Doc;
	d.file = file;
	d.version = get2(a);
	if(d.version != 1 && d.version != 2)
		err = "unknown Docfile version";
	# a[2:] is spare
	d.length = get4(a[4:]);
	d.nrec = get2(a[8:]);
	if(maxrec >= 0 && d.nrec > maxrec){
		d.nrec = maxrec;
		err = "invalid record count";
	}
	d.recsize = get2(a[10:]);
	d.position = get4(a[12:]);
	return (d, sys->sprint("unexpected Doc file format: %s", err));
}

Doc.iscompressed(d: self ref Doc): int
{
	return (d.version&7) == 2;		# high-order bits are sometimes used, ignore them
}

Doc.read(doc: self ref Doc, index: int): (string, string)
{
	(r, err) := doc.file.read(index+1);
	if(r == nil)
		return (nil, err);
	(s, serr) := doc.unpacktext(r.data);
	if(s == nil)
		return (nil, serr);
	return (s, nil);
}

Doc.unpacktext(doc: self ref Doc, a: array of byte): (string, string)
{
	nb := len a;
	s: string;
	if(!doc.iscompressed()){
		for(i := 0; i < nb; i++)
			s[len s] = int a[i];	# assumes Latin-1
		return (s, nil);
	}
	o := 0;
	for(i := 0; i < nb;){
		c := int a[i++];
		if(c >= 9 && c <= 16r7F || c == 0)
			s[o++] = c;
		else if(c >= 1 && c <= 8){
			if(i+c > nb)
				return (nil, "missing data in record");
			while(--c >= 0)
				s[o++] = int a[i++];
		}else if(c >= 16rC0 && c <= 16rFF){
			s[o] = ' ';
			s[o+1] = c & 16r7F;
			o += 2;
		}else{	# c >= 0x80 && c <= 16rBF
			v := int a[i++];
			m := ((c & 16r3F)<<5)|(v>>3);
			n := (v&7) + 3;
			if(m == 0 || m > o)
				return (nil, sys->sprint("data is corrupt: m=%d n=%d o=%d", m, n, o));
			for(; --n >= 0; o++)
				s[o] = s[o-m];
		}
	}
	return (s, nil);
}

Doc.textlength(doc: self ref Doc, a: array of byte): int
{
	nb := len a;
	if(!doc.iscompressed())
		return nb;
	o := 0;
	for(i := 0; i < nb;){
		c := int a[i++];
		if(c >= 9 && c <= 16r7F || c == 0)
			o++;
		else if(c >= 1 && c <= 8){
			if(i+c > nb)
				return -1;
			o += c;
			i += c;
		}else if(c >= 16rC0 && c <= 16rFF){
			o += 2;
		}else{	# c >= 0x80 && c <= 16rBF
			v := int a[i++];
			m := ((c & 16r3F)<<5)|(v>>3);
			n := (v&7) + 3;
			if(m == 0 || m > o)
				return -1;
			o += n;
		}
	}
	return o;
}

xs(i: int): string
{
	if(i == 0)
		return "";
	if(i & int 16r80808080)
		return sys->sprint("%8.8ux", i);
	return sys->sprint("%c%c%c%c", (i>>24)&16rFF, (i>>16)&16rFF, (i>>8)&16rFF, i&16rFF);
}

sx(s: string): int
{
	n := 0;
	for(i := 0; i < 4; i++){
		c := 0;
		if(i < len s)
			c = s[i] & 16rFF;
		n = (n<<8) | c;
	}
	return n;
}

mkpfile(name: string, mode: int): ref Pfile
{
	pf := ref Pfile;
	pf.mode = mode;
	pf.fname = name;
	pf.appinfo = array[0] of byte;		# making it non-nil saves having to check each access
	pf.sortinfo = array[0] of int;
	pf.uidseed = 0;
	pf.info = DBInfo.new(name, 0, nil, 0, nil);
	return pf;
}

DBInfo.new(name: string, attr: int, dtype: string, version: int, creator: string): ref DBInfo
{
	info := ref DBInfo;
	info.name = name;
	info.attr = attr;
	info.version = version;
	info.ctime = daytime->now();
	info.mtime = daytime->now();
	info.btime = 0;
	info.modno = 0;
	info.appinfo = 0;
	info.sortinfo = 0;
	info.dtype = dtype;
	info.creator = creator;
	info.uidseed = 0;
	info.index = 0;
	info.more = 0;
	return info;
}

Categories.new(labels: array of string): ref Categories
{
	c := ref Categories;
	c.renamed = 0;
	c.lastuid = 0;
	c.labels = array[16] of string;
	c.uids = array[] of {0 to 15 => 0};
	for(i := 0; i < len labels && i < 16; i++){
		c.labels[i] = labels[i];
		c.lastuid = 16r80 + i;
		c.uids[i] = c.lastuid;
	}
	return c;
}

Categories.unpack(a: array of byte): ref Categories
{
	if(len a < 16r114)
		return nil;		# doesn't match the structure
	c := ref Categories;
	c.renamed = get2(a);
	c.labels = array[16] of string;
	c.uids = array[16] of int;
	j := 2;
	for(i := 0; i < 16; i++){
		c.labels[i] = latin1(a[j:j+16], 0);
		j += 16;
		c.uids[i] = int a[16r102+i];
	}
	c.lastuid = int a[16r112];
	# one byte of padding is shown on p. 26, but
	# two more are invariably used in practice
	# before application specific data.
	if(len a > 16r116)
		c.appdata = a[16r116:];
	return c;
}

Categories.pack(c: self ref Categories): array of byte
{
	a := array[16r116 + len c.appdata] of byte;
	put2(a, c.renamed);
	j := 2;
	for(i := 0; i < 16; i++){
		puts(a[j:j+16], c.labels[i]);
		j += 16;
		a[16r102+i] = byte c.uids[i];
	}
	a[16r112] = byte c.lastuid;
	a[16r113] = byte 0;	# pad shown on p. 26
	a[16r114] = byte 0;	# extra two bytes of padding used in practice
	a[16r115] = byte 0;
	if(c.appdata != nil)
		a[16r116:] = c.appdata;
	return a;
}

Categories.mkidmap(c: self ref Categories): array of int
{
	a := array[256] of {* => 0};
	for(i := 0; i < len c.uids; i++)
		a[c.uids[i]] = i;
	return a;
}

#
# because PalmOS treats all times as local times, and doesn't associate
# them with time zones, we'll convert using local time on Plan 9 and Inferno
#

pilot2epoch(t: int): int
{
	if(t == 0)
		return 0;	# we'll assume it's not set
	return t - Epochdelta + tzoff;
}

epoch2pilot(t: int): int
{
	if(t == 0)
		return t;
	return t - tzoff + Epochdelta;
}

#
# map Palm name to string, assuming iso-8859-1,
# but remap space and /
#
latin1(a: array of byte, remap: int): string
{
	s := "";
	for(i := 0; i < len a; i++){
		c := int a[i];
		if(c == 0)
			break;
		if(remap){
			if(c == ' ')
				c = 16r00A0;	# unpaddable space
			else if(c == '/')
				c = 16r2215;	# division /
		}
		s[len s] = c;
	}
	return s;
}

#
# map from Unicode to Palm name
#
filename(name: string): string
{
	s := "";
	for(i := 0; i < len name; i++){
		c := name[i];
		if(c == ' ')
			c = 16r00A0;	# unpaddable space
		else if(c == '/')
			c = 16r2215;	# division solidus
		s[len s] = c;
	}
	return s;
}

dbname(name: string): string
{
	s := "";
	for(i := 0; i < len name; i++){
		c := name[i];
		case c {
		0 =>			c = ' ';	# unlikely, but just in case
		16r2215 =>	c = '/';
		16r00A0 =>	c = ' ';
		}
		s[len s] = c;
	}
	return s;
}

#
# string conversion: can't use (string a) because
# the bytes are Latin1, not Unicode
#
gets(a: array of byte): string
{
	s := "";
	for(i := 0; i < len a; i++)
		s[len s] = int a[i];
	return s;
}

puts(a: array of byte, s: string)
{
	for(i := 0; i < len a-1 && i < len s; i++)
		a[i] = byte s[i];
	for(; i < len a; i++)
		a[i] = byte 0;
}

#
#  big-endian packing
#

get4(p: array of byte): int
{
	return (((((int p[0] << 8) | int p[1]) << 8) | int p[2]) << 8) | int p[3];
}

get3(p: array of byte): int
{
	return (((int p[0] << 8) | int p[1]) << 8) | int p[2];
}

get2(p: array of byte): int
{
	return (int p[0]<<8) | int p[1];
}

put4(p: array of byte, v: int)
{
	p[0] = byte (v>>24);
	p[1] = byte (v>>16);
	p[2] = byte (v>>8);
	p[3] = byte (v & 16rFF);
}

put3(p: array of byte, v: int)
{
	p[0] = byte (v>>16);
	p[1] = byte (v>>8);
	p[2] = byte (v & 16rFF);
}

put2(p: array of byte, v: int)
{
	p[0] = byte (v>>8);
	p[1] = byte (v & 16rFF);
}
