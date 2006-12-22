#include	"u.h"
#include 	"mem.h"
#include	"../port/lib.h"
#include 	"dat.h"
#include	"fns.h"
#include	"io.h"

static ulong gpioreserved[3];
static Lock gpiolock;

void
gpioreserve(int n)
{
	ulong mask, *r;

	r = &gpioreserved[GPR(n)];
	mask = GPB(n);
	ilock(&gpiolock);
	if(*r & mask)
		panic("gpioreserve: duplicate use of GPIO %d", n);
	*r |= mask;
	iunlock(&gpiolock);
}

/*
 * set direction and alternative function bits in the GPIO control register,
 * following the configuration bits in cfg.
 */
void
gpioconfig(int n, ulong cfg)
{
	GpioReg *g;
	ulong o, m, *r;

	m = GPB(n);
	o = n>>5;
	ilock(&gpiolock);
	g = GPIOREG;
	r = &g->gpdr[o];
	if(cfg & Gpio_out)
		*r |= m;
	else
		*r &= ~m;
	r = &g->gafr[o*2];
	*r = (*r & ~GPAF(n, 3)) | GPAF(n, cfg&3);
	iunlock(&gpiolock);
}

ulong
gpioget(int n)
{
	ulong mask, o;

	mask = GPB(n);
	o = GPR(n);
	return GPIOREG->gplr[o] & mask;
}

void
gpioset(int n, int v)
{
	GpioReg *g;
	ulong mask, o;

	g = GPIOREG;
	mask = GPB(n);
	o = GPR(n);
	ilock(&gpiolock);
	if(v)
		g->gpsr[o] = mask;
	else
		g->gpcr[o] = mask;
	iunlock(&gpiolock);
}

void
gpiorelease(int n)
{
	ulong mask, *r;

	mask = GPB(n);
	r = &gpioreserved[GPR(n)];
	ilock(&gpiolock);
	if((*r & mask) != mask)
		panic("gpiorelease: unexpected release of GPIO %d", n);
	*r &= ~mask;
	iunlock(&gpiolock);
}
