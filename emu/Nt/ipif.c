#define Unknown win_Unknown
#include        <windows.h>
#include        <winbase.h>
#include        <sys/types.h>
#include        <winsock.h>
#undef Unknown
#include        "dat.h"
#include        "fns.h"
#include        "ip.h"
#include        "error.h"

typedef int socklen_t;	/* Windows is leading edge as always */


extern int SOCK_SELECT;

char Enotv4[] = "address not IPv4";

static void
ipw6(uchar *a, ulong w)
{
	memmove(a, v4prefix, IPv4off);
	memmove(a+IPv4off, &w, IPv4addrlen);
}

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
	struct sockaddr sa;
	struct sockaddr_in *sin;
	uchar *h = hdr;


	osenter();
	if(hdr == 0)
		r = send(sock, va, len, 0);
	else {
		memset(&sa, 0, sizeof(sa));
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

static int
doselect(int sock)
{
	fd_set	waitr;
	struct timeval seltime;

	up->syscall = SOCK_SELECT;
	FD_ZERO(&waitr);
	FD_SET(sock, &waitr);
	for(;;){
		int nfds;
		fd_set in, exc;

		in = waitr;
		exc = waitr;
		seltime.tv_sec = 1;
		seltime.tv_usec = 0L;
		nfds = select(sizeof(fd_set)*8, &in, (fd_set*)0, &exc, &seltime);
		if(up->intwait) {
			up->intwait = 0;
			return -1;
		}
		if(nfds < 0) {
			print("select error\n");
			return 0;
		}
		if(FD_ISSET(sock, &in) || FD_ISSET(sock, &exc)){
			return 0;
		}
	}
}

int
so_recv(int sock, void *va, int len, void *hdr, int hdrlen)
{
	int r;
	socklen_t l;
	struct sockaddr sa;
	struct sockaddr_in *sin;
	uchar h[Udphdrlen];

	osenter();
	if(doselect(sock) < 0) {
		osleave();
		return -1;
	}
	if(hdr == 0)
		r = recv(sock, va, len, 0);
	else {
		sin = (struct sockaddr_in*)&sa;
		l = sizeof(sa);
		r = recvfrom(sock, va, len, 0, &sa, &l);
		if(r >= 0) {
			memset(h, 0, sizeof(h));
			switch(hdrlen){
			case OUdphdrlenv4:
				memmove(h, &sin->sin_addr, IPv4addrlen);
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
			memset(&sa, 0, sizeof(sa));
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
	closesocket(sock);
}

void
so_connect(int fd, uchar *raddr, ushort rport)
{
	int r;
	struct sockaddr sa;
	struct sockaddr_in *sin;

	if(!isv4(raddr))
		error(Enotv4);

	memset(&sa, 0, sizeof(sa));
	sin = (struct sockaddr_in*)&sa;
	sin->sin_family = AF_INET;
	hnputs(&sin->sin_port, rport);
	memmove(&sin->sin_addr.s_addr, raddr+IPv4off, IPv4addrlen);

	osenter();
	r = connect(fd, &sa, sizeof(sa));
	osleave();
	if(r < 0)
		oserror();
}

void
so_getsockname(int fd, uchar *laddr, ushort *lport)
{
	socklen_t len;
	struct sockaddr sa;
	struct sockaddr_in *sin;

	len = sizeof(sa);
	if(getsockname(fd, &sa, &len) < 0)
		oserror();

	sin = (struct sockaddr_in*)&sa;
	if(sin->sin_family != AF_INET || len != sizeof(*sin))
		error(Enotv4);

	ipw6(laddr, sin->sin_addr.s_addr);
	*lport = nhgets(&sin->sin_port);
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
	int nfd;
	socklen_t len;
	struct sockaddr sa;
	struct sockaddr_in *sin;

	sin = (struct sockaddr_in*)&sa;

	len = sizeof(sa);
	osenter();
	if(doselect(fd) < 0) {
		osleave();
		return -1;
	}
	nfd = accept(fd, &sa, &len);
	osleave();
	if(nfd < 0)
		oserror();

	if(sin->sin_family != AF_INET || len != sizeof(*sin))
		error(Enotv4);

	ipw6(raddr, sin->sin_addr.s_addr);
	*rport = nhgets(&sin->sin_port);
	return nfd;
}

void
so_bind(int fd, int su, uchar *addr, ushort port)
{
	int i, one;
	struct sockaddr sa;
	struct sockaddr_in *sin;

	sin = (struct sockaddr_in*)&sa;

	one = 1;
//	if(setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, (char*)&one, sizeof(one)) < 0) {
//		oserrstr(up->genbuf, sizeof(up->genbuf));
//		print("setsockopt: %s", err);
//	}

	if(su) {
		for(i = 600; i < 1024; i++) {
			memset(&sa, 0, sizeof(sa));
			sin->sin_family = AF_INET;
			memmove(&sin->sin_addr.s_addr, addr+IPv4off, IPv4addrlen);
			hnputs(&sin->sin_port, i);

			if(bind(fd, &sa, sizeof(sa)) >= 0)	
				return;
		}
		oserror();
	}

	memset(&sa, 0, sizeof(sa));
	sin->sin_family = AF_INET;
	memmove(&sin->sin_addr.s_addr, addr+IPv4off, IPv4addrlen);
	hnputs(&sin->sin_port, port);

	if(bind(fd, &sa, sizeof(sa)) < 0)
		oserror();
}

int
so_gethostbyname(char *host, char**hostv, int n)
{
	int i;
	char buf[32];
	uchar *p;
	struct hostent *hp;

	hp = gethostbyname(host);
	if(hp == 0)
		return 0;

	for(i = 0; hp->h_addr_list[i] && i < n; i++) {
		p = (uchar*)hp->h_addr_list[i];
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
so_hangup(int fd, int nolinger)
{
	int r;
	static struct linger l = {1, 0};

	osenter();
	if(nolinger)
		setsockopt(fd, SOL_SOCKET, SO_LINGER, (char*)&l, sizeof(l));
	r = closesocket(fd);
	osleave();
	return r;
}

void
arpadd(char *ipaddr, char *eaddr, int n)
{
	error("arp not implemented");
}

int
so_mustbind(int restricted, int port)
{
	USED(restricted);
	USED(port);
	/* Windows requires bound sockets, even on port 0 */
	return 1;
}

void
so_keepalive(int fd, int ms)
{
	int on;

	USED(ms);
	on = 1;
	setsockopt(fd, SOL_SOCKET, SO_KEEPALIVE, (char*)&on, sizeof(on));
}
