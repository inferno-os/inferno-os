#include <windows.h>
#include <lib9.h>
#include "styxserver.h"
#include "styxaux.h"

typedef struct Fdset Fdset;

struct Fdset
{
	fd_set infds, outfds, excfds, r_infds, r_outfds, r_excfds;
};

int
styxinitsocket(void)
{
	WSADATA wsaData;
	WORD wVersionRequired=MAKEWORD(1,1);
	
	int rv = WSAStartup(wVersionRequired, &wsaData);	

	if(rv != 0){
		fprint(2, "Unable to Find winsock.dll");
		return -1;
	}
	if(LOBYTE(wsaData.wVersion) != 1 || HIBYTE(wsaData.wVersion) != 1 ){
	   	fprint(2, "Unable to find winsock.dll V1.1 or later");
		return -1;
	}
	return 0;
}

void
styxendsocket(void)
{
	WSACleanup( );
}

void
styxclosesocket(int fd)
{
	closesocket(fd);
}

int
styxannounce(Styxserver *server, char *port)
{
	struct sockaddr_in sin;
	int s, one;

	USED(server);
	s = socket(AF_INET, SOCK_STREAM, 0);
	if(s < 0)
		return s;
	one = 1;
	if(setsockopt(s, SOL_SOCKET, SO_REUSEADDR, (char*)&one, sizeof(one)) < 0)
		fprint(2, "setsockopt failed\n");
	memset(&sin, 0, sizeof(sin));
	sin.sin_family = AF_INET;
	sin.sin_addr.s_addr = 0;
	sin.sin_port = htons(atoi(port));
	if(bind(s, (struct sockaddr *)&sin, sizeof(sin)) < 0){
		close(s);
		return -1;
	}
	if(listen(s, 20) < 0){
		close(s);
		return -1;
	}
	return s;
}

int
styxaccept(Styxserver *server)
{
	struct sockaddr_in sin;
	int len, s;

	len = sizeof(sin);
	memset(&sin, 0, sizeof(sin));
	sin.sin_family = AF_INET;
	s = accept(server->connfd, (struct sockaddr *)&sin, &len);
	if(s < 0){
		if(errno != EINTR)
			fprint(2, "error in accept: %s\n", strerror(errno));
	}
	return s;
}

void
styxinitwait(Styxserver *server)
{
	Fdset *fs;

	server->priv = fs = malloc(sizeof(Fdset));
	FD_ZERO(&fs->infds);
	FD_ZERO(&fs->outfds);
	FD_ZERO(&fs->excfds);
	FD_SET(server->connfd, &fs->infds);
}

int
styxnewcall(Styxserver *server)
{
	Fdset *fs;

	fs = server->priv;
	return FD_ISSET(server->connfd, &fs->r_infds);
}

void
styxnewclient(Styxserver *server, int s)
{
	Fdset *fs;

	fs = server->priv;
	FD_SET(s, &fs->infds);
}

void
styxfreeclient(Styxserver *server, int s)
{
	Fdset *fs;

	fs = server->priv;
	FD_CLR(s, &fs->infds);
}

int
styxnewmsg(Styxserver *server, int s)
{
	Fdset *fs;

	fs = server->priv;
	return FD_ISSET(s, &fs->r_infds) || FD_ISSET(s, &fs->r_excfds);
}

char*
styxwaitmsg(Styxserver *server)
{
	struct timeval seltime;
	int nfds;
	Fdset *fs;

	fs = server->priv;
	fs->r_infds = fs->infds;
	fs->r_outfds = fs->outfds;
	fs->r_excfds = fs->excfds;
	seltime.tv_sec = 10;
	seltime.tv_usec = 0L;
	nfds = select(sizeof(fd_set)*8, &fs->r_infds, &fs->r_outfds, &fs->r_excfds, &seltime);
	if(nfds < 0 && errno != EINTR)
		return"error in select";
	return nil;
}

int
styxrecv(Styxserver *server, int fd, char *buf, int n, int m)
{
	return recv(fd, buf, n, m);
}

int
styxsend(Styxserver *server, int fd, char *buf, int n, int m)
{
	return send(fd, buf, n, m);
}

void
styxexit(int n)
{
	exit(n);
}
