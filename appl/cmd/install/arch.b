implement Arch;

include "sys.m";
	sys: Sys;
include "draw.m";
include "daytime.m";
	daytime : Daytime;
include "string.m";
	str : String;
include "bufio.m";
	bufio : Bufio;
	Iobuf : import bufio;
include "sh.m";
include "arch.m";

addp := 1;

buf := array[Sys->ATOMICIO] of byte;

init(bio: Bufio)
{
	sys = load Sys Sys->PATH;
	if(bio == nil)
		bufio = load Bufio Bufio->PATH;
	else
		bufio = bio;
	daytime = load Daytime Daytime->PATH;
	str = load String String->PATH;
}

addperms(p: int)
{
	addp = p;
}

openarch(file : string) : ref Archive
{
	return openarch0(file, 1);
}

openarchfs(file : string) : ref Archive
{
	return openarch0(file, 0);
}

openarch0(file : string, newpgrp : int) : ref Archive
{
	pid := 0;
	canseek := 1;
	b := bufio->open(file, Bufio->OREAD);
	if (b == nil)
		return nil;
	if (b.getb() == 16r1f && ((c := b.getb()) == 16r8b || c == 16r9d)) {
		# spawn gunzip
		canseek = 0;
		(b, pid) = gunzipstream(file, newpgrp);
		if (b == nil)
			return nil;
	}
	else
		b.seek(big 0, Bufio->SEEKSTART);
	ar := ref Archive;
	ar.b = b;
	ar.nexthdr = 0;
	ar.canseek = canseek;
	ar.pid = pid;
	ar.hdr = ref Ahdr;
	ar.hdr.d = ref Sys->Dir;
	return ar;
}

EOARCH : con "end of archive\n";
PREMEOARCH : con "premature end of archive";
NFLDS : con 6;

openarchgz(file : string) : (string, ref Sys->FD)
{
	ar := openarch(file);
	if (ar == nil || ar.canseek)
		return (nil, nil);
	(newfile, fd) := opentemp("wrap.gz");
	if (fd == nil)
		return (nil, nil);
	bout := bufio->fopen(fd, Bufio->OWRITE);
	if (bout == nil)
		return (nil, nil);
	while ((a := gethdr(ar)) != nil) {
		if (len a.name >= 5 && a.name[0:5] == "/wrap") {
			puthdr(bout, a.name, a.d);
			getfile(ar, bout, int a.d.length);
		}
		else
			break;
	}
	closearch(ar);
	bout.puts(EOARCH);
	bout.flush();
	sys->seek(fd, big 0, Sys->SEEKSTART);
	return (newfile, fd);
}

gunzipstream(file : string, newpgrp : int) : (ref Iobuf, int)
{
	p := array[2] of ref Sys->FD;
	if (sys->pipe(p) < 0)
		return (nil, 0);
	fd := sys->open(file, Sys->OREAD);
	if (fd == nil)
		return (nil, 0);
	b := bufio->fopen(p[0], Bufio->OREAD);
	if (b == nil)
		return (nil, 0);
	c := chan of int;
	spawn gunzip(fd, p[1], c, newpgrp);
	pid := <- c;
	p[0] = p[1] = nil;
	if (pid < 0)
		return (nil, 0);
	return (b, pid);
}

GUNZIP : con "/dis/gunzip.dis";

gunzip(stdin : ref Sys->FD, stdout : ref Sys->FD, c : chan of int, newpgrp : int)
{
	if (newpgrp)
		pid := sys->pctl(Sys->FORKFD|Sys->NEWPGRP, nil);
	else
		pid = sys->pctl(Sys->FORKFD, nil);
	sys->dup(stdin.fd, 0);
	sys->dup(stdout.fd, 1);
	sys->dup(1, 2);
	stdin = stdout = nil;
	cmd := load Command GUNZIP;
	if (cmd == nil) {
		c <-= -1;
		return;
	}
	c <-= pid;
	cmd->init(nil, GUNZIP :: nil);
}

closearch(ar : ref Archive)
{
	if (ar.pid != 0) {
		fd := sys->open("#p/" + string ar.pid + "/ctl", sys->OWRITE);
		if (fd != nil)
			sys->fprint(fd, "killgrp");
	}
	ar.b.close();
	ar.b = nil;
}

gethdr(ar : ref Archive) : ref Ahdr
{
	a := ar.hdr;
	b := ar.b;
	m := int b.offset();
	n := ar.nexthdr;
	if (m != n) {
		if (ar.canseek)
			b.seek(big n, Bufio->SEEKSTART);
		else {
			if (m > n)
				fatal(sys->sprint("bad offset in gethdr: m=%d n=%d", m, n));
			if(drain(ar, n-m) < 0)
				return nil;
		}
	}
	if ((s := b.gets('\n')) == nil) {
		ar.err = PREMEOARCH;
		return nil;
	}
# fd := sys->open("./debug", Sys->OWRITE);
# sys->seek(fd, 0, Sys->SEEKEND);
# sys->fprint(fd, "gethdr: %d %d %d %d %s\n", ar.canseek, m, n, b.offset(), s);
# fd = nil;
	if (s == EOARCH)
		return nil;
	(nf, fs) := sys->tokenize(s, " \t\n");
	if(nf != NFLDS) {
		ar.err = "too few fields in file header";
		return nil;
	}
	a.name = hd fs;						fs = tl fs;
	(a.d.mode, nil) = str->toint(hd fs, 8);		fs = tl fs;
	a.d.uid = hd fs;						fs = tl fs;
	a.d.gid = hd fs;						fs = tl fs;
	(a.d.mtime, nil) = str->toint(hd fs, 10);	fs = tl fs;
	(tmp, nil) := str->toint(hd fs, 10);		fs = tl fs;
	a.d.length = big tmp;
	ar.nexthdr = int (b.offset()+a.d.length);
	return a;
}

getfile(ar : ref Archive, bout : ref Bufio->Iobuf, n : int) : string
{
	err: string;
	bin := ar.b;
	while (n > 0) {
		m := len buf;
		if (n < m)
			m = n;
		p := bin.read(buf, m);
		if (p != m)
			return PREMEOARCH;
		p = bout.write(buf, m);
		if (p != m)
			err = sys->sprint("cannot write: %r");
		n -= m;
	}
	return err;	
}

puthdr(b : ref Iobuf, name : string, d : ref Sys->Dir)
{
	mode := d.mode;
	if(addp){
		mode |= 8r664;
		if(mode & Sys->DMDIR || mode & 8r111)
			mode |= 8r111;
	}
	b.puts(sys->sprint("%s %uo %s %s %ud %d\n", name, mode, d.uid, d.gid, d.mtime, int d.length));
}

putstring(b : ref Iobuf, s : string)
{
	b.puts(s);
}

putfile(b : ref Iobuf, f : string, n : int) : string
{
	fd := sys->open(f, Sys->OREAD);
	if (fd == nil)
		return sys->sprint("cannot open %s: %r", f);
	i := 0;
	for (;;) {
		m := sys->read(fd, buf, len buf);
		if (m < 0)
			return sys->sprint("cannot read %s: %r", f);
		if (m == 0)
			break;
		if (b.write(buf, m) != m)
			return sys->sprint("%s: cannot write: %r", f);
		i += m;
	}
	if (i != n) {
		b.seek(big (n-i), Sys->SEEKRELA);
		return sys->sprint("%s: %d bytes written: should be %d", f, i, n);
	}
	return nil;
}

putend(b : ref Iobuf)
{
	b.puts(EOARCH);
	b.flush();
}

drain(ar : ref Archive, n : int) : int
{
	while (n > 0) {
		m := n;
		if (m > len buf)
			m = len buf;
		p := ar.b.read(buf, m);
		if (p != m){
			ar.err = "unexpectedly short read";
			return -1;
		}
		n -= m;
	}
	return 0;	
}

opentemp(prefix: string): (string, ref Sys->FD)
{
	name := sys->sprint("/tmp/%s.%ud.%d", prefix, daytime->now(), sys->pctl(0, nil));
	# would use ORCLOSE here but it messes up under Nt
	fd := sys->create(name, Sys->ORDWR, 8r600);
	return (name, fd);
}

fatal(s : string)
{
	sys->fprint(sys->fildes(2), "%s\n", s);
	raise "fail:error";
}
