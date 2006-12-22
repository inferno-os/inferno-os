implement Exception;

include "sys.m";
	sys: Sys;
include "exception.m";

getexc(pid: int): (int, string, string)
{
	loadsys();
	if(pid < 0)
		pid = sys->pctl(0, nil);
	f := "/prog/"+string pid+"/exception";
	if((fd := sys->open(f, Sys->OREAD)) == nil)
		return (0, nil, nil);
	b := array[8192] of byte;
	if((n := sys->read(fd, b, len b)) < 0)
		return (0, nil, nil);
	s := string b[0: n];
	if(s == nil)
		return (0, nil, nil);
	(m, l) := sys->tokenize(s, " ");
	if(m < 3)
		return (0, nil, nil);
	pc := int hd l;	l = tl l;
	mod := hd l;	l = tl l;
	exc := hd l;	l = tl l;
	for( ; l != nil; l = tl l)
		exc += " " + hd l;
	return (pc, mod, exc);
}

setexcmode(mode: int): int
{
	loadsys();
	pid := sys->pctl(0, nil);
	f := "/prog/" + string pid + "/ctl";
	if(mode == NOTIFYLEADER)
		return write(f, "exceptions notifyleader");
	else if(mode == PROPAGATE)
		return write(f, "exceptions propagate");
	else
		return -1;
}

loadsys()
{
	if(sys == nil)
		sys = load Sys Sys->PATH;
}

write(f: string, s: string): int
{
	if((fd := sys->open(f, Sys->OWRITE)) == nil)
		return -1;
	b := array of byte s;
	if((n := sys->write(fd, b, len b)) != len b)
		return -1;
	return 0;
}
