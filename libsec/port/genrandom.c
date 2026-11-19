#include "os.h"
#include "kernel.h"
#include <mp.h>
#include <libsec.h>

/*
 * The generator behind genrandom: ChaCha20 with fast key erasure.
 * The key is 32 bytes of truerand, taken at first use. Each call makes
 * one keystream under the key and a nonce holding the time: the first
 * 32 bytes of it replace the key, and the rest is the caller's output,
 * so what has been given out cannot be recomputed from the state that
 * remains. (It replaces X9.17 over two-key triple DES, which had a
 * 64-bit state and 64-bit blocks under a 112-bit key: too little for
 * the 256-bit keys of X25519 and ML-KEM.)
 *
 * It is only as good as truerand's 256 bits.
 *
 * The ChaCha20 block function is written out here (it is 30 lines) so
 * that kernels configured without Crypt do not link Monocypher for it.
 */
enum {
	Keylen	= 32,
};

static struct {
	int	seeded;
	uchar	key[Keylen];
} rstate;

#define ROTL(x, n)	(((x)<<(n)) | ((x)>>(32-(n))))
#define QR(a, b, c, d)	\
	a += b; d ^= a; d = ROTL(d, 16);	\
	c += d; b ^= c; b = ROTL(b, 12);	\
	a += b; d ^= a; d = ROTL(d, 8);	\
	c += d; b ^= c; b = ROTL(b, 7)

/*
 * one 64-byte block of ChaCha20 (the original form: 64-bit block
 * counter, 64-bit nonce) under key
 */
static void
chachablock(uchar out[64], uchar key[Keylen], u32int ctr, uchar nonce[8])
{
	u32int x[16], s[16];
	int i;

	s[0] = 0x61707865;
	s[1] = 0x3320646e;
	s[2] = 0x79622d32;
	s[3] = 0x6b206574;
	for(i = 0; i < 8; i++)
		s[4+i] = key[4*i] | key[4*i+1]<<8 | key[4*i+2]<<16 | key[4*i+3]<<24;
	s[12] = ctr;
	s[13] = 0;
	for(i = 0; i < 2; i++)
		s[14+i] = nonce[4*i] | nonce[4*i+1]<<8 | nonce[4*i+2]<<16 | nonce[4*i+3]<<24;
	memmove(x, s, sizeof x);
	for(i = 0; i < 10; i++){
		QR(x[0], x[4], x[8], x[12]);
		QR(x[1], x[5], x[9], x[13]);
		QR(x[2], x[6], x[10], x[14]);
		QR(x[3], x[7], x[11], x[15]);
		QR(x[0], x[5], x[10], x[15]);
		QR(x[1], x[6], x[11], x[12]);
		QR(x[2], x[7], x[8], x[13]);
		QR(x[3], x[4], x[9], x[14]);
	}
	for(i = 0; i < 16; i++){
		x[i] += s[i];
		out[4*i] = x[i];
		out[4*i+1] = x[i]>>8;
		out[4*i+2] = x[i]>>16;
		out[4*i+3] = x[i]>>24;
	}
	memset(x, 0, sizeof x);
	memset(s, 0, sizeof s);
}

static void
rseed(void)
{
	int i;
	ulong x;

	for(i = 0; i < Keylen; i += 4){
		x = truerand();
		rstate.key[i] = x;
		rstate.key[i+1] = x>>8;
		rstate.key[i+2] = x>>16;
		rstate.key[i+3] = x>>24;
	}
	rstate.seeded = 1;
}

void
genrandom(uchar *p, int n)
{
	int i, m;
	u32int ctr;
	uvlong t;
	uchar nonce[8], blk[64], next[Keylen];

	if(n <= 0)
		return;
	_genrandomqlock();
	if(rstate.seeded == 0)
		rseed();
	t = nsec();
	for(i = 0; i < 8; i++)
		nonce[i] = t>>(8*i);
	/* block 0 gives the next key; the output starts at block 1 */
	chachablock(blk, rstate.key, 0, nonce);
	memmove(next, blk, Keylen);
	for(ctr = 1; n > 0; ctr++){
		chachablock(blk, rstate.key, ctr, nonce);
		m = n;
		if(m > sizeof blk)
			m = sizeof blk;
		memmove(p, blk, m);
		p += m;
		n -= m;
	}
	memmove(rstate.key, next, Keylen);
	memset(next, 0, sizeof next);
	memset(blk, 0, sizeof blk);
	_genrandomqunlock();
}
