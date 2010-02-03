#include "os.h"
#include <libsec.h>

extern void _sha256block(SHA256state*, uchar*);
extern void _sha512block(SHA512state*, uchar*);

u32int sha224h0[] = {
0xc1059ed8, 0x367cd507, 0x3070dd17, 0xf70e5939,
0xffc00b31, 0x68581511, 0x64f98fa7, 0xbefa4fa4,
};
u32int sha256h0[] = {
0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19,
};

u64int sha384h0[] = {
0xcbbb9d5dc1059ed8ULL, 0x629a292a367cd507ULL, 0x9159015a3070dd17ULL, 0x152fecd8f70e5939ULL,
0x67332667ffc00b31ULL, 0x8eb44a8768581511ULL, 0xdb0c2e0d64f98fa7ULL, 0x47b5481dbefa4fa4ULL,
};
u64int sha512h0[] = {
0x6a09e667f3bcc908ULL, 0xbb67ae8584caa73bULL, 0x3c6ef372fe94f82bULL, 0xa54ff53a5f1d36f1ULL,
0x510e527fade682d1ULL, 0x9b05688c2b3e6c1fULL, 0x1f83d9abfb41bd6bULL, 0x5be0cd19137e2179ULL,
};


static SHA256state *
sha256init(void)
{
	SHA256state *s;

	s = malloc(sizeof(*s));
	if(s == nil)
		return nil;
	s->malloced = 1;
	s->seeded = 0;
	s->len = 0;
	s->blen = 0;

	return s;
}

static void
p32(u32int v, uchar *p)
{
	p[0] = v>>24;
	p[1] = v>>16;
	p[2] = v>>8;
	p[3] = v>>0;
}

static void
p64(u64int v, uchar *p)
{
	p32(v>>32, p);
	p32(v, p+4);
}

enum {
	HI	= 0,
	LO	= 1,
};
static void
p128(u64int v[2], uchar *p)
{
	p64(v[HI], p);
	p64(v[LO], p+8);
}

static void
uvvadd(u64int v[2], int n)
{
	v[LO] += n;
	if(v[LO] < n)  /* overflow */
		v[HI]++;
}

static void
uvvmult8(u64int v[2])
{
	v[HI] = (v[HI]<<3) | (v[LO] >> (64-3));
	v[LO] <<= 3;
}


static void
_sha256(uchar *p, ulong len, SHA256state *s)
{
	u32int take;

	/* complete possible partial block from last time */
	if(s->blen > 0 && s->blen+len >= SHA256bsize) {
		take = SHA256bsize-s->blen;
		memmove(s->buf+s->blen, p, take);
		p += take;
		len -= take;
		_sha256block(s, s->buf);
		s->len += SHA256bsize;
		s->blen = 0;
		memset(s->buf, 0, SHA256bsize);
	}
	/* whole blocks */
	while(len >= SHA256bsize) {
		_sha256block(s, p);
		s->len += SHA256bsize;
		p += SHA256bsize;
		len -= SHA256bsize;
	}
	/* keep possible leftover bytes */
	if(len > 0) {
		memmove(s->buf+s->blen, p, len);
		s->blen += len;
	}
}

static void
sha256finish(SHA256state *s, uchar *digest, int smaller)
{
	int i;
	uchar end[SHA256bsize+8];
	u32int nzero, nb, nd;

	nzero = (2*SHA256bsize - s->blen - 1 - 8) % SHA256bsize;
	end[0] = 0x80;
	memset(end+1, 0, nzero);
	nb = 8*(s->len+s->blen);
	p64(nb, end+1+nzero);
	_sha256(end, 1+nzero+8, s);

	nd = SHA256dlen/4;
	if(smaller)
		nd = SHA224dlen/4;
	for(i = 0; i < nd; i++, digest += 4)
		p32(s->h32[i], digest);
}

static SHA256state*
sha256x(uchar *p, ulong len, uchar *digest, SHA256state *s, int smaller)
{
	if(s == nil) {
		s = sha256init();
		if(s == nil)
			return nil;
	}

	if(s->seeded == 0){
		memmove(s->h32, smaller? sha224h0: sha256h0, sizeof s->h32);
		s->seeded = 1;
	}

	_sha256(p, len, s);

	if(digest == 0)
		return s;

	sha256finish(s, digest, smaller);
	if(s->malloced == 1)
		free(s);
	return nil;
}

SHA256state*
sha224(uchar *p, ulong len, uchar *digest, SHA256state *s)
{
	return sha256x(p, len, digest, s, 1);
}

SHA256state*
sha256(uchar *p, ulong len, uchar *digest, SHA256state *s)
{
	return sha256x(p, len, digest, s, 0);
}


static SHA512state *
sha512init(void)
{
	SHA512state *s;

	s = malloc(sizeof(*s));
	if(s == nil)
		return nil;
	s->malloced = 1;
	s->seeded = 0;
	s->nb128[HI] = 0;
	s->nb128[LO] = 0;
	s->blen = 0;

	return s;
}

static void
_sha512(uchar *p, ulong len, SHA512state *s)
{
	u32int take;

	/* complete possible partial block from last time */
	if(s->blen > 0 && s->blen+len >= SHA512bsize) {
		take = SHA512bsize-s->blen;
		memmove(s->buf+s->blen, p, take);
		p += take;
		len -= take;
		_sha512block(s, s->buf);
		uvvadd(s->nb128, SHA512bsize);
		s->blen = 0;
		memset(s->buf, 0, SHA512bsize);
	}
	/* whole blocks */
	while(len >= SHA512bsize) {
		_sha512block(s, p);
		uvvadd(s->nb128, SHA512bsize);
		p += SHA512bsize;
		len -= SHA512bsize;
	}
	/* keep possible leftover bytes */
	if(len > 0) {
		memmove(s->buf+s->blen, p, len);
		s->blen += len;
	}
}

void
sha512finish(SHA512state *s, uchar *digest, int smaller)
{
	int i;
	uchar end[SHA512bsize+16];
	u32int nzero, n;
	u64int nb[2];

	nzero = (2*SHA512bsize - s->blen - 1 - 16) % SHA512bsize;
	end[0] = 0x80;
	memset(end+1, 0, nzero);
	nb[0] = s->nb128[0];
	nb[1] = s->nb128[1];
	uvvadd(nb, s->blen);
	uvvmult8(nb);
	p128(nb, end+1+nzero);
	_sha512(end, 1+nzero+16, s);

	n = SHA512dlen/8;
	if(smaller)
		n = SHA384dlen/8;
	for(i = 0; i < n; i++, digest += 8)
		p64(s->h64[i], digest);
}

static SHA512state*
sha512x(uchar *p, ulong len, uchar *digest, SHA512state *s, int smaller)
{
	if(s == nil) {
		s = sha512init();
		if(s == nil)
			return nil;
	}

	if(s->seeded == 0){
		memmove(s->h64, smaller? sha384h0: sha512h0, sizeof s->h64);
		s->seeded = 1;
	}

	_sha512(p, len, s);

	if(digest == 0)
		return s;

	sha512finish(s, digest, smaller);
	if(s->malloced == 1)
		free(s);
	return nil;
}

SHA512state*
sha384(uchar *p, ulong len, uchar *digest, SHA512state *s)
{
	return sha512x(p, len, digest, s, 1);
}

SHA512state*
sha512(uchar *p, ulong len, uchar *digest, SHA512state *s)
{
	return sha512x(p, len, digest, s, 0);
}
