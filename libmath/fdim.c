#include "lib9.h"
#include "mathi.h"

double
fdim(double x, double y)
{
	if(x>y)
		return x-y;
	else
		return 0;
}

double
fmax(double x, double y)
{
	if(x>y)
		return x;
	else
		return y;
}

double
fmin(double x, double y)
{
	if(x<y)
		return x;
	else
		return y;
}

