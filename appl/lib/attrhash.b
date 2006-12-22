implement Attrhash, Attrindex;

include "sys.m";
	sys: Sys;

include "bufio.m";
	bufio: Bufio;

include "attrdb.m";

init(): string
{
	sys = load Sys Sys->PATH;
	bufio = load Bufio Bufio->PATH;
	if(bufio == nil)
		return sys->sprint("can't load %s: %r", Bufio->PATH);
	return nil;
}

attrindex(): Attrindex
{
	return load Attrindex "$self";
}

Index.open(dbf: Attrdb->Dbf, attr: string, fd: ref Sys->FD): ref Index
{
	(ok, d) := sys->fstat(fd);
	if(ok < 0 || dbf.dir == nil || dbf.dir.mtime > d.mtime)
		return nil;
	length := int d.length;
	if(length < NDBHLEN)
		return nil;
	buf := array[length] of byte;
	if(sys->read(fd, buf, len buf) != len buf)
		return nil;
	mtime := get4(buf);
	if(mtime != dbf.dir.mtime)
		return nil;
	size := get3(buf[4:]);
	return ref Index(fd, attr, d.mtime, size, buf[8:]);
}

#Index.firstoff(ind: self ref Index, val: string): ref Attrdb->Dbptr
#{
#	o := hash(val, ind.size)*NDBPLEN;
#	p := get3(tab[o:]);
#	if(p == NDBNAP)
#		return nil;
#	if((p & NDBCHAIN) == 0)
#		return ref Attrdb.Direct(p);
#	p &= ~NDBCHAIN;
#	return ref Attrdb.Hash(get3(tab[p:]), get3(tab[p+NDBPLEN:]));
#}

#Index.nextoff(ind: self ref Index, val: string, ptr: ref Attrdb->Dbptr): (int, ref Attrdb->Dbptr)
#{
#	pick p := ptr {
#	Hash =>
#		o := get3(tab[p.current:]);
#		if((o & NDBCHAIN) == 0)
#			return (o, ref Attrdb.Direct(p.next));
#		o &= ~NDBCHAIN;
#		o1 := get3(tab[o:]);
#		o2 := get3(tab[o+NDBPLEN:]);
#		

#	o := hash(val, ind.size)*NDBPLEN;
#	p := get3(tab[o:]);
#	if(p == NDBNAP)
#		return nil;
#	for(; (p := get3(tab[o:])) != NDBNAP; o = p & ~NDBCHAIN)
#		if((p & NDBCHAIN) == 0){
#			put3(tab[o:], chain | NDBCHAIN);
#			put3(tab[chain:], p);
#			put3(tab[chain+NDBPLEN:], offset);
#			return chain+2*NDBPLEN;
#		}
#	return nil;
#}

#
# this must be the same hash function used by Plan 9's ndb
#
hash(s: string, hlen: int): int
{
	h := 0;
	for(i := 0; i < len s; i++)
		if(s[i] >= 16r80){
			# could optimise by calculating utf ourselves
			a := array of byte s;
			for(i=0; i<len a; i++)
				h = (h*13) + int a[i] - 'a';
			break;
		}else
			h = (h*13) + s[i]-'a';
	if(h < 0)
		return int((big h & big 16rFFFFFFFF)%big hlen);
	return h%hlen;
}

get3(a: array of byte): int
{
	return (int a[2]<<16) | (int a[1]<<8) | int a[0];
}

get4(a: array of byte): int
{
	return (int a[3]<<24) | (int a[2]<<16) | (int a[1]<<8) | int a[0];
}
