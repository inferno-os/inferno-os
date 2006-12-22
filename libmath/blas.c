#include "lib9.h"
#include "mathi.h"

double
dot(int n, double *x, double *y)
{
	double	sum = 0;
	if (n <= 0) 
		return 0;
	while (n--) {
		sum += *x++ * *y++;
	}
	return sum;
}


int
iamax(int n, double *x)
{
	int	i, m;
	double	xm, a;
	if (n <= 0) 
		return 0;
	m = 0;
	xm = fabs(*x);
	for (i = 1; i < n; i++) {
		a = fabs(*++x);
		if (xm < a) {
			m = i;
			xm = a;
		}
	}
	return m;
}


double
norm1(int n, double *x)
{
	double	sum = 0;
	if (n <= 0) 
		return 0;
	while (n--) {
		sum += fabs(*x++);
	}
	return sum;
}


double
norm2(int n, double *x)
{
	double	sum = 0;
	if (n <= 0) 
		return 0;
	while (n--) {
		sum += *x * *x;
		x++;
	}
	return sum;
}
