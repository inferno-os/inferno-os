/*
 * Fuzz harness for Dis bytecode parser.
 *
 * Exercises the operand encoding, instruction decoding, and type
 * descriptor parsing from libinterp/load.c using arbitrary byte
 * streams.  Self-contained: the parsing primitives are extracted
 * here so we don't need the full Inferno kernel to link.
 */

#include <stdint.h>
#include <stddef.h>
#include <stdlib.h>
#include <string.h>

/* Dis bytecode constants (from include/isa.h) */
enum {
	XMAGIC	= 819248,
	SMAGIC	= 923426,

	AMP	= 0x00,
	AFP	= 0x01,
	AIMM	= 0x02,
	AIND	= 0x04,
	AMASK	= 0x07,

	ARM	= 0xC0,
	AXIMM	= 0x40,
	AXINF	= 0x80,
	AXINM	= 0xC0,
};

#define SRC(x)		((x)<<3)
#define DST(x)		((x)<<0)
#define UXSRC(x)	((x)&(AMASK<<3))
#define UXDST(x)	((x)&(AMASK<<0))

typedef unsigned char uchar;
typedef unsigned long ulong;

static uchar *codeend;

/*
 * Variable-length operand decoder (from libinterp/load.c).
 * This is the core parsing primitive for the Dis bytecode format.
 */
static int
operand(uchar **p)
{
	int c;
	uchar *cp;

	cp = *p;
	if(cp >= codeend)
		return -1;
	c = cp[0];
	switch(c & 0xC0) {
	case 0x00:
		*p = cp+1;
		return c;
	case 0x40:
		*p = cp+1;
		return c|~0x7F;
	case 0x80:
		if(cp+2 > codeend)
			return -1;
		*p = cp+2;
		if(c & 0x20)
			c |= ~0x3F;
		else
			c &= 0x3F;
		return (c<<8)|cp[1];
	case 0xC0:
		if(cp+4 > codeend)
			return -1;
		*p = cp+4;
		if(c & 0x20)
			c |= ~0x3F;
		else
			c &= 0x3F;
		return (c<<24)|(cp[1]<<16)|(cp[2]<<8)|cp[3];
	}
	return 0;
}

static ulong
disw(uchar **p)
{
	ulong v;
	uchar *c;

	c = *p;
	if(c+4 > codeend)
		return 0;
	v  = c[0] << 24;
	v |= c[1] << 16;
	v |= c[2] << 8;
	v |= c[3];
	*p = c + 4;
	return v;
}

/*
 * Parse a Dis module header and instruction stream.
 * Mirrors the structure of parsemod() in libinterp/load.c
 * but without allocating kernel structures.
 */
static int
parse_dis(uchar *code, size_t length)
{
	uchar *istream, **isp;
	int magic, isize, dsize, hsize, lsize, entry, entryt;
	int i, op, add, siglen, n;

	if(length < 4)
		return -1;

	istream = code;
	isp = &istream;
	codeend = code + length;

	/* Magic number */
	magic = operand(isp);
	switch(magic) {
	default:
		return -1;
	case SMAGIC:
		siglen = operand(isp);
		n = length - (*isp - code);
		if(siglen < 0 || n < 0 || siglen > n)
			return -1;
		/* Skip signature */
		*isp += siglen;
		break;
	case XMAGIC:
		break;
	}

	/* Module header */
	int rt = operand(isp);
	int ss = operand(isp);
	isize = operand(isp);
	dsize = operand(isp);
	hsize = operand(isp);
	lsize = operand(isp);
	entry = operand(isp);
	entryt = operand(isp);

	(void)rt;
	(void)ss;
	(void)entry;
	(void)entryt;

	if(isize < 0 || dsize < 0 || hsize < 0 || lsize < 0)
		return -1;
	if(isize > 1024*1024 || hsize > 1024*1024 || lsize > 1024*1024)
		return -1;

	/* Parse instruction stream */
	for(i = 0; i < isize && istream < codeend; i++) {
		if(istream + 2 > codeend)
			return -1;
		op = *istream++;
		add = *istream++;

		/* Middle operand */
		switch(add & ARM) {
		case AXIMM:
		case AXINF:
		case AXINM:
			operand(isp);
			break;
		}

		/* Source operand */
		switch(UXSRC(add)) {
		case SRC(AFP):
		case SRC(AMP):
		case SRC(AIMM):
			operand(isp);
			break;
		case SRC(AIND|AFP):
		case SRC(AIND|AMP):
			operand(isp);
			operand(isp);
			break;
		}

		/* Destination operand */
		switch(UXDST(add)) {
		case DST(AFP):
		case DST(AMP):
		case DST(AIMM):
			operand(isp);
			break;
		case DST(AIND|AFP):
		case DST(AIND|AMP):
			operand(isp);
			operand(isp);
			break;
		}

		(void)op;
	}

	/* Parse type descriptors */
	for(i = 0; i < hsize && istream < codeend; i++) {
		int id = operand(isp);
		int tsz = operand(isp);
		int tnp = operand(isp);
		if(id < 0 || tsz < 0 || tnp < 0)
			return -1;
		if(tnp > 128*1024)
			return -1;
		/* Skip type bitmap */
		if(istream + tnp > codeend)
			return -1;
		istream += tnp;
	}

	/* Parse link section */
	for(i = 0; i < lsize && istream < codeend; i++) {
		int pc = operand(isp);
		int nargs = operand(isp);
		int frame = operand(isp);
		int nret = operand(isp);
		(void)pc;
		(void)nargs;
		(void)frame;
		(void)nret;

		/* Skip function signature */
		disw(isp);
		/* Skip name (null-terminated string) */
		while(istream < codeend && *istream != '\0')
			istream++;
		if(istream < codeend)
			istream++;  /* skip null terminator */
	}

	return 0;
}

int
LLVMFuzzerTestOneInput(const uint8_t *data, size_t size)
{
	/* Make a mutable copy since the parser advances pointers */
	uchar *buf = malloc(size);
	if(buf == NULL)
		return 0;
	memcpy(buf, data, size);

	parse_dis(buf, size);

	free(buf);
	return 0;
}
