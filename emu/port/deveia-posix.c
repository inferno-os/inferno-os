/*
 * Driver for POSIX serial ports
 */
#include	"dat.h"
#include	"fns.h"
#include	"error.h"
#undef _POSIX_C_SOURCE       /* for deveia-bsd.c */
#include <sys/stat.h>
#include	<termios.h>

enum
{
	Devchar = 't',

	Ndataqid = 1,
	Nctlqid,
	Nstatqid,
	Nqid = 3,		/* number of QIDs */

	CTLS=	023,
	CTLQ=	021,

	Maxctl = 128,
	Maxfield = 32
};

/*
 *  Macros to manage QIDs
 */
#define NETTYPE(x)	((x)&0x0F)
#define NETID(x)	((x)>>4)
#define NETQID(i,t)	(((i)<<4)|(t))

static Dirtab *eiadir;
static int ndir;

static char Devname[] = "eia";

typedef struct Eia Eia;
struct Eia {
	Ref		r;
	int		fd;
	int		overrun;
	int		frame;
	int		restore;       /* flag to restore prev. states */
	struct termios 	ts;
	int		dtr;
	int		rts;
	int		cts;
};

static Eia *eia;

struct tcdef_t {
	int	val;
	tcflag_t	flag;
};

struct flagmap {
	char*	s;
	tcflag_t	flag;
};

static struct tcdef_t bps[];

static struct tcdef_t size[] = {
	{5,	CS5},
	{6,	CS6},
	{7,	CS7},
	{8,	CS8},
	{-1,	-1}
};

static char *
ftos(char *buf, struct tcdef_t *tbl, tcflag_t flag)
{
	for(; tbl->val >= 0; tbl++)
		if(tbl->flag == flag){
			sprint(buf, "%d", tbl->val);
			return buf;
		}
	return "unknown";
}

static tcflag_t
stof(struct tcdef_t *tbl, int val)
{
	for(; tbl->val >= 0 && tbl->val != val; tbl++)
		{}
	return tbl->flag;
}

static char *
rdxtra(int port, struct termios *ts, char *str);	/* non-POSIX extensions */

static long
rdstat(int port, void *buf, long n, ulong offset)
{
	int  fd = eia[port].fd;
	struct termios ts;
	char str[Maxctl];
	char sbuf[20];
	char *s;

	if(tcgetattr(fd, &ts) < 0)
		oserror();

	s = str;
	s += sprint(s, "opens %d ferr %d oerr %d baud %s", 
		    eia[port].r.ref-1, eia[port].frame, eia[port].overrun,
		    ftos(sbuf, bps, (tcflag_t)cfgetospeed(&ts)));
	s = rdxtra(port, &ts, s);
	sprint(s, "\n");

	return readstr(offset, buf, n, str);
}

static char *
wrxtra(int port, struct termios *ts, char *cmd);  /* non-POSIX extensions */

static void
wrctl(int port, char *cmd)
{
	struct termios ts;
	char *xerr;
	int r, nf, n, i;
	char *f[Maxfield];
	int fd = eia[port].fd;
	tcflag_t flag;

	if(tcgetattr(fd, &ts) < 0) {
Error:
		oserror();
	}

	nf = tokenize(cmd, f, nelem(f));
	for(i = 0; i < nf; i++){
		if(strncmp(f[i], "break", 5) == 0){
			tcsendbreak(fd, 0);
			continue;
		}
		n = atoi(f[i]+1);
		switch(*f[i]) {
		case 'F':
		case 'f':
			if(tcflush(fd, TCOFLUSH) < 0)
				goto Error;
			break;
		case 'K':
		case 'k':
			if(tcsendbreak(fd, 0) < 0)
				;	/* ignore it */
			break;
		case 'H':
		case 'h':
			cfsetospeed(&ts, B0);
			break;
		case 'B':
		case 'b':
			flag = stof(bps, n);
			if((int)flag == -1)
				error(Ebadarg);
			cfsetispeed(&ts, (speed_t)flag);
			cfsetospeed(&ts, (speed_t)flag);
			break;
		case 'L':
		case 'l':
			flag = stof(size, n);
			if((int)flag == -1)
				error(Ebadarg);
			ts.c_cflag &= ~CSIZE;
			ts.c_cflag |= flag;
			break;
		case 'S':
		case 's':
			if(n == 1)
				ts.c_cflag &= ~CSTOPB;
			else if(n ==2)
				ts.c_cflag |= CSTOPB;
			else
				error(Ebadarg);
			break;
		case 'P':
		case 'p':
			if(*(f[i]+1) == 'o')
				ts.c_cflag |= PARENB|PARODD;
			else if(*(f[i]+1) == 'e') {
				ts.c_cflag |= PARENB;
				ts.c_cflag &= ~PARODD;
			}
			else
				ts.c_cflag &= ~PARENB;
			break;
		case 'X':
		case 'x':
			if(n == 0)
			        ts.c_iflag &= ~(IXON|IXOFF);
			else 
			        ts.c_iflag |= (IXON|IXOFF);
			break;
		case 'i':
		case 'I':
			/* enable fifo; ignore */
			break;
		default:
		        if((xerr = wrxtra(port, &ts, f[i])) != nil)
			        error(xerr);
		}
	}

	osenter();
	r = tcsetattr(fd, TCSADRAIN, &ts);
	osleave();
	if(r < 0)
		goto Error;
	eia[port].restore = 1;
	eia[port].ts      = ts;
}

static void
eiainit(void)
{
	int i, nports;
	Dirtab *dp;
	struct stat sb;

#ifdef buildsysdev
	buildsysdev();
#endif

	/* check to see which ports exist by trying to stat them */
	nports = 0;
	for (i=0; i < nelem(sysdev); i++) {
		if(stat(sysdev[i], &sb) < 0)
			break;

		nports++;
	}

	if (!nports)
		return;

	ndir = Nqid*nports+1;
	dp = eiadir = malloc(ndir*sizeof(Dirtab));
	if(dp == 0)
		panic("eiainit");
	strcpy(dp->name, ".");
	dp->qid.path = 0;
	dp->qid.type = QTDIR;
	dp->perm = DMDIR|0555;
	dp++;
	eia = malloc(nports*sizeof(Eia));
	if(eia == 0)
		panic("eiainit");
	for(i = 0; i < nports; i++) {
		sprint(dp->name, "%s%d", Devname, i);
		dp->qid.path = NETQID(i, Ndataqid);
		dp->perm = 0660;
		dp++;
		sprint(dp->name, "%s%dctl", Devname, i);
		dp->qid.path = NETQID(i, Nctlqid);
		dp->perm = 0660;
		dp++;
		sprint(dp->name, "%s%dstatus", Devname, i);
		dp->qid.path = NETQID(i, Nstatqid);
		dp->perm = 0660;
		dp++;
		eia[i].frame = eia[i].overrun = 0;
		eia[i].restore = eia[i].dtr = eia[i].rts = eia[i].cts = 0;
	}
}

static Chan*
eiaattach(char *spec)
{
	if(eiadir == nil)
		error(Enodev);

	return devattach(Devchar, spec);
}

Walkqid*
eiawalk(Chan *c, Chan *nc, char **name, int nname)
{
	return devwalk(c, nc, name, nname, eiadir, ndir, devgen);
}

int
eiastat(Chan *c, uchar *db, int n)
{
	return devstat(c, db, n, eiadir, ndir, devgen);
}

static void
resxtra(int port, struct termios *ts);	/* non-POSIX extensions */

static Chan*
eiaopen(Chan *c, int mode)
{
	int port = NETID(c->qid.path);
	struct termios ts;
	int r;

	c = devopen(c, mode, eiadir, ndir, devgen);

	switch(NETTYPE(c->qid.path)) {
	case Nctlqid:
	case Ndataqid:
	case Nstatqid:
		if(incref(&eia[port].r) != 1)
			break;

		osenter();
		eia[port].fd = open(sysdev[port], O_RDWR);
		osleave();
		if(eia[port].fd < 0)
			oserror();

		/* make port settings sane */
		if(tcgetattr(eia[port].fd, &ts) < 0)
			oserror();
		ts.c_iflag = ts.c_oflag = ts.c_lflag = 0;
		if(eia[port].restore)
		        ts = eia[port].ts;
		else {
			cfsetispeed(&ts, B9600);
			cfsetospeed(&ts, B9600);
			ts.c_iflag |= IGNPAR;
			ts.c_cflag &= ~CSIZE;
			ts.c_cflag |= CS8|CREAD;
			ts.c_cflag &= ~(PARENB|PARODD);
			ts.c_cc[VMIN] = 1;
			ts.c_cc[VTIME] = 0;
		}
		osenter();
		r = tcsetattr(eia[port].fd, TCSANOW, &ts);
		osleave();
		if(r < 0)
			oserror();

		if(eia[port].restore)
		        resxtra(port, &ts);
		break;
	}
	return c;
}

static void
eiaclose(Chan *c)
{
	int port = NETID(c->qid.path);

	if((c->flag & COPEN) == 0)
		return;

	switch(NETTYPE(c->qid.path)) {
	case Nctlqid:
	case Ndataqid:
	case Nstatqid:
		if(decref(&eia[port].r) != 0)
			break;
		if(eia[port].fd >= 0) {
			osenter();
			close(eia[port].fd);
			osleave();
		}
		break;
	}

}

static long
eiaread(Chan *c, void *buf, long n, vlong offset)
{
	ssize_t cnt;
	int port = NETID(c->qid.path);

	if(c->qid.type & QTDIR)
		return devdirread(c, buf, n, eiadir, ndir, devgen);

	switch(NETTYPE(c->qid.path)) {
	case Ndataqid:
	  	osenter(); 
		cnt = read(eia[port].fd, buf, n);
		osleave(); 
		if(cnt == -1)
			oserror();
		return cnt;
	case Nctlqid:
		return readnum(offset, buf, n, port, NUMSIZE);
	case Nstatqid:
		return rdstat(port, buf, n, offset);
	}

	return 0;
}

static long
eiawrite(Chan *c, void *buf, long n, vlong offset)
{
	ssize_t cnt;
	char cmd[Maxctl];
	int port = NETID(c->qid.path);

	USED(offset);

	if(c->qid.type & QTDIR)
		error(Eperm);

	switch(NETTYPE(c->qid.path)) {
	case Ndataqid:
	  	osenter(); 
		cnt = write(eia[port].fd, buf, n);
		osleave(); 
		if(cnt == -1)
			oserror();
		return cnt;
	case Nctlqid:
		if(n >= (long)sizeof(cmd))
			n = sizeof(cmd)-1;
		memmove(cmd, buf, n);
		cmd[n] = 0;
		wrctl(port, cmd);
		return n;
	}
	return 0;
}

int
eiawstat(Chan *c, uchar *dp, int n)
{
	Dir d;
	int i;

	if(strcmp(up->env->user, eve) != 0)
		error(Eperm);
	if(c->qid.type & QTDIR)
		error(Eperm);

	n = convM2D(dp, n, &d, nil);
	i = Nqid*NETID(c->qid.path)+NETTYPE(c->qid.path)-Ndataqid;
	eiadir[i+1].perm = d.mode&0666;
	return n;
}

Dev eiadevtab = {
        Devchar,
        Devname,

        eiainit,
        eiaattach,
        eiawalk,
        eiastat,
        eiaopen,
        devcreate,
        eiaclose,
        eiaread,
        devbread,
        eiawrite,
        devbwrite,
        devremove,
        eiawstat
};
