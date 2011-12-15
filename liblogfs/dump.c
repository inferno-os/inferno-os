#include "logfsos.h"
#include "logfs.h"
#include "local.h"
#include "fcall.h"

typedef struct WalkState {
	u32int *flashaddrp;
	u32int *lengthp;
	int i;
	int nth;
} WalkState;

static int
walk(void *magic, Extent *e, int hole)
{
	WalkState *s = magic;
	USED(hole);
	if(s->i == s->nth) {
		*s->flashaddrp = e->flashaddr;
		*s->lengthp = e->max - e->min;
		return 0;
	}
	s->i++;
	return 1;
}

char *
logfsserverreadpathextent(LogfsServer *server, u32int path, int nth, u32int *flashaddrp, u32int *lengthp,
	long *blockp, int *pagep, int *offsetp)
{
	Entry *e;
	WalkState s;
	long index;
	e = logfspathmapfinde(server->pathmap, path);
	if(e == nil)
		return logfseunknownpath;
	if(e->perm & DMDIR)
		return Eisdir;
	s.flashaddrp = flashaddrp;
	s.lengthp = lengthp;
	s.i = 0;
	s.nth = nth;
	*lengthp = 0;
	logfsextentlistwalk(e->u.file.extent, walk, &s);
	if(*lengthp) {
		logfsflashaddr2spo(server, *flashaddrp, &index, pagep, offsetp);
		if(*flashaddrp & LogAddr)
			if(index >= server->activelog->unsweptblockindex)
				if(index <= server->activelog->curblockindex)
					*blockp = server->activelog->blockmap[index];
				else
					*blockp = -1;
			else if(server->sweptlog)
				if(index <= server->sweptlog->curblockindex)
					*blockp = server->sweptlog->blockmap[index];
				else
					*blockp = -1;
			else
				*blockp = -1;
		else if(index < server->ndatablocks)
			*blockp = server->datablock[index].block;
		else
			*blockp = -1;
	}
	else {
		*blockp = 0;
		*pagep = 0;
		*offsetp = 0;
	}
	return nil;
}
