implement Pipe;

include "sys.m";
include "draw.m";
include "bufio.m";
include "sh.m";

sys : Sys;
bufio : Bufio;

UTFmax, ORDWR, NEWFD, FD, open, read, write, seek, sprint, fprint, fildes, byte2char, pipe, dup, pctl : import sys;
Iobuf : import bufio;

Pipe : module {
	init : fn(ctxt : ref Draw->Context, argl : list of string);
};

stdin, stderr : ref FD;
pipectxt : ref Draw->Context;

init(ctxt : ref Draw->Context, argl : list of string)
{
	pipectxt = ctxt;
	sys = load Sys Sys->PATH;
	bufio = load Bufio Bufio->PATH;
	stdin = fildes(0);
	stderr = fildes(2);
	main(argl);
}

include "findfile.b";

prog := "pipe";
bin : ref Iobuf;

main(argv : list of string)
{
	afd, dfd, cfd : ref FD;
	nf, nc, nr, npart : int;
	p1, p2 : array of ref FD;
	i, n, id, seq : int;
	buf : string;
	tmp, data : array of byte;
	s : string;
	r, s0 : int;
	f, tf : array of File;
	q, q0, q1 : int;
	cpid : chan of int;
	w, ok : int;

	if(len argv < 2){
		fprint(stderr, "usage: pipe command\n");
		exit;
	}

include "input.b";

	# sort back to original order
	qsort(f, nf, SCMP);

	# pipe
	id = -1;
	afd = nil;
	cfd = nil;
	dfd = nil;
	tmp = array[8192+UTFmax] of byte;
	if(tmp == nil)
		error("malloc");
	cpid = chan of int;
	for(i=0; i<nf; i++){
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

		if(fprint(afd, "#%ud", f[i].q0) < 0)
			rerror("writing address");

		q0 = f[i].q0;
		q1 = f[i].q1;
		# suck up data
		data = array[(q1-q0)*UTFmax+1] of byte;
		if(data == nil)
			error("malloc failed\n");
		s0 = 0;
		q = q0;
		bbuf := array[12] of byte;
		while(q < q1){
			nc = read(dfd, data[s0:], (q1-q)*UTFmax);
			if(nc <= 0)
				error("read error from acme");
			seek(afd, big 0, 0);
			if(read(afd, bbuf, 12) != 12)
				rerror("reading address");
			q = int string bbuf;
			s0 += nc;
		}
		bbuf = nil;
		s0 = 0;
		for(nr=0; nr<q1-q0; nr++) {
			(r, w, ok) = byte2char(data, s0);
			s0 += w;
		}

		p1 = array[2] of ref FD;
		p2 = array[2] of ref FD;
		if(pipe(p1)<0 || pipe(p2)<0)
			error("pipe");

		spawn run(tl argv, p1[0], p2[1], cpid);
		<-cpid;
		p1[0] = nil;
		p2[1] = nil;

		spawn send(data, s0, p1[1]);
		p1[1] = nil;

		# put back data
		if(fprint(afd, "#%d,#%d", q0, q1) < 0)
			rerror("writing address");

		npart = 0;
		q1 = q0;
		while((nc = read(p2[0], tmp[npart:], 8192)) > 0){
			nc += npart;
			s0 = 0;
			while(s0 <= nc-UTFmax){
				(r, w, ok) = byte2char(tmp, s0);
				s0 += w;
				q1++;
			}
			if(s0 > 0)
				if(write(dfd, tmp, s0) != s0)
					error("write error to acme");
			npart = nc - s0;
			tmp[0:] = tmp[s0:s0+npart];
		}
		p2[0] = nil;
		if(npart){
			s0 = 0;
			while(s0 < npart){
				(r, w, ok) = byte2char(tmp, s0);
				s0 += w;
				q1++;
			}
			if(write(dfd, tmp, npart) != npart)
				error("write error to acme");
		}
		if(fprint(afd, "#%d,#%d", q0, q1) < 0)
			rerror("writing address");
		if(fprint(cfd, "dot=addr\n") < 0)
			rerror("writing dot");
		data = nil;
	}
}

run(argv : list of string, p1, p2 : ref FD, c : chan of int)
{
	pctl(NEWFD, 0::1::2::p1.fd::p2.fd::nil);
	dup(p1.fd, 0);
	dup(p2.fd, 1);
	c <-= pctl(0, nil);
	exec(hd argv, argv);
	fprint(stderr, "can't exec");
	exit;
}

send(buf : array of byte, nbuf : int, fd : ref FD)
{
	if(write(fd, buf, nbuf) != nbuf)
		error("write error to process");
	fd = nil;
}

exec(cmd : string, argl : list of string)
{
	file := cmd;
	if(len file<4 || file[len file-4:]!=".dis")
		file += ".dis";

	c := load Command file;
	if(c == nil) {
		err := sys->sprint("%r");
		if(file[0]!='/' && file[0:2]!="./"){
			c = load Command "/dis/"+file;
			if(c == nil)
				err = sys->sprint("%r");
		}
		if(c == nil){
			sys->fprint(stderr, "%s: %s\n", cmd, err);
			return;
		}
	}

	c->init(pipectxt, argl);
}