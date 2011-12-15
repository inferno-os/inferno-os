#include "logfsos.h"
#include "logfs.h"
#include "local.h"

char *
logfsserveropen(LogfsServer *server, u32int fid, uchar mode, Qid *qid)
{
	Fid *f;
	Entry *e;
	ulong modemask;

	if(server->trace > 1)
		print("logfsserveropen(%ud, %d)\n",  fid, mode);
	f = logfsfidmapfindentry(server->fidmap, fid);
	if(f == nil)
		return logfsebadfid;
	if(f->openmode >= 0)
		return logfsefidopen;
	e = f->entry;
	SET(modemask);
	switch(mode & 3) {
	case OEXEC:
		modemask = DMEXEC;
		break;
	case OREAD:
		modemask = DMREAD;
		break;
	case OWRITE:
		modemask = DMWRITE;
		break;
	case ORDWR:
		modemask = DMWRITE | DMREAD;
		break;
	}
	if(e->qid.type & QTDIR) {
		if((modemask & DMWRITE) != 0 || (mode & (ORCLOSE | OTRUNC)) != 0)
			return Eperm;
	}
	else {
		if(mode & OTRUNC)
			modemask |= DMWRITE;
		if((mode & ORCLOSE) != 0 && !logfsuserpermcheck(server, e->parent, f, DMWRITE))
			return Eperm;
	}
	if(!logfsuserpermcheck(server, e, f, modemask))
		return Eperm;
	if((e->qid.type & QTDIR) == 0 && (mode & OTRUNC) != 0 && (e->perm & DMAPPEND) == 0 && e->u.file.length != 0) {
		LogMessage s;
		char *errmsg;
		s.type = LogfsLogTtrunc;
		s.path = e->qid.path;
		s.u.trunc.mtime = logfsnow();
		s.u.trunc.cvers = e->u.file.cvers + 1;
		s.u.trunc.muid = logfsisfindidfromname(server->is, f->uname);
		errmsg = logfslog(server, 1, &s);
		if(errmsg)
			return errmsg;
		e->muid = s.u.trunc.muid;
		e->mtime = s.u.trunc.mtime;
		e->qid.vers++;
		e->u.file.cvers = s.u.trunc.cvers;
		/*
		 * zap all data and extents
		 */
		logfsextentlistwalk(e->u.file.extent, logfsunconditionallymarkfreeanddirty, server);
		logfsextentlistreset(e->u.file.extent);
		e->u.file.length = 0;
	}
	f->openmode = mode;
	*qid = e->qid;
	return nil;
}
