#include "fpi.h"

/*
 * the following routines depend on memory format, not the machine
 */

void
fpis2i(Internal *i, void *v)
{
	Single *s = v;

	i->s = (*s & 0x80000000) ? 1: 0;
	if((*s & ~0x80000000) == 0){
		SetZero(i);
		return;
	}
	i->e = ((*s>>23) & 0x00FF) - SingleExpBias + ExpBias;
	i->h = (*s & 0x007FFFFF)<<(1+NGuardBits);
	i->l = 0;
	if(i->e)
		i->h |= HiddenBit;
	else
		i->e++;
}

void
fpid2i(Internal *i, void *v)
{
	Double *d = v;

	i->s = (d->h & 0x80000000) ? 1: 0;
	i->e = (d->h>>20) & 0x07FF;
	i->h = ((d->h & 0x000FFFFF)<<(4+NGuardBits))|((d->l>>25) & 0x7F);
	i->l = (d->l & 0x01FFFFFF)<<NGuardBits;
	if(i->e)
		i->h |= HiddenBit;
	else
		i->e++;
}

void
fpiw2i(Internal *i, void *v)
{
	Word w, word = *(Word*)v;
	int e;

	if(word < 0){
		i->s = 1;
		word = -word;
	}
	else
		i->s = 0;
	if(word == 0){
		SetZero(i);
		return;
	}
	if(word > 0){
		for (e = 0, w = word; w; w >>= 1, e++)
			;
	} else
		e = 32;
	if(e > FractBits){
		i->h = word>>(e - FractBits);
		i->l = (word & ((1<<(e - FractBits)) - 1))<<(2*FractBits - e);
	}
	else {
		i->h = word<<(FractBits - e);
		i->l = 0;
	}
	i->e = (e - 1) + ExpBias;
}

void
fpii2s(void *v, Internal *i)
{
	int e, n;
	unsigned long long m, r, half;
	Single *s = (Single*)v;

	*s = i->s ? 0x80000000: 0;
	if(IsWeird(i)){
		*s |= IsNaN(i) ? 0x7FC00000: 0x7F800000;
		return;
	}
	m = ((unsigned long long)i->h<<28) | i->l;
	if(m == 0)
		return;
	e = i->e - ExpBias + SingleExpBias;
	while((m & (1ULL<<55)) == 0){
		m <<= 1;
		e--;
	}
	/* round to nearest even, at 24 bits or fewer if denormal */
	n = 32;
	if(e < 1){
		n += 1 - e;
		e = 1;
	}
	if(n > 57)
		n = 57;
	r = m & ((1ULL<<n) - 1);
	half = 1ULL<<(n-1);
	m >>= n;
	if(r > half || (r == half && (m & 1)))
		m++;
	m += (unsigned long long)(e-1)<<23;
	if(m >= (SingleExpMax<<23))
		m = SingleExpMax<<23;
	*s |= m;
}

void
fpii2d(void *v, Internal *i)
{
	Double *d = (Double*)v;

	fpiround(i);
	if(i->h & HiddenBit)
		i->h &= ~HiddenBit;
	else
		i->e--;
	i->l = ((i->h & GuardMask)<<25)|(i->l>>NGuardBits);
	i->h >>= NGuardBits;
	d->h = i->s ? 0x80000000: 0;
	d->h |= (i->e<<20)|((i->h & 0x00FFFFFF)>>4);
	d->l = (i->h<<28)|i->l;
}

void
fpii2w(Word *word, Internal *i)
{
	Word w;
	int e;

	fpiround(i);
	e = (i->e - ExpBias) + 1;
	if(e <= 0)
		w = 0;
	else if(e > 31)
		w = 0x7FFFFFFF;
	else if(e > FractBits)
		w = (i->h<<(e - FractBits))|(i->l>>(2*FractBits - e));
	else
		w = i->h>>(FractBits-e);
	if(i->s)
		w = -w;
	*word = w;
}
