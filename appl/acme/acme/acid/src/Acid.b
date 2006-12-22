implement Acid;

include "sys.m";
include "draw.m";
include "sh.m";

Acid : module {
	init : fn(ctxt : ref Draw->Context, argl : list of string);
};

init(ctxt : ref Draw->Context, argl : list of string)
{
	sys := load Sys Sys->PATH;
	stderr := sys->fildes(2);
	if (len argl < 2) {
		sys->fprint(stderr, "usage : Acid pid\n");
		return;
	}
	cmd := "/acme/dis/win";
	file := cmd + ".dis";
	c := load Command file;
	if(c == nil) {
		sys->fprint(stderr, "%s: %r\n", cmd);
		return;
	}
	argl = "-l" :: argl;
	argl = "acid" :: argl;
	argl = "/acme/dis/Acid0" :: argl;
	argl = cmd :: argl;
	c->init(ctxt, argl);
}