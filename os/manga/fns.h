#include "../port/portfns.h"

ulong	aifinit(uchar *aifarr);
int	archaudiopower(int);
void	archaudiomute(int);
void	archaudioamp(int);
int	archaudiospeed(int, int);
void	archconfinit(void);
void	archconsole(void);
int	archflash12v(int);
long	archkprofmicrosecondspertick(void);
void	archkprofenable(int);
void	archpowerdown(void);
void	archpowerup(void);
void	archreboot(void);
void	archreset(void);
vlong	archrdtsc(void);
ulong archrdtsc32(void);
void	archuartpower(int, int);
void	blankscreen(int);
void	clockcheck(void);
void	clockinit(void);
void	clockpoll(void);
#define	coherence()		/* nothing to do for cache coherence for uniprocessor */
void	cursorhide(void);
void	cursorunhide(void);
void	dcflush(void*, ulong);
void	dcflushall(void);
void	dcinval(void);
int	dmaidle(Dma*);
Dma*	dmasetup(int device, void(*)(void*,ulong), void*, ulong);
int	dmastart(Dma*, void*, void*, int);
int	dmacontinue(Dma*, void*, int);
void	dmastop(Dma*);
int	dmaerror(Dma*);
void	dmafree(Dma*);
void	dmareset(void);
void	dmawait(Dma*);
void dumplongs(char *, ulong *, int);
void	dumpregs(Ureg* ureg);
void	dumpstack(void);
int	fpiarm(Ureg*);
void	fpinit(void);
ulong	getcallerpc(void*);
ulong	getcclkcfg(void);
char*	getconf(char*);
ulong	getcpsr(void);
ulong	getcpuid(void);
ulong	getspsr(void);
void	gotopc(ulong);

void	icflush(void*, ulong);
void	icflushall(void);
void	idle(void);
void	idlehands(void);
int	inb(ulong);
int	ins(ulong);
ulong	inl(ulong);
void	outb(ulong, int);
void	outs(ulong, int);
void	outl(ulong, ulong);
void inss(ulong, void*, int);
void outss(ulong, void*, int);
void	insb(ulong, void*, int);
void	outsb(ulong, void*, int);
void	intrdisable(int, int, void (*)(Ureg*, void*), void*, char*);
void	intrenable(int, int, void (*)(Ureg*, void*), void*, char*);
void	iofree(int);
#define	iofree(x)
void	ioinit(void);
int	iounused(int, int);
int	ioalloc(int, int, int, char*);
#define	ioalloc(a,b,c,d) 0
int	iprint(char*, ...);
void	installprof(void (*)(Ureg *, int));
int	isvalid_va(void*);
void	kbdinit(void);
void	ledset(int);
void	links(void);
void	mmuenable(ulong);
void*	mmucacheinhib(void*, ulong);
ulong	mmugetctl(void);
ulong	mmugetdac(void);
ulong	mmugetfar(void);
ulong	mmugetfsr(void);
void	mmuinit(void);
void*	mmukaddr(ulong);
void*	mmuphysmap(void*, ulong, ulong);
void	mmuputctl(ulong);
void	mmuputdac(ulong);
void	mmuputfsr(ulong);
void	mmuputttb(ulong);
void	mmureset(void);
void	mouseinit(void);
void*	pa2va(ulong);
void	pcimapinit(void);
int	pciscan(int, Pcidev **);
ulong	pcibarsize(Pcidev *, int);
int	pcicfgr8(Pcidev*, int);
int	pcicfgr16(Pcidev*, int);
int	pcicfgr32(Pcidev*, int);
void	pcicfgw8(Pcidev*, int, int);
void	pcicfgw16(Pcidev*, int, int);
void	pcicfgw32(Pcidev*, int, int);
void	pciclrbme(Pcidev*);
void	pcihinv(Pcidev*);
uchar	pciipin(Pcidev *, uchar);
Pcidev* pcimatch(Pcidev*, int, int);
Pcidev* pcimatchtbdf(int);
void	pcireset(void);
void	pcisetbme(Pcidev*);
void	powerenable(void (*)(int));
void	powerdisable(void (*)(int));
void	powerdown(void);
void	powerinit(void);
void	powersuspend(void);
#define procsave(p)
#define procrestore(p)
void	putcclkcfg(ulong);
long	rtctime(void);
void	screeninit(void);
void	(*screenputs)(char*, int);
int	segflush(void*, ulong);
void	setpanic(void);
void	setr13(int, void*);
int	splfhi(void);
int	splflo(void);
void	_suspendcode(void);
void	tlbinvalidateall(void);
void	tlbinvalidateaddr(void*);
void	trapinit(void);
void	trapstacks(void);
void	trapspecial(int (*)(Ureg *, uint));
void	uartconsole(void);
void	uartinstall(void);
int	uartprint(char*, ...);
ulong	va2pa(void*);
void	vectors(void);
void	vtable(void);
#define	waserror()	(up->nerrlab++, setlabel(&up->errlab[up->nerrlab-1]))
int	wasbusy(int);

#define	KADDR(p)	mmukaddr((ulong)(p))
#define PADDR(v)	va2pa((void*)(v))

ulong	timer_start(void);
ulong	timer_ticks(ulong);
int 	timer_devwait(ulong *adr, ulong mask, ulong val, int ost);
void 	timer_setwatchdog(int ost);
void 	timer_delay(int ost);
ulong	ms2tmr(int ms);
int	tmr2ms(ulong t);
void	delay(int ms);
ulong	us2tmr(int us);
int	tmr2us(ulong t);
void 	microdelay(int us);

#define	archuartclock(p,rate)	14745600

/* debugging */
extern	void	serialputs(char*, int);
extern	void	serialputc(int);
extern	void	xdelay(int);
