/*
 * Poly1305 MAC (RFC 8439, Section 2.5).
 * Based on Daniel J. Bernstein's design.
 */
#include "os.h"
#include <libsec.h>

static u32int
le32(const uchar *p)
{
	return (u32int)p[0] | ((u32int)p[1]<<8)
	     | ((u32int)p[2]<<16) | ((u32int)p[3]<<24);
}

void
setupPoly1305(Poly1305state *s, uchar key[32])
{
	memset(s, 0, sizeof(*s));

	/* r = key[0..15] with clamping (26-bit limbs) */
	s->r[0] = le32(key) & 0x3ffffff;
	s->r[1] = (le32(key+3) >> 2) & 0x3ffff03;
	s->r[2] = (le32(key+6) >> 4) & 0x3ffc0ff;
	s->r[3] = (le32(key+9) >> 6) & 0x3f03fff;
	s->r[4] = (le32(key+12) >> 8) & 0x00fffff;

	/* pad = key[16..31] */
	s->pad[0] = le32(key+16);
	s->pad[1] = le32(key+20);
	s->pad[2] = le32(key+24);
	s->pad[3] = le32(key+28);

	memset(s->h, 0, sizeof(s->h));
	s->mlen = 0;
}

static void
poly1305_block(Poly1305state *s, const uchar *m, int final)
{
	u32int hibit = final ? 0 : (1 << 24);
	u64int r0, r1, r2, r3, r4;
	u64int s1, s2, s3, s4;
	u64int h0, h1, h2, h3, h4;
	u64int d0, d1, d2, d3, d4;
	u64int c;

	h0 = s->h[0]; h1 = s->h[1]; h2 = s->h[2]; h3 = s->h[3]; h4 = s->h[4];
	r0 = s->r[0]; r1 = s->r[1]; r2 = s->r[2]; r3 = s->r[3]; r4 = s->r[4];
	s1 = r1 * 5; s2 = r2 * 5; s3 = r3 * 5; s4 = r4 * 5;

	/* h += m */
	h0 += le32(m) & 0x3ffffff;
	h1 += (le32(m+3) >> 2) & 0x3ffffff;
	h2 += (le32(m+6) >> 4) & 0x3ffffff;
	h3 += (le32(m+9) >> 6) & 0x3ffffff;
	h4 += (le32(m+12) >> 8) | hibit;

	/* h *= r (mod 2^130 - 5) */
	d0 = h0*r0 + h1*s4 + h2*s3 + h3*s2 + h4*s1;
	d1 = h0*r1 + h1*r0 + h2*s4 + h3*s3 + h4*s2;
	d2 = h0*r2 + h1*r1 + h2*r0 + h3*s4 + h4*s3;
	d3 = h0*r3 + h1*r2 + h2*r1 + h3*r0 + h4*s4;
	d4 = h0*r4 + h1*r3 + h2*r2 + h3*r1 + h4*r0;

	/* carry propagation */
	c = d0 >> 26; h0 = d0 & 0x3ffffff;
	d1 += c;      c = d1 >> 26; h1 = d1 & 0x3ffffff;
	d2 += c;      c = d2 >> 26; h2 = d2 & 0x3ffffff;
	d3 += c;      c = d3 >> 26; h3 = d3 & 0x3ffffff;
	d4 += c;      c = d4 >> 26; h4 = d4 & 0x3ffffff;
	h0 += c * 5;  c = h0 >> 26; h0 &= 0x3ffffff;
	h1 += c;

	s->h[0] = h0; s->h[1] = h1; s->h[2] = h2; s->h[3] = h3; s->h[4] = h4;
}

void
poly1305_update(Poly1305state *s, uchar *msg, int len)
{
	int want;

	/* handle buffered data */
	if(s->mlen > 0){
		want = 16 - s->mlen;
		if(len < want){
			memmove(s->mbuf + s->mlen, msg, len);
			s->mlen += len;
			return;
		}
		memmove(s->mbuf + s->mlen, msg, want);
		poly1305_block(s, s->mbuf, 0);
		msg += want;
		len -= want;
		s->mlen = 0;
	}

	/* process full blocks */
	while(len >= 16){
		poly1305_block(s, msg, 0);
		msg += 16;
		len -= 16;
	}

	/* buffer remainder */
	if(len > 0){
		memmove(s->mbuf, msg, len);
		s->mlen = len;
	}
}

void
poly1305_finish(uchar tag[16], Poly1305state *s)
{
	u64int h0, h1, h2, h3, h4;
	u64int g0, g1, g2, g3, g4;
	u64int c, mask;
	u64int f;

	/* process final partial block */
	if(s->mlen > 0){
		s->mbuf[s->mlen] = 1;
		memset(s->mbuf + s->mlen + 1, 0, 16 - s->mlen - 1);
		poly1305_block(s, s->mbuf, 1);
	}

	h0 = s->h[0]; h1 = s->h[1]; h2 = s->h[2]; h3 = s->h[3]; h4 = s->h[4];

	/* fully carry h */
	c = h1 >> 26; h1 &= 0x3ffffff;
	h2 += c;    c = h2 >> 26; h2 &= 0x3ffffff;
	h3 += c;    c = h3 >> 26; h3 &= 0x3ffffff;
	h4 += c;    c = h4 >> 26; h4 &= 0x3ffffff;
	h0 += c*5;  c = h0 >> 26; h0 &= 0x3ffffff;
	h1 += c;

	/* compute h + -p = h - (2^130 - 5) */
	g0 = h0 + 5; c = g0 >> 26; g0 &= 0x3ffffff;
	g1 = h1 + c; c = g1 >> 26; g1 &= 0x3ffffff;
	g2 = h2 + c; c = g2 >> 26; g2 &= 0x3ffffff;
	g3 = h3 + c; c = g3 >> 26; g3 &= 0x3ffffff;
	g4 = h4 + c - (1 << 26);

	/* select h if h < p, else g */
	mask = (g4 >> 63) - 1;  /* -1 if g4 >= 0 (no underflow), 0 if g4 < 0 */
	g0 &= mask; g1 &= mask; g2 &= mask; g3 &= mask; g4 &= mask;
	mask = ~mask;
	h0 = (h0 & mask) | g0;
	h1 = (h1 & mask) | g1;
	h2 = (h2 & mask) | g2;
	h3 = (h3 & mask) | g3;
	h4 = (h4 & mask) | g4;

	/* h = h % (2^128) + pad */
	h0 = (h0 | (h1 << 26)) & 0xffffffff;
	h1 = ((h1 >> 6) | (h2 << 20)) & 0xffffffff;
	h2 = ((h2 >> 12) | (h3 << 14)) & 0xffffffff;
	h3 = ((h3 >> 18) | (h4 << 8)) & 0xffffffff;

	f = h0 + s->pad[0]; h0 = f & 0xffffffff;
	f = h1 + s->pad[1] + (f >> 32); h1 = f & 0xffffffff;
	f = h2 + s->pad[2] + (f >> 32); h2 = f & 0xffffffff;
	f = h3 + s->pad[3] + (f >> 32); h3 = f & 0xffffffff;

	tag[0]  = h0; tag[1]  = h0>>8; tag[2]  = h0>>16; tag[3]  = h0>>24;
	tag[4]  = h1; tag[5]  = h1>>8; tag[6]  = h1>>16; tag[7]  = h1>>24;
	tag[8]  = h2; tag[9]  = h2>>8; tag[10] = h2>>16; tag[11] = h2>>24;
	tag[12] = h3; tag[13] = h3>>8; tag[14] = h3>>16; tag[15] = h3>>24;
}
