implement Remote, Gridmodule;
include "sys.m";
	sys: Sys;
include "draw.m";
include "sh.m";
include "alphabet/reports.m";
	reports: Reports;
	report, quit, Report: import reports;
include "alphabet/endpoints.m";
	endpoints: Endpoints;
	Endpoint: import endpoints;
include "alphabet/grid.m";
	grid: Grid;
	Value: import grid;

Remote: module {};

types(): string
{
	return "ef-as";
}

init()
{
	sys = load Sys Sys->PATH;
	reports = checkload(load Reports Reports->PATH, Reports->PATH);
	endpoints = checkload(load Endpoints Endpoints->PATH, Endpoints->PATH);
	endpoints->init();
	grid = checkload(load Grid Grid->PATH, Grid->PATH);
	grid->init();
}

run(nil: chan of string, r: ref Reports->Report,
		opts: list of (int, list of ref Grid->Value), args: list of ref Grid->Value): ref Grid->Value
{
	addr := "local";
	if(opts != nil)
		addr = (hd (hd opts).t1).s().i;
	f := (hd args).f().i;
	spawn remoteproc(ec := chan of Endpoint, f, addr, r.start("remote"));
	return ref Value.Ve(ec);
}

Noendpoint: con Endpoint(nil, nil, nil);

remoteproc(ec: chan of Endpoint, f: chan of ref Sys->FD, addr: string, errorc: chan of string)
{
	(fd1, ep) := endpoints->create(addr);
	if(fd1 == nil){
		report(errorc, "error: remote: cannot create endpoint at "+addr+": "+ep.about);
		ec <-= Noendpoint;
		<-f;
		f <-= nil;
		quit(errorc);
	}
	fd0 := <-f;
	if(fd0 != nil)
		ep.about = sys->sprint("local(%#q)", sys->fd2path(fd0));
	else
		ep.about = "local(pipe)";
	ec <-= ep;
	f <-= fd1;
	quit(errorc);
}

#	sys->pipe(p := array[2] of ref Sys->FD);
#	f <-= p[1];
#	p[1] = nil;
#	buf := array[Sys->ATOMICIO] of byte;
#	while((n := sys->read(p[0], buf, len buf)) > 0){
#		if(sys->write(fd, buf, n) == -1){
#			report(errorc, sys->sprint("write error: %r"));
#			break;
#		}
#	}exception{
#	"write on closed pipe" =>
#		report(errorc, "got write on closed pipe");
#	}
#	sys->write(fd, array[0] of byte, 0);
#	quit(errorc);
#}

checkload[T](m: T, path: string): T
{
	if(m != nil)
		return m;
	raise sys->sprint("fail:cannot load %s: %r", path);
}
