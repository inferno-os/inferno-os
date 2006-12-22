implement Timerm;

include "common.m";

sys : Sys;
acme : Acme;
utils : Utils;
dat : Dat;

millisec : import sys;
Timer : import dat;

init(mods : ref Dat->Mods)
{
	sys = mods.sys;
	acme = mods.acme;
	utils = mods.utils;
	dat = mods.dat;
}

ctimer : chan of ref Timer;

timeproc()
{
	i, nt, na, dt : int;
	x : ref Timer;
	t : array of ref Timer;
	old, new : int;

	acme->timerpid = sys->pctl(0, nil);
	sys->pctl(Sys->FORKFD, nil);
	t = array[10] of ref Timer;
	na = 10;
	nt = 0;
	old = millisec();
	for(;;){
		if (nt == 0) {	# don't waste cpu time
			x = <-ctimer;
			t[nt++] = x;
			old = millisec();
		}
		sys->sleep(1);	# will sleep minimum incr 
		new = millisec();
		dt = new-old;
		old = new;
		if(dt < 0)	# timer wrapped; go around, losing a tick 
			continue;
		for(i=0; i<nt; i++){
			x = t[i];
			x.dt -= dt;
			if(x.dt <= 0){
				#
				# avoid possible deadlock if client is
				# now sending on ctimer
				#
				 
				alt {
					x.c <-= 0 =>
						t[i:] = t[i+1:nt];
						t[nt-1] = nil;
						nt--;
						i--;
					* =>
						;
				}
			}
		}
		gotone := 1;
		while (gotone) {
			alt {
				x = <-ctimer =>
					if (nt == na) {
						ot := t;
						t = array[na+10] of ref Timer;
						t[0:] = ot[0:na];
						ot = nil;
						na += 10;
					}
					t[nt++] = x;
					old = millisec();
				* =>
					gotone = 0;
			}
		}
	}
}

timerinit()
{
	ctimer = chan of ref Timer;
	spawn timeproc();
}

#
# timeralloc() and timerfree() don't lock, so can only be
# called from the main proc.
#
 

timer : ref Timer;

timerstart(dt : int) : ref Timer
{
	t : ref Timer;

	t = timer;
	if(t != nil)
		timer = timer.next;
	else{
		t = ref Timer;
		t.c = chan of int;
	}
	t.next = nil;
	t.dt = dt;
	ctimer <-= t;
	return t;
}

timerstop(t : ref Timer)
{
	t.next = timer;
	timer = t;
}

timerwaittask(timer : ref Timer)
{
	<-(timer.c);
	timerstop(timer);
}
