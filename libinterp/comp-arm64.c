/*
 * ARM64 (AArch64) JIT compiler for Dis Virtual Machine — Apple Silicon
 *
 * Clean rewrite following the Inferno JIT architecture (comp-arm.c)
 * adapted for 64-bit ARM64 with hardware FP and divide.
 */

#include "lib9.h"
#include "isa.h"
#include "interp.h"
#include "raise.h"

#include <sys/mman.h>
#include <unistd.h>

#ifdef __APPLE__
#include <pthread.h>
#include <libkern/OSCacheControl.h>
#endif

#define	RESCHED	1	/* check for interpreter reschedule */

enum
{
	/* ARM64 register assignments for JIT */
	RA0	= 0,	/* X0: scratch / arg0 / return value */
	RA1	= 1,	/* X1: scratch / arg1 */
	RA2	= 2,	/* X2: scratch / arg2 */
	RA3	= 3,	/* X3: scratch / arg3 */
	RTA	= 4,	/* X4: temp address */
	RCON	= 5,	/* X5: constant builder */

	RREG	= 20,	/* X20: &R (callee-saved) */
	RFP	= 21,	/* X21: cached R.FP (callee-saved) */
	RMP	= 22,	/* X22: cached R.MP (callee-saved) */

	XZR	= 31,	/* zero register / SP encoding */

	/* FP scratch registers */
	FA0	= 0,	/* D0 */
	FA1	= 1,	/* D1 */
	FA2	= 2,	/* D2 */

	/* Condition codes */
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

	HS	= CS,
	LO	= CC,

	/* Memory operation types */
	Lea	= 100,
	Ldw,		/* load 64-bit word */
	Stw,		/* store 64-bit word */
	Ldb,		/* load byte */
	Stb,		/* store byte */
	Ldw32,		/* load 32-bit word (zero-extend) */
	Stw32,		/* store 32-bit word */
	Ldw32s,		/* load 32-bit word (sign-extend to 64-bit) */
	Ldh,		/* load halfword */
	Sth,		/* store halfword */

	/* Punt flags */
	SRCOP	= (1<<0),
	DSTOP	= (1<<1),
	WRTPC	= (1<<2),
	TCHECK	= (1<<3),
	NEWPC	= (1<<4),
	DBRAN	= (1<<5),
	THREOP	= (1<<6),

	/* Macro indices */
	MacFRP	= 0,
	MacRET,
	MacCASE,
	MacCOLR,
	MacMCAL,
	MacFRAM,
	MacMFRA,
	MacRELQ,
	MacBNDS,
	NMACRO
};

/*
 * ARM64 instruction encoding macros.
 * All instructions are 32-bit words emitted via *code++.
 */

/* Data Processing — Immediate (64-bit, sf=1) */
#define ADD_IMM(Rd, Rn, imm12) \
	*code++ = (0x91000000 | ((imm12)<<10) | ((Rn)<<5) | (Rd))
#define SUB_IMM(Rd, Rn, imm12) \
	*code++ = (0xD1000000 | ((imm12)<<10) | ((Rn)<<5) | (Rd))
#define ADDS_IMM(Rd, Rn, imm12) \
	*code++ = (0xB1000000 | ((imm12)<<10) | ((Rn)<<5) | (Rd))
#define SUBS_IMM(Rd, Rn, imm12) \
	*code++ = (0xF1000000 | ((imm12)<<10) | ((Rn)<<5) | (Rd))

/* Data Processing — Immediate (32-bit, sf=0) */
#define SUBS_IMM32(Rd, Rn, imm12) \
	*code++ = (0x71000000 | ((imm12)<<10) | ((Rn)<<5) | (Rd))

/* Data Processing — Register (64-bit, sf=1) */
#define ADD_REG(Rd, Rn, Rm) \
	*code++ = (0x8B000000 | ((Rm)<<16) | ((Rn)<<5) | (Rd))
#define SUB_REG(Rd, Rn, Rm) \
	*code++ = (0xCB000000 | ((Rm)<<16) | ((Rn)<<5) | (Rd))
#define SUBS_REG(Rd, Rn, Rm) \
	*code++ = (0xEB000000 | ((Rm)<<16) | ((Rn)<<5) | (Rd))
#define AND_REG(Rd, Rn, Rm) \
	*code++ = (0x8A000000 | ((Rm)<<16) | ((Rn)<<5) | (Rd))
#define ORR_REG(Rd, Rn, Rm) \
	*code++ = (0xAA000000 | ((Rm)<<16) | ((Rn)<<5) | (Rd))
#define EOR_REG(Rd, Rn, Rm) \
	*code++ = (0xCA000000 | ((Rm)<<16) | ((Rn)<<5) | (Rd))
#define MOV_REG(Rd, Rm) \
	ORR_REG(Rd, XZR, Rm)
#define NEG_REG(Rd, Rm) \
	SUB_REG(Rd, XZR, Rm)

/* Compare — aliases */
#define CMP_REG(Rn, Rm)	SUBS_REG(XZR, Rn, Rm)
#define CMP_IMM(Rn, imm12)	SUBS_IMM(XZR, Rn, imm12)
#define CMN_IMM(Rn, imm12)	ADDS_IMM(XZR, Rn, imm12)
#define CMP_IMM32(Rn, imm12)	SUBS_IMM32(XZR, Rn, imm12)

/* Shift — 2-source (64-bit) */
#define LSLV_REG(Rd, Rn, Rm) \
	*code++ = (0x9AC02000 | ((Rm)<<16) | ((Rn)<<5) | (Rd))
#define LSRV_REG(Rd, Rn, Rm) \
	*code++ = (0x9AC02400 | ((Rm)<<16) | ((Rn)<<5) | (Rd))
#define ASRV_REG(Rd, Rn, Rm) \
	*code++ = (0x9AC02800 | ((Rm)<<16) | ((Rn)<<5) | (Rd))

/* Multiply / Divide (64-bit) */
#define MUL_REG(Rd, Rn, Rm) \
	*code++ = (0x9B007C00 | ((Rm)<<16) | ((Rn)<<5) | (Rd))
#define SDIV_REG(Rd, Rn, Rm) \
	*code++ = (0x9AC00C00 | ((Rm)<<16) | ((Rn)<<5) | (Rd))
#define MSUB_REG(Rd, Rn, Rm, Ra) \
	*code++ = (0x9B008000 | ((Rm)<<16) | ((Ra)<<10) | ((Rn)<<5) | (Rd))

/* Move Wide (64-bit, sf=1) */
#define MOVZ(Rd, imm16, hw) \
	*code++ = (0xD2800000 | ((hw)<<21) | ((imm16)<<5) | (Rd))
#define MOVK(Rd, imm16, hw) \
	*code++ = (0xF2800000 | ((hw)<<21) | ((imm16)<<5) | (Rd))

/* Sign extend word (SBFM Xd, Xn, #0, #31) */
#define SXTW(Rd, Rn) \
	*code++ = (0x93407C00 | ((Rn)<<5) | (Rd))

/* Load / Store — Unsigned Offset */
#define LDR_UOFF(Rt, Rn, scaled) \
	*code++ = (0xF9400000 | ((scaled)<<10) | ((Rn)<<5) | (Rt))
#define STR_UOFF(Rt, Rn, scaled) \
	*code++ = (0xF9000000 | ((scaled)<<10) | ((Rn)<<5) | (Rt))
#define LDR32_UOFF(Rt, Rn, scaled) \
	*code++ = (0xB9400000 | ((scaled)<<10) | ((Rn)<<5) | (Rt))
#define STR32_UOFF(Rt, Rn, scaled) \
	*code++ = (0xB9000000 | ((scaled)<<10) | ((Rn)<<5) | (Rt))
#define LDRB_UOFF(Rt, Rn, off) \
	*code++ = (0x39400000 | ((off)<<10) | ((Rn)<<5) | (Rt))
#define STRB_UOFF(Rt, Rn, off) \
	*code++ = (0x39000000 | ((off)<<10) | ((Rn)<<5) | (Rt))
#define LDRH_UOFF(Rt, Rn, scaled) \
	*code++ = (0x79400000 | ((scaled)<<10) | ((Rn)<<5) | (Rt))

/* Load / Store — Unscaled Immediate (signed 9-bit offset) */
#define LDUR(Rt, Rn, simm9) \
	*code++ = (0xF8400000 | (((simm9)&0x1FF)<<12) | ((Rn)<<5) | (Rt))
#define STUR(Rt, Rn, simm9) \
	*code++ = (0xF8000000 | (((simm9)&0x1FF)<<12) | ((Rn)<<5) | (Rt))
#define LDUR32(Rt, Rn, simm9) \
	*code++ = (0xB8400000 | (((simm9)&0x1FF)<<12) | ((Rn)<<5) | (Rt))
#define STUR32(Rt, Rn, simm9) \
	*code++ = (0xB8000000 | (((simm9)&0x1FF)<<12) | ((Rn)<<5) | (Rt))
/* Sign-extending 32-bit load (LDRSW): loads int32 and sign-extends to int64 */
#define LDRSW_UOFF(Rt, Rn, scaled) \
	*code++ = (0xB9800000 | ((scaled)<<10) | ((Rn)<<5) | (Rt))
#define LDURSW(Rt, Rn, simm9) \
	*code++ = (0xB8800000 | (((simm9)&0x1FF)<<12) | ((Rn)<<5) | (Rt))
#define LDURB(Rt, Rn, simm9) \
	*code++ = (0x38400000 | (((simm9)&0x1FF)<<12) | ((Rn)<<5) | (Rt))
#define STURB(Rt, Rn, simm9) \
	*code++ = (0x38000000 | (((simm9)&0x1FF)<<12) | ((Rn)<<5) | (Rt))
#define LDURH(Rt, Rn, simm9) \
	*code++ = (0x78400000 | (((simm9)&0x1FF)<<12) | ((Rn)<<5) | (Rt))

/* Load / Store Pair — Signed Offset (64-bit, scaled by 8) */
#define LDP(Rt1, Rt2, Rn, simm7) \
	*code++ = (0xA9400000 | (((simm7)&0x7F)<<15) | ((Rt2)<<10) | ((Rn)<<5) | (Rt1))
#define STP(Rt1, Rt2, Rn, simm7) \
	*code++ = (0xA9000000 | (((simm7)&0x7F)<<15) | ((Rt2)<<10) | ((Rn)<<5) | (Rt1))

/* FP Load / Store — Unsigned Offset (double, scaled by 8) */
#define FLDR_UOFF(Ft, Rn, scaled) \
	*code++ = (0xFD400000 | ((scaled)<<10) | ((Rn)<<5) | (Ft))
#define FSTR_UOFF(Ft, Rn, scaled) \
	*code++ = (0xFD000000 | ((scaled)<<10) | ((Rn)<<5) | (Ft))

/* FP Load / Store — Unscaled (double) */
#define FLDUR(Ft, Rn, simm9) \
	*code++ = (0xFC400000 | (((simm9)&0x1FF)<<12) | ((Rn)<<5) | (Ft))
#define FSTUR(Ft, Rn, simm9) \
	*code++ = (0xFC000000 | (((simm9)&0x1FF)<<12) | ((Rn)<<5) | (Ft))

/* FP Arithmetic (double) */
#define FADD_D(Fd, Fn, Fm)	*code++ = (0x1E602800 | ((Fm)<<16) | ((Fn)<<5) | (Fd))
#define FSUB_D(Fd, Fn, Fm)	*code++ = (0x1E603800 | ((Fm)<<16) | ((Fn)<<5) | (Fd))
#define FMUL_D(Fd, Fn, Fm)	*code++ = (0x1E600800 | ((Fm)<<16) | ((Fn)<<5) | (Fd))
#define FDIV_D(Fd, Fn, Fm)	*code++ = (0x1E601800 | ((Fm)<<16) | ((Fn)<<5) | (Fd))
#define FNEG_D(Fd, Fn)		*code++ = (0x1E614000 | ((Fn)<<5) | (Fd))
#define FCMP_D(Fn, Fm)		*code++ = (0x1E602000 | ((Fm)<<16) | ((Fn)<<5))

/* FP <-> Int Conversion */
#define SCVTF_DX(Fd, Rn)	*code++ = (0x9E620000 | ((Rn)<<5) | (Fd))  /* int64->double */
#define FCVTZS_XD(Rd, Fn)	*code++ = (0x9E780000 | ((Fn)<<5) | (Rd))  /* double->int64 */

/* Branch */
#define B_IMM(imm26)		*code++ = (0x14000000 | ((imm26) & 0x3FFFFFF))
#define BL_IMM(imm26)		*code++ = (0x94000000 | ((imm26) & 0x3FFFFFF))
#define BR_REG(Rn)		*code++ = (0xD61F0000 | ((Rn)<<5))
#define BLR_REG(Rn)		*code++ = (0xD63F0000 | ((Rn)<<5))
#define RET_X30()		*code++ = 0xD65F03C0

/* Conditional Branch */
#define BCOND(cond, imm19) \
	*code++ = (0x54000000 | (((imm19) & 0x7FFFF)<<5) | (cond))
#define CBZ_X(Rt, imm19) \
	*code++ = (0xB4000000 | (((imm19) & 0x7FFFF)<<5) | (Rt))
#define CBNZ_X(Rt, imm19) \
	*code++ = (0xB5000000 | (((imm19) & 0x7FFFF)<<5) | (Rt))

/* Patch helpers */
#define RELPC(pc)		((ulong)(base + (pc)))
#define IA(s, o)		(base + s[o])

#define PATCH_BCOND(ptr)	do { \
	long _off = (long)((code) - (ptr)); \
	*(ptr) = (*(ptr) & ~(0x7FFFF << 5)) | (((_off) & 0x7FFFF) << 5); \
} while(0)

#define PATCH_B(ptr)		do { \
	long _off = (long)((code) - (ptr)); \
	*(ptr) = (*(ptr) & ~0x3FFFFFF) | ((_off) & 0x3FFFFFF); \
} while(0)

/*
 * Static globals
 */
static	u32int*	code;
static	u32int*	base;
static	ulong*	patch;
static	ulong	codeoff;
static	int	pass;
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
static	void	macbounds(void);
static	void	movmem(Inst*);
static	void	mid(Inst*, int, int);
static	void	mem(int, long, int, int);
static	void	memfl(int, long, int, int);
static	void	bcondbra(int, int);
static	void	bradis(int);
static	void	bramac(int);
static	void	blmac(int);
extern	void	das(u32int*, int);

#define T(r)	*((void**)(R.r))

static struct
{
	int	idx;
	void	(*gen)(void);
	char*	name;
} mactab[] =
{
	{ MacFRP,	macfrp,		"FRP" },
	{ MacRET,	macret,		"RET" },
	{ MacCASE,	maccase,	"CASE" },
	{ MacCOLR,	maccolr,	"COLR" },
	{ MacMCAL,	macmcal,	"MCAL" },
	{ MacFRAM,	macfram,	"FRAM" },
	{ MacMFRA,	macmfra,	"MFRA" },
	{ MacRELQ,	macrelq,	"RELQ" },
	{ MacBNDS,	macbounds,	"BNDS" },
};

/*
 * C helper functions called from JIT code via punt/macros.
 */
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
	error(exCompile);
}

static void
bounds(void)
{
	error(exBounds);
}

/*
 * con — load a 64-bit constant into register rd.
 * Always emits exactly 4 instructions for phase consistency.
 */
static void
con(uvlong val, int rd)
{
	MOVZ(rd, (val >>  0) & 0xFFFF, 0);
	MOVK(rd, (val >> 16) & 0xFFFF, 1);
	MOVK(rd, (val >> 32) & 0xFFFF, 2);
	MOVK(rd, (val >> 48) & 0xFFFF, 3);
}

/*
 * bcondbra — emit B.cond to a macro.
 */
static void
bcondbra(int cond, int macidx)
{
	long off;

	if(pass == 0) {
		BCOND(cond, 0);
		return;
	}
	off = ((long)(IA(macro, macidx)) - (long)(code + codeoff)) >> 2;
	if(off > 0x3FFFF || off < -0x40000) {
		print("bcondbra overflow: off=%ld macidx=%d\n", off, macidx);
		urk("bcondbra: branch too far");
	}
	BCOND(cond, off);
}

/*
 * bradis — emit unconditional B to a Dis PC.
 */
static void
bradis(int dispc)
{
	long off;

	if(pass == 0) {
		B_IMM(0);
		return;
	}
	off = ((long)(IA(patch, dispc)) - (long)(code + codeoff)) >> 2;
	B_IMM(off);
}

/*
 * bramac — emit unconditional B to a macro.
 */
static void
bramac(int macidx)
{
	long off;

	if(pass == 0) {
		B_IMM(0);
		return;
	}
	off = ((long)(IA(macro, macidx)) - (long)(code + codeoff)) >> 2;
	if(off > 0x1FFFFFF || off < -0x2000000) {
		print("bramac overflow: off=%ld base=%p code=%p codeoff=%lud macidx=%d\n",
			off, base, code, codeoff, macidx);
		urk("bramac: branch too far");
	}
	B_IMM(off);
}

/*
 * blmac — emit BL (branch with link) to a macro.
 */
static void
blmac(int macidx)
{
	long off;

	if(pass == 0) {
		BL_IMM(0);
		return;
	}
	off = ((long)(IA(macro, macidx)) - (long)(code + codeoff)) >> 2;
	if(off > 0x1FFFFFF || off < -0x2000000) {
		print("blmac overflow: off=%ld base=%p code=%p codeoff=%lud macidx=%d\n",
			off, base, code, codeoff, macidx);
		urk("blmac: branch too far");
	}
	BL_IMM(off);
}

/*
 * mem — load or store at base register + byte offset.
 */
static void
mem(int inst, long off, int rbase, int r)
{
	if(inst == Lea) {
		if(off == 0)
			MOV_REG(r, rbase);
		else if(off > 0 && off < 4096)
			ADD_IMM(r, rbase, off);
		else if(off < 0 && -off < 4096)
			SUB_IMM(r, rbase, -off);
		else {
			con((uvlong)(ulong)off, RCON);
			ADD_REG(r, rbase, RCON);
		}
		return;
	}

	switch(inst) {
	case Ldw:
		if(off >= 0 && (off & 7) == 0 && (off >> 3) < 4096)
			LDR_UOFF(r, rbase, off >> 3);
		else if(off >= -256 && off <= 255)
			LDUR(r, rbase, off);
		else {
			con((uvlong)(ulong)off, RCON);
			ADD_REG(RCON, rbase, RCON);
			LDR_UOFF(r, RCON, 0);
		}
		break;
	case Stw:
		if(off >= 0 && (off & 7) == 0 && (off >> 3) < 4096)
			STR_UOFF(r, rbase, off >> 3);
		else if(off >= -256 && off <= 255)
			STUR(r, rbase, off);
		else {
			con((uvlong)(ulong)off, RCON);
			ADD_REG(RCON, rbase, RCON);
			STR_UOFF(r, RCON, 0);
		}
		break;
	case Ldb:
		if(off >= 0 && off < 4096)
			LDRB_UOFF(r, rbase, off);
		else if(off >= -256 && off <= 255)
			LDURB(r, rbase, off);
		else {
			con((uvlong)(ulong)off, RCON);
			ADD_REG(RCON, rbase, RCON);
			LDRB_UOFF(r, RCON, 0);
		}
		break;
	case Stb:
		if(off >= 0 && off < 4096)
			STRB_UOFF(r, rbase, off);
		else if(off >= -256 && off <= 255)
			STURB(r, rbase, off);
		else {
			con((uvlong)(ulong)off, RCON);
			ADD_REG(RCON, rbase, RCON);
			STRB_UOFF(r, RCON, 0);
		}
		break;
	case Ldw32:
		if(off >= 0 && (off & 3) == 0 && (off >> 2) < 4096)
			LDR32_UOFF(r, rbase, off >> 2);
		else if(off >= -256 && off <= 255)
			LDUR32(r, rbase, off);
		else {
			con((uvlong)(ulong)off, RCON);
			ADD_REG(RCON, rbase, RCON);
			LDR32_UOFF(r, RCON, 0);
		}
		break;
	case Ldw32s:	/* sign-extending 32-bit load (LDRSW) */
		if(off >= 0 && (off & 3) == 0 && (off >> 2) < 4096)
			LDRSW_UOFF(r, rbase, off >> 2);
		else if(off >= -256 && off <= 255)
			LDURSW(r, rbase, off);
		else {
			con((uvlong)(ulong)off, RCON);
			ADD_REG(RCON, rbase, RCON);
			LDRSW_UOFF(r, RCON, 0);
		}
		break;
	case Stw32:
		if(off >= 0 && (off & 3) == 0 && (off >> 2) < 4096)
			STR32_UOFF(r, rbase, off >> 2);
		else if(off >= -256 && off <= 255)
			STUR32(r, rbase, off);
		else {
			con((uvlong)(ulong)off, RCON);
			ADD_REG(RCON, rbase, RCON);
			STR32_UOFF(r, RCON, 0);
		}
		break;
	case Ldh:
		if(off >= 0 && (off & 1) == 0 && (off >> 1) < 4096)
			LDRH_UOFF(r, rbase, off >> 1);
		else if(off >= -256 && off <= 255)
			LDURH(r, rbase, off);
		else {
			con((uvlong)(ulong)off, RCON);
			ADD_REG(RCON, rbase, RCON);
			LDRH_UOFF(r, RCON, 0);
		}
		break;
	}
}

/*
 * Float memory operations — load/store doubles via Dn registers.
 */
static void
memfl(int inst, long off, int rbase, int fr)
{
	switch(inst) {
	case Ldw:	/* load double */
		if(off >= 0 && (off & 7) == 0 && (off >> 3) < 4096)
			FLDR_UOFF(fr, rbase, off >> 3);
		else if(off >= -256 && off <= 255)
			FLDUR(fr, rbase, off);
		else {
			con((uvlong)(ulong)off, RCON);
			ADD_REG(RCON, rbase, RCON);
			FLDR_UOFF(fr, RCON, 0);
		}
		break;
	case Stw:	/* store double */
		if(off >= 0 && (off & 7) == 0 && (off >> 3) < 4096)
			FSTR_UOFF(fr, rbase, off >> 3);
		else if(off >= -256 && off <= 255)
			FSTUR(fr, rbase, off);
		else {
			con((uvlong)(ulong)off, RCON);
			ADD_REG(RCON, rbase, RCON);
			FSTR_UOFF(fr, RCON, 0);
		}
		break;
	}
}

/*
 * opx — decode Dis addressing mode and perform load/store.
 */
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
		con(a->imm, r);
		if(mi == Lea) {
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
opwld(Inst *i, int op, int r)
{
	opx(USRC(i->add), &i->s, op, r, O(REG, st));
}

static void
opwst(Inst *i, int op, int r)
{
	opx(UDST(i->add), &i->d, op, r, O(REG, dt));
}

/*
 * Float operand decode.
 */
static void
opfl(Adr *a, int am, int mi, int fr)
{
	int ir;

	switch(am) {
	default:
		urk("opfl");
	case AFP:
		memfl(mi, a->ind, RFP, fr);
		return;
	case AMP:
		memfl(mi, a->ind, RMP, fr);
		return;
	case AIND|AFP:
		ir = RFP;
		break;
	case AIND|AMP:
		ir = RMP;
		break;
	}
	mem(Ldw, a->i.f, ir, RTA);
	memfl(mi, a->i.s, RTA, fr);
}

static void
opflld(Inst *i, int mi, int fr)
{
	opfl(&i->s, USRC(i->add), mi, fr);
}

static void
opflst(Inst *i, int mi, int fr)
{
	opfl(&i->d, UDST(i->add), mi, fr);
}

/*
 * mid — decode middle operand.
 */
static void
mid(Inst *i, int mi, int r)
{
	int ir;

	switch(i->add & ARM) {
	default:
		opwst(i, mi, r);
		return;
	case AXIMM:
		if(mi == Lea)
			urk("mid/lea");
		con((short)i->reg, r);
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
midfl(Inst *i, int mi, int fr)
{
	int ir;

	switch(i->add & ARM) {
	default:
		opflst(i, mi, fr);
		return;
	case AXIMM:
		urk("midfl/imm");
		return;
	case AXINF:
		ir = RFP;
		break;
	case AXINM:
		ir = RMP;
		break;
	}
	memfl(mi, i->reg, ir, fr);
}

/*
 * literal — store value in literal pool and put its address in R.roff.
 */
static void
literal(uvlong imm, int roff)
{
	nlit++;
	con((uvlong)litpool, RTA);
	mem(Stw, roff, RREG, RTA);
	if(pass == 0)
		return;
	*litpool = imm;
	litpool++;
}

/*
 * schedcheck — decrement IC at backward branches; reschedule if expired.
 */
static void
schedcheck(Inst *i)
{
	u32int *skip;

	if(!RESCHED || i->d.ins > i)
		return;

	mem(Ldw32, O(REG, IC), RREG, RA0);
	SUBS_IMM32(RA0, RA0, 1);
	mem(Stw32, O(REG, IC), RREG, RA0);
	skip = code;
	BCOND(GT, 0);		/* IC > 0: continue */

	/* IC <= 0: reschedule.
	 * BL sets LR = address of next instruction (the comparison code).
	 * MacRELQ saves LR as R.PC so re-entry resumes at the comparison,
	 * not past the branch — matching AMD64's call/pop approach.
	 */
	mem(Stw, O(REG, FP), RREG, RFP);
	blmac(MacRELQ);

	PATCH_BCOND(skip);
}

/*
 * punt — fall back to C interpreter for an instruction.
 */
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
		con(RELPC(patch[i - mod->prog + 1]), RA0);
		mem(Stw, O(REG, PC), RREG, RA0);
	}
	if(m & DBRAN) {
		pc = patch[i->d.ins - mod->prog];
		literal(RELPC(pc), O(REG, d));
	}

	switch(i->add & ARM) {
	case AXNON:
		/* R.m = R.d (matches dec[] behaviour regardless of THREOP) */
		mem(Ldw, O(REG, d), RREG, RA0);
		mem(Stw, O(REG, m), RREG, RA0);
		break;
	case AXIMM:
		literal((short)i->reg, O(REG, m));
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
	con((uvlong)fn, RTA);
	BLR_REG(RTA);

	con((uvlong)&R, RREG);

	if(m & TCHECK) {
		mem(Ldw, O(REG, t), RREG, RA0);
		CBZ_X(RA0, 3);
		mem(Ldw, O(REG, xpc), RREG, RTA);
		BR_REG(RTA);
	}

	mem(Ldw, O(REG, FP), RREG, RFP);
	mem(Ldw, O(REG, MP), RREG, RMP);

	if(m & NEWPC) {
		mem(Ldw, O(REG, PC), RREG, RTA);
		BR_REG(RTA);
	}
}

/*
 * Branch helpers.
 */
static int
swapbraop(int b)
{
	switch(b) {
	case GE:	return LE;
	case LE:	return GE;
	case GT:	return LT;
	case LT:	return GT;
	}
	return b;
}

static void
cbra(Inst *i, int r)
{
	if(RESCHED)
		schedcheck(i);
	opwld(i, Ldw, RA0);
	mid(i, Ldw, RA1);
	CMP_REG(RA0, RA1);
	{
		long off;
		if(pass == 0) {
			BCOND(r, 0);
		} else {
			off = ((long)(IA(patch, i->d.ins - mod->prog)) - (long)(code + codeoff)) >> 2;
			BCOND(r, off);
		}
	}
}

static void
cbrab(Inst *i, int r)
{
	if(RESCHED)
		schedcheck(i);
	opwld(i, Ldb, RA0);
	mid(i, Ldb, RA1);
	CMP_REG(RA0, RA1);
	{
		long off;
		if(pass == 0) {
			BCOND(r, 0);
		} else {
			off = ((long)(IA(patch, i->d.ins - mod->prog)) - (long)(code + codeoff)) >> 2;
			BCOND(r, off);
		}
	}
}

static void
cbral(Inst *i, int r)
{
	if(RESCHED)
		schedcheck(i);
	opwld(i, Ldw, RA0);
	mid(i, Ldw, RA1);
	CMP_REG(RA0, RA1);
	{
		long off;
		if(pass == 0) {
			BCOND(r, 0);
		} else {
			off = ((long)(IA(patch, i->d.ins - mod->prog)) - (long)(code + codeoff)) >> 2;
			BCOND(r, off);
		}
	}
}

static void
cbraf(Inst *i, int r)
{
	if(RESCHED)
		schedcheck(i);
	opflld(i, Ldw, FA0);
	midfl(i, Ldw, FA1);
	FCMP_D(FA0, FA1);
	{
		long off;
		if(pass == 0) {
			BCOND(r, 0);
		} else {
			off = ((long)(IA(patch, i->d.ins - mod->prog)) - (long)(code + codeoff)) >> 2;
			BCOND(r, off);
		}
	}
}

/*
 * comcase — binary search case statement.
 */
static void
comcase(Inst *i, int w)
{
	int l;
	WORD *t, *e;

	if(w != 0) {
		opwld(i, Ldw, RA1);
		opwst(i, Lea, RA3);
		bramac(MacCASE);
	}

	t = (WORD*)(mod->origmp + i->d.ind + IBY2WD);
	l = t[-1];

	if(pass == 0) {
		if(l >= 0)
			t[-1] = -l - 1;
		return;
	}
	if(l >= 0)
		return;
	t[-1] = -l - 1;
	e = t + t[-1] * 3;
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

	t = (WORD*)(mod->origmp + i->d.ind + 2*IBY2WD);
	l = t[-2];
	if(pass == 0) {
		if(l >= 0)
			t[-2] = -l - 1;
		return;
	}
	if(l >= 0)
		return;
	t[-2] = -l - 1;
	e = t + t[-2] * 6;
	while(t < e) {
		t[4] = RELPC(patch[t[4]]);
		t += 6;
	}
	t[0] = RELPC(patch[t[0]]);
}

static void
comgoto(Inst *i)
{
	WORD *t, *e;

	opwld(i, Ldw, RA1);		/* index */
	opwst(i, Lea, RA0);		/* table base */
	/* each entry is IBY2WD bytes; compute RA0 + RA1 * IBY2WD */
	con(IBY2WD, RCON);
	MUL_REG(RA1, RA1, RCON);
	ADD_REG(RA0, RA0, RA1);
	LDR_UOFF(RTA, RA0, 0);
	BR_REG(RTA);

	if(pass == 0)
		return;

	t = (WORD*)(mod->origmp + i->d.ind);
	e = t + t[-1];
	t[-1] = 0;
	while(t < e) {
		t[0] = RELPC(patch[t[0]]);
		t++;
	}
}

/*
 * commframe — inline module frame allocation.
 */
static void
commframe(Inst *i)
{
	u32int *mlnil, *punt_lab;

	opwld(i, Ldw, RA0);
	CMN_IMM(RA0, 1);
	mlnil = code;
	BCOND(EQ, 0);

	if((i->add & ARM) == AXIMM) {
		mem(Ldw, OA(Modlink, links) + i->reg * sizeof(Modl) + O(Modl, frame),
			RA0, RA3);
	} else {
		mid(i, Ldw, RA1);
		con(sizeof(Modl), RCON);
		MUL_REG(RA1, RA1, RCON);
		ADD_IMM(RA1, RA1, OA(Modlink, links) + O(Modl, frame));
		ADD_REG(RA1, RA0, RA1);
		LDR_UOFF(RA3, RA1, 0);
	}

	mem(Ldw, O(Type, initialize), RA3, RA1);
	punt_lab = code;
	CBNZ_X(RA1, 0);	/* initialize != 0: jump to MacFRAM path */

	opwst(i, Lea, RA0);

	PATCH_BCOND(mlnil);
	con(RELPC(patch[i - mod->prog + 1]), RA1);
	mem(Stw, O(REG, st), RREG, RA1);
	bramac(MacMFRA);

	PATCH_BCOND(punt_lab);
	blmac(MacFRAM);
	opwst(i, Stw, RA2);
}

/*
 * commcall — inline module call.
 */
static void
commcall(Inst *i)
{
	u32int *mlnil;

	opwld(i, Ldw, RA2);
	con(RELPC(patch[i - mod->prog + 1]), RA0);
	mem(Stw, O(Frame, lr), RA2, RA0);
	mem(Stw, O(Frame, fp), RA2, RFP);
	mem(Ldw, O(REG, M), RREG, RA3);
	mem(Stw, O(Frame, mr), RA2, RA3);
	opwst(i, Ldw, RA3);
	CMN_IMM(RA3, 1);
	mlnil = code;
	BCOND(EQ, 0);
	if((i->add & ARM) == AXIMM) {
		mem(Ldw, OA(Modlink, links) + i->reg * sizeof(Modl) + O(Modl, u.pc),
			RA3, RA0);
	} else {
		mid(i, Ldw, RA1);
		con(sizeof(Modl), RCON);
		MUL_REG(RA1, RA1, RCON);
		ADD_IMM(RA1, RA1, OA(Modlink, links) + O(Modl, u.pc));
		ADD_REG(RA1, RA3, RA1);
		LDR_UOFF(RA0, RA1, 0);
	}
	PATCH_BCOND(mlnil);
	blmac(MacMCAL);
}

/*
 * movmem — block memory copy for MOVM instruction.
 */
static void
movmem(Inst *i)
{
	u32int *cp;

	/* source address already in RA1 */
	if((i->add & ARM) != AXIMM) {
		mid(i, Ldw, RA3);
		CMP_IMM(RA3, 0);
		cp = code;
		BCOND(LE, 0);
		opwst(i, Lea, RA2);
		/* byte-by-byte loop */
		LDRB_UOFF(RA0, RA1, 0);
		STRB_UOFF(RA0, RA2, 0);
		ADD_IMM(RA1, RA1, 1);
		ADD_IMM(RA2, RA2, 1);
		SUB_IMM(RA3, RA3, 1);
		CBNZ_X(RA3, -5);
		PATCH_BCOND(cp);
		return;
	}
	switch(i->reg) {
	case 0:
		break;
	case 8:
		opwst(i, Lea, RA2);
		LDR_UOFF(RA0, RA1, 0);
		STR_UOFF(RA0, RA2, 0);
		break;
	case 16:
		opwst(i, Lea, RA2);
		LDP(RA0, RA3, RA1, 0);
		STP(RA0, RA3, RA2, 0);
		break;
	default:
		if((i->reg & 7) == 0) {
			con(i->reg >> 3, RA3);
			opwst(i, Lea, RA2);
			LDR_UOFF(RA0, RA1, 0);
			STR_UOFF(RA0, RA2, 0);
			ADD_IMM(RA1, RA1, 8);
			ADD_IMM(RA2, RA2, 8);
			SUB_IMM(RA3, RA3, 1);
			CBNZ_X(RA3, -5);
		} else {
			con(i->reg, RA3);
			opwst(i, Lea, RA2);
			LDRB_UOFF(RA0, RA1, 0);
			STRB_UOFF(RA0, RA2, 0);
			ADD_IMM(RA1, RA1, 1);
			ADD_IMM(RA2, RA2, 1);
			SUB_IMM(RA3, RA3, 1);
			CBNZ_X(RA3, -5);
		}
		break;
	}
}

/*
 * comp — compile one Dis instruction to ARM64.
 */
static void
comp(Inst *i)
{
	int r;

#if 0 /* PUNT_ALL: punt data ops to C, keep control flow inline */
	switch(i->op) {
	/*
	 * Control flow — must stay inline because they use compiled addresses
	 */
	case IJMP:
		if(RESCHED)
			schedcheck(i);
		bradis(i->d.ins - mod->prog);
		return;
	case ICALL:
		opwld(i, Ldw, RA0);
		con(RELPC(patch[i - mod->prog + 1]), RA1);
		mem(Stw, O(Frame, lr), RA0, RA1);
		mem(Stw, O(Frame, fp), RA0, RFP);
		MOV_REG(RFP, RA0);
		bradis(i->d.ins - mod->prog);
		return;
	case IRET:
		mem(Ldw, O(Frame, t), RFP, RA1);
		bramac(MacRET);
		return;
	case IFRAME:
		if(UXSRC(i->add) != SRC(AIMM)) {
			punt(i, SRCOP|DSTOP, optab[i->op]);
			return;
		}
		tinit[i->s.imm] = 1;
		con((uvlong)mod->type[i->s.imm], RA3);
		blmac(MacFRAM);
		opwst(i, Stw, RA2);
		return;
	case ICASE:
		comcase(i, 1);
		return;
	case ICASEC:
		comcase(i, 0);
		punt(i, SRCOP|DSTOP|NEWPC, optab[i->op]);
		return;
	case ICASEL:
		comcasel(i);
		punt(i, SRCOP|DSTOP|NEWPC, optab[i->op]);
		return;
	case IGOTO:
		comgoto(i);
		return;
	case IMOVPC:
		con((uvlong)&mod->prog[i->s.imm], RA0);
		opwst(i, Stw, RA0);
		return;

	/*
	 * Branches — must stay inline because JMP(d) in the C handlers
	 * dereferences R.d as a pointer, which doesn't work when R.d
	 * holds a compiled code address.
	 */
	case IBEQW: cbra(i, EQ); return;
	case IBNEW: cbra(i, NE); return;
	case IBLTW: cbra(i, LT); return;
	case IBLEW: cbra(i, LE); return;
	case IBGTW: cbra(i, GT); return;
	case IBGEW: cbra(i, GE); return;
	case IBEQB: cbrab(i, EQ); return;
	case IBNEB: cbrab(i, NE); return;
	case IBLTB: cbrab(i, LT); return;
	case IBLEB: cbrab(i, LE); return;
	case IBGTB: cbrab(i, GT); return;
	case IBGEB: cbrab(i, GE); return;
	case IBEQL: cbral(i, EQ); return;
	case IBNEL: cbral(i, NE); return;
	case IBLTL: cbral(i, LT); return;
	case IBLEL: cbral(i, LE); return;
	case IBGTL: cbral(i, GT); return;
	case IBGEL: cbral(i, GE); return;
	case IBEQF: cbraf(i, EQ); return;
	case IBNEF: cbraf(i, NE); return;
	case IBLTF: cbraf(i, MI); return;
	case IBLEF: cbraf(i, LS); return;
	case IBGTF: cbraf(i, GT); return;
	case IBGEF: cbraf(i, GE); return;

	/*
	 * Everything else — punt to C interpreter
	 */
	default:
		break;
	}
	{
		int flags = SRCOP|DSTOP;
		switch(i->op) {
		case IMCALL:
			flags = SRCOP|DSTOP|THREOP|WRTPC|NEWPC;
			break;
		case ISEND: case IRECV: case IALT:
			flags = SRCOP|DSTOP|TCHECK|WRTPC;
			break;
		case INBALT:
			flags = SRCOP|DSTOP|TCHECK|WRTPC;
			break;
		case ISPAWN:
			flags = SRCOP|DBRAN;
			break;
		case IMSPAWN:
			flags = SRCOP|DSTOP;
			break;
		case IBNEC: case IBLTC: case IBLEC: case IBGTC: case IBGEC: case IBEQC:
			flags = SRCOP|DBRAN|WRTPC|NEWPC;
			break;
		case IMFRAME:
			flags = SRCOP|DSTOP|THREOP;
			break;
		case INEWCM: case INEWCMP:
			flags = SRCOP|DSTOP|THREOP;
			break;
		case INEWCB: case INEWCW: case INEWCF: case INEWCP: case INEWCL:
			flags = DSTOP|THREOP;
			break;
		case IEXIT:
			flags = 0;
			break;
		case IRAISE:
			flags = SRCOP|WRTPC;
			break;
		case ISELF:
			flags = DSTOP;
			break;
		case IMULX: case IDIVX: case ICVTXX:
		case IMULX0: case IDIVX0: case ICVTXX0:
		case IMULX1: case IDIVX1: case ICVTXX1:
		case ICVTFX: case ICVTXF:
		case IEXPW: case IEXPL: case IEXPF:
		case IMNEWZ: case IADDC:
			flags = SRCOP|DSTOP|THREOP;
			break;
		}
		punt(i, flags, optab[i->op]);
		return;
	}
#endif

	switch(i->op) {
	default:
		punt(i, SRCOP|DSTOP, optab[i->op]);
		break;

	/* ---- Punted opcodes ---- */
	case IMCALL:
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
		punt(i, SRCOP|DSTOP, optab[i->op]);
		break;
	case INBALT:
		punt(i, SRCOP|DSTOP|TCHECK|WRTPC, optab[i->op]);
		break;
	case INEWCM:
	case INEWCMP:
		punt(i, SRCOP|DSTOP|THREOP, optab[i->op]);
		break;
	case IMFRAME:
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
	case ITCMP:
		punt(i, SRCOP|DSTOP, optab[i->op]);
		break;

	/* ---- Inline case/goto ---- */
	case ICASE:
		comcase(i, 1);
		break;
	case IGOTO:
		comgoto(i);
		break;

	/* ---- Data Movement ---- */
	case IMOVW:
		opwld(i, Ldw, RA0);
		opwst(i, Stw, RA0);
		break;
	case IMOVB:
		opwld(i, Ldb, RA0);
		opwst(i, Stb, RA0);
		break;
	case IMOVL:
	case IMOVF:
		opwld(i, Ldw, RA0);
		opwst(i, Stw, RA0);
		break;
	case ILEA:
		opwld(i, Lea, RA0);
		opwst(i, Stw, RA0);
		break;
	case IMOVPC:
		con((uvlong)&mod->prog[i->s.imm], RA0);
		opwst(i, Stw, RA0);
		break;

	/* ---- Arithmetic (word) ---- */
	case IADDW:
		mid(i, Ldw, RA1);
		opwld(i, Ldw, RA0);
		ADD_REG(RA0, RA1, RA0);
		opwst(i, Stw, RA0);
		break;
	case ISUBW:
		mid(i, Ldw, RA1);
		opwld(i, Ldw, RA0);
		SUB_REG(RA0, RA1, RA0);
		opwst(i, Stw, RA0);
		break;
	case IMULW:
		opwld(i, Ldw, RA1);
		mid(i, Ldw, RA0);
		MUL_REG(RA0, RA1, RA0);
		opwst(i, Stw, RA0);
		break;
	case IDIVW:
		opwld(i, Ldw, RA1);
		mid(i, Ldw, RA0);
		SDIV_REG(RA0, RA0, RA1);
		opwst(i, Stw, RA0);
		break;
	case IMODW:
		opwld(i, Ldw, RA1);
		mid(i, Ldw, RA0);
		SDIV_REG(RA2, RA0, RA1);
		MSUB_REG(RA0, RA1, RA2, RA0);
		opwst(i, Stw, RA0);
		break;

	/* ---- Arithmetic (byte) ---- */
	case IADDB:
		mid(i, Ldb, RA1);
		opwld(i, Ldb, RA0);
		ADD_REG(RA0, RA1, RA0);
		opwst(i, Stb, RA0);
		break;
	case ISUBB:
		mid(i, Ldb, RA1);
		opwld(i, Ldb, RA0);
		SUB_REG(RA0, RA1, RA0);
		opwst(i, Stb, RA0);
		break;
	case IMULB:
		opwld(i, Ldb, RA1);
		mid(i, Ldb, RA0);
		MUL_REG(RA0, RA1, RA0);
		opwst(i, Stb, RA0);
		break;
	case IDIVB:
		opwld(i, Ldb, RA1);
		mid(i, Ldb, RA0);
		SDIV_REG(RA0, RA0, RA1);
		opwst(i, Stb, RA0);
		break;
	case IMODB:
		opwld(i, Ldb, RA1);
		mid(i, Ldb, RA0);
		SDIV_REG(RA2, RA0, RA1);
		MSUB_REG(RA0, RA1, RA2, RA0);
		opwst(i, Stb, RA0);
		break;

	/* ---- Arithmetic (long = word on 64-bit) ---- */
	case IADDL:
		mid(i, Ldw, RA1);
		opwld(i, Ldw, RA0);
		ADD_REG(RA0, RA1, RA0);
		opwst(i, Stw, RA0);
		break;
	case ISUBL:
		mid(i, Ldw, RA1);
		opwld(i, Ldw, RA0);
		SUB_REG(RA0, RA1, RA0);
		opwst(i, Stw, RA0);
		break;
	case IMULL:
		opwld(i, Ldw, RA1);
		mid(i, Ldw, RA0);
		MUL_REG(RA0, RA1, RA0);
		opwst(i, Stw, RA0);
		break;
	case IDIVL:
		opwld(i, Ldw, RA1);
		mid(i, Ldw, RA0);
		SDIV_REG(RA0, RA0, RA1);
		opwst(i, Stw, RA0);
		break;
	case IMODL:
		opwld(i, Ldw, RA1);
		mid(i, Ldw, RA0);
		SDIV_REG(RA2, RA0, RA1);
		MSUB_REG(RA0, RA1, RA2, RA0);
		opwst(i, Stw, RA0);
		break;

	/* ---- Logic (word) ---- */
	case IANDW:
		mid(i, Ldw, RA1);
		opwld(i, Ldw, RA0);
		AND_REG(RA0, RA1, RA0);
		opwst(i, Stw, RA0);
		break;
	case IORW:
		mid(i, Ldw, RA1);
		opwld(i, Ldw, RA0);
		ORR_REG(RA0, RA1, RA0);
		opwst(i, Stw, RA0);
		break;
	case IXORW:
		mid(i, Ldw, RA1);
		opwld(i, Ldw, RA0);
		EOR_REG(RA0, RA1, RA0);
		opwst(i, Stw, RA0);
		break;

	/* ---- Logic (byte) ---- */
	case IANDB:
		mid(i, Ldb, RA1);
		opwld(i, Ldb, RA0);
		AND_REG(RA0, RA1, RA0);
		opwst(i, Stb, RA0);
		break;
	case IORB:
		mid(i, Ldb, RA1);
		opwld(i, Ldb, RA0);
		ORR_REG(RA0, RA1, RA0);
		opwst(i, Stb, RA0);
		break;
	case IXORB:
		mid(i, Ldb, RA1);
		opwld(i, Ldb, RA0);
		EOR_REG(RA0, RA1, RA0);
		opwst(i, Stb, RA0);
		break;

	/* ---- Logic (long = word on 64-bit) ---- */
	case IANDL:
		mid(i, Ldw, RA1);
		opwld(i, Ldw, RA0);
		AND_REG(RA0, RA1, RA0);
		opwst(i, Stw, RA0);
		break;
	case IORL:
		mid(i, Ldw, RA1);
		opwld(i, Ldw, RA0);
		ORR_REG(RA0, RA1, RA0);
		opwst(i, Stw, RA0);
		break;
	case IXORL:
		mid(i, Ldw, RA1);
		opwld(i, Ldw, RA0);
		EOR_REG(RA0, RA1, RA0);
		opwst(i, Stw, RA0);
		break;

	/* ---- Shifts (word) ---- */
	case ISHLW:
		mid(i, Ldw, RA1);
		opwld(i, Ldw, RA0);
		LSLV_REG(RA0, RA1, RA0);
		opwst(i, Stw, RA0);
		break;
	case ISHRW:
		mid(i, Ldw, RA1);
		opwld(i, Ldw, RA0);
		ASRV_REG(RA0, RA1, RA0);
		opwst(i, Stw, RA0);
		break;
	case ILSRW:
		mid(i, Ldw, RA1);
		opwld(i, Ldw, RA0);
		LSRV_REG(RA0, RA1, RA0);
		opwst(i, Stw, RA0);
		break;

	/* ---- Shifts (byte) ---- */
	case ISHLB:
		mid(i, Ldb, RA1);
		opwld(i, Ldb, RA0);
		LSLV_REG(RA0, RA1, RA0);
		opwst(i, Stb, RA0);
		break;
	case ISHRB:
		mid(i, Ldb, RA1);
		opwld(i, Ldb, RA0);
		ASRV_REG(RA0, RA1, RA0);
		opwst(i, Stb, RA0);
		break;

	/* ---- Shifts (long) ---- */
	case ISHLL:
		mid(i, Ldw, RA1);
		opwld(i, Ldw, RA0);
		LSLV_REG(RA0, RA1, RA0);
		opwst(i, Stw, RA0);
		break;
	case ISHRL:
		mid(i, Ldw, RA1);
		opwld(i, Ldw, RA0);
		ASRV_REG(RA0, RA1, RA0);
		opwst(i, Stw, RA0);
		break;
	case ILSRL:
		mid(i, Ldw, RA1);
		opwld(i, Ldw, RA0);
		LSRV_REG(RA0, RA1, RA0);
		opwst(i, Stw, RA0);
		break;

	/* ---- Float arithmetic ---- */
	case IADDF:
		opflld(i, Ldw, FA0);
		midfl(i, Ldw, FA1);
		FADD_D(FA1, FA1, FA0);
		opflst(i, Stw, FA1);
		break;
	case ISUBF:
		opflld(i, Ldw, FA0);
		midfl(i, Ldw, FA1);
		FSUB_D(FA1, FA1, FA0);
		opflst(i, Stw, FA1);
		break;
	case IMULF:
		opflld(i, Ldw, FA0);
		midfl(i, Ldw, FA1);
		FMUL_D(FA1, FA1, FA0);
		opflst(i, Stw, FA1);
		break;
	case IDIVF:
		opflld(i, Ldw, FA0);
		midfl(i, Ldw, FA1);
		FDIV_D(FA1, FA1, FA0);
		opflst(i, Stw, FA1);
		break;
	case INEGF:
		opflld(i, Ldw, FA0);
		FNEG_D(FA0, FA0);
		opflst(i, Stw, FA0);
		break;

	/* ---- Conversions ---- */
	case ICVTBW:
		opwld(i, Ldb, RA0);
		opwst(i, Stw, RA0);
		break;
	case ICVTWB:
		opwld(i, Ldw, RA0);
		opwst(i, Stb, RA0);
		break;
	case ICVTWL:
		opwld(i, Ldw, RA0);
		SXTW(RA0, RA0);
		opwst(i, Stw, RA0);
		break;
	case ICVTLW:
		opwld(i, Ldw, RA0);
		SXTW(RA0, RA0);
		opwst(i, Stw, RA0);
		break;
	case ICVTWF:
		opwld(i, Ldw, RA0);
		SXTW(RA0, RA0);
		SCVTF_DX(FA0, RA0);
		opflst(i, Stw, FA0);
		break;
	case ICVTFW:
		opflld(i, Ldw, FA0);
		FCVTZS_XD(RA0, FA0);
		SXTW(RA0, RA0);
		opwst(i, Stw, RA0);
		break;
	case ICVTLF:
		opwld(i, Ldw, RA0);
		SCVTF_DX(FA0, RA0);
		opflst(i, Stw, FA0);
		break;
	case ICVTFL:
		opflld(i, Ldw, FA0);
		FCVTZS_XD(RA0, FA0);
		opwst(i, Stw, RA0);
		break;

	/* ---- Branches (word) ---- */
	case IBEQW:	cbra(i, EQ);	break;
	case IBNEW:	cbra(i, NE);	break;
	case IBLTW:	cbra(i, LT);	break;
	case IBLEW:	cbra(i, LE);	break;
	case IBGTW:	cbra(i, GT);	break;
	case IBGEW:	cbra(i, GE);	break;

	/* ---- Branches (byte) ---- */
	case IBEQB:	cbrab(i, EQ);	break;
	case IBNEB:	cbrab(i, NE);	break;
	case IBLTB:	cbrab(i, LT);	break;
	case IBLEB:	cbrab(i, LE);	break;
	case IBGTB:	cbrab(i, GT);	break;
	case IBGEB:	cbrab(i, GE);	break;

	/* ---- Branches (long = word on 64-bit) ---- */
	case IBEQL:	cbral(i, EQ);	break;
	case IBNEL:	cbral(i, NE);	break;
	case IBLTL:	cbral(i, LT);	break;
	case IBLEL:	cbral(i, LE);	break;
	case IBGTL:	cbral(i, GT);	break;
	case IBGEL:	cbral(i, GE);	break;

	/* ---- Branches (float) ---- */
	case IBEQF:	cbraf(i, EQ);	break;
	case IBNEF:	cbraf(i, NE);	break;
	case IBLTF:	cbraf(i, MI);	break;
	case IBLEF:	cbraf(i, LS);	break;
	case IBGTF:	cbraf(i, GT);	break;
	case IBGEF:	cbraf(i, GE);	break;

	/* ---- Control Flow ---- */
	case IJMP:
		if(RESCHED)
			schedcheck(i);
		bradis(i->d.ins - mod->prog);
		break;
	case ICALL:
		opwld(i, Ldw, RA0);
		con(RELPC(patch[i - mod->prog + 1]), RA1);
		mem(Stw, O(Frame, lr), RA0, RA1);
		mem(Stw, O(Frame, fp), RA0, RFP);
		MOV_REG(RFP, RA0);
		bradis(i->d.ins - mod->prog);
		break;
	case IRET:
		mem(Ldw, O(Frame, t), RFP, RA1);
		bramac(MacRET);
		break;
	case IFRAME:
		if(UXSRC(i->add) != SRC(AIMM)) {
			punt(i, SRCOP|DSTOP, optab[i->op]);
			break;
		}
		tinit[i->s.imm] = 1;
		con((uvlong)mod->type[i->s.imm], RA3);
		blmac(MacFRAM);
		opwst(i, Stw, RA2);
		break;

	/* ---- Array Indexing ---- */
	case IINDW:
	case IINDF:
	case IINDL:
	case IINDB:
		opwld(i, Ldw, RA0);
		CMN_IMM(RA0, 1);
		bcondbra(EQ, MacBNDS);
		if(bflag)
			mem(Ldw, O(Array, len), RA0, RA2);
		mem(Ldw, O(Array, data), RA0, RA0);
		r = 0;
		switch(i->op) {
		case IINDL:
		case IINDF:
		case IINDW:
			r = 3;
			break;
		}
		if(UXDST(i->add) == DST(AIMM)) {
			if(bflag) {
				CMP_IMM(RA2, i->d.imm);
				bcondbra(LS, MacBNDS);
			}
			{
				long off = (r > 0) ? ((long)i->d.imm << r) : i->d.imm;
				if(off >= 0 && off < 4096)
					ADD_IMM(RA0, RA0, off);
				else {
					con(off, RCON);
					ADD_REG(RA0, RA0, RCON);
				}
			}
		} else {
			opwst(i, Ldw, RA1);
			SXTW(RA1, RA1);	/* index is Dis int (32-bit) */
			if(bflag) {
				CMP_REG(RA2, RA1);
				bcondbra(LS, MacBNDS);
			}
			if(r > 0) {
				con(r, RCON);
				LSLV_REG(RA1, RA1, RCON);
			}
			ADD_REG(RA0, RA0, RA1);
		}
		mid(i, Stw, RA0);
		break;
	case IINDX:
		opwld(i, Ldw, RA0);
		CMN_IMM(RA0, 1);
		bcondbra(EQ, MacBNDS);
		opwst(i, Ldw, RA1);
		SXTW(RA1, RA1);	/* index is Dis int (32-bit) */
		if(bflag) {
			mem(Ldw, O(Array, len), RA0, RA2);
			CMP_REG(RA2, RA1);
			bcondbra(LS, MacBNDS);
		}
		mem(Ldw, O(Array, t), RA0, RA2);
		mem(Ldw, O(Array, data), RA0, RA0);
		mem(Ldw32, O(Type, size), RA2, RA2);
		MUL_REG(RA1, RA1, RA2);
		ADD_REG(RA0, RA0, RA1);
		mid(i, Stw, RA0);
		break;
	case IINDC:
		punt(i, SRCOP|DSTOP|THREOP, optab[i->op]);
		break;

	/* ---- Pointer Move ---- */
	case ITAIL:
		opwld(i, Ldw, RA0);
		CMN_IMM(RA0, 1);
		bcondbra(EQ, MacBNDS);
		mem(Ldw, O(List, tail), RA0, RA1);
		goto movp;
	case IMOVP:
		opwld(i, Ldw, RA1);
		goto movp;
	case IHEADP:
		opwld(i, Ldw, RA0);
		CMN_IMM(RA0, 1);
		bcondbra(EQ, MacBNDS);
		mem(Ldw, OA(List, data), RA0, RA1);
	movp:
		CMN_IMM(RA1, 1);
		{
			u32int *skip_colr = code;
			BCOND(EQ, 0);
			blmac(MacCOLR);
			PATCH_BCOND(skip_colr);
		}
		opwst(i, Lea, RA2);
		mem(Ldw, 0, RA2, RA0);
		mem(Stw, 0, RA2, RA1);
		blmac(MacFRP);
		break;

	/* ---- Head (scalar from list) ---- */
	case IHEADW:
	case IHEADL:
	case IHEADF:
		opwld(i, Ldw, RA0);
		CMN_IMM(RA0, 1);
		bcondbra(EQ, MacBNDS);
		mem(Ldw, OA(List, data), RA0, RA0);
		opwst(i, Stw, RA0);
		break;
	case IHEADB:
		opwld(i, Ldw, RA0);
		CMN_IMM(RA0, 1);
		bcondbra(EQ, MacBNDS);
		mem(Ldb, OA(List, data), RA0, RA0);
		opwst(i, Stb, RA0);
		break;

	/* ---- Memory Move ---- */
	case IHEADM:
		opwld(i, Ldw, RA1);
		CMN_IMM(RA1, 1);
		bcondbra(EQ, MacBNDS);
		ADD_IMM(RA1, RA1, OA(List, data));
		movmem(i);
		break;
	case IMOVM:
		opwld(i, Lea, RA1);
		movmem(i);
		break;

	/* ---- Length ---- */
	case ILENA:
		opwld(i, Ldw, RA1);
		MOV_REG(RA0, XZR);
		CMN_IMM(RA1, 1);
		{
			u32int *skip = code;
			BCOND(EQ, 0);
			mem(Ldw, O(Array, len), RA1, RA0);
			PATCH_BCOND(skip);
		}
		opwst(i, Stw, RA0);
		break;
	case ILENC:
		opwld(i, Ldw, RA1);
		MOV_REG(RA0, XZR);
		CMN_IMM(RA1, 1);
		{
			u32int *skip = code;
			BCOND(EQ, 0);
			mem(Ldw32s, O(String, len), RA1, RA0);
			/* if len < 0, negate (Rune vs byte) */
			CMP_IMM(RA0, 0);
			{
				u32int *skip2 = code;
				BCOND(GE, 0);
				NEG_REG(RA0, RA0);
				PATCH_BCOND(skip2);
			}
			PATCH_BCOND(skip);
		}
		opwst(i, Stw, RA0);
		break;
	case ILENL:
		MOV_REG(RA0, XZR);
		opwld(i, Ldw, RA1);
		{
			u32int *loop, *done;
			loop = code;
			CMN_IMM(RA1, 1);
			done = code;
			BCOND(EQ, 0);
			mem(Ldw, O(List, tail), RA1, RA1);
			ADD_IMM(RA0, RA0, 1);
			{
				long off = (long)(loop - code);
				B_IMM(off);
			}
			PATCH_BCOND(done);
		}
		opwst(i, Stw, RA0);
		break;

	case INOP:
		break;
	}
}

/*
 * preamble — comvec entry/exit trampoline (allocated once).
 */
static void
preamble(void)
{
	ulong sz;
	u32int *start, *xpc_loc, *epilogue;

	if(comvec)
		return;

	sz = 64 * sizeof(u32int);
#ifdef __APPLE__
	comvec = mmap(0, sz, PROT_READ|PROT_WRITE|PROT_EXEC,
			MAP_PRIVATE|MAP_ANON|MAP_JIT, -1, 0);
	if(comvec == MAP_FAILED) {
		comvec = nil;
		error(exNomem);
	}
	pthread_jit_write_protect_np(0);
#else
	comvec = mmap(0, sz, PROT_READ|PROT_WRITE|PROT_EXEC,
			MAP_PRIVATE|MAP_ANON, -1, 0);
	if(comvec == MAP_FAILED) {
		comvec = nil;
		error(exNomem);
	}
#endif

	code = (u32int*)comvec;
	start = code;

	/* Prologue: save callee-saved registers.
	 * Emit as raw encodings because SP (31) conflicts with XZR (31). */
	*code++ = 0xA9BD7BFD;	/* STP X29, X30, [SP, #-48]! */
	*code++ = 0x910003FD;	/* MOV X29, SP */
	*code++ = 0xA90157F4;	/* STP X20, X21, [SP, #16] */
	*code++ = 0xA9024FF6;	/* STP X22, X19, [SP, #32] */

	/* RREG = &R */
	con((uvlong)&R, RREG);

	/* R.xpc = epilogue (placeholder, patched below) */
	xpc_loc = code;
	con(0ULL, RTA);
	mem(Stw, O(REG, xpc), RREG, RTA);

	/* Load VM state */
	mem(Ldw, O(REG, FP), RREG, RFP);
	mem(Ldw, O(REG, MP), RREG, RMP);
	mem(Ldw, O(REG, PC), RREG, RTA);
	BR_REG(RTA);

	/* Epilogue */
	epilogue = code;
	*code++ = 0xA9424FF6;	/* LDP X22, X19, [SP, #32] */
	*code++ = 0xA94157F4;	/* LDP X20, X21, [SP, #16] */
	*code++ = 0xA8C37BFD;	/* LDP X29, X30, [SP], #48 */
	RET_X30();

	/* Patch epilogue address */
	{
		u32int *save = code;
		code = xpc_loc;
		con((uvlong)epilogue, RTA);
		code = save;
	}

#ifdef __APPLE__
	pthread_jit_write_protect_np(1);
	sys_icache_invalidate(start, sz);
#else
	segflush(start, sz);
#endif

	if(cflag > 3) {
		int k;
		print("preamble at %.8p (%ld words):\n", start, (long)(code - start));
		for(k = 0; k < code - start; k++)
			print("  %.8p  %.8ux\n", &start[k], start[k]);
	}
}

/*
 * Macro implementations.
 */
static void
macfrp(void)
{
	u32int *nilcheck, *notzero;

	CMN_IMM(RA0, 1);
	nilcheck = code;
	BCOND(EQ, 0);

	mem(Ldw, O(Heap, ref) - sizeof(Heap), RA0, RA2);
	SUB_IMM(RA2, RA2, 1);
	mem(Stw, O(Heap, ref) - sizeof(Heap), RA0, RA2);
	notzero = code;
	BCOND(NE, 0);

	/* ref == 0: save state, call rdestroy */
	mem(Stw, O(REG, FP), RREG, RFP);
	mem(Stw, O(REG, s), RREG, RA0);
	mem(Stw, O(REG, st), RREG, 30);
	con((uvlong)rdestroy, RTA);
	BLR_REG(RTA);
	con((uvlong)&R, RREG);
	mem(Ldw, O(REG, st), RREG, 30);
	mem(Ldw, O(REG, FP), RREG, RFP);
	mem(Ldw, O(REG, MP), RREG, RMP);

	PATCH_BCOND(nilcheck);
	PATCH_BCOND(notzero);
	RET_X30();
}

static void
maccolr(void)
{
	u32int *done;

	mem(Ldw, O(Heap, ref) - sizeof(Heap), RA1, RA0);
	ADD_IMM(RA0, RA0, 1);
	mem(Stw, O(Heap, ref) - sizeof(Heap), RA1, RA0);

	mem(Ldw32, O(Heap, color) - sizeof(Heap), RA1, RA0);
	con((uvlong)&mutator, RA2);
	mem(Ldw32, 0, RA2, RA2);
	CMP_REG(RA0, RA2);
	done = code;
	BCOND(EQ, 0);

	con(propagator, RA2);
	mem(Stw32, O(Heap, color) - sizeof(Heap), RA1, RA2);
	con((uvlong)&nprop, RA2);
	con(1, RA0);
	mem(Stw32, 0, RA2, RA0);

	PATCH_BCOND(done);
	RET_X30();
}

static void
macret(void)
{
	u32int *notypelab, *nodestroylab, *nofplab, *nomrlab, *noreflab;
	u32int *linterp;
	Inst dummy;

	CBZ_X(RA1, 0);
	notypelab = code - 1;

	mem(Ldw, O(Type, destroy), RA1, RA0);
	CBZ_X(RA0, 0);
	nodestroylab = code - 1;

	mem(Ldw, O(Frame, fp), RFP, RA2);
	CBZ_X(RA2, 0);
	nofplab = code - 1;

	mem(Ldw, O(Frame, mr), RFP, RA3);
	CBZ_X(RA3, 0);
	nomrlab = code - 1;

	mem(Ldw, O(REG, M), RREG, RA2);
	mem(Ldw, O(Heap, ref) - sizeof(Heap), RA2, RA3);
	SUB_IMM(RA3, RA3, 1);
	CBZ_X(RA3, 0);
	noreflab = code - 1;
	mem(Stw, O(Heap, ref) - sizeof(Heap), RA2, RA3);

	mem(Ldw, O(Frame, mr), RFP, RA1);
	mem(Stw, O(REG, M), RREG, RA1);
	mem(Ldw, O(Modlink, MP), RA1, RMP);
	mem(Stw, O(REG, MP), RREG, RMP);
	mem(Ldw32, O(Modlink, compiled), RA1, RA3);
	CBZ_X(RA3, 0);
	linterp = code - 1;

	/* Compiled: call destroy, jump to lr */
	BLR_REG(RA0);
	mem(Stw, O(REG, SP), RREG, RFP);
	mem(Ldw, O(Frame, lr), RFP, RA1);
	mem(Ldw, O(Frame, fp), RFP, RFP);
	mem(Stw, O(REG, FP), RREG, RFP);
	BR_REG(RA1);

	/* Not compiled: return to interpreter */
	PATCH_BCOND(linterp);
	BLR_REG(RA0);
	mem(Stw, O(REG, SP), RREG, RFP);
	mem(Ldw, O(Frame, lr), RFP, RA1);
	mem(Ldw, O(Frame, fp), RFP, RFP);
	mem(Stw, O(REG, PC), RREG, RA1);
	mem(Stw, O(REG, FP), RREG, RFP);
	mem(Ldw, O(REG, xpc), RREG, RTA);
	BR_REG(RTA);

	/* Punt fallback */
	PATCH_BCOND(notypelab);
	PATCH_BCOND(nodestroylab);
	PATCH_BCOND(nofplab);
	PATCH_BCOND(nomrlab);
	PATCH_BCOND(noreflab);
	dummy.add = AXNON;
	punt(&dummy, TCHECK|NEWPC, optab[IRET]);
}

static void
maccase(void)
{
	u32int *out, *notlt, *notfound;

	mem(Ldw, 0, RA3, RA2);		/* count */
	MOV_REG(6, RA3);		/* save initial table in X6 */

	u32int *loop = code;
	CMP_IMM(RA2, 0);
	out = code;
	BCOND(LE, 0);

	con(1, RTA);
	LSRV_REG(RA0, RA2, RTA);	/* n2 = n >> 1 */
	con(3 * IBY2WD, RTA);
	MUL_REG(RCON, RA0, RTA);
	ADD_REG(RCON, RA3, RCON);	/* pivot = table + n2*3*IBY2WD */

	mem(Ldw, IBY2WD, RCON, RTA);
	CMP_REG(RA1, RTA);
	notlt = code;
	BCOND(GE, 0);
	MOV_REG(RA2, RA0);		/* n = n2 */
	{
		long off = (long)(loop - code);
		B_IMM(off);
	}

	PATCH_BCOND(notlt);
	mem(Ldw, 2 * IBY2WD, RCON, RTA);
	CMP_REG(RA1, RTA);
	notfound = code;
	BCOND(GE, 0);
	mem(Ldw, 3 * IBY2WD, RCON, RTA);
	BR_REG(RTA);			/* found! */

	PATCH_BCOND(notfound);
	ADD_IMM(RA3, RCON, 3 * IBY2WD);
	ADD_IMM(RA0, RA0, 1);
	SUB_REG(RA2, RA2, RA0);
	{
		long off = (long)(loop - code);
		B_IMM(off);
	}

	/* Default */
	PATCH_BCOND(out);
	mem(Ldw, 0, 6, RA2);
	con(3 * IBY2WD, RTA);
	MUL_REG(RA2, RA2, RTA);
	ADD_REG(6, 6, RA2);
	mem(Ldw, IBY2WD, 6, RTA);
	BR_REG(RTA);
}

static void
macmcal(void)
{
	u32int *notnil, *hasprog;

	CMN_IMM(RA0, 1);
	notnil = code;
	BCOND(NE, 0);

	/* RA0 == H: punt to rmcall */
	mem(Stw, O(REG, st), RREG, 30);
	mem(Stw, O(REG, FP), RREG, RA2);
	mem(Stw, O(REG, dt), RREG, RA0);
	con((uvlong)rmcall, RTA);
	BLR_REG(RTA);
	con((uvlong)&R, RREG);
	mem(Ldw, O(REG, st), RREG, 30);
	mem(Ldw, O(REG, FP), RREG, RFP);
	mem(Ldw, O(REG, MP), RREG, RMP);
	RET_X30();

	PATCH_BCOND(notnil);
	mem(Ldw, O(Modlink, prog), RA3, RA1);
	CBNZ_X(RA1, 0);
	hasprog = code - 1;

	/* prog == nil: same punt */
	mem(Stw, O(REG, st), RREG, 30);
	mem(Stw, O(REG, FP), RREG, RA2);
	mem(Stw, O(REG, dt), RREG, RA0);
	con((uvlong)rmcall, RTA);
	BLR_REG(RTA);
	con((uvlong)&R, RREG);
	mem(Ldw, O(REG, st), RREG, 30);
	mem(Ldw, O(REG, FP), RREG, RFP);
	mem(Ldw, O(REG, MP), RREG, RMP);
	RET_X30();

	PATCH_BCOND(hasprog);
	MOV_REG(RFP, RA2);
	mem(Stw, O(REG, M), RREG, RA3);
	mem(Ldw, O(Heap, ref) - sizeof(Heap), RA3, RA1);
	ADD_IMM(RA1, RA1, 1);
	mem(Stw, O(Heap, ref) - sizeof(Heap), RA3, RA1);
	mem(Ldw, O(Modlink, MP), RA3, RMP);
	mem(Stw, O(REG, MP), RREG, RMP);
	mem(Ldw32, O(Modlink, compiled), RA3, RA1);
	CBNZ_X(RA1, 5);	/* skip 4 insns (Stw FP, Stw PC, Ldw xpc, BR xpc) to compiled path */
	/* Not compiled */
	mem(Stw, O(REG, FP), RREG, RFP);
	mem(Stw, O(REG, PC), RREG, RA0);
	mem(Ldw, O(REG, xpc), RREG, RTA);
	BR_REG(RTA);
	/* Compiled */
	BR_REG(RA0);
}

static void
macfram(void)
{
	u32int *expand;

	mem(Ldw, O(REG, SP), RREG, RA0);
	mem(Ldw32, O(Type, size), RA3, RA1);
	ADD_REG(RA0, RA0, RA1);
	mem(Ldw, O(REG, TS), RREG, RA1);
	CMP_REG(RA0, RA1);
	expand = code;
	BCOND(HS, 0);

	mem(Ldw, O(REG, SP), RREG, RA2);
	mem(Stw, O(REG, SP), RREG, RA0);
	mem(Stw, O(Frame, t), RA2, RA3);
	MOV_REG(RA0, XZR);
	mem(Stw, O(Frame, mr), RA2, RA0);
	/* Save RA2 (frame ptr) and LR before calling initialize */
	mem(Stw, O(REG, dt), RREG, RA2);
	mem(Stw, O(REG, st), RREG, 30);
	mem(Ldw, O(Type, initialize), RA3, RTA);
	BLR_REG(RTA);
	mem(Ldw, O(REG, st), RREG, 30);
	mem(Ldw, O(REG, dt), RREG, RA2);
	RET_X30();

	PATCH_BCOND(expand);
	mem(Stw, O(REG, s), RREG, RA3);
	mem(Stw, O(REG, FP), RREG, RFP);
	mem(Stw, O(REG, st), RREG, 30);
	con((uvlong)extend, RTA);
	BLR_REG(RTA);
	con((uvlong)&R, RREG);
	mem(Ldw, O(REG, st), RREG, 30);
	mem(Ldw, O(REG, FP), RREG, RFP);
	mem(Ldw, O(REG, s), RREG, RA2);
	mem(Ldw, O(REG, MP), RREG, RMP);
	RET_X30();
}

static void
macmfra(void)
{
	mem(Stw, O(REG, s), RREG, RA3);
	mem(Stw, O(REG, d), RREG, RA0);
	mem(Stw, O(REG, FP), RREG, RFP);
	mem(Stw, O(REG, st), RREG, 30);
	con((uvlong)rmfram, RTA);
	BLR_REG(RTA);
	con((uvlong)&R, RREG);
	mem(Ldw, O(REG, st), RREG, 30);
	mem(Ldw, O(REG, FP), RREG, RFP);
	mem(Ldw, O(REG, MP), RREG, RMP);
	RET_X30();
}

static void
macrelq(void)
{
	/* Save LR (set by BL in schedcheck) as R.PC.
	 * On re-entry after reschedule, comvec jumps to R.PC,
	 * which is the comparison code — not past the branch.
	 */
	mem(Stw, O(REG, PC), RREG, 30);	/* R.PC = LR (X30) */
	mem(Stw, O(REG, MP), RREG, RMP);
	mem(Ldw, O(REG, xpc), RREG, RTA);
	BR_REG(RTA);
}

static void
macbounds(void)
{
	con((uvlong)bounds, RTA);
	BLR_REG(RTA);
}

/*
 * comi / comd — type initializer and destroyer.
 */
void
comi(Type *t)
{
	int i, j, m, c;

	con((uvlong)H, RA0);
	for(i = 0; i < t->np; i++) {
		c = t->map[i];
		j = i * 8 * (int)sizeof(WORD*);
		for(m = 0x80; m != 0; m >>= 1) {
			if(c & m)
				mem(Stw, j, RA2, RA0);
			j += sizeof(WORD*);
		}
	}
	RET_X30();
}

void
comd(Type *t)
{
	int i, j, m, c;
	uvlong macfrp_addr;

	/*
	 * Use absolute addressing (con + BLR) instead of relative BL
	 * for calling MacFRP.  typecom() allocates a separate mmap buffer
	 * which can be >128MB from the module's code buffer, exceeding
	 * the ARM64 BL instruction's ±128MB PC-relative range.
	 */
	macfrp_addr = (uvlong)IA(macro, MacFRP);

	mem(Stw, O(REG, dt), RREG, 30);
	for(i = 0; i < t->np; i++) {
		c = t->map[i];
		j = i * 8 * (int)sizeof(WORD*);
		for(m = 0x80; m != 0; m >>= 1) {
			if(c & m) {
				mem(Ldw, j, RFP, RA0);
				con(macfrp_addr, RTA);
				BLR_REG(RTA);
			}
			j += sizeof(WORD*);
		}
	}
	mem(Ldw, O(REG, dt), RREG, 30);
	RET_X30();
}

void
typecom(Type *t)
{
	int n;
	u32int *tmp, *start;
	ulong sz;

	if(t == nil || t->initialize != 0)
		return;

	tmp = mallocz(4096 * sizeof(u32int), 0);
	if(tmp == nil)
		error(exNomem);

	code = tmp;
	comi(t);
	n = code - tmp;
	code = tmp;
	comd(t);
	n += code - tmp;
	free(tmp);

	sz = n * sizeof(u32int);

#ifdef __APPLE__
	start = mmap(0, sz, PROT_READ|PROT_WRITE|PROT_EXEC,
			MAP_PRIVATE|MAP_ANON|MAP_JIT, -1, 0);
	if(start == MAP_FAILED)
		return;
	pthread_jit_write_protect_np(0);
#else
	start = mallocz(sz, 0);
	if(start == nil)
		return;
#endif

	code = start;
	t->initialize = code;
	comi(t);
	t->destroy = code;
	comd(t);

#ifdef __APPLE__
	pthread_jit_write_protect_np(1);
	sys_icache_invalidate(start, sz);
#else
	segflush(start, sz);
#endif

	if(cflag > 3)
		print("typ= %.8p %4d i %.8p d %.8p asm=%lud\n",
			t, t->size, t->initialize, t->destroy, sz);
}

static void
patchex(Module *m, ulong *p)
{
	Handler *h;
	Except *e;

	if((h = m->htab) == nil)
		return;
	for( ; h->etab != nil; h++) {
		h->pc1 = p[h->pc1] * sizeof(u32int);
		h->pc2 = p[h->pc2] * sizeof(u32int);
		for(e = h->etab; e->s != nil; e++)
			e->pc = p[e->pc] * sizeof(u32int);
		if(e->pc != (ulong)-1)
			e->pc = p[e->pc] * sizeof(u32int);
	}
}

int
compile(Module *m, int size, Modlink *ml)
{
	Link *l;
	Modl *e;
	int i, n;
	u32int *s, *tmp;

	/* JIT enabled */
	ulong codesize;

	base = nil;
	patch = mallocz((size + 1) * sizeof(*patch), 0);
	tinit = malloc(m->ntype * sizeof(*tinit));
	tmp = malloc(4096 * sizeof(u32int));
	if(tinit == nil || patch == nil || tmp == nil)
		goto bad;

	preamble();

	mod = m;
	n = 0;
	pass = 0;
	nlit = 0;

	if(cflag > 3) {
		print("compile: entry=%.8p prog=%.8p idx=%ld size=%d\n",
			m->entry, m->prog, (long)(m->entry - m->prog), size);
		print("  &m->entry=%.8p &m->ext[0].u.pc=%.8p\n",
			&m->entry, &m->ext[0].u.pc);
	}

	for(i = 0; i < size; i++) {
		codeoff = n;
		code = tmp;
		comp(&m->prog[i]);
		patch[i] = n;
		n += code - tmp;
	}
	patch[size] = n;	/* sentinel: one past last Dis instruction */

	/* BRK trap: catch fall-through from last instruction into macros */
	n++;

	for(i = 0; i < nelem(mactab); i++) {
		codeoff = n;
		code = tmp;
		mactab[i].gen();
		macro[mactab[i].idx] = n;
		n += code - tmp;
	}

	codesize = n * sizeof(u32int) + nlit * sizeof(ulong);

#ifdef __APPLE__
	base = mmap(0, codesize, PROT_READ|PROT_WRITE|PROT_EXEC,
			MAP_PRIVATE|MAP_ANON|MAP_JIT, -1, 0);
	if(base == MAP_FAILED) {
		base = nil;
		goto bad;
	}
	pthread_jit_write_protect_np(0);
#else
	base = mallocz(codesize, 0);
	if(base == nil)
		goto bad;
#endif

	{
		static int ncompiled;
		ncompiled++;
		if(cflag > 1)
			print("[%d] dis=%5d arm64=%5d mmap=%5lud base=%.8p end=%.8p: %s\n",
				ncompiled, size, n, (ulong)codesize,
				(void*)base, (void*)(base + n), m->name);
	}

	pass = 1;
	nlit = 0;
	litpool = (ulong*)(base + n);
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
			das(s, code - s);
		}
	}

	/* BRK trap: catch fall-through from last instruction into macros */
	*code++ = 0xd4200000;	/* BRK #0 */
	n++;
	if(cflag > 4)
		print("TRAP:\n");

	for(i = 0; i < nelem(mactab); i++) {
		s = code;
		mactab[i].gen();
		if(macro[mactab[i].idx] != n) {
			print("mac phase err: %lud != %d\n", macro[mactab[i].idx], n);
			urk("phase error");
		}
		n += code - s;
		if(cflag > 4) {
			print("%s:\n", mactab[i].name);
			das(s, code - s);
		}
	}

	if(cflag > 3)
		print("A: mod->entry=%.8p\n", mod->entry);
	for(l = m->ext; l->name; l++) {
		l->u.pc = (Inst*)RELPC(patch[l->u.pc - m->prog]);
		typecom(l->frame);
	}
	if(cflag > 3)
		print("B: mod->entry=%.8p\n", mod->entry);
	if(ml != nil) {
		e = &ml->links[0];
		for(i = 0; i < ml->nlinks; i++) {
			e->u.pc = (Inst*)RELPC(patch[e->u.pc - m->prog]);
			typecom(e->frame);
			e++;
		}
	}
	if(cflag > 3)
		print("C: mod->entry=%.8p\n", mod->entry);
	for(i = 0; i < m->ntype; i++) {
		if(tinit[i] != 0)
			typecom(m->type[i]);
	}
	if(cflag > 3)
		print("D: mod->entry=%.8p\n", mod->entry);

	patchex(m, patch);

	if(cflag > 3)
		print("E: mod->entry=%.8p\n", mod->entry);
	{
		long eidx = mod->entry - mod->prog;
		if(cflag > 3)
			print("setting entry: eidx=%ld RELPC=%.8p\n",
				eidx, (void*)RELPC(patch[eidx]));
		m->entry = (Inst*)RELPC(patch[eidx]);
	}
	m->pctab = patch;

#ifdef __APPLE__
	pthread_jit_write_protect_np(1);
	sys_icache_invalidate(base, codesize);
#else
	segflush(base, codesize);
#endif

	if(cflag > 3) {
		long eidx;
		print("code at %.8p: %.8ux %.8ux %.8ux %.8ux\n",
			base, base[0], base[1], base[2], base[3]);
		print("before entry: mod->entry=%.8p mod->prog=%.8p\n",
			mod->entry, mod->prog);
		eidx = mod->entry - mod->prog;
		print("entry idx=%ld patch[0]=%lud\n", eidx, patch[0]);
	}

	free(m->prog);
	m->prog = (Inst*)base;
	m->compiled = 1;
	free(tinit);
	free(tmp);
	return 1;
bad:
	free(patch);
	free(tinit);
	free(tmp);
	return 0;
}
