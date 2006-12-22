#include <lib9.h>

long
strlen(char *s)
{

	return strchr(s, 0) - s;
}
