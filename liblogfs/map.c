#include "lib9.h"
#include "logfs.h"
#include "local.h"

typedef struct MapNode {
	struct MapNode *next;
	uchar e[1];	// entry goes here, inline
} MapNode;

struct Map {
	int size;
	int (*hash)(void *key, int size);
	int (*compare)(void *entry, void *key);
	int (*allocsize)(void *key);
	void (*free)(void *entry);
	MapNode *head[1];
};

char *
logfsmapnew(int size, int (*hash)(void *key, int size), int (*compare)(void *entry, void *key), int (*allocsize)(void *key), void (*free)(void *), Map **mapp)
{
	Map *p;
	*mapp = p = logfsrealloc(nil, sizeof(Map) + (size - 1) * sizeof(MapNode *));
	if(p == nil)
		return Enomem;
	p->size = size;
	p->hash = hash;
	p->compare = compare;
	p->allocsize = allocsize;
	p->free = free;
	return nil;
}

void
logfsmapfree(FidMap **mp)
{
	FidMap *m;
	int i;

	m = *mp;
	if(m == nil)
		return;

	for(i = 0; i < m->size; i++) {
		MapNode *n, *next;
		n = m->head[i];
		while(n) {
			next = n->next;
			if(m->free)
				(*m->free)(n->e);
			logfsfreemem(n);
			n = next;
		}
	}
	logfsfreemem(m);
	*mp = nil;
}

static char *
find(FidMap *m, void *key, int create, void **ep)
{
	MapNode *n;
	int i;
	i = (*m->hash)(key, m->size);
	n = m->head[i];
	while(n && !(*m->compare)(n->e, key))
		n = n->next;
	if(n) {
		if(create) {
			*ep = nil;
			return nil;
		}
		*ep = n->e;
		return nil;
	}
	if(!create) {
		*ep = nil;
		return nil;
	}
	n = logfsrealloc(nil, (*m->allocsize)(key) + sizeof(MapNode *));
	if(n == nil) {
		*ep = nil;
		return Enomem;
	}
	n->next = m->head[i];
	m->head[i] = n;
	*ep = n->e;
	return nil;
}

void *
logfsmapfindentry(Map *m, void *key)
{
	void *rv;
	find(m, key, 0, &rv);
	return rv;
}

char *
logfsmapnewentry(Map *m, void *key, void **entryp)
{
	return find(m, key, 1, entryp);
}

int
logfsmapdeleteentry(Map *m, void *key)
{
	MapNode **np, *n;
	np = &m->head[(*m->hash)(key, m->size)];
	while((n = *np) && !(*m->compare)(n->e, key))
		np = &n->next;
	if(n) {
		*np = n->next;
		if(m->free)
			(*m->free)(n->e);
		logfsfreemem(n);
		return 1;
	}
	return 0;		// not there
}

int
logfsmapwalk(Map *m, int (*func)(void *magic, void *), void *magic)
{
	int x;
	MapNode *n;

	for(x = 0; x < m->size; x++)
		for(n = m->head[x]; n; n = n->next) {
			int rv = (*func)(magic, n->e);
			if(rv <= 0)
				return rv;
		}
	return 1;
}

