#include "../port/portfns.h"

void	addpower(Power*);
void	archbacklight(int);
void	archconfinit(void);
int	archconfval(char**, char**, int);
void	archdisableuart(int);
void	archdisableusb(void);
void	archdisablevideo(void);
void	archenableuart(int, int);
void	archenableusb(int, int);
void	archenablevideo(void);
void	archkbdinit(void);
void	archresetvideo(void);
void	archinit(void);
int	archoptionsw(void);
void	archreboot(void);
ulong	archuartclock(int, int);
void	archuartdma(int, int);
void	clockcheck(void);
void	clockinit(void);
void	clockintr(Ureg*);
void	clrfptrap(void);
#define	coherence()		/* nothing needed for uniprocessor */
void	compiledcr(void);
void	cpuidprint(void);
void*	dcflush(void*, ulong);
void	dcinval(void*, ulong);
void	delay(int);
void	dtlbmiss(void);
void	dumplongs(char*, ulong*, int);
void	dumpregs(Ureg*);
void	eieio(void);
void	firmware(int);
void	fpinit(void);
int	fpipower(Ureg*);
void	fpoff(void);
void	fprestore(FPU*);
void	fpsave(FPU*);
ulong	fpstatus(void);
char*	getconf(char*);
ulong	getccr0(void);
ulong	getdar(void);
ulong	getdcr(int);
ulong	getdear(void);
ulong	getdepn(void);
ulong	getdsisr(void);
ulong	getesr(void);
ulong	getimmr(void);
ulong	getmsr(void);
ulong	getpit(void);
ulong	getpvr(void);
ulong	gettbl(void);
ulong	gettbu(void);
ulong	gettsr(void);
void	gotopc(ulong);
void	icflush(void*, ulong);
void	idle(void);
void	idlehands(void);
int	inb(int);
ulong	inl(int);
int	ins(int);
void	insb(int, void*, int);
void	insl(int, void*, int);
void	inss(int, void*, int);
void	intr(Ureg*);
void	intrenable(int, void (*)(Ureg*, void*), void*, int, char*);
void	intrdisable(int, void (*)(Ureg*, void*), void*, int, char*);
int	intrstats(char*, int);
void	intrvec(void);
void	intrcvec(void);
void	ioinit(void);
void	ioreset(void);
int	isaconfig(char*, int, ISAConf*);
int	isvalid_va(void*);
void	itlbmiss(void);
void	kbdinit(void);
void	kbdreset(void);
void*	kmapphys(void*, ulong, ulong, ulong, ulong);
void	lcdpanel(int);
void	links(void);
void	mapfree(RMap*, ulong, int);
void	mapinit(RMap*, Map*, int);
void	mathinit(void);
void	mmuinit(void);
void*	mmucacheinhib(void*, ulong);
ulong	mmumapsize(ulong);
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
void	procsave(Proc*);
void	procsetup(Proc*);
void	putdcr(int, ulong);
void	putesr(ulong);
void	putevpr(ulong);
void	putmsr(ulong);
void	putpit(ulong);
void	puttcr(ulong);
void	puttsr(ulong);
void	puttwb(ulong);
ulong	rmapalloc(RMap*, ulong, int, int);
long	rtctime(void);
void	screeninit(void);
int	screenprint(char*, ...);			/* debugging */
void	(*screenputs)(char*, int);
int	segflush(void*, ulong);
void	toggleled(int);
void	setpanic(void);
ulong	_tas(ulong*);
ulong	tlbrehi(int);
ulong	tlbrelo(int);
int	tlbsxcc(void*);
void	tlbwehi(int, ulong);
void	tlbwelo(int, ulong);
void	trapinit(void);
void	trapvec(void);
void	trapcvec(void);
void	uartinstall(void);
void	uartspecial(int, int, Queue**, Queue**, int (*)(Queue*, int));
void	uartwait(void);	/* debugging */
void	wbflush(void);

#define	waserror()	(up->nerrlab++, setlabel(&up->errlab[up->nerrlab-1]))
ulong	getcallerpc(void*);

#define	isphys(a)	(((ulong)(a)&KSEGM)!=KSEG0 && ((ulong)(a)&KSEGM)!=KSEG1)
#define KADDR(a)	((void*)((ulong)(a)|KZERO))
#define PADDR(a)	(isphys(a)?(ulong)(a):((ulong)(a)&~KSEGM))

/* IBM bit field order */
#define	IBIT(b)	(((ulong)(1<<31))>>(b))
#define	SIBIT(n)	((ushort)1<<(15-(n)))
#define	CIBIT(n)	((uchar)1<<(7-(n)))

