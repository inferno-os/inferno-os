implement ToFD,Mainmodule;
include "sys.m";
	sys: Sys;
include "draw.m";
include "sh.m";
include "alphabet/reports.m";
	reports: Reports;
	Report: import reports;
include "alphabet.m";
	alphabet: Alphabet;
		Value: import alphabet;

ToFD: module {};

typesig(): string
{
	return "fw";
}

init()
{
	alphabet = load Alphabet Alphabet->PATH;
	reports = load Reports Reports->PATH;
}

quit()
{
}

run(nil: ref Draw->Context, r: ref Reports->Report, nil: chan of string,
		nil: list of (int, list of ref Alphabet->Value),
		args: list of ref Alphabet->Value): ref Alphabet->Value
{
	sys = load Sys Sys->PATH;
	f := chan of ref Sys->FD;
	spawn tofdproc(f, (hd args).w().i, r.start("2fd"));
	return ref Value.Vf(f);
}

tofdproc(f, w: chan of ref Sys->FD, errorc: chan of string)
{
	fd0 := <-w;
	f <-= fd0;
	fd1 := <-f;
	if(fd1 == nil)		# asked to quit? tell w to quit too.
		w <-= nil;
	else
	if(fd0 == nil)		# no proposed fd? give 'em the one we've just got.
		w <-= fd1;
	else{				# otherwise one-way stream from w to f.
		w <-= nil;
		buf := array[Sys->ATOMICIO] of byte;
		while((n := sys->read(fd0, buf, len buf)) > 0){
			if(sys->write(fd1, buf, n) == -1){
				reports->report(errorc, sys->sprint("write error: %r"));
				break;
			}
		}
	}
	reports->quit(errorc);
}
