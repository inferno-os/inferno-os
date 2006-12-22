#include	"u.h"
#include	"../port/lib.h"
#include	"mem.h"
#include	"dat.h"
#include	"fns.h"
#include	"io.h"
#include	"../port/error.h"

#include	"flashif.h"

typedef struct Nandtab Nandtab;

struct Nandtab {
	short manufacturer;
	uchar id;
	uchar l2bytesperpage;
	ushort pagesperblock;
	ushort blocks;
	uchar tPROGms;
	ushort tBERASEms;
	uchar tRus;
};

static Nandtab nandtab[] = {
	{ 0xec, 	0xe6,	9,		16,		1024,	1,		4,		7 },	/* Samsung KM29U64000T */

	{ 0x98,	0xe6,	9,		16,		1024,	1,		4,		25 }, /* Toshiba TC58V64AFT */
	{ 0x98,	0x73,	9,		32,		1024,	1,		10,		25},	/* Toshiba TC56V128AFT */
	/* Generic entries which take timings from Toshiba SMIL example code */
	{ -1,		0xea,	8,		16,		512,		20,		400,		100	 },
	{ -1,		0xe3,	9,		16,		512,		20,		400,		100	 },
	{ -1,		0xe5,	9,		16,		512,		20,		400,		100	 },
	{ -1,		0x73,	9,		32,		1024,	20,		400,		100	 },
	{ -1,		0x75,	9,		32,		2048,	20,		400,		100	 },
	{ -1,		0x76,	9,		32,		4096,	20,		400,		100	 },
};

enum {
	ReadMode1 = 0x00,
	ReadMode2 = 0x01,
	Program = 0x10,
	ReadMode3 = 0x50,
	Erase1 = 0x60,
	ReadStatus = 0x70,
	Write = 0x80,
	Identify = 0x90,
	Erase2 = 0xd0,

	StatusReady = 0x40,
	StatusFail = 0x01,
};

/*
 * NAND flash driver
 */

#define	DPRINT	if(0)print
#define	EPRINT	if(1)print

static int idchip(Flash *f);

static void
nand_writebyte(Flash *f, uchar b)
{
	archnand_write(f, &b, 1);
}

static uchar
nand_readbyte(Flash *f)
{
	uchar b;
	archnand_read(f, &b, 1);
	return b;
}

static int
idchip(Flash *f)
{
	int x;
	uchar maker, device;

	f->id = 0;
	f->devid = 0;
	f->width = 1;
	archnand_claim(f, 1);
	archnand_setCLEandALE(f, 1, 0);
	nand_writebyte(f, Identify);
	archnand_setCLEandALE(f, 0, 1);
	nand_writebyte(f, 0);
	archnand_setCLEandALE(f, 0, 0);
	maker = nand_readbyte(f);
	device = nand_readbyte(f);
	archnand_claim(f, 0);
	iprint("man=%#ux device=%#ux\n", maker, device);
	for(x = 0; x < sizeof(nandtab) / sizeof(nandtab[0]); x++){
		if(nandtab[x].id == (device & 0xff)
			&& (nandtab[x].manufacturer == maker || nandtab[x].manufacturer == -1)){
			ulong bpp;
			f->id = maker;
			f->devid = device;
			f->nr = 1;
			bpp = 1 << nandtab[x].l2bytesperpage;
			bpp |= bpp >> 5;
			f->regions[0].erasesize = bpp * nandtab[x].pagesperblock;
			f->size = f->regions[0].erasesize * nandtab[x].blocks;
			f->regions[0].n = nandtab[x].blocks;
			f->regions[0].start = 0;
			f->regions[0].end = f->size;
			f->regions[0].pagesize = bpp;
			f->data = &nandtab[x];
			return 0;
		}
	}
	print("nand: device %#.2ux/%#.2ux not recognised\n", maker, device);
	return -1;
}

static int
erasezone(Flash *f, Flashregion *r, ulong byteaddr)
{
	Nandtab *nt = f->data;
	int paddress;
	uchar val;
	int rv;
	uchar addr[2];

	if(byteaddr%r->erasesize || byteaddr >= f->size)
		return -1;	/* bad zone */
	paddress = byteaddr/r->erasesize * nt->pagesperblock;	/* can simplify ... */
//print("erasezone(%.8lux) page %d %.8lux\n", byteaddr, paddress, r->erasesize);
	archnand_claim(f, 1);
	archnand_setCLEandALE(f, 1, 0);		// command mode
	nand_writebyte(f, Erase1);
	archnand_setCLEandALE(f, 0, 1);		// address mode
	addr[0] = paddress;
	addr[1] = paddress >> 8;
	archnand_write(f, addr, 2);
	archnand_setCLEandALE(f, 1, 0);		// command mode
	nand_writebyte(f, Erase2);
	nand_writebyte(f, ReadStatus);
	archnand_setCLEandALE(f, 0, 0);		// data mode

	do {
		val = nand_readbyte(f);
	} while((val & StatusReady) != StatusReady);

	if((val & StatusFail) != 0){
		print("erasezone failed: %.2ux\n", val);
		rv = -1;
	}
	else
		rv = 0;
	archnand_claim(f, 0);				// turn off chip
	return rv;
}

static int
writepage(Flash *f, ulong page, ushort addr, void *buf, long n)
{
	uchar cmd;
	uchar val;
	int rv;
	uchar cmdbuf[3];

//print("writepage(%ld, %d, %ld)\n", page, addr, n);
	// Fake a read to set the pointer
	if(addr < 256)
		cmd = ReadMode1;
	else if(addr < 512){
		cmd = ReadMode2;
		addr -= 256;
	}else{
		cmd = ReadMode3;
		addr -= 512;
	}
	archnand_claim(f, 1);
	archnand_setCLEandALE(f, 1, 0);		// command mode
	nand_writebyte(f, cmd);
	nand_writebyte(f, Write);
	archnand_setCLEandALE(f, 0, 1);		// address mode
	cmdbuf[0] = addr;
	cmdbuf[1] = page;
	cmdbuf[2] = page >> 8;
	archnand_write(f, cmdbuf, 3);
	archnand_setCLEandALE(f, 0, 0);		// data mode
	archnand_write(f, buf, n);
	archnand_setCLEandALE(f, 1, 0);		// command mode
	nand_writebyte(f, Program);
	nand_writebyte(f, ReadStatus);
	archnand_setCLEandALE(f, 0, 0);		// data mode

	do {
		val = nand_readbyte(f);
	}while((val & StatusReady) != StatusReady);

	if((val & StatusFail) != 0){
		print("writepage failed: %.2ux\n", val);
		rv = -1;
	}else
		rv = 0;

	archnand_claim(f, 0);
	return rv;
}

static int
write(Flash *f, ulong offset, void *buf, long n)
{
	Nandtab *nt = f->data;
	ulong page;
	ulong addr;
	ulong xbpp;

//print("write(%ld, %ld)\n", offset, n);

	xbpp = (1 << nt->l2bytesperpage);
	xbpp |= (xbpp >> 5);
	page = offset / xbpp;
	addr = offset % xbpp;

	while(n > 0){
		int count;
		count = xbpp - addr;
		if(count > n)
			count = n;
		if(writepage(f, page, addr, buf, count) < 0)
			return -1;
		offset += count;
		n -= count;
		buf = (uchar *)buf + count;
		addr = 0;
	}
//print("write done\n");
	return 0;
}

static int
read(Flash *f, ulong offset, void *buf, long n)
{
	Nandtab *nt = f->data;
	uchar cmd;
	ulong page;
	ulong addr;
	ushort bytesperpage, xbytesperpage, skip, partialaddr;
	uchar cmdbuf[3];
	int toread;

//print("read(%ld, %.8lux, %ld)\n", offset, buf, n);

	bytesperpage = (1 << nt->l2bytesperpage);
	xbytesperpage = bytesperpage;
	xbytesperpage += bytesperpage >> 5;	// 512 => 16, 256 => 8
	page = offset / xbytesperpage;
	partialaddr = offset % xbytesperpage;
	skip = 0;
	if(partialaddr >= bytesperpage && xbytesperpage - partialaddr < n){
		// cannot start read in extended area, and then chain into main area,
		// so start on last byte of main area, and skip the extra bytes
		// stupid chip design this one
		skip = partialaddr - bytesperpage + 1;
		n += skip;
		partialaddr = bytesperpage - 1;
	}
	addr = partialaddr;
	if(addr >= bytesperpage){
		cmd = ReadMode3;
		addr -= bytesperpage;
	}else if(addr >= 256){
		cmd = ReadMode2;
		addr -= 256;
	}else
		cmd = ReadMode1;

//print("cmd %.2x page %.4lux addr %.8lux partialaddr %d skip %d\n", cmd, page, addr, partialaddr, skip);
	// Read first page
	archnand_claim(f, 1);
	archnand_setCLEandALE(f, 1, 0);
	nand_writebyte(f, cmd);
	archnand_setCLEandALE(f, 0, 1);
	cmdbuf[0] = addr;
	cmdbuf[1] = page;
	cmdbuf[2] = page >> 8;
	archnand_write(f, cmdbuf, 3);
	archnand_setCLEandALE(f, 0, 0);
	if(partialaddr){
		// partial first page
		microdelay(nt->tRus);
		toread = partialaddr < xbytesperpage ? xbytesperpage - partialaddr : 0;
		if(toread > n)
			toread = n;
		if(skip){
			archnand_read(f, 0, skip);
			toread -= skip;
			n -= skip;
//			partialaddr += skip;
		}
		archnand_read(f, buf, toread);
		n -= toread;
//		partialaddr += toread;
		buf = (uchar *)buf + toread;
	}
	while(n){
		microdelay(nt->tRus);
		toread = xbytesperpage;
		if(n < toread)
			toread = n;
		archnand_read(f, buf, toread);
		n -= toread;
		buf = (uchar *)buf + toread;
	}
	archnand_claim(f, 0);
//print("readn done\n");
	return 0;
}

static int
reset(Flash *f)
{
//iprint("nandreset\n");
	if(f->data != nil)
		return 1;
	f->write = write;
 	f->read = read;
	f->eraseall = nil;
	f->erasezone = erasezone;
	f->suspend = nil;
	f->resume = nil;
	f->sort = "nand";
	archnand_init(f);
	return idchip(f);
}

void
flashnandlink(void)
{
	addflashcard("nand", reset);
}
