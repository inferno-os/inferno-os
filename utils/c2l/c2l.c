#define EXTERN

#include "cc.h"

/*
 *	locals, parameters, globals etc of the same name should work ok without having
 *	to duplicate Syms because the details are on the containing Nodes
 */

#define SZ_CHAR	1
#define SZ_SHORT	2
#define SZ_INT	4
#define SZ_LONG	4
#define SZ_FLOAT	4
#define SZ_IND	4
#define SZ_VLONG	8
#define SZ_DOUBLE	8

char buf[128], mbuf[128];
static Sym *sysop, *bioop, *libcop;
static int again;

#define INFINITY 0x7fffffff
#define	STAR	0x80
#define	RET		0x80

#define	LARR	(-1729)

static void swalk(void);
static int isdec(Node*);
static int isconst(Node*, vlong);
static int cktype(Node*, Node*, int, int);
static void addnode(int, Node*);
static int argpos(Node*, Node*);
static void setdec(Sym*, Type*);
static Type* tcp(Type*);
static int isadt(Type*);
static void aargs(Node*);
static int iteq(Type*, Type*);
static Node* arg(Node*, int);
static void etgen2(Sym*);
static Node* ckneg(Node*);
static Sym* suename(Type*);
static int isnil(Node*);
static void sliceasgn(Node*);
static Node* lastn(Node*);
static char* hasm(void);
static void prn(Node*, int);
static int isfn(Type*);

schar	ewidth[NTYPE] =
{
	-1,		/* [TXXX] */
	SZ_CHAR,	/* [TCHAR] */
	SZ_CHAR,	/* [TUCHAR] */
	SZ_SHORT,	/* [TSHORT] */
	SZ_SHORT,	/* [TUSHORT] */
	SZ_INT,		/* [TINT] */
	SZ_INT,		/* [TUINT] */
	SZ_LONG,	/* [TLONG] */
	SZ_LONG,	/* [TULONG] */
	SZ_VLONG,	/* [TVLONG] */
	SZ_VLONG,	/* [TUVLONG] */
	SZ_FLOAT,	/* [TFLOAT] */
	SZ_DOUBLE,	/* [TDOUBLE] */
	SZ_IND,		/* [TIND] */
	0,		/* [TFUNC] */
	-1,		/* [TARRAY] */
	0,		/* [TVOID] */
	-1,		/* [TSTRUCT] */
	-1,		/* [TUNION] */
	SZ_INT,		/* [TENUM] */
};

long	ncast[NTYPE] =
{
	0,				/* [TXXX] */
	BCHAR|BUCHAR,			/* [TCHAR] */
	BCHAR|BUCHAR,			/* [TUCHAR] */
	BSHORT|BUSHORT,			/* [TSHORT] */
	BSHORT|BUSHORT,			/* [TUSHORT] */
	BINT|BUINT|BLONG|BULONG|BIND,	/* [TINT] */
	BINT|BUINT|BLONG|BULONG|BIND,	/* [TUINT] */
	BINT|BUINT|BLONG|BULONG|BIND,	/* [TLONG] */
	BINT|BUINT|BLONG|BULONG|BIND,	/* [TULONG] */
	BVLONG|BUVLONG,			/* [TVLONG] */
	BVLONG|BUVLONG,			/* [TUVLONG] */
	BFLOAT,				/* [TFLOAT] */
	BDOUBLE,			/* [TDOUBLE] */
	BLONG|BULONG|BIND,		/* [TIND] */
	0,				/* [TFUNC] */
	0,				/* [TARRAY] */
	0,				/* [TVOID] */
	BSTRUCT,			/* [TSTRUCT] */
	BUNION,				/* [TUNION] */
	0,				/* [TENUM] */
};

enum{
	TCFD = 1,
	TCFC = 2,
	TCPC = 4,
	TCAR = 8,
	TCIN = 16,
	TCGEN = TCFD|TCFC|TCPC|TCAR,
	TCALL = TCFD|TCFC|TCPC|TCAR|TCIN,
};

enum{
	SGLOB,
	SPARM,
	SAUTO,
};

typedef struct Scope Scope;

struct Scope{
	Node *n;
	int	k;
	Scope *nxt;
};

static void
prtyp(Type *t, char *s, int nl)
{
	print("%s: ", s);
	if(t == T){
		print("nil");
		if(nl)
			print("\n");
		return;
	}
	while(t != T){
		print("%d(%d)[%x] ", t->etype, t->mark, (int)t);
		if(isadt(t))
			break;
		t = t->link;
	}
	if(nl)
		print("\n");
}

static Node*
func(Node *n)
{
	while(n != Z && n->op != OFUNC)
		n = n->left;
	return n;
}

static void
setmain(Node *n)
{
	inmain |= n->left->op == ONAME && strcmp(n->left->sym->name, "main") == 0;
}

static Node*
protoname(Node *n)
{
	do
		n = n->left;
	while(n != Z && n->op != ONAME && n->op != ODOTDOT);
	return n;
}

static Type*
prototype(Node *n, Type *t)
{
	for( ; n != Z ; n = n->left){
		switch(n->op){
		case OARRAY:
			t = typ(TARRAY, t);
			t->width = 0;
			break;
		case OIND:
			t = typ(TIND, t);
			break;
		case OFUNC:
			t = typ(TFUNC, t);
			t->down = fnproto(n);
			break;
		}
	}
	return t;
}

static Scope *scopes, *freescopes;

static void
pushdcl(Node *n, int c)
{
	Sym *s;

	if(passes){
		s = n->sym;
		push1(s);
		if(c != CAUTO || s->class != CSTATIC)
			s->class = c;
		s->type = n->type;
	}
}

static void
pushparams(Node *n)
{
	if(n == Z)
		return;
	if(passes){
		if(n->op == OLIST){
			pushparams(n->left);
			pushparams(n->right);
		}
		else if(n->op == OPROTO){
			n = protoname(n);
			if(n != Z && n->op == ONAME)
				pushdcl(n, CPARAM);
		}
		else if(n->op == ONAME){
			addnode(OPROTO, n);
			pushdcl(n, CPARAM);
		}
		else if(n->op != ODOTDOT)
			diag(Z, "bad op in pushparams");
	}
}

static void
pushscope(Node *n, int k)
{
	Scope *s;

	if(freescopes != nil){
		s = freescopes;
		freescopes = freescopes->nxt;
	}
	else
		s = (Scope*)malloc(sizeof(Scope));
	s->n = n;
	s->k = k;
	s->nxt = scopes;
	scopes = s;
	if(passes && (k == SPARM || k == SAUTO))
		markdcl();
	if(k == SPARM)
		pushparams(n->right);
}

static void
popscope(void)
{
	int k;
	Scope *s;

	s = scopes;
	k = s->k;
	scopes = scopes->nxt;
	s->nxt = freescopes;
	freescopes = s;
	if(passes && (k == SPARM || k == SAUTO))
		revertdcl();
}

static Node*
curfn(void)
{
	Scope *s;

	for(s = scopes; s != nil; s = s->nxt)
		if(s->k == SPARM)
			return s->n;
	return Z;
}

static void
marktype(Type *t, int tc)
{
	t->mark = tc;
}

static int
marked(Type *t)
{
	return t == T ? 0 :  t->mark;
}

static Sym*
decsym(Node *n)
{
	if(n == Z)
		return S;
	if(n->op == OFUNC){
		if(n->left->op == ONAME)
			return n->left->sym;
		return S;
	}
	if(n->op == ODAS)
		return n->left->sym;
	return n->sym;
}

static void
trep(Type *t1, Type *t)
{
	int l;
	Sym *s;
	Type *t2;

	if(t1 != T){
		l = t1->lineno;
		s = t1->sym;
		t2 = t1->down;
		*t1 = *t;
		t1->down = t2;
		t1->sym = s;
		t1->lineno = l;
	}
}

static void
tind(Node *n)
{
	if(n == Z)
		return;
	n = protoname(n);
	if(n != Z && n->type != T){
		n->type = tcp(n->type->link);
		marktype(n->type, TCIN);
	}
}

static void
tcon(Node *n, Type *t)
{
	Type *tt;

	if(n->garb)
		return;
	n->garb = 1;
	again = 1;
	switch(n->op){
		case OCONST:
			if(t->mark == TCFD && !isnil(n))
				addnode(OFILDES, n);
			n->type = t;
			break;
		case OCAST:
			tcon(n->left, t);
			*n = *n->left;
			n->type = t;
			break;
		case ONAME:
			n->sym->type = t;
			n->type = t;
			setdec(n->sym, t);
			break;
		case ODOT:
		case ODOTIND:
			trep(n->type, t);
			n->type = t;
			break;
		case OARRIND:
			tt = n->left->type;
			if(tt != T)
				tt->link = t;
			n->type = t;
			break;
		case OFUNC:
			n->left->type->link = t;
			if(n->left->op == ONAME)
				n->left->sym->type->link = t;
			n->type = t;
			break;
	}
}

static Node*
retval(Node *n)
{
	int i;
	Type *t;
	Node *a, *l, *cf;

	cf = curfn();
	t = cf->left->type->link;
	if(t->mark&(TCPC|TCFC) && (n == Z || !(n->type->mark&(TCPC|TCFC)))){
		if(n == Z)
			n = new1(ORETURN, Z, Z);
		l = n->left;
		for(i = 0; ; i++){
			a = arg(cf->right, i);
			if(a == Z)
				break;
			a = protoname(a);
			if(a == Z || a->op != ONAME)
				break;
			if(a->type->mark == TCIN){
				if(l == Z)
					l = ncopy(a);
				else
					l = new1(OTUPLE, l, ncopy(a));
			}
		}
		n->left = l;
		n->type = l->type = t;
	}
	return n;
}

static void
sube(Node *n)
{
	Node *l, *r, *nn;
	Type *tt;
	static Node *gn;
	int p;

	if(n == Z)
		return;
	l = n->left;
	r = n->right;
	switch(n->op){
		default:
			sube(l);
			sube(r);
			break;
		case OIND:
			if(l == Z)
				return;
			tt = l->type;
			sube(l);
			if(cktype(l, n, TCIN, 0) && iteq(tt, l->type))
				*n = *n->left;
			break;
		case OARRIND:
			tt = l->type;
			sube(l);
			sube(r);
			if(!isconst(r, 0))
				break;
			if(cktype(l, n, TCIN, 0) && iteq(tt, l->type))
				*n = *n->left;
			break;
		case ONAME:
			if(cktype(n, n, TCALL, 0))
				setdec(n->sym, n->type);
			break;
		case OCAST:
			sube(l);
			if(cktype(l, n, TCALL, 0))
				n->type = l->type;
			break;
		case OPROTO:
			sube(l);
			sube(r);
			nn = protoname(n);
			if(nn != Z && cktype(nn, n, TCALL, 0)){
				n->type = nn->type;
				p = argpos(n, gn->right);
				for(tt = gn->left->type->down; tt != T && p >= 0; tt = tt->down){
					if(p == 0){
						trep(tt, nn->type);
						break;
					}
					--p;
				}
			}
			break;
		case OFUNC:
			if(n->kind == KEXP)
				aargs(n);
			if(n->left->op == ONAME)
				gn = n;
			sube(l);
			sube(r);
			if(l != Z && cktype(n, n, TCGEN, 0))
				l->type->link = n->type;
			break;
		case OAS:
			sube(l);
			sube(r);
			if(r->op == ORETV){
				n->left = new1(OTUPLE, l, r->right);
				n->right = r->left;
				n->left->type = n->type;
				break;
			}
			if(cktype(r, n, TCGEN, 0)){
				tcon(l, r->type);
				n->type = r->type;
			}
			if(cktype(l, n, TCGEN, 1)){
				tcon(r, l->type);
				n->type = l->type;
			}
			break;
		case OLT:
		case OGE:
			sube(l);
			sube(r);
			if(cktype(l, n, TCFD, 0) && isconst(r, 0)){
				n->op = n->op == OLT ? OEQ : ONE;
				r->op = ONIL;
				r->type = l->type;
			}
			break;
		case OGT:
		case OLE:
			sube(l);
			sube(r);
			if(cktype(r, n, TCFD, 0) && isconst(l, 0)){
				n->op = n->op == OGT ? OEQ : ONE;
				l->op = ONIL;
				l->type = r->type;
			}
			break;
	}
}

static void
subs(Node *n, int blk, int aut)
{
	Node *l, *r;

	if(n == Z)
		return;
	if(blk)
		pushscope(n, SAUTO);
	nearln = n->lineno;
	l = n->left;
	r = n->right;
	switch(n->op){
		default:
			sube(n);
			break;
		case ONAME:
			if(aut && n->kind != KEXP)
				pushdcl(n, CAUTO);
			if(cktype(n, n, TCALL, 0))
				setdec(n->sym, n->type);
			break;
		case ODAS:
			if(aut)
				pushdcl(l, CAUTO);
			subs(l, 0, aut);
			if(cktype(l, n, TCALL, 0))
				tcon(r, l->type);
			break;
		case OSBREAK:
		case ONUL:
		case OLABEL:
		case OGOTO:
		case OCONTINUE:
		case OBREAK:
		case OSET:
		case OUSED:
			break;
		case OBLK:
			subs(l, 1, aut);
			break;
		case OCASE:
			subs(r, 1, aut);
			break;
		case OLIST:
			subs(l, 0, aut);
			subs(r, 0, aut);
			break;
		case ORETURN:
			sube(l);
			if(l != Z && cktype(l, n, TCGEN, 0)){
				n->type = l->type;
				tcon(curfn(), l->type);
			}
			retval(n);
			break;
		case OSWITCH:
		case OWHILE:
		case ODWHILE:
			sube(l);
			subs(r, 1, aut);
			break;
		case OIF:
			sube(l);
			subs(r->left, 1, aut);
			subs(r->right, 1, aut);
			break;
		case OFOR:
			sube(l->left);
			sube(l->right->left);
			sube(l->right->right);
			subs(r, 1, aut);
			break;
	}
	if(blk)
		popscope();
}

static Node*
finddec0(Sym *s, Node *n)
{
	Node *nn;

	if(n == Z)
		return ZZ;
	switch(n->op){
		case OLIST:
			nn = finddec0(s, n->left);
			if(nn != Z)
				return nn;
			return finddec0(s, n->right);
		case OFUNC:
			if(n->op != KEXP){
				if(s == decsym(n))
					return n;
				return finddec0(s, n->right);
			}
			else
				return ZZ;
		case OPROTO:
		case OIND:
		case OARRAY:
			return finddec0(s, n->left);
		case ODOTDOT:
			return ZZ;
		case ONOOP:
		case OPUSH:
		case OPOP:
		case OCODE:
		case ODECE:
		case ODECT:
			return finddec0(s, n->right);
		case ODECV:
		case ODECF:
			if(s == decsym(n->left) && !isfn(n->left->type))
				return n->left;
			return finddec0(s, n->right);
	}
	if(isdec(n)){
		if(s == decsym(n) && !isfn(n->type))
			return n;
		return Z;
	}
	return ZZ;
}

static Node*
finddec(Sym *s, int g)
{
	Node *n;
	Scope *sc;

	for(sc = scopes; sc != nil; sc = sc->nxt){
		if(!g || sc->k == SGLOB){
			n = finddec0(s, sc->n);
			if(n != Z && n != ZZ)
				return n;
		}
	}
	return Z;	
}

static void
setdec(Sym *s, Type *t)
{
	Node *n;

	if((n = finddec(s, 0)) != Z){
		n->type = t;
		if(n->op == ODAS){
			n = n->left;
			n->type = t;
		}
		n->sym->type = t;
	}
}
		
typedef struct Syml Syml;

struct Syml{
	Sym *sym;
	Syml *nxt;
};

typedef struct Symq Symq;

struct Symq{
	Syml *f;
	Syml *r;
};

typedef struct Modl Modl;

struct Modl{
	char *mod;
	int	ld;
	Modl *nxt;
};

static void
prn(Node *n, int i)
{
	int j;

	for(j = 0; j < i; j++)
		print("\t");
	if(n == Z){
		print("Z\n");
		return;
	}
	print("%s", onames[n->op]);
	if(n->blk)
		print("	block");
	if(n->type == T)
		print("	T");
	else
		print("	%s", tnames[n->type->etype]);
	if(n->op == OCONST)
		print("	%d", (int)n->vconst);
	else if(n->op == OSTRING)
		print("	%s", n->cstring);
	else if(n->op == ONAME)
		print("	%s", n->sym->name);
	print("\n");
	if(n->op != OLIST)
		i++;
	prn(n->left, i);
	prn(n->right, i);
}

static int
isbigv(vlong v)
{
	return v > 0xffffffff;
}

static int
islbigv(vlong v)
{
	return v > 0x7fffffff || v < -0x7fffffff;
}

static int
isuintv(vlong v)
{
	return !isbigv(v) && (v&0x80000000) != 0;
}

static int
isadt(Type *t)
{
	return t != T && (t->etype == TSTRUCT || t->etype == TUNION);
}

static int
isreal(Type *t)
{
	return t != T && (t->etype == TDOUBLE || t->etype == TFLOAT);
}

static int
isbyte(Type *t)
{
	return t != T && (t->etype == TCHAR || t->etype == TUCHAR);
}

static int
isshort(Type *t)
{
	return t != T && (t->etype == TSHORT || t->etype == TUSHORT);
}

static int
isint(Type *t)
{
	return t != T && (t->etype == TINT || t->etype == TUINT);
}

static int
islong(Type *t)
{
	return t != T && (t->etype == TLONG || t->etype == TULONG);
}

static int
isbig(Type *t)
{
	return t != T && (t->etype == TVLONG || t->etype == TUVLONG);
}

static int
isinteger(Type *t)
{
	return isbyte(t) || isshort(t) || isint(t) || islong(t) || isbig(t);
}

static int
isptr(Type *t)
{
	return t != T && (t->etype == TIND || t->etype == TARRAY || t->etype == TFUNC);
}

static int
isscalar(Type *t)
{
	return t != T && !isadt(t) && t->etype != TTUPLE;
}

static int
isvoid(Type *t)
{
	return t == T || t->etype == TVOID;
}

static int
isnum(Type *t)
{
	return t != T && isscalar(t) && !isptr(t) && !isvoid(t);
}

static int
isarray(Type *t)
{
	return t != T && (t->etype == TARRAY || (t->etype == TIND && !isadt(t->link)));
}

static int
isstr(Type *t)
{
	return t != T && (t->etype == TSTRING || isarray(t) && isbyte(t->link));
}

static int
isfn(Type *t)
{
	return t != T && t->etype == TFUNC;
}

static int
iscastable(Type *t, Type *tt)
{
	return t != T && (!isptr(t) || isarray(t) && isbyte(t->link) && isstr(tt));
}

static int
isname(Node *n)
{
	return n->op == ONAME;
}

static int
isstring(Node *n)
{
	return n->op == OSTRING || n->op == OLSTRING || n->op == ONAME && n->sym->tenum != T && n->sym->tenum->etype == TIND;
}

static int
isnil(Node *n)
{
	if(!isptr(n->type))
		return 0;
	while(n->op == OCAST)
		n = n->left;
	return n->op == OCONST && n->vconst == 0 || n->op == ONIL;
}

static int
isconst(Node *n, vlong v)
{
	while(n->op == OCAST)
		n = n->left;
	return n->op == OCONST && n->vconst == v;
}

static Node*
cknil(Node *n)
{
	if(isconst(n, 0))
		n->op = ONIL;
	return n;
}

static int
cktype(Node *n, Node *t, int mask, int lev)
{
	int g, m, m0;

	g = t->garb > lev;
	m = marked(n->type) & mask;
	if(n->op == ONAME){
		m0 = marked(n->sym->type) & mask;
		if(m && !m0){
			n->sym->type = n->type;
			if(!g)
				again = 1;
		}
		if(!m && m0){
			n->type = n->sym->type;
			if(!g)
				again = 1;
		}
		m |= m0;
	}
	if(m && t->garb < 2)
		t->garb++;
	return m && !g ? m : 0;
}

int
isconsym(Sym *s)
{
	switch(s->class){
		case CXXX:
		case CTYPEDEF:
			return 1;
		case CEXTERN:
		case	CGLOBL:
		case CSTATIC:
		case CLOCAL:
			return s->type != T && s->type->etype == TENUM;
	}
	return -1;
}

static void genstart(void);

static char*
mprolog[] =
{
	"%%: module",
	"{",
	"\tPATH: con \"%%%.dis\";",
	"",
	nil
};

static char*
mepilog[] =
{
	"};",
	nil
};

static char*
bprolog[] =
{
	"implement %%;",
	"",
	"include \"draw.m\";",
	"",
	"%%: module",
	"{",
	"	init: fn(nil: ref Draw->Context, argl: list of string);",
	"};",
	"",
	nil
};

static char*
bmprolog[] =
{
	"implement %%;",
	"",
	"include \"draw.m\";",
	"",
	nil
};

static char*
bepilog[] =
{
	nil
};

static void
pgen0(char **txt)
{
	int sub;
	char *b, *s, *t, **p;

	p = txt;
	for(;;){
		s = *p++;
		if(s == nil)
			break;
		sub = 0;
		for(t = s; *t != 0; t++){
			if(*t == '%' && *(t+1) == '%'){
				sub = 1;
				break;
			}
		}
		if(sub){
			strcpy(buf, s);
			b = buf;
			for(t = s; *t != 0; t++){
				if(*t == '%' && *(t+1) == '%'){
					if(*(t+2) == '%'){
						outmod(mbuf, 0);
						t++;
					}
					else
						outmod(mbuf, 1);
					strcpy(b, mbuf);
					b += strlen(mbuf);
					t++;
				}
				else
					*b++ = *t;
			}
			*b = 0;
			prline(buf);
		}
		else			
			prline(s);
	}
}

static char*
hasm()
{
	outmod(mbuf, 0);
	strcat(mbuf, ".m");
	if(exists(mbuf))
		return mbuf;
	else if(domod){
		outmod(buf, 0);
		strcat(buf, ".h");
		if(exists(buf))
			return mbuf;
	}
	return nil;
}

void
pgen(int b)
{
	char **p;

	if(!dolog())
		return;
	if(b)
		p = hasm() ? bmprolog : bprolog;
	else
		p = mprolog;
	pgen0(p);
	if(b && passes)
		genstart();
	if(!b)
		incind();
}

void
epgen(int b)
{
	char **p;

	/* output(INFINITY, 1); */
	if(!dolog())
		return;
	if(b){
		if(!passes)
			genstart();
		p = bepilog;
	}
	else
		p = mepilog;
	if(!b)
		decind();
	pgen0(p);
}

static int lastsec = 0;

#define ASSOC		1
#define RASSOC	2
#define POSTOP	4

#define LEFT	1
#define RIGHT	2
#define PRE	4
#define POST	8

static int space[] = { 0, 0, 2, 0, 4, 5, 0, 0, 0, 9, 10, 0, 0, 0, 0, 0, 0, 0, 0 };

static struct{
	char *name;
	int	prec;
	int	kind;
} ops[] = {
	"",		0,	0,	/* ONOOP */
	"",		16,	0,	/* OXXX, */
	"+",		12,	ASSOC,	/* OADD, */
	"&",		14,	RASSOC,	/* OADDR, */
	"&",		8,	ASSOC,	/* OAND, */
	"&&",	5,	ASSOC,	/* OANDAND, */
	"",		16,	0,	/* OARRAY, */
	"=",		2,	RASSOC,	/* OAS, */
	"=",		2,	RASSOC,	/* OASI, */
	"+=",		2,	RASSOC,	/* OASADD, */
	"&=",		2,	RASSOC,	/* OASAND, */
	"<<=",	2,	RASSOC,	/* OASASHL, */
	">>=",	2,	RASSOC,	/* OASASHR, */
	"/=",		2,	RASSOC,	/* OASDIV, */
	"<<",		11,	0,	/* OASHL, */
	">>",		11,	0,	/* OASHR, */
	"/=",		2,	RASSOC,	/* OASLDIV, */
	"%=",		2,	RASSOC,	/* OASLMOD, */
	"*=",		2,	RASSOC,	/* OASLMUL, */
	">>=",	2,	RASSOC,	/* OASLSHR, */
	"%=",		2,	RASSOC,	/* OASMOD, */
	"*=",		2,	RASSOC,	/* OASMUL, */
	"|=",		2,	RASSOC,	/* OASOR, */
	"-=",		2,	RASSOC,	/* OASSUB, */
	"^=",		2,	RASSOC,	/* OASXOR, */
	"",		-1,	0,	/* OBIT, */
	"",		-1,	0,	/* OBREAK, */
	"",		-1,	0,	/* OCASE, */
	"",		14,	RASSOC,	/* OCAST, */
	"",		1,	ASSOC,	/* OCOMMA, */
	"",		3,	RASSOC,	/* OCOND, */
	"",		16,	0,	/* OCONST, */
	"",		-1,	0,	/* OCONTINUE, */
	"/",		13,	0,	/* ODIV, */
	".",		15,	0,	/* ODOT, */
	"...",		16,	0,	/* ODOTDOT, */
	"",		-1,	0,	/* ODWHILE, */
	"",		-1,	0,	/* OENUM, */
	"==",		9,	0,	/* OEQ, */
	"",		-1,	0,	/* OFOR, */
	"",		15,	0,	/* OFUNC, */
	">=",		10,	0,	/* OGE, */
	"",		-1,	0,	/* OGOTO, */
	">",		10,	0,	/* OGT, */
	">",		10,	0,	/* OHI, */
	">=",		10,	0,	/* OHS, */
	"",		-1,	0,	/* OIF, */
	"*",		14,	RASSOC,	/* OIND, */
	"",		-1,	0,	/* OINDREG, */
	"",		16,	0,	/* OINIT, */
	"",		-1,	0,	/* OLABEL, */
	"/",		13,	0,	/* OLDIV, */
	"<=",		10,	0,	/* OLE, */
	"",		16,	0,	/* OLIST, */
	"%",		13,	0,	/* OLMOD, */
	"*",		13,	ASSOC,	/* OLMUL, */
	"<",		10,	0,	/* OLO, */
	"<=",		10,	0,	/* OLS, */
	">>",		11,	0,	/* OLSHR, */
	"<",		10,	0,	/* OLT, */
	"%",		13,	0,	/* OMOD, */
	"*",		13,	ASSOC,	/* OMUL, */
	"",		16,	0,	/* ONAME, */
	"!=",		9,	0,	/* ONE, */
	"!",		14,	RASSOC,	/* ONOT, */
	"|",		6,	ASSOC,	/* OOR, */
	"||",		4,	ASSOC,	/* OOROR, */
	"--",		14,	RASSOC|POSTOP,	/* OPOSTDEC, */
	"++",		14,	RASSOC|POSTOP,	/* OPOSTINC, */
	"--",		14,	RASSOC,	/* OPREDEC, */
	"++",		14,	RASSOC,	/* OPREINC, */
	"",		16,	0,	/* OPROTO, */
	"",		-1,	0,	/* OREGISTER, */
	"",		0,	0,	/* ORETURN, */
	"SET",	-1,	0,	/* OSET, */
	"signof",	14,	RASSOC,	/* OSIGN, */
	"sizeof",	14,	RASSOC,	/* OSIZE, */
	"",		16,	0,	/* OSTRING, */
	"",		16,	0,	/* OLSTRING, */
	"",		16,	0,	/* OSTRUCT, */
	"-",		12,	0,	/* OSUB, */
	"",		-1,	0,	/* OSWITCH, */
	"",		16,	0,	/* OUNION, */
	"USED",	-1,	0,	/* OUSED, */
	"",		-1,	0,	/* OWHILE, */
	"^",		7,	ASSOC,	/* OXOR, */
	"-",		14,	RASSOC,	/* ONEG, */
	"~",		14,	RASSOC,	/* OCOM, */
	"",		16,	0,	/* OELEM, */
	"",		-1,	0,	/* OTST, */
	"",		-1,	0,	/* OINDEX, */
	"",		-1,	0,	/* OFAS, */
	"",		-1,	0,	/* OBLK */
	"+",		14,	RASSOC,	/* OPOS */
	"",		-1,	0,	/* ONUL */
	".",		15,	0,	/* ODOTIND */
	"",		15,	0,	/* OARRIND */
	"",		-1,	0,	/* ODAS */
	":=",		2,	RASSOC,	/* OASD */
	"",		16,	0,	/* OIOTA */
	"",		14,	RASSOC,	/* OLEN */
	"",		17,	0,	/* OBRACKET */
	"",		14,	RASSOC,	/* OREF */
	"",		14,	RASSOC,	/* OARRAYOF */
	"",		15,	0,	/* OSLICE */
	"&",		14,	RASSOC,	/* OSADDR, */
	"",		16,	0,	/* ONIL */
	"",		16,	0,	/* OS2AB */
	"",		16,	0,	/* OAB2S */
	"",		16,	0,	/* OFILDES */
	".",		15,	0,	/* OFD */
	"",		16,	0,	/* OTUPLE */
	".",		15,	0,	/* OT0 */
	"",		15,	0,	/* ORETV */
	"+",		12,	ASSOC,	/* OCAT */
	"",		-1,	0,	/* OSBREAK, */
	".",		15,	0,	/* OLDOT */
	"->",		15,	0,	/* OMDOT */
	nil,		-1,	0,	/* OCODE */
	nil,		-1,	0,	/* ODECE */
	nil,		-1,	0,	/* ODECT */
	nil,		-1,	0,	/* ODECV */
	nil,		-1,	0,	/* ODECF */
	nil,		-1,	0,	/* OPUSH */
	nil,		-1,	0,	/* OPOP */
	"",		-1,	0,	/* OEND */
};

#define COMPLEX	32

#define NOBR	2
#define NOIN	4
#define YESBR	8
#define NONL	16
#define NOENL	32

enum{
	LNONE,
	LSTRLEN,
	LSTRCMP,
	LSTRCPY,
	LSTRCAT,
	LSTRNCMP,
	LSTRNCPY,
	LSTRNCAT,
	LSTRDUP,
	LMEMMOVE,
	LMALLOC,
	LFREE,
	LEXIT,
	LCLOSE,
	LATOI,
	LATOL,
	LATOF,
	LPRINT,
	LFPRINT,
	LSPRINT,
	LSELF,
};

static int tmp;

static void egen(Node*, int, int);
static Node* buildcases(Node*);
static void tdgen(Node *, int);
static Node* cfind(Node*);
static Node* cgen(Node*, Node*);
static void cgen0(Node*, Node*);
static int lteq(Type*, Type*);
static Type* ntype(Node*);
static int rewe(Node*, Type*, int);
static void rewlc(Node*, int, Type*);
static Node* con(vlong);
static void	clrbrk(Node*);
static int hasbrk(Node*);
static int isgen(char*);
static int simple(Node*);
static void pfmt(char*);
static void lpfmt(ushort*);
static int lline(Node*);
static void args(Node*);
static void addmodn(Sym*);
static void scomplex(Node*);
static void mset(Node*);

static Node *lastd;

static int
rev(int op)
{
	switch(op){
		case OLT:	return OGT;
		case OLE:	return OGE;
		case OGT:	return OLT;
		case OGE:	return OLE;
	}
	return op;
}

void
newsec(int l)
{
	if(l != 1 && lastd != Z){
		tdgen(lastd, 1);
		lastd = Z;
	}
	if(l != 2)
		etgen2(nil);
	if(lastsec && l != lastsec)
		newline();
	lastsec = l;
}

static Node*
defval(Type *t)
{
	Node *n;

	if(t == T)
		t = types[TINT];
	n = con(0);
	n->type = types[TINT];
	n->kind = KDEC;
	switch(t->etype){
		case TFLOAT:
		case TDOUBLE:
			n->type = types[TDOUBLE];
			n->fconst = 0.0;
			n->cstring = "0.0";
			return n;
		default:
			break;
		case TIND:
		case TFUNC:
		case TARRAY:
			n->type = typ1(TIND, types[TVOID]);
			return n;
		case TVOID:
		case TSTRUCT:
		case TUNION:
			free(n);
			return Z;
	}
	if(!lteq(n->type, t)){
		n = new1(OCAST, n, Z);
		n->type = t;
	}
	return n;
}

static int
teq(Type *t1, Type *t2)
{
	if(t1 == t2)
		return 1;
	return sametype(t1, t2);
/*
	if(t1->etype != t2->etype)
		return 0;
	switch(t1->etype){
		case TARRAY:
			if(t1->width != t2->width)
				return 0;
			break;
		case TFUNC:
			if(!teq(t1->down, t2->down))
				return 0;
			break;
		case TSTRUCT:
		case TUNION:
			return t1->link == t2->link;
		case TENUM:
			return 1;
	}
	return teq(t1->link, t2->link);
*/
}

static int
tequiv(Type *t1, Type *t2)
{
	if(!teq(t1, t2))
		return 0;
	if(t1->etype == TSTRUCT || t1->etype == TUNION)
		return suename(t1) == suename(t2);
	return 1;
}

static int
iteq(Type *t1, Type *t2)
{
	if(t1 == T || t2 == T)
		return 0;
	return t1->etype == TIND && (teq(t1->link, t2) || (t1->link->etype == TVOID && isnum(t2)));
}

static Type *
ltype(Type *t)
{
	switch(t->etype){
		case TUCHAR:
			return types[TCHAR];
		case TSHORT:
		case TUSHORT:
		case TUINT:
		case TLONG:
		case TULONG:
		case TENUM:
			return types[TINT];
		case TUVLONG:
			return types[TVLONG];
		case TFLOAT:
			return types[TDOUBLE];
		default:
			return t;
	}
	return t;
}

static int
lteq(Type *t1, Type *t2)
{
	if(t1 == T || t2 == T)
		return 0;
	if(t1 == t2)
		return 1;
	if(t1->etype == TIND && t2->etype == TIND)
		return lteq(t1->link, t2->link);
	return sametype(ltype(t1), ltype(t2));
}

static Type*
tcp(Type *t)
{
	Type *nt;

	if(t == T)
		return T;
	nt = typ1(TXXX, T);
	*nt = *t;
	return nt;
}

static Type*
tuple(Type *t1, Type *t2)
{
	Type *t, **at, *l;

	if(t1 == T || t1->etype == TVOID)
		return tcp(t2);
	if(t2 == T || t2->etype == TVOID)
		return tcp(t1);
	if(t2->etype == TTUPLE)
		diag(Z, "bad tuple type");
	t = typ1(TTUPLE, T);
	at = &t->link;
	if(t1->etype == TTUPLE){
		for(l = t1->link; l != T; l = l->down){
			*at = tcp(l);
			at = &(*at)->down;
		}
	}
	else{
		*at = tcp(t1);
		at = &(*at)->down;
	}
	*at = tcp(t2);
	return t;
}

static Sym*
sue(Type *t)
{
	int h;
	Sym *s;

	if(t != T)
		for(h=0; h<nelem(hash); h++)
			for(s = hash[h]; s != S; s = s->link)
				if(s->suetag && s->suetag->link == t)
					return s;
	return S;
}

static void
pranon(int i)
{
	prid("anon_");
	prnum(i+1, KDEC, T);
}

static int
dotpath(Sym *s, Type *t, int pr)
{
	int i;
	Type *t1;

	if(t == T)
		return 0;
	for(t1 = t->link; t1 != T; t1 = t1->down){
		if(t1->sym == s){
			if(pr){
				prdelim(".");
				prsym(s, 0);
			}
			return 1;
		}
	}
	i = 0;
	for(t1 = t->link; t1 != T; t1 = t1->down){
		if(t1->sym == S){
			i++;
			if(typesu[t1->etype] && sametype(s->type, t1)){
				if(pr){
					prdelim(".");
					pranon(i-1);
				}
				return 1;
			}
		}
	}
	i = 0;
	for(t1 = t->link; t1 != T; t1 = t1->down){
		if(t1->sym == S){
			i++;
			if(typesu[t1->etype] && dotpath(s, t1, 0)){
				if(pr){
					prdelim(".");
					pranon(i-1);
					dotpath(s, t1, 1);
				}
				return 1;
			}
		}
	}
	return 0;
}

static Sym*
suename(Type *t)
{
	Sym *s;

	s = sue(t->link);
	if(s != S)
		return s;
	else if(t->tag != S)
		return t->tag;
	else if(t->sym != S)
		return t->sym;
	return S;
}

static int
cycle(Type *t, Type *base)
{
	int r;
	Type *l;

	if(t->vis){
		/* sametype() does structural comparison so have to check names */
		if(t == base || tequiv(t, base))
			return 1;
		return 0;
	}
	r = 0;
	t->vis = 1;
	switch(t->etype){
		case TIND:
		case TARRAY:
			r = cycle(t->link, base);
			break;
		case TSTRUCT:
		case TUNION:
		case TTUPLE:
			for(l = t->link; l != T; l = l->down)
				r |= cycle(l, base);
			break;
	}
	t->vis = 0;
	return r;
}

static void
addnode(int op, Node *n)
{
	Node *nn;

	nn = new1(OXXX, Z, Z);
	*nn = *n;
	n->op = op;
	n->left = nn;
	n->right = Z;
	n->type = nn->type;
}

static void
cast(Node *n, Type *t)
{
	addnode(OCAST, n);
	n->type = t;
}

static void
intcast(Node *n)
{
	if(isptr(n->type)){
		addnode(ONE, n);
		n->right = con(0);
		n->right->type = n->left->type;
		n->type = types[TINT];
	}
	else
		cast(n, types[TINT]);
}

static void
strcast(Node *n)
{
	cast(n, stringtype);
}

static void
bptr(Node *n)
{
	if(n == Z)
		return;
	switch(n->op){
		default:
			if(!lteq(n->type, types[TINT]))
				intcast(n);
			break;
		case ONOT:
			if(!lteq(n->left->type, types[TINT])){
				intcast(n->left);
				if(n->left->op == ONE){
					n->left->op = OEQ;
					*n = *n->left;
				}
			}
			break;
		case OANDAND:
		case OOROR:
			bptr(n->left);
			bptr(n->right);
			break;
		case OCOND:
			bptr(n->right->left);
			bptr(n->right->right);
			break;
	}
}

static void
bcomplex(Node *n)
{
	if(n == Z)
		return;
	if(!passes)
		complex(n);
	bptr(n);
}

static void
ecomplex(Node *n)
{
	if(!passes)
		complex(n);
	rewe(n, T, 0);
}

static void
becomplex(Node *n)
{
	bcomplex(n);
	rewe(n, T, 0);
}

static void
tgen(Type *t, int dec, int arinit)
{
	Type *l;

	if(t == T)
		return;
	switch(t->etype){
		case TXXX:
			prid("int");
			break;
		case TCHAR: 
		case TUCHAR:
			prid("byte");
			break;
		case TSHORT:
		case TUSHORT:
		case TINT:
		case TUINT:
		case TLONG:
		case TULONG:
		case TENUM:
			prid("int");
			break;
		case TVLONG:
		case TUVLONG:
			prid("big");
			break;
		case TFLOAT:
		case TDOUBLE:
			prid("real");
			break;
		case TIND:
			if(strings == 2 && t->link && t->link->etype == TCHAR){
				prid("string");
				break;
			}
			if(isadt(t->link) || t->link->etype == TFUNC)
				prid("ref ");
			else
				prid("array of ");
			if(t->link && t->link->etype == TVOID){
				prid("byte");
				prcom("was void*", Z);
			}
			else
				tgen(t->link, 1, 0);
			break;
		case TFUNC:
			if(0){
				prid("int");
				prcom("was function", Z);
				break;
			}
			prid("fn");
			prdelim("(");
			for(l = t->down; l != T; l = l->down){
				if(l->etype == TVOID && l->down == T)
					break;
				if(l->etype == TDOT){
					prcom("was ...", Z);
					break;
				}
				if(l->sym != S)
					prsym(l->sym, 0);
				else
					prid("nil");
				prdelim(": ");
				tgen(l, 1, 0);
				if(l->down != T && l->down->etype != TDOT)
					prdelim(", ");
			}
			/* tgen(t->down, dec, 0, 0); */
			prdelim(")");
			if(!isvoid(t->link)){
				prdelim(": ");
				tgen(t->link, dec, 0);
			}
			break;
		case TARRAY:
			prid("array");
			if(t->width == LARR)
				t->width = LARR;
			else if(dec){
				if(t->nwidth != Z)
					prcom("array index was ", t->nwidth);
				else if(t->width != 0){
					sprint(buf, "array index was %ld", t->width/t->link->width);
					prcom(buf, Z);
				}
			}
			else{
				prdelim("[");
				if(t->nwidth != Z)
					egen(t->nwidth, ONOOP, PRE);
				else if(t->width != 0)
					prnum(t->width/t->link->width, KDEC, T);
				prdelim("]");
			}
			prdelim(" of ");
			if(!arinit)
				tgen(t->link, 1, 0);
			break;
		case TVOID:
			/* prid("void"); */
			prid("byte");
			prcom("was void", Z);
			break;
		case TSTRUCT:
		case TUNION:
			if(t->link != T && t->link->etype == TFD){
				prid("Sys->FD");
				usemod(sysop, 0);
			}
			else
				prsym(suename(t), 1);
			break;
		case TTUPLE:
			prdelim("(");
			for(l = t->link; l != T; l = l->down){
				tgen(l, dec, 0);
				if(l->down != T)
					prdelim(", ");
			}
			prdelim(")");
			break;
		case TDOT:
			prdelim("...");
			break;
		case TSTRING:
			prid("string");
			break;
		case TFD:
			prid("fd");
			break;
		default:
			diag(Z, "unknown type");
			break;
	}
}

static Type*
typn(Type *t, int i)
{
	Type *l;

	for(l = t->down; l != T && --i >= 0; l = l->down)
		;
	return l;
}

void
ttgen2(Type *t)
{
	Type *l;
	Sym *s;
	int anon = 0;

	switch(t->etype){
		case TSTRUCT:
		case TUNION:
			newsec(0);
			output(t->lineno, 1);
			s = suename(t);
			if(isgen(s->name))
				addmodn(s);
			setmod(s);
			prsym(s, 0);
			prdelim(": ");
			prid("adt");
			prdelim("{");
			if(t->etype == TUNION)
				prcom("was union", Z);
			newline();
			incind();
			t->vis = 1;
			for(l = t->link; l != T; l = l->down){
				output(l->lineno, 1);
				if(l->nbits)
					prcom("was bit field", Z);
				if(l->sym != S)
					prsym(l->sym, 0);
				else
					pranon(anon++);
				prdelim(": ");
				if(cycle(l, t))
					prid("cyclic ");
				tgen(l, 1, 0);
				prdelim(";");
				newline();
			}
			t->vis = 0;
			decind();
			prdelim("};");
			newline();
			newline();
			break;
		default:
			break;
	}
}

static int
canjoin(Node *n, Node *nn)
{
	return teq(n->type, nn->type) && isname(n) && isname(nn) && n->type->etype != TARRAY;
}

void
vtgen2(Node *n)
{
	int  t, c, comma = 0;
	Node *nn;
	Sym *s;

	nn = n;
	if(n->op == ODAS)
		nn = n->left;
	if(nn->type == T || nn->sym == S)
		return;
	t = nn->type->etype;
	c = nn->sym->class;
	if(0 && c == CTYPEDEF){
		/* egen(nn, ONOOP, PRE); */
		/* tdgen(n, 1, 0); */
		if(isadt(n->type)){
			s = suename(n->type);
			if(isgen(s->name)){
				s->lname = nn->sym->name;
				ttgen2(n->type);
			}
		}
	}
	if(c != CGLOBL && c != CSTATIC && c != CLOCAL && c != CEXREG)
		return;
	newsec(1);
	if(lastd != Z){
		if(t != TFUNC && canjoin(lastd, n))
			comma = 1;
		else
			tdgen(lastd, 1);
	}
	output(nn->lineno, 1);
	if(t == TFUNC){
		if(ism()){
			setmod(nn->sym);
			egen(nn, ONOOP, PRE);
			tdgen(n, 1);
		}
		lastd = Z;
		return;
	}
	if(comma)
		prdelim(", ");
	if(nn->op != ONAME)
		diag(nn, "internal: not name in vtgen");
	setmod(nn->sym);
	prsym(nn->sym, 0);
	/* egen(nn, ONOOP, PRE); */
	/* tdgen(n, 1, 0); */
	lastd = n;
	if(n->op == ODAS)
		rewe(n->right, T, 1);
}

static void minseq(Syml*);

static Node*
con(vlong v)
{
	int neg = 0;
	Node *n;

	if(v < 0){
		neg = 1;
		v = -v;
	}
	n = new1(OCONST, Z, Z);
	n->vconst = v;
	n->kind = KDEC;
	n->type = types[TINT];
	if(neg)
		n = new1(ONEG, n, Z);
	return n;
}

/*
static Node*
fcon(double v)
{
	int neg = 0;
	Node *n;

	if(v < 0){
		neg = 1;
		v = -v;
	}
	n = new1(OCONST, Z, Z);
	n->fconst = v;
	n->kind = KDEC;
	n->type = types[TDOUBLE];
	if(neg)
		n = new1(ONEG, n, Z);
	return n;
}
*/

static Node*
add(vlong v, Node *n)
{
	if(v == 0)
		return n;
	return new1(OADD, con(v), n);
}

static Node*
addn(Node *n1, Node *n2)
{
	if(n1 == Z || n2 == Z)
		return Z;
	if(isconst(n1, 0))
		return n2;
	if(isconst(n2, 0))
		return n1;
	return new1(OADD, n1, n2);
}

static Node*
mul(vlong v, Node *n)
{
	if(v == 0)
		return con(0);
	else if(v == 1)
		return n;
	else if(v == -1)
		return new1(ONEG, n, Z);
	return new1(OMUL, con(v), n);
}

static Node*
mydiv(Node *n, vlong w)
{
	Node *nn;

	if(w == 0)
		return Z;
	if(w == 1)
		return n;
	else if(w == -1)
		return new1(ONEG, n, Z);
	switch(n->op){
		case OCONST:
			if(n->vconst % w == 0){
				n->vconst /= w;
				if(n->left != Z && mydiv(n->left, w) == Z){
					n->vconst *= w;
					break;
				}
				return n;
			}
			break;
		case OCAST:
			return mydiv(n->left, w);
		case OMUL:
			nn = mydiv(n->right, w);
			if(nn != Z){
				if(isconst(nn, 1))
					*n = *n->left;
				return n;
			}
			nn = mydiv(n->left, w);
			if(nn != Z){
				if(isconst(nn, 1))
					*n = *n->right;
				return n;
			}
			break;
		default:
			break;
	}
	return Z;			
}

static Node*
iota(void)
{
	return new1(OIOTA, Z, Z);
}

static Node*
symcon(Sym *s)
{
	Node *n;

	if(s->nconst != Z)
		return s->nconst;
	n = con(s->vconst);
	n->kind = s->kind;
	return n;
}

#define ARITH	1
#define GEOM	2

static Syml*
newsyml(Sym *s, Syml **frees)
{
	Syml *sl, *f;

	if((f = *frees) != nil){
		sl = f;
		*frees = f->nxt;
	}
	else
		sl = (Syml*)malloc(sizeof(Syml));
	sl->sym = s;
	sl->nxt = nil;
	return sl;
}

static Syml*
etseq(Syml *syml)
{
	int e, pio, io, comma;
	vlong d, dd, v0, v1, v, t, tt;
	Node *expr;
	Sym *s;
	Syml *sl, *lsl;

	lsl = nil;
	pio = io = ARITH|GEOM;
	e = 0;
	dd = 0;
	for(sl = syml; sl != nil; sl = sl->nxt){
		s = sl->sym;
		if(isreal(s->tenum) || s->tenum->etype == TIND)
			break;
		if(e == 0)
			v0 = s->vconst;
		if(e == 1){
			v1 = s->vconst;
			d = v1-v0;
		}
		if(e > 0 && (v <= 0 || s->vconst != 2*v))
			io &= ~GEOM;
		if(0 && e > 1 && s->vconst-v != d)
			io &= ~ARITH;
		if(e > 1){
			t = s->vconst-v;
			tt = t-d;
			if(e > 2 && tt != dd)
				io &= ~ARITH;
			else{
				d = t;
				dd = tt;
			}
		}
		if(io == 0)
			break;
		v = s->vconst;
		lsl = sl;
		pio = io;
		e++;
	}
	if(e < 2)
		pio = 0;
	if(pio&GEOM){
		if(e < 3)
			pio = 0;
	}
	else if(pio&ARITH){
		int n;

		if(d == 0 && dd == 0)
			n = 2;
		else if(dd == 0)
			n = 3;
		else
			n = 4;
		if(e < n || (dd&1) != 0)
			pio = 0;
	}
	if(lsl == nil || pio == 0)
		lsl = syml;
	comma = 0;
	for(sl = syml; sl != nil; sl = sl->nxt){
		s = sl->sym;
		nearln = s->lineno;
		output(s->lineno, 1);
		if(pio){
			if(comma)
				prdelim(", ");
			setmod(s);
			prsym(s, 0);
			comma = 1;
		}
		else{
			setmod(s);
			prsym(s, 0);
			prdelim(": ");
			prid("con ");
			if(isbyte(s->tenum) || isbig(s->tenum) && !islbigv(s->vconst) || !isbig(s->tenum) && isuintv(s->vconst)){
				tgen(s->tenum, 1, 0);
				prdelim(" ");
			}
			if(s->nconst != Z)
				egen(s->nconst, ONOOP, PRE);
			else if(s->kind == KCHR)
				prchar(s->vconst);
			else if(isreal(s->tenum))
				prreal(s->fconst, s->cstring, s->kind);
			else
				prnum(s->vconst, s->kind, s->tenum);
			prdelim(";");
			newline();
		}
		if(sl == lsl)
			break;
	}
	if(pio){
		s = syml->sym;
		prdelim(": ");
		prid("con ");
		if(isbyte(s->tenum) || isbig(s->tenum)){
			tgen(s->tenum, 1, 0);
			prdelim(" ");
		}
		if(pio&GEOM){
			if(v0 == 0 || v0 == 1 || v0 == -1)
				expr = mul(v0, new1(OASHL, con(1), iota()));
			else
				expr = new1(OMUL, symcon(s), new1(OASHL, con(1), iota()));
		}
		else if(d == 0 && dd == 0)
			expr = symcon(s);
		else if(dd == 0)
			expr = add(v0, mul(d, iota()));
		else
			expr = add(v0, new1(OADD, mul(v1-dd/2-v0, iota()), mul(dd/2, new1(OMUL, iota(), iota()))));
		complex(expr);
		expr = ckneg(expr);
		egen(expr, ONOOP, PRE);
		prdelim(";");
		newline();
	}
	return lsl->nxt;
}

static void
adde(Syml *sl, Symq *q)
{
	if(q->f == nil)
		q->f = sl;
	else
		q->r->nxt = sl;
	q->r = sl;
}

static void
freeq(Symq *q, Syml **frees)
{
	if(q->f){
		q->r->nxt = *frees;
		*frees = q->f;
		q->f = q->r = nil;
	}
}

static void
etgen2(Sym *s)
{
	Syml *sl;
	static Syml *frees;
	static Symq symq, symq1;

	if(s != nil){
		newsec(2);
		sl = newsyml(s, &frees);
		adde(sl, &symq);
		if(isinteger(s->tenum) && isbigv(s->vconst) && !isbig(s->tenum))
			s->tenum = types[TVLONG];
		return;
	}
	/* end of enums */
	if(symq.f && symq.f == symq.r){	/* try to merge with other singletons */
		adde(symq.f, &symq1);
		symq.f = symq.r = nil;
		return;
	}
	if(symq1.f){
		for(sl = symq1.f; sl != nil; sl = etseq(sl))
			;
		freeq(&symq1, &frees);
	}
	if(symq.f){
		for(sl = symq.f; sl != nil; sl = etseq(sl))
			;
		freeq(&symq, &frees);
	}
}

static void
lgen(Node *n, int br, int first)
{
	if(br)
		prdelim("(");
	if(n == Z){
		if(br)
			prdelim(")");
		return;
	}
	if(n->op == OLIST || n->op == OTUPLE){
		lgen(n->left, 0, first);
		lgen(n->right, 0, 0);
	}
	else if(n->op != ODOTDOT){
		if(!first)
			prdelim(", ");
		egen(n, ONOOP, PRE);
	}
	else
		prcom("was ...", Z);
	if(br)
		prdelim(")");
}

static void
preced(int op1, int op2, int s, int c)
{
	int p1, p2, k1, k2, br;
	char buf[2];

	br = 0;
	p1 = ops[op1].prec;
	p2 = ops[op2].prec;
	if(p1 < 0 || p2 < 0)
		diag(Z, "-ve precedence");
	if(p1 > p2)
		br = 1;
	else if(p1 == p2){
		k1 = ops[op1].kind;
		k2 = ops[op2].kind;
		if(op1 == op2){
			if(k1&RASSOC)
				br = s == LEFT;
			else
				br = s == RIGHT && !(k1&ASSOC);
		}
		else{
			if(k1&RASSOC)
				br = s == LEFT;
			else
				br = s == RIGHT && op1 != OADD;

			if(k1&POSTOP && !(k2&POSTOP))
				br = 1;

			/* funny case */
			if(op2 == OMDOT && s == LEFT && (op1 == ODOT || op1 == ODOTIND))
				br = 1;
		}
	}
	if(br){
		buf[0] = c;
		buf[1] = '\0';
		prdelim(buf);
	}
}

static void
egen(Node *n, int op0, int side)
{
	int op, p;
	Type *t;
	Node *nn;

	if(n == Z){
		if(op0 == OBRACKET)
			prdelim("()");
		return;
	}
	if(n->op == OCONST && n->left != Z){	/* actual node in source */
		n->left->type = n->type;
		n = n->left;
	}
	if((n->op == OSTRING || n->op == OLSTRING) && n->left != Z)	/* actual node in source */
		n = n->left;
	if(n->op == OCAST && (lteq(n->type, n->left->type) || isnil(n) || !iscastable(n->type, n->left->type))){
		if(isnil(n))
			prid("nil");
		else
			egen(n->left, op0, side);
		return;
	}
	if(n->op == ONAME && arrow(n->sym))
		n->op = OMDOT;
	if(n->op != OLIST)
		output(n->lineno, 0);
	op = n->op;
	preced(op0, op, side, '(');
	switch(op){
		case OLIST:
		case OTUPLE:
			lgen(n, 1, 1);
			break;
		case OIOTA:
			prid("iota");
			break;
		case OMDOT:
		case ONAME:
		case OXXX:
			prsym(n->sym, 1);
			break;
		case OCONST:
			if(n->kind == KCHR)
				prchar(n->vconst);
			else if(isreal(n->type))
				prreal(n->fconst, n->cstring, n->kind);
			else if(isnil(n))
				prid("nil");
			else
				prnum(n->vconst, n->kind, n->type);
			if(n->right != Z)
				prcom("was ", n->right);
			break;
		case OSTRING:
			prstr(n->cstring);
			break;
		case OLSTRING:
			prlstr(n->rstring);
			break;
		case OCOND:
			egen(n->left, op, POST);
			prdelim(" ? ");
			egen(n->right->left, op, PRE|POST);
			prdelim(" : ");
			egen(n->right->right, op, PRE);
			prcom("?", Z);
			break;
		case OCOMMA:
			if(op0 != OCOMMA)
				prdelim("(");
			egen(n->left, op, LEFT);
			prdelim(", ");
			egen(n->right, op, RIGHT);
			if(op0 != OCOMMA)
				prdelim(")");
			break;
		case OLDOT:
			egen(n->left, OMOD, LEFT);	/* any precedence 13 operator */
			prdelim(".");
			egen(n->right, op, RIGHT);
			break;
		default:
			p = ops[op].prec;
			egen(n->left, op, LEFT);
			if(space[p])
				prdelim(" ");
			prdelim(ops[op].name);
			if(space[p])
				prdelim(" ");
			egen(n->right, op, RIGHT);
			break;
		case OIND: case OADDR: case OSADDR:
		case OPOS: case ONEG:
		case ONOT: case OCOM:
		case OPREINC: case OPREDEC:
			if(op == OADDR){
				n->op = OSADDR;
				if(!isfn(n->left->type))
					prcom("was ", n);
			}
			else
				prdelim(ops[op].name);
			egen(n->left, op, PRE);
			break;
		case OPOSTINC: case OPOSTDEC:
			egen(n->left, op, POST);
			prdelim(ops[op].name);
			break;
		case ODOT:
			egen(n->left, op, LEFT);
			dotpath(n->sym, n->left->type, 1);
			/* prdelim(ops[op].name); */
			/* prsym(n->sym, 0); */
			break;
		case ODOTIND:
			egen(n->left, op, LEFT);
			if(isadt(n->left->type))
				dotpath(n->sym, n->left->type, 1);	/* type may be demoted arg */
			else
				dotpath(n->sym, n->left->type->link, 1);
			/* prdelim(ops[op].name); */
			/* prsym(n->sym, 0); */
			break;
		case OARRIND:
			egen(n->left, op, LEFT);
			prdelim("[");
			egen(n->right, ONOOP, RIGHT);
			prdelim("]");
			if(n->right->op == OCONST && n->right->vconst < 0)
				prcom("negative array index", Z);
			break;
		case OLEN:
			prid("len ");
			egen(n->right, op, PRE);
			break;
		case OREF:
			prid("ref ");
			tgen(n->type->link, 0, 0);
			break;
		case OARRAYOF:
			prid("array");
			prdelim("[");
			egen(n->left, ONOOP, LEFT);
			prdelim("]");
			prid(" of ");
			tgen(n->type->link, 0, 0);
			break;
		case OSLICE:
			egen(n->left, op, LEFT);
			prdelim("[");
			egen(n->right->left, ONOOP, RIGHT);
			prdelim(": ");
			egen(n->right->right, ONOOP, RIGHT);
			prdelim("]");
			break;
		case OFUNC:
			if(n->kind == KEXP)
				egen(n->left, op, LEFT);
			else
				prsym(n->left->sym, 0);
			lgen(n->right, 1, 1);
			if(n->kind != KEXP && !isvoid(n->left->type->link)){
				prdelim(": ");
				tgen(n->left->type->link, 0, 0);
			}
			break;
		case	ONIL:
			prid("nil");
			break;
		case OCAST:
			if(isnil(n))
				prid("nil");
			else if(iscastable(n->type, n->left->type)){
				tgen(n->type, 0, 0);
				prdelim(" ");
				egen(n->left, op, RIGHT);
			}
			else
				egen(n->left, op0, RIGHT);
			break;
		case OARRAY:
			tgen(n->type, 0, 0);
			egen(n->left, op, LEFT);
			prdelim("[");
			egen(n->right, ONOOP, RIGHT);
			prdelim("]");
			break;
		case OSTRUCT:
		case OUNION:
			tgen(n->type, 0, 0);
			lgen(n->left, 1, 1);
			break;
		case OELEM:
			prdelim(".");
			/* tgen(n->type, 0, 0, 0); */
			prsym(n->sym, 0);
			break;
		case OSIZE:
		case OSIGN:
			prid(ops[op].name);
			if(n->left != Z)
				egen(n->left, OBRACKET, RIGHT);
			else{
				prdelim(" ");
				prid(tnames[n->type->etype]);
				if(typesu[n->type->etype] && n->type->tag){
					prdelim(" ");
					prid(n->type->tag->name);
				}
			}
			break;
		case OPROTO:
			nn = n;
			t = n->type;
			n = protoname(n);
			if(n != Z)
				t = n->type;
			else
				t = prototype(nn->left, t);
			if(!isvoid(t) || n != Z){
				if(n == Z)
					prid("nil");
				else if(n->op == ODOTDOT){
					prcom("was ...", Z);
					break;
				}
				else
					prsym(n->sym, 0);
				/* egen(n, ONOOP, PRE); */
				prdelim(": ");
				tgen(t, 1, 0);
			}
			break;
		case ODOTDOT:
			prid("...");
			break;
		case OINIT:
			egen(n->left, ONOOP, PRE);
			break;
		case OS2AB:
			prid("libc0->s2ab");
			prdelim("(");
			egen(n->left, ONOOP, PRE);
			prdelim(")");
			usemod(libcop, 1);
			break;
		case OAB2S:
			prid("libc0->ab2s");
			prdelim("(");
			egen(n->left, ONOOP, PRE);
			prdelim(")");
			usemod(libcop, 1);
			break;
		case OFILDES:
			prid("sys->fildes");
			prdelim("(");
			egen(n->left, ONOOP, PRE);
			prdelim(")");
			usemod(sysop, 1);
			break;
		case OFD:
			egen(n->left, op, LEFT);
			prdelim(ops[op].name);
			prid("fd");
			break;
		case OT0:
			egen(n->left, op, LEFT);
			prdelim(ops[op].name);
			prid("t0");
			break;
		case ORETV:
			n->op = OAS;
			nn = n->left;
			p = isvoid(n->type) || n->type->etype != TTUPLE || n->type->mark == TCPC;
			if(p)
				n->left = n->right;
			else
				n->left = new1(OTUPLE, new1(ONIL, Z, Z), n->right);
			n->right = nn;
			n->left->type = n->type;
			if(!p && op0 != ONOOP)
				addnode(OT0, n);
			egen(n, op0, side);
			break;
		case OCAT:
			egen(n->left, op, LEFT);
			prdelim(" + ");
			egen(n->right, op, RIGHT);
			break;
	}
	preced(op0, op, side, ')');
}

static int
isexpr(Node *n, Type *t)
{
	if(n == Z)
		return 0;
	if(n->op == OLIST || n->op == OINIT || n->op == OSTRUCT)
		return 0;
	if(teq(t, n->type))
		return 1;
	return 0;
}

static Node *
nxtval(Node *n, Node **nn)
{
	if(n == Z){
		*nn = Z;
		return Z;
	}
	if(n->op == OLIST){
		*nn = n->right;
		return n->left;
	}
	*nn = Z;
	return n;
}

static Node*
eagen(Node *n, Type *t, int ar, int *nz, int depth)
{
	int i, w, nw, down;
	Type *t1;
	Node *nn, *tn;

	if(n != Z){
		if(n->type == T && t == T){
			egen(n, ONOOP, PRE);
			if(ar){
				prdelim(",");
				newline();
			}
			return Z;
		}
		if(ar && n->op == OLIST && n->left->op == OARRAY){
			egen(n->left->left, ONOOP, PRE);
			prdelim(" => ");
			n = n->right;
		}
		if(n->op == OLIST && n->left->op == OELEM){
			prcom("cannot do ", n->left);
			n = n->right;
		}
		if(n->op == OUSED || n->op == ODOTDOT)
			n = n->left;
		if(t == T)
			t = n->type;
	}
	switch(t->etype){
		case TSTRUCT:
		case TUNION:
			if(isexpr(n, t))
				goto Default;
			down = 0;
			tn = nxtval(n, &nn);
			if(tn != Z && (tn->op == OINIT || tn->op == OSTRUCT)){
				down = 1;
				n = tn->left;
			}
			if(depth > 0){
				tgen(t, 0, 0);
				prdelim(" ");
			}
			prdelim("(");
			for(t1 = t->link; t1 != T; t1 = t1->down){
				if(n == Z)
					n = defval(t1);
				n = eagen(n, t1, 0, nil, depth+1);
				if(t1->down != T){
					prdelim(",");
					if(ar)
						prdelim("\t");
					else
						prdelim(" ");
				}
			}
			prdelim(")");
			if(down)
				n = nn;
			break;
		case TARRAY:
			if(isexpr(n, t))
				goto Default;
			if(depth > 0){
				tgen(t, 0, 1);
				prdelim(" ");
			}
			prdelim("{");
			newline();
			incind();
			w = t->width/t->link->width;
			nw = 0;
			for(i = 0; i < w; i++){
				down = 0;
				tn = nxtval(n, &nn);
				if(tn != Z && (tn->op == OINIT || tn->op == OSTRUCT)){
					down = 1;
					n = tn->left;
				}
				n = eagen(n, t->link, 1, &nw, depth+1);
				if(down)
					n = nn;
			}
			if(nw > 0){
				if(nw > 1)
					prdelim("* => ");
				egen(defval(t->link), ONOOP, PRE);
				newline();
			}
			decind();
			prdelim("}");
			break;
		default:
Default:
			if(n == Z){
				if(ar)
					(*nz)++;
				else
					egen(defval(t), ONOOP, PRE);
				return Z;
			}
			n = nxtval(n, &nn);
			if(ar && isnil(n) && iscastable(t, types[TINT])){
				tgen(t, 0, 0);
				prdelim(" ");
			}
			egen(n, ONOOP, PRE);
			n = nn;
			break;
	}
	if(ar){
		prdelim(",");
		newline();
	}
	return n;
}

/* better is
 *	array of byte "abcde\0"
 * but limbo compiler does not accept this as a constant expression
 */
static void
stob(Node *n)
{
	int m;
	char *s = nil, buf[UTFmax];
	ushort *u = nil;

	while(n->op == ONAME)
		n = n->sym->nconst;
	if(n->op == OSTRING)
		s = n->cstring;
	else
		u = n->rstring;
	prdelim("{ ");
	if(s){
		while(*s){
			prid("byte ");
			prchar(*s++);
			prdelim(", ");
		}
	}
	else{
		while(*u){
			m = runetochar(buf, u++);
			s = buf;
			while(--m >= 0){
				prid("byte ");
				prchar(*s++);
				prdelim(", ");
			}
		}
	}
	prid("byte ");
	prchar('\0');
	prdelim(" }");
}

static Type *arrayofchar;

static void
sdgen(Node *n, int glob)
{
	int sop = 0;

	prdelim(" := ");
	if(glob && n->right->op == OS2AB && isstring(n->right->left)){
		if(arrayofchar == T){
			arrayofchar = typ1(TARRAY, types[TCHAR]);
			arrayofchar->width = 0;
		}
		n->type = n->right->type = arrayofchar;
		sop = 1;
	}
	else
		n->type = n->right->type = T;
	tgen(n->type, 0, 1);
	if(sop)
		stob(n->right->left);
	else
		eagen(n->right, n->type, 0, nil, 0);
	prdelim(";");
	newline();
}

static void
tdgen(Node *n, int glob)
{
	int ar, arinit;

	if(ism()){
		prdelim(": ");
		tgen(n->type, 1, 0);
		if(n->op == ODAS)
			prcom("initial value was ", n->right);
		prdelim(";");
		newline();
		return;
	}
	if(n->op == ODAS && (isstring(n->right) || n->right->op == OS2AB)){
		sdgen(n, glob);
		return;
	}
	ar = n->type->etype == TARRAY && n->type->width != LARR;
	arinit = ar && n->op == ODAS;
	if(ar)
		prdelim(" := ");
	else
		prdelim(": ");
	tgen(n->type, 0, arinit);
	if(n->op == ODAS){
		if(!arinit)
			prdelim(" = ");
		eagen(n->right, n->type, 0, nil, 0);
	}
	prdelim(";");
	newline();
}

static int
isdec(Node *n)
{
	return isname(n) && n->kind != KEXP || n->op == ODAS;
}

static void
sgen(Node *n, int blk, Node **ln)
{
	int comma = 0;
	Node *nn;

	if(n == Z)
		return;
	if(blk){
		pushscope(n, SAUTO);
		if(n->op == OLIST && !(blk&NOBR) || (blk&YESBR)){
			prdelim("{");
			newline();
		}
		else if(!(blk&NONL))
			newline();
		if(!(blk&NOIN))
			incind();
	}
	if((nn = *ln) != Z && isdec(nn)){
		if(isdec(n)){
			if(canjoin(nn, n))
				comma = 1;
			else
				tdgen(nn, 0);
		}
		else if(n->op != OLIST){
			tdgen(nn, 0);
			newline();
		}
	}
	if(n->op != OLIST){
		*ln = n;
		output(n->lineno, 1);
	}
	switch(n->op){
		default:
			egen(n, ONOOP, PRE);
			prdelim(";");
			newline();
			break;
		case ODAS:
			pushdcl(n->left, CAUTO);
			egen(n->left, ONOOP, PRE);
			break;
		case ONAME:
			if(n->kind == KEXP){
				egen(n, ONOOP, PRE);
				prdelim(";");
				newline();
			}
			else{
				pushdcl(n, CAUTO);
				if(comma)
					prdelim(", ");
				if(n->op != ONAME)
					diag(n, "internal: not name in sgen");
				prsym(n->sym, 0);
				/* egen(n, ONOOP, PRE); */
/*
				prdelim(": ");
				tgen(n->type, 0, 0, 0);
				prdelim(";");
				newline();
*/
			}
			break;
		case OSBREAK:
			break;
		case ONUL:
			prdelim(";");
			newline();
			break;
		case OBLK:
			sgen(n->left, 1|YESBR, ln);
			break;
		case OLIST:
			sgen(n->left, 0, ln);
			sgen(n->right, 0, ln);
			break;
		case ORETURN:
			prkeywd("return");
			if(n->left != Z)
				prdelim(" ");
			egen(n->left, ONOOP, PRE);
			prdelim(";");
			newline();
			break;
		case OLABEL:
			prcom("was label ", n->left);
			/* i = zeroind(); */
			/* egen(n->left, ONOOP, PRE); */
			/* prdelim(":"); */
			newline();
			/* restoreind(i); */
			break;
		case OGOTO:
			prcom("was goto ", n->left);
			/* prkeywd("goto "); */
			/* egen(n->left, ONOOP, PRE); */
			prdelim(";");
			newline();
			break;
		case OCASE:
			for(nn = n->left; nn != Z; nn = nn->right){
				if(nn != n->left)
					prkeywd(" or ");
				if(nn->left != Z)
					egen(nn->left, ONOOP, PRE);
				else
					prkeywd("*");
			}
			prdelim(" =>");
			clrbrk(n->right);
			sgen(n->right, 1|NOBR, ln);
			if(n->kind != KLAST && !hasbrk(n->right)){
				prcom("fall through", Z);
				newline();
			}
			break;
		case OSWITCH:
			prkeywd("case");
			egen(n->left, OBRACKET, PRE);
			sgen(n->right, 1|NOIN|YESBR, ln);
			break;
		case OWHILE:
			prkeywd("while");
			egen(n->left, OBRACKET, PRE);
			sgen(n->right, 1, ln);
			break;
		case ODWHILE:
			prkeywd("do");
			sgen(n->right, 1|NOENL, ln);
			prkeywd("while");
			egen(n->left, OBRACKET, PRE);
			prdelim(";");
			newline();
			break;
		case OFOR:
			prkeywd("for");
			prdelim("(");
			egen(n->left->right->left, ONOOP, PRE);
			prdelim(";");
			if(n->left->left != Z)
				prdelim(" ");
			egen(n->left->left, ONOOP, PRE);
			prdelim(";");
			if(n->left->right->right != Z)
				prdelim(" ");
			egen(n->left->right->right, ONOOP, PRE);
			prdelim(")");
			sgen(n->right, 1, ln);
			break;
		case OCONTINUE:
			prkeywd("continue");
			prdelim(";");
			newline();
			break;
		case OBREAK:
			prkeywd("break");
			prdelim(";");
			newline();
			break;
		case OIF:
			prkeywd("if");
			egen(n->left, OBRACKET, PRE);
			if(n->right->left->op == OIF && n->right->left->right->right == Z && n->right->right != Z)		/* avoid dangling else */
				sgen(n->right->left, 1|YESBR, ln);
			else
				sgen(n->right->left, 1, ln);
			if(n->right->right != Z){
				prdelim("else");
				if(n->right->right->op == OIF){	/* merge else and if */
					prdelim(" ");
					sgen(n->right->right, 1|NONL|NOIN, ln);
				}
				else
					sgen(n->right->right, 1, ln);
			}
			break;
		case OSET:
		case OUSED:
			prkeywd(ops[n->op].name);
			lgen(n->left, 1, 1);
			prdelim(";");
			newline();
			break;
	}
	if(blk){
		if(!(blk&NOIN))
			decind();
		if(n->op == OLIST&& !(blk&NOBR) || (blk&YESBR)){
			prdelim("}");
			if(!(blk&NOENL))
				newline();
		}
		popscope();
	}
}

static void rew(Node*, int);

static void
rewc0(Node *n, Node *r)
{
	Node *nn;

	if((nn = cfind(n)) != Z){
		cgen0(nn, n);
		if(r->op == ORETURN){
			n->right->left = new1(ORETURN, n->right->left, Z);
			n->right->right = new1(ORETURN, n->right->right, Z);
			n->right->left->type = n->right->left->left->type;
			n->right->right->type = n->right->right->left->type;
			*r = *n;
		}
	}
}

static void
rewc1(Node *n)
{
	Node *c, *nc;

	if(n == Z || n->op != OCOND || side(n) || !simple(n))
		return;
	c = n->left;
	nc = new1(ONOT, ncopy(c), Z);
	n->op = OOROR;
	n->left = new1(OANDAND, c, n->right->left);
	n->right = new1(OANDAND, nc, n->right->right);
}

static void
rewc(Node *n, Node *r)
{
	Node *nn, *rr, *i;

	if((nn = cfind(n)) != Z){
		i = cgen(nn, n);
		rr = new1(OXXX, Z, Z);
		if(n == r && nn == n)
			*rr = *nn;
		else
			*rr = *r;
		r->op = OLIST;
		r->left = i;
		r->right = rr;
	}
}

static int
rewe(Node *n, Type *t, int lev)
{
	int op, k, k1, k2;
	int v;
	Node *nn;

	if(n == Z)
		return -1;
	switch(n->op){
		case OCONST:
			break;
		case ONAME:
			if(strings || !isstring(n))
				break;
		case OSTRING:
		case OLSTRING:
			if(!strings)
				addnode(OS2AB, n);
			break;
		case OCOND:
			bptr(n->left);
			rewe(n->left, T, 1);
			rewe(n->right, T, 1);
			break;
		case OIND:
			if(isfn(n->type)){
				*n = *n->left;
				rewe(n, T, 1);
				break;
			}
			if(!isadt(n->type)){
				n->op = OARRIND;
				n->right = con(0);
				rewe(n, T, 1);
				break;
			}
			rewe(n->left, T, 1);
			break;
		case OADDR:
			if(n->left->op == OARRIND){
				n->right = n->left;
				n->left = n->right->left;
				n->right->left = n->right->right;
				n->right->right = Z;
				n->right->op = OLIST;
				n->op = OSLICE;
				rewe(n, T, 1);
				break;
			}
			rewe(n->left, T, 1);
			break;
		case OSLICE:
			rewe(n->left, T, 1);
			rewe(n->right, T, 1);
			if(n->left->op == OSLICE){
				n->right->left = addn(n->left->right->left, n->right->left);
				n->right->right = addn(n->left->right->left, n->right->right);
				n->left = n->left->left;
				rewe(n, T, 1);
				break;
			}
			break;
		case OCOMMA:
			rewe(n->left, T, 1);
			rewe(n->right, T, 1);
			if(n->left->op == OAS && n->right->op == OAS){
				n->op = OAS;
				n->left->op = n->right->op = OLIST;
				nn = n->left->right;
				n->left->right = n->right->left;
				n->right->left = nn;
				rewe(n, T, 1);
				break;
			}
			break;
		case OFUNC:
			if(n->left->op == ONAME){
				if((k = n->left->sym->kind) != LNONE){
					rewlc(n, k, t);
					rewe(n->left, T, 1);
					rewe(n->right, T, 1);
					args(n);
					return k;
				}
			}
			else
				rewe(n->left, T, 1);
			rewe(n->right, T, 1);
			args(n);
			break;
		case OCAST:
			rewe(n->left, n->type, 1);
			break;
		case OAS:
		case OASI:
		case OASD:
			rewe(n->left, T, 1);
			rewe(n->right, n->type, 1);
			break;
		case ONOT:
		case OANDAND:
		case OOROR:
			bptr(n);
			rewe(n->left, T, 1);
			rewe(n->right, T, 1);
			break;
		case OPREINC:
		case OPOSTINC:
		case OASADD:
			if(n->op != OPOSTINC || lev == 0){
				sliceasgn(n);
				if(n->op == OAS){
					rewe(n, T, 1);
					break;
				}
			}
			rewe(n->left, T, 1);
			rewe(n->right, T, 1);
			break;
		case OEQ:
		case ONE:
		case OLT:
		case OLE:
		case OGT:
		case OGE:
			k1 = rewe(n->left, T, 1);
			k2 = rewe(n->right, T, 1);
			if(k1 == LSTRCMP && n->right->op == OCONST){
				op = -1;
				v = n->right->vconst;
				switch(v){
					case -1:
						if(n->op == OEQ)
							op = OLT;
						else if(n->op == ONE)
							op = OGE;
						break;
					case 0:
						op = n->op;
						break;
					case 1:
						if(n->op == OEQ)
							op = OGT;
						else if(n->op == ONE)
							op = OLE;
						break;
				}
				if(op != -1){
					*n = *n->left;
					n->op = op;
				}
			}
			if(k2 == LSTRCMP && n->left->op == OCONST){
				op = -1;
				v = n->left->vconst;
				switch(v){
					case -1:
						if(n->op == OEQ)
							op = OLT;
						else if(n->op == ONE)
							op = OGE;
						break;
					case 0:
						op = rev(n->op);
						break;
					case 1:
						if(n->op == OEQ)
							op = OGT;
						else if(n->op == ONE)
							op = OLE;
						break;
				}
				if(op != -1){
					*n = *n->right;
					n->op = op;
				}
			}
			break;
		default:
			rewe(n->left, T, 1);
			rewe(n->right, T, 1);
			break;
	}
	return -1;	
}

/*
static void
rewf(Node *n)
{
	if(n == Z)
		return;
	switch(n->op){
		case OFUNC:
			if(n->left->op == ONAME)
				fdargs(n);
			break;
		default:
			rewf(n->left);
			rewf(n->right);
			break;
	}
}
*/

static void
rew(Node *n, int blk)
{
	int i;
	Node *a, *nn;

	if(n == Z)
		return;
	if(blk)
		pushscope(n, SAUTO);
	nearln = n->lineno;
	if(n->blk){
		n->blk = 0;
		addnode(OBLK, n);
	}
	switch(n->op){
		default:
			if(simple(n))
				rewc0(n, n);
			else
				rewc(n, n);
			if(n->op == OLIST || n->op == OIF){
				rew(n, 0);
				break;
			}
			ecomplex(n);
			break;
		case ODAS:
			pushdcl(n->left, CAUTO);
			rewe(n->right, T, 1);
			break;
		case OSBREAK:
		case ONUL:
			break;
		case ONAME:
			if(n->kind == KEXP)
				ecomplex(n);
			else
				pushdcl(n, CAUTO);
			break;
		case OBLK:
			rew(n->left, 1);
			break;
		case OLIST:
			rew(n->left, 0);
			rew(n->right, 0);
			break;
		case ORETURN:
			if(simple(n->left))
				rewc0(n->left, n);
			else	
				rewc(n->left, n);
			if(n->op != ORETURN){
				rew(n, 0);
				break;
			}
			ecomplex(n);
			break;
		case OLABEL:
		case OGOTO:
			break;
		case OCASE:
			for(nn = n->left; nn != Z; nn = nn->right)
				if(nn->left != Z)
					ecomplex(nn->left);
			rew(n->right, 1);
			break;
		case OSWITCH:
			rewc(n->left, n);
			if(n->op == OLIST){
				rew(n, 0);
				break;
			}
			ecomplex(n->left);
			if(!lteq(n->left->type, types[TINT]))
				intcast(n->left);
			n->right = buildcases(n->right);
			rew(n->right, 1);
			break;
		case OWHILE:
		case ODWHILE:
			rewc1(n->left);
			becomplex(n->left);
			rew(n->right, 1);
			break;
		case OFOR:
			rewc1(n->left->left);
			rewc(n->left->right->left, n);
			if(n->op == OLIST){
				rew(n, 0);
				break;
			}
			becomplex(n->left->left);
			ecomplex(n->left->right->left);
			ecomplex(n->left->right->right);
			rew(n->right, 1);
			break;
		case OCONTINUE:
			break;
		case OBREAK:
			break;
		case OIF:
			rewc1(n->left);
			rewc(n->left, n);
			if(n->op == OLIST){
				rew(n, 0);
				break;
			}
			becomplex(n->left);
			rew(n->right->left, 1);
			rew(n->right->right, 1);
			break;
		case OSET:
			if(n->left == Z){
				n->op = ONUL;
				n->left = n->right = Z;
				break;
			}
			if(n->left->op != OLIST){
				n->op = OAS;
				n->right = defval(n->left->type);
				rew(n, 0);
				break;
			}
			i = 0;
			nn = Z;
			for(;;){
				a = arg(n->left, i);
				if(a == Z)
					break;
				a = new1(OAS, a, defval(a->type));
				if(i == 0)
					nn = a;
				else
					nn = new1(OLIST, nn, a);
				i++;
			}
			*n = *nn;
			rew(n, 0);
			break;
		case OUSED:
			if(n->left == Z){
				n->op = ONUL;
				n->left = n->right = Z;
				break;
			}
			i = 0;
			nn = Z;
			for(;;){
				a = arg(n->left, i);
				if(a == Z)
					break;
				if(i == 0)
					nn = a;
				else
					nn = new1(OOROR, nn, a);
				i++;
			}
			n->op = OIF;
			n->left = nn;
			n->right = new1(OLIST, Z, Z);
			n->right->left = new1(ONUL, Z, Z);
			rew(n, 0);
			break;
	}
	if(blk)
		popscope();
}

void
codgen2(Node *n, Node *nn, int lastlno, int rw)
{
	Node *ln = Z;

	newsec(0);
	output(nn->lineno, 1);
	tmp = 0;
	/* t = types[TVOID]; */
	nn = func(nn);
	pushscope(nn, SPARM);
	if(rw)
		rew(n, 1);
	egen(nn, ONOOP, PRE);
	newline();
	prdelim("{");
	newline();
	incind();
	/* rewf(n); */
	pushscope(n, SAUTO);
	sgen(n, 0, &ln);
	if(ln != Z && isdec(ln))
		tdgen(ln, 0);
	popscope();
	popscope();
	if(n != Z)
		output(lline(n), 1);
	output(lastlno, 1);
	decind();
	prdelim("}");
	newline();
	newline();
	setmain(nn);
}

void
rewall(Node *n, Node *nn, int lastlno)
{
	USED(lastlno);
	tmp = 0;
	nn = func(nn);
	pushscope(nn, SPARM);
	rew(n, 1);
	popscope();
	setmain(nn);
}

void
suball(Node *n, Node *nn)
{
	Node *rn;

	nn = func(nn);
	pushscope(nn, SPARM);
	subs(nn, 0, 0);
	subs(n, 1, 1);
	nn = lastn(n);
	if(nn != Z && nn->op != ORETURN){
		rn = retval(Z);
		if(rn != Z){
			addnode(OLIST, nn);
			nn->right = rn;
		}
	}
	popscope();
}

void
ginit(void)
{
	thechar = 'o';
	thestring = "386";
	tfield = types[TLONG];
}

long
align(long i, Type *t, int op)
{
	long o;
	Type *v;
	int w;

	o = i;
	w = 1;
	switch(op) {
	default:
		diag(Z, "unknown align opcode %d", op);
		break;

	case Asu2:	/* padding at end of a struct */
		w = SZ_LONG;
		break;

	case Ael1:	/* initial allign of struct element */
		for(v=t; v->etype==TARRAY; v=v->link)
			;
		w = ewidth[v->etype];
		if(w <= 0 || w >= SZ_LONG)
			w = SZ_LONG;
		break;

	case Ael2:	/* width of a struct element */
		o += t->width;
		break;

	case Aarg0:	/* initial passbyptr argument in arg list */
		if(typesuv[t->etype]) {
			o = align(o, types[TIND], Aarg1);
			o = align(o, types[TIND], Aarg2);
		}
		break;

	case Aarg1:	/* initial allign of parameter */
		w = ewidth[t->etype];
		if(w <= 0 || w >= SZ_LONG) {
			w = SZ_LONG;
			break;
		}
		w = 1;		/* little endian no adjustment */
		break;

	case Aarg2:	/* width of a parameter */
		o += t->width;
		w = SZ_LONG;
		break;

	case Aaut3:	/* total allign of automatic */
		o = align(o, t, Ael2);
		o = align(o, t, Ael1);
		w = SZ_LONG;	/* because of a pun in cc/dcl.c:contig() */
		break;
	}
	o = round(o, w);
	if(0)
		print("align %s %ld %T = %ld\n", bnames[op], i, t, o);
	return o;
}

long
maxround(long max, long v)
{
	v = round(v, SZ_LONG);
	if(v > max)
		return v;
	return max;
}

static int
nlen(Node *n)
{
	if(n == Z)
		return 0;
	if(n->op == OLIST)
		return nlen(n->left)+nlen(n->right);
	return 1;
}

static void
flatten(Node *n, Node **a, int *i)
{
	if(n == Z)
		return;
	if(n->op == OLIST){
		flatten(n->left, a, i);
		flatten(n->right, a, i);
		free(n);
		return;
	}
	a[(*i)++] = n;
}

static Node*
addcase(Node *n, Node **e, Node **s, int k)
{
	Node *nn;

	if(*e != Z){
		nn = new1(OCASE, *e, *s);
		nn->right->blk = 0;
		nn->kind = k;
	}
	else
		nn = *s;
	*e = *s = Z;
	if(n == Z)
		return nn;
	return new1(OLIST, n, nn);
}

/* collect case code together */		
static Node*
buildcases(Node *n)
{
	int i, m, m0, c;
	Node *e, *s, *nn, **a, **ep;

	m = nlen(n);
	a = (Node **)malloc(m*sizeof(Node*));
	m0 = 0;
	flatten(n, a, &m0);
	if(m != m0)
		diag(Z, "internal: bad buildcases()");
	c = 1;
	e = s = nn = Z;
	ep = &e;
	for(i = 0; i < m; i++){
		n = a[i];
		if(n->op == OCASE){
			if(!c){
				nn = addcase(nn, &e, &s, KNIL);
				ep = &e;
			}
			*ep = new1(OLIST, n->left, Z);
			if(n->left == Z)
				(*ep)->lineno = n->lineno;
			ep = &(*ep)->right;
			c = 1;
		}
		else{
			if(s == Z)
				s = n;
			else
				s = new1(OLIST, s, n);
			c = 0;
		}
	}
	nn = addcase(nn, &e, &s, KLAST);
	free(a);
	return nn;
}

static Sym *
tmpgen(Type *t)
{
	Sym *s;

	sprint(buf, "tmp_%d", ++tmp);
	s = slookup(buf);
	s->type = t;
	s->class = CAUTO;
	if(t->etype == TENUM)
		s->type = types[TINT];
	return s;
}

static Node*
cfind(Node *n)
{
	Node *nn;

	if(n == Z)
		return Z;
	if(n->op == OCOND)
		return n;
	nn = cfind(n->left);
	if(nn != Z)
		return nn;
	return cfind(n->right);
}

Node*
ncopy(Node *n)
{
	Node *nn;

	if(n == Z)
		return Z;
	nn = new1(n->op, Z, Z);
	*nn = *n;
	nn->left = ncopy(n->left);
	nn->right = ncopy(n->right);
	return nn;
}

static int
complexity(Node *n, int *cond)
{
	int c;

	if(n == Z)
		return 0;
	c = complexity(n->left, cond)+1+complexity(n->right, cond);
	if(n->op == OCOND)
		(*cond)++;
	return c;
}

static int
simple(Node *n)
{
	int c;

	c = 0;
	return complexity(n, &c) < COMPLEX && c <= 1;
}

static Type*
intype(Node *n)
{
	Type *t;

	t = ntype(n);
	if(t == T)
		return T;
	return t->link;
}

static Type*
ntype(Node *n)
{
	Type *t;

	if(n == Z)
		return T;
	t = n->type;
	if(t != T){
		if(t->etype == TENUM)
			return n->sym->tenum;
		return t;
	}
	switch(n->op){
		case OEQ:
		case ONE:
		case OLT:
		case OGE:
		case OGT:
		case OLE:
		case ONOT:
		case OANDAND:
		case OOROR:
		case OIOTA:
			return types[TINT];
		case OCOMMA:
			return ntype(n->right);
		case OCOND:
			return maxtype(ntype(n->right->left), ntype(n->right->right));
		case OFUNC:
			return intype(n->left);
		case ODOT:
			tcomd(n, ntype(n->left));
			t = n->type;
			n->type = T;
			return t;
		case ODOTIND:
			tcomd(n, intype(n->left));
			t = n->type;
			n->type = T;
			return t;
		case OARRIND:
			return intype(n->left);
		case OADDR:
			return typ1(TIND, ntype(n->left));
		case OIND:
			return intype(n->left);
		case OSTRUCT:
			return T;
	}
	return maxtype(ntype(n->left), ntype(n->right));
}

static Type*
gettype(Node *n1, Node *n2)
{
	Type *t;

	t = maxtype(n1->type, n2->type);
	if(t != T)
		return t;
	return maxtype(ntype(n1), ntype(n2));
}

static void
cgen0(Node *n, Node *e)
{
	Node *c, *nn, *ed, *ee;

	if(n == e){
		n->op = OIF;
		return;
	}
	c = n->left;
	ed = new1(OXXX, Z, Z);
	*ed = *e;
	ee = ncopy(e);
	nn = cfind(ee);
	*n = *n->right->left;
	*nn = *nn->right->right;
	e->op = OIF;
	e->left = c;
	e->right = new1(OLIST, ed, ee);
}

static Node*
cgen(Node *n, Node *e)
{
	Type *t;
	Node *tn, *i;

	USED(e);
	tn = new1(ONAME, Z, Z);
	t = gettype(n->right->left, n->right->right);
	tn->sym = tmpgen(t);
	tn->type = tn->sym->type;
/*
	if(n == e){
		n->op = OIF;
		n->right->left = new1(OASD, tn, n->right->left);
		n->right->right = new1(OAS, tn, n->right->right);
		return n;
	}
*/
	i = new1(OIF, n->left, new1(OLIST, new1(OASD, tn, n->right->left), new1(OAS, tn, n->right->right)));
	*n = *tn;
	return i;
}

static struct{
	char *name;
	int	args;
	int	fd;
	char *lname;
} sysops[] = {
	"create",	1,	RET,	nil,
	"dirstat",	1,	0,	"stat",
	"dirfstat",	0,	1,	"fstat",
	"dirwstat",	1,	0,	"wstat",
	"dirfwstat",	0,	1,	"fwstat",
	"dirread",	0,	1,	nil,
	"dup",	0,	0,	nil,
	"fprint",	2|STAR,	1,	nil,
	"fprintf",	2|STAR,	1,	"fprint",
	"open",	1,	RET,	nil,
	"print",	1|STAR,	0,	nil,
	"printf",	1|STAR,	0,	"print",
	"read",	0,	1,	nil,
	"remove",	1,	0,	nil,
	"seek",	0,	1,	nil,
	"sleep",	0,	0,	nil,
	"sprint",	1|STAR,	0,	nil,
	"sprintf",	1|STAR,	0,	"sprint",
	"write",	0,	1,	nil,
	0
};

/* dummy entry for module */
#define BIOTMP	"__bio__"

static struct{
	char	*name;
	char	*lname;
} bioops[] = {
	"Bflush",	"flush",
	"Bgetc",	"getc",
	"Bprint",	"puts",
	"Bputc",	"putc",
	"Bread",	"read",
	"Bseek",	"seek",
	"Bungetc",	"ungetc",
	"Bwrite",	"write",
	BIOTMP,	nil,
	0
};

char *libcops[] = {
	"isalnum",
	"isalpha",
	"isascii",
	"iscntrl",
	"isdigit",
	"isgraph",
	"islower",
	"isprint",
	"ispunct",
	"isspace",
	"isupper",
	"isxdigit",
	"strchr",
	"strrchr",
	"toascii",
	"tolower",
	"toupper",
	"abs",
	"min",
	"max",
	0,
};

static struct{
	char *name;
	int	type;
	int	string;
} xops[] = {
	"strlen",	LSTRLEN,	1,
	"strcmp",	LSTRCMP,	1,
	"strcpy",	LSTRCPY,	1,
	"strcat",	LSTRCAT,	1,
	"strncmp",	LSTRNCMP,	1,
	"strncpy",	LSTRNCPY,	1,
	"strncat",	LSTRNCAT,	1,
	"strdup",	LSTRDUP,	1,
	"memcpy",	LMEMMOVE,	0,
	"memmove",	LMEMMOVE,	0,
	"malloc",	LMALLOC,	0,
	"free",	LFREE,	0,
	"exit",	LEXIT,	0,
	"exits",	LEXIT,	0,
	"close",	LCLOSE,	0,
	"atoi",	LATOI,	0,
	"atol",	LATOI,	0,
	"atoll",	LATOL,	0,
	"atof",	LATOF,	0,
	"atod",	LATOF,	0,
	"print",	LPRINT,	0,
	"printf",	LPRINT,	0,
	"fprint",	LFPRINT,	0,
	"fprintf",	LFPRINT,	0,
	"sprint",	LSPRINT,	0,
	"sprintf",	LSPRINT,	0,
	0
};

char *mathsops[] = {
	"sin",
	"cos",
	"tan",
	"sinh",
	"cosh",
	"tanh",
	"asin",
	"acos",
	"atan",
	"asinh",
	"acosh",
	"atanh",
	"atan2",
	"sqrt",
	"cbrt",
	"pow",
	"pow10",
	"exp",
	"log",
	"log10",
	0
};

Node *glob, *globe;

void
sysinit(void)
{
	int i;
	Sym *s;

	glob = globe = new1(ONOOP, Z, Z);
	for(i = 0; sysops[i].name; i++){
		s = slookup(sysops[i].name);
		s->class = CEXTERN;
		s->args = sysops[i].args;
		s->fd = sysops[i].fd;
		s->mod = "sys";
		s->lname = sysops[i].lname;
		s->limbo = 1;
		sysop = s;
	}
	for(i = 0; bioops[i].name; i++){
		s = slookup(bioops[i].name);
		s->class = CEXTERN;
		if(strcmp(bioops[i].name, BIOTMP) == 0){
			s->mod = "bufio";
			bioop = s;
		}
		s->lname = bioops[i].lname;
		s->kind = LSELF;
		s->limbo = 1;
	}
	for(i = 0; mathsops[i]; i++){
		s = slookup(mathsops[i]);
		s->class = CEXTERN;
		s->mod = "math";
		s->limbo = 1;
	}
	for(i = 0; libcops[i]; i++){
		s = slookup(libcops[i]);
		s->class = CEXTERN;
		s->mod = strings ? "libc" : "libc0";
		s->limbo = 1;
		libcop = s;
	}
	for(i = 0; xops[i].name; i++){
		s = slookup(xops[i].name);
		s->class = CEXTERN;
		if(strings || !xops[i].string)
			s->kind = xops[i].type;
		else
			s->mod = "libc0";
		if(s->kind == LEXIT)
			s->lname = "exit";
		s->limbo = 1;
	}
	usemod(sysop, 1);
	if(!strings)
		usemod(libcop, 1);
}

void
clbegin(void)
{
	pushscope(glob, SGLOB);
}

void
clend(void)
{
	if(passes)
		swalk();
	popscope();
}

static Modl *mods;

void
usemod(Sym *s, int ld)
{
	Modl *ml;

	for(ml = mods; ml != nil; ml = ml->nxt)
		if(strcmp(ml->mod, s->mod) == 0){
			ml->ld |= ld;
			return;
		}
	ml = (Modl *)malloc(sizeof(Modl));
	ml->mod = s->mod;
	ml->ld = ld;
	ml->nxt = mods;
	mods = ml;
}

static void
ginc(Modl *ml)
{
	int c;
	char *s;

	if(ml == nil)
		return;
	if(ml->nxt != nil)
		ginc(ml->nxt);
	s = ml->mod;
	c = toupper(s[0]);
	sprint(buf, "include \"%s.m\";", s);
	prline(buf);
	if(ml->ld){
		sprint(buf, "	%s: %c%s;", s, c, s+1);
		prline(buf);
	}
}

static void
gload(Modl *ml)
{
	int c;
	char *s;

	if(ml == nil)
		return;
	if(ml->nxt != nil)
		gload(ml->nxt);
	if(ml->ld){
		s = ml->mod;
		c = toupper(s[0]);
		sprint(buf, "	%s = load %c%s %c%s->PATH;", s, c, s+1, c, s+1);
		prline(buf);
	}
}

static void
callmain(void)
{
	if(inmain){
		if(strings)
			prline("	main(len argl, argl);");
		else
			prline("	main(len argl, libc0->ls2aab(argl));");
	}
}

static void
genstart(void)
{
	char *s;

	if(!strings && inmain)
		usemod(libcop, 1);
	ginc(mods);
	s = hasm();
	if(s){
		sprint(buf, "include \"%s\";", s);
		prline(buf);
	}
	prline("");
	prline("init(nil: ref Draw->Context, argl: list of string)");
	prline("{");
	gload(mods);
	callmain();
	prline("}");
	prline("");
}

static int
argpos0(Node *nn, Node *n, int *p)
{
	int pp;

	if(n == Z)
		return -1;
	if(n->op == OLIST){
		pp = argpos0(nn, n->left, p);
		if(pp >= 0)
			return pp;
		return argpos0(nn, n->right, p);
	}
	if(n == nn)
		return *p;
	(*p)++;
	return -1;
}

static int
argpos(Node *nn, Node *n)
{
	int p = 0;

	p = argpos0(nn, n, &p);
	if(p < 0)
		diag(Z, "-ve argpos");
	return p;
}

static Node*
arg0(Node *n, int a, int *i)
{
	Node *nn;

	if(n == Z)
		return Z;
	if(n->op == OLIST){
		nn = arg0(n->left, a, i);
		if(nn != Z)
			return nn;
		return arg0(n->right, a, i);
	}
	if(a == (*i)++)
		return n;
	return Z;
}

static Node*
arg(Node *n, int a)
{
	int i = 0;

	return arg0(n, a, &i);
}

static Node*
list(Node *l, Node *r)
{
	if(r == Z)
		return l;
	if(l == Z)
		return r;
	return new1(OLIST, l, r);
}

static Node*
droparg(Node *n, int a, int *i)
{
	if(n == Z)
		return Z;
	if(n->op == OLIST)
		return list(droparg(n->left, a, i), droparg(n->right, a, i));
	if(a == (*i)++)
		return Z;
	return n;
}

static void
sargs(Node *n)
{
	int s, f, i, j;
	Node *a;

	if(strings || (f = n->left->sym->args) == 0)
		return;
	s = 0;
	for(i = 1, j = 0; i < STAR || s; i *= 2, j++){
		if(f&i || s){
			a = arg(n->right, j);
			if(a == Z)
				break;
			if(s && !isstr(a->type))
				continue;
			if(f&STAR)
				s++;
			if(a->op == OS2AB){
				*a = *a->left;
				continue;
			}
			addnode(OAB2S, a);
		}
	}
}

static void
fdargs(Node *n)
{
	int f, i, j;
	Node *a;

	if((f = n->left->sym->fd) == 0)
		return;
	marktype(pfdtype, TCFD);
	if(f&RET)
		tcon(n, pfdtype);
	for(i = 1, j = 0; i < RET; i *= 2, j++){
		if(f&i){
			a = arg(n->right, j);
			if(a == Z)
				break;
			tcon(a, pfdtype);
		}
	}
}

static void
aargs(Node *n)
{
	int i;
	Node *a, *nn, *fn;
	Type *t, *t0, *ft, *at, *st;

	if(!doaddr)
		return;
	if(n->op != OFUNC || n->left->op != ONAME)
		return;
	/* ft = n->left->type; */
	ft = n->left->sym->type;
	t = t0 = ft->link;
	nn = Z;
	for(i = 0; ; i++){
		a = arg(n->right, i);
		if(a == Z)
			break;
		at = typn(ft, i);
		if(at != T && at->etype != TDOT && (a->op == OADDR || iteq(a->type, at) || iteq(at, a->type))){
			if(iteq(at, a->type))
				st = at->link;
			else
				st = a->type->link;
			if(doalladdr || isscalar(st)){
				if(a->op == OADDR)
					*a = *a->left;
				else if(iteq(a->type, at))
					a->type = at;
				if(t->mark == 0){
					t = tuple(t, a->type);
					trep(at, at->link);
					fn = finddec(n->left->sym, 1);
					if(fn != Z && fn->op == OFUNC)
						tind(arg(fn->right, i));
				}
				if(nn == Z)
					nn = cknil(ncopy(a));
				else{
					nn = new1(OTUPLE, nn, cknil(ncopy(a)));
					nn->type = t;
				}
			}
		}
	}
	if(nn != Z){
		if(isvoid(t0) || t->mark == TCPC)
			marktype(t, TCPC);
		else
			marktype(t, TCFC);
		tcon(n, t);
		addnode(ORETV, n);
		n->right = nn;
	}
}

static void
args(Node *n)
{
	if(n->op != OFUNC || n->left->op != ONAME)
		return;
	sargs(n);
	if(passes){
		fdargs(n);
		aargs(n);
	}
}

static Node*
indir(Node *n)
{
	if(n->op == OADDR)
		return n->left;
	return new1(OIND, n, Z);
}

static void
rewlc(Node *n, int k, Type *t)
{
	int i;
	Type *tt;
	Node *a0, *a1, *a2, *nn;

	if(t == T)
		t = n->type;
	a0 = arg(n->right, 0);
	a1 = arg(n->right, 1);
	switch(k){
		case LSTRLEN:
			n->op = OLEN;
			break;
		case LSTRCMP:
			n->op = ONE;
			n->left = a0;
			n->right = a1;
			break;
		case LSTRCPY:
			n->op = OAS;
			n->left = a0;
			n->right = a1;
			n->type = n->left->type;
			break;
		case LSTRCAT:
			n->op = OASADD;
			n->left = a0;
			n->right = a1;
			n->type = n->left->type;
			break;
		case LSTRDUP:
			*n = *a0;
			break;
		case LMEMMOVE:
			if(!teq(a0->type, a1->type))
				break;
			if(a0->type->etype == TIND){
				tt = a0->type->link;
				a2 = arg(n->right, 2);
				if(isadt(tt) && isconst(a2, tt->width)){
					n->op = OAS;
					n->left = indir(a0);
					n->right = indir(a1);
					n->type = n->left->type = n->right->type = tt;
					break;
				}
				if(mydiv(a2, tt->width) != Z){
					n->op = OAS;
					n->left = new1(OSLICE, a0, new1(OLIST, con(0), Z));
					n->right = new1(OSLICE, a1, new1(OLIST, con(0), a2));
					n->type = n->left->type = n->right->type = a0->type;
				}
			}
			break;
		case LMALLOC:
			if(t->etype == TIND){
				tt = t->link;
				if(isadt(tt) && isconst(a0, tt->width)){
					n->op = OREF;
					n->left = Z;
					n->right = Z;
					n->type = t;
					break;
				}
				if(mydiv(a0, tt->width) != Z){
					n->op = OARRAYOF;
					n->left = a0;
					n->right = Z;
					n->type = t;
					if(isadt(tt)){
						n->type = typ1(TARRAY, tt);
						n->type->width = LARR;	/* limbo array without bounds */
						marktype(n->type, TCAR);
					}
				}
			}
			break;
		case LFREE:
			n->op = OAS;
			n->left = a0;
			n->right = con(0);
			n->type = n->left->type;
			n->right->type = n->type;
			break;
		case LEXIT:
			i = n->kind;
			*n = *n->left;
			n->kind = i;
			break;
		case LCLOSE:
			n->op = OAS;
			n->left = a0;
			n->right = con(0);
			n->left->type = typ1(TIND, n->left->type);
			n->type = n->left->type;
			n->right->type = n->type;
			break;
		case LATOI:
			if(!strings)
				strcast(a0);
			n->op = OCAST;
			n->left = a0;
			n->right = Z;
			n->type = types[TINT];
			break;
		case LATOL:
			if(!strings)
				strcast(a0);
			n->op = OCAST;
			n->left = a0;
			n->right = Z;
			n->type = types[TVLONG];
			break;
		case LATOF:
			if(!strings)
				strcast(a0);
			n->op = OCAST;
			n->left = a0;
			n->right = Z;
			n->type = types[TDOUBLE];
			break;
		case LPRINT:
			if(a0->op == OSTRING)
				pfmt(a0->cstring);
			else if(a0->op == OLSTRING)
				lpfmt(a0->rstring);
			break;
		case LFPRINT:
			if(a1->op == OSTRING)
				pfmt(a1->cstring);
			else if(a1->op == OLSTRING)
				lpfmt(a1->rstring);
			break;
		case LSPRINT:
			if(n->right->kind != KDROP){
				if(a1->op == OSTRING)
					pfmt(a1->cstring);
				else if(a1->op == OLSTRING)
					lpfmt(a1->rstring);
				nn = new1(OXXX, Z, Z);
				*nn = *n;
				i = 0;
				nn->right = droparg(nn->right, 0, &i);
				nn->right->kind = KDROP;
				n->op = OAS;
				n->left = a0;
				n->right = nn;
				n->type = nn->type;
			}
			break;
		case LSELF:
			if(n->right != Z && n->right->kind != KDROP){
				i = 0;
				n->right = droparg(n->right, 0, &i);
				if(n->right != Z)
					n->right->kind = KDROP;
				addnode(OLDOT, n->left);
				n->left->right = n->left->left;
				n->left->left = a0;
				usemod(bioop, 1);
			}
			break;
	}
}

void
expgen(Node *n)
{
	egen(n, ONOOP, PRE);
}

static void
clrbrk(Node *n)
{
	if(n == Z)
		return;
	switch(n->op){
		case OLIST:
			clrbrk(n->right);
			break;
		case OBREAK:
			n->op = OSBREAK;
			n->left = n->right = Z;
			break;
	}
}

static int
hasbrk(Node *n)
{
	if(n == Z)
		return 0;
	switch(n->op){
		case OLIST:
		case OWHILE:
		case ODWHILE:
		case OFOR:
			return hasbrk(n->right);
		case OIF:
			if(n->right->right == Z)
				return 0;
			return hasbrk(n->right->left) && hasbrk(n->right->right);
		case ORETURN:
		case OGOTO:
		case OCONTINUE:
		case OBREAK:
		case OSBREAK:
			return 1;
		default:
			return 0;
	}
	return 0;
}

static int
isgen(char *s)
{
	char *s1, *s2;

	s1 = strchr(s, '_');
	s2 = strrchr(s, '_');
	if(s1 == nil || s2-s1 != 4)
		return 0;
	return s1[1] == 'a' && s1[2] == 'd' && s1[3] == 't';
}

static void
addmodn(Sym *s)
{
	char buf[128], *ns;

	if(s->name[0] == '_'){
		outmod(buf, -1);
		ns = malloc(strlen(buf)+strlen(s->name)+1);
		strcpy(ns, buf);
		strcat(ns, s->name);
		s->name = ns;
	}
}
		
static void
pfmt(char *s)
{
	char *t = s;

	while(*s != '\0'){
		if(*s == '%'){
			*t++ = *s++;
			if(*s == 'l'){
				s++;
				if(*s == 'l')
					*t++ = 'b';
				else
					*t++ = *s;
				s++;
			}
			else if(*s == 'p'){
				*t++ = 'x';
				s++;
			}
			else
				*t++ = *s++;
		}
		else
			*t++ = *s++;
	}
	*t = '\0';
}

static void
lpfmt(ushort *s)
{
	 ushort*t = s;

	while(*s != '\0'){
		if(*s == '%'){
			*t++ = *s++;
			if(*s == 'l'){
				s++;
				if(*s == 'l')
					*t++ = 'b';
				else
					*t++ = *s;
				s++;
			}
			else if(*s == 'p'){
				*t++ = 'x';
				s++;
			}
			else
				*t++ = *s++;
		}
		else
			*t++ = *s++;
	}
	*t = '\0';
}

int
line(Node *n)
{
	if(n == Z)
		return 0;
	if(n->op == OLIST)
		return line(n->left);
	return n->lineno;
}

static int
lline(Node *n)
{
	if(n == Z)
		return 0;
	if(n->op == OLIST)
		return lline(n->right);
	return n->lineno+1;
}

static Node*
lastn(Node *n)
{
	while(n != Z && n->op == OLIST)
		n = n->right;
	return n;
}

static Node*
newnode(int op, Node *l)
{
	Node *n;

	n = new1(op, l, Z);
	globe->right = n;
	globe = n;
	return n;
}

void
codgen1(Node *n, Node *nn, int lastlno)
{
	Node *nnn;

	scomplex(n);
	nnn = newnode(OCODE, new1(OLIST, n, nn));
	nnn->lineno = lastlno;
	mset(n);
	mset(nn);
	nn = func(nn);
	newnode(ODECF, nn);
	setmain(nn);
}

void
vtgen1(Node *n)
{
	int c;
	Node *nn = n;

	if(n->op == ODAS)
		nn = n->left;
	if(nn->type == T || nn->sym == S)
		return;
	c = nn->sym->class;
	if(c == CGLOBL || c == CSTATIC || c == CLOCAL || c == CEXREG){
		newnode(ODECV, n);
		if(nn->type->etype != TFUNC || ism())
			setmod(nn->sym);
	}
	mset(n);
}

void
etgen1(Sym *s)
{
	Node *n;

	n = newnode(ODECE, Z);
	n->sym = s;
	if(s != S)
		setmod(s);
}

void
ttgen1(Type *t)
{
	Node *n;

	n = newnode(ODECT, Z);
	n->type = t;
	if(isadt(t))
		setmod(suename(t));
}

void
outpush1(char *s)
{
	Node *n;
	char *t;

	n = newnode(OPUSH, Z);
	if(s == nil)
		t = nil;
	else{
		t = malloc(strlen(s)+1);
		strcpy(t, s);
	}
	n->cstring = t;
	outpush0(s, n);
}

void
outpop1(int lno)
{
	Node *n;

	n = newnode(OPOP, Z);
	n->lineno = lno;
	outpop0(lno);
}

void
codgen(Node *n, Node *nn, int lastlno)
{
	if(passes)
		codgen1(n, nn, lastlno);
	else
		codgen2(n, nn, lastlno, 1);
}

void
vtgen(Node *n)
{
	if(passes)
		vtgen1(n);
	else
		vtgen2(n);
}

void
etgen(Sym *s)
{
	if(passes)
		etgen1(s);
	else
		etgen2(s);
}

void
ttgen(Type *t)
{
	if(passes)
		ttgen1(t);
	else
		ttgen2(t);
}

void
outpush(char *s)
{
	if(passes)
		outpush1(s);
	else
		outpush2(s, Z);
}

void
outpop(int lno)
{
	if(passes)
		outpop1(lno);
	else
		outpop2(lno);
}

static void
swalk(void)
{
	Node *n, *l;

	for(n = glob; n != Z; n = n->right){
		l = n->left;
		switch(n->op){
			case OCODE:
				rewall(l->left, l->right, n->lineno);
				break;
			default:
				break;
		}
	}
	while(again){
		again = 0;
		for(n = glob; n != Z; n = n->right){
			l = n->left;
			switch(n->op){
				case OCODE:
					suball(l->left, l->right);
					break;
				case ODECV:
					subs(l, 0, 0);
					break;
				case ODECE:
				case ODECT:
				case ODECF:
					break;
				default:
					break;
			}
		}
	}
	for(n = glob; n != Z; n = n->right){
		l = n->left;
		switch(n->op){
			case ONOOP:
				break;
			case OPUSH:
				outpush2(n->cstring, n);
				break;
			case OPOP:
				outpop2(n->lineno);
				break;
			case OCODE:
				codgen2(l->left, l->right, n->lineno, 0);
				break;
			case ODECV:
				vtgen2(l);
				break;
			case ODECE:
				etgen2(n->sym);
				break;
			case ODECT:
				ttgen2(n->type);
				break;
			case ODECF:
				break;
		}
	}
}

static void
scomplex(Node *n)
{
	if(n == Z)
		return;
	switch(n->op){
		default:
			complex(n);
			break;
		case ODAS:
		case OSBREAK:
		case ONUL:
		case OLABEL:
		case OGOTO:
		case OCONTINUE:
		case OBREAK:
			break;
		case ONAME:
			if(n->kind == KEXP)
				complex(n);
			break;
		case OBLK:
		case OSET:
		case OUSED:
			scomplex(n->left);
			break;
		case OLIST:
			scomplex(n->left);
			scomplex(n->right);
			break;
		case ORETURN:
			complex(n);
			break;
		case OCASE:
			complex(n->left);
			break;
		case OSWITCH:
		case OWHILE:
		case ODWHILE:
			complex(n->left);
			scomplex(n->right);
			break;
		case OFOR:
			complex(n->left->left);
			complex(n->left->right->left);
			complex(n->left->right->right);
			scomplex(n->right);
			break;
		case OIF:
			complex(n->left);
			scomplex(n->right->left);
			scomplex(n->right->right);
			break;
	}
}

static void
mtset(Type *t)
{
	if(t == T)
		return;
	switch(t->etype){
		case TIND:
		case TARRAY:
			mtset(t->link);
			break;
		case TSTRUCT:
		case TUNION:
			prsym0(suename(t));
			/*
			for(l = t->link; l != T; l = l->down)
				mtset(l);
			*/
			break;
	}
}

static void
mset(Node *n)
{
	if(n == Z)
		return;
	n->garb = 0;
	if(n->op == ONAME)
		prsym0(n->sym);
	mtset(n->type);
	mset(n->left);
	mset(n->right);
}

static int
sign(Node *n)
{
	int s;

	if(n == Z)
		return 1;
	switch(n->op){
		case OCONST:
			sign(n->left);
			if(n->vconst < 0){
				n->vconst = -n->vconst;
				return -1;
			}
			break;
		case OPOS:
			s = sign(n->left);
			*n = *n->left;
			return s;
		case ONEG:
			s = sign(n->left);
			*n = *n->left;
			return -s;
		case OADD:
			if(sign(n->right) < 0)
				n->op = OSUB;
			break;
		case OSUB:
			if(sign(n->right) < 0)
				n->op = OADD;
			break;
		case OMUL:
		case ODIV:
			return sign(n->left)*sign(n->right);
		default:
			break;
	}
	return 1;
}

static Node*
ckneg(Node *n)
{
	if(sign(n) < 0)
		return new1(ONEG, n, Z);
	return n;
}

static void
sliceasgn(Node *n)
{
	Type *t;
	Node *nn;

	if(side(n->left) || (n->right != Z && side(n->right)))
		return;
	t = n->type;
	if(isarray(t) && (!strings || t->link->etype != TCHAR)){
		if(n->op == OASADD)
			nn = n->right;
		else
			nn = con(1);
		n->op = OAS;
		n->right = new1(OSLICE, ncopy(n->left), new1(OLIST, nn, Z));
	}
}
