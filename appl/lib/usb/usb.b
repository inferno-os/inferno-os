#
# Copyright © 2002 Vita Nuova Holdings Limited
#
implement Usb;

include "sys.m";
	sys: Sys;

include "usb.m";

include "string.m";
	str: String;

Proto: adt {
	proto: int;
	name: string;
};

SubClass: adt {
	subclass: int;
	name: string;
	proto: array of Proto;
};

Class: adt {
	class: int;
	name: string;
	subclass: array of SubClass;
};

classes := array [] of {
	Class(Usb->CL_AUDIO, "audio",
		array [] of {
			SubClass(1, "control", nil),
			SubClass(2, "stream", nil),
			SubClass(3, "midi", nil),
		}
	),
	Class(Usb->CL_COMMS, "comms",
		array [] of {
			SubClass(1, "abstract",
				array [] of {
					Proto(1, "AT"),
				}
			)
		}
	),
	Class(Usb->CL_HID, "hid",
		array [] of {
			SubClass(1, "boot",
				array [] of {
					Proto(1, "kbd"),
					Proto(2, "mouse"),
				}
			)
		}
	),
	Class(Usb->CL_PRINTER, "printer",
		array [] of {
			SubClass(1, "printer",
				array [] of {
					Proto(1, "uni"),
					Proto(2, "bi"),
				}
			)
		}
	),
	Class(Usb->CL_HUB, "hub",
		array [] of {
			SubClass(1, "hub", nil),
		}
	),
	Class(Usb->CL_DATA, "data", nil),
	Class(Usb->CL_MASS, "mass",
		array [] of {
			SubClass(1, "rbc",
				array [] of {
					Proto(0, "cbi-cc"),
					Proto(1, "cbi-nocc"),
					Proto(16r50, "bulkonly"),
				}
			),
			SubClass(2, "sff-8020i/mmc-2",
				array [] of {
					Proto(0, "cbi-cc"),
					Proto(1, "cbi-nocc"),
					Proto(16r50, "bulkonly"),
				}
			),
			SubClass(3, "qic-157",
				array [] of {
					Proto(0, "cbi-cc"),
					Proto(1, "cbi-nocc"),
					Proto(16r50, "bulkonly"),
				}
			),
			SubClass(4, "ufi",
				array [] of {
					Proto(0, "cbi-cc"),
					Proto(1, "cbi-nocc"),
					Proto(16r50, "bulkonly"),
				}
			),
			SubClass(5, "sff-8070i",
				array [] of {
					Proto(0, "cbi-cc"),
					Proto(1, "cbi-nocc"),
					Proto(16r50, "bulkonly"),
				}
			),
			SubClass(6, "scsi",
				array [] of {
					Proto(0, "cbi-cc"),
					Proto(1, "cbi-nocc"),
					Proto(16r50, "bulkonly"),
				}
			),
		}
	),
};

get2(b: array of byte): int
{
	return int b[0] | (int b[1] << 8);
}

put2(buf: array of byte, v: int)
{
	buf[0] = byte v;
	buf[1] = byte (v >> 8);
}

get4(b: array of byte): int
{
	return int b[0] | (int b[1] << 8) | (int b[2] << 16) | (int b[3] << 24);
}

put4(buf: array of byte, v: int)
{
	buf[0] = byte v;
	buf[1] = byte (v >> 8);
	buf[2] = byte (v >> 16);
	buf[3] = byte (v >> 24);
}

bigget2(b: array of byte): int
{
	return int b[1] | (int b[0] << 8);
}

bigput2(buf: array of byte, v: int)
{
	buf[1] = byte v;
	buf[0] = byte (v >> 8);
}

bigget4(b: array of byte): int
{
	return int b[3] | (int b[2] << 8) | (int b[1] << 16) | (int b[0] << 24);
}

bigput4(buf: array of byte, v: int)
{
	buf[3] = byte v;
	buf[2] = byte (v >> 8);
	buf[1] = byte (v >> 16);
	buf[0] = byte (v >> 24);
}

strtol(s: string, base: int): (int, string)
{
	if (str == nil)
		str = load String String->PATH;
	if (base != 0)
		return str->toint(s, base);
	if (len s >= 2 && (s[0:2] == "0X" || s[0:2] == "0x"))
		return str->toint(s[2:], 16);
	if (len s > 0 && s[0:1] == "0")
		return str->toint(s[1:], 8);
	return str->toint(s, 10);
}

memset(buf: array of byte, v: int)
{
	for (x := 0; x < len buf; x++)
		buf[x] = byte v;
}

setupreq(setupfd: ref Sys->FD, typ, req, value, index: int, outbuf: array of byte, count: int): int
{
	additional: int;
	if (outbuf != nil) {
		additional = len outbuf;
		# if there is an outbuf, then the count sent must be length of the payload
		# this assumes that RH2D is set
		count = additional;
	}
	else
		additional = 0;
	buf := array[8 + additional] of byte;
	buf[0] = byte typ;
	buf[1] = byte req;
	put2(buf[2:], value);
	put2(buf[4:], index);
	put2(buf[6:], count);
	if (additional)
		buf[8:] = outbuf;
	rv := sys->write(setupfd, buf, len buf);
	if (rv < 0)
		return -1;
	if (rv != len buf)
		return -1;
	return rv;
}

setupreply(setupfd: ref Sys->FD, buf: array of byte): int
{
	nb := sys->read(setupfd, buf, len buf);
	return nb;
}

setup(setupfd: ref Sys->FD, typ, req, value, index: int, outbuf: array of byte, inbuf: array of byte): int
{
	count: int;
	if (inbuf != nil)
		count = len inbuf;
	else
		count = 0;
	if (setupreq(setupfd, typ, req, value, index, outbuf, count) < 0)
		return -1;
	if (count == 0)
		return 0;
	return setupreply(setupfd, inbuf);
}

get_descriptor(fd: ref Sys->FD, rtyp: int, dtyp: int, dindex: int, langid: int, buf: array of byte): int
{
	nr := -1;
	if (setupreq(fd, RD2H | rtyp | Rdevice, GET_DESCRIPTOR, (dtyp << 8) | dindex, langid, nil, len buf) < 0
		|| (nr = setupreply(fd, buf)) < 1)
		return -1;
	return nr;
}

get_standard_descriptor(fd: ref Sys->FD, dtyp: int, index: int, buf: array of byte): int
{
	return get_descriptor(fd, Rstandard, dtyp, index, 0, buf);
}

get_class_descriptor(fd: ref Sys->FD, dtyp: int, index: int, buf: array of byte): int
{
	return get_descriptor(fd, Rclass, dtyp, index, 0, buf);
}

get_vendor_descriptor(fd: ref Sys->FD, dtyp: int, index: int, buf: array of byte): int
{
	return get_descriptor(fd, Rvendor, dtyp, index, 0, buf);
}

get_status(fd: ref Sys->FD, port: int): int
{
	buf := array [4] of byte;
	if (setupreq(fd, RD2H | Rclass | Rother, GET_STATUS, 0, port, nil, len buf) < 0
	 	|| setupreply(fd, buf) < len buf)
		return -1;
	return get2(buf);
}

set_address(fd: ref Sys->FD, address: int): int
{
	return setupreq(fd, RH2D | Rstandard | Rdevice, SET_ADDRESS, address, 0, nil, 0);
}

set_configuration(fd: ref Sys->FD, n: int): int
{
	return setupreq(fd, RH2D | Rstandard | Rdevice, SET_CONFIGURATION, n, 0, nil, 0);
}

setclear_feature(fd: ref Sys->FD, rtyp: int, value: int, index: int, on: int): int
{
	req: int;
	if (on)
		req = SET_FEATURE;
	else
		req = CLEAR_FEATURE;
	return setupreq(fd, RH2D | rtyp, req, value, index, nil, 0);
}

parse_conf(b: array of byte): ref Configuration
{
	if (len b < DCONFLEN)
		return nil;
	conf := ref Configuration;
	conf.id = int b[5];
	conf.iface = array[int b[4]] of Interface;
	conf.attr = int b[7];
	conf.powerma = int b[8] * 2;
	return conf;
}

parse_iface(conf: ref Configuration, b: array of byte): ref AltInterface
{
	if (len b < DINTERLEN || conf == nil)
		return nil;
	id := int b[2];
	if (id >= len conf.iface)
		return nil;
	ai := ref AltInterface;
	ai.id = int b[3];
	if (int b[4] != 0)
		ai.ep = array [int b[4]] of ref Endpt;
	ai.class = int b[5];
	ai.subclass = int b[6];
	ai.proto = int b[7];
	conf.iface[id].altiface = ai :: conf.iface[id].altiface;
	return ai;
}
	
parse_endpt(conf: ref Configuration, ai: ref AltInterface, b: array of byte): ref Endpt
{
	if (len b < DENDPLEN || conf == nil || ai == nil || ai.ep == nil)
		return nil;
	for (i := 0; i < len ai.ep; i++)
		if (ai.ep[i] == nil)
			break;
	if (i >= len ai.ep)
		return nil;
	ep := ref Endpt;
	ai.ep[i] = ep;
	ep.addr = int b[2];
	ep.attr = int b[3];
	ep.d2h = ep.addr & 16r80;
	ep.etype = int b[3] & 3;
	ep.isotype = (int b[3] >> 2) & 3;
	ep.maxpkt = get2(b[4:]);
	ep.interval = int b[6];
	return ep;
}

get_parsed_configuration_descriptor(fd: ref Sys->FD, n: int): ref Configuration
{
	conf: ref Configuration;
	altiface: ref AltInterface;

	b := array [256] of byte;
	nr := get_standard_descriptor(fd, CONFIGURATION, n, b);
	if (nr < 0)
		return nil;
	conf = nil;
	altiface = nil;
	for (i := 0; nr - i > 2 && b[i] > byte 0 && int b[i] <= nr - i; i += int b[i]) {
		ni := i + int b[i];
		case int b[i + 1] {
		Usb->CONFIGURATION =>
			conf = parse_conf(b[i: ni]);
			if (conf == nil)
				return nil;
		Usb->INTERFACE =>
			altiface = parse_iface(conf, b[i: ni]);
			if (altiface == nil)
				return nil;
		Usb->ENDPOINT =>
			if (parse_endpt(conf, altiface, b[i: ni]) == nil)
				return nil;
		}
	}
	if (i < nr)
		sys->print("usb: residue at end of descriptors\n");
	return conf;
}

get_parsed_device_descriptor(fd: ref Sys->FD): ref Device
{
	b := array [256] of byte;
	nr := get_standard_descriptor(fd, DEVICE, 0, b);
	if (nr < DDEVLEN) {
		if (nr == 8 || nr == 16) {
			memset(b[nr: DDEVLEN - 1], 0);
			b[DDEVLEN - 1] = byte 1;
			nr = DDEVLEN;
		}
		else
			return nil;
	}
	dev := ref Device;
	dev.usbmajor = int b[3];
	dev.usbminor = int b[2];
	dev.class = int b[4];
	dev.subclass = int b[5];
	dev.proto = int b[6];
	dev.maxpkt0 = int b[7];
	dev.vid = get2(b[8:]);
	dev.did = get2(b[10:]);
	dev.relmajor = int b[13];
	dev.relminor = int b[12];
	dev.nconf = int b[17];
	return dev;
}

dump_configuration(fd: ref Sys->FD, conf: ref Configuration)
{
	sys->fprint(fd, "configuration %d attr 0x%.x powerma %d\n", conf.id, conf.attr, conf.powerma);
	for (i := 0; i < len conf.iface; i++) {
		sys->fprint(fd, "\tinterface %d\n", i);
		ail := conf.iface[i].altiface;
		while (ail != nil) {
			ai := hd ail;
			sys->fprint(fd, "\t\t%d class %d subclass %d proto %d [%s]\n",
				ai.id, ai.class, ai.subclass, ai.proto,	
				sclass(ai.class, ai.subclass, ai.proto));
			for (e := 0; e < len ai.ep; e++) {
				if (ai.ep[e] == nil) {
					sys->fprint(fd, "\t\t\t missing descriptor\n");
					continue;
				}
				sys->fprint(fd, "\t\t\t0x%.2ux attr 0x%.x maxpkt %d interval %d\n",
					ai.ep[e].addr, ai.ep[e].attr, ai.ep[e].maxpkt, ai.ep[e].interval);
			}
			ail = tl ail;
		}
	}
sys->fprint(fd, "done dumping\n");
}

sclass(class, subclass, proto: int): string
{
	for (c := 0; c < len classes; c++)
		if (classes[c].class == class)
			break;
	if (c >= len classes)
		return sys->sprint("%d.%d.%d", class, subclass, proto);
	if (classes[c].subclass == nil)
		return sys->sprint("%s.%d.%d", classes[c].name, subclass, proto);
	for (sc := 0; sc < len classes[c].subclass; sc++)
		if (classes[c].subclass[sc].subclass == subclass)
			break;
	if (sc >= len classes[c].subclass)
		return sys->sprint("%s.%d.%d", classes[c].name, subclass, proto);
	if (classes[c].subclass[sc].proto == nil)
		return sys->sprint("%s.%s.%d", classes[c].name, classes[c].subclass[sc].name, proto);
	for (p := 0; p < len classes[c].subclass[sc].proto; p++)
		if (classes[c].subclass[sc].proto[p].proto == proto)
			break;
	if (p >= len classes[c].subclass[sc].proto)
		return sys->sprint("%s.%s.%d", classes[c].name, classes[c].subclass[sc].name, proto);
	return sys->sprint("%s.%s.%s", classes[c].name, classes[c].subclass[sc].name,
		classes[c].subclass[sc].proto[p].name);
}

init()
{
	sys = load Sys Sys->PATH;
}
