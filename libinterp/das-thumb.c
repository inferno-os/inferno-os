#include <lib9.h>

typedef struct	Instr	Instr;
struct	Instr
{
	ulong	w;
	ulong	addr;
	uchar	op;			/* super opcode */

	uchar	rd;
	uchar	rn;
	uchar	rs;

	long	imm;			/* imm */
	char*	curr;			/* fill point in buffer */
	char*	end;			/* end of buffer */
	char*	err;			/* error message */
};

typedef struct Opcode Opcode;
struct Opcode
{
	char*	o;
	void	(*f)(Opcode*, Instr*);
	int		unused;		/* remove field some time */
	char*	a;
};

static	void	format(char*, Instr*, char*);
static	int	thumbinst(ulong, char, char*, int);
static	int	thumbdas(ulong, char*, int);

static
char*	cond[16] =
{
	"EQ",	"NE",	"CS",	"CC",
	"MI",	"PL",	"VS",	"VC",
	"HI",	"LS",	"GE",	"LT",
	"GT",	"LE",	0,	"NV"
};

static int
get4(ulong addr, long *v)
{
	*v = *(ulong*)addr;
	return 1;	
}

static int
get2(ulong addr, ushort *v)
{
	*v = *(ushort*)addr;
	return 1;
}

static char *
_hexify(char *buf, ulong p, int zeros)
{
	ulong d;

	d = p/16;
	if(d)
		buf = _hexify(buf, d, zeros-1);
	else
		while(zeros--)
			*buf++ = '0';
	*buf++ = "0123456789abcdef"[p&0x0f];
	return buf;
}

#define B(h, l)		bits(ins, h, l)

static int
bits(int i, int h, int l)
{
	if(h < l)
		print("h < l in bits");
	return (i&(((1<<(h-l+1))-1)<<l))>>l;
}

int
thumbclass(long w)
{
	int o;
	int ins = w;

	if(ins&0xffff0000)
		return 3+2+2+4+16+4+1+8+6+2+2+2+4+1+1+1+2;
	o = B(15, 13);
	switch(o){
	case 0:
		o = B(12, 11);
		switch(o){
			case 0:
			case 1:
			case 2:
				return B(12, 11);
			case 3:
				if(B(10, 10) == 0)
					return 3+B(9, 9);
				else
					return 3+2+B(9, 9);
		}
	case 1:
		return 3+2+2+B(12, 11);
	case 2:
		o = B(12, 10);
		if(o == 0)
			return 3+2+2+4+B(9, 6);
		if(o == 1){
			o = B(9, 8);
			if(o == 3)
				return 3+2+2+4+16+B(9, 8);
			return 3+2+2+4+16+B(9, 8);
		}
		if(o == 2 || o == 3)
			return 3+2+2+4+16+4;
		return 3+2+2+4+16+4+1+B(11, 9);
	case 3:
		return 3+2+2+4+16+4+1+8+B(12, 11);
	case 4:
		if(B(12, 12) == 0)
			return 3+2+2+4+16+4+1+8+4+B(11, 11);
		return 3+2+2+4+16+4+1+8+6+B(11, 11);
	case 5:
		if(B(12, 12) == 0)
			return 3+2+2+4+16+4+1+8+6+2+B(11, 11);
		if(B(11, 8) == 0)
			return 3+2+2+4+16+4+1+8+6+2+2+B(7, 7);
		return 3+2+2+4+16+4+1+8+6+2+2+2+B(11, 11);
	case 6:
		if(B(12, 12) == 0)
			return 3+2+2+4+16+4+1+8+6+2+2+2+2+B(11, 11);
		if(B(11, 8) == 0xf)
			return 3+2+2+4+16+4+1+8+6+2+2+2+4;
		return 3+2+2+4+16+4+1+8+6+2+2+2+4+1;
	case 7:
		o = B(12, 11);
		switch(o){
			case 0:
				return 3+2+2+4+16+4+1+8+6+2+2+2+4+1+1;
			case 1:
				return 3+2+2+4+16+4+1+8+6+2+2+2+4+1+1+1+2;
			case 2:
				return 3+2+2+4+16+4+1+8+6+2+2+2+4+1+1+1;
			case 3:
				return 3+2+2+4+16+4+1+8+6+2+2+2+4+1+1+1+1;
		}
	}
}

static int
decode(ulong pc, Instr *i)
{
	ushort w;

	get2(pc, &w);
	i->w = w;
	i->addr = pc;
	i->op = thumbclass(w);
	return 1;
}

static void
bprint(Instr *i, char *fmt, ...)
{
	va_list arg;

	va_start(arg, fmt);
	i->curr = vseprint(i->curr, i->end, fmt, arg);
	va_end(arg);
}

static void
thumbshift(Opcode *o, Instr *i)
{
	int ins = i->w;

	i->rd = B(2, 0);
	i->rn = B(5, 3);
	i->imm = B(10, 6);
	format(o->o, i, o->a);
}

static void
thumbrrr(Opcode *o, Instr *i)
{
	int ins = i->w;

	i->rd = B(2, 0);
	i->rn = B(5, 3);
	i->rs = B(8, 6);
	format(o->o, i, o->a);
}

static void
thumbirr(Opcode *o, Instr *i)
{
	int ins = i->w;

	i->rd = B(2, 0);
	i->rn = B(5, 3);
	i->imm = B(8, 6);
	format(o->o, i, o->a);
}

static void
thumbir(Opcode *o, Instr *i)
{
	int ins = i->w;

	i->rd = B(10, 8);
	i->imm = B(7, 0);
	format(o->o, i, o->a);
}

static void
thumbrr(Opcode *o, Instr *i)
{
	int ins = i->w;

	i->rd = B(2, 0);
	i->rn = B(5, 3);
	format(o->o, i, o->a);
}

static void
thumbrrh(Opcode *o, Instr *i)
{
	int ins = i->w;

	i->rd = B(2, 0);
	i->rn = B(5, 3);
	if(B(6, 6))
		i->rn += 8;
	if(B(7, 7))
		i->rd += 8;
	if(o != nil){
		if(i->w == 0x46b7 || i->w == 0x46f7 || i->w == 0x4730 || i->w == 0x4770)	// mov r6, pc or mov lr, pc or bx r6 or bx lr
			format("RET", i, "");
		else
			format(o->o, i, o->a);
	}
}

static void
thumbpcrel(Opcode *o, Instr *i)
{
	int ins = i->w;

	i->rn = 15;
	i->rd = B(10, 8);
	i->imm = 4*(B(7, 0)+1);
	if(i->addr & 3)
		i->imm -= 2;
	format(o->o, i, o->a);
}

static void
thumbmovirr(Opcode *o, Instr *i)
{
	int ins = i->w;

	i->rd = B(2, 0);
	i->rn = B(5, 3);
	i->imm = B(10, 6);
	if(strcmp(o->o, "MOVW") == 0)
		i->imm *= 4;
	else if(strncmp(o->o, "MOVH", 4) == 0)
		i->imm *= 2;
	format(o->o, i, o->a);
}

static void
thumbmovsp(Opcode *o, Instr *i)
{
	int ins = i->w;

	i->rn = 13;
	i->rd = B(10, 8);
	i->imm = 4*B(7, 0);
	format(o->o, i, o->a);
}

static void
thumbaddsppc(Opcode *o, Instr *i)
{
	int ins = i->w;

	i->rd = B(10, 8);
	i->imm = 4*B(7, 0);
	if(i->op == 48)
		i->imm += 4;
	format(o->o, i, o->a);
}

static void
thumbaddsp(Opcode *o, Instr *i)
{
	int ins = i->w;

	i->imm = 4*B(6, 0);
	format(o->o, i, o->a);
}	

static void
thumbswi(Opcode *o, Instr *i)
{
	int ins = i->w;

	i->imm = B(7, 0);
	format(o->o, i, o->a);
}

static void
thumbbcc(Opcode *o, Instr *i)
{
	int off, ins = i->w;

	off = B(7, 0);
	if(off & 0x80)
		off |= 0xffffff00;
	i->imm = i->addr + 2*off + 4;
	if(o != nil)
		format(o->o, i, o->a);
}

static void
thumbb(Opcode *o, Instr *i)
{
	int off, ins = i->w;

	off = B(10, 0);
	if(off & 0x400)
		off |= 0xfffff800;
	i->imm = i->addr + 2*off + 4;
	if(o != nil)
		format(o->o, i, o->a);
}	

static void
thumbbl(Opcode *o, Instr *i)
{
	int off, h, ins = i->w;
	static int reglink;

	h = B(11, 11);
	off = B(10, 0);
	if(h == 0){
		if(off & 0x400)
			off |= 0xfffff800;
		i->imm = i->addr + (off<<12) + 4;
		reglink = i->imm;
	}
	else{
		i->imm = reglink + 2*off;
	}
	if(o != nil)
		format(o->o, i, o->a);
}	

static void
thumbregs(Opcode *o, Instr *i)
{
	int ins = i->w;

	if(i->op == 52 || i->op == 53)
		i->rd = 13;
	else
		i->rd = B(10, 8);
	i->imm = B(7, 0);
	format(o->o, i, o->a);
}

static void
thumbunk(Opcode *o, Instr *i)
{
	format(o->o, i, o->a);
}

static Opcode opcodes[] =
{
	"LSL",	thumbshift,	0,	"$#%i,R%n,R%d",	// 0
	"LSR",	thumbshift,	0,	"$#%i,R%n,R%d",	// 1
	"ASR",	thumbshift,	0,	"$#%i,R%n,R%d",	// 2
	"ADD",	thumbrrr,		0,	"R%s,R%n,R%d",		// 3
	"SUB",	thumbrrr,		0,	"R%s,R%n,R%d",		// 4
	"ADD",	thumbirr,		0,	"$#%i,R%n,R%d",	// 5
	"SUB",	thumbirr,		0,	"$#%i,R%n,R%d",	// 6
	"MOVW",	thumbir,		0,	"$#%i,R%d",		// 7
	"CMP",	thumbir,		0,	"$#%i,R%d",		// 8
	"ADD",	thumbir,		0,	"$#%i,R%d,R%d",	// 9
	"SUB",	thumbir,		0,	"$#%i,R%d,R%d",	// 10
	"AND",	thumbrr,		0,	"R%n,R%d,R%d",	// 11
	"EOR",	thumbrr,		0,	"R%n,R%d,R%d",	// 12
	"LSL",	thumbrr,		0,	"R%n,R%d,R%d",	// 13
	"LSR",	thumbrr,		0,	"R%n,R%d,R%d",	// 14
	"ASR",	thumbrr,		0,	"R%n,R%d,R%d",	// 15
	"ADC",	thumbrr,		0,	"R%n,R%d,R%d",	// 16
	"SBC",	thumbrr,		0,	"R%n,R%d,R%d",	// 17
	"ROR",	thumbrr,		0,	"R%n,R%d,R%d",	// 18
	"TST",	thumbrr,		0,	"R%n,R%d",		// 19
	"NEG",	thumbrr,		0,	"R%n,R%d",		// 20
	"CMP",	thumbrr,		0,	"R%n,R%d",		// 21
	"CMPN",	thumbrr,		0,	"R%n,R%d",		// 22
	"OR",	thumbrr,		0,	"R%n,R%d,R%d",	// 23
	"MUL",	thumbrr,		0,	"R%n,R%d,R%d",	// 24
	"BITC",	thumbrr,		0,	"R%n,R%d,R%d",	// 25
	"MOVN",	thumbrr,		0,	"R%n,R%d",		// 26
	"ADD",	thumbrrh,		0,	"R%n,R%d,R%d",	// 27
	"CMP",	thumbrrh,		0,	"R%n,R%d",		// 28
	"MOVW",	thumbrrh,		0,	"R%n,R%d",		// 29
	"BX",		thumbrrh,		0,	"R%n",			// 30
	"MOVW",	thumbpcrel,	0,	"%i(PC),R%d",		// 31
	"MOVW",	thumbrrr,		0,	"R%d, [R%s,R%n]",	// 32
	"MOVH",	thumbrrr,		0,	"R%d, [R%s,R%n]",	// 33
	"MOVB",	thumbrrr,		0,	"R%d, [R%s,R%n]",	// 34
	"MOVB",	thumbrrr,		0,	"[R%s,R%n],R%d",	// 35
	"MOVW",	thumbrrr,		0,	"[R%s,R%n],R%d",	// 36
	"MOVHU",	thumbrrr,		0,	"[R%s,R%n],R%d",	// 37
	"MOVBU",	thumbrrr,		0,	"[R%s,R%n],R%d",	// 38
	"MOVH",	thumbrrr,		0,	"[R%s,R%n],R%d",	// 39
	"MOVW",	thumbmovirr,	0,	"R%d,%i(R%n)",			// 40
	"MOVW",	thumbmovirr,	0,	"%i(R%n),R%d",			// 41
	"MOVB",	thumbmovirr,	0,	"R%d,%i(R%n)",			// 42
	"MOVBU",	thumbmovirr,	0,	"%i(R%n),R%d",		// 43
	"MOVH",	thumbmovirr,	0,	"R%d,%i(R%n)",			// 44
	"MOVHU",	thumbmovirr,	0,	"%i(R%n),R%d",			// 45
	"MOVW",	thumbmovsp,	0,	"R%d,%i(SP)",			// 46
	"MOVW",	thumbmovsp,	0,	"%i(SP),R%d",			// 47
	"ADD",	thumbaddsppc,0,	"$#%i,PC,R%d",		// 48
	"ADD",	thumbaddsppc,0,	"$#%i,SP,R%d",		// 49
	"ADD",	thumbaddsp,	0,	"$#%i,SP,SP",		// 50
	"SUB",	thumbaddsp,	0,	"$#%i,SP,SP",		// 51
	"PUSH",	thumbregs,	0,	"R%d, %r",			// 52
	"POP",	thumbregs,	0,	"R%d, %r",			// 53
	"STMIA",	thumbregs,	0,	"R%d, %r",			// 54
	"LDMIA",	thumbregs,	0,	"R%d, %r",			// 55
	"SWI",	thumbswi,	0,	"$#%i",			// 56
	"B%c",	thumbbcc,	0,	"%b",				// 57
	"B",		thumbb,		0,	"%b",				// 58
	"BL",		thumbbl,		0,	"",				// 59
	"BL",		thumbbl,		0,	"%b",				// 60
	"UNK",	thumbunk,	0,	"",				// 61
};

static void
format(char *mnemonic, Instr *i, char *f)
{
	int j, k, m, n;
	int ins = i->w;

	if(mnemonic)
		format(0, i, mnemonic);
	if(f == 0)
		return;
	if(mnemonic)
		if(i->curr < i->end)
			*i->curr++ = '\t';
	for ( ; *f && i->curr < i->end; f++) {
		if(*f != '%') {
			*i->curr++ = *f;
			continue;
		}
		switch (*++f) {

		case 'c':	/* Bcc */
			bprint(i, "%s", cond[B(11, 8)]);
			break;

		case 's':
			bprint(i, "%d", i->rs);
			break;
			
		case 'n':
			bprint(i, "%d", i->rn);
			break;

		case 'd':
			bprint(i, "%d", i->rd);
			break;

		case 'i':
			bprint(i, "%lux", i->imm);
			break;

		case 'b':
			bprint(i, "%lux", i->imm);
			break;

		case 'r':
			n = i->imm&0xff;
			j = 0;
			k = 0;
			while(n) {
				m = j;
				while(n&0x1) {
					j++;
					n >>= 1;
				}
				if(j != m) {
					if(k)
						bprint(i, ",");
					if(j == m+1)
						bprint(i, "R%d", m);
					else
						bprint(i, "R%d-R%d", m, j-1);
					k = 1;
				}
				j++;
				n >>= 1;
			}
			break;

		case '\0':
			*i->curr++ = '%';
			return;

		default:
			bprint(i, "%%%c", *f);
			break;
		}
	}
	*i->curr = 0;
}

void
das(ulong *x, int n)
{
	ulong pc;
	Instr i;
	char buf[128];

	pc = (ulong)x;
	while(n > 0) {
		i.curr = buf;
		i.end = buf+sizeof(buf)-1;

		if(decode(pc, &i) < 0)
			sprint(buf, "???");
		else
			(*opcodes[i.op].f)(&opcodes[i.op], &i);

		print("%.8lux %.8lux\t%s\n", pc, i.w, buf);
		pc += 2;
		n--;
	}
}
