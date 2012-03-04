#define _POSIX_SOURCE
#define	_POSIX_C_SOURCE	1
#define _LARGEFILE64_SOURCE	1
#define _FILE_OFFSET_BITS 64
#include <stdlib.h>
#include <stdarg.h>
#include <errno.h>
#include <string.h>
#include "math.h"
#include <fcntl.h>
#include <setjmp.h>
#include <float.h>

#define	getwd	infgetwd

/*
 * math/dtoa.c
 */
#define __LITTLE_ENDIAN

#define	nil		((void*)0)

typedef unsigned char	uchar;
typedef unsigned int	uint;
typedef unsigned long	ulong;
typedef signed char	schar;
typedef unsigned short	ushort;
typedef unsigned short	Rune;
typedef long long int	vlong;
typedef unsigned long long int	uvlong;
typedef unsigned int	mpdigit;	/* for /sys/include/mp.h */
typedef unsigned short u16int;
typedef unsigned char u8int;
typedef unsigned long uintptr;

typedef signed char	int8;
typedef unsigned char	uint8;
typedef short	int16;
typedef unsigned short	uint16;
typedef int	int32;
typedef unsigned int	uint32;
typedef long long	int64;
typedef unsigned long long	uint64;

#define	USED(x)		if(x);else
#define	SET(x)

#define nelem(x)	(sizeof(x)/sizeof((x)[0]))

/*
 * mem and string routines are declared by ANSI/POSIX files above
 */

enum
{
	UTFmax		= 3,		/* maximum bytes per rune */
	Runesync	= 0x80,		/* cannot represent part of a UTF sequence (<) */
	Runeself	= 0x80,		/* rune and UTF sequences are the same (<) */
	Runeerror	= 0x80		/* decoding error in UTF */
};

/*
 * rune routines
 */
extern	int	runetochar(char*, Rune*);
extern	int	chartorune(Rune*, char*);
extern	int	runelen(long);
extern	int	runenlen(Rune*, int);
extern	int	fullrune(char*, int);
extern	int	utflen(char*);
extern	int	utfnlen(char*, long);
extern	char*	utfrune(char*, long);
extern	char*	utfrrune(char*, long);
extern	char*	utfutf(char*, char*);
extern	char*	utfecpy(char*, char*, char*);

extern	Rune*	runestrcat(Rune*, Rune*);
extern	Rune*	runestrchr(Rune*, Rune);
extern	int	runestrcmp(Rune*, Rune*);
extern	Rune*	runestrcpy(Rune*, Rune*);
extern	Rune*	runestrncpy(Rune*, Rune*, long);
extern	Rune*	runestrecpy(Rune*, Rune*, Rune*);
extern	Rune*	runestrdup(Rune*);
extern	Rune*	runestrncat(Rune*, Rune*, long);
extern	int	runestrncmp(Rune*, Rune*, long);
extern	Rune*	runestrrchr(Rune*, Rune);
extern	long	runestrlen(Rune*);
extern	Rune*	runestrstr(Rune*, Rune*);

extern	Rune	tolowerrune(Rune);
extern	Rune	totitlerune(Rune);
extern	Rune	toupperrune(Rune);
extern	int	isalpharune(Rune);
extern	int	islowerrune(Rune);
extern	int	isspacerune(Rune);
extern	int	istitlerune(Rune);
extern	int	isupperrune(Rune);

/*
 * malloc
 */
extern	void*	malloc(size_t);
extern	void*	mallocz(ulong, int);
extern	void	free(void*);
extern	ulong	msize(void*);
extern	void*	calloc(size_t, size_t);
extern	void*	realloc(void*, size_t);
extern	void		setmalloctag(void*, ulong);
extern	void		setrealloctag(void*, ulong);
extern	ulong	getmalloctag(void*);
extern	ulong	getrealloctag(void*);
extern	void*	malloctopoolblock(void*);

extern	int	getfields(char*, char**, int, int, char*);
extern	uintptr	getcallerpc(void*);

/*
 * print routines
 */
typedef struct Fmt	Fmt;
struct Fmt{
	uchar	runes;			/* output buffer is runes or chars? */
	void	*start;			/* of buffer */
	void	*to;			/* current place in the buffer */
	void	*stop;			/* end of the buffer; overwritten if flush fails */
	int	(*flush)(Fmt *);	/* called when to == stop */
	void	*farg;			/* to make flush a closure */
	int	nfmt;			/* num chars formatted so far */
	va_list	args;			/* args passed to dofmt */
	int	r;			/* % format Rune */
	int	width;
	int	prec;
	ulong	flags;
};

enum{
	FmtWidth	= 1,
	FmtLeft		= FmtWidth << 1,
	FmtPrec		= FmtLeft << 1,
	FmtSharp	= FmtPrec << 1,
	FmtSpace	= FmtSharp << 1,
	FmtSign		= FmtSpace << 1,
	FmtZero		= FmtSign << 1,
	FmtUnsigned	= FmtZero << 1,
	FmtShort	= FmtUnsigned << 1,
	FmtLong		= FmtShort << 1,
	FmtVLong	= FmtLong << 1,
	FmtComma	= FmtVLong << 1,
	FmtByte	= FmtComma << 1,

	FmtFlag		= FmtByte << 1
};

extern	int	print(char*, ...);
extern	char*	seprint(char*, char*, char*, ...);
extern	char*	vseprint(char*, char*, char*, va_list);
extern	int	snprint(char*, int, char*, ...);
extern	int	vsnprint(char*, int, char*, va_list);
extern	char*	smprint(char*, ...);
extern	char*	vsmprint(char*, va_list);
extern	int	sprint(char*, char*, ...);
extern	int	fprint(int, char*, ...);
extern	int	vfprint(int, char*, va_list);

extern	int	runesprint(Rune*, char*, ...);
extern	int	runesnprint(Rune*, int, char*, ...);
extern	int	runevsnprint(Rune*, int, char*, va_list);
extern	Rune*	runeseprint(Rune*, Rune*, char*, ...);
extern	Rune*	runevseprint(Rune*, Rune*, char*, va_list);
extern	Rune*	runesmprint(char*, ...);
extern	Rune*	runevsmprint(char*, va_list);

extern	int	fmtfdinit(Fmt*, int, char*, int);
extern	int	fmtfdflush(Fmt*);
extern	int	fmtstrinit(Fmt*);
extern	char*	fmtstrflush(Fmt*);
extern	int	runefmtstrinit(Fmt*);
extern	Rune*	runefmtstrflush(Fmt*);

extern	int	fmtinstall(int, int (*)(Fmt*));
extern	int	dofmt(Fmt*, char*);
extern	int	dorfmt(Fmt*, Rune*);
extern	int	fmtprint(Fmt*, char*, ...);
extern	int	fmtvprint(Fmt*, char*, va_list);
extern	int	fmtrune(Fmt*, int);
extern	int	fmtstrcpy(Fmt*, char*);
extern	int	fmtrunestrcpy(Fmt*, Rune*);
/*
 * error string for %r
 * supplied on per os basis, not part of fmt library
 */
extern	int	errfmt(Fmt *f);

/*
 * quoted strings
 */
extern	char	*unquotestrdup(char*);
extern	Rune	*unquoterunestrdup(Rune*);
extern	char	*quotestrdup(char*);
extern	Rune	*quoterunestrdup(Rune*);
extern	int	quotestrfmt(Fmt*);
extern	int	quoterunestrfmt(Fmt*);
extern	void	quotefmtinstall(void);
extern	int	(*doquote)(int);

extern	char*	strdup(const char*);
extern	int	tokenize(char*, char**, int);
extern	vlong	strtoll(const char*, char**, int);
#define	qsort	infqsort
extern	void	qsort(void*, long, long, int (*)(void*, void*));

extern	int	isNaN(double);
extern	int	isInf(double, int);

/*
 * Time-of-day
 */

typedef struct Tm Tm;
struct Tm {
	int	sec;
	int	min;
	int	hour;
	int	mday;
	int	mon;
	int	year;
	int	wday;
	int	yday;
	char	zone[4];
};
	
/*
 * one-of-a-kind
 */
extern	int	getfields(char*, char**, int, int, char*);
extern	char*	getuser(void);
extern	char*	getwd(char*, int);
extern	double	pow10(int);
extern	double	ipow10(int);
extern	vlong	strtoll(const char*, char**, int);
extern	uvlong	strtoull(const char*, char**, int);
extern	void	sysfatal(char*, ...);
extern	int	dec64(uchar*, int, char*, int);
extern	int	enc64(char*, int, uchar*, int);
extern	int	dec32(uchar*, int, char*, int);
extern	int	enc32(char*, int, uchar*, int);
extern	int	dec16(uchar*, int, char*, int);
extern	int	enc16(char*, int, uchar*, int);
extern	int	encodefmt(Fmt*);

/*
 *  synchronization
 */
typedef
struct Lock {
	int	val;
	int	pid;
} Lock;

extern int	_tas(int*);

extern	void	lock(Lock*);
extern	void	unlock(Lock*);
extern	int	canlock(Lock*);

typedef struct QLock QLock;
struct QLock
{
	Lock	use;			/* to access Qlock structure */
	Proc	*head;			/* next process waiting for object */
	Proc	*tail;			/* last process waiting for object */
	int	locked;			/* flag */
};

extern	void	qlock(QLock*);
extern	void	qunlock(QLock*);
extern	int	canqlock(QLock*);
extern	void	_qlockinit(ulong (*)(ulong, ulong));	/* called only by the thread library */

typedef
struct RWLock
{
	Lock	l;			/* Lock modify lock */
	QLock	x;			/* Mutual exclusion lock */
	QLock	k;			/* Lock for waiting writers */
	int	readers;		/* Count of readers in lock */
} RWLock;

extern	int	canrlock(RWLock*);
extern	int	canwlock(RWLock*);
extern	void	rlock(RWLock*);
extern	void	runlock(RWLock*);
extern	void	wlock(RWLock*);
extern	void	wunlock(RWLock*);

/*
 * system calls
 *
 */
enum
{
	NAMELEN	= 28,
	ERRLEN	= 64,
	ERRMAX = 128,
	DIRLEN	= 116
};

#define CHDIR		0x80000000	/* mode bit for directories */
#define CHAPPEND	0x40000000	/* mode bit for append only files */
#define CHEXCL		0x20000000	/* mode bit for exclusive use files */
#define CHMOUNT		0x10000000	/* mode bit for mounted channel */
#define CHREAD		0x4		/* mode bit for read permission */
#define CHWRITE		0x2		/* mode bit for write permission */
#define CHEXEC		0x1		/* mode bit for execute permission */

#define	MORDER		0x0003		/* mask for bits defining order of mounting */
#define	MREPL		0x0000		/* mount replaces object */
#define	MBEFORE		0x0001		/* mount goes before others in union directory */
#define	MAFTER		0x0002		/* mount goes after others in union directory */
#define	MCREATE		0x0004		/* permit creation in mounted directory */
#define	MCACHE	0x0010	/* cache some data */
#define	MMASK		0x0007		/* all bits on */

#define	OREAD		0		/* open for read */
#define	OWRITE		1		/* write */
#define	ORDWR		2		/* read and write */
#define	OEXEC		3		/* execute, == read but check execute permission */
#define	OTRUNC		16		/* or'ed in (except for exec), truncate file first */
#define	OCEXEC		32		/* or'ed in, close on exec */
#define	ORCLOSE		64		/* or'ed in, remove on close */
#define	OEXCL	0x1000	/* or'ed in, exclusive use (create only) */

typedef
struct Qid
{
	ulong	path;
	ulong	vers;
} Qid;

typedef
struct Dir
{
	char	name[NAMELEN];
	char	uid[NAMELEN];
	char	gid[NAMELEN];
	Qid	qid;
	ulong	mode;
	int	atime;
	int	mtime;
	vlong	length;
	ushort	type;
	ushort	dev;
} Dir;

extern	int	dirfstat(int, Dir*);
extern	int	dirstat(char*, Dir*);
extern	int	dirfwstat(int, Dir*);
extern	int	dirwstat(char*, Dir*);

extern	char*	cleanname(char*);
extern	void	exits(char*);
extern	void	_exits(char*);
extern	int	create(char*, int, int);

extern	char*	getuser(void);
extern	char*	getwd(char*, int);

extern	int	errstr(char*, uint);
extern	void	werrstr(char*, ...);

#define	ARGBEGIN	for(argv++,argc--;\
			    argv[0] && argv[0][0]=='-' && argv[0][1];\
			    argc--, argv++) {\
				char *_args, *_argt;\
				char _argc;\
				_args = &argv[0][1];\
				if(_args[0]=='-' && _args[1]==0){\
					argc--; argv++; break;\
				}\
				_argc = 0;\
				while((_argc = *_args++)!='\0')\
				switch(_argc)
#define	ARGEND		}
#define	ARGF()		(_argt=_args, _args="",\
				(*_argt? _argt: argv[1]? (argc--, *++argv): 0))
#define	ARGC()		_argc

/*
 *	Extensions for Inferno to basic libc.h
 */

#define	setbinmode()

