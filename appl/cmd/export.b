#
# export current name space on a connection
#

implement Export;

include "sys.m";
	sys: Sys;
include "draw.m";

Export: module
{
	init: fn(nil: ref Draw->Context, argv: list of string);
};

usage()
{
	sys->fprint(stderr(), "Usage: export [-a] dir [connection]\n");
	raise "fail:usage";
}

init(nil: ref Draw->Context, argv: list of string)
{
	# usage: export dir [connection]
	sys = load Sys Sys->PATH;
	if(argv != nil)
		argv = tl argv;
	flag := Sys->EXPWAIT;
	for(; argv != nil && len hd argv && (hd argv)[0] == '-'; argv = tl argv)
		for(i := 1; i < len hd argv; i++)
			case (hd argv)[i] {
			'a' =>
				flag = Sys->EXPASYNC;
			* =>
				usage();
			}
	n := len argv;
	if (n < 1 || n > 2)
		usage();
	fd: ref Sys->FD;
	if (n == 2) {
		if ((fd = sys->open(hd tl argv, Sys->ORDWR)) == nil) {
			sys->fprint(stderr(), "export: can't open %s: %r\n", hd tl argv);
			raise "fail:open";
		}
	} else
		fd = sys->fildes(0);
	if (sys->export(fd, hd argv, flag) < 0) {
		sys->fprint(stderr(), "export: can't export: %r\n");
		raise "fail:export";
	}
}

stderr(): ref Sys->FD
{
	return sys->fildes(2);
}
