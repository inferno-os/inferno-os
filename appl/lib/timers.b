implement Timers;

include "sys.m";
	sys:	Sys;

include "timers.m";

timerin: chan of ref Timer;

init(minms: int): int
{
	sys = load Sys Sys->PATH;
	timerin = chan[20] of ref Timer;
	if(minms <= 0)
		minms = 1;
	pid := chan of int;
	spawn timeproc(timerin, minms, pid);
	return <-pid;
}

shutdown()
{
	if(timerin != nil)
		timerin <-= nil;
}	

Timer.start(dt: int): ref Timer
{
	t := ref Timer(dt, chan[1] of int);
	timerin <-= t;
	return t;
}

Timer.stop(t: self ref Timer)
{
	# this is safe, because only Timer.stop sets t.timeout and timeproc only fetches it
	t.timeout = nil;
}
			
timeproc(req: chan of ref Timer, msec: int, pid: chan of int)
{
	pending: list of ref Timer;

	pid <-= sys->pctl(Sys->NEWFD|Sys->NEWNS|Sys->NEWENV, nil);	# same pgrp
	old := sys->millisec();
Work:
	for(;;){
		if(pending == nil){
			if((t := <-req) == nil)
				break Work;
			pending = t :: pending;
			old = sys->millisec();
		}else{
			# check quickly for new requests
		Check:
			for(;;) alt{
			t := <-req =>
				if(t == nil)
					break Work;
				pending = t :: pending;
			* =>
				break Check;
			}
		}
		sys->sleep(msec);
		new := sys->millisec();
		dt := new-old;
		old = new;
		if(dt < 0)
			continue;	# millisec counter wrapped
		ticked := 0;
		for(l := pending; l != nil; l = tl l)
			if(((hd l).dt -= dt) <= 0)
				ticked = 1;
		if(ticked){
			l = pending;
			pending = nil;
			for(; l != nil; l = tl l){
				t := hd l;
				if(t.dt > 0 || !notify(t))
					pending = t :: pending;
			}
		}
	}
	# shut down: attempt to clear pending requests
	for(; pending != nil; pending = tl pending)
		notify(hd pending);
}

notify(t: ref Timer): int
{
	# copy to c to avoid race with Timer.stop
	if((c := t.timeout) == nil)
		return 1;	# cancelled; consider it done
	alt{
	c <-= 1 => return 1;
	* => return 0;
	}
}
