implement Palm;

#
# Copyright © 2001-2003 Vita Nuova Holdings Limited.  All rights reserved.
#
# Based on ``Palm® File Format Specification'', Document Number 3008-004, 1 May 2001, by Palm Inc.
# Doc compression based on description by Paul Lucas, 18 August 1998
#

include "sys.m";
	sys: Sys;

include "daytime.m";
	daytime: Daytime;

include "palm.m";

# Exact value of "Jan 1, 1970 0:00:00 GMT" - "Jan 1, 1904 0:00:00 GMT"
Epochdelta: con 2082844800;
tzoff := 0;

init(): string
{
	sys = load Sys Sys->PATH;
	daytime = load Daytime Daytime->PATH;
	if(daytime == nil)
		return "can't load required module";
	tzoff = daytime->local(0).tzoff;
	return nil;
}

Record.new(id: int, attr: int, cat: int, size: int): ref Record
{
	return ref Record(id, attr, cat, array[size] of byte);
}

Resource.new(name: int, id: int, size: int): ref Resource
{
	return ref Resource(name, id, array[size] of byte);
}

Doc.open(m: Palmdb, file: ref Palmdb->PDB): (ref Doc, string)
{
	info := m->file.db.stat();
	if(info.dtype != "TEXt" || info.creator != "REAd")
		return (nil, "not a Doc file: wrong type or creator");
	r := m->file.read(0);
	if(r == nil)
		return (nil, sys->sprint("not a valid Doc file: %r"));
	a := r.data;
	if(len a < 16)
		return (nil, sys->sprint("not a valid Doc file: bad length: %d", len a));
	maxrec := m->file.db.nentries()-1;
	d := ref Doc;
	d.m = m;
	d.file = file;
	d.version = get2(a);
	err := "unknown";
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
	m := doc.m;
	DB, PDB: import m;
	r := doc.file.read(index+1);
	if(r == nil)
		return (nil, sys->sprint("%r"));
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

id2s(i: int): string
{
	if(i == 0)
		return "";
	return sys->sprint("%c%c%c%c", (i>>24)&16rFF, (i>>16)&16rFF, (i>>8)&16rFF, i&16rFF);
}

s2id(s: string): int
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
	info.dtype = dtype;
	info.creator = creator;
	info.uidseed = 0;
	info.index = 0;
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

#
# DL protocol argument wrapping, based on conventions
# extracted from include/Core/System/DLCommon.h in SDK 5
#
# tiny arguments
#	id: byte
#	size: byte	# excluding this header
#	data: byte[]
#
# small arguments
#	id: byte	# with 16r80 flag
#	pad: byte
#	size: byte[2]
#	data: byte[]
#
# long arguments
#	id: byte	# with 16r40 flag
#	pad: byte
#	size: byte[4]
#	data: byte[]

# wrapper format flag in request/response argument ID
ShortWrap: con 16r80;	# 2-byte count
LongWrap: con 16r40;	# 4-byte count

Eshort: con "response shorter than expected";

#
# set the system error string
#
e(s: string): string
{
	if(s != nil)
		sys->werrstr(s);
	return s;
}

argsize(args: array of (int, array of byte)): int
{
	totnb := 0;
	for(i := 0; i < len args; i++){
		(nil, a) := args[i];
		n := len a;
		if(n > 65535)
			totnb += 6;	# long wrap
		else if(n > 255)
			totnb += 4;	# short
		else
			totnb += 2;	# tiny
		totnb += n;
	}
	return totnb;
}

packargs(out: array of byte, args: array of (int, array of byte)): array of byte
{
	for(i := 0; i < len args; i++){
		(id, a) := args[i];
		n := len a;
		if(n > 65535){
			out[0] = byte (LongWrap|ShortWrap|id);
			out[1] = byte 0;
			put4(out[2:], n);
			out = out[6:];
		}else if(n > 255){
			out[0] = byte (ShortWrap|id);
			out[1] = byte 0;
			put2(out[2:], n);
			out = out[4:];
		}else{
			out[0] = byte id;
			out[1] = byte n;
			out = out[2:];
		}
		out[0:] = a;
		out = out[n:];
	}
	return out;
}

unpackargs(argc: int, reply: array of byte): (array of (int, array of byte), string)
{
	replies := array[argc] of (int, array of byte);
	o := 0;
	for(i := 0; i < len replies; i++){
		o = (o+1)&~1;	# each argument starts at even offset
		a := reply[o:];
		if(len a < 2)
			return (nil, e(Eshort));
		rid := int a[0];
		l: int;
		if(rid & LongWrap){
			if(len a < 6)
				return (nil, e(Eshort));
			l = get4(a[2:]);
			a = a[6:];
			o += 6;
		}else if(rid & ShortWrap){
			if(len a < 4)
				return (nil, e(Eshort));
			l = get2(a[2:]);
			a = a[4:];
			o += 4;
		}else{
			l = int a[1];
			a = a[2:];
			o += 2;
		}
		if(len a < l)
			return (nil, e(Eshort));
		replies[i] = (rid &~ 16rC0, a[0:l]);
		o += l;
	}
	return (replies, nil);
}
