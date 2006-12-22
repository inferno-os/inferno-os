/*
 * PCI support code.
 */
#include "u.h"
#include "../port/lib.h"
#include "mem.h"
#include "dat.h"
#include "fns.h"
#include "io.h"
#include "../port/error.h"

#define DBG	if(0) pcilog

typedef struct Pcicfg Pcicfg;
struct Pcicfg {
	ulong	addr;
	union {
		ulong	l;
		uchar	b[4];
		ushort	s[2];
	} data;
};

static Pcicfg*	pcicfg;
static ulong*	pciack;
static ulong*	pcimem;

struct
{
	char	output[16384];
	int	ptr;
}PCICONS;

int
pcilog(char *fmt, ...)
{
	int n;
	va_list arg;
	char buf[PRINTSIZE];

	va_start(arg, fmt);
	n = vseprint(buf, buf+sizeof(buf), fmt, arg) - buf;
	va_end(arg);

	memmove(PCICONS.output+PCICONS.ptr, buf, n);
	PCICONS.ptr += n;
	return n;
}

enum
{					/* configuration mechanism #1 */
	MaxFNO		= 7,
	MaxUBN		= 255,
};

enum
{					/* command register */
	IOen		= (1<<0),
	MEMen		= (1<<1),
	MASen		= (1<<2),
	MemWrInv	= (1<<4),
	PErrEn		= (1<<6),
	SErrEn		= (1<<8),
};

static Lock pcicfglock;
static QLock pcicfginitlock;
static int pcicfgmode = -1;
static int pcimaxbno = 7;
static int pcimaxdno;
static Pcidev* pciroot;
static Pcidev* pcilist;
static Pcidev* pcitail;

static int pcicfgrw32(int, int, int, int);
static int pcicfgrw8(int, int, int, int);

static char* bustypes[] = {
[BusOPB]	"OPB",
[BusPLB]	"PLB",
[BusPCI]	"PCI",
};

#pragma	varargck	type	"T"	int

static int
tbdffmt(Fmt* fmt)
{
	char *p;
	int l, r, type, tbdf;

	if((p = malloc(READSTR)) == nil)
		return fmtstrcpy(fmt, "(tbdfconv)");
		
	switch(fmt->r){
	case 'T':
		tbdf = va_arg(fmt->args, int);
		type = BUSTYPE(tbdf);
		if(type < nelem(bustypes))
			l = snprint(p, READSTR, bustypes[type]);
		else
			l = snprint(p, READSTR, "%d", type);
		snprint(p+l, READSTR-l, ".%d.%d.%d",
			BUSBNO(tbdf), BUSDNO(tbdf), BUSFNO(tbdf));
		break;

	default:
		snprint(p, READSTR, "(tbdfconv)");
		break;
	}
	r = fmtstrcpy(fmt, p);
	free(p);

	return r;
}

ulong
pcibarsize(Pcidev *p, int rno)
{
	ulong v, size;

	v = pcicfgrw32(p->tbdf, rno, 0, 1);
	pcicfgrw32(p->tbdf, rno, 0xFFFFFFF0, 0);
	size = pcicfgrw32(p->tbdf, rno, 0, 1);
	if(v & 1)
		size |= 0xFFFF0000;
	pcicfgrw32(p->tbdf, rno, v, 0);

	return -(size & ~0x0F);
}

static int
pcisizcmp(void *a, void *b)
{
	Pcisiz *aa, *bb;

	aa = a;
	bb = b;
	return aa->siz - bb->siz;
}

static ulong
pcimask(ulong v)
{
	ulong m;

	m = BI2BY*sizeof(v);
	for(m = 1<<(m-1); m != 0; m >>= 1) {
		if(m & v)
			break;
	}

	m--;
	if((v & m) == 0)
		return v;

	v |= m;
	return v+1;
}

static void
pcibusmap(Pcidev *root, ulong *pmema, ulong *pioa, int wrreg)
{
	Pcidev *p;
	int ntb, i, size, rno, hole;
	ulong v, mema, ioa, sioa, smema, base, limit;
	Pcisiz *table, *tptr, *mtb, *itb;
	extern void qsort(void*, long, long, int (*)(void*, void*));

	ioa = *pioa;
	mema = *pmema;

	DBG("pcibusmap wr=%d %T mem=%luX io=%luX\n", 
		wrreg, root->tbdf, mema, ioa);

	ntb = 0;
	for(p = root; p != nil; p = p->link)
		ntb++;

	ntb *= (PciCIS-PciBAR0)/4;
	table = malloc(2*ntb*sizeof(Pcisiz));
	itb = table;
	mtb = table+ntb;

	/*
	 * Build a table of sizes
	 */
	for(p = root; p != nil; p = p->link) {
		if(p->ccrb == 0x06) {
			if(p->ccru == 0x04 && p->bridge != nil) {
				sioa = ioa;
				smema = mema;
				pcibusmap(p->bridge, &smema, &sioa, 0);
	
				hole = pcimask(smema-mema);
				if(hole < (1<<20))
					hole = 1<<20;
				p->mema.size = hole;
	
				hole = pcimask(sioa-ioa);
				if(hole < (1<<12))
					hole = 1<<12;
	
				p->ioa.size = hole;
	
				itb->dev = p;
				itb->bar = -1;
				itb->siz = p->ioa.size;
				itb++;
	
				mtb->dev = p;
				mtb->bar = -1;
				mtb->siz = p->mema.size;
				mtb++;
			}
			if((pcicfgr8(p, PciHDT)&0x7f) != 0)
				continue;
		}

		for(i = 0; i <= 5; i++) {
			rno = PciBAR0 + i*4;
			v = pcicfgrw32(p->tbdf, rno, 0, 1);
			size = pcibarsize(p, rno);
			if(size == 0)
				continue;

			if(v & 1) {
				itb->dev = p;
				itb->bar = i;
				itb->siz = size;
				itb++;
			}
			else {
				mtb->dev = p;
				mtb->bar = i;
				mtb->siz = size;
				mtb++;
			}

			p->mem[i].size = size;
		}
	}

	/*
	 * Sort both tables IO smallest first, Memory largest
	 */
	qsort(table, itb-table, sizeof(Pcisiz), pcisizcmp);
	tptr = table+ntb;
	qsort(tptr, mtb-tptr, sizeof(Pcisiz), pcisizcmp);

	/*
	 * Allocate IO address space on this bus
	 */
	for(tptr = table; tptr < itb; tptr++) {
		hole = tptr->siz;
		if(tptr->bar == -1)
			hole = 1<<12;
		ioa = (ioa+hole-1) & ~(hole-1);

		p = tptr->dev;
		if(tptr->bar == -1)
			p->ioa.bar = ioa;
		else {
			p->pcr |= IOen;
			p->mem[tptr->bar].bar = ioa|1;
			if(wrreg)
				pcicfgrw32(p->tbdf, PciBAR0+(tptr->bar*4), ioa|1, 0);
		}

		ioa += tptr->siz;
	}

	/*
	 * Allocate Memory address space on this bus
	 */
	for(tptr = table+ntb; tptr < mtb; tptr++) {
		hole = tptr->siz;
		if(tptr->bar == -1)
			hole = 1<<20;
		mema = (mema+hole-1) & ~(hole-1);

		p = tptr->dev;
		if(tptr->bar == -1)
			p->mema.bar = mema;
		else {
			p->pcr |= MEMen;
			p->mem[tptr->bar].bar = mema;
			if(wrreg)
				pcicfgrw32(p->tbdf, PciBAR0+(tptr->bar*4), mema, 0);
		}
		mema += tptr->siz;
	}

	*pmema = mema;
	*pioa = ioa;
	free(table);

	if(wrreg == 0)
		return;

	/*
	 * Finally set all the bridge addresses & registers
	 */
	for(p = root; p != nil; p = p->link) {
		if(p->bridge == nil) {
			pcicfgrw8(p->tbdf, PciLTR, 64, 0);

			p->pcr |= MASen;
			pcicfgrw32(p->tbdf, PciPCR, p->pcr, 0);
			continue;
		}

		base = p->ioa.bar;
		limit = base+p->ioa.size-1;
		v = pcicfgrw32(p->tbdf, PciBAR3, 0, 1);
		v = (v&0xFFFF0000)|(limit & 0xF000)|((base & 0xF000)>>8);
		pcicfgrw32(p->tbdf, PciBAR3, v, 0);
		v = (limit & 0xFFFF0000)|(base>>16);
		pcicfgrw32(p->tbdf, 0x30, v, 0);

		base = p->mema.bar;
		limit = base+p->mema.size-1;
		v = (limit & 0xFFF00000)|((base & 0xFFF00000)>>16);
		pcicfgrw32(p->tbdf, PciBAR4, v, 0);

		/*
		 * Disable memory prefetch
		 */
		pcicfgrw32(p->tbdf, PciBAR5, 0x0000FFFF, 0);
		pcicfgrw8(p->tbdf, PciLTR, 64, 0);

		/*
		 * Enable the bridge
		 */
		v = 0xFFFF0000 | IOen | MEMen | MASen;
		pcicfgrw32(p->tbdf, PciPCR, v, 0);

		sioa = p->ioa.bar;
		smema = p->mema.bar;
		pcibusmap(p->bridge, &smema, &sioa, 1);
	}
}

static int
pcilscan(int bno, Pcidev** list)
{
	Pcidev *p, *head, *tail;
	int dno, fno, i, hdt, l, maxfno, maxubn, rno, sbn, tbdf, ubn;

	maxubn = bno;
	head = nil;
	tail = nil;
	for(dno = 0; dno <= pcimaxdno; dno++){
		maxfno = 0;
		for(fno = 0; fno <= maxfno; fno++){
			/*
			 * For this possible device, form the
			 * bus+device+function triplet needed to address it
			 * and try to read the vendor and device ID.
			 * If successful, allocate a device struct and
			 * start to fill it in with some useful information
			 * from the device's configuration space.
			 */
			tbdf = MKBUS(BusPCI, bno, dno, fno);
			l = pcicfgrw32(tbdf, PciVID, 0, 1);
			if(l == 0xFFFFFFFF || l == 0)
				continue;
			p = malloc(sizeof(*p));
			p->tbdf = tbdf;
			p->vid = l;
			p->did = l>>16;

			if(pcilist != nil)
				pcitail->list = p;
			else
				pcilist = p;
			pcitail = p;

			p->rid = pcicfgr8(p, PciRID);
			p->ccrp = pcicfgr8(p, PciCCRp);
			p->ccru = pcicfgr8(p, PciCCRu);
			p->ccrb = pcicfgr8(p, PciCCRb);
			p->pcr = pcicfgr32(p, PciPCR);

			p->intl = pcicfgr8(p, PciINTL);

			/*
			 * If the device is a multi-function device adjust the
			 * loop count so all possible functions are checked.
			 */
			hdt = pcicfgr8(p, PciHDT);
			if(hdt & 0x80)
				maxfno = MaxFNO;

			/*
			 * If appropriate, read the base address registers
			 * and work out the sizes.
			 */
			switch(p->ccrb) {
			case 0x01:		/* mass storage controller */
			case 0x02:		/* network controller */
			case 0x03:		/* display controller */
			case 0x04:		/* multimedia device */
			case 0x06:		/* bridge device */
			case 0x07:		/* simple comm. controllers */
			case 0x08:		/* base system peripherals */
			case 0x09:		/* input devices */
			case 0x0A:		/* docking stations */
			case 0x0B:		/* processors */
			case 0x0C:		/* serial bus controllers */
				if((hdt & 0x7F) != 0)
					break;
				rno = PciBAR0 - 4;
				for(i = 0; i < nelem(p->mem); i++) {
					rno += 4;
					p->mem[i].bar = pcicfgr32(p, rno);
					p->mem[i].size = pcibarsize(p, rno);
				}
				break;

			case 0x00:
			case 0x05:		/* memory controller */
			default:
				break;
			}

			if(head != nil)
				tail->link = p;
			else
				head = p;
			tail = p;
		}
	}

	*list = head;
	for(p = head; p != nil; p = p->link){
		/*
		 * Find PCI-PCI bridges and recursively descend the tree.
		 */
		if(p->ccrb != 0x06 || p->ccru != 0x04)
			continue;

		/*
		 * If the secondary or subordinate bus number is not
		 * initialised try to do what the PCI BIOS should have
		 * done and fill in the numbers as the tree is descended.
		 * On the way down the subordinate bus number is set to
		 * the maximum as it's not known how many buses are behind
		 * this one; the final value is set on the way back up.
		 */
		sbn = pcicfgr8(p, PciSBN);
		ubn = pcicfgr8(p, PciUBN);

		if(sbn == 0 || ubn == 0) {
			sbn = maxubn+1;
			/*
			 * Make sure memory, I/O and master enables are
			 * off, set the primary, secondary and subordinate
			 * bus numbers and clear the secondary status before
			 * attempting to scan the secondary bus.
			 *
			 * Initialisation of the bridge should be done here.
			 */
			pcicfgw32(p, PciPCR, 0xFFFF0000);
			l = (MaxUBN<<16)|(sbn<<8)|bno;
			pcicfgw32(p, PciPBN, l);
			pcicfgw16(p, PciSPSR, 0xFFFF);
			maxubn = pcilscan(sbn, &p->bridge);
			l = (maxubn<<16)|(sbn<<8)|bno;

			pcicfgw32(p, PciPBN, l);
		}
		else {
			maxubn = ubn;
			pcilscan(sbn, &p->bridge);
		}
	}

	return maxubn;
}

int
pciscan(int bno, Pcidev **list)
{
	int ubn;

	qlock(&pcicfginitlock);
	ubn = pcilscan(bno, list);
	qunlock(&pcicfginitlock);
	return ubn;
}

static void
pcicfginit(void)
{
	char *p;
	int bno;
	Pcidev **list;
	ulong mema, ioa;

	qlock(&pcicfginitlock);
	if(pcicfgmode != -1)
		goto out;

	//pcimmap();

	pcicfgmode = 1;
	pcimaxdno = 31;

//	fmtinstall('T', tbdffmt);

	if(p = getconf("*pcimaxbno"))
		pcimaxbno = strtoul(p, 0, 0);
	if(p = getconf("*pcimaxdno"))
		pcimaxdno = strtoul(p, 0, 0);


	list = &pciroot;
	for(bno = 0; bno <= pcimaxbno; bno++) {
		int sbno = bno;
		bno = pcilscan(bno, list);

		while(*list)
			list = &(*list)->link;

		if (sbno == 0) {
			Pcidev *pci;

			/*
			  * If we have found a PCI-to-Cardbus bridge, make sure
			  * it has no valid mappings anymore.  
			  */
			pci = pciroot;
			while (pci) {
				if (pci->ccrb == 6 && pci->ccru == 7) {
					ushort bcr;

					/* reset the cardbus */
					bcr = pcicfgr16(pci, PciBCR);
					pcicfgw16(pci, PciBCR, 0x40 | bcr);
					delay(50);
				}
				pci = pci->link;
			}
		}
	}

	if(pciroot == nil)
		goto out;

	/*
	 * Work out how big the top bus is
	 */
	mema = 0;
	ioa = 0;
	pcibusmap(pciroot, &mema, &ioa, 0);

	DBG("Sizes: mem=%8.8lux size=%8.8lux io=%8.8lux\n",
		mema, pcimask(mema), ioa);

	/*
	 * Align the windows and map it
	 */
	ioa = 0x1000;
	mema = 0;

	pcilog("Mask sizes: mem=%lux io=%lux\n", mema, ioa);

	pcibusmap(pciroot, &mema, &ioa, 1);
	DBG("Sizes2: mem=%lux io=%lux\n", mema, ioa);

out:
	qunlock(&pcicfginitlock);
}

static int
pcicfgrw8(int tbdf, int rno, int data, int read)
{
	int o, x;

	if(pcicfgmode == -1)
		pcicfginit();

	x = -1;
	if(BUSDNO(tbdf) > pcimaxdno)
		return x;

	lock(&pcicfglock);
	o = rno & 0x03;
	rno &= ~0x03;
	pcicfg->addr = 0x80000000|BUSBDF(tbdf)|rno;
	eieio();
	if(read)
		x = pcicfg->data.b[o];	/* TO DO: perhaps o^3 */
	else
		pcicfg->data.b[o] = data;
	eieio();
	pcicfg->addr = 0;
	unlock(&pcicfglock);

	return x;
}

int
pcicfgr8(Pcidev* pcidev, int rno)
{
	return pcicfgrw8(pcidev->tbdf, rno, 0, 1);
}

void
pcicfgw8(Pcidev* pcidev, int rno, int data)
{
	pcicfgrw8(pcidev->tbdf, rno, data, 0);
}

static int
pcicfgrw16(int tbdf, int rno, int data, int read)
{
	int o, x;

	if(pcicfgmode == -1)
		pcicfginit();

	x = -1;
	if(BUSDNO(tbdf) > pcimaxdno)
		return x;

	lock(&pcicfglock);
	o = (rno >> 1) & 1;
	rno &= ~0x03;
	pcicfg->addr = 0x80000000|BUSBDF(tbdf)|rno;
	eieio();
	if(read)
		x = pcicfg->data.s[o];
	else
		pcicfg->data.s[o] = data;
	eieio();
	pcicfg->addr = 0;
	unlock(&pcicfglock);

	return x;
}

int
pcicfgr16(Pcidev* pcidev, int rno)
{
	return pcicfgrw16(pcidev->tbdf, rno, 0, 1);
}

void
pcicfgw16(Pcidev* pcidev, int rno, int data)
{
	pcicfgrw16(pcidev->tbdf, rno, data, 0);
}

static int
pcicfgrw32(int tbdf, int rno, int data, int read)
{
	int x;

	if(pcicfgmode == -1)
		pcicfginit();

	x = -1;
	if(BUSDNO(tbdf) > pcimaxdno)
		return x;

	lock(&pcicfglock);
	rno &= ~0x03;
	pcicfg->addr = 0x80000000|BUSBDF(tbdf)|rno;
	eieio();
	if(read)
		x = pcicfg->data.l;
	else
		pcicfg->data.l = data;
	eieio();
	pcicfg->addr = 0;
	unlock(&pcicfglock);

	return x;
}

int
pcicfgr32(Pcidev* pcidev, int rno)
{
	return pcicfgrw32(pcidev->tbdf, rno, 0, 1);
}

void
pcicfgw32(Pcidev* pcidev, int rno, int data)
{
	pcicfgrw32(pcidev->tbdf, rno, data, 0);
}

Pcidev*
pcimatch(Pcidev* prev, int vid, int did)
{
	if(pcicfgmode == -1)
		pcicfginit();

	if(prev == nil)
		prev = pcilist;
	else
		prev = prev->list;

	while(prev != nil){
		if((vid == 0 || prev->vid == vid)
		&& (did == 0 || prev->did == did))
			break;
		prev = prev->list;
	}
	return prev;
}

Pcidev*
pcimatchtbdf(int tbdf)
{
	Pcidev *pcidev;

	if(pcicfgmode == -1)
		pcicfginit();

	for(pcidev = pcilist; pcidev != nil; pcidev = pcidev->list) {
		if(pcidev->tbdf == tbdf)
			break;
	}
	return pcidev;
}

uchar
pciipin(Pcidev *pci, uchar pin)
{
	if (pci == nil)
		pci = pcilist;

	while (pci) {
		uchar intl;

		if (pcicfgr8(pci, PciINTP) == pin && pci->intl != 0 && pci->intl != 0xff)
			return pci->intl;

		if (pci->bridge && (intl = pciipin(pci->bridge, pin)) != 0)
			return intl;

		pci = pci->list;
	}
	return 0;
}

static void
pcilhinv(Pcidev* p)
{
	int i;
	Pcidev *t;

	if(p == nil) {
		putstrn(PCICONS.output, PCICONS.ptr);
		p = pciroot;
		print("bus dev type vid  did intl memory\n");
	}
	for(t = p; t != nil; t = t->link) {
		print("%d  %2d/%d %.2ux %.2ux %.2ux %.4ux %.4ux %3d  ",
			BUSBNO(t->tbdf), BUSDNO(t->tbdf), BUSFNO(t->tbdf),
			t->ccrb, t->ccru, t->ccrp, t->vid, t->did, t->intl);

		for(i = 0; i < nelem(p->mem); i++) {
			if(t->mem[i].size == 0)
				continue;
			print("%d:%.8lux %d ", i,
				t->mem[i].bar, t->mem[i].size);
		}
		if(t->ioa.bar || t->ioa.size)
			print("ioa:%.8lux %d ", t->ioa.bar, t->ioa.size);
		if(t->mema.bar || t->mema.size)
			print("mema:%.8lux %d ", t->mema.bar, t->mema.size);
		if(t->bridge)
			print("->%d", BUSBNO(t->bridge->tbdf));
		print("\n");
	}
	while(p != nil) {
		if(p->bridge != nil)
			pcilhinv(p->bridge);
		p = p->link;
	}	
}

void
pcihinv(Pcidev* p)
{
	if(pcicfgmode == -1)
		pcicfginit();
	qlock(&pcicfginitlock);
	pcilhinv(p);
	qunlock(&pcicfginitlock);
}

void
pcishutdown(void)
{
	Pcidev *p;

	if(pcicfgmode == -1)
		pcicfginit();

	for(p = pcilist; p != nil; p = p->list){
		/* don't mess with the bridges */
		if(p->ccrb == 0x06)
			continue;
		pciclrbme(p);
	}
}

void
pcisetbme(Pcidev* p)
{
	int pcr;

	pcr = pcicfgr16(p, PciPCR);
	pcr |= MASen;
	pcicfgw16(p, PciPCR, pcr);
}

void
pciclrbme(Pcidev* p)
{
	int pcr;

	pcr = pcicfgr16(p, PciPCR);
	pcr &= ~MASen;
	pcicfgw16(p, PciPCR, pcr);
}

/*
 * 405EP specific
 */

typedef struct Pciplbregs Pciplbregs;
struct Pciplbregs {
	struct {
		ulong	la;
		ulong	ma;
		ulong	pcila;
		ulong	pciha;
	} pmm[3];
	struct {
		ulong	ms;
		ulong	la;
	} ptm[2];
};

enum {	/* mask/attribute registers */
	Pre=	1<<1,	/* enable prefetching (PMM only) */
	Ena=	1<<0,	/* enable PLB to PCI map (PMM); enable PCI to PLB (PTM) */
};

enum {	/* DCR */
	Cpc0Srr=	0xF6,	/* PCI soft reset */
	  Rpci=	1<<18,	/* reset PCI bridge */
	Cpc0PCI=	0xF9,	/* PCI control */
	  Spe=	1<<4,	/* PCIINT/WE select */
	  Hostcfgen=	1<<3,	/* enable host config */
	  Arben=	1<<1,	/* enable internal arbiter */
};

enum {
	/* PciPCR */
	Se=	1<<8,	/* enable PCISErr# when parity error detected as target */
	Per=	1<<6,	/* enable PERR# on parity errors */
	Me=	1<<2,	/* enable bridge-to-master cycles */
	Ma=	1<<1,	/* enable memory access (when PCI memory target) */

	/* PciPSR */
	Depe=	1<<15,	/* parity error */
	Sse=		1<<14,	/* signalled system error */
	Rma=	1<<13,	/* received master abort */
	Rta=		1<<12,	/* received target abort */
	Sta=		1<<11,	/* signalled target abort */
	Dpe=	1<<8,	/* data parity error */
	F66C=	1<<5,	/* 66MHz capable */

	/* PciBARn */
	Pf=		1<<3,	/* prefetchable */
};

/*
pmm 0: la=00000080 ma=010000c0 pcila=00000080 pciha=00000000
pmm 1: la=00000000 ma=00000000 pcila=00000000 pciha=00000000
pmm 2: la=00000000 ma=00000000 pcila=00000000 pciha=00000000
ptm 0: ms=01000080 la=00000000
ptm 1: ms=00000000 la=00000000
*/

static void
pcidumpdev(ulong tbdf)
{
	int i;

	for(i=0; i<0x68; i+=4)
		iprint("[%.2x]=%.8ux\n", i, pcicfgrw32(tbdf, i, 0, 1));
}

void
pcimapinit(void)
{
	Pciplbregs *pm;
	int i, bridge, psr;

	pm = kmapphys(nil, PHYSPCIBCFG, sizeof(Pciplbregs), TLBWR | TLBI | TLBG, TLBLE);
	if(0){
		/* see what the bootstrap left */
		iprint("PCI:\n");
		for(i=0; i<3; i++)
			iprint("pmm %d: la=%.8lux ma=%.8lux pcila=%.8lux pciha=%.8lux\n",
				i, pm->pmm[i].la, pm->pmm[i].ma, pm->pmm[i].pcila, pm->pmm[i].pciha);
		for(i=0; i<2; i++)
			iprint("ptm %d: ms=%.8lux la=%.8lux\n",
				i, pm->ptm[i].ms, pm->ptm[i].la);
	}
	putdcr(Cpc0Srr, Rpci);
	delay(1);
	putdcr(Cpc0Srr, 0);

	kmapphys((void*)PHYSPCIIO0, PHYSPCIIO0, 64*1024, TLBWR | TLBI | TLBG, TLBLE);
	pcicfg = kmapphys(nil, PHYSPCIADDR, sizeof(Pcicfg), TLBWR | TLBI | TLBG, TLBLE);
	pciack = kmapphys(nil, PHYSPCIACK, sizeof(ulong), TLBWR | TLBI | TLBG, TLBLE);
	eieio();

	/*
	 * PLB addresses between PHYSPCIBRIDGE and PHYSPCIBRIDGE+64Mb
	 * are mapped to PCI memory at 0.
	 */
	pm->pmm[0].ma = 0;	/* disable during update */
	eieio();
	pm->pmm[0].la = PHYSPCIBRIDGE;
	pm->pmm[0].pcila = 0;
	pm->pmm[0].pciha = 0;
	eieio();
	pm->pmm[0].ma = 0xFC000000 | Ena;	/* enable prefetch? */
	for(i=1; i<3; i++)
		pm->pmm[i].ma = 0;	/* disable the others */
	eieio();
	pcimem = kmapphys((void*)PHYSPCIBRIDGE, PHYSPCIBRIDGE, 0x4000000, TLBWR | TLBI | TLBG, TLBLE);

	/*
	 * addresses presented by a PCI device between PCIWINDOW and PCIWINDOW+1Gb
	 * are mapped to physical memory.
 	*/
	pm->ptm[0].ms = 0;
	eieio();
	pm->ptm[0].la = PCIWINDOW;
	eieio();
	pm->ptm[0].ms = 0xC0000000 | Ena;	/* always enabled by hardware */
	pm->ptm[1].ms = 0;
	eieio();

	iprint("cpc0pci=%.8lux\n", getdcr(Cpc0PCI));

	/*
	 * the 405ep's pci bridge contains IBM vendor & devid, but
	 * ppcboot rather annoyingly clears them; put them back.
	 */
	pcicfgmode = 1;
	pcimaxdno = 31;

	bridge = MKBUS(BusPCI, 0, 0, 0);
	pcicfgrw16(bridge, PciPCR, Me | Ma, 0);
	pcicfgrw16(bridge, PciVID, 0x1014, 0);
	pcicfgrw16(bridge, PciDID, 0x0156, 0);
	pcicfgrw8(bridge, PciCCRb, 0x06, 0);	/* bridge */
	pcicfgrw32(bridge, PciBAR1, Pf, 0);
	psr = pcicfgrw16(bridge, PciPSR, 0, 1);
	if(m->pcihz >= 66000000)
		psr |= F66C;	/* 66 MHz */
	pcicfgrw16(bridge, PciPSR, psr, 0);	/* reset error status */
	if(0){
		iprint("pci bridge':\n");
		pcidumpdev(bridge);
	}

	pcicfgmode = -1;
}
