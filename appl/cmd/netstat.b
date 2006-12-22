implement Netstat;

include "sys.m";
sys: Sys;
FD, Dir: import sys;
fildes, open, fstat, read, dirread, fprint, print, tokenize: import sys;

include "draw.m";
Context: import Draw;

Netstat: module
{
	init:	fn(ctxt: ref Context, argv: list of string);
};

stderr: ref FD;

init(nil: ref Context, nil: list of string)
{
	sys = load Sys Sys->PATH;

	stderr = fildes(2);

	nstat("/net/tcp", 1);
	nstat("/net/udp", 1);
	nstat("/net/il", 0);
}

nstat(file: string, whine: int)
{
	dir: Dir;
 	i, ok: int;

	fd := open(file, sys->OREAD);
	if(fd == nil) {
		if(whine)
			fprint(stderr, "netstat: %s: %r\n", file);
		return;
	}

	(ok, dir) = fstat(fd);
	if(ok == -1) {
		fprint(stderr, "netstat: fstat %s: %r\n", file);
		fd = nil;
		return;
	}
	if((dir.mode&Sys->DMDIR) == 0) {
		fprint(stderr, "netstat: not a protocol directory: %s\n", file);
		return;
	}
	for(;;) {
		(n, d) := dirread(fd);
		if(n <= 0)
			break;
		for(i = 0; i < n; i++)
			if(d[i].name[0] <= '9')
				nsprint(file+"/"+d[i].name, d[i].uid);		
	}
}

fc(file: string): string
{
	fd := open(file, sys->OREAD);
	if(fd == nil)
		return "??";

	buf := array[64] of byte;
	n := read(fd, buf, len buf);
	if(n <= 1)
		return "??";
	if(int buf[n-1] == '\n')
		n--;

	return string buf[0:n];
}

nsprint(name, user: string)
{
	n: int;
	s: list of string;

	sr := fc(name+"/status");
	(n, s) = tokenize(sr, " ");

	print("%-10s %-10s %-12s %-20s %s\n",
		name[5:],
		user,
		hd s,
		fc(name+"/local"),
		fc(name+"/remote"));
}
