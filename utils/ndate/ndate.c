#include	<lib9.h>

void
main(void)
{
	ulong t;

	t = time(0);
	print("%lud\n", t);
	exits(0);
}
