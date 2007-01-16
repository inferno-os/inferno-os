implement Man;

include "sys.m";
	sys: Sys;
include "filepat.m";
include "bufio.m";
include "man.m";

MANPATH: con "/man/";
PATHDEPTH: con 1;

indices: list of (string, list of (string, string));

init()
{
	sys = load Sys Sys->PATH;
}

loadsections(scanlist: list of string): string
{
	sys = load Sys Sys->PATH;
	bufio := load Bufio Bufio->PATH;
	Iobuf: import bufio;

	if (bufio == nil)
		return sys->sprint("cannot load %s: %r", Bufio->PATH);

	indexpaths: list of string;
	if (scanlist == nil) {
		filepat := load Filepat Filepat->PATH;
		if (filepat == nil)
			return sys->sprint("cannot load %s: %r", Filepat->PATH);

		indexpaths = filepat->expand(MANPATH + "[0-9]*/INDEX");
		if (indexpaths == nil)
			return sys->sprint("cannot find man pages");
	} else {
		for (; scanlist != nil; scanlist = tl scanlist)
			indexpaths = MANPATH + string hd scanlist + "/INDEX" :: indexpaths;
		indexpaths = sortuniq(indexpaths);
	}

	sections: list of string;
	for (; indexpaths != nil; indexpaths = tl indexpaths) {
		path := hd indexpaths;
		(nil, toks) := sys->tokenize(path, "/");
		for (d := 0; d < PATHDEPTH; d++)
			toks = tl toks;
		sections = hd toks :: sections;
	}

	for (sl := sections; sl != nil; sl = tl sl) {
		section := hd sl;
		path := MANPATH + string section + "/INDEX";
		iob := bufio->open(path, Sys->OREAD);
		if (iob == nil)
			continue;
		pairs: list of (string, string) = nil;
		
		while((s := iob.gets('\n')) != nil) {
			if (s[len s - 1] == '\n')
				s = s[0:len s - 1];
			(n, toks) := sys->tokenize(s, " ");
			if (n != 2)
				continue;
			pairs = (hd toks, hd tl toks) :: pairs;
		}
		iob.close();
		indices = (section, pairs) :: indices;
	}
	return nil;
}

getfiles(sections: list of string, keys: list of string): list of (int, string, string)
{
	ixl: list of (string, list of (string, string));

	if (sections == nil)
		ixl = indices;
	else {
		for (; sections != nil; sections = tl sections) {
			section := hd sections;
			for (il := indices; il != nil; il = tl il) {
				(s, mapl) := hd il;
				if (s == section) {
					ixl = (s, mapl) :: ixl;
					break;
				}
			}
		}
	}
	paths: list of (int, string, string);
	for(keyl := keys; keyl != nil; keyl = tl keyl){
		for (; ixl != nil; ixl = tl ixl) {
			for ((s, mapl) := hd ixl; mapl != nil; mapl = tl mapl) {
				(kw, file) := hd mapl;
				if (hd keyl == kw) {
					p := MANPATH + s + "/" + file;
					paths = (int s, kw, p) :: paths;
				}
			}
			# allow files not in the index
			if(paths == nil || (hd paths).t0 != int s || (hd paths).t1 != hd keyl){
				p := MANPATH + string s + "/" + hd keyl;
				if(sys->stat(p).t0 != -1)
					paths = (int s, hd keyl, p) :: paths;
			}
		}
	}
	return paths;
}

sortuniq(strlist: list of string): list of string
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
	r: list of string;
	prev := "";
	for (i = 0; i < len strs; i++) {
		if (strs[i] != prev) {
			r = strs[i] :: r;
			prev = strs[i];
		}
	}
	return r;
}
