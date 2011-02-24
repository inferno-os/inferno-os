#include	"u.h"
#include	"../port/lib.h"
#include	"mem.h"
#include	"dat.h"
#include	"fns.h"
#include	"../port/error.h"

static Ref pgrpid;
static Ref mountid;

Pgrp*
newpgrp(void)
{
	Pgrp *p;

	p = smalloc(sizeof(Pgrp));
	p->ref = 1;
	p->pgrpid = incref(&pgrpid);
	p->progmode = 0644;
	return p;
}

void
closepgrp(Pgrp *p)
{
	Mhead **h, **e, *f, *next;
	
	if(p == nil || decref(p) != 0)
		return;

	wlock(&p->ns);
	p->pgrpid = -1;

	e = &p->mnthash[MNTHASH];
	for(h = p->mnthash; h < e; h++) {
		for(f = *h; f; f = next) {
			wlock(&f->lock);
			cclose(f->from);
			mountfree(f->mount);
			f->mount = nil;
			next = f->hash;
			wunlock(&f->lock);
			putmhead(f);
		}
	}
	wunlock(&p->ns);
	cclose(p->dot);
	cclose(p->slash);
	free(p);
}

void
pgrpinsert(Mount **order, Mount *m)
{
	Mount *f;

	m->order = 0;
	if(*order == 0) {
		*order = m;
		return;
	}
	for(f = *order; f; f = f->order) {
		if(m->mountid < f->mountid) {
			m->order = f;
			*order = m;
			return;
		}
		order = &f->order;
	}
	*order = m;
}

/*
 * pgrpcpy MUST preserve the mountid allocation order of the parent group
 */
void
pgrpcpy(Pgrp *to, Pgrp *from)
{
	int i;
	Mount *n, *m, **link, *order;
	Mhead *f, **tom, **l, *mh;

	wlock(&from->ns);
	if(waserror()){
		wunlock(&from->ns);
		nexterror();
	}
	order = 0;
	tom = to->mnthash;
	for(i = 0; i < MNTHASH; i++) {
		l = tom++;
		for(f = from->mnthash[i]; f; f = f->hash) {
			rlock(&f->lock);
			if(waserror()){
				runlock(&f->lock);
				nexterror();
			}
			mh = malloc(sizeof(Mhead));
			if(mh == nil)
				error(Enomem);
			mh->from = f->from;
			mh->ref = 1;
			incref(mh->from);
			*l = mh;
			l = &mh->hash;
			link = &mh->mount;
			for(m = f->mount; m; m = m->next) {
				n = newmount(mh, m->to, m->mflag, m->spec);
				m->copy = n;
				pgrpinsert(&order, m);
				*link = n;
				link = &n->next;
			}
			poperror();
			runlock(&f->lock);
		}
	}
	/*
	 * Allocate mount ids in the same sequence as the parent group
	 */
	lock(&mountid.l);
	for(m = order; m; m = m->order)
		m->copy->mountid = mountid.ref++;
	unlock(&mountid.l);

	to->progmode = from->progmode;
	to->slash = cclone(from->slash);
	to->dot = cclone(from->dot);
	to->nodevs = from->nodevs;

	poperror();
	wunlock(&from->ns);
}

Fgrp*
newfgrp(Fgrp *old)
{
	Fgrp *new;
	int n;

	new = smalloc(sizeof(Fgrp));
	new->ref = 1;
	n = DELTAFD;
	if(old != nil){
		lock(old);
		if(old->maxfd >= n)
			n = (old->maxfd+1 + DELTAFD-1)/DELTAFD * DELTAFD;
		new->maxfd = old->maxfd;
		unlock(old);
	}
	new->nfd = n;
	new->fd = smalloc(n*sizeof(Chan*));
	return new;
}

Fgrp*
dupfgrp(Fgrp *f)
{
	int i;
	Chan *c;
	Fgrp *new;
	int n;

	new = smalloc(sizeof(Fgrp));
	new->ref = 1;
	lock(f);
	n = DELTAFD;
	if(f->maxfd >= n)
		n = (f->maxfd+1 + DELTAFD-1)/DELTAFD * DELTAFD;
	new->nfd = n;
	new->fd = malloc(n*sizeof(Chan*));
	if(new->fd == nil){
		unlock(f);
		free(new);
		error(Enomem);
	}
	new->maxfd = f->maxfd;
	new->minfd = f->minfd;
	for(i = 0; i <= f->maxfd; i++) {
		if(c = f->fd[i]){
			incref(c);
			new->fd[i] = c;
		}
	}
	unlock(f);

	return new;
}

void
closefgrp(Fgrp *f)
{
	int i;
	Chan *c;

	if(f == nil || decref(f) != 0)
		return;

	for(i = 0; i <= f->maxfd; i++)
		if(c = f->fd[i])
			cclose(c);

	free(f->fd);
	free(f);
}

Mount*
newmount(Mhead *mh, Chan *to, int flag, char *spec)
{
	Mount *m;

	m = smalloc(sizeof(Mount));
	m->to = to;
	m->head = mh;
	incref(to);
	m->mountid = incref(&mountid);
	m->mflag = flag;
	if(spec != 0)
		kstrdup(&m->spec, spec);

	return m;
}

void
mountfree(Mount *m)
{
	Mount *f;

	while(m) {
		f = m->next;
		cclose(m->to);
		m->mountid = 0;
		free(m->spec);
		free(m);
		m = f;
	}
}

void
resrcwait(char *reason)
{
	char *p;

	if(up == 0)
		panic("resrcwait");

	p = up->psstate;
	if(reason) {
		up->psstate = reason;
		print("%s\n", reason);
	}

	tsleep(&up->sleep, return0, 0, 300);
	up->psstate = p;
}

void
closesigs(Skeyset *s)
{
	int i;

	if(s == nil || decref(s) != 0)
		return;
	for(i=0; i<s->nkey; i++)
		freeskey(s->keys[i]);
	free(s);
}

void
freeskey(Signerkey *key)
{
	if(key == nil || decref(key) != 0)
		return;
	free(key->owner);
	(*key->pkfree)(key->pk);
	free(key);
}
