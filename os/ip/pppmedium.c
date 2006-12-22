#include "u.h"
#include "../port/lib.h"
#include "mem.h"
#include "dat.h"
#include "fns.h"
#include "../port/error.h"

#include "ip.h"
#include "kernel.h"
#include "ppp.h"

static void	pppreader(void *a);
static void	pppbind(Ipifc *ifc, int argc, char **argv);
static void	pppunbind(Ipifc *ifc);
static void	pppbwrite(Ipifc *ifc, Block *bp, int version, uchar *ip);
static void	deadremote(Ipifc *ifc);

Medium pppmedium =
{
.name=	"ppp",
.hsize=	4,
.mintu=	Minmtu,
.maxtu=	Maxmtu,
.maclen=	0,
.bind=	pppbind,
.unbind=	pppunbind,
.bwrite=	pppbwrite,
.unbindonclose=	0,		/* don't unbind on last close */
};

/*
 *  called to bind an IP ifc to an ethernet device
 *  called with ifc wlock'd
 */
static void
pppbind(Ipifc *ifc, int argc, char **argv)
{
	PPP *ppp;
	Ipaddr ipaddr, remip;
	int mtu, framing;
	char *chapname, *secret;

	if(argc < 3)
		error(Ebadarg);

	ipmove(ipaddr, IPnoaddr);
	ipmove(remip, IPnoaddr);
	mtu = Defmtu;
	framing = 1;
	chapname = nil;
	secret = nil;

	switch(argc){
	default:
	case 9:
		if(argv[8][0] != '-')
			secret = argv[8];
	case 8:
		if(argv[7][0] != '-')
			chapname = argv[7];
	case 7:
		if(argv[6][0] != '-')
			framing = strtoul(argv[6], 0, 0);
	case 6:
		if(argv[5][0] != '-')
			mtu = strtoul(argv[5], 0, 0);
	case 5:
		if(argv[4][0] != '-')
			parseip(remip, argv[4]);
	case 4:
		if(argv[3][0] != '-')
			parseip(ipaddr, argv[3]);
	case 3:
		break;
	}

	ppp = smalloc(sizeof(*ppp));
	ppp->ifc = ifc;
	ppp->f = ifc->conv->p->f;
	ifc->arg = ppp;
	if(waserror()){
		pppunbind(ifc);
		nexterror();
	}
	if(pppopen(ppp, argv[2], ipaddr, remip, mtu, framing, chapname, secret) == nil)
		error("ppp open failed");
	poperror();
	kproc("pppreader", pppreader, ifc, KPDUPPG|KPDUPFDG);
}

static void
pppreader(void *a)
{
	Ipifc *ifc;
	Block *bp;
	PPP *ppp;

	ifc = a;
	ppp = ifc->arg;
	ppp->readp = up;	/* hide identity under a rock for unbind */
	setpri(PriHi);

	if(waserror()){
		netlog(ppp->f, Logppp, "pppreader: %I: %s\n", ppp->local, up->env->errstr);
		ppp->readp = 0;
		deadremote(ifc);
		pexit("hangup", 1);
	}

	for(;;){
		bp = pppread(ppp);
		if(bp == nil)
			error("hungup");
		if(!canrlock(ifc)){
			freeb(bp);
			continue;
		}
		if(waserror()){
			runlock(ifc);
			nexterror();
		}
		ifc->in++;
		if(ifc->lifc == nil)
			freeb(bp);
		else
			ipiput(ppp->f, ifc, bp);
		runlock(ifc);
		poperror();
	}
}

/*
 *  called with ifc wlock'd
 */
static void
pppunbind(Ipifc *ifc)
{
	PPP *ppp = ifc->arg;

	if(ppp == nil)
		return;
	if(ppp->readp)
		postnote(ppp->readp, 1, "unbind", 0);
	if(ppp->timep)
		postnote(ppp->timep, 1, "unbind", 0);

	/* wait for kprocs to die */
	while(ppp->readp != 0 || ppp->timep != 0)
		tsleep(&up->sleep, return0, 0, 300);

	pppclose(ppp);
	qclose(ifc->conv->eq);
	ifc->arg = nil;
}

/*
 *  called by ipoput with a single packet to write with ifc rlock'd
 */
static void
pppbwrite(Ipifc *ifc, Block *bp, int, uchar*)
{
	PPP *ppp = ifc->arg;

	pppwrite(ppp, bp);
	ifc->out++;
}

/*
 *	If the other end hangs up, we have to unbind the interface.  An extra
 *	unbind (in the case where we are hanging up) won't do any harm.
 */
static void
deadremote(Ipifc *ifc)
{
	int fd;
	char path[128];
	PPP *ppp;

	ppp = ifc->arg;
	snprint(path, sizeof path, "#I%d/ipifc/%d/ctl", ppp->f->dev, ifc->conv->x);
	fd = kopen(path, ORDWR);
	if(fd < 0)
		return;
	kwrite(fd, "unbind", sizeof("unbind")-1);
	kclose(fd);
}

void
pppmediumlink(void)
{
	addipmedium(&pppmedium);
}
