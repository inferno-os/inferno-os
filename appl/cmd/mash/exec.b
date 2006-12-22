#
#	Manage the execution of a command.
#

srv:	string;		# srv file proto
nsrv:	int = 0;	# srv file unique id

#
#	Return error string.
#
errstr(): string
{
	return sys->sprint("%r");
}

#
#	Server thread for servefd.
#
server(c: ref Sys->FileIO, fd: ref Sys->FD, write: int)
{
	a: array of byte;
	if (!write)
		a = array[Sys->ATOMICIO] of byte;
	for (;;) {
		alt {
		(nil, b, nil, wc) := <- c.write =>
			if (wc == nil)
				return;
			if (!write) {
				wc <- = (0, EPIPE);
				return;
			}
			r := sys->write(fd, b, len b);
			if (r < 0) {
				wc <- = (0, errstr());
				return;
			}
			wc <- = (r, nil);
		(nil, n, nil, rc) := <- c.read =>
			if (rc == nil)
				return;
			if (write) {
				rc <- = (array[0] of byte, nil);
				return;
			}
			if (n > Sys->ATOMICIO)
				n = Sys->ATOMICIO;
			r := sys->read(fd, a, n);
			if (r < 0) {
				rc <- = (nil, errstr());
				return;
			}
			rc <- = (a[0:r], nil);
		}
	}
}

#
#	Serve FD as a #s file.  Used to implement generators.
#
Env.servefd(e: self ref Env, fd: ref Sys->FD, write: int): string
{
	(s, c) := e.servefile(nil);
	spawn server(c, fd, write);
	return s;
}

#
#	Generate name and FileIO adt for a served filed.
#
Env.servefile(e: self ref Env, n: string): (string, ref Sys->FileIO)
{
	c: ref Sys->FileIO;
	s: string;
	if (srv == nil) {
		(ok, d) := sys->stat(CHAN);
		if (ok < 0)
			e.couldnot("stat", CHAN);
		if (d.dtype != 's') {
			if (sys->bind("#s", CHAN, Sys->MBEFORE) < 0)
				e.couldnot("bind", CHAN);
		}
		srv = "mash." + string sys->pctl(0, nil);
	}
	retry := 0;
	for (;;) {
		if (retry || n == nil)
			s = srv + "." + string nsrv++;
		else
			s = n;
		c = sys->file2chan(CHAN, s);
		s = CHAN + "/" + s;
		if (c == nil) {
			if (retry || n == nil || errstr() != EEXISTS)
				e.couldnot("file2chan", s);
			retry = 1;
			continue;
		}
		break;
	}
	if (n != nil)
		n = CHAN + "/" + n;
	else
		n = s;
	if (retry && sys->bind(s, n, Sys->MREPL) < 0)
		e.couldnot("bind", n);
	return (n, c);
}

#
#	Shorthand for string output.
#
Env.output(e: self ref Env, s: string)
{
	if (s == nil)
		return;
	out := e.outfile();
	if (out == nil)
		return;
	out.puts(s);
	out.close();
}

#
#	Return Iobuf for stdout.
#
Env.outfile(e: self ref Env): ref Bufio->Iobuf
{
	fd := e.out;
	if (fd == nil)
		fd = sys->fildes(1);
	out := bufio->fopen(fd, Bufio->OWRITE);
	if (out == nil)
		e.report(sys->sprint("fopen failed: %r"));
	return out;
}

#
#	Return FD for /dev/null.
#
Env.devnull(e: self ref Env): ref Sys->FD
{
	fd := sys->open(DEVNULL, Sys->OREAD);
	if (fd == nil)
		e.couldnot("open", DEVNULL);
	return fd;
}

#
#	Make a pipe.
#
Env.pipe(e: self ref Env): array of ref Sys->FD
{
	fds := array[2] of ref Sys->FD;
	if (sys->pipe(fds) < 0) {
		e.report(sys->sprint("pipe failed: %r"));
		return nil;
	}
	return fds;
}

#
#	Open wait file for an env.
#
waitfd(e: ref Env)
{
	w := "#p/" + string sys->pctl(0, nil) + "/wait";
	fd := sys->open(w, sys->OREAD);
	if (fd == nil)
		e.couldnot("open", w);
	e.wait = fd;
}

#
#	Wait for a thread.  Perhaps propagate exception or exit.
#
waitfor(e: ref Env, pid: int, wc: chan of int, ec, xc: chan of string)
{
	if (ec != nil || xc != nil) {
		spawn waiter(e, pid, wc);
		if (ec == nil)
			ec = chan of string;
		if (xc == nil)
			xc = chan of string;
		alt {
		<-wc =>
			return;
		x := <-ec =>
			<-wc;
			exitmash();
		x := <-xc =>
			<-wc;
			s := x;
			if (len s < FAILLEN || s[0:FAILLEN] != FAIL)
				s = FAIL + s;
			raise s;
		}
	} else
		waiter(e, pid, nil);
}

#
#	Wait for a specific pid.
#
waiter(e: ref Env, pid: int, wc: chan of int)
{
	buf := array[sys->WAITLEN] of byte;
	for(;;) {
		n := sys->read(e.wait, buf, len buf);
		if (n < 0) {
			e.report(sys->sprint("read wait: %r\n"));
			break;
		}
		status := string buf[0:n];
		if (status[len status - 1] != ':')
			sys->fprint(e.stderr, "%s\n", status);
		who := int status;
		if (who != 0 && who == pid)
			break;
	}
	if (wc != nil)
		wc <-= 0;
}

#
#	Preparse IO for a new thread.
#	Make a new FD group and redirect stdin/stdout.
#
prepareio(in, out: ref sys->FD): (int, ref Sys->FD)
{
	fds := list of { 0, 1, 2};
	if (in != nil)
		fds = in.fd :: fds;
	if (out != nil)
		fds = out.fd :: fds;
	pid := sys->pctl(sys->NEWFD, fds);
	console := sys->fildes(2);
	if (in != nil) {
		sys->dup(in.fd, 0);
		in = nil;
	}
	if (out != nil) {
		sys->dup(out.fd, 1);
		out = nil;
	}
	return (pid, console);
}

#
#	Add ".dis" to a command if missing.
#
dis(s: string): string
{
	if (len s < 4 || s[len s - 4:] != ".dis")
		return s + ".dis";
	return s;
}

#
#	Load a builtin.
#
Env.doload(e: self ref Env, s: string)
{
	file := dis(s);
	l := load Mashbuiltin file;
	if (l == nil) {
		err := errstr();
		if (nonexistent(err) && file[0] != '/' && file[0:2] != "./") {
			l = load Mashbuiltin LIB + file;
			if (l == nil)
				err = errstr();
		}
		if (l == nil) {
			e.report(s + ": " + err);
			return;
		}
	}
	l->mashinit("load" :: s :: nil, lib, l, e);
}

#
#	Execute a spawned thread (dis module or builtin).
#
mkprog(args: list of string, e: ref Env, in, out: ref Sys->FD, wc: chan of int, ec, xc: chan of string)
{
	(pid, console) := prepareio(in, out);
	wc <-= pid;
	if (pid < 0)
		return;
	cmd := hd args;
	{
		b := e.builtin(cmd);
		if (b != nil) {
			e = e.copy();
			e.in = in;
			e.out = out;
			e.stderr = console;
			e.wait = nil;
			b->mashcmd(e, args);
		} else {
			file := dis(cmd);
			c := load Command file;
			if (c == nil) {
				err := errstr();
				if (nonexistent(err) && file[0] != '/' && file[0:2] != "./") {
					c = load Command "/dis/" + file;
					if (c == nil)
						err = errstr();
				}
				if (c == nil) {
					sys->fprint(console, "%s: %s\n", file, err);
					return;
				}
			}
			c->init(gctxt, args);
		}
	}exception x{
	FAILPAT =>
		if (xc != nil)
			xc <-= x;
		# the command failure should be propagated silently to
		# a higher level, where $status can be set.. - wrtp.
		#else
		#	sys->fprint(console, "%s: %s\n", cmd, x.name);
		exit;
	EPIPE =>
		if (xc != nil)
			xc <-= x;
		#else
		#	sys->fprint(console, "%s: %s\n", cmd, x.name);
		exit;
	EXIT =>
		if (ec != nil)
			ec <-= x;
		exit;
	}
}

#
#	Open/create files for redirection.
#
redirect(e: ref Env, f: array of string, in, out: ref Sys->FD): (int, ref Sys->FD, ref Sys->FD)
{
	s: string;
	err := 0;
	if (f[Rinout] != nil) {
		s = f[Rinout];
		in = sys->open(s, Sys->ORDWR);
		if (in == nil) {
			sys->fprint(e.stderr, "%s: %r\n", s);
			err = 1;
		}
		out = in;
	} else if (f[Rin] != nil) {
		s = f[Rin];
		in = sys->open(s, Sys->OREAD);
		if (in == nil) {
			sys->fprint(e.stderr, "%s: %r\n", s);
			err = 1;
		}
	}
	if (f[Rout] != nil || f[Rappend] != nil) {
		if (f[Rappend] != nil) {
			s = f[Rappend];
			out = sys->open(s, Sys->OWRITE);
			if (out != nil)
				sys->seek(out, big 0, Sys->SEEKEND);
		} else {
			s = f[Rout];
			out = nil;
		}
		if (out == nil) {
			out = sys->create(s, Sys->OWRITE, 8r666);
			if (out == nil) {
				sys->fprint(e.stderr, "%s: %r\n", s);
				err = 1;
			}
		}
	}
	if (err)
		return (0, nil, nil);
	return (1, in, out);
}

#
#	Spawn a command and maybe wait for it.
#
exec(a: list of string, e: ref Env, infd, outfd: ref Sys->FD, wait: int)
{
	if (wait && e.wait == nil)
		waitfd(e);
	wc := chan of int;
	if (wait && (e.flags & ERaise))
		xc := chan of string;
	if (wait && (e.flags & ETop))
		ec := chan of string;
	spawn mkprog(a, e, infd, outfd, wc, ec, xc);
	pid := <-wc;
	if (wait)
		waitfor(e, pid, wc, ec, xc);
}
