#include "cc.h"

#define INCREMENT 	8
#define DEVNULL	"/dev/null"

static int indent = 0;
static int fd = -1;
static int nf = 0;
static int mylineno = 1;

typedef struct Com{
	int lno;
	char *s;
	Node *n;
	int tba;
	struct Com *nxt;
} Com;

Com *hdc, *curc;

typedef struct File{
	char *s;
	char *f;
	char *m;
	int b;
	int loc;
	int in;
	int tg;
	Node *n;
	Com *c;
	struct File *nxt;
} File;

typedef struct Create{
	char *s;
	struct Create *nxt;
} Create;

File *fs;
Create *cs;

static void genmsg(void);
static int isloc(void);

static void
addcreate(char *s)
{
	Create *c;

	if(strcmp(s, DEVNULL) == 0)
		return;
	c = (Create*)malloc(sizeof(Create));
	c->s = malloc(strlen(s)+1);
	strcpy(c->s, s);
	c->nxt = cs;
	cs = c;
}

static int
created(char *s)
{
	Create *c;

	for(c = cs; c != nil; c = c->nxt)
		if(strcmp(s, c->s) == 0)
			return 1;
	return 0;
}

int
dolog(void)
{
	if(justcode)
		return 0;
	return domod || !doinc || inmain;
}

static char*
curf(void)
{
	File *f;

	for(f = fs; f != nil; f = f->nxt)
		if(f->f != nil)
			return f->s;
	return nil;
}

static char*
curm(void)
{
	File *f;

	for(f = fs; f != nil; f = f->nxt)
		if(f->f != nil)
			return f->m;
	return nil;
}

void
setmod(Sym *s)
{
	if(domod && s->mod == nil && ism() && !(doloc && !isloc()))
		s->mod = curm();
}

char *
outmod(char *buf, int up)
{
	char *s, *t;

	s = curf();
	if(s == nil)
		return "";
	t = strchr(s, '.');
	if(t != nil)
		*t = '\0';
	strcpy(buf, s);
	if(t != nil)
		*t = '.';
	if(up == 1 || (up < 0 && ism()))
		buf[0] = toupper(buf[0]);
	return buf;
}

int
ism(void)
{
	return !isb();
}

int
isb(void)
{
	File *f;

	for(f = fs; f != nil; f = f->nxt)
		if(f->f != nil)
			return f->b;
	return 0;
}

static int
isloc(void)
{
	File *f;

	for(f = fs; f != nil; f = f->nxt)
		if(f->f != nil)
			return f->loc;
	return 0;
}
 
static File*
pushf(void)
{
	static File zfile;
	File *f;

	f = (File*)malloc(sizeof(File));
	*f = zfile;
	f->s = nil;
	f->f = nil;
	f->m = nil;
	f->nxt = fs;
	fs = f;
	return f;
}

static void
popf(void)
{
	File *f;

	f = fs;
	fs = fs->nxt;
	if(f->s != nil)
		free(f->s);
	free(f);
}

static void
setf(File *f, char *s)
{
	int n;
	char *t;

	if(s != nil){
		t = strrchr(s, '/');
		f->loc = t == nil;
		if(t != nil)
			s = t+1;
		n = strlen(s);
		f->s = malloc(n+1);
		strcpy(f->s, s);
		s = f->s;
		if(n > 2 && s[n-2] == '.'){
			f->m = malloc(n-1);
			strncpy(f->m, s, n-2);
			if(s[n-1] == 'h')
				s[n-1] = 'm';
			else if(s[n-1] == 'c'){
				s[n-1] = 'b';
				f->b = 1;
			}
			else
				s = nil;
		}
		else
			s = nil;
		if(s == nil){
			free(f->s);
			if(f->m != nil)
				free(f->m);
			f->s = nil;
			f->m = nil;
		}
	}
	f->f = f->s;
	if(f->s != nil && nf > 0){
		if(doinc || doloc && !f->loc)
			f->f = DEVNULL;
		else if(!domod)
			f->f = nil;
	}	
}

void
outpush0(char *s, Node *n)
{
	File *f;

	f = pushf();
	setf(f, s);
	if(f->f != nil){
		nf++;
		f->tg = taggen;
		taggen = 0;
		f->n = n;
		f->c = hdc;
		hdc = nil;
	}	
}

void
outpop0(int lno)
{
	File *f;

	USED(lno);
	f = fs;
	if(f->f != nil){
		nf--;
		taggen = f->tg;
		f->n->left = (void*)hdc;
		hdc = f->c;
	}
	popf();
}

void
outpush2(char *s, Node *n)
{
	File *f;

	f = pushf();
	setf(f, s);
	if(f->f != nil){
		if(fd >= 0){
			newsec(0);
			close(fd);
			close(1);
			fd = -1;
		}
		if(created(f->f))
			f->f = DEVNULL;	/* don't overwrite original if included again */
		fd = create(f->f, OWRITE, 0664);
		if(fd >= 0)
			addcreate(f->f);
		mydup(fd, 1);
		nf++;
		f->tg = taggen;
		taggen = 0;
		f->c = hdc;
		if(n != Z)
			hdc = (void*)n->left;
		else
			hdc = nil;
		f->in = indent;
		indent = 0;
		genmsg();
		pgen(f->b);
	}	
}

void
outpop2(int lno)
{
	File *f, *g;

	f = fs;
	if(f->f != nil){
		if(fd >= 0){
			newsec(0);
			output(lno, 1);
			epgen(f->b);
			close(fd);
			close(1);
			fd = -1;
		}
		for(g = fs->nxt; g != nil; g = g->nxt){
			if(g->f != nil){
				fd = open(g->f, OWRITE);
				seek(fd, 0, 2);
				mydup(fd, 1);
				break;
			}
		}
		nf--;
		taggen = f->tg;
		hdc = f->c;
		indent = f->in;
	}
	popf();
}

static void
xprint(char *s)
{
	if(nerrors == 0)
		print(s);
}

static int tot = 0;

static void
doindent(int d)
{
	int i;

	for(i = 0; i < d/8; i++)
		xprint("\t");
	for(i = 0; i < d%8; i++)
		xprint(" ");
}

void
incind(void)
{
	indent += INCREMENT;
}

void 
decind(void)
{
	indent -= INCREMENT;
}

int
zeroind(void)
{
	int i = indent;

	indent = 0;
	return i;
}

void
restoreind(int i)
{
	indent = i;
}

void
newline0(void)
{
	xprint("\n");
	tot = 0;
	mylineno++;
}

void
newline(void)
{
	if(!outcom(1)){
		xprint("\n");
		mylineno++;
	}
	tot = 0;
}

static void 
lprint(char *s)
{
	if(tot == 0) {
		doindent(indent);
		tot += indent;
	}
	xprint(s);
	tot += strlen(s);
}

void
prline(char *s)
{
	xprint(s);
	xprint("\n");
	mylineno++;
}

void 
prdelim(char *s)
{
	if(*s == '%'){
		if(*++s == '=')
			lprint("%%=");
		else
			lprint("%%");
		return;
	}
	lprint(s);
}

void 
prkeywd(char *kw)
{
	lprint(kw);
}

void
prid(char *s)
{
	lprint(s);
}

static void
priddol(char *s, int dol)
{
	char *t;
	char buf[128];

	if(dol){
		t = strchr(s, '$');
		if(t != nil)
			*t = '_';
		lprint(s);
		if(t != nil){
			strcpy(buf, s);
			while(slookup(buf)->type != T){
				strcat(buf, "x");
				lprint("x");
			}
			*t = '$';
		}
	}
	else
		lprint(s);
}

void
prsym(Sym *s, int mod)
{
	char buf[128];
	int c;

	if(mod && s->mod && strcmp(s->mod, curm()) != 0 && (!s->limbo || s->class == CEXTERN)){
		c = isconsym(s);
		if(c >= 0){
			if(c){
				s->mod[0] = toupper(s->mod[0]);
				lprint(s->mod);
				s->mod[0] = tolower(s->mod[0]);
			}
			else
				lprint(s->mod);
			lprint("->");
			usemod(s, !c);
		}
	}
	if(s->lname)
		prid(s->lname);
	else{
		priddol(s->name, s->class == CSTATIC);
		if(s->lkw){
			strcpy(buf, s->name);
			for(;;){
				strcat(buf, "x");
				lprint("x");
				s = slookup(buf);
				if(s->type == T)
					break;
			}
		}
	}
}

int
arrow(Sym *s)
{
	if(s->mod && strcmp(s->mod, curm()) != 0)
		return isconsym(s) >= 0;
	return 0;
}

void
prsym0(Sym *s)
{
	int c;

	if(s->mod && strcmp(s->mod, curm()) != 0){
		c = isconsym(s);
		if(c >= 0)
			usemod(s, !c);
	}
}

static int
isprintable(int c)
{
	if(c >= 0x20 && c <= 0x7e)
		return 1;
	return c == '\0' || c == '\n' || c == '\t' || c == '\b' || c == '\r' || c == '\f' || c == '\a' || c == '\v';
}

static int
hex(int c)
{
	if(c < 10)
		return c+'0';
	return c+'a'-10;
}

void
prchar0(vlong x, int quote)
{
	int c, e, i = 0;
	static char buf[16];

	if(quote)
		buf[i++] = '\'';
	c = x;
	if(c < 0 || c > 255 || !isprintable(c)){
		if(c&0xffff0000)
			diag(Z, "character too big");
		buf[i++] = '\\';
		buf[i++] = 'u';
		buf[i++] = hex((c>>12)&0xf);
		buf[i++] = hex((c>>8)&0xf);
		buf[i++] = hex((c>>4)&0xf);
		buf[i++] = hex((c>>0)&0xf);
	}
	else{
		e = 0;
		switch(c){
			case '\n':	e = 'n'; break;
			case '\t':	e = 't'; break;
			case '\b':	e = 'b'; break;
			case '\r':	e = 'r'; break;
			case '\f':	e = 'f'; break;
			case '\a':	e = 'a'; break;
			case '\v':	e = 'v'; break;
			case '"':	if(!quote) e = '"'; break;
			case '\'':	if(quote) e = '\''; break;
			case '\\':	e = '\\'; break;
			case '%':	buf[i++] = c; break;
			case 0:	e = '0'; if(strings) prcom("nul byte in string ?", Z); break;
		}
		if(e != 0){
			buf[i++] = '\\';
			c = e;
		}
		buf[i++] = c;
	}
	if(quote)
		buf[i++] = '\'';
	buf[i] = '\0';
	lprint(buf);
}

void
prchar(vlong x)
{
	prchar0(x, 1);
}

void
prstr(char *s)
{
	uchar *t;
	Rune r;

	t = (uchar*)s;
	lprint("\"");
	while(*t != 0){
		if(*t & 0x80){
			t += chartorune(&r, (char*)t);
			prchar0(r, 0);
		}
		else
			prchar0(*t++, 0);
	}
	lprint("\"");
}

void
prlstr(Rune *s)
{
	lprint("\"");
	while(*s != 0)
		prchar0(*s++, 0);
	lprint("\"");
}

void
prreal(double x, char *s, int b)
{
	static char buf[128];

	if(b != KDEC)
		diag(Z, "not base 10 in prreal");
	if(s != nil)
		lprint(s);
	else{
		sprint(buf, "%f", x);
		lprint(buf);
	}
}

void
prnum(vlong x, int b, Type *t)
{
	static char buf[128];
	int w;
	vlong m;

	w = 4;
	if(t != T)
		w = ewidth[t->etype];
	m = MASK(8*w);
	if(b == KHEX)
		sprint(buf, "16r%llux", x&m);
	else if(b == KOCT)
		sprint(buf, "8r%lluo", x&m);
	else
		sprint(buf, "%lld", x);
	lprint(buf);
}

char *cb;
int cn, csz;

static void
outcom0(Com *c)
{
	Node *n;
	char *s, *t, *u;

	s = c->s;
	n = c->n;
	if(comm && c->tba){
		t = strchr(s, '\n');
		*t = '\0';
		fprint(2, "%s:%d: %s", curf(), mylineno, s);
		*t = '\n';
		if(n != Z){
			mydup(2, 1);
			expgen(n);
			mydup(fd, 1);
		}
		fprint(2, "\n");
	}
	while(*s != '\0'){
		t = strchr(s, '\n');
		*t = '\0';
		if(tot != 0)
			prdelim("\t");
		prdelim("# ");
		while((u = strchr(s, '%')) != nil){
			/* do not let print interpret % ! */
			*u = 0;
			lprint(s);
			*u = '%';
			lprint("%%");
			s = u+1;
		}
		lprint(s);
		if(n == Z)
			newline0();
		*t = '\n';
		s = t+1;
	}
	if(n != Z){
		expgen(n);
		newline0();
	}
}

int
outcom(int f)
{
	int lno, nl;
	Com *c;

	nl = 0;
	lno = pline+f;
	c = hdc;
	while(c != nil && c->lno < lno){
/* print("outcom: %d < %d (f=%d)\n", c->lno, lno, f); */
		nl = 1;
		outcom0(c);
		hdc = hdc->nxt;
		free(c->s);
		free(c);
		c = hdc;
	}
	return nl;
}

void
startcom(int lno)
{
	Com *c, **ac;

	c = (Com *)malloc(sizeof(Com));
	c->lno = lno;
	c->s = nil;
	c->n = Z;
	c->tba = 0;
	c->nxt = nil;
	for(ac = &hdc; *ac != nil && (*ac)->lno <= lno; ac = &(*ac)->nxt)
		;
	c->nxt = *ac;
	curc = *ac = c;
}

void
addcom(int rr)
{
	int i, nb;
	char *ncb;
	char s[UTFmax];
	Rune r[1];

	if(rr >= Runeself){
		r[0] = rr;
		nb = runetochar(s, r);
	}
	else{
		nb = 1;
		s[0] = rr;
	}
	if(cn+nb-1 >= csz){
		csz += 32;
		ncb = malloc(csz);
		memcpy(ncb, cb, cn);
		free(cb);
		cb = ncb;
	}
	for(i = 0; i < nb; i++)
		cb[cn++] = s[i];
}

void
endcom(void)
{
	char *s;

	addcom('\n');
	addcom('\0');
	s = malloc(strlen(cb)+1);
	strcpy(s, cb);
	curc->s = s;
/* print("com %d %s\n", curc->lno, s); */
	cn = 0;
}

void
linit()
{
	csz = 32;
	cb = malloc(csz);
	sysinit();
}

static void
genmsg(void)
{
	prline("#");
	prline("#	initially generated by c2l");
	prline("#");
	prline("");
}

void
prcom(char *s, Node *n)
{
	Com *c;

	startcom(pline);
	c = curc;
	sprint(cb, "TBA %s", s);
	cn = strlen(cb);
	c->n = n;
	c->tba = 1;
	endcom();
}

void
output(long lno, int com)
{
/* print("output(%ld)\n", lno); */
	pline = lno;
	if(com)
		outcom(0);
}

int
exists(char *f)
{
	int fd;

	fd = open(f, OREAD);
	close(fd);
	return fd >= 0;
}
