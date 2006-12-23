#include <lib9.h>
#include <bio.h>
#include <ctype.h>

#ifndef	EXTERN
#define EXTERN	extern
#endif

typedef	struct	Node	Node;
typedef	struct	Sym	Sym;
typedef	struct	Type	Type;
typedef	struct	Decl	Decl;
typedef	struct	Io	Io;
typedef	struct	Hist	Hist;
typedef	struct	Term	Term;
typedef	struct	Init	Init;
typedef	struct	Bits	Bits;

#define	NHUNK		50000L
#define	BUFSIZ		8192
#define	NSYMB		500
#define	NHASH		1024
#define	STRINGSZ	200
#define	HISTSZ		20
#define YYMAXDEPTH	500
#define	NTERM		10
#define	MAXALIGN	7

#define	SIGN(n)		((vlong)1<<(n-1))
#define	MASK(n)		(SIGN(n)|(SIGN(n)-1))

#define	BITS	5
#define	NVAR	(BITS*sizeof(ulong)*8)
struct	Bits
{
	ulong	b[BITS];
};

EXTERN	int	lastnumbase;

#define KNIL	0
#define KCHR	1
#define KOCT	2
#define KDEC	3
#define KHEX	4
#define KEXP	5
#define KDROP	6
#define KLAST	7

struct	Node
{
	Node*	left;
	Node*	right;
	double	fconst;		/* fp constant */
	vlong	vconst;		/* non fp const */
	char*	cstring;	/* character string */
	ushort*	rstring;	/* rune string */

	Sym*	sym;
	Type*	type;
	long	lineno;
	char	op;
	char	garb;
	char kind;
	char blk;
};
#define	Z	((Node*)0)
#define	ZZ	((Node*)-1)

struct	Sym
{
	Sym*	link;
	Type*	type;
	Type*	suetag;
	Type*	tenum;
	char*	macro;
	long	lineno;
	long	offset;
	vlong	vconst;
	double	fconst;
	Node*	nconst;
	char*	cstring;
	Node*	label;
	char	*name;
	char *lname;
	char *mod;
	ushort	lexical;
	ushort	block;
	ushort	sueblock;
	char	class;
	char kind;
	char lkw;
	char	args;
	char	fd;
	char limbo;
};
#define	S	((Sym*)0)

struct	Decl
{
	Decl*	link;
	Sym*	sym;
	Type*	type;
	long	offset;
	long	lineno;
	short	val;
	ushort	block;
	char	class;
};
#define	D	((Decl*)0)

struct	Type
{
	Sym*	sym;
	Sym*	tag;
	Type*	link;
	Type*	down;
	Node*	nwidth;
	long	width;
	long	offset;
	long	lineno;
	char	shift;
	char	nbits;
	char	etype;
	char	garb;
	char vis;
	char	mark;
};
#define	T	((Type*)0)
#define	NODECL	((void(*)(int, Type*, Sym*))0)

struct	Init			/* general purpose initialization */
{
	int	code;
	ulong	value;
	char*	s;
};

EXTERN struct
{
	char*	p;
	int	c;
} fi;

struct	Io
{
	Io*	link;
	char*	p;
	char	b[BUFSIZ];
	short	c;
	short	f;
};
#define	I	((Io*)0)

struct	Hist
{
	Hist*	link;
	char*	name;
	long	line;
	long	offset;
};
#define	H	((Hist*)0)
EXTERN Hist*	hist;

struct	Term
{
	vlong	mult;
	Node	*node;
};

enum
{
	Axxx,
	Ael1,
	Ael2,
	Asu2,
	Aarg0,
	Aarg1,
	Aarg2,
	Aaut3,
	NALIGN,
};

enum				/* also in ../{8a,0a}.h */
{
	Plan9	= 1<<0,
	Unix	= 1<<1,
	Windows	= 1<<2,
};

enum
{
	DMARK,
	DAUTO,
	DSUE,
	DLABEL,
};
enum
{
	ONOOP,
	OXXX,
	OADD,
	OADDR,
	OAND,
	OANDAND,
	OARRAY,
	OAS,
	OASI,
	OASADD,
	OASAND,
	OASASHL,
	OASASHR,
	OASDIV,
	OASHL,
	OASHR,
	OASLDIV,
	OASLMOD,
	OASLMUL,
	OASLSHR,
	OASMOD,
	OASMUL,
	OASOR,
	OASSUB,
	OASXOR,
	OBIT,
	OBREAK,
	OCASE,
	OCAST,
	OCOMMA,
	OCOND,
	OCONST,
	OCONTINUE,
	ODIV,
	ODOT,
	ODOTDOT,
	ODWHILE,
	OENUM,
	OEQ,
	OFOR,
	OFUNC,
	OGE,
	OGOTO,
	OGT,
	OHI,
	OHS,
	OIF,
	OIND,
	OINDREG,
	OINIT,
	OLABEL,
	OLDIV,
	OLE,
	OLIST,
	OLMOD,
	OLMUL,
	OLO,
	OLS,
	OLSHR,
	OLT,
	OMOD,
	OMUL,
	ONAME,
	ONE,
	ONOT,
	OOR,
	OOROR,
	OPOSTDEC,
	OPOSTINC,
	OPREDEC,
	OPREINC,
	OPROTO,
	OREGISTER,
	ORETURN,
	OSET,
	OSIGN,
	OSIZE,
	OSTRING,
	OLSTRING,
	OSTRUCT,
	OSUB,
	OSWITCH,
	OUNION,
	OUSED,
	OWHILE,
	OXOR,
	ONEG,
	OCOM,
	OELEM,

	OTST,		/* used in some compilers */
	OINDEX,
	OFAS,

	OBLK,
	OPOS,
	ONUL,
	ODOTIND,
	OARRIND,
	ODAS,
	OASD,
	OIOTA,
	OLEN,
	OBRACKET,
	OREF,
	OARRAYOF,
	OSLICE,
	OSADDR,
	ONIL,
	OS2AB,
	OAB2S,
	OFILDES,
	OFD,
	OTUPLE,
	OT0,
	ORETV,
	OCAT,
	OSBREAK,
	OLDOT,
	OMDOT,

	OCODE,
	ODECE,
	ODECT,
	ODECV,
	ODECF,
	OPUSH,
	OPOP,

	OEND
};
enum
{
	TXXX,
	TCHAR,
	TUCHAR,
	TSHORT,
	TUSHORT,
	TINT,
	TUINT,
	TLONG,
	TULONG,
	TVLONG,
	TUVLONG,
	TFLOAT,
	TDOUBLE,
	TIND,
	TFUNC,
	TARRAY,
	TVOID,
	TSTRUCT,
	TUNION,
	TENUM,
	NTYPE,

	TAUTO	= NTYPE,
	TEXTERN,
	TSTATIC,
	TTYPEDEF,
	TREGISTER,
	TCONSTNT,
	TVOLATILE,
	TUNSIGNED,
	TSIGNED,
	TDOT,
	TFILE,
	TOLD,

	TSTRING,
	TFD,
	TTUPLE,

	NALLTYPES,
};
enum
{
	CXXX,
	CAUTO,
	CEXTERN,
	CGLOBL,
	CSTATIC,
	CLOCAL,
	CTYPEDEF,
	CPARAM,
	CSELEM,
	CLABEL,
	CEXREG,
	NCTYPES,
};
enum
{
	GXXX		= 0,
	GCONSTNT	= 1<<0,
	GVOLATILE	= 1<<1,
	NGTYPES		= 1<<2,
};
enum
{
	BCHAR		= 1L<<TCHAR,
	BUCHAR		= 1L<<TUCHAR,
	BSHORT		= 1L<<TSHORT,
	BUSHORT		= 1L<<TUSHORT,
	BINT		= 1L<<TINT,
	BUINT		= 1L<<TUINT,
	BLONG		= 1L<<TLONG,
	BULONG		= 1L<<TULONG,
	BVLONG		= 1L<<TVLONG,
	BUVLONG		= 1L<<TUVLONG,
	BFLOAT		= 1L<<TFLOAT,
	BDOUBLE		= 1L<<TDOUBLE,
	BIND		= 1L<<TIND,
	BFUNC		= 1L<<TFUNC,
	BARRAY		= 1L<<TARRAY,
	BVOID		= 1L<<TVOID,
	BSTRUCT		= 1L<<TSTRUCT,
	BUNION		= 1L<<TUNION,
	BENUM		= 1L<<TENUM,
	BFILE		= 1L<<TFILE,
	BOLD		= 1L<<TOLD,
	BDOT		= 1L<<TDOT,
	BCONSTNT	= 1L<<TCONSTNT,
	BVOLATILE	= 1L<<TVOLATILE,
	BUNSIGNED	= 1L<<TUNSIGNED,
	BSIGNED		= 1L<<TSIGNED,
	BAUTO		= 1L<<TAUTO,
	BEXTERN		= 1L<<TEXTERN,
	BSTATIC		= 1L<<TSTATIC,
	BTYPEDEF	= 1L<<TTYPEDEF,
	BREGISTER	= 1L<<TREGISTER,

	BINTEGER	= BCHAR|BUCHAR|BSHORT|BUSHORT|BINT|BUINT|
				BLONG|BULONG|BVLONG|BUVLONG,
	BNUMBER		= BINTEGER|BFLOAT|BDOUBLE,

/* these can be overloaded with complex types */

	BCLASS		= BAUTO|BEXTERN|BSTATIC|BTYPEDEF|BREGISTER,

	BGARB		= BCONSTNT|BVOLATILE,
};

EXTERN struct
{
	Type*	tenum;		/* type of entire enum */
	Type*	cenum;		/* type of current enum run */
	vlong	lastenum;	/* value of current enum */
	double	floatenum;	/* value of current enum */
} en;

EXTERN	int	autobn;
EXTERN	long	autoffset;
EXTERN	int	blockno;
EXTERN	int	comm;
EXTERN	Decl*	dclstack;
EXTERN	int	doaddr;
EXTERN	int	doalladdr;
EXTERN	int	doinc;
EXTERN	int	doloc;
EXTERN	int	domod;
EXTERN	Hist*	ehist;
EXTERN	long	firstbit;
EXTERN	Decl*	firstdcl;
EXTERN	int	fperror;
EXTERN	Sym*	hash[NHASH];
EXTERN	char*	hunk;
EXTERN	char*	include[20];
EXTERN	Type*	fdtype;
EXTERN	int	inmain;
EXTERN	Io*	iofree;
EXTERN	Io*	ionext;
EXTERN	Io*	iostack;
EXTERN	int	justcode;
EXTERN	long	lastbit;
EXTERN	char	lastclass;
EXTERN	Type*	lastdcl;
EXTERN	long	lastfield;
EXTERN	Type*	lasttype;
EXTERN	long	lineno;
EXTERN	long	nearln;
EXTERN	int	nerrors;
EXTERN	int	newflag;
EXTERN	long	nhunk;
EXTERN	int	ninclude;
EXTERN	Node*	nodproto;
EXTERN	Node*	nodcast;
EXTERN	int	passes;
EXTERN	char*	pathname;
EXTERN	int	peekc;
EXTERN	Type*	pfdtype;
EXTERN	long	pline;
EXTERN	long	saveline;
EXTERN	Type*	strf;
EXTERN	int	strings;
EXTERN	Type*	stringtype;
EXTERN	Type*	strl;
EXTERN	char	symb[NSYMB];
EXTERN	Sym*	symstring;
EXTERN	int	taggen;
EXTERN	Type*	tfield;
EXTERN	Type*	tufield;
EXTERN	int	thechar;
EXTERN	char*	thestring;
EXTERN	Type*	thisfn;
EXTERN	long	thunk;
EXTERN	Type*	types[NTYPE];
EXTERN	Node*	initlist;
EXTERN	int	nterm;
EXTERN	int	hjdickflg;
EXTERN	int	fproundflg;
EXTERN	Bits	zbits;

extern	char	*onames[], *tnames[], *gnames[];
extern	char	*cnames[], *qnames[], *bnames[];
extern	char	tab[NTYPE][NTYPE];
extern	char	comrel[], invrel[], logrel[];
extern	long	ncast[], tadd[], tand[];
extern	long	targ[], tasadd[], tasign[], tcast[];
extern	long	tdot[], tfunct[], tindir[], tmul[];
extern	long	tnot[], trel[], tsub[];

extern	char	typeaf[];
extern	char	typefd[];
extern	char	typei[];
extern	char	typesu[];
extern	char	typesuv[];
extern	char	typeu[];
extern	char	typev[];
extern	char	typec[];
extern	char	typeh[];
extern	char	typeil[];
extern	char	typeilp[];
extern	char	typechl[];
extern	char	typechlp[];
extern	char	typechlpfd[];

extern	ulong	thash1;
extern	ulong	thash2;
extern	ulong	thash3;
extern	ulong	thash[];

/*
 *	Inferno.c/Posix.c/Nt.c
 */
int	mywait(int*);
int	mycreat(char*, int);
int	systemtype(int);
int	pathchar(void);
char*	mygetwd(char*, int);
int	myexec(char*, char*[]);
int	mydup(int, int);
int	myfork(void);
int	mypipe(int*);
void*	mysbrk(ulong);

/*
 *	parser
 */
int	yyparse(void);
int	mpatof(char*, double*);
int	mpatov(char*, vlong*);

/*
 *	lex.c
 */
void*	allocn(void*, long, long);
void*	alloc(long);
void	cinit(void);
int	compile(char*, char**, int);
void	errorexit(void);
int	filbuf(void);
int	getc(void);
long	getr(void);
int	getnsc(void);
Sym*	lookup(void);
void	main(int, char*[]);
void	newfile(char*, int);
void	newio(void);
void	outbegin(char *);
void	outend(void);
void	outfun(Node*);
void	pushio(void);
long	escchar(long, int, int);
Sym*	slookup(char*);
void	syminit(Sym*);
void	unget(int);
long	yylex(void);
int	Lconv(Fmt*);
int	Tconv(Fmt*);
int	FNconv(Fmt*);
int	Oconv(Fmt*);
int	Qconv(Fmt*);
int	VBconv(Fmt*);
void	setinclude(char*);

/*
 * mac.c
 */
void	dodefine(char*);
void	domacro(void);
Sym*	getsym(void);
long	getnsn(void);
void	linehist(char*, int);
void	macdef(void);
void	macprag(void);
void	macend(void);
void	macexpand(Sym*, char*);
void	macif(int);
void	macinc(void);
void	maclin(void);
void	macund(void);

/*
 * dcl.c
 */
Node*	doinit(Sym*, Type*, long, Node*);
Type*	tcopy(Type*);
void	init1(Sym*, Type*, long, int);
Node*	newlist(Node*, Node*);
void	adecl(int, Type*, Sym*);
int	anyproto(Node*);
void	argmark(Node*, int);
void	dbgdecl(Sym*);
Node*	dcllabel(Sym*, int);
Node*	dodecl(void(*)(int, Type*, Sym*), int, Type*, Node*, int);
Sym*	mkstatic(Sym*);
void	doenum(Sym*, Node*);
void	snap(Type*);
Type*	dotag(Sym*, int, int);
void	edecl(int, Type*, Sym*);
Type*	fnproto(Node*);
Type*	fnproto1(Node*);
void	markdcl(void);
Type*	paramconv(Type*, int);
void	pdecl(int, Type*, Sym*);
Decl*	push(void);
Decl*	push1(Sym*);
Node*	revertdcl(void);
#undef round
#define	round	ccround
long	round(long, int);
int	rsametype(Type*, Type*, int, int);
int	sametype(Type*, Type*);
ulong	signature(Type*, int);
void	suallign(Type*);
void	tmerge(Type*, Sym*);
void	walkparam(Node*, int);
void	xdecl(int, Type*, Sym*);
Node*	contig(Sym*, Node*, long);

/*
 * com.c
 */
void	ccom(Node*);
void	complex(Node*);
int	tcom(Node*);
int	tcoma(Node*, Node*, Type*, int);
int	tcomd(Node*, Type*);
int	tcomo(Node*, int);
int	tcomx(Node*);
int	tlvalue(Node*);
void	constas(Node*, Type*, Type*);

/*
 * con.c
 */
void	acom(Node*);
void	acom1(vlong, Node*);
void	acom2(Node*, Type*);
int	acomcmp1(const void*, const void*);
int	acomcmp2(const void*, const void*);
int	addo(Node*);
void	evconst(Node*);

/*
 * sub.c
 */
void	arith(Node*, int);
Type*	dotsearch(Sym*, Type*, Node*);
long	dotoffset(Type*, Type*, Node*);
void	gethunk(void);
Node*	invert(Node*);
int	bitno(long);
void	makedot(Node*, Type*, long);
Node*	new(int, Node*, Node*);
Node*	new1(int, Node*, Node*);
int	nilcast(Type*, Type*);
int	nocast(Type*, Type*);
void	prtree(Node*, char*);
void	prtree1(Node*, int, int);
void	relcon(Node*, Node*);
int	relindex(int);
int	simpleg(long);
Type*	garbt(Type*, long);
int	simplec(long);
Type*	simplet(long);
int	stcompat(Node*, Type*, Type*, long[]);
int	tcompat(Node*, Type*, Type*, long[]);
void	tinit(void);
Type*	typ(int, Type*);
Type*	typ1(int, Type*);
void	typeext(Type*, Node*);
void	typeext1(Type*, Node*);
int	side(Node*);
int	vconst(Node*);
int	vlog(Node*);
int	topbit(ulong);
long	typebitor(long, long);
void	diag(Node*, char*, ...);
void	warn(Node*, char*, ...);
void	yyerror(char*, ...);
void	fatal(Node*, char*, ...);

/*
 * acid.c
 */
void	acidtype(Type*);
void	acidvar(Sym*);

/*
 * bits.c
 */
Bits	bor(Bits, Bits);
Bits	band(Bits, Bits);
Bits	bnot(Bits);
int	bany(Bits*);
int	bnum(Bits);
Bits	blsh(uint);
int	beq(Bits, Bits);
int	bset(Bits, uint);

/*
 * dpchk.c
 */
void	dpcheck(Node*);
void	arginit(void);
void	pragvararg(void);
void	praghjdicks(void);
void	pragfpround(void);

/*
 * calls to machine depend part
 */
void	codgen(Node*, Node*, int);
void	gclean(void);
void	gextern(Sym*, Node*, long, long);
void	ginit(void);
long	outstring(char*, long);
long	outlstring(ushort*, long);
void	sextern(Sym*, Node*, long, long);
void	xcom(Node*);
long	exreg(Type*);
long	align(long, Type*, int);
long	maxround(long, long);

extern	schar	ewidth[];

/*
 * com64
 */
int	com64(Node*);
void	com64init(void);
void	bool64(Node*);
double	convvtof(vlong);
vlong	convftov(double);
double	convftox(double, int);
vlong	convvtox(vlong, int);

#pragma	varargck	argpos	warn	2
#pragma	varargck	argpos	diag	2
#pragma	varargck	argpos	yyerror	1

#pragma	varargck	type	"F"	Node*
#pragma	varargck	type	"L"	long
#pragma	varargck	type	"Q"	long
#pragma	varargck	type	"O"	int
#pragma	varargck	type	"T"	Type*
#pragma	varargck	type	"|"	int

/* output routines */

void prline(char*);
void prstr(char *);
void prlstr(ushort *);
void prkeywd(char *);
void prid(char *);
void	prsym(Sym*, int);
void	prsym0(Sym*);
void prdelim(char *);
void prchar(vlong);
void prreal(double, char*, int);
void prnum(vlong, int, Type*);
void	prcom(char *, Node*);
void newline(void);
void incind(void);
void decind(void);
int	zeroind(void);
void	restoreind(int);
void startcom(int);
void	addcom(int);
void	endcom(void);
int	outcom(int);
int	arrow(Sym*);

/* limbo generating routines */

void pgen(int);
void epgen(int);
void ttgen(Type*);
void vtgen(Node*);
void etgen(Sym*);
void expgen(Node*);

/* -m routines */

void	newsec(int);

void outpush(char*);
void outpop(int);
void outpush0(char*, Node*);
void outpop0(int);
void outpush2(char*, Node*);
void outpop2(int);
char*	outmod(char*, int);

/* miscellaneous */

int iscon(char*);
Node* ncopy(Node*);
void doasenum(Sym*);
Type *maxtype(Type*, Type*);

void	linit(void);
void	sysinit(void);

int ism(void);
int isb(void);
int dolog(void);

int line(Node*);

void	output(long, int);
void usemod(Sym*, int);
void setmod(Sym*);

int	exists(char*);
int	isconsym(Sym *);

void clbegin(void);
void clend(void);

int gfltconv(Fmt*);
