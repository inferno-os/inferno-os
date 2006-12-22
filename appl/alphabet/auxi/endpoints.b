implement Endpoints;
include "sys.m";
	sys: Sys;
include "draw.m";
include "string.m";
	str: String;
include "sh.m";
	sh: Sh;
include "alphabet/endpoints.m";

init()
{
	sys = load Sys Sys->PATH;
	sh = load Sh Sh->PATH;
	sh->initialise();
	str = load String String->PATH;
}

DIR: con "/n/endpoint";

new(nil, addr: string, force: int): string		# XXX don't ignore net directory
{
	if(!force && sys->stat(DIR+"/"+addr+"/clone").t0 != -1)
		return nil;
	if((e := sh->run(nil, "mount"::"{mntgen}"::DIR::nil)) != nil)
		return "mount mntgen failed: "+e;
	if((e = sh->run(nil, "endpointsrv"::addr::DIR+"/"+addr::nil)) != nil)
		return "endpoint failed: "+e;
	if((e = sh->run(nil, "listen"::addr::"export"::DIR+"/"+addr::nil)) != nil){
		sys->unmount(nil, DIR+"/"+addr);
		return "listen failed: "+e;
	}
	return nil;
}

err(e: string): Endpoint
{
	return (nil, nil, e);
}

create(addr: string): (ref Sys->FD, Endpoint)
{
	d := DIR+"/"+addr;
	fd := sys->open(d+"/clone", Sys->OREAD);
	if(fd == nil)
		return (nil, err(sys->sprint("cannot open %s/clone: %r", d)));

	buf := array[1024] of byte;
	n := sys->read(fd, buf, len buf);
	if(n <= 0)
		return (nil, err("read id failed"));
	s := string buf[0:n];
	(nt, toks) := sys->tokenize(s, " ");
	if(nt != 2)
		return (nil, err(sys->sprint("invalid id read %q", s)));
	id: string;
	(addr, id) = (hd toks, hd tl toks);
	fd = sys->open(d+"/"+id+".in", Sys->OWRITE);
	if(fd == nil)
		return (nil, err(sys->sprint("cannot write to %s/%s: %r", d, id)));
	return (fd, Endpoint(addr, id, nil));
}

open(net: string, ep: Endpoint): (ref Sys->FD, string)
{
	if(hasslash(ep.addr))
		return (nil, "bad address");
	if(hasslash(ep.id))
		return (nil, "bad id");
	d := DIR+"/"+ep.addr;
	fd := sys->open(d+"/"+ep.id, Sys->OREAD);
	if(fd != nil)
		return (fd, nil);
	e := sys->sprint("%r");
	if(sys->stat(d+"/clone").t0 != -1)
		return (nil, sys->sprint("endpoint does not exist: %s", e));
	if((e = sh->run(nil, "mount"::"-A"::net+ep.addr::d::nil)) != nil)
		return (nil, e);
	fd = sys->open(d+"/"+ep.id, Sys->OREAD);
	if(fd == nil)
		return (nil, sys->sprint("endpoint does not exist: %r"));
	return (fd, nil);
}

Endpoint.text(ep: self Endpoint): string
{
	return sys->sprint("%q %q %q", ep.addr, ep.id, ep.about);
}

Endpoint.mk(s: string): Endpoint
{
	t := str->unquoted(s);
	if(len t != 3)
		return err("invalid endpoint string");
	# XXX could do more validation than this.
	return (hd t, hd tl t, hd tl tl t);
}

hasslash(s: string): int
{
	for(i := 0; i < len s; i++)
		if(s[i] == '/')
			return 1;
	return 0;
}
