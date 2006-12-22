/*
 * preliminary Crystal CS4231 audio driver,
 * initially based on SB16 driver, and therefore needs work.
 * for instance, i suspect the linked-list buffering is excessive:
 * a rolling buffering scheme or double buffering should be fine,
 * and possibly simpler.
 *
 * To do:
 *	stop/start?
 *	is the linux mix_cvt ideal?
 *	ad1845 differences
 *	adpcm freezing
 */

#include	"u.h"
#include	"../port/lib.h"
#include	"mem.h"
#include	"dat.h"
#include	"fns.h"
#include	"../port/error.h"
#include	"devtab.h"
#include	"io.h"
#include	"audio.h"

#define	DPRINT	if(chatty)print

typedef struct	AChan	AChan;
typedef struct	AQueue	AQueue;
typedef struct	Buf	Buf;
typedef struct	Vol	Vol;

enum
{
	Qdir		= 0,
	Qaudio,
	Qaudioctl,

	Fmono		= 1,
	Fin		= 2,
	Fout		= 4,

	Vaudio		= 0,
	Vaux1,
	Vaux2,
	Vline,
	Vmic,
	Vmono,
	Vspeed,
	Vchans,
	Vbits,
	Nvol,

	Speed		= 22050,
	Ncmd		= 50,		/* max volume command words */
};

enum {
	Paddr=	0,
		TRD=	1<<5,
		MCE=	1<<6,
	Pdata=	1,
	Pstatus=	2,
	Pio=		3,

	LeftADC=	0,
		MGE=	1<<5,
		ISline=	0<<6,
		ISaux1=	1<<6,
		ISmic=	2<<6,
		ISloop=	3<<6,
		ISmask=	3<<6,
	RightADC= 1,
	LeftAux1= 2,
		Mute=	1<<7,
	RightAux1= 3,
	LeftAux2= 4,
	RightAux2= 5,
	LeftDAC= 6,
	RightDAC= 7,
	OutFormat=	8,
		Stereo=	1<<4,
		Linear8=	0<<5,
		uLaw=	1<<5,
		Linear16=	2<<5,
		aLaw=	3<<5,
		ADPCM=	5<<5,
		Fmask=	7<<5,
	Config=	9,
		PEN=	1<<0,
		CEN=	1<<1,
		Nocal=	0<<3,
		Convcal=	1<<3,
		DACcal=	2<<3,
		Fullcal=	3<<3,
	PinControl=	10,
		IEN=		1<<1,
		DEN=	1<<3,
		Xctl0=	1<<6,
		Xctl1=	1<<7,
	Status=	11,
		ACI=		1<<5,
	Mode=	12,
		Mode2=	1<<6,
	Loopback=	13,
		LBE=		1<<0,
	PlayCount1=	14,
	PlayCount0=	15,
	Feature1=	16,
		PMCE=	1<<4,
		CMCE=	1<<5,
	Feature2=	17,
	LeftLine=	18,
	RightLine=	19,
	Timer0=	20,
	Timer1=	21,
	Feature3=	23,
	FeatureStatus=	24,
		PI=	1<<4,	/* playback interrupt */
		CI=	1<<5,	/* capture interrupt */
		TI=	1<<6,	/* timer interrupt */
	ChipID= 25,
	MonoCtl=	26,
		MBY=	1<<5,	/* mono bypass */
		MOM=	1<<6,
	InFormat=	28,
	RecCount1=	30,
	RecCount0=	31,
};

#define	csdelay()	microdelay(1)

static Dirtab audiodir[] =
{
	"audio",	{Qaudio},		0,	0666,
	"audioctl",	{Qaudioctl},		0,	0666,
};
#define	NPORT		(sizeof audiodir/sizeof(Dirtab))

struct Buf
{
	uchar*	virt;
	int	count;
	Buf*	next;
};
struct AQueue
{
	Lock;
	Buf*	first;
	Buf*	last;
};
struct AChan
{
	QLock;
	Rendez	r;
	Buf	buf[Nbuf];	/* buffers and queues */
	AQueue	empty;
	AQueue	full;
	Buf*	current;
	Buf*	filling;
	int	flushing;
};
static struct
{
	QLock;
	int	opened;
	int	bufinit;	/* boolean if buffers allocated */
	int	rivol[Nvol];		/* right/left input/output volumes */
	int	livol[Nvol];
	int	rovol[Nvol];
	int	lovol[Nvol];
	int	loopback;

	AChan	in;
	AChan	out;
} audio;

static	char*	encname(int);

static	int	dacload(int, int);
static	int	auxload(int, int);
static	int	adcload(int, int);
static	int	monoload(int, int);

struct Vol
{
	char*	name;
	int	flag;
	int	ilval;		/* initial values */
	int	irval;
	int	reg;
	int	(*load)(int, int);
};

static	Vol	volumes[] = {
[Vaudio]	{"audio",	    Fout, 	50,	50,	LeftDAC, dacload},
[Vaux1]		{"aux1",		Fin,	0,	0,	LeftAux1, auxload},
[Vaux2]		{"aux2",		Fin,	0,	0,	LeftAux2, auxload},
[Vline]		{"line",		Fin,	0,	0,	LeftLine, auxload},
[Vmono]		{"mono",		Fin|Fout|Fmono,	0,	0,	MonoCtl, monoload},
[Vmic]		{"mic",		Fin,	0,	0,	LeftADC, adcload},

[Vspeed]	{"rate",	Fin|Fout|Fmono,	Speed,	Speed,},
[Vchans]	{"chans",	Fin|Fout|Fmono,	2,	2,},
[Vbits]	{"bits", Fin|Fout|Fmono, 8, 8,},
	{0},
};

static struct
{
	Lock;
	int	port;
	int	irq;
	uchar	sticky;
	uchar	regs[32];
} csdev;

static	void	contininput(void);
static	void	continoutput(void);

static	char	Evolume[]	= "illegal audioctl specifier";

static	int	chatty;

#include "cs4231.h"

static int
xin(int r)
{
	int i;

	for(i=100; --i >= 0 && IN(Paddr) & 0x80;)
		csdelay();
	OUT(Paddr, r|csdev.sticky);
	csdelay();
	return IN(Pdata);
}

static void
xout(int r, int v)
{
	int i;

	for(i=100; --i >= 0 && IN(Paddr) & 0x80;)
		csdelay();
	OUT(Paddr, r|csdev.sticky);
	csdelay();
	OUT(Pdata, v);
	//csdelay();
}

static void
speaker(int on)
{
	int s;

	s = xin(PinControl);
	if(on)
		s |= Xctl0;
	else
		s &= ~Xctl0;
	xout(PinControl, s);
}

static Buf*
getbuf(AQueue *q)
{
	Buf *b;

	ilock(q);
	b = q->first;
	if(b)
		q->first = b->next;
	iunlock(q);

	return b;
}

static void
putbuf(AQueue *q, Buf *b)
{
	ilock(q);
	b->next = 0;
	if(q->first)
		q->last->next = b;
	else
		q->first = b;
	q->last = b;
	iunlock(q);
}

static void
achanreset(AChan *ac)
{
	int i;

	ac->filling = 0;
	ac->flushing = 0;
	ac->current = 0;
	ac->empty.first = 0;
	ac->empty.last = 0;
	ac->full.first = 0;
	ac->full.last = 0;
	for(i=0; i<Nbuf; i++){
		ac->buf[i].count = 0;
		putbuf(&ac->empty, &ac->buf[i]);
	}
}

static void
startoutput(void)
{
	ilock(&csdev);
	if(audio.out.current == 0)
		continoutput();
	iunlock(&csdev);
}

static void
continoutput(void)
{
	Buf *b;
	int f;
	ulong n;

	b = getbuf(&audio.out.full);
	audio.out.current = b;
	//xout(Config, xin(Config)&~PEN);
	if(b){
		n = b->count;
		dmasetup(Wdma, b->virt, n, 0);
		f = xin(OutFormat);
		if((f & Fmask) == ADPCM)
			n >>= 2;
		else{
			if((f & Fmask) == Linear16)
				n >>= 1;
			if(f & Stereo)
				n >>= 1;
		}
		n--;
		xout(PlayCount0, n);
		xout(PlayCount1, n>>8);
		xout(Config, xin(Config)|PEN);
		DPRINT("cs: out %d\n", n);
	} else
		xout(Config, xin(Config)&~PEN);
}

static void
startinput(void)
{
	ilock(&csdev);
	if(audio.in.current == 0)
		contininput();
	iunlock(&csdev);
}

static void
contininput(void)
{
	Buf *b;
	int f;
	ulong n;

	xout(Config, xin(Config)&~CEN);
	if(!audio.opened || audio.in.flushing){
		return;
	}
	b = getbuf(&audio.in.empty);
	audio.in.current = b;
	if(b){
		n = Bufsize;
		dmasetup(Rdma, b->virt, Bufsize, 1);
		f = xin(InFormat);
		if((f & Fmask) == ADPCM)
			n >>= 2;
		else{
			if((f & Fmask) == Linear16)
				n >>= 1;
			if(f & Stereo)
				n >>= 1;
		}
		n--;
		xout(RecCount0, n);
		xout(RecCount1, n>>8);
		xout(Config, xin(Config)|CEN);
		DPRINT("cs: in %d\n", n);
	}
}

static void
cswait(void)
{
	int i;

	for(i=50; --i >= 0 && IN(Paddr) & 0x80;)
		microdelay(2000);
	if(i < 0)
		print("cswait1\n");
	for(i=1000; --i >= 0 && (xin(Status) & ACI) == 0;)
		csdelay();
	for(i=1000; --i >= 0 && xin(Status) & ACI;)
		microdelay(2000);
	/* could give error(Eio) if i < 0 */
	if(i < 0)
		print("cswait2\n");
}

static int
csspeed(int freq)
{
	int i;
	static int freqtab[] = {	/* p. 33 CFS2-CFS0 */
		/* xtal1 xtal2 */
		8000, 5510,
		16000, 11025,
		27420, 18900,
		32000, 22050,
		0, 37800,
		0, 44100,
		48000, 33075,
		9600, 6620,
	};
	for(i=0; i<16; i++)
		if(freqtab[i] == freq){
			xout(OutFormat, (xin(OutFormat)&~0xF) | i);
			return 1;
		}
	return 0;
}

static void
csformat(int r, int flag, int form, int *vec)
{
	int v;

	if(form == Linear8){
		if(vec[Vbits] == 16)
			form = Linear16;
		else if(vec[Vbits] == 4)
			form = ADPCM;
	}
	if(vec[Vchans] == 2)
		form |= Stereo;
	DPRINT("csformat(%x,%x,%x)\n", r, flag, form);
	if((xin(r)&0xF0) != form){
		v = xin(Feature1);
		xout(Feature1, v|flag);
		xout(r, (xin(r)&~0xF0)|form);
		xout(Feature1, v);
	}
	csdev.regs[r] = form;
}

static void
cs4231intr(Ureg*, void*)
{
	int ir, s;
	Buf *b;

	lock(&csdev);
	csdev.sticky |= TRD;
	ir = IN(Pstatus);
	s = xin(FeatureStatus);
	if(s & PI){
		b = audio.out.current;
		audio.out.current = 0;
		dmaend(Wdma);
		continoutput();
		if(b)
			putbuf(&audio.out.empty, b);
		wakeup(&audio.out.r);
	}
	if(s & CI){
		b = audio.in.current;
		audio.in.current = 0;
		dmaend(Rdma);
		contininput();
		if(b){
			b->count = Bufsize;
			putbuf(&audio.in.full, b);
		}
		wakeup(&audio.in.r);
	}
	OUT(Pstatus, 0);
	csdev.sticky &= ~TRD;
	unlock(&csdev);
	if(s & 0xF)
		DPRINT("audiointr: #%x\n", s);
}

static int
anybuf(void *p)
{
	return ((AChan*)p)->empty.first != 0;
}

static int
anyinput(void *p)
{
	return ((AChan*)p)->full.first != 0;
}

static int
outcomplete(void *p)
{
	return ((AChan*)p)->full.first == 0 && ((AChan*)p)->current==0;
}

static int
incomplete(void *p)
{
	return ((AChan*)p)->current == 0;
}

static void
acbufinit(AChan *ac)
{
	int i;
	void *p;

	for(i=0; i<Nbuf; i++) {
		//p = xspanalloc(Bufsize, CACHELINESZ, 64*1024);
		//dcflush(p, Bufsize);
		p = xalloc(Bufsize);
		ac->buf[i].virt = UNCACHED(uchar, p);
	}
}

static void
setempty(void)
{
	ilock(&csdev);
	achanreset(&audio.in);
	achanreset(&audio.out);
	iunlock(&csdev);
}

void
cs4231reset(void)
{
}

static char mix_cvt[101] = {
	0, 0,3,7,10,13,16,19,21,23,26,28,30,32,34,35,37,39,40,42,
	43,45,46,47,49,50,51,52,53,55,56,57,58,59,60,61,62,63,64,65,
	65,66,67,68,69,70,70,71,72,73,73,74,75,75,76,77,77,78,79,79,
	80,81,81,82,82,83,84,84,85,85,86,86,87,87,88,88,89,89,90,90,
	91,91,92,92,93,93,94,94,95,95,96,96,96,97,97,98,98,98,99,99,
	100
};

static int
dacload(int r, int v)
{
	USED(r);
	DPRINT("dacload(%x,%d)\n", r, v);
	if(v == 0)
		return Mute;
	return 63-((v*63)/100);
}

static int
monoload(int r, int v)
{
	DPRINT("monoload(%x,%d)\n", r, v);
	if(v == 0)
		return r|Mute;
	return (r&~(Mute|MBY))|(15-((v*15)/100));
}

static int
auxload(int r, int v)
{
	DPRINT("auxload(%x,%d)\n", r, v);
	USED(r);
	if(v == 0)
		return Mute;
	return 31-(v*31)/100;
}

static int
adcload(int r, int v)
{
	DPRINT("adcload(%x,%d)\n", r, v);
	return (r&~0xF)|((v*15)/100)|MGE;
}

static void
mxvolume(void)
{
	Vol *v;
	int i, l, r;

	ilock(&csdev);
	speaker(0);
	for(i =0; volumes[i].name; i++){
		v = &volumes[i];
		if(v->load == 0)
			continue;
		if(v->flag & Fin){
			l = audio.livol[i];
			r = audio.rivol[i];
		} else {
			l = audio.lovol[i];
			r = audio.rovol[i];
		}
		if(l < 0)
			l = 0;
		if(r < 0)
			r = 0;
		if(l > 100)
			l = 100;
		if(r > 100)
			r = 100;
		l = mix_cvt[l];
		r = mix_cvt[r];
		if((v->flag & Fmono) == 0){
			xout(v->reg, (*v->load)(xin(v->reg), l));
			xout(v->reg+1, (*v->load)(xin(v->reg+1), r));
		} else
			xout(v->reg, (*v->load)(xin(v->reg), l));
	}
	xout(LeftADC, (xin(LeftADC)&~ISmask)|csdev.regs[LeftADC]);
	xout(RightADC, (xin(RightADC)&~ISmask)|csdev.regs[RightADC]);
	if(audio.loopback)
		xout(Loopback, xin(Loopback)|LBE);
	else
		xout(Loopback, xin(Loopback)&~LBE);
	csformat(InFormat, CMCE, csdev.regs[InFormat], audio.livol);
	csformat(OutFormat, PMCE, csdev.regs[OutFormat], audio.lovol);
	if(audio.lovol[Vaudio] || audio.rovol[Vaudio])
		speaker(1);
	iunlock(&csdev);
}

static void
flushinput(void)
{
	Buf *b;

	ilock(&csdev);
	audio.in.flushing = 1;
	iunlock(&csdev);
	qlock(&audio.in);
	if(waserror()){
		qunlock(&audio.in);
		nexterror();
	}
	sleep(&audio.in.r, incomplete, &audio.in);
	qunlock(&audio.in);
	poperror();
	ilock(&csdev);
	audio.in.flushing = 0;
	iunlock(&csdev);
	if((b = audio.in.filling) != 0){
		audio.in.filling = 0;
		putbuf(&audio.in.empty, b);
	}
	while((b = getbuf(&audio.in.full)) != 0)
		putbuf(&audio.in.empty, b);
}

static void
waitoutput(void)
{
	qlock(&audio.out);
	if(waserror()){
		qunlock(&audio.out);
		nexterror();
	}
	startoutput();
	while(!outcomplete(&audio.out))
		sleep(&audio.out.r, outcomplete, &audio.out);
	qunlock(&audio.out);
	poperror();
}

static	void
resetlevel(void)
{
	int i;

	for(i=0; volumes[i].name; i++) {
		audio.lovol[i] = volumes[i].ilval;
		audio.rovol[i] = volumes[i].irval;
		audio.livol[i] = volumes[i].ilval;
		audio.rivol[i] = volumes[i].irval;
	}
}

void
cs4231init(void)
{
	cs4231install();

	csdev.regs[LeftADC] = ISmic;
	csdev.regs[RightADC] = ISmic;
	dmasize(Wdma, 8);
	dmasize(Rdma, 8);
	csdev.sticky = 0;
	OUT(Paddr, Mode);
	csdelay();
	if((IN(Pdata) & 0x8F) != 0x8a){
		DPRINT("port %x not cs4231a: %x\n", IN(Pdata));
		return;
	}
	print("audio0: cs4231a: port %x irq %d wdma %d rdma %d\n", csdev.port, csdev.irq, Wdma, Rdma);

	resetlevel();

	cswait();
	OUT(Paddr, Mode);
	csdelay();
	OUT(Pdata, Mode2|IN(Pdata));	/* mode2 for all the trimmings */
	csdelay();
	cswait();

	csdev.sticky = MCE;
	xout(Config, Fullcal);
	csspeed(volumes[Vspeed].ilval);
	csformat(InFormat, CMCE, Linear8, audio.livol);
	csformat(OutFormat, PMCE, Linear8, audio.lovol);
	csdev.sticky &= ~MCE;
	OUT(Paddr, csdev.sticky);
	microdelay(10000);
	cswait();	/* recalibration takes ages */

	xout(FeatureStatus, 0);
	OUT(Pstatus, 0);
	setvec(csdev.irq, cs4231intr, 0);
	xout(PinControl, xin(PinControl)|IEN);
}

Chan*
cs4231attach(char *param)
{
	return devattach('A', param);
}

Chan*
cs4231clone(Chan *c, Chan *nc)
{
	return devclone(c, nc);
}

int
cs4231walk(Chan *c, char *name)
{
	return devwalk(c, name, audiodir, NPORT, devgen);
}

void
cs4231stat(Chan *c, char *db)
{
	devstat(c, db, audiodir, NPORT, devgen);
}

Chan*
cs4231open(Chan *c, int omode)
{
	switch(c->qid.path & ~CHDIR) {
	default:
		error(Eperm);
		break;

	case Qaudioctl:
	case Qdir:
		break;

	case Qaudio:
		qlock(&audio);
		if(audio.opened){
			qunlock(&audio);
			error(Einuse);
		}
		if(audio.bufinit == 0) {
			audio.bufinit = 1;
			acbufinit(&audio.in);
			acbufinit(&audio.out);
		}
		audio.opened = 1;
		setempty();
		qunlock(&audio);
		mxvolume();
		break;
	}
	c = devopen(c, omode, audiodir, NPORT, devgen);
	c->mode = openmode(omode);
	c->flag |= COPEN;
	c->offset = 0;

	return c;
}

void
cs4231create(Chan *c, char *name, int omode, ulong perm)
{
	USED(c, name, omode, perm);
	error(Eperm);
}

void
cs4231close(Chan *c)
{
	Buf *b;

	switch(c->qid.path & ~CHDIR) {
	default:
		error(Eperm);
		break;

	case Qdir:
	case Qaudioctl:
		break;

	case Qaudio:
		if(c->flag & COPEN) {
			qlock(&audio);
			audio.opened = 0;
			if(waserror()){
				qunlock(&audio);
				nexterror();
			}
			b = audio.out.filling;
			if(b){
				audio.out.filling = 0;
				putbuf(&audio.out.full, b);
			}
			waitoutput();
			flushinput();
			//tsleep(&up->sleep, return0, 0, 500);
			//speaker(0);
			qunlock(&audio);
			poperror();
		}
		break;
	}
}

long
cs4231read(Chan *c, char *a, long n, vlong offset)
{
	int liv, riv, lov, rov, ifmt, ofmt;
	long m, n0;
	char buf[350];
	Buf *b;
	int j;

	n0 = n;
	switch(c->qid.path & ~CHDIR) {
	default:
		error(Eperm);
		break;

	case Qdir:
		return devdirread(c, a, n, audiodir, NPORT, devgen);

	case Qaudio:
		qlock(&audio.in);
		if(waserror()){
			qunlock(&audio.in);
			nexterror();
		}
		while(n > 0) {
			b = audio.in.filling;
			if(b == 0) {
				b = getbuf(&audio.in.full);
				if(b == 0) {
					startinput();
					sleep(&audio.in.r, anyinput, &audio.in);
					continue;
				}
				audio.in.filling = b;
				b->count = 0;
			}
			m = Bufsize-b->count;
			if(m > n)
				m = n;
			memmove(a, b->virt+b->count, m);

			b->count += m;
			n -= m;
			a += m;
			if(b->count >= Bufsize) {
				audio.in.filling = 0;
				putbuf(&audio.in.empty, b);
			}
		}
		qunlock(&audio.in);
		poperror();
		break;

	case Qaudioctl:
		j = 0;
		buf[0] = 0;
		for(m=0; volumes[m].name; m++){
			liv = audio.livol[m];
			riv = audio.rivol[m];
			lov = audio.lovol[m];
			rov = audio.rovol[m];
			j += snprint(buf+j, sizeof(buf)-j, "%s", volumes[m].name);
			if((volumes[m].flag & Fmono) || liv==riv && lov==rov){
				if((volumes[m].flag&(Fin|Fout))==(Fin|Fout) && liv==lov)
					j += snprint(buf+j, sizeof(buf)-j, " %d", liv);
				else{
					if(volumes[m].flag & Fin)
						j += snprint(buf+j, sizeof(buf)-j, " in %d", liv);
					if(volumes[m].flag & Fout)
						j += snprint(buf+j, sizeof(buf)-j, " out %d", lov);
				}
			}else{
				if((volumes[m].flag&(Fin|Fout))==(Fin|Fout) && liv==lov && riv==rov)
					j += snprint(buf+j, sizeof(buf)-j, " left %d right %d",
						liv, riv);
				else{
					if(volumes[m].flag & Fin)
						j += snprint(buf+j, sizeof(buf)-j, " in left %d right %d",
							liv, riv);
					if(volumes[m].flag & Fout)
						j += snprint(buf+j, sizeof(buf)-j, " out left %d right %d",
							lov, rov);
				}
			}
			j += snprint(buf+j, sizeof(buf)-j, "\n");
		}
		ifmt = xin(InFormat);
		ofmt = xin(OutFormat);
		if(ifmt != ofmt){
			j += snprint(buf+j, sizeof(buf)-j, "in enc %s\n", encname(ifmt));
			j += snprint(buf+j, sizeof(buf)-j, "out enc %s\n", encname(ofmt));
		} else
			j += snprint(buf+j, sizeof(buf)-j, "enc %s\n", encname(ifmt));
		j += snprint(buf+j, sizeof(buf)-j, "loop %d\n", audio.loopback);
		{int i; for(i=0; i<32; i++){j += snprint(buf+j, sizeof(buf)-j, " %d:%x", i, xin(i)); }j += snprint(buf+j,sizeof(buf)-j,"\n");}
		USED(j);

		return readstr(offset, a, n, buf);
	}
	return n0-n;
}

Block*
cs4231bread(Chan *c, long n, ulong offset)
{
	return devbread(c, n, offset);
}

long
cs4231write(Chan *c, char *a, long n, vlong offset)
{
	long m, n0;
	int i, nf, v, left, right, in, out, fmt, doload;
	char buf[255], *field[Ncmd];
	Buf *b;

	USED(offset);

	n0 = n;
	switch(c->qid.path & ~CHDIR) {
	default:
		error(Eperm);
		break;

	case Qaudioctl:
		waitoutput();
		flushinput();
		qlock(&audio);
		if(waserror()){
			qunlock(&audio);
			nexterror();
		}
		v = Vaudio;
		doload = 0;
		left = 1;
		right = 1;
		in = 1;
		out = 1;
		if(n > sizeof(buf)-1)
			n = sizeof(buf)-1;
		memmove(buf, a, n);
		buf[n] = '\0';

		nf = getfields(buf, field, Ncmd, 1, " \t\n,");
		for(i = 0; i < nf; i++){
			/*
			 * a number is volume
			 */
			if(field[i][0] >= '0' && field[i][0] <= '9') {
				m = strtoul(field[i], 0, 10);
				if(left && out)
					audio.lovol[v] = m;
				if(left && in)
					audio.livol[v] = m;
				if(right && out)
					audio.rovol[v] = m;
				if(right && in)
					audio.rivol[v] = m;
				if(v == Vspeed){
					ilock(&csdev);
					csdev.sticky = MCE;
					csspeed(m);
					csdev.sticky &= ~MCE;
					OUT(Paddr, csdev.sticky);
					microdelay(10000);
					cswait();
					iunlock(&csdev);
				} else
					doload = 1;
				continue;
			}

			for(m=0; volumes[m].name; m++) {
				if(strcmp(field[i], volumes[m].name) == 0) {
					v = m;
					in = 1;
					out = 1;
					left = 1;
					right = 1;
					break;
				}
			}
			if(volumes[m].name)
				continue;

			if(strcmp(field[i], "chat") == 0){
				chatty = !chatty;
				continue;
			}

			if(strcmp(field[i], "reset") == 0) {
				resetlevel();
				doload = 1;
				continue;
			}
			if(strcmp(field[i], "loop") == 0) {
				if(++i >= nf)
					error(Evolume);
				audio.loopback = strtoul(field[i], 0, 10);
				doload = 1;
				continue;
			}
			if(strcmp(field[i], "enc") == 0) {
				if(++i >= nf)
					error(Evolume);
				fmt = -1;
				if(strcmp(field[i], "ulaw") == 0)
					fmt = uLaw;
				else if(strcmp(field[i], "alaw") == 0)
					fmt = aLaw;
				else if(strcmp(field[i], "pcm") == 0)
					fmt = Linear8;
				else if(strcmp(field[i], "adpcm") == 0)
					fmt = ADPCM;
				else
					error(Evolume);
				if(in)
					csdev.regs[InFormat] = fmt;
				if(out)
					csdev.regs[OutFormat] = fmt;
				doload = 1;
				continue;
			}
			if(strcmp(field[i], "dev") == 0) {
				if(++i >= nf)
					error(Evolume);
				if(in){
					fmt = -1;
					if(strcmp(field[i], "mic") == 0)
						fmt = ISmic;
					else if(strcmp(field[i], "line") == 0)
						fmt = ISline;
					else if(strcmp(field[i], "aux1") == 0)
						fmt = ISaux1;
					else if(strcmp(field[i], "loop") == 0)
						fmt = ISloop;
					else
						error(Evolume);
					if(left)
						csdev.regs[LeftADC] = fmt;
					if(right)
						csdev.regs[RightADC] = fmt;
					doload = 1;
				}
				continue;
			}
			if(strcmp(field[i], "in") == 0) {
				in = 1;
				out = 0;
				continue;
			}
			if(strcmp(field[i], "out") == 0) {
				in = 0;
				out = 1;
				continue;
			}
			if(strcmp(field[i], "left") == 0) {
				left = 1;
				right = 0;
				continue;
			}
			if(strcmp(field[i], "right") == 0) {
				left = 0;
				right = 1;
				continue;
			}
			error(Evolume);
		}
		if(doload)
			mxvolume();
		qunlock(&audio);
		poperror();
		n=0;
		break;

	case Qaudio:
		qlock(&audio.out);
		if(waserror()){
			qunlock(&audio.out);
			nexterror();
		}
		while(n > 0) {
			b = audio.out.filling;
			if(b == 0) {
				b = getbuf(&audio.out.empty);
				if(b == 0) {
					startoutput();
					sleep(&audio.out.r, anybuf, &audio.out);
					continue;
				}
				b->count = 0;
				audio.out.filling = b;
			}

			m = Bufsize-b->count;
			if(m > n)
				m = n;
			memmove(b->virt+b->count, a, m);

			b->count += m;
			n -= m;
			a += m;
			if(b->count >= Bufsize) {
				audio.out.filling = 0;
				putbuf(&audio.out.full, b);
			}
		}
		qunlock(&audio.out);
		poperror();
		break;
	}
	return n0 - n;
}

long
cs4231bwrite(Chan *c, Block *bp, ulong offset)
{
	return devbwrite(c, bp, offset);
}

void
cs4231remove(Chan *c)
{
	USED(c);
	error(Eperm);
}

void
cs4231wstat(Chan *c, char *dp)
{
	USED(c, dp);
	error(Eperm);
}

static char *
encname(int v)
{
	switch(v & ~(0xF|Stereo)){
	case uLaw:	return "ulaw";
	case aLaw:	return "alaw";
	case Linear8:	return "pcm";
	case Linear16:	return "pcm16";
	case ADPCM:	return "adpcm";
	default:	return "?";
	}
}
