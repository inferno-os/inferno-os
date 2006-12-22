implement Tst;
include "sys.m";
	sys: Sys;
include "draw.m";
	draw: Draw;
	Point, Rect: import draw;
include "bufio.m";
	bufio: Bufio;
	Iobuf: import bufio;

Tst: module
{
	init:   fn(ctxt: ref Draw->Context, argv: list of string);
};

File: adt {
	name: string;
	fd: ref Sys->FD;
	pid: int;
};

files: list of ref File;

stderr: ref Sys->FD;
outputch: chan of chan of string;
init(ctxt: ref Draw->Context, argv: list of string)
{
	sys = load Sys Sys->PATH;
	stderr = sys->fildes(2);
	bufio = load Bufio Bufio->PATH;
	sys->print(":cardtst\n");
	stdin := bufio->fopen(sys->fildes(0), Sys->OREAD);
	line := "";
	currfd: ref Sys->FD;
	outputch = chan of chan of string;
	spawn outputproc();
	while ((s := stdin.gets('\n')) != nil) {
		if (len s > 1 && s[len s - 2] == '\\')
			line += s[0:len s - 2] + "\n";
		else {
			s = line + s;
			line = nil;
			if (s[0] == ':') {
				(nil, toks) := sys->tokenize(s, " \n");
				case hd toks {
				":open" =>
					if (tl toks == nil) {
						sys->fprint(stderr, "usage: open file\n");
						continue;
					}
					f := open(hd tl toks);
					if (f != nil) {
						currfd = f.fd;
						sys->print("current file is now %s\n", f.name);
					}
				":close" =>
					if (tl toks == nil) {
						sys->fprint(stderr, "usage: close file\n");
						continue;
					}
					fl := files;
					f: ref File;
					for (files = nil; fl != nil; fl = tl fl) {
						if ((hd fl).name == hd tl toks)
							f = hd fl;
						else
							files = hd fl :: files;
					}
					if (f == nil) {
						sys->fprint(stderr, "unknown file '%s'\n", hd tl toks);
						continue;
					}
					sys->fprint(f.fd, "");
					f = nil;
				":files" =>
					for (fl := files; fl != nil; fl = tl fl) {
						if ((hd fl).fd == currfd)
							sys->print(":%s <--- current\n", (hd fl).name);
						else
							sys->print(":%s\n", (hd fl).name);
					}
				* =>
					for (fl := files; fl != nil; fl = tl fl)
						if ((hd fl).name == (hd toks)[1:])
							break;
					if (fl == nil) {
						sys->fprint(stderr, "unknown file '%s'\n", (hd toks)[1:]);
						continue;
					}
					currfd = (hd fl).fd;
				}
			} else if (currfd == nil)
				sys->fprint(stderr, "no current file\n");
			else if (len s > 1 && sys->fprint(currfd, "%s", s[0:len s - 1]) == -1)
				sys->fprint(stderr, "command failed: %r\n");
		}
	}
	for (fl := files; fl != nil; fl = tl fl)
		kill((hd fl).pid);
	outputch <-= nil;
}

open(f: string): ref File
{
	fd := sys->open("/n/remote/" + f, Sys->ORDWR);
	if (fd == nil) {
		sys->fprint(stderr, "cannot open %s: %r\n", f);
		return nil;
	}
	sync := chan of int;
	spawn updateproc(f, fd, sync);
	files = ref File(f, fd, <-sync) :: files;
	sys->print("opened %s\n", f);
	return hd files;
}

updateproc(name: string, fd: ref Sys->FD,  sync: chan of int)
{
	sync <-= sys->pctl(0, nil);
	c := chan of string;
	buf := array[Sys->ATOMICIO] of byte;
	while ((n := sys->read(fd, buf, len buf)) > 0) {
		(nt, toks) := sys->tokenize(string buf[0:n], "\n");
		outputch <-= c;
		c <-= "++ " + name + ":\n";
		for (; toks != nil; toks = tl toks)
			c <-= sys->sprint("+%s\n", hd toks);
		c <-= nil;
	}
	if (n < 0)
		sys->fprint(stderr, "cards: error reading %s: %r\n", name);
	sys->fprint(stderr, "cards: updateproc (%s) exiting\n", name);
}

outputproc()
{
	for (;;) {
		c := <-outputch;
		if (c == nil)
			exit;
		while ((s := <-c) != nil)
			sys->print("%s", s);
	}
}

kill(pid: int)
{
	if ((fd := sys->open("/prog/"+string pid+"/ctl", Sys->OWRITE)) != nil)
		sys->write(fd, array of byte "kill", 4);
}

