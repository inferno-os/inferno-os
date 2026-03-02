/*
 * ChaCha20 stream cipher (RFC 8439).
 * Daniel J. Bernstein's ChaCha variant with 20 rounds.
 */
#include "os.h"
#include <libsec.h>

#define ROTL(x, n) (((x) << (n)) | ((x) >> (32-(n))))

#define QR(a, b, c, d) \
	a += b; d ^= a; d = ROTL(d, 16); \
	c += d; b ^= c; b = ROTL(b, 12); \
	a += b; d ^= a; d = ROTL(d,  8); \
	c += d; b ^= c; b = ROTL(b,  7)

static void
chacha_block(u32int out[16], const u32int in[16], int rounds)
{
	u32int x[16];
	int i;

	memmove(x, in, 64);

	for(i = 0; i < rounds; i += 2){
		/* column round */
		QR(x[0], x[4], x[ 8], x[12]);
		QR(x[1], x[5], x[ 9], x[13]);
		QR(x[2], x[6], x[10], x[14]);
		QR(x[3], x[7], x[11], x[15]);
		/* diagonal round */
		QR(x[0], x[5], x[10], x[15]);
		QR(x[1], x[6], x[11], x[12]);
		QR(x[2], x[7], x[ 8], x[13]);
		QR(x[3], x[4], x[ 9], x[14]);
	}

	for(i = 0; i < 16; i++)
		out[i] = x[i] + in[i];
}

static u32int
le32(const uchar *p)
{
	return (u32int)p[0] | ((u32int)p[1]<<8)
	     | ((u32int)p[2]<<16) | ((u32int)p[3]<<24);
}

static void
put32(uchar *p, u32int v)
{
	p[0] = v; p[1] = v>>8; p[2] = v>>16; p[3] = v>>24;
}

void
setupChaChastate(ChaChastate *s, uchar *key, int keylen, uchar *nonce, int noncelen, int rounds)
{
	memset(s, 0, sizeof(*s));
	s->rounds = rounds;

	/* "expand 32-byte k" or "expand 16-byte k" */
	if(keylen == 32){
		s->state[0] = 0x61707865;
		s->state[1] = 0x3320646e;
		s->state[2] = 0x79622d32;
		s->state[3] = 0x6b206574;
		s->state[4] = le32(key);
		s->state[5] = le32(key+4);
		s->state[6] = le32(key+8);
		s->state[7] = le32(key+12);
		s->state[8] = le32(key+16);
		s->state[9] = le32(key+20);
		s->state[10] = le32(key+24);
		s->state[11] = le32(key+28);
	} else {
		/* 16-byte key */
		s->state[0] = 0x61707865;
		s->state[1] = 0x3120646e;
		s->state[2] = 0x79622d36;
		s->state[3] = 0x6b206574;
		s->state[4] = le32(key);
		s->state[5] = le32(key+4);
		s->state[6] = le32(key+8);
		s->state[7] = le32(key+12);
		s->state[8] = le32(key);
		s->state[9] = le32(key+4);
		s->state[10] = le32(key+8);
		s->state[11] = le32(key+12);
	}

	s->state[12] = 0;  /* counter */
	if(noncelen == 12){
		s->state[13] = le32(nonce);
		s->state[14] = le32(nonce+4);
		s->state[15] = le32(nonce+8);
	} else if(noncelen == 8){
		s->state[13] = 0;
		s->state[14] = le32(nonce);
		s->state[15] = le32(nonce+4);
	}
	s->blen = 0;
}

void
chacha_setctr(ChaChastate *s, u32int ctr)
{
	s->state[12] = ctr;
	s->blen = 0;
}

void
chacha_encrypt(uchar *src, int n, ChaChastate *s)
{
	u32int block[16];
	int i, m;

	/* use leftover keystream first */
	while(s->blen > 0 && n > 0){
		*src++ ^= s->buf[ChachaBsize - s->blen];
		s->blen--;
		n--;
	}

	while(n > 0){
		chacha_block(block, s->state, s->rounds);
		s->state[12]++;

		/* serialize to bytes */
		for(i = 0; i < 16; i++)
			put32(s->buf + 4*i, block[i]);

		m = n < ChachaBsize ? n : ChachaBsize;
		for(i = 0; i < m; i++)
			src[i] ^= s->buf[i];
		src += m;
		n -= m;

		if(m < ChachaBsize)
			s->blen = ChachaBsize - m;
	}
}
