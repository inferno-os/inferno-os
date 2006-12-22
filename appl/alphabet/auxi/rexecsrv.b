implement Rexecsrv;
include "sys.m";
	sys: Sys;
include "draw.m";
include "sh.m";
	sh: Sh;
include "alphabet/endpoints.m";
	endpoints: Endpoints;
	Endpoint: import endpoints;
include "alphabet/reports.m";
	reports: Reports;
	Report: import reports;
include "alphabet.m";
	alphabet: Alphabet;
	Value: import alphabet;
include "alphabet/abc.m";
include "alphabet/abctypes.m";
include "string.m";
	str: String;

Rexecsrv: module {
	init: fn(nil: ref Draw->Context, argv: list of string);
};
drawctxt: ref Draw->Context;

init(ctxt: ref Draw->Context, argv: list of string)
{
	sys = load Sys Sys->PATH;
	endpoints = load Endpoints Endpoints->PATH;
	if(endpoints == nil)
		fatal(sys->sprint("cannot load %s: %r", Endpoints->PATH));
	endpoints->init();
	sh = load Sh Sh->PATH;
	if(sh == nil)
		fatal(sys->sprint("cannot load %s: %r", Sh->PATH));
	sh->initialise();
	reports = load Reports Reports->PATH;
	if(reports == nil)
		fatal(sys->sprint("cannot load %s: %r", Reports->PATH));
	str = load String String->PATH;
	if(str == nil)
		fatal(sys->sprint("cannot load %s: %r", String->PATH));
	if(len argv != 3)
		fatal("usage: rexecsrv dir {decls}");
	drawctxt = ctxt;
	if(sys->stat("/n/endpoint/local/clone").t0 == -1)
		fatal("no local endpoints available");
	dir := hd tl argv;
	decls := parse(hd tl tl argv);
	if(sys->bind("#s", dir, Sys->MREPL) == -1)
		fatal(sys->sprint("cannot bind #s onto %q: %r", dir));

	alphabet = declares(decls);

	fio := sys->file2chan(dir, "exec");
	sync := chan of int;
	spawn rexecproc(sync, fio);
	<-sync;
}

stderr(): ref Sys->FD
{
	return sys->fildes(2);
}

# use one alphabet module to bootstrap another
# with the desired declarations that we can use to
# execute external commands.
declares(decls: ref Sh->Cmd): Alphabet
{
	alphabet0 := load Alphabet Alphabet->PATH;
	if(alphabet0 == nil)
		fatal(sys->sprint("cannot load %s: %r", Alphabet->PATH));
	alphabet0->init();
	abctypes := load Abctypes Abctypes->PATH;
	if(abctypes == nil)
		fatal(sys->sprint("cannot load %s: %r", Abctypes->PATH));
	Abccvt: import abctypes;
	abc := load Abc Abc->PATH;
	if(abc == nil)
		fatal(sys->sprint("cannot load %s: %r", Abc->PATH));
	abc->init();
	Value: import abc;

	(c, nil, abccvt) := abctypes->proxy0();

	spawn reports->reportproc(errorc := chan of string, nil, reply := chan of ref Report);
	r := <-reply;
	if((err := alphabet0->loadtypeset("/abc", c, nil)) != nil)
		fatal("cannot load typeset /abc: "+err);
	alphabet0->setautodeclare(1);
	spawn alphabet0->eval0(
		parse("{(/cmd);"+
			"/abc/abc |"+
			"/abc/declares $1"+
			"}"
		),
		"/abc/abc",
		nil,
		r,
		r.start("evaldecls"),
		ref (Alphabet->Value).Vc(decls) :: nil,
		vc := chan of ref Alphabet->Value
	);
	r.enable();
	av: ref Alphabet->Value;
wait:
	for(;;)alt{
	av = <-vc =>
		;
	msg := <-errorc =>
		if(msg == nil)
			break wait;
		sys->fprint(stderr(), "rexecsrv: %s\n", msg);
	}
	if(av == nil)
		fatal("declarations failed");
	v := abccvt.ext2int(av).dup();
	alphabet0->av.free(1);
	pick xv := v {
	VA =>
		return xv.i.alphabet;
	}
	return nil;
}

parse(s: string): ref Sh->Cmd
{
	(c, err) := sh->parse(s);
	if(c== nil)
		fatal(sys->sprint("cannot parse %q: %s", s, err));
	return c;
}

lc(cmd: ref Sh->Cmd): ref Sh->Listnode
{
	return ref Sh->Listnode(cmd, nil);
}

lw(word: string): ref Sh->Listnode
{
	return ref Sh->Listnode(nil, word);
}

# write endpoints, cmd
# read endpoints
rexecproc(sync: chan of int, fio: ref Sys->FileIO)
{
	sys->pctl(Sys->FORKNS, nil);
	pending: list of (int, string);
	sync <-= 1;
	for(;;) alt {
	(nil, data, fid, wc) := <-fio.write =>
		if(wc == nil)
			break;
		req := string data;
		l := str->unquoted(req);
		if(len l != 2 || Endpoint.mk(hd l).addr == nil){
			wc <-= (0, "bad request");
			break;
		}
		pending = (fid, req) :: pending;
		wc <-= (0, nil);
	(offset, nil, fid, rc) := <-fio.read =>
		if(rc == nil){
			(pending, nil) = removefid(fid, pending);
			break;
		}
		if(offset > 0){
			rc <-= (nil, nil);
			break;
		}
		req: string;
		(pending, req) = removefid(fid, pending);
		if(req == nil){
			rc <-= (nil, "no pending exec");
			break;
		}
		l := str->unquoted(req);
		spawn exec(sync1 := chan of int, Endpoint.mk(hd l), hd tl l, rc);
		<-sync1;
	}
}

gather(errorc: chan of string)
{
	s := "";
	while((e := <-errorc) != nil)
		s += e + "\n";
	errorc <-= s;
}

exec(sync: chan of int, ep: Endpoint, expr: string,
		rc: chan of (array of byte, string))
{
	sys->pctl(Sys->FORKNS, nil);
	sync <-= 1;

	spawn gather(errorc := chan of string);
	(c, err) := alphabet->parse(expr);
	if(c == nil){
		rc <-= (nil, "parse error: "+err);
		return;
	}
	usage: string;
	(c, usage) = alphabet->rewrite(c, "/fd", errorc);
	errorc <-= nil;
	err = <-errorc;
	if(c == nil){
		rc <-= (nil, err);
		return;
	}
	if(!alphabet->typecompat("/fd -> /fd", usage).t0)
		rc <-= (nil, "incompatible type: "+usage);

	fd0: ref Sys->FD;
	(fd0, err) = endpoints->open(nil, ep);
	if(fd0 == nil){
		rc <-= (nil, err);
		return;
	}
	(fd1, ep1) := endpoints->create("local");
	if(fd1 == nil){
		rc <-= (nil, "cannot make endpoints: "+ep1.about);
		return;
	}
	rc <-= (array of byte ep1.text(), nil);

	runcmd(c, fd0, fd1);
}

fdproc(f: chan of ref Sys->FD, fd0: ref Sys->FD)
{
	f <-= fd0;
	fd1 := <-f;
	if(fd1 == nil)
		exit;
	buf := array[Sys->ATOMICIO] of byte;
	while((n := sys->read(fd0, buf, len buf)) > 0)
		if(sys->write(fd1, buf, n) == -1)
			break;
}

runcmd(c: ref Sh->Cmd, fd0, fd1: ref Sys->FD)
{
	f := chan of ref Sys->FD;
	spawn fdproc(f, fd0);

	spawn reports->reportproc(errorc := chan of string, nil, reply := chan of ref Report);
	r := <-reply;
	spawn alphabet->eval0(
		c,
		"/fd",
		drawctxt,
		r,
		r.start("evalcmd"),
		ref (Alphabet->Value).Vf(f) :: nil,
		vc := chan of ref Alphabet->Value
	);
	r.enable();
	av: ref Alphabet->Value;
wait:
	for(;;)alt{
	av = <-vc =>
		if(av == nil){
			sys->fprint(stderr(), "rexecsrv: no value received\n");
			break;
		}
		pick v := av {
		Vf =>
			<-v.i;
			v.i <-= fd1;
		* =>
			sys->fprint(stderr(), "rexecsrv: can't happen: expression has wrong type '%c'\n",
					alphabet->v.typec());
		}
	msg := <-errorc =>
		if(msg == nil)
			break wait;
		# XXX could queue diagnostics back to caller here.
		sys->fprint(stderr(), "rexecsrv: %s\n", msg);
	}
	sys->write(fd1, array[0] of byte, 0);
}

removefid(fid: int, l: list of (int, string)): (list of (int, string), string)
{
	if(l == nil)
		return (nil, nil);
	if((hd l).t0 == fid)
		return (removefid(fid, tl l).t0, (hd l).t1);
	(rl, d) := removefid(fid, tl l);
	return (hd l :: rl, d);
}

fatal(e: string)
{
	sys->fprint(sys->fildes(2), "rexecsrv: %s\n", e);
	raise "fail:error";
}

