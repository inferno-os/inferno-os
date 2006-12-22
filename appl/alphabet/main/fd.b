implement Fd, Mainmodule;
include "sys.m";
	sys: Sys;
include "draw.m";
include "sh.m";
include "alphabet/reports.m";
	reports: Reports;
		Report, report: import reports;
include "alphabet.m";
	alphabet: Alphabet;
		Value: import alphabet;

Fd: module {};

typesig(): string
{
	return "ws";
}

init()
{
	sys = load Sys Sys->PATH;
	alphabet = load Alphabet Alphabet->PATH;
	reports = load Reports Reports->PATH;
}

quit()
{
}

run(nil: ref Draw->Context, r: ref Reports->Report, errorc: chan of string,
		nil: list of (int, list of ref Alphabet->Value),
		args: list of ref Alphabet->Value): ref Alphabet->Value
{
	fd := sys->fildes(int (hd args).s().i);
	if(fd == nil){
		report(errorc, sys->sprint("error: no such file descriptor %q", (hd args).s().i));
		return nil;
	}
	f := chan of ref Sys->FD;
	spawn readfdproc(f, fd, r.start("stdin"));
	return ref Value.Vw(f);
}

readfdproc(f: chan of ref Sys->FD, fd0: ref Sys->FD, errorc: chan of string)
{
	f <-= fd0;
	fd1 := <-f;
	if(fd1 == nil)
		reports->quit(errorc);
	wstream(fd0, fd1, errorc);
	reports->quit(errorc);
}

wstream(fd0, fd1: ref Sys->FD, errorc: chan of string)
{
	sync := chan[2] of int;
	qc := chan of int;
	spawn stream(fd0, fd1, sync, qc, errorc);
	spawn stream(fd1, fd0, sync, qc, errorc);
	<-qc;
	kill(<-sync);
	kill(<-sync);
}

stream(fd0, fd1: ref Sys->FD, sync, qc: chan of int, errorc: chan of string)
{
	sync <-= sys->pctl(0, nil);
	buf := array[Sys->ATOMICIO] of byte;
	while((n := sys->read(fd0, buf, len buf)) > 0){
		if(sys->write(fd1, buf, n) == -1){
			report(errorc, sys->sprint("write error: %r"));
			break;
		}
	}
	qc <-= 1;
	exit;
}

kill(pid: int)
{
	sys->fprint(sys->open("#p/"+string pid+"/ctl", Sys->OWRITE), "kill");
}
