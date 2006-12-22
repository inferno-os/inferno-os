implement Ii;

include "sys.m";
include "draw.m";
include "bufio.m";

sys : Sys;
bufio : Bufio;

ORDWR, FD, open, read, write, seek, sprint, fprint, fildes, byte2char : import sys;
Iobuf : import bufio;

Ii : module {
	init : fn(ctxt : ref Draw->Context, argl : list of string);
};

stdin, stderr : ref FD;

init(nil : ref Draw->Context, argl : list of string)
{
	sys = load Sys Sys->PATH;
	bufio = load Bufio Bufio->PATH;
	stdin = fildes(0);
	stderr = fildes(2);
	main(argl);
}

prog := "i";

include "findfile.b";

bin : ref Iobuf;

main(argv : list of string)
{
	afd, cfd, dfd : ref FD;
	i, id : int;
	nf, n, seq, rlen : int;
	f, tf : array of File;
	s, buf : string;

	if(len argv != 2){
		fprint(stderr, "usage: %s 'replacement'\n", prog);
		exit;
	}
	
include "input.b";

	# sort back to original order, backwards
	qsort(f, nf, BSCMP);

	# change 
	id = -1;
	afd = nil;
	cfd = nil;
	dfd = nil;
	ab := array of byte hd tl argv;
	rlen = len ab;
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
			if(write(cfd, array of byte "mark\nnomark\n", 12) != 12)
				rerror("setting nomark");
		}
		if(fprint(afd, "#%d", f[i].q0) < 0)
			rerror("writing address");
		if(write(dfd, ab, rlen) != rlen)
			rerror("writing replacement");
	}
	exit;
}
