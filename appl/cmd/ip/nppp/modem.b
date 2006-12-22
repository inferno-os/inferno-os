implement Modem;

#
# Copyright © 1998-2001 Vita Nuova Holdings Limited.  All rights reserved.
#

include "sys.m";
	sys: Sys;

include "lock.m";
	lock: Lock;
	Semaphore: import lock;

include "draw.m";

include "modem.m";

hangupcmd := "ATH0";		# was ATZH0 but some modem versions on Umec hung on ATZ

# modem return codes
Ok, Success, Failure, Abort, Noise, Found: con iota;

maxspeed: con 115200;

#
#  modem return messages
#
Msg: adt {
	text: 		string;
	code: 		int;
};

msgs: array of Msg = array [] of {
	("OK", 			Ok),
	("NO CARRIER", 	Failure),
	("ERROR", 		Failure),
	("NO DIALTONE", Failure),
	("BUSY", 		Failure),
	("NO ANSWER", 	Failure),
	("CONNECT", 	Success),
};

kill(pid: int)
{
	fd := sys->open("/prog/"+string pid+"/ctl", Sys->OWRITE);
	if(fd == nil || sys->fprint(fd, "kill") < 0)
		sys->print("modem: can't kill %d: %r\n", pid);
}

#
# prepare a modem port
#
openserial(d: ref Device): string
{
	d.data = nil;
	d.ctl = nil;

	d.data = sys->open(d.local, Sys->ORDWR);
	if(d.data == nil)
		return sys->sprint("can't open %s: %r", d.local);

	d.ctl = sys->open(d.local+"ctl", Sys->ORDWR);
	if(d.ctl == nil)
		return sys->sprint("can't open %s: %r", d.local+"ctl");

	d.speed = maxspeed;
	d.avail = nil;
	return nil;
}

#
# shut down the monitor (if any) and return the connection
#

Device.close(m: self ref Device): ref Sys->Connection
{
	if(m.pid != 0){
		kill(m.pid);
		m.pid = 0;
	}
	if(m.data == nil)
		return nil;
	mc := ref sys->Connection(m.data, m.ctl, nil);
	m.ctl = nil;
	m.data = nil;
	return mc;
}

#
# Send a string to the modem
#

Device.send(d: self ref Device, x: string): string
{
	a := array of byte x;
	f := sys->write(d.data, a, len a);
	if(f != len a) {
		# let's attempt to close & reopen the modem
		d.close();
		err := openserial(d);
		if(err != nil)
			return err;
		f = sys->write(d.data,a, len a);
		if(f < 0)
			return sys->sprint("%r");
		if(f != len a)
			return "short write";
	}
	if(d.trace)
		sys->print("->%s\n",x);
	return nil;
}

#
#  apply a string of commands to modem & look for a response
#

apply(d: ref Device, s: string, substr: string, secs: int): int
{
	m := Ok;
	buf := "";
	for(i := 0; i < len s; i++){
		c := s[i];
		buf[len buf] = c;		# assume no Unicode
		if(c == '\r' || i == (len s -1)){
			if(c != '\r')
				buf[len buf] = '\r';
			if(d.send(buf) != nil)
				return Abort;
			(m, nil) = readmsg(d, secs, substr);
			buf = "";
		}
	}
	return m;
}

#
#  get modem into command mode if it isn't already
#
GUARDTIME: con 1100;	# usual default for S12=50 in units of 1/50 sec; allow 100ms fuzz

attention(d: ref Device): int
{
	for(i := 0; i < 3; i++){
		if(apply(d, hangupcmd, nil, 2) == Ok)
			return Ok;
		sys->sleep(GUARDTIME);
		if(d.send("+++") != nil)
			return Abort;
		sys->sleep(GUARDTIME);
		(nil, msg) := readmsg(d, 0, nil);
		if(msg != nil && d.trace)
			sys->print("status: %s\n", msg);
	}
	return Failure;
}

#
#  apply a command type
#

applyspecial(d: ref Device, cmd: string): int
{
	if(cmd == nil)
		return Failure;
	return apply(d, cmd, nil, 2);
}

#
#  hang up any connections in progress and close the device
#
Device.onhook(d: self ref Device)
{
	# hang up the modem
	monitoring(d);
	if(attention(d) != Ok)
		sys->print("modem: no attention\n");

	# hangup the stream (eg, for ppp) and toggle the lines to the modem
	if(d.ctl != nil) {
		sys->fprint(d.ctl,"d0\n");
		sys->fprint(d.ctl,"r0\n");
		sys->fprint(d.ctl, "h\n");	# hangup on native serial 
		sys->sleep(250);
		sys->fprint(d.ctl,"r1\n");
		sys->fprint(d.ctl,"d1\n");
	}

	d.close();
}

#
# does string s contain t anywhere?
#

contains(s, t: string): int
{
	if(t == nil)
		return 1;
	if(s == nil)
		return 0;
	n := len t;
	for(i := 0; i+n <= len s; i++)
		if(s[i:i+n] == t)
			return 1;
	return 0;
}

#
#  read till we see a message or we time out
#
readmsg(d: ref Device, secs: int, substr: string): (int, string)
{
	found := 0;
	msecs := secs*1000;
	limit := 1000;		# pretty arbitrary
	s := "";

	for(start := sys->millisec(); sys->millisec() <= start+msecs;){
		a := d.getinput(1);
		if(len a == 0){
			if(limit){
				sys->sleep(1);
				continue;
			}
			break;
		}
		if(a[0] == byte '\n' || a[0] == byte '\r' || limit == 0){
			if (len s) {
				if (s[(len s)-1] == '\r')
					s[(len s)-1] = '\n';
				sys->print("<-%s\n",s);
			}
			if(substr != nil && contains(s, substr))
				found = 1;
			for(k := 0; k < len msgs; k++)
				if(len s >= len msgs[k].text &&
				   s[0:len msgs[k].text] == msgs[k].text){
					if(found)
						return (Found, s);
					return (msgs[k].code, s);
				}
			start = sys->millisec();
			s = "";
			continue;
		}
		s[len s] = int a[0];
		limit--;
	}
	s = "no response from modem";
	if(found)
		return (Found, s);

	return (Noise, s);
}

#
#  get baud rate from a connect message
#

getspeed(msg: string, speed: int): int
{
	p := msg[7:];	# skip "CONNECT"
	while(p[0] == ' ' || p[0] == '\t')
		p = p[1:];
	s := int p;
	if(s <= 0)
		return speed;
	else
		return s;
}

#
#  set speed and RTS/CTS modem flow control
#

setspeed(d: ref Device, baud: int)
{
	if(d != nil && d.ctl != nil){
		sys->fprint(d.ctl, "b%d", baud);
		sys->fprint(d.ctl, "m1");
	}
}

monitoring(d: ref Device)
{
	# if no monitor then spawn one
	if(d.pid == 0) {
		pidc := chan of int;
		spawn monitor(d, pidc, nil);
		d.pid = <-pidc;
	}
}

#
#  a process to read input from a modem.
#
monitor(d: ref Device, pidc: chan of int, errc: chan of string)
{
	err := openserial(d);
	pidc <-= sys->pctl(0, nil);
	if(err != nil && errc != nil)
		errc <-= err;
	a := array[Sys->ATOMICIO] of byte;
	for(;;) {
		d.lock.obtain();
		d.status = "Idle";
		d.remote = "";
		setspeed(d, d.speed);
		d.lock.release();
		# shuttle bytes
		while((n := sys->read(d.data, a, len a)) > 0){
			d.lock.obtain();
			if (len d.avail < Sys->ATOMICIO) {
				na := array[len d.avail + n] of byte;
				na[0:] = d.avail[0:];
				na[len d.avail:] = a[0:n];
				d.avail = na;
			}				
			d.lock.release();
		}
		# on an error, try reopening the device
		d.data = nil;
		d.ctl = nil;
		err = openserial(d);
		if(err != nil && errc != nil)
			errc <-= err;
	}
}

#
#  return up to n bytes read from the modem by monitor()
#
Device.getinput(d: self ref Device, n: int): array of byte
{
	if(d==nil || n <= 0)
		return nil;
	a: array of byte;
	d.lock.obtain();
	if(len d.avail != 0){
		if(n > len d.avail)
			n = len d.avail;
		a = d.avail[0:n];
		d.avail = d.avail[n:];
	}
	d.lock.release();
	return a;
}

Device.getc(d: self ref Device, msec: int): int
{
	start := sys->millisec();
	while((b  := d.getinput(1)) == nil) {
		if (msec && sys->millisec() > start+msec)
			return 0;
		sys->sleep(1);
	}
	return int b[0];
}

init(): string
{
	sys = load Sys Sys->PATH;
	lock = load Lock Lock->PATH;
	if(lock == nil)
		return sys->sprint("can't load %s: %r", Lock->PATH);
	lock->init();
	return nil;
}

Device.new(modeminfo: ref ModemInfo, trace: int): ref Device
{
	d := ref Device;
	d.lock = Semaphore.new();
	d.local = modeminfo.path;
	d.pid = 0;
	d.speed = 0;
	d.t = *modeminfo;
	if(d.t.hangup == nil)
		d.t.hangup = hangupcmd;
	d.trace = trace | 1;	# always trace for now
	return d;
}

#
#  dial a number
#
Device.dial(d: self ref Device, number: string): string
{
	monitoring(d);

	# modem type should already be established, but just in case
	if(d.trace)
		sys->print("modem: attention\n");
	x := attention(d);
	if (x != Ok && d.trace)
		return "bad response from modem";
	#
	#  extended Hayes commands, meaning depends on modem
	#
	sys->print("modem: init\n");
	if(d.t.country != nil)
		applyspecial(d, d.t.country);

	if(d.t.init != nil)
		applyspecial(d, d.t.init);

	if(d.t.other != nil)
		applyspecial(d, d.t.other);

	applyspecial(d, d.t.errorcorrection);

	compress := Abort;
	if(d.t.mnponly != nil)
			compress = applyspecial(d, d.t.mnponly);
	if(d.t.compression != nil)
			compress = applyspecial(d, d.t.compression);

	rateadjust := Abort;
	if(compress != Ok)
		rateadjust = applyspecial(d, d.t.rateadjust);
	applyspecial(d, d.t.flowctl);

	# finally, dialout
	if(d.trace)
		sys->print("modem: dial\n");
	if((dt := d.t.dialtype) == nil)
		dt = "ATDT";
	err := d.send(sys->sprint("%s%s\r", dt, number));
	if(err != nil){
		if(d.trace)
			sys->print("modem: can't dial %s: %s\n", number, err);
		return err;
	}

	(i, msg) := readmsg(d, 120, nil);
	if(i != Success){
		if(d.trace)
			sys->print("modem: modem error reply: %s\n", msg);
		return msg;
	}

	connectspeed := getspeed(msg, d.speed);

	# change line rate if not compressing
	if(rateadjust == Ok)
		setspeed(d, connectspeed);

	if(d.ctl != nil){
		if(d != nil)
			sys->fprint(d.ctl, "s%d", connectspeed);	# set DCE speed (if device implements it)
		sys->fprint(d.ctl, "c1");	# enable CD monitoring
	}

	return nil;
}

dumpa(a: array of byte): string
{
	s := "";
	for(i:=0; i<len a; i++){
		b := int a[i];
		if(b >= ' ' && b < 16r7f)
			s[len s] = b;
		else
			s += sys->sprint("\\%.2x", b);
	}
	return s;
}
