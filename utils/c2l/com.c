#include "cc.h"

void
complex(Node *n)
{

	if(n == Z)
		return;

	nearln = n->lineno;
	if(tcom(n))
		return;
	ccom(n);
	acom(n);
}

/*
 * evaluate types
 * evaluate lvalues (addable == 1)
 */
enum
{
	ADDROF	= 1<<0,
	CASTOF	= 1<<1,
	ADDROP	= 1<<2,
};

int
tcom(Node *n)
{

	return tcomo(n, ADDROF);
}

int
tcomo(Node *n, int f)
{
	Node *l, *r;
	Type *t;
	int o;

	if(n == Z) {
		diag(Z, "Z in tcom");
		errorexit();
	}
	l = n->left;
	r = n->right;
		
	switch(n->op) {
	default:
		diag(n, "unknown op in type complex: %O", n->op);
		goto bad;

	case ODOTDOT:
		/*
		 * tcom has already been called on this subtree
		 */
		*n = *n->left;
		if(n->type == T)
			goto bad;
		break;

	case OCAST:
		if(n->type == T)
			break;
		if(n->type->width == types[TLONG]->width) {
			if(tcomo(l, ADDROF|CASTOF))
					goto bad;
		} else
			if(tcom(l))
				goto bad;
		if(tcompat(n, l->type, n->type, tcast))
			goto bad;
		break;

	case ORETURN:
		if(l == Z) {
			if(n->type->etype != TVOID)
				warn(n, "null return of a typed function");
			break;
		}
		if(tcom(l))
			goto bad;
		typeext(n->type, l);
		if(tcompat(n, n->type, l->type, tasign))
			break;
		constas(n, n->type, l->type);
		if(!sametype(n->type, l->type)) {
			l = new1(OCAST, l, Z);
			l->type = n->type;
			n->left = l;
		}
		break;

	case OASI:	/* same as as, but no test for const */
		n->op = OAS;
		o = tcom(l);
		if(o | tcom(r))
			goto bad;

		typeext(l->type, r);
		if(tlvalue(l) || tcompat(n, l->type, r->type, tasign))
			goto bad;
		if(!sametype(l->type, r->type)) {
			r = new1(OCAST, r, Z);
			r->type = l->type;
			n->right = r;
		}
		n->type = l->type;
		break;

	case OAS:
	case OASD:
		o = tcom(l);
		if(o | tcom(r))
			goto bad;

		typeext(l->type, r);
		if(tlvalue(l) || tcompat(n, l->type, r->type, tasign))
			goto bad;
		constas(n, l->type, r->type);
		if(!sametype(l->type, r->type)) {
			r = new1(OCAST, r, Z);
			r->type = l->type;
			n->right = r;
		}
		n->type = l->type;
		break;

	case OASADD:
	case OASSUB:
		o = tcom(l);
		if(o | tcom(r))
			goto bad;
		typeext1(l->type, r);
		if(tlvalue(l) || tcompat(n, l->type, r->type, tasadd))
			goto bad;
		constas(n, l->type, r->type);
		t = l->type;
		arith(n, 0);
		while(n->left->op == OCAST)
			n->left = n->left->left;
		if(!sametype(t, n->type)) {
			r = new1(OCAST, n->right, Z);
			r->type = t;
			n->right = r;
			n->type = t;
		}
		break;

	case OASMUL:
	case OASLMUL:
	case OASDIV:
	case OASLDIV:
		o = tcom(l);
		if(o | tcom(r))
			goto bad;
		typeext1(l->type, r);
		if(tlvalue(l) || tcompat(n, l->type, r->type, tmul))
			goto bad;
		constas(n, l->type, r->type);
		t = l->type;
		arith(n, 0);
		while(n->left->op == OCAST)
			n->left = n->left->left;
		if(!sametype(t, n->type)) {
			r = new1(OCAST, n->right, Z);
			r->type = t;
			n->right = r;
			n->type = t;
		}
		if(typeu[n->type->etype]) {
			if(n->op == OASDIV)
				n->op = OASLDIV;
			if(n->op == OASMUL)
				n->op = OASLMUL;
		}
		break;

	case OASLSHR:
	case OASASHR:
	case OASASHL:
		o = tcom(l);
		if(o | tcom(r))
			goto bad;
		if(tlvalue(l) || tcompat(n, l->type, r->type, tand))
			goto bad;
		n->type = l->type;
		if(typeu[n->type->etype]) {
			if(n->op == OASASHR)
				n->op = OASLSHR;
		}
		break;

	case OASMOD:
	case OASLMOD:
	case OASOR:
	case OASAND:
	case OASXOR:
		o = tcom(l);
		if(o | tcom(r))
			goto bad;
		if(tlvalue(l) || tcompat(n, l->type, r->type, tand))
			goto bad;
		t = l->type;
		arith(n, 0);
		while(n->left->op == OCAST)
			n->left = n->left->left;
		if(!sametype(t, n->type)) {
			r = new1(OCAST, n->right, Z);
			r->type = t;
			n->right = r;
			n->type = t;
		}
		if(typeu[n->type->etype]) {
			if(n->op == OASMOD)
				n->op = OASLMOD;
		}
		break;

	case OPREINC:
	case OPREDEC:
	case OPOSTINC:
	case OPOSTDEC:
		if(tcom(l))
			goto bad;
		if(tlvalue(l) || tcompat(n, l->type, types[TINT], tadd))
			goto bad;
		n->type = l->type;
		if(n->type->etype == TIND)
		if(n->type->link->width < 1)
			diag(n, "inc/dec of a void pointer");
		break;

	case OEQ:
	case ONE:
		o = tcom(l);
		if(o | tcom(r))
			goto bad;
		typeext(l->type, r);
		typeext(r->type, l);
		if(tcompat(n, l->type, r->type, trel))
			goto bad;
		arith(n, 0);
		n->type = types[TINT];
		break;

	case OLT:
	case OGE:
	case OGT:
	case OLE:
		o = tcom(l);
		if(o | tcom(r))
			goto bad;
		typeext1(l->type, r);
		typeext1(r->type, l);
		if(tcompat(n, l->type, r->type, trel))
			goto bad;
		arith(n, 0);
		if(typeu[n->type->etype])
			n->op = logrel[relindex(n->op)];
		n->type = types[TINT];
		break;

	case OCOND:
		o = tcom(l);
		o |= tcom(r->left);
		if(o | tcom(r->right))
			goto bad;
		if(r->right->type->etype == TIND && vconst(r->left) == 0) {
			r->left->type = r->right->type;
			r->left->vconst = 0;
		}
		if(r->left->type->etype == TIND && vconst(r->right) == 0) {
			r->right->type = r->left->type;
			r->right->vconst = 0;
		}
		if(sametype(r->right->type, r->left->type)) {
			r->type = r->right->type;
			n->type = r->type;
			break;
		}
		if(tcompat(r, r->left->type, r->right->type, trel))
			goto bad;
		arith(r, 0);
		n->type = r->type;
		break;

	case OADD:
		o = tcom(l);
		if(o | tcom(r))
			goto bad;
		if(tcompat(n, l->type, r->type, tadd))
			goto bad;
		arith(n, 1);
		break;

	case OSUB:
		o = tcom(l);
		if(o | tcom(r))
			goto bad;
		if(tcompat(n, l->type, r->type, tsub))
			goto bad;
		arith(n, 1);
		break;

	case OMUL:
	case OLMUL:
	case ODIV:
	case OLDIV:
		o = tcom(l);
		if(o | tcom(r))
			goto bad;
		if(tcompat(n, l->type, r->type, tmul))
			goto bad;
		arith(n, 1);
		if(typeu[n->type->etype]) {
			if(n->op == ODIV)
				n->op = OLDIV;
			if(n->op == OMUL)
				n->op = OLMUL;
		}
		break;

	case OLSHR:
	case OASHL:
	case OASHR:
		o = tcom(l);
		if(o | tcom(r))
			goto bad;
		if(tcompat(n, l->type, r->type, tand))
			goto bad;
		n->right = Z;
		arith(n, 1);
		n->right = new1(OCAST, r, Z);
		n->right->type = types[TINT];
		if(typeu[n->type->etype])
			if(n->op == OASHR)
				n->op = OLSHR;
		break;

	case OAND:
	case OOR:
	case OXOR:
		o = tcom(l);
		if(o | tcom(r))
			goto bad;
		if(tcompat(n, l->type, r->type, tand))
			goto bad;
		arith(n, 1);
		break;

	case OMOD:
	case OLMOD:
		o = tcom(l);
		if(o | tcom(r))
			goto bad;
		if(tcompat(n, l->type, r->type, tand))
			goto bad;
		arith(n, 1);
		if(typeu[n->type->etype])
			n->op = OLMOD;
		break;

	case ONOT:
		if(tcom(l))
			goto bad;
		if(tcompat(n, T, l->type, tnot))
			goto bad;
		n->type = types[TINT];
		break;

	case OPOS:
	case ONEG:
	case OCOM:
		if(tcom(l))
			goto bad; 
		n->type = l->type;
		break;

	case ONUL:
		break;

	case OIOTA:
		n->type = types[TINT];
		break;

	case ODAS:
		n->type = n->left->type;
		break;

	case OANDAND:
	case OOROR:
		o = tcom(l);
		if(o | tcom(r))
			goto bad;
		if(tcompat(n, T, l->type, tnot) |
		   tcompat(n, T, r->type, tnot))
			goto bad;
		n->type = types[TINT];
		break;

	case OCOMMA:
		o = tcom(l);
		if(o | tcom(r))
			goto bad;
		n->type = r->type;
		break;


	case OSIGN:	/* extension signof(type) returns a hash */
		if(l != Z) {
			if(l->op != OSTRING && l->op != OLSTRING)
				if(tcomo(l, 0))
					goto bad;
			if(l->op == OBIT) {
				diag(n, "signof bitfield");
				goto bad;
			}
			n->type = l->type;
		}
		if(n->type == T)
			goto bad;
		if(n->type->width < 0) {
			diag(n, "signof undefined type");
			goto bad;
		}
		n->right = ncopy(n);
		n->op = OCONST;
		n->left = Z;
		/* n->right = Z; */
		n->vconst = convvtox(signature(n->type, 10), TULONG);
		n->type = types[TULONG];
		break;

	case OSIZE:
		if(l != Z) {
			if(l->op != OSTRING && l->op != OLSTRING)
				if(tcomo(l, 0))
					goto bad;
			if(l->op == OBIT) {
				diag(n, "sizeof bitfield");
				goto bad;
			}
			n->type = l->type;
		}
		if(n->type == T)
			goto bad;
		if(n->type->width <= 0) {
			diag(n, "sizeof undefined type");
			goto bad;
		}
		if(n->type->etype == TFUNC) {
			diag(n, "sizeof function");
			goto bad;
		}
		n->right = ncopy(n);
		n->op = OCONST;
		n->left = Z;
		/* n->right = Z; */
		n->vconst = convvtox(n->type->width, TINT);
		n->type = types[TINT];
		break;

	case OFUNC:
		o = tcomo(l, 0);
		if(o)
			goto bad;
		if(l->type->etype == TIND && l->type->link->etype == TFUNC) {
			l = new1(OIND, l, Z);
			l->type = l->left->type->link;
			n->left = l;
		}
		if(tcompat(n, T, l->type, tfunct))
			goto bad;
		if(o | tcoma(l, r, l->type->down, 1))
			goto bad;
		n->type = l->type->link;
		if(1)
			if(l->type->down == T || l->type->down->etype == TOLD) {
				nerrors--;
				diag(n, "function args not checked: %F", l);
			}
		dpcheck(n);
		break;

	case ONAME:
		if(n->type == T) {
			diag(n, "name not declared: %F", n);
			goto bad;
		}
		if(n->type->etype == TENUM) {
			if(n->sym->tenum->etype == TIND){
				/* n->op = OSTRING; */
				n->type = n->sym->tenum;
				/* n->cstring = n->sym->sconst; */
				break;
			}
			n->left = ncopy(n);
			n->op = OCONST;
			n->type = n->sym->tenum;
			if(!typefd[n->type->etype])
				n->vconst = n->sym->vconst;
			else{
				n->fconst = n->sym->fconst;
				n->cstring = n->sym->cstring;
			}
			break;
		}
		break;

	case OLSTRING:
	case OSTRING:
	case OCONST:
		break;

	case ODOT:
		if(tcom(l))
			goto bad;
		if(tcompat(n, T, l->type, tdot))
			goto bad;
		if(tcomd(n, l->type))
			goto bad;
		break;

	case ODOTIND:
		if(tcom(l))
			goto bad;
		if(tcompat(n, T, l->type, tindir))
			goto bad;
		if(tcompat(n, T, l->type->link, tdot))
			goto bad;
		if(tcomd(n, l->type->link))
			goto bad;
		break;
		
	case OARRIND:
		if(tcom(l))
			goto bad;
		if(tcompat(n, T, l->type, tindir))
			goto bad;
		n->type = l->type->link;
		if(tcom(r))
			goto bad;
		break;

	case OADDR:
		if(tcomo(l, ADDROP))
			goto bad;
		if(tlvalue(l))
			goto bad;
		if(l->type->nbits) {
			diag(n, "address of a bit field");
			goto bad;
		}
		if(l->op == OREGISTER) {
			diag(n, "address of a register");
			goto bad;
		}
		n->type = typ1(TIND, l->type);
		n->type->width = types[TIND]->width;
		break;

	case OIND:
		if(tcom(l))
			goto bad;
		if(tcompat(n, T, l->type, tindir))
			goto bad;
		n->type = l->type->link;
		break;

	case OSTRUCT:
		if(tcomx(n))
			goto bad;
		break;
	}
	t = n->type;
	if(t == T)
		goto bad;
	if(t->width < 0) {
		snap(t);
		if(t->width < 0) {
			if(typesu[t->etype] && t->tag)
				diag(n, "structure not fully declared %s", t->tag->name);
			else
				diag(n, "structure not fully declared");
			goto bad;
		}
	}
	if(typeaf[t->etype]) {
		if(f & ADDROF)
			goto addaddr;
		if(f & ADDROP)
			warn(n, "address of array/func ignored");
	}
	return 0;

addaddr:
	if(n->type->etype == TARRAY)
		n->type = typ1(TIND, n->type->link);
	return 0;
	if(tlvalue(n))
		goto bad;
	l = new1(OXXX, Z, Z);
	*l = *n;
	n->op = OADDR;
	if(l->type->etype == TARRAY)
		l->type = l->type->link;
	n->left = l;
	n->right = Z;
	n->type = typ1(TIND, l->type);
	n->type->width = types[TIND]->width;
	return 0;

bad:
	n->type = T;
	return 1;
}

int
tcoma(Node *l, Node *n, Type *t, int f)
{
	Node *n1;
	int o;

	if(t != T)
	if(t->etype == TOLD || t->etype == TDOT)	/* .../old in prototype */
		t = T;
	if(n == Z) {
		if(t != T && !sametype(t, types[TVOID])) {
			diag(n, "not enough function arguments: %F", l);
			return 1;
		}
		return 0;
	}
	if(n->op == OLIST) {
		o = tcoma(l, n->left, t, 0);
		if(t != T) {
			t = t->down;
			if(t == T)
				t = types[TVOID];
		}
		return o | tcoma(l, n->right, t, 1);
	}
	if(f && t != T)
		tcoma(l, Z, t->down, 0);
	if(tcom(n) || tcompat(n, T, n->type, targ))
		return 1;
	if(sametype(t, types[TVOID])) {
		diag(n, "too many function arguments: %F", l);
		return 1;
	}
	if(t != T) {
		typeext(t, n);
		if(stcompat(nodproto, t, n->type, tasign)) {
			diag(l, "argument prototype mismatch \"%T\" for \"%T\": %F",
				n->type, t, l);
			return 1;
		}
		switch(t->etype) {
		case TCHAR:
		case TSHORT:
			/* t = types[TINT]; */
			break;

		case TUCHAR:
		case TUSHORT:
			/* t = types[TUINT]; */
			break;
		}
	} else {
		switch(n->type->etype)
		{
		case TCHAR:
		case TSHORT:
			/* t = types[TINT]; */
			t = n->type;
			break;

		case TUCHAR:
		case TUSHORT:
			/* t = types[TUINT]; */
			t = n->type;
			break;

		case TFLOAT:
			/* t = types[TDOUBLE]; */
			t = n->type;
		}
	}
	if(t != T && !sametype(t, n->type)) {
		n1 = new1(OXXX, Z, Z);
		*n1 = *n;
		n->op = OCAST;
		n->left = n1;
		n->right = Z;
		n->type = t;
	}
	return 0;
}

int
tcomd(Node *n, Type *t)
{
	long o;

	o = 0;
	/* t = n->left->type; */
	for(;;) {
		t = dotsearch(n->sym, t->link, n);
		if(t == T) {
			diag(n, "not a member of struct/union: %F", n);
			return 1;
		}
		o += t->offset;
		if(t->sym == n->sym)
			break;
		if(sametype(t, n->sym->type))
			break;
	}
	n->type = t;
	return 0;
}

int
tcomx(Node *n)
{
	Type *t;
	Node *l, *r, **ar, **al;
	int e;

	e = 0;
	if(n->type->etype != TSTRUCT) {
		diag(n, "constructor must be a structure");
		return 1;
	}
	l = invert(n->left);
	n->left = l;
	al = &n->left;
	for(t = n->type->link; t != T; t = t->down) {
		if(l == Z) {
			diag(n, "constructor list too short");
			return 1;
		}
		if(l->op == OLIST) {
			r = l->left;
			ar = &l->left;
			al = &l->right;
			l = l->right;
		} else {
			r = l;
			ar = al;
			l = Z;
		}
		if(tcom(r))
			e++;
		typeext(t, r);
		if(tcompat(n, t, r->type, tasign))
			e++;
		constas(n, t, r->type);
		if(!e && !sametype(t, r->type)) {
			r = new1(OCAST, r, Z);
			r->type = t;
			*ar = r;
		}
	}
	if(l != Z) {
		diag(n, "constructor list too long");
		return 1;
	}
	return e;
}

int
tlvalue(Node *n)
{

	if(0) {
		diag(n, "not an l-value");
		return 1;
	}
	return 0;
}

/*
 *	general rewrite
 *	(IND(ADDR x)) ==> x
 *	(ADDR(IND x)) ==> x
 *	remove some zero operands
 *	remove no op casts
 *	evaluate constants
 */
void
ccom(Node *n)
{
	Node *l, *r;
	int t;

	if(n == Z)
		return;
	l = n->left;
	r = n->right;
	switch(n->op) {

	case OAS:
	case OASD:
	case OASXOR:
	case OASAND:
	case OASOR:
	case OASMOD:
	case OASLMOD:
	case OASLSHR:
	case OASASHR:
	case OASASHL:
	case OASDIV:
	case OASLDIV:
	case OASMUL:
	case OASLMUL:
	case OASSUB:
	case OASADD:
		ccom(l);
		ccom(r);
		if(n->op == OASLSHR || n->op == OASASHR || n->op == OASASHL)
		if(r->op == OCONST) {
			t = n->type->width * 8;	/* bits per byte */
			if(r->vconst >= t || r->vconst < 0)
				warn(n, "stupid shift: %lld", r->vconst);
		}
		break;

	case OCAST:
		ccom(l);
		if(l->op == OCONST) {
			evconst(n);
			if(n->op == OCONST)
				break;
		}
		if(nocast(l->type, n->type)) {
			l->type = n->type;
			*n = *l;
		}
		break;

	case OCOND:
		ccom(l);
		ccom(r);
		break;

	case OREGISTER:
	case OINDREG:
	case OCONST:
	case ONAME:
		break;

	case OADDR:
		ccom(l);
		/* l->etype = TVOID; */
		if(l->op == OIND) {
			l->left->type = n->type;
			*n = *l->left;
			break;
		}
		goto common;

	case OIND:
		ccom(l);
		if(l->op == OADDR) {
			l->left->type = n->type;
			*n = *l->left;
			break;
		}
		goto common;

	case OEQ:
	case ONE:

	case OLE:
	case OGE:
	case OLT:
	case OGT:

	case OLS:
	case OHS:
	case OLO:
	case OHI:
		ccom(l);
		ccom(r);
		relcon(l, r);
		relcon(r, l);
		goto common;

	case OASHR:
	case OASHL:
	case OLSHR:
		ccom(l);
		ccom(r);
		if(r->op == OCONST) {
			t = n->type->width * 8;	/* bits per byte */
			if(r->vconst >= t || r->vconst <= -t)
				warn(n, "stupid shift: %lld", r->vconst);
		}
		goto common;

	default:
		if(l != Z)
			ccom(l);
		if(r != Z)
			ccom(r);
	common:
		if(l != Z)
		if(l->op != OCONST)
			break;
		if(r != Z)
		if(r->op != OCONST)
			break;
		evconst(n);
	}
}
