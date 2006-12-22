implement Mainmodule;
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

typesig(): string
{
	return "ff*";
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

run(nil: ref Draw->Context, r: ref Reports->Report, nil: chan of string,
		nil: list of (int, list of ref Alphabet->Value),
		args: list of ref Alphabet->Value): ref Alphabet->Value
{
	fds: list of chan of ref Sys->FD;
	for(; args != nil; args = tl args)
		fds = (hd args).f().i :: fds;
	f := chan of ref Sys->FD;
	spawn catproc(f, rev(fds), r.start("print"));
	return ref Value.Vf(f);
}

catproc(f: chan of ref Sys->FD, fds: list of chan of ref Sys->FD, reportc: chan of string)
{
	f <-= nil;
	if((fd1 := <-f) == nil){
		for(; fds != nil; fds = tl fds){
			<-hd fds;
			hd fds <-= nil;
		}
		reports->quit(reportc);
	}
	buf := array[8192] of byte;
	for(; fds != nil; fds = tl fds){
		fd0 := <-hd fds;
		if(fd0 == nil){
			p := array[2] of ref Sys->FD;
			sys->pipe(p);
			fd0 = p[0];
			hd fds <-= p[1];
		}else
			hd fds <-= nil;
		while((n := sys->read(fd0, buf, len buf)) > 0){
			sys->write(fd1, buf, n);
		}exception{
		"write on closed pipe" =>
			;
		}
	}
	sys->write(fd1, array[0] of byte, 0);
	reports->quit(reportc);
}

rev[T](l: list of T): list of T
{
	r: list of T;
	for(; l != nil; l = tl l)
		r = hd l :: r;
	return r;
}