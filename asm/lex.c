#include "asm.h"
#include "y.tab.h"
#include "../libinterp/tab.h"

Biobuf*	bin;
Biobuf*	bout;
Biobuf	output;
int	line;
int	heapid;
char	symbol[1024];
int	nerr;
char	cmap[256];
char*	file;
Desc*	dlist;
int	dcount;
int	dseg;
List*	mdata;
Sym*	module;
Link*	links;
Link*	linkt;
int	nlink;
int	listing;
int	mustcompile;
int	dontcompile;
char	*ofile;
int	dentry;
int	pcentry;

void
usage(void)
{
	fprint(2, "usage: asm [-l] file.s\n");
	exits("usage");
}

static char*
mkfile(char *file, char *oldext, char *ext)
{
	char *ofile;
	int n, n2;

	n = strlen(file);
	n2 = strlen(oldext);
	if(n >= n2 && strcmp(&file[n-n2], oldext) == 0)
		n -= n2;
	ofile = malloc(n + strlen(ext) + 1);
	memmove(ofile, file, n);
	strcpy(ofile+n, ext);
	return ofile;
}

void
main(int argc, char *argv[])
{
	int fd;
	char *p;

	ARGBEGIN{
	case 'C':
		dontcompile++;
		break;
	case 'c':
		mustcompile++;
		break;
	case 'l':
		listing++;
		break;
	default:
		usage();
	}ARGEND;

	fmtinstall('i', iconv);
	fmtinstall('a', aconv);
	kinit();
	pcentry = -1;
	dentry = -1;

	if(argc != 1)
		usage();
	file = argv[0];
	bin = Bopen(file, OREAD);
	if(bin == 0) {
		nerr++;
		print("open: %s: %r\n", file);
		exits("errors");
	}
	p = strrchr(file, '/');
	if(p == nil)
		p = file;
	else
		p++;
	ofile = mkfile(p, ".s", ".dis");
	fd = create(ofile, OWRITE, 0666);
	if(fd < 0) {
		nerr++;
		print("can't create: %s: %r\n", ofile);
		exits("errors");
	}
	Binit(&output, fd, OWRITE);
	bout = &output;
	line = 1;
	yyparse();
	Bterm(bin);
	Bterm(bout);
	close(fd);

	if(nerr != 0){
		remove(ofile);
		exits("errors");
	}

	exits(0);
}

int
opcode(Inst *i)
{
	return keywds[i->op].op;
}

int
iconv(Fmt *f)
{
	Inst *i;
	char buf[128];

	i = va_arg(f->args, Inst*);
	if(i == nil)
		return fmtstrcpy(f, "IZ");

	switch(keywds[i->op].terminal) {
	case TOKI0:
		sprint(buf, "%s", keywds[i->op].name);
		break;
	case TOKI1:
		sprint(buf, "%s\t%a", keywds[i->op].name, i->dst);
		break;
	case TOKI3:
		if(i->reg != 0) {
			char *pre = "";
			char *post = "";
			switch(i->reg->mode) {
			case AXIMM:
				pre = "$";
				break;
			case AXINF:
				post = "(fp)";
				break;
			case AXINM:
				post = "(mp)";
			 	break;
			}
			sprint(buf, "%s\t%a, %s%ld%s, %a", keywds[i->op].name, i->src, pre, i->reg->val, post, i->dst);
			break;
		}
	case TOKI2:
		sprint(buf, "%s\t%a, %a", keywds[i->op].name, i->src, i->dst);
		break;
	}

	return fmtstrcpy(f, buf);
}

int
aconv(Fmt *f)
{
	Addr *a;
	char buf[64];

	a = va_arg(f->args, Addr*);

	if(a == nil)
		return fmtstrcpy(f, "AZ");

	if(a->mode & AIND) {		
		switch(a->mode & ~AIND) {
		case AFP:
			sprint(buf, "%ld(%d(fp))", a->val, a->off);
			break;
		case AMP:
			sprint(buf, "%ld(%d(mp))", a->val, a->off);
			break;
		}
	}
	else {
		switch(a->mode) {
		case AFP:
			sprint(buf, "%ld(fp)", a->val);
			break;
		case AMP:
			sprint(buf, "%ld(mp)", a->val);
			break;
		case AIMM:
			sprint(buf, "$%ld", a->val);
			break;
		}
	}

	return fmtstrcpy(f, buf);
}

void
kinit(void)
{
	int i;
	Sym *s;
	
	for(i = 0; keywds[i].name; i++) {
		s = enter(keywds[i].name, keywds[i].terminal);
		s->value = keywds[i].op;
	}

	enter("desc", TOKHEAP);
	enter("mp", TOKSB);
	enter("fp", TOKFP);

	enter("byte", TOKDB);
	enter("word", TOKDW);
	enter("long", TOKDL);
	enter("real", TOKDF);
	enter("string", TOKDS);
	enter("var", TOKVAR);
	enter("ext", TOKEXT);
	enter("module", TOKMOD);
	enter("link", TOKLINK);
	enter("entry", TOKENTRY);
	enter("array", TOKARRAY);
	enter("indir", TOKINDIR);
	enter("apop", TOKAPOP);
	enter("ldts", TOKLDTS);
	enter("exceptions", TOKEXCS);
	enter("exception", TOKEXC);
	enter("exctab", TOKETAB);
	enter("source", TOKSRC);

	cmap['0'] = '\0'+1;
	cmap['z'] = '\0'+1;
	cmap['n'] = '\n'+1;
	cmap['r'] = '\r'+1;
	cmap['t'] = '\t'+1;
	cmap['b'] = '\b'+1;
	cmap['f'] = '\f'+1;
	cmap['a'] = '\a'+1;
	cmap['v'] = '\v'+1;
	cmap['\\'] = '\\'+1;
	cmap['"'] = '"'+1;
}

int
escchar(char c)
{
	int n;
	char buf[32];

	if(c >= '0' && c <= '9') {
		n = 1;
		buf[0] = c;
		for(;;) {
			c = Bgetc(bin);
			if(c == Eof)
				fatal("%d: <eof> in escape sequence", line);
			if(strchr("0123456789xX", c) == 0) {
				Bungetc(bin);
				break;
			}
			buf[n++] = c;
		}
		buf[n] = '\0';
		return strtol(buf, 0, 0);
	}

	n = cmap[c];
	if(n == 0)
		return c;
	return n-1;
}

static char	*strbuf;
static int	bufmax;

static void
resizebuf(void)
{
	bufmax += Strsize;
	strbuf = realloc(strbuf, bufmax);
}

void
eatstring(void)
{
	String *s;
	int esc, c, cnt;

	esc = 0;
	for(cnt = 0;;) {
		c = Bgetc(bin);
		switch(c) {
		case Eof:
			fatal("%d: <eof> in string constant", line);

		case '\n':
			line++;
			diag("newline in string constant");
			goto done;

		case '\\':
			if(esc) {
				if(cnt >= bufmax)
					resizebuf();
				strbuf[cnt++] = c;
				esc = 0;
				break;
			}
			esc = 1;
			break;

		case '"':
			if(esc == 0)
				goto done;

			/* Fall through */
		default:
			if(esc) {
				c = escchar(c);
				esc = 0;
			}
			if(cnt >= bufmax)
				resizebuf();
			strbuf[cnt++] = c;
			break;
		}
	}
done:
	if(cnt >= bufmax)
		resizebuf();
	strbuf[cnt] = '\0';
	s = malloc(sizeof(String));
	s->len = cnt+1;
	s->string = malloc(s->len);
	memmove(s->string, strbuf, s->len);
	yylval.string = s;
}

void
eatnl(void)
{
	int c;

	line++;
	for(;;) {
		c = Bgetc(bin);
		if(c == Eof)
			diag("eof in comment");
		if(c == '\n')
			return;
	}
}

int
yylex(void)
{
	int c;

loop:
	c = Bgetc(bin);
	switch(c) {
	case Eof:
		return Eof;
	case '"':
		eatstring();
		return TSTRING;
	case ' ':
	case '\t':
	case '\r':
		goto loop;
	case '\n':
		line++;
		goto loop;
	case '.':
		c = Bgetc(bin);
		Bungetc(bin);
		if(isdigit(c))
			return numsym('.');
		return '.';
	case '#':
		eatnl();
		goto loop;
	case '(':
	case ')':
	case ';':
	case ',':
	case '~':
	case '$':
	case '+':
	case '/':
	case '%':
	case '^':
	case '*':
	case '&':
	case '=':
	case '|':
	case '<':
	case '>':
	case '-':
	case ':':
		return c;
	case '\'':
		c = Bgetrune(bin);
		if(c == '\\')
			yylval.ival = escchar(Bgetc(bin));
		else
			yylval.ival = c;
		c = Bgetc(bin);
		if(c != '\'') {
			diag("missing '");
			Bungetc(bin);
		}
		return TCONST;

	default:
		return numsym(c);
	}
}

int
numsym(char first)
{
	int c;
	char *p;
	Sym *s;
	enum { Int, Hex, Frac, Expsign, Exp } state;

	symbol[0] = first;
	p = symbol;

	if(first == '.')
		state = Frac;
	else
		state = Int;

	if(isdigit(*p++) || state == Frac) {
		for(;;) {
			c = Bgetc(bin);
			if(c < 0)
				fatal("%d: <eof> eating numeric", line);

			switch(state) {
			case Int:
				if(strchr("01234567890", c))
					break;
				switch(c) {
				case 'x':
				case 'X':
					state = Hex;
					break;
				case '.':
					state = Frac;
					break;
				case 'e':
				case 'E':
					state = Expsign;
					break;
				default:
					goto done;
				}
				break;
			case Hex:
				if(strchr("01234567890abcdefABCDEF", c) == 0)
					goto done;
				break;
			case Frac:
				if(strchr("01234567890", c))
					break;
				if(c == 'e' || c == 'E')
					state = Expsign;
				else
					goto done;
				break;
			case Expsign:
				state = Exp;
				if(c == '-' || c == '+')
					break;
				/* else fall through */
			case Exp:
				if(strchr("01234567890", c) == 0)
					goto done;
				break;
			}
			*p++ = c;
		}
	done:
		Bungetc(bin);
		*p = '\0';
		switch(state) {
		default:
			yylval.ival = strtoll(symbol, 0, 0);
			return TCONST;
		case Frac:
		case Expsign:
		case Exp:
			yylval.fval = strtod(symbol, 0);
			return TFCONST;
		}
	}

	for(;;) {
		c = Bgetc(bin);
		if(c < 0)
			fatal("%d <eof> eating symbols", line);
		/* '$' and '/' can occur in fully-qualified Java class names */
		if(c != '_' && c != '.' && c != '/' && c != '$' && !isalnum(c)) {
			Bungetc(bin);
			break;
		}
		*p++ = c;
	}

	*p = '\0';

	s = enter(symbol, TID);
	switch(s->lexval) {
	default:
		yylval.sym = s;
		break;
	case TOKI0:
	case TOKI1:
	case TOKI2:
	case TOKI3:
		yylval.ival = s->value;
		break;
	}
	return s->lexval;
}

static Sym *hash[Hashsize];

Sym *
enter(char *name, int type)
{
	Sym *s;
	ulong h;
	char *p;

	s = lookup(name);
	if(s != nil)
		return s;

	h = 0;
	for(p = name; *p; p++)
		h = h*3 + *p;
	h %= Hashsize;

	s = malloc(sizeof(Sym));
	memset(s, 0, sizeof(Sym));
	s->name = strdup(name);
	s->lexval = type;
	s->hash = hash[h];
	hash[h] = s;
	return s;
}

Sym *
lookup(char *name)
{
	Sym *s;
	ulong h;
	char *p;

	h = 0;
	for(p = name; *p; p++)
		h = h*3 + *p;
	h %= Hashsize;

	for(s = hash[h]; s; s = s->hash)
		if(strcmp(name, s->name) == 0)
			return s;
	return 0;
}

void
yyerror(char *a, ...)
{
	va_list arg;
	char buf[128];

	if(strcmp(a, "syntax error") == 0) {
		yyerror("syntax error, near symbol '%s'", symbol);
		return;
	}
	va_start(arg, a);
	vseprint(buf, buf+sizeof(buf), a, arg);
	va_end(arg);
	print("%s %d: %s\n", file, line, buf);
	if(nerr++ > 10) {
		fprint(2, "%s %d: too many errors, giving up\n", file, line);
		remove(ofile);
		exits("yyerror");
	}
}

void
fatal(char *fmt, ...)
{
	va_list arg;
	char buf[512];

	va_start(arg, fmt);
	vseprint(buf, buf+sizeof(buf), fmt, arg);
	va_end(arg);
	fprint(2, "asm: %d (fatal compiler problem) %s\n", line, buf);
	exits(buf);
}

void
diag(char *fmt, ...)
{
	int srcline;
	va_list arg;
	char buf[512];

	srcline = line;
	va_start(arg, fmt);
	vseprint(buf, buf+sizeof(buf), fmt, arg);
	va_end(arg);
	fprint(2, "%s %d: %s\n", file, srcline, buf);
	if(nerr++ > 10) {
		fprint(2, "%s %d: too many errors, giving up\n", file, line);
		remove(ofile);
		exits("errors");
	}
}

Inst*
ai(int op)
{
	Inst *i;

	i = malloc(sizeof(Inst));
	memset(i, 0, sizeof(Inst));
	i->op = op;

	return i;
}

Addr*
aa(int val)
{
	Addr *a;

	a = malloc(sizeof(Addr));
	memset(a, 0, sizeof(Addr));
	a->val = val;
	if(val <= -1073741824 && val > 1073741823)
		diag("offset out of range");

	return a;
}

vlong
dtocanon(double d)
{
	int swap;
	ulong t;
	union { double d; ulong ul[2]; } u1;
	union { vlong v; ulong ul[2]; } u2;

	u2.v = 1;
	swap = u2.ul[0];
	u1.d = 1.;
	if(u1.ul[0]){
		u1.d = d;
		u2.ul[0] = u1.ul[0];
		u2.ul[1] = u1.ul[1];
	}else{
		u1.d = d;
		u2.ul[0] = u1.ul[1];
		u2.ul[1] = u1.ul[0];
	}
	if(swap){
		t = u2.ul[0];
		u2.ul[0] = u2.ul[1];
		u2.ul[1] = t;
	}
	return u2.v;
}
