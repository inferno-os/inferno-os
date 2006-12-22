#include "../port/portfns.h"

void	addpower(Power*);
void	archbacklight(int);
void	archconfinit(void);
void	archdisableuart(int);
void	archdisableusb(void);
void	archdisablevideo(void);
void	archenableuart(int, int);
void	archenableusb(int, int);
void	archenablevideo(void);
void	archkbdinit(void);
void	archresetvideo(void);
int	archetherenable(int, int*, int*, int, int);
void	archinit(void);
int	archoptionsw(void);
void	archreboot(void);
void	archsetirxcvr(int);
uchar*	archvideobuffer(long);
ulong	baudgen(int, int);
int	brgalloc(void);
void	brgfree(int);
int	cistrcmp(char*, char*);
int	cistrncmp(char*, char*, int);
void	clockcheck(void);
void	clockinit(void);
void	clockintr(Ureg*);
void	clrfptrap(void);
#define	coherence()		/* nothing needed for uniprocessor */
void	cpminit(void);
void	cpuidprint(void);
void	dcflush(void*, ulong);
void	dcinval(void*, ulong);
void	delay(int);
void	dtlbmiss(void);
void	dumplongs(char*, ulong*, int);
void	dumpregs(Ureg*);
void	eieio(void);
void	faultpower(Ureg*);
void	firmware(int);
void	fpinit(void);
int	fpipower(Ureg*);
void	fpoff(void);
void	fprestore(FPU*);
void	fpsave(FPU*);
ulong	fpstatus(void);
char*	getconf(char*);
ulong	getdar(void);
ulong	getdec(void);
ulong	getdepn(void);
ulong	getdsisr(void);
ulong	getimmr(void);
ulong	getmsr(void);
ulong	getpvr(void);
ulong	gettbl(void);
ulong	gettbu(void);
void	gotopc(ulong);
void	icflush(void*, ulong);
void	idle(void);
#define	idlehands()			/* nothing to do in the runproc */
void	intr(Ureg*);
void	intrenable(int, void (*)(Ureg*, void*), void*, int, char*);
void	intrdisable(int, void (*)(Ureg*, void*), void*, int, char*);
int	intrstats(char*, int);
void	intrvec(void);
int	isaconfig(char*, int, ISAConf*);
int	isvalid_va(void*);
void	itlbmiss(void);
void	kbdinit(void);
void	kbdreset(void);
void	lcdpanel(int);
void	links(void);
void	mapfree(RMap*, ulong, int);
void	mapinit(RMap*, Map*, int);
void	mathinit(void);
void	mmuinit(void);
ulong*	mmuwalk(ulong*, ulong, int);
void	pcmenable(void);
void	pcmintrenable(int, void (*)(Ureg*, void*), void*);
int	pcmpin(int slot, int type);
void	pcmpower(int, int);
int	pcmpowered(int);
void	pcmsetvcc(int, int);
void	pcmsetvpp(int, int);
int	pcmslotsavail(int);
void	procsave(Proc*);
void	procsetup(Proc*);
void	putdec(ulong);
void	putmsr(ulong);
void	puttwb(ulong);
ulong	rmapalloc(RMap*, ulong, int, int);
void	screeninit(void);
int	screenprint(char*, ...);			/* debugging */
void	screenputs(char*, int);
int	segflush(void*, ulong);
void	setpanic(void);
long	spioutin(void*, long, void*);
void	spireset(void);
ulong	_tas(ulong*);
void	trapinit(void);
void	trapvec(void);
void	uartinstall(void);
void	uartspecial(int, int, Queue**, Queue**, int (*)(Queue*, int));
void	uartwait(void);	/* debugging */
void	videoreset(void);
void	videotest(void);
void	wbflush(void);

#define	waserror()	(up->nerrlab++, setlabel(&up->errlab[up->nerrlab-1]))
ulong	getcallerpc(void*);

#define KADDR(a)	((void*)((ulong)(a)|KZERO))
#define PADDR(a)	((((ulong)(a)&KSEGM)!=KSEG0)?(ulong)(a):((ulong)(a)&~KZERO))

/* IBM bit field order */
#define	IBIT(b)	((ulong)1<<(31-(b)))
#define	SIBIT(n)	((ushort)1<<(15-(n)))
