implement SSL;

include "sys.m";
	sys: Sys;

include "keyring.m";
include "security.m";

sslclone(): (ref Sys->Connection, string)
{
	if(sys == nil)
		sys = load Sys Sys->PATH;
	(rc, nil) := sys->stat("#D");	# only the local device will work, because local file descriptors are used
	if(rc < 0)
		return (nil, sys->sprint("cannot access SSL device #D: %r"));
	c := ref Sys->Connection;
	c.dir = "#D";
	if(rc >= 0){
		(rc, nil) = sys->stat("#D/ssl");	# another variant
		if(rc >= 0)
			c.dir = "#D/ssl";
	}
	clonef := c.dir+"/clone";
	c.cfd = sys->open(clonef, Sys->ORDWR);
	if(c.cfd == nil)
		return (nil, sys->sprint("cannot open %s: %r", clonef));
	s := readstring(c.cfd);
	if(s == nil)
		return (nil, sys->sprint("cannot read %s: %r", clonef));
	c.dir += "/" + s;
	return (c, nil);
}

connect(fd: ref Sys->FD): (string, ref Sys->Connection)
{
	(c, err) := sslclone();
	if(c == nil)
		return (err, nil);
	c.dfd = sys->open(c.dir + "/data", Sys->ORDWR);
	if(c.dfd == nil)
		return (sys->sprint("cannot open data: %r"), nil);
	if(sys->fprint(c.cfd, "fd %d", fd.fd) < 0)
		return (sys->sprint("cannot push fd: %r"), nil);
	return (nil, c);
}

secret(c: ref Sys->Connection, secretin, secretout: array of byte): string
{
	if(sys == nil)
		sys = load Sys Sys->PATH;

	if(secretin != nil){
		fd := sys->open(c.dir + "/secretin", Sys->ORDWR);
		if(fd == nil)
			return sys->sprint("cannot open %s: %r", c.dir + "/secretin");
		if(sys->write(fd, secretin, len secretin) < 0)
			return sys->sprint("cannot write %s: %r", c.dir + "/secretin");
	}

	if(secretout != nil){
		fd := sys->open(c.dir + "/secretout", Sys->ORDWR);
		if(fd == nil)
			return sys->sprint("cannot open %s: %r", c.dir + "/secretout");
		if(sys->write(fd, secretout, len secretout) < 0)
			return sys->sprint("cannot open %s: %r", c.dir + "/secretout");
	}
	return nil;
}

algs(): (list of string, list of string)
{
	(c, nil) := sslclone();
	if(c == nil)
		return (nil, nil);
	c.dfd = nil;
	(nil, encalgs) := sys->tokenize(readstring(sys->open(c.dir+"/encalgs", Sys->OREAD)), " \t\n");
	(nil, hashalgs) := sys->tokenize(readstring(sys->open(c.dir+"/hashalgs", Sys->OREAD)), " \t\n");
	return (encalgs, hashalgs);
}

readstring(fd: ref Sys->FD): string
{
	if(fd == nil)
		return nil;
	buf := array[256] of byte;
	n := sys->read(fd, buf, len buf);
	if(n < 0)
		return nil;
	return string buf[0:n];
}
