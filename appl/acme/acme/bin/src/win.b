implement Win;

include "sys.m";
include "draw.m";
include "workdir.m";
include "sh.m";
include "env.m";

sys : Sys;
workdir : Workdir;
env: Env;

OREAD, OWRITE, ORDWR, FORKNS, FORKENV, FORKFD, NEWPGRP, MREPL, FD, UTFmax, pctl, open, read, write, fprint, sprint, fildes, bind, dup, byte2char, utfbytes : import sys;

Win : module {
	init : fn(ctxt : ref Draw->Context, argl : list of string);
};

Runeself : con 16r80;

PNPROC, PNGROUP : con iota;

stdout, stderr : ref FD;

drawctxt : ref Draw->Context;
finish : chan of int;

Lock : adt {
		c : chan of int;

		init : fn() : ref Lock;
		lock : fn(l : self ref Lock);
		unlock : fn(l : self ref Lock);
};

init(ctxt : ref Draw->Context, argl : list of string)
{
	sys = load Sys Sys->PATH;
	workdir = load Workdir Workdir->PATH;
	env = load Env Env->PATH;
	drawctxt = ctxt;
	stdout = fildes(1);
	stderr = fildes(2);
	debuginit();
	finish = chan[1] of int;
	spawn main(argl);
	<-finish;
}

Lock.init() : ref Lock
{
	return ref Lock(chan[1] of int);
}

Lock.lock(l : self ref Lock)
{
	l.c <-= 1;
}

Lock.unlock(l : self ref Lock)
{
	<-l.c;
}

dlock : ref Lock;
debfd : ref Sys->FD;

debuginit()
{
	# debfd = sys->create("./debugwin", Sys->OWRITE, 8r600);
	# dlock = Lock.init();
}

debugpr(nil : string)
{
	# fprint(debfd, "%s", s);
}

debug(nil : string)
{
	# dlock.lock();
	# fprint(debfd, "%s", s);	
	# dlock.unlock();
}

exec(cmd : string, argl : list of string)
{
	file := cmd;
	if(len file<4 || file[len file-4:]!=".dis")
		file += ".dis";

	c := load Command file;
	if(c == nil) {
		err := sprint("%r");
		if(file[0]!='/' && file[0:2]!="./"){
			c = load Command "/dis/"+file;
			if(c == nil)
				err = sprint("%r");
		}
		if(c == nil){
			fprint(stderr, "%s: %s\n", cmd, err);
			return;
		}
	}
	c->init(drawctxt, argl);
}

postnote(t : int, pid : int, note : string) : int
{
	# fd := open("/prog/" + string pid + "/ctl", OWRITE);
	fd := open("#p/" + string pid + "/ctl", OWRITE);
	if (fd == nil)
		return -1;
	if (t == PNGROUP)
		note += "grp";
	fprint(fd, "%s", note);

	fd = nil;
	return 0;
}

sysname(): string
{
	fd := sys->open("#c/sysname", sys->OREAD);
	if(fd == nil)
		return nil;
	buf := array[128] of byte;
	n := sys->read(fd, buf, len buf);
	if(n < 0) 
		return nil;
	return string buf[0:n];
}

EVENTSIZE : con	256;

Event : adt {
	c1 : int;
	c2 : int;
	q0 : int;
	q1 : int;
	flag : int;
	nb : int;
	nr : int;
	b : array of byte;
	r : array of int;
};

blank : ref Event;

pid : int;
# pgrpfd : ref FD;
parentpid : int;

typing : array of byte;
ntypeb : int;
ntyper : int;
ntypebreak : int;

Q : adt {
	l : ref Lock;
	p : int;
	k : int;
};

q : Q;

newevent(n : int) : ref Event
{
	e := ref Event;
	e.b = array[n*UTFmax+1] of byte;
	e.r = array[n+1] of int;
	return e;
}

main(argv : list of string)
{
	program : list of string;
	fd, ctlfd, eventfd, addrfd, datafd : ref FD;
	id : int;
	c : chan of int;
	name : string;

	sys->pctl(Sys->NEWPGRP, nil);
	q.l = Lock.init();
	blank = newevent(2);
	blank.c1 = 'M';
	blank.c2 = 'X';
	blank.q0 = blank.q1 = blank.flag = 0;
	blank.nb = blank.nr = 1;
	blank.b[0] = byte ' ';
	blank.b[1] = byte 0;
	blank.r[0] = ' ';
	blank.r[1] = 0;
	pctl(FORKNS|NEWPGRP, nil);
	parentpid = pctl(0, nil);
	program = nil;
	if(tl argv != nil)
		program = tl argv;
	name = nil;
	if(program == nil){
		# program = "-i" :: program;
		program = "sh" :: program;
		name = sysname();
	}
	if(name == nil){
		prog := hd program;
		for (n := len prog - 1; n >= 0; n--)
			if (prog[n] == '/')
				break;
		if(n >= 0)
			name = prog[n+1:];
		else
			name = prog;
		argl := tl argv;
		if (argl != nil) {
			for(argl = tl argl; argl != nil && len(name)+1+len(hd argl)<16; argl = tl argl)
				name += "_" + hd argl;
		}
	}
	if(bind("#|", "/dev/acme", MREPL) < 0)
		error("pipe");
	ctlfd = open("/chan/new/ctl", ORDWR);
	buf := array[12] of byte;
	if(ctlfd==nil || read(ctlfd, buf, 12)!=12)
		error("ctl");
	id = int string buf;
	buf = nil;
	env->setenv("acmewin", string id);
	b := sprint("/chan/%d/tag", id);
	fd = open(b, OWRITE);
	write(fd, array of byte " Send Delete", 12);
	fd = nil;
	b = sprint("/chan/%d/event", id);
	eventfd = open(b, ORDWR);
	b = sprint("/chan/%d/addr", id);
	addrfd = open(b, ORDWR);
	b = sprint("/chan/%d/data", id);
	datafd = open(b, ORDWR); # OCEXEC
	if(eventfd==nil || addrfd==nil || datafd==nil)
		error("data files");
	c = chan of int;
	spawn run(program, id, c);
	pid = <-c;
	# b = sprint("/prog/%d/notepg", pid);
	# pgrpfd = open(b, OWRITE); # OCEXEC
	# if(pgrpfd == nil)
	#	fprint(stdout, "warning: win can't open notepg: %r\n");
	c <-= 1;
	fd = open("/dev/acme/data", ORDWR);
	if(fd == nil)
		error("/dev/acme/data");
	wd  := workdir->init();
	# b = sprint("name %s/-%s\n0\n", wd, name);
	b = sprint("name %s/-%s\n", wd, name);
	ab := array of byte b;
	write(ctlfd, ab, len ab);
	b = sprint("dumpdir %s/\n", wd);
	ab = array of byte b;
	write(ctlfd, ab, len ab);
	b = sprint("dump %s\n", onestring(argv));
	ab = array of byte b;
	write(ctlfd, ab, len ab);
	ab = nil;
	spawn stdinx(fd, ctlfd, eventfd, addrfd, datafd);
	stdoutx(fd, addrfd, datafd);
}

run(argv : list of string, id : int, c : chan of int)
{
	fd0, fd1 : ref FD;

	pctl(FORKENV|FORKFD|NEWPGRP, nil);	# had RFMEM
	c <-= pctl(0, nil);
	<-c;
	pctl(FORKNS, nil);
	if(bind("/dev/acme/data1", "/dev/cons", MREPL) < 0){
		fprint(stderr, "can't bind /dev/cons: %r\n");
		exit;
	}
	fd0 = open("/dev/cons", OREAD);
	fd1 = open("/dev/cons", OWRITE);
	if(fd0==nil || fd1==nil){
		fprint(stderr, "can't open /dev/cons: %r\n");
		exit;
	}
	dup(fd0.fd, 0);
	dup(fd1.fd, 1);
	dup(fd1.fd, 2);
	fd0 = fd1 = nil;
	b := sprint("/chan/%d", id);
	if(bind(b, "/dev/acme", MREPL) < 0)
		error("bind /dev/acme");
	if(bind(sprint("/chan/%d/consctl", id), "/dev/consctl", MREPL) < 0)
	 	error("bind /dev/consctl");
	exec(hd argv, argv);
	exit;
}

killing : int = 0;

error(s : string)
{
	if(s != nil)
		fprint(stderr, "win: %s: %r\n", s);
	if (killing)
		return;
	killing = 1;
	s = "kill";
	if(pid)
		postnote(PNGROUP, pid, s);
		# write(pgrpfd, array of byte "hangup", 6);
	postnote(PNGROUP, parentpid, s);
	finish <-= 1;
	exit;
}

buff := array[8192] of byte;
bufp : int;
nbuf : int;

onestring(argv : list of string) : string
{
	s : string;

	if(argv == nil)
		return "";
	for( ; argv != nil; argv = tl argv){
		s += hd argv;
		if (tl argv != nil)
			s += " ";
	}
	return s;
}

getec(efd : ref FD) : int
{
	if(nbuf == 0){
		nbuf = read(efd, buff, len buff);
		if(nbuf <= 0)
			error(nil);
		bufp = 0;
	}
	--nbuf;
	return int buff[bufp++];
}

geten(efd : ref FD) : int
{
	n, c : int;

	n = 0;
	while('0'<=(c=getec(efd)) && c<='9')
		n = n*10+(c-'0');
	if(c != ' ')
		error("event number syntax");
	return n;
}

geter(efd : ref FD, buf : array of byte) : (int, int)
{
	r, m, n, ok : int;

	r = getec(efd);
	buf[0] = byte r;
	n = 1;
	if(r < Runeself)
		return (r, n);
	for (;;) {
		(r, m, ok) = byte2char(buf[0:n], 0);
		if (m > 0)
			return (r, n);
		buf[n++] = byte getec(efd);
	}
	return (0, 0);
}

gete(efd : ref FD, e : ref Event)
{
	i, nb : int;

	e.c1 = getec(efd);
	e.c2 = getec(efd);
	e.q0 = geten(efd);
	e.q1 = geten(efd);
	e.flag = geten(efd);
	e.nr = geten(efd);
	if(e.nr > EVENTSIZE)
		error("event string too long");
	e.nb = 0;
	for(i=0; i<e.nr; i++){
		(e.r[i], nb) = geter(efd, e.b[e.nb:]);
		e.nb += nb;
	}
	e.r[e.nr] = 0;
	e.b[e.nb] = byte 0;
	if(getec(efd) != '\n')
		error("event syntax 2");
}

nrunes(s : array of byte, nb : int) : int
{
	i, n, r, b, ok : int;

	n = 0;
	for(i=0; i<nb; n++) {
		(r, b, ok) = byte2char(s, i);
		if (b == 0)
			error("not full string in nrunes()");
		i += b;
	}
	return n;
}

stdinx(fd0 : ref FD, cfd : ref FD, efd : ref FD, afd : ref FD, dfd : ref FD)
{
	e, e2, e3, e4 : ref Event;

	e = newevent(EVENTSIZE);
	e2 = newevent(EVENTSIZE);
	e3 = newevent(EVENTSIZE);
	e4 = newevent(EVENTSIZE);
	for(;;){
		gete(efd, e);
		q.l.lock();
		case(e.c1){
		'E' =>	# write to body; can't affect us 
			break;
		'F' =>	# generated by our actions; ignore 
			break;
		'K' or 'M' =>
			case(e.c2){
			'R' =>
				addtype(' ', ntyper, e.b, e.nb, e.nr);
				sendtype(fd0, 1);
				break;
			'I' =>
				if(e.q0 < q.p)
					q.p += e.q1-e.q0;
				else if(e.q0 <= q.p+ntyper)
					typex(e, fd0, afd, dfd);
				break;
			'D' =>
				q.p -= delete(e);
				break;
			'x' or 'X' =>
				if(e.flag & 2)
					gete(efd, e2);
				if(e.flag & 8){
					gete(efd, e3);
					gete(efd, e4);
				}
				if(e.flag&1 || (e.c2=='x' && e.nr==0 && e2.nr==0)){
					# send it straight back 
					fprint(efd, "%c%c%d %d\n", e.c1, e.c2, e.q0, e.q1);
					break;
				}
				if(e.q0==e.q1 && (e.flag&2)){
					e2.flag = e.flag;
					*e = *e2;
				}
				if(e.flag & 8){
					if(e.q1 != e.q0){
						send(e, fd0, cfd, afd, dfd, 0);
						send(blank, fd0, cfd, afd, dfd, 0);
					}
					send(e3, fd0, cfd, afd, dfd, 1);
				}else	 if(e.q1 != e.q0)
					send(e, fd0, cfd, afd, dfd, 1);
				break;
			'l' or 'L' =>
				# just send it back 
				if(e.flag & 2)
					gete(efd, e2);
				fprint(efd, "%c%c%d %d\n", e.c1, e.c2, e.q0, e.q1);
				break;
			'd' or 'i' =>
				break;
			* =>
				fprint(stdout, "unknown message %c%c\n", e.c1, e.c2);
				break;
			}
		* =>
			fprint(stdout, "unknown message %c%c\n", e.c1, e.c2);
			break;
		}
		q.l.unlock();
	}
}

stdoutx(fd1 : ref FD, afd : ref FD, dfd : ref FD)
{
	n, m, w, npart : int;
	s, t : int;
	buf, hold, x : array of byte;
	r, ok : int;

	buf = array[8192+UTFmax+1] of byte;
	hold = array[UTFmax] of byte;
	npart = 0;
	for(;;){
		n = read(fd1, buf[npart:], 8192);
		if(n < 0)
			error(nil);
		if(n == 0)
			continue;

		# squash NULs 
		for (s = 0; s < n; s++)
			if (buf[npart+s] == byte 0)
				break;
		if(s < n){
			for(t=s; s<n; s++)
				if(buf[npart+t] == buf[npart+s])	# assign = 
					t++;
			n = t;
		}

		n += npart;

		# hold on to final partial rune 
		npart = 0;
		while(n>0 && (int buf[n-1]&16rC0)){
			--n;
			npart++;
			if((int buf[n]&16rC0)!=16r80){
				if(utfbytes(buf[n:], npart) > 0){
					(r, w, ok) = byte2char(buf, n);
					n += w;
					npart -= w;
				}
				break;
			}
		}
		if(n > 0){
			hold[0:] = buf[n:n+npart];
			buf[n] = byte 0;
			q.l.lock();
			str := sprint("#%d", q.p);
			x = array of byte str;
			m = len x;
			if(write(afd, x, m) != m)
				error("stdout writing address");
			x = nil;
			if(write(dfd, buf, n) != n)
				error("stdout writing body");
			q.p += nrunes(buf, n);
			q.l.unlock();
			buf[0:] = hold[0:npart];
		}
	}
}

delete(e : ref Event) : int
{
	q0, q1 : int;
	deltap : int;

	q0 = e.q0;
	q1 = e.q1;
	if(q1 <= q.p)
		return e.q1-e.q0;
	if(q0 >= q.p+ntyper)
		return 0;
	deltap = 0;
	if(q0 < q.p){
		deltap = q.p-q0;
		q0 = 0;
	}else
		q0 -= q.p;
	if(q1 > q.p+ntyper)
		q1 = ntyper;
	else
		q1 -= q.p;
	deltype(q0, q1);
	return deltap;
}

addtype(c : int, p0 : int, b : array of byte, nb : int, nr : int)
{
	i, w : int;
	r, ok : int;
	p : int;
	b0 : int;

	for(i=0; i<nb; i+=w){
		(r, w, ok) = byte2char(b, i);
		if(r==16r7F && c=='K'){
			if (pid)
				postnote(PNGROUP, pid, "kill");
				# write(pgrpfd, array of byte "interrupt", 9);
			# toss all typing 
			q.p += ntyper+nr;
			ntypebreak = 0;
			ntypeb = 0;
			ntyper = 0;
			# buglet:  more than one delete ignored 
			return;
		}
		if(r=='\n' || r==16r04)
			ntypebreak++;
	}
	ot := typing;
	typing = array[ntypeb+nb] of byte;
	if(typing == nil)
		error("realloc");
	if (ot != nil)
		typing[0:] = ot[0:ntypeb];
	ot = nil;
	if(p0 == ntyper)
		typing[ntypeb:] = b[0:nb];
	else{
		b0 = 0;
		for(p=0; p<p0 && b0<ntypeb; p++){
			(r, w, ok) = byte2char(typing[b0:], i);
			b0 += w;
		}
		if(p != p0)
			error("typing: findrune");
		typing[b0+nb:] = typing[b0:ntypeb];
		typing[b0:] = b[0:nb];
	}
	ntypeb += nb;
	ntyper += nr;
}

sendtype(fd0 : ref FD, raw : int)
{
	while(ntypebreak){
		brkc := 0;
		i := 0;
		while(i<ntypeb){
			if(typing[i]==byte '\n' || typing[i]==byte 16r04){
				n := i + (typing[i] == byte '\n');
				i++;
				if(write(fd0, typing, n) != n)
					error("sending to program");
				nr := nrunes(typing, i);
				if (!raw)
					q.p += nr;
				ntyper -= nr;
				ntypeb -= i;
				typing[0:] = typing[i:i+ntypeb];
				i = 0;
				ntypebreak--;
				brkc = 1;
			}else
				i++;
		}
		if (!brkc) {
			fprint(stdout, "no breakchar\n");
			ntypebreak = 0;
		}
	}
}

deltype(p0 : int, p1 : int)
{
	w : int;
	p, b0, b1 : int;
	r, ok : int;

	# advance to p0 
	b0 = 0;
	for(p=0; p<p0 && b0<ntypeb; p++){
		(r, w, ok) = byte2char(typing, b0);
		b0 += w;
	}
	if(p != p0)
		error("deltype 1");
	# advance to p1 
	b1 = b0;
	for(; p<p1 && b1<ntypeb; p++){
		(r, w, ok) = byte2char(typing, b1);
		b1 += w;
		if(r=='\n' || r==16r04)
			ntypebreak--;
	}
	if(p != p1)
		error("deltype 2");
	typing[b0:] = typing[b1:ntypeb];
	ntypeb -= b1-b0;
	ntyper -= p1-p0;
}

typex(e : ref Event, fd0 : ref FD, afd : ref FD, dfd : ref FD)
{
	m, n, nr : int;
	buf : array of byte;

	if(e.nr > 0)
		addtype(e.c1, e.q0-q.p, e.b, e.nb, e.nr);
	else{
		buf = array[128] of byte;
		m = e.q0;
		while(m < e.q1){
			str := sprint("#%d", m);
			b := array of byte str;
			n = len b;
			write(afd, b, n);
			b = nil;
			n = read(dfd, buf, len buf);
			nr = nrunes(buf, n);
			while(m+nr > e.q1){
				do; while(n>0 && (int buf[--n]&16rC0)==16r80);
				--nr;
			}
			if(n == 0)
				break;
			addtype(e.c1, m-q.p, buf, n, nr);
			m += nr;
		}
	}
	buf = nil;
	sendtype(fd0, 0);
}

send(e : ref Event, fd0 : ref FD, cfd : ref FD, afd : ref FD, dfd : ref FD, donl : int)
{
	l, m, n, nr, lastc, end : int;
	abuf, buf : array of byte;

	buf = array[128] of byte;
	end = q.p+ntyper;
	str := sprint("#%d", end);
	abuf = array of byte str;
	l = len abuf;
	write(afd, abuf, l);
	abuf = nil;
	if(e.nr > 0){
		write(dfd, e.b, e.nb);
		addtype(e.c1, ntyper, e.b, e.nb, e.nr);
		lastc = e.r[e.nr-1];
	}else{
		m = e.q0;
		lastc = 0;
		while(m < e.q1){
			str = sprint("#%d", m);
			abuf = array of byte str;
			n = len abuf;
			write(afd, abuf, n);
			abuf = nil;
			n = read(dfd, buf, len buf);
			nr = nrunes(buf, n);
			while(m+nr > e.q1){
				do; while(n>0 && (int buf[--n]&16rC0)==16r80);
				--nr;
			}
			if(n == 0)
				break;
			str = sprint("#%d", end);
			abuf = array of byte str;
			l = len abuf;
			write(afd, abuf, l);
			abuf = nil;
			write(dfd, buf, n);
			addtype(e.c1, ntyper, buf, n, nr);
			lastc = int buf[n-1];
			m += nr;
			end += nr;
		}
	}
	if(donl && lastc!='\n'){
		write(dfd, array of byte "\n", 1);
		addtype(e.c1, ntyper, array of byte "\n", 1, 1);
	}
	write(cfd, array of byte "dot=addr", 8);
	sendtype(fd0, 0);
	buf = nil;
}

