implement Tkcmd;

include "sys.m";
	sys: Sys;
	stderr: ref Sys->FD;
include "draw.m";
	draw: Draw;
	Display, Image, Point: import draw;
include "tk.m";
	tk: Tk;
include "tkclient.m";
	tkclient: Tkclient;
include "bufio.m";
include "arg.m";

Tkcmd : module {
	init:	fn(ctxt: ref Draw->Context, argv: list of string);
};

usage()
{
	sys->print("usage: tkcmd [-iu] [toplevelarg]\n");
	raise "fail:usage";
}

badmodule(m: string)
{
		sys->fprint(stderr, "tkcmd: cannot load %s: %r\n", m);
		raise "fail:bad module";
}

init(ctxt: ref Draw->Context, argv: list of string)
{
	sys  = load Sys  Sys->PATH;
	stderr = sys->fildes(2);
	draw = load Draw Draw->PATH;
	tk = load Tk   Tk->PATH;
	if (tk == nil)
		badmodule(Tk->PATH);
	tkclient = load Tkclient Tkclient->PATH;
	if (tkclient==nil)
		badmodule(Tkclient->PATH);
	arg := load Arg Arg->PATH;
	if (arg == nil)
		badmodule(Arg->PATH);

	arg->init(argv);
	update := 1;
	interactive := isconsole(sys->fildes(0));
	while ((opt := arg->opt()) != 0) {
		case opt {
		'i' =>
			interactive = 1;
		'u' =>
			update = 0;
		* =>
			usage();
		}
	}
	argv = arg->argv();
	arg = nil;
	tkarg := "";
	if (argv != nil) {
		if (tl argv != nil)
			usage();
		tkarg = hd argv;
	}
	
	sys->pctl(Sys->NEWPGRP, nil);
	tkclient->init();
	shellit(ctxt, tkarg, interactive, update);
}

isconsole(fd: ref Sys->FD): int
{
	(ok1, d1) := sys->fstat(fd);
	(ok2, d2) := sys->stat("/dev/cons");
	if (ok1 < 0 || ok2 < 0)
		return 0;
	return d1.dtype == d2.dtype && d1.qid.path == d2.qid.path;
}

shellit(ctxt: ref Draw->Context, arg: string, interactive, update: int)
{
	(Wwsh, winctl) := tkclient->toplevel(ctxt, arg, "Tk", Tkclient->Appl);
	tkclient->onscreen(Wwsh, nil);
	tkclient->startinput(Wwsh, "ptr" :: "kbd" :: nil);
	wm := Wwsh.ctxt;
	if(update)
		tk->cmd(Wwsh, "update");
	ps1 := "";
	ps2 := "";
	if (!interactive)
		ps1 = ps2 = "";

	lines := chan of string;
	sync := chan of int;
	spawn grab_lines(ps1, ps2, lines, sync);
	output := chan of string;
	tk->namechan(Wwsh, output, "stdout");
	pid := <-sync;
Loop:
	for(;;) alt {
	c := <-wm.kbd =>
		tk->keyboard(Wwsh, c);
	m := <-wm.ptr =>
		tk->pointer(Wwsh, *m);
	c := <-wm.ctl or
	c = <-Wwsh.wreq =>
		tkclient->wmctl(Wwsh, c);
	line := <-lines =>
		if (line == nil)
			break Loop;
		if (line[0] == '#')
			break;
		line = line[0:len line - 1];
		result := tk->cmd(Wwsh, line);
		if (result != nil)
			sys->print("#%s\n", result);
		if (update)
			tk->cmd(Wwsh, "update");
		sys->print("%s", ps1);
	menu := <-winctl =>
		tkclient->wmctl(Wwsh, menu);
	s := <-output =>
		sys->print("#<stdout>%s\n", s);
		sys->print("%s", ps1);
	}
}

grab_lines(new_inp, unfin: string, lines: chan of string, sync: chan of int)
{
	sync <-= sys->pctl(0, nil);
	{
		bufmod := load Bufio Bufio->PATH;
		Iobuf:	import bufmod;
		if (bufmod == nil) {
			lines <-= nil;
			return;
		}
		sys->print("%s", new_inp);
		iob := bufmod->fopen(sys->fildes(0),bufmod->OREAD);
		if (iob==nil){
			sys->fprint(stderr, "tkcmd: cannot open stdin for reading.\n");
			lines <-= nil;
			return;
		}
		line := "";
		while((input := iob.gets('\n')) != nil) {
			line+=input;
			if (!finished(line,0))
				sys->print("%s", unfin);
			else{
				lines <-= line;
				line=nil;
			}
		}
		lines <-= nil;
	}exception e{
	"*" =>
		sys->fprint(stderr, "tkcmd: fail: %s\n", e);
		lines <-= nil;
	}
}

# returns 1 if the line has matching braces, brackets and 
# double-quotes and does not end in "\\\n"
finished(s : string, termchar : int) : int {
	cb:=0;
	dq:=0;
	sb:=0;
	if (s==nil) return 1;
	if (termchar=='}') cb++;
	if (termchar==']') sb++;
	if (len s > 1 && s[len s -2]=='\\')
		return 0;
	if (s[0]=='{') cb++;
	if (s[0]=='}' && cb>0) cb--;
	if (s[0]=='[') sb++;
	if (s[0]==']' && sb>0) sb--;
	if (s[0]=='"') dq=1-dq;
	for(i:=1;i<len s;i++){
		if (s[i]=='{' && s[i-1]!='\\') cb++;
		if (s[i]=='}' && s[i-1]!='\\' && cb>0) cb--;
		if (s[i]=='[' && s[i-1]!='\\') sb++;
		if (s[i]==']' && s[i-1]!='\\' && sb>0) sb--;
		if (s[i]=='"' && s[i-1]!='\\') dq=1-dq;
	}
	return (cb==0 && sb==0 && dq==0);
}
