implement Filepat;

include "sys.m";
	sys: Sys;

include "readdir.m";
	rdir: Readdir;

include "filepat.m";

expand(pat: string): list of string
{
	if(sys == nil){
		sys = load Sys Sys->PATH;
	}
	if(rdir == nil){
		rdir = load Readdir Readdir->PATH;
	}
	(nil, elem) := sys->tokenize(pat, "/");
	if(elem == nil)
		return filepat1(pat, nil, 0);

	files: list of string;
	if(pat[0] == '/')
		files = "/" :: nil;

	while(elem != nil){
		files = filepat1(hd elem, files, tl elem!=nil);
		if(files == nil)
			break;
		elem = tl elem;
	}
	return files;
}

filepat1(pat: string, files: list of string, mustbedir: int): list of string
{
	if(files == nil)
		return filepatdir(pat, "", nil, mustbedir);

	# reverse list; will rebuild in forward order
	r: list of string;
	while(files != nil){
		r = hd files :: r;
		files = tl files;
	}
	files = r;

	nfiles: list of string = nil;
	while(files != nil){
		nfiles = filepatdir(pat, hd files, nfiles, mustbedir);
		files = tl files;
	}
	return nfiles;
}

filepatdir(pat: string, dir: string, files: list of string, mustbedir: int): list of string
{
	if(pat=="." || pat=="..") {
		if(dir=="/" || dir=="")
			files = (dir + pat) :: files;
		else
			files = (dir + "/" + pat) :: files;
		return files;
	}
	dirname := dir;
	if(dir == "")
		dirname = ".";
	# sort into descending order means resulting list will ascend
	(d, n) := rdir->init(dirname, rdir->NAME|rdir->DESCENDING|rdir->COMPACT);
	if(d == nil)
		return files;

	# suppress duplicates
	for(i:=1; i<n; i++)
		if(d[i-1].name == d[i].name){
			d[i-1:] = d[i:];
			n--;
			i--;
		}

	for(i=0; i<n; i++){
		if(match(pat, d[i].name) && (mustbedir==0 || (d[i].mode&Sys->DMDIR))){
			if(dir=="/" || dir=="")
				files = (dir + d[i].name) :: files;
			else
				files = (dir + "/" + d[i].name) :: files;
		}
	}
	return files;
}

match(pat, name: string): int
{
	n := 0;
	p := 0;
	while(p < len pat){
		r := pat[p++];
		case r{
		'*' =>
			pat = pat[p:];
			if(len pat==0)
				return 1;
			for(; n<=len name; n++)
				if(match(pat, name[n:]))
					return 1;
			return 0;
		'[' =>
			if(n == len name)
				return 0;
			s := name[n++];
			matched := 0;
			invert := 0;
			first := 1;
			esc: int;
			while(p < len pat){
				(p, r, esc) = char(pat, p);
				if(first && !esc && r=='^'){
					invert = 1;
					first = 0;
					continue;
				}
				first = 0;
				if(!esc && r==']')
					break;
				lo, hi: int;
				(p, lo, hi) = range(pat, p-1);
				if(lo<=s && s<=hi)
					matched = 1;
			}
			if(!(!esc && r==']') || invert==matched)
				return 0;
		'?' =>
			if(n==len name)
				return 0;
			n++;
		'\\' =>
			if(n==len name || p==len pat || pat[p++]!=name[n++])
				return 0;
		* =>
			if(n==len name || r!=name[n++])
				return 0;
		}
	}
	return n == len name;
}

# return character or range (a-z)
range(pat: string, p: int): (int, int, int)
{
	(q, lo, nil) := char(pat, p);
	(q1, hi, esc) := char(pat, q);
	if(!esc && hi=='-'){
		(q1, hi, nil) = char(pat, q1);
		return (q1, lo, hi);
	}
	return (q, lo, lo);
}

# return possibly backslash-escaped next character
char(pat: string, p: int): (int, int, int)
{
	if(p == len pat)
		return (p, 0, -1);
	r := pat[p++];
	if(p==len pat || r!='\\')
		return (p, r, 0);
	return (p+1, pat[p], 1);
}
