#include "limbo.h"

#define	bzero	bbzero	/* bsd name space pollution */
/* 
	(r, s) := f();	=> r, s have def on same pc
	s = g();	=> this def kills previous r def (and s def)
	solution: r has def pc, s has def pc+1 and next instruction has pc pc+2
*/

#define BLEN	(8*sizeof(ulong))
#define BSHIFT	5	/* assumes ulong 4 */
#define BMASK	(BLEN-1)

#define	SIGN(n)		(1<<(n-1))
#define	MSK(n)		(SIGN(n)|(SIGN(n)-1))
#define	MASK(a, b)	(MSK((b)-(a)+1)<<(a))

#define isnilsrc(s)	((s)->start.line == 0 && (s)->stop.line == 0 && (s)->start.pos == 0 && (s)->stop.pos == 0)

#define limbovar(d)	((d)->sym->name[0] != '.')
#define structure(t)	((t)->kind == Tadt || (t)->kind == Ttuple)

enum
{
	Bclr,
	Band,
	Bandinv,
	Bstore,
	Bandrev,
	Bnoop,
	Bxor,
	Bor,
	Bnor,
	Bequiv,
	Binv,
	Bimpby,
	Brev,
	Bimp,
	Bnand,
	Bset,
};

enum
{
	Suse = 1,
	Muse = 2,
	Duse = 4,
	Sdef = 8,
	Mdef = 16,
	Ddef = 32,
	Tuse1 = 64,	/* fixed point temporary */
	Tuse2 = 128,	/* fixed point temporary */
	Mduse = 256,	/* D used if M nil */

	None = 0,
	Unop = Suse|Ddef,
	Cunop = Muse|Ddef,
	Threop = Suse|Muse|Ddef,
	Binop = Suse|Muse|Ddef|Mduse,
	Mbinop = Suse|Mdef|Duse,	/* strange */
	Abinop=Suse|Duse|Ddef,
	Mabinop = Suse|Muse|Duse|Ddef,
	Use1 = Suse,
	Use2 = Suse|Duse,
	Use3 = Suse|Muse|Duse,
};

enum
{
	Sshift = 10,
	Mshift = 5,
	Dshift = 0,
};

#define S(x)	((x)<<Sshift)
#define M(x)	((x)<<Mshift)
#define D(x)	((x)<<Dshift)

#define SS(x)	(((x)>>Sshift)&0x1f)
#define SM(x)	(((x)>>Mshift)&0x1f)
#define SD(x)	(((x)>>Dshift)&0x1f)

enum
{
	I = 0,		/* ignore */
	B = 1,	/* byte */
	W = 4,	/* int */
	P = 4,	/* pointer */
	A = 4,	/* array */
	C = 4,	/* string */
	X = 4,	/* fixed */
	R = 4,	/* float */
	L = 8,	/* big */
	F = 8,	/* real */
	Sh = 2,	/* short */
	Pc = 4,	/* pc */
	Mp = 16,	/* memory */

	Bop2 = S(B)|D(B),
	Bop = S(B)|M(B)|D(B),
	Bopb = S(B)|M(B)|D(Pc),
	Wop2 = S(W)|D(W),
	Wop = S(W)|M(W)|D(W),
	Wopb = S(W)|M(W)|D(Pc),
	Lop2 = S(L)|D(L),
	Lop = S(L)|M(L)|D(L),
	Lopb = S(L)|M(L)|D(Pc),
	Cop2 = Wop2,
	Cop = Wop,
	Copb = Wopb,
	Fop2 = Lop2,
	Fop = Lop,
	Fopb = Lopb,
	Xop = Wop,
};

typedef struct Array Array;
typedef struct Bits Bits;
typedef struct Blist Blist;
typedef struct Block Block;
typedef struct Idlist Idlist;
typedef struct Optab Optab;

struct Array
{
	int	n;
	int	m;
	Block	**a;
};

struct Bits
{
	int	n;
	ulong	*b;
};

struct Blist
{
	Block	*block;
	Blist	*next;
};

struct Block
{
	int	dfn;
	int	flags;
	Inst	*first;
	Inst	*last;
	Block	*prev;
	Block	*next;
	Blist	*pred;
	Blist *succ;
	Bits	kill;
	Bits	gen;
	Bits	in;
	Bits	out;
};

struct Idlist
{
	int id;
	Idlist *next;
};

struct Optab
{
	short flags;
	short size;
};

Block	zblock;
Decl	*regdecls;
Idlist *frelist;
Idlist *deflist;
Idlist *uselist;

static void
addlist(Idlist **hd, int id)
{
	Idlist *il;

	if(frelist == nil)
		il = (Idlist*)malloc(sizeof(Idlist));
	else{
		il = frelist;
		frelist = frelist->next;
	}
	il->id = id;
	il->next = *hd;
	*hd = il;
}

static void
freelist(Idlist **hd)
{
	Idlist *il;

	for(il = *hd; il != nil && il->next != nil; il = il->next)
		;
	if(il != nil){
		il->next = frelist;
		frelist = *hd;
		*hd = nil;
	}
}
	
Optab opflags[] = {
	/* INOP */	None,	0,
	/* IALT */	Unop,	S(Mp)|D(W),
	/* INBALT */	Unop,	S(Mp)|D(W),
	/* IGOTO */	Use2,	S(W)|D(I),
	/* ICALL */	Use2,	S(P)|D(Pc),
	/* IFRAME */	Unop,	S(W)|D(P),
	/* ISPAWN */	Use2,	S(P)|D(Pc),
	/* IRUNT */	None,	0,
	/* ILOAD */	Threop,	S(C)|M(P)|D(P),
	/* IMCALL */	Use3,	S(P)|M(W)|D(P),
	/* IMSPAWN */	Use3,	S(P)|M(W)|D(P),
	/* IMFRAME */	Threop,	S(P)|M(W)|D(P),
	/* IRET */	None,	0,
	/* IJMP */	Duse,	D(Pc),
	/* ICASE */	Use2,	S(W)|D(I),
	/* IEXIT */	None,	0,
	/* INEW */	Unop,	S(W)|D(P),
	/* INEWA */	Threop,	S(W)|M(W)|D(P),
	/* INEWCB */	Cunop,	M(W)|D(P),
	/* INEWCW */	Cunop,	M(W)|D(P),
	/* INEWCF */	Cunop,	M(W)|D(P),
	/* INEWCP */	Cunop,	M(W)|D(P),
	/* INEWCM */	Threop,	S(W)|M(W)|D(P),
	/* INEWCMP */	Threop,	S(W)|M(W)|D(P),
	/* ISEND */	Use2,	S(Mp)|D(P),
	/* IRECV */	Unop,	S(P)|D(Mp),
	/* ICONSB */	Abinop,	S(B)|D(P),
	/* ICONSW */	Abinop,	S(W)|D(P),
	/* ICONSP */	Abinop,	S(P)|D(P),
	/* ICONSF */	Abinop,	S(F)|D(P),
	/* ICONSM */	Mabinop,	S(Mp)|M(W)|D(P),
	/* ICONSMP */	Mabinop,	S(Mp)|M(W)|D(P),
	/* IHEADB */	Unop,	S(P)|D(B),
	/* IHEADW */	Unop,	S(P)|D(W),
	/* IHEADP */	Unop,	S(P)|D(P),
	/* IHEADF */	Unop,	S(P)|D(F),
	/* IHEADM */	Threop,	S(P)|M(W)|D(Mp),
	/* IHEADMP */	Threop,	S(P)|M(W)|D(Mp),
	/* ITAIL */	Unop,	S(P)|D(P),
	/* ILEA */	Ddef,	S(Mp)|D(P),	/* S done specially cos of ALT */
	/* IINDX */	Mbinop,	S(P)|M(P)|D(W),
	/* IMOVP */	Unop,	S(P)|D(P),
	/* IMOVM */	Threop,	S(Mp)|M(W)|D(Mp),
	/* IMOVMP */	Threop,	S(Mp)|M(W)|D(Mp),
	/* IMOVB */	Unop,	Bop2,
	/* IMOVW */	Unop,	Wop2,
	/* IMOVF */	Unop,	Fop2,
	/* ICVTBW */	Unop,	S(B)|D(W),
	/* ICVTWB */	Unop,	S(W)|D(B),
	/* ICVTFW */	Unop,	S(F)|D(W),
	/* ICVTWF */	Unop,	S(W)|D(F),
	/* ICVTCA */	Unop,	S(C)|D(A),
	/* ICVTAC */	Unop,	S(A)|D(C),
	/* ICVTWC */	Unop,	S(W)|D(C),
	/* ICVTCW */	Unop,	S(C)|D(W),
	/* ICVTFC */	Unop,	S(F)|D(C),
	/* ICVTCF */	Unop,	S(C)|D(F),
	/* IADDB */	Binop,	Bop,
	/* IADDW */	Binop,	Wop,
	/* IADDF */	Binop,	Fop,
	/* ISUBB */	Binop,	Bop,
	/* ISUBW */	Binop,	Wop,
	/* ISUBF */	Binop,	Fop,
	/* IMULB */	Binop,	Bop,
	/* IMULW */	Binop,	Wop,
	/* IMULF */	Binop,	Fop,
	/* IDIVB */	Binop,	Bop,
	/* IDIVW */	Binop,	Wop,
	/* IDIVF */	Binop,	Fop,
	/* IMODW */	Binop,	Wop,
	/* IMODB */	Binop,	Bop,
	/* IANDB */	Binop,	Bop,
	/* IANDW */	Binop,	Wop,
	/* IORB */	Binop,	Bop,
	/* IORW */	Binop,	Wop,
	/* IXORB */	Binop,	Bop,
	/* IXORW */	Binop,	Wop,
	/* ISHLB */	Binop,	S(W)|M(B)|D(B),
	/* ISHLW */	Binop,	Wop,
	/* ISHRB */	Binop,	S(W)|M(B)|D(B),
	/* ISHRW */	Binop,	Wop,
	/* IINSC */	Mabinop,	S(W)|M(W)|D(C),
	/* IINDC */	Threop,	S(C)|M(W)|D(W),
	/* IADDC */	Binop,	Cop,
	/* ILENC */	Unop,	S(C)|D(W),
	/* ILENA */	Unop,	S(A)|D(W),
	/* ILENL */	Unop,	S(P)|D(W),
	/* IBEQB */	Use3,	Bopb,
	/* IBNEB */	Use3,	Bopb,
	/* IBLTB */	Use3,	Bopb,
	/* IBLEB */	Use3,	Bopb,
	/* IBGTB */	Use3,	Bopb,
	/* IBGEB */	Use3,	Bopb,
	/* IBEQW */	Use3,	Wopb,
	/* IBNEW */	Use3,	Wopb,
	/* IBLTW */	Use3,	Wopb,
	/* IBLEW */	Use3,	Wopb,
	/* IBGTW */	Use3,	Wopb,
	/* IBGEW */	Use3,	Wopb,
	/* IBEQF */	Use3,	Fopb,
	/* IBNEF */	Use3,	Fopb,
	/* IBLTF */	Use3,	Fopb,
	/* IBLEF */	Use3,	Fopb,
	/* IBGTF */	Use3,	Fopb,
	/* IBGEF */	Use3,	Fopb,
	/* IBEQC */	Use3,	Copb,
	/* IBNEC */	Use3,	Copb,
	/* IBLTC */	Use3,	Copb,
	/* IBLEC */	Use3,	Copb,
	/* IBGTC */	Use3,	Copb,
	/* IBGEC */	Use3,	Copb,
	/* ISLICEA */	Mabinop,	S(W)|M(W)|D(P),
	/* ISLICELA */	Use3,	S(P)|M(W)|D(P),
	/* ISLICEC */	Mabinop,	S(W)|M(W)|D(C),
	/* IINDW */	Mbinop,	S(P)|M(P)|D(W),
	/* IINDF */	Mbinop,	S(P)|M(P)|D(W),
	/* IINDB */	Mbinop,	S(P)|M(P)|D(W),
	/* INEGF */	Unop,	Fop2,
	/* IMOVL */	Unop,	Lop2,
	/* IADDL */	Binop,	Lop,
	/* ISUBL */	Binop,	Lop,
	/* IDIVL */	Binop,	Lop,
	/* IMODL */	Binop,	Lop,
	/* IMULL */	Binop,	Lop,
	/* IANDL */	Binop,	Lop,
	/* IORL */	Binop,	Lop,
	/* IXORL */	Binop,	Lop,
	/* ISHLL */	Binop,	S(W)|M(L)|D(L),
	/* ISHRL */	Binop,	S(W)|M(L)|D(L),
	/* IBNEL */	Use3,	Lopb,
	/* IBLTL */	Use3,	Lopb,
	/* IBLEL */	Use3,	Lopb,
	/* IBGTL */	Use3,	Lopb,
	/* IBGEL */	Use3,	Lopb,
	/* IBEQL */	Use3,	Lopb,
	/* ICVTLF */	Unop,	S(L)|D(F),
	/* ICVTFL */	Unop,	S(F)|D(L),
	/* ICVTLW */	Unop,	S(L)|D(W),
	/* ICVTWL */	Unop,	S(W)|D(L),
	/* ICVTLC */	Unop,	S(L)|D(C),
	/* ICVTCL */	Unop,	S(C)|D(L),
	/* IHEADL */	Unop,	S(P)|D(L),
	/* ICONSL */	Abinop,	S(L)|D(P),
	/* INEWCL */	Cunop,	M(W)|D(P),
	/* ICASEC */	Use2,	S(C)|D(I),
	/* IINDL */	Mbinop,	S(P)|M(P)|D(W),
	/* IMOVPC */	Unop,	S(W)|D(P),
	/* ITCMP */	Use2,	S(P)|D(P),
	/* IMNEWZ */	Threop,	S(P)|M(W)|D(P),
	/* ICVTRF */	Unop,	S(R)|D(F),
	/* ICVTFR */	Unop,	S(F)|D(R),
	/* ICVTWS */	Unop,	S(W)|D(Sh),
	/* ICVTSW */	Unop,	S(Sh)|D(W),
	/* ILSRW */	Binop,	Wop,
	/* ILSRL */	Binop,	S(W)|M(L)|D(L),
	/* IECLR */	None,	0,
	/* INEWZ */	Unop,	S(W)|D(P),
	/* INEWAZ */	Threop,	S(W)|M(W)|D(P),
	/* IRAISE */	Use1,	S(P),
	/* ICASEL */	Use2,	S(L)|D(I),
	/* IMULX */	Binop|Tuse2,	Xop,
	/* IDIVX */	Binop|Tuse2,	Xop,
	/* ICVTXX */	Threop,	Xop,
	/* IMULX0 */	Binop|Tuse1|Tuse2,	Xop,
	/* IDIVX0 */	Binop|Tuse1|Tuse2,	Xop,
	/* ICVTXX0 */	Threop|Tuse1,	Xop,
	/* IMULX1 */	Binop|Tuse1|Tuse2,	Xop,
	/* IDIVX1 */	Binop|Tuse1|Tuse2,	Xop,
	/* ICVTXX1 */	Threop|Tuse1,	Xop,
	/* ICVTFX */	Threop,	S(F)|M(F)|D(X),
	/* ICVTXF */	Threop,	S(X)|M(F)|D(F),
	/* IEXPW */	Binop,	S(W)|M(W)|D(W),
	/* IEXPL */	Binop,	S(W)|M(L)|D(L),
	/* IEXPF */	Binop,	S(W)|M(F)|D(F),
	/* ISELF */	Ddef,	D(P),
	/* IEXC */		None,		0,
	/* IEXC0 */	None,		0,
	/* INOOP */	None,		0,
};

/*
static int
pop(int i)
{
	i = (i & 0x55555555) + ((i>>1) & 0x55555555);
	i = (i & 0x33333333) + ((i>>2) & 0x33333333);
	i = (i & 0x0F0F0F0F) + ((i>>4) & 0x0F0F0F0F);
	i = (i & 0x00FF00FF) + ((i>>8) & 0x00FF00FF);
	i = (i & 0x0000FFFF) + ((i>>16) & 0x0000FFFF);
	return i;
}
*/

static int
bitc(uint x)
{
	uint n;

	n = (x>>1)&0x77777777;
	x -= n;
	n = (n>>1)&0x77777777;
	x -= n;
	n = (n>>1)&0x77777777;
	x -= n;
	x = (x+(x>>4))&0x0f0f0f0f;
	x *= 0x01010101;
	return x>>24;
}

/*
static int
top(uint x)
{
	int i;

	for(i = -1; x; i++)
		x >>= 1;
	return i;
}
*/

static int
topb(uint x)
{
	int i;

	if(x == 0)
		return -1;
	i = 0;
	if(x&0xffff0000){
		i |= 16;
		x >>= 16;
	}
	if(x&0xff00){
		i |= 8;
		x >>= 8;
	}
	if(x&0xf0){
		i |= 4;
		x >>= 4;
	}
	if(x&0xc){
		i |= 2;
		x >>= 2;
	}
	if(x&0x2)
		i |= 1;
	return i;
}

/*
static int
lowb(uint x)
{
	int i;

	if(x == 0)
		return -1;
	for(i = BLEN; x; i--)
		x <<= 1;
	return i;
}
*/

static int
lowb(uint x)
{
	int i;

	if(x == 0)
		return -1;
	i = 0;
	if((x&0xffff) == 0){
		i |= 16;
		x >>= 16;
	}
	if((x&0xff) == 0){
		i |= 8;
		x >>= 8;
	}
	if((x&0xf) == 0){
		i |= 4;
		x >>= 4;
	}
	if((x&0x3) == 0){
		i |= 2;
		x >>= 2;
	}
	return i+1-(x&1);
}
		
static void
pbit(int x, int n)
{
	int i, m;

	m = 1;
	for(i = 0; i < BLEN; i++){
		if(x&m)
			print("%d ", i+n);
		m <<= 1;
	}
}

static ulong
bop(int o, ulong s, ulong d)
{
	switch(o){
	case Bclr:	return 0;
	case Band:	return s & d;
	case Bandinv:	return s & ~d;
	case Bstore:	return s;
	case Bandrev:	return ~s & d;
	case Bnoop:	return d;
	case Bxor:	return s ^ d;
	case Bor:	return s | d;
	case Bnor:	return ~(s | d);
	case Bequiv:	return ~(s ^ d);
	case Binv:	return ~d;
	case Bimpby:	return s | ~d;
	case Brev:	return ~s;
	case Bimp:	return ~s | d;
	case Bnand:	return ~(s & d);
	case Bset:	return 0xffffffff;
	}
	return 0;
}

static Bits
bnew(int n, int bits)
{
	Bits b;

	if(bits)
		b.n = (n+BLEN-1)>>BSHIFT;
	else
		b.n = n;
	b.b = allocmem(b.n*sizeof(ulong));
	memset(b.b, 0, b.n*sizeof(ulong));
	return b;
}

static void
bfree(Bits b)
{
	free(b.b);
}

static void
bset(Bits b, int n)
{
	b.b[n>>BSHIFT] |= 1<<(n&BMASK);
}

static void
bclr(Bits b, int n)
{
	b.b[n>>BSHIFT] &= ~(1<<(n&BMASK));
}

static int
bmem(Bits b, int n)
{
	return b.b[n>>BSHIFT] & (1<<(n&BMASK));
}

static void
bsets(Bits b, int m, int n)
{
	int i, c1, c2;

	c1 = m>>BSHIFT;
	c2 = n>>BSHIFT;
	m &= BMASK;
	n &= BMASK;
	if(c1 == c2){
		b.b[c1] |= MASK(m, n);
		return;
	}
	for(i = c1+1; i < c2; i++)
		b.b[i] = 0xffffffff;
	b.b[c1] |= MASK(m, BLEN-1);
	b.b[c2] |= MASK(0, n);
}

static void
bclrs(Bits b, int m, int n)
{
	int i, c1, c2;

	if(n < 0)
		n = (b.n<<BSHIFT)-1;
	c1 = m>>BSHIFT;
	c2 = n>>BSHIFT;
	m &= BMASK;
	n &= BMASK;
	if(c1 == c2){
		b.b[c1] &= ~MASK(m, n);
		return;
	}
	for(i = c1+1; i < c2; i++)
		b.b[i] = 0;
	b.b[c1] &= ~MASK(m, BLEN-1);
	b.b[c2] &= ~MASK(0, n);
}
	
/* b = a op b */
static Bits
boper(int o, Bits a, Bits b)
{
	int i, n;

	n = a.n;
	if(b.n != n)
		fatal("boper %d %d %d", o, a.n, b.n);
	for(i = 0; i < n; i++)
		b.b[i] = bop(o, a.b[i], b.b[i]);
	return b;
}

static int
beq(Bits a, Bits b)
{
	int i, n;

	n = a.n;
	for(i = 0; i < n; i++)
		if(a.b[i] != b.b[i])
			return 0;
	return 1;
}

static int
bzero(Bits b)
{
	int i, n;

	n = b.n;
	for(i = 0; i < n; i++)
		if(b.b[i] != 0)
			return 0;
	return 1;
}

static int
bitcnt(Bits b)
{
	int i, m, n;

	m = b.n;
	n = 0;
	for(i = 0; i < m; i++)
		n += bitc(b.b[i]);
	return n;
}

static int
topbit(Bits b)
{
	int i, n;

	n = b.n;
	for(i = n-1; i >= 0; i--)
		if(b.b[i] != 0)
			return (i<<BSHIFT)+topb(b.b[i]);
	return -1;
}

static int
lowbit(Bits b)
{
	int i, n;

	n = b.n;
	for(i = 0; i < n; i++)
		if(b.b[i] != 0)
			return (i<<BSHIFT)+lowb(b.b[i]);
	return -1;
}

static void
pbits(Bits b)
{
	int i, n;

	n = b.n;
	for(i = 0; i < n; i++)
		pbit(b.b[i], i<<BSHIFT);
}

static char*
decname(Decl *d)
{
	if(d->sym == nil)
		return "<??>";
	return d->sym->name;
}

static void
warning(Inst *i, char *s, Decl *d, Decl *sd)
{
	int n;
	char *f;
	Decl *ds;

	n = 0;
	for(ds = sd; ds != nil; ds = ds->next)
		if(ds->link == d)
			n += strlen(ds->sym->name)+1;
	if(n == 0){
		warn(i->src.start, "%s: %s", d->sym->name, s);
		return;
	}
	n += strlen(d->sym->name);
	f = malloc(n+1);
	strcpy(f, d->sym->name);
	for(ds = sd; ds != nil; ds = ds->next){
		if(ds->link == d){
			strcat(f, "/");
			strcat(f, ds->sym->name);
		}
	}
	warn(i->src.start, "%s: %s", f, s);
	free(f);
}

static int
inspc(Inst *in)
{
	int n;
	Inst *i;

	n = 0;
	for(i = in; i != nil; i = i->next)
		i->pc = n++;
	return n;
}

static Inst*
pc2i(Block *b, int pc)
{
	Inst *i;

	for( ; b != nil; b = b->next){
		if(pc > b->last->pc)
			continue;
		for(i = b->first; ; i = i->next){
			if(i->pc == pc)
				return i;
			if(i == b->last)
				fatal("pc2i a");
		}
	}
	fatal("pc2i b");
	return nil;
}

static void
padr(int am, Addr *a, Inst *br)
{
	long reg;

	if(br != nil){
		print("$%ld", br->pc);
		return;
	}
	reg = a->reg;
	if(a->decl != nil && am != Adesc)
		reg += a->decl->offset;
	switch(am){
	case Anone:
		print("-");
		break;
	case Aimm:
	case Apc:
	case Adesc:
		print("$%ld", a->offset);
		break;
	case Aoff:
		print("$%ld", a->decl->iface->offset);
		break;
	case Anoff:
		print("-$%ld", a->decl->iface->offset);
		break;
	case Afp:
		print("%ld(fp)", reg);
		break;
	case Afpind:
		print("%ld(%ld(fp))", a->offset, reg);
		break;
	case Amp:
		print("%ld(mp)", reg);
		break;
	case Ampind:
		print("%ld(%ld(mp))", a->offset, reg);
		break;
	case Aldt:
		print("$%ld", reg);
		break;
	case Aerr:
	default:
		print("%ld(%ld(?%d?))", a->offset, reg, am);
		break;
	}
}

static void
pins(Inst *i)
{
	/* print("%L		%ld	", i->src.start, i->pc); */
	print("		%ld	", i->pc);
	if(i->op >= 0 && i->op < MAXDIS)
		print("%s", instname[i->op]);
	else
		print("noop");
	print("	");
	padr(i->sm, &i->s, nil);
	print(", ");
	padr(i->mm, &i->m, nil);
	print(", ");
	padr(i->dm, &i->d, i->branch);
	print("\n");
}

static void
blfree(Blist *bl)
{
	Blist *nbl;

	for( ; bl != nil; bl = nbl){
		nbl = bl->next;
		free(bl);
	}
}

static void
freebits(Bits *bs, int nv)
{
	int i;

	for(i = 0; i < nv; i++)
		bfree(bs[i]);
	free(bs);
}

static void
freeblks(Block *b)
{
	Block *nb;

	for( ; b != nil; b = nb){
		blfree(b->pred);
		blfree(b->succ);
		bfree(b->kill);
		bfree(b->gen);
		bfree(b->in);
		bfree(b->out);
		nb = b->next;
		free(b);
	}
}

static int
len(Decl *d)
{
	int n;

	n = 0;
	for( ; d != nil; d = d->next)
		n++;
	return n;
}

static Bits*
allocbits(int nv, int npc)
{
	int i;
	Bits *defs;

	defs = (Bits*)allocmem(nv*sizeof(Bits));
	for(i = 0; i < nv; i++)
		defs[i] = bnew(npc, 1);
	return defs;
}

static int
bitcount(Bits *bs, int nv)
{
	int i, n;

	n = 0;
	for(i = 0; i < nv; i++)
		n += bitcnt(bs[i]);
	return n;
}

static Block*
mkblock(Inst *i)
{
	Block *b;

	b = allocmem(sizeof(Block));
	*b = zblock;
	b->first = b->last = i;
	return b;
}

static Blist*
mkblist(Block *b, Blist *nbl)
{
	Blist *bl;

	bl = allocmem(sizeof(Blist));
	bl->block = b;
	bl->next = nbl;
	return bl;
}

static void
leader(Inst *i, Array *ab)
{
	int m, n;
	Block *b, **a;

	if(i != nil && i->pc == 0){
		if((n = ab->n) == (m = ab->m)){
			a = ab->a;
			ab->a = allocmem(2*m*sizeof(Block*));
			memcpy(ab->a, a, m*sizeof(Block*));
			ab->m = 2*m;
			free(a);
		}
		b = mkblock(i);
		b->dfn = n;
		ab->a[n] = b;
		i->pc = ab->n = n+1;
	}
}

static Block*
findb(Inst *i, Array *ab)
{
	if(i == nil)
		return nil;
	if(i->pc <= 0)
		fatal("pc <= 0 in findb");
	return ab->a[i->pc-1];
}

static int
memb(Block *b, Blist *bl)
{
	for( ; bl != nil; bl = bl->next)
		if(bl->block == b)
			return 1;
	return 0;
}

static int
canfallthrough(Inst *i)
{
	if(i == nil)
		return 0;
	switch(i->op){
	case IGOTO:
	case ICASE:
	case ICASEL:
	case ICASEC:
	case IRET:
	case IEXIT:
	case IRAISE:
	case IJMP:
		return 0;
	case INOOP:
		return i->branch != nil;
	}
	return 1;
}

static void
predsucc(Block *b1, Block *b2)
{
	if(b1 == nil || b2 == nil)
		return;
	if(!memb(b1, b2->pred))
		b2->pred = mkblist(b1, b2->pred);
	if(!memb(b2, b1->succ))
		b1->succ = mkblist(b2, b1->succ);
}
	
static Block*
mkblocks(Inst *in, int *nb)
{
	Inst *i;
	Block *b, *firstb, *lastb;
	Label *lab;
	Array *ab;
	int j, n;

	ab = allocmem(sizeof(Array));
	ab->n = 0;
	ab->m = 16;
	ab->a = allocmem(ab->m*sizeof(Block*));
	leader(in, ab);
	for(i = in; i != nil; i = i->next){
		switch(i->op){
		case IGOTO:
		case ICASE:
		case ICASEL:
		case ICASEC:
		case INOOP:
			if(i->op == INOOP && i->branch != nil){
				leader(i->branch, ab);
				leader(i->next, ab);
				break;
			}
			leader(i->d.decl->ty->cse->iwild, ab);
			lab = i->d.decl->ty->cse->labs;
			n = i->d.decl->ty->cse->nlab;
			for(j = 0; j < n; j++)
				leader(lab[j].inst, ab);
			leader(i->next, ab);
			break;
		case IRET:
		case IEXIT:
		case IRAISE:
			leader(i->next, ab);
			break;
		case IJMP:
			leader(i->branch, ab);
			leader(i->next, ab);
			break;
		default:
			if(i->branch != nil){
				leader(i->branch, ab);
				leader(i->next, ab);
			}
			break;
		}
	}
	firstb = lastb = mkblock(nil);
	for(i = in; i != nil; i = i->next){
		if(i->pc != 0){
			b = findb(i, ab);
			b->prev = lastb;
			lastb->next = b;
			if(canfallthrough(lastb->last))
				predsucc(lastb, b);
			lastb = b;
		}
		else
			lastb->last = i;
		switch(i->op){
		case IGOTO:
		case ICASE:
		case ICASEL:
		case ICASEC:
		case INOOP:
			if(i->op == INOOP && i->branch != nil){
				b = findb(i->next, ab);
				predsucc(lastb, b);
				b = findb(i->branch, ab);
				predsucc(lastb, b);
				break;
			}
			b = findb(i->d.decl->ty->cse->iwild, ab);
			predsucc(lastb, b);
			lab = i->d.decl->ty->cse->labs;
			n = i->d.decl->ty->cse->nlab;
			for(j = 0; j < n; j++){
				b = findb(lab[j].inst, ab);
				predsucc(lastb, b);
			}
			break;
		case IRET:
		case IEXIT:
		case IRAISE:
			break;
		case IJMP:
			b = findb(i->branch, ab);
			predsucc(lastb, b);
			break;
		default:
			if(i->branch != nil){
				b = findb(i->next, ab);
				predsucc(lastb, b);
				b = findb(i->branch, ab);
				predsucc(lastb, b);
			}
			break;
		}
	}
	*nb = ab->n;
	free(ab->a);
	free(ab);
	b = firstb->next;
	b->prev = nil;
	return b;
}

static int
back(Block *b1, Block *b2)
{
	return b1->dfn >= b2->dfn;
}

static void
pblocks(Block *b, int nb)
{
	Inst *i;
	Blist *bl;

	print("--------------------%d blocks--------------------\n", nb);
	print("------------------------------------------------\n");
	for( ; b != nil; b = b->next){
		print("dfn=%d\n", b->dfn);
		print("    pred	");
		for(bl = b->pred; bl != nil; bl = bl->next)
			print("%d%s ", bl->block->dfn, back(bl->block, b) ? "*" : "");
		print("\n");
		print("    succ	");
		for(bl = b->succ; bl != nil; bl = bl->next)
			print("%d%s ", bl->block->dfn, back(b, bl->block) ? "*" : "");
		print("\n");
		for(i = b->first; i != nil; i = i->next){
			// print("	%I\n", i);
			pins(i);
			if(i == b->last)
				break;
		}
	}
	print("------------------------------------------------\n");
}

static void
ckblocks(Inst *in, Block *b, int nb)
{
	int n;
	Block *lastb;

	if(b->first != in)
		fatal("A - %d", b->dfn);
	n = 0;
	lastb = nil;
	for( ; b != nil; b = b->next){
		n++;
		if(b->prev != lastb)
			fatal("a - %d\n", b->dfn);
		if(b->prev != nil && b->prev->next != b)
			fatal("b - %d\n", b->dfn);
		if(b->next != nil && b->next->prev != b)
			fatal("c - %d\n", b->dfn);

		if(b->prev != nil && b->prev->last->next != b->first)
			fatal("B - %d\n", b->dfn);
		if(b->next != nil && b->last->next != b->next->first)
			fatal("C - %d\n", b->dfn);
		if(b->next == nil && b->last->next != nil)
			fatal("D - %d\n", b->dfn);

		if(b->last->branch != nil && b->succ->block->first != b->last->branch)
			fatal("0 - %d\n", b->dfn);

		lastb = b;
	}
	if(n != nb)
		fatal("N - %d %d\n", n, nb);
}

static void
dfs0(Block *b, int *n)
{
	Block *s;
	Blist *bl;

	b->flags = 1;
	for(bl = b->succ; bl != nil; bl = bl->next){
		s = bl->block;
		if(s->flags == 0)
			dfs0(s, n);
	}
	b->dfn = --(*n);
}

static int
dfs(Block *b, int nb)
{
	int n, u;
	Block *b0;

	b0 = b;
	n = nb;
	dfs0(b0, &n);
	u = 0;
	for(b = b0; b != nil; b = b->next){
		if(b->flags == 0){	/* unreachable: see foldbranch */
			fatal("found unreachable code");
			u++;
			b->prev->next = b->next;
			if(b->next){
				b->next->prev = b->prev;
				b->prev->last->next = b->next->first;
			}
			else
				b->prev->last->next = nil;
		}
		b->flags = 0;
	}
	if(u){
		for(b = b0; b != nil; b = b->next)
			b->dfn -= u;
	}
	return nb-u;
}

static void
loop0(Block *b)
{
	Block *p;
	Blist *bl;

	b->flags = 1;
	for(bl = b->pred; bl != nil; bl = bl->next){
		p = bl->block;
		if(p->flags == 0)
			loop0(p);
	}
}

/* b1->b2 a back edge */
static void
loop(Block *b, Block *b1, Block *b2)
{
	if(0 && debug['o'])
		print("back edge %d->%d\n", b1->dfn, b2->dfn);
	b2->flags = 1;
	if(b1->flags == 0)
		loop0(b1);
	if(0 && debug['o'])
		print("	loop	");
	for( ; b != nil; b = b->next){
		if(b->flags && 0 && debug['o'])
			print("%d ", b->dfn);
		b->flags = 0;
	}
	if(0 && debug['o'])
		print("\n");
}

static void
loops(Block *b)
{
	Block *b0;
	Blist *bl;

	b0 = b;
	for( ; b != nil; b = b->next){
		for(bl = b->succ; bl != nil; bl = bl->next){
			if(back(b, bl->block))
				loop(b0, b, bl->block);
		}
	}
}

static int
imm(int m, Addr *a)
{
	if(m == Aimm)
		return a->offset;
	fatal("bad immediate value");
	return -1;
}

static int
desc(int m, Addr *a)
{
	if(m == Adesc)
		return a->decl->desc->size;
	fatal("bad descriptor value");
	return -1;
}

static int
fpoff(int m, Addr *a)
{
	int off;
	Decl *d;

	if(m == Afp || m == Afpind){
		off = a->reg;
		if((d = a->decl) != nil)
			off += d->offset;
		return off;
	}
	return -1;
}

static int
size(Inst *i)
{
	switch(i->op){
	case ISEND:
	case IRECV:
	case IALT:
	case INBALT:
	case ILEA:
		return i->m.offset;
	case IMOVM:
	case IHEADM:
	case ICONSM:
		return imm(i->mm, &i->m);
	case IMOVMP:
	case IHEADMP:
	case ICONSMP:
		return desc(i->mm, &i->m);
		break;
	}
	fatal("bad op in size");
	return -1;
}

static Decl*
mkdec(int o)
{
	Decl *d;

	d = mkdecl(&nosrc, Dlocal, tint);
	d->offset = o;
	return d;
}

static void
mkdecls(void)
{
	regdecls = mkdec(REGRET*IBY2WD);
	regdecls->next = mkdec(STemp);
	regdecls->next->next = mkdec(DTemp);
}

static Decl*
sharedecls(Decl *d)
{
	Decl *ld;

	ld = d;
	for(d = d->next ; d != nil; d = d->next){
		if(d->offset <= ld->offset)
			break;
		ld = d;
	}
	return d;
}

static int
finddec(int o, int s, Decl *vars, int *nv, Inst *i)
{
	int m, n;
	Decl *d;

	n = 0;
	for(d = vars; d != nil; d = d->next){
		if(o >= d->offset && o < d->offset+d->ty->size){
			m = 1;
			while(o+s > d->offset+d->ty->size){
				m++;
				d = d->next;
			}
			*nv = m;
			return n;
		}
		n++;
	}
	// print("%d %d missing\n", o, s);
	pins(i);
	fatal("missing decl");
	return -1;
}

static void
setud(Bits *b, int id, int n, int pc)
{
	if(id < 0)
		return;
	while(--n >= 0)
		bset(b[id++], pc);
}

static void
ud(Inst *i, Decl *vars, Bits *uses, Bits *defs)
{
	ushort f;
	int id, j, nv, pc, sz, s, m, d, ss, sm, sd;
	Optab *t;
	Idlist *l;

	pc = i->pc;
	ss = 0;
	t = &opflags[i->op];
	f = t->flags;
	sz = t->size;
	s = fpoff(i->sm, &i->s);
	m = fpoff(i->mm, &i->m);
	d = fpoff(i->dm, &i->d);
	if(f&Mduse && i->mm == Anone)
		f |= Duse;
	if(s >= 0){
		if(i->sm == Afp){
			ss = SS(sz);
			if(ss == Mp)
				ss = size(i);
		}
		else
			ss = IBY2WD;
		id = finddec(s, ss, vars, &nv, i);
		if(f&Suse)
			setud(uses, id, nv, pc);
		if(f&Sdef){
			if(i->sm == Afp)
				setud(defs, id, nv, pc);
			else
				setud(uses, id, nv, pc);
		}
	}
	if(m >= 0){
		if(i->mm == Afp){
			sm = SM(sz);
			if(sm == Mp)
				sm = size(i);
		}
		else
			sm = IBY2WD;
		id = finddec(m, sm, vars, &nv, i);
		if(f&Muse)
			setud(uses, id, nv, pc);
		if(f&Mdef){
			if(i->mm == Afp)
				setud(defs, id, nv, pc);
			else
				setud(uses, id, nv, pc);
		}
	}
	if(d >= 0){
		if(i->dm == Afp){
			sd = SD(sz);
			if(sd == Mp)
				sd = size(i);
		}
		else
			sd = IBY2WD;
		id = finddec(d, sd, vars, &nv, i);
		if(f&Duse)
			setud(uses, id, nv, pc);
		if(f&Ddef){
			if(i->dm == Afp)
				setud(defs, id, nv, pc);
			else
				setud(uses, id, nv, pc);
		}
	}
	if(f&Tuse1){
		id = finddec(STemp, IBY2WD, vars, &nv, i);
		setud(uses, id, nv, pc);
	}
	if(f&Tuse2){
		id = finddec(DTemp, IBY2WD, vars, &nv, i);
		setud(uses, id, nv, pc);
	}
	if(i->op == ILEA){
		if(s >= 0){
			id = finddec(s, ss, vars, &nv, i);
			if(i->sm == Afp && i->m.reg == 0)
				setud(defs, id, nv, pc);
			else
				setud(uses, id, nv, pc);
		}
	}
	if(0)
	switch(i->op){
	case ILEA:
		if(s >= 0){
			id = finddec(s, ss, vars, &nv, i);
			if(id < 0)
				break;
			for(j = 0; j < nv; j++){
				if(i->sm == Afp && i->m.reg == 0)
					addlist(&deflist, id++);
				else
					addlist(&uselist, id++);
			}
		}
		break;
	case IALT:
	case INBALT:
	case ICALL:
	case IMCALL:
		for(l = deflist; l != nil; l = l->next){
			id = l->id;
			bset(defs[id], pc);
		}
		for(l = uselist; l != nil; l = l->next){
			id = l->id;
			bset(uses[id], pc);
		}
		freelist(&deflist);
		freelist(&uselist);
		break;
	}
}

static void
usedef(Inst *in, Decl *vars, Bits *uses, Bits *defs)
{
	Inst *i;

	for(i = in; i != nil; i = i->next)
		ud(i, vars, uses, defs);
}

static void
pusedef(Bits *ud, int nv, Decl *d, char *s)
{
	int i;

	print("%s\n", s);
	for(i = 0; i < nv; i++){
		if(!bzero(ud[i])){
			print("\t%s(%ld):	", decname(d), d->offset);
			pbits(ud[i]);
			print("\n");
		}
		d = d->next;
	}
}

static void
dummydefs(Bits *defs, int nv, int npc)
{
	int i;

	for(i = 0; i < nv; i++)
		bset(defs[i], npc++);
}

static void
dogenkill(Block *b, Bits *defs, int nv)
{
	int i, n, t;
	Bits v;

	n = defs[0].n;
	v = bnew(n, 0);
	for( ; b != nil; b = b->next){
		b->gen = bnew(n, 0);
		b->kill = bnew(n, 0);
		b->in = bnew(n, 0);
		b->out = bnew(n, 0);
		for(i = 0; i < nv; i++){
			boper(Bclr, v, v);
			bsets(v, b->first->pc, b->last->pc);
			boper(Band, defs[i], v);
			t = topbit(v);
			if(t >= 0)
				bset(b->gen, t);
			else
				continue;
			boper(Bclr, v, v);
			bsets(v, b->first->pc, b->last->pc);
			boper(Binv, v, v);
			boper(Band, defs[i], v);
			boper(Bor, v, b->kill);
		}
	}
	bfree(v);
}

static void
udflow(Block *b, int nv, int npc)
{
	int iter;
	Block *b0, *p;
	Blist *bl;
	Bits newin;

	b0 = b;
	for(b = b0; b != nil; b = b->next)
		boper(Bstore, b->gen, b->out);
	newin = bnew(b0->in.n, 0);
	iter = 1;
	while(iter){
		iter = 0;
		for(b = b0; b != nil; b = b->next){
			boper(Bclr, newin, newin);
			for(bl = b->pred; bl != nil; bl = bl->next){
				p = bl->block;
				boper(Bor, p->out, newin);
			}
			if(b == b0)
				bsets(newin, npc, npc+nv-1);
			if(!beq(b->in, newin))
				iter = 1;
			boper(Bstore, newin, b->in);
			boper(Bstore, b->in, b->out);
			boper(Bandrev, b->kill, b->out);
			boper(Bor, b->gen, b->out);
		}
	}
	bfree(newin);
}

static void
pflows(Block *b)
{
	for( ; b != nil; b = b->next){
		print("block %d\n", b->dfn);
		print("	gen:	"); pbits(b->gen); print("\n");
		print("	kill:	"); pbits(b->kill); print("\n");
		print("	in:	"); pbits(b->in); print("\n");
		print("	out:	"); pbits(b->out); print("\n");
	}
}

static int
set(Decl *d)
{
	if(d->store == Darg)
		return 1;
	if(d->sym == nil)	/* || d->sym->name[0] == '.') */
		return 1;
	if(tattr[d->ty->kind].isptr || d->ty->kind == Texception)
		return 1;
	return 0;
}

static int
used(Decl *d)
{
	if(d->sym == nil )	/* || d->sym->name[0] == '.') */
		return 1;
	return 0;
}

static void
udchain(Block *b, Decl *ds, int nv, int npc, Bits *defs, Bits *uses, Decl *sd)
{
	int i, n, p, q;
	Bits d, u, dd, ud;
	Block *b0;
	Inst *in;

	b0 = b;
	n = defs[0].n;
	u = bnew(n, 0);
	d = bnew(n, 0);
	dd = bnew(n, 0);
	ud = bnew(n, 0);
	for(i = 0; i < nv; i++){
		boper(Bstore, defs[i], ud);
		bclr(ud, npc+i);
		for(b = b0 ; b != nil; b = b->next){
			boper(Bclr, u, u);
			bsets(u, b->first->pc, b->last->pc);
			boper(Band, uses[i], u);
			boper(Bclr, d, d);
			bsets(d, b->first->pc, b->last->pc);
			boper(Band, defs[i], d);
			for(;;){
				p = topbit(u);
				if(p < 0)
					break;
				bclr(u, p);
				bclrs(d, p, -1);
				q = topbit(d);
				if(q >= 0){
					bclr(ud, q);
					if(debug['o'])
						print("udc b=%d v=%d(%s/%ld) u=%d d=%d\n", b->dfn, i, decname(ds), ds->offset, p, q);
				}
				else{
					boper(Bstore, defs[i], dd);
					boper(Band, b->in, dd);
					boper(Bandrev, dd, ud);
					if(!bzero(dd)){
						if(debug['o']){
							print("udc b=%d v=%d(%s/%ld) u=%d d=", b->dfn, i, decname(ds), ds->offset, p);
							pbits(dd);
							print("\n");
						}
						if(bmem(dd, npc+i) && !set(ds))
							warning(pc2i(b0, p), "used and not set", ds, sd);
					}
					else
						fatal("no defs in udchain");
				}
			}
		}
		for(;;){
			p = topbit(ud);
			if(p < 0)
				break;
			bclr(ud, p);
			if(!used(ds)){
				in = pc2i(b0, p);
				if(isnilsrc(&in->src))	/* nilling code */
					in->op = INOOP;	/* elim p from bitmaps ? */
				else if(limbovar(ds) && !structure(ds->ty))
					warning(in, "set and not used", ds, sd);
			}
		}
		ds = ds->next;
	}
	bfree(u);
	bfree(d);
	bfree(dd);
	bfree(ud);
}

static void
ckflags(void)
{
	int i, j, k, n;
	Optab *o;

	n = nelem(opflags);
	o = opflags;
	for(i = 0; i < n; i++){
		j = (o->flags&(Suse|Sdef)) != 0;
		k = SS(o->size) != 0;
		if(j != k){
			if(!(j == 0 && k == 1 && i == ILEA))
				fatal("S %ld %s\n", o-opflags, instname[i]);
		}
		j = (o->flags&(Muse|Mdef)) != 0;
		k = SM(o->size) != 0;
		if(j != k)
			fatal("M %ld %s\n", o-opflags, instname[i]);
		j = (o->flags&(Duse|Ddef)) != 0;
		k = SD(o->size) != 0;
		if(j != k){
			if(!(j == 1 && k == 0 && (i == IGOTO || i == ICASE || i == ICASEC || i == ICASEL)))
				fatal("D %ld %s\n", o-opflags, instname[i]);
		}
		o++;
	}
}

void
optim(Inst *in, Decl *d)
{
	int nb, npc, nv, nd, nu;
	Block *b;
	Bits *uses, *defs;
	Decl *sd;

	ckflags();
	if(debug['o'])
		print("************************************************\nfunction %s\n************************************************\n", d->sym->name);
	if(in == nil || errors > 0)
		return;
	d = d->ty->ids;
	if(regdecls == nil)
		mkdecls();
	regdecls->next->next->next = d;
	d = regdecls;
	sd = sharedecls(d);
	if(debug['o'])
		printdecls(d);
	b = mkblocks(in, &nb);
	ckblocks(in, b, nb);
	npc = inspc(in);
	nb = dfs(b, nb);
	if(debug['o'])
		pblocks(b, nb);
	loops(b);
	nv = len(d);
	uses = allocbits(nv, npc+nv);
	defs = allocbits(nv, npc+nv);
	dummydefs(defs, nv, npc);
	usedef(in, d, uses, defs);
	if(debug['o']){
		pusedef(uses, nv, d, "uses");
		pusedef(defs, nv, d, "defs");
	}
	nu = bitcount(uses, nv);
	nd = bitcount(defs, nv);
	dogenkill(b, defs, nv);
	udflow(b, nv, npc);
	if(debug['o'])
		pflows(b);
	udchain(b, d, nv, npc, defs, uses, sd);
	freeblks(b);
	freebits(uses, nv);
	freebits(defs, nv);
	if(debug['o'])
		print("nb=%d npc=%d nv=%d nd=%d nu=%d\n", nb, npc, nv, nd, nu);
}

