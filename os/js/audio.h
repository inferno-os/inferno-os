enum
{
	Bufsize		= 16*1024,	/* 92 ms each */
	Nbuf		= 16,		/* 1.5 seconds total */
	Rdma		= 666,		/* XXX - Tad: fixme */
	Wdma		= 666,		/* XXX - Tad: fixme */
};

#define UNCACHED(type, v)	(type*)((ulong)(v))
