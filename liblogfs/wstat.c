#include "logfsos.h"
#include "logfs.h"
#include "fcall.h"
#include "local.h"

char *
logfsserverwstat(LogfsServer *server, u32int fid, uchar *stat, ushort nstat)
{
	Fid *f;
	uchar *p;
	ushort len;
	uchar *mep;
	Qid qid;
	u32int perm, mtime;
	uvlong length;
	char *name, *uname, *gname, *muname;
	int qiddonttouch, permdonttouch, mtimedonttouch, lengthdonttouch;
	Entry *e, *parent;
	LogMessage s;
	char *cuid, *ngid;
	Group *eg, *ng;
	char *cname;
	char *errmsg;
	char *nuid;

	if(server->trace > 1)
		print("logfsserverwstat(%ud, %ud)\n", fid, nstat);
	if(nstat < 49)
		return Eshortstat;
	p  = stat;
	len = GBIT16(p); p += BIT16SZ;
	if(len + BIT16SZ  != nstat)
		return Eshortstat;
	mep = p + len;
	p += BIT16SZ + BIT32SZ;		/* skip type and dev */
	qid.type = *p++;
	qid.vers = GBIT32(p); p += BIT32SZ;
	qid.path = GBIT64(p); p += BIT64SZ;
	perm = GBIT32(p); p += BIT32SZ;
	p += BIT32SZ;				/* skip atime */
	mtime = GBIT32(p); p += BIT32SZ;
	length = GBIT64(p); p+= BIT64SZ;
	if(!logfsgn(&p, mep, &name) || !logfsgn(&p, mep, &uname)
		|| !logfsgn(&p, mep, &gname) || !logfsgn(&p, mep, &muname))
		return Eshortstat;
	if(p != mep)
		return Eshortstat;
	qiddonttouch = qid.type == (uchar)~0 && qid.vers == ~0 && qid.path == ~(uvlong)0;
	permdonttouch = perm == ~0;
	mtimedonttouch = mtime == ~0;
	lengthdonttouch = length == ~(uvlong)0;
	if(server->trace > 1) {
		int comma = 0;
		print("logfsserverwstat(");
		if(!qiddonttouch) {
			comma = 1;
			print("qid=0x%.2ux/%lud/%llud", qid.type, qid.vers, qid.path);
		}
		if(!permdonttouch) {
			if(comma)
				print(", ");
			print("perm=0%uo", perm);
			comma = 1;
		}
		if(!mtimedonttouch) {
			if(comma)
				print(", ");
			print("mtime=%ud", mtime);
			comma = 1;
		}
		if(!lengthdonttouch) {
			if(comma)
				print(", ");
			print("length=%llud", length);
			comma = 1;
		}
		if(name != nil) {
			if(comma)
				print(", ");
			print("name=%s", name);
			comma = 1;
		}
		if(uname != nil) {
			if(comma)
				print(", ");
			print("uid=%s", uname);
			comma = 1;
		}
		if(gname != nil) {
			if(comma)
				print(", ");
			print("gid=%s", gname);
			comma = 1;
		}
		if(muname != nil) {
			if(comma)
				print(", ");
			print("muname=%s", muname);
			comma = 1;
		}
		USED(comma);
		print(")\n");
	}
	f = logfsfidmapfindentry(server->fidmap, fid);
	if(f == nil)
		return logfsebadfid;
	e = f->entry;
	if(e->deadandgone)
		return Eio;
	parent = e->parent;
	if(name) {
		Entry *oe;
		if(parent == e)
			return Eperm;
		if(!logfsuserpermcheck(server, e->parent, f, DMWRITE))
			return Eperm;
		for(oe = parent->u.dir.list; oe; oe = oe->next) {
			if(oe == e)
				continue;
			if(strcmp(oe->name, name) == 0)
				return Eexist;
		}
	}
	if(!lengthdonttouch) {
		if(!logfsuserpermcheck(server, e, f, DMWRITE))
			return Eperm;
		if(e->qid.type & QTDIR) {
			if(length != 0)
				return Eperm;
		}else if(length != e->u.file.length){
			/*
			 * TODO - truncate directory
			 * TODO - truncate file
			 */
			return "wstat -- can't change length";
		}
	}
	cuid = logfsisfindidfromname(server->is, f->uname);
	/* TODO - change entries to have a group pointer */
	eg = logfsisfindgroupfromid(server->is, e->uid);
	if(gname) {
		gname = logfsisustadd(server->is, gname);
		if(gname == nil)
			return Enomem;
		ngid = logfsisfindidfromname(server->is, gname);
		if(ngid == nil)
			return Eunknown;
	}
	else
		ngid = nil;
	if(uname) {
		uname = logfsisustadd(server->is, uname);
		if(uname == nil)
			return Enomem;
		nuid = logfsisfindidfromname(server->is, uname);
		if(nuid == nil)
			return Eunknown;
	}
	else
		nuid = nil;
	if(!permdonttouch || !mtimedonttouch) {
		/*
		 * same permissions rules - change by owner, or by group leader
		 */
		if((server->openflags & LogfsOpenFlagWstatAllow) == 0 &&
			e->uid != cuid && (eg == nil || !logfsisgroupuidisleader(server->is, eg, cuid)))
			return Eperm;
	}
	if(!permdonttouch){
		if((perm^e->perm) & DMDIR)
			return "wstat -- attempt to change directory";
		if(perm & ~(DMDIR|DMAPPEND|DMEXCL|0777))
			return Eperm;
	}
	if(gname) {
		int ok;
		ng = logfsisfindgroupfromid(server->is, ngid);
		ok = 0;
		if(e->uid == cuid && logfsisgroupuidismember(server->is, ng, e->uid))
			ok = 1;
		if(!ok && eg && logfsisgroupuidisleader(server->is, eg, cuid)
			&& logfsisgroupuidisleader(server->is, ng, cuid))
			ok = 1;
		if(!ok && (server->openflags & LogfsOpenFlagWstatAllow) == 0)
			return Eperm;
	}
	if(!qiddonttouch)
		return Eperm;
	if(uname){
		if((server->openflags & LogfsOpenFlagWstatAllow) == 0)
			return Eperm;
	}
	if(muname)
		return Eperm;
	/*
	 * we can do this
	 */
	if(mtimedonttouch && permdonttouch && lengthdonttouch
		&& name == nil && uname == nil && gname == nil) {
		/*
		 * but we aren't doing anything - this is a wstat flush
		 */
		return logfsserverflush(server);
	}
	if(name) {
		cname = logfsstrdup(name);
		if(cname == nil)
			return Enomem;
	}
	else
		cname = nil;
	/*
	 * send the log message
	 */
	s.type = LogfsLogTwstat;
	s.path = e->qid.path;	
	s.u.wstat.name = cname;
	s.u.wstat.perm = perm;
	s.u.wstat.uid = nuid;
	s.u.wstat.gid = ngid;
	s.u.wstat.mtime = mtime;
	s.u.wstat.muid = cuid;
	errmsg = logfslog(server, 1, &s);
	if(errmsg) {
		logfsfreemem(cname);
		return errmsg;
	}
	if(!mtimedonttouch)
		e->mtime = mtime;
	if(!permdonttouch)
		e->perm = (e->perm & DMDIR) | perm;
	if(!lengthdonttouch) {
		/* TODO */
	}
	if(name) {
		logfsfreemem(e->name);
		e->name = cname;
	}
	if(uname)
		e->uid = nuid;
	if(ngid)
		e->gid = ngid;
	return nil;
}

