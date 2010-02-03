#include "os.h"
#include <libsec.h>


enum {
	SHA512rounds =  80,
};

u64int sha512const[] = {
0x428a2f98d728ae22ULL, 0x7137449123ef65cdULL, 0xb5c0fbcfec4d3b2fULL, 0xe9b5dba58189dbbcULL,
0x3956c25bf348b538ULL, 0x59f111f1b605d019ULL, 0x923f82a4af194f9bULL, 0xab1c5ed5da6d8118ULL,
0xd807aa98a3030242ULL, 0x12835b0145706fbeULL, 0x243185be4ee4b28cULL, 0x550c7dc3d5ffb4e2ULL,
0x72be5d74f27b896fULL, 0x80deb1fe3b1696b1ULL, 0x9bdc06a725c71235ULL, 0xc19bf174cf692694ULL,
0xe49b69c19ef14ad2ULL, 0xefbe4786384f25e3ULL, 0x0fc19dc68b8cd5b5ULL, 0x240ca1cc77ac9c65ULL,
0x2de92c6f592b0275ULL, 0x4a7484aa6ea6e483ULL, 0x5cb0a9dcbd41fbd4ULL, 0x76f988da831153b5ULL,
0x983e5152ee66dfabULL, 0xa831c66d2db43210ULL, 0xb00327c898fb213fULL, 0xbf597fc7beef0ee4ULL,
0xc6e00bf33da88fc2ULL, 0xd5a79147930aa725ULL, 0x06ca6351e003826fULL, 0x142929670a0e6e70ULL,
0x27b70a8546d22ffcULL, 0x2e1b21385c26c926ULL, 0x4d2c6dfc5ac42aedULL, 0x53380d139d95b3dfULL,
0x650a73548baf63deULL, 0x766a0abb3c77b2a8ULL, 0x81c2c92e47edaee6ULL, 0x92722c851482353bULL,
0xa2bfe8a14cf10364ULL, 0xa81a664bbc423001ULL, 0xc24b8b70d0f89791ULL, 0xc76c51a30654be30ULL,
0xd192e819d6ef5218ULL, 0xd69906245565a910ULL, 0xf40e35855771202aULL, 0x106aa07032bbd1b8ULL,
0x19a4c116b8d2d0c8ULL, 0x1e376c085141ab53ULL, 0x2748774cdf8eeb99ULL, 0x34b0bcb5e19b48a8ULL,
0x391c0cb3c5c95a63ULL, 0x4ed8aa4ae3418acbULL, 0x5b9cca4f7763e373ULL, 0x682e6ff3d6b2b8a3ULL,
0x748f82ee5defb2fcULL, 0x78a5636f43172f60ULL, 0x84c87814a1f0ab72ULL, 0x8cc702081a6439ecULL,
0x90befffa23631e28ULL, 0xa4506cebde82bde9ULL, 0xbef9a3f7b2c67915ULL, 0xc67178f2e372532bULL,
0xca273eceea26619cULL, 0xd186b8c721c0c207ULL, 0xeada7dd6cde0eb1eULL, 0xf57d4f7fee6ed178ULL,
0x06f067aa72176fbaULL, 0x0a637dc5a2c898a6ULL, 0x113f9804bef90daeULL, 0x1b710b35131c471bULL,
0x28db77f523047d84ULL, 0x32caab7b40c72493ULL, 0x3c9ebe0a15c9bebcULL, 0x431d67c49c100d4cULL,
0x4cc5d4becb3e42b6ULL, 0x597f299cfc657e2aULL, 0x5fcb6fab3ad6faecULL, 0x6c44198c4a475817ULL,
};


static u32int
g32(uchar *p)
{
	return p[0]<<24|p[1]<<16|p[2]<<8|p[3]<<0;
}

static u64int
g64(uchar *p)
{
	return ((u64int)g32(p)<<32)|g32(p+4);
}


#define CH(x,y,z)	((x&y) ^ (~x&z))
#define MAJ(x,y,z)	((x&y) ^ (x&z) ^ (y&z))
#define ROTR32(n, v)	((v>>n) | (v<<(32-n)))
#define ROTR64(n, v)	((v>>n) | (v<<(64-n)))
#define SHR(n, x)	(x>>n)

#define SIGMA0b(x)	(ROTR64(28, x)^ROTR64(34, x)^ROTR64(39, x))
#define SIGMA1b(x)	(ROTR64(14, x)^ROTR64(18, x)^ROTR64(41, x))
#define sigma0b(x)	(ROTR64(1, x)^ROTR64(8, x)^SHR(7, x))
#define sigma1b(x)	(ROTR64(19, x)^ROTR64(61, x)^SHR(6, x))

#define A	v[0]
#define B	v[1]
#define C	v[2]
#define D	v[3]
#define E	v[4]
#define F	v[5]
#define G	v[6]
#define H	v[7]

void
_sha512block(SHA512state *s, uchar *buf)
{
	u64int w[2*SHA512bsize/8];
	int i, t;
	u64int t1, t2, t3, v[8];

	for(t = 0; t < nelem(w)/2; t++) {
		if(t < 16) {
			w[t] = g64(buf);
			buf += 8;
		}
	}

	memmove(v, s->h64, sizeof s->h64);

	for(t = 0; t < SHA512rounds; t++) {
		if(t >= 16) {
			/* w[t&31] = sigma1b(w[(t-2)&31]) + w[(t-7)&31] + sigma0b(w[(t-15)&31]) + w[(t-16)&31]; */
			t2 = w[(t-2)&31];
			t3 = w[(t-15)&31];
			/* w[t&31] = sigma1b(t2) + w[(t-7)&31] + sigma0b(t3) + w[(t-16)&31]; */
			t1 = sigma1b(t2);
			t1 += w[(t-7)&31];
			t1 +=  sigma0b(t3);
			t1 += w[(t-16)&31];
			w[t&31] = t1;
		}
		/* t1 = H + SIGMA1b(E) + CH(E,F,G) + sha512const[t] + w[t&31]; */
		t1 = H;
		t1 += SIGMA1b(E);
		t1 += CH(E, F, G);
		t1 += sha512const[t] + w[t&31];
		/* t2 = SIGMA0b(A) + MAJ(A,B,C); */
		t2 = SIGMA0b(A);
		t2 += MAJ(A, B, C);
		H = G;
		G = F;
		F = E;
		E = D+t1;
		D = C;
		C = B;
		B = A;
		A = t1+t2;
	}

	for(i = 0; i < nelem(v); i++)
		s->h64[i] += v[i];
}
