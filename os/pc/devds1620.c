#include	"u.h"
#include	"../port/lib.h"
#include	"mem.h"
#include	"dat.h"
#include	"fns.h"
#include	"../port/error.h"
#include	"io.h"

enum {
	// Ziatech 5512 Digital I/O ASIC register info
	PortSelect =	0xE7,
	Port =		0xE1,
	 DQ =		1<<0,
	 CLK =		1<<1,
	 RST =		1<<2,
	 TL =		1<<3,
	 TH =		1<<4,

	// ds1620 Masks
	Mread =		0xA0,
	Mwrite =	0,

	// ds1620 Registers
	Rtemp =		0x0A,
	Rcounter =	0x00,
	Rslope = 	0x09,
	Rhi =		0x01,
	Rlo =		0x02,
	Rconfig =	0x0C,
	 Cdone =	1<<7,	// conversion done
	 Cthf =		1<<6,	// temp >= Rhi
	 Ctlf =		1<<5,	// temp <= Rlo
	 Cnvb =		1<<4,	// e^2 nvram busy (write may take up to 10ms)
	 Ccpu =		1<<1,	// cpu use (0=clk starts conversion when rst lo)
	 C1shot =	1<<0,	// perform one conversion then stop

	// ds1620 Commands
	Startconv =	0xEE,
	Stopconv =	0x22,

	ALOTEMP = 	0,
	AHITEMP =	1,
};

#define send(v)	outb(Port, v); delay(1)
#define recv()	(!(inb(Port) & 1))

enum {
	Qdir = 0,
	Qtemp,
	Qalarm,
};

Dirtab ds1620tab[]={
	"temp",		{Qtemp, 0},	0,	0666,
	"alarm",	{Qalarm, 0},	0,	0444,
};

typedef struct Temp Temp;
struct Temp
{
	Lock;
	int lo;
	int cur;
	int hi;

	int alo;
	int ahi;
	int atime;
	Queue *aq;
};

static Temp t;

static void
sendreg(int r)
{
	int d, i;

	r = ~r;
	for(i=0;i<8;i++) {
		d = (r >> i) & 1;
		send(CLK|d);
		send(d);
		send(CLK);
	}
}

static int
ds1620rdreg(int r, int nb)
{
	int i, s;

	s = splhi();

	outb(PortSelect, 0);
	send(RST|CLK);
	sendreg(r|Mread);
	r = 0;
	for(i=0; i < nb; i++) {
		r |= recv() << i;
		delay(1);
		send(0);
		send(CLK);
	}
	send(RST);

	splx(s);
	return r;
}

static void
ds1620wrreg(int r, int v, int nb)
{
	int d, i, s;

	s = splhi();

	outb(PortSelect, 0);
	send(RST|CLK);
	sendreg(r|Mwrite);
	v = ~v;
	for(i=0; i < nb; i++) {
		d = (v >> i) & 1;
		send(CLK|d);
		send(0);
		send(CLK);
	}
	send(RST);

	splx(s);
}

static void
ds1620cmd(int r)
{
	int s;

	s = splhi();
	outb(PortSelect, 0);
	send(RST|CLK);
	sendreg(r);
	send(RST);
	splx(s);
}

static char*
t2s(int t)
{
	static char s[16];

	sprint(s, "%4d.", t>>1);
	if(t&1)
		strcat(s, "5");
	else
		strcat(s, "0");
	return s;
}

static int
s2t(char *s)
{
	int v;
	char *p;
	p = strchr(s, '.');
	if(p != nil)
		*p++ = '\0';
	v = strtoul(s, nil, 0);
	v <<= 1;
	if(p != nil && *p != '\0' && *p >= '5')
		v |= 1;
	return v;
}

static void
alarm(int code, Temp *tt)
{
	char buf[256], *end;
	int s;

	s = seconds();

	if(s - tt->atime < 60)
		return;
	tt->atime = s;

	end = buf;
	end += sprint(buf, "(alarm) %8.8uX %uld temp ", code, seconds());
	switch(code) {
	case ALOTEMP:
		end += sprint(end, "%s below threshold ", t2s(tt->lo));
		end += sprint(end, "%s.\n", t2s(tt->alo));
		break;
	case AHITEMP:
		end += sprint(end, "%s above threshold ", t2s(tt->hi));
		end += sprint(end, "%s.\n", t2s(tt->ahi));
		break;
	}

	qproduce(tt->aq, buf, end-buf);
}

void
tmon(void *a)
{
	int r;
	Temp *t;

	t = a;
	r = ds1620rdreg(Rtemp, 9);
	lock(t);
	t->lo = t->cur = t->hi = r;
	unlock(t);
	for(;;) {
		tsleep(&up->sleep, return0, nil, 1000);
		r = ds1620rdreg(Rtemp, 9);
		lock(t);
		t->cur = r;
		if(r < t->lo)
			t->lo = r;
		if(r > t->hi)
			t->hi = r;
		if(t->lo < t->alo)
			alarm(ALOTEMP, t);
		if(t->hi > t->ahi)
			alarm(AHITEMP, t);
		unlock(t);
	}
	pexit("", 0);
}

static void
ds1620init(void)
{
	int r;

	t.aq = qopen(8*1024, Qmsg, nil, nil);
	if(t.aq == nil)
		error(Enomem);

	ds1620wrreg(Rconfig, Ccpu, 8);	// continuous sample mode
	ds1620cmd(Startconv);
	r = ds1620rdreg(Rtemp, 9);
	t.alo = ds1620rdreg(Rlo, 9);	
	t.ahi = ds1620rdreg(Rhi, 9);

	print("#L: temp %s (c) ", t2s(r));
	print("low threshold %s (c) ", t2s(t.alo));
	print("high threshold %s (c)\n", t2s(t.ahi));

	kproc("tempmon", tmon, &t, 0);
}

static Chan*
ds1620attach(char *spec)
{
	return devattach('L', spec);
}

static int
ds1620walk(Chan *c, char* name)
{
	return devwalk(c, name, ds1620tab, nelem(ds1620tab), devgen);
}

static void
ds1620stat(Chan *c, char* db)
{
	ds1620tab[1].length = qlen(t.aq);
	devstat(c, db, ds1620tab, nelem(ds1620tab), devgen);
}

static Chan*
ds1620open(Chan *c, int omode)
{
	return devopen(c, omode, ds1620tab, nelem(ds1620tab), devgen);
}

static void
ds1620close(Chan*)
{
}

static long
ds1620read(Chan *c, void *a, long n, vlong offset)
{
	Temp tt;
	char buf[64];
	char *s;
	if(c->qid.path & CHDIR)
		return devdirread(c, a, n, ds1620tab, nelem(ds1620tab), devgen);
	buf[0] = 0;
	switch(c->qid.path) {
	case Qtemp:
		lock(&t);
		tt = t;
		unlock(&t);
		s = buf;
		s+= sprint(s, "%s ", t2s(tt.lo));
		s+= sprint(s, "%s ", t2s(tt.cur));
		s+= sprint(s, "%s ", t2s(tt.hi));
		s+= sprint(s, "%s ", t2s(tt.alo));
		sprint(s, "%s", t2s(tt.ahi));
		return readstr(offset, a, n, buf);
	case Qalarm:
		return qread(t.aq, a, n);
	default:
		error(Egreg);
		return 0;
	}
}

static long
ds1620write(Chan *c, void *a, long n, vlong)
{
	char buf[64];
	char *f[2];
	int lo, hi;
	int nf;

	if(c->qid.path & CHDIR)
		error(Eperm);

	if(c->qid.path == Qtemp) {
		if(n >= sizeof(buf))
			n = sizeof(buf)-1;
		memmove(buf, a, n);
		buf[n] = '\0';
		nf = getfields(buf, f, 2, 1, " \t");
		if(nf != 2)
			error(Ebadarg);
		lo = s2t(f[0]);
		hi = s2t(f[1]);
		lock(&t);
		t.alo = lo;
		t.ahi = hi;
		t.atime = 0;
		ds1620wrreg(Rlo, lo, 9);
		delay(1);
		ds1620wrreg(Rhi, hi, 9);
		unlock(&t);
		return n;
	} else
		error(Eio);
	return 0;

}

Dev ds1620devtab = {
	'L',
	"ds1620",
	devreset,
	ds1620init,
	ds1620attach,
	devdetach,
	devclone,
	ds1620walk,
	ds1620stat,
	ds1620open,
	devcreate,
	ds1620close,
	ds1620read,
	devbread,
	ds1620write,
	devbwrite,
	devremove,
	devwstat,
};
