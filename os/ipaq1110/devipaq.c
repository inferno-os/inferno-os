/*
 *  iPAQ H3650 touch screen and other devices
 *
 * Inferno driver derived from sketchy documentation and
 * information gleaned from linux/char/h3650_ts.c
 * by Charles Flynn.
 *
 * Copyright © 2000,2001 Vita Nuova Holdings Limited.  All rights reserved.
 */
#include	"u.h"
#include	"../port/lib.h"
#include	"mem.h"
#include	"dat.h"
#include	"fns.h"
#include	"io.h"
#include	"../port/error.h"

#include "keyboard.h"
#include <kernel.h>

#include <draw.h>
#include <memdraw.h>
#include "screen.h"

#define	DEBUG	0

/*
 * packet format
 *
 * SOF (0x02)
 * (id<<4) | len	byte length
 * data[len] bytes
 * chk	checksum mod 256 excluding SOF
 */

enum {
	Csof = 0x02,
	Ceof = 0x03,
	Hdrlen = 3,

	/* opcodes */

	Oversion = 0,
	Okeys = 2,
	Otouch = 3,
	Ordeeprom = 4,
	Owreeprom = 5,
	Othermal = 6,
	Oled = 8,
	Obattery = 9,
	Ospiread = 11,
	Ospiwrite = 12,
	Obacklight = 13,
	Oextstatus = 0xA1,
 };

enum {
	Powerbit = 0,	/* GPIO bit for power on/off key */
};

enum{
	Qdir,
	Qctl,
	Qtouchctl,
	Qbattery,
	Qversion,
};

static
Dirtab ipaqtab[]={
	".",	{Qdir, 0, QTDIR},	0,	0555,
	"ipaqctl",		{Qctl},		0,	0600,
	"battery",		{Qbattery},	0,	0444,
	"version",		{Qversion},	0,	0444,
	"touchctl",	{Qtouchctl},	0,	0644,
};

static struct {
	QLock;
	Chan*	c;

	Lock	rl;	/* protect cmd, reply */
	int	cmd;
	Block*	reply;
	Rendez	r;
} atmel;

/* to and from fixed point */
#define	FX(a,b)	(((a)<<16)/(b))
#define	XF(v)		((v)>>16)

static struct {
	Lock;
	int	rate;
	int	m[2][3];	/* transformation matrix */
	Point	avg;
	Point	diff;
	Point	pts[4];
	int	n;	/* number of points in pts */
	int	p;	/* current index in pts */
	int	down;
	int	nout;
} touch = {
	{0},
	.m {{-FX(1,3), 0, FX(346,1)},{0, -FX(1,4), FX(256, 1)}},
};

/*
 * map rocker positions to same codes as plan 9
 */
static	Rune	rockermap[2][4] ={
	{Right, Down, Up, Left},	/* landscape */
	{Up, Right, Left, Down},	/* portrait */
};

static	Rendez	powerevent;

static	void	cmdack(int, void*, int);
static	int	cmdio(int, void*, int, void*, int);
static	void	ipaqreadproc(void*);
static	void	powerwaitproc(void*);
static	Block*	rdevent(Block**);
static	long	touchctl(char*, long);
static	void	touched(Block*, int);
static	int	wrcmd(int, void*, int, void*, int);
static	char*	acstatus(int);
static	char*	batstatus(int);
static	void	powerintr(Ureg*, void*);

static void
ipaqreset(void)
{
	intrenable(Powerbit, powerintr, nil, BusGPIOfalling, "power off");
}

static void
ipaqinit(void)
{
	kproc("powerwait", powerwaitproc, nil, 0);
}

static Chan*
ipaqattach(char* spec)
{
	int fd;

	qlock(&atmel);
	if(waserror()){
		qunlock(&atmel);
		nexterror();
	}
	if(atmel.c == nil){
		fd = kopen("#t/eia1ctl", ORDWR);
		if(fd < 0)
			error(up->env->errstr);
		kwrite(fd, "b115200", 7);	/* it's already pn, l8 */
		kclose(fd);
		fd = kopen("#t/eia1", ORDWR);
		if(fd < 0)
			error(up->env->errstr);
		atmel.c = fdtochan(up->env->fgrp, fd, ORDWR, 0, 1);
		kclose(fd);
		atmel.cmd = -1;
		kproc("ipaqread", ipaqreadproc, nil, 0);
	}
	poperror();
	qunlock(&atmel);
	return devattach('T', spec);
}

static Walkqid*
ipaqwalk(Chan *c, Chan *nc, char **name, int nname)
{
	return devwalk(c, nc, name, nname, ipaqtab, nelem(ipaqtab), devgen);
}

static int
ipaqstat(Chan* c, uchar *db, int n)
{
	return devstat(c, db, n, ipaqtab, nelem(ipaqtab), devgen);
}

static Chan*
ipaqopen(Chan* c, int omode)
{
	return devopen(c, omode, ipaqtab, nelem(ipaqtab), devgen);
}

static void
ipaqclose(Chan*)
{
}

static long
ipaqread(Chan* c, void* a, long n, vlong offset)
{
	char *tmp, buf[64];
	uchar reply[12];
	int v, p, l;

	switch((ulong)c->qid.path){
	case Qdir:
		return devdirread(c, a, n, ipaqtab, nelem(ipaqtab), devgen);
	case Qtouchctl:
		tmp = malloc(READSTR);
		if(waserror()){
			free(tmp);
			nexterror();
		}
		snprint(tmp, READSTR, "s%d\nr%d\nR%d\nX %d %d %d\nY %d %d %d\n",
			1000, 0, 1,
			touch.m[0][0], touch.m[0][1], touch.m[0][2],
			touch.m[1][0], touch.m[1][1], touch.m[1][2]);
		n = readstr(offset, a, n, tmp);
		poperror();
		free(tmp);
		break;
	case Qbattery:
		cmdio(Obattery, reply, 0, reply, sizeof(reply));
		tmp = malloc(READSTR);
		if(waserror()){
			free(tmp);
			nexterror();
		}
		v = (reply[4]<<8)|reply[3];
		p = 425*v/1000 - 298;
		snprint(tmp, READSTR, "voltage: %d %dmV %d%% %d\nac: %s\nstatus: %d %s\nchem: %d\n",
			v, 1000*v/228, p, 300*p/100, acstatus(reply[1]), reply[5], batstatus(reply[5]), reply[2]);
		n = readstr(offset, a, n, tmp);
		poperror();
		free(tmp);
		break;
	case Qversion:
		l = cmdio(Oversion, reply, 0, reply, sizeof(reply));
		if(l > 4){
			l--;
			memmove(buf, reply+1, 4);
			if(l > 8){
				buf[4] = ' ';
				memmove(buf+5, reply+5, 4);	/* pack version */
				sprint(buf+9, " %.2x\n", reply[9]);	/* ``boot type'' */
			}else{
				buf[4] = '\n';
				buf[5] = 0;
			}
			return readstr(offset, a, n, buf);
		}
		n=0;
		break;
	default:
		n=0;
		break;
	}
	return n;
}

static long
ipaqwrite(Chan* c, void* a, long n, vlong)
{
	char cmd[64], op[32], *fields[6];
	int nf;

	switch((ulong)c->qid.path){
	case Qctl:
		if(n >= sizeof(cmd)-1)
			n = sizeof(cmd)-1;
		memmove(cmd, a, n);
		cmd[n] = 0;
		nf = getfields(cmd, fields, nelem(fields), 1, " \t\n");
		if(nf <= 0)
			error(Ebadarg);
		if(nf >= 4 && strcmp(fields[0], "light") == 0){
			op[0] = atoi(fields[1]);	/* mode */
			op[1] = atoi(fields[2]);	/* power */
			op[2] = atoi(fields[3]);	/* brightness */
			cmdack(Obacklight, op, 3);
		}else if(nf >= 5 && strcmp(fields[0], "led") == 0){
			op[0] = atoi(fields[1]);
			op[1] = atoi(fields[2]);
			op[2] = atoi(fields[3]);
			op[3] = atoi(fields[4]);
			cmdack(Oled, op, 4);
		}else if(strcmp(fields[0], "suspend") == 0){
			/* let the kproc do it */
			wakeup(&powerevent);
		}else
			error(Ebadarg);
		break;
	case Qtouchctl:
		return touchctl(a, n);
	default:
		error(Ebadusefd);
	}
	return n;
}

static void
powerintr(Ureg*, void*)
{
	wakeup(&powerevent);
}

static void
cmdack(int id, void *a, int n)
{
	uchar reply[16];

	cmdio(id, a, n, reply, sizeof(reply));
}

static int
cmdio(int id, void *a, int n, void *reply, int lim)
{
	qlock(&atmel);
	if(waserror()){
		qunlock(&atmel);
		nexterror();
	}
	n = wrcmd(id, a, n, reply, lim);
	poperror();
	qunlock(&atmel);
	return n;
}

static int
havereply(void*)
{
	return atmel.reply != nil;
}

static int
wrcmd(int id, void *a, int n, void *b, int lim)
{
	uchar buf[32];
	int i, sum;
	Block *e;

	if(n >= 16)
		error(Eio);
	lock(&atmel.rl);
	atmel.cmd = id;
	unlock(&atmel.rl);
	buf[0] = Csof;
	buf[1] = (id<<4) | (n&0xF);
	if(n)
		memmove(buf+2, a, n);
	sum = 0;
	for(i=1; i<n+2; i++)
		sum += buf[i];
	buf[i++] = sum;
	if(0){
		iprint("msg=");
		for(sum=0; sum<i; sum++)
			iprint(" %2.2ux", buf[sum]);
		iprint("\n");
	}
	if(kchanio(atmel.c, buf, i, OWRITE) != i)
		error(Eio);
	tsleep(&atmel.r, havereply, nil, 500);
	lock(&atmel.rl);
	e = atmel.reply;
	atmel.reply = nil;
	atmel.cmd = -1;
	unlock(&atmel.rl);
	if(e == nil){
		print("ipaq: no reply\n");
		error(Eio);
	}
	if(waserror()){
		freeb(e);
		nexterror();
	}
	if(e->rp[0] != id){
		print("ipaq: rdreply: mismatched reply %d :: %d\n", id, e->rp[0]);
		error(Eio);
	}
	n = BLEN(e);
	if(n < lim)
		lim = n;
	memmove(b, e->rp, lim);
	poperror();
	freeb(e);
	return lim;
}

static void
ipaqreadproc(void*)
{
	Block *e, *b, *partial;
	int c, mousemod;

	while(waserror())
		print("ipaqread: %r\n");
	partial = nil;
	mousemod = 0;
	for(;;){
		e = rdevent(&partial);
		if(e == nil){
			print("ipaqread: rdevent: %r\n");
			continue;
		}
		switch(e->rp[0]){
		case Otouch:
			touched(e, mousemod);
			freeb(e);
			break;
		case Okeys:
			//print("key %2.2ux\n", e->rp[1]);
			c = e->rp[1] & 0xF;
			if(c >= 6 && c < 10){	/* rocker */
				if((e->rp[1] & 0x80) == 0){
					kbdrepeat(0);
					kbdputc(kbdq, rockermap[conf.portrait&1][c-6]);
				}else
					kbdrepeat(0);
			}else{
				/* TO DO: change tkmouse and mousetrack to allow extra buttons */
				if(--c == 0)
					c = 5;
				if(e->rp[1] & 0x80)
					mousemod &= ~(1<<c);
				else
					mousemod |= 1<<c;
			}
			freeb(e);
			break;
		default:
			lock(&atmel.rl);
			if(atmel.cmd == e->rp[0]){
				b = atmel.reply;
				atmel.reply = e;
				unlock(&atmel.rl);
				wakeup(&atmel.r);
				if(b != nil)
					freeb(b);
			}else{
				unlock(&atmel.rl);
				print("ipaqread: discard op %d\n", e->rp[0]);
				freeb(e);
			}
		}
	}
}

static Block *
rdevent(Block **bp)
{
	Block *b, *e;
	int s, c, len, csum;
	enum {Ssof=16, Sid, Ssum};

	s = Ssof;
	csum = 0;
	len = 0;
	e = nil;
	if(waserror()){
		if(e != nil)
			freeb(e);
		nexterror();
	}
	for(;;){
		b = *bp;
		*bp = nil;
		if(b == nil){
			b = devtab[atmel.c->type]->bread(atmel.c, 128, 0);
			if(b == nil)
				error(Eio);
			if(DEBUG)
				iprint("r: %ld\n", BLEN(b));
		}
		while(b->rp < b->wp){
			c = *b->rp++;
			switch(s){
			case Ssof:
				if(c == Csof)
					s = Sid;
				else if(1)
					iprint("!sof: %2.2ux %d\n", c, s);
				break;
			case Sid:
				csum = c;
				len = c & 0xF;
				e = allocb(len+1);
				if(e == nil)
					error(Eio);
				*e->wp++ = c>>4;	/* id */
				if(len)
					s = 0;
				else
					s = Ssum;
				break;
			case Ssum:
				csum &= 0xFF;
				if(c != csum){
					iprint("cksum: %2.2ux != %2.2ux\n", c, csum);
					s = Ssof;	/* try to resynchronise */
					if(e != nil){
						freeb(e);
						e = nil;
					}
					break;
				}
				if(b->rp < b->wp)
					*bp = b;
				else
					freeb(b);
				if(DEBUG){
					int i;
					iprint("event: [%ld]", BLEN(e));
					for(i=0; i<BLEN(e);i++)
						iprint(" %2.2ux", e->rp[i]);
					iprint("\n");
				}
				poperror();
				return e;
			default:
				csum += c;
				*e->wp++ = c;
				if(++s >= len)
					s = Ssum;
				break;
			}
		}
		freeb(b);
	}
	return 0;	/* not reached */
}

static char *
acstatus(int x)
{
	switch(x){
	case 0:	return "offline";
	case 1:	return "online";
	case 2:	return "backup";
	}
	return "unknown";
}

static char *
batstatus(int x)
{
	if(x & 0x40)
		return "charging";	/* not in linux but seems to be on mine */
	switch(x){
	case 0:		return "ok";
	case 1:		return "high";
	case 2:		return "low";
	case 4:		return "critical";
	case 8:		return "charging";
	case 0x80:	return "none";
	}
	return "unknown";
}

static int
ptmap(int *m, int x, int y)
{
	return XF(m[0]*x + m[1]*y + m[2]);
}

static void
touched(Block *b, int buttons)
{
	int rx, ry, x, y, dx, dy, n;
	Point op, *lp, cur;

	if(BLEN(b) == 5){
		/* id Xhi Xlo Yhi Ylo */
		if(touch.down < 0){
			touch.down = 0;
			return;
		}
		rx = (b->rp[1]<<8)|b->rp[2];
		ry = (b->rp[3]<<8)|b->rp[4];
		if(conf.portrait){
			dx = rx; rx = ry; ry = dx;
		}
		if(touch.down == 0){
			touch.nout = 0;
			touch.p = 1;
			touch.n = 1;
			touch.avg = Pt(rx, ry);
			touch.pts[0] = touch.avg;
			touch.down = 1;
			return;
		}
		n = touch.p-1;
		if(n < 0)
			n = nelem(touch.pts)-1;
		lp = &touch.pts[n];	/* last point */
		if(touch.n > 0 && (rx-lp->x)*(ry-lp->y) > 50*50){	/* far out */
			if(++touch.nout > 3){
				touch.down = 0;
				touch.n = 0;
			}
			return;
		}
		op = touch.pts[touch.p];
		touch.pts[touch.p] = Pt(rx, ry);
		touch.p = (touch.p+1) % nelem(touch.pts);
		touch.avg.x += rx;
		touch.avg.y += ry;
		if(touch.n < nelem(touch.pts)){
			touch.n++;
			return;
		}
		touch.avg.x -= op.x;
		touch.avg.y -= op.y;
		cur = mousexy();
		rx = touch.avg.x/touch.n;
		ry = touch.avg.y/touch.n;
		x = ptmap(touch.m[0], rx, ry);
		dx = x-cur.x;
		y = ptmap(touch.m[1], rx, ry);
		dy = y-cur.y;
		if(dx*dx + dy*dy <= 2){
			dx = 0;
			dy = 0;
		}
		if(buttons == 0)
			buttons = 1<<0;	/* by default, stylus down implies button 1 */
		mousetrack(buttons&0x1f, dx, dy, 1);	/* TO DO: allow more than 3 buttons */
		/* TO DO: swcursupdate(oldx, oldy, x, y); */
		touch.down = 1;
	}else{
		if(touch.down){
			mousetrack(0, 0, 0, 1);	/* stylus up */
			touch.down = 0;
		}else
			touch.down = -1;
		touch.n = 0;
		touch.p = 0;
		touch.avg.x = 0;
		touch.avg.y = 0;
	}
}

/*
 * touchctl commands:
 *	X a b c	- set X transformation
 *	Y d e f	- set Y transformation
 *	s<delay>		- set sample delay in millisec per sample
 *	r<delay>		- set read delay in microsec
 *	R<l2nr>			- set log2 of number of readings to average
 */
static long	 
touchctl(char* a, long n)
{
	char buf[64];
	char *cp;
	int n0 = n;
	int bn;
	char *field[8];
	int nf, cmd, pn, m[2][3];

	while(n) {
		bn = (cp = memchr(a, '\n', n))!=nil ? cp-a+1 : n;
		n -= bn;
		cp = a;
		a += bn;
		bn = bn > sizeof(buf)-1 ? sizeof(buf)-1 : bn;
		memmove(buf, cp, bn);
		buf[bn] = '\0';
		nf = getfields(buf, field, nelem(field), 1, " \t\n");
		if(nf <= 0)
			continue;
		if(strcmp(field[0], "calibrate") == 0){
			if(nf == 1){
				lock(&touch);
				memset(touch.m, 0, sizeof(touch.m));
				touch.m[0][0] = FX(1,1);
				touch.m[1][1] = FX(1,1);
				unlock(&touch);
			}else if(nf >= 5){
				memset(m, 0, sizeof(m));
				m[0][0] = strtol(field[1], 0, 0);
				m[1][1] = strtol(field[2], 0, 0);
				m[0][2] = strtol(field[3], 0, 0);
				m[1][2] = strtol(field[4], 0, 0);
				if(nf > 5)
					m[0][1] = strtol(field[5], 0, 0);
				if(nf > 6)
					m[1][0] = strtol(field[6], 0, 0);
				lock(&touch);
				memmove(touch.m, m, sizeof(touch.m[0]));
				unlock(&touch);
			}else
				error(Ebadarg);
			continue;
		}
		cmd = *field[0]++;
		pn = *field[0] == 0;
		switch(cmd) {
		case 's':
			pn = strtol(field[pn], 0, 0);
			if(pn <= 0)
				error(Ebadarg);
			touch.rate = pn;
			break;
		case 'r':
			/* touch read delay */
			break;
		case 'X':
		case 'Y':
			if(nf < pn+2)
				error(Ebadarg);
			m[0][0] = strtol(field[pn], 0, 0);
			m[0][1] = strtol(field[pn+1], 0, 0);
			m[0][2] = strtol(field[pn+2], 0, 0);
			lock(&touch);
			memmove(touch.m[cmd=='Y'], m[0], sizeof(touch.m[0]));
			unlock(&touch);
			break;
		default:
			error(Ebadarg);
		}
	}
	return n0-n;
}

/*
 * this might belong elsewhere
 */
static int
powerwait(void*)
{
	return (GPIOREG->gplr & GPIO_PWR_ON_i) == 0;
}

static void
powerwaitproc(void*)
{
	for(;;){
		sleep(&powerevent, powerwait, nil);
		do{
			tsleep(&up->sleep, return0, nil, 50);
		}while((GPIOREG->gplr & GPIO_PWR_ON_i) == 0);
		powersuspend();
	}
}

Dev ipaqdevtab = {
	'T',
	"ipaq",

	ipaqreset,
	ipaqinit,
	devshutdown,
	ipaqattach,
	ipaqwalk,
	ipaqstat,
	ipaqopen,
	devcreate,
	ipaqclose,
	ipaqread,
	devbread,
	ipaqwrite,
	devbwrite,
	devremove,
	devwstat,
};
