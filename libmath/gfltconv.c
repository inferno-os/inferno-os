#include "lib9.h"
#include "mathi.h"
extern char	*dtoa(double, int, int, int *, int *, char **);
extern void	freedtoa(char*);
extern int	_fmtcpy(Fmt*, void*, int, int);

enum
{
	NONE	= -1000,
	FDIGIT	= 20,
	FDEFLT	= 6,
	NSIGNIF	= 17
};

int
gfltconv(Fmt *f)
{
	int flags = f->flags;
	int precision;
	int fmt = f->r;
	double d;
	int echr, exponent, sign, ndig, nout, i;
	char *digits, *edigits, ebuf[32], *eptr;
	char out[64], *pout;

	d = va_arg(f->args, double);
	echr = 'e';
	precision = FDEFLT;
	if(f->flags & FmtPrec)
		precision = f->prec;
	if(precision > FDIGIT)
		precision = FDIGIT;
	switch(fmt){
	case 'f':
		digits = dtoa(d, 3, precision, &exponent, &sign, &edigits);
		break;
	case 0x00c9:	/* L'É' */
	case 'E':
		echr = 'E';
		fmt = 'e';
		/* fall through */
	case 'e':
		digits = dtoa(d, 2, 1+precision, &exponent, &sign, &edigits);
		break;
	case 'G':
		echr = 'E';
		/* fall through */
	default:
	case 'g':
		if((flags&(FmtWidth|FmtPrec)) == 0){
			g_fmt(out, d, echr);
			f->flags &= FmtWidth|FmtLeft;
			return _fmtcpy(f, out, strlen(out), strlen(out));
		}
		if (precision > 0)
			digits = dtoa(d, 2, precision, &exponent, &sign, &edigits);
		else {
			digits = dtoa(d, 0, precision, &exponent, &sign, &edigits);
			precision = edigits - digits;
			if (exponent > precision && exponent <= precision + 4)
				precision = exponent;
			}
		if(exponent >= -3 && exponent <= precision){
			fmt = 'f';
			precision -= exponent;
		}else{
			fmt = 'e';
			--precision;
		}
		break;
	}
	if (exponent == 9999) {
		/* Infinity or Nan */
		precision = 0;
		exponent = edigits - digits;
		fmt = 'f';
	}
	ndig = edigits-digits;
	if((f->r=='g' || f->r=='G') && !(flags&FmtSharp)){ /* knock off trailing zeros */
		if(fmt == 'f'){
			if(precision+exponent > ndig) {
				precision = ndig - exponent;
				if(precision < 0)
					precision = 0;
			}
		}
		else{
			if(precision > ndig-1) precision = ndig-1;
		}
	}
	eptr = ebuf;
	if(fmt != 'f'){					/* exponent */
		for(i=exponent<=0?1-exponent:exponent-1; i; i/=10)
			*eptr++ = '0' + i%10;
		while(eptr<ebuf+2) *eptr++ = '0';
	}
	pout = out;
	if(sign) *pout++ = '-';
	else if(flags&FmtSign) *pout++ = '+';
	else if(flags&FmtSpace) *pout++ = ' ';
	if(fmt == 'f'){
		for(i=0; i<exponent; i++) *pout++ = i<ndig?digits[i]:'0';
		if(i == 0) *pout++ = '0';
		if(precision>0 || flags&FmtSharp) *pout++ = '.';
		for(i=0; i!=precision; i++)
			*pout++ = 0<=i+exponent && i+exponent<ndig?digits[i+exponent]:'0';
	}
	else{
		*pout++ = digits[0];
		if(precision>0 || flags&FmtSharp) *pout++ = '.';
		for(i=0; i!=precision; i++) *pout++ = i<ndig-1?digits[i+1]:'0';
	}
	if(fmt != 'f'){
		*pout++ = echr;
		*pout++ = exponent<=0?'-':'+';
		while(eptr>ebuf) *pout++ = *--eptr;
	}
	*pout = 0;
	freedtoa(digits);
	f->flags &= FmtWidth|FmtLeft;
	nout = pout-out;
	return _fmtcpy(f, out, nout, nout);
}
