#include "lib9.h"
#include "bio.h"
#include "isa.h"
#include "mathi.h"

/* internal dis ops */
#define IEXC	MAXDIS
#define IEXC0	(MAXDIS+1)
#define INOOP	(MAXDIS+2)

/* temporary */
#define	LDT	1

#ifndef Extern
#define Extern extern
#endif

#define YYMAXDEPTH	200

typedef	struct Addr	Addr;
typedef	struct Case	Case;
typedef	struct Decl	Decl;
typedef	struct Desc	Desc;
typedef	struct Dlist	Dlist;
typedef	struct Except	Except;
typedef struct File	File;
typedef struct Fline	Fline;
typedef	struct Inst	Inst;
typedef	struct Label	Label;
typedef	struct Line	Line;
typedef	struct Node	Node;
typedef struct Ok	Ok;
typedef	struct Src	Src;
typedef	struct Sym	Sym;
typedef struct Szal	Szal;
typedef	struct Tattr	Tattr;
typedef	struct Teq	Teq;
typedef	struct Tpair	Tpair;
typedef	struct Type	Type;
typedef	struct Typelist	Typelist;

typedef	double		Real;
typedef	vlong		Long;

enum
{
	STemp		= NREG * IBY2WD,
	RTemp		= STemp+IBY2WD,
	DTemp		= RTemp+IBY2WD,
	MaxTemp		= DTemp+IBY2WD,
	MaxReg		= 1<<16,
	MaxAlign	= IBY2LG,
	StrSize		= 256,
	NumSize		= 32,		/* max length of printed  */
	MaxIncPath	= 32,		/* max directories in include path */
	MaxScope	= 64,		/* max nested {} */
	MaxInclude	= 32,		/* max nested include "" */
	ScopeBuiltin	= 0,
	ScopeNils	= 1,
	ScopeGlobal	= 2
};

/*
 * return tuple from expression type checking
 */
struct Ok
{
	int	ok;
	int	allok;
};

/*
 * return tuple from type sizing
 */
struct Szal
{
	int	size;
	int	align;
};

/*
 * return tuple for file/line numbering
 */
struct Fline
{
	File	*file;
	int	line;
};

struct File
{
	char	*name;
	int	abs;			/* absolute line of start of the part of file */
	int	off;			/* offset to line in the file */
	int	in;			/* absolute line where included */
	char	*act;			/* name of real file with #line fake file */
	int	actoff;			/* offset from fake line to real line */
	int	sbl;			/* symbol file number */
};

struct Line
{
	int	line;
	int	pos;			/* character within the line */
};

struct Src
{
	Line	start;
	Line	stop;
};

enum
{
	Aimm,				/* immediate */
	Amp,				/* global */
	Ampind,				/* global indirect */
	Afp,				/* activation frame */
	Afpind,				/* frame indirect */
	Apc,				/* branch */
	Adesc,				/* type descriptor immediate */
	Aoff,				/* offset in module description table */
	Anoff,			/* above encoded as -ve */
	Aerr,				/* error */
	Anone,				/* no operand */
	Aldt,				/* linkage descriptor table immediate */
	Aend
};

struct Addr
{
	long	reg;
	long	offset;
	Decl	*decl;
};

struct Inst
{
	Src	src;
	ushort	op;
	long	pc;
	uchar	reach;			/* could a control path reach this instruction? */
	uchar	sm;			/* operand addressing modes */
	uchar	mm;
	uchar	dm;
	Addr	s;			/* operands */
	Addr	m;
	Addr	d;
	Inst	*branch;		/* branch destination */
	Inst	*next;
	int	block;			/* blocks nested inside */
};

struct Case
{
	int	nlab;
	int	nsnd;
	long	offset;			/* offset in mp */
	Label	*labs;
	Node	*wild;			/* if nothing matches */
	Inst	*iwild;
};

struct Label
{
	Node	*node;
	char	isptr;			/* true if the labelled alt channel is a pointer */
	Node	*start;			/* value in range [start, stop) => code */
	Node	*stop;
	Inst	*inst;
};

enum
{
	Dtype,
	Dfn,
	Dglobal,
	Darg,
	Dlocal,
	Dconst,
	Dfield,
	Dtag,				/* pick tags */
	Dimport,			/* imported identifier */
	Dunbound,			/* unbound identified */
	Dundef,
	Dwundef,			/* undefined, but don't whine */

	Dend
};

struct Decl
{
	Src	src;			/* where declaration */
	Sym	*sym;
	uchar	store;			/* storage class */
	uchar	nid;		/* block grouping for locals */
	schar	caninline;	/* inline function */
	uchar	das;		/* declared with := */
	Decl	*dot;			/* parent adt or module */
	Type	*ty;
	int	refs;			/* number of references */
	long	offset;
	int	tag;			/* union tag */

	uchar	scope;			/* in which it was declared */
	uchar	handler;		/* fn has exception handler in body */
	Decl	*next;			/* list in same scope, field or argument list, etc. */
	Decl	*old;			/* declaration of the symbol in enclosing scope */

	Node	*eimport;		/* expr from which imported */
	Decl	*importid;		/* identifier imported */
	Decl	*timport;		/* stack of identifiers importing a type */

	Node	*init;			/* data initialization */
	int	tref;			/* 1 => is a tmp; >=2 => tmp in use */
	char	cycle;			/* can create a cycle */
	char	cyc;			/* so labelled in source */
	char	cycerr;			/* delivered an error message for cycle? */
	char	implicit;		/* implicit first argument in an adt? */

	Decl	*iface;			/* used external declarations in a module */

	Decl	*locals;		/* locals for a function */
	Decl *link;			/* pointer to parent function or function argument or local share or parent type dec */
	Inst	*pc;			/* start of function */
	/* Inst	*endpc; */			/* limit of function - unused */

	Desc	*desc;			/* heap descriptor */
};

struct Desc
{
	int	id;			/* dis type identifier */
	uchar	used;			/* actually used in output? */
	uchar	*map;			/* byte map of pointers */
	long	size;			/* length of the object */
	long	nmap;			/* length of good bytes in map */
	Desc	*next;
};

struct Dlist
{
	Decl *d;
	Dlist *next;
};

struct Except
{
	Inst *p1;		/* first pc covered */
	Inst *p2;		/* last pc not covered */
	Case *c;		/* exception case instructions */
	Decl *d;		/* exception definition if any */
	Node *zn;		/* list of nodes to zero in handler */
	Desc *desc;	/* descriptor map for above */
	int ne;		/* number of exceptions (ie not strings) in case */
	Except *next;
};

struct Sym
{
	ushort	token;
	char	*name;
	int	len;
	int	hash;
	Sym	*next;
	Decl	*decl;
	Decl	*unbound;		/* place holder for unbound symbols */
};

/*
 * ops for nodes
 */
enum
{
	Oadd = 1,
	Oaddas,
	Oadr,
	Oadtdecl,
	Oalt,
	Oand,
	Oandand,
	Oandas,
	Oarray,
	Oas,
	Obreak,
	Ocall,
	Ocase,
	Ocast,
	Ochan,
	Ocomma,
	Ocomp,
	Ocondecl,
	Ocons,
	Oconst,
	Ocont,
	Odas,
	Odec,
	Odiv,
	Odivas,
	Odo,
	Odot,
	Oelem,
	Oeq,
	Oexcept,
	Oexdecl,
	Oexit,
	Oexp,
	Oexpas,
	Oexstmt,
	Ofielddecl,
	Ofnptr,
	Ofor,
	Ofunc,
	Ogeq,
	Ogt,
	Ohd,
	Oif,
	Oimport,
	Oinc,
	Oind,
	Oindex,
	Oinds,
	Oindx,
	Oinv,
	Ojmp,
	Olabel,
	Olen,
	Oleq,
	Oload,
	Olsh,
	Olshas,
	Olt,
	Omdot,
	Omod,
	Omodas,
	Omoddecl,
	Omul,
	Omulas,
	Oname,
	Oneg,
	Oneq,
	Onot,
	Onothing,
	Oor,
	Ooras,
	Ooror,
	Opick,
	Opickdecl,
	Opredec,
	Opreinc,
	Oraise,
	Orange,
	Orcv,
	Oref,
	Oret,
	Orsh,
	Orshas,
	Oscope,
	Oself,
	Oseq,
	Oslice,
	Osnd,
	Ospawn,
	Osub,
	Osubas,
	Otagof,
	Otl,
	Otuple,
	Otype,
	Otypedecl,
	Oused,
	Ovardecl,
	Ovardecli,
	Owild,
	Oxor,
	Oxoras,

	Oend
};

/*
 * moves
 */
enum
{
	Mas,
	Mcons,
	Mhd,
	Mtl,

	Mend
};

/*
 * addressability
 */
enum
{
	Rreg,				/* v(fp) */
	Rmreg,				/* v(mp) */
	Roff,				/* $v */
	Rnoff,			/* $v encoded as -ve */
	Rdesc,				/* $v */
	Rdescp,				/* $v */
	Rconst,				/* $v */
	Ralways,			/* preceeding are always addressable */
	Radr,				/* v(v(fp)) */
	Rmadr,				/* v(v(mp)) */
	Rcant,				/* following are not quite addressable */
	Rpc,				/* branch address */
	Rmpc,				/* cross module branch address */
	Rareg,				/* $v(fp) */
	Ramreg,				/* $v(mp) */
	Raadr,				/* $v(v(fp)) */
	Ramadr,				/* $v(v(mp)) */
	Rldt,				/* $v */

	Rend
};

#define PARENS	1
#define TEMP		2
#define FNPTRA	4	/* argument */
#define FNPTR2	8	/* 2nd parameter */
#define FNPTRN	16	/* use -ve offset */
#define FNPTR		(FNPTRA|FNPTR2|FNPTRN)

struct Node
{
	Src	src;
	uchar	op;
	uchar	addable;
	uchar	flags;
	uchar	temps;
	Node	*left;
	Node	*right;
	Type	*ty;
	Decl	*decl;
	Long	val;			/* for Oconst */
	Real	rval;			/* for Oconst */
};

enum
{
	/*
	 * types visible to limbo
	 */
	Tnone	= 0,
	Tadt,
	Tadtpick,			/* pick case of an adt */
	Tarray,
	Tbig,				/* 64 bit int */
	Tbyte,				/* 8 bit unsigned int */
	Tchan,
	Treal,
	Tfn,
	Tint,				/* 32 bit int */
	Tlist,
	Tmodule,
	Tref,
	Tstring,
	Ttuple,
	Texception,
	Tfix,
	Tpoly,

	/*
	 * internal use types
	 */
	Tainit,				/* array initializers */
	Talt,				/* alt channels */
	Tany,				/* type of nil */
	Tarrow,				/* unresolved ty->id types */
	Tcase,				/* case labels */
	Tcasel,				/* case big labels */
	Tcasec,				/* case string labels */
	Tdot,				/* unresolved ty.id types */
	Terror,
	Tgoto,				/* goto labels */
	Tid,				/* id with unknown type */
	Tiface,				/* module interface */
	Texcept,			/* exception handler tables */
	Tinst,			/* instantiated adt */

	Tend
};

enum
{
	OKbind		= 1 << 0,	/* type decls are bound */
	OKverify	= 1 << 1,	/* type looks ok */
	OKsized		= 1 << 2,	/* started figuring size */
	OKref		= 1 << 3,	/* recorded use of type */
	OKclass		= 1 << 4,	/* equivalence class found */
	OKcyc		= 1 << 5,	/* checked for cycles */
	OKcycsize	= 1 << 6,	/* checked for cycles and size */
	OKmodref	= 1 << 7,	/* started checking for a module handle */

	OKmask		= 0xff,

	/*
	 * recursive marks
	 */
	TReq		= 1 << 0,
	TRcom		= 1 << 1,
	TRcyc		= 1 << 2,
	TRvis		= 1 << 3,
};

/* type flags */
#define	FULLARGS	1	/* all hidden args added */
#define	INST	2		/* instantiated adt */
#define	CYCLIC	4	/* cyclic type */
#define	POLY	8	/* polymorphic types inside */
#define	NOPOLY	16	/* no polymorphic types inside */

struct Type
{
	Src	src;
	uchar	kind;
	uchar	varargs;		/* if a function, ends with vargs? */
	uchar	ok;			/* set when type is verified */
	uchar	linkall;		/* put all iface fns in external linkage? */
	uchar	rec;			/* in the middle of recursive type */
	uchar	cons;		/* exception constant */
	uchar	align;		/* alignment in bytes */
	uchar	flags;
	int	sbl;			/* slot in .sbl adt table */
	long	sig;			/* signature for dynamic type check */
	long	size;			/* storage required, in bytes */
	Decl	*decl;
	Type	*tof;
	Decl	*ids;
	Decl	*tags;			/* tagged fields in an adt */
	Decl *polys;			/* polymorphic fields in fn or adt */
	Case	*cse;			/* case or goto labels */
	Type	*teq;			/* temporary equiv class for equiv checking */
	Type	*tcom;			/* temporary equiv class for compat checking */
	Teq	*eq;			/* real equiv class */
	Node *val;		/* for Tfix, Tfn, Tadt only */
	union {
		Node *eraises;		/* for Tfn only */
		Typelist *tlist;		/* for Tinst only */
		Tpair *tmap;		/* for Tadt only */
	} u;
};

/*
 * type equivalence classes
 */
struct Teq
{
	int	id;		/* for signing */
	Type	*ty;		/* an instance of the class */
	Teq	*eq;		/* used to link eq sets */
};

struct Tattr
{
	char	isptr;
	char	refable;
	char	conable;
	char	big;
	char	vis;			/* type visible to users */
};

enum {
	Sother,
	Sloop,
	Sscope
};

struct Tpair
{
	Type *t1;
	Type *t2;
	Tpair *nxt;
};

struct Typelist
{
	Type *t;
	Typelist *nxt;
};
	
Extern	Decl	**adts;
Extern	Sym	*anontupsym;		/* name assigned to all anonymouse tuples */
Extern	int	arrayz;
Extern	int	asmsym;			/* generate symbols in assembly language? */
Extern	Biobuf	*bins[MaxInclude];
Extern	int	blocks;
Extern	Biobuf	*bout;			/* output file */
Extern	Biobuf	*bsym;			/* symbol output file; nil => no sym out */
Extern	double	canonnan;		/* standard nan */
Extern	uchar	casttab[Tend][Tend];	/* instruction to cast from [1] to [2] */
Extern	long	constval;
Extern	Decl	*curfn;
Extern	char	debug[256];
Extern	Desc	*descriptors;		/* list of all possible descriptors */
Extern	int	dontcompile;		/* dis header flag */
Extern	int	dowarn;
Extern	char	*emitcode;		/* emit stub routines for system module functions */
Extern	int	emitdyn;		/* emit stub routines as above but for dynamic modules */
Extern	int	emitstub;		/* emit type and call frames for system modules */
Extern	char	*emittab;		/* emit table of runtime functions for this module */
Extern	int	errors;
Extern	char	escmap[256];
Extern	Inst	*firstinst;
Extern	long	fixss;			/* set extent from command line */
Extern	Decl	*fndecls;
Extern	Decl	**fns;
Extern	int	gendis;			/* generate dis or asm? */
Extern	Decl	*impdecl;			/* id of implementation module or union if many */
Extern	Dlist	*impdecls;		/* id(s) of implementation module(s) */
/* Extern	Sym	*impmod;	*/	/* name of implementation module */
Extern	Decl	*impmods;		/* name of implementation module(s) */
Extern	Decl	*iota;
Extern	uchar	isbyteinst[256];
Extern	int	isfatal;
Extern	int	isrelop[Oend];
Extern	uchar	isused[Oend];
Extern	Inst	*lastinst;
Extern	int	lenadts;
Extern	int	maxerr;
Extern	int	maxlabdep;		/* maximum nesting of breakable/continuable statements */
Extern	long	maxstack;		/* max size of a stack frame called */
Extern	int	mustcompile;		/* dis header flag */
Extern	int	nadts;
Extern	int	newfnptr;		/* ISELF and -ve indices */
Extern	int	nfns;
Extern	Decl	*nildecl;		/* declaration for limbo's nil */
Extern	int	nlabel;
Extern	int	dontinline;
Extern	Line	noline;
Extern	Src	nosrc;
Extern	uchar	opcommute[Oend];
Extern	int	opind[Tend];
Extern	uchar	oprelinvert[Oend];
Extern	int	optims;
Extern	char	*outfile;
Extern	Type	*precasttab[Tend][Tend];
Extern	int	scope;
Extern	Decl	*selfdecl;		/* declaration for limbo's self */
Extern	uchar	sideeffect[Oend];
Extern	char	*signdump;		/* dump sig for this fn */
Extern	int	superwarn;
Extern	char	*symfile;
Extern	Type	*tany;
Extern	Type	*tbig;
Extern	Type	*tbyte;
Extern	Type	*terror;
Extern	Type	*tint;
Extern	Type	*tnone;
Extern	Type	*treal;
Extern	Node	*tree;
Extern	Type	*tstring;
Extern	Type *texception;
Extern	Type	*tunknown;
Extern	Type *tfnptr;
Extern	Type	*rtexception;
Extern	char	unescmap[256];
Extern	Src	unifysrc;
Extern	Node	znode;

extern	int	*blockstack;
extern	int	blockdep;
extern	int	nblocks;
extern	File	**files;
extern	int	nfiles;
extern	uchar	chantab[Tend];
extern	uchar	disoptab[Oend+1][7];
extern	char	*instname[];
extern	char	*kindname[Tend];
extern	uchar	movetab[Mend][Tend];
extern	char	*opname[];
extern	int	setisbyteinst[];
extern	int	setisused[];
extern	int	setsideeffect[];
extern	char	*storename[Dend];
extern	int	storespace[Dend];
extern	Tattr	tattr[Tend];

#include "fns.h"

#pragma varargck	type	"D"	Decl*
#pragma varargck	type	"I"	Inst*
#pragma varargck	type	"K"	Decl*
#pragma varargck	type	"k"	Decl*
#pragma varargck	type	"L"	Line
#pragma varargck	type	"M"	Desc*
#pragma varargck	type	"n"	Node*
#pragma varargck	type	"O"	int
#pragma varargck	type	"O"	uint
#pragma varargck	type	"g"	double
#pragma varargck	type	"Q"	Node*
#pragma varargck	type	"R"	Type*
#pragma varargck	type	"T"	Type*
#pragma varargck	type	"t"	Type*
#pragma varargck	type	"U"	Src
#pragma varargck	type	"v"	Node*
#pragma	varargck	type	"V"	Node*
