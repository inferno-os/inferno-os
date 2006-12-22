implement Farm, Gridmodule;
include "sys.m";
	sys: Sys;
include "draw.m";
include "sh.m";
	sh: Sh;
include "string.m";
	str: String;
include "alphabet/reports.m";
	reports: Reports;
	report, Report, quit: import reports;
include "alphabet/endpoints.m";
	endpoints: Endpoints;
	Endpoint: import endpoints;
include "alphabet/grid.m";
	grid: Grid;
	Value: import grid;

Farm: module {};

types(): string
{
	return "eesss*-A-k-a-v-bs";
}

init()
{
	sys = load Sys Sys->PATH;
	reports = checkload(load Reports Reports->PATH, Reports->PATH);
	endpoints = checkload(load Endpoints Endpoints->PATH, Endpoints->PATH);
	endpoints->init();
	grid = checkload(load Grid Grid->PATH, Grid->PATH);
	grid->init();
	sh = checkload(load Sh Sh->PATH, Sh->PATH);
	sh->initialise();
	str = checkload(load String String->PATH, String->PATH);
}

run(nil: chan of string, r: ref Reports->Report,
		opt: list of (int, list of ref Grid->Value), args: list of ref Grid->Value): ref Grid->Value
{
	ec0 := (hd args).e().i;
	addr := (hd tl args).s().i;
	job, opts: string;
	noauth := 0;
	for(; opt != nil; opt = tl opt){
		c := (hd opt).t0;
		case (hd opt).t0 {
		'A' => 
			noauth = 1;
		'b' =>
			opts += " -b "+(hd (hd opt).t1).s().i;
		* =>
			opts += sys->sprint(" -%c", (hd opt).t0);
		}
	}
	for(args = tl tl args; args != nil; args = tl args)
		job += sys->sprint(" %q", (hd args).s().i);

	spawn farmproc(sync := chan of int, addr, ec0, opts, job, noauth, r.start("farm"), ec := chan of Endpoint);
	<-sync;
	return ref Value.Ve(ec);
}

farmproc(sync: chan of int,
		addr: string,
		ec0: chan of Endpoint,
		opts: string,
		job: string,
		noauth: int,
		errorc: chan of string,
		ec1: chan of Endpoint)
{
	sys->pctl(Sys->FORKNS, nil);
	sync <-= 1;
	ep0 := <-ec0;
	if(ep0.addr == nil){
		ec1 <-= ep0;
		quit(errorc);
	}
	(v, e) := farm(addr, ep0, opts, job, noauth, errorc);
	if(e != nil){
		endpoints->open(nil, ep0);
		report(errorc, "error: "+e);
	}
	ec1 <-= v;
	quit(errorc);
}

Nope: con Endpoint(nil, nil, nil);

farm(addr: string,
	ep0: Endpoint,
	opts: string,
	job: string,
	noauth: int,
	errorc: chan of string): (Endpoint, string)
{
	args := addr::"/n/remote"::nil;
	if(noauth)
		args = "-A"::args;
	if((e := sh->run(nil, "mount"::args)) != nil)
		return (Nope, sys->sprint("cannot mount scheduler at %q: %s, args %s", addr, e, str->quoted(args)));

	fd := sys->open("/n/remote/admin/clone", Sys->ORDWR);
	if(fd == nil)
		return (Nope, sys->sprint("cannot open clone: %r"));
	if((d := gets(fd)) == nil)
		return (Nope, "read clone failed");
	dir := "/n/remote/admin/"+d;
	if(sys->fprint(fd, "load workflow%s %q %s", opts, ep0.text(), job) == -1)
		return (Nope, sys->sprint("job load failed: %r"));
	if(sys->fprint(fd, "start") == -1)
		return (Nope, sys->sprint("job start failed: %r"));
	dfd := sys->open(dir+"/data", Sys->OREAD);
	if(dfd == nil){
		sys->fprint(fd, "delete");
		return (Nope, sys->sprint("cannot open job data file: %r"));
	}
	s := gets(dfd);
	ep1 := Endpoint.mk(s);
	if(ep1.addr == nil)
		return (Nope, sys->sprint("bad remote endpoint %q", s));
	report(errorc, sys->sprint("job %s started, id %s", d, gets(sys->open(dir+"/id", Sys->OREAD))));
	# XXX how is the job going to be deleted eventually
	ep1.about = sys->sprint("%s | farm%s %s%s", ep0.about, opts, addr, job);
	return (ep1, nil);
}

checkload[T](m: T, path: string): T
{
	if(m != nil)
		return m;
	raise sys->sprint("fail:cannot load %s: %r", path);
}

gets(fd: ref Sys->FD): string
{
	d := array[8192] of byte;
	n := sys->read(fd, d, len d);
	if(n <= 0)
		return nil;
	return string d[0:n];
}
