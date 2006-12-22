#include <lib9.h>
void
abort(void)
{
	while(*(int*)0)
		;
}
