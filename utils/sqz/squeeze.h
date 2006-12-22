
/*
 * squeezed file format:
 *	Sqhdr
 *	original Exec header
 *	two Squeeze tables
 *	squeezed segment
 *	unsqueezed segment, if any
 */
#define	SQMAGIC	(ulong)0xFEEF0F1E

typedef struct Sqhdr Sqhdr;
struct Sqhdr {
	uchar	magic[4];	/* SQMAGIC */
	uchar	text[4];	/* squeezed length of text (excluding tables) */
	uchar	data[4];	/* squeezed length of data (excluding tables) */
	uchar	asis[4];	/* length of unsqueezed segment */
	uchar	toptxt[4];	/* value for 0 encoding in text */
	uchar	topdat[4];	/* value for 0 encoding in data */
	uchar	sum[4];	/* simple checksum of unsqueezed data */
	uchar	flags[4];
};
#define	SQHDRLEN	(8*4)

/*
 * certain power instruction types are rearranged by sqz
 * so as to move the variable part of the instruction word to the
 * low order bits.  note that the mapping is its own inverse.
 */
#define	QREMAP(X)\
	switch((X)>>26){\
	case 19: case 31: case 59: case 63:\
		(X) = (((X) & 0xFC00F801) | (((X)>>15)&0x7FE) | (((X)&0x7FE)<<15));\
	}
