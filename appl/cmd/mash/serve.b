#
#	This should be called by spawned (persistent) threads.
#	It arranges for them to be killed at the end of the day.
#
reap()
{
	if (pidchan == nil) {
		pidchan = chan of int;
		spawn zombie();
	}
	pidchan <-= sys->pctl(0, nil);
}

#
#	This thread records spawned threads and kills them.
#
zombie()
{
	pids := array[10] of int;
	pidx := 0;
	for (;;) {
		pid := <- pidchan;
		if (pid == PIDEXIT) {
			for (i := 0; i < pidx; i++)
				kill(pids[i]);
			exit;
		}
		if (pidx == len pids) {
			n := pidx * 3 / 2;
			a := array[n] of int;
			a[:] = pids;
			pids = a;
		}
		pids[pidx++] = pid;
	}
}

#
#	Kill a thread.
#
kill(pid: int)
{
	fd := sys->open("#p/" + string pid + "/ctl", sys->OWRITE);
	if (fd != nil)
		sys->fprint(fd, "kill");
}

#
#	Exit top level, killing spawned threads.
#
exitmash()
{
	if (pidchan != nil)
		pidchan <-= PIDEXIT;
	exit;
}

#
#	Slice a buffer if needed.
#
restrict(buff: array of byte, count: int): array of byte
{
	if (count < len buff)
		return buff[:count];
	else
		return buff;
}

#
#	Serve mash console reads.  Favours other programs
#	ahead of the input loop.
#
serve_read(c: ref Sys->FileIO, sync: chan of int)
{
	s: string;
	in := sys->fildes(0);
	sys->pctl(Sys->NEWFD, in.fd :: nil);
	sync <-= 0;
	reap();
	buff := array[Sys->ATOMICIO] of byte;
outer:	for (;;) {
		n := sys->read(in, buff, len buff);
		if (n < 0) {
			n = 0;
			s = errstr();
		} else
			s = nil;
		b := buff[:n];
		alt {
		(off, count, fid, rc) := <-c.read =>
			if (rc == nil)
				break;
			rc <-= (restrict(b, count), s);
			continue outer;
		* =>
			;
		}
	inner:	for (;;) {
			alt {
			(off, count, fid, rc) := <-c.read =>
				if (rc == nil)
					continue inner;
				rc <-= (restrict(b, count), s);
			inchan <-= b =>
				;
			}
			break;
		}
	}
}

#
#	Serve mash console writes.
#
serve_write(c: ref Sys->FileIO, sync: chan of int)
{
	out := sys->fildes(1);
	sys->pctl(Sys->NEWFD, out.fd :: nil);
	sync <-= 0;
	reap();
	for (;;) {
		(off, data, fid, wc) := <-c.write;
		if (wc == nil)
			continue;
		if (sys->write(out, data, len data) < 0)
			wc <-= (0, errstr());
		else
			wc <-= (len data, nil);
	}
}

#
#	Begin serving the mash console.
#
Env.serve(e: self ref Env)
{
	if (servechan != nil)
		return;
	(s, c) := e.servefile(nil);
	inchan = chan of array of byte;
	servechan = chan of array of byte;
	sync := chan of int;
	spawn serve_read(c, sync);
	spawn serve_write(c, sync);
	<-sync;
	<-sync;
	if (sys->bind(s, CONSOLE, Sys->MREPL) < 0)
		e.couldnot("bind", CONSOLE);
	sys->pctl(Sys->NEWFD, nil);
	e.in = sys->open(CONSOLE, sys->OREAD | sys->ORCLOSE);
	e.out = sys->open(CONSOLE, sys->OWRITE);
	e.stderr = sys->open(CONSOLE, sys->OWRITE);
	e.wait = nil;
}
