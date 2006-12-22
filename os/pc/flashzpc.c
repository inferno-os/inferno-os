#include	"u.h"
#include	"../port/lib.h"
#include	"mem.h"
#include	"dat.h"
#include	"fns.h"
#include	"io.h"
#include	"../port/error.h"

#include	"flashif.h"

#define FLASHMEM	0xfff80000
#define FLASHPGSZ	0x40000
#define FLASHBKSZ	(FLASHPGSZ>>2)
#define LOG2FPGSZ	18
#define FLASHEND	(FLASHMEM+FLASHPGSZ)
#define SYSREG0	0x78
#define SYSREG1	0x878

/* Intel28F016SA flash memory family (8SA and (DD)32SA as well) in byte mode */

/*
  * word mode does not work - a 2 byte write to a location results in the lower address 
  * byte being unchanged (4 byte writes are even stranger) and no indication of error.
  * Perhaps the bridge is interfering with the address lines.
  * Looks like the BIOS code doesn't use it either but that's not certain.
  */

/*
  * When port 0x78 bit 2 is set to 1 (flash device 1)
  * 	0xfff80000-0xfffbffff seems to be free but has dos block headers
  *	 0xfffc0000-0xfffdffff seems to be the DOS P: drive 
  *	 0xfffe0000-0xffffffff  is the BIOS
  * When port 0x78 bit 2 is set to 0 (flash device 0)
  *	0xfff80000-0xffffffff is a mixture of used and unused DOS blocks and apparently
  *	many copies of the BIOS
  *
  *  In the absence of information from Ziatech and to preserve the BIOS and DOS sections,
  *  this driver only uses the first range for a total of 8 x 0x40000 = 2Mb
  */

enum {
	DQ7 = 0x80,
	DQ6 = 0x40,
	DQ5 = 0x20,
	DQ4 = 0x10,
	DQ3 = 0x08,
	DQ2 = 0x04,
	DQ1 = 0x02,
	DQ0 = 0x01,
};

enum {
	FLRDM = 0xFF,		/* read */
	FLWTM = 0x10,	/* write/program */
	FLCLR = 0x50,		/* clear SR */
	FLBE1 = 0x20,		/* block erase */
	FLBE2 = 0xD0,		/* block erase */
	FLRSR = 0x70,		/* read SR */
	FLDID = 0x90,		/* read id */
};

#define	DPRINT	if(0)print
#define	EPRINT	if(1)print

static int
zpcwait(uchar *p, ulong ticks)
{
	uchar csr;

	ticks += m->ticks+1;
         while((*p & DQ7) != DQ7){
		sched();
		if(m->ticks >= ticks){
			EPRINT("flash: timed out: %8.8lux\n", (ulong)*p);
			return -1;
		}
	}
	csr = *p;
	if(csr & (DQ5|DQ4|DQ3)){
		EPRINT("flash: DQ5 error: %8.8lux %8.8lux\n", p, (ulong)csr);
		return 0;
	}
	return 1;
}

static int
eraseall(Flash *f)
{
	uchar r;
	uchar *p;
	int i, j, s;

	DPRINT("flash: erase all\n");
	for (i = 0; i < 8; i++) {		/* page */
		/* set page */
		r = inb(SYSREG0);
		r &= 0x8f;
		r |= i<<4;
		outb(SYSREG0, r);
		p = (uchar *)f->addr;
		for (j = 0; j < 4; j++) {	/* block within page */
			DPRINT("erasing page %d block %d addr %lux\n", i, j, p);
			s = splhi();
			*p = FLBE1;
			*p = FLBE2;
			splx(s);
			if(zpcwait(p, MS2TK(16*1000)) <= 0){
				*p = FLCLR;	/* clr SR */
				*p = FLRDM;	/* read mode */
				f->unusable = ~0;
				return -1;
			}
			*p = FLCLR;
			*p = FLRDM;
			p += FLASHPGSZ>>2;
		}
	}
	return 0;
}

static int
erasezone(Flash *f, int zone)
{
	uchar r;
	uchar *p;
	int s, pg, blk;

	DPRINT("flash: erase zone %d\n", zone);
	if(zone & ~31) {
		EPRINT("flash: bad erasezone %d\n", zone);
		return -1;	/* bad zone */
	}
	pg = zone>>2;
	blk = zone&3;
	/* set page */
	r = inb(SYSREG0);
	r &= 0x8f;
	r |= pg<<4;
	outb(SYSREG0, r);
	p = (uchar *)f->addr + blk*(FLASHPGSZ>>2);
	DPRINT("erasing zone %d pg %d blk %d addr %lux\n", zone, pg, blk, p);
	s = splhi();
	*p = FLBE1;
	*p = FLBE2;
	splx(s);
	if(zpcwait(p, MS2TK(8*1000)) <= 0){
		*p = FLCLR;
		*p = FLRDM;	/* reset */
		f->unusable |= 1<<zone;
		return -1;
	}
	*p = FLCLR;
	*p = FLRDM;
	return 0;
}

static int
readx(Flash *f, ulong offset, void *buf, long n)
{
	uchar r;
	ulong pg, o;
	long m;
	uchar *p = buf;

	pg = offset>>LOG2FPGSZ;
	o = offset&(FLASHPGSZ-1);
	while (n > 0) {
		if (pg < 0 || pg > 7) {
			EPRINT("flash: bad read %ld %ld\n", offset, n);
			return -1;
		}
		/* set page */
		r = inb(SYSREG0);
		r &= 0x8f;
		r |= pg<<4;
		outb(SYSREG0, r);
		if (o+n > FLASHPGSZ)
			m = FLASHPGSZ-o;
		else
			m = n;
		DPRINT("flash: read page %ld offset %lux buf %lux n %ld\n", pg, o, p-(uchar*)buf, m);
		memmove(p, (uchar *)f->addr + o, m);
		p += m;
		n -= m;
		pg++;
		o = 0;
	}
	return 0;
}

static int
writex(Flash *f, ulong offset, void *buf, long n)
{
	int i, s;
	uchar r;
	ulong pg, o;
	long m;
	uchar *a, *v = buf;

	DPRINT("flash: writex\n");
	pg = offset>>LOG2FPGSZ;
	o = offset&(FLASHPGSZ-1);
	while (n > 0) {
		if (pg < 0 || pg > 7) {
			EPRINT("flash: bad write %ld %ld\n", offset, n);
			return -1;
		}
		/* set page */
		r = inb(SYSREG0);
		r &= 0x8f;
		r |= pg<<4;
		outb(SYSREG0, r);
		if (o+n > FLASHPGSZ)
			m = FLASHPGSZ-o;
		else
			m = n;
		a = (uchar *)f->addr + o;
		DPRINT("flash: write page %ld offset %lux buf %lux n %ld\n", pg, o, v-(uchar*)buf, m);
		for (i = 0; i < m; i++, v++, a++) {
			if (~*a & *v) {
				EPRINT("flash: bad write: %lux %lux -> %lux\n", (ulong)a, (ulong)*a, (ulong)*v);
				return -1;
			}
			if (*a == *v)
				continue;
			s = splhi();
			*a = FLWTM;	/* program */
			*a = *v;
			splx(s);
			microdelay(8);
			if(zpcwait(a, 5) <= 0){
				*a = FLCLR;	/* clr SR */
				*a = FLRDM;	/* read mode */
				f->unusable = ~0;
				return -1;
			}
			*a = FLCLR;
			*a = FLRDM;
			if (*a != *v) {
				EPRINT("flash: write %lux %lux -> %lux failed\n", (ulong)a, (ulong)*a, (ulong)*v);
				return -1;
			}
		}
		n -= m;
		pg++;
		o = 0;
	}
	return 0;
}

#ifdef ZERO
/* search the whole of flash */
static void
flashsearch(Flash *f)
{
	int d, m, p, b, n, i;
	uchar r, buf[64];

	for (d = 0; d < 2; d++) {	/* flash device */
		r = inb(SYSREG0);
		r &= 0xfb;
		r |= (d<<2);
		outb(SYSREG0, r);
		for (m = 0; m < 2; m++) {	/* lower/upper mem */
			if (m == 0)
				f->addr = (void *)FLASHMEM;
			else
				f->addr = (void *)FLASHEND;
			for (p = 0; p < 8; p++) {	/* page */
				for (b = 0; b < 4; b++) {	/* block */
					n = readx(f, (4*p+b)*FLASHBKSZ, buf, 64);
					if (n != 0) {
						print("bad read in search %d\n", n);
						goto end;
					}
					print("%d %d %d %d : ", d, m, p, b);
					if (buf[0] == 0x5a && buf[1] == 0x54) {	/* DOS block */
						n = 0;
						for (i = 0; i < 64; i++) {
							if (buf[i] == 0xff)
								n++;
						}
						if (n == 64-28)
							print("un");
						print("used dos\n");
					}
					else if (buf[0] == 0x55 && buf[1] == 0xaa)
						print("bios start\n");
					else
						print("bios ?\n");	
				}
			}
		}
	}
end:
	r = inb(SYSREG0);
	r |= 4;
	outb(SYSREG0, r);
	f->addr = (void *)FLASHMEM;	
}
#endif

static int
reset(Flash *f)
{
	uchar r;
	int s;
	ulong pa;
	Pcidev *bridge;

	/*  get bridge device */
	bridge = pcimatch(nil, 0x8086, 0x7000);	/* Intel PIIX3 ISA bridge device */
	if (bridge == nil) {
		EPRINT("flash : failed to find bridge device\n");
		return 1;
	}
	/* enable extended BIOS and read/write */
	s = splhi();
	r = pcicfgr8(bridge, 0x4e);
	r |= 0x84;
	pcicfgw8(bridge, 0x4e, r);
	splx(s);
	/* set system register bits */
	r = inb(SYSREG0);
	r |= 0x86;	/* chip enable, non-BIOS part, set r/w */
	outb(SYSREG0, r);
	/*
	  * might have to grab memory starting at PADDR(FLASHMEM) ie 0x7ff80000
	  * because if this is mapped via virtual address FLASHMEM we would get a
	  * a kernel panic in mmukmap().
	  *	va = 0xfff80000 pa = 0xfff80000 for flash
	  *     va = 0xfff80000 pa = 0x7ff80000 if lower memory grabbed by anything
	  */
	/* 
	  * upafree(FLASHMEM, FLASHPGSZ);
	  * pa = upamalloc(FLASHMEM, FLASHPGSZ, 0);
	  * if (pa != FLASHMEM)
	  *	error
	  */
	pa = mmukmap(FLASHMEM, FLASHMEM, FLASHPGSZ);
	if (pa != FLASHEND) {
		EPRINT("failed to map flash memory");
		return 1;
	}
/*
	pa = mmukmap(FLASHEND, FLASHEND, FLASHPGSZ);
	if (pa != 0) {
		EPRINT("failed to map flash memory");
		return 1;
	}
*/
	f->id = 0x0089;	/* can't use autoselect: might be running in flash */
	f->devid = 0x66a0;
	f->read = readx;
	f->write = writex;
	f->eraseall = eraseall;
	f->erasezone = erasezone;
	f->suspend = nil;
	f->resume = nil;
	f->width = 1;				/* must be 1 since devflash.c must not read directly */
	f->erasesize = 64*1024;
	*(uchar*)f->addr = FLCLR;	/* clear status registers */
	*(uchar*)f->addr = FLRDM;	/* reset to read mode */
	return 0;
}

void
flashzpclink(void)
{
	addflashcard("DD28F032SA", reset);
}
