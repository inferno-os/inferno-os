#include "u.h"
#include "../port/lib.h"
#include "mem.h"
#include "dat.h"
#include "fns.h"
#include "ureg.h"
#include "../port/error.h"
#include	"rdbg.h"

#include	<kernel.h>
#include	<interp.h>

/*
 *	The following should be set in the config file to override
 *	the defaults.
 */
int	dbgstart;
char	*dbgdata;
char	*dbgctl;
char	*dbgctlstart;
char	*dbgctlstop;
char	*dbgctlflush;

//
// Error messages sent to the remote debugger
//
static	uchar	Ereset[9] = { 'r', 'e', 's', 'e', 't' };
static	uchar	Ecount[9] = { 'c', 'o', 'u', 'n', 't' };
static	uchar	Eunk[9] = { 'u', 'n', 'k' };
static	uchar	Einval[9] = { 'i', 'n', 'v', 'a', 'l' };
static	uchar	Ebadpid[9] = {'p', 'i', 'd'};
static	uchar	Eunsup[9] = { 'u', 'n', 's', 'u', 'p' };
static	uchar	Enotstop[9] = { 'n', 'o', 't', 's', 't', 'o', 'p' };
 
//
// Error messages raised via call to error()
//
static	char	Erunning[] = "Not allowed while debugger is running";
static	char	Enumarg[] = "Not enough args";
static	char	Ebadcmd[] = "Unknown command";

static	int	PROCREG;
static	struct {
	Rendez;
	Bkpt *b;
} brk;

static	Queue	*logq;

int	dbgchat = 0;

typedef struct Debugger Debugger;
struct Debugger {
	RWlock;
	int	running;
	char	data[PRINTSIZE];
	char	ctl[PRINTSIZE];
	char	ctlstart[PRINTSIZE];
	char	ctlstop[PRINTSIZE];
	char	ctlflush[PRINTSIZE];
};

static Debugger debugger = {
	.data=		"#t/eia0",
	.ctl=		"#t/eia0ctl",
	.ctlstart=	"b19200",
	.ctlstop=	"h",
	.ctlflush=	"f",
};

enum {
	BkptStackSize=	256,
};

typedef struct SkipArg SkipArg;
struct SkipArg
{
	Bkpt *b;
	Proc *p;
};

Bkpt	*breakpoints;
void	freecondlist(BkptCond *l);

static int
getbreaks(ulong addr, Bkpt **a, int nb)
{
	Bkpt *b;
	int n;

	n = 0;
	for(b = breakpoints; b != nil; b = b->next){
		if(b->addr == addr){
			a[n++] = b;
			if(n == nb)
				break;
		}
	}
	return n;
}

Bkpt*
newbreak(int id, ulong addr, BkptCond *conds, void(*handler)(Bkpt*), void *aux)
{
	Bkpt *b;

	b = malloc(sizeof(*b));
	if(b == nil)
		error(Enomem);

	b->id = id;
	b->conditions = conds;
	b->addr = addr;
	b->handler = handler;
	b->aux = aux;
	b->next = nil;

	return b;
}

void
freebreak(Bkpt *b)
{
	freecondlist(b->conditions);
	free(b);
}

BkptCond*
newcondition(uchar cmd, ulong val)
{
	BkptCond *c;

	c = mallocz(sizeof(*c), 0);
	if(c == nil)
		error(Enomem);

	c->op = cmd;
	c->val = val;
	c->next = nil;

	return c;
}

void
freecondlist(BkptCond *l)
{
	BkptCond *next;

	while(l != nil){
		next = l->next;
		free(l);
		l = next;
	}
}


void
breakset(Bkpt *b)
{
	Bkpt *e[1];

	if(getbreaks(b->addr, e, 1) != 0){
		b->instr = e[0]->instr;
	} else {
		b->instr = machinstr(b->addr);
		machbreakset(b->addr);
	}

	b->next = breakpoints;
	breakpoints = b;
}

void
breakrestore(Bkpt *b)
{
	b->next = breakpoints;
	breakpoints = b;
	machbreakset(b->addr);
}

Bkpt*
breakclear(int id)
{
	Bkpt *b, *e, *p;

	for(b=breakpoints, p=nil; b != nil && b->id != id; p = b, b = b->next)
		;

	if(b != nil){
		if(p == nil)
			breakpoints = b->next;
		else
			p->next = b->next;

		if(getbreaks(b->addr, &e, 1) == 0)
			machbreakclear(b->addr, b->instr);
	}

	return b;
}

void
breaknotify(Bkpt *b, Proc *p)
{
	p->dbgstop = 1;		// stop running this process.
	b->handler(b);
}

int
breakmatch(BkptCond *cond, Ureg *ur, Proc *p)
{
	ulong a, b;
	int pos;
	ulong s[BkptStackSize];

	memset(s, 0, sizeof(s));
	pos = 0;

	for(;cond != nil; cond = cond->next){
		switch(cond->op){
		default:
			panic("breakmatch: unknown operator %c", cond->op);
			break;
		case 'k':
			if(p == nil || p->pid != cond->val)
				return 0;
			s[pos++] = 1;
			break;
		case 'b':
			if(ur->pc != cond->val)
				return 0;
			s[pos++] = 1;
			break;
		case 'p': s[pos++] = cond->val; break;
		case '*': a = *(ulong*)s[--pos]; s[pos++] = a; break;
		case '&': a = s[--pos]; b = s[--pos]; s[pos++] = a & b; break;
		case '=': a = s[--pos]; b = s[--pos]; s[pos++] = a == b; break;
		case '!': a = s[--pos]; b = s[--pos]; s[pos++] = a != b; break;
		case 'a': a = s[--pos]; b = s[--pos]; s[pos++] = a && b; break;
		case 'o': a = s[--pos]; b = s[--pos]; s[pos++] = a || b; break;
		}
	}

	if(pos && s[pos-1])
		return 1;
	return 0;
}

void
breakinit(void)
{
	machbreakinit();
}

static void
dbglog(char *fmt, ...)
{
	int n;
	va_list arg;
	char buf[PRINTSIZE];

	va_start(arg, fmt);
	n = vseprint(buf, buf+sizeof(buf), fmt, arg) - buf;
	va_end(arg);
	qwrite(logq, buf, n);
}

static int
get(int dbgfd, uchar *b)
{
	int i;
	uchar c;

	if(kread(dbgfd, &c, 1) < 0)
		error(Eio);
	for(i=0; i<9; i++){
		if(kread(dbgfd, b++, 1) < 0)
			error(Eio);
	}
	return c;
}

static void
mesg(int dbgfd, int m, uchar *buf)
{
	int i;
	uchar c;

	c = m;
	if(kwrite(dbgfd, &c, 1) < 0)
		error(Eio);
	for(i=0; i<9; i++){
		if(kwrite(dbgfd, buf+i, 1) < 0)
			error(Eio);
	}
}

static ulong
dbglong(uchar *s)
{
	return (s[0]<<24)|(s[1]<<16)|(s[2]<<8)|(s[3]<<0);
}

static Proc *
dbgproc(ulong pid, int dbgok)
{
	int i;
	Proc *p;

	if(!dbgok && pid == up->pid)
		return 0;
	p = proctab(0);
	for(i = 0; i < conf.nproc; i++){
		if(p->pid == pid)
			return p;
		p++;
	}
	return 0;
}

static void*
addr(uchar *s)
{
	ulong a;
	Proc *p;
	static Ureg ureg;

	a = ((s[0]<<24)|(s[1]<<16)|(s[2]<<8)|(s[3]<<0));
	if(a < sizeof(Ureg)){
		p = dbgproc(PROCREG, 0);
		if(p == 0){
			dbglog("dbg: invalid pid\n");
			return 0;
		}
		if(p->dbgreg){
			/* in trap(), registers are all on stack */
			memmove(&ureg, p->dbgreg, sizeof(ureg));
		}
		else {
			/* not in trap, only pc and sp are available */
			memset(&ureg, 0, sizeof(ureg));
			ureg.sp = p->sched.sp;
			ureg.pc = p->sched.pc;
		}
		return (uchar*)&ureg+a;
	}
	return (void*)a;
}


static void
dumpcmd(uchar cmd, uchar *min)
{
	char *s;
	int n;

	switch(cmd){
	case Terr:		s = "Terr"; break;
	case Tmget:		s = "Tmget"; break;
	case Tmput:		s = "Tmput"; break;
	case Tspid:		s = "Tspid"; break;
	case Tproc:		s = "Tproc"; break;
	case Tstatus:		s = "Tstatus"; break;
	case Trnote:		s = "Trnote"; break;
	case Tstartstop:	s = "Tstartstop"; break;
	case Twaitstop:		s = "Twaitstop"; break;
	case Tstart:		s = "Tstart"; break;
	case Tstop:		s = "Tstop"; break;
	case Tkill:		s = "Tkill"; break;
	case Tcondbreak:	s = "Tcondbreak"; break;
	default:		s = "<Unknown>"; break;
	}
	dbglog("%s: [%2.2ux]: ", s, cmd);
	for(n = 0; n < 9; n++)
		dbglog("%2.2ux", min[n]);
	dbglog("\n");
}

static int
brkpending(void *a)
{
	Proc *p;

	p = a;
	if(brk.b != nil) return 1;

	p->dbgstop = 0;			/* atomic */
	if(p->state == Stopped)
		ready(p);

	return 0;
}

static void
gotbreak(Bkpt *b)
{
	Bkpt *cur, *prev;

	b->link = nil;

	for(prev = nil, cur = brk.b; cur != nil; prev = cur, cur = cur->link)
		;
	if(prev == nil)
		brk.b = b;
	else
		prev->link = b;

	wakeup(&brk);
}

static int
startstop(Proc *p)
{
	int id;
	int s;
	Bkpt *b;

	sleep(&brk, brkpending, p);

	s = splhi();
	b = brk.b;
	brk.b = b->link;
	splx(s);

	id = b->id;

	return id;
}

static int
condbreak(char cmd, ulong val)
{
	BkptCond *c;
	static BkptCond *head = nil;
	static BkptCond *tail = nil;
	static Proc *p = nil;
	static int id = -1;
	int s;

	if(waserror()){
		dbglog(up->env->errstr);
		freecondlist(head);
		head = tail = nil;
		p = nil;
		id = -1;
		return 0;
	}

	switch(cmd){
	case 'b': case 'p':
	case '*': case '&': case '=':
	case '!': case 'a': case 'o':
		break;
	case 'n':
		id = val;
		poperror();
		return 1;
	case 'k':
		p = dbgproc(val, 0);
		if(p == nil)
			error("k: unknown pid");
		break;
	case 'd': {
		Bkpt *b;

		s = splhi();
		b = breakclear(val);
		if(b != nil){
			Bkpt *cur, *prev;

			prev = nil;
			cur = brk.b;
			while(cur != nil){
				if(cur->id == b->id){
					if(prev == nil)
						brk.b = cur->link;
					else
						prev->link = cur->link;
					break;
				}
				cur = cur->link;
			}
			freebreak(b);
		}
		splx(s);
		poperror();
		return 1;
		}
	default:
		dbglog("condbreak(): unknown op %c %lux\n", cmd, val);
		error("unknown op");
	}

	c = newcondition(cmd, val);

	 //
	 // the 'b' command comes last, (so we know we have reached the end
	 // of the condition list), but it should be the first thing
	 // checked, so put it at the head.
	 //
	if(cmd == 'b'){
		if(p == nil) error("no pid");
		if(id == -1) error("no id");

		c->next = head;
		s = splhi();
		breakset(newbreak(id, val, c, gotbreak, p));
		splx(s);
		head = tail = nil;
		p = nil;
		id = -1;
	} else if(tail != nil){
		tail->next = c;
		tail = c;
	} else
		head = tail = c;

	poperror();

	return 1;
}

static void
dbg(void*)
{
	Proc *p;
	ulong val;
	int n, cfd, dfd;
	uchar cmd, *a, min[RDBMSGLEN-1], mout[RDBMSGLEN-1];

	rlock(&debugger);

	setpri(PriRealtime);

	closefgrp(up->env->fgrp);
	up->env->fgrp = newfgrp(nil);

	if(waserror()){
		dbglog("dbg: quits: %s\n", up->env->errstr);
		runlock(&debugger);
		wlock(&debugger);
		debugger.running = 0;
		wunlock(&debugger);
		pexit("", 0);
	}

	dfd = kopen(debugger.data, ORDWR);
	if(dfd < 0){
		dbglog("dbg: can't open %s: %s\n",debugger.data, up->env->errstr);
		error(Eio);
	}
	if(waserror()){
		kclose(dfd);
		nexterror();
	}

	if(debugger.ctl[0] != 0){
		cfd = kopen(debugger.ctl, ORDWR);
		if(cfd < 0){
			dbglog("dbg: can't open %s: %s\n", debugger.ctl, up->env->errstr);
			error(Eio);
		}
		if(kwrite(cfd, debugger.ctlstart, strlen(debugger.ctlstart)) < 0){
			dbglog("dbg: write %s: %s\n", debugger.ctl, up->env->errstr);
			error(Eio);
		}
	}else
		cfd = -1;
	if(waserror()){
		if(cfd != -1){
			kwrite(cfd, debugger.ctlflush, strlen(debugger.ctlflush));
			kclose(cfd);
		}
		nexterror();
	}

	mesg(dfd, Rerr, Ereset);

	for(;;){
		memset(mout, 0, sizeof(mout));
		cmd = get(dfd, min);
		if(dbgchat)
			dumpcmd(cmd, min);
		switch(cmd){
		case Tmget:
			n = min[4];
			if(n > 9){
				mesg(dfd, Rerr, Ecount);
				break;
			}
			a = addr(min+0);
			if(!isvalid_va(a)){
				mesg(dfd, Rerr, Einval);
				break;
			}
			memmove(mout, a, n);
			mesg(dfd, Rmget, mout);
			break;
		case Tmput:
			n = min[4];
			if(n > 4){
				mesg(dfd, Rerr, Ecount);
				break;
			}
			a = addr(min+0);
			if(!isvalid_va(a)){
				mesg(dfd, Rerr, Einval);
				break;
			}
			memmove(a, min+5, n);
			segflush(a, n);
			mesg(dfd, Rmput, mout);
			break;
		case Tproc:
			p = dbgproc(dbglong(min+0), 0);
			if(p == 0){
				mesg(dfd, Rerr, Ebadpid);
				break;
			}
			PROCREG = p->pid;	/* try this instead of Tspid */
			sprint((char*)mout, "%8.8lux", p);
			mesg(dfd, Rproc, mout);
			break;
		case Tstatus:
			p = dbgproc(dbglong(min+0), 1);
			if(p == 0){
				mesg(dfd, Rerr, Ebadpid);
				break;
			}
			if(p->state > Rendezvous || p->state < Dead)
				sprint((char*)mout, "%8.8ux", p->state);
			else if(p->dbgstop == 1)
				strncpy((char*)mout, statename[Stopped], sizeof(mout));
			else
				strncpy((char*)mout, statename[p->state], sizeof(mout));
			mesg(dfd, Rstatus, mout);
			break;
		case Trnote:
			p = dbgproc(dbglong(min+0), 0);
			if(p == 0){
				mesg(dfd, Rerr, Ebadpid);
				break;
			}
			mout[0] = 0;	/* should be trap status, if any */
			mesg(dfd, Rrnote, mout);
			break;
		case Tstop:
			p = dbgproc(dbglong(min+0), 0);
			if(p == 0){
				mesg(dfd, Rerr, Ebadpid);
				break;
			}
			p->dbgstop = 1;			/* atomic */
			mout[0] = 0;
			mesg(dfd, Rstop, mout);
			break;
		case Tstart:
			p = dbgproc(dbglong(min+0), 0);
			if(p == 0){
				mesg(dfd, Rerr, Ebadpid);
				break;
			}
			p->dbgstop = 0;			/* atomic */
			if(p->state == Stopped)
				ready(p);
			mout[0] = 0;
			mesg(dfd, Rstart, mout);
			break;
		case Tstartstop:
			p = dbgproc(dbglong(min+0), 0);
			if(p == 0){
				mesg(dfd, Rerr, Ebadpid);
				break;
			}
			if(!p->dbgstop){
				mesg(dfd, Rerr, Enotstop);
				break;
			}
			mout[0] = startstop(p);
			mesg(dfd, Rstartstop, mout);
			break;
		case Tcondbreak:
			val = dbglong(min+0);
			if(!condbreak(min[4], val)){
				mesg(dfd, Rerr, Eunk);
				break;
			}
			mout[0] = 0;
			mesg(dfd, Rcondbreak, mout);
			break;
		default:
			dumpcmd(cmd, min);
			mesg(dfd, Rerr, Eunk);
			break;
		}
	}
}

static void
dbgnote(Proc *p, Ureg *ur)
{
	if(p){
		p->dbgreg = ur;
		PROCREG = p->pid;	/* acid can get the trap info from regs */
	}
}

enum {
	Qdir,
	Qdbgctl,
	Qdbglog,

	DBGrun = 1,
	DBGstop = 2,

	Loglimit = 4096,
};

static Dirtab dbgdir[]=
{
	".",		{Qdir, 0, QTDIR},	0,	0555,
	"dbgctl",	{Qdbgctl},	0,		0660,
	"dbglog",	{Qdbglog},	0,		0440,
};

static void
start_debugger(void)
{
	breakinit();
	dbglog("starting debugger\n");
	debugger.running++;
	kproc("dbg", dbg, 0, KPDUPPG);
}

static void
dbginit(void)
{

	logq = qopen(Loglimit, 0, 0, 0);
	if(logq == nil)
		error(Enomem);
	qnoblock(logq, 1);

	wlock(&debugger);
	if(waserror()){
		wunlock(&debugger);
		qfree(logq);
		logq = nil;
		nexterror();
	}

	if(dbgdata != nil){
		strncpy(debugger.data, dbgdata, sizeof(debugger.data));
		debugger.data[sizeof(debugger.data)-1] = 0;
	}
	if(dbgctl != nil){
		strncpy(debugger.ctl, dbgctl, sizeof(debugger.ctl));
		debugger.ctl[sizeof(debugger.ctl)-1] = 0;
	}
	if(dbgctlstart != nil){
		strncpy(debugger.ctlstart, dbgctlstart, sizeof(debugger.ctlstart));
		debugger.ctlstart[sizeof(debugger.ctlstart)-1] = 0;
	}
	if(dbgctlstop != nil){
		strncpy(debugger.ctlstop, dbgctlstop, sizeof(debugger.ctlstop));
		debugger.ctlstop[sizeof(debugger.ctlstop)-1] = 0;
	}
	if(dbgctlflush != nil){
		strncpy(debugger.ctlflush, dbgctlflush, sizeof(debugger.ctlflush));
		debugger.ctlflush[sizeof(debugger.ctlflush)-1] = 0;
	}
	if(dbgstart)
		start_debugger();

	poperror();
	wunlock(&debugger);
}

static Chan*
dbgattach(char *spec)
{
	return devattach('b', spec);
}

static Walkqid*
dbgwalk(Chan *c, Chan *nc, char **name, int nname)
{
	return devwalk(c, nc, name, nname, dbgdir, nelem(dbgdir), devgen);
}

static int
dbgstat(Chan *c, uchar *dp, int n)
{
	return devstat(c, dp, n, dbgdir, nelem(dbgdir), devgen);
}

static Chan*
dbgopen(Chan *c, int omode)
{
	return devopen(c, omode, dbgdir, nelem(dbgdir), devgen);
}

static long
dbgread(Chan *c, void *buf, long n, vlong offset)
{
	char *ctlstate;

	switch((ulong)c->qid.path){
	case Qdir:
		return devdirread(c, buf, n, dbgdir, nelem(dbgdir), devgen);
	case Qdbgctl:
		rlock(&debugger);
		ctlstate = smprint("%s data %s ctl %s ctlstart %s ctlstop %s ctlflush %s\n",
			debugger.running ? "running" : "stopped",
			debugger.data, debugger.ctl, 
			debugger.ctlstart, debugger.ctlstop, debugger.ctlflush);
		runlock(&debugger);
		if(ctlstate == nil)
			error(Enomem);
		if(waserror()){
			free(ctlstate);
			nexterror();
		}
		n = readstr(offset, buf, n, ctlstate);
		poperror();
		free(ctlstate);
		return n;
	case Qdbglog:
		return qread(logq, buf, n);
	default:
		error(Egreg);
	}
	return -1;		/* never reached */
}

static void
ctl(Cmdbuf *cb)
{
	Debugger d;
	int dbgstate = 0;
	int i;
	char *df;
	int dfsize;
	int setval;

	memset(&d, 0, sizeof(d));
	for(i=0; i < cb->nf; i++){
		setval = 0;
		df = nil;
		dfsize = 0;
		switch(cb->f[i][0]){
		case 'd':
			df = d.data;
			dfsize = sizeof(d.data);
			setval=1;
			break;
		case 'c':
			df = d.ctl;
			dfsize = sizeof(d.ctl);
			setval=1;
			break;
		case 'i':
			df = d.ctlstart;
			dfsize = sizeof(d.ctlstart);
			setval=1;
			break;
		case 'h':
			df = d.ctlstop;
			dfsize = sizeof(d.ctlstop);
			setval=1;
			break;
		case 'f':
			df = d.ctlflush;
			dfsize = sizeof(d.ctlflush);
			setval=1;
			break;
		case 'r':
			dbgstate = DBGrun;
			break;
		case 's':
			dbgstate = DBGstop;
			break;
		default:
			error(Ebadcmd);
		}
		if(setval){
			if(i+1 >= cb->nf)
				cmderror(cb, Enumarg);
			strncpy(df, cb->f[i+1], dfsize-1);
			df[dfsize-1] = 0;
			++d.running;
			++i;
		}
	}

	if(d.running){
		wlock(&debugger);
		if(debugger.running){
			wunlock(&debugger);
			error(Erunning);
		}
		if(d.data[0] != 0){
			strcpy(debugger.data, d.data);
			dbglog("data %s\n",debugger.data);
		}
		if(d.ctl[0] != 0){
			strcpy(debugger.ctl, d.ctl);
			dbglog("ctl %s\n",debugger.ctl);
		}
		if(d.ctlstart[0] != 0){
			strcpy(debugger.ctlstart, d.ctlstart);
			dbglog("ctlstart %s\n",debugger.ctlstart);
		}
		if(d.ctlstop[0] != 0){
			strcpy(debugger.ctlstop, d.ctlstop);
			dbglog("ctlstop %s\n",debugger.ctlstop);
		}
		wunlock(&debugger);
	}

	if(dbgstate == DBGrun){
		if(!debugger.running){
			wlock(&debugger);
			if(waserror()){
				wunlock(&debugger);
				nexterror();
			}
			if(!debugger.running)
				start_debugger();
			else
				dbglog("debugger already running\n");
			poperror();
			wunlock(&debugger);
		} else
			dbglog("debugger already running\n");
	} else if(dbgstate == DBGstop){
		if(debugger.running){
			/* force hangup to stop the dbg process */
			int cfd;
			if(debugger.ctl[0] == 0)
				return;
			cfd = kopen(debugger.ctl, OWRITE);
			if(cfd == -1)
				error(up->env->errstr);
			dbglog("stopping debugger\n");
			if(kwrite(cfd, debugger.ctlstop, strlen(debugger.ctlstop)) == -1)
				error(up->env->errstr);
			kclose(cfd);
		} else
			dbglog("debugger not running\n");
	}
}

static long
dbgwrite(Chan *c, void *va, long n, vlong)
{
	Cmdbuf *cb;

	switch((ulong)c->qid.path){
	default:
		error(Egreg);
		break;
	case Qdbgctl:
		cb = parsecmd(va, n);
		if(waserror()){
			free(cb);
			nexterror();
		}
		ctl(cb);
		poperror();
		break;
	}
	return n;
}

static void
dbgclose(Chan*)
{
}

Dev dbgdevtab = {
	'b',
	"dbg",

	devreset,
	dbginit,
	devshutdown,
	dbgattach,
	dbgwalk,
	dbgstat,
	dbgopen,
	devcreate,
	dbgclose,
	dbgread,
	devbread,
	dbgwrite,
	devbwrite,
	devremove,
	devwstat,
};
