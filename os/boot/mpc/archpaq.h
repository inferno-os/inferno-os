enum {
	/* memory controller CS assignment on PowerPAQ */
	BOOTCS = 0,
	DRAM1 = 1,	/* UPMB */
	DRAM2 = 2,	/* UPMB */
	/* CS3 also connected to DRAM */
	/* CS4 128mbyte 8-bit gpcm, trlx, 15 wait; it's DAC */
	/* CS5 is external*/
};

enum {
	/* I2C addresses */
	PanelI2C = 0x21<<1,
	  /* the control bits are active low enables, or high disables */
	  DisableVGA = ~0xFD,	/* disable VGA signals */
	  DisableTFT = ~0xFB,	/* disable TFT panel signals */
	  DisableSPIBus = ~0xF7,	/* disable SPI/I2C to panel */
	  DisablePanelVCC5 = ~0xEF,	/* disable +5V to panel(s) */
	  DisablePanelVCC3 = ~0xDF,	/* disable +3.3V to panel(s) */
	  DisableMonoPanel = ~0xBF,	/* disable mono panel signals */
	  DisableSPISelect = ~0x7F,	/* disable SPI chip select to LVDS panel */
	ContrastI2C = 0x2E<<1,
	LEDRegI2C = 0x20<<1,
	  DisableGreenLED = ~0xFE,
	  DisableYellowLED = ~0xFD,
	  DisableRedLED = ~0xFB,

	EnableLCD = IBIT(23),	/* LCD enable bit in i/o port B */
};
