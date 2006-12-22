#include	"dat.h"
#include	"fns.h"
#include	"error.h"
#include	<a.out.h>
#include	<dynld.h>

/*
 * channel-based kernel interface to dynld, for use by devdynld.c,
 * libinterp/dlm.c, and possibly others
 */

static long
readfc(void *a, void *buf, long nbytes)
{
	Chan *c = a;

	if(waserror())
		return -1;
	nbytes = devtab[c->type]->read(c, buf, nbytes, c->offset);
	poperror();
	return nbytes;
}

static vlong
seekfc(void *a, vlong off, int t)
{
	Chan *c = a;

	if(c->qid.type & QTDIR || off < 0)
		return -1;	/* won't happen */
	switch(t){
	case 0:
		lock(c);
		c->offset = off;
		unlock(c);
		break;
	case 1:
		lock(c);
		off += c->offset;
		c->offset = off;
		unlock(c);
		break;
	case 2:
		return -1;	/* not needed */
	}
	return off;
}

static void
errfc(char *s)
{
	kstrcpy(up->env->errstr, s, ERRMAX);
}

Dynobj*
kdynloadchan(Chan *c, Dynsym *tab, int ntab)
{
	return dynloadgen(c, readfc, seekfc, errfc, tab, ntab, 0);
}

int
kdynloadable(Chan *c)
{
	return dynloadable(c, readfc, seekfc);
}
