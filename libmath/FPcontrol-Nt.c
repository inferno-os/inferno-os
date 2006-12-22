#include "lib9.h"
#include <float.h>
#include "mathi.h"

void
FPinit(void)
{
	_controlfp(_EM_INEXACT,_MCW_EM);	// abort on underflow, etc.
}

ulong
getFPstatus(void)
{
	ulong fsr = 0, fsr32 = _statusfp();
	if(fsr32&_SW_INEXACT) fsr |= INEX;
	if(fsr32&_SW_OVERFLOW) fsr |= OVFL;
	if(fsr32&_SW_UNDERFLOW) fsr |= UNFL;
	if(fsr32&_SW_ZERODIVIDE) fsr |= ZDIV;
	if(fsr32&_SW_INVALID) fsr |= INVAL;
	return fsr;
}

ulong
FPstatus(ulong fsr, ulong mask)
{
	ulong old = getFPstatus();
	fsr = (fsr&mask) | (old&~mask);
	if(fsr!=old){
		_clearfp();
		if(fsr){
			ulong fcr = _controlfp(0,0);
			double x = 1., y = 1e200, z = 0.;
			_controlfp(_MCW_EM,_MCW_EM);
			if(fsr&INEX) z = x + y;
			if(fsr&OVFL) z = y*y;
			if(fsr&UNFL) z = (x/y)/y;
			if(fsr&ZDIV) z = x/z;
			if(fsr&INVAL) z = z/z;
			_controlfp(fcr,_MCW_EM);
		}
	}
	return(old&mask);
}

ulong
getFPcontrol(void)
{
	ulong fcr, fcr32 = _controlfp(0,0);
	switch(fcr32&_MCW_RC){
		case _RC_NEAR:	fcr = RND_NR; break;
		case _RC_DOWN:	fcr = RND_NINF; break;
		case _RC_UP:	fcr = RND_PINF; break;
		case _RC_CHOP:	fcr = RND_Z; break;
	}
	if(!(fcr32&_EM_INEXACT)) fcr |= INEX;
	if(!(fcr32&_EM_OVERFLOW)) fcr |= OVFL;
	if(!(fcr32&_EM_UNDERFLOW)) fcr |= UNFL;
	if(!(fcr32&_EM_ZERODIVIDE)) fcr |= ZDIV;
	if(!(fcr32&_EM_INVALID)) fcr |= INVAL;
	return fcr;
}

ulong
FPcontrol(ulong fcr, ulong mask)
{
	ulong old = getFPcontrol();
	ulong fcr32 = _MCW_EM, mask32 = _MCW_RC|_MCW_EM;
	fcr = (fcr&mask) | (old&~mask);
	if(fcr&INEX) fcr32 ^= _EM_INEXACT;
	if(fcr&OVFL) fcr32 ^= _EM_OVERFLOW;
	if(fcr&UNFL) fcr32 ^= _EM_UNDERFLOW;
	if(fcr&ZDIV) fcr32 ^= _EM_ZERODIVIDE;
	if(fcr&INVAL) fcr32 ^= _EM_INVALID;
	switch(fcr&RND_MASK){
		case RND_NR:	fcr32 |= _RC_NEAR; break;
		case RND_NINF:	fcr32 |= _RC_DOWN; break;
		case RND_PINF:	fcr32 |= _RC_UP; break;
		case RND_Z:	fcr32 |= _RC_CHOP; break;
	}
	_controlfp(fcr32,mask32);
	return(old&mask);
}
