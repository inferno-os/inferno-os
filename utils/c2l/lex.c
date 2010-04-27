#include	"cc.h"
#include	"y.tab.h"

#ifndef	CPP
#define	CPP	"/bin/cpp"
#endif

static int ansip;

void
main(int argc, char *argv[])
{
	char *defs[50], *p;
	int nproc, nout, status, i, c, ndef;

	tinit();
	cinit();
	ginit();
	arginit();

	tufield = simplet((1L<<tfield->etype) | BUNSIGNED);
	ndef = 0;
	include[ninclude++] = ".";
	strings = 1;
	passes = 1;

	ARGBEGIN {
	default:
		break;

	case 'p':
		ansip = 1;
		break;

	case 'D':
		p = ARGF();
		if(p) {
			defs[ndef++] = p;
			dodefine(p);
		}
		break;

	case 'I':
		p = ARGF();
		setinclude(p);
		break;

	case 'm':
		domod = 1;
		break;

	case 'i':
		doinc = 1;
		break;

	case 'l':
		doloc = 1;
		break;

	case 'c':
		justcode = 1;
		break;

	case 'v':
		comm = 1;
		break;

	case 's':
		strings = 0;
		break;

	case 'S':
		strings = 2;
		break;

	case 'M':
		inmain = 1;
		break;

	case 'q':
		passes = 0;
		break;

	case 'a':
		doaddr = 1;
		break;

	case 'A':
		doaddr = 1;
		doalladdr = 1;
		break;

	} ARGEND

	if(doinc)
		domod = doloc = 0;

	linit();

	if(argc != 1) {
		print("usage: c2l [-options] file\n");
		errorexit();
	}
	if(argc > 1 && systemtype(Windows)){
		print("can't compile multiple files on windows\n");
		errorexit();
	}
	if(argc > 1 && !systemtype(Windows)) {
		nproc = 1;
		if(p = getenv("NPROC"))
			nproc = atol(p);	/* */
		c = 0;
		nout = 0;
		for(;;) {
			while(nout < nproc && argc > 0) {
				i = myfork();
				if(i < 0) {
					i = mywait(&status);
					if(i < 0) {
						print("cannot create a process\n");
						errorexit();
					}
					if(status)
						c++;
					nout--;
					continue;
				}
				if(i == 0) {
					fprint(2, "%s:\n", *argv);
					if (compile(*argv, defs, ndef))
						errorexit();
					exits(0);
				}
				nout++;
				argc--;
				argv++;
			}
			i = mywait(&status);
			if(i < 0) {
				if(c)
					errorexit();
				exits(0);
			}
			if(status)
				c++;
			nout--;
		}
	}

	if(argc == 0)
		c = compile("stdin", defs, ndef);
	else
		c = compile(argv[0], defs, ndef);

	if(c)
		errorexit();
	exits(0);
}

int
compile(char *file, char **defs, int ndef)
{
	char ofile[200], incfile[20];
	char *p, *av[100], opt[256];
	int i, c, fd[2];

	strcpy(ofile, file);
	p = utfrrune(ofile, pathchar());
	if(p) {
		*p++ = 0;
		include[0] = strdup(ofile);
	} else
		p = ofile;

	USED(p);
	if(p = getenv("INCLUDE")) {
		setinclude(p);
	} else {
		if(systemtype(Plan9)) {
			sprint(incfile, "/%s/include", thestring);
			setinclude(strdup(incfile));
			setinclude("/sys/include");
		}
	}
	newio();

	/* Use an ANSI preprocessor */
	if(ansip) {
		if(systemtype(Windows)) {
			diag(Z, "-p option not supported on windows");
			errorexit();
		}
		if(mypipe(fd) < 0) {
			diag(Z, "pipe failed");
			errorexit();
		}
		switch(myfork()) {
		case -1:
			diag(Z, "fork failed");
			errorexit();
		case 0:
			close(fd[0]);
			mydup(fd[1], 1);
			close(fd[1]);
			av[0] = CPP;
			i = 1;
			for(c = 0; c < ndef; c++) {
				sprint(opt, "-D%s", defs[c]);
				av[i++] = strdup(opt);
			}
			for(c = 0; c < ninclude; c++) {
				sprint(opt, "-I%s", include[c]);
				av[i++] = strdup(opt);
			}
			if(strcmp(file, "stdin") != 0)
				av[i++] = file;
			av[i] = 0;
			if(0) {
				for(c = 0; c < i; c++)
					fprint(2, "%s ", av[c]);
				print("\n");
			}
			myexec(av[0], av);
			fprint(2, "can't exec C preprocessor %s: %r\n", CPP);
			errorexit();
		default:
			close(fd[1]);
			newfile(file, fd[0]);
			break;
		}
	} else {
		if(strcmp(file, "stdin") == 0)
			newfile(file, 0);
		else
			newfile(file, -1);
	}

	clbegin();
	yyparse();
	clend();
	newsec(0);
	return nerrors;
}

void
errorexit(void)
{
	exits("error");
}

void
pushio(void)
{
	Io *i;

	i = iostack;
	if(i == I) {
		yyerror("botch in pushio");
		errorexit();
	}
	i->p = fi.p;
	i->c = fi.c;
}

void
newio(void)
{
	Io *i;
	static pushdepth = 0;

	i = iofree;
	if(i == I) {
		pushdepth++;
		if(pushdepth > 1000) {
			yyerror("macro/io expansion too deep");
			errorexit();
		}
		i = alloc(sizeof(*i));
	} else
		iofree = i->link;
	i->c = 0;
	i->f = -1;
	ionext = i;
}

void
newfile(char *s, int f)
{
	Io *i;

	if(0)
		print("%L: %s\n", lineno, s);

	i = ionext;
	i->link = iostack;
	iostack = i;
	i->f = f;
	if(f < 0)
		i->f = open(s, 0);
	if(i->f < 0) {
		yyerror("c2l: %r: %s", s);
		errorexit();
	}
	fi.c = 0;
	linehist(s, 0);
	outpush(s);
}

Sym*
slookup(char *s)
{

	strcpy(symb, s);
	return lookup();
}

Sym*
lookup(void)
{
	static Sym zsym;
	Sym *s;
	ulong h;
	char *p;
	int c, n;

	h = 0;
	for(p=symb; *p;) {
		h = h * 3;
		h += *p++;
	}
	n = (p - symb) + 1;
	if((long)h < 0)
		h = ~h;
	h %= NHASH;
	c = symb[0];
	for(s = hash[h]; s != S; s = s->link) {
		if(s->name[0] != c)
			continue;
		if(strcmp(s->name, symb) == 0)
			return s;
	}
	s = alloc(sizeof(*s));
	*s = zsym;
	s->name = alloc(n);
	memmove(s->name, symb, n);

	strcpy(s->name, symb);
	s->link = hash[h];
	hash[h] = s;
	syminit(s);

	return s;
}

void
syminit(Sym *s)
{
	s->lexical = LNAME;
	s->type = T;
	s->suetag = T;
	s->class = CXXX;
	s->lname = s->mod = nil;
	s->lineno = lineno;
	s->tenum = T;
}

#define	EOF	(-1)
#define	IGN	(-2)
#define	ESC	(1<<20)
#define	GETC()	((--fi.c < 0)? filbuf(): (*fi.p++ & 0xff))

enum
{
	Numdec		= 1<<0,
	Numlong		= 1<<1,
	Numuns		= 1<<2,
	Numvlong	= 1<<3,
	Numflt		= 1<<4,
};

static int ypeek = 0;

long
yylex(void)
{
	vlong vv;
	long c, c1;
	char *cp;
	Rune rune;
	Sym *s;

	if(peekc != IGN) {
		c = peekc;
		peekc = IGN;
		goto l1;
	}
l0:
	c = GETC();

l1:
	if(c >= Runeself) {
		/*
		 * extension --
		 *	all multibyte runes are alpha
		 */
		cp = symb;
		goto talph;
	}
	if(isspace(c)) {
		if(c == '\n')
			lineno++;
		goto l0;
	}
	if(isalpha(c)) {
		cp = symb;
		if(c != 'L')
			goto talph;
		*cp++ = c;
		c = GETC();
		if(c == '\'') {
			/* L'x' */
			c = escchar('\'', 1, 0);
			if(c == EOF)
				c = '\'';
			c1 = escchar('\'', 1, 0);
			if(c1 != EOF) {
				yyerror("missing '");
				peekc = c1;
			}
			yylval.vval = convvtox(c, TUSHORT);
			return LUCONST;
		}
		if(c == '"') {
			goto caselq;
		}
		goto talph;
	}
	if(isdigit(c))
		goto tnum;
	switch(c)
	{

	case EOF:
		peekc = EOF;
		return -1;

	case '_':
		cp = symb;
		goto talph;

	case '#':
		domacro();
		goto l0;

	case '.':
		c1 = GETC();
		if(isdigit(c1)) {
			cp = symb;
			*cp++ = c;
			c = c1;
			c1 = 0;
			goto casedot;
		}
		break;

	case '"':
		strcpy(symb, "\"<string>\"");
		cp = alloc(0);
		c1 = 0;

		/* "..." */
		for(;;) {
			c = escchar('"', 0, 1);
			if(c == EOF)
				break;
			if(c & ESC) {
				cp = allocn(cp, c1, 1);
				cp[c1++] = c;
			} else {
				rune = c;
				c = runelen(rune);
				cp = allocn(cp, c1, c);
				runetochar(cp+c1, &rune);
				c1 += c;
			}
		}
		yylval.sval.l = c1;
		do {
			cp = allocn(cp, c1, 1);
			cp[c1++] = 0;
		} while(c1 & MAXALIGN);
		yylval.sval.s = cp;
		return LSTRING;

	caselq:
		/* L"..." */
		strcpy(symb, "\"L<string>\"");
		cp = alloc(0);
		c1 = 0;
		for(;;) {
			c = escchar('"', 1, 0);
			if(c == EOF)
				break;
			cp = allocn(cp, c1, sizeof(ushort));
			*(ushort*)(cp + c1) = c;
			c1 += sizeof(ushort);
		}
		yylval.sval.l = c1;
		do {
			cp = allocn(cp, c1, sizeof(ushort));
			*(ushort*)(cp + c1) = 0;
			c1 += sizeof(ushort);
		} while(c1 & MAXALIGN);
		yylval.sval.s = cp;
		return LLSTRING;

	case '\'':
		/* '.' */
		c = escchar('\'', 0, 0);
		if(c == EOF)
			c = '\'';
		c1 = escchar('\'', 0, 0);
		if(c1 != EOF) {
			yyerror("missing '");
			peekc = c1;
		}
		vv = c;
		yylval.vval = convvtox(vv, TUCHAR);
		if(yylval.vval != vv)
			yyerror("overflow in character constant: 0x%lx", c);
		else
		if(c & 0x80)
			warn(Z, "sign-extended character constant");
		yylval.vval = convvtox(vv, TCHAR);
		return LCHARACTER;

	case '/':
		c1 = GETC();
		if(c1 == '*') {
			startcom(lineno);
			for(;;) {
				c = getr();
				if(c == '*'){
					while(c == '*') {
						c = getr();
						if(c == '/'){
							endcom();
							goto l0;
						}
						addcom('*');
					}
					addcom(c);
				}
				else
					addcom(c);
				if(c == EOF) {
					yyerror("eof in comment");
					errorexit();
				}
			}
		}
		if(c1 == '/') {
			startcom(lineno);
			for(;;) {
				c = getr();
				if(c == '\n'){
					endcom();
					goto l0;
				}
				addcom(c);
				if(c == EOF) {
					yyerror("eof in comment");
					errorexit();
				}
			}
		}
		if(c1 == '=')
			return LDVE;
		break;

	case '*':
		c1 = GETC();
		if(c1 == '=')
			return LMLE;
		break;

	case '%':
		c1 = GETC();
		if(c1 == '=')
			return LMDE;
		break;

	case '+':
		c1 = GETC();
		if(c1 == '+')
			return LPP;
		if(c1 == '=')
			return LPE;
		break;

	case '-':
		c1 = GETC();
		if(c1 == '-')
			return LMM;
		if(c1 == '=')
			return LME;
		if(c1 == '>')
			return LMG;
		break;

	case '>':
		c1 = GETC();
		if(c1 == '>') {
			c = LRSH;
			c1 = GETC();
			if(c1 == '=')
				return LRSHE;
			break;
		}
		if(c1 == '=')
			return LGE;
		break;

	case '<':
		c1 = GETC();
		if(c1 == '<') {
			c = LLSH;
			c1 = GETC();
			if(c1 == '=')
				return LLSHE;
			break;
		}
		if(c1 == '=')
			return LLE;
		break;

	case '=':
		c1 = GETC();
		if(c1 == '=')
			return LEQ;
		break;

	case '!':
		c1 = GETC();
		if(c1 == '=')
			return LNE;
		break;

	case '&':
		c1 = GETC();
		if(c1 == '&')
			return LANDAND;
		if(c1 == '=')
			return LANDE;
		break;

	case '|':
		c1 = GETC();
		if(c1 == '|')
			return LOROR;
		if(c1 == '=')
			return LORE;
		break;

	case '^':
		c1 = GETC();
		if(c1 == '=')
			return LXORE;
		break;

	default:
		return c;
	}
	peekc = c1;
	return c;

talph:
	/*
	 * cp is set to symb and some
	 * prefix has been stored
	 */
	for(;;) {
		if(c >= Runeself) {
			for(c1=0;;) {
				cp[c1++] = c;
				if(fullrune(cp, c1))
					break;
				c = GETC();
			}
			cp += c1;
			c = GETC();
			continue;
		}
		if(!isalnum(c) && c != '_')
			break;
		*cp++ = c;
		c = GETC();
	}
	*cp = 0;
	if(0)
		print("%L: %s\n", lineno, symb);
	peekc = c;
	s = lookup();
	if(s->macro && !ypeek) {
		newio();
		cp = ionext->b;
		macexpand(s, cp);
		pushio();
		ionext->link = iostack;
		iostack = ionext;
		fi.p = cp;
		fi.c = strlen(cp);
		if(peekc != IGN) {
			cp[fi.c++] = peekc;
			cp[fi.c] = 0;
			peekc = IGN;
		}
		/* outpush(nil); */
		goto l0;
	}
	yylval.sym = s;
	if(s->class == CTYPEDEF) {
		if(s->type && typesu[s->type->etype])
			return LCTYPE;
		return LSTYPE;
	}
	return s->lexical;

tnum:
	lastnumbase = KDEC;
	c1 = 0;
	cp = symb;
	if(c != '0') {
		c1 |= Numdec;
		for(;;) {
			*cp++ = c;
			c = GETC();
			if(isdigit(c))
				continue;
			goto dc;
		}
	}
	*cp++ = c;
	c = GETC();
	if(c == 'x' || c == 'X'){
		lastnumbase = KHEX;
		for(;;) {
			*cp++ = c;
			c = GETC();
			if(isdigit(c))
				continue;
			if(c >= 'a' && c <= 'f')
				continue;
			if(c >= 'A' && c <= 'F')
				continue;
			if(cp == symb+2)
				yyerror("malformed hex constant");
			goto ncu;
		}
	}
	else
		lastnumbase = KOCT;
	if(c < '0' || c > '7'){
		lastnumbase = KDEC;
		goto dc;
	}
	for(;;) {
		if(c >= '0' && c <= '7') {
			*cp++ = c;
			c = GETC();
			continue;
		}
		goto ncu;
	}

dc:
	if(c == '.')
		goto casedot;
	if(c == 'e' || c == 'E')
		goto casee;

ncu:
	if((c == 'U' || c == 'u') && !(c1 & Numuns)) {
		c = GETC();
		c1 |= Numuns;
		goto ncu;
	}
	if((c == 'L' || c == 'l') && !(c1 & Numvlong)) {
		c = GETC();
		if(c1 & Numlong)
			c1 |= Numvlong;
		c1 |= Numlong;
		goto ncu;
	}
	*cp = 0;
	peekc = c;
	if(mpatov(symb, &yylval.vval))
		yyerror("overflow in constant");

	vv = yylval.vval;
	if(c1 & Numvlong) {
		if(c1 & Numuns) {
			c = LUVLCONST;
			goto nret;
		}
		yylval.vval = convvtox(yylval.vval, TVLONG);
		if(yylval.vval < 0) {
			c = LUVLCONST;
			goto nret;
		}
		c = LVLCONST;
		goto nret;
	}
	if(c1 & Numlong) {
		if(c1 & Numuns) {
			c = LULCONST;
			goto nret;
		}
		yylval.vval = convvtox(yylval.vval, TLONG);
		if(yylval.vval < 0) {
			c = LULCONST;
			goto nret;
		}
		c = LLCONST;
		goto nret;
	}
	if(c1 & Numuns) {
		c = LUCONST;
		goto nret;
	}
	yylval.vval = convvtox(yylval.vval, TINT);
	if(yylval.vval < 0) {
		c = LUCONST;
		goto nret;
	}
	c = LCONST;
	goto nret;

nret:
	return c;

casedot:
	for(;;) {
		*cp++ = c;
		c = GETC();
		if(!isdigit(c))
			break;
	}
	if(c != 'e' && c != 'E')
		goto caseout;

casee:
	*cp++ = 'e';
	c = GETC();
	if(c == '+' || c == '-') {
		*cp++ = c;
		c = GETC();
	}
	if(!isdigit(c))
		yyerror("malformed fp constant exponent");
	while(isdigit(c)) {
		*cp++ = c;
		c = GETC();
	}

caseout:
	if(c == 'L' || c == 'l') {
		c = GETC();
		c1 |= Numlong;
	} else
	if(c == 'F' || c == 'f') {
		c = GETC();
		c1 |= Numflt;
	}
	*cp = 0;
	peekc = c;
	if(mpatof(symb, &yylval.dval)) {
		yyerror("overflow in float constant");
		yylval.dval = 0;
	}
	if(c1 & Numflt)
		return LFCONST;
	return LDCONST;
}

int
getc(void)
{
	int c;

	if(peekc != IGN) {
		c = peekc;
		peekc = IGN;
	} else
		c = GETC();
	if(c == '\n')
		lineno++;
	if(c == EOF) {
		yyerror("End of file");
		errorexit();
	}
	return c;
}

long
getr(void)
{
	int c, i;
	char str[UTFmax+1];
	Rune rune;


	c = getc();
	if(c < Runeself)
		return c;
	i = 0;
	str[i++] = c;

loop:
	c = getc();
	str[i++] = c;
	if(!fullrune(str, i))
		goto loop;
	c = chartorune(&rune, str);
	if(rune == Runeerror && c == 1) {
		/* nearln = lineno; */
		diag(Z, "illegal rune in string");
		for(c=0; c<i; c++)
			print(" %.2x", *(uchar*)(str+c));
		print("\n");
	}
	return rune;
}

int
getnsc(void)
{
	int c;

	if(peekc != IGN) {
		c = peekc;
		peekc = IGN;
	} else
		c = GETC();
	for(;;) {
		if(!isspace(c))
			return c;
		if(c == '\n') {
			lineno++;
			return c;
		}
		c = GETC();
	}
	/* not reached */
}

void
unget(int c)
{

	peekc = c;
	if(c == '\n')
		lineno--;
}

long
escchar(long e, int longflg, int escflg)
{
	long c, l;
	int i;

loop:
	c = getr();
	if(c == '\n') {
		yyerror("newline in string");
		return EOF;
	}
	if(c != '\\') {
		if(c == e)
			c = EOF;
		return c;
	}
	c = getr();
	if(c == 'x') {
		/*
		 * note this is not ansi,
		 * supposed to only accept 2 hex
		 */
		i = 2;
		if(longflg)
			i = 4;
		l = 0;
		for(; i>0; i--) {
			c = getc();
			if(c >= '0' && c <= '9') {
				l = l*16 + c-'0';
				continue;
			}
			if(c >= 'a' && c <= 'f') {
				l = l*16 + c-'a' + 10;
				continue;
			}
			if(c >= 'A' && c <= 'F') {
				l = l*16 + c-'A' + 10;
				continue;
			}
			unget(c);
			break;
		}
		if(escflg)
			l |= ESC;
		return l;
	}
	if(c >= '0' && c <= '7') {
		/*
		 * note this is not ansi,
		 * supposed to only accept 3 oct
		 */
		i = 2;
		if(longflg)
			i = 5;
		l = c - '0';
		for(; i>0; i--) {
			c = getc();
			if(c >= '0' && c <= '7') {
				l = l*8 + c-'0';
				continue;
			}
			unget(c);
		}
		if(escflg)
			l |= ESC;
		return l;
	}
	switch(c)
	{
	case '\n':	goto loop;
	case 'n':	return '\n';
	case 't':	return '\t';
	case 'b':	return '\b';
	case 'r':	return '\r';
	case 'f':	return '\f';
	case 'a':	return '\a';
	case 'v':	return '\v';
	}
	return c;
}

struct
{
	char	*name;
	ushort	lexical;
	ushort	type;
} itab[] =
{
	"auto",		LAUTO,		0,
	"break",	LBREAK,		0,
	"case",		LCASE,		0,
	"char",		LCHAR,		TCHAR,
	"const",	LCONSTNT,	0,
	"continue",	LCONTINUE,	0,
	"default",	LDEFAULT,	0,
	"do",		LDO,		0,
	"double",	LDOUBLE,	TDOUBLE,
	"else",		LELSE,		0,
	"enum",		LENUM,		0,
	"extern",	LEXTERN,	0,
	"float",	LFLOAT,		TFLOAT,
	"for",		LFOR,		0,
	"goto",		LGOTO,		0,
	"if",		LIF,		0,
	"int",		LINT,		TINT,
	"long",		LLONG,		TLONG,
	"register",	LREGISTER,	0,
	"return",	LRETURN,	0,
	"SET",		LSET,		0,
	"short",	LSHORT,		TSHORT,
	"signed",	LSIGNED,	0,
	"signof",	LSIGNOF,	0,
	"sizeof",	LSIZEOF,	0,
	"static",	LSTATIC,	0,
	"struct",	LSTRUCT,	0,
	"switch",	LSWITCH,	0,
	"typedef",	LTYPEDEF,	0,
	"union",	LUNION,		0,
	"unsigned",	LUNSIGNED,	0,
	"USED",		LUSED,		0,
	"void",		LVOID,		TVOID,
	"volatile",	LVOLATILE,	0,
	"while",	LWHILE,		0,
	"__int64",	LVLONG,	TVLONG,			/* for windows */
	0
};

static char *litab[] =
{
	"adt",
	"alt",
	"array",
	"big",
	"break",
	"byte",
	"case",
	"chan",
	"con",
	"continue",
	"cyclic",
	"do",
	"else",
	"exit",
	"fn",
	"for",
	"hd",
	"if",
	"implement",
	"import",
	"include",
	"int",
	"len",
	"list",
	"load",
	"module",
	"nil",
	"of",
	"or",
	"pick",
	"real",
	"ref",
	"return",
	"self",
	"spawn",
	"string",
	"tagof",
	"tl",
	"to",
	"type",
	"while",
	0,
};

void
cinit(void)
{
	Sym *s;
	int i;
	Type *t;

	nerrors = 0;
	lineno = 1;
	iostack = I;
	iofree = I;
	peekc = IGN;
	nhunk = 0;

	types[TXXX] = T;
	types[TCHAR] = typ(TCHAR, T);
	types[TUCHAR] = typ(TUCHAR, T);
	types[TSHORT] = typ(TSHORT, T);
	types[TUSHORT] = typ(TUSHORT, T);
	types[TINT] = typ(TINT, T);
	types[TUINT] = typ(TUINT, T);
	types[TLONG] = typ(TLONG, T);
	types[TULONG] = typ(TULONG, T);
	types[TVLONG] = typ(TVLONG, T);
	types[TUVLONG] = typ(TUVLONG, T);
	types[TFLOAT] = typ(TFLOAT, T);
	types[TDOUBLE] = typ(TDOUBLE, T);
	types[TVOID] = typ(TVOID, T);
	types[TENUM] = typ(TENUM, T);
	types[TFUNC] = typ(TFUNC, types[TINT]);
	types[TIND] = typ(TIND, types[TVOID]);
	stringtype = typ(TSTRING, T);
	fdtype = typ(TSTRUCT, typ(TFD, T));
	fdtype->width = 4;
	pfdtype = typ(TIND, fdtype);

	for(i=0; i<NHASH; i++)
		hash[i] = S;
	for(i=0; itab[i].name; i++) {
		s = slookup(itab[i].name);
		s->lexical = itab[i].lexical;
		if(itab[i].type != 0)
			s->type = types[itab[i].type];
	}
	for(i=0; litab[i]; i++){
		s = slookup(litab[i]);
		s->lkw = 1;
	}
	blockno = 0;
	autobn = 0;
	autoffset = 0;

	t = typ(TARRAY, types[TCHAR]);
	t->width = 0;
	symstring = slookup(".string");
	symstring->class = CSTATIC;
	symstring->type = t;

	t = typ(TARRAY, types[TCHAR]);
	t->width = 0;

	nodproto = new(OPROTO, Z, Z);
	dclstack = D;

	pathname = allocn(pathname, 0, 100);
	if(mygetwd(pathname, 99) == 0) {
		pathname = allocn(pathname, 100, 900);
		if(mygetwd(pathname, 999) == 0)
			strcpy(pathname, "/???");
	}

	fmtinstall('f', gfltconv);
	fmtinstall('F', gfltconv);
	fmtinstall('g', gfltconv);
	fmtinstall('G', gfltconv);
	fmtinstall('e', gfltconv);
	fmtinstall('E', gfltconv);
	
	fmtinstall('O', Oconv);
	fmtinstall('T', Tconv);
	fmtinstall('F', FNconv);
	fmtinstall('L', Lconv);
	fmtinstall('Q', Qconv);
	fmtinstall('|', VBconv);
}

int
filbuf(void)
{
	Io *i;

loop:
	i = iostack;
	if(i == I)
		return EOF;
	if(i->f < 0)
		goto pop;
	fi.c = read(i->f, i->b, BUFSIZ) - 1;
	if(fi.c < 0) {
		close(i->f);
		linehist(0, 0);
		goto pop;
	}
	fi.p = i->b + 1;
	return i->b[0] & 0xff;

pop:
	if(i->f >= 0)
		outpop(lineno);
	iostack = i->link;
	i->link = iofree;
	iofree = i;
	i = iostack;
	if(i == I)
		return EOF;
	fi.p = i->p;
	fi.c = i->c;
	if(--fi.c < 0)
		goto loop;
	return *fi.p++ & 0xff;
}

int
Oconv(Fmt *fp)
{
	int a;
	char s[STRINGSZ];

	a = va_arg(fp->args, int);
	if(a < OXXX || a > OEND) {
		sprint(s, "***badO %d***", a);
		fmtstrcpy(fp, s);
	} else
		fmtstrcpy(fp, onames[a]);
	return 0;
}

int
Lconv(Fmt *fp)
{
	char str[STRINGSZ], s[STRINGSZ];
	Hist *h;
	struct
	{
		Hist*	incl;	/* start of this include file */
		long	idel;	/* delta line number to apply to include */
		Hist*	line;	/* start of this #line directive */
		long	ldel;	/* delta line number to apply to #line */
	} a[HISTSZ];
	long l, d;
	int i, n;

	l = va_arg(fp->args, long);
	n = 0;
	for(h = hist; h != H; h = h->link) {
		if(l < h->line)
			break;
		if(h->name) {
			if(h->offset != 0) {		/* #line directive, not #pragma */
				if(n > 0 && n < HISTSZ && h->offset >= 0) {
					a[n-1].line = h;
					a[n-1].ldel = h->line - h->offset + 1;
				}
			} else {
				if(n < HISTSZ) {	/* beginning of file */
					a[n].incl = h;
					a[n].idel = h->line;
					a[n].line = 0;
				}
				n++;
			}
			continue;
		}
		n--;
		if(n > 0 && n < HISTSZ) {
			d = h->line - a[n].incl->line;
			a[n-1].ldel += d;
			a[n-1].idel += d;
		}
	}
	if(n > HISTSZ)
		n = HISTSZ;
	str[0] = 0;
	for(i=n-1; i>=0; i--) {
		if(i != n-1) {
			if(fp->flags & ~(FmtWidth|FmtPrec))	/* BUG ROB - was f3 */
				break;
			strcat(str, " ");
		}
		if(a[i].line)
			snprint(s, STRINGSZ, "%s:%ld[%s:%ld]",
				a[i].line->name, l-a[i].ldel+1,
				a[i].incl->name, l-a[i].idel+1);
		else
			snprint(s, STRINGSZ, "%s:%ld",
				a[i].incl->name, l-a[i].idel+1);
		if(strlen(s)+strlen(str) >= STRINGSZ-10)
			break;
		strcat(str, s);
		l = a[i].incl->line - 1;	/* now print out start of this file */
	}
	if(n == 0)
		strcat(str, "<eof>");
	fmtstrcpy(fp, str);
	return 0;
}

int
Tconv(Fmt *fp)
{
	char str[STRINGSZ+20], s[STRINGSZ+20];
	Type *t, *t1;
	int et;
	long n;

	str[0] = 0;
	for(t = va_arg(fp->args, Type*); t != T; t = t->link) {
		et = t->etype;
		if(str[0])
			strcat(str, " ");
		if(t->garb) {
			sprint(s, "%s ", gnames[t->garb]);
			if(strlen(str) + strlen(s) < STRINGSZ)
				strcat(str, s);
		}
		sprint(s, "%s", tnames[et]);
		if(strlen(str) + strlen(s) < STRINGSZ)
			strcat(str, s);
		if(et == TFUNC && (t1 = t->down)) {
			sprint(s, "(%T", t1);
			if(strlen(str) + strlen(s) < STRINGSZ)
				strcat(str, s);
			while(t1 = t1->down) {
				sprint(s, ", %T", t1);
				if(strlen(str) + strlen(s) < STRINGSZ)
					strcat(str, s);
			}
			if(strlen(str) + strlen(s) < STRINGSZ)
				strcat(str, ")");
		}
		if(et == TARRAY) {
			n = t->width;
			if(t->link && t->link->width)
				n /= t->link->width;
			sprint(s, "[%ld]", n);
			if(strlen(str) + strlen(s) < STRINGSZ)
				strcat(str, s);
		}
		if(t->nbits) {
			sprint(s, " %d:%d", t->shift, t->nbits);
			if(strlen(str) + strlen(s) < STRINGSZ)
				strcat(str, s);
		}
		if(typesu[et]) {
			if(t->tag) {
				strcat(str, " ");
				if(strlen(str) + strlen(t->tag->name) < STRINGSZ)
					strcat(str, t->tag->name);
			} else
				strcat(str, " {}");
			break;
		}
	}
	fmtstrcpy(fp, str);
	return 0;
}

int
FNconv(Fmt *fp)
{
	char *str;
	Node *n;

	n = va_arg(fp->args, Node*);
	str = "<indirect>";
	if(n != Z && (n->op == ONAME || n->op == ODOT || n->op == OELEM))
		str = n->sym->name;
	fmtstrcpy(fp, str);
	return 0;
}

int
Qconv(Fmt *fp)
{
	char str[STRINGSZ+20], *s;
	long b;
	int i;

	str[0] = 0;
	for(b = va_arg(fp->args, long); b;) {
		i = bitno(b);
		if(str[0])
			strcat(str, " ");
		s = qnames[i];
		if(strlen(str) + strlen(s) >= STRINGSZ)
			break;
		strcat(str, s);
		b &= ~(1L << i);
	}
	fmtstrcpy(fp, str);
	return 0;
}

int
VBconv(Fmt *fp)
{
	char str[STRINGSZ];
	int i, n, t, pc;

	n = va_arg(fp->args, int);
	pc = 0;	/*was printcol */
	i = 0;
	while(pc < n) {
		t = (pc+8) & ~7;
		if(t <= n) {
			str[i++] = '\t';
			pc = t;
			continue;
		}
		str[i++] = ' ';
		pc++;
	}
	str[i] = 0;
	fmtstrcpy(fp, str);
	return 0;
}

/*
 * real allocs
 */
void*
alloc(long n)
{
	void *p;

	while((ulong)hunk & MAXALIGN) {
		hunk++;
		nhunk--;
	}
	while(nhunk < n)
		gethunk();
	p = hunk;
	nhunk -= n;
	hunk += n;
	return p;
}

void*
allocn(void *p, long on, long n)
{
	void *q;

	q = (uchar*)p + on;
	if(q != hunk || nhunk < n) {
		while(nhunk < on+n)
			gethunk();
		memmove(hunk, p, on);
		p = hunk;
		hunk += on;
		nhunk -= on;
	}
	hunk += n;
	nhunk -= n;
	return p;
}

void
setinclude(char *p)
{
	int i;
	char *e;

	while(*p != 0) {
		e = strchr(p, ' ');
		if(e != 0)
			*e = '\0';

		for(i=1; i < ninclude; i++)
			if(strcmp(p, include[i]) == 0)
				break;

		if(i >= ninclude)
			include[ninclude++] = p;

		if(ninclude > nelem(include)) {
			diag(Z, "ninclude too small %d", nelem(include));
			exits("ninclude");
		}

		if(e == 0)
			break;
		p = e+1;
	}
}

static void
doio(char *s)
{
	char *cp;

	newio();
	cp = ionext->b;
	strcpy(cp, s);
	pushio();
	ionext->link = iostack;
	iostack = ionext;
	fi.p = cp;
	fi.c = strlen(cp);
	if(peekc != IGN) {
		cp[fi.c++] = peekc;
		cp[fi.c] = 0;
		peekc = IGN;
	}
}

static void
undoio(void)
{
	Io *i;

	i = iostack;
	iostack = i->link;
	i->link = iofree;
	iofree = i;
	i = iostack;
	fi.p = i->p;
	fi.c = i->c;
}

/* rm // comment from a string */
static void
slashslash(char *s)
{
	for( ; *s != '\0'; s++)
		if(*s == '/' && s[1] == '/'){
			*s = '\0';
			return;
		}
}

int
iscon(char *str)
{
	int olineno, opeekc, con, tok, t;
	Sym *s;
	char buf[1024];

	if(str == nil || *str == 0 || strlen(str)+16 > 1024)
		return 0;
	ypeek = 1;
	olineno = lineno;
	opeekc = peekc;
	peekc = IGN;
	strcpy(buf, str);
	slashslash(buf);
	strcat(buf, " break break");
	doio(buf);
	tok = 0;
	con = 1;
	while(con){
		t = yylex();
		if(t == LBREAK)
			break;
		switch(t){
			case LSTRING:
			case LLSTRING:
				tok = 1;
				free(yylval.sval.s);
				break;
			case LNAME:
				tok = 1;
				s = yylval.sym;
				if(s->macro || s->type == T || s->type->etype != TENUM)
					con = 0;
				break;
			case LCHARACTER:
			case LCONST:
			case LLCONST:
			case LUCONST:
			case LULCONST:
			case LVLCONST:
			case LUVLCONST:
			case LFCONST:
			case LDCONST:
				tok = 1;
				break;
			case '+':
			case '-':
			case '*':
			case '/':
			case '%':
			case LPP:
			case LMM:
			case '<':
			case '>':
			case LGE:
			case LLE:
			case LEQ:
			case LNE:
			case LLSH:
			case LRSH:
			case '!':
			case '~':
			case '&':
			case '|':
			case '^':
			case '(':
			case ')':
				break;
			default:
				con = 0;
				break;
		}
	}
	undoio();
	peekc = opeekc;
	lineno = olineno;
	ypeek = 0;
	return con && tok;
}

void
doasenum(Sym *s)
{
	char *b, buf[1024];

	b = s->macro;
	s->macro = nil;
	lineno--;
	slashslash(b+1);
	sprint(buf, "enum{ %s = %s };\n", s->name, b+1);
	doio(buf);
	/* outpush(nil); */
	free(b);
}
