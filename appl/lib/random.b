implement Random;

include "sys.m";
include "draw.m";
include "keyring.m";
include "security.m";

sys: Sys;

randfd(which: int): ref sys->FD
{
	file: string;

	sys = load Sys Sys->PATH;
	case(which){
	ReallyRandom =>
		file = "/dev/random";
	NotQuiteRandom =>
		file = "/dev/notquiterandom";
	}
	fd := sys->open(file, sys->OREAD);
	if(fd == nil){
		sys->print("can't open /dev/random\n");
		return nil;
	}
	return fd;
}

randomint(which: int): int
{
	fd := randfd(which);
	if(fd == nil)
		return 0;
	buf := array[4] of byte;
	sys->read(fd, buf, 4);
	rand := 0;
	for(i := 0; i < 4; i++)
		rand = (rand<<8) | int buf[i];
	return rand;
}

randombuf(which, n: int): array of byte
{
	buf := array[n] of byte;
	fd := randfd(which);
	if(fd == nil)
		return buf;
	sys->read(fd, buf, n);
	return buf;
}
