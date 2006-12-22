implement Rexec, Gridmodule;
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

Rexec: module {};

types(): string
{
	return "eesc-A";
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
		opts: list of (int, list of ref Grid->Value), args: list of ref Grid->Value): ref Grid->Value
{
	ec0 := (hd args).e().i;
	addr := (hd tl args).s().i;
	cmd := (hd tl tl args).c().i;

	spawn rexecproc(sync := chan of int, addr, ec0, cmd, r.start("rexec"), opts != nil, ec1 := chan of Endpoint);
	<-sync;
	return ref Value.Ve(ec1);
}

rexecproc(sync: chan of int,
		addr: string,
		ec0: chan of Endpoint,
		cmd: ref Sh->Cmd,
		errorc: chan of string,
		noauth: int,
		ec1: chan of Endpoint
	)
{
	sys->pctl(Sys->FORKNS, nil);
	sync <-= 1;

	ep0 := <-ec0;
	if(ep0.addr == nil){
		ec1 <-= ep0;
		quit(errorc);
	}

	(ep1, err) := exec(addr, ep0, cmd, noauth);
	if(err != nil){
		endpoints->open(nil, ep0);	# discard 
		report(errorc, err);
	}
	ec1 <-= ep1;
	quit(errorc);
}

Nope: con Endpoint(nil, nil, nil);

exec(addr: string, ep0: Endpoint, cmd: ref Sh->Cmd, noauth: int): (Endpoint, string)
{
	args := addr::"/n/remote"::nil;
	if(noauth)
		args = "-A"::args;
	if((e := sh->run(nil, "mount"::args)) != nil)
		return (Nope, sys->sprint("cannot mount rexec at %q: %s", addr, e));

	fd := sys->open("/n/remote/exec", Sys->ORDWR);
	if(fd == nil)
		return (Nope, sys->sprint("cannot open exec at %q: %r", addr));
	if(sys->fprint(fd, "%q %q", ep0.text(), sh->cmd2string(cmd)) == -1)
		return (Nope, sys->sprint("exec write failed: %r"));
	buf := array[1024] of byte;
	n := sys->read(fd, buf, len buf);
	if(n < 0)
		return (Nope, sys->sprint("error reading endpoint: %r"));
	if(n == 0)
		return (Nope, "eof reading endpoint");
	s := string buf[0:n];
	ep1 := Endpoint.mk(s);
	if(ep1.addr == nil)
		return (Nope, sys->sprint("bad endpoint %#q: %s", s, ep1.about));
	ep1.about = sys->sprint("%s | rexec %q %s", ep0.about, addr, sh->cmd2string(cmd));
	return (ep1, nil);
}

checkload[T](m: T, path: string): T
{
	if(m != nil)
		return m;
	raise sys->sprint("fail:cannot load %s: %r", path);
}
