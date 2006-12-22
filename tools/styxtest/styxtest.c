#include <lib9.h>
#include "styxserver.h"

/*
 * An in-memory file server
 * allowing truncation, removal on closure, wstat and
 * all other file operations
 */

char *fsremove(Qid);

Styxserver *server;

char*
fsopen(Qid *qid, int mode)
{
	Styxfile *f;

	f = styxfindfile(server, qid->path);
	if(mode&OTRUNC){	/* truncate on open */
		styxfree(f->u);
		f->u = nil;
		f->d.length = 0;
	}
	return nil;
}

char*
fsclose(Qid qid, int mode)
{
	if(mode&ORCLOSE)	/* remove on close */
		return fsremove(qid);
	return nil;
}

char *
fscreate(Qid *qid, char *name, int perm, int mode)
{
	int isdir;
	Styxfile *f;

	USED(mode);
	isdir = perm&DMDIR;
	if(isdir)
		f = styxadddir(server, qid->path, -1, name, perm, "inferno");
	else
		f = styxaddfile(server, qid->path, -1, name, perm, "inferno");
	if(f == nil)
		return Eexist;
	f->u = nil;
	f->d.length = 0;
	*qid = f->d.qid;
	return nil;
}

char *
fsremove(Qid qid)
{
	Styxfile *f;

	f = styxfindfile(server, qid.path);
	if((f->d.qid.type&QTDIR) && f->child != nil)
		return "directory not empty";
	styxfree(f->u);
	styxrmfile(server, qid.path);	
	return nil;
}

char *
fsread(Qid qid, char *buf, ulong *n, vlong off)
{
	int m;
	Styxfile *f;

	f = styxfindfile(server, qid.path);
	m = f->d.length;
	if(off >= m)
		*n = 0;
	else{
		if(off + *n > m)
			*n = m-off;
		memmove(buf, (char*)f->u+off, *n);
	}
	return nil;
}

char*
fswrite(Qid qid, char *buf, ulong *n, vlong off)
{
	Styxfile *f;
	vlong m, p;
	char *u;

	f = styxfindfile(server, qid.path);
	m = f->d.length;
	p = off + *n;
	if(p > m){	/* just grab a larger piece of memory */
		u = styxmalloc(p);
		if(u == nil)
			return "out of memory";
		memset(u, 0, p);
		memmove(u, f->u, m);
		styxfree(f->u);
		f->u = u;
		f->d.length = p;
	}
	memmove((char*)f->u+off, buf, *n);
	return nil;
}

char*
fswstat(Qid qid, Dir *d)
{
	Styxfile *f, *tf;
	Client *c;
	int owner;

	/* the most complicated operation when fully allowed */

	c = styxclient(server);
	f = styxfindfile(server, qid.path);
	owner = strcmp(c->uname, f->d.uid) == 0;
	if(d->name != nil && strcmp(d->name, f->d.name) != 0){
		/* need write permission in parent directory */
		if(!styxperm(f->parent, c->uname, OWRITE))
			return Eperm;
		if((tf = styxaddfile(server, f->parent->d.qid.path, -1, d->name, 0, "")) == nil){
			/* file with same name exists */
			return Eexist;
		}
		else{
			/* undo above addfile */
			styxrmfile(server, tf->d.qid.path);
		}
		/* ok to change name now */
		styxfree(f->d.name);
		f->d.name = strdup(d->name);	
	}
	if(d->uid != nil && strcmp(d->uid, f->d.uid) != 0){
		if(!owner)
			return Eperm;
		styxfree(f->d.uid);
		f->d.uid = strdup(d->uid);
	}
	if(d->gid != nil && strcmp(d->gid, f->d.gid) != 0){
		if(!owner)
			return Eperm;
		styxfree(f->d.gid);
		f->d.gid = strdup(d->gid);
	}
	if(d->mode != ~0 && d->mode != f->d.mode){
		if(!owner)
			return Eperm;
		if(d->mode&DMDIR != f->d.mode&DMDIR)
			return Eperm;	/* cannot change file->directory or vice-verse */
		f->d.mode = d->mode;
	}
	if(d->mtime != ~0 && d->mtime != f->d.mtime){
		if(!owner)
			return Eperm;
		f->d.mtime = d->mtime;
	}
	/* all other file attributes cannot be changed by wstat */
	return nil;
}

Styxops ops = {
	nil,			/* newclient */
	nil,			/* freeclient */

	nil,			/* attach */
	nil,			/* walk */
	fsopen,		/* open */
	fscreate,		/* create */
	fsread,		/* read */
	fswrite,		/* write */
	fsclose,		/* close */
	fsremove,	/* remove */
	nil,			/* stat */
	fswstat,		/* wstat */
};

main(int argc, char **argv)
{
	Styxserver s;

	USED(argc);
	USED(argv);
	server = &s;
	styxdebug();
	styxinit(&s, &ops, "6701", 0777, 1);
	for(;;){
		styxwait(&s);
		styxprocess(&s);
	}
	return 0;
}

