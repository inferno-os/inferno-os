#include	"u.h"
#include	"../port/lib.h"
#include	"mem.h"
#include	"dat.h"
#include	"fns.h"
#include	"../port/error.h"

#include	"io.h"
#include	"archipe.h"

enum {
	FPGASIZE = 8*1024*1024,
	FPGATMR = 2-1,	/* BCLK timer number (mapped to origin 0) */
	TIMERSH = FPGATMR*4,	/* timer field shift */

	COM3=	IBIT(1)|IBIT(2),	/* sccr: clock output disabled */

	ConfDone = 1<<1,
	nStatus = 1<<0,
};

/*
 * provisional FPGA interface for simple development work;
 * for more complex things, use this to load the device then have a
 * purpose-built device driver or module
 */

enum{
	Qdir,
	Qmemb,
	Qmemw,
	Qprog,
	Qctl,
	Qclk,
	Qstatus,
};

static struct {
	QLock;
	int	clkspeed;
} fpga;

static void resetfpga(void);
static void	startfpga(int);
static int endfpga(void);
static int fpgastatus(void);
static void powerfpga(int);
static void vclkenable(int);
static void vclkset(char*, char*, char*, char*);
static void memmovew(ushort*, ushort*, long);

static Dirtab fpgadir[]={
	".",			{Qdir, 0, QTDIR},	0,	0555,
	"fpgamemb",		{Qmemb, 0},	FPGASIZE,	0666,
	"fpgamemw",		{Qmemw, 0},	FPGASIZE, 0666,
	"fpgaprog",	{Qprog, 0},	0,	0222,
	"fpgastatus",	{Qstatus, 0},	0,	0444,
	"fpgactl",		{Qctl, 0},		0,	0666,
	"fpgaclk",		{Qclk, 0},		0,	0666,
};

static char Eodd[] = "odd count or offset";

static void
fpgareset(void)
{
	powerfpga(0);
}

static Chan*
fpgaattach(char *spec)
{
	return devattach('G', spec);
}

static Walkqid*
fpgawalk(Chan *c, Chan *nc, char **name, int nname)
{
	return devwalk(c, nc, name, nname, fpgadir, nelem(fpgadir), devgen);
}

static int
fpgastat(Chan *c, uchar *dp, int n)
{
	return devstat(c, dp, n, fpgadir, nelem(fpgadir), devgen);
}

static Chan*
fpgaopen(Chan *c, int omode)
{
	return devopen(c, omode, fpgadir, nelem(fpgadir), devgen);
}

static void
fpgaclose(Chan*)
{
}

static long	 
fpgaread(Chan *c, void *buf, long n, vlong offset)
{
	int v;
	char stat[32], *p;

	if(c->qid.type & QTDIR)
		return devdirread(c, buf, n, fpgadir, nelem(fpgadir), devgen);

	switch((ulong)c->qid.path){
	case Qmemb:
		if(offset >= FPGASIZE)
			return 0;
		if(offset+n >= FPGASIZE)
			n = FPGASIZE-offset;
		memmove(buf, KADDR(FPGAMEM+offset), n);
		return n;
	case Qmemw:
		if((n | offset) & 1)
			error(Eodd);
		if(offset >= FPGASIZE)
			return 0;
		if(offset+n >= FPGASIZE)
			n = FPGASIZE-offset;
		memmovew((ushort*)buf, (ushort*)KADDR(FPGAMEM+offset), n);
		return n;
	case Qstatus:
		v = fpgastatus();
		p = seprint(stat, stat+sizeof(stat), "%sconfig", v&ConfDone?"":"!");
		seprint(p, stat+sizeof(stat), " %sstatus\n", v&nStatus?"":"!");
		return readstr(offset, buf, n, stat);
	case Qclk:
		return readnum(offset, buf, n, fpga.clkspeed, NUMSIZE);
	case Qctl:
	case Qprog:
		return 0;
	}
	error(Egreg);
	return 0;		/* not reached */
}

static long	 
fpgawrite(Chan *c, void *buf, long n, vlong offset)
{
	int i, j, v;
	ulong w;
	Cmdbuf *cb;
	ulong *cfg;
	uchar *cp;

	switch((ulong)c->qid.path){
	case Qmemb:
		if(offset >= FPGASIZE)
			return 0;
		if(offset+n >= FPGASIZE)
			n = FPGASIZE-offset;
		memmove(KADDR(FPGAMEM+offset), buf, n);
		return n;
	case Qmemw:
		if((n | offset) & 1)
			error(Eodd);
		if(offset >= FPGASIZE)
			return 0;
		if(offset+n >= FPGASIZE)
			n = FPGASIZE-offset;
		memmovew((ushort*)KADDR(FPGAMEM+offset), (ushort*)buf, n);
		return n;
	case Qctl:
		cb = parsecmd(buf, n);
		if(waserror()){
			free(cb);
			nexterror();
		}
		if(cb->nf < 1)
			error(Ebadarg);
		if(strcmp(cb->f[0], "reset") == 0)
			resetfpga();
		else if(strcmp(cb->f[0], "bclk") == 0){
			v = 48;
			if(cb->nf > 1)
				v = strtoul(cb->f[1], nil, 0);
			if(v <= 0 || 48%v != 0)
				error(Ebadarg);
			startfpga(48/v-1);
		}else if(strcmp(cb->f[0], "vclk") == 0){
			if(cb->nf == 5){	/* vclk n m v r */
				vclkenable(1);
				vclkset(cb->f[1], cb->f[2], cb->f[3], cb->f[4]);
			}else
				vclkenable(cb->nf < 2 || strcmp(cb->f[1], "on") == 0);
		}else if(strcmp(cb->f[0], "power") == 0)
			powerfpga(cb->nf < 2 || strcmp(cb->f[1], "off") != 0);
		else
			error(Ebadarg);
		poperror();
		free(cb);
		return n;
	case Qprog:
		qlock(&fpga);
		if(waserror()){
			qunlock(&fpga);
			nexterror();
		}
		powerfpga(1);
		resetfpga();
		cfg = KADDR(FPGACR);
		cp = buf;
		for(i=0; i<n; i++){
			w = cp[i];
			for(j=0; j<8; j++){
				*cfg = w&1;
				w >>= 1;
			}
		}
		for(j=0; j<50; j++)	/* Altera note says at least 10 clock cycles, but microblaster uses 50 */
			*cfg = 0;
		v = fpgastatus();
		if(v != (nStatus|ConfDone)){
			snprint(up->genbuf, sizeof(up->genbuf), "error loading fpga: status %d", v);
			error(up->genbuf);
		}
		poperror();
		qunlock(&fpga);
		return n;
	}
	error(Egreg);
	return 0;		/* not reached */
}

/*
 * PDN seems to control power to the FPGA subsystem
 * but it is not documented nor is its scope clear (PLL as well?).
 * It will not run without it.
 */
static void
powerfpga(int on)
{
	IMM *io;

	io = ioplock();
	if(io->sccr & COM3){
		io->sccrk = KEEP_ALIVE_KEY;
		io->sccr &= ~ COM3;	/* FPGA designs can use the clock */
		io->sccrk = ~KEEP_ALIVE_KEY;
	}
	io->pcpar &= ~PDN;
	io->pcdir |= PDN;
	if(on)
		io->pcdat &= ~PDN;	
	else
		io->pcdat |= PDN;
	iopunlock();
}

static void
resetfpga(void)
{
	IMM *io;

	io = ioplock();
	io->pcpar &= ~nCONFIG;
	io->pcdir |= nCONFIG;
	io->pcdat &= ~nCONFIG;
	microdelay(200);
	io->pcdat |= nCONFIG;
	iopunlock();
}

static int
fpgastatus(void)
{
	/* isolate status bits IP_B0 and IP_B1 */
	return (m->iomem->pipr>>14) & (ConfDone|nStatus);
}

static void
startfpga(int scale)
{
	IMM *io;

	io = ioplock();
	io->tgcr &= ~(0xF<<TIMERSH);
	io->tmr2 = ((scale&0xFF)<<8) | 0x2A;
	io->tcn2 = 0;
	io->trr2 = 0;
	io->ter2 = 0xFFFF;
	io->tgcr |= 0x1<<TIMERSH;
	io->padir |= BCLK;
	io->papar |= BCLK;
	iopunlock();
}

static void
vclkenable(int i)
{
	IMM *io;

	io = ioplock();
	io->padir &= ~VCLK;
	io->papar &= ~VCLK;
	io->pbdir |= EnableVCLK;
	io->pbpar &= ~EnableVCLK;
	if(i)
		io->pbdat |= EnableVCLK;
	else
		io->pbdat &= ~EnableVCLK;
	iopunlock();
}

static void
vclkin(ulong *clk, int v)
{
	int i;

	for(i=0; i<7; i++)
		*clk = (v>>i) & 1;
}

static void
vclkset(char *ns, char *ms, char *vs, char *rs)
{
	int n, m, v, r;
	ulong *clk;

	clk = KADDR(CLOCKCR);
	n = strtol(ns, nil, 0);
	m = strtol(ms, nil, 0);
	v = strtol(vs, nil, 0);
	r = strtol(rs, nil, 0);
	if(n < 3 || n > 127 || m < 3 || m > 127 || v != 1 && v != 8 ||
	   r != 1 && r != 2 && r != 4 && r != 8)
		error(Ebadarg);
	vclkenable(0);
	vclkin(clk, n);
	vclkin(clk, m);
	*clk = (v==0) & 1;
	*clk = 1; *clk = 1;
	*clk = r == 2 || r == 8;
	*clk = r == 4 || r == 8;
	*clk = 1;	/* clock out */
	*clk = 0;	/* disable clk/x */
	*clk = 1; *clk = 0; *clk = 1;
	*clk = 0; *clk = 0; *clk = 0;
	vclkenable(1);
}

/*
 * copy data aligned on 16-bit word boundaries.
 */
static void
memmovew(ushort *to, ushort *from, long count)
{
	int n;

	if(count <= 0)
		return;
	count >>= 1;
	n = (count+7) >> 3;
	switch(count&7) {	/* Duff's device */
	case 0: do {	*to++ = *from++;
	case 7:		*to++ = *from++;
	case 6:		*to++ = *from++;
	case 5:		*to++ = *from++;
	case 4:		*to++ = *from++;
	case 3:		*to++ = *from++;
	case 2:		*to++ = *from++;
	case 1:		*to++ = *from++;
		} while(--n > 0);
	}
}

Dev fpgadevtab = {
	'G',
	"fpga",

	fpgareset,
	devinit,
	devshutdown,
	fpgaattach,
	fpgawalk,
	fpgastat,
	fpgaopen,
	devcreate,
	fpgaclose,
	fpgaread,
	devbread,
	fpgawrite,
	devbwrite,
	devremove,
	devwstat,
};
