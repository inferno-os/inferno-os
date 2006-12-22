#include "u.h"
#include "../port/lib.h"
#include "mem.h"
#include "ebsit.h"
#include "dat.h"
#include "fns.h"

#include "ureg.h"

int inpanic;

#define CSR ((ushort *) 0x2000000)
 

typedef struct Irqctlr {
	uint	addr;
  	uint	enabled;
	struct {
		void	(*r)(Ureg*, void*);
		void 	*a;
	} h[16];
} Irqctlr;

static Irqctlr irqctlr;  

void 
csrset( int bit )
{
static ushort *csr_val = 0x8c;

	*csr_val ^= (1 << bit);
	putcsr(*csr_val);
}

void
intrinit( void )
{
int offset;
ulong op;


	irqctlr.addr = 1;
	irqctlr.enabled = 0;
 
	/* Reset Exception */
	offset = ((((ulong) _vsvccall) - 0x0)-8) >> 2;
	op = ( 0xea << 24 ) | offset;
	*((ulong *) 0x0) = op;

	/* Undefined Instruction Exception */
	offset = ((((ulong) _vundcall) - 0x4)-8) >> 2;
	op = ( 0xea << 24 ) | offset;
	*((ulong *) 0x4) = op;

	/* SWI Exception */
	offset = ((((ulong) _vsvccall) - 0x8)-8) >> 2;
	op = ( 0xea << 24 ) | offset;
	*((ulong *) 0x8) = op;

	/* Prefetch Abort Exception */
	offset = ((((ulong) _vpabcall) - 0xc)-8) >> 2;
	op = ( 0xea << 24 ) | offset;
	*((ulong *) 0xc) = op;

	/* Data Abort Exception */
	offset = ((((ulong) _vdabcall) - 0x10)-8) >> 2;
	op = ( 0xea << 24 ) | offset;
	*((ulong *) 0x10) = op;

	/* IRQ Exception */
	offset = ((((ulong) _virqcall) - 0x18)-8) >> 2;
	op = ( 0xea << 24 ) | offset;
	*((ulong *) 0x18) = op;


}

void
intrenable(uint addr, int bit, void (*r)(Ureg*, void*), void* a)
{
	int i;
	USED(addr);
	for(i = 0; i < 16; i++)
		{
		if((bit & (1<<i)) == 0)
			continue;
		irqctlr.h[i].r = r;
		irqctlr.h[i].a = a;
		irqctlr.enabled |= (1<<i); 
		if (i < 7) 
			csrset(i);
		}
	return;
}

int lucifer;					/* Global to store the last CSR (eric) */

static void
interrupt(Ureg* ureg)
{
	int i, mask;

 		mask = *CSR;
		lucifer = mask;			/* eric */
		if(irqctlr.enabled == 0){
		
			return;
 			}
		for(i = 0; i < 16; i++)
			{

			if((irqctlr.enabled & (1<<i)) == 0)
				continue;
			if(( mask & (1 << i)) == 0)
				continue;
			if (!irqctlr.h[i].r)
				continue;
			(irqctlr.h[i].r)(ureg, irqctlr.h[i].a);
			mask &= ~(1 << i);
			}

		if ((mask) && (mask < 0x90))		/* ignore non-maskable interrupts */
			{
			print("unknown or unhandled interrupt\n");
			panic("unknown or unhandled interrupt: mask=%ux",mask);
			}
	
}

static void
dumpregs(Ureg* ureg)
{
	print("PSR %8.8uX type %2.2uX PC %8.8uX LINK %8.8uX\n",
		ureg->psr, ureg->type, ureg->pc, ureg->link);
	print("R14 %8.8uX R13 %8.8uX R12 %8.8uX R11 %8.8uX R10 %8.8uX\n",
		ureg->r14, ureg->r13, ureg->r12, ureg->r11, ureg->r10);
	print("R9  %8.8uX R8  %8.8uX R7  %8.8uX R6  %8.8uX R5  %8.8uX\n",
		ureg->r9, ureg->r8, ureg->r7, ureg->r6, ureg->r5);
	print("R4  %8.8uX R3  %8.8uX R2  %8.8uX R1  %8.8uX R0  %8.8uX\n",
		ureg->r4, ureg->r3, ureg->r2, ureg->r1, ureg->r0);
	print("Last Interrupt's CSR: %8.8uX\n",lucifer);
	print("CPSR %8.8uX SPSR %8.8uX\n", cpsrr(), spsrr());
}

void
dumpstack(void)
{
}

void
exception(Ureg* ureg)
{
	static Ureg old_ureg;
	uint far =0;
	uint fsr =0;

	static lasttype = 0;

	LOWBAT;	
	
	USED(far, fsr);

	lasttype = ureg->type;

	/*
	 * All interrupts/exceptions should be resumed at ureg->pc-4,
	 * except for Data Abort which resumes at ureg->pc-8.
	 */

	if(ureg->type == (PsrMabt+1))
		ureg->pc -= 8;
	else
		ureg->pc -= 4;

	switch(ureg->type){

	case PsrMfiq:				/* (Fast) */
		print("Fast\n");
		print("We should never be here\n");
		while(1);

	case PsrMirq:				/* Interrupt Request */
		interrupt(ureg);
		break;

	case PsrMund:				/* Undefined instruction */
		print("Undefined instruction\n");
	case PsrMsvc:				/* Jump through 0, SWI or reserved trap */
		print("SWI/SVC trap\n");
	case PsrMabt:				/* Prefetch abort */
		print("Prefetch Abort\n");
	case PsrMabt+1:				/* Data abort */
		print("Data Abort\n");


	default:
		dumpregs(ureg);
		/* panic("exception %uX\n", ureg->type); */
		break;
	}

	LOWBAT;				/* Low bat off after interrupt */

	splhi();

}
