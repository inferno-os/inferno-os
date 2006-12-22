#include "u.h"
#include "../port/lib.h"
#include "mem.h"
#include "dat.h"
#include "fns.h"
#include "io.h"
#include "../port/error.h"

/*
 *  MPC821/3 PCMCIA driver (prototype)
 *
 * unlike the i82365 adapter, there isn't an offset register:
 * card addresses are simply the lower order 26 bits of the host address.
 *
 * to do:
 *	split allocation of memory/attrib (all 26 bits valid) and io space (typically 10 or 12 bits)
 *	correct config
 *	interrupts and i/o space access
 *	DMA?
 *	power control
 */

enum
{
	Maxctlr=	1,
	Maxslot=	2,
	Slotashift=	16,

	/* pipr */
	Cbvs1=	1<<15,
	Cbvs2=	1<<14,
	Cbwp=	1<<13,
	Cbcd2=	1<<12,
	Cbcd1=	1<<11,
	Cbbvd2=	1<<10,
	Cbbvd1=	1<<9,
	Cbrdy=	1<<8,

	/* pscr and per */
	Cbvs1_c=	1<<15,
	Cbvs2_c=	1<<14,
	Cbwp_c=	1<<13,
	Cbcd2_c=	1<<12,
	Cbcd1_c=	1<<11,
	Cbbvd2_c=	1<<10,
	Cbbvd1_c=	1<<9,
	Cbrdy_l=	1<<7,
	Cbrdy_h=	1<<6,
	Cbrdy_r=	1<<5,
	Cbrdy_f=	1<<4,

	/* pgcr[n] */
	Cbdreq_int=	0<<14,
	Cbdreq_iois16=	2<<14,
	Cbdreq_spkr=	3<<14,
	Cboe=	1<<7,
	Cbreset=	1<<6,

	/* porN */
	Rport8=	0<<6,
	Rport16=	1<<6,
	Rmtype=	7<<3,	/* memory type field */
	 Rmem=	0<<3,	/* common memory space */
	 Rattrib=	2<<3,	/* attribute space */
	 Rio=		3<<3,
	 Rdma=	4<<3,	/* normal DMA */
	 Rdmalx=	5<<3,	/* DMA, last transaction */
	 RA22_23= 6<<3,	/* ``drive A22 and A23 signals on CE2 and CE1'' */
	RslotB=	1<<2,	/* select slot B (always, on MPC823) */
	Rwp=	1<<1,	/* write protect */
	Rvalid=	1<<0,	/* region valid */

	Nmap=		8,		/* max number of maps to use */

	/*
	 *  configuration registers - they start at an offset in attribute
	 *  memory found in the CIS.
	 */
	Rconfig=	0,
	 Creset=	 (1<<7),	/*  reset device */
	 Clevel=	 (1<<6),	/*  level sensitive interrupt line */
	Rccsr=	2,
	 Ciack	= (1<<0),
	 Cipend	= (1<<1),
	 Cpwrdown=	(1<<2),
	 Caudioen=	(1<<3),
	 Ciois8=	(1<<5),
	 Cchgena=	(1<<6),
	 Cchange=	(1<<7),
	Rpin=	4,	/* pin replacement register */
	Rscpr=	6,	/* socket and copy register */
	Riob0=	10,
	Riob1=	12,
	Riob2=	14,
	Riob3=	16,
	Riolim=	18,

	Maxctab=	8,		/* maximum configuration table entries */
	MaxCIS = 8192,		/* maximum CIS size in bytes */
	Mgran = 8192,		/* maximum size of reads and writes */

	Statusbounce=20,	/* msec debounce time */
};

typedef struct Ctlr Ctlr;

/* a controller (there's only one) */
struct Ctlr
{
	int	dev;
	int	nslot;

	/* memory maps */
	Lock	mlock;		/* lock down the maps */
	PCMmap	mmap[Nmap];	/* maps */

	/* IO port allocation */
	ulong	nextport;
};
static Ctlr controller[Maxctlr];

static PCMslot	*slot;
static PCMslot	*lastslot;
static int	nslot;

static	Map	pcmmapv[Nmap+1];
static	RMap	pcmmaps = {"PCMCIA mappings"};

static void	pcmciaintr(Ureg*, void*);
static void	pcmciareset(void);
static int	pcmio(int, ISAConf*);
static long	pcmread(int, int, void*, long, ulong);
static long	pcmwrite(int, int, void*, long, ulong);
static void	slotdis(PCMslot*);

static ulong pcmmalloc(ulong, long);
static void	pcmfree(ulong, long);
static void pcmciaproc(void*);

static void pcmciadump(PCMslot*);

/*
 *  get info about card
 */
static void
slotinfo(PCMslot *pp)
{
	ulong pipr;

	pipr = (m->iomem->pipr >> pp->slotshift) & 0xFF00;
print("pipr=%8.8lux/%lux\n", m->iomem->pipr, pipr);
	pp->v3_3 = (pipr&Cbvs1)!=0;
	pp->voltage = (((pipr & Cbvs2)!=0)<<1) | ((pipr & Cbvs1)!=0);
	pp->occupied = (pipr&(Cbcd1|Cbcd2))==0;
	pp->powered = pcmpowered(pp->slotno);
	pp->battery = (pipr & (Cbbvd1|Cbbvd2))>>9;
	pp->wrprot = (pipr&Cbwp)!=0;
	pp->busy = (pipr&Cbrdy)==0;
}

static void
pcmdelay(int ms)
{
	if(up == nil)
		delay(ms);
	else
		tsleep(&up->sleep, return0, nil, ms);
}

/*
 *  enable the slot card
 */
static void
slotena(PCMslot *pp)
{
	IMM *io;

	if(pp->enabled)
		return;
	m->iomem->pgcr[pp->slotno] &= ~Cboe;
	pcmpower(pp->slotno, 1);
	eieio();
	pcmdelay(300);
	io = m->iomem;
	io->pgcr[pp->slotno] |= Cbreset;	/* active high */
	eieio();
	pcmdelay(100);
	io->pgcr[pp->slotno] &= ~Cbreset;
	eieio();
	pcmdelay(500);	/* ludicrous delay */

	/* get configuration */
	slotinfo(pp);
	if(pp->occupied){
		if(pp->cisread == 0){
			pcmcisread(pp);
			pp->cisread = 1;
		}
		pp->enabled = 1;
	} else{
		print("empty slot\n");
		slotdis(pp);
	}
}

/*
 *  disable the slot card
 */
static void
slotdis(PCMslot *pp)
{
	int i;
	Ctlr *ctlr;
	PCMmap *pm;

iprint("slotdis %d\n", pp->slotno);
	pcmpower(pp->slotno, 0);
	m->iomem->pgcr[pp->slotno] |= Cboe;
	ctlr = pp->ctlr;
	for(i = 0; i < nelem(ctlr->mmap); i++){
		pm = &ctlr->mmap[i];
		if(m->iomem->pcmr[i].option & Rvalid && pm->slotno == pp->slotno)
			pcmunmap(pp->slotno, pm);
	}
	pp->enabled = 0;
	pp->cisread = 0;
}

static void
pcmciardy(Ureg *ur, void *a)
{
	PCMslot *pp;
	ulong w;

	pp = a;
	w = (m->iomem->pipr >> pp->slotshift) & 0xFF00;
	if(pp->occupied && (w & Cbrdy) == 0){ /* interrupt */
print("PCM.%dI#%lux|", pp->slotno, w);
		if(pp->intr.f != nil)
			pp->intr.f(ur, pp->intr.arg);
	}
}

void
pcmintrenable(int slotno, void (*f)(Ureg*, void*), void *arg)
{
	PCMslot *pp;
	IMM *io;
	char name[KNAMELEN];

	if(slotno < 0 || slotno >= nslot)
		panic("pcmintrenable");
	snprint(name, sizeof(name), "pcmcia.irq%d", slotno);
	io = ioplock();
	pp = slot+slotno;
	pp->intr.f = f;
	pp->intr.arg = arg;
	intrenable(PCMCIAio, pcmciardy, pp, BUSUNKNOWN, name);
	io->per |= Cbrdy_l;	/* assumes used for irq, not rdy; assumes level interrupt always right */
	iopunlock();
}

void
pcmintrdisable(int slotno, void (*f)(Ureg*, void*), void *arg)
{
	PCMslot *pp;
	IMM *io;
	char name[KNAMELEN];

	if(slotno < 0 || slotno >= nslot)
		panic("pcmintrdisable");
	snprint(name, sizeof(name), "pcmcia.irq%d", slotno);
	io = ioplock();
	pp = slot+slotno;
	if(pp->intr.f == f && pp->intr.arg == arg){
		pp->intr.f = nil;
		pp->intr.arg = nil;
		intrdisable(PCMCIAio, pcmciardy, pp, BUSUNKNOWN, name);
		io->per &= ~Cbrdy_l;
	}
	iopunlock();
}

/*
 *  status change interrupt
 *
 * this wakes a monitoring process to read the CIS,
 * rather than holding other interrupts out here.
 */

static Rendez pcmstate;

static int
statechanged(void *a)
{
	PCMslot *pp;
	int in;

	pp = a;
	in = (m->iomem->pipr & (Cbcd1|Cbcd2))==0;
	return in != pp->occupied;
}

static void
pcmciaintr(Ureg*, void*)
{
	ulong events;

	if(slot == 0)
		return;
	events = m->iomem->pscr & (Cbvs1_c|Cbvs2_c|Cbwp_c|Cbcd2_c|Cbcd1_c|Cbbvd2_c|Cbbvd1_c);
	eieio();
	m->iomem->pscr = events;
	/* TO DO: other slot */
iprint("PCM: #%lux|", events);
iprint("pipr=#%lux|", m->iomem->pipr & 0xFF00);
	wakeup(&pcmstate);
}

static void
pcmciaproc(void*)
{
	ulong csc;
	PCMslot *pp;
	int was;

	for(;;){
		sleep(&pcmstate, statechanged, slot+1);
		tsleep(&up->sleep, return0, nil, Statusbounce);
		/*
		 * voltage change 1,2
		 * write protect change
		 * card detect 1,2
		 * battery voltage 1 change (or SPKR-bar)
		 * battery voltage 2 change (or STSCHG-bar)
		 * card B rdy / IRQ-bar low
		 * card B rdy / IRQ-bar high
		 * card B rdy / IRQ-bar rising edge
		 * card B rdy / IRQ-bar falling edge
		 *
		 * TO DO: currently only handle card-present changes
		 */

		for(pp = slot; pp < lastslot; pp++){
			if(pp->memlen == 0)
				continue;
			csc = (m->iomem->pipr>>pp->slotshift) & (Cbcd1|Cbcd2);
			was = pp->occupied;
			slotinfo(pp);
			if(csc == 0 && was != pp->occupied){
				if(!pp->occupied){
					slotdis(pp);
					if(pp->special && pp->notify.f != nil)
						pp->notify.f(pp->notify.arg, 1);
				}
			}
		}
	}
}

static uchar greycode[] = {
	0, 1, 3, 2, 6, 7, 5, 4, 014, 015, 017, 016, 012, 013, 011, 010,
	030, 031, 033, 032, 036, 037, 035, 034, 024, 025, 027
};

/*
 *  get a map for pc card region, return corrected len
 */
PCMmap*
pcmmap(int slotno, ulong offset, int len, int attr)
{
	Ctlr *ctlr;
	PCMslot *pp;
	PCMmap *pm, *nm;
	IMM *io;
	int i;
	ulong e, bsize, code, opt;

	if(0)
		print("pcmmap: %d #%lux %d #%x\n", slotno, offset, len, attr);
	pp = slot + slotno;
	if(!pp->occupied)
		return nil;
	if(attr == 1){	/* account for ../port/cis.c's conventions */
		attr = Rattrib;
		if(len <= 0)
			len = MaxCIS*2;	/* TO DO */
	}
	ctlr = pp->ctlr;

	/* convert offset to granularity */
	if(len <= 0)
		len = 1;
	e = offset+len;
	for(i=0;; i++){
		if(i >= nelem(greycode))
			return nil;
		bsize = 1<<i;
		offset &= ~(bsize-1);
		if(e <= offset+bsize)
			break;
	}
	code = greycode[i];
	if(0)
		print("i=%d bsize=%lud code=0%luo\n", i, bsize, code);
	e = offset+bsize;
	len = bsize;

	lock(&ctlr->mlock);

	/* look for an existing map that covers the right area */
	io = m->iomem;
	nm = nil;
	for(i=0; i<Nmap; i++){
		pm = &ctlr->mmap[i];
		if(io->pcmr[i].option & Rvalid &&
		   pm->slotno == slotno &&
		   pm->attr == attr &&
		   offset >= pm->ca && e <= pm->cea){
			pm->ref++;
			unlock(&ctlr->mlock);
			return pm;
		}
		if(nm == 0 && pm->ref == 0)
			nm = pm;
	}
	pm = nm;
	if(pm == nil){
		unlock(&ctlr->mlock);
		return nil;
	}

	/* set up new map */
	pm->isa = pcmmalloc(offset, len);
	if(pm->isa == 0){
		/* address not available: in use, or too much to map */
		unlock(&ctlr->mlock);
		return 0;
	}
	if(0)
		print("mx=%d isa=#%lux\n", (int)(pm - ctlr->mmap), pm->isa);

	pm->len = len;
	pm->ca = offset;
	pm->cea = pm->ca + pm->len;
	pm->attr = attr;
	i = pm - ctlr->mmap;
	io->pcmr[i].option &= ~Rvalid;	/* disable map before changing it */
	io->pcmr[i].base = pm->isa;
	opt = attr;
	opt |= code<<27;
	if((attr&Rmtype) == Rio){
		opt |= 4<<12;	/* PSST */
		opt |= 8<<7;	/* PSL */
		opt |= 2<<16;	/* PSHT */
	}else{
		opt |= 6<<12;	/* PSST */
		opt |= 24<<7;	/* PSL */
		opt |= 8<<16;	/* PSHT */
	}
	if((attr & Rport16) == 0)
		opt |= Rport8;
	if(slotno == 1)
		opt |= RslotB;
	io->pcmr[i].option = opt | Rvalid;
	pm->slotno = slotno;
	pm->ref = 1;

	unlock(&ctlr->mlock);
	return pm;
}

static void
pcmiomap(PCMslot *pp, PCMconftab *ct, int i)
{
	int n, attr;
	Ctlr *ctlr;

	if(0)
		print("pcm iomap #%lux %lud\n", ct->io[i].start, ct->io[i].len);
	if(ct->io[i].len <= 0)
		return;
	if(ct->io[i].start == 0){
		n = 1<<ct->nlines;
		ctlr = pp->ctlr;
		lock(&ctlr->mlock);
		if(ctlr->nextport == 0)
			ctlr->nextport = 0xF000;
		ctlr->nextport = (ctlr->nextport + n - 1) & ~(n-1);
		ct->io[i].start = ctlr->nextport;
		ct->io[i].len = n;
		ctlr->nextport += n;
		unlock(&ctlr->mlock);
	}
	attr = Rio;
	if(ct->bit16)
		attr |= Rport16;
	ct->io[i].map = pcmmap(pp->slotno, ct->io[i].start, ct->io[i].len, attr);
}

void
pcmunmap(int slotno, PCMmap* pm)
{
	int i;
	PCMslot *pp;
	Ctlr *ctlr;

	pp = slot + slotno;
	if(pp->memlen == 0)
		return;
	ctlr = pp->ctlr;
	lock(&ctlr->mlock);
	if(pp->slotno == pm->slotno && --pm->ref == 0){
		i = pm - ctlr->mmap;
		m->iomem->pcmr[i].option = 0;
		m->iomem->pcmr[i].base = 0;
		pcmfree(pm->isa, pm->len);
	}
	unlock(&ctlr->mlock);
}

static void
increfp(PCMslot *pp)
{
	if(incref(pp) == 1)
		slotena(pp);
}

static void
decrefp(PCMslot *pp)
{
	if(decref(pp) == 0)
		slotdis(pp);
}

/*
 *  look for a card whose version contains 'idstr'
 */
int
pcmspecial(char *idstr, ISAConf *isa)
{
	PCMslot *pp;
	extern char *strstr(char*, char*);

	pcmciareset();
	for(pp = slot; pp < lastslot; pp++){
		if(pp->special || pp->memlen == 0)
			continue;	/* already taken */
		increfp(pp);
		if(pp->occupied && strstr(pp->verstr, idstr)){
			print("PCMslot #%d: Found %s - ",pp->slotno, idstr);
			if(isa == 0 || pcmio(pp->slotno, isa) == 0){
				print("ok.\n");
				pp->special = 1;
				return pp->slotno;
			}
			print("error with isa io\n");
		}
		decrefp(pp);
	}
	return -1;
}

void
pcmspecialclose(int slotno)
{
	PCMslot *pp;

	if(slotno >= nslot)
		panic("pcmspecialclose");
	pp = slot + slotno;
	pp->special = 0;
	decrefp(pp);
}

void
pcmnotify(int slotno, void (*f)(void*, int), void* a)
{
	PCMslot *pp;

	if(slotno < 0 || slotno >= nslot)
		panic("pcmnotify");
	pp = slot + slotno;
	if(pp->occupied && pp->special){
		pp->notify.f = f;
		pp->notify.arg = a;
	}
}

/*
 * reserve pcmcia slot address space [addr, addr+size[,
 * returning a pointer to it, or nil if the space was already reserved.
 */
static ulong
pcmmalloc(ulong addr, long size)
{
	return rmapalloc(&pcmmaps, PHYSPCMCIA+addr, size, size);
}

static void
pcmfree(ulong a, long size)
{
	if(a != 0 && size > 0)
		mapfree(&pcmmaps, a, size);
}

enum
{
	Qdir,
	Qmem,
	Qattr,
	Qctl,
};

#define SLOTNO(c)	((c->qid.path>>8)&0xff)
#define TYPE(c)		(c->qid.path&0xff)
#define QID(s,t)	(((s)<<8)|(t))

static int
pcmgen(Chan *c, char*, Dirtab*, int, int i, Dir *dp)
{
	int slotno;
	Qid qid;
	long len;
	PCMslot *pp;

	if(i>=3*nslot)
		return -1;
	slotno = i/3;
	pp = slot + slotno;
	if(pp->memlen == 0)
		return 0;
	len = 0;
	switch(i%3){
	case 0:
		qid.path = QID(slotno, Qmem);
		sprint(up->genbuf, "pcm%dmem", slotno);
		len = pp->memlen;
		break;
	case 1:
		qid.path = QID(slotno, Qattr);
		sprint(up->genbuf, "pcm%dattr", slotno);
		len = pp->memlen;
		break;
	case 2:
		qid.path = QID(slotno, Qctl);
		sprint(up->genbuf, "pcm%dctl", slotno);
		break;
	}
	qid.vers = 0;
	devdir(c, qid, up->genbuf, len, eve, 0660, dp);
	return 1;
}

/*
 * used only when debugging
 */
static void
pcmciadump(PCMslot *)
{
	IMM *io;
	int i;

	io = m->iomem;
	print("pipr #%4.4lux pscr #%4.4lux per #%4.4lux pgcr[1] #%8.8lux\n",
		io->pipr & 0xFFFF, io->pscr & 0xFFFF, io->per & 0xFFFF, io->pgcr[1]);
	for(i=0; i<8; i++)
		print("pbr%d #%8.8lux por%d #%8.8lux\n", i, io->pcmr[i].base, i, io->pcmr[i].option);
}

/*
 *  set up for slot cards
 */
static void
pcmciareset(void)
{
	static int already;
	int i;
	Ctlr *cp;
	IMM *io;
	PCMslot *pp;

	if(already)
		return;
	already = 1;

	cp = controller;
	/* TO DO: set low power mode? ... */

	mapinit(&pcmmaps, pcmmapv, sizeof(pcmmapv));
	mapfree(&pcmmaps, PHYSPCMCIA, PCMCIALEN);

	io = m->iomem;

	for(i=0; i<8; i++){
		io->pcmr[i].option = 0;
		io->pcmr[i].base = 0;
	}

	io->pscr = ~0;	/* reset status */
	/* TO DO: Cboe, Cbreset */
	/* TO DO: two slots except on 823 */
	pcmenable();
	/* TO DO: if the card is there turn on 5V power to keep its battery alive */
	slot = xalloc(Maxslot * sizeof(PCMslot));
	lastslot = slot;
	slot[0].slotshift = Slotashift;
	slot[1].slotshift = 0;
	for(i=0; i<Maxslot; i++){
		pp = &slot[i];
		if(!pcmslotavail(i)){
			pp->memlen = 0;
			continue;
		}
		io->per |= (Cbvs1_c|Cbvs2_c|Cbwp_c|Cbcd2_c|Cbcd1_c|Cbbvd2_c|Cbbvd1_c)<<pp->slotshift;	/* enable status interrupts */
		io->pgcr[i] = (1<<(31-PCMCIAio)) | (1<<(23-PCMCIAstatus));
		pp->slotno = i;
		pp->memlen = 8*MB;
		pp->ctlr = cp;
		//slotdis(pp);
		lastslot = slot;
		nslot = i+1;
	}
	if(1)
		pcmciadump(slot);
	intrenable(PCMCIAstatus, pcmciaintr, cp, BUSUNKNOWN, "pcmcia");
	print("pcmcia reset\n");
}

static void
pcmciainit(void)
{
	kproc("pcmcia", pcmciaproc, nil, 0);
}

static Chan*
pcmciaattach(char *spec)
{
	return devattach('y', spec);
}

static Walkqid*
pcmciawalk(Chan *c, Chan *nc, char **name, int nname)
{
	return devwalk(c, nc, name, nname, 0, 0, pcmgen);
}

static int
pcmciastat(Chan *c, uchar *dp, int n)
{
	return devstat(c, dp, n, 0, 0, pcmgen);
}

static Chan*
pcmciaopen(Chan *c, int omode)
{
	if(c->qid.type & QTDIR){
		if(omode != OREAD)
			error(Eperm);
	} else
		increfp(slot + SLOTNO(c));
	c->mode = openmode(omode);
	c->flag |= COPEN;
	c->offset = 0;
	return c;
}

static void
pcmciaclose(Chan *c)
{
	if(c->flag & COPEN)
		if((c->qid.type & QTDIR) == 0)
			decrefp(slot+SLOTNO(c));
}

/* a memmove using only bytes */
static void
memmoveb(uchar *to, uchar *from, int n)
{
	while(n-- > 0)
		*to++ = *from++;
}

static long
pcmread(int slotno, int attr, void *a, long n, ulong offset)
{
	int i, len;
	PCMmap *m;
	void *ka;
	uchar *ac;
	PCMslot *pp;

	pp = slot + slotno;
	if(pp->memlen < offset)
		return 0;
	if(pp->memlen < offset + n)
		n = pp->memlen - offset;

	ac = a;
	for(len = n; len > 0; len -= i){
		if((i = len) > Mgran)
			i = Mgran;
		m = pcmmap(pp->slotno, offset, i, attr? Rattrib: Rmem);
		if(m == 0)
			error("can't map PCMCIA card");
		if(waserror()){
			if(m)
				pcmunmap(pp->slotno, m);
			nexterror();
		}
		if(offset + len > m->cea)
			i = m->cea - offset;
		else
			i = len;
		ka = (char*)KADDR(m->isa) + (offset - m->ca);
		memmoveb(ac, ka, i);
		poperror();
		pcmunmap(pp->slotno, m);
		offset += i;
		ac += i;
	}

	return n;
}

static long
pcmciaread(Chan *c, void *a, long n, vlong offset)
{
	char *cp, *buf;
	ulong p;
	PCMslot *pp;

	p = TYPE(c);
	switch(p){
	case Qdir:
		return devdirread(c, a, n, 0, 0, pcmgen);
	case Qmem:
	case Qattr:
		return pcmread(SLOTNO(c), p==Qattr, a, n, offset);
	case Qctl:
		buf = malloc(READSTR);
		if(buf == nil)
			error(Enomem);
		if(waserror()){
			free(buf);
			nexterror();
		}
		cp = buf;
		pp = slot + SLOTNO(c);
		if(pp->occupied)
			cp += sprint(cp, "occupied\n");
		if(pp->enabled)
			cp += sprint(cp, "enabled\n");
		if(pp->powered)
			cp += sprint(cp, "powered\n");
		if(pp->configed)
			cp += sprint(cp, "configed\n");
		if(pp->wrprot)
			cp += sprint(cp, "write protected\n");
		if(pp->busy)
			cp += sprint(cp, "busy\n");
		if(pp->v3_3)
			cp += sprint(cp, "3.3v ok\n");
		cp += sprint(cp, "battery lvl %d\n", pp->battery);
		cp += sprint(cp, "voltage select %d\n", pp->voltage);
		/* TO DO: could return pgcr[] values for debugging */
		*cp = 0;
		n = readstr(offset, a, n, buf);
		poperror();
		free(buf);
		break;
	default:
		n=0;
		break;
	}
	return n;
}

static long
pcmwrite(int dev, int attr, void *a, long n, ulong offset)
{
	int i, len;
	PCMmap *m;
	void *ka;
	uchar *ac;
	PCMslot *pp;

	pp = slot + dev;
	if(pp->memlen < offset)
		return 0;
	if(pp->memlen < offset + n)
		n = pp->memlen - offset;

	ac = a;
	for(len = n; len > 0; len -= i){
		if((i = len) > Mgran)
			i = Mgran;
		m = pcmmap(pp->slotno, offset, i, attr? Rattrib: Rmem);
		if(m == 0)
			error("can't map PCMCIA card");
		if(waserror()){
			if(m)
				pcmunmap(pp->slotno, m);
			nexterror();
		}
		if(offset + len > m->cea)
			i = m->cea - offset;
		else
			i = len;
		ka = (char*)KADDR(m->isa) + (offset - m->ca);
		memmoveb(ka, ac, i);
		poperror();
		pcmunmap(pp->slotno, m);
		offset += i;
		ac += i;
	}

	return n;
}

static long
pcmciawrite(Chan *c, void *a, long n, vlong offset)
{
	ulong p;
	PCMslot *pp;
	char buf[32];

	p = TYPE(c);
	switch(p){
	case Qctl:
		if(n >= sizeof(buf))
			n = sizeof(buf) - 1;
		strncpy(buf, a, n);
		buf[n] = 0;
		pp = slot + SLOTNO(c);
		if(!pp->occupied)
			error(Eio);

		/* set vpp on card */
		if(strncmp(buf, "vpp", 3) == 0){
			p = strtol(buf+3, nil, 0);
			pcmsetvpp(pp->slotno, p);
		}
		break;
	case Qmem:
	case Qattr:
		pp = slot + SLOTNO(c);
		if(pp->occupied == 0 || pp->enabled == 0)
			error(Eio);
		n = pcmwrite(pp->slotno, p == Qattr, a, n, offset);
		if(n < 0)
			error(Eio);
		break;
	default:
		error(Ebadusefd);
	}
	return n;
}

Dev pcmciadevtab = {
	'y',
	"pcmcia",

	pcmciareset,
	pcmciainit,
	devshutdown,
	pcmciaattach,
	pcmciawalk,
	pcmciastat,
	pcmciaopen,
	devcreate,
	pcmciaclose,
	pcmciaread,
	devbread,
	pcmciawrite,
	devbwrite,
	devremove,
	devwstat,
};

/*
 *  configure the PCMslot for IO.  We assume very heavily that we can read
 *  configuration info from the CIS.  If not, we won't set up correctly.
 */
static int
pcmio(int slotno, ISAConf *isa)
{
	PCMslot *pp;
	PCMconftab *ct, *et, *t;
	PCMmap *pm;
	uchar *p;
	int irq, i, x;

	irq = isa->irq;
	if(irq == 2)
		irq = 9;

	if(slotno > nslot)
		return -1;
	pp = slot + slotno;

	if(!pp->occupied)
		return -1;

	et = &pp->ctab[pp->nctab];

	/* assume default is right */
	if(pp->def)
		ct = pp->def;
	else
		ct = pp->ctab;
	/* try for best match */
	if(ct->nlines == 0 || ct->io[0].start != isa->port || ((1<<irq) & ct->irqs) == 0){
		for(t = pp->ctab; t < et; t++)
			if(t->nlines && t->io[0].start == isa->port && ((1<<irq) & t->irqs)){
				ct = t;
				break;
			}
	}
	if(ct->nlines == 0 || ((1<<irq) & ct->irqs) == 0){
		for(t = pp->ctab; t < et; t++)
			if(t->nlines && ((1<<irq) & t->irqs)){
				ct = t;
				break;
			}
	}
	if(ct->nlines == 0){
		for(t = pp->ctab; t < et; t++)
			if(t->nlines){
				ct = t;
				break;
			}
	}
print("slot %d: nlines=%d iolen=%lud irq=%d ct->index=%d nport=%d ct->port=#%lux/%lux\n", slotno, ct->nlines, ct->io[0].len, irq, ct->index, ct->nio, ct->io[0].start, isa->port);
	if(ct == et || ct->nlines == 0)
		return -1;
	/* route interrupts */
	isa->irq = irq;
	//wrreg(pp, Rigc, irq | Fnotreset | Fiocard);
	delay(2);

	/* set power and enable device */
	pcmsetvcc(pp->slotno, ct->vcc);
	pcmsetvpp(pp->slotno, ct->vpp1);

	delay(2);	/* could poll BSY during power change */

	for(i=0; i<ct->nio; i++)
		pcmiomap(pp, ct, i);

	if(ct->nio)
		isa->port = ct->io[0].start;

	/* only touch Rconfig if it is present */
	if(pp->cpresent & (1<<Rconfig)){
print("Rconfig present: #%lux\n", pp->caddr+Rconfig);
		/*  Reset adapter */
		pm = pcmmap(slotno, pp->caddr + Rconfig, 1, Rattrib);
		if(pm == nil)
			return -1;

		p = (uchar*)KADDR(pm->isa) + (pp->caddr + Rconfig - pm->ca);

		/* set configuration and interrupt type */
		x = ct->index;
		if((ct->irqtype & 0x20) && ((ct->irqtype & 0x40)==0 || isa->irq>7))
			x |= Clevel;
		*p = x;
		delay(5);

		pcmunmap(pp->slotno, pm);
print("Adapter reset\n");
	}

	return 0;
}
