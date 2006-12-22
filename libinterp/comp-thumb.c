#include "lib9.h"
#include "isa.h"
#include "interp.h"
#include "raise.h"

#define	RESCHED 1	/* check for interpreter reschedule */

enum
{
	R0	= 0,		// why wasn't this used ?
	R1	= 1,
	R2	= 2,
	R3	= 3,
	R4	= 4,
	R5	= 5,
	R6	= 6,
	R7	= 7,
	R8	= 8,
	R9	= 9,
	R10	= 10,		// unused
	R11	= 11,		// unused
	R12	= 12,		/* C's SB */
	R13	= 13,		/* C's SP */
	R14	= 14,		/* Link Register */
	R15	= 15,		/* PC */

	RSB		= R12,
	RLINK	= R14,
	RPC		= R15,

	RTMP = R11,	/* linker temp */
	RHT	= R8,		/* high temp */
	RFP	= R7,		/* Frame Pointer */
	RMP	= R6,		/* Module Pointer */
	RREG	= R5,		/* Pointer to REG */
	RA3	= R4,		/* gpr 3 */
	RA2	= R3,		/* gpr 2 2+3 = L */
	RA1	= R2,		/* gpr 1 */
	RA0	= R1,		/* gpr 0 0+1 = L */
	RCON	= R0,		/* Constant builder */

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

	And = 0,
	Eor = 1,
	Lsl = 2,
	Lsr = 3,
	Asr = 4,
	Adc = 5,
	Sbc = 6,
	Ror = 7,
	Tst = 8,
	Neg = 9,
	Cmp = 10,
	Cmn = 11,
	Orr = 12,
	Mul = 13,
	Bic = 14,
	Mvn = 15,

	Mov = 16,
	Cmpi = 17,
	Add = 18,
	Sub = 19,

	Cmph = 19,
	Movh = 20,

	Lea	= 100,		/* macro memory ops */
	Ldw,
	Ldb,
	Stw,
	Stb,

	NCON	= (0x3fc-8)/4,

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

#define FIRSTPASS	0
#define MIDDLEPASS	1
#define LASTPASS	2
static	int	pass;

static void
OP(int o, int o1, int o2, char *s)
{
	if(o < o1 || o > o2) print("error: bad op %d in %s\n", o, s);
}

static void
IMM(int i, int i1, int i2, char *s)	
{
	if(i < i1 || i > i2) print("error: bad imm %d in %s\n", i, s);
}

static void
MULT(int o, int m, char *s)
{
	if((o/m)*m != o) print("error: %d not multiple of %d in %s\n", o, m, s);
}
	
static void
LOWREG(int r, char *s)
{
	if(r < 0 || r >= 8) print("error: %s: bad low reg %d\n", s, r);
}

static void
HIGHREG(int r, char *s)
{
	if(r < 8) print("error: %s: bad high reg %d\n", s, r);
}

static void
CKIRRS(int op, int i, int rm, int rd)
{
	OP(op, Lsl, Asr, "IRRS");
	IMM(i, 0, 31, "IRRS");
	LOWREG(rm, "IRRS rm");
	LOWREG(rd, "IRRS rd");
}

static void
CKRRR(int op, int rs, int rm, int rd)
{
	OP(op, Add, Sub, "RRR");
	LOWREG(rs, "RRR rs");
	LOWREG(rm, "RRR rm");
	LOWREG(rd, "RRR rd");
}

static void
CKIRR(int op, int i, int rm, int rd)
{
	OP(op, Add, Sub, "IRR");
	IMM(i, 0, 7, "IRR");
	LOWREG(rm, "IRR rm");
	LOWREG(rd, "IRR rd");
}

static void
CKIR(int op, int i, int rd)
{
	OP(op, Mov, Sub, "IR");
	IMM(i, 0, 255, "IR");
	LOWREG(rd, "IR rd");
}

static void
CKRR(int op, int rs, int rd)
{
	OP(op, And, Mvn, "RR");
	LOWREG(rs, "RR rs");
	LOWREG(rd, "RR rd");
}

static void
CKRH(int op, int rs, int rd)
{
	OP(op, Add, Movh, "RH");
	LOWREG(rs, "RH");
	HIGHREG(rd, "RH");
}

static void
CKHR(int op, int rs, int rd)
{
	OP(op, Add, Movh, "HR");
	HIGHREG(rs, "HR");
	LOWREG(rd, "HR");
}

static void
CKHH(int op, int rs, int rd)
{
	OP(op, Add, Movh, "HH");
	HIGHREG(rs, "HH");
	HIGHREG(rd, "HH");
}

static void
CKLS(int rn, int o, int rd, int s, int l)
{
	char buf[16];

	sprint(buf, "LS %d %d", s, l);
	LOWREG(rn, buf);
	LOWREG(rd, buf);
	MULT(o, s, buf);
	IMM(o/s, 0, 31, buf);
}

static void
CKLSR(int rn, int rm, int rd, int s, int l)
{
	char buf[16];

	sprint(buf, "LSR %d %d", s, l);
	LOWREG(rn, buf);
	LOWREG(rm, buf);
	LOWREG(rd, buf);
}

static void
CKLPCR(int o, int rd)
{
	LOWREG(rd, "LPCR");
	if(o&3)
		o += 2;
	MULT(o, 4, "LPCR");
	IMM(o/4, 0, 255, "LPCR");
}

static void
CKB(int o)
{
	if(pass == FIRSTPASS)
		return;
	MULT(o, 2, "B");
	IMM(o, -2048, 2046, "B");
}

static void
CKBCC(int o)
{
	if(pass == FIRSTPASS)
		return;
	MULT(o, 2, "BCC");
	IMM(o, -256, 254, "BCC");
}

static void
CKBL(int o)
{
	if(pass == FIRSTPASS)
		return;
	MULT(o, 2, "BL");
	IMM(o, -4194304, 4194302, "BL");
}

#define DPIRRS(op, i, rm, rd)	(CKIRRS(op, i, rm, rd), *code++ = ((op-Lsl)<<11) | (i<<6) | (rm<<3) | rd)
#define DPRRR(op, rs, rm, rd)	(CKRRR(op, rs, rm, rd), *code++ = (6<<10) | ((op-Add)<<9) | (rs<<6) | (rm<<3) | rd)
#define DPIRR(op, i, rm, rd)	(CKIRR(op, i, rm, rd), *code++ = (7<<10) | ((op-Add)<<9) | (i<<6) | (rm<<3) | rd)
#define DPIR(op, i, rd)		(CKIR(op, i, rd), *code++ = (1<<13) | ((op-Mov)<<11) | (rd<<8) | i)
#define DPRR(op, rs, rd)		(CKRR(op, rs, rd), *code++ = (1<<14) | (op<<6) | (rs<<3) | rd)

#define DPRH(op, rs, hd)		(CKRH(op, rs, hd), *code++ = (17<<10) | ((op-Add)<<8) | (1<<7) | (rs<<3) | (hd-8))
#define DPHR(op, hs, rd)		(CKHR(op, hs, rd), *code++ = (17<<10) | ((op-Add)<<8) | (1<<6) | ((hs-8)<<3) | rd)
#define DPHH(op, hs, hd)		(CKHH(op, hs, hd), *code++ = (17<<10) | ((op-Add)<<8) | (3<<6) | ((hs-8)<<3) | (hd-8))

#define LDW(rs, o, rd)	(CKLS(rs, o, rd, 4, 1), *code++ = (13<<11)|((o/4)<<6)|(rs<<3)|rd)
#define STW(rs, o, rd)	(CKLS(rs, o, rd, 4, 0), *code++ = (12<<11)|((o/4)<<6)|(rs<<3)|rd)
#define LDH(rs, o, rd)	(CKLS(rs, o, rd, 2, 0), *code++ = (17<<11)|((o/2)<<6)|(rs<<3)|rd)
#define STH(rs, o, rd)	(CKLS(rs, o, rd, 2, 1), *code++ = (16<<11)|((o/2)<<6)|(rs<<3)|rd)
#define LDB(rs, o, rd)	(CKLS(rs, o, rd, 1, 1), *code++ = (15<<11)|(o<<6)|(rs<<3)|rd)
#define STB(rs, o, rd)	(CKLS(rs, o, rd, 1, 0), *code++ = (14<<11)|(o<<6)|(rs<<3)|rd)
#define LDRW(rs, rm, rd)	(CKLSR(rs, rm, rd, 4, 1), *code++ = (44<<9)|(rs<<6)|(rm<<3)|rd)
#define STRW(rs, rm, rd)	(CKLSR(rs, rm, rd, 4, 1), *code++ = (40<<9)|(rs<<6)|(rm<<3)|rd)
#define LDRH(rs, rm, rd)	(CKLSR(rs, rm, rd, 4, 1), *code++ = (45<<9)|(rs<<6)|(rm<<3)|rd)
#define STRH(rs, rm, rd)	(CKLSR(rs, rm, rd, 4, 1), *code++ = (41<<9)|(rs<<6)|(rm<<3)|rd)
#define LDRB(rs, rm, rd)	(CKLSR(rs, rm, rd, 4, 1), *code++ = (46<<9)|(rs<<6)|(rm<<3)|rd)
#define STRB(rs, rm, rd)	(CKLSR(rs, rm, rd, 4, 1), *code++ = (42<<9)|(rs<<6)|(rm<<3)|rd)

#define LDWPCREL(o, rd)	(CKLPCR(o, rd), *code++ = (9<<11)|(rd<<8)|(o/4))

#define CMPI(i, rn)		DPIR(Cmpi, i, rn)
#define CMP(rs, rn)		DPRR(Cmp, rs, rn)
#define CMPRH(rs, rn)	DPRH(Cmph, rs, rn)
#define CMPHR(rs, rn)	DPHR(Cmph, rs, rn)
#define CMPHH(rs, rn)	DPHH(Cmph, rs, rn)
#define MOV(src, dst)	DPIRRS(Lsl, 0, src, dst)
#define MOVRH(s, d)	DPRH(Movh, s, d)
#define MOVHR(s, d)	DPHR(Movh, s, d)
#define MOVHH(s, d)	DPHH(Movh, s, d)
#define MUL(rs, rd)		DPRR(Mul, rs, rd)

#define CODE			(code+codeoff)
#define IA(s, o)			(ulong)(base+s[o])
#define RELPC(pc)		(ulong)(base+(pc))

#define RINV(c)		((c)&1 ? (c)-1 : (c)+1)
#define FPX(fp)			(((ulong)(fp))&~1)	
#define NOBR			4	

#define BRAU(o)		((28<<11) | (((o)>>1)&0x7ff))
#define BRAC(c, o)		((13<<12) | ((c)<<8) | (((o)>>1)&0xff))
#define BRAL1(o)		((30<<11) | ((o)&0x7ff))
#define BRAL2(o)		((31<<11) | ((o)&0x7ff))

#define CJUMP(c, o)		CBRA(RINV(c), o)
#define BRA(o)			(CKB((o)-4), gen(BRAU((o)-4)))
#define CBRA(c, o)		(CKBCC((o)-4), gen(BRAC(c, (o)-4)))
#define BRADIS(o)		branch(IA(patch, o)-(ulong)CODE)
#define CBRADIS(c, o)	cbranch(c, IA(patch, o)-(ulong)CODE)
#define BRAMAC(o)		branch(IA(macro, o)-(ulong)CODE)
#define RETURN		MOVHH(RLINK, RPC)
#define CALL(o)		call((ulong)(FPX(o))-(ulong)CODE)
#define CALLMAC(o)	call(IA(macro, o)-(ulong)CODE)
		
#define PATCH(ptr)		(CKB((ulong)code-(ulong)ptr-4), *ptr |= (((ulong)code-(ulong)(ptr)-4)>>1) & 0x7ff)
#define CPATCH(ptr)	(CKBCC((ulong)code-(ulong)ptr-4), *ptr |= (((ulong)code-(ulong)(ptr)-4)>>1) & 0xff)
#define BPATCH(ptr)		((ulong)ptr-(ulong)code)

/* long branches */
#define DWORD(o)		(*code++ = (o)&0xffff, *code++ = ((o)>>16)&0xffff)
#define BRALONG(o)		(LDWPCREL(0, RCON), MOVRH(RCON, RPC), DWORD(o+(ulong)code-4))
#define CALLLONG(o)	(MOVHR(RPC, RCON), DPIR(Add, 10, RCON), MOVRH(RCON, RLINK), BRALONG(o))

#define PAD()		MOVHH(RSB, RSB)

#define BITS(B)				(1<<B)

#define FITS8(v)	((ulong)(v)<BITS(8))
#define FITS5(v)	((ulong)(v)<BITS(5))
#define FITS3(v)	((ulong)(v)<BITS(3))

/* assumes H==-1 */
#define CMPH(r, scr)		DPIRR(Add, 1, r, scr)
#define NOTNIL(r, scr)	(CMPH(r, scr), label = code, CJUMP(EQ, NOBR), CALL(bounds), CPATCH(label))

#define ADDSP(o)	*code++ = (11<<12) | (0<<7) | (o>>2)
#define SUBSP(o)	*code++ = (11<<12) | (1<<7) | (o>>2)
#define LDSP(o, r)	*code++ = (19<<11) | (r<<8) | (o>>2)
#define STSP(o, r)	*code++ = (18<<11) | (r<<8) | (o>>2)

static	ushort*	code;
static	ushort*	base;
static	ulong*	patch;
static	ulong	codeoff;
static	Module*	mod;
static	uchar*	tinit;
static	ushort*	litpool;
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
extern	void	das(ushort*, int);

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
	ushort*	code;
	ushort*	pc;
};

typedef struct Con Con;
struct Con
{
	int	ptr;
	Const	table[NCON];	
};
static Con rcon;

static void gen(ulong), genc(ulong);

/* only CBRADIS could be too long by the look of things */
static void
cbranch(int c, long o)
{
	long off = o-4;

	if(pass == FIRSTPASS || (off >= -256 && off <= 254))
		CBRA(c, o);
	else if(off >= -2046 && off <= 2048){
		CBRA(RINV(c), 4);
		BRA(o-2);
	}
	else{
		if(!((int)CODE&2))
			PAD();
		CBRA(RINV(c), 10);
		BRALONG(o);
	}
}

/* only BRADIS, BRAMAC could be too long */
static void
branch(long o)
{
	long off = o-4;

	if(pass == FIRSTPASS || (off >= -2048 && off <= 2046))
		BRA(o);
	else{
		if((int)CODE&2)
			PAD();
		BRALONG(o);
	}
}

static void
call(long o)
{
	long off = o-4;

	if(pass == FIRSTPASS || (off >= -4194304 && off <= 4194302))
		genc(o);
	else{
		if(!((int)CODE&2))
			PAD();
		CALLLONG(o);
	}
}

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

static void
genc(ulong o)
{
	o -= 4;
	CKBL(o);
	*code++ = BRAL1(o>>12);
	*code++ = BRAL2(o>>1);
}
	
static void
flushcon(int genbr)
{
	int i;
	Const *c;
	ulong disp;

	if(rcon.ptr == 0)
		return;
	if(genbr ^ (((int)CODE&2)>>1))
		PAD();
	if(genbr)
		BRA(rcon.ptr*4+2);
	c = &rcon.table[0];
	for(i = 0; i < rcon.ptr; i++) {
		if(pass == LASTPASS){
			disp = (code - c->code) * sizeof(*code) - 4;
			if(disp >= BITS(10))
				print("error: INVALID constant range %lud", disp);
			CKLPCR(disp, R0);	// any reg will do
			if(disp & 3)
				disp += 2;		// ensure M(4) offset
			*c->code |= (disp/4);
		}
		*code++ = (c->o)&0xffff;
		*code++ = (c->o >> 16)&0xffff;
		c++;
	}
	rcon.ptr = 0;
}

static void
flushchk(void)
{
	if(rcon.ptr >= NCON || rcon.ptr > 0 && (code+codeoff+2-rcon.table[0].pc)*sizeof(*code) >= BITS(10)-256)  // 256 allows for a little delay in calling flushchk
		flushcon(1);
}

static void
con(ulong o, int r, int opt)
{
	Const *c;

	LOWREG(r, "con");
	if(opt != 0) {
		if(o >= 0 && o <= 255){
			DPIR(Mov, o, r);
			return;
		}
		if(-o >= 0 && -o <= 255){
			DPIR(Mov, -o, r);
			DPRR(Neg, r, r);
			return;
		}
		if(o >= 256 && o <= 510){
			DPIR(Mov, 255, r);
			DPIR(Add, o-255, r);
			return;
		}
		if(o > 0){
			int n = 0;
			ulong m = o;

			while(!(m & 1)){
				n++;
				m >>= 1;
			}
			if(m >= 0 && m <= 255){
				DPIR(Mov, m, r);
				DPIRRS(Lsl, n, r, r);
				return;
			}
		}
	}
	flushchk();
	c = &rcon.table[rcon.ptr++];
	c->o = o;
	c->code = code;
	c->pc = code+codeoff;
	LDWPCREL(0, r);
}

static void
mem(int inst, ulong disp, int rm, int r)
{
	LOWREG(rm, "mem");
	LOWREG(r, "mem");
	LOWREG(RCON, "mem");
	if(inst == Lea) {
		if(rm == r){
			if(disp < BITS(8)){
				DPIR(Add, disp, r);
				return;
			}
			if(-disp < BITS(8)){
				DPIR(Sub, -disp, r);
				return;
			}
		}
		else{
			if(disp < BITS(3)){
				DPIRR(Add, disp, rm, r);
				return;
			}
			if(-disp < BITS(3)){
				DPIRR(Sub, -disp, rm, r);
				return;
			}
		}
		con(disp, RCON, 1);
		DPRRR(Add, RCON, rm, r);
		return;
	}

	switch(inst) {
	case Ldw:
		if(disp < BITS(7)){
			LDW(rm, disp, r);
			return;
		}
		break;
	case Ldb:
		if(disp < BITS(5)){
			LDB(rm, disp, r);
			return;
		}
		break;
	case Stw:
		if(disp < BITS(7)){
			STW(rm, disp, r);
			return;
		}
		break;
	case Stb:
		if(disp < BITS(5)){
			STB(rm, disp, r);
			return;
		}
		break;
	}

	con(disp, RCON, 1);
	switch(inst) {
	case Ldw:
		LDRW(rm, RCON, r);
		break;
	case Ldb:
		LDRB(rm, RCON, r);
		break;
	case Stw:
		STRW(rm, RCON, r);
		break;
	case Stb:
		STRB(rm, RCON, r);
		break;
	}
}

static void
memh(int inst, ulong disp, int rm, int r)
{
	HIGHREG(r, "memh");
	if(inst == Stw || inst == Stb)
		MOVHR(r, RCON);
	mem(inst, disp, rm, RCON);
	if(inst != Stw && inst != Stb)
		MOVRH(RCON, r);
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
	if(mi == Lea || mi == Ldb || mi == Ldw)
		rta = r;
	else if(r == RA3)	/* seems safe - have to squeeze reg use */
		rta = RA2;
	else
		rta = RA3;
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
literal(ulong imm, int roff)
{
	nlit++;

	con((ulong)litpool, RCON, 0);
	mem(Stw, roff, RREG, RCON);

	if(pass != LASTPASS)
		return;

	*litpool++ = imm&0xffff;
	*litpool++ = (imm>>16)&0xffff;
}

static void
schedcheck(Inst *i)
{
	ushort *label;

	if(RESCHED && i->d.ins <= i){
		mem(Ldw, O(REG, IC), RREG, RA0);
		DPIR(Sub, 1, RA0);
		mem(Stw, O(REG, IC), RREG, RA0);
		/* CMPI(1, RA0); */
		label = code;
		CBRA(LE, NOBR);
		/* CJUMP(LE, NOBR); */
		CALLMAC(MacRELQ);
		CPATCH(label);
	}
}

static void
bounds(void)
{
	/* mem(Stw, O(REG,FP), RREG, RFP); */
	error(exBounds);
}

/*
static void
called(int x)
{
	extern void ttrace(void);

	if(x)
		mem(Stw, O(REG, FP), RREG, RFP);
	CALL(ttrace);
	con((ulong)&R, RREG, 1);
	mem(Ldw, O(REG, FP), RREG, RFP);
	mem(Ldw, O(REG, MP), RREG, RMP);
}
*/

static void
punt(Inst *i, int m, void (*fn)(void))
{
	ulong pc;
	ushort *label;

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
		CMPI(0, RA0);
		label = code;
		CJUMP(NE, NOBR);
		memh(Ldw, O(REG, xpc), RREG, RLINK);
		RETURN;		/* if(R.t) goto(R.xpc) */
		CPATCH(label);
	}
	mem(Ldw, O(REG, FP), RREG, RFP);
	mem(Ldw, O(REG, MP), RREG, RMP);

	if(m & NEWPC){
		memh(Ldw, O(REG, PC), RREG, RPC);
		flushcon(0);
	}
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
		CMPI(i->s.imm, RA1);
		r = swapbraop(r);
	} else if((i->add & ARM) == AXIMM && FITS8(i->reg)) {
		opwld(i, Ldw, RA1);
		CMPI(i->reg, RA1);
	} else {
		opwld(i, Ldw, RA0);
		mid(i, Ldw, RA1);
		CMP(RA1, RA0);
	}
	CBRADIS(r, i->d.ins-mod->prog);
}

static void
cbrab(Inst *i, int r)
{
	if(RESCHED)
		schedcheck(i);
	if(UXSRC(i->add) == SRC(AIMM)) {
		mid(i, Ldb, RA1);
		CMPI(i->s.imm&0xff, RA1);
		r = swapbraop(r);
	} else if((i->add & ARM) == AXIMM) {
		opwld(i, Ldb, RA1);
		CMPI(i->reg&0xff, RA1);
	} else {
		opwld(i, Ldb, RA0);
		mid(i, Ldb, RA1);
		CMP(RA1, RA0);
	}
	CBRADIS(r, i->d.ins-mod->prog);
}

static void
cbral(Inst *i, int jmsw, int jlsw, int mode)
{
	ulong dst;
	ushort *label;

	if(RESCHED)
		schedcheck(i);
	opwld(i, Lea, RA1);
	mid(i, Lea, RA3);
	mem(Ldw, 0, RA1, RA2);
	mem(Ldw, 0, RA3, RA0);
	CMP(RA0, RA2);
	label = nil;
	dst = i->d.ins-mod->prog;
	switch(mode) {
	case ANDAND:
		label = code;
		CBRA(jmsw, NOBR);
		break;
	case OROR:
		CBRADIS(jmsw, dst);
		break;
	case EQAND:
		CBRADIS(jmsw, dst);
		label = code;
		CBRA(NE, NOBR);
		break;
	}
	mem(Ldw, 4, RA3, RA0);
	mem(Ldw, 4, RA1, RA2);
	CMP(RA0, RA2);
	CBRADIS(jlsw, dst);
	if(label != nil)
		CPATCH(label);
}

static void
cbraf(Inst *i, int r)
{
	USED(r);
	if(RESCHED)
		schedcheck(i);
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
		BRAMAC(MacCASE);
	}

	t = (WORD*)(mod->origmp+i->d.ind+4);
	l = t[-1];
	
	/* have to take care not to relocate the same table twice - 
	 * the limbo compiler can duplicate a case instruction
	 * during its folding phase
	 */

	if(pass == FIRSTPASS || pass == MIDDLEPASS) {
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
	if(pass == FIRSTPASS || pass == MIDDLEPASS) {
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
	ushort *punt, *mlnil;

	opwld(i, Ldw, RA0);
	CMPH(RA0, RA3);
	mlnil = code;
	CBRA(EQ, NOBR);

	if((i->add&ARM) == AXIMM) {
		mem(Ldw, OA(Modlink, links)+i->reg*sizeof(Modl)+O(Modl, frame), RA0, RA3);
	} else {
		mid(i, Ldw, RA1);
		// RA1 = RA0 + (RA1<<3)
		DPIRRS(Lsl, 3, RA1, RA1);
		DPRRR(Add, RA0, RA1, RA1);	// assumes sizeof(Modl) == 8
		mem(Ldw, OA(Modlink, links)+O(Modl, frame), RA1, RA3);
	}

	mem(Ldw, O(Type, initialize), RA3, RA1);
	CMPI(0, RA1);
	punt = code;
	CBRA(NE, NOBR);

	opwst(i, Lea, RA0);

	/* Type in RA3, destination in RA0 */
	CPATCH(mlnil);
	con(RELPC(patch[i-mod->prog+1]), RA2, 0);
	MOVRH(RA2, RLINK);
	BRAMAC(MacMFRA);

	/* Type in RA3 */
	CPATCH(punt);
	CALLMAC(MacFRAM);
	opwst(i, Stw, RA2);
}

static void
commcall(Inst *i)
{
	ushort *mlnil;

	opwld(i, Ldw, RA2);
	con(RELPC(patch[i-mod->prog+1]), RA0, 0);
	mem(Stw, O(Frame, lr), RA2, RA0);
	mem(Stw, O(Frame, fp), RA2, RFP);
	mem(Ldw, O(REG, M), RREG, RA3);
	mem(Stw, O(Frame, mr), RA2, RA3);
	opwst(i, Ldw, RA3);
	CMPH(RA3, RA0);
	mlnil = code;
	CBRA(EQ, NOBR);
	if((i->add&ARM) == AXIMM) {
		mem(Ldw, OA(Modlink, links)+i->reg*sizeof(Modl)+O(Modl, u.pc), RA3, RA0);
	} else {
		mid(i, Ldw, RA1);
		DPIRRS(Lsl, 3, RA1, RA1);
		DPRRR(Add, RA1, RA3, RA1);	// assumes sizeof(Modl) == 8
		mem(Ldw, OA(Modlink, links)+O(Modl, u.pc), RA1, RA0);
	}
	CPATCH(mlnil);
	CALLMAC(MacMCAL);
}

static void
larith(Inst *i, int op, int opc)
{
	opwld(i, Lea, RA0);
	mid(i, Lea, RA3);
	mem(Ldw, 4, RA0, RA1);	// ls (big endian `big' even in little endian mode)
	mem(Ldw, 4, RA3, RA2);
	if(op == Add || op == Sub)
		DPRRR(op, RA1, RA2, RA2);
	else
		DPRR(op, RA1, RA2);		// ls: RA2 = RA2 op RA1
	mem(Ldw, 0, RA0, RA1);
	mem(Ldw, 0, RA3, RA0);
	DPRR(opc, RA1, RA0);		// ms: RA0 = RA0 opc RA1
	if((i->add&ARM) != AXNON)
		opwst(i, Lea, RA3);
	mem(Stw, 0, RA3, RA0);
	mem(Stw, 4, RA3, RA2);
}

static void
movloop(Inst *i, int s)
{
	ushort *label;

	opwst(i, Lea, RA2);
	label = code;
	if(s == 1)
		LDB(RA1, 0, RA0);
	else
		LDW(RA1, 0, RA0);
	DPIR(Add, s, RA1);
	if(s == 1)
		STB(RA2, 0, RA0);
	else
		STW(RA2, 0, RA0);
	DPIR(Add, s, RA2);
	DPIR(Sub, 1, RA3);
	CBRA(NE, BPATCH(label));
}

static void
movmem(Inst *i)
{
	ushort *cp;

	// source address already in RA1
	if((i->add&ARM) != AXIMM){
		mid(i, Ldw, RA3);
		CMPI(0, RA3);
		cp = code;
		CBRA(LE, NOBR);
		movloop(i, 1);
		CPATCH(cp);
		return;
	}
	switch(i->reg){
	case 0:
		break;
	case 4:
		LDW(RA1, 0, RA2);
		opwst(i, Stw, RA2);
		break;
	case 8:
		LDW(RA1, 0, RA2);
		opwst(i, Lea, RA3);
		LDW(RA1, 4, RA1);
		STW(RA3, 0, RA2);
		STW(RA3, 4, RA1);
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
	DPIRRS(Lsl, 2, RA1, RA1);
	LDRW(RA0, RA1, RA0);
	MOVRH(RA0, RPC);
	flushcon(0);

	if(pass != LASTPASS)
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
	ushort *label, *label1;

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
	// case ILSRW:
	case ILSRL:
	case IMODW:
	case IMODB:
	case IDIVW:
	case IDIVB:
		punt(i, SRCOP|DSTOP|THREOP, optab[i->op]);
		break;
/*
	case IMODW:
	case IMODB:
	case IDIVW:
	case IDIVB:
		SUBSP(8);
		mid(i, Ldw, RA0);
		MOVRH(RA0, RTMP);
		opwld(i, Ldw, RA0);
		STSP(4, RA0);			// movw RA0, 4(SP)
		call 					// need to save, restore context
		MOVHR(RTMP, RA0);
		opwst(i, Stw, RA0);
		ADDSP(8);
*/
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
	// case IHEADB:
	// case IHEADW:
	// case IHEADL:
	// case IHEADF:
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
		//comcase(i, 0);
		//punt(i, SRCOP|DSTOP|NEWPC, optab[i->op]); break;
		break;
	case IGOTO:
		comgoto(i);
		//punt(i, SRCOP|DSTOP|NEWPC, optab[i->op]); break;
		break;
	case IMOVL:
	case IMOVF:
		opwld(i, Lea, RA1);
		LDW(RA1, 0, RA2);
		LDW(RA1, 4, RA3);
		opwst(i, Lea, RA1);
		STW(RA1, 0, RA2);
		STW(RA1, 4, RA3);
		break;
	case IHEADM:
		//punt(i, SRCOP|DSTOP, optab[i->op]); break;
		opwld(i, Ldw, RA1);
		NOTNIL(RA1, RA2);
		DPIR(Add, OA(List,data), RA1);
		movmem(i);
		break;
	case IMOVM:
		//punt(i, SRCOP|DSTOP, optab[i->op]); break;
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
	case IHEADW:
		opwld(i, Ldw, RA0);
		mem(Ldw, OA(List, data), RA0, RA0);
		opwst(i, Stw, RA0);
		break;
	case IHEADB:
		opwld(i, Ldw, RA0);
		mem(Ldb, OA(List, data), RA0, RA0);
		opwst(i, Stb, RA0);
		break;
	case IHEADL:
	case IHEADF:
		opwld(i, Ldw, RA0);
		mem(Lea, OA(List, data), RA0, RA0);
		LDW(RA0, 0, RA1);
		LDW(RA0, 4, RA2);
		opwst(i, Lea, RA0);
		STW(RA0, 0, RA1);
		STW(RA0, 4, RA2);
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
		NOTNIL(RA0, RA1);
		mem(Ldw, O(List, tail), RA0, RA1);
		goto movp;
	case IMOVP:
		opwld(i, Ldw, RA1);
		goto movp;
	case IHEADP:
		opwld(i, Ldw, RA0);
		NOTNIL(RA0, RA1);
		mem(Ldw, OA(List, data), RA0, RA1);
	movp:
		CMPH(RA1, RA2);
		label = code;
		CJUMP(NE, NOBR);
		CALLMAC(MacCOLR);		// colour if not H
		CPATCH(label);
		opwst(i, Lea, RA2);
		mem(Ldw, 0, RA2, RA0);
		mem(Stw, 0, RA2, RA1);
		CALLMAC(MacFRP);
		break;
	case ILENA:
		opwld(i, Ldw, RA1);
		con(0, RA0, 1);
		CMPH(RA1, RA2);
		CJUMP(NE, 4);
		LDW(RA1, O(Array,len), RA0);
		opwst(i, Stw, RA0);
		break;
	case ILENC:
		opwld(i, Ldw, RA1);
		con(0, RA0, 1);
		CMPH(RA1, RA2);
		label = code;
		CJUMP(NE, NOBR);
		mem(Ldw, O(String,len),RA1, RA0);
		CPATCH(label);
		CMPI(0, RA0);
		CJUMP(LT, 4);
		DPRR(Neg, RA0, RA0);
		opwst(i, Stw, RA0);
		break;
	case ILENL:
		con(0, RA0, 1);
		opwld(i, Ldw, RA1);

		label = code;
		CMPH(RA1, RA2);
		label1 = code;
		CJUMP(NE, NOBR);
		LDW(RA1, O(List, tail), RA1);
		DPIR(Add, 1, RA0);
		BRA(BPATCH(label));
		CPATCH(label1);

		opwst(i, Stw, RA0);
		break;
	case ICALL:
		opwld(i, Ldw, RA0);
		con(RELPC(patch[i-mod->prog+1]), RA1, 0);
		mem(Stw, O(Frame, lr), RA0, RA1);
		mem(Stw, O(Frame, fp), RA0, RFP);
		MOV(RA0, RFP);
		BRADIS(i->d.ins-mod->prog);
		flushcon(0);
		break;
	case IJMP:
		if(RESCHED)
			schedcheck(i);
		BRADIS(i->d.ins-mod->prog);
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
		//punt(i, TCHECK|NEWPC, optab[i->op]); break;
		mem(Ldw, O(Frame,t), RFP, RA1);
		BRAMAC(MacRET);
		break;
	case IMULW:
		opwld(i, Ldw, RA1);
		mid(i, Ldw, RA0);
		MUL(RA1, RA0);
		opwst(i, Stw, RA0);
		break;
	case IMULB:
		opwld(i, Ldb, RA1);
		mid(i, Ldb, RA0);
		MUL(RA1, RA0);
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
		if((r == Add || r == Sub) && UXSRC(i->add) == SRC(AIMM) && FITS3(i->s.imm)){
			DPIRR(r, i->s.imm, RA1, RA0);
			opwst(i, Stw, RA0);
		}
		else {
			opwld(i, Ldw, RA0);
			if(r == Add || r == Sub){
				DPRRR(r, RA0, RA1, RA0);
				opwst(i, Stw, RA0);
			}
			else{
				DPRR(r, RA0, RA1);
				opwst(i, Stw, RA1);
			}
		}
		break;
	case ISHRW:
		r = Asr;
	shiftw:
		mid(i, Ldw, RA1);
		if(UXSRC(i->add) == SRC(AIMM) && FITS5(i->s.imm)){
			DPIRRS(r, i->s.imm, RA1, RA0);
			opwst(i, Stw, RA0);
		}
		else {
			opwld(i, Ldw, RA0);
			DPRR(r, RA0, RA1);
			opwst(i, Stw, RA1);
		}
		break;
	case ISHLW:
		r = Lsl;
		goto shiftw;
		break;
	case ILSRW:
		r = Lsr;
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
		if((r == Add || r == Sub) && UXSRC(i->add) == SRC(AIMM) && FITS3(i->s.imm)){
			DPIRR(r, i->s.imm, RA1, RA0);
			opwst(i, Stb, RA0);
		}
		else {
			opwld(i, Ldb, RA0);
			if(r == Add || r == Sub){
				DPRRR(r, RA0, RA1, RA0);
				opwst(i, Stb, RA0);
			}
			else{
				DPRR(r, RA0, RA1);
				opwst(i, Stb, RA1);
			}
		}
		break;
	case ISHRB:
		r = Asr;
		goto shiftb;
	case ISHLB:
		r = Lsl;
	shiftb:
		mid(i, Ldb, RA1);
		if(UXSRC(i->add) == SRC(AIMM) && FITS5(i->s.imm)){
			DPIRRS(r, i->s.imm, RA1, RA0);
			opwst(i, Stb, RA0);
		}
		else {
			opwld(i, Ldw, RA0);
			DPRR(r, RA0, RA1);
			opwst(i, Stb, RA1);
		}
		break;
	case IINDC:
		opwld(i, Ldw, RA1);			// RA1 = string
		NOTNIL(RA1, RA2);
		imm = 1;
		if((i->add&ARM) != AXIMM || !FITS8((short)i->reg<<1)){
			mid(i, Ldw, RA2);			// RA2 = i
			imm = 0;
		}
		mem(Ldw, O(String,len),RA1, RA0);	// len<0 => index Runes, otherwise bytes
		// BUG: check !((ulong)i >= abs(a->len))
		DPIR(Add, O(String,data), RA1);
		CMPI(0, RA0);
		if(imm){
			label = code;
			CJUMP(GE, NOBR);
			if(i->reg < BITS(5))
				LDB(RA1, i->reg, RA3);
			else{
				con(i->reg, RCON, 1);
				LDRB(RA1, RCON, RA3);
			}
			CPATCH(label);
			label = code;
			CJUMP(LT, NOBR);
			if((ushort)((short)i->reg<<1) < BITS(6))
				LDH(RA1, (short)i->reg<<1, RA3);
			else{
				con((short)i->reg<<1, RCON, 1);
				LDRH(RA1, RCON, RA3);
			}
			CPATCH(label);
		} else {
			CJUMP(GE, 4);
			LDRB(RA1, RA2, RA3);
			CJUMP(LT, 6);
			DPIRRS(Lsl, 1, RA2, RA2);
			LDRH(RA1, RA2, RA3);
		}
		opwst(i, Stw, RA3);
		break;
	case IINDL:
	case IINDF:
	case IINDW:
	case IINDB:
		opwld(i, Ldw, RA0);			/* a */
		NOTNIL(RA0, RA1);
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
		if(UXDST(i->add) == DST(AIMM) && FITS8(i->d.imm<<r)) {
			DPIR(Add, (i->d.imm<<r), RA0);
		} else {
			opwst(i, Ldw, RA1);
			DPIRRS(Lsl, r, RA1, RA1);
			DPRRR(Add, RA0, RA1, RA0);
		}
		mid(i, Stw, RA0);
		break;
	case IINDX:
		opwld(i, Ldw, RA0);			/* a */
		NOTNIL(RA0, RA1);
		opwst(i, Ldw, RA1);			/* i */

		mem(Ldw, O(Array, t), RA0, RA2);
		mem(Ldw, O(Array, data), RA0, RA0);
		mem(Ldw, O(Type, size), RA2, RA2);
		MUL(RA2, RA1);
		DPRRR(Add, RA0, RA1, RA0);
		mid(i, Stw, RA0);
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
		DPIRRS(Asr, 16, RA1, RA0);
		DPIRRS(Asr, 16, RA0, RA0);
		STW(RA2, 0, RA0);
		STW(RA2, 4, RA1);
		break;
	case ICVTLW:
		opwld(i, Lea, RA0);
		mem(Ldw, 4, RA0, RA0);
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
	// case IMOVF:
	//	punt(i, SRCOP|DSTOP, optab[i->op]);
	//	break;
	case IDIVF:
		goto arithf;
	case IMULF:
		goto arithf;
	case ISUBF:
		goto arithf;
	case IADDF:
	arithf:
		punt(i, SRCOP|DSTOP|THREOP, optab[i->op]);
		break;
	case INEGF:
		punt(i, SRCOP|DSTOP, optab[i->op]);
		break;
	case ICVTWF:
		punt(i, SRCOP|DSTOP, optab[i->op]);
		break;
	case ICVTFW:
		punt(i, SRCOP|DSTOP, optab[i->op]);
		break;
	case ISHLL:
		punt(i, SRCOP|DSTOP|THREOP, optab[i->op]);
		break;
	case ISHRL:
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
	code = (ushort*)comvec;

	con((ulong)&R, RREG, 0);
	memh(Stw, O(REG, xpc), RREG, RLINK);
	mem(Ldw, O(REG, FP), RREG, RFP);
	mem(Ldw, O(REG, MP), RREG, RMP);
	memh(Ldw, O(REG, PC), RREG, RPC);
	pass = LASTPASS;
	flushcon(0);
	pass = FIRSTPASS;
	// print("preamble\n");
	// das((ushort*)comvec, code-(ushort*)comvec);
	segflush(comvec, 10 * sizeof(*code));
	comvec =(void *)((ulong)comvec | 1);	/* T bit */
}

static void
maccase(void)
{
	ushort *cp1, *loop, *inner, *label;
/*
 * RA1, RHT = value (input arg), t
 * RA2 = count, n
 * RA3 = table pointer (input arg)
 * RA0  = n/2, n2
 * RCON  = pivot element t+n/2*3, l
 */
	MOVRH(RA1, RHT);
	LDW(RA3, 0, RA2);	// count from table
	MOVRH(RA3, RLINK);	// initial table pointer

	loop = code;			// loop:
	CMPI(0, RA2);
	cp1 = code;
	CBRA(LE, NOBR);	// n <= 0? goto out

	inner = code;
	DPIRRS(Lsr, 1, RA2, RA0);
	DPIRRS(Lsl, 1, RA0, RCON);
	DPRRR(Add, RA0, RCON, RCON);
	DPIRRS(Lsl, 2, RCON, RCON);
	DPRRR(Add, RA3, RCON, RCON);

	LDW(RCON, 4, RA1);
	CMPRH(RA1, RHT);
	label = code;
	CJUMP(LT, NOBR);
	MOV(RA0, RA2);
	BRA(BPATCH(loop));	// v < l[1]? goto loop
	CPATCH(label);

	LDW(RCON, 8, RA1);
	CMPRH(RA1, RHT);
	CJUMP(LT, 6);
	LDW(RCON, 12, RA1);
	MOVRH(RA1, RPC);	// v >= l[1] && v < l[2] => found; goto l[3]

	// v >= l[2] (high)
	DPIRR(Add, 7, RCON, RA3);
	DPIR(Add, 5, RA3);
	DPIRR(Add, 1, RA0, RA1);
	DPRRR(Sub, RA1, RA2, RA2);
	CBRA(GT, BPATCH(inner));	// n > 0? goto loop

	CPATCH(cp1);	// out:
	MOVHR(RLINK, RA2);
	LDW(RA2, 0, RA2);		// initial n
	DPIRRS(Lsl, 1, RA2, RA0);
	DPRRR(Add, RA2, RA0, RA2);
	DPIRRS(Lsl, 2, RA2, RA2);
	DPRH(Add, RA2, RLINK);
	MOVHR(RLINK, RA2);
	LDW(RA2, 4, RA1);
	MOVRH(RA1, RPC);		// goto (initial t)[n*3+1]
}

static void
macfrp(void)
{
	ushort *label;

	/* destroy the pointer in RA0 */
	CMPH(RA0, RA2);
	CJUMP(EQ, 4);
	RETURN;		// arg == H? => return

	mem(Ldw, O(Heap, ref)-sizeof(Heap), RA0, RA2);
	DPIR(Sub, 1, RA2);
	label = code;
	CJUMP(NE, NOBR);
	mem(Stw, O(Heap, ref)-sizeof(Heap), RA0, RA2);
	RETURN;		// --h->ref != 0 => return
	CPATCH(label);

	mem(Stw, O(REG, FP), RREG, RFP);
	memh(Stw, O(REG, st), RREG, RLINK);
	mem(Stw, O(REG, s), RREG, RA0);
	CALL(rdestroy);
	con((ulong)&R, RREG, 1);
	memh(Ldw, O(REG, st), RREG, RLINK);
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
	DPIR(Add, 1, RA0);
	mem(Stw, O(Heap, ref)-sizeof(Heap), RA1, RA0);	// h->ref++
	con((ulong)&mutator, RA2, 1);
	mem(Ldw, O(Heap, color)-sizeof(Heap), RA1, RA0);
	mem(Ldw, 0, RA2, RA2);
	CMP(RA2, RA0);
	CJUMP(EQ, 4);
	RETURN;	// return if h->color == mutator
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
	ushort *cp1, *cp2, *cp3, *cp4, *cp5, *linterp;

	CMPI(0, RA1);
	cp1 = code;
	CBRA(EQ, NOBR);				// t(Rfp) == 0

	mem(Ldw, O(Type,destroy),RA1, RA0);
	CMPI(0, RA0);
	cp2 = code;
	CBRA(EQ, NOBR);				// destroy(t(fp)) == 0

	mem(Ldw, O(Frame,fp),RFP, RA2);
	CMPI(0, RA2);
	cp3 = code;
	CBRA(EQ, NOBR);				// fp(Rfp) == 0

	mem(Ldw, O(Frame,mr),RFP, RA3);
	CMPI(0, RA3);
	cp4 = code;
	CBRA(EQ, NOBR);				// mr(Rfp) == 0

	mem(Ldw, O(REG,M),RREG, RA2);
	mem(Ldw, O(Heap,ref)-sizeof(Heap),RA2, RA3);
	DPIR(Sub, 1, RA3);
	cp5 = code;
	CBRA(EQ, NOBR);				// --ref(arg) == 0
	mem(Stw, O(Heap,ref)-sizeof(Heap),RA2, RA3);

	mem(Ldw, O(Frame,mr),RFP, RA1);
	mem(Stw, O(REG,M),RREG, RA1);
	mem(Ldw, O(Modlink,MP),RA1, RMP);
	mem(Stw, O(REG,MP),RREG, RMP);
	mem(Ldw, O(Modlink,compiled), RA1, RA3);	// R.M->compiled
	CMPI(0, RA3);
	linterp = code;
	CBRA(EQ, NOBR);

	CPATCH(cp4);
	MOVHH(RPC, RLINK);		// call destroy(t(fp))
	MOVRH(RA0, RPC);

	mem(Stw, O(REG,SP),RREG, RFP);
	mem(Ldw, O(Frame,lr),RFP, RA1);
	mem(Ldw, O(Frame,fp),RFP, RFP);
	mem(Stw, O(REG,FP),RREG, RFP);	// R.FP = RFP
	MOVRH(RA1, RPC);

	CPATCH(linterp);
	MOVHH(RPC, RLINK);		// call destroy(t(fp))
	MOVRH(RA0, RPC);

	mem(Stw, O(REG,SP),RREG, RFP);
	mem(Ldw, O(Frame,lr),RFP, RA1);
	mem(Ldw, O(Frame,fp),RFP, RFP);
	mem(Stw, O(REG,PC),RREG, RA1);	// R.PC = fp->lr
	mem(Stw, O(REG,FP),RREG, RFP);	// R.FP = RFP
	memh(Ldw, O(REG, xpc), RREG, RLINK);
	RETURN;		// return to xec uncompiled code

	CPATCH(cp1);
	CPATCH(cp2);
	CPATCH(cp3);
	CPATCH(cp5);
	i.add = AXNON;
	punt(&i, TCHECK|NEWPC, optab[IRET]);
}

static void
macmcal(void)
{
	ushort *lab, *label;

	CMPH(RA0, RA1);
	label = code;
	CJUMP(NE, NOBR);
	mem(Ldw, O(Modlink, prog), RA3, RA1);	// RA0 != H
	CMPI(0, RA1);	// RA0 != H
	lab = code;
	CBRA(NE, NOBR);	// RA0 != H && m->prog!=0
	CPATCH(label);

	memh(Stw, O(REG, st), RREG, RLINK);
	mem(Stw, O(REG, FP), RREG, RA2);
	mem(Stw, O(REG, dt), RREG, RA0);
	CALL(rmcall);				// CALL rmcall

	con((ulong)&R, RREG, 1);		// MOVL	$R, RREG
	memh(Ldw, O(REG, st), RREG, RLINK);
	mem(Ldw, O(REG, FP), RREG, RFP);
	mem(Ldw, O(REG, MP), RREG, RMP);
	RETURN;

	CPATCH(lab);				// patch:
	MOV(RA2, RFP);
	mem(Stw, O(REG, M), RREG, RA3);	// MOVL RA3, R.M
	mem(Ldw, O(Heap, ref)-sizeof(Heap), RA3, RA1);
	DPIR(Add, 1, RA1);
	mem(Stw, O(Heap, ref)-sizeof(Heap), RA3, RA1);
	mem(Ldw, O(Modlink, MP), RA3, RMP);	// MOVL R.M->mp, RMP
	mem(Stw, O(REG, MP), RREG, RMP);	// MOVL RA3, R.MP	R.MP = ml->m
	mem(Ldw, O(Modlink,compiled), RA3, RA1);	// M.compiled?
	CMPI(0, RA1);
	CJUMP(NE, 4);
	MOVRH(RA0, RPC);
	mem(Stw, O(REG,FP),RREG, RFP);	// R.FP = RFP
	mem(Stw, O(REG,PC),RREG, RA0);	// R.PC = RPC
	memh(Ldw, O(REG, xpc), RREG, RLINK);
	RETURN;		// return to xec uncompiled code
	flushcon(0);
}

static void
macfram(void)
{
	ushort *lab1;

	mem(Ldw, O(REG, SP), RREG, RA0);	// MOVL	R.SP, RA0
	mem(Ldw, O(Type, size), RA3, RA1);
	DPRRR(Add, RA0, RA1, RA0);
	mem(Ldw, O(REG, TS), RREG, RA1);
	CMP(RA1, RA0);	// nsp :: R.TS
	lab1 = code;
	CBRA(CS, NOBR);	// nsp >= R.TS; must expand

	mem(Ldw, O(REG, SP), RREG, RA2);	// MOVL	R.SP, RA2
	mem(Stw, O(REG, SP), RREG, RA0);	// MOVL	RA0, R.SP

	mem(Stw, O(Frame, t), RA2, RA3);	// MOVL	RA3, t(RA2) f->t = t
	con(0, RA0, 1);
	mem(Stw, O(Frame,mr), RA2, RA0);     	// MOVL $0, mr(RA2) f->mr
	memh(Ldw, O(Type, initialize), RA3, RPC);	// become t->init(RA2), returning RA2

	CPATCH(lab1);
	mem(Stw, O(REG, s), RREG, RA3);
	memh(Stw, O(REG, st), RREG, RLINK);
	mem(Stw, O(REG, FP), RREG, RFP);	// MOVL	RFP, R.FP
	CALL(extend);				// CALL	extend

	con((ulong)&R, RREG, 1);
	memh(Ldw, O(REG, st), RREG, RLINK);
	mem(Ldw, O(REG, FP), RREG, RFP);	// MOVL	R.FP, RFP
	mem(Ldw, O(REG, s), RREG, RA2);	// MOVL	R.s, *R.d
	mem(Ldw, O(REG, MP), RREG, RMP);	// MOVL R.MP, RMP
	RETURN;					// RET
}

static void
macmfra(void)
{
	memh(Stw, O(REG, st), RREG, RLINK);
	mem(Stw, O(REG, s), RREG, RA3);	// Save type
	mem(Stw, O(REG, d), RREG, RA0);	// Save destination
	mem(Stw, O(REG, FP), RREG, RFP);
	CALL(rmfram);				// CALL rmfram

	con((ulong)&R, RREG, 1);
	memh(Ldw, O(REG, st), RREG, RLINK);
	mem(Ldw, O(REG, FP), RREG, RFP);
	mem(Ldw, O(REG, MP), RREG, RMP);
	RETURN;
}

static void
macrelq(void)
{
	mem(Stw, O(REG,FP),RREG, RFP);	// R.FP = RFP
	memh(Stw, O(REG,PC),RREG, RLINK);	// R.PC = RLINK
	memh(Ldw, O(REG, xpc), RREG, RLINK);
	RETURN;
}

void
comd(Type *t)
{
	int i, j, m, c;

	memh(Stw, O(REG, dt), RREG, RLINK);
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
	memh(Ldw, O(REG, dt), RREG, RLINK);
	RETURN;
	flushcon(0);
}

void
comi(Type *t)
{
	int i, j = 0, m, c, r;

	if(t->np > 4){
		r = RA3;
		MOV(RA2, RA3);
	}
	else
		r = RA2;
	con((ulong)H, RA0, 1);
	for(i = 0; i < t->np; i++) {
		c = t->map[i];
		if(j == 128){
			if(t->np <= 4) print("error: bad j in comi\n");
			DPIR(Add, 128, RA3);
			j = 0;
		}
		for(m = 0x80; m != 0; m >>= 1) {
			if(c & m)
				mem(Stw, j, r, RA0);
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
	ushort *tmp, *start;

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

// print("type\n");
// das(start, code-start);

	if(cflag > 1)
		print("typ= %.8lux %4d i %.8lux d %.8lux asm=%d\n",
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
	ushort *s, *tmp;
	int again, lastc = 0, lastn = 0;

	base = nil;
	patch = mallocz(size*sizeof(*patch), 0);
	tinit = malloc(m->ntype*sizeof(*tinit));
	tmp = malloc(4096*sizeof(ulong));
	base = tmp;
	if(tinit == nil || patch == nil || tmp == nil)
		goto bad;

	preamble();

	mod = m;
	pass = FIRSTPASS;

	do{
		again = 0;
		n = 0;
		nlit = 0;

		for(i = 0; i < size; i++) {
			codeoff = n;
			code = tmp;
			comp(&m->prog[i]);
			if(patch[i] != n)
				again = 1;
			patch[i] = n;
			n += code - tmp;
		}

		for(i = 0; i < nelem(mactab); i++) {
			codeoff = n;
			code = tmp;
			mactab[i].gen();
			if(macro[mactab[i].idx] != n)
				again = 1;
			macro[mactab[i].idx] = n;
			n += code - tmp;
		}
		code = tmp;
		flushcon(0);
		n += code - tmp;
		if(code-tmp != lastc || n != lastn)
			again = 1;
		lastc = code-tmp;
		lastn = n;

		if(pass == FIRSTPASS)
			pass = MIDDLEPASS;

	}while(again);

	base = mallocz((n+nlit)*sizeof(*code), 0);
	if(base == nil)
		goto bad;

	if(cflag > 1)
		print("dis=%5d %5d 386=%5d asm=%.8lux: %s\n",
			size, size*sizeof(Inst), n, base, m->name);

	pass = LASTPASS;
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
			print("error: %lud != %d\n", patch[i], n);
			urk("phase error");
		}
		n += code - s;
		if(cflag > 2) {
			print("%3d %D\n", i, &m->prog[i]);
			das(s, code-s);
		}
	}

	for(i = 0; i < nelem(mactab); i++) {
		s = code;
		mactab[i].gen();
		if(macro[mactab[i].idx] != n){
			print("error: mac phase err: %lud != %d\n", macro[mactab[i].idx], n);
			urk("phase error");
		}
		n += code - s;
		if(cflag > 2) {
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
// print("comvec at %lux\n", (ulong)comvec);
// print("base at %lux-%lux\n", (ulong)base, (ulong)base+2*n);
// print("entry %lux prog %lux\n", (ulong)m->entry, (ulong)m->prog);
	return 1;
bad:
	free(patch);
	free(tinit);
	free(base);
	free(tmp);
	return 0;
}
