Usb: module
{
	PATH: con "/dis/lib/usb/usb.dis";
	DATABASEPATH: con "/lib/usbdb";
	RH2D: con 0<<7;
	RD2H: con 1<<7;
	Rstandard: con 0<<5;
	Rclass: con 1<<5;
	Rvendor: con 2<<5;
	Rdevice: con 0;
	Rinterface: con 1;
	Rendpt: con 2;
	Rother: con 3;
	
	GET_STATUS: con 0;
	CLEAR_FEATURE: con 1;
	SET_FEATURE: con 3;
	SET_ADDRESS: con 5;
	GET_DESCRIPTOR: con 6;
	SET_DESCRIPTOR: con 7;
	GET_CONFIGURATION: con 8;
	SET_CONFIGURATION: con 9;
	GET_INTERFACE: con 10;
	SET_INTERFACE: con 11;
	SYNCH_FRAME: con 12;
	
	DEVICE: con 1;
	CONFIGURATION: con 2;
	STRING: con 3;
	INTERFACE: con 4;
	ENDPOINT: con 5;
	HID: con 16r21;
	REPORT: con 16r22;
	PHYSICAL: con 16r23;
	HUB: con 16r29;

	CL_AUDIO: con 1;
	CL_COMMS: con 2;
	CL_HID: con 3;
	CL_PRINTER: con 7;
	CL_MASS: con 8;
	CL_HUB: con 9;
	CL_DATA: con 10;

	DDEVLEN: con 18;
	DCONFLEN: con 9;
	DINTERLEN: con 9;
	DENDPLEN: con 7;
	DHUBLEN: con 9;
	DHIDLEN: con 9;

	PORT_CONNECTION: con 0;
	PORT_ENABLE: con 1;
	PORT_SUSPEND: con 2;
	PORT_OVER_CURRENT: con 3;
	PORT_RESET: con 4;
	PORT_POWER: con 8;
	PORT_LOW_SPEED: con 9;

	Endpt: adt {
		addr: int;
		d2h:	int;
		attr:	int;
		etype:	int;
		isotype:	int;
		maxpkt: int;
		interval: int;
	};

	Econtrol, Eiso, Ebulk, Eintr: con iota;	# Endpt.etype
	Eunknown, Easync, Eadapt, Esync: con iota;	# Endpt.isotype
	
	NendPt: con 16;
	
	Device: adt {
		usbmajor, usbminor, relmajor, relminor: int;
		class, subclass, proto, maxpkt0, vid, did, nconf: int;
	};

	AltInterface: adt {
		id: int;
		class, subclass, proto: int;
		ep: array of ref Endpt;
	};

	Interface: adt {
		altiface: list of ref AltInterface;
	};

	Configuration: adt {
		id: int;
		attr: int;
		powerma: int;
		iface: array of Interface;
	};

	init: fn();
	get2: fn(b: array of byte): int;
	put2: fn(buf: array of byte, v: int);
	get4: fn(b: array of byte): int;
	put4: fn(buf: array of byte, v: int);
	bigget2: fn(b: array of byte): int;
	bigput2: fn(buf: array of byte, v: int);
	bigget4: fn(b: array of byte): int;
	bigput4: fn(buf: array of byte, v: int);
	memset: fn(b: array of byte, v: int);
	strtol: fn(s: string, base: int): (int, string);
	sclass: fn(class, subclass, proto: int): string;
	
	get_descriptor: fn(fd: ref Sys->FD, rtyp: int, dtyp: int, dindex: int, langid: int, buf: array of byte): int;
	get_standard_descriptor: fn(fd: ref Sys->FD, dtyp: int, index: int, buf: array of byte): int;
	get_class_descriptor: fn(fd: ref Sys->FD, dtyp: int, index: int, buf: array of byte): int;
	get_vendor_descriptor: fn(fd: ref Sys->FD, dtyp: int, index: int, buf: array of byte): int;
	get_status: fn(fd: ref Sys->FD, port: int): int;
	set_address: fn(fd: ref Sys->FD, address: int): int;
	set_configuration: fn(fd: ref Sys->FD, n: int): int;
	setclear_feature: fn(fd: ref Sys->FD, rtyp: int, value: int, index: int, on: int): int;
	setup: fn(setupfd: ref Sys->FD, typ, req, value, index: int, outbuf: array of byte, inbuf: array of byte): int;
	get_parsed_configuration_descriptor: fn(fd: ref Sys->FD, n: int): ref Configuration;
	get_parsed_device_descriptor: fn(fd: ref Sys->FD): ref Device;

	dump_configuration: fn(fd: ref Sys->FD, conf: ref Configuration);
};

UsbDriver: module
{
	MOUSEPATH: con "/appl/cmd/usb/usbmouse.dis";
	init: fn(usb: Usb, setupfd, ctlfd: ref Sys->FD, dev: ref Usb->Device, conf: array of ref Usb->Configuration, path: string): int;
	shutdown: fn();
};
