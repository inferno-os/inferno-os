implement Srvmgr;

include "sys.m";
	sys: Sys;

include "srvmgr.m";
include "service.m";
include "cfg.m";

Srvinfo: adt {
	name: string;
	path: string;
	args: list of string;
};

services: list of ref Srvinfo;

init(srvdir: string): (string, chan of ref Srvreq)
{
	sys = load Sys Sys->PATH;
	cfg := load Cfg Cfg->PATH;
	cfgpath := srvdir + "/services.cfg";
	if (cfg == nil)
		return (sys->sprint("cannot load %s: %r", Cfg->PATH), nil);
	err := cfg->init(cfgpath);
	if (err != nil)
		return (err, nil);

	(err, services) = parsecfg(cfgpath, srvdir, cfg);
	if (err != nil)
		return (err, nil);

	rc := chan of ref Srvreq;
	spawn srv(rc);
	return (nil, rc);
}

parsecfg(p, srvdir: string, cfg: Cfg): (string, list of ref Srvinfo)
{
	srvlist: list of ref Srvinfo;
	Record, Tuple: import cfg;

	for (slist := cfg->getkeys(); slist != nil; slist = tl slist) {
		name := hd slist;
		matches := cfg->lookup(name);
		if (len matches > 1) {
			(nil, duplicate) := hd tl matches;
			primary := hd duplicate.tuples;
			lnum := primary.lnum;
			err := sys->sprint("%s:%d: duplicate service name %s", p, lnum, name);
			return (err, nil);
		}
		(nil, r) := hd matches;
		lnum := (hd r.tuples).lnum;

		(path, tuple) := r.lookup("path");
		if (path == nil) {
			err := sys->sprint("%s:%d: missing path for service %s", p, lnum, name);
			return (err, nil);
		}
		if (path[0] != '/')
			path = srvdir + "/" + path;

		args: list of string = nil;
		for (tuples := tl r.tuples; tuples != nil; tuples = tl tuples) {
			t := hd tuples;
			arg := t.lookup("arg");
			if (arg != nil)
				args = arg :: args;
		}
		nargs: list of string = nil;
		for (; args != nil; args = tl args)
			nargs = hd args :: nargs;
		srvlist = ref Srvinfo(name, path, args) ::srvlist;
	}
	if (srvlist == nil) {
		err := sys->sprint("%s: no services", p);
		return (err, nil);
	}
	return (nil, srvlist);
}
	
srv(rc: chan of ref Srvreq)
{
	for (;;) {
		req := <- rc;
		id := req.sname + " " + req.id;
		pick r := req {
		Acquire =>
			# r.user not used, but could control access
			service := acquire(id);
			err := "";
			if (service.fd == nil) {
				(err, service.root, service.fd) = startservice(req.sname);
				if (err != nil)
					release(id);
			}
			r.reply <-= (err, service.root, service.fd);
		Release =>
			release(id);
		}
	}
}

#
# returns (error, service root, service FD)
#
startservice(name: string): (string, string, ref Sys->FD)
{
sys->print("startservice [%s]\n", name);
	srv: ref Srvinfo;
	for (sl := services; sl != nil; sl = tl sl) {
		s := hd sl;
		if (s.name == name) {
			srv = s;
			break;
		}
	}
	if (srv == nil)
		return ("unknown service", nil, nil);

	service := load Service srv.path;
	if (service == nil) {
		err := sys->sprint("cannot load %s: %r", srv.path);
		return (err, nil, nil);
	}

	return service->init(srv.args);
}

Srvmap: adt {
	id: string;
	root: string;
	fd: ref Sys->FD;
	nref: int;
	next: cyclic ref Srvmap;
};

PRIME: con 211;
buckets := array[PRIME] of ref Srvmap;

hash(id: string): int
{
	# HashPJW
	h := 0;
	for (i := 0; i < len id; i++) {
		h = (h << 4) + id[i];
		g := h & int 16rf0000000;
		if (g != 0) {
			h = h ^ ((g >> 24) & 16rff);
			h = h ^ g;
		}
	}
	if (h < 0)
		h &= ~(1<<31);
	return int (h % PRIME);
}

acquire(id: string): ref Srvmap
{
	h := hash(id);
	for (p := buckets[h]; p != nil; p = p.next)
		if (p.id == id) {
			p.nref++;
			return p;
		}
	p = ref Srvmap(id, nil, nil, 1, buckets[h]);
	buckets[h] = p;
	return p;
}

release(id: string)
{
	h :=hash(id);
	prev: ref Srvmap;
	for (p := buckets[h]; p != nil; p = p.next) {
		if (p.id == id){
			p.nref--;
			if (p.nref == 0) {
				sys->print("release [%s]\n", p.id);
				if (prev == nil)
					buckets[h] = p.next;
				else
					prev.next = p.next;
			}
			return;
		}
		prev = p;
	}
}
