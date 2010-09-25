implement Complete;

# Limbo translation by caerwyn of libcomplete on Plan 9
# Subject to the Lucent Public License 1.02

include "sys.m";
	sys: Sys;

include "string.m";
	str: String;

include "complete.m";

include "readdir.m";
	readdir: Readdir;

init()
{
	sys = load Sys Sys->PATH;
	str = load String String->PATH;
	readdir = load Readdir Readdir->PATH;
}


longestprefixlength(a, b: string, n: int): int
{
	for(i := 0; i < n; i++)
		if(a[i] != b[i])
			break;
	return i;
}

complete(dir, s: string): (ref Completion, string)
{
	if(str->splitl(s, "/").t1 != nil)
		return (nil, "slash character in name argument to complete()");

	(da, n) := readdir->init(dir, Readdir->COMPACT);
	if(n < 0)
		return (nil, sys->sprint("%r"));
	if(n == 0)
		return (nil, nil);


	c := ref Completion(0, 0, nil, 0, nil);

	name := array[n] of string;
	mode := array[n] of int;
	length := len s;
	nfile := 0;
	minlen := 1000000;
	for(i := 0; i < n; i++)
		if(str->prefix(s,da[i].name)){
			name[nfile] = da[i].name;
			mode[nfile] = da[i].mode;
			if(minlen > len da[i].name)
				minlen = len da[i].name;
			nfile++;
		}

	if(nfile > 0){
		# report interesting results
		# trim length back to longest common initial string
		for(i = 1; i < nfile; i++)
			minlen = longestprefixlength(name[0], name[i], minlen);

		c.complete = (nfile == 1);
		c.advance = c.complete || (minlen > length);
		c.str = name[0][length:minlen];
		if(c.complete){
			if(mode[0]&Sys->DMDIR)
				c.str[minlen++ - length] = '/';
			else
				c.str[minlen++ - length] = ' ';
		}
		c.nmatch = nfile;
	}else{
		# no match: return all names
		for(i = 0; i < n; i++){
			name[i] = da[i].name;
			mode[i] = da[i].mode;
		}
		nfile = n;
		c.nmatch = 0;
	}
	c.filename = name;
	for(i = 0; i < nfile; i++)
		if(mode[i] & Sys->DMDIR)
			c.filename[i] += "/";

	return (c, nil);
}
