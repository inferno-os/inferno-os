#include	"l.h"

static	Sym*	sym_div;
static	Sym*	sym_divu;
static	Sym*	sym_mod;
static	Sym*	sym_modu;

static void setdiv(int);

static Prog *
movrr(Prog *q, int rs, int rd, Prog *p)
{
	if(q == nil)
		q = prg();
	q->as = AMOVW;
	q->line = p->line;
	q->from.type = D_REG;
	q->from.reg = rs;
	q->to.type = D_REG;
	q->to.reg = rd;
	q->link = p->link;
	return q;
}

static Prog *
fnret(Prog *q, int rs, int foreign, Prog *p)
{
	q = movrr(q, rs, REGPC, p);
	if(foreign){	// BX rs
		q->as = ABXRET;
		q->from.type = D_NONE;
		q->from.reg = NREG;
		q->to.reg = rs;
	}
	return q;
}

static Prog *
aword(long w, Prog *p)
{
	Prog *q;

	q = prg();
	q->as = AWORD;
	q->line = p->line;
	q->from.type = D_NONE;
	q->reg = NREG;
	q->to.type = D_CONST;
	q->to.offset = w;
	q->link = p->link;
	p->link = q;
	return q;
}

static Prog *
adword(long w1, long w2, Prog *p)
{
	Prog *q;

	q = prg();
	q->as = ADWORD;
	q->line = p->line;
	q->from.type = D_CONST;
	q->from.offset = w1;
	q->reg = NREG;
	q->to.type = D_CONST;
	q->to.offset = w2;
	q->link = p->link;
	p->link = q;
	return q;
}

void
noops(void)
{
	Prog *p, *q, *q1, *q2;
	int o, curframe, curbecome, maxbecome, foreign;

	/*
	 * find leaf subroutines
	 * become sizes
	 * frame sizes
	 * strip NOPs
	 * expand RET
	 * expand BECOME pseudo
	 */

	if(debug['v'])
		Bprint(&bso, "%5.2f noops\n", cputime());
	Bflush(&bso);

	curframe = 0;
	curbecome = 0;
	maxbecome = 0;
	curtext = 0;

	q = P;
	for(p = firstp; p != P; p = p->link) {
		setarch(p);

		/* find out how much arg space is used in this TEXT */
		if(p->to.type == D_OREG && p->to.reg == REGSP)
			if(p->to.offset > curframe)
				curframe = p->to.offset;

		switch(p->as) {
		case ATEXT:
			if(curtext && curtext->from.sym) {
				curtext->from.sym->frame = curframe;
				curtext->from.sym->become = curbecome;
				if(curbecome > maxbecome)
					maxbecome = curbecome;
			}
			curframe = 0;
			curbecome = 0;

			p->mark |= LEAF;
			curtext = p;
			break;

		case ARET:
			/* special form of RET is BECOME */
			if(p->from.type == D_CONST)
				if(p->from.offset > curbecome)
					curbecome = p->from.offset;
			break;

		case ANOP:
			q1 = p->link;
			q->link = q1;		/* q is non-nop */
			q1->mark |= p->mark;
			continue;

		case ABL:
		case ABX:
			if(curtext != P)
				curtext->mark &= ~LEAF;

		case ABCASE:
		case AB:

		case ABEQ:
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

			q1 = p->cond;
			if(q1 != P) {
				while(q1->as == ANOP) {
					q1 = q1->link;
					p->cond = q1;
				}
			}
			break;
		}
		q = p;
	}

	if(curtext && curtext->from.sym) {
		curtext->from.sym->frame = curframe;
		curtext->from.sym->become = curbecome;
		if(curbecome > maxbecome)
			maxbecome = curbecome;
	}

	if(debug['b'])
		print("max become = %d\n", maxbecome);
	xdefine("ALEFbecome", STEXT, maxbecome);

	curtext = 0;
	for(p = firstp; p != P; p = p->link) {
		setarch(p);
		switch(p->as) {
		case ATEXT:
			curtext = p;
			break;
		case ABL:
		// case ABX:
			if(curtext != P && curtext->from.sym != S && curtext->to.offset >= 0) {
				o = maxbecome - curtext->from.sym->frame;
				if(o <= 0)
					break;
				/* calling a become or calling a variable */
				if(p->to.sym == S || p->to.sym->become) {
					curtext->to.offset += o;
					if(debug['b']) {
						curp = p;
						print("%D calling %D increase %d\n",
							&curtext->from, &p->to, o);
					}
				}
			}
			break;
		}
	}

	for(p = firstp; p != P; p = p->link) {
		setarch(p);
		o = p->as;
		switch(o) {
		case ATEXT:
			curtext = p;
			autosize = p->to.offset + 4;
			if(autosize <= 4)
			if(curtext->mark & LEAF) {
				p->to.offset = -4;
				autosize = 0;
			}

			if(!autosize && !(curtext->mark & LEAF)) {
				if(debug['v'])
					Bprint(&bso, "save suppressed in: %s\n",
						curtext->from.sym->name);
				Bflush(&bso);
				curtext->mark |= LEAF;
			}
#ifdef CALLEEBX
			if(p->from.sym->foreign){
				if(thumb)
					// don't allow literal pool to seperate these
					p = adword(0xe28f7001, 0xe12fff17, p); // arm add 1, pc, r7 and bx r7
					// p = aword(0xe12fff17, aword(0xe28f7001, p)); // arm add 1, pc, r7 and bx r7
				else
					p = aword(0x4778, p);	// thumb bx pc and 2 bytes padding
			}
#endif
			if(curtext->mark & LEAF) {
				if(curtext->from.sym)
					curtext->from.sym->type = SLEAF;
#ifdef optimise_time
				if(autosize) {
					q = prg();
					q->as = ASUB;
					q->line = p->line;
					q->from.type = D_CONST;
					q->from.offset = autosize;
					q->to.type = D_REG;
					q->to.reg = REGSP;

					q->link = p->link;
					p->link = q;
				}
				break;
#else
				if(!autosize)
					break;
#endif
			}

			if(thumb){
				if(!(curtext->mark & LEAF)){
					q = movrr(nil, REGLINK, REGTMPT-1, p);
					p->link = q;
					q1 = prg();
					q1->as = AMOVW;
					q1->line = p->line;
					q1->from.type = D_REG;
					q1->from.reg = REGTMPT-1;
					q1->to.type = D_OREG;
					q1->to.name = D_NONE;
					q1->to.reg = REGSP;
					q1->to.offset = 0;
					q1->link = q->link;
					q->link = q1;
				}
				if(autosize){
					q2 = prg();
					q2->as = ASUB;
					q2->line = p->line;
					q2->from.type = D_CONST;
					q2->from.offset = autosize;
					q2->to.type = D_REG;
					q2->to.reg = REGSP;
					q2->link = p->link;
					p->link = q2;
				}
				break;
			}

			q1 = prg();
			q1->as = AMOVW;
			q1->scond |= C_WBIT;
			q1->line = p->line;
			q1->from.type = D_REG;
			q1->from.reg = REGLINK;
			q1->to.type = D_OREG;
			q1->to.offset = -autosize;
			q1->to.reg = REGSP;
			q1->link = p->link;
			p->link = q1;
			break;

		case ARET:
			nocache(p);
			foreign = seenthumb && curtext->from.sym != S && (curtext->from.sym->foreign || curtext->from.sym->fnptr);
// print("%s %d %d\n", curtext->from.sym->name, curtext->from.sym->foreign, curtext->from.sym->fnptr);
			if(p->from.type == D_CONST)
				goto become;
			if(curtext->mark & LEAF) {
				if(!autosize) {
					if(thumb){
						p = fnret(p, REGLINK, foreign, p);
						break;
					}
// if(foreign) print("ABXRET 1 %s\n", curtext->from.sym->name);
					p->as = foreign ? ABXRET : AB;
					p->from = zprg.from;
					p->to.type = D_OREG;
					p->to.offset = 0;
					p->to.reg = REGLINK;
					break;
				}

#ifdef optimise_time
				p->as = AADD;
				p->from.type = D_CONST;
				p->from.offset = autosize;
				p->to.type = D_REG;
				p->to.reg = REGSP;
				if(thumb){
					p->link = fnret(nil, REGLINK, foreign, p);
					break;
				}
				q = prg();
// if(foreign) print("ABXRET 2 %s\n", curtext->from.sym->name);
				q->as = foreign ? ABXRET : AB;
				q->scond = p->scond;
				q->line = p->line;
				q->to.type = D_OREG;
				q->to.offset = 0;
				q->to.reg = REGLINK;

				q->link = p->link;
				p->link = q;

				break;
#endif
			}
			if(thumb){
				if(curtext->mark & LEAF){
					if(autosize){
						p->as = AADD;
						p->from.type = D_CONST;
						p->from.offset = autosize;
						p->to.type = D_REG;
						p->to.reg = REGSP;
						q = nil;
					}
					else
						q = p;
					q = fnret(q, REGLINK, foreign, p);
					if(q != p)
						p->link = q;
				}
				else{
					p->as = AMOVW;
					p->from.type = D_OREG;
					p->from.name = D_NONE;
					p->from.reg = REGSP;
					p->from.offset = 0;
					p->to.type = D_REG;
					p->to.reg = REGTMPT-1;
					if(autosize){
						q = prg();
						q->as = AADD;
						q->from.type = D_CONST;
						q->from.offset = autosize;
						q->to.type = D_REG;
						q->to.reg = REGSP;
						q->link = p->link;
						p->link = 	q;
					}
					else
						q = p;
					q1 = fnret(nil, REGTMPT-1, foreign, p);
					q1->link = q->link;
					q->link = q1;
				}
				break;
			}
			if(foreign) {
// if(foreign) print("ABXRET 3 %s\n", curtext->from.sym->name);
#define	R	1
				p->as = AMOVW;
				p->from.type = D_OREG;
				p->from.name = D_NONE;
				p->from.reg = REGSP;
				p->from.offset = 0;
				p->to.type = D_REG;
				p->to.reg = R;
				q = prg();
				q->as = AADD;
				q->scond = p->scond;
				q->line = p->line;
				q->from.type = D_CONST;
				q->from.offset = autosize;
				q->to.type = D_REG;
				q->to.reg = REGSP;
				q->link = p->link;
				p->link = q;
				q1 = prg();
				q1->as = ABXRET;
				q1->scond = p->scond;
				q1->line = p->line;
				q1->to.type = D_OREG;
				q1->to.offset = 0;
				q1->to.reg = R;
				q1->link = q->link;
				q->link = q1;
#undef	R
			}
			else {
				p->as = AMOVW;
				p->scond |= C_PBIT;
				p->from.type = D_OREG;
				p->from.offset = autosize;
				p->from.reg = REGSP;
				p->to.type = D_REG;
				p->to.reg = REGPC;
			}
			break;

		become:
			if(foreign){
				diag("foreign become - help");
				break;
			}
			if(thumb){
				diag("thumb become - help");
				break;
			}
			print("arm become\n");
			if(curtext->mark & LEAF) {

				if(!autosize) {
					p->as = AB;
					p->from = zprg.from;
					break;
				}

#ifdef optimise_time
				q = prg();
				q->scond = p->scond;
				q->line = p->line;
				q->as = AB;
				q->from = zprg.from;
				q->to = p->to;
				q->cond = p->cond;
				q->link = p->link;
				p->link = q;

				p->as = AADD;
				p->from = zprg.from;
				p->from.type = D_CONST;
				p->from.offset = autosize;
				p->to = zprg.to;
				p->to.type = D_REG;
				p->to.reg = REGSP;

				break;
#endif
			}
			q = prg();
			q->scond = p->scond;
			q->line = p->line;
			q->as = AB;
			q->from = zprg.from;
			q->to = p->to;
			q->cond = p->cond;
			q->link = p->link;
			p->link = q;
			if(thumb){
				q1 = prg();
				q1->line = p->line;
				q1->as = AADD;
				q1->from.type = D_CONST;
				q1->from.offset = autosize;
				q1->to.type = D_REG;
				q1->to.reg = REGSP;
				p->as = AMOVW;
				p->line = p->line;
				p->from.type = D_OREG;
				p->from.name = D_NONE;
				p->from.reg = REGSP;
				p->from.offset = 0;
				p->to.type = D_REG;
				p->to.reg = REGTMPT-1;
				q1->link = q;
				p->link = q1;
				q2 = movrr(nil, REGTMPT-1, REGLINK, p);
				q2->link = q;
				q1->link = q2;
				break;
			}
			p->as = AMOVW;
			p->scond |= C_PBIT;
			p->from = zprg.from;
			p->from.type = D_OREG;
			p->from.offset = autosize;
			p->from.reg = REGSP;
			p->to = zprg.to;
			p->to.type = D_REG;
			p->to.reg = REGLINK;

			break;

		case AMOVW:
			if(thumb){
				Adr *a = &p->from;

				if(a->type == D_CONST && ((a->name == D_NONE && a->reg == REGSP) || a->name == D_AUTO || a->name == D_PARAM) && (a->offset & 3))
					diag("SP offset not multiple of 4");
			}
			break;
		case AMOVB:
		case AMOVBU:
		case AMOVH:
		case AMOVHU:
			if(thumb){
				if(p->from.type == D_OREG && (p->from.name == D_AUTO || p->from.name == D_PARAM || (p->from.name == D_CONST && p->from.reg == REGSP))){
					q = prg();
					*q = *p;
					if(p->from.name == D_AUTO)
						q->from.offset += autosize;
					else if(p->from.name == D_PARAM)
						q->from.offset += autosize+4;
					q->from.name = D_NONE;
					q->from.reg = REGTMPT;
					p = movrr(p, REGSP, REGTMPT, p);
					q->link = p->link;
					p->link = q;
				}
				if(p->to.type == D_OREG && (p->to.name == D_AUTO || p->to.name == D_PARAM || (p->to.name == D_CONST && p->to.reg == REGSP))){
					q = prg();
					*q = *p;
					if(p->to.name == D_AUTO)
						q->to.offset += autosize;
					else if(p->to.name == D_PARAM)
						q->to.offset += autosize+4;
					q->to.name = D_NONE;
					q->to.reg = REGTMPT;
					p = movrr(p, REGSP, REGTMPT, p);
					q->link = p->link;
					p->link = q;
					if(q->to.offset < 0 || q->to.offset > 255){	// complicated
						p->to.reg = REGTMPT+1;			// mov sp, r8
						q1 = prg();
						q1->line = p->line;
						q1->as = AMOVW;
						q1->from.type = D_CONST;
						q1->from.offset = q->to.offset;
						q1->to.type = D_REG;
						q1->to.reg = REGTMPT;			// mov $o, r7
						p->link = q1;
						q1->link = q;
						q1 = prg();
						q1->line = p->line;
						q1->as = AADD;
						q1->from.type = D_REG;
						q1->from.reg = REGTMPT+1;
						q1->to.type = D_REG;
						q1->to.reg = REGTMPT;			// add r8, r7
						p->link->link = q1;
						q1->link = q;
						q->to.offset = 0;				// mov* r, 0(r7)
						/* phew */
					}
				}
			}
			break;
		case AMOVM:
			if(thumb){
				if(p->from.type == D_OREG){
					if(p->from.offset == 0)
						p->from.type = D_REG;
					else
						diag("non-zero AMOVM offset");
				}
				else if(p->to.type == D_OREG){
					if(p->to.offset == 0)
						p->to.type = D_REG;
					else
						diag("non-zero AMOVM offset");
				}
			}
			break;
		case AB:
			if(thumb && p->to.type == D_OREG){
				if(p->to.offset == 0){
					p->as = AMOVW;
					p->from.type = D_REG;
					p->from.reg = p->to.reg;
					p->to.type = D_REG;
					p->to.reg = REGPC;
				}
				else{
					p->as = AADD;
					p->from.type = D_CONST;
					p->from.offset = p->to.offset;
					p->reg = p->to.reg;
					p->to.type = D_REG;
					p->to.reg = REGTMPT-1;
					q = prg();
					q->as = AMOVW;
					q->line = p->line;
					q->from.type = D_REG;
					q->from.reg = REGTMPT-1;
					q->to.type = D_REG;
					q->to.reg = REGPC;
					q->link = p->link;
					p->link = q;
				}
			}
			if(seenthumb && !thumb && p->to.type == D_OREG && p->to.reg == REGLINK){	
				// print("warn %s:	b	(R%d)	assuming a return\n", curtext->from.sym->name, p->to.reg);
				p->as = ABXRET;
			}
			break;
		case ABL:
		case ABX:
			if(thumb && p->to.type == D_OREG){
				if(p->to.offset == 0){
					p->as = o;
					p->from.type = D_NONE;
					p->to.type = D_REG;
				}
				else{
					p->as = AADD;
					p->from.type = D_CONST;
					p->from.offset = p->to.offset;
					p->reg = p->to.reg;
					p->to.type = D_REG;
					p->to.reg = REGTMPT-1;
					q = prg();
					q->as = o;
					q->line = p->line;
					q->from.type = D_NONE;
					q->to.type = D_REG;
					q->to.reg = REGTMPT-1;
					q->link = p->link;
					p->link = q;
				}
			}
			break;
		}
	}
}

void
nocache(Prog *p)
{
	p->optab = 0;
	p->from.class = 0;
	p->to.class = 0;
}
