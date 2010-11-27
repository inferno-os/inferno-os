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
#include	<arpa/inet.h>
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
	int v6only;

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

	fd = socket(AF_INET6, type, 0);
	if(fd < 0)
		oserror();

	/* OpenBSD has v6only fixed to 1, so the following will fail */
	v6only = 0;
	if(setsockopt(fd, IPPROTO_IPV6, IPV6_V6ONLY, (void*)&v6only, sizeof v6only) < 0)
		oserror();

	if(type == SOCK_DGRAM){
		one = 1;
		setsockopt(fd, SOL_SOCKET, SO_BROADCAST, (char*)&one, sizeof(one));
	}else{
		one = 1;
		setsockopt(fd, IPPROTO_TCP, TCP_NODELAY, (char*)&one, sizeof(one));
	}
	return fd;
}

int
so_send(int sock, void *va, int len, void *hdr, int hdrlen)
{
	int r;
	struct sockaddr_storage sa;
	struct sockaddr_in6 *sin6;
	char *h = hdr;

	osenter();
	if(hdr == 0)
		r = write(sock, va, len);
	else {
		memset(&sa, 0, sizeof(sa));
		sin6 = (struct sockaddr_in6*)&sa;
		sin6->sin6_family = AF_INET6;
		switch(hdrlen){
		case OUdphdrlenv4:
			v4tov6((uchar*)&sin6->sin6_addr, h);
			memmove(&sin6->sin6_port, h+8, 2);
			break;
		case OUdphdrlen:
			memmove((uchar*)&sin6->sin6_addr, h, IPaddrlen);
			memmove(&sin6->sin6_port, h+2*IPaddrlen, 2);	/* rport */
			break;
		default:
			memmove((uchar*)&sin6->sin6_addr, h, IPaddrlen);
			memmove(&sin6->sin6_port, h+3*IPaddrlen, 2);
			break;
		}
		r = sendto(sock, va, len, 0, (struct sockaddr*)sin6, sizeof(*sin6));
	}
	osleave();
	return r;
}

int
so_recv(int sock, void *va, int len, void *hdr, int hdrlen)
{
	int r, l;
	struct sockaddr_storage sa;
	struct sockaddr_in6 *sin6;
	char h[Udphdrlen];

	osenter();
	if(hdr == 0)
		r = read(sock, va, len);
	else {
		sin6 = (struct sockaddr_in6*)&sa;
		l = sizeof(sa);
		r = recvfrom(sock, va, len, 0, (struct sockaddr*)&sa, &l);
		if(r >= 0) {
			memset(h, 0, sizeof(h));
			switch(hdrlen){
			case OUdphdrlenv4:
				if(v6tov4(h, (uchar*)&sin6->sin6_addr) < 0) {
					osleave();
					error("OUdphdrlenv4 with IPv6 address");
				}
				memmove(h+2*IPv4addrlen, &sin6->sin6_port, 2);
				break;
			case OUdphdrlen:
				memmove(h, (uchar*)&sin6->sin6_addr, IPaddrlen);
				memmove(h+2*IPaddrlen, &sin6->sin6_port, 2);
				break;
			default:
				memmove(h, (uchar*)&sin6->sin6_addr, IPaddrlen);
				memmove(h+3*IPaddrlen, &sin6->sin6_port, 2);
				break;
			}

			/* alas there's no way to get the local addr/port correctly.  Pretend. */
			memset(&sa, 0, sizeof(sa));
			l = sizeof(sa);
			getsockname(sock, (struct sockaddr*)&sa, &l);
			switch(hdrlen){
			case OUdphdrlenv4:
				/*
				 * we get v6Unspecified/noaddr if local address cannot be determined.
				 * that's reasonable for ipv4 too.
				 */
				if(ipcmp(v6Unspecified, (uchar*)&sin6->sin6_addr) != 0
				&& v6tov4(h+IPv4addrlen, (uchar*)&sin6->sin6_addr) < 0) {
					osleave();
					error("OUdphdrlenv4 with IPv6 address");
				}
				memmove(h+2*IPv4addrlen+2, &sin6->sin6_port, 2);
				break;
			case OUdphdrlen:
				memmove(h+IPaddrlen, (uchar*)&sin6->sin6_addr, IPaddrlen);
				memmove(h+2*IPaddrlen+2, &sin6->sin6_port, 2);
				break;
			default:
				memmove(h+IPaddrlen, (uchar*)&sin6->sin6_addr, IPaddrlen);
				memmove(h+2*IPaddrlen, (uchar*)&sin6->sin6_addr, IPaddrlen);	/* ifcaddr */
				memmove(h+3*IPaddrlen+2, &sin6->sin6_port, 2);
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
so_connect(int fd, uchar *raddr, ushort rport)
{
	int r;
	struct sockaddr_storage sa;
	struct sockaddr_in6 *sin6;

	memset(&sa, 0, sizeof(sa));
	sin6 = (struct sockaddr_in6*)&sa;
	sin6->sin6_family = AF_INET6;
	hnputs(&sin6->sin6_port, rport);
	memmove((uchar*)&sin6->sin6_addr, raddr, IPaddrlen);

	osenter();
	r = connect(fd, (struct sockaddr*)sin6, sizeof(*sin6));
	osleave();
	if(r < 0)
		oserror();
}

void
so_getsockname(int fd, uchar *laddr, ushort *lport)
{
	int len;
	struct sockaddr_storage sa;
	struct sockaddr_in6 *sin6;

	len = sizeof(*sin6);
	if(getsockname(fd, (struct sockaddr*)&sa, &len) < 0)
		oserror();

	sin6 = (struct sockaddr_in6*)&sa;
	if(sin6->sin6_family != AF_INET6 || len != sizeof(*sin6))
		error("not AF_INET6");

	memmove(laddr, &sin6->sin6_addr, IPaddrlen);
	*lport = nhgets(&sin6->sin6_port);
}

void
so_listen(int fd)
{
	int r;

	osenter();
	r = listen(fd, 256);
	osleave();
	if(r < 0)
		oserror();
}

int
so_accept(int fd, uchar *raddr, ushort *rport)
{
	int nfd, len;
	struct sockaddr_storage sa;
	struct sockaddr_in6 *sin6;

	sin6 = (struct sockaddr_in6*)&sa;

	len = sizeof(*sin6);
	osenter();
	nfd = accept(fd, (struct sockaddr*)&sa, &len);
	osleave();
	if(nfd < 0)
		oserror();

	if(sin6->sin6_family != AF_INET6 || len != sizeof(*sin6))
		error("not AF_INET6");

	memmove(raddr, &sin6->sin6_addr, IPaddrlen);
	*rport = nhgets(&sin6->sin6_port);
	return nfd;
}

void
so_bind(int fd, int su, uchar *addr, ushort port)
{
	int i, one;
	struct sockaddr_storage sa;
	struct sockaddr_in6 *sin6;

	sin6 = (struct sockaddr_in6*)&sa;

	one = 1;
	if(setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, (char*)&one, sizeof(one)) < 0) {
		oserrstr(up->genbuf, sizeof(up->genbuf));
		print("setsockopt: %s", up->genbuf);
	}

	if(su) {
		for(i = 600; i < 1024; i++) {
			memset(&sa, 0, sizeof(sa));
			sin6->sin6_family = AF_INET6;
			memmove(&sin6->sin6_addr, addr, IPaddrlen);
			hnputs(&sin6->sin6_port, i);

			if(bind(fd, (struct sockaddr*)sin6, sizeof(*sin6)) >= 0)	
				return;
		}
		oserror();
	}

	memset(&sa, 0, sizeof(sa));
	sin6->sin6_family = AF_INET6;
	memmove(&sin6->sin6_addr, addr, IPaddrlen);
	hnputs(&sin6->sin6_port, port);

	if(bind(fd, (struct sockaddr*)sin6, sizeof(*sin6)) < 0)
		oserror();
}

static int
resolve(char *name, char **hostv, int n, int isnumeric)
{
	int i;
	struct addrinfo *res0, *r;
	char buf[5*8];
	uchar addr[IPaddrlen];
	struct addrinfo hints;

	memset(&hints, 0, sizeof hints);
	hints.ai_flags = isnumeric? AI_NUMERICHOST: 0;
	hints.ai_family = PF_UNSPEC;
	hints.ai_socktype = SOCK_STREAM;
	if(getaddrinfo(name, nil, &hints, &res0) < 0)
		return 0;
	i = 0;
	for(r = res0; r != nil && i < n; r = r->ai_next) {
		if(r->ai_family == AF_INET)
			v4tov6(addr, (uchar*)&((struct sockaddr_in*)r->ai_addr)->sin_addr);
		else if(r->ai_family == AF_INET6)
			memmove(addr, &((struct sockaddr_in6*)r->ai_addr)->sin6_addr, IPaddrlen);
		else
			continue;

		snprint(buf, sizeof buf, "%I", addr);
		hostv[i++] = strdup(buf);
	}

	freeaddrinfo(res0);
	return i;
}

int
so_gethostbyname(char *host, char **hostv, int n)
{
	return resolve(host, hostv, n, 0);
}

int
so_gethostbyaddr(char *addr, char **hostv, int n)
{
	return resolve(addr, hostv, n, 1);
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
so_hangup(int fd, int nolinger)
{
	int r;
	static struct linger l = {1, 0};

	osenter();
	if(nolinger)
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
