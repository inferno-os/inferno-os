#include "lib9.h"
#include "isa.h"
#include "interp.h"
#include "raise.h"

enum
{
	R8	= 8,		/* SUN calls these %o0 - %o7 */
	R9	= 9,
	R10	= 10,
	R11	= 11,
	R12	= 12,
	R13	= 13,
	R14	= 14,		/* SUN %sp */
	R15	= 15,		/* R15/%o7 is the default link register */

	R16	= 16,		/* SUN calls these %l0 - %l7 */
	R17	= 17,
	R18	= 18,
	R19	= 19,
	R20	= 20,
	R21	= 21,
	R22	= 22,
	R23	= 23,
	RLINK	= 15,

	RZ	= 0,		/* Always 0 */
	RFP	= R23,		/* Frame Pointer */
	RMP	= R22,		/* Module Pointer */
	RTA	= R21,		/* Intermediate address for double indirect */
	RREG	= R20,		/* Pointer to REG */
	RA3	= R19,		/* gpr 3 */
	RA2	= R18,		/* gpr 2 2+3 = L */
	RA1	= R17,		/* gpr 1 */
	RA0	= R16,		/* gpr 0 0+1 = L */

	RCON	= R8,		/* Constant builder */

	FA2	= 2,		/* Floating */
	FA3	= 3,
	FA4	= 4,
	FA5	= 5,

	Olea	= (1<<20),	/* Pseudo op */
	Owry	= 48,
	Omul	= 11,
	Oumul	= 10,
	Osdiv	= 15,
	Osll	= 37,
	Osra	= 39,
	Osrl	= 38,
	Osethi	= 4,
	Oadd	= 0,
	Oaddcc	= 16,
	Oaddx	= 8,
	Osub	= 4,
	Osubcc	= 20,
	Osubx	= 12,
	Oor	= 2,
	Oand	= 1,
	Oxor	= 3,
	Oldw	= 0,
	Oldsh	= 10,
	Ostw	= 4,
	Osth	= 6,
	Ojmpl	= 56,
	Ocall	= 1,
	Ocmp	= 20,		/* subcc */
	Oldbu	= 1,
	Ostb	= 5,
	Oba	= 8,
	Obn	= 0,
	Obne	= 9,
	Obe	= 1,
	Obg	= 10,
	Oble	= 2,
	Obge	= 11,
	Obl	= 3,
	Obgu	= 12,
	Obleu	= 4,
	Obcc	= 13,
	Obcs	= 5,
	Obpos	= 14,
	Obneg	= 6,
	Obvc	= 15,
	Obvs	= 7,
	OfaddD	= 66,
	OfsubD	= 70,
	OfdivD	= 78,
	OfmulD	= 74,
	Oldf	= 32,
	Ostf	= 36,
	OfDtoQ	= 206,
	OfnegS	= 5,
	OfcmpD	= 82,
	Ofba	= 8,
	Ofbe	= 9,
	Ofbg	= 6,
	Ofbge	= 11,
	Ofbl	= 4,
	Ofble	= 13,
	Ofbne	= 1,
	OfWtoD	= 200,
	OfDtoW	= 210,
	Osave	= 60,
	Orestore= 61,

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

#define OP(n)			   (n<<30)
#define I13(i)			   ((i)&0x1fff)
#define D22(i)			   ((i)&0x3fffff)
#define PC30(pc)		   (((ulong)(pc) - (ulong)code)>>2)

#define CALL(addr)		   *code=OP(1)|PC30(addr); code++
#define FM2I(op2, i, rd)	   *code=OP(0)|(rd<<25)|(op2<<22)|D22(i); code++
#define BRA(cond, disp)		   *code=OP(0)|(cond<<25)|(2<<22)|D22((disp)); code++
#define BRAF(cond, disp)	   *code=OP(0)|(cond<<25)|(6<<22)|D22((disp)); code++
#define BRADIS(r, o)		   BRA(r, ((ulong)(base+patch[o])-(ulong)code)>>2)
#define BRAFDIS(r, o)		   BRAF(r, ((ulong)(base+patch[o])-(ulong)code)>>2)
#define BRAMAC(r, o)		   BRA(r, ((ulong)(base+macro[o])-(ulong)code)>>2);
#define FM3I(op, op3, i, rs1, rd)  *code++=OP(op)|(rd<<25)|(op3<<19)|(rs1<<14)|\
					   (1<<13)|I13(i)
#define FM3(op, op3, rs2, rs1, rd) *code++=OP(op)|(rd<<25)|(op3<<19)|(rs1<<14)|rs2
#define FMF1(opf, rs2, rs1, rd)	   *code++=OP(2)|(rd<<25)|(52<<19)|(rs1<<14)|(opf<<5)|rs2
#define FMF2(opf, rs2, rs1, rd)	   *code++=OP(2)|(rd<<25)|(53<<19)|(rs1<<14)|(opf<<5)|rs2
#define NOOP			   *code++=(4<<22)
#define RETURN			   FM3I(2, Ojmpl, 8, RLINK, RZ);
#define MOV(s, d)		   FM3(2, Oor, s, RZ, d)

#define RELPC(pc)		   (ulong)(base+pc)
#define PATCH(ptr)		   *ptr |= (code-ptr) & 0x3fffff

static	ulong*	code;
static	ulong*	base;
static	ulong*	patch;
static	int	pass;
static	int	puntpc = 1;
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
urk(void)
{
	error(exCompile);
}

static int
bc(long c)
{
	c &= ~0xfffL;
	if (c == 0 || c == ~0xfffL)
		return 1;

	return 0;
}

static void
con(ulong o, int r, int opt)
{
	if(opt != 0) {
		if(bc(o)) {	
			FM3I(2, Oadd, o & 0x1fff, RZ, r);
			return;
		}
		if((o & 0x3ff) == 0) {
			FM2I(Osethi, o>>10, r);
			return;
		}
	}
	FM2I(Osethi, o>>10, r);
	FM3I(2, Oadd, o & 0x3ff, r, r);
}

static void
mem(int inst, ulong disp, int rm, int r)
{
	int op;

	op = 3;
	if(inst == Olea) {
		op = 2;
		inst = Oadd;
	}
	if(bc(disp)) {
		FM3I(op, inst, disp, rm, r);
		return;
	}
	con(disp, RCON, 1);
	FM3(op, inst, RCON, rm, r);
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
		if(mi == Olea) {
			mem(Ostw, O(REG, st), RREG, r);
			con((ulong)&R.st, r, 1);
		}
		return;
	case SRC(AIND|AFP):
		ir = RFP;
		break;
	case SRC(AIND|AMP):
		ir = RMP;
		break;
	}
	rta = RTA;
	if(mi == Olea)
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
	if(mi == Olea)
		rta = r;
	mem(Oldw, i->d.i.f, ir, rta);
	mem(mi, i->d.i.s, rta, r);
}

static void
opfl(Adr *a, int am, int mi, int r)
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
	mem(Ostw, roff, RREG, RTA);

	if(pass == 0)
		return;

	*litpool = imm;
	litpool++;	
}

static void
punt(Inst *i, int m, void (*fn)(void))
{
	ulong pc;

	if(m & SRCOP) {
		if(UXSRC(i->add) == SRC(AIMM))
			literal(i->s.imm, O(REG, s));
		else {
			opwld(i, Olea, RA0);
			mem(Ostw, O(REG, s), RREG, RA0);
		}
	}

	if(m & DSTOP) {
		opwst(i, Olea, RA0);
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
		mem(Olea, i->reg, RFP, RA0);
		mem(Ostw, O(REG, m), RREG, RA0);
		break;
	case AXINM:
		mem(Olea, i->reg, RMP, RA0);
		mem(Ostw, O(REG, m), RREG, RA0);
		break;
	}

	CALL(fn);
	mem(Ostw, O(REG, FP), RREG, RFP);

	con((ulong)&R, RREG, 1);
	if(m & TCHECK) {
		mem(Oldw, O(REG, t), RREG, RA0);
		FM3I(2, Ocmp, 0, RA0, RZ);
		BRA(Obe, 5);
		NOOP;				
		mem(Oldw, O(REG, xpc), RREG, RLINK);
		RETURN;
		NOOP;
	}

	mem(Oldw, O(REG, FP), RREG, RFP);
	mem(Oldw, O(REG, MP), RREG, RMP);

	if(m & NEWPC) {
		mem(Oldw, O(REG, PC), RREG, RA0);
		FM3I(2, Ojmpl, 0, RA0, RZ);
		NOOP;
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
	mem(mi, i->reg+4, ir, r+1);
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
cbral(Inst *i, int jmsw, int jlsw, int mode)
{
	ulong dst, *label;

	opwld(i, Olea, RA1);
	mid(i, Olea, RA3);
	mem(Oldw, 0, RA1, RA2);
	mem(Oldw, 0, RA3, RA0);
	FM3(2, Ocmp, RA0, RA2, RZ);
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
		NOOP;
		label = code;
		BRA(Obne, 0);
		break;
	}
	NOOP;
	mem(Oldw, 4, RA3, RA0);
	mem(Oldw, 4, RA1, RA2);
	FM3(2, Ocmp, RA0, RA2, RZ);
	BRADIS(jlsw, dst);
	if(label != nil)
		PATCH(label);
}

static void
comcase(Inst *i, int w)
{
	int l;
	WORD *t, *e;

	if(w != 0) {
		opwld(i, Oldw, RA0);		// v
		opwst(i, Olea, RCON);		// table
		BRAMAC(Oba, MacCASE);
		NOOP;
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
	FM3I(2, Ocmp, -1, RA0, RZ);
	mlnil = code;
	BRA(Obe, 0);
	NOOP;
	
	if((i->add&ARM) == AXIMM) {
		o = OA(Modlink, links)+i->reg*sizeof(Modl)+O(Modl, frame);
		mem(Oldw, o, RA0, RA3);
	} else {
		mid(i, Oldw, RA1);
		FM3I(2, Osll, 3, RA1, RA1);		// assumes sizeof(Modl) == 8
		FM3(2, Oadd, RA0, RA1, RA1);
		o = OA(Modlink, links)+O(Modl, frame);
		mem(Oldw, o, RA1, RA3);
	}
	mem(Oldw, O(Type, initialize), RA3, RA1);
	FM3I(2, Ocmp, 0, RA1, RZ);
	punt = code;
	BRA(Obne, 0);
	NOOP;

	opwst(i, Olea, RA0);

	/* Type in RA3, destination in RA0 */
	PATCH(mlnil);
	con(RELPC(patch[i-mod->prog+1])-8, RLINK, 0);
	BRAMAC(Oba, MacMFRA);
	NOOP;

	/* Type in RA3 */
	PATCH(punt);
	CALL(base+macro[MacFRAM]);
	NOOP;
	opwst(i, Ostw, RA2);
}

static void
commcall(Inst *i)
{
	opwld(i, Oldw, RA2);
	con(RELPC(patch[i-mod->prog+1]), RA0, 0);
	mem(Ostw, O(Frame, lr), RA2, RA0);
	mem(Ostw, O(Frame, fp), RA2, RFP);
	mem(Oldw, O(REG, M), RREG, RA3);
	mem(Ostw, O(Frame, mr), RA2, RA3);
	opwst(i, Oldw, RA3);
	if((i->add&ARM) == AXIMM) {
		CALL(base+macro[MacMCAL]);
		mem(Oldw, OA(Modlink, links)+i->reg*sizeof(Modl)+O(Modl, u.pc), RA3, RA0);
	} else {
		mid(i, Oldw, RA1);
		FM3I(2, Osll, 3, RA1, RA1);		// assumes sizeof(Modl) == 8
		FM3(2, Oadd, RA1, RA3, RA0);
		CALL(base+macro[MacMCAL]);
		mem(Oldw, OA(Modlink, links)+O(Modl, u.pc), RA0, RA0);
	}
}

static void
larith(Inst *i, int op, int opc)
{
	opflld(i, Oldw, RA0);
	midfl(i, Oldw, RA2);
	FM3(2, op, RA1, RA3, RA1);
	FM3(2, opc, RA0, RA2, RA0);
	opflst(i, Ostw, RA0);
}

static void
movloop(Inst *i, int ld, int st)
{
	int s;

	s = 1;
	if(ld == Oldw)
		s = 4;
	opwld(i, Olea, RA1);
	opwst(i, Olea, RA2);
	mem(ld, 0, RA1, RA0);
	mem(st, 0, RA2, RA0);
	FM3I(2, Oadd, s, RA2, RA2);
	FM3I(2, Oaddcc, -1, RA3, RA3);
	BRA(Obne, -4);
	FM3I(2, Oadd, s, RA1, RA1);
}

static
void
compdbg(void)
{
	print("%s:%d@%.8ux\n", R.M->m->name, R.t, R.st);
}

static void
shll(Inst *i)
{
	ulong *lab0, *lab1, *lab2;

	opwld(i, Oldw, RA2);
	midfl(i, Oldw, RA0);
	FM3I(2, Ocmp, RZ, RA2, RZ);
	lab0 = code;
	BRA(Obe, 0);
	FM3I(2, Ocmp, 32, RA2, RZ);
	lab1 = code;
	BRA(Obl, 0);
	NOOP;
	FM3I(2, Osub, 32, RA2, RA2);
	FM3(2, Osll, RA2, RA1, RA0);
	lab2 = code;
	BRA(Oba, 0);
	MOV(RZ, RA1);

	PATCH(lab1);
	FM3(2, Osll, RA2, RA0, RA0);
	con(32, RA3, 1);
	FM3(2, Osub, RA2, RA3, RA3);
	FM3(2, Osrl, RA3, RA1, RA3);
	FM3(2, Oor, RA0, RA3, RA0);
	FM3(2, Osll, RA2, RA1, RA1);

	PATCH(lab0);
	PATCH(lab2);
	opflst(i, Ostw, RA0);
}

static void
comp(Inst *i)
{
	int r;
	WORD *t, *e;
	char buf[64];

	if(0) {
		Inst xx;
		xx.add = AXIMM|SRC(AIMM);
		xx.s.imm = (ulong)code;
		xx.reg = i-mod->prog;
		puntpc = 0;
		punt(&xx, SRCOP, compdbg);
		puntpc = 1;
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
	case IMODW:
	case IMODB:
	case IMNEWZ:
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
	case ICVTRF:
	case ICVTFR:
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
		opwld(i, Oldw, RA1);
		opwst(i, Olea, RA0);
		FM3I(2, Osll, 2, RA1, RA1);
		FM3(3, Oldw, RA1, RA0, RA0);
		FM3I(2, Ojmpl, 0, RA0, RZ);
		NOOP;

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
		opflld(i, Oldw, RA0);
		opflst(i, Ostw, RA0);
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
		movloop(i, Oldbu, Ostb);
		break;
	case IFRAME:
		if(UXSRC(i->add) != SRC(AIMM)) {
			punt(i, SRCOP|DSTOP, optab[i->op]);
			break;
		}
		tinit[i->s.imm] = 1;
		con((ulong)mod->type[i->s.imm], RA3, 1);
		CALL(base+macro[MacFRAM]);
		NOOP;
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
		opwld(i, Oldbu, RA0);
		opwst(i, Ostw, RA0);
		break;
	case ICVTWB:
		opwld(i, Oldw, RA0);
		opwst(i, Ostb, RA0);
		break;
	case ILEA:
		opwld(i, Olea, RA0);
		opwst(i, Ostw, RA0);
		break;
	case IMOVW:
		opwld(i, Oldw, RA0);
		opwst(i, Ostw, RA0);
		break;
	case IMOVB:
		opwld(i, Oldbu, RA0);
		opwst(i, Ostb, RA0);
		break;
	case ICVTSW:
		opwld(i, Oldsh, RA0);
		opwst(i, Ostw, RA0);
		break;
	case ICVTWS:
		opwld(i, Oldw, RA0);
		opwst(i, Osth, RA0);
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
		FM3I(2, Ocmp, (ulong)H, RA1, RZ);
		BRA(Obe, 5);
		con((ulong)&mutator, RA2, 1);
		CALL(base+macro[MacCOLR]);
		mem(Oldw, O(Heap, ref)-sizeof(Heap), RA1, RA0);
		opwst(i, Oldw, RA0);
		opwst(i, Ostw, RA1);
		CALL(base+macro[MacFRP]);
		NOOP;
		break;
	case ILENA:
		opwld(i, Oldw, RA1);
		FM3I(2, Ocmp, (ulong)H, RA1, RZ);
		BRA(Obe, 3);
		con(0, RA0, 1);
		mem(Oldw, O(Array, len), RA1, RA0);
		opwst(i, Ostw, RA0);
		break;
	case ILENL:
		con(0, RA0, 1);
		opwld(i, Oldw, RA1);
		FM3I(2, Ocmp, (ulong)H, RA1, RZ);
		BRA(Obe, 5);
		NOOP;
		mem(Oldw, O(List, tail), RA1, RA1);
		BRA(Oba, -4);
		FM3I(2, Oadd, 1, RA0, RA0);
		opwst(i, Ostw, RA0);
		break;
	case ICALL:
		opwld(i, Oldw, RA0);
		con(RELPC(patch[i-mod->prog+1]), RA1, 0);
		mem(Ostw, O(Frame, lr), RA0, RA1);
		mem(Ostw, O(Frame, fp), RA0, RFP);
		BRADIS(Oba, i->d.ins-mod->prog);
		MOV(RA0, RFP);
		break;
	case IJMP:
		BRADIS(Oba, i->d.ins-mod->prog);
		NOOP;
		break;
	case IBEQW:
		r = Obe;
	braw:
		opwld(i, Oldw, RA1);
		mid(i, Oldw, RA0);
		FM3(2, Ocmp, RA0, RA1, RZ);
		BRADIS(r, i->d.ins-mod->prog);
		NOOP;
		break;		
	case IBNEW:
		r = Obne;
		goto braw;
	case IBLTW:
		r = Obl;
		goto braw;
	case IBLEW:
		r = Oble;
		goto braw;
	case IBGTW:
		r = Obg;
		goto braw;
	case IBGEW:
		r = Obge;
		goto braw;
	case IBEQB:
		r = Obe;
	brab:
		opwld(i, Oldbu, RA1);
		mid(i, Oldbu, RA0);
		FM3(2, Ocmp, RA0, RA1, RZ);
		BRADIS(r, i->d.ins-mod->prog);
		NOOP;
		break;		
	case IBNEB:
		r = Obne;
		goto brab;
	case IBLTB:
		r = Obl;
		goto brab;
	case IBLEB:
		r = Oble;
		goto brab;
	case IBGTB:
		r = Obg;
		goto brab;
	case IBGEB:
		r = Obge;
		goto brab;
	case IBEQF:
		r = Ofbe;
	braf:
		opflld(i, Oldf, FA4);
		midfl(i, Oldf, FA2);
		FMF2(OfcmpD, FA2, FA4, 0);
		NOOP;
		BRAFDIS(r, i->d.ins-mod->prog);
		NOOP;
		break;		
	case IBNEF:
		r = Ofbne;
		goto braf;
	case IBLTF:
		r = Ofbl;
		goto braf;
	case IBLEF:
		r = Ofble;
		goto braf;
	case IBGTF:
		r = Ofbg;
		goto braf;
	case IBGEF:
		r = Ofbge;
		goto braf;
	case IRET:
		BRAMAC(Oba, MacRET);
		mem(Oldw, O(Frame,t), RFP, RA1);
		break;
	case IORW:
		r = Oor;
		goto arithw;
	case IANDW:
		r = Oand;
		goto arithw;
	case IXORW:
		r = Oxor;
		goto arithw;
	case ISUBW:
		r = Osub;
		goto arithw;
	case ISHRW:
		r = Osra;
		goto arithw;
	case ISHLW:
		r = Osll;
		goto arithw;
	case ILSRW:
		r = Osrl;
		goto arithw;
	case IMULW:
		r = Omul;
		goto arithw;
	case IDIVW:
		r = Osdiv;
		goto arithw;
	case IADDW:
		r = Oadd;
	arithw:
		mid(i, Oldw, RA1);
		if(i->op == IDIVW) {
			FM3I(2, Osra, 31, RA1, RA0);
			FM3(2, Owry, RZ, RA0, 0);
		}
		if(UXSRC(i->add) == SRC(AIMM) && bc(i->s.imm))
			FM3I(2, r, i->s.imm, RA1, RA0);
		else {
			opwld(i, Oldw, RA0);
			FM3(2, r, RA0, RA1, RA0);
		}
		opwst(i, Ostw, RA0);
		break;
	case IORB:
		r = Oor;
		goto arithb;
	case IANDB:
		r = Oand;
		goto arithb;
	case IXORB:
		r = Oxor;
		goto arithb;
	case ISUBB:
		r = Osub;
		goto arithb;
	case IMULB:
		r = Omul;
		goto arithb;
	case IDIVB:
		FM3(2, Owry, RZ, RZ, 0);
		r = Osdiv;
		goto arithb;
	case IADDB:
		r = Oadd;
	arithb:
		mid(i, Oldbu, RA1);
		opwld(i, Oldbu, RA0);
		FM3(2, r, RA0, RA1, RA0);
		opwst(i, Ostb, RA0);
		break;
	case ISHRB:
		r = Osra;
		goto shiftb;
	case ISHLB:
		r = Osll;
	shiftb:
		mid(i, Oldbu, RA1);
		if(UXSRC(i->add) == SRC(AIMM) && bc(i->s.imm))
			FM3I(2, r, i->s.imm, RA1, RA0);
		else {
			opwld(i, Oldw, RA0);
			FM3(2, r, RA0, RA1, RA0);
		}
		opwst(i, Ostb, RA0);
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
		if(UXDST(i->add) == DST(AIMM) && bc(i->d.imm<<r)) {
			mem(Oldw, O(Array, data), RA0, RA0);
			FM3I(2, Oadd, (i->d.imm<<r), RA0, RA0);
		}
		else {
			opwst(i, Oldw, RA1);
			mem(Oldw, O(Array, data), RA0, RA0);
			if(r != 0)
				FM3I(2, Osll, r, RA1, RA1);
			FM3(2, Oadd, RA0, RA1, RA0);
		}
		r = RMP;
		if((i->add&ARM) == AXINF)
			r = RFP;
		mem(Ostw, i->reg, r, RA0);
		break;
	case IINDX:
		opwld(i, Oldw, RA0);			/* a */
		/*
		r = 0;
		if(UXDST(i->add) == DST(AIMM) && bc(i->d.imm<<r))
			r = i->d.imm<<r;
		else
		*/
			opwst(i, Oldw, RA1);		/* i */
		mem(Oldw, O(Array, t), RA0, RA2);
		mem(Oldw, O(Array, data), RA0, RA0);
		mem(Oldw, O(Type, size), RA2, RA2);
		/*
		if(r != 0)
			FM3I(2, Oumul, r, RA2, RA1);
		else
		*/
			FM3(2, Oumul, RA1, RA2, RA1);
		FM3(2, Oadd, RA0, RA1, RA0);
		r = RMP;
		if((i->add&ARM) == AXINF)
			r = RFP;
		mem(Ostw, i->reg, r, RA0);
		break;
	case IADDL:
		larith(i, Oaddcc, Oaddx);
		break;
	case ISUBL:
		larith(i, Osubcc, Osubx);
		break;
	case IORL:
		larith(i, Oor, Oor);
		break;
	case IANDL:
		larith(i, Oand, Oand);
		break;
	case IXORL:
		larith(i, Oxor, Oxor);
		break;
	case ICVTWL:
		opwld(i, Oldw, RA1);
		FM3I(2, Osra, 31, RA1, RA0);
		opflst(i, Ostw, RA0);
		break;
	case ICVTLW:
		opwld(i, Olea, RA0);
		mem(Oldw, 4, RA0, RA0);
		opwst(i, Ostw, RA0);
		break;
	case IBEQL:
		cbral(i, Obne, Obe, ANDAND);
		break;
	case IBNEL:
		cbral(i, Obne, Obne, OROR);
		break;
	case IBLEL:
		cbral(i, Obl, Obleu, EQAND);
		break;
	case IBGTL:
		cbral(i, Obg, Obgu, EQAND);
		break;
	case IBLTL:
		cbral(i, Obl, Obcs, EQAND);
		break;
	case IBGEL:
		cbral(i, Obg, Obcc, EQAND);
		break;
	case IMOVF:
		opflld(i, Oldf, FA2);
		opflst(i, Ostf, FA2);
		break;
	case IDIVF:
		r = OfdivD;
		goto arithf;
	case IMULF:
		r = OfmulD;
		goto arithf;
	case ISUBF:
		r = OfsubD;
		goto arithf;
	case IADDF:
		r = OfaddD;
	arithf:
		opflld(i, Oldf, FA2);
		midfl(i, Oldf, FA4);
		FMF1(r, FA2, FA4, FA4);
		opflst(i, Ostf, FA4);
		break;
	case INEGF:
		opflld(i, Oldf, FA2);
		FMF1(OfnegS, FA2, 0, FA2);
		opflst(i, Ostf, FA2);
		break;
	case ICVTFL:
		// >= Sparc 8
		// opflld(i, Oldf, FA2);
		// FMF1(OfDtoQ, FA2, 0, FA2);
		// opflst(i, Ostf, FA2);
		punt(i, SRCOP|DSTOP, optab[i->op]);
		break;
	case ICVTLF:
		// >= Sparc 8
		// opflld(i, Oldf, FA2);
		// FMF1(OfQtoD, FA2, 0, FA2);
		// opflst(i, Ostf, FA2);
		punt(i, SRCOP|DSTOP, optab[i->op]);
		break;
	case ICVTWF:
		opwld(i, Oldf, FA2);
		FMF1(OfWtoD, FA2, 0, FA2);
		opflst(i, Ostf, FA2);
		break;
	case ICVTFW:
		opflld(i, Oldf, FA2);
		FMF1(OfDtoW, FA2, 0, FA2);
		opwst(i, Ostf, FA2);
		break;
	case ISHLL:
		shll(i);
		break;
	case ISHRL:
	case ILSRL:
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
	ulong *start;

	if(comvec)
		return;

	comvec = malloc(10 * sizeof(*code));
	if(comvec == nil)
		error(exNomem);
	code = (ulong*)comvec;
	start = code;

	con((ulong)&R, RREG, 1);
	mem(Ostw, O(REG, xpc), RREG, RLINK);
	mem(Oldw, O(REG, PC), RREG, RA0);
	mem(Oldw, O(REG, FP), RREG, RFP);
	FM3I(2, Ojmpl, 0, RA0, RZ);
	mem(Oldw, O(REG, MP), RREG, RMP);

	segflush(comvec, 10 * sizeof(*code));

	if(cflag > 4) {
		print("comvec:\n");
		das(start, code-start);
	}
}

static void
maccase(void)
{
	ulong *loop, *def, *lab1;

	mem(Oldw, 0, RCON, RA3);		// n = t[0]
	FM3I(2, Oadd, 4, RCON, RCON);
	MOV(RA3, RA1);
	FM3I(2, Osll, 1, RA1, RA1);
	FM3(2, Oadd, RA3, RA1, RA1);
	FM3I(2, Osll, 2, RA1, RA1);
	FM3(3, Oldw, RCON, RA1, RLINK);

	loop = code;
	FM3(2, Ocmp, RZ, RA3, RZ);
	def = code;
	BRA(Oble, 0);
	NOOP;

	MOV(RA3, RA2);				// MOVL	DX, CX	n2 = n
	FM3I(2, Osra, 1, RA2, RA2);		// SHR	CX,1	n2 = n2>>1
	MOV(RA2, RA1);
	FM3I(2, Osll, 1, RA1, RA1);
	FM3(2, Oadd, RA2, RA1, RA1);
	FM3I(2, Osll, 2, RA1, RA1);

	FM3(3, Oldw, RA1, RCON, RTA);		// MOV	(RA1+RCON), RTA
	FM3(2, Ocmp, RTA, RA0, RZ);
	lab1 = code;
	BRA(Obge, 0);
	NOOP;
	MOV(RA2, RA3);				// n = n2
	BRA(Oba, loop-code);
	NOOP;

	PATCH(lab1);
	FM3I(2, Oadd, 4, RA1, RTA);
	FM3(3, Oldw, RTA, RCON, RTA);		// MOV	(RA1+RCON), RTA
	FM3(2, Ocmp, RTA, RA0, RZ);
	lab1 = code;
	BRA(Obl, 0);
	NOOP;

	FM3I(2, Oadd, 12, RA1, RTA);
	FM3(2, Oadd, RTA, RCON, RCON);
	FM3(2, Osub, RA2, RA3, RA3);		// SUBL	CX, DX		n -= n2
	FM3I(2, Oadd, -1, RA3, RA3);		// DECL	DX		n -= 1
	BRA(Oba, loop-code);
	NOOP;

	PATCH(lab1);
	FM3I(2, Oadd, 8, RA1, RTA);
	FM3(3, Oldw, RTA, RCON, RLINK);

	PATCH(def);
	FM3I(2, Ojmpl, 0, RLINK, RZ);
	NOOP;
}

static void
macfrp(void)
{
	ulong *lab1, *lab2;

	/* destroy the pointer in RA0 */
	FM3I(2, Ocmp, -1, RA0, RZ);
	lab1 = code;
	BRA(Obe, 0);
	NOOP;
	mem(Oldw, O(Heap, ref)-sizeof(Heap), RA0, RA2);
	FM3I(2, Oadd, -1, RA2, RA2);
	FM3I(2, Ocmp, 0, RA2, RZ);
	lab2 = code;
	BRA(Obne, 0);
	NOOP;
	mem(Ostw, O(REG, FP), RREG, RFP);
	mem(Ostw, O(REG, st), RREG, RLINK);
	CALL(rdestroy);
	mem(Ostw, O(REG, s), RREG, RA0);
	con((ulong)&R, RREG, 1);
	mem(Oldw, O(REG, st), RREG, RLINK);
	mem(Oldw, O(REG, FP), RREG, RFP);
	RETURN;
	mem(Oldw, O(REG, MP), RREG, RMP);
	PATCH(lab2);
	mem(Ostw, O(Heap, ref)-sizeof(Heap), RA0, RA2);	
	PATCH(lab1);
	RETURN;
	NOOP;
}

static void
macret(void)
{
	Inst i;
	ulong *cp1, *cp2, *cp3, *cp4, *cp5, *cp6;

	FM3I(2, Ocmp, 0, RA1, RZ);
	cp1 = code;
	BRA(Obe, 0);				// t(Rfp) == 0
	NOOP;

	mem(Oldw, O(Type,destroy),RA1, RA0);
	FM3I(2, Ocmp, 0, RA0, RZ);
	cp2 = code;
	BRA(Obe, 0);				// destroy(t(fp)) == 0
	NOOP;

	mem(Oldw, O(Frame,fp),RFP, RA2);
	FM3I(2, Ocmp, 0, RA2, RZ);
	cp3 = code;
	BRA(Obe, 0);				// fp(Rfp) == 0
	NOOP;

	mem(Oldw, O(Frame,mr),RFP, RA3);
	FM3I(2, Ocmp, 0, RA3, RZ);
	cp4 = code;
	BRA(Obe, 0);				// mr(Rfp) == 0
	NOOP;

	mem(Oldw, O(REG,M),RREG, RA2);
	mem(Oldw, O(Heap,ref)-sizeof(Heap),RA2, RA3);
	FM3I(2, Oaddcc, -1, RA3, RA3);
	cp5 = code;
	BRA(Obe, 0);				// --ref(arg) == 0
	NOOP;
	mem(Ostw, O(Heap,ref)-sizeof(Heap),RA2, RA3);

	mem(Oldw, O(Frame,mr),RFP, RA1);
	mem(Ostw, O(REG,M),RREG, RA1);
	mem(Oldw, O(Modlink,compiled),RA1, RA2);	// check for uncompiled code
	mem(Oldw, O(Modlink,MP),RA1, RMP);
	FM3I(2, Ocmp, 0, RA2, RZ);
	cp6 = code;
	BRA(Obe, 0);
	NOOP;
	mem(Ostw, O(REG,MP),RREG, RMP);

	PATCH(cp4);
	FM3I(2, Ojmpl, 0, RA0, RLINK);		// call destroy(t(fp))
	NOOP;
	mem(Ostw, O(REG,SP),RREG, RFP);
	mem(Oldw, O(Frame,lr),RFP, RA1);
	mem(Oldw, O(Frame,fp),RFP, RFP);
	mem(Ostw, O(REG,FP),RREG, RFP);
	FM3I(2, Ojmpl, 0, RA1, RZ);		// goto lr(Rfp)
	NOOP;

	PATCH(cp6);
	FM3I(2, Ojmpl, 0, RA0, RLINK);		// call destroy(t(fp))
	NOOP;
	mem(Ostw, O(REG,SP),RREG, RFP);
	mem(Oldw, O(Frame,lr),RFP, RA1);
	mem(Oldw, O(Frame,fp),RFP, RFP);
	mem(Ostw, O(REG,FP),RREG, RFP);
	mem(Oldw, O(REG,xpc),RREG, RA2);
	FM3I(2, Oadd, 0x8, RA2, RA2);
	FM3I(2, Ojmpl, 0, RA2, RZ);		// return to uncompiled code
	mem(Ostw, O(REG,PC),RREG, RA1);
	
	PATCH(cp1);
	PATCH(cp2);
	PATCH(cp3);
	PATCH(cp5);
	i.add = AXNON;
	punt(&i, TCHECK|NEWPC, optab[IRET]);
}

static void
maccolr(void)
{
	ulong *br;

	/* color the pointer in RA1 */
	FM3I(2, Oadd, 1, RA0, RA0);
	mem(Ostw, O(Heap, ref)-sizeof(Heap), RA1, RA0);
	mem(Oldw, O(Heap, color)-sizeof(Heap), RA1, RA0);
	mem(Oldw, 0, RA2, RA2);
	FM3(2, Ocmp, RA0, RA2, RZ);
	br = code;
	BRA(Obe, 0);
	con(propagator, RA2, 1);
	mem(Ostw, O(Heap, color)-sizeof(Heap), RA1, RA2);	
	con((ulong)&nprop, RA2, 1);
	RETURN;
	mem(Ostw, 0, RA2, RA2);	
	PATCH(br);
	RETURN;
	NOOP;
}

static void
macmcal(void)
{
	ulong *lab1, *lab2;

	mem(Oldw, O(Modlink, prog), RA3, RA1);
	FM3I(2, Ocmp, 0, RA1, RZ);
	lab1 = code;
	BRA(Obne, 0);
	NOOP;

	mem(Ostw, O(REG, st), RREG, RLINK);
	mem(Ostw, O(REG, FP), RREG, RA2);
	CALL(rmcall);				// CALL rmcall
	mem(Ostw, O(REG, dt), RREG, RA0);

	con((ulong)&R, RREG, 1);		// MOVL	$R, RREG
	mem(Oldw, O(REG, st), RREG, RLINK);
	mem(Oldw, O(REG, FP), RREG, RFP);
	mem(Oldw, O(REG, MP), RREG, RMP);
	RETURN;
	NOOP;

	PATCH(lab1);				// patch:
	FM3(2, Oor, RA2, RZ, RFP);
	mem(Ostw, O(REG, M), RREG, RA3);	// MOVL RA3, R.M
	mem(Oldw, O(Heap, ref)-sizeof(Heap), RA3, RA1);
	FM3I(2, Oadd, 1, RA1, RA1);
	mem(Ostw, O(Heap, ref)-sizeof(Heap), RA3, RA1);
	mem(Oldw, O(Modlink, compiled), RA3, RA1);
	mem(Oldw, O(Modlink, MP), RA3, RMP);	// MOVL R.M->MP, RMP
	FM3I(2, Ocmp, 0, RA1, RZ);
	lab2 = code;
	BRA(Obe, 0);
	mem(Ostw, O(REG, MP), RREG, RMP);	// MOVL RA3, R.MP	R.MP = ml->MP

	FM3I(2, Ojmpl, 0, RA0, RZ);
	NOOP;

	PATCH(lab2);
	mem(Ostw, O(REG,FP),RREG, RFP);
	mem(Oldw, O(REG,xpc),RREG, RA1);
	FM3I(2, Oadd, 0x8, RA1, RA1);
	FM3I(2, Ojmpl, 0, RA1, RZ);		// call to uncompiled code
	mem(Ostw, O(REG,PC),RREG, RA0);
}

static void
macfram(void)
{
	ulong *lab1;

	mem(Oldw, O(REG, SP), RREG, RA0);	// MOVL	R.SP, RA0
	mem(Oldw, O(Type, size), RA3, RA1);
	FM3(2, Oadd, RA0, RA1, RA0);
	mem(Oldw, O(REG, TS), RREG, RA1);
	FM3(2, Ocmp, RA1, RA0, RZ);
	lab1 = code;
	BRA(Obl, 0);
	NOOP;

	mem(Ostw, O(REG, s), RREG, RA3);
	mem(Ostw, O(REG, st), RREG, RLINK);
	CALL(extend);				// CALL	extend
	mem(Ostw, O(REG, FP), RREG, RFP);	// MOVL	RFP, R.FP

	con((ulong)&R, RREG, 1);
	mem(Oldw, O(REG, st), RREG, RLINK);
	mem(Oldw, O(REG, FP), RREG, RFP);	// MOVL	R.MP, RMP
	mem(Oldw, O(REG, s), RREG, RA2);	// MOVL	R.s, *R.d
	mem(Oldw, O(REG, MP), RREG, RMP);	// MOVL R.MP, RMP
	RETURN;					// RET
	NOOP;

	PATCH(lab1);
	mem(Oldw, O(REG, SP), RREG, RA2);	// MOVL	R.SP, RA2
	mem(Ostw, O(REG, SP), RREG, RA0);	// MOVL	RA0, R.SP

	mem(Ostw, O(Frame, t), RA2, RA3);	// MOVL	RA3, t(RA2) f->t = t
	mem(Oldw, O(Type, initialize), RA3, RA3);
	FM3I(2, Ojmpl, 0, RA3, RZ);
	mem(Ostw, REGMOD*4, RA2, RZ);     	// MOVL $0, mr(RA2) f->mr
}

static void
macmfra(void)
{
	mem(Ostw, O(REG, st), RREG, RLINK);
	mem(Ostw, O(REG, s), RREG, RA3);	// Save type
	mem(Ostw, O(REG, d), RREG, RA0);	// Save destination
	CALL(rmfram);				// CALL rmfram
	mem(Ostw, O(REG, FP), RREG, RFP);

	con((ulong)&R, RREG, 1);
	mem(Oldw, O(REG, st), RREG, RLINK);
	mem(Oldw, O(REG, FP), RREG, RFP);
	mem(Oldw, O(REG, MP), RREG, RMP);
	RETURN;
	NOOP;
}

void
comd(Type *t)
{
	int i, j, m, c;

	mem(Ostw, O(REG, dt), RREG, RLINK);
	for(i = 0; i < t->np; i++) {
		c = t->map[i];
		j = i<<5;
		for(m = 0x80; m != 0; m >>= 1) {
			if(c & m) {
				CALL(base+macro[MacFRP]);
				mem(Oldw, j, RFP, RA0);
			}
			j += sizeof(WORD*);
		}
	}
	mem(Oldw, O(REG, dt), RREG, RLINK);
	RETURN;
	NOOP;
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
	RETURN;
	NOOP;
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

	if(cflag > 1)
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
	tmp = mallocz(1024*sizeof(ulong), 0);
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
		patch[i] = n;
		n += code - tmp;
	}

	for(i = 0; i < nelem(mactab); i++) {
		code = tmp;
		mactab[i].gen();
		macro[mactab[i].idx] = n;
		n += code - tmp;
	}

	base = mallocz((n+nlit)*sizeof(*code), 0);
	if(base == nil)
		goto bad;

	if(cflag > 1)
		print("dis=%5d %5d sparc=%5d asm=%.8p lit=%d: %s\n",
			size, size*sizeof(Inst), n, base, nlit, m->name);

	pass++;
	nlit = 0;
	litpool = base+n;
	code = base;

	for(i = 0; i < size; i++) {
		s = code;
		comp(&m->prog[i]);
		if(cflag > 2) {
			print("%d %D\n", i, &m->prog[i]);
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

	if(n != (code - base))
		error(exCphase);

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
	free(tmp);
	free(base);
	return 0;
}
