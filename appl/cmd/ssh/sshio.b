implement Sshio;

include "sys.m";
	sys: Sys;

include "ipints.m";
	ipints: IPints;
	IPint: import ipints;

include "crypt.m";
	crypt: Crypt;
	PK, SK: import crypt;

include "sshio.m";

include "rand.m";
	rand: Rand;

init()
{
	sys = load Sys Sys->PATH;
	ipints = load IPints IPints->PATH;
	crypt = load Crypt Crypt->PATH;
	rand = load Rand Rand->PATH;
	rand->init(sys->millisec());
}

msgnames := array[45] of {
	"SSH_MSG_NONE",	#  0 
	"SSH_MSG_DISCONNECT",
	"SSH_SMSG_PUBLIC_KEY",
	"SSH_CMSG_SESSION_KEY",
	"SSH_CMSG_USER",
	"SSH_CMSG_AUTH_RHOSTS",
	"SSH_CMSG_AUTH_RSA",
	"SSH_SMSG_AUTH_RSA_CHALLENGE",
	"SSH_CMSG_AUTH_RSA_RESPONSE",
	"SSH_CMSG_AUTH_PASSWORD",
	"SSH_CMSG_REQUEST_PTY",	#  10 
	"SSH_CMSG_WINDOW_SIZE",
	"SSH_CMSG_EXEC_SHELL",
	"SSH_CMSG_EXEC_CMD",
	"SSH_SMSG_SUCCESS",
	"SSH_SMSG_FAILURE",
	"SSH_CMSG_STDIN_DATA",
	"SSH_SMSG_STDOUT_DATA",
	"SSH_SMSG_STDERR_DATA",
	"SSH_CMSG_EOF",
	"SSH_SMSG_EXITSTATUS",	#  20 
	"SSH_MSG_CHANNEL_OPEN_CONFIRMATION",
	"SSH_MSG_CHANNEL_OPEN_FAILURE",
	"SSH_MSG_CHANNEL_DATA",
	"SSH_MSG_CHANNEL_INPUT_EOF",
	"SSH_MSG_CHANNEL_OUTPUT_CLOSED",
	"SSH_MSG_UNIX_DOMAIN_X11_FORWARDING (obsolete)",
	"SSH_SMSG_X11_OPEN",
	"SSH_CMSG_PORT_FORWARD_REQUEST",
	"SSH_MSG_PORT_OPEN",
	"SSH_CMSG_AGENT_REQUEST_FORWARDING",	#  30 
	"SSH_SMSG_AGENT_OPEN",
	"SSH_MSG_IGNORE",
	"SSH_CMSG_EXIT_CONFIRMATION",
	"SSH_CMSG_X11_REQUEST_FORWARDING",
	"SSH_CMSG_AUTH_RHOSTS_RSA",
	"SSH_MSG_DEBUG",
	"SSH_CMSG_REQUEST_COMPRESSION",
	"SSH_CMSG_MAX_PACKET_SIZE",
	"SSH_CMSG_AUTH_TIS",
	"SSH_SMSG_AUTH_TIS_CHALLENGE",	#  40 
	"SSH_CMSG_AUTH_TIS_RESPONSE",
	"SSH_CMSG_AUTH_KERBEROS",
	"SSH_SMSG_AUTH_KERBEROS_RESPONSE",
	"SSH_CMSG_HAVE_KERBEROS_TGT",
};

Conn.mk(host: string, fd: ref Sys->FD): ref Conn
{
	c := ref Conn;
	c.host = host;
	c.sesskey = array[SESSKEYLEN] of byte;
	c.sessid = array[SESSIDLEN] of byte;
	c.in = chan of (ref Msg, string);
	c.out = chan of ref Msg;
	c.flags = 0;
	c.interactive = 0;
	sync := chan of int;
	spawn msgreader(c, fd, sync);
	<-sync;
	spawn msgwriter(c, fd, sync);
	<-sync;
	return c;
}

Conn.setkey(c: self ref Conn, key: ref PK.RSA)
{
	c.hostkey = key;
}

msgreader(c: ref Conn, fd: ref Sys->FD, sync: chan of int)
{
	sys->pctl(Sys->NEWFD, 2 :: fd.fd :: nil);
	sync <-= 1;
	fd = sys->fildes(fd.fd);
	for(;;){
		m := readmsg(c, fd);
		if(m == nil){
			c.in <-= (nil, sys->sprint("%r"));
			break;
		}
		debug(DBG_PROTO, sys->sprint("<-[%d] %s\n", m.ep-m.rp, m.fulltext()));
		case m.mtype {
		SSH_MSG_IGNORE =>
			;
		SSH_MSG_DEBUG =>
			debug(DBG_PROTO, sys->sprint("remote DEBUG: %s\n", m.getstring()));
		* =>
			c.in <-= (m, nil);
		}
	}
}

msgwriter(c: ref Conn, fd: ref Sys->FD, sync: chan of int)
{
	sys->pctl(Sys->NEWFD, 2 :: fd.fd :: nil);
	sync <-= 1;
	fd = sys->fildes(fd.fd);
	while((m := <-c.out) != nil)
		if(writemsg(c, m, fd) < 0){
			while(<-c.out != nil)
				{}	# flush
			exit;
		}
}

#
# read initial SSH-m.n-comment line 
#
readversion(fd: ref Sys->FD): (int, int, string)
{
	buf := array[128] of byte;
	if((n := readstrnl(fd, buf, len buf)) < 0)
		return (-1, -1, sys->sprint("error reading version: %r"));
	#  id string is "SSH-m.n-comment".  We need m=1, n>=5.
	s := string buf[0: n];
	(nf, fld) := sys->tokenize(s, "-\r\n");
	if(nf < 3 || hd fld != "SSH")
		return (-1, -1, sys->sprint("unexpected protocol reply: %s", s));
	(nf, fld) = sys->tokenize(hd tl fld, ".");
	if(nf < 2)
		return (-1, -1, "invalid SSH version string in "+s);
	return (1, int hd tl fld, s);
}

calcsessid(hostmod: ref IPint, servermod: ref IPint, cookie: array of byte): array of byte
{
	b1 := hostmod.iptobebytes();
	b2 := servermod.iptobebytes();
	buf := array[len b1+len b2+COOKIELEN] of byte;
	buf[0:] = b1;
	buf[len b1:] = b2;
	buf[len b1+len b2:] = cookie[0: COOKIELEN];
	sessid := array[Crypt->MD5dlen] of byte;
	crypt->md5(buf, len buf, sessid, nil);
	return sessid;
}

Msg.text(m: self ref Msg): string
{
	if(0 <= m.mtype && m.mtype < len msgnames)
		return msgnames[m.mtype];
	return sys->sprint("<unknown type %d>", m.mtype);
}

Msg.fulltext(m: self ref Msg): string
{
	s := m.text();
	n := m.ep;
	if(n > 64)
		n = 64;
	for(i := 0; i < n; i++)
		s += sys->sprint(" %.2ux", int m.data[i]);
	if(n != m.ep)
		s += " ...";
	return s;
}

badmsg(m: ref Msg, want: int, errmsg: string)
{
	if(m == nil)
		s := sys->sprint("<early eof: %s>", errmsg);
	else
		s = m.text();
	if(want)
		error(sys->sprint("got %s message expecting %s", s, msgnames[want]));
	error(sys->sprint("got unexpected %s message", s));
}

Msg.mk(mtype: int, length: int): ref Msg
{
	if(length > 256*1024)
		raise "message too large";
	return ref Msg(mtype, array[4+8+1+length+4] of byte, 0, 0, length);
}

# used by auth tis
unrecvmsg(c: ref Conn, m: ref Msg)
{
	debug(DBG_PROTO, sys->sprint("unreceived %s len %d\n", msgnames[m.mtype], m.ep-m.rp));
	c.unget = m;
}

readmsg(c: ref Conn, fd: ref Sys->FD): ref Msg
{
	if(c.unget != nil){	# TO DO: assumes state of processes ensures exclusive access
		m := c.unget;
		c.unget = nil;
		return m;
	}
	buf := array[4] of byte;
	if((n := sys->readn(fd, buf, len buf)) != len buf){
		if(n < 0)
			sys->werrstr("short net read: %r");
		else
			sys->werrstr("short net read");
		return nil;
	}
	length := get4(buf, 0);
	if(length < 5 || length > 256*1024){
		sys->werrstr(sys->sprint("implausible packet length: %.8ux", length));
		return nil;
	}
	pad := 8-length%8;
	m := ref Msg(0, array[pad+length] of byte, pad, 0, pad+length-4);
	if(sys->readn(fd, m.data, len m.data) != len m.data){
		sys->werrstr(sys->sprint("short net read: %r"));
		return nil;
	}
	if(c.cipher != nil)
		c.cipher->decrypt(m.data, length+pad);
	crc := sum32(0, m.data, m.ep);
	crc0 := get4(m.data, m.ep);
	if(crc != crc0){
		sys->werrstr(sys->sprint("bad crc %#ux != %#ux (packet length %ud)", crc, crc0, length));
		return nil;
	}
	m.mtype = int m.data[m.rp++];
	return m;
}

recvmsg(c: ref Conn, mtype: int): ref Msg
{
	(m, errmsg) := <-c.in;
	if(mtype == 0){
		#  no checking 
	}else if(mtype == -1){
		#  must not be nil 
		if(m == nil)
			error(Ehangup);
	}else if(m == nil || m.mtype != mtype)	#  must be given type 
		badmsg(m, mtype, errmsg);
	return m;
}

writemsg(c: ref Conn, m: ref Msg, fd: ref Sys->FD): int
{
	datalen := m.wp;
	length := datalen+1+4;	# will add type and crc
	pad := 8-length%8;
	debug(DBG_PROTO, sys->sprint("->[%d] %s\n", datalen, m.fulltext()));
	m.data[4+pad+1:] = m.data[0: datalen];	# slide data to correct position (is this guaranteed?)	TO DO
	put4(m.data, 0, length);
	p := 4;
	if(c.cipher != nil)
		for(i := 0; i < pad; i++)
			m.data[p++] = byte fastrand();
	else{
		for(i = 0; i < pad; i++)
			m.data[p++] = byte 0;
	}
	m.data[p++] = byte m.mtype;
	#  data already in position 
	p += datalen;
	crc := sum32(0, m.data[4:], pad+1+datalen);
	put4(m.data, p, crc);
	p += 4;
	if(c.cipher != nil)
		c.cipher->encrypt(m.data[4:], length+pad);
	if(sys->write(fd, m.data, p) != p)
		return -1;
	return 0;
}

Msg.get1(m: self ref Msg): int
{
	if(m.rp >= m.ep)
		raise Edecode;
	return int m.data[m.rp++];
}

Msg.get2(m: self ref Msg): int
{
	if(m.rp+2 > m.ep)
		raise Edecode;
	x := (int m.data[m.rp+0]<<8) | int m.data[m.rp+1];
	m.rp += 2;
	return x;
}

Msg.get4(m: self ref Msg): int
{
	if(m.rp+4 > m.ep)
		raise Edecode;
	x := int m.data[m.rp+0]<<24|int m.data[m.rp+1]<<16|int m.data[m.rp+2]<<8|int m.data[m.rp+3];
	m.rp += 4;
	return x;
}

Msg.getarray(m: self ref Msg): array of byte
{
	length := m.get4();
	if(m.rp+length > m.ep)
		raise Edecode;
	p := m.data[m.rp: m.rp+length];
	m.rp += length;
	return p;
}

Msg.getstring(m: self ref Msg): string
{
	return string m.getarray();
}

Msg.getbytes(m: self ref Msg, n: int): array of byte
{
	if(m.rp+n > m.ep)
		raise Edecode;
	p := m.data[m.rp: m.rp+n];
	m.rp += n;
	return p;
}

Msg.getipint(m: self ref Msg): ref IPint
{
	n := (m.get2()+7)/8;	#  get2 returns # bits 
	return IPint.bebytestoip(m.getbytes(n));
}

Msg.getpk(m: self ref Msg): ref PK.RSA
{
	m.get4();
	ek := m.getipint();
	n := m.getipint();
	return ref PK.RSA(n, ek);
}

Msg.put1(m: self ref Msg, x: int)
{
	if(m.wp >= m.ep)
		raise Eencode;
	m.data[m.wp++] = byte x;
}

Msg.put2(m: self ref Msg, x: int)
{
	if(m.wp+2 > m.ep)
		raise Eencode;
	(m.data[m.wp+0], m.data[m.wp+1]) = (byte (x>>8), byte x);
	m.wp += 2;
}

Msg.put4(m: self ref Msg, x: int)
{
	if(m.wp+4 > m.ep)
		raise Eencode;
	(m.data[m.wp+0], m.data[m.wp+1], m.data[m.wp+2], m.data[m.wp+3]) = (byte (x>>24), byte (x>>16), byte (x>>8), byte x);
	m.wp += 4;
}

Msg.putstring(m: self ref Msg, s: string)
{
	b := array of byte s;
	m.put4(len b);
	m.putbytes(b, len b);
}

Msg.putbytes(m: self ref Msg, a: array of byte, n: int)
{
	if(m.wp+n > m.ep)
		raise Eencode;
	m.data[m.wp:] = a[0: n];
	m.wp += n;
}

Msg.putipint(m: self ref Msg, b: ref IPint)
{
	bits := b.bits();
	m.put2(bits);
#	n := (bits+7)/8;
	ba := b.iptobebytes();
	n := len ba;
	if(m.wp+n > m.ep)
		raise Eencode;
	m.data[m.wp:] = ba;
	m.wp += n;
}

Msg.putpk(m: self ref Msg, key: ref PK.RSA)
{
	m.put4(key.n.bits());
	m.putipint(key.ek);
	m.putipint(key.n);
}

crctab := array[256] of int;

initsum32()
{
	poly := int 16redb88320;
	for(i := 0; i < 256; i++){
		crc := i;
		for(j := 0; j < 8; j++)
			if(crc&1)
				crc = ((crc>>1) & int ~16r80000000)^poly;		# need unsigned shift
			else
				crc = (crc>>1) & int ~16r80000000;
		crctab[i] = crc;
	}
}

first_38: int = 1;

sum32(lcrc: int, buf: array of byte, n: int): int
{
	crc := lcrc;
	if(first_38){
		first_38 = 0;
		initsum32();
	}
	s := 0;
	while(n-- > 0)
		crc = crctab[(crc^int buf[s++])&16rff]^((crc>>8)&int ~16rFF000000);
	return crc;
}

erase(b: array of byte)
{
	for(i := 0; i < len b; i++)
		b[i] = byte 0;
}

#
# PKCS#1 padding
#
rsapad(b: ref IPint, n: int): ref IPint
{
	a := b.iptobebytes();
	pad := n - len a - 3;
	if(pad < 0)
		error("value too large to pad");	# can't happen if keys are required size
	buf := array[n] of byte;
	buf[0] = byte 0;
	buf[1] = byte 2;
	for(i := 2; --pad >= 0; i++)
		buf[i] = byte (1+fastrand()%255);
	buf[i++] = byte 0;
	buf[i:] = a;
	c := IPint.bebytestoip(buf);
	erase(buf);
	erase(a);
	return c;
}

rsaunpad(b: ref IPint): ref IPint
{
	buf := b.iptobebytes();
	i := 0;
	if(buf[0] == byte 0)
		i++;
	if(buf[i] != byte 2)
		error("bad data in rsaunpad");
	for(; i < len buf; i++)
		if(buf[i] == byte 0)
			break;
	c := IPint.bebytestoip(buf[i:]);
	erase(buf);
	return c;
}

rsaencryptbuf(key: ref PK.RSA, buf: array of byte, nbuf: int): ref IPint
{
	n := (key.n.bits()+7)/8;
	a := IPint.bebytestoip(buf[0: nbuf]);
	b := rsapad(a, n);
	return crypt->rsaencrypt(key, b);
}

iptorjustbe(b: ref IPint, buf: array of byte, length: int)
{
	a := b.iptobebytes();
	if(len a < length){
		length -= len a;
		erase(buf[0: length]);
		buf[length:] = a;
	}else
		buf[0:] = a[0: length];
	erase(a);
}

hex(a: array of byte): string
{
	s := "";
	for(i := 0; i < len a; i++)
		s += sys->sprint("%.2ux", int a[i]);
	return s;
}

debug(n: int, s: string)
{
	sys->fprint(sys->fildes(2), "debug: %s", s);
}

error(s: string)
{
	sys->fprint(sys->fildes(2), "error: %s\n", s);
	raise "error";
}

rsagen(bits: int): ref SK.RSA
{
	return crypt->rsagen(bits, 6, 0);
}

rsaencrypt(key: ref PK.RSA, b: ref IPint): ref IPint
{
	return crypt->rsaencrypt(key, b);
}

rsadecrypt(key: ref SK.RSA, b: ref IPint): ref IPint
{
	return crypt->rsadecrypt(key, b);
}

fastrand(): int
{
	return int rand->bigrand(4294967295);
}

readstrnl(fd: ref Sys->FD, buf: array of byte, nbuf: int): int
{
	for(i := 0; i < nbuf; i++)
		case sys->read(fd, buf[i:], 1) {
		-1 =>
			return -1;
		0 =>
			sys->werrstr("unexpected EOF");
			return -1;
		* =>
			if(buf[i] == byte '\n')
				return i;
		}
	sys->werrstr("line too long");
	return -1;
}

eqbytes(a: array of byte, b: array of byte, n: int): int
{
	if(len a > n || len b > n)
		return 0;
	for(i := 0; i < n; i++)
		if(a[i] != b[i])
			return 0;
	return 1;
}

get4(a: array of byte, o: int): int
{
	return int a[o+0]<<24 | int a[o+1]<<16 | int a[o+2]<<8 | int a[o+3];
}

put4(a: array of byte, o: int, v: int)
{
	a[o+0] = byte (v>>24);
	a[o+1] = byte (v>>16);
	a[o+2] = byte (v>>8);
	a[o+3] = byte v;
}
