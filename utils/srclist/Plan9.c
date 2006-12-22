#include	"lib9.h"

char*
mygetwd(char *path, int len)
{
	return getwd(path, len);
}
