#include "u.h"
#include "../port/lib.h"
#include "mem.h"
#include "dat.h"
#include "fns.h"
#include "../port/error.h"
#include "kernel.h"
#include "ip.h"
#include "ppp.h"

Ipaddr pppdns[2];

static	ulong	fsip;
static	ulong	auip;
static	ulong	gwip;
static	ulong	ipmask;
static	ulong	ipaddr;
static	ulong	dns1ip;
static	ulong	dns2ip;

int		dhcpmsgtype;
int		debug=0;
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
	uchar	op;			/* opcode */
	uchar	htype;		/* hardware type */
	uchar	hlen;			/* hardware address len */
	uchar	hops;		/* hops */
	uchar	xid[4];		/* a random number */
	uchar	secs[2];		/* elapsed snce client started booting */
	uchar	flags[2];		/* flags */
	uchar	ciaddr[4];		/* client IP address (client tells server) */
	uchar	yiaddr[4];		/* client IP address (server tells client) */
	uchar	siaddr[4];		/* server IP address */
	uchar	giaddr[4];		/* gateway IP address */
	uchar	chaddr[16];	/* client hardware address */
	uchar	sname[64];	/* server host name (optional) */
	uchar	file[128];		/* boot file name */
	uchar	vend[128];	/* vendor-specific goo 340 */
} Bootp;

static	Bootp	req;
static	Proc*	rcvprocp;
static	int	recv;
static	int	done;
static	Rendez	bootpr;
static	char	rcvbuf[512+2*IPaddrlen+2*2];	  /* 576 */
static	uchar sid[4];
static	ulong iplease;

/*
 * bootp returns:
 *
 * "fsip d.d.d.d
 * auip d.d.d.d
 * gwip d.d.d.d
 * ipmask d.d.d.d
 * ipaddr d.d.d.d
 * dns1ip	d.d.d.d
 * dns2ip	d.d.d.d
 *
 * where d.d.d.d is the IP address in dotted decimal notation, and each
 * address is followed by a newline.
	Last change:  SUN  13 Sep 2001    4:36 pm
 */

/*
 * Parse the vendor specific fields according to RFC 1084.
 * We are overloading the "cookie server" to be the Inferno 
 * authentication server and the "resource location server"
 * to be the Inferno file server.
 *
 * If the vendor specific field is formatted properly, it
 * will being with the four bytes 99.130.83.99 and end with
 * an 0xFF byte.
 */
static int
parsevend(uchar* pvend)
{	
	uchar *vend=pvend;
	int dhcpmsg=0;
	/* The field must start with 99.130.83.99 to be compliant */
	if ((vend[0] != 99) || (vend[1] != 130) || (vend[2] != 83) || (vend[3] != 99)){
		print("bad bootp vendor field: %.2x%.2x%.2x%.2x", vend[0], vend[1], vend[2], vend[3]);
		return -1;
	}

	/* Skip over the magic cookie */
	vend += 4;

	while ((vend[0] != 0) && (vend[0] != 0xFF)) {
		int i;
//	
		if(debug){
			print(">>>Opt[%d] [%d]", vend[0], vend[1]);
			for(i=0; i<vend[1]; i++)
				print(" %2.2x", vend[i+2]);
			print("\n");
		}
//
		switch (vend[0]) {
		case 1:	/* Subnet mask field */
			/* There must be only one subnet mask */
			if (vend[1] == 4)
				ipmask = (vend[2]<<24)|(vend[3]<<16)| (vend[4]<<8)| vend[5];
			else{ 
				return -1;
			}
			break;

		case 3:	/* Gateway/router field */
			/* We are only concerned with first address */
			if (vend[1] >0 && vend[1]%4==0)
				gwip = (vend[2]<<24)|(vend[3]<<16)|(vend[4]<<8)|vend[5];
			else 
				return -1;
			break;
		case 6:	/* domain name server */
			if(vend[1]>0 && vend[1] %4==0){
				dns1ip=(vend[2]<<24)|(vend[3]<<16)|(vend[4]<<8)|vend[5];
				if(vend[1]>4)
					dns2ip=(vend[6]<<24)|(vend[7]<<16)|(vend[8]<<8)|vend[9];
			}else
				return -1;
			break;

		case 8:	/* "Cookie server" (auth server) field */
			/* We are only concerned with first address */
			if (vend[1] > 0 && vend[1]%4==0)
				auip = (vend[2]<<24)|(vend[3]<<16)|(vend[4]<<8)|vend[5];
			else
				return -1;
			break;

		case 11:	/* "Resource loc server" (file server) field */
			/* We are only concerned with first address */
			if (vend[1] > 0 && vend[1]%4==0)
				fsip = (vend[2]<<24)| (vend[3]<<16)| (vend[4]<<8)| vend[5];
			else
				return -1;
			break;
		case 51:	/* ip lease time */
			if(vend[1]==4){
				iplease=(vend[2]<<24)|(vend[3]<<16)|(vend[4]<<8)|vend[5];
			}else
				return -1;
			break;
		case 53:	/* DHCP message type */
			if(vend[1]==1)
				dhcpmsg=vend[2];
			else
				return -1;
			break;
		case 54:	/* server identifier */
			if(vend[1]==4){
				memmove(sid, vend+2, 4);
			}else
				return -1;
			break;

		default:	/* Everything else stops us */
			break;
		}

		/* Skip over the field */
		vend += vend[1] + 2;
	}
	if(debug)
		print(">>>Opt[%d] [%d]\n", vend[0], vend[1]);
	return dhcpmsg;
}

static void
dispvend(uchar* pvend)
{	
	uchar *vend=pvend;

	//print("<<<Magic : %2.2x%2.2x%2.2x%2.2x\n", vend[0], vend[1], vend[2], vend[3]);
	
	vend += 4;		/* Skip over the magic cookie */
	while ((vend[0] != 0) && (vend[0] != 0xFF)) {
	//	int i;
	  //	print("<<<Opt[%d] [%d]", vend[0], vend[1]);
		//for(i=0; i<vend[1]; i++)
		//	print(" %2.2x", vend[i+2]);
		//print("\n");
	
		vend += vend[1] + 2;
	}
	//print("<<<Opt[ %2.2x] [%2.2x]\n", vend[0], vend[1]);
}

static void
rcvbootp(void *a)
{
	int n, fd, dhcp;
	Bootp *rp;

	if(waserror())
		pexit("", 0);
	rcvprocp = up;	/* store for postnote below */
	fd = (int)a;
	while(done == 0) {
		if(debug)
			print("rcvbootp:looping\n");

		n = kread(fd, rcvbuf, sizeof(rcvbuf));
		if(n <= 0)
			break;
		rp = (Bootp*)rcvbuf;
		if (memcmp(req.chaddr, rp->chaddr, 6) == 0 && rp->htype == 1 && rp->hlen == 6) {
			ipaddr = (rp->yiaddr[0]<<24)| (rp->yiaddr[1]<<16)| (rp->yiaddr[2]<<8)| rp->yiaddr[3];
			if(debug)
				print("ipaddr = %2.2x %2.2x %2.2x %2.2x \n", rp->yiaddr[0], rp->yiaddr[1], rp->yiaddr[2], rp->yiaddr[3]);
			//memmove(req.siaddr, rp->siaddr, 4);	/* siaddr */
			dhcp = parsevend(rp->vend);
	
			if(dhcpmsgtype < dhcp){
				dhcpmsgtype=dhcp;
				recv = 1;
				wakeup(&bootpr);
				if(dhcp==0 || dhcp ==5 || dhcp == 6 )
					break;
			}
		}
	}
	poperror();
	rcvprocp = nil;

	if(debug)
		print("rcvbootp exit\n");
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
	uchar *vend;

	/*
	 * broadcast bootp's till we get a reply,
	 * or fixed number of tries
	 */
	if(debug)
	    print("dhcp: bootp() called\n");
	tries = 0;
	av[1] = "0.0.0.0";
	av[2] = "0.0.0.0";
	ipifcadd(ifc, av, 3, 0, nil);

	cfd = kannounce("udp!*!68", dir);
	if(cfd < 0)
		return "dhcp announce failed";
	strcat(dir, "/data");
	if(kwrite(cfd, "headers", 7) < 0){
		kclose(cfd);
		return "dhcp ctl headers failed";
	}
	kwrite(cfd, "oldheaders", 10);
	dfd = kopen(dir, ORDWR);
	if(dfd < 0){
		kclose(cfd);
		return "dhcp open data failed";
	}
	kclose(cfd);
	
	while(tries<1){
		tries++;
		memset(sid, 0, 4);
		iplease=0;
		dhcpmsgtype=-2;
/* DHCPDISCOVER*/
		done = 0;
		recv = 0;
		kproc("rcvbootp", rcvbootp, (void*)dfd, KPDUPFDG);
		/* Prepare DHCPDISCOVER */	
		memset(&req, 0, sizeof(req));
		ipmove(req.raddr, IPv4bcast);
		hnputs(req.rport, 67);
		req.op = Bootrequest;
		req.htype = 1;			/* ethernet (all we know) */
		req.hlen = 6;			/* ethernet (all we know) */
		
		memmove(req.chaddr, ifc->mac, 6);	/* Hardware MAC address */
		//ipv4local(ifc, req.ciaddr);				/* Fill in the local IP address if we know it */
		memset(req.file, 0, sizeof(req.file));
		vend=req.vend;
		memmove(vend, vend_rfc1048, 4); vend+=4;
		*vend++=53; *vend++=1;*vend++=1;		/* dhcp msg type==3, dhcprequest */
		
		*vend++=61;*vend++=7;*vend++=1;
		memmove(vend, ifc->mac, 6);vend+=6;
		*vend=0xff;

		if(debug)
			dispvend(req.vend); 
		for(n=0;n<4;n++){
			if(kwrite(dfd, &req, sizeof(req))<0)	/* SEND DHCPDISCOVER */
				print("DHCPDISCOVER: %r");
		
			tsleep(&bootpr, return0, 0, 1000);	/* wait DHCPOFFER */
			if(debug)
				print("[DHCP] DISCOVER: msgtype = %d\n", dhcpmsgtype);

			if(dhcpmsgtype==2)		/* DHCPOFFER */
				break;
			else if(dhcpmsgtype==0)	/* bootp */
				return nil;
			else if(dhcpmsgtype== -2)	/* time out */
				continue;
			else
				break;
			
		}
		if(dhcpmsgtype!=2)
			continue;

/* DHCPREQUEST */	
		memset(req.vend, 0, sizeof(req.vend));
		vend=req.vend;
		memmove(vend, vend_rfc1048, 4);vend+=4;	

		*vend++=53; *vend++=1;*vend++=3;		/* dhcp msg type==3, dhcprequest */

		*vend++=50;	*vend++=4;				/* requested ip address */
		*vend++=(ipaddr >> 24)&0xff;
		*vend++=(ipaddr >> 16)&0xff;
		*vend++=(ipaddr >> 8) & 0xff;
		*vend++=ipaddr & 0xff;

		*vend++=51;*vend++=4;					/* lease time */
		*vend++=(iplease>>24)&0xff; *vend++=(iplease>>16)&0xff; *vend++=(iplease>>8)&0xff; *vend++=iplease&0xff;

		*vend++=54; *vend++=4;					/* server identifier */
		memmove(vend, sid, 4);	vend+=4;
	
		*vend++=61;*vend++=07;*vend++=01;		/* client identifier */
		memmove(vend, ifc->mac, 6);vend+=6;
		*vend=0xff;
		if(debug) 
			dispvend(req.vend); 
		if(kwrite(dfd, &req, sizeof(req))<0){
			print("DHCPREQUEST: %r");
			continue;
		}
		tsleep(&bootpr, return0, 0, 2000);
		if(dhcpmsgtype==5)		/* wait for DHCPACK */
			break;
		else
			continue;
		/* CHECK ARP */
		/* DHCPDECLINE */
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
	int n, i;
	char *buf;
	uchar a[4];

	if(debug)
		print("dhcp: bootpread() \n");
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
	n += snprint(buf+n, READSTR-n, "expired %lud\n", iplease);

	n += snprint(buf + n, READSTR-n, "dns");
	if(dns2ip){
		hnputl(a, dns2ip);
		n+=snprint(buf + n, READSTR-n, " %15V", a);
	}
	if(dns1ip){
		hnputl(a, dns1ip);
		n += snprint(buf + n, READSTR-n, " %15V", a);
	}

	for(i=0; i<2; i++)
		if(ipcmp(pppdns[i], IPnoaddr) != 0 && ipcmp(pppdns[i], v4prefix) != 0)
			n += snprint(buf + n, READSTR-n, " %15I", pppdns[i]);

	snprint(buf + n, READSTR-n, "\n");
	len = readstr(offset, bp, len, buf);
	poperror();
	free(buf);
	return len;
}

char*	(*bootp)(Ipifc*) = rbootp;
int	(*bootpread)(char*, ulong, int) = rbootpread;
