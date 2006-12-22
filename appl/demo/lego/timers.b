# Chris Locke. June 2000

# TODO: for auto-repeat timers don't set up a new sender
# if there is already a pending sender for that timer.

implement Timers;

include "sys.m";
include "timers.m";

RealTimer : adt {
	t : ref Timer;
	nticks : int;
	rep : int;
	nexttick: big;
	tick : chan of int;
	sender : int;
};

Sender : adt {
	tid : int;
	idle : int;		# set by sender() when done, reset by main when about to assign work
	ctl : chan of chan of int;
};

sys : Sys;
acquire : chan of int;
timers := array [4] of ref RealTimer;
senders := array [4] of ref Sender;
curtick := big 0;
tickres : int;

init(res : int)
{
	sys = load Sys Sys->PATH;
	acquire = chan of int;
	tickres = res;
	spawn main();
}

new(ms, rep : int) : ref Timer
{
	acquire <- = 1;
	t := do_new(ms, rep);
	<- acquire;
	return t;
}

Timer.destroy(t : self ref Timer)
{
	acquire <- = 1;
	do_destroy(t);
	<- acquire;
}

Timer.reset(t : self ref Timer)
{
	acquire <- = 1;
	do_reset(t);
	<- acquire;
}

Timer.cancel(t : self ref Timer)
{
	acquire <- = 1;
	do_cancel(t);
	<- acquire;
}

# only call under lock
#
realtimer(t : ref Timer) : ref RealTimer
{
	if (t.id < 0 || t.id >= len timers)
		return nil;
	if (timers[t.id] == nil)
		return nil;
	if (timers[t.id].t != t)
		return nil;
	return timers[t.id];
}


# called under lock
#
do_destroy(t : ref Timer)
{
	rt := realtimer(t);
	if (rt == nil)
		return;
	clearsender(rt, t.id);
	timers[t.id] = nil;
}

# called under lock
#
do_reset(t : ref Timer)
{
	rt := realtimer(t);
	if (rt == nil)
		return;
	clearsender(rt, t.id);
	rt.nexttick = curtick + big (rt.nticks);
	startclk = 1;
}

# called under lock
#
do_cancel(t : ref Timer)
{
	rt := realtimer(t);
	if (rt == nil)
		return;
	clearsender(rt, t.id);
	rt.nexttick = big 0;
}

# only call under lock
#
clearsender(rt : ref RealTimer, tid : int)
{
	# check to see if there is a sender trying to deliver tick
	if (rt.sender != -1) {
		sender := senders[rt.sender];
		rt.sender = -1;
		if (sender.tid == tid && !sender.idle) {
			# receive the tick to clear the busy state
			alt {
				<- rt.tick =>
					;
				* =>
					;
			}
		}
	}
}

# called under lock
do_new(ms, rep : int) : ref Timer
{
	# find free slot
	for (i := 0; i < len timers; i++)
		if (timers[i] == nil)
			break;
	if (i == len timers) {
		# grow the array
		newtimers := array [len timers * 2] of ref RealTimer;
		newtimers[0:] = timers;
		timers = newtimers;
	}
	tick := chan of int;
	t := ref Timer(i, tick);
	nticks := ms / tickres;
	if (nticks == 0)
		nticks = 1;
	rt := ref RealTimer(t, nticks, rep, big 0, tick, -1);
	timers[i] = rt;
	return t;
}

startclk : int;
stopclk : int;

main()
{
	clktick := chan of int;
	clkctl := chan of int;
	clkstopped := 1;
	spawn ticker(tickres, clkctl, clktick);

	for (;;) alt {
	<- acquire =>
		# Locking
		acquire <- = 1;

		if (clkstopped && startclk) {
			clkstopped = 0;
			startclk = 0;
			clkctl <- = 1;
		}

	t := <- clktick =>
		if (t == 0) {
			stopclk = 0;
			if (startclk) {
				startclk = 0;
				clkctl <- = 1;
			} else {
				clkstopped = 1;
				continue;
			}
		}
		curtick++;
		npend := 0;
		for (i := 0; i < len timers; i++) {
			rt := timers[i];
			if (rt == nil)
				continue;
			if (rt.nexttick == big 0)
				continue;
			if (rt.nexttick > curtick) {
				npend++;
				continue;
			}
			# Timeout - arrange to send the tick
			if (rt.rep) {
				rt.nexttick = curtick + big rt.nticks;
				npend++;
			} else
				rt.nexttick = big 0;
			si := getsender();
			s := senders[si];
			s.tid = i;
			s.idle = 0;
			rt.sender = si;
			s.ctl <- = rt.tick;

		}
		if (!npend)
			stopclk = 1;
	}
}

getsender() : int
{
	for (i := 0; i < len senders; i++) {
		s := senders[i];
		if (s == nil || s.idle == 1)
			break;
	}
	if (i == len senders) {
		newsenders := array [len senders * 2] of ref Sender;
		newsenders[0:] = senders;
		senders = newsenders;
	}
	if (senders[i] == nil) {
		s := ref Sender (-1, 1, chan of chan of int);
		spawn sender(s);
		senders[i] = s;
	}
	return i;
}

sender(me : ref Sender)
{
	for (;;) {
		tickch := <- me.ctl;
		tickch <- = 1;
		me.idle = 1;
	}
}

ticker(ms : int, start, tick : chan of int)
{
	for (;;) {
		<- start;
		while (!stopclk) {
			sys->sleep(ms);
			tick <- = 1;
		}
		tick <- = 0;
	}
}
