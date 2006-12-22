#include	"u.h"
#include	"../port/lib.h"
#include	"mem.h"
#include	"dat.h"
#include	"fns.h"
#include	"../port/error.h"
#include	"io.h"

enum{
	Qdir,
	Qgpioset,
	Qgpioclear,
	Qgpioedge,
	Qgpioctl,
	Qgpiostatus,
};

Dirtab gpiodir[]={
	".",				{Qdir,0},			0,	0555,
	"gpioset",			{Qgpioset, 0},		0,	0664,
	"gpioclear",		{Qgpioclear, 0},		0,	0664,
	"gpioedge",		{Qgpioedge, 0},		0,	0664,
	"gpioctl",			{Qgpioctl,0},		0,	0664,
	"gpiostatus",		{Qgpiostatus,0},	0,	0444,
};

static Chan*
gpioattach(char* spec)
{
	return devattach('G', spec);
}

static Walkqid*
gpiowalk(Chan* c, Chan *nc, char **name, int nname)
{
	return devwalk(c, nc, name, nname, gpiodir, nelem(gpiodir), devgen);
}

static int	 
gpiostat(Chan* c, uchar *dp, int n)
{
	return devstat(c, dp, n, gpiodir, nelem(gpiodir), devgen);
}

static Chan*
gpioopen(Chan* c, int omode)
{
	return devopen(c, omode, gpiodir, nelem(gpiodir), devgen);
}

static void	 
gpioclose(Chan*)
{
}

static long	 
gpioread(Chan* c, void *buf, long n, vlong offset)
{
	char str[128];
	GpioReg *g;
	
	if(c->qid.type & QTDIR)
		return devdirread(c, buf, n, gpiodir, nelem(gpiodir), devgen);

	g = GPIOREG;
	switch((ulong)c->qid.path){
	case Qgpioset:
	case Qgpioclear:
		sprint(str, "%8.8lux", g->gplr);
		break;
	case Qgpioedge:
		sprint(str, "%8.8lux", g->gedr);
		break;
	case Qgpioctl:
		/* return 0; */
	case Qgpiostatus:
		snprint(str, sizeof(str), "GPDR:%8.8lux\nGRER:%8.8lux\nGFER:%8.8lux\nGAFR:%8.8lux\nGPLR:%8.8lux\n", g->gpdr, g->grer, g->gfer, g->gafr, g->gplr);
		break;
	default:
		error(Ebadarg);
		return 0;
	}
	return readstr(offset, buf, n, str);
}

static long	 
gpiowrite(Chan *c, void *a, long n, vlong)
{
	char buf[128], *field[3];
	int pin, set;
	ulong *r;
	GpioReg *g;

	if(n >= sizeof(buf))
		n = sizeof(buf)-1;
	memmove(buf, a, n);
	buf[n] = 0;	
	g = GPIOREG;
	switch((ulong)c->qid.path){
	case Qgpioset:
		g->gpsr = strtol(buf, 0, 16);
		break;
	case Qgpioclear:
		g->gpcr = strtol(buf, 0, 16);
		break;
	case Qgpioedge:
		g->gedr = strtol(buf, 0, 16);
		break;
	case Qgpioctl:
		if(getfields(buf, field, 3, 1, " \n\t") == 3) {
			pin = strtol(field[1], 0, 0);
			if(pin < 0 || pin >= 32)
				error(Ebadarg);
			set = strtol(field[2], 0, 0);
			switch(*field[0]) {
			case 'd':
				r = &g->gpdr;
				break;
			case 'r':
				r = &g->grer;
				break;
			case 'f':
				r = &g->gfer;
				break;
			case 'a':
				r = &g->gafr;
				break;
			default:
				error(Ebadarg);
				return 0;
			}
			if(set)
				*r |= 1 << pin;
			else
				*r &= ~(1 << pin);
		} else
			error(Ebadarg);
		break;
	default:
		error(Ebadusefd);
		return 0;
	}
	return n;
}

Dev gpiodevtab = {
	'G',
	"gpio",

	devreset,
	devinit,
	devshutdown,
	gpioattach,
	gpiowalk,
	gpiostat,
	gpioopen,
	devcreate,
	gpioclose,
	gpioread,
	devbread,
	gpiowrite,
	devbwrite,
	devremove,
	devwstat,
};
