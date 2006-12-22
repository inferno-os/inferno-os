#include	"dat.h"
#include	"fns.h"
#include	"error.h"

enum
{
	Qtopdir,	/* top level directory */
	Qcmd,
	Qclonus,
	Qconvdir,
	Qconvbase,
	Qdata = Qconvbase,
	Qctl,
	Qstatus,
	Qwait,

	Debug=0	/* to help debug os.c */
};
#define TYPE(x) 	((ulong)(x).path & 0xf)
#define CONV(x) 	(((ulong)(x).path >> 4)&0xfff)
#define QID(c, y) 	(((c)<<4) | (y))

typedef struct Conv	Conv;
struct Conv
{
	int	x;
	int	inuse;
	int	wcount;
	int	rcount;
	int	rfd;
	int	wfd;
	int	perm;
	char*	owner;
	char*	state;
	Cmdbuf*	cmd;
	char*	dir;
	QLock	l;	/* protects state changes */
	Queue*	waitq;
	void*	child;
	char*	error;	/* on start up */
	int	nice;
	short	killonclose;
	short	killed;
	Rendez	startr;
};

static struct
{
	QLock	l;
	int	nc;
	int	maxconv;
	Conv**	conv;
} cmd;

static	Conv*	cmdclone(char*);
static	void	cmdproc(void*);

static int
cmd3gen(Chan *c, int i, Dir *dp)
{
	Qid q;
	Conv *cv;

	cv = cmd.conv[CONV(c->qid)];
	switch(i){
	default:
		return -1;
	case Qdata:
		mkqid(&q, QID(CONV(c->qid), Qdata), 0, QTFILE);
		devdir(c, q, "data", 0, cv->owner, cv->perm, dp);
		return 1;
	case Qctl:
		mkqid(&q, QID(CONV(c->qid), Qctl), 0, QTFILE);
		devdir(c, q, "ctl", 0, cv->owner, cv->perm, dp);
		return 1;
	case Qstatus:
		mkqid(&q, QID(CONV(c->qid), Qstatus), 0, QTFILE);
		devdir(c, q, "status", 0, cv->owner, 0444, dp);
		return 1;
	case Qwait:
		mkqid(&q, QID(CONV(c->qid), Qwait), 0, QTFILE);
		devdir(c, q, "wait", 0, cv->owner, 0444, dp);
		return 1;
	}
}

static int
cmdgen(Chan *c, char *name, Dirtab *d, int nd, int s, Dir *dp)
{
	Qid q;
	Conv *cv;

	USED(name);
	USED(nd);
	USED(d);

	if(s == DEVDOTDOT){
		switch(TYPE(c->qid)){
		case Qtopdir:
		case Qcmd:
			mkqid(&q, QID(0, Qtopdir), 0, QTDIR);
			devdir(c, q, "#C", 0, eve, DMDIR|0555, dp);
			break;
		case Qconvdir:
			mkqid(&q, QID(0, Qcmd), 0, QTDIR);
			devdir(c, q, "cmd", 0, eve, DMDIR|0555, dp);
			break;
		default:
			panic("cmdgen %llux", c->qid.path);
		}
		return 1;
	}

	switch(TYPE(c->qid)) {
	case Qtopdir:
		if(s >= 1)
			return -1;
		mkqid(&q, QID(0, Qcmd), 0, QTDIR);
		devdir(c, q, "cmd", 0, "cmd", DMDIR|0555, dp);
		return 1;
	case Qcmd:
		if(s < cmd.nc) {
			cv = cmd.conv[s];
			mkqid(&q, QID(s, Qconvdir), 0, QTDIR);
			sprint(up->genbuf, "%d", s);
			devdir(c, q, up->genbuf, 0, cv->owner, DMDIR|0555, dp);
			return 1;
		}
		s -= cmd.nc;
		if(s == 0){
			mkqid(&q, QID(0, Qclonus), 0, QTFILE);
			devdir(c, q, "clone", 0, "cmd", 0666, dp);
			return 1;
		}
		return -1;
	case Qclonus:
		if(s == 0){
			mkqid(&q, QID(0, Qclonus), 0, QTFILE);
			devdir(c, q, "clone", 0, "cmd", 0666, dp);
			return 1;
		}
		return -1;
	case Qconvdir:
		return cmd3gen(c, Qconvbase+s, dp);
	case Qdata:
	case Qctl:
	case Qstatus:
	case Qwait:
		return cmd3gen(c, TYPE(c->qid), dp);
	}
	return -1;
}

static void
cmdinit(void)
{
	cmd.maxconv = 100;
	cmd.conv = mallocz(sizeof(Conv*)*(cmd.maxconv+1), 1);
	/* cmd.conv is checked by cmdattach, below */
}

static Chan *
cmdattach(char *spec)
{
	Chan *c;

	if(cmd.conv == nil)
		error(Enomem);
	c = devattach('C', spec);
	mkqid(&c->qid, QID(0, Qtopdir), 0, QTDIR);
	return c;
}

static Walkqid*
cmdwalk(Chan *c, Chan *nc, char **name, int nname)
{
	return devwalk(c, nc, name, nname, 0, 0, cmdgen);
}

static int
cmdstat(Chan *c, uchar *db, int n)
{
	return devstat(c, db, n, 0, 0, cmdgen);
}

static Chan *
cmdopen(Chan *c, int omode)
{
	int perm;
	Conv *cv;
	char *user;

	perm = 0;
	omode = openmode(omode);
	switch(omode) {
	case OREAD:
		perm = 4;
		break;
	case OWRITE:
		perm = 2;
		break;
	case ORDWR:
		perm = 6;
		break;
	}

	switch(TYPE(c->qid)) {
	default:
		break;
	case Qtopdir:
	case Qcmd:
	case Qconvdir:
	case Qstatus:
		if(omode != OREAD)
			error(Eperm);
		break;
	case Qclonus:
		qlock(&cmd.l);
		if(waserror()){
			qunlock(&cmd.l);
			nexterror();
		}
		cv = cmdclone(up->env->user);
		poperror();
		qunlock(&cmd.l);
		if(cv == 0)
			error(Enodev);
		mkqid(&c->qid, QID(cv->x, Qctl), 0, QTFILE);
		break;
	case Qdata:
	case Qctl:
	case Qwait:
		qlock(&cmd.l);
		cv = cmd.conv[CONV(c->qid)];
		qlock(&cv->l);
		if(waserror()){
			qunlock(&cv->l);
			qunlock(&cmd.l);
			nexterror();
		}
		user = up->env->user;
		if((perm & (cv->perm>>6)) != perm) {
			if(strcmp(user, cv->owner) != 0 ||
		 	  (perm & cv->perm) != perm)
				error(Eperm);
		}
		switch(TYPE(c->qid)){
		case Qdata:
			if(omode == OWRITE || omode == ORDWR)
				cv->wcount++;
			if(omode == OREAD || omode == ORDWR)
				cv->rcount++;
			c->mode = omode;
			break;
		case Qwait:
			if(cv->waitq == nil)
				cv->waitq = qopen(1024, Qmsg, nil, 0);
			break;
		}
		cv->inuse++;
		if(cv->inuse == 1) {
			cv->state = "Open";
			kstrdup(&cv->owner, user);
			cv->perm = 0660;
			cv->nice = 0;
		}
		poperror();
		qunlock(&cv->l);
		qunlock(&cmd.l);
		break;
	}
	c->mode = openmode(omode);
	c->flag |= COPEN;
	c->offset = 0;
	return c;
}

static void
closeconv(Conv *c)
{
	kstrdup(&c->owner, "cmd");
	kstrdup(&c->dir, rootdir);
	c->perm = 0666;
	c->state = "Closed";
	c->killonclose = 0;
	c->killed = 0;
	c->nice = 0;
	free(c->cmd);
	c->cmd = nil;
	if(c->waitq != nil){
		qfree(c->waitq);
		c->waitq = nil;
	}
	free(c->error);
	c->error = nil;
}

static void
cmdclose(Chan *c)
{
	Conv *cc;
	int r;

	if((c->flag & COPEN) == 0)
		return;

	switch(TYPE(c->qid)) {
	case Qctl:
	case Qdata:
	case Qwait:
		cc = cmd.conv[CONV(c->qid)];
		qlock(&cc->l);
		if(TYPE(c->qid) == Qdata){
			if(c->mode == OWRITE || c->mode == ORDWR){
				if(--cc->wcount == 0 && cc->wfd != -1){
					close(cc->wfd);
					cc->wfd = -1;
				}
			}
			if(c->mode == OREAD || c->mode == ORDWR){
				if(--cc->rcount == 0 && cc->rfd != -1){
					close(cc->rfd);
					cc->rfd = -1;
				}
			}
		}

		r = --cc->inuse;
		if(cc->child != nil){
			if(!cc->killed)
			if(r == 0 || (cc->killonclose && TYPE(c->qid) == Qctl)){
				oscmdkill(cc->child);
				cc->killed = 1;
			}
		}else if(r == 0)
			closeconv(cc);

		qunlock(&cc->l);
		break;
	}
}

static long
cmdread(Chan *ch, void *a, long n, vlong offset)
{
	Conv *c;
	char *p, *cmds;

	USED(offset);

	p = a;
	switch(TYPE(ch->qid)) {
	default:
		error(Eperm);
	case Qcmd:
	case Qtopdir:
	case Qconvdir:
		return devdirread(ch, a, n, 0, 0, cmdgen);
	case Qctl:
		sprint(up->genbuf, "%ld", CONV(ch->qid));
		return readstr(offset, p, n, up->genbuf);
	case Qstatus:
		c = cmd.conv[CONV(ch->qid)];
		cmds = "";
		if(c->cmd != nil)
			cmds = c->cmd->f[1];
		snprint(up->genbuf, sizeof(up->genbuf), "cmd/%d %d %s %q %q\n",
			c->x, c->inuse, c->state, c->dir, cmds);
		return readstr(offset, p, n, up->genbuf);
	case Qdata:
		c = cmd.conv[CONV(ch->qid)];
		qlock(&c->l);
		if(c->rfd == -1){
			qunlock(&c->l);
			return 0;
		}
		qunlock(&c->l);
		osenter();
		n = read(c->rfd, a, n);
		osleave();
		if(n < 0)
			oserror();
		return n;
	case Qwait:
		c = cmd.conv[CONV(ch->qid)];
		return qread(c->waitq, a, n);
	}
}

static int
cmdstarted(void *a)
{
	Conv *c;

	c = a;
	return c->child != nil || c->error != nil;
}

enum
{
	CMdir,
	CMexec,
	CMkill,
	CMnice,
	CMkillonclose
};

static
Cmdtab cmdtab[] = {
	CMdir,	"dir",	2,
	CMexec,	"exec",	0,
	CMkill,	"kill",	1,
	CMnice,	"nice",	0,
	CMkillonclose, "killonclose", 0,
};

static long
cmdwrite(Chan *ch, void *a, long n, vlong offset)
{
	int r;
	Conv *c;
	Cmdbuf *cb;
	Cmdtab *ct;

	USED(offset);

	switch(TYPE(ch->qid)) {
	default:
		error(Eperm);
	case Qctl:
		c = cmd.conv[CONV(ch->qid)];
		cb = parsecmd(a, n);
		if(waserror()){
			free(cb);
			nexterror();
		}
		ct = lookupcmd(cb, cmdtab, nelem(cmdtab));
		switch(ct->index){
		case CMdir:
			kstrdup(&c->dir, cb->f[1]);
			break;
		case CMexec:
			poperror();	/* cb */
			qlock(&c->l);
			if(waserror()){
				qunlock(&c->l);
				free(cb);
				nexterror();
			}
			if(c->child != nil || c->cmd != nil || c->wfd != -1 || c->rfd != -1)
				error(Einuse);
			if(cb->nf < 1)
				error(Etoosmall);
			kproc("cmdproc", cmdproc, c, 0);	/* cmdproc held back until unlock below */
			free(c->cmd);
			c->cmd = cb;	/* don't free cb */
			c->state = "Execute";
			poperror();
			qunlock(&c->l);
			while(waserror())
				;
			Sleep(&c->startr, cmdstarted, c);
			poperror();
			if(c->error)
				error(c->error);
			return n;	/* avoid free(cb) below */
		case CMkill:
			qlock(&c->l);
			if(waserror()){
				qunlock(&c->l);
				nexterror();
			}
			if(c->child == nil)
				error("not started");
			if(oscmdkill(c->child) < 0)
				oserror();
			poperror();
			qunlock(&c->l);
			break;
		case CMnice:
			c->nice = cb->nf > 1? atoi(cb->f[1]): 1;
			break;
		case CMkillonclose:
			c->killonclose = 1;
			break;
		}
		poperror();
		free(cb);
		break;
	case Qdata:
		c = cmd.conv[CONV(ch->qid)];
		qlock(&c->l);
		if(c->wfd == -1){
			qunlock(&c->l);
			error(Ehungup);
		}
		qunlock(&c->l);
		osenter();
		r = write(c->wfd, a, n);
		osleave();
		if(r == 0)
			error(Ehungup);
		if(r < 0) {
			/* XXX perhaps should kill writer "write on closed pipe" here, 2nd time around? */
			oserror();
		}
		return r;
	}
	return n;
}

static int
cmdwstat(Chan *c, uchar *dp, int n)
{
	Dir *d;
	Conv *cv;

	switch(TYPE(c->qid)){
	default:
		error(Eperm);
	case Qctl:
	case Qdata:
		d = malloc(sizeof(*d)+n);
		if(d == nil)
			error(Enomem);
		if(waserror()){
			free(d);
			nexterror();
		}
		n = convM2D(dp, n, d, (char*)&d[1]);
		if(n == 0)
			error(Eshortstat);
		cv = cmd.conv[CONV(c->qid)];
		if(!iseve() && strcmp(up->env->user, cv->owner) != 0)
			error(Eperm);
		if(!emptystr(d->uid))
			kstrdup(&cv->owner, d->uid);
		if(d->mode != ~0UL)
			cv->perm = d->mode & 0777;
		poperror();
		free(d);
		break;
	}
	return n;
}

static Conv*
cmdclone(char *user)
{
	Conv *c, **pp, **ep;

	c = nil;
	ep = &cmd.conv[cmd.maxconv];
	for(pp = cmd.conv; pp < ep; pp++) {
		c = *pp;
		if(c == nil) {
			c = malloc(sizeof(Conv));
			if(c == nil)
				error(Enomem);
			qlock(&c->l);
			c->inuse = 1;
			c->x = pp - cmd.conv;
			cmd.nc++;
			*pp = c;
			break;
		}
		if(canqlock(&c->l)){
			if(c->inuse == 0 && c->child == nil)
				break;
			qunlock(&c->l);
		}
	}
	if(pp >= ep)
		return nil;

	c->inuse = 1;
	kstrdup(&c->owner, user);
	kstrdup(&c->dir, rootdir);
	c->perm = 0660;
	c->state = "Closed";
	c->rfd = -1;
	c->wfd = -1;

	qunlock(&c->l);
	return c;
}

static void
cmdproc(void *a)
{
	Conv *c;
	int n;
	char status[ERRMAX];
	void *t;

	c = a;
	qlock(&c->l);
	if(Debug)
		print("f[0]=%q f[1]=%q\n", c->cmd->f[0], c->cmd->f[1]);
	if(waserror()){
		if(Debug)
			print("failed: %q\n", up->env->errstr);
		kstrdup(&c->error, up->env->errstr);
		c->state = "Done";
		qunlock(&c->l);
		Wakeup(&c->startr);
		pexit("cmdproc", 0);
	}
	t = oscmd(c->cmd->f+1, c->nice, c->dir, &c->rfd, &c->wfd);
	if(t == nil)
		oserror();
	c->child = t;	/* to allow oscmdkill */
	poperror();
	qunlock(&c->l);
	Wakeup(&c->startr);
	if(Debug)
		print("started\n");
	while(waserror())
		oscmdkill(t);
	osenter();
	n = oscmdwait(t, status, sizeof(status));
	osleave();
	if(n < 0){
		oserrstr(up->genbuf, sizeof(up->genbuf));
		n = snprint(status, sizeof(status), "0 0 0 0 %q", up->genbuf);
	}
	qlock(&c->l);
	c->child = nil;
	oscmdfree(t);
	if(Debug){
		status[n]=0;
		print("done %d %d: %q\n", c->rfd, c->wfd, status);
	}
	if(c->inuse > 0){
		c->state = "Done";
		if(c->waitq != nil)
			qproduce(c->waitq, status, n);
	}else
		closeconv(c);
	qunlock(&c->l);
	pexit("", 0);
}

Dev cmddevtab = {
	'C',
	"cmd",

	cmdinit,
	cmdattach,
	cmdwalk,
	cmdstat,
	cmdopen,
	devcreate,
	cmdclose,
	cmdread,
	devbread,
	cmdwrite,
	devbwrite,
	devremove,
	cmdwstat
};
