typedef	unsigned short	ushort;
typedef	unsigned char	uchar;

enum {
	IsaIOBase		= 0xf0000000,
	IsaMemBase	= 0xe0000000,

	IOBase		= 0x300,
	MemBase		= 0xc0000,

	TxFrame		= 0x0a00,
};

#define	regw(reg, val)		*((ushort *)IsaMemBase + MemBase + (reg)) = (val)

void
main(void)
{
	regw(TxFrame, 0x1234);
}
