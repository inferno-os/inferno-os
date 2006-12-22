#include "u.h"
#include "../port/lib.h"
#include "mem.h"
#include "dat.h"
#include "fns.h"
#include "ureg.h"
#include "../port/error.h"

//
// from trap.c
//
extern int (*breakhandler)(Ureg *ur, Proc*);
extern Instr BREAK;
extern void portbreakinit(void);

//
// Instructions that can have the PC as a destination register
//
enum {
	IADD = 1,
	IBRANCH,
	ILDM,
	ILDR,
	IMOV,

	//
	// These should eventually be implemented
	//
	IADC,
	IAND,
	IBIC,
	IEOR,
	ILDRT,
	IMRS,
	IMVN,
	IORR,
	IRSB,
	IRSC,
	ISBC,
	ISUB,
};

static int	instrtype(Instr i);
static ulong	iadd(Ureg *ur, Instr i);
static ulong	ibranch(Ureg *ur, Instr i);
static ulong	ildm(Ureg *ur, Instr i);
static ulong	ildr(Ureg *ur, Instr i);
static ulong	imov(Ureg *ur, Instr i);
static ulong	shifterval(Ureg *ur, Instr i);
static int	condpass(Instr i, ulong psr);
static ulong	*address(Ureg *ur, Instr i);
static ulong*	multiaddr(Ureg *ur, Instr i);
static int	nbits(ulong v);

#define COND_N(psr)	(((psr) >> 31) & 1)
#define COND_Z(psr)	(((psr) >> 30) & 1)
#define COND_C(psr)	(((psr) >> 29) & 1)
#define COND_V(psr)	(((psr) >> 28) & 1)
#define REG(i, a, b)	(((i) & BITS((a), (b))) >> (a))
#define REGVAL(ur, r)	(*((ulong*)(ur) + (r)))
#define LSR(v, s)	((ulong)(v) >> (s))
#define ASR(v, s)	((long)(v) >> (s))
#define ROR(v, s)	(LSR((v), (s)) | (((v) & ((1 << (s))-1)) << (32 - (s))))

void
machbreakinit(void)
{
	portbreakinit();
	breakhandler = breakhit;
}

Instr
machinstr(ulong addr)
{
	if (addr < KTZERO)
		error(Ebadarg);
	return *(Instr*)addr;
}

void
machbreakset(ulong addr)
{
	if (addr < KTZERO)
		error(Ebadarg);
	*(Instr*)addr = BREAK;
	segflush((void*)addr, sizeof(Instr));
}

void
machbreakclear(ulong addr, Instr i)
{
	if (addr < KTZERO)
		error(Ebadarg);
	*(Instr*)addr = i;
	segflush((void*)addr, sizeof(Instr));
}

//
// Return the address of the instruction that will be executed after the
// instruction at address ur->pc.
//
// This means decoding the instruction at ur->pc.
//
// In the simple case, the PC will simply be the address of the next
// sequential instruction following ur->pc.
//
// In the complex case, the instruction is a branch of some sort, so the
// value of the PC after the instruction must be computed by decoding
// and simulating the instruction enough to determine the PC.
//

ulong
machnextaddr(Ureg *ur)
{
	Instr i;
	i = machinstr(ur->pc);
	switch(instrtype(i)) {
		case IADD:	return iadd(ur,i);
		case IBRANCH:	return ibranch(ur,i);
		case ILDM:	return ildm(ur,i);
		case ILDR:	return ildr(ur,i);
		case IMOV:	return imov(ur,i);

		case IADC:
		case IAND:
		case IBIC:
		case IEOR:
		case ILDRT:
		case IMRS:
		case IMVN:
		case IORR:
		case IRSB:
		case IRSC:
		case ISBC:
		case ISUB:
			// XXX - Tad: unimplemented
			//
			// any of these instructions could possibly have the
			// PC as Rd.  Eventually, these should all be
			// checked just like the others.
		default:
			return ur->pc+4;
	}

	return 0;
}

static int
instrtype(Instr i)
{
	if(i & BITS(26,27) == 0) {
		switch((i >> 21) & 0xF) {
			case 0:		return IAND;
			case 1:		return IEOR;
			case 2:		return ISUB;
			case 3:		return IRSB;
			case 4:		return IADD;
			case 5:		return IADC;
			case 6:		return ISBC;
			case 7:		return IRSC;
			case 0xD:	return IMOV;
			case 0xC:	return IORR;
			case 0xE:	return IBIC;
			case 0xF:	return IMVN;
		}
		if(((i & BIT(25)|BITS(23,24)|BITS(20,21))) >> 20 == 0x10)
			return IMRS;
		return 0;
	}

	if(((i & BITS(27,25)|BIT(20)) >> 20) == 0x81) return ILDM;
	if(((i & BITS(26,27)|BIT(22)|BIT(20)) >> 20) == 0x41) return ILDR;
	if(((i & BITS(25,27)) >> 25) == 5) return IBRANCH;

	return 0;
}

static ulong
iadd(Ureg *ur, Instr i)
{
	ulong Rd = REG(i, 12, 15);
	ulong Rn = REG(i, 16, 19);

	if(Rd != 15 || !condpass(i, ur->psr))
		return ur->pc+4;

	return REGVAL(ur, Rn) + shifterval(ur, i);
}

static ulong
ibranch(Ureg *ur, Instr i)
{
	if(!condpass(i, ur->psr))
		return ur->pc+4;
	return ur->pc + ((signed long)(i << 8) >> 6) + 8;
}

static ulong
ildm(Ureg *ur, Instr i)
{
	if((i & BIT(15)) == 0)
		return ur->pc+4;

	return *(multiaddr(ur, i) + nbits(i & BITS(15, 0)));
}

static ulong
ildr(Ureg *ur, Instr i)
{
	if(REG(i, 12, 19) != 15 || !condpass(i, ur->psr))
		return ur->pc+4;

	return *address(ur, i);
}

static ulong
imov(Ureg *ur, Instr i)
{
	if(REG(i, 12, 15) != 15 || !condpass(i, ur->psr))
		return ur->pc+4;

	return shifterval(ur, i);
}

static int
condpass(Instr i, ulong psr)
{
	uchar n = COND_N(psr);
	uchar z = COND_Z(psr);
	uchar c = COND_C(psr);
	uchar v = COND_V(psr);

	switch(LSR(i,28)) {
		case 0:		return z;
		case 1:		return !z;
		case 2:		return c;
		case 3:		return !c;
		case 4:		return n;
		case 5:		return !n;
		case 6:		return v;
		case 7:		return !v;
		case 8:		return c && !z;
		case 9:		return !c || z;
		case 10:	return n == v;
		case 11:	return n != v;
		case 12:	return !z && (n == v);
		case 13:	return z && (n != v);
		case 14:	return 1;
		case 15:	return 0;
	}
}

static ulong
shifterval(Ureg *ur, Instr i)
{
	if(i & BIT(25)) {					// IMMEDIATE
		ulong imm = i & BITS(0,7);
		ulong s = (i & BITS(8,11)) >> 7;  // this contains the * 2
		return ROR(imm, s);
	} else {
		ulong Rm = REGVAL(ur, REG(i, 0, 3));
		ulong s = (i & BITS(7,11)) >> 7;

		switch((i & BITS(6,4)) >> 4) {
		case 0: 					// LSL
			return Rm << s;
		case 1:						// LSLREG
			s = REGVAL(ur, s >> 1) & 0xFF;
			if(s >= 32) return 0;
			return Rm << s;
		case 2: 					// LSRIMM
			return LSR(Rm, s);
		case 3: 					// LSRREG
			s = REGVAL(ur, s >> 1) & 0xFF;
			if(s >= 32) return 0;
			return LSR(Rm, s);
		case 4:						// ASRIMM
			if(s == 0) {
				if(Rm & BIT(31) == 0)
					return 0;
				return 0xFFFFFFFF;
			}
			return ASR(Rm, s);
		case 5:						// ASRREG
			s = REGVAL(ur, s >> 1) & 0xFF;
			if(s >= 32) {
				if(Rm & BIT(31) == 0)
					return 0;
				return 0xFFFFFFFF;
			}
			return ASR(Rm, s);
		case 6: 					// RORIMM
			if(s == 0)
				return (COND_C(ur->psr) << 31) | LSR(Rm, 1);
			return ROR(Rm, s);
		case 7: 					// RORREG
			s = REGVAL(ur, s >> 1) & 0xFF;
			if(s == 0 || (s & 0xF) == 0)
				return Rm;
			return ROR(Rm, s & 0xF);
		}
	}
}

static ulong*
address(Ureg *ur, Instr i)
{
	ulong Rn = REGVAL(ur, REG(i, 16, 19));

	if(i & BIT(24) == 0) 					// POSTIDX
		return (ulong*)REGVAL(ur, Rn);
	if(i & BIT(25) == 0) {					// OFFSET
		if(i & BIT(23))
			return (ulong*)(REGVAL(ur, Rn) + (i & BITS(0, 11)));
		return (ulong*)(REGVAL(ur, Rn) - (i & BITS(0, 11)));
	} else {						// REGOFF
		ulong Rm = REGVAL(ur, REG(i, 0, 3));
		ulong index = 0;
		switch(i & BITS(5,6) >> 5) {
		case 0:	index = Rm << ((i & BITS(7, 11)) >> 7);		break;
		case 1:	index = LSR(Rm, ((i & BITS(7, 11)) >> 7));	break;
		case 2:	index = ASR(Rm, ((i & BITS(7, 11)) >> 7));	break;
		case 3:
			if(i & BITS(7, 11) == 0)
				index = (COND_C(ur->psr) << 31) | LSR(Rm, 1);
			else
				index = ROR(Rm, (i & BITS(7, 11)) >> 7);
			break;
		}
		if(i & BIT(23))
			return (ulong*)(Rn + index);
		return (ulong*)(Rn - index);
	}
}

static ulong*
multiaddr(Ureg *ur, Instr i)
{
	ulong Rn = REGVAL(ur, REG(i, 16, 19));

	switch((i >> 23) & 3) {
		case 0: return (ulong*)(Rn - (nbits(i & BITS(0,15))*4)+4);
		case 1:	return (ulong*)Rn;
		case 2: return (ulong*)(Rn - (nbits(i & BITS(0,15))*4));
		case 3: return (ulong*)(Rn + 4);
	}
}

static int
nbits(ulong v)
{
	int n = 0;
	int i;
	for(i = 0; i < 32; i++) {
		if(v & 1)
			++n;
		v = LSR(v, 1);
	}
	return n;
}
