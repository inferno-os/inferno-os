#include "lib9.h"
#include "isa.h"
#include "interp.h"
#include "raise.h"

/*
 * Copyright © 1997 C H Forsyth (forsyth@terzarima.net)
 */

#define	ROMABLE	0	/* costs something to zero patch vectors */
#define	RESCHED 1	/* check for interpreter reschedule */

#define PATCH(ptr)		   *ptr |= ((ulong)code-(ulong)ptr) & 0xfffc

#define T(r)	*((void**)(R.r))

#define	XO(o,xo)	(((o)<<26)|((xo)<<1))

/* botch: ARRR, AIRR, LRRR, etc have dest first (will fix soon) */

#define	OPARRR(o,d,a,b)	((o)|((d)<<21)|((a)<<16)|((b)<<11))
#define	ARRR(o,d,a,b)		gen((o)|((d)<<21)|((a)<<16)|((b)<<11))
#define	AIRR(o,d,a,v)		gen((o)|((d)<<21)|((a)<<16)|((v)&0xFFFF))
#define	IRR(o,v,a,d)	AIRR((o),(d),(a),(v))
#define	RRR(o,b,a,d)	ARRR((o),(d),(a),(b))
#define	LRRR(o,a,s,b)		ARRR((o),(s),(a),(b))
#define	LIRR(o,a,s,v)		AIRR((o),(s),(a),(v))
#define	Bx(li,aa)		gen((18<<26)|((li)&0x3FFFFFC)|((aa)<<1))
#define	RLW(op,a,s,sh,mb,me) ((op)|(((s)&31L)<<21)|(((a)&31L)<<16)|(((sh)&31L)<<11)|\
					(((mb)&31L)<<6)|(((me)&31L)<<1))
#define	MFSPR(s, d)	gen(XO(31,339) | ((d)<<21) | ((s)<<11))
#define	MTSPR(s, d)	gen(XO(31,467) | ((s)<<21) | ((d)<<11));

#define	MFCR(d)		gen(XO(31,19) | ((d)<<21))
#define	MTCRF(s, mask)	gen(XO(31,144) | ((s)<<21) | ((mask)<<12))
#define	MTCR(s)		MTCRF(s, 0xff)

#define	SLWI(d,a,n)	gen(slw((d),(a),(n),0))
#define	LRET()	gen(Oblr)

#define	SETR0()	if(macjit){	AIRR(Oaddi, Rzero, 0, 0); }		/* set R0 to 0 */

/* assumes H can be formed from signed halfword */
#define	CMPH(r)		AIRR(Ocmpi, Rcrf0, (r), (ulong)H);
#define NOTNIL(r)	(CMPH((r)), CCALL(EQ, bounds))

enum
{
	Rzero	= 0,	/* zero by design, not definition (P9/Inferno) */

	Rsp = 1,
	Rsb = 2,
	Rarg	= 3,

	Ro1	= 8,
	Ro2	= 9,
	Ro3	= 10,
	Ri	= 11,
	Rj	= 12,

	Rmp	= 13,
	Rfp	= 14,
	Rreg	= 15,
	Rta	= 16,		/* unused */
	Rpic	= 17,		/* address for computed goto, for move to CTR or LR */

	Rcon = 26,	/* constant builder; temporary */
	/* 27, 28, 29, 30 are potentially external registers (P9/Inferno) */
	Rlink = 31,	/* holds copies of LR; linker temp */

	Rfret	= 0,
	Rf1	= 4,
	Rf2	= 6,
	Rfcvi	= 27,	/* floating conversion constant (P9/Inferno) */
	Rfzero = 28,	/* 0.0 (P9/Inferno) */
	Rfhalf = 29,	/* 0.5 (P9/Inferno) */

	Rlr = 8<<5,	/* SPR(LR) */
	Rctr = 9<<5,	/* SPR(CTR) */

	Rcrf0 = 0,		/* condition code field 0 */
	Rcrf1 = 1<<2,	/* condition code field 1 */

	Rcrbrel = 31,	/* condition code bit set to force relinquish */

	Olwz	= XO(32, 0),
	Olwzu = XO(33, 0),
	Olwzx = XO(31, 23),
	Olbz	= XO(34, 0),
	Olbzu = XO(35, 0),
	Olbzx = XO(31, 87),
	Olfd	= XO(50, 0),
	Olhz	= XO(40, 0),
	Olhzx = XO(31, 279),
	Ostw	= XO(36, 0),
	Ostwu = XO(37, 0),
	Ostwx = XO(31, 151),
	Ostb	= XO(38, 0),
	Ostbu = XO(39, 0),
	Ostbx = XO(31, 215),
	Osth	= XO(44,0),
	Osthx = XO(31, 407),
	Ostfd	= XO(54, 0),
	Ostfdu	= XO(55, 0),

	Oaddc	= XO(31,10),
	Oadde	= XO(31, 138),
	Oaddi	= XO(14, 0),	/* simm */
	Oaddic_	= XO(13, 0),
	Oaddis	= XO(15, 0),
	Ocrxor	= XO(19, 193),
	Ofadd	= XO(63, 21),
	Ofcmpo	= XO(63, 32),
	Ofctiwz	= XO(63, 15),
	Ofsub	= XO(63, 20),
	Ofmr	= XO(63, 72),
	Ofmul	= XO(63, 25),
	Ofdiv	= XO(63, 18),
	Ofneg	= XO(63, 40),
	Oori		= XO(24,0),	/* uimm */
	Ooris	= XO(25,0),	/* uimm */
	Odivw	= XO(31, 491),
	Odivwu	= XO(31, 459),
	Omulhw	= XO(31, 75),
	Omulhwu	= XO(31, 11),
	Omulli	= XO(7, 0),
	Omullw	= XO(31, 235),
	Osubf	= XO(31, 40),
	Osubfc	= XO(31,8),
	Osubfe	= XO(31,136),
	Osubfic	= XO(8, 0),
	Oadd	= XO(31, 266),
	Oand	= XO(31, 28),
	Oneg	= XO(31, 104),
	Oor		= XO(31, 444),
	Oxor		= XO(31, 316),

	Ocmpi = XO(11, 0),
	Ocmp = XO(31, 0),
	Ocmpl = XO(31, 32),
	Ocmpli = XO(10,0),

	Orlwinm = XO(21, 0),
	Oslw	= XO(31, 24),
	Osraw = XO(31,792),
	Osrawi =	XO(31,824),
	Osrw = XO(31,536),

	Cnone	= OPARRR(0,20,0,0),	/* unconditional */
	Ceq		= OPARRR(0,12,2,0),
	Cle		= OPARRR(0,4,1,0),
	Clt		= OPARRR(0,12,0,0),
	Cdnz	= OPARRR(0,16,0,0),
	Cgt		= OPARRR(0,12,1,0),
	Cne		= OPARRR(0,4,2,0),
	Cge		= OPARRR(0,4,0,0),
	Cle1		= OPARRR(0,4,5,0),	/* Cle on CR1 */
	Crelq	= OPARRR(0,12,Rcrbrel,0),	/* relinquish */
	Cnrelq	= OPARRR(0,4,Rcrbrel,0),	/* not relinquish */
	Cpredict	= OPARRR(0,1,0,0),	/* reverse prediction */
	Lk		= 1,
	Aa		= 2,

	Obeq	= OPARRR(16<<26,12,2,0),
	Obge	= OPARRR(16<<26,4,0,0),
	Obgt		= OPARRR(16<<26,12,1,0),
	Oble		= OPARRR(16<<26,4,1,0),
	Oblt		= OPARRR(16<<26,12,0,0),
	Obne	= OPARRR(16<<26,4,2,0),

	Ob		= XO(18, 0),
	Obc		= XO(16, 0),
	Obcctr	= XO(19,528),
	Obcctrl	= Obcctr | Lk,
	Obctr	= Obcctr | Cnone,
	Obctrl	= Obctr | Lk,
	Obclr	= XO(19, 16),
	Oblr		= Obclr | Cnone,
	Oblrl		= Oblr | Lk,

	Olea	= 100,		// pseudo op

	SRCOP	= (1<<0),
	DSTOP	= (1<<1),
	WRTPC	= (1<<2),	/* update R.PC */
	TCHECK	= (1<<3),	/* check R.t for continue/ret */
	NEWPC	= (1<<4),	/* goto R.PC */
	DBRAN	= (1<<5),	/* dest is branch */
	THREOP	= (1<<6),

	Lg2Rune	= sizeof(Rune)==4? 2: 1,
	ANDAND	= 1,
	OROR,
	EQAND,

	MacRET	= 0,
	MacFRP,
	MacCASE,
	MacFRAM,
	MacCOLR,
	MacMCAL,
	MacMFRA,
	MacCVTFW,
	MacRELQ,
	MacEND,
	NMACRO
};

	void	(*comvec)(void);
	int	macjit;
extern	long	das(ulong*);
static	ulong*	code;
static	ulong*	base;
static	ulong*	patch;
static	int	pass;
static	Module*	mod;
static	ulong*	tinit;
static	ulong*	litpool;
static	int	nlit;
static	ulong	macro[NMACRO];
static	void	ldbigc(long, int);
static	void	rdestroy(void);
static	void	macret(void);
static	void	macfrp(void);
static	void	maccase(void);
static	void	maccvtfw(void);
static	void	macfram(void);
static	void	maccolr(void);
static	void	macend(void);
static	void	macmcal(void);
static	void	macmfra(void);
static	void	macrelq(void);
static	void	movmem(Inst*);

struct
{
	int	o;
	void	(*f)(void);
} macinit[] =
{
	MacFRP,		macfrp,		/* decrement and free pointer */
	MacRET,		macret,		/* return instruction */
	MacCASE,	maccase,	/* case instruction */
	MacCOLR,	maccolr,	/* increment and color pointer */
	MacFRAM,	macfram,	/* frame instruction */
	MacMCAL,	macmcal,	/* mcall bottom half */
	MacMFRA,	macmfra,	/* punt mframe because t->initialize==0 */
	MacCVTFW,	maccvtfw,
	MacRELQ,		macrelq,	/* reschedule */
	MacEND,		macend,
	0
};

static void
rdestroy(void)
{
	destroy(R.s);
}

static void
rmcall(void)
{
	Frame *f;
	Prog *p;

	if((void*)R.dt == H)
		error(exModule);

	f = (Frame*)R.FP;
	if(f == H)
		error(exModule);

	f->mr = nil;
	((void(*)(Frame*))R.dt)(f);
	R.SP = (uchar*)f;
	R.FP = f->fp;
	if(f->t == nil)
		unextend(f);
	else
		freeptrs(f, f->t);
	p = currun();
	if(p->kill != nil)
		error(p->kill);
}

static void
rmfram(void)
{
	Type *t;
	Frame *f;
	uchar *nsp;

	t = (Type*)R.s;
	if(t == H)
		error(exModule);
	nsp = R.SP + t->size;
	if(nsp >= R.TS) {
		R.s = t;
		extend();
		T(d) = R.s;
		return;
	}
	f = (Frame*)R.SP;
	R.SP = nsp;
	f->t = t;
	f->mr = nil;
	initmem(t, f);
	T(d) = f;
}

void
urk(char *s)
{
	print("compile failed: %s\n", s);	// debugging
	error(exCompile);	// production
}

static void
gen(ulong o)
{
	*code++ = o;
}

static void
br(ulong op, ulong disp)
{
	*code++ = op | (disp & 0xfffc);
}

static void
mfspr(int d, int s)
{
	MFSPR(s, d);
}

static void
mtspr(int d, int s)
{
	MTSPR(s, d);
}

static ulong
slw(int d, int s, int v, int rshift)
{
	int m0, m1;

	if(v < 0 || v > 32)
		urk("slw v");
	if(v < 0)
		v = 0;
	else if(v > 32)
		v = 32;
	if(rshift) {	/* shift right */
		m0 = v;
		m1 = 31;
		v = 32-v;
	} else {
		m0 = 0;
		m1 = 31-v;
	}
	return RLW(Orlwinm, d, s, v, m0, m1);
}

static void
jr(int reg)
{
	mtspr(Rctr, reg);	/* code would be faster if this were loaded well before branch */
	gen(Obctr);
}

static void
jrl(int reg)
{
	mtspr(Rctr, reg);
	gen(Obctrl);
}

static void
jrc(int op, int reg)
{
	mtspr(Rctr, reg);
	gen(Obcctr | op);
}

static long
brdisp(ulong *dest)
{
	ulong d, top;

	d = (ulong)dest - (ulong)code;
	if(!ROMABLE)
		return d & 0x3fffffc;
	top = d>>25;
	if(top == 0 || top == 0x7F){
		/* fits in 26-bit signed displacement */
		return d & 0x3fffffc;
	}
	return -1;
}

static void
jmp(ulong *dest)
{
	long d;

	if((d = brdisp(dest)) < 0){
		ldbigc((ulong)dest, Rpic);	/* Rpic & Rctr must be free */
		jr(Rpic);
	} else
		gen(Ob | d);
}

static void
jmpl(ulong *dest)
{
	long d;

	if((d = brdisp(dest)) < 0){
		ldbigc((ulong)dest, Rpic);	/* Rpic must be free */
		jrl(Rpic);
	} else
		gen(Ob | d | Lk);
}

static void
jmpc(int op, ulong *dest)
{
	ldbigc((ulong)dest, Rpic);
	jrc(op, Rpic);
}

static int
bigc(long c)
{
	if(c >= -0x8000 && c <= 0x7FFF)
		return 0;
	return 1;
}

static void
ldbigc(long c, int reg)
{
	AIRR(Oaddis, reg,Rzero,c>>16);
	LIRR(Oori, reg,reg,c);
}

static void
ldc(long c, int reg)
{
	if(!bigc(c))
		AIRR(Oaddi, reg, Rzero, c);
	else if((ulong)c <= 0xFFFF)
		LIRR(Oori, reg, Rzero, c);
	else if((c&0xFFFF) == 0)
		LIRR(Ooris, reg, Rzero, c>>16);
	else {
		AIRR(Oaddis, reg,Rzero,c>>16);
		LIRR(Oori, reg,reg,c);
	}
}

static void
mem(int inst, long disp, int rm, int r)
{
	if(bigc(disp)) {
		ldc(disp, Rcon);
		switch(inst){
		default: 		urk("mem op"); break;
		case Olea:		inst = Oadd; break;
		case Olwz:	inst = Olwzx; break;
		case Olbz:		inst = Olbzx; break;
		case Olhz:		inst = Olhzx; break;
		case Ostw:	inst = Ostwx; break;
		case Ostb:		inst = Ostbx; break;
		case Osth:		inst = Osthx; break;
		}
		ARRR(inst, r, Rcon, rm);
	} else {
		if(inst == Olea)
			inst = Oaddi;
		AIRR(inst, r, rm,disp);
	}
}

static void
opx(int mode, Adr *a, int op, int reg)
{
	ulong c;
	int r, rx, lea;

	lea = 0;
	if(op == Olea){
		lea = 1;
		op = Oaddi;
	}
	switch(mode) {
	case AFP:
		c = a->ind;
		if(bigc(c))
			urk("bigc op1b 1");
		AIRR(op, reg, Rfp,c);
		break;
	case AMP:
		c = a->ind;
		if(bigc(c))
			urk("bigc op1b 2");
		AIRR(op, reg, Rmp,c);
		break;
	case AIMM:
		if(lea) {
			if(a->imm != 0) {
				ldc(a->imm, reg);
				AIRR(Ostw, reg, Rreg,O(REG,st));
			} else
				AIRR(Ostw, Rzero, Rreg,O(REG,st));
			AIRR(Oaddi, reg, Rreg,O(REG,st));
		} else
			ldc(a->imm, reg);
		return;
	case AIND|AFP:
		r = Rfp;
		goto offset;
	case AIND|AMP:
		r = Rmp;
	offset:
		c = a->i.s;
		rx = Ri;
		if(lea || op == Olwz)
			rx = reg;
		AIRR(Olwz, rx, r,a->i.f);
		if(!lea || c != 0)
			AIRR(op, reg, rx,c);
		break;
	}
}

static void
opwld(Inst *i, int op, int reg)
{
	opx(USRC(i->add), &i->s, op, reg);
}

static void
opwst(Inst *i, int op, int reg)
{
	opx(UDST(i->add), &i->d, op, reg);
}

static void
op2(Inst *i, int op, int reg)
{
	int lea;

	lea = 0;
	if(op == Olea){
		op = Oaddi;
		lea = 1;
	}
	switch(i->add & ARM) {
	case AXNON:
		if(lea)
			op = Olea;
		opwst(i, op, reg);
		return;
	case AXIMM:
		if(lea)
			urk("op2/lea");
		ldc((short)i->reg, reg);
		return;
	case AXINF:
		IRR(op, i->reg,Rfp, reg);
		break;
	case AXINM:
		IRR(op, i->reg,Rmp, reg);
		break;
	}
}

static void
op12(Inst *i, int b1flag, int b2flag)
{
	int o1, o2;

	o1 = Olwz;
	if(b1flag)
		o1 = Olbz;
	o2 = Olwz;
	if(b2flag)
		o2 = Olbz;
	if((i->add & ARM) == AXIMM) {
		opwld(i, o1, Ro1);
		op2(i, o2, Ro2);
	} else {
		op2(i, o2, Ro2);
		opwld(i, o1, Ro1);
	}
}

static void
op13(Inst *i, int o1, int o2)
{
	opwld(i, o1, Ro1);
	opwst(i, o2, Ro1);
}

static ulong
branch(Inst *i)
{
	ulong rel;

	if(base == 0)
		return 0;
	rel = (ulong)(base+patch[i->d.ins - mod->prog]);
	rel -= (ulong)code;
	if(rel & 3 || (long)rel <= -(1<<16) || (long)rel >= 1<<16)
		urk("branch off");
	return rel & 0xfffc;
}

static void
schedcheck(Inst *i)
{
	ulong *cp;

	if(i != nil && i->d.ins != nil && i->d.ins > i)
		return;	/* only backwards jumps can loop: needn't check forward ones */
	cp = code;
	gen(Obc | Cnrelq | Cpredict);
	jmpl(base+macro[MacRELQ]);
	PATCH(cp);
}

static void
literal(ulong imm, int roff)
{
	nlit++;

	ldbigc((ulong)litpool, Ro1);
	IRR(Ostw, roff, Rreg, Ro1);

	if(pass == 0)
		return;

	*litpool = imm;
	litpool++;	
}

static void
bounds(void)
{
	/* mem(Ostw, O(REG,FP), Rreg, Rfp); */
	error(exBounds);
}

static void
punt(Inst *i, int m, void (*fn)(void))
{
	ulong pc;

	if(m & SRCOP) {
		if(UXSRC(i->add) == SRC(AIMM))
			literal(i->s.imm, O(REG, s));
		else {
			opwld(i, Olea, Ro1);
			mem(Ostw, O(REG, s), Rreg, Ro1);
		}
	}
	if(m & DSTOP) {
		opwst(i, Olea, Ro3);
		IRR(Ostw, O(REG,d),Rreg, Ro3);
	}
	if(m & WRTPC) {
		pc = patch[i-mod->prog+1];
		ldbigc((ulong)(base+pc), Ro1);
		IRR(Ostw, O(REG,PC),Rreg, Ro1);
	}
	if(m & DBRAN) {
		pc = patch[i->d.ins-mod->prog];
		literal((ulong)(base+pc), O(REG, d));
	}

	switch(i->add&ARM) {
	case AXNON:
		if(m & THREOP) {
			IRR(Olwz, O(REG,d),Rreg, Ro2);
			IRR(Ostw, O(REG,m),Rreg, Ro2);
		}
		break;
	case AXIMM:
		literal((short)i->reg, O(REG,m));
		break;
	case AXINF:
		mem(Olea, i->reg, Rfp, Ro2);
		mem(Ostw, O(REG, m), Rreg, Ro2);
		break;
	case AXINM:
		mem(Olea, i->reg, Rmp, Ro2);
		mem(Ostw, O(REG, m), Rreg, Ro2);
		break;
	}
	IRR(Ostw, O(REG,FP),Rreg, Rfp);

	jmpl((ulong*)fn);

	ldc((ulong)&R, Rreg);
	SETR0();
	if(m & TCHECK) {
		IRR(Olwz, O(REG,t),Rreg, Ro1);
		IRR(Olwz, O(REG,xpc),Rreg, Ro2);
		IRR(Ocmpi, 0, Ro1, Rcrf0);
		mtspr(Rctr, Ro2);
		gen(Obcctr | Cne);
	}
	IRR(Olwz, O(REG,FP),Rreg, Rfp);
	IRR(Olwz, O(REG,MP),Rreg, Rmp);

	if(m & NEWPC) {
		IRR(Olwz, O(REG,PC),Rreg, Ro1);
		jr(Ro1);
	}
}
				
static void
comgoto(Inst *i)
{
	WORD *t, *e;

	opwld(i, Olwz, Ro2);
	opwst(i, Olea, Ro3);
	SLWI(Ro2, Ro2, 2);
	ARRR(Olwzx, Ro1, Ro3,Ro2);
	jr(Ro1);

	if(pass == 0)
		return;

	t = (WORD*)(mod->origmp+i->d.ind);
	e = t + t[-1];
	t[-1] = 0;
	while(t < e) {
		t[0] = (ulong)(base + patch[t[0]]);
		t++;
	}
}

static void
comcase(Inst *i, int w)
{
	int l;
	WORD *t, *e;

	if(w != 0) {
		opwld(i, Olwz, Ro1);		// v
		opwst(i, Olea, Ro3);		// table
		jmp(base+macro[MacCASE]);
	}

	t = (WORD*)(mod->origmp+i->d.ind+4);
	l = t[-1];
	
	/* have to take care not to relocate the same table twice - 
	 * the limbo compiler can duplicate a case instruction
	 * during its folding phase
	 */

	if(pass == 0) {
		if(l >= 0)
			t[-1] = -l-1;	/* Mark it not done */
		return;
	}
	if(l >= 0)			/* Check pass 2 done */
		return;
	t[-1] = -l-1;			/* Set real count */
	e = t + t[-1]*3;
	while(t < e) {
		t[2] = (ulong)(base + patch[t[2]]);
		t += 3;
	}
	t[0] = (ulong)(base + patch[t[0]]);
}

static void
comcasel(Inst *i)
{
	int l;
	WORD *t, *e;

	t = (WORD*)(mod->origmp+i->d.ind+8);
	l = t[-2];
	if(pass == 0) {
		if(l >= 0)
			t[-2] = -l-1;	/* Mark it not done */
		return;
	}
	if(l >= 0)			/* Check pass 2 done */
		return;
	t[-2] = -l-1;			/* Set real count */
	e = t + t[-2]*6;
	while(t < e) {
		t[4] = (ulong)base + patch[t[4]];
		t += 6;
	}
	t[0] = (ulong)base + patch[t[0]];
}

static void
commframe(Inst *i)
{
	ulong *cp1, *cp2;

	opwld(i, Olwz, Ri);	// must use Ri for MacFRAM
	CMPH(Ri);
	cp1 = code;
	br(Obeq, 0);

	if((i->add&ARM) == AXIMM) {
		mem(Olwz, OA(Modlink, links)+i->reg*sizeof(Modl)+O(Modl, frame), Ri, Ri);
	} else {
		op2(i, Olwz, Ro2);
		SLWI(Ro2, Ro2, 3);	// assumes sizeof(Modl) == 8
		ARRR(Oadd, Ri, Ro2, Ro2);
		mem(Olwz, OA(Modlink, links)+O(Modl, frame), Ri, Ri);
	}

	AIRR(Olwz, Ro2, Ri,O(Type,initialize));
	AIRR(Ocmpi, Rcrf0, Ro2, 0);
	cp2 = code;
	br(Obne, 0);

	opwst(i, Olea, Rj);

	PATCH(cp1);
	ldbigc((ulong)(base+patch[i-mod->prog+1]), Rpic);
	mtspr(Rlr, Rpic);
	jmp(base+macro[MacMFRA]);

	PATCH(cp2);
	jmpl(base+macro[MacFRAM]);
	opwst(i, Ostw, Ro1);
}

static void
commcall(Inst *i)
{
	opwld(i, Olwz, Ro1);				// f in Ro1
	AIRR(Olwz, Ro3, Rreg,O(REG,M));
	AIRR(Ostw, Rfp, Ro1,O(Frame,fp));			// f->fp = R.FP
	AIRR(Ostw, Ro3, Ro1,O(Frame,mr));			// f->mr = R.M
	opwst(i, Olwz, Ri);
	if((i->add&ARM) == AXIMM) {
		mem(Olwz, OA(Modlink, links)+i->reg*sizeof(Modl)+O(Modl, u.pc), Ri, Rj);	// ml->entry in Rj
	} else {
		op2(i, Olwz, Rj);
		SLWI(Rj, Rj, 3);	// assumes sizeof(Modl) == 8
		ARRR(Oadd, Ri, Rj, Rj);
		mem(Olwz, OA(Modlink, links)+O(Modl, u.pc), Rj, Rj);
	}
	jmpl(base+macro[MacMCAL]);
}

static int
swapbraop(int b)
{
	switch(b) {
	case Obge:
		return Oble;
	case Oble:
		return Obge;
	case Obgt:
		return Oblt;
	case Oblt:
		return Obgt;
	}
	return b;
}

static void
cbra(Inst *i, int op)
{
	if(RESCHED)
		schedcheck(i);
	if(UXSRC(i->add) == SRC(AIMM) && !bigc(i->s.imm)) {
		op2(i, Olwz, Ro1);
		AIRR(Ocmpi, Rcrf0, Ro1, i->s.imm);
		op = swapbraop(op);
	} else if((i->add & ARM) == AXIMM) {
		opwld(i, Olwz, Ro1);
		AIRR(Ocmpi, Rcrf0, Ro1, i->reg);
	} else {
		op12(i, 0, 0);
		ARRR(Ocmp, Rcrf0, Ro1, Ro2);
	}
	br(op, branch(i));
}

static void
cbrab(Inst *i, int op)
{
	if(RESCHED)
		schedcheck(i);
	if(UXSRC(i->add) == SRC(AIMM)) {
		op2(i, Olbz, Ro1);
		AIRR(Ocmpi, Rcrf0, Ro1, i->s.imm&0xFF);
		op = swapbraop(op);
	} else if((i->add & ARM) == AXIMM) {
		opwld(i, Olbz, Ro1);
		AIRR(Ocmpi, Rcrf0, Ro1, i->reg&0xFF);	// mask i->reg?
	} else {
		op12(i, 1, 1);
		ARRR(Ocmp, Rcrf0, Ro1, Ro2);
	}
	br(op, branch(i));
}

static void
cbraf(Inst *i, int op)
{
	if(RESCHED)
		schedcheck(i);
	opwld(i, Olfd, Rf1);
	op2(i, Olfd, Rf2);
	ARRR(Ofcmpo, Rcrf0, Rf1, Rf2);
	br(op, branch(i));
}

static void
cbral(Inst *i, int cms, int cls, int mode)
{
	ulong *cp;

	if(RESCHED)
		schedcheck(i);
	cp = nil;
	opwld(i, Olea, Ri);
	op2(i, Olea, Rj);
	IRR(Olwz, 0,Ri, Ro1);
	IRR(Olwz, 0,Rj, Ro2);
	ARRR(Ocmp, Rcrf0, Ro1, Ro2);
	switch(mode) {
	case ANDAND:
		cp = code;
		br(cms, 0);
		break;
	case OROR:
		br(cms, branch(i));
		break;
	case EQAND:
		br(cms, branch(i));
		cp = code;
		br(Obne, 0);
		break;
	}
	IRR(Olwz, 4,Ri, Ro1);
	IRR(Olwz, 4,Rj, Ro2);
	ARRR(Ocmpl, Rcrf0, Ro1, Ro2);
	br(cls, branch(i));
	if(cp)
		PATCH(cp);
}

static void
shrl(Inst *i)
{
//	int c;

//	if(USRC(i->add) != AIMM) {
		punt(i, SRCOP|DSTOP|THREOP, optab[i->op]);
		return;
//	}
/*
	c = i->s.imm;
	op2(i, Olea, Ro3);
	IRR(Olwz, 0,Ro3, Ro1);
	if(c >= 32) {
		if((i->add&ARM) != AXNON)
			opwst(i, Olea, Ro3);
		SRR(Osra, 31, Ro1, Ro2);
		IRR(Ostw, 0,Ro3, Ro2);
		if(c >= 64) {
			IRR(Ostw, 4,Ro3, Ro2);
			return;
		}
		if(c > 32)
			SRR(Osra, c-32, Ro1, Ro1);
		IRR(Ostw, 4,Ro3, Ro1);
		return;
	}
	IRR(Olwz, 4,Ro3, Ro2);
	if((i->add&ARM) != AXNON)
		opwst(i, Olea, Ro3);
	if(c != 0) {
		SRR(Osll, 32-c, Ro1, Ri);
		SRR(Osra, c, Ro1, Ro1);
		SRR(Osrl, c, Ro2, Ro2);
		RRR(Oor, Ri, Ro2, Ro2);
	}
	IRR(Ostw, 4,Ro3, Ro2);
	IRR(Ostw, 0,Ro3, Ro1);
*/
}

static void
shll(Inst *i)
{
//	int c;

//	if(USRC(i->add) != AIMM) {
		punt(i, SRCOP|DSTOP|THREOP, optab[i->op]);
		return;
//	}
/*
	c = i->s.imm;
	if(c >= 64) {
		opwst(i, Olea, Ro3);
		IRR(Ostw, 0,Ro3, Rzero);
		IRR(Ostw, 4,Ro3, Rzero);
		return;
	}
	op2(i, Olea, Ro3);
	if(c >= 32) {
		IRR(Olwz, 4,Ro3, Ro1);
		if((i->add&ARM) != AXNON)
			opwst(i, Olea, Ro3);
		IRR(Ostw, 4,Ro3, Rzero);
		if(c > 32)
			SRR(Osll, c-32, Ro1, Ro1);
		IRR(Ostw, 0,Ro3, Ro1);
		return;
	}
	IRR(Olwz, 4,Ro3, Ro2);
	IRR(Olwz, 0,Ro3, Ro1);
	if((i->add&ARM) != AXNON)
		opwst(i, Olea, Ro3);
	if(c != 0) {
		SRR(Osrl, 32-c, Ro2, Ri);
		SRR(Osll, c, Ro2, Ro2);
		SRR(Osll, c, Ro1, Ro1);
		RRR(Oor, Ri, Ro1, Ro1);
	}
	IRR(Ostw, 4,Ro3, Ro2);
	IRR(Ostw, 0,Ro3, Ro1);
*/
}

static void
compdbg(void)
{
	print("%s:%lud@%.8lux\n", R.M->m->name, *(ulong*)R.m, *(ulong*)R.s);
}

static void
comp(Inst *i)
{
	int o, q, b;
	ulong *cp, *cp1;
	char buf[64];

	if(0) {
		Inst xx;
		xx.add = AXIMM|SRC(AIMM);
		xx.s.imm = (ulong)code;
		xx.reg = i-mod->prog;
		punt(&xx, SRCOP, compdbg);
	}

	switch(i->op) {
	default:
		snprint(buf, sizeof buf, "%s compile, no '%D'", mod->name, i);
		error(buf);
		break;
	case IMCALL:
		if((i->add&ARM) == AXIMM)
			commcall(i);
		else
			punt(i, SRCOP|DSTOP|THREOP|WRTPC|NEWPC, optab[i->op]);
		break;
	case ISEND:
	case IRECV:
	case IALT:
		punt(i, SRCOP|DSTOP|TCHECK|WRTPC, optab[i->op]);
		break;
	case ISPAWN:
		punt(i, SRCOP|DBRAN, optab[i->op]);
		break;
	case IBNEC:
	case IBEQC:
	case IBLTC:
	case IBLEC:
	case IBGTC:
	case IBGEC:
		punt(i, SRCOP|DBRAN|NEWPC|WRTPC, optab[i->op]);
		break;
	case ICASEC:
		comcase(i, 0);
		punt(i, SRCOP|DSTOP|NEWPC, optab[i->op]);
		break;
	case ICASEL:
		comcasel(i);
		punt(i, SRCOP|DSTOP|NEWPC, optab[i->op]);
		break;
	case IADDC:
	case IMULL:
	case IDIVL:
	case IMODL:
	case IMNEWZ:
	case ILSRW:
	case ILSRL:
		punt(i, SRCOP|DSTOP|THREOP, optab[i->op]);
		break;
	case IMFRAME:
		if((i->add&ARM) == AXIMM)
			commframe(i);
		else
			punt(i, SRCOP|DSTOP|THREOP, optab[i->op]);
		break;
	case ILOAD:
	case INEWA:
	case INEWAZ:
	case INEW:
	case INEWZ:
	case ISLICEA:
	case ISLICELA:
	case ICONSB:
	case ICONSW:
	case ICONSL:
	case ICONSF:
	case ICONSM:
	case ICONSMP:
	case ICONSP:
	case IMOVMP:
	case IHEADMP:
	case IINSC:
	case ICVTAC:
	case ICVTCW:
	case ICVTWC:
	case ICVTCL:
	case ICVTLC:
	case ICVTFC:
	case ICVTCF:
	case ICVTFL:
	case ICVTLF:
	case ICVTRF:
	case ICVTFR:
	case ICVTWS:
	case ICVTSW:
	case IMSPAWN:
	case ICVTCA:
	case ISLICEC:
	case INBALT:
		punt(i, SRCOP|DSTOP, optab[i->op]);
		break;
	case INEWCM:
	case INEWCMP:
		punt(i, SRCOP|DSTOP|THREOP, optab[i->op]);
		break;
	case INEWCB:
	case INEWCW:
	case INEWCF:
	case INEWCP:
	case INEWCL:
		punt(i, DSTOP|THREOP, optab[i->op]);
		break;
	case IEXIT:
		punt(i, 0, optab[i->op]);
		break;
	case ICVTWB:
		op13(i, Olwz, Ostb);
		break;
	case ICVTBW:
		op13(i, Olbz, Ostw);
		break;
	case IMOVB:
		if(USRC(i->add) == AIMM && i->s.imm == 0) {
			opwst(i, Ostb, Rzero);
			break;
		}
		op13(i, Olbz, Ostb);
		break;
	case IMOVW:
		if(USRC(i->add) == AIMM && i->s.imm == 0) {
			opwst(i, Ostw, Rzero);
			break;
		}
		op13(i, Olwz, Ostw);
		break;
	case ICVTLW:
		opwld(i, Olea, Ro1);
		AIRR(Olwz, Ro2, Ro1,4);
		opwst(i, Ostw, Ro2);
		break;
	case ICVTWL:
		opwld(i, Olwz, Ro1);
		opwst(i, Olea, Ro2);
		LRRR(Osrawi, Ro3, Ro1, 31);
		AIRR(Ostw, Ro1, Ro2,4);
		AIRR(Ostw, Ro3, Ro2,0);
		break;
	case IHEADM:
		opwld(i, Olwz, Ro1);
		AIRR(Oaddi, Ro1, Ro1,OA(List,data));
		movmem(i);
		break;
	case IMOVM:
		opwld(i, Olea, Ro1);
		movmem(i);
		break;
	case IRET:
		jmp(base+macro[MacRET]);
		break;
	case IFRAME:
		if(UXSRC(i->add) != SRC(AIMM)) {
			punt(i, SRCOP|DSTOP, optab[i->op]);
			break;
		}
		tinit[i->s.imm] = 1;
		ldc((ulong)mod->type[i->s.imm], Ri);
		jmpl(base+macro[MacFRAM]);
		opwst(i, Ostw, Ro1);
		break;
	case ILEA:
		op13(i, Olea, Ostw);
		break;
	case IHEADW:
		opwld(i, Olwz, Ro1);
		AIRR(Olwz, Ro1, Ro1,OA(List,data));
		opwst(i, Ostw, Ro1);
		break;
	case IHEADF:
		opwld(i, Olwz, Ro1);
		AIRR(Olfd, Rf1, Ro1,OA(List,data));
		opwst(i, Ostfd, Rf1);
		break;
	case IHEADB:
		opwld(i, Olwz, Ro1);
		AIRR(Olbz, Ro1, Ro1,OA(List,data));
		opwst(i, Ostb, Ro1);
		break;
	case ITAIL:
		opwld(i, Olwz, Ro1);
		AIRR(Olwz, Ro1, Ro1,O(List,tail));
		goto movp;
	case IMOVP:
		opwld(i, Olwz, Ro1);
		goto movp;
	case IHEADP:
		opwld(i, Olwz, Ro1);
		AIRR(Olwz, Ro1, Ro1,OA(List,data));
	movp:
		CMPH(Ro1);
		cp = code;
		br(Obeq, 0);
		jmpl(base+macro[MacCOLR]);
		PATCH(cp);
		opwst(i, Olea, Ro3);
		AIRR(Olwz, Ri, Ro3,0);
		AIRR(Ostw, Ro1, Ro3,0);
		jmpl(base+macro[MacFRP]);
		break;
	case ILENA:
		opwld(i, Olwz, Ri);
		ldc(0, Ro1);
		CMPH(Ri);
		cp = code;
		br(Obeq, 0);
		AIRR(Olwz, Ro1, Ri,O(Array,len));
		PATCH(cp);
		opwst(i, Ostw, Ro1);
		break;
	case ILENC:
		opwld(i, Olwz, Ri);
		ldc(0, Ro1);
		CMPH(Ri);
		cp = code;
		br(Obeq, 0);
		AIRR(Olwz, Ro1, Ri,O(String,len));
		AIRR(Ocmpi, Rcrf0, Ro1, 0);
		br(Obge, 2*4);	// BGE 2(PC); skip
		ARRR(Oneg, Ro1, Ro1, 0);
		PATCH(cp);
		opwst(i, Ostw, Ro1);
		break;
	case ILENL:
		opwld(i, Olwz, Ro1);
		ldc(0, Ro3);
		CMPH(Ro1);
		cp = code;
		br(Obeq, 0);

		cp1 = code;
		AIRR(Olwz, Ro1, Ro1,O(List,tail));
		AIRR(Oaddi, Ro3, Ro3, 1);
		CMPH(Ro1);
		br(Obne, ((ulong)cp1-(ulong)code));

		PATCH(cp);
		opwst(i, Ostw, Ro3);
		break;
	case IMOVL:
		opwld(i, Olea, Ro1);
		AIRR(Olwz, Ro2, Ro1,0);
		AIRR(Olwz, Ro3, Ro1,4);
		opwst(i, Olea, Ro1);
		AIRR(Ostw, Ro2, Ro1,0);
		AIRR(Ostw, Ro3, Ro1,4);
		break;
	case IMOVF:
		opwld(i, Olfd, Rf1);
		opwst(i, Ostfd, Rf1);
		break;
	case ICVTFW:
		if(!macjit){
			opwld(i, Olfd, Rf1);
			jmpl(base+macro[MacCVTFW]);
			opwst(i, Ostw, Ro1);
			break;
		}
	case ICVTWF:
		punt(i, SRCOP|DSTOP, optab[i->op]);
		break;
	case INEGF:
		opwld(i, Olfd, Rf1);
		ARRR(Ofneg, Rf2, 0, Rf1);
		opwst(i, Ostfd, Rf2);
		break;
	case IXORL:
	case IORL:
	case IANDL:
	case IADDL:
	case ISUBL:
		opwld(i, Olea, Ro1);
		op2(i, Olea, Ro3);

		AIRR(Olwz, Rj, Ro1,4);	/* ls */
		AIRR(Olwz, Ro2, Ro3,4);
		AIRR(Olwz, Ri, Ro1,0);	/* ms */
		AIRR(Olwz, Ro1, Ro3,0);

		switch(i->op) {
		case IXORL:
			o = Oxor;
			goto l1;
		case IORL:
			o = Oor;
			goto l1;
		case IANDL:
			o = Oand;
		l1:
			LRRR(o, Ro1, Ri, Ro1);
			LRRR(o, Ro2, Rj, Ro2);
			break;
		case IADDL:
			RRR(Oaddc, Rj,Ro2, Ro2);
			RRR(Oadde, Ri,Ro1, Ro1);
			break;
		case ISUBL:
			RRR(Osubfc, Ro2,Rj, Ro2);
			RRR(Osubfe, Ro1,Ri, Ro1);
			break;
		}
		if((i->add&ARM) != AXNON)
			opwst(i, Olea, Ro3);
		IRR(Ostw, 0,Ro3, Ro1);
		IRR(Ostw, 4,Ro3, Ro2);
		break;
	case ISHLL:
		shll(i);
		break;
	case ISHRL:
		shrl(i);
		break;
	case IADDF:	o = Ofadd; goto f1;
	case ISUBF:	o = Ofsub; goto f1;
	case IMULF:	o = Ofmul; goto f1;
	case IDIVF:	o = Ofdiv; goto f1;
	f1:
		opwld(i, Olfd, Rf1);
		op2(i, Olfd, Rf2);
		if(o == Ofmul)
			gen(o | (Rf2<<21) | (Rf2<<16) | (Rf1<<6));	/* odd one out: op D,A,-,C */
		else
			ARRR(o, Rf2, Rf2, Rf1);
		opwst(i, Ostfd, Rf2);
		break;

	case IBEQF:
		cbraf(i, Obeq);
		break;
	case IBGEF:
		cbraf(i, Obge);
	case IBGTF:
		cbraf(i, Obgt);
		break;
	case IBLEF:
		cbraf(i, Oble);
		break;
	case IBLTF:
		cbraf(i, Oblt);
		break;
	case IBNEF:
		cbraf(i, Obne);
		break;

	case IBLTB:
		cbrab(i, Oblt);
		break;
	case IBLEB:
		cbrab(i, Oble);
		break;
	case IBGTB:
		cbrab(i, Obgt);
		break;
	case IBGEB:
		cbrab(i, Obge);
		break;
	case IBEQB:
		cbrab(i, Obeq);
		break;
	case IBNEB:
		cbrab(i, Obne);
		break;

	case IBLTW:
		cbra(i, Oblt);
		break;
	case IBLEW:
		cbra(i, Oble);
		break;
	case IBGTW:
		cbra(i, Obgt);
		break;
	case IBGEW:
		cbra(i, Obge);
		break;
	case IBEQW:
		cbra(i, Obeq);
		break;
	case IBNEW:
		cbra(i, Obne);
		break;

	case IBEQL:
		cbral(i, Obne, Obeq, ANDAND);
		break;
	case IBNEL:
		cbral(i, Obne, Obne, OROR);
		break;
	case IBLTL:
		cbral(i, Oblt, Oblt, EQAND);
		break;
	case IBLEL:
		cbral(i, Oblt, Oble, EQAND);
		break;
	case IBGTL:
		cbral(i, Obgt, Obgt, EQAND);
		break;
	case IBGEL:
		cbral(i, Obgt, Obge, EQAND);
		break;

	case ISUBB:
	case IADDB:
	case IANDB:
	case IORB:
	case IXORB:
	case IMODB:
	case IDIVB:
	case IMULB:
		b = 1;
		op12(i, b, b);
		goto s2;
	case ISHLB:
	case ISHRB:
		b = 1;
		op12(i, 0, b);
		goto s2;
	case ISUBW:
	case IADDW:
	case IANDW:
	case IORW:
	case IXORW:
	case ISHLW:
	case ISHRW:
	case IMODW:
	case IDIVW:
	case IMULW:
		b = 0;
		op12(i, b, b);
	s2:
		q = 0;
		switch(i->op) {
		case ISUBB:
		case ISUBW:	o = Osubf; q = Osubfic;
			// TO DO: if immediate operand, should use opcode q
			USED(q);
			ARRR(o, Ro3, Ro1, Ro2);
			break;
		case IADDB:
		case IADDW:	o = Oadd; q = Oaddi; goto c1;
		case IMULB:
		case IMULW:	o = Omullw; q = Omulli; goto c1;
		case IDIVB:
		case IDIVW:	o = Odivw; goto c1;
		c1:
			// TO DO: if immediate operand, should use opcode q
			USED(q);
			ARRR(o, Ro3, Ro2, Ro1);
			break;
		case IANDB:
		case IANDW:	o = Oand; goto c2;
		case IORB:
		case IORW:	o = Oor; goto c2;
		case IXORB:
		case IXORW:	o = Oxor; goto c2;
		case ISHLB:
		case ISHLW:	o = Oslw; goto c2;
		case ISHRB:
		case ISHRW:	o = Osraw; goto c2;
		c2:
			LRRR(o, Ro3,Ro2,Ro1);
			break;
		case IMODB:
		case IMODW:
			ARRR(Odivw, Ro3, Ro2, Ro1);
			ARRR(Omullw, Ro3, Ro3, Ro1);
			ARRR(Osubf, Ro3, Ro3, Ro2);
			break;
		}
		opwst(i, b? Ostb: Ostw, Ro3);
		break;
	case ICALL:
		opwld(i, Olwz, Ro1);	/* f = T(s) */
		ldbigc((ulong)(base+patch[i-mod->prog+1]), Ro2);	/* R.pc */
		AIRR(Ostw, Rfp, Ro1,O(Frame,fp));	/* f->fp = R.fp */
		AIRR(Ostw, Ro2, Ro1,O(Frame,lr));	/* f->lr = R.pc */
		AIRR(Oaddi, Rfp, Ro1, 0);	/* R.fp = (uchar*)f */
		jmp(base+patch[i->d.ins - mod->prog]);
		break;
	case IJMP:
		if(RESCHED)
			schedcheck(i);
		jmp(base+patch[i->d.ins - mod->prog]);
		break;
	case IGOTO:
		comgoto(i);
		break;
	case IINDC:
		opwld(i, Olwz, Ro1);			// Ro1 = string
		if((i->add&ARM) != AXIMM)
			op2(i, Olwz, Ro2);			// Ro2 = i
		AIRR(Olwz, Ri, Ro1,O(String,len));	// len<0 => index Runes, otherwise bytes
		AIRR(Oaddi, Ro1, Ro1,O(String,data));
		AIRR(Ocmpi, Rcrf0, Ri, 0);
		if(bflag){
			br(Obge, 2*4);
			ARRR(Oneg, Ri, Ri, 0);
			if((i->add&ARM) != AXIMM)
				ARRR(Ocmpl, Rcrf1, Ri, Ro2);		/* CMPU len, i */
			else
				AIRR(Ocmpli, Rcrf1, Ri, i->reg);	/* CMPU len, i */
			jmpc(Cle1, (ulong*)bounds);
		}
		cp = code;
		br(Obge, 0);
		if((i->add&ARM) != AXIMM){
			SLWI(Ro2, Ro2, Lg2Rune);
			if(sizeof(Rune) == 4)
				ARRR(Olwz, Ro3, Ro1, Ro2);
			else
				ARRR(Olhzx, Ro3, Ro1, Ro2);
		} else
			mem(Olwz, (short)i->reg<<Lg2Rune, Ro1, Ro3);	/* BUG: TO DO: 16-bit signed displacement */
		gen(Ob | (2*4));	// skip
		PATCH(cp);
		if((i->add&ARM) != AXIMM)
			ARRR(Olbzx, Ro3, Ro1, Ro2);
		else
			AIRR(Olbz, Ro3, Ro1,i->reg);
		opwst(i, Ostw, Ro3);
		break;
	case IINDX:
	case IINDB:
	case IINDF:
	case IINDW:
	case IINDL:
		opwld(i, Olwz, Ro1);			/* Ro1 = a */
		opwst(i, Olwz, Ro3);			/* Ro3 = i */
		if(bflag){
			AIRR(Olwz, Ro2, Ro1, O(Array, len));		/* Ro2 = a->len */
			ARRR(Ocmpl, Rcrf0, Ro3, Ro2);			/* CMPU i, len */
			jmpc(Cge, (ulong*)bounds);
		}
		// TO DO: check a != H
		AIRR(Olwz, Ro2, Ro1,O(Array,data));	/* Ro2 = a->data */
		switch(i->op) {
		case IINDX:
			AIRR(Olwz, Ri, Ro1,O(Array,t));			// Ri = a->t
			AIRR(Olwz, Ro1, Ri,O(Type,size));		// Ro1 = a->t->size
			ARRR(Omullw, Ro3, Ro3, Ro1);			// Ro3 = i*size
			break;
		case IINDL:
		case IINDF:
			SLWI(Ro3, Ro3, 3);		/* Ro3 = i*8 */
			break;
		case IINDW:
			SLWI(Ro3, Ro3, 2);		/* Ro3 = i*4 */
			break;
		case IINDB:
			/* no further work */
			break;
		}
		ARRR(Oadd, Ro2, Ro2, Ro3);		/* Ro2 = i*size + data */
		op2(i, Ostw, Ro2);
		break;
	case ICASE:
		comcase(i, 1);
		break;
	case IRAISE:
		punt(i, SRCOP|WRTPC|NEWPC, optab[i->op]);
		break;
	case IMULX:
	case IDIVX:
	case ICVTXX:
	case IMULX0:
	case IDIVX0:
	case ICVTXX0:
	case IMULX1:
	case IDIVX1:
	case ICVTXX1:
	case ICVTFX:
	case ICVTXF:
	case IEXPW:
	case IEXPL:
	case IEXPF:
		punt(i, SRCOP|DSTOP|THREOP, optab[i->op]);
		break;
	case ISELF:
		punt(i, DSTOP, optab[i->op]);
		break;
	}
}

enum {
	PREFLEN = 64,	/* max instruction words in comvec */
};

static void
preamble(void)
{
	ulong *s;

	if(comvec != nil)
		return;
	s = code = malloc(PREFLEN*sizeof(*code));
	if(s == nil)
		error(exNomem);

#ifdef __ELF__
	if(macjit) {
		ulong *cp;
		int r;

		/*
		 * ELF frame:
		 *  0(%sp) - back chain
		 *  4(%sp) - callee's LR save slot
		 *  8(%sp) to 36(%sp) - 8 words of parameter list area
		 * 40(%sp) to 48(%sp) - pad to 16 byte alignment/local vars
		 */
		mfspr(Ro1, Rlr);
		AIRR(Ostw, Ro1, Rsp,4);
		AIRR(Ostwu, Rsp, Rsp,-128);

		MFCR(Ro1);
		AIRR(Ostw, Ro1, Rsp,52);
		for (r = 14; r < 32; ++r)
			AIRR(Ostw, r, Rsp,r*4);

		cp = code;
		gen(Ob | Lk);

		AIRR(Olwz, Ro1, Rsp,52);
		MTCR(Ro1);
		for (r = 14; r < 32; ++r)
			AIRR(Olwz, r, Rsp,r*4);
		AIRR(Oaddi, Rsp, Rsp, 128);

		AIRR(Olwz, Ro1, Rsp,4);
		mtspr(Rlr, Ro1);
		LRET();

		PATCH(cp);
	}
#endif	/* __ELF__ */

	ldc((ulong)&R, Rreg);
	SETR0();
	mfspr(Rlink, Rlr);
	AIRR(Ostw, Rlink, Rreg,O(REG,xpc));
	AIRR(Olwz, Ri, Rreg,O(REG,PC));
	mtspr(Rctr, Ri);
	AIRR(Olwz, Rfp, Rreg,O(REG,FP));
	AIRR(Olwz, Rmp, Rreg,O(REG,MP));
	gen(Obctr);
	if(code >= (ulong*)(s + PREFLEN))
		urk("preamble");
	comvec = (void*)s;
	segflush(s, PREFLEN*sizeof(*s));
	if(cflag > 3) {
		print("comvec\n");
		while(s < code)
			s += das(s);
	}
}

static void
macfrp(void)
{
	CMPH(Ri);
	gen(Obclr | Ceq);	// arg == $H? => return

	AIRR(Olwz, Ro2, Ri,O(Heap,ref)-sizeof(Heap));
	AIRR(Oaddic_, Rj, Ro2, -1);		// ref(arg)-- and test
	AIRR(Ostw, Rj, Ri,O(Heap,ref)-sizeof(Heap));
	gen(Obclr | Cne);		// ref(arg) nonzero? => return

	AIRR(Ostw, Ro2, Ri,O(Heap,ref)-sizeof(Heap));	// restore ref count of 1 for destroy
	mfspr(Rlink, Rlr);
	AIRR(Ostw, Rlink, Rreg,O(REG,st));
	AIRR(Ostw, Rfp, Rreg,O(REG,FP));
	AIRR(Ostw, Ri, Rreg,O(REG,s));

	jmpl((ulong*)rdestroy);				// CALL	destroy

	ldc((ulong)&R, Rreg);
	SETR0();
	AIRR(Olwz, Rlink, Rreg,O(REG,st));
	mtspr(Rlr, Rlink);
	AIRR(Olwz, Rfp, Rreg,O(REG,FP));
	AIRR(Olwz, Rmp, Rreg,O(REG,MP));
	LRET();
}

static void
macret(void)
{
	ulong *cp1, *cp2, *cp3, *cp4, *cp5, *linterp;
	Inst i;

	AIRR(Olwz, Ro1, Rfp,O(Frame,t));
	AIRR(Ocmpi, Rcrf0, Ro1, 0);
	cp1 = code;
	br(Obeq, 0);		// t(Rfp) == 0

	AIRR(Olwz, Rpic, Ro1,O(Type,destroy));
	AIRR(Ocmpi, Rcrf0, Rpic, 0);
	cp2 = code;
	br(Obeq, 0);		// destroy(t(fp)) == 0

	AIRR(Olwz, Ro2, Rfp,O(Frame,fp));
	AIRR(Ocmpi, Rcrf0, Ro2, 0);
	cp3 = code;
	br(Obeq, 0);		// fp(Rfp) == 0

	AIRR(Olwz, Ro3, Rfp,O(Frame,mr));
	AIRR(Ocmpi, Rcrf0, Ro3, 0);
	cp4 = code;
	br(Obeq, 0);		// mr(Rfp) == 0

	AIRR(Olwz, Ro2, Rreg,O(REG,M));
	AIRR(Olwz, Ro3, Ro2,O(Heap,ref)-sizeof(Heap));
	AIRR(Oaddic_, Ro3, Ro3, -1);	// --ref(arg), set cc
	cp5 = code;
	br(Obeq, 0);	// --ref(arg) == 0?
	AIRR(Ostw, Ro3, Ro2,O(Heap,ref)-sizeof(Heap));

	AIRR(Olwz, Ro1, Rfp,O(Frame,mr));
	AIRR(Ostw, Ro1, Rreg,O(REG,M));
	AIRR(Olwz, Rmp, Ro1,O(Modlink,MP));
	AIRR(Ostw, Rmp, Rreg,O(REG,MP));
	AIRR(Olwz, Ro3, Ro1,O(Modlink,compiled));	// R.M->compiled?
	AIRR(Ocmpi, Rcrf0, Ro3, 0);
	linterp = code;
	br(Obeq, 0);

	PATCH(cp4);
	jrl(Rpic);			// call destroy(t(fp))
	AIRR(Ostw, Rfp, Rreg,O(REG,SP));
	AIRR(Olwz, Ro1, Rfp,O(Frame,lr));
	AIRR(Olwz, Rfp, Rfp,O(Frame,fp));
	AIRR(Ostw, Rfp, Rreg,O(REG,FP));	// R.FP = Rfp
	jr(Ro1);				// goto lr(Rfp)

	PATCH(linterp);
	jrl(Rpic);			// call destroy(t(fp))
	AIRR(Ostw, Rfp, Rreg,O(REG,SP));
	AIRR(Olwz, Ro1, Rfp,O(Frame,lr));
	AIRR(Olwz, Rfp, Rfp,O(Frame,fp));
	AIRR(Ostw, Ro1, Rreg,O(REG,PC));	// R.PC = fp->lr
	AIRR(Ostw, Rfp, Rreg,O(REG,FP));	// R.FP = Rfp
	AIRR(Olwz, Rpic, Rreg,O(REG,xpc));
	mtspr(Rlr, Rpic);
	gen(Oblr);		// return to xec uncompiled code

	PATCH(cp1);
	PATCH(cp2);
	PATCH(cp3);
	PATCH(cp5);
	i.add = AXNON;
	punt(&i, TCHECK|NEWPC, optab[IRET]);
}

static void
maccase(void)
{
	ulong *cp1, *cp2, *cp3, *loop;

/*
 * Ro1 = value (input arg), t
 * Ro2 = count, n
 * Ro3 = table pointer (input arg)
 * Ri  = n/2, n2
 * Rj  = pivot element t+n/2*3, l
 */

	IRR(Olwz, 0,Ro3, Ro2);		// count
	IRR(Oaddi, 0,Ro3, Rlink);	// initial table pointer

	loop = code;			// loop:
	AIRR(Ocmpi, Rcrf0, Ro2, 0);
	cp1 = code;
	br(Oble, 0);	// n <= 0? goto out
	LRRR(Osrawi, Ri, Ro2, 1);		// n2 = n>>1
	SLWI(Rj, Ri, 1);
	ARRR(Oadd, Rj, Rj, Ri);
	SLWI(Rj, Rj, 2);
	ARRR(Oadd, Rj, Rj, Ro3);	// l = t + n2*3;
	AIRR(Olwz, Rpic, Rj,4);
	ARRR(Ocmp, Rcrf0, Ro1, Rpic);
	cp2 = code;
	br(Oblt, 0);		// v < l[1]? goto low

	IRR(Olwz, 8,Rj, Rpic);
	ARRR(Ocmp, Rcrf0, Ro1, Rpic);
	cp3 = code;
	br(Obge, 0);		// v >= l[2]? goto high

	IRR(Olwz, 12,Rj, Ro3);		// found
	jr(Ro3);

	PATCH(cp2);	// low:
	IRR(Oaddi, 0, Ri, Ro2);	// n = n2
	jmp(loop);

	PATCH(cp3);	// high:
	IRR(Oaddi, 12, Rj, Ro3);	// t = l+3;
	IRR(Oaddi, 1, Ri, Rpic);
	RRR(Osubf, Ro2, Rpic, Ro2);	// n -= n2 + 1
	jmp(loop);

	PATCH(cp1);	// out:
	IRR(Olwz, 0,Rlink, Ro2);		// initial n
	SLWI(Ro3, Ro2, 1);
	RRR(Oadd, Ro3, Ro2, Ro2);
	SLWI(Ro2, Ro2, 2);
	RRR(Oadd, Ro2, Rlink, Rlink);
	IRR(Olwz, 4,Rlink, Ro3);		// (initial t)[n*3+1]
	jr(Ro3);
}

static	void
macmcal(void)
{
	ulong *cp;

	AIRR(Olwz, Ro2, Ri,O(Modlink,prog));
	mfspr(Rlink, Rlr);
	AIRR(Ostw, Rlink, Ro1,O(Frame,lr));	// f->lr = return
	AIRR(Ocmpi, Rcrf0, Ro2, 0);
	AIRR(Oaddi, Rfp, Ro1, 0);		// R.FP = f
	cp = code;
	br(Obne, 0);		// CMPL ml->m->prog != 0

	AIRR(Ostw, Rlink, Rreg,O(REG,st));
	AIRR(Ostw, Ro1, Rreg,O(REG,FP));
	AIRR(Ostw, Rj, Rreg,O(REG,dt));
	jmpl((ulong*)rmcall);			// CALL	rmcall
	ldc((ulong)&R, Rreg);
	SETR0();
	AIRR(Olwz, Rlink, Rreg,O(REG,st));
	mtspr(Rlr, Rlink);
	AIRR(Olwz, Rfp, Rreg,O(REG,FP));
	AIRR(Olwz, Rmp, Rreg,O(REG,MP));
	gen(Oblr);	// RET

	PATCH(cp);
	AIRR(Olwz, Ro2, Ri,O(Heap,ref)-sizeof(Heap));
	AIRR(Ostw, Ri, Rreg,O(REG,M));
	AIRR(Oaddi, Ro2, Ro2, 1);
	AIRR(Olwz, Rmp, Ri,O(Modlink,MP));
	AIRR(Ostw, Ro2, Ri,O(Heap,ref)-sizeof(Heap));
	AIRR(Ostw, Rmp, Rreg,O(REG,MP));
	AIRR(Olwz, Ro2, Ri,O(Modlink,compiled));
	AIRR(Ocmpi, Rcrf0, Ro2, 0);
	mtspr(Rctr, Rj);
	gen(Obcctr | Cne);	// return to compiled code

	AIRR(Ostw, Rfp, Rreg,O(REG,FP));	// R.FP = Rfp
	AIRR(Ostw, Rj, Rreg,O(REG,PC));	// R.PC = Rj
	AIRR(Olwz, Rpic, Rreg,O(REG,xpc));
	mtspr(Rlr, Rpic);
	gen(Oblr);		// return to xec uncompiled code
}

static	void
macmfra(void)
{
	mfspr(Rlink, Rlr);
	AIRR(Ostw, Rlink, Rreg,O(REG,st));
	AIRR(Ostw, Rfp, Rreg,O(REG,FP));
	AIRR(Ostw, Ri, Rreg,O(REG,s));
	AIRR(Ostw, Rj, Rreg,O(REG,d));
	jmpl((ulong*)rmfram);
	ldc((ulong)&R, Rreg);
	SETR0();
	AIRR(Olwz, Rlink, Rreg,O(REG,st));
	mtspr(Rlr, Rlink);
	AIRR(Olwz, Rfp, Rreg,O(REG,FP));
	AIRR(Olwz, Rmp, Rreg,O(REG,MP));
	gen(Oblr);
}

static void
macfram(void)
{
	ulong *cp;

	/*
	 * Ri has t
	 */
	AIRR(Olwz, Ro2, Ri,O(Type,size));		// MOVW t->size, Ro3
	AIRR(Olwz, Ro1, Rreg,O(REG,SP));		// MOVW	R.SP, Ro1  (=(Frame*)R.SP)
	AIRR(Olwz, Ro3, Rreg,O(REG,TS));		// MOVW	R.TS, tmp
	ARRR(Oadd, Ro2, Ro2, Ro1);		// ADD Ro1, t->size, nsp
	ARRR(Ocmpl, Rcrf0, Ro2, Ro3);		// CMPU nsp,tmp (nsp >= R.TS?)
	cp = code;
	br(Obge, 0);			// BGE expand

	AIRR(Olwz, Rj, Ri,O(Type,initialize));
	mtspr(Rctr, Rj);
	AIRR(Ostw, Ro2, Rreg,O(REG,SP));		// R.SP = nsp
	AIRR(Ostw, Rzero, Ro1,O(Frame,mr));	// Ro1->mr = nil
	AIRR(Ostw, Ri, Ro1,O(Frame,t));		// Ro1->t = t
	gen(Obctr);				// become t->init(Ro1), returning Ro1

	PATCH(cp);					// expand:
	AIRR(Ostw, Ri, Rreg,O(REG,s));		// MOVL	t, R.s
	mfspr(Rlink, Rlr);
	AIRR(Ostw, Rlink, Rreg,O(REG,st));	// MOVL	Rlink, R.st
	AIRR(Ostw, Rfp, Rreg,O(REG,FP));		// MOVL	RFP, R.FP
	jmpl((ulong*)extend);		// CALL	extend
	ldc((ulong)&R, Rreg);
	SETR0();
	AIRR(Olwz, Rlink, Rreg,O(REG,st));	// reload registers
	mtspr(Rlr, Rlink);
	AIRR(Olwz, Rfp, Rreg,O(REG,FP));
	AIRR(Olwz, Rmp, Rreg,O(REG,MP));
	AIRR(Olwz, Ro1, Rreg,O(REG,s));		// return R.s set by extend
	LRET();	// RET
}

static void
movloop(int ldu, int stu, int adj)
{
	ulong *cp;

	AIRR(Oaddi, Ro1, Ro1, -adj);	// adjust for update ld/st
	AIRR(Oaddi, Ro3, Ro3, -adj);
	mtspr(Rctr, Ro2);

	cp = code;			// l0:
	AIRR(ldu, Ri, Ro1,adj);
	AIRR(stu, Ri, Ro3,adj);
	br(Obc | Cdnz, ((ulong)cp-(ulong)code));	// DBNZ l0
}

static void
movmem(Inst *i)
{
	ulong *cp;

	// source address already in Ro1
	if((i->add&ARM) != AXIMM){
		op2(i, Olwz, Ro2);
		AIRR(Ocmpi, Rcrf0, Ro2, 0);
		cp = code;
		br(Oble, 0);
		opwst(i, Olea, Ro3);
		movloop(Olbzu, Ostbu, 1);
		PATCH(cp);
		return;
	}
	switch(i->reg){
	case 4:
		AIRR(Olwz, Ro2, Ro1,0);
		opwst(i, Ostw, Ro2);
		break;
	case 8:
		AIRR(Olwz, Ro2, Ro1,0);
		opwst(i, Olea, Ro3);
		AIRR(Olwz, Ro1, Ro1,4);
		AIRR(Ostw, Ro2, Ro3,0);
		AIRR(Ostw, Ro1, Ro3,4);
		break;
	default:
		// could use lwsi/stwsi loop...
		opwst(i, Olea, Ro3);
		if((i->reg&3) == 0) {
			ldc(i->reg>>2, Ro2);
			movloop(Olwzu, Ostwu, 4);
		} else {
			ldc(i->reg, Ro2);
			movloop(Olbzu, Ostbu, 1);
		}
		break;
	}
}

static void
maccolr(void)
{
	ldbigc((ulong)&mutator, Ri);
	AIRR(Olwz, Ri, Ri,0);
	AIRR(Olwz, Ro3, Ro1,O(Heap,color)-sizeof(Heap));	// h->color

	AIRR(Olwz, Ro2, Ro1,O(Heap,ref)-sizeof(Heap));	// h->ref

	ARRR(Ocmp, Rcrf0, Ri, Ro3);
	AIRR(Oaddi, Ro2, Ro2, 1);	// h->ref++
	AIRR(Ostw, Ro2, Ro1,O(Heap,ref)-sizeof(Heap));
	gen(Obclr | Ceq);	// return if h->color == mutator

	ldc(propagator, Ro3);
	AIRR(Ostw, Ro3, Ro1,O(Heap,color)-sizeof(Heap));	// h->color = propagator
	ldc((ulong)&nprop, Ro3);
	AIRR(Ostw, Ro1, Ro3,0);	// nprop = !0
	LRET();
}

static void
maccvtfw(void)
{
	ulong *cp;

	ARRR(Ofcmpo, Rcrf0, Rf1, Rfzero);
	ARRR(Ofneg, Rf2, 0, Rfhalf);
	cp = code;
	br(Oblt, 0);
	ARRR(Ofmr, Rf2, 0, Rfhalf);
	PATCH(cp);
	ARRR(Ofadd, Rf1, Rf1, Rf2);	//x<0? x-.5: x+.5
	ARRR(Ofctiwz, Rf2, 0, Rf1);
	/* avoid using Ostfdu for now, since software emulation will run on same stack */
	if(0){
		AIRR(Ostfdu, Rf2, Rsp,-8);		// MOVDU Rf2, -8(R1)    (store in temp)
	}else{
		AIRR(Oaddi, Rsp, Rsp, -8);		// SUB $8, R1
		AIRR(Ostfd, Rf2, Rsp,0);		// MOVD Rf2, 0(R1)    (store in temp)
	}
	AIRR(Olwz, Ro1, Rsp,4);		// MOVW 4(R1), Ro1
	AIRR(Oaddi, Rsp, Rsp, 8);		// ADD $8, R1
	LRET();
}

static void
macrelq(void)
{
	ARRR(Ocrxor, Rcrbrel, Rcrbrel, Rcrbrel);	/* clear the relinquish condition */
	mfspr(Rlink, Rlr);
	IRR(Ostw, O(REG,FP),Rreg, Rfp);
	IRR(Ostw, O(REG,PC),Rreg, Rlink);
	IRR(Olwz, O(REG,xpc),Rreg, Ro2);
	jr(Ro2);
}

static void
macend(void)
{
}

void
comd(Type *t)
{
	int i, j, m, c;

	mfspr(Rlink, Rlr);
	AIRR(Ostw, Rlink, Rreg,O(REG,dt));
	for(i = 0; i < t->np; i++) {
		c = t->map[i];
		j = i<<5;
		for(m = 0x80; m != 0; m >>= 1) {
			if(c & m) {
				mem(Olwz, j, Rfp, Ri);
				jmpl(base+macro[MacFRP]);
			}
			j += sizeof(WORD*);
		}
	}
	AIRR(Olwz, Rlink, Rreg,O(REG,dt));
	mtspr(Rlr, Rlink);
	gen(Oblr);
}

void
comi(Type *t)
{
	int i, j, m, c;

	ldc((ulong)H, Ri);
	for(i = 0; i < t->np; i++) {
		c = t->map[i];
		j = i<<5;
		for(m = 0x80; m != 0; m >>= 1) {
			if(c & m)
				mem(Ostw, j, Ro1, Ri);
			j += sizeof(WORD*);
		}
	}
	LRET();
}

void
typecom(Type *t)
{
	int n;
	ulong *tmp, *start;

	if(t == nil || t->initialize != 0)
		return;

	tmp = mallocz(4096*sizeof(ulong), 0);
	if(tmp == nil)
		error(exNomem);

	code = tmp;
	comi(t);
	n = code - tmp;
	code = tmp;
	comd(t);
	n += code - tmp;
	free(tmp);

	n *= sizeof(*code);
	code = mallocz(n, 0);
	if(code == nil)
		return;

	start = code;
	t->initialize = code;
	comi(t);
	t->destroy = code;
	comd(t);

	segflush(start, n);

	if(cflag > 3)
		print("typ= %.8lux %4d i %.8lux d %.8lux asm=%d\n",
			(ulong)t, t->size, (ulong)t->initialize, (ulong)t->destroy, n);
}

static void
patchex(Module *m, ulong *p)
{
	Handler *h;
	Except *e;

	if((h = m->htab) == nil)
		return;
	for( ; h->etab != nil; h++){
		h->pc1 = p[h->pc1];
		h->pc2 = p[h->pc2];
		for(e = h->etab; e->s != nil; e++)
			e->pc = p[e->pc];
		if(e->pc != -1)
			e->pc = p[e->pc];
	}
}

int
compile(Module *m, int size, Modlink *ml)
{
	Link *l;
	Modl *e;
	int i, n;
	ulong *s, *tmp;

	base = nil;
	patch = mallocz(size*sizeof(*patch), ROMABLE);
	tinit = malloc(m->ntype*sizeof(*tinit));
	tmp = malloc(4096*sizeof(ulong));
	if(tinit == nil || patch == nil || tmp == nil)
		goto bad;

	preamble();

	mod = m;
	n = 0;
	pass = 0;
	nlit = 0;

	for(i = 0; i < size; i++) {
		code = tmp;
		comp(&m->prog[i]);
		if(code >= &tmp[4096]) {
			print("%3d %D\n", i, &m->prog[i]);
			urk("tmp ovflo");
		}
		patch[i] = n;
		n += code - tmp;
	}

	for(i=0; macinit[i].f; i++) {
		code = tmp;
		(*macinit[i].f)();
		macro[macinit[i].o] = n;
		n += code - tmp;
	}

	base = mallocz((n+nlit)*sizeof(*base), 0);
	if(base == nil)
		goto bad;

	if(cflag > 3)
		print("dis=%5d %5d ppc=%5d asm=%.8lux lit=%d: %s\n",
			size, size*sizeof(Inst), n, (ulong)base, nlit, m->name);

	pass++;
	nlit = 0;
	litpool = base+n;
	code = base;
	n = 0;

	for(i = 0; i < size; i++) {
		s = code;
		comp(&m->prog[i]);
		if(patch[i] != n) {
			print("%3d %D\n", i, &m->prog[i]);
			urk("phase error");
		}
		n += code - s;
		if(cflag > 3) {
			print("%3d %D\n", i, &m->prog[i]);
			while(s < code)
				s += das(s);
		}/**/
	}

	for(i=0; macinit[i].f; i++) {
		if(macro[macinit[i].o] != n) {
			print("macinit %d\n", macinit[i].o);
			urk("phase error");
		}
		s = code;
		(*macinit[i].f)();
		n += code - s;
		if(cflag > 3) {
			print("macinit %d\n", macinit[i].o);
			while(s < code)
				s += das(s);
		}/**/
	}

	for(l = m->ext; l->name; l++) {
		l->u.pc = (Inst*)(base+patch[l->u.pc-m->prog]);
		typecom(l->frame);
	}
	if(ml != nil) {
		e = &ml->links[0];
		for(i = 0; i < ml->nlinks; i++) {
			e->u.pc = (Inst*)(base+patch[e->u.pc-m->prog]);
			typecom(e->frame);
			e++;
		}
	}
	for(i = 0; i < m->ntype; i++) {
		if(tinit[i] != 0)
			typecom(m->type[i]);
	}
	patchex(m, patch);
	m->entry = (Inst*)(base+patch[mod->entry-mod->prog]);
	free(patch);
	free(tinit);
	free(tmp);
	free(m->prog);
	m->prog = (Inst*)base;
	m->compiled = 1;
	segflush(base, n*sizeof(*base));
	return 1;
bad:
	free(patch);
	free(tinit);
	free(base);
	free(tmp);
	return 0;
}
