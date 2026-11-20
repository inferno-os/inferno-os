implement Factest;

#
# factest [-1]: factotum's infauth protocol, client against server over a
# pipe, both ends through /mnt/factotum (which must hold a key with
# role=client and one with role=server; see ai2key(8)). Prints what each
# end learned and whether their keys agree. -1 asks for version 1.
#

include "sys.m";
	sys: Sys;
include "draw.m";
include "factotum.m";
	factotum: Factotum;
	Authinfo: import Factotum;
include "bufio.m";
include "sexprs.m";
	sexprs: Sexprs;
	Sexp: import sexprs;

Factest: module
{
	init: fn(nil: ref Draw->Context, args: list of string);
};

init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	factotum = load Factotum Factotum->PATH;
	sexprs = load Sexprs Sexprs->PATH;
	if(factotum == nil || sexprs == nil){
		sys->print("factest: can't load modules: %r\n");
		raise "fail:load";
	}
	factotum->init();
	sexprs->init();
	extra := "";
	if(args != nil && tl args != nil && hd tl args == "-1")
		extra = " version=1";
	fds := array[2] of ref Sys->FD;
	if(sys->pipe(fds) < 0){
		sys->print("factest: pipe: %r\n");
		raise "fail:pipe";
	}
	done := chan of ref Authinfo;
	spawn end(fds[0], "proto=infauth role=server"+extra, done);
	spawn end(fds[1], "proto=infauth role=client"+extra, done);
	a := <-done;
	b := <-done;
	fds = nil;
	if(a == nil || b == nil){
		sys->print("factest: failed\n");
		raise "fail:auth";
	}
	if(extra != nil){
		if(field(a, "secret") != nil && field(a, "secret") == field(b, "secret")){
			sys->print("factest: version 1 ok: the two ends share a secret\n");
			return;
		}
	}else if(field(a, "secretin") != nil && field(a, "secretin") == field(b, "secretout") &&
	   field(a, "secretout") == field(b, "secretin") && field(a, "secretin") != field(a, "secretout") &&
	   field(a, "alg") == "chacha20poly1305" && field(b, "alg") == "chacha20poly1305"){
		sys->print("factest: version 2 ok: the two ends agree on a key for each direction, alg %s\n", field(a, "alg"));
		return;
	}
	sys->print("factest: the two ends disagree\n");
	raise "fail:keys";
}

end(fd: ref Sys->FD, params: string, done: chan of ref Authinfo)
{
	ai := factotum->proxy(fd, factotum->open(), params);
	if(ai == nil)
		sys->print("factest: %s: %r\n", params);
	done <-= ai;
}

# the value of a field of the s-expression in the secret, as text
field(ai: ref Authinfo, name: string): string
{
	(se, nil, nil) := Sexp.unpack(ai.secret);	# (sexp, rest, error)
	if(se == nil)
		return nil;
	for(l := se.els(); l != nil; l = tl l){
		e := (hd l).els();
		if(e != nil && tl e != nil && (hd e).astext() == name){
			v := hd tl e;
			if(name == "alg")
				return v.astext();
			return v.b64text();
		}
	}
	return nil;
}
