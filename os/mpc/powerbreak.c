#include	"u.h"
#include	"../port/lib.h"
#include	"mem.h"
#include	"dat.h"
#include	"fns.h"
#include	"../port/error.h"
#include	"ureg.h"

extern int (*breakhandler)(Ureg *ur, Proc*);	/* trap.c */
extern Instr BREAK;	/* trap.c */
extern void portbreakinit(void);

#define getop(i) ((i>>26)&0x3F)
#define getxo(i) ((i>>1)&0x3FF)
#define getbobi(i)	bo = (i>>21)&0x1f; bi = (i>>16)&0x1f; xx = (i>>11)&0x1f;

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

static int
condok(Ureg *ur, ulong ir, int ctrok)
{
	int bo, bi, xx;
	ulong ctrval;

	ctrval = ur->ctr;
	getbobi(ir);
	if(xx)
		return 0;	/* illegal */
	if((bo & 0x4) == 0) {
		if(!ctrok)
			return 0;	/* illegal */
		ctrval--;
	}
	if(bo & 0x4 || (ctrval!=0)^((bo>>1)&1)) {
		if(bo & 0x10 || (((ur->cr & (1L<<(31-bi))!=0)==((bo>>3)&1))))
			return 1;
	}
	return 0;
}

/*
 * Return the address of the instruction that will be executed after the
 * instruction at ur->pc, accounting for current branch conditions.
 */
ulong
machnextaddr(Ureg *ur)
{
	long imm;
	ulong ir;

	ir = *(ulong*)ur->pc;
	switch(getop(ir)) {
	case 18:	/* branch */
		imm = ir & 0x03FFFFFC;
		if(ir & 0x02000000)
			imm |= 0xFC000000;	/* sign extended */
		if((ir & 2) == 0)	/* relative address */
			return ur->pc + imm;
		return imm;
			
	case 16:	/* conditional branch */
		if(condok(ur, ir&0xFFFF0000, 1)){
			imm = ir & 0xFFFC;
			if(ir & 0x08000)
				imm |= 0xFFFF0000;	/* sign extended */
			if((ir & 2) == 0)	/* relative address */
				return ur->pc + imm;
			return imm;
		}
		break;

	case 19:	/* conditional branch to register */
		switch(getxo(ir)){
		case 528:	/* bcctr */
			if(condok(ur, ir, 0))
				return ur->ctr & ~3;
			break;
		case 16:	/* bclr */
			if(condok(ur, ir, 1))
				return ur->lr & ~3;
			break;
		}
		break;
	}
	return ur->pc+4;	/* next instruction */
}

int
isvalid_va(void *v)
{
	return (ulong)v >= KTZERO;
}
