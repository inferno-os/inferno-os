#include "lib9.h"
#include "kernel.h"
#include "draw.h"

Font*
openfont(Display *d, char *name)
{
	Font *fnt;
	int fd, i, n;
	char *buf;
	Dir *dir;

	fd = libopen(name, OREAD);
	if(fd < 0)
		return 0;

	if((dir = libdirfstat(fd)) == nil){
    Err0:
		libclose(fd);
		return 0;
	}
	n = dir->length;
	free(dir);
	buf = malloc(n+1);
	if(buf == 0)
		goto Err0;
	buf[n] = 0;
	i = libreadn(fd, buf, n);
	libclose(fd);
	if(i != n){
		free(buf);
		return 0;
	}
	fnt = buildfont(d, buf, name);
	free(buf);
	return fnt;
}
