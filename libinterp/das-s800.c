#include "lib9.h"
#include "isa.h"
#include "interp.h"

/* s800 disassembler. */
/* does not handle stuff that won't be generated */

typedef struct instr Instr;

struct instr
{
	ulong	value;		/* bits 31-00 */
	uchar	op;		/* bits 31-26 */
	uchar	subop;		/* bits 11-05 */
	uchar	sysop;		/* bits 12-05 */
	uchar	reg0;		/* bits 25-21 */
	uchar	reg1;		/* bits 20-16 */
	uchar	reg2;		/* bits 4-0 */
	uchar	space;		/* bits 15-14 */
	uchar	indexed;	/* bit 13 */
	uchar	cond;		/* bits 15-13 */
	uchar	sr;		/* bits 13,15,14 */
	uchar	ftype;		/* bits 12-9 */
	uchar	simm;		/* bit 12 */
	uchar	store;		/* bit 9 */
	uchar	size;		/* bits 8-6 */
	uchar	mod;		/* bit 5 */
	uchar	shz;		/* bit 9-5 */
	long	imm21;		/* bits 20-00 */
	short	simm14;		/* bits 13-01, sign 00 */
	short	simm11;		/* bits 10-01, sign 00 */
	short	simm5;		/* bits 4-1, sign 0 */
	short	off;		/* bits 13-02, sign 00 */
	char	csimm5;		/* bits 20-17, sign 16 */
	char	*curr;		/* current fill level in output buffer */
	char	*end;		/* end of buffer */
};

typedef struct opdec	Opdec;

struct opdec
{
	char	*mnem;
	void	(*func)(Instr *, char *);
};

static char	ill[]	= "ILL";
static char	sizes[]	= "BHWXXXXX";

static char	*conds[8]	=
{
	"never",
	"equal",
	"less",
	"leq",
	"lessu",
	"lequ",
	"sv",
	"odd",
};

static char	*fconds[8]	=
{
	"F",
	"==",
	"<",
	"<=",
	">",
	">=",
	"!=",
	"T",
};

static void	das_nil(Instr *, char *);
static void	das_sys(Instr *, char *);
static void	das_arith(Instr *, char *);
static void	das_ldwx(Instr *, char *);
static void	das_ld(Instr *, char *);
static void	das_ldil(Instr *, char *);
static void	das_ldo(Instr *, char *);
static void	das_st(Instr *, char *);
static void	das_fldst(Instr *, char *);
static void	das_fltc(Instr *, char *);
static void	das_combt(Instr *, char *);
static void	das_ibt(Instr *, char *);
static void	das_combf(Instr *, char *);
static void	das_ibf(Instr *, char *);
static void	das_extrs(Instr *, char *);
static void	das_be(Instr *, char *);
static void	das_bx(Instr *, char *);

Opdec	dastab[1 << 6]	=
{
	{ill,		das_sys},	/* 0x00 */
	{ill,		das_nil},	/* 0x01 */
	{ill,		das_arith},	/* 0x02 */
	{ill,		das_ldwx},	/* 0x03 */
	{ill,		das_nil},	/* 0x04 */
	{ill,		das_nil},	/* 0x05 */
	{ill,		das_nil},	/* 0x06 */
	{ill,		das_nil},	/* 0x07 */
	{ill,		das_ldil},	/* 0x08 */
	{ill,		das_nil},	/* 0x09 */
	{ill,		das_nil},	/* 0x0A */
	{ill,		das_fldst},	/* 0x0B */
	{ill,		das_fltc},	/* 0x0C */
	{ill,		das_ldo},	/* 0x0D */
	{ill,		das_nil},	/* 0x0E */
	{ill,		das_nil},	/* 0x0F */

	{"LDB",		das_ld},	/* 0x10 */
	{"LDH",		das_ld},	/* 0x11 */
	{"LDW",		das_ld},	/* 0x12 */
	{ill,		das_nil},	/* 0x13 */
	{ill,		das_nil},	/* 0x14 */
	{ill,		das_nil},	/* 0x15 */
	{ill,		das_nil},	/* 0x16 */
	{ill,		das_nil},	/* 0x17 */
	{"STB",		das_st},	/* 0x18 */
	{"STH",		das_st},	/* 0x19 */
	{"STW",		das_st},	/* 0x1A */
	{ill,		das_nil},	/* 0x1B */
	{ill,		das_nil},	/* 0x1C */
	{ill,		das_nil},	/* 0x1D */
	{ill,		das_nil},	/* 0x1E */
	{ill,		das_nil},	/* 0x1F */

	{ill,		das_combt},	/* 0x20 */
	{"COM",		das_ibt},	/* 0x21 */
	{ill,		das_combf},	/* 0x22 */
	{"COM",		das_ibf},	/* 0x23 */
	{ill,		das_nil},	/* 0x24 */
	{ill,		das_nil},	/* 0x25 */
	{ill,		das_nil},	/* 0x26 */
	{ill,		das_nil},	/* 0x27 */
	{ill,		das_nil},	/* 0x28 */
	{"ADD",		das_ibt},	/* 0x29 */
	{ill,		das_nil},	/* 0x2A */
	{"ADD",		das_ibf},	/* 0x2B */
	{ill,		das_nil},	/* 0x2C */
	{ill,		das_nil},	/* 0x2D */
	{ill,		das_nil},	/* 0x2E */
	{ill,		das_nil},	/* 0x2F */

	{ill,		das_nil},	/* 0x30 */
	{ill,		das_nil},	/* 0x31 */
	{ill,		das_nil},	/* 0x32 */
	{ill,		das_nil},	/* 0x33 */
	{ill,		das_extrs},	/* 0x34 */
	{ill,		das_nil},	/* 0x35 */
	{ill,		das_nil},	/* 0x36 */
	{ill,		das_nil},	/* 0x37 */
	{"BE",		das_be},	/* 0x38 */
	{"BLE",		das_be},	/* 0x39 */
	{ill,		das_bx},	/* 0x3A */
	{ill,		das_nil},	/* 0x3B */
	{ill,		das_nil},	/* 0x3C */
	{ill,		das_nil},	/* 0x3D */
	{ill,		das_nil},	/* 0x3E */
	{ill,		das_nil},	/* 0x3F */
};

static void
bprint(Instr *i, char *fmt, ...)
{
	va_list arg;

	va_start(arg, fmt);
	i->curr = vseprint(i->curr, i->end, fmt, arg);
	va_end(arg);
}

static void
decode(ulong *pc, Instr *i)
{
	ulong w;
	int t;

	w = *pc;

	i->value = w;
	i->op = (w >> 26) & 0x3F;
	i->subop = (w >> 5) & 0x7F;
	i->sysop = (w >> 5) & 0xFF;
	i->reg0 = (w >> 21) & 0x1F;
	i->reg1 = (w >> 16) & 0x1F;
	i->reg2 = w & 0x1F;
	i->space = (w >> 14) & 0x03;
	i->indexed = (w >> 13) & 0x01;
	i->cond = (w >> 13) & 0x07;
	i->sr = (i->cond >> 1) | ((i->cond & 1) << 2);
	i->ftype = (w >> 9) & 0xF;
	i->simm = (w >> 12) & 0x01;
	i->store = (w >> 9) & 0x01;
	i->size = (w >> 6) & 0x07;
	i->mod = (w >> 5) & 0x01;
	i->shz = (w >> 5) & 0x1F;
	i->imm21 = w & 0x01FFFFF;
	i->simm14 = (w >> 1) & 0x1FFF;
	i->simm11 = (w >> 1) & 0x03FF;
	i->simm5 = (w >> 1) & 0x0F;
	i->off = ((w >> 3) & 0x3FF) | ((w & (1 << 2)) << 8);
	i->csimm5 = (w >> 17) & 0x0F;
	if(w & 1) {
		i->simm14 |= ~((1 << 13) - 1);
		i->simm11 |= ~((1 << 10) - 1);
		i->simm5 |= ~((1 << 4) - 1);
		i->off |= ~((1 << 10) - 1);
	}
	if(w & (1 << 16))
		i->csimm5 |= ~((1 << 4) - 1);
}

static void
das_ill(Instr *i)
{
	das_nil(i, ill);
}

static void
das_nil(Instr *i, char *m)
{
	bprint(i, "%s\t%lx", m, i->value);
}

static void
das_sys(Instr *i, char *m)
{
	switch(i->sysop) {
	case 0x85:
		bprint(i, "LDSID\t(sr%d,r%d),r%d", i->sr, i->reg0, i->reg2);
		break;
	case 0xC1:
		bprint(i, "MTSP\tr%d,sr%d", i->reg1, i->sr);
		break;
	default:
		das_ill(i);
	}
}

static void
das_arith(Instr *i, char *m)
{
	switch(i->subop) {
	case 0x10:
		m = "AND";
		break;
	case 0x12:
		if (i->reg1 + i->reg0 + i->reg2 == 0) {
			bprint(i, "NOP");
			return;
		}
		m = "OR";
		break;
	case 0x14:
		m = "XOR";
		break;
	case 0x20:
		m = "SUB";
		break;
	case 0x30:
		m = "ADD";
		break;
	case 0x32:
		m = "SH1ADD";
		break;
	case 0x34:
		m = "SH2ADD";
		break;
	default:
		das_ill(i);
		return;
	}

	bprint(i, "%s\tr%d,r%d,r%d", m, i->reg1, i->reg0, i->reg2);
}

static void
das_ldwx(Instr *i, char *m)
{
	bprint(i, "LD%cX\tr%d(r%d),r%d", sizes[i->size], i->reg0, i->reg1, i->reg2);
}

static void
das_ld(Instr *i, char *m)
{
	bprint(i, "%s\t%d(r%d),r%d", m, i->simm14, i->reg0, i->reg1);
}

static ulong
unfrig17(ulong v)
{
	ulong r;

	r = ((v >> 3) & 0x3FF) |
		((v & (1 << 2)) << 8) |
		((v & (0x1F << 16)) >> 5);
	if (v & 1)
		r |= ~((1 << 16) - 1);
	return r << 2;
}

static ulong
unfrig21(ulong v)
{
	return (((v & 1) << 20) |
		((v & (0x7FF << 1)) << 8) |
		((v >> 12) & 3) |
		((v & (3 << 14)) >> 7) |
		((v & (0x1F << 16)) >> 14)) << 11;
}

static void
das_ldil(Instr *i, char *m)
{
	bprint(i, "LDIL\tL%%0x%lx,r%d", unfrig21(i->imm21), i->reg0);
}

static void
das_ldo(Instr *i, char *m)
{
	bprint(i, "LDO\t%d(r%d),r%d", i->simm14, i->reg0, i->reg1);
}

static void
das_st(Instr *i, char *m)
{
	bprint(i, "%s\tr%d,%d(r%d)", m, i->reg1, i->simm14, i->reg0);
}

static void
das_fldst(Instr *i, char *m)
{
	if (i->simm) {
		if (i->store)
			bprint(i, "FSTDS\tfr%d,%d(r%d)", i->reg2, i->csimm5, i->reg0);
		else
			bprint(i, "FLDDS\t%d(r%d),fr%d", i->reg0, i->csimm5, i->reg2);
	}
	else {
		if (i->store)
			bprint(i, "FSTDX\tfr%d,r%d(r%d)", i->reg2, i->reg1, i->reg0);
		else
			bprint(i, "FLDDX\tr%d(r%d),fr%d", i->reg0, i->reg1, i->reg2);
	}
}

static void
das_fltc(Instr *i, char *m)
{
	char *o;

	switch (i->ftype) {
	case 2:
		bprint(i, "FTEST");
		break;
	case 6:
		bprint(i, "FCMP\tfr%d,%s,fr%d", i->reg0, fconds[i->reg2 >> 2], i->reg1);
		break;
	case 7:
		switch (i->cond) {
		case 0:
			o = "ADD";
			break;
		case 1:
			o = "SUB";
			break;
		case 2:
			o = "MUL";
			break;
		case 3:
			o = "DIV";
			break;
		default:
			das_ill(i);
			return;
		}
		bprint(i, "F%s\tfr%d,fr%d,fr%d", o, i->reg0, i->reg1, i->reg2);
		break;
	default:
		das_ill(i);
	}
}

static void
das_combt(Instr *i, char *m)
{
	bprint(i, "COMBT,%s\tr%d,r%d,%d", conds[i->cond], i->reg1, i->reg0, i->off);
}

static void
das_ibt(Instr *i, char *m)
{
	bprint(i, "%sIBT,%s\t%d,r%d,%d", m, conds[i->cond], i->csimm5, i->reg0, i->off);
}

static void
das_combf(Instr *i, char *m)
{
	bprint(i, "COMBF,%s\tr%d,r%d,%d", conds[i->cond], i->reg1, i->reg0, i->off);
}

static void
das_ibf(Instr *i, char *m)
{
	bprint(i, "%sIBF,%s\t%d,r%d,%d", m, conds[i->cond], i->csimm5, i->reg0, i->off);
}

static void
das_extrs(Instr *i, char *m)
{
	bprint(i, "EXTRS\tr%d,%d,%d,r%d", i->reg0, i->shz, 32 - i->reg2, i->reg1);
}

static void
das_be(Instr *i, char *m)
{
	bprint(i, "%s\t%d(sr%d,r%d)", m, unfrig17(i->value), i->sr, i->reg0);
}

static void
das_bx(Instr *i, char *m)
{
	switch(i->cond) {
	case 0:
		bprint(i, "BL\t%d,r%d", unfrig17(i->value), i->reg0);
		break;
	case 6:
		bprint(i, "BV\tr%d(r%d)", i->reg1, i->reg0);
		break;
	default:
		das_ill(i);
	}
}

static int
inst(ulong *pc)
{
	Instr instr;
	static char buf[128];

	decode(pc, &instr);
	instr.curr = buf;
	instr.end = buf + sizeof(buf) - 1;
	(*dastab[instr.op].func)(&instr, dastab[instr.op].mnem);
	if (cflag > 5)
		print("\t%.8lux %.8lux %s\n", pc, *pc, buf);
	else
		print("\t%.8lux %s\n", pc, buf);
}

void
das(ulong *x, int n)
{
	while (--n >= 0)
		inst(x++);
}
