implement Cut;

#
# cut - cut selected fields/characters from lines
# Plan 9 / Inferno port
#

include "sys.m";
	sys: Sys;

include "draw.m";

include "bufio.m";
	bufio: Bufio;
	Iobuf: import bufio;

include "arg.m";
	arg: Arg;

include "string.m";
	str: String;

Cut: module
{
	init:	fn(nil: ref Draw->Context, nil: list of string);
};

Range: adt {
	lo:	int;	# 1-indexed, 0 means "from start"
	hi:	int;	# 1-indexed, 0 means "to end"
};

FIELDS, CHARS: con iota;

mode := FIELDS;
delim := '\t';
sflag := 0;
ranges: list of ref Range;
stderr: ref Sys->FD;

usage()
{
	sys->fprint(stderr, "usage: cut [-s] [-d delim] {-f | -c} list [file ...]\n");
	raise "fail:usage";
}

error(s: string)
{
	sys->fprint(stderr, "cut: %s\n", s);
	raise "fail:error";
}

init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	stderr = sys->fildes(2);
	bufio = load Bufio Bufio->PATH;
	str = load String String->PATH;
	arg = load Arg Arg->PATH;

	liststr: string;
	gotmode := 0;

	arg->init(args);
	while((c := arg->opt()) != 0)
		case c {
		'f' =>
			mode = FIELDS;
			gotmode = 1;
			liststr = arg->earg();
		'c' =>
			mode = CHARS;
			gotmode = 1;
			liststr = arg->earg();
		'd' =>
			s := arg->earg();
			if(len s != 1)
				error("delimiter must be a single character");
			delim = s[0];
		's' =>
			sflag = 1;
		'n' =>
			;	# no-op: Inferno is already UTF-8 native
		* =>
			usage();
		}

	if(!gotmode)
		usage();

	ranges = parselist(liststr);
	if(ranges == nil)
		error("empty list");

	args = arg->argv();
	ob := bufio->fopen(sys->fildes(1), Bufio->OWRITE);
	if(args == nil)
		process(bufio->fopen(sys->fildes(0), Bufio->OREAD), ob);
	else {
		for(; args != nil; args = tl args) {
			f := bufio->open(hd args, Bufio->OREAD);
			if(f == nil) {
				sys->fprint(stderr, "cut: %s: %r\n", hd args);
				continue;
			}
			process(f, ob);
		}
	}
	ob.flush();
}

# Parse a list specification: N, N-M, N-, -M, comma-separated
parselist(s: string): list of ref Range
{
	rl: list of ref Range;
	while(s != nil) {
		# find next comma-separated element
		elem: string;
		for(i := 0; i < len s; i++) {
			if(s[i] == ',') {
				elem = s[:i];
				s = s[i+1:];
				break;
			}
		}
		if(i == len s) {
			elem = s;
			s = nil;
		}

		if(elem == nil)
			error("empty list element");

		r := ref Range(0, 0);

		# check for dash
		dashpos := -1;
		for(j := 0; j < len elem; j++) {
			if(elem[j] == '-') {
				dashpos = j;
				break;
			}
		}

		if(dashpos < 0) {
			# single number
			(n, rest) := str->toint(elem, 10);
			if(rest != nil || n <= 0)
				error("bad list value: " + elem);
			r.lo = n;
			r.hi = n;
		} else if(dashpos == 0) {
			# -M
			(n, rest) := str->toint(elem[1:], 10);
			if(rest != nil || n <= 0)
				error("bad list value: " + elem);
			r.lo = 1;
			r.hi = n;
		} else if(dashpos == len elem - 1) {
			# N-
			(n, rest) := str->toint(elem[:dashpos], 10);
			if(rest != nil || n <= 0)
				error("bad list value: " + elem);
			r.lo = n;
			r.hi = 0;	# 0 means "to end"
		} else {
			# N-M
			(n1, rest1) := str->toint(elem[:dashpos], 10);
			(n2, rest2) := str->toint(elem[dashpos+1:], 10);
			if(rest1 != nil || rest2 != nil || n1 <= 0 || n2 <= 0)
				error("bad list value: " + elem);
			if(n1 > n2)
				error("bad range: " + elem);
			r.lo = n1;
			r.hi = n2;
		}
		rl = r :: rl;
	}

	# reverse
	rev: list of ref Range;
	for(; rl != nil; rl = tl rl)
		rev = hd rl :: rev;
	return rev;
}

# Check if position n (1-indexed) is selected by any range
inrange(n: int): int
{
	for(rl := ranges; rl != nil; rl = tl rl) {
		r := hd rl;
		if(r.hi == 0) {
			# open-ended: N-
			if(n >= r.lo)
				return 1;
		} else {
			if(n >= r.lo && n <= r.hi)
				return 1;
		}
	}
	return 0;
}

# Find the maximum hi value in ranges (0 if any range is open-ended)
maxrange(): int
{
	m := 0;
	for(rl := ranges; rl != nil; rl = tl rl) {
		r := hd rl;
		if(r.hi == 0)
			return 0;	# open-ended
		if(r.hi > m)
			m = r.hi;
	}
	return m;
}

process(f: ref Iobuf, ob: ref Iobuf)
{
	while((line := f.gets('\n')) != nil) {
		# strip trailing newline for processing
		hasnl := 0;
		if(len line > 0 && line[len line - 1] == '\n') {
			hasnl = 1;
			line = line[:len line - 1];
		}

		if(mode == CHARS)
			cutchars(line, ob);
		else
			cutfields(line, ob);

		if(hasnl)
			ob.putc('\n');
	}
}

cutchars(line: string, ob: ref Iobuf)
{
	for(i := 0; i < len line; i++) {
		if(inrange(i + 1))
			ob.putc(line[i]);
	}
}

cutfields(line: string, ob: ref Iobuf)
{
	# check if line contains delimiter
	hasdelim := 0;
	for(i := 0; i < len line; i++) {
		if(line[i] == delim) {
			hasdelim = 1;
			break;
		}
	}

	if(!hasdelim) {
		if(!sflag)
			ob.puts(line);
		return;
	}

	# split into fields preserving empty fields
	fields: list of string;
	nfields := 0;
	start := 0;
	for(i = 0; i <= len line; i++) {
		if(i == len line || line[i] == delim) {
			fields = line[start:i] :: fields;
			nfields++;
			start = i + 1;
		}
	}

	# reverse the field list
	rev: list of string;
	for(; fields != nil; fields = tl fields)
		rev = hd fields :: rev;

	# output selected fields with delimiter
	first := 1;
	n := 1;
	for(; rev != nil; rev = tl rev) {
		if(inrange(n)) {
			if(!first)
				ob.putc(delim);
			ob.puts(hd rev);
			first = 0;
		}
		n++;
	}

	# if any open-ended ranges extend past the line, we're done
}
