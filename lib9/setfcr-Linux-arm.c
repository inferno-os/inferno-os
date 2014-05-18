/*
 * Linux arm fpu support
 * Mimic Plan9 floating point support
 */

#include "lib9.h"

#include <fenv.h>

void
setfcr(ulong fcr)
{
}

ulong
getfcr(void)
{
	ulong fcr = 0;
	return fcr; 
}

ulong
getfsr(void)
{
	ulong fsr = -1;
	return fsr;
}

void
setfsr(ulong fsr)
{
}
