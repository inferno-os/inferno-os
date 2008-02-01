#include "limbo.h"

static	int	addrmode[Rend] =
{
	/* Rreg */	Afp,
	/* Rmreg */	Amp,
	/* Roff */	Aoff,
	/* Rnoff */	Anoff,
	/* Rdesc */	Adesc,
	/* Rdescp */	Adesc,
	/* Rconst */	Aimm,
	/* Ralways */	Aerr,
	/* Radr */	Afpind,
	/* Rmadr */	Ampind,
	/* Rcant */	Aerr,
	/* Rpc */	Apc,
	/* Rmpc */	Aerr,
	/* Rareg */	Aerr,
	/* Ramreg */	Aerr,
	/* Raadr */	Aerr,
	/* Ramadr */	Aerr,
	/* Rldt */	Aldt,
};

static	Decl	*wtemp;
static	Decl	*bigtemp;
static	int	ntemp;
static	Node	retnode;
static	Inst	zinst;

	int	*blockstack;
	int	blockdep;
	int	nblocks;
static	int	lenblockstack;
static	Node	*ntoz;

static Inst* genfixop(Src *src, int op, Node *s, Node *m, Node *d);

void
genstart(void)
{
	Decl *d;

	d = mkdecl(&nosrc, Dlocal, tint);
	d->sym = enter(".ret", 0);
	d->offset = IBY2WD * REGRET;

	retnode = znode;
	retnode.op = Oname;
	retnode.addable = Rreg;
	retnode.decl = d;
	retnode.ty = tint;

	zinst.op = INOP;
	zinst.sm = Anone;
	zinst.dm = Anone;
	zinst.mm = Anone;

	firstinst = allocmem(sizeof *firstinst);
	*firstinst = zinst;
	lastinst = firstinst;

	blocks = -1;
	blockdep = 0;
	nblocks = 0;
}

/*
 * manage nested control flow blocks
 */
int
pushblock(void)
{
	if(blockdep >= lenblockstack){
		lenblockstack = blockdep + 32;
		blockstack = reallocmem(blockstack, lenblockstack * sizeof *blockstack);
	}
	blockstack[blockdep++] = blocks;
	return blocks = nblocks++;
}

void
repushblock(int b)
{
	blockstack[blockdep++] = blocks;
	blocks = b;
}

void
popblock(void)
{
	blocks = blockstack[blockdep -= 1];
}

void
tinit(void)
{
	wtemp = nil;
	bigtemp = nil;
}

Decl*
tdecls(void)
{
	Decl *d;

	for(d = wtemp; d != nil; d = d->next){
		if(d->tref != 1)
			fatal("temporary %s has %d references", d->sym->name, d->tref-1);
	}

	for(d = bigtemp; d != nil; d = d->next){
		if(d->tref != 1)
			fatal("temporary %s has %d references", d->sym->name, d->tref-1);
	}

	return appdecls(wtemp, bigtemp);
}

Node*
talloc(Node *n, Type *t, Node *nok)
{
	Decl *d, *ok;
	Desc *desc;
	char buf[StrSize];

	ok = nil;
	if(nok != nil)
		ok = nok->decl;
	if(ok == nil || ok->tref == 0 || tattr[ok->ty->kind].big != tattr[t->kind].big || ok->ty->align != t->align)
		ok = nil;
	*n = znode;
	n->op = Oname;
	n->addable = Rreg;
	n->ty = t;
	if(tattr[t->kind].big){
		desc = mktdesc(t);
		if(ok != nil && ok->desc == desc){
			ok->tref++;
			ok->refs++;
			n->decl = ok;
			return n;
		}
		for(d = bigtemp; d != nil; d = d->next){
			if(d->tref == 1 && d->desc == desc && d->ty->align == t->align){
				d->tref++;
				d->refs++;
				n->decl = d;
				return n;
			}
		}
		d = mkdecl(&nosrc, Dlocal, t);
		d->desc = desc;
		d->tref = 2;
		d->refs = 1;
		n->decl = d;
		seprint(buf, buf+sizeof(buf), ".b%d", ntemp++);
		d->sym = enter(buf, 0);
		d->next = bigtemp;
		bigtemp = d;
		return n;
	}
	if(ok != nil
	&& tattr[ok->ty->kind].isptr == tattr[t->kind].isptr
	&& ok->ty->size == t->size){
		ok->tref++;
		n->decl = ok;
		return n;
	}
	for(d = wtemp; d != nil; d = d->next){
		if(d->tref == 1
		&& tattr[d->ty->kind].isptr == tattr[t->kind].isptr
		&& d->ty->size == t->size
		&& d->ty->align == t->align){
			d->tref++;
			n->decl = d;
			return n;
		}
	}
	d = mkdecl(&nosrc, Dlocal, t);
	d->tref = 2;
	d->refs = 1;
	n->decl = d;
	seprint(buf, buf+sizeof(buf), ".t%d", ntemp++);
	d->sym = enter(buf, 0);
	d->next = wtemp;
	wtemp = d;
	return n;
}

void
tfree(Node *n)
{
	if(n == nil || n->decl == nil || n->decl->tref == 0)
		return;
	if(n->decl->tref == 1)
		fatal("double free of temporary %s", n->decl->sym->name);
	if (--n->decl->tref == 1)
		zcom1(n, nil);
}

void
tfreelater(Node *n)
{
	if(n == nil || n->decl == nil || n->decl->tref == 0)
		return;
	if(n->decl->tref == 1)
		fatal("double free of temporary %s", n->decl->sym->name);
	if(--n->decl->tref == 1){
		Node *nn = mkn(Oname, nil, nil);

		*nn = *n;
		nn->left = ntoz;
		ntoz = nn;
		n->decl->tref++;
	}
}

void
tfreenow()
{
	Node *n, *nn;

	for(n = ntoz; n != nil; n = nn){
		nn = n->left;
		n->left = nil;
		if(n->decl->tref != 2)
			fatal("bad free of temporary %s", n->decl->sym->name);
		--n->decl->tref;
		zcom1(n, nil);
	}
	ntoz = nil;
}

/*
 * realloc a temporary after it's been freed
 */
Node*
tacquire(Node *n)
{
	if(n == nil || n->decl == nil || n->decl->tref == 0)
		return n;
/*
	if(n->decl->tref != 1)
		fatal("tacquire ref != 1: %d", n->decl->tref);
*/
	n->decl->tref++;
	return n;
}

void
trelease(Node *n)
{
	if(n == nil || n->decl == nil || n->decl->tref == 0)
		return;
	if(n->decl->tref == 1)
		fatal("double release of temporary %s", n->decl->sym->name);
	n->decl->tref--;
}

Inst*
mkinst(void)
{
	Inst *in;

	in = lastinst->next;
	if(in == nil){
		in = allocmem(sizeof *in);
		*in = zinst;
		lastinst->next = in;
	}
	lastinst = in;
	in->block = blocks;
	if(blocks < 0)
		fatal("mkinst no block");
	return in;
}

Inst*
nextinst(void)
{
	Inst *in;

	in = lastinst->next;
	if(in != nil)
		return in;
	in = allocmem(sizeof(*in));
	*in = zinst;
	lastinst->next = in;
	return in;
}

/*
 * allocate a node for returning
 */
Node*
retalloc(Node *n, Node *nn)
{
	if(nn->ty == tnone)
		return nil;
	*n = znode;
	n->op = Oind;
	n->addable = Radr;
	n->left = dupn(1, &n->src, &retnode);
	n->ty = nn->ty;
	return n;
}

Inst*
genrawop(Src *src, int op, Node *s, Node *m, Node *d)
{
	Inst *in;

	in = mkinst();
	in->op = op;
	in->src = *src;
if(in->sm != Anone || in->mm != Anone || in->dm != Anone)
fatal("bogus mkinst in genrawop: %I\n", in);
	if(s != nil){
		in->s = genaddr(s);
		in->sm = addrmode[s->addable];
	}
	if(m != nil){
		in->m = genaddr(m);
		in->mm = addrmode[m->addable];
		if(in->mm == Ampind || in->mm == Afpind)
			fatal("illegal addressing mode in register %n", m);
	}
	if(d != nil){
		in->d = genaddr(d);
		in->dm = addrmode[d->addable];
	}
	return in;
}

Inst*
genop(Src *src, int op, Node *s, Node *m, Node *d)
{
	Inst *in;
	int iop;

	iop = disoptab[op][opind[d->ty->kind]];
	if(iop == 0)
		fatal("can't deal with op %s on %n %n %n in genop", opname[op], s, m, d);
	if(iop == IMULX || iop == IDIVX)
		return genfixop(src, iop, s, m, d);
	in = mkinst();
	in->op = iop;
	in->src = *src;
	if(s != nil){
		in->s = genaddr(s);
		in->sm = addrmode[s->addable];
	}
	if(m != nil){
		in->m = genaddr(m);
		in->mm = addrmode[m->addable];
		if(in->mm == Ampind || in->mm == Afpind)
			fatal("illegal addressing mode in register %n", m);
	}
	if(d != nil){
		in->d = genaddr(d);
		in->dm = addrmode[d->addable];
	}
	return in;
}

Inst*
genbra(Src *src, int op, Node *s, Node *m)
{
	Type *t;
	Inst *in;
	int iop;

	t = s->ty;
	if(t == tany)
		t = m->ty;
	iop = disoptab[op][opind[t->kind]];
	if(iop == 0)
		fatal("can't deal with op %s on %n %n in genbra", opname[op], s, m);
	in = mkinst();
	in->op = iop;
	in->src = *src;
	if(s != nil){
		in->s = genaddr(s);
		in->sm = addrmode[s->addable];
	}
	if(m != nil){
		in->m = genaddr(m);
		in->mm = addrmode[m->addable];
		if(in->mm == Ampind || in->mm == Afpind)
			fatal("illegal addressing mode in register %n", m);
	}
	return in;
}

Inst*
genchan(Src *src, Node *sz, Type *mt, Node *d)
{
	Inst *in;
	Desc *td;
	Addr reg;
	int op, regm;

	regm = Anone;
	reg.decl = nil;
	reg.reg = 0;
	reg.offset = 0;
	op = chantab[mt->kind];
	if(op == 0)
		fatal("can't deal with op %d in genchan", mt->kind);

	switch(mt->kind){
	case Tadt:
	case Tadtpick:
	case Ttuple:
		td = mktdesc(mt);
		if(td->nmap != 0){
			op++;		/* sleazy */
			usedesc(td);
			regm = Adesc;
			reg.decl = mt->decl;
		}else{
			regm = Aimm;
			reg.offset = mt->size;
		}
		break;
	}
	in = mkinst();
	in->op = op;
	in->src = *src;
	in->s = reg;
	in->sm = regm;
	if(sz != nil){
		in->m = genaddr(sz);
		in->mm = addrmode[sz->addable];
	}
	if(d != nil){
		in->d = genaddr(d);
		in->dm = addrmode[d->addable];
	}
	return in;
}

Inst*
genmove(Src *src, int how, Type *mt, Node *s, Node *d)
{
	Inst *in;
	Desc *td;
	Addr reg;
	int op, regm;

	regm = Anone;
	reg.decl = nil;
	reg.reg = 0;
	reg.offset = 0;
	op = movetab[how][mt->kind];
	if(op == 0)
		fatal("can't deal with op %d on %n %n in genmove", how, s, d);

	switch(mt->kind){
	case Tadt:
	case Tadtpick:
	case Ttuple:
	case Texception:
		if(mt->size == 0 && how == Mas)
			return nil;
		td = mktdesc(mt);
		if(td->nmap != 0){
			op++;		/* sleazy */
			usedesc(td);
			regm = Adesc;
			reg.decl = mt->decl;
		}else{
			regm = Aimm;
			reg.offset = mt->size;
		}
		break;
	}
	in = mkinst();
	in->op = op;
	in->src = *src;
	if(s != nil){
		in->s = genaddr(s);
		in->sm = addrmode[s->addable];
	}
	in->m = reg;
	in->mm = regm;
	if(d != nil){
		in->d = genaddr(d);
		in->dm = addrmode[d->addable];
	}
	if(s->addable == Rpc)
		in->op = IMOVPC;
	return in;
}

void
patch(Inst *b, Inst *dst)
{
	Inst *n;

	for(; b != nil; b = n){
		n = b->branch;
		b->branch = dst;
	}
}

long
getpc(Inst *i)
{
	if(i->pc == 0 && i != firstinst && (firstinst->op != INOOP || i != firstinst->next)){
		do
			i = i->next;
		while(i != nil && i->pc == 0);
		if(i == nil || i->pc == 0)
			fatal("bad instruction in getpc");
	}
	return i->pc;
}

/*
 * follow all possible paths from n,
 * marking reached code, compressing branches, and reclaiming unreached insts
 */
void
reach(Inst *in)
{
	Inst *last;

	foldbranch(in);
	last = in;
	for(in = in->next; in != nil; in = in->next){
		if(!in->reach)
			last->next = in->next;
		else
			last = in;
	}
	lastinst = last;
}

/*
 * follow all possible paths from n,
 * marking reached code, compressing branches, and eliminating tail recursion
 */
void
foldbranch(Inst *in)
{
	Inst *b, *next;
	Label *lab;
	int i, n;

	while(in != nil && !in->reach){
		in->reach = 1;
		if(in->branch != nil)
			while(in->branch->op == IJMP){
				if(in == in->branch || in->branch == in->branch->branch)
					break;
				in->branch = in->branch->branch;
			}
		switch(in->op){
		case IGOTO:
		case ICASE:
		case ICASEL:
		case ICASEC:
		case IEXC:
			foldbranch(in->d.decl->ty->cse->iwild);
			lab = in->d.decl->ty->cse->labs;
			n = in->d.decl->ty->cse->nlab;
			for(i = 0; i < n; i++)
				foldbranch(lab[i].inst);
			if(in->op == IEXC)
				in->op = INOOP;
			return;
		case IEXC0:
			foldbranch(in->branch);
			in->op = INOOP;
			break;
		case IRET:
		case IEXIT:
		case IRAISE:
			return;
		case IJMP:
			b = in->branch;
			switch(b->op){
			case ICASE:
			case ICASEL:
			case ICASEC:
			case IRET:
			case IEXIT:
				next = in->next;
				*in = *b;
				in->next = next;
				if(b->op == IRET)
					b->reach = 1;	/* might be default return (TO DO) */
				continue;
			}
			foldbranch(b);
			return;
		default:
			if(in->branch != nil)
				foldbranch(in->branch);
			break;
		}

		in = in->next;
	}
}

/*
 * convert the addressable node into an operand
 * see the comment for sumark
 */
Addr
genaddr(Node *n)
{
	Addr a;

	a.reg = 0;
	a.offset = 0;
	a.decl = nil;
	if(n == nil)
		return a;
	switch(n->addable){
	case Rreg:
		if(n->decl != nil)
			a.decl = n->decl;
		else
			a = genaddr(n->left);
		break;
	case Rmreg:
		if(n->decl != nil)
			a.decl = n->decl;
		else
			a = genaddr(n->left);
		break;
	case Rdesc:
		a.decl = n->ty->decl;
		break;
	case Roff:
	case Rnoff:
		a.decl = n->decl;
		break;
	case Rconst:
		a.offset = n->val;
		break;
	case Radr:
		a = genaddr(n->left);
		break;
	case Rmadr:
		a = genaddr(n->left);
		break;
	case Rareg:
	case Ramreg:
		a = genaddr(n->left);
		if(n->op == Oadd)
			a.reg += n->right->val;
		break;
	case Raadr:
	case Ramadr:
		a = genaddr(n->left);
		if(n->op == Oadd)
			a.offset += n->right->val;
		break;
	case Rldt:
		a.decl = n->decl;
		break;
	case Rdescp:
	case Rpc:
		a.decl = n->decl;
		break;
	default:
		fatal("can't deal with %n in genaddr", n);
		break;
	}
	return a;
}

int
sameaddr(Node *n, Node *m)
{
	Addr a, b;

	if(n->addable != m->addable)
		return 0;
	a = genaddr(n);
	b = genaddr(m);
	return a.offset == b.offset && a.reg == b.reg && a.decl == b.decl;
}

long
resolvedesc(Decl *mod, long length, Decl *decls)
{
	Desc *g, *d, *last;
	int descid;

	g = gendesc(mod, length, decls);
	g->used = 0;
	last = nil;
	for(d = descriptors; d != nil; d = d->next){
		if(!d->used){
			if(last != nil)
				last->next = d->next;
			else
				descriptors = d->next;
			continue;
		}
		last = d;
	}

	g->next = descriptors;
	descriptors = g;

	descid = 0;
	for(d = descriptors; d != nil; d = d->next)
		d->id = descid++;
	if(g->id != 0)
		fatal("bad global descriptor id");

	return descid;
}

int
resolvemod(Decl *m)
{
	Decl *id, *d;

	for(id = m->ty->ids; id != nil; id = id->next){
		switch(id->store){
		case Dfn:
			id->iface->pc = id->pc;
			id->iface->desc = id->desc;
if(debug['v']) print("R1: %s %p %p %p\n", id->sym->name, id, id->iface, id->pc);
			break;
		case Dtype:
			if(id->ty->kind != Tadt)
				break;
			for(d = id->ty->ids; d != nil; d = d->next){
				if(d->store == Dfn){
					d->iface->pc = d->pc;
					d->iface->desc = d->desc;
if(debug['v']) print("R2: %s %p %p %p\n", d->sym->name, d, d->iface, d->pc);
				}
			}
			break;
		}
	}
	/* for addiface */
	for(id = m->ty->tof->ids; id != nil; id = id->next){
		if(id->store == Dfn){
			if(id->pc == nil)
				id->pc = id->iface->pc;
			if(id->desc == nil)
				id->desc = id->iface->desc;
if(debug['v']) print("R3: %s %p %p %p\n", id->sym->name, id, id->iface, id->pc);
		}
	}
	return m->ty->tof->decl->init->val;
}

/*
 * place the Tiface decs in another list
 */
Decl*
resolveldts(Decl *d, Decl **dd)
{
	Decl *d1, *ld1, *d2, *ld2, *n;

	d1 = d2 = nil;
	ld1 = ld2 = nil;
	for( ; d != nil; d = n){
		n = d->next;
		d->next = nil;
		if(d->ty->kind == Tiface){
			if(d2 == nil)
				d2 = d;
			else
				ld2->next = d;
			ld2 = d;
		}
		else{
			if(d1 == nil)
				d1 = d;
			else
				ld1->next = d;
			ld1 = d;
		}
	}
	*dd = d2;
	return d1;
}

/*
 * fix up all pc's
 * finalize all data offsets
 * fix up instructions with offsets too large
 */
long
resolvepcs(Inst *inst)
{
	Decl *d;
	Inst *in;
	int op;
	ulong r, off;
	long v, pc;

	pc = 0;
	for(in = inst; in != nil; in = in->next){
		if(!in->reach || in->op == INOP)
			fatal("unreachable pc: %I %ld", in, pc);
		if(in->op == INOOP){
			in->pc = pc;
			continue;
		}
		d = in->s.decl;
		if(d != nil){
			if(in->sm == Adesc){
				if(d->desc != nil)
					in->s.offset = d->desc->id;
			}else
				in->s.reg += d->offset;
		}
		r = in->s.reg;
		off = in->s.offset;
		if((in->sm == Afpind || in->sm == Ampind)
		&& (r >= MaxReg || off >= MaxReg))
			fatal("big offset in %I\n", in);

		d = in->m.decl;
		if(d != nil){
			if(in->mm == Adesc){
				if(d->desc != nil)
					in->m.offset = d->desc->id;
			}else
				in->m.reg += d->offset;
		}
		v = 0;
		switch(in->mm){
		case Anone:
			break;
		case Aimm:
		case Apc:
		case Adesc:
			v = in->m.offset;
			break;
		case Aoff:
		case Anoff:
			v = in->m.decl->iface->offset;
			break;
		case Afp:
		case Amp:
		case Aldt:
			v = in->m.reg;
			if(v < 0)
				v = 0x8000;
			break;

		default:
			fatal("can't deal with %I's m mode\n", in);
			break;
		}
		if(v > 0x7fff || v < -0x8000){
			switch(in->op){
			case IALT:
			case IINDX:
warn(in->src.start, "possible bug: temp m too big in %I: %ld %ld %d\n", in, in->m.reg, in->m.reg, MaxReg);
				rewritedestreg(in, IMOVW, RTemp);
				break;
			default:
				op = IMOVW;
				if(isbyteinst[in->op])
					op = IMOVB;
				in = rewritesrcreg(in, op, RTemp, pc++);
				break;
			}
		}

		d = in->d.decl;
		if(d != nil){
			if(in->dm == Apc)
				in->d.offset = d->pc->pc;
			else
				in->d.reg += d->offset;
		}
		r = in->d.reg;
		off = in->d.offset;
		if((in->dm == Afpind || in->dm == Ampind)
		&& (r >= MaxReg || off >= MaxReg))
			fatal("big offset in %I\n", in);

		in->pc = pc;
		pc++;
	}
	for(in = inst; in != nil; in = in->next){
		d = in->s.decl;
		if(d != nil && in->sm == Apc)
			in->s.offset = d->pc->pc;
		d = in->d.decl;
		if(d != nil && in->dm == Apc)
			in->d.offset = d->pc->pc;
		if(in->branch != nil){
			in->dm = Apc;
			in->d.offset = in->branch->pc;
		}
	}
	return pc;
}

/*
 * fixp up a big register constant uses as a source
 * ugly: smashes the instruction
 */
Inst*
rewritesrcreg(Inst *in, int op, int treg, int pc)
{
	Inst *new;
	Addr a;
	int am;

	a = in->m;
	am = in->mm;
	in->mm = Afp;
	in->m.reg = treg;
	in->m.decl = nil;

	new = allocmem(sizeof(*in));
	*new = *in;

	*in = zinst;
	in->src = new->src;
	in->next = new;
	in->op = op;
	in->s = a;
	in->sm = am;
	in->dm = Afp;
	in->d.reg = treg;
	in->pc = pc;
	in->reach = 1;
	in->block = new->block;
	return new;
}

/*
 * fix up a big register constant by moving to the destination
 * after the instruction completes
 */
Inst*
rewritedestreg(Inst *in, int op, int treg)
{
	Inst *n;

	n = allocmem(sizeof(*n));
	*n = zinst;
	n->next = in->next;
	in->next = n;
	n->src = in->src;
	n->op = op;
	n->sm = Afp;
	n->s.reg = treg;
	n->d = in->m;
	n->dm = in->mm;
	n->reach = 1;
	n->block = in->block;

	in->mm = Afp;
	in->m.reg = treg;
	in->m.decl = nil;

	return n;
}

int
instconv(Fmt *f)
{
	Inst *in;
	char buf[512], *p;
	char *op, *comma;

	in = va_arg(f->args, Inst*);
	op = nil;
	if(in->op < MAXDIS)
		op = instname[in->op];
	if(op == nil)
		op = "??";
	buf[0] = '\0';
	if(in->op == INOP)
		return fmtstrcpy(f, "\tnop");
	p = seprint(buf, buf + sizeof(buf), "\t%s\t", op);
	comma = "";
	if(in->sm != Anone){
		p = addrprint(p, buf + sizeof(buf), in->sm, &in->s);
		comma = ",";
	}
	if(in->mm != Anone){
		p = seprint(p, buf + sizeof(buf), "%s", comma);
		p = addrprint(p, buf + sizeof(buf), in->mm, &in->m);
		comma = ",";
	}
	if(in->dm != Anone){
		p = seprint(p, buf + sizeof(buf), "%s", comma);
		p = addrprint(p, buf + sizeof(buf), in->dm, &in->d);
	}
	
	if(asmsym && in->s.decl != nil && in->sm == Adesc)
		p = seprint(p, buf+sizeof(buf), "	#%D", in->s.decl);
	if(0 && asmsym && in->m.decl != nil)
		p = seprint(p, buf+sizeof(buf), "	#%D", in->m.decl);
	if(asmsym && in->d.decl != nil && in->dm == Apc)
		p = seprint(p, buf+sizeof(buf), "	#%D", in->d.decl);
	if(asmsym)
		p = seprint(p, buf+sizeof(buf), "	#%U", in->src);
	USED(p);
	return fmtstrcpy(f, buf);
}

char*
addrprint(char *buf, char *end, int am, Addr *a)
{
	switch(am){
	case Anone:
		return buf;
	case Aimm:
	case Apc:
	case Adesc:
		return seprint(buf, end, "$%ld", a->offset);
	case Aoff:
		return seprint(buf, end, "$%ld", a->decl->iface->offset);
	case Anoff:
		return seprint(buf, end, "-$%ld", a->decl->iface->offset);
	case Afp:
		return seprint(buf, end, "%ld(fp)", a->reg);
	case Afpind:
		return seprint(buf, end, "%ld(%ld(fp))", a->offset, a->reg);
	case Amp:
		return seprint(buf, end, "%ld(mp)", a->reg);
	case Ampind:
		return seprint(buf, end, "%ld(%ld(mp))", a->offset, a->reg);
	case Aldt:
		return seprint(buf, end, "$%ld", a->reg);
	case Aerr:
	default:
		return seprint(buf, end, "%ld(%ld(?%d?))", a->offset, a->reg, am);
	}
}

static void
genstore(Src *src, Node *n, int offset)
{
	Decl *de;
	Node d;

	de = mkdecl(&nosrc, Dlocal, tint);
	de->sym = nil;
	de->offset = offset;

	d = znode;
	d.op = Oname;
	d.addable = Rreg;
	d.decl = de;
	d.ty = tint;
	genrawop(src, IMOVW, n, nil, &d);
}

static Inst*
genfixop(Src *src, int op, Node *s, Node *m, Node *d)
{
	int p, a;
	Node *mm;
	Inst *i;

	mm = m ? m: d;
	op = fixop(op, mm->ty, s->ty, d->ty, &p, &a);
	if(op == IMOVW){	/* just zero d */
		s = sumark(mkconst(src, 0));
		return genrawop(src, op, s, nil, d);
	}
	if(op != IMULX && op != IDIVX)
		genstore(src, sumark(mkconst(src, a)), STemp);
	genstore(src, sumark(mkconst(src, p)), DTemp);
	i =  genrawop(src, op, s, m, d);
	return i;
}

Inst*
genfixcastop(Src *src, int op, Node *s, Node *d)
{
	int p, a;
	Node *m;

	op = fixop(op, s->ty, tint, d->ty, &p, &a);
	if(op == IMOVW){	/* just zero d */
		s = sumark(mkconst(src, 0));
		return genrawop(src, op, s, nil, d);
	}
	m = sumark(mkconst(src, p));
	if(op != ICVTXX)
		genstore(src, sumark(mkconst(src, a)), STemp);
	return genrawop(src, op, s, m, d);
}
