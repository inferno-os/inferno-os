implement Ee;

include "sys.m";
include "draw.m";
include "bufio.m";

sys : Sys;
bufio : Bufio;

ORDWR, FD, open, read, write, seek, sprint, fprint, fildes, byte2char : import sys;
Iobuf : import bufio;

Ee : module {
	init : fn(ctxt : ref Draw->Context, argl : list of string);
};

stdin, stdout, stderr : ref FD;

init(ctxt : ref Draw->Context, argl : list of string)
{
	sys = load Sys Sys->PATH;
	bufio = load Bufio Bufio->PATH;
	stdin = fildes(0);
	stdout = fildes(1);
	stderr = fildes(2);
	main(argl);
}

File : adt {
	id : int;
	seq : int;
	ok : int;
	q0, q1 : int;
	name : string;
	addr : string;
};

BSCMP, SCMP, NCMP, FCMP : con iota;

indexfile := "/usr/jrf/tmp/index";

dfd: ref Sys->FD;
debug(s : string)
{
	if (dfd == nil)
		dfd = sys->create("/usr/jrf/acme/debugedit", Sys->OWRITE, 8r600);
	sys->fprint(dfd, "%s", s);
}

error(s : string)
{
debug(sys->sprint("error %s\n", s));
	fprint(stderr, "%s: %s\n", prog, s);
	exit;
}

errors(s, t : string)
{
debug(sys->sprint("errors %s %s\n", s, t));
	fprint(stderr, "%s: %s %s\n", prog, s, t);
	exit;
}

rerror(s : string)
{
debug(sys->sprint("rerror %s\n", s));
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
		index.seek(0, 0);
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

prog := "e";

main(argv : list of string)
{
	afd, cfd : ref FD;
	i, id : int;
	buf : string;
	nf, n, lines, l0, l1 : int;
	f, tf : array of File;

	if(len argv < 2){
debug(sys->sprint("usage\n"));
		fprint(stderr, "usage: %s 'file[:address]' ...\n", prog);
		exit;
	}
	nf = 0;
	f = nil;
	for(argv = tl argv; argv != nil; argv = tl argv){
		(n, tf) = findfile(hd argv);
		if(n == 0)
			errors("no files match pattern", hd argv);
		oldf := f;
		f = array[n+nf] of File;
		if(f == nil)
			rerror("out of memory");
		if (oldf != nil) {
			f[0:] = oldf[0:nf];
			oldf = nil;
		}
		f[nf:] = tf[0:n];
		nf += n;
		tf = nil;
	}
debug(sys->sprint("nf=%d\n", nf));
	# convert to character positions
	for(i=0; i<nf; i++){
		id = f[i].id;
		buf = sprint("/mnt/acme/%d/addr", id);
		# afd = open(buf, ORDWR);
		# if(afd == nil)
			# rerror(buf);
		buf = sprint("/mnt/acme/%d/ctl", id);
		# cfd = open(buf, ORDWR);
		# if(cfd == nil)
			# rerror(buf);
		if(0 && write(cfd, array of byte "addr=dot\n", 9) != 9)
			rerror("setting address to dot");
		ab := array of byte f[i].addr;
		if(0 && write(afd, ab, len ab) != len ab){
			fprint(stderr, "%s: %s:%s is invalid address\n", prog, f[i].name, f[i].addr);
			f[i].ok = 0;
			afd = nil;
			cfd = nil;
			continue;
		}
		# seek(afd, 0, 0);
		ab = array[24] of byte;
		if(0 && read(afd, ab, len ab) != 2*12)
			rerror("reading address");
		afd = nil;
		cfd = nil;
		# buf = string ab;
		ab = nil;
		f[i].q0 = 0; 	# int buf;
		f[i].q1 = 5;		# int buf[12:];
		f[i].ok = 1;
debug(sys->sprint("q0=%d q1=%d\n", f[i].q0, f[i].q1));
	}

	# sort
	# qsort(f, nf, FCMP);

	# print
	for(i=0; i<nf; i++){
		if(f[i].ok)
			{
				if(f[i].q1 > f[i].q0)
					fprint(stdout, "%s:#%d,#%d\n", f[i].name, f[i].q0, f[i].q1);
				else
					fprint(stdout, "%s:#%d\n", f[i].name, f[i].q0);
			}
	}
debug("e exiting\n");
	exit;
}