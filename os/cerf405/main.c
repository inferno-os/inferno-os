#include	"u.h"
#include	"../port/lib.h"
#include	"mem.h"
#include	"dat.h"
#include	"fns.h"
#include	"io.h"
#include	"ureg.h"
#include	"../ip/ip.h"
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
void	eepromscan(void);

static void
options(void)
{
//	nconf = archconfval(confname, confval, sizeof(confname));
}

void
doc(char *m)
{
	USED(m);
	iprint("%s...\n", m);
}

void
idoc(char *m)
{
	uartputs(m, strlen(m));
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
		baud = 115200;
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
	idoc("machinit...\n");
	machinit();
	idoc("options...\n");
	compiledcr();
	options();
//	archinit();
	quotefmtinstall();
	idoc("confinit...\n");
	confinit();
	xinit();
	poolsizeinit();
	poolinit();
	idoc("trapinit...\n");
	trapinit();
	mmuinit();
	ioinit();
	printinit();
	uartinstall();
	serialconsole();
	pcimapinit();
	eepromscan();
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

//ccdv=1 cbdv=2 opdv=2 epdv=3 mpdv=1 ppdv=2

void
machinit(void)
{
	int n;

	n = m->machno;
	memset(m, 0, sizeof(Mach));
	m->machno = n;
	m->mmask = 1<<m->machno;
	m->cputype = getpvr()>>16;
	m->delayloop = 20000;	/* initial estimate only; set by clockinit */
	m->speed = 266;	/* initial estimate only; set by archinit */
	m->cpuhz = 266333333;
	m->vcohz = 799000000;
	m->pllhz = 266333333;
	m->plbhz = 133166666;
	m->opbhz = 66600000;
	m->epbhz = 44*MHz;
	m->pcihz = 66600000;
	m->clockgen = m->cpuhz;	/* it's the internal cpu clock */
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

	archconfinit();
	
	conf.npage = conf.npage0 + conf.npage1;
	if(pcnt < 10)
		pcnt = 70;
	conf.ialloc = (((conf.npage*(100-pcnt))/100)/2)*BY2PG;

	conf.nproc = 100 + ((conf.npage*BY2PG)/MB)*5;
	conf.nmach = MAXMACH;

}

static void
twinkle(void)
{
	if(m->ticks%MS2TK(1000) == 0)
		((Gpioregs*)PHYSGPIO)->or ^= 1<<31;
}

void (*archclocktick)(void) = twinkle;

void
exit(int ispanic)
{
	up = 0;
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

/*
 * kept in case it's needed for PCI/ISA devices
 */
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
idlehands(void)
{
	putmsr(getmsr() | MSR_WE | MSR_EE | MSR_CE);	/* MSR_DE as well? */
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

/*
 * some of this is possibly ice-cube specific
 */

enum {
	Cpc0Pllmr0=	0xF0,	/* PLL mode register 0 */
	Cpc0Boot=	0xF1,	/* clock status */
	Cpc0Pllmr1=	0xF4,	/* PLL mode register 1 */
	Cpc0Srr=		0xF6,	/* PCI soft reset */
	Cpc0PCI=		0xF9,	/* PCI control */
};
/*
00f0 = 00011101
00f1 = 00000025
00f2 = 00000000
00f3 = 00000000
00f4 = 8085523e
00f5 = 00000017
00f6 = 00000000
ccdv=1 cbdv=2 opdv=2 epdv=3 mpdv=1 ppdv=2
fbmul=8 fwdva=5 fwdvb=5 tun=257 m=40
*/
void
archconfinit(void)
{
	ulong ktop;

	conf.npage0 = (32*1024*1024)/BY2PG;
	conf.base0 = 0;
	ktop = PGROUND((ulong)end);
	ktop = PADDR(ktop) - conf.base0;
	conf.npage0 -= ktop/BY2PG;
	conf.base0 += ktop;

	{int i; for(i=0xF0; i<=0xF6; i++){iprint("%.4ux = %.8lux\n", i, getdcr(i));}}
	{
		int ccdv, cbdv, opdv, epdv, mpdv, ppdv;
		int fbmul, fwdva, fwdvb, tun;
		ulong mr0, mr1;

		mr0 = getdcr(Cpc0Pllmr0);
		ccdv = ((mr0>>20)&3)+1;
		cbdv = ((mr0>>16)&3)+1;
		opdv = ((mr0>>12)&3)+1;
		epdv = ((mr0>>8)&3)+2;
		mpdv = ((mr0>>4)&3)+1;
		ppdv = (mr0&3)+1;
		iprint("ccdv=%d cbdv=%d opdv=%d epdv=%d mpdv=%d ppdv=%d\n",
			ccdv, cbdv, opdv, epdv, mpdv, ppdv);
		mr1 = getdcr(Cpc0Pllmr1);
		fbmul = (mr1>>20) & 0xF;
		if(fbmul == 0)
			fbmul = 16;
		fwdva = (mr1>>16) & 7;
		if(fwdva == 0)
			fwdva = 8;
		fwdvb = (mr1>>12) & 7;
		if(fwdvb == 0)
			fwdvb = 8;
		tun = mr0 & 0x3FF;
		iprint("fbmul=%d fwdva=%d fwdvb=%d tun=%d m=%d\n",
			fbmul, fwdva, fwdvb, tun, fbmul*fwdva);
	}
}

void
archreboot(void)
{
	putevpr(~0);
	firmware(0);
	for(;;);
}

void
clockcheck(void)
{
}

void
cpuidprint(void)
{
	iprint("PowerPC 405EP pvr=%8.8lux\n", getpvr());
	/* TO DO */
}

#include	"../port/flashif.h"

/*
 * for devflash.c:/^flashreset
 * retrieve flash type, virtual base and length and return 0;
 * return -1 on error (no flash)
 */
int
archflashreset(int bank, Flash *f)
{
	switch(bank){
	case 0:
		f->type = "AMD29F0x0";	/* not right, but will do for now */
		f->addr = (void*)PHYSFLASH;
		f->size = FLASHSIZE;
		f->width = 2;
		return 0;
	case 1:
		f->type = "nand";
		f->addr = (void*)PHYSNAND;
		f->size = 0;	/* done by probe */
		f->width = 1;
		return 0;
	default:
		return -1;
	}
}

void
archflashwp(Flash*, int)
{
}

#include "../port/netif.h"
#include "etherif.h"

enum {
	/* EMAC-PHY control, tucked away in CPC0 */
	Cpc0Epctl=	0xF3,	/* EMAC-PHY ctl */

	E0Nf=	1<<31,	/* Emac0 noise filter enable */
	E1Nf=	1<<30,	/* Emac1 noise filter enable */
	E1pr=	1<<7,	/* Emac1 packet reject is active high */
	E0pr=	1<<6,	/* Emac 0 packet reject is active high */
	E1rm=	1<<5,	/* enable Emac 1 packet removal */
	E0rm=	1<<4,	/* enable Emac 0 packet removal */
	E1pci=	1<<1,	/* Emac 1 clock source is Tx clock output (loopback) */
	E0pci=	1<<0,	/* Emac 0 clock source is Tx clock output (loopback) */
};

int
archether(int ctlno, Ether *ether)
{
	char name[KNAMELEN], *p;
	int s;

	if(ctlno > 1)
		return -1;
	ether->type = "EMAC";
	ether->port = ctlno;
	if(ctlno != 0)
		snprint(name, sizeof(name), "eth%daddr", ctlno);
	else
		strcpy(name, "ethaddr");
	p = getconf(name);
	if(p == 0){
		iprint("ether%d: no %s in EEPROM env\n", ctlno, name);
		return -1;
	}
	parsemac(ether->ea, p, Eaddrlen);
	s = splhi();
	putdcr(Cpc0Epctl, getdcr(Cpc0Epctl) | (ctlno?E1Nf:E0Nf));
	splx(s);
	return 1;
}

enum {
	/* UART control */
	Cpc0Ucr=		0xF5,	/* UART control register */

	U0Dc=		1<<21,	/* UART0 DMA clear enable */
	U0Dt=		1<<20,	/* enable UART0 DMA transmit channel */
	U0Dr=		1<<19,	/* enable UART0 DMA receive channel */
	U1Dc=		1<<18,	/* UART1 DMA clear enable */
	U1Dt=		1<<17,	/* enable UART1 DMA transmit channel */
	U1Dr=		1<<16,	/* enable UART1 DMA receive channel */
	U1Div_s=		8,		/* UART1 serial clock divisor (shift) */
	U1Stop=		1<<8,
	U0Div_s=		0,		/* UART0 serial clock divisor (shift) */
	U0Stop=		1<<0,
	UDiv_m=		0x7F,	/* UARTx divisor mask */
};

static ulong
findserialclock(int rate, ulong *freq)
{
	ulong d, b;
	ulong serialclock;
	int actual, e, beste, bestd;

	*freq = 0;
	if(rate == 0)
		return 0;
	d = ((m->pllhz+m->opbhz-1)/m->opbhz)*2;	/* double to allow for later rounding */
	beste = 0;
	bestd = -1;
	for(; d<=128; d++){
		serialclock = (2*m->pllhz)/d;
		b = ((serialclock+8*rate-1)/(rate*16))>>1;
		actual = ((serialclock+8*b-1)/(b*16))>>1;
		e = rate-actual;
		if(e < 0)
			e = -e;
		if(bestd < 0 || e < beste || e == beste && (bestd&1) && (d&1)==0){
			beste = e;
			bestd = d;
		}
	}
	if(bestd > 0)
		*freq = m->pllhz/bestd;
	return bestd;
}

/*
 * return a value for UARTn's baud rate generator, and
 * set a corresponding divsor in the UARTn clock generator
 * (between 2 and 128)
 */
ulong
archuartclock(int n, int rate)
{
	int d, s;
	ulong m, freq;

	d = findserialclock(rate, &freq);
	if(d <= 0)
		d = U0Stop;
	m = UDiv_m;
	if(n){
		d <<= U1Div_s;
		m <<= U1Div_s;
	}
	s = splhi();
	putdcr(Cpc0Ucr, (getdcr(Cpc0Ucr) & ~m) | d);
	splx(s);
	return freq;
}

void
archuartdma(int n, int on)
{
	ulong r;
	int s;

	r = n? (U1Dc|U1Dt|U1Dr): (U0Dc|U0Dt|U0Dr);
	if(on){
		s = splhi();
		putdcr(Cpc0Ucr, getdcr(Cpc0Ucr) | r);
		splx(s);
	}else{
		s = splhi();
		putdcr(Cpc0Ucr, getdcr(Cpc0Ucr) & ~r);
		splx(s);
	}
}

/*
 * boot environment in eeprom
 */

enum {
	EEpromHdr=	8,	/* bytes */
	Envsize=	0x400,
};

static I2Cdev eedev;
static struct {
	uchar	buf[Envsize];
	int	size;
} bootenv;

static int
eepromitem(uchar *buf, int lim, ulong *off)
{
	int l;
	uchar b;

	if(i2crecv(&eedev, &b, 1, (*off)++) != 1)
		return -1;
	l = b;
	if(l & 0x80){
		if(i2crecv(&eedev, &b, 1, (*off)++) != 1)
			return -1;
		l = ((l & 0x7F)<<8) | b;
	}
	if(buf == nil)
		return l;
	if(l > lim)
		l = lim;
	return i2crecv(&eedev, buf, l, *off);
}

void
eepromscan(void)
{
	int n, l;
	ulong off;
	uchar buf[2];
	char *p, *ep, *v;

	eedev.addr = 0x50;
	eedev.salen = 2;
	i2csetup(1);
	n = i2crecv(&eedev, buf, sizeof(buf), 0);
	if(n <= 0){
		iprint("eepromscan: %d\n", n);
		return;
	}
	if(buf[0] != 0xEF || buf[1] != 0xBE){
		iprint("eeprom invalid\n");
		return;
	}
	bootenv.size = 0;
	for(off = EEpromHdr; off < 16384;){
		l = eepromitem(bootenv.buf, sizeof(bootenv.buf), &off);	/* key */
		if(l <= 0)
			break;
		off += l;
		if(l == 7 && memcmp(bootenv.buf, "PPCBOOT", 7) == 0){	/* intrinsyc key */
			bootenv.size = eepromitem(bootenv.buf, sizeof(bootenv.buf), &off);
			break;
		}
		l = eepromitem(nil, 0, &off);	/* skip value */
		if(l < 0)
			break;
		off += l+2;	/* 2 byte crc */
	}
	p = (char*)bootenv.buf+4;	/* skip crc */
	ep = p+bootenv.size;
	for(; p < ep && *p; p += l){
		l = strlen(p)+1;
		v = strchr(p, '=');
		if(v != nil)
			*v++ = 0;
		else
			v = "";
		addconf(p, v);
		if(0)
			iprint("%q = %q\n", p, v);
	}
}

ulong
logfsnow(void)
{
	return rtctime();
}
