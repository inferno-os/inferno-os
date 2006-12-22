/* Load programs with -lfpe. See man pages for fpc and /usr/include/sigfpe.h, sys/fpu.h. */
#include <stdlib.h>
#include <sigfpe.h>
#include <sys/fpu.h>
typedef unsigned int ulong;
#include "mathi.h"

/*
 * Irix does not permit a use handled SIGFPE since the floating point unit
 * cannot be IEEE754 compliant without some software, so we must vector using
 * the library
 */
extern	void trapFPE(unsigned exception[5], int value[2]);

void
FPinit(void)
{
	union fpc_csr csr;
	int i;
	for(i=1; i<=4; i++) {
		sigfpe_[i].repls = _USER_DETERMINED;
		sigfpe_[i].abort = 2;
	}
	handle_sigfpes(_ON,
			_EN_UNDERFL|_EN_OVERFL|_EN_DIVZERO|_EN_INVALID,
			trapFPE,
			_ABORT_ON_ERROR, 0);
}


ulong
getFPstatus(void)
{
	ulong fsr = 0;
	union fpc_csr csr;
	csr.fc_word = get_fpc_csr();
	if(csr.fc_struct.se_inexact) fsr |= INEX;
	if(csr.fc_struct.se_overflow) fsr |= OVFL;
	if(csr.fc_struct.se_underflow) fsr |= UNFL;
	if(csr.fc_struct.se_divide0) fsr |= ZDIV;
	if(csr.fc_struct.se_invalid) fsr |= INVAL;
	return fsr;
}

ulong
FPstatus(ulong fsr, ulong mask)
{
	ulong old = getFPstatus();
	union fpc_csr csr;
	csr.fc_word = get_fpc_csr();
	fsr = (fsr&mask) | (old&~mask);
	csr.fc_struct.se_inexact = (fsr&INEX)?1:0;
	csr.fc_struct.se_overflow = (fsr&OVFL)?1:0;
	csr.fc_struct.se_underflow = (fsr&UNFL)?1:0;
	csr.fc_struct.se_divide0 = (fsr&ZDIV)?1:0;
	csr.fc_struct.se_invalid = (fsr&INVAL)?1:0;
	set_fpc_csr(csr.fc_word);
	return(old&mask);
}

ulong
getFPcontrol(void)
{
	ulong fcr = 0;
	union fpc_csr csr;
	double junk = fabs(1.); /* avoid bug mentioned in sigfpes man page [ehg] */
	csr.fc_word = get_fpc_csr();
	switch(csr.fc_struct.rounding_mode){
		case ROUND_TO_NEAREST:		fcr = RND_NR; break;
		case ROUND_TO_MINUS_INFINITY:	fcr = RND_NINF; break;
		case ROUND_TO_PLUS_INFINITY:	fcr = RND_PINF; break;
		case ROUND_TO_ZERO:		fcr = RND_Z; break;
	}
	if(csr.fc_struct.en_inexact) fcr |= INEX;
	if(csr.fc_struct.en_overflow) fcr |= OVFL;
	if(csr.fc_struct.en_underflow) fcr |= UNFL;
	if(csr.fc_struct.en_divide0) fcr |= ZDIV;
	if(csr.fc_struct.en_invalid) fcr |= INVAL;
	return fcr;
}

ulong
FPcontrol(ulong fcr, ulong mask)
{
	ulong old = getFPcontrol();
	union fpc_csr csr;
	csr.fc_word = get_fpc_csr();
	fcr = (fcr&mask) | (old&~mask);
	csr.fc_struct.en_inexact = (fcr&INEX)?1:0;
	csr.fc_struct.en_overflow = (fcr&OVFL)?1:0;
	csr.fc_struct.en_underflow = (fcr&UNFL)?1:0;
	csr.fc_struct.en_divide0 = (fcr&ZDIV)?1:0;
	csr.fc_struct.en_invalid = (fcr&INVAL)?1:0;
	switch(fcr&RND_MASK){
		case RND_NR:	csr.fc_struct.rounding_mode = ROUND_TO_NEAREST; break;
		case RND_NINF:	csr.fc_struct.rounding_mode = ROUND_TO_MINUS_INFINITY; break;
		case RND_PINF:	csr.fc_struct.rounding_mode = ROUND_TO_PLUS_INFINITY; break;
		case RND_Z:	csr.fc_struct.rounding_mode = ROUND_TO_ZERO; break;
	}
	set_fpc_csr(csr.fc_word);
	return(old&mask);
}
