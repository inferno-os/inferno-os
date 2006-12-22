implement Xx;

include "sys.m";
include "draw.m";
include "bufio.m";

sys : Sys;
bufio : Bufio;

ORDWR, FD, open, read, write, seek, sprint, fprint, fildes, byte2char : import sys;
Iobuf : import bufio;

Xx : module {
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

prog := "x";
bin : ref Iobuf;

main(argv : list of string)
{
	afd, cfd, dfd : ref FD;
	i, id, seq : int;
	nf, n, plen : int;
	addr, aq0, aq1, matched : int;
	f, tf : array of File;
	buf, s : string;
	bbuf0 : array of byte;

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
		bbuf0 = array of byte f[i].addr;
		n = len bbuf0;
		if(write(afd, bbuf0, n)!=n || fprint(cfd, "limit=addr\n")<0){
			buf = sprint("%s:%s is invalid limit", f[i].name, f[i].addr);
			rerror(buf);
		}
		if(fprint(afd, "#%d", f[i].q0) < 0)
			rerror("can't set address");
		if(fprint(cfd, "dot=addr") < 0)
			rerror("can't unset dot");
		addr = f[i].q0-1;
		bbuf := array of byte hd tl argv;
		plen = len bbuf;
		matched = 0;
		# scan for matches
		for(;;){
			if(write(afd, bbuf, plen) != plen)
				break;
			seek(afd, big 0, 0);
			bbuf0 = array[2*12] of byte;
			if(read(afd, bbuf0, len bbuf0) != 2*12)
				rerror("reading address");
			buf = string bbuf0;
			bbuf0 = nil;
			aq0 = int buf;
			aq1 = int buf[12:];
			if(matched && aq1==aq0 && addr==aq1){	# repeated null match; advance
				matched = 0;
				addr++;
				if(addr > f[i].q1)
					break;
				if(fprint(afd, "#%d", addr) < 0)
					rerror("writing address");
				continue;
			}
			matched = 1;
			if(aq0<addr || aq0>=f[i].q1 || aq1>f[i].q1)
				break;
			addr = aq1;
			if(aq0 == aq1)
				fprint(stdout, "%s:#%d\n", f[i].name, aq0);
			else
				fprint(stdout, "%s:#%d,#%d\n", f[i].name, aq0, aq1);
		}
	}
	exit;
}
