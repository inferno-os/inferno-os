#include "lib9.h"
#include "logfs.h"
#include "local.h"

int
logfsuserpermcheck(LogfsServer *s, Entry *e, Fid *f, ulong permmask)
{
	if(s->openflags & LogfsOpenFlagNoPerm)
		return 1;
	if((e->perm & permmask) == permmask)
		/* the whole world can do this */
		return 1;
	if(((e->perm >> 6) & permmask) == permmask) {
		/* maybe we're the owner */
		char *uname = logfsisfindnamefromid(s->is, e->uid);
		if(uname == f->uname)
			return 1;
	}
	if(((e->perm >> 3) & permmask) == permmask) {
		/* maybe we're in the group */
		Group *g = logfsisfindgroupfromid(s->is, e->gid);
		return g && logfsisgroupunameismember(s->is, g, f->uname);
	}
	return 0;
}
