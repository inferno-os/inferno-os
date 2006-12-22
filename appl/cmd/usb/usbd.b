implement Usbd;

include "sys.m";
	sys: Sys;
include "draw.m";
include "string.m";
	str: String;
include "lock.m";
	lock: Lock;
	Semaphore: import lock;
include "arg.m";
	arg: Arg;

include "usb.m";
	usb: Usb;
	Device, Configuration, Endpt: import Usb;
include "bufio.m";
	bufio: Bufio;
	Iobuf: import bufio;

Detached, Attached, Enabled, Assigned, Configured: con (iota);

Usbd: module
{
	init: fn(nil: ref Draw->Context, args: list of string);
};

Hub: adt {
	nport, pwrmode, compound, pwrms, maxcurrent, removable, pwrctl: int;
	ports: cyclic ref DDevice;
};
	
DDevice: adt {
	port: int;
	pids: list of int;
	parent: cyclic ref DDevice;
	next: cyclic ref DDevice;
	cfd, setupfd, rawfd: ref Sys->FD;
	id: int;
	ls: int;
	state: int;
	ep: array of ref Endpt;
	config: array of ref Usb->Configuration;
	hub: Hub;
	mod: UsbDriver;
	d: ref Device;
};

Line: adt {
	level: int;
	command: string;
	value: int;
	svalue: string;
};

ENUMERATE_POLL_INTERVAL: con 1000;
FAILED_ENUMERATE_RETRY_INTERVAL: con 10000;

verbose: int;
debug: int;
stderr: ref Sys->FD;

usbportfd: ref Sys->FD;
usbctlfd: ref Sys->FD;
usbctl0: ref Sys->FD;
usbsetup0: ref Sys->FD;

usbbase: string;

configsema, setupsema, treesema: ref Semaphore;


# UHCI style status which is returned by the driver.
UHCIstatus_Suspend: con 1 << 12;
UHCIstatus_PortReset: con 1 << 9;
UHCIstatus_SlowDevice: con 1 << 8;
UHCIstatus_ResumeDetect: con 1 << 6;
UHCIstatus_PortEnableChange: con 1 << 3;   
UHCIstatus_PortEnable: con 1 << 2;
UHCIstatus_ConnectStatusChange: con 1 << 1;	
UHCIstatus_DevicePresent: con 1 << 0;

obt()
{
#	sys->fprint(stderr, "%d waiting\n", sys->pctl(0, nil));
	setupsema.obtain();
#	sys->fprint(stderr, "%d got\n", sys->pctl(0, nil));
}

rel()
{
#	sys->fprint(stderr, "%d releasing\n", sys->pctl(0, nil));
	setupsema.release();
}

hubid(hub: ref DDevice): int
{
	if (hub == nil)
		return 0;
	return hub.id;
}

hubfeature(d: ref DDevice, p: int, feature: int, on: int): int
{
	rtyp: int;
	if (p == 0)
		rtyp = Usb->Rclass;
	else
		rtyp = Usb->Rclass | Usb->Rother;
	obt();
	rv := usb->setclear_feature(d.setupfd, rtyp, feature, p, on);
	rel();
	return rv;
}

portpower(hub: ref DDevice, port: int, on: int)
{
	if (verbose)
		sys->fprint(stderr, "portpower %d/%d %d\n", hubid(hub), port, on);
	if (hub == nil)
		return;
	if (port)
		hubfeature(hub, port, Usb->PORT_POWER, on);
}

countrootports(): int
{
	sys->seek(usbportfd, big 0, Sys->SEEKSTART);
	buf := array [256] of byte;
	n := sys->read(usbportfd, buf, len buf);
	if (n <= 0) {
		sys->fprint(stderr, "usbd: countrootports: error reading root port status\n");
		exit;
	}
	(nv, nil) := sys->tokenize(string buf[0: n], "\n");
	if (nv < 1) {
		sys->fprint(stderr, "usbd: countrootports: strange root port status\n");
		exit;
	}
	return nv;
}

portstatus(hub: ref DDevice, port: int): int
{
	rv: int;
#	setupsema.obtain();
	obt();
	if (hub == nil) {
		sys->seek(usbportfd, big 0, Sys->SEEKSTART);
		buf := array [256] of byte;
		n := sys->read(usbportfd, buf, len buf);
		if (n < 1) {
			sys->fprint(stderr, "usbd: portstatus: read error\n");
			rel();
			return 0;
		}
		(nil, l) := sys->tokenize(string buf[0: n], "\n");
		for(; l != nil; l = tl l){
			(nv, f) := sys->tokenize(hd l, " ");
			if(nv < 2){
				sys->fprint(stderr, "usbd: portstatus: odd status line\n");
				rel();
				return 0;
			}
			if(int hd f == port){
				(rv, nil) = usb->strtol(hd tl f, 16);
				# the status change bits are not used so mask them off
				rv &= 16rffff;
				break;
			}
		}
		if (l == nil) {
			sys->fprint(stderr, "usbd: portstatus: no status for port %d\n", port);
			rel();
			return 0;
		}
	}
	else
		rv = usb->get_status(hub.setupfd, port);
#	setupsema.release();
	rel();
	if (rv < 0)
		return 0;
	return rv;
}

portenable(hub: ref DDevice, port: int, enable: int)
{
	if (verbose)
		sys->fprint(stderr, "portenable %d/%d %d\n", hubid(hub), port, enable);
	if (hub == nil) {
		if (enable)
			sys->fprint(usbctlfd, "enable %d", port);
		else
			sys->fprint(usbctlfd, "disable %d", port);
		return;
	}
	if (port)
		hubfeature(hub, port, Usb->PORT_ENABLE, enable);
}

portreset(hub: ref DDevice, port: int)
{
	if (verbose)
		sys->fprint(stderr, "portreset %d/%d\n", hubid(hub), port);
	if (hub == nil) {
		if(0)sys->fprint(usbctlfd, "reset %d", port);
		for (i := 0; i < 4; ++i) {
	  		sys->sleep(20);			# min 10 milli second reset recovery.
	  		s := portstatus(hub, port);
	  		if ((s & UHCIstatus_PortReset) == 0)		# only leave when reset is finished.
				break;
		}
		return;
	}
	if (port)
		hubfeature(hub, port, Usb->PORT_RESET, 1);
	return;
}

devspeed(d: ref DDevice)
{
	sys->fprint(d.cfd, "speed %d", !d.ls);
	if (debug) {
		s: string;
		if (d.ls)
			s = "low";
		else
			s = "high";
		sys->fprint(stderr, "%d: set speed %s\n", d.id, s);
	}
}

devmaxpkt0(d: ref DDevice, size: int)
{
	sys->fprint(d.cfd, "maxpkt 0 %d", size);
	if (debug)
		sys->fprint(stderr, "%d: set maxpkt0 %d\n", d.id, size);
}

closedev(d: ref DDevice)
{
	d.cfd = usbctl0;
	d.rawfd = nil;
	d.setupfd = usbsetup0;
}

openusb(f: string, mode: int): ref Sys->FD
{
	fd := sys->open(usbbase + f, mode);
	if (fd == nil) {
		sys->fprint(stderr, "usbd: can't open %s: %r\n", usbbase + f);
		raise "fail:open";
	}
	return fd;
}

opendevf(id: int, f: string, mode: int): ref Sys->FD
{
	fd := sys->open(usbbase + string id + "/" + f, mode);
	if (fd == nil) {
		sys->fprint(stderr, "usbd: can't open %s: %r\n", usbbase + string id + "/" + f);
		exit;
	}
	return fd;
}

kill(pid: int): int
{
	if (debug)
		sys->print("killing %d\n", pid);
	fd := sys->open("#p/"+string pid+"/ctl", Sys->OWRITE);
	if (fd == nil) {
		sys->print("kill: open failed\n");
		return -1;
	}
	if (sys->write(fd, array of byte "kill", 4) != 4) {
		sys->print("kill: write failed\n");
		return -1;
	}
	return 0;
}

rdetach(d: ref DDevice)
{
	if (d.mod != nil) {
		d.mod->shutdown();
		d.mod = nil;
	}
	while (d.pids != nil) {
		if (verbose)
			sys->fprint(stderr, "kill %d\n", hd d.pids);
		kill(hd d.pids);
		d.pids = tl d.pids;
	}
	if (d.parent != nil) {
		last, hp: ref DDevice;
		last = nil;
		hp = d.parent.hub.ports;
		while (hp != nil && hp != d)
			hp = hp.next;
		if (last != nil)
			last.next = d.next;
		else
			d.parent.hub.ports = d.next;
	}
	if (d.hub.ports != nil) {
		for (c := d.hub.ports; c != nil; c = c.next) {
			c.parent = nil;
			rdetach(c);
		}
	}
	d.state = Detached;
	if (sys->fprint(d.cfd, "detach") < 0)
		sys->fprint(stderr, "detach failed\n");
	d.cfd = nil;
	d.rawfd = nil;
	d.setupfd = nil;
}

detach(d: ref DDevice)
{
	configsema.obtain();
	treesema.obtain();
	obt();
#	setupsema.obtain();

	if (verbose)
		sys->fprint(stderr, "detach %d\n", d.id);
	rdetach(d);
	if (verbose)
		sys->fprint(stderr, "detach %d done\n", d.id);
#	setupsema.release();
	rel();
	treesema.release();
	configsema.release();
}

readnum(fd: ref Sys->FD): int
{
	buf := array [16] of byte;
	n := sys->read(fd, buf, len buf);
	if (n <= 0)
		return -1;
	(rv , nil) := usb->strtol(string buf[0: n], 0);
	return rv;
}

setaddress(d: ref DDevice): int
{
	if (d.state == Assigned)
		return d.id;
	closedev(d);
	d.id = 0;
	d.cfd = openusb("new", Sys->ORDWR);
	id := readnum(d.cfd);
	if (id <= 0) {
		if (debug)
			sys->fprint(stderr, "usbd: usb/new ID: %r\n");
		d.cfd = nil;
		return -1;
	}
#	setupsema.obtain();
	obt();
	if (usb->set_address(d.setupfd, id) < 0) {
#		setupsema.release();
		rel();
		return -1;
	}
#	setupsema.release();
	rel();
	d.id = id;
	d.state = Assigned;
	return id;
}

#optstring(d: ref DDevice, langids: list of int, desc: string, index: int)
#{
#	if (index) {
#		buf := array [256] of byte;
#		while (langids != nil) {
#			nr := usb->get_descriptor(d.setupfd, Usb->Rstandard, Usb->STRING, index, hd langids, buf);
#			if (nr > 2) {
#				sys->fprint(stderr, "%s: ", desc);
#				usbdump->desc(d, -1, buf[0: nr]);
#			}
#			langids = tl langids;
#		}
#	}
#}

langid(d: ref DDevice): (list of int)
{
	l: list of int;
	buf := array [256] of byte;
	nr := usb->get_standard_descriptor(d.setupfd, Usb->STRING, 0, buf);
	if (nr < 4)
		return nil;
	if (nr & 1)
		nr--;
	l = nil;
	for (i := nr - 2; i >= 2; i -= 2)
		l = usb->get2(buf[i:]) :: l;
	return l;
}

describedevice(d: ref DDevice): int
{
	obt();
	devmaxpkt0(d, 64);				# guess 64 byte max packet to avoid overrun on read
	for (x := 0; x < 3; x++) {			# retry 3 times
		d.d = usb->get_parsed_device_descriptor(d.setupfd);
		if (d.d != nil)
			break;
		sys->sleep(200);			# tolerate out of spec. devices
	}

	if (d.d == nil) {
		rel();
		return -1;
	}

	if (d.d.maxpkt0 != 64) {
		devmaxpkt0(d, d.d.maxpkt0);
		d.d = usb->get_parsed_device_descriptor(d.setupfd);
		if (d.d == nil) {
			rel();
			return -1;
		}
	}

	rel();

	if (verbose) {
		sys->fprint(stderr, "usb %x.%x", d.d.usbmajor, d.d.usbminor);
		sys->fprint(stderr, " class %d subclass %d proto %d [%s] max0 %d",
			d.d.class, d.d.subclass, d.d.proto,
			usb->sclass(d.d.class, d.d.subclass, d.d.proto), d.d.maxpkt0);
		sys->fprint(stderr, " vendor 0x%.4x product 0x%.4x rel %x.%x",
			d.d.vid, d.d.did, d.d.relmajor, d.d.relminor);
		sys->fprint(stderr, " nconf %d", d.d.nconf);
		sys->fprint(stderr, "\n");
		obt();
		l := langid(d);
		if (l != nil) {
			l2 := l;
			sys->fprint(stderr, "langids [");
			while (l2 != nil) {
				sys->fprint(stderr, " %d", hd l2);
				l2 = tl l2;
			}
			sys->fprint(stderr, "]\n");
		}
#		optstring(d, l, "manufacturer", int buf[14]);
#		optstring(d, l, "product", int buf[15]);
#		optstring(d, l, "serial number", int buf[16]);
		rel();
	}
	return 0;
}

describehub(d: ref DDevice): int
{
	b := array [256] of byte;
#	setupsema.obtain();
	obt();
	nr := usb->get_class_descriptor(d.setupfd, 0, 0, b);
	if (nr < Usb->DHUBLEN) {
#		setupsema.release();
		rel();
		sys->fprint(stderr, "usbd: error reading hub descriptor: got %d of %d\n", nr, Usb->DHUBLEN);
		return -1;
	}
#	setupsema.release();
	rel();
	if (verbose)
		sys->fprint(stderr, "nport %d charac 0x%.4ux pwr %dms current %dmA remov 0x%.2ux pwrctl 0x%.2ux",
			int b[2], usb->get2(b[3:]), int b[5] * 2, int b[6] * 2, int b[7], int b[8]);
	d.hub.nport = int b[2];
	d.hub.pwrms = int b[5] * 2;
	d.hub.maxcurrent = int b[6] * 2;
	char := usb->get2(b[3:]);
	d.hub.pwrmode = char & 3;
	d.hub.compound = (char & 4) != 0;
	d.hub.removable = int b[7];
	d.hub.pwrctl = int b[8];
	return 0;
}

loadconfig(d: ref DDevice, n: int): int
{
	obt();
	d.config[n] = usb->get_parsed_configuration_descriptor(d.setupfd, n);
	if (d.config[n] == nil) {
		rel();
		sys->fprint(stderr, "usbd: error reading configuration descriptor\n");
		return -1;
	}
	rel();
	if (verbose)
		usb->dump_configuration(stderr, d.config[n]);
	return 0;
}

#setdevclass(d: ref DDevice, n: int)
#{
#	dd := d.config[n];
#	if (dd != nil)
#		sys->fprint(d.cfd, "class %d %d %d %d %d", d.d.nconf, n, dd.class, dd.subclass, dd.proto);
#}

setconfig(d: ref DDevice, n: int): int
{
	obt();
	rv := usb->set_configuration(d.setupfd, n);
	rel();
	if (rv < 0)
		return -1;
	d.state = Configured;
	return 0;
}

configure(hub: ref DDevice, port: int): ref DDevice
{
	configsema.obtain();
	portreset(hub, port);
	sys->sleep(300);				# long sleep necessary for strange hardware....
#	sys->sleep(20);
	s := portstatus(hub, port);
	s = portstatus(hub, port);

	if (debug)
		sys->fprint(stderr, "port %d status 0x%ux\n", port, s);

	if ((s & UHCIstatus_DevicePresent) == 0) {
		configsema.release();
		return nil;
	}

	if ((s & UHCIstatus_PortEnable) == 0) {
		if (debug)
			sys->fprint(stderr, "hack: re-enabling port %d\n", port);
		portenable(hub, port, 1);
		s = portstatus(hub, port);
		if (debug)
			sys->fprint(stderr, "port %d status now 0x%.ux\n", port, s);
	}

	d := ref DDevice;
	d.port = port;
	d.cfd = usbctl0;
	d.setupfd = usbsetup0;
	d.id = 0;
	if (hub == nil)
		d.ls = (s & UHCIstatus_SlowDevice) != 0;
	else
		d.ls = (s & (1 << 9)) != 0;
	d.state = Enabled;
	devspeed(d);
	if (describedevice(d) < 0) {
		portenable(hub, port, 0);
		configsema.release();
		return nil;
	}
	if (setaddress(d) < 0) {
		portenable(hub, port, 0);
		configsema.release();
		return nil;
	}
	d.setupfd = opendevf(d.id, "setup", Sys->ORDWR);
	d.cfd = opendevf(d.id, "ctl", Sys->ORDWR);
	devspeed(d);
	devmaxpkt0(d, d.d.maxpkt0);
	d.config = array [d.d.nconf] of ref Configuration;
	for (i := 0; i < d.d.nconf; i++) {
		loadconfig(d, i);
#		setdevclass(d, i);
	}
	if (hub != nil) {
		treesema.obtain();
		d.parent = hub;
		d.next = hub.hub.ports;
		hub.hub.ports = d;
		treesema.release();
	}
	configsema.release();
	return d;
}

enumerate(hub: ref DDevice, port: int)
{
	if (hub != nil)
		hub.pids = sys->pctl(0, nil) :: hub.pids;
	reenumerate := 0;
	for (;;) {
		if (verbose)
			sys->fprint(stderr, "enumerate: starting\n");
		if ((portstatus(hub, port) & UHCIstatus_DevicePresent) == 0) {
			if (verbose)
				sys->fprint(stderr, "%d: port %d empty\n", hubid(hub), port);
			do {
				sys->sleep(ENUMERATE_POLL_INTERVAL);
			} while ((portstatus(hub, port) & UHCIstatus_DevicePresent) == 0);
		}
		if (verbose)
			sys->fprint(stderr, "%d: port %d attached\n", hubid(hub), port);
		# Δt3 (TATTDB) guarantee 100ms after attach detected
		sys->sleep(200);
		d := configure(hub, port);
		if (d == nil) {
			if (verbose)
				sys->fprint(stderr, "%d: can't configure port %d\n", hubid(hub), port);
		}
		else if (d.d.class == Usb->CL_HUB) {
			i: int;
			if (setconfig(d, 1) < 0) {
				if (verbose)
					sys->fprint(stderr, "%d: can't set configuration for hub on port %d\n", hubid(hub), port);
				detach(d);
				d = nil;
			}
			else if (describehub(d) < 0) {
				if (verbose)
					sys->fprint(stderr, "%d: failed to describe hub on port %d\n", hubid(hub), port);
				detach(d);
				d = nil;
			}
			else {
				for (i = 1; i <= d.hub.nport; i++)
					portpower(d, i, 1);
				sys->sleep(d.hub.pwrms);
				for (i = 1; i <= d.hub.nport; i++)
					spawn enumerate(d, i);
			}
		}
		else if (d.d.nconf >= 1 && (path := searchdriverdatabase(d.d, d.config[0])) != nil) {
			d.mod = load UsbDriver path;
			if (d.mod == nil)
				sys->fprint(stderr, "usbd: failed to load %s\n", path);
			else {
				rv := d.mod->init(usb, d.setupfd, d.cfd, d.d, d.config, usbbase + string d.id + "/");
				if (rv == -11) {
					sys->fprint(stderr, "usbd: %s: reenumerate\n", path);
					d.mod = nil;
					reenumerate = 1;
				}	
				else if (rv < 0) {
					sys->fprint(stderr, "usbd: %s:init failed\n", path);
					d.mod = nil;
				}
				else if (verbose)
					sys->fprint(stderr, "%s running\n", path);
			}
		}
		else if (setconfig(d, 1) < 0) {
			if (verbose)
				sys->fprint(stderr, "%d: can't set configuration for port %d\n", hubid(hub), port);
			detach(d);
			d = nil;
		}
		if (!reenumerate) {
			if (d != nil) {
				# wait for it to be unplugged
				while (portstatus(hub, port) & UHCIstatus_DevicePresent)
					sys->sleep(ENUMERATE_POLL_INTERVAL);
			}
			else {
				# wait a bit and prod it again
				if (portstatus(hub, port) & UHCIstatus_DevicePresent)
					sys->sleep(FAILED_ENUMERATE_RETRY_INTERVAL);
			}
		}
		if (d != nil) {
			detach(d);
			d = nil;
		}
		reenumerate = 0;
	}
}

lines: array of Line;

searchdriverdatabase(d: ref Device, conf: ref Configuration): string
{
	backtracking := 0;
	level := 0;
	for (i := 0; i < len lines; i++) {
		if (verbose > 1)
			sys->fprint(stderr, "search line %d: lvl %d cmd %s val %d (back %d lvl %d)\n",
				i, lines[i].level, lines[i].command, lines[i].value, backtracking, level);
		if (backtracking) {
			if (lines[i].level > level)
				continue;
			backtracking = 0;
		}
		if (lines[i].level != level) {
			level = 0;
			backtracking = 1;
		}
		case lines[i].command {
		"class" =>
			if (d.class != 0) {
				if (lines[i].value != d.class)
					backtracking = 1;
			}
			else if (lines[i].value != (hd conf.iface[0].altiface).class)
				backtracking = 1;
		"subclass" =>
			if (d.class != 0) {
				if (lines[i].value != d.subclass)
					backtracking = 1;
			}
			else if (lines[i].value != (hd conf.iface[0].altiface).subclass)
				backtracking = 1;
		"proto" =>
			if (d.class != 0) {
				if (lines[i].value != d.proto)
					backtracking = 1;
			}
			else if (lines[i].value != (hd conf.iface[0].altiface).proto)
				backtracking = 1;
		"vendor" =>
			if (lines[i].value != d.vid)
				backtracking  =1;
		"product" =>
			if (lines[i].value != d.did)
				backtracking  =1;
		"load" =>
			return lines[i].svalue;
		* =>
			continue;
		}
		if (!backtracking)
			level++;
	}
	return nil;
}

loaddriverdatabase()
{
	newlines: array of Line;

	if (bufio == nil)
		bufio = load Bufio Bufio->PATH;

	iob := bufio->open(Usb->DATABASEPATH, Sys->OREAD);
	if (iob == nil) {
		sys->fprint(stderr, "usbd: couldn't open %s: %r\n", Usb->DATABASEPATH);
		return;
	}
	lines = array[100] of Line;
	lc := 0;
	while ((line := iob.gets('\n')) != nil) {
		if (line[0] == '#')
			continue;
		level := 0;
		while (line[0] == '\t') {
			level++;
			line = line[1:];
		}
		(n, l) := sys->tokenize(line[0: len line - 1], "\t ");
		if (n != 2)
			continue;
		if (lc >= len lines) {
			newlines = array [len lines * 2] of Line;
			newlines[0:] = lines[0: len lines];
			lines = newlines;
		}
		lines[lc].level = level;
		lines[lc].command = hd l;
		case hd l {
		"class" or "subclass" or "proto" or "vendor" or "product" =>
			(lines[lc].value, nil) = usb->strtol(hd tl l, 0);
		"load" =>
			lines[lc].svalue = hd tl l;
		* =>
			continue;
		}
		lc++;
	}
	if (verbose)
		sys->fprint(stderr, "usbd: loaded %d lines\n", lc);
	newlines = array [lc] of Line;
	newlines[0:] = lines[0 : lc];
	lines = newlines;
}

init(nil: ref Draw->Context, args: list of string)
{
	usbbase = "/dev/usbh/";
	sys = load Sys Sys->PATH;
	str = load String String->PATH;

	lock = load Lock Lock->PATH;
	lock->init();

	usb = load Usb Usb->PATH;
	usb->init();

	arg = load Arg Arg->PATH;

	stderr = sys->fildes(2);

	verbose = 0;
	debug = 0;

	arg->init(args);
	arg->setusage("usbd [-dv] [-i interface]");
	while ((c := arg->opt()) != 0)
		case c {
		'v' => verbose = 1;
		'd' => debug = 1;
		'i' => usbbase = arg->earg() + "/";
		* => arg->usage();
		}
	args = arg->argv();

	usbportfd = openusb("port", Sys->OREAD);
	usbctlfd = sys->open(usbbase + "ctl", Sys->OWRITE);
	if(usbctlfd == nil)
		usbctlfd = openusb("port", Sys->OWRITE);
	usbctl0 = opendevf(0, "ctl", Sys->ORDWR);
	usbsetup0 = opendevf(0, "setup", Sys->ORDWR);
	setupsema = Semaphore.new();
	configsema = Semaphore.new();
	treesema = Semaphore.new();
	loaddriverdatabase();
	ports := countrootports();
	if (verbose)
		sys->print("%d root ports found\n", ports);
	for (p := 2; p <= ports; p++)
		spawn enumerate(nil, p);
	if (p >= 1)
		enumerate(nil, 1);
}
