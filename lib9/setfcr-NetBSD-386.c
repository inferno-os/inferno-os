/*
 * Linux 386 fpu support
 * Mimic Plan9 floating point support
 */
#include "lib9.h"

void
setfcr(ulong fcr)
{
	__asm__(	"xorb	$0x3f, %%al\n\t"
			"pushw	%%ax\n\t"
			"fwait\n\t"
			"fldcw	(%%esp)\n\t"
			"popw	%%ax\n\t"
			: /* no output */
			: "al" (fcr)
	);
}

ulong
getfcr(void)
{
	ulong fcr = 0;

	__asm__(	"pushl	%%eax\n\t"
			"fwait\n\t"
			"fstcw	(%%esp)\n\t"
			"popl	%%eax\n\t"
			"xorb	$0x3f, %%al\n\t"
			: "=a"  (fcr)
			: "eax"	(fcr)
	);
	return fcr; 
}

ulong
getfsr(void)
{
	ulong fsr = -1;

	__asm__(	"fwait\n\t"
			"fstsw	(%%eax)\n\t"
			"movl	(%%eax), %%eax\n\t"
			"andl	$0xffff, %%eax\n\t"
			: "=a"  (fsr)
			: "eax" (&fsr)
	);
	return fsr;
}

void
setfsr(ulong fsr)
{
	__asm__("fclex\n\t");
}
