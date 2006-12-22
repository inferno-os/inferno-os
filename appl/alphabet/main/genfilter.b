implement Myfilter, Mainmodule;
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
include "alphabet.m";
	alphabet: Alphabet;
		Value: import alphabet;

Myfilter: module {};

typesig(): string
{
	return "ff";
}

init()
{
	sys = load Sys Sys->PATH;
	alphabet = load Alphabet Alphabet->PATH;
	reports = load Reports Reports->PATH;
	bufio = load Bufio Bufio->PATH;
}

quit()
{
}

run(drawctxt: ref Draw->Context, report: ref Reports->Report, nil: chan of string,
		nil: list of (int, list of ref Alphabet->Value),
		args: list of ref Alphabet->Value): ref Alphabet->Value
{
	f := chan of ref Sys->FD;
	spawn filterproc(drawctxt, (hd args).f().i, f, report.start("myfilter"));
	return ref Value.Vf(f);
}

filterproc(nil: ref Draw->Context, f0, f1: chan of ref Sys->FD, errorc: chan of string)
{
	(fd0, fd1) := startfilter(f0, f1, errorc);
	iob0 := bufio->fopen(fd0, Sys->OREAD);
	iob1 := bufio->fopen(fd1, Sys->OWRITE);

	# XXX your filter here!
	while((s := iob0.gets('\n')) != nil){
		d := array of byte s;
		iob1.puts("data "+string len d+"\n");
		iob1.write(d, len d);
	}exception{
	"write on closed pipe" =>
		;
	}
	iob1.flush();
	sys->fprint(fd1, "");
	reports->quit(errorc);
}

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
