Alarm*	alarm(int, void (*)(Alarm*), void*);
void	alarminit(void);
void	archbacklight(int);
char*	archconfig(void);
void	archdisableuart(int);
void	archenableuart(int, int);
void	archenableusb(int);
void	archetherdisable(int);
int	archetherenable(int, int*, int*);
int	archflashreset(char*, void**, long*);
void	archinit(void);
int	archoptionsw(void);
int	bootp(int, char*);
void	cancel(Alarm*);
void	checkalarms(void);
void	clockinit(void);
void	clockintr(Ureg*, void*);
void	consinit(void);
void	cpminit(void);
void	cpuidprint(void);
#define	dcflush(a,b)
void	delay(int);
void	eieio(void);
uchar*	etheraddr(int);
int	etherinit(void);
int	etherrxpkt(int, Etherpkt*, int);
int	ethertxpkt(int, Etherpkt*, int, int);
void	exception(void);
int	flashboot(int);
int	flashbootable(int);
char*	flashconfig(int);
int	flashinit(void);
void	free(void*);
void	freeb(Block*);
int	getcfields(char*, char**, int, char*);
char*	getconf(char*);
ulong	getdec(void);
ulong	gethid0(void);
ulong	getimmr(void);
ulong	getmsr(void);
ulong	getpvr(void);
int	getstr(char*, char*, int, char*);
ulong	gettbl(void);
ulong	gettbu(void);
int	hardinit(void);
long	hardread(int, void*, long);
long	hardseek(int, long);
long	hardwrite(int, void*, long);
long	i2csend(int, void*, long);
void	i2csetup(void);
void*	ialloc(ulong, int);
Block*	iallocb(int);
void	idle(void);
int	isaconfig(char*, int, ISAConf*);
int	issqueezed(uchar*);
void	kbdchar(Queue*, int);
void	kbdinit(void);
void	kbdreset(void);
void	machinit(void);
void*	malloc(ulong);
ulong	mapalloc(RMap*, ulong, int, int);
void	mapfree(RMap*, ulong, int);
void	mapinit(RMap*, Map*, int);
void	meminit(void);
void	microdelay(int);
void	mmuinit(void);
int	optionsw(void);
void	panic(char*, ...);
int	parseether(uchar*, char*);
int	plan9boot(int, long (*)(int, long), long (*)(int, void*, long));
void	putdec(ulong);
void	puthid0(ulong);
void	putmsr(ulong);
int	qbgetc(Queue*);
void	qbputc(Queue*, int);
void	qbwrite(Queue*, Block*);
Block*	qget(Queue*);
long	qlen(Queue*);
Queue*	qopen(int, int, void (*)(void*), void*);
#define	qpass	qbwrite
void	scc2stop(void);
void	sccnmsi(int, int, int);
void	sched(void);
void	screeninit(void);
void	screenputs(char*, int);
void	sdraminit(ulong);
Partition*	sethardpart(int, char*);
Partition*	setscsipart(int, char*);
void	setvec(int, void (*)(Ureg*, void*), void*);
int	splhi(void);
int	spllo(void);
void	splx(int);
void	trapinit(void);
void	uartputs(char*, int);
void	uartsetboot(void (*f)(uchar*, int));
void	uartspecial(int, int, Queue**, Queue**, void(*)(Queue*,int));
void	uartwait(void);
long	unsqueezef(Block*, ulong*);

#define	GSHORT(p)	(((p)[1]<<8)|(p)[0])
#define	GLONG(p)	((GSHORT(p+2)<<16)|GSHORT(p))
#define	GLSHORT(p)	(((p)[0]<<8)|(p)[1])
#define	GLLONG(p)	((GLSHORT(p)<<16)|GLSHORT(p+2))

#define KADDR(a)	((void*)((ulong)(a)|KZERO))
#define PADDR(a)	((ulong)(a)&~KSEGM)

/* IBM bit field order */
#define	IBIT(b)	((ulong)1<<(31-(b)))
#define	SIBIT(n)	((ushort)1<<(15-(n)))

#define IOREGS(x, T)	((T*)((char*)m->iomem+(x)))

int	uartinit(void);
Partition*	setuartpart(int, char*);
long	uartread(int, void*, long);
long	uartseek(int, long);
