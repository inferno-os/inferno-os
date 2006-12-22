void	aamloop(int);
Alarm*	alarm(int, void (*)(Alarm*), void*);
void	alarminit(void);
int	bootp(int, char*);
void	cancel(Alarm*);
void	checkalarms(void);
void	clockinit(void);
void	consinit(void);
void	delay(int);
uchar*	etheraddr(int);
int	etherinit(void);
int	etherrxpkt(int, Etherpkt*, int);
int	ethertxpkt(int, Etherpkt*, int, int);
int	flashboot(int);
int	flashbootable(int);
char*	flashconfig(int);
int	flashinit(void);
char*	getconf(char*);
int	getcfields(char*, char**, int, char*);
int	getstr(char*, char*, int, char*);
int	hardinit(void);
long	hardread(int, void*, long);
long	hardseek(int, long);
long	hardwrite(int, void*, long);
void*	ialloc(ulong, int);
void	idle(void);
int	isaconfig(char*, int, ISAConf*);
int	isgzipped(uchar*);
int	issqueezed(uchar*);
void	kbdinit(void);
void	kbdchar(Queue*, int);
void	machinit(void);
void	meminit(void);
void	microdelay(int);
void	mmuinit(void);
uchar	nvramread(int);
void	outb(int, int);
void	outs(int, ushort);
void	outl(int, ulong);
void	outsb(int, void*, int);
void	outss(int, void*, int);
void	outsl(int, void*, int);
void	panic(char*, ...);
int	optionsw(void);
int	plan9boot(int, long (*)(int, long), long (*)(int, void*, long));
Partition*	setflashpart(int, char*);
Partition* sethardpart(int, char*);
Partition* setscsipart(int, char*);
void	setvec(int, void (*)(Ureg*, void*), void*);
void	screeninit(void);
void	screenputs(char*, int);
void setr13(int, void*);
int	splhi(void);
int	spllo(void);
void	splx(int);
void	trapinit(void);
void	uartspecial(int, int, Queue**, Queue**, void(*)(Queue*,int));
void	uartputs(char*, int);
void	uartwait(void);
long	unsqueezef(Block*, ulong*);

#define	GSHORT(p)	(((p)[1]<<8)|(p)[0])
#define	GLONG(p)	((GSHORT(p+2)<<16)|GSHORT(p))
#define	GLSHORT(p)	(((p)[0]<<8)|(p)[1])
#define	GLLONG(p)	((GLSHORT(p)<<16)|GLSHORT(p+2))

#define KADDR(a)	((void*)((ulong)(a)|KZERO))
#define PADDR(a)	((ulong)(a)&~KZERO)


void	mapinit(RMap*, Map*, int);
void	mapfree(RMap*, ulong, int);
ulong	mapalloc(RMap*, ulong, int, int);

/* IBM bit field order */
#define	IBFEXT(v,a,b) (((ulong)(v)>>(32-(b)-1)) & ~(~0L<<(((b)-(a)+1))))
#define	IBIT(b)	((ulong)1<<(31-(b)))

#define	SIBIT(n)	((ushort)1<<(15-(n)))

void*	malloc(ulong);
void	free(void*);

extern Block*	iallocb(int);
extern void	freeb(Block*);
extern Queue*	qopen(int, int, void (*)(void*), void*);
extern Block*	qget(Queue*);
extern void	qbwrite(Queue*, Block*);
extern long	qlen(Queue*);
#define	qpass	qbwrite
extern void	qbputc(Queue*, int);
extern int	qbgetc(Queue*);

int	sio_inb(int);
void	sio_outb(int, int);
void	led(int);

extern void _virqcall(void);
extern void _vfiqcall(void);
extern void _vundcall(void);
extern void _vsvccall(void);
extern void _vpabcall(void);
extern void _vdabcall(void);

void flushIcache(void);
void writeBackDC(void);
void flushDcache(void);
void flushIcache(void);
void drainWBuffer(void);

void pumainit(void);
