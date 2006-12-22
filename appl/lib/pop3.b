implement Pop3;
 
include "sys.m";
	sys : Sys;
include "draw.m";
include "bufio.m";
	bufio : Bufio;
include "pop3.m";

FD, Connection: import sys;
Iobuf : import bufio;

ibuf, obuf : ref Bufio->Iobuf;
conn : int = 0;
inited : int = 0;
 
rpid : int = -1;
cread : chan of (int, string);

DEBUG : con 0;

open(user, password, server : string): (int, string)
{
	s : string;
 
	if (!inited) {
		sys = load Sys Sys->PATH;
		bufio = load Bufio Bufio->PATH;
		inited = 1;
	}
	if (conn)
		return (-1, "connection is already open");
	if (server == nil) {
		server = defaultserver();
		if (server == nil)
			return (-1, "no default mail server");
	}
	(ok, c) := sys->dial ("tcp!" + server + "!110", nil);
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
	(ok, s) = mcmd("USER " + user);
	if (ok < 0)
		return (-1, s);
	(ok, s) = mcmd("PASS " + password);
	if (ok < 0)
		return (-1, s);
	conn = 1;
	return (1, nil);
}

stat() : (int, string, int, int)
{
	if (!conn)
		return (-1, "not connected", 0, 0);
	(ok, s) := mcmd("STAT");
	if (ok < 0)
		return (-1, s, 0, 0);
	(n, ls) := sys->tokenize(s, " ");
	if (n == 3)
		return (1, nil, int hd tl ls, int hd tl tl ls);
	return (-1, "stat failed", 0, 0);
}
	
msglist() : (int, string, list of (int, int))
{
	ls : list of (int, int);

	if (!conn)
		return (-1, "not connected", nil);
	(ok, s) := mcmd("LIST");
	if (ok < 0)
		return (-1, s, nil);
	for (;;) {
		(ok, s) = mread();
		if (ok < 0)
			return (-1, s, nil);
		if (len s < 3) {
			if (len s > 0 && s[0] == '.')
				return (1, nil, rev2(ls));
			else
				return (-1, s, nil);
		}
		else {
			(n, sl) := sys->tokenize(s, " ");
			if (n == 2)
				ls = (int hd sl, int hd tl sl) :: ls;
			else
				return (-1, "bad list format", nil);
		}
	}
}

msgnolist() : (int, string, list of int)
{
	ls : list of int;

	if (!conn)
		return (-1, "not connected", nil);
	(ok, s) := mcmd("LIST");
	if (ok < 0)
		return (-1, s, nil);
	for (;;) {
		(ok, s) = mread();
		if (ok < 0)
			return (-1, s, nil);
		if (len s < 3) {
			if (len s > 0 && s[0] == '.')
				return (1, nil, rev1(ls));
			else
				return (-1, s, nil);
		}
		else {
			(n, sl) := sys->tokenize(s, " ");
			if (n == 2)
				ls = int hd sl :: ls;
			else
				return (-1, "bad list format", nil);
		}
	}
}

top(m : int) : (int, string, string)
{
	if (!conn)
		return (-1, "not connected", nil);
	(ok, s) := mcmd("TOP " + string m + " 1");
	if (ok < 0)
		return (-1, s, nil);
	return getbdy();
}

get(m : int) : (int, string, string)
{
	if (!conn)
		return (-1, "not connected", nil);
	(ok, s) := mcmd("RETR " + string m);
	if (ok < 0)
		return (-1, s, nil);
	return getbdy();
}
	
getbdy() : (int, string, string)
{
	b : string;

	for (;;) {
		(ok, s) := mread();
		if (ok < 0)
			return (-1, s, nil);
		if (s == ".")
			break;
		if (len s > 1 && s[0] == '.' && s[1] == '.')
			s = s[1:];
		b = b + s + "\n";
	}
	return (1, nil, b);
}
	
delete(m : int) : (int, string)
{
	if (!conn)
		return (-1, "not connected");
	return mcmd("DELE " + string m);
}
			
close(): (int, string)
{
	if (!conn)
		return (-1, "connection not open");
	ok := mwrite("QUIT");
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
		c <- = (1, line[0:l]);
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
	if (len r > 1 && r[0] == '+')
		return (1, r);
	return (-1, r);
}

defaultserver() : string
{
	return "$pop3";
}

rev1(l1 : list of int) : list of int
{
	l2 : list of int;

	for ( ; l1 != nil; l1 = tl l1)
		l2 = hd l1 :: l2;
	return l2;
}

rev2(l1 : list of (int, int)) : list of (int, int)
{
	l2 : list of (int, int);

	for ( ; l1 != nil; l1 = tl l1)
		l2 = hd l1 :: l2;
	return l2;
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
