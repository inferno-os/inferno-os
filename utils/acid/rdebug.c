#include <lib9.h>
#include <bio.h>
#include <ctype.h>
#include "mach.h"
#define Extern extern
#include "acid.h"
#include "../../include/rdbg.h"

/*
 * remote kernel debugging
 */

enum {
	chatty = 0
};

static	long	myreadn(int, void*, long);
static	int	rproto(int, char*, int);

void
remotemap(Map *m, int i)
{
	setmapio(m, i, remget, remput);
}

/*
 * send a /proc control message to remote pid,
 * and await a reply
 */
int
sendremote(int pid, char *msg)
{
	int tag;
	char dbg[RDBMSGLEN];

	if(protodebug)
		fprint(2, "sendremote: pid %d: %s\n", pid, msg);
	if(strcmp(msg, "startstop") == 0)
		tag = Tstartstop;
	else if(strcmp(msg, "waitstop") == 0)
		tag = Twaitstop;
	else if(strcmp(msg, "start") == 0)
		tag = Tstart;
	else if(strcmp(msg, "stop") == 0)
		tag = Tstop;
	else if(strcmp(msg, "kill") == 0)
		tag = Tkill;
	else {
		werrstr("invalid sendremote: %s", msg);
		return -1;
	}
	memset(dbg, 0, sizeof(dbg));
	dbg[0] = tag;
	dbg[1] = pid>>24;
	dbg[2] = pid>>16;
	dbg[3] = pid>>8;
	dbg[4] = pid;
	if(rproto(remfd, dbg, sizeof(dbg)) < 0)
		return -1;
	return 0;
}

/*
 * read a line from /proc/<pid>/<file> into buf
 */
int
remoteio(int pid, char *file, char *buf, int nb)
{
	char dbg[RDBMSGLEN];
	int tag;

	if(protodebug)
		fprint(2, "remoteio %d: %s\n", pid, file);
	memset(buf, 0, nb);
	if(strcmp(file, "proc") == 0)
		tag = Tproc;
	else if(strcmp(file, "status") == 0)
		tag = Tstatus;
	else if(strcmp(file, "note") == 0)
		tag = Trnote;
	else {
		werrstr("invalid remoteio: %s", file);
		return -1;
	}
	memset(dbg, 0, sizeof(dbg));
	dbg[0] = tag;
	dbg[1] = pid>>24;
	dbg[2] = pid>>16;
	dbg[3] = pid>>8;
	dbg[4] = pid;
	if(rproto(remfd, dbg, sizeof(dbg)) < 0)
		return -1;
	if(nb > sizeof(dbg)-1)
		nb = sizeof(dbg)-1;
	memmove(buf, dbg+1, nb);
	return strlen(buf);
}

int
remget(struct segment *s, ulong addr, long off, char *buf, int size)
{
	int n, t;
	char dbg[RDBMSGLEN];

	if (protodebug)
		fprint(2, "remget addr %#lux off %#lux\n", addr, off);
	for (t = 0; t < size; t += n) {
		n = size;
		if(n > 9)
			n = 9;
		memset(dbg, 0, sizeof(dbg));
		dbg[0] = Tmget;
		dbg[1] = off>>24;
		dbg[2] = off>>16;
		dbg[3] = off>>8;
		dbg[4] = off;
		dbg[5] = n;
		if(rproto(s->fd, dbg, sizeof(dbg)) < 0) {
			werrstr("can't read address %#lux: %r", addr);
			return -1;
		}
		memmove(buf, dbg+1, n);
		buf += n;
	}
	return t;
}

int
remput(struct segment *s, ulong addr, long off, char *buf, int size)
{
	int n, i, t;
	char dbg[RDBMSGLEN];

	if (protodebug)
		fprint(2, "remput addr %#lux off %#lux\n", addr, off);
	for (t = 0; t < size; t += n) {
		n = size;
		if(n > 4)
			n = 4;
		memset(dbg, 0, sizeof(dbg));
		dbg[0] = Tmput;
		dbg[1] = off>>24;
		dbg[2] = off>>16;
		dbg[3] = off>>8;
		dbg[4] = off;
		dbg[5] = n;
		for(i=0; i<n; i++)
			dbg[6+i] = *buf++;
		if(rproto(s->fd, dbg, sizeof(dbg)) < 0) {
			werrstr("can't write address %#lux: %r", addr);
			return -1;
		}
	}
	return t;
}

int
remcondset(char op, ulong val)
{
	char dbg[RDBMSGLEN];

	if (protodebug)
		fprint(2, "remcondset op %c val: %#lux\n", op, val);
	memset(dbg, 0, sizeof(dbg));

	dbg[0] = Tcondbreak;
	dbg[1] = val>>24;
	dbg[2] = val>>16;
	dbg[3] = val>>8;
	dbg[4] = val;
	dbg[5] = op;
	if(rproto(remfd, dbg, sizeof(dbg)) < 0) {
		werrstr("can't set condbreak: %c %#lux: %r", op, val);
		return -1;
	}
	return 0;
}

int
remcondstartstop(int pid)
{
	char dbg[RDBMSGLEN];

	if (protodebug) 
		fprint(2, "remcondstartstop pid %d\n", pid);
	memset(dbg, 0, sizeof(dbg));

	dbg[0] = Tstartstop;
	dbg[1] = pid>>24;
	dbg[2] = pid>>16;
	dbg[3] = pid>>8;
	dbg[4] = pid;

	if(rproto(remfd, dbg, sizeof(dbg)) < 0) {
		werrstr("can't send Tstartstop");
		return -1;
	}

	return dbg[1];
}

static int
rproto(int fd, char *buf, int nb)
{
	int tag;

	if (protodebug) {
		int i;
		print("rproto remote write fd %d bytes: %d\n", fd, nb);
		for (i=0; i < nb; i++) {
			print(" %2.2ux", buf[i]&0xFF);
		}
		print("\n");
	}
	tag = buf[0];
	if(remote_write(fd, buf, nb) != nb ||
	    myreadn(fd, buf, nb) != nb){	/* could set alarm */
		werrstr("remote i/o: %r");
		return -1;
	}
	if(buf[0] == Rerr){
		buf[nb-1] = 0;
		werrstr("remote err: %s", buf+1);
		return -1;
	}
	if(buf[0] != tag+1) {
		werrstr("remote proto err: %.2ux", buf[0]&0xff);
		return -1;
	}
	if(chatty) {
		int i;
		fprint(2, "remote [%d]: ", nb);
		for(i=0; i<nb; i++)
			fprint(2, " %.2ux", buf[i]&0xff);
		fprint(2, "\n");
	}
	return nb;
}

/*
 * this should probably be in lib9 as readn
 */
static long
myreadn(int f, void *av, long n)
{
	char *a;
	long m, t;

	if (protodebug) {
		print("remote read fd %d bytes: %ld", f, n);
	}
	a = av;
	t = 0;
	while(t < n){
		m = remote_read(f, a+t, n-t);
		if(m < 0){
			if(t == 0)
				return m;
			break;
		}
		if (protodebug) {
			print(" rtn: %ld\n", m);
			if (m) {
				int i;
		
				for (i=0; i < m; i++)
					print(" %2.2ux", a[i+t]&0xFF);
				print("\n");
			}
		}
		t += m;
	}
	return t;
}
