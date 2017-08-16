#include "lib9.h"
#include "isa.h"
#include "interp.h"
#include "runt.h"
#include "sysmod.h"
#include "raise.h"


static	int		utfnleng(char*, int, int*);

void
sysmodinit(void)
{
	sysinit();
	builtinmod("$Sys", Sysmodtab, Sysmodlen);
}

int
xprint(Prog *xp, void *vfp, void *vva, String *s1, char *buf, int n)
{
	WORD i;
	void *p;
	LONG bg;
	Type *t;
	double d;
	String *ss;
	ulong *ptr;
	uchar *fp, *va;
	int nc, c, isbig, isr, sip;
	char *b, *eb, *f, fmt[32];
	Rune r;

	fp = vfp;
	va = vva;

	sip = 0;
	isr = 0;
	if(s1 == H)
		return 0;
	nc = s1->len;
	if(nc < 0) {
		nc = -nc;
		isr = 1;
	}

	b = buf;
	eb = buf+n-1;
	while(nc--) {
		c = isr ? s1->Srune[sip] : s1->Sascii[sip];
		sip++;
		if(c != '%') {
			if(b < eb) {
				if(c < Runeself)
					*b++ = c;
				else
					b += snprint(b, eb-b, "%C", c);
			}
			continue;
		}
		f = fmt;
		*f++ = c;
		isbig = 0;
		while(nc--) {
			c = isr ? s1->Srune[sip] : s1->Sascii[sip];
			sip++;
			*f++ = c;
			*f = '\0';
			switch(c) {
			default:
				continue;
			case '*':
				i = *(WORD*)va;
				f--;
				f += snprint(f, sizeof(fmt)-(f-fmt), "%d", i);
				va += IBY2WD;
				continue;
			case 'b':
				f[-1] = 'l';
				*f++ = 'l';
				*f = '\0';
				isbig = 1;
				continue;
			case '%':
				if(b < eb)
					*b++ = '%';
				break;
			case 'q':
			case 's':
				ss = *(String**)va;
				va += IBY2WD;
				if(ss == H)
					p = "";
				else
				if(ss->len < 0) {
					f[-1] += 'A'-'a';
					ss->Srune[-ss->len] = L'\0';
					p = ss->Srune;
				}
				else {
					ss->Sascii[ss->len] = '\0';
					p = ss->Sascii;
				}
				b += snprint(b, eb-b, fmt, p);
				break;
			case 'E':
				f--;
				r = 0x00c9;	/* L'É' */
				f += runetochar(f, &r);	/* avoid clash with ether address */
				*f = '\0';
				/* fall through */
			case 'e':
			case 'f':
			case 'g':
			case 'G':
				while((va - fp) & (sizeof(REAL)-1))
					va++;
				d = *(REAL*)va;
				b += snprint(b, eb-b, fmt, d);
				va += sizeof(REAL);
				break;
			case 'd':
			case 'o':
			case 'x':
			case 'X':
			case 'c':
				if(isbig) {
					while((va - fp) & (IBY2LG-1))
						va++;
					bg = *(LONG*)va;
					b += snprint(b, eb-b, fmt, bg);
					va += IBY2LG;
				}
				else {
					i = *(WORD*)va;
					/* always a unicode character */
					if(c == 'c')
						f[-1] = 'C';
					b += snprint(b, eb-b, fmt, i);
					va += IBY2WD;
				}
				break;
			case 'r':
				b = syserr(b, eb, xp);
				break;
/* Debugging formats - may disappear */
			case 'H':
				ptr = *(ulong**)va;
				c = -1;
				t = nil;
				if(ptr != H) {
					c = D2H(ptr)->ref;
					t = D2H(ptr)->t;
				}
				b += snprint(b, eb-b, "%d.%.8lux", c, (ulong)t);
				va += IBY2WD;
				break;
			}
			break;
		}
	}
	return b - buf;
}

int
bigxprint(Prog *xp, void *vfp, void *vva, String *s1, char **buf, int s)
{
	char *b;
	int m, n;

	m = s;
	for (;;) {
		m *= 2;
		b = malloc(m);
		if (b == nil)
			error(exNomem);
		n = xprint(xp, vfp, vva, s1, b, m);
		if (n < m-UTFmax-2)
			break;
		free(b);
	}
	*buf = b;
	return n;
}

void
Sys_sprint(void *fp)
{
	int n;
	char buf[256], *b = buf;
	F_Sys_sprint *f;

	f = fp;
	n = xprint(currun(), f, &f->vargs, f->s, buf, sizeof(buf));
	if (n >= sizeof(buf)-UTFmax-2)
		n = bigxprint(currun(), f, &f->vargs, f->s, &b, sizeof(buf));
	b[n] = '\0';
	retstr(b, f->ret);
	if (b != buf)
		free(b);
}

void
Sys_aprint(void *fp)
{
	int n;
	char buf[256], *b = buf;
	F_Sys_aprint *f;

	f = fp;
	n = xprint(currun(), f, &f->vargs, f->s, buf, sizeof(buf));
	if (n >= sizeof(buf)-UTFmax-2)
		n = bigxprint(currun(), f, &f->vargs, f->s, &b, sizeof(buf));
	destroy(*f->ret);
	*f->ret = mem2array(b, n);
	if (b != buf)
		free(b);
}

static int
tokdelim(int c, String *d)
{
	int l;
	char *p;
	Rune *r;

	l = d->len;
	if(l < 0) {
		l = -l;
		for(r = d->Srune; l != 0; l--)
			if(*r++ == c)
				return 1;
		return 0;
	}
	for(p = d->Sascii; l != 0; l--)
		if(*p++ == c)
			return 1;
	return 0;
}

void
Sys_tokenize(void *fp)
{
	String *s, *d;
	List **h, *l, *nl;
	F_Sys_tokenize *f;
	int n, c, nc, first, last, srune;

	f = fp;
	s = f->s;
	d = f->delim;

	if(s == H || d == H) {
		f->ret->t0 = 0;
		destroy(f->ret->t1);
		f->ret->t1 = H;
		return;
	}

	n = 0;
	l = H;
	h = &l;
	first = 0;
	srune = 0;

	nc = s->len;
	if(nc < 0) {
		nc = -nc;
		srune = 1;
	}

	while(first < nc) {
		while(first < nc) {
			c = srune ? s->Srune[first] : s->Sascii[first];
			if(tokdelim(c, d) == 0)
				break;	
			first++;
		}

		last = first;

		while(last < nc) {
			c = srune ? s->Srune[last] : s->Sascii[last];
			if(tokdelim(c, d) != 0)
				break;	
			last++;
		}

		if(first == last)
			break;

		nl = cons(IBY2WD, h);
		nl->tail = H;
		nl->t = &Tptr;
		Tptr.ref++;
		*(String**)nl->data = slicer(first, last, s);
		h = &nl->tail;

		first = last;
		n++;
	}

	f->ret->t0 = n;
	destroy(f->ret->t1);
	f->ret->t1 = l;
}

void
Sys_utfbytes(void *fp)
{
	Array *a;
	int nbyte;
	F_Sys_utfbytes *f;

	f = fp;
	a = f->buf;
	if(a == H || (UWORD)f->n > a->len)
		error(exBounds);

	utfnleng((char*)a->data, f->n, &nbyte);
	*f->ret = nbyte;
}

void
Sys_byte2char(void *fp)
{
	Rune r;
	char *p;
	int n, w;
	Array *a;
	F_Sys_byte2char *f;

	f = fp;
	a = f->buf;
	n = f->n;
	if(a == H || (UWORD)n >= a->len)
		error(exBounds);
	r = a->data[n];
	if(r < Runeself){
		f->ret->t0 = r;
		f->ret->t1 = 1;
		f->ret->t2 = 1;
		return;
	}
	p = (char*)a->data+n;
	if(n+UTFmax <= a->len || fullrune(p, a->len-n))
		w = chartorune(&r, p);
	else {
		/* insufficient data */
		f->ret->t0 = Runeerror;
		f->ret->t1 = 0;
		f->ret->t2 = 0;
		return;
	}
	if(r == Runeerror && w==1){	/* encoding error */
		f->ret->t0 = Runeerror;
		f->ret->t1 = 1;
		f->ret->t2 = 0;
		return;
	}
	f->ret->t0 = r;
	f->ret->t1 = w;
	f->ret->t2 = 1;
}

void
Sys_char2byte(void *fp)
{
	F_Sys_char2byte *f;
	Array *a;
	int n, c;
	Rune r;

	f = fp;
	a = f->buf;
	n = f->n;
	c = f->c;
	if(a == H || (UWORD)n>=a->len)
		error(exBounds);
	if(c<0 || c>=Runemax)
		c = Runeerror;
	if(c < Runeself){
		a->data[n] = c;
		*f->ret = 1;
		return;
	}
	r = c;
	if(n+UTFmax<=a->len || runelen(c)<=a->len-n){
		*f->ret = runetochar((char*)a->data+n, &r);
		return;
	}
	*f->ret = 0;
}

Module *
builtinmod(char *name, void *vr, int rlen)
{
	Runtab *r = vr;
	Type *t;
	Module *m;
	Link *l;

	m = newmod(name);
	if(rlen == 0){
		while(r->name){
			rlen++;
			r++;
		}
		r = vr;
	}
	l = m->ext = (Link*)malloc((rlen+1)*sizeof(Link));
	if(l == nil){
		freemod(m);
		return nil;
	}
	while(r->name) {
		t = dtype(freeheap, r->size, r->map, r->np);
		runtime(m, l, r->name, r->sig, r->fn, t);
		r++;
		l++;
	}
	l->name = nil;
	return m;
}

void
retnstr(char *s, int n, String **d)
{
	String *s1;

	s1 = H;
	if(n != 0)
		s1 = c2string(s, n);
	destroy(*d);
	*d = s1;
}

void
retstr(char *s, String **d)
{
	String *s1;

	s1 = H;
	if(s != nil)
		s1 = c2string(s, strlen(s));
	destroy(*d);
	*d = s1;
}

Array*
mem2array(void *va, int n)
{
	Heap *h;
	Array *a;

	if(n < 0)
		n = 0;
	h = nheap(sizeof(Array)+n);
	h->t = &Tarray;
	h->t->ref++;
	a = H2D(Array*, h);
	a->t = &Tbyte;
	Tbyte.ref++;
	a->len = n;
	a->root = H;
	a->data = (uchar*)a+sizeof(Array);
	if(va != 0)
		memmove(a->data, va, n);

	return a;
}

static int
utfnleng(char *s, int nb, int *ngood)
{
	int c;
	long n;
	Rune rune;
	char *es, *starts;

	starts = s;
	es = s+nb;
	for(n = 0; s < es; n++) {
		c = *(uchar*)s;
		if(c < Runeself)
			s++;
		else {
			if(s+UTFmax<=es || fullrune(s, es-s))
				s += chartorune(&rune, s);
			else
				break;
		}
	}
	if(ngood)
		*ngood = s-starts;
	return n;
}
