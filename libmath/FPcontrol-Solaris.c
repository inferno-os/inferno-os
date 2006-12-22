#include <ieeefp.h>
#include "lib9.h"
#include "mathi.h"

void
FPinit(void)
{
	fpsetsticky(0);		/* Clear pending exceptions */
	fpsetround(FP_RN);
	fpsetmask(FP_X_INV|FP_X_DZ|FP_X_UFL|FP_X_OFL);
}

ulong
getFPstatus(void)
{
	ulong fsr = 0;
	fp_except fsr9=fpgetsticky();
	if(fsr9&FP_X_IMP) fsr |= INEX;
	if(fsr9&FP_X_OFL) fsr |= OVFL;
	if(fsr9&FP_X_UFL) fsr |= UNFL;
	if(fsr9&FP_X_DZ) fsr |= ZDIV;
	if(fsr9&FP_X_INV) fsr |= INVAL;
	return fsr;
}

ulong
FPstatus(ulong fsr, ulong mask)
{
	ulong fsr9 = 0;
	ulong old = getFPstatus();
	fsr = (fsr&mask) | (old&~mask);
	if(fsr&INEX) fsr9 |= FP_X_IMP;
	if(fsr&OVFL) fsr9 |= FP_X_OFL;
	if(fsr&UNFL) fsr9 |= FP_X_UFL;
	if(fsr&ZDIV) fsr9 |= FP_X_DZ;
	if(fsr&INVAL) fsr9 |= FP_X_INV;
	/* fpsetmask(fsr9); */
	fpsetsticky(fsr9);
	return(old&mask);
}

ulong
getFPcontrol(void)
{
	ulong fcr = 0;
	fp_except fpc = fpgetmask();
	fp_rnd fpround = fpgetround();

	if(fpc&FP_X_INV)
		fcr|=INVAL;
	if(fpc&FP_X_DZ)
		fcr|=ZDIV;
	if(fpc&FP_X_OFL)
		fcr|=OVFL;
	if(fpc&FP_X_UFL)
		fcr|=UNFL;
	if(fpc&FP_X_IMP)
		fcr|=INEX;
	switch(fpround){
	case FP_RZ:
		fcr|=RND_Z;
		break;
    	case FP_RN:
		fcr|=RND_NINF;
		break;
    	case FP_RP:
		fcr|=RND_PINF;
		break;
    	case FP_RM:
		fcr|=RND_NR;
	}
	return fcr;
}
ulong
FPcontrol(ulong fcr, ulong mask)
{
	fp_except fc=0;
	fp_rnd round;
	ulong old = getFPcontrol();
	ulong changed = mask&(fcr^old);
	fcr = (fcr&mask) | (old&~mask);

	if(fcr&INEX) fc |= FP_X_IMP;
	if(fcr&OVFL) fc |= FP_X_OFL;
	if(fcr&UNFL) fc |= FP_X_UFL;
	if(fcr&ZDIV) fc |= FP_X_DZ;
	if(fcr&INVAL) fc |= FP_X_INV;

	switch(fcr&RND_MASK){
		case RND_NR:    round |= FP_RM; break;
		case RND_NINF:  round |= FP_RN; break;
		case RND_PINF:  round |= FP_RP; break;
		case RND_Z:     round |= FP_RZ; break;
	}

	fpsetround(round);
	fpsetmask(fc);
	return(old&mask);
}
