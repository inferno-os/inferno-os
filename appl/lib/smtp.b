implement Smtp;
 
include "sys.m";
	sys : Sys;
include "bufio.m";
	bufio : Bufio;
include "smtp.m";
include "encoding.m";
include "attrdb.m";
	attrdb: Attrdb;
	Db, Dbentry, Tuples: import attrdb;
include "ip.m";
	ip: IP;
include "ipattr.m";
	ipattr: IPattr;

include "keyring.m";
include "asn1.m";
include "pkcs.m";
include "sslsession.m";
include "ssl3.m";
	ssl3: SSL3;
	Context: import ssl3;
# Inferno supported cipher suites: RSA_EXPORT_RC4_40_MD5
ssl_suites := array [] of {
	byte 0, byte 16r03,	# RSA_EXPORT_WITH_RC4_40_MD5
	byte 0, byte 16r04,	# RSA_WITH_RC4_128_MD5
	byte 0, byte 16r05,	# RSA_WITH_RC4_128_SHA
	byte 0, byte 16r06,	# RSA_EXPORT_WITH_RC2_CBC_40_MD5
	byte 0, byte 16r07,	# RSA_WITH_IDEA_CBC_SHA
	byte 0, byte 16r08,	# RSA_EXPORT_WITH_DES40_CBC_SHA
	byte 0, byte 16r09,	# RSA_WITH_DES_CBC_SHA
	byte 0, byte 16r0A,	# RSA_WITH_3DES_EDE_CBC_SHA
	
	byte 0, byte 16r0B,	# DH_DSS_EXPORT_WITH_DES40_CBC_SHA
	byte 0, byte 16r0C,	# DH_DSS_WITH_DES_CBC_SHA
	byte 0, byte 16r0D,	# DH_DSS_WITH_3DES_EDE_CBC_SHA
	byte 0, byte 16r0E,	# DH_RSA_EXPORT_WITH_DES40_CBC_SHA
	byte 0, byte 16r0F,	# DH_RSA_WITH_DES_CBC_SHA
	byte 0, byte 16r10,	# DH_RSA_WITH_3DES_EDE_CBC_SHA
	byte 0, byte 16r11,	# DHE_DSS_EXPORT_WITH_DES40_CBC_SHA
	byte 0, byte 16r12,	# DHE_DSS_WITH_DES_CBC_SHA
	byte 0, byte 16r13,	# DHE_DSS_WITH_3DES_EDE_CBC_SHA
	byte 0, byte 16r14,	# DHE_RSA_EXPORT_WITH_DES40_CBC_SHA
	byte 0, byte 16r15,	# DHE_RSA_WITH_DES_CBC_SHA
	byte 0, byte 16r16,	# DHE_RSA_WITH_3DES_EDE_CBC_SHA
	
	byte 0, byte 16r17,	# DH_anon_EXPORT_WITH_RC4_40_MD5
	byte 0, byte 16r18,	# DH_anon_WITH_RC4_128_MD5
	byte 0, byte 16r19,	# DH_anon_EXPORT_WITH_DES40_CBC_SHA
	byte 0, byte 16r1A,	# DH_anon_WITH_DES_CBC_SHA
	byte 0, byte 16r1B,	# DH_anon_WITH_3DES_EDE_CBC_SHA
	
	byte 0, byte 16r1C,	# FORTEZZA_KEA_WITH_NULL_SHA
	byte 0, byte 16r1D,	# FORTEZZA_KEA_WITH_FORTEZZA_CBC_SHA
	byte 0, byte 16r1E,	# FORTEZZA_KEA_WITH_RC4_128_SHA
};
ssl_comprs := array [] of {byte 0};
usessl:= 0;
sslx : ref Context;

FD, Connection: import sys;
Iobuf : import bufio;

ibuf, obuf : ref Bufio->Iobuf;
conn : int = 0;
init : int = 0;
 
rpid : int = -1;
cread : chan of (int, string);
base64: Encoding;
db: ref Db;
dbfile := "/lib/ndb/local";

DEBUG : con 0;

open(server : string): (int, string)
{
	s : string;
 
	if (!init) {
		sys = load Sys Sys->PATH;
		bufio = load Bufio Bufio->PATH;
		init = 1;
	}
	if (conn)
		return (-1, "connection is already open");
	if (server == nil)
		server = "$smtp";
	(ok, c) := sys->dial ("tcp!" + server + "!25", nil);
	if (ok < 0)
		return (-1, "dialup failed");
 
	ibuf = bufio->fopen(c.dfd, Bufio->OREAD);
	obuf = bufio->fopen(c.dfd, Bufio->OWRITE);
	if (ibuf == nil || obuf == nil)
		return (-1, "failed to open bufio");
	cread = chan of (int, string);
	spawn mreader(cread);
	(rpid, nil) = <- cread;
	
 	(ok, s) = mread();
	if (ok < 0)
		return (-1, s);
	conn = 1;
	return (1, nil);
}
 
authopen(user, password, server : string, usesslarg: int): (int, string)
{
	s : string;
 
 	usessl = usesslarg;
	if (!init) {
		sys = load Sys Sys->PATH;
		bufio = load Bufio Bufio->PATH;
		base64 = load Encoding Encoding->BASE64PATH;
		attrdb = load Attrdb Attrdb->PATH;
		if(attrdb == nil)
			return (-1, "cannot load Attrdb");
		attrdb->init();
		ip = load IP IP->PATH;
		if(ip == nil)
			return (-1, "cannot load IP");
		ip->init();
		ipattr = load IPattr IPattr->PATH;
		if(ipattr == nil)
			return (-1, "cannot load IPattr");
		ipattr->init(attrdb, ip);
		db = Db.open(dbfile);
		init = 1;
	}
	if (conn)
		return (-1, "connection is already open");
	if (server == nil)
		server = "$smtp";
	addr: string;
	if(usessl)
		addr = "tcp!" + server + "!465";
	else
		addr = "tcp!" + server + "!25";
	(ok, c) := sys->dial (addr, nil);
	if (ok < 0)
		return (-1, "dialup failed");
	if(DEBUG)
		sys->print("usessl\n");
	if(usessl){
		ssl3 = load SSL3 SSL3->PATH;
		ssl3->init();
		sslx = ssl3->Context.new();
#		sslx.use_devssl();
		vers := 3;
		e: string;
		info := ref SSL3->Authinfo(ssl_suites, ssl_comprs, nil, 0, nil, nil, nil);
		(e, vers) = sslx.client(c.dfd, addr, vers, info);
		if(e != "") {
			return (-1, s);
		}
		if(DEBUG)
			sys->print("SSL HANDSHAKE completed\n");
		cread = chan of (int, string);
		spawn tlsreader(cread);
		(rpid, nil) = <- cread;
	}else{
		ibuf = bufio->fopen(c.dfd, Bufio->OREAD);
		obuf = bufio->fopen(c.dfd, Bufio->OWRITE);
		if (ibuf == nil || obuf == nil)
			return (-1, "failed to open bufio");
		cread = chan of (int, string);
		spawn mreader(cread);
		(rpid, nil) = <- cread;
	}
	
 	(ok, s) = mread();
	if (ok < 0)
		return (-1, s);
	
	hostname := readfile("/dev/sysname");
	(domain, err) := ipattr->findnetattr(db, "sys", hostname, "dom");

	if(err != nil){
		sys->fprint(sys->fildes(2), "smtp: %s\n", err);
		domain=hostname;
	}
	(ok, s) = mcmd("HELO "+domain);
	if(ok < 0)
		return (-1, s);
	(ok, s) = mcmd("AUTH PLAIN");
	if(ok < 0)
		return (-1, s);
	auths := user + "\0" + user + "\0" + password;
	(ok, s) = mcmd(base64->enc(array of byte auths));
	if (ok < 0)
		return (-1, s);

	conn = 1;
	return (1, nil);
}
 
sendmail (fromwho : string, towho : list of string, cc : list of string, mlist: list of string): (int, string)
{
	ok : int;
	s, t, line : string;

	if (!conn)
		return (-1, "connection is not open");
	(ok, s) = mcmd("RSET");
	if (ok < 0)
		return (-1, s);
	(user, dom) := split(fromwho, '@');
	if (fromwho == nil || user == nil)
		return (-1, "no 'from' name");
	if (towho == nil)
		return (-1, "no 'to' name");
	if (dom == nil)
		return (-1, "no domain name");
	if(!usessl){
		(ok, s) = mcmd("HELO " + dom);
		if (ok < 0)
			return (-1, s);
	}
	(ok, s) = mcmd("MAIL FROM:<" + fromwho + ">");
	if (ok < 0)
		return (-1, s);
	all := concat(towho, cc);
	t = nil;
	for ( ; all != nil; all = tl all) {
		(ok, s) = mcmd("RCPT TO:<" + hd all + ">");
		if (ok < 0)
			t += " " + s;
	}
	if (t != nil)
		return (-1, t);
	(ok, s) = mcmd("DATA");
	if (ok < 0)
		return (-1, s);
	for ( ; mlist != nil; mlist = tl mlist) {
		for (msg := hd mlist; msg != nil; ) {
			(line, msg) = split(msg, '\n');	# BUG: too much copying for larger messages
			if (putline(line) < 0)
				return (-1, sys->sprint("write to server failed: %r"));
		}
	}
#	obuf.flush();
	(ok, s) = mcmd(".");      
	if (ok < 0)  
		return (-1, s);  
	return (1, nil);
}

putline(line: string): int
{
	ln := len line;
	if (ln > 0 && line[ln-1] == '\r')
		line = line[0:ln-1];
	if (line != nil && line[0] == '.'){
		line = "." + line;
	}
	return mwrite(line);
}

close(): (int, string)
{
	ok : int;
 
	if (!conn)
		return (-1, "connection is not open");
	ok = mwrite("QUIT");
	kill(rpid);
	if(!usessl){
		ibuf.close();
		obuf.close();
	}
	conn = 0;
	if (ok < 0)
		return (-1, "failed to close connection");
	return (1, nil);
}
 
SLPTIME : con 100;
MAXSLPTIME : con 10000;

mread() : (int, string)
{
	t := 0;
	while (t < MAXSLPTIME) {
		alt {
			(ok, s) := <- cread =>
				return (ok, s);
			* =>
				t += SLPTIME;
				sys->sleep(SLPTIME);
		}
	}
	kill(rpid);
	return (-1, "smtp timed out\n");		
}

mreader(c : chan of (int, string))
{
	c <- = (sys->pctl(0, nil), nil);
	for (;;) {
		line := ibuf.gets('\n');
		if (DEBUG)
			sys->print("mread : %s", line);
		if (line == nil) {
			c <- = (-1, "could not read response from server");
			continue;
		}
		l := len line;
		if (line[l-1] == '\n')
			l--;
		if (line[l-1] == '\r')
			l--;
		if (l < 3) {
			c <- = (-1, "short response from server");
			continue;
		}
		if (l > 0 && (line[0] == '1' || line[0] == '2' || line[0] == '3')) {
			c <- = (1, nil);
			continue;
		}
		c <- = (-1, line[3:l]);
	}
}
 
mwrite(s : string): int
{
	s += "\r\n";
	if (DEBUG)
		sys->print("mwrite : %s", s);
	b := array of byte s;
	l := len b;
	nb: int;
	if(!usessl){
		nb = obuf.write(b, l);
		obuf.flush();
	}else{
		nb = sslx.write(b,l);
	}
	if (nb != l)
		return -1;
	return 1;
}
 
mcmd(s : string) : (int, string)
{
	ok : int;
	r : string;

	ok = mwrite(s);
	if (ok < 0)
		return (-1, err(s) + " send failed");
	(ok, r) = mread();
	if (ok < 0)
		return (-1, err(s) + " receive failed (" + r + ")");
	return (1, nil);
}

split(s : string, c : int) : (string, string)
{
	for (i := 0; i < len s; i++)
		if (s[i] == c)
			return (s[0:i], s[i+1:]);
	return (s, nil);
}

concat(l1, l2 : list of string) : list of string
{
	ls : list of string;

	ls = nil;
	for (l := l1; l != nil; l = tl l)
		ls = hd l :: ls;
	for (l = l2; l != nil; l = tl l)
		ls = hd l :: ls;
	return ls;
}

err(s : string) : string
{
	for (i := 0; i < len s; i++)
		if (s[i] == ' ' || s[i] == ':')
			return s[0:i];
	return s;
}

kill(pid : int) : int
{
	if (pid < 0)
		return 0;
	fd := sys->open("#p/" + string pid + "/ctl", sys->OWRITE);
	if (fd == nil || sys->fprint(fd, "kill") < 0)
		return -1;
	return 0;
}

tlsreader(c : chan of (int, string))
{
	buf := array[1] of byte;
	lin := array[1024] of byte;
	c <- = (sys->pctl(0, nil), nil);
	k := 0;
	for (;;) {
		n := sslx.read(buf, len buf);
		if(n < 0){
			c <- = (-1, "could not read response from server");
			continue;
		}
		lin[k++] = buf[0];
		if(int buf[0] == '\n'){
			line := string lin[0:k];
			if (DEBUG)
				sys->print("tlsreader : %s", line);
			l := len line - 1;
			if (line[l-1] == '\r')
				l--;
			c <- = (1, line[0:l]);
			k = 0;
		}
	}
}

readfile(f : string) : string
{
	fd := sys->open(f, sys->OREAD);
	if(fd == nil)
		return nil;
	buf := array[128] of byte;
	n := sys->read(fd, buf, len buf);
	if(n < 0)
		return nil;
	return string buf[0:n];	
}
