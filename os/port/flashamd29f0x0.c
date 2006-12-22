#include	"u.h"
#include	"../port/lib.h"
#include	"mem.h"
#include	"dat.h"
#include	"fns.h"
#include	"io.h"
#include	"../port/error.h"

#include	"../port/flashif.h"

/*
 * AMD29F0x0 with 4 interleaved to give 32 bits
 */

enum {
	DQ7 = 0x80808080,
	DQ6 = 0x40404040,
	DQ5 = 0x20202020,
	DQ3 = 0x08080808,
	DQ2 = 0x04040404,
};

#define	DPRINT	if(0)print
#define	EPRINT	if(1)print

static char*
amdwait(ulong *p, ulong ticks)
{
	ulong v0, v1;

	ticks += m->ticks+1;
	v0 = *p;
	for(;;){
		sched();
		v1 = *p;
		if((v1 & DQ6) == (v0 & DQ6))
			break;
		if((v1 & DQ5) == DQ5){
			v0 = *p;
			v1 = *p;
			if((v1 & DQ6) == (v0 & DQ6))
				break;
			EPRINT("flash: DQ5 error: %8.8lux %8.8lux\n", v0, v1);
			return "flash write error";
		}
		if(m->ticks >= ticks){
			EPRINT("flash: timed out: %8.8lux\n", *p);
			return "flash write timed out";
		}
		v0 = v1;
	}
	return nil;
}

static int
eraseall(Flash *f)
{
	ulong *p;
	int s;
	char *e;

	DPRINT("flash: erase all\n");
	p = (ulong*)f->addr;
	s = splhi();
	*(p+0x555) = 0xAAAAAAAA;
	*(p+0x2AA) = 0x55555555;
	*(p+0x555) = 0x80808080;
	*(p+0x555) = 0xAAAAAAAA;
	*(p+0x2AA) = 0x55555555;
	*(p+0x555) = 0x10101010;	/* chip erase */
	splx(s);
	e = amdwait(p, MS2TK(64*1000));
	*p = 0xF0F0F0F0;	/* reset */
	if(e != nil)
		error(e);
	return 0;
}

static int
erasezone(Flash *f, Flashregion *r, ulong addr)
{
	ulong *p;
	int s;
	char *e;

	DPRINT("flash: erase %8.8lux\n", addr);
	if(addr & (r->erasesize-1))
		return -1;	/* bad zone */
	p = (ulong*)f->addr;
	s = splhi();
	*(p+0x555) = 0xAAAAAAAA;
	*(p+0x2AA) = 0x55555555;
	*(p+0x555) = 0x80808080;
	*(p+0x555) = 0xAAAAAAAA;
	*(p+0x2AA) = 0x55555555;
	p += addr>>2;
	*p = 0x30303030;	/* sector erase */
	splx(s);
	e = amdwait(p, MS2TK(8*1000));
	*p = 0xF0F0F0F0;	/* reset */
	if(e != nil)
		error(e);
	return 0;
}

static int
write4(Flash *f, ulong offset, void *buf, long n)
{
	ulong *p, *a, *v, w;
	int s;
	char *e;

	p = (ulong*)f->addr;
	if(((ulong)p|offset|n)&3)
		return -1;
	n >>= 2;
	a = p + (offset>>2);
	v = buf;
	for(; --n >= 0; v++, a++){
		w = *a;
		DPRINT("flash: write %lux %lux -> %lux\n", (ulong)a, w, *v);
		if(w == *v)
			continue;	/* already set */
		if(~w & *v)
			error("flash not erased");
		s = splhi();
		*(p+0x555) = 0xAAAAAAAA;
		*(p+0x2AA) = 0x55555555;
		*(p+0x555) = 0xA0A0A0A0;	/* program */
		*a = *v;
		splx(s);
		microdelay(8);
		if(*a != *v){
			microdelay(8);
			while(*a != *v){
				e = amdwait(a, 1);
				if(e != nil)
					error(e);
			}
		}
	}
	return 0;
}

static int
reset(Flash *f)
{
	f->id = 0x01;	/* can't use autoselect: might be running in flash */
	f->devid = 0;
	f->write = write4;
	f->eraseall = eraseall;
	f->erasezone = erasezone;
	f->suspend = nil;
	f->resume = nil;
	f->width = 4;
	f->interleave = 0;	/* TO DO */
	f->nr = 1;
	f->regions[0] = (Flashregion){f->size/(4*64*1024), 0, f->size, 4*64*1024, 0};
	*(ulong*)f->addr = 0xF0F0F0F0;	/* reset (just in case) */
	return 0;
}

void
flashamd29f0x0link(void)
{
	addflashcard("AMD29F0x0", reset);
}
