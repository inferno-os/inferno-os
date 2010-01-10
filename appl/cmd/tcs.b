implement Tcs;

include "sys.m";
	sys: Sys;
include "draw.m";
include "arg.m";
include "bufio.m";
	bufio: Bufio;
	Iobuf: import bufio;
include "convcs.m";
	convcs: Convcs;

Tcs: module
{
	init: fn (nil: ref Draw->Context, args: list of string);
};

stderr: ref Sys->FD;

init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	stderr = sys->fildes(2);
	if ((arg := load Arg Arg->PATH) == nil)
		badmodule(Arg->PATH);
	if ((bufio = load Bufio Bufio->PATH) == nil)
		badmodule(Bufio->PATH);
	if ((convcs = load Convcs Convcs->PATH) == nil)
		badmodule(Convcs->PATH);

	arg->init(args);
	arg->setusage("tcs [-C configfile] [-l] [-f ics] [-t ocs] file ...");
	lflag := 0;
	vflag := 0;
	ics := "utf8";
	ocs := "utf8";
	csfile := "";
	while ((c := arg->opt()) != 0) {
		case c {
		'C' =>
			csfile = arg->arg();
		'f' =>
			ics = arg->arg();
		'l' =>
			lflag = 1;
		't' =>
			ocs = arg->arg();
		'v' =>
			vflag = 1;
		* =>
			arg->usage();
		}
	}
	file := arg->arg();

	out := bufio->fopen(sys->fildes(1), Sys->OWRITE);
	err := convcs->init(csfile);
	if (err != nil) {
		sys->fprint(stderr, "convcs: %s\n", err);
		raise "fail:init";
	}

	if (lflag) {
		if (file != nil)
			dumpaliases(out, file, vflag);
		else
			dumpconvs(out, vflag);
		return;
	}
	
	stob: Stob;
	btos: Btos;
	(stob, err) = convcs->getstob(ocs);
	if (err != nil) {
		sys->fprint(stderr, "tcs: %s: %s\n", ocs, err);
		raise "fail:badarg";
	}
	(btos, err) = convcs->getbtos(ics);
	if (err != nil) {
		sys->fprint(stderr, "tcs: %s: %s\n", ics, err);
		raise "fail:badarg";
	}

	fd: ref Sys->FD;
	if (file == nil) {
		fd = sys->fildes(0);
		file = "standard input";
	} else
		fd = open(file);

	inbuf := array [Sys->ATOMICIO] of byte;
	for(;;){
		btoss: Convcs->State = nil;
		stobs: Convcs->State = nil;

		unc := 0;
		nc: int;
		s: string;
		while ((n := sys->read(fd, inbuf[unc:], len inbuf - unc)) > 0) {
			n += unc;		# include unconsumed prefix
			(btoss, s, nc) = btos->btos(btoss, inbuf[0:n], -1);
			if (s != nil)
				stobs = output(out, stob, stobs, s);
			# copy down unconverted part of buffer
			unc = n - nc;
			if (unc > 0 && nc > 0)
				inbuf[0:] = inbuf[nc: n];
		}
		if (n < 0) {
			sys->fprint(stderr, "tcs: error reading %s: %r\n", file);
			raise "fail:read error";
		}

		# flush conversion state
		(nil, s, nil) = btos->btos(btoss, inbuf[0: unc], 0);
		if(s != nil)
			stobs = output(out, stob, stobs, s);
		output(out, stob, stobs, "");

		if(out.flush() != 0) {
			sys->fprint(stderr, "tcs: write error: %r\n");
			raise "fail:write error";
		}
		file = arg->arg();
		if (file == nil)
			break;
		fd = open(file);
	}
}

output(out: ref Iobuf, stob: Stob, stobs: Convcs->State, s: string): Convcs->State
{
	outbuf: array of byte;
	(stobs, outbuf) = stob->stob(stobs, s);
	if(outbuf != nil)
		out.write(outbuf, len outbuf);
	return stobs;
}

badmodule(s: string)
{
	sys->fprint(stderr, "tcs: cannot load module %s: %r\n", s);
	raise "fail:init";
}

dumpconvs(out: ref Iobuf, verbose: int)
{
	first := 1;
	for (csl := convcs->enumcs(); csl != nil; csl = tl csl) {
		(name, desc, mode) := hd csl;
		if (!verbose) {
			if (!first)
				out.putc(' ');
			out.puts(name);
		} else {
			ms := "";
			case mode {
			Convcs->BTOS =>
				ms = "(from)";
			Convcs->STOB =>
				ms = "(to)";
			}
			out.puts(sys->sprint("%s%s\t%s\n", name, ms, desc));
		}
		first = 0;
	}
	if (!verbose)
		out.putc('\n');
	out.flush();
}

dumpaliases(out: ref Iobuf, cs: string, verbose: int)
{
	(desc, asl) := convcs->aliases(cs);
	if (asl == nil) {
		sys->fprint(stderr, "%s\n", desc);
		return;
	}

	if (verbose) {
		out.puts(desc);
		out.putc('\n');
	}
	first := 1;
	for (; asl != nil; asl = tl asl) {
		a := hd asl;
		if (!first)
			out.putc(' ');
		out.puts(a);
		first = 0;
	}
	out.putc('\n');
	out.flush();
}

open(path: string): ref Sys->FD
{
	fd := sys->open(path, Bufio->OREAD);
	if (fd == nil) {
		sys->fprint(stderr, "tcs: cannot open %s: %r\n", path);
		raise "fail:open";
	}
	return fd;
}
