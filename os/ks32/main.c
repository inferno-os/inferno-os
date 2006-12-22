#include "u.h"
#include "../port/lib.h"
#include "mem.h"
#include "io.h"
#include "dat.h"
#include "fns.h"
#include "../port/error.h"
#include "version.h"

Mach *m = (Mach*)MACHADDR;
Proc *up = 0;
Conf conf;

extern ulong kerndate;
extern int cflag;
extern int consoleprint;
extern int redirectconsole;
extern int main_pool_pcnt;
extern int heap_pool_pcnt;
extern int image_pool_pcnt;
extern int kernel_pool_pcnt;

int
segflush(void *p, ulong l)
{
	USED(p, l);
	return 1;
}

static void
poolsizeinit(void)
{
	ulong nb;

	nb = conf.npage*BY2PG;
	iprint("free memory %ld\n", nb);
	poolsize(mainmem, (nb*main_pool_pcnt)/100, 0);
	poolsize(heapmem, (nb*heap_pool_pcnt)/100, 0);
	poolsize(imagmem, (nb*image_pool_pcnt)/100, 1);
}

void
reboot(void)
{
	exit(0);
}

void
halt(void)
{
	spllo();
	print("cpu halted\n");
	while(1);
}

void
confinit(void)
{
	ulong base;

	archconfinit();

	base = PGROUND((ulong)end);
	conf.base0 = base;

	conf.base1 = 0;
	conf.npage1 = 0;

	conf.npage0 = (conf.topofmem - base)/BY2PG;

	conf.npage = conf.npage0 + conf.npage1;
	conf.ialloc = (((conf.npage*(main_pool_pcnt))/100)/2)*BY2PG;


	conf.nproc = 20;
//	conf.nproc = 100 + ((conf.npage*BY2PG)/MB)*5;
	conf.nmach = 1;
}

void
machinit(void)
{
	memset(m, 0, sizeof(Mach));	/* clear the mach struct */
}

void
cachemode(int size, int cenable, int wbenable)
{
	ulong sc = SYSCFG;
	int cm;

	switch (size) {
	case 0:
	default:
		cm = 2;
		break;
	case 4096:
		cm = 0;
		break;
	case 8192:
		cm = 1;
		break;
	}
	sc &= ~((3 << 4) | (1 << 2) | (1 << 1));
	SYSCFG = sc |  (cm << 4) | (cenable << 1) | (wbenable << 2);
}

void
serputc()
{
	// dummy routine
}

void
main(void)
{
	long *p, *ep;

	/* clear the BSS by hand */
	p = (long*)edata;
	ep = (long*)end;
	while(p < ep)
		*p++ = 0;
	// memset(edata, 0, end-edata);		/* clear the BSS */
	cachemode(8192, 1, 1);
	machinit();
	archreset();
	confinit();
	links();
	xinit();
	poolinit();
	poolsizeinit();
	trapinit(); 
//	mmuctlregw(mmuctlregr() | CpCDcache | CpCwb | CpCi32 | CpCd32 | CpCIcache);
	clockinit(); 
	printinit();
//	screeninit();
	procinit();
	chandevreset();

	eve = strdup("inferno");

	archconsole();
//	else
//		kbdinit();

	print("\nInferno %s\n", VERSION);
	print("conf %s (%lud) jit %d\n\n", conffile, kerndate, cflag);
	userinit();
// print("userinit over\n");
	schedinit();
}

void
init0(void)
{
	Osenv *o;

// print("init0\n");
	up->nerrlab = 0;
	spllo();
	if(waserror())
		panic("init0 %r");

	/*
	 * These are o.k. because rootinit is null.
	 * Then early kproc's will have a root and dot.
	 */
	o = up->env;
	o->pgrp->slash = namec("#/", Atodir, 0, 0);
	cnameclose(o->pgrp->slash->name);
	o->pgrp->slash->name = newcname("/");
	o->pgrp->dot = cclone(o->pgrp->slash);

	chandevinit();
	poperror();
// iprint("init0: disinit\n");
// print("CXXXYYYYYYYYZZZZZZZ\n");
	disinit("/osinit.dis");
}

void
userinit()
{
	Proc *p;
	Osenv *o;

	p = newproc();
	o = p->env;

	o->fgrp = newfgrp(nil);

	o->pgrp = newpgrp();
	kstrdup(&o->user, eve);

	strcpy(p->text, "interp");

	p->fpstate = FPINIT;

	/*
	 * Kernel Stack
	 *
	 * N.B. The -12 for the stack pointer is important.
	 *	4 bytes for gotolabel's return PC
	 */
	p->sched.pc = (ulong)init0;
	p->sched.sp = (ulong)p->kstack+KSTACK-8;

	ready(p);
}

void
exit(int inpanic)
{
	up = 0;

	/* Shutdown running devices */
	chandevshutdown();

	if(inpanic){
		print("Hit the reset button\n");
		for(;;)clockpoll();
	}
	archreboot();
}

static void
linkproc(void)
{
	spllo();
	if (waserror())
		print("error() underflow: %r\n");
	else
		(*up->kpfun)(up->arg);
	pexit("end proc", 1);
}

void
kprocchild(Proc *p, void (*func)(void*), void *arg)
{
	p->sched.pc = (ulong)linkproc;
	p->sched.sp = (ulong)p->kstack+KSTACK-8;

	p->kpfun = func;
	p->arg = arg;
}

/* stubs */
void
setfsr(ulong x) {
USED(x);
}

ulong
getfsr(){
return 0;
}

void
setfcr(ulong x) {
USED(x);
}

ulong
getfcr(){
return 0;
}

void
fpinit(void)
{
}

void
FPsave(void*)
{
}

void
FPrestore(void*)
{
}

ulong
va2pa(void *v)
{
	return (ulong)v;
}

