#include	<lib9.h>

#define	Lock	Rclock
#define	Ref		Rcref

typedef union Code	Code;
typedef struct Tree	Tree;
typedef struct Thread	Thread;
typedef struct Word	Word;
typedef struct Var	Var;
typedef struct List	List;
typedef struct Redir	Redir;
typedef struct Io	Io;
typedef struct Here	Here;
typedef struct Ref	Ref;
typedef struct Lock	Lock;
typedef	struct Direntry Direntry;

#define	EOF	(-1)
#define	NBUF	512

/* values for Tree->rtype */
#define	APPEND	1
#define	WRITE	2
#define	READ	3
#define	HERE	4
#define	DUPFD	5
#define	CLOSE	6

/*
 * redir types
 */
#define	ROPEN	1			/* dup2(from, to); close(from); */
#define	RDUP	2			/* dup2(from, to); */
#define	RCLOSE	3			/* close(from); */

#define	NSTATUS	64			/* length of status (from plan 9) */

#define	IWS	0x01	/* inter word seperator when word lists are stored in env variables */

/*
 * Glob character escape in strings:
 *	In a string, GLOB must be followed by *?[ or GLOB.
 *	GLOB* matches any string
 *	GLOB? matches any single character
 *	GLOB[...] matches anything in the brackets
 *	GLOBGLOB matches GLOB
 */
#define	GLOB	((char)0x02)

/*
 * The first word of any code vector is a reference count.
 * Always create a new reference to a code vector by calling codecopy(.).
 * Always call codefree(.) when deleting a reference.
 */
union Code {
	void	(*f)(void);
	int	i;
	char	*s;
};


struct Tree
{
	int	type;
	int	rtype, fd0, fd1;		/* details of REDIR PIPE DUP tokens */
	char	*str;
	int	quoted;
	int	iskw;
	Tree	*child[3];
	Tree	*next;
};

struct Thread
{
	Code	*code;			/* code for this thread */
	int	pc;			/* code[pc] is the next instruction */
	List	*argv;			/* argument stack */
	Redir	*redir;			/* redirection stack */
	Redir	*startredir;		/* redir inheritance point */
	Var	*local;			/* list of local variables */
	char	*cmdfile;		/* file name in Xrdcmd */
	Io	*cmdfd;			/* file descriptor for Xrdcmd */
	int	iflast;			/* static `if not' checking */
	int	eof;			/* is cmdfd at eof? */
	int	iflag;			/* interactive? */
	int	lineno;			/* linenumber */
	int	pid;			/* process for Xpipewait to wait for */
	char	status[NSTATUS];	/* status for Xpipewait */
	Tree	*treenodes;		/* tree nodes created by this process */
	Thread	*ret;			/* who continues when this finishes */
};

struct Io
{
	int	fd;
	char	*bufp;
	char	*ebuf;
	char	*strp;
	char	buf[NBUF];
};

struct Var
{
	char	*name;		/* ascii name */
	Word	*val;		/* value */
	int	changed;
	Code	*fn;		/* pointer to function's code vector */
	int	fnchanged;
	int	pc;		/* pc of start of function */
	Var	*next;		/* next on hash or local list */
};

struct Word
{
	char	*word;
	Word	*next;
};

struct List
{
	Word	*words;
	List	*next;
};

struct Redir
{
	char	type;		/* what to do */
	short	from, to;	/* what to do it to */
	Redir	*next;		/* what else to do (reverse order) */
};

struct Here{
	Tree	*tag;
	char	*name;
	Here	*next;
};

struct Lock {
	int	val;
};

struct Ref
{
	Lock	lk;
	int	ref;
};

struct	Direntry
{
	int	isdir;
	char	*name;
};

/* main.c */
void	start(Code *c, int pc, Var *local);

/* lex.c */
void	yyerror(char*);
int	yylex(void);
int	yyparse(void);
int	wordchr(int);
int	idchr(int);

/* code.c */
int	compile(Tree*);
Code	*codecopy(Code*);
void	codefree(Code*);
void	cleanhere(char *f);

void	skipnl(void);

void	panic(char*, int);

/* var.c */
void	kinit(void);
void	vinit(void);
Var	*vlook(char*);
Var	*gvlook(char*);
Var	*newvar(char*, Var*);
void	setvar(char*, Word*);
void	updenv(void);
void	kenter(int type, char *name);

/* glob.c */
void	deglob(char*);
void	globlist(void);
int	match(char *s, char *p, int stop);

/* main.c */
void	setstatus(char *s);
char	*getstatus(void);
int	truestatus(void);
void	execcmds(Io*);
char	*concstatus(char *s, char *t);
char	**procargv(char*, char*, char*, char*, Word *w);

void	freewords(Word*);

/* tree.c */
Tree	*newtree(void);
Tree	*token(char*, int), *klook(char*), *tree1(int, Tree*);
Tree	*tree2(int, Tree*, Tree*), *tree3(int, Tree*, Tree*, Tree*);
Tree	*mung1(Tree*, Tree*), *mung2(Tree*, Tree*, Tree*);
Tree	*mung3(Tree*, Tree*, Tree*, Tree*), *epimung(Tree*, Tree*);
Tree	*simplemung(Tree*), *heredoc(Tree*);
void	freetree(Tree*);
void	freenodes(void);

/* here.c */
Tree	*heredoc(Tree *tag);

/* exec.c */
extern void Xappend(void), Xasync(void), Xbackq(void), Xbang(void), Xclose(void);
extern void Xconc(void), Xcount(void), Xdelfn(void), Xdol(void), Xqdol(void), Xdup(void);
extern void Xexit(void), Xfalse(void), Xfn(void), Xfor(void), Xglob(void);
extern void Xjump(void), Xmark(void), Xmatch(void), Xpipe(void), Xread(void);
extern void Xunredir(void), Xstar(void), Xreturn(void), Xsubshell(void);
extern void Xtrue(void), Xword(void), Xwrite(void), Xpipefd(void), Xcase(void);
extern void Xlocal(void), Xunlocal(void), Xassign(void), Xsimple(void), Xpopm(void);
extern void Xrdcmds(void), Xwastrue(void), Xif(void), Xifnot(void), Xpipewait(void);
extern void Xdelhere(void), Xpopredir(void), Xsub(void), Xeflag(void), Xsettrue(void);
extern void Xerror(char*), Xperror(char*);

/* word.c */
Word	*newword(char*, Word*);
void	pushlist(void);
void	poplist(void);
void	pushword(char*);
void	popword(void);
int	count(Word*);
Word	*copywords(Word*, Word*);
void	pushredir(int, int, int);
void	turfredir(void);
char	*list2str(Word*);
void	freelist(Word*);
Word	*conclist(Word*, Word*, Word*);
Word  	*subwords(Word*, int, Word*, Word*);

/* io.c */
#define	pchr(b, c) if((b)->bufp==(b)->ebuf)fullbuf((b), (c));else (*(b)->bufp++=(c))
#define	rchr(b) ((b)->bufp==(b)->ebuf?emptybuf(b):(*(b)->bufp++&0xff))

Io	*openfd(int), *openstr(void), *opencore(char*, int);
int	emptybuf(Io*);
void	closeio(Io*);
void	flush(Io*);
int	fullbuf(Io*, int);

void	pfmt(Io*, char*, ...);
void	perr(Io*);
void	pstr(Io*, char*);
void	pfnc(Io*, Thread*);

void	pprompt(void);

/* trap.c */
void	dotrap(void);
void	dointr(void);

void	waitfor(uint);

/* nt.c */

Direntry* readdirect(char*);
void	fatal(char*, ...);
uint	proc(char**, int, int, int);
int	procwait(uint);
int	refinc(Ref*);
int	refdec(Ref*);
int	pipe(int*);

/*
 * onebyte(c), twobyte(c), threebyte(c)
 * Is c the first character of a one- two- or three-byte utf sequence?
 */
#define	onebyte(c)	((c&0x80)==0x00)
#define	twobyte(c)	((c&0xe0)==0xc0)
#define	threebyte(c)	((c&0xf0)==0xe0)

#define	new(type)	((type *)malloc(sizeof(type)))


extern Tree	*cmdtree;
extern Thread	*runq;
extern Io	*err;
extern int	flag[256];
extern int	doprompt;
extern char	*promptstr;
extern int	ndot;
extern int	nerror;
extern Code	*codebuf;
extern int	eflagok;
extern int	interrupted;
extern Ref	ntrap;
