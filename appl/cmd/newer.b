implement Newer;

#
# test if a file is up to date
#

include "sys.m";

include "draw.m";

Newer: module
{
	init:	fn(nil: ref Draw->Context, nil: list of string);
};

init(nil: ref Draw->Context, args: list of string)
{
	sys := load Sys Sys->PATH;
	if(len args != 3){
		sys->fprint(sys->fildes(2), "usage: newer newfile oldfile\n");
		raise "fail:usage";
	}
	args = tl args;
	(ok1, d1) := sys->stat(hd args);
	if(ok1 < 0)
		raise sys->sprint("fail:new:%r");
	if(d1.mode & Sys->DMDIR)
		raise "fail:new:directory";
	(ok2, d2) := sys->stat(hd tl args);
	if(ok2 < 0)
		raise sys->sprint("fail:old:%r");
	if(d2.mode & Sys->DMDIR)
		raise "fail:old:directory";
	if(d2.mtime > d1.mtime)
		raise "fail:older";
}
