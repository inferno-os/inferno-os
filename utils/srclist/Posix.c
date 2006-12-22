#include	"lib9.h"
#undef getwd
#undef getwd
#include	<unistd.h>

char*
mygetwd(char *path, int len)
{
	return getcwd(path, len);
}
