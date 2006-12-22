implement Awd;

include "sys.m";
include "draw.m";
include "workdir.m";

Awd : module {
	init : fn(ctxt : ref Draw->Context, argl : list of string);
};

sys : Sys;
workdir : Workdir;

FD, OWRITE, open, write : import sys;

init(nil : ref Draw->Context, argl : list of string)
{
	n : int;
	fd : ref FD;
	buf, dir, str : string;
	ab : array of byte;

	sys = load Sys Sys->PATH;
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
		str = "rc";
	buf += str + "\n";
	ab = array of byte buf;
	write(fd, ab, len ab);
	buf = "dumpdir " + dir + "\n";
	ab = array of byte buf;
	write(fd, ab, len ab);
	exit;
}
