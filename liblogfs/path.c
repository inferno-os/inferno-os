#include "logfsos.h"
#include "logfs.h"
#include "local.h"

enum {
	PATHMOD = 127
};

static int
compare(void *a, void *b)
{
	Path *f = a;
	ulong path = (ulong)b;	/* sic */
	return f->path == path;
}

static int
allocsize(void *key)
{
	USED(key);
	return sizeof(Path);
}

char *
logfspathmapnew(PathMap **pathmapp)
{
	return logfsmapnew(PATHMOD, logfshashulong, compare, allocsize, nil, pathmapp);
}

char *
logfspathmapnewentry(PathMap *m, ulong path, Entry *e, Path **pathmapp)
{
	char *errmsg;
	errmsg = logfsmapnewentry(m, (void*)path, pathmapp);
	if(errmsg)
		return errmsg;
	if(*pathmapp == nil)
		return nil;
	(*pathmapp)->path = path;
	(*pathmapp)->entry = e;
	return nil;
}

Entry *
logfspathmapfinde(PathMap *m, ulong path)
{
	Path *p;
	p = logfspathmapfindentry(m, path);
	return p ? p->entry : nil;
}
