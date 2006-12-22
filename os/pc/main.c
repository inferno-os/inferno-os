#include	"u.h"
#include	"../port/lib.h"
#include	"mem.h"
#include	"dat.h"
#include	"fns.h"
#include	"io.h"
#include	"ureg.h"

extern int main_pool_pcnt;
extern int heap_pool_pcnt;
extern int image_pool_pcnt;
int	pckdebug;

Mach *m;

static  uchar *sp;	/* stack pointer for /boot */

/*
 * Where configuration info is left for the loaded programme.
 * This will turn into a structure as more is done by the boot loader
 * (e.g. why parse the .ini file twice?).
 * There are 3584 bytes available at CONFADDR.
 */
#define BOOTLINE	((char*)CONFADDR)
#define BOOTLINELEN	64
#define BOOTARGS	((char*)(CONFADDR+BOOTLINELEN))
#define	BOOTARGSLEN	(4096-0x200-BOOTLINELEN)
#define	MAXCONF		64

char bootdisk[KNAMELEN];
char *confname[MAXCONF];
char *confval[MAXCONF];
int nconf;

static void
options(void)
{
	long i, n;
	char *cp, *line[MAXCONF], *p, *q;

	/*
	 *  parse configuration args from dos file plan9.ini
	 */
	cp = BOOTARGS;	/* where b.com leaves its config */
	cp[BOOTARGSLEN-1] = 0;

	/*
	 * Strip out '\r', change '\t' -> ' '.
	 */
	p = cp;
	for(q = cp; *q; q++){
		if(*q == '\r')
			continue;
		if(*q == '\t')
			*q = ' ';
		*p++ = *q;
	}
	*p = 0;

	n = getfields(cp, line, MAXCONF, 1, "\n");
	for(i = 0; i < n; i++){
		if(*line[i] == '#')
			continue;
		cp = strchr(line[i], '=');
		if(cp == nil)
			continue;
		*cp++ = '\0';
		confname[nconf] = line[i];
		confval[nconf] = cp;
		nconf++;
	}
}

static void
doc(char *m)
{
	int i;
	print("%s...\n", m);
	for(i = 0; i < 100*1024*1024; i++)
		i++;
}

void
main(void)
{
	outb(0x3F2, 0x00);			/* botch: turn off the floppy motor */

	mach0init();
	options();
	ioinit();
	i8250console();
	quotefmtinstall();
	kbdinit();
	i8253init();
	cpuidentify();
	confinit();
	archinit();
	xinit();
	poolsizeinit();
	trapinit();
	printinit();
	screeninit();
	cpuidprint();
	mmuinit();
	eve = strdup("inferno");
	if(arch->intrinit){	/* launches other processors on an mp */
		doc("intrinit");
		arch->intrinit();
	}
	doc("timersinit");
	timersinit();
	doc("mathinit");
	mathinit();
	doc("kbdenable");
	kbdenable();
	if(arch->clockenable){
		doc("clockinit");
		arch->clockenable();
	}
	doc("procinit");
	procinit();
	doc("links");
	links();
	doc("chandevreset");
	chandevreset();
	doc("userinit");
	userinit();
	doc("schedinit");
	active.thunderbirdsarego = 1;
	schedinit();
	
}

void
mach0init(void)
{
	conf.nmach = 1;
	MACHP(0) = (Mach*)CPU0MACH;
	m->pdb = (ulong*)CPU0PDB;
	m->gdt = (Segdesc*)CPU0GDT;

	machinit();

	active.machs = 1;
	active.exiting = 0;
}

void
machinit(void)
{
	int machno;
	ulong *pdb;
	Segdesc *gdt;

	machno = m->machno;
	pdb = m->pdb;
	gdt = m->gdt;
	memset(m, 0, sizeof(Mach));
	m->machno = machno;
	m->pdb = pdb;
	m->gdt = gdt;

	/*
	 * For polled uart output at boot, need
	 * a default delay constant. 100000 should
	 * be enough for a while. Cpuidentify will
	 * calculate the real value later.
	 */
	m->loopconst = 100000;
}

void
init0(void)
{
	Osenv *o;
	int i;
	char buf[2*KNAMELEN];

	up->nerrlab = 0;

	spllo();
	if(waserror())
		panic("init0: %r");
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

	if(!waserror()){
		ksetenv("cputype", "386", 0);
		snprint(buf, sizeof(buf), "386 %s", conffile);
		ksetenv("terminal", buf, 0);
		for(i = 0; i < nconf; i++){
			if(confname[i][0] != '*')
				ksetenv(confname[i], confval[i], 0);
			ksetenv(confname[i], confval[i], 1);
		}
		poperror();
	}

	poperror();

	disinit("/osinit.dis");
}

void
userinit(void)
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
	fpoff();

	/*
	 * Kernel Stack
	 *
	 * N.B. make sure there's
	 *	4 bytes for gotolabel's return PC
	 */
	p->sched.pc = (ulong)init0;
	p->sched.sp = (ulong)p->kstack+KSTACK-BY2WD;

	ready(p);
}

Conf	conf;

char*
getconf(char *name)
{
	int i;

	for(i = 0; i < nconf; i++)
		if(cistrcmp(confname[i], name) == 0)
			return confval[i];
	return 0;
}

void
confinit(void)
{
	char *p;
	int pcnt;
	ulong maxmem;

	if(p = getconf("*maxmem"))
		maxmem = strtoul(p, 0, 0);
	else
		maxmem = 0;
	if(p = getconf("*kernelpercent"))
		pcnt = 100 - strtol(p, 0, 0);
	else
		pcnt = 0;

	meminit(maxmem);

	conf.npage = conf.npage0 + conf.npage1;
	if(pcnt < 10)
		pcnt = 70;
	conf.ialloc = (((conf.npage*(100-pcnt))/100)/2)*BY2PG;

	conf.nproc = 100 + ((conf.npage*BY2PG)/MB)*5;
}

void
poolsizeinit(void)
{
	ulong nb;

	nb = conf.npage*BY2PG;
	poolsize(mainmem, (nb*main_pool_pcnt)/100, 0);
	poolsize(heapmem, (nb*heap_pool_pcnt)/100, 0);
	poolsize(imagmem, (nb*image_pool_pcnt)/100, 1);
}

static char *mathmsg[] =
{
	"invalid operation",
	"denormalized operand",
	"division by zero",
	"numeric overflow",
	"numeric underflow",
	"precision loss",
	"stack",
	"error",
};

/*
 *  math coprocessor error
 */
void
matherror(Ureg* ureg, void* arg)
{
	ulong status;
	int i;
	char *msg;
	char note[ERRMAX];

	USED(arg);

	/*
	 *  a write cycle to port 0xF0 clears the interrupt latch attached
	 *  to the error# line from the 387
	 */
	if(!(m->cpuiddx & 0x01))
		outb(0xF0, 0xFF);

	/*
	 *  save floating point state to check out error
	 */
	FPsave(&up->fpsave.env);
	status = up->fpsave.env.status;

	msg = 0;
	for(i = 0; i < 8; i++)
		if((1<<i) & status){
			msg = mathmsg[i];
			sprint(note, "sys: fp: %s fppc=0x%lux", msg, up->fpsave.env.pc);
			error(note);
			break;
		}
	if(msg == 0){
		sprint(note, "sys: fp: unknown fppc=0x%lux", up->fpsave.env.pc);
		error(note);
	}
	if(ureg->pc & KZERO)
		panic("fp: status %lux fppc=0x%lux pc=0x%lux", status,
			up->fpsave.env.pc, ureg->pc);
}

/*
 *  math coprocessor emulation fault
 */
void
mathemu(Ureg* ureg, void* arg)
{
	USED(ureg, arg);
	switch(up->fpstate){
	case FPINIT:
		fpinit();
		up->fpstate = FPACTIVE;
		break;
	case FPINACTIVE:
		fprestore(&up->fpsave);
		up->fpstate = FPACTIVE;
		break;
	case FPACTIVE:
		panic("math emu");
		break;
	}
}

/*
 *  math coprocessor segment overrun
 */
void
mathover(Ureg* ureg, void* arg)
{
	USED(arg);
	print("sys: fp: math overrun pc 0x%lux pid %ld\n", ureg->pc, up->pid);
	pexit("math overrun", 0);
}

void
mathinit(void)
{
	trapenable(VectorCERR, matherror, 0, "matherror");
	if(X86FAMILY(m->cpuidax) == 3)
		intrenable(IrqIRQ13, matherror, 0, BUSUNKNOWN, "matherror");
	trapenable(VectorCNA, mathemu, 0, "mathemu");
	trapenable(VectorCSO, mathover, 0, "mathover");
}

/*
 *  Save the mach dependent part of the process state.
 */
void
procsave(Proc *p)
{
	if(p->fpstate == FPACTIVE){
		if(p->state == Moribund)
			fpoff();
		else
			fpsave(&up->fpsave);
		p->fpstate = FPINACTIVE;
	}
}

void
exit(int ispanic)
{
	USED(ispanic);

	up = 0;
	print("exiting\n");

	/* Shutdown running devices */
	chandevshutdown();

	arch->reset();
}

void
reboot(void)
{
	exit(0);
}

int
isaconfig(char *class, int ctlrno, ISAConf *isa)
{
	char cc[32], *p;
	int i;

	snprint(cc, sizeof cc, "%s%d", class, ctlrno);
	p = getconf(cc);
	if(p == nil)
		return 0;

	isa->nopt = tokenize(p, isa->opt, NISAOPT);
	for(i = 0; i < isa->nopt; i++){
		p = isa->opt[i];
		if(cistrncmp(p, "type=", 5) == 0)
			isa->type = p + 5;
		else if(cistrncmp(p, "port=", 5) == 0)
			isa->port = strtoul(p+5, &p, 0);
		else if(cistrncmp(p, "irq=", 4) == 0)
			isa->irq = strtoul(p+4, &p, 0);
		else if(cistrncmp(p, "dma=", 4) == 0)
			isa->dma = strtoul(p+4, &p, 0);
		else if(cistrncmp(p, "mem=", 4) == 0)
			isa->mem = strtoul(p+4, &p, 0);
		else if(cistrncmp(p, "size=", 5) == 0)
			isa->size = strtoul(p+5, &p, 0);
		else if(cistrncmp(p, "freq=", 5) == 0)
			isa->freq = strtoul(p+5, &p, 0);
	}
	return 1;
}
