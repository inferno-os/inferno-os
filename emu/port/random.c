#include	"dat.h"
#include	"fns.h"

extern void prng(uchar *buf, int nbytes);

static struct
{
	QLock	l;
	Rendez	producer;
	Rendez	consumer;
	Rendez	clock;
	ulong	randomcount;
	uchar	buf[1024];
	uchar	*ep;
	uchar	*rp;
	uchar	*wp;
	uchar	next;
	uchar	bits;
	uchar	wakeme;
	uchar	filled;
	int	kprocstarted;
	ulong	randn;
	ulong	mixstate;	/* additional non-linear mixer state */
	int	target;
} rb;

static int
rbnotfull(void *v)
{
	int i;

	USED(v);
	i = rb.wp - rb.rp;
	if(i < 0)
		i += sizeof(rb.buf);
	return i < rb.target;
}

static int
rbnotempty(void *v)
{
	USED(v);
	return rb.wp != rb.rp;
}

/*
 *  spin counting up
 */
static void
genrandom(void *v)
{
	USED(v);
	oslopri();
	for(;;){
		for(;;)
			if(++rb.randomcount > 65535)
				break;
		if(rb.filled || !rbnotfull(0))
			Sleep(&rb.producer, rbnotfull, 0);
	}
}

/*
 *  produce random bits in a circular buffer
 */
static void
randomclock(void *v)
{
	uchar *p;

	USED(v);
	for(;; osmillisleep(20)){
		while(!rbnotfull(0)){
			rb.filled = 1;
			Sleep(&rb.clock, rbnotfull, 0);
		}
		if(rb.randomcount == 0)
			continue;

		rb.bits = (rb.bits<<2) ^ rb.randomcount;
		rb.randomcount = 0;

		rb.next++;
		if(rb.next != 8/2)
			continue;
		rb.next = 0;

		p = rb.wp;
		*p ^= rb.bits;
		if(++p == rb.ep)
			p = rb.buf;
		rb.wp = p;

		if(rb.wakeme)
			Wakeup(&rb.consumer);
	}
}

void
randominit(void)
{
	rb.target = 16;
	rb.ep = rb.buf + sizeof(rb.buf);
	rb.rp = rb.wp = rb.buf;

	/*
	 * Seed the mixer state from host OS entropy so the output
	 * is not predictable even if the timing-based entropy is weak
	 * (e.g. in VMs or containers with synchronized clocks).
	 */
	prng((uchar*)&rb.randn, sizeof(rb.randn));
	prng((uchar*)&rb.mixstate, sizeof(rb.mixstate));
}

/*
 *  consume random bytes from a circular buffer
 */
ulong
randomread(void *xp, ulong n)
{
	uchar *e, *p, *r;
	ulong x;
	int i;

	p = xp;

if(0)print("A%ld.%d.%lux|", n, rb.target, getcallerpc(&xp));
	if(waserror()){
		qunlock(&rb.l);
		nexterror();
	}

	qlock(&rb.l);
	if(!rb.kprocstarted){
		rb.kprocstarted = 1;
		kproc("genrand", genrandom, 0, 0);
		kproc("randomclock", randomclock, 0, 0);
	}

	for(e = p + n; p < e; ){
		r = rb.rp;
		if(r == rb.wp){
			rb.wakeme = 1;
			Wakeup(&rb.clock);
			Wakeup(&rb.producer);
			Sleep(&rb.consumer, rbnotempty, 0);
			rb.wakeme = 0;
			continue;
		}

		/*
		 *  Beating clocks will be predictable if
		 *  they are synchronized.  Mix the timing entropy
		 *  with a non-linear function seeded from host OS
		 *  entropy at init time, so the output is not
		 *  predictable even with weak timing sources.
		 *
		 *  Uses xorshift-multiply mixing (splitmix-style)
		 *  instead of the previous weak LCG (1103515245).
		 */
		rb.mixstate += 0x9e3779b9UL;
		x = rb.mixstate ^ *r;
		x ^= rb.randn;
		x ^= (x >> 13);
		x *= 0x5bd1e995UL;	/* MurmurHash2 mixing constant */
		x ^= (x >> 15);
		*p++ = rb.randn = x;

		if(++r == rb.ep)
			r = rb.buf;
		rb.rp = r;
	}
	if(rb.filled && rb.wp == rb.rp){
		i = 2*rb.target;
		if(i > sizeof(rb.buf) - 1)
			i = sizeof(rb.buf) - 1;
		rb.target = i;
		rb.filled = 0;
	}
	qunlock(&rb.l);
	poperror();

	Wakeup(&rb.clock);
	Wakeup(&rb.producer);

if(0)print("B");
	return n;
}
