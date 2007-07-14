implement ScsiIO;

# adapted from /sys/src/libdisk on Plan 9: subject to Lucent Public License 1.02

include "sys.m";
	sys: Sys;

include "bufio.m";
	bufio: Bufio;
	Iobuf: import bufio;

include "daytime.m";
	daytime: Daytime;

include "scsiio.m";

scsiverbose := 0;

Codefile: con "/lib/scsicodes";

Code: adt {
	v:	int;	# (asc<<8) | ascq
	s:	string;
};
codes: array of Code;

init(verbose: int)
{
	sys = load Sys Sys->PATH;
	bufio = load Bufio Bufio->PATH;
	daytime = load Daytime Daytime->PATH;

	scsiverbose = verbose;
	getcodes();
}

getcodes()
{
	fd := bufio->open(Codefile, Sys->OREAD);
	if(fd == nil)
		return;

	codes = array[256] of Code;
	nc := 0;
	while((s := fd.gets('\n')) != nil){
		if(s[0] == '#' || s[0] == '\n')
			continue;
		s = s[0: len s-1];	# trim '\n'
		m: string;
		for(i := 0; i < len s; i++)
			if(s[i] == ' '){
				m = s[i+1:];
				break;
			}
		c := Code(tohex(s), m);
		if(nc >= len codes){
			ct := array[nc + 20] of Code;
			ct[0:] = codes;
			codes = ct;
		}
		codes[nc++] = c;
	}
	codes = codes[0:nc];
}

tohex(s: string): int
{
	n := 0;
	j := 0;
	for(i := 0; i < len s && j < 4; i++){
		if(s[i] == '/')
			continue;
		d := hex(s[i]);
		if(d < 0)
			return -1;
		n = (n<<4) | d;
		j++;
	}
	return n;
}

hex(c: int): int
{
	if(c >= '0' && c <= '9')
		return c-'0';
	if(c >= 'A' && c <= 'F')
		return c-'A' + 10;
	if(c >= 'a' && c <= 'f')
		return c-'a' + 10;
	return -1;
}

scsierror(asc: int, ascq: int): string
{
	t := -1;
	for(i := 0; i < len codes; i++){
		if(codes[i].v == ((asc<<8) | ascq))
			return codes[i].s;
		if(codes[i].v == (asc<<8))
			t = i;
	}
	if(t >= 0)
		return sys->sprint("(ascq #%.2ux) %s", ascq, codes[t].s);
	return sys->sprint("scsi #%.2ux %.2ux", asc, ascq);
}

_scsicmd(s: ref Scsi, cmd: array of byte, data: array of byte, io: int, dolock: int): int
{
	if(dolock)
		qlock(s);
	dcount := len data;
	if(sys->write(s.rawfd, cmd, len cmd) != len cmd) {
		sys->werrstr("cmd write: %r");
		if(dolock)
			qunlock(s);
		return -1;
	}

	n: int;
	resp := array[16] of byte;
	case io {
	Sread =>
		n = sys->read(s.rawfd, data, dcount);
		if(n < 0 && scsiverbose)
			sys->fprint(sys->fildes(2), "dat read: %r: cmd %#2.2uX\n", int cmd[0]);
	Swrite =>
		n = sys->write(s.rawfd, data, dcount);
		if(n != dcount && scsiverbose)
			sys->fprint(sys->fildes(2), "dat write: %r: cmd %#2.2uX\n", int cmd[0]);
	Snone or * =>
		n = sys->write(s.rawfd, resp, 0);
		if(n != 0 && scsiverbose)
			sys->fprint(sys->fildes(2), "none write: %r: cmd %#2.2uX\n", int cmd[0]);
	}

	m := sys->read(s.rawfd, resp, len resp);
	if(dolock)
		qunlock(s);
	if(m < 0){
		sys->werrstr("resp read: %r\n");
		return -1;
	}
	status := int string resp[0:m];
	if(status == 0)
		return n;

	sys->werrstr(sys->sprint("cmd %2.2uX: status %uX dcount %d n %d", int cmd[0], status, dcount, n));
	return -1;
}

Scsi.rawcmd(s: self ref Scsi, cmd: array of byte, data: array of byte, io: int): int
{
	return _scsicmd(s, cmd, data, io, 1);
}

_scsiready(s: ref Scsi, dolock: int): int
{
	if(dolock)
		qlock(s);
	for(i:=0; i<3; i++) {
		cmd := array[6] of {0 => byte 16r00, * => byte 0};	# test unit ready
		if(sys->write(s.rawfd, cmd, len cmd) != len cmd) {
			if(scsiverbose)
				sys->fprint(sys->fildes(2), "ur cmd write: %r\n");
			continue;
		}
		resp := array[16] of byte;
		sys->write(s.rawfd, resp, 0);
		m := sys->read(s.rawfd, resp, len resp);
		if(m < 0){
			if(scsiverbose)
				sys->fprint(sys->fildes(2), "ur resp read: %r\n");
			continue;	# retry
		}
		status := int string resp[0:m];
		if(status == 0 || status == 16r02) {
			if(dolock)
				qunlock(s);
			return 0;
		}
		if(scsiverbose)
			sys->fprint(sys->fildes(2), "target: bad status: %x\n", status);
	}
	if(dolock)
		qunlock(s);
	return -1;
}

Scsi.ready(s: self ref Scsi): int
{
	return _scsiready(s, 1);
}

Scsi.cmd(s: self ref Scsi, cmd: array of byte, data: array of byte, io: int): int
{
	dcount := len data;
	code := 0;
	key := 0;
	qlock(s);
	sense: array of byte;
	for(tries:=0; tries<2; tries++) {
		n := _scsicmd(s, cmd, data, io, 0);
		if(n >= 0) {
			qunlock(s);
			return n;
		}

		#
		# request sense
		#
		sense = array[255] of {* => byte 16rFF};	# TO DO: usb mass storage devices might inist on less
		req := array[6] of {0 => byte 16r03, 4 => byte len sense, * => byte 0};
		if((n=_scsicmd(s, req, sense, Sread, 0)) < 14)
			if(scsiverbose)
				sys->fprint(sys->fildes(2), "reqsense scsicmd %d: %r\n", n);
	
		if(_scsiready(s, 0) < 0)
			if(scsiverbose)
				sys->fprint(sys->fildes(2), "unit not ready\n");
	
		key = int sense[2];
		code = int sense[12];
		if(code == 16r17 || code == 16r18) {	# recovered errors
			qunlock(s);
			return dcount;
		}
		if(code == 16r28 && int cmd[0] == 16r43) {	# get info and media changed
			s.nchange++;
			s.changetime = daytime->now();
			continue;
		}
	}

	# drive not ready, or medium not present
	if(cmd[0] == byte 16r43 && key == 2 && (code == 16r3a || code == 16r04)) {
		s.changetime = 0;
		qunlock(s);
		return -1;
	}
	qunlock(s);

	if(cmd[0] == byte 16r43 && key == 5 && code == 16r24)	# blank media
		return -1;

	p := scsierror(code, int sense[13]);

	sys->werrstr(sys->sprint("cmd #%.2ux: %s", int cmd[0], p));

	if(scsiverbose)
		sys->fprint(sys->fildes(2), "scsi cmd #%.2ux: %.2ux %.2ux %.2ux: %s\n", int cmd[0], key, code, int sense[13], p);

#	if(key == 0)
#		return dcount;
	return -1;
}

Scsi.open(dev: string): ref Scsi
{
	rawfd := sys->open(dev+"/raw", Sys->ORDWR);
	if(rawfd == nil)
		return nil;
	ctlfd := sys->open(dev+"/ctl", Sys->ORDWR);
	if(ctlfd == nil)
		return nil;

	buf := array[512] of byte;
	n := sys->readn(ctlfd, buf, len buf);
	if(n < 8){
		if(n >= 0)
			sys->werrstr("error reading ctl file");
		return nil;
	}
	ctlfd = nil;

	for(i := 0; i < n; i++)
		if(buf[i] == byte '\n')
			break;
	inq := string buf[0:i];
	if(i >= n || inq[0:8] != "inquiry "){
		sys->werrstr("invalid inquiry string");
		return nil;
	}
	s := ref Scsi;
	s.lock = chan[1] of int;
	s.rawfd = rawfd;
	s.inquire = inq[8:];
	s.changetime = daytime->now();

	if(s.ready() < 0)
		return nil;

	return s;
}

qlock(s: ref Scsi)
{
	s.lock <-= 1;
}

qunlock(s: ref Scsi)
{
	<-s.lock;
}
