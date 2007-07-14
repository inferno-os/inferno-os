implement Trfs;

include "sys.m";
	sys: Sys;

include "draw.m";

include "styx.m";
	styx: Styx;
	Rmsg, Tmsg: import styx;

Trfs: module
{
	init: fn(nil: ref Draw->Context, nil: list of string);
};

Fid: adt {
	fid:	int;
	isdir:	int;
	aux:	int;
};

Table: adt[T] {
	items: array of list of (int, T);
	nilval: T;

	new: fn(nslots: int, nilval: T): ref Table[T];
	add:	fn(t: self ref Table, id: int, x: T): int;
	del:	fn(t: self ref Table, id: int): T;
	find:	fn(t: self ref Table, id: int): T;
};

NBspace: con 16r00A0;	# Unicode `no-break' space (looks like a faint box in some fonts)
NBspacelen: con 2;		# length of it in utf-8

msize: int;
lock: chan of int;
fids: ref Table[ref Fid];
tfids: ref Table[ref Fid];

init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	styx = load Styx Styx->PATH;
	
	if(len args != 3){
		sys->fprint(sys->fildes(2), "usage: trfs dir mountpoint\n");
		raise "fail:usage";
	}
	dir := hd tl args;
	mntpt := hd tl tl args;
	p := array[2] of ref Sys->FD;
	q := array[2] of ref Sys->FD;
	fids = Table[ref Fid].new(11, nil);
	tfids = Table[ref Fid].new(11, nil);
	lock = chan[1] of int;

	styx->init();
	sys->pipe(p);
	sys->pipe(q);
	if(sys->export(q[0], dir, Sys->EXPASYNC) < 0)
		fatal("can't export " + dir);
	spawn trfsin(p[1], q[1]);
	spawn trfsout(p[1], q[1]);
	if(sys->mount(p[0], nil, mntpt, Sys->MREPL|Sys->MCREATE, nil) < 0)
		fatal("can't mount on " + mntpt);
}

trfsin(cfd, sfd: ref Sys->FD)
{
	while((t:=Tmsg.read(cfd, msize)) != nil){
		pick m := t {
		Clunk or
		Remove =>
			fids.del(m.fid);
		Create =>
			fid := ref Fid(m.fid, 0, 0);
			fids.add(m.fid, fid);
			addtfid(m.tag, fid);
			m.name = tr(m.name, NBspace, ' ');
		Open =>
			fid := ref Fid(m.fid, 0, 0);
			fids.add(m.fid, fid);
			addtfid(m.tag, fid);
		Read =>
			fid := fids.find(m.fid);
			addtfid(m.tag, fid);
			if(fid.isdir){
				m.count /= NBspacelen;	# translated strings might grow by this much
				if(m.offset == big 0)
					fid.aux = 0;
				m.offset -= big fid.aux;
			}
		Walk =>
			for(i:=0; i<len m.names; i++)
				m.names[i] = tr(m.names[i], NBspace, ' ');
		Wstat =>
			m.stat.name = tr(m.stat.name, NBspace, ' ');
		}
		sys->write(sfd, t.pack(), t.packedsize());
	}
}
		
trfsout(cfd, sfd: ref Sys->FD)
{
	b := array[Styx->MAXFDATA] of byte;
	while((r := Rmsg.read(sfd, msize)) != nil){
		pick m := r {
		Version =>
			msize = m.msize;
			if(msize > len b)
				b = array[msize] of byte;	# a bit more than needed but doesn't matter
		Create or
		Open =>
			fid := deltfid(m.tag);
			fid.isdir = m.qid.qtype & Sys->QTDIR;
		Read =>
			fid := deltfid(m.tag);
			if(fid.isdir){
				bs := 0;
				for(n := 0; n < len m.data; ){
					(ds, d) := styx->unpackdir(m.data[n:]);
					if(ds <= 0)
						break;
					d.name = tr(d.name, ' ', NBspace);
					b[bs:] = styx->packdir(d);
					bs += styx->packdirsize(d);
					n += ds;
				}
				fid.aux += bs-n;
				m.data = b[0:bs];
			}
		Stat =>
			m.stat.name = tr(m.stat.name, ' ', NBspace);
		}
		sys->write(cfd, r.pack(), r.packedsize());
	}
}

tr(name: string, c1, c2: int): string
{
	for(i:=0; i<len name; i++)
		if(name[i] == c1)
			name[i] = c2;
	return name;
}

Table[T].new(nslots: int, nilval: T): ref Table[T]
{
	if(nslots == 0)
		nslots = 13;
	return ref Table[T](array[nslots] of list of (int, T), nilval);
}

Table[T].add(t: self ref Table[T], id: int, x: T): int
{
	slot := id % len t.items;
	for(q := t.items[slot]; q != nil; q = tl q)
		if((hd q).t0 == id)
			return 0;
	t.items[slot] = (id, x) :: t.items[slot];
	return 1;
}

Table[T].del(t: self ref Table[T], id: int): T
{
	p: list of (int, T);
	slot := id % len t.items;
	for(q := t.items[slot]; q != nil; q = tl q){
		if((hd q).t0 == id){
			t.items[slot] = join(p, tl q);
			return (hd q).t1;
		}
		p = hd q :: p;
	}
	return t.nilval;
}

Table[T].find(t: self ref Table[T], id: int): T
{
	for(p := t.items[id % len t.items]; p != nil; p = tl p)
		if((hd p).t0 == id)
			return (hd p).t1;
	return t.nilval;
}

join[T](x, y: list of (int, T)): list of (int, T)
{
	for(; x != nil; x = tl x)
		y = hd x :: y;
	return y;
}

addtfid(t: int, fid: ref Fid)
{
	lock <-= 1;
	tfids.add(t, fid);
	<- lock;
}

deltfid(t: int): ref Fid
{
	lock <-= 1;
	r := tfids.del(t);
	<- lock;
	return r;
}

fatal(s: string)
{
	sys->fprint(sys->fildes(2), "trfs: %s: %r\n", s);
	raise "fail:error";
}
