implement LegoLink;

include "sys.m";
include "draw.m";
include "timers.m";
include "rcxsend.m";

LegoLink : module {
	init : fn (ctxt : ref Draw->Context, argv : list of string);
};

POLLDONT : con 0;
POLLNOW : con 16r02;
POLLDO : con 16r04;

sys : Sys;
timers : Timers;
Timer : import timers;
datain : chan of array of byte;
errormsg : string;

error(msg: string)
{
	sys->fprint(sys->fildes(2), "%s\n", msg);
	raise "fail:error";
}

init(nil : ref Draw->Context, argv : list of string)
{
	sys = load Sys Sys->PATH;
	sys->pctl(Sys->NEWPGRP, nil);

	argv = tl argv;
	if (len argv != 1)
		error("usage: legolink portnum");

	timers = load Timers "timers.dis";
	if (timers == nil)
		error(sys->sprint("cannot load timers module: %r"));

	portnum := int hd argv;
	(rdfd, wrfd, err) := serialport(portnum);
	if (err != nil)
		error(err);

	# set up our mount file
	if (sys->bind("#s", "/net", Sys->MBEFORE) == -1)
		error(sys->sprint("failed to bind srv device: %r"));

	f2c := sys->file2chan("/net", "legolink");
	if (f2c == nil)
		error(sys->sprint("cannot create legolink channel: %r"));

	datain = chan of array of byte;
	send := chan of array of byte;
	recv := chan of array of byte;
	timers->init(50);
	spawn reader(rdfd, datain);
	consume();
	spawn protocol(wrfd, send, recv);
	spawn srvlink(f2c, send, recv);
}

srvlink(f2c : ref Sys->FileIO, send, recv : chan of array of byte)
{
	me := sys->pctl(0, nil);
	rdfid := -1;
	wrfid := -1;
	buffer := array [256] of byte;
	bix := 0;

	rdblk := chan of (int, int, int, Sys->Rread);
	readreq := rdblk;
	wrblk := chan of (int, array of byte, int, Sys->Rwrite);
	writereq := f2c.write;
	wrreply : Sys->Rwrite;
	sendblk := chan of array of byte;
	sendchan := sendblk;
	senddata : array of byte;

	for (;;) alt {
	data := <- recv =>
		# got some data from brick, nil for error
		if (data == nil) {
			# some sort of error
			if (wrreply != nil) {
				wrreply <- = (0, errormsg);
			}
			killgrp(me);
		}
		if (bix + len data > len buffer) {
			newb := array [bix + len data + 256] of byte;
			newb[0:] = buffer;
			buffer = newb;
		}
		buffer[bix:] = data;
		bix += len data;
		readreq = f2c.read;

	(offset, count, fid, rc) := <- readreq =>
		if (rdfid == -1)
			rdfid = fid;
		if (fid != rdfid) {
			if (rc != nil)
				rc <- = (nil, "file in use");
			continue;
		}
		if (rc == nil) {
			rdfid = -1;
			continue;
		}
		if (errormsg != nil) {
			rc <- = (nil, errormsg);
			killgrp(me);
		}
		# reply with what we've got
		if (count > bix)
			count = bix;
		rdata := array [count] of byte;
		rdata[0:] = buffer[0:count];
		buffer[0:] = buffer[count:bix];
		bix -= count;
		if (bix == 0)
			readreq = rdblk;
		alt {
		rc <- = (rdata, nil)=>
			;
		* =>
			;
		}

	(offset, data, fid, wc) := <- writereq =>
		if (wrfid == -1)
			wrfid = fid;
		if (fid != wrfid) {
			if (wc != nil)
				wc <- = (0, "file in use");
			continue;
		}
		if (wc == nil) {
			wrfid = -1;
			continue;
		}
		if (errormsg != nil) {
			wc <- = (0, errormsg);
			killgrp(me);
		}
		senddata = data;
		sendchan = send;
		wrreply = wc;
		writereq = wrblk;

	sendchan <- = senddata =>
		alt {
		wrreply <- = (len senddata, nil) =>
			;
		* =>
			;
		}
		wrreply = nil;
		sendchan = sendblk;
		writereq = f2c.write;
	}
}

killgrp(pid : int)
{
	pctl := sys->open("/prog/" + string pid + "/ctl", Sys->OWRITE);
	if (pctl != nil) {
		poison := array of byte "killgrp";
		sys->write(pctl, poison, len poison);
	}
	exit;
}

serialport(port : int) : (ref Sys->FD, ref Sys->FD, string)
{
	serport := "/dev/eia" + string port;
	serctl := serport + "ctl";

	rfd := sys->open(serport, Sys->OREAD);
	if (rfd == nil)
		return (nil, nil, sys->sprint("cannot read %s: %r", serport));
	wfd := sys->open(serport, Sys->OWRITE);
	if (wfd == nil)
		return (nil, nil, sys->sprint("cannot write %s: %r", serport));
	ctlfd := sys->open(serctl, Sys->OWRITE);
	if (ctlfd == nil)
		return (nil, nil, sys->sprint("cannot open %s: %r", serctl));

	config := array [] of {
		"b2400",
		"l8",
		"po",
		"m0",
		"s1",
		"d1",
		"r1",
	};

	for (i := 0; i < len config; i++) {
		cmd := array of byte config[i];
		if (sys->write(ctlfd, cmd, len cmd) <= 0)
			return (nil, nil, sys->sprint("serial config (%s): %r", config[i]));
	}
	return (rfd, wfd, nil);
}

# reader and nbread as in rcxsend.b
reader(fd : ref Sys->FD, out : chan of array of byte)
{
	# with buf size of 1 there is no need
	# for overrun code in nbread()

	buf := array [1] of byte;
	for (;;) {
		n := sys->read(fd, buf, len buf);
		if (n <= 0)
			break;
		data := array [n] of byte;
		data[0:] = buf[0:n];
		out <- = data;
	}
	out <- = nil;
}

overrun : array of byte;

nbread(ms, n : int) : array of byte
{
	ret := array[n] of byte;
	tot := 0;
	if (overrun != nil) {
		if (n < len overrun) {
			ret[0:] = overrun[0:n];
			overrun = overrun[n:];
			return ret;
		}
		ret[0:] = overrun;
		tot += len overrun;
		overrun = nil;
	}
	tmr := timers->new(ms, 0);
loop:
	while (tot < n) {
		tmr.reset();
		alt {
			data := <- datain =>
				if (data == nil)
					break loop;
				dlen := len data;
				if (dlen > n - tot) {
					dlen = n - tot;
					overrun = data[dlen:];
				}
				ret[tot:] = data[0:dlen];
				tot += dlen;
			<- tmr.tick =>
				# reply timeout;
				break loop;
		}
	}
	tmr.destroy();
	if (tot == 0)
		return nil;
	return ret[0:tot];
}

consume()
{
	while (nbread(300, 1024) != nil)
		;
}

# fd: connection to remote client
# send: from local to remote
# recv: from remote to local
protocol(fd : ref Sys->FD, send, recv : chan of array of byte)
{
	seqnum := 0;
	towerdown := timers->new(1500, 0);
	starttower := 1;
	tmr := timers->new(250, 0);

	for (;;) {
		data : array of byte = nil;
		# get data to send
		alt {
		data = <- send =>
			;
		<- tmr.tick =>
			data = nil;
		<- towerdown.tick =>
			starttower = 1;
			continue;
		}
			
		poll := POLLNOW;
		while (poll == POLLNOW) {
			reply : array of byte;
			(reply, poll, errormsg) = datasend(fd, seqnum++, data, starttower);
			starttower = 0;
			towerdown.reset();
			if (errormsg != nil) {
sys->print("protocol: send error: %s\n", errormsg);
				tmr.destroy();
				recv <- = nil;
				return;
			}
			if (reply != nil) {
				recv <- = reply;
			}
			if (poll == POLLNOW) {
				# quick check to see if we have any more data
				alt {
				data = <- send =>
						;
				* =>
						data = nil;
				}
			}
		}
		if (poll == POLLDO)
			tmr.reset();
		else
			tmr.cancel();
	}
}

TX_HDR : con 3;
DL_HDR : con 5;	# 16r45 seqLSB seqMSB lenLSB lenMSB
DL_CKSM : con 1;
LN_HDR : con 1;
LN_JUNK : con 2;
LN_LEN : con 2;
LN_RXLEN : con 2;
LN_POLLMASK : con 16r06;
LN_COMPMASK : con 16r08;


# send a message (may be empty)
# wait for the reply
# returns (data, poll request, error)

datasend(wrfd : ref Sys->FD, seqnum : int, data : array of byte, startup : int) : (array of byte, int, string)
{
if (startup) {
	dummy := array [] of { byte 255, byte 0, byte 255, byte 0};
	sys->write(wrfd, dummy, len dummy);
	nbread(100, 100);
}
	seqnum = seqnum & 1;
	docomp := 0;
	if (data != nil) {
		comp := rlencode(data);
		if (len comp < len data) {
			docomp = 1;
			data = comp;
		}
	}

	# construct the link-level data packet
	# DL_HDR LN_HDR data cksum
	# last byte of data is stored in cksum byte
	llen := LN_HDR + len data;
	blklen := LN_LEN + llen - 1;	# llen includes cksum
	ldata := array [DL_HDR + blklen + 1] of byte;

	# DL_HDR
	if (seqnum == 0)
		ldata[0] = byte 16r45;
	else
		ldata[0] = byte 16r4d;
	ldata[1] = byte 0;				# blk number LSB
	ldata[2] = byte 0;				# blk number MSB
	ldata[3] = byte (blklen & 16rff);		# blk length LSB
	ldata[4] = byte ((blklen >> 8) & 16rff);	# blk length MSB

	# LN_LEN
	ldata[5] = byte (llen & 16rff);
	ldata[6] = byte ((llen>>8) & 16rff);
	# LN_HDR
	lhval := byte 0;
	if (seqnum == 1)
		lhval |= byte 16r01;
	if (docomp)
		lhval |= byte 16r08;
	
	ldata[7] = lhval;

	# data (+cksum)
	ldata[8:] = data;

	# construct the rcx data packet
	# TX_HDR (dn ~dn) cksum ~cksum
	rcxlen := TX_HDR + 2*(len ldata + 1);
	rcxdata := array [rcxlen] of byte;

	rcxdata[0] = byte 16r55;
	rcxdata[1] = byte 16rff;
	rcxdata[2] = byte 16r00;
	rcix := TX_HDR;
	cksum := 0;
	for (i := 0; i < len ldata; i++) {
		b := ldata[i];
		rcxdata[rcix++] = b;
		rcxdata[rcix++] = ~b;
		cksum += int b;
	}
	rcxdata[rcix++] = byte (cksum & 16rff);
	rcxdata[rcix++] = byte (~cksum & 16rff);

	# send it
	err : string;
	reply : array of byte;
	for (try := 0; try < 8; try++) {
		if (err != nil)
			sys->print("Try %d (lasterr %s)\n", try, err);
		err = "";
		step := 8;
		for (i = 0; err == nil && i < rcxlen; i += step) {
			if (i + step > rcxlen)
				step = rcxlen -i;
			if (sys->write(wrfd, rcxdata[i:i+step], step) != step) {
				return (nil, 0, "hangup");
			}

			# get the echo
			reply = nbread(300, step);
			if (reply == nil || len reply != step)
				# short echo
				err = "tower not responding";

			# check the echo
			for (ei := 0; err == nil && ei < step; ei++) {
				if (reply[ei] != rcxdata[i+ei])
					# echo mis-match
					err = "serial comms error";
			}
		}
		if (err != nil) {
			consume();
			continue;
		}

		# wait for a reply
		replen := TX_HDR + LN_JUNK + 2*LN_RXLEN;
		reply = nbread(300, replen);
		if (reply == nil || len reply != replen) {
			err = "brick not responding";
			consume();
			continue;
		}
		if (reply[0] != byte 16r55 || reply[1] != byte 16rff || reply[2] != byte 0
		|| reply[5] != ~reply[6] || reply[7] != ~reply[8]) {
			err = "bad reply from brick";
			consume();
			continue;
		}
		# reply[3] and reply [4] are junk, ~junk
		# put on front of msg by rcx rom
		replen = int reply[5] + ((int reply[7]) << 8) + 1;
		cksum = int reply[3] + int reply[5] + int reply[7];
		reply = nbread(200, replen * 2);
		if (reply == nil || len reply != replen * 2) {
			err = "short reply from brick";
			consume();
			continue;
		}
		cksum += int reply[0];
		for (i = 1; i < replen; i++) {
			reply[i] = reply[2*i];
			cksum += int reply[i];
		}
		cksum -= int reply[replen-1];
		if (reply[replen-1] != byte (cksum & 16rff)) {
			err = "bad checksum from brick";
			consume();
			continue;
		}
		if ((reply[0] & byte 1) != byte (seqnum & 1)) {
			# seqnum error
			# we have read everything, don't bother with consume()
			err = "bad seqnum from brick";
			continue;
		}

		# TADA! we have a valid message
		mdata : array of byte;
		lnhdr := int reply[0];
		poll := lnhdr & LN_POLLMASK;
		if (replen > 2) {
			# more than just hdr and cksum
			if (lnhdr & LN_COMPMASK) {
				mdata = rldecode(reply[1:replen-1]);
				if (mdata == nil) {
					err = "bad brick msg compression";
					continue;
				}
			} else {
				mdata = array [replen - 2] of byte;
				mdata[0:] = reply[1:replen-1];
			}
		}
		return (mdata, poll, nil);
	}
	return (nil, 0, err);
}


rlencode(data : array of byte) : array of byte
{
	srcix := 0;
	outix := 0;
	out := array [64] of byte;
	val := 0;
	nextval := -1;
	n0 := 0;

	while (srcix < len data || nextval != -1) {
		if (nextval != -1) {
			val = nextval;
			nextval = -1;
		} else {
			val = int data[srcix];
			if (val == 16r88)
				nextval = 0;
			if (val == 0) {
				n0++;
				srcix++;
				if (srcix < len data && n0 < 16rff + 2)
					continue;
			}
			case n0 {
			0 =>
				srcix++;
			1 =>
				val = 0;
				nextval = -1;
				n0 = 0;
			2 =>
				val = 0;
				nextval = 0;
				n0 = 0;
			* =>
				val = 16r88;
				nextval = (n0-2);
				n0 = 0;
			}
		}
		if (outix >= len out) {
			newout := array [2 * len out] of byte;
			newout[0:] = out;
			out = newout;
		}
		out[outix++] = byte val;
	}
	return out[0:outix];
}

rldecode(data : array of byte) : array of byte
{
	srcix := 0;
	outix := 0;
	out := array [64] of byte;

	n0 := 0;
	val := 0;
	while (srcix < len data || n0 > 0) {
		if (n0 > 0)
			n0--;
		else {
			val = int data[srcix++];
			if (val == 16r88) {
				if (srcix >= len data)
					# bad encoding
					return nil;
				n0 = int data[srcix++];
				if (n0 > 0) {
					n0 += 2;
					val = 0;
					continue;
				}
			}
		}
		if (outix >= len out) {
			newout := array [2 * len out] of byte;
			newout[0:] = out;
			out = newout;
		}
		out[outix++] = byte val;
	}
	return out[0:outix];
}

hexdump(data : array of byte)
{
	for (i := 0; i < len data; i++)
		sys->print("%.2x ", int data[i]);
	sys->print("\n");
}
