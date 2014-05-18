/*
 * MacOSX/Darwin ppc fpu support
 * Mimic Plan9 floating point support
 */

#include "lib9.h"
#include <architecture/ppc/fp_regs.h>

__inline__ ulong
getfcr(void)
{
	ppc_fp_scr_t fpscr = get_fp_scr();
	return ((ulong *)&fpscr)[1];
}

ulong
getfsr(void)
{
	ppc_fp_scr_t fpscr = get_fp_scr();
	return ((ulong *)&fpscr)[1];
}

void
setfsr(ulong fsr)
{
	ppc_fp_scr_t fpscr;
	// fpscr = get_fp_scr();
	(((ulong *)&fpscr)[1]) = fsr;
	set_fp_scr(fpscr);
}

void
setfcr(ulong fcr)
{
	ppc_fp_scr_t fpscr;
	// fpscr = get_fp_scr();
	(((ulong *)&fpscr)[1]) = fcr;
	set_fp_scr(fpscr);
}
