#include "cc.h"

void
evconst(Node *n)
{
	Node *l, *r;
	int et, isf;
	vlong v;
	double d;

	if(n == Z || n->type == T)
		return;

	et = n->type->etype;
	isf = typefd[et];

	l = n->left;
	r = n->right;

	d = 0;
	v = 0;

	switch(n->op) {
	default:
		return;

	case OCAST:
		if(et == TVOID)
			return;
		et = l->type->etype;
		if(isf) {
			if(typefd[et])
				d = l->fconst;
			else
				d = l->vconst;
		} else {
			if(typefd[et])
				v = l->fconst;
			else
				v = convvtox(l->vconst, n->type->etype);
		}
		break;

	case OCONST:
		break;

	case OADD:
		if(isf)
			d = l->fconst + r->fconst;
		else {
			v = l->vconst + r->vconst;
		}
		break;

	case OSUB:
		if(isf)
			d = l->fconst - r->fconst;
		else
			v = l->vconst - r->vconst;
		break;

	case OMUL:
		if(isf)
			d = l->fconst * r->fconst;
		else {
			v = l->vconst * r->vconst;
		}
		break;

	case OLMUL:
		v = (uvlong)l->vconst * (uvlong)r->vconst;
		break;


	case ODIV:
		if(vconst(r) == 0) {
			warn(n, "divide by zero");
			return;
		}
		if(isf)
			d = l->fconst / r->fconst;
		else
			v = l->vconst / r->vconst;
		break;

	case OLDIV:
		if(vconst(r) == 0) {
			warn(n, "divide by zero");
			return;
		}
		v = (uvlong)l->vconst / (uvlong)r->vconst;
		break;

	case OMOD:
		if(vconst(r) == 0) {
			warn(n, "modulo by zero");
			return;
		}
		v = l->vconst % r->vconst;
		break;

	case OLMOD:
		if(vconst(r) == 0) {
			warn(n, "modulo by zero");
			return;
		}
		v = (uvlong)l->vconst % (uvlong)r->vconst;
		break;

	case OAND:
		v = l->vconst & r->vconst;
		break;

	case OOR:
		v = l->vconst | r->vconst;
		break;

	case OXOR:
		v = l->vconst ^ r->vconst;
		break;

	case OLSHR:
		v = (uvlong)l->vconst >> r->vconst;
		break;

	case OASHR:
		v = l->vconst >> r->vconst;
		break;

	case OASHL:
		v = l->vconst << r->vconst;
		break;

	case OLO:
		v = (uvlong)l->vconst < (uvlong)r->vconst;
		break;

	case OLT:
		if(typefd[l->type->etype])
			v = l->fconst < r->fconst;
		else
			v = l->vconst < r->vconst;
		break;

	case OHI:
		v = (uvlong)l->vconst > (uvlong)r->vconst;
		break;

	case OGT:
		if(typefd[l->type->etype])
			v = l->fconst > r->fconst;
		else
			v = l->vconst > r->vconst;
		break;

	case OLS:
		v = (uvlong)l->vconst <= (uvlong)r->vconst;
		break;

	case OLE:
		if(typefd[l->type->etype])
			v = l->fconst <= r->fconst;
		else
			v = l->vconst <= r->vconst;
		break;

	case OHS:
		v = (uvlong)l->vconst >= (uvlong)r->vconst;
		break;

	case OGE:
		if(typefd[l->type->etype])
			v = l->fconst >= r->fconst;
		else
			v = l->vconst >= r->vconst;
		break;

	case OEQ:
		if(typefd[l->type->etype])
			v = l->fconst == r->fconst;
		else
			v = l->vconst == r->vconst;
		break;

	case ONE:
		if(typefd[l->type->etype])
			v = l->fconst != r->fconst;
		else
			v = l->vconst != r->vconst;
		break;

	case ONOT:
		if(typefd[l->type->etype])
			v = !l->fconst;
		else
			v = !l->vconst;
		break;

	case OANDAND:
		if(typefd[l->type->etype])
			v = l->fconst && r->fconst;
		else
			v = l->vconst && r->vconst;
		break;

	case OOROR:
		if(typefd[l->type->etype])
			v = l->fconst || r->fconst;
		else
			v = l->vconst || r->vconst;
		break;

	case OPOS:
		if(isf)
			d = l->fconst;
		else
			v = l->vconst;
		break;

	case ONEG:
		if(isf)
			d = -l->fconst;
		else
			v = -l->vconst;
		break;

	case OCOM:
		if(typefd[l->type->etype])
			v = 0;	/* ~l->fconst */
		else
			v = ~l->vconst;
		break;
	}

	n->left = ncopy(n);
	n->op = OCONST;
	/* n->left = Z; */
	n->right = Z;
	if(isf) {
		n->fconst = d;
	} else {
		n->vconst = convvtox(v, n->type->etype);
	}
}

void
acom(Node *n)
{
	USED(n);
}
