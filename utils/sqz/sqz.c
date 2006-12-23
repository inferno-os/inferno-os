#include <lib9.h>
#include <a.out.h>
#include "squeeze.h"

/*
 * forsyth@vitanuova.com
 */

typedef struct Word Word;
struct Word {
	ulong	v;
	ushort	freq;
	ushort	code;
	Word*	next;
};

typedef struct Squeeze Squeeze;
struct Squeeze {
	int	n;
	/*union {*/
		ulong	tab[7*256];
		Word*	rep[7*256];
	/*};*/
};

enum {
	HMASK = 0xFFFF,
	HSIZE = HMASK+1,

	Codebufsize = 3*1024*1024
};

#define	GET4(p)	(((((((p)[0]<<8)|(p)[1])<<8)|(p)[2])<<8)|(p)[3])
#define	GET4L(p)	(((((((p)[3]<<8)|(p)[2])<<8)|(p)[1])<<8)|(p)[0])
#define	PUT4(p,v)	(((p)[0]=(v)>>24),((p)[1]=(v)>>16),((p)[2]=(v)>>8),((p)[3]=(v)))

static	uchar	prog[Codebufsize];
static	uchar	outbuf[Codebufsize];
static	Word*	hash1[HSIZE];
static	Word*	hash2[HSIZE];
static	Sqhdr	sqhdr;
static	ulong	chksum;

static	int	dflag;	/* squeeze data, not text */
static	int	tflag;		/* squeeze text, leave data as-is */
static	int	qflag = 1;	/* enable powerpc option */
static	int	wflag;	/* write output */
static	int	islittle;		/* object code uses little-endian byte order */
static	int	debug;
static	char*	fname;

static	void	analyse(ulong*, int, Squeeze*, Squeeze*, Word**);
static	Word**	collate(Word**, int);
static	void	dumpsq(Squeeze*, int);
static	void	freehash(Word**);
static	long	Read(int, void*, long);
static	void	remap(Squeeze*);
static	int	squeeze(ulong*, int, uchar*, ulong);
static	int	squeezetab(int, int, Squeeze*, Word**, int);
static	void	squirt(int, Squeeze*);
static	void	Write(int, void*, long);

static void
usage(void)
{
	fprint(2, "Usage: sqz [-w] [-t] [-d] [-q] q.out\n");
	exits("usage");
}

void
main(int argc, char **argv)
{
	int fd, n, ns, nst, nsd;
	long txtlen, datlen, asis;
	ulong topdat, toptxt;
	Exec ex;
	Squeeze sq3, sq4, sq5, sq6;
	Word *top;

	setbinmode();
/*	fmtinstall('f', gfltconv); */
	ARGBEGIN{
	case 'D':
		debug++;
		break;
	case 'd':
		dflag++;
		break;
	case 'q':
		qflag = 0;
		break;
	case 't':
		tflag++;
		break;
	case 'w':
		wflag++;
		break;
	default:
		usage();
	}ARGEND
	fname = *argv;
	if(fname == nil)
		usage();
	fd = open(fname, OREAD);
	if(fd < 0){
		fprint(2, "sqz: can't open %s: %r\n", fname);
		exits("open");
	}
	Read(fd, &ex, sizeof(Exec));
	txtlen = GET4((uchar*)&ex.text);
	datlen = GET4((uchar*)&ex.data);
	switch(GET4((uchar*)&ex.magic)){
	case Q_MAGIC:	/* powerpc */
		islittle = 0;
		break;
	case E_MAGIC:	/* arm */
		islittle = 1;
		qflag = 0;
		break;
	case 0xA0E1:	/* arm AIF */
		islittle = 1;
		qflag = 0;
		txtlen = GET4L((uchar*)&ex+(5*4))-sizeof(Exec);
		datlen = GET4L((uchar*)&ex+(6*4));
		break;
	default:
		fprint(2, "sqz: unknown magic for sqz: %8.8ux\n", GET4((uchar*)&ex.magic));
		exits("bad magic");
	}
	if(qflag)
		fprint(2, "PowerPC rules\n");
	if(islittle)
		fprint(2, "Little endian\n");
	if(txtlen > sizeof(prog) || datlen > sizeof(prog) || txtlen+datlen > sizeof(prog)){
		fprint(2, "sqz: executable too big: %lud+%lud; increase Codebufsize in sqz.c\n", txtlen, datlen);
		exits("size");
	}
	if(dflag){
		seek(fd, txtlen, 1);
		Read(fd, prog, datlen);
	}else{
		Read(fd, prog, txtlen);
		Read(fd, prog+txtlen, datlen);
	}
	close(fd);
	asis = 0;
	if(dflag)
		n = datlen;
	else if(tflag){
		n = txtlen;
		asis = datlen;
	}else
		n = txtlen+datlen;
	if(dflag || tflag){
		analyse((ulong*)prog, n/4, &sq3, &sq4, &top);
		nst = squeeze((ulong*)prog, n/4, outbuf, top->v);
		if(nst < 0)
			exits("sqz");
		nsd = 0;
		remap(&sq3);
		remap(&sq4);
		toptxt = topdat = top->v;
	}else{
		analyse((ulong*)prog, txtlen/4, &sq3, &sq4, &top);
		nst = squeeze((ulong*)prog, txtlen/4, outbuf, top->v);
		if(nst < 0)
			exits("sqz");
		toptxt = top->v;
		remap(&sq3);
		remap(&sq4);
		if(datlen/4){
			freehash(hash1);
			freehash(hash2);
			analyse((ulong*)(prog+txtlen), datlen/4, &sq5, &sq6, &top);
			nsd = squeeze((ulong*)(prog+txtlen), datlen/4, outbuf+nst, top->v);
			if(nsd < 0)
				exits("sqz");
			topdat = top->v;
			remap(&sq5);
			remap(&sq6);
		}else{
			nsd = 0;
			topdat = 0;
		}
	}
	ns = nst+nsd;
	fprint(2, "%d/%d bytes\n", ns, n);
	fprint(2, "%8.8lux csum\n", chksum);
	if(!wflag)
		exits(0);
	PUT4(sqhdr.magic, SQMAGIC);
	PUT4(sqhdr.toptxt, toptxt);
	PUT4(sqhdr.sum, chksum);
	PUT4(sqhdr.text, nst);
	PUT4(sqhdr.topdat, topdat);
	PUT4(sqhdr.data, nsd);
	PUT4(sqhdr.asis, asis);
	PUT4(sqhdr.flags, 0);
	Write(1, &sqhdr, SQHDRLEN);
	Write(1, &ex, sizeof(Exec));
	squirt(1, &sq3);
	squirt(1, &sq4);
	Write(1, outbuf, nst);
	if(nsd){
		squirt(1, &sq5);
		squirt(1, &sq6);
		Write(1, outbuf+nst, nsd);
	}
	if(asis)
		Write(1, prog+txtlen, asis);
	exits(0);
}

static void
analyse(ulong *prog, int nw, Squeeze *sq3, Squeeze *sq4, Word **top)
{
	Word *w, **hp, **sorts, **resorts;
	ulong *rp, *ep;
	ulong v;
	int i, nv1, nv2, nv, nz;

	rp = prog;
	ep = prog+nw;
	nv = 0;
	nz = 0;
	while(rp < ep){
		if(islittle){
			v = GET4L((uchar*)rp);
		}else{
			v = GET4((uchar*)rp);
		}
		rp++;
		chksum += v;
		if(v == 0){
			nz++;
			if(0)
				continue;
		}
		if(qflag){
			QREMAP(v);
		}
		for(hp = &hash1[v&HMASK]; (w = *hp) != nil; hp = &w->next)
			if(w->v == v)
				break;
		if(w == nil){
			w = (Word*)malloc(sizeof(*w));
			w->v = v;
			w->freq = 0;
			w->code = 0;
			w->next = nil;
			*hp = w;
			nv++;
		}
		w->freq++;
	}
	sorts = collate(hash1, nv);
	fprint(2, "phase 1: %d/%d words (%d zero), %d top (%8.8lux)\n", nv, nw, nz, sorts[0]->freq, sorts[0]->v);
	*top = sorts[0];
	nv1 = squeezetab(1, 0x900, sq3, sorts+1, nv-1)+1;
	nv2 = 0;
	for(i=nv1; i<nv; i++){
		v = sorts[i]->v >> 8;
		for(hp = &hash2[v&HMASK]; (w = *hp) != nil; hp = &w->next)
			if(w->v == v)
				break;
		if(w == nil){
			w = (Word*)malloc(sizeof(*w));
			w->v = v;
			w->freq = 0;
			w->code = 0;
			w->next = nil;
			*hp = w;
			nv2++;
		}
		w->freq++;
	}
	free(sorts);
	resorts = collate(hash2, nv2);
	fprint(2, "phase 2: %d/%d\n", nv2, nv-nv1);
	squeezetab(2, 0x200, sq4, resorts, nv2);
	free(resorts);
	fprint(2, "phase 3: 1 4-code, %d 12-codes, %d 20-codes, %d uncoded\n",
		sq3->n, sq4->n, nv-(sq3->n+sq4->n+1));
}

static int
wdcmp(const void *a, const void *b)
{
	return (*(Word**)b)->freq - (*(Word**)a)->freq;
}

static Word **
collate(Word **tab, int nv)
{
	Word *w, **hp, **sorts;
	int i;

	sorts = (Word**)malloc(nv*sizeof(Word**));
	i = 0;
	for(hp = &tab[0]; hp < &tab[HSIZE]; hp++)
		for(w = *hp; w != nil; w = w->next)
			sorts[i++] = w;
	qsort(sorts, nv, sizeof(*sorts), wdcmp);
	if(debug > 1)
		for(i=0; i<nv; i++)
			fprint(2, "%d\t%d\t%8.8lux\n", i, sorts[i]->freq, sorts[i]->v);
	return sorts;
}

static int
tabcmp(const void *a, const void *b)
{
	ulong av, bv;

	av = (*(Word**)a)->v;
	bv = (*(Word**)b)->v;
	if(av > bv)
		return 1;
	if(av < bv)
		return -1;
	return 0;
}

static int
squeezetab(int tabno, int base, Squeeze *sq, Word **sorts, int nv)
{
	int i;

	if(nv >= 7*256)
		nv = 7*256;
	memset(sq, 0, sizeof(*sq));
	for(i=0; i<nv; i++)
		sq->rep[sq->n++] = sorts[i];
	qsort(sq->rep, sq->n, sizeof(*sq->rep), tabcmp);
	for(i=0; i<sq->n; i++)
		sq->rep[i]->code = base + i;
	if(debug)
		dumpsq(sq, tabno);
	return sq->n;
}

static void
dumpsq(Squeeze *sq, int n)
{
	int i;

	fprint(2, "table %d: %d entries\n", n, sq->n);
	for(i=0; i<sq->n; i++)
		fprint(2, "%.3x\t%8.8lux\t%lux\n", sq->rep[i]->code, sq->rep[i]->v, i? sq->rep[i]->v - sq->rep[i-1]->v: 0);
}

static void
remap(Squeeze *sq)
{
	int i;
	ulong v;

	if(sq->n){
		v = 0;
		for(i=0; i<sq->n; i++){
			sq->tab[i] = sq->rep[i]->v - v;
			v += sq->tab[i];
		}
	}
}

static Word *
squash(Word **tab, ulong v)
{
	Word *w, **hp;

	for(hp = &tab[v&0xFFFF]; (w = *hp) != nil; hp = &w->next)
		if(w->v == v)
			return w;
	return nil;
}

static void
freehash(Word **tab)
{
	Word *w, **hp;

	for(hp = &tab[0]; hp < &tab[HSIZE]; hp++)
		while((w = *hp) != nil){
			*hp = w->next;
			free(w);
		}
}

static int
squeeze(ulong *prog, int nw, uchar *out, ulong top)
{
	ulong *rp, *ep;
	ulong v, bits;
	ulong e1, e2, e3, e4;
	Word *w;
	uchar bytes[8], *bp, *wp;
	int ctl, n;

	rp = prog;
	ep = prog+nw;
	bits = 0;
	e1 = e2 = e3 = e4 = 0;
	wp = out;
	n = 0;
	ctl = 0;
	bp = bytes;
	for(;;){
		if(n == 2){
			*wp++ = ctl;
			if(0)
				fprint(2, "%x\n", ctl);
			memmove(wp, bytes, bp-bytes);
			wp += bp-bytes;
			bp = bytes;
			ctl = 0;
			n = 0;
		}
		ctl <<= 4;
		n++;
		if(rp >= ep){
			if(n == 1)
				break;
			continue;
		}
		if(islittle){
			v = GET4L((uchar*)rp);
		}else{
			v = GET4((uchar*)rp);
		}
		rp++;
		if(qflag){
			QREMAP(v);
		}
		if(v == top){
			e1++;
			bits += 4;
			ctl |= 0;
			continue;
		}
		w = squash(hash1, v);
		if(w && w->code){
			e2++;
			bits += 4+8;
			ctl |= w->code>>8;
			*bp++ = w->code;
			continue;
		}
		w = squash(hash2, v>>8);
		if(w && w->code){
			e3++;
			bits += 4+8+8;
			ctl |= w->code>>8;
			*bp++ = w->code;
			*bp++ = v & 0xFF;
			if(debug > 2)
				fprint(2, "%x %8.8lux %8.8lux\n", w->code, w->v, v);
			continue;
		}
		e4++;
		bits += 4+32;
		ctl |= 0x1;
		bp[0] = v;
		bp[1] = v>>8;
		bp[2] = v>>16;
		bp[3] = v>>24;
		bp += 4;
	}
	fprint(2, "enc: %lud 4-bits, %lud 12-bits %lud 20-bits %lud 36-bits -- %ld bytes\n",
		e1, e2, e3, e4, wp-out);
	return wp-out;
}

static void
squirt(int fd, Squeeze *sq)
{
	uchar b[7*256*5 + 2], rep[5], *p, *q;
	ulong v;
	int i;

	p = b+2;
	for(i=0; i<sq->n; i++){
		v = sq->tab[i];
		q = rep;
		do {
			*q++ = v & 0x7F;
		}while((v >>= 7) != 0);
		do {
			*p++ = *--q | 0x80;
		}while(q != rep);
		p[-1] &= ~0x80;
	}
	if(p > b+sizeof(b))
		abort();
	i = p-b;
	b[0] = i>>8;
	b[1] = i;
	Write(fd, b, i);
	fprint(2, "table: %d/%d\n", i, (sq->n+1)*4);
}

static long
Read(int fd, void *buf, long nb)
{
	long n;

	n = read(fd, buf, nb);
	if(n < 0){
		fprint(2, "sqz: %s: read error: %r\n", fname);
		exits("read");
	}
	if(n < nb){
		fprint(2, "sqz: %s: unexpected end-of-file\n", fname);
		exits("read");
	}
	return n;
}

static void
Write(int fd, void *buf, long nb)
{
	if(write(fd, buf, nb) != nb){
		fprint(2, "sqz: write error: %r\n");
		exits("write err");
	}
}
