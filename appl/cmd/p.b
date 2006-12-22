implement P;
# Original by Steve Arons, based on Plan 9 p

include "sys.m"; 
	sys: Sys;
	FD:	import Sys;
include "draw.m";
include "string.m";
	str: String;
include "bufio.m";
	bufio: Bufio;
	Iobuf: import bufio;
include "sh.m";

stderr: ref FD;
outb, cons: ref Iobuf;
drawctxt: ref Draw->Context;

nlines := 22;	# 1/3rd 66-line nroff page (!)
progname := "p";

P: module
{
	init:  fn(ctxt:  ref Draw->Context, argv:  list of string);
};

usage()
{
	sys->fprint(stderr, "Usage: p [-number] [file...]\n");
	raise "fail:usage";
}

init(ctxt: ref Draw->Context, argv:  list of string)
{
	sys = load Sys Sys->PATH;
	bufio = load Bufio Bufio->PATH;
	if(bufio == nil)
		nomod(Bufio->PATH);
	str = load String String->PATH;
	if(str == nil)
		nomod(String->PATH);
	sys->pctl(Sys->FORKFD, nil);
	drawctxt = ctxt;

	stderr = sys->fildes(2);

	if((stdout := sys->fildes(1)) != nil)
		outb = bufio->fopen(stdout, bufio->OWRITE);
	if(outb == nil){
		sys->fprint(stderr, "p: can't open stdout: %r\n");
		raise "fail:stdout";
	}
	cons = bufio->open("/dev/cons", bufio->OREAD);
	if(cons == nil){
		sys->fprint(stderr, "p: can't open /dev/cons: %r\n");
		raise "fail:cons";
	}

	if(argv != nil){
		progname = hd argv;
		argv = tl argv;
		if(argv != nil){
			s := hd argv;
			if(len s > 1 && s[0] == '-'){
				(x, y) := str->toint(s[1:],10);
				if(y == "" && x > 0)
					nlines = x;
				else
					usage();
				argv = tl argv;
			}
		}
	}
	if(argv == nil)
		argv = "-" :: nil;
	for(; argv != nil; argv = tl argv){
		file := hd argv;
		fd: ref Sys->FD;
		if(file == "-"){
			file = "stdin";
			fd = sys->fildes(0);
		}else
			fd = sys->open(file, Sys->OREAD);
		if(fd == nil){
			sys->fprint(stderr, "%s: can't open %s: %r\n", progname, file);
			continue;
		}
		page(fd);
		fd = nil;
	}
}

nomod(m: string)
{
	sys->fprint(sys->fildes(2), "%s: can't load %s: %r\n", progname, m);
	raise "fail:load";
}

page(fd: ref Sys->FD)
{
	inb := bufio->fopen(fd, bufio->OREAD);
	nl := nlines;
	while((line := inb.gets('\n')) != nil){
		outb.puts(line);        
		if(--nl == 0){
			outb.flush();
			nl = nlines;
			pause();
		}
	}
	outb.flush();   
}

pause()
{
	for(;;){
		cmdline := cons.gets('\n');
		if(cmdline == nil || cmdline[0] == 'q') # catch ^d
			exit;
		else if(cmdline[0] == '!') {
			done := chan of int;
			spawn command(cmdline[1:], done);
			<-done;
		}else
			break;
	}
}

command(cmdline: string, done: chan of int)
{
	sh := load Sh Sh->PATH;
	if(sh == nil) {
		sys->fprint(stderr, "%s: can't load %s: %r\n", progname, Sh->PATH);
		done <-= 0;
		return;
	}
	sys->pctl(Sys->FORKFD, nil);
	sys->dup(cons.fd.fd, 0);
	sh->system(drawctxt, cmdline);
	done <-= 1;
}
