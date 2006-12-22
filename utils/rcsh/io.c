#include "rc.h"

int	pfmtnest=0;

void	pdec(Io*, long);
void	poct(Io*, ulong);
void	phex(Io*, long);
void	pquo(Io*, char*);
void	pwrd(Io*, char*);
void	pcmd(Io*, Tree*);
void	pval(Io*, Word*);

void
pfmt(Io *f, char *fmt, ...)
{
	va_list ap;

	va_start(ap, fmt);
	pfmtnest++;
	for(;*fmt;fmt++) {
		if(*fmt!='%') pchr(f, *fmt);
		else switch(*++fmt){
		case '\0': va_end(ap); return;
		case 'c': pchr(f, va_arg(ap, int)); break;
		case 'd': pdec(f, va_arg(ap, int)); break;
		case 'o': poct(f, va_arg(ap, unsigned)); break;
		case 'p': phex(f, (long)va_arg(ap, char *)); break; /*unportable*/
		case 'Q': pquo(f, va_arg(ap, char *)); break;
		case 'q': pwrd(f, va_arg(ap, char *)); break;
		case 'r': perr(f); break;
		case 's': pstr(f, va_arg(ap, char *)); break;
		case 't': pcmd(f, va_arg(ap, Tree *)); break;
		case 'v': pval(f, va_arg(ap, Word *)); break;
		default: pchr(f, *fmt); break;
		}
	}
	va_end(ap);
	if(--pfmtnest==0) flush(f);
}

void
perr(Io *f)
{
	char err[ERRMAX];
	
	err[0] = 0;
	errstr(err, sizeof err);
	pstr(f, err);
	errstr(err, sizeof err);
}

void
pquo(Io *f, char *s)
{
	pchr(f, '\'');
	for(;*s;s++)
		if(*s=='\'') pfmt(f, "''");
		else pchr(f, *s);
	pchr(f, '\'');
}

void
pwrd(Io *f, char *s)
{
	char *t;
	for(t=s;*t;t++)
		if(!wordchr(*t))
			break;
	if(t==s || *t)
		pquo(f, s);
	else
		pstr(f, s);
}

void
phex(Io *f, long p)
{
	int n;
	for(n=28;n>=0;n-=4) pchr(f, "0123456789ABCDEF"[(p>>n)&0xF]);
}

void
pstr(Io *f, char *s)
{
	if(s==0)
		s="(null)";
	while(*s)
		pchr(f, *s++);
}

void
pdec(Io *f, long n)
{
	if(n<0){
		n=-n;
		if(n>=0){
			pchr(f, '-');
			pdec(f, n);
			return;
		}
		/* n is two's complement minimum integer */
		n=1-n;
		pchr(f, '-');
		pdec(f, n/10);
		pchr(f, n%10+'1');
		return;
	}
	if(n>9) pdec(f, n/10);
	pchr(f, n%10+'0');
}

void
poct(Io *f, ulong n)
{
	if(n>7) poct(f, n>>3);
	pchr(f, (n&7)+'0');
}

void
pval(Io *f, Word *a)
{
	if(a){
		while(a->next && a->next->word){
			pwrd(f, a->word);
			pchr(f, ' ');
			a=a->next;
		}
		pwrd(f, a->word);
	}
}

int
fullbuf(Io *f, int c)
{
	flush(f);
	return *f->bufp++=c;
}

void
flush(Io *f)
{
	int n;
	char *s;
	if(f->strp){
		n=f->ebuf-f->strp;
		f->strp=realloc(f->strp, n+101);
		if(f->strp==0)
			panic("Can't realloc %d bytes in flush!", n+101);
		f->bufp=f->strp+n;
		f->ebuf=f->bufp+100;
		for(s=f->bufp;s<=f->ebuf;s++) *s='\0';
	}
	else{
		n=f->bufp-f->buf;
		if(n && write(f->fd, f->buf, n) < 0){
/*			write(3, "Write error\n", 12); 
			if(ntrap.ref)
				dotrap();
*/
		}
		f->bufp=f->buf;
		f->ebuf=f->buf+NBUF;
	}
}

Io *
openfd(int fd)
{
	Io *f = new(Io);
	f->fd = fd;
	f->bufp = f->ebuf = f->buf;
	f->strp = 0;
	return f;
}

Io *
openstr(void)
{
	Io *f=new(struct Io);
	char *s;
	f->fd=-1;
	f->bufp=f->strp=malloc(101);
	f->ebuf=f->bufp+100;
	for(s=f->bufp;s<=f->ebuf;s++)
		*s='\0';
	return f;
}

/*
 * Open a corebuffer to read.  EOF occurs after reading len
 * characters from buf.
 */
Io *
opencore(char *s, int len)
{
	Io *f;
	char *buf;

	f = new(Io);
	buf = malloc(len);
	f->fd = -1;
	f->bufp = f->strp=buf;
	f->ebuf = buf+len;
	memmove(buf, s, len);

	return f;
}

void
rewind(Io *io)
{
	if(io->fd==-1) {
		io->bufp = io->strp;
	} else {
		io->bufp = io->ebuf = io->buf;
		seek(io->fd, 0L, 0);
	}
}

void
closeio(Io *io)
{
	if(io->fd>=0)
		close(io->fd);
	if(io->strp)
		free(io->strp);
	free(io);
}

int 
emptybuf(Io *f)
{
	int n;
	if(f->fd==-1 || (n=read(f->fd, f->buf, NBUF))<=0) return EOF;
	f->bufp=f->buf;
	f->ebuf=f->buf+n;
	return *f->bufp++&0xff;
}
