implement Dd;

include "sys.m";
include "draw.m";
include "sh.m";

Dd : module {
	init : fn(ctxt : ref Draw->Context, argl : list of string);
};

init(ctxt : ref Draw->Context, argl : list of string)
{
	sys := load Sys Sys->PATH;
	stderr := sys->fildes(2);
	if (len argl != 1) {
		sys->fprint(stderr, "usage : d\n");
		return;
	}
	cmd := "/acme/edit/c";
	file := cmd + ".dis";
	c := load Command file;
	if(c == nil) {
		sys->fprint(stderr, "%s: %r\n", cmd);
		return;
	}
	argl = nil;
	argl = "" :: argl;
	argl = cmd :: argl;
	c->init(ctxt, argl);
}