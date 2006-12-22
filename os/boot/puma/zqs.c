#include "boot.h"
#include "squeeze.h"

#define	EXECHDRLEN	(8*4)

typedef struct Squeeze Squeeze;
struct Squeeze {
	int	n;
	ulong	tab[7*256];
};

#define	GET4(p)	(((((((p)[0]<<8)|(p)[1])<<8)|(p)[2])<<8)|(p)[3])

/*
 * for speed of unsqueezing from Flash, certain checks are
 * not done inside the loop (as they would be in the unsqueeze program zqs),
 * but instead the checksum is expected to catch corrupted files.
 * in fact the Squeeze array bounds can't be exceeded in practice
 * because the tables are always full for a squeezed kernel.
 */
enum {
	QFLAG = 1,	/* invert powerpc-specific code transformation */
	CHECK = 0,	/* check precise bounds in Squeeze array (otherwise checksum detects error) */
};

static	ulong	chksum;
static	int	rdtab(Block*, Squeeze*, int);
static	ulong*	unsqueeze(ulong*, uchar*, uchar*, Squeeze*, Squeeze*, ulong);
static	uchar*	unsqzseg(uchar*, Block*, long, long, char*);
static	Alarm*	unsqzal;

int
issqueezed(uchar *b)
{
	return GET4(b) == SQMAGIC? GET4(b+SQHDRLEN): 0;
}

static void
unsqzdot(void*)
{
	unsqzal = alarm(500, unsqzdot, nil);
	print(".");
}

long
unsqueezef(Block *b, ulong *entryp)
{
	uchar *loada, *wp;
	ulong toptxt, topdat, oldsum;
	long asis, nst, nsd;
	Sqhdr *sqh;
	Exec *ex;

	if(BLEN(b) < SQHDRLEN+EXECHDRLEN)
		return -1;
	sqh = (Sqhdr*)b->rp;
	if(GET4(sqh->magic) != SQMAGIC)
		return -1;
	chksum = 0;
	toptxt = GET4(sqh->toptxt);
	topdat = GET4(sqh->topdat);
	oldsum = GET4(sqh->sum);
	asis = GET4(sqh->asis);
	nst = GET4(sqh->text);
	nsd = GET4(sqh->data);
	b->rp += SQHDRLEN;
	ex = (Exec*)b->rp;
	if(GET4(ex->magic) != E_MAGIC){
		print("zqs: not StrongARM executable\n");
		return -1;
	}
	*entryp = GET4(ex->entry);
	b->rp += EXECHDRLEN;
	loada = KADDR(PADDR(*entryp));
	wp = unsqzseg(loada, b, nst, toptxt, "text");
	if(wp == nil){
		print("zqs: format error\n");
		return -1;
	}
	if(nsd){
		wp = (uchar*)PGROUND((ulong)wp);
		wp = unsqzseg(wp, b, nsd, topdat, "data");
		if(wp == nil){
			print("zqs: format error\n");
			return -1;
		}
	}
	if(asis){
		memmove(wp, b->rp, asis);
		wp += asis;
		b->rp += asis;
	}
	if(chksum != oldsum){
		print("\nsqueezed kernel: checksum error: %8.8lux need %8.8lux\n", chksum, oldsum);
		return -1;
	}
	return wp-loada;
}

static uchar *
unsqzseg(uchar *wp, Block *b, long ns, long top, char *what)
{
	static Squeeze sq3, sq4;

	print("unpack %s %8.8lux %lud:", what, wp, ns);
	if(ns == 0)
		return wp;
	if(rdtab(b, &sq3, 0) < 0)
		return nil;
	if(rdtab(b, &sq4, 8) < 0)
		return nil;
	if(BLEN(b) < ns){
		print(" **size error\n");
		return nil;
	}
	unsqzal = alarm(500, unsqzdot, nil);
	wp = (uchar*)unsqueeze((ulong*)wp, b->rp, b->rp+ns, &sq3, &sq4, top);
	cancel(unsqzal);
	unsqzal = nil;
	print("\n");
	if(wp == nil){
		print("zqs: corrupt squeezed data stream\n");
		return nil;
	}
	b->rp += ns;
	return wp;
}

static ulong*
unsqueeze(ulong *wp, uchar *rp, uchar *ep, Squeeze *sq3, Squeeze *sq4, ulong top)
{
	ulong nx, csum;
	int code, n;

	if(QFLAG){
		QREMAP(top);	/* adjust top just once, outside the loop */
	}
	csum = chksum;
	while(rp < ep){
		/* no function calls within this loop for speed */
		code = *rp;
		rp++;
		n = 0;
		nx = code>>4;
		do{
			if(nx == 0){
				nx = top;
			}else{
				if(nx==1){
					nx = (((((rp[3]<<8)|rp[2])<<8)|rp[1])<<8)|rp[0];
					rp += 4;
				}else if(nx <= 8){	/* 2 to 8 */
					nx = ((nx-2)<<8) | rp[0];
					if(CHECK && nx >= sq4->n)
						return nil;	/* corrupted file */
					nx = sq4->tab[nx] | rp[1];
					rp += 2;
				}else{	/* 9 to 15 */
					nx = ((nx-9)<<8) | rp[0];
					if(CHECK && nx >= sq3->n)
						return nil;	/* corrupted file */
					nx = sq3->tab[nx];
					rp++;
				}
				if(rp > ep)
					return nil;	/* corrupted file */
				if(QFLAG){
					QREMAP(nx);
				}
			}
			*wp = nx;
			wp++;
			csum += nx;
			nx = code & 0xF;
		}while(++n == 1);
	}
	chksum = csum;
	return wp;
}

static int
rdtab(Block *b, Squeeze *sq, int shift)
{
	uchar *p, *ep;
	ulong v, w;
	int i;

	if(BLEN(b) < 2)
		return -1;
	i = (b->rp[0]<<8) | b->rp[1];
	if(1)
		print(" T%d", i);
	b->rp += 2;
	if((i -= 2) > 0){
		if(BLEN(b) < i)
			return -1;
	}
	sq->n = 0;
	p = b->rp;
	ep = b->rp+i;
	b->rp += i;
	v = 0;
	while(p < ep){
		w = 0;
		do{
			if(p >= ep)
				return -1;
			w = (w<<7) | (*p & 0x7F);
		}while(*p++ & 0x80);
		v += w;
		if(0)
			print("%d %8.8lux %8.8lux\n", sq->n, v, w);
		sq->tab[sq->n++] = v<<shift;
	}
	return 0;
}
