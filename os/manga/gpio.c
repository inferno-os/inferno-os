#include	"u.h"
#include 	"mem.h"
#include	"../port/lib.h"
#include 	"dat.h"
#include	"fns.h"
#include	"io.h"

static ulong gpioreserved;
static Lock gpiolock;

void
gpioreserve(int n)
{
	ulong mask;

	mask = 1<<n;
	ilock(&gpiolock);
	if(gpioreserved & mask)
		panic("gpioreserve: duplicate use of GPIO %d", n);
	gpioreserved |= mask;
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

	ilock(&gpiolock);
	g = GPIOREG;
	if(cfg & Gpio_out)
		g->iopm |= 1<<n;
	else
		g->iopm &= ~(1<<n);
	iunlock(&gpiolock);
}

ulong
gpioget(int n)
{
	return GPIOREG->iopd & (1<<n);
}

void
gpioset(int n, int v)
{
	GpioReg *g;
	ulong mask;

	mask = 1<<n;
	ilock(&gpiolock);
	g = GPIOREG;
	if(v)
		g->iopd |= mask;
	else
		g->iopd &= ~mask;
	iunlock(&gpiolock);
}

void
gpiorelease(int n)
{
	ulong mask;

	mask = 1<<n;
	ilock(&gpiolock);
	if((gpioreserved & mask) != mask)
		panic("gpiorelease: unexpected release of GPIO %d", n);
	gpioreserved &= ~mask;
	iunlock(&gpiolock);
}
