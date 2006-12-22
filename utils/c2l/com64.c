#include "cc.h"

/*
 * this is machine depend, but it is totally
 * common on all of the 64-bit symulating machines.
 */

/*
 * more machine depend stuff.
 * this is common for 8,16,32,64 bit machines.
 * this is common for ieee machines.
 */
double
convvtof(vlong v)
{
	double d;

	d = v;		/* BOTCH */
	return d;
}

vlong
convftov(double d)
{
	vlong v;


	v = d;		/* BOTCH */
	return v;
}

double
convftox(double d, int et)
{

	if(!typefd[et])
		diag(Z, "bad type in castftox %s", tnames[et]);
	return d;
}

vlong
convvtox(vlong c, int et)
{
	int n;

	n = 8 * ewidth[et];
	c &= MASK(n);
	if(!typeu[et])
		if(c & SIGN(n))
			c |= ~MASK(n);
	return c;
}
