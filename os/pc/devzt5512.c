/*
 *  Namespace Interface for Ziatech 5512 System Registers
 */
#include	"u.h"
#include	"../port/lib.h"
#include	"mem.h"
#include	"dat.h"
#include	"fns.h"
#include	"../port/error.h"


enum{
	Qdir,
	Qsysid,
	Qwatchdog,
	Qledctl,
	Qpower,
	Qswitch,
	Qstat,
};

static
Dirtab zttab[]={
	".",			{Qdir,0,QTDIR},		0,	0555,
	"id",			{Qsysid, 0},		0,	0444,
	"watchdog",	{Qwatchdog, 0}, 	0,	0600,
	"ledctl",		{Qledctl, 0},		0,	0666,
	"powerstat",	{Qpower, 0},		0,	0444,
	"switch",		{Qswitch, 0},		0,	0444,
	"stat",		{Qstat, 0},			0,	0444,
};

extern int watchdog;
void
watchdog_strobe(void)
{
	uchar sysreg;

	sysreg = inb(0x78);
	sysreg &= (~1);
	outb(0x78, sysreg);	/* disable/strobe watchdog */
	sysreg |= 1;
	outb(0x78, sysreg);	/* enable watchdog */
}

static void
ztreset(void)						/* default in dev.c */
{
	uchar sysreg;

	if(watchdog)
		addclock0link(watchdog_strobe);
	/* clear status LEDs */
	sysreg = inb(0xe2);
	sysreg &= ~3;		/* clear usr1 */
	sysreg &= ~(3 << 2); /* clear usr2 */
	outb(0xe2, sysreg);
}

static Chan*
ztattach(char* spec)
{
	return devattach('Z', spec);
}

static int
ztwalk(Chan* c, char* name)
{
	return devwalk(c, name, zttab, nelem(zttab), devgen);
}

static void
ztstat(Chan* c, char* db)
{
	devstat(c, db, zttab, nelem(zttab), devgen);
}

static Chan*
ztopen(Chan* c, int omode)
{
	return devopen(c, omode, zttab, nelem(zttab), devgen);
}

static void
ztclose(Chan* c)
{
	USED(c);
}

static long
ztread(Chan* c, void* a, long n, vlong offset)
{
	uchar sysreg;
	char buf[256];

	USED(offset);

	switch(c->qid.path & ~CHDIR) {
	case Qdir:
		return devdirread(c, a, n, zttab, nelem(zttab), devgen);
	case Qsysid: {
		ulong rev;
		sysreg = inb(0xe3);
		rev = (ulong) (sysreg & 0x7f);
		sysreg = inb(0xe2);
		sprint(buf, "Board Rev: %lud\nSerial #: %lud\n", rev, (ulong)(sysreg >> 4));
		return readstr(offset, a, n, buf);
		};
	case Qwatchdog:
		sysreg = inb(0x78);
		if((sysreg & 1) == 1) {
			n = readstr(offset, a, n, "enabled");
		} else {
			n = readstr(offset, a, n, "disabled");
		}
		return n;
	case Qledctl:
		{
		char usr1[6], usr2[6];
		sysreg = inb(0xe2);
		switch( sysreg & 3 ) {
			case 0:
			case 3:
				sprint(usr1, "off");
				break;
			case 1:
				sprint(usr1, "red");
				break;
			case 2:
				sprint(usr1, "green");
		};
		switch( (sysreg >> 2) & 3) {
			case 0:
			case 3:
				sprint(usr2, "off");
				break;
			case 1:
				sprint(usr2, "red");
				break;
			case 2:
				sprint(usr2, "green");
		};
		sprint(buf, "usr1: %s\nusr2: %s\n",usr1, usr2);
		return readstr(offset, a, n, buf);
		};
	case Qpower:
		sysreg = inb(0xe4);
		sprint(buf, "DEG#: %d\nFAL#: %d\n", (sysreg & 2), (sysreg & 1));
		return readstr(offset, a, n, buf);
	case Qswitch:
		sysreg = inb(0xe4);
		sprint(buf, "%d %d %d %d", (sysreg & (1<<6)), (sysreg & (1<<5)), (sysreg & (1<<4)), (sysreg & (1<<3)));
		return readstr(offset, a, n, buf);
	case Qstat: {
		char bus[10],cpu[20], mode[20], boot[20];

		sysreg = inb(0xe5);
		switch (sysreg & 0x7) {
			case 1: 
				sprint(bus, "66 MHz");
				break;
			case 2:
				sprint(bus, "60 MHz");
				break;
			case 3:
				sprint(bus, "50 MHz");
				break;
			default:
				sprint(bus, "unknown");
		};
		switch ((sysreg>>3)&0x7) {
			case 0:
				sprint(cpu, "75, 90, 100 MHz");
				break;
			case 1:
				sprint(cpu, "120, 133 MHz");
				break;
			case 2:
				sprint(cpu, "180, 200 MHz");
				break;
			case 3:
				sprint(cpu, "150, 166 MHz");
			default:
				sprint(cpu, "unknown");
		};
		if(sysreg & (1<<6)) 
			sprint(mode, "Port 80 test mode");
		else
			sprint(mode, "Normal decode");
		if(sysreg & (1<<7))
			sprint(boot,"EEPROM");
		else
			sprint(boot,"Flash");
		sprint(buf,"Bus Frequency: %s\nPentium: %s\nTest Mode Status: %s\nBIOS Boot ROM: %s\n",
				bus, cpu, mode, boot);
		return readstr(offset, a, n, buf);
		};
	default:
		n=0;
		break;
	}
	return n;
}



static long
ztwrite(Chan* c, void *vp, long n, vlong offset)
{
	uchar sysreg;
	char buf[256];
	char *a;
	int nf;
	char *fields[3];

	a = vp;
	if(n >= sizeof(buf))
		n = sizeof(buf)-1;
	strncpy(buf, a, n);
	buf[n] = 0;	

	USED(a, offset);

	switch(c->qid.path & ~CHDIR){
	case Qwatchdog:
		sysreg = inb(0x78);

		if(strncmp(buf, "enable", 6) == 0) {
			if((sysreg & 1) != 1)
		 		addclock0link(watchdog_strobe);
			break;
		}
		n = 0;
		error(Ebadarg);
	case Qledctl:
		nf = getfields(buf, fields, 3, 1, " \t\n");
		if(nf < 2) {
			error(Ebadarg);
			n = 0;
			break;
		}
		sysreg = inb(0xe2);
		USED(sysreg);
		if(strncmp(fields[0],"usr1", 4)==0) {
			sysreg &= ~3;
			if(strncmp(fields[1], "off", 3)==0) {
				outb(0xe2, sysreg);
				break;
			} 
			if(strncmp(fields[1], "red", 3)==0) {
				sysreg |= 1;
				outb(0xe2, sysreg);
				break;
			} 
			if(strncmp(fields[1], "green", 5)==0) {
				sysreg |= 2;
				outb(0xe2, sysreg);
				break;
			} 		
		}
		if(strncmp(fields[0],"usr2", 4)==0) {
			sysreg &= ~(3 << 2);
			if(strncmp(fields[1], "off", 3)==0) {
				outb(0xe2, sysreg);
				break;
			} 
			if(strncmp(fields[1], "red", 3)==0) {
				sysreg |= (1 << 2);
				outb(0xe2, sysreg);
				break;
			} 
			if(strncmp(fields[1], "green", 5)==0) {
				sysreg |= (2 << 2);
				outb(0xe2, sysreg);
				break;
			} 		
		}
		n = 0;
		error(Ebadarg);
	default:
		error(Ebadusefd);
	}
	return n;
}



Dev zt5512devtab = {				/* defaults in dev.c */
	'Z',
	"Ziatech5512",

	ztreset,						/* devreset */
	devinit,						/* devinit */
	ztattach,
	devdetach,
	devclone,						/* devclone */
	ztwalk,
	ztstat,
	ztopen,
	devcreate,					/* devcreate */
	ztclose,
	ztread,
	devbread,						/* devbread */
	ztwrite,
	devbwrite,					/* devbwrite */
	devremove,					/* devremove */
	devwstat,						/* devwstat */
};
