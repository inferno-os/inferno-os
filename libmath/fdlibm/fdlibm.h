/* derived from /netlib/fdlibm */
#include "lib9.h"

/* @(#)fdlibm.h 1.5 95/01/18 */
/*
 * ====================================================
 * Copyright (C) 1993 by Sun Microsystems, Inc. All rights reserved.
 *
 * Developed at SunSoft, a Sun Microsystems, Inc. business.
 * Permission to use, copy, modify, and distribute this
 * software is freely granted, provided that this notice 
 * is preserved.
 * ====================================================
 */


#ifdef USE_FPdbleword
#define __HI(x) ((FPdbleword*)&x)->hi
#define __LO(x) ((FPdbleword*)&x)->lo
#define __HIp(x) ((FPdbleword*)x)->hi
#define __LOp(x) ((FPdbleword*)x)->lo
#else
#ifdef __LITTLE_ENDIAN
#define __HI(x) *(1+(int*)&x)
#define __LO(x) *(int*)&x
#define __HIp(x) *(1+(int*)x)
#define __LOp(x) *(int*)x
#else
#define __HI(x) *(int*)&x
#define __LO(x) *(1+(int*)&x)
#define __HIp(x) *(int*)x
#define __LOp(x) *(1+(int*)x)
#endif
#endif

/*
 * ANSI/POSIX
 */
extern double acos(double);
extern double asin(double);
extern double atan(double);
extern double atan2(double, double);
extern double cos(double);
extern double sin(double);
extern double tan(double);

extern double cosh(double);
extern double sinh(double);
extern double tanh(double);

extern double exp(double);
extern double frexp(double, int *);
extern double ldexp(double, int);
extern double log(double);
extern double log10(double);
extern double modf(double, double *);

extern double pow(double, double);
extern double sqrt(double);

extern double ceil(double);
extern double fabs(double);
extern double floor(double);
extern double fmod(double, double);

extern double erf(double);
extern double erfc(double);
extern double gamma(double);
extern double hypot(double, double);
extern int finite(double);
extern double j0(double);
extern double j1(double);
extern double jn(int, double);
extern double lgamma(double);
extern double y0(double);
extern double y1(double);
extern double yn(int, double);

extern double acosh(double);
extern double asinh(double);
extern double atanh(double);
extern double cbrt(double);
extern double logb(double);
extern double nextafter(double, double);
extern double remainder(double, double);
extern double scalb(double, double);

/*
 * IEEE Test Vector
 */
extern double significand(double);

/*
 * Functions callable from C, intended to support IEEE arithmetic.
 */
extern double copysign(double, double);
extern int ilogb(double);
extern double rint(double);
extern double scalbn(double, int);

/*
 * BSD math library entry points
 */
extern double expm1(double);
extern double log1p(double);

/*
 * Reentrant version of gamma & lgamma; passes signgam back by reference
 * as the second argument; user must allocate space for signgam.
 */
#ifdef _REENTRANT
extern double gamma_r(double, int *);
extern double lgamma_r(double, int *);
#endif	/* _REENTRANT */

/* ieee style elementary functions */
extern double __ieee754_sqrt(double);			
extern double __ieee754_acos(double);			
extern double __ieee754_acosh(double);			
extern double __ieee754_log(double);			
extern double __ieee754_atanh(double);			
extern double __ieee754_asin(double);			
extern double __ieee754_atan2(double,double);			
extern double __ieee754_exp(double);
extern double __ieee754_cosh(double);
extern double __ieee754_fmod(double,double);
extern double __ieee754_pow(double,double);
extern double __ieee754_lgamma_r(double,int *);
extern double __ieee754_gamma_r(double,int *);
extern double __ieee754_lgamma(double);
extern double __ieee754_gamma(double);
extern double __ieee754_log10(double);
extern double __ieee754_sinh(double);
extern double __ieee754_hypot(double,double);
extern double __ieee754_j0(double);
extern double __ieee754_j1(double);
extern double __ieee754_y0(double);
extern double __ieee754_y1(double);
extern double __ieee754_jn(int,double);
extern double __ieee754_yn(int,double);
extern double __ieee754_remainder(double,double);
extern int    __ieee754_rem_pio2(double,double*);
extern double __ieee754_scalb(double,int);

/* fdlibm kernel function */
extern double __kernel_standard(double,double,int);	
extern double __kernel_sin(double,double,int);
extern double __kernel_cos(double,double);
extern double __kernel_tan(double,double,int);
extern int    __kernel_rem_pio2(double*,double*,int,int,int,const int*);
