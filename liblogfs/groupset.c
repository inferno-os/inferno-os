#include "lib9.h"
#include "logfs.h"
#include "local.h"

struct GroupSet {
	int maxentries;
	int nentries;
	Group **entry;
};

char *
logfsgroupsetnew(GroupSet **gsp)
{
	GroupSet *gs = logfsrealloc(nil, sizeof(*gs));
	if(gs == nil)
		return Enomem;
	gs->entry = logfsrealloc(nil, sizeof(Group *));
	if(gs->entry == nil) {
		logfsfreemem(gs);
		return Enomem;
	}
	gs->maxentries = 1;		/* most groups have one member */
	gs->nentries = 0;
	*gsp = gs;
	return nil;
}

void
logfsgroupsetfree(GroupSet **gsp)
{
	GroupSet *gs = *gsp;
	if(gs) {
		logfsfreemem(gs->entry);
		logfsfreemem(gs);
		*gsp = nil;
	}
}

int
logfsgroupsetadd(GroupSet *gs, Group *g)
{
	int x;
	for(x = 0; x < gs->nentries; x++)
		if(gs->entry[x] == g)
			return 1;
	if(gs->nentries >= gs->maxentries) {
		Group **ne = logfsrealloc(gs->entry, sizeof(Group *) + (gs->maxentries * 2));
		if(ne)
			return 0;
		gs->entry = ne;
		gs->maxentries *= 2;
	}
	gs->entry[gs->nentries++] = g;
	return 1;
}

int
logfsgroupsetremove(GroupSet *gs, Group *g)
{
	int x;
	for(x = 0; x < gs->nentries; x++)
		if(gs->entry[x] == g)
			break;
	if(x == gs->nentries)
		return 0;
	gs->nentries--;
	memmove(&gs->entry[x], &gs->entry[x + 1], sizeof(Group *) * (gs->nentries - x));
	return 1;
}

int
logfsgroupsetwalk(GroupSet *gs, LOGFSGROUPSETWALKFN *func, void *magic)
{
	int x;
	for(x = 0; x < gs->nentries; x++) {
		int rv = (*func)(magic, gs->entry[x]);
		if(rv <= 0)
			return rv;
	}
	return 1;
}

int
logfsgroupsetismember(GroupSet *gs, Group *g)
{
	int x;
	for(x = 0; x < gs->nentries; x++)
		if(gs->entry[x] == g)
			return 1;
	return 0;
}
