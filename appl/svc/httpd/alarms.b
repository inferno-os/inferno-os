implement Alarms;
include "sys.m";
	sys: Sys;

include "alarms.m";

Alarm.stop(a: self Alarm) 
{
	a.alchan <-= -1;
	fd:=sys->open("#p/"+string a.pid+"/ctl",sys->OWRITE);
	sys->fprint(fd, "killgrp");
}

Alarm.alarm(time: int): Alarm
{
	if (sys == nil)
		sys = load Sys Sys->PATH;

	pid := sys->pctl(sys->NEWPGRP|sys->FORKNS,nil);
	a:=Alarm(chan of int,pid);
	spawn listener(a.alchan);
	spawn sleeper(a.alchan,time,pid);
	return a;
}
	
sleeper(ch: chan of int, time, pid: int)
{
	sys->sleep(time);
	alt{
		ch <-= pid =>
			;
		* =>
			exit;
	}
}

listener(ch: chan of int)
{
	a := <-ch;
	if (a==-1)
		exit;
	fd := sys->open("#p/"+string a+"/ctl",sys->OWRITE);
	if (fd != nil)
		sys->fprint(fd, "killgrp");
}
