implement Pp;

include "sys.m";
include "draw.m";
include "bufio.m";

sys : Sys;
bufio : Bufio;

ORDWR, FD, open, read, write, seek, sprint, fprint, fildes, byte2char : import sys;
Iobuf : import bufio;

Pp : module {
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

prog := "p";
bin : ref Iobuf;

main(argv : list of string)
{
	afd, cfd, dfd : ref FD;
	i, id : int;
	m, nr, nf, n, nflag, seq : int;
	f, tf : array of File;
	buf, s : string;

	nflag = 0;
	if(len argv==2 && hd tl argv == "-n"){
		argv = tl argv;
		nflag = 1;
	}
	if(len argv != 1){
		fprint(stderr, "usage: %s [-n]\n", prog);
		exit;
	}
	
include "input.b";

	# sort back to original order
	qsort(f, nf, SCMP);

	# print
	id = -1;
	afd = nil;
	cfd = nil;
	dfd = nil;
	for(i=0; i<nf; i++){
		if(f[i].ok == 0)
			continue;
		if(f[i].id != id){
			if(id > 0){
				afd = cfd = dfd = nil;
			}
			id = f[i].id;
			buf = sprint("/mnt/acme/%d/addr", id);
			afd = open(buf, ORDWR);
			if(afd == nil)
				rerror(buf);
			buf = sprint("/mnt/acme/%d/data", id);
			dfd = open(buf, ORDWR);
			if(dfd == nil)
				rerror(buf);
			buf = sprint("/mnt/acme/%d/ctl", id);
			cfd = open(buf, ORDWR);
			if(cfd == nil)
				rerror(buf);
		}
		if(nflag){
			if(f[i].q1 > f[i].q0)
				fprint(stdout, "%s:#%d,#%d: ", f[i].name, f[i].q0, f[i].q1);
			else
				fprint(stdout, "%s:#%d: ", f[i].name, f[i].q0);
		}
		m = f[i].q0;
		while(m < f[i].q1){
			if(fprint(afd, "#%d", m) < 0){
				fprint(stderr, "%s: %s:%s is invalid address\n", prog, f[i].name, f[i].addr);
				continue;
			}
			bbuf := array[512] of byte;
			n = read(dfd, bbuf, len buf);
			nr = nrunes(bbuf, n);
			while(m+nr > f[i].q1){
				do; while(n>0 && (int bbuf[--n]&16rC0)==16r80);
				--nr;
			}
			if(n == 0)
				break;
			write(stdout, bbuf, n);
			m += nr;
		}
	}
	exit;
}
