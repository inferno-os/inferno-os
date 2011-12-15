#include "logfsos.h"
#include "logfs.h"
#include "fcall.h"
#include "local.h"

char *
logfsserverwalk(LogfsServer *server, u32int fid, u32int newfid, ushort nwname, char **wname, ushort *nwqid, Qid *wqid)
{
	ushort i;
	Entry *e;
	char *errmsg;
	Fid *f;
	if(server->trace > 1) {
		print("logfsserverwalk(%ud, %ud, %ud, \"", fid, newfid, nwname);
		for(i = 0; i < nwname; i++) {
			if(i > 0)
				print("/");
			print("%s", wname[i]);
		}
		print("\")\n");
	}
	f = logfsfidmapfindentry(server->fidmap, fid);
	if(f == nil)
		return logfsebadfid;
	if(f->openmode >= 0)
		return logfsefidopen;
	errmsg = nil;
	e = f->entry;
	if(e->deadandgone)
		return Eio;
	for(i = 0; i < nwname; i++) {
		Entry *se;
		/*
		 * deal with ..
		 */
		if(strcmp(wname[i], "..") == 0)
			se = e->parent;
		else if(strcmp(wname[i], ".") == 0)
			se = e;
		else {
			/*
			 * is it a directory?
			 */
			if((e->qid.type & QTDIR) == 0) {
				errmsg = Enotdir;
				break;
			}
			/*
			 * can we walk the walk, or just talk the protocol?
			 */
			if(!logfsuserpermcheck(server, e, f, DMEXEC)) {
				errmsg = Eperm;
				break;
			}
			/*
			 * search current entry for nwname[i]
			 */
			for(se = e->u.dir.list; se; se = se->next)
				if(strcmp(se->name, wname[i]) == 0)
					break;
			if(se == nil) {
				errmsg = Enonexist;
				break;
			}
		}
		wqid[i] = se->qid;
		e = se;
	}
	if(nwname > 0 && i == 0) {
		/*
		 * fell at the first fence
		 */
		return errmsg;
	}
	*nwqid = i;
	if(i < nwname)
		return nil;
	/*
	 * new fid required?
	 */
	if(fid != newfid) {
		Fid *newf;
		char *errmsg;
		errmsg = logfsfidmapnewentry(server->fidmap, newfid, &newf);
		if(errmsg)
			return errmsg;
		if(newf == nil)
			return logfsefidinuse;
		newf->entry = e;
		newf->uname = f->uname;
		e->inuse++;
	}
	else {
		/*
		 * this may now be right
		 * 1. increment reference on new entry first in case e and f->entry are the same
		 * 2. clunk the old one in case this has the effect of removing an old entry
		 * 3. dump the directory read state if the entry has changed
		 */
		e->inuse++;
		logfsentryclunk(f->entry);
		if(e != f->entry)
			logfsdrsfree(&f->drs);
		f->entry = e;
	}
	return nil;
}

