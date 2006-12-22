implement Line2rec, Gridmodule;
include "sys.m";
	sys: Sys;
include "draw.m";
include "sh.m";
include "bufio.m";
	bufio: Bufio;
	Iobuf: import bufio;
include "alphabet/reports.m";
	reports: Reports;
		Report, report: import reports;
include "alphabet/endpoints.m";
include "alphabet/grid.m";
	grid: Grid;
	Value: import grid;

Line2rec: module {};

types(): string
{
	return "bf";
}

init()
{
	sys = load Sys Sys->PATH;
	grid = load Grid Grid->PATH;
	reports = load Reports Reports->PATH;
	bufio = load Bufio Bufio->PATH;
}

quit()
{
}

run(nil: chan of string, r: ref Report,
		nil: list of (int, list of ref Value), args: list of ref Value): ref Value
{
	f := chan of ref Sys->FD;
	spawn line2recproc((hd args).f().i, f, r.start("line2rec"));
	return ref Value.Vb(f);
}

line2recproc(
	f0,
	f1: chan of ref Sys->FD,
	errorc: chan of string)
{
	(fd0, fd1) := startfilter(f0, f1, errorc);
	iob0 := bufio->fopen(fd0, Sys->OREAD);
	iob1 := bufio->fopen(fd1, Sys->OWRITE);
	{
		while((s := iob0.gets('\n')) != nil){
			d := array of byte s;
			if(iob1.puts("data "+string len d) < 0)
				break;
			if(iob1.write(d, len d) != len d)
				break;
		}
		iob1.flush();
		sys->fprint(fd1, "");
	}exception{
	"write on closed pipe" =>
		;
	}
	reports->quit(errorc);
}

# read side (when it's an argument):
# 	read proposed new fd
# 	write actual fd for them to write to (creating pipe in necessary)
# 
# write side (when you're returning it):
# 	write a proposed new fd (or nil if no suggestion)
# 	read actual fd for writing
startfilter(f0, f1: chan of ref Sys->FD, errorc: chan of string): (ref Sys->FD, ref Sys->FD)
{
	f1 <-= nil;
	if((fd1 := <-f1) == nil){
		<-f0;
		f0 <-= nil;
		reports->quit(errorc);
	}
	if((fd0 := <-f0) == nil){
		sys->pipe(p := array[2] of ref Sys->FD);
		f0 <-= p[1];
		fd0 = p[0];
	}else
		f0 <-= nil;
	return (fd0, fd1);
}
