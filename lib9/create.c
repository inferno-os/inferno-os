#include "lib9.h"
#include <sys/types.h>
#include <fcntl.h>

int
create(char *f, int mode, int perm)
{
	int m;

	m = 0;
	switch(mode & 3){
	case OREAD:
	case OEXEC:
		m = O_RDONLY;
		break;
	case OWRITE:
		m = O_WRONLY;
		break;
	case ORDWR:
		m = O_RDWR;
		break;
	}
#ifdef _WIN32
	m |= O_CREAT|O_TRUNC|O_BINARY;
#else
	m |= O_CREAT|O_TRUNC;
#endif

	if(perm & DMDIR){
#ifdef _WIN32
		if(_mkdir(f) < 0)
#else
		if(mkdir(f, perm&0777) < 0)
#endif
			return -1;
		perm &= ~DMDIR;
		m &= 3;
	}
	return open(f, m, perm);
}
