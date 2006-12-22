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
	sys->fprint(cfd, "b9600");

	dfd := sys->open("#t/eia1", sys->OREAD);
	cfd = nil;

	spawn reader(keys, pid, dfd);
	return 0;
}

reader(keys, pid: chan of int, dfd: ref FD)
{
	n, ta, tb: int;
	dir: Dir;
	b1:= array[1] of byte;
	b2:= array[1] of byte;

	pid <-= sys->pctl(0,nil);
	(n, dir) = sys->fstat(dfd);
	if(n >= 0 && dir.length > big 0) {
		while(dir.length > big 0) {
			l := int dir.length;
			n = sys->read(dfd, array[l] of byte, l);
			if(n < 0)
				break;
			dir.length -= big n;
		}
	}	

out:	for(;;) {
		n = sys->read(dfd, b1, len b1);
		if(n <= 0)
			break;
		ta = sys->millisec();
		for(;;) {
			n = sys->read(dfd, b2, 1);
			if(n <= 0)
				break out;
			tb = sys->millisec();
			if(tb - ta <= 200)
				break;
			ta = tb;
			b1[0] = b2[0];
		}
		case ((int b1[0]&16r1f)<<5) | (int b2[0]&16r1f) {
		 71 =>	n = Ir->ChanDN;
		 95 =>	n = Ir->Seven;
		135 =>	n = Ir->VolDN;
		207 =>	n = Ir->Three;
		215 =>	n = Ir->Select;
		263 =>	n = Ir->Dn;
		335 =>	n = Ir->Five;
		343 =>	n = Ir->Rew;
		399 =>	n = Ir->Nine;
		407 =>	n = Ir->Enter;
		455 =>	n = Ir->Power;
		479 =>	n = Ir->One;
		591 =>	n = Ir->Six;
		599 =>	n = Ir->ChanUP;
		663 =>	n = Ir->VolUP;
		711 =>	n = Ir->Up;
		735 =>	n = Ir->Two;
		791 =>	n = Ir->Mute;
		839 =>	n = Ir->FF;
		863 =>	n = Ir->Four;
		903 =>	n = Ir->Record;
		927 =>	n = Ir->Eight;
		975 =>	n = Ir->Zero;
		983 =>	n = Ir->Rcl;
		* =>	n = Ir->Error;
		}

		keys <-= n;
	}
	keys <-= Ir->Error;
}

translate(c: int): int
{
	return c;
}
