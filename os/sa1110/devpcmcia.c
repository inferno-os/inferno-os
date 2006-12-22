#include "u.h"
#include "../port/lib.h"
#include "mem.h"
#include "dat.h"
#include "fns.h"
#include "io.h"
#include "../port/error.h"

int pcmdebug=0;
#define DPRINT if(pcmdebug)iprint
#define DPRINT1 if(pcmdebug > 1)iprint
#define DPRINT2 if(pcmdebug > 2)iprint
#define PCMERR(x)	pce(x);

enum
{
	Qdir,
	Qmem,
	Qattr,
	Qctl,
};

#define SLOTNO(c)	(((ulong)c->qid.path>>8)&0xff)
#define TYPE(c)		((ulong)c->qid.path&0xff)
#define QID(s,t)	(((s)<<8)|(t))

/*
 *  Support for 2 card slots usng StrongArm pcmcia support.
 *
 */
enum
{
	/*
	 *  configuration registers - they start at an offset in attribute
	 *  memory found in the CIS.
	 */
	Rconfig=	0,
	 Creset=	 (1<<7),	/*  reset device */
	 Clevel=	 (1<<6),	/*  level sensitive interrupt line */

};


enum	{
	Maxctab=	8,	/* maximum configuration table entries */
	Maxslot=	2
};

static struct {
	Ref;
} pcmcia;

static PCMslot	slot[Maxslot];
static PCMslot *lastslot ;
static	int	nslot = Maxslot;

static void	slotdis(PCMslot *);
static void	pcmciaintr(Ureg*, void*);
static void	pcmciareset(void);
static int	pcmio(int, ISAConf*);
static long	pcmread(int, int, void*, long, ulong);
static long	pcmwrite(int, int, void*, long, ulong);
static void slottiming(int, int, int, int, int);
static void slotmap(int, ulong, ulong, ulong);

static void pcmciadump(PCMslot*);

static ulong GPIOrdy[2];
static ulong GPIOeject[2];
static ulong GPIOall[2];

/*
 *  get info about card
 */
static void
slotinfo(PCMslot *pp)
{
	ulong gplr;
	int was;

	gplr = GPIOREG->gplr;
	was = pp->occupied;
	pp->occupied = (gplr & GPIOeject[pp->slotno]) ? 0 : 1;
	pp->busy = (gplr & GPIOrdy[pp->slotno]) ? 0 : 1;
	pp->powered = pcmpowered(pp->slotno);
	pp->battery = 0;
	pp->wrprot = 0;
	if (!was & pp->occupied)
		print("PCMCIA card %d inserted\n", pp->slotno);
	if (was & !pp->occupied)
		print("PCMCIA card %d removed!\n", pp->slotno);
}

/*
 *  enable the slot card
 */
static void
slotena(PCMslot *pp)
{
	if(pp->enabled)
		return;
	DPRINT("Enable slot# %d\n", pp->slotno);
	DPRINT("pcmcia ready %8.8lux\n", GPIOREG->gplr & GPIOrdy[pp->slotno]);

	/* get configuration */
	slotinfo(pp);
	if(pp->occupied){
		if(pp->cisread == 0){
			pcmcisread(pp);
			pp->cisread = 1;
		}
		pp->enabled = 1;
	} else
		slotdis(pp);
}

/*
 *  disable the slot card
 */
static void
slotdis(PCMslot *pp)
{
	if (pp->enabled)
		DPRINT("Disable slot# %d\n", pp->slotno);
	pp->enabled = 0;
	pp->cisread = 0;
}

/*
 *  status change interrupt
 */
static void
pcmciaintr(Ureg*, void*)
{
	uchar was;
	PCMslot *pp;

	if(slot == 0)
		return;
	for(pp = slot; pp < lastslot; pp++){
		was = pp->occupied;
		slotinfo(pp);
		if(0 && !pp->occupied){
			if(was != pp->occupied){
				slotdis(pp);
//				if (pp->special && pp->notify.f)
//					(*pp->notify.f)(ur, pp->notify.a, 1);
			}
		}
	}
}

static void
increfp(PCMslot *pp)
{
	if(up){
		wlock(pp);
		if(waserror()){
			wunlock(pp);
			nexterror();
		}
	}
	if(incref(&pcmcia) == 1){
		pcmpower(pp->slotno, 1);
		pcmreset(pp->slotno);
		delay(500);
	}

	if(incref(&pp->ref) == 1)
		slotena(pp);
	if(up){
		poperror();
		wunlock(pp);
	}
}

static void
decrefp(PCMslot *pp)
{
	if(decref(&pp->ref) == 0)
		slotdis(pp);
	if(decref(&pcmcia) == 0)
		pcmpower(pp->slotno, 0);
}

/*
 *  look for a card whose version contains 'idstr'
 */
int
pcmspecial(char *idstr, ISAConf *isa)
{
	PCMslot *pp;

	pcmciareset();
	for(pp = slot; pp < lastslot; pp++){
		if(pp->special)
			continue;	/* already taken */
		increfp(pp);

		if(pp->occupied)
		if(strstr(pp->verstr, idstr)){
			DPRINT("PCMslot #%d: Found %s - ",pp->slotno, idstr);
			if(isa == 0 || pcmio(pp->slotno, isa) == 0){
				DPRINT("ok.\n");
				pp->special = 1;
				return pp->slotno;
			}
			print("error with isa io for %s\n", idstr);
		}
		decrefp(pp);
	}
	return -1;
}

void
pcmspecialclose(int slotno)
{
	PCMslot *pp;
	int s;

	if(slotno < 0 || slotno >= nslot)
		panic("pcmspecialclose");
	pp = slot + slotno;
	pp->special = 0;	/* Is this OK ? */
	s = splhi();
	GPIOREG->gfer &= ~GPIOrdy[pp->slotno];	/* TO DO: intrdisable */
	GPIOREG->grer &= ~GPIOrdy[pp->slotno];
	splx(s);
	decrefp(pp);
}

static int
pcmgen(Chan *c, char*, Dirtab*, int, int i, Dir *dp)
{
	int slotno;
	Qid qid;
	long len;
	PCMslot *pp;

	if(i == DEVDOTDOT){
		mkqid(&qid, Qdir, 0, QTDIR);
		devdir(c, qid, "#y", 0, eve, 0555, dp);
		return 1;
	}

	if(i>=3*nslot)
		return -1;
	slotno = i/3;
	pp = slot + slotno;
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
	qid.type = QTFILE;
	devdir(c, qid, up->genbuf, len, eve, 0660, dp);
	return 1;
}

static void
pcmciadump(PCMslot *pp)
{
	USED(pp);
}

/*
 *  set up for slot cards
 */
static void
pcmciareset(void)
{
	static int already;
	int slotno, v, rdypin;
	PCMslot *pp;

	if(already)
		return;
	already = 1;
	DPRINT("pcmcia reset\n");

	lastslot = slot;

	nslot = 0;
	for(slotno = 0; slotno < Maxslot; slotno++){
		rdypin = pcmpin(slotno, PCMready);
		if(rdypin < 0)
			break;
		nslot = slotno+1;
		slotmap(slotno, PCMCIAIO(slotno), PCMCIAAttr(slotno), PCMCIAMem(slotno));
		slottiming(slotno, 300, 300, 300, 0);	/* set timing to the default, 300 */
		pp = lastslot++;
		GPIOeject[slotno] = (1<<pcmpin(slotno, PCMeject));
		GPIOrdy[slotno] = (1<<rdypin);
		GPIOall[slotno] = GPIOeject[slotno] | GPIOrdy[slotno];
		GPIOREG->gafr &= ~GPIOall[slotno];
		slotdis(pp);
		intrenable(pcmpin(slotno, PCMeject), pcmciaintr, 0, BusGPIOrising, "pcmcia eject");
		if((v = pcmpin(slotno, PCMstschng)) >= 0)	/* status change interrupt */
			intrenable(v, pcmciaintr, 0, BusGPIOrising, "pcmcia status");
	}
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
pcmciastat(Chan *c, uchar *db, int n)
{
	return devstat(c, db, n, 0, 0, pcmgen);
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
	PCMslot *pp;
	long i;
	uchar *b, *p;

	pp = slot + slotno;
	rlock(pp);
	if(waserror()){
		runlock(pp);
		nexterror();
	}
	if(!pp->occupied)
		error(Eio);
	if(pp->memlen < offset){
		runlock(pp);
		poperror();
		return 0;
	}
	if(pp->memlen < offset + n)
		n = pp->memlen - offset;
	if (attr){
		b = a;
		p = (uchar*)PCMCIAAttr(slotno) + offset;
		for(i=0; i<n; i++){
			if(!pp->occupied)
				error(Eio);
			b[0] = *p;
			i++;
			if(i<n)
				b[1] = 0;
			b += 2;
			p += 2;
		}
	}else
		memmoveb(a, (uchar *)PCMCIAMem(slotno) + offset, n);
	poperror();
	runlock(pp);
	return n;
}

static long
pcmciaread(Chan *c, void *a, long n, vlong offset)
{
	char *cp, *buf;
	ulong p;
	PCMslot *pp;
	int i;

	p = TYPE(c);
	switch(p){
	case Qdir:
		return devdirread(c, a, n, 0, 0, pcmgen);
	case Qmem:
	case Qattr:
		return pcmread(SLOTNO(c), p==Qattr, a, n, offset);
	case Qctl:
		buf = malloc(2048);
		if(buf == nil)
			error(Eio);
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
		if(pp->busy)
			cp += sprint(cp, "busy\n");
		if(pp->enabled && (i = strlen(pp->verstr)) > 0)
			cp += sprint(cp, "verstr %d\n%s\n", i, pp->verstr);
		cp += sprint(cp, "battery lvl %d\n", pp->battery);
		/* DUMP registers here */
		cp += sprint(cp, "mecr 0x%lux\n",
			(SLOTNO(c) ? MEMCFGREG->mecr >> 16 : MEMCFGREG->mecr) & 0x7fff);
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
pcmwrite(int slotno, int attr, void *a, long n, ulong offset)
{
	PCMslot *pp;

	pp = slot + slotno;
	rlock(pp);
	if(waserror()){
		runlock(pp);
		nexterror();
	}
	if(pp->memlen < offset)
		error(Eio);
	if(pp->memlen < offset + n)
		error(Eio);
	memmoveb((uchar *)(attr ? PCMCIAAttr(slotno) : PCMCIAMem(slotno)) + offset, a, n);
	poperror();
	runlock(pp);
	return n;
}

/*
 *  the regions are staticly mapped
 */
static void
slotmap(int slotno, ulong regs, ulong attr, ulong mem)
{
	PCMslot *sp;

	if(slotno >= Maxslot)
		return;

	sp = &slot[slotno];
	sp->slotno = slotno;
	sp->memlen = 64*MB;
	sp->verstr[0] = 0;

	sp->mem = (void*)mem;
	sp->memmap.ca = 0;
	sp->memmap.cea = 64*MB;
	sp->memmap.isa = (ulong)mem;
	sp->memmap.len = 64*MB;
	sp->memmap.attr = 0;

	sp->attr = (void*)attr;
	sp->attrmap.ca = 0;
	sp->attrmap.cea = MB;
	sp->attrmap.isa = (ulong)attr;
	sp->attrmap.len = MB;
	sp->attrmap.attr = 1;

	sp->regs = (void*)regs;
}

PCMmap*
pcmmap(int slotno, ulong, int, int attr)
{
	if(slotno >= nslot)
		panic("pcmmap");
	if(attr)
		return &slot[slotno].attrmap;
	else
		return &slot[slotno].memmap;
}
void
pcmunmap(int, PCMmap*)
{
}

/*
 *  setup card timings
 *    times are in ns
 *    count = ceiling[access-time/(2*3*T)] - 1, where T is a processor cycle
 *
 */
static int
ns2count(int ns)
{
	ulong y;

	/* get 100 times cycle time */
	y = 100000000/(m->cpuhz/1000);

	/* get 10 times ns/(cycle*6) */
	y = (1000*ns)/(6*y);

	/* round up */
	y += 9;
	y /= 10;

	/* subtract 1 */	
	y = y-1;
	if(y < 0)
		y  = 0;
	if(y > 0x1F)
		y = 0x1F;

	return y & 0x1F;
}
static void
slottiming(int slotno, int tio, int tattr, int tmem, int fast)
{
	ulong x;
	MemcfgReg *memconfregs = MEMCFGREG;

	x = ns2count(tio) << 0;
	x |= ns2count(tattr) << 5;
	x |= ns2count(tmem) << 10;
	if(fast)
		x |= 1<<15;
	if(slotno == 0){
		x |= memconfregs->mecr & 0xffff0000;
	} else {
		x <<= 16;
		x |= memconfregs->mecr & 0xffff;
	}
	memconfregs->mecr = x;
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

		if(strncmp(buf, "vpp", 3) == 0)
			pcmsetvpp(pp->slotno, atoi(buf+3));
		break;
	case Qmem:
	case Qattr:
		pp = slot + SLOTNO(c);
		if(pp->occupied == 0 || pp->enabled == 0)
			error(Eio);
		n = pcmwrite(SLOTNO(c), p == Qattr, a, n, offset);
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
	devinit,
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
pce(char *s)
{
	USED(s);
	DPRINT("pcmio failed: %s\n", s);
	return -1;
}

static int
pcmio(int slotno, ISAConf *isa)
{
	uchar *p;
	PCMslot *pp;
	int i, index;
	char *cp;

	if(slotno >= nslot)
		return PCMERR("bad slot#");
	pp = slot + slotno;

	if(!pp->occupied)
		return PCMERR("empty slot");

	index = 0;
	if(pp->def)
		index = pp->def->index;
	for(i = 0; i < isa->nopt; i++){
		if(strncmp(isa->opt[i], "index=", 6))
			continue;
		index = strtol(&isa->opt[i][6], &cp, 0);
		if(cp == &isa->opt[i][6] || index < 0 || index >= pp->nctab)
			return PCMERR("bad index");
		break;
	}
	/* only touch Rconfig if it is present */
	if(pp->cfg[0].cpresent & (1<<Rconfig)){
		p = (uchar*)(PCMCIAAttr(slotno) + pp->cfg[0].caddr + Rconfig);
		*p = index;
		delay(5);
	}
	isa->port = (ulong)pp->regs;
	isa->mem = (ulong)pp->mem;
	isa->irq = pcmpin(pp->slotno, PCMready);
	isa->itype = BusGPIOfalling;
	return 0;
}

int
inb(ulong p)
{
	return *(uchar*)p;
}

int
ins(ulong p)
{
	return *(ushort*)p;
}

ulong
inl(ulong p)
{
	return *(ulong*)p;
}

void
outb(ulong p, int v)
{
	*(uchar*)p = v;
}

void
outs(ulong p, int v)
{
	*(ushort*)p = v;
}

void
outl(ulong p, ulong v)
{
	*(ulong*)p = v;
}

void
inss(ulong p, void* buf, int ns)
{
	ushort *addr;

	addr = (ushort*)buf;
	for(;ns > 0; ns--)
		*addr++ = *(ushort*)p;
}

void
outss(ulong p, void* buf, int ns)
{
	ushort *addr;

	addr = (ushort*)buf;
	for(;ns > 0; ns--)
		*(ushort*)p = *addr++;
}

void
insb(ulong p, void* buf, int ns)
{
	uchar *addr;

	addr = (uchar*)buf;
	for(;ns > 0; ns--)
		*addr++ = *(uchar*)p;
}

void
outsb(ulong p, void* buf, int ns)
{
	uchar *addr;

	addr = (uchar*)buf;
	for(;ns > 0; ns--)
		*(uchar*)p = *addr++;
}
