#
# basic Flash Translation Layer driver
#	see for instance the Intel technical paper
#	``Understanding the Flash Translation Layer (FTL) Specification''
#	Order number 297816-001 (online at www.intel.com)
#
# a public driver by David Hinds, dhinds@allegro.stanford.edu
# further helps with some details.
#
# this driver uses the common simplification of never storing
# the VBM on the medium (a waste of precious flash!) but
# rather building it on the fly as the block maps are read.
#
# Plan 9 driver (c) 1997 by C H Forsyth (forsyth@caldo.demon.co.uk)
#	This driver may be used or adapted by anyone for any non-commercial purpose.
#
# adapted for Inferno 1998 by C H Forsyth, Vita Nuova Limited, York, England (byteles@vitanuova.com)
#
# C H Forsyth and Vita Nuova Limited expressly allow Lucent Technologies
# to use this driver freely for any Inferno-related purposes whatever,
# including commercial applications.
#
# TO DO:
#	check error handling details for get/put flash
#	bad block handling
#	reserved space in formatted size
#	possibly block size as parameter
#	fetch parameters from header on init
#
# Adapted to a ftl formatter for Inferno 2000 by J R Firth, Vita Nuova Limited
#	usage : ftl flashsize secsize inputfile outputfile
# outputfile will then be a ftl image of inputfile
# nb assumes the base address is zero
#
# Converted to limbo for Inferno 2000 by JR Firth, Vita Nuova Holdings Limited
#

implement Ftlimage;

include "sys.m";
include "draw.m";

sys : Sys;
	OREAD, OWRITE, FD, open, create, read, write, print, fprint : import sys;

Ftlimage : module
{
	init : fn(nil : ref Draw->Context, argv : list of string);
};

stderr : ref FD;

flashsize, secsize : int;
flashm : array of byte;
trace : int = 0;

Eshift : con 18;			# 2^18=256k; log2(eraseunit)
Flashseg : con 1<<Eshift;
Bshift : con 9;			# 2^9=512
Bsize : con 1<<Bshift;
BAMoffset : con 16r100;
Nolimit : con ~0;
USABLEPCT : con 95;	# release only this % to client

FTLDEBUG : con 0;

# erase unit header (defined by FTL specification)
# offsets into Merase
O_LINKTUPLE : con 0;
O_ORGTUPLE : con 5;
O_NXFER : con 15;
O_NERASE : con 16;
O_ID : con 20;
O_BSHIFT : con 22;
O_ESHIFT : con 23;
O_PSTART : con 24;
O_NUNITS : con 26;
O_PSIZE : con 28;
O_VBMBASE : con 32;
O_NVBM : con 36;
O_FLAGS : con 38;
O_CODE : con 39;
O_SERIAL : con 40;
O_ALTOFFSET : con 44;
O_BAMOFFSET : con 48;
O_RSV2 : con 52;

ERASEHDRLEN : con	64;

# special unit IDs
XferID : con 16rffff;
XferBusy : con 16r7fff;

# special BAM addresses
Bfree : con -1;	#16rffffffff
Bwriting : con -2; #16rfffffffe
Bdeleted : con 0;

# block types
TypeShift : con 7;
BlockType : con (1<<TypeShift)-1;
ControlBlock : con 16r30;
DataBlock : con 16r40;
ReplacePage : con 16r60;
BadBlock : con 16r70;

BNO(va : int) : int
{
	return va>>Bshift;
}
MKBAM(b : int,t : int) : int
{
	return (b<<Bshift)|t;
}

Terase : adt {
	x : int;
	id : int;
	offset : int;
	bamoffset : int;
	nbam : int;
	bam : array of byte;
	bamx : int;
	nfree : int;
	nused : int;
	ndead : int;
	nbad : int;
	nerase : int;
};

Ftl : adt {
	base : int;		# base of flash region 
	size : int;		# size of flash region 
	segsize : int;	# size of flash segment (erase unit) 
	eshift : int;	# log2(erase-unit-size) 
	bshift : int;	# log2(bsize) 
	bsize : int;
	nunit : int;		# number of segments (erase units) 
	unit : array of ref Terase;
	lastx : int;		# index in unit of last allocation 
	xfer : int;		# index in unit of current transfer unit (-1 if none) 
	nfree : int;		# total free space in blocks 
	nblock : int;	# total space in blocks 
	rwlimit : int;	# user-visible block limit (`formatted size') 
	vbm : array of int;		# virtual block map
	fstart : int;		# address of first block of data in a segment 
	trace : int;		# (debugging) trace of read/write actions 
	detach : int;	# free Ftl on last close 
 
	# scavenging variables 
	needspace : int;
	hasproc : int;
};

# Ftl.detach 
Detached : con 1;	# detach on close 
Deferred : con 2;	# scavenger must free it 

ftls : ref Ftl;

ftlstat(sz : int)
{
	print("16r%x:16r%x:16r%x\n", ftls.rwlimit*Bsize, sz, flashsize);
	print("%d:%d:%d in 512b blocks\n", ftls.rwlimit, sz>>Bshift, flashsize>>Bshift);
}
	 
ftlread(buf : array of byte, n : int, offset : int) : int
{
	ftl : ref Ftl;
	e : ref Terase;
	nb : int;
	a : int;
	pb : int;
	mapb : int;

	if(n <= 0 || n%Bsize || offset%Bsize) {
		fprint(stderr, "ftl: bad read\n");
		exit;
	}
	ftl = ftls;
	nb = n/Bsize;
	offset /= Bsize;
	if(offset >= ftl.rwlimit)
		return 0;
	if(offset+nb > ftl.rwlimit)
		nb = ftl.rwlimit - offset;
	a = 0;
	for(n = 0; n < nb; n++){
		(mapb, e, pb) = mapblk(ftl, offset+n);
		if(mapb)
			getflash(ftl, buf[a:], e.offset + pb*Bsize, Bsize);
		else
			memset(buf[a:], 0, Bsize);
		a += Bsize;
	}
	return a;
}

ftlwrite(buf : array of byte, n : int, offset : int) : int
{
	ns, nb : int;
	a : int;
	e, oe : ref Terase;
	ob, v : int;
	ftl : ref Ftl;
	mapb : int;

	if(n <= 0)
		return 0;
	ftl = ftls;
	if(n <= 0 || n%Bsize || offset%Bsize) {
		fprint(stderr, "ftl: bad write\n");
		exit;
	}
	nb = n/Bsize;
	offset /= Bsize;
	if(offset >= ftl.rwlimit)
		return 0;
	if(offset+nb > ftl.rwlimit)
		nb = ftl.rwlimit - offset;
	a = 0;
	for(n = 0; n < nb; n++){
		ns = 0;
		while((v = allocblk(ftl)) == 0)
			if(!scavenge(ftl) || ++ns > 3){
				fprint(stderr, "ftl: flash memory full\n");
			}
		(mapb, oe, ob) = mapblk(ftl, offset+n);
		if(!mapb)
			oe = nil;
		e = ftl.unit[v>>16];
		v &= 16rffff;
		putflash(ftl, e.offset + v*Bsize, buf[a:], Bsize);
		putbam(ftl, e, v, MKBAM(offset+n, DataBlock));
		# both old and new block references exist in this window (can't be closed?) 
		ftl.vbm[offset+n] = (e.x<<16) | v;
		if(oe != nil){
			putbam(ftl, oe, ob, Bdeleted);
			oe.ndead++;
		}
		a += Bsize;
	}
	return a;
}

mkftl(fname : string, base : int, size : int, eshift : int, op : string) : ref Ftl
{
	i, j, nov, segblocks : int;
	limit : int;
	e : ref Terase;

	ftl := ref Ftl;
	ftl.lastx = 0;
	ftl.detach = 0;
	ftl.needspace = 0;
	ftl.hasproc = 0;
	ftl.trace = 0;
	limit = flashsize;
	if(size == Nolimit)
		size = limit-base;
	if(base >= limit || size > limit || base+size > limit || eshift < 8 || (1<<eshift) > size) {
		fprint(stderr, "bad flash space parameters");
		exit;
	}
	if(FTLDEBUG || ftl.trace || trace)
		print("%s flash %s #%x:#%x limit #%x\n", op, fname, base, size, limit);
	ftl.base = base;
	ftl.size = size;
	ftl.bshift = Bshift;
	ftl.bsize = Bsize;
	ftl.eshift = eshift;
	ftl.segsize = 1<<eshift;
	ftl.nunit = size>>eshift;
	nov = ((ftl.segsize/Bsize)*4 + BAMoffset + Bsize - 1)/Bsize;	# number of overhead blocks per segment (header, and BAM itself) 
	ftl.fstart = nov;
	segblocks = ftl.segsize/Bsize - nov;
	ftl.nblock = ftl.nunit*segblocks;
	if(ftl.nblock >= 16r10000)
		ftl.nblock = 16r10000;
	ftl.vbm = array[ftl.nblock] of int; 
	ftl.unit = array[ftl.nunit] of ref Terase;
	if(ftl.vbm == nil || ftl.unit == nil) {
		fprint(stderr, "out of mem");
		exit;
	}
	for(i=0; i<ftl.nblock; i++)
		ftl.vbm[i] = 0;
	if(op == "format"){
		for(i=0; i<ftl.nunit-1; i++)
			eraseinit(ftl, i*ftl.segsize, i, 1);
		eraseinit(ftl, i*ftl.segsize, XferID, 1);
	}
	ftl.xfer = -1;
	for(i=0; i<ftl.nunit; i++){
		e = eraseload(ftl, i, i*ftl.segsize);
		if(e == nil){
			fprint(stderr, "ftl: logical segment %d: bad format\n", i);
			continue;
		}
		if(e.id == XferBusy){
			e.nerase++;
			eraseinit(ftl, e.offset, XferID, e.nerase);
			e.id = XferID;
		}
		for(j=0; j<ftl.nunit; j++)
			if(ftl.unit[j] != nil && ftl.unit[j].id == e.id){
				fprint(stderr, "ftl: duplicate erase unit #%x\n", e.id);
				erasefree(e);
				e = nil;
				break;
			}
		if(e != nil){
			ftl.unit[e.x] = e;
			if(e.id == XferID)
				ftl.xfer = e.x;
			if (FTLDEBUG || ftl.trace || trace)
				fprint(stderr, "ftl: unit %d:#%x used %d free %d dead %d bad %d nerase %d\n",
					e.x, e.id, e.nused, e.nfree, e.ndead, e.nbad, e.nerase);
		}
	}
	if(ftl.xfer < 0 && ftl.nunit <= 0 || ftl.xfer >= 0 && ftl.nunit <= 1) {
		fprint(stderr, "ftl: no valid flash data units");
		exit;
	}
	if(ftl.xfer < 0)
		fprint(stderr, "ftl: no transfer unit: device is WORM\n");
	else
		ftl.nblock -= segblocks;	# discount transfer segment 
	if(ftl.nblock >= 1000)
		ftl.rwlimit = ftl.nblock-100;	# TO DO: variable reserve 
	else
		ftl.rwlimit = ftl.nblock*USABLEPCT/100;
	return ftl;
}

ftlfree(ftl : ref Ftl)
{
	if(ftl != nil){
		ftl.unit = nil;
		ftl.vbm = nil;
		ftl = nil;
	}
}

#
# this simple greedy algorithm weighted by nerase does seem to lead
# to even wear of erase units (cf. the eNVy file system)
#
 
bestcopy(ftl : ref Ftl) : ref Terase
{
	e, be : ref Terase;
	i : int;

	be = nil;
	for(i=0; i<ftl.nunit; i++)
		if((e = ftl.unit[i]) != nil && e.id != XferID && e.id != XferBusy && e.ndead+e.nbad &&
		    (be == nil || e.nerase <= be.nerase && e.ndead >= be.ndead))
			be = e;
	return be;
}

copyunit(ftl : ref Ftl, from : ref Terase, too : ref Terase) : int
{
	i, nb : int;
	id := array[2] of byte;
	bam : array of byte;
	buf : array of byte;
	v, bno : int;

	if(FTLDEBUG || ftl.trace || trace)
		print("ftl: copying %d (#%x) to #%x\n", from.id, from.offset, too.offset);
	too.nbam = 0;
	too.bam = nil;
	bam = nil;
	buf = array[Bsize] of byte;
	if(buf == nil)
		return 0;
	PUT2(id, XferBusy);
	putflash(ftl, too.offset+O_ID, id, 2);
	# make new BAM 
	nb = from.nbam*4;
	bam = array[nb] of byte;
	memmove(bam, from.bam, nb);
	too.nused = 0;
	too.nbad = 0;
	too.nfree = 0;
	too.ndead = 0;
	for(i = 0; i < from.nbam; i++)
		bv := GET4(bam[4*i:]);
		case(bv){
		Bwriting or
		Bdeleted or
		Bfree =>
			PUT4(bam[4*i:], Bfree);
			too.nfree++;
			break;
		* =>
			case(bv&BlockType){
			DataBlock or
			ReplacePage =>
				v = bv;
				bno = BNO(v & ~BlockType);
				if(i < ftl.fstart || bno >= ftl.nblock){
					print("ftl: unit %d:#%x bad bam[%d]=#%x\n", from.x, from.id, i, v);
					too.nfree++;
					PUT4(bam[4*i:], Bfree);
					break;
				}
				getflash(ftl, buf, from.offset+i*Bsize, Bsize);
				putflash(ftl, too.offset+i*Bsize, buf, Bsize);
				too.nused++;
				break;
			ControlBlock =>
				too.nused++;
				break;
			* =>
				# case BadBlock:	# it isn't necessarily bad in this unit 
				too.nfree++;
				PUT4(bam[4*i:], Bfree);
				break;
			}
		}
	# for(i=0; i<from.nbam; i++){
	#	v = GET4(bam[4*i:]);
	#	if(v != Bfree && ftl.trace > 1)
	#		print("to[%d]=#%x\n", i, v);
	#	PUT4(bam[4*i:], v);
	# }
	putflash(ftl, too.bamoffset, bam, nb);	# BUG: PUT4 ? IS IT ?
	# for(i=0; i<from.nbam; i++){
	#	v = GET4(bam[4*i:]);
	#	PUT4(bam[4*i:], v);
	# }
	too.id = from.id;
	PUT2(id, too.id);
	putflash(ftl, too.offset+O_ID, id, 2);
	too.nbam = from.nbam;
	too.bam = bam;
	ftl.nfree += too.nfree - from.nfree;
	buf = nil;
	return 1;
}

mustscavenge(a : ref Ftl) : int
{
	return a.needspace || a.detach == Deferred;
}

donescavenge(a : ref Ftl) : int
{
	return a.needspace == 0;
}

scavengeproc(arg : ref Ftl)
{
	ftl : ref Ftl;
	i : int;
	e, ne : ref Terase;

	ftl = arg;
	if(mustscavenge(ftl)){
		if(ftl.detach == Deferred){
			ftlfree(ftl);
			fprint(stderr, "scavenge out of memory\n");
			exit;
		}
		if(FTLDEBUG || ftl.trace || trace)
			print("ftl: scavenge %d\n", ftl.nfree);
		e = bestcopy(ftl);
		if(e == nil || ftl.xfer < 0 || (ne = ftl.unit[ftl.xfer]) == nil || ne.id != XferID || e == ne)
			;
		else if(copyunit(ftl, e, ne)){
			i = ne.x; ne.x = e.x; e.x = i;
			ftl.unit[ne.x] = ne;
			ftl.unit[e.x] = e;
			ftl.xfer = e.x;
			e.id = XferID;
			e.nbam = 0;
			e.bam = nil;
			e.bamx = 0;
			e.nerase++;
			eraseinit(ftl, e.offset, XferID, e.nerase);
		}
		if(FTLDEBUG || ftl.trace || trace)
			print("ftl: end scavenge %d\n", ftl.nfree);
		ftl.needspace = 0;
	}
}

scavenge(ftl : ref Ftl) : int
{
	if(ftl.xfer < 0 || bestcopy(ftl) == nil)
		return 0;	# you worm! 

	if(!ftl.hasproc){
		ftl.hasproc = 1;
	}
	ftl.needspace = 1;

	scavengeproc(ftls);

	return ftl.nfree;
}

putbam(ftl : ref Ftl, e : ref Terase, n : int, entry : int)
{
	b := array[4] of byte;

	PUT4(e.bam[4*n:], entry);
	PUT4(b, entry);
	putflash(ftl, e.bamoffset + n*4, b, 4);
}

allocblk(ftl : ref Ftl) : int
{
	e : ref Terase;
	i, j : int;

	i = ftl.lastx;
	do{
		e = ftl.unit[i];
		if(e != nil && e.id != XferID && e.nfree){
			ftl.lastx = i;
			for(j=e.bamx; j<e.nbam; j++)
				if(GET4(e.bam[4*j:])== Bfree){
					putbam(ftl, e, j, Bwriting);
					ftl.nfree--;
					e.nfree--;
					e.bamx = j+1;
					return (e.x<<16) | j;
				}
			e.nfree = 0;
			print("ftl: unit %d:#%x nfree %d but not free in BAM\n", e.x, e.id, e.nfree);
		}
		if(++i >= ftl.nunit)
			i = 0;
	}while(i != ftl.lastx);
	return 0;
}

mapblk(ftl : ref Ftl, bno : int) : (int, ref Terase, int)
{
	v : int;
	x : int;

	if(bno < ftl.nblock){
		v = ftl.vbm[bno];
		if(v == 0 || v == ~0)
			return (0, nil, 0);
		x = v>>16;
		if(x >= ftl.nunit || x == ftl.xfer || ftl.unit[x] == nil){
			print("ftl: corrupt format: bad block mapping %d . unit #%x\n", bno, x);
			return (0, nil, 0);
		}
		return (1, ftl.unit[x], v & 16rFFFF);
	}
	return (0, nil, 0);
}

eraseinit(ftl : ref Ftl, offset : int, id : int, nerase : int)
{
	m : array of byte;
	bam : array of byte;
	i, nov : int;

	nov = ((ftl.segsize/Bsize)*4 + BAMoffset + Bsize - 1)/Bsize;	# number of overhead blocks (header, and BAM itself) 
	if(nov*Bsize >= ftl.segsize) {
		fprint(stderr, "ftl -- too small for files");
		exit;
	}
	eraseflash(ftl, offset);
	m = array[ERASEHDRLEN] of byte;
	if(m == nil) {
		fprint(stderr, "nomem\n");
		exit;
	}
	memset(m, 16rFF, len m);
	m[O_LINKTUPLE+0] = byte 16r13;
	m[O_LINKTUPLE+1] = byte 16r3;
	memmove(m[O_LINKTUPLE+2:], array of byte "CIS", 3);
	m[O_ORGTUPLE+0] = byte 16r46;
	m[O_ORGTUPLE+1] = byte 16r57;
	m[O_ORGTUPLE+2] = byte 16r00;
	memmove(m[O_ORGTUPLE+3:], array of byte "FTL100\0", 7);
	m[O_NXFER] = byte 1;
	PUT4(m[O_NERASE:], nerase);
	PUT2(m[O_ID:], id);
	m[O_BSHIFT] = byte ftl.bshift;
	m[O_ESHIFT] = byte ftl.eshift;
	PUT2(m[O_PSTART:], 0);
	PUT2(m[O_NUNITS:], ftl.nunit);
	PUT4(m[O_PSIZE:], ftl.size - nov*Bsize);
	PUT4(m[O_VBMBASE:], -1);	# we always calculate the VBM (16rffffffff)
	PUT2(m[O_NVBM:], 0);
	m[O_FLAGS] = byte 0;
	m[O_CODE] = byte 16rFF;
	memmove(m[O_SERIAL:], array of byte "Inf1", 4);
	PUT4(m[O_ALTOFFSET:], 0);
	PUT4(m[O_BAMOFFSET:], BAMoffset);
	putflash(ftl, offset, m, ERASEHDRLEN);
	m = nil;
	if(id == XferID)
		return;
	nov *= 4;	# now bytes of BAM 
	bam = array[nov] of byte;
	if(bam == nil) {
		fprint(stderr, "nomem");
		exit;
	}
	for(i=0; i<nov; i += 4)
		PUT4(bam[i:], ControlBlock);	# reserve them 
	putflash(ftl, offset+BAMoffset, bam, nov);
	bam = nil;
}

eraseload(ftl : ref Ftl, x : int, offset : int) : ref Terase
{
	m : array of byte;
	e : ref Terase;
	i, nbam : int;
	bno, v : int;

	m = array[ERASEHDRLEN] of byte;
	if(m == nil) {
		fprint(stderr, "nomem");
		exit;
	}
	getflash(ftl, m, offset, ERASEHDRLEN);
	if(memcmp(m[O_ORGTUPLE+3:], array of byte "FTL100\0", 7) != 0 ||
	   memcmp(m[O_SERIAL:], array of byte "Inf1", 4) != 0){
		m = nil;
		return nil;
	}
	e = ref Terase;
	if(e == nil){
		m = nil;
		fprint(stderr, "nomem");
		exit;
	}
	e.x = x;
	e.id = GET2(m[O_ID:]);
	e.offset = offset;
	e.bamoffset = GET4(m[O_BAMOFFSET:]);
	e.nerase = GET4(m[O_NERASE:]);
	e.bamx = 0;
	e.nfree = 0;
	e.nused = 0;
	e.ndead = 0;
	e.nbad = 0;
	m = nil;
	if(e.bamoffset != BAMoffset){
		e = nil;
		return nil;
	}
	e.bamoffset += offset;
	if(e.id == XferID || e.id == XferBusy){
		e.bam = nil;
		e.nbam = 0;
		return e;
	}
	nbam = ftl.segsize/Bsize;
	e.bam = array[4*nbam] of byte;
	e.nbam = nbam;
	getflash(ftl, e.bam, e.bamoffset, nbam*4);
	# scan BAM to build VBM 
	e.bamx = 0;
	for(i=0; i<nbam; i++){
		v = GET4(e.bam[4*i:]);
		if(v == Bwriting || v == Bdeleted)
			e.ndead++;
		else if(v == Bfree){
			if(e.bamx == 0)
				e.bamx = i;
			e.nfree++;
			ftl.nfree++;
		}else{
			case(v & BlockType){
			ControlBlock =>
				break;
			DataBlock =>
				# add to VBM 
				if(v & (1<<31))
					break;	# negative => VBM page, ignored 
				bno = BNO(v & ~BlockType);
				if(i < ftl.fstart || bno >= ftl.nblock){
					print("ftl: unit %d:#%x bad bam[%d]=#%x\n", e.x, e.id, i, v);
					e.nbad++;
					break;
				}
				ftl.vbm[bno] = (e.x<<16) | i;
				e.nused++;
				break;
			ReplacePage =>
				# replacement VBM page; ignored 
				break;
			BadBlock =>
				e.nbad++;
				break;
			* =>
				print("ftl: unit %d:#%x bad bam[%d]=%x\n", e.x, e.id, i, v);
			}
		}
	}
	return e;
}

erasefree(e : ref Terase)
{
	e.bam = nil;
	e = nil;
}

eraseflash(ftl : ref Ftl, offset : int)
{
	offset += ftl.base;
	if(FTLDEBUG || ftl.trace || trace)
		print("ftl: erase seg @#%x\n", offset);
	memset(flashm[offset:], 16rff, secsize);
}

putflash(ftl : ref Ftl, offset : int, buf : array of byte, n : int)
{
	offset += ftl.base;
	if(ftl.trace || trace)
		print("ftl: write(#%x, %d)\n", offset, n);
	memmove(flashm[offset:], buf, n);
}

getflash(ftl : ref Ftl, buf : array of byte, offset : int, n : int)
{
	offset += ftl.base;
	if(ftl.trace || trace)
		print("ftl: read(#%x, %d)\n", offset, n);
	memmove(buf, flashm[offset:], n);
}

BUFSIZE : con 8192;

main(argv : list of string)
{
	k, r, sz, offset : int = 0;
	buf, buf1 : array of byte;
	fd1, fd2 : ref FD;

	if (len argv != 5) {
		fprint(stderr, "usage: %s flashsize secsize kfsfile flashfile\n", hd argv);
		exit;
	}
	flashsize = atoi(hd tl argv);
	secsize = atoi(hd tl tl argv);
	fd1 = open(hd tl tl tl argv, OREAD);
	fd2 = create(hd tl tl tl tl argv, OWRITE, 8r644);
	if (fd1 == nil || fd2 == nil) {
		fprint(stderr, "bad io files\n");
		exit;
	}
	if(secsize == 0 || secsize > flashsize || secsize&(secsize-1) || 0&(secsize-1) || flashsize == 0 || flashsize != Nolimit && flashsize&(secsize-1)) {
		fprint(stderr, "ftl: bad sizes\n");
		exit;
	}
	for(k=0; k<32 && (1<<k) != secsize; k++)
			;
	flashm = array[flashsize] of byte;
	buf = array[BUFSIZE] of byte;
	if (flashm == nil) {
		fprint(stderr, "ftl: no mem for flash\n");
		exit;
	}
	ftls = mkftl("FLASH", 0, Nolimit, k, "format");
	for (;;) {
		r = read(fd1, buf, BUFSIZE);
		if (r <= 0)
			break;
		if (ftlwrite(buf, r, offset) != r) {
			fprint(stderr, "ftl: ftlwrite failed - input file too big\n");
			exit;
		}
		offset += r;
	}
	write(fd2, flashm, flashsize);
	fd1 = fd2 = nil;
	ftlstat(offset);
	# ftls = mkftl("FLASH", 0, Nolimit, k, "init"); 
	sz = offset;
	offset = 0;
	buf1 = array[BUFSIZE] of byte;
	fd1 = open(hd tl tl tl argv, OREAD);
	for (;;) {
		r = read(fd1, buf1, BUFSIZE);
		if (r <= 0)
			break;
		if (ftlread(buf, r, offset) != r) {
			fprint(stderr, "ftl: ftlread failed\n");
			exit;
		}
		if (memcmp(buf, buf1, r) != 0) {
			fprint(stderr, "ftl: bad read\n");
			exit;
		}
		offset += r;
	}
	fd1 = nil;
	if (offset != sz) {
		fprint(stderr, "ftl: bad final offset\n");
		exit;
	}
	exit;
}

init(nil : ref Draw->Context, argl : list of string)
{
	sys = load Sys Sys->PATH;
	stderr = sys->fildes(2);
	main(argl);
}

memset(d : array of byte, v : int, n : int)
{
	for (i := 0; i < n; i++)
		d[i] = byte v;
}

memmove(d : array of byte, s : array of byte, n : int)
{
	d[0:] = s[0:n];
}

memcmp(s1 : array of byte, s2 : array of byte, n : int) : int
{
	for (i := 0; i < n; i++) {
		if (s1[i] < s2[i])
			return -1;
		if (s1[i] > s2[i])
			return 1;
	}
	return 0;
}

atoi(s : string) : int
{
	v : int;
	base := 10;
	n := len s;
	neg := 0;

	for (i := 0; i < n && (s[i] == ' ' || s[i] == '\t'); i++)
		;
	if (s[i] == '+' || s[i] == '-') {
		if (s[i] == '-')
			neg = 1;
		i++;
	}
	if (n-i >= 2 && s[i] == '0' && s[i+1] == 'x') {
		base = 16;
		i += 2;
	}
	else if (n-i >= 1 && s[i] == '0') {
		base = 8;
		i++;
	}
	m := 0;
	for(; i < n; i++) {
		c := s[i];
		case c {
		'a' to 'z' =>
			v = c - 'a' + 10;
		'A' to 'Z' =>
			v = c - 'A' + 10;
		'0' to '9' =>
			v = c - '0';
		* =>
			fprint(stderr, "ftl: bad character in number %s\n", s);
			exit;
		}
		if(v >= base) {
			fprint(stderr, "ftl: character too big for base in %s\n", s);
			exit;
		}
		m = m * base + v;
	}
	if(neg)
		m = -m;
	return m;
}

# little endian 

GET2(b : array of byte) : int
{
	return ((int b[1]) << 8) | (int b[0]);
}

GET4(b : array of byte) : int
{
	return ((int b[3]) << 24) | ((int b[2]) << 16) | ((int b[1]) << 8) | (int b[0]);
}

PUT2(b : array of byte, v : int)
{
	b[1] = byte (v>>8);
	b[0] = byte v;
}

PUT4(b : array of byte, v : int)
{
	b[3] = byte (v>>24);
	b[2] = byte (v>>16);
	b[1] = byte (v>>8);
	b[0] = byte v;
}
