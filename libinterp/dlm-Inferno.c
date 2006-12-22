#include "lib9.h"
#include "isa.h"
#include "interp.h"
#include "raise.h"
#include "pool.h"
#include "kernel.h"
#include "dynld.h"

#define	DBG	if(1) print

extern Dynobj* dynld(int);
extern char*	enverror(void);

typedef struct{char *name; long sig; void (*fn)(void*); int size; int np; uchar map[16];} Runtab;

static void*
addr(char *pre, char *suf, Dynobj *o, ulong sig)
{
	char buf[64];

	if(o == nil || strlen(pre)+strlen(suf) > 64-1)
		return nil;
	snprint(buf, sizeof(buf), "%s%s", pre, suf);
	return dynimport(o, buf, sig);
}

Module*
newdyncode(int fd, char *path, Dir *dir)
{
	Module *m;
	void *v;
	Runtab *r;
	Dynobj *o;
	char *name;

	DBG("module path is %s\n", path);
	m = nil;
	o = dynld(fd);
	if(o == nil){
		DBG("%s\n", enverror());
		goto Error;
	}
	v = addr("XXX", "module", o, signof(char*));
	if(v == nil)
		goto Error;
	name = *(char**)v;
	DBG("module name is %s\n", name);
	r = addr(name, "modtab", o, signof(Runtab[]));
	if(r == nil)
		goto Error;
	m = builtinmod(name, r, 0);
	m->rt = DYNMOD;
	m->dev = dir->dev;
	m->dtype = dir->type;
	m->qid = dir->qid;
	m->mtime = dir->mtime;
	m->path = strdup(path);
	if(m->path == nil)
		goto Error;
	m->dlm = o;
	DBG("module base is 0x%p\n", o->base);
	return m;
Error:
	if(o != nil)
		dynobjfree(o);
	if(m != nil)
		freemod(m);
	return nil;
}

void
freedyncode(Module *m)
{
	dynobjfree(m->dlm);
}

static void
callfn(Module *m, char *fn)
{
	void *v, (*f)(void);

	if(m->ref != 1)
		return;
	v = addr(m->name, fn, m->dlm, signof(*f));
	if(v != nil){
		f = v;
		(*f)();
	}
}

void
newdyndata(Modlink *ml)
{
	callfn(ml->m, "init");
}

void
freedyndata(Modlink *ml)
{
	callfn(ml->m, "end");
}
