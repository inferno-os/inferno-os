/*
 * L3 emulation using GPIO pins
 *
 * from the Linux sa1100-uda1341.c,
 * Copyright (c) 2000 Nicolas Pitre <nico@cam.org>
 * Portions are Copyright (C) 2000 Lernout & Hauspie Speech Products, N.V.
 *
 * This program is free software; you can redistribute it and/or 
 * modify it under the terms of the GNU General Public License.
 *
 * Modified by Vita Nuova 2001
 *
 */
#include	"u.h"
#include	"../port/lib.h"
#include	"mem.h"
#include	"dat.h"
#include	"fns.h"
#include	"../port/error.h"
#include	"io.h"

/*
 * GPIO based L3 bus support.
 *
 * This provides control of Philips L3 type devices. 
 * GPIO lines are used for clock, data and mode pins.
 *
 * Note: The L3 pins are shared with I2C devices. This should not present
 * any problems as long as an I2C start sequence is not generated. This is
 * defined as a 1->0 transition on the data lines when the clock is high.
 * It is critical this code only allow data transitions when the clock
 * is low. This is always legal in L3.
 *
 * The IIC interface requires the clock and data pin to be LOW when idle. We
 * must make sure we leave them in this state.
 *
 * It appears the read data is generated on the falling edge of the clock
 * and should be held stable during the clock high time.
 */

/* 
 * L3 setup and hold times (expressed in us)
 */
enum {
	L3DataSetupTime = 1, /* 190 ns */
	L3DataHoldTime = 1, /*  30 ns */
	L3ModeSetupTime = 1, /* 190 ns */
	L3ModeHoldTime = 1, /* 190 ns */
	L3ClockHighTime = 1, /* 250 ns (min is 64*fs, 35us @ 44.1 Khz) */
	L3ClockLowTime = 1, /* 250 ns (min is 64*fs, 35us @ 44.1 Khz) */
	L3HaltTime = 1, /* 190 ns */
};

/*
 * Grab control of the IIC/L3 shared pins
 */
static void
L3acquirepins(void)
{
	GpioReg *g = GPIOREG;
	int s;

	s = splhi();
	g->gpsr = (L3Mode | L3Clock | L3Data);
	g->gpdr |=  (L3Mode | L3Clock | L3Data);
	splx(s);
//	microdelay(2);
}

/*
 * Release control of the IIC/L3 shared pins
 */
static void
L3releasepins(void)
{
	GpioReg *g = GPIOREG;
	int s;

	s = splhi();
	g->gpdr &= ~(L3Mode | L3Clock | L3Data);
	splx(s);
}

/*
 * Initialize the interface
 */
void
L3init(void)
{
	GpioReg *g = GPIOREG;
	int s;

	s = splhi();
	g->gafr &= ~(L3Data | L3Clock | L3Mode);
	splx(s);
	L3releasepins();
}

/*
 * Send a byte. The mode line is set or pulsed based on the mode sequence
 * count. The mode line is high on entry and exit. The mod line is pulsed
 * before the second data byte and before ech byte thereafter.
 */
static void
L3sendbyte(int data, int mode)
{
	int i;
	GpioReg *g = GPIOREG;

	switch(mode) {
	case 0: /* Address mode */
		g->gpcr = L3Mode;
		break;
	case 1: /* First data byte */
		break;
	default: /* Subsequent bytes */
		g->gpcr = L3Mode;
		microdelay(L3HaltTime);
		g->gpsr = L3Mode;
		break;
	}

	microdelay(L3ModeSetupTime);

	for (i = 0; i < 8; i++){
		microdelay(2);
		/*
		 * Send a bit. The clock is high on entry and on exit. Data is sent only
		 * when the clock is low (I2C compatibility).
		 */
		g->gpcr = L3Clock;

		if (data & (1<<i))
			g->gpsr = L3Data;
		else
			g->gpcr = L3Data;

		/* Assumes L3DataSetupTime < L3ClockLowTime */
		microdelay(L3ClockLowTime);

		g->gpsr = L3Clock;
		microdelay(L3ClockHighTime);
	}

	if (mode == 0)  /* Address mode */
		g->gpsr = L3Mode;

	microdelay(L3ModeHoldTime);

}

/*
 * Get a byte. The mode line is set or pulsed based on the mode sequence
 * count. The mode line is high on entry and exit. The mod line is pulsed
 * before the second data byte and before each byte thereafter. This
 * function is never valid with mode == 0 (address cycle) as the address
 * is always sent on the bus, not read.
 */
static int
L3getbyte(int mode)
{
	int data = 0;
	int i;
	GpioReg *g = GPIOREG;

	switch(mode) {
	case 0: /* Address mode - never valid */
		break;
	case 1: /* First data byte */
		break;
	default: /* Subsequent bytes */
		g->gpcr = L3Mode;
		microdelay(L3HaltTime);
		g->gpsr = L3Mode;
		break;
	}

	microdelay(L3ModeSetupTime);

	for (i = 0; i < 8; i++){
		/*
		 * Get a bit. The clock is high on entry and on exit. Data is read after
		 * the clock low time has expired.
		 */
		g->gpcr = L3Clock;
		microdelay(L3ClockLowTime);

		if(g->gplr & L3Data)
			data |= 1<<i;

	 	g->gpsr = L3Clock;
		microdelay(L3ClockHighTime);
	}

	microdelay(L3ModeHoldTime);

	return data;
}

/*
 * Write data to a device on the L3 bus. The address is passed as well as
 * the data and length. The length written is returned. The register space
 * is encoded in the address (low two bits are set and device address is
 * in the upper 6 bits).
 */
int
L3write(int addr, void *data, int len)
{
	int mode = 0;
	int bytes = len;
	uchar *b;

	L3acquirepins();
	L3sendbyte(addr, mode++);
	for(b = data; --len >= 0;)
		L3sendbyte(*b++, mode++);
	L3releasepins();

	return bytes;
}

/*
 * Read data from a device on the L3 bus. The address is passed as well as
 * the data and length. The length read is returned. The register space
 * is encoded in the address (low two bits are set and device address is
 * in the upper 6 bits).
 */
int
L3read(int addr, void *data, int len)
{
	int mode = 0;
	int bytes = len;
	uchar *b;
	int s;

	L3acquirepins();
	L3sendbyte(addr, mode++);
	s = splhi();
	GPIOREG->gpdr &= ~(L3Data);
	splx(s);
	for(b = data; --len >= 0;)
		*b++ = L3getbyte(mode++);
	L3releasepins();

	return bytes;
}
