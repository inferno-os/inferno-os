#
# stream data from files
#
# Copyright © 2000 Vita Nuova Limited.  All rights reserved.
#

implement Stream;

include "sys.m";
	sys: Sys;
include "draw.m";

Stream: module
{
	init:	fn(nil: ref Draw->Context, argv: list of string);
};

stderr: ref Sys->FD;

usage()
{
	sys->fprint(stderr, "Usage: stream [-a] [-b bufsize] file1 [file2]\n");
	fail("usage");
}

init(nil: ref Draw->Context, argv: list of string)
{
	sys = load Sys Sys->PATH;
	stderr = sys->fildes(2);

	bsize := 0;
	sync := chan of int;
	if(argv != nil)
		argv = tl argv;
	for(; argv != nil && len hd argv && (s := hd argv)[0] == '-' && len s > 1; argv = tl argv)
		case s[1] {
		'b' =>
			if(len s > 2)
				bsize = int s[2:];
			else if((argv = tl argv) != nil)
				bsize = int hd argv;
			else
				usage();
		'a' =>
			sync = nil;
		* =>
			usage();
		}
	if(bsize <= 0 || bsize > 2*1024*1024)
		bsize = Sys->ATOMICIO;
	argc := len argv;
	if(argc < 1)
		usage();

	if(argc > 1){
		f1 := eopen(hd argv, Sys->ORDWR);
		f2 := eopen(hd tl argv, Sys->ORDWR);
		spawn stream(f1, f2, bsize, sync);
		spawn stream(f2, f1, bsize, sync);
	}else{
		f2 := sys->fildes(1);
		if(f2 == nil) {
			sys->fprint(stderr, "stream: can't access standard output: %r\n");
			fail("stdout");
		}
		f1 := eopen(hd argv, Sys->OREAD);
		spawn stream(f1, f2, bsize, sync);
	}
	if(sync != nil){	# count them back in
		<-sync;
		if(argc > 1)
			<-sync;
	}
}

stream(source: ref Sys->FD, sink: ref Sys->FD, bufsize: int, sync: chan of int)
{
	if(sys->stream(source, sink, bufsize) < 0)
		sys->fprint(stderr, "stream: error streaming data: %r\n");
	if(sync != nil)
		sync <-= 1;
}

eopen(name: string, mode: int): ref Sys->FD
{
	fd := sys->open(name, mode);
	if(fd == nil){
		sys->fprint(stderr, "stream: can't open %s: %r\n", name);
		fail("open");
	}
	return fd;
}

fail(s: string)
{
	raise s;
	exit;
}
