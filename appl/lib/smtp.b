implement Smtp;
 
include "sys.m";
	sys : Sys;
include "bufio.m";
	bufio : Bufio;
include "dial.m";
	dial: Dial;
include "smtp.m";

FD, Connection: import sys;
Iobuf : import bufio;

ibuf, obuf : ref Bufio->Iobuf;
conn : int = 0;
init : int = 0;
 
rpid : int = -1;
cread : chan of (int, string);

DEBUG : con 0;

open(server : string): (int, string)
{
	s : string;
 
	if (!init) {
		sys = load Sys Sys->PATH;
		bufio = load Bufio Bufio->PATH;
		dial = load Dial Dial->PATH;
		init = 1;
	}
	if (conn)
		return (-1, "connection is already open");
	if (server == nil)
		server = "$smtp";
	else
		server = dial->netmkaddr(server, "tcp", "25");
	c := dial->dial(server, nil);
	if (c == nil)
		return (-1, "dialup failed");
	ibuf = bufio->fopen(c.dfd, Bufio->OREAD);
	obuf = bufio->fopen(c.dfd, Bufio->OWRITE);
	if (ibuf == nil || obuf == nil)
		return (-1, "failed to open bufio");
	cread = chan of (int, string);
	spawn mreader(cread);
	(rpid, nil) = <- cread;
	ok: int;
 	(ok, s) = mread();
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
	(ok, s) = mcmd("HELO " + dom);
	if (ok < 0)
		return (-1, s);
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
	obuf.flush();
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
		if(obuf.putb(byte '.') < 0)
			return -1;
	}
	if(line != nil && obuf.puts(line) < 0)
		return -1;
	return obuf.puts("\r\n");
}

close(): (int, string)
{
	ok : int;
 
	if (!conn)
		return (-1, "connection is not open");
	ok = mwrite("QUIT");
	kill(rpid);
	ibuf.close();
	obuf.close();
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
	nb := obuf.write(b, l);
	obuf.flush();
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
