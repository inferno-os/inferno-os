implement mouse;
# ported from plan 9's aux/mouse

include "sys.m";
	sys: Sys;
	sprint, fprint, sleep: import sys;
include "draw.m";

stderr: ref Sys->FD;

mouse: module {
	init: fn(ctxt: ref Draw->Context, argv: list of string);
};

Sleep500: 	con 500;
Sleep1000:	con 1000;
Sleep2000:	con 2000;
TIMEOUT: 	con 5000;
fail := "fail:";
usage()
{
	fprint(stderr, "usage: mouse [type]\n");
	raise fail+"usage";
}

write(fd: ref Sys->FD, buf: array of byte, n: int): int
{
	if (debug) {
		sys->fprint(stderr, "write(%d) ", fd.fd);
		for (i := 0; i < len buf; i++) {
			sys->fprint(stderr, "'%c' ", int buf[i]);
		}
		sys->fprint(stderr, "\n");
	}
	return sys->write(fd, buf, n);
}

speeds := array[] of {"b1200", "b2400", "b4800", "b9600"};
debug := 0;
can9600 := 0;

init(nil: ref Draw->Context, argv: list of string)
{
	sys = load Sys Sys->PATH;
	stderr = sys->fildes(2);

{
	if (argv == nil)
		usage();

	argv = tl argv;


	while (argv != nil && len (arg := hd argv) > 1 && arg[0] == '-') {
		case arg[1] {
		'D' =>
			debug = 1;
		* =>
			usage();
		}
		argv = tl argv;
	}
	if (len argv > 1)
		usage();

	p: string;
	if (argv == nil)
		p = mouseprobe();
	else
		p = hd argv;
	if (p != nil && !isnum(p)) {
		mouseconfig(p);
		return;
	}
	if (p == nil) {
		serial("0");
		serial("1");
		fprint(stderr, "mouse: no mouse detected\n");
	} else {
		err := serial(p);
		fprint(stderr, "mouse: %s\n", err);
	}
}
exception{
	# this could be taken out so the shell could
	# get an indication that the command has failed.
	"fail:*" =>
		;
}
}

# probe for a serial mouse on port p;
# return some an error string if not found. 
serial(p: string): string
{
	baud := 0;
	f := sys->sprint("/dev/eia%sctl", p);
	if ((ctl := sys->open(f, Sys->ORDWR)) == nil)
		return sprint("can't open %s - %r\n", f);

	f = sys->sprint("/dev/eia%s", p);
	if ((data := sys->open(f, Sys->ORDWR)) == nil)
		return sprint("can't open %s - %r\n", f);

	if(debug) fprint(stderr, "ctl=%d, data=%d\n", ctl.fd, data.fd);

	if(debug) fprint(stderr, "MorW()\n");
	mtype := MorW(ctl, data);
	if (mtype == 0) {
		if(debug) return "no mouse detected";

		if(debug) fprint(stderr, "C()\n");
		mtype = C(ctl, data);
	}
	if (mtype == 0)
		return "no mouse detected on port "+p;

	if(debug)fprint(stderr, "done eia setup\n");
	mt := "serial " + p;
	case mtype {
	* =>
		return "unknown mouse type";
	'C' =>
		if(debug) fprint(stderr, "Logitech 5 byte mouse\n");
		Cbaud(ctl, data, baud);
	'W' =>
		if(debug) fprint(stderr, "Type W mouse\n");
		Wbaud(ctl, data, baud);
	'M' =>
		if(debug) fprint(stderr, "Microsoft compatible mouse\n");
		mt += " M";
	}
	mouseconfig(mt);
	return nil;
}

mouseconfig(mt: string)
{
	if ((conf := sys->open("/dev/mousectl", Sys->OWRITE)) == nil) {
		fprint(stderr, "mouse: can't open mousectl - %r\n");
		raise fail+"open mousectl";
	}
	if(debug) fprint(stderr, "opened mousectl\n");
	if (write(conf, array of byte mt, len array of byte mt) < 0) {
		fprint(stderr, "mouse: error setting mouse type - %r\n");
		raise fail+"write conf";
	}
	fprint(stderr, "mouse: configured as '%s'\n", mt);
}

isnum(s: string): int
{
	for (i := 0; i < len s; i++)
		if (s[i] < '0' || s[i] > '9')
			return 0;
	return 1;
}

mouseprobe(): string
{
	if ((probe := sys->open("/dev/mouseprobe", Sys->OREAD)) == nil) {
		fprint(stderr, "mouse: can't open mouseprobe - %r\n");
		return nil;
	}
	buf := array[64] of byte;
	n := sys->read(probe, buf, len buf);
	if (n <= 0)
		return nil;
	if (buf[n - 1] == byte '\n')
		n--;
	if(debug) fprint(stderr, "mouse probe detected mouse of type '%s'\n", string buf[0:n]);
	return string buf[0:n];
}

readbyte(fd: ref Sys->FD): int
{
	buf := array[1] of byte;
	(n, err) := timedread(fd, buf, 1, 200);
	if (n < 0) {
		if (err == nil)
			return -1;
		fprint(stderr, "mouse: readbyte failed - %s\n", err);
		raise fail+"read failed";
	}
	return int buf[0];
}

slowread(fd: ref Sys->FD, buf: array of byte, nbytes: int, msg: string): int
{
	for (i := 0; i < nbytes; i++) {
		if ((c := readbyte(fd)) == -1)
			break;
		buf[i] = byte c;
	}
	if(debug) dumpbuf(buf[0:i], msg);
	return i;
}

dumpbuf(buf: array of byte, msg: string)
{
	sys->fprint(stderr, "%s", msg);
	for (i := 0; i < len buf; i++)
		sys->fprint(stderr, "#%ux ", int buf[i]);
	sys->fprint(stderr, "\n");
}

toggleRTS(fd: ref Sys->FD)
{
	# reset the mouse (toggle RTS)
	# must be >100mS
	writes(fd, "d0");
	sleep(10);
	writes(fd, "r0");
	sleep(Sleep500);
	writes(fd, "d1");
	sleep(10);
	writes(fd, "r1");
	sleep(Sleep500);
}

setupeia(fd: ref Sys->FD, baud, bits: string)
{
	# set the speed to 1200/2400/4800/9600 baud,
	# 7/8-bit data, one stop bit and no parity

	(abaud, abits) := (array of byte baud, array of byte bits);
	if(debug)sys->fprint(stderr, "setupeia(%s,%s)\n", baud, bits);
	write(fd, abaud, len abaud);
	write(fd, abits, len abits);
	writes(fd, "s1");
	writes(fd, "pn");
}

# check for types M, M3 & W
#
# we talk to all these mice using 1200 baud

MorW(ctl, data: ref Sys->FD): int
{
	# set up for type M, V or W
	# flush any pending data

	setupeia(ctl, "b1200", "l7");
	toggleRTS(ctl);
	if(debug)sys->fprint(stderr, "toggled RTS\n");

	buf := array[256] of byte;
	while (slowread(data, buf, len buf, "flush: ") > 0)
		;
	if(debug) sys->fprint(stderr, "done slowread\n");
	toggleRTS(ctl);

	# see if there's any data from the mouse
	# (type M, V and W mice)
	c := slowread(data, buf, len buf, "check M: ");
	
	# type M, V and W mice return "M" or "M3" after reset.
	# check for type W by sending a 'Send Standard Configuration'
	# command, "*?".
	if (c > 0 && int buf[0] == 'M') {
		writes(data, "*?");
		c = slowread(data, buf, len buf, "check W: ");
		# 4 bytes back indicates a type W mouse
		if (c == 4) {
			if (int buf[1] & (1<<4))
				can9600 = 1;
			setupeia(ctl, "b1200", "l8");
			writes(data, "*U");
			slowread(data, buf, len buf, "check W: ");
			return 'W';
		}
		return 'M';
	}
	return 0;
}

# check for type C by seeing if it responds to the status
# command "s".  the mouse is at an unknown speed so we
# have to check all possible speeds.
C(ctl, data: ref Sys->FD): int
{
	buf := array[256] of byte;
	for (s := speeds; len s > 0; s = s[1:]) {
		if (debug) sys->print("%s\n", s[0]);
		setupeia(ctl, s[0], "l8");
		writes(data, "s");
		c := slowread(data, buf, len buf, "check C: ");
		if (c >= 1 && (int buf[0] & 16rbf) == 16r0f) {
			sleep(100);
			writes(data, "*n");
			sleep(100);
			setupeia(ctl, "b1200", "l8");
			writes(data, "s");
			c = slowread(data, buf, len buf, "recheck C: ");
			if (c >= 1 && (int buf[0] & 16rbf) == 16r0f) {
				writes(data, "U");
				return 'C';
			}
		}
		sleep(100);
	}
	return 0;
}

Cbaud(ctl, data: ref Sys->FD, baud: int)
{
	buf := array[2] of byte;
	case baud {
	0 or 1200 =>
		return;
	2400 =>
		buf[1] = byte 'o';
	4800 =>
		buf[1] = byte 'p';
	9600 =>
		buf[1] = byte 'q';
	* =>
		fprint(stderr, "mouse: can't set baud rate, mouse at 1200\n");
		return;
	}
	buf[0] = byte '*';
	sleep(100);
	write(data, buf, 2);
	sleep(100);
	write(data, buf, 2);
	setupeia(ctl, sys->sprint("b%d", baud), "l8");
}

Wbaud(ctl, data: ref Sys->FD, baud: int)
{
	case baud {
	0 or 1200 =>
		return;
	* =>
		if (baud == 9600 && can9600)
			break;
		fprint(stderr, "mouse: can't set baud rate, mouse at 1200\n");
		return;
	}
	writes(data, "*q");
	setupeia(ctl, "b9600", "l8");
	slowread(data, array[32] of byte, 32, "setbaud: ");
}
		
readproc(fd: ref Sys->FD, buf: array of byte, n: int,
				pidch: chan of int, ch: chan of (int, string))
{
	s: string;
	pidch <-= sys->pctl(0, nil);
	n = sys->read(fd, buf, n);
	if (n < 0)
		s = sys->sprint("read: %r");
	ch <-= (n, s);
}

sleepproc(t: int, pidch: chan of int, ch: chan of (int, string))
{
	pidch <-= sys->pctl(0, nil);
	sys->sleep(t);
	ch <-= (-1, nil);
}

timedread(fd: ref Sys->FD, buf: array of byte, n: int, t: int): (int, string)
{
	pidch := chan of int;
	retch := chan of (int, string);
	spawn readproc(fd, buf, n, pidch, retch);
	wpid := <-pidch;
	spawn sleepproc(t, pidch, retch);
	spid := <-pidch;

	(nr, err) := <-retch;
	if (nr == -1 && err == nil)
		kill(wpid);
	else
		kill(spid);
	return (nr, err);
}

kill(pid: int)
{
	if ((fd := sys->open("#p/"+string pid+"/ctl", Sys->OWRITE)) == nil) {
		fprint(stderr, "couldn't kill %d: %r\n", pid);
		return;
	}
	sys->write(fd, array of byte "kill", 4);
}

writes(fd: ref Sys->FD, s: string): int
{
	a := array of byte s;
	return write(fd, a, len a);
}

