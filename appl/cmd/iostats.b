implement Iostats;

#
# iostats - gather file system access statistics
#

include "sys.m";
	sys: Sys;
	Qid: import sys;

include "draw.m";

include "styx.m";
	styx: Styx;
	Tmsg, Rmsg, NOFID, NOTAG: import styx;

include "workdir.m";
	workdir: Workdir;

include "sh.m";

include "arg.m";

Iostats: module
{
	init:	fn(nil: ref Draw->Context, nil: list of string);
};

Maxmsg: con 128*1024+Styx->IOHDRSZ;
Ns2ms: con big 1000000;

Rpc: adt
{
	name:	string;
	count:	big;
	time:		big;
	lo:	big;
	hi:	big;
	bin:		big;
	bout:	big;
};

Stats: adt
{
	totread:	big;
	totwrite:	big;
	nrpc:	int;
	nproto:	int;
	rpc:		array of ref Rpc;	# Maxrpc
};

Fid: adt {
	nr:	int;	# fid number
	path:		ref Path;	# path used to open Fid
	qid:		Qid;
	mode:	int;
	nread:	big;
	nwrite:	big;
	bread:	big;
	bwrite:	big;
	offset:	big;	# for directories
};

Path: adt {
	parent:	cyclic ref Path;
	name:	string;
};

Frec: adt
{
	op:	ref Path;	# first name?
	qid:	Qid;
	nread:	big;
	nwrite:	big;
	bread:	big;
	bwrite:	big;
	opens:	int;
};

Tag: adt {
	m: 		ref Tmsg;
	fid:		ref Fid;
	stime:	big;
	next: 	cyclic ref Tag;
};

NTAGHASH: con 1<<4;	# power of 2
NFIDHASH: con 1<<4;	# power of 2

tags := array[NTAGHASH] of ref Tag;
fids := array[NFIDHASH] of list of ref Fid;
dbg := 0;

stats: Stats;
frecs:	list of ref Frec;

replymap := array[tagof Rmsg.Stat+1] of {
	tagof Rmsg.Version => tagof Tmsg.Version,
	tagof Rmsg.Auth => tagof Tmsg.Auth,
	tagof Rmsg.Attach => tagof Tmsg.Attach,
	tagof Rmsg.Flush => tagof Tmsg.Flush,
	tagof Rmsg.Clunk => tagof Tmsg.Clunk,
	tagof Rmsg.Remove => tagof Tmsg.Remove,
	tagof Rmsg.Wstat => tagof Tmsg.Wstat,
	tagof Rmsg.Walk => tagof Tmsg.Walk,
	tagof Rmsg.Create => tagof Tmsg.Create,
	tagof Rmsg.Open => tagof Tmsg.Open,
	tagof Rmsg.Read => tagof Tmsg.Read,
	tagof Rmsg.Write => tagof Tmsg.Write,
	tagof Rmsg.Stat => tagof Tmsg.Stat,
	* => -1,
};

init(ctxt: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	workdir = load Workdir Workdir->PATH;
	sh := load Sh Sh->PATH;
	styx = load Styx Styx->PATH;
	styx->init();

	wd := workdir->init();

	dbfile := "iostats.out";
	arg := load Arg Arg->PATH;
	arg->init(args);
	arg->setusage("iostats [-d] [-f debugfile] cmds [args ...]");
	while((o := arg->opt()) != 0)
		case o {
		'd' =>	dbg++;
		'f' =>		dbfile = arg->earg();
		* =>		arg->usage();
		}
	args = arg->argv();
	if(args == nil)
		arg->usage();
	arg = nil;

	sys->pctl(Sys->FORKFD|Sys->FORKNS|Sys->NEWPGRP|Sys->FORKENV, nil);

	if(dbg){
		fd := sys->create(dbfile, Sys->OWRITE, 8r666);
		if(fd == nil)
			fatal(sys->sprint("can't create %q: %r", dbfile));
		sys->dup(fd.fd, 2);
	}

	if(sys->chdir("/") < 0)
		fatal(sys->sprint("chdir /: %r"));

	stats.totread = big 0;
	stats.totwrite = big 0;
	stats.nrpc = 0;
	stats.nproto = 0;
	stats.rpc = array[tagof Tmsg.Wstat + 1] of ref Rpc;
	stats.rpc[tagof Tmsg.Version] = mkrpc("version");
	stats.rpc[tagof Tmsg.Auth] = mkrpc("auth");
	stats.rpc[tagof Tmsg.Flush] = mkrpc("flush");
	stats.rpc[tagof Tmsg.Attach] = mkrpc("attach");
	stats.rpc[tagof Tmsg.Walk] = mkrpc("walk");
	stats.rpc[tagof Tmsg.Open] = mkrpc("open");
	stats.rpc[tagof Tmsg.Create] = mkrpc("create");
	stats.rpc[tagof Tmsg.Clunk] = mkrpc("clunk");
	stats.rpc[tagof Tmsg.Read] = mkrpc("read");
	stats.rpc[tagof Tmsg.Write] = mkrpc("write");
	stats.rpc[tagof Tmsg.Remove] = mkrpc("remove");
	stats.rpc[tagof Tmsg.Stat] = mkrpc("stat");
	stats.rpc[tagof Tmsg.Wstat] = mkrpc("wstat");

	mpipe := array[2] of ref Sys->FD;
	if(sys->pipe(mpipe) < 0)
		fatal(sys->sprint("can't create pipe: %r"));
	pids := chan of int;
	cmddone := chan of int;
	spawn cmd(sh, ctxt, args, wd, mpipe[0], pids, cmddone);
	<-pids;
	mpipe[0] = nil;
	epipe := array[2] of ref Sys->FD;
	if(sys->pipe(epipe) < 0)
		fatal(sys->sprint("can't create pipe: %r"));
	spawn export(epipe[1], pids);
	<-pids;
	epipe[1] = nil;
	iodone := chan of int;
	spawn iostats(epipe[0], mpipe[1], pids, iodone);
	<-pids;
	epipe[0] = mpipe[1] = nil;
	<-cmddone;
	<-iodone;
	results();
}

cmd(sh: Sh, ctxt: ref Draw->Context, args: list of string, wdir: string, fsfd: ref Sys->FD, pids: chan of int, done: chan of int)
{
	{
		pids <-= sys->pctl(Sys->FORKNS|Sys->FORKFD, nil);
		if(sys->mount(fsfd, nil, "/", Sys->MREPL, "") < 0)
			fatal(sys->sprint("can't mount /: %r"));
		fsfd = nil;
		sys->bind("#e", "/env", Sys->MREPL | Sys->MCREATE);
		sys->bind("#d", "/fd", Sys->MREPL);	# better than nothing
		if(sys->chdir(wdir) < 0)
			fatal(sys->sprint("can't chdir to %s: %r", wdir));
		sh->run(ctxt, args);
	}exception{
	"fail:*" =>
		;	# don't mention it
	* =>
		raise;	# cause the fault
	}
	done <-= 1;
}

iostats(expfd: ref Sys->FD, mountfd: ref Sys->FD, pids: chan of int, done: chan of int)
{
	pids <-= sys->pctl(Sys->NEWFD|Sys->NEWPGRP, 1 :: 2 :: expfd.fd :: mountfd.fd :: nil);
	timefd := sys->open("/dev/time", Sys->OREAD);
	if(timefd == nil)
		fatal(sys->sprint("can't open /dev/time: %r"));
	tmsgs := chan of (int, ref Tmsg);
	spawn Treader(mountfd, expfd, tmsgs);
	(tpid, nil) := <-tmsgs;
	rmsgs := chan of (int, ref Rmsg);
	spawn Rreader(expfd, mountfd, rmsgs);
	(rpid, nil) := <-rmsgs;
	expfd = mountfd = nil;
	stderr := sys->fildes(2);
Run:
	for(;;)alt{
	(n, t) := <-tmsgs =>	# n.b.: received on tmsgs before it goes to server
		if(t == nil || tagof t == tagof Tmsg.Readerror)
			break Run;	# TO DO?
		if(dbg)
			sys->fprint(stderr, "->%s\n", t.text());
		tag := newtag(t, nsec(timefd));
		stats.nrpc++;
		stats.nproto += n;
		rpc := stats.rpc[tagof t];
		if(rpc == nil){
			sys->fprint(stderr, "iostats: unexpected T-msg %d\n", tagof t);
			continue;
		}
		rpc.count++;
		rpc.bin += big n;
		pick pt := t {
		Auth =>
			tag.fid = newfid(pt.afid);
		Attach =>
			tag.fid = newfid(pt.fid);
		Walk =>
			tag.fid = findfid(pt.fid);
		Open =>
			tag.fid = findfid(pt.fid);
		Create =>
			tag.fid = findfid(pt.fid);
		Read =>
			tag.fid = findfid(pt.fid);
		Write =>
			tag.fid = findfid(pt.fid);
			pt.data = nil;	# don't need to keep data
		Clunk or
		Stat or
		Remove =>
			tag.fid = findfid(pt.fid);
		Wstat =>
			tag.fid = findfid(pt.fid);
		}
	(n, r) := <-rmsgs =>
		if(r == nil || tagof r == tagof Rmsg.Readerror){
			break Run;	# TO DO
		}
		if(dbg)
			sys->fprint(stderr, "<-%s\n", r.text());
		stats.nproto += n;
		tag := findtag(r.tag, 1);
		if(tag == nil)
			continue;	# client or server error TO DO: account for flush
		if(tagof r < len replymap && (tt := replymap[tagof r]) >= 0 && (rpc := stats.rpc[tt]) != nil){
			update(rpc, nsec(timefd)-tag.stime);
			rpc.bout += big n;
		}
		fid := tag.fid;
		pick pr := r {
		Error =>
			pick m := tag.m {
			Auth =>
				if(fid != nil){
					if(fid.nread != big 0 || fid.nwrite != big 0)
						fidreport(fid);
					freefid(fid);
				}
			}
		Version =>
			# could pick up message size
			# flush fids/tags
			tags = array[len tags] of ref Tag;
			fids = array[len fids] of list of ref Fid;
		Auth =>
			# afid from fid.t, qaid from auth
			if(fid != nil){
				fid.qid = pr.aqid;
				fid.path = ref Path(nil, "#auth");
			}
		Attach =>
			if(fid != nil){
				fid.qid = pr.qid;
				fid.path = ref Path(nil, "/");
			}
		Walk =>
			pick m := tag.m {
			Walk =>
				if(len pr.qids != len m.names)
					break;	# walk failed, no change
				if(fid == nil)
					break;
				if(m.newfid != m.fid){
					nf := newfid(m.newfid);
					nf.path = fid.path;
					fid = nf;	# walk new fid
				}
				for(i := 0; i < len m.names; i++){
					fid.qid = pr.qids[i];
					if(m.names[i] == ".."){
						if(fid.path.parent != nil)
							fid.path = fid.path.parent;
					}else
						fid.path = ref Path(fid.path, m.names[i]);
				}
			}
		Open or
		Create =>
			if(fid != nil)
				fid.qid = pr.qid;
		Read =>
			fid.nread++;
			nr := big len pr.data;
			fid.bread += nr;
			stats.totread += nr;
		Write =>
			# count
			fid.nwrite++;
			fid.bwrite += big pr.count;
			stats.totwrite += big pr.count;
		Flush =>
			pick m := tag.m {
			Flush =>
				findtag(m.oldtag, 1);	# discard if there
			}
		Clunk or
		Remove =>
			if(fid != nil){
				if(fid.nread != big 0 || fid.nwrite != big 0)
					fidreport(fid);
				freefid(fid);
			}
		}
	}
	kill(rpid, "kill");
	kill(tpid, "kill");
	done <-= 1;
}

results()
{
	stderr := sys->fildes(2);
	rpc := stats.rpc[tagof Tmsg.Read];
	brpsec := real stats.totread / ((real rpc.time/1.0e9)+.000001);

	rpc = stats.rpc[tagof Tmsg.Write];
	bwpsec := real stats.totwrite / ((real rpc.time/1.0e9)+.000001);

	ttime := big 0;
	for(n := 0; n < len stats.rpc; n++){
		rpc = stats.rpc[n];
		if(rpc == nil || rpc.count == big 0)
			continue;
		ttime += rpc.time;
	}

	bppsec := real stats.nproto / ((real ttime/1.0e9)+.000001);

	sys->fprint(stderr, "\nread      %bud bytes, %g Kb/sec\n", stats.totread, brpsec/1024.0);
	sys->fprint(stderr, "write     %bud bytes, %g Kb/sec\n", stats.totwrite, bwpsec/1024.0);
	sys->fprint(stderr, "protocol  %ud bytes, %g Kb/sec\n", stats.nproto, bppsec/1024.0);
	sys->fprint(stderr, "rpc       %ud count\n\n", stats.nrpc);

	sys->fprint(stderr, "%-10s %5s %5s %5s %5s %5s           T        R\n", 
	      "Message", "Count", "Low", "High", "Time", "  Avg");

	for(n = 0; n < len stats.rpc; n++){
		rpc = stats.rpc[n];
		if(rpc == nil || rpc.count == big 0)
			continue;
		sys->fprint(stderr, "%-10s %5bud %5bud %5bud %5bud %5bud ms %8bud %8bud bytes\n", 
			rpc.name, 
			rpc.count,
			rpc.lo/Ns2ms,
			rpc.hi/Ns2ms,
			rpc.time/Ns2ms,
			rpc.time/Ns2ms/rpc.count,
			rpc.bin,
			rpc.bout);
	}

	# unclunked fids
	for(n = 0; n < NFIDHASH; n++)
		for(fl := fids[n]; fl != nil; fl = tl fl){
			fid := hd fl;
			if(fid.nread != big 0 || fid.nwrite != big 0)
				fidreport(fid);
		}
	if(frecs == nil)
		exit;

	sys->fprint(stderr, "\nOpens    Reads  (bytes)   Writes  (bytes) File\n");
	for(frl := frecs; frl != nil; frl = tl frl){
		fr := hd frl;
		case s := makepath(fr.op) {
		"/fd/0" =>	s = "(stdin)";
		"/fd/1" =>	s = "(stdout)";
		"/fd/2" =>	s = "(stderr)";
		"" =>		s = "/.";
		}
		sys->fprint(stderr, "%5ud %8bud %8bud %8bud %8bud %s\n", fr.opens, fr.nread, fr.bread,
							fr.nwrite, fr.bwrite, s);
	}
}

Treader(fd: ref Sys->FD, ofd: ref Sys->FD, out: chan of (int, ref Tmsg))
{
	out <-= (sys->pctl(0, nil), nil);
	fd = sys->fildes(fd.fd);
	ofd = sys->fildes(ofd.fd);
	for(;;){
		(a, err) := styx->readmsg(fd, Maxmsg);
		if(err != nil){
			out <-= (0, ref Tmsg.Readerror(0, err));
			break;
		}
		if(a == nil){
			out <-= (0, nil);
			break;
		}
		(nil, m) := Tmsg.unpack(a);
		if(m == nil){
			out <-= (0, ref Tmsg.Readerror(0, "bad Styx T-message format"));
			break;
		}
		out <-= (len a, m);
		sys->write(ofd, a, len a);	# TO DO: errors
	}
}

Rreader(fd: ref Sys->FD, ofd: ref Sys->FD, out: chan of (int, ref Rmsg))
{
	out <-= (sys->pctl(0, nil), nil);
	fd = sys->fildes(fd.fd);
	ofd = sys->fildes(ofd.fd);
	for(;;){
		(a, err) := styx->readmsg(fd, Maxmsg);
		if(err != nil){
			out <-= (0, ref Rmsg.Readerror(0, err));
			break;
		}
		if(a == nil){
			out <-= (0, nil);
			break;
		}
		(nil, m) := Rmsg.unpack(a);
		if(m == nil){
			out <-= (0, ref Rmsg.Readerror(0, "bad Styx R-message format"));
			break;
		}
		out <-= (len a, m);
		sys->write(ofd, a, len a);	# TO DO: errors
	}
}

reply(fd: ref Sys->FD, m: ref Rmsg)
{
	d := m.pack();
	sys->write(fd, d, len d);
}

mkrpc(s: string): ref Rpc
{
	return ref Rpc(s, big 0, big 0, big 1 << 40, big 0, big 0, big 0);
}

newfid(nr: int): ref Fid
{
	h := nr%NFIDHASH;
	for(fl := fids[h]; fl != nil; fl = tl fl)
		if((hd fl).nr == nr)
			return hd fl;	# shouldn't happen: faulty client
	fid := ref Fid;
	fid.nr = nr;
	fid.nread = big 0;
	fid.nwrite = big 0;
	fid.bread = big 0;
	fid.bwrite = big 0;
	fid.qid = Qid(big 0, 0, -1);
	fids[h] = fid :: fids[h];
	return fid;
}

findfid(nr: int): ref Fid
{
	for(fl := fids[nr%NFIDHASH]; fl != nil; fl = tl fl)
		if((hd fl).nr == nr)
			return hd fl;
	return nil;
}

freefid(fid: ref Fid)
{
	h := fid.nr%NFIDHASH;
	nl: list of ref Fid;
	for(fl := fids[h]; fl != nil; fl = tl fl)
		if((hd fl).nr != fid.nr)
			nl = hd fl :: nl;
	fids[h] = nl;
}

makepath(p: ref Path): string
{
	nl: list of string;
	for(; p != nil; p = p.parent)
		if(p.name != "/")
			nl = p.name :: nl;
	s := "";
	for(; nl != nil; nl = tl nl)
		if(s != nil)
			s += "/" + hd nl;
		else
			s = hd nl;
	return "/"+s;
}

fatal(s: string)
{
	sys->fprint(sys->fildes(2), "iostats: %s: %r\n", s);
	raise "fatal:error";
}

nsec(fd: ref Sys->FD): big
{
	buf := array[100] of byte;
	n := sys->pread(fd, buf, len buf, big 0);
	if(n <= 0)
		return big 0;
	return big string buf[0:n];
}

fidreport(f: ref Fid)
{
	for(fl := frecs; fl != nil; fl = tl fl){
		fr := hd fl;
		if(eqqid(f.qid, fr.qid)){
			# could put f.path in list of paths if aliases were interesting
			fr.nread += f.nread;
			fr.nwrite += f.nwrite;
			fr.bread += f.bread;
			fr.bwrite += f.bwrite;
			fr.opens++;
			return;
		}
	}

	fr := ref Frec;
	fr.op = f.path;
	fr.qid = f.qid;
	fr.nread = f.nread;
	fr.nwrite = f.nwrite;
	fr.bread = f.bread;
	fr.bwrite = f.bwrite;
	fr.opens = 1;
	frecs = fr :: frecs;
}

update(rpc: ref Rpc, t: big)
{
	if(t < big 0)
		t = big 0;

	rpc.time += t;
	if(t < rpc.lo)
		rpc.lo = t;
	if(t > rpc.hi)
		rpc.hi = t;
}

newtag(m: ref Tmsg, t: big): ref Tag
{
	slot := m.tag & (NTAGHASH - 1);
	tag := ref Tag(m, nil, t, tags[slot]);
	tags[slot] = tag;
	return tag;
}

findtag(tag: int, destroy: int): ref Tag
{
	slot := tag & (NTAGHASH - 1);
	prev: ref Tag;
	for(t := tags[slot]; t != nil; t = t.next){
		if(t.m.tag == tag)
			break;
		prev = t;
	}
	if(t == nil || !destroy)
		return t;
	if(prev == nil)
		tags[slot] = t.next;
	else
		prev.next = t.next;
	return t;
}

eqqid(a, b: Qid): int
{
	return a.path == b.path && a.qtype == b.qtype;
}

export(fd: ref Sys->FD, pid: chan of int)
{
	pid <-= sys->pctl(Sys->NEWFD|Sys->FORKNS, fd.fd::0::1::2::nil);
	sys->export(fd, "/", Sys->EXPWAIT);
}

kill(pid: int, what: string)
{
	fd := sys->open("#p/"+string pid+"/ctl", Sys->OWRITE);
	if(fd != nil)
		sys->fprint(fd, "%s", what);
}
