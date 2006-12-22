implement Local,Gridmodule;
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

Local: module {};
types(): string
{
	return "fe-v";
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

	spawn localproc((hd args).e().i, f := chan of ref Sys->FD, opts!=nil, r.start("local"));
	return ref Value.Vf(f);
}

localproc(ec: chan of Endpoint, f: chan of ref Sys->FD, verbose: int, errorc: chan of string)
{
	ep := <-ec;
	if(ep.addr == nil){
		# error should already have been printed (XXX is that the right way to do it?)
		f <-= nil;
		<-f;
		quit(errorc);
	}
	if(verbose)
		report(errorc, sys->sprint("endpoint %q at %q: %s", ep.id, ep.addr, ep.about));
	(fd0, err) := endpoints->open(nil, ep);
	if(fd0 == nil){
		report(errorc, sys->sprint("error: local: cannot open endpoint (%q %q): %s", ep.addr, ep.id, err));
		f <-= nil;
		<-f;
		quit(errorc);
	}
	f <-= fd0;
	fd1 := <-f;
	if(fd1 == nil)
		quit(errorc);
	
	buf := array[Sys->ATOMICIO] of byte;
	{
		while((n := sys->read(fd0, buf, len buf)) > 0){
#sys->print("local read %d bytes\n", n);
			sys->write(fd1, buf, n);
		}
#sys->print("local eof %d\n", n);
		sys->write(fd1, array[0] of byte, 0);
		if(n < 0)
			report(errorc, sys->sprint("read error: %r"));
	} exception e {
	"write on closed pipe" =>
		report(errorc, "write on closed pipe");
		;
	}
	quit(errorc);
}

checkload[T](m: T, path: string): T
{
	if(m != nil)
		return m;
	raise sys->sprint("fail:cannot load %s: %r", path);
}
