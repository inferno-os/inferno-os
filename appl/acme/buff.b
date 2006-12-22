implement Bufferm;

include "common.m";

sys : Sys;
dat : Dat;
utils : Utils;
diskm : Diskm;
ecmd: Editcmd;

FALSE, TRUE, XXX, Maxblock, Astring : import Dat;
Block : import Dat;
disk : import dat;
Disk : import diskm;
File: import Filem;
error, warning, min : import utils;

init(mods : ref Dat->Mods)
{
	sys = mods.sys;
	dat = mods.dat;
	utils = mods.utils;
	diskm = mods.diskm;
	ecmd = mods.editcmd;
}

nullbuffer : Buffer;

newbuffer() : ref Buffer
{
	b := ref nullbuffer;
	return b;
}

Slop : con 100;	# room to grow with reallocation

Buffer.sizecache(b : self ref Buffer, n : int)
{
	if(n <= b.cmax)
		return;
	b.cmax = n+Slop;
	os := b.c;
	b.c = utils->stralloc(b.cmax);
	if (os != nil) {
		loss := len os.s;
		c := b.c;
		oss := os.s;
		for (i := 0; i < loss && i < b.cmax; i++)
			c.s[i] = oss[i];
		utils->strfree(os);
	}
}

#
# Move cache so b.cq <= q0 < b.cq+b.cnc.
# If at very end, q0 will fall on end of cache block.
#

Buffer.flush(b : self ref Buffer)
{
	if(b.cdirty || b.cnc==0){
		if(b.cnc == 0)
			b.delblock(b.cbi);
		else
			b.bl[b.cbi] = disk.write(b.bl[b.cbi], b.c.s, b.cnc);
		b.cdirty = FALSE;
	}
}

Buffer.setcache(b : self ref Buffer, q0 : int)
{
	blp, bl : ref Block;
	i, q : int;

	if (q0 > b.nc)
		error("bad assert in setcache");

	# flush and reload if q0 is not in cache.
	 
	if(b.nc == 0 || (b.cq<=q0 && q0<b.cq+b.cnc))
		return;

	# if q0 is at end of file and end of cache, continue to grow this block
	 
	if(q0==b.nc && q0==b.cq+b.cnc && b.cnc<Maxblock)
		return;
	b.flush();
	# find block 
	if(q0 < b.cq){
		q = 0;
		i = 0;
	}else{
		q = b.cq;
		i = b.cbi;
	}
	blp = b.bl[i];
	while(q+blp.n <= q0 && q+blp.n < b.nc){
		q += blp.n;
		i++;
		blp = b.bl[i];
		if(i >= b.nbl)
			error("block not found");
	}
	bl = blp;
	# remember position 
	b.cbi = i;
	b.cq = q;
	b.sizecache(bl.n);
	b.cnc = bl.n;
	#read block
	disk.read(bl, b.c, b.cnc);
}

Buffer.addblock(b : self ref Buffer, i : int, n : int)
{
	if (i > b.nbl)
		error("bad assert in addblock");

	obl := b.bl;
	b.bl = array[b.nbl+1] of ref Block;
	b.bl[0:] = obl[0:i];
	if(i < b.nbl)
		b.bl[i+1:] = obl[i:b.nbl];
	b.bl[i] = disk.new(n);
	b.nbl++;
	obl = nil;
}

Buffer.delblock(b : self ref Buffer, i : int)
{
	if (i >= b.nbl)
		error("bad assert in delblock");

	disk.release(b.bl[i]);
	obl := b.bl;
	b.bl = array[b.nbl-1] of ref Block;
	b.bl[0:] = obl[0:i];
	if(i < b.nbl-1)
		b.bl[i:] = obl[i+1:b.nbl];
	b.nbl--;
	obl = nil;
}

Buffer.insert(b : self ref Buffer, q0 : int, s : string, n : int)
{
	i, j,  m, t, off, p : int;

	if (q0>b.nc)
		error("bad assert in insert");
	p = 0;
	while(n > 0){
		b.setcache(q0);
		off = q0-b.cq;
		if(b.cnc+n <= Maxblock){
			# Everything fits in one block. 
			t = b.cnc+n;
			m = n;
			if(b.bl == nil){	# allocate 
				if (b.cnc != 0)
					error("bad assert in insert");
				b.addblock(0, t);
				b.cbi = 0;
			}
			b.sizecache(t);
			c := b.c;
			# cs := c.s;
			for (j = b.cnc-1; j >= off; j--)
				c.s[j+m] = c.s[j];
			for (j = 0; j < m; j++)
				c.s[off+j] = s[p+j];
			b.cnc = t;
		}
		#
		# We must make a new block.  If q0 is at
		# the very beginning or end of this block,
		# just make a new block and fill it.
		#
		else if(q0==b.cq || q0==b.cq+b.cnc){
			if(b.cdirty)
				b.flush();
			m = min(n, Maxblock);
			if(b.bl == nil){	# allocate 
				if (b.cnc != 0)
					error("bad assert in insert");
				i = 0;
			}else{
				i = b.cbi;
				if(q0 > b.cq)
					i++;
			}
			b.addblock(i, m);
			b.sizecache(m);
			c := b.c;
			for (j = 0; j < m; j++)
				c.s[j] = s[p+j];
			b.cq = q0;
			b.cbi = i;
			b.cnc = m;
		}
		else {
			#
		 	# Split the block; cut off the right side and
		 	# let go of it.
			#
		 
			m = b.cnc-off;
			if(m > 0){
				i = b.cbi+1;
				b.addblock(i, m);
				b.bl[i] = disk.write(b.bl[i], b.c.s[off:], m);
				b.cnc -= m;
			}
			#
			# Now at end of block.  Take as much input
			# as possible and tack it on end of block.
			#
		 
			m = min(n, Maxblock-b.cnc);
			b.sizecache(b.cnc+m);
			c := b.c;
			for (j = 0; j < m; j++)
				c.s[j+b.cnc] = s[p+j];
			b.cnc += m;
		}
		b.nc += m;
		q0 += m;
		p += m;
		n -= m;
		b.cdirty = TRUE;
	}
}

Buffer.delete(b : self ref Buffer, q0 : int, q1 : int)
{
	m, n, off : int;

	if (q0>q1 || q0>b.nc || q1>b.nc)
		error("bad assert in delete");

	while(q1 > q0){
		b.setcache(q0);
		off = q0-b.cq;
		if(q1 > b.cq+b.cnc)
			n = b.cnc - off;
		else
			n = q1-q0;
		m = b.cnc - (off+n);
		if(m > 0) {
			c := b.c;
			# cs := c.s;
			p := m+off;
			for (j := off; j < p; j++)
				c.s[j] = c.s[j+n];
		}
		b.cnc -= n;
		b.cdirty = TRUE;
		q1 -= n;
		b.nc -= n;
	}
}

# Buffer.replace(b: self ref Buffer, q0: int, q1: int, s: string, n: int)
# {
#	if(q0>q1 || q0>b.nc || q1>b.nc || n != q1-q0)
#		error("bad assert in replace");
#	p := 0;
#	while(q1 > q0){
#		b.setcache(q0);
#		off := q0-b.cq;
#		if(q1 > b.cq+b.cnc)
#			n = b.cnc-off;
#		else
#			n = q1-q0;
#		c := b.c;
#		for(i := 0; i < n; i++)
#			c.s[i+off] = s[i+p];
#		b.cdirty = TRUE;
#		q0 += n;
#		p += n;
#	}	
# }

pbuf : array of byte;

bufloader(b: ref Buffer, q0: int, r: string, nr: int): int
{
	b.insert(q0, r, nr);
	return nr;
}

loadfile(fd: ref Sys->FD, q0: int, fun: int, b: ref Buffer, f: ref File): int
{
	p : array of byte;
	r : string;
	m, n, nb, nr : int;
	q1 : int;

	if (pbuf == nil)
		pbuf = array[Maxblock+Sys->UTFmax] of byte;
	p = pbuf;
	m = 0;
	n = 1;
	q1 = q0;
	#
	# At top of loop, may have m bytes left over from
	# last pass, possibly representing a partial rune.
	#	 
	while(n > 0){
		n = sys->read(fd, p[m:], Maxblock);
		if(n < 0){
			warning(nil, "read error in Buffer.load");
			break;
		}
		m += n;
		nb = sys->utfbytes(p, m);
		r = string p[0:nb];
		p[0:] = p[nb:m];
		m -= nb;
		nr = len r;
		if(fun == Dat->BUFL)
			q1 += bufloader(b, q1, r, nr);
		else
			q1 += ecmd->readloader(f, q1, r, nr);
	}
	p = nil;
	r = nil;
	return q1-q0;
}

Buffer.loadx(b : self ref Buffer, q0 : int, fd : ref Sys->FD) : int
{
	if (q0>b.nc)
		error("bad assert in load");
	return loadfile(fd, q0, Dat->BUFL, b, nil);
}

Buffer.read(b : self ref Buffer, q0 : int, s : ref Astring, p : int, n : int)
{
	m : int;

	if (q0>b.nc || q0+n>b.nc)
		error("bad assert in read");
	while(n > 0){
		b.setcache(q0);
		m = min(n, b.cnc-(q0-b.cq));
		c := b.c;
		cs := c.s;
		for (j := 0; j < m; j++)
			s.s[p+j] = cs[j+q0-b.cq];
		q0 += m;
		p += m;
		n -= m;
	}
}

Buffer.reset(b : self ref Buffer)
{
	i : int;

	b.nc = 0;
	b.cnc = 0;
	b.cq = 0;
	b.cdirty = 0;
	b.cbi = 0;
	# delete backwards to avoid n² behavior 
	for(i=b.nbl-1; --i>=0; )
		b.delblock(i);
}

Buffer.close(b : self ref Buffer)
{
	b.reset();
	if (b.c != nil) {
		utils->strfree(b.c);
		b.c = nil;
	}
	b.cnc = 0;
	b.bl = nil;
	b.nbl = 0;
}
