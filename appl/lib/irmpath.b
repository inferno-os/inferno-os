# Driver for Mind Path IR50.

implement Ir;

include "sys.m";
FD, Dir: import Sys;
include "ir.m";

sys: Sys;

init(keys, pid: chan of int): int
{
	sys = load Sys Sys->PATH;

	cfd := sys->open("#t/eia1ctl", sys->OWRITE);
	if(cfd == nil)
		return -1;
	sys->fprint(cfd, "b1200");	# baud rate
	sys->fprint(cfd, "d1");		# DTR on
	sys->fprint(cfd, "r1");		# RTS on

	dfd := sys->open("#t/eia1", sys->OREAD);
	if(dfd == nil)
		return -1;
	cfd = nil;

	spawn reader(keys, pid, dfd);
	return 0;
}

reader(keys, pid: chan of int, dfd: ref FD)
{
	n: int;
	dir: Dir;
	button: int;

	pid <-= sys->pctl(0,nil);
	(n, dir) = sys->fstat(dfd);
	if(n >= 0 && dir.length > 0) {
		while(dir.length) {
			n = sys->read(dfd, array[dir.length] of byte, dir.length);
			if(n < 0)
				break;
			dir.length -= n;
		}
	}	

	for(;;) {
		# Look for 2 consecutive characters that are the same.
		if((button=getconsec(dfd,2)) < 0)
			break;
		case button {
			'-' => n = Ir->Enter;
			'+' => n = Ir->Rcl;
			'1' => n = Ir->One;
			'2' => n = Ir->Two;
			'3' => n = Ir->Three;
			'4' => n = Ir->ChanUP;	# page up
			'5' => n = Ir->ChanDN;	# page down
			'U' => continue;
			'R' =>
				if((button=getconsec(dfd,2)) < 0)
					break;
				case button {
					'a' or 'e' or 'i' or 'p' =>
						n = Ir->Up;
					'b' or 'f' or 'j' or 'k' =>
						n = Ir->FF;	# right
					'c' or 'g' or 'l' or 'm' =>
						n = Ir->Dn;
					'd' or 'h' or 'n' or 'o' =>
						n = Ir->Rew;	# left
					'Z' => n = Ir->Select;
					* =>	;
				}
			* =>	;
		}
		keys <-= n;	# Send translated key over channel
		# Read through to trailer before looking for another key press
		while((button=getconsec(dfd,2)) != 'U') {
			if(button <= 0)
				break;
		}
	}
	keys <-= Ir->Error;
}

translate(c: int): int
{
	return c;
}

# Gets 'count' consecutive occurrences of a byte.
getconsec(dfd: ref FD, count: int): int
{
	b1:= array[1] of byte;
	b2:= array[1] of byte;

	n := sys->read(dfd, b1, 1);
	if(n <= 0) {
		if(n==0)
			n = -1;
		return n;
	}
	for(sofar:=1; sofar < count; sofar++) {
		n = sys->read(dfd, b2, 1);
		if(n <= 0) {
			if(n==0)
				n = -1;
			return n;
		}
		if(b1[0]!=b2[0]) {
			sofar = 1;
			b1[0] = b2[0];
		}
	}
	return int b1[0];
}
