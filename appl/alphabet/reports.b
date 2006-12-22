implement Reports;
include "sys.m";
	sys: Sys;
include "draw.m";
include "sh.m";
include "alphabet/reports.m";

Reporter: adt {
	id: int;
	name: string;
	stopc: chan of int;
};

reportproc(errorc: chan of string, stopc: chan of int, reply: chan of ref Report)
{
	if(sys == nil)
		sys = load Sys Sys->PATH;
	r := ref Report(chan of (string, chan of string, chan of int), chan of int);
	if(stopc == nil)
		stopc = chan of int;
	else
		sys->pctl(Sys->NEWPGRP, nil);
	reply <-= r;
	reportproc0(stopc, errorc, r.startc, r.enablec);
}

Report.start(r: self ref Report, name: string): chan of string
{
	if(r == nil)
		return nil;
	errorc := chan of string;
	r.startc <-= (name, errorc, nil);
	return errorc;
}

Report.add(r: self ref Report, name: string, errorc: chan of string, stopc: chan of int)
{
	r.startc <-= (name, errorc, stopc);
}

Report.enable(r: self ref Report)
{
	r.enablec <-= 0;
}

reportproc0(
		stopc: chan of int,
		reportc: chan of string,
		startc: chan of (string, chan of string, chan of int),
		enablec: chan of int
	)
{
	realc := array[2] of chan of string;
	p := array[len realc] of Reporter;
	a := array[0] of chan of string;
	id := n := 0;
	stopped := 0;
out:
	for(;;) alt{
	<-stopc =>
		stopped = 1;
		break out;
	(prefix, c, stop) := <-startc =>
		if(n == len realc){
			if(realc == a)
				a = nil;
			realc = (array[n * 2] of chan of string)[0:] = realc;
			p = (array[n * 2] of Reporter)[0:] = p;
			if(a == nil)
				a = realc;
		}
		realc[n] = c;
		p[n] = (id++, prefix, stop);
		n++;
	<-enablec =>
		if(n == 0)
			break out;
		a = realc;
	(x, msg) := <-a =>
		if(msg == nil){
			if(--n == 0)
				break out;
			if(n != x){
				a[x] = a[n];
				a[n] = nil;
				p[x] = p[n];
				p[n] = (-1, nil, nil);
			}
		}else{
			if(reportc != nil){
				alt{
				reportc <-= sys->sprint("%d. %s: %s", p[x].id, p[x].name, msg) =>
					;
				<-stopc =>
					stopped = 1;
					break out;
				}
			}
		}
	}
	if(stopped == 0){
		if(reportc != nil){
			alt{
			reportc <-= nil =>
				;
			<-stopc =>
				stopped = 1;
			}
		}
	}
	if(stopped){
		for(i := 0; i < n; i++)
			note(p[i].stopc);
		note(stopc);
	}
}

quit(errorc: chan of string)
{
	if(errorc != nil)
		errorc <-= nil;
	exit;
}

report(errorc: chan of string, err: string)
{
	if(errorc != nil)
		errorc <-= err;
}

newpgrp(stopc: chan of int, flags: int): chan of int
{
	if(sys == nil)
		sys = load Sys Sys->PATH;
	if(flags&PROPAGATE){
		if(stopc == nil)
			stopc = chan[1] of int;
		sys->pipe(p := array[2] of ref Sys->FD);
		spawn deadman(p[1]);
		sys->pctl(Sys->NEWPGRP, nil);
		spawn watchproc(p[0], stopc); 
	}else
		sys->pctl(Sys->NEWPGRP, nil);
	spawn grpproc(stopc, newstopc := chan[1] of int, flags&KILL);
	return newstopc;
}

grpproc(noteparent, noteself: chan of int, kill: int)
{
	if(noteparent == nil)
		noteparent = chan of int;
	alt{
	<-noteparent =>
		note(noteparent);
	<-noteself =>
		;
	}
	note(noteself);
	if(kill){
		pid := sys->pctl(0, nil);
		fd := sys->open("#p/"+string pid+"/ctl", Sys->OWRITE);
		if(fd == nil)
			fd = sys->open("/prog/"+string pid+"/ctl", Sys->OWRITE);
		sys->fprint(fd, "killgrp");
	}
}

note(c: chan of int)
{
	if(c != nil){
		alt {
		c <-= 1 =>
			;
		* =>
			;
		}
	}
}

deadman(nil: ref Sys->FD)
{
	<-chan of int;
}

watchproc(fd: ref Sys->FD, stopc: chan of int)
{
	sys->read(fd, array[1] of byte, 1);
	note(stopc);
}
