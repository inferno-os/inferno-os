#include	"auxi.h"

/*
 * in some embedded coff files, edata and end have type 0 not 4,
 * and file value is pointer to next file sym (as here), but the last one
 * points to an external symbol, not 0 as here.
 */

#define C_NULL	0
#define C_AUTO	1
#define C_EXT		2
#define C_STAT	3
#define C_ARG		9
#define C_FCN		101
#define C_FILE		103

#define T_VOID	0
#define T_CHAR	2
#define T_SHORT	3
#define T_INT		4
#define T_LONG	5

#define DT_NON	0
#define DT_PTR	1
#define DT_FCN	2
#define DT_ARY	3

#define T(a, b)	(((a)<<4)|b)

#define DOTTEXT	".text"
#define DOTDATA	".data"
#define DOTBSS	".bss"
#define DOTBF		".bf"
#define DOTEF		".ef"

#define SINDEX(s)	(*((long*)(&s->become)))
#define LINDEX(s)	(*((long*)(&s->used)))

typedef struct Hist Hist;

struct Hist{
	Auto *a;
	Hist *n;
};

static int nsym, nlc, lines;

static void cofflcsz(void);

static Hist *freeh, *curh;

static void
dohist(Auto *a)
{
	Hist *h, **ha;

	if(a->aoffset == 1){	/* new file */
		for(ha = &curh; *ha != nil; ha = &((*ha)->n))
			;
		*ha = freeh;
		freeh = curh;
		curh = nil;
	}
	if(freeh != nil){
		h = freeh;
		freeh = freeh->n;
	}
	else
		h = malloc(sizeof(Hist));
	h->a = a;
	h->n = nil;
	for(ha = &curh; *ha != nil; ha = &((*ha)->n))
		;
	*ha = h;
}

static long
lineno(long n)
{
	long o, d;
	Hist *h;

	if(1)
		return n;	/* now using fileline() not pc2line() */

	if(curh == nil)
		return 0;
	o = curh->a->aoffset-1;
	d = 1;
	for(h = curh->n; d && h != nil; h = h->n){
		if(h->a->asym->name[1] || h->a->asym->name[2]){
			if(h->a->type == D_FILE1) {
				;
			}
			else if(d == 1 && n < h->a->aoffset)
				break;
			else if(d++ == 1)
				o -= h->a->aoffset;
		}
		else if(--d == 1)
			o += h->a->aoffset;
	}
	return n-o;
}

static char *
filelookup(int k)
{
	int i;
	Symx *s;

	for(i = 0; i < NHASH; i++){
		for(s = hash[i]; s != nil; s = s->link){
			if(s->type == SFILE && k == s->value)
				return s->name+1;
		}
	}
	return "";
}

static char*
filename(char *s)
{
	int j, k, l;
	static char buf[256];

	buf[0] = '\0';
	if(s[0] != 0)
		diag("bad filename");
	for(j = 1; ; j += 2){
		k = (s[j]<<8)|s[j+1];
		if(k == 0)
			break;
		l = strlen(buf);
		if(l != 0 && buf[l-1] != '/')
			strcat(buf, "/");
		strcat(buf, filelookup(k));
	}
	return buf;
}

static void
sput(char *s, int n)
{
	int i;

	for(i = 0; i < n && s != nil && *s != '\0'; i++, s++)
		cput(*s);
	for( ; i < n; i++)
		cput(0);
}

static void
coffsect(char *s, long a, long sz, long o, long lp, long nl, long f)
{
	if(0)
		print("sect %s pa=%lux va=%lux sz=%lux\n", s, a, a, sz);
	sput(s, 8);			/* name <= 8 chars in len */
	lputl(a);			/* pa */
	lputl(a);			/* va */
	lputl(sz);			/* size */
	lputl(o);			/* file offset */
	lputl(0);			/* reloc */
	lputl(lp);			/* line nos */
	lputl(0);			/* no reloc entries */
	lputl(nl);			/* no line no entries */
	lputl(f);			/* flags */
	hputl(0);			/* reserved */
	hputl(0);			/* mem page no */
}

void
coffhdr(void)
{
	if(0){
		print("H=%lux t=%lux d=%lux b=%lux\n", HEADR, textsize, datsize, bsssize);
		print("e=%lux ts=%lux ds=%lux\n", entryvalue(), INITTEXT, INITDAT);
	}

	/*
	 * file header
	 */
	hputl(0xc2);			/* version ID */
	hputl(3);				/* no section hdrs */
	lputl(0);				/* date stamp */
	lputl(HEADR+textsize+datsize+6*nlc);	/* sym table */
	lputl(nsym);			/* no sym table entries */
	hputl(28);				/* size optional hdr */
	hputl(0x0103);			/* flags */
	hputl(0x97);			/* target ID */
	/*
	 * optional file header
	 */
	hputl(0x108);			/* magic */
	hputl(0);				/* version stamp */
	lputl(textsize);			/* text size */
	lputl(datsize);			/* data size */
	lputl(bsssize);			/* bss size */
	lputl(entryvalue());		/* entry pt */
	lputl(INITTEXT);		/* text start */
	lputl(INITDAT);			/* data start */
	/*
	 * sections
	 */
	coffsect(DOTTEXT, INITTEXT, textsize, HEADR, HEADR+textsize+datsize, nlc, 0x20);
	coffsect(DOTDATA, INITDAT, datsize, HEADR+textsize, 0, 0, 0x40);
	coffsect(DOTBSS, INITDAT+datsize, bsssize, 0, 0, 0, 0x80);
}

static int
private(char *s)
{
	return strcmp(s, "safe") == 0 || strcmp(s, "ret") == 0 || strcmp(s, "string") == 0;
}

static long stoff = 4;

static long
stput(char *s)
{
	long r;

	r = stoff;
	stoff += strlen(s)+1;
	return r;
}

static long
strput(char *s)
{
	int l;

	if((l = strlen(s)) > 8){
		if(*s == '.' && private(s+1))
			return 0;
		while(*s)
			cput(*s++);
		cput(*s);
		return l+1;
	}
	return 0;
}

static void
stflush(void)
{
	int i;
	long o;
	Prog *p;
	Auto *a, *f;
	Symx *s;
	char *fn, file[256];

	lputl(stoff);
	o = 4;
	for(p = firstp; p != P; p = p->link){
		if(p->as == ATEXT){
			f = nil;
			fn = nil;
			for(a = p->to.autom; a != nil; a = a->link){
				if(a->type == D_FILE){
					f = a;
					break;
				}
			}
			if(f != nil)
				fn = filename(f->asym->name);
			if(fn != nil && *fn != '\0' && strcmp(fn, file) != 0){
				strcpy(file, fn);
				o += strput(file);
			}
			o += strput(p->from.sym->name);
			for(a = p->to.autom; a != nil; a = a->link){
				if(a->type == D_AUTO || a->type == D_PARAM)
					o += strput(a->asym->name);
			}
		}
	}
	for(i = 0; i < NHASH; i++){
		for(s = hash[i]; s != nil; s = s->link){
			if(s->version > 0 && (s->type == SDATA || s->type == SBSS))
				o += strput(s->name);
		}
	}
	for(i = 0; i < NHASH; i++){
		for(s = hash[i]; s != nil; s = s->link){
			if(s->version == 0 && (s->type == SDATA || s->type == SBSS))
				o += strput(s->name);
		}
	}
	if(o != stoff)
		diag("bad stflush offset");
}

static int
putsect(Symx *s)
{
	int sz, ln;

	sz = ln = 0;
	// isn't this repetition ?
	if(strcmp(s->name, DOTTEXT) == 0){
		sz = textsize;
		ln = nlc;
	}
	else if(strcmp(s->name, DOTDATA) == 0)
		sz = datsize;
	else if(strcmp(s->name, DOTBSS) == 0)
		sz = bsssize;
	else
		diag("bad putsect sym");
	lputl(sz);
	hputl(0);
	hputl(ln);
	sput(nil, 10);
	return 1;
}

static int
putfun(Symx *s)
{
	/* lputl(SINDEX(s)+2); */
	lputl(0);
	lputl(0);	/* patched later */
	lputl(HEADR+textsize+datsize+LINDEX(s));
	lputl(0);	/* patched later */
	sput(nil, 2);
	return 1;
}

static int
putbf(int lno)
{
	lputl(0);
	hputl(lno);
	hputl(lines);
	lputl(autosize);
	lputl(0);	/* patched later */
	sput(nil, 2);
	return 1;
}

static int
putef(int lno)
{
	sput(nil, 4);
	hputl(lno);
	sput(nil, 12);
	return 1;
}

static int
putsym(Symx *s, int sc, int t, int lno)
{
	long v;

	if(s == nil || s->name == nil || s->name[0] == '\0' || (s->name[0] == '.' && private(s->name+1)))
		return 0;
	if(0)
		print("putsym %s %d %ld %d %d\n", s->name, s->type, s->value, sc, t);
	if(strlen(s->name) <= 8)
		sput(s->name, 8);
	else{
		lputl(0);
		lputl(stput(s->name));
	}
	/* value */
	v = s->value;
	if(s->type == SDATA || s->type == SDATA1 || s->type == SBSS)
		lputl(INITDAT+v);
	else if(sc == C_AUTO)
		lputl(autosize+v);
	else if(sc == C_ARG)
		lputl(autosize+v+4);
	else
		lputl(v);
	switch(s->type){	/* section number */
	case STEXT:
	case SLEAF:
		hputl(1);
		break;
	case SDATA:
	case SDATA1:
		hputl(2);
		break;
	case SBSS:
		hputl(3);
		break;
	case SFILE:
		hputl(-2);
		break;
	default:
		diag("type %d in putsym", s->type);
		break;
	}
	hputl(t);			/* type */
	cput(sc);			/* storage class */
	/* aux entries */
	if(sc == C_STAT && t == T_VOID && s->name[0] == '.'){	/* section */
		cput(1);
		return 1+putsect(s);
	}
	else if((t>>4) == DT_FCN){	/* function */
		cput(1);
		return 1+putfun(s);
	}
	else if(sc == C_FCN && strcmp(s->name, DOTBF) == 0){	/* bf */
		cput(1);
		return 1+putbf(lno);
	}
	else if(sc == C_FCN && strcmp(s->name, DOTEF) == 0){	/* ef */
		cput(1);
		return 1+putef(lno);
	}
	cput(0);			/* 0 aux entry */
	return 1;
}

static Symx*
defsym(char *p, int t, long v)
{
	Symx *s;

	s = lookupsym(p, 0);
	if(s->type == SDATA || s->type == SBSS)
		return nil;		/* already output */
	if(s->type == 0 || s->type == SXREF){
		s->type = t;
		s->value = v;
	}
	return s;
}

static int
specsym(char *p, int t, long v, int c)
{
	return putsym(defsym(p, t, v), c, T_VOID, 0);
}

static int
cclass(Symx *s)
{
/*
	if(s->version > 0 && dclass == D_EXTERN)
		diag("%s: version %d dclass EXTERN", s->name, s->version);
	if(s->version == 0 && dclass == D_STATIC)
		diag("%s: version %d dclass STATIC", s->name, s->version);
*/
	return s->version > 0 ? C_STAT : C_EXT;
}

static void
patchsym(long i, long o, long v)
{
	long oo;

	cflush();
	oo = seek(cout, 0, 1);
	seek(cout, HEADR+textsize+datsize+6*nlc+18*i+o, 0);
	lputl(v);
	cflush();
	seek(cout, oo, 0);
}

void
coffsym(void)
{
	int i;
	long ns, lno, lpc, v, vs, lastf;
	Prog *p;
	Auto *a, *f;
	Symx *s, *bf, *ef, ts;
	char *fn, file[256];

	file[0] = '\0';
	cofflcsz();
	seek(cout, 6*nlc, 1);		/* advance over line table */
	ns = 0;
	lpc = -1;
	lno = -1;
	lastf = -1;
	bf = defsym(DOTBF, STEXT, 0);
	ef = defsym(DOTEF, STEXT, 0);
	for(p = firstp; p != P; p = p->link){
		if(p->as != ATEXT){
			if(p->line != 0)
				lno = lineno(p->line);
		}
		if(p->as == ATEXT){
			curtext = p;
			autosize = p->to.offset+4;
			if(lpc >= 0){
				ef->value = lpc;
				ns += putsym(ef, C_FCN, T_VOID, lno);
			}
			f = nil;
			fn = nil;
			for(a = p->to.autom; a != nil; a = a->link){
				if(a->type == D_FILE || a->type == D_FILE1)
					dohist(a);
				if(f == nil && a->type == D_FILE)
					f = a;		/* main filename */
			}
			if(f != nil)
				fn = filename(f->asym->name);
			if(fn != nil && *fn != '\0' && strcmp(fn, file) != 0){
				strcpy(file, fn);
				ts.name = file;
				ts.type = SFILE;
				ts.value = 0;
				if(lastf >= 0)
					patchsym(lastf, 8, ns);
				lastf = ns;
				ns += putsym(&ts, C_FILE, T_VOID, 0);
			}
			if(p->link != P && p->link->line != 0)
				lno = lineno(p->link->line);
			else if(p->line != 0)
				lno = lineno(p->line);
			s = p->from.sym;
			SINDEX(s) = ns;
			ns += putsym(s, cclass(s), T(DT_FCN, T_INT), 0);
			if(p->cond != P)
				lines = LINDEX(p->cond->from.sym)-LINDEX(s)-1;
			else
				lines = 0;
			bf->value = p->pc;
			ns += putsym(bf, C_FCN, T_VOID, lno);
			for(a = p->to.autom; a != nil; a = a->link){
				if(a->type == D_AUTO || a->type == D_PARAM){
					ts.name = a->asym->name;
					ts.type = STEXT;
					ts.value = a->aoffset;
					ns += putsym(&ts, a->type == D_AUTO ? C_AUTO : C_ARG, T_INT, 0);
				}
			}
		}
		lpc = p->pc;
	}
	if(lpc >= 0){
		ef->value = lpc;
		ns += putsym(ef, C_FCN, T_VOID, lno);
	}
	/* patch up */
	for(p = textp; p != P; p = p->cond){
		s = p->from.sym;
		if(p->cond != P){
			v = SINDEX(p->cond->from.sym);
			vs = p->cond->pc - p->pc;
		}
		else{
			v = 0;
			vs = INITTEXT+textsize-p->pc;
		}
		patchsym(SINDEX(s)+1, 4, 8*vs);
		patchsym(SINDEX(s)+1, 12, v);
		patchsym(SINDEX(s)+3, 12, v);
	}
	for(i = 0; i < NHASH; i++){
		for(s = hash[i]; s != nil; s = s->link){
			if(s->version > 0 && (s->type == SDATA || s->type == SBSS))
				ns += putsym(s, cclass(s), T_INT, 0);
		}
	}
	for(i = 0; i < NHASH; i++){
		for(s = hash[i]; s != nil; s = s->link){
			if(s->version == 0 && (s->type == SDATA || s->type == SBSS))
				ns += putsym(s, cclass(s), T_INT, 0);
		}
	}
	ns += specsym(DOTTEXT, STEXT, INITTEXT, C_STAT);
	ns += specsym(DOTDATA, SDATA, 0, C_STAT);
	ns += specsym(DOTBSS, SBSS, datsize, C_STAT);
	ns += specsym("etext", STEXT, INITTEXT+textsize, C_EXT);
	ns += specsym("edata", SDATA, datsize, C_EXT);
	ns += specsym("end", SBSS, datsize+bsssize, C_EXT);
	nsym = ns;
	stflush();
}

void
cofflc(void)
{
	long olc, nl;
	Symx *s;
	Prog *p;
	Auto *a;

	cflush();
	seek(cout, HEADR+textsize+datsize, 0);
	nl = 0;
	/* opc = INITTEXT; */
	olc = 0;
	for(p = firstp; p != P; p = p->link){
		if(p->as == ATEXT){
			curtext = p;
			s = p->from.sym;
			/* opc = p->pc; */
			for(a = p->to.autom; a != nil; a = a->link){
				if(a->type == D_FILE || a->type == D_FILE1)
					dohist(a);
			}
			lputl(SINDEX(s));
			hputl(0);
			nl++;
			continue;
		}
		if(p->line == 0 || p->line == olc || p->as == ANOP)
			continue;
		lputl(p->pc);
		hputl(lineno(p->line));
		nl++;
		olc = p->line;
	}
	if(nl != nlc)
		diag("bad line count in cofflc()");
	nlc = nl;
}

static void
cofflcsz(void)
{
	long olc, nl;
	Prog *p;

	nl = 0;
	olc = 0;
	for(p = firstp; p != P; p = p->link){
		if(p->as == ATEXT){
			LINDEX(p->from.sym) = nl;
			nl++;
			continue;
		}
		if(p->line == 0 || p->line == olc || p->as == ANOP)
			continue;
		nl++;
		olc = p->line;
	}
	nlc = nl;
}
