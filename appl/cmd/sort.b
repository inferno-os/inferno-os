implement Sort;

include "sys.m";
	sys: Sys;
include "bufio.m";
include "draw.m";
include "arg.m";

Sort: module
{
	init:	fn(nil: ref Draw->Context, args: list of string);
};

usage()
{
	sys->fprint(sys->fildes(2), "usage: sort [-n] [file]\n");
	raise "fail:usage";
}

Incr: con 2000;		# growth quantum for record array

init(nil : ref Draw->Context, args : list of string)
{
	bio : ref Bufio->Iobuf;

	sys = load Sys Sys->PATH;
	stderr := sys->fildes(2);
	bufio := load Bufio Bufio->PATH;
	if (bufio == nil) {
		sys->fprint(stderr, "sort: cannot load %s: %r\n", Bufio->PATH);
		raise "fail:bad module";
	}
	Iobuf: import bufio;
	arg := load Arg Arg->PATH;
	if (arg == nil) {
		sys->fprint(stderr, "sort: cannot load %s: %r\n", Arg->PATH);
		raise "fail:bad module";
	}

	nflag := 0;
	rflag := 0;
	arg->init(args);
	while ((opt := arg->opt()) != 0) {
		case opt {
		'n' =>
			nflag = 1;
		'r' =>
			rflag = 1;
		* =>
			usage();
		}
	}
	args = arg->argv();
	if (len args > 1)
		usage();
	if (args != nil) {
		bio = bufio->open(hd args, Bufio->OREAD);
		if (bio == nil) {
			sys->fprint(stderr, "sort: cannot open %s: %r\n", hd args);
			raise "fail:open file";
		}
	}
	else
		bio = bufio->fopen(sys->fildes(0), Bufio->OREAD);
	a := array[Incr] of string;
	n := 0;
	while ((s := bio.gets('\n')) != nil) {
		if (n >= len a) {
			b := array[len a + Incr] of string;
			b[0:] = a;
			a = b;
		}
		a[n++] = s;
	}
	if (nflag)
		mergesortnumeric(a, array[n] of string, n);
	else
		mergesort(a, array[n] of string, n);

	stdout := bufio->fopen(sys->fildes(1), Bufio->OWRITE);
	if (rflag) {
		for (i := n-1; i >= 0; i--)
			stdout.puts(a[i]);
	} else {
		for (i := 0; i < n; i++)
			stdout.puts(a[i]);
	}
	stdout.close();
}

mergesort(a, b: array of string, r: int)
{
	if (r > 1) {
		m := (r-1)/2 + 1;
		mergesort(a[0:m], b[0:m], m);
		mergesort(a[m:r], b[m:r], r-m);
		b[0:] = a[0:r];
		for ((i, j, k) := (0, m, 0); i < m && j < r; k++) {
			if (b[i] > b[j])
				a[k] = b[j++];
			else
				a[k] = b[i++];
		}
		if (i < m)
			a[k:] = b[i:m];
		else if (j < r)
			a[k:] = b[j:r];
	}
}

mergesortnumeric(a, b: array of string, r: int)
{
	if (r > 1) {
		m := (r-1)/2 + 1;
		mergesortnumeric(a[0:m], b[0:m], m);
		mergesortnumeric(a[m:r], b[m:r], r-m);
		b[0:] = a[0:r];
		for ((i, j, k) := (0, m, 0); i < m && j < r; k++) {
			if (int b[i] > int b[j])
				a[k] = b[j++];
			else
				a[k] = b[i++];
		}
		if (i < m)
			a[k:] = b[i:m];
		else if (j < r)
			a[k:] = b[j:r];
	}
}
