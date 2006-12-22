implement Grep;

include "sys.m";
	sys: Sys;
	FD: import Sys;
	stdin, stderr, stdout: ref FD;

include "draw.m";
	Context: import Draw;

include "regex.m";
	regex: Regex;
	Re: import regex;

include "bufio.m";
	bufio: Bufio;
	Iobuf: import bufio;

include "arg.m";


Grep: module
{
	init:	fn(ctxt: ref Context, argv: list of string);
};

multi: int;
lflag, nflag, vflag, iflag, Lflag, sflag: int = 0;

badmodule(path: string)
{
	sys->fprint(stderr, "grep: cannot load %s: %r\n", path);
	raise "fail:bad module";
}

init(nil: ref Context, argv: list of string)
{
	sys = load Sys Sys->PATH;
	stdin = sys->fildes(0);
	stdout = sys->fildes(1);
	stderr = sys->fildes(2);

	arg := load Arg Arg->PATH;
	if (arg == nil)
		badmodule(Arg->PATH);

	regex = load Regex Regex->PATH;
	if(regex == nil)
		badmodule(Regex->PATH);

	bufio = load Bufio Bufio->PATH;
	if(bufio == nil)
		badmodule(Bufio->PATH);

	arg->init(argv);
	while ((opt := arg->opt()) != 0) {
		case opt {
		'l' =>
			lflag = 1;
		'n' =>
			nflag = 1;
		'v' =>
			vflag = 1;
		'i' =>
			iflag = 1;
		'L' =>
			Lflag = 1;
		's' =>
			sflag = 1;
		* =>
			usage();
		}
	}
	argv = arg->argv();
	arg = nil;

	if(argv == nil)
		usage();
	pattern := hd argv;
	argv = tl argv;
	if (iflag)
		pattern = tolower(pattern);
	(re, err) := regex->compile(pattern,0);
	if(re == nil) {
		sys->fprint(stderr, "grep: %s\n", err);
		raise "fail:bad regex";
	}

	matched := 0;
	if(argv == nil)
		matched = grep(re, bufio->fopen(stdin, Bufio->OREAD), "stdin");
	else {
		multi = (tl argv != nil);
		for (; argv != nil; argv = tl argv) {
			f := bufio->open(hd argv, Bufio->OREAD);
			if(f == nil)
				sys->fprint(stderr, "grep: cannot open %s: %r\n", hd argv);
			else
				matched += grep(re, f, hd argv);
		}
	}
	if (!matched)
		raise "fail:no matches";
}

usage()
{
	sys->fprint(stderr, "usage: grep [-lnviLs] pattern [file...]\n");
	raise "fail:usage";
}

grep(re: Re, f: ref Iobuf, file: string): int
{
	matched := 0;
	for(line := 1; ; line++) {
		s := t := f.gets('\n');
		if(s == nil)
			break;
		if (iflag)
			s = tolower(s);
		if((regex->executese(re, s, (0, len s-1), 1, 1) != nil) ^ vflag) {
			matched = 1;
			if(lflag || sflag) {
				if (!sflag)
					sys->print("%s\n", file);
				return matched;
			}
			if (!Lflag) {
				if(nflag)
					if(multi)
						sys->print("%s:%d: %s", file, line, t);
					else
						sys->print("%d:%s", line, t);
				else
					if(multi)
						sys->print("%s: %s", file, t);
					else
						sys->print("%s", t);
			}
		}
	}
	if (Lflag && matched == 0 && !sflag)
		sys->print("%s\n", file);
	return matched;
}

tolower(s: string): string
{
	for (i := 0; i < len s; i++) {
		c := s[i];
		if (c >= 'A' && c <= 'Z')
			s[i] = c - 'A' + 'a';
	}
	return s;
}
