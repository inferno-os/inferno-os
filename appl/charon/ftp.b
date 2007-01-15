implement Transport;

include "common.m";
include "transport.m";

# local copies from CU
sys: Sys;
U: Url;
	Parsedurl: import U;
S: String;
CU: CharonUtils;
	Netconn, ByteSource, Header, config: import CU;

FTPPORT: con 21;

# Return codes
Extra, Success, Incomplete, TempFail, PermFail : con (1+iota);

cmdbuf := array[200] of byte;
dbg := 0;

init(c: CharonUtils)
{
	CU = c;
	sys = load Sys Sys->PATH;
	S = load String String->PATH;
	U = load Url Url->PATH;
	if (U != nil)
		U->init();
	dbg = int (CU->config).dbg['n'];
}

connect(nc: ref Netconn, bs: ref ByteSource)
{
	port := nc.port;
	if(port == 0)
		port = FTPPORT;
	addr := "tcp!" + nc.host + "!" + string port;
	if(dbg)
		sys->print("ftp %d: dialing %s\n", nc.id, addr);
	err := "";
	ctlfd : ref sys->FD = nil;
	rv : int;
	(rv, nc.conn) = sys->dial(addr, nil);
	if(rv < 0) {
		syserr := sys->sprint("%r");
		if(S->prefix("cs: dialup", syserr))
			err = syserr[4:];
		else if(S->prefix("cs: dns: no translation found", syserr))
			err = "unknown host";
		else
			err = sys->sprint("couldn't connect: %s", syserr);
	}
	else {
		if(dbg)
			sys->print("ftp %d: connected\n", nc.id);
		ctlfd = nc.conn.dfd;
		# use cfd to hold control connection so can use dfd to hold data connection
		nc.conn.cfd = ctlfd;
		nc.conn.dfd = nil;

		# look for Hello
		(code, msg) := getreply(nc, ctlfd);
		if(code != Success)
			err = "instead of hello: " + msg;
		else {
			# logon
			err = sendrequest(nc, ctlfd, "USER anonymous");
			if(err == "") {
				(code, msg) = getreply(nc, ctlfd);
				if(code == Incomplete) {
					# need password
					err = sendrequest(nc, ctlfd, "PASS webget@webget.com");
					if(err == "")
						(code, msg) = getreply(nc, ctlfd);
				}
				if(err == "") {
					if(code != Success)
						err =  "login failed: " + msg;

					# image type
					err = sendrequest(nc, ctlfd, "TYPE I");
					if(err == "") {
						(code, msg) = getreply(nc, ctlfd);
						if(code != Success)
							err =  "can't set type I: " + msg;
					}
				}
			}
		}
	}
	if(err == "") {
		nc.connected = 1;
		nc.state = CU->NCgethdr;
	}
	else {
		if(dbg)
			sys->print("ftp %d: connection failed: %s\n", nc.id, err);
		bs.err = err;
		closeconn(nc);
	}
}

# Ask ftp server on ctlfd for passive port and dial it
dialdata(nc: ref Netconn, ctlfd: ref sys->FD) : string
{
	# put in passive mode
	sendrequest(nc, ctlfd, "PASV");
	(code, msg) := getreply(nc, ctlfd);
	if(code != Success)
		return "can't use passive mode: " + msg;
	(paddr, pport) := passvap(msg);
	if(paddr == "")
		return "passive mode protocol botch: " + msg;
	# dial data port
	daddr := "tcp!" + paddr + "!" + pport;
	if(dbg)
		sys->print("ftp %d: dialing data %s", nc.id, daddr);
	(ok, dnet) := sys->dial(daddr, nil);
	if(ok < 0)
		return "data dial error";
	nc.conn.dfd = dnet.dfd;
	return "";
}

writereq(nc: ref Netconn, bs: ref ByteSource)
{
	ctlfd := nc.conn.cfd;
	CU->assert(ctlfd != nil);
	err := dialdata(nc, ctlfd);
	if(err == "") {
		# tell remote to send file
		err = sendrequest(nc, ctlfd, "RETR " + bs.req.url.path);
	}
	if(err != "") {
		if(dbg)
			sys->print("ftp %d: error: %s\n", nc.id, err);
		bs.err = err;
		closeconn(nc);
	}
}

gethdr(nc: ref Netconn, bs: ref ByteSource)
{
	hdr := Header.new();
	bs.hdr = hdr;
	err := "";
	ctlfd := nc.conn.cfd;
	dfd := nc.conn.dfd;
	CU->assert(ctlfd != nil && dfd != nil);
	(code, msg) := getreply(nc, ctlfd);
	if(code != Extra) {
		if(dbg)
			sys->print("ftp %d: retrieve failed: %s\n",
				nc.id, msg);
		hdr.code = CU->HCNotFound;
		hdr.msg = "Not found";
	}
	else {
		hdr.code = CU->HCOk;

		# try to guess media type before returning header
		buf := array[sys->ATOMICIO] of byte;
		n := sys->read(dfd, buf, len buf);
		if(dbg)
			sys->print("ftp %d: read %d bytes\n", nc.id, n);
		if(n < 0)
			err = "error reading data";
		else {
			if(n > 0)
				nc.tbuf = buf[0:n];
			else
				nc.tbuf = nil;
			hdr.setmediatype(bs.req.url.path, nc.tbuf);
			hdr.actual = bs.req.url;
			hdr.base = hdr.actual;
			hdr.length = -1;
			hdr.msg = "Ok";
		}
	}
	if(err != "") {
		if(dbg)
			sys->print("ftp %d: error %s\n", nc.id, err);
		bs.err = err;
		closeconn(nc);
	}
}

getdata(nc: ref Netconn, bs: ref ByteSource): int
{
	dfd := nc.conn.dfd;
	CU->assert(dfd != nil);
	if (bs.data == nil || bs.edata >= len bs.data) {
		closeconn(nc);
		return 0;
	}
	buf := bs.data[bs.edata:];
	n := len buf;
	if (nc.tbuf != nil) {
		# initial overread of header
		if (n >= len nc.tbuf) {
			n = len nc.tbuf;
			buf[:] = nc.tbuf;
			nc.tbuf = nil;
			return n;
		}
		buf[:] = nc.tbuf[:n];
		nc.tbuf = nc.tbuf[n:];
		return n;
	}
	n = sys->read(dfd, buf, n);
	if(dbg > 1)
		sys->print("ftp %d: read %d bytes\n", nc.id, n);
	if(n <= 0) {
		bs.err = "eof";
		closeconn(nc);
	}
	return n;
}

# Send ftp request cmd along fd; return "" if OK else error string.
sendrequest(nc: ref Netconn, fd: ref sys->FD, cmd: string) : string
{
	if(dbg > 1)
		sys->print("ftp %d: send request: %s\n", nc.id, cmd);
	cmd = cmd + "\r\n";
	buf := array of byte cmd;
	n := len buf;
	if(sys->write(fd, buf, n) != n)
		return sys->sprint("write error: %r");
	return "";
}

# Get reply to ftp request along fd.
# Reply may be more than one line ("commentary")
# but ends with a line that has a status code in the first
# three characters (a number between 100 and 600)
# followed by a blank and a possible message.
# If OK, return the hundreds digit of the status (which will
# mean one of Extra, Success, etc.), and the whole
# last line; else return (-1, "").
getreply(nc: ref Netconn, fd: ref sys->FD) : (int, string)
{
	# Reply might contain more than one line,
	# because there might be "commentary" lines.
	i := 0;
	j := 0;
	aline: array of byte;
	eof := 0;
	for(;;) {
		(aline, eof, i, j) = CU->getline(fd, cmdbuf, i, j);
		if(eof)
			break;
		line := string aline;
		n := len line;
		if(n == 0)
			break;
		if(dbg > 1)
			sys->print("ftp %d: got reply: %s\n", nc.id, line);
		rv := int line;
		if(rv >= 100 && rv < 600) {
			# if line is like '123-stuff'
			# then there will be more lines until
			# '123 stuff'
			if(len line<4 || line[3]==' ')
				return (rv/100, line);
		}
	}
	return (-1, "");
}

# Parse reply to PASSV to find address and port numbers.
# This is AI because extant agents aren't good at following
# the standard.
passvap(s: string) : (string, string)
{
	addr := "";
	port := "";
	(nil, v) := S->splitl(s, "(");
	if(v != "")
		s = v[1:];
	else
		(nil, s) = S->splitl(s, "0123456789");
	if(s != "") {
		(n, l) := sys->tokenize(s, ",");
		if(n >= 6) {
			addr = hd l + ".";
			l = tl l;
			addr += hd l + ".";
			l = tl l;
			addr += hd l + ".";
			l = tl l;
			addr += hd l;
			l = tl l;
			p1 := int hd l;
			p2 := int hd tl l;
			port = string (((p1&255)<<8)|(p2&255));
		}
	}
	return (addr, port);
}

defaultport(nil: string) : int
{
	return FTPPORT;
}

closeconn(nc: ref Netconn)
{
	nc.conn.dfd = nil;
	nc.conn.cfd = nil;
	nc.conn.dir = "";
	nc.connected = 0;
}
