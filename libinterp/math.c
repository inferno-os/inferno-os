#include "lib9.h"
#include "interp.h"
#include "isa.h"
#include "runt.h"
#include "raise.h"
#include "mathi.h"
#include "mathmod.h"

static union
{
	double x;
	uvlong u;
} bits64;

static union{
	float x;
	unsigned int u;
} bits32;

void
mathmodinit(void)
{
	builtinmod("$Math", Mathmodtab, Mathmodlen);
	fmtinstall('g', gfltconv);
	fmtinstall('G', gfltconv);
	fmtinstall('e', gfltconv);
	/* fmtinstall('E', gfltconv); */	/* avoid clash with ether address */
	fmtinstall(0x00c9, gfltconv);	/* L'É' */
	fmtinstall('f', gfltconv);
}

void
Math_import_int(void *fp)
{
	F_Math_import_int *f;
	int i, n;
	unsigned int u;
	unsigned char *bp;
	int *x;

	f = fp;
	n = f->x->len;
	if(f->b->len!=4*n)
		error(exMathia);
	bp = (unsigned char *)(f->b->data);
	x = (int*)(f->x->data);
	for(i=0; i<n; i++){
		u = *bp++;
		u = (u<<8) | *bp++;
		u = (u<<8) | *bp++;
		u = (u<<8) | *bp++;
		x[i] = u;
	}
}

void
Math_import_real32(void *fp)
{
	F_Math_import_int *f;
	int i, n;
	unsigned int u;
	unsigned char *bp;
	double *x;

	f = fp;
	n = f->x->len;
	if(f->b->len!=4*n)
		error(exMathia);
	bp = (unsigned char *)(f->b->data);
	x = (double*)(f->x->data);
	for(i=0; i<n; i++){
		u = *bp++;
		u = (u<<8) | *bp++;
		u = (u<<8) | *bp++;
		u = (u<<8) | *bp++;
		bits32.u = u;
		x[i] = bits32.x;
	}
}

void
Math_import_real(void *fp)
{
	F_Math_import_int *f;
	int i, n;
	uvlong u;
	unsigned char *bp;
	double *x;

	f = fp;
	n = f->x->len;
	if(f->b->len!=8*n)
		error(exMathia);
	bp = f->b->data;
	x = (double*)(f->x->data);
	for(i=0; i<n; i++){
		u = *bp++;
		u = (u<<8) | *bp++;
		u = (u<<8) | *bp++;
		u = (u<<8) | *bp++;
		u = (u<<8) | *bp++;
		u = (u<<8) | *bp++;
		u = (u<<8) | *bp++;
		u = (u<<8) | *bp++;
		bits64.u = u;
		x[i] = bits64.x;
	}
}

void
Math_export_int(void *fp)
{
	F_Math_export_int *f;
	int i, n;
	unsigned int u;
	unsigned char *bp;
	int *x;

	f = fp;
	n = f->x->len;
	if(f->b->len!=4*n)
		error(exMathia);
	bp = (unsigned char *)(f->b->data);
	x = (int*)(f->x->data);
	for(i=0; i<n; i++){
		u = x[i];
		*bp++ = u>>24;
		*bp++ = u>>16;
		*bp++ = u>>8;
		*bp++ = u;
	}
}

void
Math_export_real32(void *fp)
{
	F_Math_export_int *f;
	int i, n;
	unsigned int u;
	unsigned char *bp;
	double *x;

	f = fp;
	n = f->x->len;
	if(f->b->len!=4*n)
		error(exMathia);
	bp = (unsigned char *)(f->b->data);
	x = (double*)(f->x->data);
	for(i=0; i<n; i++){
		bits32.x = x[i];
		u = bits32.u;
		*bp++ = u>>24;
		*bp++ = u>>16;
		*bp++ = u>>8;
		*bp++ = u;
	}
}

void
Math_export_real(void *fp)
{
	F_Math_export_int *f;
	int i, n;
	uvlong u;
	unsigned char *bp;
	double *x;

	f = fp;
	n = f->x->len;
	if(f->b->len!=8*n)
		error(exMathia);
	bp = (unsigned char *)(f->b->data);
	x = (double*)(f->x->data);
	for(i=0; i<n; i++){
		bits64.x = x[i];
		u = bits64.u;
		*bp++ = u>>56;
		*bp++ = u>>48;
		*bp++ = u>>40;
		*bp++ = u>>32;
		*bp++ = u>>24;
		*bp++ = u>>16;
		*bp++ = u>>8;
		*bp++ = u;
	}
}


void
Math_bits32real(void *fp)
{
	F_Math_bits32real *f;

	f = fp;
	bits32.u = f->b;
	*f->ret = bits32.x;
}

void
Math_bits64real(void *fp)
{
	F_Math_bits64real *f;

	f = fp;
	bits64.u = f->b;
	*f->ret = bits64.x;
}

void
Math_realbits32(void *fp)
{
	F_Math_realbits32 *f;

	f = fp;
	bits32.x = f->x;
	*f->ret = bits32.u;
}

void
Math_realbits64(void *fp)
{
	F_Math_realbits64 *f;

	f = fp;
	bits64.x = f->x;
	*f->ret = bits64.u;
}


void
Math_getFPcontrol(void *fp)
{
	F_Math_getFPcontrol *f;

	f = fp;

	*f->ret = getFPcontrol();
}

void
Math_getFPstatus(void *fp)
{
	F_Math_getFPstatus *f;

	f = fp;

	*f->ret = getFPstatus();
}

void
Math_finite(void *fp)
{
	F_Math_finite *f;

	f = fp;

	*f->ret = finite(f->x);
}

void
Math_ilogb(void *fp)
{
	F_Math_ilogb *f;

	f = fp;

	*f->ret = ilogb(f->x);
}

void
Math_isnan(void *fp)
{
	F_Math_isnan *f;

	f = fp;

	*f->ret = isNaN(f->x);
}

void
Math_acos(void *fp)
{
	F_Math_acos *f;

	f = fp;

	*f->ret = __ieee754_acos(f->x);
}

void
Math_acosh(void *fp)
{
	F_Math_acosh *f;

	f = fp;

	*f->ret = __ieee754_acosh(f->x);
}

void
Math_asin(void *fp)
{
	F_Math_asin *f;

	f = fp;

	*f->ret = __ieee754_asin(f->x);
}

void
Math_asinh(void *fp)
{
	F_Math_asinh *f;

	f = fp;

	*f->ret = asinh(f->x);
}

void
Math_atan(void *fp)
{
	F_Math_atan *f;

	f = fp;

	*f->ret = atan(f->x);
}

void
Math_atanh(void *fp)
{
	F_Math_atanh *f;

	f = fp;

	*f->ret = __ieee754_atanh(f->x);
}

void
Math_cbrt(void *fp)
{
	F_Math_cbrt *f;

	f = fp;

	*f->ret = cbrt(f->x);
}

void
Math_ceil(void *fp)
{
	F_Math_ceil *f;

	f = fp;

	*f->ret = ceil(f->x);
}

void
Math_cos(void *fp)
{
	F_Math_cos *f;

	f = fp;

	*f->ret = cos(f->x);
}

void
Math_cosh(void *fp)
{
	F_Math_cosh *f;

	f = fp;

	*f->ret = __ieee754_cosh(f->x);
}

void
Math_erf(void *fp)
{
	F_Math_erf *f;

	f = fp;

	*f->ret = erf(f->x);
}

void
Math_erfc(void *fp)
{
	F_Math_erfc *f;

	f = fp;

	*f->ret = erfc(f->x);
}

void
Math_exp(void *fp)
{
	F_Math_exp *f;

	f = fp;

	*f->ret = __ieee754_exp(f->x);
}

void
Math_expm1(void *fp)
{
	F_Math_expm1 *f;

	f = fp;

	*f->ret = expm1(f->x);
}

void
Math_fabs(void *fp)
{
	F_Math_fabs *f;

	f = fp;

	*f->ret = fabs(f->x);
}

void
Math_floor(void *fp)
{
	F_Math_floor *f;

	f = fp;

	*f->ret = floor(f->x);
}

void
Math_j0(void *fp)
{
	F_Math_j0 *f;

	f = fp;

	*f->ret = __ieee754_j0(f->x);
}

void
Math_j1(void *fp)
{
	F_Math_j1 *f;

	f = fp;

	*f->ret = __ieee754_j1(f->x);
}

void
Math_log(void *fp)
{
	F_Math_log *f;

	f = fp;

	*f->ret = __ieee754_log(f->x);
}

void
Math_log10(void *fp)
{
	F_Math_log10 *f;

	f = fp;

	*f->ret = __ieee754_log10(f->x);
}

void
Math_log1p(void *fp)
{
	F_Math_log1p *f;

	f = fp;

	*f->ret = log1p(f->x);
}

void
Math_rint(void *fp)
{
	F_Math_rint *f;

	f = fp;

	*f->ret = rint(f->x);
}

void
Math_sin(void *fp)
{
	F_Math_sin *f;

	f = fp;

	*f->ret = sin(f->x);
}

void
Math_sinh(void *fp)
{
	F_Math_sinh *f;

	f = fp;

	*f->ret = __ieee754_sinh(f->x);
}

void
Math_sqrt(void *fp)
{
	F_Math_sqrt *f;

	f = fp;

	*f->ret = __ieee754_sqrt(f->x);
}

void
Math_tan(void *fp)
{
	F_Math_tan *f;

	f = fp;

	*f->ret = tan(f->x);
}

void
Math_tanh(void *fp)
{
	F_Math_tanh *f;

	f = fp;

	*f->ret = tanh(f->x);
}

void
Math_y0(void *fp)
{
	F_Math_y0 *f;

	f = fp;

	*f->ret = __ieee754_y0(f->x);
}

void
Math_y1(void *fp)
{
	F_Math_y1 *f;

	f = fp;

	*f->ret = __ieee754_y1(f->x);
}

void
Math_fdim(void *fp)
{
	F_Math_fdim *f;

	f = fp;

	*f->ret = fdim(f->x, f->y);
}

void
Math_fmax(void *fp)
{
	F_Math_fmax *f;

	f = fp;

	*f->ret = fmax(f->x, f->y);
}

void
Math_fmin(void *fp)
{
	F_Math_fmin *f;

	f = fp;

	*f->ret = fmin(f->x, f->y);
}

void
Math_fmod(void *fp)
{
	F_Math_fmod *f;

	f = fp;

	*f->ret = __ieee754_fmod(f->x, f->y);
}

void
Math_hypot(void *fp)
{
	F_Math_hypot *f;

	f = fp;

	*f->ret = __ieee754_hypot(f->x, f->y);
}

void
Math_nextafter(void *fp)
{
	F_Math_nextafter *f;

	f = fp;

	*f->ret = nextafter(f->x, f->y);
}

void
Math_pow(void *fp)
{
	F_Math_pow *f;

	f = fp;

	*f->ret = __ieee754_pow(f->x, f->y);
}



void
Math_FPcontrol(void *fp)
{
	F_Math_FPcontrol *f;

	f = fp;

	*f->ret = FPcontrol(f->r, f->mask);
}

void
Math_FPstatus(void *fp)
{
	F_Math_FPstatus *f;

	f = fp;

	*f->ret = FPstatus(f->r, f->mask);
}

void
Math_atan2(void *fp)
{
	F_Math_atan2 *f;

	f = fp;

	*f->ret = __ieee754_atan2(f->y, f->x);
}

void
Math_copysign(void *fp)
{
	F_Math_copysign *f;

	f = fp;

	*f->ret = copysign(f->x, f->s);
}

void
Math_jn(void *fp)
{
	F_Math_jn *f;

	f = fp;

	*f->ret = __ieee754_jn(f->n, f->x);
}

void
Math_lgamma(void *fp)
{
	F_Math_lgamma *f;

	f = fp;

	f->ret->t1 = __ieee754_lgamma_r(f->x, &f->ret->t0);
}

void
Math_modf(void *fp)
{
	F_Math_modf *f;
	double ipart;

	f = fp;

	f->ret->t1 = modf(f->x, &ipart);
	f->ret->t0 = ipart;
}

void
Math_pow10(void *fp)
{
	F_Math_pow10 *f;

	f = fp;

	*f->ret = ipow10(f->p);
}

void
Math_remainder(void *fp)
{
	F_Math_remainder *f;

	f = fp;

	*f->ret = __ieee754_remainder(f->x, f->p);
}

void
Math_scalbn(void *fp)
{
	F_Math_scalbn *f;

	f = fp;

	*f->ret = scalbn(f->x, f->n);
}

void
Math_yn(void *fp)
{
	F_Math_yn *f;

	f = fp;

	*f->ret = __ieee754_yn(f->n, f->x);
}


/**** sorting real vectors through permutation vector ****/
/* qsort from coma:/usr/jlb/qsort/qsort.dir/qsort.c on 28 Sep '92
 char* has been changed to uchar*, static internal functions.
 specialized to swapping ints (which are 32-bit anyway in limbo).
 converted uchar* to int* (and substituted 1 for es).
*/

static int
cmp(int *u, int *v, double *x)
{
	return ((x[*u]==x[*v])? 0 : ((x[*u]<x[*v])? -1 : 1));
}

#define swap(u, v) {int t = *(u); *(u) = *(v); *(v) = t;}

#define vecswap(u, v, n) if(n>0){	\
    int i = n;				\
    register int *pi = u;		\
    register int *pj = v;		\
    do {				\
        register int t = *pi;		\
        *pi++ = *pj;			\
        *pj++ = t;			\
    } while (--i > 0);			\
}

#define minimum(x, y) ((x)<=(y) ? (x) : (y))

static int *
med3(int *a, int *b, int *c, double *x)
{	return cmp(a, b, x) < 0 ?
		  (cmp(b, c, x) < 0 ? b : (cmp(a, c, x) < 0 ? c : a ) )
		: (cmp(b, c, x) > 0 ? b : (cmp(a, c, x) < 0 ? a : c ) );
}

void
rqsort(int *a, int n, double *x)
{
	int *pa, *pb, *pc, *pd, *pl, *pm, *pn;
	int  d, r;

	if (n < 7) { /* Insertion sort on small arrays */
		for (pm = a + 1; pm < a + n; pm++)
			for (pl = pm; pl > a && cmp(pl-1, pl, x) > 0; pl--)
				swap(pl, pl-1);
		return;
	}
	pm = a + (n/2);
	if (n > 7) {
		pl = a;
		pn = a + (n-1);
		if (n > 40) { /* On big arrays, pseudomedian of 9 */
			d = (n/8);
			pl = med3(pl, pl+d, pl+2*d, x);
			pm = med3(pm-d, pm, pm+d, x);
			pn = med3(pn-2*d, pn-d, pn, x);
		}
		pm = med3(pl, pm, pn, x); /* On mid arrays, med of 3 */
	}
	swap(a, pm); /* On tiny arrays, partition around middle */
	pa = pb = a + 1;
	pc = pd = a + (n-1);
	for (;;) {
		while (pb <= pc && (r = cmp(pb, a, x)) <= 0) {
			if (r == 0) { swap(pa, pb); pa++; }
			pb++;
		}
		while (pb <= pc && (r = cmp(pc, a, x)) >= 0) {
			if (r == 0) { swap(pc, pd); pd--; }
			pc--;
		}
		if (pb > pc) break;
		swap(pb, pc);
		pb++;
		pc--;
	}
	pn = a + n;
	r = minimum(pa-a,  pb-pa);   vecswap(a,  pb-r, r);
	r = minimum(pd-pc, pn-pd-1); vecswap(pb, pn-r, r);
	if ((r = pb-pa) > 1) rqsort(a, r, x);
	if ((r = pd-pc) > 1) rqsort(pn-r, r, x);
}

void
Math_sort(void*fp)
{
	F_Math_sort *f;
	int	i, pilen, xlen, *p;

	f = fp;

	/* check that permutation contents are in [0,n-1] !!! */
	p = (int*) (f->pi->data);
	pilen = f->pi->len;
	xlen = f->x->len - 1;

	for(i = 0; i < pilen; i++) {
		if((*p < 0) || (xlen < *p))
			error(exMathia);
		p++;
	}

	rqsort( (int*)(f->pi->data), f->pi->len, (double*)(f->x->data));
}


/************ BLAS ***************/

void
Math_dot(void *fp)
{
	F_Math_dot *f;

	f = fp;
	if(f->x->len!=f->y->len)
		error(exMathia);	/* incompatible lengths */
	*f->ret = dot(f->x->len, (double*)(f->x->data), (double*)(f->y->data));
}

void
Math_iamax(void *fp)
{
	F_Math_iamax *f;

	f = fp;

	*f->ret = iamax(f->x->len, (double*)(f->x->data));
}

void
Math_norm2(void *fp)
{
	F_Math_norm2 *f;

	f = fp;

	*f->ret = norm2(f->x->len, (double*)(f->x->data));
}

void
Math_norm1(void *fp)
{
	F_Math_norm1 *f;

	f = fp;

	*f->ret = norm1(f->x->len, (double*)(f->x->data));
}

void
Math_gemm(void *fp)
{
	F_Math_gemm *f = fp;
	int nrowa, ncola, nrowb, ncolb, mn, ld, m, n;
	double *adata = 0, *bdata = 0, *cdata;
	int nota = f->transa=='N';
	int notb = f->transb=='N';
	if(nota){
		nrowa = f->m;
		ncola = f->k;
	}else{
		nrowa = f->k;
		ncola = f->m;
	}
	if(notb){
		nrowb = f->k;
		ncolb = f->n;
	}else{
		nrowb = f->n;
		ncolb = f->k;
	}
	if(     (!nota && f->transa!='C' && f->transa!='T') ||
		(!notb && f->transb!='C' && f->transb!='T') ||
		(f->m < 0 || f->n < 0 || f->k < 0) ){
		error(exMathia);
	}
	if(f->a != H){
		mn = f->a->len;
		adata = (double*)(f->a->data);
		ld = f->lda;
		if(ld<nrowa || ld*(ncola-1)>mn)
			error(exBounds);
	}
	if(f->b != H){
		mn = f->b->len;
		ld = f->ldb;
		bdata = (double*)(f->b->data);
		if(ld<nrowb || ld*(ncolb-1)>mn)
			error(exBounds);
	}
	m = f->m;
	n = f->n;
	mn = f->c->len;
	cdata = (double*)(f->c->data);
	ld = f->ldc;
	if(ld<m || ld*(n-1)>mn)
		error(exBounds);

	gemm(f->transa, f->transb, f->m, f->n, f->k, f->alpha,
		adata, f->lda, bdata, f->ldb, f->beta, cdata, f->ldc);
}
