#include "../port/portfns.h"
#define dumplongs(x, y, z)
#define clockcheck()
#define setpanic()

void	links(void);
void	prom_printf(char *format, ...);	/* can't use after mmuinit() */
void	savefpregs(FPU *);
void	restfpregs(FPU*);
void	savefsr(FPenv *);
void	restfsr(FPenv *);
void	disabfp(void);
void	fpinit(void);
void	fpsave(FPU*);
void	bootargs(ulong);
void	cacheinit(void);
ulong	call_openboot(void*, ...);
void	clearftt(ulong);
#define	clearmmucache()
void	clockinit(void);
void	clock(Ureg*);
#define	coherence()		/* nothing to do on uniprocessor */
void	dcflush(void);
void	disabfp(void);
void	enabfp(void);
char*	excname(ulong);

#define	flushpage(pa)	icflush()
void	flushtlb(void);
void	flushtlbctx(void);
void	flushtlbpage(ulong);
int	fpcr(int);
int	fpquiet(void);
void	fpregrestore(char*);
void	fpregsave(char*);
int	fptrap(void);
int	getfpq(ulong*);
ulong	getfsr(void);
ulong	getpcr(void);
ulong	getphys(ulong);
ulong	getrmmu(ulong);
ulong	getpsr(void);
void	icflush(void);
int	isvalid_va(void*);
void	flushicache(void);
void	flushdcache(void);
void	flushiline(ulong);
void	flushdline(ulong);
#define	idlehands()			/* nothing to do in the runproc */
void	intrinit(void);
void	ioinit(void);
void	kbdclock(void);
void	kbdrepeat(int);
void	kbdinit(void);
void	kbdintr(void);
#define KADDR(a)	((void*)((ulong)(a)|KZERO))
#define PADDR(a)	((ulong)(a)&~KZERO)
void	kmapinit(void);
void*	kmappa(ulong, ulong);
ulong	kmapsbus(int);
ulong	kmapdma(ulong, ulong);
int	kprint(char*, ...);
void	kproftimer(ulong);
void	kunmap(KMap*);
void	lanceintr(void);
void	lancesetup(Lance*);
void	lancetoggle(void);
void	mmuinit(void);
void	mousebuttons(int);
void	printinit(void);
#define	procrestore(p)
#define	procsave(p)
#define	procsetup(x)	((p)->fpstate = FPinit)
void	putphys(ulong, ulong);
void	putrmmu(ulong, ulong);
void	putstr(char*);
void	puttbr(ulong);
void	systemreset(void);
void	screeninit(void);
void	screenputc(char *);
void	screenputs(char*, int);
void	scsiintr(void);
void	setpcr(ulong);
void	setpsr(ulong);
void	spldone(void);
void	trap(Ureg*);
void	trapinit(void);
#define	wbflush()	/* mips compatibility */
#define	waserror()	(up->nerrlab++, setlabel(&up->errlab[up->nerrlab-1]))
ulong	getcallerpc(void*);
void	dumpregs(Ureg*);

void	ns16552special(int,int,Queue**,Queue**,int (*)(Queue*,int));
char	ns16552dmarcv(int);
void	ns16552install(void);
void	ns16552intr(int);

long	dmasetup(int,void*,long,int);
void	dmaend(int);
int	dmacount(int);

void	superioinit(ulong va, uchar*, uchar*, uchar*, uchar*);
ulong	superiova(void);

uchar	superio_readctl(void);
uchar	superio_readdata(void);
void	superio_writectl(uchar val);
void	superio_writedata(uchar val);
void	outb(ulong, uchar);
uchar	inb(ulong);
