implement Wait;

#
# Copyright © 2003 Vita Nuova Holdings Limited.  All rights reserved.
#

include "sys.m";
	sys: Sys;

include "wait.m";

init()
{
	sys = load Sys Sys->PATH;
}

read(fd: ref Sys->FD): (int, string, string)
{
	buf := array[2*Sys->WAITLEN] of byte;
	n := sys->read(fd, buf, len buf);
	if(n <= 0)
		return (n, nil, sys->sprint("%r"));
	return parse(string buf[0:n]);
}

monitor(fd: ref Sys->FD): (int, chan of (int, string, string))
{
	pid := chan of int;
	out := chan of (int, string, string);
	spawn waitreader(fd, pid, out);
	return (<-pid, out);
}

waitreader(fd: ref Sys->FD, pid: chan of int, out: chan of (int, string, string))
{
	pid <-= sys->pctl(0, nil);
	for(;;){
		(child, modname, status) := read(fd);
		out <-= (child, modname, status);
		if(child <= 0)
			break;	# exit on error
	}
}

parse(status: string): (int, string, string)
{
	for (i := 0; i < len status; i++)
		if (status[i] == ' ')
			break;
	j := i+2;	# skip space and "
	for (i = j; i < len status; i++)
		if (status[i] == '"')
			break;
	return (int status, status[j:i], status[i+2:]);
}
