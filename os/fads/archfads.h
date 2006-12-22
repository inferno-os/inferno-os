
enum {
	/* BCSR1 bits */
	DisableFlash=	IBIT(0),
	DisableDRAM=	IBIT(1),
	DisableEther=	IBIT(2),
	DisableIR=	IBIT(3),
	DisableRS232a=	IBIT(7),
	DisablePCMCIA=	IBIT(8),
	PCCVCCMask=	IBIT(9)|IBIT(15),
	PCCVPPMask=	IBIT(10)|IBIT(11),
	DisableRS232b=	IBIT(13),
	EnableSDRAM=	IBIT(14),

	PCCVCC0V=	IBIT(15)|IBIT(9),
	PCCVCC5V=	IBIT(9),	/* active low */
	PCCVCC3V=	IBIT(15),	/* active low */
	PCCVPP0V=	IBIT(10)|IBIT(11),	/* active low */
	PCCVPP5V=	IBIT(10),	/* active low */
	PCCVPP12V=	IBIT(11),	/* active low */
	PCCVPPHiZ=	IBIT(10)|IBIT(11),

	/* BCSR4 bits */
	DisableTPDuplex=	IBIT(1),
	DisableLamp=	IBIT(3),
	DisableUSB=	IBIT(4),
	USBFullSpeed=	IBIT(5),
	DisableUSBVcc=	IBIT(6),
	DisableVideoLamp=	IBIT(8),
	EnableVideoClock=	IBIT(9),
	EnableVideoPort=	IBIT(10),
	DisableModem=	IBIT(11),
};
