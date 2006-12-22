implement Shutdown;

include "sys.m";
sys: Sys;
FD: import Sys;
stderr: ref FD;

include "draw.m";
Context: import Draw;

sysctl:	con "/dev/sysctl";
reboot:	con "reboot";
halt:	con "halt";

Shutdown: module
{
	init:	fn(ctxt: ref Context, argv: list of string);
};

rflag: int;
hflag: int;

init(nil: ref Context, argv: list of string)
{
	sys = load Sys Sys->PATH;

	stderr = sys->fildes(2);

	argv = tl argv;
	if(len argv < 1)
		usage();

	while(argv != nil && len hd argv && (arg := hd argv)[0] == '-' && len arg > 1){
		case arg[1] {
		'r' =>
			rflag = 1;
		'h' =>
			hflag = 1;
		}
		argv = tl argv;
	}

	if(rflag == 0 && hflag == 0)
		usage();

	if(rflag == 1 && hflag == 1)
		usage();

	fd := sys->open(sysctl, sys->OWRITE);
	if(fd == nil) {
		sys->fprint(stderr, "shutdown: %r\n");
		exit;
	}

	if(rflag == 1) 
		if (sys->write(fd, array of byte reboot, len reboot) < 0) {
			sys->fprint(stderr, "shutdown: write failed: %r\n");
			exit;
		}

	if(hflag == 1) 
		if (sys->write(fd, array of byte halt, len halt) < 0) {
			sys->fprint(stderr, "shutdown: write failed: %r\n");
			exit;
		}
}

usage()
{
	sys->fprint(stderr, "usage: shutdown -r | -h\n");
	exit;
}
