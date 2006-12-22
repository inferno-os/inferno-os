/*
 *  Test device
 */
#include	"u.h"
#include	"../port/lib.h"
#include	"mem.h"
#include	"dat.h"
#include	"fns.h"
#include	"io.h"
#include	"../port/error.h"
#include	"libcrypt.h"

#include <kernel.h>

#define	DEBUG	0

extern void _startup(void);

enum{
	Qdir,
	Qkt5sum,
	Qkerndate,
};

static
Dirtab testtab[]={
	".",			{ Qdir, 0, QTDIR},	0,	0555,
	"kt5sum",		{ Qkt5sum },		0,	0444,
	"kerndate",	{ Qkerndate },		0,	0444,
};


void ktsum(char *digest)
{
	uchar rawdigest[MD5dlen+1];
	int i;
	void *start =  _startup;
	ulong size = (ulong)etext - (ulong) start;
	md5(start, size, rawdigest, nil);
	for (i=0; i<MD5dlen; i++)
		sprint(&digest[2*i], "%2.2x", rawdigest[i]);
	digest[MD5dlen*2] = 0;
	strcat(digest, "\n");
}

static Chan*
testattach(char *spec)
{
	return devattach('Z', spec);
}

static Walkqid*
testwalk(Chan *c, Chan *nc, char **name, int nname)
{
	return devwalk(c, nc, name, nname, testtab, nelem(testtab), devgen);
}

static int
teststat(Chan *c, uchar *db, int n)
{
	return devstat(c, db, n, testtab, nelem(testtab), devgen);
}

static Chan*
testopen(Chan *c, int omode)
{
	return devopen(c, omode, testtab, nelem(testtab), devgen);
}

static void
testclose(Chan *)
{
}

extern ulong kerndate;

static long
testread(Chan* c, void* a, long n, vlong offset)
{
	char digest[MD5dlen*2+1];
	switch ((ulong)c->qid.path) {
	case Qdir:
		return devdirread(c, a, n, testtab, nelem(testtab), devgen);
	case Qkt5sum:
		ktsum(digest);
		return readstr(offset, a, n, digest);
	case Qkerndate:
		sprint(digest, "%ld\n", kerndate);
		return readstr(offset, a, n, digest);
	default:
		n = 0;
		break;
	}
	return n;
}
	

static long
testwrite(Chan*, void*, long, vlong)
{
	error(Ebadusefd);
	return 0;
}

Dev testdevtab = {
	'Z',
	"test",

	devreset,
	devinit,
	devshutdown,
	testattach,
	testwalk,
	teststat,
	testopen,
	devcreate,
	testclose,
	testread,
	devbread,
	testwrite,
	devbwrite,
	devremove,
	devwstat,
};

