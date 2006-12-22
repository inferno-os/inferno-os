#include	"u.h"
#include	"../port/lib.h"
#include	"mem.h"
#include	"dat.h"
#include	"fns.h"
#include	"../port/error.h"
#include	<libcrypt.h>
#include	<kernel.h>
#include	"ip.h"
#include	"ppp.h"

int	nocompress;
Ipaddr	pppdns[2];

/*
 * Calculate FCS - rfc 1331
 */
ushort fcstab[256] =
{
      0x0000, 0x1189, 0x2312, 0x329b, 0x4624, 0x57ad, 0x6536, 0x74bf,
      0x8c48, 0x9dc1, 0xaf5a, 0xbed3, 0xca6c, 0xdbe5, 0xe97e, 0xf8f7,
      0x1081, 0x0108, 0x3393, 0x221a, 0x56a5, 0x472c, 0x75b7, 0x643e,
      0x9cc9, 0x8d40, 0xbfdb, 0xae52, 0xdaed, 0xcb64, 0xf9ff, 0xe876,
      0x2102, 0x308b, 0x0210, 0x1399, 0x6726, 0x76af, 0x4434, 0x55bd,
      0xad4a, 0xbcc3, 0x8e58, 0x9fd1, 0xeb6e, 0xfae7, 0xc87c, 0xd9f5,
      0x3183, 0x200a, 0x1291, 0x0318, 0x77a7, 0x662e, 0x54b5, 0x453c,
      0xbdcb, 0xac42, 0x9ed9, 0x8f50, 0xfbef, 0xea66, 0xd8fd, 0xc974,
      0x4204, 0x538d, 0x6116, 0x709f, 0x0420, 0x15a9, 0x2732, 0x36bb,
      0xce4c, 0xdfc5, 0xed5e, 0xfcd7, 0x8868, 0x99e1, 0xab7a, 0xbaf3,
      0x5285, 0x430c, 0x7197, 0x601e, 0x14a1, 0x0528, 0x37b3, 0x263a,
      0xdecd, 0xcf44, 0xfddf, 0xec56, 0x98e9, 0x8960, 0xbbfb, 0xaa72,
      0x6306, 0x728f, 0x4014, 0x519d, 0x2522, 0x34ab, 0x0630, 0x17b9,
      0xef4e, 0xfec7, 0xcc5c, 0xddd5, 0xa96a, 0xb8e3, 0x8a78, 0x9bf1,
      0x7387, 0x620e, 0x5095, 0x411c, 0x35a3, 0x242a, 0x16b1, 0x0738,
      0xffcf, 0xee46, 0xdcdd, 0xcd54, 0xb9eb, 0xa862, 0x9af9, 0x8b70,
      0x8408, 0x9581, 0xa71a, 0xb693, 0xc22c, 0xd3a5, 0xe13e, 0xf0b7,
      0x0840, 0x19c9, 0x2b52, 0x3adb, 0x4e64, 0x5fed, 0x6d76, 0x7cff,
      0x9489, 0x8500, 0xb79b, 0xa612, 0xd2ad, 0xc324, 0xf1bf, 0xe036,
      0x18c1, 0x0948, 0x3bd3, 0x2a5a, 0x5ee5, 0x4f6c, 0x7df7, 0x6c7e,
      0xa50a, 0xb483, 0x8618, 0x9791, 0xe32e, 0xf2a7, 0xc03c, 0xd1b5,
      0x2942, 0x38cb, 0x0a50, 0x1bd9, 0x6f66, 0x7eef, 0x4c74, 0x5dfd,
      0xb58b, 0xa402, 0x9699, 0x8710, 0xf3af, 0xe226, 0xd0bd, 0xc134,
      0x39c3, 0x284a, 0x1ad1, 0x0b58, 0x7fe7, 0x6e6e, 0x5cf5, 0x4d7c,
      0xc60c, 0xd785, 0xe51e, 0xf497, 0x8028, 0x91a1, 0xa33a, 0xb2b3,
      0x4a44, 0x5bcd, 0x6956, 0x78df, 0x0c60, 0x1de9, 0x2f72, 0x3efb,
      0xd68d, 0xc704, 0xf59f, 0xe416, 0x90a9, 0x8120, 0xb3bb, 0xa232,
      0x5ac5, 0x4b4c, 0x79d7, 0x685e, 0x1ce1, 0x0d68, 0x3ff3, 0x2e7a,
      0xe70e, 0xf687, 0xc41c, 0xd595, 0xa12a, 0xb0a3, 0x8238, 0x93b1,
      0x6b46, 0x7acf, 0x4854, 0x59dd, 0x2d62, 0x3ceb, 0x0e70, 0x1ff9,
      0xf78f, 0xe606, 0xd49d, 0xc514, 0xb1ab, 0xa022, 0x92b9, 0x8330,
      0x7bc7, 0x6a4e, 0x58d5, 0x495c, 0x3de3, 0x2c6a, 0x1ef1, 0x0f78
};

static char *snames[] =
{
	"Sclosed",
	"Sclosing",
	"Sreqsent",
	"Sackrcvd",
	"Sacksent",
	"Sopened",
};

static void	init(PPP*);
static void	setphase(PPP*, int);
static void	pinit(PPP*, Pstate*);
static void	ppptimer(void*);
static void	ptimer(PPP*, Pstate*);
static int	getframe(PPP*, Block**);
static Block*	putframe(PPP*, int, Block*);
static uchar*	escapebyte(PPP*, ulong, uchar*, ushort*);
static void	config(PPP*, Pstate*, int);
static int	getopts(PPP*, Pstate*, Block*);
static void	rejopts(PPP*, Pstate*, Block*, int);
static void	newstate(PPP*, Pstate*, int);
static void	rcv(PPP*, Pstate*, Block*);
static void	getchap(PPP*, Block*);
static void	getpap(PPP*, Block*);
static void	sendpap(PPP*);
static void	getlqm(PPP*, Block*);
static void	putlqm(PPP*);
static void	hangup(PPP*);
static void	remove(PPP*);

static	int		validv4(Ipaddr);
static	void		invalidate(Ipaddr);
static	void		ipconnect(PPP *);
static	void		setdefroute(PPP *, Ipaddr);
static	void		printopts(PPP *, Pstate*, Block*, int);
static	void		sendtermreq(PPP*, Pstate*);

static void
errlog(PPP *ppp, char *err)
{
	int n;
	char msg[64];

	n = snprint(msg, sizeof(msg), "%s\n", err);
	qproduce(ppp->ifc->conv->eq, msg, n);
}

static void
init(PPP* ppp)
{
	if(ppp->inbuf == nil){
		ppp->inbuf = allocb(4096);
		ppp->outbuf = allocb(4096);

		ppp->lcp = malloc(sizeof(Pstate));
		ppp->ipcp = malloc(sizeof(Pstate));
		if(ppp->lcp == nil || ppp->ipcp == nil)
			error("ppp init: malloc");

		ppp->lcp->proto = Plcp;
		ppp->lcp->state = Sclosed;
		ppp->ipcp->proto = Pipcp;
		ppp->ipcp->state = Sclosed;

		kproc("ppptimer", ppptimer, ppp, KPDUPPG|KPDUPFDG);
	}

	pinit(ppp, ppp->lcp);
	setphase(ppp, Plink);
}

static void
setphase(PPP *ppp, int phase)
{
	int oldphase;

	oldphase = ppp->phase;

	ppp->phase = phase;
	switch(phase){
	default:
		panic("ppp: unknown phase %d", phase);
	case Pdead:
		/* restart or exit? */
		pinit(ppp, ppp->lcp);
		setphase(ppp, Plink);
		break;
	case Plink:
		/* link down */
		switch(oldphase) {
		case Pnet:
			newstate(ppp, ppp->ipcp, Sclosed);
		}
		break;
	case Pauth:
		if(ppp->usepap)
			sendpap(ppp);
		else if(!ppp->usechap)
			setphase(ppp, Pnet);
		break;
	case Pnet:
		pinit(ppp, ppp->ipcp);
		break;
	case Pterm:
		/* what? */
		break;
	}
}

static void
pinit(PPP *ppp, Pstate *p)
{
	p->timeout = 0;

	switch(p->proto){
	case Plcp:
		ppp->magic = TK2MS(MACHP(0)->ticks);
		ppp->xctlmap = 0xffffffff;
		ppp->period = 0;
		p->optmask = 0xffffffff;
		ppp->rctlmap = 0;
		ppp->ipcp->state = Sclosed;
		ppp->ipcp->optmask = 0xffffffff;

		/* quality goo */
		ppp->timeout = 0;
		memset(&ppp->in, 0, sizeof(ppp->in));
		memset(&ppp->out, 0, sizeof(ppp->out));
		memset(&ppp->pin, 0, sizeof(ppp->pin));
		memset(&ppp->pout, 0, sizeof(ppp->pout));
		memset(&ppp->sin, 0, sizeof(ppp->sin));
		break;
	case Pipcp:
		if(ppp->localfrozen == 0)
			invalidate(ppp->local);
		if(ppp->remotefrozen == 0)
			invalidate(ppp->remote);
		p->optmask = 0xffffffff;
		ppp->ctcp = compress_init(ppp->ctcp);
		ppp->usedns = 3;
		invalidate(ppp->dns1);
		invalidate(ppp->dns2);
		break;
	}
	p->confid = p->rcvdconfid = -1;
	config(ppp, p, 1);
	newstate(ppp, p, Sreqsent);
}

/*
 *  change protocol to a new state.
 */
static void
newstate(PPP *ppp, Pstate *p, int state)
{
	netlog(ppp->f, Logppp, "%ux %ux %s->%s ctlmap %lux/%lux flags %ux mtu %d mru %d\n", ppp, p->proto,
		snames[p->state], snames[state], ppp->rctlmap, ppp->xctlmap, p->flags,
		ppp->mtu, ppp->mru);

	if(p->proto == Plcp) {
		if(state == Sopened)
			setphase(ppp, Pauth);
		else if(state == Sclosed)
			setphase(ppp, Pdead);
		else if(p->state == Sopened)
			setphase(ppp, Plink);
	}

	if(p->proto == Pipcp && state == Sopened && validv4(ppp->local) && validv4(ppp->remote)){
		netlog(ppp->f, Logppp, "pppnewstate: local %I remote %I\n", ppp->local, ppp->remote);
		ipmove(pppdns[0], ppp->dns1);
		ipmove(pppdns[1], ppp->dns2);
		ipconnect(ppp);
		/* if this is the only network, set up a default route */
//		if(ppp->ifc->link==nil)		/* how??? */
			setdefroute(ppp, ppp->remote);
		errlog(ppp, Enoerror);
	}

	p->state = state;
}

static void
remove(PPP *ppp)
{
	free(ppp->ipcp);
	ppp->ipcp = 0;
	free(ppp->ctcp);
	ppp->ctcp = 0;
	free(ppp->lcp);
	ppp->lcp = 0;
	if (ppp->inbuf) {
		freeb(ppp->inbuf);
		ppp->inbuf = nil;
	}
	if (ppp->outbuf) {
		freeb(ppp->outbuf);
		ppp->outbuf = nil;
	}
	free(ppp);
}

void
pppclose(PPP *ppp)
{
	hangup(ppp);
	remove(ppp);
}

static void
dumpblock(Block *b)
{
	char x[256];
	int i;

	for(i = 0; i < (sizeof(x)-1)/3 && b->rp+i < b->wp; i++)
		sprint(&x[3*i], "%2.2ux ", b->rp[i]);
	print("%s\n", x);
}

/* returns (protocol, information) */
static int
getframe(PPP *ppp, Block **info)
{
	uchar *p, *from, *to;
	int n, len, proto;
	ulong c;
	ushort fcs;
	Block *buf, *b;

	buf = ppp->inbuf;
	for(;;){
		/* read till we hit a frame byte or run out of room */
		for(p = buf->rp; buf->wp < buf->lim;){
			for(; p < buf->wp; p++)
				if(*p == HDLC_frame)
					goto break2;

			len = buf->lim - buf->wp;
			n = 0;
			if(ppp->dchan != nil)
				n = kchanio(ppp->dchan, buf->wp, len, OREAD);
				netlog(ppp->f, Logppp, "ppp kchanio %d bytes\n", n);
			if(n <= 0){
				buf->wp = buf->rp;
//				if(n < 0)
//					print("ppp kchanio(%s) returned %d: %r",
//						ppp->dchan->path->elem, n);
				*info = nil;
				return 0;
			}
			buf->wp += n;
		}
break2:

		/* copy into block, undoing escapes, and caculating fcs */
		fcs = PPP_initfcs;
		b = allocb(p - buf->rp);
		to = b->wp;
		for(from = buf->rp; from != p;){
			c = *from++;
			if(c == HDLC_esc){
				if(from == p)
					break;
				c = *from++ ^ 0x20;
			} else if((c < 0x20) && (ppp->rctlmap & (1 << c)))
				continue;
			*to++ = c;
			fcs = (fcs >> 8) ^ fcstab[(fcs ^ c) & 0xff];
		}

		/* copy down what's left in buffer */
		p++;
		memmove(buf->rp, p, buf->wp - p);
		n = p - buf->rp;
		buf->wp -= n;
		b->wp = to - 2;

		/* return to caller if checksum matches */
		if(fcs == PPP_goodfcs){
			if(b->rp[0] == PPP_addr && b->rp[1] == PPP_ctl)
				b->rp += 2;
			proto = *b->rp++;
			if((proto & 0x1) == 0)
				proto = (proto<<8) | *b->rp++;
			if(b->rp < b->wp){
				ppp->in.bytes += n;
				ppp->in.packets++;
				*info = b;
				return proto;
			}
		} else if(BLEN(b) > 0){
			ppp->ifc->inerr++;
			ppp->in.discards++;
			netlog(ppp->f, Logppp, "len %d/%d cksum %ux (%ux %ux %ux %ux)\n",
				BLEN(b), BLEN(buf), fcs, b->rp[0],
				b->rp[1], b->rp[2], b->rp[3]);
		}

		freeblist(b);
	}
	*info = nil;
	return 0;
}

/* send a PPP frame */
static Block *
putframe(PPP *ppp, int proto, Block *b)
{
	Block *buf;
	uchar *to, *from;
	ushort fcs;
	ulong ctlmap;
	int c;
	Block *bp;

	if(ppp->dchan == nil){
		netlog(ppp->f, Logppp, "putframe: dchan down\n");
		errlog(ppp, Ehungup);
		return b;
	}
	netlog(ppp->f, Logppp, "putframe %ux %d %d (%d bytes)\n", proto, b->rp[0], b->rp[1], BLEN(b));

	ppp->out.packets++;

	if(proto == Plcp)
		ctlmap = 0xffffffff;
	else
		ctlmap = ppp->xctlmap;

	/* make sure we have head room */
	if(b->rp - b->base < 4){
		b = padblock(b, 4);
		b->rp += 4;
	}

	/* add in the protocol and address, we'd better have left room */
	from = b->rp;
	*--from = proto;
	if(!(ppp->lcp->flags&Fpc) || proto > 0x100 || proto == Plcp)
		*--from = proto>>8;
	if(!(ppp->lcp->flags&Fac) || proto == Plcp){
		*--from = PPP_ctl;
		*--from = PPP_addr;
	}

	qlock(&ppp->outlock);
	buf = ppp->outbuf;

	/* escape and checksum the body */
	fcs = PPP_initfcs;
	to = buf->rp;

	*to++ = HDLC_frame;

	for(bp = b; bp; bp = bp->next){
		if(bp != b)
			from = bp->rp;
		for(; from < bp->wp; from++){
			c = *from;
			if(c == HDLC_frame || c == HDLC_esc
			   || (c < 0x20 && ((1<<c) & ctlmap))){
				*to++ = HDLC_esc;
				*to++ = c ^ 0x20;
			} else 
				*to++ = c;
			fcs = (fcs >> 8) ^ fcstab[(fcs ^ c) & 0xff];
		}
	}

	/* add on and escape the checksum */
	fcs = ~fcs;
	c = fcs;
	if(c == HDLC_frame || c == HDLC_esc
	   || (c < 0x20 && ((1<<c) & ctlmap))){
		*to++ = HDLC_esc;
		*to++ = c ^ 0x20;
	} else 
		*to++ = c;
	c = fcs>>8;
	if(c == HDLC_frame || c == HDLC_esc
	   || (c < 0x20 && ((1<<c) & ctlmap))){
		*to++ = HDLC_esc;
		*to++ = c ^ 0x20;
	} else 
		*to++ = c;

	/* add frame marker and send */
	*to++ = HDLC_frame;
	buf->wp = to;
	if(ppp->dchan == nil){
		netlog(ppp->f, Logppp, "putframe: dchan down\n");
		errlog(ppp, Ehungup);
	}else{
		kchanio(ppp->dchan, buf->rp, BLEN(buf), OWRITE);
		ppp->out.bytes += BLEN(buf);
	}

	qunlock(&ppp->outlock);
	return b;
}

#define IPB2LCP(b) ((Lcpmsg*)((b)->wp-4))

static Block*
alloclcp(int code, int id, int len)
{
	Block *b;
	Lcpmsg *m;

	/*
	 *  leave room for header
	 */
	b = allocb(len);

	m = (Lcpmsg*)b->wp;
	m->code = code;
	m->id = id;
	b->wp += 4;

	return b;
}

static void
putao(Block *b, int type, int aproto, int alg)
{
	*b->wp++ = type;
	*b->wp++ = 5;
	hnputs(b->wp, aproto);
	b->wp += 2;
	*b->wp++ = alg;
}

static void
putlo(Block *b, int type, ulong val)
{
	*b->wp++ = type;
	*b->wp++ = 6;
	hnputl(b->wp, val);
	b->wp += 4;
}

static void
putv4o(Block *b, int type, Ipaddr val)
{
	*b->wp++ = type;
	*b->wp++ = 6;
	if(v6tov4(b->wp, val) < 0){
		/*panic("putv4o")*/;
	}
	b->wp += 4;
}

static void
putso(Block *b, int type, ulong val)
{
	*b->wp++ = type;
	*b->wp++ = 4;
	hnputs(b->wp, val);
	b->wp += 2;
}

static void
puto(Block *b, int type)
{
	*b->wp++ = type;
	*b->wp++ = 2;
}

/*
 *  send configuration request
 */
static void
config(PPP *ppp, Pstate *p, int newid)
{
	Block *b;
	Lcpmsg *m;
	int id;

	if(newid){
		id = ++(p->id);
		p->confid = id;
		p->timeout = Timeout;
	} else
		id = p->confid;
	b = alloclcp(Lconfreq, id, 256);
	m = IPB2LCP(b);
	USED(m);

	switch(p->proto){
	case Plcp:
		if(p->optmask & Fmagic)
			putlo(b, Omagic, ppp->magic);
		if(p->optmask & Fmtu)
			putso(b, Omtu, ppp->mru);
		if(p->optmask & Fac)
			puto(b, Oac);
		if(p->optmask & Fpc)
			puto(b, Opc);
		if(p->optmask & Fctlmap)
			putlo(b, Octlmap, 0);	/* we don't want anything escaped */
		break;
	case Pipcp:
		if((p->optmask & Fipaddr) /*&& validv4(ppp->local)*/)
			putv4o(b, Oipaddr, ppp->local);
		if(!nocompress && (p->optmask & Fipcompress)){
			*b->wp++ = Oipcompress;
			*b->wp++ = 6;
			hnputs(b->wp, Pvjctcp);
			b->wp += 2;
			*b->wp++ = MAX_STATES-1;
			*b->wp++ = 1;
		}
		if(ppp->usedns & 1)
			putlo(b, Oipdns, 0);
		if(ppp->usedns & 2)
			putlo(b, Oipdns2, 0);
		break;
	}

	hnputs(m->len, BLEN(b));
	b = putframe(ppp, p->proto, b);
	freeblist(b);
}

/*
 *  parse configuration request, sends an ack or reject packet
 *
 *	returns:	-1 if request was syntacticly incorrect
 *			 0 if packet was accepted
 *			 1 if packet was rejected
 */
static int
getopts(PPP *ppp, Pstate *p, Block *b)
{
	Lcpmsg *m, *repm;	
	Lcpopt *o;
	uchar *cp;
	ulong rejecting, nacking, flags, proto;
	ulong mtu, ctlmap, period;
	ulong x;
	Block *repb;
	Ipaddr ipaddr;

	rejecting = 0;
	nacking = 0;
	flags = 0;

	/* defaults */
	invalidate(ipaddr);
	mtu = ppp->mtu;

	ctlmap = 0xffffffff;
	period = 0;

	m = (Lcpmsg*)b->rp;
	repb = alloclcp(Lconfack, m->id, BLEN(b));
	repm = IPB2LCP(repb);

	/* copy options into ack packet */
	memmove(repm->data, m->data, b->wp - m->data);
	repb->wp += b->wp - m->data;

	/* look for options we don't recognize or like */
	for(cp = m->data; cp < b->wp; cp += o->len){
		o = (Lcpopt*)cp;
		if(cp + o->len > b->wp || o->len == 0){
			freeblist(repb);
			netlog(ppp->f, Logppp, "ppp %s: bad option length %ux\n", ppp->ifc->dev,
				o->type);
			return -1;
		}

		switch(p->proto){
		case Plcp:
			switch(o->type){
			case Oac:
				flags |= Fac;
				continue;
			case Opc:
				flags |= Fpc;
				continue;
			case Omtu:
				mtu = nhgets(o->data);
				if(mtu < ppp->ifc->m->mintu){
					netlog(ppp->f, Logppp, "bogus mtu %d\n", mtu);
					mtu = ppp->ifc->m->mintu;
				}
				continue;
			case Omagic:
				if(ppp->magic == nhgetl(o->data))
					netlog(ppp->f, Logppp, "ppp: possible loop\n");
				continue;
			case Octlmap:
				ctlmap = nhgetl(o->data);
				continue;
			case Oquality:
				proto = nhgets(o->data);
				if(proto != Plqm)
					break;
				x = nhgetl(o->data+2)*10;
				period = (x+Period-1)/Period;
				continue;
			case Oauth:
				proto = nhgets(o->data);
				if(proto == Ppap && ppp->chapname[0] && ppp->secret[0]){
					ppp->usepap = 1;
					netlog(ppp->f, Logppp, "PPP %s: select PAP\n", ppp->ifc->dev);
					continue;
				}
				if(proto != Pchap || o->data[2] != APmd5){
					if(!nacking){
						nacking = 1;
						repb->wp = repm->data;
						repm->code = Lconfnak;
					}
					putao(repb, Oauth, Pchap, APmd5);
				}
				else
					ppp->usechap = 1;
				ppp->usepap = 0;
				continue;
			}
			break;
		case Pipcp:
			switch(o->type){
			case Oipaddr:	
				v4tov6(ipaddr, o->data);
				if(!validv4(ppp->remote))
					continue;
				if(!validv4(ipaddr) && !rejecting){
					/* other side requesting an address */
					if(!nacking){
						nacking = 1;
						repb->wp = repm->data;
						repm->code = Lconfnak;
					}
					putv4o(repb, Oipaddr, ppp->remote);
				}
				continue;
			case Oipcompress:
				proto = nhgets(o->data);
				if(nocompress || proto != Pvjctcp || compress_negotiate(ppp->ctcp, o->data+2) < 0)
					break;
				flags |= Fipcompress;
				continue;
			}
			break;
		}

		/* come here if option is not recognized */
		if(!rejecting){
			rejecting = 1;
			repb->wp = repm->data;
			repm->code = Lconfrej;
		}
		netlog(ppp->f, Logppp, "ppp %s: bad %ux option %d\n", ppp->ifc->dev, p->proto, o->type);
		memmove(repb->wp, o, o->len);
		repb->wp += o->len;
	}

	/* permanent changes only after we know that we liked the packet */
	if(!rejecting && !nacking){
		switch(p->proto){
		case Plcp:
			netlog(ppp->f, Logppp, "Plcp: mtu: %d %d x:%lux/r:%lux %lux\n", mtu, ppp->mtu, ppp->xctlmap, ppp->rctlmap, ctlmap);
			ppp->period = period;
			ppp->xctlmap = ctlmap;
			if(mtu > Maxmtu)
				mtu = Maxmtu;
			if(mtu < Minmtu)
				mtu = Minmtu;
			ppp->mtu = mtu;
			break;
		case Pipcp:
			if(validv4(ipaddr) && ppp->remotefrozen == 0)
 				ipmove(ppp->remote, ipaddr);
			break;
		}
		p->flags = flags;
	}

	hnputs(repm->len, BLEN(repb));
	repb = putframe(ppp, p->proto, repb);
	freeblist(repb);

	return rejecting || nacking;
}

/*
 *  parse configuration rejection, just stop sending anything that they
 *  don't like (except for ipcp address nak).
 */
static void
rejopts(PPP *ppp, Pstate *p, Block *b, int code)
{
	Lcpmsg *m;
	Lcpopt *o;

	/* just give up trying what the other side doesn't like */
	m = (Lcpmsg*)b->rp;
	for(b->rp = m->data; b->rp < b->wp; b->rp += o->len){
		o = (Lcpopt*)b->rp;
		if(b->rp + o->len > b->wp || o->len == 0){
			netlog(ppp->f, Logppp, "ppp %s: bad roption length %ux\n", ppp->ifc->dev,
				o->type);
			return;
		}

		if(code == Lconfrej){
			if(o->type < 8*sizeof(p->optmask))
				p->optmask &= ~(1<<o->type);
			if(o->type == Oipdns)
				ppp->usedns &= ~1;
			else if(o->type == Oipdns2)
				ppp->usedns &= ~2;
			netlog(ppp->f, Logppp, "ppp %s: %ux rejecting %d\n", ppp->ifc->dev, p->proto,
				o->type);
			continue;
		}

		switch(p->proto){
		case Plcp:
			switch(o->type){
			case Octlmap:
				ppp->rctlmap = nhgetl(o->data);
				break;
			default:
				if(o->type < 8*sizeof(p->optmask))
					p->optmask &= ~(1<<o->type);
				break;
			};
		case Pipcp:
			switch(o->type){
			case Oipaddr:
				if(!validv4(ppp->local))
					v4tov6(ppp->local, o->data);
//				if(o->type < 8*sizeof(p->optmask))
//					p->optmask &= ~(1<<o->type);
				break;
			case Oipdns:
				if(!validv4(ppp->dns1))
					v4tov6(ppp->dns1, o->data);
				ppp->usedns &= ~1;
				break;
			case Oipdns2:
				if(!validv4(ppp->dns2))
					v4tov6(ppp->dns2, o->data);
				ppp->usedns &= ~2;
				break;
			default:
				if(o->type < 8*sizeof(p->optmask))
					p->optmask &= ~(1<<o->type);
				break;
			}
			break;
		}
	}
}


/*
 *  put a messages through the lcp or ipcp state machine.  They are
 *  very similar.
 */
static void
rcv(PPP *ppp, Pstate *p, Block *b)
{
	ulong len;
	int err;
	Lcpmsg *m;

	if(BLEN(b) < 4){
		netlog(ppp->f, Logppp, "ppp %s: short lcp message\n", ppp->ifc->dev);
		freeblist(b);
		return;
	}
	m = (Lcpmsg*)b->rp;
	len = nhgets(m->len);
	if(BLEN(b) < len){
		netlog(ppp->f, Logppp, "ppp %s: short lcp message\n", ppp->ifc->dev);
		freeblist(b);
		return;
	}

	netlog(ppp->f, Logppp, "ppp: %ux rcv %d len %d id %d/%d/%d\n",
		p->proto, m->code, len, m->id, p->confid, p->id);

	if(p->proto != Plcp && ppp->lcp->state != Sopened){
		netlog(ppp->f, Logppp, "ppp: non-lcp with lcp not open\n");
		freeb(b);
		return;
	}

	qlock(ppp);
	switch(m->code){
	case Lconfreq:
		/* flush the output queue */
		if(p->state == Sopened && p->proto == Plcp)
			kchanio(ppp->cchan, "f", 1, OWRITE);

		printopts(ppp, p, b, 0);
		err = getopts(ppp, p, b);
		if(err < 0)
			break;

		if(m->id == p->rcvdconfid)
			break;			/* don't change state for duplicates */
		p->rcvdconfid = m->id;

		switch(p->state){
		case Sackrcvd:
			if(err)
				break;
			newstate(ppp, p, Sopened);
			break;
		case Sclosed:
		case Sopened:
			config(ppp, p, 1);
			if(err == 0)
				newstate(ppp, p, Sacksent);
			else
				newstate(ppp, p, Sreqsent);
			break;
			break;
		case Sreqsent:
		case Sacksent:
			if(err == 0)
				newstate(ppp, p, Sacksent);
			else
				newstate(ppp, p, Sreqsent);
			break;
		}
		break;
	case Lconfack:
		if(p->confid != m->id){
			/* ignore if it isn't the message we're sending */
			netlog(ppp->f, Logppp, "ppp: dropping confack\n");
			break;
		}
		p->confid = -1;		/* ignore duplicates */
		p->id++;		/* avoid sending duplicates */

		switch(p->state){
		case Sopened:
		case Sackrcvd:
			config(ppp, p, 1);
			newstate(ppp, p, Sreqsent);
			break;
		case Sreqsent:
			newstate(ppp, p, Sackrcvd);
			break;
		case Sacksent:
			newstate(ppp, p, Sopened);
			break;
		}
		break;
	case Lconfrej:
	case Lconfnak:
		if(p->confid != m->id) {
			/* ignore if it isn't the message we're sending */
			netlog(ppp->f, Logppp, "ppp: dropping confrej or confnak\n");
			break;
		}
		p->confid = -1;		/* ignore duplicates */
		p->id++;		/* avoid sending duplicates */

		switch(p->state){
		case Sopened:
		case Sackrcvd:
			config(ppp, p, 1);
			newstate(ppp, p, Sreqsent);
			break;
		case Sreqsent:
		case Sacksent:
			printopts(ppp, p, b, 0);
			rejopts(ppp, p, b, m->code);
			config(ppp, p, 1);
			break;
		}
		break;
	case Ltermreq:
		m->code = Ltermack;
		b = putframe(ppp, p->proto, b);

		switch(p->state){
		case Sackrcvd:
		case Sacksent:
			newstate(ppp, p, Sreqsent);
			break;
		case Sopened:
			newstate(ppp, p, Sclosing);
			break;
		}
		break;
	case Ltermack:
		if(p->termid != m->id)	/* ignore if it isn't the message we're sending */
			break;

		if(p->proto == Plcp)
			ppp->ipcp->state = Sclosed;
		switch(p->state){
		case Sclosing:
			newstate(ppp, p, Sclosed);
			break;
		case Sackrcvd:
			newstate(ppp, p, Sreqsent);
			break;
		case Sopened:
			config(ppp, p, 0);
			newstate(ppp, p, Sreqsent);
			break;
		}
		break;
	case Lcoderej:
		netlog(ppp->f, Logppp, "ppp %s: code reject %d\n", ppp->ifc->dev, m->data[0]);
		break;
	case Lprotorej:
		netlog(ppp->f, Logppp, "ppp %s: proto reject %lux\n", ppp->ifc->dev, nhgets(m->data));
		break;
	case Lechoreq:
		m->code = Lechoack;
		b = putframe(ppp, p->proto, b);
		break;
	case Lechoack:
	case Ldiscard:
		/* nothing to do */
		break;
	}

	qunlock(ppp);
	freeblist(b);
}

/*
 *  timer for protocol state machine
 */
static void
ptimer(PPP *ppp, Pstate *p)
{
	if(p->state == Sopened || p->state == Sclosed)
		return;

	p->timeout--;
	switch(p->state){
	case Sclosing:
		sendtermreq(ppp, p);
		break;
	case Sreqsent:
	case Sacksent:
		if(p->timeout <= 0){
			if(p->proto && ppp->cchan != nil)
				kchanio(ppp->cchan, "f", 1, OWRITE); /* flush output queue */
			newstate(ppp, p, Sclosed);
		} else {
			config(ppp, p, 0);
		}
		break;
	case Sackrcvd:
		if(p->timeout <= 0){
			if(p->proto && ppp->cchan != nil)
				kchanio(ppp->cchan, "f", 1, OWRITE); /* flush output queue */
			newstate(ppp, p, Sclosed);
		}
		else {
			config(ppp, p, 0);
			newstate(ppp, p, Sreqsent);
		}
		break;
	}
}

/*
 *  timer for ppp
 */
static void
ppptimer(void *arg)
{
	PPP *ppp;

	ppp = arg;
	ppp->timep = up;
	if(waserror()){
		netlog(ppp->f, Logppp, "ppptimer: %I: %s\n", ppp->local, up->env->errstr);
		ppp->timep = 0;
		pexit("hangup", 1);
	}
	for(;;){
		tsleep(&up->sleep, return0, nil, Period);
		if(ppp->pppup){
			qlock(ppp);

			ptimer(ppp, ppp->lcp);
			if(ppp->lcp->state == Sopened)
				ptimer(ppp, ppp->ipcp);

			if(ppp->period && --(ppp->timeout) <= 0){
				ppp->timeout = ppp->period;
				putlqm(ppp);
			}

			qunlock(ppp);
		}
	}
}

static void
setdefroute(PPP *ppp, Ipaddr gate)
{
	int fd, n;
	char path[128], msg[128];

	snprint(path, sizeof path, "#I%d/iproute", ppp->f->dev);
	fd = kopen(path, ORDWR);
	if(fd < 0)
		return;
	n = snprint(msg, sizeof(msg), "add 0 0 %I", gate);
	kwrite(fd, msg, n);
	kclose(fd);
}

static void
ipconnect(PPP *ppp)
{
	int fd, n;
	char path[128], msg[128];

	snprint(path, sizeof path, "#I%d/ipifc/%d/ctl", ppp->f->dev, ppp->ifc->conv->x);
	fd = kopen(path, ORDWR);
	if(fd < 0)
		return;
	n = snprint(msg, sizeof(msg), "connect %I 255.255.255.255 %I", ppp->local, ppp->remote);
	if (kwrite(fd, msg, n) != n)
		print("ppp ipconnect: %s: %r\n", msg);
	kclose(fd);
}

PPP*
pppopen(PPP *ppp, char *dev,
	Ipaddr ipaddr, Ipaddr remip,
	int mtu, int framing,
	char *chapname, char *secret)
{
	int fd, cfd;
	char ctl[Maxpath];

	invalidate(ppp->remote);
	invalidate(ppp->local);
	invalidate(ppp->dns1);
	invalidate(ppp->dns2);
	ppp->mtu = Defmtu;
	ppp->mru = mtu;
	ppp->framing = framing;

	if(remip != nil && validv4(remip)){
		ipmove(ppp->remote, remip);
		ppp->remotefrozen = 1;
	}
	if(ipaddr != nil && validv4(ipaddr)){
		ipmove(ppp->local, ipaddr);
		ppp->localfrozen = 1;
	}

	/* authentication goo */
	ppp->secret[0] = 0;
	if(secret != nil)
		strncpy(ppp->secret, secret, sizeof(ppp->secret));
	ppp->chapname[0] = 0;
	if(chapname != nil)
		strncpy(ppp->chapname, chapname, sizeof(ppp->chapname));

	if(strchr(dev, '!'))
		fd = kdial(dev, nil, nil, nil);
	else
		fd = kopen(dev, ORDWR);
	if(fd < 0){
		netlog(ppp->f, Logppp, "ppp: can't open %s\n", dev);
		return nil;
	}
	ppp->dchan = fdtochan(up->env->fgrp, fd, ORDWR, 0, 1);
	kclose(fd);

	/* set up serial line */
/* XXX this stuff belongs in application, not driver */
	sprint(ctl, "%sctl", dev);
	cfd = kopen(ctl, ORDWR);
	if(cfd >= 0){
		ppp->cchan = fdtochan(up->env->fgrp, cfd, ORDWR, 0, 1);
		kclose(cfd);
		kchanio(ppp->cchan, "m1", 2, OWRITE);	/* cts/rts flow control/fifo's) on */
		kchanio(ppp->cchan, "q64000", 6, OWRITE);/* increas q size to 64k */
		kchanio(ppp->cchan, "n1", 2, OWRITE);	/* nonblocking writes on */
		kchanio(ppp->cchan, "r1", 2, OWRITE);	/* rts on */
		kchanio(ppp->cchan, "d1", 2, OWRITE);	/* dtr on */
	}

	ppp->pppup = 1;
	init(ppp);
	return ppp;
}

static void
hangup(PPP *ppp)
{
	qlock(ppp);
	if(waserror()){
		qunlock(ppp);
		nexterror();
	}
	netlog(ppp->f, Logppp, "PPP Hangup\n");
	errlog(ppp, Ehungup);
	if(ppp->pppup && ppp->cchan != nil){
		kchanio(ppp->cchan, "f", 1, OWRITE);	/* flush */
		kchanio(ppp->cchan, "h", 1, OWRITE);	/* hangup */
	}
	cclose(ppp->dchan);
	cclose(ppp->cchan);
	ppp->dchan = nil;
	ppp->cchan = nil;
	ppp->pppup = 0;
	qunlock(ppp);
	poperror();
}

/* return next input IP packet */
Block*
pppread(PPP *ppp)
{
	Block *b;
	int proto;
	Lcpmsg *m;

	for(;;){
		proto = getframe(ppp, &b);
		if(b == nil)
			return nil;
		netlog(ppp->f, Logppp, "ppp: read proto %d len %d\n", proto, blocklen(b));
		switch(proto){
		case Plcp:
			rcv(ppp, ppp->lcp, b);
			break;
		case Pipcp:
			rcv(ppp, ppp->ipcp, b);
			break;
		case Pip:
			if(ppp->ipcp->state == Sopened)
				return b;
			freeblist(b);
			break;
		case Plqm:
			getlqm(ppp, b);
			break;
		case Pchap:
			getchap(ppp, b);
			break;
		case Ppap:
			getpap(ppp, b);
			break;
		case Pvjctcp:
		case Pvjutcp:
			if(ppp->ipcp->state == Sopened){
				b = tcpuncompress(ppp->ctcp, b, proto, ppp->f);
				if(b != nil)
					return b;
			}
			freeblist(b);
			break;
		default:
			netlog(ppp->f, Logppp, "unknown proto %ux\n", proto);
			if(ppp->lcp->state == Sopened){
				/* reject the protocol */
				b->rp -= 6;
				m = (Lcpmsg*)b->rp;
				m->code = Lprotorej;
				m->id = ++ppp->lcp->id;
				hnputs(m->data, proto);
				hnputs(m->len, BLEN(b));
				b = putframe(ppp, Plcp, b);
			}
			freeblist(b);
			break;
		}
	}
	return nil;		/* compiler confused */
}

/* transmit an IP packet */
int
pppwrite(PPP *ppp, Block *b)
{
	ushort proto;
	int r;

	qlock(ppp);

	/* can't send ip packets till we're established */
	if(ppp->ipcp->state != Sopened)
		goto ret;

	/* link hung up */
	if(ppp->dchan == nil)
		goto ret;

	b = concatblock(b);		/* or else compression will barf */

	proto = Pip;
	if(ppp->ipcp->flags & Fipcompress)
		proto = compress(ppp->ctcp, b, ppp->f);
	b = putframe(ppp, proto, b);


ret:
	qunlock(ppp);

	r = blocklen(b);
	netlog(ppp->f, Logppp, "ppp wrt len %d\n", r);

	freeblist(b);
	return r;
}

/*
 *  link quality management
 */
static void
getlqm(PPP *ppp, Block *b)
{
	Qualpkt *p;

	p = (Qualpkt*)b->rp;
	if(BLEN(b) == sizeof(Qualpkt)){
		ppp->in.reports++;
		ppp->pout.reports = nhgetl(p->peeroutreports);
		ppp->pout.packets = nhgetl(p->peeroutpackets);
		ppp->pout.bytes = nhgetl(p->peeroutbytes);
		ppp->pin.reports = nhgetl(p->peerinreports);
		ppp->pin.packets = nhgetl(p->peerinpackets);
		ppp->pin.discards = nhgetl(p->peerindiscards);
		ppp->pin.errors = nhgetl(p->peerinerrors);
		ppp->pin.bytes = nhgetl(p->peerinbytes);

		/* save our numbers at time of reception */
		memmove(&ppp->sin, &ppp->in, sizeof(Qualstats));

	}
	freeblist(b);
	if(ppp->period == 0)
		putlqm(ppp);

}
static void
putlqm(PPP *ppp)
{
	Qualpkt *p;
	Block *b;

	b = allocb(sizeof(Qualpkt));
	b->wp += sizeof(Qualpkt);
	p = (Qualpkt*)b->rp;
	hnputl(p->magic, 0);

	/* heresay (what he last told us) */
	hnputl(p->lastoutreports, ppp->pout.reports);
	hnputl(p->lastoutpackets, ppp->pout.packets);
	hnputl(p->lastoutbytes, ppp->pout.bytes);

	/* our numbers at time of last reception */
	hnputl(p->peerinreports, ppp->sin.reports);
	hnputl(p->peerinpackets, ppp->sin.packets);
	hnputl(p->peerindiscards, ppp->sin.discards);
	hnputl(p->peerinerrors, ppp->sin.errors);
	hnputl(p->peerinbytes, ppp->sin.bytes);

	/* our numbers now */
	hnputl(p->peeroutreports, ppp->out.reports+1);
	hnputl(p->peeroutpackets, ppp->out.packets+1);
	hnputl(p->peeroutbytes, ppp->out.bytes+53/*hack*/);

	b = putframe(ppp, Plqm, b);
	freeblist(b);
	ppp->out.reports++;
}

/*
 *  challenge response dialog
 */
static void
getchap(PPP *ppp, Block *b)
{
	Lcpmsg *m;
	int len, vlen, n;
	char md5buf[512];

	m = (Lcpmsg*)b->rp;
	len = nhgets(m->len);
	if(BLEN(b) < len){
		netlog(ppp->f, Logppp, "ppp %s: short chap message\n", ppp->ifc->dev);
		freeblist(b);
		return;
	}

	switch(m->code){
	case Cchallenge:
		vlen = m->data[0];
		if(vlen > len - 5){
			netlog(ppp->f, Logppp, "PPP %s: bad challenge len\n", ppp->ifc->dev);
			freeblist(b);
			break;
		}

		netlog(ppp->f, Logppp, "PPP %s: CHAP Challenge\n", ppp->ifc->dev);
netlog(ppp->f, Logppp, "(secret %s chapname %s id %d)\n", ppp->secret, ppp->chapname, m->id);
		/* create string to hash */
		md5buf[0] = m->id;
		strcpy(md5buf+1, ppp->secret);
		n = strlen(ppp->secret) + 1;
		memmove(md5buf+n, m->data+1, vlen);
		n += vlen;
		freeblist(b);

		/* send reply */
		len = 4 + 1 + 16 + strlen(ppp->chapname);
		b = alloclcp(2, md5buf[0], len);
		m = IPB2LCP(b);
		m->data[0] = 16;
		md5((uchar*)md5buf, n, m->data+1, 0);
		memmove((char*)m->data+17, ppp->chapname, strlen(ppp->chapname));
		hnputs(m->len, len);
		b->wp += len-4;
		b = putframe(ppp, Pchap, b);
		break;
	case Cresponse:
		netlog(ppp->f, Logppp, "PPP %s: chap response?\n", ppp->ifc->dev);
		break;
	case Csuccess:
		netlog(ppp->f, Logppp, "PPP %s: chap succeeded\n", ppp->ifc->dev);
		setphase(ppp, Pnet);
		break;
	case Cfailure:
		netlog(ppp->f, Logppp, "PPP %s: chap failed: %.*s\n", ppp->ifc->dev, len-4, m->data);
		errlog(ppp, Eperm);
		break;
	default:
		netlog(ppp->f, Logppp, "PPP %s: chap code %d?\n", ppp->ifc->dev, m->code);
		break;
	}
	freeblist(b);
}

/*
 *  password authentication protocol dialog
 *	-- obsolete but all we know how to use with NT just now
 */
static void
sendpap(PPP *ppp)
{
	Lcpmsg *m;
	int clen, slen, len;
	Block *b;
	uchar *p;

	clen = strlen(ppp->chapname);
	slen = strlen(ppp->secret);
	len = 4 + 1 + clen + 1 + slen;
	ppp->papid = ++ppp->lcp->id;
	b = alloclcp(Cpapreq, ppp->papid, len);
	m = IPB2LCP(b);
	p = m->data;
	p[0] = clen;
	memmove(p+1, ppp->chapname, clen);
	p += clen + 1;
	p[0] = slen;
	memmove(p+1, ppp->secret, slen);
	hnputs(m->len, len);
	b->wp += len-4;
	b = putframe(ppp, Ppap, b);
	netlog(ppp->f, Logppp, "PPP %s: sent pap auth req (%d)\n", ppp->ifc->dev, len);
	freeblist(b);
}

static void
getpap(PPP *ppp, Block *b)
{
	Lcpmsg *m;
	int len;

	m = (Lcpmsg*)b->rp;
	len = nhgets(m->len);
	if(BLEN(b) < len){
		netlog(ppp->f, Logppp, "ppp %s: short pap message\n", ppp->ifc->dev);
		freeblist(b);
		return;
	}

	switch(m->code){
	case Cpapreq:
		netlog(ppp->f, Logppp, "PPP %s: pap request?\n", ppp->ifc->dev);
		break;
	case Cpapack:
		netlog(ppp->f, Logppp, "PPP %s: PAP succeeded\n", ppp->ifc->dev);
		setphase(ppp, Pnet);
		break;
	case Cpapnak:
		if(m->data[0])
			netlog(ppp->f, Logppp, "PPP %s: PAP failed: %.*s\n", ppp->ifc->dev, len-5, m->data+1);
		else
			netlog(ppp->f, Logppp, "PPP %s: PAP failed\n", ppp->ifc->dev);
		errlog(ppp, Eperm);
		break;
	default:
		netlog(ppp->f, Logppp, "PPP %s: pap code %d?\n", ppp->ifc->dev, m->code);
		break;
	}
	freeblist(b);
}

static void
printopts(PPP *ppp, Pstate *p, Block *b, int send)
{
	Lcpmsg *m;	
	Lcpopt *o;
	int proto, x, period;
	uchar *cp;
	char *code, *dir;

	m = (Lcpmsg*)b->rp;
	switch(m->code) {
	default: code = "<unknown>"; break;
	case Lconfreq: code = "confrequest"; break;
	case Lconfack: code = "confack"; break;
	case Lconfnak: code = "confnak"; break;
	case Lconfrej: code = "confreject"; break;
	}

	if(send)
		dir = "send";
	else
		dir = "recv";

	netlog(ppp->f, Logppp, "ppp: %s %s: id=%d\n", dir, code, m->id);

	for(cp = m->data; cp < b->wp; cp += o->len){
		o = (Lcpopt*)cp;
		if(cp + o->len > b->wp || o->len == 0){
			netlog(ppp->f, Logppp, "\tbad option length %ux\n", o->type);
			return;
		}

		switch(p->proto){
		case Plcp:
			switch(o->type){
			default:
				netlog(ppp->f, Logppp, "\tunknown %d len=%d\n", o->type, o->len);
				break;
			case Omtu:
				netlog(ppp->f, Logppp, "\tmtu = %d\n", nhgets(o->data));
				break;
			case Octlmap:
				netlog(ppp->f, Logppp, "\tctlmap = %ux\n", nhgetl(o->data));
				break;
			case Oauth:
				netlog(ppp->f, Logppp, "\tauth = ", nhgetl(o->data));
				proto = nhgets(o->data);
				switch(proto) {
				default:
					netlog(ppp->f, Logppp, "unknown auth proto %d\n", proto);
					break;
				case Ppap:
					netlog(ppp->f, Logppp, "password\n");
					break;
				case Pchap:
					netlog(ppp->f, Logppp, "chap %ux\n", o->data[2]);
					break;
				}
				break;
			case Oquality:
				proto = nhgets(o->data);
				switch(proto) {
				default:
					netlog(ppp->f, Logppp, "\tunknown quality proto %d\n", proto);
					break;
				case Plqm:
					x = nhgetl(o->data+2)*10;
					period = (x+Period-1)/Period;
					netlog(ppp->f, Logppp, "\tlqm period = %d\n", period);
					break;
				}
			case Omagic:
				netlog(ppp->f, Logppp, "\tmagic = %ux\n", nhgetl(o->data));
				break;
			case Opc:
				netlog(ppp->f, Logppp, "\tprotocol compress\n");
				break;
			case Oac:
				netlog(ppp->f, Logppp, "\taddr compress\n");
				break;
			}
			break;
		case Pccp:
			switch(o->type){
			default:
				netlog(ppp->f, Logppp, "\tunknown %d len=%d\n", o->type, o->len);
				break;
			case Ocoui:	
				netlog(ppp->f, Logppp, "\tOUI\n");
				break;
			case Ocstac:
				netlog(ppp->f, Logppp, "\tstac LZS\n");
				break;
			case Ocmppc:	
				netlog(ppp->f, Logppp, "\tMicrosoft PPC len=%d %ux\n", o->len, nhgetl(o->data));
				break;
			}
			break;
		case Pecp:
			switch(o->type){
			default:
				netlog(ppp->f, Logppp, "\tunknown %d len=%d\n", o->type, o->len);
				break;
			case Oeoui:	
				netlog(ppp->f, Logppp, "\tOUI\n");
				break;
			case Oedese:
				netlog(ppp->f, Logppp, "\tDES\n");
				break;
			}
			break;
		case Pipcp:
			switch(o->type){
			default:
				netlog(ppp->f, Logppp, "\tunknown %d len=%d\n", o->type, o->len);
				break;
			case Oipaddrs:	
				netlog(ppp->f, Logppp, "\tip addrs - deprecated\n");
				break;
			case Oipcompress:
				netlog(ppp->f, Logppp, "\tip compress\n");
				break;
			case Oipaddr:	
				netlog(ppp->f, Logppp, "\tip addr %V\n", o->data);
				break;
			case Oipdns:
				netlog(ppp->f, Logppp, "\tdns addr %V\n", o->data);
				break;
			case Oipwins:	
				netlog(ppp->f, Logppp, "\twins addr %V\n", o->data);
				break;
			case Oipdns2:
				netlog(ppp->f, Logppp, "\tdns2 addr %V\n", o->data);
				break;
			case Oipwins2:	
				netlog(ppp->f, Logppp, "\twins2 addr %V\n", o->data);
				break;
			}
			break;
		}
	}
}

static void
sendtermreq(PPP *ppp, Pstate *p)
{
	Block *b;
	Lcpmsg *m;

	p->termid = ++(p->id);
	b = alloclcp(Ltermreq, p->termid, 4);
	m = IPB2LCP(b);
	hnputs(m->len, 4);
	putframe(ppp, p->proto, b);
	freeb(b);
	newstate(ppp, p, Sclosing);
}

static void
sendechoreq(PPP *ppp, Pstate *p)
{
	Block *b;
	Lcpmsg *m;

	p->termid = ++(p->id);
	b = alloclcp(Lechoreq, p->id, 4);
	m = IPB2LCP(b);
	hnputs(m->len, 4);
	putframe(ppp, p->proto, b);
	freeb(b);
}

/*
 *  return non-zero if this is a valid v4 address
 */
static int
validv4(Ipaddr addr)
{
	return memcmp(addr, v4prefix, IPv4off) == 0;
}

static void
invalidate(Ipaddr addr)
{
	ipmove(addr, IPnoaddr);
}
