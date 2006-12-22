#include "u.h"
#include "../port/lib.h"
#include "mem.h"
#include "dat.h"
#include "fns.h"
#include "../port/error.h"
#include "kernel.h"
#include "ip.h"

static	ulong	fsip;
static	ulong	auip;
static	ulong	gwip;
static	ulong	ipmask;
static	ulong	ipaddr;
static	ulong	dnsip;

enum
{
	Bootrequest = 1,
	Bootreply   = 2,
};

typedef struct Bootp
{
	/* udp.c oldheader */
	uchar	raddr[IPaddrlen];
	uchar	laddr[IPaddrlen];
	uchar	rport[2];
	uchar	lport[2];
	/* bootp itself */
	uchar	op;		/* opcode */
	uchar	htype;		/* hardware type */
	uchar	hlen;		/* hardware address len */
	uchar	hops;		/* hops */
	uchar	xid[4];		/* a random number */
	uchar	secs[2];	/* elapsed snce client started booting */
	uchar	pad[2];
	uchar	ciaddr[4];	/* client IP address (client tells server) */
	uchar	yiaddr[4];	/* client IP address (server tells client) */
	uchar	siaddr[4];	/* server IP address */
	uchar	giaddr[4];	/* gateway IP address */
	uchar	chaddr[16];	/* client hardware address */
	uchar	sname[64];	/* server host name (optional) */
	uchar	file[128];	/* boot file name */
	uchar	vend[128];	/* vendor-specific goo */
} Bootp;

/*
 * bootp returns:
 *
 * "fsip d.d.d.d
 * auip d.d.d.d
 * gwip d.d.d.d
 * ipmask d.d.d.d
 * ipaddr d.d.d.d
 * dnsip d.d.d.d"
 *
 * where d.d.d.d is the IP address in dotted decimal notation, and each
 * address is followed by a newline.
 */

static	Bootp	req;
static	Proc*	rcvprocp;
static	int	recv;
static	int	done;
static	Rendez	bootpr;
static	char	rcvbuf[512];
static	int	bootpdebug;

/*
 * Parse the vendor specific fields according to RFC 1084.
 * We are overloading the "cookie server" to be the Inferno 
 * authentication server and the "resource location server"
 * to be the Inferno file server.
 *
 * If the vendor specific field is formatted properly, it
 * will begin with the four bytes 99.130.83.99 and end with
 * an 0xFF byte.
 */
static void
parsevend(uchar* vend)
{
	/* The field must start with 99.130.83.99 to be compliant */
	if ((vend[0] != 99) || (vend[1] != 130) ||
	    (vend[2] != 83) || (vend[3] != 99)){
		if(bootpdebug)
			print("bad bootp vendor field: %.2x%.2x%.2x%.2x", vend[0], vend[1], vend[2], vend[3]);
		return;
	}

	/* Skip over the magic cookie */
	vend += 4;

	while ((vend[0] != 0) && (vend[0] != 0xFF)) {
		if(bootpdebug){
			int i;
			print("vend %d [%d]", vend[0], vend[1]);
			for(i=0; i<vend[1]; i++)
				print(" %2.2x", vend[i]);
			print("\n");
		}
		switch (vend[0]) {
		case 1:	/* Subnet mask field */
			/* There must be only one subnet mask */
			if (vend[1] != 4)
				return;

			ipmask = (vend[2]<<24)|
				 (vend[3]<<16)|
				 (vend[4]<<8)|
				  vend[5];
			break;

		case 3:	/* Gateway/router field */
			/* We are only concerned with first address */
			if (vend[1] < 4)
				break;

			gwip =	(vend[2]<<24)|
				(vend[3]<<16)|
				(vend[4]<<8)|
				 vend[5];
			break;

		case 6:	/* DNS server */
			/* We are only concerned with first address */
			if (vend[1] < 4)
				break;

			dnsip =	(vend[2]<<24)|
				(vend[3]<<16)|
				(vend[4]<<8)|
				 vend[5];
			break;

		case 8:	/* "Cookie server" (auth server) field */
			/* We are only concerned with first address */
			if (vend[1] < 4)
				break;

			auip =	(vend[2]<<24)|
				(vend[3]<<16)|
				(vend[4]<<8)|
				 vend[5];
			break;

		case 11:	/* "Resource loc server" (file server) field */
			/* We are only concerned with first address */
			if (vend[1] < 4)
				break;

			fsip =	(vend[2]<<24)|
				(vend[3]<<16)|
				(vend[4]<<8)|
				 vend[5];
			break;

		default:	/* Ignore everything else */
			break;
		}

		/* Skip over the field */
		vend += vend[1] + 2;
	}
}

static void
rcvbootp(void *a)
{
	int n, fd;
	Bootp *rp;

	if(waserror())
		pexit("", 0);
	rcvprocp = up;	/* store for postnote below */
	fd = (int)a;
	while(done == 0) {
		n = kread(fd, rcvbuf, sizeof(rcvbuf));
		if(n <= 0)
			break;
		rp = (Bootp*)rcvbuf;
		if (memcmp(req.chaddr, rp->chaddr, 6) == 0 &&
		   rp->htype == 1 && rp->hlen == 6) {
			ipaddr = (rp->yiaddr[0]<<24)|
				 (rp->yiaddr[1]<<16)|
				 (rp->yiaddr[2]<<8)|
				  rp->yiaddr[3];
			parsevend(rp->vend);
			break;
		}
	}
	poperror();
	rcvprocp = nil;

	recv = 1;
	wakeup(&bootpr);
	pexit("", 0);
}

static char*
rbootp(Ipifc *ifc)
{
	int cfd, dfd, tries, n;
	char ia[5+3*16], im[16], *av[3];
	uchar nipaddr[4], ngwip[4], nipmask[4];
	char dir[Maxpath];
	static uchar vend_rfc1048[] = { 99, 130, 83, 99 };

	av[1] = "0.0.0.0";
	av[2] = "0.0.0.0";
	ipifcadd(ifc, av, 3, 0, nil);

	cfd = kannounce("udp!*!68", dir);
	if(cfd < 0)
		return "bootp announce failed";
	strcat(dir, "/data");
	if(kwrite(cfd, "headers", 7) < 0){
		kclose(cfd);
		return "bootp ctl headers failed";
	}
	kwrite(cfd, "oldheaders", 10);
	dfd = kopen(dir, ORDWR);
	if(dfd < 0){
		kclose(cfd);
		return "bootp open data failed";
	}
	kclose(cfd);

	/* create request */
	memset(&req, 0, sizeof(req));
	ipmove(req.raddr, IPv4bcast);
	hnputs(req.rport, 67);
	req.op = Bootrequest;
	req.htype = 1;			/* ethernet (all we know) */
	req.hlen = 6;			/* ethernet (all we know) */

	/* Hardware MAC address */
	memmove(req.chaddr, ifc->mac, 6);
	/* Fill in the local IP address if we know it */
	ipv4local(ifc, req.ciaddr);
	memset(req.file, 0, sizeof(req.file));
	memmove(req.vend, vend_rfc1048, 4);

	done = 0;
	recv = 0;

	kproc("rcvbootp", rcvbootp, (void*)dfd, KPDUPFDG);

	/*
	 * broadcast bootp's till we get a reply,
	 * or fixed number of tries
	 */
	tries = 0;
	while(recv == 0) {
		if(kwrite(dfd, &req, sizeof(req)) < 0)
			print("bootp: write: %r");

		tsleep(&bootpr, return0, 0, 1000);
		if(++tries > 10) {
			print("bootp: timed out\n");
			break;
		}
	}
	kclose(dfd);
	done = 1;
	if(rcvprocp != nil){
		postnote(rcvprocp, 1, "timeout", 0);
		rcvprocp = nil;
	}

	av[1] = "0.0.0.0";
	av[2] = "0.0.0.0";
	ipifcrem(ifc, av, 3);

	hnputl(nipaddr, ipaddr);
	sprint(ia, "%V", nipaddr);
	hnputl(nipmask, ipmask);
	sprint(im, "%V", nipmask);
	av[1] = ia;
	av[2] = im;
	ipifcadd(ifc, av, 3, 0, nil);

	if(gwip != 0) {
		hnputl(ngwip, gwip);
		n = sprint(ia, "add 0.0.0.0 0.0.0.0 %V", ngwip);
		routewrite(ifc->conv->p->f, nil, ia, n);
	}
	return nil;
}

static int
rbootpread(char *bp, ulong offset, int len)
{
	int n;
	char *buf;
	uchar a[4];

	buf = smalloc(READSTR);
	if(waserror()){
		free(buf);
		nexterror();
	}
	hnputl(a, fsip);
	n = snprint(buf, READSTR, "fsip %15V\n", a);
	hnputl(a, auip);
	n += snprint(buf + n, READSTR-n, "auip %15V\n", a);
	hnputl(a, gwip);
	n += snprint(buf + n, READSTR-n, "gwip %15V\n", a);
	hnputl(a, ipmask);
	n += snprint(buf + n, READSTR-n, "ipmask %15V\n", a);
	hnputl(a, ipaddr);
	n += snprint(buf + n, READSTR-n, "ipaddr %15V\n", a);
	hnputl(a, dnsip);
	snprint(buf + n, READSTR-n, "dnsip %15V\n", a);

	len = readstr(offset, bp, len, buf);
	poperror();
	free(buf);
	return len;
}

char*	(*bootp)(Ipifc*) = rbootp;
int	(*bootpread)(char*, ulong, int) = rbootpread;
