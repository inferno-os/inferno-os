#ifdef WINDOWSNT
#include <windows.h>
#endif
#include <lib9.h>
#include <styx.h>
#include "styxserver.h"
/* #include <winsock.h> */

#define DEFCOLSIZE			10000

static int ODebug;

char Eodbcalloc[] =	"no free ODBC handles";
char Enoconnect[] =	"no ODBC connection";

static char	*netport = "6700";
static char	*inferno = "inferno";

Styxserver *iserver;

/* ----- */
#include <sql.h>
#include <sqlext.h>

int nclients = 0;

typedef struct Env Env;
struct Env
{
	SQLHENV h;			/* ODBC environment handle */
};

typedef struct Conn Conn;
struct Conn
{
	SQLHDBC	h;			/* ODBC connection handle */
	int		connected;
};

typedef struct Coltype Coltype;
struct Coltype
{
	char		name[255];
	ushort	type;
	SQLUINTEGER		size;
	ushort	digits;
	ushort	nulls;
};

typedef struct Column Column;
struct Column
{
	char 	*data;
	SQLINTEGER	len;
};

typedef struct Stmt Stmt;
struct Stmt
{
	SQLHSTMT h;			/* ODBC statement handle */
	ushort	ncols;		/* number of columns in result */
	ulong	nrows;		/* number of rows affected by update, insert, delete */
	Coltype	*cols;		/* column descriptions */
	Column	*rec;			/* data record */
	char		*headstr;		/* column headings if requested */
};

/* ----- */
enum
{
	Qtopdir		= 0,	/* top level directory */
	Qnclients,
	Qprotodir,
	Qclonus,
	Qconvdir,
	Qdata,
	Qcmd,
	Qctl,
	Qstatus,
	Qformat,
	Qsources,
	Qerror,

	MAXPROTO	= 1
};
#define TYPE(x) 	((x).path & 0xf)
#define CONV(x) 	(((x).path >> 4)&0xfff)
#define PROTO(x) 	(((x).path >> 16)&0xff)
#define QID(p, c, y) 	(((p)<<16) | ((c)<<4) | (y))

typedef struct Proto	Proto;
typedef struct Conv	Conv;
typedef struct Output Output;

struct Output {
	enum {Fixed, Float} style;			/* output style */
	uchar	fs;					/* float: field separator */
	uchar	rs;					/* float: record separator */
};
Output defoutput = {Float, '|', '\n'};

struct Conv
{
	int	x;
	int	ref;
	int	perm;
	char	*owner;
	char*	state;
	Proto*	p;

	/*-----*/
	Conn	c;
	Stmt		s;
	Output	out;
	int		headings;
	char		errmsg[400];	/* odbc error messages can be big */
};

struct Proto
{
	int	x;
	char	*name;
	uint	nc;
	int	maxconv;
	Conv**	conv;
	Qid	qid;
};

typedef struct Dirtab	Dirtab;
struct Dirtab
{
	char	name[255];
	Qid	qid;
	long	length;
	long	perm;
};

static	int		np;
static	Proto	proto[MAXPROTO];
static	Conv*	protoclone(Proto*, char*);

typedef int    Devgen(Fid*, char *, Dirtab*, int, int, Dir*);

struct xClient {
	/* ---- */
	Env		e;
};

#define H(c)	((Env*)(c->u))->h

void
fatal(char *fmt, ...)
{
	char buf[1024], *out;
	va_list arg;
	out = vseprint(buf, buf+sizeof(buf), "Fatal error: ", 0);
	va_start(arg, fmt);
	out = vseprint(out, buf+sizeof(buf), fmt, arg);
	va_end(arg);
	write(2, buf, out-buf);
	exit(1);
}

#define ASSERT(A,B) xassert((int)A,B)

void
xassert(int true, char *reason)
{
	if(!true)
		fatal("assertion failed: %s\n", reason);
}

void *
xmalloc(int bytes)
{
	char *m = malloc(bytes);
	if(m)
		memset(m, 0, bytes);
//	print("xmalloc: %lux (%d)\n", m, bytes);
	return m;
}

void
xfree(void *p, char *from)
{
//	print("xfree: %lux [%s]\n", p, from);
	free(p);
}

char *
odbcerror(Conv *cv, int lasterr)
{
	char sqlstate[6];
	long native;
	char *mp;
	short msglen;

	if(cv == 0)
		return "";
	if(lasterr)
		return cv->errmsg;
	if(cv->c.connected)
		SQLGetDiagRec(SQL_HANDLE_STMT, cv->s.h, 1, sqlstate, &native, cv->errmsg, sizeof(cv->errmsg), &msglen);
	else
		SQLGetDiagRec(SQL_HANDLE_DBC, cv->c.h, 1, sqlstate, &native, cv->errmsg, sizeof(cv->errmsg), &msglen);
	cv->errmsg[msglen]=0;
	/* fprint(2, "c: sqlstate: %s, msg %s\n", sqlstate, cv->errmsg); */
	if((mp=strrchr(cv->errmsg, ']')) != 0)
		return mp+1;
	return cv->errmsg;
}

char*
odbcsources(Client *c)
{
	int ss, i;
	char server[SQL_MAX_DSN_LENGTH+1];
	char source[1024];
	char buff[1024+SQL_MAX_DSN_LENGTH+1];
	short serverlen, sourcelen;
	char *all = nil, *p;

	for (i=0;; i++) {
		ss = SQLDataSources(H(c), (i==0 ? SQL_FETCH_FIRST : SQL_FETCH_NEXT),
				server, sizeof(server), &serverlen,
				source, sizeof(source), &sourcelen);
		if (ss != SQL_SUCCESS)
			break;
		snprint(buff, sizeof(buff), "%s:%s\n", server, source);
		if (i == 0)
			all = strdup(buff);
		else {
			p = all;
			all = malloc(strlen(all)+strlen(buff)+1);
			strcpy(all, p);
			strcat(all, buff);
			free(p);
		}
	}
	return all;
}


int
sqlerr(Conv *c, int sqlstatus, char *errp, char *func, char *sqlcall)
{
	char *e;

	errp[0] = 0;
	e = "failed";
	if (sqlstatus == SQL_ERROR || sqlstatus == SQL_SUCCESS_WITH_INFO)
		strecpy(errp, errp+ERRMAX, odbcerror(c, 0));
	if (sqlstatus == SQL_SUCCESS_WITH_INFO)
		e = "info";
	if (sqlstatus != SQL_SUCCESS)
		fprint(2, "%s: %s %s - %s\n", func, sqlcall, e, errp);
	if (sqlstatus != SQL_SUCCESS && sqlstatus != SQL_SUCCESS_WITH_INFO)
		return 1;
	return 0;
}

char*
odbcnewclient(Client *c)
{
	int ss;

	/* ---- */
	c->u = styxmalloc(sizeof(Env));
	ss = SQLAllocHandle(SQL_HANDLE_ENV, SQL_NULL_HANDLE, &H(c));
	if (ss != SQL_SUCCESS && ss != SQL_SUCCESS_WITH_INFO) {
		fprint(2, "newclient: SQLAllocHandle failed\n");
		return "SQLAllocHandle failed";
	}
	ss = SQLSetEnvAttr(H(c), SQL_ATTR_ODBC_VERSION, (char*)SQL_OV_ODBC2, 0);
	if (ss != SQL_SUCCESS && ss != SQL_SUCCESS_WITH_INFO) {
		fprint(2, "newclient: SQLSetEnvAttr failed\n");
		return "SQLSetEnvAttr failed";
	}
	nclients++;
	return nil;
}

char*
odbcfreeclient(Client *c)
{
	int ss;

	ss = SQLFreeHandle(SQL_HANDLE_ENV, H(c));
	if (ss != SQL_SUCCESS && ss != SQL_SUCCESS_WITH_INFO)
		fprint(2, "freeclient: SQLFreeHandle failed\n");
	styxfree(c->u);
	nclients--;
	return nil;
}

int
parsefields(char *lp, char **fields, int n, char *sep)
{
	int i;

	for(i=0; lp && *lp && i<n; i++){
		while(*lp && strchr(sep, *lp) != 0)
			*lp++=0;
		if(*lp == 0)
			break;
		fields[i]=lp;
		while(*lp && strchr(sep, *lp) == 0)
			lp++;
	}
	return i;
}

void
odbcdisconnect(Conv *c)
{
	int ss;

	if(c->c.connected){
		ss = SQLFreeHandle(SQL_HANDLE_STMT, c->s.h);
		if (ss != SQL_SUCCESS && ss != SQL_SUCCESS_WITH_INFO)
			fprint(2, "odbcdisconnect: SQLFreeHandle failed\n");
		ss = SQLDisconnect(c->c.h);
		if (ss != SQL_SUCCESS && ss != SQL_SUCCESS_WITH_INFO)
			fprint(2, "odbcdisconnect: SQLDisconnect failed\n");
		c->c.connected = 0;
	}
}

int
odbcconnect(Conv *c, char *server, char *user, char *auth, char *ename)
{
	int ss;

	odbcdisconnect(c);
	ss = SQLConnect(c->c.h, server, SQL_NTS, user, strlen(user), auth, strlen(auth));
	if (sqlerr(c, ss, ename, "odbcconnect", "SQLConnect"))
		return -1;
	c->c.connected = 1;
	ss = SQLAllocHandle(SQL_HANDLE_STMT, c->c.h, &c->s.h);
	if (sqlerr(c, ss, ename, "odbcconnect", "SQLAllocHandle"))
		return -1;
	return 0;
}

int
odbcnewconv(Client *c, Conv *cv)
{
	int ss;

	ss = SQLAllocHandle(SQL_HANDLE_DBC, H(c), &cv->c.h);
	if (ss != SQL_SUCCESS && ss != SQL_SUCCESS_WITH_INFO) {
		fprint(2, "odbcnewconv: SQLAllocHandle failed\n");
		return -1;
	}
	return 0;
}

void
odbcfreeconv(Conv *c)
{
	int ss;

	odbcdisconnect(c);
	ss = SQLFreeHandle(SQL_HANDLE_DBC, c->c.h);
	if (ss != SQL_SUCCESS && ss != SQL_SUCCESS_WITH_INFO)
		fprint(2, "odbcfreeconv: SQLFreeHandle failed\n");
}

/* Free up all memory used in the last query */
void
freestat(Stmt *s)
{
	int i;
	if (s->ncols == 0)
		return;
	for(i=0; i<s->ncols; i++){
		Column *d = &s->rec[i];
		xfree(d->data, "freestat - data");
	}
	xfree(s->cols, "freestat - cols");
	s->cols = 0;
	xfree(s->rec, "freestat - rec");
	s->rec = 0;
	xfree(s->headstr, "freestat - headstr");
	s->headstr = 0;
	s->ncols = 0;
}


/* build an array describing the columns */
int
mkcols(Conv *c, char *ename)
{
	Stmt *s;
	int rv, i, err, hsize;
	ushort ignore;
	char *p;

	s = &c->s;
	s->ncols = 0;
	rv = SQLNumResultCols(s->h, &s->ncols);
	if (sqlerr(c, rv, ename, "mkcols", "SQLNumResultCols"))
		return -1;
	s->cols = xmalloc(s->ncols*sizeof(Coltype));
	err = 0;
	hsize = 0;
	for(i=0; i<s->ncols; i++){
		Coltype *t = &s->cols[i];
		rv = SQLDescribeCol(s->h, i+1, t->name, sizeof(t->name), &ignore, &t->type, &t->size, &t->digits, &t->nulls);
		if (sqlerr(c, rv, ename, "mkcols", "SQLDescribeCol"))
			err++;
		if(t->size == 0 || t->size > MSGMAX) /* odbc should return 0 if size not available, not -1 */
			t->size = DEFCOLSIZE;
		hsize += strlen(t->name) + 1;
	}
	if (c->headings) {
		hsize += 2;
		s->headstr = xmalloc(hsize);
		p = s->headstr;
		for(i=0; i<s->ncols; i++) {
			Coltype *t = &s->cols[i];
			p += sprint(p, "%s%c", t->name, c->out.fs);
		}
		p[-1] = c->out.rs;
	} else 
		s->headstr = 0;
	return (err ? -1 : 0);
}

/* build a record to hold `fetched' results */
int
mkrec(Conv *c, char *ename)
{
	Stmt *s;
	int rv, i;

	s = &c->s;
	s->rec = xmalloc(s->ncols*sizeof(Column));
	for(i=0; i<s->ncols; i++){
		Coltype *t = &s->cols[i];
		Column *d = &s->rec[i];
		if (ODebug)
			print("Column %d size=%ud type=%hd\n", i, t->size, t->type);
		d->data = xmalloc(t->size+1);		/* expects to zero terminate */
		rv = SQLBindCol(s->h, i+1, SQL_C_CHAR, d->data, t->size+1, &d->len);
		if (sqlerr(c, rv, ename, "mkrec", "SQLBindCol"))
			return -1;
	}
	return 0;
}

int
rowcount(Conv *c, char *ename)
{
	Stmt *s;
	int rv;

	s = &c->s;
	s->nrows = 0;
	rv = SQLRowCount(s->h, &s->nrows);
	if (sqlerr(c, rv, ename, "rowcount", "SQLRowCount"))
		return -1;
	return 0;
}

int
odbcfetch(Conv *c, char *ename)
{
	Stmt *s = &c->s;
	int rv;

	rv = SQLFetch(s->h);
	if(rv == SQL_NO_DATA) {
		freestat(s);
		return 0;
	}
	if (sqlerr(c, rv, ename, "odbcfetch", "SQLFetch")) {
		freestat(s);
		return -1;
	}
	return 1;
}

int
odbcresults(Conv *c, char *ename)
{
	if(mkcols(c, ename))
		return -1;
	if(mkrec(c, ename))
		return -1;
	if(rowcount(c, ename))
		return -1;
	return 0;
}

void
struncate(char *s, long *len)
{
	long i;
	for (i=0; i<*len; i++)
		if (s[i] == 0) {
			*len = i;
			return;
		}
}

void
fix_delim(char *p, int len, char delim)
{
	int i;
	for (i=0; i<len; i++)
		if (p[i] == delim)
			p[i] = '\\';
}

long
odbcdataread(Conv *c, void *a, long n, ulong offset, char *ename)
{
	Stmt *s = &c->s;
	int i, r;
	long left;
	char *p, *lastp;

	if(c->c.connected == 0){
		strcpy(ename, Enoconnect);
		return -1;
	}
	if (s->cols == 0 || s->rec == 0)
		return 0;
	p = a;
	left = n;
	if (c->headings) {
		r = strlen(s->headstr);
		if (r && offset < r) {
			memcpy(p, s->headstr+offset, r-offset);
			p +=  r-offset;
			left -=  r-offset;
			return n-left;
		}
	}
	if((r=odbcfetch(c, ename)) < 0)
		return -1;	
	if(r == 0)
		return 0;
	for(i=0; i<s->ncols; i++){
		Coltype *t = &s->cols[i];
		Column *d = &s->rec[i];
		if (ODebug)
			fprint(2, "Col %d Returned data len=%d\n", i, d->len);
		if(d->len <= 0)			/* SQL_NULL_DATA or strange error! */
			d->len = 0;
		if (d->len > t->size+1)
			d->len = t->size+1;
		if(left <= d->len+1)		/* whole fields */
			break;
		struncate(d->data, &d->len);	/* assume string data and stop on an embedded null */
		memcpy(p, d->data, d->len);
		lastp = p;
		left -= d->len;
		p += d->len;
		fix_delim(lastp, d->len, '\n');
		switch(c->out.style){
		case Float:
			fix_delim(lastp, d->len, c->out.fs);
			*p++ = (i==s->ncols-1)? c->out.rs: c->out.fs;
			left--;
			break;
		case Fixed:
			r = t->size - d->len;
			if(r < 0)
				r = 0;
			if(left < r)
				r = left;
			memset(p, ' ', r);
			left -= r;
			p += r;
			break;
		}
	}
	if (left < 0)
		fprint(2, "*** left<0 n=%d left=%d\n", n, left);
	return n-left;
}

/*
 * Returns a description of the format of a fixed width output
 * record. `start' is the offset of the first character in the field.
 * `end' is one greater than the offset of the last character of the field.
 * `name' is the column name (which may contain spaces).
 * `start' and `end' are terminated with a space, `name' with a newline.
 * return 1 record containing one line for each field in the output:
 *    start1 end1 name1\n
 *    start2 end2 name2\n
 *    ....
 */
long
odbcfmtread(Conv *c, void *a, long n, ulong offset, char *ename)
{
	Stmt *s = &c->s;
	int i, len;
	long left, off;
	char *p;
	char buf[100];

	if(offset > 0)
		return 0;
	p = a;
	left = n;
	off = 0;
	for(i=0; i<s->ncols; i++){
		Coltype *t = &s->cols[i];

		len = snprint(buf, sizeof(buf), "%ld %ld %s\n", off, off+t->size, t->name);
		off += t->size;
		if(left < len)
			break;
		memcpy(p, buf, len);
		left -= len;
		p += len;

	}
	return n-left;
}

int
odbctables(Conv *c, char *ename)
{
	int rv;

	if(c->c.connected == 0){
		strcpy(ename, Enoconnect);
		return -1;
	}
	rv = SQLCloseCursor(c->s.h);
	rv = SQLTables(c->s.h, 0, 0, 0, 0, 0, 0, 0, 0);
	if (sqlerr(c, rv, ename, "odbctables", "SQLTables"))
		return -1;
	if(odbcresults(c, ename))
		return -1;
	return 0;
}

int
odbccolumns(Conv *c, char *table, char *ename)
{
	int rv;

	if(c->c.connected == 0){
		strcpy(ename, Enoconnect);
		return -1;
	}
	rv = SQLCloseCursor(c->s.h);
	rv = SQLColumns(c->s.h, 0, 0, 0, 0, table, strlen(table), 0, 0);
	if (sqlerr(c, rv, ename, "odbccolumns", "SQLColumns"))
		return -1;
	if(odbcresults(c, ename))
		return -1;
	return 0;
}

int
odbcexec(Conv *c, char *cmd, int cmdlen, char *ename)
{
	int rv;

	if(c->c.connected == 0){
		strcpy(ename, Enoconnect);
		return -1;
	}
	SQLCloseCursor(c->s.h);
	rv = SQLExecDirect(c->s.h, cmd, cmdlen);
	if (sqlerr(c, rv, ename, "odbcexec", "SQLExecDirect"))
		return -1;
	if(odbcresults(c, ename))
		return -1;
	return 0;
}

int
odbctrans(Conv *c, char *cmd, char *ename)
{
	int rv;

	if(strcmp(cmd, "auto") == 0){
		rv = SQLSetConnectAttr(c->c.h, SQL_ATTR_AUTOCOMMIT, (char*)SQL_AUTOCOMMIT_ON, 0);
	} else if(strcmp(cmd, "begin") == 0){
		rv = SQLSetConnectAttr(c->c.h, SQL_ATTR_AUTOCOMMIT, (char*)SQL_AUTOCOMMIT_OFF, 0);
	} else if(strcmp(cmd, "commit") == 0){
		rv = SQLEndTran(SQL_HANDLE_DBC, c->c.h, SQL_COMMIT);
	} else if(strcmp(cmd, "rollback") == 0){
		rv = SQLEndTran(SQL_HANDLE_DBC, c->c.h, SQL_ROLLBACK);
	} else {
		strcpy(ename, Ebadarg);
		return -1;
	}
	if (sqlerr(c, rv, ename, "odbctrans", "SQLSetConnectAttr/SQLEndTran"))
		return -1;
	return 0;
}

int
readstr(ulong off, char *buf, ulong n, char *str)
{
	int size;

	size = strlen(str);
	if(off >= size)
		return 0;
	if(off+n > size)
		n = size-off;
	memmove(buf, str+off, n);
	return n;
}

static void
newproto(char *name, int maxconv)
{
	int l;
	Proto *p;

	if(np >= MAXPROTO) {
		print("no %s: increase MAXPROTO", name);
		return;
	}

	p = &proto[np];
	p->name = strdup(name);
	p->qid.path = QID(np, 0, Qprotodir);
	p->qid.type = QTDIR;
	p->x = np++;
	p->maxconv = maxconv;
	l = sizeof(Conv*)*(p->maxconv+1);
	p->conv = xmalloc(l);
	if(p->conv == 0)
		fatal("no memory");
	memset(p->conv, 0, l);
}

char*
openmode(int *o)
{
	if(*o >= (OTRUNC|OCEXEC|ORCLOSE|OEXEC)){
		return Ebadarg;
	}
	*o &= ~(OTRUNC|OCEXEC|ORCLOSE);
	if(*o > OEXEC){
		return Ebadarg;
	}
	if(*o == OEXEC)
		*o = OREAD;
	return nil;
}

static Conv*
protoclone(Proto *p, char *user)
{
	Conv *c, **pp, **ep;
	uvlong nr;
	char buf[16];

	c = 0;
	ep = &p->conv[p->maxconv];
	for(pp = p->conv; pp < ep; pp++) {
		c = *pp;
		if(c == 0) {
			c = xmalloc(sizeof(Conv));
			if(c == 0)
				return 0;
			c->ref = 1;
			c->p = p;
			c->x = pp - p->conv;
			p->nc++;
			*pp = c;
			break;
		}
		if(c->ref == 0) {
			c->ref++;
			break;
		}
	}
	if(pp >= ep)
		return 0;

	c->owner = strdup(user);
	c->perm = 0660;
	c->state = "Open";
	c->out = defoutput;
	c->headings = 0;
	c->errmsg[0] = 0;

	nr = QID(0, c->x, Qconvdir);
	snprint(buf, sizeof(buf), "%d", c->x);
	styxadddir(iserver, Qprotodir, nr, buf, 0555, c->owner);
	styxaddfile(iserver, nr, QID(0, c->x, Qcmd), "cmd", c->perm, c->owner);
	styxaddfile(iserver, nr, QID(0, c->x, Qctl), "ctl", c->perm, c->owner);
	styxaddfile(iserver, nr, QID(0, c->x, Qdata), "data", c->perm, c->owner);
	styxaddfile(iserver, nr, QID(0, c->x, Qerror), "error", c->perm, c->owner);
	styxaddfile(iserver, nr, QID(0, c->x, Qformat), "format", c->perm, c->owner);
	styxaddfile(iserver, nr, QID(0, c->x, Qsources), "sources", c->perm, c->owner);
	styxaddfile(iserver, nr, QID(0, c->x, Qstatus), "status", 0444, c->owner);

	return c;
}

char*
dbopen(Qid *qid, int omode)
{
	Proto *p;
	int perm;
	Conv *cv;
	char *user;
	Qid q;
	Client *c;

	q = *qid;
	c = styxclient(iserver);

	perm = 0;
	omode &= 3;
	switch(omode) {
	case OREAD:
		perm = 4;
		break;
	case OWRITE:
		perm = 2;
		break;
	case ORDWR:
		perm = 6;
		break;
	}

	switch(TYPE(q)) {
	default:
		break;
	case Qtopdir:
	case Qprotodir:
	case Qconvdir:
	case Qstatus:
	case Qformat:
	case Qsources:
	case Qerror:
		if(omode != OREAD){
			return Eperm;
		}
		break;
	case Qclonus:
		p = &proto[PROTO(q)];
		cv = protoclone(p, c->uname);
		if(cv == 0){
			return Enodev;
		}
		qid->path = QID(p->x, cv->x, Qctl);
		qid->type = 0;
		qid->vers = 0;
		if(odbcnewconv(c, cv) != 0){
			return Eodbcalloc;
		}
		break;
	case Qdata:
	case Qcmd:
	case Qctl:
		p = &proto[PROTO(q)];
		cv = p->conv[CONV(q)];
		user = c->uname;
		if((perm & (cv->perm>>6)) != perm) {
			if(strcmp(user, cv->owner) != 0 ||
		 	  (perm & cv->perm) != perm) {
				return Eperm;
			}
		}
		cv->ref++;
		if(cv->ref == 1) {
			cv->state = "Open";
			cv->owner = strdup(user);
			cv->perm = 0660;
			if(odbcnewconv(c, cv) != 0){
				return Eodbcalloc;
			}
		}
		break;
	}
	return openmode(&omode);
}

char*
dbclose(Qid qid, int mode)
{
	Conv *cc;

	USED(mode);
	switch(TYPE(qid)) {
	case Qctl:
	case Qcmd:
	case Qdata:
		cc = proto[PROTO(qid)].conv[CONV(qid)];
		if(--cc->ref != 0)
			break;
		cc->owner = inferno;
		cc->perm = 0666;
		cc->state = "Closed";
		odbcfreeconv(cc);
		styxrmfile(iserver, QID(0, cc->x, Qconvdir));
		break;
	}
	return nil;
}

static char ebuf[ERRMAX];

char*
dbread(Qid qid, char *ba, ulong *n, vlong offset)
{
	uchar *a = ba;
	Conv *c;
	Proto *x;
	char buf[128], *p, *s;
	long r;
	ulong m;

	m = *n;
	ebuf[0] = 0;
	p = a;
	switch(TYPE(qid)) {
	default:
		return Eperm;
	case Qnclients:
		snprint(buf, sizeof(buf), "%d\n", nclients);
		*n = readstr(offset, p, m, buf);
		return nil;
	case Qprotodir:
	case Qtopdir:
	case Qconvdir:
		return "bad read of directory";
	case Qctl:
		snprint(buf, sizeof(buf), "%ld", CONV(qid));
		*n = readstr(offset, p, m, buf);
		return nil;
	case Qstatus:
		x = &proto[PROTO(qid)];
		c = x->conv[CONV(qid)];
		snprint(buf, sizeof(buf), "%s/%d %ld %s %s\n",
			c->p->name, c->x, c->ref, c->state, "");
		*n = readstr(offset, p, m, buf);
		return nil;
	case Qdata:
		c = proto[PROTO(qid)].conv[CONV(qid)];
		*n = odbcdataread(c, a, m, offset, ebuf);
		if(ebuf[0] != 0)
			return ebuf;
		return nil;
	case Qformat:
		c = proto[PROTO(qid)].conv[CONV(qid)];
		*n = odbcfmtread(c, a, m, offset, ebuf);
		if(ebuf[0] != 0)
			return ebuf;
		return nil;
	case Qerror:
		c = proto[PROTO(qid)].conv[CONV(qid)];
		*n = readstr(offset, p, m, odbcerror(c, 1));
		return nil;
	case Qsources:
		c = proto[PROTO(qid)].conv[CONV(qid)];
		s = odbcsources(styxclient(iserver));
		r = readstr(offset, p, m, s);
		free(s);
		*n = r;
		return nil;
	}
	return nil;
}

char*
dbwrite(Qid qid, char *ba, ulong *n, vlong offset)
{
	uchar *a = ba;
	int nf;
	Conv *c;
	Proto *x;
	char *fields[10], buf[512], safebuf[512];
	ulong m;

	m = *n;
	ebuf[0] = 0;
	switch(TYPE(qid)) {
	default:
		return Eperm;
	case Qctl:
		x = &proto[PROTO(qid)];
		c = x->conv[CONV(qid)];
		// 
		if(m > sizeof(buf)-1)
			m = sizeof(buf)-1;
		memmove(buf, a, m);
		buf[m] = '\0';
		if (ODebug)
			fprint(2, "write Qctl: <%s>\n", buf);
		fields[0] = 0;
		nf = parsefields(buf, fields, sizeof(fields)/sizeof(*fields), " \n\t");
		if (nf == 0) {
			return Ebadarg;
		}
		if(strcmp(fields[0], "connect") == 0){ 	/* connect database [user!auth] */
			char *afields[2];
			char *user = "";
			char *auth = "";
			switch(nf){
			default:
				return Ebadarg;
			case 2:
				break;
			case 3:
				nf = parsefields(fields[2], afields, 2, "!");
				switch(nf){
				case 2:
					user = afields[0];
					auth = afields[1];
					break;
				case 1:
					if(fields[2][0] == 0)
						auth = afields[0];
					else
						user = afields[0];
					break;
				default:
					break;
				}
				break;
			}
			if(odbcconnect(c, fields[1], user, auth, ebuf) < 0)
				return ebuf;
			c->state = "Connected";
		} else if(strcmp(fields[0], "disconnect") == 0){
			odbcdisconnect(c);
			c->state = "Disconnected";
		} else if(strcmp(fields[0], "fixed") == 0){
			c->out = defoutput;
			c->out.style = Fixed;
		} else if(strcmp(fields[0], "float") == 0){
			c->out = defoutput;
			c->out.style = Float;
			if(nf > 1)
				c->out.fs = fields[1][0];
			if(nf > 2)
				c->out.rs = fields[2][0];
		} else if(strcmp(fields[0], "headings") == 0){
			c->headings = 1;
		} else if(strcmp(fields[0], "noheadings") == 0){
			c->headings = 0;
		} else if(strcmp(fields[0], "trans") == 0){ /* begin, auto, commit, rollback */
			if(nf < 2){
				return Ebadarg;
			}
			if(odbctrans(c, fields[1], ebuf) < 0)
				return ebuf;
		} else {
			return Ebadcmd;
		}
		*n = m;
		return nil;
	case Qcmd:
		x = &proto[PROTO(qid)];
		c = x->conv[CONV(qid)];
		if(m > sizeof(buf)-1)
			m = sizeof(buf)-1;
		memmove(buf, a, m);
		buf[m] = '\0';
		if (ODebug)
			fprint(2, "write Qcmd: <%s>\n", buf);
		memmove(safebuf, a, m);
		safebuf[m] = '\0';
		fields[0] = 0;
		nf = parsefields(buf, fields, 3, " \n\t");
		if (nf == 0) {
			return Ebadarg;
		}
		if(strcmp(fields[0], "tables") == 0){
			if(odbctables(c, ebuf))
				return ebuf;
		}else if(strcmp(fields[0], "columns") == 0){
			if(nf < 2){
				return Ebadarg;
			}
			if(odbccolumns(c, &safebuf[strlen(fields[0])+1], ebuf))	/* allow for spaces in table name */
				return ebuf;
		} else
			if (odbcexec(c, a, m, ebuf))
				return ebuf;
		*n = m;
		return nil;
	case Qdata:
		return Eperm;
	}
	return nil;
}

void
badusage(void)
{
	fprint(2, "Usage: odbc [-d] [-p port]\n");
	exit(1);
}

Styxops ops = {
	odbcnewclient,			/* newclient */
	odbcfreeclient,			/* freeclient */

	nil,			/* attach */
	nil,			/* walk */
	dbopen,		/* open */
	nil,			/* create */
	dbread,		/* read */
	dbwrite,		/* write */
	dbclose,		/* close */
	nil,			/* remove */
	nil,			/* stat */
	nil,			/* wstat */
};

void
main(int argc, char *argv[])
{
	Styxserver s;

	ARGBEGIN {
	default:
		badusage();
	case 'd':		/* Debug */
		ODebug = 1;
		styxdebug();
		break;
	case 'p':		/* Debug */
		netport = EARGF(badusage());
		break;
	} ARGEND

	iserver = &s;
	styxinit(&s, &ops, netport, -1, 1);
	styxaddfile(&s, Qroot, Qnclients, "nclients", 0444, inferno);
	styxadddir(&s, Qroot, Qprotodir, "db", 0555, inferno);
	styxaddfile(&s, Qprotodir, Qclonus, "new", 0666, inferno);
	newproto("db", 100);
	for (;;) {
		styxwait(&s);
		styxprocess(&s);
	}
	styxend(&s);
}
