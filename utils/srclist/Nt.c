#include	<windows.h>  
#include	"lib9.h"

char*
mygetwd(char *path, int len)
{
	return getcwd(path, len);
}
