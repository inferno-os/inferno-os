implement Dial;

include "sys.m";
	sys: Sys;

include "dial.m";

#
# the dialstring is of the form '[/net/]proto!dest'
#
dial(addr: string, local: string): ref Connection
{
	if(sys == nil)
		sys = load Sys Sys->PATH;
	(netdir, proto, rem) := dialparse(addr);
	if(netdir != nil)
		return csdial(netdir, proto, rem, local);

	c := csdial("/net", proto, rem, local);
	if(c != nil)
		return c;
	err := sys->sprint("%r");
	if(lookstr(err, "refused") >= 0)
		return nil;
	c = csdial("/net.alt", proto, rem, local);
	if(c != nil)
		return c;
	# ignore the least precise one
	alterr := sys->sprint("%r");
	if(lookstr(alterr, "translate")>=0 || lookstr(alterr, "does not exist")>=0)
		sys->werrstr(err);
	else
		sys->werrstr(alterr);
	return nil;
}

#
# ask the connection server to translate
#
csdial(netdir: string, proto: string, rem: string, local: string): ref Connection
{
	fd := sys->open(netdir+"/cs", Sys->ORDWR);
	if(fd == nil){
		# no connection server, don't translate
		return call(netdir+"/"+proto+"/clone", rem, local);
	}

	if(sys->fprint(fd, "%s!%s", proto, rem) < 0)
		return  nil;

	# try each recipe until we get one that works
	besterr, err: string;
	sys->seek(fd, big 0, 0);
	for(;;){
		(clonefile, addr) := csread(fd);
		if(clone == nil)
			break;
		c := call(redir(clonefile, netdir), addr, local);
		if(c != nil)
			return c;
		err = sys->sprint("%r");
		if(lookstr(err, "does not exist") < 0)
			besterr = err;
	}
	if(besterr != nil)
		sys->werrstr(besterr);
	else
		sys->werrstr(err);
	return nil;
}

call(clonefile: string, dest: string, local: string): ref Connection
{
	(cfd, convdir) := clone(clonefile);
	if(cfd == nil)
		return nil;

	if(local != nil)
		rv := sys->fprint(cfd, "connect %s %s", dest, local);
	else
		rv = sys->fprint(cfd, "connect %s", dest);
	if(rv < 0)
		return nil;

	fd := sys->open(convdir+"/data", Sys->ORDWR);
	if(fd == nil)
		return nil;
	return ref Connection(fd, cfd, convdir);
}

clone(clonefile: string): (ref Sys->FD, string)
{
	pdir := parent(clonefile);
	if(pdir == nil){
		sys->werrstr(sys->sprint("bad clone file name: %q", clonefile));
		return (nil, nil);
	}
	cfd := sys->open(clonefile, Sys->ORDWR);
	if(cfd == nil)
		return (nil, nil);
	lno := readchan(cfd);
	if(lno == nil)
		return (nil, nil);
	return (cfd, pdir+"/"+lno);
}

readchan(cfd: ref Sys->FD): string
{
	buf := array[Sys->NAMEMAX] of byte;
	n := sys->read(cfd, buf, len buf);
	if(n < 0)
		return nil;
	if(n == 0){
		sys->werrstr("empty clone file");
		return nil;
	}
	return string int string buf[0: n];
}

redir(old: string, newdir: string): string
{
	# because cs is in a different name space, replace the mount point
	# assumes the mount point is directory in root (eg, /net/proto/clone)
	if(len old > 1 && old[0] == '/'){
		p := lookc(old[1:], '/');
		if(p >= 0)
			return newdir+"/"+old[1+p+1:];
	}
	return newdir+"/"+old;
}

lookc(s: string, c: int): int
{
	for(i := 0; i < len s; i++)
		if(s[i] == c)
			return i;
	return -1;
}

backc(s: string, i: int, c: int): int
{
	if(i >= len s)
		return -1;
	while(i >= 0 && s[i] != c)
		i--;
	return i;
}

lookstr(s: string, t: string): int
{
	lt := len t;	# we know it's not zero
Search:
	for(i := 0; i <= len s - lt; i++){
		for(j := 0; j < lt; j++)
			if(s[i+j] != t[j])
				continue Search;
		return i;
	}
	return -1;
}

#
# [[/netdir/]proto!]remainder
#
dialparse(addr: string): (string, string, string)
{
	p := lookc(addr, '!');
	if(p < 0)
		return (nil, "net", addr);
	if(addr[0] != '/' && addr[0] != '#')
		return (nil, addr[0: p], addr[p+1:]);
	p2 := backc(addr, p, '/');
	if(p2 <= 0)
		return (addr[0: p], "net", addr[p+1:]);	# plan 9 returns proto ""
	return (addr[0: p2], addr[p2+1: p], addr[p+1:]);
}

#
# announce a network service
#
announce(addr: string): ref Connection
{
	if(sys == nil)
		sys = load Sys Sys->PATH;

	(naddr, clonefile) := nettrans(addr);
	if(naddr == nil)
		return nil;

	(ctl, convdir) := clone(clonefile);
	if(ctl == nil){
		sys->werrstr(sys->sprint("announce %r"));
		return nil;
	}

	if(sys->fprint(ctl, "announce %s", naddr) < 0){
		sys->werrstr(sys->sprint("announce writing %s: %r", clonefile));
		return nil;
	}

	return ref Connection(nil, ctl, convdir);
}

#
# listen for an incoming call on announced connection
#
listen(ac: ref Connection): ref Connection
{
	if(sys == nil)
		sys = load Sys Sys->PATH;

	pdir := parent(ac.dir);	# ac.dir should be /netdir/N
	if(pdir == nil){
		sys->werrstr(sys->sprint("listen directory format: %q", ac.dir));
		return nil;
	}

	ctl := sys->open(ac.dir+"/listen", Sys->ORDWR);
	if(ctl == nil){
		sys->werrstr(sys->sprint("listen opening %s: %r", ac.dir+"/listen"));
		return nil;
	}

	lno := readchan(ctl);
	if(lno == nil){
		sys->werrstr(sys->sprint("listen reading %s/listen: %r", ac.dir));
		return nil;
	}
	return ref Connection(nil, ctl, pdir+"/"+lno);

}

#
# translate an address [[/netdir/]proto!rem] using /netdir/cs
# returning (newaddress, clonefile)
#
nettrans(addr: string): (string, string)
{
	(netdir, proto, rem) := dialparse(addr);
	if(proto == nil || proto == "net"){
		sys->werrstr(sys->sprint("bad dial string: %s", addr));
		return (nil, nil);
	}
	if(netdir == nil)
		netdir = "/net";

	# try to translate using connection server
	fd := sys->open(netdir+"/cs", Sys->ORDWR);
	if(fd == nil){
		# use it untranslated
		if(rem == nil){
			sys->werrstr(sys->sprint("bad dial string: %s", addr));
			return (nil, nil);
		}
		return (rem, netdir+"/"+proto+"/clone");
	}
	if(sys->fprint(fd, "%s!%s", proto, rem) < 0)
		return (nil, nil);
	sys->seek(fd, big 0, 0);
	(clonefile, naddr) := csread(fd);
	if(clonefile == nil)
		return (nil, nil);

	return (naddr, redir(clonefile, netdir));
}

csread(fd: ref Sys->FD): (string, string)
{
	buf := array[Sys->NAMEMAX] of byte;
	n := sys->read(fd, buf, len buf);
	if(n < 0)
		return (nil, nil);
	line := string buf[0: n];
	p := lookc(line, ' ');
	if(p < 0)
		return (nil, nil);
	if(p == 0){
		sys->werrstr("cs: no translation");
		return (nil, nil);
	}
	return (line[0:p], line[p+1:]);
}

#
# accept a call, return an fd to the open data file
#
accept(c: ref Connection): ref Sys->FD
{
	if(sys == nil)
		sys = load Sys Sys->PATH;
	sys->fprint(c.cfd, "accept %s", lastname(c.dir));	# ignore return value, network might not need accepts
	return sys->open(c.dir+"/data", Sys->ORDWR);
}

#
# reject a call, tell device the reason for the rejection
#
reject(c: ref Connection, why: string): int
{
	if(sys == nil)
		sys = load Sys Sys->PATH;
	if(sys->fprint(c.cfd, "reject %s %q", lastname(c.dir), why) < 0)
		return -1;
	return 0;
}

lastname(dir: string): string
{
	p := backc(dir, len dir-1, '/');
	if(p < 0)
		return dir;
	return dir[p+1:];	# N in /net/N
}

parent(dir: string): string
{
	p := backc(dir, len dir-1, '/');
	if(p < 0)
		return nil;
	return dir[0: p];
}

netmkaddr(addr, net, svc: string): string
{
	if(sys == nil)
		sys = load Sys Sys->PATH;
	if(net == nil)
		net = "net";
	(n, nil) := sys->tokenize(addr, "!");
	if(n <= 1){
		if(svc== nil)
			return sys->sprint("%s!%s", net, addr);
		return sys->sprint("%s!%s!%s", net, addr, svc);
	}
	if(svc == nil || n > 2)
		return addr;
	return sys->sprint("%s!%s", addr, svc);
}

netinfo(c: ref Connection): ref Conninfo
{
	if(sys == nil)
		sys = load Sys Sys->PATH;
	if((dir := c.dir) == nil){
		if(c.dfd == nil)
			return nil;
		dir = parent(sys->fd2path(c.dfd));
		if(dir == nil)
			return nil;
	}
	ci := ref Conninfo;
	ci.dir = dir;
	ci.root = parent(dir);
	while((p := parent(ci.root)) != nil && p != "/")
		ci.root = p;
	(ok, d) := sys->stat(ci.dir);
	if(ok >= 0)
		ci.spec = sys->sprint("#%c%d", d.dtype, d.dev);
	(ci.lsys, ci.lserv) = getendpoint(ci.dir, "local");
	(ci.rsys, ci.rserv) = getendpoint(ci.dir, "remote");
	p = parent(ci.dir);
	if(p == nil)
		return nil;
	if(len p >= 5 && p[0:5] == "/net/")
		p = p[5:];
	ci.laddr = sys->sprint("%s!%s!%s", p, ci.lsys, ci.lserv);
	ci.raddr = sys->sprint("%s!%s!%s", p, ci.rsys, ci.rserv);
	return ci;
}

getendpoint(dir: string, file: string): (string, string)
{
	fd := sys->open(dir+"/"+file, Sys->OREAD);
	buf := array[128] of byte;
	if(fd == nil || (n := sys->read(fd, buf, len buf)) <= 0)
		return ("???", "???");	# compatible, but probably poor defaults
	if(n > 0 && buf[n-1] == byte '\n')
		n--;
	s := string buf[0: n];
	p := lookc(s, '!');
	if(p < 0)
		return (s, "???");
	return (s[0:p], s[p+1:]);
}
