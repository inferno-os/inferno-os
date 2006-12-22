#include	"u.h"
#include	"../port/lib.h"
#include	"mem.h"
#include	"dat.h"
#include	"fns.h"
#include	"ureg.h"
#include	"io.h"
#include	"../port/error.h"


enum 
{
	Maxhandler=	MaxVector		/* max number of interrupt handlers */
};

typedef struct Handler	Handler;
struct Handler
{
	void	(*r)(Ureg*, void*);
	void	*arg;
	char	name[KNAMELEN];
	Handler	*next;
	ulong	nintr;
	ulong	ticks;
	int	maxtick;
};

struct
{
	Handler	*ivec[MaxVector];
	Handler	h[Maxhandler];
	int	free;
	Handler*	freelist;
} halloc;

Instr BREAK = 0x7fe00008;
int (*breakhandler)(Ureg*, Proc*);

void	kernfault(Ureg*, int);

char *excname[] =
{
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
	"i/o controller interface error",
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
	"reserved 15",
	"reserved 16",
	"reserved 17",
	"reserved 18",
	"reserved 19",
	"reserved 1A",
	"reserved 1B",
	"data breakpoint",
	"instruction breakpoint",
	"peripheral breakpoint",
	"development port",
	/* the following are made up on a program exception */
	"floating point exception",		/* 20: FPEXC */
	"illegal instruction",	/* 21 */
	"privileged instruction",	/* 22 */
	"trap",	/* 23 */
	"illegal operation",	/* 24 */
	"breakpoint",	/* 25 */
};

char *fpcause[] =
{
	"inexact operation",
	"division by zero",
	"underflow",
	"overflow",
	"invalid operation",
};
char	*fpexcname(Ureg*, ulong, char*);
#define FPEXPMASK	0xfff80300		/* Floating exception bits in fpscr */


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

void
sethvec(int v, void (*r)(void))
{
	ulong *vp, pa, o;

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
	dcflush(vp, 8*sizeof(ulong));
}

void
sethvec2(int v, void (*r)(void))
{
	ulong *vp;

	vp = (ulong*)KADDR(v);
	vp[0] = (18<<26)|((ulong)r&~KSEGM)|2;	/* ba */
	dcflush(vp, sizeof(*vp));
}

void
trap(Ureg *ur)
{
	int ecode, s;
	ulong w;
	char buf[ERRMAX];

	ecode = ur->cause >> 8;
	if(ecode < 0 || ecode >= 0x1F)
		ecode = 0x1F;
	switch(ecode){
	case CDEC:
		clockintr(ur);
		preemption(1);
		break;

	case CMCHECK:
	case CDSI:
	case CISI:
	case CIMISS:
	case CDMISS:
	case CITLBE:
	case CDTLBE:
		faultpower(ur);
		break;

	case CEMU:
		if(up == nil)
			goto Default;
		if((ulong)(ur+1) != ur->r1)
			panic("fp emu stack");
		spllo();
		if(waserror()){
			if(up->type == Interp)
				disfault(ur, up->env->errstr);
			panic("%s", up->env->errstr);
		}
		if(fpipower(ur) == 0){
			splhi();
			poperror();
			print("pc=#%lux op=#%8.8lux\n", ur->pc, *(ulong*)ur->pc);
			goto Default;
		}
		poperror();
		break;

	case CPROG:
		if(ur->status & (1<<19)) {
			ecode = 0x20;
			w = ur->pc;
			if(ur->status & (1<<16))
				w += 4;
			if(*(ulong*)w == 0x7fe00008){ /* tw 31,0,0 */
				if(breakhandler){
					s = (*breakhandler)(ur, up);
					if(s == BrkSched){
						if(up){
							up->preempted = 0;
							sched();
							splhi();
						}
					}else if(s == BrkNoSched){
						if(up){
							up->preempted = 1;	/* stop it being preempted until next instruction */
							up->dbgreg = 0;
						}
					}
					break;
				}
				ecode = 0x1D;	/* breakpoint */
			}
		}
		if(ur->status & (1<<18))
			ecode = 0x21;
		if(ur->status & (1<<17))
			ecode = 0x22;
		/* FALL THROUGH */

	Default:
	default:
		if(up && up->type == Interp) {
			spllo();
			snprint(buf, sizeof buf, "sys: trap: %s pc=0x%lux", excname[ecode], ur->pc);
			error(buf);
			break;
		}
		print("kernel %s pc=0x%lux\n", excname[ecode], ur->pc);
		dumpregs(ur);
		dumpstack();
		if(m->machno == 0)
			spllo();
		exit(1);
	}

	splhi();
}

void
spurious(Ureg *ur, void *a)
{
	USED(a);
	print("SPURIOUS interrupt pc=0x%lux cause=0x%lux\n",
		ur->pc, ur->cause);
	panic("bad interrupt");
}

#define	LEV(n)	(((n)<<1)|1)
#define	IRQ(n)	(((n)<<1)|0)

Lock	veclock;

void
trapinit(void)
{
	int i;
	IMM *io;


	io = m->iomem;
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
		sethvec(i, trapvec);

	sethvec(CEI<<8, intrvec);
	//sethvec2(CIMISS<<8, itlbmiss);
	//sethvec2(CDMISS<<8, dtlbmiss);
}

void
intrenable(int v, void (*r)(Ureg*, void*), void *arg, int, char *name)
{
	Handler *h;
	IMM *io;

	v -= VectorPIC;
	if(v < 0 || v >= nelem(halloc.ivec))
		panic("intrenable(%d)", v+VectorPIC);
	ilock(&veclock);
	if((h = halloc.freelist) == nil){
		if(halloc.free >= Maxhandler){
			iunlock(&veclock);
			panic("out of interrupt handlers");
		}
		h = &halloc.h[halloc.free++];
	}else
		halloc.freelist = h->next;
	h->r = r;
	h->arg = arg;
	strncpy(h->name, name, KNAMELEN-1);
	h->name[KNAMELEN-1] = 0;
	h->next = halloc.ivec[v];
	halloc.ivec[v] = h;

	/*
	 * enable corresponding interrupt in SIU/CPM
	 */

	eieio();
	io = m->iomem;
	if(v >= VectorCPIC){
		v -= VectorCPIC;
		io->cimr |= 1<<(v&0x1F);
	}
	else if(v >= VectorIRQ)
		io->simask |= 1<<(31-IRQ(v&7));
	else
		io->simask |= 1<<(31-LEV(v));
	eieio();
	iunlock(&veclock);
}

static void
irqdisable(int v)
{
	IMM *io;

	io = m->iomem;
	if(v >= VectorCPIC){
		v -= VectorCPIC;
		io->cimr &= ~(1<<(v&0x1F));
	}
	else if(v >= VectorIRQ)
		io->simask &= ~(1<<(31-IRQ(v&7)));
	else
		io->simask &= ~(1<<(31-LEV(v)));
}

void
intrdisable(int v, void (*r)(Ureg*, void*), void *arg, int, char *name)
{
	Handler *h, **hp;

	v -= VectorPIC;
	if(v < 0 || v >= nelem(halloc.ivec))
		panic("intrenable(%d)", v+VectorPIC);
	ilock(&veclock);
	for(hp = &halloc.ivec[v]; (h = *hp) != nil; hp = &h->next)
		if(h->r == r && h->arg == arg && strcmp(h->name, name) == 0){
			*hp = h->next;
			h->next = halloc.freelist;
			halloc.freelist = h;
			break;
		}
	if(halloc.ivec[v] == nil)
		irqdisable(v);
	iunlock(&veclock);
}

/*
 * called directly by l.s:/intrvec.  on a multiprocessor we'd need to lock veclock.
 */
void
intr(Ureg *ur)
{
	int b, v;
	IMM *io;
	Handler *h;
	long t0;
	Proc *oup;

	ur->cause &= ~0xff;
	io = m->iomem;
	b = io->sivec>>2;
	v = b>>1;
	if(b & 1) {
		if(v == CPIClevel){
			io->civr = 1;
			eieio();
			v = VectorCPIC+(io->civr>>11);
		}
	}else{
		v += VectorIRQ;
		if(io->siel & (1<<(31-b))){
			io->sipend |= 1<<(31-b);
			eieio();
		}
	}

	ur->cause |= v;
	h = halloc.ivec[v];
	if(h == nil){
		iprint("unknown interrupt %d pc=0x%lux\n", v, ur->pc);
		irqdisable(v);
		return;
	}

	/*
	 *  call the interrupt handlers
	 */
	oup = up;
	up = nil;	/* no process at interrupt level */
	do {
		h->nintr++;
		t0 = getdec();
		(*h->r)(ur, h->arg);
		t0 -= getdec();
		h->ticks += t0;
		if(h->maxtick < t0)
			h->maxtick = t0;
		h = h->next;
	} while(h != nil);
	if(v >= VectorCPIC)
		io->cisr |= 1<<(v-VectorCPIC);
	eieio();
	up = oup;
	preemption(0);
}

int
intrstats(char *buf, int bsize)
{
	Handler *h;
	int i, n;

	n = 0;
	for(i=0; i<nelem(halloc.ivec) && n < bsize; i++)
		if((h = halloc.ivec[i]) != nil && h->nintr)
			n += snprint(buf+n, bsize-n, "%3d %lud %lud %ud\n", i, h->nintr, h->ticks, h->maxtick);
	return n;
}

char*
fpexcname(Ureg *ur, ulong fpscr, char *buf)
{
	int i;
	char *s;
	ulong fppc;

	fppc = ur->pc;
	s = 0;
	fpscr >>= 3;		/* trap enable bits */
	fpscr &= (fpscr>>22);	/* anded with exceptions */
	for(i=0; i<5; i++)
		if(fpscr & (1<<i))
			s = fpcause[i];
	if(s == 0)
		return "no floating point exception";
	sprint(buf, "%s fppc=0x%lux", s, fppc);
	return buf;
}

#define KERNPC(x)	(KTZERO<(ulong)(x)&&(ulong)(x)<(ulong)etext)

void
kernfault(Ureg *ur, int code)
{
	Label l;

	print("panic: kfault %s dar=0x%lux\n", excname[code], getdar());
	print("u=0x%lux status=0x%lux pc=0x%lux sp=0x%lux\n",
				up, ur->status, ur->pc, ur->sp);
	dumpregs(ur);
	l.sp = ur->sp;
	l.pc = ur->pc;
	dumpstack();
	setpri(PriBackground);		/* Let the debugger in */
	for(;;)
		sched();
}

void
dumpstack(void)
{
	ulong l, v;
	int i;

	if(up == 0)
		return;
	i = 0;
	for(l=(ulong)&l; l<(ulong)(up->kstack+KSTACK); l+=4){
		v = *(ulong*)l;
		if(KTZERO < v && v < (ulong)etext){
			print("%lux=%lux, ", l, v);
			if(i++ == 4){
				print("\n");
				i = 0;
			}
		}
	}
}

void
dumpregs(Ureg *ur)
{
	int i;
	ulong *l;
	if(up) {
		print("registers for %s %ld\n", up->text, up->pid);
		if(ur->usp < (ulong)up->kstack ||
		   ur->usp > (ulong)up->kstack+KSTACK)
			print("invalid stack ptr\n");
	}
	else
		print("registers for kernel\n");

	l = &ur->cause;
	for(i=0; i<sizeof regname/sizeof(char*); i+=2, l+=2)
		print("%s\t%.8lux\t%s\t%.8lux\n", regname[i], l[0], regname[i+1], l[1]);
}

static void
linkproc(void)
{
	spllo();
	(*up->kpfun)(up->arg);
	pexit("", 0);
}

void
kprocchild(Proc *p, void (*func)(void*), void *arg)
{
	p->sched.pc = (ulong)linkproc;
	p->sched.sp = (ulong)p->kstack+KSTACK;

	p->kpfun = func;
	p->arg = arg;
}

void
setpanic(void)
{
	consoleprint = 1;
}

void
dumplongs(char*, ulong*, int)
{
}
