/*
 *	SAC/UDA 1341 Audio driver for the Bitsy
 *
 *	This code is covered by the Lucent Public Licence 1.02 (http://plan9.bell-labs.com/plan9dist/license.html);
 *	see the file NOTICE in the current directory.  Modifications for the Inferno environment by Vita Nuova.
 *
 *	The Philips UDA 1341 sound chip is accessed through the Serial Audio
 *	Controller (SAC) of the StrongARM SA-1110.
 *
 *	The code morphs Nicolas Pitre's <nico@cam.org> Linux controller
 *	and Ken's Soundblaster controller.
 *
 *	The interface should be identical to that of devaudio.c
 */
#include	"u.h"
#include	"../port/lib.h"
#include	"mem.h"
#include	"dat.h"
#include	"fns.h"
#include	"../port/error.h"
#include	"io.h"

static int debug = 0;

/* UDA 1341 Registers */
enum {
	/* Status0 register */
	UdaStatusDC		= 0,	/* 1 bit */
	UdaStatusIF		= 1,	/* 3 bits */
	UdaStatusSC		= 4,	/* 2 bits */
	UdaStatusRST		= 6,	/* 1 bit */
};

enum {
	/* Status1 register */
	UdaStatusPC	= 0,	/* 2 bits */
	UdaStatusDS	= 2,	/* 1 bit */
	UdaStatusPDA	= 3,	/* 1 bit */
	UdaStatusPAD	= 4,	/* 1 bit */
	UdaStatusIGS	= 5,	/* 1 bit */
	UdaStatusOGS	= 6,	/* 1 bit */
};

/*
 * UDA1341 L3 address and command types
 */

enum {
	UDA1341_DATA0 =	0,
	UDA1341_DATA1,
	UDA1341_STATUS,
	UDA1341_L3Addr = 0x14,
};

typedef struct	AQueue	AQueue;
typedef struct	Buf	Buf;
typedef struct	IOstate IOstate;

enum
{
	Qdir		= 0,
	Qaudio,
	Qvolume,
	Qstatus,
	Qaudioctl,

	Fmono		= 1,
	Fin			= 2,
	Fout		= 4,

	Aclosed		= 0,
	Aread,
	Awrite,

	Vaudio		= 0,
	Vmic,
	Vtreb,
	Vbass,
	Vspeed,
	Vfilter,
	Vinvert,
	Nvol,

	Bufsize		= 4*1024,	/* 46 ms each */
	Nbuf		= 32,		/* 1.5 seconds total */

	Speed		= 44100,
	Ncmd		= 50,		/* max volume command words */
};

Dirtab
audiodir[] =
{
	".",		{Qdir, 0, QTDIR},	0,	0555,
	"audio",	{Qaudio},		0,	0666,
	"volume",	{Qvolume},		0,	0666,
	"audioctl", {Qaudioctl},		0,	0666,
	"audiostat",{Qstatus},		0,	0444,
};

struct	Buf
{
	uchar*	virt;
	ulong	phys;
	uint	nbytes;
};

struct	IOstate
{
	QLock;
	Lock			ilock;
	Rendez			vous;
	Chan			*chan;			/* chan of open */
	Dma*				dma;			/* dma chan, alloc on open, free on close */
	int				bufinit;		/* boolean, if buffers allocated */
	Buf				buf[Nbuf];		/* buffers and queues */
	volatile Buf	*current;		/* next dma to finish */
	volatile Buf	*next;			/* next candidate for dma */
	volatile Buf	*filling;		/* buffer being filled */
/* just be be cute (and to have defines like linux, a real operating system) */
#define emptying filling
};

static	struct
{
	QLock;
	int		amode;			/* Aclosed/Aread/Awrite for /audio */
	int		intr;			/* boolean an interrupt has happened */
	int		rivol[Nvol];	/* right/left input/output volumes */
	int		livol[Nvol];
	int		rovol[Nvol];
	int		lovol[Nvol];
	uvlong	totcount;		/* how many bytes processed since open */
	vlong	tottime;		/* time at which totcount bytes were processed */
	int	clockout;	/* need steady output to provide input clock */
	IOstate	i;
	IOstate	o;
} audio;

static struct
{
	ulong	bytes;
	ulong	totaldma;
	ulong	idledma;
	ulong	faildma;
	ulong	samedma;
} iostats;

static	struct
{
	char*	name;
	int	flag;
	int	ilval;		/* initial values */
	int	irval;
} volumes[] =
{
[Vaudio]	{"audio",	Fout|Fmono,	 80,	 80},
[Vmic]		{"mic",		Fin|Fmono,	  0,	  0},
[Vtreb]		{"treb",	Fout|Fmono,	 50,	 50},
[Vbass]		{"bass",	Fout|Fmono, 	 50,	 50},
[Vspeed]	{"speed",	Fin|Fout|Fmono,	Speed,	Speed},
[Vfilter]	{"filter",	Fout|Fmono,	  0,	  0},
[Vinvert]	{"invert",	Fin|Fout|Fmono,	  0,	  0},
[Nvol]		{0}
};

static void	setreg(char *name, int val, int n);

static	char	Emode[]		= "illegal open mode";
static	char	Evolume[]	= "illegal volume specifier";

static void
bufinit(IOstate *b)
{
	int i;

	if (debug) print("bufinit\n");
	for (i = 0; i < Nbuf; i++) {
		b->buf[i].virt = xspanalloc(Bufsize, CACHELINESZ, 0);
		b->buf[i].phys = PADDR(b->buf[i].virt);
	}
	b->bufinit = 1;
};

static void
setempty(IOstate *b)
{
	int i;

	if (debug) print("setempty\n");
	for (i = 0; i < Nbuf; i++) {
		b->buf[i].nbytes = 0;
	}
	b->filling = b->buf;
	b->current = b->buf;
	b->next = b->buf;
}

static int
audioqnotempty(void *x)
{
	IOstate *s = x;

	return dmaidle(s->dma) || s->emptying != s->current;
}

static int
audioqnotfull(void *x)
{
	IOstate *s = x;

	return dmaidle(s->dma) || s->filling != s->current;
}

static void
audioreset(void)
{
	/* Turn MCP operations off */
	MCPREG->mccr = 0;
}

uchar	status0[1]		= {0x22};
uchar	status1[1]		= {0x80};
uchar	data00[1]		= {0x00};		/* volume control, bits 0 – 5 */
uchar	data01[1]		= {0x40};
uchar	data02[1]		= {0x80};
uchar	data0e0[2]	= {0xc0, 0xe0};
uchar	data0e1[2]	= {0xc1, 0xe0};
uchar	data0e2[2]	= {0xc2, 0xf2};
/* there is no data0e3 */
uchar	data0e4[2]	= {0xc4, 0xe0};
uchar	data0e5[2]	= {0xc5, 0xe0};
uchar	data0e6[2]	= {0xc6, 0xe3};

static void
enable(void)
{
	uchar	data[1];
	int cs;

	L3init();

	PPCREG->ppar &= ~PPAR_SPR;

	/* external clock and ssp configured for current samples/sec */
	cs = archaudiospeed(audio.livol[Vspeed], 1);
	status0[0] = (status0[0] & ~(3<<4)) | (cs<<4);

	/* Enable the audio power */
	archaudiopower(1);
//	egpiobits(EGPIO_audio_ic_power | EGPIO_codec_reset, 1);

	/* Wait for the UDA1341 to wake up */
	delay(100);

	/* Reset the chip */
	data[0] = status0[0] | 1<<UdaStatusRST;
	L3write(UDA1341_L3Addr | UDA1341_STATUS, data, 1 );
	archcodecreset();

	/* write uda 1341 status[0] */
	L3write(UDA1341_L3Addr | UDA1341_STATUS, status0, 1 );
	L3write(UDA1341_L3Addr | UDA1341_STATUS, status1, 1);
	L3write(UDA1341_L3Addr | UDA1341_DATA0, data02, 1);
	L3write(UDA1341_L3Addr | UDA1341_DATA0, data0e2, 2);
	L3write(UDA1341_L3Addr | UDA1341_DATA0, data0e6, 2 );

	if (debug) {
		print("enable:	status0	= 0x%2.2ux\n", status0[0]);
		print("enable:	status1	= 0x%2.2ux\n", status1[0]);
		print("enable:	data02	= 0x%2.2ux\n", data02[0]);
		print("enable:	data0e2	= 0x%4.4ux\n", data0e2[0] | data0e2[1]<<8);
		print("enable:	data0e4	= 0x%4.4ux\n", data0e4[0] | data0e4[1]<<8);
		print("enable:	data0e6	= 0x%4.4ux\n", data0e6[0] | data0e6[1]<<8);
	}
}

static void
disable(void)
{
	SSPREG->sscr0 = 0x031f;	/* disable */
}

static void
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

static void
mxvolume(void) {
	int *left, *right;
	int cs;

	cs = archaudiospeed(audio.livol[Vspeed], 1);
	status0[0] = (status0[0] & ~(3<<4)) | (cs<<4);
	L3write(UDA1341_L3Addr | UDA1341_STATUS, status0, 1);
	if(debug)
		print("mxvolume:	status0	= %2.2ux\n", status0[0]);
	if(audio.amode & Aread){
		left = audio.livol;
		right = audio.rivol;
		if (left[Vmic]+right[Vmic] == 0) {
			/* Turn on automatic gain control (AGC) */
			data0e4[1] |= 0x10;
			L3write(UDA1341_L3Addr | UDA1341_DATA0, data0e4, 2 );
		} else {
			int v;
			/* Turn on manual gain control */
			v = ((left[Vmic]+right[Vmic])*0x7f/200)&0x7f;
			data0e4[1] &= ~0x13;
			data0e5[1] &= ~0x1f;
			data0e4[1] |= v & 0x3;
			data0e5[0] |= (v & 0x7c)<<6;
			data0e5[1] |= (v & 0x7c)>>2;
			L3write(UDA1341_L3Addr | UDA1341_DATA0, data0e4, 2 );
			L3write(UDA1341_L3Addr | UDA1341_DATA0, data0e5, 2 );
		}
		if (left[Vinvert]+right[Vinvert] == 0)
			status1[0] &= ~0x10;
		else
			status1[0] |= 0x10;
		L3write(UDA1341_L3Addr | UDA1341_STATUS, status1, 1);
		if (debug) {
			print("mxvolume:	status1	= 0x%2.2ux\n", status1[0]);
			print("mxvolume:	data0e4	= 0x%4.4ux\n", data0e4[0]|data0e4[0]<<8);
			print("mxvolume:	data0e5	= 0x%4.4ux\n", data0e5[0]|data0e5[0]<<8);
		}
	}
	if(audio.amode & Awrite){
		left = audio.lovol;
		right = audio.rovol;
		data00[0] &= ~0x3f;
		data00[0] |= ((200-left[Vaudio]-right[Vaudio])*0x3f/200)&0x3f;
		if (left[Vtreb]+right[Vtreb] <= 100
		 && left[Vbass]+right[Vbass] <= 100)
			/* settings neutral */
			data02[0] &= ~0x03;
		else {
			data02[0] |= 0x03;
			data01[0] &= ~0x3f;
			data01[0] |= ((left[Vtreb]+right[Vtreb]-100)*0x3/100)&0x03;
			data01[0] |= (((left[Vbass]+right[Vbass]-100)*0xf/100)&0xf)<<2;
		}
		if (left[Vfilter]+right[Vfilter] == 0)
			data02[0] &= ~0x10;
		else
			data02[0]|= 0x10;
		if (left[Vinvert]+right[Vinvert] == 0)
			status1[0] &= ~0x8;
		else
			status1[0] |= 0x8;
		L3write(UDA1341_L3Addr | UDA1341_STATUS, status1, 1);
		L3write(UDA1341_L3Addr | UDA1341_DATA0, data00, 1);
		L3write(UDA1341_L3Addr | UDA1341_DATA0, data01, 1);
		L3write(UDA1341_L3Addr | UDA1341_DATA0, data02, 1);
		if (debug) {
			print("mxvolume:	status1	= 0x%2.2ux\n", status1[0]);
			print("mxvolume:	data00	= 0x%2.2ux\n", data00[0]);
			print("mxvolume:	data01	= 0x%2.2ux\n", data01[0]);
			print("mxvolume:	data02	= 0x%2.2ux\n", data02[0]);
		}
	}
}

static void
setreg(char *name, int val, int n)
{
	uchar x[2];
	int i;

	if(strcmp(name, "pause") == 0){
		for(i = 0; i < n; i++)
			microdelay(val);
		return;
	}

	x[0] = val;
	x[1] = val>>8;

	switch(n){
	case 1:
	case 2:
		break;
	default:
		error("setreg");
	}

	if(strcmp(name, "status") == 0){
		L3write(UDA1341_L3Addr | UDA1341_STATUS, x, n);
	} else if(strcmp(name, "data0") == 0){
		L3write(UDA1341_L3Addr | UDA1341_DATA0, x, n);
	} else if(strcmp(name, "data1") == 0){
		L3write(UDA1341_L3Addr | UDA1341_DATA1, x, n);
	} else
		error("setreg");
}

static void
outenable(void) {
	/* turn on DAC, set output gain switch */
	archaudioamp(1);
	archaudiomute(0);
	status1[0] |= 0x41;
	L3write(UDA1341_L3Addr | UDA1341_STATUS, status1, 1);
	/* set volume */
	data00[0] |= 0xf;
	L3write(UDA1341_L3Addr | UDA1341_DATA0, data00, 1);
	if (debug) {
		print("outenable:	status1	= 0x%2.2ux\n", status1[0]);
		print("outenable:	data00	= 0x%2.2ux\n", data00[0]);
	}
}

static void
outdisable(void) {
	archaudiomute(1);
	dmastop(audio.o.dma);
	/* turn off DAC, clear output gain switch */
	archaudioamp(0);
	status1[0] &= ~0x41;
	L3write(UDA1341_L3Addr | UDA1341_STATUS, status1, 1);
	if (debug) {
		print("outdisable:	status1	= 0x%2.2ux\n", status1[0]);
	}
//	egpiobits(EGPIO_audio_power, 0);
}

static void
inenable(void) {
	/* turn on ADC, set input gain switch */
	status1[0] |= 0x22;
	L3write(UDA1341_L3Addr | UDA1341_STATUS, status1, 1);
	if (debug) {
		print("inenable:	status1	= 0x%2.2ux\n", status1[0]);
	}
}

static void
indisable(void) {
	dmastop(audio.i.dma);
	/* turn off ADC, clear input gain switch */
	status1[0] &= ~0x22;
	L3write(UDA1341_L3Addr | UDA1341_STATUS, status1, 1);
	if (debug) {
		print("indisable:	status1	= 0x%2.2ux\n", status1[0]);
	}
}

static void
sendaudio(IOstate *s) {
	/* interrupt routine calls this too */
	int n;

	if (debug > 1) print("#A: sendaudio\n");
	ilock(&s->ilock);
	while (s->next != s->filling) {
		assert(s->next->nbytes);
		if ((n = dmastart(s->dma, (void*)s->next->phys, s->next->nbytes)) == 0) {
			iostats.faildma++;
			break;
		}
		iostats.totaldma++;
		switch (n) {
		case 1:
			iostats.idledma++;
			break;
		case 3:
			iostats.faildma++;
			break;
		}
		if (debug) {
			if (debug > 1)
				print("dmastart @%p\n", s->next);
			else
				iprint("+");
		}
		s->next->nbytes = 0;
		s->next++;
		if (s->next == &s->buf[Nbuf])
			s->next = &s->buf[0];
	}
	iunlock(&s->ilock);
}

static void
recvaudio(IOstate *s) {
	/* interrupt routine calls this too */
	int n;

	if (debug > 1) print("#A: recvaudio\n");
	ilock(&s->ilock);
	while (s->next != s->emptying) {
		assert(s->next->nbytes == 0);
		if ((n = dmastart(s->dma, (void*)s->next->phys, Bufsize)) == 0) {
			iostats.faildma++;
			break;
		}
		iostats.totaldma++;
		switch (n) {
		case 1:
			iostats.idledma++;
			break;
		case 3:
			iostats.faildma++;
			break;
		}
		if (debug) {
			if (debug > 1)
				print("dmastart @%p\n", s->next);
			else
				iprint("+");
		}
		s->next++;
		if (s->next == &s->buf[Nbuf])
			s->next = &s->buf[0];
	}
	iunlock(&s->ilock);
}

static void
audiopower(int flag) {
	IOstate *s;

	if (debug) {
		iprint("audiopower %d\n", flag);
	}
	if (flag) {
		/* power on only when necessary */
		if (audio.amode) {
			archaudiopower(1);
			enable();
			if (audio.amode & Aread) {
				inenable();
				s = &audio.i;
				dmastop(s->dma);
				recvaudio(s);
			}
			if (audio.amode & Awrite) {
				outenable();
				s = &audio.o;
				dmastop(s->dma);
				sendaudio(s);
			}
			mxvolume();
		}
	} else {
		/* power off */
		if (audio.amode & Aread)
			indisable();
		if (audio.amode & Awrite)
			outdisable();
		disable();
		archaudiopower(0);
	}
}

static void
audiointr(void *x, ulong ndma) {
	IOstate *s = x;

	if (debug) {
		if (debug > 1)
			iprint("#A: audio interrupt @%p\n", s->current);
		else
			iprint("-");
	}
	/* Only interrupt routine touches s->current */
	s->current++;
	if (s->current == &s->buf[Nbuf])
		s->current = &s->buf[0];
	if (ndma > 0) {
		if (s == &audio.o)
			sendaudio(s);
		else if (s == &audio.i)
			recvaudio(s);
	}
	wakeup(&s->vous);
}

static void
audioinit(void)
{
	audio.amode = Aclosed;
	resetlevel();
//	powerenable(audiopower);
}

static Chan*
audioattach(char *param)
{
	return devattach('A', param);
}

static Walkqid*
audiowalk(Chan *c, Chan *nc, char **name, int nname)
{
	return devwalk(c, nc, name, nname, audiodir, nelem(audiodir), devgen);
}

static int
audiostat(Chan *c, uchar *db, int n)
{
	return devstat(c, db, n, audiodir, nelem(audiodir), devgen);
}

static Chan*
audioopen(Chan *c, int mode)
{
	IOstate *s;
	int omode = mode;

	switch((ulong)c->qid.path) {
	default:
		error(Eperm);
		break;

	case Qstatus:
		if((omode&7) != OREAD)
			error(Eperm);
	case Qvolume:
	case Qaudioctl:
	case Qdir:
		break;

	case Qaudio:
		omode = (omode & 0x7) + 1;
		if (omode & ~(Aread | Awrite))
			error(Ebadarg);
		qlock(&audio);
		if(audio.amode & omode){
			qunlock(&audio);
			error(Einuse);
		}
		enable();
		memset(&iostats, 0, sizeof(iostats));
		if (omode & Aread) {
			inenable();
			s = &audio.i;
			if(s->bufinit == 0)
				bufinit(s);
			setempty(s);
			s->emptying = &s->buf[Nbuf-1];
			s->chan = c;
			s->dma = dmasetup(DmaSSP, 1, 0, audiointr, (void*)s);
			audio.amode |= Aread;
			audio.clockout = 1;
		}
		if (omode & Awrite) {
			outenable();
			s = &audio.o;
			audio.amode |= Awrite;
			if(s->bufinit == 0)
				bufinit(s);
			setempty(s);
			s->chan = c;
			s->dma = dmasetup(DmaSSP, 0, 0, audiointr, (void*)s);
			audio.amode |= Awrite;
		}
		mxvolume();
		qunlock(&audio);
		if (debug) print("open done\n");
		break;
	}
	c = devopen(c, mode, audiodir, nelem(audiodir), devgen);
	c->mode = openmode(mode);
	c->flag |= COPEN;
	c->offset = 0;

	return c;
}

static void
audioclose(Chan *c)
{
	IOstate *s;

	switch((ulong)c->qid.path) {
	default:
		error(Eperm);
		break;

	case Qdir:
	case Qvolume:
	case Qaudioctl:
	case Qstatus:
		break;

	case Qaudio:
		if (debug > 1) print("#A: close\n");
		if(c->flag & COPEN) {
			qlock(&audio);
			if(waserror()){
				qunlock(&audio);
				nexterror();
			}
			if (audio.o.chan == c) {
				/* closing the write end */
				audio.amode &= ~Awrite;
				s = &audio.o;
				qlock(s);
				if(waserror()){
					qunlock(s);
					nexterror();
				}
				if (s->filling->nbytes) {
					/* send remaining partial buffer */
					s->filling++;
					if (s->filling == &s->buf[Nbuf])
						s->filling = &s->buf[0];
					sendaudio(s);
				}
				dmawait(s->dma);
				outdisable();
				setempty(s);
				dmafree(s->dma);
				qunlock(s);
				poperror();
			}
			if (audio.i.chan == c) {
				/* closing the read end */
				audio.amode &= ~Aread;
				s = &audio.i;
				qlock(s);
				if(waserror()){
					qunlock(s);
					nexterror();
				}
				indisable();
				setempty(s);
				dmafree(s->dma);
				qunlock(s);
				poperror();
			}
			if (audio.amode == 0) {
				/* turn audio off */
				archaudiopower(0);
			}
			qunlock(&audio);
			poperror();
			if (debug) {
				print("total dmas: %lud\n", iostats.totaldma);
				print("dmas while idle: %lud\n", iostats.idledma);
				print("dmas while busy: %lud\n", iostats.faildma);
				print("out of order dma: %lud\n", iostats.samedma);
			}
		}
		break;
	}
}

static long
audioread(Chan *c, void *v, long n, vlong off)
{
	int liv, riv, lov, rov;
	long m, n0;
	char buf[300];
	int j;
	ulong offset = off;
	char *p;
	IOstate *s;

	n0 = n;
	p = v;
	switch((ulong)c->qid.path) {
	default:
		error(Eperm);
		break;

	case Qdir:
		return devdirread(c, p, n, audiodir, nelem(audiodir), devgen);

	case Qaudio:
		if (debug > 1) print("#A: read %ld\n", n);
		if((audio.amode & Aread) == 0)
			error(Emode);
		s = &audio.i;
		qlock(s);
		if(waserror()){
			qunlock(s);
			nexterror();
		}
		while(n > 0) {
			if(s->emptying->nbytes == 0) {
				if (debug > 1) print("#A: emptied @%p\n", s->emptying);
				recvaudio(s);
				s->emptying++;
				if (s->emptying == &s->buf[Nbuf])
					s->emptying = s->buf;
			}
			/* wait if dma in progress */
			while (!dmaidle(s->dma) && s->emptying == s->current) {
				if (debug > 1) print("#A: sleep\n");
				sleep(&s->vous, audioqnotempty, s);
			}

			m = Bufsize - s->emptying->nbytes;
			if(m > n)
				m = n;
			memmove(p, s->emptying->virt + s->emptying->nbytes, m);

			s->emptying->nbytes -= m;
			n -= m;
			p += m;
		}
		poperror();
		qunlock(s);
		break;
		break;

	case Qstatus:
		buf[0] = 0;
		snprint(buf, sizeof(buf), "bytes %llud\ntime %lld\n",
			audio.totcount, audio.tottime);
		return readstr(offset, p, n, buf);

	case Qvolume:
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
						j += snprint(buf+j, sizeof(buf)-j,
							" in %d", liv);
					if(volumes[m].flag & Fout)
						j += snprint(buf+j, sizeof(buf)-j,
							" out %d", lov);
				}
			}else{
				if((volumes[m].flag&(Fin|Fout))==(Fin|Fout) &&
				    liv==lov && riv==rov)
					j += snprint(buf+j, sizeof(buf)-j,
						" left %d right %d",
						liv, riv);
				else{
					if(volumes[m].flag & Fin)
						j += snprint(buf+j, sizeof(buf)-j,
							" in left %d right %d",
							liv, riv);
					if(volumes[m].flag & Fout)
						j += snprint(buf+j, sizeof(buf)-j,
							" out left %d right %d",
							lov, rov);
				}
			}
			j += snprint(buf+j, sizeof(buf)-j, "\n");
		}
		return readstr(offset, p, n, buf);
	}
	return n0-n;
}

static long
audiowrite(Chan *c, void *vp, long n, vlong)
{
	long m, n0;
	int i, nf, v, left, right, in, out;
	char buf[255], *field[Ncmd];
	char *p;
	IOstate *a;

	p = vp;
	n0 = n;
	switch((ulong)c->qid.path) {
	default:
		error(Eperm);
		break;

	case Qvolume:
	case Qaudioctl:
		v = Vaudio;
		left = 1;
		right = 1;
		in = 1;
		out = 1;
		if(n > sizeof(buf)-1)
			n = sizeof(buf)-1;
		memmove(buf, p, n);
		buf[n] = '\0';
		n = 0;

		nf = getfields(buf, field, Ncmd, 1, " \t\n");
		for(i = 0; i < nf; i++){
			/*
			 * a number is volume
			 */
			if(field[i][0] >= '0' && field[i][0] <= '9') {
				m = strtoul(field[i], 0, 10);
				if(v == Vspeed){
					if(archaudiospeed(m, 0) < 0)
						error(Evolume);
				}else
					if(m < 0 || m > 100)
						error(Evolume);
				if(left && out)
					audio.lovol[v] = m;
				if(left && in)
					audio.livol[v] = m;
				if(right && out)
					audio.rovol[v] = m;
				if(right && in)
					audio.rivol[v] = m;
				goto cont0;
			}
			if(strcmp(field[i], "rate") == 0)
				field[i] = "speed";	/* honestly ... */

			for(m=0; volumes[m].name; m++) {
				if(strcmp(field[i], volumes[m].name) == 0) {
					v = m;
					in = 1;
					out = 1;
					left = 1;
					right = 1;
					goto cont0;
				}
			}
			if(strcmp(field[i], "enc") == 0) {
				if(++i >= nf)
					error(Evolume);
				if(strcmp(field[i], "pcm") != 0)
					error(Evolume);
				goto cont0;
			}
			if(strcmp(field[i], "bits") == 0) {
				if(++i >= nf)
					error(Evolume);
				if(strtol(field[i], 0, 0) != 16)
					error(Evolume);
				goto cont0;
			}
			if(strcmp(field[i], "chans") == 0) {
				if(++i >= nf)
					error(Evolume);
				if(strtol(field[i], 0, 0) != 2)
					error(Evolume);
				goto cont0;
			}
			if(strcmp(field[i], "reset") == 0) {
				resetlevel();
				goto cont0;
			}
			if(strcmp(field[i], "debug") == 0) {
				debug = debug?0:1;
				goto cont0;
			}
			if(strcmp(field[i], "in") == 0) {
				in = 1;
				out = 0;
				goto cont0;
			}
			if(strcmp(field[i], "out") == 0) {
				in = 0;
				out = 1;
				goto cont0;
			}
			if(strcmp(field[i], "left") == 0) {
				left = 1;
				right = 0;
				goto cont0;
			}
			if(strcmp(field[i], "right") == 0) {
				left = 0;
				right = 1;
				goto cont0;
			}
			if(strcmp(field[i], "reg") == 0) {
				if(nf < 3)
					error(Evolume);
				setreg(field[1], atoi(field[2]), nf == 4 ? atoi(field[3]):1);
				return n0;
			}
			error(Evolume);
			break;
		cont0:;
		}
		mxvolume();
		break;

	case Qaudio:
		if (debug > 1) print("#A: write %ld\n", n);
		if((audio.amode & Awrite) == 0)
			error(Emode);
		a = &audio.o;
		qlock(a);
		if(waserror()){
			qunlock(a);
			nexterror();
		}
		while(n > 0) {
			/* wait if dma in progress */
			while (!dmaidle(a->dma) && a->filling == a->current) {
				if (debug > 1) print("#A: sleep\n");
				sleep(&a->vous, audioqnotfull, a);
			}

			m = Bufsize - a->filling->nbytes;
			if(m > n)
				m = n;
			memmove(a->filling->virt + a->filling->nbytes, p, m);

			a->filling->nbytes += m;
			n -= m;
			p += m;
			if(a->filling->nbytes >= Bufsize) {
				if (debug > 1) print("#A: filled @%p\n", a->filling);
				a->filling++;
				if (a->filling == &a->buf[Nbuf])
					a->filling = a->buf;
				sendaudio(a);
			}
		}
		poperror();
		qunlock(a);
		break;
	}
	return n0 - n;
}

Dev audiodevtab = {
	'A',
	"audio",

	audioreset,
	audioinit,
	devshutdown,
	audioattach,
	audiowalk,
	audiostat,
	audioopen,
	devcreate,
	audioclose,
	audioread,
	devbread,
	audiowrite,
	devbwrite,
	devremove,
	devwstat,
	audiopower,
};
