#include	"dat.h"
#include	"fns.h"
#include	"error.h"
#include	"ip.h"

enum
{
	Qtopdir		= 1,	/* top level directory */
	Qtopbase,
	Qarp=	Qtopbase,
/*	Qiproute, */
/*	Qipselftab,	*/
	Qndb,

	Qprotodir,		/* directory for a protocol */
	Qprotobase,
	Qclone=	Qprotobase,
	Qstats,

	Qconvdir,		/* directory for a conversation */
	Qconvbase,
	Qctl=	Qconvbase,
	Qdata,
	Qlisten,
	Qlocal,
	Qremote,
	Qstatus,

	Logtype=	5,
	Masktype=	(1<<Logtype)-1,
	Logconv=	12,
	Maskconv=	(1<<Logconv)-1,
	Shiftconv=	Logtype,
	Logproto=	8,
	Maskproto=	(1<<Logproto)-1,
	Shiftproto=	Logtype + Logconv,

	Statelen = 256,

	Nfs=	1,

	Maxproto	= 4,
	MAXCONV		= 4096
};
#define TYPE(x) 	( ((ulong)(x).path) & Masktype )
#define CONV(x) 	( (((ulong)(x).path) >> Shiftconv) & Maskconv )
#define PROTO(x) 	( (((ulong)(x).path) >> Shiftproto) & Maskproto )
#define QID(p, c, y) 	( ((p)<<(Shiftproto)) | ((c)<<Shiftconv) | (y) )

enum
{
	Idle=		0,
	Announcing=	1,
	Announced=	2,
	Connecting=	3,
	Connected=	4,
	Hungup=	5,
};

struct Conv
{
	QLock	l;

	int	x;	/* conversation index */
	Proto*	p;

	uchar	laddr[IPaddrlen];	/* local IP address */
	uchar	raddr[IPaddrlen];	/* remote IP address */
	int	restricted;	/* remote port is restricted */
	ushort	lport;	/* local port number */
	ushort	rport;	/* remote port number */

	char*	owner;	/* protections */
	int	perm;
	int	inuse;	/* opens of listen/data/ctl */
	int	state;

	/* udp specific */
	int	headers;	/* data src/dst headers in udp */

	char	cerr[ERRMAX];

	QLock	listenq;

	void*	ptcl;	/* protocol specific stuff */

	int	sfd;
	QLock	wlock;	/* prevent data from being split by concurrent writes */
};

struct Proto
{
	QLock	l;
	int	x;
	int	ipproto;
	int	stype;
	char*	name;
	int	maxconv;
	Fs*	f;	/* file system this proto is part of */
	Conv**	conv;	/* array of conversations */
	int	pctlsize;	/* size of per protocol ctl block */
	int	nc;	/* number of conversations */
	int	ac;
	Qid	qid;	/* qid for protocol directory */
	/* port allocation isn't done here when hosted */

	void*	priv;
};

/*
 * one per IP protocol stack
 */
struct Fs
{
	RWlock	l;
	int	dev;

	int	np;
	Proto*	p[Maxproto+1];	/* list of supported protocols */
	Proto*	t2p[256];	/* vector of all protocols */

	char	ndb[1024];	/* an ndb entry for this interface */
	int	ndbvers;
	long	ndbmtime;
};

static	Fs	*ipfs[Nfs];	/* attached fs's */
static	char	network[] = "network";
static	char* ipstates[] = {
	"Closed",	/* Idle */
	"Announcing",
	"Announced",
	"Connecting",
	"Established",	/* Connected */
	"Closed",	/* Hungup */
};

static	Conv*	protoclone(Proto*, char*, int);
static	Conv*	newconv(Proto*, Conv **);
static	void	setladdr(Conv*);
static	ulong	ip6w(uchar*);
static	void	ipw6(uchar*, ulong);

static int
ip3gen(Chan *c, int i, Dir *dp)
{
	Qid q;
	Conv *cv;
	char *p;

	cv = ipfs[c->dev]->p[PROTO(c->qid)]->conv[CONV(c->qid)];
	if(cv->owner == nil)
		kstrdup(&cv->owner, eve);
	mkqid(&q, QID(PROTO(c->qid), CONV(c->qid), i), 0, QTFILE);

	switch(i) {
	default:
		return -1;
	case Qctl:
		devdir(c, q, "ctl", 0, cv->owner, cv->perm, dp);
		return 1;
	case Qdata:
		devdir(c, q, "data", 0, cv->owner, cv->perm, dp);
		return 1;
	case Qlisten:
		devdir(c, q, "listen", 0, cv->owner, cv->perm, dp);
		return 1;
	case Qlocal:
		p = "local";
		break;
	case Qremote:
		p = "remote";
		break;
	case Qstatus:
		p = "status";
		break;
	}
	devdir(c, q, p, 0, cv->owner, 0444, dp);
	return 1;
}

static int
ip2gen(Chan *c, int i, Dir *dp)
{
	Qid q;

	switch(i) {
	case Qclone:
		mkqid(&q, QID(PROTO(c->qid), 0, Qclone), 0, QTFILE);
		devdir(c, q, "clone", 0, network, 0666, dp);
		return 1;
	case Qstats:
		mkqid(&q, QID(PROTO(c->qid), 0, Qstats), 0, QTFILE);
		devdir(c, q, "stats", 0, network, 0444, dp);
		return 1;
	}	
	return -1;
}

static int
ip1gen(Chan *c, int i, Dir *dp)
{
	Qid q;
	char *p;
	int prot;
	int len = 0;
	Fs *f;
	extern ulong	kerndate;

	f = ipfs[c->dev];

	prot = 0664;
	mkqid(&q, QID(0, 0, i), 0, QTFILE);
	switch(i) {
	default:
		return -1;
	case Qarp:
		p = "arp";
		break;
	case Qndb:
		p = "ndb";
		len = strlen(ipfs[c->dev]->ndb);
		break;
/*	case Qiproute:
		p = "iproute";
		break;
	case Qipselftab:
		p = "ipselftab";
		prot = 0444;
		break;
	case Qiprouter:
		p = "iprouter";
		break;
	case Qlog:
		p = "log";
		break;
*/
	}
	devdir(c, q, p, len, network, prot, dp);
	if(i == Qndb && f->ndbmtime > kerndate)
		dp->mtime = f->ndbmtime;
	return 1;
}

static int
ipgen(Chan *c, char *name, Dirtab *tab, int x, int s, Dir *dp)
{
	Qid q;
	Conv *cv;
	Fs *f;

	USED(name);
	USED(tab);
	USED(x);
	f = ipfs[c->dev];

	switch(TYPE(c->qid)) {
	case Qtopdir:
		if(s == DEVDOTDOT){
			mkqid(&q, QID(0, 0, Qtopdir), 0, QTDIR);
			sprint(up->genbuf, "#I%lud", c->dev);
			devdir(c, q, up->genbuf, 0, network, 0555, dp);
			return 1;
		}
		if(s < f->np) {
/*			if(f->p[s]->connect == nil)
				return 0;	/* protocol with no user interface */
			mkqid(&q, QID(s, 0, Qprotodir), 0, QTDIR);
			devdir(c, q, f->p[s]->name, 0, network, 0555, dp);
			return 1;
		}
		s -= f->np;
		return ip1gen(c, s+Qtopbase, dp);
	case Qarp:
	case Qndb:
/*	case Qiproute:
	case Qiprouter:
	case Qipselftab:	*/
		return ip1gen(c, TYPE(c->qid), dp);
	case Qprotodir:
		if(s == DEVDOTDOT){
			mkqid(&q, QID(0, 0, Qtopdir), 0, QTDIR);
			sprint(up->genbuf, "#I%lud", c->dev);
			devdir(c, q, up->genbuf, 0, network, 0555, dp);
			return 1;
		}
		if(s < f->p[PROTO(c->qid)]->ac) {
			cv = f->p[PROTO(c->qid)]->conv[s];
			sprint(up->genbuf, "%d", s);
			mkqid(&q, QID(PROTO(c->qid), s, Qconvdir), 0, QTDIR);
			devdir(c, q, up->genbuf, 0, cv->owner, 0555, dp);
			return 1;
		}
		s -= f->p[PROTO(c->qid)]->ac;
		return ip2gen(c, s+Qprotobase, dp);
	case Qclone:
	case Qstats:
		return ip2gen(c, TYPE(c->qid), dp);
	case Qconvdir:
		if(s == DEVDOTDOT){
			s = PROTO(c->qid);
			mkqid(&q, QID(s, 0, Qprotodir), 0, QTDIR);
			devdir(c, q, f->p[s]->name, 0, network, 0555, dp);
			return 1;
		}
		return ip3gen(c, s+Qconvbase, dp);
	case Qctl:
	case Qdata:
	case Qlisten:
	case Qlocal:
	case Qremote:
	case Qstatus:
		return ip3gen(c, TYPE(c->qid), dp);
	}
	return -1;
}

static void
newproto(char *name, int type, int maxconv)
{
	Proto *p;

	p = smalloc(sizeof(*p));
	p->name = name;
	p->stype = type;
	p->ipproto = type+1;	/* temporary */
	p->nc = maxconv;
	if(Fsproto(ipfs[0], p))
		panic("can't newproto %s", name);
}

void
ipinit(void)
{
	ipfs[0] = malloc(sizeof(Fs));
	if(ipfs[0] == nil)
		panic("no memory for IP stack");

	newproto("udp", S_UDP, 64);
	newproto("tcp", S_TCP, 2048);

	fmtinstall('i', eipfmt);
	fmtinstall('I', eipfmt);
	fmtinstall('E', eipfmt);
	fmtinstall('V', eipfmt);
	fmtinstall('M', eipfmt);
}

Chan *
ipattach(char *spec)
{
	Chan *c;

	if(atoi(spec) != 0)
		error("bad specification");

	c = devattach('I', spec);
	mkqid(&c->qid, QID(0, 0, Qtopdir), 0, QTDIR);
	c->dev = 0;

	return c;
}

static Walkqid*
ipwalk(Chan* c, Chan *nc, char **name, int nname)
{
	return devwalk(c, nc, name, nname, nil, 0, ipgen);
}

static int
ipstat(Chan *c, uchar *db, int n)
{
	return devstat(c, db, n, 0, 0, ipgen);
}

static int m2p[] = {
	4,
	2,
	6,
};

static Chan *
ipopen(Chan *c, int omode)
{
	Conv *cv, *nc;
	Proto *p;
	ulong raddr;
	ushort rport;
	int perm, sfd;
	Fs *f;

	perm = m2p[omode&3];

	f = ipfs[c->dev];

	switch(TYPE(c->qid)) {
	default:
		break;
	case Qtopdir:
	case Qprotodir:
	case Qconvdir:
	case Qstatus:
	case Qremote:
	case Qlocal:
	case Qstats:
	/* case Qipselftab: */
		if(omode != OREAD)
			error(Eperm);
		break;
	case Qndb:
		if(omode & (OWRITE|OTRUNC) && !iseve())
			error(Eperm);
		if((omode & (OWRITE|OTRUNC)) == (OWRITE|OTRUNC)){
			f->ndb[0] = 0;
			f->ndbvers++;
		}
		break;
	case Qclone:
		p = f->p[PROTO(c->qid)];
		cv = protoclone(p, up->env->user, -1);
		if(cv == 0)
			error(Enodev);
		mkqid(&c->qid, QID(p->x, cv->x, Qctl), 0, QTFILE);
		break;
	case Qdata:
	case Qctl:
		p = f->p[PROTO(c->qid)];
		qlock(&p->l);
		cv = p->conv[CONV(c->qid)];
		qlock(&cv->l);
		if(waserror()){
			qunlock(&cv->l);
			qunlock(&p->l);
			nexterror();
		}
		if((perm & (cv->perm>>6)) != perm) {
			if(strcmp(up->env->user, cv->owner) != 0)
				error(Eperm);
			if((perm & cv->perm) != perm)
				error(Eperm);
		}
		cv->inuse++;
		if(cv->inuse == 1) {
			kstrdup(&cv->owner, up->env->user);
			cv->perm = 0660;
			if(cv->sfd < 0)
				cv->sfd = so_socket(p->stype);
		}
		poperror();
		qunlock(&cv->l);
		qunlock(&p->l);
		break;
	case Qlisten:
		p = f->p[PROTO(c->qid)];
		cv = p->conv[CONV(c->qid)];
		if((perm & (cv->perm>>6)) != perm){
			if(strcmp(up->env->user, cv->owner) != 0)
				error(Eperm);
			if((perm & cv->perm) != perm)
				error(Eperm);
		}

		if(cv->state != Announced)
			error("not announced");

		qlock(&cv->listenq);
		if(waserror()){
			qunlock(&cv->listenq);
			nexterror();
		}

		sfd = so_accept(cv->sfd, &raddr, &rport);

		nc = protoclone(p, up->env->user, sfd);
		if(nc == 0) {
			so_close(sfd);
			error(Enodev);
		}
		ipw6(nc->raddr, raddr);
		nc->rport = rport;
		setladdr(nc);
		nc->state = Connected;
		mkqid(&c->qid, QID(PROTO(c->qid), nc->x, Qctl), 0, QTFILE);

		poperror();
		qunlock(&cv->listenq);
		break;
	}
	c->mode = openmode(omode);
	c->flag |= COPEN;
	c->offset = 0;
	return c;
}

static void
closeconv(Conv *cv)
{
	int fd;

	qlock(&cv->l);

	if(--cv->inuse > 0) {
		qunlock(&cv->l);
		return;
	}

	if(waserror()){
		qunlock(&cv->l);
		return;
	}
	kstrdup(&cv->owner, network);
	cv->perm = 0660;
	/* cv->p->close(cv); */
	cv->state = Idle;
	cv->restricted = 0;
	fd = cv->sfd;
	cv->sfd = -1;
	if(fd >= 0)
		so_close(fd);
	poperror();
	qunlock(&cv->l);
}

static void
ipclose(Chan *c)
{
	Fs *f;

	f = ipfs[c->dev];
	switch(TYPE(c->qid)) {
	case Qdata:
	case Qctl:
		if(c->flag & COPEN)
			closeconv(f->p[PROTO(c->qid)]->conv[CONV(c->qid)]);
		break;
	}
}

static long
ipread(Chan *ch, void *a, long n, vlong off)
{
	int r;
	Conv *c;
	Proto *x;
	char *p, *s;
	Fs *f;
	ulong offset = off;

	f = ipfs[ch->dev];

	p = a;
	switch(TYPE(ch->qid)) {
	default:
		error(Eperm);
	case Qprotodir:
	case Qtopdir:
	case Qconvdir:
		return devdirread(ch, a, n, 0, 0, ipgen);
	case Qarp:
		error(Eperm);	/* TO DO */
	case Qndb:
		return readstr(off, a, n, f->ndb);
	case Qctl:
		sprint(up->genbuf, "%lud", CONV(ch->qid));
		return readstr(offset, p, n, up->genbuf);
	case Qremote:
		x = f->p[PROTO(ch->qid)];
		c = x->conv[CONV(ch->qid)];
		sprint(up->genbuf, "%I!%d\n", c->raddr, c->rport);
		return readstr(offset, p, n, up->genbuf);
	case Qlocal:
		x = f->p[PROTO(ch->qid)];
		c = x->conv[CONV(ch->qid)];
		sprint(up->genbuf, "%I!%d\n", c->laddr, c->lport);
		return readstr(offset, p, n, up->genbuf);
	case Qstatus:
		x = f->p[PROTO(ch->qid)];
		c = x->conv[CONV(ch->qid)];
		s = smalloc(Statelen);
		if(waserror()){
			free(s);
			nexterror();
		}
		snprint(s, Statelen, "%s\n", ipstates[c->state]);
		n = readstr(offset, p, n, s);
		poperror();
		free(s);
		return n;
	case Qdata:
		x = f->p[PROTO(ch->qid)];
		c = x->conv[CONV(ch->qid)];
		if(c->sfd < 0)
			error(Ehungup);
		if(c->headers) {
			if(n < c->headers)
				error(Ebadarg);
			p = a;
			r = so_recv(c->sfd, p + c->headers, n - c->headers, p, c->headers);
			if(r > 0)
				r += c->headers;
		} else
			r = so_recv(c->sfd, a, n, nil, 0);
		if(r < 0)
			oserror();
		return r;
	case Qstats:
		error("stats not implemented");
		return n;
	}
}

static void
setladdr(Conv *c)
{
	ulong laddr;

	/* TO DO: this can't be right for hosts with several addresses */
	so_getsockname(c->sfd, &laddr, &c->lport);
	ipw6(c->laddr, laddr);
}

/*
 * pick a local port and set it
 */
static void
setlport(Conv *c)
{
	ulong laddr;

	so_bind(c->sfd, c->restricted, c->lport);
	if(c->lport == 0)
		so_getsockname(c->sfd, &laddr, &c->lport);
}

static int
portno(char *p)
{
	long n;
	char *e;

	n = strtoul(p, &e, 0);
	if(p == e)
		error("non-numeric port number");
	return n;
}

/*
 *  set a local address and port from a string of the form
 *	[address!]port[!r]
 */
static void
setladdrport(Conv *c, char *str, int announcing)
{
	char *p;
	int lport;

	/*
	 *  ignore restricted part if it exists.  it's
	 *  meaningless on local ports.
	 */
	p = strchr(str, '!');
	if(p != nil){
		*p++ = 0;
		if(strcmp(p, "r") == 0)
			p = nil;
	}

	c->lport = 0;
	if(p == nil){
		if(announcing)
			ipmove(c->laddr, IPnoaddr);
		else if(0)
			setladdr(c);
		p = str;
	} else {
		if(strcmp(str, "*") == 0)
			ipmove(c->laddr, IPnoaddr);
		else
			parseip(c->laddr, str);
	}

	if(announcing && strcmp(p, "*") == 0){
		if(!iseve())
			error(Eperm);
		c->lport = 0;
		setlport(c);
		return;
	}

	lport = portno(p);
	if(lport <= 0)
		c->lport = 0;
	else
		c->lport = lport;

	setlport(c);
}

static char*
setraddrport(Conv *c, char *str)
{
	char *p;

	p = strchr(str, '!');
	if(p == nil)
		return "malformed address";
	*p++ = 0;
	parseip(c->raddr, str);
	c->rport = portno(p);
	p = strchr(p, '!');
	if(p){
		if(strstr(p, "!r") != nil)
			c->restricted = 1;
	}
	return nil;
}

static void
connectctlmsg(Proto *x, Conv *c, Cmdbuf *cb)
{
	char *p;

	USED(x);
	if(c->state != Idle)
		error(Econinuse);
	c->state = Connecting;
	c->cerr[0] = '\0';
	switch(cb->nf) {
	default:
		error("bad args to connect");
	case 2:
		p = setraddrport(c, cb->f[1]);
		if(p != nil)
			error(p);
		break;
	case 3:
		p = setraddrport(c, cb->f[1]);
		if(p != nil)
			error(p);
		c->lport = portno(cb->f[2]);
		setlport(c);
		break;
	}
	qunlock(&c->l);
	if(waserror()){
		qlock(&c->l);
		c->state = Connected;	/* sic */
		nexterror();
	}
	/* p = x->connect(c, cb->f, cb->nf); */
	so_connect(c->sfd, ip6w(c->raddr), c->rport);
	qlock(&c->l);
	poperror();
	setladdr(c);
	c->state = Connected;
}

static void
announcectlmsg(Proto *x, Conv *c, Cmdbuf *cb)
{
	if(c->state != Idle)
		error(Econinuse);
	c->state = Announcing;
	c->cerr[0] = '\0';
	ipmove(c->raddr, IPnoaddr);
	c->rport = 0;
	switch(cb->nf){
	default:
		error("bad args to announce");
	case 2:
		setladdrport(c, cb->f[1], 1);
		break;
	}
	USED(x);
	/* p = x->announce(c, cb->f, cb->nf); */
	if(c->p->stype != S_UDP){
		qunlock(&c->l);
		if(waserror()){
			c->state = Announced;	/* sic */
			qlock(&c->l);
			nexterror();
		}
		so_listen(c->sfd);
		qlock(&c->l);
		poperror();
	}
	c->state = Announced;
}

static void
bindctlmsg(Proto *x, Conv *c, Cmdbuf *cb)
{
	USED(x);
	switch(cb->nf){
	default:
		error("bad args to bind");
	case 2:
		setladdrport(c, cb->f[1], 0);
		break;
	}
}

static long
ipwrite(Chan *ch, void *a, long n, vlong off)
{
	Conv *c;
	Proto *x;
	char *p;
	Cmdbuf *cb;
	Fs *f;

	f = ipfs[ch->dev];

	switch(TYPE(ch->qid)) {
	default:
		error(Eperm);
	case Qdata:
		x = f->p[PROTO(ch->qid)];
		c = x->conv[CONV(ch->qid)];
		if(c->sfd < 0)
			error(Ehungup);
		qlock(&c->wlock);
		if(waserror()){
			qunlock(&c->wlock);
			nexterror();
		}
		if(c->headers) {
			if(n < c->headers)
				error(Eshort);
			p = a;
			n = so_send(c->sfd, p + c->headers, n - c->headers, p, c->headers);
			if(n >= 0)
				n += c->headers;
		} else
			n = so_send(c->sfd, a, n, nil, 0);
		poperror();
		qunlock(&c->wlock);
		if(n < 0)
			oserror();
		break;
	case Qarp:
		return arpwrite(a, n);
	case Qndb:
		if(off > strlen(f->ndb))
			error(Eio);
		if(off+n >= sizeof(f->ndb)-1)
			error(Eio);
		memmove(f->ndb+off, a, n);
		f->ndb[off+n] = 0;
		f->ndbvers++;
		f->ndbmtime = seconds();
		break;
	case Qctl:
		x = f->p[PROTO(ch->qid)];
		c = x->conv[CONV(ch->qid)];
		cb = parsecmd(a, n);
		qlock(&c->l);
		if(waserror()){
			qunlock(&c->l);
			free(cb);
			nexterror();
		}
		if(cb->nf < 1)
			error("short control request");
		if(strcmp(cb->f[0], "connect") == 0)
			connectctlmsg(x, c, cb);
		else if(strcmp(cb->f[0], "announce") == 0)
			announcectlmsg(x, c, cb);
		else if(strcmp(cb->f[0], "bind") == 0)
			bindctlmsg(x, c, cb);
		else if(strcmp(cb->f[0], "ttl") == 0){
			/* ignored */
		} else if(strcmp(cb->f[0], "tos") == 0){
			/* ignored */
		} else if(strcmp(cb->f[0], "ignoreadvice") == 0){
			/* ignored */
		} else if(strcmp(cb->f[0], "headers4") == 0){
			if(c->p->stype != S_UDP)
				error(Enoctl);
			c->headers = OUdphdrlenv4;
		} else if(strcmp(cb->f[0], "oldheaders") == 0){
			if(c->p->stype != S_UDP)
				error(Enoctl);
			c->headers = OUdphdrlen;
		} else if(strcmp(cb->f[0], "headers") == 0){
			if(c->p->stype != S_UDP)
				error(Enoctl);
			c->headers = Udphdrlen;
		} else if(strcmp(cb->f[0], "hangup") == 0){
			if(c->p->stype != S_TCP)
				error(Enoctl);
			qunlock(&c->l);
			if(waserror()){
				qlock(&c->l);
				nexterror();
			}
			/* TO DO: check fd status if socket close/hangup interrupted */
			if(c->sfd >= 0 && so_hangup(c->sfd, 1) < 0)
				oserror();
			qlock(&c->l);
			poperror();
			c->sfd = -1;
			c->state = Hungup;
		} else if(strcmp(cb->f[0], "keepalive") == 0){
			if(c->p->stype != S_TCP)
				error(Enoctl);
			if(c->sfd < 0)
				error("not connected");
			so_keepalive(c->sfd, cb->nf>1? atoi(cb->f[1]): 0);
		} else
			error(Enoctl);
		poperror();
		qunlock(&c->l);
		free(cb);
		break;
	}
	return n;
}

static int
ipwstat(Chan *c, uchar *dp, int n)
{
	Dir *d;
	Conv *cv;
	Proto *p;
	Fs *f;

	f = ipfs[c->dev];
	switch(TYPE(c->qid)) {
	default:
		error(Eperm);
		break;
	case Qctl:
	case Qdata:
		break;
	}

	d = smalloc(sizeof(*d)+n);
	if(waserror()){
		free(d);
		nexterror();
	}
	n = convM2D(dp, n, d, (char*)&d[1]);
	if(n == 0)
		error(Eshortstat);
	p = f->p[PROTO(c->qid)];
	cv = p->conv[CONV(c->qid)];
	if(!iseve() && strcmp(up->env->user, cv->owner) != 0)
		error(Eperm);
	if(!emptystr(d->uid))
		kstrdup(&cv->owner, d->uid);
	if(d->mode != ~0UL)
		cv->perm = d->mode & 0777;
	poperror();
	free(d);
	return n;
}

static Conv*
protoclone(Proto *p, char *user, int nfd)
{
	Conv *c, **pp, **ep, **np;
	int maxconv;

	c = 0;
	qlock(&p->l);
	if(waserror()) {
		qunlock(&p->l);
		nexterror();
	}
	ep = &p->conv[p->nc];
	for(pp = p->conv; pp < ep; pp++) {
		c = *pp;
		if(c == 0) {
			c = newconv(p, pp);
			break;
		}
		if(canqlock(&c->l)){
			if(c->inuse == 0)
				break;
			qunlock(&c->l);
		}
	}
	if(pp >= ep) {
		if(p->nc >= MAXCONV) {
			qunlock(&p->l);
			poperror();
			return 0;
		}
		maxconv = 2 * p->nc;
		if(maxconv > MAXCONV)
			maxconv = MAXCONV;
		np = realloc(p->conv, sizeof(Conv*) * maxconv);
		if(np == nil)
			error(Enomem);
		p->conv = np;
		pp = &p->conv[p->nc];
		memset(pp, 0, sizeof(Conv*)*(maxconv - p->nc));
		p->nc = maxconv;
		c = newconv(p, pp);
	}

	c->inuse = 1;
	kstrdup(&c->owner, user);
	c->perm = 0660;
	c->state = Idle;
	ipmove(c->laddr, IPnoaddr);
	ipmove(c->raddr, IPnoaddr);
	c->lport = 0;
	c->rport = 0;
	c->restricted = 0;
	c->sfd = nfd;
	if(nfd == -1)
		c->sfd = so_socket(p->stype);

	qunlock(&c->l);
	qunlock(&p->l);
	poperror();
	return c;
}

static Conv*
newconv(Proto *p, Conv **pp)
{
	Conv *c;

	*pp = c = malloc(sizeof(Conv));
	if(c == 0)
		error(Enomem);
	qlock(&c->l);
	c->inuse = 1;
	c->p = p;
	c->x = pp - p->conv;
	p->ac++;
	return c;
}

int
arpwrite(char *s, int len)
{
	int n;
	char *f[4], buf[256];

	if(len >= sizeof(buf))
		len = sizeof(buf)-1;
	memmove(buf, s, len);
	buf[len] = 0;
	if(len > 0 && buf[len-1] == '\n')
		buf[len-1] = 0;

	n = getfields(buf, f, 4, 1, " ");
	if(strcmp(f[0], "add") == 0) {
		if(n == 3) {
			arpadd(f[1], f[2], n);
			return len;
		}
	}
	error("bad arp request");

	return len;
}

Dev ipdevtab = {
	'I',
	"ip",

	ipinit,
	ipattach,
	ipwalk,
	ipstat,
	ipopen,
	devcreate,
	ipclose,
	ipread,
	devbread,
	ipwrite,
	devbwrite,
	devremove,
	ipwstat
};

int
Fsproto(Fs *f, Proto *p)
{
	if(f->np >= Maxproto)
		return -1;

	p->f = f;

	if(p->ipproto > 0){
		if(f->t2p[p->ipproto] != nil)
			return -1;
		f->t2p[p->ipproto] = p;
	}

	p->qid.type = QTDIR;
	p->qid.path = QID(f->np, 0, Qprotodir);
	p->conv = malloc(sizeof(Conv*)*(p->nc+1));
	if(p->conv == nil)
		panic("Fsproto");

	p->x = f->np;
	f->p[f->np++] = p;

	return 0;
}

/*
 *  return true if this protocol is
 *  built in
 */
int
Fsbuiltinproto(Fs* f, uchar proto)
{
	return f->t2p[proto] != nil;
}

/*
 * temporarily convert ipv6 addresses to ipv4 as ulong for
 * ipif.c interface
 */
static ulong
ip6w(uchar *a)
{
	uchar v4[IPv4addrlen];

	v6tov4(v4, a);
	return (((((v4[0]<<8)|v4[1])<<8)|v4[2])<<8)|v4[3];
}

static void
ipw6(uchar *a, ulong w)
{
	memmove(a, v4prefix, IPv4off);
	hnputl(a+IPv4off, w);
}
