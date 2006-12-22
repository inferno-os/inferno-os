/*
 * values for RPXLite AW
 */
enum {
	/* CS assignment */
	BOOTCS = 0,
	DRAM1CS = 1,
	DRAM2CS = 2,
	BCSRCS = 3,
	NVRAMCS = 4,
	/* expansion header on CS5 */
	PCMCIA0CS=	6,	/* even bytes(!); CS6 to header if OP2 high */
	PCMCIA1CS= 7,	/* odd bytes(!); CS7 to header if OP2 high */
};

/*
 * BCSR bits (there's only one register)
 */
enum {
	EnableEnet =	IBIT(0),
	EnableXcrLB=	IBIT(1),
	DisableColTest=	IBIT(2),
	DisableFullDplx=IBIT(3),
	LedOff=		IBIT(4),
	DisableUSB=	IBIT(5),
	HighSpdUSB=	IBIT(6),
	EnableUSBPwr=	IBIT(7),
	/* 8,9,10 unused */
	VCCMask=	IBIT(12)|IBIT(13),
	VPPMask=	IBIT(14)|IBIT(15),
	VCC0V=	0,
	VCC5V=	IBIT(13),
	VCC3V=	IBIT(12),
	VPP0V=	0,
	VPPVCC=	IBIT(14),
	VPP12V=	IBIT(15),
	VPPHiZ=	IBIT(14)|IBIT(15),
	/* 16-23 NYI */
	DipSwitchMask=	IBIT(24)|IBIT(25)|IBIT(26)|IBIT(27),
	DipSwitch0=	IBIT(24),
	DipSwitch1=	IBIT(25),
	DipSwitch2=	IBIT(26),
	DipSwitch3=	IBIT(27),
	/* bit 28 RESERVED */
	FlashComplete=	IBIT(29),
	NVRAMBattGood=	IBIT(30),
	RTCBattGood=	IBIT(31),
};
