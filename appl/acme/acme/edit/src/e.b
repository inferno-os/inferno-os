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

init(nil : ref Draw->Context, argl : list of string)
{
	sys = load Sys Sys->PATH;
	bufio = load Bufio Bufio->PATH;
	stdin = fildes(0);
	stdout = fildes(1);
	stderr = fildes(2);
	main(argl);
}

include "findfile.b";

prog := "e";

main(argv : list of string)
{
	afd, cfd : ref FD;
	i, id : int;
	buf : string;
	nf, n, lines, l0, l1 : int;
	f, tf : array of File;

	lines = 0;
	if(len argv>1 && hd tl argv == "-l"){
		lines = 1;
		argv = tl argv;
	}
	if(len argv < 2){
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

	# convert to character positions
	for(i=0; i<nf; i++){
		id = f[i].id;
		buf = sprint("/mnt/acme/%d/addr", id);
		afd = open(buf, ORDWR);
		if(afd == nil)
			rerror(buf);
		buf = sprint("/mnt/acme/%d/ctl", id);
		cfd = open(buf, ORDWR);
		if(cfd == nil)
			rerror(buf);
		if(write(cfd, array of byte "addr=dot\n", 9) != 9)
			rerror("setting address to dot");
		ab := array of byte f[i].addr;
		if(write(afd, ab, len ab) != len ab){
			fprint(stderr, "%s: %s:%s is invalid address\n", prog, f[i].name, f[i].addr);
			f[i].ok = 0;
			afd = nil;
			cfd = nil;
			continue;
		}
		seek(afd, big 0, 0);
		ab = array[24] of byte;
		if(read(afd, ab, len ab) != 2*12)
			rerror("reading address");
		afd = nil;
		cfd = nil;
		buf = string ab;
		ab = nil;
		f[i].q0 = int buf;
		f[i].q1 = int buf[12:];
		f[i].ok = 1;
	}

	# sort
	qsort(f, nf, FCMP);

	# print
	for(i=0; i<nf; i++){
		if(f[i].ok)
			if(lines){
				(l0, l1) = lineno(f[i]);
				if(l1 > l0)
					fprint(stdout, "%s:%d,%d\n", f[i].name, l0, l1);
				else
					fprint(stdout, "%s:%d\n", f[i].name, l0);
			}else{
				if(f[i].q1 > f[i].q0)
					fprint(stdout, "%s:#%d,#%d\n", f[i].name, f[i].q0, f[i].q1);
				else
					fprint(stdout, "%s:#%d\n", f[i].name, f[i].q0);
			}
	}
	exit;
}

lineno(f : File) : (int, int)
{
	b : ref Iobuf;
	n0, n1, q, r : int;
	buf : string;

	buf = sprint("/mnt/acme/%d/body", f.id);
	b = bufio->open(buf, bufio->OREAD);
	if(b == nil){
		fprint(stderr, "%s: can't open %s: %r\n", prog, buf);
		exit;
	}
	n0 = 1;
	n1 = 1;
	for(q=0; q<f.q1; q++){
		r = b.getc();
		if(r == bufio->EOF){
			fprint(stderr, "%s: early EOF on %s\n", prog, buf);
			exit;
		}
		if(r=='\n'){
			if(q < f.q0)
				n0++;
			if(q+1 < f.q1)
				n1++;
		}
	}
	b.close();
	return (n0, n1);
}
