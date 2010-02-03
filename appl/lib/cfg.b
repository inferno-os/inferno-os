implement Cfg;

include "sys.m";
include "bufio.m";
include "cfg.m";

sys : Sys;
bufio : Bufio;

Iobuf : import bufio;
ENOMOD : con "cannot load module";
EBADPATH : con "bad path";


init(path : string) : string
{
	sys = load Sys Sys->PATH;
	bufio = load Bufio Bufio->PATH;
	if (bufio == nil)
		return sys->sprint("%s: %r", ENOMOD);

	iob := bufio->open(path, Sys->OREAD);
	if (iob == nil)
		return sys->sprint("%s: %r", EBADPATH);

	# parse the config file
	r : list of ref Tuple;
	lnum := 0;
	rlist : list of list of ref Tuple;

	while ((line := iob.gets('\n')) != nil) {
		lnum++;
		(tuple, err) := parseline(line, lnum);
		if (err != nil)
			return sys->sprint("%s:%d: %s", path, lnum, err);

		if (tuple == nil)
			continue;
		if (line[0] != ' ' && line[0] != '\t') {
			# start of a new record
			if (r != nil)
				rlist = r :: rlist;
			r = nil;
		}
		r = tuple :: r;
	}
	if (r != nil)
		rlist = r :: rlist;
	for (; rlist != nil; rlist = tl rlist)
		insert(hd rlist);
	return nil;
}

parseline(s : string, lnum : int) : (ref Tuple, string)
{
	attrs : list of Attr;
	quote := 0;
	word := "";
	lastword := "";
	name := "";

loop:
	for (i := 0 ; i < len s; i++) {
		if (quote) {
			if (s[i] == quote) {
				if (i + 1 < len s && s[i+1] == quote) {
					word[len word] = quote;
					i++;
				} else {
					quote = 0;
					continue;
				}
			} else
				word[len word] = s[i];
			continue;
		}
		case s[i] {
		'\'' or '\"' =>
			quote = s[i];
			continue;
		'#' =>
			break loop;
		' ' or '\t' or '\n' or '\r' =>
			if (word == nil)
				continue;
			if (lastword != nil) {
				# lastword space word space
				attrs = Attr(lastword, nil) :: attrs;
			}
			lastword = word;
			word = nil;

			if (name != nil) {
				# name = lastword space
				attrs = Attr(name, lastword) :: attrs;
				name = lastword = nil;
			}
		'=' =>
			if (lastword == nil) {
				# word=
				lastword = word;
				word = nil;
			}
			if (word != nil) {
				# lastword word=
				attrs = Attr(lastword, nil) :: attrs;
				lastword = word;
				word = nil;
			}
			if (lastword == nil)
				return (nil, "empty name");
			name = lastword;
			lastword = nil;
		* =>
			word[len word] = s[i];
		}
	}
	if (quote)
		return (nil, "missing quote");

	if (lastword == nil) {
		lastword = word;
		word = nil;
	}

	if (name == nil) {
		name = lastword;
		lastword = nil;
	}

	if (name != nil)
		attrs = Attr(name, lastword) :: attrs;

	if (attrs == nil)
		return (nil, nil);

	fattrs : list of Attr;
	for (; attrs != nil; attrs = tl attrs)
		fattrs = hd attrs :: fattrs;
	return (ref Tuple(lnum, fattrs), nil);
}

lookup(name : string) : list of (string, ref Record)
{
	l := buckets[hash(name)];
	for (; l != nil; l = tl l) {
		hr := hd l;
		if (hr.name != name)
			continue;
		return hr.vrecs;
	}
	return nil;
}

Record.lookup(r : self ref Record, name : string) : (string, ref Tuple)
{
	for (ts := r.tuples; ts != nil; ts = tl ts) {
		t := hd ts;
		for (as := t.attrs; as != nil; as = tl as) {
			a := hd as;
			if (a.name == name)
				return (a.value, t);
		}
	}
	return (nil, nil);
}

Tuple.lookup(t : self ref Tuple, name : string) : string
{
	for (as := t.attrs; as != nil; as = tl as) {
		a := hd as;
		if (a.name == name)
			return a.value;
	}
	return nil;
}

reset()
{
	keynames = nil;
	buckets = array[HSIZE+1] of list of ref HRecord;
}

# Record hash table
HRecord : adt {
	name : string;
	vrecs : list of (string, ref Record);
};

keynames : list of string;

HSIZE : con 16rff;	# must be (2^n)-1 due to hash() defn
buckets := array [HSIZE+1] of list of ref HRecord;

hash(name : string) : int
{
	# maybe use hashPJW?
	h := 0;
	for (i := 0; i < len name; i++)
		h = (h + name[i]) & HSIZE;
	return h;
}

insert(rtups : list of ref Tuple) {
	# tuple list is currently in reverse order
	ftups : list of ref Tuple;
	for (; rtups != nil; rtups = tl rtups)
		ftups = hd rtups :: ftups;
	
	maintuple := hd ftups;
	mainattr := hd maintuple.attrs;
	name := mainattr.name;
	value := mainattr.value;

	# does name already exist?
	hr : ref HRecord;
	h := hash(name);
	l := buckets[h];
	for (; l != nil; l = tl l) {
		hr = hd l;
		if (hr.name == name)
			break;
	}
	if (l == nil) {
		keynames = name :: keynames;
		buckets[h] = ref HRecord(name, (value, ref Record(ftups))::nil) :: buckets[h];
	} else
		hr.vrecs = (value, ref Record(ftups)) :: hr.vrecs;
}

getkeys() : list of string
{
	return keynames;
}
