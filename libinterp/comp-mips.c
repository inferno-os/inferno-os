#include "lib9.h"
#include "isa.h"
#include "interp.h"
#include "raise.h"

#define T(r)	*((void**)(R.r))

#define	SRR(op,c,r1,r2)		gen((op)|((c)<<6)|((r1)<<16)|((r2)<<11))
#define	RRR(op,r1,r2,r3)	gen((op)|((r1)<<16)|((r2)<<21)|((r3)<<11))
#define	FRRR(op,r1,r2,r3)	gen((op)|((r1)<<16)|((r2)<<11)|((r3)<<6))
#define	FI(op,c)		gen((op)|((c)&0xffff))
#define	IRR(op,c,r1,r2)		gen((op)|((c)&0xffff)|((r1)<<21)|((r2)<<16))
#define	BRRI(op,r1,r2,c)	gen((op)|((r1)<<21)|((r2)<<16)|((c)&0xffff))
#define	BRI(op,r,c)		gen((op)|((r)<<21)|((c)&0xffff))
#define	JR(op,r)		gen((op)|((r)<<21))
#define	J(op,c)			gen((op)|(((ulong)(c)>>2)&0x3FFFFFFUL))

enum
{
	Rzero	= 0,

	Ro1	= 8,
	Ro2	= 9,
	Ro3	= 10,
	Ri	= 11,
	Rj	= 12,

	Rmp	= 13,
	Rfp	= 14,
	Rreg	= 15,

	Rpic	= 25,
	Rlink	= 31,

	Rf1	= 4,
	Rf2	= 6,

	Olw	= 0x23<<26,
	Olbu	= 0x24<<26,
	Olhu	= 0x25<<26,
	Osw	= 0x2b<<26,
	Osb	= 0x28<<26,
	Oaddui	= 0x09<<26,
	Olui	= 0x0f<<26,
	Oori	= 0x0d<<26,
	Odiv	= (0x00<<26) | 0x1a,
	Omul	= (0x00<<26) | 0x18,
	Omfhi	= (0x00<<26) | 0x10,
	Omflo	= (0x00<<26) | 0x12,
	Osubu	= (0x00<<26) | 0x23,
	Oaddu	= (0x00<<26) | 0x21,
	Oand	= (0x00<<26) | 0x24,
	Oor	= (0x00<<26) | 0x25,
	Oxor	= (0x00<<26) | 0x26,
	Odelay	= (0x00<<26) | 0x27,
	Osll	= (0x00<<26) | 0x00,
	Osrl	= (0x00<<26) | 0x02,
	Osra	= (0x00<<26) | 0x03,
	Osllv	= (0x00<<26) | 0x04,
	Osrlv	= (0x00<<26) | 0x06,
	Osrav	= (0x00<<26) | 0x07,
	Oslt	= (0x00<<26) | 0x2a,
	Osltu	= (0x00<<26) | 0x2b,
	Obeq	= 0x04<<26,
	Obne	= 0x05<<26,
	Obltz	= (0x01<<26) | (0x0<<16),
	Obgtz	= (0x07<<26) | (0x0<<16),
	Oblez	= (0x06<<26) | (0x0<<16),
	Obgez	= (0x01<<26) | (0x1<<16),
	Ojr	= (0x00<<26) | 0x08,
	Ojalr	= (0x00<<26) | 0x09 | (Rlink<<11),
	Oj	= (0x02<<26),
	Ojal	= (0x03<<26),
	Olea	= Oaddui,		// pseudo op

	Olf	= 0x31<<26,
	Osf	= 0x39<<26,
	Oaddf	= (0x11<<26) | (17<<21) | 0,
	Osubf	= (0x11<<26) | (17<<21) | 1,
	Omulf	= (0x11<<26) | (17<<21) | 2,
	Odivf	= (0x11<<26) | (17<<21) | 3,
	Onegf	= (0x11<<26) | (17<<21) | 7,

	Ocvtwf	= (0x11<<26) | (20<<21) | 33,
	Ocvtfw	= (0x11<<26) | (17<<21) | 36,

	Ofeq	= (0x11<<26) | (17<<21) | (3<<4) | 2,
	Oflt	= (0x11<<26) | (17<<21) | (3<<4) | 12,

	Obrf	= (0x11<<26) | (0x100<<16),
	Obrt	= (0x11<<26) | (0x101<<16),

	SRCOP	= (1<<0),
	DSTOP	= (1<<1),
	WRTPC	= (1<<2),
	TCHECK	= (1<<3),
	NEWPC	= (1<<4),
	DBRAN	= (1<<5),
	THREOP	= (1<<6),

	ANDAND	= 1,
	OROR,
	EQAND,

	XOR,
	IOR,
	AND,
	ADD,
	SUB,

	OMASK	= (1<<4) - 1,
	REV1	= 1<<4,
	REV2	= 1<<5,

	MacRET	= 0,
	MacFRP,
	MacINDX,
	MacCASE,
	MacLENA,
	MacFRAM,
	MacMOVM,
	MacCOLR,
	MacMCAL,
	MacMFRA,
	MacEND,
	NMACRO
};

extern	char	Tmodule[];
	void	(*comvec)(void);
extern	void	das(ulong*);
static	ulong*	code;
static	ulong*	base;
static	ulong*	patch;
static	int	pass;
static	int	regdelay;
static	Module*	mod;
static	ulong*	tinit;
static	ulong*	litpool;
static	int	nlit;
static	ulong	macro[NMACRO];
static	void	rdestroy(void);
static	void	macret(void);
static	void	macfrp(void);
static	void	macindx(void);
static	void	maccase(void);
static	void	maclena(void);
static	void	macfram(void);
static	void	macmovm(void);
static	void	maccvtfw(void);
static	void	maccolr(void);
static	void	macend(void);
static	void	macmcal(void);
static	void	macmfra(void);

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
	MacMOVM,	macmovm,
	MacLENA,	maclena,
	MacINDX,	macindx,
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

void
urk(char *s)
{
	print("urk: %s\n", s);
	exits(0);
}

void
gen(ulong o)
{
	*code++ = o;
}

void
delay(void)
{
	gen(Odelay);
}

int
bigc(long c)
{
	c >>= 15;
	if(c == 0 || c == -1)
		return 0;
	return 1;
}

void
ldbigc(ulong c, int reg)
{
	IRR(Olui, c>>16,Rzero,reg);
	IRR(Oori, c,reg,reg);
}

void
ldc(ulong c, int reg)
{

	if(bigc(c))
		ldbigc(c, reg);
	else
		IRR(Oaddui, c,Rzero, reg);
}

void
xchg(void)
{
	ulong t;

	t = code[-1];
	code[-1] = code[-2];
	code[-2] = t;
}

void
opx(int mode, Adr *a, int op, int reg, int del)
{
	ulong c;
	int r, rx;

	switch(mode) {
	case AFP:
		c = a->ind;
		if(bigc(c))
			urk("bigc op1b 1");
		if(regdelay == Rfp)
			delay();
		IRR(op, c,Rfp, reg);
		break;
	case AMP:
		c = a->ind;
		if(bigc(c))
			urk("bigc op1b 2");
		if(regdelay == Rmp)
			delay();
		IRR(op, c,Rmp, reg);
		break;
	case AIMM:
		if(op == Olea) {
			if(a->imm != 0) {
				ldc(a->imm, reg);
				IRR(Osw, O(REG,st),Rreg, reg);
			} else
				IRR(Osw, O(REG,st),Rreg, Rzero);
			IRR(Oaddui, O(REG,st),Rreg, reg);
		} else
			ldc(a->imm, reg);
		return;
	case AIND|AFP:
		r = Rfp;
		goto offset;
	case AIND|AMP:
		r = Rmp;
	offset:
		if(regdelay == r)
			delay();
		c = a->i.s;
		rx = Ri;
		if(op == Olea || op == Olw)
			rx = reg;
		IRR(Olw, a->i.f,r, rx);
		if(c != 0 || op != Oaddui) {
			delay();
			IRR(op, c,rx, reg);
		}
		break;
	}
	if(op != Olea && del)
		delay();
	regdelay = 0;
}

void
op1(Inst *i, int op, int reg, int del)
{
	opx(USRC(i->add), &i->s, op, reg, del);
}

void
op3(Inst *i, int op, int reg, int del)
{
	opx(UDST(i->add), &i->d, op, reg, del);
}

void
op2(Inst *i, int op, int reg, int del)
{
	switch(i->add & ARM) {
	case AXNON:
		op3(i, op, reg, del);
		return;
	case AXIMM:
		if(op == Olea) {
			if((short)i->reg != 0) {
				ldc((short)i->reg, reg);
				IRR(Osw, O(REG,t),Rreg, reg);
			} else
				IRR(Osw, O(REG,t),Rreg, Rzero);
			IRR(Oaddui, O(REG,t),Rreg, reg);
		} else
			ldc((short)i->reg, reg);
		return;
	case AXINF:
		IRR(op, i->reg,Rfp, reg);
		break;
	case AXINM:
		IRR(op, i->reg,Rmp, reg);
		break;
	}
	if(op != Olea && del)
		delay();
}

ulong
branch(Inst *i)
{
	ulong rel;

	if(base == 0)
		return 0;
	rel = patch[(Inst*)i->d.imm - mod->prog];
	rel += (base - code) - 1;
	return rel & 0xffff;
}

static void
literal(ulong imm, int roff)
{
	nlit++;

	ldbigc((ulong)litpool, Ro1);
	IRR(Osw, roff, Rreg, Ro1);

	if(pass == 0)
		return;

	*litpool = imm;
	litpool++;	
}

void
punt(Inst *i, int m, void (*fn)(void))
{
	ulong *cp, pc;

	if(m & SRCOP) {
		op1(i, Olea, Ro1, 1);
		IRR(Osw, O(REG,s),Rreg, Ro1);
	}
	if(m & DSTOP) {
		op3(i, Olea, Ro3, 1);
		IRR(Osw, O(REG,d),Rreg, Ro3);
	}
	if(m & WRTPC) {
		pc = patch[i-mod->prog+1];
		ldbigc((ulong)(base+pc), Ro1);
		IRR(Osw, O(REG,PC),Rreg, Ro1);
	}
	if(m & DBRAN) {
		pc = patch[(Inst*)i->d.imm-mod->prog];
		literal((ulong)(base+pc), O(REG, d));
	}

	if((i->add&ARM) == AXNON) {
		if(m & THREOP) {
			delay();
			IRR(Olw, O(REG,d),Rreg, Ro2);
			delay();
			IRR(Osw, O(REG,m),Rreg, Ro2);
		}
	} else {
		op2(i, Olea, Ro2, 1);
		IRR(Osw, O(REG,m),Rreg, Ro2);
	}

	ldc((ulong)fn, Rpic);
	JR(Ojalr, Rpic);
	IRR(Osw, O(REG,FP),Rreg, Rfp);

	ldc((ulong)&R, Rreg);
	IRR(Olw, O(REG,FP),Rreg, Rfp);
	IRR(Olw, O(REG,MP),Rreg, Rmp);
	regdelay = Rmp;

	if(m & TCHECK) {
		IRR(Olw, O(REG,t),Rreg, Ro1);
		xchg();
		cp = code;
		BRRI(Obeq,Ro1,Rzero,0);
		IRR(Olw, O(REG,xpc),Rreg, Ro2);
		delay();
		JR(Ojr, Ro2);
		delay();
		*cp |= (code - cp) - 1;
		regdelay = 0;
	}

	if(m & NEWPC) {
		IRR(Olw, O(REG,PC),Rreg, Ro1);
		if(m & TCHECK)
			delay();
		else
			xchg();
		JR(Ojr, Ro1);
		delay();
		regdelay = 0;
	}
}
				
static void
comgoto(Inst *i)
{
	WORD *t, *e;

	op1(i, Olw, Ro2, 0);
	op3(i, Olea, Ro3, 0);
	SRR(Osll, 2, Ro2, Ro2);
	RRR(Oaddu, Ro2, Ro3, Ro3);
	IRR(Olw, 0,Ro3, Ro1);
	delay();
	JR(Ojr, Ro1);
	delay();

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
		op1(i, Olw, Ro1, 0);		// v
		op3(i, Olea, Ro3, 0);		// table
		J(Oj, base+macro[MacCASE]);
		xchg();
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
	Modlink *ml;
	ulong *cp1, *cp2;

	op1(i, Olw, Ro1, 0);
	ldc((ulong)H, Ri);
	cp1 = code;
	BRRI(Obeq, Ro1,Ri, 0);
	delay();

	ml = nil;
	IRR(Olw, (ulong)&ml->links[i->reg].frame,Ro1, Ri);
	delay();
	IRR(Olw, O(Type,initialize),Ri, Ro2);
	delay();
	cp2 = code;
	BRRI(Obne, Ro2,Rzero, 0);
	delay();

	op3(i, Olea, Rj, 0);

	*cp1 |= (code - cp1) - 1;
	ldbigc((ulong)(base+patch[i-mod->prog+1]), Rlink);
	J(Oj, base+macro[MacMFRA]);
	xchg();

	*cp2 |= (code - cp2) - 1;
	J(Ojal, base+macro[MacFRAM]);
	delay();
	op3(i, Osw, Ro1, 0);
}

static void
commcall(Inst *i)
{
	Modlink *ml;

	op1(i, Olw, Ro1, 0);				// f in Ro1
	IRR(Olw, O(REG,M),Rreg, Ro3);
	IRR(Osw, O(Frame,fp),Ro1, Rfp);			// f->fp = R.FP
	IRR(Osw, O(Frame,mr),Ro1, Ro3);			// f->mr = R.M
	op3(i, Olw, Ri, 1);
	ml = nil;
	IRR(Olw, (ulong)&ml->links[i->reg].u.pc,Ri, Rj);// ml->entry in Rj
	J(Ojal, base+macro[MacMCAL]);
	xchg();
}

static void
cbral(Inst *i, int op, int mode)
{
	ulong *cp;

	cp = 0;
	op1(i, Olea, Ri, 0);
	op2(i, Olea, Rj, 0);
	IRR(Olw, 0,Ri, Ro1);
	IRR(Olw, 0,Rj, Ro2);
	IRR(Olw, 4,Ri, Ri);

	switch(mode & OMASK) {
	case ANDAND:
		cp = code;
		BRRI(Obne, Ro2,Ro1, 0);
		goto b1;

	case OROR:
		BRRI(Obne, Ro2,Ro1, branch(i));
	b1:
		IRR(Olw, 4,Rj, Rj);
		delay();
		BRRI(op, Rj,Ri, branch(i));
		break;

	case EQAND:
		if(mode & REV1)
			RRR(Oslt, Ro2,Ro1, Ro3);
		else
			RRR(Oslt, Ro1,Ro2, Ro3);
		BRI(Obne, Ro3, branch(i));
		IRR(Olw, 4,Rj, Rj);
		cp = code;
		BRRI(Obne, Ro2,Ro1, 0);
		if(mode & REV2)
			RRR(Osltu, Rj,Ri, Ro3);
		else
			RRR(Osltu, Ri,Rj, Ro3);
		BRI(op, Ro3, branch(i));
		break;
	}
	delay();
	if(cp)
		*cp |= (code - cp) - 1;
}

static void
op12(Inst *i, int b1flag, int b2flag)
{
	int o1, o2;

	o1 = Olw;
	if(b1flag)
		o1 = Olbu;
	o2 = Olw;
	if(b2flag)
		o2 = Olbu;
	if((i->add & ARM) == AXIMM) {
		op1(i, o1, Ro1, 0);
		op2(i, o2, Ro2, 1);
	} else {
		op2(i, o2, Ro2, 0);
		op1(i, o1, Ro1, 1);
	}
}

static void
op13(Inst *i, int o1, int o2)
{
	op1(i, o1, Ro1, 1);
	op3(i, o2, Ro1, 0);
}

static void
shrl(Inst *i)
{
	int c;

	if(USRC(i->add) != AIMM) {
		punt(i, SRCOP|DSTOP|THREOP, optab[i->op]);
		return;
	}
	c = i->s.imm;
	op2(i, Olea, Ro3, 1);
	IRR(Olw, 0,Ro3, Ro1);
	if(c >= 32) {
		if((i->add&ARM) != AXNON)
			op3(i, Olea, Ro3, 0);
		else
			delay();
		SRR(Osra, 31, Ro1, Ro2);
		IRR(Osw, 0,Ro3, Ro2);
		if(c >= 64) {
			IRR(Osw, 4,Ro3, Ro2);
			return;
		}
		if(c > 32)
			SRR(Osra, c-32, Ro1, Ro1);
		IRR(Osw, 4,Ro3, Ro1);
		return;
	}
	IRR(Olw, 4,Ro3, Ro2);
	if((i->add&ARM) != AXNON)
		op3(i, Olea, Ro3, !c);
	if(c != 0) {
		SRR(Osll, 32-c, Ro1, Ri);
		SRR(Osra, c, Ro1, Ro1);
		SRR(Osrl, c, Ro2, Ro2);
		RRR(Oor, Ri, Ro2, Ro2);
	}
	IRR(Osw, 4,Ro3, Ro2);
	IRR(Osw, 0,Ro3, Ro1);
}

static void
shll(Inst *i)
{
	int c;

	if(USRC(i->add) != AIMM) {
		punt(i, SRCOP|DSTOP|THREOP, optab[i->op]);
		return;
	}
	c = i->s.imm;
	if(c >= 64) {
		op3(i, Olea, Ro3, 1);
		IRR(Osw, 0,Ro3, Rzero);
		IRR(Osw, 4,Ro3, Rzero);
		return;
	}
	op2(i, Olea, Ro3, 1);
	if(c >= 32) {
		IRR(Olw, 4,Ro3, Ro1);
		if((i->add&ARM) != AXNON)
			op3(i, Olea, Ro3, 1);
		IRR(Osw, 4,Ro3, Rzero);
		if(c > 32)
			SRR(Osll, c-32, Ro1, Ro1);
		IRR(Osw, 0,Ro3, Ro1);
		return;
	}
	IRR(Olw, 4,Ro3, Ro2);
	IRR(Olw, 0,Ro3, Ro1);
	if((i->add&ARM) != AXNON)
		op3(i, Olea, Ro3, !c);
	if(c != 0) {
		SRR(Osrl, 32-c, Ro2, Ri);
		SRR(Osll, c, Ro2, Ro2);
		SRR(Osll, c, Ro1, Ro1);
		RRR(Oor, Ri, Ro1, Ro1);
	}
	IRR(Osw, 4,Ro3, Ro2);
	IRR(Osw, 0,Ro3, Ro1);
}

static void
compdbg(void)
{
	print("%s:%d@%.8ux\n", R.M->m->name, R.t, R.st);
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
	case ILSRL:
	case IMNEWZ:
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
	case IHEADL:
	case IHEADMP:
	case IINDC:
	case ILENC:
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
	case ICVTFR:
	case ICVTRF:
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
		op13(i, Olw, Osb);
		break;
	case ICVTBW:
		op13(i, Olbu, Osw);
		break;
	case ICVTWS:
		op13(i, Olw, Osb);
		break;
	case ICVTSW:
		op13(i, Olhu, Osw);
		break;
	case IMOVB:
		op13(i, Olbu, Osb);
		break;
	case IMOVW:
		if(USRC(i->add) == AIMM && i->s.imm == 0) {
			op3(i, Osw, Rzero, 0);
			break;
		}
		op13(i, Olw, Osw);
		break;
	case ICVTLW:
		op1(i, Olea, Ro1, 1);
		IRR(Olw, 4,Ro1, Ro1);
		delay();
		op3(i, Osw, Ro1, 0);
		break;
	case ICVTWL:
		op1(i, Olw, Ro1, 0);
		op3(i, Olea, Ro2, 0);
		SRR(Osra, 31, Ro1, Ro3);
		IRR(Osw, 4,Ro2, Ro1);
		IRR(Osw, 0,Ro2, Ro3);
		break;
	case IHEADM:
		op1(i, Olw, Ro1, 1);
		IRR(Oaddui, OA(List,data),Ro1,  Ro1);
		goto m1;
	case IMOVM:
		op1(i, Olea, Ro1, 0);
	m1:
		op2(i, Olw, Ro2, 0);
		op3(i, Olea, Ro3, 0);
		J(Ojal, base+macro[MacMOVM]);
		xchg();
		break;
	case IRET:
		J(Oj, base+macro[MacRET]);
		delay();
		break;
	case IFRAME:
		if(UXSRC(i->add) != SRC(AIMM)) {
			punt(i, SRCOP|DSTOP, optab[i->op]);
			break;
		}
		ldc((ulong)mod->type[i->s.imm], Ri);
		J(Ojal, base+macro[MacFRAM]);
		xchg();
		op3(i, Osw, Ro1, 0);
		tinit[i->s.imm] = 1;
		break;
	case ILEA:
		op13(i, Olea, Osw);
		break;
	case IHEADW:
		op1(i, Olw, Ro1, 1);
		IRR(Olw, OA(List,data),Ro1, Ro1);
		delay();
		op3(i, Osw, Ro1, 0);
		break;
	case IHEADF:
		op1(i, Olw, Ro1, 1);
		IRR(Olw, OA(List,data),Ro1, Ro2);
		IRR(Olw, OA(List,data)+4,Ro1, Ro3);
		op3(i, Olea, Ro1, 1);
		IRR(Osw, 0,Ro1, Ro2);
		IRR(Osw, 4,Ro1, Ro3);
		break;
	case IHEADB:
		op1(i, Olw, Ro1, 1);
		IRR(Olbu , OA(List,data),Ro1, Ro1);
		delay();
		op3(i, Osb, Ro1, 0);
		break;
	case ITAIL:
		op1(i, Olw, Ro1, 1);
		IRR(Olw, O(List,tail),Ro1, Ro1);
		goto movp;
	case IMOVP:
		op1(i, Olw, Ro1, 0);
		goto movp;
	case IHEADP:
		op1(i, Olw, Ro1, 1);
		IRR(Olw, OA(List,data),Ro1, Ro1);
	movp:
		ldc((ulong)H, Ro2);
		cp = code;
		BRRI(Obeq,Ro1,Ro2,0);
		ldbigc((ulong)&mutator, Ri);
		J(Ojal, base+macro[MacCOLR]);
		xchg();
		*cp |= (code - cp) - 1;
		op3(i, Olea, Ro3, 1);
		IRR(Olw, 0,Ro3, Ri);
		J(Ojal, base+macro[MacFRP]);
		IRR(Osw, 0,Ro3, Ro1);
		break;
	case ILENA:
		op1(i, Olw, Ri, 0);
		J(Ojal, base+macro[MacLENA]);
		xchg();
		op3(i, Osw, Ro1, 0);
		break;
	case ILENL:
		op1(i, Olw, Ro1, 0);
		ldc((ulong)H, Ro2);
		cp = code;
		BRRI(Obeq, Ro1,Ro2, 0);
		ldc(0, Ro3);

		cp1 = code;
		IRR(Olw, O(List,tail),Ro1, Ro1);
		IRR(Oaddui, 1,Ro3, Ro3);
		BRRI(Obne, Ro1,Ro2, (cp1-code)-1);
		delay();

		*cp |= (code - cp) - 1;
		op3(i, Osw, Ro3, 0);
		break;
	case IMOVL:
	case IMOVF:
		op1(i, Olea, Ro1, 1);
		IRR(Olw, 0,Ro1, Ro2);
		IRR(Olw, 4,Ro1, Ro3);
		op3(i, Olea, Ro1, 1);
		IRR(Osw, 0,Ro1, Ro2);
		IRR(Osw, 4,Ro1, Ro3);
		break;
	case ICVTFW:
		op1(i, Olea, Ro1, 1);
		IRR(Olf, 0,Ro1, Rf2+1);
		IRR(Olf, 4,Ro1, Rf2);
		delay();
		FRRR(Ocvtfw, 0, Rf2, Rf2);
		op3(i, Olea, Ro2, 1);
		IRR(Osf, 0,Ro2, Rf2);
		break;
	case ICVTWF:
		op1(i, Olea, Ro1, 1);
		IRR(Olf, 0,Ro1, Rf2);
		delay();
		FRRR(Ocvtwf, 0, Rf2, Rf2);
		op3(i, Olea, Ro2, 1);
		IRR(Osf, 0,Ro2, Rf2+1);
		IRR(Osf, 4,Ro2, Rf2);
		break;
	case INEGF:
		op1(i, Olea, Ro1, 1);
		IRR(Olf, 0,Ro1, Rf1+1);
		IRR(Olf, 4,Ro1, Rf1);
		op3(i, Olea, Ro2, 1);
		FRRR(Onegf, 0, Rf1,Rf2);
		IRR(Osf, 0,Ro2, Rf2+1);
		IRR(Osf, 4,Ro2, Rf2);
		break;
	case IXORL:
	case IORL:
	case IANDL:
	case IADDL:
	case ISUBL:
		op1(i, Olea, Ro1, 0);
		op2(i, Olea, Ro3, 0);

		IRR(Olw, 4,Ro1, Rj);	/* ls */
		IRR(Olw, 4,Ro3, Ro2);
		IRR(Olw, 0,Ro1, Ri);	/* ms */
		IRR(Olw, 0,Ro3, Ro1);

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
			RRR(o, Ri,Ro1, Ro1);
			RRR(o, Rj,Ro2, Ro2);
			break;
		case IADDL:
			RRR(Oaddu, Ri,Ro1, Ro1);
			RRR(Oaddu, Rj,Ro2, Ro2);
			RRR(Osltu, Rj,Ro2, Ri);
			RRR(Oaddu, Ri,Ro1, Ro1);
			break;
		case ISUBL:
			RRR(Osubu, Ri,Ro1, Ro1);
			RRR(Osltu, Rj,Ro2, Ri);
			RRR(Osubu, Rj,Ro2, Ro2);
			RRR(Osubu, Ri,Ro1, Ro1);
			break;
		}
		if((i->add&ARM) != AXNON)
			op3(i, Olea, Ro3, 1);
		IRR(Osw, 0,Ro3, Ro1);
		IRR(Osw, 4,Ro3, Ro2);
		break;
	case ISHLL:
		shll(i);
		break;
	case ISHRL:
		shrl(i);
		break;
	case IADDF:
	case ISUBF:
	case IMULF:
	case IDIVF:
	case IBEQF:
	case IBGEF:
	case IBGTF:
	case IBLEF:
	case IBLTF:
	case IBNEF:
		op1(i, Olea, Ro1, 0);
		op2(i, Olea, Ro2, 0);
		IRR(Olf, 0,Ro1, Rf1+1);
		IRR(Olf, 4,Ro1, Rf1);
		IRR(Olf, 0,Ro2, Rf2+1);
		IRR(Olf, 4,Ro2, Rf2);
		switch(i->op) {
		case IADDF:	o = Oaddf; goto f1;
		case ISUBF:	o = Osubf; goto f1;
		case IMULF:	o = Omulf; goto f1;
		case IDIVF:	o = Odivf; goto f1;
		case IBEQF:	o = Ofeq; q = Obrt; goto f2;
		case IBGEF:	o = Oflt; q = Obrf; goto f3;
		case IBGTF:	o = Oflt; q = Obrt; goto f2;
		case IBLEF:	o = Oflt; q = Obrf; goto f2;
		case IBLTF:	o = Oflt; q = Obrt; goto f3;
		case IBNEF:	o = Ofeq; q = Obrf; goto f2;
		f1:
			op3(i, Olea, Ro1, 0);
			FRRR(o, Rf1,Rf2, Rf2);
			IRR(Osf, 0,Ro1, Rf2+1);
			IRR(Osf, 4,Ro1, Rf2);
			break;
		f2:
			delay();
			FRRR(o, Rf1,Rf2, 0);
			goto f4;
		f3:
			delay();
			FRRR(o, Rf2,Rf1, 0);
			goto f4;
		f4:
			delay();
			FI(q, branch(i));
			delay();
			break;
		}
		break;

	case IBLTB:
	case IBLEB:
	case IBGTB:
	case IBGEB:
	case IBEQB:
	case IBNEB:
		b = 1;
		goto s1;
	case IBLTW:
	case IBLEW:
	case IBGTW:
	case IBGEW:
	case IBEQW:
	case IBNEW:
		b = 0;
	s1:
		op12(i, b, b);
		switch(i->op) {
		case IBLTB:
		case IBLTW:	o = Obne; goto b1;
		case IBGEB:
		case IBGEW:	o = Obeq; goto b1;
		case IBGTB:
		case IBGTW:	o = Obne; goto b2;
		case IBLEB:
		case IBLEW:	o = Obeq; goto b2;
		case IBEQB:
		case IBEQW:	o = Obeq; goto b3;
		case IBNEB:
		case IBNEW:	o = Obne; goto b3;
		b1:	RRR(Oslt, Ro2,Ro1, Ro3);
			BRI(o,Ro3, branch(i));
			break;
		b2:	RRR(Oslt, Ro1,Ro2, Ro3);
			BRI(o,Ro3, branch(i));
			break;
		b3:	BRRI(o, Ro2,Ro1, branch(i));
			break;
		}
		delay();
		break;

	case IBEQL:
		cbral(i, Obeq, ANDAND);
		break;
	case IBNEL:
		cbral(i, Obne, OROR);
		break;
	case IBLEL:
		cbral(i, Obeq, EQAND|REV1);
		break;
	case IBGTL:
		cbral(i, Obne, EQAND);
		break;
	case IBLTL:
		cbral(i, Obne, EQAND|REV1|REV2);
		break;
	case IBGEL:
		cbral(i, Obeq, EQAND|REV2);
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
		switch(i->op) {
		case IADDB:
		case IADDW:	o = Oaddu; goto c1;
		case ISUBB:
		case ISUBW:	o = Osubu; goto c1;
		case IANDB:
		case IANDW:	o = Oand; goto c1;
		case IORB:
		case IORW:	o = Oor; goto c1;
		case IXORB:
		case IXORW:	o = Oxor; goto c1;
		c1:
			RRR(o, Ro1,Ro2, Ro3);
			break;
		case ISHLB:
		case ISHLW:	o = Osllv; goto c2;
		case ILSRW:	o = Osrlv; goto c2;
		case ISHRB:
		case ISHRW:	o = Osrav; goto c2;
		c2:
			RRR(o, Ro2,Ro1, Ro3);
			break;
		case IMULB:
		case IMULW:	q = Omul; o = Omflo; goto c3;
		case IDIVB:
		case IDIVW:	q = Odiv; o = Omflo; goto c3;
		case IMODB:
		case IMODW:	q = Odiv; o = Omfhi; goto c3;
		c3:
			RRR(q, Ro1,Ro2, Rzero);
			RRR(o, Rzero,Rzero, Ro3);
			break;
		}
		op3(i, b? Osb: Osw, Ro3, 0);
		break;
	case ICALL:
		op1(i, Olw, Ro1, 0);
		ldbigc((ulong)(base+patch[i-mod->prog+1]), Ro2);
		IRR(Osw, O(Frame,lr),Ro1, Ro2);
		IRR(Osw, O(Frame,fp),Ro1, Rfp);
		J(Oj, base+patch[(Inst*)i->d.imm - mod->prog]);
		RRR(Oaddu, Ro1,Rzero, Rfp);
		break;
	case IJMP:
		J(Oj, base+patch[(Inst*)i->d.imm - mod->prog]);
		delay();
		break;
	case IGOTO:
		comgoto(i);
		break;
	case IINDX:
		op1(i, Olw, Ro1, 0);				/* Ro1 = a */
		op3(i, Olw, Ro3, 0);				/* Ro2 = i */
		J(Ojal, base+macro[MacINDX]);
		xchg();
		op2(i, Osw, Ro2, 0);
		break;
	case IINDB:
	case IINDF:
	case IINDW:
	case IINDL:
		op1(i, Olw, Ro1, 0);			/* Ro1 = a */
		op3(i, Olw, Ro3, 0);			/* Ro3 = i */
		IRR(Olw, O(Array,data),Ro1, Ro1);	/* Ro1 = a->data */
		switch(i->op) {
		case IINDL:
		case IINDF:
			SRR(Osll, 3, Ro3, Ro3);		/* Ro3 = i*8 */
			break;
		case IINDW:
			SRR(Osll, 2, Ro3, Ro3);		/* Ro3 = i*4 */
			break;
		case IINDB:
			delay();
			break;
		}
		RRR(Oaddu, Ro1,Ro3, Ro2);		/* Ro2 = i*size + data */
		op2(i, Osw, Ro2, 0);
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

static void
preamble(void)
{
	ldc((ulong)&R, Rreg);
	IRR(Olw, O(REG,PC),Rreg, Ri);
	IRR(Olw, O(REG,FP),Rreg, Rfp);
	IRR(Olw, O(REG,MP),Rreg, Rmp);
	IRR(Osw, O(REG,xpc),Rreg, Rlink);
	JR(Ojr, Ri);
	delay();
}

static void
macfrp(void)
{
	ulong *cp1, *cp2;

	ldc((ulong)H, Ro1);
	cp1 = code;
	BRRI(Obeq, Ri,Ro1, 0);			// arg == $H
	delay();

	IRR(Olw, O(Heap,ref)-sizeof(Heap),Ri, Ro2);
	ldc((ulong)1, Ro1);
	cp2 = code;
	BRRI(Obeq, Ro1,Ro2, 0);			// ref(arg) == $1
	IRR(Oaddui, -1,Ro2, Ro2);		// ref(arg)--
	JR(Ojr, Rlink);
	IRR(Osw, O(Heap,ref)-sizeof(Heap),Ri, Ro2);

	*cp2 |= (code - cp2) - 1;
	IRR(Osw, O(REG,st),Rreg, Rlink);
	IRR(Osw, O(REG,FP),Rreg, Rfp);

	ldc((ulong)rdestroy, Rpic);
	JR(Ojalr, Rpic);				// CALL	destroy
	IRR(Osw, O(REG,s),Rreg, Ri);

	ldc((ulong)&R, Rreg);
	IRR(Olw, O(REG,st),Rreg, Rlink);
	IRR(Olw, O(REG,FP),Rreg, Rfp);
	IRR(Olw, O(REG,MP),Rreg, Rmp);

	*cp1 |= (code - cp1) - 1;
	JR(Ojr, Rlink);
	delay();
}

static void
macret(void)
{
	ulong *cp1, *cp2, *cp3, *cp4, *cp5, *cp6;
	Inst i;

// NOTE this needs to be scheduled

	IRR(Olw, O(Frame,t),Rfp, Ro1);
	delay();
	cp1 = code;
	BRRI(Obeq, Ro1,Rzero, 0);		// t(Rfp) == 0
	delay();

	IRR(Olw, O(Type,destroy),Ro1, Rpic);
	delay();
	cp2 = code;
	BRRI(Obeq, Rpic,Rzero, 0);		// destroy(t(fp)) == 0
	delay();

	IRR(Olw, O(Frame,fp),Rfp, Ro2);
	delay();
	cp3 = code;
	BRRI(Obeq, Ro2,Rzero, 0);		// fp(Rfp) == 0
	delay();

	IRR(Olw, O(Frame,mr),Rfp, Ro3);
	delay();
	cp4 = code;
	BRRI(Obeq, Ro3,Rzero, 0);		// mr(Rfp) == 0
	delay();

	IRR(Olw, O(REG,M),Rreg, Ro2);
	delay();
	IRR(Olw, O(Heap,ref)-sizeof(Heap),Ro2, Ro3);
	delay();
	IRR(Oaddui, -1,Ro3, Ro3);
	cp5 = code;
	BRRI(Obeq, Ro3,Rzero, 0);		// --ref(arg) == 0
	delay();
	IRR(Osw, O(Heap,ref)-sizeof(Heap),Ro2, Ro3);

	IRR(Olw, O(Frame,mr),Rfp, Ro1);
	delay();
	IRR(Osw, O(REG,M),Rreg, Ro1);
	IRR(Olw, O(Modlink,compiled),Ro1, Ro2);	// check for uncompiled module
	IRR(Olw, O(Modlink,MP),Ro1, Rmp);
	cp6 = code;
	BRRI(Obeq, Ro2,Rzero, 0);
	IRR(Osw, O(REG,MP),Rreg, Rmp);

	*cp4 |= (code - cp4) - 1;
	JR(Ojalr, Rpic);			// call destroy(t(fp))
	delay();
	IRR(Osw, O(REG,SP),Rreg, Rfp);
	IRR(Olw, O(Frame,lr),Rfp, Ro1);
	IRR(Olw, O(Frame,fp),Rfp, Rfp);
	IRR(Osw, O(REG,FP),Rreg, Rfp);
	JR(Ojr, Ro1);				// goto lr(Rfp)
	delay();

	*cp6 |= (code - cp6) - 1;		// returning to uncompiled module
	JR(Ojalr, Rpic);			// call destroy(t(fp))
	delay();
	IRR(Osw, O(REG,SP),Rreg, Rfp);
	IRR(Olw, O(Frame,lr),Rfp, Ro1);
	IRR(Olw, O(Frame,fp),Rfp, Rfp);
	IRR(Osw, O(REG,FP),Rreg, Rfp);
	IRR(Olw, O(REG,xpc),Rreg, Ro2);
	JR(Ojr, Ro2);				// return to uncompiled code
	IRR(Osw, O(REG,PC),Rreg, Ro1);
 
	*cp1 |= (code - cp1) - 1;
	*cp2 |= (code - cp2) - 1;
	*cp3 |= (code - cp3) - 1;
	*cp5 |= (code - cp5) - 1;
	i.add = AXNON;
	punt(&i, TCHECK|NEWPC, optab[IRET]);
}

static void
macindx(void)
{

	IRR(Olw, O(Array,t),Ro1, Ro2);
	IRR(Olw, O(Array,data),Ro1, Ro1);		// Ro1 = data
	IRR(Olw, O(Type,size),Ro2, Ro2);		// Ro2 = size
	delay();

	RRR(Omul, Ro3,Ro2,Rzero);			// Ro2 = i*size
	RRR(Omflo, Rzero,Rzero,Ro2);
	JR(Ojr, Rlink);
	RRR(Oaddu, Ro1,Ro2,Ro2);			// Ro2 = i*size + data
}

static void
maccase(void)
{
	ulong *cp1, *cp2, *cp3;

/*
 * Ro1 = value (input arg), t
 * Ro2 = count, n
 * Ro3 = table pointer (input arg)
 * Ri  = n/2, n2
 * Rj  = pivot element t+n/2*3, l
 */

	IRR(Olw, 0,Ro3, Ro2);		// count
	IRR(Oaddui, 0,Ro3, Rlink);	// initial table pointer

	cp1 = code;			// loop:
	BRI(Oblez,Ro2, 0);		// n <= 0? goto out
	SRR(Osra, 1, Ro2, Ri);		// n2 = n>>1
	SRR(Osll, 1, Ri, Rj);
	RRR(Oaddu, Rj, Ri, Rj);
	SRR(Osll, 2, Rj, Rj);
	RRR(Oaddu, Ro3, Rj, Rj);	// l = t + n2*3;
	IRR(Olw, 4,Rj, Rpic);
	delay();
	RRR(Oslt, Rpic, Ro1, Rpic);
	cp2 = code;
	BRI(Obne, Rpic, 0);		// v < l[1]? goto low
	delay();

	IRR(Olw, 8,Rj, Rpic);
	delay();
	RRR(Oslt, Rpic, Ro1, Rpic);
	cp3 = code;
	BRI(Obeq, Rpic, 0);		// v >= l[2]? goto high
	delay();

	IRR(Olw, 12,Rj, Ro3);		// found
	delay();
	JR(Ojr, Ro3);
	delay();

	*cp2 |= (code - cp2) - 1;	// low:
	BRRI(Obeq, Rzero,Rzero, (cp1-code)-1);
	IRR(Oaddui, 0, Ri, Ro2);	// n = n2

	*cp3 |= (code - cp3) - 1;	// high:
	IRR(Oaddui, 12, Rj, Ro3);	// t = l+3;
	IRR(Oaddui, 1, Ri, Rpic);
	BRRI(Obeq, Rzero,Rzero, (cp1-code)-1);
	RRR(Osubu, Rpic, Ro2, Ro2);	// n -= n2 + 1

	*cp1 |= (code - cp1) - 1;	// out:
	IRR(Olw, 0,Rlink, Ro2);		// initial n
	delay();
	SRR(Osll, 1, Ro2, Ro3);
	RRR(Oaddu, Ro3, Ro2, Ro2);
	SRR(Osll, 2, Ro2, Ro2);
	RRR(Oaddu, Ro2, Rlink, Rlink);
	IRR(Olw, 4,Rlink, Ro3);		// (initital t)[n*3+1]
	delay();
	JR(Ojr, Ro3);
	delay();
}

static void
maclena(void)
{
	ulong *cp;

	ldc((ulong)H, Ro1);
	cp = code;
	BRRI(Obeq, Ri,Ro1, 0);
	delay();
	IRR(Olw, O(Array,len),Ri, Ro1);
	JR(Ojr, Rlink);
	delay();
	*cp |= (code - cp) - 1;
	JR(Ojr, Rlink);
	ldc(0, Ro1);
}

static	void
macmcal(void)
{
	ulong *cp1, *cp2;

	IRR(Olw, O(Modlink,prog),Ri, Ro2);
	IRR(Osw, O(Frame,lr),Ro1, Rlink);	// f->lr = return
	cp1 = code;
	BRRI(Obne, Ro2, Rzero, 0);		// CMPL ml->m->prog != 0
	IRR(Oaddui, 0,Ro1, Rfp);		// R.FP = f

	IRR(Osw, O(REG,st),Rreg, Rlink);
	ldc((ulong)rmcall, Rpic);
	IRR(Osw, O(REG,FP),Rreg, Ro1);
	IRR(Osw, O(REG,dt),Rreg, Rj);
	JR(Ojalr, Rpic);			// CALL	rmcall
	xchg();
	ldc((ulong)&R, Rreg);
	IRR(Olw, O(REG,st),Rreg, Rlink);
	IRR(Olw, O(REG,FP),Rreg, Rfp);
	IRR(Olw, O(REG,MP),Rreg, Rmp);
	JR(Ojr, Rlink);
	delay();

	*cp1 |= (code - cp1) - 1;
	IRR(Olw, O(Heap,ref)-sizeof(Heap),Ri, Ro2);
	IRR(Osw, O(REG,M),Rreg, Ri);
	IRR(Oaddui, 1,Ro2, Ro2);
	IRR(Olw, O(Modlink,MP),Ri, Rmp);
	IRR(Olw, O(Modlink,compiled),Ri, Ro1);
	IRR(Osw, O(Heap,ref)-sizeof(Heap),Ri, Ro2);
	cp2 = code;
	BRRI(Obeq, Ro1,Rzero, 0);
	IRR(Osw, O(REG,MP),Rreg, Rmp);

	JR(Ojr, Rj);
	delay();

	*cp2 |= (code - cp2) - 1;
	IRR(Osw, O(REG,FP),Rreg, Rfp);		// call to uncompiled code
	IRR(Olw, O(REG,xpc),Rreg, Ro1);
	JR(Ojr, Ro1);
	IRR(Osw, O(REG,PC),Rreg, Rj); 
}

static	void
macmfra(void)
{
	ldc((ulong)rmfram, Rpic);
	IRR(Osw, O(REG,st),Rreg, Rlink);
	IRR(Osw, O(REG,FP),Rreg, Rfp);
	IRR(Osw, O(REG,s),Rreg, Ri);
	IRR(Osw, O(REG,d),Rreg, Rj);
	JR(Ojalr, Rpic);			// CALL	rmfram
	xchg();
	ldc((ulong)&R, Rreg);
	IRR(Olw, O(REG,st),Rreg, Rlink);
	IRR(Olw, O(REG,FP),Rreg, Rfp);
	IRR(Olw, O(REG,MP),Rreg, Rmp);
	JR(Ojr, Rlink);
	delay();
}

static void
macfram(void)
{
	ulong *cp;

	/*
	 * Ri has t
	 */
	IRR(Olw, O(Type,initialize),Ri, Rj);
	IRR(Olw, O(Type,size),Ri, Ro3);		// MOVL $t->size, Ro3
	IRR(Olw, O(REG,SP),Rreg, Ro2);		// MOVL	R.SP, Ro2
	IRR(Olw, O(REG,TS),Rreg, Ro1);		// MOVL	R.TS, Ro1
	RRR(Oaddu,Ro3,Ro2, Ro2);		// ADDL $t->size, Ro2
	RRR(Osltu, Ro1,Ro2, Ro3);		// CMP Ro1,Ro2,Ro3
	cp = code;
	BRI(Obne,Ro3,0);			// BLT Ro3,**
	delay();

	IRR(Osw, O(REG,s),Rreg, Ri);		// MOVL	t, R.s
	IRR(Osw, O(REG,st),Rreg, Rlink);	// MOVL	Rlink, R.st
	ldc((ulong)extend, Rpic);
	JR(Ojalr, Rpic);			// CALL	extend
	IRR(Osw, O(REG,FP),Rreg, Rfp);		// MOVL	RFP, R.FP
	ldc((ulong)&R, Rreg);
	IRR(Olw, O(REG,st),Rreg, Rlink);	// reload registers
	IRR(Olw, O(REG,FP),Rreg, Rfp);
	IRR(Olw, O(REG,MP),Rreg, Rmp);
	IRR(Olw, O(REG,s),Rreg, Ro1);		// return arg
	JR(Ojr, Rlink);
	delay();

	*cp |= (code - cp) - 1;
	IRR(Olw, O(REG,SP),Rreg, Ro1);
	IRR(Osw, O(REG,SP),Rreg, Ro2);
	IRR(Osw, O(Frame,mr),Ro1, Rzero);
	JR(Ojr, Rj);				// return from tinit to main program
	IRR(Osw, O(Frame,t),Ro1, Ri);
}

static void
macmovm(void)
{
	ulong *cp1, *cp2;

	/*
	 * from = Ro1
	 * to = Ro3
	 * count = Ro2
	 */

	cp1 = code;
	BRRI(Obeq, Ro2, Rzero, 0);
	delay();

	cp2 = code;
	IRR(Olbu, 0,Ro1, Ri);
	IRR(Oaddui, -1,Ro2, Ro2);
	IRR(Osb, 0,Ro3, Ri);
	IRR(Oaddui, 1,Ro1, Ro1);
	BRRI(Obne, Ro2, Rzero, (cp2-code)-1);
	IRR(Oaddui, 1,Ro3, Ro3);

	*cp1 |= (code - cp1) - 1;
	JR(Ojr, Rlink);
	delay();
}

static void
maccolr(void)
{
	ulong *cp;

	IRR(Olw, 0,Ri, Ri);
	IRR(Olw, O(Heap,color)-sizeof(Heap),Ro1, Ro3);

	IRR(Olw, O(Heap,ref)-sizeof(Heap),Ro1, Ro2);

	cp = code;
	BRRI(Obeq, Ri, Ro3, 0);
	IRR(Oaddui, 1,Ro2, Ro2);

	ldc(propagator, Ro3);
	IRR(Osw, O(Heap,color)-sizeof(Heap),Ro1, Ro3);
	ldc((ulong)&nprop, Ro3);
	IRR(Osw, 0,Ro3, Ro1);

	*cp |= (code - cp) - 1;
	JR(Ojr, Rlink);
	IRR(Osw, O(Heap,ref)-sizeof(Heap),Ro1, Ro2);
}

static void
macend(void)
{
}

void
comd(Type *t)
{
	int i, j, m, c;

	IRR(Osw, O(REG,dt),Rreg, Rlink);
	for(i = 0; i < t->np; i++) {
		c = t->map[i];
		j = i<<5;
		for(m = 0x80; m != 0; m >>= 1) {
			if(c & m) {
				J(Ojal, base+macro[MacFRP]);
				IRR(Olw, j,Rfp, Ri);
			}
			j += sizeof(WORD*);
		}
	}
	IRR(Olw, O(REG,dt),Rreg, Rlink);
	delay();
	JR(Ojr, Rlink);
	delay();
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
				IRR(Osw, j,Ro1, Ri);
			j += sizeof(WORD*);
		}
	}
	JR(Ojr, Rlink);
	xchg();
}

void
typecom(Type *t)
{
	int n;
	ulong *tmp, *start;

	if(t == nil || t->initialize != 0)
		return;

	tmp = mallocz(4096, 0);
	if(tmp == nil)
		return;
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
	ulong *s, tmp[512];

	patch = mallocz(size*sizeof(*patch), 0);
	tinit = malloc(m->ntype*sizeof(*tinit));
	base = 0;

	if(!comvec) {
		i = 10;		/* length of comvec */
		code = malloc(i*sizeof(*code));
		s = code;
		preamble();
		if(code >= (ulong*)(s + i))
			urk("preamble");
		comvec = (void*)s;
		segflush(s, i*sizeof(*s));
		if(cflag > 1) {
			print("comvec\n");
			while(s < code)
				das(s++);
		}/**/
	}

	mod = m;
	n = 0;
	regdelay = 0;
	pass = 0;
	nlit = 0;

	for(i = 0; i < size; i++) {
		code = tmp;
		comp(&m->prog[i]);
		if(code >= &tmp[nelem(tmp)]) {
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

	base = malloc((n+nlit)*sizeof(*base));
	if(cflag > 1)
		print("dis=%5d %5d mips=%5d asm=%.8p lit=%d: %s\n",
			size, size*sizeof(Inst), n, base, nlit, m->name);

	pass++;
	code = base;
	litpool = base+n;
	n = 0;
	nlit = 0;
	regdelay = 0;

	for(i = 0; i < size; i++) {
		s = code;
		comp(&m->prog[i]);
		if(patch[i] != n) {
			print("%3d %D\n", i, &m->prog[i]);
			urk(exCphase);
		}
		n += code - s;
		if(cflag > 1) {
			print("%3d %D\n", i, &m->prog[i]);
			while(s < code)
				das(s++);
		}/**/
	}

	for(i=0; macinit[i].f; i++) {
		if(macro[macinit[i].o] != n) {
			print("macinit %d\n", macinit[i].o);
			urk(exCphase);
		}
		s = code;
		(*macinit[i].f)();
		n += code - s;
		if(cflag > 1) {
			print("macinit %d\n", macinit[i].o);
			while(s < code)
				das(s++);
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
	free(m->prog);
	m->prog = (Inst*)base;
	m->compiled = 1;
	segflush(base, n*sizeof(*base));
	return 1;
}
