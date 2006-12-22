#include	"u.h"
#include	"../port/lib.h"
#include	"mem.h"
#include	"dat.h"
#include	"fns.h"
#include	"error.h"
#include	"mp.h"
#include	"libsec.h"

/*
 * Copyright © 2003 Vita Nuova Holdings Limited.  All rights reserved.
 */

enum {
	Captimeout = 15,	/* seconds until expiry */
	Capidletime = 60	/* idle seconds before capwatch exits */
};

typedef struct Caps Caps;
struct Caps
{
	uchar	hash[SHA1dlen];
	ulong	time;
	Caps*	next;
};

struct {
	QLock	l;
	Caps*	caps;
	int	kpstarted;
} allcaps;

enum {
	Qdir,
	Qhash,
	Quse
};

static Dirtab capdir[] =
{
	".",			{Qdir, 0, QTDIR},	0,	DMDIR|0555,
	"capuse",		{Quse, 0},			0,	0222,
	"caphash",	{Qhash, 0},		0,	0200,
};

static int ncapdir = nelem(capdir);

static void
capwatch(void *a)
{
	Caps *c, **l;
	int idletime;

	USED(a);
	idletime = 0;
	for(;;){
		tsleep(&up->sleep, return0, nil, 30*1000);
		qlock(&allcaps.l);
		for(l = &allcaps.caps; (c = *l) != nil;)
			if(++c->time > Captimeout){
				*l = c->next;
				free(c);
			}else
				l = &c->next;
		if(allcaps.caps == nil){
			if(++idletime > Capidletime){
				allcaps.kpstarted = 0;
				qunlock(&allcaps.l);
				pexit("", 0);
			}
		}else
			idletime = 0;
		qunlock(&allcaps.l);
	}
}

static Chan *
capattach(char *spec)
{
	return devattach(L'¤', spec);
}

static Walkqid*
capwalk(Chan *c, Chan *nc, char **name, int nname)
{
	return devwalk(c, nc, name, nname, capdir, nelem(capdir), devgen);
}

static int
capstat(Chan *c, uchar *db, int n)
{
	return devstat(c, db, n, capdir, nelem(capdir), devgen);
}

static Chan*
capopen(Chan *c, int omode)
{
	if(c->qid.type & QTDIR) {
		if(omode != OREAD)
			error(Eisdir);
		c->mode = omode;
		c->flag |= COPEN;
		c->offset = 0;
		return c;
	}

	if(c->qid.path == Qhash && !iseve())
		error(Eperm);

	c->mode = openmode(omode);
	c->flag |= COPEN;
	c->offset = 0;
	return c;
}

static void
capclose(Chan *c)
{
	USED(c);
}

static long
capread(Chan *c, void *va, long n, vlong vl)
{
	USED(vl);
	switch((ulong)c->qid.path){
	case Qdir:
		return devdirread(c, va, n, capdir, ncapdir, devgen);

	default:
		error(Eperm);
		break;
	}
	return n;
}

static int
capwritehash(uchar *a, int l)
{
	Caps *c;

	if(l != SHA1dlen)
		return -1;
	c = malloc(sizeof(*c));
	if(c == nil)
		return -1;
	memmove(c->hash, a, l);
	c->time = 0;
	qlock(&allcaps.l);
	c->next = allcaps.caps;
	allcaps.caps = c;
	if(!allcaps.kpstarted){
		allcaps.kpstarted = 1;
		kproc("capwatch", capwatch, 0, 0);
	}
	qunlock(&allcaps.l);
	return 0;
}

static int
capwriteuse(uchar *a, int len)
{
	int n;
	uchar digest[SHA1dlen];
	char buf[128], *p, *users[3];
	Caps *c, **l;

	if(len >= sizeof(buf)-1)
		return -1;
	memmove(buf, a, len);
	buf[len] = 0;
	p = strrchr(buf, '@');
	if(p == nil)
		return -1;
	*p++ = 0;
	len = strlen(p);
	n = strlen(buf);
	if(len == 0 || n == 0)
		return -1;
	hmac_sha1((uchar*)buf, n, (uchar*)p, len, digest, nil);
	n = getfields(buf, users, nelem(users), 0, "@");
	if(n == 1)
		users[1] = users[0];
	else if(n != 2)
		return -1;
	if(*users[0] == 0 || *users[1] == 0)
		return -1;
	qlock(&allcaps.l);
	for(l = &allcaps.caps; (c = *l) != nil; l = &c->next)
		if(memcmp(c->hash, digest, sizeof(c->hash)) == 0){
			*l = c->next;
			qunlock(&allcaps.l);
			free(c);
			if(n == 2 && strcmp(up->env->user, users[0]) != 0)
				return -1;
			kstrdup(&up->env->user, users[1]);
			return 0;
		}
	qunlock(&allcaps.l);
	return -1;
}

static long	 
capwrite(Chan* c, void* buf, long n, vlong offset)
{
	USED(offset);
	switch((ulong)c->qid.path){
	case Qhash:
		if(capwritehash(buf, n) < 0)
			error(Ebadarg);
		return n;
	case Quse:
		if(capwriteuse(buf, n) < 0)
			error("invalid capability");
		return n;
	}
	error(Ebadarg);
	return 0;
}

static void
capremove(Chan *c)
{
	if(c->qid.path != Qhash || !iseve())
		error(Eperm);
	ncapdir = nelem(capdir)-1;
}

Dev capdevtab = {
	L'¤',
	"cap",

	devreset,
	devinit,
	devshutdown,
	capattach,
	capwalk,
	capstat,
	capopen,
	devcreate,
	capclose,
	capread,
	devbread,
	capwrite,
	devbwrite,
	capremove,
	devwstat
};
