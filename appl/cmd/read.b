implement Read;
include "sys.m"; 
	sys: Sys;
include "draw.m";

Read: module {
	init: fn(nil: ref Draw->Context, argv: list of string);
};

usage()
{
	sys->fprint(sys->fildes(2), "usage: read [-[ero] offset] count\n");
	raise "fail:usage";
}

init(nil: ref Draw->Context, argv: list of string)
{
	sys = load Sys Sys->PATH;
	# usage: read [-[ero] offset] count
	count := Sys->ATOMICIO;
	offset := big 0;
	seeking := -1;
	if (argv != nil)
		argv = tl argv;
	if (argv != nil && hd argv != nil && (hd argv)[0] == '-') {
		if (tl argv == nil)
			usage();
		case hd argv {
		"-o" =>
			seeking = Sys->SEEKSTART;
		"-e" =>
			seeking = Sys->SEEKEND;
		"-r" =>
			seeking = Sys->SEEKRELA;
		* =>
			usage();
		}
		offset = big hd tl argv;
		argv = tl tl argv;
	}
	if (argv != nil) {
		if (tl argv != nil)
			usage();
		count = int hd argv;
	}
	fd := sys->fildes(0);
	if (seeking != -1)
		sys->seek(fd, offset, seeking);
	if (count == 0)
		return;
	buf := array[count] of byte;
	n := sys->read(fd, buf, len buf);
	if (n > 0)
		sys->write(sys->fildes(1), buf, n);
	else {
		if (n == -1) {
			sys->fprint(sys->fildes(2), "read: read error: %r\n");
			raise "fail:error";
		}
		raise "fail:eof";
	}
}
