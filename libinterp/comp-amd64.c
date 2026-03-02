/*
 * AMD64 (x86-64) JIT compiler for Dis Virtual Machine
 *
 * Based on comp-386.c but adapted for 64-bit AMD64.
 * Key differences from x86 (comp-386.c):
 *   - 64-bit registers (RAX, RBX, etc.)
 *   - REX prefixes for 64-bit operations
 *   - sizeof(WORD) = 8, sizeof(Modl) = 16
 *   - System V AMD64 ABI calling convention
 *   - RIP-relative addressing available
 */

#include "lib9.h"
#include "isa.h"
#include "interp.h"
#include "raise.h"

#include <sys/mman.h>
#ifdef __APPLE__
#include <pthread.h>
#include <libkern/OSCacheControl.h>
#endif

/*
 * Allocate executable memory within 2GB of the text segment on Linux.
 * This is needed because AMD64 JIT uses rel32 branches to C functions.
 * Tries mmap with hint addresses at decreasing distances from compile().
 */
#ifndef __APPLE__
static void*
jitmalloc(size_t size)
{
	void *p;
	uvlong base_addr = (uvlong)compile & ~0xFFFULL;
	uvlong try;
	int i;

	/* Try addresses below the text segment first, then above */
	for(i = 1; i < 1024; i++) {
		try = base_addr - (uvlong)i * 0x10000ULL;
		if(try < 0x10000ULL)
			break;
		p = mmap((void*)try, size,
		         PROT_READ|PROT_WRITE|PROT_EXEC,
		         MAP_PRIVATE|MAP_ANON, -1, 0);
		if(p != MAP_FAILED) {
			vlong diff = (vlong)((uvlong)p - base_addr);
			if(diff < 0) diff = -diff;
			if(diff < 0x70000000LL)  /* within ~1.75 GB */
				return p;
			munmap(p, size);
		}
	}
	for(i = 1; i < 1024; i++) {
		try = base_addr + (uvlong)i * 0x10000ULL;
		p = mmap((void*)try, size,
		         PROT_READ|PROT_WRITE|PROT_EXEC,
		         MAP_PRIVATE|MAP_ANON, -1, 0);
		if(p != MAP_FAILED) {
			vlong diff = (vlong)((uvlong)p - base_addr);
			if(diff < 0) diff = -diff;
			if(diff < 0x70000000LL)
				return p;
			munmap(p, size);
		}
	}
	return MAP_FAILED;
}
#endif

#define DOT			((uvlong)code)

#define	RESCHED 1	/* check for interpreter reschedule */

enum
{
	/* 64-bit registers */
	RAX	= 0,
	RCX	= 1,
	RDX	= 2,
	RBX	= 3,
	RSP	= 4,
	RBP	= 5,
	RSI	= 6,
	RDI	= 7,
	R8	= 8,
	R9	= 9,
	R10	= 10,
	R11	= 11,
	R12	= 12,
	R13	= 13,
	R14	= 14,
	R15	= 15,

	/* Legacy names */
	RAH	= 4,	/* Can't access AH with REX prefix */

	/*
	 * VM Register allocation
	 * Using callee-saved registers for VM state
	 */
	RLINK	= R14,	/* Pointer to REG (&R) - callee saved */
	RRTMP	= R15,	/* Temp register - callee saved */
	RRFP	= RBX,	/* Dis Frame Pointer - callee saved */
	RRMP	= R12,	/* Module Pointer - callee saved */
	RRTA	= R10,	/* Temp address - caller saved but we manage it */
	RRTMP2	= R11,	/* Additional temp */

	/* x86-64 opcodes */
	Omovzxb	= 0xb6,
	Omovzxw	= 0xb7,
	Omovsxb	= 0xbe,
	Omovsxw	= 0xbf,
	Omovsxd	= 0x63,	/* MOVSXD - sign extend 32 to 64 */
	Osal	= 0xd1,
	Oaddf	= 0xdc,
	Ocall	= 0xe8,
	Ocallrm	= 0xff,
	Ocqo	= 0x99,		/* Sign extend RAX to RDX:RAX */
	Ocdq	= 0x99,		/* Same opcode, different mode */
	Ocld	= 0xfc,
	Ocmpb	= 0x38,
	Ocmpw	= 0x39,
	Ocmpi	= 0x83,
	Ocmpi32	= 0x81,
	Odecrm	= 0xff,
	Oincrm	= 0xff,
	Ojccl	= 0x83,
	Ojcsl	= 0x82,
	Ojeqb	= 0x74,
	Ojeql	= 0x84,
	Ojgel	= 0x8d,
	Ojgtl	= 0x8f,
	Ojhil	= 0x87,
	Ojlel	= 0x8e,
	Ojlsl	= 0x86,
	Ojltl	= 0x8c,
	Ojol	= 0x80,
	Ojnol	= 0x81,
	Ojbl	= 0x82,
	Ojael	= 0x83,
	Ojal	= 0x87,
	Ojnel	= 0x85,
	Ojbel	= 0x86,
	Ojneb	= 0x75,
	Ojgtb	= 0x7f,
	Ojgeb	= 0x7d,
	Ojleb	= 0x7e,
	Ojltb	= 0x7c,
	Ojmp	= 0xe9,
	Ojmpb	= 0xeb,
	Ojmprm	= 0xff,
	Oldb	= 0x8a,
	Olds	= 0x89,
	Oldw	= 0x8b,
	Olea	= 0x8d,
	Otestib	= 0xf6,
	Oshld	= 0xa5,
	Oshrd	= 0xad,
	Osar	= 0xd3,
	Osarimm = 0xc1,
	Omov	= 0xc7,
	Omovf	= 0xdd,
	Omovimm	= 0xb8,
	Omovimm64 = 0xb8,	/* With REX.W */
	Omovsb	= 0xa4,
	Orep	= 0xf3,
	Oret	= 0xc3,
	Oshl	= 0xd3,
	Oshr	= 0xd1,
	Ostb	= 0x88,
	Ostw	= 0x89,
	Osubf	= 0xdc,
	Oxchg	= 0x87,
	OxchgAX	= 0x90,
	Oxor	= 0x31,
	Opopq	= 0x58,
	Opushq	= 0x50,
	Opushrm	= 0xff,
	Oneg	= 0xf7,

	/* REX prefixes */
	REX	= 0x40,
	REXW	= 0x48,		/* 64-bit operand size */
	REXR	= 0x44,		/* ModRM reg field extension */
	REXX	= 0x42,		/* SIB index field extension */
	REXB	= 0x41,		/* ModRM r/m, SIB base, opcode reg extension */

	/* Operation flags */
	SRCOP	= (1<<0),
	DSTOP	= (1<<1),
	WRTPC	= (1<<2),
	TCHECK	= (1<<3),
	NEWPC	= (1<<4),
	DBRAN	= (1<<5),
	THREOP	= (1<<6),

	/* Branch combination modes */
	ANDAND	= 1,
	OROR	= 2,
	EQAND	= 3,

	/* Macro indices */
	MacFRP	= 0,
	MacRET	= 1,
	MacCASE	= 2,
	MacCOLR	= 3,
	MacMCAL	= 4,
	MacFRAM	= 5,
	MacMFRA	= 6,
	MacRELQ = 7,
	NMACRO
};

static	uchar*	code;
static	uchar*	base;
static	uvlong*	patch;
static	int	pass;
static	Module*	mod;
static	uchar*	tinit;
static	uvlong*	litpool;
static	int	nlit;
static	void	macfrp(void);
static	void	macret(void);
static	void	maccase(void);
static	void	maccolr(void);
static	void	macmcal(void);
static	void	macfram(void);
static	void	macmfra(void);
static	void	macrelq(void);
static	void	cmpl64(int, uvlong);
static	void	bra(uvlong, int);
static	uvlong	macro[NMACRO];
	void	(*comvec)(void);
extern	void	das(uchar*, int);

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
	MacRELQ,	macrelq,	/* reschedule */
};

/*
 * Helper functions
 */
static void
bounds(void)
{
	error(exBounds);
}

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

/*
 * Check if displacement fits in signed byte
 */
static int
bc(vlong o)
{
	if(o < 127 && o > -128)
		return 1;
	return 0;
}

/*
 * Check if value fits in signed 32-bit
 */
static int
is32(vlong v)
{
	return v == (int)v;
}

static void
urk(void)
{
	error(exCompile);
}

/*
 * Code generation helpers
 */
static void
genb(uchar o)
{
	*code++ = o;
}

static void
gen2(uchar o1, uchar o2)
{
	code[0] = o1;
	code[1] = o2;
	code += 2;
}

static void
gen3(uchar o1, uchar o2, uchar o3)
{
	code[0] = o1;
	code[1] = o2;
	code[2] = o3;
	code += 3;
}

static void
genw(ulong o)
{
	*(u32int*)code = (u32int)o;
	code += 4;
}

static void
genq(uvlong o)
{
	*(uvlong*)code = o;
	code += 8;
}

/*
 * Generate REX prefix for 64-bit operation
 * w = 1 for 64-bit operand, r = high bit of reg, b = high bit of rm/base
 */
static void
rex(int w, int r, int x, int b)
{
	int prefix = REX;
	if(w) prefix |= 0x08;
	if(r) prefix |= 0x04;
	if(x) prefix |= 0x02;
	if(b) prefix |= 0x01;
	if(prefix != REX || w)
		genb(prefix);
}

/*
 * Generate mod/rm byte with displacement
 * For 64-bit, we need REX prefix for extended registers
 */
static void
modrm(int inst, vlong disp, int rm, int r)
{
	int rex_prefix = REXW;	/* Default to 64-bit operand */
	int rmlo = rm & 7;
	int rlo = r & 7;

	/* Handle extended registers R8-R15 */
	if(rm >= R8)
		rex_prefix |= REXB;
	if(r >= R8)
		rex_prefix |= REXR;

	genb(rex_prefix);
	genb(inst);

	if(disp == 0 && rmlo != RBP) {
		if(rmlo == RSP) {
			/* Need SIB byte */
			genb((0<<6)|(rlo<<3)|RSP);
			genb((0<<6)|(RSP<<3)|RSP);
		} else {
			genb((0<<6)|(rlo<<3)|rmlo);
		}
		return;
	}
	if(bc(disp)) {
		if(rmlo == RSP) {
			genb((1<<6)|(rlo<<3)|RSP);
			genb((0<<6)|(RSP<<3)|RSP);
		} else {
			genb((1<<6)|(rlo<<3)|rmlo);
		}
		genb(disp);
		return;
	}
	if(rmlo == RSP) {
		genb((2<<6)|(rlo<<3)|RSP);
		genb((0<<6)|(RSP<<3)|RSP);
	} else {
		genb((2<<6)|(rlo<<3)|rmlo);
	}
	genw(disp);
}

/*
 * ModRM for 32-bit operations (no REX.W)
 */
static void
modrm32(int inst, vlong disp, int rm, int r)
{
	int rex_prefix = 0;
	int rmlo = rm & 7;
	int rlo = r & 7;

	/* Handle extended registers R8-R15 */
	if(rm >= R8)
		rex_prefix |= REXB;
	if(r >= R8)
		rex_prefix |= REXR;

	if(rex_prefix)
		genb(REX | rex_prefix);

	genb(inst);

	if(disp == 0 && rmlo != RBP) {
		if(rmlo == RSP) {
			genb((0<<6)|(rlo<<3)|RSP);
			genb((0<<6)|(RSP<<3)|RSP);
		} else {
			genb((0<<6)|(rlo<<3)|rmlo);
		}
		return;
	}
	if(bc(disp)) {
		if(rmlo == RSP) {
			genb((1<<6)|(rlo<<3)|RSP);
			genb((0<<6)|(RSP<<3)|RSP);
		} else {
			genb((1<<6)|(rlo<<3)|rmlo);
		}
		genb(disp);
		return;
	}
	if(rmlo == RSP) {
		genb((2<<6)|(rlo<<3)|RSP);
		genb((0<<6)|(RSP<<3)|RSP);
	} else {
		genb((2<<6)|(rlo<<3)|rmlo);
	}
	genw(disp);
}

/*
 * Register-register ModRM (mod=3)
 */
static void
modrr(int inst, int rm, int r)
{
	int rex_prefix = REXW;
	int rmlo = rm & 7;
	int rlo = r & 7;

	if(rm >= R8)
		rex_prefix |= REXB;
	if(r >= R8)
		rex_prefix |= REXR;

	genb(rex_prefix);
	genb(inst);
	genb((3<<6)|(rlo<<3)|rmlo);
}

/*
 * Register-register for 32-bit operations
 */
static void
modrr32(int inst, int rm, int r)
{
	int rex_prefix = 0;
	int rmlo = rm & 7;
	int rlo = r & 7;

	if(rm >= R8)
		rex_prefix |= REXB;
	if(r >= R8)
		rex_prefix |= REXR;

	if(rex_prefix)
		genb(REX | rex_prefix);

	genb(inst);
	genb((3<<6)|(rlo<<3)|rmlo);
}

/*
 * Load 64-bit constant into register
 */
static void
con64(uvlong o, int r)
{
	int rlo = r & 7;

	if(o == 0) {
		/* XOR r, r - shorter encoding */
		modrr32(Oxor, r, r);
		return;
	}
	if(o <= 0xFFFFFFFF) {
		/* 32-bit move with zero-extend (no REX.W) */
		if(r >= R8)
			genb(REX | REXB);
		genb(Omovimm + rlo);
		genw(o);
		return;
	}
	/* Full 64-bit immediate */
	if(r >= R8)
		genb(REXW | REXB);
	else
		genb(REXW);
	genb(Omovimm + rlo);
	genq(o);
}

/*
 * Load 32-bit constant into register
 */
static void
con32(ulong o, int r)
{
	int rlo = r & 7;

	if(o == 0) {
		modrr32(Oxor, r, r);
		return;
	}
	if(r >= R8)
		genb(REX | REXB);
	genb(Omovimm + rlo);
	genw(o);
}

/*
 * Load operand from source addressing mode
 */
static void
opwld(Inst *i, int mi, int r)
{
	int ir;

	switch(UXSRC(i->add)) {
	default:
		print("%D\n", i);
		urk();
	case SRC(AFP):
		modrm(mi, i->s.ind, RRFP, r);
		return;
	case SRC(AMP):
		modrm(mi, i->s.ind, RRMP, r);
		return;
	case SRC(AIMM):
		con64((uvlong)(vlong)i->s.imm, r);
		return;
	case SRC(AIND|AFP):
		ir = RRFP;
		break;
	case SRC(AIND|AMP):
		ir = RRMP;
		break;
	}
	modrm(Oldw, i->s.i.f, ir, RRTA);
	if(mi == Olea) {
		modrm(mi, i->s.i.s, RRTA, r);
	} else {
		modrm(mi, i->s.i.s, RRTA, r);
	}
}

/*
 * Store/load operand to/from destination addressing mode
 */
static void
opwst(Inst *i, int mi, int r)
{
	int ir;

	switch(UXDST(i->add)) {
	default:
		print("%D\n", i);
		urk();
	case DST(AIMM):
		con64((uvlong)(vlong)i->d.imm, r);
		return;
	case DST(AFP):
		modrm(mi, i->d.ind, RRFP, r);
		return;
	case DST(AMP):
		modrm(mi, i->d.ind, RRMP, r);
		return;
	case DST(AIND|AFP):
		ir = RRFP;
		break;
	case DST(AIND|AMP):
		ir = RRMP;
		break;
	}
	modrm(Oldw, i->d.i.f, ir, RRTA);
	modrm(mi, i->d.i.s, RRTA, r);
}

/*
 * Branch with 32-bit displacement
 */
static void
bra(uvlong dst, int op)
{
	vlong rel = dst - (DOT + 5);
	if(!is32(rel)) {
		print("branch too far: %llx\n", rel);
		urk();
	}
	genb(op);
	genw((ulong)rel);
}

/*
 * Relative branch to patch address (within JIT buffer).
 * On pass 0, base is nil so we skip the range check (only sizes matter).
 */
static void
rbra(uvlong dst, int op)
{
	vlong rel;
	dst += (uvlong)base;
	rel = dst - (DOT + 5);
	if(pass && !is32(rel)) {
		print("rbra too far: %llx\n", rel);
		urk();
	}
	genb(op);
	genw((ulong)rel);
}

/*
 * Store literal in pool for later relocation
 */
static void
literal(uvlong imm, int roff)
{
	nlit++;

	/* Store address of literal pool entry */
	con64((uvlong)litpool, RAX);
	modrm(Ostw, roff, RLINK, RAX);

	if(pass == 0)
		return;

	*litpool = imm;
	litpool++;
}

/*
 * Generate conditional skip over bounds error block.
 * Emits: Jcc <skip> / save R.FP, R.PC / call bounds()
 * Uses backpatch for Jcc and fixed 10-byte MOVABS for R.PC
 * to ensure phase consistency between pass 0 and pass 1.
 *
 * R.PC is set to base+patch[i]+1 because handler() in
 * exception.c does pc-- after computing pc = R.PC - m->prog.
 * The +1 ensures pc-- lands at patch[i] (start of instruction i),
 * which falls within the handler's [pc1, pc2) range.
 */
static void
jnebounds(int cc, Inst *i)
{
	uchar *patch_loc;
	uvlong pc;

	gen2(cc, 0);			/* Jcc with placeholder rel8 */
	patch_loc = code - 1;
	modrm(Ostw, O(REG, FP), RLINK, RRFP);		/* 4 bytes */
	/* Always use 10-byte MOVABS for phase consistency */
	pc = (uvlong)base + patch[i - mod->prog] + 1;
	genb(REXW);
	genb(Omovimm + (RAX & 7));
	genq(pc);						/* 10 bytes total */
	modrm(Ostw, O(REG, PC), RLINK, RAX);		/* 3 bytes */
	bra((uvlong)bounds, Ocall);			/* 5 bytes */
	*patch_loc = code - (patch_loc + 1);		/* backpatch rel8 */
}

/*
 * Punt an operation to the interpreter
 */
static void
punt(Inst *i, int m, void (*fn)(void))
{
	uvlong pc;

	/* Save VM state to R structure */
	if(m & SRCOP) {
		if(UXSRC(i->add) == SRC(AIMM))
			literal((uvlong)(vlong)i->s.imm, O(REG, s));
		else {
			opwld(i, Olea, RAX);
			modrm(Ostw, O(REG, s), RLINK, RAX);
		}
	}

	if(m & DSTOP) {
		opwst(i, Olea, RAX);
		modrm(Ostw, O(REG, d), RLINK, RAX);
	}

	if(m & WRTPC) {
		pc = patch[i-mod->prog+1];
		con64((uvlong)base + pc, RAX);
		modrm(Ostw, O(REG, PC), RLINK, RAX);
	}

	if(m & DBRAN) {
		pc = patch[(Inst*)i->d.imm-mod->prog];
		literal((uvlong)base+pc, O(REG, d));
	}

	switch(i->add&ARM) {
	case AXNON:
		if(m & THREOP) {
			modrm(Oldw, O(REG, d), RLINK, RAX);
			modrm(Ostw, O(REG, m), RLINK, RAX);
		}
		break;
	case AXIMM:
		literal((uvlong)(vlong)(short)i->reg, O(REG, m));
		break;
	case AXINF:
		modrm(Olea, i->reg, RRFP, RAX);
		modrm(Ostw, O(REG, m), RLINK, RAX);
		break;
	case AXINM:
		modrm(Olea, i->reg, RRMP, RAX);
		modrm(Ostw, O(REG, m), RLINK, RAX);
		break;
	}
	modrm(Ostw, O(REG, FP), RLINK, RRFP);

	/* Align stack for C function call (RSP must be 0 mod 16 before CALL) */
	genb(Opushq+RAX);
	bra((uvlong)fn, Ocall);
	genb(Opopq+RCX);	/* restore stack alignment */

	if(m & TCHECK) {
		modrm(Ocmpi, O(REG, t), RLINK, 7);
		genb(0x00);
		gen2(Ojeqb, 0x08);	/* JEQ over exit: 2+2+2+1+1 = 8 bytes */
		/* Restore callee-saved and return */
		genb(REX|REXB); genb(Opopq+R15-R8);
		genb(REX|REXB); genb(Opopq+R14-R8);
		genb(REX|REXB); genb(Opopq+R12-R8);
		genb(Opopq+RBX);
		genb(Oret);
	}

	modrm(Oldw, O(REG, FP), RLINK, RRFP);
	modrm(Oldw, O(REG, MP), RLINK, RRMP);

	if(m & NEWPC) {
		modrm(Oldw, O(REG, PC), RLINK, RAX);
		/* JMP *RAX */
		genb(REXW);
		gen2(Ojmprm, (3<<6)|(4<<3)|RAX);
	}
}

/*
 * Load middle operand
 */
static void
mid(Inst *i, uchar mi, int r)
{
	int ir;

	switch(i->add&ARM) {
	default:
		opwst(i, mi, r);
		return;
	case AXIMM:
		con64((uvlong)(vlong)(short)i->reg, r);
		return;
	case AXINF:
		ir = RRFP;
		break;
	case AXINM:
		ir = RRMP;
		break;
	}
	modrm(mi, i->reg, ir, r);
}

/*
 * Arithmetic operations
 */
static void
arith(Inst *i, int op2, int rm)
{
	if(UXSRC(i->add) != SRC(AIMM)) {
		if(i->add&ARM) {
			mid(i, Oldw, RAX);
			opwld(i, op2|2, RAX);
			opwst(i, Ostw, RAX);
			return;
		}
		opwld(i, Oldw, RAX);
		opwst(i, op2, RAX);
		return;
	}
	/* Immediate source */
	if(i->add&ARM) {
		mid(i, Oldw, RAX);
		if(bc(i->s.imm)) {
			modrr(0x83, RAX, rm);
			genb(i->s.imm);
		} else {
			modrr(0x81, RAX, rm);
			genw(i->s.imm);
		}
		opwst(i, Ostw, RAX);
		return;
	}
	if(bc(i->s.imm)) {
		opwst(i, 0x83, rm);
		genb(i->s.imm);
		return;
	}
	opwst(i, 0x81, rm);
	genw(i->s.imm);
}

/*
 * Byte arithmetic
 */
static void
arithb(Inst *i, int op2)
{
	if(UXSRC(i->add) == SRC(AIMM))
		urk();

	if(i->add&ARM) {
		mid(i, Oldb, RAX);
		opwld(i, op2|2, RAX);
		opwst(i, Ostb, RAX);
		return;
	}
	opwld(i, Oldb, RAX);
	opwst(i, op2, RAX);
}

/*
 * Shift operations
 */
static void
shift(Inst *i, int ld, int st, int op, int r)
{
	mid(i, ld, RAX);
	opwld(i, Oldw, RCX);
	modrr(op, RAX, r);
	opwst(i, st, RAX);
}

/*
 * Compare and set flags for 64-bit
 */
static void
cmpl64(int r, uvlong v)
{
	if(bc(v)) {
		modrr(0x83, r, 7);
		genb(v);
		return;
	}
	if(is32(v)) {
		modrr(0x81, r, 7);
		genw(v);
		return;
	}
	/* Value doesn't fit in 32-bit immediate - load and compare */
	con64(v, RRTMP2);
	modrr(Ocmpw, r, RRTMP2);
}

static int
swapbraop(int b)
{
	switch(b) {
	case Ojgel:
		return Ojlel;
	case Ojlel:
		return Ojgel;
	case Ojgtl:
		return Ojltl;
	case Ojltl:
		return Ojgtl;
	}
	return b;
}

static void
schedcheck(Inst *i)
{
	if(RESCHED && i->d.ins <= i) {
		/* sub $1, R.IC */
		modrm(0x83, O(REG, IC), RLINK, 5);
		genb(1);
		gen2(Ojgtb, 5);
		rbra(macro[MacRELQ], Ocall);
	}
}

/*
 * Conditional branch for WORD
 */
static void
cbra(Inst *i, int jmp)
{
	if(RESCHED)
		schedcheck(i);
	mid(i, Oldw, RAX);
	if(UXSRC(i->add) == SRC(AIMM)) {
		cmpl64(RAX, (uvlong)(vlong)i->s.imm);
		jmp = swapbraop(jmp);
	} else {
		opwld(i, Ocmpw, RAX);
	}
	genb(0x0f);
	rbra(patch[i->d.ins-mod->prog], jmp);
}

/*
 * Conditional branch for BIG (64-bit)
 */
static void
cbral(Inst *i, int jmsw, int jlsw, int mode)
{
	uvlong dst;
	uchar *label;

	if(RESCHED)
		schedcheck(i);

	/* Load both operands */
	opwld(i, Olea, RRTMP);
	mid(i, Olea, RRTA);

	/* Compare high words first */
	modrm32(Oldw, 4, RRTA, RAX);
	modrm32(Ocmpw, 4, RRTMP, RAX);

	label = nil;
	dst = patch[i->d.ins-mod->prog];

	switch(mode) {
	case ANDAND:
		gen2(Ojneb, 0);
		label = code-1;
		break;
	case OROR:
		genb(0x0f);
		rbra(dst, jmsw);
		break;
	case EQAND:
		genb(0x0f);
		rbra(dst, jmsw);
		gen2(Ojneb, 0);
		label = code-1;
		break;
	}

	/* Compare low words */
	modrm32(Oldw, 0, RRTA, RAX);
	modrm32(Ocmpw, 0, RRTMP, RAX);
	genb(0x0f);
	rbra(dst, jlsw);

	if(label != nil)
		*label = code-label-1;
}

/*
 * Conditional branch for BYTE
 */
static void
cbrab(Inst *i, int jmp)
{
	if(RESCHED)
		schedcheck(i);
	mid(i, Oldb, RAX);
	if(UXSRC(i->add) == SRC(AIMM))
		urk();

	opwld(i, Ocmpb, RAX);
	genb(0x0f);
	rbra(patch[i->d.ins-mod->prog], jmp);
}

/*
 * Case dispatch
 */
static void
comcase(Inst *i, int w)
{
	int l;
	WORD *t, *e;

	if(w != 0) {
		opwld(i, Oldw, RAX);		/* v */
		genb(Opushq+RSI);
		/*
		 * Use origmp address directly for case table.
		 * comcase() patches JIT addresses into origmp, but
		 * newmp() may not propagate them to Modlink->MP.
		 * origmp is stable for the module's lifetime.
		 */
		con64((uvlong)(mod->origmp+i->d.ind), RSI);
		rbra(macro[MacCASE], Ojmp);
	}

	t = (WORD*)(mod->origmp+i->d.ind+sizeof(WORD));
	l = t[-1];

	if(pass == 0) {
		if(l >= 0)
			t[-1] = -l-1;
		return;
	}
	if(l >= 0)
		return;
	t[-1] = -l-1;
	e = t + t[-1]*3;
	while(t < e) {
		t[2] = (uvlong)base + patch[t[2]];
		t += 3;
	}
	t[0] = (uvlong)base + patch[t[0]];
}

static void
comcasel(Inst *i)
{
	int l;
	WORD *t, *e;

	t = (WORD*)(mod->origmp+i->d.ind+2*sizeof(WORD));
	l = t[-2];
	if(pass == 0) {
		if(l >= 0)
			t[-2] = -l-1;
		return;
	}
	if(l >= 0)
		return;
	t[-2] = -l-1;
	e = t + t[-2]*6;
	while(t < e) {
		t[4] = (uvlong)base + patch[t[4]];
		t += 6;
	}
	t[0] = (uvlong)base + patch[t[0]];
}

/*
 * Module frame setup
 */
static void
commframe(Inst *i)
{
	int o;
	uchar *punt_label, *mlnil;

	opwld(i, Oldw, RAX);
	cmpl64(RAX, (uvlong)H);
	gen2(Ojeqb, 0);
	mlnil = code - 1;

	if((i->add&ARM) == AXIMM) {
		/* sizeof(Modl) = 16 on 64-bit, so shift by 4 */
		o = OA(Modlink, links)+i->reg*sizeof(Modl)+O(Modl, frame);
		modrm(Oldw, o, RAX, RRTA);
	} else {
		modrr(Oldw, RAX, RRTMP);
		mid(i, Oldw, RCX);
		/* RAX = RAX + RCX * sizeof(Modl) where sizeof(Modl) = 16 */
		/* x86 SIB max scale is 8, so use two LEAs: base + idx*8 + idx*8 */
		genb(REXW);
		gen3(Olea, (0<<6)|(RAX<<3)|4, (3<<6)|(RCX<<3)|RAX);
		genb(REXW);
		gen3(Olea, (0<<6)|(RAX<<3)|4, (3<<6)|(RCX<<3)|RAX);
		o = OA(Modlink, links)+O(Modl, frame);
		modrm(Oldw, o, RAX, RRTA);
		modrr(Oxchg, RAX, RRTMP);
	}

	modrm32(Ocmpi, O(Type, initialize), RRTA, 7);
	genb(0);
	gen2(Ojneb, 0);
	punt_label = code - 1;

	modrr(Oxchg, RAX, RRTA);
	opwst(i, Olea, RRTA);
	*mlnil = code-mlnil-1;
	rbra(macro[MacMFRA], Ocall);
	rbra(patch[i-mod->prog+1], Ojmp);

	*punt_label = code-punt_label-1;
	rbra(macro[MacFRAM], Ocall);
	opwst(i, Ostw, RCX);
}

/*
 * Module call
 */
static void
commcall(Inst *i)
{
	uchar *mlnil;

	/* Load new frame pointer from source operand into RCX */
	opwld(i, Oldw, RCX);

	/* Store return address in Frame.lr */
	con64((uvlong)base+patch[i-mod->prog+1], RAX);
	modrm(Ostw, O(Frame, lr), RCX, RAX);
	modrm(Ostw, O(Frame, fp), RCX, RRFP);
	modrm(Oldw, O(REG, M), RLINK, RRTA);
	modrm(Ostw, O(Frame, mr), RCX, RRTA);

	opwst(i, Oldw, RRTA);
	cmpl64(RRTA, (uvlong)H);
	gen2(Ojeqb, 0);
	mlnil = code - 1;

	if((i->add&ARM) == AXIMM) {
		/* sizeof(Modl) = 16 */
		modrm(Oldw, OA(Modlink, links)+i->reg*sizeof(Modl)+O(Modl, u.pc), RRTA, RAX);
	} else {
		genb(Opushq+RCX);
		mid(i, Oldw, RCX);
		/* RAX = RRTA + RCX * sizeof(Modl) where sizeof(Modl) = 16 */
		/* x86 SIB max scale is 8, so use two LEAs: base + idx*8 + idx*8 */
		genb(REXW|REXB);	/* REXB for R10 base */
		gen3(Olea, (0<<6)|(RAX<<3)|4, (3<<6)|(RCX<<3)|(RRTA&7));
		genb(REXW);
		gen3(Olea, (0<<6)|(RAX<<3)|4, (3<<6)|(RCX<<3)|RAX);
		modrm(Oldw, OA(Modlink, links)+O(Modl, u.pc), RAX, RAX);
		genb(Opopq+RCX);
	}

	*mlnil = code-mlnil-1;
	rbra(macro[MacMCAL], Ocall);
}

/*
 * 64-bit arithmetic (BIG type)
 */
static void
larith(Inst *i, int op, int opc)
{
	opwld(i, Olea, RRTMP);
	mid(i, Olea, RRTA);
	modrm32(Oldw, 0, RRTA, RAX);
	modrm32(op, 0, RRTMP, RAX);
	modrm32(Oldw, 4, RRTA, RCX);
	modrm32(opc, 4, RRTMP, RCX);
	if((i->add&ARM) != AXNON)
		opwst(i, Olea, RRTA);
	modrm32(Ostw, 0, RRTA, RAX);
	modrm32(Ostw, 4, RRTA, RCX);
}

/*
 * Left shift BIG
 */
static void
shll(Inst *i)
{
	uchar *label, *label1;

	opwld(i, Oldw, RCX);
	mid(i, Olea, RRTA);
	gen2(Otestib, (3<<6)|(0<<3)|RCX);
	genb(0x20);
	gen2(Ojneb, 0);
	label = code-1;

	modrm32(Oldw, 0, RRTA, RAX);
	modrm32(Oldw, 4, RRTA, RDX);
	genb(0x0f);
	modrr32(Oshld, RDX, RAX);
	modrr32(Oshl, RAX, 4);
	gen2(Ojmpb, 0);
	label1 = code-1;

	*label = code-label-1;
	modrm32(Oldw, 0, RRTA, RDX);
	con32(0, RAX);
	modrr32(Oshl, RDX, 4);

	*label1 = code-label1-1;
	opwst(i, Olea, RRTA);
	modrm32(Ostw, 0, RRTA, RAX);
	modrm32(Ostw, 4, RRTA, RDX);
}

/*
 * Right shift BIG (arithmetic)
 */
static void
shrl(Inst *i)
{
	uchar *label, *label1;

	opwld(i, Oldw, RCX);
	mid(i, Olea, RRTA);
	gen2(Otestib, (3<<6)|(0<<3)|RCX);
	genb(0x20);
	gen2(Ojneb, 0);
	label = code-1;

	modrm32(Oldw, 0, RRTA, RAX);
	modrm32(Oldw, 4, RRTA, RDX);
	genb(0x0f);
	modrr32(Oshrd, RAX, RDX);
	modrr32(Osar, RDX, 7);
	gen2(Ojmpb, 0);
	label1 = code-1;

	*label = code-label-1;
	modrm32(Oldw, 4, RRTA, RDX);
	modrr32(Oldw, RDX, RAX);
	gen2(Osarimm, (3<<6)|(7<<3)|RDX);
	genb(0x1f);
	modrr32(Osar, RAX, 7);

	*label1 = code-label1-1;
	opwst(i, Olea, RRTA);
	modrm32(Ostw, 0, RRTA, RAX);
	modrm32(Ostw, 4, RRTA, RDX);
}

static void
compdbg(void)
{
	print("%s:%lud@%.16llux\n", R.M->m->name, *(ulong*)R.m, (uvlong)*(ulong*)R.s);
}

/*
 * Main instruction compiler
 */
static void
comp(Inst *i)
{
	int r;
	WORD *t, *e;
	char buf[64];

	if(0) {
		Inst xx;
		xx.add = AXIMM|SRC(AIMM);
		xx.s.imm = (uvlong)code;
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
		opwld(i, Oldb, RAX);
		genb(0x0f);
		modrr32(0xb6, RAX, RAX);
		opwst(i, Ostw, RAX);
		break;
	case ICVTWB:
		opwld(i, Oldw, RAX);
		opwst(i, Ostb, RAX);
		break;
	case ICVTFW:
	case ICVTWF:
	case ICVTLF:
	case ICVTFL:
		punt(i, SRCOP|DSTOP, optab[i->op]);
		break;
	case IHEADM:
		opwld(i, Oldw, RAX);
		modrm(Olea, OA(List, data), RAX, RAX);
		goto movm;
	case IMOVM:
		opwld(i, Olea, RAX);
	movm:
		opwst(i, Olea, RDI);
		mid(i, Oldw, RCX);
		/* Save RSI, use RAX as source */
		modrr(Oxchg, RAX, RSI);
		genb(Ocld);
		gen2(Orep, Omovsb);
		modrr(Oxchg, RAX, RSI);
		break;
	case IRET:
		rbra(macro[MacRET], Ojmp);
		break;
	case IFRAME:
		if(UXSRC(i->add) != SRC(AIMM)) {
			punt(i, SRCOP|DSTOP, optab[i->op]);
			break;
		}
		tinit[i->s.imm] = 1;
		con64((uvlong)mod->type[i->s.imm], RRTA);
		rbra(macro[MacFRAM], Ocall);
		opwst(i, Ostw, RCX);
		break;
	case ILEA:
		if(UXSRC(i->add) == SRC(AIMM)) {
			gen2(Ojmpb, 8);
			genq(i->s.imm);
			con64(DOT-8, RAX);
		} else {
			opwld(i, Olea, RAX);
		}
		opwst(i, Ostw, RAX);
		break;
	case IHEADW:
		opwld(i, Oldw, RAX);
		modrm(Oldw, OA(List, data), RAX, RAX);
		opwst(i, Ostw, RAX);
		break;
	case IHEADF:
		opwld(i, Oldw, RAX);
		gen2(0xDB, 0xE3);	/* FNINIT: reset x87 FPU state */
		modrm(Omovf, OA(List, data), RAX, 0);
		opwst(i, Omovf, 3);
		break;
	case IHEADB:
		opwld(i, Oldw, RAX);
		modrm(Oldb, OA(List, data), RAX, RAX);
		opwst(i, Ostb, RAX);
		break;
	case ITAIL:
		opwld(i, Oldw, RAX);
		modrm(Oldw, O(List, tail), RAX, RDI);
		goto movp;
	case IMOVP:
	case IHEADP:
		opwld(i, Oldw, RDI);
		if(i->op == IHEADP)
			modrm(Oldw, OA(List, data), RDI, RDI);
	movp:
		cmpl64(RDI, (uvlong)H);
		gen2(Ojeqb, 0x05);
		rbra(macro[MacCOLR], Ocall);
		opwst(i, Oldw, RAX);
		opwst(i, Ostw, RDI);
		rbra(macro[MacFRP], Ocall);
		break;
	case ILENA: {
		uchar *skip;
		opwld(i, Oldw, RDI);
		con64(0, RAX);
		cmpl64(RDI, (uvlong)H);
		gen2(Ojeqb, 0);
		skip = code - 1;
		modrm32(Oldw, O(Array, len), RDI, RAX);
		*skip = code - (skip + 1);
		opwst(i, Ostw, RAX);
		break;
	}
	case ILENC: {
		uchar *skip;
		opwld(i, Oldw, RDI);
		con64(0, RAX);
		cmpl64(RDI, (uvlong)H);
		gen2(Ojeqb, 0);
		skip = code - 1;
		modrm32(Oldw, O(String, len), RDI, RAX);
		cmpl64(RAX, 0);
		gen2(Ojgeb, 0x03);
		modrr(Oneg, RAX, 3);
		*skip = code - (skip + 1);
		opwst(i, Ostw, RAX);
		break;
	}
	case ILENL: {
		uchar *looptop, *loopend;
		con64(0, RAX);
		opwld(i, Oldw, RDI);
		looptop = code;
		cmpl64(RDI, (uvlong)H);
		gen2(Ojeqb, 0);
		loopend = code-1;
		modrm(Oldw, O(List, tail), RDI, RDI);
		modrr(0x83, RAX, 0);
		genb(1);
		gen2(Ojmpb, looptop - code - 2);
		*loopend = code - loopend - 1;
		opwst(i, Ostw, RAX);
		break;
	}
	case IBEQF:
	case IBNEF:
	case IBLEF:
	case IBLTF:
	case IBGEF:
	case IBGTF:
		punt(i, SRCOP|DSTOP|DBRAN|NEWPC|WRTPC, optab[i->op]);
		break;
	case IBEQW:
		cbra(i, Ojeql);
		break;
	case IBLEW:
		cbra(i, Ojlel);
		break;
	case IBNEW:
		cbra(i, Ojnel);
		break;
	case IBGTW:
		cbra(i, Ojgtl);
		break;
	case IBLTW:
		cbra(i, Ojltl);
		break;
	case IBGEW:
		cbra(i, Ojgel);
		break;
	case IBEQB:
		cbrab(i, Ojeql);
		break;
	case IBLEB:
		cbrab(i, Ojlsl);
		break;
	case IBNEB:
		cbrab(i, Ojnel);
		break;
	case IBGTB:
		cbrab(i, Ojhil);
		break;
	case IBLTB:
		cbrab(i, Ojbl);
		break;
	case IBGEB:
		cbrab(i, Ojael);
		break;
	case ISUBW:
		arith(i, 0x29, 5);
		break;
	case ISUBB:
		arithb(i, 0x28);
		break;
	case ISUBF:
		punt(i, SRCOP|DSTOP|THREOP, optab[i->op]);
		break;
	case IADDW:
		arith(i, 0x01, 0);
		break;
	case IADDB:
		arithb(i, 0x00);
		break;
	case IADDF:
		punt(i, SRCOP|DSTOP|THREOP, optab[i->op]);
		break;
	case IORW:
		arith(i, 0x09, 1);
		break;
	case IORB:
		arithb(i, 0x08);
		break;
	case IANDW:
		arith(i, 0x21, 4);
		break;
	case IANDB:
		arithb(i, 0x20);
		break;
	case IXORW:
		arith(i, Oxor, 6);
		break;
	case IXORB:
		arithb(i, 0x30);
		break;
	case ISHLW:
		shift(i, Oldw, Ostw, 0xd3, 4);
		break;
	case ISHLB:
		shift(i, Oldb, Ostb, 0xd2, 4);
		break;
	case ISHRW:
		shift(i, Oldw, Ostw, 0xd3, 7);
		break;
	case ISHRB:
		shift(i, Oldb, Ostb, 0xd2, 5);
		break;
	case IMOVF:
		gen2(0xDB, 0xE3);	/* FNINIT: reset x87 FPU state */
		opwld(i, Omovf, 0);
		opwst(i, Omovf, 3);
		break;
	case INEGF:
		gen2(0xDB, 0xE3);	/* FNINIT: reset x87 FPU state */
		opwld(i, Omovf, 0);
		genb(0xd9);
		genb(0xe0);
		opwst(i, Omovf, 3);
		break;
	case IMOVB:
		opwld(i, Oldb, RAX);
		opwst(i, Ostb, RAX);
		break;
	case IMOVW:
	case ICVTLW:
		if(UXSRC(i->add) == SRC(AIMM)) {
			opwst(i, Omov, RAX);
			genw(i->s.imm);
			break;
		}
		opwld(i, Oldw, RAX);
		opwst(i, Ostw, RAX);
		break;
	case ICVTWL:
		opwst(i, Olea, RRTMP);
		opwld(i, Oldw, RAX);
		/* Sign extend 32 to 64 then store both halves */
		modrr32(Oldw, RAX, RAX);		/* Zero extend to RAX */
		modrm32(Ostw, 0, RRTMP, RAX);
		genb(Ocdq);
		modrm32(Ostw, 4, RRTMP, RDX);
		break;
	case ICALL:
		if(UXDST(i->add) != DST(AIMM))
			opwst(i, Oldw, RRTA);
		opwld(i, Oldw, RAX);
		con64((uvlong)base+patch[i-mod->prog+1], RRTMP);
		modrm(Ostw, O(Frame, lr), RAX, RRTMP);
		modrm(Ostw, O(Frame, fp), RAX, RRFP);
		modrr(Oldw, RAX, RRFP);
		if(UXDST(i->add) != DST(AIMM)) {
			genb(REXW|REXB);
			gen2(Ojmprm, (3<<6)|(4<<3)|(RRTA&7));
			break;
		}
		/* fall through */
	case IJMP:
		if(RESCHED)
			schedcheck(i);
		rbra(patch[i->d.ins-mod->prog], Ojmp);
		break;
	case IMOVPC:
		con64(patch[i->s.imm]+(uvlong)base, RAX);
		opwst(i, Ostw, RAX);
		break;
	case IGOTO:
		opwst(i, Olea, RDI);
		opwld(i, Oldw, RAX);
		/* JMP [RDI + RAX*8] */
		genb(REXW);
		gen2(Ojmprm, (0<<6)|(4<<3)|4);
		genb((3<<6)|(RAX<<3)|RDI);

		if(pass == 0)
			break;

		t = (WORD*)(mod->origmp+i->d.ind);
		e = t + t[-1];
		t[-1] = 0;
		while(t < e) {
			t[0] = (uvlong)base + patch[t[0]];
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
		mid(i, Oldw, RAX);
		opwld(i, Oldw, RRTMP);
		if(i->op == IMULW) {
			modrr(0xf7, RRTMP, 4);
		} else {
			genb(REXW);
			genb(Ocqo);
			modrr(0xf7, RRTMP, 7);
			if(i->op == IMODW)
				modrr(Oxchg, RAX, RDX);
		}
		opwst(i, Ostw, RAX);
		break;
	case IMODB:
	case IDIVB:
	case IMULB:
		mid(i, Oldb, RAX);
		opwld(i, Oldb, RRTMP);
		if(i->op == IMULB) {
			modrr32(0xf6, RRTMP, 4);
		} else {
			genb(Ocdq);
			modrr32(0xf6, RRTMP, 7);
			if(i->op == IMODB)
				modrr32(Oxchg, RAX, RDX);
		}
		opwst(i, Ostb, RAX);
		break;
	case IINDX:
		opwld(i, Oldw, RRTMP);
		cmpl64(RRTMP, (uvlong)H);
		jnebounds(Ojneb, i);
		if(bflag) {
			opwst(i, Oldw, RAX);
			modrm32(0x3b, O(Array, len), RRTMP, RAX);
			jnebounds(0x72, i);
			modrm(Oldw, O(Array, t), RRTMP, RRTA);
			modrm32(0xf7, O(Type, size), RRTA, 5);
		} else {
			modrm(Oldw, O(Array, t), RRTMP, RAX);
			modrm32(Oldw, O(Type, size), RAX, RAX);
			if(UXDST(i->add) == DST(AIMM)) {
				modrr32(0x69, RAX, 0);
				genw(i->d.imm);
			} else {
				opwst(i, 0xf7, 5);
			}
		}
		modrm(0x03, O(Array, data), RRTMP, RAX);
		r = RRMP;
		if((i->add&ARM) == AXINF)
			r = RRFP;
		modrm(Ostw, i->reg, r, RAX);
		break;
	case IINDB:
		r = 0;
		goto idx;
	case IINDF:
	case IINDL:
		r = 3;
		goto idx;
	case IINDW:
		r = 3;	/* 64-bit on AMD64 */
	idx:
		opwld(i, Oldw, RAX);
		opwst(i, Oldw, RRTMP);
		cmpl64(RAX, (uvlong)H);
		jnebounds(Ojneb, i);
		if(bflag) {
			modrm32(0x3b, O(Array, len), RAX, RRTMP);
			jnebounds(0x72, i);
		}
		modrm(Oldw, O(Array, data), RAX, RAX);
		/* LEA (RAX)(RRTMP*scale), RAX */
		genb(REXW|REXX);
		gen2(Olea, (0<<6)|(0<<3)|4);
		genb((r<<6)|((RRTMP&7)<<3)|(RAX&7));
		r = RRMP;
		if((i->add&ARM) == AXINF)
			r = RRFP;
		modrm(Ostw, i->reg, r, RAX);
		break;
	case IINDC:
		opwld(i, Oldw, RAX);
		mid(i, Oldw, RDI);
		if(bflag) {
			modrm32(Oldw, O(String, len), RAX, RRTA);
			cmpl64(RRTA, 0);
			gen2(Ojltb, 16);
			modrr32(0x3b, RDI, RRTA);
			gen2(0x72, 5);
			bra((uvlong)bounds, Ocall);
			genb(0x0f);
			gen2(Omovzxb, (1<<6)|(0<<3)|4);
			gen2((0<<6)|(RDI<<3)|RAX, O(String, data));
			gen2(Ojmpb, 11);
			modrr32(Oneg, RRTA, 3);
			modrr32(0x3b, RDI, RRTA);
			gen2(0x73, 0xee);
			genb(0x0f);
			gen2(Omovzxw, (1<<6)|(0<<3)|4);
			gen2((1<<6)|(RDI<<3)|RAX, O(String, data));
			opwst(i, Ostw, RAX);
			break;
		}
		modrm32(Ocmpi, O(String, len), RAX, 7);
		genb(0);
		gen2(Ojltb, 7);
		genb(0x0f);
		gen2(Omovzxb, (1<<6)|(0<<3)|4);
		gen2((0<<6)|(RDI<<3)|RAX, O(String, data));
		gen2(Ojmpb, 5);
		genb(0x0f);
		gen2(Omovzxw, (1<<6)|(0<<3)|4);
		gen2((1<<6)|(RDI<<3)|RAX, O(String, data));
		opwst(i, Ostw, RAX);
		break;
	case ICASE:
		comcase(i, 1);
		break;
	case IMOVL:
		opwld(i, Oldw, RAX);
		opwst(i, Ostw, RAX);
		break;
	case IADDL:
		larith(i, 0x03, 0x13);
		break;
	case ISUBL:
		larith(i, 0x2b, 0x1b);
		break;
	case IORL:
		larith(i, 0x0b, 0x0b);
		break;
	case IANDL:
		larith(i, 0x23, 0x23);
		break;
	case IXORL:
		larith(i, 0x33, 0x33);
		break;
	case IBEQL:
		cbral(i, Ojnel, Ojeql, ANDAND);
		break;
	case IBNEL:
		cbral(i, Ojnel, Ojnel, OROR);
		break;
	case IBLEL:
		cbral(i, Ojltl, Ojbel, EQAND);
		break;
	case IBGTL:
		cbral(i, Ojgtl, Ojal, EQAND);
		break;
	case IBLTL:
		cbral(i, Ojltl, Ojbl, EQAND);
		break;
	case IBGEL:
		cbral(i, Ojgtl, Ojael, EQAND);
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

/*
 * JIT entry preamble
 */
static void
preamble(void)
{
	if(comvec)
		return;

#ifdef __APPLE__
	comvec = mmap(0, 128, PROT_READ|PROT_WRITE|PROT_EXEC,
	              MAP_PRIVATE|MAP_ANON|MAP_JIT, -1, 0);
	if(comvec == MAP_FAILED) {
		comvec = nil;
		return;
	}
	pthread_jit_write_protect_np(0);
#else
	comvec = jitmalloc(128);
	if(comvec == MAP_FAILED) {
		comvec = nil;
		return;
	}
#endif

	code = (uchar*)comvec;

	/* Save callee-saved registers */
	genb(Opushq+RBX);
	genb(REX|REXB); genb(Opushq+(R12-R8));
	genb(REX|REXB); genb(Opushq+(R14-R8));
	genb(REX|REXB); genb(Opushq+(R15-R8));

	/* Load R pointer into RLINK */
	con64((uvlong)&R, RLINK);

	/* Load VM registers */
	modrm(Oldw, O(REG, FP), RLINK, RRFP);
	modrm(Oldw, O(REG, MP), RLINK, RRMP);

	/* Jump to PC */
	modrm(Oldw, O(REG, PC), RLINK, RAX);
	genb(REXW);
	gen2(Ojmprm, (3<<6)|(4<<3)|RAX);

#ifdef __APPLE__
	pthread_jit_write_protect_np(1);
	sys_icache_invalidate(comvec, 128);
#else
	segflush(comvec, 128);
#endif
}

/*
 * Case dispatch macro
 */
static void
maccase(void)
{
	uchar *loop, *def, *lab1;

	/* n = t[0]; t = &t[1] */
	modrm(Oldw, 0, RSI, RDX);
	modrm(Olea, sizeof(WORD), RSI, RSI);

	/* RDI = n*3 (for table indexing) */
	modrr(Oldw, RDX, RDI);
	modrr(0x01, RDI, RDI);		/* ADD RDI, RDI → RDI = n*2 */
	modrr(0x01, RDI, RDX);		/* ADD RDI, RDX → RDI = n*3 (RDX preserved) */

	/* Push default address */
	genb(REXW);
	gen2(Opushrm, (0<<6)|(6<<3)|4);
	genb((3<<6)|(RDI<<3)|RSI);

	loop = code;
	cmpl64(RDX, 0);
	gen2(Ojleb, 0);
	def = code-1;

	/* n2 = n >> 1 */
	modrr(Oldw, RDX, RCX);
	modrr(0xd1, RCX, 5);		/* SHR RCX, 1 */

	/* RDI = n2 * 3 */
	modrr(Oldw, RCX, RDI);
	modrr(0x01, RDI, RDI);		/* ADD RDI, RDI → RDI = n2*2 */
	modrr(0x01, RDI, RCX);		/* ADD RDI, RCX → RDI = n2*3 (RCX preserved) */

	/* Compare: RAX vs t[n2*3] */
	genb(REXW);
	gen2(0x3b, (0<<6)|(RAX<<3)|4);
	genb((3<<6)|(RDI<<3)|RSI);

	gen2(Ojgeb, 0);
	lab1 = code-1;

	/* RAX < t[n2*3]: n = n2 */
	modrr(Oldw, RCX, RDX);
	gen2(Ojmpb, loop-code-2);

	*lab1 = code-lab1-1;

	/* RAX >= t[n2*3]: check upper bound */
	genb(REXW);
	gen2(0x3b, (1<<6)|(RAX<<3)|4);
	gen2((3<<6)|(RDI<<3)|RSI, sizeof(WORD));

	gen2(Ojltb, 0);
	lab1 = code-1;

	/* In range: t = &t[n2*3 + 3], n = n - n2 - 1 */
	genb(REXW);
	gen2(Olea, (1<<6)|(RSI<<3)|4);
	gen2((3<<6)|(RDI<<3)|RSI, 3*sizeof(WORD));
	modrr(0x2b, RCX, RDX);
	modrr(0x83, RDX, 5);
	genb(1);
	gen2(Ojmpb, loop-code-2);

	*lab1 = code-lab1-1;
	/* Found: jump to t[n2*3 + 2] */
	genb(REXW);
	gen2(Oldw, (1<<6)|(RAX<<3)|4);
	gen2((3<<6)|(RDI<<3)|RSI, 2*sizeof(WORD));
	genb(Opopq+RSI);		/* Pop default */
	genb(Opopq+RSI);
	genb(REXW);
	gen2(Ojmprm, (3<<6)|(4<<3)|RAX);

	*def = code-def-1;
	/* Default */
	genb(Opopq+RAX);
	genb(Opopq+RSI);
	genb(REXW);
	gen2(Ojmprm, (3<<6)|(4<<3)|RAX);
}

/*
 * Free pointer macro
 */
static void
macfrp(void)
{
	cmpl64(RAX, (uvlong)H);
	gen2(Ojneb, 0x01);
	genb(Oret);

	modrm32(0x83, O(Heap, ref)-sizeof(Heap), RAX, 7);
	genb(0x01);
	gen2(Ojeqb, 0x04);
	modrm32(Odecrm, O(Heap, ref)-sizeof(Heap), RAX, 1);
	genb(Oret);

	modrm(Ostw, O(REG, FP), RLINK, RRFP);
	modrm(Ostw, O(REG, s), RLINK, RAX);
	bra((uvlong)rdestroy, Ocall);
	modrm(Oldw, O(REG, FP), RLINK, RRFP);
	modrm(Oldw, O(REG, MP), RLINK, RRMP);
	genb(Oret);
}

/*
 * Return macro
 */
static void
macret(void)
{
	Inst i;
	uchar *s;
	static uvlong lpunt, lnomr, lfrmr, linterp;

	s = code;

	lpunt -= 2;
	lnomr -= 2;
	lfrmr -= 2;
	linterp -= 2;

	con64(0, RDI);
	modrm(Oldw, O(Frame, t), RRFP, RAX);
	modrr(Ocmpw, RAX, RDI);
	gen2(Ojeqb, lpunt-(code-s));

	modrm(Oldw, O(Type, destroy), RAX, RAX);
	modrr(Ocmpw, RAX, RDI);
	gen2(Ojeqb, lpunt-(code-s));

	modrm(Ocmpw, O(Frame, fp), RRFP, RDI);
	gen2(Ojeqb, lpunt-(code-s));

	modrm(Ocmpw, O(Frame, mr), RRFP, RDI);
	gen2(Ojeqb, lnomr-(code-s));

	modrm(Oldw, O(REG, M), RLINK, RRTA);
	modrm32(Odecrm, O(Heap, ref)-sizeof(Heap), RRTA, 1);
	gen2(Ojneb, lfrmr-(code-s));
	modrm32(Oincrm, O(Heap, ref)-sizeof(Heap), RRTA, 0);
	gen2(Ojmpb, lpunt-(code-s));

	lfrmr = code - s;
	modrm(Oldw, O(Frame, mr), RRFP, RRTA);
	modrm(Ostw, O(REG, M), RLINK, RRTA);
	modrm(Oldw, O(Modlink, MP), RRTA, RRMP);
	modrm(Ostw, O(REG, MP), RLINK, RRMP);
	modrm32(Ocmpi, O(Modlink, compiled), RRTA, 7);
	genb(0x00);
	gen2(Ojeqb, linterp-(code-s));

	lnomr = code - s;
	/* CALL *RAX */
	genb(REXW);
	gen2(Ocallrm, (3<<6)|(2<<3)|RAX);
	modrm(Ostw, O(REG, SP), RLINK, RRFP);
	modrm(Oldw, O(Frame, lr), RRFP, RAX);
	/* Check Frame.lr != nil before jumping to it */
	genb(REXW);
	gen2(0x85, (3<<6)|(RAX<<3)|RAX);	/* TEST RAX, RAX */
	gen2(Ojeqb, lpunt-(code-s));		/* JZ lpunt */
	modrm(Oldw, O(Frame, fp), RRFP, RRFP);
	modrm(Ostw, O(REG, FP), RLINK, RRFP);
	genb(REXW);
	gen2(Ojmprm, (3<<6)|(4<<3)|RAX);

	linterp = code - s;
	genb(REXW);
	gen2(Ocallrm, (3<<6)|(2<<3)|RAX);
	modrm(Ostw, O(REG, SP), RLINK, RRFP);
	modrm(Oldw, O(Frame, lr), RRFP, RAX);
	modrm(Ostw, O(REG, PC), RLINK, RAX);
	modrm(Oldw, O(Frame, fp), RRFP, RRFP);
	modrm(Ostw, O(REG, FP), RLINK, RRFP);
	/* Restore callee-saved and return */
	genb(REX|REXB); genb(Opopq+(R15-R8));
	genb(REX|REXB); genb(Opopq+(R14-R8));
	genb(REX|REXB); genb(Opopq+(R12-R8));
	genb(Opopq+RBX);
	genb(Oret);

	lpunt = code - s;
	i.add = AXNON;
	punt(&i, TCHECK|NEWPC, optab[IRET]);
}

/*
 * Color pointer macro
 */
static void
maccolr(void)
{
	modrm32(Oincrm, O(Heap, ref)-sizeof(Heap), RDI, 0);
	con64((uvlong)&mutator, RAX);
	modrm(Oldw, 0, RAX, RAX);
	modrm32(Ocmpw, O(Heap, color)-sizeof(Heap), RDI, RAX);
	gen2(Ojneb, 0x01);
	genb(Oret);
	con64(propagator, RAX);
	modrm32(Ostw, O(Heap, color)-sizeof(Heap), RDI, RAX);
	genb(Opushq+RDI);
	con64((uvlong)&nprop, RDI);
	modrm(Ostw, 0, RDI, RAX);
	genb(Opopq+RDI);
	genb(Oret);
}

/*
 * Module call macro
 */
static void
macmcal(void)
{
	uchar *label, *mlnil, *interp;

	cmpl64(RAX, (uvlong)H);
	gen2(Ojeqb, 0);
	mlnil = code - 1;

	modrm32(0x83, O(Modlink, prog), RRTA, 7);
	genb(0x00);
	gen2(Ojneb, 0);
	label = code-1;

	*mlnil = code-mlnil-1;
	modrm(Ostw, O(REG, FP), RLINK, RCX);
	modrm(Ostw, O(REG, dt), RLINK, RAX);
	bra((uvlong)rmcall, Ocall);
	modrm(Oldw, O(REG, FP), RLINK, RRFP);
	modrm(Oldw, O(REG, MP), RLINK, RRMP);
	genb(Oret);

	*label = code-label-1;
	modrr(Oldw, RCX, RRFP);
	modrm(Ostw, O(REG, M), RLINK, RRTA);
	modrm32(Oincrm, O(Heap, ref)-sizeof(Heap), RRTA, 0);
	modrm(Oldw, O(Modlink, MP), RRTA, RRMP);
	modrm(Ostw, O(REG, MP), RLINK, RRMP);

	modrm32(Ocmpi, O(Modlink, compiled), RRTA, 7);
	genb(0x00);
	genb(REX|REXB); genb(Opopq+(RRTA&7));
	gen2(Ojeqb, 0);
	interp = code-1;
	genb(REXW);
	gen2(Ojmprm, (3<<6)|(4<<3)|RAX);

	*interp = code-interp-1;
	modrm(Ostw, O(REG, FP), RLINK, RRFP);
	modrm(Ostw, O(REG, PC), RLINK, RAX);
	genb(REX|REXB); genb(Opopq+(R15-R8));
	genb(REX|REXB); genb(Opopq+(R14-R8));
	genb(REX|REXB); genb(Opopq+(R12-R8));
	genb(Opopq+RBX);
	genb(Oret);
}

/*
 * Frame allocation macro
 */
static void
macfram(void)
{
	uchar *label;

	modrm(Oldw, O(REG, SP), RLINK, RAX);
	modrm32(Oldw, O(Type, size), RRTA, RCX);	/* 32-bit load, zero-extended */
	modrr(0x03, RCX, RAX);				/* 64-bit ADD RAX, RCX */
	modrm(0x3b, O(REG, TS), RLINK, RAX);
	gen2(0x7c, 0x00);
	label = code-1;

	modrm(Ostw, O(REG, s), RLINK, RRTA);
	modrm(Ostw, O(REG, FP), RLINK, RRFP);
	bra((uvlong)extend, Ocall);
	modrm(Oldw, O(REG, FP), RLINK, RRFP);
	modrm(Oldw, O(REG, MP), RLINK, RRMP);
	modrm(Oldw, O(REG, s), RLINK, RCX);
	genb(Oret);

	*label = code-label-1;
	modrm(Oldw, O(REG, SP), RLINK, RCX);
	modrm(Ostw, O(REG, SP), RLINK, RAX);
	modrm(Ostw, O(Frame, t), RCX, RRTA);
	modrm(Omov, O(Frame, mr), RCX, 0);
	genw(0);
	modrm(Oldw, O(Type, initialize), RRTA, RRTA);
	genb(REXW|REXB);
	gen2(Ojmprm, (3<<6)|(4<<3)|(RRTA&7));
	genb(Oret);
}

/*
 * Module frame allocation (when initialize==0)
 */
static void
macmfra(void)
{
	modrm(Ostw, O(REG, FP), RLINK, RRFP);
	modrm(Ostw, O(REG, s), RLINK, RAX);
	modrm(Ostw, O(REG, d), RLINK, RRTA);
	bra((uvlong)rmfram, Ocall);
	modrm(Oldw, O(REG, FP), RLINK, RRFP);
	modrm(Oldw, O(REG, MP), RLINK, RRMP);
	genb(Oret);
}

/*
 * Reschedule check macro
 */
static void
macrelq(void)
{
	modrm(Ostw, O(REG, FP), RLINK, RRFP);
	genb(Opopq+RAX);
	modrm(Ostw, O(REG, PC), RLINK, RAX);
	genb(REX|REXB); genb(Opopq+(R15-R8));
	genb(REX|REXB); genb(Opopq+(R14-R8));
	genb(REX|REXB); genb(Opopq+(R12-R8));
	genb(Opopq+RBX);
	genb(Oret);
}

/*
 * Generate type destructor
 */
void
comd(Type *t)
{
	int i, j, m, c;

	for(i = 0; i < t->np; i++) {
		c = t->map[i];
		j = i * 8 * (int)sizeof(WORD*);
		for(m = 0x80; m != 0; m >>= 1) {
			if(c & m) {
				modrm(Oldw, j, RRFP, RAX);
				rbra(macro[MacFRP], Ocall);
			}
			j += sizeof(WORD*);
		}
	}
	genb(Oret);
}

/*
 * Generate type initializer
 */
void
comi(Type *t)
{
	int i, j, m, c;

	con64((uvlong)H, RAX);
	for(i = 0; i < t->np; i++) {
		c = t->map[i];
		j = i * 8 * (int)sizeof(WORD*);
		for(m = 0x80; m != 0; m >>= 1) {
			if(c & m)
				modrm(Ostw, j, RCX, RAX);
			j += sizeof(WORD*);
		}
	}
	genb(Oret);
}

void
typecom(Type *t)
{
	int n;
	uchar *tmp;

	if(t == nil || t->initialize != 0)
		return;

#ifdef __APPLE__
	tmp = mallocz(8192*sizeof(uchar), 0);
	if(tmp == nil)
		error(exNomem);
#else
	tmp = jitmalloc(8192*sizeof(uchar));
	if(tmp == MAP_FAILED)
		error(exNomem);
#endif

	code = tmp;
	comi(t);
	n = code - tmp;
	code = tmp;
	comd(t);
	n += code - tmp;
#ifdef __APPLE__
	free(tmp);
#else
	munmap(tmp, 8192*sizeof(uchar));
#endif

#ifdef __APPLE__
	code = mmap(0, n, PROT_READ|PROT_WRITE|PROT_EXEC,
	            MAP_PRIVATE|MAP_ANON|MAP_JIT, -1, 0);
	if(code == MAP_FAILED) {
		code = nil;
		return;
	}
	pthread_jit_write_protect_np(0);
#else
	code = jitmalloc(n);
	if(code == MAP_FAILED) {
		code = nil;
		return;
	}
	memset(code, 0, n);
#endif

	t->initialize = code;
	comi(t);
	t->destroy = code;
	comd(t);

	if(cflag > 3)
		print("typ= %.16llux %4d i %.16llux d %.16llux asm=%d\n",
			(uvlong)t, t->size, (uvlong)t->initialize, (uvlong)t->destroy, n);

#ifdef __APPLE__
	pthread_jit_write_protect_np(1);
	sys_icache_invalidate(t->initialize, n);
#else
	segflush(t->initialize, n);
#endif
}

static void
patchex(Module *m, uvlong *p)
{
	Handler *h;
	Except *e;

	if((h = m->htab) == nil)
		return;
	for( ; h->etab != nil; h++) {
		h->pc1 = p[h->pc1];
		h->pc2 = p[h->pc2];
		for(e = h->etab; e->s != nil; e++)
			e->pc = p[e->pc];
		if(e->pc != -1)
			e->pc = p[e->pc];
	}
}

/*
 * Main compilation entry point
 */
int
compile(Module *m, int size, Modlink *ml)
{
	uvlong v;
	Modl *e;
	Link *l;
	int i, n;
	uchar *s, *tmp;

	if(getenv("INFERNODE_NOJIT") != nil)
		return 0;

	base = nil;
	patch = mallocz((size+1)*sizeof(*patch), 0);
	tinit = malloc(m->ntype*sizeof(*tinit));
	/*
	 * tmp is used for pass 0 size estimation. On AMD64, it must be
	 * near the text segment so that bra() rel32 displacements to C
	 * functions fit in 32 bits during size calculation.
	 */
	tmp = jitmalloc(8192*sizeof(uchar));
	if(tinit == nil || patch == nil || tmp == MAP_FAILED) {
		if(tmp == MAP_FAILED) tmp = nil;
		goto bad;
	}

	preamble();
	if(comvec == nil)
		goto bad;

	mod = m;
	n = 0;
	pass = 0;
	nlit = 0;
	/*
	 * Set base and litpool to tmp during pass 0 so that con64() generates
	 * the same size encodings as pass 1 (both will be near the text segment).
	 */
	base = tmp;
	litpool = (uvlong*)tmp;

	for(i = 0; i < size; i++) {
		code = tmp;
		comp(&m->prog[i]);
		patch[i] = n;
		n += code - tmp;
	}
	patch[size] = n;	/* sentinel: offset past last instruction */

	for(i = 0; i < nelem(mactab); i++) {
		code = tmp;
		mactab[i].gen();
		macro[mactab[i].idx] = n;
		n += code - tmp;
	}

	n = (n+7)&~7;

	nlit *= sizeof(uvlong);

#ifdef __APPLE__
	base = mmap(0, n + nlit, PROT_READ|PROT_WRITE|PROT_EXEC,
	            MAP_PRIVATE|MAP_ANON|MAP_JIT, -1, 0);
	if(base == MAP_FAILED) {
		base = nil;
		goto bad;
	}
	pthread_jit_write_protect_np(0);
#else
	base = jitmalloc(n + nlit);
	if(base == MAP_FAILED) {
		base = nil;
		goto bad;
	}
	memset(base, 0, n + nlit);
#endif

	if(cflag > 3)
		print("dis=%5d %5d amd64=%5d asm=%.16llux lit=%d: %s\n",
			size, (int)(size*sizeof(Inst)), n, (uvlong)base, nlit, m->name);

	pass++;
	nlit = 0;
	litpool = (uvlong*)(base+n);
	code = base;

	{
	int nn = 0;
	for(i = 0; i < size; i++) {
		s = code;
		comp(&m->prog[i]);
		if(patch[i] != nn) {
			print("amd64 jit phase error: instr %d %D: pass0=%lud pass1=%d\n",
				i, &m->prog[i], patch[i], nn);
			urk();
		}
		nn += code - s;
		if(cflag > 4) {
			print("[%d] +0x%lux: %D\n", i, (ulong)nn, &m->prog[i]);
			das(s, code-s);
		}
	}
	}

	for(i = 0; i < nelem(mactab); i++)
		mactab[i].gen();

#ifdef __APPLE__
	pthread_jit_write_protect_np(1);
	sys_icache_invalidate(base, n + nlit);
#endif

	v = (uvlong)base;
	for(l = m->ext; l->name; l++) {
		l->u.pc = (Inst*)(v+patch[l->u.pc-m->prog]);
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
	if(tmp != nil)
		munmap(tmp, 8192*sizeof(uchar));
	free(m->prog);
	m->prog = (Inst*)base;
	m->compiled = 1;

#ifndef __APPLE__
	segflush(base, n*sizeof(*base));
#endif

	return 1;
bad:
	free(patch);
	free(tinit);
	if(tmp != nil)
		munmap(tmp, 8192*sizeof(uchar));
	if(base != nil && base != MAP_FAILED)
		munmap(base, n + nlit);
	return 0;
}
