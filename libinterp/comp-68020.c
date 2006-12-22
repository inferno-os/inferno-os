#include "lib9.h"
#include "isa.h"
#include "interp.h"
#include "raise.h"

enum
{
	RAX	= 0,
	RCX	= 1,			/* Be careful with RCX, smashed in bra() */
	RTA	= 2,
	RTMP	= 3,
	RFP	= 4,
	RMP	= 5,
	R7	= 7,

	DTMP	= 0,
	DTMP1	= 1,
	DTMP2	= 2,
	DTMP3	= 3,

	Oadd	= 0xD000,
	OaddaR	= 0xD1E8,		/* ADDA (d16,Rr), Rr */
	Oaddi	= 0x0600,
	OaddRD	= 0xD0A8,
	OaslbD	= 0xE120,
	OaslwD	= 0xE1A0,
	OasrbD	= 0xE020,
	OasrwD	= 0xE0A0,
	Oand	= 0xC000,
	Oandi	= 0x0200,
	Obra	= 0x6000,
	Obsr	= 0x6100,
	OclrwD	= 0x4280,
	OcmpiwR	= 0x0CA8,		/* cmpi.l offset(Rrm), imm.long */
	OcmpwR	= 0xB1E8,		/* cmpa $offset(Rrm), Rr */
	OcmpbD	= 0xB028,		/* cmp.b $offset(Rrm), Dr */
	OcmpwD	= 0xB0A8,		/* cmp.l $offset(Rx), Dr */
	OcmpwDD	= 0xB080,		/* cmp.l Dr, Dx */
	Odbeq	= 0x57C8,
	OdecrwRind = 0x53A8,		/* SUBQ.L $0x1, offset(Rr) */
	Odivs	= 0x81C0,
	Oeor	= 0xB000,
	Oeori	= 0x0A00,
	OexgRR	= 0xC148,		/* exg Rx, Ry */
	Oextw	= 0x4880,		/* EXT.W Dx extend byte to 16-bit */
	Oextbw	= 0x49C0,		/* EXTB.L Dx extend byte to 32-bit */
	OincrwR	= 0x5288,		/* ADDQ.L $0x1, Rr */
	OincrwRind = 0x52A8,		/* ADDQ.L $0x1, offset(Rr) */
	Ojhi	= 0x6200,		/* BHI */
	Ojhs	= 0x6400,		/* BCC(HS) */
	Ojlo	= 0x6500,		/* BCS(LO) */
	Ojls	= 0x6300,		/* BLS */
	Ojeq	= 0x6700,		/* BEQ */
	Ojge	= 0x6C00,		/* BGE */
	Ojgt	= 0x6E00,		/* BGT */
	Ojle	= 0x6F00,		/* BLE */
	Ojlt	= 0x6D00,		/* BLT */
	Ojne	= 0x6600,		/* BNE */
	OjmpRind= 0x4ED0,		/* jmp (Rn) */
	OjmpRindoffs= 0x4EE8,		/* jmp $offs(Rn) */
	OjsrRind= 0x4E90,
	OldbD	= 0x1028,		/* $offset(Rrm).b -> Dr */
	OldbR	= 0x1058,		/* $offset(Rrm).b -> Rr */
	OldwD	= 0x2028,		/* $offset(Rrm) -> Dr */
	OldwR	= 0x2068,		/* $offset(Rrm) -> Rr */
	OleaR	= 0x41E8,		/* addr($offset(Rrm) -> Rr */
	OlslD	= 0xE388,
	Olsl2D	= 0xE588,
	OlsrD	= 0xE288,
	OlslbD	= 0xE128,
	OlslwD	= 0xE1A8,
	OlsrbD	= 0xE028,
	OlsrwD	= 0xE0A8,
	OmovelitwR= 0x207C,		/* move $xx, Rr */
	OmovelitwD= 0x203C,		/* move $xx, Dr */
	Omoveal	= 0x2040,
	OmovwR	= 0x217C,		/* imm.long -> $offset(Rrm) */
	OmovwRR	= 0x2048,		/* movea.l Rr, Rx */
	OmovwRD	= 0x2008,		/* move.l Rr, Dx */
	Omuls	= 0xC1C0,
	OnegwD	= 0x4480,
	Oor	= 0x8000,
	Oori	= 0x0000,
	OpopwR	= 0x205F,		/* MOVEA.L (A7)+, Rr */
	OpushwR	= 0x2F08,		/* MOVE.L Rr, -(A7) */
	Opushil	= 0x2F3C,		/* MOVE.L imm., -(A7) */
	OroxlD	= 0xE390,
	OroxrD	= 0xE290,
	Orts	= 0x4E75,
	OstbD	= 0x1140,		/* Dr.b -> $offset(Rrm) !!!!! ostbR does NOT exist */
	OstwD	= 0x2140,		/* Dr -> $offset(Rrm) */
	OstwR	= 0x2148,		/* Rr -> $offset(Rrm) */
	Osub	= 0x9000,
	Osubi	= 0x0400,
	OaddqwR	= 0x5088,
	Oswap	= 0x4840,
	OtstbD	= 0x4A00,		/* tst.b Dr */
	OtstwR	= 0x4AA8,		/* tst.l $offset(Rx) */
	Oill	= 0x4afc,		/* illegal instruction trap */
	Onop	= 0x4E71,
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

static	uchar*	code;
static	uchar*	base;
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

extern void _mull(void);
extern void _divsl(void);

#define T(r)	*((void**)(R.r))

struct
{
	int	idx;
	void	(*gen)(void);
} mactab[] =
{
	MacFRP,		macfrp,		/* decrement and free pointer */
	MacRET,		macret,		/* return instruction */
	MacCASE,	maccase,	/* case instruction */
	MacCOLR,	maccolr,	/* increment and color pointer */
	MacMCAL,	macmcal,	/* mcall bottom half */
	MacFRAM,	macfram,	/* frame instruction */
	MacMFRA,	macmfra,	/* punt mframe because t->initialize==0 */
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

static int
bc(int o)
{
	if(o < 127 && o > -128)
		return 1;
	return 0;
}

static int
wc(int o)
{
	if(o < 65535 && o > -65536)
		return 1;
	return 0;
}

static void
urk(void)
{
	error(exCompile);
}

static void
gen2(uchar o1, uchar o2)
{
	code[0] = o1;
	code[1] = o2;
	code += 2;
}

static void
genw(ulong o)
{
	code[0] = (o>>8)&0xFF;
	code[1] = o&0xFF;
	code += 2;
}

static void
genl(ulong o)
{
	*(ulong*)code = o;
	code += 4;
}

static void
modrm(int inst, ulong disp, int rm, int r)
{
	switch (inst) {
		case OstwD:
		case OstwR:
		case OstbD:
			if (!disp) {
				inst&=0xfe3f;
				inst|=0x0080;
			}
			genw(inst | (rm<<9) | r);
			if (disp)
				genw(disp);
			break;
		case Oadd|0x28|(0x6<<6):
		case Oadd|0x28|(0x4<<6):
		case Osub|0x28|(0x6<<6):
		case Osub|0x28|(0x4<<6):
		case Oor|0x28|(0x6<<6):
		case Oor|0x28|(0x4<<6):
		case Oand|0x28|(0x6<<6):
		case Oand|0x28|(0x4<<6):
		case Oeor|0x28|(0x6<<6):
		case Oeor|0x28|(0x4<<6):
		case Oaddi|0x28|(0x2<<6):
		case Oori|0x28|(0x2<<6):
		case Oandi|0x28|(0x2<<6):
		case Oeori|0x28|(0x2<<6):
		case Osubi|0x28|(0x2<<6):
		case Oaddi|0x28:
		case Oori|0x28:
		case Oandi|0x28:
		case Oeori|0x28:
		case Osubi|0x28:
		case OldbD:
		case OldwD:
		case OldwR:
		case OldbR:
		case OleaR:
		case OaddRD:
		case OcmpwR:
		case OcmpwD:
		case OcmpbD:
		case OdecrwRind:
		case OincrwRind:
		case OtstwR:
			if (!disp) {
				inst&=0xffc7;
				inst|=0x0010;
			}
			genw(inst | (r<<9) | rm);	
			if (disp)
				genw(disp);
			break;
		default:
			print("modrm: urk on opcode 0x%ux\n",inst);
			urk();
	}
}

static void
conR(ulong o, int r)
{
	if(o == 0) {
		genw(0x91C8|(r<<9)|r); /* SUBA Rr, Rr */
		return;
	}
	genw(Omoveal|(r<<9)|0x7C); /* MOVEA.L $o,Rr */
	genl(o);
}

static void
conD(ulong o, int r)
{
	if(o == 0) {
		genw(OclrwD|r); /* CLR.L Dr */
		return;
	}
	genw(OmovelitwD|(r<<9)); /* MOVEA.L $o,Dr */
	genl(o);
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
		modrm(mi, i->s.ind, RFP, r);
		return;
	case SRC(AMP):
		modrm(mi, i->s.ind, RMP, r);
		return;
	case SRC(AIMM):
		conR(i->s.imm, r);
		return;
	case SRC(AIND|AFP):
		ir = RFP;
		break;
	case SRC(AIND|AMP):
		ir = RMP;
		break;
	}
	rta = RTA;
	if(mi == OleaR)
		rta = r;
	modrm(OldwR, i->s.i.f, ir, rta);
	modrm(mi, i->s.i.s, rta, r);
}

static void
opwldD(Inst *i, int mi, int r)
{
	int ir, rta;
	switch(UXSRC(i->add)) {
	default:
		print("%D\n", i);
		urk();
	case SRC(AFP):
		modrm(mi, i->s.ind, RFP, r);
		return;
	case SRC(AMP):
		modrm(mi, i->s.ind, RMP, r);
		return;
	case SRC(AIMM):
		conD(i->s.imm, r);
		return;
	case SRC(AIND|AFP):
		ir = RFP;
		break;
	case SRC(AIND|AMP):
		ir = RMP;
		break;
	}
	rta = RTA;
	modrm(OldwR, i->s.i.f, ir, rta);
	modrm(mi, i->s.i.s, rta, r);
}

static int
opwst(Inst *i, int mi, int r)
{
	int ir, rta;

	switch(UXDST(i->add)) {
	default:
		print("%D\n", i);
		urk();
	case DST(AIMM):
		conR(i->d.imm, r);
		return 0;
	case DST(AFP):
		modrm(mi, i->d.ind, RFP, r);
		return i->d.ind;
	case DST(AMP):
		modrm(mi, i->d.ind, RMP, r);
		return i->d.ind;
	case DST(AIND|AFP):
		ir = RFP;
		break;
	case DST(AIND|AMP):
		ir = RMP;
		break;
	}
	rta = RTA;
	if(mi == OleaR)
		rta = r;
	modrm(OldwR, i->d.i.f, ir, rta);
	modrm(mi, i->d.i.s, rta, r);
	return i->d.i.s;
}

static void
opwstD(Inst *i, int mi, int r)
{
	int ir, rta;

	switch(UXDST(i->add)) {
	default:
		print("%D\n", i);
		urk();
	case DST(AIMM):
		conD(i->d.imm, r);
		return;
	case DST(AFP):
		modrm(mi, i->d.ind, RFP, r);
		return;
	case DST(AMP):
		modrm(mi, i->d.ind, RMP, r);
		return;
	case DST(AIND|AFP):
		ir = RFP;
		break;
	case DST(AIND|AMP):
		ir = RMP;
		break;
	}
	rta = RTA;
	if(mi == OleaR)
		rta = r;
	modrm(OldwR, i->d.i.f, ir, rta);
	modrm(mi, i->d.i.s, rta, r);
}

static int
swapbraop(int b)
{
	switch(b) {
	case Ojge:
		return Ojlt;
	case Ojle:
		return Ojgt;
	case Ojgt:
		return Ojle;
	case Ojlt:
		return Ojge;
	case Ojhi:
		return Ojls;
	case Ojlo:
		return Ojhs;
	case Ojhs:
		return Ojlo;
	case Ojls:
		return Ojhi;
	case Ojeq:
		return Ojne;
	case Ojne:
		return Ojeq;
	}
	return b;
}

static void
bra(ulong dst, int op)
{
	ulong ddst;
	switch (op) {
		case Obsr:
			genw(OmovelitwR|(RCX<<9));
			genl(dst);
			genw(OjsrRind|RCX);
			break;
		case Obra:
dojmp:
			ddst=dst-((ulong)code+2);
			if (bc(ddst)) {
				genw(Obra|(uchar)ddst);
				genw(Onop);
				genw(Onop);
				genw(Onop);
			} else if (wc(ddst)) {
				genw(Obra);
				genw(ddst);
				genw(Onop);
				genw(Onop);
			} else {
				genw(OmovelitwR|(RCX<<9));
				genl(dst);
				genw(OjmpRind|RCX);
			}
			break;	
		case Ojhi:
		case Ojhs:
		case Ojlo:
		case Ojls:
		case Ojeq:
		case Ojge:
		case Ojgt:
		case Ojle:
		case Ojlt:
		case Ojne:
			genw(swapbraop(op)|0x8);
			goto dojmp;
		default:
			print("bra: urk op opcode 0x%ux\n",op);	
			urk();
			break;
	}		
}

static void
rbra(ulong dst, int op)
{
	dst += (ulong)base;
	bra(dst,op);
}

static void
literal(ulong imm, int roff)
{
	nlit++;
	genw(OmovelitwR|(RAX<<9));
	genl((ulong)litpool);
	modrm(OstwR, roff, RTMP, RAX);

	if(pass == 0)
		return;

	*litpool = imm;
	litpool++;	
}


static void
punt(Inst *i, int m, void (*fn)(void))
{
	ulong pc;
	conR((ulong)&R, RTMP);

	if(m & SRCOP) {
		if(UXSRC(i->add) == SRC(AIMM)) {
			literal(i->s.imm, O(REG, s));
		}
		else {
			opwld(i, OleaR, RAX);
			modrm(OstwR, O(REG, s), RTMP, RAX);
		}
	}

	if(m & DSTOP) {
		if(UXDST(i->add) == DST(AIMM)) {
			literal(i->d.imm, O(REG, d));
		} else {
			opwst(i, OleaR, RAX);
			modrm(OstwR, O(REG, d), RTMP, RAX);
		}
	}
	if(m & WRTPC) {
		genw(OmovwR|(RTMP<<9));
		pc = patch[i-mod->prog+1];
		genl((ulong)base + pc);
		genw(O(REG, PC));
	}
	if(m & DBRAN) {
		pc = patch[(Inst*)i->d.imm-mod->prog];

		literal((ulong)base+pc, O(REG, d));
	}

	switch(i->add&ARM) {
	case AXNON:
		if(m & THREOP) {
			modrm(OldwR, O(REG, d), RTMP, RAX);
			modrm(OstwR, O(REG, m), RTMP, RAX);
		}
		break;
	case AXIMM:
		literal((short)i->reg, O(REG, m));
		break;
	case AXINF:
		modrm(OleaR, i->reg, RFP, RAX);
		modrm(OstwR, O(REG, m), RTMP, RAX);
		break;
	case AXINM:
		modrm(OleaR, i->reg, RMP, RAX);
		modrm(OstwR, O(REG, m), RTMP, RAX);
		break;
	}
	modrm(OstwR, O(REG, FP), RTMP, RFP);

	bra((ulong)fn, Obsr);

	conR((ulong)&R, RTMP);
	if(m & TCHECK) {
		genw(Orts);
	}

	modrm(OldwR, O(REG, FP), RTMP, RFP);
	modrm(OldwR, O(REG, MP), RTMP, RMP);

	if(m & NEWPC) {
		modrm(OldwR, O(REG, PC), RTMP, RAX);
		genw(OjmpRind|RAX);
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
		conR((short)i->reg, r);
		return;
	case AXINF:
		ir = RFP;
		break;
	case AXINM:
		ir = RMP;
		break;
	}
	modrm(mi, i->reg, ir, r);
}

static void
midD(Inst *i, int mi, int r)
{
	int ir;
	switch(i->add&ARM) {
	default:
		opwstD(i, mi, r);
		return;
	case AXIMM:
		conD((short)i->reg, r);
		return;
	case AXINF:
		ir = RFP;
		break;
	case AXINM:
		ir = RMP;
		break;
	}
	modrm(mi, i->reg, ir, r);
}

static void
arithimms(Inst *i, int opcode, int opmode)
{	
	uchar off[3];
	int hasoff;
	if(i->add&ARM) {
		midD(i,(opmode)?OldwD:OldbD,DTMP);
		if (((opcode==Oaddi)||(opcode==Osubi))&&(i->s.imm>0)&&(i->s.imm<=8))
			genw(0x5000|((opcode==Osubi)?0x100:0)|(((opmode)?0x2:0x0)<<6)|(((uchar)i->s.imm)<<9)|DTMP);
		else {
			genw(opcode|DTMP|(((opmode)?0x2:0)<<6));
			if (opmode)
				genl(i->s.imm);
			else
				genw(i->s.imm);
		}
		opwstD(i, (opmode)?OstwD:OstbD, DTMP);	
		return;	
	}
	if (hasoff=opwst(i, opcode|0x28|(((opmode)?0x2:0)<<6), 0)) {
		code-=2;
		off[0]=code[0]; off[1]=code[1];
	}
	if (((opcode==Oaddi)||(opcode==Osubi))&&(i->s.imm>0)&&(i->s.imm<=8)) {
		code-=2; 
		off[2]=code[1];
		genw(0x5000|((opcode==Osubi)?0x100:0)|(((opmode)?0x2:0x0)<<6)|(((uchar)i->s.imm)<<9)|((hasoff)?0x28:0x10)|(off[2]&0x7));
	}
	else {
		if (opmode)
			genl(i->s.imm);
		else
			genw(i->s.imm);
	}
	if (hasoff) 
		gen2(off[0],off[1]);
}

static void
arith(Inst *i, int opcode, int opmode)
{	
	opwldD(i, (opmode)?OldwD:OldbD, DTMP1);
	if(i->add&ARM) {
		midD(i,(opmode)?OldwD:OldbD,DTMP);
		genw(opcode|(DTMP<<9)|DTMP1|(((opmode)?0x2:0)<<6));
		opwstD(i, (opmode)?OstwD:OstbD, DTMP);
		return;	
	}
	opwst(i, opcode|0x28|(((opmode)?0x6:0x4)<<6), DTMP1);
}

static void
oldarithsub(Inst *i, int opmode)
{
	opwldD(i, (opmode)?OldwD:OldbD, DTMP1);
	if(i->add&ARM)
		midD(i,(opmode)?OldwD:OldbD,DTMP);
	else
		opwstD(i, (opmode)?OldwD:OldbD, DTMP);
	genw(Osub|(DTMP<<9)|DTMP1|(((opmode)?0x2:0)<<6));
	opwstD(i, (opmode)?OstwD:OstbD, DTMP);	
}

static void
shift(Inst *i, int ld, int st, int op)
{
	midD(i, ld, DTMP);
	opwldD(i, OldwD, DTMP1);
	genw(op|(DTMP1<<9)|DTMP);
	opwstD(i, st, DTMP);
}

static void
cmpl(int r, ulong v)
{
	genw(0xB1FC|(r<<9));
	genl(v);
}

static int
swapforcbra(int jmp) {
	switch(jmp) {
		case Ojge:
			return Ojle;
		case Ojle:
			return Ojge;
		case Ojgt:
			return Ojlt;
		case Ojlt:
			return Ojgt;
		case Ojhi:
			return Ojlo;
		case Ojlo:
			return Ojhi;
		case Ojhs:
			return Ojls;
		case Ojls:
			return Ojhs;
		default:
			return jmp;
	}

}
static void
cbra(Inst *i, int jmp)
{
	midD(i, OldwD, DTMP);
	if (UXSRC(i->add)==SRC(AIMM)) {
		genw(0xB0BC|DTMP);
		genl(i->s.imm);
	}
	else
		opwldD(i,OcmpwD,DTMP);
	rbra(patch[i->d.ins-mod->prog], swapforcbra(jmp));
}

static void
cbral(Inst *i, int jmsw, int jlsw, int mode)
{
	ulong dst;
	uchar *label;
	opwld(i, OleaR, RTMP);
	mid(i, OleaR, RTA);
	modrm(OldwR, 4, RTMP, RAX);
	modrm(OcmpwR, 4, RTA, RAX);
	label = 0;
	dst = patch[i->d.ins-mod->prog];
	switch(mode) {
	case ANDAND:
		genw(jmsw);
		label = code-1;
		break;
	case OROR:
		rbra(dst, jmsw);
		break;
	case EQAND:
		rbra(dst, jmsw);
		genw(Ojne);
		label = code-1;
		break;
	}
	modrm(OldwR, 0, RTMP, RAX);
	modrm(OcmpwR, 0, RTA, RAX);
	rbra(dst, jlsw);
	if(label != nil)
		*label = code-label-1;
}

static void
cbrab(Inst *i, int jmp)
{
	if(UXSRC(i->add) == SRC(AIMM))
		urk();

	midD(i, OldbD, DTMP);
	opwldD(i,OcmpbD,DTMP);
	rbra(patch[i->d.ins-mod->prog], swapforcbra(jmp));
}

static void
comcase(Inst *i, int w)
{
	int l;
	WORD *t, *e;
	
	USED (w);

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
		t[2] = (ulong)base + patch[t[2]];
		t += 3;
	}
	t[0] = (ulong)base + patch[t[0]];
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
	int o;
	uchar *punt, *mlnil;

	opwld(i, OldwR, RAX);
	cmpl(RAX, (ulong)H);
	genw(Ojeq);
	mlnil = code - 1;
	o = OA(Modlink, links)+i->reg*sizeof(Modl)+O(Modl, frame);
	modrm(OldwR, o, RAX, RTA);
	modrm(OtstwR,O(Type, initialize),RTA,0);
	genw(Ojne);
	punt = code - 1;
	genw(OexgRR|RAX|(RTA<<9));
	opwst(i, OleaR, RTA);
	*mlnil = code-mlnil-1;
	rbra(macro[MacMFRA], Obsr);
	rbra(patch[i-mod->prog+1], Obra);

	*punt = code-punt-1;
	rbra(macro[MacFRAM], Obsr);
	opwst(i, OstwR, RAX);
}

static void
commcall(Inst *i)
{
	conR((ulong)&R, RTMP);			// MOVL	$R, RTMP
	opwld(i, OldwR, RTA);
	genw(OmovwR|(RTA<<9));			// MOVL $.+1, lr(RTA)	f->lr = R.PC
	genl((ulong)base+patch[i-mod->prog+1]);
	genw(O(Frame, lr));	
	modrm(OstwR, O(Frame, fp), RTA, RFP); 	// MOVL RFP, fp(RTA)	f->fp = R.FP
	modrm(OldwD, O(REG, M), RTMP, DTMP);	// MOVL R.M, DTMP
	modrm(OstwD, O(Frame, mr), RTA, DTMP);	// MOVL RTA, mr(RTA) 	f->mr = R.M
	opwst(i, OldwR, RAX);			// MOVL ml, RAX
	modrm(OldwD, O(Modlink, m), RAX, DTMP);	// MOVL ml->m, DTMP
	modrm(OldwR, OA(Modlink, links)+i->reg*sizeof(Modl)+O(Modl, u.pc), RAX, RAX);
	rbra(macro[MacMCAL], Obsr);
}

static void
laritha(Inst *i, int opc)
{
	if((i->add&ARM) != AXNON) {
		mid(i, OleaR, RTMP);
		opwst(i, OleaR, RTA);
		genw(0x20D8|(RTA<<9)|RTMP);	// MOVL (RTMP)+, (RTA)+
		genw(0x20D8|(RTA<<9)|RTMP);	// MOVL (RTMP)+, (RTA)+
		}
	else {
		mid(i, OleaR, RTA);
		genw(0x5088|RTA);		// ADDQ.l #8, RTA
		}

	opwld(i, OleaR, RTMP);		
	genw(0x5088|RTMP);			// ADDQ.l #8, RTMP

	genw(0x44FC);				// MOVE imm16, CCR
	genw(0);
	genw(opc|RTMP|(RTA<<9));		// ADDX (-RTMP), (-RTA)
	genw(opc|RTMP|(RTA<<9));		// ADDX (-RTMP), (-RTA)
}

static void
larith(Inst *i, int op)
{
	if((i->add&ARM) != AXNON) {
		mid(i, OleaR, RTMP);
		opwst(i, OleaR, RTA);
		genw(0x20D8|RTMP|(RTA<<9));	// MOVL (RTMP)+, (RTA)+
		genw(0x2090|RTMP|(RTA<<9));	// MOVL (RTMP), (RTA)
		genw(0x5988|RTA);		// SUBQ.l #4, RTA
		}
	else
		mid(i, OleaR, RTA);


	opwld(i, OleaR, RTMP);
	genw(0x2018|RTMP|(DTMP<<9));		// MOVL (RTMP+), DTMP
	genw(op|RTA|(DTMP<<9));			// ORL DTMP, (RTA+)
	genw(0x2010|(DTMP<<9)|RTMP);		// MOVL (RTMP) DTMP
	genw((op&0xFFF7)|RTA|(DTMP<<9));	// ORL DTMP, (RTA)
}

static void
shll(Inst *i)
{
	uchar *label;

	opwldD(i, OldwD, DTMP);		// The number of shifts -> DTMP
	mid(i, OleaR, RTA);		// LEA source, RTA
	genw(0x2018|(DTMP1<<9)|RTA);	// move (RTA+), DTMP1 
	genw(0x2010|(DTMP2<<9)|RTA);	// move (RTA), DTMP2

	genw(Obra);
	label=code-1;

	genw(OlslD|DTMP2);
	genw(OroxlD|DTMP1);
	*label=code-label-1;
	genw(Odbeq);
	genw(label-code+1);

	opwst(i, OleaR, RTA);
	genw(0x2080|(RTA<<9)|DTMP2);	// move DTMP2, (RTA)
	genw(0x2100|(RTA<<9)|DTMP1);	// move DTMP1, (-RTA)
}

static void
shrl(Inst *i)
{
	uchar *label;

	opwldD(i, OldwD, DTMP);		// The number of shifts -> DTMP
	mid(i, OleaR, RTA);		// LEA source, RTA
	genw(0x2018|(DTMP1<<9)|RTA);	// move (RTA+), DTMP1 
	genw(0x2010|(DTMP2<<9)|RTA);	// move (RTA), DTMP2

	genw(Obra);
	label=code-1;

	genw(OlsrD|DTMP2);
	genw(OroxrD|DTMP1);
	*label=code-label-1;
	genw(Odbeq);
	genw(label-code+1);

	opwst(i, OleaR, RTA);
	genw(0x2080|(RTA<<9)|DTMP2);	// move DTMP2, (RTA)
	genw(0x2100|(RTA<<9)|DTMP1);	// move DTMP1, (-RTA)
}

static int myic;

static
void
compdbg(void)
{
	print("%s:%lud@%.8lux\n", R.M->m->name, *(ulong*)R.m, *(ulong*)R.s);
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
	case ILOAD:
	case IMSPAWN:
	case ISLICEA:
	case ISLICELA:
	case ISLICEC:
		punt(i, SRCOP|DSTOP|THREOP, optab[i->op]);
		break;
	case INEWA:
	case INEW:
	case ICONSB:
	case ICONSW:
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
	case ICVTLC:
	case ICVTCL:
	case ICVTFC:
	case ICVTCF:
	case ICVTCA:
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
		genw(OclrwD| DTMP);
		opwldD(i, OldbD, DTMP);
		opwstD(i, OstwD, DTMP);
		break;
	case ICVTWB:
		opwldD(i, OldwD, DTMP);
		opwstD(i, OstbD, DTMP);
		break;
	case ICVTFW:
	case ICVTWF:
	case ICVTLF:
	case ICVTFL:
		punt(i, SRCOP|DSTOP, optab[i->op]);
		break;
	case IHEADM:
	case IMOVM:
		punt(i, SRCOP|DSTOP|THREOP, optab[i->op]);
		break;
	case IRET:
		rbra(macro[MacRET], Obra);
		break;
	case IFRAME:
		if(UXSRC(i->add) != SRC(AIMM)) {
			punt(i, SRCOP|DSTOP, optab[i->op]);
			break;
		}
		tinit[i->s.imm] = 1;
		conR((ulong)mod->type[i->s.imm], RTA);
		rbra(macro[MacFRAM], Obsr);
		opwst(i, OstwR, RAX);
		break;
	case ILEA:
		if(UXSRC(i->add) == SRC(AIMM)) {
			genw(Obra|4);
			genl(i->s.imm);
			conR((ulong)(code-4), RAX);
		}
		else
			opwld(i, OleaR, RAX);
		opwst(i, OstwR, RAX);
		break;
	case IHEADW:
		opwld(i, OldwR, RAX);
		modrm(OldwR, OA(List, data), RAX, RAX);
		opwst(i, OstwR, RAX);
		break;
	case IHEADF:
		punt(i, SRCOP|DSTOP, optab[i->op]);
		break;
	case IHEADB:
		opwld(i, OldwR, RAX);
		modrm(OldbD, OA(List, data), RAX, DTMP);
		opwstD(i, OstbD, DTMP);
		break;
	case ITAIL:
		opwld(i, OldwR, RAX);
		modrm(OldwR, O(List, tail), RAX, RTMP);
		goto movp;
	case IMOVP:
	case IHEADP:
		opwld(i, OldwR, RTMP);
		if(i->op == IHEADP)
			modrm(OldwR, OA(List, data), RTMP, RTMP);
	movp:
		{uchar *label;	
			cmpl(RTMP, (ulong)H);
			genw(Ojeq);
			label=code-1;
			rbra(macro[MacCOLR], Obsr);
			*label=code-label-1;
			opwst(i, OldwR, RAX);
			opwst(i, OstwR, RTMP);
			rbra(macro[MacFRP], Obsr);
		}
		break;
	case ILENA:
		opwld(i, OldwR, RTMP);
		conR(0, RAX);
		cmpl(RTMP, (ulong)H);
		genw(Ojeq|0x2);
		modrm(OldwR, O(Array, len), RTMP, RAX);
		opwst(i, OstwR, RAX);
		break;
	case ILENC:
		{uchar *label;
			opwld(i, OldwR, RTMP);
			conD(0, DTMP);
			cmpl(RTMP, (ulong)H);
			genw(Ojeq);
			label=code-1;
			modrm(OldwD, O(String, len), RTMP, DTMP);
			genw(0x4A80|RAX);				// TSTL	 DTMP
			genw(Ojge|0x02);
			genw(OnegwD|DTMP);
			*label=code-label-1;
			opwstD(i, OstwD, DTMP);
		}
		break;
	case ILENL:
		{uchar *label,*l2;
			conR(0, RAX);
			opwld(i, OldwR, RTMP);
			l2=code-1;
			cmpl(RTMP, (ulong)H);
			genw(Ojeq);
			label=code-1;
			modrm(OldwR, O(List, tail), RTMP, RTMP);
			genw(OincrwR|RAX);
			genw(Obra|(uchar)(l2-code-1));
			*label=code-label-1;
			opwst(i, OstwR, RAX);
		}
		break;
	case IBEQF:
	case IBNEF:
	case IBLEF:
	case IBLTF:
	case IBGEF:
	case IBGTF:
		punt(i, SRCOP|DBRAN|NEWPC|WRTPC, optab[i->op]);
		break;
	case IBEQW:
		cbra(i, Ojeq);
		break;
	case IBLEW:
		cbra(i, Ojle);
		break;
	case IBNEW:
		cbra(i, Ojne);
		break;
	case IBGTW:
		cbra(i, Ojgt);
		break;
	case IBLTW:
		cbra(i, Ojlt);
		break;
	case IBGEW:
		cbra(i, Ojge);
		break;
	case IBEQB:
		cbrab(i, Ojeq);
		break;
	case IBLEB:
		cbrab(i, Ojls);
		break;
	case IBNEB:
		cbrab(i, Ojne);
		break;
	case IBGTB:
		cbrab(i, Ojhi);
		break;
	case IBLTB:
		cbrab(i, Ojlo);
		break;
	case IBGEB:
		cbrab(i, Ojhs);
		break;
	case ISUBW:
		if (UXSRC(i->add)==SRC(AIMM)) 
			arithimms(i,Osubi,1);
		else
			arith(i, Osub, 1);
		break;
	case ISUBB:
		if (UXSRC(i->add)==SRC(AIMM)) 
			arithimms(i,Osubi,1);
		else
			arith(i, Osub, 0);
		break;
	case ISUBF:
		punt(i, SRCOP|DSTOP|THREOP, optab[i->op]);
		break;
	case IADDW:
		if (UXSRC(i->add)==SRC(AIMM)) 
			arithimms(i,Oaddi,1);
		else
			arith(i, Oadd, 1);
		break;
	case IADDB:
		if (UXSRC(i->add)==SRC(AIMM)) 
			arithimms(i,Oaddi,0);
		else
			arith(i, Oadd, 0);
		break;
	case IADDF:
		punt(i, SRCOP|DSTOP|THREOP, optab[i->op]);
		break;
	case IORW:
		if (UXSRC(i->add)==SRC(AIMM)) 
			arithimms(i,Oori,1);
		else
			arith(i, Oor, 1);
		break;
	case IORB:
		if (UXSRC(i->add)==SRC(AIMM)) 
			arithimms(i,Oori,0);
		else
			arith(i, Oor, 0);
		break;
	case IANDW:
		arith(i, Oand, 1);
		break;
	case IANDB:
		arith(i, Oand, 0);
		break;
	case IXORW:
		if (UXSRC(i->add)==SRC(AIMM)) 
			arithimms(i,Oeori,1);
		else
			arith(i, Oeor, 1);
		break;
	case IXORB:
		if (UXSRC(i->add)==SRC(AIMM)) 
			arithimms(i,Oeori,0);
		else
			arith(i, Oeor, 0);
		break;
	case ISHLW:
		shift(i, OldwD, OstwD, OaslwD);
		break;
	case ISHLB:
		shift(i, OldbD, OstbD, OaslbD);
		break;
	case ISHRW:
		shift(i, OldwD, OstwD, OasrwD);
		break;
	case ISHRB:
		shift(i, OldbD, OstbD, OasrbD);
		break;
	case IMOVF:
	case INEGF:
		punt(i, SRCOP|DSTOP, optab[i->op]);
		break;
	case IMOVB:
		opwldD(i, OldbD, DTMP);
		opwstD(i, OstbD, DTMP);
		break;
	case IMOVW:
		opwldD(i, OldwD, DTMP);
		opwstD(i, OstwD, DTMP);
		break;
	case ICVTLW:
	case ICVTWL:
		punt(i, SRCOP|DSTOP, optab[i->op]);
		break;
	case ICALL:
		opwld(i, OldwR, RAX);
		genw(OmovwR|(RAX<<9));			// MOVL $.+1, lr(AX)
		genl((ulong)base+patch[i-mod->prog+1]);
		genw(O(Frame, lr));
		modrm(OstwR, O(Frame, fp), RAX, RFP); 	// MOVL RFP, fp(AX)
		genw(OmovwRR|(RFP<<9)|RAX);		// MOVL AX,RFP
		/* no break */
	case IJMP:
		rbra(patch[i->d.ins-mod->prog], Obra);
		break;
	case IGOTO:
		opwst(i, OleaR, RTMP);
		opwldD(i, OldwD, DTMP);
		genw(OlslwD|DTMP);
		genw(Oadd|(RTMP<<9)|(7<<6)|DTMP);
		genw(OjmpRind|RTMP);

		if(pass == 0)
			break;

		t = (WORD*)(mod->origmp+i->d.ind);
		e = t + t[-1];
		t[-1] = 0;
		while(t < e) {
			t[0] = (ulong)base + patch[t[0]];
			t++;
		}
		break;
	case IMULF:
	case IDIVF:
		punt(i, SRCOP|DSTOP|THREOP, optab[i->op]);
		break;
	case IMODW:
	case IDIVW:
	case IMULW:
		opwld(i, OldwR, RAX);
		genw(OpushwR|RAX);
		mid(i, OldwR, RAX);
		genw(OpushwR|RAX);
		switch(i->op) {
			case IMULW:
				bra((ulong)_mull,Obsr);
				genw(OaddqwR|(4<<9)|R7);
				genw(OpopwR|(RAX<<9));	
				break;
			case IMODW:
				bra((ulong)_divsl,Obsr);
				genw(OaddqwR|(4<<9)|R7);
				genw(OpopwR|(RAX<<9));	
				break;
			case IDIVW:
				bra((ulong)_divsl,Obsr);
				genw(OpopwR|(RAX<<9));	
				genw(OaddqwR|(4<<9)|R7);
				break;
		}
		opwst(i, OstwR, RAX);
		break;
	case IMODB:
	case IDIVB:
	case IMULB:
		midD(i, OldbD, DTMP);
		genw(Oextw|DTMP);
		opwldD(i, OldbD, DTMP2);
		if (i->op == IMULB)
		if(i->op == IMULB) {
			genw(Oextw|DTMP2);
			genw(Omuls|(DTMP<<9)|DTMP2);
		}
		else {
			genw(Oextbw|DTMP2);
			genw(Odivs|(DTMP<<9)|DTMP2);
		}
		if (i->op == IMODB)
			genw(Oswap|DTMP);
		opwstD(i, OstbD, DTMP);
		break;
	case IINDX:
		opwld(i, OldwR, RTMP);				// MOVW	xx(s), RTMP
		modrm(OldwR, O(Array, t), RTMP, RAX);		// MOVW	t(RTMP), AX
		modrm(OldwD, O(Type, size), RAX, DTMP1);	// MOVW size(AX), DTMP1
		opwstD(i, OldwD, DTMP2);			// MOVW indx, DTMP2
		genl(0x70204283);				// loop to MULW DTMP1, DTMP2, DTMP3
		genl(0xe2996402);
		genl(0xd682e38a);
		genl(0x57c8fff6);		

		modrm(OldwR, O(Array, data), RTMP, RTMP);
		genw(Oadd|(DTMP3<<9)|0x0088|RTMP);		// ADDL data(RTMP), DTMP3
		r = RMP;
		if((i->add&ARM) == AXINF)
			r = RFP;
		modrm(OstwD, i->reg, r, DTMP3);
		break;
	case IINDB:
		r = 0;
		goto idx;
	case IINDF:
		punt(i, SRCOP|THREOP|DSTOP, optab[i->op]);
		break;
	case IINDL:
		r = 3;
		goto idx;
	case IINDW:
		r = 2;
	idx:
		opwld(i, OldwR, RAX);
		opwstD(i, OldwD, DTMP);
		modrm(OldwR, O(Array, data), RAX, RTMP);

		if (r) 
			genw(0xE188|(r<<9)|DTMP);		
		genw(Oadd|(RTMP<<9)|(7<<6)|DTMP);		/* lea  (AX)(DTMP*r) */

		r = RMP;
		if((i->add&ARM) == AXINF)
			r = RFP;
		modrm(OstwR, i->reg, r, RTMP);
		break;
	case IINDC:
		{	uchar *label;
			opwld(i, OldwR, RAX);			// string
			midD(i, OldwD, DTMP);			// index
			modrm(OtstwR,O(String, len),RAX,0);
			modrm(OleaR, O(String, data), RAX, RAX); 
			genw(Ojge);				// Ascii only, jump 
			label=code-1;

			genw(OnegwD|DTMP);
			genw(Olsl2D|DTMP);			// << 2; index is times 4 bytes
			genw(Oadd|(RAX<<9)|0x01C0|DTMP);
			modrm(OldwD, 0, RAX, DTMP);
			genw(Obra|0x4);
			*label=code-label-1;
			genw(Oadd|(RAX<<9)|0x01C0|DTMP);
			modrm(OldbD, 0, RAX, DTMP);

			opwst(i, OstwD, DTMP);
		}
		break;
	case ICASE:
		comcase(i, 1);
		punt(i, SRCOP|DSTOP|NEWPC, optab[i->op]);
		break;
	case IMOVL:
		opwld(i, OleaR, RTA);
		opwst(i, OleaR, RTMP);
		genw(0x20D8|(RTMP<<9)|RTA);		// MOVE.l (RTA+), (RTMP+)
		genw(0x2090|(RTMP<<9)|RTA);		// MOVE.l (RTA), (RTMP)
		break;
	case IADDL:
		laritha(i, 0xD188);	// ADDX.l (-R0), (-R0)
		break;
	case ISUBL:
		laritha(i, 0x9188);	// SUBX.l (-R0), (-R0)
		break;
	case IORL:
		larith(i, 0x8198); 	// OR.l D0, (R0+)
		break;
	case IANDL:
		larith(i, 0xC198); 	// AND.l D0, (R0+)
		break;
	case IXORL:
		larith(i, 0xB198); 	// EOR.l D0, (R0+)
		break;
	case IBEQL:
		cbral(i, Ojne, Ojeq, ANDAND);
		break;
	case IBNEL:
		cbral(i, Ojne, Ojne, OROR);
		break;
	case IBLEL:
		cbral(i, Ojlt, Ojls, EQAND);
		break;
	case IBGTL:
		cbral(i, Ojgt, Ojhi, EQAND);
		break;
	case IBLTL:
		cbral(i, Ojlt, Ojlo, EQAND);
		break;
	case IBGEL:
		cbral(i, Ojgt, Ojhs, EQAND);
		break;
	case ISHLL:
		shll(i);
		break;
	case ISHRL:
		shrl(i);
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
	uchar *s;
	if(comvec)
		return;

	comvec = malloc(32);
	if(comvec == nil)
		error(exNomem);
	code = (uchar*)comvec;
	s = code;

	conR((ulong)&R, RAX);
	modrm(OldwR, O(REG, FP), RAX, RFP);
	modrm(OldwR, O(REG, MP), RAX, RMP);
	modrm(OldwR, O(REG, PC), RAX, RAX);
	genw(OjmpRind|RAX);
	
	segflush(comvec, 32);

	if(cflag > 2) {
		print("preamble\n");
		das(s, code-s);
	}
}

static void
maccase(void)
{
	/* Not used yet, done with punt() */
}

static void
macfrp(void)
{
	uchar *label,*s;
	s=code;
	cmpl(RAX, (ulong)H);			// CMPL AX, $H
	genw(Ojne|0x2);				// JNE	.+2
	genw(Orts);				// RET
	genw(OcmpiwR|(RAX<<9));
	genl(0x01);				// CMP	AX.ref, $1
	genw(O(Heap, ref)-sizeof(Heap));
	genw(Ojeq);				// JEQ
	label=code-1;
	modrm(OdecrwRind, O(Heap, ref)-sizeof(Heap), RAX, 0);	// DEC	AX.ref
	genw(Orts);				// RET
	*label=code-label-1;

	conR((ulong)&R, RTMP);			// MOV  $R, RTMP
	modrm(OstwR, O(REG, FP), RTMP, RFP);	// MOVL	RFP, R.FP
	modrm(OstwR, O(REG, s), RTMP, RAX);	// MOVL	RAX, R.s
						// CALL rdestroy
	bra((ulong)rdestroy, Obsr);
	conR((ulong)&R, RTMP);			// MOVL	$R, RTMP
	modrm(OldwR, O(REG, FP), RTMP, RFP);	// MOVL	R.FP, RFP
	modrm(OldwR, O(REG, MP), RTMP, RMP);	// MOVL R.MP, RMP
	genw(Orts);
	if(pass&&(cflag > 2)) {
		print("macfrp\n");
		das(s, code-s);
	}
}

static void
macret(void)
{
	Inst i;
	uchar *s;
	static ulong lpunt, lnomr, lfrmr,linterp;

	s = code;

	lpunt -= 2;
	lnomr -= 2;
	lfrmr -= 2;
	linterp -= 2;

	modrm(OldwR, O(Frame, t), RFP, RAX);		// MOVL  t(FP), RAX
	genw(OmovwRD|(DTMP<<9)|RAX);
	genw(0x4A80|DTMP);				// TSTL	 DTMP
	genw(Ojeq|(uchar)(lpunt-(code-s)));		// JEQ	 lpunt
	modrm(OldwR, O(Type, destroy), RAX, RAX);	// MOVL  destroy(RAX), RAX
	genw(OmovwRD|(DTMP<<9)|RAX);
	genw(0x4A80|DTMP);				// TSTL	 DTMP
	genw(Ojeq|(uchar)(lpunt-(code-s)));		// JEQ	 lpunt
	modrm(OtstwR, O(Frame, fp), RFP, 0);		// TSTL  fp(RFP)
	genw(Ojeq|(uchar)(lpunt-(code-s)));		// JEQ	 lpunt
	modrm(OtstwR, O(Frame, mr), RFP, 0);		// TSTL	 mr(RFP)
	genw(Ojeq|(uchar)(lnomr-(code-s)));		// JEQ	 lnomr
	conR((ulong)&R, RTMP);				// MOVL	 $R, RTMP
	modrm(OldwR, O(REG, M), RTMP, RTA);		// MOVL	 R.M, RTA
	modrm(OdecrwRind, O(Module, ref), RTA, 0);	// DECL  ref(RTA)
	genw(Ojne|(uchar)(lfrmr-(code-s)));		// JNE	 lfrmr
	modrm(OincrwRind, O(Module, ref), RTA, 0);	// INCL  ref(RTA)
	genw(Obra|(uchar)(lpunt-(code-s)));		// JMP	 lpunt
	lfrmr = code - s;
	modrm(OldwR, O(Frame, mr), RFP, RTA);		// MOVL	 mr(RFP), RTA
	modrm(OstwR, O(REG, M), RTMP, RTA);		// MOVL	 RTA, R.M
	modrm(OldwR, O(Modlink, MP), RTA, RMP);		// MOVL	 mp(RTA), RMP
	modrm(OstwR, O(REG, MP), RTMP, RMP);		// MOVL	 RMP, R.MP

	modrm(OtstwR, O(Modlink, compiled), RTA, 0);	// CMPL $0, M.compiled
	genw(Ojeq|(uchar)(linterp-(code-s)));
	
	lnomr = code - s;
	genw(OjsrRind|RAX);				// CALL* AX
	conR((ulong)&R, RTMP);				// MOVL	 $R, RTMP
	modrm(OstwR, O(REG, SP), RTMP, RFP);		// MOVL  RFP, R.SP
	modrm(OldwR, O(Frame, lr), RFP, RAX);		// MOVL  lr(RFP), RAX
	modrm(OldwR, O(Frame, fp), RFP, RFP);		// MOVL  fp(RFP), RFP
	modrm(OstwR, O(REG, FP), RTMP, RFP);		// MOVL  RFP, R.FP
	genw(OjmpRind|RAX);				// JMP*L AX

	linterp = code - s;
	genw(OjsrRind|RAX);				// CALL* AX
	conR((ulong)&R, RTMP);				// MOVL	 $R, RTMP
	modrm(OstwR, O(REG, SP), RTMP, RFP);		// MOVL  RFP, R.SP
	modrm(OldwR, O(Frame, lr), RFP, RAX);		// MOVL  lr(RFP), RAX
	modrm(OstwR, O(REG, PC), RTMP, RAX);		// MOVL  RAX, R.PC
	modrm(OldwR, O(Frame, fp), RFP, RFP);		// MOVL  fp(RFP), RFP
	modrm(OstwR, O(REG, FP), RTMP, RFP);		// MOVL  RFP, R.FP

	genw(Orts);
	lpunt = code - s;				// label:
	i.add = AXNON;
	punt(&i, NEWPC, optab[IRET]);
	if(pass&&(cflag > 2)) {
		print("macret\n");
		das(s, code-s);
	}
}

static void
maccolr(void)
{
	uchar *s;
	s=code;
	modrm(OincrwRind, O(Heap, ref)-sizeof(Heap), RTMP, 0);	// INCL	ref(RTMP)
	genw(0x2079|(RAX<<9));			// MOVL	(mutator), RAX
	genl((ulong)&mutator);	
	modrm(OcmpwR, O(Heap, color)-sizeof(Heap), RTMP, RAX);	// CMPL	color(RTMP), RAX
	genw(Ojne|0x02);			
	genw(Orts);				
	conR(propagator, RAX);			// MOVL $propagator,RAX
	modrm(OstwR, O(Heap, color)-sizeof(Heap), RTMP, RAX);	// MOVL	RAX, color(RTMP)
	genw(0x23C8|RAX);			// can be any !0 value
	genl((ulong)&nprop);			// MOVL	RAX, (nprop)
	genw(Orts);
	if(pass&&(cflag > 2)) {
		print("maccolr\n");
		das(s, code-s);
	}
}

static void
macmcal(void)
{
	uchar *s,*label,*interp;
	s=code;

	genw(0x2040|(RCX<<9)|DTMP);
	modrm(OtstwR,O(Module, prog),RCX,0);	// TSTL ml->m->prog

	genw(Ojne);				// JNE	patch
	label = code-1;
	modrm(OstwR, O(REG, FP), RTMP, RTA);
	modrm(OstwR, O(REG, dt), RTMP, RAX);
						// CALL rmcall
	bra((ulong)rmcall, Obsr);

	conR((ulong)&R, RTMP);			// MOVL	$R, RTMP
	modrm(OldwR, O(REG, FP), RTMP, RFP);
	modrm(OldwR, O(REG, MP), RTMP, RMP);
	genw(Orts);				// RET
	*label = code-label-1;			// patch:
	genw(0x2048|(RFP<<9)|RTA);		// MOVL RTA, RFP		R.FP = f
	modrm(OstwR, O(REG, M), RTMP, RCX);	// MOVL RCX, R.M
	modrm(OincrwRind, O(Module, ref), RCX, 0);	// INC.L R.M->ref
	modrm(OldwR, O(Modlink, MP), RCX, RMP);	// MOVL R.M->mp, RMP
	modrm(OstwR, O(REG, MP), RTMP, RMP);	// MOVL RCX, R.MP	R.MP = ml->m
	modrm(OtstwR, O(Module, compiled), RCX, 0);// CMPL $0, M.compiled

	genw(OpopwR|(RCX<<9));			// balance call
	genw(Ojeq);				// JEQ interp
	interp=code-1;
	genw(OjmpRind|RAX);			// JMP*L AX
	*interp= code-interp-1;
	modrm(OstwR, O(REG, FP), RTMP, RFP);	// MOVL FP, R.FP
	modrm(OstwR, O(REG, PC), RTMP, RAX);	// MOVL PC, R.PC
	genw(Orts);
	if(pass&&(cflag > 2)) {
		print("macmcal\n");
		das(s, code-s);
	}
}

static void
macfram(void)
{
	uchar *label,*s;
	s=code;
	conR((ulong)&R, RTMP);			// MOVL	$R, RTMP
	modrm(OldwD, O(REG, SP), RTMP, DTMP);	// MOVL	R.SP, DTMP
	modrm(OaddRD, O(Type, size), RTA, DTMP);// ADDL size(RTA), DTMP
	modrm(OcmpwD, O(REG, TS), RTMP, DTMP);	// CMPL	DTMP, R.TS
	genw(Ojlt);				// JLT	.+(patch)
	label = code-1;

	modrm(OstwR, O(REG, s), RTMP, RTA);
	modrm(OstwR, O(REG, FP), RTMP, RFP);	// MOVL	RFP, R.FP
						// BSR	extend
	bra((ulong)extend, Obsr);
	conR((ulong)&R, RTMP);
	modrm(OldwR, O(REG, FP), RTMP, RFP);	// MOVL	R.MP, RMP
	modrm(OldwR, O(REG, MP), RTMP, RMP);	// MOVL R.FP, RFP
	modrm(OldwR, O(REG, s), RTMP, RAX);	// MOVL	R.s, *R.d
	genw(Orts);				// RET
	*label = code-label-1;
	modrm(OldwR, O(REG, SP), RTMP, RAX);	// MOVL	R.SP, RAX
	modrm(OstwD, O(REG, SP), RTMP, DTMP);	// MOVL	DTMP, R.SP

	modrm(OstwR, O(Frame, t), RAX, RTA);	// MOVL	RTA, t(RAX) f->t = t
	genw(OmovwR|(RAX<<9));			// MOVL $0, mr(RAX) f->mr
	genl(0);
	genw(REGMOD*4);

	modrm(OldwR, O(Type, initialize), RTA, RTA);
	genw(OjmpRind|RTA);			// JMP*L RTA
	genw(Orts);				// RET
	if(pass&&(cflag > 2)) {
		print("macfram\n");
		das(s, code-s);
	}
}

static void
macmfra(void)
{
	uchar *s;
	s=code;
	conR((ulong)&R, RTMP);			// MOVL	$R, RTMP
	modrm(OstwR, O(REG, FP), RTMP, RFP);
	modrm(OstwR, O(REG, s), RTMP, RAX);	// Save type
	modrm(OstwR, O(REG, d), RTMP, RTA);	// Save destination
						// CALL rmfram
	bra((ulong)rmfram, Obsr);
	conR((ulong)&R, RTMP);			// MOVL	$R, RTMP
	modrm(OldwR, O(REG, FP), RTMP, RFP);
	modrm(OldwR, O(REG, MP), RTMP, RMP);
	genw(Orts);				// RET
	if(pass&&(cflag > 2)) {
		print("macmfra\n");
		das(s, code-s);
	}
}

void
comd(Type *t)
{
	int i, j, m, c;

	for(i = 0; i < t->np; i++) {
		c = t->map[i];
		j = i<<5;
		for(m = 0x80; m != 0; m >>= 1) {
			if(c & m) {
				modrm(OldwR, j, RFP, RAX);
				rbra(macro[MacFRP], Obsr);
			}
			j += sizeof(WORD*);
		}
	}
	genw(Orts);
}

void
comi(Type *t)
{
	int i, j, m, c;

	conD((ulong)H, DTMP);
	for(i = 0; i < t->np; i++) {
		c = t->map[i];
		j = i<<5;
		for(m = 0x80; m != 0; m >>= 1) {
			if(c & m)
				modrm(OstwD, j, RAX, DTMP);
			j += sizeof(WORD*);
		}
	}
	genw(Orts);
}

void
typecom(Type *t)
{
	int n;
	uchar *tmp;
	tmp=malloc(4096);

	if(tmp == nil)
		error(exNomem);
	if(t == nil || t->initialize != 0)
		return;

	code = tmp;
	comi(t);
	n = code - tmp;
	code = tmp;
	comd(t);
	n += code - tmp;

	code = mallocz(n, 0);
	if(code == nil)
		return;

	t->initialize = code;
	comi(t);
	t->destroy = code;
	comd(t);

	segflush(t->initialize, n);

	if(cflag > 1) {
		print("typ= %.8p %4d i %.8p d %.8p asm=%d\n",
			t, t->size, t->initialize, t->destroy, n);
		if (cflag > 2)
			das(t->destroy, code-(uchar*)t->destroy);
	}
	free(tmp);
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
	uchar *s, *tmp;
	base = nil;

	tmp=malloc(4096);
	patch = mallocz(size*sizeof(*patch), 0);
	tinit = malloc(m->ntype*sizeof(*tinit));
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
			print("tmp ovlo\n%3d %D\n", i, &m->prog[i]);
			urk();
		}
		patch[i] = n;
		n += code - tmp;
	}

	for(i = 0; i < nelem(mactab); i++) {
		code = tmp;
		(*mactab[i].gen)();
		macro[mactab[i].idx] = n;
		n += code - tmp;
	}

	nlit *= sizeof(ulong);
	base = mallocz(n + nlit, 0);
	if(base == nil)
		goto bad;

	if(cflag > 1)
		print("dis=%5d %5d 386=%5d asm=%.8p lit=%d: %s\n",
			size, size*sizeof(Inst), n, base, nlit, m->name);

	pass++;
	nlit = 0;
	litpool = (ulong*)(base+n);
	code = base;
	n = 0;
	for(i = 0; i < size; i++) {
		s = code;
		comp(&m->prog[i]);
		if(patch[i] != n) {
			print("phase error\n%3d %D\n", i, &m->prog[i]);
			urk();
		}
		n += code - s;
		if(cflag > 1) {
			print("%d: %D\n", i,&m->prog[i]);
			das(s, code-s);
		}
	}

	for(i = 0; i < nelem(mactab); i++) {
		if(macro[mactab[i].idx] != n) {
			print("phase error\nmactab %d\n", mactab[i].idx);
			urk();
		}
		s = code;
		(*mactab[i].gen)();
		n += code-s;
		if(cflag > 1) {
			print("mactab %d\n", mactab[i].idx);
			das(s, code-s);
		}
	}

	v = (ulong)base;
	for(l = m->ext; l->name; l++) {
//print("### link: %lux ",l->u.pc-m->prog);
		l->u.pc = (Inst*)(v+patch[l->u.pc-m->prog]);
//print("%lux\n",l->u.pc);
		typecom(l->frame);
	}
	if(ml != nil) {
		e = &ml->links[0];
		for(i = 0; i < ml->nlinks; i++) {
			e->u.pc = (Inst*)(v+patch[e->u.pc-m->prog]);
			typecom(e->frame);
			e++;
		}
	}
	for(i = 0; i < m->ntype; i++) {
		if(tinit[i] != 0)
			typecom(m->type[i]);
	}
	patchex(m, patch);
	m->entry = (Inst*)(v+patch[mod->entry-mod->prog]);
	free(patch);
	free(tinit);
	free(tmp);
	free(m->prog);
	m->prog = (Inst*)base;
	m->compiled = 1;
	segflush(base, n*sizeof(*base));
	return 1;
bad:
	free(tmp);
	free(patch);
	free(tinit);
	free(base);
	return 0;
}
