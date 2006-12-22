implement Cookiesrv;
include "sys.m";
include "bufio.m";
include "string.m";
include "daytime.m";
include "cookiesrv.m";

sys: Sys;
bufio: Bufio;
S: String;
daytime: Daytime;

Iobuf: import bufio;

Cookielist: adt {
	prev: cyclic ref Cookielist;
	next: cyclic ref Cookie;
};

Cookie: adt {
	name: string;
	value: string;
	dom: string;
	path: string;
	expire: int;		# seconds from epoch, -1 => not set, 0 => expire now
	secure: int;
	touched: int;
	link: cyclic ref Cookielist;	# linkage for list of cookies in the same domain
};

Domain: adt {
	name: string;
	doms: cyclic list of ref Domain;
	cookies: ref Cookielist;
};

MAXCOOKIES: con 300;		# total number of cookies allowed
LISTMAX: con 20;			# max number of cookies per Domain
PURGENUM: con 30;			# number of cookies to delete when freeing up space
MAXCKLEN: con 4*1024;		# max cookie length

ncookies := 0;
doms: list of ref Domain;
now: int;	# seconds since epoch
cookiepath: string;
touch := 0;

start(path: string, saveinterval: int): ref Client
{
	sys = load Sys Sys->PATH;
	bufio = load Bufio Bufio->PATH;
	if (bufio == nil) {
		sys->print("cookiesrv: cannot load %s: %r\n", Bufio->PATH);
		return nil;
	}
	S = load String String->PATH;
	if (S == nil) {
		sys->print("cookiesrv: cannot load %s: %r\n", String->PATH);
		return nil;
	}
	daytime = load Daytime Daytime->PATH;
	if (daytime == nil) {
		sys->print("cookiesrv: cannot load %s: %r\n", Daytime->PATH);
		return nil;
	}

	cookiepath = path;
	now = daytime->now();

	# load the cookie file
	# order is most recently touched first 
	iob := bufio->open(cookiepath, Sys->OREAD);
	if (iob != nil) {
		line: string;
		while ((line = iob.gets('\n')) != nil) {
			if (line[len line -1] == '\n')
				line = line[:len line -1];
			loadcookie(line);
		}
		iob.close();
		iob = nil;
		expire();
	}
	fdc := chan of ref Sys->FD;
	spawn server(fdc, saveinterval);
	fd := <- fdc;
	if (fd == nil)
		return nil;
	return ref Client(fd);
}

addcookie(ck: ref Cookie, domlist: ref Cookielist)
{
	(last, n) := lastlink(domlist);
	if (n == LISTMAX)
		rmcookie(last.prev.next);
	if (ncookies == MAXCOOKIES)
		rmlru();
	ck.link = ref Cookielist(domlist, domlist.next);
	if (domlist.next != nil)
		domlist.next.link.prev = ck.link;
	domlist.next = ck;
	ncookies++;
}

rmcookie(ck: ref Cookie)
{
	nextck := ck.link.next;
	ck.link.prev.next = nextck;
	if (nextck != nil) 
		nextck.link.prev = ck.link.prev;
	ncookies--;
}

lastlink(ckl: ref Cookielist): (ref Cookielist, int)
{
	n := 0;
	for (nckl := ckl.prev; nckl != nil; nckl = nckl.prev)
		n++;
	for (; ckl.next != nil; ckl = ckl.next.link)
		n++;
	return (ckl, n);
}

rmlru()
{
	cka := array [ncookies] of ref Cookie;
	ix := getallcookies(doms, cka, 0);
	if (ix < PURGENUM)
		return;
	mergesort(cka, nil, SORT_TOUCHED);
	for (n := 0; n < PURGENUM; n++)
		rmcookie(cka[n]);
}

getallcookies(dl: list of ref Domain, cka: array of ref Cookie, ix: int): int
{
	for (; dl != nil; dl = tl dl) {
		dom := hd dl;
		for (ck := dom.cookies.next; ck != nil; ck = ck.link.next)
			cka[ix++] = ck;
		ix = getallcookies(dom.doms, cka, ix);
	}
	return ix;
}

isipaddr(s: string): int
{
	# assume ipaddr if only numbers and '.'s
	# should maybe count the dots too (what about IPV6?)
	return S->drop(s, ".0123456789") == nil;
}

setcookie(ck: ref Cookie)
{
	parent, dom: ref Domain;
	domain := ck.dom;
	if (isipaddr(domain))
		(parent, dom, domain) = getdom(doms, nil, domain);
	else
		(parent, dom, domain) = getdom(doms, domain, nil);

	if (dom == nil)
		dom = newdom(parent, domain);

	for (oldck := dom.cookies.next; oldck != nil; oldck = oldck.link.next) {
		if (ck.name == oldck.name && ck.path == oldck.path) {
			rmcookie(oldck);
			break;
		}
	}
	if (ck.expire > 0 && ck.expire <= now)
		return;
	addcookie(ck, dom.cookies);
}

expire()
{
	cka := array [ncookies] of ref Cookie;
	ix := getallcookies(doms, cka, 0);
	for (i := 0; i < ix; i++) {
		ck := cka[i];
		if (ck.expire > 0 && ck.expire < now)
			rmcookie(ck);
	}
}

newdom(parent: ref Domain, domain: string): ref Domain
{
	while (domain != "") {
		(lhs, rhs) := splitdom(domain);
		d := ref Domain(rhs, nil, ref Cookielist(nil, nil));
		if (parent == nil)
			doms = d :: doms;
		else
			parent.doms = d :: parent.doms;
		parent = d;
		domain = lhs;
	}
	return parent;
}

getdom(dl: list of ref Domain, lhs, rhs: string): (ref Domain, ref Domain, string)
{
	if (rhs == "")
		(lhs, rhs) = splitdom(lhs);
	parent: ref Domain;
	while (dl != nil) {
		d := hd dl;
		if (d.name != rhs) {
			dl = tl dl;
			continue;
		}
		# name matches
		if (lhs == nil)
			return (parent, d, rhs);
		parent = d;
		(lhs, rhs) = splitdom(lhs);
		dl = d.doms;
	}
	return (parent, nil, lhs+rhs);
}

# returned list is in shortest to longest domain match order
getdoms(dl: list of ref Domain, lhs, rhs: string): list of ref Domain
{
	if (rhs == "")
		(lhs, rhs) = splitdom(lhs);
	for (; dl != nil; dl = tl dl) {
		d := hd dl;
		if (d.name == rhs) {
			if (lhs == nil)
				return d :: nil;
			(lhs, rhs) = splitdom(lhs);
			return d :: getdoms(d.doms, lhs, rhs);
		}
	}
	return nil;
}

server(fdc: chan of ref Sys->FD, saveinterval: int)
{
	sys->pctl(Sys->NEWPGRP|Sys->FORKNS, nil);
	sys->bind("#s", "/chan", Sys->MBEFORE);
	fio := sys->file2chan("/chan", "ctl");
	if (fio == nil) {
		fdc <-= nil;
		return;
	}
	fd := sys->open("/chan/ctl", Sys->OWRITE);
	fdc <-= fd;
	if (fd == nil)
		return;
	fd = nil;
		
	tick := chan of int;
	spawn ticker(tick, 1*60*1000);	# clock tick once a minute
	tickerpid := <- tick;

	modified := 0;
	savetime := now + saveinterval;

	for (;;) alt {
	now = <- tick =>
		expire();
		if (saveinterval != 0 && now > savetime) {
			if (modified) {
				save();
				modified = 0;
			}
			savetime = now + saveinterval;
		}
	(nil, line, nil, rc) := <- fio.write =>
		now = daytime->now();
		if (rc == nil) {
			kill(tickerpid);
			expire();
			save();
			return;
		}
		loadcookie(string line);
		alt {
		rc <-= (len line, nil) =>
			;
		* =>
			;
		};
		modified = 1;
	}
}

ticker(tick: chan of int, ms: int)
{
	tick <-= sys->pctl(0, nil);
	for (;;) {
		sys->sleep(ms);
		tick <-= daytime->now();
	}
}

# sort orders
SORT_TOUCHED, SORT_PATHLEN: con iota;

mergesort(a, b: array of ref Cookie, order: int)
{
	if (b == nil)
		b = array [len a] of ref Cookie;
	r := len a;
	if (r > 1) {
		m := (r-1)/2 + 1;
		mergesort(a[0:m], b[0:m], order);
		mergesort(a[m:], b[m:], order);
		b[0:] = a;
		for ((i, j, k) := (0, m, 0); i < m && j < r; k++) {
			if (greater(b[i], b[j], order))
				a[k] = b[j++];
			else
				a[k] = b[i++];
		}
		if (i < m)
			a[k:] = b[i:m];
		else if (j < r)
			a[k:] = b[j:r];
	}
}

greater(x, y: ref Cookie, order: int): int
{
	if (y == nil)
		return 0;
	case order {
	SORT_TOUCHED =>
		if (x.touched > y.touched)
			return 1;
	SORT_PATHLEN =>
		if (len x.path < len y.path)
			return 1;
	}
	return 0;
}

cookie2str(ck: ref Cookie): string
{
	if (len ck.name +1 > MAXCKLEN)
		return "";
	namval := sys->sprint("%s=%s", ck.name, ck.value);
	if (len namval > MAXCKLEN)
		namval = namval[:MAXCKLEN];
	return sys->sprint("%s\t%s\t%d\t%d\t%s", ck.dom, ck.path, ck.expire, ck.secure, namval);
}

loadcookie(ckstr: string)
{
	(n, toks) := sys->tokenize(ckstr, "\t");
	if (n < 5)
		return;
	dom, path, exp, sec, namval: string;
	(dom, toks) = (hd toks, tl toks);
	(path, toks) = (hd toks, tl toks);
	(exp, toks) = (hd toks, tl toks);
	(sec, toks) = (hd toks, tl toks);
	(namval, toks) = (hd toks, tl toks);

	# some sanity checks
	if (dom == "" || path == "" || path[0] != '/')
		return;

	(name, value) := S->splitl(namval, "=");
	if (value == nil)
		return;
	value = value[1:];
	ck := ref Cookie(name, value, dom, path, int exp, int sec, touch++, nil);
	setcookie(ck);
}

Client.set(c: self ref Client, host, path, cookie: string)
{
	ck := parsecookie(host, path, cookie);
	if (ck == nil)
		return;
	b := array of byte cookie2str(ck);
	sys->write(c.fd, b, len b);
}

Client.getcookies(nil: self ref Client, host, path: string, secure: int): string
{
	dl: list of ref Domain;
	if (isipaddr(host))
		dl = getdoms(doms, nil, host);
	else {
		# note some domains match hosts
		# e.g. site X.com has to set a cookie for '.X.com'
		# to get around the netscape '.' count check
		# this messes up our domain checking
		# putting a '.' on the front of host is a safe way of handling this
#		host = "." + host;
		dl = getdoms(doms, host, nil);
	}
	cookies: list of ref Cookie;
	for (; dl != nil; dl = tl dl) {
		ckl := (hd dl).cookies;
		for (ck := ckl.next; ck != nil; ck = ck.link.next) {
			if (ck.secure && !secure)
				continue;
			if (!S->prefix(ck.path, path))
				continue;
			ck.touched = touch++;
			cookies = ck :: cookies;
		}
	}
	if (cookies == nil)
		return "";

	# sort w.r.t path len and creation order
	cka := array [len cookies] of ref Cookie;
	for (i := 0; cookies != nil; cookies = tl cookies)
		cka[i++] = hd cookies;

	mergesort(cka, nil, SORT_PATHLEN);

	s := sys->sprint("%s=%s", cka[0].name, cka[0].value);
	for (i = 1; i < len cka; i++)
		s += sys->sprint("; %s=%s", cka[i].name, cka[i].value);
	return s;
}

save()
{
	fd := sys->create(cookiepath, Sys->OWRITE, 8r600);
	if (fd == nil)
		return;
	cka := array [ncookies] of ref Cookie;
	ix := getallcookies(doms, cka, 0);
	mergesort(cka, nil, SORT_TOUCHED);

	for (i := 0; i < ncookies; i++) {
		ck := cka[i];
		if (ck.expire > now)
			sys->fprint(fd, "%s\n", cookie2str(cka[i]));
	}
}

parsecookie(dom, path, cookie: string): ref Cookie
{
	defpath := "/";
	if (path != nil)
		(defpath, nil) = S->splitr(path, "/");

	(nil, toks) := sys->tokenize(cookie, ";");
	namval := hd toks;
	toks = tl toks;

	(name, value) := S->splitl(namval, "=");
	name = trim(name);
	if (value != nil && value[0] == '=')
		value = value[1:];
	value = trim(value);

	ck := ref Cookie(name, value, dom, defpath, -1, 0, 0, nil);
	for (; toks != nil; toks = tl toks) {
		(name, value) = S->splitl(hd toks, "=");
		if (value != nil && value[0] == '=')
			value = value[1:];
		name = trim(name);
		value = trim(value);
		case S->tolower(name) {
		"domain" =>
			ck.dom = value;
		"expires" =>
			ck.expire = date2sec(value);
		"path" =>
			ck.path = value;
		"secure" =>
			ck.secure = 1;
		}
	}
	if (ckcookie(ck, dom, path))
		return ck;
	return nil;
}

# Top Level Domains as defined in Netscape cookie spec
tld := array [] of {
	".com", ".edu", ".net", ".org", ".gov", ".mil", ".int"
};

ckcookie(ck: ref Cookie, host, path: string): int
{
#dumpcookie(ck, "CKCOOKIE");
	if (ck == nil)
		return 0;
	if (ck.path == "" || ck.dom == "")
		return 0;
	if (host == "" || path == "")
		return 1;

# netscape does no path check on accpeting a cookie
# any page can set a cookie on any path within its domain.
# the filtering is done when sending cookies back to the server
#	if (!S->prefix(ck.path, path))
#		return 0;

	if (host == ck.dom)
		return 1;
	if (ck.dom[0] != '.' || len host < len ck.dom)
		return 0;

	ipaddr := S->drop(host, ".0123456789") == nil;
	if (ipaddr)
		# ip addresses have to match exactly
		return 0;

	D := host[len host - len ck.dom:];
	if (D != ck.dom)
		return 0;

	# netscape specific policy
	ndots := 0;
	for (i := 0; i < len D; i++)
		if (D[i] == '.')
			ndots++;
	for (i = 0; i < len tld; i++) {
		if (len D >= len tld[i] && D[len D - len tld[i]:] == tld[i]) {
			if (ndots < 2)
				return 0;
			return 1;
		}
	}
	if (ndots < 3)
		return 0;
	return 1;
}

trim(s: string): string
{
	is := 0;
	ie := len s;
	while(is < ie) {
		c := s[is];
		if(!(c == ' ' || c == '\t'))
			break;
		is++;
	}
	if(is == ie)
		return "";
	while(ie > is) {
		c := s[ie-1];
		if(!(c == ' ' || c == '\t'))
			break;
		ie--;
	}
	if(is >= ie)
		return "";
	if(is == 0 && ie == len s)
		return s;
	return s[is:ie];
}

kill(pid: int)
{
	sys->fprint(sys->open("/prog/"+string pid+"/ctl", Sys->OWRITE), "kill");
}

date2sec(date: string): int
{
	Tm: import daytime;
	tm := daytime->string2tm(date);
	if(tm == nil || tm.year < 70 || tm.zone != "GMT")
		t := -1;
	else
		t = daytime->tm2epoch(tm);
	return t;
}

dumpcookie(ck: ref Cookie, msg: string)
{
	if (msg != nil)
		sys->print("%s: ", msg);
	if (ck == nil)
		sys->print("NIL\n");
	else {
		dbgval := ck.value;
		if (len dbgval > 10)
			dbgval = dbgval[:10];
		sys->print("dom[%s], path[%s], name[%s], value[%s], secure=%d\n", ck.dom, ck.path, ck.name, dbgval, ck.secure);
	}
}

splitdom(s: string): (string, string)
{
	for (ie := len s -1; ie > 0; ie--)
		if (s[ie] == '.')
			break;
	return (s[:ie], s[ie:]);
}
