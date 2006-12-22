#include	"u.h"
#include	"../port/lib.h"
#include	"mem.h"
#include	"dat.h"
#include	"fns.h"
#include	"io.h"
#include	"ureg.h"
#include	"../port/error.h"

#define waslo(sr) (!((sr) & (PsrDirq|PsrDfiq)))

typedef struct Handler Handler;
struct Handler {
	void	(*r)(Ureg*, void*);
	void	*a;
	char	name[KNAMELEN];
	Handler	*next;
};

static Handler irqvec[32];
static Handler gpiovec[MaxGPIObit+1];
static Lock veclock;

Instr BREAK = 0xE6BAD010;

int (*breakhandler)(Ureg*, Proc*);
int (*catchdbg)(Ureg *, uint);
void (*suspendcode)(void);

extern void (*serwrite)(char *, int);

/*
 * Interrupt sources not masked by splhi(): special
 *  interrupt handlers (eg, profiler or watchdog), not allowed
 *  to share regular kernel data structures.  All interrupts are
 *  masked by splfhi(), which should only be used sparingly.
 * splflo enables FIQ but no others.
 */
enum {
	IRQ_NONMASK = (1 << IRQtimer3) | (1 << IRQtimer2),
};

void
intrenable(int sort, int v, void (*f)(Ureg*, void*), void* a, char *name)
{
	int x, o;
	ulong m;
	GpioReg *g;
	Handler *ie;

	ilock(&veclock);
	switch(sort) {
	case GPIOfalling:
	case GPIOrising:
	case GPIOboth:
		if(v < 0 || v > MaxGPIObit)
			panic("intrenable: gpio %d out of range", v);
		g = GPIOREG;
		o = GPR(v);
		m = GPB(v);
		switch(sort){
		case GPIOfalling:
			g->gfer[o] |= m;
			g->grer[o] &= ~m;
			break;
		case GPIOrising:
			g->grer[o] |= m;
			g->gfer[o] &= ~m;
			break;
		case GPIOboth:
			g->grer[o] |= m;
			g->gfer[o] |= m;
			break;
		}
		g->gpdr[o] &= ~m;	/* must be input */
		if(v > MaxGPIOIRQ) {
			ie = &gpiovec[v];
			if(ie->r != nil)
				iprint("duplicate gpio irq: %d (%s)\n", v, ie->name);
			ie->r = f;
			ie->a = a;
			strncpy(ie->name, name, KNAMELEN-1);
			ie->name[KNAMELEN-1] = 0;
			iunlock(&veclock);
			return;
		}
		v += IRQgpio0;
		/*FALLTHROUGH for GPIO sources 0-MaxGPIOIRQ */
	case IRQ:
		if(v < 0 || v > 31)
			panic("intrenable: irq source %d out of range", v);
		ie = &irqvec[v];
		if(ie->r != nil)
			iprint("duplicate irq: %d (%s)\n", v, ie->name);
		ie->r = f;
		ie->a = a;
		strncpy(ie->name, name, KNAMELEN-1);
		ie->name[KNAMELEN-1] = 0;

		x = splfhi();
		/* Enable the interrupt by setting the mask bit */
		INTRREG->icmr |= 1 << v;
		splx(x);
		break;
	default:
		panic("intrenable: unknown irq bus %d", sort);
	}
	iunlock(&veclock);
}

void
intrdisable(int sort, int v, void (*f)(Ureg*, void*), void* a, char *name)
{
	int x, o;
	GpioReg *g;
	Handler *ie;
	ulong m;

	ilock(&veclock);
	switch(sort) {
	case GPIOfalling:
	case GPIOrising:
	case GPIOboth:
		if(v < 0 || v > MaxGPIObit)
			panic("intrdisable: gpio source %d out of range", v);
		if(v > MaxGPIOIRQ)
			ie = &gpiovec[v];
		else
			ie = &irqvec[v];
		if(ie->r != f || ie->a != a || strcmp(ie->name, name) != 0)
			break;
		ie->r = nil;
		if(v <= MaxGPIOIRQ){
			v += IRQgpio0;
			x = splfhi();
			INTRREG->icmr &= ~(1<<v);
			splx(x);
		}
		g = GPIOREG;
		o = GPR(v);
		m = GPB(v);
		switch(sort){
		case GPIOfalling:
			g->gfer[o] &= ~m;
			break;
		case GPIOrising:
			g->grer[o] &= ~m;
			break;
		case GPIOboth:
			g->grer[o] &= ~m;
			g->gfer[o] &= ~m;
			break;
		}
		break;
	case IRQ:
		if(v < 0 || v > 31)
			panic("intrdisable: irq source %d out of range", v);
		ie = &irqvec[v];
		if(ie->r != f || ie->a != a || strcmp(ie->name, name) != 0)
			break;
		ie->r = nil;
		x = splfhi();
		INTRREG->icmr &= ~(1<<v);
		splx(x);
		break;
	default:
		panic("intrdisable: unknown irq bus %d", sort);
	}
	iunlock(&veclock);
}

static void
gpiointr(Ureg *ur, void*)
{
	Handler *cur;
	ulong e;
	int i, o;

	for(o=0; o<3; o++){
		e = GPIOREG->gedr[o];
		GPIOREG->gedr[o] = e;
		for(i = 0; i < 32 && e != 0; i++){
			if(e & (1<<i)){
				cur = &gpiovec[(o<<5)+i];
				if(cur->r != nil){
					cur->r(ur, cur->a);
					e &= ~(1<<i);
				}
			}
		}
		if(e != 0){
			GPIOREG->gfer[o] &= ~e;
			GPIOREG->grer[o] &= ~e;
			iprint("spurious GPIO[%d] %8.8lux interrupt\n", o,e);
		}
	}
}

static void
intrs(Ureg *ur, ulong ibits)
{
	Handler *cur;
	int i, s;

	for(i=0; i<nelem(irqvec) && ibits; i++)
		if(ibits & (1<<i)){
			cur = &irqvec[i];
			if(cur->r != nil){
				cur->r(ur, cur->a);
				ibits &= ~(1<<i);
			}
		}
	if(ibits != 0){
		iprint("spurious irq interrupt: %8.8lux\n", ibits);
		s = splfhi();
		INTRREG->icmr &= ~ibits;
		splx(s);
	}
}

/*
 * initialise R13 in each trap mode, at the start and after suspend reset.
 */
void
trapstacks(void)
{
	setr13(PsrMfiq, m->fiqstack+nelem(m->fiqstack));
	setr13(PsrMirq, m->irqstack+nelem(m->irqstack));
	setr13(PsrMabt, m->abtstack+nelem(m->abtstack));
	setr13(PsrMund, m->undstack+nelem(m->undstack));
}

void
trapinit(void)
{
	IntrReg *intr = INTRREG;

	intr->icmr = 0;	/* mask everything */
	intr->iccr = 1;	/* only enabled and unmasked interrupts wake us */
	intr->iclr = IRQ_NONMASK;

	trapstacks();

	memmove(page0->vectors, vectors, sizeof(page0->vectors));
	memmove(page0->vtable, vtable, sizeof(page0->vtable));
	dcflush(page0, sizeof(*page0));

#ifdef NOTYET
	suspendcode = xspanalloc(16*sizeof(ulong), CACHELINESZ, 0);
	memmove(suspendcode, _suspendcode, 16*sizeof(ulong));
	dcflush(suspendcode, 8*sizeof(ulong));
#endif

	icflushall();

	intrenable(IRQ, IRQgpio, gpiointr, nil, "gpio");
}

static char *trapnames[PsrMask+1] = {
	[ PsrMfiq ] "Fiq interrupt",
	[ PsrMirq ] "Mirq interrupt",
	[ PsrMsvc ] "SVC/SWI Exception",
	[ PsrMabt ] "Prefetch Abort/Data Abort",
	[ PsrMabt+1 ] "Data Abort",
	[ PsrMund ] "Undefined instruction",
	[ PsrMsys ] "Sys trap"
};

static char *
trapname(int psr)
{
	char *s;

	s = trapnames[psr & PsrMask];
	if(s == nil)
		s = "Undefined trap";
	return s;
}

static void
sys_trap_error(int type)
{
	char errbuf[ERRMAX];
	sprint(errbuf, "sys: trap: %s\n", trapname(type));
	error(errbuf);
}

static void
faultarm(Ureg *ureg, ulong far)
{
	char buf[ERRMAX];

	sprint(buf, "sys: trap: fault pc=%8.8lux addr=0x%lux", (ulong)ureg->pc, far);
	if(1){
		iprint("%s\n", buf);
		dumpregs(ureg);
	}
	if(far == ~0)
		disfault(ureg, "dereference of nil");
	disfault(ureg, buf);
}

/*
 *  All traps come here.  It might be slightly slower to have all traps call trap
 *  rather than directly vectoring the handler.
 *  However, this avoids a lot of code duplication and possible bugs.
 *  trap is called splfhi().
 */
void
trap(Ureg* ureg)
{
	ulong far, fsr;
	int rem, t, itype;
	Proc *oup;

	if(up != nil)
		rem = ((char*)ureg)-up->kstack;
	else
		rem = ((char*)ureg)-(char*)m->stack;
	if(ureg->type != PsrMfiq && rem < 256)
		panic("trap %d bytes remaining (%s), up=#%8.8lux ureg=#%8.8lux pc=#%8.8ux",
			rem, up?up->text:"", up, ureg, ureg->pc);

	/*
	 * All interrupts/exceptions should be resumed at ureg->pc-4,
	 * except for Data Abort which resumes at ureg->pc-8.
	 */
	itype = ureg->type;
	if(itype == PsrMabt+1)
		ureg->pc -= 8;
	else
		ureg->pc -= 4;
	ureg->sp = (ulong)(ureg+1);
	if(itype == PsrMfiq){	/* fast interrupt (eg, profiler) */
		oup = up;
		up = nil;
		intrs(ureg, INTRREG->icfp);
		up = oup;
		return;
	}

	/* All other traps */

	if(0 && ureg->psr & PsrDfiq)
		panic("FIQ disabled");

	if(up){
		up->pc = ureg->pc;
		up->dbgreg = ureg;
	}
	switch(itype) {
	case PsrMirq:
		t = m->ticks;	/* CPU time per proc */
		up = nil;		/* no process at interrupt level */
		splflo();	/* allow fast interrupts */
		intrs(ureg, INTRREG->icip);
		up = m->proc;
		preemption(m->ticks - t);
		break;

	case PsrMund:				/* Undefined instruction */
		if(*(ulong*)ureg->pc == BREAK && breakhandler) {
			int s;
			Proc *p;

			p = up;
			/* if(!waslo(ureg->psr) || ureg->pc >= (ulong)splhi && ureg->pc < (ulong)islo)
				p = 0; */
			s = breakhandler(ureg, p);
			if(s == BrkSched) {
				p->preempted = 0;
				sched();
			} else if(s == BrkNoSched) {
				p->preempted = 1;	/* stop it being preempted until next instruction */
				if(up)
					up->dbgreg = 0;
				return;
			}
			break;
		}
		if(up == nil)
			goto faultpanic;
		spllo();
		if(waserror()) {
			if(waslo(ureg->psr) && up->type == Interp)
				disfault(ureg, up->env->errstr);
			setpanic();
			dumpregs(ureg);
			panic("%s", up->env->errstr);
		}
		if(!fpiarm(ureg)) {
			dumpregs(ureg);
			sys_trap_error(ureg->type);
		}
		poperror();
		break;

	case PsrMsvc:				/* Jump through 0 or SWI */
		if(waslo(ureg->psr) && up && up->type == Interp) {
			spllo();
			dumpregs(ureg);
			sys_trap_error(ureg->type);
		}
		setpanic();
		dumpregs(ureg);
		panic("SVC/SWI exception");
		break;

	case PsrMabt:				/* Prefetch abort */
		if(catchdbg && catchdbg(ureg, 0))
			break;
		/* FALL THROUGH */
	case PsrMabt+1:			/* Data abort */
		fsr = mmugetfsr();
		far = mmugetfar();
		if(fsr & (1<<9)) {
			mmuputfsr(fsr & ~(1<<9));
			if(catchdbg && catchdbg(ureg, fsr))
				break;
			print("Debug/");
		}
		if(waslo(ureg->psr) && up && up->type == Interp) {
			spllo();
			faultarm(ureg, far);
		}
		iprint("Data Abort: FSR %8.8luX FAR %8.8luX\n", fsr, far); xdelay(1);
		/* FALL THROUGH */

	default:				/* ??? */
faultpanic:
		setpanic();
		dumpregs(ureg);
		panic("exception %uX %s\n", ureg->type, trapname(ureg->type));
		break;
	}

	splhi();
	if(up)
		up->dbgreg = 0;		/* becomes invalid after return from trap */
}

void
setpanic(void)
{
	if(breakhandler != 0)	/* don't mess up debugger */
		return;
	INTRREG->icmr = 0;
	spllo();
	consoleprint = 1;
	serwrite = uartputs;
}

int
isvalid_wa(void *v)
{
	return (ulong)v >= KZERO && (ulong)v < conf.topofmem && !((ulong)v & 3);
}

int
isvalid_va(void *v)
{
	return (ulong)v >= KZERO && (ulong)v < conf.topofmem;
}

void
dumplongs(char *msg, ulong *v, int n)
{
	int i, l;

	l = 0;
	iprint("%s at %.8p: ", msg, v);
	for(i=0; i<n; i++){
		if(l >= 4){
			iprint("\n    %.8p: ", v);
			l = 0;
		}
		if(isvalid_va(v)){
			iprint(" %.8lux", *v++);
			l++;
		}else{
			iprint(" invalid");
			break;
		}
	}
	iprint("\n");
}

static void
_dumpstack(Ureg *ureg)
{
	ulong *v, *l;
	ulong inst;
	ulong *estack;
	int i;

	l = (ulong*)(ureg+1);
	if(!isvalid_wa(l)){
		iprint("invalid ureg/stack: %.8p\n", l);
		return;
	}
	print("ktrace /kernel/path %.8ux %.8ux %.8ux\n", ureg->pc, ureg->sp, ureg->r14);
	if(up != nil && l >= (ulong*)up->kstack && l <= (ulong*)(up->kstack+KSTACK-4))
		estack = (ulong*)(up->kstack+KSTACK);
	else if(l >= (ulong*)m->stack && l <= (ulong*)((ulong)m+BY2PG-4))
		estack = (ulong*)((ulong)m+BY2PG-4);
	else{
		iprint("unknown stack\n");
		return;
	}
	i = 0;
	for(; l<estack; l++) {
		if(!isvalid_wa(l)) {
			iprint("invalid(%8.8p)", l);
			break;
		}
		v = (ulong*)*l;
		if(isvalid_wa(v)) {
			inst = v[-1];
			if((inst & 0x0ff0f000) == 0x0280f000 &&
			     (*(v-2) & 0x0ffff000) == 0x028fe000	||
				(inst & 0x0f000000) == 0x0b000000) {
				iprint("%8.8p=%8.8lux ", l, v);
				i++;
			}
		}
		if(i == 4){
			iprint("\n");
			i = 0;
		}
	}
	if(i)
		print("\n");
}

void
dumpregs(Ureg* ureg)
{
	print("TRAP: %s", trapname(ureg->type));
	if((ureg->psr & PsrMask) != PsrMsvc)
		print(" in %s", trapname(ureg->psr));
	print("\n");
	print("PSR %8.8uX type %2.2uX PC %8.8uX LINK %8.8uX\n",
		ureg->psr, ureg->type, ureg->pc, ureg->link);
	print("R14 %8.8uX R13 %8.8uX R12 %8.8uX R11 %8.8uX R10 %8.8uX\n",
		ureg->r14, ureg->r13, ureg->r12, ureg->r11, ureg->r10);
	print("R9  %8.8uX R8  %8.8uX R7  %8.8uX R6  %8.8uX R5  %8.8uX\n",
		ureg->r9, ureg->r8, ureg->r7, ureg->r6, ureg->r5);
	print("R4  %8.8uX R3  %8.8uX R2  %8.8uX R1  %8.8uX R0  %8.8uX\n",
		ureg->r4, ureg->r3, ureg->r2, ureg->r1, ureg->r0);
	print("Stack is at: %8.8luX\n", ureg);
	print("PC %8.8lux LINK %8.8lux\n", (ulong)ureg->pc, (ulong)ureg->link);

	if(up)
		print("Process stack:  %8.8lux-%8.8lux\n",
			up->kstack, up->kstack+KSTACK-4);
	else
		print("System stack: %8.8lux-%8.8lux\n",
			(ulong)(m+1), (ulong)m+BY2PG-4);
	dumplongs("stack", (ulong *)(ureg + 1), 16);
	_dumpstack(ureg);
}

/*
 * Fill in enough of Ureg to get a stack trace, and call a function.
 * Used by debugging interface rdb.
 */
void
callwithureg(void (*fn)(Ureg*))
{
	Ureg ureg;
	ureg.pc = getcallerpc(&fn);
	ureg.sp = (ulong)&fn;
	ureg.r14 = 0;
	fn(&ureg);
}

void
dumpstack(void)
{
	callwithureg(_dumpstack);
}

void
trapspecial(int (*f)(Ureg *, uint))
{
	catchdbg = f;
}
