implement Burn;

include "sys.m";
	sys: Sys;

include "draw.m";

include "bufio.m";
	bufio: Bufio;
	Iobuf: import bufio;

include "timers.m";
	timers: Timers;
	Timer: import timers;

include "string.m";
	str: String;

include "arg.m";

Burn: module
{
	init:	fn(nil: ref Draw->Context, nil: list of string);
};

Avr: adt {
	id:	int;
	rev:	int;
	flashsize:	int;
	eepromsize:	int;
	fusebytes:	int;
	lockbytes:	int;
	serfprog:	int;	# serial fuse programming support
	serlprog:	int;	# serial lockbit programming support
	serflread:	int;	# serial fuse/lockbit reading support
	commonlfr:	int;	# lockbits and fuses are combined
	sermemprog:	int;	# serial memory programming support
	pagesize:	int;
	eeprompagesize:	int;
	selftimed:	int;	# all instructions are self-timed
	fullpar:	int;	# part has full parallel interface
	polling:	int;	# polling can be used during SPI access
	fpoll:	int;	# flash poll value
	epoll1:	int;	# eeprom poll value 1
	epoll2:	int;	# eeprom poll value 2
	name:	string;
	signalpagel:	int;	# posn of PAGEL signal (16rD7 by default)
	signalbs2:	int;	# posn of BS2 signal (16rA0 by default)
};

F, T: con iota;
ATMEGA128: con 16rB2;	# 128k devices

avrs: array of Avr = array[] of {
	(ATMEGA128,  1, 131072, 4096, 3, 1, T,  T,  T,  F, T,  256, 8,  T,  T,  T,  16rFF, 16rFF, 16rFF, "ATmega128",   16rD7, 16rA0),
};

sfd: ref Sys->FD;
cfd: ref Sys->FD;
rd: ref Rd;
mib510 := 1;

Rd: adt {
	c:	chan of array of byte;
	pid:	int;
	fd:	ref Sys->FD;
	buf:	array of byte;
	new:	fn(fd: ref Sys->FD): ref Rd;
	read:	fn(r: self ref Rd, ms: int): array of byte;
	readn:	fn(r: self ref Rd, n: int, ms: int): array of byte;
	flush:	fn(r: self ref Rd);
	stop:	fn(r: self ref Rd);
	reader:	fn(r: self ref Rd, c: chan of int);
};

debug := 0;
verify := 0;
erase := 1;
ignore := 0;

init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	bufio = ckl(load Bufio Bufio->PATH, Bufio->PATH);
	str = ckl(load String String->PATH, String->PATH);
	timers = ckl(load Timers Timers->PATH, Timers->PATH);

	serial := "/dev/eia0";
	fuseext := -1;
	fuselow := -1;
	fusehigh := -1;
	arg := ckl(load Arg Arg->PATH, Arg->PATH);
	arg->init(args);
	arg->setusage("burn [-rD] [-d serialdev] file.out");
	while((o := arg->opt()) != 0)
		case o {
		'D' =>	debug++;
		'e' =>	erase = 0;
		'r' =>	verify = 1;
		'd' =>	serial = arg->earg();
		'i' =>	ignore = 1;
		'E' =>	fuseext = fuseval(arg->earg());
		'L' =>	fuselow = fuseval(arg->earg());
		'H' =>	fusehigh = fuseval(arg->earg());
		* =>	arg->usage();
		}
	args = arg->argv();
	if(len args != 1)
		arg->usage();
	arg = nil;

	sfile := hd args;
	fd := bufio->open(sfile, Sys->OREAD);
	if(fd == nil)
		err(sys->sprint("can't open %s: %r", sfile));
			
	timers->init(2);
	sfd = sys->open(serial, Sys->ORDWR);
	if(sfd == nil)
		err(sys->sprint("can't open %s: %r", "/dev/eia0"));
	cfd = sys->open(serial+"ctl", Sys->ORDWR);
	sys->fprint(cfd, "f");
	sys->fprint(cfd, "b115200");
	sys->fprint(cfd, "i8");
#	sys->fprint(cfd, "f\nb115200\ni8");
	rd = Rd.new(sfd);

	initialise();
	if(fuseext >= 0 || fuselow >= 0 || fusehigh >= 0){
		if(fuselow >= 0 && (fuselow & 16rF) == 0)
			err("don't program external clock");
		if(fuseext >= 0 && (fuseext & (1<<0)) == 0)
			err("don't program ATmega103 compatibility");
		if(fusehigh >= 0 && (fusehigh & (1<<7)) == 0)
			err("don't program OCDEN=0");
		if(fusehigh >= 0 && writefusehigh(fusehigh) >= 0)
			sys->print("set fuse high=%.2ux\n", fusehigh);
		if(fuselow >= 0 && writefuselow(fuselow) >= 0)
			sys->print("set fuse low=%.2ux\n", fuselow);
		if(fuseext >= 0 && writefuseext(fuseext) >= 0)
			sys->print("set fuse ext=%.2ux\n", fuseext);
		shutdown();
		exit;
	}

	if(!verify && erase){
		chiperase();
		sys->print("Erased flash\n");
	}

	totbytes := 0;
	while((l := fd.gets('\n')) != nil){
		(c, addr, data) := sdecode(l);
		if(c >= '1' && c <= '3'){
			if(verify){
				fdata := readflashdata(addr, len data);
				if(!eq(fdata, data))
					sys->print("mismatch: %d::%d at %4.4ux\n", len data, len fdata, addr);
			}else if(writeflashdata(addr, data) != len data)
				err("failed to program device");
			totbytes += len data;
		} else if(c == '0')
			sys->print("title: %q\n", string data);
	}
	if(!verify){
		flushpage();
		sys->print("Programmed %ud (0x%4.4ux) bytes\n", totbytes, totbytes);
	}

	shutdown();
}

ckl[T](m: T, s: string): T
{
	if(m == nil)
		err(sys->sprint("can't load %s: %r", s));
	return m;
}

fuseval(s: string): int
{
	(n, t) := str->toint(s, 16);
	if(t != nil || n < 0 || n > 255)
		err("illegal fuse value");
	return n;
}

cache: (int, array of byte);

readflashdata(addr: int, nbytes: int): array of byte
{
	data := array[nbytes] of byte;
	ia := addr;
	ea := addr+nbytes;
	while(addr < ea){
		(ca, cd) := cache;
		if(addr >= ca && addr < ca+len cd){
			n := nbytes;
			o := addr-ca;
			if(o+n > len cd)
				n = len cd - o;
			if(addr-ia+n > len data)
				n = len data - (addr-ia);
			data[addr-ia:] = cd[o:o+n];
			addr += n;
		}else{
			ca = addr & ~16rFF;
			cd = readflashpage(ca, 16r100);
			cache = (ca, cd);
		}
	}
	return data;
}

writeflashdata(addr: int, data: array of byte): int
{
	pagesize := avrs[0].pagesize;
	ia := addr;
	ea := addr+len data;
	while(addr < ea){
		(ca, cd) := cache;
		if(addr >= ca && addr < ca+len cd){
			n := len data;
			o := addr-ca;
			if(o+n > len cd)
				n = len cd - o;
			cd[o:] = data[0:n];
			addr += n;
			data = data[n:];
		}else{
			if(flushpage() < 0)
				break;
			cache = (addr & ~16rFF, array[pagesize] of {* => byte 16rFF});
		}
	}
	return addr-ia;
}

flushpage(): int
{
	(ca, cd) := cache;
	if(len cd == 0)
		return 0;
	cache = (0, nil);
	if(writeflashpage(ca, cd) != len cd)
		return -1;
	return len cd;
}
			
shutdown()
{
#	setisp(0);
	if(rd != nil){
		rd.stop();
		rd = nil;
	}
	if(timers != nil)
		timers->shutdown();
}

err(s: string)
{
	sys->fprint(sys->fildes(2), "burn: %s\n", s);
	shutdown();
	raise "fail:error";
}

dump(a: array of byte): string
{
	s := sys->sprint("[%d]", len a);
	for(i := 0; i < len a; i++)
		s += sys->sprint(" %.2ux", int a[i]);
	return s;
}

initialise()
{
	if(mib510){
		# MIB510-specific: switch rs232 to STK500
		for(i:=0; i<8; i++){
			setisp0(1);
			sys->sleep(10);
			rd.flush();
			if(setisp(1))
				break;
		}
		if(!setisp(1))
			err("no response from programmer");
	}
	resync();
	resync();
	if(!mib510){
		r := rpc(array[] of {Cmd_STK_GET_SIGN_ON}, 7);
		if(r != nil)
			sys->print("got: %q\n", string r);
	}
	r := readsig();
	if(len r > 0 && r[0] != byte 16rFF)
		sys->print("sig: %s\n", dump(r));
	(min, maj) := version();
	sys->print("Firmware version: %s.%s\n", min, maj);
	setdevice(avrs[0]);
	pgmon();
	r = readsig();
	sys->print("sig: %s\n", dump(r));
	pgmoff();
	if(len r < 3 || r[0] != byte 16r1e || r[1] != byte 16r97 || r[2] != byte 16r02)
		if(!ignore)
		err("unlikely response: check connections");

	# could set voltages here...
	sys->print("fuses: h=%.2ux l=%.2ux e=%.2ux\n", readfusehigh(), readfuselow(), readfuseext());
}

resync()
{
	for(i := 0; i < 8; i++){
		rd.flush();
		r := rpc(array[] of {Cmd_STK_GET_SYNC}, 0);
		if(r != nil)
			return;
	}
	err("lost sync with programmer");
}

getparam(p: byte): int
{
	r := rpc(array[] of {Cmd_STK_GET_PARAMETER, p}, 1);
	if(len r > 0)
		return int r[0];
	return -1;
}

version(): (string, string)
{
	maj := getparam(Parm_STK_SW_MAJOR);
	min := getparam(Parm_STK_SW_MINOR);
	if(mib510)
		return (sys->sprint("%c", maj), sys->sprint("%c", min));
	return (sys->sprint("%d", maj), sys->sprint("%d", min));
}

eq(a, b: array of byte): int
{
	if(len a != len b)
		return 0;
	for(i := 0; i < len a; i++)
		if(a[i] != b[i])
			return 0;
	return 1;
}

#
# Motorola S records
#

badsrec(s: string)
{
	err("bad S record: "+s);
}

hexc(c: int): int
{
	if(c >= '0' && c <= '9')
		return c-'0';
	if(c >= 'a' && c <= 'f')
		return c-'a'+10;
	if(c >= 'A' && c <= 'F')
		return c-'A'+10;
	return -1;
}

g8(s: string): int
{
	if(len s >= 2){
		c0 := hexc(s[0]);
		c1 := hexc(s[1]);
		if(c0 >= 0 && c1 >= 0)
			return (c0<<4) | c1;
	}
	return -1;
}

# S d len 
sdecode(s: string): (int, int, array of byte)
{
	while(len s > 0 && (s[len s-1] == '\r' || s[len s-1] == '\n'))
		s = s[0:len s-1];
	if(len s < 4 || s[0] != 'S')
		badsrec(s);
	l := g8(s[2:4]);
	if(l < 0)
		badsrec("length: "+s);
	if(2*l != len s - 4)
		badsrec("length: "+s);
	csum := l;
	na := 2;
	if(s[1] >= '1' && s[1] <= '3')
		na = s[1]-'1'+2;
	addr := 0;
	for(i:=0; i<na; i++){
		b := g8(s[4+i*2:]);
		if(b < 0)
			badsrec(s);
		csum += b;
		addr = (addr << 8) | b;
	}
	case s[1] {
	'0' or		# used as segment name (seems to be srec file name with TinyOS)
	'1' to '3' or	# data
	'5' or		# plot so far
	'7' to '9' =>	# end/start address
		;
	* =>
		badsrec("type: "+s);
	}
	data := array[l-na-1] of byte;
	for(i = 0; i < len data; i++){
		c := g8(s[4+(na+i)*2:]);
		csum += c;
		data[i] = byte c;
	}
	v := g8(s[4+l*2-2:]);
	csum += v;
	if((csum & 16rFF) != 16rFF)
		badsrec("checksum: "+s);
	return (s[1], addr, data);
}

#
# serial port
#

Rd.new(fd: ref Sys->FD): ref Rd
{
	r := ref Rd(chan[4] of array of byte, 0, fd, nil);
	c := chan of int;
	spawn r.reader(c);
	<-c;
	return r;
}

Rd.reader(r: self ref Rd, c: chan of int)
{
	r.pid = sys->pctl(0, nil);
	c <-= 1;
	for(;;){
		buf := array[258] of byte;
		n := sys->read(r.fd, buf, len buf);
		if(n <= 0){
			r.pid = 0;
			err(sys->sprint("read error: %r"));
		}
		if(debug)
			sys->print("<- %s\n", dump(buf[0:n]));
		r.c <-= buf[0:n];
	}
}

Rd.read(r: self ref Rd, ms: int): array of byte
{
	if((a := r.buf) != nil){
		r.buf = nil;
		return a;
	}
	t := Timer.start(ms);
	alt{
	a = <-r.c =>
		t.stop();
	    Acc:
		for(;;){
			sys->sleep(5);
			alt{
			b := <-r.c =>
				if(b == nil)
					break Acc;
				a = cat(a, b);
			* =>
				break Acc;
			}
		}
		return a;
	<-t.timeout =>
		return nil;
	}
}

Rd.readn(r: self ref Rd, n: int, ms: int): array of byte
{
	a: array of byte;

	while((need := n - len a) > 0){
		b := r.read(ms);
		if(b == nil)
			break;
		if(len b > need){
			r.buf = b[need:];
			b = b[0:need];
		}
		a = cat(a, b);
	}
	return a;
}

Rd.flush(r: self ref Rd)
{
	r.buf = nil;
	sys->sleep(5);
	for(;;){
		alt{
		<-r.c =>
			;
		* =>
			return;
		}
	}
}

Rd.stop(r: self ref Rd)
{
	pid := r.pid;
	if(pid){
		fd := sys->open("#p/"+string pid+"/ctl", Sys->OWRITE);
		if(fd != nil)
			sys->fprint(fd, "kill");
	}
}

cat(a, b: array of byte): array of byte
{
	if(len b == 0)
		return a;
	if(len a == 0)
		return b;
	c := array[len a + len b] of byte;
	c[0:] = a;
	c[len a:] = b;
	return c;
}

#
# STK500 communication protocol
#

STK_SIGN_ON_MESSAGE: con "AVR STK";   # Sign on string for Cmd_STK_GET_SIGN_ON

# Responses

Resp_STK_OK: con byte 16r10;
Resp_STK_FAILED: con byte 16r11;
Resp_STK_UNKNOWN: con byte 16r12;
Resp_STK_NODEVICE: con byte 16r13;
Resp_STK_INSYNC: con byte 16r14;
Resp_STK_NOSYNC: con byte 16r15;

Resp_ADC_CHANNEL_ERROR: con byte 16r16;
Resp_ADC_MEASURE_OK: con byte 16r17;
Resp_PWM_CHANNEL_ERROR: con byte 16r18;
Resp_PWM_ADJUST_OK: con byte 16r19;

# Special constants

Sync_CRC_EOP: con byte 16r20;

# Commands

Cmd_STK_GET_SYNC: con byte 16r30;
Cmd_STK_GET_SIGN_ON: con byte 16r31;

Cmd_STK_SET_PARAMETER: con byte 16r40;
Cmd_STK_GET_PARAMETER: con byte 16r41;
Cmd_STK_SET_DEVICE: con byte 16r42;
Cmd_STK_SET_DEVICE_EXT: con byte 16r45;

Cmd_STK_ENTER_PROGMODE: con byte 16r50;
Cmd_STK_LEAVE_PROGMODE: con byte 16r51;
Cmd_STK_CHIP_ERASE: con byte 16r52;
Cmd_STK_CHECK_AUTOINC: con byte 16r53;
Cmd_STK_LOAD_ADDRESS: con byte 16r55;
Cmd_STK_UNIVERSAL: con byte 16r56;
Cmd_STK_UNIVERSAL_MULTI: con byte 16r57;

Cmd_STK_PROG_FLASH: con byte 16r60;
Cmd_STK_PROG_DATA: con byte 16r61;
Cmd_STK_PROG_FUSE: con byte 16r62;
Cmd_STK_PROG_LOCK: con byte 16r63;
Cmd_STK_PROG_PAGE: con byte 16r64;
Cmd_STK_PROG_FUSE_EXT: con byte 16r65;

Cmd_STK_READ_FLASH: con byte 16r70;
Cmd_STK_READ_DATA: con byte 16r71;
Cmd_STK_READ_FUSE: con byte 16r72;
Cmd_STK_READ_LOCK: con byte 16r73;
Cmd_STK_READ_PAGE: con byte 16r74;
Cmd_STK_READ_SIGN: con byte 16r75;
Cmd_STK_READ_OSCCAL: con byte 16r76;
Cmd_STK_READ_FUSE_EXT: con byte 16r77;
Cmd_STK_READ_OSCCAL_EXT: con byte 16r78;

# Parameter constants

Parm_STK_HW_VER: con byte 16r80; # ' ' - R
Parm_STK_SW_MAJOR: con byte 16r81; # ' ' - R
Parm_STK_SW_MINOR: con byte 16r82; # ' ' - R
Parm_STK_LEDS: con byte 16r83; # ' ' - R/W
Parm_STK_VTARGET: con byte 16r84; # ' ' - R/W
Parm_STK_VADJUST: con byte 16r85; # ' ' - R/W
Parm_STK_OSC_PSCALE: con byte 16r86; # ' ' - R/W
Parm_STK_OSC_CMATCH: con byte 16r87; # ' ' - R/W
Parm_STK_RESET_DURATION: con byte 16r88; # ' ' - R/W
Parm_STK_SCK_DURATION: con byte 16r89; # ' ' - R/W

Parm_STK_BUFSIZEL: con byte 16r90; # ' ' - R/W, Range {0..255}
Parm_STK_BUFSIZEH: con byte 16r91; # ' ' - R/W, Range {0..255}
Parm_STK_DEVICE: con byte 16r92; # ' ' - R/W, Range {0..255}
Parm_STK_PROGMODE: con byte 16r93; # ' ' - 'P' or 'S'
Parm_STK_PARAMODE: con byte 16r94; # ' ' - TRUE or FALSE
Parm_STK_POLLING: con byte 16r95; # ' ' - TRUE or FALSE
Parm_STK_SELFTIMED: con byte 16r96; # ' ' - TRUE or FALSE

# status bits

Stat_STK_INSYNC: con byte 16r01; # INSYNC status bit, '1' - INSYNC
Stat_STK_PROGMODE: con byte 16r02; # Programming mode,  '1' - PROGMODE
Stat_STK_STANDALONE: con byte 16r04; # Standalone mode,   '1' - SM mode
Stat_STK_RESET: con byte 16r08; # RESET button,      '1' - Pushed
Stat_STK_PROGRAM: con byte 16r10; # Program button, '   1' - Pushed
Stat_STK_LEDG: con byte 16r20; # Green LED status,  '1' - Lit
Stat_STK_LEDR: con byte 16r40; # Red LED status,    '1' - Lit
Stat_STK_LEDBLINK: con byte 16r80; # LED blink ON/OFF,  '1' - Blink

ispmode := array[] of {byte 16rAA, byte 16r55, byte 16r55, byte 16rAA, byte 16r17, byte 16r51, byte 16r31, byte 16r13,  byte 0};	# last byte is 1 to switch isp on 0 to switch off

ck(r: array of byte)
{
	if(r == nil)
		err("programming failed");
}

pgmon()
{
	ck(rpc(array[] of {Cmd_STK_ENTER_PROGMODE}, 0));
}

pgmoff()
{
	ck(rpc(array[] of {Cmd_STK_LEAVE_PROGMODE}, 0));
}

setisp0(on: int)
{
	rd.flush();
	buf := array[len ispmode] of byte;
	buf[0:] = ispmode;
	buf[8] = byte on;
	sys->write(sfd, buf, len buf);
}

setisp(on: int): int
{
	rd.flush();
	buf := array[len ispmode] of byte;
	buf[0:] = ispmode;
	buf[8] = byte on;
	r := send(buf, 2);
	return len r == 2 && ok(r);
}

readsig(): array of byte
{
	r := send(array[] of {Cmd_STK_READ_SIGN, Sync_CRC_EOP}, 5);
	# doesn't behave as documented in AVR061: it repeats the command bytes instead
	if(len r != 5 || r[0] != Cmd_STK_READ_SIGN || r[4] != Sync_CRC_EOP){
		sys->fprint(sys->fildes(2), "bad reply %s\n", dump(r));
		return nil;
	}
	return r[1:len r-1];	# trim proto bytes
}

pgrpc(a: array of byte, repn: int): array of byte
{
	pgmon();
	r := rpc(a, repn);
	pgmoff();
	return r;
}

eop := array[] of {Sync_CRC_EOP};

rpc(a: array of byte, repn: int): array of byte
{
	r := send(cat(a, eop), repn+2);
	if(!ok(r)){
		if(len r >= 2 && r[0] == Resp_STK_INSYNC && r[len r-1] == Resp_STK_NODEVICE)
			err("internal error: programming parameters not correctly set");
		if(len r >= 1 && r[0] == Resp_STK_NOSYNC)
			err("lost synchronisation");
		sys->fprint(sys->fildes(2), "bad reply %s\n", dump(r));
		return nil;
	}
	return r[1:len r-1];	# trim sync bytes
}

send(a: array of byte, repn: int): array of byte
{
	if(debug)
		sys->print("-> %s\n", dump(a));
	if(sys->write(sfd, a, len a) != len a)
		err(sys->sprint("write error: %r"));
	return rd.readn(repn, 2000);
}

ok(r: array of byte): int
{
	return len r >= 2 && r[0] == Resp_STK_INSYNC && r[len r -1] == Resp_STK_OK;
}

universal(req: array of byte): int
{
	r := pgrpc(cat(array[] of {Cmd_STK_UNIVERSAL}, req), 1);
	if(r == nil)
		return -1;
	return int r[0];
}

setdevice(d: Avr)
{
	b := array[] of {
		Cmd_STK_SET_DEVICE,
		byte d.id,
		byte d.rev,
		byte 0,	# prog type (CHECK)
		byte d.fullpar,
		byte d.polling,
		byte d.selftimed,
		byte d.lockbytes,
		byte d.fusebytes,
		byte d.fpoll,
		byte d.fpoll,
		byte d.epoll1,
		byte d.epoll2,
		byte (d.pagesize >> 8), byte d.pagesize,
		byte (d.eepromsize>>8), byte d.eepromsize,
		byte (d.flashsize>>24), byte (d.flashsize>>16), byte (d.flashsize>>8), byte d.flashsize
	};
	ck(rpc(b, 0));
	if(mib510)
		return;
	b = array[] of {
		Cmd_STK_SET_DEVICE_EXT,
		byte 4,
		byte d.eeprompagesize,
		byte d.signalpagel,
		byte d.signalbs2,
		byte 0	# ResetDisable
	};
	ck(rpc(b, 0));
}

chiperase()
{
	ck(pgrpc(array[] of {Cmd_STK_CHIP_ERASE}, 0));
}

readfuselow(): int
{
	return universal(array[] of {byte 16r50, byte 0, byte 0, byte 0});
}

readfusehigh(): int
{
	return universal(array[] of {byte 16r58, byte 8, byte 0, byte 0});
}

readfuseext(): int
{
	return universal(array[] of {byte 16r50, byte 8, byte 0, byte 0});
}

readlockfuse(): int
{
	return universal(array[] of {byte 16r58, byte 0, byte 0, byte 0});
}

readflashpage(addr: int, nb: int): array of byte
{
	return readmem('F', addr/2, nb);
}

readeeprompage(addr: int, nb: int): array of byte
{
	return readmem('E', addr, nb);
}

readmem(memtype: int, addr: int, nb: int): array of byte
{
	if(nb > 256)
		nb = 256;
	pgmon();
	r := rpc(array[] of {Cmd_STK_LOAD_ADDRESS, byte addr, byte (addr>>8)}, 0);
	if(r != nil){
		r = send(array[] of {Cmd_STK_READ_PAGE, byte (nb>>8), byte nb, byte memtype, Sync_CRC_EOP}, nb+2);
		l := len r;
		# AVR601 says last byte should be Resp_STK_OK but it's not, at least on MIB; check for both
		if(l >= 2 && r[0] == Resp_STK_INSYNC && (r[l-1] == Resp_STK_INSYNC || r[l-1] == Resp_STK_OK))
			r = r[1:l-1];	# trim framing bytes
		else{
			sys->print("bad reply: %s\n", dump(r));
			r = nil;
		}
		if(len r < nb)
			sys->print("short [%d@%4.4ux]\n", nb, addr);
	}
	pgmoff();
	return r;
}

writeflashpage(addr: int, data: array of byte): int
{
	return writemem('F', addr/2, data);
}

writeeeprompage(addr: int, data: array of byte): int
{
	return writemem('E', addr, data);
}

writemem(memtype: int, addr: int, data: array of byte): int
{
	nb := len data;
	if(nb > 256){
		nb = 256;
		data = data[0:nb];
	}
	pgmon();
	r := rpc(array[] of {Cmd_STK_LOAD_ADDRESS, byte addr, byte (addr>>8)}, 0);
	if(r != nil){
		r = rpc(cat(array[] of {Cmd_STK_PROG_PAGE, byte (nb>>8), byte nb, byte memtype},data), 0);
		if(r == nil)
			nb = -1;
	}
	pgmoff();
	return nb;
}

writefuseext(v: int): int
{
	return universal(array[] of {byte 16rAC, byte 16rA4, byte 16rFF, byte v});
}

writefuselow(v: int): int
{
	return universal(array[] of {byte 16rAC, byte 16rA0, byte 16rFF, byte v});
}

writefusehigh(v: int): int
{
	return universal(array[] of {byte 16rAC, byte 16rA8, byte 16rFF, byte v});
}
