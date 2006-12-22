implement Dbm;

# Copyright © Caldera International Inc.  2001-2002.  All rights reserved.
# Limbo transliteration (with amendment) Copyright © 2004 Vita Nuova Holdings Limited.

include "sys.m";
	sys: Sys;
	OREAD, OWRITE, ORDWR: import Sys;

include "dbm.m";

BYTESIZ: con 8;	# bits
SHORTSIZ: con 2;	# bytes

PBLKSIZ: con 512;
DBLKSIZ: con 8192;	# was 4096

init()
{
	sys = load Sys Sys->PATH;
}

Dbf.create(file: string, mode: int): ref Dbf
{
	pf := sys->create(file+".pag", ORDWR, mode);
	if(pf == nil)
		return nil;
	df := sys->create(file+".dir", ORDWR, mode);
	if(df == nil)
		return nil;
	return alloc(pf, df, ORDWR);
}

Dbf.open(file: string, flags: int): ref Dbf
{
	if((flags & 3) == OWRITE)
		flags = (flags & ~3) | ORDWR;
	pf := sys->open(file+".pag", flags);
	if(pf == nil)
		return nil;
	df := sys->open(file+".dir", flags);
	if(df == nil)
		return nil;
	return alloc(pf, df, flags);
}

alloc(pf: ref Sys->FD, df: ref Sys->FD, flags: int): ref Dbf
{
	db := ref Dbf;
	db.pagf = pf;
	db.dirf = df;
	db.flags = flags & 3;
	db.maxbno = 0;
	db.bitno = 0;
	db.hmask = 0;
	db.blkno = 0;
	db.pagbno = -1;
	db.pagbuf = array[PBLKSIZ] of byte;
	db.dirbno = -1;
	db.dirbuf = array[DBLKSIZ] of byte;
	(ok, d) := sys->fstat(db.dirf);
	if(ok < 0)
		d.length = big 0;
	db.maxbno = int (d.length*big BYTESIZ - big 1);
	return db;
}

Dbf.flush(db: self ref Dbf)
{
	db.pagbno = db.dirbno = -1;
}

Dbf.isrdonly(db: self ref Dbf): int
{
	return db.flags == OREAD;
}

Dbf.fetch(db: self ref Dbf, key: Datum): Datum
{
	access(db, calchash(key));
	for(i:=0;; i+=2){
		item := makdatum(db.pagbuf, i);
		if(item == nil)
			return item;
		if(cmpdatum(key, item) == 0){
			item = makdatum(db.pagbuf, i+1);
			if(item == nil){
				sys->fprint(sys->fildes(2), "dbm: items not in pairs\n");
				raise "dbm: items not in pairs";
			}
			return item;
		}
	}
}

Dbf.delete(db: self ref Dbf, key: Datum): int
{
	if(db.isrdonly())
		return -1;
	access(db, calchash(key));
	for(i:=0;; i+=2){
		item := makdatum(db.pagbuf, i);
		if(item == nil)
			return -1;
		if(cmpdatum(key, item) == 0){
			delitem(db.pagbuf, i);
			delitem(db.pagbuf, i);
			break;
		}
	}
	sys->seek(db.pagf, big db.blkno*big PBLKSIZ, 0);
	write(db.pagf, db.pagbuf, PBLKSIZ);
	db.pagbno = db.blkno;
	return 0;
}

Dbf.store(db: self ref Dbf, key: Datum, dat: Datum, replace: int): int
{
	if(db.isrdonly())
		return -1;
	for(;;){
		access(db, calchash(key));
		for(i:=0;; i+=2){
			item := makdatum(db.pagbuf, i);
			if(item == nil)
				break;
			if(cmpdatum(key, item) == 0){
				if(!replace)
					return 1;
				delitem(db.pagbuf, i);
				delitem(db.pagbuf, i);
				break;
			}
		}
		i = additem(db.pagbuf, key);
		if(i >= 0){
			if(additem(db.pagbuf, dat) >= 0)
				break;
			delitem(db.pagbuf, i);
		}
		if(!split(db, key, dat))
			return -1;
	}
	sys->seek(db.pagf, big db.blkno*big PBLKSIZ, 0);
	write(db.pagf, db.pagbuf, PBLKSIZ);
	db.pagbno = db.blkno;
	return 0;
}

split(db: ref Dbf, key: Datum, dat: Datum): int
{
	if(len key+len dat+3*SHORTSIZ >= PBLKSIZ)
		return 0;
	ovfbuf := array[PBLKSIZ] of {* => byte 0};
	for(i:=0;;){
		item := makdatum(db.pagbuf, i);
		if(item == nil)
			break;
		if(calchash(item) & (db.hmask+1)){
			additem(ovfbuf, item);
			delitem(db.pagbuf, i);
			item = makdatum(db.pagbuf, i);
			if(item == nil){
				sys->fprint(sys->fildes(2), "dbm: split not paired\n");
				raise "dbm: split not paired";
				#break;
			}
			additem(ovfbuf, item);
			delitem(db.pagbuf, i);
			continue;
		}
		i += 2;
	}
	sys->seek(db.pagf, big db.blkno*big PBLKSIZ, 0);
	write(db.pagf, db.pagbuf, PBLKSIZ);
	db.pagbno = db.blkno;
	sys->seek(db.pagf, (big db.blkno+big db.hmask+big 1)*big PBLKSIZ, 0);
	write(db.pagf, ovfbuf, PBLKSIZ);
	setbit(db);
	return 1;
}

Dbf.firstkey(db: self ref Dbf): Datum
{
	return copy(firsthash(db, 0));
}

Dbf.nextkey(db: self ref Dbf, key: Datum): Datum
{
	hash := calchash(key);
	access(db, hash);
	item, bitem: Datum;
	for(i:=0;; i+=2){
		item = makdatum(db.pagbuf, i);
		if(item == nil)
			break;
		if(cmpdatum(key, item) <= 0)
			continue;
		if(bitem == nil || cmpdatum(bitem, item) < 0)
			bitem = item;
	}
	if(bitem != nil)
		return copy(bitem);
	hash = hashinc(db, hash);
	if(hash == 0)
		return copy(item);
	return copy(firsthash(db, hash));
}

firsthash(db: ref Dbf, hash: int): Datum
{
	for(;;){
		access(db, hash);
		bitem := makdatum(db.pagbuf, 0);
		item: Datum;
		for(i:=2;; i+=2){
			item = makdatum(db.pagbuf, i);
			if(item == nil)
				break;
			if(cmpdatum(bitem, item) < 0)
				bitem = item;
		}
		if(bitem != nil)
			return bitem;
		hash = hashinc(db, hash);
		if(hash == 0)
			return item;
	}
}

access(db: ref Dbf, hash: int)
{
	for(db.hmask=0;; db.hmask=(db.hmask<<1)+1){
		db.blkno = hash & db.hmask;
		db.bitno = db.blkno + db.hmask;
		if(getbit(db) == 0)
			break;
	}
	if(db.blkno != db.pagbno){
		sys->seek(db.pagf, big db.blkno * big PBLKSIZ, 0);
		read(db.pagf, db.pagbuf, PBLKSIZ);
		chkblk(db.pagbuf);
		db.pagbno = db.blkno;
	}
}

getbit(db: ref Dbf): int
{
	if(db.bitno > db.maxbno)
		return 0;
	n := db.bitno % BYTESIZ;
	bn := db.bitno / BYTESIZ;
	i := bn % DBLKSIZ;
	b := bn / DBLKSIZ;
	if(b != db.dirbno){
		sys->seek(db.dirf, big b * big DBLKSIZ, 0);
		read(db.dirf, db.dirbuf, DBLKSIZ);
		db.dirbno = b;
	}
	if(int db.dirbuf[i] & (1<<n))
		return 1;
	return 0;
}

setbit(db: ref Dbf)
{
	if(db.bitno > db.maxbno){
		db.maxbno = db.bitno;
		getbit(db);
	}
	n := db.bitno % BYTESIZ;
	bn := db.bitno / BYTESIZ;
	i := bn % DBLKSIZ;
	b := bn / DBLKSIZ;
	db.dirbuf[i] |= byte (1<<n);
	sys->seek(db.dirf, big b * big DBLKSIZ, 0);
	write(db.dirf, db.dirbuf, DBLKSIZ);
	db.dirbno = b;
}

makdatum(buf: array of byte, n: int): Datum
{
	ne := GETS(buf, 0);
	if(n < 0 || n >= ne)
		return nil;
	t := PBLKSIZ;
	if(n > 0)
		t = GETS(buf, n+1-1);
	v := GETS(buf, n+1);
	return buf[v: t];	# size is t-v
}

cmpdatum(d1: Datum, d2: Datum): int
{
	n := len d1;
	if(n != len d2)
		return n - len d2;
	if(n == 0)
		return 0;
	for(i := 0; i < len d1; i++)
		if(d1[i] != d2[i])
			return int d1[i] - int d2[i];
	return 0;
}

copy(d: Datum): Datum
{
	if(d == nil)
		return nil;
	a := array[len d] of byte;
	a[0:] = d;
	return a;
}

# ken's
#
#	055,043,036,054,063,014,004,005,
#	010,064,077,000,035,027,025,071,
#

hitab := array[16] of {
         61, 57, 53, 49, 45, 41, 37, 33,
	29, 25, 21, 17, 13,  9,  5,  1,
};

hltab := array[64] of {
	8r6100151277,8r6106161736,8r6452611562,8r5001724107,
	8r2614772546,8r4120731531,8r4665262210,8r7347467531,
	8r6735253126,8r6042345173,8r3072226605,8r1464164730,
	8r3247435524,8r7652510057,8r1546775256,8r5714532133,
	8r6173260402,8r7517101630,8r2431460343,8r1743245566,
	8r0261675137,8r2433103631,8r3421772437,8r4447707466,
	8r4435620103,8r3757017115,8r3641531772,8r6767633246,
	8r2673230344,8r0260612216,8r4133454451,8r0615531516,
	8r6137717526,8r2574116560,8r2304023373,8r7061702261,
	8r5153031405,8r5322056705,8r7401116734,8r6552375715,
	8r6165233473,8r5311063631,8r1212221723,8r1052267235,
	8r6000615237,8r1075222665,8r6330216006,8r4402355630,
	8r1451177262,8r2000133436,8r6025467062,8r7121076461,
	8r3123433522,8r1010635225,8r1716177066,8r5161746527,
	8r1736635071,8r6243505026,8r3637211610,8r1756474365,
	8r4723077174,8r3642763134,8r5750130273,8r3655541561,
};

hashinc(db: ref Dbf, hash: int): int
{
	hash &= db.hmask;
	bit := db.hmask+1;
	for(;;){
		bit >>= 1;
		if(bit == 0)
			return 0;
		if((hash&bit) == 0)
			return hash|bit;
		hash &= ~bit;
	}
}

calchash(item: Datum): int
{
	hashl := 0;
	hashi := 0;
	for(i:=0; i<len item; i++){
		f := int item[i];
		for(j:=0; j<BYTESIZ; j+=4){
			hashi += hitab[f&16rF];
			hashl += hltab[hashi&16r3F];
			f >>= 4;
		}
	}
	return hashl;
}

delitem(buf: array of byte, n: int)
{
	ne := GETS(buf, 0);
	if(n < 0 || n >= ne){
		sys->fprint(sys->fildes(2), "dbm: bad delitem\n");
		raise "dbm: bad delitem";
	}
	i1 := GETS(buf, n+1);
	i2 := PBLKSIZ;
	if(n > 0)
		i2 = GETS(buf, n+1-1);
	i3 := GETS(buf, ne+1-1);
	if(i2 > i1)
		while(i1 > i3){
			i1--;
			i2--;
			buf[i2] = buf[i1];
			buf[i1] = byte 0;
		}
	i2 -= i1;
	for(i1=n+1; i1<ne; i1++)
		PUTS(buf, i1+1-1, GETS(buf, i1+1) + i2);
	PUTS(buf, 0, ne-1);
	PUTS(buf, ne, 0);
}

additem(buf: array of byte, item: Datum): int
{
	i1 := PBLKSIZ;
	ne := GETS(buf, 0);
	if(ne > 0)
		i1 = GETS(buf, ne+1-1);
	i1 -= len item;
	i2 := (ne+2) * SHORTSIZ;
	if(i1 <= i2)
		return -1;
	PUTS(buf, ne+1, i1);
	buf[i1:] = item;
	PUTS(buf, 0, ne+1);
	return ne;
}

chkblk(buf: array of byte)
{
	t := PBLKSIZ;
	ne := GETS(buf, 0);
	for(i:=0; i<ne; i++){
		v := GETS(buf, i+1);
		if(v > t)
			badblk();
		t = v;
	}
	if(t < (ne+1)*SHORTSIZ)
		badblk();
}

read(fd: ref Sys->FD, buf: array of byte, n: int)
{
	nr := sys->read(fd, buf, n);
	if(nr == 0){
		for(i := 0; i < len buf; i++)
			buf[i] = byte 0;
	}else if(nr != n)
		raise "dbm: read error: "+sys->sprint("%r");
}

write(fd: ref Sys->FD, buf: array of byte, n: int)
{
	if(sys->write(fd, buf, n) != n)
		raise "dbm: write error: "+sys->sprint("%r");
}

badblk()
{
	sys->fprint(sys->fildes(2), "dbm: bad block\n");
	raise "dbm: bad block";
}

GETS(buf: array of byte, sh: int): int
{
	sh *= SHORTSIZ;
	return (int buf[sh]<<8) | int buf[sh+1];
}

PUTS(buf: array of byte, sh: int, v: int)
{
	sh *= SHORTSIZ;
	buf[sh] = byte (v>>8);
	buf[sh+1] = byte v;
}
