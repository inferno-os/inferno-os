#include "os.h"
#include <libsec.h>

enum {
	SHA256rounds =  64,
};

u32int sha256const[] = {
0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
};


#define CH(x,y,z)	((x&y) ^ (~x&z))
#define MAJ(x,y,z)	((x&y) ^ (x&z) ^ (y&z))
#define ROTR32(n, v)	((v>>n) | (v<<(32-n)))
#define ROTR64(n, v)	((v>>n) | (v<<(64-n)))
#define SHR(n, x)	(x>>n)

#define SIGMA0a(x)	(ROTR32(2, x)^ROTR32(13, x)^ROTR32(22, x))
#define SIGMA1a(x)	(ROTR32(6, x)^ROTR32(11, x)^ROTR32(25, x))
#define sigma0a(x)	(ROTR32(7, x)^ROTR32(18, x)^SHR(3, x))
#define sigma1a(x)	(ROTR32(17, x)^ROTR32(19, x)^SHR(10, x))

/* for use in _sha*() */
#define A	v[0]
#define B	v[1]
#define C	v[2]
#define D	v[3]
#define E	v[4]
#define F	v[5]
#define G	v[6]
#define H	v[7]

static u32int
g32(uchar *p)
{
	return p[0]<<24|p[1]<<16|p[2]<<8|p[3]<<0;
}

void
_sha256block(SHA256state *s, uchar *buf)
{
	u32int w[2*SHA256bsize/4];
	int i, t;
	u32int t1, t2;
	u32int v[8];

	for(t = 0; t < nelem(w)/2; t++) {
		if(t < 16) {
			w[t] = g32(buf);
			buf += 4;
		}
	}

	memmove(v, s->h32, sizeof s->h32);

	for(t = 0; t < SHA256rounds; t++) {
		if(t >= 16)
			w[t&31] = sigma1a(w[(t-2)&31]) + w[(t-7)&31] + sigma0a(w[(t-15)&31]) + w[(t-16)&31];
		t1 = H + SIGMA1a(E) + CH(E,F,G) + sha256const[t] + w[t&31];
		t2 = SIGMA0a(A) + MAJ(A,B,C);
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
		s->h32[i] += v[i];
}
