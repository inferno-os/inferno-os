# Model 1
implement Clockface;

include "sys.m";
	sys: Sys;

include "draw.m";

Clockface: module {
	init:	fn(ctxt: ref Draw->Context, argv: list of string);
};

hmpath:	con "motor/0";		# hour-hand motor
mmpath:	con "motor/2";		# minute-hand motor
allmpath:	con "motor/012";	# all motors (for stopall msg)

hbpath:	con "sensor/0";	# hour-hand sensor
mbpath:	con "sensor/2";	# minute-hand sensor
lspath:	con "sensor/1";	# light sensor;

ONTHRESH:	con 780;		# light sensor thresholds
OFFTHRESH:	con 740;
NCLICKS:		con 120;
MINCLICKS:	con 2;		# min number of clicks required to stop a motor

Hand: adt {
	motor:	ref Sys->FD;
	sensor:	ref Sys->FD;
	fwd:		array of byte;
	rev:		array of byte;
	stop:		array of byte;
	pos:		int;
	time:		int;
};

lightsensor:	ref Sys->FD;
allmotors:		ref Sys->FD;
hourhand:	ref Hand;
minutehand:	ref Hand;
timedata:		array of byte;
readq:		list of Sys->Rread;
verbose		:= 0;

init(nil: ref Draw->Context, argv: list of string)
{
	sys = load Sys Sys->PATH;

	argv = tl argv;
	if (len argv > 0 && hd argv == "-v") {
		verbose++;
		argv = tl argv;
	}
	if (len argv != 1) {
		sys->print("usage: [-v] legodir\n");
		raise "fail:usage";
	}
	legodir := hd argv + "/";

	# set up our control file
	f2c := sys->file2chan("/chan", "clockface");
	if (f2c == nil) {
		sys->print("cannot create clockface channel: %r\n");
		return;
	}

	# get the motor files
	log("opening motor files");
	hm := sys->open(legodir + hmpath, Sys->OWRITE);
	mm := sys->open(legodir +mmpath, Sys->OWRITE);
	allmotors = sys->open(legodir + allmpath, Sys->OWRITE);
	if (hm == nil || mm == nil || allmotors == nil) {
		sys->print("cannot open motor files\n");
		raise "fail:error";
	}

	# get the sensor files
	log("opening sensor files");
	hb := sys->open(legodir + hbpath, Sys->ORDWR);
	mb := sys->open(legodir + mbpath, Sys->ORDWR);
	lightsensor = sys->open(legodir + lspath, Sys->ORDWR);

	if (hb == nil || mb == nil) {
		sys->print("cannot open sensor files\n");
		raise "fail:error";
	}

	hourhand = ref Hand(hm, hb, array of byte "r7", array of byte "f7", array of byte "s7", 0, 00);
	minutehand = ref Hand(mm, mb, array of byte "f7", array of byte "r7", array of byte "s7", 0, 00);

	log("setting sensor types");
	setsensortypes(hourhand, minutehand, lightsensor);

	# get the hands to 12 o'clock
	reset();
	log(sys->sprint("H %d, M %d", hourhand.pos, minutehand.pos));
	spawn srvlink(f2c);
}

srvlink(f2c: ref Sys->FileIO)
{
	tick := chan of int;
	spawn eggtimer(tick);

	for (;;) alt {
	(nil, count, fid, rc) := <-f2c.read =>
		if (rc == nil) {
			close(fid);
			continue;
		}
		if (count < len timedata) {
			rc <-= (nil, "read too small");
			continue;
		}
		if (open(fid))
			readq = rc :: readq;
		else
			rc <-= (timedata, nil);

	(nil, data, fid, wc) := <-f2c.write =>
		if (wc == nil) {
			close(fid);
			continue;
		}
		(nil, toks) := sys->tokenize(string data, ": \t\n");
		if (len toks == 2) {
			wc <-= (len data, nil);
			hourhand.time = int hd toks % 12;
			minutehand.time = int hd tl toks % 60;
			sethands();
		} else if (len toks == 1 && hd toks == "reset") {
			wc <-= (len data, nil);
			reset();
		} else
			wc <-= (0, "syntax is hh:mm or `reset'");

	<-tick =>
		if (++minutehand.time == 60) {
			minutehand.time = 0;
			hourhand.time++;
			hourhand.time %= 12;
		}
		sethands();
	}
}

readers: list of int;

open(fid: int): int
{
	for (rlist := readers; rlist != nil; rlist = tl rlist)
		if (hd rlist == fid)
			return 1;
	readers = fid :: readers;
	return 0;
}

close(fid: int)
{
	rlist: list of int;
	for (; readers != nil; readers = tl readers)
		if (hd readers != fid)
			rlist = hd readers :: rlist;
	readers = rlist;
}

eggtimer(tick: chan of int)
{
	next := sys->millisec();
	for (;;) {
		next += 60*1000;
		sys->sleep(next - sys->millisec());
		tick <-= 1;
	}
}

clicks(): (int, int)
{
	h := hourhand.time;
	m := minutehand.time;
	h = ((h * NCLICKS) / 12) + ((m * NCLICKS) / (12 * 60));
	m = (m * NCLICKS) / 60;
	return (h, m);
}

sethands()
{
	timedata = array of byte sys->sprint("%2d:%.2d\n", (hourhand.time+11) % 12 + 1, minutehand.time);
	for (; readq != nil; readq = tl readq)
		alt {
		(hd readq) <-= (timedata, nil) => ;
		* => ;
		}

	(hclk, mclk) := clicks();
	for (i := 0; i < 6; i++) {
		hdelta := clickdistance(hourhand.pos, hclk, NCLICKS);
		mdelta := clickdistance(minutehand.pos, mclk, NCLICKS);
		if (hdelta != 0)
			sethand(hourhand, hdelta);
		else if (mdelta != 0)
			sethand(minutehand, mdelta);
		else
			break;
	}
	releaseall();
}

clickdistance(start, stop, mod: int): int
{
	if (start > stop)
		stop += mod;
	d := (stop - start) % mod;
	if (d > mod/2)
		d -= mod;
	return d;
}

setsensortypes(h1, h2: ref Hand, ls: ref Sys->FD)
{
	button := array of byte "b0";
	light := array of byte "l0";
	sys->write(h1.sensor, button, len button);
	sys->write(h2.sensor, button, len button);
	sys->write(ls, light, len light);
}

HOUR_ADJUST: con 1;
MINUTE_ADJUST: con 2;

reset()
{
	# run the motors until hands are well away from 12 o'clock (below threshold)

	val := readsensor(lightsensor);
	if (val > OFFTHRESH) {
		triggered := chan of int;
		log("wait for hands clear of light sensor");
		spawn lightwait(triggered, lightsensor, 0);
		forward(minutehand);
		reverse(hourhand);
		val = <-triggered;
		stopall();
		log("sensor "+string val);
	}

	resethand(hourhand);
	hourhand.pos += HOUR_ADJUST;
	resethand(minutehand);
	minutehand.pos += MINUTE_ADJUST;
	sethands();
}

sethand(hand: ref Hand, delta: int)
{
	triggered := chan of int;
	dir := 1;
	if (delta < 0) {
		dir = -1;
		delta = -delta;
	}
	if (delta > MINCLICKS) {
		spawn handwait(triggered, hand, delta - MINCLICKS);
		if (dir > 0)
			forward(hand);
		else
			reverse(hand);
		<-triggered;
		stop(hand);
		hand.pos += dir * readsensor(hand.sensor);
	} else {
		startval := readsensor(hand.sensor);
		if (dir > 0)
			forward(hand);
		else
			reverse(hand);
		stop(hand);
		hand.pos += dir * (readsensor(hand.sensor) - startval);
	}
	if (hand.pos < 0)
		hand.pos += NCLICKS;
	hand.pos %= NCLICKS;
}

resethand(hand: ref Hand)
{
	triggered := chan of int;
	val: int;

	# run the hand until the light sensor is above threshold
	log("running hand until light sensor activated");
	spawn lightwait(triggered, lightsensor, 1);
	forward(hand);
	val = <-triggered;
	stop(hand);
	log("sensor "+string val);

	startclick := readsensor(hand.sensor);

	# advance until light sensor drops below threshold
	log("running hand until light sensor clear");
	spawn lightwait(triggered, lightsensor, 0);
	forward(hand);
	val = <-triggered;
	stop(hand);
	log("sensor "+string val);
	
	stopclick := readsensor(hand.sensor);
	nclicks := stopclick - startclick;
	log(sys->sprint("startpos %d, endpos %d (nclicks %d)", startclick, stopclick, nclicks));

	hand.pos = nclicks/2;
}

stop(hand: ref Hand)
{
	sys->seek(hand.motor, big 0, Sys->SEEKSTART);
	sys->write(hand.motor, hand.stop, len hand.stop);
}

stopall()
{
	msg := array of byte "s0s0s0";
	sys->seek(allmotors, big 0, Sys->SEEKSTART);
	sys->write(allmotors, msg, len msg);
}

releaseall()
{
	msg := array of byte "F0F0F0";
	sys->seek(allmotors, big 0, Sys->SEEKSTART);
	sys->write(allmotors, msg, len msg);
}

forward(hand: ref Hand)
{
	sys->seek(hand.motor, big 0, Sys->SEEKSTART);
	sys->write(hand.motor, hand.fwd, len hand.fwd);
}

reverse(hand: ref Hand)
{
	sys->seek(hand.motor, big 0, Sys->SEEKSTART);
	sys->write(hand.motor, hand.rev, len hand.rev);
}

readsensor(fd: ref Sys->FD): int
{
	buf := array[4] of byte;
	sys->seek(fd, big 0, Sys->SEEKSTART);
	n := sys->read(fd, buf, len buf);
	if (n <= 0)
		return -1;
	return int string buf[:n];
}

handwait(reply: chan of int, hand: ref Hand, clicks: int)
{
	blk := array of byte ("b" + string clicks);
	log("handwait "+string blk);
	sys->seek(hand.sensor, big 0, Sys->SEEKSTART);
	if (sys->write(hand.sensor, blk, len blk) != len blk)
		sys->print("handwait write error: %r\n");
	reply <-= readsensor(hand.sensor);
}

lightwait(reply: chan of int, fd: ref Sys->FD, on: int)
{
	thresh := "";
	if (on)
		thresh = "l>" + string ONTHRESH;
	else
		thresh = "l<" + string OFFTHRESH;
	blk := array of byte thresh;
	log("lightwait "+string blk);
	sys->seek(fd, big 0, Sys->SEEKSTART);
	sys->write(fd, blk, len blk);
	reply <-= readsensor(fd);
}

log(msg: string)
{
	if (verbose)
		sys->print("%s\n", msg);
}
