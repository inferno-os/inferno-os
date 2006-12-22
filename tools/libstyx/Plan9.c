#include <lib9.h>
#include "styxserver.h"
#include "styxaux.h"

typedef struct Listener Listener;
typedef struct Reader Reader;
typedef struct Union Union;

struct Listener
{
	int fd;
	char *dir;
	Listener *next;
};

struct Reader
{
	int pid;
	int fd;
	int n;
	char buf[MSGMAX];
	char rbuf[MSGMAX];
	Reader *next;
};

struct Union
{
	int	pid;
	Lock	lock;
	Listener *lr;
	Reader *rr;
};

void xlock(Lock *l){ lock(l); }
void xunlock(Lock *l){ unlock(l); }

static Reader*
findr(Styxserver *server, int fd)
{
	Reader *r;
	Union *u;

	u = server->priv;
	xlock(&u->lock);
	for(r = u->rr; r != nil; r = r->next)
		if(r->fd == fd)
			break;
	xunlock(&u->lock);
	return r;
}

int
styxinitsocket(void)
{
	return 0;
}

void
styxendsocket(void)
{
}

void
styxclosesocket(int fd)
{
	close(fd);
}

static void
listener(Styxserver *server, int afd, char *adir)
{
	int s;
	Listener *l;
	Union *u;
	char ld[40];

	USED(afd);
	u = server->priv;
	for(;;){
		s = listen(adir, ld);
		/* fprint(2, "listen %d %s %s\n", s, adir, ld); */
		if(s < 0){
			u->pid = -1;
			break;
		}
		l = malloc(sizeof(Listener));
		l->fd = s;
		l->dir = strdup(ld);
		xlock(&u->lock);
		l->next = u->lr;
		u->lr = l;
		xunlock(&u->lock);
	}
}

int
styxannounce(Styxserver *server, char *port)
{
	int s, pid;
	Union *u;
	char adr[32], adir[40];

	server->priv = u = malloc(sizeof(Union));
	u->lock.val = 0;
	u->lr = nil;
	u->rr = nil;
	sprint(adr, "tcp!*!%s", port);
	s = announce(adr, adir);
	/* fprint(2, "announce %d %s %s\n", s, adr, adir); */
	if(s < 0)
		return s;
	switch((pid = rfork(RFPROC|RFREND|RFMEM))){
	case 0:
		listener(server, s, strdup(adir));
		break;
	default:
		u->pid = pid;
		break;
	}
	return s;
}

static void
reader(Styxserver *server, Reader *r)
{
	int m, n, s;
	Union *u;

	u = server->priv;
	s = r->fd;
	for(;;){
		n = r->n;
		if(n < 0){
			r->pid = -1;
			exits(nil);
		}
		m = read(s, r->rbuf, MSGMAX-n);
		xlock(&u->lock);
		n = r->n;
		if(m < 0)
			r->n = n == 0 ? m : n;
		else{
			memmove(r->buf+n, r->rbuf, m);
			r->n = m+n;	
		}
		xunlock(&u->lock);
	}
}

int
styxaccept(Styxserver *server)
{
	int s, fd, pid;
	Reader *r;
	Listener *l;
	Union *u;
	char *dir;

	u = server->priv;
	xlock(&u->lock);
	if((l = u->lr) == nil){
		xunlock(&u->lock);
		return -1;
	}
	u->lr = l->next;
	xunlock(&u->lock);
	fd = l->fd;
	dir = l->dir;
	free(l);
	s = accept(fd, dir);
	/* fprint(2, "accept %d\n", s); */
	free(dir);
	if(s < 0)
		return s;
	r = malloc(sizeof(struct Reader));
	r->fd = s;
	r->n = 0;
	xlock(&u->lock);
	r->next = u->rr;
	u->rr = r;
	xunlock(&u->lock);
	switch((pid = rfork(RFPROC|RFREND|RFMEM))){
	case 0:
		reader(server, r);
		break;
	case 1:
		r->pid = pid;
		break;
	}
	return s;
}

void
styxinitwait(Styxserver *server)
{
	USED(server);
}

int
styxnewcall(Styxserver *server)
{
	Union *u;

	u = server->priv;
	return u->lr != nil;
}

int
styxnewmsg(Styxserver *server, int fd)
{
	Reader *r;

	r = findr(server, fd);
	return r != nil && r->n != 0;
}

void
styxnewclient(Styxserver *server, int fd)
{
	USED(server);
	USED(fd);
}

void
styxfreeclient(Styxserver *server, int fd)
{
	Reader *r, **rp;
	Union *u;

	u = server->priv;
	r = findr(server, fd);
	if(r == nil)
		return;
	xlock(&u->lock);
	for(rp = &u->rr; *rp != nil; rp = &(*rp)->next)
		if(r == *rp){
			*rp = r->next;
			break;
		}
	xunlock(&u->lock);
	if(r->pid >= 0)
		postnote(PNPROC, r->pid, "kill");
	free(r);
}

char*
styxwaitmsg(Styxserver *server)
{
	int i;
	Reader *r;
	Union *u;

	u = server->priv;
	for(i = 0; i < 100; i++){
		if(u->lr != nil)
			return nil;
		xlock(&u->lock);
		for(r = u->rr; r != nil; r = r->next)
			if(r->n != 0){
				xunlock(&u->lock);
				return nil;
			}
		xunlock(&u->lock);
		sleep(100);
	}
	return nil;
}

int
styxrecv(Styxserver *server, int fd, char *buf, int n, int m)
{
	Reader *r;
	Union *u;
	int rn;
	char *rbuf;

	USED(m);
	r = findr(server, fd);
	if(r == nil)
		return -1;
	u = server->priv;
	xlock(&u->lock);
	rn = r->n;
	rbuf = r->buf;
	if(rn < 0){
		xunlock(&u->lock);
		return rn;
	}
	if(n > rn)
		n = rn;
	memmove(buf, rbuf, n);
	rn -= n;
	memmove(rbuf, rbuf+n, rn);
	r->n = rn;
	xunlock(&u->lock);
	return n;
}

int
styxsend(Styxserver *server, int fd, char *buf, int n, int m)
{
	USED(server);
	USED(m);
	return write(fd, buf, n);
}

void
styxexit(int n)
{
	if(n)
		exits("error");
	else
		exits(nil);
}
