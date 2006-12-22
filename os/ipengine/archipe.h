/*
 * values for Brightstar Engineering ipEngine
 */
enum {
	/* CS assignment */
	BOOTCS = 0,	/* flash */
	FPGACS = 1,	/* 8Mb FPGA space */
	DRAMCS = 2,
	FPGACONFCS = 3,	/* FPGA config */
	CLOCKCS = 4,	/* clock synth reg */
};

enum {
	/* port A pins */
	VCLK=	SIBIT(5),
	BCLK=	SIBIT(4),

	/* port B */
	EnableVCLK=	IBIT(30),
	EnableEnet=	IBIT(29),
	EnableRS232=	IBIT(28),
	EnetFullDuplex=	IBIT(16),

	/* port C */
	nCONFIG = SIBIT(13),	/* FPGA configuration */
	USBFullSpeed=	SIBIT(12),
	PDN=	SIBIT(5),	/* ? seems to control power to FPGA subsystem? */
	EnetLoopback=	SIBIT(4),

	/* nSTATUS is ip_b1, conf_done is ip_b0 in PIPR (hardware doc wrongly says ip_b2 and ip_b1) */

};
