implement Lc;

include "sys.m";
	sys: Sys;
include "draw.m";
include "readdir.m";
	readdir: Readdir;
include "bufio.m";
	bufio: Bufio;
	Iobuf: import bufio;

Lc: module {
	init: fn(nil: ref Draw->Context, argv: list of string);
};

t_FILE, t_DIR, t_NUMTYPES: con iota;
columns := 65;
stderr: ref Sys->FD;
stdout: ref Iobuf;

usage()
{
	sys->fprint(stderr, "usage: lc [-df] [-c columns] [file ...]\n");
	raise "fail:usage";
}

init(nil: ref Draw->Context, argv: list of string)
{
	sys = load Sys Sys->PATH;
	stderr = sys->fildes(2);
	readdir = load Readdir Readdir->PATH;
	if (readdir == nil) {
		sys->fprint(stderr, "lc: cannot load %s: %r\n", Readdir->PATH);
		raise "fail:bad module";
	}
	bufio = load Bufio Bufio->PATH;
	stdout = bufio->fopen(sys->fildes(1), Sys->OWRITE);
	if (bufio == nil) {
		sys->fprint(stderr, "lc: cannot load %s: %r\n", Bufio->PATH);
		raise "fail:bad module";
	}
	if (argv == nil)
		return;
	argv = tl argv;
	flags := 0;
loop:	while (argv != nil && hd argv != nil && (hd argv)[0] == '-') {
		s := (hd argv)[1:];
		argv = tl argv;
	flagloop: for (; s != nil; s = s[1:]) {
			case s[0] {
			'-' =>
				break loop;
			'd' =>
				flags |= 1 << t_DIR;
			'f' =>
				flags |= 1 << t_FILE;
			'c' =>
				if (len s > 1) {
					columns = int s[1:];
					break flagloop;
				}
				if (argv == nil)
					usage();
				columns = int hd argv;
				argv = tl argv;
			* =>
				usage();
			}
		}
	}
					
	headings := 0;
	if (flags == 0) {
		flags = (1<<t_DIR)|(1<<t_FILE);
		headings = 1;
	}
	if (argv == nil)
		argv = "." :: nil;
	multi := tl argv != nil;
	nondir: list of string;
	for (; argv != nil; argv = tl argv) {
		dname := hd argv;
		(ok, dir) := sys->stat(dname);
		if(ok < 0) {
			sys->fprint(stderr, "lc: can't stat %s: %r\n", hd argv);
			continue;
		}
		if (dir.mode & Sys->DMDIR) {
			(d, n) := readdir->init(hd argv, Readdir->NAME | Readdir->COMPACT);
			if (n < 0)
				sys->fprint(stderr, "lc: cannot read %s: %r\n", hd argv);
			else {
				indent := 0;
				if (multi && headings) {
					stdout.puts(hd argv + "/\n");
					indent = 2;
				}
				l: list of string = nil;
				for (i := 0; i < n; i++) {
					s := d[i].name;
					if (!headings && dname != ".")
						s = dname + "/" + s;
					if (d[i].mode & Sys->DMDIR) {
						if (flags & (1<<t_DIR))
							l = s + "/" :: l;
					} else if (flags & (1<<t_FILE))
						l = s :: l;
				}
				d = nil;
				lc(l, indent);
			}
		} else if (flags & (1 << t_FILE))
			nondir = dname :: nondir;
	}
	lc(nondir, 0);
	stdout.close();
}

lc(dl: list of string, indent: int)
{
	a := array[len dl] of string;
	j := len a - 1;
	maxwidth := 0;
	for (; dl != nil; dl = tl dl) {
		s := hd dl;
		a[j--] = s;
		if (len s > maxwidth)
			maxwidth = len s;
	}
	outcols(a, maxwidth, indent);
}
		
outcols(stuff: array of string, maxwidth, indent: int)
{
	num := len stuff;
	cols := columns - indent;
	numcols := cols / (maxwidth + 1);
	colwidth: int;
	if (numcols == 0) {
		numcols = 1;
		colwidth = maxwidth;
	} else
		colwidth = cols / numcols;
	numrows := (num + numcols - 1) / numcols;
	
	for (i := 0; i < numrows; i++) {
		if (indent)
			stdout.puts(sys->sprint("%*s", indent, ""));
		for (j := i; j < num; j += numrows) {
			if (j + numrows < num)
				stdout.puts(sys->sprint("%*.*s", -colwidth, colwidth, stuff[j]));
			else
				stdout.puts(sys->sprint("%.*s\n", colwidth, stuff[j]));
		}
	}
}
