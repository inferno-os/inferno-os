implement Lookman;
include "sys.m";
include "bufio.m";
include "draw.m";


Lookman : module {
	init : fn (ctxt : ref Draw->Context, argv : list of string);
};

sys : Sys;
bufio : Bufio;
Iobuf : import bufio;

ctype := array [256] of { * => byte 0 };

MANINDEX : con "/man/index";

init(nil : ref Draw->Context, argv : list of string)
{
	sys = load Sys Sys->PATH;
	bufio = load Bufio Bufio->PATH;

	if (bufio == nil)
		raise "init:fail";

	# setup our char conversion table
	# map upper-case to lower-case
	for (i := 'A'; i <= 'Z'; i++)
		ctype[i] = byte ((i - 'A') + 'a');

	# only allow the following chars
	okchars := "abcdefghijklmnopqrstuvwxyz0123456789+.:½ ";
	for (i = 0; i < len okchars; i++) {
		ch := okchars[i];
		ctype[ch] = byte ch;
	}

	stdout := bufio->fopen(sys->fildes(1), Sys->OWRITE);

	argv = tl argv;
	paths := lookup(argv);
	for (; paths != nil; paths = tl paths)
		stdout.puts(sys->sprint("%s\n", hd paths));
	stdout.flush();
}

lookup(words : list of string) : list of string
{
	# open the index file
	manindex := bufio->open(MANINDEX, Sys->OREAD);
	if (manindex == nil) {
		sys->print("cannot open %s: %r\n", MANINDEX);
		return nil;
	}

	# convert to lower-case and discard funny chars
	keywords : list of string;
	for (; words != nil; words = tl words) {
		word := hd words;
		kw := "";
		for (i := 0; i < len word; i++) {
			ch := word[i];
			if (ch < len ctype && ctype[ch] != byte 0)
				kw[len kw] = int ctype[ch];
		}
		if (kw != "")
			keywords = kw :: keywords;
	}

	if (keywords == nil)
		return nil;

	keywords = sortuniq(keywords);
	matches : list of list of string;

	for (; keywords != nil; keywords = tl keywords) {
		kw := hd keywords;
		matchlist := look(manindex, '\t', kw);
		pathlist : list of string = nil;
		for (; matchlist != nil; matchlist = tl matchlist) {
			line := hd matchlist;
			(n, toks) := sys->tokenize(line, "\t");
			if (n != 2)
				continue;
			pathlist = hd tl toks :: pathlist;
		}
		if (pathlist != nil)
			matches = pathlist :: matches;
	}

	return intersect(matches);
}

getentry(iob : ref Iobuf) : (string, string)
{
	while ((s := iob.gets('\n')) != nil) {
		if (s[len s -1] == '\n')
			s = s[0:len s -1];
		if (s == nil)
			continue;
		(n, toks) := sys->tokenize(s, "\t");
		if (n != 2)
			continue;
		return (hd toks, hd tl toks);
	}
	return (nil, nil);
}

sortuniq(strlist : list of string) : list of string
{
	strs := array [len strlist] of string;
	for (i := 0; strlist != nil; (i, strlist) = (i+1, tl strlist))
		strs[i] = hd strlist;

	# simple sort (greatest first)
	for (i = 0; i < len strs - 1; i++) {
		for (j := i+1; j < len strs; j++)
			if (strs[i] < strs[j])
				(strs[i], strs[j]) = (strs[j], strs[i]);
	}

	# construct list (result is ascending)
	r : list of string;
	prev := "";
	for (i = 0; i < len strs; i++) {
		if (strs[i] != prev) {
			r = strs[i] :: r;
			prev = strs[i];
		}
	}
	return r;
}

intersect(strlists : list of list of string) : list of string
{
	if (strlists == nil)
		return nil;

	okl := hd strlists;
	for (strlists = tl strlists; okl != nil && strlists != nil; strlists = tl strlists) {
		find := hd strlists;
		found : list of string = nil;
		for (; okl != nil; okl = tl okl) {
			ok := hd okl;
			for (scanl := find; scanl != nil; scanl = tl scanl) {
				scan := hd scanl;
				if (scan == ok) {
					found = ok :: found;
					break;
				}
			}
		}
		okl = found;
	}
	return sortuniq(okl);
}

# binary search for key in f.
# based on Plan 9 look.c
#
look(f: ref Iobuf, sep: int, key: string): list of string
{
	bot := mid := 0;
	top := int f.seek(big 0, Sys->SEEKEND);
	key = canon(key, sep);

	for (;;) {
		mid = (top + bot) / 2;
		f.seek(big mid, Sys->SEEKSTART);
		c: int;
		do {
			c = f.getb();
			mid++;
		} while (c != Bufio->EOF && c != Bufio->ERROR && c != '\n');
		(entry, eof) := getword(f);
		if (entry == nil && eof)
			break;
		entry = canon(entry, sep);
		case comparewords(key, entry) {
		-2 or -1 or 0 =>
			if (top <= mid)
				break;
			top = mid;
			continue;
		1 or 2 =>
			bot = mid;
			continue;
		}
		break;
	}
	matchlist : list of string;
	f.seek(big bot, Sys->SEEKSTART);
	for (;;) {
		(entry, eof) := getword(f);
		if (entry == nil && eof)
			return matchlist;
		word := canon(entry, sep);
		case comparewords(key, word) {
		-1 or 0 =>
			matchlist = entry :: matchlist;
			continue;
		1 or 2 =>
			continue;
		}
		break;
	}
	return matchlist;
}

comparewords(s, t: string): int
{
	if (s == t)
		return 0;
	i := 0;
	for (; i < len s && i < len t && s[i] == t[i]; i++)
		;
	if (i >= len s)
		return -1;
	if (i >= len t)
		return 1;
	if (s[i] < t[i])
		return -2;
	return 2;
}

getword(f: ref Iobuf): (string, int)
{
	ret := "";
	for (;;) {
		c := f.getc();
		if (c == Bufio->EOF || c == Bufio->ERROR)
			return (ret, 0);
		if (c == '\n')
			break;
		ret[len ret] = c;
	}
	return (ret, 1);
}

canon(s: string, sep: int): string
{
	if (sep < 0)
		return s;
	i := 0;
	for (; i < len s; i++)
		if (s[i] == sep)
			break;
	return s[0:i];
}
