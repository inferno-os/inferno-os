#include	"u.h"
#include	"../port/lib.h"
#include	"mem.h"
#include	"dat.h"
#include	"fns.h"
#include	"ureg.h"
#include	"io.h"
#include	"../port/error.h"

void	noted(Ureg**, ulong);
void	rfnote(Ureg**);
int	domuldiv(ulong, Ureg*);

extern	Label catch;
extern	void traplink(void);
extern	void syslink(void);
static	void faultsparc(Ureg *ur);
static	void faultasync(Ureg *ur);

	long	ticks;
static	char	excbuf[64];	/* BUG: not reentrant! */

char *trapname[]={
	"reset",
	"instruction access exception",
	"illegal instruction",
	"privileged instruction",
	"fp: disabled",
	"window overflow",
	"window underflow",
	"unaligned address",
	"fp: exception",
	"data access exception",
	"tag overflow",
	"watchpoint detected",
};

char *fptrapname[]={
	"none",
	"IEEE 754 exception",
	"unfinished FP op",
	"unimplemented FP op",
	"sequence error",
	"hardware error",
	"invalid FP register",
	"reserved",
}
;

char*
excname(ulong tbr)
{
	char xx[64];
	char *t;

	switch(tbr){
	case 8:
		if(up == 0)
			panic("fptrap in kernel\n");
		else{
panic("fptrap not implemented\n");
#ifdef notdef
			if(m->fpunsafe==0 && up->p->fpstate!=FPactive)
				panic("fptrap not active\n"); 							fsr = up->fpsave.env;
			sprint(excbuf, "fp: %s fppc=0x%lux",
				fptrapname[(fsr>>14)&7],
				up->fpsave.q[0].a, fsr);
#endif
		}
		return excbuf;
	case 36:
		return "trap: cp disabled";
	case 37:
		return "trap: unimplemented instruction";
	case 40:
		return "trap: cp exception";
	case 42:
		return "trap: divide by zero";
	case 128:
		return "syscall";
	case 129:
		return "breakpoint";
	}
	t = 0;
	if(tbr < sizeof trapname/sizeof(char*))
		t = trapname[tbr];
	if(t == 0){
		if(tbr >= 130)
			sprint(xx, "trap instruction %ld", tbr-128);
		else if(17<=tbr && tbr<=31)
			sprint(xx, "interrupt level %ld", tbr-16);
		else
			sprint(xx, "unknown trap %ld", tbr);
		t = xx;
	}
	if(strncmp(t, "fp: ", 4) == 0)
		strcpy(excbuf, t);
	else
		sprint(excbuf, "trap: %s", t);
	return excbuf;

}

void
trap(Ureg *ur)
{
	int user;
	ulong tbr, iw;

	tbr = (ur->tbr&0xFFF)>>4;
	/*
	 * Hack to catch bootstrap fault during probe
	 */
	if(catch.pc)
		gotolabel(&catch);

	if(up)
		up->dbgreg = ur;

	user = !(ur->psr&PSRPSUPER);
	if(user) {
		panic("how did we get to user mode???");
	}
	if(tbr > 16){			/* interrupt */
		switch(tbr-16) {
		case 15:			/* asynch mem err */
			faultasync(ur);
			break;
		case 14:			/* processor counter */
			clock(ur);
			break;
		case 13:			/* keyboard/mouse */
			ns16552intr(0);
			kbdintr();
			break;
		case 6:				/* lance */
			lanceintr();
			break;
		default:
			print("unexp intr lev %ld\n", tbr-16);
			goto Error;
		}
	}else{
		switch(tbr){
		case 1:				/* instr. access */
		case 9:				/* data access */
			if(up && up->fpstate==FPACTIVE) {
				fpquiet();
				fpsave(&up->fpsave);
				up->fpstate = FPINACTIVE;
			}
			faultsparc(ur);
			goto Return;
		case 2:				/* illegal instr, maybe mul */
			iw = *(ulong*)ur->pc;
			if((iw&0xC1500000) == 0x80500000){
				if(domuldiv(iw, ur))
					goto Return;
				tbr = ur->tbr;
			}
			break;
		case 4:				/* floating point disabled */
panic("some more floating point crapola");
break;
#ifdef notdef
			if(u && u->p){
				if(up->p->fpstate == FPINIT)
					restfpregs(initfpp, up->fpsave.fsr);
				else if(u->p->fpstate == FPinactive)
					restfpregs(&u->fpsave, u->fpsave.fsr);
				else
					break;
				u->p->fpstate = FPactive;
				ur->psr |= PSREF;
				return;
			}
			break;
#endif
		case 8:				/* floating point exception */
panic("floating point crapola #3");
break;
#ifdef notdef
			/* if unsafe, trap happened shutting down FPU; just return */
			if(m->fpunsafe){
				m->fptrap = (fptrap()==0);
				return;
			}
			if(fptrap())
				goto Return;	/* handled the problem */
			break;
#endif
		default:
			break;
		}
    Error:
		panic("kernel trap: %s pc=0x%lux\n", excname(tbr), ur->pc);
	}
    Return:
    	return;
}

void
trapinit(void)
{
	int i;
	long t, a;

	a = ((ulong)traplink-TRAPS)>>2;
	a += 0x40000000;			/* CALL traplink(SB) */
	t = TRAPS;
	for(i=0; i<256; i++){
		*(ulong*)(t+0) = a;		/* CALL traplink(SB) */
		*(ulong*)(t+4) = 0xa7480000;	/* MOVW PSR, R19 */
		a -= 16/4;
		t += 16;
	}

#ifdef notdef
	flushpage(TRAPS);
#else
	flushicache();
#endif

	puttbr(TRAPS);
	setpsr(getpsr()|PSRET|SPL(15));	/* enable traps, not interrupts */
}

void
mulu(ulong u1, ulong u2, ulong *lop, ulong *hip)
{
	ulong lo1, lo2, hi1, hi2, lo, hi, t1, t2, t;

	lo1 = u1 & 0xffff;
	lo2 = u2 & 0xffff;
	hi1 = u1 >> 16;
	hi2 = u2 >> 16;

	lo = lo1 * lo2;
	t1 = lo1 * hi2;
	t2 = lo2 * hi1;
	hi = hi1 * hi2;
	t = lo;
	lo += t1 << 16;
	if(lo < t)
		hi++;
	t = lo;
	lo += t2 << 16;
	if(lo < t)
		hi++;
	hi += (t1 >> 16) + (t2 >> 16);
	*lop = lo;
	*hip = hi;
}

void
muls(long l1, long l2, long *lop, long *hip)
{
	ulong t, lo, hi;
	ulong mlo, mhi;
	int sign;

	sign = 0;
	if(l1 < 0){
		sign ^= 1;
		l1 = -l1;
	}
	if(l2 < 0){
		sign ^= 1;
		l2 = -l2;
	}
	mulu(l1, l2, &mlo, &mhi);
	lo = mlo;
	hi = mhi;
	if(sign){
		t = lo = ~lo;
		hi = ~hi;
		lo++;
		if(lo < t)
			hi++;
	}
	*lop = lo;
	*hip = hi;
}

int
domuldiv(ulong iw, Ureg *ur)
{
	long op1, op2;
	long *regp;
	long *regs;

	regs = (long*)ur;
	if(iw & (1<<13)){	/* signed immediate */
		op2 = iw & 0x1FFF;
		if(op2 & 0x1000)
			op2 |= ~0x1FFF;
	}else
		op2 = regs[iw&0x1F];
	op1 = regs[(iw>>14)&0x1F];
	regp = &regs[(iw>>25)&0x1F];

	if(iw & (4<<19)){	/* divide */
		if(ur->y!=0 && ur->y!=~0){
	unimp:
			ur->tbr = 37;	/* "unimplemented instruction" */
			return 0;	/* complex Y is too hard */
		}
		if(op2 == 0){
			ur->tbr = 42;	/* "zero divide" */
			return 0;
		}
		if(iw & (1<<19)){
			if(ur->y && (op1&(1<<31))==0)
				goto unimp;	/* Y not sign extension */
			*regp = op1 / op2;
		}else{
			if(ur->y)
				goto unimp;
			*regp = (ulong)op1 / (ulong)op2;
		}
	}else{
		if(iw & (1<<19))
			muls(op1, op2, regp, (long*)&ur->y);
		else
			mulu(op1, op2, (ulong*)regp, &ur->y);
	}
	if(iw & (16<<19)){	/* set CC */
		ur->psr &= ~(0xF << 20);
		if(*regp & (1<<31))
			ur->psr |= 8 << 20;	/* N */
		if(*regp == 0)
			ur->psr |= 4 << 20;	/* Z */
		/* BUG: don't get overflow right on divide */
	}
	ur->pc += 4;
	ur->npc = ur->pc+4;
	return 1;
}

void
dumpregs(Ureg *ur)
{
	int i;
	ulong *l;

	if(up) {
		print("registers for %s %ld\n",up->text,up->pid);
		if(ur->usp < (ulong)up->kstack ||
		   ur->usp > (ulong)up->kstack+KSTACK-8)
			print("invalid stack pointer\n");
	} else
		print("registers for kernel\n");

	print("PSR=%lux PC=%lux TBR=%lux\n", ur->psr, ur->pc, ur->tbr);
	l = &ur->r0;
	for(i=0; i<32; i+=2, l+=2)
		print("R%d\t%.8lux\tR%d\t%.8lux\n", i, l[0], i+1, l[1]);
}


/* This routine must save the values of registers the user is not permitted to
 * write from devproc and the restore the saved values before returning
 */
void
setregisters(Ureg *xp, char *pureg, char *uva, int n)
{
	ulong psr;

	psr = xp->psr;
	memmove(pureg, uva, n);
	xp->psr = psr;
}

void
dumpstack(void)
{
}

/*
 * Must only be called splhi() when it is safe to spllo().  Because the FP unit
 * traps if you touch it when an exception is pending, and because if you
 * trap with ET==0 you halt, this routine sets some global flags to enable
 * the rest of the system to handle the trap that might occur here without
 * upsetting the kernel.  Shouldn't be necessary, but safety first.
 */
int
fpquiet(void)
{
	int i, notrap;
	ulong fsr;
	char buf[128];

	i = 0;
	notrap = 1;
	up->fpstate = FPINACTIVE;
	for(;;){
		m->fptrap = 0;
		fsr = getfsr();
		if(m->fptrap){
			/* trap occurred and up->fpsave contains state */
			sprint(buf, "sys: %s", excname(8));
#ifdef notdef
			postnote(u->p, 1, buf, NDebug);
#else
			panic(buf);
#endif
			notrap = 0;
			break;
		}
		if((fsr&(1<<13)) == 0)
			break;
		if(++i > 1000){
			print("fp not quiescent\n");
			break;
		}
	}
	up->fpstate = FPACTIVE;
	return notrap;
}

enum
{
	SE_WRITE	= 4<<5,
	SE_PROT		= 2<<2,
};

static void
faultsparc(Ureg *ur)
{
	ulong addr;
	char buf[ERRMAX];
	int read;
	ulong tbr, ser;

	tbr = (ur->tbr&0xFFF)>>4;
	addr = ur->pc;			/* assume instr. exception */
	read = 1;
	if(tbr == 9){			/* data access exception */
		addr = getrmmu(SFAR);
		ser = getrmmu(SFSR);
		if(ser&(SE_WRITE))	/* is SE_PROT needed? */
			read = 0;
	}

	up->dbgreg = ur;		/* for remote acid */
	spllo();
	sprint(buf, "sys: trap: fault %s addr=0x%lux",
		read? "read" : "write", addr);

	if(up->type == Interp)
		disfault(ur,buf);
	dumpregs(ur);
	panic("fault: %s", buf);
}

static void
faultasync(Ureg *ur)
{
	int user;

	print("interrupt 15 AFSR %lux AFAR %lux MFSR %lux MFAR %lux\n",
		getphys(AFSR), getphys(AFAR), getphys(MFSR), getphys(MFAR));
	dumpregs(ur);
	/*
	 * Clear interrupt
	 */
	putphys(PROCINTCLR, 1<<15);
	user = !(ur->psr&PSRPSUPER);
	if(user)
		pexit("Suicide", 0);
	panic("interrupt 15");
}
