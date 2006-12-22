#
# Copyright © 2002 Vita Nuova Holdings Limited
#
implement UsbDriver;

# MCT RS232 USB driver
# 'Documentation' mined from NetBSD

include "sys.m";
	sys: Sys;
include "usb.m";
	usb: Usb;

UMCT_SET_REQUEST: con 1640;

REQ_SET_BAUD_RATE: con 5;
REQ_SET_LCR: con 7;

LCR_SET_BREAK: con 16r40;
LCR_PARITY_EVEN: con 16r18;
LCR_PARITY_ODD: con 16r08;
LCR_PARITY_NONE: con 16r00;
LCR_DATA_BITS_5, LCR_DATA_BITS_6, LCR_DATA_BITS_7, LCR_DATA_BITS_8: con iota;
LCR_STOP_BITS_2: con 16r04;
LCR_STOP_BITS_1: con 16r00;

setupfd: ref Sys->FD;
debug: con 1;

ioreaderpid, statusreaderpid: int;

kill(pid: int): int
{
	fd := sys->open("/prog/"+string pid+"/ctl", Sys->OWRITE);
	if (fd == nil)
		return -1;
	if (sys->write(fd, array of byte "kill", 4) != 4)
		return -1;
	return 0;
}

ioreader(pidc: chan of int, fd: ref Sys->FD)
{
	pid := sys->pctl(0, nil);
	pidc <-= pid;
	buf := array [256] of byte;
	while ((n := sys->read(fd, buf, len buf)) >= 0)
	{
		sys->print("[%d]\n", n);
		sys->write(sys->fildes(1), buf, n);
	}
	ioreaderpid = -1;
}

statusreader(pidc: chan of int, fd: ref Sys->FD)
{
	pid := sys->pctl(0, nil);
	pidc <-= pid;
	buf := array [2] of byte;
	while ((n := sys->read(fd, buf, len buf)) >= 0)
	{
		sys->print("S(%d)%.2ux%.2ux\n", n, int buf[0], int buf[1]);
	}
	statusreaderpid = -1;
}

set_baud_rate(baud: int)
{
	buf := array [1] of byte;
	val := 12;
	case baud {
	300 => val  = 1;
	1200 => val  = 3;
	2400 => val  = 4;
	4800 => val  = 6;
	9600 => val = 8;
	19200 => val = 9;
	38400 => val = 10;
	57600 => val = 11;
	115200 => val = 12;
	}
	buf[0] = byte val;
	if (usb->setup(setupfd, UMCT_SET_REQUEST, REQ_SET_BAUD_RATE, 0, 0, buf, nil) < 0) {
		if (debug)
			sys->print("usbmct: set_baud_rate failed\n");
	}
}

set_lcr(val: int)
{
	buf := array [1] of byte;
	buf[0] = byte val;
	if (usb->setup(setupfd, UMCT_SET_REQUEST, REQ_SET_LCR, 0, 0, buf, nil) < 0) {
		if (debug)
			sys->print("usbmct: set_lcr failed\n");
	}
}
	
init(usbmod: Usb, psetupfd, pctlfd: ref Sys->FD,
	dev: ref Usb->Device,
	conf: array of ref Usb->Configuration, path: string): int
{
	statusep, inep, outep: ref Usb->Endpt;
	usb = usbmod;
	sys = load Sys Sys->PATH;
	setupfd = psetupfd;
	# check the device descriptor to see if it really is an MCT doofer
	if (dev.vid != 16r0711 || dev.did != 16r0230) {
		if (debug)
			sys->print("usbmct: wrong device!\n");
		return -1;
	}
	usb->set_configuration(setupfd, conf[0].id);
	ai := hd conf[0].iface[0].altiface;
	statusep = nil;
	inep = nil;
	outep = nil;
	for (e := 0; e < len ai.ep; e++) {
		ep := ai.ep[e];
		if ((ep.addr & 16r80) != 0 && (ep.attr & 3) == 3 && ep.maxpkt == 2)
			statusep = ep;
		else if ((ep.addr & 16r80) != 0 && (ep.attr & 3) == 3)
			inep = ep;
		else if ((ep.addr & 16r80) == 0 && (ep.attr & 3) == 2)
			outep = ep;
	}
	if (statusep == nil || outep == nil || inep == nil) {
		if (debug)
			sys->print("usbmct: can't find sensible endpoints\n");
		return -1;
	}
	if ((inep.addr & 15) != (outep.addr & 15)) {
		if (debug)
			sys->print("usbmct: in and out endpoints not same number\n");
		return -1;
	}
	ioid := inep.addr & 15;
	statusid := statusep.addr & 15;
	if (debug)
		sys->print("ep %d %d r %d 32\n", ioid, inep.maxpkt, inep.interval);
	if (sys->fprint(pctlfd, "ep %d %d r %d 32", ioid, inep.maxpkt, inep.interval) < 0) {
		if (debug)
			sys->print("usbmct: can't create i/o endpoint (i)\n");
		return -1;
	}
#	if (debug)
#		sys->print("ep %d %d r bulk 32\n", ioid, inep.maxpkt);
#	if (sys->fprint(pctlfd, "ep %d %d r bulk 32", ioid, inep.maxpkt) < 0) {
#		if (debug)
#			sys->print("usbmct: can't create i/o endpoint (i)\n");
#		return -1;
#	}
	if (debug)
		sys->print("ep %d %d w bulk 8\n", ioid, outep.maxpkt);
	if (sys->fprint(pctlfd, "ep %d %d w bulk 8", ioid, outep.maxpkt) < 0) {
		if (debug)
			sys->print("usbmct: can't create i/o endpoint (o)\n");
		return -1;
	}
	iofd := sys->open(path + "ep" + string ioid + "data", Sys->ORDWR);
	if (iofd == nil) {
		if (debug)
			sys->print("usbmct: can't open i/o endpoint\n");
		return -1;
	}
	if (debug)
		sys->print("ep %d %d r %d 8\n", statusid, statusep.maxpkt, statusep.interval);
	if (sys->fprint(pctlfd, "ep %d %d r %d 8", statusid, statusep.maxpkt, statusep.interval) < 0) {
		if (debug)
			sys->print("usbmct: can't create status endpoint\n");
		return -1;
	}
	statusfd := sys->open(path + "ep" + string statusid + "data", Sys->ORDWR);
	if (statusfd == nil) {
		if (debug)
			sys->print("usbmct: can't open status endpoint\n");
		return -1;
	}
sys->print("setting baud rate\n");
	set_baud_rate(9600);
sys->print("setting lcr\n");
	set_lcr(LCR_PARITY_NONE | LCR_DATA_BITS_8 | LCR_STOP_BITS_1);
sys->print("launching reader\n");
	pidc := chan of int;
	spawn ioreader(pidc, iofd);
	ioreaderpid = <- pidc;
	spawn statusreader(pidc, statusfd);
	statusreaderpid = <- pidc;
	buf := array[512] of byte;
	for (x := 0; x < 512; x += 16) {
		buf[x:] = array of byte sys->sprint("%.2ux", x / 16);
		buf[x + 2:] = array of byte "-0123456789-\r\n";
	}
	sys->write(iofd, buf, 512);
	return 0;
}

shutdown()
{
	if (ioreaderpid >= 0)
		kill(ioreaderpid);
	if (statusreaderpid >= 0)
		kill(statusreaderpid);
}
