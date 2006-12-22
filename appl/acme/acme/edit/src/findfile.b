File : adt {
	id : int;
	seq : int;
	ok : int;
	q0, q1 : int;
	name : string;
	addr : string;
};

BSCMP, SCMP, NCMP, FCMP : con iota;

indexfile := "/mnt/acme/index";

dfd: ref Sys->FD;
debug(s : string)
{
	if (dfd == nil)
		dfd = sys->create("/usr/jrf/acme/debugedit", Sys->OWRITE, 8r600);
	sys->fprint(dfd, "%s", s);
}

error(s : string)
{
	fprint(stderr, "%s: %s\n", prog, s);
	exit;
}

errors(s, t : string)
{
	fprint(stderr, "%s: %s %s\n", prog, s, t);
	exit;
}

rerror(s : string)
{
	fprint(stderr, "%s: %s: %r\n", prog, s);
	exit;
}

strcmp(s, t : string) : int
{
	if (s < t) return -1;
	if (s > t) return 1;
	return 0;
}

strstr(s, t : string) : int
{
	if (t == nil)
		return 0;
	n := len t;
	if (n > len s)
		return -1;
	e := len s - n;
	for (p := 0; p <= e; p++)
		if (s[p:p+n] == t)
			return p;
	return -1;
}

nrunes(s : array of byte, nb : int) : int
{
	i, n, r, b, ok : int;

	n = 0;
	for(i=0; i<nb; n++) {
		(r, b, ok) = byte2char(s, i);
		i += b;
	}
	return n;
}

index : ref Iobuf;

findfile(pat : string) : (int, array of File)
{
	line, pat1, pat2 : string;
	colon, blank : int;
	n : int;
	f : array of File;

	if(index == nil)
		index = bufio->open(indexfile, bufio->OREAD);
	else
		index.seek(big 0, 0);
	if(index == nil)
		rerror(indexfile);
	for(colon=0; colon < len pat && pat[colon]!=':'; colon++)
		;
	if (colon == len pat) {
		pat1 = pat;
		pat2 = ".";
	}
	else {
		pat1 = pat[0:colon];
		pat2 = pat[colon+1:];
	}
	n = 0;
	f = nil;
	while((line=index.gets('\n')) != nil){
		if(len line < 5*12)
			rerror("bad index file format");
		line = line[0:len line - 1];
		for(blank=5*12; blank < len line && line[blank]!=' '; blank++)
			;
		if (blank < len line)
			line = line[0:blank];
		if(strcmp(line[5*12:], pat1) == 0){
			# exact match: take that
			f = nil;	# should also free t->addr's
			f = array[1] of File;
			if(f == nil)
				rerror("out of memory");
			f[0].id = int line;
			f[0].name = line[5*12:];
			f[0].addr = pat2;
			n = 1;
			break;
		}
		if(strstr(line[5*12:], pat1) >= 0){
			# partial match: add to list
			off := f;
			f = array[n+1] of File;
			if(f == nil)
				rerror("out of memory");
			f[0:] = off[0:n];
			off = nil;
			f[n].id = int line;
			f[n].name = line[5*12:];
			f[n].addr = pat2;
			n++;
		}
	}
	return (n, f);
}

bscmp(a : File, b : File) : int
{
	return b.seq - a.seq;
}

scmp(a : File, b : File) : int
{
	return a.seq - b.seq;
}

ncmp(a : File, b : File) : int
{
	return strcmp(a.name, b.name);
}

fcmp(a : File, b : File) : int
{
	x : int;

	if (a.name < b.name)
		return -1;
	if (a.name > b.name)
		return 1;
	x = a.q0 - b.q0;
	if(x != 0)
		return x;
	return a.q1-b.q1;
}

gencmp(a : File, b : File, c : int) : int
{
	if (c == BSCMP)
		return bscmp(a, b);
	if (c == SCMP)
		return scmp(a, b);
	if (c == NCMP)
		return ncmp(a, b);
	if (c == FCMP)
		return fcmp(a, b);
	return 0;
}

qsort(a : array of File, n : int, c : int)
{
	i, j : int;
	t : File;

	while(n > 1) {
		i = n>>1;
		t = a[0]; a[0] = a[i]; a[i] = t;
		i = 0;
		j = n;
		for(;;) {
			do
				i++;
			while(i < n && gencmp(a[i], a[0], c) < 0);
			do
				j--;
			while(j > 0 && gencmp(a[j], a[0], c) > 0);
			if(j < i)
				break;
			t = a[i]; a[i] = a[j]; a[j] = t;
		}
		t = a[0]; a[0] = a[j]; a[j] = t;
		n = n-j-1;
		if(j >= n) {
			qsort(a, j, c);
			a = a[j+1:];
		} else {
			qsort(a[j+1:], n, c);
			n = j;
		}
	}
}