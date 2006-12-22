implement RcxSend;

include "sys.m";
include "timers.m";
include "rcxsend.m";

sys : Sys;
timers : Timers;
Timer : import timers;
datain : chan of array of byte;
debug : int;
rpid : int;
wrfd : ref Sys->FD;

TX_HDR : con 3;
TX_CKSM : con 2;

init(portnum, dbg : int) : string
{
	debug = dbg;
	sys = load Sys Sys->PATH;
	timers = load Timers Timers->PATH; 	#"timers.dis";
	if (timers == nil)
		 return sys->sprint("cannot load timer module: %r");

	rdfd : ref Sys->FD;
	err : string;
	(rdfd, wrfd, err) = serialport(portnum);
	if (err != nil)
		return err;

	timers->init(50);
	pidc := chan of int;
	datain = chan of array of byte;
	spawn reader(pidc, rdfd, datain);
	rpid = <- pidc;
	consume();
	return nil;
}

reader(pidc : chan of int, fd : ref Sys->FD, out : chan of array of byte)
{
	pidc <- = sys->pctl(0, nil);

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
	if (debug)
		sys->print("Reader error\n");
}

send(data : array of byte, n, rlen: int) : array of byte
{
	# 16r55 16rff 16r00 (d[i] ~d[i])*n cksum ~cksum
	obuf := array [TX_HDR + (2*n ) + TX_CKSM] of byte;
	olen := 0;
	obuf[olen++] = byte 16r55;
	obuf[olen++] = byte 16rff;
	obuf[olen++] = byte 16r00;
	cksum := 0;
	for (i := 0; i < n; i++) {
		obuf[olen++] = data[i];
		obuf[olen++] = ~data[i];
		cksum += int data[i];
	}
	obuf[olen++] = byte (cksum & 16rff);
	obuf[olen++] = byte (~cksum & 16rff);

	needr := rlen;
	if (rlen > 0)
		needr = TX_HDR + (2 * rlen) + TX_CKSM;
	for (try := 0; try < 5; try++) {
		ok := 1;
		err := "";
		reply : array of byte;

		step := 8;
		for (i = 0; ok && i < olen; i += step) {
			if (i + step > olen)
				step = olen -i;
			if (sys->write(wrfd, obuf[i:i+step], step) != step) {
				if (debug)
					sys->print("serial tx error: %r\n");
				return nil;
			}

			# get the echo
			reply = nbread(200, step);
			if (reply == nil || len reply != step) {
				err = "short echo";
				ok = 0;
			}

			# check the echo
			for (ei := 0; ok && ei < step; ei++) {
				if (reply[ei] != obuf[i+ei]) {
					err = "bad echo";
					ok = 0;
				}
			}
		}

		# get the reply
		if (ok) {
			if (needr == 0)
				return nil;
			if (needr == -1) {
				# just get what we can
				needr = TX_HDR + TX_CKSM;
				reply = nbread(300, 1024);
			} else {
				reply = nbread(200, needr);
			}
			if (len reply < needr) {
				err = "short reply";
				ok = 0;
			}
		}
		# check the reply
		if (ok && reply[0] == byte 16r55 && reply[1] == byte 16rff && reply[2] == byte 0) {
			cksum := int reply[len reply -TX_CKSM];
			val := reply[TX_HDR:len reply -TX_CKSM];
			r := array [len val / 2] of byte;
			sum := 0;
			for (i = 0; i < len r; i++) {
				r[i] = val[i*2];
				sum += int r[i];
			}
			if (cksum == (sum & 16rff)) {
				return r;
			}
			ok = 0;
			err = "bad cksum";
		} else if (ok) {
			ok = 0;
			err = "reply header error";
		}
		if (debug && ok == 0 && err != nil) {
			sys->print("try %d %s: ", try, err);
			hexdump(reply);
		}
		consume();
	}
	return nil;
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
hexdump(data : array of byte)
{
	for (i := 0; i < len data; i++)
		sys->print("%.2x ", int data[i]);
	sys->print("\n");
}

