implement Powerman;

#
# Copyright © 2001 Vita Nuova Holdings Limited.  All rights reserved.
#

include "sys.m";
	sys: Sys;

include "powerman.m";

pid := 0;

init(file: string, events: chan of string): int
{
	if(file == nil)
		file = "/dev/powerdata";
	fd := sys->open(file, Sys->OREAD);
	if(fd == nil)
		return -1;
	pidc := chan of int;
	spawn reader(fd, events, pidc);
	return pid = <-pidc;
}

reader(fd: ref Sys->FD, events: chan of string, pidc: chan of int)
{
	pidc <-= sys->pctl(0, nil);
	buf := array[128] of byte;
	while((n := sys->read(fd, buf, len buf)) > 0){
		if(buf[n-1] == byte '\n')
			n--;
		events <-= string buf[0:n];
	}
	events <-= "error";
}

stop()
{
	if(pid != 0){
		fd := sys->open("#p/"+string pid+"/ctl", Sys->OWRITE);
		if(fd != nil)
			sys->fprint(fd, "kill");
		pid = 0;
	}
}

ack(op: string)
{
	ctl("ack "+op);
}

ctl(op: string): string
{
	fd := sys->open("/dev/powerctl", Sys->OWRITE);
	if(fd != nil && sys->fprint(fd, "%s", op) >= 0)
		return nil;
	return sys->sprint("%r");
}
