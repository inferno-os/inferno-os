#include "lib9.h"

ulong
getfcr(void)
{
	ulong v;

	__asm("st %%fsr, %0" : "=m" (*&v));
	return v;
}

void
setfcr(ulong v)
{
	ulong vv;

	vv = (getfcr() & ~FPFCR) | (v & FPFCR);
	__asm("ld %0, %%fsr" : : "m" (*&vv));
}

ulong
getfsr(void)
{
	ulong v;

	__asm("st %%fsr, %0" : "=m" (*&v));
	return v;
}

void
setfsr(ulong v)
{
	ulong vv;

	vv = (getfcr() & ~FPFSR) | (v & FPFSR);
	__asm("ld %0, %%fsr" : : "m" (*&vv));
}
