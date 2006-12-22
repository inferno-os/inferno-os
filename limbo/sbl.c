#include "limbo.h"

static char sbltname[Tend] =
{
	/* Tnone */	'n',
	/* Tadt */	'a',
	/* Tadtpick */	'a',
	/* Tarray */	'A',
	/* Tbig */	'B',
	/* Tbyte */	'b',
	/* Tchan */	'C',
	/* Treal */	'f',
	/* Tfn */	'F',
	/* Tint */	'i',
	/* Tlist */	'L',
	/* Tmodule */	'm',
	/* Tref */	'R',
	/* Tstring */	's',
	/* Ttuple */	't',
	/* Texception */	't',
	/* Tfix */	'i',
	/* Tpoly */	'P',

	/* Tainit */	'?',
	/* Talt */	'?',
	/* Tany */	'N',
	/* Tarrow */	'?',
	/* Tcase */	'?',
	/* Tcasel */	'?',
	/* Tcasec */	'?',
	/* Tdot */	'?',
	/* Terror */	'?',
	/* Tgoto */	'?',
	/* Tid */	'?',
	/* Tiface */	'?',
	/* Texcept */	'?',
	/* Tinst */	'?',
};
int	sbltadtpick = 'p';

static	Sym	*sfiles;
static	Sym	*ftail;
static	int	nsfiles;
static	int	blockid;
static	int	lastf;
static	int	lastline;

static	void	sbltype(Type*, int);
static	void	sbldecl(Decl*, int);
static	void	sblftype(Type*);
static	void	sblfdecl(Decl*, int);

void
sblmod(Decl *m)
{
	Bprint(bsym, "limbo .sbl 2.1\n");
	Bprint(bsym, "%s\n", m->sym->name);

	blockid = 0;
	nsfiles = 0;
	sfiles = ftail = nil;
	lastf = 0;
	lastline = 0;
}

static int
sblfile(char *name)
{
	Sym *s;
	int i;

	i = 0;
	for(s = sfiles; s != nil; s = s->next){
		if(strcmp(s->name, name) == 0)
			return i;
		i++;
	}
	s = allocmem(sizeof(Sym));
	s->name = name;
	s->next = nil;
	if(sfiles == nil)
		sfiles = s;
	else
		ftail->next = s;
	ftail = s;
	nsfiles = i + 1;
	return i;
}

static char *
filename(char *s)
{
	char *t;

	t = strrchr(s, '/');
	if(t != nil)
		s = t + 1;
	t = strrchr(s, '\\');
	if(t != nil)
		s = t+1;
	t = strrchr(s, ' ');
	if(t != nil)
		s = t + 1;
	return s;
}

void
sblfiles(void)
{
	Sym *s;
	int i;

	for(i = 0; i < nfiles; i++)
		files[i]->sbl = sblfile(files[i]->name);
	Bprint(bsym, "%d\n", nsfiles);
	for(s = sfiles; s != nil; s = s->next)
		Bprint(bsym, "%s\n", filename(s->name));
}

static char*
sblsrcconv(char *buf, char *end, Src *src)
{
	Fline fl;
	File *startf, *stopf;
	char *s;
	int startl, stopl;

	s = buf;

	fl = fline(src->start.line);
	startf = fl.file;
	startl = fl.line;
	fl = fline(src->stop.line);
	stopf = fl.file;
	stopl = fl.line;
	if(lastf != startf->sbl)
		s = seprint(s, end, "%d:", startf->sbl);
	if(lastline != startl)
		s = seprint(s, end, "%d.", startl);
	s = seprint(s, end, "%d,", src->start.pos);
	if(startf->sbl != stopf->sbl)
		s = seprint(s, end, "%d:", stopf->sbl);
	if(startl != stopl)
		s = seprint(s, end, "%d.", stopl);
	seprint(s, end, "%d ", src->stop.pos);
	lastf = stopf->sbl;
	lastline = stopl;
	return buf;
}

#define isnilsrc(s)	((s)->start.line == 0 && (s)->stop.line == 0 && (s)->start.pos == 0 && (s)->stop.pos == 0)
#define isnilstopsrc(s)	((s)->stop.line == 0 && (s)->stop.pos == 0)

void
sblinst(Inst *inst, long ninst)
{
	Inst *in;
	char buf[StrSize];
	int *sblblocks, i, b;
	Src src;

	Bprint(bsym, "%ld\n", ninst);
	sblblocks = allocmem(nblocks * sizeof *sblblocks);
	for(i = 0; i < nblocks; i++)
		sblblocks[i] = -1;
	for(in = inst; in != nil; in = in->next){
		if(in->op == INOOP)
			continue;
		if(in->src.start.line < 0)
			fatal("no file specified for %I", in);
		b = sblblocks[in->block];
		if(b < 0)
			sblblocks[in->block] = b = blockid++;
		if(isnilsrc(&in->src))
			in->src = src;
		else if(isnilstopsrc(&in->src)){	/* how does this happen ? */
			in->src.stop = in->src.start;
			in->src.stop.pos++;
		}
		Bprint(bsym, "%s%d\n", sblsrcconv(buf, buf+sizeof(buf), &in->src), b);
		src = in->src;
	}
	free(sblblocks);
}

void
sblty(Decl **tys, int ntys)
{
	Decl *d;
	int i;

	Bprint(bsym, "%d\n", ntys);
	for(i = 0; i < ntys; i++){
		d = tys[i];
		d->ty->sbl = i;
	}
	for(i = 0; i < ntys; i++){
		d = tys[i];
		sbltype(d->ty, 1);
	}
}

void
sblfn(Decl **fns, int nfns)
{
	Decl *f;
	int i;

	Bprint(bsym, "%d\n", nfns);
	for(i = 0; i < nfns; i++){
		f = fns[i];
		if(ispoly(f))
			rmfnptrs(f);
		if(f->dot != nil && f->dot->ty->kind == Tadt)
			Bprint(bsym, "%ld:%s.%s\n", f->pc->pc, f->dot->sym->name, f->sym->name);
		else
			Bprint(bsym, "%ld:%s\n", f->pc->pc, f->sym->name);
		sbldecl(f->ty->ids, Darg);
		sbldecl(f->locals, Dlocal);
		sbltype(f->ty->tof, 0);
	}
}

void
sblvar(Decl *vars)
{
	sbldecl(vars, Dglobal);
}

static int
isvis(Decl *id)
{
	if(!tattr[id->ty->kind].vis
	|| id->sym == nil
	|| id->sym->name == nil		/*????*/
	|| id->sym->name[0] == '.')
		return 0;
	if(id->ty == tstring && id->init != nil && id->init->op == Oconst)
		return 0;
	if(id->src.start.line < 0 || id->src.stop.line < 0)
		return 0;
	return 1;
}

static void
sbldecl(Decl *ids, int store)
{
	Decl *id;
	char buf[StrSize];
	int n;

	n = 0;
	for(id = ids; id != nil; id = id->next){
		if(id->store != store || !isvis(id))
			continue;
		n++;
	}
	Bprint(bsym, "%d\n", n);
	for(id = ids; id != nil; id = id->next){
		if(id->store != store || !isvis(id))
			continue;
		Bprint(bsym, "%ld:%s:%s", id->offset, id->sym->name, sblsrcconv(buf, buf+sizeof(buf), &id->src));
		sbltype(id->ty, 0);
		Bprint(bsym, "\n");
	}
}

static void
sbltype(Type *t, int force)
{
	Type *lastt;
	Decl *tg, *d;
	char buf[StrSize];

	if(t->kind == Tadtpick)
		t = t->decl->dot->ty;

	d = t->decl;
	if(!force && d != nil && d->ty->sbl >= 0){
		Bprint(bsym, "@%d\n", d->ty->sbl);
		return;
	}

	switch(t->kind){
	default:
		fatal("bad type %T in sbltype", t);
		break;
	case Tnone:
	case Tany:
	case Tint:
	case Tbig:
	case Tbyte:
	case Treal:
	case Tstring:
	case Tfix:
	case Tpoly:
		Bprint(bsym, "%c", sbltname[t->kind]);
		break;
	case Tfn:
		Bprint(bsym, "%c", sbltname[t->kind]);
		sbldecl(t->ids, Darg);
		sbltype(t->tof, 0);
		break;
	case Tarray:
	case Tlist:
	case Tchan:
	case Tref:
		Bprint(bsym, "%c", sbltname[t->kind]);
		if(t->kind == Tref && t->tof->kind == Tfn){
			tattr[Tany].vis = 1;
			sbltype(tfnptr, 0);
			tattr[Tany].vis = 0;
		}
		else
			sbltype(t->tof, 0);
		break;
	case Ttuple:
	case Texception:
		Bprint(bsym, "%c%d.", sbltname[t->kind], t->size);
		sbldecl(t->ids, Dfield);
		break;
	case Tadt:
		if(t->tags != nil)
			Bputc(bsym, sbltadtpick);
		else
			Bputc(bsym, sbltname[t->kind]);
		if(d->dot != nil && !isimpmod(d->dot->sym))
			Bprint(bsym, "%s->", d->dot->sym->name);
		Bprint(bsym, "%s %s%d\n", d->sym->name, sblsrcconv(buf, buf+sizeof(buf), &d->src), d->ty->size);
		sbldecl(t->ids, Dfield);
		if(t->tags != nil){
			Bprint(bsym, "%d\n", t->decl->tag);
			lastt = nil;
			for(tg = t->tags; tg != nil; tg = tg->next){
				Bprint(bsym, "%s:%s", tg->sym->name, sblsrcconv(buf, buf+sizeof(buf), &tg->src));
				if(lastt == tg->ty){
					Bputc(bsym, '\n');
				}else{
					Bprint(bsym, "%d\n", tg->ty->size);
					sbldecl(tg->ty->ids, Dfield);
				}
				lastt = tg->ty;
			}
		}
		break;
	case Tmodule:
		Bprint(bsym, "%c%s\n%s", sbltname[t->kind], d->sym->name, sblsrcconv(buf, buf+sizeof(buf), &d->src));
		sbldecl(t->ids, Dglobal);
		break;
	}
}
