implement Diskblocks;

#
# adapted from Acme's disk.b
#

include "sys.m";
	sys: Sys;

include "diskblocks.m";

init()
{
	sys = load Sys Sys->PATH;
}

tempfile(): ref Sys->FD
{
	user := "inferno";
	fd := sys->open("/dev/user", Sys->OREAD);
	if(fd != nil){
		b := array[Sys->NAMEMAX] of byte;
		n := sys->read(fd, b, len b);
		if(n > 0)
			user = string b[0:n];
	}
	fd = nil;
	buf := sys->sprint("/tmp/X%d.%.4sblks", sys->pctl(0, nil), user);
	for(i:='A'; i<='Z'; i++){
		buf[5] = i;
		if(sys->stat(buf).t0 == 0)
			continue;
		fd = sys->create(buf, Sys->ORDWR|Sys->ORCLOSE|Sys->OEXCL, 8r600);
		if(fd != nil)
			return fd;
	}
	return nil;
}

Disk.init(fd: ref Sys->FD, gran: int, maxblock: int): ref Disk
{
	d := ref Disk;
	if(gran == 0 || maxblock%gran != 0)
		return nil;
	d.maxblock = maxblock;
	d.gran = gran;
	d.free = array[maxblock/gran+1] of list of ref Block;
	d.addr = big 0;
	d.fd = fd;
	d.lock = chan[1] of int;
	return d;
}

ntosize(d: ref Disk, n: int): (int, int)
{
	if (n > d.maxblock)
		return (-1, -1);
	size := n;
	if((size % d.gran) != 0)
		size += d.gran - size%d.gran;
	# last bucket holds blocks of exactly d.maxblock
	return (size, size/d.gran);
}

Disk.new(d: self ref Disk, n: int): ref Block
{
	(size, i) := ntosize(d, n);
	if(i < 0){
		sys->werrstr("illegal Disk allocation");
		return nil;
	}
	b: ref Block;
	d.lock <-= 1;
	if(d.free[i] != nil){
		b = hd d.free[i];
		d.free[i] = tl d.free[i];
	}else{
		b = ref Block(d.addr, 0);
		d.addr += big size;
	}
	<-d.lock;
	b.n = n;
	return b;
}

Disk.release(d: self ref Disk, b: ref Block)
{
	(nil, i) := ntosize(d, b.n);
	d.lock <-= 1;
	d.free[i] = b :: d.free[i];
	<-d.lock;
}

Disk.write(d: self ref Disk, b: ref Block, a: array of byte, n: int): ref Block
{
	if(b != nil){
		(size, nil) := ntosize(d, b.n);
		(nsize, nil) := ntosize(d, n);
		if(size != nsize){
			d.release(b);
			b = d.new(n);
		}
	}else
		b = d.new(n);
	if(b == nil)
		return nil;
	if(sys->pwrite(d.fd, a, n, b.addr) != n){
		sys->werrstr(sys->sprint("Disk write error: %r"));
		return nil;
	}
	b.n = n;
	return b;
}

Disk.read(d: self ref Disk, b: ref Block, a: array of byte, n: int): int
{
	if(b == nil || n > b.n){
		sys->werrstr("read request bigger than block");
		return -1;
	}
	return sys->pread(d.fd, a, n, b.addr);
}
