implement Mount,Mainmodule;
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

Mount: module {};

typesig(): string
{
	return "rws-a-b-c-xs";
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

After, Before, Create: con 1<<iota;

run(nil: ref Draw->Context, report: ref Reports->Report, nil: chan of string,
		opts: list of (int, list of ref Alphabet->Value),
		args: list of ref Alphabet->Value): ref Alphabet->Value
{
	flag := Sys->MREPL;
	aname := "";
	for(; opts != nil; opts = tl opts){
		case (hd opts).t0 {
		'a' =>
			flag = After & (flag&Sys->MCREATE);
		'b' =>
			flag = Before & (flag&Sys->MCREATE);
		'c' =>
			flag |= Create;
		'x' =>
			aname = (hd (hd opts).t1).s().i;
		}
	}
	r := chan of string;
	spawn mountproc(r, (hd args).w().i, (hd tl args).s().i, aname, flag, report.start("mount"));
	return ref Value.Vr(r);
}

mountproc(r: chan of string, w: chan of ref Sys->FD, dir, aname: string, flag: int, errorc: chan of string)
{
	if(<-r != nil){
		errorc <-= nil;
		<-w;
		w <-= nil;
		exit;
	}
	fd := <-w;
	if(fd == nil){
		sys->pipe(p := array[2] of ref Sys->FD);
		w <-= p[0];
		fd = p[1];
	}else
		w <-= nil;
	if(sys->mount(fd, nil, dir, flag, aname) == -1){
		e := sys->sprint("mount error on %#q: %r", dir);
		report(errorc, e);
		r <-= e;
		exit;
	}

	errorc <-= nil;
	r <-= nil;
}
