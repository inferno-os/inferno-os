implement Sendmail;

include "sys.m";
   	sys: Sys;
include "draw.m";
include "bufio.m";
include "daytime.m";
include "smtp.m";
include "env.m";

sprint, fprint : import sys;

DEBUG : con 0;
STRMAX : con 512;

Sendmail : module
{
	PATH : con "/dis/sendmail.dis";

	# argv is list of persons to send mail to (or nil if To: lines present in message)
	# mail is read from standard input
	# scans mail for headers (From: , To: , Cc: , Subject: , Re: ) where case is not sensitive
	init: fn(ctxt : ref Draw->Context, argv : list of string);
};

init(nil : ref Draw->Context, args : list of string) {
	from : string;
	tos, cc : list of string = nil;

  	sys = load Sys Sys->PATH;
	smtp := load Smtp Smtp->PATH;
  	if (smtp == nil)
    		error(sprint("cannot load %s", Smtp->PATH), 1);
	daytime := load Daytime Daytime->PATH;
	if (daytime == nil)
		error(sprint("cannot load %s", Daytime->PATH), 1);
	msgl := readin();
	for (ml := msgl; ml != nil; ml = tl ml) {
		msg := hd ml;
		lenm := len msg;
		sol := 1;
		for (i := 0; i < lenm; i++) {
			if (sol) {
				for (j := i; j < lenm; j++)
					if (msg[j] == '\n')
						break;
				s := msg[i:j];
				if (from == nil) {
					from = match(s, "from");
					if (from != nil)
						from = extract(from);
				}
				if (tos == nil)
					tos = lmatch(s, "to");
				if (cc == nil)
					cc = lmatch(s, "cc");
				sol = 0;
			}
			if (msg[i] == '\n')
				sol = 1;
		}
	}
	if (tos != nil && tl args != nil)
		error("recipients specified on To: line and as args - aborted", 1);
	if (from == nil)
		from = readfile("/dev/user");
	from = adddom(from);
	if (tos == nil)
		tos = tl args;
	(ok, err) := smtp->open(nil);
  	if (ok < 0) {
		smtp->close();
    		error(sprint("smtp open failed: %s", err), 1);
	}
	dump(from, tos, cc, msgl);
	msgl = "From " + from + "\t" + daytime->time() + "\n" :: msgl;
	# msgl = "From: " + from + "\n" + "Date: " + daytime->time() + "\n" :: msgl;
	(ok, err) = smtp->sendmail(from, tos, cc, msgl);
	if (ok < 0) {
		smtp->close();
		error(sprint("send failed : %s", err), 0);
	}
	smtp->close();
}

readin() : list of string
{
	m : string;
	ls : list of string;
	nc : int;

	bufio := load Bufio Bufio->PATH;
	Iobuf : import bufio;
	b := bufio->fopen(sys->fildes(0), Bufio->OREAD);
	ls = nil;
	m = nil;
	nc = 0;
	while ((s := b.gets('\n')) != nil) {
		if (nc > STRMAX) {
			ls = m :: ls;
			m = nil;
			nc = 0;
		}
		m += s;
		nc += len s;
	}
	b.close();
	if (m != nil)
		ls = m :: ls;
	return rev(ls);
}

match(s: string, pat : string) : string
{
	ls := len s;
	lp := len pat;
	if (ls < lp)
		return nil;
	for (i := 0; i < lp; i++) {
		c := s[i];
		if (c >= 'A' && c <= 'Z')
			c += 'a'-'A';
		if (c != pat[i])
			return nil;
	}
	if (i < len s && s[i] == ':')
		i++;
	else if (i < len s - 1 && s[i] == ' ' && s[i+1] == ':')
		i += 2;
	else
		return nil;
	while (i < len s && (s[i] == ' ' || s[i] == '\t'))
		i++;
	j := ls-1;
	while (j >= 0 && (s[j] == ' ' || s[j] == '\t' || s[j] == '\n'))
		j--;
	return s[i:j+1];
}
	
lmatch(s : string, pat : string) : list of string
{
	r := match(s, pat);
	if (r != nil) {
		(ok, lr) := sys->tokenize(r, " ,\t");
		return lr;
	}
	return nil;
}
	
extract(s : string) : string
{
	ls := len s;
	for(i := 0; i < ls; i++) {
		if(s[i] == '<') {
			for(j := i+1; j < ls; j++)
				if(s[j] == '>')
					break;
			return s[i+1:j];
		}
	}
	return s;
}

adddom(s : string) : string
{
	if (s == nil)
		return nil;
	for (i := 0; i < len s; i++)
		if (s[i] == '@')
			return s;
	# better to get it from environment if possible
	env := load Env Env->PATH;
	if (env != nil && (dom := env->getenv("DOMAIN")) != nil) {
		ldom := len dom;
		if (dom[ldom - 1] == '\n')
			dom = dom[0:ldom - 1];
		return s + "@" + dom;
	}
	d := readfile("/usr/" + s + "/mail/domain");
	if (d != nil) {
		ld := len d;
		if (d[ld - 1] == '\n')
			d = d[0:ld - 1];
		return s + "@" + d;
	}
	return s;
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

rev(l1 : list of string) : list of string
{
	l2 : list of string = nil;

	for ( ; l1 != nil; l1 = tl l1)
		l2 = hd l1 :: l2;
	return l2;
}

lprint(fd : ref Sys->FD, ls : list of string)
{
	for ( ; ls != nil; ls = tl ls)
		fprint(fd, "%s ", hd ls);
	fprint(fd, "\n");
}

cfd : ref Sys->FD;

opencons()
{
	if (cfd == nil)
		cfd = sys->open("/dev/cons", Sys->OWRITE);
}

dump(from : string, tos : list of string, cc : list of string, msgl : list of string)
{
	if (DEBUG) {
		opencons();
		fprint(cfd, "from\n");
		fprint(cfd, "%s\n", from);
		fprint(cfd, "to\n");
		lprint(cfd, tos);
		fprint(cfd, "cc\n");
		lprint(cfd, cc);
		fprint(cfd, "message\n");
		for ( ; msgl != nil; msgl = tl msgl) {
			fprint(cfd, "%s", hd msgl);
			fprint(cfd, "xxxx\n");
		}
	}
}

error(s : string, ex : int)
{
	if (DEBUG) {
		opencons();
		fprint(cfd, "sendmail: %s\n", s);
	}
	fprint(sys->fildes(2), "sendmail: %s\n", s);
	if (ex)
		exit;
}
