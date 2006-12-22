#include "lib9.h"
#include "kernel.h"
#include "draw.h"

/*
 * Default version: treat as file name
 */

Subfont*
_getsubfont(Display *d, char *name)
{
	int fd;
	Subfont *f;

	fd = libopen(name, OREAD);
		
	if(fd < 0){
		_drawprint(2, "getsubfont: can't open %s: %r\n", name);
		return 0;
	}
	/*
	 * unlock display so i/o happens with display released, unless
	 * user is doing his own locking, in which case this could break things.
	 * _getsubfont is called only from string.c and stringwidth.c,
	 * which are known to be safe to have this done.
	 */
	if(d->local == 0)
		unlockdisplay(d);
	f = readsubfont(d, name, fd, d->local == 0);
	if(d->local == 0)
		lockdisplay(d);
	if(f == 0)
		_drawprint(2, "getsubfont: can't read %s: %r\n", name);
	libclose(fd);
	return f;
}
