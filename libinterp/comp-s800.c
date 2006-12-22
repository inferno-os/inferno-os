#include "lib9.h"
#include "isa.h"
#include "interp.h"
#include "raise.h"

#define	P4(o)	((o) < (1 << 4))
#define	N4(o)	(~(o) < (1 << 4))
#define	P13(o)	((o) < (1 << 13))
#define	N13(o)	(~(o) < (1 << 13))
#define	B4(o)	((o) & M4)
#define	B11(o)	((o) & M11)
#define	B13(o)	((o) & M13)
#define	B21(o)	((o) & M21)

#define	DOT		((ulong)code)
#define RELPC(pc)	((ulong)(base+pc))

#define	nop()		arith(Aor, RZ, RZ, RZ)
#define	bra(o)		BL(RZ, (o))
#define	add(r, c)	LDSTpos(Oldo, c, r, r)
#define	displ(ix)	((ulong)(base+patch[ix]-code-2))
#define	mdispl(ix)	((ulong)(base+macro[ix]-code-2))
#define	mbra(ix)	bra(mdispl(ix))

enum
{
	R0	= 0,
	R1	= 1,
	R2	= 2,

	R19	= 19,
	R20	= 20,
	R21	= 21,
	R22	= 22,
	R23	= 23,
	R24	= 24,
	R25	= 25,
	R26	= 26,
	R27	= 27,
	R28	= 28,
	R29	= 29,
	R30	= 30,
	R31	= 31,

	RLINK	= R2,		/* Function linkage */

	RZ	= R0,		/* Always 0 */
	RFP	= R26,		/* Frame Pointer */
	RMP	= R25,		/* Module Pointer */
	RREG	= R24,		/* Pointer to REG */
	RTA	= R29,		/* Intermediate address for double indirect */
	RCON	= R23,		/* Constant builder */
	RCALL	= R31,		/* Call temp and link dest */

	RA3	= R22,		/* gpr 3 */
	RA2	= R21,		/* gpr 2 2+3 = big */
	RA1	= R20,		/* gpr 1 */
	RA0	= R19,		/* gpr 0 0+1 = big */

	RCSP	= R30,		/* C stack pointer */
	RARG0	= R26,		/* C arg0 */
	RMILLI0	= R22,		/* Millicode arg0 */

	/* Floating */
	FRZ	= 0,		/* Zero */
	FR0	= 4,
	FR1	= 5,

	/* opcodes */
	Osys	= 0x00,
	Oarith	= 0x02,
	Oldwx	= 0x03,
	Oldil	= 0x08,
	Oldo	= 0x0D,
	Oldb	= 0x10,
	Oldh	= 0x11,
	Oldw	= 0x12,
	Ostb	= 0x18,
	Osth	= 0x19,
	Ostw	= 0x1A,
	Ocombt	= 0x20,
	Ocomibt	= 0x21,
	Ocombf	= 0x22,
	Ocomibf	= 0x23,
	Oaddibt	= 0x29,
	Oaddibf	= 0x2B,
	Oextrs	= 0x34,
	Obe	= 0x38,
	Oble	= 0x39,
	Obr	= 0x3A,

	Oflldst	= 0x0B,
	Ofltc	= 0x0C,

	Ftst	= 0x2420,
	Fload	= 0,
	Fstore	= 1,

	/* psuedo opcodes */
	Pld	= 0x10,		/* base of loads */
	Pst	= 0x18,		/* base of stores */

	/* sub opcodes */
	Aand	= 0x10,
	Aor	= 0x12,
	Axor	= 0x14,
	Asub	= 0x20,
	Aadd	= 0x30,
	Ash1add	= 0x32,
	Ash2add	= 0x34,

	/* FP sub codes */
	Fadd	= 0,
	Fsub	= 1,
	Fmul	= 2,
	Fdiv	= 3,

	Sldsid	= 0x85,
	Smtsp	= 0xC1,

	/* conditions */
	Cnever	= 0,
	Cequal	= 1,
	Cless	= 2,
	Cleq	= 3,
	Clessu	= 4,
	Clequ	= 5,
	Csv	= 6,
	Codd	= 7,

	/* FP conditions */
	Fnever	= 0,
	Fequal	= 1,
	Fless	= 2,
	Fleq	= 3,
	Fgrt	= 4,
	Fgeq	= 5,
	Fneq	= 6,
	Falways	= 7,

	/* masks */
	M4	= 0xF,
	M5	= 0x1F,
	M10	= 0x3FF,
	M11	= 0x7FF,
	M13	= 0x1FFF,
	M21	= 0x1FFFFF,

	/* spaces */
	STemp	= 0,
	SCode	= 4,
	SData	= 5,

	PRESZ	= 20,

	/* punt ops */
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
	MacRET	= 1,
	MacCASE	= 2,
	MacCOLR	= 3,
	MacMCAL	= 4,
	MacFRAM	= 5,
	MacMFRA	= 6,
	NMACRO
};

static	ulong*	code;
static	ulong*	base;
static	ulong*	patch;
static	int	pass;
static	Module*	mod;
static	uchar*	tinit;
static	ulong*	litpool;
static	int	nlit;
static	void	macfrp(void);
static	void	macret(void);
static	void	maccase(void);
static	void	maccolr(void);
static	void	macmcal(void);
static	void	macfram(void);
static	void	macmfra(void);
static	ulong	macro[NMACRO];
	void	(*comvec)(void);
extern	void	das(uchar*, int);
extern ulong	*dataptr;
extern void	calldata();
extern void	calltext();
extern long	dyncall;

#define T(r)	*((void**)(R.r))

static void
prlast()
{
	print("%x\t%x\n", code - 1, code[-1]);
}

struct
{
	int	idx;
	void	(*gen)(void);
	char*	name;
} mactab[] =
{
	MacFRP,		macfrp,		"FRP",		/* decrement and free pointer */
	MacRET,		macret,		"RET",		/* return instruction */
	MacCASE,	maccase,	"CASE",		/* case instruction */
	MacCOLR,	maccolr,	"COLR",		/* increment and color pointer */
	MacMCAL,	macmcal,	"MCAL",		/* mcall bottom half */
	MacFRAM,	macfram,	"FRAM",		/* frame instruction */
	MacMFRA,	macmfra,	"MFRA",		/* punt mframe because t->initialize==0 */
};

static void
rdestroy(void)
{
	destroy(R.s);
}

static void
rmcall(void)
{
	Prog *p;
	Frame *f;

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
	if(p->kill)
		error(p->kill);
}

static void
rmfram(void)
{
	Type *t;
	Frame *f;
	uchar *nsp;

	t = (Type*)R.s;
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
urk(void)
{
	error("compile failed");
}

static int
mkspace(int s)
{
	return ((s & 4) << 11) | ((s & 3) << 14);
}

static ulong
posdisp(int disp)
{
	return (((disp & M10) << 1) | ((disp >> 10) & 1)) << 2;
}

static ulong
disp11(int disp)
{
	return posdisp(disp) | (disp < 0 ? 1 : 0);
}

static void
opatch(ulong *b)
{
	*b |= posdisp(code - b - 2);
}

static ulong
frig17(ulong v)
{
	return ((v & M10) << 3) |
		((v & (1 << 10)) >> 8) |
		((v & (M5 << 11)) << 5) |
		((v >> 16) & 1);
}

static ulong
frig21(ulong v)
{
	return ((v >> 20) & 1) |
		((v >> 8) & (M11 << 1)) |
		((v & 3) << 12) |
		((v & (3 << 7)) << 7) |
		((v & (M5 << 2)) << 14);
}

static void
BLE(int r, int off, int s)
{
	*code++ = (Oble << 26) | (r << 21) | mkspace(s) | frig17(off >> 2);
}

static void
BE(int r, int off, int s)
{
	*code++ = (Obe << 26) | (r << 21) | mkspace(s) | frig17(off);
}

static void
BL(int r, int off)
{
	*code++ = (Obr << 26) | (r << 21) | frig17(off);
}

static void
BV(int r)
{
	*code++ = (Obr << 26) | (r << 21) | (6 << 13);
}

static void
LDIL(int r, ulong imm)
{
	*code++ = (Oldil << 26) | (r << 21) | frig21(imm);
}

static void
LDWX(int i, int b, int r, int t)
{
	*code++ = (Oldwx << 26) | (b << 21) | (r << 16) | ((i - Pld) << 6) | t;
}

static void
LDSTneg(int i, ulong off, int b, int r)
{
	*code++ = (i << 26) | (b << 21) | (r << 16) | (B13(off) << 1) | 1;
}

static void
LDSTpos(int i, ulong off, int b, int r)
{
	*code++ = (i << 26) | (b << 21) | (r << 16) | (off << 1);
}

static void
FLDSTneg(int inst, ulong disp, int rm, int r)
{
	*code++ = (Oflldst << 26) | (rm << 21) | (B4(disp) << 17) | (1 << 16) | (1 << 12) | (inst << 9) | r;
}

static void
FLDSTpos(int inst, ulong disp, int rm, int r)
{
	*code++ = (Oflldst << 26) | (rm << 21) | (disp << 17) | (1 << 12) | (inst << 9) | r;
}

static void
FLDSTX(int inst, int b, int x, int r)
{
	*code++ = (Oflldst << 26) | (b << 21) | (x << 17) | (inst << 9) | r;
}

static void
FCMP(int r, int c, int b)
{
	*code++ = (Ofltc << 26) | (r << 21) | (b << 16) | (6 << 9) | (c << 2);
}

static void
FTEST()
{
	*code++ = (Ofltc << 26) | Ftst;
}

static void
farith(int o, int r1, int r2, int t)
{
	*code++ = (Ofltc << 26) | (r1 << 21) | (r2 << 16) | (o << 13) | (7 << 9) | t;
}

static void
arith(int o, int s, int m, int d)
{
	*code++ = (Oarith << 26) | (m << 21) | (s << 16) | (o << 5) | d;
}

static void
mov(int s, int d)
{
	LDSTpos(Oldo, 0, s, d);
}

static void
shrs(int r, int s, int t)
{
	*code++ = (Oextrs << 26) | (r << 21) | (t << 16) | (7 << 10) | ((31 - s) << 5) | s;
}

static void
comb(int op, int r1, int c, int r2, int off)
{
	*code++ = (op << 26) | (r2 << 21) | (r1 << 16) | (c << 13) | disp11(off);
}

static int
es5(int v)
{
	return (B4(v) << 1) | (v < 0 ? 1 : 0);
}

static void
combt(int r1, int c, int r2, int off)
{
	comb(Ocombt, r1, c, r2, off);
}

static void
comibt(int r1, int c, int v, int off)
{
	comb(Ocomibt, es5(v), c, r1, off);
}

static void
combf(int r1, int c, int r2, int off)
{
	comb(Ocombf, r1, c, r2, off);
}

static void
comibf(int r1, int c, int v, int off)
{
	comb(Ocomibf, es5(v), c, r1, off);
}

static void
combdis(int r1, int c, int r2, int f, int ix)
{
	comb(f ? Ocombf : Ocombt, r1, c, r2, displ(ix));
}

static void
addibt(int r1, int c, int v, int off)
{
	comb(Oaddibt, es5(v), c, r1, off);
}

static void
addibf(int r1, int c, int v, int off)
{
	comb(Oaddibf, es5(v), c, r1, off);
}

static void
con(ulong o, int r, int opt)
{
	if(opt) {
		if(P13(o)) {
			LDSTpos(Oldo, o, RZ, r);
			return;
		}
		if(N13(o)) {
			LDSTneg(Oldo, o, RZ, r);
			return;
		}
		LDIL(r, B21(o >> 11));
		if(B11(o) != 0)
			LDSTpos(Oldo, B11(o), r, r);
	}
	else {
		LDIL(r, B21(o >> 11));
		LDSTpos(Oldo, B11(o), r, r);
	}
}

static void
call(ulong a, int s)
{
	if (s == SCode) {
		con(a, RMILLI0, 1);
		a = dyncall;
	}
	LDIL(RCALL, a >> 11);
	BLE(RCALL, B11(a), s);
	mov(RCALL, RLINK);
}

static void
callindir(int r)
{
	BLE(r, 0, SData);
	mov(RCALL, RLINK);
}

static void
leafret()
{
	BV(RLINK);
	nop();
}

static void
linkage()
{
	LDSTneg(Ostw, -20, RCSP, RLINK);
	LDSTpos(Oldo, 64, RCSP, RCSP);
}

static void
ret()
{
	LDSTneg(Oldw, -84, RCSP, RLINK);
	BV(RLINK);
	LDSTneg(Oldo, -64, RCSP, RCSP);
}

static void
mem(int inst, ulong disp, int rm, int r)
{
	if(P13(disp)) {
		LDSTpos(inst, disp, rm, r);
		return;
	}
	if(N13(disp)) {
		LDSTneg(inst, disp, rm, r);
		return;
	}
	con(disp, RCON, 1);
	if(inst >= Pst) {
		arith(Aadd, rm, RCON, RCON);
		LDSTpos(inst, 0, RCON, r);
	}
	else
		LDWX(inst, RCON, rm, r);
}

static void
fmem(int inst, ulong disp, int rm, int r)
{
	if(P4(disp)) {
		FLDSTpos(inst, disp, rm, r);
		return;
	}
	if(N4(disp)) {
		FLDSTneg(inst, disp, rm, r);
		return;
	}
	con(disp, RCON, 1);
	FLDSTX(inst, RCON, rm, r);
}

static void
opwld(Inst *i, int mi, int r)
{
	int ir, rta;

	switch(UXSRC(i->add)) {
	default:
		print("%D\n", i);
		urk();
	case SRC(AFP):
		mem(mi, i->s.ind, RFP, r);
		return;
	case SRC(AMP):
		mem(mi, i->s.ind, RMP, r);
		return;
	case SRC(AIMM):
		con(i->s.imm, r, 1);
		return;
	case SRC(AIND|AFP):
		ir = RFP;
		break;
	case SRC(AIND|AMP):
		ir = RMP;
		break;
	}
	rta = RTA;
	if(mi == Oldo)
		rta = r;
	mem(Oldw, i->s.i.f, ir, rta);
	mem(mi, i->s.i.s, rta, r);
}

static void
opwst(Inst *i, int mi, int r)
{
	int ir, rta;

	switch(UXDST(i->add)) {
	default:
		print("%D\n", i);
		urk();
	case DST(AIMM):
		con(i->d.imm, r, 1);
		return;
	case DST(AFP):
		mem(mi, i->d.ind, RFP, r);
		return;
	case DST(AMP):
		mem(mi, i->d.ind, RMP, r);
		return;
	case DST(AIND|AFP):
		ir = RFP;
		break;
	case DST(AIND|AMP):
		ir = RMP;
		break;
	}
	rta = RTA;
	if(mi == Oldo)
		rta = r;
	mem(Oldw, i->d.i.f, ir, rta);
	mem(mi, i->d.i.s, rta, r);
}

static void
opbig(Adr *a, int am, int mi, int r)
{
	int ir;

	switch(am) {
	default:
		urk();
	case AFP:
		mem(mi, a->ind, RFP, r);
		mem(mi, a->ind+4, RFP, r+1);
		return;
	case AMP:
		mem(mi, a->ind, RMP, r);
		mem(mi, a->ind+4, RMP, r+1);
		return;
	case AIND|AFP:
		ir = RFP;
		break;
	case AIND|AMP:
		ir = RMP;
		break;
	}
	mem(Oldw, a->i.f, ir, RTA);
	mem(mi, a->i.s, RTA, r);
	mem(mi, a->i.s+4, RTA, r+1);
}

static void
opbigld(Inst *i, int r)
{
	opbig(&i->s, USRC(i->add), Oldw, r);
}

static void
opbigst(Inst *i, int r)
{
	opbig(&i->d, UDST(i->add), Ostw, r);
}

static void
opfloat(Adr *a, int am, int mi, int r)
{
	int ir;

	switch(am) {
	default:
		urk();
	case AFP:
		fmem(mi, a->ind, RFP, r);
		return;
	case AMP:
		fmem(mi, a->ind, RMP, r);
		return;
	case AIND|AFP:
		ir = RFP;
		break;
	case AIND|AMP:
		ir = RMP;
		break;
	}
	mem(Oldw, a->i.f, ir, RTA);
	fmem(mi, a->i.s, RTA, r);
}

static void
opflld(Inst *i, int r)
{
	opfloat(&i->s, USRC(i->add), Fload, r);
}

static void
opflst(Inst *i, int r)
{
	opfloat(&i->d, UDST(i->add), Fstore, r);
}

static void
midfl(Inst *i, int r)
{
	int ir;

	switch(i->add&ARM) {
	default:
		opfloat(&i->d, UDST(i->add), Fload, r);
		return;
	case AXINF:
		ir = RFP;
		break;
	case AXINM:
		ir = RMP;
		break;
	}
	fmem(Fload, i->reg, ir, r);
}

static void
literal(ulong imm, int roff)
{
	nlit++;

	con((ulong)litpool, RTA, 0);
	LDSTpos(Ostw, roff, RREG, RTA);

	if(pass == 0)
		return;

	*litpool = imm;
	litpool++;
}

static
void
compdbg(void)
{
	print("%s:%d@%.8lux\n", R.M->m->name, *(ulong *)R.m, *(ulong *)R.s);
}

static void
punt(Inst *i, int m, void (*fn)(void))
{
	ulong pc;

	if(m & SRCOP) {
		if(UXSRC(i->add) == SRC(AIMM))
			literal(i->s.imm, O(REG, s));
		else {
			opwld(i, Oldo, RA0);
			mem(Ostw, O(REG, s), RREG, RA0);
		}
	}

	if(m & DSTOP) {
		opwst(i, Oldo, RA0);
		mem(Ostw, O(REG, d), RREG, RA0);
	}

	if(m & WRTPC) {
		con(RELPC(patch[i-mod->prog+1]), RA0, 0);
		mem(Ostw, O(REG, PC), RREG, RA0);
	}

	if(m & DBRAN) {
		pc = patch[(Inst*)i->d.imm-mod->prog];
		literal(RELPC(pc), O(REG, d));
	}

	switch(i->add&ARM) {
	case AXNON:
		if(m & THREOP) {
			mem(Oldw, O(REG, d), RREG, RA0);
			mem(Ostw, O(REG, m), RREG, RA0);
		}
		break;
	case AXIMM:
		literal((short)i->reg, O(REG, m));
		break;
	case AXINF:
		mem(Oldo, i->reg, RFP, RA0);
		mem(Ostw, O(REG, m), RREG, RA0);
		break;
	case AXINM:
		mem(Oldo, i->reg, RMP, RA0);
		mem(Ostw, O(REG, m), RREG, RA0);
		break;
	}

	mem(Ostw, O(REG, FP), RREG, RFP);
	call((ulong)fn, SCode);

	con((ulong)&R, RREG, 1);
	if(m & TCHECK) {
		mem(Oldw, O(REG, t), RREG, RA0);
		combt(RA0, Cequal, RZ, 3);
		nop();				
		mem(Oldw, O(REG, xpc), RREG, RLINK);
		leafret();
	}

	mem(Oldw, O(REG, FP), RREG, RFP);
	mem(Oldw, O(REG, MP), RREG, RMP);

	if(m & NEWPC) {
		mem(Oldw, O(REG, PC), RREG, RA0);
		BV(RA0);
		nop();
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

static void
cbral(Inst *i, int jmsw, int fm, int jlsw, int fl, int mode)
{
	ulong dst, *label;

	opwld(i, Oldo, RA1);
	mid(i, Oldo, RA3);
	mem(Oldw, 0, RA1, RA2);
	mem(Oldw, 0, RA3, RA0);
	label = nil;
	dst = i->d.ins-mod->prog;
	switch(mode) {
	case ANDAND:
		label = code;
		comb(RA0, jmsw, RA2, fm, 0);
		break;
	case OROR:
		combdis(RA0, jmsw, RA2, fm, dst);
		break;
	case EQAND:
		combdis(RA0, jmsw, RA2, fm, dst);
		nop();
		label = code;
		combf(RA0, Cequal, RA2, 0);
		break;
	}
	nop();
	mem(Oldw, 4, RA3, RA0);
	mem(Oldw, 4, RA1, RA2);
	combdis(RA0, jlsw, RA2, fl, dst);
	if(label != nil)
		opatch(label);
}

static void
commcall(Inst *i)
{
	int o;

	opwld(i, Oldw, RA2);
	con(RELPC(patch[i-mod->prog+1]), RA0, 0);
	mem(Ostw, O(Frame, lr), RA2, RA0);
	mem(Ostw, O(Frame, fp), RA2, RFP);
	mem(Oldw, O(REG, M), RREG, RA3);
	mem(Ostw, O(Frame, mr), RA2, RA3);
	opwst(i, Oldw, RA3);
	o = OA(Modlink, links)+i->reg*sizeof(Modl)+O(Modl, u.pc);
	mem(Oldw, o, RA3, RA0);
	call(base+macro[MacMCAL], SData);
}

static void
comcase(Inst *i, int w)
{
	int l;
	WORD *t, *e;

	if(w != 0) {
		opwld(i, Oldw, RA0);		// v
		opwst(i, Oldo, RCON);		// table
		mbra(MacCASE);
		nop();
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
	int o;
	ulong *punt, *mlnil;

	opwld(i, Oldw, RA0);
	mlnil = code;
	comibt(RA0, Cequal, -1, 0);
	nop();
	
	o = OA(Modlink, links)+i->reg*sizeof(Modl)+O(Modl, frame);
	mem(Oldw, o, RA0, RA3);
	mem(Oldw, O(Type, initialize), RA3, RA1);
	punt = code;
	combf(RA1, Cequal, RZ, 0);
	nop();

	opwst(i, Oldo, RA0);

	/* Type in RA3, destination in RA0 */
	opatch(mlnil);
	con(RELPC(patch[i-mod->prog+1]), RLINK, 0);
	mbra(MacMFRA);
	nop();

	/* Type in RA3 */
	opatch(punt);
	call(base+macro[MacFRAM], SData);
	opwst(i, Ostw, RA2);
}

static void
movloop(Inst *i, int ld, int st)
{
	int s;

	if(ld == Oldw)
		s = 4;
	else
		s = 1;
	opwld(i, Oldo, RA1);
	opwst(i, Oldo, RA2);
	mem(ld, 0, RA1, RA0);
	mem(st, 0, RA2, RA0);
	add(RA2, s);
	addibf(RA3, Cequal, -1, -5);
	add(RA1, s);
}

static void
comp(Inst *i)
{
	int r, f;
	WORD *t, *e;
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
	case IMULW:
	case IDIVW:
	case IMODW:
	case IMULB:
	case IDIVB:
	case IMODB:
	case ISHRW:
	case ISHLW:
	case ISHRB:
	case ISHLB:
	case IADDL:
	case ISUBL:
	case IORL:
	case IANDL:
	case IXORL:
	case ICVTWL:
	case ISHLL:
	case ISHRL:
	case IINDX:
		punt(i, SRCOP|DSTOP|THREOP, optab[i->op]);
		break;
	case ILOAD:
	case INEWA:
	case INEW:
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
	case IHEADM:
	case IHEADB:
	case IHEADW:
	case IHEADL:
	case IHEADF:
	case IINDC:
	case ILENC:
	case IINSC:
	case ICVTAC:
	case ICVTCW:
	case ICVTWC:
	case ICVTLC:
	case ICVTCL:
	case ICVTFC:
	case ICVTCF:
	case ICVTFL:
	case ICVTLF:
	case ICVTWF:
	case ICVTFW:
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
		// comcase(i, 0);
		// punt(i, SRCOP|DSTOP|NEWPC, optab[i->op]);
		break;
	case IGOTO:
		opwld(i, Oldw, RA1);
		opwst(i, Oldo, RA0);
		arith(Ash2add, RA1, RZ, RA1);
		LDWX(Oldw, RA0, RA1, RA0);
		BV(RA0);
		nop();

		if(pass == 0)
			break;

		t = (WORD*)(mod->origmp+i->d.ind);
		e = t + t[-1];
		t[-1] = 0;
		while(t < e) {
			t[0] = RELPC(patch[t[0]]);
			t++;
		}
		break;
	case IMOVL:
	movl:
		opbigld(i, RA0);
		opbigst(i, RA0);
		break;
	case IMOVM:
		if((i->add&ARM) == AXIMM) {
			if(i->reg == 8)
				goto movl;
			if((i->reg&3) == 0) {
				con(i->reg>>2, RA3, 1);
				movloop(i, Oldw, Ostw);
				break;
			} 
		}
		mid(i, Oldw, RA3);
		movloop(i, Oldb, Ostb);
		break;
	case IFRAME:
		if(UXSRC(i->add) != SRC(AIMM)) {
			punt(i, SRCOP|DSTOP, optab[i->op]);
			break;
		}
		tinit[i->s.imm] = 1;
		con((ulong)mod->type[i->s.imm], RA3, 1);
		call(base+macro[MacFRAM], SData);
		opwst(i, Ostw, RA2);
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
		opwld(i, Oldb, RA0);
		opwst(i, Ostw, RA0);
		break;
	case ICVTWB:
		opwld(i, Oldw, RA0);
		opwst(i, Ostb, RA0);
		break;
	case ILEA:
		opwld(i, Oldo, RA0);
		opwst(i, Ostw, RA0);
		break;
	case IMOVW:
		opwld(i, Oldw, RA0);
		opwst(i, Ostw, RA0);
		break;
	case IMOVB:
		opwld(i, Oldb, RA0);
		opwst(i, Ostb, RA0);
		break;
	case ITAIL:
		opwld(i, Oldw, RA0);
		mem(Oldw, O(List, tail), RA0, RA1);
		goto movp;
	case IMOVP:
	case IHEADP:
		opwld(i, Oldw, RA1);
		if(i->op == IHEADP)
			mem(Oldw, OA(List, data), RA1, RA1);
	movp:
		comibt(RA1, Cequal, (ulong)H, 3);	// H is small (-1)
		nop();
		call(base+macro[MacCOLR], SData);	// 3 instrs
		opwst(i, Oldw, RA0);
		opwst(i, Ostw, RA1);
		call(base+macro[MacFRP], SData);
		break;
	case ILENA:
		opwld(i, Oldw, RA1);
		comibt(RA1, Cequal, (ulong)H, 0);
		mov(RZ, RA0);
		mem(Oldw, O(Array, len), RA1, RA0);
		opwst(i, Ostw, RA0);
		break;
	case ILENL:
		mov(RZ, RA0);
		opwld(i, Oldw, RA1);
		comibt(RA1, Cequal, (ulong)H, 3);
		nop();
		mem(Oldw, O(List, tail), RA1, RA1);
		bra(-5);
		add(RA0, 1);
		opwst(i, Ostw, RA0);
		break;
	case ICALL:
		opwld(i, Oldw, RA0);
		con(RELPC(patch[i-mod->prog+1]), RA1, 0);
		mem(Ostw, O(Frame, lr), RA0, RA1);
		mem(Ostw, O(Frame, fp), RA0, RFP);
		bra(displ(i->d.ins-mod->prog));
		mov(RA0, RFP);
		break;
	case IJMP:
		bra(displ(i->d.ins-mod->prog));
		nop();
		break;
	case IBEQW:
		r = Cequal;
		f = 0;
	braw:
		opwld(i, Oldw, RA0);
		mid(i, Oldw, RA1);
		combdis(RA0, r, RA1, f, i->d.ins-mod->prog);
		nop();
		break;		
	case IBNEW:
		r = Cequal;
		f = 1;
		goto braw;
	case IBLTW:
		r = Cless;
		f = 0;
		goto braw;
	case IBLEW:
		r = Cleq;
		f = 0;
		goto braw;
	case IBGTW:
		r = Cleq;
		f = 1;
		goto braw;
	case IBGEW:
		r = Cless;
		f = 1;
		goto braw;
	case IBEQB:
		r = Cequal;
		f = 0;
	brab:
		opwld(i, Oldb, RA0);
		mid(i, Oldb, RA1);
		combdis(RA0, r, RA1, f, i->d.ins-mod->prog);
		nop();
		break;		
	case IBNEB:
		r = Cequal;
		f = 1;
		goto brab;
	case IBLTB:
		r = Cless;
		f = 0;
		goto brab;
	case IBLEB:
		r = Cleq;
		f = 0;
		goto brab;
	case IBGTB:
		r = Cleq;
		f = 1;
		goto brab;
	case IBGEB:
		r = Cless;
		f = 1;
		goto brab;
	case IBEQF:
		r = Fneq;
	braf:
		opflld(i, FR1);
		midfl(i, FR0);
		FCMP(FR1, r, FR0);
		bra(displ(i->d.ins-mod->prog));
		nop();
		break;		
	case IBNEF:
		r = Fequal;
		goto braf;
	case IBLTF:
		r = Fgeq;
		goto braf;
	case IBLEF:
		r = Fgrt;
		goto braf;
	case IBGTF:
		r = Fleq;
		goto braf;
	case IBGEF:
		r = Fless;
		goto braf;
	case IRET:
		// punt(i, NEWPC, optab[i->op]);
		mbra(MacRET);
		mem(Oldw, O(Frame, t), RFP, RA1);
		break;
	case IORW:
		r = Aor;
		goto arithw;
	case IANDW:
		r = Aand;
		goto arithw;
	case IXORW:
		r = Axor;
		goto arithw;
	case ISUBW:
		r = Asub;
		goto arithw;
	case IADDW:
		r = Aadd;
	arithw:
		mid(i, Oldw, RA1);
		opwld(i, Oldw, RA0);
		arith(r, RA1, RA0, RA1);
		opwst(i, Ostw, RA1);
		break;
	case IORB:
		r = Aor;
		goto arithb;
	case IANDB:
		r = Aand;
		goto arithb;
	case IXORB:
		r = Axor;
		goto arithb;
	case ISUBB:
		r = Asub;
		goto arithb;
	case IADDB:
		r = Aadd;
	arithb:
		mid(i, Oldb, RA1);
		opwld(i, Oldb, RA0);
		arith(r, RA1, RA0, RA1);
		opwst(i, Ostb, RA1);
		break;
	case IINDL:
	case IINDF:
	case IINDW:
	case IINDB:
		opwld(i, Oldw, RA0);			/* a */
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
		opwst(i, Oldw, RA1);
		mem(Oldw, O(Array, data), RA0, RA0);
		switch(r) {
		default:
			urk();
		case 0:
			arith(Aadd, RA0, RA1, RA0);
			break;
		case 2:
			arith(Ash2add, RA1, RA0, RA0);
			break;
		case 3:
			arith(Ash2add, RA1, RZ, RA1);
			arith(Ash1add, RA1, RA0, RA0);
			break;
		}
		r = RMP;
		if((i->add&ARM) == AXINF)
			r = RFP;
		mem(Ostw, i->reg, r, RA0);
		break;
	case ICVTLW:
		opwld(i, Oldo, RA0);
		mem(Oldw, 4, RA0, RA0);
		opwst(i, Ostw, RA0);
		break;
	case IBEQL:
		cbral(i, Cequal, 1, Cequal, 0, ANDAND);
		break;
	case IBNEL:
		cbral(i, Cequal, 1, Cequal, 1, OROR);
		break;
	case IBLEL:
		cbral(i, Cless, 0, Clequ, 0, EQAND);
		break;
	case IBGTL:
		cbral(i, Cleq, 1, Clequ, 1, EQAND);
		break;
	case IBLTL:
		cbral(i, Cless, 0, Clessu, 0, EQAND);
		break;
	case IBGEL:
		cbral(i, Cleq, 1, Clessu, 1, EQAND);
		break;
	case IMOVF:
		opflld(i, FR0);
		opflst(i, FR0);
		break;
	case IDIVF:
		r = Fdiv;
		goto arithf;
	case IMULF:
		r = Fmul;
		goto arithf;
	case ISUBF:
		r = Fsub;
		goto arithf;
	case IADDF:
		r = Fadd;
	arithf:
		midfl(i, FR1);
		opflld(i, FR0);
		farith(r, FR1, FR0, FR1);
		opflst(i, FR1);
		break;
	case INEGF:
		opflld(i, FR0);
		farith(Fsub, FRZ, FR0, FR0);
		opflst(i, FR0);
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

/*
 *	Preamble.  This is complicated by the space registers.
 *	We point comvec at calldata which does a dataspace call
 *	to dataptr.  The code at dataptr calls the real preamble
 *	code at start which saves the link register and branches
 *	to the new pc.  When the compiled code finally returns
 *	by branching indirect through the saved link it will
 *	return into the dataptr code which will return to text
 *	space (calldata) which will return to the outside.
 */
static void
preamble(void)
{
	ulong *start;

	if (comvec)
		return;

	code = (ulong*)malloc(PRESZ * sizeof(*code));

	if (code == nil)
		urk();

	start = code;
	con((ulong)&R, RREG, 1);		// load R
	mem(Ostw, O(REG, xpc), RREG, RLINK);	// save link
	mem(Oldw, O(REG, PC), RREG, RA0);	// load new PC
	mem(Oldw, O(REG, FP), RREG, RFP);	// load FP
	BV(RA0);				// jump to new PC
	mem(Oldw, O(REG, MP), RREG, RMP);	// load MP (delay)

	dataptr = code;
	LDSTneg(Ostw, -20, RCSP, RLINK);	// save return link
	LDSTpos(Oldo, 64, RCSP, RCSP);		// stack frame
	con((ulong)start, RA0, 1);		// load start
	BLE(RA0, 0, SData);			// call real preamble
	mov(RCALL, RLINK);			// linkage (delay)
        LDSTneg(Oldw, -84, RCSP, RLINK);	// fetch return link
	BE(RLINK, 0, SCode);			// return to text space
	LDSTneg(Oldo, -64, RCSP, RCSP);		// stack frame (delay)

	if (code > start + PRESZ)
		error("preamble overrun");

	segflush(start, PRESZ * sizeof(*code));

	if(cflag > 4) {
		print("preamble:\n");
		das(start, code-start);
	}

	comvec = calldata;
}

static void
maccase(void)
{
	ulong *loop, *def, *lab1;

	mem(Oldw, 0, RCON, RA3);		// n = t[0]
	mem(Oldo, 4, RCON, RCON);		// t = &t[1]
	arith(Ash1add, RA3, RA3, RA1);		// n1 = 3*n
	arith(Ash2add, RA1, RZ, RA1);		// n1 = 12*n
	LDWX(Oldw, RCON, RA1, RLINK);		// rlink = default

	loop = code;				// loop:
	def = code;
	combt(RA3, Cleq, RZ, 0);		// if (n <= 0) goto out
	// nop();

	shrs(RA3, 1, RA2);			// n' = n>>1
	arith(Ash1add, RA2, RA2, RTA);		// n2 = 3*n'
	arith(Ash2add, RTA, RCON, RA1);		// l = &t[n2]

	mem(Oldw, 0, RA1, RTA);			// l[0]
	lab1 = code;
	combt(RTA, Cleq, RA0, 0);		// if (l[0] <= v) goto 1f
	nop();
	bra(loop-code-2);			// goto loop
	mov(RA2, RA3);				// n = n2 (delay)

	opatch(lab1);				// 1f:
	mem(Oldw, 4, RA1, RTA);			// l[1]
	lab1 = code;
	combt(RA0, Cless, RTA, 0);		// if (v < l[1]) goto 1f
	nop();

	mem(Oldo, 12, RA1, RCON);		// t = &l[3]
	arith(Asub, RA3, RA2, RA3);		// n -= n'
	bra(loop-code-2);			// goto loop
	mem(Oldo, -1, RA3, RA3);		// n -= 1 (delay)

	opatch(lab1);				// 1f:
	mem(Oldw, 8, RA1, RLINK);		// rlink = l[2]

	opatch(def);				// out:
	BV(RLINK);				// jmp rlink
	nop();
}

static void
macfrp(void)
{
	ulong *lab1, *lab2;

	/* destroy the pointer in RA0 */
	lab1 = code;
	comibt(RA0, Cequal, -1, 0);		// if (p == h) goto out
	nop();

	mem(Oldw, O(Heap, ref)-sizeof(Heap), RA0, RA2);	// r = D2H(v)->ref
	lab2 = code;
	addibf(RA2, Cequal, -1, 0);		// if (--r != 0) goto store
	nop();

	mem(Ostw, O(REG, FP), RREG, RFP);	// call destroy
	mem(Ostw, O(REG, st), RREG, RLINK);
	mem(Ostw, O(REG, s), RREG, RA0);
	call((ulong)rdestroy, SCode);

	con((ulong)&R, RREG, 1);
	mem(Oldw, O(REG, st), RREG, RLINK);
	mem(Oldw, O(REG, FP), RREG, RFP);
	mem(Oldw, O(REG, MP), RREG, RMP);
	leafret();

	opatch(lab2);				// store
	mem(Ostw, O(Heap, ref)-sizeof(Heap), RA0, RA2);
	opatch(lab1);				// out
	leafret();
}

static void
macret(void)
{
	Inst i;
	ulong *cp1, *cp2, *cp3, *cp4, *cp5, *cp6;

	cp1 = code;
	combt(RA1, Cequal, RZ, 0);		// if (t(Rfp) == 0) goto punt
	nop();

	mem(Oldw, O(Type, destroy), RA1, RA0);
	cp2 = code;
	combt(RA0, Cequal, RZ, 0);		// if (destroy(t(fp)) == 0) goto punt
	nop();

	mem(Oldw, O(Frame, fp), RFP, RA2);
	cp3 = code;
	combt(RA2, Cequal, RZ, 0);		// if (fp(Rfp) == 0) goto punt
	nop();

	mem(Oldw, O(Frame, mr), RFP, RA3);
	cp4 = code;
	combt(RA3, Cequal, RZ, 0);		// if (mr(Rfp) == 0) goto call
	nop();

	mem(Oldw, O(REG, M), RREG, RA2);
	mem(Oldw, O(Heap, ref)-sizeof(Heap), RA2, RA3);
	cp5 = code;
	addibt(RA3, Cequal, -1, 0);		// if (--ref(arg) == 0) goto punt
	nop();
	mem(Ostw, O(Heap, ref)-sizeof(Heap), RA2, RA3);

	mem(Oldw, O(Frame, mr), RFP, RA1);
	mem(Ostw, O(REG, M), RREG, RA1);
	mem(Oldw, O(Modlink, compiled), RA1, RA2);	// check for uncompiled code
	mem(Oldw, O(Modlink, MP), RA1, RMP);
	cp6 = code;
	combt(RA2, Cequal, RZ, 0);
	nop();
	mem(Ostw, O(REG, MP), RREG, RMP);

	opatch(cp4);
	callindir(RA0);				// call destroy(t(fp))

	mem(Ostw, O(REG, SP), RREG, RFP);
	mem(Oldw, O(Frame, lr), RFP, RA1);
	mem(Oldw, O(Frame, fp), RFP, RFP);
	mem(Ostw, O(REG, FP), RREG, RFP);
	BV(RA1);				// goto lr(Rfp)
	mem(Oldw, O(Frame, fp), RFP, RFP);	// (delay)

	opatch(cp6);
	callindir(RA0);				// call destroy(t(fp))
	
	mem(Ostw, O(REG, SP), RREG, RFP);
	mem(Oldw, O(Frame, lr), RFP, RA1);
	mem(Oldw, O(Frame, fp), RFP, RFP);
	mem(Ostw, O(REG, FP), RREG, RFP);
	mem(Oldw, O(REG, xpc), RREG, RA2);
	BV(RA2);				// return to uncompiled code
	mem(Oldw, O(REG, PC), RREG, RA1);

	opatch(cp1);
	opatch(cp2);
	opatch(cp3);
	opatch(cp5);
	i.add = AXNON;
	punt(&i, TCHECK|NEWPC, optab[IRET]);
}

static void
maccolr(void)
{
	ulong *br;

	/* color the pointer in RA1 */
	mem(Oldw, O(Heap, ref)-sizeof(Heap), RA1, RA0);	// inc ref
	add(RA0, 1);
	mem(Ostw, O(Heap, ref)-sizeof(Heap), RA1, RA0);
	con((ulong)&mutator, RA2, 1);
	mem(Oldw, O(Heap, color)-sizeof(Heap), RA1, RA0);
	mem(Oldw, 0, RA2, RA2);
	br = code;
	combt(RA0, Cequal, RA2, 0);		// if (color == mutator) goto out
	con(propagator, RA2, 1);
	mem(Ostw, O(Heap, color)-sizeof(Heap), RA1, RA2);	// color = propagator
	con((ulong)&nprop, RA2, 1);
	mem(Ostw, 0, RA2, RA1);			// nprop = !0
	opatch(br);
	leafret();
}

static void
macmcal(void)
{
	ulong *lab1, *lab2;

	mem(Oldw, O(Modlink, prog), RA3, RA1);
	lab1 = code;
	combf(RA1, Cequal, RZ, 0);		// if (m->prog != nil) goto 1f
	nop();

	mem(Ostw, O(REG, st), RREG, RLINK);
	mem(Ostw, O(REG, FP), RREG, RA2);
	mem(Ostw, O(REG, dt), RREG, RA0);
	call((ulong)rmcall, SCode);		// CALL rmcall

	con((ulong)&R, RREG, 1);
	mem(Oldw, O(REG, st), RREG, RLINK);
	mem(Oldw, O(REG, FP), RREG, RFP);
	mem(Oldw, O(REG, MP), RREG, RMP);
	leafret();

	opatch(lab1);				// 1f
	mov(RA2, RFP);
	mem(Ostw, O(REG, M), RREG, RA3);
	mem(Oldw, O(Heap, ref)-sizeof(Heap), RA3, RA1);
	add(RA1, 1);
	mem(Ostw, O(Heap, ref)-sizeof(Heap), RA3, RA1);
	mem(Oldw, O(Modlink, compiled), RA3, RA1);
	mem(Oldw, O(Modlink, MP), RA3, RMP);
	lab2 = code;
	combt(RA1, Cequal, RZ, 0);
	mem(Ostw, O(REG, MP), RREG, RMP);

	BV(RA0);
	nop();

	opatch(lab2);
	mem(Ostw, O(REG, FP), RREG, RFP);
	mem(Oldw, O(REG, xpc), RREG, RA1);
	BV(RA1);				// call to uncompiled code
	mem(Ostw, O(REG, PC), RREG, RA0);
}

static void
macfram(void)
{
	ulong *lab1;

	mem(Oldw, O(REG, SP), RREG, RA0);
	mem(Oldw, O(Type, size), RA3, RA1);
	arith(Aadd, RA0, RA1, RA0);		// new frame
	mem(Oldw, O(REG, TS), RREG, RA1);	// top of stack
	lab1 = code;
	combt(RA0, Cless, RA1, 0);
	nop();

	mem(Ostw, O(REG, s), RREG, RA3);
	mem(Ostw, O(REG, st), RREG, RLINK);
	mem(Ostw, O(REG, FP), RREG, RFP);
	call((ulong)extend, SCode);		// CALL	extend

	con((ulong)&R, RREG, 1);
	mem(Oldw, O(REG, st), RREG, RLINK);
	mem(Oldw, O(REG, FP), RREG, RFP);
	mem(Oldw, O(REG, s), RREG, RA2);
	mem(Oldw, O(REG, MP), RREG, RMP);
	leafret();

	opatch(lab1);
	mem(Oldw, O(REG, SP), RREG, RA2);	// old frame
	mem(Ostw, O(REG, SP), RREG, RA0);	// new frame

	mem(Ostw, O(Frame, t), RA2, RA3);	// f->t = t
	mem(Oldw, O(Type, initialize), RA3, RA3);
	BV(RA3);				// initialize
	mem(Ostw, O(Frame, mr), RA2, RZ);	// f->mr = nil
}

static void
macmfra(void)
{
	mem(Ostw, O(REG, st), RREG, RLINK);
	mem(Ostw, O(REG, s), RREG, RA3);	// save type
	mem(Ostw, O(REG, d), RREG, RA0);	// save destination
	mem(Ostw, O(REG, FP), RREG, RFP);
	call((ulong)rmfram, SCode);		// call rmfram

	con((ulong)&R, RREG, 1);		// reload
	mem(Oldw, O(REG, st), RREG, RLINK);
	mem(Oldw, O(REG, FP), RREG, RFP);
	BV(RLINK);
	mem(Oldw, O(REG, MP), RREG, RMP);
}

void
comd(Type *t)
{
	int i, j, m, c;
	ulong frp;

	frp = (ulong)(base+macro[MacFRP]);
	mem(Ostw, O(REG, dt), RREG, RLINK);
	for(i = 0; i < t->np; i++) {
		c = t->map[i];
		j = i<<5;
		for(m = 0x80; m != 0; m >>= 1) {
			if(c & m) {
				mem(Oldw, j, RFP, RA0);
				call(frp, SData);
			}
			j += sizeof(WORD*);
		}
	}
	mem(Oldw, O(REG, dt), RREG, RLINK);
	leafret();
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
				mem(Ostw, j, RA2, RA0);
			j += sizeof(WORD*);
		}
	}
	leafret();
}

void
typecom(Type *t)
{
	int n;
	ulong tmp[4096], *start;

	if(t == nil || t->initialize != 0)
		return;

	code = tmp;
	comi(t);
	n = code - tmp;
	code = tmp;
	comd(t);
	n += code - tmp;

	n *= sizeof(*code);
	code = mallocz(n, 0);
	if(code == nil)
		return;

	start = code;
	t->initialize = code;
	comi(t);
	t->destroy = code;
	comd(t);

	if (code - start != n / sizeof(*code))
		error("typecom mismatch");

	segflush(start, n);

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
	ulong v;
	Link *l;
	Modl *e;
	int i, n;
	ulong *s, tmp[4096];

	base = nil;
	patch = mallocz(size*sizeof(*patch), 0);
	tinit = malloc(m->ntype*sizeof(*tinit));
	if(tinit == nil || patch == nil)
		goto bad;

	preamble();

	mod = m;
	n = 0;
	pass = 0;
	nlit = 0;

	for(i = 0; i < size; i++) {
		code = tmp;
		comp(&m->prog[i]);
		patch[i] = n;
		n += code - tmp;
	}

	for(i = 0; i < nelem(mactab); i++) {
		code = tmp;
		mactab[i].gen();
		macro[mactab[i].idx] = n;
		n += code - tmp;
	}

	base = mallocz((n + nlit) * sizeof(ulong), 0);
	if(base == nil)
		goto bad;

	if(cflag > 1)
		print("dis=%5d %5d s800=%5d asm=%.8lux lit=%d: %s\n",
			size, size*sizeof(Inst), n, base, nlit, m->name);

	pass++;
	nlit = 0;
	litpool = (ulong*)base + n;
	code = base;

	for(i = 0; i < size; i++) {
		s = code;
		comp(&m->prog[i]);
		if(cflag > 2) {
			print("%D\n", &m->prog[i]);
			das(s, code-s);
		}
	}

	for(i = 0; i < nelem(mactab); i++) {
		s = code;
		mactab[i].gen();
		if(cflag > 2) {
			print("%s:\n", mactab[i].name);
			das(s, code-s);
		}
	}

	if (code - base != n)
		error("typecom mismatch");

	segflush(base, n * sizeof(*base));

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
	if(cflag > 2)
		print("entry %lx\n", m->entry);
	free(patch);
	free(tinit);
	free(m->prog);
	m->prog = (Inst*)base;
	m->compiled = 1;
	return 1;
bad:
	free(patch);
	free(tinit);
	free(base);
	return 0;
}
