#include	"auxi.h"

Prog *firstp, *textp, *curtext, *lastp, *etextp;
Symx *hash[NHASH];
Auto *lasta;
long autosize;
int version = 0;

static int
private(char *s)
{
	return strcmp(s, "safe") == 0 || strcmp(s, "ret") == 0 || strcmp(s, "string") == 0;
}

static int
zlen(char *s)
{
	int i;

	for(i=1; s[i] != 0 || s[i+1] != 0; i += 2)
		;
	i++;
	return i+1;
}

static Symx*
allocsym(char *symb, int l, int v)
{
	Symx *s;

	s = malloc(sizeof(Symx));
	s->name = malloc(l);
	memmove(s->name, symb, l);
	s->name[l-1] = '\0';
	s->type = 0;
	s->version = v;
	s->value = 0;
	s->link = nil;
	return s;
}

Symx*
lookupsym(char *symb, int v)
{
	Symx *s, **as;
	char *p;
	long h;
	int c, l;

	h = v;
	for(p=symb; c = *p; p++)
		h = h+h+h + c;
	l = (p - symb) + 1;
	if(h < 0)
		h = ~h;
	h %= NHASH;
	for(s = hash[h]; s != nil; s = s->link)
		if(s->version == v)
		if(memcmp(s->name, symb, l) == 0)
			return s;
	s = allocsym(symb, l, v);
	for(as = &hash[h]; *as != nil; as = &((*as)->link))
		;
	*as = s;
	// s->link = hash[h];
	// hash[h] = s;
	return s;
}

static void
addauto(Auto **aut, Symx *s, int t, long v)
{
	Auto *a, **aa;

	a = (Auto*)malloc(sizeof(Auto));
	a->asym = s;
	a->link = nil;
	a->aoffset = v;
	a->type = t;
	for(aa = aut; *aa != nil; aa = &((*aa)->link))
		;
	*aa = a;
}

static Prog*
newprog(int as, long pc, long ln)
{
	Prog *p;

	p = (Prog *)malloc(sizeof(Prog));
	p->as = as;
	p->pc = pc;
	p->line = ln;
	p->link = p->cond = P;
	if(firstp == P)
		firstp = p;
	else
		lastp->link = p;
	lastp = p;
	if(as == ATEXT){
		if(textp == P)
			textp = p;
		else
			etextp->cond = p;
		etextp = p;	
	}
	return p;
}

static int
line(long pc)
{
	char buf[1024], *s;

	// return pc2line(pc);
	if(fileline(buf, sizeof(buf), pc)){
		for(s = buf; *s != ':' && *s != '\0'; s++)
			;
		if(*s != ':')
			return -1;
		return atoi(s+1);
	}
	return -1;
}

static void
lines(long v)
{
	long ll, nl, pc;
	if(etextp != P){
		ll = 0;
		for(pc = etextp->pc; pc < v; pc += 4){
			nl = line(pc);
			if(nl != -1 && nl != ll){
				newprog(ATEXT-1, pc, nl);
				ll = nl;
			}
		}
		pc -= 4;
		if(lastp->pc != pc){
			nl = line(pc);
			if(nl != -1)
				newprog(ATEXT-1, pc, nl);
		}
	}
}

void
beginsym(void)
{
}

/* create the same structures as in 5l so we can use same coff.c source file */
void
newsym(int i, char *nm, long v, int t)
{
	long l, ver;
	char *os;
	Symx *s;
	Prog *p;

	if(i == 0 && (t == 't' || t == 'T') && strcmp(nm, "etext") == 0)
		return;
	if(nm[0] == '.' && private(nm+1))
		return;
// print("%s %ld %c\n", nm, v, t);
	ver = 0;
	if(t == 't' || t == 'l' || t == 'd' || t == 'b'){
		ver = ++version;
		if(ver == 0)
			diag("0 version for static");
	}
	if(t == 'a' || t == 'p')
		s = allocsym(nm, strlen(nm)+1, 0);
	else if(t == 'z' || t == 'Z')
		s = allocsym(nm, zlen(nm), 0);
	else if(t != 'm'){
		s = lookupsym(nm, ver);
		if(s->type != 0)
			diag("seen sym before in newsym");
		s->value = v;
	}
	else
		s = nil;
	switch(t){
	case 'T':
	case 'L':
	case 't':
	case 'l':
		lines(v);
		if(t == 'l' || t == 'L')
			s->type = SLEAF;
		else
			s->type = STEXT;
		p = newprog(ATEXT, v, line(v));
		p->from.sym = s;
		p->to.autom = lasta;
		lasta = nil;
		break;
	case 'D':
	case 'd':
		s->type = SDATA;
		s->value -= INITDAT;
		break;
	case 'B':
	case 'b':
		s->type = SBSS;
		s->value -= INITDAT;
		break;
	case 'f':
		// version++;
		s->type = SFILE;
		os = s->name;
		l = strlen(os)+1;
		s->name = malloc(l+1);
		s->name[0] = '>';
		memmove(s->name+1, os, l);
		free(os);
		break;
/*
	case 'f'+'a'-'A':
		s->type = SFILE;
		break;
*/
	case 'z':
		addauto(&lasta, s, D_FILE, v);
		break;
	case 'Z':
		addauto(&lasta, s, D_FILE1, v);
		break;
	case 'a':
		addauto(&(etextp->to.autom), s, D_AUTO, -v);
		break;
	case 'p':
		addauto(&(etextp->to.autom), s, D_PARAM, v);
		break;
	case 'm':
		etextp->to.offset = v-4;
		autosize = v;
		break;
	default:
		diag("bad case in newsym");
		break;
	}
}

void
endsym(void)
{
	lines(INITTEXT+textsize);
}
