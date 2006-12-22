implement Filter, Mainmodule;
include "sys.m";
	sys: Sys;
include "draw.m";
include "sh.m";
	sh: Sh;
	Context: import sh;
include "bufio.m";
	bufio: Bufio;
	Iobuf: import bufio;
include "alphabet/reports.m";
	reports: Reports;
		Report, report: import reports;
include "alphabet.m";
	alphabet: Alphabet;
		Value: import alphabet;

Filter: module {};

typesig(): string
{
	return "ffcs*";		# XXX option to suppress stderr?
}

init()
{
	sys = load Sys Sys->PATH;
	alphabet = load Alphabet Alphabet->PATH;
	reports = load Reports Reports->PATH;
	bufio = load Bufio Bufio->PATH;
	sh = load Sh Sh->PATH;
	sh->initialise();
}

quit()
{
}

run(drawctxt: ref Draw->Context, report: ref Reports->Report, nil: chan of string,
		nil: list of (int, list of ref Value),
		args: list of ref Value): ref Value
{
	f := chan of ref Sys->FD;
	a: list of ref Sh->Listnode;
	for(al := tl tl args; al != nil; al = tl al)
		a = ref Sh->Listnode(nil, (hd al).s().i) :: a;
	spawn filterproc(drawctxt, (hd args).f().i, f, (hd tl args).c().i, rev(a), report.start("filter"));
	return ref Value.Vf(f);
}

filterproc(drawctxt: ref Draw->Context,
	f0,
	f1: chan of ref Sys->FD,
	c: ref Sh->Cmd,
	args: list of ref Sh->Listnode,
	errorc: chan of string)
{
	(fd0, fd1) := startfilter(f0, f1, errorc);
	sys->pipe(p := array[2] of ref Sys->FD);
	spawn stderrproc(p[0], errorc);
	p[0] = nil;

	# i hate this stuff.
	sys->pctl(Sys->FORKFD, nil);
	sys->dup(fd0.fd, 0);
	sys->dup(fd1.fd, 1);
	sys->dup(p[1].fd, 2);
	fd0 = fd1 = nil;
	p = nil;
	sys->pctl(Sys->NEWFD, 0::1::2::nil);
	Context.new(drawctxt).run(ref Sh->Listnode(c, nil)::args, 0);
	sys->fprint(sys->fildes(2), "");
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

stderrproc(fd: ref Sys->FD, errorc: chan of string)
{
	iob := bufio->fopen(fd, Sys->OREAD);
	while((s := iob.gets('\n')) != nil)
		if(len s > 1)
			errorc <-= s[0:len s - 1];
	errorc <-= nil;
}

rev[T](l: list of T): list of T
{
	r: list of T;
	for(; l != nil; l = tl l)
		r = hd l :: r;
	return r;
}