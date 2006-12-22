#
# Copyright © 2002 Vita Nuova Holdings Limited.
#
implement UsbDriver;

include "sys.m";
	sys: Sys;
include "usb.m";
	usb: Usb;

readerpid: int;

kill(pid: int): int
{
	fd := sys->open("/prog/"+string pid+"/ctl", Sys->OWRITE);
	if (fd == nil)
		return -1;
	if (sys->write(fd, array of byte "kill", 4) != 4)
		return -1;
	return 0;
}

reader(pidc: chan of int, fd: ref Sys->FD)
{
	pid := sys->pctl(0, nil);
	pidc <-= pid;
	buf := array [4] of byte;
	while ((n := sys->read(fd, buf, len buf)) >= 0)
		sys->print("%d: %d\n", sys->millisec(), n);
	readerpid = -1;
}
	
init(usbmod: Usb, setupfd, ctlfd: ref Sys->FD,
	nil: ref Usb->Device,
	conf: array of ref Usb->Configuration, path: string): int
{
	usb = usbmod;
	sys = load Sys Sys->PATH;
	rv := usb->set_configuration(setupfd, conf[0].id);
	if (rv < 0)
		return rv;
	ep := (hd conf[0].iface[0].altiface).ep[0];
	sys->print("maxpkt %d interval %d\n", ep.maxpkt, ep.interval);
	rv = sys->fprint(ctlfd, "ep 1 %d r %d 32", ep.maxpkt, ep.interval);
	if (rv < 0)
		return rv;
	datafd := sys->open(path + "ep1data", Sys->OREAD);
	if (datafd == nil)
		return -1;
	pidc := chan of int;
	spawn reader(pidc, datafd);
	readerpid = <- pidc;
	return 0;
}

shutdown()
{
	if (readerpid >= 0)
		kill(readerpid);
}
