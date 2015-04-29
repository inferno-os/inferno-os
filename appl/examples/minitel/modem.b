#
# Copyright © 1998 Vita Nuova Limited.  All rights reserved.
#

#modem states for direct connection
MSstart, MSdialing, MSconnected, MSdisconnecting,

# special features
Ecp								# error correction
	: con (1 << iota);

Ecplen: con 17;	# error correction block length: data[15], crc, validation (=0)

Modem: adt {
	m:		ref Module;			# common attributes
	in:		chan of ref Event;

	connect:	int;					# None, Direct, Network
	state:	int;					# modem dialing state
	saved:	string;				# response, so far (direct dial)
	initstr:	string;				# softmodem init string (direct dial)
	dialstr:	string;				# softmodem dial string (direct dial)
	lastdialstr:	string;

	spec:	int;					# special features
	fd:		ref Sys->FD;			# modem data file, if != nil
	cfd:		ref Sys->FD;			# modem ctl file, if != nil (direct dial only)
	devpath:	string;				# path to the modem;
	avail:	array of byte;			# already read
	rd:		chan of array of byte;	# reader -> rd
	pid:		int;					# reader pid if != 0

	seq:		int;					# ECP block sequence number
	waitsyn:	int;					# awaiting restart SYN SYN ... sequence
	errforce:	int;
	addparity:	int;					# must add parity to outgoing data

	init:		fn(m: self ref Modem, connect: int, initstr, dialstr: string);
	reset:	fn(m: self ref Modem);
	run:		fn(m: self ref Modem);
	quit:		fn(m: self ref Modem);
	runstate:	fn(m: self ref Modem, data: array of byte);
	write:	fn(m: self ref Modem, data: array of byte):int;	# to network
	reader:	fn(m: self ref Modem, pidc: chan of int);
};

partab: array of byte;

dump(a: array of byte, n: int): string
{
	s := sys->sprint("[%d]", n);
	for(i := 0; i < n; i++)
		s += sys->sprint(" %.2x", int a[i]);
	return s;
}

Modem.init(m: self ref Modem, connect: int, initstr, dialstr: string)
{
	partab = array[128] of byte;
	for(c := 0; c < 128; c++)
		if(parity(c))
			partab[c] = byte (c | 16r80);
		else
			partab[c] = byte c;
	m.in = chan of ref Event;
	m.connect = connect;
	m.state = MSstart;
	m.initstr = initstr;
	m.dialstr = dialstr;
	m.pid = 0;
	m.spec = 0;
	m.seq = 0;
	m.waitsyn = 0;
	m.errforce = 0;
	m.addparity = 0;
	m.avail = array[0] of byte;
	m.rd = chan of array of byte;
	m.reset();
}

Modem.reset(m: self ref Modem)
{
	m.m = ref Module(Pscreen, 0);
}

Modem.run(m: self ref Modem)
{
	if(m.dialstr != nil)
		send(ref Event.Eproto(Pmodem, Mmodem, Cconnect, "", 0,0,0));
Runloop:
	for(;;){
		alt {
		ev := <- m.in =>
			pick e := ev {
			Equit =>
				break Runloop;
			Edata =>
				if(debug['m'] > 0)
					fprint(stderr, "Modem <- %s\n", e.str());
				m.write(e.data);
				if(T.state == Local || T.spec & Echo) {	# loopback
					if(e.from == Mkeyb) {
						send(ref Event.Eproto(Pscreen, Mkeyb, Ccursor, "", 0,0,0));
						send(ref Event.Edata(Pscreen, Mkeyb, e.data));
					}
				}
			Eproto =>
				case e.cmd {
				Creset =>
					m.reset();
				Cconnect =>
					if(m.pid != 0)
						break;
					m.addparity = 1;
					T.state = Connecting;
					send(ref Event.Eproto(Pscreen, Mmodem, Cindicators, "",0,0,0));

					case m.connect {
					Direct =>
						S.msg("Appel "+m.dialstr+" ...");
						dev := "/dev/modem";
						if(openmodem(m, dev) < 0) {
							S.msg("Modem non prêt");
							T.state = Local;
							send(ref Event.Eproto(Pscreen, Mmodem, Cindicators, "",0,0,0));
							break;
						}
						m.state = MSdialing;
						m.saved = "";
						dialout(m);
						T.terminalid = TERMINALID2;
					Network =>	
						S.msg("Connexion au serveur ...");
						if(debug['m'] > 0 || debug['M'] > 0)
							sys->print("dial(%s)\n", m.dialstr);
						cx := dial->dial(m.dialstr, "");
						if (cx == nil){
							S.msg("Echec de la connexion");
							T.state = Local;
							send(ref Event.Eproto(Pscreen, Mmodem, Cindicators, "",0,0,0));
							if(debug['m'] > 0)
								sys->print("can't dial %s: %r\n", m.dialstr);
							break;
						}
						m.fd = cx.dfd;
						m.cfd = cx.cfd;
						if(len m.dialstr >= 3 && m.dialstr[0:3] == "tcp")
							m.addparity = 0;	# Internet gateway apparently doesn't require parity
						if(m.fd != nil) {
							S.msg(nil);
							m.state = MSconnected;
							T.state = Online;
							send(ref Event.Eproto(Pscreen, Mmodem, Cindicators, "",0,0,0));
						}
						T.terminalid = TERMINALID1;
					}
					if(m.fd != nil) {
						pidc := chan of int;
						spawn m.reader(pidc);
						m.pid = <-pidc;
					}
				Cdisconnect =>
					if(m.pid != 0) {
						S.msg("Déconnexion ...");
						m.state = MSdisconnecting;
					}
					if(m.connect == Direct)
						hangup(m);
					else
						nethangup(m);
				Cplay =>			# for testing
					case e.s {
					"play" =>
						replay(m);
					}
				Crequestecp =>
					if(m.spec & Ecp){	# for testing: if already active, force an error
						m.errforce = 1;
						break;
					}
					m.write(array[] of {byte SEP, byte 16r4A});
sys->print("sending request for ecp\n");
				Cstartecp =>
					m.spec |= Ecp;
					m.seq = 0;	# not in spec
					m.waitsyn = 0;	# not in spec
				Cstopecp =>
					m.spec &= ~Ecp;
				* => break;
				}
			}
		b := <- m.rd =>
			if(debug['m'] > 0){
				fprint(stderr, "Modem -> %s\n", dump(b,len b));
			}
			if(b == nil) {
				m.pid = 0;
				case m.state {
				MSdialing =>
					S.msg("Echec appel");
				MSdisconnecting =>
					S.msg(nil);
				}
				m.state = MSstart;
				T.state = Local;
				send(ref Event.Eproto(Pscreen, Mmodem, Cscreenon, "",0,0,0));
				send(ref Event.Eproto(Pscreen, Mmodem, Cindicators, "",0,0,0));
				break;
			}
			m.runstate(b);
		}
	}
	if(m.pid != 0)
		kill(m.pid);
	send(nil);	
}

Modem.quit(nil: self ref Modem)
{
}

Modem.runstate(m: self ref Modem, data: array of byte)
{
	if(debug['m']>0)
		sys->print("runstate %d %s\n", m.state, dump(data, len data));
	case m.state {
	MSstart =>	;
	MSdialing =>
		for(i:=0; i<len data; i++) {
			ch := int data[i];
			if(ch != '\n' && ch != '\r') {
				m.saved[len m.saved] = ch;
				continue;
			}
			(code, str) := seenreply(m.saved);
			case code {
			Noise or Ok =>	;
			Success =>
				S.msg(nil);
				m.state = MSconnected;
				T.state = Online;
				send(ref Event.Eproto(Pscreen, Mmodem, Cindicators, "",0,0,0));
			Failure =>
				hangup(m);
				S.msg(str);
				m.state = MSstart;
				T.state = Local;
				send(ref Event.Eproto(Pscreen, Mmodem, Cindicators, "",0,0,0));
			}
			m.saved = "";
		}
	MSconnected =>
		send(ref Event.Edata(m.m.path, Mmodem, data));
	MSdisconnecting =>	;
	}
}

Modem.write(m: self ref Modem, data: array of byte): int
{
	if(m.fd == nil)
		return -1;
	if(len data == 0)
		return 0;
	if(m.addparity){
		# unfortunately must copy data to add parity for direct modem connection
		pa := array[len data] of byte;
		for(i := 0; i<len data; i++)
			pa[i] = partab[int data[i] & 16r7F];
		data = pa;
	}
	if(debug['m']>0)
		sys->print("WRITE %s\n", dump(data, len data));
	return sys->write(m.fd, data, len data);
}

#
# minitel error correction protocol
#
# SYN, SYN, block number	start of retransmission
# NUL ignored
# DLE escapes {DLE, SYN, NACK, NUL}
# NACK, block	restart request
#

crctab: array of int;
Crcpoly: con 16r9;	# crc7 = x^7+x^3+1

# precalculate the CRC7 remainder for all bytes

mktabs()
{
	crctab = array[256] of int;
	for(c := 0; c < 256; c++){
		v := c;
		crc := 0;
		for(i := 0; i < 8; i++){
			crc <<= 1;		# align remainder's MSB with value's
			if((v^crc) & 16r80)
				crc ^= Crcpoly;
			v <<= 1;
		}
		crctab[c] = (crc<<1) & 16rFE;	# pre-align the result to save <<1 later
	}
}

# return the index of the first non-NUL character (the start of a block)

nextblock(a: array of byte, i: int, n: int): int
{
	for(; i < n; i++)
		if(a[i] != byte NUL)
			break;
	return i;
}

# return the data in the ecp block in a[0:Ecplen] (return nil for bad format)

decode(a: array of byte): array of byte
{
	if(debug['M']>0)
		sys->print("DECODE: %s\n", dump(a, Ecplen));
	badpar := 0;
	oldcrc := int a[Ecplen-2];
	crc := 0;
	op := 0;
	dle := 0;
	for(i:=0; i<Ecplen-2; i++){	# first byte is high-order byte of polynomial (MSB first)
		c := int a[i];
		nc := c & 16r7F;	# strip parity
		if((c^int partab[nc]) & 16r80)
			badpar++;
		crc = crctab[crc ^ c];
		# collapse DLE sequences
		if(!dle){
			if(nc == DLE && i+1 < Ecplen-2){
				dle = 1;
				continue;
			}
			if(nc == NUL)
				continue;	# strip non-escaped NULs
		}
		dle = 0;
		a[op++] = byte nc;
	}
	if(badpar){
		if(debug['E'] > 0)
			sys->print("bad parity\n");
		return nil;	
	}
	crc = (crc>>1)&16r7F;
	if(int partab[crc] != oldcrc){
		if(debug['E'] > 0)
			sys->print("bad crc: in %ux got %ux\n", oldcrc, int partab[crc]);
		return nil;
	}
	b := array[op] of byte;
	b[0:] = a[0:op];
	if(debug['M'] > 0)
		sys->print("OUT: %s [%x :: %x]\n", dump(b,op), crc, oldcrc);
	return b;
}

Modem.reader(m: self ref Modem, pidc: chan of int)
{
	pidc <-= sys->pctl(0, nil);
	if(crctab == nil)
		mktabs();
	a := array[Sys->ATOMICIO] of byte;
	inbuf := 0;
	while(m.fd != nil) {
		while((n := read(m.fd, a[inbuf:], len a-inbuf)) > 0){
			n += inbuf;
			inbuf = 0;
			if((m.spec & Ecp) == 0){
				b := array[n] of byte;
				for(i := 0; i<n; i++)
					b[i] = byte (int a[i] & 16r7F);	# strip parity
				m.rd <-= b;
			}else{
				#sys->print("IN: %s\n", dump(a,n));
				i := 0;
				if(m.waitsyn){
					sys->print("seeking SYN #%x\n", m.seq);
					syn := byte (SYN | 16r80);
					lim := n-3;
					for(; i <= lim; i++)
						if(a[i] == syn && a[i+1] == syn && (int a[i+2]&16r0F) == m.seq){
							i += 3;
							m.waitsyn = 0;
							sys->print("found SYN #%x@%d\n", m.seq, i-3);
							break;
						}
				}
				lim := n-Ecplen;
				for(; (i = nextblock(a, i, n)) <= lim; i += Ecplen){
					b := decode(a[i:]);
					if(m.errforce || b == nil){
						m.errforce = 0;
						b = array[2] of byte;
						b[0] = byte NACK;
						b[1] = byte (m.seq | 16r40);
						sys->print("NACK #%x\n", m.seq);
						m.write(b);
						m.waitsyn = 1;
						i = n;		# discard rest of block
						break;
					}
					m.seq = (m.seq+1) & 16rF;	# mod 16 counter
					m.rd <-= b;
				}
				if(i < n){
					a[0:] = a[i:n];
					inbuf = n-i;
				}
			}
		}
		if(n <= 0)
			break;
	}
#	m.fd = nil;
	m.rd <-= nil;
}

playfd: ref Sys->FD;
in_code, in_char: con iota;

replay(m: ref Modem)
{
	buf := array[8192] of byte;
	DMAX:	con 10;
	d := 0;
	da := array[DMAX] of byte;
	playfd = nil;
	if(playfd == nil)
		playfd = sys->open("minitel.txt", Sys->OREAD);
	if(playfd == nil)
		return;
	nl := 1;
	discard := 1;
	state := in_code;
	hs := "";
	start := 0;
mainloop:
	for(;;) {
		n := sys->read(playfd, buf, len buf);
		if(n <= 0)
			break;
		for(i:=0; i<n; i++) {
			ch := int buf[i];
			if(nl)
				case ch {
				'>' =>	discard = 0;
				'<' =>	discard = 1;
						if(start)
							sys->sleep(1000);
				'{' =>		start = 1;
				'}' =>		break mainloop;
				}
			if(ch == '\n')
				nl = 1;
			else
				nl = 0;
			if(discard)
				continue;
			if(!start)
				continue;
			if(state == in_code && ((ch >= '0' && ch <= '9') || (ch >= 'a' && ch <= 'z')))
				hs[len hs] = ch;
			else if(ch == '(') {
				state = in_char;
				(v, nil) := toint(hs, 16);
				da[d++] = byte v;
				if(d == DMAX) {
					send(ref Event.Edata(m.m.path, Mmodem, da));
					d = 0;
					da = array[DMAX] of byte;
					sys->sleep(50);
				}
				hs = "";
			}else if(ch == ')')
				state = in_code;
		}
	}
	playfd = nil;

}

kill(pid : int)
{
	prog := "#p/" + string pid + "/ctl";
	fd := sys->open(prog, Sys->OWRITE);
	if (fd != nil) {
		cmd := array of byte "kill";
		sys->write(fd, cmd, len cmd);
	}
}


# Modem stuff


# modem return codes
Ok, Success, Failure, Noise, Found: con iota;

#
#  modem return messages
#
Msg: adt {
	text: string;
	trans: string;
	code: int;
};

msgs: array of Msg = array [] of {
	("OK",			"Ok", Ok),
	("NO CARRIER",		"No carrier", Failure),
	("ERROR",			"Bad modem command", Failure),
	("NO DIALTONE",	"No dial tone", Failure),
	("BUSY",			"Busy tone", Failure),
	("NO ANSWER",		"No answer", Failure),
	("CONNECT",		"", Success),
};

msend(m: ref Modem, x: string): int
{
	a := array of byte x;
	return sys->write(m.fd, a, len a);
}

#
#  apply a string of commands to modem
#
apply(m: ref Modem, s: string): int
{
	buf := "";
	for(i := 0; i < len s; i++){
		c := s[i];
		buf[len buf] = c;	# assume no Unicode
		if(c == '\r' || i == (len s -1)){
			if(c != '\r')
				buf[len buf] = '\r';
			if(msend(m, buf) < 0)
				return Failure;
			buf = "";
		}
	}
	return Ok;
}

openmodem(m: ref Modem, dev: string): int
{
	m.fd = sys->open(dev, Sys->ORDWR);
	m.cfd = sys->open(dev+"ctl", Sys->ORDWR);
	if(m.fd == nil || m.cfd == nil)
		return -1;
#	hangup(m);
#	m.fd = sys->open(dev, Sys->ORDWR);
#	m.cfd = sys->open(dev+"ctl", Sys->ORDWR);
#	if(m.fd == nil || m.cfd == nil)
#		return -1;
	return 0;
}

hangup(m: ref Modem)
{
	sys->sleep(1020);
	msend(m, "+++");
	sys->sleep(1020);
	apply(m, "ATH0");
	m.fd = nil;
#	sys->write(m.cfd, array of byte "f", 1);
	sys->write(m.cfd, array of byte "h", 1);
	m.cfd = nil;
	# HACK: shannon softmodem "off-hook" bug fix
	sys->open("/dev/modem", Sys->OWRITE);
}

nethangup(m: ref Modem)
{
	m.fd = nil;
	sys->write(m.cfd, array of byte "hangup", 6);
	m.cfd = nil;
}


#
#  check `s' for a known reply or `substr'
#
seenreply(s: string): (int, string)
{
	for(k := 0; k < len msgs; k++)
		if(len s >= len msgs[k].text && s[0:len msgs[k].text] == msgs[k].text) {
			return (msgs[k].code, msgs[k].trans);
		}
	return (Noise, s);
}

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

dialout(m: ref Modem)
{
	if(m.initstr != nil)
		apply(m, "AT"+m.initstr);
	if(m.dialstr != nil) {
		apply(m, "ATD"+m.dialstr);
		m.lastdialstr = m.dialstr;
		m.dialstr = nil;
	}
}
