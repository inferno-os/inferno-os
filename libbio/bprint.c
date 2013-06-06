#include	"lib9.h"
#include	<bio.h>

int
Bprint(Biobuf *bp, char *fmt, ...)
{
	va_list arg;
	int n;

	va_start(arg, fmt);
	n = Bvprint(bp, fmt, arg);
	va_end(arg);
	return n;
}
