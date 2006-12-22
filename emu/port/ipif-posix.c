#ifdef sun
#define	uint uxuint
#define	ulong uxulong
#define	ushort uxushort
#endif
#include <sys/types.h>
#include	<sys/time.h>
#include	<sys/socket.h>
#include	<net/if.h>
#include	<net/if_arp.h>
#include	<netinet/in.h>
#include	<netinet/tcp.h>
#include	<netdb.h>
#include	<sys/ioctl.h>
#undef ulong
#undef ushort
#undef uint

#include        "dat.h"
#include        "fns.h"
#include        "ip.h"
#include        "error.h"

int
so_socket(int type)
{
	int fd, one;

	switch(type) {
	default:
		error("bad protocol type");
	case S_TCP:
		type = SOCK_STREAM;
		break;
	case S_UDP:
		type = SOCK_DGRAM;
		break;
	}

	fd = socket(AF_INET, type, 0);
	if(fd < 0)
		oserror();
	if(type == SOCK_DGRAM){
		one = 1;
		setsockopt(fd, SOL_SOCKET, SO_BROADCAST, (char*)&one, sizeof (one));
	}else{
		one = 1;
		setsockopt(fd, IPPROTO_TCP, TCP_NODELAY, (char *)&one, sizeof(one));
	}
	return fd;
}

int
so_send(int sock, void *va, int len, void *hdr, int hdrlen)
{
	int r;
	struct sockaddr sa;
	struct sockaddr_in *sin;
	char *h = hdr;


	osenter();
	if(hdr == 0)
		r = write(sock, va, len);
	else {
		memset(&sa, sizeof(sa), 0);
		sin = (struct sockaddr_in*)&sa;
		sin->sin_family = AF_INET;
		switch(hdrlen){
		case OUdphdrlenv4:
			memmove(&sin->sin_addr, h,  4);
			memmove(&sin->sin_port, h+8, 2);
			break;
		case OUdphdrlen:
			v6tov4((uchar*)&sin->sin_addr, h);
			memmove(&sin->sin_port, h+2*IPaddrlen, 2);	/* rport */
			break;
		default:
			v6tov4((uchar*)&sin->sin_addr, h);
			memmove(&sin->sin_port, h+3*IPaddrlen, 2);
			break;
		}
		r = sendto(sock, va, len, 0, &sa, sizeof(sa));
	}
	osleave();
	return r;
}

int
so_recv(int sock, void *va, int len, void *hdr, int hdrlen)
{
	int r, l;
	struct sockaddr sa;
	struct sockaddr_in *sin;
	char h[Udphdrlen];


	osenter();
	if(hdr == 0)
		r = read(sock, va, len);
	else {
		sin = (struct sockaddr_in*)&sa;
		l = sizeof(sa);
		r = recvfrom(sock, va, len, 0, &sa, &l);
		if(r >= 0) {
			memset(h, sizeof h, 0);
			switch(hdrlen){
			case OUdphdrlenv4:
				memmove(h, &sin->sin_addr, 4);
				memmove(h+2*IPv4addrlen, &sin->sin_port, 2);
				break;
			case OUdphdrlen:
				v4tov6(h, (uchar*)&sin->sin_addr);
				memmove(h+2*IPaddrlen, &sin->sin_port, 2);
				break;
			default:
				v4tov6(h, (uchar*)&sin->sin_addr);
				memmove(h+3*IPaddrlen, &sin->sin_port, 2);
				break;
			}

			/* alas there's no way to get the local addr/port correctly.  Pretend. */
			getsockname(sock, &sa, &l);
			switch(hdrlen){
			case OUdphdrlenv4:
				memmove(h+IPv4addrlen, &sin->sin_addr, IPv4addrlen);
				memmove(h+2*IPv4addrlen+2, &sin->sin_port, 2);
				break;
			case OUdphdrlen:
				v4tov6(h+IPaddrlen, (uchar*)&sin->sin_addr);
				memmove(h+2*IPaddrlen+2, &sin->sin_port, 2);
				break;
			default:
				v4tov6(h+IPaddrlen, (uchar*)&sin->sin_addr);
				v4tov6(h+2*IPaddrlen, (uchar*)&sin->sin_addr);	/* ifcaddr */
				memmove(h+3*IPaddrlen+2, &sin->sin_port, 2);
				break;
			}
			memmove(hdr, h, hdrlen);
		}
	}
	osleave();
	return r;
}

void
so_close(int sock)
{
	close(sock);
}

void
so_connect(int fd, unsigned long raddr, unsigned short rport)
{
	int r;
	struct sockaddr sa;
	struct sockaddr_in *sin;

	memset(&sa, 0, sizeof(sa));
	sin = (struct sockaddr_in*)&sa;
	sin->sin_family = AF_INET;
	hnputs(&sin->sin_port, rport);
	hnputl(&sin->sin_addr.s_addr, raddr);

	osenter();
	r = connect(fd, &sa, sizeof(sa));
	osleave();
	if(r < 0)
		oserror();
}

void
so_getsockname(int fd, unsigned long *laddr, unsigned short *lport)
{
	int len;
	struct sockaddr sa;
	struct sockaddr_in *sin;

	len = sizeof(sa);
	if(getsockname(fd, &sa, &len) < 0)
		oserror();

	sin = (struct sockaddr_in*)&sa;
	if(sin->sin_family != AF_INET || len != sizeof(*sin))
		error("not AF_INET");

	*laddr = nhgetl(&sin->sin_addr.s_addr);
	*lport = nhgets(&sin->sin_port);
}

void
so_listen(int fd)
{
	int r;

	osenter();
	r = listen(fd, 5);
	osleave();
	if(r < 0)
		oserror();
}

int
so_accept(int fd, unsigned long *raddr, unsigned short *rport)
{
	int nfd, len;
	struct sockaddr sa;
	struct sockaddr_in *sin;

	sin = (struct sockaddr_in*)&sa;

	len = sizeof(sa);
	osenter();
	nfd = accept(fd, &sa, &len);
	osleave();
	if(nfd < 0)
		oserror();

	if(sin->sin_family != AF_INET || len != sizeof(*sin))
		error("not AF_INET");

	*raddr = nhgetl(&sin->sin_addr.s_addr);
	*rport = nhgets(&sin->sin_port);
	return nfd;
}

void
so_bind(int fd, int su, unsigned short port)
{
	int i, one;
	struct sockaddr sa;
	struct sockaddr_in *sin;

	sin = (struct sockaddr_in*)&sa;

	one = 1;
	if(setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, (char*)&one, sizeof(one)) < 0) {
		oserrstr(up->genbuf, sizeof(up->genbuf));
		print("setsockopt: %s", up->genbuf);
	}

	if(su) {
		for(i = 600; i < 1024; i++) {
			memset(&sa, 0, sizeof(sa));
			sin->sin_family = AF_INET;
			hnputs(&sin->sin_port, i);

			if(bind(fd, &sa, sizeof(sa)) >= 0)	
				return;
		}
		oserror();
	}

	memset(&sa, 0, sizeof(sa));
	sin->sin_family = AF_INET;
	hnputs(&sin->sin_port, port);

	if(bind(fd, &sa, sizeof(sa)) < 0)
		oserror();
}

void
so_setsockopt(int fd, int opt, int value)
{
	int r;
	struct linger l;

	if(opt == SO_LINGER){
		l.l_onoff = 1;
		l.l_linger = (short) value;
		osenter();
		r = setsockopt(fd, SOL_SOCKET, opt, (char *)&l, sizeof(l));
		osleave();
	}else
		error(Ebadctl);
	if(r < 0)
		oserror();
}

int
so_gethostbyname(char *host, char**hostv, int n)
{
	int i;
	unsigned char buf[32], *p;
	struct hostent *hp;

	hp = gethostbyname(host);
	if(hp == 0)
		return 0;

	for(i = 0; hp->h_addr_list[i] && i < n; i++) {
		p = hp->h_addr_list[i];
		sprint(buf, "%ud.%ud.%ud.%ud", p[0], p[1], p[2], p[3]);
		hostv[i] = strdup(buf);
		if(hostv[i] == 0)
			break;
	}
	return i;
}

int
so_gethostbyaddr(char *addr, char **hostv, int n)
{
	int i;
	struct hostent *hp;
	unsigned long straddr;

	straddr = inet_addr(addr);
	if(straddr == -1)
		return 0;

	hp = gethostbyaddr((char *)&straddr, sizeof(straddr), AF_INET);
	if(hp == 0)
		return 0;

	hostv[0] = strdup(hp->h_name);
	if(hostv[0] == 0)
		return 0;
	for(i = 1; hp->h_aliases[i-1] && i < n; i++) {
		hostv[i] = strdup(hp->h_aliases[i-1]);
		if(hostv[i] == 0)
			break;
	}
	return i;
}

int
so_getservbyname(char *service, char *net, char *port)
{
	ushort p;
	struct servent *s;

	s = getservbyname(service, net);
	if(s == 0)
		return -1;
	p = s->s_port;
	sprint(port, "%d", nhgets(&p));	
	return 0;
}

int
so_hangup(int fd, int linger)
{
	int r;
	static struct linger l = {1, 1000};

	osenter();
	if(linger)
		setsockopt(fd, SOL_SOCKET, SO_LINGER, (char*)&l, sizeof(l));
	r = shutdown(fd, 2);
	if(r >= 0)
		r = close(fd);
	osleave();
	return r;
}

void
arpadd(char *ipaddr, char *eaddr, int n)
{
#ifdef SIOCGARP
	struct arpreq a;
	struct sockaddr_in pa;
	int s;
	uchar addr[IPaddrlen];

	s = socket(AF_INET, SOCK_DGRAM, 0);
	memset(&a, 0, sizeof(a));
	memset(&pa, 0, sizeof(pa));
	pa.sin_family = AF_INET;
	pa.sin_port = 0;
	parseip(addr, ipaddr);
	if(!isv4(addr)){
		close(s);
		error(Ebadarg);
	}
	memmove(&pa.sin_addr, ipaddr+IPv4off, IPv4addrlen);
	memmove(&a.arp_pa, &pa, sizeof(pa));
	while(ioctl(s, SIOCGARP, &a) != -1) {
		ioctl(s, SIOCDARP, &a);
		memset(&a.arp_ha, 0, sizeof(a.arp_ha));
	}
	a.arp_ha.sa_family = AF_UNSPEC;
	parsemac((uchar*)a.arp_ha.sa_data, eaddr, 6);
	a.arp_flags = ATF_PERM;
	if(ioctl(s, SIOCSARP, &a) == -1) {
		oserrstr(up->env->errstr, ERRMAX);
		close(s);
		error(up->env->errstr);
	}
	close(s);
#else
	error("arp not implemented");
#endif
}

int
so_mustbind(int restricted, int port)
{
	return restricted || port != 0;
}

void
so_keepalive(int fd, int ms)
{
	int on;

	on = 1;
	setsockopt(fd, SOL_SOCKET, SO_KEEPALIVE, (char*)&on, sizeof(on));
#ifdef TCP_KEEPIDLE
	if(ms <= 120000)
		ms = 120000;
	ms /= 1000;
	setsockopt(fd, IPPROTO_TCP, TCP_KEEPIDLE, (char*)&ms, sizeof(ms));
#endif
}
