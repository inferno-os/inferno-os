#include "limbo.h"

static long	stubalign(long offset, int a, char** b, char *e);
static void		pickadtstub(Type *t);

void
emit(Decl *globals)
{
	Decl *m, *d, *id;

	for(m = globals; m != nil; m = m->next){
		if(m->store != Dtype || m->ty->kind != Tmodule)
			continue;
		m->ty = usetype(m->ty);
		for(d = m->ty->ids; d != nil; d = d->next){
			d->ty = usetype(d->ty);
			if(d->store == Dglobal || d->store == Dfn)
				modrefable(d->ty);
			if(d->store == Dtype && d->ty->kind == Tadt){
				for(id = d->ty->ids; id != nil; id = id->next){
					id->ty = usetype(id->ty);
					modrefable(d->ty);
				}
			}
		}
	}
	if(emitstub){
		print("#pragma hjdicks x4\n");
		print("#pragma pack x4\n");
		adtstub(globals);
		modstub(globals);
		print("#pragma pack off\n");
		print("#pragma hjdicks off\n");
	}
	if(emittab != nil)
		modtab(globals);
	if(emitcode)
		modcode(globals);
}

static char*
lowercase(char *f)
{
	char *s = f;

	for( ; *s != 0; s++)
		if(*s >= 'A' && *s <= 'Z')
			*s += 'a' - 'A';
	return f;
}

void
modcode(Decl *globals)
{
	Decl *d, *id;
	char buf[32];

	if(emitdyn){
		strcpy(buf, emitcode);
		lowercase(buf);
		print("#include \"%s.h\"\n", buf);
	}
	else{
		print("#include <lib9.h>\n");
		print("#include <isa.h>\n");
		print("#include <interp.h>\n");
		print("#include \"%smod.h\"\n", emitcode);
	}
	print("\n");

	for(d = globals; d != nil; d = d->next)
		if(d->store == Dtype && d->ty->kind == Tmodule && strcmp(d->sym->name, emitcode) == 0)
			break;

	if(d == nil)
		return;
	
	/*
	 * stub types
	 */
	for(id = d->ty->ids; id != nil; id = id->next){
		if(id->store == Dtype && id->ty->kind == Tadt){
			id->ty = usetype(id->ty);
			print("Type*\tT_%s;\n", id->sym->name);
		}
	}

	/*
	 * type maps
	 */
	if(emitdyn){
		for(id = d->ty->ids; id != nil; id = id->next)
			if(id->store == Dtype && id->ty->kind == Tadt)
				print("uchar %s_map[] = %s_%s_map;\n",
					id->sym->name, emitcode, id->sym->name);
	}
	
	/*
	  * heap allocation and garbage collection for a type
	 */
	if(emitdyn){
		for(id = d->ty->ids; id != nil; id = id->next)
			if(id->store == Dtype && id->ty->kind == Tadt){
				print("\n%s_%s*\n%salloc%s(void)\n{\n\tHeap *h;\n\n\th = heap(T_%s);\n\treturn H2D(%s_%s*, h);\n}\n", emitcode, id->sym->name, emitcode, id->sym->name, id->sym->name, emitcode, id->sym->name);
				print("\nvoid\n%sfree%s(Heap *h, int swept)\n{\n\t%s_%s *d;\n\n\td = H2D(%s_%s*, h);\n\tfreeheap(h, swept);\n}\n", emitcode, id->sym->name, emitcode, id->sym->name, emitcode, id->sym->name);
			}
	}

	/*
	 * initialization function
	 */
	if(emitdyn)
		print("\nvoid\n%sinit(void)\n{\n", emitcode);
	else{
		print("\nvoid\n%smodinit(void)\n{\n", emitcode);
		print("\tbuiltinmod(\"$%s\", %smodtab);\n", emitcode, emitcode);
	}
	for(id = d->ty->ids; id != nil; id = id->next){
		if(id->store == Dtype && id->ty->kind == Tadt){
			if(emitdyn)
				print("\tT_%s = dtype(%sfree%s, %s_%s_size, %s_map, sizeof(%s_map));\n",
					id->sym->name, emitcode, id->sym->name, emitcode, id->sym->name, id->sym->name, id->sym->name);
			else
				print("\tT_%s = dtype(freeheap, sizeof(%s), %smap, sizeof(%smap));\n",
					id->sym->name, id->sym->name, id->sym->name, id->sym->name);
		}
	}
	print("}\n");

	/*
	 * end function
	 */
	if(emitdyn){
		print("\nvoid\n%send(void)\n{\n", emitcode);
		for(id = d->ty->ids; id != nil; id = id->next)
			if(id->store == Dtype && id->ty->kind == Tadt)
				print("\tfreetype(T_%s);\n", id->sym->name);
		print("}\n");
	}

	/*
	 * stub functions
	 */
	for(id = d->ty->tof->ids; id != nil; id = id->next){
		print("\nvoid\n%s_%s(void *fp)\n{\n\tF_%s_%s *f = fp;\n",
			id->dot->sym->name, id->sym->name,
			id->dot->sym->name, id->sym->name);
		if(id->ty->tof != tnone && tattr[id->ty->tof->kind].isptr)
			print("\n\tdestroy(*f->ret);\n\t*f->ret = H;\n");
		print("}\n");
	}

	if(emitdyn)
		print("\n#include \"%smod.h\"\n", buf);
}

void
modtab(Decl *globals)
{
	int n;
	Desc *md;
	Decl *d, *id;

	print("typedef struct{char *name; long sig; void (*fn)(void*); int size; int np; uchar map[16];} Runtab;\n");
	for(d = globals; d != nil; d = d->next){
		if(d->store == Dtype && d->ty->kind == Tmodule && strcmp(d->sym->name, emittab) == 0){
			n = 0;
			print("Runtab %smodtab[]={\n", d->sym->name);
			for(id = d->ty->tof->ids; id != nil; id = id->next){
				n++;
				print("\t\"");
				if(id->dot != d)
					print("%s.", id->dot->sym->name);
				print("%s\",0x%lux,%s_%s,", id->sym->name, sign(id),
					id->dot->sym->name, id->sym->name);
				if(id->ty->varargs)
					print("0,0,{0},");
				else{
					md = mkdesc(idoffsets(id->ty->ids, MaxTemp, MaxAlign), id->ty->ids);
					print("%ld,%ld,%M,", md->size, md->nmap, md);
				}
				print("\n");
			}
			print("\t0\n};\n");
			print("#define %smodlen	%d\n", d->sym->name, n);
		}
	}
}

/*
 * produce activation records for all the functions in modules
 */
void
modstub(Decl *globals)
{
	Type *t;
	Decl *d, *id, *m;
	char buf[StrSize*2], *p;
	long offset;
	int arg;

	for(d = globals; d != nil; d = d->next){
		if(d->store != Dtype || d->ty->kind != Tmodule)
			continue;
		arg = 0;
		for(id = d->ty->tof->ids; id != nil; id = id->next){
			if(emitdyn && id->dot->dot != nil)
				seprint(buf, buf+sizeof(buf), "%s_%s_%s", id->dot->dot->sym->name, id->dot->sym->name, id->sym->name);
			else
				seprint(buf, buf+sizeof(buf), "%s_%s", id->dot->sym->name, id->sym->name);
			print("void %s(void*);\ntypedef struct F_%s F_%s;\nstruct F_%s\n{\n",
				buf, buf, buf, buf);
			print("	WORD	regs[NREG-1];\n");
			if(id->ty->tof != tnone)
				print("	%R*	ret;\n", id->ty->tof);
			else
				print("	WORD	noret;\n");
			print("	uchar	temps[%d];\n", MaxTemp-NREG*IBY2WD);
			offset = MaxTemp;
			for(m = id->ty->ids; m != nil; m = m->next){
				if(m->sym != nil)
					p = m->sym->name;
				else{
					seprint(buf, buf+sizeof(buf), "arg%d", arg);
					p = buf;
				}

				/*
				 * explicit pads for structure alignment
				 */
				t = m->ty;
				offset = stubalign(offset, t->align, nil, nil);
				if(offset != m->offset)
					yyerror("module stub must not contain data objects");
					// fatal("modstub bad offset");
				print("	%R	%s;\n", t, p);
				arg++;
				offset += t->size;
			}
			if(id->ty->varargs)
				print("	WORD	vargs;\n");
			print("};\n");
		}
		for(id = d->ty->ids; id != nil; id = id->next)
			if(id->store == Dconst)
				constub(id);
	}
}

static void
chanstub(char *in, Decl *id)
{
	Desc *desc;

	print("typedef %R %s_%s;\n", id->ty->tof, in, id->sym->name);
	desc = mktdesc(id->ty->tof);
	print("#define %s_%s_size %ld\n", in, id->sym->name, desc->size);
	print("#define %s_%s_map %M\n", in, id->sym->name, desc);
}

/*
 * produce c structs for all adts
 */
void
adtstub(Decl *globals)
{
	Type *t, *tt;
	Desc *desc;
	Decl *m, *d, *id;
	char buf[2*StrSize];
	long offset;

	for(m = globals; m != nil; m = m->next){
		if(m->store != Dtype || m->ty->kind != Tmodule)
			continue;
		for(d = m->ty->ids; d != nil; d = d->next){
			if(d->store != Dtype)
				continue;
			t = usetype(d->ty);
			d->ty = t;
			dotprint(buf, buf+sizeof(buf), d->ty->decl, '_');
			switch(d->ty->kind){
			case Tadt:
				print("typedef struct %s %s;\n", buf, buf);
				break;
			case Tint:
			case Tbyte:
			case Treal:
			case Tbig:
			case Tfix:
				print("typedef %T %s;\n", t, buf);
				break;
			}
		}
	}
	for(m = globals; m != nil; m = m->next){
		if(m->store != Dtype || m->ty->kind != Tmodule)
			continue;
		for(d = m->ty->ids; d != nil; d = d->next){
			if(d->store != Dtype)
				continue;
			t = d->ty;
			if(t->kind == Tadt || t->kind == Ttuple && t->decl->sym != anontupsym){
				if(t->tags != nil){
					pickadtstub(t);
					continue;
				}
				dotprint(buf, buf+sizeof(buf), t->decl, '_');
				print("struct %s\n{\n", buf);
				offset = 0;
				for(id = t->ids; id != nil; id = id->next){
					if(id->store == Dfield){
						tt = id->ty;
						offset = stubalign(offset, tt->align, nil, nil);
						if(offset != id->offset)
							fatal("adtstub bad offset");
						print("	%R	%s;\n", tt, id->sym->name);
						offset += tt->size;
					}
				}
				if(t->ids == nil){
					print("	char	dummy[1];\n");
					offset = 1;
				}
				offset = stubalign(offset, t->align, nil ,nil);
				offset = stubalign(offset, IBY2WD, nil , nil);
				if(offset != t->size && t->ids != nil)
					fatal("adtstub: bad size");
				print("};\n");

				for(id = t->ids; id != nil; id = id->next)
					if(id->store == Dconst)
						constub(id);

				for(id = t->ids; id != nil; id = id->next)
					if(id->ty->kind == Tchan)
						chanstub(buf, id);

				desc = mktdesc(t);
				if(offset != desc->size && t->ids != nil)
					fatal("adtstub: bad desc size");
				print("#define %s_size %ld\n", buf, offset);
				print("#define %s_map %M\n", buf, desc);
if(0)
				print("struct %s_check {int s[2*(sizeof(%s)==%s_size)-1];};\n", buf, buf, buf);
			}else if(t->kind == Tchan)
				chanstub(m->sym->name, d);
		}
	}
}

/*
 * emit an expicit pad field for aligning emitted c structs
 * according to limbo's definition
 */
static long
stubalign(long offset, int a, char **buf, char *end)
{
	long x;

	x = offset & (a-1);
	if(x == 0)
		return offset;
	x = a - x;
	if(buf == nil)
		print("\tuchar\t_pad%ld[%ld];\n", offset, x);
	else
		*buf = seprint(*buf, end, "uchar\t_pad%ld[%ld]; ", offset, x);
	offset += x;
	if((offset & (a-1)) || x >= a)
		fatal("compiler stub misalign");
	return offset;
}

void
constub(Decl *id)
{
	char buf[StrSize*2];

	seprint(buf, buf+sizeof(buf), "%s_%s", id->dot->sym->name, id->sym->name);
	switch(id->ty->kind){
	case Tbyte:
		print("#define %s %d\n", buf, (int)id->init->val & 0xff);
		break;
	case Tint:
	case Tfix:
		print("#define %s %ld\n", buf, (long)id->init->val);
		break;
	case Tbig:
		print("#define %s %ld\n", buf, (long)id->init->val);
		break;
	case Treal:
		print("#define %s %g\n", buf, id->init->rval);
		break;
	case Tstring:
		print("#define %s \"%s\"\n", buf, id->init->decl->sym->name);
		break;
	}
}

int
mapconv(Fmt *f)
{
	Desc *d;
	char *s, *e, buf[1024];
	int i;

	d = va_arg(f->args, Desc*);
	e = buf+sizeof(buf);
	s = buf;
	s = secpy(s, e, "{");
	for(i = 0; i < d->nmap; i++)
		s = seprint(s, e, "0x%x,", d->map[i]);
	if(i == 0)
		s = seprint(s, e, "0");
	seprint(s, e, "}");
	return fmtstrcpy(f, buf);
}

char*
dotprint(char *buf, char *end, Decl *d, int dot)
{
	if(d->dot != nil){
		buf = dotprint(buf, end, d->dot, dot);
		if(buf < end)
			*buf++ = dot;
	}
	if(d->sym == nil)
		return buf;
	return seprint(buf, end, "%s", d->sym->name);
}

char *ckindname[Tend] =
{
	/* Tnone */	"void",
	/* Tadt */	"struct",
	/* Tadtpick */	"?adtpick?",
	/* Tarray */	"Array*",
	/* Tbig */	"LONG",
	/* Tbyte */	"BYTE",
	/* Tchan */	"Channel*",
	/* Treal */	"REAL",
	/* Tfn */	"?fn?",
	/* Tint */	"WORD",
	/* Tlist */	"List*",
	/* Tmodule */	"Modlink*",
	/* Tref */	"?ref?",
	/* Tstring */	"String*",
	/* Ttuple */	"?tuple?",
	/* Texception */	"?exception",
	/* Tfix */		"WORD",
	/* Tpoly */	"void*",

	/* Tainit */	"?ainit?",
	/* Talt */	"?alt?",
	/* Tany */	"void*",
	/* Tarrow */	"?arrow?",
	/* Tcase */	"?case?",
	/* Tcasel */	"?casel",
	/* Tcasec */	"?casec?",
	/* Tdot */	"?dot?",
	/* Terror */	"?error?",
	/* Tgoto */	"?goto?",
	/* Tid */	"?id?",
	/* Tiface */	"?iface?",
	/* Texcept */	"?except?",
	/* Tinst */	"?inst?",
};

char*
ctprint(char *buf, char *end, Type *t)
{
	Decl *id;
	Type *tt;
	long offset;

	if(t == nil)
		return secpy(buf, end, "void");
	switch(t->kind){
	case Tref:
		return seprint(buf, end, "%R*", t->tof);
	case Tarray:
	case Tlist:
	case Tint:
	case Tbig:
	case Tstring:
	case Treal:
	case Tbyte:
	case Tnone:
	case Tany:
	case Tchan:
	case Tmodule:
	case Tfix:
	case Tpoly:
		return seprint(buf, end, "%s", ckindname[t->kind]);
	case Tadtpick:
		return ctprint(buf, end, t->decl->dot->ty);
	case Tadt:
	case Ttuple:
		if(t->decl->sym != anontupsym)
			return dotprint(buf, end, t->decl, '_');
		offset = 0;
		buf = secpy(buf, end, "struct{ ");
		for(id = t->ids; id != nil; id = id->next){
			tt = id->ty;
			offset = stubalign(offset, tt->align, &buf, end);
			if(offset != id->offset)
				fatal("ctypeconv tuple bad offset");
			buf = seprint(buf, end, "%R %s; ", tt, id->sym->name);
			offset += tt->size;
		}
		offset = stubalign(offset, t->align, &buf, end);
		if(offset != t->size)
			fatal("ctypeconv tuple bad t=%T size=%ld offset=%ld", t, t->size, offset);
		return secpy(buf, end, "}");
	default:
		if(t->kind >= Tend)
			yyerror("no C equivalent for type %d", t->kind);
		else
			yyerror("no C equivalent for type %s", kindname[t->kind]);
		break;
	}
	return buf;
}

static void
pickadtstub(Type *t)
{
	Type *tt;
	Desc *desc;
	Decl *id, *tg;
	char buf[2*StrSize];
	int ok;
	long offset, tgoffset;

	dotprint(buf, buf+sizeof(buf), t->decl, '_');
	offset = 0;
	for(tg = t->tags; tg != nil; tg = tg->next)
		print("#define %s_%s %ld\n", buf, tg->sym->name, offset++);
	print("struct %s\n{\n", buf);
	print("	int	pick;\n");
	offset = IBY2WD;
	for(id = t->ids; id != nil; id = id->next){
		if(id->store == Dfield){
			tt = id->ty;
			offset = stubalign(offset, tt->align, nil, nil);
			if(offset != id->offset)
				fatal("pickadtstub bad offset");
			print("	%R	%s;\n", tt, id->sym->name);
			offset += tt->size;
		}
	}
	print("	union{\n");
	for(tg = t->tags; tg != nil; tg = tg->next){
		tgoffset = offset;
		print("		struct{\n");
		for(id = tg->ty->ids; id != nil; id = id->next){
			if(id->store == Dfield){
				tt = id->ty;
				tgoffset = stubalign(tgoffset, tt->align, nil, nil);
				if(tgoffset != id->offset)
					fatal("pickadtstub bad offset");
				print("			%R	%s;\n", tt, id->sym->name);
				tgoffset += tt->size;
			}
		}
		if(tg->ty->ids == nil)
			print("			char	dummy[1];\n");
		print("		} %s;\n", tg->sym->name);
	}
	print("	} u;\n");
	print("};\n");

	for(id = t->ids; id != nil; id = id->next)
		if(id->store == Dconst)
			constub(id);

	for(id = t->ids; id != nil; id = id->next)
		if(id->ty->kind == Tchan)
			chanstub(buf, id);

	for(tg = t->tags; tg != nil; tg = tg->next){
		ok = tg->ty->tof->ok;
		tg->ty->tof->ok = OKverify;
		sizetype(tg->ty->tof);
		tg->ty->tof->ok = OKmask;
		desc = mktdesc(tg->ty->tof);
		tg->ty->tof->ok = ok;
		print("#define %s_%s_size %ld\n", buf, tg->sym->name, tg->ty->size);
		print("#define %s_%s_map %M\n", buf, tg->sym->name, desc);
	}
}
