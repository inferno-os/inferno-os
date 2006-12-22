#
# Copyright © 2001 Vita Nuova Holdings Limited.
#
implement UsbDriver;

include "sys.m";
	sys: Sys;
include "usb.m";
	usb: Usb;
	Endpt, RD2H, RH2D: import Usb;

ENDPOINT_STALL: con 0;	# TO DO: should be in usb.m

readerpid: int;
setupfd, ctlfd: ref Sys->FD;
infd, outfd: ref Sys->FD;
inep, outep: ref Endpt;
cbwseq := 0;
capacity: big;
debug := 0;

lun: int;
blocksize: int;

kill(pid: int)
{
	fd := sys->open("#p/"+string pid+"/ctl", Sys->OWRITE);
	if (fd != nil)
		sys->fprint(fd, "kill");
}

reader(pidc: chan of int, fileio: ref Sys->FileIO)
{
	pid := sys->pctl(0, nil);
	pidc <-= pid;
	for(;;) alt{
	(offset, count, nil, rc) := <-fileio.read =>
		if (rc != nil) {
			if (offset%blocksize || count%blocksize) {
				rc <- = (nil, "unaligned read");
				continue;
			}
			offset /= blocksize;
			count /= blocksize;
			buf := array [count * blocksize] of byte;
			if (scsiread10(lun, offset, count, buf) < 0) {
				scsirequestsense(lun);
				rc <- = (nil, "read error");
				continue;
			}
			rc <- = (buf, nil);
		}
	(offset, data, nil, wc) := <-fileio.write =>
		if(wc != nil){
			count := len data;
			if(offset%blocksize || count%blocksize){
				wc <-= (0, "unaligned write");
				continue;
			}
			offset /= blocksize;
			count /= blocksize;
			if(scsiwrite10(lun, offset, count, data) < 0){
				scsirequestsense(lun);
				wc <-= (0, "write error");
				continue;
			}
			wc <-= (len data, nil);
		}
	}
	readerpid = -1;
}

massstoragereset(): int
{
	if (usb->setup(setupfd, Usb->RH2D | Usb->Rclass | Usb->Rinterface, 255, 0, 0, nil, nil) < 0) {
		sys->print("usbmass: storagereset failed\n");
		return -1;
	}
	return 0;
}
	
getmaxlun(): int
{
	buf := array[1] of byte;
	if (usb->setup(setupfd, Usb->RD2H | Usb->Rclass | Usb->Rinterface, 254, 0, 0, nil, buf) < 0) {
		sys->print("usbmass: getmaxlun failed\n");
		return -1;
	}
	return int buf[0];
}

#
# CBW:
#	sig[4]="USBC" tag[4] datalen[4] flags[1] lun[1] len[1] cmd[len]
#
sendcbw(dtl: int, outdir: int, lun: int, cmd: array of byte): int
{
	cbw := array [31] of byte;
	cbw[0] = byte 'U';
	cbw[1] = byte 'S';
	cbw[2] = byte 'B';
	cbw[3] = byte 'C';
	usb->put4(cbw[4:], ++cbwseq);
	usb->put4(cbw[8:], dtl);
	if (outdir)
		cbw[12] = byte RH2D;
	else
		cbw[12] = byte RD2H;
	cbw[13] = byte lun;
	cbw[14] = byte len cmd;
	cbw[15:] = cmd;
	rv := sys->write(outfd, cbw, len cbw);
	if (rv < 0) {
		sys->print("sendcbw: failed: %r\n");
		return -1;
	}
	if (rv != len cbw) {
		sys->print("sendcbw: truncated send\n");
		return -1;
	}
	return 0;
}

#
# CSW:
#	sig[4]="USBS" tag[4] residue[4] status[1]
#

recvcsw(tag: int): (int, int)
{
	if(debug)
		sys->print("recvcsw\n");
	buf := array [13] of byte;
	if (sys->read(infd, buf, len buf) != len buf) {
		sys->print("recvcsw: read failed: %r\n");
		return (-1, -1);
	}
	if (usb->get4(buf) != (('S'<<24)|('B'<<16)|('S'<<8)|'U')) {
		sys->print("recvcsw: signature wrong\n");
		return (-1, -1);
	}
	recvtag := usb->get4(buf[4:]);
	if (recvtag != tag) {
		sys->print("recvcsw: tag does not match: sent %d recved %d\n", tag, recvtag);
		return (-1, -1);
	}
	residue := usb->get4(buf[8:]);
	status := int buf[12];
	if(debug)
		sys->print("recvcsw: residue %d status %d\n", residue, status);
	return (residue, status);
}

unstall(ep: ref Endpt)
{
	if(debug)
		sys->print("unstalling bulk %x\n", ep.addr);
	x := ep.addr & 16rF;
	sys->fprint(ctlfd, "unstall %d", x);
	sys->fprint(ctlfd, "data %d 0", x);
	if (usb->setclear_feature(setupfd, Usb->Rendpt, ENDPOINT_STALL, ep.addr, 0) < 0) {
		sys->print("unstall: clear_feature() failed: %r\n");
		return;
	}
}

warnfprint(fd: ref Sys->FD, s: string)
{
	if (sys->fprint(fd, "%s", s) != len s)
		sys->print("warning: writing %s failed: %r\n", s);
}

bulkread(lun: int, cmd: array of byte, buf: array of byte, dump: int): int
{
	if (sendcbw(len buf, 0, lun, cmd) < 0)
		return -1;
	got := 0;
	if (buf != nil) {
		while (got < len buf) {
			rv := sys->read(infd, buf[got:], len buf - got);
			if (rv < 0) {
				sys->print("bulkread: read failed: %r\n");
				break;
			}
			if(debug)
				sys->print("read %d\n", rv);
			got += rv;
			break;
		}
		if (dump) {
			for (i := 0; i < got; i++)
				sys->print("%.2ux", int buf[i]);
			sys->print("\n");
		}
		if (got == 0)
			unstall(inep);
	}
	(residue, status) := recvcsw(cbwseq);
	if (residue < 0) {
		unstall(inep);
		(residue, status) = recvcsw(cbwseq);
		if (residue < 0)
			return -1;
	}
	if (status != 0)
		return -1;
	return got;
}

bulkwrite(lun: int, cmd: array of byte, buf: array of byte): int
{
	if (sendcbw(len buf, 1, lun, cmd) < 0)
		return -1;
	got := 0;
	if (buf != nil) {
		while (got < len buf) {
			rv := sys->write(outfd, buf[got:], len buf - got);
			if (rv < 0) {
				sys->print("bulkwrite: write failed: %r\n");
				break;
			}
			if(debug)
				sys->print("write %d\n", rv);
			got += rv;
			break;
		}
		if (got == 0)
			unstall(outep);
	}
	(residue, status) := recvcsw(cbwseq);
	if (residue < 0) {
		unstall(inep);
		(residue, status) = recvcsw(cbwseq);
		if (residue < 0)
			return -1;
	}
	if (status != 0)
		return -1;
	return got;
}

scsiinquiry(lun: int): int
{
	buf := array [36] of byte;	# don't use 255, many devices can't cope
	cmd := array [6] of byte;
	cmd[0] = byte 16r12;
	cmd[1] = 	byte (lun << 5);
	cmd[2] = byte 0;
	cmd[3] = byte 0;
	cmd[4] = byte len buf;
	cmd[5]  = byte 0;
	got := bulkread(lun, cmd, buf, 0);
	if (got < 0)
		return -1;
	if (got < 36) {
		sys->print("scsiinquiry: too little data\n");
		return -1;
	}
	t := int buf[0] & 16r1f;
	if(debug)
		sys->print("scsiinquiry: type %d/%s\n", t, string buf[8:35]);
	if (t != 0)
		return -1;
	return 0;
}

scsireadcapacity(lun: int): int
{
#	warnfprint(ctlfd, "debug 0 1");
#	warnfprint(ctlfd, "debug 1 1");
#	warnfprint(ctlfd, "debug 2 1");
	buf := array [8] of byte;
	cmd := array [10] of byte;
	cmd[0] = byte 16r25;
	cmd[1] = 	byte (lun << 5);
	cmd[2] = byte 0;
	cmd[3] = byte 0;
	cmd[4] = byte 0;
	cmd[5]  = byte 0;
	cmd[6]  = byte 0;
	cmd[7]  = byte 0;
	cmd[8]  = byte 0;
	cmd[9] = byte 0;
	got := bulkread(lun, cmd, buf, 0);
	if (got < 0)
		return -1;
	if (got != len buf) {
		sys->print("scsireadcapacity: returned data not right size\n");
		return -1;
	}
	blocksize = usb->bigget4(buf[4:]);
	lba := big usb->bigget4(buf[0:]) & 16rFFFFFFFF;
	capacity = big blocksize * (lba+big 1);
	if(debug)
		sys->print("block size %d lba %bd cap %bd\n", blocksize, lba, capacity);
	return 0;
}

scsirequestsense(lun: int): int
{
#	warnfprint(ctlfd, "debug 0 1");
#	warnfprint(ctlfd, "debug 1 1");
#	warnfprint(ctlfd, "debug 2 1");
	buf := array [18] of byte;
	cmd := array [6] of byte;
	cmd[0] = byte 16r03;
	cmd[1] = 	byte (lun << 5);
	cmd[2] = byte 0;
	cmd[3] = byte 0;
	cmd[4] = byte len buf;
	cmd[5]  = byte 0;
	got := bulkread(lun, cmd, buf, 1);
	if (got < 0)
		return -1;
	return 0;
}

scsiread10(lun: int, offset, count: int, buf: array of byte): int
{
	cmd := array [10] of byte;
	cmd[0] = byte 16r28;
	cmd[1] = byte (lun << 5);
	usb->bigput4(cmd[2:], offset);
	cmd[6] = byte 0;
	usb->bigput2(cmd[7:], count);
	cmd[9] = byte 0;
	got := bulkread(lun, cmd, buf, 0);
	if (got < 0)
		return -1;
	return 0;
}

scsiwrite10(lun: int, offset, count: int, buf: array of byte): int
{
	cmd := array [10] of byte;
	cmd[0] = byte 16r2A;
	cmd[1] = byte (lun << 5);
	usb->bigput4(cmd[2:], offset);
	cmd[6] = byte 0;
	usb->bigput2(cmd[7:], count);
	cmd[9] = byte 0;
	got := bulkwrite(lun, cmd, buf);
	if (got < 0)
		return -1;
	return 0;
}

scsistartunit(lun: int, start: int): int
{
#	warnfprint(ctlfd, "debug 0 1");
#	warnfprint(ctlfd, "debug 1 1");
#	warnfprint(ctlfd, "debug 2 1");
	cmd := array [6] of byte;
	cmd[0] = byte 16r1b;
	cmd[1] = byte (lun << 5);
	cmd[2] = byte 0;
	cmd[3] = byte 0;
	cmd[4] = byte (start & 1);
	cmd[5]  = byte 0;
	got := bulkread(lun, cmd, nil, 0);
	if (got < 0)
		return -1;
	return 0;
}

init(usbmod: Usb, psetupfd, pctlfd: ref Sys->FD,
	nil: ref Usb->Device,
	conf: array of ref Usb->Configuration, path: string): int
{
	usb = usbmod;
	setupfd = psetupfd;
	ctlfd = pctlfd;

	sys = load Sys Sys->PATH;
	rv := usb->set_configuration(setupfd, conf[0].id);
	if (rv < 0)
		return rv;
	rv = massstoragereset();
	if (rv < 0)
		return rv;
	maxlun := getmaxlun();
	if (maxlun < 0)
		return maxlun;
	lun = 0;
	if(debug)
		sys->print("maxlun %d\n", maxlun);
	inep = outep = nil;
	epts := (hd conf[0].iface[0].altiface).ep;
	for(i := 0; i < len epts; i++)
		if(epts[i].etype == Usb->Ebulk){
			if(epts[i].d2h){
				if(inep == nil)
					inep = epts[i];
			}else{
				if(outep == nil)
					outep = epts[i];
			}
		}
	if(inep == nil || outep == nil){
		sys->print("can't find endpoints\n");
		return -1;
	}
	isrw := (inep.addr & 16rF) == (outep.addr & 16rF);
	if(!isrw){
		infd = openep(path, inep, Sys->OREAD);
		if(infd == nil)
			return -1;
		outfd = openep(path, outep, Sys->OWRITE);
		if(outfd == nil)
			return -1;
	}else{
		infd = outfd = openep(path, inep, Sys->ORDWR);
		if(infd == nil)
			return -1;
	}
	if (scsiinquiry(0) < 0)
		return -1;
	scsistartunit(lun, 1);
	if (scsireadcapacity(0) < 0) {
		scsirequestsense(0);
		if (scsireadcapacity(0) < 0)
			return -1;
	}
	fileio := sys->file2chan("/chan", "usbdisk");
	if (fileio == nil) {
		sys->print("file2chan failed: %r\n");
		return -1;
	}
	setlength("/chan/usbdisk", capacity);
#	warnfprint(ctlfd, "debug 0 1");
#	warnfprint(ctlfd, "debug 1 1");
#	warnfprint(ctlfd, "debug 2 1");
	pidc := chan of int;
	spawn reader(pidc, fileio);
	readerpid = <- pidc;
	return 0;
}

shutdown()
{
	if (readerpid >= 0)
		kill(readerpid);
}

openep(path: string, ep: ref Endpt, mode: int): ref Sys->FD
{
	if(debug)
		sys->print("ep %x maxpkt %d interval %d\n", ep.addr, ep.maxpkt, ep.interval);
	ms: string;
	case mode {
	Sys->OREAD => ms = "r";
	Sys->OWRITE => ms = "w";
	* => ms = "rw";
	}
	if(sys->fprint(ctlfd, "ep %d bulk %s %d 16", ep.addr&16rF, ms, ep.maxpkt) < 0)
		return nil;
	return sys->open(sys->sprint("%s/ep%ddata", path, ep.addr&16rF), mode);
}

setlength(f: string, size: big)
{
	d := sys->nulldir;
	d.length = size;
	sys->wstat(f, d);	# ignore errors since it fails on older kernels
}
