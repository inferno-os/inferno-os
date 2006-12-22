/*
 * power management
 */

#include	"u.h"
#include	"../port/lib.h"
#include	"mem.h"
#include	"dat.h"
#include	"fns.h"
#include	"../port/error.h"

typedef struct Power Power;
typedef struct Puser Puser;

enum{
	Qdir,
	Qctl,
	Qdata
};

static
Dirtab powertab[]={
	".",			{Qdir, 0, QTDIR},	0,	0500,
	"powerctl",		{Qctl, 0},		0,	0600,
	"powerdata",		{Qdata, 0},	0,	0666,
};

struct Puser {
	Ref;
	ulong	alarm;	/* real time clock alarm time, if non-zero */
	QLock	rl;		/* mutual exclusion to protect r */
	Rendez	r;		/* wait for event of interest */
	int	state;	/* shutdown state of this process */
	Puser*	next;
};

enum{
	Pwridle,
	Pwroff,
	Pwrack
};

static struct {
	QLock;
	Puser	*list;
	Lock	l;	/* protect shutdown, nwaiting */
	int	shutdown;	/* non-zero if currently shutting down */
	int	nwaiting;		/* waiting for this many processes */
	Rendez	ackr;	/* wait here for all acks */
} pwrusers;


static Chan*
powerattach(char* spec)
{
	return devattach(L'↓', spec);
}

static int
powerwalk(Chan* c, char* name)
{
	return devwalk(c, name, powertab, nelem(powertab), devgen);
}

static void
powerstat(Chan* c, char* db)
{
	devstat(c, db, powertab, nelem(powertab), devgen);
}

static Chan*
poweropen(Chan* c, int omode)
{
	Puser *p;

	if(c->qid.type & QTDIR)
		return devopen(c, omode, powertab, nelem(powertab), devgen);
	switch(c->qid.path){
	case Qdata:
		p = mallocz(sizeof(Puser), 1);
		if(p == nil)
			error(Enovmem);
		p->state = Pwridle;
		p->ref = 1;
		if(waserror()){
			free(p);
			nexterror();
		}
		c = devopen(c, omode, powertab, nelem(powertab), devgen);
		c->aux = p;
		qlock(&pwrusers);
		p->next = pwrusers.list;
		pwrusers.list = p;	/* note: must place on front of list for correct shutdown ordering */
		qunlock(&pwrusers);
		poperror();
		break;
	case Qctl:
		c = devopen(c, omode, powertab, nelem(powertab), devgen);
		break;
	}
	return c;
}

static Chan *
powerclone(Chan *c, Chan *nc)
{
	Puser *p;

	nc = devclone(c, nc);
	if((p = nc->aux) != nil)
		incref(p);
	return nc;
}

static void
powerclose(Chan* c)
{
	Puser *p, **l;

	if(c->qid.type & QTDIR || (c->flag & COPEN) == 0)
		return;
	p = c->aux;
	if(p != nil && decref(p) == 0){
		/* TO DO: cancel alarm */
		qlock(&pwrusers);
		for(l = &pwrusers.list; *l != nil; l = &(*l)->next)
			if(*l == p){
				*l = p->next;
				break;
			}
		qunlock(&pwrusers);
		free(p);
	}
}

static int
isshutdown(void *a)
{
	return ((Puser*)a)->state == Pwroff;
}

static long
powerread(Chan* c, void* a, long n, vlong offset)
{
	Puser *p;
	char *msg;

	switch(c->qid.path & ~CHDIR){
	case Qdir:
		return devdirread(c, a, n, powertab, nelem(powertab), devgen);
	case Qdata:
		p = c->aux;
		for(;;){
			if(!canqlock(&p->rl))
				error(Einuse);	/* only one reader at a time */
			if(waserror()){
				qunlock(&p->rl);
				nexterror();
			}
			sleep(&p->r, isshutdown, p);
			poperror();
			qunlock(&p->rl);
			msg = nil;
			lock(p);
			if(p->state == Pwroff){
				msg = "power off";
				p->state = Pwrack;
			}
			unlock(p);
			if(msg != nil)
				return readstr(offset, a, n, msg);
		}
		break;
	case Qctl:
	default:
		n=0;
		break;
	}
	return n;
}

static int
alldown(void*)
{
	return pwrusers.nwaiting == 0;
}

static long
powerwrite(Chan* c, void *a, long n, vlong)
{
	Cmdbuf *cmd;
	Puser *p;

	if(c->qid.type & QTDIR)
		error(Ebadusefd);
	cmd = parsecmd(a, n);
	if(waserror()){
		free(cmd);
		nexterror();
	}
	switch(c->qid.path & ~CHDIR){
	case Qdata:
		p = c->aux;
		if(cmd->nf < 2)
			error(Ebadarg);
		if(strcmp(cmd->f[0], "ack") == 0){
			if(strcmp(cmd->f[1], "power") == 0){
				lock(p);
				if(p->state == Pwrack){
					lock(&pwrusers.l);
					if(pwrusers.shutdown && pwrusers.nwaiting > 0)
						pwrusers.nwaiting--;
					unlock(&pwrusers.l);
					wakeup(&pwrusers.ackr);
					p->state = Pwridle;
				}
				unlock(p);
			}else
				error(Ebadarg);
		}else if(strcmp(cmd->f[0], "alarm") == 0){
			/* set alarm */
		}else
			error(Ebadarg);
		break;
	case Qctl:
		if(cmd->nf < 1)
			error(Ebadarg);
		if(strcmp(cmd->f[0], "suspend") == 0){
			/* start the suspend action */
			qlock(&pwrusers);
			//powersuspend(0);	/* calls poweringdown, then archsuspend() */
			qunlock(&pwrusers);
		}else if(strcmp(cmd->f[0], "shutdown") == 0){
			/* go to it */
			qlock(&pwrusers);
			if(waserror()){
				lock(&pwrusers.l);
				pwrusers.shutdown = 0;	/* hard luck for those already notified */
				unlock(&pwrusers.l);
				qunlock(&pwrusers);
				nexterror();
			}
			lock(&pwrusers.l);
			pwrusers.shutdown = 1;
			pwrusers.nwaiting = 0;
			unlock(&pwrusers.l);
			for(p = pwrusers.list; p != nil; p = p->next){
				lock(p);
				if(p->state == Pwridle){
					p->state = Pwroff;
					lock(&pwrusers.l);
					pwrusers.nwaiting++;
					unlock(&pwrusers.l);
				}
				unlock(p);
				wakeup(&p->r);
				/* putting the tsleep here does each in turn; move out of loop to multicast */
				tsleep(&pwrusers.ackr, alldown, nil, 1000);
			}
			poperror();
			qunlock(&pwrusers);
			//powersuspend(1);
		}else
			error(Ebadarg);
		free(cmd);
		break;
	default:
		error(Ebadusefd);
	}
	poperror();
	return n;
}

/*
 * device-level power management: suspend/resume/shutdown
 */

struct Power {
	void	(*f)(int);
	Power*	prev;
	Power*	next;
};

static struct {
	Lock;
	Power	list;
} power;

void
powerenablereset(void)
{
	power.list.next = power.list.prev = &power.list;
	power.list.f = (void*)-1;	/* something not nil */
}

void
powerenable(void (*f)(int))
{
	Power *p, *l;

	p = malloc(sizeof(*p));
	p->f = f;
	p->prev = nil;
	p->next = nil;
	ilock(&power);
	for(l = power.list.next; l != &power.list; l = l->next)
		if(l->f == f){
			iunlock(&power);
			free(p);
			return;
		}
	l = &power.list;
	p->prev = l->prev;
	l->prev = p;
	p->next = l;
	p->prev->next = p;
	iunlock(&power);
}

void
powerdisable(void (*f)(int))
{
	Power *l;

	ilock(&power);
	for(l = power.list.next; l != &power.list; l = l->next)
		if(l->f == f){
			l->prev->next = l->next;
			l->next->prev = l->prev;
			free(l);
			break;
		}
	iunlock(&power);
}

/*
 * interrupts are assumed off so there's no need to lock
 */
void
poweringup(void)
{
	Power *l;

	for(l = power.list.next; l != &power.list; l = l->next)
		(*l->f)(1);
}

void
poweringdown(void)
{
	Power *l;

	for(l = power.list.prev; l != &power.list; l = l->prev)
		(*l->f)(0);
}

Dev powerdevtab = {
	L'↓',
	"power",

	devreset,
	devinit,
	powerattach,
	devdetach,
	powerclone,
	powerwalk,
	powerstat,
	poweropen,
	devcreate,
	powerclose,
	powerread,
	devbread,
	powerwrite,
	devbwrite,
	devremove,
	devwstat,
};
