#include "logfsos.h"
#include "logfs.h"
#include "local.h"

enum {
	FIDMOD = 127
};

int
logfshashulong(void *v, int size)
{
	return (ulong)v % size;
}

/*
 * TO DO: assumes map.c always passes sought key value as b, and value in map as a
 */
static int
compare(void *a, void *b)
{
	Fid *f = a;
	ulong fid = (ulong)b;	/* sic */
//print("fidcompare(%ld, %ld)\n", f->fid, fid);
	return f->fid == fid;
}

static int
allocsize(void *key)
{
	USED(key);
	return sizeof(Fid);
}

static void
fidfree(void *a)
{
	Fid *f = a;
	logfsdrsfree(&f->drs);
}

char *
logfsfidmapnew(FidMap **fidmapp)
{
	return logfsmapnew(FIDMOD, logfshashulong, compare, allocsize, fidfree, fidmapp);
}

int
logfsfidmapclunk(FidMap *m, ulong fid)
{
	Fid *f = logfsfidmapfindentry(m, fid);
	if(f != nil){
		logfsentryclunk(f->entry);
		logfsmapdeleteentry(m, (void *)fid);
		return 1;
	}
	return 0;
}

char *
logfsfidmapnewentry(FidMap *m, ulong fid, Fid **fidmapp)
{
	char *errmsg;
	errmsg = logfsmapnewentry(m, (void*)fid, fidmapp);
	if(errmsg)
		return errmsg;
	if(*fidmapp == nil)
		return nil;
	(*fidmapp)->fid = fid;
	(*fidmapp)->openmode = -1;
	return nil;
}
