#include "os.h"
#include "mp.h"
#include "libsec.h"

#define KEYLEN	52

#define	MODA	0x10000
#define	MODM	0x10001
#define	MASKA	(MODA-1)

#define 	OP1(x, y)		((x) ^ (y))
#define	OP2(x, y)		(((x) + (y)) & MASKA)
#define 	OP3(x, y)		mod(x, y)

#define	OP2INV(x)	(-(x))
#define	OP3INV(x)	inv(x)

#define BIGEND(k, i)	((k[i]<<8)|k[i+1])
#define MSB(x)		((x)>>8)
#define LSB(x)		((x)&0xff)

static ushort
mod(ushort x, ushort y)
{
	ushort q, r;
	uint z;

	if (x == 0)
		return 1-y;
	if (y == 0)
		return 1-x;
	z = (uint)x*(uint)y;
	q = z >> 16;
	r = z & MASKA;
	return r-q+(r<q);
}

static ushort 
inv(ushort x)
{
	int q, r0, r1, r2, v0, v1, v2;

	if (x <= 1)
		return x;
	r0 = MODM;
	r1 = x;
	v0 = 0;
	v1 = 1;
	while (r1 != 0) {
		q = r0/r1;
		r2 = r0-q*r1;
		v2 = v0-q*v1;
		r0 = r1;
		r1 = r2;
		v0 = v1;
		v1 = v2;
	}
	if (v0 < 0)
		v0 += MODM;
	return v0 & MASKA;
}

static void
idea_key_setup_decrypt(ushort ek[KEYLEN], ushort dk[KEYLEN])
{
	int i;

	for (i = 0; i < 54; i += 6) {
		dk[i] = OP3INV(ek[48-i]);
		dk[i+1] = OP2INV(ek[50-i]);
		dk[i+2] = OP2INV(ek[49-i]);
		dk[i+3] = OP3INV(ek[51-i]);
		if (i < 48) {
			dk[i+4] = ek[46-i];
			dk[i+5] = ek[47-i];
		}
	}
}

void
idea_key_setup(uchar key[16], ushort ek[2*KEYLEN])
{
	int i, j;
	ushort tmp, *e = ek;

	for (i = 0; i < 8; i++)
		ek[i] = BIGEND(key, 2*i);
	for (i = 8, j = 1; i < KEYLEN; i++, j++) {
		ek[i] = (e[j&7]<<9)|(e[(j+1)&7]>>7);
		if (((i+1) & 7) == 0)
			e += 8;
	}
	tmp = ek[49];
	ek[49] = ek[50];
	ek[50] = tmp;
	idea_key_setup_decrypt(ek, &ek[KEYLEN]);
}

void
idea_cipher(ushort key[2*KEYLEN], uchar text[8], int decrypting)
{
	int i;
	ushort *k;
	ushort x[4];
	ushort tmp, yout, zout;

	k = decrypting ? &key[KEYLEN] : key;
	for (i = 0; i < 4; i++)
		x[i] = BIGEND(text, 2*i);
	for (i = 0; i < 17; i++) {
		if (!(i&1)) {		/* odd round */
			x[0] = OP3(x[0], k[3*i]);
			tmp = OP2(x[2], k[3*i+2]);
			x[2] = OP2(x[1], k[3*i+1]);
			x[3] = OP3(x[3], k[3*i+3]);
			x[1] = tmp;
		}
		else {
			tmp = OP3(k[3*i+1], OP1(x[0], x[1]));
			yout = OP3(OP2(tmp, OP1(x[2], x[3])), k[3*i+2]);
			zout = OP2(tmp, yout);
			x[0] = OP1(x[0], yout);
			x[1] = OP1(x[1], yout);
			x[2] = OP1(x[2], zout);
			x[3] = OP1(x[3], zout);
		}
	}
	for (i = 0; i < 4; i++) {
		text[2*i] = MSB(x[i]); 
		text[2*i+1] = LSB(x[i]);
	}
}

void
setupIDEAstate(IDEAstate *s, uchar key[16], uchar *ivec)
{
	memset(s, 0, sizeof(*s));
	memmove(s->key, key, sizeof(s->key));
	idea_key_setup(key, s->edkey);
	if(ivec)
		memmove(s->ivec, ivec, 8);
}

/*
void
main()
{
	uchar key[] = { 0x00, 0x01, 0x00, 0x02, 0x00, 0x03, 0x00, 0x04,
			        0x00, 0x05, 0x00, 0x06, 0x00, 0x07, 0x00, 0x08 };
	uchar plain[] = { 0x00, 0x00, 0x00, 0x01, 0x00, 0x02, 0x00, 0x03 };
	uchar cipher[] = { 0x11, 0xFB, 0xED, 0x2B, 0x01, 0x98, 0x6D, 0xE5 };
	ushort edkey[2*KEYLEN];
	uchar tmp[8];

	memcpy(tmp, plain, 8);
	idea_key_setup(key, edkey);
	idea_cipher(edkey, tmp, 0);
	if (memcmp(tmp, cipher, 8)) {
		print("encrypt wrong\n");
		exits("");
	}
	idea_cipher(edkey, tmp, 1);
	if (memcmp(tmp, plain, 8)) {
		print("decrypt wrong\n");
		exits("");
	}
}
*/	
