/*
 *  Javastation specific code for the ns16552 (really the superio chip,
 *  but it has a serial port that looks like the ns16552).
 */
enum
{
	UartFREQ= 1843200,
	TTYABase = 0x2F8
};

#define uartwrreg(u,r,v)	outb((u)->port + r, (u)->sticky[r] | (v))
#define uartrdreg(u,r)		inb((u)->port + r)

void	ns16552setup(ulong, ulong, char*);

static void
uartpower(int, int)
{
}

/*
 *  handle an interrupt to a single uart
 */
static void
ns16552intrx(Ureg *ur, void *arg)
{
	USED(ur);

	ns16552intr((ulong)arg);
}

/*
 *  install the uarts (called by reset)
 */
void
ns16552install(void)
{
	static int already;
	void uartclock(void);

	if(already)
		return;
	already = 1;

	/* first two ports are always there and always the normal frequency */
	ns16552setup(superiova()+TTYABase, UartFREQ, "eia0");
	ns16552special(0, 38400, &kbdq, &printq, kbdputc);
	addclock0link(uartclock, 22);
}

/*
 * If the UART's receiver can be connected to a DMA channel,
 * this function does what is necessary to create the
 * connection and returns the DMA channel number.
 * If the UART's receiver cannot be connected to a DMA channel,
 * a -1 is returned.
 */
char
ns16552dmarcv(int dev)
{
 
	USED(dev);
        return -1;
}

long
dmasetup(int,void*,long,int)
{
	return 0;
}

void
dmaend(int)
{
}

int
dmacount(int)
{
	return 0;
}
