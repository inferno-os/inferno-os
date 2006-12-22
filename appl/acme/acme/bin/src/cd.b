implement Cd;

include "sys.m";
include "draw.m";
include "workdir.m";

Cd : module {
	init : fn(ctxt : ref Draw->Context, argl : list of string);
};

sys : Sys;
workdir : Workdir;

FD, OREAD, OWRITE, open, read, write, chdir, fildes, fprint : import sys;

init(nil : ref Draw->Context, argl : list of string)
{
	n : int;
	fd, stderr : ref FD;
	buf, dir, str : string;
	ab : array of byte;

	sys = load Sys Sys->PATH;
	stderr = fildes(2);
	argl = tl argl;
	if (argl == nil)
		argl = "/usr/" + user() :: nil;
	if (tl argl != nil) {
		fprint(stderr, "Usage: cd [directory]\n");
		exit;
	}
	if (chdir(hd argl) < 0) {
		fprint(stderr, "cd: %s: %r\n", hd argl);
		exit;
	}

	workdir = load Workdir Workdir->PATH;
	fd = open("/dev/acme/ctl", OWRITE);
	if(fd == nil)
		exit;
	dir = workdir->init();
	buf = "name " + dir;
	n = len buf;
	if(n>0 && buf[n-1] !='/')
		buf[n++] = '/';
	buf[n++] = '-';
	if(tl argl != nil)
		str = hd tl argl;
	else
		str = "sh";
	buf += str + "\n";
	ab = array of byte buf;
	write(fd, ab, len ab);
	buf = "dumpdir " + dir + "\n";
	ab = array of byte buf;
	write(fd, ab, len ab);
	exit;
}

user(): string
{
	fd := open("/dev/user", OREAD);
	if(fd == nil)
		return "inferno";
	buf := array[Sys->NAMEMAX] of byte;
	n := read(fd, buf, len buf);
	if(n <= 0)
		return "inferno";
	return string buf[0:n];
}
