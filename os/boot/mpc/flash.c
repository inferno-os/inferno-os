#include "boot.h"

typedef struct Flashdev Flashdev;
struct Flashdev {
	uchar*	base;
	int	size;
	uchar*	exec;
	char*	config;
	int	conflen;
};

enum {
	FLASHSEG = 256*1024,
	CONFIGLIM = FLASHSEG,
	BOOTOFF = FLASHSEG,
	BOOTLEN = 3*FLASHSEG,	/* third segment might be filsys */
	/* rest of flash is free */
};

static Flashdev flash;

/*
 * configuration data is written between the bootstrap and
 * the end of region 0. the region ends with allocation descriptors
 * of the following form:
 *
 * byte order is big endian
 *
 * the last valid region found that starts with the string "#plan9.ini\n" is plan9.ini
 */
typedef struct Flalloc Flalloc;
struct Flalloc {
	ulong	check;	/* checksum of data, or ~0 */
	ulong	base;	/* base of region; ~0 if unallocated, 0 if deleted */
	uchar	len[3];
	uchar	tag;		/* see below */
	uchar	sig[4];
};

enum {
	/* tags */
	Tdead=	0,
	Tboot=	0x01,	/* space reserved for boot */
	Tconf=	0x02,	/* configuration data */
	Tnone=	0xFF,

	Noval=	~0,
};

static char flashsig[] = {0xF1, 0xA5, 0x5A, 0x1F};
static char conftag[] = "#plan9.ini\n";

static ulong
checksum(uchar* p, int n)
{
	ulong s;

	for(s=0; --n >= 0;)
		s += *p++;
	return s;
}

static int
validptr(Flalloc *ap, uchar *p)
{
	return p > (uchar*)&end && p < (uchar*)ap;
}

static int
flashcheck(Flalloc *ap, char **val, int *len)
{
	uchar *base;
	int n;

	if(ap->base == Noval || ap->base >= FLASHSEG || ap->tag == Tnone)
		return 0;
	base = flash.base+ap->base;
	if(!validptr(ap, base))
		return 0;
	n = (((ap->len[0]<<8)|ap->len[1])<<8)|ap->len[2];
	if(n == 0xFFFFFF)
		n = 0;
	if(n < 0)
		return 0;
	if(n > 0 && !validptr(ap, base+n-1))
		return 0;
	if(ap->check != Noval && checksum(base, n) != ap->check){
		print("flash: bad checksum\n");
		return 0;
	}
	*val = (char*)base;
	*len = n;
	return 1;
}

int
flashinit(void)
{
	int len;
	char *val;
	Flalloc *ap;
	void *addr;
	long mbytes;
	char type[20];

	flash.base = 0;
	flash.exec = 0;
	flash.size = 0;
	if(archflashreset(type, &addr, &mbytes) < 0){
		print("flash: flash not present or not enabled\n");	/* shouldn't happen */
		return 0;
	}
	flash.size = mbytes;
	flash.base = addr;
	flash.exec = flash.base + BOOTOFF;
	flash.config = nil;
	flash.conflen = 0;

	for(ap = (Flalloc*)(flash.base+CONFIGLIM)-1; memcmp(ap->sig, flashsig, 4) == 0; ap--){
		if(0)
			print("conf #%8.8lux: #%x #%6.6lux\n", ap, ap->tag, ap->base);
		if(ap->tag == Tconf &&
		   flashcheck(ap, &val, &len) &&
		   len >= sizeof(conftag)-1 &&
		   memcmp(val, conftag, sizeof(conftag)-1) == 0){
			flash.config = val;
			flash.conflen = len;
			if(0)
				print("flash: found config %8.8lux(%d):\n%s\n", val, len, val);
		}
	}
	if(flash.config == nil)
		print("flash: no config\n");
	else
		print("flash config %8.8lux(%d):\n%s\n", flash.config, flash.conflen, flash.config);
	if(issqueezed(flash.exec) == Q_MAGIC){
		print("flash: squeezed powerpc kernel installed\n");
		return 1<<0;
	}
	if(GLLONG(flash.exec) == Q_MAGIC){
		print("flash: unsqueezed powerpc kernel installed\n");
		return 1<<0;
	}
	flash.exec = 0;
	print("flash: no powerpc kernel in Flash\n");
	return 0;
}

char*
flashconfig(int)
{
	return flash.config;
}

int
flashbootable(int)
{
	return flash.exec != nil && (issqueezed(flash.exec) || GLLONG(flash.exec) == Q_MAGIC);
}

int
flashboot(int)
{
	ulong entry, addr;
	void (*b)(void);
	Exec *ep;
	Block in;
	long n;
	uchar *p;

	if(flash.exec == 0)
		return -1;
	p = flash.exec;
	if(GLLONG(p) == Q_MAGIC){
		/* unsqueezed: copy data and perhaps text, then jump to it */
		ep = (Exec*)p;
		entry = PADDR(GLLONG(ep->entry));
		p += sizeof(Exec);
		addr = entry;
		n = GLLONG(ep->text);
		if(addr != (ulong)p){
			memmove((void*)addr, p, n);
			print("text: %8.8lux <- %8.8lux [%ld]\n", addr, p, n);
		}
		p += n;
		if(entry >= FLASHMEM)
			addr = 3*BY2PG;	/* kernel text is in Flash, data in RAM */
		else
			addr = PGROUND(addr+n);
		n = GLLONG(ep->data);
		memmove((void*)addr, p, n);
		print("data: %8.8lux <- %8.8lux [%ld]\n", addr, p, n);
	}else{
		in.data = p;
		in.rp = in.data;
		in.lim = p+BOOTLEN;
		in.wp = in.lim;
		n = unsqueezef(&in, &entry);
		if(n < 0)
			return -1;
	}
	print("entry=0x%lux\n", entry);
	uartwait();
	scc2stop();
	/*
	 *  Go to new code. It's up to the program to get its PC relocated to
	 *  the right place.
	 */
	b = (void (*)(void))KADDR(PADDR(entry));
	(*b)();
	return -1;
}
