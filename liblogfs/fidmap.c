#include "lib9.h"
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

static int
compare(Fid *f, ulong fid)
{
//print("fidcompare(%ld, %ld)\n", f->fid, fid);
	return f->fid == fid;
}

static int
allocsize(void *key)
{
	USED(key);
	return sizeof(Fid);
}

void
fidfree(Fid *f)
{
	logfsdrsfree(&f->drs);
}

char *
logfsfidmapnew(FidMap **fidmapp)
{
	return logfsmapnew(FIDMOD, logfshashulong, (int (*)(void *, void *))compare, allocsize, (void (*)(void *))fidfree, fidmapp);
}

int
logfsfidmapclunk(FidMap *m, ulong fid)
{
	Fid *f = logfsfidmapfindentry(m, fid);
	if(f) {
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
	errmsg = logfsmapnewentry(m, (void *)fid, fidmapp);
	if(errmsg)
		return errmsg;
	if(*fidmapp == nil)
		return nil;
	(*fidmapp)->fid = fid;
	(*fidmapp)->openmode = -1;
	return nil;
}

