#include "lib9.h"
#include "interp.h"
#include "pool.h"


typedef struct Audit Audit;
struct Audit
{
	Type*	t;
	ulong	n;
	ulong	size;
	Audit*	hash;
};
Audit*	ahash[128];
extern	Pool*	heapmem;
extern void conslog(char*, ...);
#define	conslog	print

typedef struct Typed	Typed;
typedef struct Ptyped	Ptyped;

extern Type Trdchan;
extern Type Twrchan;

struct Typed
{
	char*	name;
	Type*	ptr;
} types[] =
{
	{"array",	&Tarray},
	{"byte",	&Tbyte},
	{"channel",	&Tchannel},
	{"list",	&Tlist},
	{"modlink",	&Tmodlink},
	{"ptr",		&Tptr},
	{"string",	&Tstring},

	{"rdchan",	&Trdchan},
	{"wrchan",	&Twrchan},
	{"unspec",	nil},

	0
};

extern Type* TDisplay;
extern Type* TFont;
extern Type* TImage;
extern Type* TScreen;
extern Type* TFD;
extern Type* TFileIO;
extern Type* Tread;
extern Type* Twrite;
extern Type* fakeTkTop;

extern Type* TSigAlg;
extern Type* TCertificate;
extern Type* TSK;
extern Type* TPK;
extern Type* TDigestState;
extern Type* TAuthinfo;
extern Type* TDESstate;
extern Type* TIPint;

struct Ptyped
{
	char*	name;
	Type**	ptr;
} ptypes[] =
{
	{"Display",	&TDisplay},
	{"Font",	&TFont},
	{"Image",	&TImage},
	{"Screen",	&TScreen},

	{"SigAlg",	&TSigAlg},
	{"Certificate",	&TCertificate},
	{"SK",		&TSK},
	{"PK",		&TPK},
	{"DigestState",	&TDigestState},
	{"Authinfo",	&TAuthinfo},
	{"DESstate",	&TDESstate},
	{"IPint",	&TIPint},

	{"FD",		&TFD},
	{"FileIO",	&TFileIO},

/*	{"Fioread",	&Tread},	*/
/*	{"Fiowrite",	&Twrite},	*/

	{"TkTop",	&fakeTkTop},

	0
};

static Audit **
auditentry(Type *t)
{
	Audit **h, *a;

	for(h = &ahash[((ulong)t>>2)%nelem(ahash)]; (a = *h) != nil; h = &a->hash)
		if(a->t == t)
			break;
	return h;
}

void
heapaudit(void)
{
	Type *t;
	Heap *h;
	List *l;
	Array *r;
	Module *m;
	int i, ntype, n;
	Bhdr *b, *base, *limit;
	Audit *a, **hash;

	acquire();

	b = poolchain(heapmem);
	base = b;
	limit = B2LIMIT(b);

	while(b != nil) {
		if(b->magic == MAGIC_A) {
			h = B2D(b);
			t = h->t;
			n = 1;
			if(t == &Tlist) {
				l = H2D(List*, h);
				t = l->t;
			} else if(t == &Tarray) {
				r = H2D(Array*, h);
				t = r->t;
				n = r->len;
			}
			hash = auditentry(t);
			if((a = *hash) == nil){
				a = malloc(sizeof(Audit));
				if(a == nil)
					continue;
				a->n = 1;
				a->t = t;
				a->hash = *hash;
				*hash = a;
			}else
				a->n++;
			if(t != nil && t != &Tmodlink && t != &Tstring)
				a->size += t->size*n;
			else
				a->size += b->size;
		}
		b = B2NB(b);
		if(b >= limit) {
			base = base->clink;
			if(base == nil)
				break;
			b = base;
			limit = B2LIMIT(base);
		}
	}

	for(m = modules; m != nil; m = m->link) {
		for(i = 0; i < m->ntype; i++)
			if((a = *auditentry(m->type[i])) != nil) {
				conslog("%8ld %8lud %3d %s\n", a->n, a->size, i, m->path);
				a->size = 0;
				break;
			}
	}

	for(i = 0; (t = types[i].ptr) != nil; i++)
		if((a = *auditentry(t)) != nil){
			conslog("%8ld %8lud %s\n", a->n, a->size, types[i].name);
			a->size = 0;
			break;
		}

	for(i = 0; ptypes[i].name != nil; i++)
		if((a = *auditentry(*ptypes[i].ptr)) != nil){
			conslog("%8ld %8lud %s\n", a->n, a->size, ptypes[i].name);
			a->size = 0;
			break;
		}

	ntype = 0;
	for(i = 0; i < nelem(ahash); i++)
		while((a = ahash[i]) != nil){
			ahash[i] = a->hash;
			if(a->size != 0)
				conslog("%8ld %8lud %p\n", a->n, a->size, a->t);
			free(a);
			ntype++;
		}

	release();
}
