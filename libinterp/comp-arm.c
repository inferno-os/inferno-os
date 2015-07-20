#include "lib9.h"
#include "isa.h"
#include "interp.h"
#include "raise.h"

/*
 * to do:
 *	eliminate litpool?
 *	eliminate long constants in comi/comd
 *	enable and check inline FP code (not much point with fpemu)
 */

#define	RESCHED 1	/* check for interpreter reschedule */
#define	SOFTFP	1

enum
{
	R0	= 0,
	R1	= 1,
	R2	= 2,
	R3	= 3,
	R4	= 4,
	R5	= 5,
	R6	= 6,
	R7	= 7,
	R8	= 8,
	R9	= 9,
	R10	= 10,
	R11	= 11,
	R12	= 12,		/* C's SB */
	R13	= 13,		/* C's SP */
	R14	= 14,		/* Link Register */
	R15	= 15,		/* PC */

	RLINK	= 14,

	RFP	= R9,		/* Frame Pointer */
	RMP	= R8,		/* Module Pointer */
	RTA	= R7,		/* Intermediate address for double indirect */
	RCON	= R6,		/* Constant builder */
	RREG	= R5,		/* Pointer to REG */
	RA3	= R4,		/* gpr 3 */
	RA2	= R3,		/* gpr 2 2+3 = L */
	RA1	= R2,		/* gpr 1 */
	RA0	= R1,		/* gpr 0 0+1 = L */


	FA2	= 2,		/* Floating */
	FA3	= 3,
	FA4	= 4,
	FA5	= 5,

	EQ	= 0,
	NE	= 1,
	CS	= 2,
	CC	= 3,
	MI	= 4,
	PL	= 5,
	VS	= 6,
	VC	= 7,
	HI	= 8,
	LS	= 9,
	GE	= 10,
	LT	= 11,
	GT	= 12,
	LE	= 13,
	AL	= 14,
	NV	= 15,

	HS	= CS,
	LO	= CC,

	And	= 0,
	Eor	= 1,
	Sub	= 2,
	Rsb	= 3,
	Add	= 4,
	Adc	= 5,
	Sbc	= 6,
	Rsc	= 7,
	Tst	= 8,
	Teq	= 9,
	Cmp	= 10,
	Cmn	= 11,
	Orr	= 12,
	Mov	= 13,
	Bic	= 14,
	Mvn	= 15,

	Adf	= 0,
	Muf	= 1,
	Suf	= 2,
	Rsf	= 3,
	Dvf	= 4,
	Rdf	= 5,
	Rmf	= 8,

	Mvf	= 0,
	Mnf	= 1,
	Abs	= 2,
	Rnd	= 3,

	Flt	= 0,
	Fix	= 1,

	Cmf	= 4,
	Cnf	= 5,

	Lea	= 100,		/* macro memory ops */
	Ldw,
	Ldb,
	Stw,
	Stb,
	Ldf,
	Stf,
	Ldh,

	Blo	= 0,	/* offset of low order word in big */
	Bhi	= 4,	/* offset of high order word in big */

	Lg2Rune	= 2,

	NCON	= (0xFFC-8)/4,

	SRCOP	= (1<<0),
	DSTOP	= (1<<1),
	WRTPC	= (1<<2),
	TCHECK	= (1<<3),
	NEWPC	= (1<<4),
	DBRAN	= (1<<5),
	THREOP	= (1<<6),

	ANDAND	= 1,
	OROR	= 2,
	EQAND	= 3,

	MacFRP	= 0,
	MacRET,
	MacCASE,
	MacCOLR,
	MacMCAL,
	MacFRAM,
	MacMFRA,
	MacRELQ,
	NMACRO
};

#define BITS(B)				(1<<B)
#define IMM(O)				(O & ((1<<12)-1))
#define SBIT	(1<<20)
#define PBIT	(1<<24)
#define UPBIT	(1<<23)

#define LDW(C, Rn, Rd, O)		*code++ = (C<<28)|(1<<26)|(1<<24)|(1<<23)|(1<<20)|\
					  (Rn<<16)|(Rd<<12)|IMM(O)
#define STW(C, Rn, Rd, O)		*code++ = (C<<28)|(1<<26)|(1<<24)|(1<<23)|\
					  (Rn<<16)|(Rd<<12)|IMM(O)
#define LDB(C, Rn, Rd, O)		*code++ = (C<<28)|(1<<26)|(1<<24)|(1<<23)|(1<<20)|(1<<22)|\
					  (Rn<<16)|(Rd<<12)|IMM(O)
#define STB(C, Rn, Rd, O)		*code++ = (C<<28)|(1<<26)|(1<<24)|(1<<23)|(1<<22)|\
					  (Rn<<16)|(Rd<<12)|IMM(O)

#define LDxP(C, Rn, Rd, O, B)		*code++ = (C<<28)|(1<<26)|(B<<22)|(1<<23)|(1<<20)|\
					  (Rn<<16)|(Rd<<12)|IMM(O)
#define STxP(C, Rn, Rd, O, B)		*code++ = (C<<28)|(1<<26)|(B<<22)|(1<<23)|\
					  (Rn<<16)|(Rd<<12)|IMM(O)
#define LDRW(C, Rn, Rd, SH, R)		*code++ = (C<<28)|(3<<25)|(1<<24)|(1<<23)|(1<<20)|\
					  (Rn<<16)|(Rd<<12)|(SH<<4)|R
#define STRW(C, Rn, Rd, SH, R)		*code++ = (C<<28)|(3<<25)|(1<<24)|(1<<23)|\
					  (Rn<<16)|(Rd<<12)|(SH<<4)|R
#define LDRB(C, Rn, Rd, SH, R)		*code++ = (C<<28)|(3<<25)|(1<<24)|(1<<23)|(1<<20)|(1<<22)|\
					  (Rn<<16)|(Rd<<12)|(SH<<4)|R
#define STRB(C, Rn, Rd, SH, R)		*code++ = (C<<28)|(3<<25)|(1<<24)|(1<<23)|(1<<22)|\
					  (Rn<<16)|(Rd<<12)|(SH<<4)|R

#define DPI(C, Op, Rn, Rd, RO, O)	*code++ = (C<<28)|(1<<25)|(Op<<21)|\
					  (Rn<<16)|(Rd<<12)|(RO<<8)|((O)&0xff)
#define DP(C, Op, Rn, Rd, Sh, Ro)	*code++ = (C<<28)|(Op<<21)|(Rn<<16)|\
					  (Rd<<12)|((Sh)<<4)|Ro
#define CMPI(C, Rn, Rd, RO, O)	*code++ = (C<<28)|(1<<25)|(Cmp<<21)|(1<<20)|\
					  (Rn<<16)|(Rd<<12)|(RO<<8)|((O)&0xff)
#define CMNI(C, Rn, Rd, RO, O)	*code++ = (C<<28)|(1<<25)|(Cmn<<21)|(1<<20)|\
					  (Rn<<16)|(Rd<<12)|(RO<<8)|((O)&0xff)
#define CMP(C, Rn, Rd, Sh, Ro)	*code++ = (C<<28)|(Cmp<<21)|(Rn<<16)|(1<<20)|\
					  (Rd<<12)|((Sh)<<4)|Ro
#define CMN(C, Rn, Rd, Sh, Ro)	*code++ = (C<<28)|(Cmn<<21)|(Rn<<16)|(1<<20)|\
					  (Rd<<12)|((Sh)<<4)|Ro
#define MUL(C, Rm, Rs, Rd)		*code++ = (C<<28)|(Rd<<16)|(Rm<<0)|(Rs<<8)|\
					  (9<<4)

#define LDF(C, Rn, Fd, O)		*code++ = (C<<28)|(6<<25)|(1<<24)|(1<<23)|(1<<20)|\
					  (Rn<<16)|(1<<15)|(Fd<<12)|(1<<8)|((O)&0xff)
#define STF(C, Rn, Fd, O)		*code++ = (C<<28)|(6<<25)|(1<<24)|(1<<23)|\
					  (Rn<<16)|(1<<15)|(Fd<<12)|(1<<8)|((O)&0xff)
#define CMF(C, Fn, Fm)	*code++ = (C<<28)|(7<<25)|(4<<21)|(1<<20)|(Fn<<16)|\
						(0xF<<12)|(1<<8)|(1<<4)|(Fm)

#define LDH(C, Rn, Rd, O)		*code++ = (C<<28)|(0<<25)|(1<<24)|(1<<23)|(1<<22)|(1<<20)|\
					  (Rn<<16)|(Rd<<12)|(((O)&0xf0)<<4)|(0xb<<4)|((O)&0xf)
#define LDRH(C, Rn, Rd, Rm)		*code++ = (C<<28)|(0<<25)|(1<<24)|(1<<23)|(1<<20)|\
					  (Rn<<16)|(Rd<<12)|(0xb<<4)|Rm

#define CPDO2(C, Op, Fn, Fd, Fm)	*code++ = (C<<28)|(0xE<<24)|(Op<<20)|(Fn<<16)|(Fd<<12)|(1<<8)|(1<<7)|(Fm)
#define CPDO1(C, Op, Fd, Fm)	CPDO2((C),(Op),0,(Fd),(Fm))|(1<<15)
#define CPFLT(C, Fn, Rd)	*code++ = (C<<28)|(0xE<<24)|(0<<20)|(Fn<<16)|(Rd<<12)|(1<<8)|(9<<4)
#define CPFIX(C, Rd, Fm)	*code++ = (C<<28)|(0xE<<24)|(1<<20)|(0<<16)|(Rd<<12)|(1<<8)|(9<<4)|(Fm)

#define BRAW(C, o)			((C<<28)|(5<<25)|((o) & 0x00ffffff))
#define BRA(C, o)			gen(BRAW((C),(o)))
#define IA(s, o)			(ulong)(base+s[o])
#define BRADIS(C, o)			BRA(C, (IA(patch, o)-(ulong)code-8)>>2)
#define BRAMAC(r, o)			BRA(r, (IA(macro, o)-(ulong)code-8)>>2)
#define BRANCH(C, o)				gen(BRAW(C, ((ulong)(o)-(ulong)code-8)>>2))
#define CALL(o)				gen(BRAW(AL, ((ulong)(o)-(ulong)code-8)>>2)|(1<<24))
#define CCALL(C,o)				gen(BRAW((C), ((ulong)(o)-(ulong)code-8)>>2)|(1<<24))
#define CALLMAC(C,o)			gen(BRAW((C), (IA(macro, o)-(ulong)code-8)>>2)|(1<<24))
#define RELPC(pc)			(ulong)(base+(pc))
#define RETURN				DPI(AL, Add, RLINK, R15, 0, 0)				
#define CRETURN(C)				DPI(C, Add, RLINK, R15, 0, 0)				
#define PATCH(ptr)			*ptr |= (((ulong)code-(ulong)(ptr)-8)>>2) & 0x00ffffff

#define MOV(src, dst)			DP(AL, Mov, 0, dst, 0, src)

#define FITS12(v)	((ulong)(v)<BITS(12))
#define FITS8(v)	((ulong)(v)<BITS(8))
#define FITS5(v)	((ulong)(v)<BITS(5))

/* assumes H==-1 */
#define CMPH(C, r)		CMNI(C, r, 0, 0, 1)
#define NOTNIL(r)	(CMPH(AL, (r)), CCALL(EQ, nullity))

/* array bounds checking */
#define BCK(r, rb)	(CMP(AL, rb, 0, 0, r), CCALL(LS, bounds))
#define BCKI(i, rb)	(CMPI(AL, rb, 0, 0, i), CCALL(LS, bounds))
#define BCKR(i, rb)	(CMPI(AL, rb, 0, 0, 0)|(i), CCALL(LS, bounds))

static	ulong*	code;
static	ulong*	base;
static	ulong*	patch;
static	ulong	codeoff;
static	int	pass;
static	int	puntpc = 1;
static	Module*	mod;
static	uchar*	tinit;
static	ulong*	litpool;
static	int	nlit;
static	ulong	macro[NMACRO];
	void	(*comvec)(void);
static	void	macfrp(void);
static	void	macret(void);
static	void	maccase(void);
static	void	maccolr(void);
static	void	macmcal(void);
static	void	macfram(void);
static	void	macmfra(void);
static	void	macrelq(void);
static	void movmem(Inst*);
static	void mid(Inst*, int, int);
extern	void	das(ulong*, int);

#define T(r)	*((void**)(R.r))

struct
{
	int	idx;
	void	(*gen)(void);
	char*	name;
} mactab[] =
{
	MacFRP,		macfrp,		"FRP", 	/* decrement and free pointer */
	MacRET,		macret,		"RET",	/* return instruction */
	MacCASE,	maccase,	"CASE",	/* case instruction */
	MacCOLR,	maccolr,	"COLR",	/* increment and color pointer */
	MacMCAL,	macmcal,	"MCAL",	/* mcall bottom half */
	MacFRAM,	macfram,	"FRAM",	/* frame instruction */
	MacMFRA,	macmfra,	"MFRA",	/* punt mframe because t->initialize==0 */
	MacRELQ,		macrelq,	/* reschedule */
};

typedef struct Const Const;
struct Const
{
	ulong	o;
	ulong*	code;
	ulong*	pc;
};

typedef struct Con Con;
struct Con
{
	int	ptr;
	Const	table[NCON];	
};
static Con rcon;

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

	if(R.d == H)
		error(exModule);
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

static void
urk(char *s)
{
	USED(s);
	error(exCompile);	//production
	//panic("compile failed: urk: %s\n", s);	//debugging
}

static void
gen(ulong w)
{
	*code++ = w;
}

static long
immrot(ulong v)
{
	int i;

	for(i=0; i<16; i++) {
		if((v & ~0xff) == 0)
			return (i<<8) | v | (1<<25);
		v = (v<<2) | (v>>30);
	}
	return 0;
}

static long
immaddr(long v)
{

	if(v >= 0 && v <= 0xfff)
		return (v & 0xfff) |
			(1<<24) |	/* pre indexing */
			(1<<23);	/* pre indexing, up */
	if(v >= -0xfff && v < 0)
		return (-v & 0xfff) |
			(1<<24);	/* pre indexing */
	return 0;
}

static void
flushcon(int genbr)
{
	int i;
	Const *c;
	ulong disp;

	if(rcon.ptr == 0)
		return;
	if(genbr){
		if(0)print("BR %d(PC)=%8.8p (len=%d)\n", (rcon.ptr*4+4-8)>>2, code+rcon.ptr+1, rcon.ptr);
		BRA(AL, (rcon.ptr*4+4-8)>>2);
	}
	c = &rcon.table[0];
	for(i = 0; i < rcon.ptr; i++) {
		if(pass){
			disp = (code - c->code) * sizeof(*code) - 8;
			if(disp >= BITS(12))
				print("INVALID constant range %lud", disp);
			if(0)print("data %8.8p %8.8lux (%8.8p, ins=%8.8lux cpc=%8.8p)\n", code, c->o, c->code, *c->code, c->pc);
			*c->code |= (disp&0xfff);
		}
		*code++ = c->o;
		c++;
	}
	rcon.ptr = 0;
}

static void
flushchk(void)
{
	if(rcon.ptr >= NCON || rcon.ptr > 0 && (code+codeoff+2-rcon.table[0].pc)*sizeof(*code) >= BITS(12)-256){  // 256 allows for a little delay in calling flushchk
		if(0)print("flushed constant table: len %ux disp %ld\n", rcon.ptr, (code+codeoff-rcon.table[0].pc)*sizeof(*code)-8);
		flushcon(1);
	}
}

static void
ccon(int cc, ulong o, int r, int opt)
{
	ulong u;
	Const *c;

	if(opt != 0) {
		u = o & ~0xff;
		if(u == 0) {
			DPI(cc, Mov, 0, r, 0, o);
			return;		
		}
		if(u == ~0xff) {
			DPI(cc, Mvn, 0, r, 0, ~o);
			return;
		}
		u = immrot(o);
		if(u) {
			DPI(cc, Mov, 0, r, 0, 0) | u;
			return;
		}
		u = o & ~0xffff;
		if(u == 0) {
			DPI(cc, Mov, 0, r, 0, o);
			DPI(cc, Orr, r, r, (24/2), o>>8);
			return;
		}
	}
	flushchk();
	c = &rcon.table[rcon.ptr++];
	c->o = o;
	c->code = code;
	c->pc = code+codeoff;
	LDW(cc, R15, r, 0);
}

static void
memc(int c, int inst, ulong disp, int rm, int r)
{
	int bit;

	if(inst == Lea) {
		if(disp < BITS(8)) {
			if(disp != 0 || rm != r)
				DPI(c, Add, rm, r, 0, disp);
			return;
		}
		if(-disp < BITS(8)) {
			DPI(c, Sub, rm, r, 0, -disp);
			return;
		}
		bit = immrot(disp);
		if(bit) {
			DPI(c, Add, rm, r, 0, 0) | bit;
			return;
		}
		ccon(c, disp, RCON, 1);
		DP(c, Add, rm, r, 0, RCON);
		return;
	}

	if(disp < BITS(12) || -disp < BITS(12)) {	/* Direct load */
		if(disp < BITS(12))
			bit = 0;
		else {
			disp = -disp;
			bit = UPBIT;
		}
		switch(inst) {
		case Ldw:
			LDW(c, rm, r, disp);
			break;
		case Ldb:
			LDB(c, rm, r, disp);
			break;
		case Stw:
			STW(c, rm, r, disp);
			break;
		case Stb:
			STB(c, rm, r, disp);
			break;
		}
		if(bit)
			code[-1] ^= bit;
		return;
	}

	ccon(c, disp, RCON, 1);
	switch(inst) {
	case Ldw:
		LDRW(c, rm, r, 0, RCON);
		break;
	case Ldb:
		LDRB(c, rm, r, 0, RCON);
		break;
	case Stw:
		STRW(c, rm, r, 0, RCON);
		break;
	case Stb:
		STRB(c, rm, r, 0, RCON);
		break;
	}
}

static void
con(ulong o, int r, int opt)
{
	ccon(AL, o, r, opt);
}

static void
mem(int inst, ulong disp, int rm, int r)
{
	memc(AL, inst, disp, rm, r);
}

static void
opx(int mode, Adr *a, int mi, int r, int li)
{
	int ir, rta;

	switch(mode) {
	default:
		urk("opx");
	case AFP:
		mem(mi, a->ind, RFP, r);
		return;
	case AMP:
		mem(mi, a->ind, RMP, r);
		return;
	case AIMM:
		con(a->imm, r, 1);
		if(mi == Lea) {	/* could be simpler if con generates reachable literal */
			mem(Stw, li, RREG, r);
			mem(Lea, li, RREG, r);
		}
		return;
	case AIND|AFP:
		ir = RFP;
		break;
	case AIND|AMP:
		ir = RMP;
		break;
	}
	rta = RTA;
	if(mi == Lea)
		rta = r;
	mem(Ldw, a->i.f, ir, rta);
	mem(mi, a->i.s, rta, r);
}

static void
opwld(Inst *i, int op, int reg)
{
	opx(USRC(i->add), &i->s, op, reg, O(REG, st));
}

static void
opwst(Inst *i, int op, int reg)
{
	opx(UDST(i->add), &i->d, op, reg, O(REG, dt));
}

static void
memfl(int cc, int inst, ulong disp, int rm, int r)
{
	int bit, wd;

	wd = (disp&03)==0;
	bit = 0;
	if(wd && disp < BITS(10))
		disp >>= 2;	/* direct load */
	else if(wd && -disp < BITS(10)){
		bit = UPBIT;
		disp = -disp >> 2;
	}else{
		ccon(cc, disp, RCON, 1);
		DP(cc, Add, RCON, RCON, 0, rm);
		rm = RCON;
		disp = 0;
	}
	switch(inst) {
	case Ldf:
		LDF(cc, rm, r, disp);
		break;
	case Stf:
		STF(cc, rm, r, disp);
		break;
	}
	if(bit)
		code[-1] ^= bit;
}

static void
opfl(Adr *a, int am, int mi, int r)
{
	int ir;

	switch(am) {
	default:
		urk("opfl");
	case AFP:
		memfl(AL, mi, a->ind, RFP, r);
		return;
	case AMP:
		memfl(AL, mi, a->ind, RMP, r);
		return;
	case AIND|AFP:
		ir = RFP;
		break;
	case AIND|AMP:
		ir = RMP;
		break;
	}
	mem(Ldw, a->i.f, ir, RTA);
	memfl(AL, mi, a->i.s, RTA, r);
}

static void
opflld(Inst *i, int mi, int r)
{
	opfl(&i->s, USRC(i->add), mi, r);
}

static void
opflst(Inst *i, int mi, int r)
{
	opfl(&i->d, UDST(i->add), mi, r);
}

static void
literal(ulong imm, int roff)
{
	nlit++;

	con((ulong)litpool, RTA, 0);
	mem(Stw, roff, RREG, RTA);

	if(pass == 0)
		return;

	*litpool = imm;
	litpool++;	
}

static void
schedcheck(Inst *i)
{
	if(RESCHED && i->d.ins <= i){
		mem(Ldw, O(REG, IC), RREG, RA0);
		DPI(AL, Sub, RA0, RA0, 0, 1) | SBIT;
		mem(Stw, O(REG, IC), RREG, RA0);
		/* CMPI(AL, RA0, 0, 0, 1); */
		CALLMAC(LE, MacRELQ);
	}
}

static void
bounds(void)
{
	/* mem(Stw, O(REG,FP), RREG, RFP); */
	error(exBounds);
}

static void
nullity(void)
{
	/* mem(Stw, O(REG,FP), RREG, RFP); */
	error(exNilref);
}

static void
punt(Inst *i, int m, void (*fn)(void))
{
	ulong pc;

	if(m & SRCOP) {
		if(UXSRC(i->add) == SRC(AIMM))
			literal(i->s.imm, O(REG, s));
		else {
			opwld(i, Lea, RA0);
			mem(Stw, O(REG, s), RREG, RA0);
		}
	}

	if(m & DSTOP) {
		opwst(i, Lea, RA0);
		mem(Stw, O(REG, d), RREG, RA0);
	}
	if(m & WRTPC) {
		con(RELPC(patch[i-mod->prog+1]), RA0, 0);
		mem(Stw, O(REG, PC), RREG, RA0);
	}
	if(m & DBRAN) {
		pc = patch[i->d.ins-mod->prog];
		literal((ulong)(base+pc), O(REG, d));
	}

	switch(i->add&ARM) {
	case AXNON:
		if(m & THREOP) {
			mem(Ldw, O(REG, d), RREG, RA0);
			mem(Stw, O(REG, m), RREG, RA0);
		}
		break;
	case AXIMM:
		literal((short)i->reg, O(REG,m));
		break;
	case AXINF:
		mem(Lea, i->reg, RFP, RA2);
		mem(Stw, O(REG, m), RREG, RA2);
		break;
	case AXINM:
		mem(Lea, i->reg, RMP, RA2);
		mem(Stw, O(REG, m), RREG, RA2);
		break;
	}
	mem(Stw, O(REG, FP), RREG, RFP);

	CALL(fn);

	con((ulong)&R, RREG, 1);
	if(m & TCHECK) {
		mem(Ldw, O(REG, t), RREG, RA0);
		CMPI(AL, RA0, 0, 0, 0);
		memc(NE, Ldw, O(REG, xpc), RREG, RLINK);
		CRETURN(NE);		/* if(R.t) goto(R.xpc) */
	}
	mem(Ldw, O(REG, FP), RREG, RFP);
	mem(Ldw, O(REG, MP), RREG, RMP);

	if(m & NEWPC){
		mem(Ldw, O(REG, PC), RREG, R15);
		flushcon(0);
	}
}

static void
midfl(Inst *i, int mi, int r)
{
	int ir;

	switch(i->add&ARM) {
	default:
		opflst(i, mi, r);
		return;
	case AXIMM:
		con((short)i->reg, r, 1);	// BUG
		return;
	case AXINF:
		ir = RFP;
		break;
	case AXINM:
		ir = RMP;
		break;
	}
	memfl(AL, mi, i->reg, ir, r);
}

static void
mid(Inst *i, int mi, int r)
{
	int ir;

	switch(i->add&ARM) {
	default:
		opwst(i, mi, r);
		return;
	case AXIMM:
		if(mi == Lea)
			urk("mid/lea");
		con((short)i->reg, r, 1);
		return;
	case AXINF:
		ir = RFP;
		break;
	case AXINM:
		ir = RMP;
		break;
	}
	mem(mi, i->reg, ir, r);
}

static int
swapbraop(int b)
{
	switch(b) {
	case GE:
		return LE;
	case LE:
		return GE;
	case GT:
		return LT;
	case LT:
		return GT;
	}
	return b;
}

static void
cbra(Inst *i, int r)
{
	if(RESCHED)
		schedcheck(i);
	if(UXSRC(i->add) == SRC(AIMM) && FITS8(i->s.imm)) {
		mid(i, Ldw, RA1);
		CMPI(AL, RA1, 0, 0, i->s.imm);
		r = swapbraop(r);
	} else if(UXSRC(i->add) == SRC(AIMM) && FITS8(-i->s.imm)) {
		mid(i, Ldw, RA1);
		CMNI(AL, RA1, 0, 0, -i->s.imm);
		r = swapbraop(r);
	} else if((i->add & ARM) == AXIMM && FITS8(i->reg)) {
		opwld(i, Ldw, RA1);
		CMPI(AL, RA1, 0, 0, i->reg);
	} else if((i->add & ARM) == AXIMM && FITS8(-(short)i->reg)) {
		opwld(i, Ldw, RA1);
		CMNI(AL, RA1, 0, 0, -(short)i->reg);
	} else {
		opwld(i, Ldw, RA0);
		mid(i, Ldw, RA1);
		CMP(AL, RA0, 0, 0, RA1);
	}
	BRADIS(r, i->d.ins-mod->prog);
}

static void
cbrab(Inst *i, int r)
{
	if(RESCHED)
		schedcheck(i);
	if(UXSRC(i->add) == SRC(AIMM)) {
		mid(i, Ldb, RA1);
		CMPI(AL, RA1, 0, 0, i->s.imm&0xFF);
		r = swapbraop(r);
	} else if((i->add & ARM) == AXIMM) {
		opwld(i, Ldb, RA1);
		CMPI(AL, RA1, 0, 0, i->reg&0xFF);
	} else {
		opwld(i, Ldb, RA0);
		mid(i, Ldb, RA1);
		CMP(AL, RA0, 0, 0, RA1);
	}
	BRADIS(r, i->d.ins-mod->prog);
}

static void
cbral(Inst *i, int jmsw, int jlsw, int mode)
{
	ulong dst, *label;

	if(RESCHED)
		schedcheck(i);
	opwld(i, Lea, RA1);
	mid(i, Lea, RA3);
	mem(Ldw, Bhi, RA1, RA2);
	mem(Ldw, Bhi, RA3, RA0);
	CMP(AL, RA2, 0, 0, RA0);
	label = nil;
	dst = i->d.ins-mod->prog;
	switch(mode) {
	case ANDAND:
		label = code;
		BRA(jmsw, 0);
		break;
	case OROR:
		BRADIS(jmsw, dst);
		break;
	case EQAND:
		BRADIS(jmsw, dst);
		label = code;
		BRA(NE, 0);
		break;
	}
	mem(Ldw, Blo, RA3, RA0);
	mem(Ldw, Blo, RA1, RA2);
	CMP(AL, RA2, 0, 0, RA0);
	BRADIS(jlsw, dst);
	if(label != nil)
		PATCH(label);
}

static void
cbraf(Inst *i, int r)
{
	if(RESCHED)
		schedcheck(i);
	if(!SOFTFP){
		ulong *s=code;
		opflld(i, Ldf, FA4);
		midfl(i, Ldf, FA2);
		CMF(AL, FA4, FA2);
		BRADIS(r, i->d.ins-mod->prog);
		if(pass){print("%D\n", i); das(s, code-s);}
	}else
		punt(i, SRCOP|THREOP|DBRAN|NEWPC|WRTPC, optab[i->op]);
}	

static void
comcase(Inst *i, int w)
{
	int l;
	WORD *t, *e;

	if(w != 0) {
		opwld(i, Ldw, RA1);		// v
		opwst(i, Lea, RA3);		// table
		BRAMAC(AL, MacCASE);
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
		t[2] = RELPC(patch[t[2]]);
		t += 3;
	}
	t[0] = RELPC(patch[t[0]]);
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
		t[4] = RELPC(patch[t[4]]);
		t += 6;
	}
	t[0] = RELPC(patch[t[0]]);
}

static void
commframe(Inst *i)
{
	ulong *punt, *mlnil;

	opwld(i, Ldw, RA0);
	CMPH(AL, RA0);
	mlnil = code;
	BRA(EQ, 0);

	if((i->add&ARM) == AXIMM) {
		mem(Ldw, OA(Modlink, links)+i->reg*sizeof(Modl)+O(Modl, frame), RA0, RA3);
	} else {
		mid(i, Ldw, RA1);
		DP(AL, Add, RA0, RA1, (3<<3), RA1);	// assumes sizeof(Modl) == 8
		mem(Ldw, OA(Modlink, links)+O(Modl, frame), RA1, RA3);
	}

	mem(Ldw, O(Type, initialize), RA3, RA1);
	CMPI(AL, RA1, 0, 0, 0);
	punt = code;
	BRA(NE, 0);

	opwst(i, Lea, RA0);

	/* Type in RA3, destination in RA0 */
	PATCH(mlnil);
	con(RELPC(patch[i-mod->prog+1]), RLINK, 0);
	BRAMAC(AL, MacMFRA);

	/* Type in RA3 */
	PATCH(punt);
	CALLMAC(AL, MacFRAM);
	opwst(i, Stw, RA2);
}

static void
commcall(Inst *i)
{
	ulong *mlnil;

	opwld(i, Ldw, RA2);
	con(RELPC(patch[i-mod->prog+1]), RA0, 0);
	mem(Stw, O(Frame, lr), RA2, RA0);
	mem(Stw, O(Frame, fp), RA2, RFP);
	mem(Ldw, O(REG, M), RREG, RA3);
	mem(Stw, O(Frame, mr), RA2, RA3);
	opwst(i, Ldw, RA3);
	CMPH(AL, RA3);
	mlnil = code;
	BRA(EQ, 0);
	if((i->add&ARM) == AXIMM) {
		mem(Ldw, OA(Modlink, links)+i->reg*sizeof(Modl)+O(Modl, u.pc), RA3, RA0);
	} else {
		mid(i, Ldw, RA1);
		DP(AL, Add, RA3, RA1, (3<<3), RA1);	// assumes sizeof(Modl) == 8
		mem(Ldw, OA(Modlink, links)+O(Modl, u.pc), RA1, RA0);
	}
	PATCH(mlnil);
	CALLMAC(AL, MacMCAL);
}

static void
larith(Inst *i, int op, int opc)
{
	opwld(i, Lea, RA0);
	mid(i, Lea, RA3);
	mem(Ldw, Blo, RA0, RA1);	// ls
	mem(Ldw, Blo, RA3, RA2);
	DP(AL, op, RA2, RA2, 0, RA1) | SBIT;	// ls: RA2 = RA2 op RA1
	mem(Ldw, Bhi, RA0, RA1);
	mem(Ldw, Bhi, RA3, RA0);
	DP(AL, opc, RA0, RA0, 0, RA1);	// ms: RA0 = RA0 opc RA1
	if((i->add&ARM) != AXNON)
		opwst(i, Lea, RA3);
	mem(Stw, Blo, RA3, RA2);
	mem(Stw, Bhi, RA3, RA0);
}

static void
movloop(Inst *i, int s)
{
	int b;

	b = (s==1);
	opwst(i, Lea, RA2);
	LDxP(AL, RA1, RA0, s, b);
	STxP(AL, RA2, RA0, s, b);
	DPI(AL, Sub, RA3, RA3, 0, 1) | SBIT;
	BRA(NE, (-3*4-8)>>2);
}

static void
movmem(Inst *i)
{
	ulong *cp;

	// source address already in RA1
	if((i->add&ARM) != AXIMM){
		mid(i, Ldw, RA3);
		CMPI(AL, RA3, 0, 0, 0);
		cp = code;
		BRA(LE, 0);
		movloop(i, 1);
		PATCH(cp);
		return;
	}
	switch(i->reg){
	case 0:
		break;
	case 4:
		LDW(AL, RA1, RA2, 0);
		opwst(i, Stw, RA2);
		break;
	case 8:
		LDW(AL, RA1, RA2, 0);
		opwst(i, Lea, RA3);
		LDW(AL, RA1, RA1, 4);
		STW(AL, RA3, RA2, 0);
		STW(AL, RA3, RA1, 4);
		break;
	default:
		// could use ldm/stm loop...
		if((i->reg&3) == 0) {
			con(i->reg>>2, RA3, 1);
			movloop(i, 4);
		} else {
			con(i->reg, RA3, 1);
			movloop(i, 1);
		}
		break;
	}
}

static
void
compdbg(void)
{
	print("%s:%lud@%.8lux\n", R.M->m->name, *(ulong*)R.m, *(ulong*)R.s);
}

static void
comgoto(Inst *i)
{
	WORD *t, *e;

	opwld(i, Ldw, RA1);
	opwst(i, Lea, RA0);
	LDRW(AL, RA0, R15, (2<<3), RA1);
	flushcon(0);

	if(pass == 0)
		return;

	t = (WORD*)(mod->origmp+i->d.ind);
	e = t + t[-1];
	t[-1] = 0;
	while(t < e) {
		t[0] = RELPC(patch[t[0]]);
		t++;
	}
}

static void
comp(Inst *i)
{
	int r, imm;
	char buf[64];
//ulong *s = code;
	if(0) {
		Inst xx;
		xx.add = AXIMM|SRC(AIMM);
		xx.s.imm = (ulong)code;
		xx.reg = i-mod->prog;
		puntpc = 0;
		punt(&xx, SRCOP, compdbg);
		puntpc = 1;
		flushcon(1);
	}
	flushchk();

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
	case IMODW:
	case IMODB:
	case IDIVW:
	case IDIVB:
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
	case IHEADB:
	case IHEADW:
	case IHEADL:
	case IINSC:
	case ICVTAC:
	case ICVTCW:
	case ICVTWC:
	case ICVTLC:
	case ICVTCL:
	case ICVTFC:
	case ICVTCF:
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
	case IMFRAME:
		if((i->add&ARM) == AXIMM)
			commframe(i);
		else
			punt(i, SRCOP|DSTOP|THREOP, optab[i->op]);
		break;
	case ICASE:
		comcase(i, 1);
		break;
	case IGOTO:
		comgoto(i);
		break;
	case IMOVF:
		if(!SOFTFP){
			opflld(i, Ldf, FA2);
			opflst(i, Stf, FA2);
			break;
		}
		/* if no hardware, just fall through */
	case IMOVL:
		opwld(i, Lea, RA1);
		LDW(AL, RA1, RA2, 0);
		LDW(AL, RA1, RA3, 4);
		opwst(i, Lea, RA1);
		STW(AL, RA1, RA2, 0);
		STW(AL, RA1, RA3, 4);
		break;
		break;
	case IHEADM:
		opwld(i, Ldw, RA1);
		NOTNIL(RA1);
		if(OA(List,data) != 0)
			DPI(AL, Add, RA1, RA1, 0, OA(List,data));
		movmem(i);
		break;
/*
	case IHEADW:
		opwld(i, Ldw, RA0);
		NOTNIL(RA0);
		mem(Ldw, OA(List, data), RA0, RA0);
		opwst(i, Stw, RA0);
		break;
*/
	case IMOVM:
		opwld(i, Lea, RA1);
		movmem(i);
		break;
	case IFRAME:
		if(UXSRC(i->add) != SRC(AIMM)) {
			punt(i, SRCOP|DSTOP, optab[i->op]);
			break;
		}
		tinit[i->s.imm] = 1;
		con((ulong)mod->type[i->s.imm], RA3, 1);
		CALL(base+macro[MacFRAM]);
		opwst(i, Stw, RA2);
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
	case ICVTBW:
		opwld(i, Ldb, RA0);
		opwst(i, Stw, RA0);
		break;
	case ICVTWB:
		opwld(i, Ldw, RA0);
		opwst(i, Stb, RA0);
		break;
	case ILEA:
		opwld(i, Lea, RA0);
		opwst(i, Stw, RA0);
		break;
	case IMOVW:
		opwld(i, Ldw, RA0);
		opwst(i, Stw, RA0);
		break;
	case IMOVB:
		opwld(i, Ldb, RA0);
		opwst(i, Stb, RA0);
		break;
	case ITAIL:
		opwld(i, Ldw, RA0);
		NOTNIL(RA0);
		mem(Ldw, O(List, tail), RA0, RA1);
		goto movp;
	case IMOVP:
		opwld(i, Ldw, RA1);
		goto movp;
	case IHEADP:
		opwld(i, Ldw, RA0);
		NOTNIL(RA0);
		mem(Ldw, OA(List, data), RA0, RA1);
	movp:
		CMPH(AL, RA1);
		CALLMAC(NE, MacCOLR);		// colour if not H
		opwst(i, Lea, RA2);
		mem(Ldw, 0,RA2, RA0);
		mem(Stw, 0,RA2, RA1);
		CALLMAC(AL, MacFRP);
		break;
	case ILENA:
		opwld(i, Ldw, RA1);
		con(0, RA0, 1);
		CMPH(AL, RA1);
		LDW(NE, RA1, RA0, O(Array,len));
		opwst(i, Stw, RA0);
		break;
	case ILENC:
		opwld(i, Ldw, RA1);
		con(0, RA0, 1);
		CMPH(AL, RA1);
		memc(NE, Ldw, O(String,len),RA1, RA0);
		CMPI(AL, RA0, 0, 0, 0);
		DPI(LT, Rsb, RA0, RA0, 0, 0);
		opwst(i, Stw, RA0);
		break;
	case ILENL:
		con(0, RA0, 1);
		opwld(i, Ldw, RA1);

		CMPH(AL, RA1);
		LDW(NE, RA1, RA1, O(List, tail));
		DPI(NE, Add, RA0, RA0, 0, 1);
		BRA(NE, (-4*3-8)>>2);

		opwst(i, Stw, RA0);
		break;
	case ICALL:
		opwld(i, Ldw, RA0);
		con(RELPC(patch[i-mod->prog+1]), RA1, 0);
		mem(Stw, O(Frame, lr), RA0, RA1);
		mem(Stw, O(Frame, fp), RA0, RFP);
		MOV(RA0, RFP);
		BRADIS(AL, i->d.ins-mod->prog);
		flushcon(0);
		break;
	case IJMP:
		if(RESCHED)
			schedcheck(i);
		BRADIS(AL, i->d.ins-mod->prog);
		flushcon(0);
		break;
	case IBEQW:
		cbra(i, EQ);
		break;		
	case IBNEW:
		cbra(i, NE);
		break;
	case IBLTW:
		cbra(i, LT);
		break;
	case IBLEW:
		cbra(i, LE);
		break;
	case IBGTW:
		cbra(i, GT);
		break;
	case IBGEW:
		cbra(i, GE);
		break;
	case IBEQB:
		cbrab(i, EQ);
		break;
	case IBNEB:
		cbrab(i, NE);
		break;
	case IBLTB:
		cbrab(i, LT);
		break;
	case IBLEB:
		cbrab(i, LE);
		break;
	case IBGTB:
		cbrab(i, GT);
		break;
	case IBGEB:
		cbrab(i, GE);
		break;
	case IBEQF:
		cbraf(i, EQ);
		break;
	case IBNEF:
		cbraf(i, NE);
		break;
	case IBLTF:
		cbraf(i, LT);
		break;
	case IBLEF:
		cbraf(i, LE);
		break;
	case IBGTF:
		cbraf(i, GT);
		break;
	case IBGEF:
		cbraf(i, GE);
		break;
	case IRET:
		mem(Ldw, O(Frame,t), RFP, RA1);
		BRAMAC(AL, MacRET);
		break;
	case IMULW:
		opwld(i, Ldw, RA1);
		mid(i, Ldw, RA0);
		MUL(AL, RA1, RA0, RA0);
		opwst(i, Stw, RA0);
		break;
	case IMULB:
		opwld(i, Ldb, RA1);
		mid(i, Ldb, RA0);
		MUL(AL, RA1, RA0, RA0);
		opwst(i, Stb, RA0);
		break;
	case IORW:
		r = Orr;
		goto arithw;
	case IANDW:
		r = And;
		goto arithw;
	case IXORW:
		r = Eor;
		goto arithw;
	case ISUBW:
		r = Sub;
		goto arithw;
	case IADDW:
		r = Add;
	arithw:
		mid(i, Ldw, RA1);
		if(UXSRC(i->add) == SRC(AIMM) && FITS8(i->s.imm))
			DPI(AL, r, RA1, RA0, 0, i->s.imm);
		else if(UXSRC(i->add) == SRC(AIMM) && immrot(i->s.imm)){
			DPI(AL, r, RA1, RA0, 0, 0) | immrot(i->s.imm);
			//print("rot: %ux %ux\n", i->s.imm, immrot(i->s.imm)); das(code-1, 1);
		} else {
			opwld(i, Ldw, RA0);
			DP(AL, r, RA1, RA0, 0, RA0);
		}
		opwst(i, Stw, RA0);
		break;
	case ISHRW:
		r = 2;
	shiftw:
		mid(i, Ldw, RA1);
		if(UXSRC(i->add) == SRC(AIMM) && FITS5(i->s.imm))
			DP(AL, Mov, 0, RA0, ((i->s.imm&0x3F)<<3)|(r<<1), RA1);
		else {
			opwld(i, Ldw, RA0);
			DP(AL, Mov, 0, RA0, (RA0<<4)|(r<<1)|1, RA1);
		}
		opwst(i, Stw, RA0);
		break;
	case ISHLW:
		r = 0;
		goto shiftw;
		break;
	case IORB:
		r = Orr;
		goto arithb;
	case IANDB:
		r = And;
		goto arithb;
	case IXORB:
		r = Eor;
		goto arithb;
	case ISUBB:
		r = Sub;
		goto arithb;
	case IADDB:
		r = Add;
	arithb:
		mid(i, Ldb, RA1);
		if(UXSRC(i->add) == SRC(AIMM))
			DPI(AL, r, RA1, RA0, 0, i->s.imm);
		else {
			opwld(i, Ldb, RA0);
			DP(AL, r, RA1, RA0, 0, RA0);
		}
		opwst(i, Stb, RA0);
		break;
	case ISHRB:
		r = 2;
		goto shiftb;
	case ISHLB:
		r = 0;
	shiftb:
		mid(i, Ldb, RA1);
		if(UXSRC(i->add) == SRC(AIMM) && FITS5(i->s.imm))
			DP(AL, Mov, 0, RA0, ((i->s.imm&0x3F)<<3)|(r<<1), RA1);
		else {
			opwld(i, Ldw, RA0);
			DP(AL, Mov, 0, RA0, (RA0<<4)|(r<<1)|1, RA1);
		}
		opwst(i, Stb, RA0);
		break;
	case IINDC:
		opwld(i, Ldw, RA1);			// RA1 = string
		NOTNIL(RA1);
		imm = 1;
		if((i->add&ARM) != AXIMM || !FITS12((short)i->reg<<Lg2Rune) || immrot((short)i->reg) == 0){
			mid(i, Ldw, RA2);			// RA2 = i
			imm = 0;
		}
		mem(Ldw, O(String,len),RA1, RA0);	// len<0 => index Runes, otherwise bytes
		if(bflag){
			DPI(AL, Orr, RA0, RA3, 0, 0);
			DPI(LT, Rsb, RA3, RA3, 0, 0);
			if(imm)
				BCKR(immrot((short)i->reg), RA3);
			else
				BCK(RA2, RA3);
		}
		DPI(AL, Add, RA1, RA1, 0, O(String,data));
		CMPI(AL, RA0, 0, 0, 0);
		if(imm){
			LDB(GE, RA1, RA3, i->reg);
			LDW(LT, RA1, RA3, (short)i->reg<<Lg2Rune);
		} else {
			LDRB(GE, RA1, RA3, 0, RA2);
			DP(LT, Mov, 0, RA2, (Lg2Rune<<3), RA2);
			LDRW(LT, RA1, RA3, 0, RA2);
		}
		opwst(i, Stw, RA3);
//if(pass){print("%D\n", i); das(s, code-s);}
		break;
	case IINDL:
	case IINDF:
	case IINDW:
	case IINDB:
		opwld(i, Ldw, RA0);			/* a */
		NOTNIL(RA0);
		if(bflag)
			mem(Ldw, O(Array, len), RA0, RA2);
		mem(Ldw, O(Array, data), RA0, RA0);
		r = 0;
		switch(i->op) {
		case IINDL:
		case IINDF:
			r = 3;
			break;
		case IINDW:
			r = 2;
			break;
		}
		if(UXDST(i->add) == DST(AIMM) && (imm = immrot(i->d.imm)) != 0) {
			if(bflag)
				BCKR(imm, RA2);
			if(i->d.imm != 0)
				DPI(AL, Add, RA0, RA0, 0, 0) | immrot(i->d.imm<<r);
		} else {
			opwst(i, Ldw, RA1);
			if(bflag)
				BCK(RA1, RA2);
			DP(AL, Add, RA0, RA0, r<<3, RA1);
		}
		mid(i, Stw, RA0);
//if(pass){print("%D\n", i); das(s, code-s);}
		break;
	case IINDX:
		opwld(i, Ldw, RA0);			/* a */
		NOTNIL(RA0);
		opwst(i, Ldw, RA1);			/* i */

		if(bflag){
			mem(Ldw, O(Array, len), RA0, RA2);
			BCK(RA1, RA2);
		}
		mem(Ldw, O(Array, t), RA0, RA2);
		mem(Ldw, O(Array, data), RA0, RA0);
		mem(Ldw, O(Type, size), RA2, RA2);
		MUL(AL, RA2, RA1, RA1);
		DP(AL, Add, RA1, RA0, 0, RA0);
		mid(i, Stw, RA0);
//if(pass){print("%D\n", i); das(s, code-s);}
		break;
	case IADDL:
		larith(i, Add, Adc);
		break;
	case ISUBL:
		larith(i, Sub, Sbc);
		break;
	case IORL:
		larith(i, Orr, Orr);
		break;
	case IANDL:
		larith(i, And, And);
		break;
	case IXORL:
		larith(i, Eor, Eor);
		break;
	case ICVTWL:
		opwld(i, Ldw, RA1);
		opwst(i, Lea, RA2);
		DP(AL, Mov, 0, RA0, (0<<3)|(2<<1), RA1);	// ASR 32
		STW(AL, RA2, RA1, Blo);
		STW(AL, RA2, RA0, Bhi);
		break;
	case ICVTLW:
		opwld(i, Lea, RA0);
		mem(Ldw, Blo, RA0, RA0);
		opwst(i, Stw, RA0);
		break;
	case IBEQL:
		cbral(i, NE, EQ, ANDAND);
		break;
	case IBNEL:
		cbral(i, NE, NE, OROR);
		break;
	case IBLEL:
		cbral(i, LT, LS, EQAND);
		break;
	case IBGTL:
		cbral(i, GT, HI, EQAND);
		break;
	case IBLTL:
		cbral(i, LT, CC, EQAND);
		break;
	case IBGEL:
		cbral(i, GT, CS, EQAND);
		break;
	case ICVTFL:
	case ICVTLF:
		punt(i, SRCOP|DSTOP, optab[i->op]);
		break;
	case IDIVF:
		r = Dvf;
		goto arithf;
	case IMULF:
		r = Muf;
		goto arithf;
	case ISUBF:
		r = Suf;
		goto arithf;
	case IADDF:
		r = Adf;
	arithf:
		if(SOFTFP){
			/* software fp */
			USED(r);
			punt(i, SRCOP|DSTOP|THREOP, optab[i->op]);
			break;
		}
		opflld(i, Ldf, FA2);
		midfl(i, Ldf, FA4);
		CPDO2(AL, r, FA4, FA4, FA2);
		opflst(i, Stf, FA4);
		break;
	case INEGF:
		if(SOFTFP){
			punt(i, SRCOP|DSTOP, optab[i->op]);
			break;
		}
		opflld(i, Ldf, FA2);
		CPDO1(AL, Mnf, FA2, FA2);
		opflst(i, Stf, FA2);
//if(pass){print("%D\n", i); das(s, code-s);}
		break;
	case ICVTWF:
		if(SOFTFP){
			punt(i, SRCOP|DSTOP, optab[i->op]);
			break;
		}
		opwld(i, Ldw, RA2);
		CPFLT(AL, FA2, RA2);
		opflst(i, Stf, FA2);
//if(pass){print("%D\n", i); das(s, code-s);}
		break;
	case ICVTFW:
		if(SOFTFP){
			punt(i, SRCOP|DSTOP, optab[i->op]);
			break;
		}
		opflld(i, Ldf, FA2);
		CPFIX(AL, RA2, FA2);
		opwst(i, Stw, RA2);
//if(pass){print("%D\n", i); das(s, code-s);}
		break;
	case ISHLL:
		/* should do better */
		punt(i, SRCOP|DSTOP|THREOP, optab[i->op]);
		break;
	case ISHRL:
		/* should do better */
		punt(i, SRCOP|DSTOP|THREOP, optab[i->op]);
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

static void
preamble(void)
{
	if(comvec)
		return;

	comvec = malloc(10 * sizeof(*code));
	if(comvec == nil)
		error(exNomem);
	code = (ulong*)comvec;

	con((ulong)&R, RREG, 0);
	mem(Stw, O(REG, xpc), RREG, RLINK);
	mem(Ldw, O(REG, FP), RREG, RFP);
	mem(Ldw, O(REG, MP), RREG, RMP);
	mem(Ldw, O(REG, PC), RREG, R15);
	pass++;
	flushcon(0);
	pass--;

	segflush(comvec, 10 * sizeof(*code));
}

static void
maccase(void)
{
	ulong *cp1, *loop, *inner;
/*
 * RA1 = value (input arg), t
 * RA2 = count, n
 * RA3 = table pointer (input arg)
 * RA0  = n/2, n2
 * RCON  = pivot element t+n/2*3, l
 */
	LDW(AL, RA3, RA2, 0);	// count from table
	MOV(RA3, RLINK);	// initial table pointer

	loop = code;			// loop:
	CMPI(AL, RA2, 0, 0, 0);
	cp1 = code;
	BRA(LE, 0);	// n <= 0? goto out

	inner = code;
	DP(AL, Mov, 0, RA0, (1<<3)|2, RA2);	// n2 = n>>1
	DP(AL, Add, RA0, RCON, (1<<3), RA0);	// n' = n2+(n2<<1) = 3*n2
	DP(AL, Add, RA3, RCON, (2<<3), RCON);	// l = t + n2*3;

	LDW(AL, RCON, RTA, 4);
	CMP(AL, RA1, 0, 0, RTA);
	DP(LT, Mov, 0, RA2, 0, RA0);	// v < l[1]? n=n2
	BRANCH(LT, loop);	// v < l[1]? goto loop

	LDW(AL, RCON, RTA, 8);
	CMP(AL, RA1, 0, 0, RTA);
	LDW(LT, RCON, R15, 12);	// v >= l[1] && v < l[2] => found; goto l[3]

	// v >= l[2] (high)
	DPI(AL, Add, RCON, RA3, 0, 12);	// t = l+3;
	DPI(AL, Add, RA0, RTA, 0, 1);
	DP(AL, Sub, RA2, RA2, 0, RTA) | SBIT;	// n -= n2+1
	BRANCH(GT, inner);	// n > 0? goto loop

	PATCH(cp1);	// out:
	LDW(AL, RLINK, RA2, 0);		// initial n
	DP(AL, Add, RA2, RA2, (1<<3), RA2);	// n = n+(n<<1) = 3*n
	DP(AL, Add, RLINK, RLINK, (2<<3), RA2);	// t' = &(initial t)[n*3]
	LDW(AL, RLINK, R15, 4);		// goto (initial t)[n*3+1]
}

static void
macfrp(void)
{
	/* destroy the pointer in RA0 */
	CMPH(AL, RA0);
	CRETURN(EQ);		// arg == H? => return

	mem(Ldw, O(Heap, ref)-sizeof(Heap), RA0, RA2);
	DPI(AL, Sub, RA2, RA2, 0, 1) | SBIT;
	memc(NE, Stw, O(Heap, ref)-sizeof(Heap), RA0, RA2);
	CRETURN(NE);		// --h->ref != 0 => return

	mem(Stw, O(REG, FP), RREG, RFP);
	mem(Stw, O(REG, st), RREG, RLINK);
	mem(Stw, O(REG, s), RREG, RA0);
	CALL(rdestroy);
	con((ulong)&R, RREG, 1);
	mem(Ldw, O(REG, st), RREG, RLINK);
	mem(Ldw, O(REG, FP), RREG, RFP);
	mem(Ldw, O(REG, MP), RREG, RMP);
	RETURN;
	flushcon(0);
}

static void
maccolr(void)
{
	/* color the pointer in RA1 */
	mem(Ldw, O(Heap, ref)-sizeof(Heap), RA1, RA0);
	DPI(AL, Add, RA0, RA0, 0, 1);
	mem(Stw, O(Heap, ref)-sizeof(Heap), RA1, RA0);	// h->ref++
	con((ulong)&mutator, RA2, 1);
	mem(Ldw, O(Heap, color)-sizeof(Heap), RA1, RA0);
	mem(Ldw, 0, RA2, RA2);
	CMP(AL, RA0, 0, 0, RA2);
	CRETURN(EQ);	// return if h->color == mutator
	con(propagator, RA2, 1);
	mem(Stw, O(Heap, color)-sizeof(Heap), RA1, RA2);	// h->color = propagator
	con((ulong)&nprop, RA2, 1);
	mem(Stw, 0, RA2, RA2);	// nprop = !0
	RETURN;
	flushcon(0);
}

static void
macret(void)
{
	Inst i;
	ulong *cp1, *cp2, *cp3, *cp4, *cp5, *linterp;

	CMPI(AL, RA1, 0, 0, 0);
	cp1 = code;
	BRA(EQ, 0);				// t(Rfp) == 0

	mem(Ldw, O(Type,destroy),RA1, RA0);
	CMPI(AL, RA0, 0, 0, 0);
	cp2 = code;
	BRA(EQ, 0);				// destroy(t(fp)) == 0

	mem(Ldw, O(Frame,fp),RFP, RA2);
	CMPI(AL, RA2, 0, 0, 0);
	cp3 = code;
	BRA(EQ, 0);				// fp(Rfp) == 0

	mem(Ldw, O(Frame,mr),RFP, RA3);
	CMPI(AL, RA3, 0, 0, 0);
	cp4 = code;
	BRA(EQ, 0);				// mr(Rfp) == 0

	mem(Ldw, O(REG,M),RREG, RA2);
	mem(Ldw, O(Heap,ref)-sizeof(Heap),RA2, RA3);
	DPI(AL, Sub, RA3, RA3, 0, 1) | SBIT;
	cp5 = code;
	BRA(EQ, 0);				// --ref(arg) == 0
	mem(Stw, O(Heap,ref)-sizeof(Heap),RA2, RA3);

	mem(Ldw, O(Frame,mr),RFP, RA1);
	mem(Stw, O(REG,M),RREG, RA1);
	mem(Ldw, O(Modlink,MP),RA1, RMP);
	mem(Stw, O(REG,MP),RREG, RMP);
	mem(Ldw, O(Modlink,compiled), RA1, RA3);	// R.M->compiled
	CMPI(AL, RA3, 0, 0, 0);
	linterp = code;
	BRA(EQ, 0);

	PATCH(cp4);
	MOV(R15, R14);		// call destroy(t(fp))
	MOV(RA0, R15);

	mem(Stw, O(REG,SP),RREG, RFP);
	mem(Ldw, O(Frame,lr),RFP, RA1);
	mem(Ldw, O(Frame,fp),RFP, RFP);
	mem(Stw, O(REG,FP),RREG, RFP);	// R.FP = RFP
	DP(AL, Mov, 0, R15, 0, RA1);		// goto lr(Rfp), if compiled

	PATCH(linterp);
	MOV(R15, R14);		// call destroy(t(fp))
	MOV(RA0, R15);

	mem(Stw, O(REG,SP),RREG, RFP);
	mem(Ldw, O(Frame,lr),RFP, RA1);
	mem(Ldw, O(Frame,fp),RFP, RFP);
	mem(Stw, O(REG,PC),RREG, RA1);	// R.PC = fp->lr
	mem(Stw, O(REG,FP),RREG, RFP);	// R.FP = RFP
	mem(Ldw, O(REG, xpc), RREG, RLINK);
	RETURN;		// return to xec uncompiled code

	PATCH(cp1);
	PATCH(cp2);
	PATCH(cp3);
	PATCH(cp5);
	i.add = AXNON;
	punt(&i, TCHECK|NEWPC, optab[IRET]);
}

static void
macmcal(void)
{
	ulong *lab;

	CMPH(AL, RA0);
	memc(NE, Ldw, O(Modlink, prog), RA3, RA1);	// RA0 != H
	CMPI(NE, RA1, 0, 0, 0);	// RA0 != H
	lab = code;
	BRA(NE, 0);	// RA0 != H && m->prog!=0

	mem(Stw, O(REG, st), RREG, RLINK);
	mem(Stw, O(REG, FP), RREG, RA2);
	mem(Stw, O(REG, dt), RREG, RA0);
	CALL(rmcall);				// CALL rmcall

	con((ulong)&R, RREG, 1);		// MOVL	$R, RREG
	mem(Ldw, O(REG, st), RREG, RLINK);
	mem(Ldw, O(REG, FP), RREG, RFP);
	mem(Ldw, O(REG, MP), RREG, RMP);
	RETURN;

	PATCH(lab);				// patch:
	DP(AL, Mov, 0, RFP, 0, RA2);
	mem(Stw, O(REG, M), RREG, RA3);	// MOVL RA3, R.M
	mem(Ldw, O(Heap, ref)-sizeof(Heap), RA3, RA1);
	DPI(AL, Add, RA1, RA1, 0, 1);
	mem(Stw, O(Heap, ref)-sizeof(Heap), RA3, RA1);
	mem(Ldw, O(Modlink, MP), RA3, RMP);	// MOVL R.M->mp, RMP
	mem(Stw, O(REG, MP), RREG, RMP);	// MOVL RA3, R.MP	R.MP = ml->m
	mem(Ldw, O(Modlink,compiled), RA3, RA1);	// M.compiled?
	CMPI(AL, RA1, 0, 0, 0);
	DP(NE, Mov, 0, R15, 0, RA0);	// return to compiled code
	mem(Stw, O(REG,FP),RREG, RFP);	// R.FP = RFP
	mem(Stw, O(REG,PC),RREG, RA0);	// R.PC = RPC
	mem(Ldw, O(REG, xpc), RREG, RLINK);
	RETURN;		// return to xec uncompiled code
	flushcon(0);
}

static void
macfram(void)
{
	ulong *lab1;

	mem(Ldw, O(REG, SP), RREG, RA0);	// MOVL	R.SP, RA0
	mem(Ldw, O(Type, size), RA3, RA1);
	DP(AL, Add, RA0, RA0, 0, RA1);		// nsp = R.SP + t->size
	mem(Ldw, O(REG, TS), RREG, RA1);
	CMP(AL, RA0, 0, 0, RA1);	// nsp :: R.TS
	lab1 = code;
	BRA(CS, 0);	// nsp >= R.TS; must expand

	mem(Ldw, O(REG, SP), RREG, RA2);	// MOVL	R.SP, RA2
	mem(Stw, O(REG, SP), RREG, RA0);	// MOVL	RA0, R.SP

	mem(Stw, O(Frame, t), RA2, RA3);	// MOVL	RA3, t(RA2) f->t = t
	con(0, RA0, 1);
	mem(Stw, O(Frame,mr), RA2, RA0);     	// MOVL $0, mr(RA2) f->mr
	mem(Ldw, O(Type, initialize), RA3, R15);	// become t->init(RA2), returning RA2

	PATCH(lab1);
	mem(Stw, O(REG, s), RREG, RA3);
	mem(Stw, O(REG, st), RREG, RLINK);
	mem(Stw, O(REG, FP), RREG, RFP);	// MOVL	RFP, R.FP
	CALL(extend);				// CALL	extend

	con((ulong)&R, RREG, 1);
	mem(Ldw, O(REG, st), RREG, RLINK);
	mem(Ldw, O(REG, FP), RREG, RFP);	// MOVL	R.FP, RFP
	mem(Ldw, O(REG, s), RREG, RA2);	// MOVL	R.s, *R.d
	mem(Ldw, O(REG, MP), RREG, RMP);	// MOVL R.MP, RMP
	RETURN;					// RET
}

static void
macmfra(void)
{
	mem(Stw, O(REG, st), RREG, RLINK);
	mem(Stw, O(REG, s), RREG, RA3);	// Save type
	mem(Stw, O(REG, d), RREG, RA0);	// Save destination
	mem(Stw, O(REG, FP), RREG, RFP);
	CALL(rmfram);				// CALL rmfram

	con((ulong)&R, RREG, 1);
	mem(Ldw, O(REG, st), RREG, RLINK);
	mem(Ldw, O(REG, FP), RREG, RFP);
	mem(Ldw, O(REG, MP), RREG, RMP);
	RETURN;
}

static void
macrelq(void)
{
	mem(Stw, O(REG,FP),RREG, RFP);	// R.FP = RFP
	mem(Stw, O(REG,PC),RREG, RLINK);	// R.PC = RLINK
	mem(Ldw, O(REG, xpc), RREG, RLINK);
	RETURN;
}

void
comd(Type *t)
{
	int i, j, m, c;

	mem(Stw, O(REG, dt), RREG, RLINK);
	for(i = 0; i < t->np; i++) {
		c = t->map[i];
		j = i<<5;
		for(m = 0x80; m != 0; m >>= 1) {
			if(c & m) {
				mem(Ldw, j, RFP, RA0);
				CALL(base+macro[MacFRP]);
			}
			j += sizeof(WORD*);
		}
		flushchk();
	}
	mem(Ldw, O(REG, dt), RREG, RLINK);
	RETURN;
	flushcon(0);
}

void
comi(Type *t)
{
	int i, j, m, c;

	con((ulong)H, RA0, 1);
	for(i = 0; i < t->np; i++) {
		c = t->map[i];
		j = i<<5;
		for(m = 0x80; m != 0; m >>= 1) {
			if(c & m)
				mem(Stw, j, RA2, RA0);
			j += sizeof(WORD*);
		}
		flushchk();
	}
	RETURN;
	flushcon(0);
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
		print("typ= %.8p %4d i %.8p d %.8p asm=%d\n",
			t, t->size, t->initialize, t->destroy, n);
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
	patch = mallocz(size*sizeof(*patch), 0);
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
		codeoff = n;
		code = tmp;
		comp(&m->prog[i]);
		patch[i] = n;
		n += code - tmp;
	}

	for(i = 0; i < nelem(mactab); i++) {
		codeoff = n;
		code = tmp;
		mactab[i].gen();
		macro[mactab[i].idx] = n;
		n += code - tmp;
	}
	code = tmp;
	flushcon(0);
	n += code - tmp;

	base = mallocz((n+nlit)*sizeof(*code), 0);
	if(base == nil)
		goto bad;

	if(cflag > 3)
		print("dis=%5d %5d 386=%5d asm=%.8p: %s\n",
			size, size*sizeof(Inst), n, base, m->name);

	pass++;
	nlit = 0;
	litpool = base+n;
	code = base;
	n = 0;
	codeoff = 0;
	for(i = 0; i < size; i++) {
		s = code;
		comp(&m->prog[i]);
		if(patch[i] != n) {
			print("%3d %D\n", i, &m->prog[i]);
			print("%lud != %d\n", patch[i], n);
			urk("phase error");
		}
		n += code - s;
		if(cflag > 4) {
			print("%3d %D\n", i, &m->prog[i]);
			das(s, code-s);
		}
	}

	for(i = 0; i < nelem(mactab); i++) {
		s = code;
		mactab[i].gen();
		if(macro[mactab[i].idx] != n){
			print("mac phase err: %lud != %d\n", macro[mactab[i].idx], n);
			urk("phase error");
		}
		n += code - s;
		if(cflag > 4) {
			print("%s:\n", mactab[i].name);
			das(s, code-s);
		}
	}
	s = code;
	flushcon(0);
	n += code - s;

	for(l = m->ext; l->name; l++) {
		l->u.pc = (Inst*)RELPC(patch[l->u.pc-m->prog]);
		typecom(l->frame);
	}
	if(ml != nil) {
		e = &ml->links[0];
		for(i = 0; i < ml->nlinks; i++) {
			e->u.pc = (Inst*)RELPC(patch[e->u.pc-m->prog]);
			typecom(e->frame);
			e++;
		}
	}
	for(i = 0; i < m->ntype; i++) {
		if(tinit[i] != 0)
			typecom(m->type[i]);
	}
	patchex(m, patch);
	m->entry = (Inst*)RELPC(patch[mod->entry-mod->prog]);
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
