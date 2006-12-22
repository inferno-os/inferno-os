#include "lib9.h"
#include "isa.h"
#include "interp.h"
#include "mathi.h"

enum
{
	TOKI0,
	TOKI1,
	TOKI2,
	TOKI3,
	TOKSB,
	TOKFP
};
#include "tab.h"

typedef struct Addr	Addr;
struct Addr
{
	uchar	mode;
	Adr	a;
};

#pragma	varargck	type	"a"	Addr*

char*	opnam[256];
int	iconv(Fmt*);
int	aconv(Fmt*);

int
aconv(Fmt *f)
{
	Addr *a;
	char buf[64];

	a = va_arg(f->args, Addr*);
	if(a == nil)
		return fmtstrcpy(f, "AZ");
	switch(a->mode & AMASK) {
	case AFP:	sprint(buf, "%d(fp)", a->a.ind);	break;
	case AMP:	sprint(buf, "%d(mp)", a->a.ind);	break;
	case AIMM:	sprint(buf, "$%d", a->a.imm);		break;
	case AIND|AFP:	sprint(buf, "%d(%d(fp))", a->a.i.s, a->a.i.f); break;
	case AIND|AMP:	sprint(buf, "%d(%d(mp))", a->a.i.s, a->a.i.f); break;
	}
	return fmtstrcpy(f, buf);
}

int
Dconv(Fmt *f)
{
	int j;
	Inst *i;
	Addr s, d;
	char buf[128];
	static int init;

	if(init == 0) {
		for(j = 0; keywds[j].name != nil; j++)
			opnam[keywds[j].op] = keywds[j].name;

		fmtinstall('a', aconv);
		init = 1;
	}

	i = va_arg(f->args, Inst*);
	if(i == nil)
		return fmtstrcpy(f, "IZ");

	switch(keywds[i->op].terminal) {
	case TOKI0:
		sprint(buf, "%s", opnam[i->op]);
		break;
	case TOKI1:
		d.a = i->d;
		d.mode = UDST(i->add);
		sprint(buf, "%s\t%a", opnam[i->op], &d);
		break;
	case TOKI3:
		d.a = i->d;
		d.mode = UDST(i->add);
		s.a = i->s;
		s.mode = USRC(i->add);
		switch(i->add&ARM) {
		default:
			sprint(buf, "%s\t%a, %a", opnam[i->op], &s, &d);
			break;
		case AXIMM:
			sprint(buf, "%s\t%a, $%d, %a", opnam[i->op], &s, i->reg, &d);
			break;
		case AXINF:
			sprint(buf, "%s\t%a, %d(fp), %a", opnam[i->op], &s, i->reg, &d);
			break;
		case AXINM:
			sprint(buf, "%s\t%a, %d(mp), %a", opnam[i->op], &s, i->reg, &d);
			break;
		}
		break;
	case TOKI2:
		d.a = i->d;
		d.mode = UDST(i->add);
		s.a = i->s;
		s.mode = USRC(i->add);
		sprint(buf, "%s\t%a, %a", opnam[i->op], &s, &d);
		break;
	}

	return fmtstrcpy(f, buf);
}

