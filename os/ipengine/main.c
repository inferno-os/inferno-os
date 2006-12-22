#include	"u.h"
#include	"../port/lib.h"
#include	"mem.h"
#include	"dat.h"
#include	"fns.h"
#include	"io.h"
#include	"ureg.h"
#include "version.h"

#define	MAXCONF		32

extern ulong kerndate;
extern int cflag;
int	remotedebug;

extern int main_pool_pcnt;
extern int heap_pool_pcnt;
extern int image_pool_pcnt;

char *confname[MAXCONF];
char *confval[MAXCONF];
int nconf;

void addconf(char *, char *);

static void
options(void)
{
	nconf = archconfval(confname, confval, sizeof(confname));
}

void
doc(char *m)
{
	USED(m);
	//iprint("%s...\n", m);
}

static void
poolsizeinit(void)
{
	ulong nb;

	nb = conf.npage*BY2PG;
	poolsize(mainmem, (nb*main_pool_pcnt)/100, 0);
	poolsize(heapmem, (nb*heap_pool_pcnt)/100, 0);
	poolsize(imagmem, (nb*image_pool_pcnt)/100, 1);
}

static void
serialconsole(void)
{
	char *p;
	int port, baud;

	p = getconf("console");
	if(p == nil)
		p = "0";
	if(p != nil && !remotedebug){
		port = strtol(p, nil, 0);
		baud = 9600;
		p = getconf("baud");
		if(p != nil){
			baud = strtol(p, nil, 0);
			if(baud < 9600)
				baud = 9600;
		}
		uartspecial(port, baud, &kbdq, &printq, kbdcr2nl);
	}
}

void
main(void)
{
	machinit();
	options();
	archinit();
	quotefmtinstall();
	confinit();
	cpminit();
	xinit();
	poolsizeinit();
	trapinit();
	mmuinit();
	printinit();
	uartinstall();
	serialconsole();
	doc("screeninit");
	screeninit();
	doc("kbdinit");
	kbdinit();
	doc("clockinit");
	clockinit();
	doc("procinit");
	procinit();
	cpuidprint();
	doc("links");
	links();
	doc("chandevreset");
	chandevreset();

	eve = strdup("inferno");

	print("\nInferno %s\n", VERSION);
	print("Vita Nuova\n");
	print("conf %s (%lud) jit %d\n\n",conffile, kerndate, cflag);

	doc("userinit");
	userinit();
	doc("schedinit");
	schedinit();
}

void
machinit(void)
{
	int n;

	n = m->machno;
	memset(m, 0, sizeof(Mach));
	m->machno = n;
	m->mmask = 1<<m->machno;
	m->iomem = KADDR(getimmr() & ~0xFFFF);
	m->cputype = getpvr()>>16;
	m->delayloop = 20000;	/* initial estimate only; set by clockinit */
	m->speed = 50;	/* initial estimate only; set by archinit */
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
		panic("init0");
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
		ksetenv("cputype", "power", 0);
		snprint(buf, sizeof(buf), "power %s", conffile);
		ksetenv("terminal", buf, 0);
		poperror();
	}
	for(i = 0; i < nconf; i++)
		if(confname[i][0] != '*'){
			if(!waserror()){
				ksetenv(confname[i], confval[i], 0);
				poperror();
			}
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
	o->egrp = newegrp();
	kstrdup(&o->user, eve);

	strcpy(p->text, "interp");

	/*
	 * Kernel Stack
	 */
	p->sched.pc = (ulong)init0;
	p->sched.sp = (ulong)p->kstack+KSTACK;

	ready(p);
}

Conf	conf;

void
addconf(char *name, char *val)
{
	if(nconf >= MAXCONF)
		return;
	confname[nconf] = name;
	confval[nconf] = val;
	nconf++;
}

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

	if(p = getconf("*kernelpercent"))
		pcnt = 100 - strtol(p, 0, 0);
	else
		pcnt = 0;

	conf.nscc = 4;
	conf.smcuarts = (1<<1)|(1<<0);	/* SMC2, SMC1 (usual console) */
	conf.sccuarts = 0;	/* SCC2 not available by default (it's Ether) */

	archconfinit();
	
	conf.npage = conf.npage0 + conf.npage1;
	if(pcnt < 10)
		pcnt = 70;
	conf.ialloc = (((conf.npage*(100-pcnt))/100)/2)*BY2PG;

	conf.nproc = 100 + ((conf.npage*BY2PG)/MB)*5;
	conf.nmach = MAXMACH;
}

void
exit(int ispanic)
{
	up = 0;
	toggleled(3);
	spllo();
	print("cpu %d exiting\n", m->machno);

	/* Shutdown running devices */
	chandevshutdown();

	delay(1000);
	splhi();
	if(ispanic)
		for(;;);
	archreboot();
}

void
reboot(void)
{
	exit(0);
}

void
halt(void)
{
	print("cpu halted\n");
	microdelay(1000);
	for(;;)
		;
}

int
isaconfig(char *class, int ctlrno, ISAConf *isa)
{
	char cc[KNAMELEN], *p;
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
		else if(cistrncmp(p, "mem=", 4) == 0)
			isa->mem = strtoul(p+4, &p, 0);
		else if(cistrncmp(p, "size=", 5) == 0)
			isa->size = strtoul(p+5, &p, 0);
		else if(cistrncmp(p, "freq=", 5) == 0)
			isa->freq = strtoul(p+5, &p, 0);
		else if(cistrncmp(p, "dma=", 4) == 0)
			isa->dma = strtoul(p+4, &p, 0);
	}
	return 1;
}

/*
 *  Save the mach dependent part of the process state.
 */
void
procsave(Proc*)
{
}

void
uartputs(char *s, int n)
{
//	screenputs(buf, n);
	putstrn(s, n);
	uartwait();
}

/* stubs */
void
setfsr(ulong)
{
}

ulong
getfsr()
{
	return 0;
}

void
setfcr(ulong)
{
}

ulong
getfcr()
{
	return 0;
}
