#include "logfsos.h"
#include "logfs.h"
#include "local.h"
#include "fcall.h"

static void
pn(uchar **pp, char *v)
{
	uchar *p = *pp;
	int l;
	l = v ? strlen(v) : 0;
	PBIT16(p, l); p += BIT16SZ;
	memmove(p, v, l);
	p += l;
	*pp = p;
}

static uint
sn(char *p)
{
	if(p == nil)
		return BIT16SZ;
	return strlen(p) + BIT16SZ;
}

uint
logfsconvM2S(uchar *ap, uint nap, LogMessage *f)
{
	uchar *p = ap;
	uchar *ep = p + nap;
	uchar *mep;
	uint size;
//print("conv(%d)\n", nap);
	if(p + 1 > ep)
		return 0;
	f->type = *p++;
//print("type %c\n", f->type);
	switch(f->type) {
	case LogfsLogTstart:
	case LogfsLogTcreate:
	case LogfsLogTtrunc:
	case LogfsLogTremove:
	case LogfsLogTwrite:
	case LogfsLogTwstat:
		break;
	case LogfsLogTend:
		return 1;
	default:	
		return 0;
	}
	if(p + BIT16SZ > ep)
		return 0;
	size = GBIT16(p); p += BIT16SZ;
//print("size %ud\n", size);
	if(p + size > ep)
		return 0;
	mep = p + size;
	if(p + BIT32SZ > mep)
		return 0;
	f->path = GBIT32(p); p += BIT32SZ;
	switch(f->type) {
	case LogfsLogTstart:
		/* 's' size[2] path[4] nerase[4] */
		if(p + BIT32SZ > ep)
			return 0;
		f->u.start.nerase = GBIT32(p); p += BIT32SZ;
		break;
	case LogfsLogTcreate:
		/* 'c' size[2] path[4] perm[4] newpath[4] mtime[4] cvers[4] name[s] uid[s] gid[s] */
		if(p + 4 * BIT32SZ > mep)
			return 0;
		f->u.create.perm = GBIT32(p); p+= BIT32SZ;
		f->u.create.newpath = GBIT32(p); p+= BIT32SZ;
		f->u.create.mtime = GBIT32(p); p+= BIT32SZ;
		f->u.create.cvers = GBIT32(p); p+= BIT32SZ;
		if(!logfsgn(&p, mep, &f->u.create.name)
			|| !logfsgn(&p, mep, &f->u.create.uid)
			|| !logfsgn(&p, mep, &f->u.create.gid))
			return 0;
		break;
	case LogfsLogTremove:
		/* 'r' size[2] path[4] mtime[4] muid[s] */
		if(p + BIT32SZ > mep)
			return 0;
		f->u.remove.mtime = GBIT32(p); p += BIT32SZ;
		if(!logfsgn(&p, mep, &f->u.remove.muid))
			return 0;
		break;
	case LogfsLogTtrunc:
		/* 't' size[2] path[4] mtime[4] cvers[4] muid[s] */
		if(p + 2 * BIT32SZ > mep)
			return 0;
		f->u.trunc.mtime = GBIT32(p); p += BIT32SZ;
		f->u.trunc.cvers = GBIT32(p); p += BIT32SZ;
		if(!logfsgn(&p, mep, &f->u.trunc.muid))
			return 0;
		break;
	case LogfsLogTwrite:
		/* 'w' size[2] path[4] offset[4] count[2] mtime[4] cvers[4] muid[s] flashaddr[4] [data[n]] */
		if(p + BIT32SZ + BIT16SZ + 2 * BIT32SZ > mep)
			return 0;
		f->u.write.offset = GBIT32(p); p += BIT32SZ;
		f->u.write.count = GBIT16(p); p += BIT16SZ;
		f->u.write.mtime = GBIT32(p); p += BIT32SZ;
		f->u.write.cvers = GBIT32(p); p += BIT32SZ;
		if(!logfsgn(&p, mep, &f->u.write.muid))
			return 0;
		if(p + BIT32SZ > mep)
			return 0;
		f->u.write.flashaddr = GBIT32(p); p += BIT32SZ;
		if(f->u.write.flashaddr & LogAddr) {
			if(p + f->u.write.count > mep)
				return 0;
			f->u.write.data = p;
			p += f->u.write.count;
		}
		else
			f->u.write.data = nil;
		break;
	case LogfsLogTwstat:
		/* 'W' size[2] path[4] name[s] perm[4] uid[s] gid[s] mtime[4] muid[s] or */
		/* 'W' size[2] path[4] name[s] perm[4] gid[s] mtime[4] muid[s] */
		if(!logfsgn(&p, mep, &f->u.wstat.name))
			return 0;
		if(p + BIT32SZ > mep)
			return 0;
		f->u.wstat.perm = GBIT32(p); p += BIT32SZ;
		if(!logfsgn(&p, mep, &f->u.wstat.uid))
			return 0;
		if(!logfsgn(&p, mep, &f->u.wstat.gid))
			return 0;
		if(p + BIT32SZ > mep)
			return 0;
		f->u.wstat.mtime = GBIT32(p); p += BIT32SZ;
		if(!logfsgn(&p, mep, &f->u.wstat.muid))
			return 0;
		break;
	default:
		return 0;
	}
	if(p != mep)
		return 0;
	return p - ap;
}

uint
logfssizeS2M(LogMessage *m)
{
	switch(m->type) {
	case LogfsLogTend:
		return 1;
	case LogfsLogTstart:
		return 11;
	case LogfsLogTcreate:
		/* 'c' size[2] path[4] perm[4] newpath[4] mtime[4] cvers[4] name[s] uid[s] gid[s] */
		return 1 + BIT16SZ + 5 * BIT32SZ
			+ sn(m->u.create.name) + sn(m->u.create.uid) + sn(m->u.create.gid);
	case LogfsLogTremove:
		/* 'r' size[2] path[4] mtime[4] muid[s] */
		return 1 + BIT16SZ + 2 * BIT32SZ + sn(m->u.remove.muid);
	case LogfsLogTtrunc:
		/* 't' size[2] path[4] mtime[4] cvers[4] muid[s] */
		return 1 + BIT16SZ + 3 * BIT32SZ + sn(m->u.trunc.muid);
	case LogfsLogTwrite:
		/* 'w' size[2] path[4] offset[4] count[2] mtime[4] cvers[4] muid[s] flashaddr[4] [data[n]] */
		return 1 + BIT16SZ + 2 * BIT32SZ + BIT16SZ + 2 * BIT32SZ + sn(m->u.write.muid)
			+ BIT32SZ + (m->u.write.data ? m->u.write.count : 0);
	case LogfsLogTwstat:
		/* 'W' size[2] path[4] name[s] perm[4] uid[s] gid[s] mtime[4] muid[s] */
		/* 'W' size[2] path[4] name[s] perm[4] gid[s] mtime[4] muid[s] */
		return 1 + BIT16SZ + BIT32SZ + sn(m->u.wstat.name) + BIT32SZ
			+ sn(m->u.wstat.uid)
			+ sn(m->u.wstat.gid) + BIT32SZ + sn(m->u.wstat.muid);
	default:
		return 0;
	}
}

uint
logfsconvS2M(LogMessage *s, uchar *ap, uint nap)
{
	uint size;
	uchar *p;
	size = logfssizeS2M(s);
	if(size == 0 || size > nap)
		return 0;
	p = ap;
	*p++ = s->type;
	if(s->type == LogfsLogTend)
		return 1;
	size -= 1 + BIT16SZ;
	PBIT16(p, size); p += BIT16SZ;
	PBIT32(p, s->path); p += BIT32SZ;
	switch(s->type) {
	case LogfsLogTstart:
		PBIT32(p, s->u.start.nerase); p += BIT32SZ;
		break;
	case LogfsLogTcreate:
		/* 'c' size[2] path[4] perm[4] newpath[4] mtime[4] cvers[4] name[s] uid[s] gid[s] */
		PBIT32(p, s->u.create.perm); p += BIT32SZ;
		PBIT32(p, s->u.create.newpath); p += BIT32SZ;
		PBIT32(p, s->u.create.mtime); p += BIT32SZ;
		PBIT32(p, s->u.create.cvers); p += BIT32SZ;
		pn(&p, s->u.create.name);
		pn(&p, s->u.create.uid);
		pn(&p, s->u.create.gid);
		break;
	case LogfsLogTremove:
		/* 'r' size[2] path[4] mtime[4] muid[s] */
		PBIT32(p, s->u.remove.mtime); p += BIT32SZ;
		pn(&p, s->u.remove.muid);
		break;
	case LogfsLogTtrunc:
		/* 't' size[2] path[4] mtime[4] cvers[4] muid[s] */
		PBIT32(p, s->u.trunc.mtime); p += BIT32SZ;
		PBIT32(p, s->u.trunc.cvers); p += BIT32SZ;
		pn(&p, s->u.trunc.muid);
		break;
	case LogfsLogTwrite:
		/* 'w' size[2] path[4] offset[4] count[2] mtime[4] cvers[4] muid[s] flashaddr[4] [data[n]] */
		PBIT32(p, s->u.write.offset); p += BIT32SZ;
		PBIT16(p, s->u.write.count); p += BIT16SZ;
		PBIT32(p, s->u.write.mtime); p += BIT32SZ;
		PBIT32(p, s->u.write.cvers); p += BIT32SZ;
		pn(&p, s->u.write.muid);
		PBIT32(p, s->u.write.flashaddr); p += BIT32SZ;
		if(s->u.write.data) {
			memmove(p, s->u.write.data, s->u.write.count);
			p += s->u.write.count;
		}
		break;
	case LogfsLogTwstat:
		/* 'W' size[2] path[4] name[s] perm[4] uid[s] gid[s] mtime[4] muid[s] */
		/* 'W' size[2] path[4] name[s] perm[4] gid[s] mtime[4] muid[s] */
		pn(&p, s->u.wstat.name);
		PBIT32(p, s->u.wstat.perm); p += BIT32SZ;
		pn(&p, s->u.wstat.uid);
		pn(&p, s->u.wstat.gid);
		PBIT32(p, s->u.wstat.mtime); p+= BIT32SZ;
		pn(&p, s->u.wstat.muid);
		break;
	default:
		return 0;
	}
	return p - ap;
}
		
void
logfsdumpS(LogMessage *m)
{
	switch(m->type) {
	case LogfsLogTend:
		print("LogfsLogTend()");
		break;
	case LogfsLogTstart:
		print("LogfsLogTstart(path=%ud, nerase=%ud)", m->path, m->u.start.nerase);
		break;
	case LogfsLogTcreate:
		print("LogfsLogTcreate(path=%ud, perm=0%uo, newpath=%ud, mtime=%ud, cvers=%ud, name=%s, uid=%s, gid=%s)",
			m->path, m->u.create.perm, m->u.create.newpath, m->u.create.mtime, m->u.create.cvers,
			m->u.create.name, m->u.create.uid, m->u.create.gid);
		break;
	case LogfsLogTremove:
		print("LogfsLogTremove(path=%ud, mtime=%ud, muid=%s)",
			m->path, m->u.remove.mtime, m->u.remove.muid);
		break;
	case LogfsLogTtrunc:
		print("LogfsLogTtrunc(path=%ud, mtime=%ud, cvers=%ud, muid=%s)",
			m->path, m->u.trunc.mtime, m->u.trunc.cvers, m->u.trunc.muid);
		break;
	case LogfsLogTwrite:
		print("LogfsLogTwrite(path=%ud, offset=%ud, count=%ud, mtime=%ud, cvers=%ud, muid=%s, flashaddr=0x%.8ux)",
			m->path, m->u.write.offset, m->u.write.count, m->u.write.mtime, m->u.write.cvers, m->u.write.muid,
			m->u.write.flashaddr);
		break;
	case LogfsLogTwstat:
		print("LogfsLogTwstat(path=%ud, name=%s, perm=0%uo, uid=%s, gid=%s, mtime=%ud, muid=%s)",
			m->path, m->u.wstat.name, m->u.wstat.perm, m->u.wstat.uid, m->u.wstat.gid,
			m->u.wstat.mtime, m->u.wstat.muid);
		break;
	default:
		print("LogfsLogTother(%c)", m->type);
		break;
	}
}
