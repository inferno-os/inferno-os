#include "boot.h"

enum 
{
	Maxhandler=	32+16,		/* max number of interrupt handlers */
};

typedef struct Handler	Handler;
struct Handler
{
	void	(*r)(Ureg*, void*);
	void	*arg;
	Handler	*next;
	int	edge;
};

struct
{
	Handler	*ivec[128];
	Handler	h[Maxhandler];
	int	free;
} halloc;

char	*excname[] = {
	"reserved 0",
	"system reset",
	"machine check",
	"data access",
	"instruction access",
	"external interrupt",
	"alignment",
	"program exception",
	"floating-point unavailable",
	"decrementer",
	"reserved A",
	"reserved B",
	"system call",
	"trace trap",
	"floating point assist",
	"reserved F",
	"software emulation",
	"ITLB miss",
	"DTLB miss",
	"ITLB error",
	"DTLB error",
};

char *regname[]={
	"CAUSE",	"SRR1",
	"PC",		"GOK",
	"LR",		"CR",
	"XER",	"CTR",
	"R0",		"R1",
	"R2",		"R3",
	"R4",		"R5",
	"R6",		"R7",
	"R8",		"R9",
	"R10",	"R11",
	"R12",	"R13",
	"R14",	"R15",
	"R16",	"R17",
	"R18",	"R19",
	"R20",	"R21",
	"R22",	"R23",
	"R24",	"R25",
	"R26",	"R27",
	"R28",	"R29",
	"R30",	"R31",
};

static	void	intr(Ureg*);

void
sethvec(int v, void (*r)(void))
{
	ulong *vp, pa, o;

	if((ulong)r & 3)
		panic("sethvec");
	vp = (ulong*)KADDR(v);
	vp[0] = 0x7c1043a6;	/* MOVW R0, SPR(SPRG0) */
	vp[1] = 0x7c0802a6;	/* MOVW LR, R0 */
	vp[2] = 0x7c1243a6;	/* MOVW R0, SPR(SPRG2) */
	pa = PADDR(r);
	o = pa >> 25;
	if(o != 0 && o != 0x7F){
		/* a branch too far: running from ROM */
		vp[3] = (15<<26)|(pa>>16);	/* MOVW $r&~0xFFFF, R0 */
		vp[4] = (24<<26)|(pa&0xFFFF);	/* OR $r&0xFFFF, R0 */
		vp[5] = 0x7c0803a6;	/* MOVW	R0, LR */
		vp[6] = 0x4e800021;	/* BL (LR) */
	}else
		vp[3] = (18<<26)|(pa&0x3FFFFFC)|3;	/* bla */
}

#define	LEV(n)	(((n)<<1)|1)
#define	IRQ(n)	(((n)<<1)|0)

void
setvec(int v, void (*r)(Ureg*, void*), void *arg)
{
	Handler *h;
	IMM *io;

	if(halloc.free >= Maxhandler)
		panic("out of interrupt handlers");
	v -= VectorPIC;
	h = &halloc.h[halloc.free++];
	h->next = halloc.ivec[v];
	h->r = r;
	h->arg = arg;
	halloc.ivec[v] = h;

	/*
	 * enable corresponding interrupt in SIU/CPM
	 */

	io = m->iomem;
	if(v >= VectorCPIC){
		v -= VectorCPIC;
		io->cimr |= 1<<(v&0x1F);
	}
	else if(v >= VectorIRQ)
		io->simask |= 1<<(31-IRQ(v&7));
	else
		io->simask |= 1<<(31-LEV(v));
}

void
trapinit(void)
{
	int i;
	IMM *io;

	io = m->iomem;
	io->sypcr &= ~(3<<2);	/* disable watchdog (821/823) */
	io->simask = 0;	/* mask all */
	io->siel = ~0;	/* edge sensitive, wake on all */
	io->cicr = 0;	/* disable CPM interrupts */
	io->cipr = ~0;	/* clear all interrupts */
	io->cimr = 0;	/* mask all events */
	io->cicr = (0xE1<<16)|(CPIClevel<<13)|(0x1F<<8);
	io->cicr |= 1 << 7;	/* enable */
	io->tbscrk = KEEP_ALIVE_KEY;
	io->tbscr = 1;	/* TBE */
	io->simask |= 1<<(31-LEV(CPIClevel));	/* CPM's level */
	io->tbk = KEEP_ALIVE_KEY;
	eieio();
	putdec(~0);

	/*
	 * set all exceptions to trap
	 */
	for(i = 0x0; i < 0x3000; i += 0x100)
		sethvec(i, exception);
}

void
dumpregs(Ureg *ur)
{
	int i;
	ulong *l;
	l = &ur->cause;
	for(i=0; i<sizeof regname/sizeof(char*); i+=2, l+=2)
		print("%s\t%.8lux\t%s\t%.8lux\n", regname[i], l[0], regname[i+1], l[1]);
}

void
trap(Ureg *ur)
{
	int c;

	c = ur->cause >> 8;
	switch(c){
	default:
		{extern int predawn; predawn = 1;}
		if(c < 0 || c >= nelem(excname))
			print("exception/interrupt #%x\n", c);
		else
			print("exception %s\n", excname[c]);
		dumpregs(ur);
		/* spllo(); */
		print("^P to reset\n");
		for(;;)
			;

	case 0x09:	/* decrementer */
		clockintr(ur, 0);
		return;

	case 0x05:	/* external interrupt */
		intr(ur);
		break;
	}
}

static void
intr(Ureg *ur)
{
	int b, v;
	Handler *h;
	IMM *io;

	io = m->iomem;
	b = io->sivec>>2;
	v = b>>1;
	if(b & 1) {
		if(v == CPIClevel){
			io->civr = 1;
			eieio();
			v = VectorCPIC+(io->civr>>11);
		}
	}else
		v += VectorIRQ;
	h = halloc.ivec[v];
	if(h == nil){
		for(;;)
			;
		//print("unknown interrupt %d pc=0x%lux\n", v, ur->pc);
		return;
	}
	if(h->edge)
		io->sipend |= 1<<(31-b);
	/*
	 *  call the interrupt handlers
	 */
	do {
		(*h->r)(ur, h->arg);
		h = h->next;
	} while(h != nil);
	if(v >= VectorCPIC)
		io->cisr |= 1<<(v-VectorCPIC);
}
