/*
 * Driver for Hauppage TV board
 *
 * Control commands:
 *
 *	init
 *	window %d %d %d %d
 *	colorkey %d %d %d %d %d %d
 *	capture %d %d %d %d
 *	capbrightness %d
 *	capcontrast %d
 *	capsaturation %d
 *	caphue %d
 *	capbw %d
 *	brightness %d
 *	contrast %d
 *	saturation %d
 *	source %d
 *	svideo %d
 *	format %d
 *	channel %d %d
 *	signal
 *	volume %d [ %d ]
 *	bass %d
 *	treble %d
 *	freeze %d
 */
#include	"u.h"
#include	"../port/lib.h"
#include	"mem.h"
#include	"dat.h"
#include	"fns.h"
#include	"../port/error.h"
#include	"tv.h"

#include	<draw.h>

enum {
	MemSize=			1,
	MemAddr=			0xB8000,

	CompressReg=			-14,

	/* smart lock registers */
	SLReg1=				-2,
	SLReg2=				-1,

	/* the Bt812 registers */
	Bt812Index=			-5,
	Bt812Data=			-6,

	Bt2VideoPresent=		0x40,
	Bt4ColorBars=			0x40,
	Bt5YCFormat=			0x80,
	Bt7TriState=			0x0C,

	/* VxP 500 registers */
	Vxp500Index=			0,
	Vxp500Data=			1,

	/* video controller registers */
	MemoryWindowBaseAddrA=		0x14,
	MemoryWindowBaseAddrB=		0x15,
	MemoryPageReg=			0x16,
	MemoryConfReg=			0x18,
	ISAControl=			0x30,
	I2CControl=			0x34,
	InputVideoConfA=		0x38,
	InputVideoConfB=		0x39,
	ISASourceWindowWidthA=		0x3A,
	ISASourceWindowWidthB=		0x3B,
	ISASourceWindowHeightA=		0x3C,
	ISASourceWindowHeightB=		0x3D,
	InputHorzCropLeftA=		0x40,
	InputHorzCropLeftB=		0x41,
	InputHorzCropRightA=		0x44,
	InputHorzCropRightB=		0x45,
	InputHorzCropTopA=		0x48,
	InputHorzCropTopB=		0x49,
	InputHorzCropBottomA=		0x4C,
	InputHorzCropBottomB=		0x4D,
	InputHorzFilter=		0x50,
	InputHorzScaleControlA=		0x54,
	InputHorzScaleControlB=		0x55,
	InputVertInterpolControl=	0x58,
	InputVertScaleControlA=		0x5C,
	InputVertScaleControlB=		0x5D,
	InputFieldPixelBufStatus=	0x64,
	VideoInputFrameBufDepthA=	0x68,
	VideoInputFrameBufDepthB=	0x69,
	AcquisitionControl=		0x6C,
	AcquisitionAddrA=		0x70,
	AcquisitionAddrB=		0x71,
	AcquisitionAddrC=		0x72,
	VideoBufferLayoutControl=	0x73,
	CaptureControl=			0x80,
	CaptureViewPortAddrA=		0x81,
	CaptureViewPortAddrB=		0x82,
	CaptureViewPortAddrC=		0x83,
	CaptureViewPortWidthA=		0x84,
	CaptureViewPortWidthB=		0x85,
	CaptureViewPortHeightA=		0x86,
	CaptureViewPortHeightB=		0x87,
	CapturePixelBufLow=		0x88,
	CapturePixelBufHigh=		0x89,
	CaptureMultiBufDepthA=		0x8A,
	CaptureMultiBufDepthB=		0x8B,
	DisplayControl=			0x92,
	VGAControl=			0x94,
	OutputProcControlA=		0x96,
	OutputProcControlB=		0x97,
        DisplayViewPortStartAddrA=	0xA0,
        DisplayViewPortStartAddrB=	0xA1,
        DisplayViewPortStartAddrC=	0xA2,
	DisplayViewPortWidthA=		0xA4,
	DisplayViewPortWidthB=		0xA5,
	DisplayViewPortHeightA=		0xA6,
	DisplayViewPortHeightB=		0xA7,
	DisplayViewPortOrigTopA=	0xA8,
	DisplayViewPortOrigTopB=	0xA9,
	DisplayViewPortOrigLeftA=	0xAA,
	DisplayViewPortOrigLeftB=	0xAB,
	DisplayWindowLeftA=		0xB0,
	DisplayWindowLeftB=		0xB1,
	DisplayWindowRightA=		0xB4,
	DisplayWindowRightB=		0xB5,
	DisplayWindowTopA=		0xB8,
	DisplayWindowTopB=		0xB9,
	DisplayWindowBottomA=		0xBC,
	DisplayWindowBottomB=		0xBD,
	OutputVertZoomControlA=		0xC0,
	OutputVertZoomControlB=		0xC1,
	OutputHorzZoomControlA=		0xC4,
	OutputHorzZoomControlB=		0xC5,
	BrightnessControl=		0xC8,
	ContrastControl=		0xC9,
	SaturationControl=		0xCA,
	VideoOutIntrStatus=		0xD3,

	/* smart lock bits */
	PixelClk=			0x03,
	SmartLock=			0x00,
	FeatureConnector=		0x01,
	Divider=			0x02,
	Window=				0x08,
	KeyWindow=			0x0C,
	HSyncLow=			0x20,
	VSyncLow=			0x40,

	ClkBit=				0x01,
	DataBit=			0x02,
	HoldBit=			0x04,
	SelBit=				0x08,
	DivControl=			0x40,

	/* i2c bus control bits */
	I2C_Clock=			0x02,
	I2C_Data=			0x08,
	I2C_RdClock=			0x10,
	I2C_RdData=			0x20,
	I2C_RdData_D=			0x40,

	/* I2C bus addresses */
	Adr5249=			0x22,	/* teletext decoder */
	Adr8444=			0x48,	/* 6-bit DAC (TDA 8444) */
	Adr6300=			0x80,	/* sound fader (TEA 6300) */
	Adr6320=			0x80,	/* sound fader (TEA 6320T) */
	AdrTuner=			0xC0,

	/* Philips audio chips */
	TEA6300=			0,
	TEA6320T=			1,

	/* input formats */
	NTSC_M = 0,
	NTSC_443 = 1,
	External = 2,

	NTSCCropLeft= 			36,	/* NTSC 3.6 usec */
	NTSCCropRight=			558,	/* NTSC 55.8 usec */

	/* color control indices */
	Vxp500Brightness=		1,
	Vxp500Contrast=			2,
	Vxp500Saturation=		3,
	Bt812Brightness=		4,
	Bt812Contrast=			5,
	Bt812Saturation=		6,
	Bt812Hue=			7,
	Bt812BW=			8,

	/* board revision numbers */
	RevisionPP=			0,
	RevisionA=			1,
	HighQ=				2,

	/* VGA controller registers */
	VGAMiscOut=			0x3CC,
	VGAIndex=			0x3D4,
	VGAData=			0x3D5,
	VGAHorzTotal=			0x00,
};

enum {
	Qdir,
	Qdata,
	Qctl,
};

static
Dirtab tvtab[]={
	".",		{Qdir, 0, QTDIR},	0,	0555,
	"tv",		{Qdata, 0},	0,	0666,
	"tvctl",	{Qctl, 0},	0,	0666,
};

static
int ports[] = {	/* board addresses */
	0x51C, 0x53C, 0x55C, 0x57C,
	0x59C, 0x5BC, 0x5DC, 0x5FC
};

/*
 * Default settings, settings between 0..100
 */
static
int defaults[] = {
	Vxp500Brightness,	0,
	Vxp500Contrast,		54,
	Vxp500Saturation,	54,
	Bt812Brightness,	13,
	Bt812Contrast,		57,
	Bt812Saturation,	51,
	Bt812Hue,		0,
	Bt812BW,		0,
};

static int port;
static int soundchip;
static int boardrev;
static int left, right;
static int vsync, hsync;
static ulong xtalfreq;
static ushort cropleft, cropright;
static ushort cropbottom, croptop;
static Rectangle window, capwindow;

static void setreg(int, int);
static void setbt812reg(int, int);
static void videoinit(void);
static void createwindow(Rectangle);
static void setcontrols(int, uchar);
static void setcolorkey(int, int, int, int, int, int);
static void soundinit(void);
static void setvolume(int, int);
static void setbass(int);
static void settreble(int);
static void setsoundsource(int);
static void tunerinit(void);
static void settuner(int, int);
static void setvideosource(int);
static int waitvideosignal(void);
static void freeze(int);
static void setsvideo(int);
static void setinputformat(int);
static void enablevideo(void);
static void *saveframe(int *);

static int
min(int a, int b)
{
	return a < b ? a : b;
}

static int
max(int a, int b)
{
	return a < b ? b : a;
}

static int
present(int port)
{
	outb(port+Vxp500Index, 0xAA);
	if (inb(port+Vxp500Index) != 0xAA)
		return 0;
	outb(port+Vxp500Index, 0x55);
	outb(port+Vxp500Data, 0xAA);
	if (inb(port+Vxp500Index) != 0x55)
		return 0;
	if (inb(port+Vxp500Data) != 0xAA)
		return 0;
	outb(port+Vxp500Data, 0x55);
	if (inb(port+Vxp500Index) != 0x55)
		return 0;
	if (inb(port+Vxp500Data) != 0x55)
		return 0;
	return 1;
}

static int
getvsync(void)
{
	int vslow, vshigh, s;
	ushort timo;

	s = splhi();

	outb(port+Vxp500Index, VideoOutIntrStatus);

	/* wait for VSync to go high then low */
	for (timo = ~0; timo; timo--)
		if (inb(port+Vxp500Data) & 2) break;
	for (timo = ~0; timo; timo--)
		if ((inb(port+Vxp500Data) & 2) == 0) break;

	/* count how long it stays low and how long it stays high */
	for (vslow = 0, timo = ~0; timo; timo--, vslow++)
		if (inb(port+Vxp500Data) & 2) break;
	for (vshigh = 0, timo = ~0; timo; timo--, vshigh++)
		if ((inb(port+Vxp500Data) & 2) == 0) break;
	splx(s);

	return vslow < vshigh;
}

static int
gethsync(void)
{
	int hslow, hshigh, s;
	ushort timo;

	s = splhi();

	outb(port+Vxp500Index, VideoOutIntrStatus);

	/* wait for HSync to go high then low */
	for (timo = ~0; timo; timo--)
		if (inb(port+Vxp500Data) & 1) break;
	for (timo = ~0; timo; timo--)
		if ((inb(port+Vxp500Data) & 1) == 0) break;

	/* count how long it stays low and how long it stays high */
	for (hslow = 0, timo = ~0; timo; timo--, hslow++)
		if (inb(port+Vxp500Data) & 1) break;
	for (hshigh = 0, timo = ~0; timo; timo--, hshigh++)
		if ((inb(port+Vxp500Data) & 1) == 0) break;
	splx(s);

	return hslow < hshigh;
}

static void
tvinit(void)
{
	int i;

	for (i = 0, port = 0; i < nelem(ports); i++) {
		if (present(ports[i])) {
			port = ports[i];
			break;
		}
	}
	if (i == nelem(ports))
		return;

	/*
	 * the following routines are the prefered way to
	 * find out the sync polarities. Unfortunately, it
	 * doesn't always work.
	 */
#ifndef VSync
	vsync = getvsync();
	hsync = gethsync();
#else
	vsync = VSync;
	hsync = HSync;
#endif
	left = right = 80;
	soundinit();
	tunerinit();
	videoinit();
}

static Chan*
tvattach(char *spec)
{
	if (port == 0)
		error(Enonexist);
	return devattach('V', spec);
}

static Walkqid*
tvwalk(Chan *c, Chan *nc, char **name, int nname)
{
	return devwalk(c, nc, name, nname, tvtab, nelem(tvtab), devgen);
}

static int
tvstat(Chan *c, uchar *db, int n)
{
	return devstat(c, db, n, tvtab, nelem(tvtab), devgen);
}

static Chan*
tvopen(Chan *c, int omode)
{
	return devopen(c, omode, tvtab, nelem(tvtab), devgen);
}

static void
tvclose(Chan *)
{
}

static long
tvread(Chan *c, void *a, long n, vlong offset)
{
	static void *frame;
	static int size;

	USED(offset);

	switch((ulong)c->qid.path){
	case Qdir:
		return devdirread(c, a, n, tvtab, nelem(tvtab), devgen);
	case Qdata:
		if (eqrect(capwindow, Rect(0, 0, 0, 0)))
			error(Ebadarg);
		if (offset == 0)
			frame = saveframe(&size);
		if (frame) {
			if (n > size - offset)
				n = size - offset;
			memmove(a, (char *)frame + offset, n);
		} else
			error(Enovmem);
		break;
	default:
		n=0;
		break;
	}
	return n;
}

static long
tvwrite(Chan *c, void *vp, long n, vlong offset)
{
	char buf[128], *field[10], *a;
	int i, nf, source;
	static Rectangle win;
	static int hsize, size = 0;
	static void *frame;

	USED(offset);

	a = vp;
	switch((ulong)c->qid.path){
	case Qctl:
		if (n > sizeof(buf)-1)
			n = sizeof(buf)-1;
		memmove(buf, a, n);
		buf[n] = '\0';

		nf = getfields(buf, field, nelem(field), 1, " \t");
		if (nf < 1) error(Ebadarg);

		if (strcmp(field[0], "init") == 0) {
			window = Rect(0, 0, 0, 0);
			capwindow = Rect(0, 0, 0, 0);
			source = 0; /* video 0 input */
			setvideosource(source);
			left = right = 80;
			setsoundsource(source);
			for (i = 0; i < nelem(defaults); i += 2)
				setcontrols(defaults[i], defaults[i+1]);
		} else if (strcmp(field[0], "colorkey") == 0) {
			if (nf < 7) error(Ebadarg);
			setcolorkey(strtoul(field[1], 0, 0), strtoul(field[2], 0, 0),
				strtoul(field[3], 0, 0), strtoul(field[4], 0, 0),
				strtoul(field[5], 0, 0), strtoul(field[6], 0, 0));
		} else if (strcmp(field[0], "window") == 0) {
			if (nf < 5) error(Ebadarg);
			createwindow(Rect(strtoul(field[1], 0, 0), strtoul(field[2], 0, 0),
				strtoul(field[3], 0, 0), strtoul(field[4], 0, 0)));
			setvolume(left, right);
		} else if (strcmp(field[0], "capture") == 0) {
			if (nf < 5) error(Ebadarg);
			capwindow = Rect(strtoul(field[1], 0, 0), strtoul(field[2], 0, 0),
				strtoul(field[3], 0, 0), strtoul(field[4], 0, 0));
		} else if (strcmp(field[0], "freeze") == 0) {
			if (nf < 2) error(Ebadarg);
			freeze(strtoul(field[1], 0, 0));
		} else if (strcmp(field[0], "capbrightness") == 0) {
			if (nf < 2) error(Ebadarg);
			setcontrols(Bt812Brightness, strtoul(field[1], 0, 0));
		} else if (strcmp(field[0], "capcontrast") == 0) {
			if (nf < 2) error(Ebadarg);
			setcontrols(Bt812Contrast, strtoul(field[1], 0, 0));
		} else if (strcmp(field[0], "capsaturation") == 0) {
			if (nf < 2) error(Ebadarg);
			setcontrols(Bt812Saturation, strtoul(field[1], 0, 0));
		} else if (strcmp(field[0], "caphue") == 0) {
			if (nf < 2) error(Ebadarg);
			setcontrols(Bt812Hue, strtoul(field[1], 0, 0));
		} else if (strcmp(field[0], "capbw") == 0) {
			if (nf < 2) error(Ebadarg);
			setcontrols(Bt812BW, strtoul(field[1], 0, 0));
		} else if (strcmp(field[0], "brightness") == 0) {
			if (nf < 2) error(Ebadarg);
			setcontrols(Vxp500Brightness, strtoul(field[1], 0, 0));
		} else if (strcmp(field[0], "contrast") == 0) {
			if (nf < 2) error(Ebadarg);
			setcontrols(Vxp500Contrast, strtoul(field[1], 0, 0));
		} else if (strcmp(field[0], "saturation") == 0) {
			if (nf < 2) error(Ebadarg);
			setcontrols(Vxp500Saturation, strtoul(field[1], 0, 0));
		} else if (strcmp(field[0], "source") == 0) {
			if (nf < 2) error(Ebadarg);
			source = strtoul(field[1], 0, 0);
			setvideosource(source);
			setsoundsource(source);	
		} else if (strcmp(field[0], "svideo") == 0) {
			if (nf < 2) error(Ebadarg);
			setsvideo(strtoul(field[1], 0, 0));
		} else if (strcmp(field[0], "format") == 0) {
			if (nf < 2) error(Ebadarg);
			setinputformat(strtoul(field[1], 0, 0));
		} else if (strcmp(field[0], "channel") == 0) {
			if (nf < 3) error(Ebadarg);
			setvolume(0, 0);
			settuner(strtoul(field[1], 0, 0), strtoul(field[2], 0, 0));
			tsleep(&up->sleep, return0, 0, 300);
			setvolume(left, right);
		} else if (strcmp(field[0], "signal") == 0) {
			if (!waitvideosignal())
				error(Etimedout);
		} else if (strcmp(field[0], "volume") == 0) {
			if (nf < 2) error(Ebadarg);
			left = strtoul(field[1], 0, 0);
			if (nf < 3)
				right = left;
			else
				right = strtoul(field[2], 0, 0);
			setvolume(left, right);
		} else if (strcmp(field[0], "bass") == 0) {
			if (nf < 2) error(Ebadarg);
			setbass(strtoul(field[1], 0, 0));
		} else if (strcmp(field[0], "treble") == 0) {
			if (nf < 2) error(Ebadarg);
			settreble(strtoul(field[1], 0, 0));
		} else
			error(Ebadctl);
		break;		
	default:
		error(Ebadusefd);
	}
	return n;
}


Dev tvdevtab = {
	'V',
	"tv",

	devreset,
	tvinit,
	devshutdown,
	tvattach,
	tvwalk,
	tvstat,
	tvopen,
	devcreate,
	tvclose,
	tvread,
	devbread,
	tvwrite,
	devbwrite,
	devremove,
	devwstat,
};

static void
setreg(int index, int data)
{
	outb(port+Vxp500Index, index);
	outb(port+Vxp500Data, data);
}

static unsigned int
getreg(int index)
{
	outb(port+Vxp500Index, index);
	return inb(port+Vxp500Data);
}

/*
 * I2C routines
 */
static void
delayi2c(void)
{
	int i, val;

	/* delay for 4.5 usec to guarantee clock time */
	for (i = 0; i < 75; i++) {	/* was 50 */
		val = inb(port+Vxp500Data);
		USED(val);
	}
}

static int
waitSDA(void)
{
	ushort timo;

	/* wait for i2c clock to float high */
	for (timo = ~0; timo; timo--)
		if (inb(port+Vxp500Data) & I2C_RdData)
			break;
	if (!timo) print("devtv: waitSDA fell out of loop\n");
	return !timo;
}

static int
waitSCL(void)
{
	ushort timo;

	/* wait for i2c clock to float high */
	for (timo = ~0; timo; timo--)
		if (inb(port+Vxp500Data) & I2C_RdClock)
			break;
	delayi2c();
	if (!timo) print("devtv: waitSCL fell out of loop\n");
	return !timo;
}

static int
seti2cdata(int data)
{
	int b, reg, val;
	int error;

	error = 0;
	reg = inb(port+Vxp500Data);
	for (b = 0x80; b; b >>= 1) {
		if (data & b)
			reg |= I2C_Data;
		else
			reg &= ~I2C_Data;
		outb(port+Vxp500Data, reg);
		reg |= I2C_Clock;
		outb(port+Vxp500Data, reg);
		error |= waitSCL();
		reg &= ~I2C_Clock;
		outb(port+Vxp500Data, reg);
		delayi2c();
	}
	reg |= I2C_Data;
	outb(port+Vxp500Data, reg);
	reg |= I2C_Clock;
	outb(port+Vxp500Data, reg);
	error |= waitSCL();
	val = inb(port+Vxp500Data);
	USED(val);
	reg &= ~I2C_Clock;
	outb(port+Vxp500Data, reg);
	delayi2c();
	return error;
}

static int
seti2creg(int id, int index, int data)
{
	int reg, error;

	error = 0;
        /* set i2c control register to enable i2c clock and data lines */
	setreg(I2CControl, I2C_Data|I2C_Clock);
	error |= waitSDA();
	error |= waitSCL();
	outb(port+Vxp500Data, I2C_Clock);
	delayi2c();
	outb(port+Vxp500Data, 0);
	delayi2c();

	error |= seti2cdata(id);
	error |= seti2cdata(index);
	error |= seti2cdata(data);

	reg = inb(port+Vxp500Data);
	reg &= ~I2C_Data;
	outb(port+Vxp500Data, reg);
	reg |= I2C_Clock;
	outb(port+Vxp500Data, reg);
	error |= waitSCL();
	reg |= I2C_Data;
	outb(port+Vxp500Data, reg);
	error |= waitSDA();
	return error;
}

static int
seti2cregs(int id, int index, int n, uchar *data)
{
	int reg, error;

	error = 0;
        /* set i2c control register to enable i2c clock and data lines */
	setreg(I2CControl, I2C_Data|I2C_Clock);
	error |= waitSDA();
	error |= waitSCL();
	outb(port+Vxp500Data, I2C_Clock);
	delayi2c();
	outb(port+Vxp500Data, 0);
	delayi2c();

	/* send data */
	error |= seti2cdata(id);
	error |= seti2cdata(index);
	while (n--)
		error |= seti2cdata(*data++);

	/* send stop */
	reg = inb(port+Vxp500Data);
	reg &= ~I2C_Data;
	outb(port+Vxp500Data, reg);
	reg |= I2C_Clock;
	outb(port+Vxp500Data, reg);
	error |= waitSCL();
	reg |= I2C_Data;
	outb(port+Vxp500Data, reg);
	error |= waitSDA();
	return error;
}

/*
 * Audio routines
 */
static void
setvolume(int left, int right)
{
	int vol, loudness = 0;

	if (soundchip == TEA6300) {
		seti2creg(Adr6300, 0, (63L * left) / 100);
		seti2creg(Adr6300, 1, (63L * right) / 100);
		vol = (15L * max(left, right)) / 100;
		seti2creg(Adr6300, 4, 0x30 | vol);
	} else {
		vol = (63L * max(left, right)) / 100;
		seti2creg(Adr6320, 0, vol | (loudness << 6));
		seti2creg(Adr6320, 1, (63L * right) / 100);
		seti2creg(Adr6320, 2, (63L * left) / 100);
	}
}

static void
setbass(int bass)
{
	if (soundchip == TEA6300)
		seti2creg(Adr6300, 2, (15L * bass) / 100);
	else
		seti2creg(Adr6320, 5, max((31L * bass) / 100, 4));
}

static void
settreble(int treble)
{
	if (soundchip == TEA6300)
		seti2creg(Adr6300, 3, (15L * treble) / 100);
	else
		seti2creg(Adr6320, 6, max((31L * treble) / 100, 7));

}

static void
setsoundsource(int source)
{
	if (soundchip == TEA6300)
		seti2creg(Adr6300, 5, 1 << source);
	else
		seti2creg(Adr6320, 7, source);
	setbass(50);
	settreble(50);
	setvolume(left, right);
}

static void
soundinit(void)
{
	if (seti2creg(Adr6320, 7, 0) && seti2creg(Adr6300, 4, 0))
		print("devtv: Audio init failed\n");

	soundchip = AudioChip;
	setvolume(0, 0);
}

/*
 * Tuner routines
 */
static
long hrcfreq[] = {	/* HRC CATV frequencies */
	    0,  7200,  5400,  6000,  6600,  7800,  8400, 17400,
	18000, 18600, 19200, 19800, 20400, 21000, 12000, 12600,
	13200, 13800, 14400, 15000, 15600, 16200, 16800, 21600,
	22200, 22800, 23400, 24000, 24600, 25200, 25800, 26400,
	27000, 27600, 28200, 28800, 29400, 30000, 30600, 31200,
	31800, 32400, 33000, 33600, 34200, 34800, 35400, 36000,
	36600, 37200, 37800, 38400, 39000, 39600, 40200, 40800,
	41400, 42000, 42600, 43200, 43800, 44400, 45000, 45600,
	46200, 46800, 47400, 48000, 48600, 49200, 49800, 50400,
	51000, 51600, 52200, 52800, 53400, 54000, 54600, 55200,
	55800, 56400, 57000, 57600, 58200, 58800, 59400, 60000,
	60600, 61200, 61800, 62400, 63000, 63600, 64200,  9000,
	 9600, 10200, 10800, 11400, 64800, 65400, 66000, 66600,
	67200, 67800, 68400, 69000, 69600, 70200, 70800, 71400,
	72000, 72600, 73200, 73800, 74400, 75000, 75600, 76200,
	76800, 77400, 78000, 78600, 79200, 79800,
};

static void
settuner(int channel, int finetune)
{
	static long lastfreq;
	uchar data[3];
	long freq;
	int cw2, n, sa;

	if (channel < 0 || channel > nelem(hrcfreq))
		error(Ebadarg);

	freq = hrcfreq[channel];

	/* these settings are all for (FS936E) USA Tuners */
	if (freq < 16025) /* low band */
		cw2 = 0xA4;
	else if (freq < 45425) /* mid band */
		cw2 = 0x94;
	else
		cw2 = 0x34;

	/*
	 * Channels are stored are 1/100 MHz resolutions, but
	 * the tuner wants stuff in MHZ, so divide by 100, we
	 * then have to shift by 4 to get the prog. div. value
	 */
	n = ((freq + 4575L) * 16) / 100L + finetune;

	if (freq > lastfreq) {
		sa = (n >> 8) & 0xFF;
		data[0] = n & 0xFF;
		data[1] = 0x8E;
		data[2] = cw2;
	} else {
		sa = 0x8E;
		data[0] = cw2;
		data[1] = (n >> 8) & 0xFF;
		data[2] = n & 0xFF;
	}
	lastfreq = freq;
	seti2cregs(AdrTuner, sa, 3, data);
}

static void
tunerinit(void)
{
	if (seti2creg(AdrTuner, 0, 0))
		print("devtv: Tuner init failed\n");
}

/*
 * Video routines
 */
static int slreg1 = 0;
static int slreg2 = 0;
static int vcogain = 0;
static int phdetgain = 2;
static int plln1 = 2;
static int pllp2 = 1;

static void
waitforretrace(void)
{
	ushort timo;

	for (timo = ~0; (getreg(VideoOutIntrStatus) & 2) == 0 && timo; timo--)
		/* wait for VSync inactive */;
	for (timo = ~0; (getreg(VideoOutIntrStatus) & 2) && timo; timo--)
		/* wait for VSync active */;
}

static void
updateshadowregs(void)
{
	int val;

	setreg(InputVideoConfA, getreg(InputVideoConfA) | 0x40);
	val = getreg(OutputProcControlB);
	setreg(OutputProcControlB, val & 0x7F);
	setreg(OutputProcControlB, val | 0x80);
}

static void
setvgareg(int data)
{
	/* set HSync & VSync first, to make sure VSync works properly */
	setreg(VGAControl,  (getreg(VGAControl) & ~0x06) | (data & 0x06));

	/* wait for VSync and set the whole register */
	waitforretrace();
	setreg(VGAControl, data);
}

static void
setbt812reg(int index, int data)
{
	outb(port+Bt812Index, index);
	outb(port+Bt812Data, data);
}

static int
getbt812reg(int index)
{
	outb(port+Bt812Index, index);
	return inb(port+Bt812Data);
}

static void
setbt812regpair(int index, ushort data)
{
	outb(port+Bt812Index, index);
	outb(port+Bt812Data, data);
	outb(port+Bt812Data, data >> 8);
}

static void
setvideosource(int source)
{
	int s;

	source &= 7;
	s = source & 3;
	setbt812reg(0, ((s << 2) | s) << 3);
	s = (source & 4) << 4;
	setbt812reg(4, (getbt812reg(4) & ~Bt4ColorBars) | s);
}

static void
setsvideo(int enable)
{
	if (enable)
		setbt812reg(5, getbt812reg(5) | Bt5YCFormat);
	else
		setbt812reg(5, getbt812reg(5) & ~Bt5YCFormat);
}

static int
waitvideosignal(void)
{
	ushort timo;

	for (timo = ~0; timo; timo--)
		if (getbt812reg(2) & Bt2VideoPresent)
			return 1;
	return 0;
}

/*
 * ICS1572 Programming Configuration
 *
 *	R  = 1
 *	M  = x
 *	A  = x
 *	N1 = 4
 *	N2 = internal divide ratio
 */
static
uchar ICSbits[7] = {
	0x01,			/* bits  8 - 1	00000001 */
	0x05,			/* bits 16 - 9	00000101 */
	0xFF,			/* bits 24 - 17	11111111 */
	0x8C,			/* bits 32 - 25	10001100 */
	0xBF,			/* bits 40 - 33	10111111 */
	0x00,			/* bits 48 - 41	00000000 */
	0x00,			/* bits 56 - 49	00000000 */
};

static void
sendbit(int val, int hold)
{
	slreg2 &= ~(HoldBit|DataBit|ClkBit);
	if (val) slreg2 |= DataBit;
	if (hold) slreg2 |= HoldBit;
	outb(port+SLReg2, slreg2);
	outb(port+SLReg2, slreg2|ClkBit);
	outb(port+SLReg2, slreg2);
}

static void
load1572(int select)
{
	int reg;
	uchar mask;

	if (select)
		slreg2 |= SelBit;
	else
		slreg2 &= ~SelBit;
	outb(port+SLReg2, slreg2);

	for (reg = 0; reg < sizeof(ICSbits); reg++) {
		for (mask = 1; mask != 0; mask <<= 1) {
			if (reg == sizeof(ICSbits)-1 && mask == 0x80) {
				sendbit(ICSbits[reg] & mask, 1);
			} else
				sendbit(ICSbits[reg] & mask, 0);
		}
	}
}

static void
smartlockdiv(int count, int vcogain, int phdetgain, int n1, int p2)
{
	int extdiv, intdiv;
	int nslreg2, external; 

	nslreg2 = slreg2;
	extdiv = ((count - 1) / 512) + 1;
	intdiv = (count / extdiv);
	nslreg2 &= ~0xC0;
	switch (extdiv) {
	case 1: external = 0; break;
	case 2: external = 1; break;
	case 3: external = 1; nslreg2 |= 0x40; break;
	case 4:	external = 1; nslreg2 |= 0x80; break;
	default: return;
	}
	if ((slreg1 & PixelClk) == 0) {
		slreg2 = nslreg2;
		outb(port+SLReg2, slreg2);
	}

	/* set PLL divider */
	ICSbits[0] &= ~0x07;
	ICSbits[0] |= n1 & 0x07;
	ICSbits[3] &= ~0xB7;
	ICSbits[3] |= vcogain & 0x07;
	ICSbits[3] |= (phdetgain & 0x03) << 4;
	ICSbits[3] |= p2 << 7;
	if (external)
		ICSbits[1] |= 0x04;		/* set EXTFBKEN	 */
	else
		ICSbits[1] &= ~0x04;		/* clear EXTFBKEN */
	intdiv--;
	ICSbits[2] = intdiv;			/* set N2 */
	ICSbits[3] &= ~ 0x08;
	ICSbits[3] |= (intdiv >> 5) & 0x08;
	load1572(1);
}

static void
disablecolorkey(void)
{
	setreg(DisplayControl, getreg(DisplayControl) & 0xFE);
	updateshadowregs();			
}

static 
uchar colorkeylimit[6] = {
	15,		/* upper limit green */
	255,		/* lower limit green */
	63,		/* upper limit red */
	63,		/* upper limit blue */
	15,		/* lower limit red */
	15,		/* lower limit blue */
};

static void
enablecolorkey(int enable)
{
	int i;

	if (enable) {
		for (i = 0; i < 6; i++)
			seti2creg(Adr8444, 0xF0 | i, colorkeylimit[i]);
		slreg1 &= ~0x1C;
		if (colorkeylimit[4] == 255)
			slreg1 |= 0x04;		/* disable red lower limit */
		if (colorkeylimit[1] == 255)
			slreg1 |= 0x08;		/* disable green lower limit */
		if (colorkeylimit[5] == 255)
			slreg1 |= 0x10;		/* disable blue lower limit */
	} else {
		for (i = 0; i < 6; i++)
			seti2creg(Adr8444, 0xF0 | i, 63);
		slreg1 |= 0x1C;
	}
	outb(port+SLReg1, slreg1);
	disablecolorkey();
}

static void
setcolorkey(int rl, int rh, int gl, int gh, int bl, int bh)
{
	colorkeylimit[0] = gh;
	colorkeylimit[1] = gl;
	colorkeylimit[2] = rh;
	colorkeylimit[3] = bh;
	colorkeylimit[4] = rl;
	colorkeylimit[5] = bl;
	enablecolorkey(1);
}

static void
waitvideoframe(void)
{
	ushort timo;
	int val;

	/* clear status bits and wait for start of an even field */
	val = getreg(InputFieldPixelBufStatus);
	USED(val);
	for (timo = ~0; timo; timo--)
		if ((getreg(InputFieldPixelBufStatus) & 2) == 0)
			break;
	if (!timo) print("devtv: Wait for video frame failed\n");
}

static void
freeze(int enable)
{
	ushort timo;
	int reg;

	if (enable) {
		waitvideoframe();
		waitvideoframe();

		setreg(InputVideoConfB, getreg(InputVideoConfB) | 0x08);
		updateshadowregs();

		for (timo = ~0; timo; timo--)
			if (getreg(InputVideoConfB) & 0x80) break;
		waitvideoframe();
		
		reg = getreg(OutputProcControlB);
		if ((reg & 0x20) == 0) {
			setreg(ISAControl, 0x80);
			setreg(OutputProcControlB, getreg(OutputProcControlB) | 0x20);
			setreg(ISAControl, 0x42);

			reg = getreg(OutputProcControlB);
			setreg(OutputProcControlB, reg & 0x7F);
			setreg(OutputProcControlB, reg | 0x80);
		}
	} else {
		setreg(InputVideoConfB, getreg(InputVideoConfB) & ~0x08);
		updateshadowregs();

		for (timo = ~0; timo; timo--)
			if (getreg(InputVideoConfB) & 0x40) break;
		waitvideoframe();
		reg = getreg(InputFieldPixelBufStatus);
		USED(reg);
	}
}

static void
enablevideo(void)
{
	setreg(DisplayControl, 0x04);
	updateshadowregs();
}

static void
disablevideo(void)
{
	setreg(DisplayControl, 0x18);
	updateshadowregs();
}

static
uchar vxp500init[] = { /* video register initialization in (index,data) hex pairs */
	0x30, 0x82, 0x39, 0x40, 0x58, 0x0C, 0x73, 0x02, 0x80, 0x00, 0x25, 0x0F,
	0x26, 0x0F, 0x38, 0x46, 0x30, 0x03, 0x12, 0x3B, 0x97, 0x20, 0x13, 0x00,
	0x14, 0x34, 0x15, 0x04, 0x16, 0x00, 0x17, 0x53, 0x18, 0x04, 0x19, 0x62,
	0x1C, 0x00, 0x1D, 0x00, 0x34, 0x3A, 0x38, 0x06, 0x3A, 0x00, 0x3B, 0x00,
	0x3C, 0x00, 0x3D, 0x00, 0x40, 0x40, 0x41, 0x40, 0x44, 0xFF, 0x45, 0xFF,
	0x48, 0x40, 0x49, 0x40, 0x4C, 0xFF, 0x4D, 0xFF, 0x50, 0xF0, 0x54, 0x30,
	0x55, 0x00, 0x5C, 0x04, 0x5D, 0x00, 0x60, 0x00, 0x68, 0x00, 0x69, 0x00,
	0x6C, 0x06, 0x6D, 0x00, 0x70, 0x00, 0x71, 0x00, 0x72, 0x00, 0x78, 0x01,
	0x79, 0x0C, 0x80, 0x10, 0x81, 0x00, 0x82, 0x00, 0x83, 0x00, 0x84, 0x00,
	0x85, 0x00, 0x86, 0x00, 0x87, 0x00, 0x88, 0x04, 0x89, 0x10, 0x8A, 0x00,
	0x8B, 0x00, 0x90, 0x05, 0x91, 0x0C, 0x92, 0x18, 0x93, 0x00, 0x96, 0x18,
	0x9A, 0x30, 0x9C, 0x2D, 0x9D, 0x00, 0xA0, 0x00, 0xA1, 0x00, 0xA2, 0x00,
	0xA4, 0x50, 0xA5, 0x50, 0xA6, 0xF0, 0xA7, 0xF0, 0xA8, 0x19, 0xA9, 0x18,
	0xAA, 0x64, 0xAB, 0x64, 0xB0, 0x64, 0xB1, 0x64, 0xB4, 0xA4, 0xB5, 0xA5,
	0xB8, 0x19, 0xB9, 0x18, 0xBC, 0x09, 0xBD, 0x09, 0xC0, 0x00, 0xC1, 0x02,
	0xC4, 0x00, 0xC5, 0x00, 0xC8, 0x00, 0xC9, 0x08, 0xCA, 0x08, 0xCE, 0x00,
	0xCF, 0x00, 0xD0, 0x00, 0xD1, 0x00, 0xD2, 0x00, 0xD8, 0x00, 0xD9, 0x00,
	0xDA, 0x00, 0xDB, 0x00, 0xDC, 0x00, 0xDD, 0x00, 0x38, 0x46, 0x97, 0xA0,
	0x97, 0x20, 0x97, 0xA0,
};

static
uchar bt812init[] = {	/* bt812 initializations */
	0xFF, 0x00, 0x00, 0x00, 0x01, 0x00, 0x02, 0x00, 0x03, 0xC0,
	0x04, 0x08, 0x05, 0x00, 0x06, 0x40, 0x07, 0x00, 0x08, 0x10,
	0x09, 0x90, 0x0A, 0x80, 0x0B, 0x00, 0x0C, 0x0C, 0x0D, 0x03,
	0x0E, 0x66, 0x0F, 0x00, 0x10, 0x80, 0x11, 0x02, 0x12, 0x16,
	0x13, 0x00, 0x14, 0xE5, 0x15, 0x01, 0x16, 0xAB, 0x17, 0xAA,
	0x18, 0x12, 0x19, 0x51, 0x1A, 0x46, 0x1B, 0x00, 0x1C, 0x00,
	0x1D, 0x37,
};

static ushort actpixs = 720;
static ulong Hdesired = 13500000L;

/*			   NTSC-M  NTSC-443  EXTERNAL */
static ushort horzfreq[] =	{   15734,    15625,        0 };
static ushort Vdelay[]	=	{      22,       25,       25 };
static ushort s2b[] =		{      90,       90,        0 };
static ushort actlines[] =	{     485,      485,      575 };
static ulong subcarfreq[] =	{ 3579545,  4433619,  4433619 };

static 
unsigned int framewidth[5][4] = {
	1024,  512,  512, 512,      /* mode 0 - single, double, single, quad */
	1536,  768,  768, 384,      /* mode 1 - single, double, single, quad */
	2048, 1024, 1024, 512,      /* mode 2 - single, double, single, quad */
	1024,  512,  512, 512,      /* mode 3 - single, double, single, quad */
	1536,  768,  768, 384       /* mode 4 - single, double, single, quad */
};

static 
unsigned int frameheight[5][4] = {
	512, 512, 1024, 512,        /* mode 0 - single, double, single, quad */
	512, 512, 1024, 512,        /* mode 1 - single, double, single, quad */
	512, 512, 1024, 512,        /* mode 2 - single, double, single, quad */
	512, 512, 1024, 512,        /* mode 3 - single, double, single, quad */
	512, 512, 1024, 256         /* mode 4 - single, double, single, quad */
};

static
uchar horzfilter[] = { 3, 3, 2, 2, 1, 1, 0, 0 };

static
uchar interleave[] = { 2, 3, 4, 2, 3 };

#define	ADJUST(n)	(((n) * hrsmult + hrsdiv - 1) / hrsdiv)

static int q = 100;
static int ilv = 2;
static int hrsmult = 1;
static int hrsdiv = 2;

static ushort panmask[] = { 0xFFFE, 0xFFFC, 0xFFFF, 0xFFFF, 0xFFFE };


static void
cropwindow(int left, int right, int top, int bottom)
{
	top &= 0x3FE;
	bottom &= 0x3FE;
        setreg(InputHorzCropLeftA, left);
        setreg(InputHorzCropLeftB, left >> 8);
        setreg(InputHorzCropRightA, right);
        setreg(InputHorzCropRightB, right >> 8);
        setreg(InputHorzCropTopA, top);
        setreg(InputHorzCropTopB, top >> 8);
        setreg(InputHorzCropBottomA, bottom);
        setreg(InputHorzCropBottomB, bottom >> 8);
}

static void
setinputformat(int format)
{
	ushort hclock, hclockdesired;
	ulong subcarrier;
	int cr7;

	cr7 = getbt812reg(7) & ~Bt7TriState;
	if (format == External)
		cr7 |= Bt7TriState;
	setbt812reg(7, cr7);
	setbt812reg(5, getbt812reg(5) & 2);

	hclock = (xtalfreq >> 1) / horzfreq[format];
	setbt812regpair(0x0C, hclock);
	setbt812regpair(0x0E,
		(ushort)(s2b[format] * (Hdesired / 10) / 1000000L) | 1);
	setbt812regpair(0x10, actpixs);
	setbt812regpair(0x12, Vdelay[format]);
	setbt812regpair(0x14, actlines[format]);

	subcarrier = (ulong)
		((((long long)subcarfreq[format] * 0x1000000) / xtalfreq + 1) / 2);
	setbt812regpair(0x16, (int)(subcarrier & 0xFFFF)); /* subcarrier */
	setbt812reg(0x18, (int)(subcarrier >> 16));

	setbt812reg(0x19, (uchar)(((xtalfreq / 200) * 675) / 1000000L + 8));
	setbt812reg(0x1A, (uchar)((xtalfreq * 65) / 20000000L - 10));
	hclockdesired = (ushort) (Hdesired / horzfreq[format]);
	setbt812regpair(0x1B,
		(ushort)(((hclock - hclockdesired) * 65536L) / hclockdesired));
}

static ushort
vgadivider(void)
{
	ushort horztotal;

	outb(VGAIndex, VGAHorzTotal);
	horztotal = (inb(VGAData) << 3) + 40;
	if (horztotal > ScreenWidth && horztotal < ((ScreenWidth * 3 ) / 2))
		return horztotal;
	else
		return (ScreenWidth * 5) / 4;
}

static void
videoinit(void)
{
	int i, reg, width, tuner;

	/* early PLL smart lock initialization */
	if (ScreenWidth == 640) {
		slreg1 = Window|HSyncLow|VSyncLow;
		slreg2 = 0x0D;
	} else {
		slreg1 = Window;
		slreg2 = 0x0C;
	}
	outb(port+CompressReg, 2);
	outb(port+SLReg1, slreg1);
	outb(port+SLReg2, slreg2);
	smartlockdiv((vgadivider() * hrsmult)/hrsdiv, vcogain, phdetgain, 2, 1);

	/* program the VxP-500 chip (disables video) */
	waitforretrace();
	for (i = 0; i < sizeof(vxp500init); i += 2)
		setreg(vxp500init[i], vxp500init[i+1]);

	/* set memory base for frame capture */
	setreg(MemoryWindowBaseAddrA, MemAddr >> 14);
	setreg(MemoryWindowBaseAddrB, ((MemAddr >> 22) & 3) | (MemSize << 2));
	setreg(MemoryPageReg, 0);

	/* generic 422 decoder, mode 3 and 4 */
	setreg(MemoryConfReg, ilv+1);

	setreg(AcquisitionAddrA, 0);
	setreg(AcquisitionAddrB, 0);
	setreg(AcquisitionAddrC, 0);

	/* program VxP-500 for correct sync polarity */
	reg = ScreenWidth > 1023 ? 0x01 : 0x00;
	reg |= (vsync << 1) | (hsync << 2);
	setvgareg(reg);
	setreg(VGAControl, reg);

	setreg(VideoBufferLayoutControl, 0); /* for ilv = 2 */

	/* set sync polarities to get proper blanking */
	if (vsync)
		slreg1 |= VSyncLow;
	if (!hsync) {
		slreg1 ^= HSyncLow;
		setreg(VGAControl, reg | 4);
	}
	outb(port+SLReg1, slreg1);

	if ((slreg1 & PixelClk) == 0) { /* smart lock active */
		enablecolorkey(1);
		setreg(VGAControl, getreg(VGAControl) & 6);
	} else
		enablecolorkey(0);

	/* color key initializations */
	if ((slreg1 & PixelClk) == 0)
		setreg(VGAControl, getreg(VGAControl) & 7);	

	/* initialize Bt812 */
	for (i = 0; i < sizeof(bt812init); i += 2)
		setbt812reg(bt812init[i], bt812init[i+1]);

	/* figure out clock source (Xtal or Oscillator) and revision */
	setbt812reg(6, 0x40);
	reg = getreg(InputFieldPixelBufStatus) & 3;
	if ((getreg(InputFieldPixelBufStatus) & 3) == reg) {
		/* crystal - could be revision PP if R34 is installed */
		setbt812reg(6, 0x00);
		reg = inb(port+SLReg1);
		if (reg & 0x20) {
			if ((reg & 0xE0) == 0xE0)
				boardrev = HighQ;
			else
				boardrev = RevisionA;
		} else
			boardrev = RevisionPP;
	} else /* revision A or newer with 27 MHz oscillator */
		boardrev = RevisionA;

	/* figure out xtal frequency */
	if (xtalfreq == 0) {
		if (boardrev == RevisionPP) {
			tuner = (inb(port+SLReg1) >> 6) & 3;
			if (tuner == 0) /* NTSC */
				xtalfreq = 24545400L;
			else
				xtalfreq = 29500000L;
		} else if (boardrev == HighQ)
			xtalfreq = 29500000L;
		else
			xtalfreq = 27000000L;
	}

//	print("Hauppage revision %d (xtalfreq %ld)\n", boardrev, xtalfreq);

	/* on RevPP boards set early sync, on rev A and newer clear it */
	if (boardrev == RevisionPP)
		setreg(InputVideoConfA, getreg(InputVideoConfA) | 4);
	else
		setreg(InputVideoConfA, getreg(InputVideoConfA) & ~4);

	switch (xtalfreq) {
	case 24545400L:
		actpixs = 640;
		break;
	case 29500000L:
		actpixs = 768;
		break;
	default:
		actpixs = 720;
		break;
	}

	/* set crop window (these values are for NTSC!) */
	if (boardrev == RevisionPP) {
		Hdesired = xtalfreq / 2;
		cropleft = (NTSCCropLeft * ((Hdesired / 10))) / 1000000L;
		cropright = (NTSCCropRight * ((Hdesired / 10))) / 1000000L;
	} else {
		cropleft = actpixs / 100;
		cropright = actpixs - cropleft;
	}
	width = ((cropright - cropleft + ilv) / ilv) * ilv;
	cropright = cropleft + width + 1;
	croptop = 26;
	cropbottom = 505;
	cropwindow(cropleft, cropright, croptop, cropbottom);

	/* set input format */
	setinputformat(NTSC_M);
	setsvideo(0);
}

static void
panwindow(Point p)
{
	int memmode, ilv, frw;
	ulong pos;

	memmode = getreg(MemoryConfReg) & 7;
	ilv = interleave[memmode];
	frw = framewidth[memmode][getreg(VideoBufferLayoutControl) & 3];

	pos = (p.y * (frw/ilv)) + ((p.x/ilv) & panmask[memmode]);
	setreg(DisplayViewPortStartAddrA, (uchar) pos);
	setreg(DisplayViewPortStartAddrB, (uchar) (pos >> 8));
	setreg(DisplayViewPortStartAddrC, (uchar) (pos >> 16) & 0x03);
	updateshadowregs();
}

static int
testqfactor(void)
{
	ulong timo;
	int reg;

	waitvideoframe();
	for (reg = 0, timo = ~0; timo; timo--) {
		reg |= getreg(InputFieldPixelBufStatus);
		if (reg & 0xE) break;
	}
	if (reg & 0xC) return 0;

	waitvideoframe();
	for (reg = 0, timo = ~0; timo; timo--) {
		reg |= getreg(InputFieldPixelBufStatus);
		if (reg & 0xE) break;
	}
	return (reg & 0xC) == 0;
}

static void
newwindow(Rectangle r)
{
	unsigned ww, wh, dx, dy, xs, ys, xe, ye;
	unsigned scalex, scaley;
	int frwidth, frheight, vidwidth, vidheight;
	int memmode, layout;
	int width, height;
	int filter, changed, val;

	changed = r.min.x != window.min.x || r.min.y != window.min.y ||
		  r.max.x != window.max.x || r.max.y != window.max.y;
	if (changed) window = r;

	if (r.min.x < 0) r.min.x = 0;
	if (r.max.x > ScreenWidth) r.max.x = ScreenWidth;
	if (r.min.y < 0) r.min.y = 0;
	if (r.max.y > ScreenHeight) r.max.y = ScreenHeight;

	if ((dx = r.max.x - r.min.x) <= 0) dx = 1;
	if ((dy = r.max.y - r.min.y) <= 0) dy = 1;

	wh = dy;
	ww = dx = ADJUST(dx);
	r.min.x = (r.min.x * hrsmult) / hrsdiv;

	memmode = getreg(MemoryConfReg) & 7;
	layout = getreg(VideoBufferLayoutControl) & 3;
	vidwidth = cropright - cropleft + 1;
	vidheight = (cropbottom & 0x3FE) - (croptop & 0x3FE) + 1;
	frwidth = min(framewidth[memmode][layout], vidwidth);
	frheight = min(frameheight[memmode][layout], vidheight);

	/* round up scale width to nearest multiple of interleave factor */
	dx = ((ulong)dx * q) / 100;
	dx = ilv * ((dx + ilv - 1) / ilv);

	scalex = (((ulong)dx * 1024L) + vidwidth - 2) / (vidwidth - 1);
	if (dy > frheight) dy = frheight - 1;
	scaley = (((ulong)dy * 1024L) + vidheight - 2) / (vidheight - 1);

	setreg(InputHorzScaleControlA, (scalex << 6) & 0xC0);
	setreg(InputHorzScaleControlB, (scalex >> 2) & 0xFF);
	setreg(InputVertScaleControlA, (scaley << 6) & 0xC0);
	setreg(InputVertScaleControlB, (scaley >> 2) & 0xFF);

	/* turn on horizontal filtering if we are scaling down */
	setreg(InputHorzFilter, horzfilter[((scalex - 1) >> 7) & 7]);

	/* set vertical interpolation */
	filter = scaley > 512 ? (ScreenWidth == 640 ? 0x44 : 0xC5) : 0x46; /* magic */
	if ((getreg(InputVertInterpolControl) & 0x1F) != (filter & 0x1F)) {
		setreg(ISAControl, 0x80);
		setreg(InputVertInterpolControl, filter & 0x1F);
		setreg(ISAControl, 0x42);
	}
	setreg(AcquisitionControl, ((filter >> 6) ^ 3) | 0x04);

	/* set viewport position and size */
	width = ((ulong)ww * q) / 100;
	if (width >= frwidth - ilv)
		width = frwidth - ilv;
	width = ((width + ilv - 1) / ilv) + 2;

	height = ((ulong)wh * dy + wh - 1) / wh;
	if (height >= frheight)
		height = frheight - 3;
	height += 2;

	xs = r.min.x + XCorrection;
	if (xs < 0) xs = 2;
	ys = r.min.y + YCorrection;
	if (ys < 0) ys = 2;
	if (ScreenWidth > 1023) ys |= 1;

	setreg(DisplayViewPortWidthA, width);
	setreg(DisplayViewPortWidthB, width >> 8);
	setreg(DisplayViewPortHeightA, height);
	setreg(DisplayViewPortHeightB, height >> 8);
	setreg(DisplayViewPortOrigTopA, ys);
	setreg(DisplayViewPortOrigTopB, ys >> 8);
	setreg(DisplayViewPortOrigLeftA, xs);
	setreg(DisplayViewPortOrigLeftB, xs >> 8);

	xe = r.min.x + ww - 1 + XCorrection;
	if (xe < 0) xe = 2;
	ye = r.min.y + wh - 1 + YCorrection;
	if (ye < 0) ye = 2;

	setreg(DisplayWindowLeftA, xs);
	setreg(DisplayWindowLeftB, xs >> 8);
	setreg(DisplayWindowRightA, xe);
	setreg(DisplayWindowRightB, xe >> 8);
	setreg(DisplayWindowTopA, ys);
	setreg(DisplayWindowTopB, ys >> 8);
	setreg(DisplayWindowBottomA, ye);
	setreg(DisplayWindowBottomB, ye >> 8);

	if (dx < ww) { /* horizontal zoom */
		int zoom = ((ulong) (dx - 1) * 2048) / ww;
		setreg(OutputProcControlA, getreg(OutputProcControlA) | 6);
		setreg(OutputHorzZoomControlA, zoom);
		setreg(OutputHorzZoomControlB, zoom >> 8);
	} else
		setreg(OutputProcControlA, getreg(OutputProcControlA) & 0xF9);

	if (dy < wh) { /* vertical zoom */
		int zoom = ((ulong) (dy - 1) * 2048) / wh;
		setreg(OutputProcControlB, getreg(OutputProcControlB) | 1);
		setreg(OutputVertZoomControlA, zoom);
		setreg(OutputVertZoomControlB, zoom >> 8);
	} else
		setreg(OutputProcControlB, getreg(OutputProcControlB) & 0xFE);

	setreg(OutputProcControlB, getreg(OutputProcControlB) | 0x20);
	updateshadowregs();

	if (changed) {
		setreg(OutputProcControlA, getreg(OutputProcControlA) & 0xDF);
	} else {
		val = getreg(InputFieldPixelBufStatus);
		USED(val);
	}

	panwindow(Pt(0, 0));
}

static void
createwindow(Rectangle r)
{
	for (q = 100; q >= 30; q -= 10) {
		newwindow(r);
		if (testqfactor())
			break;
	}
	enablevideo();
}

static void
setcontrols(int index, uchar val)
{
	switch (index) {
	case Vxp500Brightness:
		setreg(BrightnessControl, (127L * val) / 100);
		updateshadowregs();
		break;
	case Vxp500Contrast:
		setreg(ContrastControl, (15L * val) / 100);
		updateshadowregs();
		break;	
	case Vxp500Saturation:
		setreg(SaturationControl, (15L * val) / 100);
		updateshadowregs();
		break;
	case Bt812Brightness:
		setbt812reg(0x08, ((126L * val) / 100) & 0xFE);
		break;
	case Bt812Contrast:
		setbt812reg(0x09, ((254L * val) / 100) & 0xFE);
		break;
	case Bt812Saturation:
		setbt812reg(0x0A, ((254L * val) / 100) & 0xFE);
		break;
	case Bt812Hue:
		setbt812reg(0x0B, ((254L * val) / 100) & 0xFE);
		break;
	case Bt812BW:
		setbt812reg(0x05, (getbt812reg(0x5) & ~2) | ((val << 1) & 2));
		break;
	}
}

static void
enablememwindow(void)
{
	setreg(MemoryWindowBaseAddrB, getreg(MemoryWindowBaseAddrB) | 0x20);
}

static void
disablememwindow(void)
{
	setreg(MemoryWindowBaseAddrB, getreg(MemoryWindowBaseAddrB) & ~0x20);
}

volatile static ushort *fb = (ushort *)EISA(MemAddr);
static uchar yuvpadbound[] = { 4, 12, 4, 2, 6 }; 

/*
 * Capture a frame in UY0, VY1 format
 */
static void *
saveframe(int *nb)
{
	int memmode, layout, ilv;
	int frwidth, frheight;
	int bound, n, val, toggle;
	unsigned save58, save6C;
	int x, y, w, h, width, height;
	ulong pos, size;
	char *p;
	static void *frame = 0;
	static ulong framesize = 0;

	width = capwindow.max.x - capwindow.min.x;
	height = capwindow.max.y - capwindow.min.y;

	memmode = getreg(MemoryConfReg) & 7;
	if (memmode <= 2) {
		print("devtv: cannot handle YUV411\n");
		error(Egreg); /* actually, Eleendert */
	}
	layout = getreg(VideoBufferLayoutControl) & 3;
	ilv = interleave[memmode];
	frwidth = framewidth[memmode][layout];
	frheight = frameheight[memmode][layout];

	pos = getreg(AcquisitionAddrA) +
		(getreg(AcquisitionAddrB) << 8) + (getreg(AcquisitionAddrC) & 3) << 16;

	x = capwindow.min.x + (pos % frwidth);
	y = capwindow.min.y + (pos / frwidth);
	if (x > frwidth || y > frheight)
		return 0;
	if (x + width > frwidth)
		width = frwidth - x;
	if (y + height > frheight)
		height = frheight - y;

	pos = y * (frwidth / ilv) + (x / ilv);

	/* compute padding for each scan line */
	bound = yuvpadbound[memmode];
	switch (bound) {
	case 2:
		width = (width + 1) & ~1;
		break;
	case 4:
		width = (width + 3) & ~3;
		break;
	default:
		width = (width + (bound - 1)) / bound;
		break;
	}

	size = width * height * sizeof(ushort);
	if (size != framesize) {
		framesize = 0;
		if (frame)
			free(frame);
		frame = malloc(size + 256);
	}
	if (frame == 0)
		return 0;

	memset(frame, 0, size + 256);

	framesize = size;
	p = (char *) frame + snprint(frame, 256,
		"TYPE=ccir601\nWINDOW=%d %d %d %d\n\n",
		capwindow.min.x, capwindow.min.y, 
		capwindow.min.x+width, capwindow.min.y+height);

	freeze(1);

	save58 = getreg(InputVertInterpolControl);
	save6C = getreg(AcquisitionControl);

	waitforretrace();
	setreg(ISAControl, 0xC0); /* global reset */
	setreg(InputVertInterpolControl, 0x0D);
	setreg(AcquisitionControl, 0x04);
	setreg(CaptureControl, 0x80); /* set capture mode */
	setreg(VideoInputFrameBufDepthA, 0xFF);
	setreg(VideoInputFrameBufDepthB, 0x03);
	setreg(InputVideoConfA, getreg(InputVideoConfA) | 0x40);
	setreg(ISAControl, 0x44); /* tight decode, global reset off */

	setreg(CaptureViewPortAddrA, (int) pos & 0xFF);
	setreg(CaptureViewPortAddrB, (int) (pos >> 8) & 0xFF);
	setreg(CaptureViewPortAddrC, (int) (pos >> 16) & 0x03);
	n = (width / ilv) - 1;
	setreg(CaptureViewPortWidthA, n & 0xFF);
	setreg(CaptureViewPortWidthB, n >> 8);
	setreg(CaptureViewPortHeightA, (height-1) & 0xFF);
	setreg(CaptureViewPortHeightB, (height-1) >> 8);
	setreg(CapturePixelBufLow, 0x04); /* pix buffer low */
	setreg(CapturePixelBufHigh, 0x0E); /* pix buffer high */
	setreg(CaptureMultiBufDepthA, 0xFF); /* multi buffer depth maximum */
	setreg(CaptureMultiBufDepthB, 0x03);
	updateshadowregs();

	setreg(CaptureControl, 0x90); /* capture reset */
	val = getreg(InputFieldPixelBufStatus);	/* clear read status */
	USED(val);

	toggle = !(getreg(OutputProcControlA) & 0x01) ? 0x8000 : 0x0000;
	setreg(CaptureControl, 0xC0); /* capture enable, active */

	while ((getreg(InputFieldPixelBufStatus) & 0x10) == 0)
		/* wait for capture FIFO to become ready */;

	enablememwindow();
	for (h = height; h > 0; h--) {
		for (w = width; w > 0; w -= 2) {
			ushort uy0 = swab16(fb[0]) ^ toggle;
			ushort vy1 = swab16(fb[1]) ^ toggle;
			/* unfortunately p may not be properly aligned */
			*p++ = uy0 >> 8;
			*p++ = uy0;
			*p++ = vy1 >> 8;
			*p++ = vy1;	
		}
	}
	disablememwindow();

	waitforretrace();
	setreg(ISAControl, 0xC0); /* global reset */
	setreg(CaptureControl, 0); /* clear capture mode */
	setreg(InputVertInterpolControl, save58);
	setreg(AcquisitionControl, save6C);
	setreg(InputVideoConfA, getreg(InputVideoConfA) | 0x40);
	setreg(ISAControl, 0x40); /* clear global reset */
	updateshadowregs();

	freeze(0);

	*nb = p - (char *) frame;
	return frame;
}
