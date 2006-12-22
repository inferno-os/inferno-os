implement Gg;

include "sys.m";
include "draw.m";
include "bufio.m";

sys : Sys;
bufio : Bufio;

ORDWR, FD, open, read, write, seek, sprint, fprint, fildes, byte2char : import sys;
Iobuf : import bufio;

Gg : module {
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

prog := "g";

include "findfile.b";

bin : ref Iobuf;

main(argv : list of string)
{
	afd, cfd, dfd : ref FD;
	i, id, seq : int;
	nf, n, plen : int;
	f, tf : array of File;
	buf, s : string;

	if(len argv!=2 || len hd tl argv==0 || (hd tl argv)[0]!='/'){
		fprint(stderr, "usage: %s '/regexp/'\n", prog);
		exit;
	}

include "input.b";

	# execute regexp
	id = -1;
	afd = nil;
	dfd = nil;
	cfd = nil;
	bufb := array of byte hd tl argv;
	plen = len bufb;
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
			buf = sprint("/mnt/acme/%d/ctl", id);
			cfd = open(buf, ORDWR);
			if(cfd == nil)
				rerror(buf);
			buf = sprint("/mnt/acme/%d/data", id);
			dfd = open(buf, ORDWR);
			if(dfd == nil)
				rerror(buf);
		}
		ab := array of byte f[i].addr;
		n = len ab;
		if(write(afd, ab, n)!=n || fprint(cfd, "limit=addr\n")<0){
			buf = sprint("%s:%s is invalid limit", f[i].name, f[i].addr);
			rerror(buf);
		}
		if(fprint(afd, "#%d", f[i].q0) < 0)
			rerror("can't set dot");
		# look for match
		if(write(afd, bufb, plen) == plen){
			if(f[i].q0 == f[i].q1)
				fprint(stdout, "%s:#%d\n", f[i].name, f[i].q0);
			else
				fprint(stdout, "%s:#%d,#%d\n", f[i].name, f[i].q0, f[i].q1);
		}
	}
	exit;
}
