#include "lib9.h"

ulong
getfcr(void)
{
	double fpscr;

	fpscr = __readflm();
	return ((ulong*)&fpscr)[1];
}

ulong
getfsr(void)
{
	double fpscr;

	fpscr = __readflm();
	return ((ulong*)&fpscr)[1];
}

void
setfsr(ulong fsr)
{
	double fpscr;

	fpscr = __readflm();
	(((ulong*)&fpscr)[1]) = fsr;
	__setflm(fpscr);
}

void
setfcr(ulong fcr)
{
	double fpscr;

	fpscr = __readflm();
	(((ulong*)&fpscr)[1]) = fcr;
	__setflm(fpscr);
}
