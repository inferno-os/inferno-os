implement Diskm;

include "common.m";

sys : Sys;
acme : Acme;
utils : Utils;

SZSHORT, Block, Blockincr, Astring : import Dat;
error : import utils;

init(mods : ref Dat->Mods)
{
	sys = mods.sys;
	acme = mods.acme;
	utils = mods.utils;
}

blist : ref Block;

tempfile() : ref Sys->FD
{
	buf := sys->sprint("/tmp/X%d.%.4sacme", sys->pctl(0, nil), utils->getuser());
	for(i:='A'; i<='Z'; i++){
		buf[5] = i;
		(ok, nil) := sys->stat(buf);
		if(ok == 0)
			continue;
		fd := sys->create(buf, Sys->ORDWR|Sys->ORCLOSE, 8r600);
		if(fd != nil)
			return fd;
	}
	return nil;
}

Disk.init() : ref Disk
{
	d : ref Disk;

	d = ref Disk;
	d.free = array[Dat->Maxblock/Dat->Blockincr+1] of ref Block;
	d.addr = 0;
	d.fd = tempfile();
	if(d.fd == nil){
		error(sys->sprint("can't create temp file %r"));
		acme->acmeexit("temp create");
	}
	return d;
}

ntosize(n : int) : (int, int)
{
	size : int;

	if (n > Dat->Maxblock)
		error("bad assert in ntosize");
	size = n;
	if(size & (Blockincr-1))
		size += Blockincr - (size & (Blockincr-1));
	# last bucket holds blocks of exactly Maxblock
	return (size * SZSHORT, size/Blockincr);
}

Disk.new(d : self ref Disk, n : int) : ref Block
{
	i, j, size : int;
	b, bl : ref Block;

	(size, i) = ntosize(n);
	b = d.free[i];
	if(b != nil)
		d.free[i] = b.next;
	else{
		# allocate in chunks to reduce malloc overhead
		if(blist == nil){
			blist = ref Block;
			bl = blist;
			for(j=0; j<100-1; j++) {
				bl.next = ref Block;
				bl = bl.next;
			}
		}
		b = blist;
		blist = b.next;
		b.addr = d.addr;
		d.addr += size;
	}
	b.n = n;
	return b;
}

Disk.release(d : self ref Disk, b : ref Block)
{
	(nil, i) := ntosize(b.n);
	b.next = d.free[i];
	d.free[i] = b;
}

Disk.write(d : self ref Disk, bp : ref Block, r : string, n : int) : ref Block
{
	size, nsize, i : int;
	b : ref Block;
	ab : array of byte;

	b = bp;
	(size, i) = ntosize(b.n);
	(nsize, i) = ntosize(n);
	if(size != nsize){
		d.release(b);
		b = d.new(n);
	}
	if(sys->seek(d.fd, big b.addr, 0) < big 0)
		error("seek error in temp file");
	ab = utils->stob(r, n);
	if(sys->write(d.fd, ab, len ab) != len ab)
		error("write error to temp file");
	ab = nil;
	b.n = n;
	return b;
}

Disk.read(d : self ref Disk, b : ref Block, r : ref Astring, n : int)
{
	ab : array of byte;

	if (n > b.n)
		error("bad assert in Disk.read");
	(nil, nil) := ntosize(b.n);
	if(sys->seek(d.fd, big b.addr, 0) < big 0)
		error("seek error in temp file");
	ab = array[n*SZSHORT] of byte;
	if(sys->read(d.fd, ab, len ab) != len ab)
		error("read error from temp file");
	utils->btos(ab, r);
	ab = nil;
}
