#include "lib9.h"
#include "mathi.h"

void
FPinit(void)
{
	setfsr(0);	/* Clear pending exceptions */
	setfcr(FPPDBL|FPRNR|FPINVAL|FPZDIV|FPUNFL|FPOVFL);
}

ulong
getFPstatus(void)
{
	ulong fsr = 0, fsr9 = getfsr();
	/* on specific machines, could be table lookup */
	if(fsr9&FPAINEX) fsr |= INEX;
	if(fsr9&FPAOVFL) fsr |= OVFL;
	if(fsr9&FPAUNFL) fsr |= UNFL;
	if(fsr9&FPAZDIV) fsr |= ZDIV;
	if(fsr9&FPAINVAL) fsr |= INVAL;
	return fsr;
}

ulong
FPstatus(ulong fsr, ulong mask)
{
	ulong fsr9 = 0;
	ulong old = getFPstatus();
	fsr = (fsr&mask) | (old&~mask);
	if(fsr&INEX) fsr9 |= FPAINEX;
	if(fsr&OVFL) fsr9 |= FPAOVFL;
	if(fsr&UNFL) fsr9 |= FPAUNFL;
	if(fsr&ZDIV) fsr9 |= FPAZDIV;
	if(fsr&INVAL) fsr9 |= FPAINVAL;
	setfsr(fsr9);
	return(old&mask);
}

ulong
getFPcontrol(void)
{
	ulong fcr = 0, fcr9 = getfcr();
	switch(fcr9&FPRMASK){
		case FPRNR:	fcr = RND_NR; break;
		case FPRNINF:	fcr = RND_NINF; break;
		case FPRPINF:	fcr = RND_PINF; break;
		case FPRZ:	fcr = RND_Z; break;
	}
	if(fcr9&FPINEX) fcr |= INEX;
	if(fcr9&FPOVFL) fcr |= OVFL;
	if(fcr9&FPUNFL) fcr |= UNFL;
	if(fcr9&FPZDIV) fcr |= ZDIV;
	if(fcr9&FPINVAL) fcr |= INVAL;
	return fcr;
}

ulong
FPcontrol(ulong fcr, ulong mask)
{
	ulong fcr9 = FPPDBL;
	ulong old = getFPcontrol();
	fcr = (fcr&mask) | (old&~mask);
	if(fcr&INEX) fcr9 |= FPINEX;
	if(fcr&OVFL) fcr9 |= FPOVFL;
	if(fcr&UNFL) fcr9 |= FPUNFL;
	if(fcr&ZDIV) fcr9 |= FPZDIV;
	if(fcr&INVAL) fcr9 |= FPINVAL;
	switch(fcr&RND_MASK){
		case RND_NR:	fcr9 |= FPRNR; break;
		case RND_NINF:	fcr9 |= FPRNINF; break;
		case RND_PINF:	fcr9 |= FPRPINF; break;
		case RND_Z:	fcr9 |= FPRZ; break;
	}
	setfcr(fcr9);
	return(old&mask);
}

