implement Mkhash;

#
# for compatibility, this is closely modelled on Plan 9's ndb/mkhash
#

include "sys.m";
	sys: Sys;

include "draw.m";

include "bufio.m";
include "attrdb.m";
	attrdb: Attrdb;
	Db, Dbf, Dbentry, Tuples, Attr: import attrdb;
	attrhash: Attrhash;
	NDBPLEN, NDBHLEN, NDBCHAIN, NDBNAP: import Attrhash;

Mkhash: module
{
	init:	fn(nil: ref Draw->Context, nil: list of string);
};

init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	attrdb = load Attrdb Attrdb->PATH;
	if(attrdb == nil)
		error(sys->sprint("can't load %s: %r", Attrdb->PATH));
	attrdb->init();
	attrhash = load Attrhash Attrhash->PATH;
	if(attrhash == nil)
		error(sys->sprint("can't load %s: %r", Attrhash->PATH));

	if(len args != 3)
		error("usage: mkhash file attr");
	args = tl args;
	dbname := hd args;
	args = tl args;
	attr := hd args;
	dbf := Dbf.open(dbname);
	if(dbf == nil)
		error(sys->sprint("can't open %s: %r", dbname));
	offset := 0;
	n := 0;
	for(;;){
		(e, nil, next) := dbf.readentry(offset, nil, nil, 0);
		if(e == nil)
			break;
		m := len e.find(attr);
		if(0 && m != 0)
			sys->fprint(sys->fildes(2), "%ud [%d]\n", offset, m);
		n += m;
		offset = next;
	}
	hlen := 2*n+1;
	chains := n*2*NDBPLEN;
	file := array[NDBHLEN + hlen*NDBPLEN + chains] of byte;
	tab := file[NDBHLEN:];
	for(i:=0; i<len tab; i+=NDBPLEN)
		put3(tab[i:], NDBNAP);
	offset = 0;
	chain := hlen*NDBPLEN;
	for(;;){
		(e, nil, next) := dbf.readentry(offset, nil, nil, 0);
		if(e == nil)
			break;
		for(l := e.find(attr); l != nil; l = tl l)
			for((nil, al) := hd l; al != nil; al = tl al)
				chain = enter(tab, hd al, hlen, chain, offset);
		offset = next;
	}
	hashfile := dbname+"."+attr;
	hfd := sys->create(hashfile, Sys->OWRITE, 8r666);
	if(hfd == nil)
		error(sys->sprint("can't create %s: %r", hashfile));
	mtime := 0;
	if(dbf.dir != nil)
		mtime = dbf.dir.mtime;
	put4(file, mtime);
	put4(file[4:], hlen);
	if(sys->write(hfd, file, NDBHLEN+chain) != NDBHLEN+chain)
		error(sys->sprint("error writing %s: %r", hashfile));
}

error(s: string)
{
	sys->fprint(sys->fildes(2), "mkhash: %s\n", s);
	raise "fail:error";
}

enter(tab: array of byte, a: ref Attr, hlen: int, chain: int, offset: int): int
{
	o := attrhash->hash(a.val, hlen)*NDBPLEN;
	for(; (p := attrhash->get3(tab[o:])) != NDBNAP; o = p & ~NDBCHAIN)
		if((p & NDBCHAIN) == 0){
			put3(tab[o:], chain | NDBCHAIN);
			put3(tab[chain:], p);
			put3(tab[chain+NDBPLEN:], offset);
			return chain+2*NDBPLEN;
		}
	put3(tab[o:], offset);
	return chain;
}

put3(a: array of byte, v: int)
{
	a[0] = byte v;
	a[1] = byte (v>>8);
	a[2] = byte (v>>16);
}

put4(a: array of byte, v: int)
{
	a[0] = byte v;
	a[1] = byte (v>>8);
	a[2] = byte (v>>16);
	a[3] = byte (v>>24);
}
