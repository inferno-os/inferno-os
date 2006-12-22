implement Nsbuild;

include "sys.m";
	sys: Sys;
include "draw.m";

include "newns.m";

stderr: ref Sys->FD;

Nsbuild: module
{
	init: fn(ctxt: ref Draw->Context, argv: list of string);
};

init(nil: ref Draw->Context, argv: list of string)
{
	sys = load Sys Sys->PATH;
	stderr = sys->fildes(2);

	ns := load Newns "/dis/lib/newns.dis";
	if(ns == nil) {
		sys->fprint(stderr, "nsbuild: can't load %s: %r", Newns->PATH);
		raise "fail:load";
	}

	if(len argv > 2) {
		sys->fprint(stderr, "Usage: nsbuild [nsfile]\n");
		raise "fail:usage";
	}

	nsfile := "namespace";
	if(len argv == 2)
		nsfile = hd tl argv;

   	e := ns->newns(nil, nsfile);
	if(e != ""){
		sys->fprint(stderr, "nsbuild: error building namespace: %s\n", e);
		raise "fail:newns";
	}
} 
