implement Command;

include "sys.m";
	sys: Sys;
	print, fprint, FD: import sys;
	stderr: ref FD;

include "draw.m";

include "debug.m";
	debug: Debug;
	Prog, Module, Exp: import debug;

include "arg.m";
include "bufio.m";
	bufio: Bufio;
	Iobuf: import bufio;

include "env.m";
	env: Env;

include "string.m";
	str: String;

include "dis.m";
	dism: Dis;

Command: module
{
	init: fn(ctxt: ref Draw->Context, argv: list of string);
};

usage()
{
	sys->fprint(stderr, "usage: stack [-v] pid\n");
	raise "fail:usage";
}

badmodule(p: string)
{
	sys->fprint(stderr, "stack: cannot load %s: %r\n", p);
	raise "fail:bad module";
}

sbldirs: list of (string, string);

init(nil: ref Draw->Context, argv: list of string)
{

	sys = load Sys Sys->PATH;
	stderr = sys->fildes(2);
	arg := load Arg Arg->PATH;
	if (arg == nil)
		badmodule(Arg->PATH);
	bufio = load Bufio Bufio->PATH;
	if (bufio == nil)
		badmodule(Bufio->PATH);
	debug = load Debug Debug->PATH;
	if(debug == nil)
		badmodule(Debug->PATH);
	env = load Env Env->PATH;
	if (env != nil) {
		str = load String String->PATH;
		if (str == nil)
			badmodule(String->PATH);
	}
	bout := bufio->fopen(sys->fildes(1), Sys->OWRITE);

	arg->init(argv);
	verbose := 0;
	while ((opt := arg->opt()) != 0) {
		case opt {
		'v' =>
			verbose = 1;
		'p' =>
			dispath := arg->arg();
			sblpath := arg->arg();
			if (dispath == nil || sblpath == nil)
				usage();
			sbldirs = (addslash(dispath), addslash(sblpath)) :: sbldirs;
		* =>
			usage();
		}
	}
	if (env != nil && (pathl := env->getenv("sblpath")) != nil) {
		toks := str->unquoted(pathl);
		for (; toks != nil && tl toks != nil; toks = tl tl toks)
			sbldirs = (addslash(hd toks), addslash(hd tl toks)) :: sbldirs;
	}
	t: list of (string, string);
	for (; sbldirs != nil; sbldirs = tl sbldirs)
		t = hd sbldirs :: t;
	sbldirs = t;

	argv = arg->argv();
	if(argv == nil)
		usage();

	debug->init();

	(p, err) := debug->prog(int hd argv);
	if(err != nil){
		fprint(stderr, "stack: %s\n", err);
		return;
	}
	stk: array of ref Exp;
	(stk, err) = p.stack();

	if(err != nil){
		fprint(stderr, "stack: %s\n", err);
		return;
	}

	for(i := 0; i < len stk; i++){
		stdsym(stk[i].m);
		stk[i].m.stdsym();
		stk[i].findsym();
		bout.puts(stk[i].name + "(");
		vs := stk[i].expand();
		if(verbose && vs != nil){
			for(j := 0; j < len vs; j++){
				if(vs[j].name == "args"){
					d := vs[j].expand();
					s := "";
					for(j = 0; j < len d; j++) {
						bout.puts(sys->sprint("%s%s=%s", s, d[j].name, d[j].val().t0));
						s = ", ";
					}
					break;
				}
			}
		}
		bout.puts(sys->sprint(") %s\n", stk[i].srcstr()));
		if(verbose && vs != nil){
			for(j := 0; j < len vs; j++){
				if(vs[j].name == "locals"){
					d := vs[j].expand();
					for(j = 0; j < len d; j++)
						bout.puts("\t" + d[j].name + "=" + d[j].val().t0 + "\n");
					break;
				}
			}
		}
	}
	bout.flush();
}

stdsym(m: ref Module)
{
	dis := m.dis();
	if(dism == nil){
		dism = load Dis Dis->PATH;
		if(dism != nil)
			dism->init();
	}
	if(dism != nil && (sp := dism->src(dis)) != nil){
		sp = sp[0: len sp - 1] + "sbl";
		(sym, nil) := debug->sym(sp);
		if (sym != nil) {
			m.addsym(sym);
			return;
		}
	}
	for (sbl := sbldirs; sbl != nil; sbl = tl sbl) {
		(dispath, sblpath) := hd sbl;
		if (len dis > len dispath && dis[0:len dispath] == dispath) {
			sblpath = sblpath + dis[len dispath:];
			if (len sblpath > 4 && sblpath[len sblpath - 4:] == ".dis")
				sblpath = sblpath[0:len sblpath - 4] + ".sbl";
			(sym, nil) := debug->sym(sblpath);
			if (sym != nil) {
				m.addsym(sym);
				return;
			}
		}
	}
}
			
addslash(p: string): string
{
	if (p != nil && p[len p - 1] != '/')
		p[len p] = '/';
	return p;
}
