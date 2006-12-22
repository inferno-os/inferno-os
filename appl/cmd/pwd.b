implement Pwd;

include "sys.m";
include "draw.m";
include "workdir.m";

Pwd: module
{
	init:	fn(nil: ref Draw->Context, nil: list of string);
};

init(nil: ref Draw->Context, nil: list of string)
{
	sys := load Sys Sys->PATH;
	stderr := sys->fildes(2);
	gwd := load Workdir Workdir->PATH;
	if (gwd == nil) {
		sys->fprint(stderr, "pwd: cannot load %s: %r\n", Workdir->PATH);
		raise "fail:bad module";
	}

	wd := gwd->init();
	if(wd == nil) {
		sys->fprint(stderr, "pwd: %r\n");
		raise "fail:error";
	}
	sys->print("%s\n", wd);
}
