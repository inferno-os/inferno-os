implement Announce;
include "sys.m";
	sys:	Sys;
include "dial.m";
	dial: Dial;
include "grid/announce.m";

init()
{
	sys = load Sys Sys->PATH;
}

announce(): (string, ref Sys->Connection)
{
	sysname := readfile("/dev/sysname");
	c := dial->announce("tcp!*!0");
	if(c == nil)
		return (nil, nil);
	local := readfile(c.dir + "/local");
	if(local == nil)
		return (nil, nil);
	for(i := len local - 1; i >= 0; i--)
		if(local[i] == '!')
			break;
	port := local[i+1:];
	if(port == nil)
		return (nil, nil);
	if(port[len port - 1] == '\n')
		port = port[0:len port - 1];
	return ("tcp!" + sysname + "!" + port, c);
}


readfile(f: string): string
{
	fd := sys->open(f, Sys->OREAD);
	if (fd == nil)
		return nil;
	buf := array[8192] of byte;
	n := sys->read(fd, buf, len buf);
	if (n <= 0)
		return nil;
	return string buf[0:n];
}
