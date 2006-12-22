/*
 * iPAQ 36xx-specific definitions
 */

/*
 * GPIO assignment on iPAQ (see H3600 hardware spec).
 * Following Plan 9, _i is input signal, _o is output, _io is both.
 */
enum {
	GPIO_PWR_ON_i = 1<<0,	/* power on/off (active low)*/
	GPIO_UP_IRQ_i = 1<<1,	/* microcontroller interrupt (active low) */
	/* 2-9 are LCD 8-15 */
	GPIO_CARD_IND1_i = 1<<10,	/* PCMCIA/CF socket 1 card inserted (active low) */
	GPIO_CARD_IRQ1_i = 1<<11,	/* socket 1 IRQ (active low) */
	GPIO_CLK_SET0_o = 1<<12,		/* codec clock select 0 */
	GPIO_CLK_SET1_o = 1<<13,		/* codec clock select 1 */
	GPIO_L3_SDA_io = 1<<14,		/* L3 data to/from UDA1341 */
	GPIO_L3_MODE_o = 1<<15,		/* L3 mode to UDA1341 */
	GPIO_L3_SCLK_o = 1<<16,		/* L3 SCLK to UDA1341 */
	GPIO_CARD_IND0_i = 1<<17,		/* PCMCIA/CF socket 0 card inserted (active low) */
	GPIO_KEY_ACT_i = 1<<18,	/* joypad centre button (active low) */
	GPIO_SYS_CLK_i = 1<<19,	/* codec external clock */
	GPIO_BAT_FAULT_i = 1<<20,	/* battery fault (active high) */
	GPIO_CARD_IRQ0_i = 1<<21,	/* socket 0 IRQ (active low) */
	GPIO_LOCK_i = 1<<22,	/* expansion pack lock/unlock signal (active low) */
	GPIO_COM_DCD_i = 1<<23,	/* UART3 DCD from cradle (active high) */
	GPIO_OPT_IRQ_i = 1<<24,	/* expansion pack shared IRQ (all but PCMCIA/CF, active high) */
	GPIO_COM_CTS_i = 1<<25,	/* UART3 CTS (active high) */
	GPIO_COM_RTS_o = 1<<26,	/* UART3 RTS (active high) */
	GPIO_OPT_IND_i = 1<<27,	/* expansion pack inserted (active low) */
};

/* special EGPIO register, write only*/
enum {
	EGPIO_VPEN = 1<<0,	/* flash write enable */
	EGPIO_CARD_RESET = 1<<1,	/* CF/PCMCIA reset signal */
	EGPIO_OPT_RESET = 1<<2,	/* expansion pack reset for other than CF/PCMCIA */
	EGPIO_CODEC_RESET = 1<<3,	/* codec reset signal (active low) */
	EGPIO_OPT_PWR_ON = 1<<4,	/* enable power to NVRAM in expansion pack */
	EGPIO_OPT_ON = 1<<5,	/* enable full power to expansion pack */
	EGPIO_LCD_ON = 1<<6,	/* enable LCD 3.3v supply */
	EGPIO_RS232_ON = 1<<7,	/* enable RS232 transceiver */
	EGPIO_LCD_PCI = 1<<8,	/* enable power to LCD control IC */
	EGPIO_IR_ON = 1<<9,	/* enable power to IR module */
	EGPIO_AUD_ON = 1<<10,	/* enable power to audio amp */
	EGPIO_AUD_PWR_ON = 1<<11,	/* enable power to all other audio circuitry */
	EGPIO_QMUTE = 1<<12,	/* mute audio codec (nb: wastes power if set when audio not powered) */
	EGPIO_IR_FSEL = 1<<13,	/* FIR mode selection: 1=FIR, 0=SIR */
	EGPIO_LCD_5V_ON = 1<<14,	/* enable 5V to LCD module */
	EGPIO_LVDD_ON = 1<<15,	/* enable 9V and -6.5V to LCD module */
};

/* board-dependent GPIO pin assignment for l3gpio.c */
enum {
	L3Data = GPIO_L3_SDA_io,
	L3Mode = GPIO_L3_MODE_o,
	L3Clock = GPIO_L3_SCLK_o,
};

#include "../sa1110/sa1110io.h"
