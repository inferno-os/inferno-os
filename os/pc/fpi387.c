/*
 * Copyright © 1999 Vita Nuova Limited
 *
 * this doesn't attempt to implement 387 floating-point properties
 * that aren't visible in the Inferno environment.  in particular,
 * all arithmetic is done in double precision, not extended precision.
 * furthermore, the FP trap status isn't updated.
 */

#ifdef TEST
#include <u.h>
#include <libc.h>
#include <ureg.h>
#include "fpi.h"
#include "tst.h"
#else
#include <u.h>
#include	"ureg.h"
#include "fpi.h"
#include	"../port/lib.h"
#include	"mem.h"
#include	"dat.h"
#include	"fns.h"
#include	"io.h"
#endif

#define	fabs	Fabs

typedef struct FPI FPI;

struct FPI {
	char*	name;
	void	(*f)(Ureg*, int, void*, Internal*, Internal*);
	int	dstf;
};

enum {
	RndNearest = 0,
	RndDown,
	RndUp,
	Rnd0,

	C0 = 1<<8,
	C1 = 1<<9,
	C2 = 1<<10,
	C3 = 1<<14,
};


int	fpemudebug = 0;

static Internal fpconst[7] = {	/* indexed by op&7 */
	/* s, e, l, h */
	{0, 0x3FF, 0x00000000, 0x08000000},	/* 1 */
	{0, 0x400, 0x0BCD1B8A, 0x0D49A784}, /* l2t */
	{0, 0x3FF, 0x095C17F0, 0x0B8AA3B2}, /* l2e */
	{0, 0x400, 0x022168C2, 0x0C90FDAA},	/* pi */
	{0, 0x3FD, 0x04FBCFF7, 0x09A209A8}, /* lg2 */
	{0, 0x3FE, 0x07D1CF79, 0x0B17217F}, /* ln2 */
	{0, 0x1, 0x00000000, 0x00000000}, /* z */
};

static Internal *fpstk(int i);
#define ST(x) (*fpstk((x)))

#define	I387	(up->env->fpu)

/* BUG: check fetch (not worthwhile in Inferno) */
#define	getubyte(a) (*(uchar*)(a))
#define	getuword(a) (*(ushort*)(a))
#define	getulong(a) (*(ulong*)(a))

static void
popfp(void)
{
	ushort *s;

	s = &I387.status;
	*s = (*s & ~0x3800) | ((*s + 0x0800) & 0x3800);
}

static void
pushfp(void)
{
	ushort *s;

	s = &I387.status;
	*s = (*s & ~0x3800) | ((*s + 0x3800) & 0x3800);
}

static Internal *
fpstk(int i)
{
	return (Internal*)I387.istack[(i+(I387.status>>11))&7];
}

static void
fldc(Ureg*, int op, void*, Internal*, Internal *d)
{
	*d = fpconst[op&7];
}

static void
fabs(Ureg*, int, void*, Internal*, Internal *d)
{
	d->s = 0;
}

static void
fchs(Ureg*, int, void*, Internal*, Internal *d)
{
	d->s ^= 1;
}

static void
fadd(Ureg*, int, void*, Internal *s, Internal *d)
{
	Internal l, r;

	l = *s;
	r = *d;
	(l.s == r.s? fpiadd: fpisub)(&l, &r, d);
}

static void
fsub(Ureg*, int, void*, Internal *s, Internal *d)
{
	Internal l, r;

	l = *s;
	r = *d;
	l.s ^= 1;
	(l.s == r.s? fpiadd: fpisub)(&l, &r, d);
}

static void
fsubr(Ureg*, int, void*, Internal *s, Internal *d)
{
	Internal l, r;

	l = *s;
	r = *d;
	r.s ^= 1;
	(l.s == r.s? fpiadd: fpisub)(&r, &l, d);
}

static void
fmul(Ureg*, int, void*, Internal *s, Internal *d)
{
	Internal l, r;

	l = *s;
	r = *d;
	fpimul(&l, &r, d);
}

static void
fdiv(Ureg*, int, void*, Internal *s, Internal *d)
{
	Internal l, r;

	l = *s;
	r = *d;
	fpidiv(&l, &r, d);
}

static void
fdivr(Ureg*, int, void*, Internal *s, Internal *d)
{
	Internal l, r;

	l = *s;
	r = *d;
	fpidiv(&r, &l, d);
}

static void
fcom(Ureg*, int, void*, Internal *s, Internal *d)
{
	int i;
	ushort *p;

	p = &I387.status;
	if(IsWeird(s) || IsWeird(d)){
		*p |= C0|C2|C3;
		/* BUG: should trap if not masked */
		return;
	}
	*p &= ~(C0|C2|C3);
	i = fpicmp(d, s);
	if(i < 0)
		*p |= C0;
	else if(i == 0)
		*p |= C3;
}

static void
fpush(Ureg*, int op, void*, Internal*, Internal*)
{
	Internal *p;

	p = &ST(op & 7);
	pushfp();
	ST(0) = *p;
}

static void
fmov(Ureg*, int, void*, Internal *s, Internal *d)
{
	*d = *s;
}

static void
fmovr(Ureg*, int, void*, Internal *s, Internal *d)
{
	*s = *d;
}

static void
fxch(Ureg*, int, void*, Internal *s, Internal *d)
{
	Internal t;

	t = *s; *s = *d; *d = t;
}

static void
frstor(Ureg*, int, void *s, Internal*, Internal*)
{
	validaddr(s, 108, 0);
	memmove(&I387, s, 108);
}

static void
fsave(Ureg*, int, void *d, Internal*, Internal*)
{
	validaddr(d, 108, 1);
	memmove(d, &I387, 108);
	I387.control = 0x037F;
	I387.status = 0;
	I387.tag = 0;
}

static void
fstsw(Ureg*, int, void *d, Internal*, Internal*)
{
	validaddr(d, 2, 1);
	*(short*)d = I387.status;
}

static void
fldenv(Ureg*, int, void *s, Internal*, Internal*)
{
	validaddr(s, 28, 0);
	memmove(&I387, s, 28);
}

static void
fldcw(Ureg*, int, void *s, Internal*, Internal*)
{
	validaddr(s, 2, 0);
	I387.control = *(short*)s;
}

static void
fstenv(Ureg*, int, void *d, Internal*, Internal*)
{
	validaddr(d, 4*7, 1);
	memmove(d, &I387, 4*7);
}

static void
fstcw(Ureg*, int, void *d, Internal*, Internal*)
{
	validaddr(d, 2, 1);
	*(short*)d = I387.control;
}

static void
fincstp(Ureg*, int, void*, Internal*, Internal*)
{
	popfp();
}

static void
fdecstp(Ureg*, int, void*, Internal*, Internal*)
{
	pushfp();
}

static void
fscale(Ureg*, int, void*, Internal *s, Internal *d) 
{
	Word w;

	fpii2w(&w, s);	/* should truncate towards zero ... */
	d->e += w;
}

static void
fstswax(Ureg *ur, int, void*, Internal*, Internal*)
{
	ur->ax = (ur->ax & ~0xFFFF) | (I387.status & 0xFFFF);
}

static void
ftst(Ureg*, int, void*, Internal*, Internal *d)
{
	ushort *p;

	p = &I387.status;
	if(IsWeird(d)){
		*p |= C0|C2|C3;
		return;
	}
	*p &= ~(C0|C2|C3);
	fpinormalise(d);
	if(IsZero(d))
		*p |= C3;
	else if(d->s)
		*p |=C0;
}

static void
frndint(Ureg*, int, void*, Internal*, Internal *d)
{
	fpiround(d);	/* BUG: doesn't look at rounding mode */
}

static void
fnop(Ureg*, int, void*, Internal*, Internal*)
{
}

enum {
	Fpop1= 1<<0,
	Fpop2 = 1<<1,
	Fload = 1<<2,
};

/*
 * %e	-	effective address - Mod R/M value
 * %f	-	floating point register F0-F7 - from Mod R/M register
 */

static void fload(Ureg*, int, void*, Internal*, Internal*);
static void fstore(Ureg*, int, void*, Internal*, Internal*);

#define	X(a,b) (((a)<<2)|(b))

static	FPI	optab1[4][4] = {	/* normal mod r/m operand */
[0]	{
	[0]	{"FLDENV %e", fldenv, 0},
	[1]	{"FLDCW %e", fldcw, 0},
	[2]	{"FSTENV %e", fstenv, 0},
	[3]	{"FSTCW %e", fstcw, 0},
	},
[1]	{
	[1]	{"FMOVX %e,F0", nil, Fload},
	[3]	{"FMOVXP F0,%e", nil, Fpop1},
	},
[2]	{
	[0]	{"FRSTOR %e", frstor, 0},
	[2]	{"FSAVE %e", fsave, 0},
	[3]	{"FSTSW %e", fstsw, 0},
	},
[3]	{
	[0]	{"FMOVB %e", nil, 0},
	[1]	{"FMOVV %e,F0", nil, Fload},
	[2]	{"FMOVBP %e", nil, Fpop1},
	[3]	{"FMOVVP F0,%e", nil, Fpop1},
	},
};

#undef X

static	FPI	optab2a[1<<3] = {	/* A=0 */
[0]	{"FADDx %e,F0", fadd, 0},
[1]	{"FMULx %e,F0", fmul, 0},
[2]	{"FCOMx %e,F0", fcom, 0},
[3]	{"FCOMxP %e,F0", fcom, Fpop1},
[4]	{"FSUBx %e,F0", fsub, 0},
[5]	{"FSUBRx %e,F0", fsubr, 0},	/* ?? */
[6]	{"FDIVx %e,F0", fdiv, 0},
[7]	{"FDIVRx %e,F0", fdivr, 0},	/* ?? */
};

static	FPI	optab2b[1<<2] = {	/* A=1, B=0,2,3 */
[0]	{"FMOVx %e,F0", fload, Fload},
[2]	{"FMOVx F0,%e", fstore, 0},
[3]	{"FMOVxP F0,%e", fstore, Fpop1},
};

#define	X(d,P,B) ((d<<4)|(P<<3)|B)

static	FPI	optab3a[1<<5] = {	/* A=0 */
[X(0,0,0)]	{"FADDD	%f,F0", fadd, 0},
[X(1,0,0)]	{"FADDD	F0,%f", fadd, 0},
[X(1,1,0)]	{"FADDDP	F0,%f", fadd, Fpop1},
[X(0,0,1)]	{"FMULD	%f,F0", fmul, 0},
[X(1,0,1)]	{"FMULD	F0,%f", fmul, 0},
[X(1,1,1)]	{"FMULDP	F0,%f", fmul, Fpop1},
[X(0,0,2)]	{"FCOMD	%f,F0", fcom, 0},
[X(0,0,3)]	{"FCOMDP	%f,F0", fcom, Fpop1},
[X(1,1,3)]	{"FCOMDPP", fcom, Fpop1|Fpop2},
[X(0,0,4)]	{"FSUBD	%f,F0", fsub, 0},
[X(1,0,4)]	{"FSUBRD	F0,%f", fsubr, 0},
[X(1,1,4)]	{"FSUBRDP F0,%f", fsubr, Fpop1},
[X(0,0,5)]	{"FSUBRD	%f,F0", fsubr, 0},
[X(1,0,5)]	{"FSUBD	F0,%f", fsub, 0},
[X(1,1,5)]	{"FSUBDP	F0,%f", fsub, Fpop1},
[X(0,1,5)]	{"FUCOMPP", fcom, Fpop1|Fpop2},
[X(0,0,6)]	{"FDIVD	%f,F0", fdiv, 0},
[X(1,0,6)]	{"FDIVRD	F0,%f", fdivr, 0},
[X(1,1,6)]	{"FDIVRDP F0,%f", fdivr, Fpop1},
[X(0,0,7)]	{"FDIVRD	%f,F0", fdivr, 0},
[X(1,0,7)]	{"FDIVD	F0,%f", fdiv, 0},
[X(1,1,7)]	{"FDIVDP	F0,%f", fdiv, Fpop1},
};

static	FPI	optab3b[1<<5] = {	/* A=1 */
[X(0,0,0)]	{"FMOVD	%f,F0", fmov, Fload},
[X(0,0,1)]	{"FXCHD	%f,F0", fxch, 0},
[X(0,0,2)]	{"FNOP", fnop, 0},	/* F0 only */
[X(1,0,0)]	{"FFREED	%f", fnop, 0},
[X(1,0,2)]	{"FMOVD	F0,%f", fmovr, 0},
[X(1,0,3)]	{"FMOVDP	F0,%f", fmovr, Fpop1},
[X(1,1,4)]	{"FSTSW	AX", fstswax, 0},
[X(1,0,4)]	{"FUCOMD	%f,F0", fcom, 0},
[X(1,0,5)]	{"FUCOMDP %f,F0", fcom, Fpop1},
};

#undef X

static	FPI	optab4[1<<6] = {
[0x00]	{"FCHS", fchs, 0},
[0x01]	{"FABS", fabs, 0},
[0x04]	{"FTST", ftst, 0},
[0x05]	{"FXAM", nil, 0},
[0x08]	{"FLD1", fldc, Fload},
[0x09]	{"FLDL2T", fldc, Fload},
[0x0a]	{"FLDL2E", fldc, Fload},
[0x0b]	{"FLDPI", fldc, Fload},
[0x0c]	{"FLDLG2", fldc, Fload},
[0x0d]	{"FLDLN2", fldc, Fload},
[0x0e]	{"FLDZ", fldc, Fload},
[0x10]	{"F2XM1", nil, 0},
[0x11]	{"FYL2X", nil, 0},
[0x12]	{"FPTAN", nil, 0},
[0x13]	{"FPATAN", nil, 0},
[0x14]	{"FXTRACT", nil, 0},
[0x15]	{"FPREM1", nil, 0},
[0x16]	{"FDECSTP", fdecstp, 0},
[0x17]	{"FINCSTP", fincstp, 0},
[0x18]	{"FPREM", nil, 0},
[0x19]	{"FYL2XP1", nil, 0},
[0x1a]	{"FSQRT", nil, 0},
[0x1b]	{"FSINCOS", nil, 0},
[0x1c]	{"FRNDINT", frndint, 0},
[0x1d]	{"FSCALE", fscale, 0},
[0x1e]	{"FSIN", nil, 0},
[0x1f]	{"FCOS", nil, 0},
};

static void
loadr32(void *s, Internal *d)
{
	validaddr(s, 4, 0);
	fpis2i(d, s);
}

static void
loadi32(void *s, Internal *d)
{
	validaddr(s, 4, 0);
	fpiw2i(d, s);
}

static void
loadr64(void *s, Internal *d)
{
	validaddr(s, 8, 0);
	fpid2i(d, s);
}

static void
loadi16(void *s, Internal *d)
{
	Word w;

	validaddr(s, 2, 0);
	w = *(short*)s;
	fpiw2i(d, &w);
}

static	void	(*loadf[4])(void*, Internal*) ={
	loadr32, loadi32, loadr64, loadi16
};

static void
storer32(Internal s, void *d)
{
	validaddr(d, 4, 1);
	fpii2s(d, &s);
}

static void
storei32(Internal s, void *d)
{
	validaddr(d, 4, 1);
	fpii2w(d, &s);
}

static void
storer64(Internal s, void *d)
{
	validaddr(d, 8, 1);
	fpii2d(d, &s);
}

static void
storei16(Internal s, void *d)
{
	Word w;

	validaddr(d, 2, 1);
	fpii2w(&w, &s);
	if((short)w != w)
		;	/* overflow */
	*(short*)d = w;
}

static	void	(*storef[4])(Internal, void*) ={
	storer32, storei32, storer64, storei16
};

static void
fload(Ureg*, int op, void *mem, Internal*, Internal *d)
{
	(*loadf[(op>>9)&3])(mem, d);
}

static void
fstore(Ureg*, int op, void *mem, Internal *s, Internal*)
{
	(*storef[(op>>9)&3])(*s, mem);
}

#define	REG(x) (*(ulong*)(((char*)ur)+roff[(x)]))

static	int	roff[] = {
	offsetof(Ureg, ax),
	offsetof(Ureg, cx),
	offsetof(Ureg, dx),
	offsetof(Ureg, bx),
	offsetof(Ureg, ecode),	/* ksp */
	offsetof(Ureg, bp),
	offsetof(Ureg, si),
	offsetof(Ureg, di),
};

static long
getdisp(Ureg *ur, int mod, int rm)
{
	uchar c;
	long disp;

	if(mod > 2)
		return 0;
	disp = 0;
	if(mod == 1) {
		c = getubyte(ur->pc++);
		if(c&0x80)
			disp = c|(~0<<8);
		else
			disp = c;
	} else if(mod == 2 || rm == 5) {
		disp = getulong(ur->pc);
		ur->pc += 4;
	}
	if(mod || rm != 5)
		disp += REG(rm);	/* base */
	return disp;
}

static ulong
modrm(Ureg *ur, uchar c)
{
	uchar rm, mod;
	int reg;
	ulong base;

	mod = (c>>6)&3;
	rm = c&7;
	if(mod == 3)	/* register */
		error("sys: fpemu: invalid addr mode");
	/* no 16-bit mode */
	if(rm == 4) {	/* scummy sib byte */
		c = getubyte(ur->pc++);
		reg = (c>>3)&0x07;	/* index */
		base = getdisp(ur, mod, c&7);
		if(reg != 4)
			base += (REG(reg) << (c>>6));	/* index */
		if(fpemudebug>1)
			print("ur=#%lux sib=#%x reg=%d mod=%d base=%d basev=#%lux sp=%lux\n", ur, c, reg, mod, c&7, base, ur->usp);
		return base;
	}
	if(rm == 5 && mod == 0){
		ur->pc += 4;
		return getulong(ur->pc-4);
	}
	return getdisp(ur, mod, rm);
}

static void *
ea(Ureg *ur, uchar op)
{
	ulong addr;

	addr = modrm(ur, op);
	I387.operand = addr;
	if(fpemudebug>1)
		print("EA=#%lux\n", addr);
	return (void*)addr;
}

void
fpi387(Ureg *ur)
{
	int op, i;
	ulong pc;
	FPenv *ufp;
	FPI *fp;
	Internal tmp, *s, *d;
	void *mem;
	char buf[60];

	ur->ecode = (ulong)&ur->sp;	/* BUG: TEMPORARY compensation for incorrect Ureg for kernel mode */
	ufp = &up->env->fpu;	/* because all the state is in Osenv, it need not be saved/restored */
	if(ufp->fpistate != FPACTIVE) {
		ufp->fpistate = FPACTIVE;
		ufp->control = 0x037f;
		ufp->status = 0;
		ufp->tag = 0;
		ufp->oselector = 0x17;
	}
	while((op = getubyte(ur->pc)) >= 0xd8 && op <= 0xdf || op == 0x9B){
		if(op == 0x9B){	/* WAIT */
			ur->pc++;
			continue;
		}
		if(ufp->control & ufp->status & 0x3F)
			ufp->status |= 0x8000;
		else
			ufp->status &= 0x7FFF;
		pc = ur->pc;
		op = (op<<8) | getubyte(pc+1);
		ufp->selector = ur->cs;
		ufp->r4 = op-0xD800;
		ur->pc += 2;
		mem = nil;
		s = nil;
		d = nil;
		/* decode op, following table 10.2.4 in i486 handbook */
		i = op & 0xFFE0;
		if(i == 0xD9E0){
			fp = &optab4[op&0x1F];
			s = &ST(0);
			if(fp->dstf & Fload)
				pushfp();
			d = &ST(0);
		} else if(i == 0xDBE0){
			i = op & 0x1F;
			if(i == 2){	/* FCLEX */
				ufp->status &= 0x7f00;
				continue;
			} else if(i == 3){	/* FINIT */
				ufp->control = 0x037f;
				ufp->status = 0;
				ufp->tag = 0;
				continue;
			}
			fp = nil;
		} else if((op & 0xF8C0) == 0xD8C0){
			i = ((op>>6)&030)|((op>>3)&7);
			if(op & (1<<8)){
				fp = &optab3b[i];
				s = &ST(op&7);
				if(fp->dstf & Fload)
					pushfp();
				d = &ST(0);
			} else {
				fp = &optab3a[i];
				i = op & 7;
				if(op & (1<<10)){
					s = &ST(0);
					d = &ST(i);
				}else{
					s = &ST(i);
					d = &ST(0);
				}
			}
		} else if((op & 0xF920) == 0xD920){
			mem = ea(ur, op&0xFF);
			fp = &optab1[(op>>9)&3][(op>>3)&3];
		} else {
			mem = ea(ur, op&0xFF);
			if(op & (1<<8)){
				/* load/store */
				fp = &optab2b[(op>>3)&7];
				if(fp->dstf & Fload){
					pushfp();
					d = &ST(0);
				} else
					s = &ST(0);
			} else {
				/* mem OP reg */
				fp = &optab2a[(op>>3)&7];
				(*loadf[(op>>9)&3])(mem, &tmp);
				s = &tmp;
				d = &ST(0);
			}
		}
		if(fp == nil || fp->f == nil){
			if(fp == nil || fp->name == nil)
				snprint(buf, sizeof(buf), "sys: fp: pc=%lux invalid fp 0x%.4x", pc, op);
			else
				snprint(buf, sizeof(buf), "sys: fp: pc=%lux unimp fp 0x%.4x (%s)", pc, op, fp->name);
			error(buf);
		}
		if(fpemudebug)
			print("%8.8lux %.4x %s\n", pc, op, fp->name);
		(*fp->f)(ur, op, mem, s, d);
		if(fp->dstf & Fpop1){
			popfp();
			if(fp->dstf & Fpop2)
				popfp();
		}
		if(anyhigher())
			sched();
	}
}
