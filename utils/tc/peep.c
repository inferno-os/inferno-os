#include "gc.h"

void
peep(void)
{
	Reg *r, *r1, *r2;
	Prog *p, *p1;
	int t;
/*
 * complete R structure
 */
	t = 0;
	for(r=firstr; r!=R; r=r1) {
		r1 = r->link;
		if(r1 == R)
			break;
		p = r->prog->link;
		while(p != r1->prog)
		switch(p->as) {
		default:
			r2 = rega();
			r->link = r2;
			r2->link = r1;

			r2->prog = p;
			r2->p1 = r;
			r->s1 = r2;
			r2->s1 = r1;
			r1->p1 = r2;

			r = r2;
			t++;

		case ADATA:
		case AGLOBL:
		case ANAME:
		case ASIGNAME:
			p = p->link;
		}
	}

loop1:
	t = 0;
	for(r=firstr; r!=R; r=r->link) {
		p = r->prog;
		if(p->as == AMOVW || p->as == AMOVF || p->as == AMOVD)
		if(regtyp(&p->to)) {
			if(p->from.type == D_CONST)
				constprop(&p->from, &p->to, r->s1);
			else if(regtyp(&p->from))
			if(p->from.type == p->to.type) {
				if(copyprop(r)) {
					excise(r);
					t++;
				} else
				if(subprop(r) && copyprop(r)) {
					excise(r);
					t++;
				}
			}
		}
	}
	if(t)
		goto loop1;
	/*
	 * look for MOVB x,R; MOVB R,R
	 */
	for(r=firstr; r!=R; r=r->link) {
		p = r->prog;
		switch(p->as) {
		default:
			continue;
		case AEOR:
			/*
			 * EOR -1,x,y => MVN x,y
			 */
			if(p->from.type == D_CONST && p->from.offset == -1) {
				p->as = AMVN;
				p->from.type = D_REG;
				if(p->reg != NREG)
					p->from.reg = p->reg;
				else
					p->from.reg = p->to.reg;
				p->reg = NREG;
			}
			continue;
		case AMOVH:
		case AMOVHU:
		case AMOVB:
		case AMOVBU:
			if(p->to.type != D_REG)
				continue;
			break;
		}
		r1 = r->link;
		if(r1 == R)
			continue;
		p1 = r1->prog;
		if(p1->as != p->as)
			continue;
		if(p1->from.type != D_REG || p1->from.reg != p->to.reg)
			continue;
		if(p1->to.type != D_REG || p1->to.reg != p->to.reg)
			continue;
		excise(r1);
	}
}

void
excise(Reg *r)
{
	Prog *p;

	p = r->prog;
	p->as = ANOP;
	p->from = zprog.from;
	p->to = zprog.to;
	p->reg = zprog.reg; /**/
}

Reg*
uniqp(Reg *r)
{
	Reg *r1;

	r1 = r->p1;
	if(r1 == R) {
		r1 = r->p2;
		if(r1 == R || r1->p2link != R)
			return R;
	} else
		if(r->p2 != R)
			return R;
	return r1;
}

Reg*
uniqs(Reg *r)
{
	Reg *r1;

	r1 = r->s1;
	if(r1 == R) {
		r1 = r->s2;
		if(r1 == R)
			return R;
	} else
		if(r->s2 != R)
			return R;
	return r1;
}

int
regtyp(Adr *a)
{

	if(a->type == D_REG)
		return 1;
	if(a->type == D_FREG)
		return 1;
	return 0;
}

/*
 * the idea is to substitute
 * one register for another
 * from one MOV to another
 *	MOV	a, R0
 *	ADD	b, R0	/ no use of R1
 *	MOV	R0, R1
 * would be converted to
 *	MOV	a, R1
 *	ADD	b, R1
 *	MOV	R1, R0
 * hopefully, then the former or latter MOV
 * will be eliminated by copy propagation.
 */
int
subprop(Reg *r0)
{
	Prog *p;
	Adr *v1, *v2;
	Reg *r;
	int t;

	p = r0->prog;
	v1 = &p->from;
	if(!regtyp(v1))
		return 0;
	v2 = &p->to;
	if(!regtyp(v2))
		return 0;
	for(r=uniqp(r0); r!=R; r=uniqp(r)) {
		if(uniqs(r) == R)
			break;
		p = r->prog;
		switch(p->as) {
		case ABL:
		case ABX:
			return 0;

		// case ACMP:
		// case ACMN:
		case AADD:
		case ASUB:
		// case ASLL:
		// case ASRL:
		// case ASRA:
		// case AORR:
		// case AAND:
		// case AEOR:
		// case AMUL:
		// case ADIV:
		// case ADIVU:

		// case ACMPF:
		// case ACMPD:
		// case AADDD:
		// case AADDF:
		// case ASUBD:
		// case ASUBF:
		// case AMULD:
		// case AMULF:
		// case ADIVD:
		// case ADIVF:
			if(p->to.type == v1->type)
			if(p->to.reg == v1->reg) {
				if(p->reg == NREG)
					p->reg = p->to.reg;
				goto gotit;
			}
			break;

		case AMOVF:
		case AMOVD:
		case AMOVW:
			if(p->to.type == v1->type)
			if(p->to.reg == v1->reg)
				goto gotit;
			break;

		case AMOVM:
			t = 1<<v2->reg;
			if((p->from.type == D_CONST && (p->from.offset&t)) ||
			   (p->to.type == D_CONST && (p->to.offset&t)))
				return 0;
			break;
		}
		if(copyau(&p->from, v2) ||
		   copyau1(p, v2) ||
		   copyau(&p->to, v2))
			break;
		if(copysub(&p->from, v1, v2, 0) ||
		   copysub1(p, v1, v2, 0) ||
		   copysub(&p->to, v1, v2, 0))
			break;
	}
	return 0;

gotit:
	copysub(&p->to, v1, v2, 1);
	if(debug['P']) {
		print("gotit: %D->%D\n%P", v1, v2, r->prog);
		if(p->from.type == v2->type)
			print(" excise");
		print("\n");
	}
	for(r=uniqs(r); r!=r0; r=uniqs(r)) {
		p = r->prog;
		copysub(&p->from, v1, v2, 1);
		copysub1(p, v1, v2, 1);
		copysub(&p->to, v1, v2, 1);
		if(debug['P'])
			print("%P\n", r->prog);
	}
	t = v1->reg;
	v1->reg = v2->reg;
	v2->reg = t;
	if(debug['P'])
		print("%P last\n", r->prog);
	return 1;
}

/*
 * The idea is to remove redundant copies.
 *	v1->v2	F=0
 *	(use v2	s/v2/v1/)*
 *	set v1	F=1
 *	use v2	return fail
 *	-----------------
 *	v1->v2	F=0
 *	(use v2	s/v2/v1/)*
 *	set v1	F=1
 *	set v2	return success
 */
int
copyprop(Reg *r0)
{
	Prog *p;
	Adr *v1, *v2;
	Reg *r;

	p = r0->prog;
	v1 = &p->from;
	v2 = &p->to;
	if(copyas(v1, v2))
		return 1;
	for(r=firstr; r!=R; r=r->link)
		r->active = 0;
	return copy1(v1, v2, r0->s1, 0);
}

int
copy1(Adr *v1, Adr *v2, Reg *r, int f)
{
	int t;
	Prog *p;

	if(r->active) {
		if(debug['P'])
			print("act set; return 1\n");
		return 1;
	}
	r->active = 1;
	if(debug['P'])
		print("copy %D->%D f=%d\n", v1, v2, f);
	for(; r != R; r = r->s1) {
		p = r->prog;
		if(debug['P'])
			print("%P", p);
		if(!f && uniqp(r) == R) {
			f = 1;
			if(debug['P'])
				print("; merge; f=%d", f);
		}
		t = copyu(p, v2, A);
		switch(t) {
		case 2:	/* rar, cant split */
			if(debug['P'])
				print("; %Drar; return 0\n", v2);
			return 0;

		case 3:	/* set */
			if(debug['P'])
				print("; %Dset; return 1\n", v2);
			return 1;

		case 1:	/* used, substitute */
		case 4:	/* use and set */
			if(f) {
				if(!debug['P'])
					return 0;
				if(t == 4)
					print("; %Dused+set and f=%d; return 0\n", v2, f);
				else
					print("; %Dused and f=%d; return 0\n", v2, f);
				return 0;
			}
			if(copyu(p, v2, v1)) {
				if(debug['P'])
					print("; sub fail; return 0\n");
				return 0;
			}
			if(debug['P'])
				print("; sub%D/%D", v2, v1);
			if(t == 4) {
				if(debug['P'])
					print("; %Dused+set; return 1\n", v2);
				return 1;
			}
			break;
		}
		if(!f) {
			t = copyu(p, v1, A);
			if(!f && (t == 2 || t == 3 || t == 4)) {
				f = 1;
				if(debug['P'])
					print("; %Dset and !f; f=%d", v1, f);
			}
		}
		if(debug['P'])
			print("\n");
		if(r->s2)
			if(!copy1(v1, v2, r->s2, f))
				return 0;
	}
	return 1;
}

/*
 * The idea is to remove redundant constants.
 *	$c1->v1
 *	($c1->v2 s/$c1/v1)*
 *	set v1  return
 * The v1->v2 should be eliminated by copy propagation.
 */
void
constprop(Adr *c1, Adr *v1, Reg *r)
{
	Prog *p;

	if(debug['C'])
		print("constprop %D->%D\n", c1, v1);
	for(; r != R; r = r->s1) {
		p = r->prog;
		if(debug['C'])
			print("%P", p);
		if(uniqp(r) == R) {
			if(debug['C'])
				print("; merge; return\n");
			return;
		}
		if(p->as == AMOVW && copyas(&p->from, c1)) {
				if(debug['C'])
					print("; sub%D/%D", &p->from, v1);
				p->from = *v1;
		} else if(copyu(p, v1, A) > 1) {
			if(debug['C'])
				print("; %Dset; return\n", v1);
			return;
		}
		if(debug['C'])
			print("\n");
		if(r->s2)
			constprop(c1, v1, r->s2);
	}
}

/*
 * return
 * 1 if v only used (and substitute),
 * 2 if read-alter-rewrite
 * 3 if set
 * 4 if set and used
 * 0 otherwise (not touched)
 */
int
copyu(Prog *p, Adr *v, Adr *s)
{

	switch(p->as) {

	default:
		if(debug['P'])
			print(" (???)");
		return 2;

	case AMOVM:
		if(v->type != D_REG)
			return 0;
		if(p->from.type == D_CONST) {	/* read reglist, read/rar */
			if(s != A) {
				if(p->from.offset&(1<<v->reg))
					return 1;
				if(copysub(&p->to, v, s, 1))
					diag(Z, "movm dst being replaced");	// was return 1;
				return 0;
			}
			if(copyau(&p->to, v))
				return 2;		// register updated in thumb // was return 1;
			if(p->from.offset&(1<<v->reg))
				return 1;
		} else {			/* read/rar, write reglist */
			if(s != A) {
				if(p->to.offset&(1<<v->reg))
					return 1;
				if(copysub(&p->from, v, s, 1))
					diag(Z, "movm src being replaced");	// was return 1;
				return 0;
			}
			if(copyau(&p->from, v)) {
				// if(p->to.offset&(1<<v->reg))
					// return 4;
				return 2;		// register updated in thumb // was return 1;
			}
			if(p->to.offset&(1<<v->reg))
				return 3;
		}
		return 0;
		
	case ANOP:	/* read, write */
	case AMOVW:
	case AMOVF:
	case AMOVD:
	case AMOVH:
	case AMOVHU:
	case AMOVB:
	case AMOVBU:
	case AMOVDW:
	case AMOVWD:
	case AMOVFD:
	case AMOVDF:
		if(s != A) {
			if(copysub(&p->from, v, s, 1))
				return 1;
			if(!copyas(&p->to, v))
				if(copysub(&p->to, v, s, 1))
					return 1;
			return 0;
		}
		if(copyas(&p->to, v)) {
			if(copyau(&p->from, v))
				return 4;
			return 3;
		}
		if(copyau(&p->from, v))
			return 1;
		if(copyau(&p->to, v))
			return 1;
		return 0;

	case ASLL:
	case ASRL:
	case ASRA:
	case AORR:
	case AAND:
	case AEOR:
	case AMUL:
	case ADIV:
	case ADIVU:
	case AADDF:
	case AADDD:
	case ASUBF:
	case ASUBD:
	case AMULF:
	case AMULD:
	case ADIVF:
	case ADIVD:
	case ACMPF:
	case ACMPD:
	case ACMP:
	case ACMN:
		if(copyas(&p->to, v))
			return 2;
		/*FALLTHROUGH*/

	case AADD:	/* read, read, write */
	case ASUB:
		if(s != A) {
			if(copysub(&p->from, v, s, 1))
				return 1;
			if(copysub1(p, v, s, 1))
				return 1;
			if(!copyas(&p->to, v))
				if(copysub(&p->to, v, s, 1))
					return 1;
			return 0;
		}
		if(copyas(&p->to, v)) {
			if(p->reg == NREG)
				p->reg = p->to.reg;
			if(copyau(&p->from, v))
				return 4;
			if(copyau1(p, v))
				return 4;
			return 3;
		}
		if(copyau(&p->from, v))
			return 1;
		if(copyau1(p, v))
			return 1;
		if(copyau(&p->to, v))
			return 1;
		return 0;

	case ABEQ:	/* read, read */
	case ABNE:
	case ABCS:
	case ABHS:
	case ABCC:
	case ABLO:
	case ABMI:
	case ABPL:
	case ABVS:
	case ABVC:
	case ABHI:
	case ABLS:
	case ABGE:
	case ABLT:
	case ABGT:
	case ABLE:
		if(s != A) {
			if(copysub(&p->from, v, s, 1))
				return 1;
			return copysub1(p, v, s, 1);
		}
		if(copyau(&p->from, v))
			return 1;
		if(copyau1(p, v))
			return 1;
		return 0;

	case AB:	/* funny */
		if(s != A) {
			if(copysub(&p->to, v, s, 1))
				return 1;
			return 0;
		}
		if(copyau(&p->to, v))
			return 1;
		return 0;

	case ARET:	/* funny */
		if(v->type == D_REG)
		if(v->reg == REGRET)
			return 2;
		if(v->type == D_FREG)
		if(v->reg == FREGRET)
			return 2;

	case ABL:	/* funny */
	case ABX:
		if(v->type == D_REG) {
			if(v->reg <= REGEXT && v->reg > exregoffset)
				return 2;
			if(v->reg == REGARG)
				return 2;
		}
		if(v->type == D_FREG)
			if(v->reg <= FREGEXT && v->reg > exfregoffset)
				return 2;

		if(s != A) {
			if(copysub(&p->to, v, s, 1))
				return 1;
			return 0;
		}
		if(copyau(&p->to, v))
			return 4;
		return 3;

	case ATEXT:	/* funny */
		if(v->type == D_REG)
			if(v->reg == REGARG)
				return 3;
		return 0;
	}
	return 0;
}

int
a2type(Prog *p)
{

	switch(p->as) {

	case ACMP:
	case ACMN:

	case AADD:
	case ASUB:
	case ASLL:
	case ASRL:
	case ASRA:
	case AORR:
	case AAND:
	case AEOR:
	case AMUL:
	case ADIV:
	case ADIVU:
		return D_REG;

	case ACMPF:
	case ACMPD:

	case AADDF:
	case AADDD:
	case ASUBF:
	case ASUBD:
	case AMULF:
	case AMULD:
	case ADIVF:
	case ADIVD:
		return D_FREG;
	}
	return D_NONE;
}

/*
 * direct reference,
 * could be set/use depending on
 * semantics
 */
int
copyas(Adr *a, Adr *v)
{

	if(regtyp(v)) {
		if(a->type == v->type)
		if(a->reg == v->reg)
			return 1;
	} else if(v->type == D_CONST) {		/* for constprop */
		if(a->type == v->type)
		if(a->name == v->name)
		if(a->sym == v->sym)
		if(a->reg == v->reg)
		if(a->offset == v->offset)
			return 1;
	}
	return 0;
}

/*
 * either direct or indirect
 */
int
copyau(Adr *a, Adr *v)
{

	if(copyas(a, v))
		return 1;
	if(v->type == D_REG) {
		if(a->type == D_OREG) {
			if(v->reg == a->reg)
				return 1;
		}
	}
	return 0;
}

int
copyau1(Prog *p, Adr *v)
{

	if(regtyp(v)) {
		if(a2type(p) == v->type)
		if(p->reg == v->reg) {
			if(a2type(p) != v->type)
				print("botch a2type %P\n", p);
			return 1;
		}
	}
	return 0;
}

/*
 * substitute s for v in a
 * return failure to substitute
 */
int
copysub(Adr *a, Adr *v, Adr *s, int f)
{

	if(f)
	if(copyau(a, v)) {
		a->reg = s->reg;
	}
	return 0;
}

int
copysub1(Prog *p1, Adr *v, Adr *s, int f)
{

	if(f)
	if(copyau1(p1, v))
		p1->reg = s->reg;
	return 0;
}
