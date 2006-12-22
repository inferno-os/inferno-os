implement Palmdb;

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

include "palm.m";
	palm: Palm;
	DBInfo, Record, Resource, get2, get3, get4, put2, put3, put4, gets, puts: import palm;
	filename, dbname: import palm;

Entry: adt {
	id:	int;	# resource: id; record: unique ID
	offset:	int;
	size:	int;
	name:	int;	# resource entry only
	attr:	int;	# record entry only
};

Ofile: adt {
	fname:	string;
	f:	ref Iobuf;
	mode:	int;
	info:	ref DBInfo;
	appinfo:	array of byte;
	sortinfo:	array of int;
	uidseed:	int;
	entries:	array of ref Entry;
};

files:	array of ref Ofile;

Dbhdrlen: con 72+6;
Datahdrsize: con 4+1+3;
Resourcehdrsize: con 4+2+4;

# Exact value of "Jan 1, 1970 0:00:00 GMT" - "Jan 1, 1904 0:00:00 GMT"
Epochdelta: con 2082844800;
tzoff := 0;

init(m: Palm): string
{
	sys = load Sys Sys->PATH;
	bufio = load Bufio Bufio->PATH;
	daytime = load Daytime Daytime->PATH;
	if(bufio == nil || daytime == nil)
		return "can't load required module";
	palm = m;
	tzoff = daytime->local(0).tzoff;
	return nil;
}

Eshort: con "file format error: too small";

DB.open(name: string, mode: int): (ref DB, string)
{
	if(mode != Sys->OREAD)
		return (nil, "invalid mode");
	fd := sys->open(name, mode);
	if(fd == nil)
		return (nil, sys->sprint("%r"));
	(ok, d) := sys->fstat(fd);
	if(ok < 0)
		return (nil, sys->sprint("%r"));
	length := int d.length;
	if(length == 0)
		return (nil, "empty file");
	(pf, ofile, fx) := mkpfile(name, mode);

	f := bufio->fopen(fd, mode);	# automatically closed if open fails

	p := array[Dbhdrlen] of byte;
	if(f.read(p, Dbhdrlen) != Dbhdrlen)
		return (nil, "invalid file header: too short");

	ip := ofile.info;
	ip.name = gets(p[0:32]);
	ip.attr = get2(p[32:]);
	ip.version = get2(p[34:]);
	ip.ctime = pilot2epoch(get4(p[36:]));
	ip.mtime = pilot2epoch(get4(p[40:]));
	ip.btime = pilot2epoch(get4(p[44:]));
	ip.modno = get4(p[48:]);
	appinfo := get4(p[52:]);
	sortinfo := get4(p[56:]);
	if(appinfo < 0 || sortinfo < 0 || (appinfo|sortinfo)&1)
		return (nil, "invalid header: bad offset");
	ip.dtype = xs(get4(p[60:]));
	ip.creator = xs(get4(p[64:]));
	ofile.uidseed = ip.uidseed = get4(p[68:]);

	if(get4(p[72:]) != 0)
		return (nil, "chained headers not supported");	# Palm says to reject such files
	nrec := get2(p[76:]);
	if(nrec < 0)
		return (nil, sys->sprint("invalid header: bad record count: %d", nrec));

	esize := Datahdrsize;
	if(ip.attr & Palm->Fresource)
		esize = Resourcehdrsize;
	
	dataoffset := length;
	ofile.entries = array[nrec] of ref Entry;
	if(nrec > 0){
		laste: ref Entry;
		buf := array[esize] of byte;
		for(i := 0; i < nrec; i++){
			if(f.read(buf, len buf) != len buf)
				return (nil, Eshort);
			e := ref Entry;
			if(ip.attr & Palm->Fresource){
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
			ofile.entries[i] = e;
		}
		if(laste != nil)
			laste.size = length - laste.offset;
		dataoffset = ofile.entries[0].offset;
	}else{
		if(f.read(p, 2) != 2)
			return (nil, Eshort);	# discard placeholder bytes
	}

	n := 0;
	if(appinfo > 0){
		n = appinfo - int f.offset();
		while(--n >= 0)
			f.getb();
		if(sortinfo)
			n = sortinfo - appinfo;
		else
			n = dataoffset - appinfo;
		ofile.appinfo = array[n] of byte;
		if(f.read(ofile.appinfo, n) != n)
			return (nil, Eshort);
	}
	if(sortinfo > 0){
		n = sortinfo - int f.offset();
		while(--n >= 0)
			f.getb();
		n = (dataoffset-sortinfo)/2;
		ofile.sortinfo = array[n] of int;
		tmp := array[2*n] of byte;
		if(f.read(tmp, len tmp) != len tmp)
			return (nil, Eshort);
		for(i := 0; i < n; i++)
			ofile.sortinfo[i] = get2(tmp[2*i:]);
	}
	ofile.f = f;	# safe to save open file reference
	files[fx] = ofile;
	return (pf, nil);
}

DB.close(db: self ref DB): string
{
	ofile := files[db.x];
	if(ofile.f != nil){
		ofile.f.close();
		ofile.f = nil;
	}
	files[db.x] = nil;
	return nil;
}

DB.stat(db: self ref DB): ref DBInfo
{
	return ref *files[db.x].info;
}

DB.create(name: string, mode: int, perm: int, info: ref DBInfo): (ref DB, string)
{
	return (nil, "DB.create not implemented");
}

DB.wstat(db: self ref DB, ip: ref DBInfo, flags: int)
{
	raise "DB.wstat not implemented";
}

#DB.wstat(db: self ref DB, ip: ref DBInfo): string
#{
#	ofile := files[db.x];
#	if(ofile.mode != Sys->OWRITE)
#		return "not open for writing";
#	if((ip.attr & Palm->Fresource) != (ofile.info.attr & Palm->Fresource))
#		return "cannot change file type";
#	# copy only a subset
#	ofile.info.name = ip.name;
#	ofile.info.attr = ip.attr;
#	ofile.info.version = ip.version;
#	ofile.info.ctime = ip.ctime;
#	ofile.info.mtime = ip.mtime;
#	ofile.info.btime = ip.btime;
#	ofile.info.modno = ip.modno;
#	ofile.info.dtype = ip.dtype;
#	ofile.info.creator = ip.creator;
#	return nil;
#}

DB.rdappinfo(db: self ref DB): (array of byte, string)
{
	return (files[db.x].appinfo, nil);
}

DB.wrappinfo(db: self ref DB, data: array of byte): string
{
	ofile := files[db.x];
	if(ofile.mode != Sys->OWRITE)
		return "not open for writing";
	ofile.appinfo = array[len data] of byte;
	ofile.appinfo[0:] = data;
	return nil;
}

DB.rdsortinfo(db: self ref DB): (array of int, string)
{
	return (files[db.x].sortinfo, nil);
}

DB.wrsortinfo(db: self ref DB, sort: array of int): string
{
	ofile := files[db.x];
	if(ofile.mode != Sys->OWRITE)
		return "not open for writing";
	ofile.sortinfo = array[len sort] of int;
	ofile.sortinfo[0:] = sort;
	return nil;
}

DB.readidlist(db: self ref DB, nil: int): array of int
{
	ent := files[db.x].entries;
	a := array[len ent] of int;
	for(i := 0; i < len a; i++)
		a[i] = ent[i].id;
	return a;
}

DB.nentries(db: self ref DB): int
{
	return len files[db.x].entries;
}

DB.resetsyncflags(db: self ref DB): string
{
	raise "DB.resetsyncflags not implemented";
}

DB.records(db: self ref DB): ref PDB
{
	if(db == nil || db.attr & Palm->Fresource)
		return nil;
	return ref PDB(db);
}

DB.resources(db: self ref DB): ref PRC
{
	if(db == nil || (db.attr & Palm->Fresource) == 0)
		return nil;
	return ref PRC(db);
}

PDB.read(pdb: self ref PDB, i: int): ref Record
{
	ofile := files[pdb.db.x];
	if(i < 0 || i >= len ofile.entries){
		if(i == len ofile.entries)
			return nil; # treat as end-of-file
		#return "index out of range";
		return nil;
	}
	e := ofile.entries[i];
	nb := e.size;
	r := ref Record(e.id, e.attr & 16rF0, e.attr & 16r0F, array[nb] of byte);
	ofile.f.seek(big e.offset, 0);
	if(ofile.f.read(r.data, nb) != nb)
		return nil;
	return r;
}

PDB.readid(pdb: self ref PDB, id: int): (ref Record, int)
{
	ofile := files[pdb.db.x];
	ent := ofile.entries;
	for(i := 0; i < len ent; i++)
		if((e := ent[i]).id == id){
			nb := e.size;
			r := ref Record(e.id, e.attr & 16rF0, e.attr & 16r0F, array[e.size] of byte);
			ofile.f.seek(big e.offset, 0);
			if(ofile.f.read(r.data, nb) != nb)
				return (nil, -1);
			return (r, id);
		}
	sys->werrstr("ID not found");
	return (nil, -1);
}

PDB.resetnext(db: self ref PDB): int
{
	raise "PDB.resetnext not implemented";
}

PDB.readnextmod(db: self ref PDB): (ref Record, int)
{
	raise "PDB.readnextmod not implemented";
}

PDB.write(db: self ref PDB, r: ref Record): string
{
	return "PDB.write not implemented";
}

PDB.truncate(db: self ref PDB): string
{
	return "PDB.truncate not implemented";
}

PDB.delete(db: self ref PDB, id: int): string
{
	return "PDB.delete not implemented";
}

PDB.deletecat(db: self ref PDB, cat: int): string
{
	return "PDB.deletecat not implemented";
}

PDB.purge(db: self ref PDB): string
{
	return "PDB.purge not implemented";
}

PDB.movecat(db: self ref PDB, old: int, new: int): string
{
	return "PDB.movecat not implemented";
}

PRC.read(db: self ref PRC, index: int): ref Resource
{
	return nil;
}

PRC.readtype(db: self ref PRC, name: int, id: int): (ref Resource, int)
{
	return (nil, -1);
}

PRC.write(db: self ref PRC, r: ref Resource): string
{
	return "PRC.write not implemented";
}

PRC.truncate(db: self ref PRC): string
{
	return "PRC.truncate not implemented";
}

PRC.delete(db: self ref PRC, name: int, id: int): string
{
	return "PRC.delete not implemented";
}

#
# internal function to extend entry list if necessary, and return a
# pointer to the next available slot
#
entryensure(db: ref DB, i: int): ref Entry
{
	ofile := files[db.x];
	if(i < len ofile.entries)
		return ofile.entries[i];
	e := ref Entry(0, -1, 0, 0, 0);
	n := len ofile.entries;
	if(n == 0)
		n = 64;
	else
		n = (i+63) & ~63;
	a := array[n] of ref Entry;
	a[0:] = ofile.entries;
	a[i] = e;
	ofile.entries = a;
	return e;
}

writefilehdr(db: ref DB, mode: int, perm: int): string
{
	ofile := files[db.x];
	if(len ofile.entries >= 64*1024)
		return "too many records for Palm file";	# is there a way to extend it?

	if((f := bufio->create(ofile.fname, mode, perm)) == nil)
		return sys->sprint("%r");

	ip := ofile.info;

	esize := Datahdrsize;
	if(ip.attr & Palm->Fresource)
		esize = Resourcehdrsize;
	offset := Dbhdrlen + esize*len ofile.entries + 2;
	offset += 2;	# placeholder bytes or gap bytes
	appinfo := 0;
	if(len ofile.appinfo > 0){
		appinfo = offset;
		offset += len ofile.appinfo;
	}
	sortinfo := 0;
	if(len ofile.sortinfo > 0){
		sortinfo = offset;
		offset += 2*len ofile.sortinfo;	# 2-byte entries
	}
	p := array[Dbhdrlen] of byte;	# bigger than any entry as well
	puts(p[0:32], ip.name);
	put2(p[32:], ip.attr);
	put2(p[34:], ip.version);
	put4(p[36:], epoch2pilot(ip.ctime));
	put4(p[40:], epoch2pilot(ip.mtime));
	put4(p[44:], epoch2pilot(ip.btime));
	put4(p[48:], ip.modno);
	put4(p[52:], appinfo);
	put4(p[56:], sortinfo);
	put4(p[60:], sx(ip.dtype));
	put4(p[64:], sx(ip.creator));
	put4(p[68:], ofile.uidseed);
	put4(p[72:], 0);		# next record list ID
	put2(p[76:], len ofile.entries);

	if(f.write(p, Dbhdrlen) != Dbhdrlen)
		return ewrite(f);
	if(len ofile.entries > 0){
		for(i := 0; i < len ofile.entries; i++) {
			e := ofile.entries[i];
			e.offset = offset;
			if(ip.attr & Palm->Fresource) {
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

	if(appinfo != 0){
		if(f.write(ofile.appinfo, len ofile.appinfo) != len ofile.appinfo)
			return ewrite(f);
	}

	if(sortinfo != 0){
		tmp := array[2*len ofile.sortinfo] of byte;
		for(i := 0; i < len ofile.sortinfo; i++)
			put2(tmp[2*i:], ofile.sortinfo[i]);
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

mkpfile(name: string, mode: int): (ref DB, ref Ofile, int)
{
	ofile := ref Ofile(name, nil, mode, DBInfo.new(name, 0, nil, 0, nil),
		array[0] of byte, array[0] of int, 0, nil);
	for(x := 0; x < len files; x++)
		if(files[x] == nil)
			return (ref DB(x, mode, 0), ofile, x);
	a := array[x] of ref Ofile;
	a[0:] = files;
	files = a;
	return (ref DB(x, mode, 0), ofile, x);
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
