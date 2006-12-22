implement Cat;

include "sys.m";
include "draw.m";

Cat: module
{
	init:	fn(ctxt: ref Draw->Context, argv: list of string);
};

sys: Sys;
stdout: ref Sys->FD;

init(nil: ref Draw->Context, argl: list of string)
{
	sys = load Sys Sys->PATH;

	stdout = sys->fildes(1);

	argl = tl argl;
	if(argl == nil)
		argl = "-" :: nil;
	while(argl != nil) {
		cat(hd argl);
		argl = tl argl;
	}
}

cat(file: string)
{
	n: int;
	fd: ref Sys->FD;
	buf := array[8192] of byte;

	if(file == "-")
		fd = sys->fildes(0);
	else {
		fd = sys->open(file, sys->OREAD);
		if(fd == nil) {
			sys->fprint(sys->fildes(2), "cat: cannot open %s: %r\n", file);
			raise "fail:bad open";
		}
	}
	for(;;) {
		n = sys->read(fd, buf, len buf);
		if(n <= 0)
			break;
		if(sys->write(stdout, buf, n) < n) {
			sys->fprint(sys->fildes(2), "cat: write error: %r\n");
			raise "fail:write error";
		}
	}
	if(n < 0) {
		sys->fprint(sys->fildes(2), "cat: read error: %r\n");
		raise "fail:read error";
	}
}
