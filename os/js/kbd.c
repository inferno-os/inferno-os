#include "u.h"
#include "../port/lib.h"
#include "mem.h"
#include "dat.h"
#include "fns.h"
#include "io.h"
#include "../port/error.h"

enum
{
	Data=		0x60,	/* data port */

	Status=		0x64,	/* status port */
	 Inready=	0x01,	/*  input character ready */
	 Outbusy=	0x02,	/*  output busy */
	 Sysflag=	0x04,	/*  system flag */
	 Cmddata=	0x08,	/*  cmd==0, data==1 */
	 Inhibit=	0x10,	/*  keyboard/mouse inhibited */
	 Minready=	0x20,	/*  mouse character ready */
	 Rtimeout=	0x40,	/*  general timeout */
	 Parity=	0x80,

	Cmd=		0x64,	/* command port (write only) */

	CTdata=		0x0,	/* chips & Technologies ps2 data port */
	CTstatus=	0x1,	/* chips & Technologies ps2 status port */
	 Enable=	1<<7,
	 Clear=		1<<6,
	 Error=		1<<5,
	 Intenable=	1<<4,
	 Reset=		1<<3,
	 Tready=	1<<2,
	 Rready=	1<<1,
	 Idle=		1<<0,

	Spec=	0x80,

	PF=	Spec|0x20,	/* num pad function key */
	View=	Spec|0x00,	/* view (shift window up) */
	KF=	Spec|0x40,	/* function key */
	Shift=	Spec|0x60,
	Break=	Spec|0x61,
	Ctrl=	Spec|0x62,
	Latin=	Spec|0x63,
	Caps=	Spec|0x64,
	Num=	Spec|0x65,
	Middle=	Spec|0x66,
	No=	0x00,		/* peter */

	Home=	KF|13,
	Up=	KF|14,
	Pgup=	KF|15,
	Print=	KF|16,
	Left=	View,
	Right=	View,
	End=	'\r',
	Down=	View,
	Pgdown=	View,
	Ins=	KF|20,
	Del=	0x7F,

	Rbutton=4,
	Mbutton=2,
	Lbutton=1,
};

uchar
kbtab[] = {
[0x00]	No,	0x1b,	'1',	'2',	'3',	'4',	'5',	'6',
[0x08]	'7',	'8',	'9',	'0',	'-',	'=',	'\b',	'\t',
[0x10]	'q',	'w',	'e',	'r',	't',	'y',	'u',	'i',
[0x18]	'o',	'p',	'[',	']',	'\n',	Ctrl,	'a',	's',
[0x20]	'd',	'f',	'g',	'h',	'j',	'k',	'l',	';',
[0x28]	'\'',	'`',	Shift,	'\\',	'z',	'x',	'c',	'v',
[0x30]	'b',	'n',	'm',	',',	'.',	'/',	Shift,	'*',
[0x38]	Latin,	' ',	Ctrl,	KF|1,	KF|2,	KF|3,	KF|4,	KF|5,
[0x40]	KF|6,	KF|7,	KF|8,	KF|9,	KF|10,	Num,	KF|12,	'7',
[0x48]	'8',	'9',	'-',	'4',	'5',	'6',	'+',	'1',
[0x50]	'2',	'3',	'0',	'.',	No,	No,	No,	KF|11,
[0x58]	KF|12,	No,	No,	No,	No,	No,	No,	No,
};

uchar
kbtabshift[] = {
[0x00]	No,	0x1b,	'!',	'@',	'#',	'$',	'%',	'^',
[0x08]	'&',	'*',	'(',	')',	'_',	'+',	'\b',	'\t',
[0x10]	'Q',	'W',	'E',	'R',	'T',	'Y',	'U',	'I',
[0x18]	'O',	'P',	'{',	'}',	'\n',	Ctrl,	'A',	'S',
[0x20]	'D',	'F',	'G',	'H',	'J',	'K',	'L',	':',
[0x28]	'"',	'~',	Shift,	'|',	'Z',	'X',	'C',	'V',
[0x30]	'B',	'N',	'M',	'<',	'>',	'?',	Shift,	'*',
[0x38]	Latin,	' ',	Ctrl,	KF|1,	KF|2,	KF|3,	KF|4,	KF|5,
[0x40]	KF|6,	KF|7,	KF|8,	KF|9,	KF|10,	Num,	KF|12,	'7',
[0x48]	'8',	'9',	'-',	'4',	'5',	'6',	'+',	'1',
[0x50]	'2',	'3',	'0',	'.',	No,	No,	No,	KF|11,
[0x58]	KF|12,	No,	No,	No,	No,	No,	No,	No,
};

uchar
kbtabesc1[] = {
[0x00]	No,	No,	No,	No,	No,	No,	No,	No,
[0x08]	No,	No,	No,	No,	No,	No,	No,	No,
[0x10]	No,	No,	No,	No,	No,	No,	No,	No,
[0x18]	No,	No,	No,	No,	'\n',	Ctrl,	No,	No,
[0x20]	No,	No,	No,	No,	No,	No,	No,	No,
[0x28]	No,	No,	Shift,	No,	No,	No,	No,	No,
[0x30]	No,	No,	No,	No,	No,	'/',	No,	Print,
[0x38]	Latin,	No,	No,	No,	No,	No,	No,	No,
[0x40]	No,	No,	No,	No,	No,	No,	Break,	Home,
[0x48]	Up,	Pgup,	No,	Left,	No,	Right,	No,	End,
[0x50]	Down,	Pgdown,	Ins,	Del,	No,	No,	No,	No,
[0x58]	No,	No,	No,	No,	No,	No,	No,	No,
};

static	int	keybuttons;
static	uchar	ccc;
static	int	shift;

enum
{
	/* controller command byte */
	Cscs1=		(1<<6),		/* scan code set 1 */
	Cmousedis=	(1<<5),		/* mouse disable */
	Ckbddis=	(1<<4),		/* kbd disable */
	Csf=		(1<<2),		/* system flag */
	Cmouseint=	(1<<1),		/* mouse interrupt enable */
	Ckbdint=	(1<<0),		/* kbd interrupt enable */
};

/*
 *  wait for output no longer busy
 */
static int
outready(void)
{
	int tries;

	for(tries = 0; (superio_readctl() & Outbusy); tries++){
		if(tries > 500)
			return -1;
		microdelay(2);
	}
	return 0;
}

/*
 *  wait for input
 */
static int
inready(void)
{
	int tries;

	for(tries = 0; !(superio_readctl() & Inready); tries++){
		if(tries > 500)
			return -1;
		microdelay(2);
	}
	return 0;
}

/*
 *  send a command to the mouse
 */
static int
mousecmd(int cmd)
{
	unsigned int c;
	int tries;

	c = 0;
	tries = 0;
	do{
		if(tries++ > 2)
			break;
		if(outready() < 0)
			break;
		superio_writectl(0xD4);
		if(outready() < 0)
			break;
		superio_writedata(cmd);
		if(outready() < 0)
			break;
		if(inready() < 0)
			break;
		c = superio_readdata();
	} while(c == 0xFE || c == 0);

	if(c != 0xFA){
		print("mouse returns %2.2ux to the %2.2ux command\n", c, cmd);
		return -1;
	}
	return 0;
}

/*
 *  ask 8042 to enable the use of address bit 20
 */
void
i8042a20(void)
{
	outready();
	superio_writectl(0xD1);
	outready();
	superio_writedata(0xDF);
	outready();
}

/*
 *  ask 8042 to reset the machine
 */
void
i8042reset(void)
{
	ushort *s = (ushort*)(KZERO|0x472);
	int i, x;

	*s = 0x1234;		/* BIOS warm-boot flag */

	/*
	 *  newer reset the machine command
	 */
	outready();
	superio_writectl(0xFE);
	outready();

	/*
	 *  Pulse it by hand (old somewhat reliable)
	 */
	x = 0xDF;
	for(i = 0; i < 5; i++){
		x ^= 1;
		outready();
		superio_writectl(0xD1);
		outready();
		superio_writedata(x);	/* toggle reset */
		microdelay(100);
	}
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
static int
ps2mouseputc(int c)
{
	static short msg[3];
	static int nb;
	static uchar b[] = {0, 1, 4, 5, 2, 3, 6, 7, 0, 1, 2, 5, 2, 3, 6, 7 };
	int buttons, dx, dy;

	/* 
	 *  check byte 0 for consistency
	 */
	if(nb==0 && (c&0xc8)!=0x08)
		return 0;

	msg[nb] = c;
	if(++nb == 3) {
		nb = 0;
		if(msg[0] & 0x10)
			msg[1] |= 0xFF00;
		if(msg[0] & 0x20)
			msg[2] |= 0xFF00;

		buttons = b[(msg[0]&7) | (shift ? 8 : 0)] | keybuttons;
		dx = msg[1];
		dy = -msg[2];
		mousetrack(buttons, dx, dy, 1);
	}
	return 0;
}

/*
 *  keyboard interrupt
 */
void
kbdintr(void)
{
	int s, c, i;
	static int esc1, esc2;
	static int caps;
	static int ctl;
	static int num;
	static int collecting, nk;
	static int alt;
	static Rune kc[5];
	int keyup;

	/*
	 *  get status
	 */
	s = superio_readctl();
	if(!(s&Inready))
		return;

	/*
	 *  get the character
	 */
	c = superio_readdata();

	/*
	 *  if it's the mouse...
	 */
	if(s & Minready) {
		ps2mouseputc(c);
		return;
	}

	/*
	 *  e0's is the first of a 2 character sequence
	 */
	if(c == 0xe0){
		esc1 = 1;
		return;
	} else if(c == 0xe1){
		esc2 = 2;
		return;
	}

	keyup = c&0x80;
	c &= 0x7f;
	if(c > sizeof kbtab){
/*		print("unknown key %ux\n", c|keyup); */
		return;
	}

	if(esc1){
		c = kbtabesc1[c];
		esc1 = 0;
	} else if(esc2){
		esc2--;
		return;
	} else if(shift)
		c = kbtabshift[c];
	else
		c = kbtab[c];

	if(caps && c<='z' && c>='a')
		c += 'A' - 'a';

	/*
	 *  keyup only important for shifts
	 */
	if(keyup){
		switch(c){
		case Latin:
			alt = 0;
			break;
		case Shift:
			shift = 0;
			break;
		case Ctrl:
			ctl = 0;
			break;
		}
		return;
	}

	/*
 	 *  normal character
	 */
	if(!(c & Spec)){
		if(ctl){
			if(alt && c == Del)
				exit(0);
			c &= 0x1f;
		}
		if(!collecting){
			kbdputc(kbdq, c);
			return;
		}
		kc[nk++] = c;
		c = latin1(kc, nk);
		if(c < -1)	/* need more keystrokes */
			return;
		if(c != -1)	/* valid sequence */
			kbdputc(kbdq, c);
		else	/* dump characters */
			for(i=0; i<nk; i++)
				kbdputc(kbdq, kc[i]);
		nk = 0;
		collecting = 0;
		return;
	} else {
		switch(c){
		case Caps:
			caps ^= 1;
			return;
		case Num:
			num ^= 1;
			return;
		case Shift:
			shift = 1;
			return;
		case Latin:
			alt = 1;
			collecting = 1;
			nk = 0;
			return;
		case Ctrl:
			ctl = 1;
			return;
		}
	}
	kbdputc(kbdq, c);
}

/*
 *  set up a ps2 mouse
 */
static void
ps2mouse(void)
{
	int x;

	/* enable kbd/mouse xfers and interrupts */
	x = splhi();
	ccc &= ~Cmousedis;
	ccc |= Cmouseint;
	if(outready() < 0)
		print("mouse init failed\n");
	superio_writectl(0x60);
	if(outready() < 0)
		print("mouse init failed\n");
	superio_writedata(ccc);
	if(outready() < 0)
		print("mouse init failed\n");
	superio_writectl(0xA8);
	if(outready() < 0){
		splx(x);
		return;
	}

	/* make mouse streaming, enabled */
	mousecmd(0xEA);
	mousecmd(0xF4);
	splx(x);
}

void
kbdinit(void)
{
	int c;

	kbdq = qopen(4*1024, 0, 0, 0);
	qnoblock(kbdq, 1);

	/* wait for a quiescent controller */
	while((c = superio_readctl()) & (Outbusy | Inready))
		if(c & Inready)
			superio_readdata();

	/* get current controller command byte */
	superio_writectl(0x20);
	if(inready() < 0){
		print("kbdinit: can't read ccc\n");
		ccc = 0;
	} else
		ccc = superio_readdata();

	/* enable kbd xfers and interrupts */
	/* disable mouse */
	ccc &= ~Ckbddis;
	ccc |= Csf | Ckbdint | Cscs1 | Cmousedis;
	if(outready() < 0)
		print("kbd init failed\n");
	superio_writectl(0x60);
	if(outready() < 0)
		print("kbd init failed\n");
	superio_writedata(ccc);
	outready();

	/* Assume ps2 mouse */
	ps2mouse();
}
