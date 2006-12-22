#include	"u.h"
#include	"../port/lib.h"
#include	"mem.h"
#include	"dat.h"
#include	"fns.h"
#include	"io.h"
#include	"../port/error.h"

/*
 * TODO
 * - shift key should modify right button with non-serial mice
 * + intellimouse implementation
 * - acceleration for all mouse types
 * + spurious interrupt 7 after probing for ps2 mouse for the first time...?
 * - test with ms busmouse
 * - test with logitech serial mouse
 */

/*
 *  mouse types
 */
enum
{
	Mouseother,
	Mouseserial,
	MousePS2,
	Mousebus,
	Mouseintelli,
	Mousemsbus,
};

static int mousetype;
static int mouseswap;
static int mouseport;		/* port for serial mice, irq for bus mice */
static int mousesubtype;
static int accelerated;
static QLock mouselock;

static int msbusmousedetect(void);
static int busmousedetect(void);
static void mousectl(char *buf);
static void mouseprobe(char *buf, int len);
static void mousestatus(char *buf, int len);

enum{
	Qdir,
	Qmousectl,
	Qmouseprobe,
};

static
Dirtab mousetab[]={
	"mousectl",		{Qmousectl, 0},	0,	0600,
	"mouseprobe",	{Qmouseprobe, 0}, 0, 0400,
};

static Chan*
mouseattach(char* spec)
{
	return devattach('m', spec);
}

static int
mousewalk(Chan* c, char* name)
{
	return devwalk(c, name, mousetab, nelem(mousetab), devgen);
}

static void
mousestat(Chan* c, char* db)
{
	devstat(c, db, mousetab, nelem(mousetab), devgen);
}

static Chan*
mouseopen(Chan* c, int omode)
{
	return devopen(c, omode, mousetab, nelem(mousetab), devgen);
}

static void
mouseclose(Chan* c)
{
	USED(c);
}

static long
mouseread(Chan* c, void* a, long n, vlong offset)
{
	char buf[64];
	USED(offset);

	switch(c->qid.path & ~CHDIR){
	case Qdir:
		return devdirread(c, a, n, mousetab, nelem(mousetab), devgen);
	case Qmousectl:
		qlock(&mouselock);
		mousestatus(buf, sizeof(buf));
		qunlock(&mouselock);
		n = readstr(offset, a, n, buf);
		break;
	case Qmouseprobe:
		if (mousetype)
			error(Emouseset);
		mouseprobe(buf, sizeof(buf));
		n = readstr(offset, a, n, buf);
		break;
	default:
		n=0;
		break;
	}
	return n;
}

static long
mousewrite(Chan* c, void *a, long n, vlong)
{
	char buf[64];
	if ((c->qid.path & ~CHDIR) != Qmousectl)
		error(Ebadusefd);
	if (n >= sizeof(buf))
		n = sizeof(buf) - 1;
	strncpy(buf, a, n);
	buf[n] = 0;

	qlock(&mouselock);
	if (waserror()) {
		qunlock(&mouselock);
		nexterror();
	}
	mousectl(buf);
	poperror();
	qunlock(&mouselock);
	return n;
}

static void
track(int b, int dx, int dy)
{
	static uchar map[8] = {0,4,2,6,1,5,3,7};
	if (mouseswap)
		b = map[b&7];
	mousetrack(b, dx, dy);
}

static void
setintellimouse(void)
{
	i8042auxcmd(0xF3);	/* set sample */
	i8042auxcmd(0xC8);
	i8042auxcmd(0xF3);	/* set sample */
	i8042auxcmd(0x64);
	i8042auxcmd(0xF3);	/* set sample */
	i8042auxcmd(0x50);
}

/*
 * check for an Intellimouse.
 * this is only used when we know there's an 8042 aux device
 */
static int
intellimousedetect(void)
{
	int id;
	setintellimouse();
	/* check whether the mouse is now in extended mode */
	id = i8042auxcmdval(0xf2);		/* identify device */
	if (id != 3) {
		/*
		 * set back to standard sample rate (100 per sec)
		 */
		i8042auxcmd(0xf3);
		i8042auxcmd(0x64);
		return 0;
	}
	return 1;
}

static void
mouseprobe(char *buf, int len)
{
	USED(len);
	/*
	 * bus mice are easiest, so probe them first
	 */
	if (busmousedetect())
		sprint(buf, "bus\n");
	else if (msbusmousedetect())
		sprint(buf, "msbus\n");
	else if (i8042auxdetect()) {
		if (intellimousedetect())
			sprint(buf, "ps2intellimouse\n");
		else
			sprint(buf, "ps2\n");
	}
	else
		*buf = 0;
}


static void
mousestatus(char *buf, int len)
{
	char *s;
	USED(len);
	s = buf;
	switch (mousetype) {
	case Mouseserial:
		if (mousesubtype)
			s += sprint(s, "serial %d %c\n", mouseport, mousesubtype);
		else
			s += sprint(s, "serial %d\n", mouseport);
		break;
	case MousePS2:
		s += sprint(s, "ps2\n");
		break;
	case Mousebus:
		s += sprint(s, "bus %d\n", mouseport);
		break;
	case Mouseintelli:
		s += sprint(s, "intelli\n");
		break;
	case Mousemsbus:
		s += sprint(s, "msbus %d\n", mouseport);
		break;
	default:
	case Mouseother:
		s += sprint(s, "unknown\n");
		break;
	}
	if (accelerated)
		s += sprint(s, "accelerated\n");
	if (mouseswap)
		sprint(s, "swap\n");
}

/*
 *  Logitech 5 byte packed binary mouse format, 8 bit bytes
 *
 *  shift & right button is the same as middle button (for 2 button mice)
 */
static int
logitechmouseputc(Queue *q, int c)
{
	static short msg[5];
	static int nb;
	static uchar b[] = {0, 4, 2, 6, 1, 5, 3, 7, 0, 2, 2, 6, 1, 5, 3, 7};
	int dx, dy, newbuttons;
	int mouseshifted;

	USED(q);
	if((c&0xF0) == 0x80)
		nb=0;
	msg[nb] = c;
	if(c & 0x80)
		msg[nb] |= ~0xFF;	/* sign extend */
	if(++nb == 5){
		mouseshifted = 0;	/* XXX should be from keyboard shift key */
		newbuttons = b[((msg[0]&7)^7) | (mouseshifted ? 8 : 0)];
		dx = msg[1]+msg[3];
		dy = -(msg[2]+msg[4]);
		track(newbuttons, dx, dy);
		nb = 0;
	}
	return 0;
}

/*
 *  microsoft 3 button, 7 bit bytes
 *
 *	byte 0 -	1  L  R Y7 Y6 X7 X6
 *	byte 1 -	0 X5 X4 X3 X2 X1 X0
 *	byte 2 -	0 Y5 Y4 Y3 Y2 Y1 Y0
 *	byte 3 -	0  M  x  x  x  x  x	(optional)
 *
 *  shift & right button is the same as middle button (for 2 button mice)
 */
static int
m3mouseputc(Queue*, int c)
{
	static uchar msg[3];
	static int nb;
	static int middle;
	static uchar b[] = { 0, 4, 1, 5, 0, 2, 1, 5 };
	short x;
	int dx, dy, buttons;

	/* 
	 *  check bit 6 for consistency
	 */
	if(nb==0){
		if((c&0x40) == 0){
			/* an extra byte gets sent for the middle button */
			if(c & 0x1c)
				return 0;
			middle = (c&0x20) ? 2 : 0;
			buttons = (mouse.b & ~2) | middle;
			track(buttons, 0, 0);
			return 0;
		}
	}
	msg[nb] = c&0x3f;
	if(++nb == 3){
		nb = 0;
		buttons = middle | b[(msg[0]>>4)&3];
		x = (msg[0]&0x3)<<14;
		dx = (x>>8) | msg[1];
		x = (msg[0]&0xc)<<12;
		dy = (x>>8) | msg[2];
		track(buttons, dx, dy);
	}
	return 0;
}

static void
serialmouse(int port, char *type, int setspeed)
{
	int (*putc)(Queue *, int) = 0;
	char pn[KNAMELEN];

	if(mousetype)
		error(Emouseset);

	if(port >= 2 || port < 0)
		error(Ebadarg);

	if (type == 0)
		putc = logitechmouseputc;
	else if (*type == 'M')
		putc = m3mouseputc;
	else
		error(Ebadarg);
	snprint(pn, sizeof(pn), "%d", port);
	i8250mouse(pn, putc, setspeed);
	mousetype = Mouseserial;
	mouseport = port;
	mousesubtype = (type && *type == 'M') ? 'M' : 0;
}

/*
 *  ps/2 mouse message is three bytes
 *
 *	byte 0 -	0 0 SDY SDX 1 M R L
 *	byte 1 -	DX
 *	byte 2 -	DY
 *
 *  shift & left button is the same as middle button
 */
static void
ps2mouseputc(int c, int shift)
{
	static short msg[3];
	static int nb;
	static uchar b[] = {0, 1, 4, 5, 2, 3, 6, 7, 0, 1, 2, 5, 2, 3, 6, 7 };
	int buttons, dx, dy;

	/* 
	 *  check byte 0 for consistency
	 */
	if(nb==0 && (c&0xc8)!=0x08)
		return;

	msg[nb] = c;
	if(++nb == 3){
		nb = 0;
		if(msg[0] & 0x10)
			msg[1] |= 0xFF00;
		if(msg[0] & 0x20)
			msg[2] |= 0xFF00;

		buttons = b[(msg[0]&7) | (shift ? 8 : 0)];
		dx = msg[1];
		dy = -msg[2];
		track(buttons, dx, dy);
	}
	return;
}

/*
 *  set up a ps2 mouse
 */
static void
ps2mouse(void)
{
	if(mousetype)
		error(Emouseset);

	i8042auxenable(ps2mouseputc);
	/* make mouse streaming, enabled */
	i8042auxcmd(0xEA);
	i8042auxcmd(0xF4);

	mousetype = MousePS2;
}

/* logitech bus mouse ports and commands */
enum {
	/* ports */
	BMdatap	= 0x23c,
	BMsigp	= 0x23d,
	BMctlp	= 0x23e,
	BMintrp	= 0x23e,
	BMconfigp	= 0x23f,

	/* commands */
	BMintron = 0x0,
	BMintroff = 0x10,
	BMrxlo	= 0x80,
	BMrxhi	= 0xa0,
	BMrylo	= 0xc0,
	BMryhi	= 0xe0,

	BMconfig	= 0x91,
	BMdefault	= 0x90,

	BMsigval	= 0xa5
};

static void
busmouseintr(Ureg *, void *)
{
	char dx, dy;
	uchar b;
	static uchar oldb;
	static Lock intrlock;
	ilock(&intrlock);
	outb(BMintrp, BMintroff);
	outb(BMctlp, BMrxlo);
	dx = inb(BMdatap) & 0xf;
	outb(BMctlp, BMrxhi);
	dx |= (inb(BMdatap) & 0xf) << 4;
	outb(BMctlp, BMrylo);
	dy = inb(BMdatap) & 0xf;
	outb(BMctlp, BMryhi);
	b = inb(BMdatap);
	dy |= (b & 0xf) << 4;
	b = ~(b >> 5) & 7;
	if (dx || dy || b != oldb) {
		oldb = b;
		track((b>>2)|(b&0x02)|((b&0x01)<<2), dx, dy);
	}
	iunlock(&intrlock);
	outb(BMintrp, BMintron);
}

static int
busmousedetect(void)
{
	outb(BMconfigp, BMconfig);
	outb(BMsigp, BMsigval);
	delay(2);
	if (inb(BMsigp) != BMsigval)
		return 0;
	outb(BMconfigp, BMdefault);
	return 1;
}

/*
 * set up a logitech bus mouse
 */
static void
busmouse(int irq)
{
	if (mousetype)
		error(Emouseset);
	if (!busmousedetect())
		error(Enodev);

	intrenable(irq >= 0 ? irq+VectorPIC : VectorBUSMOUSE, busmouseintr, 0, BUSUNKNOWN);
	outb(BMintrp, BMintron);
	mousetype = Mousebus;
	mouseport = irq >= 0 ? irq : VectorBUSMOUSE-VectorPIC;
}

/* microsoft bus mouse ports and commands */
enum {
	MBMdatap=	0x23d,
	MBMsigp=	0x23e,
	MBMctlp=	0x23c,
	MBMconfigp=	0x23f,

	MBMintron=	0x11,
	MBMintroff=	0x10,
	MBMrbuttons= 0x00,
	MBMrx=		0x01,
	MBMry=		0x02,
	MBMstart=	0x80,
	MBMcmd=		0x07,
};

static void
msbusmouseintr(Ureg *, void *)
{
	char dx, dy;
	uchar b;
	static uchar oldb;
	static Lock intrlock;
	ilock(&intrlock);
	outb(MBMctlp, MBMcmd);
	outb(MBMdatap, inb(MBMdatap)|0x20);

	outb(MBMctlp, MBMrx);
	dx = inb(MBMdatap);

	outb(MBMctlp, MBMry);
	dy = inb(MBMdatap);

	outb(MBMctlp, MBMrbuttons);
	b = inb(MBMdatap) & 0x7;

	outb(MBMctlp, MBMcmd);
	outb(MBMdatap, inb(MBMdatap)&0xdf);

	if (dx != 0 || dy != 0 || b != oldb) {
		oldb = b;
		/* XXX this is almost certainly wrong */
		track((b>>2)|(b&0x02)|((b&0x01)<<2), dx, dy);
	}
	iunlock(&intrlock);
}

static int
msbusmousedetect(void)
{
	if (inb(MBMsigp) == 0xde) {
		int v, i;
		delay(1);
		v = inb(MBMsigp);
		delay(1);
		for (i = 0; i < 4; i++) {
			if (inb(MBMsigp) != 0xde)
				break;
			delay(1);
			if (inb(MBMsigp) != v)
				break;
			delay(1);
		}
		if (i == 4) {
			outb(MBMctlp, MBMcmd);
			return 1;
		}
	}
	return 0;
}

static void
msbusmouse(int irq)
{
	if (mousetype)
		error(Emouseset);
	if (!msbusmousedetect())
		error(Enodev);
	mousetype = Mousemsbus;
	mouseport = irq >= 0 ? irq : VectorBUSMOUSE-VectorPIC;
	intrenable(irq >= 0 ? irq+VectorPIC : VectorBUSMOUSE, msbusmouseintr, 0, BUSUNKNOWN);
	outb(MBMdatap, MBMintron);
}

static void
mousectl(char *buf)
{
	int nf, x;
	char *field[10];
	nf = getfields(buf, field, 10, 1, " \t\n");
	if (nf < 1)
		return;
	if(strncmp(field[0], "serial", 6) == 0){
		switch(nf){
		/* the difference between these two cases is intriguing - wrtp */
		case 1:
			serialmouse(atoi(field[0]+6), 0, 1);
			break;
		case 2:
			serialmouse(atoi(field[1]), 0, 0);
			break;
		case 3:
		default:
			serialmouse(atoi(field[1]), field[2], 0);
			break;
		}
	} else if(strcmp(field[0], "ps2") == 0){
		ps2mouse();
	} else if (strcmp(field[0], "ps2intellimouse") == 0) {
		ps2mouse();
		setintellimouse();
	} else if (strncmp(field[0], "bus", 3) == 0 || strncmp(field[0], "msbus", 5) == 0) {
		int irq, isms;

		isms = (field[0][0] == 'm');
		if (nf == 1)
			irq = atoi(field[0] + (isms ? 5 : 3));
		else
			irq = atoi(field[1]);
		if (irq < 1)
			irq = -1;
		if (isms)
			msbusmouse(irq);
		else
			busmouse(irq);
	} else if(strcmp(field[0], "accelerated") == 0){
		switch(mousetype){
		case MousePS2:
			x = splhi();
			i8042auxcmd(0xE7);
			splx(x);
			accelerated = 1;
			break;
		}
	} else if(strcmp(field[0], "linear") == 0){
		switch(mousetype){
		case MousePS2:
			x = splhi();
			i8042auxcmd(0xE6);
			splx(x);
			accelerated = 0;
			break;
		}
	} else if(strcmp(field[0], "res") == 0){
		int n,m;
		switch(nf){
		default:
			n = 0x02;
			m = 0x23;
			break;
		case 2:
			n = atoi(field[1])&0x3;
			m = 0x7;
			break;
		case 3:
			n = atoi(field[1])&0x3;
			m = atoi(field[2])&0x7;
			break;
		}
			
		switch(mousetype){
		case MousePS2:
			x = splhi();
			i8042auxcmd(0xE8);
			i8042auxcmd(n);
			i8042auxcmd(0x5A);
			i8042auxcmd(0x30|m);
			i8042auxcmd(0x5A);
			i8042auxcmd(0x20|(m>>1));
			splx(x);
			break;
		}
	} else if(strcmp(field[0], "swap") == 0)
		mouseswap ^= 1;
}

Dev mousedevtab = {					/* defaults in dev.c */
	'm',
	"mouse",

	devreset,					/* devreset */
	devinit,					/* devinit */
	mouseattach,
	devdetach,
	devclone,					/* devclone */
	mousewalk,
	mousestat,
	mouseopen,
	devcreate,					/* devcreate */
	mouseclose,
	mouseread,
	devbread,					/* devbread */
	mousewrite,
	devbwrite,					/* devbwrite */
	devremove,					/* devremove */
	devwstat,					/* devwstat */
};

