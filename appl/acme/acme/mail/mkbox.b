implement Mkbox;

include "sys.m";
include "draw.m";

sys : Sys;

FD : import sys;

Mkbox : module {
	init : fn(ctxt : ref Draw->Context, argl : list of string);
};

init(nil : ref Draw->Context, argl : list of string)
{
	sys = load Sys Sys->PATH;
	for (argl = tl argl; argl != nil; argl = tl argl) {
		nm := hd argl;
		(ok, dir) := sys->stat(nm);
		if (ok < 0) {
			fd := sys->create(nm, Sys->OREAD, 8r600);
			fd = nil;
		}
	}
}
