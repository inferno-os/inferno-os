implement Modem;

include "sys.m";
	sys: Sys;

include "lock.m";
	lock: Lock;
	Semaphore: import lock;

include "draw.m";

include "modem.m";

hangupcmd := "ATH0";		# was ATZH0 but some modem versions on Umec hung on ATZ (BUG: should be in modeminfo)

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
	fd := sys->open("#p/"+string pid+"/ctl", Sys->OWRITE);
	if(fd == nil || sys->fprint(fd, "kill") < 0)
		sys->print("modem: can't kill %d: %r\n", pid);
}

#
# prepare a modem port
#
openserial(d: ref Device)
{
	if (d==nil) {
		raise "fail: device not initialized";
		return;
	}

	d.data = nil;
	d.ctl = nil;

	d.data = sys->open(d.local, Sys->ORDWR);
	if(d.data == nil) {
		raise "fail: can't open "+d.local;
		return;
	}

	d.ctl = sys->open(d.local+"ctl", Sys->ORDWR);
	if(d.ctl == nil) {
		raise "can't open "+d.local+"ctl";
		return;
	}

	d.speed = maxspeed;
	d.avail = nil;
}

#
# shut down the monitor (if any) and return the connection
#

close(m: ref Device): ref Sys->Connection
{
	if(m == nil)
		return nil;
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

send(d: ref Device, x: string): int
{
	if (d == nil)
		return -1;
	
	a := array of byte x;
	f := sys->write(d.data, a, len a);
	if (f < 0) {
		# let's attempt to close & reopen the modem
		close(d);
		openserial(d);
		f = sys->write(d.data,a, len a);
	}
	sys->print("->%s\n",x);
	return f;
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
			if(send(d, buf) < 0)
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
		if(send(d, "+++") < 0) 
			return Abort;
		sys->sleep(GUARDTIME);
		(nil, msg) := readmsg(d, 0, nil);
		if(msg != nil)
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
onhook(d: ref Device)
{
	if(d == nil)
		return;

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

	close(d);
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
	if (d == nil)
		return (Abort, "device not initialized");
	found := 0;
	secs *= 1000;
	limit := 1000;		# pretty arbitrary
	s := "";

	for(start := sys->millisec(); sys->millisec() <= start+secs;){
		a := getinput(d,1);
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
	s = "No response from modem";
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

monitoring(d: ref Device)
{
	# if no monitor then spawn one
	if(d.pid == 0) {
		pidc := chan of int;
		spawn monitor(d, pidc);
		d.pid = <-pidc;
	}
}

#
#  a process to read input from a modem.
#
monitor(d: ref Device, pidc: chan of int)
{
	openserial(d);
	pidc <-= sys->pctl(0, nil);	# pidc can be written once only.
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
		openserial(d);
	}
}

#
#  return up to n bytes read from the modem by monitor()
#
getinput(d: ref Device, n: int): array of byte
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

getc(m: ref Device, timo: int): int
{
	start := sys->millisec();
	while((b  := getinput(m, 1)) == nil) {
		if (timo && sys->millisec() > start+timo)
			return 0;
		sys->sleep(1);
	}
	return int b[0];
}

init(modeminfo: ref ModemInfo): ref Device
{
	if (sys == nil) {
		sys = load Sys Sys->PATH;
		lock = load Lock Lock->PATH;
		if (lock == nil) {
			raise "fail: Couldn't load lock module";
			return nil;
		}
		lock->init();
	}

	newdev := ref Device;
	newdev.lock = Semaphore.new();
	newdev.local = modeminfo.path;
	newdev.pid = 0;
	newdev.t = modeminfo;

	return newdev;
}


#
#  dial a number
#
dial(d: ref Device, number: string)
{
	if (d==nil) {
		raise "fail: Device not initialized";
		return;
	}

	monitoring(d);

	# modem type should already be established, but just in case
	sys->print("Attention\n");
	x := attention(d);
	if (x != Ok)
		sys->print("Attention failed\n");
	#
	#  extended Hayes commands, meaning depends on modem (VGA all over again)
	#
	sys->print("Init\n");
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
	sys->print("Dialing\n");
	if((dt := d.t.dialtype) == nil)
		dt = "ATDT";
	if(send(d, sys->sprint("%s%s\r", dt, number)) < 0) {
		raise "can't dial "+number;
		return;
	}

	(i, msg) := readmsg(d, 120, nil);
	if(i != Success) {
		raise "fail: "+msg;
		return;
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
}
