#define IN(x)		inb(csdev.port+(x))
#define OUT(x,v)	outb(csdev.port+(x),(v))

void
cs4231install(void)
{
	KMap *k;
	static int installed=0;

	if(installed)
		return;

	k = kmappa(AUDIO_PHYS_PAGE, PTEIO|PTENOCACHE);

	csdev.port = VA(k)+AUDIO_INDEX_OFFSET;
	dmasize(Wdma, 8);
	dmasize(Rdma, 8);

	installed=1;
}
