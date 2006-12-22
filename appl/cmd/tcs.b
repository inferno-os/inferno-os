implement Tcs;

include "sys.m";
include "draw.m";
include "arg.m";
include "bufio.m";
include "convcs.m";

Tcs : module {
	init : fn (nil : ref Draw->Context, args : list of string);
};

sys : Sys;
convcs : Convcs;
bufio : Bufio;

Iobuf : import bufio;

stderr : ref Sys->FD;

usage()
{
	sys->fprint(stderr, "tcs [-C configfile] [-l] [-f ics] [-t ocs] file ...\n");
	raise "fail:usage";
}

init(nil : ref Draw->Context, args : list of string)
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
	lflag, vflag : int = 0;
	ics, ocs : string = "utf8";
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
			usage();
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
	
	stob : Stob;
	btos : Btos;
	(stob, err) = convcs->getstob(ocs);
	if (err != nil) {
		sys->fprint(stderr, "%s: %s\n", ocs, err);
		raise "fail:badarg";
	}
	(btos, err) = convcs->getbtos(ics);
	if (err != nil) {
		sys->fprint(stderr, "%s: %s\n", ics, err);
		raise "fail:badarg";
	}

	fd := sys->fildes(0);
	if (file != nil)
		fd = open(file);

	inbuf := array [Sys->ATOMICIO] of byte;
	start := 0;
	while (fd != nil) {
		btoss : Convcs->State = nil;
		stobs : Convcs->State = nil;

		while ((n := sys->read(fd, inbuf[start:], len inbuf - start)) > 0) {
			s := "";
			nc := 0;
			outbuf : array of byte = nil;
			(btoss, s, nc) = btos->btos(btoss, inbuf[0:n], -1);
			if (s != nil)
				(stobs, outbuf) = stob->stob(stobs, s);
			if (outbuf != nil) {
				out.write(outbuf, len outbuf);
			}
			# copy down unconverted part of buffer
			start = n - nc;
			if (start && nc)
				inbuf[:] = inbuf[nc:n];
		}

		out.flush();
		file = arg->arg();
		if (file == nil)
			break;
		fd = open(file);
	}
}

badmodule(s : string)
{
	sys->fprint(stderr, "cannot load module %s: %r\n", s);
	raise "fail:init";
}

dumpconvs(out : ref Iobuf, verbose : int)
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

dumpaliases(out : ref Iobuf, cs : string, verbose : int)
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

open(path : string) : ref Sys->FD
{
	fd := sys->open(path, Bufio->OREAD);
	if (fd == nil)
		sys->fprint(stderr, "cannot open %s: %r\n", path);
	return fd;
}
