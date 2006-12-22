/*
 *  Boffin MPEG decoder
 */
#include	"u.h"
#include	"../port/lib.h"
#include	"mem.h"
#include	"dat.h"
#include	"fns.h"
#include	"../port/error.h"
#include	"zoran.h"
#include	"crystal.h"
#include	"io.h"

enum
{

	CPUACCCTRL      = 0x20,	/* Trident Window Chip control registers */
	CPUACCMD        = 0x21,
	BNKADR          = 0x22,
	SYSCONFIG       = 0x23,
	VGACOMP         = 0x24,
	VGAMASK         = 0x25,
	VIDCOMPL        = 0x26,
	VIDCOMPH        = 0x27,
	MOS             = 0x28,
	DISPCTRL        = 0x29,
	CAPCTRL         = 0x2a,
	OVLKT           = 0x2b,
	OVLWINHSTRT     = 0x2c,
	OVLWINVSTRT     = 0x2d,
	OVLWINHEND      = 0x2e,
	OVLWINVEND      = 0x2f,
	RESERVED1       = 0x30,
	RESERVED2       = 0x31,
	DISPWINVSTRT1   = 0x32,
	DISPWINVSTRT2   = 0x33,
	DISPWINVEND     = 0x34,
	DISPWINHSTRT1   = 0x35,
	DISPWINHSTRT2   = 0x36,
	DISPWINHEND     = 0x37,
	CAPWINVSTRT     = 0x38,
	CAPWINHSTRT     = 0x39,
	CAPWINVMF       = 0x3a,
	CAPWINHMF       = 0x3b,
	RESERVED3       = 0x3c,
	CAPMASK         = 0x3d,
	BNKPOLATION     = 0x3e,
	SYNCPOL         = 0x3f,
	DISPVTOTAL      = 0x40,
	DISPHTOTAL      = 0x41,
	DISPVSTRT       = 0x42,
	DISPVEND        = 0x43,
	DISPHSTRT       = 0x44,
	DISPHEND        = 0x45,
	DISPSYNCW       = 0x46,
	DISPCRTCCTRL    = 0x47,
	CAPVTOTAL       = 0x48,
	CAPHTOTAL       = 0x49,
	CAPVSTRT        = 0x4a,
	CAPVEND         = 0x4b,
	CAPHSTRT        = 0x4c,
	CAPHEND         = 0x4d,
	CAPSYNCW        = 0x4e,
	CAPCRTCCTRL     = 0x4f,
	VIDLUTDACRW     = 0x50,
	VIDLUTDACRW0    = (VIDLUTDACRW),
	VIDLUTDACRW1    = (VIDLUTDACRW+1),
	VIDLUTDACRW2    = (VIDLUTDACRW+2),
	VIDLUTDACRW3    = (VIDLUTDACRW+3),
	VIDLUTDACRW4    = (VIDLUTDACRW+4),
	VIDLUTDACRW5    = (VIDLUTDACRW+5),
	VIDLUTDACRW6    = (VIDLUTDACRW+6),
	VIDLUTDACRW7    = (VIDLUTDACRW+7),
	VGALUTDACRW     = 0x58,
	VGALUTDACRW0    = (VGALUTDACRW),
	VGALUTDACRW1    = (VGALUTDACRW+1),
	VGALUTDACRW2    = (VGALUTDACRW+2),
	VGALUTDACRW3    = (VGALUTDACRW+3),
	VGALUTDACRW4    = (VGALUTDACRW+4),
	VGALUTDACRW5    = (VGALUTDACRW+5),
	VGALUTDACRW6    = (VGALUTDACRW+6),
	VGALUTDACRW7    = (VGALUTDACRW+7),
	HZOOMF          = 0x60,
	VZOOMF          = 0x61,
	DELAY1          = 0x62,
	DELAY2          = 0x63,

	TRILO      	= 0,
	TRIHI     	= 1,
	TRIINDEX    	= 2,

	SCL             = 0x02,
	SDA             = 0x01,
	I2CR		= 0x2B,
	SAA7110		= 0x9c,
	WRITE_C		= 0x00,
	I2DLY		= 5,
};

enum
{
	ZR36100		= 0x1e0,
	ZRIRQ		= 15,
	ZRDMA		= 6,

	ZRIDREG		= 4,				/* offset */
	ZRMACH210   	= 6,				/* offset */
	ZRREG0      	= 8,				/* offset */
	ZRREG1		= 10,				/* offset */
	ZRSR		= ZRREG1,			/* offset */
	ZRRDY		= (1<<3),
	ZRIDLE		= (1<<2),
	ZRREG2		= 12,				/* offset */
	ZRREG3		= 14,				/* offset */

	SIFwidth	= 320,
	SIFheight	= 240,

	IDPCOUNT	= 3064,
	PMDPCOUNT	= 2048,
	SVMDPCOUNT	= 2048,

	HIWAT		= 2*128*1024,
	DMABLK		= 16384,
};

static struct {
	int	zrport;
	int	irq;
	int	dma;
	int	trport;
} mpegconf;

static	char Evmode[] = "video format not supported";
static	char Eaudio[] = "invalid audio layer";
static	char Earate[] = "bad audio sample rate";

/* Status bits depend on board revision */
static	short	STDBY;
static	short	VIDSEL;
static	short	VSNIRQn;
static	short	INTENAn;
static	short	DSPBOOT;
static	short	DSPRST;
static	short	MPGRST;
static	int	machsr;
static	int	dopen;
static	int	started;
static	int	stop;
static	int	pause;
static	int	sp2br;
static	int	sp2cd;
static	char	properties[] = "video mpeg1,sif\naudio musicam,I musicam,II\n";
static	void	inittrident(void);
static	int	initzoran(void);
static	void	initcrystal(void);
static	void	mpegintr(Ureg*, void*);
static	void	setwindow(int, char**);
static	void	freebufs(void);
static	int	mkbuf(char*, int);

typedef struct Buf Buf;
struct Buf
{
	int	nchar;
	uchar*	ptr;
	Buf*	link;
	uchar	data[1];
};

static struct
{
	Lock;
	int	qlen;
	Buf*	head;
	Buf*	tail;
	Rendez	flow;
} bqueue;

static int
zrstatus(void)
{
	return ins(mpegconf.zrport+ZRSR) & 0xf;
}

static int
zrwaitrdy(int timo, char *msg)
{
	int i;

	for(i = 0; i < timo; i++)
		if(ins(mpegconf.zrport+ZRSR) & ZRRDY)
			return 0;

	print("devmpeg: device not ready %s\n", msg);
	return 1;
}

static void
zrdma(Buf *b)
{
	int n;

	n = dmasetup(mpegconf.dma, b->ptr, b->nchar, 0);
	b->ptr += n;
	b->nchar -= n;
	bqueue.qlen -= n;
}

static void
triwr(int reg, int val)
{
	outb(mpegconf.trport+TRIINDEX, reg);
	outb(mpegconf.trport+TRILO, val);
	outb(mpegconf.trport+TRIHI, val>>8);
}

static int
trird(int reg)
{
	int v;

	outb(mpegconf.trport+TRIINDEX, reg);
	v = inb(mpegconf.trport+TRILO);
	v |= inb(mpegconf.trport+TRIHI)<<8;

	return v;
}

enum
{
	Qdir,
	Qdata,
	Qctl,
};
static Dirtab mpegtab[]=
{
	"mpeg",		{Qdata, 0},	0,	0666,
	"mpegctl",	{Qctl,  0},	0,	0666,
};

static void
mpegreset(void)
{
	ISAConf isa;

	mpegconf.zrport = ZR36100;
	mpegconf.irq = ZRIRQ;
	mpegconf.dma = ZRDMA;

	memset(&isa, 0, sizeof(isa));
	if(isaconfig("mpeg", 0, &isa) == 0)
		return;	
	if(isa.port)
		mpegconf.zrport = isa.port;
	if(isa.irq)
		mpegconf.irq = isa.irq;
	if(isa.dma)
		mpegconf.dma = isa.dma;
	dmainit(mpegconf.dma, 64*1024);
	print("mpeg0: port 0x%uX, irq %d, dma %d\n",
		mpegconf.zrport, mpegconf.irq, mpegconf.dma);
	mpegconf.trport = mpegconf.zrport+0x100;
	intrenable(VectorPIC+mpegconf.irq, mpegintr, 0, BUSUNKNOWN);
}

static void
mpeginit(void)
{
	if(mpegconf.trport == 0)
		return;

	inittrident();
	setwindow(0, 0);
}

static Chan*
mpegattach(char *spec)
{
	if(mpegconf.trport == 0)
		error(Enodev);

	return devattach('E', spec);
}

static int
mpegwalk(Chan *c, char *name)
{
	return devwalk(c, name, mpegtab, nelem(mpegtab), devgen);
}

static void
mpegstat(Chan *c, char *db)
{
	devstat(c, db, mpegtab, nelem(mpegtab), devgen);
}

static Chan*
mpegopen(Chan *c, int omode)
{
	switch(c->qid.path) {
	default:
		break;
	case Qdata:
		if(dopen)
			error(Einuse);
		dopen = 1;
		break;
	}
	return devopen(c, omode, mpegtab, nelem(mpegtab), devgen);
}

static void
mpegclose(Chan *c)
{
	int i;

	switch(c->qid.path) {
	default:
		break;
	case Qdata:
		if((c->flag & COPEN) == 0)
			break;
		if(started) {
			for(i = 0; i < 50; i++) {
				if(ins(mpegconf.zrport+ZRSR) & ZRIDLE)
					break;
				tsleep(&up->sleep, return0, 0, 100);
			}
		}
		if(stop != 0)
			outs(mpegconf.zrport+ZRREG1, 0x1000);
		microdelay(15);
		outs(mpegconf.zrport+ZRREG1, 0x8000);
		freebufs();
		dopen = 0;
	}
}

static long
mpegread(Chan *c, void *a, long n, ulong off)
{
	switch(c->qid.path & ~CHDIR){
	default:
		error(Eperm);
	case Qdir:
		return devdirread(c, a, n, mpegtab, nelem(mpegtab), devgen);
	case Qctl:
		return readstr(off, a, n, properties);
	}
	return 0;
}

#define SCALE(a, b)	((((a)<<10)/(b))-1024)
enum
{
	CWINVF = 0x3ff,
	CWINHF = 0x1da,
};

static void
setwindow(int nf, char **field)
{
	int minx, miny, maxx, maxy, width, height;

	if(field == 0) {
		minx = 0;
		miny = 0;
		maxx = 0;
		maxy = 0;
	}
	else {
		if(nf != 5)
			error(Ebadarg);

		minx = strtoul(field[1], 0, 0);
		miny = strtoul(field[2], 0, 0);
		maxx = strtoul(field[3], 0, 0) + 8;
		maxy = strtoul(field[4], 0, 0);
	}

	triwr(OVLWINHSTRT, minx);
	triwr(OVLWINVSTRT, miny);
	triwr(OVLWINHEND, maxx+12);
	triwr(OVLWINVEND, maxy);

	width = maxx - minx;
	height = maxy - miny;
	if(width >= SIFwidth) {
		triwr(HZOOMF, SCALE(width, SIFwidth));
		triwr(CAPWINHMF, CWINHF);
	}
	else {
		triwr(HZOOMF, SCALE(SIFwidth, SIFwidth));
		triwr(CAPWINHMF, width*CWINHF/SIFwidth);
	}
	if(height >= SIFheight) {
		triwr(VZOOMF, SCALE(height, SIFheight));
		triwr(CAPWINVMF, CWINVF);
	}
	else {
		triwr(VZOOMF, SCALE(SIFheight, SIFheight));
		triwr(CAPWINVMF, height*CWINVF/SIFheight);
	}
}

static int
mpegflow(void*)
{
	return bqueue.qlen < HIWAT || stop;
}

static int
mkbuf(char *d, int n)
{
	Buf *b;

	b = malloc(sizeof(Buf)+n);
	if(b == 0)
		return 0;

	memmove(b->data, d, n);
	b->ptr = b->data;
	b->nchar = n;
	b->link = 0;

	ilock(&bqueue);
	bqueue.qlen += n;
	if(bqueue.head)
		bqueue.tail->link = b;
	else
		bqueue.head = b;
	bqueue.tail = b;
	iunlock(&bqueue);

	return 1;
}

static void
freebufs(void)
{
	Buf *next;

	ilock(&bqueue);
	bqueue.qlen = 0;
	while(bqueue.head) {
		next = bqueue.head->link;
		free(bqueue.head);
		bqueue.head = next;
	}
	iunlock(&bqueue);
}

typedef struct Audio Audio;
struct Audio {
	int rate;
	int cd;
	int br;
};

static Audio AudioclkI[] = 
{
	 64000, 0x000000bb, 0x00071797,
	 96000, 0x0000007d, 0x00071c71,
	128000, 0x0000005d, 0x00070de1,
	160000, 0x0000004b, 0x00071c71,
	192000, 0x0000003e, 0x00070de1,
	224000, 0x00000035, 0x00070906,
	256000, 0x0000002e, 0x0006fa76,
	288000, 0x00000029, 0x0006ff51,
	320000, 0x00000025, 0x0007042b,
	352000, 0x00000022, 0x00071797,
	384000, 0x0000001f, 0x00070de1,
	416000, 0x0000001c, 0x0006e70b,
	448000, 0x0000001a, 0x0006e70b,
};

static Audio  AudioclkII[] = 
{
	 48000, 0x000000fa, 0x00071c71,
	 56000, 0x000000d6, 0x00071a04,
	 64000, 0x000000bb, 0x00071797,
	 80000, 0x00000096, 0x00071c71,
	 96000, 0x0000007d, 0x00071c71,
	112000, 0x0000006b, 0x00071a04,
	128000, 0x0000005d, 0x00070de1,
	160000, 0x0000004b, 0x00071c71,
	192000, 0x0000003e, 0x00070de1,
	224000, 0x00000035, 0x00070906,
	256000, 0x0000002e, 0x0006fa76,
	320000, 0x00000025, 0x0007042b,
	384000, 0x0000001f, 0x00070de1,
};

static long
mpegwrite(Chan *c, char *a, long n, vlong)
{
	Audio *t;
	int i, nf, l, x;
	char buf[128], *field[10];

	switch(c->qid.path & ~CHDIR) {
	case Qctl:
		if(n > sizeof(buf)-1)
			n = sizeof(buf)-1;
		memmove(buf, a, n);
		buf[n] = '\0';

		nf = getfields(buf, field, nelem(field), 1, " \t\n");
		if(nf < 1)
			error(Ebadarg);

		if(strcmp(field[0], "stop") == 0) {
			if(started == 0)
				error("not started");
			if(pause) {
				pause = 0;
				outs(mpegconf.zrport+ZRREG1, 0x9000);
			}
			stop = 1;
			outs(mpegconf.zrport+ZRREG1, 0x1000);
			microdelay(15);
			outs(mpegconf.zrport+ZRREG1, 0x8000);
			wakeup(&bqueue.flow);
			return n;
		}
		if(strcmp(field[0], "pause") == 0) {
			if(started == 0)
				error("not started");
			if(pause == 0) {
				pause = 1;
				outs(mpegconf.zrport+ZRREG1, 0x1000);
			}
			else {
				pause = 0;
				outs(mpegconf.zrport+ZRREG1, 0x9000);
			}
			return n;
		}
		if(strcmp(field[0], "window") == 0) {
			setwindow(nf, field);
			return n;
		}
		if(strcmp(field[0], "audio") == 0) {
			if(nf < 3)
				error(Ebadarg);
			t = 0;
			if(strcmp(field[1], "musicam,I") == 0)
				t = AudioclkI;
			else
			if(strcmp(field[1], "musicam,II") == 0)
				t = AudioclkII;
			else
				error(Eaudio);
			x = strtoul(field[2], 0, 0);
			for(i = 0; t[i].rate != 0; i++) {
				if(t[i].rate == x) {
					sp2cd = t[i].cd;
					sp2br = t[i].br;
					return n;
				}
			}
			error(Earate);
		}
		if(strcmp(field[0], "video") == 0) {
			if(nf != 3)
				error(Ebadarg);
			if(strcmp(field[1], "iso11172") != 0)
				error(Evmode);
			if(strcmp(field[2], "mpeg1,sif") != 0)
				error(Evmode);
			return n;
		}
		if(strcmp(field[0], "init") == 0) {
			inittrident();
			for(i = 0; i < 3; i++)
				if(initzoran() != -1)
					break;
			initcrystal();
			started = 0;
			stop = 0;
			pause = 0;
			return n;
		}
		error(Ebadarg);
	case Qdata:
		if(n & 1)
			error("odd write");

		while(!mpegflow(0))
			sleep(&bqueue.flow, mpegflow, 0);
		
		if(stop)
			error("stopped");

		x = n;
		while(x) {
			l = x;
			if(l > DMABLK)
				l = DMABLK;
			if(mkbuf(a, l) == 0)
				error(Enomem);
			x -= l;
			a += l;
		}
		if(started || bqueue.qlen < (HIWAT*3)/4)
			break;

		zrdma(bqueue.head);
		outs(mpegconf.zrport+ZRREG1, 0x0000);
		outs(mpegconf.zrport+ZRREG1, 0x0000);
		started = 1;
		break;
	default:
		error(Ebadusefd);
	}
	return n;
}

Dev mpegdevtab = {
	'E',
	"mpeg",

	mpegreset,
	mpeginit,
	mpegattach,
	devdetach,
	devclone,
	mpegwalk,
	mpegstat,
	mpegopen,
	devcreate,
	mpegclose,
	mpegread,
	devbread,
	mpegwrite,
	devbwrite,
	devremove,
	devwstat,
};

static void
initctl(void)
{
	int boardid;
	static int done;

	if(done)
		return;

	boardid = ins(mpegconf.zrport+ZRIDREG);
	if(boardid == 0xE3E3) {		/* REV c/d */
		STDBY   = 0x0000;
		VIDSEL  = 0x2020;
		VSNIRQn = 0x1010;
		INTENAn = 0x0808;
		DSPBOOT = 0x0404;
		DSPRST  = 0x0202;
		MPGRST  = 0x0101;
	}
	else {				/* REV b */
		STDBY   = 0x0404;
		VIDSEL  = 0x1010;
		VSNIRQn = 0x8080;
		INTENAn = 0x4040;
		DSPBOOT = 0x0202;
		DSPRST  = 0x0101;
		MPGRST  = 0x2020;
	}
	done = 1;

}

/*
 * nbl (reg 0x1[ab]) was 0x0022, nblf (reg 1[cd]) was 0x0006
 */
static uchar
zrparam[] = 
{
/* 00 */  0xEF, 0x01, 0x01, 0x01, 0x80, 0x0E, 0x31, 0x00,
/* 08 */  0x01, 0x60, 0x00, 0x00, 0x03, 0x5A, 0x00, 0x7A,
/* 10 */  0x00, 0x10, 0x00, 0x08, 0x00, 0xF0, 0x00, 0x00,
/* 18 */  0x02, 0x0D, 0x00, 0x1e, 0x00, 0x0a, 0x00, 0x02, 
/* 20 */  0x40, 0x06, 0x80, 0x00, 0x80, 0x00, 0x05, 0x9B, 
/* 28 */  0x07, 0x16, 0xFD, 0x25, 0xFE, 0xA0, 0x00, 0x00,
/* 30 */  0x00, 0x07, 0x0d, 0xe1, 0x00, 0x00, 0x00, 0x3E,
/* 38 */  0x00, 0x00, 0x09, 0x51, 0x00, 0x00, 0xCD, 0xFE,
/* 40 */  0x60, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 
/* 48 */  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
/* 50 */  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
/* 58 */  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
/* 60 */  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
/* 68 */  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
/* 70 */  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
/* 78 */  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
};

static int
initzoran(void)
{
	int i, nbytes, zrs;

	initctl();
	freebufs();

	machsr = DSPRST|VSNIRQn;
	outs(mpegconf.zrport+ZRMACH210, machsr);
	microdelay(4000);

	machsr |= STDBY;
	outs(mpegconf.zrport+ZRMACH210, machsr);
	microdelay(4000);

	machsr |= MPGRST;
	outs(mpegconf.zrport+ZRMACH210, machsr);
	microdelay(4000);
	machsr &= ~MPGRST;
	outs(mpegconf.zrport+ZRMACH210, machsr);
	microdelay(4000);
	machsr |= MPGRST;
	outs(mpegconf.zrport+ZRMACH210, machsr);
	microdelay(4000);

	if(zrwaitrdy(2000, "load IDP"))
		return -1;

	for(i = 0; i < IDPCOUNT; i++)
		outb(mpegconf.zrport+ZRREG2, zrmpeg1[i]);

	if(((zrs = zrstatus()) & 3) != 3) {
/*		print("devmpeg: error loading IDP sr=%2.2ux\n", zrs);	*/
		USED(zrs);
		return -1;
	}

	if(zrwaitrdy(2000, "load PMDP"))
		return -1;

	for(i = 0; i < PMDPCOUNT; i++)
		outb(mpegconf.zrport+ZRREG3, zrmpeg2[i]);

	if(((zrs = zrstatus()) & 3) != 3) {
/*		print("devmpeg: error loading PMDP sr=%2.2ux\n", zrs);	*/
		USED(zrs);
		return -1;
	}

	zrparam[0x36] = sp2cd>>8;
	zrparam[0x37] = sp2cd>>0;
	zrparam[0x31] = sp2br>>16;
	zrparam[0x32] = sp2br>>8;
	zrparam[0x33] = sp2br>>0;

	nbytes = 16;
	for(i = 0; i < 128; i++) {
		if(nbytes >= 16) {
			if(zrwaitrdy(2000, "load parameters"))
				return -1;
			nbytes = 0;
		}
		outb(mpegconf.zrport+ZRREG0, zrparam[i]);
		nbytes++;
	}

	if(zrwaitrdy(2000, "load SVMDP"))
		return -1;

	for(i = 0; i < SVMDPCOUNT; i++)
		outb(mpegconf.zrport+ZRREG3, zrmpeg3s[i]);

	if(((zrs = zrstatus()) & 3) != 3) {
/*		print("devmpeg: error loading SVMDP sr=%2.2ux\n", zrs);	*/
		USED(zrs);
		return -1;
	}
	return 0;
}

static struct
{
	short	reg;
	ushort	val;
} trireg[] =
{
	0x20, 0x0400,
	0x21, 0x00e9,
	0x22, 0x0000,
	0x23, 0x07ee,
	0x24, 0x0005,
	0x25, 0xff00,
	0x26, 0x0000,
	0x27, 0x7fff,
	0x28, 0x0004,
	0x29, 0x88a0,
	0x2a, 0x0011,
	0x2b, 0x8540,
	0x2c, 0x00c4,
	0x2d, 0x00ac,
	0x2e, 0x020f,
	0x2f, 0x019d,
	0x30, 0x00bd,
	0x31, 0x00ff,
	0x32, 0x0000,
	0x33, 0x0000,
	0x34, 0x03ff,
	0x35, 0x0000,
	0x36, 0x0000,
	0x37, 0x03ff,
	0x38, 0x0000,
	0x39, 0x0000,
	0x3a, 0x03ff,
	0x3b, 0x01da,
	0x3c, 0xe8ce,
	0x3d, 0x2ac0,
	0x3e, 0x891f,
	0x3f, 0x3e25,
	0x40, 0x03ff,
	0x41, 0x01ff,
	0x42, 0x001f,
	0x43, 0x01ff,
	0x44, 0x003b,
	0x45, 0x0186,
	0x46, 0x1d06,
	0x47, 0x1a4f,
	0x48, 0x020d,
	0x49, 0x01ad,
	0x4a, 0x001b,
	0x4b, 0x01fd,
	0x4c, 0x003a,
	0x4d, 0x034b,
	0x4e, 0x2006,
	0x4f, 0x0083,
	0x50, 0xef08,
	0x51, 0xef3a,
	0x52, 0xefff,
	0x53, 0xef08,
	0x54, 0xef08,
	0x55, 0xef15,
	0x56, 0xefc0,
	0x57, 0xef08,
	0x58, 0xefef,
	0x59, 0xefef,
	0x5a, 0xefef,
	0x5b, 0xefef,
	0x5c, 0xefef,
	0x5d, 0xefef,
	0x5e, 0xefef,
	0x5f, 0xefef,
	0x60, 0x0000,
	0x61, 0x0004,
	0x62, 0x0020,
	0x63, 0x8080,
	0x64, 0x0300,
	-1
};

static void
clrI2C(uchar b)
{
	uchar t;

	outb(mpegconf.trport+TRIINDEX, I2CR);
	t = inb(mpegconf.trport+TRIHI);
	t &= ~b;
	outb(mpegconf.trport+TRIHI, t);
}

static void
setI2C(uchar b)
{
	uchar t;

	outb(mpegconf.trport+TRIINDEX, I2CR);
	t = inb(mpegconf.trport+TRIHI);
	t |= b;
	outb(mpegconf.trport+TRIHI, t);
}

static void
startI2C(void)
{
	setI2C(SDA);
	setI2C(SCL);
	microdelay(I2DLY);
	clrI2C(SDA);
	microdelay(I2DLY);
	clrI2C(SCL);
	microdelay(I2DLY);
}

static void
endI2C(void)
{
	clrI2C(SDA);
	clrI2C(SCL);
	microdelay(I2DLY);
	setI2C(SCL);
	microdelay(I2DLY);
	setI2C(SDA);
	microdelay(I2DLY);
}

static void
wrI2Cbit(uchar b)
{
	clrI2C(SDA);
	clrI2C(SCL);
	microdelay(I2DLY);
	if(b & 1) {
		setI2C(SDA);
		microdelay(I2DLY);
		setI2C(SCL);
		microdelay(I2DLY);
		clrI2C(SCL);
		microdelay(I2DLY);
		clrI2C(SDA);
		microdelay(I2DLY);
	}
	else {
		setI2C(SCL);
		microdelay(I2DLY);
		clrI2C(SCL);
		microdelay(I2DLY);
	}
}

static void
wrI2CB(unsigned char data)
{
	int i;

	for(i = 0; i < 8; i++)
		wrI2Cbit(data >>(7-i));
}

static int
rdI2CBit(void)
{
	int bit = 1;

	setI2C(SDA);
	clrI2C(SCL);
	setI2C(SCL);
	outb(mpegconf.trport+TRIINDEX, I2CR);
	if(inb(mpegconf.trport+TRIHI) & SDA)
		bit = 0;
	clrI2C(SDA);
	clrI2C(SCL);

	return bit;
}

static int
wrI2CD(uchar data)
{
	int r;
	ulong s;

	s = splhi();
	wrI2CB(data);
	r = rdI2CBit();
	splx(s);
	return r;
}

static uchar
setupSAA7110[] =
{
	/* Digital */
	0x4c, 0x3c, 0x0d, 0xef, 0xbd, 0xf0, 0x40, 0x03, 
	0xf8, 0xf8, 0x90, 0x90, 0x00, 0x02, 0x10, 0x77,
	0x00, 0x2c, 0x40, 0x40, 0x3b, 0x10, 0xfc, 0xd2,
	0xf0, 0x80,

	/* Analog */
	0xd9, 0x16, 0x40, 0x40, 0x80, 0x40, 0x80, 0x4f,
	0xfe, 0x01, 0xcf, 0x0f, 0x03, 0x01, 0x81, 0x0a,
	0x40, 0x35, 0x02, 0x8c, 0x03
};

static void
addrI2CB(int addr, int val)
{
	ulong s;

	s = splhi();
	startI2C();
	wrI2CD(SAA7110|WRITE_C);
	wrI2CD(addr);
	wrI2CD(val);
	endI2C();
	splx(s);
}

static void
inittrident(void)
{
	int i;

	for(i = 0; trireg[i].reg != -1; i++)
		triwr(trireg[i].reg, trireg[i].val);

	for(i = 0; i < 47; i++)
		addrI2CB(i, setupSAA7110[i]); 
}

static void
initcrystal(void)
{
	int i;
	static int done;

	if(done)
		return;

	done = 1;

	initctl();

	/* Reboot the Musicam decoder */
	clrI2C(SCL);
	clrI2C(SDA);
	machsr |= DSPRST;
	outs(mpegconf.zrport+ZRMACH210, machsr);
	machsr |= DSPBOOT;
	outs(mpegconf.zrport+ZRMACH210, machsr);
	machsr &= ~DSPRST;
	outs(mpegconf.zrport+ZRMACH210, machsr);
	machsr |= DSPRST;
	outs(mpegconf.zrport+ZRMACH210, machsr);
	machsr &= ~DSPBOOT;
	outs(mpegconf.zrport+ZRMACH210, machsr);

	startI2C();
	wrI2CD(0);
	for(i = 0; i < sizeof(crystal); i++ ) 
		wrI2CD(crystal[i]);
	endI2C();
}

static void
mpegintr(Ureg*, void*)
{
	Buf *b;

	b = bqueue.head;
	if(b == 0 || dmadone(mpegconf.dma) == 0)
		return;

	dmaend(mpegconf.dma);
	if(b->nchar == 0) {
		bqueue.head = b->link;
		free(b);

		b = bqueue.head;
		if(b == 0) {
			started = 0;
			return;
		}
	}
	zrdma(b);
	wakeup(&bqueue.flow);
}
