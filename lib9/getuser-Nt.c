#include "lib9.h"

char*
getuser(void)
{
	static char *user = 0;
	user = "unknown";
	return user;
}
